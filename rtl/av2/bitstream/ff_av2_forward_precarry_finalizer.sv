`timescale 1ns/1ps

module ff_av2_forward_precarry_finalizer #(
  // Must match src/av2/entropy.rs AV2_PRE_CARRY_PENDING_LIMIT. Keep this
  // local to the RTL entropy path so build/synthesis entry points do not grow
  // another public knob for an internal carry guard.
  parameter int PENDING_WORDS = 32
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        tile_reset,
  input  logic        push_valid,
  input  logic [15:0] push_word,
  output logic        push_ready,
  input  logic        flush_start,
  input  logic        count_only,
  input  logic        payload_write_ready,
  output logic        flush_done,
  output logic        payload_write_valid,
  output logic [15:0] payload_write_addr,
  output logic [7:0]  payload_write_data,
  input  logic [15:0] payload_base,
  output logic        payload_write_last,
  output logic [15:0] byte_count,
  output logic [5:0]  pending_count,
  output logic        overflow_error
);

  localparam int PENDING_COUNT_BITS =
    (PENDING_WORDS > 1) ? $clog2(PENDING_WORDS + 1) : 1;

  logic [8:0] pending_q [0:PENDING_WORDS - 1];
  logic [PENDING_COUNT_BITS - 1:0] pending_count_q;
  logic [15:0] byte_count_q;
  logic flush_active_q;
  logic flush_done_q;
  logic overflow_error_q;
  logic flush_active_w;
  logic stable_oldest_w;
  logic emit_now_w;
  logic [7:0] oldest_byte0_w;
  logic [7:0] oldest_byte1_w;
  logic [7:0] oldest_byte2_w;
  logic [9:0] carry0_w;
  logic [9:0] carry1_w;
  logic [9:0] carry2_w;
  logic [9:0] sum0_w;
  logic [9:0] sum1_w;
  logic [9:0] sum2_w;
  logic [PENDING_COUNT_BITS - 1:0] pending_count_after_emit_w;
  logic emit_ready_w;
  logic push_fits_w;
  logic full_unstable_w;
  integer eval_i;
  integer shift_i;

  always @* begin
    carry0_w = 10'd0;
    carry1_w = 10'd1;
    carry2_w = 10'd2;
    oldest_byte0_w = 8'd0;
    oldest_byte1_w = 8'd0;
    oldest_byte2_w = 8'd0;
    sum0_w = 10'd0;
    sum1_w = 10'd0;
    sum2_w = 10'd0;
    for (eval_i = PENDING_WORDS - 1; eval_i >= 0; eval_i = eval_i - 1) begin
      if (eval_i < pending_count_q) begin
        sum0_w = {1'b0, pending_q[eval_i]} + carry0_w;
        sum1_w = {1'b0, pending_q[eval_i]} + carry1_w;
        sum2_w = {1'b0, pending_q[eval_i]} + carry2_w;
        if (eval_i == 0) begin
          oldest_byte0_w = sum0_w[7:0];
          oldest_byte1_w = sum1_w[7:0];
          oldest_byte2_w = sum2_w[7:0];
        end
        carry0_w = {8'd0, sum0_w[9:8]};
        carry1_w = {8'd0, sum1_w[9:8]};
        carry2_w = {8'd0, sum2_w[9:8]};
      end
    end
  end

  assign flush_active_w = flush_active_q || flush_start;
  assign stable_oldest_w =
    (pending_count_q != {PENDING_COUNT_BITS{1'b0}}) &&
    (oldest_byte0_w == oldest_byte1_w) &&
    (oldest_byte0_w == oldest_byte2_w);
  assign emit_ready_w = count_only || payload_write_ready;
  assign emit_now_w =
    !overflow_error_q &&
    emit_ready_w &&
    (pending_count_q != {PENDING_COUNT_BITS{1'b0}}) &&
    (flush_active_w || stable_oldest_w);
  assign pending_count_after_emit_w =
    emit_now_w ? (pending_count_q - {{(PENDING_COUNT_BITS - 1){1'b0}}, 1'b1}) :
                 pending_count_q;
  assign push_fits_w =
    !flush_active_w &&
    !overflow_error_q &&
    ((pending_count_after_emit_w < PENDING_COUNT_BITS'(PENDING_WORDS)) || !push_valid);
  assign push_ready =
    !flush_active_w &&
    !overflow_error_q &&
    (pending_count_after_emit_w < PENDING_COUNT_BITS'(PENDING_WORDS));
  assign full_unstable_w =
    !flush_active_w &&
    (pending_count_q == PENDING_COUNT_BITS'(PENDING_WORDS)) &&
    !stable_oldest_w;

  assign payload_write_valid = emit_now_w && !count_only;
  assign payload_write_addr = payload_base + byte_count_q;
  assign payload_write_data = oldest_byte0_w;
  assign payload_write_last =
    payload_write_valid &&
    flush_active_w &&
    (pending_count_after_emit_w == {PENDING_COUNT_BITS{1'b0}});
  assign byte_count = byte_count_q;
  assign pending_count = pending_count_q;
  assign flush_done = flush_done_q;
  assign overflow_error = overflow_error_q;

`ifndef SYNTHESIS
  always @(posedge clk) begin
    if (rst_n && overflow_error_q) begin
      $error("AV2 forward pre-carry pending queue exceeded %0d words", PENDING_WORDS);
    end
  end
`endif

  always_ff @(posedge clk) begin
    if (!rst_n || tile_reset) begin
      pending_count_q <= {PENDING_COUNT_BITS{1'b0}};
      byte_count_q <= 16'd0;
      flush_active_q <= 1'b0;
      flush_done_q <= 1'b0;
      overflow_error_q <= 1'b0;
      for (shift_i = 0; shift_i < PENDING_WORDS; shift_i = shift_i + 1) begin
        pending_q[shift_i] <= 9'd0;
      end
    end else begin
      flush_done_q <= 1'b0;

      if (flush_start) begin
        flush_active_q <= 1'b1;
      end

      if (full_unstable_w || (push_valid && push_word[15:9] != 7'd0) ||
          (push_valid && !push_fits_w)) begin
        overflow_error_q <= 1'b1;
        flush_active_q <= 1'b0;
      end else begin
        if (emit_now_w) begin
          byte_count_q <= byte_count_q + 16'd1;
          for (shift_i = 0; shift_i < PENDING_WORDS - 1; shift_i = shift_i + 1) begin
            pending_q[shift_i] <= pending_q[shift_i + 1];
          end
          pending_q[PENDING_WORDS - 1] <= 9'd0;
          pending_count_q <= pending_count_after_emit_w;
        end

        if (push_valid && push_ready) begin
          if (emit_now_w) begin
            pending_q[pending_count_after_emit_w] <= push_word[8:0];
            pending_count_q <= pending_count_after_emit_w + {{(PENDING_COUNT_BITS - 1){1'b0}}, 1'b1};
          end else begin
            pending_q[pending_count_q] <= push_word[8:0];
            pending_count_q <= pending_count_q + {{(PENDING_COUNT_BITS - 1){1'b0}}, 1'b1};
          end
        end

        if (flush_active_w && emit_now_w &&
            (pending_count_after_emit_w == {PENDING_COUNT_BITS{1'b0}})) begin
          flush_active_q <= 1'b0;
          flush_done_q <= 1'b1;
        end else if (flush_active_w &&
                     (pending_count_q == {PENDING_COUNT_BITS{1'b0}})) begin
          flush_active_q <= 1'b0;
          flush_done_q <= 1'b1;
        end
      end
    end
  end

endmodule
