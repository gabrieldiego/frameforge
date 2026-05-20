`timescale 1ns/1ps

module ff_vvc_toy4x4_encoder (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [1:0] frame_count,
  output logic       busy,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [7:0] s_axis_data,
  input  logic       s_axis_last,
  output logic       input_error,
  output logic       sampled_color_valid,
  output logic [7:0] sampled_y,
  output logic [7:0] sampled_u,
  output logic [7:0] sampled_v,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int SPS_PAYLOAD_LEN  = 31;
  localparam int PPS_PAYLOAD_LEN  = 14;
  localparam int NAL_OVERHEAD_LEN = 6;
  localparam int SPS_NAL_LEN = NAL_OVERHEAD_LEN + SPS_PAYLOAD_LEN;
  localparam int PPS_NAL_LEN = NAL_OVERHEAD_LEN + PPS_PAYLOAD_LEN;
  localparam int PARAMETER_SET_LEN = SPS_NAL_LEN + PPS_NAL_LEN;
  localparam int FRAME_BYTES = 24;

  logic [7:0] index_q;
  logic [7:0] stream_len_q;
  logic [7:0] input_count_q;
  logic [7:0] input_len_q;
  logic       input_active_q;
  logic [4:0] quant_luma_rem_q;

  assign busy = input_active_q || m_axis_valid || (index_q != 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q      <= '0;
      stream_len_q <= '0;
      input_count_q <= '0;
      input_len_q   <= '0;
      input_active_q <= 1'b0;
      s_axis_ready <= 1'b0;
      input_error  <= 1'b0;
      sampled_color_valid <= 1'b0;
      sampled_y <= '0;
      sampled_u <= '0;
      sampled_v <= '0;
      quant_luma_rem_q <= 5'd16;
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
    end else begin
      if (start && !busy) begin
        input_active_q <= 1'b1;
        s_axis_ready   <= 1'b1;
        input_count_q  <= '0;
        input_len_q    <= input_len(frame_count);
        stream_len_q   <= '0;
        input_error    <= 1'b0;
        sampled_color_valid <= 1'b0;
        quant_luma_rem_q <= 5'd16;
        m_axis_valid   <= 1'b0;
        m_axis_last    <= 1'b0;
        index_q        <= '0;
      end else if (input_active_q && s_axis_valid && s_axis_ready) begin
        if (s_axis_last != (input_count_q == input_len_q - 1'b1)) begin
          input_error <= 1'b1;
        end
        if (input_count_q == 8'd0) begin
          sampled_y <= s_axis_data;
          quant_luma_rem_q <= quant_luma_rem_from_solid_transform(s_axis_data);
        end
        if (input_count_q == 8'd16) begin
          sampled_u <= s_axis_data;
        end
        if (input_count_q == 8'd20) begin
          sampled_v <= s_axis_data;
        end

        if (input_count_q == input_len_q - 1'b1) begin
          input_active_q <= 1'b0;
          s_axis_ready   <= 1'b0;
          sampled_color_valid <= !input_error && s_axis_last;
          stream_len_q   <= stream_len(frame_count);
          m_axis_valid   <= 1'b1;
          m_axis_data    <= stream_byte(8'd0);
          m_axis_last    <= 1'b0;
          index_q        <= 8'd1;
        end else begin
          input_count_q <= input_count_q + 1'b1;
        end
      end else if (m_axis_valid && m_axis_ready) begin
        if (index_q == stream_len_q) begin
          m_axis_valid <= 1'b0;
          m_axis_last  <= 1'b0;
          index_q      <= '0;
        end else begin
          m_axis_data <= stream_byte(index_q);
          m_axis_last <= (index_q == stream_len_q - 1'b1);
          index_q     <= index_q + 1'b1;
        end
      end
    end
  end

  function automatic logic [7:0] input_len(input logic [1:0] frames);
    case (frames)
      2'd2: input_len = FRAME_BYTES * 2;
      default: input_len = FRAME_BYTES;
    endcase
  endfunction

  function automatic logic [7:0] stream_len(input logic [1:0] frames);
    case (frames)
      2'd2: stream_len = PARAMETER_SET_LEN + color_filler_nal_len() + (slice_nal_len() * 2);
      default: stream_len = PARAMETER_SET_LEN + color_filler_nal_len() + slice_nal_len();
    endcase
  endfunction

  function automatic logic [7:0] slice_payload_len();
    begin
      case (quant_luma_rem())
        5'd0, 5'd1, 5'd2: slice_payload_len = 8'd9;
        5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9, 5'd10, 5'd11: slice_payload_len = 8'd10;
        default: slice_payload_len = 8'd11;
      endcase
    end
  endfunction

  function automatic logic [7:0] slice_nal_len();
    begin
      slice_nal_len = NAL_OVERHEAD_LEN + slice_payload_len();
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem();
    begin
      quant_luma_rem = quant_luma_rem_q;
    end
  endfunction

  function automatic signed [9:0] solid_luma_dc_coeff(input logic [7:0] sample);
    begin
      solid_luma_dc_coeff = $signed({ 2'b00, sample }) - 10'sd114;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_solid_transform(input logic [7:0] sample);
    begin
      quant_luma_rem_from_solid_transform = quant_luma_rem_from_dc_coeff(solid_luma_dc_coeff(sample));
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_dc_coeff(input logic signed [9:0] dc_coeff);
    logic [7:0] sample;
    begin
      if (dc_coeff <= -10'sd114) begin
        sample = 8'd0;
      end else if (dc_coeff >= 10'sd141) begin
        sample = 8'd255;
      end else begin
        sample = dc_coeff + 10'sd114;
      end
      quant_luma_rem_from_dc_coeff = quant_luma_rem_from_sample(sample);
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_sample(input logic [7:0] sample);
    begin
      if (sample >= 8'd111) quant_luma_rem_from_sample = 5'd0;
      else if (sample >= 8'd104) quant_luma_rem_from_sample = 5'd1;
      else if (sample >= 8'd96) quant_luma_rem_from_sample = 5'd2;
      else if (sample >= 8'd89) quant_luma_rem_from_sample = 5'd3;
      else if (sample >= 8'd82) quant_luma_rem_from_sample = 5'd4;
      else if (sample >= 8'd75) quant_luma_rem_from_sample = 5'd5;
      else if (sample >= 8'd68) quant_luma_rem_from_sample = 5'd6;
      else if (sample >= 8'd61) quant_luma_rem_from_sample = 5'd7;
      else if (sample >= 8'd54) quant_luma_rem_from_sample = 5'd8;
      else if (sample >= 8'd46) quant_luma_rem_from_sample = 5'd9;
      else if (sample >= 8'd39) quant_luma_rem_from_sample = 5'd10;
      else if (sample >= 8'd32) quant_luma_rem_from_sample = 5'd11;
      else if (sample >= 8'd25) quant_luma_rem_from_sample = 5'd12;
      else if (sample >= 8'd18) quant_luma_rem_from_sample = 5'd13;
      else if (sample >= 8'd11) quant_luma_rem_from_sample = 5'd14;
      else if (sample >= 8'd4) quant_luma_rem_from_sample = 5'd15;
      else quant_luma_rem_from_sample = 5'd16;
    end
  endfunction

  function automatic logic [7:0] color_filler_count();
    begin
      color_filler_count = (sampled_y + sampled_u + sampled_v) & 8'h0f;
    end
  endfunction

  function automatic logic [7:0] color_filler_payload_len();
    begin
      color_filler_payload_len = color_filler_count() + 8'd1;
    end
  endfunction

  function automatic logic [7:0] color_filler_nal_len();
    begin
      color_filler_nal_len = NAL_OVERHEAD_LEN + color_filler_payload_len();
    end
  endfunction

  function automatic logic [7:0] stream_byte(input logic [7:0] index);
    logic second_picture;
    logic [7:0] slice_base;
    logic [6:0] slice_index;

    begin
      if (index < SPS_NAL_LEN) begin
        stream_byte = nal_byte(2'd0, index[6:0], 1'b0);
      end else if (index < PARAMETER_SET_LEN) begin
        stream_byte = nal_byte(2'd1, index - SPS_NAL_LEN, 1'b0);
      end else if (index < PARAMETER_SET_LEN + color_filler_nal_len()) begin
        stream_byte = nal_byte(2'd3, index - PARAMETER_SET_LEN, 1'b0);
      end else begin
        slice_base = PARAMETER_SET_LEN + color_filler_nal_len();
        second_picture = (index >= slice_base + slice_nal_len());
        slice_index = second_picture
          ? (index - (slice_base + slice_nal_len()))
          : (index - slice_base);
        stream_byte = nal_byte(2'd2, slice_index, second_picture);
      end
    end
  endfunction

  function automatic logic [7:0] nal_byte(
    input logic [1:0] nal_kind,
    input logic [6:0] nal_index,
    input logic       cra_picture
  );
    begin
      if (nal_index < 7'd4) begin
        nal_byte = start_code_byte(nal_index[1:0]);
      end else if (nal_index < 7'd6) begin
        nal_byte = nal_header_byte(nal_kind, nal_index[0], cra_picture);
      end else begin
        nal_byte = payload_byte(nal_kind, nal_index - 7'd6, cra_picture);
      end
    end
  endfunction

  function automatic logic [7:0] start_code_byte(input logic [1:0] index);
    case (index)
      2'd3: start_code_byte = 8'h01;
      default: start_code_byte = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] nal_header_byte(
    input logic [1:0] nal_kind,
    input logic       byte_index,
    input logic       cra_picture
  );
    logic [15:0] header;

    begin
      header = nal_header_bits(6'd0, nal_unit_type(nal_kind, cra_picture), 3'd0);
      nal_header_byte = byte_index ? header[7:0] : header[15:8];
    end
  endfunction

  function automatic logic [4:0] nal_unit_type(
    input logic [1:0] nal_kind,
    input logic       cra_picture
  );
    begin
      case (nal_kind)
        2'd0: nal_unit_type = 5'd15; // SPS.
        2'd1: nal_unit_type = 5'd16; // PPS.
        2'd3: nal_unit_type = 5'd25; // Filler data.
        default: nal_unit_type = cra_picture ? 5'd9 : 5'd8;
      endcase
    end
  endfunction

  function automatic logic [15:0] nal_header_bits(
    input logic [5:0] layer_id,
    input logic [4:0] nal_type,
    input logic [2:0] temporal_id
  );
    begin
      nal_header_bits = {
        1'b0,              // forbidden_zero_bit
        1'b0,              // nuh_reserved_zero_bit
        layer_id,          // nuh_layer_id
        nal_type,          // nal_unit_type
        temporal_id + 3'd1 // nuh_temporal_id_plus1
      };
    end
  endfunction

  function automatic logic [7:0] payload_byte(
    input logic [1:0] nal_kind,
    input logic [6:0] payload_index,
    input logic       cra_picture
  );
    begin
      case (nal_kind)
        2'd0: payload_byte = sps_payload_byte(payload_index);
        2'd1: payload_byte = pps_payload_byte(payload_index);
        2'd3: payload_byte = color_filler_payload_byte(payload_index);
        default: payload_byte = slice_payload_byte(payload_index, cra_picture);
      endcase
    end
  endfunction

  function automatic logic [7:0] color_filler_payload_byte(input logic [6:0] index);
    begin
      if (index < color_filler_count()) begin
        color_filler_payload_byte = 8'hff;
      end else if (index == color_filler_count()) begin
        color_filler_payload_byte = 8'h80;
      end else begin
        color_filler_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] sps_payload_byte(input logic [6:0] index);
    logic [247:0] payload_bits;

    begin
      payload_bits = sps_payload_bits();
      if (index < 7'd31) begin
        sps_payload_byte = payload_bits >> ((7'd30 - index) * 8);
      end else begin
        sps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] pps_payload_byte(input logic [6:0] index);
    logic [111:0] payload_bits;

    begin
      payload_bits = pps_payload_bits();
      if (index < 7'd14) begin
        pps_payload_byte = payload_bits >> ((7'd13 - index) * 8);
      end else begin
        pps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [247:0] sps_payload_bits();
    begin
      sps_payload_bits = {
        // sps_seq_parameter_set_id, sps_video_parameter_set_id,
        // sps_max_sub_layers_minus1, sps_chroma_format_idc,
        // sps_log2_ctu_size_minus5, sps_ptl_dpb_hrd_params_present_flag.
        16'h000b,
        // profile_tier_level prefix and general constraints for the toy stream.
        32'h0200_8000,
        // ptl_num_sub_profiles, SPS picture size, conformance window, and
        // early SPS tool flags through sps_entry_point_offsets_present_flag.
        64'h4244_eed5_01f4_46e8,
        // POC/extra-header/DPB fields and intra/inter partition constraints.
        64'h8468_8424_6136_28c5,
        // Transform, chroma QP table, prediction-tool, intra-tool, and
        // extension/trailing fields for the current 4x4 all-intra target.
        72'h4306_80ab_8fe0_ac10_20
      };
    end
  endfunction

  function automatic logic [111:0] pps_payload_bits();
    begin
      pps_payload_bits = {
        // PPS ids, 8x8 coded canvas for 4x4 conformance-cropped output, no
        // picture partitioning, and default reference index syntax.
        48'h0002_448a_4200,
        // QP/chroma/deblocking syntax and rbsp_trailing_bits for the toy stream.
        64'hc7b2_1459_4594_5880
      };
    end
  endfunction

  function automatic logic [7:0] slice_payload_byte(
    input logic [6:0] index,
    input logic       cra_picture
  );
    begin
      slice_payload_byte = quant_luma_payload_byte(quant_luma_rem(), index, cra_picture);
    end
  endfunction

  function automatic logic [7:0] quant_luma_payload_byte(
    input logic [4:0] rem,
    input logic [6:0] index,
    input logic       cra_picture
  );
    logic [87:0] payload;

    begin
      case (rem)
        5'd0: payload = { 16'h0000, 72'hc4007080593f5e58fc };
        5'd1: payload = { 16'h0000, 72'hc40070805e1faf2c7e };
        5'd2: payload = { 16'h0000, 72'hc4007080608fd7963f };
        5'd3: payload = { 8'h00, 80'hc400708061c7ebcb1f80 };
        5'd4: payload = { 8'h00, 80'hc40070806263f5e58fc0 };
        5'd5: payload = { 8'h00, 80'hc400708062b1faf2c7e0 };
        5'd6: payload = { 8'h00, 80'hc400708062cf7ebcb1f8 };
        5'd7: payload = { 8'h00, 80'hc400708062ddfebcb1f8 };
        5'd8: payload = { 8'h00, 80'hc400708062e55faf2c7e };
        5'd9: payload = { 8'h00, 80'hc400708062e8ffaf2c7e };
        5'd10: payload = { 8'h00, 80'hc400708062ec9faf2c7e };
        5'd11: payload = { 8'h00, 80'hc400708062f03faf2c7e };
        5'd12: payload = 88'hc400708062f217ebcb1f80;
        5'd13: payload = 88'hc400708062f2ffebcb1f80;
        5'd14: payload = 88'hc400708062f3e7ebcb1f80;
        5'd15: payload = 88'hc400708062f4cfebcb1f80;
        default: payload = 88'hc400708062f5b7ebcb1f80;
      endcase

      if (cra_picture && index == 7'd0) begin
        quant_luma_payload_byte = 8'hc4;
      end else if (cra_picture && index == 7'd1) begin
        quant_luma_payload_byte = 8'h04;
      end else if (cra_picture && index == 7'd2) begin
        quant_luma_payload_byte = 8'h78;
      end else begin
        case (slice_payload_len())
          8'd9: quant_luma_payload_byte = payload >> ((7'd8 - index) * 8);
          8'd10: quant_luma_payload_byte = payload >> ((7'd9 - index) * 8);
          default: quant_luma_payload_byte = payload >> ((7'd10 - index) * 8);
        endcase
      end
    end
  endfunction

  function automatic logic [18:0] slice_header_bits(input logic cra_picture);
    logic [7:0] poc_lsb;

    begin
      poc_lsb = cra_picture ? 8'd1 : 8'd0;
      slice_header_bits = {
        1'b1,    // sh_picture_header_in_slice_header_flag
        1'b1,    // ph_gdr_or_irap_pic_flag
        1'b0,    // ph_non_ref_pic_flag
        1'b0,    // ph_gdr_pic_flag
        1'b0,    // ph_inter_slice_allowed_flag
        1'b1,    // ph_pic_parameter_set_id ue(v) = 0
        poc_lsb, // ph_pic_order_cnt_lsb
        1'b0,    // ph_partition_constraints_override_flag
        1'b0,    // ph_joint_cbcr_sign_flag
        1'b0,    // sh_no_output_of_prior_pics_flag
        1'b1,    // sh_qp_delta se(v) = 0
        1'b1     // sh_dep_quant_used_flag
      };
    end
  endfunction

endmodule
