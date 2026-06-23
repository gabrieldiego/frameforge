`timescale 1ns/1ps

module ff_vvc_cabac_bit_writer (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,

  input  logic        s_axis_valid,
  output logic        s_axis_ready,
  input  logic [31:0] s_axis_value,
  input  logic [5:0]  s_axis_bit_count,
  input  logic        s_axis_flush_zero,
  input  logic        s_axis_last,

  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,

  output logic [12:0] total_bit_count,
  output logic [2:0]  partial_bit_count,
  output logic        idle,
  output logic        done
);
  typedef enum logic [1:0] {
    ST_IDLE,
    ST_BITS,
    ST_FLUSH,
    ST_OUT
  } state_t;

  state_t state_q;
  logic [31:0] value_q;
  logic [5:0] bits_left_q;
  logic [7:0] partial_byte_q;
  logic [2:0] partial_count_q;
  logic [7:0] out_byte_q;
  logic out_last_q;
  logic command_last_q;
  logic [12:0] total_bit_count_q;
  logic [3:0] partial_space_w;
  logic [5:0] consume_count_w;
  logic [5:0] remaining_bits_w;
  logic [31:0] consume_mask_w;
  logic [31:0] consume_chunk_w;
  logic [8:0] partial_next_w;
  logic [3:0] partial_count_next_w;

  assign s_axis_ready = (state_q == ST_IDLE);
  assign m_axis_valid = (state_q == ST_OUT);
  assign m_axis_data = out_byte_q;
  assign m_axis_last = m_axis_valid && out_last_q;
  assign total_bit_count = total_bit_count_q;
  assign partial_bit_count = partial_count_q;
  assign idle = (state_q == ST_IDLE) && !m_axis_valid;

  always @* begin
    partial_space_w = 4'd8 - {1'b0, partial_count_q};
    if (bits_left_q == 6'd0) begin
      consume_count_w = 6'd0;
    end else if (bits_left_q < {2'd0, partial_space_w}) begin
      consume_count_w = bits_left_q;
    end else begin
      consume_count_w = {2'd0, partial_space_w};
    end

    remaining_bits_w = bits_left_q - consume_count_w;
    consume_mask_w =
      (consume_count_w == 6'd0) ? 32'd0 : ((32'd1 << consume_count_w) - 32'd1);
    consume_chunk_w = (value_q >> remaining_bits_w) & consume_mask_w;
    partial_next_w =
      ({1'b0, partial_byte_q} << consume_count_w) | {1'b0, consume_chunk_w[7:0]};
    partial_count_next_w = {1'b0, partial_count_q} + consume_count_w[3:0];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      value_q <= 32'd0;
      bits_left_q <= 6'd0;
      partial_byte_q <= 8'd0;
      partial_count_q <= 3'd0;
      out_byte_q <= 8'd0;
      out_last_q <= 1'b0;
      command_last_q <= 1'b0;
      total_bit_count_q <= 13'd0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      value_q <= 32'd0;
      bits_left_q <= 6'd0;
      partial_byte_q <= 8'd0;
      partial_count_q <= 3'd0;
      out_byte_q <= 8'd0;
      out_last_q <= 1'b0;
      command_last_q <= 1'b0;
      total_bit_count_q <= 13'd0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      case (state_q)
        ST_IDLE: begin
          if (s_axis_valid && s_axis_ready) begin
            command_last_q <= s_axis_last;
            if (s_axis_flush_zero) begin
              if (partial_count_q != 3'd0) begin
                out_byte_q <= partial_byte_q << (3'd0 - partial_count_q);
                out_last_q <= s_axis_last;
                partial_byte_q <= 8'd0;
                partial_count_q <= 3'd0;
                state_q <= ST_OUT;
              end else if (s_axis_last) begin
                done <= 1'b1;
              end
            end else if (s_axis_bit_count != 6'd0) begin
              if ((partial_count_q == 3'd0) && (s_axis_bit_count == 6'd8)) begin
                out_byte_q <= s_axis_value[7:0];
                out_last_q <= s_axis_last;
                total_bit_count_q <= total_bit_count_q + 13'd8;
                state_q <= ST_OUT;
              end else begin
                value_q <= s_axis_value;
                bits_left_q <= s_axis_bit_count;
                state_q <= ST_BITS;
              end
            end else if (s_axis_last) begin
              done <= 1'b1;
            end
          end
        end

        ST_BITS: begin
          total_bit_count_q <= total_bit_count_q + {7'd0, consume_count_w};
          bits_left_q <= remaining_bits_w;

          if (partial_count_next_w == 4'd8) begin
            out_byte_q <= partial_next_w[7:0];
            out_last_q <= command_last_q && (remaining_bits_w == 6'd0);
            partial_byte_q <= 8'd0;
            partial_count_q <= 3'd0;
            state_q <= ST_OUT;
          end else begin
            partial_byte_q <= partial_next_w[7:0];
            partial_count_q <= partial_count_next_w[2:0];
            if (remaining_bits_w == 6'd0) begin
              state_q <= ST_IDLE;
            end
          end
        end

        ST_OUT: begin
          if (m_axis_ready) begin
            if (bits_left_q != 6'd0) begin
              out_last_q <= 1'b0;
              state_q <= ST_BITS;
            end else begin
              done <= out_last_q;
              out_last_q <= 1'b0;
              command_last_q <= 1'b0;
              state_q <= ST_IDLE;
            end
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
