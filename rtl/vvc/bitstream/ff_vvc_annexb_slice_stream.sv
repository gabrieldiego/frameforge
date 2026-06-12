`timescale 1ns/1ps

module ff_vvc_annexb_slice_stream (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       clear,
  input  logic       start,
  input  logic [4:0] nal_unit_type,
  input  logic [15:0] poc_lsb,
  input  logic       include_picture_header,
  input  logic       multi_slice_picture,
  input  logic [15:0] slice_address,
  input  logic [5:0]  slice_address_bits,
  input  logic       sps_joint_cbcr_enabled_flag,
  input  logic       sh_dep_quant_used_flag,
  input  logic       sh_sign_data_hiding_used_flag,
  input  logic       sh_ts_residual_coding_disabled_flag,
  input  logic       palette_lossless_qp,

  output logic       s_axis_ready,
  input  logic       s_axis_valid,
  input  logic [7:0] s_axis_data,
  input  logic       s_axis_last,

  input  logic       m_axis_ready,
  output logic       m_axis_valid,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last,
  output logic       done
);
  localparam logic [5:0] NAL_LAYER_ID = 6'd0;
  localparam logic [2:0] NAL_TEMPORAL_ID_PLUS1 = 3'd1;
  localparam logic [2:0] ST_IDLE = 3'd0;
  localparam logic [2:0] ST_START_CODE = 3'd1;
  localparam logic [2:0] ST_NAL_HEADER = 3'd2;
  localparam logic [2:0] ST_PREFIX_CLEAR = 3'd3;
  localparam logic [2:0] ST_PREFIX_FIELDS = 3'd4;
  localparam logic [2:0] ST_PREFIX_FLUSH = 3'd5;
  localparam logic [2:0] ST_PREFIX_DRAIN = 3'd6;
  localparam logic [2:0] ST_PAYLOAD_RBSP = 3'd7;
  localparam logic [4:0] NAL_UNIT_TYPE_CRA = 5'd9;
  localparam logic [4:0] SLICE_PREFIX_FIELD_COUNT_IDR = 5'd15;
  localparam logic [4:0] SLICE_PREFIX_FIELD_COUNT_CRA = 5'd16;
  localparam logic [4:0] SLICE_PREFIX_FIELD_COUNT_NO_PH = 5'd9;

  logic [2:0] state_q;
  logic [2:0] byte_index_q;
  logic       ep_clear_q;
  logic       prefix_writer_clear_q;
  logic       ep_s_valid;
  logic       ep_s_ready;
  logic [7:0] ep_s_data;
  logic       ep_s_last;
  logic       ep_m_valid;
  logic       ep_m_ready;
  logic [7:0] ep_m_data;
  logic       ep_m_last;
  logic [4:0] prefix_field_index_q;
  logic [4:0] prefix_field_count;
  logic       prefix_fields_done;
  logic [31:0] prefix_syntax_value;
  logic [5:0]  prefix_syntax_bits;
  logic        prefix_bit_valid;
  logic        prefix_bit_ready;
  logic [31:0] prefix_bit_value;
  logic [5:0]  prefix_bit_count;
  logic        prefix_bit_flush_zero;
  logic        prefix_byte_valid;
  logic        prefix_byte_ready;
  logic [7:0]  prefix_byte_data;
  logic        prefix_writer_idle;
  logic        is_cra_nal;
  logic [31:0] sh_qp_delta_syntax_value;
  logic [5:0]  sh_qp_delta_syntax_bits;

  assign is_cra_nal = nal_unit_type == NAL_UNIT_TYPE_CRA;
  // H.266 8.4.5.3 palette escape reconstruction is lossless for 8-bit
  // PaletteEscapeVal samples when SliceQpY is 4. With the current PPS base
  // QP 32, palette slices therefore signal sh_qp_delta se(-28), encoded as
  // ue(56) = 00000_111001. Residual slices keep se(0).
  assign sh_qp_delta_syntax_value = palette_lossless_qp ? 32'd57 : 32'd1;
  assign sh_qp_delta_syntax_bits = palette_lossless_qp ? 6'd11 : 6'd1;
  assign prefix_field_count = include_picture_header ?
    (is_cra_nal ? SLICE_PREFIX_FIELD_COUNT_CRA : SLICE_PREFIX_FIELD_COUNT_IDR) :
    SLICE_PREFIX_FIELD_COUNT_NO_PH;
  assign prefix_fields_done = prefix_field_index_q >= prefix_field_count;
  assign ep_m_ready = (state_q == ST_PREFIX_FIELDS ||
                       state_q == ST_PREFIX_FLUSH ||
                       state_q == ST_PREFIX_DRAIN ||
                       state_q == ST_PAYLOAD_RBSP) &&
                      (!m_axis_valid || m_axis_ready);
  assign s_axis_ready = (state_q == ST_PAYLOAD_RBSP) && ep_s_ready;

  always @* begin
    prefix_syntax_value = 32'd0;
    prefix_syntax_bits = 6'd0;
    if (include_picture_header) begin
      case (prefix_field_index_q)
        5'd0:  begin prefix_syntax_value = 32'd1; prefix_syntax_bits = 6'd1; end // sh_picture_header_in_slice_header_flag
        5'd1:  begin prefix_syntax_value = 32'd1; prefix_syntax_bits = 6'd1; end // ph_gdr_or_irap_pic_flag
        5'd2:  begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd1; end // ph_non_ref_pic_flag
        5'd3:  begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd1; end // ph_gdr_pic_flag
        5'd4:  begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd1; end // ph_inter_slice_allowed_flag
        5'd5:  begin prefix_syntax_value = 32'd1; prefix_syntax_bits = 6'd1; end // ph_pic_parameter_set_id ue(0)
        5'd6:  begin prefix_syntax_value = {16'd0, poc_lsb}; prefix_syntax_bits = 6'd16; end // ph_pic_order_cnt_lsb
        5'd7:  begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd1; end // ph_partition_constraints_override_flag
        5'd8:  begin prefix_syntax_value = 32'd0; prefix_syntax_bits = sps_joint_cbcr_enabled_flag ? 6'd1 : 6'd0; end // ph_joint_cbcr_sign_flag
        5'd9:  begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd1; end // sh_no_output_of_prior_pics_flag
        5'd10: begin prefix_syntax_value = sh_qp_delta_syntax_value; prefix_syntax_bits = sh_qp_delta_syntax_bits; end // sh_qp_delta
        5'd11: begin prefix_syntax_value = {31'd0, sh_dep_quant_used_flag}; prefix_syntax_bits = sh_dep_quant_used_flag ? 6'd1 : 6'd0; end // sh_dep_quant_used_flag
        5'd12: begin prefix_syntax_value = {31'd0, sh_sign_data_hiding_used_flag}; prefix_syntax_bits = (sh_sign_data_hiding_used_flag && !sh_dep_quant_used_flag) ? 6'd1 : 6'd0; end // sh_sign_data_hiding_used_flag
        5'd13: begin prefix_syntax_value = {31'd0, sh_ts_residual_coding_disabled_flag}; prefix_syntax_bits = sh_ts_residual_coding_disabled_flag ? 6'd1 : 6'd0; end
        5'd14: begin prefix_syntax_value = 32'd1; prefix_syntax_bits = 6'd1; end // cabac_alignment_one_bit
        5'd15: begin prefix_syntax_value = 32'd1; prefix_syntax_bits = 6'd1; end // CRA alignment bit matching current SW subset
        default: begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd0; end
      endcase
    end else begin
      case (prefix_field_index_q)
        5'd0: begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd1; end // sh_picture_header_in_slice_header_flag
        5'd1: begin prefix_syntax_value = {16'd0, slice_address}; prefix_syntax_bits = multi_slice_picture ? slice_address_bits : 6'd0; end
        5'd2: begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd1; end // sh_no_output_of_prior_pics_flag
        5'd3: begin prefix_syntax_value = sh_qp_delta_syntax_value; prefix_syntax_bits = sh_qp_delta_syntax_bits; end // sh_qp_delta
        5'd4: begin prefix_syntax_value = {31'd0, sh_dep_quant_used_flag}; prefix_syntax_bits = sh_dep_quant_used_flag ? 6'd1 : 6'd0; end
        5'd5: begin prefix_syntax_value = {31'd0, sh_sign_data_hiding_used_flag}; prefix_syntax_bits = (sh_sign_data_hiding_used_flag && !sh_dep_quant_used_flag) ? 6'd1 : 6'd0; end
        5'd6: begin prefix_syntax_value = {31'd0, sh_ts_residual_coding_disabled_flag}; prefix_syntax_bits = sh_ts_residual_coding_disabled_flag ? 6'd1 : 6'd0; end
        5'd7: begin prefix_syntax_value = 32'd1; prefix_syntax_bits = 6'd1; end // cabac_alignment_one_bit before CABAC payload
        5'd8: begin prefix_syntax_value = 32'd1; prefix_syntax_bits = is_cra_nal ? 6'd1 : 6'd0; end // extra CRA cabac_alignment_one_bit
        default: begin prefix_syntax_value = 32'd0; prefix_syntax_bits = 6'd0; end
      endcase
    end
  end

  always @* begin
    prefix_bit_valid = 1'b0;
    prefix_bit_value = prefix_syntax_value;
    prefix_bit_count = prefix_syntax_bits;
    prefix_bit_flush_zero = 1'b0;
    if (state_q == ST_PREFIX_FIELDS && !prefix_fields_done) begin
      prefix_bit_valid = prefix_syntax_bits != 6'd0;
    end else if (state_q == ST_PREFIX_FLUSH) begin
      prefix_bit_valid = 1'b1;
      prefix_bit_value = 32'd0;
      prefix_bit_count = 6'd0;
      prefix_bit_flush_zero = 1'b1;
    end
  end

  always @* begin
    ep_s_valid = 1'b0;
    ep_s_data = 8'h00;
    ep_s_last = 1'b0;
    if (state_q == ST_PREFIX_FIELDS ||
        state_q == ST_PREFIX_FLUSH ||
        state_q == ST_PREFIX_DRAIN) begin
      ep_s_valid = prefix_byte_valid;
      ep_s_data = prefix_byte_data;
      ep_s_last = 1'b0;
    end else if (state_q == ST_PAYLOAD_RBSP) begin
      ep_s_valid = s_axis_valid;
      ep_s_data = s_axis_data;
      ep_s_last = s_axis_last;
    end
  end

  assign prefix_byte_ready = (state_q == ST_PREFIX_FIELDS ||
                              state_q == ST_PREFIX_FLUSH ||
                              state_q == ST_PREFIX_DRAIN) && ep_s_ready;

  ff_vvc_cabac_bit_writer prefix_bit_writer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(prefix_writer_clear_q || clear),
    .s_axis_valid(prefix_bit_valid),
    .s_axis_ready(prefix_bit_ready),
    .s_axis_value(prefix_bit_value),
    .s_axis_bit_count(prefix_bit_count),
    .s_axis_flush_zero(prefix_bit_flush_zero),
    .s_axis_last(1'b0),
    .m_axis_ready(prefix_byte_ready),
    .m_axis_valid(prefix_byte_valid),
    .m_axis_data(prefix_byte_data),
    .m_axis_last(),
    .total_bit_count(),
    .partial_bit_count(),
    .idle(prefix_writer_idle),
    .done()
  );

  ff_vvc_emulation_prevention_stream rbsp_emulation_prevention (
    .clk(clk),
    .rst_n(rst_n),
    .clear(ep_clear_q || clear),
    .s_axis_valid(ep_s_valid),
    .s_axis_ready(ep_s_ready),
    .s_axis_data(ep_s_data),
    .s_axis_last(ep_s_last),
    .m_axis_ready(ep_m_ready),
    .m_axis_valid(ep_m_valid),
    .m_axis_data(ep_m_data),
    .m_axis_last(ep_m_last),
    .done()
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      byte_index_q <= 3'd0;
      ep_clear_q <= 1'b0;
      prefix_writer_clear_q <= 1'b0;
      prefix_field_index_q <= 5'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      byte_index_q <= 3'd0;
      ep_clear_q <= 1'b0;
      prefix_writer_clear_q <= 1'b0;
      prefix_field_index_q <= 5'd0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      ep_clear_q <= 1'b0;
      prefix_writer_clear_q <= 1'b0;

      if (m_axis_valid && !m_axis_ready) begin
        state_q <= state_q;
      end else begin
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;

        case (state_q)
          ST_IDLE: begin
            if (start) begin
              ep_clear_q <= 1'b1;
              prefix_writer_clear_q <= 1'b1;
              prefix_field_index_q <= 5'd0;
              state_q <= ST_START_CODE;
              byte_index_q <= 3'd0;
            end
          end

          ST_START_CODE: begin
            m_axis_valid <= 1'b1;
            m_axis_data <= (byte_index_q == 3'd3) ? 8'h01 : 8'h00;
            if (byte_index_q == 3'd3) begin
              byte_index_q <= 3'd0;
              state_q <= ST_NAL_HEADER;
            end else begin
              byte_index_q <= byte_index_q + 3'd1;
            end
          end

          ST_NAL_HEADER: begin
            m_axis_valid <= 1'b1;
            if (byte_index_q == 3'd0) begin
              m_axis_data <= {2'b00, NAL_LAYER_ID};
              byte_index_q <= 3'd1;
            end else begin
              m_axis_data <= {nal_unit_type, NAL_TEMPORAL_ID_PLUS1};
              byte_index_q <= 3'd0;
              prefix_writer_clear_q <= 1'b1;
              prefix_field_index_q <= 5'd0;
              state_q <= ST_PREFIX_CLEAR;
            end
          end

          ST_PREFIX_CLEAR: begin
            state_q <= ST_PREFIX_FIELDS;
          end

          ST_PREFIX_FIELDS: begin
            if (ep_m_valid) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= ep_m_data;
              m_axis_last <= 1'b0;
            end
            if (prefix_fields_done) begin
              if (prefix_writer_idle) begin
                state_q <= ST_PREFIX_FLUSH;
              end
            end else if (prefix_syntax_bits == 6'd0) begin
              prefix_field_index_q <= prefix_field_index_q + 5'd1;
            end else if (prefix_bit_valid && prefix_bit_ready) begin
              prefix_field_index_q <= prefix_field_index_q + 5'd1;
            end
          end

          ST_PREFIX_FLUSH: begin
            if (ep_m_valid) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= ep_m_data;
              m_axis_last <= 1'b0;
            end
            if (prefix_bit_valid && prefix_bit_ready) begin
              state_q <= ST_PREFIX_DRAIN;
            end
          end

          ST_PREFIX_DRAIN: begin
            if (ep_m_valid) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= ep_m_data;
              m_axis_last <= 1'b0;
            end
            if (prefix_writer_idle && !prefix_byte_valid && !ep_m_valid) begin
              state_q <= ST_PAYLOAD_RBSP;
            end
          end

          ST_PAYLOAD_RBSP: begin
            if (ep_m_valid) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= ep_m_data;
              m_axis_last <= ep_m_last;
              if (ep_m_last) begin
                state_q <= ST_IDLE;
                done <= 1'b1;
              end
            end
          end

          default: begin
            state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end
endmodule
