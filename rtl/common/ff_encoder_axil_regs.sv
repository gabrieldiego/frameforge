`timescale 1ns/1ps

module ff_encoder_axil_regs #(
  parameter int AXI_ADDR_BITS = 32,
  parameter int AXIL_ADDR_BITS = 12
) (
  input  logic                     clk,
  input  logic                     rst_n,

  input  logic [AXIL_ADDR_BITS-1:0] s_axil_awaddr,
  input  logic                     s_axil_awvalid,
  output logic                     s_axil_awready,
  input  logic [31:0]              s_axil_wdata,
  input  logic [3:0]               s_axil_wstrb,
  input  logic                     s_axil_wvalid,
  output logic                     s_axil_wready,
  output logic [1:0]               s_axil_bresp,
  output logic                     s_axil_bvalid,
  input  logic                     s_axil_bready,
  input  logic [AXIL_ADDR_BITS-1:0] s_axil_araddr,
  input  logic                     s_axil_arvalid,
  output logic                     s_axil_arready,
  output logic [31:0]              s_axil_rdata,
  output logic [1:0]               s_axil_rresp,
  output logic                     s_axil_rvalid,
  input  logic                     s_axil_rready,

  input  logic                     busy,
  input  logic                     done,
  input  logic                     input_error,
  input  logic                     axi_error,
  input  logic [31:0]              encoded_byte_count,

  output logic                     start_pulse,
  output logic [15:0]              visible_width,
  output logic [15:0]              visible_height,
  output logic [1:0]               chroma_format_idc,
  output logic [31:0]              frame_count,
  output logic [AXI_ADDR_BITS-1:0] src_y_base,
  output logic [AXI_ADDR_BITS-1:0] src_u_base,
  output logic [AXI_ADDR_BITS-1:0] src_v_base,
  output logic [31:0]              src_y_stride,
  output logic [31:0]              src_u_stride,
  output logic [31:0]              src_v_stride,
  output logic [31:0]              src_frame_stride,
  output logic [AXI_ADDR_BITS-1:0] dst_bitstream_base,
  output logic [31:0]              dst_bitstream_capacity
);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_CONTROL      = AXIL_ADDR_BITS'(12'h000);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_STATUS       = AXIL_ADDR_BITS'(12'h004);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_WIDTH        = AXIL_ADDR_BITS'(12'h008);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_HEIGHT       = AXIL_ADDR_BITS'(12'h00c);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_CHROMA       = AXIL_ADDR_BITS'(12'h010);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_FRAME_COUNT  = AXIL_ADDR_BITS'(12'h014);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_SRC_Y_BASE   = AXIL_ADDR_BITS'(12'h018);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_SRC_U_BASE   = AXIL_ADDR_BITS'(12'h01c);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_SRC_V_BASE   = AXIL_ADDR_BITS'(12'h020);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_SRC_Y_STRIDE = AXIL_ADDR_BITS'(12'h024);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_SRC_U_STRIDE = AXIL_ADDR_BITS'(12'h028);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_SRC_V_STRIDE = AXIL_ADDR_BITS'(12'h02c);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_FRAME_STRIDE = AXIL_ADDR_BITS'(12'h030);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_DST_BASE     = AXIL_ADDR_BITS'(12'h034);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_DST_CAPACITY = AXIL_ADDR_BITS'(12'h038);
  localparam logic [AXIL_ADDR_BITS-1:0] REG_BYTES_USED   = AXIL_ADDR_BITS'(12'h03c);

  logic aw_pending_q;
  logic w_pending_q;
  logic [AXIL_ADDR_BITS-1:0] awaddr_q;
  logic [31:0] wdata_q;
  logic done_sticky_q;
  logic input_error_sticky_q;
  logic axi_error_sticky_q;
  logic [31:0] read_data_w;
  logic write_fire_w;

  assign s_axil_awready = !aw_pending_q && !s_axil_bvalid;
  assign s_axil_wready = !w_pending_q && !s_axil_bvalid;
  assign s_axil_bresp = 2'b00;
  assign s_axil_arready = !s_axil_rvalid;
  assign s_axil_rresp = 2'b00;
  assign write_fire_w = aw_pending_q && w_pending_q && !s_axil_bvalid;

  always_comb begin
    read_data_w = 32'd0;
    case (s_axil_araddr)
      REG_CONTROL: read_data_w = 32'd0;
      REG_STATUS: read_data_w = {
        28'd0,
        axi_error_sticky_q,
        input_error_sticky_q,
        done_sticky_q,
        busy
      };
      REG_WIDTH: read_data_w = {16'd0, visible_width};
      REG_HEIGHT: read_data_w = {16'd0, visible_height};
      REG_CHROMA: read_data_w = {30'd0, chroma_format_idc};
      REG_FRAME_COUNT: read_data_w = frame_count;
      REG_SRC_Y_BASE: read_data_w = src_y_base[31:0];
      REG_SRC_U_BASE: read_data_w = src_u_base[31:0];
      REG_SRC_V_BASE: read_data_w = src_v_base[31:0];
      REG_SRC_Y_STRIDE: read_data_w = src_y_stride;
      REG_SRC_U_STRIDE: read_data_w = src_u_stride;
      REG_SRC_V_STRIDE: read_data_w = src_v_stride;
      REG_FRAME_STRIDE: read_data_w = src_frame_stride;
      REG_DST_BASE: read_data_w = dst_bitstream_base[31:0];
      REG_DST_CAPACITY: read_data_w = dst_bitstream_capacity;
      REG_BYTES_USED: read_data_w = encoded_byte_count;
      default: read_data_w = 32'd0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_pending_q <= 1'b0;
      w_pending_q <= 1'b0;
      awaddr_q <= '0;
      wdata_q <= 32'd0;
      s_axil_bvalid <= 1'b0;
      s_axil_rvalid <= 1'b0;
      s_axil_rdata <= 32'd0;
      start_pulse <= 1'b0;
      visible_width <= 16'd0;
      visible_height <= 16'd0;
      chroma_format_idc <= 2'd3;
      frame_count <= 32'd1;
      src_y_base <= '0;
      src_u_base <= '0;
      src_v_base <= '0;
      src_y_stride <= 32'd0;
      src_u_stride <= 32'd0;
      src_v_stride <= 32'd0;
      src_frame_stride <= 32'd0;
      dst_bitstream_base <= '0;
      dst_bitstream_capacity <= 32'd0;
      done_sticky_q <= 1'b0;
      input_error_sticky_q <= 1'b0;
      axi_error_sticky_q <= 1'b0;
    end else begin
      start_pulse <= 1'b0;
      if (done) begin
        done_sticky_q <= 1'b1;
      end
      if (input_error) begin
        input_error_sticky_q <= 1'b1;
      end
      if (axi_error) begin
        axi_error_sticky_q <= 1'b1;
      end

      if (s_axil_awvalid && s_axil_awready) begin
        awaddr_q <= s_axil_awaddr;
        aw_pending_q <= 1'b1;
      end
      if (s_axil_wvalid && s_axil_wready) begin
        wdata_q <= s_axil_wdata;
        w_pending_q <= 1'b1;
      end
      if (write_fire_w) begin
        case (awaddr_q)
          REG_CONTROL: begin
            if (wdata_q[0]) begin
              start_pulse <= 1'b1;
              done_sticky_q <= 1'b0;
              input_error_sticky_q <= 1'b0;
              axi_error_sticky_q <= 1'b0;
            end
            if (wdata_q[1]) begin
              done_sticky_q <= 1'b0;
              input_error_sticky_q <= 1'b0;
              axi_error_sticky_q <= 1'b0;
            end
          end
          REG_WIDTH: visible_width <= wdata_q[15:0];
          REG_HEIGHT: visible_height <= wdata_q[15:0];
          REG_CHROMA: chroma_format_idc <= wdata_q[1:0];
          REG_FRAME_COUNT: frame_count <= wdata_q;
          REG_SRC_Y_BASE: src_y_base <= wdata_q;
          REG_SRC_U_BASE: src_u_base <= wdata_q;
          REG_SRC_V_BASE: src_v_base <= wdata_q;
          REG_SRC_Y_STRIDE: src_y_stride <= wdata_q;
          REG_SRC_U_STRIDE: src_u_stride <= wdata_q;
          REG_SRC_V_STRIDE: src_v_stride <= wdata_q;
          REG_FRAME_STRIDE: src_frame_stride <= wdata_q;
          REG_DST_BASE: dst_bitstream_base <= wdata_q;
          REG_DST_CAPACITY: dst_bitstream_capacity <= wdata_q;
          default: begin
          end
        endcase
        aw_pending_q <= 1'b0;
        w_pending_q <= 1'b0;
        s_axil_bvalid <= 1'b1;
      end else if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end

      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_rdata <= read_data_w;
        s_axil_rvalid <= 1'b1;
      end else if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid <= 1'b0;
      end
    end
  end
endmodule
