`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module ff_av2_chroma_sample_store (
  input  logic        clk,
  input  logic        write_u_en,
  input  logic        write_v_en,
  input  logic [11:0] write_addr,
  input  logic [7:0]  write_data,
  input  logic [11:0] read_addr,
  output logic [7:0]  read_u_data,
  output logic [7:0]  read_v_data
);

  logic [7:0] u_mem_q [0:4095];
  logic [7:0] v_mem_q [0:4095];

  always_ff @(posedge clk) begin
    if (write_u_en) begin
      u_mem_q[write_addr] <= write_data;
    end
    if (write_v_en) begin
      v_mem_q[write_addr] <= write_data;
    end
    read_u_data <= u_mem_q[read_addr];
    read_v_data <= v_mem_q[read_addr];
  end

endmodule
