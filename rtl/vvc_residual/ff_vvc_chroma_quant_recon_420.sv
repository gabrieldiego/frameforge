`timescale 1ns/1ps

`define FF_VVC_CHROMA_MUL36(V) (((V) <<< 5) + ((V) <<< 2))
`define FF_VVC_CHROMA_MUL64(V) ((V) <<< 6)
`define FF_VVC_CHROMA_MUL83(V) (((V) <<< 6) + ((V) <<< 4) + ((V) <<< 1) + (V))

module ff_vvc_chroma_quant_recon_420 (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic start,
  input  logic [(8 * 4 * 4) - 1:0] samples,
  input  logic [(8 * 4) - 1:0] top_ref,
  input  logic [(8 * 4) - 1:0] left_ref,
  output logic signed [8:0] dc_level,
  output logic [(4 * 3) - 1:0] ac_levels,
  output logic [(8 * 4) - 1:0] bottom_ref,
  output logic [(8 * 4) - 1:0] right_ref,
  output logic done,
  output logic busy
);
  localparam int CHROMA_TU_SIZE = 4;
  localparam int CHROMA_SAMPLE_COUNT = CHROMA_TU_SIZE * CHROMA_TU_SIZE;

  localparam logic [2:0] ST_IDLE = 3'd0;
  localparam logic [2:0] ST_LOAD = 3'd1;
  localparam logic [2:0] ST_SAMPLES = 3'd2;
  localparam logic [2:0] ST_QUANT = 3'd3;
  localparam logic [2:0] ST_RECON_VERTICAL = 3'd4;
  localparam logic [2:0] ST_RECON_SAMPLE = 3'd5;
  localparam logic [2:0] ST_DONE = 3'd6;

  logic [2:0] state_q;
  logic [3:0] sample_index_q;
  logic [2:0] recon_edge_q;

  logic [(8 * CHROMA_SAMPLE_COUNT) - 1:0] samples_q;
  logic [(8 * CHROMA_TU_SIZE) - 1:0] top_ref_q;
  logic [(8 * CHROMA_TU_SIZE) - 1:0] left_ref_q;
  logic [7:0] dc_pred_q;
  logic signed [12:0] residual_sum_q;
  logic signed [31:0] ac_acc_10_q;
  logic signed [31:0] ac_acc_01_q;
  logic signed [31:0] ac_acc_11_q;
  logic signed [17:0] dequant_dc_q;
  logic signed [17:0] dequant_10_q;
  logic signed [17:0] dequant_01_q;
  logic signed [17:0] dequant_11_q;
  logic signed [17:0] vertical_0_q;
  logic signed [17:0] vertical_1_q;

  logic [31:0] dc_ref_sum_w;
  logic [1:0] sample_x_w;
  logic [1:0] sample_y_w;
  logic [7:0] sample_w;
  logic signed [31:0] left_diff_w;
  logic signed [31:0] top_diff_w;
  logic signed [31:0] left_term_w;
  logic signed [31:0] top_term_w;
  logic signed [31:0] pdpc_w;
  logic [7:0] predicted_w;
  logic signed [31:0] residual_w;
  logic signed [31:0] residual_sum_next_w;
  logic signed [31:0] residual_wide_w;
  logic signed [31:0] sample_basis_x_w;
  logic signed [31:0] sample_basis_y_w;
  logic signed [31:0] sample_basis_xy_w;
  logic signed [31:0] ac_acc_10_next_w;
  logic signed [31:0] ac_acc_01_next_w;
  logic signed [31:0] ac_acc_11_next_w;

  logic signed [31:0] dc_level_abs_wide_w;
  logic signed [8:0] dc_level_abs_w;
  logic signed [8:0] dc_level_w;
  logic signed [31:0] ac_abs_10_w;
  logic signed [31:0] ac_abs_01_w;
  logic signed [31:0] ac_abs_11_w;
  logic signed [31:0] ac_rounded_10_w;
  logic signed [31:0] ac_rounded_01_w;
  logic signed [31:0] ac_rounded_11_w;
  logic signed [8:0] quant_level_10_w;
  logic signed [8:0] quant_level_01_w;
  logic signed [8:0] quant_level_11_w;
  logic signed [8:0] ac_level_10_w;
  logic signed [8:0] ac_level_01_w;
  logic signed [8:0] ac_level_11_w;
  logic signed [31:0] scaled_level_w;
  logic signed [31:0] dequant_dc_w;
  logic signed [31:0] dequant_10_w;
  logic signed [31:0] dequant_01_w;
  logic signed [31:0] dequant_11_w;
  logic [(4 * 3) - 1:0] ac_levels_w;

  logic recon_bottom_edge_w;
  logic [1:0] recon_x_w;
  logic [1:0] recon_y_w;
  logic [7:0] recon_predicted_w;
  logic signed [31:0] dequant_dc_q_wide;
  logic signed [31:0] dequant_10_q_wide;
  logic signed [31:0] dequant_01_q_wide;
  logic signed [31:0] dequant_11_q_wide;
  logic signed [31:0] vertical_0_q_wide;
  logic signed [31:0] vertical_1_q_wide;
  logic signed [31:0] recon_basis_y_w;
  logic signed [31:0] recon_basis_xy_w;
  logic signed [31:0] vertical_0_w;
  logic signed [31:0] vertical_1_w;
  logic signed [31:0] recon_basis_x_w;
  logic signed [31:0] recon_sum_w;
  logic signed [31:0] recon_residual_w;
  logic signed [31:0] recon_sample_w;
  logic [7:0] recon_clipped_w;

  integer ref_i;

  assign busy = (state_q != ST_IDLE) && (state_q != ST_DONE);
  assign done = (state_q == ST_DONE);

  assign sample_x_w = sample_index_q[1:0];
  assign sample_y_w = sample_index_q[3:2];
  assign sample_w = samples_q[sample_index_q * 8 +: 8];

  always @* begin
    dc_ref_sum_w = 32'd0;
    for (ref_i = 0; ref_i < CHROMA_TU_SIZE; ref_i = ref_i + 1) begin
      dc_ref_sum_w =
        dc_ref_sum_w + {24'd0, top_ref_q[ref_i * 8 +: 8]} +
        {24'd0, left_ref_q[ref_i * 8 +: 8]};
    end
  end

  always @* begin
    left_diff_w = $signed({24'd0, left_ref_q[sample_y_w * 8 +: 8]}) -
                  $signed({24'd0, dc_pred_q});
    top_diff_w = $signed({24'd0, top_ref_q[sample_x_w * 8 +: 8]}) -
                 $signed({24'd0, dc_pred_q});
    case (sample_x_w)
      2'd0: left_term_w = left_diff_w <<< 5;
      2'd1: left_term_w = left_diff_w <<< 3;
      2'd2: left_term_w = left_diff_w <<< 1;
      default: left_term_w = 32'sd0;
    endcase
    case (sample_y_w)
      2'd0: top_term_w = top_diff_w <<< 5;
      2'd1: top_term_w = top_diff_w <<< 3;
      2'd2: top_term_w = top_diff_w <<< 1;
      default: top_term_w = 32'sd0;
    endcase
    pdpc_w = $signed({24'd0, dc_pred_q}) + ((left_term_w + top_term_w + 32'sd32) >>> 6);
    if (pdpc_w < 32'sd0) begin
      predicted_w = 8'd0;
    end else if (pdpc_w > 32'sd255) begin
      predicted_w = 8'd255;
    end else begin
      predicted_w = pdpc_w[7:0];
    end

    residual_w = $signed({24'd0, sample_w}) - $signed({24'd0, predicted_w});
    residual_sum_next_w = residual_sum_q + residual_w;
    residual_wide_w = residual_w;

    case (sample_x_w)
      2'd0: sample_basis_x_w = `FF_VVC_CHROMA_MUL83(residual_wide_w);
      2'd1: sample_basis_x_w = `FF_VVC_CHROMA_MUL36(residual_wide_w);
      2'd2: sample_basis_x_w = -`FF_VVC_CHROMA_MUL36(residual_wide_w);
      default: sample_basis_x_w = -`FF_VVC_CHROMA_MUL83(residual_wide_w);
    endcase
    case (sample_y_w)
      2'd0: begin
        sample_basis_y_w = `FF_VVC_CHROMA_MUL83(residual_wide_w);
        sample_basis_xy_w = `FF_VVC_CHROMA_MUL83(sample_basis_x_w);
      end
      2'd1: begin
        sample_basis_y_w = `FF_VVC_CHROMA_MUL36(residual_wide_w);
        sample_basis_xy_w = `FF_VVC_CHROMA_MUL36(sample_basis_x_w);
      end
      2'd2: begin
        sample_basis_y_w = -`FF_VVC_CHROMA_MUL36(residual_wide_w);
        sample_basis_xy_w = -`FF_VVC_CHROMA_MUL36(sample_basis_x_w);
      end
      default: begin
        sample_basis_y_w = -`FF_VVC_CHROMA_MUL83(residual_wide_w);
        sample_basis_xy_w = -`FF_VVC_CHROMA_MUL83(sample_basis_x_w);
      end
    endcase
    ac_acc_10_next_w = ac_acc_10_q + $signed(`FF_VVC_CHROMA_MUL64(sample_basis_x_w));
    ac_acc_01_next_w = ac_acc_01_q + $signed(`FF_VVC_CHROMA_MUL64(sample_basis_y_w));
    ac_acc_11_next_w = ac_acc_11_q + sample_basis_xy_w;
  end

  always @* begin
    dc_level_abs_wide_w = 32'sd0;
    dc_level_abs_w = 9'sd0;
    if ((residual_sum_q >= -32'sd64) && (residual_sum_q <= 32'sd64)) begin
      dc_level_w = 9'sd0;
    end else if (residual_sum_q > 32'sd64) begin
      dc_level_abs_wide_w = (residual_sum_q + 32'sd63) >>> 7;
      dc_level_abs_w = $signed(dc_level_abs_wide_w[8:0]);
      dc_level_w = dc_level_abs_w;
    end else begin
      dc_level_abs_wide_w = ((-residual_sum_q) + 32'sd64) >>> 7;
      dc_level_abs_w = $signed(dc_level_abs_wide_w[8:0]);
      dc_level_w = -dc_level_abs_w;
    end

    ac_abs_10_w = ac_acc_10_q[31] ? -ac_acc_10_q : ac_acc_10_q;
    ac_abs_01_w = ac_acc_01_q[31] ? -ac_acc_01_q : ac_acc_01_q;
    ac_abs_11_w = ac_acc_11_q[31] ? -ac_acc_11_q : ac_acc_11_q;
    ac_rounded_10_w = (ac_abs_10_w + 32'sd65536) >>> 17;
    ac_rounded_01_w = (ac_abs_01_w + 32'sd65536) >>> 17;
    ac_rounded_11_w = (ac_abs_11_w + 32'sd65536) >>> 17;
    quant_level_10_w = (ac_rounded_10_w > 32'sd2) ? 9'sd2 : $signed(ac_rounded_10_w[8:0]);
    quant_level_01_w = (ac_rounded_01_w > 32'sd2) ? 9'sd2 : $signed(ac_rounded_01_w[8:0]);
    quant_level_11_w = (ac_rounded_11_w > 32'sd2) ? 9'sd2 : $signed(ac_rounded_11_w[8:0]);
    ac_level_10_w = ac_acc_10_q[31] ? -quant_level_10_w : quant_level_10_w;
    ac_level_01_w = ac_acc_01_q[31] ? -quant_level_01_w : quant_level_01_w;
    ac_level_11_w = ac_acc_11_q[31] ? -quant_level_11_w : quant_level_11_w;

    ac_levels_w = '0;
    ac_levels_w[(0 * 4) +: 4] = ac_level_10_w[3:0];
    ac_levels_w[(1 * 4) +: 4] = ac_level_01_w[3:0];
    ac_levels_w[(2 * 4) +: 4] = ac_level_11_w[3:0];

    scaled_level_w = ($signed(dc_level_w) <<< 15) + 32'sd16;
    dequant_dc_w = (dc_level_w == 9'sd0) ? 32'sd0 : (scaled_level_w >>> 5);
    scaled_level_w = ($signed(ac_level_10_w) <<< 15) + 32'sd16;
    dequant_10_w = (ac_level_10_w == 9'sd0) ? 32'sd0 : (scaled_level_w >>> 5);
    scaled_level_w = ($signed(ac_level_01_w) <<< 15) + 32'sd16;
    dequant_01_w = (ac_level_01_w == 9'sd0) ? 32'sd0 : (scaled_level_w >>> 5);
    scaled_level_w = ($signed(ac_level_11_w) <<< 15) + 32'sd16;
    dequant_11_w = (ac_level_11_w == 9'sd0) ? 32'sd0 : (scaled_level_w >>> 5);
  end

  assign recon_bottom_edge_w = (recon_edge_q < 3'd4);
  assign dequant_dc_q_wide = dequant_dc_q;
  assign dequant_10_q_wide = dequant_10_q;
  assign dequant_01_q_wide = dequant_01_q;
  assign dequant_11_q_wide = dequant_11_q;
  assign vertical_0_q_wide = vertical_0_q;
  assign vertical_1_q_wide = vertical_1_q;

  always @* begin
    if (recon_bottom_edge_w) begin
      recon_y_w = 2'd3;
      recon_x_w = recon_edge_q[1:0];
      recon_predicted_w = bottom_ref[recon_edge_q[1:0] * 8 +: 8];
    end else begin
      recon_y_w = recon_edge_q[1:0];
      recon_x_w = 2'd3;
      recon_predicted_w = right_ref[recon_edge_q[1:0] * 8 +: 8];
    end

    case (recon_y_w)
      2'd0: begin
        recon_basis_y_w = `FF_VVC_CHROMA_MUL83(dequant_01_q_wide);
        recon_basis_xy_w = `FF_VVC_CHROMA_MUL83(dequant_11_q_wide);
      end
      2'd1: begin
        recon_basis_y_w = `FF_VVC_CHROMA_MUL36(dequant_01_q_wide);
        recon_basis_xy_w = `FF_VVC_CHROMA_MUL36(dequant_11_q_wide);
      end
      2'd2: begin
        recon_basis_y_w = -`FF_VVC_CHROMA_MUL36(dequant_01_q_wide);
        recon_basis_xy_w = -`FF_VVC_CHROMA_MUL36(dequant_11_q_wide);
      end
      default: begin
        recon_basis_y_w = -`FF_VVC_CHROMA_MUL83(dequant_01_q_wide);
        recon_basis_xy_w = -`FF_VVC_CHROMA_MUL83(dequant_11_q_wide);
      end
    endcase
    vertical_0_w = (`FF_VVC_CHROMA_MUL64(dequant_dc_q_wide) + recon_basis_y_w + 32'sd64) >>> 7;
    vertical_1_w =
      (`FF_VVC_CHROMA_MUL64(dequant_10_q_wide) + $signed(recon_basis_xy_w[31:0]) + 32'sd64) >>> 7;

    case (recon_x_w)
      2'd0: recon_basis_x_w = `FF_VVC_CHROMA_MUL83(vertical_1_q_wide);
      2'd1: recon_basis_x_w = `FF_VVC_CHROMA_MUL36(vertical_1_q_wide);
      2'd2: recon_basis_x_w = -`FF_VVC_CHROMA_MUL36(vertical_1_q_wide);
      default: recon_basis_x_w = -`FF_VVC_CHROMA_MUL83(vertical_1_q_wide);
    endcase
    recon_sum_w = $signed(`FF_VVC_CHROMA_MUL64(vertical_0_q_wide)) + $signed(recon_basis_x_w);
    recon_residual_w = (recon_sum_w + 32'sd2048) >>> 12;
    recon_sample_w = $signed({24'd0, recon_predicted_w}) + recon_residual_w;
    if (recon_sample_w < 32'sd0) begin
      recon_clipped_w = 8'd0;
    end else if (recon_sample_w > 32'sd255) begin
      recon_clipped_w = 8'd255;
    end else begin
      recon_clipped_w = recon_sample_w[7:0];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      sample_index_q <= 4'd0;
      recon_edge_q <= 3'd0;
      samples_q <= '0;
      top_ref_q <= '0;
      left_ref_q <= '0;
      dc_pred_q <= 8'd128;
      residual_sum_q <= 13'sd0;
      ac_acc_10_q <= 32'sd0;
      ac_acc_01_q <= 32'sd0;
      ac_acc_11_q <= 32'sd0;
      dequant_dc_q <= 18'sd0;
      dequant_10_q <= 18'sd0;
      dequant_01_q <= 18'sd0;
      dequant_11_q <= 18'sd0;
      vertical_0_q <= 18'sd0;
      vertical_1_q <= 18'sd0;
      dc_level <= 9'sd0;
      ac_levels <= '0;
      bottom_ref <= '0;
      right_ref <= '0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      sample_index_q <= 4'd0;
      recon_edge_q <= 3'd0;
      samples_q <= '0;
      top_ref_q <= '0;
      left_ref_q <= '0;
      dc_pred_q <= 8'd128;
      residual_sum_q <= 13'sd0;
      ac_acc_10_q <= 32'sd0;
      ac_acc_01_q <= 32'sd0;
      ac_acc_11_q <= 32'sd0;
      dequant_dc_q <= 18'sd0;
      dequant_10_q <= 18'sd0;
      dequant_01_q <= 18'sd0;
      dequant_11_q <= 18'sd0;
      vertical_0_q <= 18'sd0;
      vertical_1_q <= 18'sd0;
      dc_level <= 9'sd0;
      ac_levels <= '0;
      bottom_ref <= '0;
      right_ref <= '0;
    end else begin
      case (state_q)
        ST_IDLE: begin
          if (start) begin
            state_q <= ST_LOAD;
            sample_index_q <= 4'd0;
            recon_edge_q <= 3'd0;
            samples_q <= samples;
            top_ref_q <= top_ref;
            left_ref_q <= left_ref;
            dc_pred_q <= 8'd128;
            residual_sum_q <= 13'sd0;
            ac_acc_10_q <= 32'sd0;
            ac_acc_01_q <= 32'sd0;
            ac_acc_11_q <= 32'sd0;
            dequant_dc_q <= 18'sd0;
            dequant_10_q <= 18'sd0;
            dequant_01_q <= 18'sd0;
            dequant_11_q <= 18'sd0;
            vertical_0_q <= 18'sd0;
            vertical_1_q <= 18'sd0;
            dc_level <= 9'sd0;
            ac_levels <= '0;
            bottom_ref <= '0;
            right_ref <= '0;
          end
        end

        ST_LOAD: begin
          dc_pred_q <= (dc_ref_sum_w + 32'd4) >> 3;
          sample_index_q <= 4'd0;
          residual_sum_q <= 13'sd0;
          ac_acc_10_q <= 32'sd0;
          ac_acc_01_q <= 32'sd0;
          ac_acc_11_q <= 32'sd0;
          state_q <= ST_SAMPLES;
        end

        ST_SAMPLES: begin
          residual_sum_q <= residual_sum_next_w;
          ac_acc_10_q <= ac_acc_10_next_w;
          ac_acc_01_q <= ac_acc_01_next_w;
          ac_acc_11_q <= ac_acc_11_next_w;
          if (sample_y_w == 2'd3) begin
            bottom_ref[sample_x_w * 8 +: 8] <= predicted_w;
          end
          if (sample_x_w == 2'd3) begin
            right_ref[sample_y_w * 8 +: 8] <= predicted_w;
          end
          if (sample_index_q == (CHROMA_SAMPLE_COUNT - 1)) begin
            state_q <= ST_QUANT;
          end else begin
            sample_index_q <= sample_index_q + 4'd1;
          end
        end

        ST_QUANT: begin
          dc_level <= dc_level_w;
          ac_levels <= ac_levels_w;
          dequant_dc_q <= dequant_dc_w;
          dequant_10_q <= dequant_10_w;
          dequant_01_q <= dequant_01_w;
          dequant_11_q <= dequant_11_w;
          recon_edge_q <= 3'd0;
          state_q <= ST_RECON_VERTICAL;
        end

        ST_RECON_VERTICAL: begin
          vertical_0_q <= vertical_0_w;
          vertical_1_q <= vertical_1_w;
          state_q <= ST_RECON_SAMPLE;
        end

        ST_RECON_SAMPLE: begin
          if (recon_bottom_edge_w) begin
            bottom_ref[recon_x_w * 8 +: 8] <= recon_clipped_w;
          end else begin
            right_ref[recon_y_w * 8 +: 8] <= recon_clipped_w;
          end
          if (recon_edge_q == 3'd7) begin
            state_q <= ST_DONE;
          end else begin
            recon_edge_q <= recon_edge_q + 3'd1;
            state_q <= ST_RECON_VERTICAL;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule

`undef FF_VVC_CHROMA_MUL36
`undef FF_VVC_CHROMA_MUL64
`undef FF_VVC_CHROMA_MUL83
