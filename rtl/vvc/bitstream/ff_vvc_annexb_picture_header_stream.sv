`timescale 1ns/1ps

module ff_vvc_annexb_picture_header_stream (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [15:0] poc_lsb,
  input  logic        sps_joint_cbcr_enabled_flag,

  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic        done
);
  localparam logic [4:0] NAL_UNIT_TYPE_PH = 5'd19;
  localparam logic [5:0] NAL_LAYER_ID = 6'd0;
  localparam logic [2:0] NAL_TEMPORAL_ID_PLUS1 = 3'd1;
  localparam logic [3:0] PH_FIELD_COUNT = 4'd8;

  localparam logic [3:0] ST_IDLE = 4'd0;
  localparam logic [3:0] ST_START_CODE = 4'd1;
  localparam logic [3:0] ST_NAL_HEADER = 4'd2;
  localparam logic [3:0] ST_CLEAR_RBSP = 4'd3;
  localparam logic [3:0] ST_FIELDS = 4'd4;
  localparam logic [3:0] ST_TRAILING_STOP = 4'd5;
  localparam logic [3:0] ST_TRAILING_FLUSH = 4'd6;
  localparam logic [3:0] ST_DRAIN_RBSP = 4'd7;

  logic [3:0] state_q;
  logic [2:0] byte_index_q;
  logic [3:0] field_index_q;
  logic       rbsp_clear_q;
  logic       rbsp_last_seen_q;

  logic [31:0] syntax_value;
  logic [5:0]  syntax_bits;
  logic        syntax_fields_done;
  logic        bit_writer_valid;
  logic        bit_writer_ready;
  logic [31:0] bit_writer_value;
  logic [5:0]  bit_writer_bits;
  logic        bit_writer_flush_zero;
  logic        bit_writer_last;
  logic        bit_writer_byte_valid;
  logic        bit_writer_byte_ready;
  logic [7:0]  bit_writer_byte_data;
  logic        bit_writer_byte_last;
  logic        rbsp_valid;
  logic        rbsp_ready;
  logic [7:0]  rbsp_data;
  logic        rbsp_last;
  logic        direct_valid;
  logic [7:0]  direct_data;
  logic        rbsp_output_active;

  assign syntax_fields_done = field_index_q >= PH_FIELD_COUNT;
  assign rbsp_output_active =
    (state_q == ST_FIELDS) ||
    (state_q == ST_TRAILING_STOP) ||
    (state_q == ST_TRAILING_FLUSH) ||
    (state_q == ST_DRAIN_RBSP);

  ff_vvc_cabac_bit_writer rbsp_bit_writer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(rbsp_clear_q || clear),
    .s_axis_valid(bit_writer_valid),
    .s_axis_ready(bit_writer_ready),
    .s_axis_value(bit_writer_value),
    .s_axis_bit_count(bit_writer_bits),
    .s_axis_flush_zero(bit_writer_flush_zero),
    .s_axis_last(bit_writer_last),
    .m_axis_ready(bit_writer_byte_ready),
    .m_axis_valid(bit_writer_byte_valid),
    .m_axis_data(bit_writer_byte_data),
    .m_axis_last(bit_writer_byte_last),
    .total_bit_count(),
    .partial_bit_count(),
    .idle(),
    .done()
  );

  ff_vvc_emulation_prevention_stream rbsp_emulation_prevention (
    .clk(clk),
    .rst_n(rst_n),
    .clear(rbsp_clear_q || clear),
    .s_axis_valid(bit_writer_byte_valid),
    .s_axis_ready(bit_writer_byte_ready),
    .s_axis_data(bit_writer_byte_data),
    .s_axis_last(bit_writer_byte_last),
    .m_axis_ready(rbsp_ready),
    .m_axis_valid(rbsp_valid),
    .m_axis_data(rbsp_data),
    .m_axis_last(rbsp_last),
    .done()
  );

  assign direct_valid = (state_q == ST_START_CODE) || (state_q == ST_NAL_HEADER);
  assign direct_data =
    (state_q == ST_START_CODE) ? ((byte_index_q == 3'd3) ? 8'h01 : 8'h00) :
    ((byte_index_q == 3'd0) ? {2'b00, NAL_LAYER_ID} :
      {NAL_UNIT_TYPE_PH, NAL_TEMPORAL_ID_PLUS1});
  assign rbsp_ready = rbsp_output_active && m_axis_ready;
  assign m_axis_valid = direct_valid ? 1'b1 : (rbsp_output_active && rbsp_valid);
  assign m_axis_data = direct_valid ? direct_data : rbsp_data;
  assign m_axis_last = rbsp_output_active && rbsp_valid && rbsp_last;

  always @* begin
    syntax_value = 32'd0;
    syntax_bits = 6'd0;

    case (field_index_q)
      4'd0: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // ph_gdr_or_irap_pic_flag
      4'd1: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ph_non_ref_pic_flag
      4'd2: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ph_gdr_pic_flag
      4'd3: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ph_inter_slice_allowed_flag
      4'd4: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // ph_pic_parameter_set_id ue(0)
      4'd5: begin syntax_value = {16'd0, poc_lsb}; syntax_bits = 6'd16; end
      4'd6: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ph_partition_constraints_override_flag
      4'd7: begin syntax_value = 32'd0; syntax_bits = sps_joint_cbcr_enabled_flag ? 6'd1 : 6'd0; end // ph_joint_cbcr_sign_flag
      default: begin syntax_value = 32'd0; syntax_bits = 6'd0; end
    endcase
  end

  always @* begin
    bit_writer_valid = 1'b0;
    bit_writer_value = syntax_value;
    bit_writer_bits = syntax_bits;
    bit_writer_flush_zero = 1'b0;
    bit_writer_last = 1'b0;

    if (state_q == ST_FIELDS && !syntax_fields_done) begin
      bit_writer_valid = syntax_bits != 6'd0;
    end else if (state_q == ST_TRAILING_STOP) begin
      bit_writer_valid = 1'b1;
      bit_writer_value = 32'd1;
      bit_writer_bits = 6'd1;
      bit_writer_last = 1'b1;
    end else if (state_q == ST_TRAILING_FLUSH) begin
      bit_writer_valid = 1'b1;
      bit_writer_value = 32'd0;
      bit_writer_bits = 6'd0;
      bit_writer_flush_zero = 1'b1;
      bit_writer_last = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      byte_index_q <= 3'd0;
      field_index_q <= 4'd0;
      rbsp_clear_q <= 1'b0;
      rbsp_last_seen_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      byte_index_q <= 3'd0;
      field_index_q <= 4'd0;
      rbsp_clear_q <= 1'b0;
      rbsp_last_seen_q <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      rbsp_clear_q <= 1'b0;

      if (rbsp_output_active && rbsp_valid && rbsp_ready && rbsp_last) begin
        rbsp_last_seen_q <= 1'b1;
      end

      case (state_q)
        ST_IDLE: begin
          rbsp_last_seen_q <= 1'b0;
          if (start) begin
            byte_index_q <= 3'd0;
            field_index_q <= 4'd0;
            state_q <= ST_START_CODE;
          end
        end

        ST_START_CODE: begin
          if (m_axis_ready) begin
            if (byte_index_q == 3'd3) begin
              byte_index_q <= 3'd0;
              state_q <= ST_NAL_HEADER;
            end else begin
              byte_index_q <= byte_index_q + 3'd1;
            end
          end
        end

        ST_NAL_HEADER: begin
          if (m_axis_ready) begin
            if (byte_index_q == 3'd1) begin
              byte_index_q <= 3'd0;
              rbsp_clear_q <= 1'b1;
              field_index_q <= 4'd0;
              rbsp_last_seen_q <= 1'b0;
              state_q <= ST_CLEAR_RBSP;
            end else begin
              byte_index_q <= byte_index_q + 3'd1;
            end
          end
        end

        ST_CLEAR_RBSP: begin
          state_q <= ST_FIELDS;
        end

        ST_FIELDS: begin
          if (syntax_fields_done) begin
            state_q <= ST_TRAILING_STOP;
          end else if (syntax_bits == 6'd0) begin
            field_index_q <= field_index_q + 4'd1;
          end else if (bit_writer_valid && bit_writer_ready) begin
            field_index_q <= field_index_q + 4'd1;
          end
        end

        ST_TRAILING_STOP: begin
          if (bit_writer_valid && bit_writer_ready) begin
            state_q <= ST_TRAILING_FLUSH;
          end
        end

        ST_TRAILING_FLUSH: begin
          if (bit_writer_valid && bit_writer_ready) begin
            state_q <= ST_DRAIN_RBSP;
          end
        end

        ST_DRAIN_RBSP: begin
          if (rbsp_last_seen_q && (!rbsp_valid || (rbsp_valid && rbsp_ready))) begin
            done <= 1'b1;
            state_q <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
