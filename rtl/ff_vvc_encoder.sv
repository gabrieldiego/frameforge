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
  localparam int SLICE_PAYLOAD_BUFFER_BITS = 4096;
  localparam int PALETTE_CU_SIZE = 8;
  localparam int MAX_CTU_PALETTE_SYMBOLS =
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE) *
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE);
  localparam bit PALETTE_MODE = (CHROMA_FORMAT_IDC == 3);

  logic [12:0] index_q;
  logic [12:0] stream_len_q;
  logic [INPUT_COUNT_BITS - 1:0] input_count_q;
  logic [INPUT_COUNT_BITS - 1:0] input_len_q;
  logic       input_active_q;
  logic [(SAMPLE_BITS * MAX_LUMA_SAMPLES) - 1:0] luma_frame_q;
  logic [(SAMPLE_BITS * MAX_CHROMA_PLANE_SAMPLES) - 1:0] cb_frame_q;
  logic [(SAMPLE_BITS * MAX_CHROMA_PLANE_SAMPLES) - 1:0] cr_frame_q;
  logic [(SAMPLE_BITS * TOY_RESIDUAL_LUMA_SAMPLES) - 1:0] luma_samples_q;
  logic [(SAMPLE_BITS * TOY_RESIDUAL_LUMA_SAMPLES) - 1:0] luma_samples_1_q;
  logic [(SAMPLE_BITS * 16) - 1:0] cb_samples_q;
  logic [(SAMPLE_BITS * 16) - 1:0] cr_samples_q;
  logic [4:0] quant_luma_rem_q;
  logic [4:0] quant_luma_rem_1_q;
  logic [4:0] quant_chroma_rem_q;
  logic [119:0] quant_luma_ac_tokens_q;
  logic [119:0] quant_luma_ac_tokens_1_q;
  logic [4:0] residual_quant_luma_rem;
  logic [4:0] residual_quant_luma_rem_1;
  logic [119:0] residual_quant_luma_ac_tokens;
  logic [119:0] residual_quant_luma_ac_tokens_1;
  logic [7:0] residual_recon_luma_sample;
  logic [7:0] residual_recon_luma_sample_1;
  logic [15:0] coding_tree_coded_width;
  logic [15:0] coding_tree_coded_height;
  logic [1:0]  coding_tree_body_kind;
  logic        coding_tree_uses_capacity_tu_grid;
  logic [12:0] coding_tree_luma_tu_count;
  logic [12:0] coding_tree_capacity_tu_grid_bit_len;
  logic        cabac_supported;
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
  logic [7:0]  cabac_stream_data;
  logic        cabac_stream_last;
  logic [12:0] cabac_stream_bit_count;
  logic [12:0] cabac_stream_byte_count;
  logic        cabac_start_q;
  logic        cabac_capture_active_q;
  logic [12:0] cabac_capture_byte_index_q;
  logic [12:0] cabac_captured_bit_len_q;
  logic [12:0] cabac_captured_byte_len_q;
  logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] cabac_captured_byte_bits_q;
  logic        cabac_capture_done_q;
  logic        pending_output_q;
  logic        palette_done_q;
  logic [12:0] slice_payload_ebsp_len_q;
  logic [12:0] slice_payload_ebsp_cra_len_q;
  logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] slice_payload_ebsp_bits_q;
  logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] slice_payload_ebsp_cra_bits_q;

  assign busy = input_active_q || pending_output_q || m_axis_valid || (index_q != 0);
  assign cabac_enable = 1'b1;

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
    .body_kind(coding_tree_body_kind),
    .uses_capacity_tu_grid(coding_tree_uses_capacity_tu_grid),
    .luma_tu_count(coding_tree_luma_tu_count),
    .capacity_tu_grid_bit_len(coding_tree_capacity_tu_grid_bit_len)
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
    .sample_valid(palette_sample_valid),
    .sample_plane(palette_sample_plane),
    .sample(s_axis_data),
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
    .supported(cabac_supported),
    .s_axis_valid(palette_stream_valid),
    .s_axis_ready(palette_stream_ready),
    .s_axis_kind(8'd1),
    .s_axis_data(palette_stream_data),
    .s_axis_last(palette_stream_last),
    .m_axis_ready(1'b1),
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
    .quant_luma_ac_tokens(residual_quant_luma_ac_tokens),
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
    .quant_luma_ac_tokens(residual_quant_luma_ac_tokens_1),
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
      cb_frame_q <= '0;
      cr_frame_q <= '0;
      luma_samples_q <= '0;
      luma_samples_1_q <= '0;
      cb_samples_q <= '0;
      cr_samples_q <= '0;
      quant_luma_rem_q <= 5'd16;
      quant_luma_rem_1_q <= 5'd16;
      quant_chroma_rem_q <= 5'd6;
      quant_luma_ac_tokens_q <= {15{8'h40}};
      quant_luma_ac_tokens_1_q <= {15{8'h40}};
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
      slice_payload_ebsp_len_q <= '0;
      slice_payload_ebsp_cra_len_q <= '0;
      slice_payload_ebsp_bits_q <= '0;
      slice_payload_ebsp_cra_bits_q <= '0;
      cabac_start_q <= 1'b0;
      cabac_capture_active_q <= 1'b0;
      cabac_capture_byte_index_q <= 13'd0;
      cabac_captured_bit_len_q <= 13'd0;
      cabac_captured_byte_len_q <= 13'd0;
      cabac_captured_byte_bits_q <= '0;
      cabac_capture_done_q <= 1'b0;
      pending_output_q <= 1'b0;
      palette_done_q <= 1'b0;
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
        cb_frame_q <= '0;
        cr_frame_q <= '0;
        luma_samples_q <= '0;
        luma_samples_1_q <= '0;
        cb_samples_q <= '0;
        cr_samples_q <= '0;
        quant_luma_rem_q <= 5'd16;
        quant_luma_rem_1_q <= 5'd16;
        quant_chroma_rem_q <= 5'd6;
        quant_luma_ac_tokens_q <= {15{8'h40}};
        quant_luma_ac_tokens_1_q <= {15{8'h40}};
        m_axis_valid   <= 1'b0;
        m_axis_last    <= 1'b0;
        index_q        <= '0;
        slice_payload_ebsp_len_q <= '0;
        slice_payload_ebsp_cra_len_q <= '0;
        slice_payload_ebsp_bits_q <= '0;
        slice_payload_ebsp_cra_bits_q <= '0;
        cabac_capture_active_q <= 1'b0;
        cabac_capture_byte_index_q <= 13'd0;
        cabac_captured_bit_len_q <= 13'd0;
        cabac_captured_byte_len_q <= 13'd0;
        cabac_captured_byte_bits_q <= '0;
        cabac_capture_done_q <= 1'b0;
        pending_output_q <= 1'b0;
        palette_done_q <= 1'b0;
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
        if (PALETTE_MODE && input_count_q >= luma_samples() && input_count_q < luma_samples() + chroma_plane_samples()) begin
          cb_frame_q[(MAX_CHROMA_PLANE_SAMPLES - 1 - (input_count_q - luma_samples())) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (PALETTE_MODE && input_count_q >= v_sample_index() && input_count_q < v_sample_index() + chroma_plane_samples()) begin
          cr_frame_q[(MAX_CHROMA_PLANE_SAMPLES - 1 - (input_count_q - v_sample_index())) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (is_residual_luma_sample(input_count_q)) begin
          luma_samples_q[(15 - residual_luma_sample_index(input_count_q)) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (is_second_residual_luma_sample(input_count_q)) begin
          luma_samples_1_q[(15 - second_residual_luma_sample_index(input_count_q)) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (PALETTE_MODE && input_count_q >= luma_samples() && input_count_q < luma_samples() + 10'd16) begin
          cb_samples_q[(15 - (input_count_q - luma_samples())) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (PALETTE_MODE && input_count_q >= v_sample_index() && input_count_q < v_sample_index() + 10'd16) begin
          cr_samples_q[(15 - (input_count_q - v_sample_index())) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (input_count_q == luma_samples()) begin
          quant_luma_rem_q <= residual_quant_luma_rem;
          quant_luma_ac_tokens_q <= residual_quant_luma_ac_tokens;
          quant_luma_rem_1_q <= residual_quant_luma_rem_1;
          quant_luma_ac_tokens_1_q <= residual_quant_luma_ac_tokens_1;
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
      end else if (pending_output_q && !cabac_capture_active_q && !cabac_capture_done_q &&
                   ((!PALETTE_MODE) || palette_done_q)) begin
        cabac_start_q <= 1'b1;
        cabac_capture_active_q <= 1'b1;
        cabac_capture_byte_index_q <= 13'd0;
        cabac_captured_bit_len_q <= cabac_stream_bit_count;
        cabac_captured_byte_len_q <= cabac_stream_byte_count;
        cabac_captured_byte_bits_q <= '0;
      end else if (pending_output_q && cabac_capture_done_q) begin
        pending_output_q <= 1'b0;
        palette_done_q <= 1'b0;
        cabac_capture_done_q <= 1'b0;
        slice_payload_ebsp_len_q <= slice_payload_escaped_len_calc(1'b0);
        slice_payload_ebsp_bits_q <= slice_payload_escaped_bits_calc(1'b0);
        slice_payload_ebsp_cra_len_q <= slice_payload_escaped_len_calc(1'b1);
        slice_payload_ebsp_cra_bits_q <= slice_payload_escaped_bits_calc(1'b1);
        stream_len_q   <= stream_len_from_slice_payloads(frame_count);
        m_axis_valid   <= 1'b1;
        m_axis_data    <= stream_byte(13'd0);
        m_axis_last    <= 1'b0;
        index_q        <= 8'd1;
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
      if (pending_output_q && palette_stream_valid && palette_stream_ready && palette_stream_last) begin
        palette_done_q <= 1'b1;
      end
      if (cabac_capture_active_q && cabac_stream_valid) begin
        cabac_captured_byte_bits_q <= (cabac_captured_byte_bits_q << 8) | cabac_stream_data;
        cabac_capture_byte_index_q <= cabac_capture_byte_index_q + 13'd1;
        if (cabac_stream_last) begin
          cabac_capture_active_q <= 1'b0;
          cabac_capture_done_q <= 1'b1;
        end
      end
    end
  end

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
      if (PALETTE_MODE) begin
        bit_len = 13'd24 + captured_cabac_payload_bit_len() + 13'd1;
      end else if (uses_capacity_tu_grid()) begin
        bit_len = 13'd24 + capacity_tu_grid_bit_len() + 13'd1;
      end else if (cabac_supported) begin
        bit_len = 13'd24 + captured_cabac_payload_bit_len() + 13'd1;
      end else begin
        bit_len = 13'd24 + 13'd1;
      end
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

  function automatic logic [119:0] quant_luma_ac_tokens();
    begin
      quant_luma_ac_tokens = quant_luma_ac_tokens_q;
    end
  endfunction

  function automatic logic [4:0] quant_luma_rem_1();
    begin
      quant_luma_rem_1 = quant_luma_rem_1_q;
    end
  endfunction

  function automatic logic [119:0] quant_luma_ac_tokens_1();
    begin
      quant_luma_ac_tokens_1 = quant_luma_ac_tokens_1_q;
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
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] raw_payload;
    logic [12:0] raw_index;
    logic [12:0] raw_len;
    logic [12:0] escaped_len;
    logic [1:0] zero_count;
    logic [7:0] raw_byte;
    begin
      raw_payload = current_slice_payload_bits(cra_picture);
      raw_len = slice_payload_len();
      escaped_len = 13'd0;
      zero_count = 2'd0;
      for (raw_index = 13'd0; raw_index < raw_len; raw_index = raw_index + 13'd1) begin
        raw_byte = slice_payload_byte_from_bits(raw_payload, raw_index);
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

  function automatic logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] slice_payload_escaped_bits_calc(
    input logic cra_picture
  );
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] raw_payload;
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] escaped_payload;
    logic [12:0] raw_index;
    logic [12:0] raw_len;
    logic [12:0] escaped_len;
    logic [1:0] zero_count;
    logic [7:0] raw_byte;
    begin
      raw_payload = current_slice_payload_bits(cra_picture);
      raw_len = slice_payload_len();
      escaped_payload = '0;
      escaped_len = 13'd0;
      zero_count = 2'd0;

      for (raw_index = 13'd0; raw_index < raw_len; raw_index = raw_index + 13'd1) begin
        raw_byte = slice_payload_byte_from_bits(raw_payload, raw_index);
        if (zero_count >= 2'd2 && raw_byte <= 8'h03) begin
          escaped_payload = (escaped_payload << 8) | 8'h03;
          escaped_len = escaped_len + 13'd1;
          zero_count = 2'd0;
        end

        escaped_payload = (escaped_payload << 8) | raw_byte;
        escaped_len = escaped_len + 13'd1;

        if (raw_byte == 8'h00) begin
          if (zero_count < 2'd2) begin
            zero_count = zero_count + 2'd1;
          end
        end else begin
          zero_count = 2'd0;
        end
      end

      slice_payload_escaped_bits_calc =
        escaped_payload << (((SLICE_PAYLOAD_BUFFER_BITS >> 3) - escaped_len) * 8);
    end
  endfunction

  function automatic logic [7:0] slice_payload_escaped_cached_byte(
    input logic [12:0] escaped_index,
    input logic        cra_picture
  );
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] payload;
    logic [12:0] len;
    begin
      if (cra_picture) begin
        payload = slice_payload_ebsp_cra_bits_q;
        len = slice_payload_ebsp_cra_len_q;
      end else begin
        payload = slice_payload_ebsp_bits_q;
        len = slice_payload_ebsp_len_q;
      end
      slice_payload_escaped_cached_byte =
        payload >> ((((SLICE_PAYLOAD_BUFFER_BITS >> 3) - 1) - escaped_index) * 8);
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
    begin
      slice_payload_byte = quant_luma_payload_byte(
        quant_luma_rem(),
        quant_luma_ac_tokens(),
        quant_luma_rem_1(),
        quant_luma_ac_tokens_1(),
        index,
        cra_picture
      );
    end
  endfunction

  function automatic logic [7:0] quant_luma_payload_byte(
    input logic [4:0] rem,
    input logic [119:0] ac_tokens,
    input logic [4:0] rem_1,
    input logic [119:0] ac_tokens_1,
    input logic [12:0] index,
    input logic       cra_picture
  );
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] payload;

    begin
      payload = generated_slice_payload_bits(rem, ac_tokens, rem_1, ac_tokens_1, cra_picture);
      quant_luma_payload_byte = slice_payload_byte_from_bits(payload, index);
    end
  endfunction

  function automatic logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] current_slice_payload_bits(
    input logic cra_picture
  );
    begin
      current_slice_payload_bits = generated_slice_payload_bits(
        quant_luma_rem(),
        quant_luma_ac_tokens(),
        quant_luma_rem_1(),
        quant_luma_ac_tokens_1(),
        cra_picture
      );
    end
  endfunction

  function automatic logic [7:0] slice_payload_byte_from_bits(
    input logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] payload,
    input logic [12:0] index
  );
    begin
      slice_payload_byte_from_bits = payload >> (((slice_payload_len() - 13'd1) - index) * 8);
    end
  endfunction

  function automatic logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] generated_slice_payload_bits(
    input logic [4:0] rem,
    input logic [119:0] ac_tokens,
    input logic [4:0] rem_1,
    input logic [119:0] ac_tokens_1,
    input logic       cra_picture
  );
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] acc;
    logic [12:0]  bit_len;
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] selected_cabac_payload_bits;
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] capacity_bits;
    logic [12:0]  payload_len;
    logic [12:0]  payload_bits_len;
    logic [12:0]  payload_byte_len;

    begin
      acc = '0;
      bit_len = 13'd0;

      acc = (acc << 19) | slice_header_bits(cra_picture);
      bit_len = bit_len + 13'd19;

      acc = (acc << 1) | 1'b1; // cabac_alignment_one_bit
      bit_len = bit_len + 13'd1;
      if (cra_picture) begin
        acc = (acc << 1) | 1'b1; // current CRA slice alignment bit
        bit_len = bit_len + 13'd1;
      end
      while (bit_len[2:0] != 3'd0) begin
        acc = acc << 1;
        bit_len = bit_len + 13'd1;
      end

      if (uses_capacity_tu_grid()) begin
        if (PALETTE_MODE) begin
          payload_len = captured_cabac_payload_bit_len();
          selected_cabac_payload_bits = captured_cabac_payload_bits();
          acc = (acc << payload_len) | selected_cabac_payload_bits;
          bit_len = bit_len + payload_len;
        end else begin
        capacity_bits = capacity_tu_grid_bits();
        payload_len = capacity_tu_grid_bit_len();
        acc = (acc << payload_len) | capacity_bits;
        bit_len = bit_len + payload_len;
        end
      end else begin
        if (PALETTE_MODE) begin
          payload_len = captured_cabac_payload_bit_len();
          selected_cabac_payload_bits = captured_cabac_payload_bits();
          acc = (acc << payload_len) | selected_cabac_payload_bits;
          bit_len = bit_len + payload_len;
        end else begin
          payload_len = cabac_supported ? captured_cabac_payload_bit_len() : 13'd0;
          selected_cabac_payload_bits = cabac_supported ? captured_cabac_payload_bits() : '0;
          acc = (acc << payload_len) | selected_cabac_payload_bits;
          bit_len = bit_len + payload_len;
        end
      end

      acc = (acc << 1) | 1'b1; // rbsp_stop_one_bit
      bit_len = bit_len + 13'd1;
      while (bit_len[2:0] != 3'd0) begin
        acc = acc << 1;
        bit_len = bit_len + 13'd1;
      end

      payload_byte_len = (bit_len + 13'd7) >> 3;
      payload_bits_len = payload_byte_len << 3;
      generated_slice_payload_bits = acc << (payload_bits_len - bit_len);
    end
  endfunction

  function automatic logic [12:0] captured_cabac_payload_bit_len();
    begin
      captured_cabac_payload_bit_len = cabac_captured_bit_len_q;
    end
  endfunction

  function automatic logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] captured_cabac_payload_bits();
    logic [12:0] pad_bits;
    begin
      if (cabac_captured_bit_len_q == 13'd0) begin
        captured_cabac_payload_bits = '0;
      end else begin
        pad_bits = (cabac_captured_byte_len_q << 3) - cabac_captured_bit_len_q;
        captured_cabac_payload_bits = cabac_captured_byte_bits_q >> pad_bits;
      end
    end
  endfunction

  function automatic logic uses_capacity_tu_grid();
    begin
      uses_capacity_tu_grid = coding_tree_uses_capacity_tu_grid;
    end
  endfunction

  function automatic logic [12:0] luma_tu_count();
    begin
      luma_tu_count = coding_tree_luma_tu_count;
    end
  endfunction

  function automatic logic [12:0] capacity_tu_grid_bit_len();
    begin
      capacity_tu_grid_bit_len = coding_tree_capacity_tu_grid_bit_len;
    end
  endfunction

  function automatic logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] capacity_tu_grid_bits();
    logic [SLICE_PAYLOAD_BUFFER_BITS - 1:0] bits;
    logic [12:0] tu;
    begin
      bits = luma_tu_count();
      for (tu = 13'd0; tu < luma_tu_count(); tu = tu + 13'd1) begin
        bits = (bits << 5) | quant_luma_rem_for_tu(tu);
        bits = (bits << 8) | quant_luma_ac0_for_tu(tu);
      end
      capacity_tu_grid_bits = bits;
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
