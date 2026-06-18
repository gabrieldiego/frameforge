`timescale 1ns/1ps

module ff_axi4_frame_reader #(
  parameter int AXI_ADDR_BITS = 32,
  parameter int AXI_DATA_BITS = 128,
  parameter int SAMPLE_BITS = 8,
  parameter int CTU_SIZE = 64,
  // 0: VVC fixed-TU scan order, 1: raster 8x8 block order.
  parameter bit RASTER_BLOCK_ORDER = 1'b0
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       start,
  input  logic [15:0]                visible_width,
  input  logic [15:0]                visible_height,
  input  logic [1:0]                 chroma_format_idc,
  input  logic [15:0]                segment_origin_x,
  input  logic [15:0]                segment_origin_y,
  input  logic [15:0]                segment_width,
  input  logic [15:0]                segment_height,
  input  logic                       stream_last_on_segment_end,
  input  logic                       frame_last_segment,
  input  logic [AXI_ADDR_BITS-1:0]   src_y_base,
  input  logic [AXI_ADDR_BITS-1:0]   src_u_base,
  input  logic [AXI_ADDR_BITS-1:0]   src_v_base,
  input  logic [AXI_ADDR_BITS-1:0]   src_frame_offset,
  input  logic [31:0]                src_y_stride,
  input  logic [31:0]                src_u_stride,
  input  logic [31:0]                src_v_stride,

  output logic                       m_axi_arvalid,
  input  logic                       m_axi_arready,
  output logic [AXI_ADDR_BITS-1:0]   m_axi_araddr,
  output logic [7:0]                 m_axi_arlen,
  output logic [2:0]                 m_axi_arsize,
  output logic [1:0]                 m_axi_arburst,
  input  logic                       m_axi_rvalid,
  output logic                       m_axi_rready,
  input  logic [AXI_DATA_BITS-1:0]   m_axi_rdata,
  input  logic [1:0]                 m_axi_rresp,
  input  logic                       m_axi_rlast,

  output logic                       sample_valid,
  input  logic                       sample_ready,
  output logic [SAMPLE_BITS-1:0]     sample_data,
  output logic                       sample_last,
  output logic                       busy,
  output logic                       done,
  output logic                       error
);
  localparam int SAMPLE_BYTES = (SAMPLE_BITS + 7) / 8;
  localparam int SAMPLE_BYTE_SHIFT =
    (SAMPLE_BYTES <= 1) ? 0 :
    (SAMPLE_BYTES <= 2) ? 1 :
    (SAMPLE_BYTES <= 4) ? 2 :
    3;
  localparam logic [2:0] SAMPLE_AXI_SIZE = SAMPLE_BYTE_SHIFT;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_SKIP,
    ST_ADDR,
    ST_WAIT_R,
    ST_PAD,
    ST_VALID
  } state_t;

  state_t state_q;
  logic [5:0] scan_q;
  logic [2:0] raster_col_q;
  logic [2:0] raster_row_q;
  logic [6:0] leaf_count_q;
  logic [1:0] component_q;
  logic [5:0] sample_q;
  logic [2:0] vvc_col_w;
  logic [2:0] vvc_row_w;
  logic [2:0] leaf_col_w;
  logic [2:0] leaf_row_w;
  logic [3:0] active_cols_w;
  logic [3:0] active_rows_w;
  logic [6:0] active_leaf_count_w;
  logic leaf_active_w;
  logic component_last_w;
  logic sample_last_in_component_w;
  logic block_last_w;
  logic segment_last_w;
  logic output_last_w;
  logic [5:0] component_sample_last_w;
  logic [15:0] local_x_w;
  logic [15:0] local_y_w;
  logic [15:0] sample_x_w;
  logic [15:0] sample_y_w;
  logic [15:0] plane_x_w;
  logic [15:0] plane_y_w;
  logic [31:0] plane_stride_w;
  logic [AXI_ADDR_BITS-1:0] plane_base_w;
  logic [AXI_ADDR_BITS-1:0] plane_offset_w;
  logic [AXI_ADDR_BITS-1:0] row_offset_w;
  logic [AXI_ADDR_BITS-1:0] col_offset_w;
  logic [SAMPLE_BITS-1:0] pad_sample_w;
  logic in_visible_w;

  assign busy = (state_q != ST_IDLE);
  assign m_axi_arlen = 8'd0;
  assign m_axi_arsize = SAMPLE_AXI_SIZE;
  assign m_axi_arburst = 2'b01;

  assign active_cols_w = (segment_width + 16'd7) >> 3;
  assign active_rows_w = (segment_height + 16'd7) >> 3;
  always_comb begin
    case (active_rows_w)
      4'd0: active_leaf_count_w = 7'd0;
      4'd1: active_leaf_count_w = {3'd0, active_cols_w};
      4'd2: active_leaf_count_w = {2'd0, active_cols_w, 1'b0};
      4'd3: active_leaf_count_w = {2'd0, active_cols_w, 1'b0} + {3'd0, active_cols_w};
      4'd4: active_leaf_count_w = {1'd0, active_cols_w, 2'b00};
      4'd5: active_leaf_count_w = {1'd0, active_cols_w, 2'b00} + {3'd0, active_cols_w};
      4'd6: active_leaf_count_w = {1'd0, active_cols_w, 2'b00} + {2'd0, active_cols_w, 1'b0};
      4'd7: active_leaf_count_w = {active_cols_w, 3'b000} - {3'd0, active_cols_w};
      default: active_leaf_count_w = {active_cols_w, 3'b000};
    endcase
  end
  // VVC fixed 8x8 leaf order is a Morton/Z scan. Use direct bit selects so
  // each concatenation operand is exactly one bit; shifted masks would widen
  // in Verilog and can silently drop the upper row bits.
  assign vvc_col_w = {scan_q[4], scan_q[2], scan_q[0]};
  assign vvc_row_w = {scan_q[5], scan_q[3], scan_q[1]};
  assign leaf_col_w = RASTER_BLOCK_ORDER ? raster_col_q : vvc_col_w;
  assign leaf_row_w = RASTER_BLOCK_ORDER ? raster_row_q : vvc_row_w;
  assign leaf_active_w =
    ({1'b0, leaf_col_w} < active_cols_w) &&
    ({1'b0, leaf_row_w} < active_rows_w);

  assign component_sample_last_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ? 6'd15 : 6'd63;
  assign sample_last_in_component_w = (sample_q == component_sample_last_w);
  assign component_last_w = (component_q == 2'd2) && sample_last_in_component_w;
  assign block_last_w =
    component_last_w &&
    (leaf_count_q == (active_leaf_count_w - 7'd1));
  assign segment_last_w = block_last_w;
  assign output_last_w = segment_last_w &&
    (stream_last_on_segment_end || frame_last_segment);

  assign local_x_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      {13'd0, sample_q[1:0]} :
      {13'd0, sample_q[2:0]};
  assign local_y_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      {12'd0, sample_q[5:2]} :
      {13'd0, sample_q[5:3]};
  assign sample_x_w =
    segment_origin_x + ({13'd0, leaf_col_w} << 3) + local_x_w;
  assign sample_y_w =
    segment_origin_y + ({13'd0, leaf_row_w} << 3) + local_y_w;
  assign plane_x_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      ((segment_origin_x >> 1) + ({13'd0, leaf_col_w} << 2) + local_x_w) :
      sample_x_w;
  assign plane_y_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      ((segment_origin_y >> 1) + ({13'd0, leaf_row_w} << 2) + local_y_w) :
      sample_y_w;
  assign plane_base_w =
    (component_q == 2'd0) ? src_y_base :
    (component_q == 2'd1) ? src_u_base :
    src_v_base;
  assign plane_stride_w =
    (component_q == 2'd0) ? src_y_stride :
    (component_q == 2'd1) ? src_u_stride :
    src_v_stride;
  assign row_offset_w = {32'd0, plane_y_w} * plane_stride_w;
  assign col_offset_w = {32'd0, plane_x_w} << SAMPLE_BYTE_SHIFT;
  assign plane_offset_w = src_frame_offset + row_offset_w + col_offset_w;
  assign m_axi_araddr = plane_base_w + plane_offset_w;
  assign pad_sample_w = (component_q == 2'd0) ? '0 : {{(SAMPLE_BITS-8){1'b0}}, 8'd128};
  assign in_visible_w =
    (sample_x_w < visible_width) &&
    (sample_y_w < visible_height) &&
    !((chroma_format_idc == 2'd1) && (component_q != 2'd0) &&
      ((plane_x_w >= (visible_width >> 1)) || (plane_y_w >= (visible_height >> 1))));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      scan_q <= 6'd0;
      raster_col_q <= 3'd0;
      raster_row_q <= 3'd0;
      leaf_count_q <= 7'd0;
      component_q <= 2'd0;
      sample_q <= 6'd0;
      m_axi_arvalid <= 1'b0;
      m_axi_rready <= 1'b0;
      sample_valid <= 1'b0;
      sample_data <= '0;
      sample_last <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start) begin
        state_q <= ST_SKIP;
        scan_q <= 6'd0;
        raster_col_q <= 3'd0;
        raster_row_q <= 3'd0;
        leaf_count_q <= 7'd0;
        component_q <= 2'd0;
        sample_q <= 6'd0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready <= 1'b0;
        sample_valid <= 1'b0;
        sample_last <= 1'b0;
        error <= 1'b0;
      end else begin
        if (sample_valid && sample_ready) begin
          sample_valid <= 1'b0;
          sample_last <= 1'b0;
          if (segment_last_w) begin
            state_q <= ST_IDLE;
            done <= 1'b1;
          end else begin
            state_q <= ST_SKIP;
            if (sample_last_in_component_w) begin
              sample_q <= 6'd0;
              if (component_q == 2'd2) begin
                component_q <= 2'd0;
                leaf_count_q <= leaf_count_q + 7'd1;
                if (RASTER_BLOCK_ORDER) begin
                  if ({1'b0, raster_col_q} == (active_cols_w - 4'd1)) begin
                    raster_col_q <= 3'd0;
                    raster_row_q <= raster_row_q + 3'd1;
                  end else begin
                    raster_col_q <= raster_col_q + 3'd1;
                  end
                end else begin
                  scan_q <= scan_q + 6'd1;
                end
              end else begin
                component_q <= component_q + 2'd1;
              end
            end else begin
              sample_q <= sample_q + 6'd1;
            end
          end
        end

        case (state_q)
          ST_IDLE: begin
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
          end
          ST_SKIP: begin
            if (leaf_active_w) begin
              if (in_visible_w) begin
                m_axi_arvalid <= 1'b1;
                state_q <= ST_ADDR;
              end else begin
                sample_data <= pad_sample_w;
                sample_last <= output_last_w;
                sample_valid <= 1'b1;
                state_q <= ST_PAD;
              end
            end else if (!RASTER_BLOCK_ORDER && scan_q != 6'd63) begin
              scan_q <= scan_q + 6'd1;
            end else begin
              state_q <= ST_IDLE;
              done <= 1'b1;
            end
          end
          ST_ADDR: begin
            if (m_axi_arvalid && m_axi_arready) begin
              m_axi_arvalid <= 1'b0;
              m_axi_rready <= 1'b1;
              state_q <= ST_WAIT_R;
            end
          end
          ST_WAIT_R: begin
            if (m_axi_rvalid && m_axi_rready) begin
              m_axi_rready <= 1'b0;
              sample_data <= m_axi_rdata[SAMPLE_BITS-1:0];
              sample_last <= output_last_w;
              sample_valid <= 1'b1;
              state_q <= ST_VALID;
              if (m_axi_rresp != 2'b00 || !m_axi_rlast) begin
                error <= 1'b1;
              end
            end
          end
          ST_PAD: begin
          end
          ST_VALID: begin
          end
          default: begin
            state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end
endmodule
