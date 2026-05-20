`timescale 1ns/1ps

module ff_vvc_toy4x4_encoder (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [1:0] frame_count,
  output logic       busy,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int SPS_PAYLOAD_LEN  = 31;
  localparam int PPS_PAYLOAD_LEN  = 14;
  localparam int SLICE_PAYLOAD_LEN = 11;
  localparam int NAL_OVERHEAD_LEN = 6;
  localparam int SPS_NAL_LEN = NAL_OVERHEAD_LEN + SPS_PAYLOAD_LEN;
  localparam int PPS_NAL_LEN = NAL_OVERHEAD_LEN + PPS_PAYLOAD_LEN;
  localparam int SLICE_NAL_LEN = NAL_OVERHEAD_LEN + SLICE_PAYLOAD_LEN;
  localparam int PARAMETER_SET_LEN = SPS_NAL_LEN + PPS_NAL_LEN;

  logic [7:0] index_q;
  logic [7:0] stream_len_q;

  assign busy = m_axis_valid || (index_q != 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q      <= '0;
      stream_len_q <= '0;
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
    end else begin
      if (start && !busy) begin
        m_axis_valid <= 1'b1;
        m_axis_data  <= stream_byte(8'd0);
        m_axis_last  <= 1'b0;
        index_q      <= 8'd1;
        stream_len_q <= stream_len(frame_count);
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

  function automatic logic [7:0] stream_len(input logic [1:0] frames);
    case (frames)
      2'd2: stream_len = PARAMETER_SET_LEN + (SLICE_NAL_LEN * 2);
      default: stream_len = PARAMETER_SET_LEN + SLICE_NAL_LEN;
    endcase
  endfunction

  function automatic logic [7:0] stream_byte(input logic [7:0] index);
    logic second_picture;
    logic [6:0] slice_index;

    begin
      if (index < SPS_NAL_LEN) begin
        stream_byte = nal_byte(2'd0, index[6:0], 1'b0);
      end else if (index < PARAMETER_SET_LEN) begin
        stream_byte = nal_byte(2'd1, index - SPS_NAL_LEN, 1'b0);
      end else begin
        second_picture = (index >= PARAMETER_SET_LEN + SLICE_NAL_LEN);
        slice_index = second_picture
          ? (index - (PARAMETER_SET_LEN + SLICE_NAL_LEN))
          : (index - PARAMETER_SET_LEN);
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
        default: payload_byte = slice_payload_byte(payload_index, cra_picture);
      endcase
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
    logic [87:0] payload_bits;

    begin
      payload_bits = {slice_header_bits(cra_picture), toy_cabac_packet_bits(cra_picture)};
      if (index < 7'd11) begin
        slice_payload_byte = payload_bits >> ((7'd10 - index) * 8);
      end else begin
        slice_payload_byte = 8'h00;
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

  function automatic logic [68:0] toy_cabac_packet_bits(input logic cra_picture);
    begin
      toy_cabac_packet_bits = {
        toy_luma_split_cu_prefix(cra_picture),
        toy_luma_intra_prediction_bits(),
        toy_luma_transform_unit_prefix(),
        toy_luma_residual_prefix(),
        toy_luma_residual_suffix_ep(),
        toy_chroma_tree_prefix(),
        toy_chroma_residual_prefix(),
        toy_cabac_alignment_bits()
      };
    end
  endfunction

  function automatic logic [3:0] toy_luma_split_cu_prefix(input logic cra_picture);
    begin
      toy_luma_split_cu_prefix = cra_picture ? 4'b1100 : 4'b1000;
    end
  endfunction

  function automatic logic [3:0] toy_luma_intra_prediction_bits();
    begin
      toy_luma_intra_prediction_bits = 4'b0100;
    end
  endfunction

  function automatic logic [7:0] toy_luma_transform_unit_prefix();
    begin
      toy_luma_transform_unit_prefix = 8'h03;
    end
  endfunction

  function automatic logic [15:0] toy_luma_residual_prefix();
    begin
      toy_luma_residual_prefix = 16'h17ad;
    end
  endfunction

  function automatic logic [15:0] toy_luma_residual_suffix_ep();
    begin
      toy_luma_residual_suffix_ep = 16'hbf5e;
    end
  endfunction

  function automatic logic [7:0] toy_chroma_tree_prefix();
    begin
      toy_chroma_tree_prefix = 8'h58;
    end
  endfunction

  function automatic logic [7:0] toy_chroma_residual_prefix();
    begin
      toy_chroma_residual_prefix = 8'hfc;
    end
  endfunction

  function automatic logic [4:0] toy_cabac_alignment_bits();
    begin
      toy_cabac_alignment_bits = 5'b00000;
    end
  endfunction

endmodule
