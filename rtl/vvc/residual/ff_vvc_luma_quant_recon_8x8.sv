`timescale 1ns/1ps

`define FF_VVC_LUMA_MUL18(V) (((V) <<< 4) + ((V) <<< 1))
`define FF_VVC_LUMA_MUL36(V) (((V) <<< 5) + ((V) <<< 2))
`define FF_VVC_LUMA_MUL50(V) (((V) <<< 5) + ((V) <<< 4) + ((V) <<< 1))
`define FF_VVC_LUMA_MUL64(V) ((V) <<< 6)
`define FF_VVC_LUMA_MUL75(V) (((V) <<< 6) + ((V) <<< 3) + ((V) <<< 1) + (V))
`define FF_VVC_LUMA_MUL83(V) (((V) <<< 6) + ((V) <<< 4) + ((V) <<< 1) + (V))
`define FF_VVC_LUMA_MUL89(V) (((V) <<< 6) + ((V) <<< 4) + ((V) <<< 3) + (V))

module ff_vvc_luma_quant_recon_8x8 (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic start,
  input  logic [(8 * 64) - 1:0] samples,
  input  logic [3:0] visible_cols,
  input  logic [3:0] visible_rows,
  input  logic [(8 * 8) - 1:0] top_ref,
  input  logic [(8 * 8) - 1:0] left_ref,
  output logic [7:0] abs_level,
  output logic negative,
  output logic [(4 * 15) - 1:0] ac_levels,
  output logic [(8 * 8) - 1:0] bottom_ref,
  output logic [(8 * 8) - 1:0] right_ref,
  output logic done,
  output logic busy
);
  localparam int LUMA_TU_SIZE = 8;
  localparam int LUMA_COEFF_SIZE = 4;
  localparam int LUMA_SAMPLE_COUNT = LUMA_TU_SIZE * LUMA_TU_SIZE;
  localparam int LUMA_COEFF_COUNT = LUMA_COEFF_SIZE * LUMA_COEFF_SIZE;

  localparam logic [2:0] ST_IDLE = 3'd0;
  localparam logic [2:0] ST_SAMPLES = 3'd1;
  localparam logic [2:0] ST_AC = 3'd2;
  localparam logic [2:0] ST_RECON = 3'd3;
  localparam logic [2:0] ST_DONE = 3'd4;

  logic [2:0] state_q;
  logic [5:0] sample_index_q;
  logic [3:0] ac_coeff_q;
  logic [3:0] recon_edge_q;

  logic [7:0] dc_pred_q;
  logic signed [31:0] residual_sum_q;
  logic signed [11:0] cell_sum_q [0:LUMA_COEFF_COUNT - 1];
  logic signed [8:0] coeff_level_q [0:LUMA_COEFF_COUNT - 1];

  logic [1:0] cell_x_w;
  logic [1:0] cell_y_w;
  logic [2:0] cell_lane_x_w [0:3];
  logic [2:0] cell_lane_y_w [0:3];
  logic [5:0] cell_lane_raster_w [0:3];
  logic [7:0] cell_lane_sample_w [0:3];
  logic [7:0] cell_lane_predicted_w [0:3];
  logic signed [31:0] cell_lane_residual_w [0:3];
  logic [31:0] dc_ref_sum_w;
  logic signed [31:0] cell_left_diff_w;
  logic signed [31:0] cell_top_diff_w;
  logic signed [31:0] cell_left_term_w;
  logic signed [31:0] cell_top_term_w;
  logic signed [31:0] cell_pdpc_w;
  logic signed [31:0] residual_sum_next_w;
  logic signed [31:0] cell_sum_next_w;
  logic signed [31:0] residual_avg_w;
  logic signed [31:0] dc_scaled_w;
  logic signed [31:0] dc_level_w;
  logic [31:0] abs_dc_level_w;

  logic [1:0] ac_coeff_x_w;
  logic [1:0] ac_coeff_y_w;
  logic [1:0] ac_sum_cell_x_w;
  logic [1:0] ac_sum_cell_y_w;
  logic ac_basis_x_negative_w;
  logic ac_basis_y_negative_w;
  logic signed [31:0] ac_term_w;
  logic signed [31:0] ac_acc_full_w;
  logic signed [31:0] ac_abs_w;
  logic signed [31:0] ac_rounded_w;
  logic signed [7:0] ac_level_w;

  logic [2:0] recon_x_w;
  logic [2:0] recon_y_w;
  logic [3:0] recon_fast_coeff_index_w;
  logic signed [31:0] recon_fast_coeff_w;
  logic signed [31:0] recon_fast_dequant_w;
  logic signed [31:0] recon_fast_vertical_term_w;
  logic signed [31:0] recon_fast_vertical_acc_w [0:3];
  logic signed [31:0] recon_fast_vertical_value_w [0:3];
  logic signed [31:0] recon_fast_horizontal_term_w;
  logic signed [31:0] recon_fast_horizontal_acc_w;
  logic signed [31:0] recon_residual_w;
  logic signed [31:0] recon_sample_w;
  logic [7:0] recon_predicted_w;
  logic [7:0] recon_clipped_w;

  integer init_i;
  integer ac_sum_i;
  integer cell_lane_i;
  integer recon_fast_x_i;
  integer recon_fast_y_i;

  assign busy = (state_q != ST_IDLE) && (state_q != ST_DONE);
  assign done = (state_q == ST_DONE);

  assign cell_x_w = sample_index_q[1:0];
  assign cell_y_w = sample_index_q[3:2];

  always @* begin
    dc_ref_sum_w = 32'd0;
    for (init_i = 0; init_i < LUMA_TU_SIZE; init_i = init_i + 1) begin
      dc_ref_sum_w =
        dc_ref_sum_w + {24'd0, top_ref[init_i * 8 +: 8]} +
        {24'd0, left_ref[init_i * 8 +: 8]};
    end
  end

  always @* begin
    residual_sum_next_w = residual_sum_q;
    cell_sum_next_w =
      $signed({{20{cell_sum_q[sample_index_q[3:0]][11]}},
               cell_sum_q[sample_index_q[3:0]]});
    cell_left_diff_w = 32'sd0;
    cell_top_diff_w = 32'sd0;
    cell_left_term_w = 32'sd0;
    cell_top_term_w = 32'sd0;
    cell_pdpc_w = 32'sd0;
    for (cell_lane_i = 0; cell_lane_i < 4; cell_lane_i = cell_lane_i + 1) begin
      cell_lane_x_w[cell_lane_i] = {cell_x_w, cell_lane_i[0]};
      cell_lane_y_w[cell_lane_i] = {cell_y_w, cell_lane_i[1]};
      cell_lane_raster_w[cell_lane_i] = {
        cell_lane_y_w[cell_lane_i],
        cell_lane_x_w[cell_lane_i]
      };
      cell_lane_sample_w[cell_lane_i] =
        (({1'b0, cell_lane_x_w[cell_lane_i]} < visible_cols) &&
         ({1'b0, cell_lane_y_w[cell_lane_i]} < visible_rows)) ?
        samples[cell_lane_raster_w[cell_lane_i] * 8 +: 8] :
        8'd0;
      cell_left_diff_w =
        $signed({24'd0, left_ref[cell_lane_y_w[cell_lane_i] * 8 +: 8]}) -
        $signed({24'd0, dc_pred_q});
      cell_top_diff_w =
        $signed({24'd0, top_ref[cell_lane_x_w[cell_lane_i] * 8 +: 8]}) -
        $signed({24'd0, dc_pred_q});
      case (cell_lane_x_w[cell_lane_i])
        3'd0: cell_left_term_w = cell_left_diff_w <<< 5;
        3'd1: cell_left_term_w = cell_left_diff_w <<< 4;
        3'd2: cell_left_term_w = cell_left_diff_w <<< 3;
        3'd3: cell_left_term_w = cell_left_diff_w <<< 2;
        3'd4: cell_left_term_w = cell_left_diff_w <<< 1;
        3'd5: cell_left_term_w = cell_left_diff_w;
        default: cell_left_term_w = 32'sd0;
      endcase
      case (cell_lane_y_w[cell_lane_i])
        3'd0: cell_top_term_w = cell_top_diff_w <<< 5;
        3'd1: cell_top_term_w = cell_top_diff_w <<< 4;
        3'd2: cell_top_term_w = cell_top_diff_w <<< 3;
        3'd3: cell_top_term_w = cell_top_diff_w <<< 2;
        3'd4: cell_top_term_w = cell_top_diff_w <<< 1;
        3'd5: cell_top_term_w = cell_top_diff_w;
        default: cell_top_term_w = 32'sd0;
      endcase
      cell_pdpc_w =
        $signed({24'd0, dc_pred_q}) +
        ((cell_left_term_w + cell_top_term_w + 32'sd32) >>> 6);
      if (cell_pdpc_w < 32'sd0) begin
        cell_lane_predicted_w[cell_lane_i] = 8'd0;
      end else if (cell_pdpc_w > 32'sd255) begin
        cell_lane_predicted_w[cell_lane_i] = 8'd255;
      end else begin
        cell_lane_predicted_w[cell_lane_i] = cell_pdpc_w[7:0];
      end
      cell_lane_residual_w[cell_lane_i] =
        $signed({24'd0, cell_lane_sample_w[cell_lane_i]}) -
        $signed({24'd0, cell_lane_predicted_w[cell_lane_i]});
      residual_sum_next_w =
        residual_sum_next_w + cell_lane_residual_w[cell_lane_i];
      cell_sum_next_w =
        cell_sum_next_w + cell_lane_residual_w[cell_lane_i];
    end
  end

  always @* begin
    if (residual_sum_next_w < 32'sd0) begin
      residual_avg_w = -(((-residual_sum_next_w) + 32'sd32) >>> 6);
    end else begin
      residual_avg_w = (residual_sum_next_w + 32'sd32) >>> 6;
    end
    dc_scaled_w = residual_avg_w * 32'sd5;
    if (dc_scaled_w < 32'sd0) begin
      dc_level_w = -(((-dc_scaled_w) + 32'sd8) >>> 4);
    end else begin
      dc_level_w = (dc_scaled_w + 32'sd8) >>> 4;
    end
    abs_dc_level_w = (dc_level_w < 32'sd0) ? -dc_level_w : dc_level_w;
  end

  assign ac_coeff_x_w = ac_coeff_q[1:0];
  assign ac_coeff_y_w = ac_coeff_q[3:2];

  always @* begin
    ac_acc_full_w = 32'sd0;
    ac_sum_cell_x_w = 2'd0;
    ac_sum_cell_y_w = 2'd0;
    ac_basis_x_negative_w = 1'b0;
    ac_basis_y_negative_w = 1'b0;
    ac_term_w = 32'sd0;
    for (ac_sum_i = 0; ac_sum_i < LUMA_COEFF_COUNT; ac_sum_i = ac_sum_i + 1) begin
      ac_sum_cell_x_w = ac_sum_i[1:0];
      ac_sum_cell_y_w = ac_sum_i[3:2];
      case (ac_coeff_x_w)
        2'd1: ac_basis_x_negative_w = (ac_sum_cell_x_w >= 2);
        2'd2: ac_basis_x_negative_w =
          (ac_sum_cell_x_w == 2'd1) || (ac_sum_cell_x_w == 2'd2);
        2'd3: ac_basis_x_negative_w =
          (ac_sum_cell_x_w == 2'd1) || (ac_sum_cell_x_w == 2'd3);
        default: ac_basis_x_negative_w = 1'b0;
      endcase
      case (ac_coeff_y_w)
        2'd1: ac_basis_y_negative_w = (ac_sum_cell_y_w >= 2);
        2'd2: ac_basis_y_negative_w =
          (ac_sum_cell_y_w == 2'd1) || (ac_sum_cell_y_w == 2'd2);
        2'd3: ac_basis_y_negative_w =
          (ac_sum_cell_y_w == 2'd1) || (ac_sum_cell_y_w == 2'd3);
        default: ac_basis_y_negative_w = 1'b0;
      endcase
      ac_term_w = $signed(cell_sum_q[ac_sum_i]);
      if (ac_basis_x_negative_w ^ ac_basis_y_negative_w) begin
        ac_term_w = -ac_term_w;
      end
      ac_acc_full_w = ac_acc_full_w + ac_term_w;
    end
    ac_abs_w = ac_acc_full_w[31] ? -ac_acc_full_w : ac_acc_full_w;
    ac_rounded_w = (ac_abs_w + 32'sd128) >>> 8;
    if (ac_rounded_w > 32'sd2) begin
      ac_rounded_w = 32'sd2;
    end
    ac_level_w =
      ac_acc_full_w[31] ?
      -$signed({5'd0, ac_rounded_w[2:0]}) :
      $signed({5'd0, ac_rounded_w[2:0]});
  end

  always @* begin
    if (recon_edge_q < 4'd8) begin
      recon_y_w = 3'd7;
      recon_x_w = recon_edge_q[2:0];
    end else begin
      recon_y_w = recon_edge_q[2:0] - 3'd0;
      recon_x_w = 3'd7;
    end
    if (recon_edge_q < 4'd8) begin
      recon_predicted_w = bottom_ref[recon_x_w * 8 +: 8];
    end else begin
      recon_predicted_w = right_ref[recon_y_w * 8 +: 8];
    end

    recon_fast_horizontal_acc_w = 32'sd0;
    for (recon_fast_x_i = 0; recon_fast_x_i < 4; recon_fast_x_i = recon_fast_x_i + 1) begin
      recon_fast_vertical_acc_w[recon_fast_x_i] = 32'sd0;
      recon_fast_vertical_value_w[recon_fast_x_i] = 32'sd0;
      for (recon_fast_y_i = 0; recon_fast_y_i < 4; recon_fast_y_i = recon_fast_y_i + 1) begin
        recon_fast_coeff_index_w = {recon_fast_y_i[1:0], recon_fast_x_i[1:0]};
        recon_fast_coeff_w =
          $signed({{23{coeff_level_q[recon_fast_coeff_index_w][8]}},
                   coeff_level_q[recon_fast_coeff_index_w]});
        recon_fast_dequant_w =
          (recon_fast_coeff_w <<< 8) +
          (recon_fast_coeff_w <<< 7) +
          (recon_fast_coeff_w <<< 4) +
          (recon_fast_coeff_w <<< 3);
        recon_fast_vertical_term_w = 32'sd0;
        case (recon_fast_y_i[1:0])
          2'd0: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL64(recon_fast_dequant_w);
          2'd1: begin
            case (recon_y_w)
              3'd0: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL89(recon_fast_dequant_w);
              3'd1: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL75(recon_fast_dequant_w);
              3'd2: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL50(recon_fast_dequant_w);
              3'd3: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL18(recon_fast_dequant_w);
              3'd4: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL18(recon_fast_dequant_w);
              3'd5: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL50(recon_fast_dequant_w);
              3'd6: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL75(recon_fast_dequant_w);
              default: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL89(recon_fast_dequant_w);
            endcase
          end
          2'd2: begin
            case (recon_y_w)
              3'd0: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL83(recon_fast_dequant_w);
              3'd1: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL36(recon_fast_dequant_w);
              3'd2: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL36(recon_fast_dequant_w);
              3'd3: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL83(recon_fast_dequant_w);
              3'd4: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL83(recon_fast_dequant_w);
              3'd5: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL36(recon_fast_dequant_w);
              3'd6: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL36(recon_fast_dequant_w);
              default: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL83(recon_fast_dequant_w);
            endcase
          end
          default: begin
            case (recon_y_w)
              3'd0: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL75(recon_fast_dequant_w);
              3'd1: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL18(recon_fast_dequant_w);
              3'd2: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL89(recon_fast_dequant_w);
              3'd3: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL50(recon_fast_dequant_w);
              3'd4: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL50(recon_fast_dequant_w);
              3'd5: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL89(recon_fast_dequant_w);
              3'd6: recon_fast_vertical_term_w = `FF_VVC_LUMA_MUL18(recon_fast_dequant_w);
              default: recon_fast_vertical_term_w = -`FF_VVC_LUMA_MUL75(recon_fast_dequant_w);
            endcase
          end
        endcase
        recon_fast_vertical_acc_w[recon_fast_x_i] =
          recon_fast_vertical_acc_w[recon_fast_x_i] + recon_fast_vertical_term_w;
      end
      recon_fast_vertical_value_w[recon_fast_x_i] =
        (recon_fast_vertical_acc_w[recon_fast_x_i] + 32'sd64) >>> 7;
      recon_fast_horizontal_term_w = 32'sd0;
      case (recon_fast_x_i[1:0])
        2'd0: recon_fast_horizontal_term_w =
          `FF_VVC_LUMA_MUL64(recon_fast_vertical_value_w[recon_fast_x_i]);
        2'd1: begin
          case (recon_x_w)
            3'd0: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL89(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd1: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL75(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd2: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL50(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd3: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL18(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd4: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL18(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd5: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL50(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd6: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL75(recon_fast_vertical_value_w[recon_fast_x_i]);
            default: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL89(recon_fast_vertical_value_w[recon_fast_x_i]);
          endcase
        end
        2'd2: begin
          case (recon_x_w)
            3'd0: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL83(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd1: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL36(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd2: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL36(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd3: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL83(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd4: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL83(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd5: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL36(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd6: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL36(recon_fast_vertical_value_w[recon_fast_x_i]);
            default: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL83(recon_fast_vertical_value_w[recon_fast_x_i]);
          endcase
        end
        default: begin
          case (recon_x_w)
            3'd0: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL75(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd1: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL18(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd2: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL89(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd3: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL50(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd4: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL50(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd5: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL89(recon_fast_vertical_value_w[recon_fast_x_i]);
            3'd6: recon_fast_horizontal_term_w =
              `FF_VVC_LUMA_MUL18(recon_fast_vertical_value_w[recon_fast_x_i]);
            default: recon_fast_horizontal_term_w =
              -`FF_VVC_LUMA_MUL75(recon_fast_vertical_value_w[recon_fast_x_i]);
          endcase
        end
      endcase
      recon_fast_horizontal_acc_w =
        recon_fast_horizontal_acc_w + recon_fast_horizontal_term_w;
    end
    recon_residual_w = (recon_fast_horizontal_acc_w + 32'sd2048) >>> 12;
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
      sample_index_q <= 6'd0;
      ac_coeff_q <= 4'd1;
      recon_edge_q <= 4'd0;
      dc_pred_q <= 8'd128;
      residual_sum_q <= 32'sd0;
      abs_level <= 8'd0;
      negative <= 1'b0;
      ac_levels <= '0;
      bottom_ref <= '0;
      right_ref <= '0;
      for (init_i = 0; init_i < LUMA_COEFF_COUNT; init_i = init_i + 1) begin
        cell_sum_q[init_i] <= 12'sd0;
        coeff_level_q[init_i] <= 9'sd0;
      end
    end else if (clear) begin
      state_q <= ST_IDLE;
      sample_index_q <= 6'd0;
      ac_coeff_q <= 4'd1;
      recon_edge_q <= 4'd0;
      dc_pred_q <= 8'd128;
      residual_sum_q <= 32'sd0;
      abs_level <= 8'd0;
      negative <= 1'b0;
      ac_levels <= '0;
      bottom_ref <= '0;
      right_ref <= '0;
      for (init_i = 0; init_i < LUMA_COEFF_COUNT; init_i = init_i + 1) begin
        cell_sum_q[init_i] <= 12'sd0;
        coeff_level_q[init_i] <= 9'sd0;
      end
    end else begin
      case (state_q)
        ST_IDLE: begin
          if (start) begin
            state_q <= ST_SAMPLES;
            sample_index_q <= 6'd0;
            ac_coeff_q <= 4'd1;
            recon_edge_q <= 4'd0;
            dc_pred_q <= (dc_ref_sum_w + 32'd8) >> 4;
            residual_sum_q <= 32'sd0;
            abs_level <= 8'd0;
            negative <= 1'b0;
            ac_levels <= '0;
            bottom_ref <= '0;
            right_ref <= '0;
            for (init_i = 0; init_i < LUMA_COEFF_COUNT; init_i = init_i + 1) begin
              cell_sum_q[init_i] <= 12'sd0;
              coeff_level_q[init_i] <= 9'sd0;
            end
          end
        end

        ST_SAMPLES: begin
          residual_sum_q <= residual_sum_next_w;
          cell_sum_q[sample_index_q[3:0]] <= cell_sum_next_w[11:0];
          for (cell_lane_i = 0; cell_lane_i < 4; cell_lane_i = cell_lane_i + 1) begin
            if (cell_lane_y_w[cell_lane_i] == 3'd7) begin
              bottom_ref[cell_lane_x_w[cell_lane_i] * 8 +: 8] <=
                cell_lane_predicted_w[cell_lane_i];
            end
            if (cell_lane_x_w[cell_lane_i] == 3'd7) begin
              right_ref[cell_lane_y_w[cell_lane_i] * 8 +: 8] <=
                cell_lane_predicted_w[cell_lane_i];
            end
          end
          if (sample_index_q == 6'd15) begin
            coeff_level_q[0] <= dc_level_w[8:0];
            abs_level <= (abs_dc_level_w > 32'd255) ? 8'hff : abs_dc_level_w[7:0];
            negative <= (abs_dc_level_w != 32'd0) && (dc_level_w < 32'sd0);
            state_q <= ST_AC;
            ac_coeff_q <= 4'd1;
          end else begin
            sample_index_q <= sample_index_q + 6'd1;
          end
        end

        ST_AC: begin
          coeff_level_q[ac_coeff_q] <= {ac_level_w[7], ac_level_w};
          ac_levels[((15 - ac_coeff_q) * 4) +: 4] <= ac_level_w[3:0];
          if (ac_coeff_q == 4'd15) begin
            state_q <= ST_RECON;
            recon_edge_q <= 4'd0;
          end else begin
            ac_coeff_q <= ac_coeff_q + 4'd1;
          end
        end

        ST_RECON: begin
          if (recon_edge_q < 4'd8) begin
            bottom_ref[recon_x_w * 8 +: 8] <= recon_clipped_w;
            if (recon_x_w == 3'd7) begin
              right_ref[3'd7 * 8 +: 8] <= recon_clipped_w;
            end
          end else begin
            right_ref[recon_y_w * 8 +: 8] <= recon_clipped_w;
          end
          if (recon_edge_q == 4'd14) begin
            state_q <= ST_DONE;
          end else begin
            recon_edge_q <= recon_edge_q + 4'd1;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule

`undef FF_VVC_LUMA_MUL18
`undef FF_VVC_LUMA_MUL36
`undef FF_VVC_LUMA_MUL50
`undef FF_VVC_LUMA_MUL64
`undef FF_VVC_LUMA_MUL75
`undef FF_VVC_LUMA_MUL83
`undef FF_VVC_LUMA_MUL89
