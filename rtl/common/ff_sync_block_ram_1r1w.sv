module ff_sync_block_ram_1r1w #(
  parameter int DATA_BITS = 8,
  parameter int ADDR_BITS = 16,
  parameter int DEPTH = 1 << ADDR_BITS
) (
  input  logic clk,
  input  logic write_valid,
  input  logic [ADDR_BITS - 1:0] write_addr,
  input  logic [DATA_BITS - 1:0] write_data,
  input  logic [ADDR_BITS - 1:0] read_addr,
  output logic [DATA_BITS - 1:0] read_data
);
  (* ram_style = "block" *) logic [DATA_BITS - 1:0] mem_q [0:DEPTH - 1];

  always_ff @(posedge clk) begin
    read_data <= mem_q[read_addr];
    if (write_valid) begin
      mem_q[write_addr] <= write_data;
    end
  end
endmodule
