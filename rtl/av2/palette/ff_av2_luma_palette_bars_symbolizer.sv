`timescale 1ns/1ps

module ff_av2_luma_palette_bars_symbolizer (
  input  logic       enable,
  input  logic [2:0] phase,
  input  logic [3:0] step,
  input  logic [5:0] row,
  output logic       op_valid,
  output logic       op_literal,
  output logic [31:0] op_literal_value,
  output logic [4:0]  op_literal_bits,
  output logic [31:0] op_fl,
  output logic [31:0] op_fh,
  output integer     op_fl_inc,
  output integer     op_fh_inc,
  output logic       row_has_extra_token
);

  localparam logic [2:0] PHASE_PALETTE_HEADER = 3'd1;
  localparam logic [2:0] PHASE_PALETTE_MAP = 3'd2;

  always @* begin
    op_valid = 1'b0;
    op_literal = 1'b0;
    op_literal_value = 32'd0;
    op_literal_bits = 5'd0;
    op_fl = 32'd32768;
    op_fh = 32'd0;
    op_fl_inc = 0;
    op_fh_inc = 0;
    row_has_extra_token = (row == 6'd0) || (row == 6'd32);

    if (enable && phase == PHASE_PALETTE_HEADER) begin
      op_valid = 1'b1;
      case (step)
        4'd0: begin
          // AV2 v1.0.0 Sections 5.11.55 and 5.20.5.3: palette_y_mode flag.
          op_fl = 32'd2723;
          op_fh = 32'd0;
          op_fl_inc = 8;
        end
        4'd1: begin
          // palette_y_size_minus_2 = 0 for the first two-color luma subset.
          op_fh = 32'd23989;
          op_fh_inc = 13;
        end
        4'd2: begin
          // delta_encode_palette_colors(): first luma palette entry = 32.
          op_literal = 1'b1;
          op_literal_value = 32'd32;
          op_literal_bits = 5'd8;
        end
        4'd3: begin
          // delta precision minus the AV2 8-bit minimum of five bits.
          op_literal = 1'b1;
          op_literal_value = 32'd3;
          op_literal_bits = 5'd2;
        end
        4'd4: begin
          // second luma entry 176 is coded as delta 144, stored as delta-1.
          op_literal = 1'b1;
          op_literal_value = 32'd143;
          op_literal_bits = 5'd8;
        end
        default: begin
          op_valid = 1'b0;
        end
      endcase
    end else if (enable && phase == PHASE_PALETTE_MAP) begin
      op_valid = 1'b1;
      if (step == 4'd0) begin
        // AV2 palette color-map pack_map_tokens(): the 64x64 bars vector uses
        // one repeated row run for each flat luma band and one explicit row at
        // the band transition.
        if (row == 6'd0) begin
          op_fl = 32'd19769;
          op_fh = 32'd12;
          op_fl_inc = 10;
          op_fh_inc = 5;
        end else if (row == 6'd32) begin
          op_fl = 32'd29220;
          op_fh = 32'd28605;
          op_fl_inc = 10;
          op_fh_inc = 5;
        end else if (row == 6'd1 || row == 6'd33) begin
          op_fl = 32'd27535;
          op_fh = 32'd0;
          op_fl_inc = 5;
        end else begin
          op_fl = 32'd28605;
          op_fh = 32'd0;
          op_fl_inc = 5;
        end
      end else if (step == 4'd1 && row == 6'd0) begin
        // write_uniform(n=2, value=0) for the first row's first color index.
        op_literal = 1'b1;
        op_literal_value = 32'd0;
        op_literal_bits = 5'd1;
      end else if (step == 4'd1 && row == 6'd32) begin
        // palette_y_color_index token 1 switches the transition row to color 1.
        op_fl = 32'd4628;
        op_fh = 32'd0;
        op_fl_inc = 8;
      end else begin
        op_valid = 1'b0;
      end
    end
  end

endmodule
