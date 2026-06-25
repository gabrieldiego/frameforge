`timescale 1ns/1ps

module ff_axi4_frame_reader #(
  parameter int AXI_ADDR_BITS = 32,
  parameter int AXI_DATA_BITS = 128,
  parameter int SAMPLE_BITS = 8,
  parameter int CTU_SIZE = 64,
  parameter int OUTPUT_SAMPLES = 1,
  // 0: VVC fixed-TU scan order, 1: raster 8x8 block order.
  parameter bit RASTER_BLOCK_ORDER = 1'b0,
  // Opportunistically overlap the next 4:2:0 read with the current response.
  // Keep this opt-in until each codec path has been audited for timing-sensitive
  // packet ordering assumptions.
  parameter bit ENABLE_420_PREFETCH = 1'b0
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       start,
  input  logic [15:0]                visible_width,
  input  logic [15:0]                visible_height,
  input  logic [1:0]                 chroma_format_idc,
  input  logic [15:0]                segment_origin_x,
  input  logic [15:0]                segment_origin_y,
  input  logic [15:0]                segment_width,
  input  logic [15:0]                segment_height,
  input  logic                       stream_last_on_segment_end,
  input  logic                       frame_last_segment,
  input  logic [AXI_ADDR_BITS-1:0]   src_y_base,
  input  logic [AXI_ADDR_BITS-1:0]   src_u_base,
  input  logic [AXI_ADDR_BITS-1:0]   src_v_base,
  input  logic [AXI_ADDR_BITS-1:0]   src_frame_offset,
  input  logic [31:0]                src_y_stride,
  input  logic [31:0]                src_u_stride,
  input  logic [31:0]                src_v_stride,

  output logic                       m_axi_arvalid,
  input  logic                       m_axi_arready,
  output logic [AXI_ADDR_BITS-1:0]   m_axi_araddr,
  output logic [7:0]                 m_axi_arlen,
  output logic [2:0]                 m_axi_arsize,
  output logic [1:0]                 m_axi_arburst,
  input  logic                       m_axi_rvalid,
  output logic                       m_axi_rready,
  input  logic [AXI_DATA_BITS-1:0]   m_axi_rdata,
  input  logic [1:0]                 m_axi_rresp,
  input  logic                       m_axi_rlast,

  output logic                       sample_valid,
  input  logic                       sample_ready,
  output logic [OUTPUT_SAMPLES*SAMPLE_BITS-1:0] sample_data,
  output logic [3:0]                 sample_count,
  output logic                       sample_last,
  output logic                       busy,
  output logic                       done,
  output logic                       error
);
  localparam int SAMPLE_BYTES = (SAMPLE_BITS + 7) / 8;
  localparam int SAMPLE_BYTE_SHIFT =
    (SAMPLE_BYTES <= 1) ? 0 :
    (SAMPLE_BYTES <= 2) ? 1 :
    (SAMPLE_BYTES <= 4) ? 2 :
    3;
  localparam int AXI_BYTES = AXI_DATA_BITS / 8;
  localparam int AXI_BYTE_SHIFT =
    (AXI_BYTES <= 1) ? 0 :
    (AXI_BYTES <= 2) ? 1 :
    (AXI_BYTES <= 4) ? 2 :
    (AXI_BYTES <= 8) ? 3 :
    (AXI_BYTES <= 16) ? 4 :
    (AXI_BYTES <= 32) ? 5 :
    6;
  localparam int AXI_BYTE_INDEX_BITS = (AXI_BYTES <= 1) ? 1 : $clog2(AXI_BYTES);
  localparam logic [2:0] AXI_SIZE = AXI_BYTE_SHIFT;
  localparam int CACHE_WORDS = 24;
  localparam int CACHE_INDEX_BITS = 5;
  localparam int OUTPUT_SAMPLES_CLAMPED =
    (OUTPUT_SAMPLES < 1) ? 1 :
    (OUTPUT_SAMPLES > 8) ? 8 :
    OUTPUT_SAMPLES;
  localparam logic [3:0] OUTPUT_SAMPLES_COUNT = OUTPUT_SAMPLES_CLAMPED;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_INIT_SEGMENT,
    ST_SKIP,
    ST_ADDR,
    ST_WAIT_R,
    ST_PAD,
    ST_VALID
  } state_t;

  state_t state_q;
  logic [5:0] scan_q;
  logic [2:0] raster_col_q;
  logic [2:0] raster_row_q;
  logic [6:0] leaf_count_q;
  logic [1:0] component_q;
  logic [5:0] sample_q;
  logic [2:0] vvc_col_w;
  logic [2:0] vvc_row_w;
  logic [2:0] leaf_col_w;
  logic [2:0] leaf_row_w;
  logic [3:0] active_cols_w;
  logic [3:0] active_rows_w;
  logic [6:0] active_leaf_count_w;
  logic leaf_active_w;
  logic component_last_w;
  logic sample_last_in_component_w;
  logic block_last_w;
  logic segment_last_w;
  logic output_last_w;
  logic [5:0] component_sample_last_w;
  logic [15:0] local_x_w;
  logic [15:0] local_y_w;
  logic [15:0] local_plane_x_w;
  logic [15:0] local_plane_y_w;
  logic [15:0] sample_x_w;
  logic [15:0] sample_y_w;
  logic [15:0] plane_x_w;
  logic [15:0] plane_y_w;
  logic [31:0] plane_stride_w;
  logic [AXI_ADDR_BITS-1:0] plane_stride_addr_w;
  logic [AXI_ADDR_BITS-1:0] plane_base_w;
  logic [AXI_ADDR_BITS-1:0] plane_segment_offset_w;
  logic [AXI_ADDR_BITS-1:0] plane_offset_w;
  logic [AXI_ADDR_BITS-1:0] row_offset_w;
  logic [AXI_ADDR_BITS-1:0] col_offset_w;
  logic [AXI_ADDR_BITS-1:0] sample_addr_w;
  logic [AXI_ADDR_BITS-1:0] axi_word_addr_w;
  logic [AXI_BYTE_INDEX_BITS-1:0] axi_byte_offset_w;
  logic [CACHE_WORDS-1:0] cache_valid_q;
  logic [AXI_ADDR_BITS-1:0] cache_addr_q [0:CACHE_WORDS-1];
  logic [AXI_DATA_BITS-1:0] cache_data_q [0:CACHE_WORDS-1];
  logic [CACHE_INDEX_BITS-1:0] cache_index_w;
  logic cache_hit_w;
  logic [AXI_DATA_BITS-1:0] cache_hit_data_w;
  logic [AXI_DATA_BITS-1:0] active_axi_word_q;
  logic [SAMPLE_BITS-1:0] pad_sample_w;
  logic in_visible_w;
  logic fast_next_same_row_w;
  logic fast_next_contiguous_row_w;
  logic fast_next_contiguous_addr_w;
  logic fast_next_same_axi_word_w;
  logic fast_next_visible_w;
  logic fast_next_sample_w;
  logic [5:0] next_sample_q_w;
  logic [15:0] next_local_x_w;
  logic [15:0] next_local_y_w;
  logic [AXI_BYTE_INDEX_BITS-1:0] next_axi_byte_offset_w;
  logic [15:0] next_sample_x_w;
  logic [15:0] next_sample_y_w;
  logic [15:0] next_plane_x_w;
  logic [15:0] next_plane_y_w;
  logic [31:0] packet_row_bytes_w;
  logic [15:0] packet_row_start_x_w;
  logic next_sample_last_in_component_w;
  logic next_component_last_w;
  logic next_output_last_w;
  logic [3:0] row_width_samples_w;
  logic [3:0] row_pos_w;
  logic [3:0] row_remaining_w;
  logic [31:0] axi_word_remaining_bytes_w;
  logic [4:0] axi_word_remaining_samples_w;
  logic [3:0] packet_candidate_count_w;
  logic [3:0] packet_count_w;
  logic [5:0] packet_last_sample_w;
  logic packet_sample_last_in_component_w;
  logic packet_component_last_w;
  logic packet_block_last_w;
  logic packet_segment_last_w;
  logic packet_output_last_w;
  logic packet_all_visible_w;
  logic [15:0] plane_visible_width_w;
  logic [15:0] plane_visible_height_w;
  logic [OUTPUT_SAMPLES*SAMPLE_BITS-1:0] packet_cache_data_w;
  logic [OUTPUT_SAMPLES*SAMPLE_BITS-1:0] packet_rdata_w;
  logic [OUTPUT_SAMPLES*SAMPLE_BITS-1:0] packet_pad_data_w;
  logic [5:0] advance_scan_w;
  logic [2:0] advance_raster_col_w;
  logic [2:0] advance_raster_row_w;
  logic [6:0] advance_leaf_count_w;
  logic [1:0] advance_component_w;
  logic [5:0] advance_sample_w;
  logic [2:0] advance_vvc_col_w;
  logic [2:0] advance_vvc_row_w;
  logic [2:0] advance_leaf_col_w;
  logic [2:0] advance_leaf_row_w;
  logic advance_leaf_active_w;
  logic [5:0] advance_component_sample_last_w;
  logic [15:0] advance_local_x_w;
  logic [15:0] advance_local_y_w;
  logic [15:0] advance_local_plane_x_w;
  logic [15:0] advance_local_plane_y_w;
  logic [15:0] advance_sample_x_w;
  logic [15:0] advance_sample_y_w;
  logic [15:0] advance_plane_x_w;
  logic [15:0] advance_plane_y_w;
  logic [31:0] advance_plane_stride_w;
  logic [AXI_ADDR_BITS-1:0] advance_plane_stride_addr_w;
  logic [AXI_ADDR_BITS-1:0] advance_plane_base_w;
  logic [AXI_ADDR_BITS-1:0] advance_plane_segment_offset_w;
  logic [AXI_ADDR_BITS-1:0] advance_row_offset_w;
  logic [AXI_ADDR_BITS-1:0] advance_col_offset_w;
  logic [AXI_ADDR_BITS-1:0] advance_plane_offset_w;
  logic [AXI_ADDR_BITS-1:0] advance_sample_addr_w;
  logic [AXI_ADDR_BITS-1:0] advance_axi_word_addr_w;
  logic [AXI_BYTE_INDEX_BITS-1:0] advance_axi_byte_offset_w;
  logic [CACHE_INDEX_BITS-1:0] advance_cache_index_w;
  logic advance_cache_hit_w;
  logic [AXI_DATA_BITS-1:0] advance_cache_hit_data_w;
  logic [SAMPLE_BITS-1:0] advance_pad_sample_w;
  logic advance_in_visible_w;
  logic [3:0] advance_row_width_samples_w;
  logic [3:0] advance_row_pos_w;
  logic [3:0] advance_row_remaining_w;
  logic [31:0] advance_axi_word_remaining_bytes_w;
  logic [4:0] advance_axi_word_remaining_samples_w;
  logic [3:0] advance_packet_candidate_count_w;
  logic [3:0] advance_packet_count_w;
  logic [5:0] advance_packet_last_sample_w;
  logic advance_packet_sample_last_in_component_w;
  logic advance_packet_component_last_w;
  logic advance_packet_block_last_w;
  logic advance_packet_segment_last_w;
  logic advance_packet_output_last_w;
  logic advance_packet_all_visible_w;
  logic [15:0] advance_plane_visible_width_w;
  logic [15:0] advance_plane_visible_height_w;
  logic [OUTPUT_SAMPLES*SAMPLE_BITS-1:0] advance_packet_cache_data_w;
  logic [OUTPUT_SAMPLES*SAMPLE_BITS-1:0] advance_packet_rdata_w;
  logic [OUTPUT_SAMPLES*SAMPLE_BITS-1:0] advance_packet_pad_data_w;
  logic arvalid_hold_q;
  logic [AXI_ADDR_BITS-1:0] araddr_hold_q;
  logic prefetch_enable_w;
  logic prefetch_pending_q;
  logic [AXI_ADDR_BITS-1:0] prefetch_addr_q;
  logic [CACHE_INDEX_BITS-1:0] prefetch_cache_index_q;
  logic sample_fire_w;
  logic current_read_request_w;
  logic advance_read_request_w;
  logic wait_r_prefetch_request_w;
  logic prefetch_response_w;
  logic advance_prefetch_response_hit_w;
  logic ar_request_valid_w;
  logic [AXI_ADDR_BITS-1:0] ar_request_addr_w;
  logic [AXI_ADDR_BITS-1:0] y_segment_offset_q;
  logic [AXI_ADDR_BITS-1:0] u_segment_offset_q;
  logic [AXI_ADDR_BITS-1:0] v_segment_offset_q;
  logic [AXI_ADDR_BITS-1:0] y_stride_shift_q;
  logic [AXI_ADDR_BITS-1:0] u_stride_shift_q;
  logic [AXI_ADDR_BITS-1:0] v_stride_shift_q;
  logic [15:0] y_origin_shift_q;
  logic [15:0] uv_origin_shift_q;
  logic [4:0] segment_init_bit_q;
  integer packet_i;

  assign busy = (state_q != ST_IDLE);
  assign sample_fire_w = sample_valid && sample_ready;
  assign prefetch_enable_w = ENABLE_420_PREFETCH && (chroma_format_idc == 2'd1);
  assign current_read_request_w =
    (state_q == ST_SKIP) && leaf_active_w && in_visible_w && !cache_hit_w;
  assign advance_read_request_w =
    sample_fire_w && !packet_segment_last_w &&
    advance_leaf_active_w && advance_in_visible_w && !advance_cache_hit_w;
  assign wait_r_prefetch_request_w =
    prefetch_enable_w &&
    (state_q == ST_WAIT_R) &&
    m_axi_rvalid &&
    m_axi_rready &&
    !prefetch_pending_q &&
    !packet_segment_last_w &&
    advance_leaf_active_w &&
    advance_in_visible_w &&
    !advance_cache_hit_w &&
    (advance_axi_word_addr_w != axi_word_addr_w);
  assign prefetch_response_w = prefetch_pending_q && m_axi_rvalid && m_axi_rready;
  assign advance_prefetch_response_hit_w =
    prefetch_response_w &&
    (prefetch_addr_q == advance_axi_word_addr_w) &&
    (prefetch_cache_index_q == advance_cache_index_w);
  assign ar_request_valid_w =
    !arvalid_hold_q &&
    !(prefetch_pending_q && !prefetch_response_w) &&
    (wait_r_prefetch_request_w ||
     advance_read_request_w ||
     current_read_request_w);
  assign ar_request_addr_w =
    wait_r_prefetch_request_w ? advance_axi_word_addr_w :
    (advance_read_request_w ? advance_axi_word_addr_w : axi_word_addr_w);
  assign m_axi_arvalid = arvalid_hold_q || ar_request_valid_w;
  assign m_axi_araddr = arvalid_hold_q ? araddr_hold_q : ar_request_addr_w;
  assign m_axi_arlen = 8'd0;
  assign m_axi_arsize = AXI_SIZE;
  assign m_axi_arburst = 2'b01;

  assign active_cols_w = (segment_width + 16'd7) >> 3;
  assign active_rows_w = (segment_height + 16'd7) >> 3;
  always_comb begin
    case (active_rows_w)
      4'd0: active_leaf_count_w = 7'd0;
      4'd1: active_leaf_count_w = {3'd0, active_cols_w};
      4'd2: active_leaf_count_w = {2'd0, active_cols_w, 1'b0};
      4'd3: active_leaf_count_w = {2'd0, active_cols_w, 1'b0} + {3'd0, active_cols_w};
      4'd4: active_leaf_count_w = {1'd0, active_cols_w, 2'b00};
      4'd5: active_leaf_count_w = {1'd0, active_cols_w, 2'b00} + {3'd0, active_cols_w};
      4'd6: active_leaf_count_w = {1'd0, active_cols_w, 2'b00} + {2'd0, active_cols_w, 1'b0};
      4'd7: active_leaf_count_w = {active_cols_w, 3'b000} - {3'd0, active_cols_w};
      default: active_leaf_count_w = {active_cols_w, 3'b000};
    endcase
  end
  // VVC fixed 8x8 leaf order is a Morton/Z scan. Use direct bit selects so
  // each concatenation operand is exactly one bit; shifted masks would widen
  // in Verilog and can silently drop the upper row bits.
  assign vvc_col_w = {scan_q[4], scan_q[2], scan_q[0]};
  assign vvc_row_w = {scan_q[5], scan_q[3], scan_q[1]};
  assign leaf_col_w = RASTER_BLOCK_ORDER ? raster_col_q : vvc_col_w;
  assign leaf_row_w = RASTER_BLOCK_ORDER ? raster_row_q : vvc_row_w;
  assign leaf_active_w =
    ({1'b0, leaf_col_w} < active_cols_w) &&
    ({1'b0, leaf_row_w} < active_rows_w);

  assign component_sample_last_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ? 6'd15 : 6'd63;
  assign sample_last_in_component_w = (sample_q == component_sample_last_w);
  assign component_last_w = (component_q == 2'd2) && sample_last_in_component_w;
  assign block_last_w =
    component_last_w &&
    (leaf_count_q == (active_leaf_count_w - 7'd1));
  assign segment_last_w = block_last_w;
  assign output_last_w = segment_last_w &&
    (stream_last_on_segment_end || frame_last_segment);

  assign local_x_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      {13'd0, sample_q[1:0]} :
      {13'd0, sample_q[2:0]};
  assign local_y_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      {12'd0, sample_q[5:2]} :
      {13'd0, sample_q[5:3]};
  assign local_plane_x_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      (({13'd0, leaf_col_w} << 2) + local_x_w) :
      (({13'd0, leaf_col_w} << 3) + local_x_w);
  assign local_plane_y_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      (({13'd0, leaf_row_w} << 2) + local_y_w) :
      (({13'd0, leaf_row_w} << 3) + local_y_w);
  assign sample_x_w =
    segment_origin_x + ({13'd0, leaf_col_w} << 3) + local_x_w;
  assign sample_y_w =
    segment_origin_y + ({13'd0, leaf_row_w} << 3) + local_y_w;
  assign plane_x_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      ((segment_origin_x >> 1) + local_plane_x_w) :
      sample_x_w;
  assign plane_y_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      ((segment_origin_y >> 1) + local_plane_y_w) :
      sample_y_w;
  assign plane_base_w =
    (component_q == 2'd0) ? src_y_base :
    (component_q == 2'd1) ? src_u_base :
    src_v_base;
  assign plane_stride_w =
    (component_q == 2'd0) ? src_y_stride :
    (component_q == 2'd1) ? src_u_stride :
    src_v_stride;
  assign plane_stride_addr_w = AXI_ADDR_BITS'(plane_stride_w);
  assign plane_segment_offset_w =
    (component_q == 2'd0) ? y_segment_offset_q :
    (component_q == 2'd1) ? u_segment_offset_q :
    v_segment_offset_q;
  // The full segment-origin row product is registered when a segment starts.
  // The packet path only multiplies the local row inside the 64x64 region,
  // avoiding the duplicated full-width y*stride DSP cones that were dominating
  // Vivado timing optimization.
  assign row_offset_w =
    (local_plane_y_w[0] ? plane_stride_addr_w : '0) +
    (local_plane_y_w[1] ? (plane_stride_addr_w << 1) : '0) +
    (local_plane_y_w[2] ? (plane_stride_addr_w << 2) : '0) +
    (local_plane_y_w[3] ? (plane_stride_addr_w << 3) : '0) +
    (local_plane_y_w[4] ? (plane_stride_addr_w << 4) : '0) +
    (local_plane_y_w[5] ? (plane_stride_addr_w << 5) : '0);
  assign col_offset_w = AXI_ADDR_BITS'(local_plane_x_w) << SAMPLE_BYTE_SHIFT;
  assign plane_offset_w = plane_segment_offset_w + row_offset_w + col_offset_w;
  assign sample_addr_w = plane_base_w + plane_offset_w;
  assign axi_byte_offset_w =
    (AXI_BYTES <= 1) ? '0 : sample_addr_w[AXI_BYTE_INDEX_BITS-1:0];
  assign axi_word_addr_w =
    (AXI_BYTES <= 1) ?
      sample_addr_w :
      {sample_addr_w[AXI_ADDR_BITS-1:AXI_BYTE_INDEX_BITS], {AXI_BYTE_INDEX_BITS{1'b0}}};
  always @* begin
    case (component_q)
      2'd0: cache_index_w = {2'd0, local_y_w[2:0]};
      2'd1: cache_index_w = {2'd1, local_y_w[2:0]};
      default: cache_index_w = {2'd2, local_y_w[2:0]};
    endcase
  end
  assign cache_hit_w =
    cache_valid_q[cache_index_w] && (cache_addr_q[cache_index_w] == axi_word_addr_w);
  assign cache_hit_data_w = cache_data_q[cache_index_w];
  assign pad_sample_w = (component_q == 2'd0) ? '0 : {{(SAMPLE_BITS-8){1'b0}}, 8'd128};
  assign in_visible_w =
    (sample_x_w < visible_width) &&
    (sample_y_w < visible_height) &&
    !((chroma_format_idc == 2'd1) && (component_q != 2'd0) &&
      ((plane_x_w >= (visible_width >> 1)) || (plane_y_w >= (visible_height >> 1))));
  assign row_width_samples_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ? 4'd4 : 4'd8;
  assign row_pos_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      {2'd0, sample_q[1:0]} :
      {1'b0, sample_q[2:0]};
  assign row_remaining_w = row_width_samples_w - row_pos_w;
  assign axi_word_remaining_bytes_w = AXI_BYTES - {28'd0, axi_byte_offset_w};
  assign axi_word_remaining_samples_w =
    (SAMPLE_BYTES <= 1) ?
      axi_word_remaining_bytes_w[4:0] :
      (axi_word_remaining_bytes_w >> SAMPLE_BYTE_SHIFT);
  always_comb begin
    packet_candidate_count_w = row_remaining_w;
    if (packet_candidate_count_w > OUTPUT_SAMPLES_COUNT) begin
      packet_candidate_count_w = OUTPUT_SAMPLES_COUNT;
    end
    if (packet_candidate_count_w > axi_word_remaining_samples_w) begin
      packet_candidate_count_w = axi_word_remaining_samples_w;
    end
    if (packet_candidate_count_w == 4'd0) begin
      packet_candidate_count_w = 4'd1;
    end
  end
  assign plane_visible_width_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      (visible_width >> 1) :
      visible_width;
  assign plane_visible_height_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      (visible_height >> 1) :
      visible_height;
  assign packet_all_visible_w =
    in_visible_w &&
    (plane_y_w < plane_visible_height_w) &&
    (({16'd0, plane_x_w} + {28'd0, packet_candidate_count_w}) <=
      {16'd0, plane_visible_width_w});
  assign packet_count_w =
    packet_all_visible_w ? packet_candidate_count_w : 4'd1;
  assign packet_last_sample_w = sample_q + {2'd0, packet_count_w} - 6'd1;
  assign packet_sample_last_in_component_w =
    (packet_last_sample_w == component_sample_last_w);
  assign packet_component_last_w =
    (component_q == 2'd2) && packet_sample_last_in_component_w;
  assign packet_block_last_w =
    packet_component_last_w &&
    (leaf_count_q == (active_leaf_count_w - 7'd1));
  assign packet_segment_last_w = packet_block_last_w;
  assign packet_output_last_w = packet_segment_last_w &&
    (stream_last_on_segment_end || frame_last_segment);
  always_comb begin
    packet_cache_data_w = '0;
    packet_rdata_w = '0;
    packet_pad_data_w = '0;
    for (packet_i = 0; packet_i < OUTPUT_SAMPLES; packet_i = packet_i + 1) begin
      if (packet_i < packet_count_w) begin
        packet_cache_data_w[packet_i * SAMPLE_BITS +: SAMPLE_BITS] =
          cache_hit_data_w[(axi_byte_offset_w + (packet_i * SAMPLE_BYTES)) * 8 +: SAMPLE_BITS];
        packet_rdata_w[packet_i * SAMPLE_BITS +: SAMPLE_BITS] =
          m_axi_rdata[(axi_byte_offset_w + (packet_i * SAMPLE_BYTES)) * 8 +: SAMPLE_BITS];
        packet_pad_data_w[packet_i * SAMPLE_BITS +: SAMPLE_BITS] = pad_sample_w;
      end
    end
  end
  assign fast_next_same_row_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      (sample_q[1:0] != 2'd3) :
      (sample_q[2:0] != 3'd7);
  assign next_sample_q_w = sample_q + 6'd1;
  assign next_local_x_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      {14'd0, next_sample_q_w[1:0]} :
      {13'd0, next_sample_q_w[2:0]};
  assign next_local_y_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      {12'd0, next_sample_q_w[5:2]} :
      {13'd0, next_sample_q_w[5:3]};
  assign next_sample_x_w =
    segment_origin_x + ({13'd0, leaf_col_w} << 3) + next_local_x_w;
  assign next_sample_y_w =
    segment_origin_y + ({13'd0, leaf_row_w} << 3) + next_local_y_w;
  assign next_plane_x_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      ((segment_origin_x >> 1) + ({13'd0, leaf_col_w} << 2) + next_local_x_w) :
      next_sample_x_w;
  assign next_plane_y_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      ((segment_origin_y >> 1) + ({13'd0, leaf_row_w} << 2) + next_local_y_w) :
      next_sample_y_w;
  assign packet_row_bytes_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      (32'd4 << SAMPLE_BYTE_SHIFT) :
      (32'd8 << SAMPLE_BYTE_SHIFT);
  assign packet_row_start_x_w =
    ((chroma_format_idc == 2'd1) && (component_q != 2'd0)) ?
      ((segment_origin_x >> 1) + ({13'd0, leaf_col_w} << 2)) :
      (segment_origin_x + ({13'd0, leaf_col_w} << 3));
  assign fast_next_contiguous_row_w =
    !fast_next_same_row_w &&
    !sample_last_in_component_w &&
    (next_plane_x_w == packet_row_start_x_w) &&
    (plane_stride_w == packet_row_bytes_w);
  assign fast_next_contiguous_addr_w =
    fast_next_same_row_w || fast_next_contiguous_row_w;
  assign fast_next_same_axi_word_w =
    fast_next_contiguous_addr_w &&
    (AXI_BYTES >= (2 * SAMPLE_BYTES)) &&
    ({1'b0, axi_byte_offset_w} <= (AXI_BYTES - (2 * SAMPLE_BYTES)));
  assign next_axi_byte_offset_w = axi_byte_offset_w + AXI_BYTE_INDEX_BITS'(SAMPLE_BYTES);
  assign fast_next_visible_w =
    (next_sample_x_w < visible_width) &&
    (next_sample_y_w < visible_height) &&
    !((chroma_format_idc == 2'd1) && (component_q != 2'd0) &&
      ((next_plane_x_w >= (visible_width >> 1)) || (next_plane_y_w >= (visible_height >> 1))));
  assign fast_next_sample_w =
    fast_next_same_axi_word_w &&
    fast_next_visible_w;
  assign next_sample_last_in_component_w =
    ((sample_q + 6'd1) == component_sample_last_w);
  assign next_component_last_w =
    (component_q == 2'd2) && next_sample_last_in_component_w;
  assign next_output_last_w =
    next_component_last_w &&
    (leaf_count_q == (active_leaf_count_w - 7'd1)) &&
    (stream_last_on_segment_end || frame_last_segment);

  always_comb begin
    advance_scan_w = scan_q;
    advance_raster_col_w = raster_col_q;
    advance_raster_row_w = raster_row_q;
    advance_leaf_count_w = leaf_count_q;
    advance_component_w = component_q;
    advance_sample_w = sample_q;

    if (packet_sample_last_in_component_w) begin
      advance_sample_w = 6'd0;
      if (component_q == 2'd2) begin
        advance_component_w = 2'd0;
        advance_leaf_count_w = leaf_count_q + 7'd1;
        if (RASTER_BLOCK_ORDER) begin
          if ({1'b0, raster_col_q} == (active_cols_w - 4'd1)) begin
            advance_raster_col_w = 3'd0;
            advance_raster_row_w = raster_row_q + 3'd1;
          end else begin
            advance_raster_col_w = raster_col_q + 3'd1;
          end
        end else begin
          advance_scan_w = scan_q + 6'd1;
        end
      end else begin
        advance_component_w = component_q + 2'd1;
      end
    end else begin
      advance_sample_w = sample_q + {2'd0, packet_count_w};
    end
  end

  assign advance_vvc_col_w = {advance_scan_w[4], advance_scan_w[2], advance_scan_w[0]};
  assign advance_vvc_row_w = {advance_scan_w[5], advance_scan_w[3], advance_scan_w[1]};
  assign advance_leaf_col_w = RASTER_BLOCK_ORDER ? advance_raster_col_w : advance_vvc_col_w;
  assign advance_leaf_row_w = RASTER_BLOCK_ORDER ? advance_raster_row_w : advance_vvc_row_w;
  assign advance_leaf_active_w =
    ({1'b0, advance_leaf_col_w} < active_cols_w) &&
    ({1'b0, advance_leaf_row_w} < active_rows_w);
  assign advance_component_sample_last_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ? 6'd15 : 6'd63;
  assign advance_local_x_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      {14'd0, advance_sample_w[1:0]} :
      {13'd0, advance_sample_w[2:0]};
  assign advance_local_y_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      {12'd0, advance_sample_w[5:2]} :
      {13'd0, advance_sample_w[5:3]};
  assign advance_local_plane_x_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      (({13'd0, advance_leaf_col_w} << 2) + advance_local_x_w) :
      (({13'd0, advance_leaf_col_w} << 3) + advance_local_x_w);
  assign advance_local_plane_y_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      (({13'd0, advance_leaf_row_w} << 2) + advance_local_y_w) :
      (({13'd0, advance_leaf_row_w} << 3) + advance_local_y_w);
  assign advance_sample_x_w =
    segment_origin_x + ({13'd0, advance_leaf_col_w} << 3) + advance_local_x_w;
  assign advance_sample_y_w =
    segment_origin_y + ({13'd0, advance_leaf_row_w} << 3) + advance_local_y_w;
  assign advance_plane_x_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      ((segment_origin_x >> 1) + advance_local_plane_x_w) :
      advance_sample_x_w;
  assign advance_plane_y_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      ((segment_origin_y >> 1) + advance_local_plane_y_w) :
      advance_sample_y_w;
  assign advance_plane_base_w =
    (advance_component_w == 2'd0) ? src_y_base :
    (advance_component_w == 2'd1) ? src_u_base :
    src_v_base;
  assign advance_plane_stride_w =
    (advance_component_w == 2'd0) ? src_y_stride :
    (advance_component_w == 2'd1) ? src_u_stride :
    src_v_stride;
  assign advance_plane_stride_addr_w = AXI_ADDR_BITS'(advance_plane_stride_w);
  assign advance_plane_segment_offset_w =
    (advance_component_w == 2'd0) ? y_segment_offset_q :
    (advance_component_w == 2'd1) ? u_segment_offset_q :
    v_segment_offset_q;
  assign advance_row_offset_w =
    (advance_local_plane_y_w[0] ? advance_plane_stride_addr_w : '0) +
    (advance_local_plane_y_w[1] ? (advance_plane_stride_addr_w << 1) : '0) +
    (advance_local_plane_y_w[2] ? (advance_plane_stride_addr_w << 2) : '0) +
    (advance_local_plane_y_w[3] ? (advance_plane_stride_addr_w << 3) : '0) +
    (advance_local_plane_y_w[4] ? (advance_plane_stride_addr_w << 4) : '0) +
    (advance_local_plane_y_w[5] ? (advance_plane_stride_addr_w << 5) : '0);
  assign advance_col_offset_w = AXI_ADDR_BITS'(advance_local_plane_x_w) << SAMPLE_BYTE_SHIFT;
  assign advance_plane_offset_w =
    advance_plane_segment_offset_w + advance_row_offset_w + advance_col_offset_w;
  assign advance_sample_addr_w = advance_plane_base_w + advance_plane_offset_w;
  assign advance_axi_byte_offset_w =
    (AXI_BYTES <= 1) ? '0 : advance_sample_addr_w[AXI_BYTE_INDEX_BITS-1:0];
  assign advance_axi_word_addr_w =
    (AXI_BYTES <= 1) ?
      advance_sample_addr_w :
      {advance_sample_addr_w[AXI_ADDR_BITS-1:AXI_BYTE_INDEX_BITS], {AXI_BYTE_INDEX_BITS{1'b0}}};
  assign advance_cache_index_w =
    (advance_component_w == 2'd0) ? {2'd0, advance_local_y_w[2:0]} :
    (advance_component_w == 2'd1) ? {2'd1, advance_local_y_w[2:0]} :
    {2'd2, advance_local_y_w[2:0]};
  assign advance_cache_hit_w =
    cache_valid_q[advance_cache_index_w] &&
    (cache_addr_q[advance_cache_index_w] == advance_axi_word_addr_w);
  assign advance_cache_hit_data_w = cache_data_q[advance_cache_index_w];
  assign advance_pad_sample_w =
    (advance_component_w == 2'd0) ? '0 : {{(SAMPLE_BITS-8){1'b0}}, 8'd128};
  assign advance_in_visible_w =
    (advance_sample_x_w < visible_width) &&
    (advance_sample_y_w < visible_height) &&
    !((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0) &&
      ((advance_plane_x_w >= (visible_width >> 1)) ||
       (advance_plane_y_w >= (visible_height >> 1))));
  assign advance_row_width_samples_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ? 4'd4 : 4'd8;
  assign advance_row_pos_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      {2'd0, advance_sample_w[1:0]} :
      {1'b0, advance_sample_w[2:0]};
  assign advance_row_remaining_w = advance_row_width_samples_w - advance_row_pos_w;
  assign advance_axi_word_remaining_bytes_w =
    AXI_BYTES - {28'd0, advance_axi_byte_offset_w};
  assign advance_axi_word_remaining_samples_w =
    (SAMPLE_BYTES <= 1) ?
      advance_axi_word_remaining_bytes_w[4:0] :
      (advance_axi_word_remaining_bytes_w >> SAMPLE_BYTE_SHIFT);
  always_comb begin
    advance_packet_candidate_count_w = advance_row_remaining_w;
    if (advance_packet_candidate_count_w > OUTPUT_SAMPLES_COUNT) begin
      advance_packet_candidate_count_w = OUTPUT_SAMPLES_COUNT;
    end
    if (advance_packet_candidate_count_w > advance_axi_word_remaining_samples_w) begin
      advance_packet_candidate_count_w = advance_axi_word_remaining_samples_w;
    end
    if (advance_packet_candidate_count_w == 4'd0) begin
      advance_packet_candidate_count_w = 4'd1;
    end
  end
  assign advance_plane_visible_width_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      (visible_width >> 1) :
      visible_width;
  assign advance_plane_visible_height_w =
    ((chroma_format_idc == 2'd1) && (advance_component_w != 2'd0)) ?
      (visible_height >> 1) :
      visible_height;
  assign advance_packet_all_visible_w =
    advance_in_visible_w &&
    (advance_plane_y_w < advance_plane_visible_height_w) &&
    (({16'd0, advance_plane_x_w} + {28'd0, advance_packet_candidate_count_w}) <=
      {16'd0, advance_plane_visible_width_w});
  assign advance_packet_count_w =
    advance_packet_all_visible_w ? advance_packet_candidate_count_w : 4'd1;
  assign advance_packet_last_sample_w =
    advance_sample_w + {2'd0, advance_packet_count_w} - 6'd1;
  assign advance_packet_sample_last_in_component_w =
    (advance_packet_last_sample_w == advance_component_sample_last_w);
  assign advance_packet_component_last_w =
    (advance_component_w == 2'd2) && advance_packet_sample_last_in_component_w;
  assign advance_packet_block_last_w =
    advance_packet_component_last_w &&
    (advance_leaf_count_w == (active_leaf_count_w - 7'd1));
  assign advance_packet_segment_last_w = advance_packet_block_last_w;
  assign advance_packet_output_last_w =
    advance_packet_segment_last_w &&
    (stream_last_on_segment_end || frame_last_segment);
  always_comb begin
    advance_packet_cache_data_w = '0;
    advance_packet_rdata_w = '0;
    advance_packet_pad_data_w = '0;
    for (int i = 0; i < OUTPUT_SAMPLES; i = i + 1) begin
      if (i < advance_packet_count_w) begin
        advance_packet_cache_data_w[i * SAMPLE_BITS +: SAMPLE_BITS] =
          advance_cache_hit_data_w[
            (advance_axi_byte_offset_w + (i * SAMPLE_BYTES)) * 8 +: SAMPLE_BITS];
        advance_packet_rdata_w[i * SAMPLE_BITS +: SAMPLE_BITS] =
          m_axi_rdata[(advance_axi_byte_offset_w + (i * SAMPLE_BYTES)) * 8 +: SAMPLE_BITS];
        advance_packet_pad_data_w[i * SAMPLE_BITS +: SAMPLE_BITS] = advance_pad_sample_w;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      scan_q <= 6'd0;
      raster_col_q <= 3'd0;
      raster_row_q <= 3'd0;
      leaf_count_q <= 7'd0;
      component_q <= 2'd0;
      sample_q <= 6'd0;
      arvalid_hold_q <= 1'b0;
      araddr_hold_q <= '0;
      prefetch_pending_q <= 1'b0;
      prefetch_addr_q <= '0;
      prefetch_cache_index_q <= '0;
      m_axi_rready <= 1'b0;
      sample_valid <= 1'b0;
      sample_data <= '0;
      sample_count <= 4'd0;
      sample_last <= 1'b0;
      active_axi_word_q <= '0;
      cache_valid_q <= '0;
      y_segment_offset_q <= '0;
      u_segment_offset_q <= '0;
      v_segment_offset_q <= '0;
      y_stride_shift_q <= '0;
      u_stride_shift_q <= '0;
      v_stride_shift_q <= '0;
      y_origin_shift_q <= 16'd0;
      uv_origin_shift_q <= 16'd0;
      segment_init_bit_q <= 5'd0;
      done <= 1'b0;
      error <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start) begin
        state_q <= ST_INIT_SEGMENT;
        scan_q <= 6'd0;
        raster_col_q <= 3'd0;
        raster_row_q <= 3'd0;
        leaf_count_q <= 7'd0;
        component_q <= 2'd0;
        sample_q <= 6'd0;
        arvalid_hold_q <= 1'b0;
        araddr_hold_q <= '0;
        prefetch_pending_q <= 1'b0;
        prefetch_addr_q <= '0;
        prefetch_cache_index_q <= '0;
        m_axi_rready <= 1'b0;
        sample_valid <= 1'b0;
        sample_count <= 4'd0;
        sample_last <= 1'b0;
        active_axi_word_q <= '0;
        cache_valid_q <= '0;
        y_segment_offset_q <=
          src_frame_offset + (AXI_ADDR_BITS'(segment_origin_x) << SAMPLE_BYTE_SHIFT);
        u_segment_offset_q <=
          src_frame_offset +
          (AXI_ADDR_BITS'((chroma_format_idc == 2'd1) ?
            (segment_origin_x >> 1) : segment_origin_x) << SAMPLE_BYTE_SHIFT);
        v_segment_offset_q <=
          src_frame_offset +
          (AXI_ADDR_BITS'((chroma_format_idc == 2'd1) ?
            (segment_origin_x >> 1) : segment_origin_x) << SAMPLE_BYTE_SHIFT);
        y_stride_shift_q <= AXI_ADDR_BITS'(src_y_stride);
        u_stride_shift_q <= AXI_ADDR_BITS'(src_u_stride);
        v_stride_shift_q <= AXI_ADDR_BITS'(src_v_stride);
        y_origin_shift_q <= segment_origin_y;
        uv_origin_shift_q <=
          (chroma_format_idc == 2'd1) ? (segment_origin_y >> 1) : segment_origin_y;
        segment_init_bit_q <= 5'd0;
        error <= 1'b0;
      end else begin
        if (prefetch_response_w) begin
          cache_valid_q[prefetch_cache_index_q] <= 1'b1;
          cache_addr_q[prefetch_cache_index_q] <= prefetch_addr_q;
          cache_data_q[prefetch_cache_index_q] <= m_axi_rdata;
          prefetch_pending_q <= 1'b0;
          m_axi_rready <= 1'b0;
          if (m_axi_rresp != 2'b00 || !m_axi_rlast) begin
            error <= 1'b1;
          end
        end

        if (sample_valid && sample_ready) begin
          sample_valid <= 1'b0;
          sample_last <= 1'b0;
          sample_count <= 4'd0;
          if (packet_segment_last_w) begin
            state_q <= ST_IDLE;
            done <= 1'b1;
          end else begin
            scan_q <= advance_scan_w;
            raster_col_q <= advance_raster_col_w;
            raster_row_q <= advance_raster_row_w;
            leaf_count_q <= advance_leaf_count_w;
            component_q <= advance_component_w;
            sample_q <= advance_sample_w;

            // Packet-aware lookahead: after a packet is accepted, immediately
            // prepare the next packet or issue its AXI read. The slow ST_SKIP
            // fallback remains for inactive Morton leaves in partial CTUs.
            if (advance_leaf_active_w) begin
              if (advance_in_visible_w) begin
                if (advance_prefetch_response_hit_w) begin
                  active_axi_word_q <= m_axi_rdata;
                  sample_data <= advance_packet_rdata_w;
                  sample_count <= advance_packet_count_w;
                  sample_last <= advance_packet_output_last_w;
                  sample_valid <= 1'b1;
                  state_q <= ST_VALID;
                end else if (advance_cache_hit_w) begin
                  active_axi_word_q <= advance_cache_hit_data_w;
                  sample_data <= advance_packet_cache_data_w;
                  sample_count <= advance_packet_count_w;
                  sample_last <= advance_packet_output_last_w;
                  sample_valid <= 1'b1;
                  state_q <= ST_VALID;
                end else begin
                  if (m_axi_arready) begin
                    m_axi_rready <= 1'b1;
                    state_q <= ST_WAIT_R;
                  end else begin
                    arvalid_hold_q <= 1'b1;
                    araddr_hold_q <= advance_axi_word_addr_w;
                    state_q <= ST_ADDR;
                  end
                end
              end else begin
                sample_data <= advance_packet_pad_data_w;
                sample_count <= advance_packet_count_w;
                sample_last <= advance_packet_output_last_w;
                sample_valid <= 1'b1;
                state_q <= ST_PAD;
              end
            end else begin
              state_q <= ST_SKIP;
            end
          end
        end

        case (state_q)
          ST_IDLE: begin
            arvalid_hold_q <= 1'b0;
            m_axi_rready <= 1'b0;
          end
          ST_INIT_SEGMENT: begin
            if (y_origin_shift_q[0]) begin
              y_segment_offset_q <= y_segment_offset_q + y_stride_shift_q;
            end
            if (uv_origin_shift_q[0]) begin
              u_segment_offset_q <= u_segment_offset_q + u_stride_shift_q;
              v_segment_offset_q <= v_segment_offset_q + v_stride_shift_q;
            end
            y_origin_shift_q <= {1'b0, y_origin_shift_q[15:1]};
            uv_origin_shift_q <= {1'b0, uv_origin_shift_q[15:1]};
            y_stride_shift_q <= y_stride_shift_q << 1;
            u_stride_shift_q <= u_stride_shift_q << 1;
            v_stride_shift_q <= v_stride_shift_q << 1;
            if (segment_init_bit_q == 5'd15) begin
              state_q <= ST_SKIP;
            end else begin
              segment_init_bit_q <= segment_init_bit_q + 5'd1;
            end
          end
          ST_SKIP: begin
            if (leaf_active_w) begin
              if (in_visible_w) begin
                if (cache_hit_w) begin
                  active_axi_word_q <= cache_hit_data_w;
                  sample_data <= packet_cache_data_w;
                  sample_count <= packet_count_w;
                  sample_last <= packet_output_last_w;
                  sample_valid <= 1'b1;
                  state_q <= ST_VALID;
                end else begin
                  if (m_axi_arready) begin
                    m_axi_rready <= 1'b1;
                    state_q <= ST_WAIT_R;
                  end else begin
                    arvalid_hold_q <= 1'b1;
                    araddr_hold_q <= axi_word_addr_w;
                    state_q <= ST_ADDR;
                  end
                end
              end else begin
                sample_data <= packet_pad_data_w;
                sample_count <= packet_count_w;
                sample_last <= packet_output_last_w;
                sample_valid <= 1'b1;
                state_q <= ST_PAD;
              end
            end else if (!RASTER_BLOCK_ORDER && scan_q != 6'd63) begin
              scan_q <= scan_q + 6'd1;
            end else begin
              state_q <= ST_IDLE;
              done <= 1'b1;
            end
          end
          ST_ADDR: begin
            if (m_axi_arvalid && m_axi_arready) begin
              arvalid_hold_q <= 1'b0;
              m_axi_rready <= 1'b1;
              state_q <= ST_WAIT_R;
            end
          end
          ST_WAIT_R: begin
            if (m_axi_rvalid && m_axi_rready) begin
              if (wait_r_prefetch_request_w && m_axi_arready) begin
                prefetch_pending_q <= 1'b1;
                prefetch_addr_q <= advance_axi_word_addr_w;
                prefetch_cache_index_q <= advance_cache_index_w;
                m_axi_rready <= 1'b1;
              end else begin
                m_axi_rready <= 1'b0;
              end
              cache_valid_q[cache_index_w] <= 1'b1;
              cache_addr_q[cache_index_w] <= axi_word_addr_w;
              cache_data_q[cache_index_w] <= m_axi_rdata;
              active_axi_word_q <= m_axi_rdata;
              sample_data <= packet_rdata_w;
              sample_count <= packet_count_w;
              sample_last <= packet_output_last_w;
              sample_valid <= 1'b1;
              state_q <= ST_VALID;
              if (m_axi_rresp != 2'b00 || !m_axi_rlast) begin
                error <= 1'b1;
              end
            end
          end
          ST_PAD: begin
          end
          ST_VALID: begin
          end
          default: begin
            state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end
endmodule
