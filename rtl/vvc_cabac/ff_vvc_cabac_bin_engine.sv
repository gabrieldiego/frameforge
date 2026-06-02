`timescale 1ns/1ps

module ff_vvc_cabac_bin_engine (
  input  logic [2:0]  bin_kind,
  input  logic        bin_value,
  input  logic [8:0]  ctx_lps,
  input  logic        ctx_mps,
  input  logic [31:0] low_in,
  input  logic [15:0] range_in,
  input  logic [7:0]  bits_left_in,
  output logic [31:0] low_out,
  output logic [15:0] range_out,
  output logic [7:0]  bits_left_out,
  output logic        write_out
);
  localparam logic [2:0] CABAC_BIN_EP  = 3'd0;
  localparam logic [2:0] CABAC_BIN_TRM = 3'd1;
  localparam logic [2:0] CABAC_BIN_CTX = 3'd2;

  logic [31:0] low_next;
  logic [15:0] range_next;
  logic [7:0] bits_left_next;
  logic [3:0] renorm;
  logic [15:0] ctx_lps_ext;

  assign ctx_lps_ext = {7'd0, ctx_lps};

  always @* begin
    low_next = low_in;
    range_next = range_in;
    bits_left_next = bits_left_in;
    renorm = 4'd0;

    case (bin_kind)
      CABAC_BIN_CTX: begin
        range_next = range_in - ctx_lps;
        if (bin_value != ctx_mps) begin
          if (ctx_lps[8]) begin
            renorm = 4'd0;
          end else if (ctx_lps[7]) begin
            renorm = 4'd1;
          end else if (ctx_lps[6]) begin
            renorm = 4'd2;
          end else if (ctx_lps[5]) begin
            renorm = 4'd3;
          end else if (ctx_lps[4]) begin
            renorm = 4'd4;
          end else if (ctx_lps[3]) begin
            renorm = 4'd5;
          end else if (ctx_lps[2]) begin
            renorm = 4'd6;
          end else if (ctx_lps[1]) begin
            renorm = 4'd7;
          end else begin
            renorm = 4'd8;
          end
          bits_left_next = bits_left_in - {4'd0, renorm};
          low_next = (low_in + range_next) << renorm;
          range_next = ctx_lps << renorm;
        end else if (range_next < 16'd256) begin
          bits_left_next = bits_left_in - 8'd1;
          low_next = low_in << 1;
          range_next = range_next << 1;
        end
      end
      CABAC_BIN_TRM: begin
        range_next = range_in - 16'd2;
        if (bin_value) begin
          low_next = (low_in + range_next) << 7;
          range_next = 16'd256;
          bits_left_next = bits_left_in - 8'd7;
        end else if (range_next < 16'd256) begin
          low_next = low_in << 1;
          range_next = range_next << 1;
          bits_left_next = bits_left_in - 8'd1;
        end
      end
      default: begin
        low_next = low_in << 1;
        if (bin_value) begin
          low_next = low_next + range_in;
        end
        bits_left_next = bits_left_in - 8'd1;
      end
    endcase

    low_out = low_next;
    range_out = range_next;
    bits_left_out = bits_left_next;
    write_out = bits_left_next < 8'd12;
  end
endmodule
