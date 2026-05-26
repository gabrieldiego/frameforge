`timescale 1ns/1ps

module ff_vvc_coding_tree_scheduler #(
  parameter int CTU_SIZE = 64
) (
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,

  output logic [15:0] coded_width,
  output logic [15:0] coded_height,
  output logic [1:0]  body_kind
);
  import ff_vvc_geometry_pkg::*;

  localparam logic [1:0] BODY_GENERATED       = 2'd0;

  always_comb begin
    coded_width = ff_vvc_coded_dimension(visible_width);
    coded_height = ff_vvc_coded_dimension(visible_height);
    body_kind = BODY_GENERATED;
  end

endmodule
