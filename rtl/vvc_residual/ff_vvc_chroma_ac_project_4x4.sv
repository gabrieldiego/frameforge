`timescale 1ns/1ps

module ff_vvc_dct2_4_basis (
  input  logic [1:0] sample_index,
  output logic signed [31:0] basis_0,
  output logic signed [31:0] basis_1,
  output logic signed [31:0] basis_2,
  output logic signed [31:0] basis_3
);
  always @* begin
    basis_0 = 32'sd64;
    basis_1 = 32'sd0;
    basis_2 = 32'sd0;
    basis_3 = 32'sd0;

    // Current residual subset fixes 4:2:0 chroma transform blocks to 4x4.
    // H.266 8.7.4 inverse transform uses the 4-point DCT-II rows mirrored in
    // the software model; larger basis tables are intentionally not present in
    // this synthesis path.
    case (sample_index)
      2'd0: begin basis_1 = 32'sd83;  basis_2 = 32'sd64;   basis_3 = 32'sd36;  end
      2'd1: begin basis_1 = 32'sd36;  basis_2 = -32'sd64;  basis_3 = -32'sd83; end
      2'd2: begin basis_1 = -32'sd36; basis_2 = -32'sd64;  basis_3 = 32'sd83;  end
      default: begin basis_1 = -32'sd83; basis_2 = 32'sd64; basis_3 = -32'sd36; end
    endcase
  end
endmodule

module ff_vvc_chroma_ac_project_4x4 (
  input  logic [15:0] sample_x,
  input  logic [15:0] sample_y,
  input  logic signed [15:0] residual,
  output logic [(64 * 15) - 1:0] ac_terms
);
  logic signed [31:0] basis_x_0_w;
  logic signed [31:0] basis_x_1_w;
  logic signed [31:0] basis_x_2_w;
  logic signed [31:0] basis_x_3_w;
  logic signed [31:0] basis_y_0_w;
  logic signed [31:0] basis_y_1_w;
  logic signed [31:0] basis_y_2_w;
  logic signed [31:0] basis_y_3_w;
  logic signed [63:0] residual_ext_w;
  logic signed [63:0] basis_x_0_ext_w;
  logic signed [63:0] basis_x_1_ext_w;
  logic signed [63:0] basis_x_2_ext_w;
  logic signed [63:0] basis_x_3_ext_w;
  logic signed [63:0] basis_y_0_ext_w;
  logic signed [63:0] basis_y_1_ext_w;
  logic signed [63:0] basis_y_2_ext_w;
  logic signed [63:0] basis_y_3_ext_w;

  // H.266 7.3.11.10 writes residual coefficients for the TU dimensions. In the
  // current fixed-TB subset that is exactly the 4x4 chroma coefficient group.
  ff_vvc_dct2_4_basis x_basis (
    .sample_index(sample_x[1:0]),
    .basis_0(basis_x_0_w),
    .basis_1(basis_x_1_w),
    .basis_2(basis_x_2_w),
    .basis_3(basis_x_3_w)
  );

  ff_vvc_dct2_4_basis y_basis (
    .sample_index(sample_y[1:0]),
    .basis_0(basis_y_0_w),
    .basis_1(basis_y_1_w),
    .basis_2(basis_y_2_w),
    .basis_3(basis_y_3_w)
  );

  assign residual_ext_w = {{48{residual[15]}}, residual};
  assign basis_x_0_ext_w = {{32{basis_x_0_w[31]}}, basis_x_0_w};
  assign basis_x_1_ext_w = {{32{basis_x_1_w[31]}}, basis_x_1_w};
  assign basis_x_2_ext_w = {{32{basis_x_2_w[31]}}, basis_x_2_w};
  assign basis_x_3_ext_w = {{32{basis_x_3_w[31]}}, basis_x_3_w};
  assign basis_y_0_ext_w = {{32{basis_y_0_w[31]}}, basis_y_0_w};
  assign basis_y_1_ext_w = {{32{basis_y_1_w[31]}}, basis_y_1_w};
  assign basis_y_2_ext_w = {{32{basis_y_2_w[31]}}, basis_y_2_w};
  assign basis_y_3_ext_w = {{32{basis_y_3_w[31]}}, basis_y_3_w};

  always @* begin
    ac_terms = '0;
    ac_terms[(0 * 64) +: 64] = residual_ext_w * basis_x_1_ext_w * basis_y_0_ext_w;
    ac_terms[(1 * 64) +: 64] = residual_ext_w * basis_x_2_ext_w * basis_y_0_ext_w;
    ac_terms[(2 * 64) +: 64] = residual_ext_w * basis_x_3_ext_w * basis_y_0_ext_w;
    ac_terms[(3 * 64) +: 64] = residual_ext_w * basis_x_0_ext_w * basis_y_1_ext_w;
    ac_terms[(4 * 64) +: 64] = residual_ext_w * basis_x_1_ext_w * basis_y_1_ext_w;
    ac_terms[(5 * 64) +: 64] = residual_ext_w * basis_x_2_ext_w * basis_y_1_ext_w;
    ac_terms[(6 * 64) +: 64] = residual_ext_w * basis_x_3_ext_w * basis_y_1_ext_w;
    ac_terms[(7 * 64) +: 64] = residual_ext_w * basis_x_0_ext_w * basis_y_2_ext_w;
    ac_terms[(8 * 64) +: 64] = residual_ext_w * basis_x_1_ext_w * basis_y_2_ext_w;
    ac_terms[(9 * 64) +: 64] = residual_ext_w * basis_x_2_ext_w * basis_y_2_ext_w;
    ac_terms[(10 * 64) +: 64] = residual_ext_w * basis_x_3_ext_w * basis_y_2_ext_w;
    ac_terms[(11 * 64) +: 64] = residual_ext_w * basis_x_0_ext_w * basis_y_3_ext_w;
    ac_terms[(12 * 64) +: 64] = residual_ext_w * basis_x_1_ext_w * basis_y_3_ext_w;
    ac_terms[(13 * 64) +: 64] = residual_ext_w * basis_x_2_ext_w * basis_y_3_ext_w;
    ac_terms[(14 * 64) +: 64] = residual_ext_w * basis_x_3_ext_w * basis_y_3_ext_w;
  end
endmodule
