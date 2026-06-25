`timescale 1ns/1ps

module ff_sync_byte_write_word_ram_1r1w #(
  parameter int ADDR_BITS = 16,
  parameter int DEPTH_BYTES = 1 << ADDR_BITS
) (
  input  logic                  clk,
  input  logic                  write_valid,
  input  logic [ADDR_BITS-1:0]  write_addr,
  input  logic [15:0]           write_strobe,
  input  logic [127:0]          write_data,
  input  logic [ADDR_BITS-5:0]  read_word_addr,
  output logic [127:0]          read_data
);
  localparam int WORD_DEPTH = DEPTH_BYTES >> 4;
  localparam int WORD_INDEX_BITS = (WORD_DEPTH <= 1) ? 1 : $clog2(WORD_DEPTH);

  logic [WORD_INDEX_BITS-1:0] write_word_addr_w;
  logic [WORD_INDEX_BITS-1:0] read_word_addr_w;
  genvar bank_g;

  assign write_word_addr_w = write_addr[WORD_INDEX_BITS+3:4];
  assign read_word_addr_w = read_word_addr[WORD_INDEX_BITS-1:0];

  generate
    for (bank_g = 0; bank_g < 4; bank_g = bank_g + 1) begin : gen_word_bank
      (* ram_style = "block" *) logic [31:0] mem_q [0:WORD_DEPTH-1];

      always_ff @(posedge clk) begin
        read_data[bank_g * 32 +: 32] <= mem_q[read_word_addr_w];
        if (write_valid) begin
          if (write_strobe[bank_g * 4 + 0]) begin
            mem_q[write_word_addr_w][7:0] <= write_data[(bank_g * 32) + 0 +: 8];
          end
          if (write_strobe[bank_g * 4 + 1]) begin
            mem_q[write_word_addr_w][15:8] <= write_data[(bank_g * 32) + 8 +: 8];
          end
          if (write_strobe[bank_g * 4 + 2]) begin
            mem_q[write_word_addr_w][23:16] <= write_data[(bank_g * 32) + 16 +: 8];
          end
          if (write_strobe[bank_g * 4 + 3]) begin
            mem_q[write_word_addr_w][31:24] <= write_data[(bank_g * 32) + 24 +: 8];
          end
        end
      end
    end
  endgenerate
endmodule
