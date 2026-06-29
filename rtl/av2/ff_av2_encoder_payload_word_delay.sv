`timescale 1ns/1ps

module ff_av2_encoder_payload_word_delay (
  input  logic         clk,
  input  logic         rst_n,
  input  logic [11:0]  payload_read_word_addr_q,
  output logic [11:0]  payload_read_data_word_addr_q
);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      payload_read_data_word_addr_q <= 12'd0;
    end else begin
      payload_read_data_word_addr_q <= payload_read_word_addr_q;
    end
  end

endmodule
