`timescale 1ns/1ps

module ff_av2_entropy_op_mux (
  input  logic        partition_active,
  input  logic        leaf_active,
  input  logic [2:0]  phase,
  input  logic [6:0]  step,
  input  logic [1:0]  partition,
  input  logic        partition_emit_do_split,
  input  logic        partition_emit_rect,
  input  logic [31:0] partition_do_cdf0,
  input  logic [31:0] partition_rect_cdf0,
  input  logic        ibc_use_copy,
  input  logic [1:0]  ibc_drl_idx,
  input  logic [1:0]  intrabc_ctx,
  input  logic [1:0]  intrabc_skip_ctx,
  input  logic [1:0]  leaf_luma_mode,
  input  logic        leaf_fsc_symbol,
  input  logic [31:0] leaf_fsc_fh,
  input  logic        palette_mode,
  input  logic        residual_mode,
  input  logic        leaf_luma_palette,
  input  logic        palette_op_valid,
  input  logic        palette_op_literal,
  input  logic [31:0] palette_op_literal_value,
  input  logic [4:0]  palette_op_literal_bits,
  input  logic [31:0] palette_op_fl,
  input  logic [31:0] palette_op_fh,
  input  logic [4:0]  palette_op_fl_inc,
  input  logic [4:0]  palette_op_fh_inc,
  input  logic        luma_residual_op_valid,
  input  logic        luma_residual_op_literal,
  input  logic [31:0] luma_residual_op_literal_value,
  input  logic [4:0]  luma_residual_op_literal_bits,
  input  logic [31:0] luma_residual_op_fl,
  input  logic [31:0] luma_residual_op_fh,
  input  logic [4:0]  luma_residual_op_fl_inc,
  input  logic [4:0]  luma_residual_op_fh_inc,
  input  logic        chroma_bdpcm_op_valid,
  input  logic        chroma_bdpcm_op_literal,
  input  logic [31:0] chroma_bdpcm_op_literal_value,
  input  logic [4:0]  chroma_bdpcm_op_literal_bits,
  input  logic [31:0] chroma_bdpcm_op_fl,
  input  logic [31:0] chroma_bdpcm_op_fh,
  input  logic [4:0]  chroma_bdpcm_op_fl_inc,
  input  logic [4:0]  chroma_bdpcm_op_fh_inc,
  input  logic [31:0] y_txb_nonzero_fh,
  input  logic [31:0] u_txb_nonzero_fh,
  input  logic [31:0] v_txb_nonzero_fh,
  input  logic [31:0] y_dc_sign_fl,
  input  logic [15:0] txb_index,
  input  logic [15:0] txb_count,
  input  logic        chroma_bdpcm_txb_done,
  input  logic        stack_empty,
  output logic        op_valid,
  output logic        op_literal,
  output logic [31:0] op_literal_value,
  output logic [4:0]  op_literal_bits,
  output logic [31:0] op_fl,
  output logic [31:0] op_fh,
  output logic [4:0]  op_fl_inc,
  output logic [4:0]  op_fh_inc,
  output logic        op_last
);

  localparam logic [1:0] PARTITION_NONE = 2'd0;
  localparam logic [1:0] PARTITION_VERT = 2'd2;
  localparam logic [2:0] PHASE_INTRA = 3'd0;
  localparam logic [2:0] PHASE_PALETTE_HEADER = 3'd1;
  localparam logic [2:0] PHASE_PALETTE_MAP = 3'd2;
  localparam logic [2:0] PHASE_Y_COEFF = 3'd3;
  localparam logic [2:0] PHASE_U_COEFF = 3'd4;
  localparam logic [2:0] PHASE_V_COEFF = 3'd5;
  localparam logic [2:0] PHASE_INTRABC = 3'd6;
  localparam logic [1:0] LUMA_MODE_V = 2'd1;
  localparam logic [1:0] LUMA_MODE_H = 2'd2;

  always @* begin
    op_valid = 1'b0;
    op_literal = 1'b0;
    op_literal_value = 32'd0;
    op_literal_bits = 5'd0;
    op_fl = 32'd32768;
    op_fh = 32'd0;
    op_fl_inc = 0;
    op_fh_inc = 0;
    op_last = 1'b0;

    if (partition_active) begin
      if (partition_emit_do_split) begin
        // AV2 v1.0.0 Section 5.20.3.2 partition(): do_split is present only
        // when PARTITION_NONE is allowed at the current block.
        op_valid = 1'b1;
        if (partition == PARTITION_NONE) begin
          op_fh = partition_do_cdf0;
          op_fh_inc = 8;
        end else begin
          op_fl = partition_do_cdf0;
          op_fh = 32'd0;
          op_fl_inc = 8;
          op_fh_inc = 0;
        end
      end else if (partition_emit_rect) begin
        // AV2 v1.0.0 Section 5.20.3.2 partition(): rect_type selects
        // vertical when coded as symbol 1; symbol 0 selects horizontal.
        op_valid = 1'b1;
        if (partition == PARTITION_VERT) begin
          op_fl = partition_rect_cdf0;
          op_fh = 32'd0;
          op_fl_inc = 8;
          op_fh_inc = 0;
        end else begin
          op_fh = partition_rect_cdf0;
          op_fh_inc = 8;
        end
      end
    end else if (leaf_active) begin
      op_valid = 1'b1;
      if (phase == PHASE_INTRABC) begin
        case (step)
          7'd0: begin
            // AV2 v1.0.0 read_intra_frame_mode_info(): use_intrabc is
            // signaled before normal intra mode syntax when allow_intrabc=1.
            if (ibc_use_copy) begin
              case (intrabc_ctx)
                2'd0: op_fl = 32'd683;
                2'd1: op_fl = 32'd17596;
                default: op_fl = 32'd28265;
              endcase
              op_fh = 32'd0;
              op_fl_inc = 8;
              op_fh_inc = 0;
            end else begin
              case (intrabc_ctx)
                2'd0: op_fh = 32'd683;
                2'd1: op_fh = 32'd17596;
                default: op_fh = 32'd28265;
              endcase
              op_fh_inc = 8;
            end
          end
          7'd1: begin
            case (intrabc_skip_ctx)
              2'd0: op_fl = 32'd6903;
              2'd1: op_fl = 32'd18452;
              default: op_fl = 32'd28170;
            endcase
            op_fh = 32'd0;
            op_fl_inc = 8;
            op_fh_inc = 0;
          end
          7'd2: begin
            // AV2 v1.0.0 write_intrabc_info(): intrabc_mode=1 selects a
            // reference block vector from the BVP stack. The local matcher can
            // select spatial BVPs at DRL 0/1 or default above/left entries at
            // DRL 2/3.
            op_fl = 32'd2775;
            op_fh = 32'd0;
            op_fl_inc = 8;
            op_fh_inc = 0;
          end
          7'd3,
          7'd4,
          7'd5: begin
            op_literal = 1'b1;
            case (step)
              7'd3: op_literal_value = {31'd0, (ibc_drl_idx != 2'd0)};
              7'd4: op_literal_value = {31'd0, (ibc_drl_idx != 2'd1)};
              default: op_literal_value = {31'd0, (ibc_drl_idx != 2'd2)};
            endcase
            op_literal_bits = 5'd1;
          end
          default: op_valid = 1'b0;
        endcase
      end else if (phase == PHASE_INTRA) begin
        case (step)
          7'd0: begin op_fh = 32'd16384; op_fh_inc = 8; end
          7'd1: begin op_fh = 32'd3905; op_fh_inc = 12; end
          7'd2: begin
            // AV2 v1.0.0 Sections 5.20.5.5 and 5.20.5.6:
            // read_intra_luma_mode() calls get_y_intra_mode_set(). With
            // non-directional neighbors, DC_PRED, V_PRED, and H_PRED are
            // symbols 0, 5, and 6 in mode set 0.
            if (leaf_luma_mode == LUMA_MODE_V) begin
              op_fl = 32'd6363;
              op_fh = 32'd5113;
              op_fl_inc = 6;
              op_fh_inc = 4;
            end else if (leaf_luma_mode == LUMA_MODE_H) begin
              op_fl = 32'd5113;
              op_fh = 32'd3908;
              op_fl_inc = 4;
              op_fh_inc = 2;
            end else begin
              op_fh = 32'd17593;
              op_fh_inc = 14;
            end
          end
          7'd3: begin
            if (leaf_fsc_symbol) begin
              op_fh = leaf_fsc_fh;
              op_fh_inc = 8;
            end else begin
              op_valid = 1'b0;
            end
          end
          7'd4: begin
            // AV2 v1.0.0 Section 5.20.5.6 read_intra_uv_mode():
            // palette-coded luma leaves keep chroma lossless through
            // horizontal BDPCM because AV2 palette syntax is luma-only.
            if (palette_mode) begin
              op_fl = 32'd16384;
              op_fh = 32'd0;
              op_fl_inc = 8;
              op_fh_inc = 0;
            end else begin
              op_fh = 32'd16384;
              op_fh_inc = 8;
            end
          end
          7'd5: begin
            if (palette_mode) begin
              op_fl = 32'd16384;
              op_fh = 32'd0;
              op_fl_inc = 8;
              op_fh_inc = 0;
            end else begin
              op_fh = 32'd23405;
              op_fh_inc = 14;
            end
          end
          default: op_valid = 1'b0;
        endcase
      end else if (leaf_luma_palette &&
                   (phase == PHASE_PALETTE_HEADER || phase == PHASE_PALETTE_MAP)) begin
        op_valid = palette_op_valid;
        op_literal = palette_op_literal;
        op_literal_value = palette_op_literal_value;
        op_literal_bits = palette_op_literal_bits;
        op_fl = palette_op_fl;
        op_fh = palette_op_fh;
        op_fl_inc = palette_op_fl_inc;
        op_fh_inc = palette_op_fh_inc;
      end else if (phase == PHASE_Y_COEFF) begin
        if (residual_mode) begin
          op_valid = luma_residual_op_valid;
          op_literal = luma_residual_op_literal;
          op_literal_value = luma_residual_op_literal_value;
          op_literal_bits = luma_residual_op_literal_bits;
          op_fl = luma_residual_op_fl;
          op_fh = luma_residual_op_fh;
          op_fl_inc = luma_residual_op_fl_inc;
          op_fh_inc = luma_residual_op_fh_inc;
        end else begin
          case (step)
            7'd0: begin
              op_fh = y_txb_nonzero_fh;
              op_fh_inc = 8;
            end
            7'd1: begin op_fh = 32'd30822; op_fh_inc = 12; end
            7'd2: begin op_fl = 32'd704; op_fh = 32'd0; op_fl_inc = 3; op_fh_inc = 0; end
            7'd3: begin op_fl = 32'd11993; op_fh = 32'd0; op_fl_inc = 4; op_fh_inc = 0; end
            7'd4: begin
              op_fl = y_dc_sign_fl;
              op_fh = 32'd0;
              op_fl_inc = 8;
              op_fh_inc = 0;
            end
            7'd5: begin op_literal = 1'b1; op_literal_value = 32'd0; op_literal_bits = 5'd5; end
            7'd6: begin op_literal = 1'b1; op_literal_value = 32'd0; op_literal_bits = 5'd6; end
            7'd7: begin op_literal = 1'b1; op_literal_value = 32'd249; op_literal_bits = 5'd8; end
            7'd8: begin op_literal = 1'b1; op_literal_value = 32'd0; op_literal_bits = 5'd1; end
            default: op_valid = 1'b0;
          endcase
        end
      end else if (residual_mode) begin
        op_valid = chroma_bdpcm_op_valid;
        op_literal = chroma_bdpcm_op_literal;
        op_literal_value = chroma_bdpcm_op_literal_value;
        op_literal_bits = chroma_bdpcm_op_literal_bits;
        op_fl = chroma_bdpcm_op_fl;
        op_fh = chroma_bdpcm_op_fh;
        op_fl_inc = chroma_bdpcm_op_fl_inc;
        op_fh_inc = chroma_bdpcm_op_fh_inc;
      end else begin
        case (step)
          7'd0: begin
            // AV2 v1.0.0 Section 5.20.7.27 coeffs(): txb_skip=0 for
            // an internal black lossless DC-only chroma TX_4X4 transform.
            if (phase == PHASE_U_COEFF) begin
              op_fh = u_txb_nonzero_fh;
            end else begin
              op_fh = v_txb_nonzero_fh;
            end
            op_fh_inc = 8;
          end
          7'd1: begin op_fh = 32'd24768; op_fh_inc = 12; end
          7'd2: begin op_fl = 32'd511; op_fh = 32'd0; op_fl_inc = 3; op_fh_inc = 0; end
          7'd3: begin op_literal = 1'b1; op_literal_value = 32'd1; op_literal_bits = 5'd1; end
          7'd4: begin op_literal = 1'b1; op_literal_value = 32'd0; op_literal_bits = 5'd5; end
          7'd5: begin op_literal = 1'b1; op_literal_value = 32'd0; op_literal_bits = 5'd6; end
          7'd6: begin op_literal = 1'b1; op_literal_value = 32'd250; op_literal_bits = 5'd8; end
          7'd7: begin op_literal = 1'b1; op_literal_value = 32'd1; op_literal_bits = 5'd1; end
          default: op_valid = 1'b0;
        endcase
      end
    end

    op_last = leaf_active &&
              (phase == PHASE_V_COEFF) &&
              (txb_index == (txb_count - 16'd1)) &&
              ((residual_mode && chroma_bdpcm_txb_done) || (!residual_mode && step == 7'd7)) &&
              stack_empty;
  end

endmodule
