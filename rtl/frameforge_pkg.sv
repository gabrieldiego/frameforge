package frameforge_pkg;
  typedef struct packed {
    logic [15:0] x;
    logic [15:0] y;
    logic [15:0] width;
    logic [15:0] height;
    logic [7:0]  kind;
  } ff_block_packet_t;

  localparam logic [7:0] FF_BLOCK_INTRA    = 8'h01;
  localparam logic [7:0] FF_BLOCK_RESIDUAL = 8'h02;
  localparam logic [7:0] FF_BLOCK_PALETTE  = 8'h10;
  localparam logic [7:0] FF_BLOCK_IBC      = 8'h11;
endpackage

