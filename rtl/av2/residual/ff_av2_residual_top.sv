`timescale 1ns/1ps

module ff_av2_residual_top (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic        pending_push_valid,
  input  logic        state_leaf,
  input  logic        state_chroma_fetch,
  input  logic        phase_y_coeff,
  input  logic        phase_u_coeff,
  input  logic        phase_v_coeff,
  input  logic        palette_mode,
  input  logic        lossy_420_mode,
  input  logic        leaf_chroma_bdpcm_horz,
  input  logic        palette_luma_residual_zero,
  input  logic        palette_chroma_bdpcm_known_zero_hint,
  input  logic        luma_fetch_done,
  input  logic        chroma_fetch_done,
  input  logic        chroma_fetch_current_cache_hit,
  input  logic [3:0]  luma_residual_skip_ctx,
  input  logic [1:0]  luma_residual_dc_sign_ctx,
  input  logic [3:0]  chroma_bdpcm_skip_ctx,
  input  logic [127:0] luma_fetch_txb_samples,
  input  logic [127:0] luma_fetch_predictor_samples,
  input  logic [11:0] lossy420_luma_sample_sum,
  input  logic [7:0]  lossy420_luma_predictor,
  input  logic [127:0] chroma_bdpcm_txb_samples,
  input  logic [31:0] chroma_bdpcm_predictor_samples,
  input  logic [11:0] lossy420_chroma_sample_sum,
  input  logic [7:0]  lossy420_chroma_predictor,
  input  logic        residual_mode,
  output logic        luma_residual_enable,
  output logic        chroma_bdpcm_enable,
  output logic        luma_residual_op_valid,
  output logic        luma_residual_op_literal,
  output logic [31:0] luma_residual_op_literal_value,
  output logic [4:0]  luma_residual_op_literal_bits,
  output logic [31:0] luma_residual_op_fl,
  output logic [31:0] luma_residual_op_fh,
  output logic [4:0]  luma_residual_op_fl_inc,
  output logic [4:0]  luma_residual_op_fh_inc,
  output logic        luma_residual_txb_done,
  output logic [7:0]  luma_residual_entropy_context,
  output logic [7:0]  lossy420_luma_residual_recon_sample,
  output logic signed [9:0] lossy420_luma_delta,
  output logic        lossy420_luma_known_zero,
  output logic        palette_luma_residual_known_zero,
  output logic        chroma_bdpcm_op_valid,
  output logic        chroma_bdpcm_op_literal,
  output logic [31:0] chroma_bdpcm_op_literal_value,
  output logic [4:0]  chroma_bdpcm_op_literal_bits,
  output logic [31:0] chroma_bdpcm_op_fl,
  output logic [31:0] chroma_bdpcm_op_fh,
  output logic [4:0]  chroma_bdpcm_op_fl_inc,
  output logic [4:0]  chroma_bdpcm_op_fh_inc,
  output logic        chroma_bdpcm_txb_done,
  output logic        chroma_bdpcm_txb_nonzero,
  output logic [7:0]  chroma_bdpcm_entropy_context,
  output logic [7:0]  lossy420_chroma_bdpcm_recon_sample,
  output logic signed [9:0] lossy420_chroma_delta,
  output logic        lossy420_chroma_known_zero
);

  logic palette_luma_residual_op_valid_w;
  logic palette_luma_residual_op_literal_w;
  logic [31:0] palette_luma_residual_op_literal_value_w;
  logic [4:0] palette_luma_residual_op_literal_bits_w;
  logic [31:0] palette_luma_residual_op_fl_w;
  logic [31:0] palette_luma_residual_op_fh_w;
  logic [4:0] palette_luma_residual_op_fl_inc_w;
  logic [4:0] palette_luma_residual_op_fh_inc_w;
  logic palette_luma_residual_txb_done_w;
  logic [7:0] palette_luma_residual_entropy_context_w;
  logic lossy420_luma_residual_op_valid_w;
  logic lossy420_luma_residual_op_literal_w;
  logic [31:0] lossy420_luma_residual_op_literal_value_w;
  logic [4:0] lossy420_luma_residual_op_literal_bits_w;
  logic [31:0] lossy420_luma_residual_op_fl_w;
  logic [31:0] lossy420_luma_residual_op_fh_w;
  logic [4:0] lossy420_luma_residual_op_fl_inc_w;
  logic [4:0] lossy420_luma_residual_op_fh_inc_w;
  logic lossy420_luma_residual_txb_done_w;
  logic [7:0] lossy420_luma_residual_entropy_context_w;
  logic [7:0] lossy420_luma_recon_sample_w;
  logic palette_chroma_bdpcm_op_valid_w;
  logic palette_chroma_bdpcm_op_literal_w;
  logic [31:0] palette_chroma_bdpcm_op_literal_value_w;
  logic [4:0] palette_chroma_bdpcm_op_literal_bits_w;
  logic [31:0] palette_chroma_bdpcm_op_fl_w;
  logic [31:0] palette_chroma_bdpcm_op_fh_w;
  logic [4:0] palette_chroma_bdpcm_op_fl_inc_w;
  logic [4:0] palette_chroma_bdpcm_op_fh_inc_w;
  logic palette_chroma_bdpcm_txb_done_w;
  logic palette_chroma_bdpcm_txb_nonzero_w;
  logic palette_chroma_bdpcm_known_zero_w;
  logic [7:0] palette_chroma_bdpcm_entropy_context_w;
  logic lossy420_chroma_bdpcm_op_valid_w;
  logic lossy420_chroma_bdpcm_op_literal_w;
  logic [31:0] lossy420_chroma_bdpcm_op_literal_value_w;
  logic [4:0] lossy420_chroma_bdpcm_op_literal_bits_w;
  logic [31:0] lossy420_chroma_bdpcm_op_fl_w;
  logic [31:0] lossy420_chroma_bdpcm_op_fh_w;
  logic [4:0] lossy420_chroma_bdpcm_op_fl_inc_w;
  logic [4:0] lossy420_chroma_bdpcm_op_fh_inc_w;
  logic lossy420_chroma_bdpcm_txb_done_w;
  logic lossy420_chroma_bdpcm_txb_nonzero_w;
  logic [7:0] lossy420_chroma_bdpcm_entropy_context_w;
  logic [7:0] lossy420_chroma_recon_sample_w;
  logic luma_residual_advance_w;
  logic palette_luma_residual_advance_w;
  logic lossy420_luma_residual_advance_w;
  logic luma_residual_enable_w;
  logic palette_luma_residual_enable_w;
  logic lossy420_luma_residual_enable_w;
  logic chroma_bdpcm_advance_w;
  logic palette_chroma_bdpcm_advance_w;
  logic lossy420_chroma_bdpcm_advance_w;
  logic chroma_residual_phase_w;
  logic chroma_bdpcm_fetch_ready_w;
  logic palette_chroma_bdpcm_cache_ready_w;
  logic palette_chroma_bdpcm_enable_w;
  logic lossy420_chroma_bdpcm_enable_w;

  ff_av2_chroma_bdpcm_symbolizer #(
    .LUMA_PALETTE_RESIDUAL(1)
  ) luma_palette_residual_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(palette_luma_residual_enable_w),
    .advance(palette_luma_residual_advance_w),
    .plane_v(1'b0),
    .bdpcm_horz(1'b1),
    .skip_ctx(luma_residual_skip_ctx),
    .dc_sign_ctx(luma_residual_dc_sign_ctx),
    .txb_samples(luma_fetch_txb_samples),
    .predictor_samples(32'd0),
    .predictor_txb_samples(luma_fetch_predictor_samples),
    .dc_delta(10'sd0),
    .dc_recon_sample(8'd0),
    .known_zero_txb(palette_luma_residual_known_zero),
    .op_valid(palette_luma_residual_op_valid_w),
    .op_literal(palette_luma_residual_op_literal_w),
    .op_literal_value(palette_luma_residual_op_literal_value_w),
    .op_literal_bits(palette_luma_residual_op_literal_bits_w),
    .op_fl(palette_luma_residual_op_fl_w),
    .op_fh(palette_luma_residual_op_fh_w),
    .op_fl_inc(palette_luma_residual_op_fl_inc_w),
    .op_fh_inc(palette_luma_residual_op_fh_inc_w),
    .txb_done(palette_luma_residual_txb_done_w),
    .txb_nonzero(),
    .entropy_context(palette_luma_residual_entropy_context_w),
    .latched_dc_recon_sample()
  );

  ff_av2_lossy420_dc_estimator lossy420_luma_dc_estimator (
    .sample_sum(lossy420_luma_sample_sum),
    .predictor(lossy420_luma_predictor),
    .delta(lossy420_luma_delta),
    .recon_sample(lossy420_luma_recon_sample_w),
    .zero_delta(lossy420_luma_known_zero)
  );

  ff_av2_dc_delta_txb_symbolizer #(
    .LUMA_PLANE(1)
  ) lossy420_luma_residual_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(lossy420_luma_residual_enable_w),
    .advance(lossy420_luma_residual_advance_w),
    .emit_first_cycle(state_leaf),
    .plane_v(1'b0),
    .skip_ctx(luma_residual_skip_ctx),
    .dc_sign_ctx(luma_residual_dc_sign_ctx),
    .dc_delta(lossy420_luma_delta),
    .dc_recon_sample(lossy420_luma_recon_sample_w),
    .known_zero_txb(lossy420_luma_known_zero),
    .op_valid(lossy420_luma_residual_op_valid_w),
    .op_literal(lossy420_luma_residual_op_literal_w),
    .op_literal_value(lossy420_luma_residual_op_literal_value_w),
    .op_literal_bits(lossy420_luma_residual_op_literal_bits_w),
    .op_fl(lossy420_luma_residual_op_fl_w),
    .op_fh(lossy420_luma_residual_op_fh_w),
    .op_fl_inc(lossy420_luma_residual_op_fl_inc_w),
    .op_fh_inc(lossy420_luma_residual_op_fh_inc_w),
    .txb_done(lossy420_luma_residual_txb_done_w),
    .txb_nonzero(),
    .entropy_context(lossy420_luma_residual_entropy_context_w),
    .latched_dc_recon_sample(lossy420_luma_residual_recon_sample)
  );

  ff_av2_chroma_bdpcm_symbolizer #(
    .LUMA_PALETTE_RESIDUAL(0)
  ) chroma_bdpcm_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(palette_chroma_bdpcm_enable_w),
    .advance(palette_chroma_bdpcm_advance_w),
    .plane_v(phase_v_coeff),
    .bdpcm_horz(leaf_chroma_bdpcm_horz),
    .skip_ctx(chroma_bdpcm_skip_ctx),
    .dc_sign_ctx(2'd0),
    .txb_samples(chroma_bdpcm_txb_samples),
    .predictor_samples(chroma_bdpcm_predictor_samples),
    .predictor_txb_samples(128'd0),
    .dc_delta(10'sd0),
    .dc_recon_sample(8'd0),
    .known_zero_txb(palette_chroma_bdpcm_known_zero_w),
    .op_valid(palette_chroma_bdpcm_op_valid_w),
    .op_literal(palette_chroma_bdpcm_op_literal_w),
    .op_literal_value(palette_chroma_bdpcm_op_literal_value_w),
    .op_literal_bits(palette_chroma_bdpcm_op_literal_bits_w),
    .op_fl(palette_chroma_bdpcm_op_fl_w),
    .op_fh(palette_chroma_bdpcm_op_fh_w),
    .op_fl_inc(palette_chroma_bdpcm_op_fl_inc_w),
    .op_fh_inc(palette_chroma_bdpcm_op_fh_inc_w),
    .txb_done(palette_chroma_bdpcm_txb_done_w),
    .txb_nonzero(palette_chroma_bdpcm_txb_nonzero_w),
    .entropy_context(palette_chroma_bdpcm_entropy_context_w),
    .latched_dc_recon_sample()
  );

  ff_av2_lossy420_dc_estimator lossy420_chroma_dc_estimator (
    .sample_sum(lossy420_chroma_sample_sum),
    .predictor(lossy420_chroma_predictor),
    .delta(lossy420_chroma_delta),
    .recon_sample(lossy420_chroma_recon_sample_w),
    .zero_delta(lossy420_chroma_known_zero)
  );

  ff_av2_dc_delta_txb_symbolizer #(
    .LUMA_PLANE(0)
  ) lossy420_chroma_bdpcm_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .enable(lossy420_chroma_bdpcm_enable_w),
    .advance(lossy420_chroma_bdpcm_advance_w),
    .emit_first_cycle(state_leaf),
    .plane_v(phase_v_coeff),
    .skip_ctx(chroma_bdpcm_skip_ctx),
    .dc_sign_ctx(2'd0),
    .dc_delta(lossy420_chroma_delta),
    .dc_recon_sample(lossy420_chroma_recon_sample_w),
    .known_zero_txb(lossy420_chroma_known_zero),
    .op_valid(lossy420_chroma_bdpcm_op_valid_w),
    .op_literal(lossy420_chroma_bdpcm_op_literal_w),
    .op_literal_value(lossy420_chroma_bdpcm_op_literal_value_w),
    .op_literal_bits(lossy420_chroma_bdpcm_op_literal_bits_w),
    .op_fl(lossy420_chroma_bdpcm_op_fl_w),
    .op_fh(lossy420_chroma_bdpcm_op_fh_w),
    .op_fl_inc(lossy420_chroma_bdpcm_op_fl_inc_w),
    .op_fh_inc(lossy420_chroma_bdpcm_op_fh_inc_w),
    .txb_done(lossy420_chroma_bdpcm_txb_done_w),
    .txb_nonzero(lossy420_chroma_bdpcm_txb_nonzero_w),
    .entropy_context(lossy420_chroma_bdpcm_entropy_context_w),
    .latched_dc_recon_sample(lossy420_chroma_bdpcm_recon_sample)
  );

  assign luma_residual_op_valid =
    lossy_420_mode ? lossy420_luma_residual_op_valid_w : palette_luma_residual_op_valid_w;
  assign luma_residual_op_literal =
    lossy_420_mode ? lossy420_luma_residual_op_literal_w : palette_luma_residual_op_literal_w;
  assign luma_residual_op_literal_value =
    lossy_420_mode ? lossy420_luma_residual_op_literal_value_w : palette_luma_residual_op_literal_value_w;
  assign luma_residual_op_literal_bits =
    lossy_420_mode ? lossy420_luma_residual_op_literal_bits_w : palette_luma_residual_op_literal_bits_w;
  assign luma_residual_op_fl =
    lossy_420_mode ? lossy420_luma_residual_op_fl_w : palette_luma_residual_op_fl_w;
  assign luma_residual_op_fh =
    lossy_420_mode ? lossy420_luma_residual_op_fh_w : palette_luma_residual_op_fh_w;
  assign luma_residual_op_fl_inc =
    lossy_420_mode ? lossy420_luma_residual_op_fl_inc_w : palette_luma_residual_op_fl_inc_w;
  assign luma_residual_op_fh_inc =
    lossy_420_mode ? lossy420_luma_residual_op_fh_inc_w : palette_luma_residual_op_fh_inc_w;
  assign luma_residual_txb_done =
    lossy_420_mode ? lossy420_luma_residual_txb_done_w : palette_luma_residual_txb_done_w;
  assign luma_residual_entropy_context =
    lossy_420_mode ? lossy420_luma_residual_entropy_context_w : palette_luma_residual_entropy_context_w;
  assign chroma_bdpcm_op_valid =
    lossy_420_mode ? lossy420_chroma_bdpcm_op_valid_w : palette_chroma_bdpcm_op_valid_w;
  assign chroma_bdpcm_op_literal =
    lossy_420_mode ? lossy420_chroma_bdpcm_op_literal_w : palette_chroma_bdpcm_op_literal_w;
  assign chroma_bdpcm_op_literal_value =
    lossy_420_mode ? lossy420_chroma_bdpcm_op_literal_value_w : palette_chroma_bdpcm_op_literal_value_w;
  assign chroma_bdpcm_op_literal_bits =
    lossy_420_mode ? lossy420_chroma_bdpcm_op_literal_bits_w : palette_chroma_bdpcm_op_literal_bits_w;
  assign chroma_bdpcm_op_fl =
    lossy_420_mode ? lossy420_chroma_bdpcm_op_fl_w : palette_chroma_bdpcm_op_fl_w;
  assign chroma_bdpcm_op_fh =
    lossy_420_mode ? lossy420_chroma_bdpcm_op_fh_w : palette_chroma_bdpcm_op_fh_w;
  assign chroma_bdpcm_op_fl_inc =
    lossy_420_mode ? lossy420_chroma_bdpcm_op_fl_inc_w : palette_chroma_bdpcm_op_fl_inc_w;
  assign chroma_bdpcm_op_fh_inc =
    lossy_420_mode ? lossy420_chroma_bdpcm_op_fh_inc_w : palette_chroma_bdpcm_op_fh_inc_w;
  assign chroma_bdpcm_txb_done =
    lossy_420_mode ? lossy420_chroma_bdpcm_txb_done_w : palette_chroma_bdpcm_txb_done_w;
  assign chroma_bdpcm_txb_nonzero =
    lossy_420_mode ? lossy420_chroma_bdpcm_txb_nonzero_w : palette_chroma_bdpcm_txb_nonzero_w;
  assign chroma_bdpcm_entropy_context =
    lossy_420_mode ? lossy420_chroma_bdpcm_entropy_context_w : palette_chroma_bdpcm_entropy_context_w;

  // AV2 v1.0.0 Section 5.20.7.27 coeffs(): the palette path can skip a
  // TX_4X4 when every luma sample equals its predictor. The analyzer's
  // block-level zero flag catches all-zero 8x8 leaves; this narrower check
  // also lets mixed 8x8 leaves take the symbolizer's zero-TXB fast path.
  assign palette_luma_residual_known_zero =
    palette_luma_residual_zero ||
    ((luma_fetch_txb_samples[0 * 8 +: 8] == luma_fetch_predictor_samples[0 * 8 +: 8]) &&
     (luma_fetch_txb_samples[1 * 8 +: 8] == luma_fetch_predictor_samples[1 * 8 +: 8]) &&
     (luma_fetch_txb_samples[2 * 8 +: 8] == luma_fetch_predictor_samples[2 * 8 +: 8]) &&
     (luma_fetch_txb_samples[3 * 8 +: 8] == luma_fetch_predictor_samples[3 * 8 +: 8]) &&
     (luma_fetch_txb_samples[4 * 8 +: 8] == luma_fetch_predictor_samples[4 * 8 +: 8]) &&
     (luma_fetch_txb_samples[5 * 8 +: 8] == luma_fetch_predictor_samples[5 * 8 +: 8]) &&
     (luma_fetch_txb_samples[6 * 8 +: 8] == luma_fetch_predictor_samples[6 * 8 +: 8]) &&
     (luma_fetch_txb_samples[7 * 8 +: 8] == luma_fetch_predictor_samples[7 * 8 +: 8]) &&
     (luma_fetch_txb_samples[8 * 8 +: 8] == luma_fetch_predictor_samples[8 * 8 +: 8]) &&
     (luma_fetch_txb_samples[9 * 8 +: 8] == luma_fetch_predictor_samples[9 * 8 +: 8]) &&
     (luma_fetch_txb_samples[10 * 8 +: 8] == luma_fetch_predictor_samples[10 * 8 +: 8]) &&
     (luma_fetch_txb_samples[11 * 8 +: 8] == luma_fetch_predictor_samples[11 * 8 +: 8]) &&
     (luma_fetch_txb_samples[12 * 8 +: 8] == luma_fetch_predictor_samples[12 * 8 +: 8]) &&
     (luma_fetch_txb_samples[13 * 8 +: 8] == luma_fetch_predictor_samples[13 * 8 +: 8]) &&
     (luma_fetch_txb_samples[14 * 8 +: 8] == luma_fetch_predictor_samples[14 * 8 +: 8]) &&
     (luma_fetch_txb_samples[15 * 8 +: 8] == luma_fetch_predictor_samples[15 * 8 +: 8]));

  assign luma_residual_advance_w =
    !start &&
    !pending_push_valid &&
    state_leaf &&
    residual_mode &&
    phase_y_coeff &&
    luma_residual_op_valid;
  assign palette_luma_residual_advance_w = luma_residual_advance_w && palette_mode;
  assign lossy420_luma_residual_advance_w = luma_residual_advance_w && lossy_420_mode;
  assign luma_residual_enable_w =
    residual_mode &&
    phase_y_coeff &&
    (state_leaf || (!lossy_420_mode && state_chroma_fetch && luma_fetch_done));
  assign palette_luma_residual_enable_w = luma_residual_enable_w && palette_mode;
  assign lossy420_luma_residual_enable_w = luma_residual_enable_w && lossy_420_mode;
  assign luma_residual_enable = luma_residual_enable_w;

  assign chroma_bdpcm_advance_w =
    !start &&
    !pending_push_valid &&
    state_leaf &&
    residual_mode &&
    (phase_u_coeff || phase_v_coeff) &&
    chroma_bdpcm_op_valid;
  assign palette_chroma_bdpcm_advance_w = chroma_bdpcm_advance_w && palette_mode;
  assign lossy420_chroma_bdpcm_advance_w = chroma_bdpcm_advance_w && lossy_420_mode;
  assign chroma_residual_phase_w =
    residual_mode &&
    (phase_u_coeff || phase_v_coeff);
  assign chroma_bdpcm_fetch_ready_w =
    state_leaf ||
    (state_chroma_fetch && chroma_fetch_done);
  assign palette_chroma_bdpcm_cache_ready_w =
    state_chroma_fetch && chroma_fetch_current_cache_hit;
  assign palette_chroma_bdpcm_enable_w =
    palette_mode &&
    chroma_residual_phase_w &&
    (chroma_bdpcm_fetch_ready_w || palette_chroma_bdpcm_cache_ready_w);
  assign lossy420_chroma_bdpcm_enable_w =
    lossy_420_mode &&
    chroma_residual_phase_w &&
    state_leaf;
  assign chroma_bdpcm_enable =
    palette_mode ? palette_chroma_bdpcm_enable_w : lossy420_chroma_bdpcm_enable_w;

  // AV2 v1.0.0 Section 5.20.7.27 coeffs(): for FrameForge's staged chroma
  // BDPCM residual path, a zero TXB is completely determined by the row
  // or column predictor and already reconstructed samples. Detect it before
  // the residual symbolizer so zero chroma TXBs emit only the skip symbol.
  assign palette_chroma_bdpcm_known_zero_w =
    palette_chroma_bdpcm_known_zero_hint ||
    (leaf_chroma_bdpcm_horz ?
      ((chroma_bdpcm_txb_samples[0 * 8 +: 8] == chroma_bdpcm_predictor_samples[0 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[1 * 8 +: 8] == chroma_bdpcm_txb_samples[0 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[2 * 8 +: 8] == chroma_bdpcm_txb_samples[1 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[3 * 8 +: 8] == chroma_bdpcm_txb_samples[2 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[4 * 8 +: 8] == chroma_bdpcm_predictor_samples[1 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[5 * 8 +: 8] == chroma_bdpcm_txb_samples[4 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[6 * 8 +: 8] == chroma_bdpcm_txb_samples[5 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[7 * 8 +: 8] == chroma_bdpcm_txb_samples[6 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[8 * 8 +: 8] == chroma_bdpcm_predictor_samples[2 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[9 * 8 +: 8] == chroma_bdpcm_txb_samples[8 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[10 * 8 +: 8] == chroma_bdpcm_txb_samples[9 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[11 * 8 +: 8] == chroma_bdpcm_txb_samples[10 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[12 * 8 +: 8] == chroma_bdpcm_predictor_samples[3 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[13 * 8 +: 8] == chroma_bdpcm_txb_samples[12 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[14 * 8 +: 8] == chroma_bdpcm_txb_samples[13 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[15 * 8 +: 8] == chroma_bdpcm_txb_samples[14 * 8 +: 8])) :
      ((chroma_bdpcm_txb_samples[0 * 8 +: 8] == chroma_bdpcm_predictor_samples[0 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[1 * 8 +: 8] == chroma_bdpcm_predictor_samples[1 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[2 * 8 +: 8] == chroma_bdpcm_predictor_samples[2 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[3 * 8 +: 8] == chroma_bdpcm_predictor_samples[3 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[4 * 8 +: 8] == chroma_bdpcm_txb_samples[0 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[5 * 8 +: 8] == chroma_bdpcm_txb_samples[1 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[6 * 8 +: 8] == chroma_bdpcm_txb_samples[2 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[7 * 8 +: 8] == chroma_bdpcm_txb_samples[3 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[8 * 8 +: 8] == chroma_bdpcm_txb_samples[4 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[9 * 8 +: 8] == chroma_bdpcm_txb_samples[5 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[10 * 8 +: 8] == chroma_bdpcm_txb_samples[6 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[11 * 8 +: 8] == chroma_bdpcm_txb_samples[7 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[12 * 8 +: 8] == chroma_bdpcm_txb_samples[8 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[13 * 8 +: 8] == chroma_bdpcm_txb_samples[9 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[14 * 8 +: 8] == chroma_bdpcm_txb_samples[10 * 8 +: 8]) &&
       (chroma_bdpcm_txb_samples[15 * 8 +: 8] == chroma_bdpcm_txb_samples[11 * 8 +: 8])));

endmodule
