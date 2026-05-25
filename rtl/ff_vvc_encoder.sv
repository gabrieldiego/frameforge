`timescale 1ns/1ps

module ff_vvc_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 64,
  parameter int MAX_VISIBLE_HEIGHT = 64,
  parameter int CTU_SIZE = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS,
  // VVC chroma_format_idc values: 1=4:2:0, 2=4:2:2, 3=4:4:4.
  // 4:2:0 uses the current transform/residual path. 4:4:4 is routed through
  // the toy palette path so the sampling path is independent of TU size.
  parameter int CHROMA_FORMAT_IDC = 1,
  parameter bit PALETTE_SKIP_OFF_VIEW_CUS = 1'b1
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [1:0] frame_count,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  output logic       busy,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [SAMPLE_BITS - 1:0] s_axis_data,
  input  logic       s_axis_last,
  output logic       input_error,
  output logic       sampled_color_valid,
  output logic [SAMPLE_BITS - 1:0] sampled_y,
  output logic [SAMPLE_BITS - 1:0] sampled_u,
  output logic [SAMPLE_BITS - 1:0] sampled_v,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);
  localparam int NAL_OVERHEAD_LEN = 6;
  localparam int MAX_LUMA_SAMPLES = MAX_VISIBLE_WIDTH * MAX_VISIBLE_HEIGHT;
  localparam int MAX_CHROMA_PLANE_SAMPLES = MAX_LUMA_SAMPLES;
  localparam int MAX_FRAME_SAMPLES = MAX_LUMA_SAMPLES + (MAX_CHROMA_PLANE_SAMPLES * 2);
  localparam int INPUT_COUNT_BITS = $clog2((MAX_FRAME_SAMPLES * 2) + 1);
  localparam int TOY_RESIDUAL_CB_SIZE = 4;
  localparam int TOY_RESIDUAL_LUMA_SAMPLES = TOY_RESIDUAL_CB_SIZE * TOY_RESIDUAL_CB_SIZE;
  localparam int PALETTE_CU_SIZE = 8;
  localparam int MAX_CTU_PALETTE_SYMBOLS =
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE) *
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE);
  localparam bit PALETTE_MODE = (CHROMA_FORMAT_IDC == 3);
  localparam logic [1:0] PALETTE_OUT_IDLE     = 2'd0;
  localparam logic [1:0] PALETTE_OUT_PREAMBLE = 2'd1;
  localparam logic [1:0] PALETTE_OUT_CABAC    = 2'd2;
  localparam logic [1:0] PALETTE_OUT_TRAIL    = 2'd3;
  localparam logic [1:0] GENERATED_OUT_IDLE     = 2'd0;
  localparam logic [1:0] GENERATED_OUT_PREAMBLE = 2'd1;
  localparam logic [1:0] GENERATED_OUT_CABAC    = 2'd2;
  localparam logic [1:0] GENERATED_OUT_TRAIL    = 2'd3;

  logic [12:0] index_q;
  logic [12:0] stream_len_q;
  logic [INPUT_COUNT_BITS - 1:0] input_count_q;
  logic [INPUT_COUNT_BITS - 1:0] input_len_q;
  logic       input_active_q;
  logic [(SAMPLE_BITS * MAX_LUMA_SAMPLES) - 1:0] luma_frame_q;
  logic [(SAMPLE_BITS * TOY_RESIDUAL_LUMA_SAMPLES) - 1:0] luma_samples_q;
  logic [(SAMPLE_BITS * TOY_RESIDUAL_LUMA_SAMPLES) - 1:0] luma_samples_1_q;
  logic [4:0] quant_luma_rem_q;
  logic [4:0] quant_luma_rem_1_q;
  logic [4:0] quant_chroma_rem_q;
  logic [4:0] residual_quant_luma_rem;
  logic [4:0] residual_quant_luma_rem_1;
  logic [7:0] residual_recon_luma_sample;
  logic [7:0] residual_recon_luma_sample_1;
  logic [15:0] coding_tree_coded_width;
  logic [15:0] coding_tree_coded_height;
  logic [1:0]  coding_tree_body_kind;
  logic        cabac_enable;
  logic [7:0]  palette_symbol_count;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] palette_cu_select_mask;
  logic        palette_sample_valid;
  logic [1:0]  palette_sample_plane;
  logic        palette_stream_valid;
  logic        palette_stream_ready;
  logic [31:0] palette_stream_data;
  logic        palette_stream_last;
  logic        residual_sample_valid;
  logic        residual_sample_last;
  logic        residual_sample_1_valid;
  logic        residual_sample_1_last;
  logic        cabac_stream_valid;
  logic        cabac_stream_ready;
  logic [7:0]  cabac_stream_data;
  logic        cabac_stream_last;
  logic [12:0] cabac_stream_bit_count;
  logic [12:0] cabac_stream_byte_count;
  logic        cabac_start_q;
  logic        pending_output_q;
  logic        palette_done_q;
  logic [12:0] slice_payload_ebsp_len_q;
  logic [12:0] slice_payload_ebsp_cra_len_q;
  logic [1:0]  palette_out_state_q;
  logic [12:0] palette_out_index_q;
  logic        palette_hold_valid_q;
  logic [7:0]  palette_hold_byte_q;
  logic        palette_tail_extra_q;
  logic [1:0]  palette_zero_count_q;
  logic        palette_epb_pending_q;
  logic [7:0]  palette_epb_byte_q;
  logic        palette_epb_last_q;
  logic [1:0]  generated_out_state_q;
  logic [12:0] generated_out_index_q;
  logic        generated_slice_cra_q;
  logic        generated_hold_valid_q;
  logic [7:0]  generated_hold_byte_q;
  logic        generated_tail_extra_q;
  logic [1:0]  generated_zero_count_q;
  logic        generated_epb_pending_q;
  logic [7:0]  generated_epb_byte_q;
  logic        generated_epb_stream_last_q;
  logic        generated_epb_slice_last_q;

  assign busy = input_active_q || pending_output_q || m_axis_valid || (index_q != 0) ||
                (palette_out_state_q != PALETTE_OUT_IDLE) ||
                (generated_out_state_q != GENERATED_OUT_IDLE);
  assign cabac_enable = 1'b1;
  assign cabac_stream_ready =
    PALETTE_MODE
      ? ((palette_out_state_q == PALETTE_OUT_CABAC) && !palette_epb_pending_q &&
         (!m_axis_valid || m_axis_ready))
      : ((generated_out_state_q == GENERATED_OUT_CABAC) && !generated_epb_pending_q &&
         (!m_axis_valid || m_axis_ready));

  generate
    if (PALETTE_SKIP_OFF_VIEW_CUS) begin : gen_palette_skip_off_view_cus
      always_comb begin
        palette_cu_select_mask = '0;
        for (int i = 0; i < MAX_CTU_PALETTE_SYMBOLS; i = i + 1) begin
          palette_cu_select_mask[MAX_CTU_PALETTE_SYMBOLS - 1 - i] =
            palette_cu_origin_is_visible(i);
        end
      end
    end else begin : gen_palette_code_padded_cus
      // Compatibility mode for the current VVC syntax path, which still codes
      // padded CUs in the cropped canvas.
      assign palette_cu_select_mask = {MAX_CTU_PALETTE_SYMBOLS{1'b1}};
    end
  endgenerate

  ff_vvc_toy_coding_tree_scheduler #(
    .CTU_SIZE(CTU_SIZE)
  ) coding_tree_scheduler (
    .visible_width(visible_width),
    .visible_height(visible_height),
    .coded_width(coding_tree_coded_width),
    .coded_height(coding_tree_coded_height),
    .body_kind(coding_tree_body_kind)
  );

  generate
    if (PALETTE_MODE) begin : gen_palette_sample_route
      always @* begin
        palette_sample_valid = 1'b0;
        palette_sample_plane = 2'd0;
        if (input_active_q && s_axis_valid && (input_count_q < frame_samples())) begin
          palette_sample_valid = 1'b1;
          palette_sample_plane = palette_plane_for_input(input_count_q);
        end
      end
    end else begin : gen_no_palette_sample_route
      assign palette_sample_valid = 1'b0;
      assign palette_sample_plane = 2'd0;
    end
  endgenerate

  always @* begin
    residual_sample_valid = input_active_q && s_axis_valid && s_axis_ready &&
                            is_residual_luma_sample(input_count_q);
    residual_sample_last = residual_sample_valid &&
                           (residual_luma_sample_index(input_count_q) == 4'd15);
    residual_sample_1_valid = input_active_q && s_axis_valid && s_axis_ready &&
                              is_second_residual_luma_sample(input_count_q);
    residual_sample_1_last = residual_sample_1_valid &&
                             (second_residual_luma_sample_index(input_count_q) == 4'd15);
  end

  ff_vvc_palette_symbolizer #(
    .CTU_SIZE(CTU_SIZE),
    .PALETTE_CU_SIZE(PALETTE_CU_SIZE),
    .SAMPLE_BITS(SAMPLE_BITS),
    .MAX_PALETTE_SYMBOLS(MAX_CTU_PALETTE_SYMBOLS)
  ) palette_symbolizer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .enable(PALETTE_MODE),
    .ctu_coded_width(coding_tree_coded_width),
    .ctu_coded_height(coding_tree_coded_height),
    .cu_select_mask(palette_cu_select_mask),
    .s_axis_valid(palette_sample_valid),
    .s_axis_ready(),
    .s_axis_plane(palette_sample_plane),
    .s_axis_sample(s_axis_data),
    .s_axis_last(s_axis_last),
    .m_axis_valid(palette_stream_valid),
    .m_axis_ready(palette_stream_ready),
    .m_axis_data(palette_stream_data),
    .m_axis_last(palette_stream_last),
    .symbol_count(palette_symbol_count)
  );

  ff_vvc_cabac #(
    .MAX_VISIBLE_WIDTH(MAX_VISIBLE_WIDTH),
    .MAX_VISIBLE_HEIGHT(MAX_VISIBLE_HEIGHT),
    .MAX_PALETTE_SYMBOLS(MAX_CTU_PALETTE_SYMBOLS)
  ) cabac_writer (
    .clk(clk),
    .rst_n(rst_n),
    .start(cabac_start_q),
    .enable(cabac_enable),
    .mode_palette_444(PALETTE_MODE),
    .body_kind(coding_tree_body_kind),
    .visible_width(visible_width),
    .visible_height(visible_height),
    .coded_width(coding_tree_coded_width),
    .coded_height(coding_tree_coded_height),
    .luma_rem(quant_luma_rem_q),
    .chroma_rem(quant_chroma_rem_q),
    .symbol_count(palette_symbol_count),
    .s_axis_valid(palette_stream_valid),
    .s_axis_ready(palette_stream_ready),
    .s_axis_kind(8'd1),
    .s_axis_data(palette_stream_data),
    .s_axis_last(palette_stream_last),
    .m_axis_ready(cabac_stream_ready),
    .m_axis_valid(cabac_stream_valid),
    .m_axis_data(cabac_stream_data),
    .m_axis_last(cabac_stream_last),
    .stream_bit_count(cabac_stream_bit_count),
    .stream_byte_count(cabac_stream_byte_count)
  );

  ff_residual_stub #(
    .SAMPLE_BITS(SAMPLE_BITS),
    .LUMA_CB_SIZE(TOY_RESIDUAL_CB_SIZE)
  ) residual_block (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .enable(1'b1),
    .s_axis_valid(residual_sample_valid),
    .s_axis_ready(),
    .s_axis_sample(s_axis_data),
    .s_axis_last(residual_sample_last),
    .m_axis_valid(),
    .m_axis_ready(1'b1),
    .m_axis_kind(),
    .m_axis_data(),
    .m_axis_last(),
    .luma_samples(luma_samples_q),
    .quant_luma_rem(residual_quant_luma_rem),
    .quant_luma_ac_tokens(),
    .recon_luma_sample(residual_recon_luma_sample)
  );

  ff_residual_stub #(
    .SAMPLE_BITS(SAMPLE_BITS),
    .LUMA_CB_SIZE(TOY_RESIDUAL_CB_SIZE)
  ) residual_block_1 (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .enable(1'b1),
    .s_axis_valid(residual_sample_1_valid),
    .s_axis_ready(),
    .s_axis_sample(s_axis_data),
    .s_axis_last(residual_sample_1_last),
    .m_axis_valid(),
    .m_axis_ready(1'b1),
    .m_axis_kind(),
    .m_axis_data(),
    .m_axis_last(),
    .luma_samples(luma_samples_1_q),
    .quant_luma_rem(residual_quant_luma_rem_1),
    .quant_luma_ac_tokens(),
    .recon_luma_sample(residual_recon_luma_sample_1)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q      <= '0;
      stream_len_q <= '0;
      input_count_q <= '0;
      input_len_q   <= '0;
      input_active_q <= 1'b0;
      s_axis_ready <= 1'b0;
      input_error  <= 1'b0;
      sampled_color_valid <= 1'b0;
      sampled_y <= '0;
      sampled_u <= '0;
      sampled_v <= '0;
      luma_frame_q <= '0;
      luma_samples_q <= '0;
      luma_samples_1_q <= '0;
      quant_luma_rem_q <= 5'd16;
      quant_luma_rem_1_q <= 5'd16;
      quant_chroma_rem_q <= 5'd6;
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
      slice_payload_ebsp_len_q <= '0;
      slice_payload_ebsp_cra_len_q <= '0;
      cabac_start_q <= 1'b0;
      pending_output_q <= 1'b0;
      palette_done_q <= 1'b0;
      palette_out_state_q <= PALETTE_OUT_IDLE;
      palette_out_index_q <= 13'd0;
      palette_hold_valid_q <= 1'b0;
      palette_hold_byte_q <= 8'd0;
      palette_tail_extra_q <= 1'b0;
      palette_zero_count_q <= 2'd0;
      palette_epb_pending_q <= 1'b0;
      palette_epb_byte_q <= 8'd0;
      palette_epb_last_q <= 1'b0;
      generated_out_state_q <= GENERATED_OUT_IDLE;
      generated_out_index_q <= 13'd0;
      generated_slice_cra_q <= 1'b0;
      generated_hold_valid_q <= 1'b0;
      generated_hold_byte_q <= 8'd0;
      generated_tail_extra_q <= 1'b0;
      generated_zero_count_q <= 2'd0;
      generated_epb_pending_q <= 1'b0;
      generated_epb_byte_q <= 8'd0;
      generated_epb_stream_last_q <= 1'b0;
      generated_epb_slice_last_q <= 1'b0;
    end else begin
      cabac_start_q <= 1'b0;
      if (start && !busy) begin
        input_active_q <= 1'b1;
        s_axis_ready   <= 1'b1;
        input_count_q  <= '0;
        input_len_q    <= input_len(frame_count);
        stream_len_q   <= '0;
        input_error    <= 1'b0;
        sampled_color_valid <= 1'b0;
        luma_frame_q <= '0;
        luma_samples_q <= '0;
        luma_samples_1_q <= '0;
        quant_luma_rem_q <= 5'd16;
        quant_luma_rem_1_q <= 5'd16;
        quant_chroma_rem_q <= 5'd6;
        m_axis_valid   <= 1'b0;
        m_axis_last    <= 1'b0;
        index_q        <= '0;
        slice_payload_ebsp_len_q <= '0;
        slice_payload_ebsp_cra_len_q <= '0;
        pending_output_q <= 1'b0;
        palette_done_q <= 1'b0;
        palette_out_state_q <= PALETTE_OUT_IDLE;
        palette_out_index_q <= 13'd0;
        palette_hold_valid_q <= 1'b0;
        palette_hold_byte_q <= 8'd0;
        palette_tail_extra_q <= 1'b0;
        palette_zero_count_q <= 2'd0;
        palette_epb_pending_q <= 1'b0;
        palette_epb_byte_q <= 8'd0;
        palette_epb_last_q <= 1'b0;
        generated_out_state_q <= GENERATED_OUT_IDLE;
        generated_out_index_q <= 13'd0;
        generated_slice_cra_q <= 1'b0;
        generated_hold_valid_q <= 1'b0;
        generated_hold_byte_q <= 8'd0;
        generated_tail_extra_q <= 1'b0;
        generated_zero_count_q <= 2'd0;
        generated_epb_pending_q <= 1'b0;
        generated_epb_byte_q <= 8'd0;
        generated_epb_stream_last_q <= 1'b0;
        generated_epb_slice_last_q <= 1'b0;
      end else if (input_active_q && s_axis_valid && s_axis_ready) begin
        if (s_axis_last != (input_count_q == input_len_q - 1'b1)) begin
          input_error <= 1'b1;
        end
        if (input_count_q == 8'd0) begin
          sampled_y <= s_axis_data;
        end
        if (input_count_q < luma_samples()) begin
          luma_frame_q[(MAX_LUMA_SAMPLES - 1 - input_count_q) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (is_residual_luma_sample(input_count_q)) begin
          luma_samples_q[(15 - residual_luma_sample_index(input_count_q)) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (is_second_residual_luma_sample(input_count_q)) begin
          luma_samples_1_q[(15 - second_residual_luma_sample_index(input_count_q)) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (input_count_q == luma_samples()) begin
          quant_luma_rem_q <= residual_quant_luma_rem;
          quant_luma_rem_1_q <= residual_quant_luma_rem_1;
        end
        if (input_count_q == luma_samples()) begin
          sampled_u <= s_axis_data;
        end
        if (input_count_q == v_sample_index()) begin
          sampled_v <= s_axis_data;
          quant_chroma_rem_q <= quant_chroma_rem_from_samples(sampled_u, s_axis_data);
        end

        if (input_count_q == input_len_q - 1'b1) begin
          input_active_q <= 1'b0;
          s_axis_ready   <= 1'b0;
          sampled_color_valid <= !input_error && s_axis_last;
          pending_output_q <= 1'b1;
        end else begin
          input_count_q <= input_count_q + 1'b1;
        end
      end else if (pending_output_q && PALETTE_MODE &&
                   (palette_out_state_q == PALETTE_OUT_IDLE)) begin
        pending_output_q <= 1'b0;
        palette_out_state_q <= PALETTE_OUT_PREAMBLE;
        palette_out_index_q <= 13'd0;
        palette_hold_valid_q <= 1'b0;
        palette_hold_byte_q <= 8'd0;
        palette_tail_extra_q <= 1'b0;
        palette_zero_count_q <= 2'd0;
        palette_epb_pending_q <= 1'b0;
        palette_epb_byte_q <= 8'd0;
        palette_epb_last_q <= 1'b0;
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        m_axis_last <= 1'b0;
      end else if (pending_output_q && !PALETTE_MODE &&
                   (generated_out_state_q == GENERATED_OUT_IDLE)) begin
        pending_output_q <= 1'b0;
        generated_out_state_q <= GENERATED_OUT_PREAMBLE;
        generated_out_index_q <= 13'd0;
        generated_slice_cra_q <= 1'b0;
        generated_hold_valid_q <= 1'b0;
        generated_hold_byte_q <= 8'd0;
        generated_tail_extra_q <= 1'b0;
        generated_zero_count_q <= 2'd0;
        generated_epb_pending_q <= 1'b0;
        generated_epb_byte_q <= 8'd0;
        generated_epb_stream_last_q <= 1'b0;
        generated_epb_slice_last_q <= 1'b0;
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        m_axis_last <= 1'b0;
      end else if (m_axis_valid && m_axis_ready) begin
        if (index_q == stream_len_q) begin
          m_axis_valid <= 1'b0;
          m_axis_last  <= 1'b0;
          index_q      <= '0;
        end else begin
          m_axis_data <= stream_byte(index_q);
          m_axis_last <= (index_q == stream_len_q - 1'b1);
          index_q     <= index_q + 1'b1;
        end
      end
      if (PALETTE_MODE && (palette_out_state_q != PALETTE_OUT_IDLE) &&
          (!m_axis_valid || m_axis_ready)) begin
        if (palette_epb_pending_q) begin
          m_axis_valid <= 1'b1;
          m_axis_data <= palette_epb_byte_q;
          m_axis_last <= palette_epb_last_q;
          palette_epb_pending_q <= 1'b0;
          palette_zero_count_q <= next_zero_count(palette_zero_count_q, palette_epb_byte_q);
          if (palette_epb_last_q) begin
            palette_out_state_q <= PALETTE_OUT_IDLE;
            palette_epb_last_q <= 1'b0;
          end
        end else begin
          case (palette_out_state_q)
          PALETTE_OUT_PREAMBLE: begin
            if (palette_out_index_q < palette_direct_preamble_len()) begin
              if (palette_direct_preamble_is_slice_payload(palette_out_index_q)) begin
                emit_palette_raw_byte(palette_direct_preamble_byte(palette_out_index_q), 1'b0);
              end else begin
                m_axis_valid <= 1'b1;
                m_axis_data <= palette_direct_preamble_byte(palette_out_index_q);
                m_axis_last <= 1'b0;
                palette_zero_count_q <= 2'd0;
              end
              palette_out_index_q <= palette_out_index_q + 13'd1;
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
              palette_out_state_q <= PALETTE_OUT_CABAC;
            end
          end
          PALETTE_OUT_CABAC: begin
            if (cabac_stream_valid) begin
              if (palette_hold_valid_q) begin
                emit_palette_raw_byte(palette_hold_byte_q, 1'b0);
              end else begin
                m_axis_valid <= 1'b0;
                m_axis_last <= 1'b0;
              end
              palette_hold_valid_q <= 1'b1;
              palette_hold_byte_q <= cabac_stream_data;
              if (cabac_stream_last) begin
                palette_out_state_q <= PALETTE_OUT_TRAIL;
                palette_tail_extra_q <= (cabac_stream_bit_count[2:0] == 3'd0);
              end
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
            end
          end
          PALETTE_OUT_TRAIL: begin
            if (palette_tail_extra_q && palette_hold_valid_q) begin
              emit_palette_raw_byte(palette_hold_byte_q, 1'b0);
              palette_hold_valid_q <= 1'b0;
            end else if (palette_tail_extra_q) begin
              emit_palette_raw_byte(8'h80, 1'b1);
              palette_tail_extra_q <= 1'b0;
            end else begin
              emit_palette_raw_byte(palette_tail_byte(palette_hold_byte_q, cabac_stream_bit_count[2:0]), 1'b1);
              palette_hold_valid_q <= 1'b0;
            end
          end
          default: begin
            palette_out_state_q <= PALETTE_OUT_IDLE;
          end
          endcase
        end
      end
      if (pending_output_q && palette_stream_valid && palette_stream_ready && palette_stream_last) begin
        palette_done_q <= 1'b1;
      end
      if (!PALETTE_MODE && (generated_out_state_q != GENERATED_OUT_IDLE) &&
          (!m_axis_valid || m_axis_ready)) begin
        if (generated_epb_pending_q) begin
          m_axis_valid <= 1'b1;
          m_axis_data <= generated_epb_byte_q;
          m_axis_last <= generated_epb_stream_last_q;
          generated_epb_pending_q <= 1'b0;
          generated_zero_count_q <= next_zero_count(generated_zero_count_q, generated_epb_byte_q);
          if (generated_epb_stream_last_q) begin
            generated_out_state_q <= GENERATED_OUT_IDLE;
            generated_epb_stream_last_q <= 1'b0;
            generated_epb_slice_last_q <= 1'b0;
          end else if (generated_epb_slice_last_q) begin
            generated_out_state_q <= GENERATED_OUT_PREAMBLE;
            generated_out_index_q <= 13'd0;
            generated_slice_cra_q <= 1'b1;
            generated_epb_slice_last_q <= 1'b0;
          end
        end else begin
          case (generated_out_state_q)
          GENERATED_OUT_PREAMBLE: begin
            if (generated_out_index_q < generated_direct_preamble_len(generated_slice_cra_q)) begin
              if (generated_direct_preamble_is_slice_payload(generated_out_index_q, generated_slice_cra_q)) begin
                emit_generated_raw_byte(
                  generated_direct_preamble_byte(generated_out_index_q, generated_slice_cra_q),
                  1'b0,
                  1'b0
                );
              end else begin
                m_axis_valid <= 1'b1;
                m_axis_data <= generated_direct_preamble_byte(generated_out_index_q, generated_slice_cra_q);
                m_axis_last <= 1'b0;
                generated_zero_count_q <= 2'd0;
              end
              generated_out_index_q <= generated_out_index_q + 13'd1;
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
              cabac_start_q <= 1'b1;
              generated_out_state_q <= GENERATED_OUT_CABAC;
            end
          end
          GENERATED_OUT_CABAC: begin
            if (cabac_stream_valid) begin
              if (generated_hold_valid_q) begin
                emit_generated_raw_byte(generated_hold_byte_q, 1'b0, 1'b0);
              end else begin
                m_axis_valid <= 1'b0;
                m_axis_last <= 1'b0;
              end
              generated_hold_valid_q <= 1'b1;
              generated_hold_byte_q <= cabac_stream_data;
              if (cabac_stream_last) begin
                generated_out_state_q <= GENERATED_OUT_TRAIL;
                generated_tail_extra_q <= (cabac_stream_bit_count[2:0] == 3'd0);
              end
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
            end
          end
          GENERATED_OUT_TRAIL: begin
            if (generated_tail_extra_q && generated_hold_valid_q) begin
              emit_generated_raw_byte(generated_hold_byte_q, 1'b0, 1'b0);
              generated_hold_valid_q <= 1'b0;
            end else if (generated_tail_extra_q) begin
              emit_generated_raw_byte(8'h80, generated_stream_last_slice(), 1'b1);
              generated_tail_extra_q <= 1'b0;
            end else begin
              emit_generated_raw_byte(
                palette_tail_byte(generated_hold_byte_q, cabac_stream_bit_count[2:0]),
                generated_stream_last_slice(),
                1'b1
              );
              generated_hold_valid_q <= 1'b0;
            end
          end
          default: begin
            generated_out_state_q <= GENERATED_OUT_IDLE;
          end
          endcase
        end
      end
    end
  end

  task automatic emit_palette_raw_byte(input logic [7:0] raw_byte, input logic raw_last);
    begin
      if ((palette_zero_count_q >= 2'd2) && (raw_byte <= 8'h03)) begin
        m_axis_valid <= 1'b1;
        m_axis_data <= 8'h03;
        m_axis_last <= 1'b0;
        palette_epb_pending_q <= 1'b1;
        palette_epb_byte_q <= raw_byte;
        palette_epb_last_q <= raw_last;
        palette_zero_count_q <= 2'd0;
      end else begin
        m_axis_valid <= 1'b1;
        m_axis_data <= raw_byte;
        m_axis_last <= raw_last;
        palette_zero_count_q <= next_zero_count(palette_zero_count_q, raw_byte);
        if (raw_last) begin
          palette_out_state_q <= PALETTE_OUT_IDLE;
        end
      end
    end
  endtask

  task automatic emit_generated_raw_byte(
    input logic [7:0] raw_byte,
    input logic stream_last,
    input logic slice_last
  );
    begin
      if ((generated_zero_count_q >= 2'd2) && (raw_byte <= 8'h03)) begin
        m_axis_valid <= 1'b1;
        m_axis_data <= 8'h03;
        m_axis_last <= 1'b0;
        generated_epb_pending_q <= 1'b1;
        generated_epb_byte_q <= raw_byte;
        generated_epb_stream_last_q <= stream_last;
        generated_epb_slice_last_q <= slice_last;
        generated_zero_count_q <= 2'd0;
      end else begin
        m_axis_valid <= 1'b1;
        m_axis_data <= raw_byte;
        m_axis_last <= stream_last;
        generated_zero_count_q <= next_zero_count(generated_zero_count_q, raw_byte);
        if (stream_last) begin
          generated_out_state_q <= GENERATED_OUT_IDLE;
        end else if (slice_last) begin
          generated_out_state_q <= GENERATED_OUT_PREAMBLE;
          generated_out_index_q <= 13'd0;
          generated_slice_cra_q <= 1'b1;
        end
      end
    end
  endtask

  function automatic logic [1:0] next_zero_count(
    input logic [1:0] zero_count,
    input logic [7:0] byte_value
  );
    begin
      if (byte_value == 8'h00) begin
        next_zero_count = zero_count == 2'd2 ? 2'd2 : zero_count + 2'd1;
      end else begin
        next_zero_count = 2'd0;
      end
    end
  endfunction

  function automatic logic [12:0] palette_direct_preamble_len();
    begin
      palette_direct_preamble_len =
        parameter_set_len() + color_filler_nal_len() + NAL_OVERHEAD_LEN + 13'd3;
    end
  endfunction

  function automatic logic [7:0] palette_direct_preamble_byte(input logic [12:0] index);
    logic [12:0] slice_base;
    logic [12:0] slice_index;
    begin
      slice_base = parameter_set_len() + color_filler_nal_len();
      if (index < slice_base) begin
        palette_direct_preamble_byte = stream_byte(index);
      end else if (index < slice_base + NAL_OVERHEAD_LEN) begin
        slice_index = index - slice_base;
        if (slice_index < 13'd4) begin
          palette_direct_preamble_byte = start_code_byte(slice_index[1:0]);
        end else begin
          palette_direct_preamble_byte = nal_header_byte(3'd2, slice_index[0], 1'b0);
        end
      end else begin
        palette_direct_preamble_byte =
          slice_payload_prefix_byte(index - (slice_base + NAL_OVERHEAD_LEN), 1'b0);
      end
    end
  endfunction

  function automatic logic palette_direct_preamble_is_slice_payload(input logic [12:0] index);
    begin
      palette_direct_preamble_is_slice_payload =
        index >= (parameter_set_len() + color_filler_nal_len() + NAL_OVERHEAD_LEN);
    end
  endfunction

  function automatic logic [12:0] generated_direct_preamble_len(input logic cra_picture);
    begin
      generated_direct_preamble_len =
        (cra_picture ? 13'd0 : parameter_set_len() + color_filler_nal_len())
        + NAL_OVERHEAD_LEN + 13'd3;
    end
  endfunction

  function automatic logic [7:0] generated_direct_preamble_byte(
    input logic [12:0] index,
    input logic        cra_picture
  );
    logic [12:0] slice_prefix_base;
    logic [12:0] slice_index;
    begin
      if (!cra_picture && (index < parameter_set_len() + color_filler_nal_len())) begin
        generated_direct_preamble_byte = stream_byte(index);
      end else begin
        slice_prefix_base = cra_picture ? 13'd0 : parameter_set_len() + color_filler_nal_len();
        slice_index = index - slice_prefix_base;
        if (slice_index < 13'd4) begin
          generated_direct_preamble_byte = start_code_byte(slice_index[1:0]);
        end else if (slice_index < 13'd6) begin
          generated_direct_preamble_byte = nal_header_byte(3'd2, slice_index[0], cra_picture);
        end else begin
          generated_direct_preamble_byte = slice_payload_prefix_byte(slice_index - 13'd6, cra_picture);
        end
      end
    end
  endfunction

  function automatic logic generated_direct_preamble_is_slice_payload(
    input logic [12:0] index,
    input logic        cra_picture
  );
    begin
      generated_direct_preamble_is_slice_payload =
        index >= ((cra_picture ? 13'd0 : parameter_set_len() + color_filler_nal_len()) + NAL_OVERHEAD_LEN);
    end
  endfunction

  function automatic logic generated_stream_last_slice();
    begin
      generated_stream_last_slice = (frame_count != 2'd2) || generated_slice_cra_q;
    end
  endfunction

  function automatic logic [7:0] palette_tail_byte(
    input logic [7:0] last_cabac_byte,
    input logic [2:0] valid_bits
  );
    logic [7:0] keep_mask;
    begin
      case (valid_bits)
        3'd1: keep_mask = 8'b1000_0000;
        3'd2: keep_mask = 8'b1100_0000;
        3'd3: keep_mask = 8'b1110_0000;
        3'd4: keep_mask = 8'b1111_0000;
        3'd5: keep_mask = 8'b1111_1000;
        3'd6: keep_mask = 8'b1111_1100;
        3'd7: keep_mask = 8'b1111_1110;
        default: keep_mask = 8'b0000_0000;
      endcase
      palette_tail_byte = (last_cabac_byte & keep_mask) | (8'h80 >> valid_bits);
    end
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] input_len(input logic [1:0] frames);
    case (frames)
      2'd2: input_len = frame_samples() * 2;
      default: input_len = frame_samples();
    endcase
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] luma_samples();
    begin
      luma_samples = visible_width * visible_height;
    end
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] chroma_plane_samples();
    begin
      chroma_plane_samples = (visible_width / chroma_subsample_x()) *
                             (visible_height / chroma_subsample_y());
    end
  endfunction

  function automatic logic [1:0] chroma_subsample_x();
    begin
      case (CHROMA_FORMAT_IDC)
        1, 2: chroma_subsample_x = 2'd2;
        default: chroma_subsample_x = 2'd1;
      endcase
    end
  endfunction

  function automatic logic [1:0] chroma_subsample_y();
    begin
      case (CHROMA_FORMAT_IDC)
        1: chroma_subsample_y = 2'd2;
        default: chroma_subsample_y = 2'd1;
      endcase
    end
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] frame_samples();
    begin
      frame_samples = luma_samples() + (chroma_plane_samples() << 1);
    end
  endfunction

  function automatic logic [1:0] palette_plane_for_input(
    input logic [INPUT_COUNT_BITS - 1:0] sample_index
  );
    begin
      if (sample_index < luma_samples()) begin
        palette_plane_for_input = 2'd0;
      end else if (sample_index < v_sample_index()) begin
        palette_plane_for_input = 2'd1;
      end else begin
        palette_plane_for_input = 2'd2;
      end
    end
  endfunction

  function automatic logic [INPUT_COUNT_BITS - 1:0] v_sample_index();
    begin
      v_sample_index = luma_samples() + chroma_plane_samples();
    end
  endfunction

  function automatic logic is_residual_luma_sample(input logic [INPUT_COUNT_BITS - 1:0] sample_index);
    begin
      is_residual_luma_sample = (sample_index < luma_samples()) &&
                                ((sample_index % visible_width) < TOY_RESIDUAL_CB_SIZE) &&
                                ((sample_index / visible_width) < TOY_RESIDUAL_CB_SIZE);
    end
  endfunction

  function automatic logic [3:0] residual_luma_sample_index(input logic [INPUT_COUNT_BITS - 1:0] sample_index);
    logic [INPUT_COUNT_BITS - 1:0] index;
    begin
      index = ((sample_index / visible_width) * TOY_RESIDUAL_CB_SIZE) + (sample_index % visible_width);
      residual_luma_sample_index = index[3:0];
    end
  endfunction

  function automatic logic has_second_residual_luma_block();
    begin
      has_second_residual_luma_block = (visible_width >= (TOY_RESIDUAL_CB_SIZE * 2)) ||
                                       (visible_height >= (TOY_RESIDUAL_CB_SIZE * 2));
    end
  endfunction

  function automatic logic [15:0] second_residual_origin_x();
    begin
      second_residual_origin_x = (visible_width >= (TOY_RESIDUAL_CB_SIZE * 2)) ? TOY_RESIDUAL_CB_SIZE : 16'd0;
    end
  endfunction

  function automatic logic [15:0] second_residual_origin_y();
    begin
      second_residual_origin_y = (visible_width >= (TOY_RESIDUAL_CB_SIZE * 2)) ? 16'd0 :
                                 ((visible_height >= (TOY_RESIDUAL_CB_SIZE * 2)) ? TOY_RESIDUAL_CB_SIZE : 16'd0);
    end
  endfunction

  function automatic logic is_second_residual_luma_sample(input logic [INPUT_COUNT_BITS - 1:0] sample_index);
    logic [INPUT_COUNT_BITS - 1:0] x;
    logic [INPUT_COUNT_BITS - 1:0] y;
    begin
      x = sample_index % visible_width;
      y = sample_index / visible_width;
      is_second_residual_luma_sample = (sample_index < luma_samples()) &&
                                       has_second_residual_luma_block() &&
                                       (x >= second_residual_origin_x()) &&
                                       (x < second_residual_origin_x() + TOY_RESIDUAL_CB_SIZE) &&
                                       (y >= second_residual_origin_y()) &&
                                       (y < second_residual_origin_y() + TOY_RESIDUAL_CB_SIZE);
    end
  endfunction

  function automatic logic [3:0] second_residual_luma_sample_index(input logic [INPUT_COUNT_BITS - 1:0] sample_index);
    logic [INPUT_COUNT_BITS - 1:0] x;
    logic [INPUT_COUNT_BITS - 1:0] y;
    logic [INPUT_COUNT_BITS - 1:0] index;
    begin
      x = sample_index % visible_width;
      y = sample_index / visible_width;
      index = ((y - second_residual_origin_y()) * TOY_RESIDUAL_CB_SIZE) +
              (x - second_residual_origin_x());
      second_residual_luma_sample_index = index[3:0];
    end
  endfunction

  function automatic logic [12:0] stream_len(input logic [1:0] frames);
    case (frames)
      2'd2: stream_len = parameter_set_len() + color_filler_nal_len() + slice_nal_len() + slice_cra_nal_len();
      default: stream_len = parameter_set_len() + color_filler_nal_len() + slice_nal_len();
    endcase
  endfunction

  function automatic logic [12:0] stream_len_from_slice_payloads(input logic [1:0] frames);
    logic [12:0] first_slice_len;
    logic [12:0] second_slice_len;
    begin
      first_slice_len = slice_payload_escaped_len_calc(1'b0);
      second_slice_len = slice_payload_escaped_len_calc(1'b1);
      case (frames)
        2'd2: stream_len_from_slice_payloads =
          parameter_set_len() + color_filler_nal_len()
          + NAL_OVERHEAD_LEN + first_slice_len
          + NAL_OVERHEAD_LEN + second_slice_len;
        default: stream_len_from_slice_payloads =
          parameter_set_len() + color_filler_nal_len()
          + NAL_OVERHEAD_LEN + first_slice_len;
      endcase
    end
  endfunction

  function automatic logic [12:0] sps_nal_len();
    begin
      sps_nal_len = NAL_OVERHEAD_LEN + sps_payload_len();
    end
  endfunction

  function automatic logic [12:0] pps_nal_len();
    begin
      pps_nal_len = NAL_OVERHEAD_LEN + pps_payload_len();
    end
  endfunction

  function automatic logic [12:0] parameter_set_len();
    begin
      parameter_set_len = sps_nal_len() + pps_nal_len();
    end
  endfunction

  function automatic logic [12:0] slice_payload_len();
    logic [12:0]  bit_len;
    begin
      bit_len = 13'd24 + slice_body_bit_len() + 13'd1;
      slice_payload_len = (bit_len + 13'd7) >> 3;
    end
  endfunction

  function automatic logic [12:0] slice_nal_len();
    begin
      slice_nal_len = NAL_OVERHEAD_LEN + slice_payload_ebsp_len_q;
    end
  endfunction

  function automatic logic [12:0] slice_cra_nal_len();
    begin
      slice_cra_nal_len = NAL_OVERHEAD_LEN + slice_payload_ebsp_cra_len_q;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem();
    begin
      quant_luma_rem = quant_luma_rem_q;
    end
  endfunction

  function automatic logic [4:0] quant_chroma_rem();
    begin
      quant_chroma_rem = quant_chroma_rem_q;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_1();
    begin
      quant_luma_rem_1 = quant_luma_rem_1_q;
    end
  endfunction

  function automatic logic [4:0] quant_chroma_rem_from_samples(
    input logic [SAMPLE_BITS - 1:0] u,
    input logic [SAMPLE_BITS - 1:0] v
  );
    begin
      quant_chroma_rem_from_samples = (sample_to_8bit(u) == 8'd0 && sample_to_8bit(v) == 8'd0) ? 5'd6 : 5'd0;
    end
  endfunction

  function automatic logic [7:0] sample_to_8bit(input logic [SAMPLE_BITS - 1:0] sample);
    begin
      if (SAMPLE_BITS <= 8) begin
        sample_to_8bit = sample[7:0];
      end else begin
        sample_to_8bit = sample >> (SAMPLE_BITS - 8);
      end
    end
  endfunction

  function automatic logic [7:0] color_filler_count();
    begin
      color_filler_count = (sample_to_8bit(sampled_y) + sample_to_8bit(sampled_u) + sample_to_8bit(sampled_v)) & 8'h0f;
    end
  endfunction

  function automatic logic [7:0] color_filler_payload_len();
    begin
      color_filler_payload_len = color_filler_count() + 8'd1;
    end
  endfunction

  function automatic logic [12:0] color_filler_nal_len();
    begin
      color_filler_nal_len = NAL_OVERHEAD_LEN + color_filler_payload_len();
    end
  endfunction

  function automatic logic [7:0] stream_byte(input logic [12:0] index);
    logic second_picture;
    logic [12:0] slice_base;
    logic [12:0] slice_index;

    begin
      if (index < sps_nal_len()) begin
        stream_byte = nal_byte(3'd0, index, 1'b0);
      end else if (index < parameter_set_len()) begin
        stream_byte = nal_byte(3'd1, index - sps_nal_len(), 1'b0);
      end else if (index < parameter_set_len() + color_filler_nal_len()) begin
        stream_byte = nal_byte(3'd3, index - parameter_set_len(), 1'b0);
      end else begin
        slice_base = parameter_set_len() + color_filler_nal_len();
        second_picture = (index >= slice_base + slice_nal_len());
        slice_index = second_picture
          ? (index - (slice_base + slice_nal_len()))
          : (index - slice_base);
        stream_byte = nal_byte(3'd2, slice_index, second_picture);
      end
    end
  endfunction

  function automatic logic [7:0] nal_byte(
    input logic [2:0] nal_kind,
    input logic [12:0] nal_index,
    input logic       cra_picture
  );
    begin
      if (nal_index < 7'd4) begin
        nal_byte = start_code_byte(nal_index[1:0]);
      end else if (nal_index < 7'd6) begin
        nal_byte = nal_header_byte(nal_kind, nal_index[0], cra_picture);
      end else if (nal_kind != 3'd0 && nal_kind != 3'd1 && nal_kind != 3'd3) begin
        nal_byte = slice_payload_escaped_cached_byte(nal_index - 7'd6, cra_picture);
      end else begin
        nal_byte = payload_byte(nal_kind, nal_index - 7'd6, cra_picture);
      end
    end
  endfunction

  function automatic logic [7:0] start_code_byte(input logic [1:0] index);
    case (index)
      2'd3: start_code_byte = 8'h01;
      default: start_code_byte = 8'h00;
    endcase
  endfunction

  function automatic logic [7:0] nal_header_byte(
    input logic [2:0] nal_kind,
    input logic       byte_index,
    input logic       cra_picture
  );
    logic [15:0] header;

    begin
      header = nal_header_bits(6'd0, nal_unit_type(nal_kind, cra_picture), 3'd0);
      nal_header_byte = byte_index ? header[7:0] : header[15:8];
    end
  endfunction

  function automatic logic [4:0] nal_unit_type(
    input logic [2:0] nal_kind,
    input logic       cra_picture
  );
    begin
      case (nal_kind)
        3'd0: nal_unit_type = 5'd15; // SPS.
        3'd1: nal_unit_type = 5'd16; // PPS.
        3'd3: nal_unit_type = 5'd25; // Filler data.
        default: nal_unit_type = cra_picture ? 5'd9 : 5'd8;
      endcase
    end
  endfunction

  function automatic logic [15:0] nal_header_bits(
    input logic [5:0] layer_id,
    input logic [4:0] nal_type,
    input logic [2:0] temporal_id
  );
    begin
      nal_header_bits = {
        1'b0,              // forbidden_zero_bit
        1'b0,              // nuh_reserved_zero_bit
        layer_id,          // nuh_layer_id
        nal_type,          // nal_unit_type
        temporal_id + 3'd1 // nuh_temporal_id_plus1
      };
    end
  endfunction

  function automatic logic [7:0] payload_byte(
    input logic [2:0] nal_kind,
    input logic [12:0] payload_index,
    input logic       cra_picture
  );
    begin
      case (nal_kind)
        3'd0: payload_byte = sps_payload_byte(payload_index);
        3'd1: payload_byte = pps_payload_byte(payload_index);
        3'd3: payload_byte = color_filler_payload_byte(payload_index);
        default: payload_byte = slice_payload_byte(payload_index, cra_picture);
      endcase
    end
  endfunction

  function automatic logic [12:0] slice_payload_escaped_len_calc(input logic cra_picture);
    logic [12:0] raw_index;
    logic [12:0] raw_len;
    logic [12:0] escaped_len;
    logic [1:0] zero_count;
    logic [7:0] raw_byte;
    begin
      raw_len = slice_payload_len();
      escaped_len = 13'd0;
      zero_count = 2'd0;
      for (raw_index = 13'd0; raw_index < raw_len; raw_index = raw_index + 13'd1) begin
        raw_byte = slice_payload_byte(raw_index, cra_picture);
        if (zero_count >= 2'd2 && raw_byte <= 8'h03) begin
          escaped_len = escaped_len + 13'd1;
          zero_count = 2'd0;
        end
        escaped_len = escaped_len + 13'd1;
        if (raw_byte == 8'h00) begin
          if (zero_count < 2'd2) begin
            zero_count = zero_count + 2'd1;
          end
        end else begin
          zero_count = 2'd0;
        end
      end
      slice_payload_escaped_len_calc = escaped_len;
    end
  endfunction

  function automatic logic [7:0] slice_payload_escaped_cached_byte(
    input logic [12:0] escaped_index,
    input logic        cra_picture
  );
    logic [12:0] raw_index;
    logic [12:0] out_index;
    logic [1:0] zero_count;
    logic [7:0] raw_byte;
    logic found;
    begin
      out_index = 13'd0;
      zero_count = 2'd0;
      found = 1'b0;
      slice_payload_escaped_cached_byte = 8'h00;

      for (raw_index = 13'd0; raw_index < slice_payload_len(); raw_index = raw_index + 13'd1) begin
        raw_byte = slice_payload_byte(raw_index, cra_picture);
        if (!found && zero_count >= 2'd2 && raw_byte <= 8'h03) begin
          if (out_index == escaped_index) begin
            slice_payload_escaped_cached_byte = 8'h03;
            found = 1'b1;
          end
          out_index = out_index + 13'd1;
          zero_count = 2'd0;
        end

        if (!found && out_index == escaped_index) begin
          slice_payload_escaped_cached_byte = raw_byte;
          found = 1'b1;
        end
        out_index = out_index + 13'd1;

        if (raw_byte == 8'h00) begin
          if (zero_count < 2'd2) begin
            zero_count = zero_count + 2'd1;
          end
        end else begin
          zero_count = 2'd0;
        end
      end
    end
  endfunction

  function automatic logic [7:0] color_filler_payload_byte(input logic [12:0] index);
    begin
      if (index < color_filler_count()) begin
        color_filler_payload_byte = 8'hff;
      end else if (index == color_filler_count()) begin
        color_filler_payload_byte = 8'h80;
      end else begin
        color_filler_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] sps_payload_byte(input logic [12:0] index);
    logic [264:0] payload;

    begin
      payload = sps_payload_state();
      if (index < sps_payload_len()) begin
        sps_payload_byte = payload[255:0] >> (((sps_payload_len() - 1) - index) * 8);
      end else begin
        sps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] pps_payload_byte(input logic [12:0] index);
    logic [264:0] payload;

    begin
      payload = pps_payload_state();
      if (index < pps_payload_len()) begin
        pps_payload_byte = payload[255:0] >> (((pps_payload_len() - 1) - index) * 8);
      end else begin
        pps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [8:0] sps_payload_len();
    logic [264:0] payload;

    begin
      payload = sps_payload_state();
      sps_payload_len = payload[264:256] >> 3;
    end
  endfunction

  function automatic logic [8:0] pps_payload_len();
    logic [264:0] payload;

    begin
      payload = pps_payload_state();
      pps_payload_len = payload[264:256] >> 3;
    end
  endfunction

  function automatic logic [264:0] append_u(
    input logic [264:0] state,
    input logic [31:0]  value,
    input int unsigned  width
  );
    logic [8:0] len;
    logic [255:0] bits;
    logic [63:0] mask;

    begin
      len = state[264:256];
      bits = state[255:0];
      if (width == 0) begin
        append_u = state;
      end else begin
        mask = (64'd1 << width) - 64'd1;
        bits = (bits << width) | (value & mask);
        len = len + width[8:0];
        append_u = {len, bits};
      end
    end
  endfunction

  function automatic logic [264:0] append_flag(input logic [264:0] state, input logic value);
    begin
      append_flag = append_u(state, {31'd0, value}, 1);
    end
  endfunction

  function automatic logic [264:0] append_ue(input logic [264:0] state, input logic [31:0] value);
    begin
      append_ue = append_exp_golomb_code(state, value + 32'd1);
    end
  endfunction

  function automatic logic [264:0] append_exp_golomb_code(
    input logic [264:0] state,
    input logic [31:0] code_num
  );
    int unsigned prefix;

    begin
      prefix = 0;
      while ((code_num >> prefix) > 1) begin
        prefix = prefix + 1;
      end
      state = append_u(state, 32'd0, prefix);
      append_exp_golomb_code = append_u(state, code_num, prefix + 1);
    end
  endfunction

  function automatic logic [264:0] append_se(input logic [264:0] state, input int signed value);
    logic [31:0] mapped;

    begin
      if (value > 0) begin
        mapped = value * 2;
      end else begin
        mapped = (-value * 2) + 1;
      end
      append_se = append_exp_golomb_code(state, mapped);
    end
  endfunction

  function automatic logic [264:0] append_trailing_bits(input logic [264:0] state);
    begin
      state = append_flag(state, 1'b1);
      while (state[258:256] != 3'd0) begin
        state = append_flag(state, 1'b0);
      end
      append_trailing_bits = state;
    end
  endfunction

  function automatic logic [15:0] coded_dimension(input logic [15:0] value);
    begin
      if (value <= 16'd8) begin
        coded_dimension = 16'd8;
      end else if (value <= 16'd16) begin
        coded_dimension = 16'd16;
      end else if (value <= 16'd32) begin
        coded_dimension = 16'd32;
      end else begin
        coded_dimension = 16'd64;
      end
    end
  endfunction

  function automatic logic [15:0] coded_width();
    begin
      coded_width = coding_tree_coded_width;
    end
  endfunction

  function automatic logic palette_cu_origin_is_visible(input logic [7:0] index);
    logic [31:0] pos;
    begin
      pos = palette_coding_order_position(index);
      palette_cu_origin_is_visible =
        (pos[31:16] < visible_width) && (pos[15:0] < visible_height);
    end
  endfunction

  function automatic logic [31:0] palette_coding_order_position(input logic [7:0] index);
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    logic [7:0]  index_in_32;
    logic [7:0]  index_in_16;
    begin
      origin_x = 16'd0;
      origin_y = 16'd0;
      if (coding_tree_coded_width == 16'd64 && coding_tree_coded_height == 16'd64) begin
        origin_x = index[4] ? 16'd32 : 16'd0;
        origin_y = index[5] ? 16'd32 : 16'd0;
        index_in_32 = {4'd0, index[3:0]};
      end else begin
        index_in_32 = index;
      end

      if (coding_tree_coded_width >= 16'd32 && coding_tree_coded_height >= 16'd32) begin
        origin_x = origin_x + (index_in_32[2] ? 16'd16 : 16'd0);
        origin_y = origin_y + (index_in_32[3] ? 16'd16 : 16'd0);
        index_in_16 = {6'd0, index_in_32[1:0]};
      end else begin
        index_in_16 = index_in_32;
      end

      if (coding_tree_coded_width >= 16'd16 && coding_tree_coded_height >= 16'd16) begin
        origin_x = origin_x + (index_in_16[0] ? PALETTE_CU_SIZE : 16'd0);
        origin_y = origin_y + (index_in_16[1] ? PALETTE_CU_SIZE : 16'd0);
      end else begin
        origin_x = index_in_16[2:0] * PALETTE_CU_SIZE;
        origin_y = index_in_16[5:3] * PALETTE_CU_SIZE;
      end

      palette_coding_order_position = {origin_x, origin_y};
    end
  endfunction

  function automatic logic [15:0] coded_height();
    begin
      coded_height = coding_tree_coded_height;
    end
  endfunction

  function automatic logic [264:0] sps_payload_state();
    logic [264:0] state;

    begin
      state = '0;
      state = append_u(state, 0, 4);
      state = append_u(state, 0, 4);
      state = append_u(state, 0, 3);
      state = append_u(state, CHROMA_FORMAT_IDC[1:0], 2);
      state = append_u(state, 1, 2);
      state = append_flag(state, 1'b1);
      state = append_u(state, (PALETTE_MODE || (CHROMA_FORMAT_IDC == 3)) ? 0 : 1, 7);
      state = append_flag(state, 1'b0);
      state = append_u(state, 0, 8);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      repeat (5) state = append_flag(state, 1'b0);
      state = append_u(state, 0, 8);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_ue(state, coded_width());
      state = append_ue(state, coded_height());
      state = append_flag(state, 1'b1);
      state = append_ue(state, 0);
      state = append_ue(state, crop_right_offset());
      state = append_ue(state, 0);
      state = append_ue(state, crop_bottom_offset());
      state = append_flag(state, 1'b0);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_u(state, 4, 4);
      state = append_flag(state, 1'b0);
      state = append_u(state, 0, 2);
      state = append_u(state, 0, 2);
      state = append_ue(state, 0);
      state = append_ue(state, 0);
      state = append_ue(state, 0);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 1);
      state = append_ue(state, 3);
      state = append_ue(state, 2);
      state = append_ue(state, 2);
      state = append_flag(state, !((CHROMA_FORMAT_IDC == 3) && PALETTE_MODE));
      if (!((CHROMA_FORMAT_IDC == 3) && PALETTE_MODE)) begin
        state = append_ue(state, 1);
        state = append_ue(state, 3);
        state = append_ue(state, 3);
        state = append_ue(state, 2);
      end
      state = append_ue(state, 1);
      state = append_ue(state, 3);
      state = append_ue(state, 3);
      state = append_ue(state, 3);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_se(state, -9);
      state = append_ue(state, 2);
      state = append_ue(state, 9);
      state = append_ue(state, 5);
      state = append_ue(state, 4);
      state = append_ue(state, 1);
      state = append_ue(state, 11);
      state = append_ue(state, 12);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 1);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_ue(state, 0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      if (CHROMA_FORMAT_IDC == 1) begin
        state = append_flag(state, 1'b1);
        state = append_flag(state, 1'b0);
      end
      state = append_flag(state, PALETTE_MODE);
      if (PALETTE_MODE) begin
        state = append_ue(state, 0);
      end
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      sps_payload_state = append_trailing_bits(state);
    end
  endfunction

  function automatic logic [15:0] crop_right_offset();
    begin
      crop_right_offset = (coded_width() - visible_width) / chroma_subsample_x();
    end
  endfunction

  function automatic logic [15:0] crop_bottom_offset();
    begin
      crop_bottom_offset = (coded_height() - visible_height) / chroma_subsample_y();
    end
  endfunction

  function automatic logic [264:0] pps_payload_state();
    logic [264:0] state;

    begin
      state = '0;
      state = append_u(state, 0, 6);
      state = append_u(state, 0, 4);
      state = append_flag(state, 1'b0);
      state = append_ue(state, coded_width());
      state = append_ue(state, coded_height());
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_ue(state, 3);
      state = append_ue(state, 3);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_se(state, 6);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_se(state, 0);
      state = append_se(state, 0);
      state = append_flag(state, 1'b1);
      state = append_se(state, -1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b1);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_se(state, -2);
      state = append_se(state, -5);
      state = append_se(state, -2);
      state = append_se(state, -5);
      state = append_se(state, -2);
      state = append_se(state, -5);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      state = append_flag(state, 1'b0);
      pps_payload_state = append_trailing_bits(state);
    end
  endfunction

  function automatic logic [7:0] slice_payload_byte(
    input logic [12:0] index,
    input logic       cra_picture
  );
    logic [12:0] body_byte_index;
    logic [12:0] body_bit_index;
    logic [12:0] body_len;
    logic [12:0] indexed_bit;
    logic [7:0] out_byte;
    integer bit_idx;
    begin
      if (index < 13'd3) begin
        slice_payload_byte = slice_payload_prefix_byte(index, cra_picture);
      end else begin
        body_byte_index = index - 13'd3;
        body_bit_index = body_byte_index << 3;
        body_len = slice_body_bit_len();
        out_byte = 8'd0;
        for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
          indexed_bit = body_bit_index + bit_idx[12:0];
          out_byte = out_byte << 1;
          if (indexed_bit < body_len) begin
            out_byte[0] = slice_body_bit(indexed_bit);
          end else if (indexed_bit == body_len) begin
            out_byte[0] = 1'b1;
          end
        end
        slice_payload_byte = out_byte;
      end
    end
  endfunction

  function automatic logic [7:0] slice_payload_prefix_byte(
    input logic [12:0] index,
    input logic        cra_picture
  );
    logic [23:0] prefix;
    begin
      prefix = cra_picture
        ? {slice_header_bits(cra_picture), 1'b1, 1'b1, 3'b000}
        : {slice_header_bits(cra_picture), 1'b1, 4'b0000};
      case (index)
        13'd0: slice_payload_prefix_byte = prefix[23:16];
        13'd1: slice_payload_prefix_byte = prefix[15:8];
        default: slice_payload_prefix_byte = prefix[7:0];
      endcase
    end
  endfunction

  function automatic logic [12:0] slice_body_bit_len();
    begin
      slice_body_bit_len = 13'd0;
    end
  endfunction

  function automatic logic slice_body_bit(input logic [12:0] bit_index);
    begin
      slice_body_bit = 1'b0;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_for_tu(input logic [12:0] tu);
    begin
      quant_luma_rem_for_tu = quant_luma_rem_from_sample(forward_luma_dc_sample_for_tu(tu));
    end
  endfunction

  function automatic logic [7:0] quant_luma_ac0_for_tu(input logic [12:0] tu);
    logic [7:0] dc;
    begin
      dc = forward_luma_dc_sample_for_tu(tu);
      quant_luma_ac0_for_tu = quant_ac_token_for_samples(luma_sample_for_tu(tu, 4'd1), dc);
    end
  endfunction

  function automatic logic [7:0] forward_luma_dc_sample_for_tu(input logic [12:0] tu);
    logic [12:0] sum;
    integer i;
    begin
      sum = 13'd0;
      for (i = 0; i < 16; i = i + 1) begin
        sum = sum + {5'd0, luma_sample_for_tu(tu, i[3:0])};
      end
      forward_luma_dc_sample_for_tu = (sum + 13'd8) >> 4;
    end
  endfunction

  function automatic logic [7:0] luma_sample_for_tu(input logic [12:0] tu, input logic [3:0] sample_index);
    logic [15:0] tus_per_row;
    logic [15:0] origin_x;
    logic [15:0] origin_y;
    logic [15:0] x;
    logic [15:0] y;
    logic [INPUT_COUNT_BITS - 1:0] linear_index;
    logic [SAMPLE_BITS - 1:0] raw;
    begin
      tus_per_row = (visible_width + 16'd3) >> 2;
      origin_x = (tu % tus_per_row) << 2;
      origin_y = (tu / tus_per_row) << 2;
      x = origin_x + {12'd0, sample_index[1:0]};
      y = origin_y + {12'd0, sample_index[3:2]};
      if ((x < visible_width) && (y < visible_height)) begin
        linear_index = y * visible_width + x;
        raw = luma_frame_q[(MAX_LUMA_SAMPLES - 1 - linear_index) * SAMPLE_BITS +: SAMPLE_BITS];
        luma_sample_for_tu = sample_to_8bit(raw);
      end else begin
        luma_sample_for_tu = 8'd0;
      end
    end
  endfunction

  function automatic logic [7:0] quant_ac_token_for_samples(input logic [7:0] sample, input logic [7:0] dc);
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
      quant_ac_token_for_samples = 8'h40 | { 2'b00, negative, magnitude };
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_from_sample(input logic [7:0] sample);
    begin
      if (sample >= 8'd111) quant_luma_rem_from_sample = 5'd0;
      else if (sample >= 8'd104) quant_luma_rem_from_sample = 5'd1;
      else if (sample >= 8'd97) quant_luma_rem_from_sample = 5'd2;
      else if (sample >= 8'd90) quant_luma_rem_from_sample = 5'd3;
      else if (sample >= 8'd82) quant_luma_rem_from_sample = 5'd4;
      else if (sample >= 8'd75) quant_luma_rem_from_sample = 5'd5;
      else if (sample >= 8'd68) quant_luma_rem_from_sample = 5'd6;
      else if (sample >= 8'd61) quant_luma_rem_from_sample = 5'd7;
      else if (sample >= 8'd54) quant_luma_rem_from_sample = 5'd8;
      else if (sample >= 8'd46) quant_luma_rem_from_sample = 5'd9;
      else if (sample >= 8'd40) quant_luma_rem_from_sample = 5'd10;
      else if (sample >= 8'd33) quant_luma_rem_from_sample = 5'd11;
      else if (sample >= 8'd25) quant_luma_rem_from_sample = 5'd12;
      else if (sample >= 8'd18) quant_luma_rem_from_sample = 5'd13;
      else if (sample >= 8'd11) quant_luma_rem_from_sample = 5'd14;
      else if (sample >= 8'd4) quant_luma_rem_from_sample = 5'd15;
      else quant_luma_rem_from_sample = 5'd16;
    end
  endfunction

  function automatic logic [18:0] slice_header_bits(input logic cra_picture);
    logic [7:0] poc_lsb;

    begin
      poc_lsb = cra_picture ? 8'd1 : 8'd0;
      slice_header_bits = {
        1'b1,    // sh_picture_header_in_slice_header_flag
        1'b1,    // ph_gdr_or_irap_pic_flag
        1'b0,    // ph_non_ref_pic_flag
        1'b0,    // ph_gdr_pic_flag
        1'b0,    // ph_inter_slice_allowed_flag
        1'b1,    // ph_pic_parameter_set_id ue(v) = 0
        poc_lsb, // ph_pic_order_cnt_lsb
        1'b0,    // ph_partition_constraints_override_flag
        1'b0,    // ph_joint_cbcr_sign_flag
        1'b0,    // sh_no_output_of_prior_pics_flag
        1'b1,    // sh_qp_delta se(v) = 0
        1'b1     // sh_dep_quant_used_flag
      };
    end
  endfunction

endmodule
