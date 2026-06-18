`timescale 1ns/1ps

module ff_axi4_bitstream_writer #(
  parameter int AXI_ADDR_BITS = 32,
  parameter int AXI_DATA_BITS = 128
) (
  input  logic                     clk,
  input  logic                     rst_n,
  input  logic                     start,
  input  logic [AXI_ADDR_BITS-1:0] dst_base,
  input  logic [31:0]              dst_capacity,

  input  logic                     s_axis_valid,
  output logic                     s_axis_ready,
  input  logic [7:0]               s_axis_data,
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
  localparam int AXI_BYTE_SHIFT =
    (AXI_BYTES <= 1) ? 0 :
    (AXI_BYTES <= 2) ? 1 :
    (AXI_BYTES <= 4) ? 2 :
    (AXI_BYTES <= 8) ? 3 :
    (AXI_BYTES <= 16) ? 4 :
    (AXI_BYTES <= 32) ? 5 :
    6;
  localparam logic [2:0] AXI_SIZE = AXI_BYTE_SHIFT;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_COLLECT,
    ST_AW,
    ST_W,
    ST_B
  } state_t;

  state_t state_q;
  logic [AXI_DATA_BITS-1:0] word_q;
  logic [AXI_BYTES-1:0] strobe_q;
  logic [AXI_BYTE_COUNT_BITS-1:0] byte_count_q;
  logic [AXI_BYTE_COUNT_BITS-1:0] write_count_q;
  logic pending_last_q;
  logic [31:0] write_offset_q;
  logic capacity_ok_w;
  logic take_byte_w;
  logic flush_word_w;
  logic [AXI_BYTE_COUNT_BITS-1:0] axi_last_byte_count_w;
  logic [AXI_BYTE_COUNT_BITS-1:0] one_byte_count_w;

  assign busy = (state_q != ST_IDLE);
  assign m_axi_awaddr = dst_base + write_offset_q;
  assign m_axi_awlen = 8'd0;
  assign m_axi_awsize = AXI_SIZE;
  assign m_axi_awburst = 2'b01;
  assign m_axi_wdata = word_q;
  assign m_axi_wstrb = strobe_q;
  assign m_axi_wlast = 1'b1;
  assign capacity_ok_w = (dst_capacity == 32'd0) || (bytes_written < dst_capacity);
  assign s_axis_ready = (state_q == ST_COLLECT) && capacity_ok_w;
  assign take_byte_w = s_axis_valid && s_axis_ready;
  assign axi_last_byte_count_w = AXI_BYTES - 1;
  assign one_byte_count_w = 1;
  assign flush_word_w = take_byte_w &&
    ((byte_count_q == axi_last_byte_count_w) || s_axis_last);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      word_q <= '0;
      strobe_q <= '0;
      byte_count_q <= '0;
      write_count_q <= '0;
      pending_last_q <= 1'b0;
      write_offset_q <= 32'd0;
      bytes_written <= 32'd0;
      frame_done <= 1'b0;
      error <= 1'b0;
      m_axi_awvalid <= 1'b0;
      m_axi_wvalid <= 1'b0;
      m_axi_bready <= 1'b0;
    end else begin
      frame_done <= 1'b0;
      if (start) begin
        state_q <= ST_COLLECT;
        word_q <= '0;
        strobe_q <= '0;
        byte_count_q <= '0;
        write_count_q <= '0;
        pending_last_q <= 1'b0;
        write_offset_q <= 32'd0;
        bytes_written <= 32'd0;
        error <= 1'b0;
        m_axi_awvalid <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
      end else begin
        case (state_q)
          ST_IDLE: begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;
          end
          ST_COLLECT: begin
            if (take_byte_w) begin
              word_q[byte_count_q * 8 +: 8] <= s_axis_data;
              strobe_q[byte_count_q] <= 1'b1;
              bytes_written <= bytes_written + 32'd1;
              pending_last_q <= s_axis_last;
              if (flush_word_w) begin
                write_count_q <= byte_count_q + one_byte_count_w;
                byte_count_q <= '0;
                m_axi_awvalid <= 1'b1;
                state_q <= ST_AW;
              end else begin
                byte_count_q <= byte_count_q + one_byte_count_w;
              end
            end else if (!capacity_ok_w) begin
              error <= 1'b1;
            end
          end
          ST_AW: begin
            if (m_axi_awvalid && m_axi_awready) begin
              m_axi_awvalid <= 1'b0;
              m_axi_wvalid <= 1'b1;
              state_q <= ST_W;
            end
          end
          ST_W: begin
            if (m_axi_wvalid && m_axi_wready) begin
              m_axi_wvalid <= 1'b0;
              m_axi_bready <= 1'b1;
              state_q <= ST_B;
            end
          end
          ST_B: begin
            if (m_axi_bvalid && m_axi_bready) begin
              m_axi_bready <= 1'b0;
              write_offset_q <= write_offset_q + {{(32-AXI_BYTE_COUNT_BITS){1'b0}}, write_count_q};
              word_q <= '0;
              strobe_q <= '0;
              write_count_q <= '0;
              if (m_axi_bresp != 2'b00) begin
                error <= 1'b1;
              end
              if (pending_last_q) begin
                frame_done <= 1'b1;
              end
              pending_last_q <= 1'b0;
              state_q <= ST_COLLECT;
            end
          end
          default: begin
            state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end
endmodule
