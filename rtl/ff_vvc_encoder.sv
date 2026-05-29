`timescale 1ns/1ps

module ff_vvc_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 64,
  parameter int MAX_VISIBLE_HEIGHT = 64,
  parameter int CTU_SIZE = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [1:0] frame_count,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  // VVC chroma_format_idc values: 1=4:2:0, 2=4:2:2, 3=4:4:4.
  input  logic [1:0] chroma_format_idc,
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
  localparam int CODED_DIMENSION_GRANULARITY = 8;
  localparam int NAL_OVERHEAD_LEN = 6;
  localparam int MAX_LUMA_SAMPLES = MAX_VISIBLE_WIDTH * MAX_VISIBLE_HEIGHT;
  localparam int MAX_CHROMA_PLANE_SAMPLES = MAX_LUMA_SAMPLES;
  localparam int MAX_FRAME_SAMPLES = MAX_LUMA_SAMPLES + (MAX_CHROMA_PLANE_SAMPLES * 2);
  localparam int INPUT_COUNT_BITS = $clog2((MAX_FRAME_SAMPLES * 2) + 1);
  localparam int VVC_RESIDUAL_CB_SIZE = 4;
  localparam int VVC_RESIDUAL_LUMA_SAMPLES = VVC_RESIDUAL_CB_SIZE * VVC_RESIDUAL_CB_SIZE;
  localparam int PALETTE_CU_SIZE = 8;
  localparam int MAX_CTU_PALETTE_SYMBOLS =
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE) *
    ((CTU_SIZE + PALETTE_CU_SIZE - 1) / PALETTE_CU_SIZE);
  localparam logic [1:0] PALETTE_OUT_IDLE     = 2'd0;
  localparam logic [1:0] PALETTE_OUT_PREAMBLE = 2'd1;
  localparam logic [1:0] PALETTE_OUT_CABAC    = 2'd2;
  localparam logic [1:0] PALETTE_OUT_TRAIL    = 2'd3;
  localparam logic [2:0] GENERATED_OUT_IDLE     = 3'd0;
  localparam logic [2:0] GENERATED_OUT_PREAMBLE = 3'd1;
  localparam logic [2:0] GENERATED_OUT_CABAC    = 3'd2;
  localparam logic [2:0] GENERATED_OUT_TRAIL    = 3'd3;

  logic [INPUT_COUNT_BITS - 1:0] input_count_q;
  logic [INPUT_COUNT_BITS - 1:0] input_len_q;
  logic       input_active_q;
  logic [(SAMPLE_BITS * VVC_RESIDUAL_LUMA_SAMPLES) - 1:0] luma_samples_q;
  logic [4:0] quant_luma_rem_q;
  logic [4:0] quant_cb_rem_q;
  logic [4:0] quant_cr_rem_q;
  logic [4:0] residual_quant_luma_rem;
  logic [7:0] residual_recon_luma_sample;
  logic [15:0] coding_tree_coded_width;
  logic [15:0] coding_tree_coded_height;
  logic        cabac_enable;
  logic [7:0]  palette_symbol_count;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_active_mask;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_palette_mask;
  logic [MAX_CTU_PALETTE_SYMBOLS - 1:0] ctu_cu_residual_mask;
  logic        palette_sample_valid;
  logic [1:0]  palette_sample_plane;
  logic        palette_stream_valid;
  logic        palette_stream_ready;
  logic [31:0] palette_stream_data;
  logic        palette_stream_last;
  logic        residual_sample_valid;
  logic        residual_sample_last;
  logic        m_axis_residual_valid;
  logic        m_axis_residual_ready;
  logic [7:0]  m_axis_residual_kind;
  logic [31:0] m_axis_residual_data;
  logic        m_axis_residual_last;
  logic        ctu_symbol_valid;
  logic        ctu_symbol_ready;
  logic [7:0]  ctu_symbol_kind;
  logic [31:0] ctu_symbol_data;
  logic        ctu_symbol_last;
  logic        cabac_symbol_ready;
  logic        cabac_stream_valid;
  logic        cabac_stream_ready;
  logic [7:0]  cabac_stream_data;
  logic        cabac_stream_last;
  logic [2:0]  cabac_stream_last_byte_bits;
  logic        cabac_start_q;
  logic        pending_output_q;
  logic [1:0]  palette_out_state_q;
  logic        palette_hold_valid_q;
  logic [7:0]  palette_hold_byte_q;
  logic        palette_tail_extra_q;
  logic [2:0]  generated_out_state_q;
  logic        generated_slice_cra_q;
  logic        generated_hold_valid_q;
  logic [7:0]  generated_hold_byte_q;
  logic        generated_tail_extra_q;
  logic [7:0]  generated_header_index_q;
  logic [7:0]  generated_header_byte_w;
  logic [7:0]  generated_header_byte_count_w;
  logic        generated_header_supported_w;
  logic        ctu_has_palette_cu;
  logic [1:0]  chroma_subsample_x_w;
  logic [1:0]  chroma_subsample_y_w;
  logic [INPUT_COUNT_BITS - 1:0] luma_samples_w;
  logic [INPUT_COUNT_BITS - 1:0] chroma_plane_samples_w;
  logic [INPUT_COUNT_BITS - 1:0] frame_samples_w;
  logic [INPUT_COUNT_BITS - 1:0] input_len_w;
  logic [INPUT_COUNT_BITS - 1:0] v_sample_index_w;
  logic [1:0]  palette_sample_plane_w;
  logic [15:0] input_luma_x_w;
  logic [15:0] input_luma_y_w;
  logic        residual_luma_sample_w;
  logic [3:0]  residual_luma_sample_index_w;
  logic [7:0]  sampled_u_8bit_w;
  logic [7:0]  sampled_v_8bit_w;
  logic [8:0]  sampled_u_clamped_w;
  logic [8:0]  sampled_v_clamped_w;
  logic [8:0]  quant_cb_level_w;
  logic [8:0]  quant_cr_level_w;
  logic [7:0]  cabac_tail_byte_w;

  // Current subset policy: 4:4:4 input selects palette for every visible CU.
  // This is deliberately represented as a CU mask so later mixed
  // palette/residual decisions can be made per CU without changing the
  // palette and residual block interfaces.
  assign ctu_cu_palette_mask = (chroma_format_idc == 2'd3) ? ctu_cu_active_mask : '0;
  assign ctu_cu_residual_mask = ctu_cu_active_mask & ~ctu_cu_palette_mask;

  // The output/CABAC mux is still slice-wide. For the current subset, a 4:4:4
  // picture has all active CUs in palette mode; future mixed slices should
  // replace this with a CU-mode symbol stream instead of a whole-slice mux.
  assign ctu_has_palette_cu = |ctu_cu_palette_mask;
  assign chroma_subsample_x_w = ((chroma_format_idc == 2'd1) || (chroma_format_idc == 2'd2)) ?
                                2'd2 : 2'd1;
  assign chroma_subsample_y_w = (chroma_format_idc == 2'd1) ? 2'd2 : 2'd1;
  assign luma_samples_w = visible_width * visible_height;
  assign chroma_plane_samples_w =
    (visible_width / chroma_subsample_x_w) * (visible_height / chroma_subsample_y_w);
  assign frame_samples_w = luma_samples_w + (chroma_plane_samples_w << 1);
  assign input_len_w = (frame_count == 2'd2) ? (frame_samples_w << 1) : frame_samples_w;
  assign v_sample_index_w = luma_samples_w + chroma_plane_samples_w;
  assign palette_sample_plane_w =
    (input_count_q < luma_samples_w) ? 2'd0 :
    ((input_count_q < v_sample_index_w) ? 2'd1 : 2'd2);
  assign input_luma_x_w = (visible_width == 16'd0) ? 16'd0 : (input_count_q % visible_width);
  assign input_luma_y_w = (visible_width == 16'd0) ? 16'd0 : (input_count_q / visible_width);
  assign residual_luma_sample_w =
    (input_count_q < luma_samples_w) &&
    (input_luma_x_w < VVC_RESIDUAL_CB_SIZE[15:0]) &&
    (input_luma_y_w < VVC_RESIDUAL_CB_SIZE[15:0]);
  assign residual_luma_sample_index_w =
    ((input_luma_y_w[3:0] * VVC_RESIDUAL_CB_SIZE[3:0]) + input_luma_x_w[3:0]);
  assign sampled_u_8bit_w = (SAMPLE_BITS <= 8) ? sampled_u[7:0] : (sampled_u >> (SAMPLE_BITS - 8));
  assign sampled_v_8bit_w = (SAMPLE_BITS <= 8) ? sampled_v[7:0] : (sampled_v >> (SAMPLE_BITS - 8));
  assign sampled_u_clamped_w = (sampled_u_8bit_w > 8'd128) ? 9'd128 : {1'b0, sampled_u_8bit_w};
  assign sampled_v_clamped_w = (sampled_v_8bit_w > 8'd128) ? 9'd128 : {1'b0, sampled_v_8bit_w};
  assign quant_cb_level_w = (sampled_u_clamped_w + 9'd4) >> 3;
  assign quant_cr_level_w = (sampled_v_clamped_w + 9'd4) >> 3;

  always_comb begin
    case (cabac_stream_last_byte_bits)
      3'd1: cabac_tail_byte_w = (generated_hold_byte_q & 8'b1000_0000) | 8'h40;
      3'd2: cabac_tail_byte_w = (generated_hold_byte_q & 8'b1100_0000) | 8'h20;
      3'd3: cabac_tail_byte_w = (generated_hold_byte_q & 8'b1110_0000) | 8'h10;
      3'd4: cabac_tail_byte_w = (generated_hold_byte_q & 8'b1111_0000) | 8'h08;
      3'd5: cabac_tail_byte_w = (generated_hold_byte_q & 8'b1111_1000) | 8'h04;
      3'd6: cabac_tail_byte_w = (generated_hold_byte_q & 8'b1111_1100) | 8'h02;
      3'd7: cabac_tail_byte_w = (generated_hold_byte_q & 8'b1111_1110) | 8'h01;
      default: cabac_tail_byte_w = 8'h80;
    endcase
  end

  assign busy = input_active_q || pending_output_q || m_axis_valid ||
                (palette_out_state_q != PALETTE_OUT_IDLE) ||
                (generated_out_state_q != GENERATED_OUT_IDLE);
  assign cabac_enable = 1'b1;
  assign cabac_stream_ready =
    ctu_has_palette_cu
      ? ((palette_out_state_q == PALETTE_OUT_CABAC) && (!m_axis_valid || m_axis_ready))
      : ((generated_out_state_q == GENERATED_OUT_CABAC) && (!m_axis_valid || m_axis_ready));
  assign palette_stream_ready = ctu_has_palette_cu && cabac_symbol_ready;
  assign m_axis_residual_ready = !ctu_has_palette_cu && cabac_symbol_ready;

  ff_vvc_cu_activity_mask #(
    .CTU_SIZE(CTU_SIZE),
    .CU_SIZE(PALETTE_CU_SIZE),
    .CU_COUNT(MAX_CTU_PALETTE_SYMBOLS)
  ) ctu_cu_activity_mask (
    .visible_width(visible_width),
    .visible_height(visible_height),
    .cu_active_mask(ctu_cu_active_mask)
  );

  ff_vvc_coding_tree_scheduler #(
    .CTU_SIZE(CTU_SIZE)
  ) coding_tree_scheduler (
    .visible_width(visible_width),
    .visible_height(visible_height),
    .coded_width(coding_tree_coded_width),
    .coded_height(coding_tree_coded_height)
  );

  ff_vvc_annexb_header annexb_header (
    .visible_width(visible_width),
    .visible_height(visible_height),
    .index(generated_header_index_q),
    .byte_value(generated_header_byte_w),
    .byte_count(generated_header_byte_count_w),
    .supported(generated_header_supported_w)
  );

  always @* begin
    palette_sample_valid = 1'b0;
    palette_sample_plane = 2'd0;
    if (ctu_has_palette_cu && input_active_q && s_axis_valid &&
        (input_count_q < frame_samples_w)) begin
      palette_sample_valid = 1'b1;
      palette_sample_plane = palette_sample_plane_w;
    end
  end

  always @* begin
    residual_sample_valid = !ctu_has_palette_cu && input_active_q && s_axis_valid && s_axis_ready &&
                            residual_luma_sample_w;
    residual_sample_last = residual_sample_valid &&
                           (residual_luma_sample_index_w == 4'd15);
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
    .enable(ctu_has_palette_cu),
    .ctu_coded_width(coding_tree_coded_width),
    .ctu_coded_height(coding_tree_coded_height),
    .cu_select_mask(ctu_cu_palette_mask),
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
    .mode_palette_444(ctu_has_palette_cu),
    .visible_width(visible_width),
    .visible_height(visible_height),
    .coded_width(coding_tree_coded_width),
    .coded_height(coding_tree_coded_height),
    .luma_rem(quant_luma_rem_q),
    .cb_rem(quant_cb_rem_q),
    .cr_rem(quant_cr_rem_q),
    .symbol_count(palette_symbol_count),
    .s_axis_valid(ctu_has_palette_cu ? palette_stream_valid : ctu_symbol_valid),
    .s_axis_ready(cabac_symbol_ready),
    .s_axis_kind(ctu_has_palette_cu ? 8'd1 : ctu_symbol_kind),
    .s_axis_data(ctu_has_palette_cu ? palette_stream_data : ctu_symbol_data),
    .s_axis_last(ctu_has_palette_cu ? palette_stream_last : ctu_symbol_last),
    .m_axis_ready(cabac_stream_ready),
    .m_axis_valid(cabac_stream_valid),
    .m_axis_data(cabac_stream_data),
    .m_axis_last(cabac_stream_last),
    .stream_last_byte_bits(cabac_stream_last_byte_bits)
  );

  ff_vvc_residual_transform #(
    .SAMPLE_BITS(SAMPLE_BITS),
    .LUMA_CB_SIZE(VVC_RESIDUAL_CB_SIZE),
    .CU_ACTIVE_COUNT(MAX_CTU_PALETTE_SYMBOLS)
  ) residual_block (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .enable(1'b1),
    .cu_active_mask(ctu_cu_residual_mask),
    .cu_index(8'd0),
    .cu_active(),
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

  ff_vvc_residual_dc_symbolizer residual_dc_symbols (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .start(cabac_start_q && !ctu_has_palette_cu),
    .abs_level(quant_luma_rem_q),
    .negative(quant_luma_rem_q != 5'd0),
    .log2_tb_size((coding_tree_coded_width >= 16'd16 || coding_tree_coded_height >= 16'd16) ? 3'd4 : 3'd3),
    .m_axis_valid(m_axis_residual_valid),
    .m_axis_ready(m_axis_residual_ready),
    .m_axis_kind(m_axis_residual_kind),
    .m_axis_data(m_axis_residual_data),
    .m_axis_last(m_axis_residual_last),
    .busy()
  );

  ff_vvc_420_ctu_symbolizer ctu_420_symbols (
    .clk(clk),
    .rst_n(rst_n),
    .clear(start && !busy),
    .start(cabac_start_q && !ctu_has_palette_cu),
    .visible_width(visible_width),
    .visible_height(visible_height),
    .luma_abs_level(quant_luma_rem_q),
    .luma_negative(quant_luma_rem_q != 5'd0),
    .m_axis_valid(ctu_symbol_valid),
    .m_axis_ready(ctu_symbol_ready),
    .m_axis_kind(ctu_symbol_kind),
    .m_axis_data(ctu_symbol_data),
    .m_axis_last(ctu_symbol_last),
    .busy()
  );

  assign ctu_symbol_ready = !ctu_has_palette_cu && cabac_symbol_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      input_count_q <= '0;
      input_len_q   <= '0;
      input_active_q <= 1'b0;
      s_axis_ready <= 1'b0;
      input_error  <= 1'b0;
      sampled_color_valid <= 1'b0;
      sampled_y <= '0;
      sampled_u <= '0;
      sampled_v <= '0;
      luma_samples_q <= '0;
      quant_luma_rem_q <= 5'd16;
      quant_cb_rem_q <= 5'd16;
      quant_cr_rem_q <= 5'd16;
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
      cabac_start_q <= 1'b0;
      pending_output_q <= 1'b0;
      palette_out_state_q <= PALETTE_OUT_IDLE;
      palette_hold_valid_q <= 1'b0;
      palette_hold_byte_q <= 8'd0;
      palette_tail_extra_q <= 1'b0;
      generated_out_state_q <= GENERATED_OUT_IDLE;
      generated_slice_cra_q <= 1'b0;
      generated_hold_valid_q <= 1'b0;
      generated_hold_byte_q <= 8'd0;
      generated_tail_extra_q <= 1'b0;
      generated_header_index_q <= 8'd0;
    end else begin
      cabac_start_q <= 1'b0;
      if (start && !busy) begin
        input_active_q <= 1'b1;
        s_axis_ready   <= 1'b1;
        input_count_q  <= '0;
        input_len_q    <= input_len_w;
        input_error    <= 1'b0;
        sampled_color_valid <= 1'b0;
        luma_samples_q <= '0;
        quant_luma_rem_q <= 5'd16;
        quant_cb_rem_q <= 5'd16;
        quant_cr_rem_q <= 5'd16;
        m_axis_valid   <= 1'b0;
        m_axis_last    <= 1'b0;
        pending_output_q <= 1'b0;
        palette_out_state_q <= PALETTE_OUT_IDLE;
        palette_hold_valid_q <= 1'b0;
        palette_hold_byte_q <= 8'd0;
        palette_tail_extra_q <= 1'b0;
        generated_out_state_q <= GENERATED_OUT_IDLE;
        generated_slice_cra_q <= 1'b0;
        generated_hold_valid_q <= 1'b0;
        generated_hold_byte_q <= 8'd0;
        generated_tail_extra_q <= 1'b0;
        generated_header_index_q <= 8'd0;
      end else if (input_active_q && s_axis_valid && s_axis_ready) begin
        if (s_axis_last != (input_count_q == input_len_q - 1'b1)) begin
          input_error <= 1'b1;
        end
        if (input_count_q == 8'd0) begin
          sampled_y <= s_axis_data;
        end
        if (residual_luma_sample_w) begin
          luma_samples_q[(15 - residual_luma_sample_index_w) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (input_count_q == luma_samples_w) begin
          quant_luma_rem_q <= residual_quant_luma_rem;
        end
        if (input_count_q == luma_samples_w) begin
          sampled_u <= s_axis_data;
        end
        if (input_count_q == v_sample_index_w) begin
          sampled_v <= s_axis_data;
          quant_cb_rem_q <= 5'd16 - quant_cb_level_w[4:0];
          quant_cr_rem_q <= 5'd16 - quant_cr_level_w[4:0];
        end

        if (input_count_q == input_len_q - 1'b1) begin
          input_active_q <= 1'b0;
          s_axis_ready   <= 1'b0;
          sampled_color_valid <= !input_error && s_axis_last;
          pending_output_q <= 1'b1;
        end else begin
          input_count_q <= input_count_q + 1'b1;
        end
      end else if (pending_output_q && ctu_has_palette_cu &&
                   (palette_out_state_q == PALETTE_OUT_IDLE)) begin
        pending_output_q <= 1'b0;
        palette_out_state_q <= PALETTE_OUT_PREAMBLE;
        palette_hold_valid_q <= 1'b0;
        palette_hold_byte_q <= 8'd0;
        palette_tail_extra_q <= 1'b0;
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        m_axis_last <= 1'b0;
      end else if (pending_output_q && !ctu_has_palette_cu &&
                   (generated_out_state_q == GENERATED_OUT_IDLE)) begin
        pending_output_q <= 1'b0;
        generated_out_state_q <= GENERATED_OUT_PREAMBLE;
        generated_slice_cra_q <= 1'b0;
        generated_hold_valid_q <= 1'b0;
        generated_hold_byte_q <= 8'd0;
        generated_tail_extra_q <= 1'b0;
        generated_header_index_q <= 8'd0;
        m_axis_valid <= 1'b0;
        m_axis_data <= 8'd0;
        m_axis_last <= 1'b0;
      end
      if (ctu_has_palette_cu && (palette_out_state_q != PALETTE_OUT_IDLE) &&
          (!m_axis_valid || m_axis_ready)) begin
        case (palette_out_state_q)
          PALETTE_OUT_PREAMBLE: begin
            m_axis_valid <= 1'b0;
            m_axis_last <= 1'b0;
            cabac_start_q <= 1'b1;
            palette_out_state_q <= PALETTE_OUT_CABAC;
          end
          PALETTE_OUT_CABAC: begin
            if (cabac_stream_valid) begin
              if (palette_hold_valid_q) begin
                m_axis_valid <= 1'b1;
                m_axis_data <= palette_hold_byte_q;
                m_axis_last <= 1'b0;
              end else begin
                m_axis_valid <= 1'b0;
                m_axis_last <= 1'b0;
              end
              palette_hold_valid_q <= 1'b1;
              palette_hold_byte_q <= cabac_stream_data;
              if (cabac_stream_last) begin
                palette_out_state_q <= PALETTE_OUT_TRAIL;
                palette_tail_extra_q <= (cabac_stream_last_byte_bits == 3'd0);
              end
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
            end
          end
          PALETTE_OUT_TRAIL: begin
            if (palette_tail_extra_q && palette_hold_valid_q) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= palette_hold_byte_q;
              m_axis_last <= 1'b0;
              palette_hold_valid_q <= 1'b0;
            end else if (palette_tail_extra_q) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= 8'h80;
              m_axis_last <= 1'b1;
              palette_tail_extra_q <= 1'b0;
              palette_out_state_q <= PALETTE_OUT_IDLE;
            end else begin
              m_axis_valid <= 1'b1;
              m_axis_data <= cabac_tail_byte_w;
              m_axis_last <= 1'b1;
              palette_hold_valid_q <= 1'b0;
              palette_out_state_q <= PALETTE_OUT_IDLE;
            end
          end
          default: begin
            palette_out_state_q <= PALETTE_OUT_IDLE;
          end
        endcase
      end
      if (!ctu_has_palette_cu && (generated_out_state_q != GENERATED_OUT_IDLE) &&
          (!m_axis_valid || m_axis_ready)) begin
        case (generated_out_state_q)
          GENERATED_OUT_PREAMBLE: begin
            if (generated_header_supported_w && generated_header_index_q < generated_header_byte_count_w) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= generated_header_byte_w;
              m_axis_last <= 1'b0;
              if (generated_header_index_q == generated_header_byte_count_w - 8'd1) begin
                generated_header_index_q <= 8'd0;
                cabac_start_q <= 1'b1;
                generated_out_state_q <= GENERATED_OUT_CABAC;
              end else begin
                generated_header_index_q <= generated_header_index_q + 8'd1;
              end
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
              generated_header_index_q <= 8'd0;
              cabac_start_q <= 1'b1;
              generated_out_state_q <= GENERATED_OUT_CABAC;
            end
          end
          GENERATED_OUT_CABAC: begin
            if (cabac_stream_valid) begin
              if (generated_hold_valid_q) begin
                m_axis_valid <= 1'b1;
                m_axis_data <= generated_hold_byte_q;
                m_axis_last <= 1'b0;
              end else begin
                m_axis_valid <= 1'b0;
                m_axis_last <= 1'b0;
              end
              generated_hold_valid_q <= 1'b1;
              generated_hold_byte_q <= cabac_stream_data;
              if (cabac_stream_last) begin
                generated_out_state_q <= GENERATED_OUT_TRAIL;
                generated_tail_extra_q <= (cabac_stream_last_byte_bits == 3'd0);
              end
            end else begin
              m_axis_valid <= 1'b0;
              m_axis_last <= 1'b0;
            end
          end
          GENERATED_OUT_TRAIL: begin
            if (generated_tail_extra_q && generated_hold_valid_q) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= generated_hold_byte_q;
              m_axis_last <= 1'b0;
              generated_hold_valid_q <= 1'b0;
            end else if (generated_tail_extra_q) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= 8'h80;
              m_axis_last <= (frame_count != 2'd2) || generated_slice_cra_q;
              generated_tail_extra_q <= 1'b0;
              if ((frame_count != 2'd2) || generated_slice_cra_q) begin
                generated_out_state_q <= GENERATED_OUT_IDLE;
              end else begin
                generated_out_state_q <= GENERATED_OUT_PREAMBLE;
                generated_slice_cra_q <= 1'b1;
              end
            end else begin
              m_axis_valid <= 1'b1;
              m_axis_data <= cabac_tail_byte_w;
              m_axis_last <= (frame_count != 2'd2) || generated_slice_cra_q;
              generated_hold_valid_q <= 1'b0;
              if ((frame_count != 2'd2) || generated_slice_cra_q) begin
                generated_out_state_q <= GENERATED_OUT_IDLE;
              end else begin
                generated_out_state_q <= GENERATED_OUT_PREAMBLE;
                generated_slice_cra_q <= 1'b1;
              end
            end
          end
          default: begin
            generated_out_state_q <= GENERATED_OUT_IDLE;
          end
        endcase
      end
    end
  end

endmodule
