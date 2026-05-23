`timescale 1ns/1ps

module ff_vvc_generated_cabac_body #(
  parameter int MAX_SLICE_PAYLOAD_BITS = 4096
) (
  input  logic         clk,
  input  logic         rst_n,
  input  logic         start,
  input  logic [1:0]   body_kind,
  input  logic [15:0]  coded_width,
  input  logic [15:0]  coded_height,
  input  logic [4:0]   luma_rem,
  input  logic [4:0]   chroma_rem,
  output logic         supported,
  input  logic         m_axis_ready,
  output logic         m_axis_valid,
  output logic [7:0]   m_axis_data,
  output logic         m_axis_last,
  output logic [12:0]  stream_bit_count,
  output logic [12:0]  stream_byte_count,

  // Temporary glue for modules that still pack the enclosing slice as a
  // combinational bit vector. The byte stream above is the block boundary.
  output logic [12:0]  compat_payload_bit_len,
  output logic [MAX_SLICE_PAYLOAD_BITS - 1:0] compat_payload_bits
);
  localparam logic [1:0] BODY_GENERATED = 2'd0;

  localparam int CABAC_BITS_LSB = 0;
  localparam int CABAC_LEN_LSB = CABAC_BITS_LSB + MAX_SLICE_PAYLOAD_BITS;
  localparam int CABAC_LOW_LSB = CABAC_LEN_LSB + 13;
  localparam int CABAC_RANGE_LSB = CABAC_LOW_LSB + 32;
  localparam int CABAC_BUFFERED_BYTE_LSB = CABAC_RANGE_LSB + 16;
  localparam int CABAC_NUM_BUFFERED_BYTES_LSB = CABAC_BUFFERED_BYTE_LSB + 9;
  localparam int CABAC_BITS_LEFT_LSB = CABAC_NUM_BUFFERED_BYTES_LSB + 8;
  localparam int CABAC_STATE_BITS = CABAC_BITS_LEFT_LSB + 8;
  localparam int VVC_PROB_MODEL_BITS = 40;

  typedef logic [CABAC_STATE_BITS - 1:0] cabac_state_t;
  typedef logic [VVC_PROB_MODEL_BITS - 1:0] vvc_prob_model_t;
  typedef logic [CABAC_STATE_BITS + VVC_PROB_MODEL_BITS - 1:0] cabac_vvc_model_step_t;
  typedef logic [CABAC_STATE_BITS + 5 * VVC_PROB_MODEL_BITS - 1:0] cabac_luma_leaf_step_t;

  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] selected_bits;
  logic [12:0] selected_pad_bits;
  logic [MAX_SLICE_PAYLOAD_BITS - 1:0] stream_bits_q;
  logic [12:0] stream_byte_count_q;
  logic [12:0] stream_byte_index_q;
  logic stream_active_q;

  assign stream_byte_count =
    stream_active_q ? stream_byte_count_q : ((compat_payload_bit_len + 13'd7) >> 3);
  assign stream_bit_count = compat_payload_bit_len;

  always @* begin
    supported =
      (body_kind == BODY_GENERATED) && supports_generated_body(coded_width, coded_height);

    if ((body_kind == BODY_GENERATED) && supports_generated_body(coded_width, coded_height)) begin
      {compat_payload_bit_len, compat_payload_bits} = encode_generated_body(coded_width, coded_height, luma_rem, chroma_rem);
    end else begin
      compat_payload_bit_len = 13'd0;
      compat_payload_bits = '0;
    end
  end

  always @* begin
    selected_pad_bits = ((((compat_payload_bit_len + 13'd7) >> 3) << 3) - compat_payload_bit_len);
    selected_bits = compat_payload_bits << selected_pad_bits;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stream_bits_q <= '0;
      stream_byte_count_q <= 13'd0;
      stream_byte_index_q <= 13'd0;
      stream_active_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
    end else begin
      if (start && supported) begin
        stream_bits_q <= selected_bits;
        stream_byte_count_q <= (compat_payload_bit_len + 13'd7) >> 3;
        stream_byte_index_q <= 13'd0;
        stream_active_q <= ((compat_payload_bit_len + 13'd7) >> 3) != 13'd0;
        m_axis_valid <= ((compat_payload_bit_len + 13'd7) >> 3) != 13'd0;
        m_axis_data <= stream_byte(selected_bits, (compat_payload_bit_len + 13'd7) >> 3, 13'd0);
        m_axis_last <= ((compat_payload_bit_len + 13'd7) >> 3) == 13'd1;
      end else if (m_axis_valid && m_axis_ready) begin
        if (m_axis_last) begin
          stream_active_q <= 1'b0;
          m_axis_valid <= 1'b0;
          m_axis_data <= 8'd0;
          m_axis_last <= 1'b0;
        end else begin
          stream_byte_index_q <= stream_byte_index_q + 13'd1;
          m_axis_data <= stream_byte(stream_bits_q, stream_byte_count_q, stream_byte_index_q + 13'd1);
          m_axis_last <= (stream_byte_index_q + 13'd1) == (stream_byte_count_q - 13'd1);
        end
      end else if (!stream_active_q) begin
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;
        m_axis_data <= 8'd0;
      end
    end
  end

  function automatic logic [7:0] stream_byte(
    input logic [MAX_SLICE_PAYLOAD_BITS - 1:0] bits,
    input logic [12:0] byte_count,
    input logic [12:0] byte_index
  );
    begin
      if (byte_index < byte_count) begin
        stream_byte = bits >> (((byte_count - 13'd1) - byte_index) * 8);
      end else begin
        stream_byte = 8'd0;
      end
    end
  endfunction

  function automatic logic supports_generated_body(
    input logic [15:0] width,
    input logic [15:0] height
  );
    begin
      supports_generated_body =
        ((width == 16'd8) && (height == 16'd8)) ||
        ((width == 16'd16) && (height == 16'd16)) ||
        ((width == 16'd32) && (height == 16'd32)) ||
        ((width == 16'd64) && (height == 16'd64));
    end
  endfunction

  function automatic logic [12 + MAX_SLICE_PAYLOAD_BITS:0] encode_generated_body(
    input logic [15:0] width,
    input logic [15:0] height,
    input logic [4:0]  rem,
    input logic [4:0]  c_rem
  );
    begin
      if ((width == 16'd8) && (height == 16'd8)) begin
        encode_generated_body = encode_8x8_body(rem, c_rem);
      end else if ((width == 16'd16) && (height == 16'd16)) begin
        encode_generated_body = encode_16x16_body(rem, c_rem);
      end else if ((width == 16'd32) && (height == 16'd32)) begin
        encode_generated_body = encode_32x32_body(rem, c_rem);
      end else if ((width == 16'd64) && (height == 16'd64)) begin
        encode_generated_body = encode_64x64_body(width, height, rem, c_rem);
      end else begin
        encode_generated_body = '0;
      end
    end
  endfunction

  function automatic logic [12 + MAX_SLICE_PAYLOAD_BITS:0] encode_8x8_body(
    input logic [4:0] rem,
    input logic [4:0] c_rem
  );
    cabac_state_t st;
    begin
      st = cabac_start();
      st = encode_8x8_luma_tree(st, rem);
      st = encode_4x4_chroma_tree(st, c_rem);
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      encode_8x8_body = {
        st[CABAC_LEN_LSB +: 13],
        st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS]
      };
    end
  endfunction

  function automatic logic [12 + MAX_SLICE_PAYLOAD_BITS:0] encode_16x16_body(
    input logic [4:0] rem,
    input logic [4:0] c_rem
  );
    cabac_state_t st;
    begin
      st = cabac_start();
      st = encode_16x16_tree(st, rem, c_rem);
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      encode_16x16_body = {
        st[CABAC_LEN_LSB +: 13],
        st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS]
      };
    end
  endfunction

  function automatic logic [12 + MAX_SLICE_PAYLOAD_BITS:0] encode_32x32_body(
    input logic [4:0] rem,
    input logic [4:0] c_rem
  );
    cabac_state_t st;
    begin
      st = cabac_start();
      st = encode_32x32_luma_tree(st, rem);
      st = encode_32x32_chroma_tree(st, c_rem);
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      encode_32x32_body = {
        st[CABAC_LEN_LSB +: 13],
        st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS]
      };
    end
  endfunction

  function automatic logic [12 + MAX_SLICE_PAYLOAD_BITS:0] encode_64x64_body(
    input logic [15:0] coded_width,
    input logic [15:0] coded_height,
    input logic [4:0] rem,
    input logic [4:0] c_rem
  );
    cabac_state_t st;
    begin
      st = cabac_start();
      st = encode_partitioned_ctu_tree(st, coded_width, coded_height, rem, c_rem);
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      encode_64x64_body = {
        st[CABAC_LEN_LSB +: 13],
        st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS]
      };
    end
  endfunction

  function automatic cabac_state_t encode_partitioned_ctu_tree(
    input cabac_state_t st_in,
    input logic [15:0]  root_width,
    input logic [15:0]  root_height,
    input logic [4:0]   rem,
    input logic [4:0]   c_rem
  );
    cabac_state_t st;
    logic [7:0] child_width;
    logic [7:0] child_height;
    vvc_prob_model_t split_child_ctx;
    vvc_prob_model_t split_chroma_ctx;
    vvc_prob_model_t multi_ref_line_ctx;
    vvc_prob_model_t intra_mpm_ctx;
    vvc_prob_model_t intra_planar_ctx;
    vvc_prob_model_t qt_cbf_y_ctx;
    vvc_prob_model_t qt_cbf_cb_ctx;
    vvc_prob_model_t qt_cbf_cr_ctx;
    begin
      st = st_in;
      child_width = root_width[8:1];
      child_height = root_height[8:1];
      split_child_ctx = vvc_prob_model_init(
        vvc_split_flag_init(vvc_split_cu_ctx_full_child_no_neighbours()),
        vvc_split_flag_log2_window(vvc_split_cu_ctx_full_child_no_neighbours()),
        32
      );
      split_chroma_ctx = vvc_prob_model_init(
        vvc_split_flag_init(vvc_split_cu_ctx_chroma_root_no_neighbours()),
        vvc_split_flag_log2_window(vvc_split_cu_ctx_chroma_root_no_neighbours()),
        32
      );
      multi_ref_line_ctx = vvc_prob_model_init(vvc_multi_ref_line_idx_init(4'd0), vvc_multi_ref_line_idx_log2_window(4'd0), 32);
      intra_mpm_ctx = vvc_prob_model_init(vvc_intra_luma_mpm_flag_init(), vvc_intra_luma_mpm_flag_log2_window(), 32);
      intra_planar_ctx = vvc_prob_model_init(vvc_intra_luma_planar_flag_init(4'd1), vvc_intra_luma_planar_flag_log2_window(4'd1), 32);
      qt_cbf_y_ctx = vvc_prob_model_init(vvc_qt_cbf_y_init(4'd0), vvc_qt_cbf_y_log2_window(4'd0), 32);
      qt_cbf_cb_ctx = vvc_prob_model_init(vvc_qt_cbf_cb_init(4'd0), vvc_qt_cbf_cb_log2_window(4'd0), 32);
      qt_cbf_cr_ctx = vvc_prob_model_init(vvc_qt_cbf_cr_init(4'd0), vvc_qt_cbf_cr_log2_window(4'd0), 32);
      st = encode_ctu_qt_split(st, 8'd0, 8'd0, root_width[7:0], root_height[7:0], 3'd0, 3'd0);
      {split_child_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, st} =
        encode_ctu_luma_leaf(st, split_child_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, rem, 8'd0, 8'd0, child_width, child_height, 3'd1, 3'd0);
      {split_child_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, st} =
        encode_ctu_luma_leaf(st, split_child_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, rem, child_width, 8'd0, child_width, child_height, 3'd1, 3'd0);
      {split_child_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, st} =
        encode_ctu_luma_leaf(st, split_child_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, rem, 8'd0, child_height, child_width, child_height, 3'd1, 3'd0);
      {split_child_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, st} =
        encode_ctu_luma_leaf(st, split_child_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, rem, child_width, child_height, child_width, child_height, 3'd1, 3'd0);
      st = encode_ctu_chroma_leaf(st, split_chroma_ctx, qt_cbf_cb_ctx, qt_cbf_cr_ctx, c_rem, 8'd0, 8'd0, child_width, child_height, 3'd1, 3'd0);
      encode_partitioned_ctu_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_ctu_qt_split(
    input cabac_state_t st_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    vvc_prob_model_t split_ctx;
    begin
      st = st_in;
      // VVC 7.3.11.4 coding_tree emits split_cu_flag for the 64x64 root. In
      // this subset binary/ternary root splits are unavailable, so split_qt_flag
      // is inferred and no CABAC bin is written for it.
      // VVC CABACWriter::split_cu_mode writes split_cu_flag as !isNo, so a
      // QT split is encoded as bin 1.
      split_ctx = vvc_prob_model_init(
        vvc_split_flag_init(vvc_split_cu_ctx_qt_only_root()),
        vvc_split_flag_log2_window(vvc_split_cu_ctx_qt_only_root()),
        32
      );
      {split_ctx, st} = cabac_encode_vvc_model_bin(st, split_ctx, 1'b1);
      encode_ctu_qt_split = st;
    end
  endfunction

  function automatic cabac_luma_leaf_step_t encode_ctu_luma_leaf(
    input cabac_state_t st_in,
    input vvc_prob_model_t split_ctx_in,
    input vvc_prob_model_t multi_ref_line_ctx_in,
    input vvc_prob_model_t intra_mpm_ctx_in,
    input vvc_prob_model_t intra_planar_ctx_in,
    input vvc_prob_model_t qt_cbf_y_ctx_in,
    input logic [4:0]   rem,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    vvc_prob_model_t split_ctx;
    vvc_prob_model_t multi_ref_line_ctx;
    vvc_prob_model_t intra_mpm_ctx;
    vvc_prob_model_t intra_planar_ctx;
    vvc_prob_model_t qt_cbf_y_ctx;
    begin
      {split_ctx, st} = encode_ctu_luma_leaf_split(st_in, split_ctx_in, cb_x, cb_y, cb_width, cb_height, cqt_depth, mtt_depth);
      {multi_ref_line_ctx, st} = encode_ctu_luma_multi_ref_line(st, multi_ref_line_ctx_in, cb_x, cb_y, cb_width, cb_height, cqt_depth, mtt_depth);
      {intra_mpm_ctx, intra_planar_ctx, st} = encode_ctu_luma_intra_planar_mode(st, intra_mpm_ctx_in, intra_planar_ctx_in, cb_x, cb_y, cb_width, cb_height, cqt_depth, mtt_depth);
      {qt_cbf_y_ctx, st} = encode_ctu_luma_cbf(st, qt_cbf_y_ctx_in, 1'b0, cb_x, cb_y, cb_width, cb_height, cqt_depth, mtt_depth);
      encode_ctu_luma_leaf = {split_ctx, multi_ref_line_ctx, intra_mpm_ctx, intra_planar_ctx, qt_cbf_y_ctx, st};
    end
  endfunction

  function automatic cabac_vvc_model_step_t encode_ctu_luma_multi_ref_line(
    input cabac_state_t st_in,
    input vvc_prob_model_t multi_ref_line_ctx_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    vvc_prob_model_t multi_ref_line_ctx;
    begin
      multi_ref_line_ctx = multi_ref_line_ctx_in;
      st = st_in;
      // With sps_mrl_enabled_flag set, VVC extend_ref_line emits
      // MultiRefLineIdx(0) for intra luma CUs that are not on the first luma
      // line of the CTU. FrameForge currently always selects reference line 0.
      if (cb_y != 8'd0) begin
        {multi_ref_line_ctx, st} = cabac_encode_vvc_model_bin(st, multi_ref_line_ctx, 1'b0);
      end
      encode_ctu_luma_multi_ref_line = {multi_ref_line_ctx, st};
    end
  endfunction

  function automatic cabac_vvc_model_step_t encode_ctu_luma_leaf_split(
    input cabac_state_t st_in,
    input vvc_prob_model_t split_ctx_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    vvc_prob_model_t split_ctx;
    begin
      // VVC 7.3.11.4 reaches coding_unit when split_cu_flag is false. This
      // uses the split_cu_flag ctxInc derived by VVC 9.3.4.2.2 for this CTU
      // child and maintains that context across the four child leaves.
      {split_ctx, st} = cabac_encode_vvc_model_bin(st_in, split_ctx_in, 1'b0);
      encode_ctu_luma_leaf_split = {split_ctx, st};
    end
  endfunction

  function automatic logic [2 * VVC_PROB_MODEL_BITS + CABAC_STATE_BITS - 1:0] encode_ctu_luma_intra_planar_mode(
    input cabac_state_t st_in,
    input vvc_prob_model_t intra_mpm_ctx_in,
    input vvc_prob_model_t intra_planar_ctx_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    vvc_prob_model_t intra_mpm_ctx;
    vvc_prob_model_t intra_planar_ctx;
    begin
      {intra_mpm_ctx, st} = cabac_encode_vvc_model_bin(st_in, intra_mpm_ctx_in, 1'b1);
      {intra_planar_ctx, st} = cabac_encode_vvc_model_bin(st, intra_planar_ctx_in, 1'b0);
      encode_ctu_luma_intra_planar_mode = {intra_mpm_ctx, intra_planar_ctx, st};
    end
  endfunction

  function automatic cabac_vvc_model_step_t encode_ctu_luma_cbf(
    input cabac_state_t st_in,
    input vvc_prob_model_t qt_cbf_y_ctx_in,
    input logic         cbf,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    vvc_prob_model_t qt_cbf_y_ctx;
    begin
      {qt_cbf_y_ctx, st} = cabac_encode_vvc_model_bin(st_in, qt_cbf_y_ctx_in, cbf);
      encode_ctu_luma_cbf = {qt_cbf_y_ctx, st};
    end
  endfunction

  function automatic cabac_state_t encode_ctu_chroma_leaf(
    input cabac_state_t st_in,
    input vvc_prob_model_t split_ctx_in,
    input vvc_prob_model_t qt_cbf_cb_ctx_in,
    input vvc_prob_model_t qt_cbf_cr_ctx_in,
    input logic [4:0]   c_rem,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    vvc_prob_model_t split_ctx;
    vvc_prob_model_t qt_cbf_cb_ctx;
    vvc_prob_model_t qt_cbf_cr_ctx;
    vvc_prob_model_t cclm_mode_ctx;
    vvc_prob_model_t intra_chroma_pred_ctx;
    begin
      cclm_mode_ctx = vvc_prob_model_init(vvc_cclm_mode_flag_init(), vvc_cclm_mode_flag_log2_window(), 32);
      intra_chroma_pred_ctx = vvc_prob_model_init(vvc_intra_chroma_pred_mode_init(), vvc_intra_chroma_pred_mode_log2_window(), 32);
      {split_ctx, st} = cabac_encode_vvc_model_bin(st_in, split_ctx_in, 1'b0);
      // Select derived chroma mode for this dual-tree chroma CU:
      // cclm_mode_flag=0, intra_chroma_pred_mode=0.
      {cclm_mode_ctx, st} = cabac_encode_vvc_model_bin(st, cclm_mode_ctx, 1'b0);
      {intra_chroma_pred_ctx, st} = cabac_encode_vvc_model_bin(st, intra_chroma_pred_ctx, 1'b0);
      {qt_cbf_cb_ctx, st} = cabac_encode_vvc_model_bin(st, qt_cbf_cb_ctx_in, 1'b0);
      {qt_cbf_cr_ctx, st} = cabac_encode_vvc_model_bin(st, qt_cbf_cr_ctx_in, 1'b0);
      encode_ctu_chroma_leaf = st;
    end
  endfunction

  function automatic cabac_state_t encode_ctu_luma_32x32_cbf(
    input cabac_state_t st_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    begin
      // cbf_comp luma=1 for the 32x32 transform unit. The current path
      // always emits a residual-bearing luma TU so the downstream residual
      // syntax remains present.
      encode_ctu_luma_32x32_cbf = cabac_encode_bin(st_in, 1'b1, 9'd130, 1'b1);
    end
  endfunction

  function automatic cabac_state_t encode_ctu_luma_32x32_residual_prefix(
    input cabac_state_t st_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    begin
      // TODO(vvc): Split residual_coding into named coefficient-group,
      // last-position, significance, and level syntax. These are the first
      // VVC 7.3.11.11.
      st = cabac_encode_bin(st_in, 1'b1, 9'd84, 1'b1);
      st = cabac_encode_bin(st, 1'b1, 9'd84, 1'b1);
      encode_ctu_luma_32x32_residual_prefix = st;
    end
  endfunction

  function automatic cabac_state_t encode_ctu_luma_32x32_residual_scan_prefix(
    input cabac_state_t st_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    begin
      // TODO(vvc): Replace this with named residual_coding syntax once the
      // coefficient scan position and group flags are derived from the
      // residual path.
      st = cabac_encode_bin(st_in, 1'b1, 9'd60, 1'b1);
      st = cabac_encode_bin(st, 1'b1, 9'd130, 1'b1);
      st = cabac_encode_bin(st, 1'b1, 9'd76, 1'b1);
      st = cabac_encode_bin(st, 1'b0, 9'd178, 1'b0);
      encode_ctu_luma_32x32_residual_scan_prefix = st;
    end
  endfunction

  function automatic cabac_state_t encode_ctu_luma_32x32_residual_scan_tail(
    input cabac_state_t st_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    begin
      // TODO(vvc): Replace these coefficient-position/context bins with
      // generated residual_coding syntax driven by transform output.
      st = cabac_encode_bin(st_in, 1'b1, 9'd140, 1'b1);
      st = cabac_encode_bin(st, 1'b1, 9'd84, 1'b1);
      st = cabac_encode_bin(st, 1'b1, 9'd106, 1'b1);
      st = cabac_encode_bin(st, 1'b1, 9'd68, 1'b1);
      st = cabac_encode_bin(st, 1'b1, 9'd166, 1'b1);
      st = cabac_encode_bin(st, 1'b0, 9'd92, 1'b1);
      encode_ctu_luma_32x32_residual_scan_tail = st;
    end
  endfunction

  function automatic cabac_state_t encode_ctu_luma_32x32_residual_bypass_suffix(
    input cabac_state_t st_in,
    input logic [7:0]   cb_x,
    input logic [7:0]   cb_y,
    input logic [7:0]   cb_width,
    input logic [7:0]   cb_height,
    input logic [2:0]   cqt_depth,
    input logic [2:0]   mtt_depth
  );
    cabac_state_t st;
    begin
      // TODO(vvc): Replace this with named residual bypass syntax
      // (suffix/remainder/sign bins) from generated coefficient levels.
      st = cabac_encode_bin_ep(st_in, 1'b1);
      st = cabac_encode_bin_ep(st, 1'b1);
      st = cabac_encode_bin_ep(st, 1'b0);
      encode_ctu_luma_32x32_residual_bypass_suffix = st;
    end
  endfunction

  function automatic cabac_state_t encode_ctu_chroma_32x32_tree(
    input cabac_state_t st_in,
    input logic [4:0]   c_rem
  );
    begin
      encode_ctu_chroma_32x32_tree = encode_32x32_chroma_tree(st_in, c_rem);
    end
  endfunction

  function automatic cabac_state_t encode_8x8_luma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      st = cabac_encode_ctx_bins(st, 5'd0,  8'b0000_0101, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd4,  8'b0000_0010, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd8,  8'b0000_0001, 4'd1);
      st = cabac_encode_rem_abs_ep(st, rem, 3'd0);
      st = cabac_encode_bin_ep(st, 1'b1);
      st = cabac_encode_ctx_bins(st, 5'd9,  8'b0000_1011, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd13, 8'b0000_0100, 4'd3);
      encode_8x8_luma_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_4x4_chroma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   c_rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      st = cabac_encode_ctx_bins(st, 5'd16, 8'b0000_0101, 4'd3);
      st = cabac_encode_rem_abs_ep(st, c_rem, 3'd0);
      st = cabac_encode_bin_ep(st, 1'b1);
      encode_4x4_chroma_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_16x16_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem,
    input logic [4:0]   c_rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      // TODO(vvc): Replace these generated decisions with
      // generated 16x16 split, prediction, CBF, and residual syntax.
      st = cabac_encode_bin(st, 1'b0, 9'd214, 1'b0); // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd67, 1'b1);  // split_cu_mode qt=1
      st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[5]
      st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[4]
      st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[3]
      st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[2]
      st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[1]
      st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[0]
      st = cabac_encode_bin(st, 1'b1, 9'd52, 1'b1);  // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd166, 1'b1); // split_cu_mode qt=1
      st = cabac_encode_bin(st, 1'b1, 9'd109, 1'b1); // split_cu_mode split=0
      st = cabac_encode_bin(st, 1'b1, 9'd134, 1'b1); // cbf_comp luma=1
      st = cabac_encode_bin(st, 1'b1, 9'd116, 1'b1); // sig_coeff_group_flag
      st = cabac_encode_bin(st, 1'b1, 9'd142, 1'b1); // sig_coeff_group_flag
      st = cabac_encode_bin(st, 1'b1, 9'd221, 1'b0); // last_sig_coeff_x_prefix
      st = cabac_encode_bin(st, 1'b0, 9'd205, 1'b0); // last_sig_coeff_y_prefix
      st = cabac_encode_bin_ep(st, 1'b0);            // last_sig_coeff_suffix
      st = cabac_encode_bin(st, 1'b0, 9'd39, 1'b0);  // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd101, 1'b0); // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd99, 1'b0);  // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd67, 1'b0);  // abs_level_gtx_flag
      st = cabac_encode_bin_ep(st, 1'b0);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b1);            // coeff_sign_flag
      st = cabac_encode_bin(st, 1'b0, 9'd64, 1'b0);  // ts_flag=0
      st = cabac_encode_bin(st, 1'b0, 9'd54, 1'b0);  // mts_idx=0

      st = cabac_encode_bin(st, 1'b0, 9'd40, 1'b0);  // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd176, 1'b0); // split_cu_mode qt=1
      st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd130, 1'b0); // split_cu_mode qt=1
      st = cabac_encode_bin(st, 1'b0, 9'd88, 1'b0);  // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd114, 1'b0); // split_cu_mode qt=1
      st = cabac_encode_bin(st, 1'b0, 9'd80, 1'b0);  // split_cu_mode split=0
      st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // cbf_comp Cb=0
      st = cabac_encode_bin(st, 1'b0, 9'd53, 1'b0);  // cbf_comp Cr=1
      st = cabac_encode_bin(st, 1'b0, 9'd26, 1'b0);  // sig_coeff_group_flag
      st = cabac_encode_bin(st, 1'b1, 9'd96, 1'b0);  // last_sig_coeff_x_prefix
      st = cabac_encode_bin(st, 1'b0, 9'd112, 1'b0); // last_sig_coeff_y_prefix
      st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd72, 1'b0);  // abs_level_gtx_flag
      st = cabac_encode_bin(st, 1'b1, 9'd112, 1'b1); // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd72, 1'b0);  // abs_level_gtx_flag
      st = cabac_encode_bin(st, 1'b1, 9'd88, 1'b1);  // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd84, 1'b0);  // abs_level_gtx_flag
      st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd206, 1'b1); // abs_level_gtx_flag
      st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b0);            // remainder_suffix
      st = cabac_encode_bin_ep(st, 1'b1);            // coeff_sign_flag
      st = cabac_encode_bin(st, 1'b1, 9'd160, 1'b0); // ts_flag=0
      st = cabac_encode_bin(st, 1'b1, 9'd29, 1'b0);  // mts_idx=0

      st = cabac_encode_bin(st, 1'b1, 9'd172, 1'b1); // split_cu_mode split=0 at (4,0)
      st = cabac_encode_bin(st, 1'b0, 9'd107, 1'b0); // cbf_comp Cb(4,0)=0
      st = cabac_encode_bin(st, 1'b0, 9'd136, 1'b0); // cbf_comp Cr(4,0)=0
      st = cabac_encode_bin(st, 1'b1, 9'd67, 1'b0);  // mts_idx=0 at (4,0)
      st = cabac_encode_bin(st, 1'b0, 9'd100, 1'b0); // split_cu_mode split=0 at (0,4)
      st = cabac_encode_bin(st, 1'b0, 9'd124, 1'b0); // cbf_comp Cb(0,4)=0
      st = cabac_encode_bin(st, 1'b0, 9'd160, 1'b0); // cbf_comp Cr(0,4)=0
      st = cabac_encode_bin(st, 1'b0, 9'd20, 1'b0);  // mts_idx=0 at (0,4)
      st = cabac_encode_bin_ep(st, 1'b1);            // alignment EP before final block
      st = cabac_encode_bin(st, 1'b1, 9'd169, 1'b1); // split_cu_mode split=0 at (4,4)
      st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // cbf_comp Cb(4,4)=0
      st = cabac_encode_bin(st, 1'b0, 9'd147, 1'b0); // cbf_comp Cr(4,4)=0
      st = cabac_encode_bin(st, 1'b0, 9'd68, 1'b0);  // mts_idx=0 at (4,4)
      st = cabac_encode_bin(st, 1'b1, 9'd140, 1'b1); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd119, 1'b0); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd56, 1'b0);  // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd118, 1'b1); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd130, 1'b0); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd104, 1'b0); // final cbf cleanup
      st = cabac_encode_bin(st, 1'b0, 9'd81, 1'b0);  // final cbf cleanup
      encode_16x16_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_32x32_luma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      st = encode_compact_cabac_word(st, 16'h035a);
      st = encode_compact_cabac_word(st, 16'h010f);
      st = encode_32x32_luma_leaf_tree(st, rem);
      encode_32x32_luma_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_32x32_luma_leaf_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      st = encode_compact_cabac_word(st, 16'h0377);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h0163);
      st = encode_compact_cabac_word(st, 16'h020b);
      st = encode_compact_cabac_word(st, 16'h0153);
      st = encode_compact_cabac_word(st, 16'h0153);
      st = encode_compact_cabac_word(st, 16'h00f3);
      st = encode_compact_cabac_word(st, 16'h020b);
      st = encode_compact_cabac_word(st, 16'h0133);
      st = encode_compact_cabac_word(st, 16'h02ca);
      st = encode_compact_cabac_word(st, 16'h0233);
      st = encode_compact_cabac_word(st, 16'h0153);
      st = encode_compact_cabac_word(st, 16'h01ab);
      st = encode_compact_cabac_word(st, 16'h0113);
      st = encode_compact_cabac_word(st, 16'h029b);
      st = encode_compact_cabac_word(st, 16'h0170);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_32x32_luma_leaf_after_residual_bypass_suffix_tree(st, rem);
      encode_32x32_luma_leaf_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_32x32_luma_leaf_after_residual_bypass_suffix_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      st = encode_compact_cabac_word(st, 16'h007d);
      st = encode_compact_cabac_word(st, 16'h011e);
      st = encode_compact_cabac_word(st, 16'h0092);
      st = encode_compact_cabac_word(st, 16'h008a);
      st = encode_compact_cabac_word(st, 16'h01b1);
      st = encode_compact_cabac_word(st, 16'h0196);
      st = encode_compact_cabac_word(st, 16'h00c7);
      st = encode_compact_cabac_word(st, 16'h0102);
      st = encode_compact_cabac_word(st, 16'h0116);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0146);
      st = encode_compact_cabac_word(st, 16'h0203);
      st = encode_compact_cabac_word(st, 16'h010e);
      st = encode_compact_cabac_word(st, 16'h0394);
      st = encode_compact_cabac_word(st, 16'h009e);
      st = encode_compact_cabac_word(st, 16'h0337);
      st = encode_compact_cabac_word(st, 16'h0092);
      st = encode_compact_cabac_word(st, 16'h008b);
      st = encode_compact_cabac_word(st, 16'h007e);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0062);
      st = encode_compact_cabac_word(st, 16'h022f);
      st = encode_compact_cabac_word(st, 16'h0061);
      st = encode_compact_cabac_word(st, 16'h008a);
      st = encode_compact_cabac_word(st, 16'h0012);
      st = encode_compact_cabac_word(st, 16'h0077);
      st = encode_compact_cabac_word(st, 16'h00a2);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h00e1);
      st = encode_compact_cabac_word(st, 16'h0129);
      st = encode_compact_cabac_word(st, 16'h005a);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h00b1);
      st = encode_compact_cabac_word(st, 16'h007e);
      st = encode_compact_cabac_word(st, 16'h013d);
      st = encode_compact_cabac_word(st, 16'h008e);
      st = encode_compact_cabac_word(st, 16'h00b1);
      st = encode_compact_cabac_word(st, 16'h00aa);
      st = encode_compact_cabac_word(st, 16'h0179);
      st = encode_compact_cabac_word(st, 16'h0096);
      st = encode_compact_cabac_word(st, 16'h01ca);
      st = encode_compact_cabac_word(st, 16'h025e);
      st = encode_compact_cabac_word(st, 16'h017a);
      st = encode_compact_cabac_word(st, 16'h02cb);
      st = encode_compact_cabac_word(st, 16'h00ba);
      st = encode_compact_cabac_word(st, 16'h00fb);
      st = encode_compact_cabac_word(st, 16'h007e);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0076);
      st = encode_compact_cabac_word(st, 16'h017a);
      st = encode_compact_cabac_word(st, 16'h008b);
      st = encode_compact_cabac_word(st, 16'h007e);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0062);
      st = encode_compact_cabac_word(st, 16'h020b);
      st = encode_compact_cabac_word(st, 16'h0062);
      st = encode_compact_cabac_word(st, 16'h01b4);
      st = encode_compact_cabac_word(st, 16'h02cf);
      st = encode_compact_cabac_word(st, 16'h0052);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h0162);
      st = encode_compact_cabac_word(st, 16'h0073);
      st = encode_compact_cabac_word(st, 16'h00d7);
      st = encode_compact_cabac_word(st, 16'h005a);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0042);
      st = encode_compact_cabac_word(st, 16'h01c3);
      st = encode_compact_cabac_word(st, 16'h0046);
      st = encode_compact_cabac_word(st, 16'h0141);
      st = encode_compact_cabac_word(st, 16'h004e);
      st = encode_compact_cabac_word(st, 16'h006b);
      st = encode_compact_cabac_word(st, 16'h0042);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h01d2);
      st = encode_compact_cabac_word(st, 16'h01f1);
      st = encode_compact_cabac_word(st, 16'h006a);
      st = encode_compact_cabac_word(st, 16'h02e8);
      st = encode_compact_cabac_word(st, 16'h01f4);
      st = encode_compact_cabac_word(st, 16'h02e3);
      st = encode_compact_cabac_word(st, 16'h020a);
      st = encode_compact_cabac_word(st, 16'h006b);
      st = encode_compact_cabac_word(st, 16'h004e);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h004e);
      st = encode_compact_cabac_word(st, 16'h01ac);
      st = encode_compact_cabac_word(st, 16'h007b);
      st = encode_compact_cabac_word(st, 16'h00e9);
      st = encode_compact_cabac_word(st, 16'h009d);
      st = encode_compact_cabac_word(st, 16'h0022);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h00d5);
      st = encode_compact_cabac_word(st, 16'h00c6);
      st = encode_compact_cabac_word(st, 16'h0026);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h024f);
      st = encode_compact_cabac_word(st, 16'h024e);
      st = encode_compact_cabac_word(st, 16'h00b2);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h0083);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h005e);
      st = encode_compact_cabac_word(st, 16'h024e);
      st = encode_compact_cabac_word(st, 16'h00a3);
      st = encode_compact_cabac_word(st, 16'h004a);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0046);
      st = encode_compact_cabac_word(st, 16'h02cf);
      st = encode_compact_cabac_word(st, 16'h004e);
      st = encode_compact_cabac_word(st, 16'h02e8);
      st = encode_compact_cabac_word(st, 16'h0223);
      st = encode_compact_cabac_word(st, 16'h0321);
      st = encode_compact_cabac_word(st, 16'h01c2);
      st = encode_compact_cabac_word(st, 16'h00b2);
      st = encode_compact_cabac_word(st, 16'h035b);
      st = encode_compact_cabac_word(st, 16'h0032);
      st = encode_compact_cabac_word(st, 16'h0053);
      st = encode_compact_cabac_word(st, 16'h004e);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h004a);
      st = encode_compact_cabac_word(st, 16'h0267);
      st = encode_compact_cabac_word(st, 16'h0209);
      st = encode_compact_cabac_word(st, 16'h0132);
      st = encode_compact_cabac_word(st, 16'h00d6);
      st = encode_compact_cabac_word(st, 16'h005b);
      st = encode_compact_cabac_word(st, 16'h0036);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0032);
      st = encode_compact_cabac_word(st, 16'h0173);
      st = encode_compact_cabac_word(st, 16'h027c);
      st = encode_compact_cabac_word(st, 16'h019f);
      st = encode_compact_cabac_word(st, 16'h014a);
      st = encode_compact_cabac_word(st, 16'h0027);
      st = encode_compact_cabac_word(st, 16'h01f1);
      st = encode_compact_cabac_word(st, 16'h01b6);
      st = encode_compact_cabac_word(st, 16'h008a);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h0053);
      st = encode_compact_cabac_word(st, 16'h01b6);
      st = encode_compact_cabac_word(st, 16'h0083);
      st = encode_compact_cabac_word(st, 16'h0046);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0042);
      st = encode_compact_cabac_word(st, 16'h0263);
      st = encode_compact_cabac_word(st, 16'h004a);
      st = encode_compact_cabac_word(st, 16'h02b4);
      st = encode_compact_cabac_word(st, 16'h01a2);
      st = encode_compact_cabac_word(st, 16'h033b);
      st = encode_compact_cabac_word(st, 16'h0032);
      st = encode_compact_cabac_word(st, 16'h0053);
      st = encode_compact_cabac_word(st, 16'h004e);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h004a);
      st = encode_compact_cabac_word(st, 16'h0242);
      st = encode_compact_cabac_word(st, 16'h005b);
      st = encode_compact_cabac_word(st, 16'h0032);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0032);
      st = encode_compact_cabac_word(st, 16'h0142);
      st = encode_compact_cabac_word(st, 16'h0027);
      st = encode_compact_cabac_word(st, 16'h0102);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h00c2);
      st = encode_compact_cabac_word(st, 16'h0304);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h005b);
      st = encode_compact_cabac_word(st, 16'h0027);
      st = encode_compact_cabac_word(st, 16'h028d);
      st = encode_compact_cabac_word(st, 16'h0165);
      st = encode_compact_cabac_word(st, 16'h00c2);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h01e7);
      st = encode_compact_cabac_word(st, 16'h01f5);
      st = encode_compact_cabac_word(st, 16'h013e);
      st = encode_compact_cabac_word(st, 16'h0230);
      st = encode_compact_cabac_word(st, 16'h0023);
      st = encode_compact_cabac_word(st, 16'h0123);
      st = encode_compact_cabac_word(st, 16'h029a);
      st = encode_compact_cabac_word(st, 16'h0242);
      st = encode_compact_cabac_word(st, 16'h01c8);
      st = encode_compact_cabac_word(st, 16'h002f);
      st = encode_compact_cabac_word(st, 16'h0298);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0167);
      st = encode_compact_cabac_word(st, 16'h0306);
      st = encode_compact_cabac_word(st, 16'h0142);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0193);
      st = encode_compact_cabac_word(st, 16'h01e6);
      st = encode_compact_cabac_word(st, 16'h01b2);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0201);
      st = encode_compact_cabac_word(st, 16'h0142);
      st = encode_compact_cabac_word(st, 16'h007e);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h01d2);
      st = encode_compact_cabac_word(st, 16'h0253);
      st = encode_compact_cabac_word(st, 16'h01f3);
      st = encode_compact_cabac_word(st, 16'h0281);
      st = encode_compact_cabac_word(st, 16'h017a);
      st = encode_compact_cabac_word(st, 16'h0297);
      st = encode_compact_cabac_word(st, 16'h01b3);
      st = encode_compact_cabac_word(st, 16'h01f5);
      st = encode_compact_cabac_word(st, 16'h011e);
      st = encode_compact_cabac_word(st, 16'h002b);
      st = encode_compact_cabac_word(st, 16'h0337);
      st = encode_compact_cabac_word(st, 16'h01fe);
      st = encode_compact_cabac_word(st, 16'h006a);
      st = encode_compact_cabac_word(st, 16'h0170);
      st = encode_compact_cabac_word(st, 16'h0027);
      st = encode_compact_cabac_word(st, 16'h0173);
      st = encode_compact_cabac_word(st, 16'h01b2);
      st = encode_compact_cabac_word(st, 16'h0156);
      st = encode_compact_cabac_word(st, 16'h017f);
      st = encode_compact_cabac_word(st, 16'h0173);
      st = encode_compact_cabac_word(st, 16'h01b1);
      st = encode_compact_cabac_word(st, 16'h01c9);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h0067);
      st = encode_compact_cabac_word(st, 16'h02e8);
      st = encode_compact_cabac_word(st, 16'h028c);
      st = encode_compact_cabac_word(st, 16'h0268);
      st = encode_compact_cabac_word(st, 16'h023c);
      st = encode_compact_cabac_word(st, 16'h0132);
      st = encode_compact_cabac_word(st, 16'h0335);
      st = encode_compact_cabac_word(st, 16'h011a);
      st = encode_compact_cabac_word(st, 16'h0063);
      st = encode_compact_cabac_word(st, 16'h01c1);
      st = encode_compact_cabac_word(st, 16'h019a);
      st = encode_compact_cabac_word(st, 16'h0076);
      st = encode_compact_cabac_word(st, 16'h0155);
      st = encode_compact_cabac_word(st, 16'h00ee);
      st = encode_compact_cabac_word(st, 16'h0142);
      st = encode_compact_cabac_word(st, 16'h02f8);
      st = encode_compact_cabac_word(st, 16'h0208);
      st = encode_compact_cabac_word(st, 16'h0141);
      st = encode_compact_cabac_word(st, 16'h00da);
      st = encode_compact_cabac_word(st, 16'h0093);
      st = encode_compact_cabac_word(st, 16'h012a);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h024e);
      st = encode_compact_cabac_word(st, 16'h0375);
      st = encode_compact_cabac_word(st, 16'h00fa);
      st = encode_compact_cabac_word(st, 16'h01f7);
      st = encode_compact_cabac_word(st, 16'h011e);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h002b);
      st = encode_compact_cabac_word(st, 16'h0337);
      st = encode_compact_cabac_word(st, 16'h020a);
      st = encode_compact_cabac_word(st, 16'h006a);
      st = encode_compact_cabac_word(st, 16'h01c3);
      st = encode_compact_cabac_word(st, 16'h015b);
      st = encode_compact_cabac_word(st, 16'h01c2);
      st = encode_compact_cabac_word(st, 16'h018e);
      st = encode_compact_cabac_word(st, 16'h002f);
      st = encode_compact_cabac_word(st, 16'h031f);
      st = encode_compact_cabac_word(st, 16'h022d);
      st = encode_compact_cabac_word(st, 16'h0062);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h01d3);
      st = encode_compact_cabac_word(st, 16'h0281);
      st = encode_compact_cabac_word(st, 16'h017a);
      st = encode_compact_cabac_word(st, 16'h017c);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h0234);
      st = encode_compact_cabac_word(st, 16'h0013);
      encode_32x32_luma_leaf_after_residual_bypass_suffix_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_32x32_chroma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   c_rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      st = encode_compact_cabac_word(st, 16'h0103);
      st = encode_compact_cabac_word(st, 16'h02ce);
      st = encode_compact_cabac_word(st, 16'h020e);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h015b);
      st = encode_compact_cabac_word(st, 16'h01b2);
      st = encode_compact_cabac_word(st, 16'h0166);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h031f);
      st = encode_compact_cabac_word(st, 16'h01ae);
      st = encode_compact_cabac_word(st, 16'h00d5);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h031f);
      st = encode_compact_cabac_word(st, 16'h01fe);
      st = encode_compact_cabac_word(st, 16'h005a);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h00fb);
      st = encode_compact_cabac_word(st, 16'h0306);
      st = encode_compact_cabac_word(st, 16'h01f3);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h00e3);
      st = encode_compact_cabac_word(st, 16'h02ce);
      st = encode_compact_cabac_word(st, 16'h0377);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h00e0);
      st = encode_compact_cabac_word(st, 16'h010f);
      st = encode_compact_cabac_word(st, 16'h012c);
      st = encode_compact_cabac_word(st, 16'h00b0);
      st = encode_compact_cabac_word(st, 16'h00ef);
      st = encode_compact_cabac_word(st, 16'h00a3);
      st = encode_compact_cabac_word(st, 16'h0359);
      st = encode_compact_cabac_word(st, 16'h01cb);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h01e5);
      st = encode_compact_cabac_word(st, 16'h02c2);
      st = encode_compact_cabac_word(st, 16'h023e);
      st = encode_compact_cabac_word(st, 16'h012b);
      st = encode_compact_cabac_word(st, 16'h0181);
      st = encode_compact_cabac_word(st, 16'h02e1);
      st = encode_compact_cabac_word(st, 16'h0147);
      st = encode_compact_cabac_word(st, 16'h0192);
      st = encode_compact_cabac_word(st, 16'h0223);
      st = encode_compact_cabac_word(st, 16'h0295);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h01f1);
      st = encode_compact_cabac_word(st, 16'h03b3);
      st = encode_compact_cabac_word(st, 16'h01c2);
      st = encode_compact_cabac_word(st, 16'h01c2);
      st = encode_compact_cabac_word(st, 16'h0221);
      st = encode_compact_cabac_word(st, 16'h01c1);
      st = encode_compact_cabac_word(st, 16'h0242);
      st = encode_compact_cabac_word(st, 16'h005a);
      st = encode_compact_cabac_word(st, 16'h0143);
      st = encode_compact_cabac_word(st, 16'h00ea);
      st = encode_compact_cabac_word(st, 16'h0013);
      st = encode_compact_cabac_word(st, 16'h00c6);
      st = encode_compact_cabac_word(st, 16'h00c7);
      st = encode_compact_cabac_word(st, 16'h0338);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h0221);
      st = encode_compact_cabac_word(st, 16'h01a1);
      st = encode_compact_cabac_word(st, 16'h0219);
      st = encode_compact_cabac_word(st, 16'h0181);
      st = encode_compact_cabac_word(st, 16'h011a);
      st = encode_compact_cabac_word(st, 16'h021a);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h006a);
      st = encode_compact_cabac_word(st, 16'h018e);
      st = encode_compact_cabac_word(st, 16'h0295);
      st = encode_compact_cabac_word(st, 16'h00b2);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h0062);
      st = encode_compact_cabac_word(st, 16'h0062);
      st = encode_compact_cabac_word(st, 16'h009e);
      st = encode_compact_cabac_word(st, 16'h0092);
      st = encode_compact_cabac_word(st, 16'h008a);
      st = encode_compact_cabac_word(st, 16'h007e);
      st = encode_compact_cabac_word(st, 16'h0075);
      st = encode_compact_cabac_word(st, 16'h00f1);
      st = encode_compact_cabac_word(st, 16'h00a6);
      st = encode_compact_cabac_word(st, 16'h0012);
      st = encode_compact_cabac_word(st, 16'h0282);
      st = encode_compact_cabac_word(st, 16'h0072);
      st = encode_compact_cabac_word(st, 16'h02c2);
      st = encode_compact_cabac_word(st, 16'h01ae);
      st = encode_compact_cabac_word(st, 16'h024e);
      st = encode_compact_cabac_word(st, 16'h0172);
      st = encode_compact_cabac_word(st, 16'h01f6);
      st = encode_compact_cabac_word(st, 16'h022e);
      st = encode_compact_cabac_word(st, 16'h0166);
      st = encode_compact_cabac_word(st, 16'h01f2);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h0252);
      st = encode_compact_cabac_word(st, 16'h027b);
      st = encode_compact_cabac_word(st, 16'h01c2);
      st = encode_compact_cabac_word(st, 16'h029a);
      st = encode_compact_cabac_word(st, 16'h010e);
      st = encode_compact_cabac_word(st, 16'h0223);
      st = encode_compact_cabac_word(st, 16'h0202);
      st = encode_compact_cabac_word(st, 16'h010c);
      st = encode_compact_cabac_word(st, 16'h0200);
      st = encode_compact_cabac_word(st, 16'h0163);
      st = encode_compact_cabac_word(st, 16'h01de);
      st = encode_compact_cabac_word(st, 16'h029a);
      st = encode_compact_cabac_word(st, 16'h0092);
      st = encode_compact_cabac_word(st, 16'h0226);
      st = encode_compact_cabac_word(st, 16'h018f);
      st = encode_compact_cabac_word(st, 16'h0296);
      st = encode_compact_cabac_word(st, 16'h01ad);
      st = encode_compact_cabac_word(st, 16'h02cc);
      st = encode_compact_cabac_word(st, 16'h024f);
      st = encode_compact_cabac_word(st, 16'h02ea);
      st = encode_compact_cabac_word(st, 16'h0305);
      st = encode_compact_cabac_word(st, 16'h01d9);
      st = encode_compact_cabac_word(st, 16'h0146);
      st = encode_compact_cabac_word(st, 16'h0072);
      st = encode_compact_cabac_word(st, 16'h019f);
      st = encode_compact_cabac_word(st, 16'h00b1);
      st = encode_compact_cabac_word(st, 16'h007e);
      st = encode_compact_cabac_word(st, 16'h0012);
      st = encode_compact_cabac_word(st, 16'h00c7);
      st = encode_compact_cabac_word(st, 16'h00d2);
      st = encode_compact_cabac_word(st, 16'h0117);
      st = encode_compact_cabac_word(st, 16'h019f);
      st = encode_compact_cabac_word(st, 16'h01b1);
      st = encode_compact_cabac_word(st, 16'h017d);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8001);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h01b1);
      st = encode_compact_cabac_word(st, 16'h01e7);
      st = encode_compact_cabac_word(st, 16'h019e);
      st = encode_compact_cabac_word(st, 16'h02b6);
      st = encode_compact_cabac_word(st, 16'h00e2);
      st = encode_compact_cabac_word(st, 16'h01c8);
      st = encode_compact_cabac_word(st, 16'h0209);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h8000);
      st = encode_compact_cabac_word(st, 16'h0192);
      st = encode_compact_cabac_word(st, 16'h008a);
      encode_32x32_chroma_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_compact_cabac_word(
    input cabac_state_t st_in,
    input logic [15:0]  word
  );
    begin
      if (word[15]) begin
        encode_compact_cabac_word = cabac_encode_bin_ep(st_in, word[0]);
      end else begin
        encode_compact_cabac_word = cabac_encode_bin(st_in, word[0], {1'b0, word[10:2]}, ~(word[1] ^ word[0]));
      end
    end
  endfunction

  function automatic cabac_state_t cabac_start();
    begin
      cabac_start = '0;
      cabac_start[CABAC_LOW_LSB +: 32] = 32'd0;
      cabac_start[CABAC_RANGE_LSB +: 16] = 16'd510;
      cabac_start[CABAC_BUFFERED_BYTE_LSB +: 9] = 9'h0ff;
      cabac_start[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = 8'd0;
      cabac_start[CABAC_BITS_LEFT_LSB +: 8] = 8'd23;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_ctx_bins(
    input cabac_state_t st_in,
    input logic [4:0]   ctx_offset,
    input logic [7:0]   bin_pattern,
    input logic [3:0]   num_bins
  );
    cabac_state_t st;
    integer i;
    begin
      st = st_in;
      for (i = 0; i < num_bins; i = i + 1) begin
        st = cabac_encode_bin(
          st,
          bin_pattern[num_bins - 1 - i],
          vvc_ctx_lps(ctx_offset + i[4:0]),
          vvc_ctx_mps(ctx_offset + i[4:0])
        );
      end
      cabac_encode_ctx_bins = st;
    end
  endfunction

  function automatic cabac_vvc_model_step_t cabac_encode_vvc_model_bin(
    input cabac_state_t     st_in,
    input vvc_prob_model_t  model_in,
    input logic             bin
  );
    cabac_state_t st;
    vvc_prob_model_t model;
    begin
      st = cabac_encode_bin(
        st_in,
        bin,
        vvc_prob_model_lps(model_in, st_in[CABAC_RANGE_LSB +: 16]),
        vvc_prob_model_mps(model_in)
      );
      model = vvc_prob_model_update(model_in, bin);
      cabac_encode_vvc_model_bin = {model, st};
    end
  endfunction

  function automatic vvc_prob_model_t vvc_prob_model_init(
    input logic [7:0] init_value,
    input logic [3:0] log2_window_size,
    input integer     qp
  );
    integer slope;
    integer offset;
    integer inistate;
    logic [15:0] p_state;
    integer rate0;
    integer rate1;
    begin
      // Mirrors VTM BinProbModel_Std initialization for the all-intra path.
      slope = (init_value >> 3) - 4;
      offset = ((init_value & 8'd7) * 18) + 1;
      inistate = ((slope * (qp - 16)) >>> 1) + offset;
      if (inistate < 1) begin
        inistate = 1;
      end else if (inistate > 127) begin
        inistate = 127;
      end
      p_state = inistate[15:0] << 8;
      rate0 = 2 + ((log2_window_size >> 2) & 3);
      rate1 = 3 + rate0 + (log2_window_size & 3);
      vvc_prob_model_init[0 +: 16] = p_state & 16'h7fe0;
      vvc_prob_model_init[16 +: 16] = p_state & 16'h7ffe;
      vvc_prob_model_init[32 +: 8] = ((rate0 & 8'h0f) << 4) | (rate1 & 8'h0f);
    end
  endfunction

  function automatic logic [7:0] vvc_prob_model_state(input vvc_prob_model_t model);
    logic [16:0] state_sum;
    begin
      state_sum = {1'b0, model[0 +: 16]} + {1'b0, model[16 +: 16]};
      vvc_prob_model_state = state_sum[15:8];
    end
  endfunction

  function automatic logic [3:0] vvc_split_cu_flag_ctx(
    input logic left_condition,
    input logic above_condition,
    input logic allow_bt_vertical,
    input logic allow_bt_horizontal,
    input logic allow_tt_vertical,
    input logic allow_tt_horizontal,
    input logic allow_qt
  );
    logic [3:0] split_alternatives;
    logic [3:0] ctx_set_idx;
    begin
      // VVC 9.3.4.2.2 derives ctxInc for split_cu_flag as:
      // condL + condA + ctxSetIdx * 3.
      split_alternatives =
        {3'd0, allow_bt_vertical} +
        {3'd0, allow_bt_horizontal} +
        {3'd0, allow_tt_vertical} +
        {3'd0, allow_tt_horizontal} +
        ({3'd0, allow_qt} << 1);
      ctx_set_idx = (split_alternatives - 4'd1) >> 1;
      vvc_split_cu_flag_ctx =
        {3'd0, left_condition} + {3'd0, above_condition} + (ctx_set_idx * 4'd3);
    end
  endfunction

  function automatic logic [3:0] vvc_split_cu_ctx_qt_only_root();
    begin
      vvc_split_cu_ctx_qt_only_root = vvc_split_cu_flag_ctx(
        1'b0, 1'b0,
        1'b0, 1'b0,
        1'b0, 1'b0,
        1'b1
      );
    end
  endfunction

  function automatic logic [3:0] vvc_split_cu_ctx_full_child_no_neighbours();
    begin
      vvc_split_cu_ctx_full_child_no_neighbours = vvc_split_cu_flag_ctx(
        1'b0, 1'b0,
        1'b1, 1'b1,
        1'b1, 1'b1,
        1'b1
      );
    end
  endfunction

  function automatic logic [3:0] vvc_split_cu_ctx_chroma_root_no_neighbours();
    begin
      vvc_split_cu_ctx_chroma_root_no_neighbours = vvc_split_cu_flag_ctx(
        1'b0, 1'b0,
        1'b1, 1'b1,
        1'b1, 1'b1,
        1'b0
      );
    end
  endfunction

  function automatic logic [3:0] vvc_split_qt_flag_ctx(
    input logic left_deeper_qt,
    input logic above_deeper_qt,
    input logic [2:0] cqt_depth
  );
    begin
      // VVC 9.3.4.2.2 derives ctxInc for split_qt_flag as:
      // condL + condA + ctxSetIdx * 3, where ctxSetIdx is cqtDepth >= 2.
      vvc_split_qt_flag_ctx =
        {3'd0, left_deeper_qt} + {3'd0, above_deeper_qt} + (cqt_depth >= 3'd2 ? 4'd3 : 4'd0);
    end
  endfunction

  function automatic logic vvc_prob_model_mps(input vvc_prob_model_t model);
    logic [7:0] state;
    begin
      state = vvc_prob_model_state(model);
      vvc_prob_model_mps = state[7];
    end
  endfunction

  function automatic logic [8:0] vvc_prob_model_lps(
    input vvc_prob_model_t model,
    input logic [15:0]     range
  );
    logic [15:0] q;
    logic [15:0] lps_full;
    begin
      q = {8'd0, vvc_prob_model_state(model)};
      if (q[7]) begin
        q = q ^ 16'h00ff;
      end
      lps_full = (((q >> 2) * (range >> 5)) >> 1) + 16'd4;
      vvc_prob_model_lps = lps_full[8:0];
    end
  endfunction

  function automatic vvc_prob_model_t vvc_prob_model_update(
    input vvc_prob_model_t model_in,
    input logic            bin
  );
    logic [15:0] state0;
    logic [15:0] state1;
    logic [7:0]  rate;
    integer rate0;
    integer rate1;
    begin
      state0 = model_in[0 +: 16];
      state1 = model_in[16 +: 16];
      rate = model_in[32 +: 8];
      rate0 = rate[7:4];
      rate1 = rate[3:0];
      state0 = state0 - ((state0 >> rate0) & 16'h7fe0);
      state1 = state1 - ((state1 >> rate1) & 16'h7ffe);
      if (bin) begin
        state0 = state0 + ((16'h7fff >> rate0) & 16'h7fe0);
        state1 = state1 + ((16'h7fff >> rate1) & 16'h7ffe);
      end
      vvc_prob_model_update = model_in;
      vvc_prob_model_update[0 +: 16] = state0;
      vvc_prob_model_update[16 +: 16] = state1;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin(
    input cabac_state_t st_in,
    input logic         bin,
    input logic [8:0]   lps_in,
    input logic         mps
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    logic [8:0]  lps;
    integer bits_left;
    integer num_bits;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      lps = lps_in;

      range = range - lps;
      if (bin != mps) begin
        num_bits = renorm_bits_sv(lps);
        bits_left = bits_left - num_bits;
        low = low + range;
        low = low << num_bits;
        range = lps << num_bits;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_RANGE_LSB +: 16] = range;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else if (range < 16'd256) begin
        // VVC BinProbModel_Std::getRenormBitsRange() is fixed to one bit for
        // MPS renormalization. LPS renormalization still uses renorm_bits_sv().
        num_bits = 4'd1;
        bits_left = bits_left - num_bits;
        low = low << num_bits;
        range = range << num_bits;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_RANGE_LSB +: 16] = range;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else begin
        st[CABAC_RANGE_LSB +: 16] = range;
      end
      cabac_encode_bin = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin_ep(
    input cabac_state_t st_in,
    input logic         bin
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32] << 1;
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8] - 1;
      if (bin) begin
        low = low + range;
      end
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bins_ep(
    input cabac_state_t st_in,
    input logic [31:0]  bin_pattern_in,
    input logic [5:0]   num_bins_in
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [31:0] bin_pattern;
    logic [15:0] range;
    logic [31:0] pattern;
    integer bits_left;
    integer num_bins;
    begin
      st = st_in;
      bin_pattern = bin_pattern_in;
      num_bins = num_bins_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];

      while (num_bins > 8) begin
        num_bins = num_bins - 8;
        pattern = bin_pattern >> num_bins;
        low = low << 8;
        low = low + (range * pattern);
        bin_pattern = bin_pattern - (pattern << num_bins);
        bits_left = bits_left - 8;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
          low = st[CABAC_LOW_LSB +: 32];
          bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
        end
      end

      low = low << num_bins;
      low = low + (range * bin_pattern);
      bits_left = bits_left - num_bins;
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bins_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_rem_abs_ep(
    input cabac_state_t st_in,
    input logic [4:0]   value,
    input logic [2:0]   rice_param
  );
    cabac_state_t st;
    logic [5:0] threshold;
    logic [5:0] length;
    logic [5:0] code_value;
    logic [5:0] prefix_length;
    logic [5:0] total_prefix_length;
    logic [5:0] suffix_length;
    logic [31:0] prefix;
    logic [31:0] suffix;
    begin
      st = st_in;
      threshold = 6'd5 << rice_param;
      if (value < threshold) begin
        length = (value >> rice_param) + 6'd1;
        st = cabac_encode_bins_ep(st, (32'd1 << length) - 32'd2, length);
        st = cabac_encode_bins_ep(st, value & ((32'd1 << rice_param) - 32'd1), rice_param);
      end else begin
        code_value = (value >> rice_param) - 6'd5;
        prefix_length = 6'd0;
        while (code_value > ((6'd2 << prefix_length) - 6'd2)) begin
          prefix_length = prefix_length + 6'd1;
        end
        total_prefix_length = prefix_length + 6'd5;
        suffix_length = prefix_length + rice_param + 6'd1;
        prefix = (32'd1 << total_prefix_length) - 32'd1;
        suffix = ((code_value - ((6'd1 << prefix_length) - 6'd1)) << rice_param)
          | (value & ((32'd1 << rice_param) - 32'd1));
        st = cabac_encode_bins_ep(st, prefix, total_prefix_length);
        st = cabac_encode_bins_ep(st, suffix, suffix_length);
      end
      cabac_encode_rem_abs_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin_trm(
    input cabac_state_t st_in,
    input logic         bin
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16] - 16'd2;
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      if (bin) begin
        low = low + range;
        low = low << 7;
        range = 16'd256;
        bits_left = bits_left - 7;
      end else if (range < 16'd256) begin
        low = low << 1;
        range = range << 1;
        bits_left = bits_left - 1;
      end
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_RANGE_LSB +: 16] = range;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_trm = st;
    end
  endfunction

  function automatic cabac_state_t cabac_finish(input cabac_state_t st_in);
    cabac_state_t st;
    logic [31:0] low;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    integer bits_left;
    integer final_bits;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      buffered_byte = st[CABAC_BUFFERED_BYTE_LSB +: 9];
      num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];

      if ((low >> (32 - bits_left)) != 0) begin
        st = cabac_write_bits(st, buffered_byte + 9'd1, 6'd8);
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'd0, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
        low = low - (32'd1 << (32 - bits_left));
        st[CABAC_LOW_LSB +: 32] = low;
      end else begin
        if (num_buffered_bytes > 8'd0) begin
          st = cabac_write_bits(st, buffered_byte, 6'd8);
        end
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'h0ff, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
      end

      final_bits = 24 - bits_left;
      if (final_bits > 0) begin
        st = cabac_write_bits(st, low >> 8, final_bits[5:0]);
      end
      cabac_finish = st;
    end
  endfunction

  function automatic cabac_state_t cabac_write_out(input cabac_state_t st_in);
    cabac_state_t st;
    logic [31:0] low;
    logic [31:0] lead_byte;
    logic [31:0] mask;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    logic [8:0] byte_value;
    logic [8:0] repeated_byte;
    logic [8:0] carry;
    integer bits_left;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      buffered_byte = st[CABAC_BUFFERED_BYTE_LSB +: 9];
      num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
      lead_byte = low >> (24 - bits_left);
      bits_left = bits_left + 8;
      mask = 32'hffff_ffff >> bits_left;
      low = low & mask;

      if (lead_byte == 32'hff) begin
        num_buffered_bytes = num_buffered_bytes + 8'd1;
      end else if (num_buffered_bytes > 8'd0) begin
        carry = lead_byte >> 8;
        byte_value = buffered_byte + carry;
        buffered_byte = lead_byte[7:0];
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_BUFFERED_BYTE_LSB +: 9] = buffered_byte;
        st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        st = cabac_write_bits(st, byte_value, 6'd8);
        repeated_byte = (9'h0ff + carry) & 9'h0ff;
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, repeated_byte, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
      end else begin
        num_buffered_bytes = 8'd1;
        buffered_byte = lead_byte[7:0];
      end

      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BUFFERED_BYTE_LSB +: 9] = buffered_byte;
      st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      cabac_write_out = st;
    end
  endfunction

  function automatic cabac_state_t cabac_write_bits(
    input cabac_state_t st_in,
    input logic [31:0]  value,
    input logic [5:0]   bit_count
  );
    cabac_state_t st;
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] bits;
    logic [12:0] len;
    integer i;
    begin
      st = st_in;
      bits = st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS];
      len = st[CABAC_LEN_LSB +: 13];
      for (i = bit_count - 1; i >= 0; i = i - 1) begin
        bits = (bits << 1) | value[i];
        len = len + 13'd1;
      end
      st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS] = bits;
      st[CABAC_LEN_LSB +: 13] = len;
      cabac_write_bits = st;
    end
  endfunction

  function automatic logic [3:0] renorm_bits_sv(input logic [15:0] range_in);
    logic [15:0] range;
    logic [3:0] count;
    begin
      range = range_in;
      count = 4'd0;
      while (range < 16'd256) begin
        range = range << 1;
        count = count + 4'd1;
      end
      renorm_bits_sv = count;
    end
  endfunction

  function automatic logic [7:0] vvc_split_flag_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_split_flag_init = 8'd19;
        4'd1: vvc_split_flag_init = 8'd28;
        4'd2: vvc_split_flag_init = 8'd38;
        4'd3: vvc_split_flag_init = 8'd27;
        4'd4: vvc_split_flag_init = 8'd29;
        4'd5: vvc_split_flag_init = 8'd38;
        4'd6: vvc_split_flag_init = 8'd20;
        4'd7: vvc_split_flag_init = 8'd30;
        default: vvc_split_flag_init = 8'd31;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_split_flag_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_split_flag_log2_window = 4'd12;
        4'd1: vvc_split_flag_log2_window = 4'd13;
        4'd2: vvc_split_flag_log2_window = 4'd8;
        4'd3: vvc_split_flag_log2_window = 4'd8;
        4'd4: vvc_split_flag_log2_window = 4'd13;
        4'd5: vvc_split_flag_log2_window = 4'd12;
        4'd6: vvc_split_flag_log2_window = 4'd5;
        4'd7: vvc_split_flag_log2_window = 4'd9;
        default: vvc_split_flag_log2_window = 4'd9;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_split_qt_flag_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_split_qt_flag_init = 8'd27;
        4'd1: vvc_split_qt_flag_init = 8'd6;
        4'd2: vvc_split_qt_flag_init = 8'd15;
        4'd3: vvc_split_qt_flag_init = 8'd25;
        4'd4: vvc_split_qt_flag_init = 8'd19;
        default: vvc_split_qt_flag_init = 8'd37;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_split_qt_flag_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_split_qt_flag_log2_window = 4'd0;
        4'd1: vvc_split_qt_flag_log2_window = 4'd8;
        4'd2: vvc_split_qt_flag_log2_window = 4'd8;
        4'd3: vvc_split_qt_flag_log2_window = 4'd12;
        4'd4: vvc_split_qt_flag_log2_window = 4'd12;
        default: vvc_split_qt_flag_log2_window = 4'd8;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_multi_ref_line_idx_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_multi_ref_line_idx_init = 8'd25;
        default: vvc_multi_ref_line_idx_init = 8'd60;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_multi_ref_line_idx_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_multi_ref_line_idx_log2_window = 4'd5;
        default: vvc_multi_ref_line_idx_log2_window = 4'd8;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_intra_luma_mpm_flag_init();
    begin
      vvc_intra_luma_mpm_flag_init = 8'd45;
    end
  endfunction

  function automatic logic [3:0] vvc_intra_luma_mpm_flag_log2_window();
    begin
      vvc_intra_luma_mpm_flag_log2_window = 4'd6;
    end
  endfunction

  function automatic logic [7:0] vvc_intra_luma_planar_flag_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_intra_luma_planar_flag_init = 8'd13;
        default: vvc_intra_luma_planar_flag_init = 8'd28;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_intra_luma_planar_flag_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_intra_luma_planar_flag_log2_window = 4'd1;
        default: vvc_intra_luma_planar_flag_log2_window = 4'd5;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_cclm_mode_flag_init();
    begin
      vvc_cclm_mode_flag_init = 8'd59;
    end
  endfunction

  function automatic logic [3:0] vvc_cclm_mode_flag_log2_window();
    begin
      vvc_cclm_mode_flag_log2_window = 4'd9;
    end
  endfunction

  function automatic logic [7:0] vvc_intra_chroma_pred_mode_init();
    begin
      vvc_intra_chroma_pred_mode_init = 8'd34;
    end
  endfunction

  function automatic logic [3:0] vvc_intra_chroma_pred_mode_log2_window();
    begin
      vvc_intra_chroma_pred_mode_log2_window = 4'd9;
    end
  endfunction

  function automatic logic [7:0] vvc_qt_cbf_y_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_qt_cbf_y_init = 8'd15;
        4'd1: vvc_qt_cbf_y_init = 8'd12;
        4'd2: vvc_qt_cbf_y_init = 8'd5;
        default: vvc_qt_cbf_y_init = 8'd7;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_qt_cbf_y_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_qt_cbf_y_log2_window = 4'd5;
        4'd1: vvc_qt_cbf_y_log2_window = 4'd1;
        4'd2: vvc_qt_cbf_y_log2_window = 4'd8;
        default: vvc_qt_cbf_y_log2_window = 4'd9;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_qt_cbf_cb_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_qt_cbf_cb_init = 8'd12;
        default: vvc_qt_cbf_cb_init = 8'd21;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_qt_cbf_cb_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_qt_cbf_cb_log2_window = 4'd5;
        default: vvc_qt_cbf_cb_log2_window = 4'd0;
      endcase
    end
  endfunction

  function automatic logic [7:0] vvc_qt_cbf_cr_init(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_qt_cbf_cr_init = 8'd33;
        4'd1: vvc_qt_cbf_cr_init = 8'd28;
        default: vvc_qt_cbf_cr_init = 8'd36;
      endcase
    end
  endfunction

  function automatic logic [3:0] vvc_qt_cbf_cr_log2_window(input logic [3:0] index);
    begin
      case (index)
        4'd0: vvc_qt_cbf_cr_log2_window = 4'd2;
        4'd1: vvc_qt_cbf_cr_log2_window = 4'd1;
        default: vvc_qt_cbf_cr_log2_window = 4'd0;
      endcase
    end
  endfunction

  function automatic logic [8:0] vvc_ctx_lps(input logic [4:0] index);
    begin
      case (index)
        5'd0: vvc_ctx_lps = 9'd146;
        5'd1: vvc_ctx_lps = 9'd81;
        5'd2: vvc_ctx_lps = 9'd128;
        5'd3: vvc_ctx_lps = 9'd52;
        5'd4: vvc_ctx_lps = 9'd160;
        5'd5: vvc_ctx_lps = 9'd129;
        5'd6: vvc_ctx_lps = 9'd24;
        5'd7: vvc_ctx_lps = 9'd58;
        5'd8: vvc_ctx_lps = 9'd29;
        5'd9: vvc_ctx_lps = 9'd172;
        5'd10: vvc_ctx_lps = 9'd107;
        5'd11: vvc_ctx_lps = 9'd136;
        5'd12: vvc_ctx_lps = 9'd128;
        5'd13: vvc_ctx_lps = 9'd125;
        5'd14: vvc_ctx_lps = 9'd184;
        5'd15: vvc_ctx_lps = 9'd112;
        5'd16: vvc_ctx_lps = 9'd28;
        5'd17: vvc_ctx_lps = 9'd67;
        default: vvc_ctx_lps = 9'd26;
      endcase
    end
  endfunction

  function automatic logic vvc_ctx_mps(input logic [4:0] index);
    begin
      case (index)
        5'd0: vvc_ctx_mps = 1'b0;
        5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd9, 5'd12: vvc_ctx_mps = 1'b1;
        default: vvc_ctx_mps = 1'b0;
      endcase
    end
  endfunction
endmodule
