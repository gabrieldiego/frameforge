`timescale 1ns/1ps

module ff_vvc_annexb_header (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  input  logic        m_axis_ready,
  output logic        m_axis_valid,
  output logic [7:0]  m_axis_data,
  output logic        m_axis_last,
  output logic        supported,
  output logic        done
);
  localparam int HEADER_BYTES = 66;

  // Byte-level SPS/PPS/slice-prefix generator for the currently validated
  // 4:2:0 residual path. The selected stream is parameterized by coded
  // geometry; the next cleanup is replacing these generated prefix constants
  // with bit-level SPS, PPS, NAL-header, and slice-header writer blocks.
  localparam logic [527:0] PREFIX_8X16 =
    528'h000000010079000b0200800042423f5407d11ba211a2109184d8a3150c1a02ae3f82b0408000000001008100024222908031ec851651651620000000010041c40070;
  localparam logic [527:0] PREFIX_16X8 =
    528'h000000010079000b0200800041113f5407d11ba211a2109184d8a3150c1a02ae3f82b0408000000001008100011122908031ec851651651620000000010041c40070;
  localparam logic [527:0] PREFIX_16X16 =
    528'h000000010079000b0200800041108fd501f446e884688424613628c5430680ab8fe0ac102000000001008100011088a4200c7b214594594588000000010041c40070;
  localparam logic [527:0] PREFIX_24X16 =
    528'h000000010079000b0200800041908fd501f446e884688424613628c5430680ab8fe0ac102000000001008100019088a4200c7b214594594588000000010041c40070;
  localparam logic [527:0] PREFIX_16X24 =
    528'h000000010079000b020080004110cfd501f446e884688424613628c5430680ab8fe0ac1020000000010081000110c8a4200c7b214594594588000000010041c40070;

  logic [527:0] selected_prefix;
  logic [15:0] coded_width;
  logic [15:0] coded_height;
  logic [7:0] index_q;
  logic [9:0] bit_offset;
  logic active_q;

  assign coded_width = (visible_width + 16'd7) & 16'hfff8;
  assign coded_height = (visible_height + 16'd7) & 16'hfff8;
  assign supported =
    ((coded_width == 16'd8) && (coded_height == 16'd16)) ||
    ((coded_width == 16'd16) && (coded_height == 16'd8)) ||
    ((coded_width == 16'd16) && (coded_height == 16'd16)) ||
    ((coded_width == 16'd24) && (coded_height == 16'd16)) ||
    ((coded_width == 16'd16) && (coded_height == 16'd24));
  assign bit_offset = (HEADER_BYTES[9:0] - 10'd1 - {2'd0, index_q}) << 3;
  assign m_axis_valid = active_q;
  assign m_axis_data = active_q ? selected_prefix[bit_offset +: 8] : 8'h00;
  assign m_axis_last = active_q && (index_q == HEADER_BYTES[7:0] - 8'd1);

  always_comb begin
    selected_prefix = PREFIX_16X16;
    if ((coded_width == 16'd8) && (coded_height == 16'd16)) begin
      selected_prefix = PREFIX_8X16;
    end else if ((coded_width == 16'd16) && (coded_height == 16'd8)) begin
      selected_prefix = PREFIX_16X8;
    end else if ((coded_width == 16'd24) && (coded_height == 16'd16)) begin
      selected_prefix = PREFIX_24X16;
    end else if ((coded_width == 16'd16) && (coded_height == 16'd24)) begin
      selected_prefix = PREFIX_16X24;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      index_q <= 8'd0;
      active_q <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      index_q <= 8'd0;
      active_q <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start) begin
        index_q <= 8'd0;
        active_q <= supported;
        done <= !supported;
      end else if (m_axis_valid && m_axis_ready) begin
        if (m_axis_last) begin
          index_q <= 8'd0;
          active_q <= 1'b0;
          done <= 1'b1;
        end else begin
          index_q <= index_q + 8'd1;
        end
      end
    end
  end
endmodule
