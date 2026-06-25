`timescale 1ns/1ps

module ff_sync_halfword_write_quad_read_ram_1r1w #(
  parameter int ADDR_BITS = 16,
  parameter int DEPTH_HALFWORDS = 1 << ADDR_BITS,
  parameter int READ_HALFWORDS = 8
) (
  input  logic                  clk,
  input  logic                  write_valid,
  input  logic [ADDR_BITS-1:0]  write_addr,
  input  logic [15:0]           write_data,
  input  logic [ADDR_BITS-$clog2(READ_HALFWORDS)-1:0] read_word_addr,
  output logic [(READ_HALFWORDS*16)-1:0] read_data
);
  localparam int READ_INDEX_BITS = $clog2(READ_HALFWORDS);
  localparam int WORD_DEPTH = DEPTH_HALFWORDS >> READ_INDEX_BITS;
  localparam int WORD_INDEX_BITS = (WORD_DEPTH <= 1) ? 1 : $clog2(WORD_DEPTH);

  logic [WORD_INDEX_BITS-1:0] write_word_addr_w;
  logic [WORD_INDEX_BITS-1:0] read_word_addr_w;
  integer halfword_i;

  assign write_word_addr_w = write_addr[WORD_INDEX_BITS+READ_INDEX_BITS-1:READ_INDEX_BITS];
  assign read_word_addr_w = read_word_addr[WORD_INDEX_BITS-1:0];

  (* ram_style = "block" *) logic [(READ_HALFWORDS*16)-1:0] mem_q [0:WORD_DEPTH-1];

  always_ff @(posedge clk) begin
    read_data <= mem_q[read_word_addr_w];
    if (write_valid) begin
      for (halfword_i = 0; halfword_i < READ_HALFWORDS; halfword_i = halfword_i + 1) begin
        if (write_addr[READ_INDEX_BITS-1:0] == halfword_i[READ_INDEX_BITS-1:0]) begin
          mem_q[write_word_addr_w][halfword_i * 16 +: 16] <= write_data;
        end
      end
    end
  end
endmodule
