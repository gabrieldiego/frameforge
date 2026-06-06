`timescale 1ns/1ps

module ff_vvc_annexb_header #(
  parameter int CTU_SIZE = 64
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic [1:0]  chroma_format_idc,
  input  logic        sps_palette_enabled_flag,
  input  logic        sps_ref_pic_resampling_enabled_flag,
  input  logic        sps_entry_point_offsets_present_flag,
  input  logic        sps_transform_skip_enabled_flag,
  input  logic        sps_mts_enabled_flag,
  input  logic        sps_lfnst_enabled_flag,
  input  logic        sps_joint_cbcr_enabled_flag,
  input  logic        sps_mrl_enabled_flag,
  input  logic        sps_cclm_enabled_flag,
  input  logic        sps_dep_quant_enabled_flag,
  input  logic        sps_sign_data_hiding_enabled_flag,
  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic        done
);
  localparam logic [15:0] CODED_GRANULARITY = 16'd8;
  localparam logic [4:0] NAL_UNIT_TYPE_SPS = 5'd15;
  localparam logic [4:0] NAL_UNIT_TYPE_PPS = 5'd16;
  localparam logic [5:0] NAL_LAYER_ID = 6'd0;
  localparam logic [2:0] NAL_TEMPORAL_ID_PLUS1 = 3'd1;
  localparam logic [6:0] SPS_FIELD_COUNT = 7'd106;
  localparam logic [6:0] PPS_FIELD_COUNT = 7'd27;
  localparam logic [3:0] ST_IDLE = 4'd0;
  localparam logic [3:0] ST_START_CODE = 4'd1;
  localparam logic [3:0] ST_NAL_HEADER = 4'd2;
  localparam logic [3:0] ST_CLEAR_RBSP = 4'd3;
  localparam logic [3:0] ST_FIELDS = 4'd4;
  localparam logic [3:0] ST_TRAILING_STOP = 4'd5;
  localparam logic [3:0] ST_TRAILING_WAIT = 4'd6;
  localparam logic [3:0] ST_TRAILING_FLUSH = 4'd7;
  localparam logic [3:0] ST_DRAIN_RBSP = 4'd8;

  logic [3:0] state_q;
  logic       nal_is_pps_q;
  logic [2:0] byte_index_q;
  logic [15:0] field_index_q;
  logic       rbsp_clear_q;
  logic       rbsp_last_seen_q;

  logic [15:0] coded_width;
  logic [15:0] coded_height;
  logic [15:0] crop_right_offset;
  logic [15:0] crop_bottom_offset;
  logic [15:0] ctu_cols;
  logic [15:0] ctu_rows;
  logic [15:0] slice_count;
  logic        has_multiple_ctus;
  logic        sps_dual_tree_intra_flag;
  logic [6:0]  general_profile_idc;
  logic [31:0] ue_width_value;
  logic [31:0] ue_height_value;
  logic [31:0] ue_crop_right_value;
  logic [31:0] ue_crop_bottom_value;
  logic [31:0] ue_ctu_cols_minus1_value;
  logic [31:0] ue_ctu_rows_minus1_value;
  logic [31:0] ue_slice_count_minus1_value;
  logic [5:0]  ue_width_bits;
  logic [5:0]  ue_height_bits;
  logic [5:0]  ue_crop_right_bits;
  logic [5:0]  ue_crop_bottom_bits;
  logic [5:0]  ue_ctu_cols_minus1_bits;
  logic [5:0]  ue_ctu_rows_minus1_bits;
  logic [5:0]  ue_slice_count_minus1_bits;

  logic [31:0] syntax_value;
  logic [5:0]  syntax_bits;
  logic [15:0] syntax_field_count;
  logic [15:0] pps_multi_field_count;
  logic [15:0] pps_slice_geometry_field_count;
  logic [15:0] pps_multi_index;
  logic [15:0] pps_after_tiles_index;
  logic [15:0] pps_post_index;
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
  logic [2:0]  bit_writer_partial_bits;
  logic        bit_writer_idle;
  logic        rbsp_valid;
  logic        rbsp_ready;
  logic [7:0]  rbsp_data;
  logic        rbsp_last;
  logic        direct_valid;
  logic [7:0]  direct_data;
  logic        rbsp_output_active;

  assign coded_width = (visible_width + CODED_GRANULARITY - 16'd1) & ~(CODED_GRANULARITY - 16'd1);
  assign coded_height = (visible_height + CODED_GRANULARITY - 16'd1) & ~(CODED_GRANULARITY - 16'd1);
  assign ctu_cols = (coded_width + 16'd63) >> 6;
  assign ctu_rows = (coded_height + 16'd63) >> 6;
  always @* begin
    case (ctu_rows[4:0])
      5'd0: slice_count = 16'd0;
      5'd1: slice_count = ctu_cols;
      5'd2: slice_count = ctu_cols << 1;
      5'd3: slice_count = (ctu_cols << 1) + ctu_cols;
      5'd4: slice_count = ctu_cols << 2;
      5'd5: slice_count = (ctu_cols << 2) + ctu_cols;
      5'd6: slice_count = (ctu_cols << 2) + (ctu_cols << 1);
      5'd7: slice_count = (ctu_cols << 3) - ctu_cols;
      5'd8: slice_count = ctu_cols << 3;
      5'd9: slice_count = (ctu_cols << 3) + ctu_cols;
      5'd10: slice_count = (ctu_cols << 3) + (ctu_cols << 1);
      5'd11: slice_count = (ctu_cols << 3) + (ctu_cols << 1) + ctu_cols;
      5'd12: slice_count = (ctu_cols << 3) + (ctu_cols << 2);
      5'd13: slice_count = (ctu_cols << 3) + (ctu_cols << 2) + ctu_cols;
      5'd14: slice_count = (ctu_cols << 4) - (ctu_cols << 1);
      5'd15: slice_count = (ctu_cols << 4) - ctu_cols;
      5'd16: slice_count = ctu_cols << 4;
      default: slice_count = 16'd0;
    endcase
  end
  assign has_multiple_ctus = slice_count > 16'd1;
  assign crop_right_offset =
    ((chroma_format_idc == 2'd1) || (chroma_format_idc == 2'd2)) ?
    ((coded_width - visible_width) >> 1) : (coded_width - visible_width);
  assign crop_bottom_offset =
    (chroma_format_idc == 2'd1) ?
    ((coded_height - visible_height) >> 1) : (coded_height - visible_height);
  // The Rust reference selects single-tree partitioning for 4:4:4 palette and
  // dual-tree partitioning for the current 4:2:0 residual subset. Palette is a
  // CU prediction mode below the tree, not itself the tree selector.
  assign sps_dual_tree_intra_flag = chroma_format_idc != 2'd3;
  assign general_profile_idc =
    ((chroma_format_idc == 2'd3) || sps_palette_enabled_flag) ? 7'd0 : 7'd1;
  assign syntax_field_count = nal_is_pps_q ?
    (has_multiple_ctus ? pps_multi_field_count : PPS_FIELD_COUNT) :
    SPS_FIELD_COUNT;
  assign syntax_fields_done = field_index_q >= syntax_field_count;
  // With one tile per CTU and one rectangular slice per tile, VVC PPS
  // rectangular-slice geometry emits ue(0) for every non-final tile-column
  // width in each CTU row and ue(0) for every non-final tile-row height.
  // This is equivalent to the previous CTU scan, but avoids synthesizing
  // a modulo/divide search tree over the configured maximum CTU count.
  assign pps_slice_geometry_field_count =
    (slice_count == 16'd0) ? 16'd0 : (slice_count - 16'd1);
  // Multi-CTU PPS fields:
  // 13 fields through pps_num_exp_tile_rows_minus1,
  // one ue(0) per tile column and row,
  // five fixed partition/slice fields through pps_tile_idx_delta_present_flag
  // (the tile-delta flag is zero-width when the spec gates it off),
  // geometry fields for rectangular slices,
  // one loop-filter-across-slices flag,
  // then 26 post-partition fields through pps_extension_flag. The deblocking
  // offset syntax is gated off because pps_deblocking_filter_disabled_flag=1.
  assign pps_multi_field_count =
    16'd45 + ctu_cols + ctu_rows + pps_slice_geometry_field_count;
  assign rbsp_output_active =
    (state_q == ST_FIELDS) ||
    (state_q == ST_TRAILING_STOP) ||
    (state_q == ST_TRAILING_WAIT) ||
    (state_q == ST_TRAILING_FLUSH) ||
    (state_q == ST_DRAIN_RBSP);

  ff_vvc_ue_code ue_width (
    .value(coded_width),
    .code_value(ue_width_value),
    .bit_count(ue_width_bits)
  );

  ff_vvc_ue_code ue_height (
    .value(coded_height),
    .code_value(ue_height_value),
    .bit_count(ue_height_bits)
  );

  ff_vvc_ue_code ue_crop_right (
    .value(crop_right_offset),
    .code_value(ue_crop_right_value),
    .bit_count(ue_crop_right_bits)
  );

  ff_vvc_ue_code ue_crop_bottom (
    .value(crop_bottom_offset),
    .code_value(ue_crop_bottom_value),
    .bit_count(ue_crop_bottom_bits)
  );

  ff_vvc_ue_code ue_ctu_cols_minus1 (
    .value(ctu_cols - 16'd1),
    .code_value(ue_ctu_cols_minus1_value),
    .bit_count(ue_ctu_cols_minus1_bits)
  );

  ff_vvc_ue_code ue_ctu_rows_minus1 (
    .value(ctu_rows - 16'd1),
    .code_value(ue_ctu_rows_minus1_value),
    .bit_count(ue_ctu_rows_minus1_bits)
  );

  ff_vvc_ue_code ue_slice_count_minus1 (
    .value(slice_count - 16'd1),
    .code_value(ue_slice_count_minus1_value),
    .bit_count(ue_slice_count_minus1_bits)
  );

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
    .partial_bit_count(bit_writer_partial_bits),
    .idle(bit_writer_idle),
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
      {nal_is_pps_q ? NAL_UNIT_TYPE_PPS : NAL_UNIT_TYPE_SPS, NAL_TEMPORAL_ID_PLUS1});
  assign rbsp_ready = rbsp_output_active && m_axis_ready;
  assign m_axis_valid = direct_valid ? 1'b1 : (rbsp_output_active && rbsp_valid);
  assign m_axis_data = direct_valid ? direct_data : rbsp_data;
  assign m_axis_last = rbsp_output_active && rbsp_valid && rbsp_last && nal_is_pps_q;

  always @* begin
    syntax_value = 32'd0;
    syntax_bits = 6'd0;
    pps_multi_index = 16'd0;
    pps_after_tiles_index = 16'd0;
    pps_post_index = 16'd0;

    if (!nal_is_pps_q) begin
      case (field_index_q)
        7'd0: begin syntax_value = 32'd0; syntax_bits = 6'd4; end  // sps_seq_parameter_set_id
        7'd1: begin syntax_value = 32'd0; syntax_bits = 6'd4; end  // sps_video_parameter_set_id
        7'd2: begin syntax_value = 32'd0; syntax_bits = 6'd3; end  // sps_max_sub_layers_minus1
        7'd3: begin syntax_value = {30'd0, chroma_format_idc}; syntax_bits = 6'd2; end  // sps_chroma_format_idc
        7'd4: begin syntax_value = 32'd1; syntax_bits = 6'd2; end  // sps_log2_ctu_size_minus5
        7'd5: begin syntax_value = 32'd1; syntax_bits = 6'd1; end  // sps_ptl_dpb_hrd_params_present_flag
        7'd6: begin syntax_value = {25'd0, general_profile_idc}; syntax_bits = 6'd7; end  // general_profile_idc
        7'd7: begin syntax_value = 32'd0; syntax_bits = 6'd1; end  // general_tier_flag
        7'd8: begin syntax_value = 32'd0; syntax_bits = 6'd8; end  // general_level_idc
        7'd9: begin syntax_value = 32'd1; syntax_bits = 6'd1; end  // ptl_frame_only_constraint_flag
        7'd10: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ptl_multilayer_enabled_flag
        7'd11: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // gci_present_flag
        7'd12: begin syntax_value = 32'd0; syntax_bits = 6'd5; end // gci_alignment_zero_bit[0..4]
        7'd13: begin syntax_value = 32'd0; syntax_bits = 6'd8; end // ptl_num_sub_profiles
        7'd14: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_gdr_enabled_flag
        7'd15: begin syntax_value = {31'd0, sps_ref_pic_resampling_enabled_flag}; syntax_bits = 6'd1; end // sps_ref_pic_resampling_enabled_flag
        7'd16: begin syntax_value = 32'd0; syntax_bits = sps_ref_pic_resampling_enabled_flag ? 6'd1 : 6'd0; end // sps_res_change_in_clvs_allowed_flag
        7'd17: begin syntax_value = ue_width_value; syntax_bits = ue_width_bits; end
        7'd18: begin syntax_value = ue_height_value; syntax_bits = ue_height_bits; end
        7'd19: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // sps_conformance_window_flag
        7'd20: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // sps_conf_win_left_offset ue(0)
        7'd21: begin syntax_value = ue_crop_right_value; syntax_bits = ue_crop_right_bits; end
        7'd22: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // sps_conf_win_top_offset ue(0)
        7'd23: begin syntax_value = ue_crop_bottom_value; syntax_bits = ue_crop_bottom_bits; end
        7'd24: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_subpic_info_present_flag
        7'd25: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // sps_bitdepth_minus8 ue(0)
        7'd26: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_entropy_coding_sync_enabled_flag
        7'd27: begin syntax_value = {31'd0, sps_entry_point_offsets_present_flag}; syntax_bits = 6'd1; end // sps_entry_point_offsets_present_flag
        7'd28: begin syntax_value = 32'd12; syntax_bits = 6'd4; end // sps_log2_max_pic_order_cnt_lsb_minus4
        7'd29: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_poc_msb_cycle_flag
        7'd30: begin syntax_value = 32'd0; syntax_bits = 6'd2; end // sps_num_extra_ph_bytes
        7'd31: begin syntax_value = 32'd0; syntax_bits = 6'd2; end // sps_num_extra_sh_bytes
        7'd32, 7'd33, 7'd34, 7'd35: begin syntax_value = 32'd1; syntax_bits = 6'd1; end
        7'd36: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // sps_partition_constraints_override_enabled_flag
        7'd37: begin syntax_value = 32'd2; syntax_bits = 6'd3; end // ue(1)
        7'd38: begin syntax_value = 32'd4; syntax_bits = 6'd5; end // ue(3)
        7'd39: begin syntax_value = 32'd3; syntax_bits = 6'd3; end // ue(2)
        7'd40: begin syntax_value = 32'd3; syntax_bits = 6'd3; end // ue(2)
        7'd41: begin syntax_value = {31'd0, sps_dual_tree_intra_flag}; syntax_bits = 6'd1; end // sps_qtbtt_dual_tree_intra_flag
        7'd42: begin syntax_value = 32'd2; syntax_bits = sps_dual_tree_intra_flag ? 6'd3 : 6'd0; end // chroma ue(1)
        7'd43: begin syntax_value = 32'd4; syntax_bits = sps_dual_tree_intra_flag ? 6'd5 : 6'd0; end // chroma ue(3)
        7'd44: begin syntax_value = 32'd4; syntax_bits = sps_dual_tree_intra_flag ? 6'd5 : 6'd0; end // chroma ue(3)
        7'd45: begin syntax_value = 32'd3; syntax_bits = sps_dual_tree_intra_flag ? 6'd3 : 6'd0; end // chroma ue(2)
        7'd46: begin syntax_value = 32'd2; syntax_bits = 6'd3; end // inter ue(1)
        7'd47: begin syntax_value = 32'd4; syntax_bits = 6'd5; end // inter ue(3)
        7'd48: begin syntax_value = 32'd4; syntax_bits = 6'd5; end // inter ue(3)
        7'd49: begin syntax_value = 32'd4; syntax_bits = 6'd5; end // inter ue(3)
        7'd50: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // sps_max_luma_transform_size_64_flag
        7'd51: begin syntax_value = {31'd0, sps_transform_skip_enabled_flag}; syntax_bits = 6'd1; end // sps_transform_skip_enabled_flag
        7'd52: begin syntax_value = {31'd0, sps_mts_enabled_flag}; syntax_bits = 6'd1; end // sps_mts_enabled_flag
        7'd53: begin syntax_value = {31'd0, sps_lfnst_enabled_flag}; syntax_bits = 6'd1; end // sps_lfnst_enabled_flag
        7'd54: begin syntax_value = {31'd0, sps_joint_cbcr_enabled_flag}; syntax_bits = 6'd1; end // sps_joint_cbcr_enabled_flag
        7'd55: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // same qp table
        7'd56: begin syntax_value = 32'd19; syntax_bits = 6'd9; end // se(-9)
        7'd57: begin syntax_value = 32'd3; syntax_bits = 6'd3; end // ue(2)
        7'd58: begin syntax_value = 32'd10; syntax_bits = 6'd7; end // ue(9)
        7'd59: begin syntax_value = 32'd6; syntax_bits = 6'd5; end // ue(5)
        7'd60: begin syntax_value = 32'd5; syntax_bits = 6'd5; end // ue(4)
        7'd61: begin syntax_value = 32'd2; syntax_bits = 6'd3; end // ue(1)
        7'd62: begin syntax_value = 32'd12; syntax_bits = 6'd7; end // ue(11)
        7'd63: begin syntax_value = 32'd13; syntax_bits = 6'd7; end // ue(12)
        7'd64, 7'd65, 7'd66, 7'd67, 7'd68, 7'd69, 7'd70: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
        7'd71: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // sps_rpl1_same_as_rpl0_flag
        7'd72: begin syntax_value = 32'd2; syntax_bits = 6'd3; end // sps_num_ref_pic_lists[0] ue(1)
        7'd73: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // num_ref_entries ue(0)
        7'd74: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ref wraparound
        7'd75: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_temporal_mvp_enabled_flag
        7'd76: begin syntax_value = 32'd0; syntax_bits = 6'd0; end // sps_sbtmvp_enabled_flag gated off
        7'd77: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_amvr_enabled_flag
        7'd78: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // bdof
        7'd79: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // smvd
        7'd80: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // dmvr
        7'd81: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_mmvd_enabled_flag
        7'd82: begin syntax_value = 32'd0; syntax_bits = 6'd0; end // sps_mmvd_fullpel_only_flag gated off
        7'd83: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // six_minus_max_num_merge_cand ue(0)
        7'd84: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_sbt_enabled_flag
        7'd85: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // sps_affine_enabled_flag
        7'd86: begin syntax_value = 32'd0; syntax_bits = 6'd0; end // sps_five_minus_max_num_subblock_merge_cand gated off
        7'd87: begin syntax_value = 32'd0; syntax_bits = 6'd0; end // sps_affine_type_flag gated off
        7'd88, 7'd89: begin syntax_value = 32'd0; syntax_bits = 6'd0; end // gated affine subfields
        7'd90, 7'd91, 7'd92: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // bcw, ciip, gpm
        7'd93: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // log2_parallel_merge_level_minus2 ue(0)
        7'd94: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // isp
        7'd95: begin syntax_value = {31'd0, sps_mrl_enabled_flag}; syntax_bits = 6'd1; end // sps_mrl_enabled_flag
        7'd96: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // mip
        7'd97: begin syntax_value = {31'd0, sps_cclm_enabled_flag}; syntax_bits = (chroma_format_idc != 2'd0) ? 6'd1 : 6'd0; end // sps_cclm_enabled_flag
        7'd98: begin syntax_value = 32'd1; syntax_bits = (chroma_format_idc == 2'd1) ? 6'd1 : 6'd0; end // chroma horizontal collocated
        7'd99: begin syntax_value = 32'd0; syntax_bits = (chroma_format_idc == 2'd1) ? 6'd1 : 6'd0; end // chroma vertical collocated
        7'd100: begin syntax_value = {31'd0, sps_palette_enabled_flag}; syntax_bits = 6'd1; end // palette enabled
        7'd101: begin syntax_value = 32'd1; syntax_bits = sps_palette_enabled_flag ? 6'd1 : 6'd0; end // sps_internal_bit_depth_minus_input_bit_depth ue(0)
        7'd102: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ibc
        7'd103: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ladf
        7'd104: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // scaling list
        7'd105: begin syntax_value = {25'd0, sps_dep_quant_enabled_flag, sps_sign_data_hiding_enabled_flag, 5'b00000}; syntax_bits = 6'd7; end // dep/sign through extension flags
        default: begin syntax_value = 32'd0; syntax_bits = 6'd0; end
      endcase
    end else begin
      if (!has_multiple_ctus) begin
        case (field_index_q)
          7'd0: begin syntax_value = 32'd0; syntax_bits = 6'd6; end  // pps_pic_parameter_set_id
          7'd1: begin syntax_value = 32'd0; syntax_bits = 6'd4; end  // pps_seq_parameter_set_id
          7'd2: begin syntax_value = 32'd0; syntax_bits = 6'd1; end  // pps_mixed_nalu_types_in_pic_flag
          7'd3: begin syntax_value = ue_width_value; syntax_bits = ue_width_bits; end
          7'd4: begin syntax_value = ue_height_value; syntax_bits = ue_height_bits; end
          7'd5: begin syntax_value = 32'b000100; syntax_bits = 6'd6; end // conformance through pps_cabac_init_present_flag
          7'd6: begin syntax_value = 32'd4; syntax_bits = 6'd5; end // num_ref_idx_default_active_minus1[0] ue(3)
          7'd7: begin syntax_value = 32'd4; syntax_bits = 6'd5; end // num_ref_idx_default_active_minus1[1] ue(3)
          7'd8: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // pps_rpl1_idx_present_flag
          7'd9: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // weighted pred
          7'd10: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // weighted bipred
          7'd11: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // ref wraparound
          7'd12: begin syntax_value = 32'd12; syntax_bits = 6'd7; end // pps_init_qp_minus26 se(6)
          7'd13: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // cu qp delta
          7'd14: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // chroma tool offsets present
          7'd15: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // cb qp offset se(0)
          7'd16: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // cr qp offset se(0)
          7'd17: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // joint cbcr offset present
          7'd18: begin syntax_value = 32'd3; syntax_bits = 6'd3; end // joint cbcr qp offset se(-1)
          7'd19: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // slice chroma offsets
          7'd20: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // cu chroma qp offset list
          7'd21: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // deblocking filter control present
          7'd22: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // deblocking override
          7'd23: begin syntax_value = 32'd1; syntax_bits = 6'd1; end // deblocking disabled
          7'd24: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // picture header extension
          7'd25: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // slice header extension
          7'd26: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // pps_extension_flag
          default: begin syntax_value = 32'd0; syntax_bits = 6'd0; end
        endcase
      end else begin
        pps_multi_index = field_index_q;

        if (pps_multi_index <= 16'd4) begin
          case (field_index_q)
            7'd0: begin syntax_value = 32'd0; syntax_bits = 6'd6; end
            7'd1: begin syntax_value = 32'd0; syntax_bits = 6'd4; end
            7'd2: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
            7'd3: begin syntax_value = ue_width_value; syntax_bits = ue_width_bits; end
            7'd4: begin syntax_value = ue_height_value; syntax_bits = ue_height_bits; end
            default: begin syntax_value = 32'd0; syntax_bits = 6'd0; end
          endcase
        end else if (pps_multi_index <= 16'd9) begin
          case (pps_multi_index - 16'd5)
            16'd0: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // pps_conformance_window_flag
            16'd1: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // pps_scaling_window_explicit_signalling_flag
            16'd2: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // pps_output_flag_present_flag
            16'd3: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // pps_no_pic_partition_flag
            16'd4: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // pps_subpic_id_mapping_present_flag
            default: begin syntax_value = 32'd0; syntax_bits = 6'd0; end
          endcase
        end else if (pps_multi_index == 16'd10) begin
          syntax_value = 32'd1;
          syntax_bits = 6'd2; // pps_log2_ctu_size_minus5
        end else if (pps_multi_index == 16'd11) begin
          syntax_value = ue_ctu_cols_minus1_value;
          syntax_bits = ue_ctu_cols_minus1_bits;
        end else if (pps_multi_index == 16'd12) begin
          syntax_value = ue_ctu_rows_minus1_value;
          syntax_bits = ue_ctu_rows_minus1_bits;
        end else if (pps_multi_index < (16'd13 + ctu_cols)) begin
          syntax_value = 32'd1;
          syntax_bits = 6'd1; // pps_tile_column_width_minus1[i] ue(0)
        end else if (pps_multi_index < (16'd13 + ctu_cols + ctu_rows)) begin
          syntax_value = 32'd1;
          syntax_bits = 6'd1; // pps_tile_row_height_minus1[i] ue(0)
        end else begin
          pps_after_tiles_index = pps_multi_index - (16'd13 + ctu_cols + ctu_rows);
          if (pps_after_tiles_index == 16'd0) begin
            syntax_value = 32'd0; syntax_bits = 6'd1; // pps_loop_filter_across_tiles_enabled_flag
          end else if (pps_after_tiles_index == 16'd1) begin
            syntax_value = 32'd1; syntax_bits = 6'd1; // pps_rect_slice_flag
          end else if (pps_after_tiles_index == 16'd2) begin
            syntax_value = 32'd0; syntax_bits = 6'd1; // pps_single_slice_per_subpic_flag
          end else if (pps_after_tiles_index == 16'd3) begin
            syntax_value = ue_slice_count_minus1_value;
            syntax_bits = ue_slice_count_minus1_bits;
          end else if (pps_after_tiles_index == 16'd4) begin
            syntax_value = 32'd0;
            syntax_bits = ((slice_count - 16'd1) > 16'd1) ? 6'd1 : 6'd0;
          end else if (pps_after_tiles_index < (16'd5 + pps_slice_geometry_field_count)) begin
            syntax_value = 32'd1;
            syntax_bits = 6'd1; // rectangular-slice geometry ue(0)
          end else if (pps_after_tiles_index == (16'd5 + pps_slice_geometry_field_count)) begin
            syntax_value = 32'd0; syntax_bits = 6'd1; // pps_loop_filter_across_slices_enabled_flag
          end else begin
            pps_post_index = pps_after_tiles_index - (16'd6 + pps_slice_geometry_field_count);
            case (pps_post_index)
              16'd0: begin syntax_value = 32'd0; syntax_bits = 6'd1; end // pps_cabac_init_present_flag
              16'd1: begin syntax_value = 32'd4; syntax_bits = 6'd5; end
              16'd2: begin syntax_value = 32'd4; syntax_bits = 6'd5; end
              16'd3: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd4: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd5: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd6: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd7: begin syntax_value = 32'd12; syntax_bits = 6'd7; end
              16'd8: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd9: begin syntax_value = 32'd1; syntax_bits = 6'd1; end
              16'd10: begin syntax_value = 32'd1; syntax_bits = 6'd1; end
              16'd11: begin syntax_value = 32'd1; syntax_bits = 6'd1; end
              16'd12: begin syntax_value = 32'd1; syntax_bits = 6'd1; end
              16'd13: begin syntax_value = 32'd3; syntax_bits = 6'd3; end
              16'd14: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd15: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd16: begin syntax_value = 32'd1; syntax_bits = 6'd1; end
              16'd17: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd18: begin syntax_value = 32'd1; syntax_bits = 6'd1; end
              16'd19, 16'd20, 16'd21, 16'd22: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd23: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd24: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              16'd25: begin syntax_value = 32'd0; syntax_bits = 6'd1; end
              default: begin syntax_value = 32'd0; syntax_bits = 6'd0; end
            endcase
          end
        end
      end
    end
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
      nal_is_pps_q <= 1'b0;
      byte_index_q <= 3'd0;
      field_index_q <= 16'd0;
      rbsp_clear_q <= 1'b0;
      rbsp_last_seen_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      nal_is_pps_q <= 1'b0;
      byte_index_q <= 3'd0;
      field_index_q <= 16'd0;
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
            nal_is_pps_q <= 1'b0;
            byte_index_q <= 3'd0;
            field_index_q <= 16'd0;
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
              field_index_q <= 16'd0;
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
            field_index_q <= field_index_q + 16'd1;
          end else if (bit_writer_valid && bit_writer_ready) begin
            field_index_q <= field_index_q + 16'd1;
          end
        end

        ST_TRAILING_STOP: begin
          if (bit_writer_valid && bit_writer_ready) begin
            state_q <= ST_TRAILING_WAIT;
          end
        end

        ST_TRAILING_WAIT: begin
          if (bit_writer_idle) begin
            if (bit_writer_partial_bits == 3'd0) begin
              state_q <= ST_DRAIN_RBSP;
            end else begin
              state_q <= ST_TRAILING_FLUSH;
            end
          end
        end

        ST_TRAILING_FLUSH: begin
          if (bit_writer_valid && bit_writer_ready) begin
            state_q <= ST_DRAIN_RBSP;
          end
        end

        ST_DRAIN_RBSP: begin
          if (rbsp_last_seen_q || (rbsp_valid && rbsp_ready && rbsp_last)) begin
            if (nal_is_pps_q) begin
              done <= 1'b1;
              state_q <= ST_IDLE;
            end else begin
              nal_is_pps_q <= 1'b1;
              byte_index_q <= 3'd0;
              field_index_q <= 16'd0;
              rbsp_last_seen_q <= 1'b0;
              state_q <= ST_START_CODE;
            end
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
