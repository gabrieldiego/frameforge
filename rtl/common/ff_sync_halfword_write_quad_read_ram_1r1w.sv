`timescale 1ns/1ps

module ff_sync_halfword_write_quad_read_ram_1r1w #(
  parameter int ADDR_BITS = 16,
  parameter int DEPTH_HALFWORDS = 1 << ADDR_BITS
) (
  input  logic                  clk,
  input  logic                  write_valid,
  input  logic [ADDR_BITS-1:0]  write_addr,
  input  logic [15:0]           write_data,
  input  logic [ADDR_BITS-4:0]  read_word_addr,
  output logic [127:0]          read_data
);
  localparam int WORD_DEPTH = DEPTH_HALFWORDS >> 3;
  localparam int WORD_INDEX_BITS = (WORD_DEPTH <= 1) ? 1 : $clog2(WORD_DEPTH);

  logic [WORD_INDEX_BITS-1:0] write_word_addr_w;
  logic [WORD_INDEX_BITS-1:0] read_word_addr_w;

  assign write_word_addr_w = write_addr[WORD_INDEX_BITS+2:3];
  assign read_word_addr_w = read_word_addr[WORD_INDEX_BITS-1:0];

  (* ram_style = "block" *) logic [127:0] mem_q [0:WORD_DEPTH-1];

  always_ff @(posedge clk) begin
    read_data <= mem_q[read_word_addr_w];
    if (write_valid) begin
      case (write_addr[2:0])
        3'd0: mem_q[write_word_addr_w][15:0] <= write_data;
        3'd1: mem_q[write_word_addr_w][31:16] <= write_data;
        3'd2: mem_q[write_word_addr_w][47:32] <= write_data;
        3'd3: mem_q[write_word_addr_w][63:48] <= write_data;
        3'd4: mem_q[write_word_addr_w][79:64] <= write_data;
        3'd5: mem_q[write_word_addr_w][95:80] <= write_data;
        3'd6: mem_q[write_word_addr_w][111:96] <= write_data;
        default: mem_q[write_word_addr_w][127:112] <= write_data;
      endcase
    end
  end
endmodule
