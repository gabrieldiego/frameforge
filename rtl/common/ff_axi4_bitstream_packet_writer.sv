`timescale 1ns/1ps

module ff_axi4_bitstream_packet_writer #(
  parameter int AXI_ADDR_BITS = 32,
  parameter int AXI_DATA_BITS = 128,
  parameter int BURST_MAX_BEATS = 4,
  parameter int FIFO_WORDS = BURST_MAX_BEATS * 2
) (
  input  logic                     clk,
  input  logic                     rst_n,
  input  logic                     start,
  input  logic [AXI_ADDR_BITS-1:0] dst_base,
  input  logic [31:0]              dst_capacity,

  input  logic                     s_axis_valid,
  output logic                     s_axis_ready,
  input  logic [AXI_DATA_BITS-1:0] s_axis_data,
  input  logic [$clog2((AXI_DATA_BITS/8)+1)-1:0] s_axis_count,
  input  logic                     s_axis_last,

  output logic                     m_axi_awvalid,
  input  logic                     m_axi_awready,
  output logic [AXI_ADDR_BITS-1:0] m_axi_awaddr,
  output logic [7:0]               m_axi_awlen,
  output logic [2:0]               m_axi_awsize,
  output logic [1:0]               m_axi_awburst,
  output logic                     m_axi_wvalid,
  input  logic                     m_axi_wready,
  output logic [AXI_DATA_BITS-1:0] m_axi_wdata,
  output logic [(AXI_DATA_BITS/8)-1:0] m_axi_wstrb,
  output logic                     m_axi_wlast,
  input  logic                     m_axi_bvalid,
  output logic                     m_axi_bready,
  input  logic [1:0]               m_axi_bresp,

  output logic [31:0]              bytes_written,
  output logic                     frame_done,
  output logic                     busy,
  output logic                     error
);
  localparam int AXI_BYTES = AXI_DATA_BITS / 8;
  localparam int AXI_BYTE_COUNT_BITS = $clog2(AXI_BYTES + 1);
  localparam int BURST_COUNT_BITS = $clog2(BURST_MAX_BEATS + 1);
  localparam int FIFO_COUNT_BITS = $clog2(FIFO_WORDS + 1);
  localparam int FIFO_INDEX_BITS = (FIFO_WORDS <= 1) ? 1 : $clog2(FIFO_WORDS);
  localparam logic [BURST_COUNT_BITS-1:0] BURST_MAX_BEATS_VALUE = BURST_MAX_BEATS;
  localparam logic [FIFO_COUNT_BITS-1:0] FIFO_WORDS_VALUE = FIFO_WORDS;
  localparam logic [AXI_BYTE_COUNT_BITS:0] AXI_BYTES_VALUE = AXI_BYTES;
  localparam int AXI_BYTE_SHIFT =
    (AXI_BYTES <= 1) ? 0 :
    (AXI_BYTES <= 2) ? 1 :
    (AXI_BYTES <= 4) ? 2 :
    (AXI_BYTES <= 8) ? 3 :
    (AXI_BYTES <= 16) ? 4 :
    (AXI_BYTES <= 32) ? 5 :
    6;
  localparam logic [2:0] AXI_SIZE = AXI_BYTE_SHIFT;

  typedef enum logic [1:0] {
    TX_IDLE,
    TX_AW,
    TX_W,
    TX_B
  } tx_state_t;

  tx_state_t tx_state_q;
  logic run_q;
  logic [AXI_DATA_BITS-1:0] word_q;
  logic [AXI_BYTES-1:0] strobe_q;
  logic [AXI_DATA_BITS-1:0] fifo_data_q [0:FIFO_WORDS-1];
  logic [AXI_BYTES-1:0] fifo_strobe_q [0:FIFO_WORDS-1];
  logic [AXI_BYTE_COUNT_BITS-1:0] byte_count_q;
  logic [FIFO_COUNT_BITS-1:0] fifo_count_q;
  logic [FIFO_INDEX_BITS-1:0] fifo_wr_ptr_q;
  logic [FIFO_INDEX_BITS-1:0] fifo_rd_ptr_q;
  logic [BURST_COUNT_BITS-1:0] tx_count_q;
  logic [BURST_COUNT_BITS-1:0] tx_remaining_q;
  logic tx_pending_last_q;
  logic final_seen_q;
  logic [31:0] write_offset_q;
  logic [AXI_DATA_BITS-1:0] next_word_w;
  logic [AXI_BYTES-1:0] next_strobe_w;
  logic [AXI_BYTE_COUNT_BITS-1:0] s_axis_count_safe_w;
  logic s_axis_count_valid_w;
  logic [AXI_BYTE_COUNT_BITS:0] packet_count_sum_w;
  logic [31:0] packet_byte_advance_w;
  logic capacity_ok_w;
  logic fifo_has_room_w;
  logic flush_input_w;
  logic take_word_w;
  logic enqueue_word_w;
  logic dequeue_word_w;
  logic final_available_w;
  logic start_burst_w;
  logic [FIFO_COUNT_BITS-1:0] fifo_count_after_pop_w;
  logic [FIFO_COUNT_BITS-1:0] fifo_count_after_activity_w;
  logic [FIFO_INDEX_BITS-1:0] fifo_wr_ptr_next_w;
  logic [FIFO_INDEX_BITS-1:0] fifo_rd_ptr_next_w;
  logic [BURST_COUNT_BITS-1:0] start_burst_count_w;
  logic [31:0] tx_byte_advance_w;
  logic [AXI_BYTES-1:0] packet_strobe_unshifted_w;
  logic [AXI_BYTES-1:0] packet_strobe_shifted_w;
  logic [AXI_DATA_BITS-1:0] packet_data_masked_w;
  logic [AXI_DATA_BITS-1:0] packet_data_shifted_w;
  logic [7:0] packet_shift_bits_w;
  logic invalid_axis_count_w;
  integer packet_i;
  integer axis_count_i;
  integer clear_i;

  assign busy =
    run_q ||
    (tx_state_q != TX_IDLE) ||
    (fifo_count_q != '0) ||
    (byte_count_q != '0);
  assign m_axi_awaddr = dst_base + write_offset_q;
  assign m_axi_awlen = {{(8-BURST_COUNT_BITS){1'b0}}, tx_count_q} - 8'd1;
  assign m_axi_awsize = AXI_SIZE;
  assign m_axi_awburst = 2'b01;
  assign m_axi_wdata = fifo_data_q[fifo_rd_ptr_q];
  assign m_axi_wstrb = fifo_strobe_q[fifo_rd_ptr_q];
  assign m_axi_wlast = (tx_remaining_q == BURST_COUNT_BITS'(1));
  always @* begin
    s_axis_count_safe_w = '0;
    s_axis_count_valid_w = 1'b0;
    for (axis_count_i = 0; axis_count_i <= AXI_BYTES; axis_count_i = axis_count_i + 1) begin
      if (s_axis_count == axis_count_i[AXI_BYTE_COUNT_BITS-1:0]) begin
        s_axis_count_safe_w = axis_count_i[AXI_BYTE_COUNT_BITS-1:0];
        s_axis_count_valid_w = 1'b1;
      end
    end
  end

  assign packet_byte_advance_w =
    {{(32-AXI_BYTE_COUNT_BITS){1'b0}}, s_axis_count_safe_w};
  assign capacity_ok_w =
    (dst_capacity == 32'd0) ||
    ((bytes_written + packet_byte_advance_w) <= dst_capacity);
  assign fifo_has_room_w = (fifo_count_q < FIFO_WORDS_VALUE) || dequeue_word_w;
  assign packet_count_sum_w =
    {1'b0, byte_count_q} + {1'b0, s_axis_count_safe_w};
  assign flush_input_w =
    s_axis_valid &&
    ((packet_count_sum_w >= AXI_BYTES_VALUE) || s_axis_last);
  assign s_axis_ready =
    run_q &&
    !final_seen_q &&
    capacity_ok_w &&
    (!flush_input_w || fifo_has_room_w);
  assign take_word_w =
    s_axis_valid &&
    s_axis_ready &&
    s_axis_count_valid_w &&
    (s_axis_count_safe_w != '0);
  assign invalid_axis_count_w =
    s_axis_valid && s_axis_count_valid_w === 1'b0;
  assign enqueue_word_w =
    take_word_w &&
    ((packet_count_sum_w >= AXI_BYTES_VALUE) || s_axis_last);
  assign dequeue_word_w = m_axi_wvalid && m_axi_wready;
  assign fifo_wr_ptr_next_w =
    (fifo_wr_ptr_q == FIFO_INDEX_BITS'(FIFO_WORDS - 1)) ? '0 : (fifo_wr_ptr_q + 1'b1);
  assign fifo_rd_ptr_next_w =
    (fifo_rd_ptr_q == FIFO_INDEX_BITS'(FIFO_WORDS - 1)) ? '0 : (fifo_rd_ptr_q + 1'b1);
  assign fifo_count_after_pop_w =
    fifo_count_q - {{(FIFO_COUNT_BITS-1){1'b0}}, dequeue_word_w};
  assign fifo_count_after_activity_w =
    fifo_count_after_pop_w + {{(FIFO_COUNT_BITS-1){1'b0}}, enqueue_word_w};
  assign final_available_w = final_seen_q || (enqueue_word_w && s_axis_last);
  assign start_burst_w =
    (tx_state_q == TX_IDLE) &&
    (fifo_count_after_activity_w != '0) &&
    (final_available_w ||
      (fifo_count_after_activity_w >=
        {{(FIFO_COUNT_BITS-BURST_COUNT_BITS){1'b0}}, BURST_MAX_BEATS_VALUE}));
  assign start_burst_count_w =
    (fifo_count_after_activity_w >=
      {{(FIFO_COUNT_BITS-BURST_COUNT_BITS){1'b0}}, BURST_MAX_BEATS_VALUE}) ?
        BURST_MAX_BEATS_VALUE :
        fifo_count_after_activity_w[BURST_COUNT_BITS-1:0];
  assign tx_byte_advance_w =
    {{(32-BURST_COUNT_BITS-AXI_BYTE_SHIFT){1'b0}}, tx_count_q, {AXI_BYTE_SHIFT{1'b0}}};
  assign packet_strobe_unshifted_w =
    (s_axis_count_safe_w == '0) ?
      {AXI_BYTES{1'b0}} :
      ((AXI_BYTES'(1) << s_axis_count_safe_w) - AXI_BYTES'(1));
  assign packet_strobe_shifted_w = packet_strobe_unshifted_w << byte_count_q;
  assign packet_shift_bits_w = {3'd0, byte_count_q} << 3;
  assign packet_data_shifted_w = packet_data_masked_w << packet_shift_bits_w;

  always @* begin
    packet_data_masked_w = '0;
    for (packet_i = 0; packet_i < AXI_BYTES; packet_i = packet_i + 1) begin
      if (packet_strobe_unshifted_w[packet_i]) begin
        packet_data_masked_w[packet_i * 8 +: 8] =
          s_axis_data[packet_i * 8 +: 8];
      end
    end
    next_word_w = word_q | packet_data_shifted_w;
    next_strobe_w = strobe_q | packet_strobe_shifted_w;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_state_q <= TX_IDLE;
      run_q <= 1'b0;
      word_q <= '0;
      strobe_q <= '0;
      byte_count_q <= '0;
      fifo_count_q <= '0;
      fifo_wr_ptr_q <= '0;
      fifo_rd_ptr_q <= '0;
      tx_count_q <= '0;
      tx_remaining_q <= '0;
      tx_pending_last_q <= 1'b0;
      final_seen_q <= 1'b0;
      write_offset_q <= 32'd0;
      bytes_written <= 32'd0;
      frame_done <= 1'b0;
      error <= 1'b0;
      m_axi_awvalid <= 1'b0;
      m_axi_wvalid <= 1'b0;
      m_axi_bready <= 1'b0;
      for (clear_i = 0; clear_i < FIFO_WORDS; clear_i = clear_i + 1) begin
        fifo_data_q[clear_i] <= '0;
        fifo_strobe_q[clear_i] <= '0;
      end
    end else begin
      frame_done <= 1'b0;
      if (start) begin
        tx_state_q <= TX_IDLE;
        run_q <= 1'b1;
        word_q <= '0;
        strobe_q <= '0;
        byte_count_q <= '0;
        fifo_count_q <= '0;
        fifo_wr_ptr_q <= '0;
        fifo_rd_ptr_q <= '0;
        tx_count_q <= '0;
        tx_remaining_q <= '0;
        tx_pending_last_q <= 1'b0;
        final_seen_q <= 1'b0;
        write_offset_q <= 32'd0;
        bytes_written <= 32'd0;
        error <= 1'b0;
        m_axi_awvalid <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        for (clear_i = 0; clear_i < FIFO_WORDS; clear_i = clear_i + 1) begin
          fifo_data_q[clear_i] <= '0;
          fifo_strobe_q[clear_i] <= '0;
        end
      end else begin
        if (run_q && invalid_axis_count_w) begin
          error <= 1'b1;
        end
        if (take_word_w) begin
          bytes_written <= bytes_written + packet_byte_advance_w;
          if (enqueue_word_w) begin
            fifo_data_q[fifo_wr_ptr_q] <= next_word_w;
            fifo_strobe_q[fifo_wr_ptr_q] <= next_strobe_w;
            fifo_wr_ptr_q <= fifo_wr_ptr_next_w;
            word_q <= '0;
            strobe_q <= '0;
            byte_count_q <= '0;
            if (s_axis_last) begin
              final_seen_q <= 1'b1;
            end
          end else begin
            word_q <= next_word_w;
            strobe_q <= next_strobe_w;
            byte_count_q <= packet_count_sum_w[AXI_BYTE_COUNT_BITS-1:0];
          end
        end else if (run_q && s_axis_valid && !capacity_ok_w) begin
          error <= 1'b1;
        end

        if (dequeue_word_w) begin
          fifo_rd_ptr_q <= fifo_rd_ptr_next_w;
          tx_remaining_q <= tx_remaining_q - BURST_COUNT_BITS'(1);
        end

        case ({enqueue_word_w, dequeue_word_w})
          2'b10: fifo_count_q <= fifo_count_q + 1'b1;
          2'b01: fifo_count_q <= fifo_count_q - 1'b1;
          default: begin
          end
        endcase

        case (tx_state_q)
          TX_IDLE: begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;
            if (start_burst_w) begin
              tx_count_q <= start_burst_count_w;
              tx_remaining_q <= start_burst_count_w;
              tx_pending_last_q <= final_available_w &&
                (fifo_count_after_activity_w <=
                  {{(FIFO_COUNT_BITS-BURST_COUNT_BITS){1'b0}}, BURST_MAX_BEATS_VALUE});
              m_axi_awvalid <= 1'b1;
              tx_state_q <= TX_AW;
            end
          end
          TX_AW: begin
            if (m_axi_awvalid && m_axi_awready) begin
              m_axi_awvalid <= 1'b0;
              m_axi_wvalid <= 1'b1;
              tx_state_q <= TX_W;
            end
          end
          TX_W: begin
            if (m_axi_wvalid && m_axi_wready) begin
              if (m_axi_wlast) begin
                m_axi_wvalid <= 1'b0;
                m_axi_bready <= 1'b1;
                tx_state_q <= TX_B;
              end
            end
          end
          TX_B: begin
            if (m_axi_bvalid && m_axi_bready) begin
              m_axi_bready <= 1'b0;
              write_offset_q <= write_offset_q + tx_byte_advance_w;
              if (m_axi_bresp != 2'b00) begin
                error <= 1'b1;
              end
              if (tx_pending_last_q) begin
                frame_done <= 1'b1;
                run_q <= 1'b0;
                final_seen_q <= 1'b0;
              end
              tx_pending_last_q <= 1'b0;
              tx_state_q <= TX_IDLE;
            end
          end
          default: begin
            tx_state_q <= TX_IDLE;
          end
        endcase
      end
    end
  end
endmodule
