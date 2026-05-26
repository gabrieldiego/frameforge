`timescale 1ns/1ps

module ff_vvc_residual_transform #(
  parameter int SAMPLE_BITS = 8,
  parameter int LUMA_CB_SIZE = 4,
  parameter int CU_ACTIVE_COUNT = 64
) (
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic enable,
  input  logic [CU_ACTIVE_COUNT - 1:0] cu_active_mask,
  input  logic [7:0] cu_index,
  output logic cu_active,
  input  logic s_axis_valid,
  output logic s_axis_ready,
  input  logic [SAMPLE_BITS - 1:0] s_axis_sample,
  input  logic s_axis_last,
  output logic m_axis_valid,
  input  logic m_axis_ready,
  output logic [7:0] m_axis_kind,
  output logic [31:0] m_axis_data,
  output logic m_axis_last,
  input  logic [(SAMPLE_BITS * LUMA_CB_SIZE * LUMA_CB_SIZE) - 1:0] luma_samples,
  output logic [4:0]   quant_luma_rem,
  output logic [119:0] quant_luma_ac_tokens,
  output logic [7:0]   recon_luma_sample
);
  import ff_vvc_reconstruction_pkg::*;

  localparam int LUMA_SAMPLE_COUNT = LUMA_CB_SIZE * LUMA_CB_SIZE;

  logic signed [9:0] dc_coeff;
  logic signed [9:0] quantized_dc_coeff;
  logic [7:0] dc_sample;
  logic [(SAMPLE_BITS * LUMA_SAMPLE_COUNT) - 1:0] stream_samples_q;
  logic [4:0] stream_sample_count_q;
  logic stream_result_valid_q;
  logic [3:0] stream_packet_index_q;
  logic [4:0] stream_quant_luma_rem;
  logic [119:0] stream_quant_luma_ac_tokens;
  logic [7:0] stream_recon_luma_sample;

  assign dc_sample = forward_luma_dc_sample(luma_samples);
  assign dc_coeff = $signed({ 2'b00, dc_sample }) - 10'sd114;
  assign quant_luma_rem = quant_luma_rem_from_dc_coeff(dc_coeff);
  assign quant_luma_ac_tokens = quant_ac_tokens(luma_samples, dc_sample);
  assign quantized_dc_coeff = ff_vvc_reconstructed_luma_dc_coeff_from_rem(quant_luma_rem);
  assign recon_luma_sample = ff_vvc_inverse_luma_dc_coeff(quantized_dc_coeff);
  assign s_axis_ready = enable && (!stream_result_valid_q || (m_axis_valid && m_axis_ready && m_axis_last));
  assign stream_quant_luma_rem =
    quant_luma_rem_from_dc_coeff($signed({2'b00, forward_luma_dc_sample(stream_samples_q)}) - 10'sd114);
  assign stream_quant_luma_ac_tokens = quant_ac_tokens(stream_samples_q, forward_luma_dc_sample(stream_samples_q));
  assign stream_recon_luma_sample =
    ff_vvc_inverse_luma_dc_coeff(ff_vvc_reconstructed_luma_dc_coeff_from_rem(stream_quant_luma_rem));
  assign cu_active = cu_active_mask[CU_ACTIVE_COUNT - 1 - cu_index];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stream_samples_q <= '0;
      stream_sample_count_q <= 5'd0;
      stream_result_valid_q <= 1'b0;
      stream_packet_index_q <= 4'd0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else if (clear || !enable) begin
      stream_samples_q <= '0;
      stream_sample_count_q <= 5'd0;
      stream_result_valid_q <= 1'b0;
      stream_packet_index_q <= 4'd0;
      m_axis_valid <= 1'b0;
      m_axis_kind <= 8'd0;
      m_axis_data <= 32'd0;
      m_axis_last <= 1'b0;
    end else begin
      if (s_axis_valid && s_axis_ready) begin
        stream_samples_q[((LUMA_SAMPLE_COUNT - 1) - stream_sample_count_q) * SAMPLE_BITS +: SAMPLE_BITS] <=
          s_axis_sample;
        if (s_axis_last || stream_sample_count_q == LUMA_SAMPLE_COUNT - 1) begin
          stream_result_valid_q <= 1'b1;
          stream_packet_index_q <= 4'd0;
          stream_sample_count_q <= 5'd0;
        end else begin
          stream_sample_count_q <= stream_sample_count_q + 5'd1;
        end
      end

      if (stream_result_valid_q && (!m_axis_valid || m_axis_ready)) begin
        m_axis_valid <= 1'b1;
        {m_axis_kind, m_axis_data, m_axis_last} <= residual_packet(stream_packet_index_q);
        if (stream_packet_index_q == residual_last_packet_index(stream_quant_luma_rem)) begin
          stream_result_valid_q <= 1'b0;
          stream_packet_index_q <= 4'd0;
        end else begin
          stream_packet_index_q <= stream_packet_index_q + 4'd1;
        end
      end else if (m_axis_valid && m_axis_ready) begin
        m_axis_valid <= 1'b0;
        m_axis_kind <= 8'd0;
        m_axis_data <= 32'd0;
        m_axis_last <= 1'b0;
      end
    end
  end

  function automatic logic [40:0] residual_packet(input logic [3:0] index);
    logic [4:0] rem;
    logic signed [9:0] recon_dc;
    logic negative;
    begin
      rem = stream_quant_luma_rem;
      recon_dc = ff_vvc_reconstructed_luma_dc_coeff_from_rem(rem);
      negative = (rem != 5'd0) && (recon_dc < 10'sd0);
      case (index)
        4'd0: residual_packet = {8'd1, 27'd0, rem, 1'b0};
        4'd1: residual_packet = {8'd2, stream_quant_luma_ac_tokens[119:88], 1'b0};
        4'd2: residual_packet = {8'd3, stream_quant_luma_ac_tokens[87:56], 1'b0};
        4'd3: residual_packet = {8'd4, stream_quant_luma_ac_tokens[55:24], 1'b0};
        4'd4: residual_packet = {8'd5, stream_quant_luma_ac_tokens[23:0], 8'd0, 1'b0};
        4'd5: residual_packet = {8'd6, 24'd0, stream_recon_luma_sample, 1'b0};
        // Named residual CABAC symbol stream. Data packing is deliberately
        // simple for cocotb/software comparison: low bits hold fields named
        // by the packet kind rather than a final encoded payload.
        4'd6: residual_packet = {8'd7, 31'd0, 1'b0, 1'b0}; // last_sig_coeff_x_prefix binIdx=0 bin=0
        4'd7: residual_packet = {8'd8, 31'd0, 1'b0, 1'b0}; // last_sig_coeff_y_prefix binIdx=0 bin=0
        4'd8: residual_packet = {8'd9, 27'd0, 2'd0, 2'd0, rem != 5'd0, residual_last_packet_index(rem) == 4'd8};
        4'd9: residual_packet = {8'd10, 27'd0, 2'd0, 2'd0, 1'b0, 1'b0}; // par_level_flag
        4'd10: residual_packet = {8'd11, 28'd0, 3'd0, rem > 5'd1, 1'b0}; // abs_level_gtx_flag[0]
        4'd11: residual_packet = {8'd12, 24'd0, 3'd0, residual_abs_remainder_value(rem), 1'b0};
        default: residual_packet = {8'd13, 27'd0, 2'd0, 2'd0, negative, 1'b1}; // coeff_sign_flag
      endcase
    end
  endfunction

  function automatic logic [3:0] residual_last_packet_index(input logic [4:0] rem);
    begin
      if (rem == 5'd0) begin
        residual_last_packet_index = 4'd8;
      end else if (rem <= 5'd1) begin
        residual_last_packet_index = 4'd10;
      end else begin
        residual_last_packet_index = 4'd12;
      end
    end
  endfunction

  function automatic logic [4:0] residual_abs_remainder_value(input logic [4:0] rem);
    begin
      residual_abs_remainder_value = (rem > 5'd1) ? (rem - 5'd2) : 5'd0;
    end
  endfunction

  function automatic logic [7:0] forward_luma_dc_sample(
    input logic [(SAMPLE_BITS * LUMA_SAMPLE_COUNT) - 1:0] samples
  );
    logic [12:0] sum;
    begin
      // Current token generation still emits only the DC coefficient, but the
      // residual block consumes all luma samples so SW and RTL share the same
      // first transform boundary.
      sum =
        {5'd0, sample_at(samples, 4'd0)}  + {5'd0, sample_at(samples, 4'd1)}  +
        {5'd0, sample_at(samples, 4'd2)}  + {5'd0, sample_at(samples, 4'd3)}  +
        {5'd0, sample_at(samples, 4'd4)}  + {5'd0, sample_at(samples, 4'd5)}  +
        {5'd0, sample_at(samples, 4'd6)}  + {5'd0, sample_at(samples, 4'd7)}  +
        {5'd0, sample_at(samples, 4'd8)}  + {5'd0, sample_at(samples, 4'd9)}  +
        {5'd0, sample_at(samples, 4'd10)} + {5'd0, sample_at(samples, 4'd11)} +
        {5'd0, sample_at(samples, 4'd12)} + {5'd0, sample_at(samples, 4'd13)} +
        {5'd0, sample_at(samples, 4'd14)} + {5'd0, sample_at(samples, 4'd15)};
      forward_luma_dc_sample = (sum + 13'd8) >> 4;
    end
  endfunction

  function automatic logic [119:0] quant_ac_tokens(
    input logic [(SAMPLE_BITS * LUMA_SAMPLE_COUNT) - 1:0] samples,
    input logic [7:0]   dc
  );
    logic [119:0] tokens;
    integer i;
    begin
      tokens = '0;
      for (i = 1; i < 16; i = i + 1) begin
        tokens = (tokens << 8) | quant_ac_token(sample_at(samples, i[3:0]), dc);
      end
      quant_ac_tokens = tokens;
    end
  endfunction

  function automatic logic [7:0] sample_at(
    input logic [(SAMPLE_BITS * LUMA_SAMPLE_COUNT) - 1:0] samples,
    input logic [3:0] index
  );
    logic [SAMPLE_BITS - 1:0] raw;
    begin
      raw = samples[(15 - index) * SAMPLE_BITS +: SAMPLE_BITS];
      if (SAMPLE_BITS <= 8) begin
        sample_at = raw[7:0];
      end else begin
        sample_at = raw >> (SAMPLE_BITS - 8);
      end
    end
  endfunction

  function automatic logic [7:0] quant_ac_token(input logic [7:0] sample, input logic [7:0] dc);
    logic signed [9:0] coeff;
    logic [8:0] abs_coeff;
    logic [4:0] magnitude;
    logic negative;
    begin
      coeff = $signed({ 2'b00, sample }) - $signed({ 2'b00, dc });
      negative = coeff < 0;
      abs_coeff = negative ? -coeff : coeff;
      magnitude = (abs_coeff + 9'd8) >> 4;
      if (magnitude > 5'd8) begin
        magnitude = 5'd8;
      end
      if (magnitude == 5'd0) begin
        negative = 1'b0;
      end
      quant_ac_token = 8'h40 | { 2'b00, negative, magnitude };
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_dc_coeff(input logic signed [9:0] coeff);
    logic [7:0] sample;
    begin
      sample = ff_vvc_inverse_luma_dc_coeff(coeff);
      quant_luma_rem_from_dc_coeff = quant_luma_rem_from_sample(sample);
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_sample(input logic [7:0] sample);
    logic [12:0] scaled_distance;
    begin
      if (sample >= 8'd114) begin
        quant_luma_rem_from_sample = 5'd0;
      end else begin
        scaled_distance = (((13'd114 - {5'd0, sample}) * 13'd16) + 13'd57) / 13'd114;
        quant_luma_rem_from_sample =
          (scaled_distance > 13'd16) ? 5'd16 : scaled_distance[4:0];
      end
    end
  endfunction
endmodule
