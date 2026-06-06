`timescale 1ns/1ps

module ff_vvc_chroma_quant_recon_420 (
  input  logic [(8 * 4 * 4) - 1:0] samples,
  input  logic [(8 * 4) - 1:0] top_ref,
  input  logic [(8 * 4) - 1:0] left_ref,
  output logic signed [8:0] dc_level,
  output logic [(8 * 15) - 1:0] ac_levels,
  output logic [(8 * 4 * 4) - 1:0] recon_samples
);
  localparam int MAX_SIZE = 4;
  localparam int MAX_SAMPLES = MAX_SIZE * MAX_SIZE;
  localparam int DCT2_4_BASIS_BITS = 9;
  localparam logic signed [(DCT2_4_BASIS_BITS * MAX_SIZE) - 1:0] DCT2_4_ROW1_PACK = {
    -9'sd83, -9'sd36, 9'sd36, 9'sd83
  };

  logic [(8 * MAX_SAMPLES) - 1:0] predicted_pack_tmp;
  logic [(16 * MAX_SAMPLES) - 1:0] residual_pack_tmp;
  logic signed [63:0] ac_acc_10_tmp;
  logic signed [63:0] ac_acc_01_tmp;
  logic signed [63:0] ac_acc_11_tmp;
  logic signed [63:0] abs_acc_tmp;
  logic signed [63:0] rounded_level_tmp;
  logic signed [63:0] scaled_level_tmp;
  logic signed [63:0] recon_sum_tmp;
  logic signed [31:0] residual_sum_tmp;
  logic signed [31:0] residual_value_tmp;
  logic signed [31:0] pdpc_wl_tmp;
  logic signed [31:0] pdpc_wt_tmp;
  logic signed [31:0] pdpc_val_tmp;
  logic signed [31:0] recon_residual_tmp;
  logic signed [31:0] recon_sample_tmp;
  logic signed [31:0] vertical_0_tmp;
  logic signed [31:0] vertical_1_tmp;
  logic signed [31:0] dequant_dc_tmp;
  logic signed [31:0] dequant_10_tmp;
  logic signed [31:0] dequant_01_tmp;
  logic signed [31:0] dequant_11_tmp;
  logic signed [8:0] ac_level_10_tmp;
  logic signed [8:0] ac_level_01_tmp;
  logic signed [8:0] ac_level_11_tmp;
  logic signed [8:0] quant_level_tmp;
  logic signed [8:0] dc_level_abs_tmp;
  logic signed [31:0] dc_level_abs_wide_tmp;
  logic signed [8:0] basis_x_tmp;
  logic signed [8:0] basis_y_tmp;
  logic [31:0] dc_ref_sum_tmp;
  logic [31:0] pdpc_index_tmp;
  logic [7:0] dc_pred_tmp;
  logic [7:0] predicted_value_tmp;
  logic [7:0] sample_tmp;

  integer idx;
  integer x_i;
  integer y_i;
  integer basis_index_tmp;

  always @* begin
    dc_level = 9'sd0;
    ac_levels = '0;
    recon_samples = '0;
    predicted_pack_tmp = '0;
    residual_pack_tmp = '0;
    residual_sum_tmp = 32'sd0;
    dc_ref_sum_tmp = 32'd0;
    dc_pred_tmp = 8'd128;
    ac_acc_10_tmp = 64'sd0;
    ac_acc_01_tmp = 64'sd0;
    ac_acc_11_tmp = 64'sd0;
    ac_level_10_tmp = 9'sd0;
    ac_level_01_tmp = 9'sd0;
    ac_level_11_tmp = 9'sd0;
    dequant_dc_tmp = 32'sd0;
    dequant_10_tmp = 32'sd0;
    dequant_01_tmp = 32'sd0;
    dequant_11_tmp = 32'sd0;
    basis_x_tmp = 9'sd64;
    basis_y_tmp = 9'sd64;
    dc_level_abs_wide_tmp = 32'sd0;
    basis_index_tmp = 0;

    for (idx = 0; idx < MAX_SIZE; idx = idx + 1) begin
      dc_ref_sum_tmp =
        dc_ref_sum_tmp + {24'd0, top_ref[idx * 8 +: 8]} + {24'd0, left_ref[idx * 8 +: 8]};
    end
    dc_pred_tmp = (dc_ref_sum_tmp + 32'd4) >> 3;

    // H.266 8.4.5 derives DC/PDPC chroma prediction from reconstructed
    // neighbouring samples before 7.3.11.10 transform_unit() residual syntax.
    // This fixed 4:2:0 path keeps DC plus the 2x2 low-frequency AC group.
    for (y_i = 0; y_i < MAX_SIZE; y_i = y_i + 1) begin
      for (x_i = 0; x_i < MAX_SIZE; x_i = x_i + 1) begin
        idx = (y_i * MAX_SIZE) + x_i;
        pdpc_index_tmp = x_i << 1;
        pdpc_wl_tmp = 32'sd32 >>> pdpc_index_tmp;
        pdpc_index_tmp = y_i << 1;
        pdpc_wt_tmp = 32'sd32 >>> pdpc_index_tmp;
        pdpc_val_tmp =
          $signed({24'd0, dc_pred_tmp}) +
          (((pdpc_wl_tmp *
             ($signed({24'd0, left_ref[y_i * 8 +: 8]}) -
              $signed({24'd0, dc_pred_tmp}))) +
            (pdpc_wt_tmp *
             ($signed({24'd0, top_ref[x_i * 8 +: 8]}) -
              $signed({24'd0, dc_pred_tmp}))) +
            32'sd32) >>> 6);
        if (pdpc_val_tmp < 32'sd0) begin
          predicted_value_tmp = 8'd0;
        end else if (pdpc_val_tmp > 32'sd255) begin
          predicted_value_tmp = 8'd255;
        end else begin
          predicted_value_tmp = pdpc_val_tmp[7:0];
        end
        predicted_pack_tmp[idx * 8 +: 8] = predicted_value_tmp;

        sample_tmp = samples[idx * 8 +: 8];
        residual_value_tmp =
          $signed({8'd0, sample_tmp}) - $signed({8'd0, predicted_value_tmp});
        residual_pack_tmp[idx * 16 +: 16] = residual_value_tmp[15:0];
        residual_sum_tmp = residual_sum_tmp + residual_value_tmp;

        basis_index_tmp = x_i * DCT2_4_BASIS_BITS;
        basis_x_tmp = $signed(DCT2_4_ROW1_PACK[basis_index_tmp +: DCT2_4_BASIS_BITS]);
        basis_index_tmp = y_i * DCT2_4_BASIS_BITS;
        basis_y_tmp = $signed(DCT2_4_ROW1_PACK[basis_index_tmp +: DCT2_4_BASIS_BITS]);
        ac_acc_10_tmp =
          ac_acc_10_tmp + ($signed(residual_value_tmp[15:0]) * basis_x_tmp * 9'sd64);
        ac_acc_01_tmp =
          ac_acc_01_tmp + ($signed(residual_value_tmp[15:0]) * 9'sd64 * basis_y_tmp);
        ac_acc_11_tmp =
          ac_acc_11_tmp + ($signed(residual_value_tmp[15:0]) * basis_x_tmp * basis_y_tmp);
      end
    end

    // For H.266 8.7.3 and 8.7.4 at 4x4 chroma QP 34, the DC-only inverse
    // residual is 8 * level. This is equivalent to the software SSE search,
    // including its strict-improvement tie behaviour.
    if ((residual_sum_tmp >= -32'sd64) && (residual_sum_tmp <= 32'sd64)) begin
      dc_level = 9'sd0;
    end else if (residual_sum_tmp > 32'sd64) begin
      dc_level_abs_wide_tmp = (residual_sum_tmp + 32'sd63) >>> 7;
      dc_level_abs_tmp = $signed(dc_level_abs_wide_tmp[8:0]);
      dc_level = dc_level_abs_tmp;
    end else begin
      dc_level_abs_wide_tmp = ((-residual_sum_tmp) + 32'sd64) >>> 7;
      dc_level_abs_tmp = $signed(dc_level_abs_wide_tmp[8:0]);
      dc_level = -dc_level_abs_tmp;
    end

    abs_acc_tmp = ac_acc_10_tmp[63] ? -ac_acc_10_tmp : ac_acc_10_tmp;
    rounded_level_tmp = (abs_acc_tmp + 64'sd65536) >>> 17;
    quant_level_tmp = (rounded_level_tmp > 64'sd2) ? 9'sd2 : rounded_level_tmp[8:0];
    ac_level_10_tmp = ac_acc_10_tmp[63] ? -quant_level_tmp : quant_level_tmp;

    abs_acc_tmp = ac_acc_01_tmp[63] ? -ac_acc_01_tmp : ac_acc_01_tmp;
    rounded_level_tmp = (abs_acc_tmp + 64'sd65536) >>> 17;
    quant_level_tmp = (rounded_level_tmp > 64'sd2) ? 9'sd2 : rounded_level_tmp[8:0];
    ac_level_01_tmp = ac_acc_01_tmp[63] ? -quant_level_tmp : quant_level_tmp;

    abs_acc_tmp = ac_acc_11_tmp[63] ? -ac_acc_11_tmp : ac_acc_11_tmp;
    rounded_level_tmp = (abs_acc_tmp + 64'sd65536) >>> 17;
    quant_level_tmp = (rounded_level_tmp > 64'sd2) ? 9'sd2 : rounded_level_tmp[8:0];
    ac_level_11_tmp = ac_acc_11_tmp[63] ? -quant_level_tmp : quant_level_tmp;

    ac_levels = '0;
    ac_levels[(14 * 8) +: 8] = ac_level_10_tmp[7:0];
    ac_levels[(11 * 8) +: 8] = ac_level_01_tmp[7:0];
    ac_levels[(10 * 8) +: 8] = ac_level_11_tmp[7:0];

    scaled_level_tmp = ($signed(dc_level) * 64'sd32768) + 64'sd16;
    dequant_dc_tmp = (dc_level == 9'sd0) ? 32'sd0 : (scaled_level_tmp >>> 5);
    scaled_level_tmp = ($signed(ac_level_10_tmp) * 64'sd32768) + 64'sd16;
    dequant_10_tmp = (ac_level_10_tmp == 9'sd0) ? 32'sd0 : (scaled_level_tmp >>> 5);
    scaled_level_tmp = ($signed(ac_level_01_tmp) * 64'sd32768) + 64'sd16;
    dequant_01_tmp = (ac_level_01_tmp == 9'sd0) ? 32'sd0 : (scaled_level_tmp >>> 5);
    scaled_level_tmp = ($signed(ac_level_11_tmp) * 64'sd32768) + 64'sd16;
    dequant_11_tmp = (ac_level_11_tmp == 9'sd0) ? 32'sd0 : (scaled_level_tmp >>> 5);

    for (y_i = 0; y_i < MAX_SIZE; y_i = y_i + 1) begin
      basis_index_tmp = y_i * DCT2_4_BASIS_BITS;
      basis_y_tmp = $signed(DCT2_4_ROW1_PACK[basis_index_tmp +: DCT2_4_BASIS_BITS]);
      vertical_0_tmp = ((32'sd64 * dequant_dc_tmp) + (basis_y_tmp * dequant_01_tmp) + 32'sd64) >>> 7;
      vertical_1_tmp = ((32'sd64 * dequant_10_tmp) + (basis_y_tmp * dequant_11_tmp) + 32'sd64) >>> 7;

      for (x_i = 0; x_i < MAX_SIZE; x_i = x_i + 1) begin
        basis_index_tmp = x_i * DCT2_4_BASIS_BITS;
        basis_x_tmp = $signed(DCT2_4_ROW1_PACK[basis_index_tmp +: DCT2_4_BASIS_BITS]);
        recon_sum_tmp = (64'sd64 * vertical_0_tmp) + (basis_x_tmp * vertical_1_tmp);
        recon_residual_tmp = (recon_sum_tmp + 64'sd2048) >>> 12;
        idx = (y_i * MAX_SIZE) + x_i;
        predicted_value_tmp = predicted_pack_tmp[idx * 8 +: 8];
        recon_sample_tmp = $signed({24'd0, predicted_value_tmp}) + recon_residual_tmp;
        if (recon_sample_tmp < 32'sd0) begin
          recon_samples[idx * 8 +: 8] = 8'd0;
        end else if (recon_sample_tmp > 32'sd255) begin
          recon_samples[idx * 8 +: 8] = 8'd255;
        end else begin
          recon_samples[idx * 8 +: 8] = recon_sample_tmp[7:0];
        end
      end
    end
  end
endmodule
