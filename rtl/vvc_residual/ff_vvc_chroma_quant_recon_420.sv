`timescale 1ns/1ps

`define FF_VVC_CHROMA_MUL36(V) (((V) <<< 5) + ((V) <<< 2))
`define FF_VVC_CHROMA_MUL64(V) ((V) <<< 6)
`define FF_VVC_CHROMA_MUL83(V) (((V) <<< 6) + ((V) <<< 4) + ((V) <<< 1) + (V))

module ff_vvc_chroma_quant_recon_420 (
  input  logic [(8 * 4 * 4) - 1:0] samples,
  input  logic [(8 * 4) - 1:0] top_ref,
  input  logic [(8 * 4) - 1:0] left_ref,
  output logic signed [8:0] dc_level,
  output logic [(4 * 3) - 1:0] ac_levels,
  output logic [(8 * 4) - 1:0] bottom_ref,
  output logic [(8 * 4) - 1:0] right_ref
);
  localparam int MAX_SIZE = 4;
  localparam int MAX_SAMPLES = MAX_SIZE * MAX_SIZE;

  logic [(8 * MAX_SAMPLES) - 1:0] predicted_pack_tmp;
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
  logic signed [31:0] residual_wide_tmp;
  logic signed [31:0] basis_x_term_tmp;
  logic signed [31:0] basis_y_term_tmp;
  logic signed [63:0] basis_xy_term_tmp;
  logic signed [8:0] ac_level_10_tmp;
  logic signed [8:0] ac_level_01_tmp;
  logic signed [8:0] ac_level_11_tmp;
  logic signed [8:0] quant_level_tmp;
  logic signed [8:0] dc_level_abs_tmp;
  logic signed [31:0] dc_level_abs_wide_tmp;
  logic [31:0] dc_ref_sum_tmp;
  logic [7:0] dc_pred_tmp;
  logic [7:0] predicted_value_tmp;
  logic [7:0] recon_clipped_tmp;
  logic [7:0] sample_tmp;

  integer idx;
  integer x_i;
  integer y_i;

  always @* begin
    dc_level = 9'sd0;
    ac_levels = '0;
    bottom_ref = '0;
    right_ref = '0;
    predicted_pack_tmp = '0;
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
    basis_x_term_tmp = 32'sd0;
    basis_y_term_tmp = 32'sd0;
    basis_xy_term_tmp = 64'sd0;
    residual_wide_tmp = 32'sd0;
    dc_level_abs_wide_tmp = 32'sd0;
    recon_clipped_tmp = 8'd0;

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
        case (x_i)
          0: pdpc_wl_tmp = 32'sd32;
          1: pdpc_wl_tmp = 32'sd8;
          2: pdpc_wl_tmp = 32'sd2;
          default: pdpc_wl_tmp = 32'sd0;
        endcase
        case (y_i)
          0: pdpc_wt_tmp = 32'sd32;
          1: pdpc_wt_tmp = 32'sd8;
          2: pdpc_wt_tmp = 32'sd2;
          default: pdpc_wt_tmp = 32'sd0;
        endcase
        pdpc_val_tmp =
          $signed({24'd0, dc_pred_tmp}) +
          (((((pdpc_wl_tmp == 32'sd32) ?
              (($signed({24'd0, left_ref[y_i * 8 +: 8]}) -
                $signed({24'd0, dc_pred_tmp})) <<< 5) :
              ((pdpc_wl_tmp == 32'sd8) ?
               (($signed({24'd0, left_ref[y_i * 8 +: 8]}) -
                 $signed({24'd0, dc_pred_tmp})) <<< 3) :
               ((pdpc_wl_tmp == 32'sd2) ?
                (($signed({24'd0, left_ref[y_i * 8 +: 8]}) -
                  $signed({24'd0, dc_pred_tmp})) <<< 1) :
                32'sd0))) +
             ((pdpc_wt_tmp == 32'sd32) ?
              (($signed({24'd0, top_ref[x_i * 8 +: 8]}) -
                $signed({24'd0, dc_pred_tmp})) <<< 5) :
              ((pdpc_wt_tmp == 32'sd8) ?
               (($signed({24'd0, top_ref[x_i * 8 +: 8]}) -
                 $signed({24'd0, dc_pred_tmp})) <<< 3) :
               ((pdpc_wt_tmp == 32'sd2) ?
                (($signed({24'd0, top_ref[x_i * 8 +: 8]}) -
                  $signed({24'd0, dc_pred_tmp})) <<< 1) :
                32'sd0)))) +
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
        residual_sum_tmp = residual_sum_tmp + residual_value_tmp;

        residual_wide_tmp = $signed(residual_value_tmp[15:0]);
        case (x_i)
          0: begin
            basis_x_term_tmp = `FF_VVC_CHROMA_MUL83(residual_wide_tmp);
          end
          1: begin
            basis_x_term_tmp = `FF_VVC_CHROMA_MUL36(residual_wide_tmp);
          end
          2: begin
            basis_x_term_tmp = -`FF_VVC_CHROMA_MUL36(residual_wide_tmp);
          end
          default: begin
            basis_x_term_tmp = -`FF_VVC_CHROMA_MUL83(residual_wide_tmp);
          end
        endcase
        case (y_i)
          0: begin
            basis_y_term_tmp = `FF_VVC_CHROMA_MUL83(residual_wide_tmp);
            basis_xy_term_tmp = `FF_VVC_CHROMA_MUL83(basis_x_term_tmp);
          end
          1: begin
            basis_y_term_tmp = `FF_VVC_CHROMA_MUL36(residual_wide_tmp);
            basis_xy_term_tmp = `FF_VVC_CHROMA_MUL36(basis_x_term_tmp);
          end
          2: begin
            basis_y_term_tmp = -`FF_VVC_CHROMA_MUL36(residual_wide_tmp);
            basis_xy_term_tmp = -`FF_VVC_CHROMA_MUL36(basis_x_term_tmp);
          end
          default: begin
            basis_y_term_tmp = -`FF_VVC_CHROMA_MUL83(residual_wide_tmp);
            basis_xy_term_tmp = -`FF_VVC_CHROMA_MUL83(basis_x_term_tmp);
          end
        endcase
        ac_acc_10_tmp = ac_acc_10_tmp + `FF_VVC_CHROMA_MUL64(basis_x_term_tmp);
        ac_acc_01_tmp = ac_acc_01_tmp + `FF_VVC_CHROMA_MUL64(basis_y_term_tmp);
        ac_acc_11_tmp = ac_acc_11_tmp + basis_xy_term_tmp;
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

    // H.266 7.3.11.10 transform_unit() codes coefficients in 4x4 raster
    // coordinates. This lossy 4:2:0 subset stores only the 2x2 AC positions:
    // slot 0=(1,0), slot 1=(0,1), slot 2=(1,1).
    ac_levels = '0;
    ac_levels[(0 * 4) +: 4] = ac_level_10_tmp[3:0];
    ac_levels[(1 * 4) +: 4] = ac_level_01_tmp[3:0];
    ac_levels[(2 * 4) +: 4] = ac_level_11_tmp[3:0];

    scaled_level_tmp = ($signed(dc_level) <<< 15) + 64'sd16;
    dequant_dc_tmp = (dc_level == 9'sd0) ? 32'sd0 : (scaled_level_tmp >>> 5);
    scaled_level_tmp = ($signed(ac_level_10_tmp) <<< 15) + 64'sd16;
    dequant_10_tmp = (ac_level_10_tmp == 9'sd0) ? 32'sd0 : (scaled_level_tmp >>> 5);
    scaled_level_tmp = ($signed(ac_level_01_tmp) <<< 15) + 64'sd16;
    dequant_01_tmp = (ac_level_01_tmp == 9'sd0) ? 32'sd0 : (scaled_level_tmp >>> 5);
    scaled_level_tmp = ($signed(ac_level_11_tmp) <<< 15) + 64'sd16;
    dequant_11_tmp = (ac_level_11_tmp == 9'sd0) ? 32'sd0 : (scaled_level_tmp >>> 5);

    for (y_i = 0; y_i < MAX_SIZE; y_i = y_i + 1) begin
      case (y_i)
        0: begin
          basis_y_term_tmp = `FF_VVC_CHROMA_MUL83(dequant_01_tmp);
          basis_xy_term_tmp = `FF_VVC_CHROMA_MUL83(dequant_11_tmp);
        end
        1: begin
          basis_y_term_tmp = `FF_VVC_CHROMA_MUL36(dequant_01_tmp);
          basis_xy_term_tmp = `FF_VVC_CHROMA_MUL36(dequant_11_tmp);
        end
        2: begin
          basis_y_term_tmp = -`FF_VVC_CHROMA_MUL36(dequant_01_tmp);
          basis_xy_term_tmp = -`FF_VVC_CHROMA_MUL36(dequant_11_tmp);
        end
        default: begin
          basis_y_term_tmp = -`FF_VVC_CHROMA_MUL83(dequant_01_tmp);
          basis_xy_term_tmp = -`FF_VVC_CHROMA_MUL83(dequant_11_tmp);
        end
      endcase
      vertical_0_tmp = (`FF_VVC_CHROMA_MUL64(dequant_dc_tmp) + basis_y_term_tmp + 32'sd64) >>> 7;
      vertical_1_tmp =
        (`FF_VVC_CHROMA_MUL64(dequant_10_tmp) + $signed(basis_xy_term_tmp[31:0]) + 32'sd64) >>> 7;

      for (x_i = 0; x_i < MAX_SIZE; x_i = x_i + 1) begin
        if ((y_i == (MAX_SIZE - 1)) || (x_i == (MAX_SIZE - 1))) begin
          case (x_i)
            0: begin
              basis_x_term_tmp = `FF_VVC_CHROMA_MUL83(vertical_1_tmp);
            end
            1: begin
              basis_x_term_tmp = `FF_VVC_CHROMA_MUL36(vertical_1_tmp);
            end
            2: begin
              basis_x_term_tmp = -`FF_VVC_CHROMA_MUL36(vertical_1_tmp);
            end
            default: begin
              basis_x_term_tmp = -`FF_VVC_CHROMA_MUL83(vertical_1_tmp);
            end
          endcase
          recon_sum_tmp = `FF_VVC_CHROMA_MUL64(vertical_0_tmp) + basis_x_term_tmp;
          recon_residual_tmp = (recon_sum_tmp + 64'sd2048) >>> 12;
          idx = (y_i * MAX_SIZE) + x_i;
          predicted_value_tmp = predicted_pack_tmp[idx * 8 +: 8];
          recon_sample_tmp = $signed({24'd0, predicted_value_tmp}) + recon_residual_tmp;
          if (recon_sample_tmp < 32'sd0) begin
            recon_clipped_tmp = 8'd0;
          end else if (recon_sample_tmp > 32'sd255) begin
            recon_clipped_tmp = 8'd255;
          end else begin
            recon_clipped_tmp = recon_sample_tmp[7:0];
          end
          if (y_i == (MAX_SIZE - 1)) begin
            bottom_ref[x_i * 8 +: 8] = recon_clipped_tmp;
          end
          if (x_i == (MAX_SIZE - 1)) begin
            right_ref[y_i * 8 +: 8] = recon_clipped_tmp;
          end
        end
      end
    end
  end
endmodule
