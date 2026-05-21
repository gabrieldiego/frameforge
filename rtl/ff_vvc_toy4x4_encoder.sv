`timescale 1ns/1ps

module ff_vvc_toy4x4_encoder #(
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS,
  // VVC chroma_format_idc values: 1=4:2:0, 2=4:2:2, 3=4:4:4.
  // The current generated bitstream remains the toy 4:2:0 validation stream,
  // but the input drain and first-chroma sampling are parameterized so wider
  // RTL input front-ends can be tested independently.
  parameter int CHROMA_FORMAT_IDC = 1
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [1:0] frame_count,
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
  localparam int SPS_PAYLOAD_LEN  = 31;
  localparam int PPS_PAYLOAD_LEN  = 14;
  localparam int COEFF_SIDEBAND_PAYLOAD_LEN = 23;
  localparam int PALETTE_SAMPLE_NIBBLES = (SOURCE_SAMPLE_BITS + 3) / 4;
  localparam int PALETTE_ENTRY_PAYLOAD_LEN = 16 * 3 * PALETTE_SAMPLE_NIBBLES;
  localparam int PALETTE_ENTRY_START = 11;
  localparam int PALETTE_INDEX_MARKER_START = PALETTE_ENTRY_START + PALETTE_ENTRY_PAYLOAD_LEN;
  localparam int PALETTE_INDEX_START = PALETTE_INDEX_MARKER_START + 3;
  localparam int PALETTE_SIDEBAND_PAYLOAD_LEN = PALETTE_INDEX_START + 8 + 1;
  localparam int NAL_OVERHEAD_LEN = 6;
  localparam int SPS_NAL_LEN = NAL_OVERHEAD_LEN + SPS_PAYLOAD_LEN;
  localparam int PPS_NAL_LEN = NAL_OVERHEAD_LEN + PPS_PAYLOAD_LEN;
  localparam int COEFF_SIDEBAND_NAL_LEN = NAL_OVERHEAD_LEN + COEFF_SIDEBAND_PAYLOAD_LEN;
  localparam int PALETTE_SIDEBAND_NAL_LEN = NAL_OVERHEAD_LEN + PALETTE_SIDEBAND_PAYLOAD_LEN;
  localparam int PARAMETER_SET_LEN = SPS_NAL_LEN + PPS_NAL_LEN;
  localparam int LUMA_SAMPLES = 16;
  localparam int CHROMA_PLANE_SAMPLES = (CHROMA_FORMAT_IDC == 3) ? 16 :
                                       ((CHROMA_FORMAT_IDC == 2) ? 8 : 4);
  localparam int FRAME_SAMPLES = LUMA_SAMPLES + (CHROMA_PLANE_SAMPLES * 2);
  localparam int V_SAMPLE_INDEX = LUMA_SAMPLES + CHROMA_PLANE_SAMPLES;
  localparam bit PALETTE_MODE = (CHROMA_FORMAT_IDC == 3);

  logic [8:0] index_q;
  logic [8:0] stream_len_q;
  logic [7:0] input_count_q;
  logic [7:0] input_len_q;
  logic       input_active_q;
  logic [(SAMPLE_BITS * 16) - 1:0] luma_samples_q;
  logic [(SAMPLE_BITS * 16) - 1:0] cb_samples_q;
  logic [(SAMPLE_BITS * 16) - 1:0] cr_samples_q;
  logic [4:0] quant_luma_rem_q;
  logic [4:0] quant_chroma_rem_q;
  logic [119:0] quant_luma_ac_tokens_q;
  logic [4:0] residual_quant_luma_rem;
  logic [119:0] residual_quant_luma_ac_tokens;
  logic [7:0] residual_recon_luma_sample;

  assign busy = input_active_q || m_axis_valid || (index_q != 0);

  ff_residual_stub #(
    .SAMPLE_BITS(SAMPLE_BITS)
  ) residual_block (
    .luma_samples(luma_samples_q),
    .quant_luma_rem(residual_quant_luma_rem),
    .quant_luma_ac_tokens(residual_quant_luma_ac_tokens),
    .recon_luma_sample(residual_recon_luma_sample)
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
      luma_samples_q <= '0;
      cb_samples_q <= '0;
      cr_samples_q <= '0;
      quant_luma_rem_q <= 5'd16;
      quant_chroma_rem_q <= 5'd6;
      quant_luma_ac_tokens_q <= {15{8'h40}};
      m_axis_valid <= 1'b0;
      m_axis_data  <= '0;
      m_axis_last  <= 1'b0;
    end else begin
      if (start && !busy) begin
        input_active_q <= 1'b1;
        s_axis_ready   <= 1'b1;
        input_count_q  <= '0;
        input_len_q    <= input_len(frame_count);
        stream_len_q   <= '0;
        input_error    <= 1'b0;
        sampled_color_valid <= 1'b0;
        luma_samples_q <= '0;
        cb_samples_q <= '0;
        cr_samples_q <= '0;
        quant_luma_rem_q <= 5'd16;
        quant_chroma_rem_q <= 5'd6;
        quant_luma_ac_tokens_q <= {15{8'h40}};
        m_axis_valid   <= 1'b0;
        m_axis_last    <= 1'b0;
        index_q        <= '0;
      end else if (input_active_q && s_axis_valid && s_axis_ready) begin
        if (s_axis_last != (input_count_q == input_len_q - 1'b1)) begin
          input_error <= 1'b1;
        end
        if (input_count_q == 8'd0) begin
          sampled_y <= s_axis_data;
        end
        if (input_count_q < LUMA_SAMPLES) begin
          luma_samples_q[(15 - input_count_q[3:0]) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (PALETTE_MODE && input_count_q >= LUMA_SAMPLES && input_count_q < LUMA_SAMPLES + 8'd16) begin
          cb_samples_q[(15 - (input_count_q - LUMA_SAMPLES)) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (PALETTE_MODE && input_count_q >= V_SAMPLE_INDEX && input_count_q < V_SAMPLE_INDEX + 8'd16) begin
          cr_samples_q[(15 - (input_count_q - V_SAMPLE_INDEX)) * SAMPLE_BITS +: SAMPLE_BITS] <= s_axis_data;
        end
        if (input_count_q == LUMA_SAMPLES) begin
          quant_luma_rem_q <= residual_quant_luma_rem;
          quant_luma_ac_tokens_q <= residual_quant_luma_ac_tokens;
        end
        if (input_count_q == LUMA_SAMPLES) begin
          sampled_u <= s_axis_data;
        end
        if (input_count_q == V_SAMPLE_INDEX) begin
          sampled_v <= s_axis_data;
          quant_chroma_rem_q <= quant_chroma_rem_from_samples(sampled_u, s_axis_data);
        end

        if (input_count_q == input_len_q - 1'b1) begin
          input_active_q <= 1'b0;
          s_axis_ready   <= 1'b0;
          sampled_color_valid <= !input_error && s_axis_last;
          stream_len_q   <= stream_len(frame_count);
          m_axis_valid   <= 1'b1;
          m_axis_data    <= stream_byte(8'd0);
          m_axis_last    <= 1'b0;
          index_q        <= 8'd1;
        end else begin
          input_count_q <= input_count_q + 1'b1;
        end
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
    end
  end

  function automatic logic [7:0] input_len(input logic [1:0] frames);
    case (frames)
      2'd2: input_len = FRAME_SAMPLES * 2;
      default: input_len = FRAME_SAMPLES;
    endcase
  endfunction

  function automatic logic [8:0] stream_len(input logic [1:0] frames);
    case (frames)
      2'd2: stream_len = PARAMETER_SET_LEN + color_filler_nal_len() + palette_sideband_nal_len() + COEFF_SIDEBAND_NAL_LEN + (slice_nal_len() * 2);
      default: stream_len = PARAMETER_SET_LEN + color_filler_nal_len() + palette_sideband_nal_len() + COEFF_SIDEBAND_NAL_LEN + slice_nal_len();
    endcase
  endfunction

  function automatic logic [7:0] slice_payload_len();
    begin
      case (quant_luma_rem())
        5'd0, 5'd1, 5'd2: slice_payload_len = 8'd9;
        5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9, 5'd10, 5'd11: slice_payload_len = 8'd10;
        default: slice_payload_len = 8'd11;
      endcase
      if (quant_chroma_rem() == 5'd0) begin
        slice_payload_len = slice_payload_len - 8'd1;
      end
    end
  endfunction

  function automatic logic [7:0] slice_nal_len();
    begin
      slice_nal_len = NAL_OVERHEAD_LEN + slice_payload_len();
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

  function automatic logic [7:0] color_filler_nal_len();
    begin
      color_filler_nal_len = NAL_OVERHEAD_LEN + color_filler_payload_len();
    end
  endfunction

  function automatic logic [8:0] palette_sideband_nal_len();
    begin
      palette_sideband_nal_len = PALETTE_MODE ? PALETTE_SIDEBAND_NAL_LEN : 9'd0;
    end
  endfunction

  function automatic logic [7:0] stream_byte(input logic [8:0] index);
    logic second_picture;
    logic [8:0] slice_base;
    logic [8:0] palette_base;
    logic [8:0] coeff_base;
    logic [6:0] slice_index;

    begin
      if (index < SPS_NAL_LEN) begin
        stream_byte = nal_byte(3'd0, index[6:0], 1'b0);
      end else if (index < PARAMETER_SET_LEN) begin
        stream_byte = nal_byte(3'd1, index - SPS_NAL_LEN, 1'b0);
      end else if (index < PARAMETER_SET_LEN + color_filler_nal_len()) begin
        stream_byte = nal_byte(3'd3, index - PARAMETER_SET_LEN, 1'b0);
      end else if (index < PARAMETER_SET_LEN + color_filler_nal_len() + palette_sideband_nal_len()) begin
        palette_base = PARAMETER_SET_LEN + color_filler_nal_len();
        stream_byte = nal_byte(3'd5, index - palette_base, 1'b0);
      end else if (index < PARAMETER_SET_LEN + color_filler_nal_len() + palette_sideband_nal_len() + COEFF_SIDEBAND_NAL_LEN) begin
        coeff_base = PARAMETER_SET_LEN + color_filler_nal_len() + palette_sideband_nal_len();
        stream_byte = nal_byte(3'd4, index - coeff_base, 1'b0);
      end else begin
        slice_base = PARAMETER_SET_LEN + color_filler_nal_len() + palette_sideband_nal_len() + COEFF_SIDEBAND_NAL_LEN;
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
    input logic [8:0] nal_index,
    input logic       cra_picture
  );
    begin
      if (nal_index < 7'd4) begin
        nal_byte = start_code_byte(nal_index[1:0]);
      end else if (nal_index < 7'd6) begin
        nal_byte = nal_header_byte(nal_kind, nal_index[0], cra_picture);
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
        3'd4: nal_unit_type = 5'd30; // Reserved FrameForge coefficient sideband.
        3'd5: nal_unit_type = 5'd30; // Reserved FrameForge palette sideband.
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
    input logic [8:0] payload_index,
    input logic       cra_picture
  );
    begin
      case (nal_kind)
        3'd0: payload_byte = sps_payload_byte(payload_index);
        3'd1: payload_byte = pps_payload_byte(payload_index);
        3'd3: payload_byte = color_filler_payload_byte(payload_index);
        3'd4: payload_byte = coeff_sideband_payload_byte(payload_index);
        3'd5: payload_byte = palette_sideband_payload_byte(payload_index);
        default: payload_byte = slice_payload_byte(payload_index, cra_picture);
      endcase
    end
  endfunction

  function automatic logic [7:0] palette_sideband_payload_byte(input logic [8:0] index);
    logic [8:0] entry_rel;
    logic [8:0] entry_token;
    logic [3:0] entry_idx;
    logic [1:0] entry_comp;
    logic [3:0] sample_nibble;
    logic [15:0] entry_sample;

    begin
      if (index == 7'd0 || index == 7'd1) begin
        palette_sideband_payload_byte = 8'h46; // F
      end else if (index == 7'd2) begin
        palette_sideband_payload_byte = 8'h50; // P
      end else if (index == 7'd3) begin
        palette_sideband_payload_byte = 8'h4c; // L
      end else if (index == 7'd4) begin
        palette_sideband_payload_byte = 8'h85; // sideband version 5
      end else if (index == 7'd5) begin
        palette_sideband_payload_byte = 8'h10; // sixteen palette entries
      end else if (index == 7'd6) begin
        palette_sideband_payload_byte = CHROMA_FORMAT_IDC;
      end else if (index == 7'd7) begin
        palette_sideband_payload_byte = SOURCE_SAMPLE_BITS;
      end else if (index == 7'd8) begin
        palette_sideband_payload_byte = 8'h59; // Y
      end else if (index == 7'd9) begin
        palette_sideband_payload_byte = 8'h55; // U
      end else if (index == 7'd10) begin
        palette_sideband_payload_byte = 8'h56; // V
      end else if (index >= PALETTE_ENTRY_START && index < PALETTE_INDEX_MARKER_START) begin
        entry_rel = index - PALETTE_ENTRY_START;
        entry_idx = entry_rel / (3 * PALETTE_SAMPLE_NIBBLES);
        entry_token = entry_rel - (entry_idx * 3 * PALETTE_SAMPLE_NIBBLES);
        entry_comp = entry_token / PALETTE_SAMPLE_NIBBLES;
        sample_nibble = (PALETTE_SAMPLE_NIBBLES - 1) - (entry_token - (entry_comp * PALETTE_SAMPLE_NIBBLES));
        case (entry_comp)
          2'd0: entry_sample = luma_sample_source(entry_idx);
          2'd1: entry_sample = cb_sample_source(entry_idx);
          default: entry_sample = cr_sample_source(entry_idx);
        endcase
        palette_sideband_payload_byte = 8'h40 | ((entry_sample >> (sample_nibble * 4)) & 16'h000f);
      end else if (index == PALETTE_INDEX_MARKER_START) begin
        palette_sideband_payload_byte = 8'h49; // I
      end else if (index == PALETTE_INDEX_MARKER_START + 1) begin
        palette_sideband_payload_byte = 8'h44; // D
      end else if (index == PALETTE_INDEX_MARKER_START + 2) begin
        palette_sideband_payload_byte = 8'h58; // X
      end else if (index >= PALETTE_INDEX_START && index < PALETTE_INDEX_START + 8) begin
        palette_sideband_payload_byte = ((index - PALETTE_INDEX_START) << 5) | (((index - PALETTE_INDEX_START) << 1) + 1'b1);
      end else if (index == PALETTE_INDEX_START + 8) begin
        palette_sideband_payload_byte = 8'h80;
      end else begin
        palette_sideband_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] luma_sample_8(input logic [3:0] index);
    begin
      luma_sample_8 = sample_to_8bit(luma_samples_q[(15 - index) * SAMPLE_BITS +: SAMPLE_BITS]);
    end
  endfunction

  function automatic logic [15:0] luma_sample_source(input logic [3:0] index);
    begin
      luma_sample_source = sample_to_source(luma_samples_q[(15 - index) * SAMPLE_BITS +: SAMPLE_BITS]);
    end
  endfunction

  function automatic logic [7:0] cb_sample_8(input logic [3:0] index);
    begin
      cb_sample_8 = sample_to_8bit(cb_samples_q[(15 - index) * SAMPLE_BITS +: SAMPLE_BITS]);
    end
  endfunction

  function automatic logic [15:0] cb_sample_source(input logic [3:0] index);
    begin
      cb_sample_source = sample_to_source(cb_samples_q[(15 - index) * SAMPLE_BITS +: SAMPLE_BITS]);
    end
  endfunction

  function automatic logic [7:0] cr_sample_8(input logic [3:0] index);
    begin
      cr_sample_8 = sample_to_8bit(cr_samples_q[(15 - index) * SAMPLE_BITS +: SAMPLE_BITS]);
    end
  endfunction

  function automatic logic [15:0] cr_sample_source(input logic [3:0] index);
    begin
      cr_sample_source = sample_to_source(cr_samples_q[(15 - index) * SAMPLE_BITS +: SAMPLE_BITS]);
    end
  endfunction

  function automatic logic [15:0] sample_to_source(input logic [SAMPLE_BITS - 1:0] sample);
    begin
      if (SOURCE_SAMPLE_BITS > SAMPLE_BITS) begin
        sample_to_source = sample << (SOURCE_SAMPLE_BITS - SAMPLE_BITS);
      end else if (SOURCE_SAMPLE_BITS < SAMPLE_BITS) begin
        sample_to_source = sample >> (SAMPLE_BITS - SOURCE_SAMPLE_BITS);
      end else begin
        sample_to_source = sample;
      end
    end
  endfunction

  function automatic logic [7:0] color_filler_payload_byte(input logic [8:0] index);
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

  function automatic logic [7:0] coeff_sideband_payload_byte(input logic [8:0] index);
    begin
      case (index)
        7'd0: coeff_sideband_payload_byte = 8'h46; // F
        7'd1: coeff_sideband_payload_byte = 8'h46; // F
        7'd2: coeff_sideband_payload_byte = 8'h41; // A
        7'd3: coeff_sideband_payload_byte = 8'h43; // C
        7'd4: coeff_sideband_payload_byte = 8'h81; // sideband version 1
        7'd5: coeff_sideband_payload_byte = 8'h4f; // 15 AC tokens
        7'd6: coeff_sideband_payload_byte = 8'h40 | {3'b000, quant_luma_rem()};
        7'd7, 7'd8, 7'd9, 7'd10, 7'd11, 7'd12, 7'd13, 7'd14,
        7'd15, 7'd16, 7'd17, 7'd18, 7'd19, 7'd20, 7'd21:
          coeff_sideband_payload_byte = quant_luma_ac_tokens_q[(21 - index) * 8 +: 8];
        7'd22: coeff_sideband_payload_byte = 8'h80;
        default: coeff_sideband_payload_byte = 8'h00;
      endcase
    end
  endfunction

  function automatic logic [7:0] sps_payload_byte(input logic [8:0] index);
    logic [247:0] payload_bits;

    begin
      payload_bits = sps_payload_bits();
      if (index < 7'd31) begin
        sps_payload_byte = payload_bits >> ((7'd30 - index) * 8);
      end else begin
        sps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [7:0] pps_payload_byte(input logic [8:0] index);
    logic [111:0] payload_bits;

    begin
      payload_bits = pps_payload_bits();
      if (index < 7'd14) begin
        pps_payload_byte = payload_bits >> ((7'd13 - index) * 8);
      end else begin
        pps_payload_byte = 8'h00;
      end
    end
  endfunction

  function automatic logic [247:0] sps_payload_bits();
    begin
      sps_payload_bits = {
        // sps_seq_parameter_set_id, sps_video_parameter_set_id,
        // sps_max_sub_layers_minus1, sps_chroma_format_idc,
        // sps_log2_ctu_size_minus5, sps_ptl_dpb_hrd_params_present_flag.
        16'h000b,
        // profile_tier_level prefix and general constraints for the toy stream.
        32'h0200_8000,
        // ptl_num_sub_profiles, SPS picture size, conformance window, and
        // early SPS tool flags through sps_entry_point_offsets_present_flag.
        64'h4244_eed5_01f4_46e8,
        // POC/extra-header/DPB fields and intra/inter partition constraints.
        64'h8468_8424_6136_28c5,
        // Transform, chroma QP table, prediction-tool, intra-tool, and
        // extension/trailing fields for the current 4x4 all-intra target.
        72'h4306_80ab_8fe0_ac10_20
      };
    end
  endfunction

  function automatic logic [111:0] pps_payload_bits();
    begin
      pps_payload_bits = {
        // PPS ids, 8x8 coded canvas for 4x4 conformance-cropped output, no
        // picture partitioning, and default reference index syntax.
        48'h0002_448a_4200,
        // QP/chroma/deblocking syntax and rbsp_trailing_bits for the toy stream.
        64'hc7b2_1459_4594_5880
      };
    end
  endfunction

  function automatic logic [7:0] slice_payload_byte(
    input logic [6:0] index,
    input logic       cra_picture
  );
    begin
      slice_payload_byte = quant_luma_payload_byte(quant_luma_rem(), index, cra_picture);
    end
  endfunction

  function automatic logic [7:0] quant_luma_payload_byte(
    input logic [4:0] rem,
    input logic [6:0] index,
    input logic       cra_picture
  );
    logic [87:0] payload;

    begin
      payload = toy_slice_payload_bits(rem, cra_picture);
      case (slice_payload_len())
        8'd9: quant_luma_payload_byte = payload >> ((7'd8 - index) * 8);
        8'd10: quant_luma_payload_byte = payload >> ((7'd9 - index) * 8);
        default: quant_luma_payload_byte = payload >> ((7'd10 - index) * 8);
      endcase
    end
  endfunction

  function automatic logic [87:0] toy_slice_payload_bits(
    input logic [4:0] rem,
    input logic       cra_picture
  );
    logic [127:0] acc;
    logic [7:0]   bit_len;
    logic [135:0] cabac;
    logic [95:0]  cabac_bits;
    logic [7:0]   cabac_len;
    logic [7:0]   payload_bits_len;
    logic [7:0]   payload_byte_len;

    begin
      acc = '0;
      bit_len = 8'd0;

      acc = (acc << 19) | slice_header_bits(cra_picture);
      bit_len = bit_len + 8'd19;

      acc = (acc << 1) | 1'b1; // cabac_alignment_one_bit
      bit_len = bit_len + 8'd1;
      if (cra_picture) begin
        acc = (acc << 1) | 1'b1; // current CRA slice alignment bit
        bit_len = bit_len + 8'd1;
      end
      while (bit_len[2:0] != 3'd0) begin
        acc = acc << 1;
        bit_len = bit_len + 8'd1;
      end

      cabac = toy_cabac_bitstream(rem);
      cabac_len = cabac[135:128];
      cabac_bits = cabac[95:0];
      acc = (acc << cabac_len) | cabac_bits;
      bit_len = bit_len + cabac_len;

      acc = (acc << 1) | 1'b1; // rbsp_stop_one_bit
      bit_len = bit_len + 8'd1;
      while (bit_len[2:0] != 3'd0) begin
        acc = acc << 1;
        bit_len = bit_len + 8'd1;
      end

      payload_byte_len = slice_payload_len();
      payload_bits_len = payload_byte_len << 3;
      toy_slice_payload_bits = acc << (payload_bits_len - bit_len);
    end
  endfunction

  function automatic logic [135:0] toy_cabac_bitstream(input logic [4:0] rem);
    logic [255:0] st;

    begin
      st = cabac_start();
      st = cabac_encode_ctx_bins(st, 5'd0,  8'b0000_0101, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd4,  8'b0000_0010, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd8,  8'b0000_0001, 4'd1);
      st = cabac_encode_rem_abs_ep(st, rem, 3'd0);
      st = cabac_encode_bin_ep(st, 1'b1);
      st = cabac_encode_ctx_bins(st, 5'd9,  8'b0000_1011, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd13, 8'b0000_0100, 4'd3);
      st = cabac_encode_ctx_bins(st, 5'd16, 8'b0000_0101, 4'd3);
      st = cabac_encode_rem_abs_ep(st, quant_chroma_rem(), 3'd0);
      st = cabac_encode_bin_ep(st, 1'b1);
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      toy_cabac_bitstream = { st[103:96], 32'd0, st[95:0] };
    end
  endfunction

  function automatic logic [255:0] cabac_start();
    begin
      cabac_start = '0;
      cabac_start[135:104] = 32'd0;   // low
      cabac_start[151:136] = 16'd510; // range
      cabac_start[160:152] = 9'h0ff;  // buffered_byte
      cabac_start[168:161] = 8'd0;    // num_buffered_bytes
      cabac_start[176:169] = 8'd23;   // bits_left
    end
  endfunction

  function automatic logic [255:0] cabac_encode_ctx_bins(
    input logic [255:0] st_in,
    input logic [4:0]   ctx_offset,
    input logic [7:0]   bin_pattern,
    input logic [3:0]   num_bins
  );
    logic [255:0] st;
    integer i;

    begin
      st = st_in;
      for (i = 0; i < num_bins; i = i + 1) begin
        st = cabac_encode_bin(
          st,
          bin_pattern[num_bins - 1 - i],
          toy_ctx_lps(ctx_offset + i[4:0]),
          toy_ctx_mps(ctx_offset + i[4:0])
        );
      end
      cabac_encode_ctx_bins = st;
    end
  endfunction

  function automatic logic [255:0] cabac_encode_bin(
    input logic [255:0] st_in,
    input logic         bin,
    input logic [8:0]   lps_in,
    input logic         mps
  );
    logic [255:0] st;
    logic [31:0] low;
    logic [15:0] range;
    logic [8:0]  lps;
    integer bits_left;
    integer num_bits;

    begin
      st = st_in;
      low = st[135:104];
      range = st[151:136];
      bits_left = st[176:169];
      lps = lps_in;

      range = range - lps;
      if (bin != mps) begin
        num_bits = renorm_bits_sv(lps);
        bits_left = bits_left - num_bits;
        low = low + range;
        low = low << num_bits;
        range = lps << num_bits;
        st[135:104] = low;
        st[151:136] = range;
        st[176:169] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else if (range < 16'd256) begin
        num_bits = renorm_bits_sv(range);
        bits_left = bits_left - num_bits;
        low = low << num_bits;
        range = range << num_bits;
        st[135:104] = low;
        st[151:136] = range;
        st[176:169] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else begin
        st[151:136] = range;
      end
      cabac_encode_bin = st;
    end
  endfunction

  function automatic logic [255:0] cabac_encode_bin_ep(
    input logic [255:0] st_in,
    input logic         bin
  );
    logic [255:0] st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;

    begin
      st = st_in;
      low = st[135:104] << 1;
      range = st[151:136];
      bits_left = st[176:169] - 1;
      if (bin) begin
        low = low + range;
      end
      st[135:104] = low;
      st[176:169] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_ep = st;
    end
  endfunction

  function automatic logic [255:0] cabac_encode_bins_ep(
    input logic [255:0] st_in,
    input logic [31:0]  bin_pattern_in,
    input logic [5:0]   num_bins_in
  );
    logic [255:0] st;
    logic [31:0] low;
    logic [31:0] bin_pattern;
    logic [15:0] range;
    logic [31:0] pattern;
    integer bits_left;
    integer num_bins;

      begin
      st = st_in;
      bin_pattern = bin_pattern_in;
      num_bins = num_bins_in;
      low = st[135:104];
      range = st[151:136];
      bits_left = st[176:169];

      while (num_bins > 8) begin
        num_bins = num_bins - 8;
        pattern = bin_pattern >> num_bins;
        low = low << 8;
        low = low + (range * pattern);
        bin_pattern = bin_pattern - (pattern << num_bins);
        bits_left = bits_left - 8;
        st[135:104] = low;
        st[176:169] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
          low = st[135:104];
          bits_left = st[176:169];
        end
      end

      low = low << num_bins;
      low = low + (range * bin_pattern);
      bits_left = bits_left - num_bins;
      st[135:104] = low;
      st[176:169] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bins_ep = st;
    end
  endfunction

  function automatic logic [255:0] cabac_encode_rem_abs_ep(
    input logic [255:0] st_in,
    input logic [4:0]   value,
    input logic [2:0]   rice_param
  );
    logic [255:0] st;
    logic [5:0] threshold;
    logic [5:0] length;
    logic [5:0] code_value;
    logic [5:0] prefix_length;
    logic [5:0] total_prefix_length;
    logic [5:0] suffix_length;
    logic [31:0] prefix;
    logic [31:0] suffix;

    begin
      st = st_in;
      threshold = 6'd5 << rice_param;
      if (value < threshold) begin
        length = (value >> rice_param) + 6'd1;
        st = cabac_encode_bins_ep(st, (32'd1 << length) - 32'd2, length);
        st = cabac_encode_bins_ep(st, value & ((32'd1 << rice_param) - 32'd1), rice_param);
      end else begin
        code_value = (value >> rice_param) - 6'd5;
        prefix_length = 6'd0;
        while (code_value > ((6'd2 << prefix_length) - 6'd2)) begin
          prefix_length = prefix_length + 6'd1;
        end
        total_prefix_length = prefix_length + 6'd5;
        suffix_length = prefix_length + rice_param + 6'd1;
        prefix = (32'd1 << total_prefix_length) - 32'd1;
        suffix = ((code_value - ((6'd1 << prefix_length) - 6'd1)) << rice_param)
          | (value & ((32'd1 << rice_param) - 32'd1));
        st = cabac_encode_bins_ep(st, prefix, total_prefix_length);
        st = cabac_encode_bins_ep(st, suffix, suffix_length);
      end
      cabac_encode_rem_abs_ep = st;
    end
  endfunction

  function automatic logic [255:0] cabac_encode_bin_trm(
    input logic [255:0] st_in,
    input logic         bin
  );
    logic [255:0] st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;

    begin
      st = st_in;
      low = st[135:104];
      range = st[151:136] - 16'd2;
      bits_left = st[176:169];
      if (bin) begin
        low = low + range;
        low = low << 7;
        range = 16'd256;
        bits_left = bits_left - 7;
      end else if (range < 16'd256) begin
        low = low << 1;
        range = range << 1;
        bits_left = bits_left - 1;
      end
      st[135:104] = low;
      st[151:136] = range;
      st[176:169] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_trm = st;
    end
  endfunction

  function automatic logic [255:0] cabac_finish(input logic [255:0] st_in);
    logic [255:0] st;
    logic [31:0] low;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    integer bits_left;
    integer final_bits;

    begin
      st = st_in;
      low = st[135:104];
      buffered_byte = st[160:152];
      num_buffered_bytes = st[168:161];
      bits_left = st[176:169];

      if ((low >> (32 - bits_left)) != 0) begin
        st = cabac_write_bits(st, buffered_byte + 9'd1, 6'd8);
        num_buffered_bytes = st[168:161];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'd0, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[168:161] = num_buffered_bytes;
        end
        low = low - (32'd1 << (32 - bits_left));
        st[135:104] = low;
      end else begin
        if (num_buffered_bytes > 8'd0) begin
          st = cabac_write_bits(st, buffered_byte, 6'd8);
        end
        num_buffered_bytes = st[168:161];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'h0ff, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[168:161] = num_buffered_bytes;
        end
      end

      final_bits = 24 - bits_left;
      if (final_bits > 0) begin
        st = cabac_write_bits(st, low >> 8, final_bits[5:0]);
      end
      cabac_finish = st;
    end
  endfunction

  function automatic logic [255:0] cabac_write_out(input logic [255:0] st_in);
    logic [255:0] st;
    logic [31:0] low;
    logic [31:0] lead_byte;
    logic [31:0] mask;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    logic [8:0] byte_value;
    logic [8:0] repeated_byte;
    logic [8:0] carry;
    integer bits_left;

    begin
      st = st_in;
      low = st[135:104];
      bits_left = st[176:169];
      buffered_byte = st[160:152];
      num_buffered_bytes = st[168:161];
      lead_byte = low >> (24 - bits_left);
      bits_left = bits_left + 8;
      mask = 32'hffff_ffff >> bits_left;
      low = low & mask;

      if (lead_byte == 32'hff) begin
        num_buffered_bytes = num_buffered_bytes + 8'd1;
      end else if (num_buffered_bytes > 8'd0) begin
        carry = lead_byte >> 8;
        byte_value = buffered_byte + carry;
        buffered_byte = lead_byte[7:0];
        st[135:104] = low;
        st[160:152] = buffered_byte;
        st[168:161] = num_buffered_bytes;
        st[176:169] = bits_left[7:0];
        st = cabac_write_bits(st, byte_value, 6'd8);
        repeated_byte = (9'h0ff + carry) & 9'h0ff;
        num_buffered_bytes = st[168:161];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, repeated_byte, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[168:161] = num_buffered_bytes;
        end
      end else begin
        num_buffered_bytes = 8'd1;
        buffered_byte = lead_byte[7:0];
      end

      st[135:104] = low;
      st[160:152] = buffered_byte;
      st[168:161] = num_buffered_bytes;
      st[176:169] = bits_left[7:0];
      cabac_write_out = st;
    end
  endfunction

  function automatic logic [255:0] cabac_write_bits(
    input logic [255:0] st_in,
    input logic [31:0]  value,
    input logic [5:0]   bit_count
  );
    logic [255:0] st;
    logic [95:0] bits;
    logic [7:0] len;
    integer i;

    begin
      st = st_in;
      bits = st[95:0];
      len = st[103:96];
      for (i = bit_count - 1; i >= 0; i = i - 1) begin
        bits = (bits << 1) | value[i];
        len = len + 8'd1;
      end
      st[95:0] = bits;
      st[103:96] = len;
      cabac_write_bits = st;
    end
  endfunction

  function automatic logic [3:0] renorm_bits_sv(input logic [15:0] range_in);
    logic [15:0] range;
    logic [3:0] count;

    begin
      range = range_in;
      count = 4'd0;
      while (range < 16'd256) begin
        range = range << 1;
        count = count + 4'd1;
      end
      renorm_bits_sv = count;
    end
  endfunction

  function automatic logic [8:0] toy_ctx_lps(input logic [4:0] index);
    begin
      case (index)
        5'd0: toy_ctx_lps = 9'd146;
        5'd1: toy_ctx_lps = 9'd81;
        5'd2: toy_ctx_lps = 9'd128;
        5'd3: toy_ctx_lps = 9'd52;
        5'd4: toy_ctx_lps = 9'd160;
        5'd5: toy_ctx_lps = 9'd129;
        5'd6: toy_ctx_lps = 9'd24;
        5'd7: toy_ctx_lps = 9'd58;
        5'd8: toy_ctx_lps = 9'd29;
        5'd9: toy_ctx_lps = 9'd172;
        5'd10: toy_ctx_lps = 9'd107;
        5'd11: toy_ctx_lps = 9'd136;
        5'd12: toy_ctx_lps = 9'd128;
        5'd13: toy_ctx_lps = 9'd125;
        5'd14: toy_ctx_lps = 9'd184;
        5'd15: toy_ctx_lps = 9'd112;
        5'd16: toy_ctx_lps = 9'd28;
        5'd17: toy_ctx_lps = 9'd67;
        default: toy_ctx_lps = 9'd26;
      endcase
    end
  endfunction

  function automatic logic toy_ctx_mps(input logic [4:0] index);
    begin
      case (index)
        5'd0: toy_ctx_mps = 1'b0;
        5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd9, 5'd12: toy_ctx_mps = 1'b1;
        default: toy_ctx_mps = 1'b0;
      endcase
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
