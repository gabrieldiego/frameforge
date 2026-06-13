`timescale 1ns/1ps

module ff_av2_encoder #(
  parameter int MAX_VISIBLE_WIDTH = 1024,
  parameter int MAX_VISIBLE_HEIGHT = 1024,
  // TODO(av2): revisit this shared integration name once AV2 block/superblock
  // terminology is finalized in the implementation.
  parameter int CTU_SIZE = 64,
  parameter int SAMPLE_BITS = 8,
  parameter int SOURCE_SAMPLE_BITS = SAMPLE_BITS
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [15:0] visible_width,
  input  logic [15:0] visible_height,
  // Shared chroma format IDs: 1=4:2:0, 2=4:2:2, 3=4:4:4.
  input  logic [1:0] chroma_format_idc,
  output logic       busy,

  input  logic       s_axis_valid,
  output logic       s_axis_ready,
  input  logic [SAMPLE_BITS - 1:0] s_axis_data,
  input  logic       s_axis_last,
  output logic       input_error,

  output logic       m_axis_valid,
  input  logic       m_axis_ready,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last
);

  localparam int AV2_MAX_TILE_BYTES = 512;
  localparam int AV2_PREFIX_BYTES_8X8 = 20;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_ENCODE,
    ST_FINISH_INIT,
    ST_FINISH_PUSH,
    ST_CARRY,
    ST_OUTPUT
  } state_t;

  state_t state_q;
  logic supported_black_geometry_w;
  logic start_invalid_w;
  logic [15:0] precarry_mem_q [0:AV2_MAX_TILE_BYTES - 1];
  logic [7:0] tile_mem_q [0:AV2_MAX_TILE_BYTES - 1];
  logic [15:0] precarry_len_q;
  logic [15:0] tile_len_q;
  logic [15:0] stream_index_q;
  logic [63:0] low_q;
  logic [31:0] rng_q;
  integer cnt_q;
  logic [1:0] phase_q;
  logic [3:0] step_q;
  logic [1:0] txb_q;
  logic [63:0] finish_e_q;
  integer finish_c_q;
  integer finish_s_q;
  logic [15:0] carry_q;
  integer carry_index_q;

  logic        op_valid_w;
  logic        op_literal_w;
  logic [31:0] op_literal_value_w;
  logic [4:0]  op_literal_bits_w;
  logic [31:0] op_fl_w;
  logic [31:0] op_fh_w;
  integer      op_fl_inc_w;
  integer      op_fh_inc_w;
  logic        op_last_w;

  logic [63:0] raw_low_w;
  logic [31:0] raw_rng_w;
  integer raw_bypass_bits_w;
  logic [31:0] rr_w;
  integer pp_fl_w;
  integer pp_fh_w;
  logic [31:0] scaled_u_w;
  logic [31:0] scaled_v_w;
  integer ilog_rng_w;
  integer norm_c_w;
  integer norm_d_w;
  integer norm_s_w;
  integer norm_c_after_w;
  integer norm_s_after_w;
  logic [63:0] norm_mask_w;
  logic [63:0] norm_low_work_w;
  logic [1:0] norm_push_count_w;
  logic [15:0] norm_push0_w;
  logic [15:0] norm_push1_w;
  logic [63:0] norm_low_w;
  logic [31:0] norm_rng_w;
  integer norm_cnt_w;
  logic [7:0] prefix_byte_w;
  logic [15:0] total_stream_len_w;
  logic [15:0] carry_sum_w;

  assign supported_black_geometry_w =
    (visible_width == 16'd8) &&
    (visible_height == 16'd8);

  assign start_invalid_w =
    !supported_black_geometry_w ||
    (visible_width > MAX_VISIBLE_WIDTH) ||
    (visible_height > MAX_VISIBLE_HEIGHT) ||
    (chroma_format_idc != 2'd3);

  // TODO(av2): widen this 8x8 smoke generator into the full recursive
  // superblock traversal used by the Rust model. The tile entropy bytes below
  // are generated through the AV2 range-coder state, not stored as bitstream
  // blobs, so later geometry support can reuse the same writer.
  assign busy = (state_q != ST_IDLE);
  assign s_axis_ready = 1'b0;
  assign total_stream_len_w = 16'd20 + tile_len_q;
  assign carry_sum_w = carry_q + precarry_mem_q[carry_index_q];

  always @* begin
    op_valid_w = 1'b1;
    op_literal_w = 1'b0;
    op_literal_value_w = 32'd0;
    op_literal_bits_w = 5'd0;
    op_fl_w = 32'd32768;
    op_fh_w = 32'd0;
    op_fl_inc_w = 0;
    op_fh_inc_w = 0;
    op_last_w = 1'b0;

    if (phase_q == 2'd0) begin
      case (step_q)
        4'd0: begin op_fh_w = 32'd4684; op_fh_inc_w = 8; end
        4'd1: begin op_fh_w = 32'd16384; op_fh_inc_w = 8; end
        4'd2: begin op_fh_w = 32'd3905; op_fh_inc_w = 12; end
        4'd3: begin op_fh_w = 32'd17593; op_fh_inc_w = 14; end
        4'd4: begin op_fh_w = 32'd514; op_fh_inc_w = 8; end
        4'd5: begin op_fh_w = 32'd16384; op_fh_inc_w = 8; end
        4'd6: begin op_fh_w = 32'd23405; op_fh_inc_w = 14; end
        default: op_valid_w = 1'b0;
      endcase
    end else if (phase_q == 2'd1) begin
      case (step_q)
        4'd0: begin
          case (txb_q)
            2'd0: op_fh_w = 32'd31669;
            2'd1, 2'd2: op_fh_w = 32'd24824;
            default: op_fh_w = 32'd3692;
          endcase
          op_fh_inc_w = 8;
        end
        4'd1: begin op_fh_w = 32'd30822; op_fh_inc_w = 12; end
        4'd2: begin op_fl_w = 32'd704; op_fh_w = 32'd0; op_fl_inc_w = 3; op_fh_inc_w = 0; end
        4'd3: begin op_fl_w = 32'd11993; op_fh_w = 32'd0; op_fl_inc_w = 4; op_fh_inc_w = 0; end
        4'd4: begin
          op_fl_w = (txb_q == 2'd0) ? 32'd16937 : 32'd19136;
          op_fh_w = 32'd0;
          op_fl_inc_w = 8;
          op_fh_inc_w = 0;
        end
        4'd5: begin op_literal_w = 1'b1; op_literal_value_w = 32'd0; op_literal_bits_w = 5'd5; end
        4'd6: begin op_literal_w = 1'b1; op_literal_value_w = 32'd0; op_literal_bits_w = 5'd6; end
        4'd7: begin op_literal_w = 1'b1; op_literal_value_w = 32'd249; op_literal_bits_w = 5'd8; end
        4'd8: begin op_literal_w = 1'b1; op_literal_value_w = 32'd0; op_literal_bits_w = 5'd1; end
        default: op_valid_w = 1'b0;
      endcase
    end else begin
      case (step_q)
        4'd0: begin
          if (phase_q == 2'd2) begin
            case (txb_q)
              2'd0: op_fh_w = 32'd23870;
              2'd1, 2'd2: op_fh_w = 32'd19113;
              default: op_fh_w = 32'd10420;
            endcase
          end else begin
            op_fh_w = 32'd16384;
          end
          op_fh_inc_w = 8;
        end
        4'd1: begin op_fh_w = 32'd24768; op_fh_inc_w = 12; end
        4'd2: begin op_fl_w = 32'd511; op_fh_w = 32'd0; op_fl_inc_w = 3; op_fh_inc_w = 0; end
        4'd3: begin op_literal_w = 1'b1; op_literal_value_w = 32'd1; op_literal_bits_w = 5'd1; end
        4'd4: begin op_literal_w = 1'b1; op_literal_value_w = 32'd0; op_literal_bits_w = 5'd5; end
        4'd5: begin op_literal_w = 1'b1; op_literal_value_w = 32'd0; op_literal_bits_w = 5'd6; end
        4'd6: begin op_literal_w = 1'b1; op_literal_value_w = 32'd250; op_literal_bits_w = 5'd8; end
        4'd7: begin op_literal_w = 1'b1; op_literal_value_w = 32'd1; op_literal_bits_w = 5'd1; end
        default: op_valid_w = 1'b0;
      endcase
      op_last_w = (phase_q == 2'd3) && (txb_q == 2'd3) && (step_q == 4'd7);
    end
  end

  always @* begin
    rr_w = rng_q >> 8;
    pp_fl_w = (((op_fl_w >> 7) << 4) + op_fl_inc_w);
    pp_fh_w = (((op_fh_w >> 7) << 4) + op_fh_inc_w);
    scaled_u_w = (((rr_w * pp_fl_w[31:0]) >> 7) << 3);
    scaled_v_w = (((rr_w * pp_fh_w[31:0]) >> 7) << 3);

    if (op_literal_w) begin
      raw_low_w = (low_q << op_literal_bits_w) + (rng_q * op_literal_value_w);
      raw_rng_w = rng_q;
      raw_bypass_bits_w = op_literal_bits_w;
    end else if (op_fl_w < 32'd32768) begin
      raw_low_w = low_q + (rng_q - scaled_u_w);
      raw_rng_w = scaled_u_w - scaled_v_w;
      raw_bypass_bits_w = 0;
    end else begin
      raw_low_w = low_q;
      raw_rng_w = rng_q - scaled_v_w;
      raw_bypass_bits_w = 0;
    end

    if (raw_rng_w[15]) ilog_rng_w = 16;
    else if (raw_rng_w[14]) ilog_rng_w = 15;
    else if (raw_rng_w[13]) ilog_rng_w = 14;
    else if (raw_rng_w[12]) ilog_rng_w = 13;
    else if (raw_rng_w[11]) ilog_rng_w = 12;
    else if (raw_rng_w[10]) ilog_rng_w = 11;
    else if (raw_rng_w[9]) ilog_rng_w = 10;
    else if (raw_rng_w[8]) ilog_rng_w = 9;
    else if (raw_rng_w[7]) ilog_rng_w = 8;
    else if (raw_rng_w[6]) ilog_rng_w = 7;
    else if (raw_rng_w[5]) ilog_rng_w = 6;
    else if (raw_rng_w[4]) ilog_rng_w = 5;
    else if (raw_rng_w[3]) ilog_rng_w = 4;
    else if (raw_rng_w[2]) ilog_rng_w = 3;
    else if (raw_rng_w[1]) ilog_rng_w = 2;
    else ilog_rng_w = 1;

    norm_c_w = cnt_q;
    if (raw_bypass_bits_w > 0) begin
      norm_c_w = cnt_q + raw_bypass_bits_w;
      norm_d_w = 0;
    end else begin
      norm_d_w = 16 - ilog_rng_w;
    end
    norm_s_w = norm_c_w + norm_d_w;
    norm_low_work_w = raw_low_w;
    norm_c_after_w = norm_c_w;
    norm_s_after_w = norm_s_w;
    norm_push_count_w = 2'd0;
    norm_push0_w = 16'd0;
    norm_push1_w = 16'd0;
    norm_mask_w = 64'd0;

    if (norm_s_w >= 0) begin
      norm_c_after_w = norm_c_w + 16;
      if (norm_c_after_w >= 64) norm_mask_w = 64'hffff_ffff_ffff_ffff;
      else if (norm_c_after_w <= 0) norm_mask_w = 64'd0;
      else norm_mask_w = (64'd1 << norm_c_after_w) - 64'd1;

      if (norm_s_w >= 8) begin
        norm_push0_w = (norm_low_work_w >> norm_c_after_w) & 16'hffff;
        norm_low_work_w = norm_low_work_w & norm_mask_w;
        norm_c_after_w = norm_c_after_w - 8;
        norm_mask_w = norm_mask_w >> 8;
        norm_push1_w = (norm_low_work_w >> norm_c_after_w) & 16'hffff;
        norm_push_count_w = 2'd2;
      end else begin
        norm_push0_w = (norm_low_work_w >> norm_c_after_w) & 16'hffff;
        norm_push_count_w = 2'd1;
      end
      norm_s_after_w = norm_c_after_w + norm_d_w - 24;
      norm_low_work_w = norm_low_work_w & norm_mask_w;
    end

    norm_low_w = norm_low_work_w << norm_d_w;
    norm_rng_w = raw_rng_w << norm_d_w;
    norm_cnt_w = norm_s_after_w;
  end

  always @* begin
    case (stream_index_q)
      16'd0: prefix_byte_w = 8'h01;
      16'd1: prefix_byte_w = 8'h08;
      16'd2: prefix_byte_w = 8'h0c;
      16'd3: prefix_byte_w = 8'h04;
      16'd4: prefix_byte_w = 8'h92;
      16'd5: prefix_byte_w = 8'h06;
      16'd6: prefix_byte_w = 8'h88;
      16'd7: prefix_byte_w = 8'hbf;
      16'd8: prefix_byte_w = 8'h00;
      16'd9: prefix_byte_w = 8'h00;
      16'd10: prefix_byte_w = 8'h42;
      16'd11: prefix_byte_w = 8'h01;
      16'd12: prefix_byte_w = 8'hb8;
      16'd13: prefix_byte_w = 8'h08;
      16'd14: prefix_byte_w = 8'h80;
      16'd15: prefix_byte_w = 8'h35;
      16'd16: prefix_byte_w = 8'h10;
      16'd17: prefix_byte_w = 8'he6;
      16'd18: prefix_byte_w = 8'h00;
      16'd19: prefix_byte_w = 8'h00;
      default: prefix_byte_w = 8'h00;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      input_error <= 1'b0;
      state_q <= ST_IDLE;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      low_q <= 64'd0;
      rng_q <= 32'h8000;
      cnt_q <= -9;
      precarry_len_q <= 16'd0;
      tile_len_q <= 16'd0;
      stream_index_q <= 16'd0;
      phase_q <= 2'd0;
      step_q <= 4'd0;
      txb_q <= 2'd0;
      finish_e_q <= 64'd0;
      finish_c_q <= 0;
      finish_s_q <= 0;
      carry_q <= 16'd0;
      carry_index_q <= 0;
    end else if (start) begin
      input_error <= start_invalid_w;
      if (!start_invalid_w && state_q == ST_IDLE) begin
        state_q <= ST_ENCODE;
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;
        low_q <= 64'd0;
        rng_q <= 32'h8000;
        cnt_q <= -9;
        precarry_len_q <= 16'd0;
        tile_len_q <= 16'd0;
        stream_index_q <= 16'd0;
        phase_q <= 2'd0;
        step_q <= 4'd0;
        txb_q <= 2'd0;
      end
    end else begin
      input_error <= 1'b0;
      case (state_q)
        ST_IDLE: begin
          m_axis_valid <= 1'b0;
          m_axis_last <= 1'b0;
        end
        ST_ENCODE: begin
          if (op_valid_w) begin
            if (norm_push_count_w != 2'd0) begin
              precarry_mem_q[precarry_len_q] <= norm_push0_w;
            end
            if (norm_push_count_w == 2'd2) begin
              precarry_mem_q[precarry_len_q + 16'd1] <= norm_push1_w;
            end
            precarry_len_q <= precarry_len_q + {14'd0, norm_push_count_w};
            low_q <= norm_low_w;
            rng_q <= norm_rng_w;
            cnt_q <= norm_cnt_w;

            if (op_last_w) begin
              state_q <= ST_FINISH_INIT;
            end else if (phase_q == 2'd0) begin
              if (step_q == 4'd6) begin
                phase_q <= 2'd1;
                step_q <= 4'd0;
                txb_q <= 2'd0;
              end else begin
                step_q <= step_q + 4'd1;
              end
            end else if (phase_q == 2'd1) begin
              if (step_q == 4'd8) begin
                step_q <= 4'd0;
                if (txb_q == 2'd3) begin
                  phase_q <= 2'd2;
                  txb_q <= 2'd0;
                end else begin
                  txb_q <= txb_q + 2'd1;
                end
              end else begin
                step_q <= step_q + 4'd1;
              end
            end else begin
              if (step_q == 4'd7) begin
                step_q <= 4'd0;
                if (txb_q == 2'd3) begin
                  phase_q <= phase_q + 2'd1;
                  txb_q <= 2'd0;
                end else begin
                  txb_q <= txb_q + 2'd1;
                end
              end else begin
                step_q <= step_q + 4'd1;
              end
            end
          end
        end
        ST_FINISH_INIT: begin
          finish_e_q <= ((low_q + 64'h3fff) & ~64'h3fff) | 64'h4000;
          finish_c_q <= cnt_q;
          finish_s_q <= cnt_q + 10;
          state_q <= ST_FINISH_PUSH;
        end
        ST_FINISH_PUSH: begin
          if (finish_s_q > 0) begin
            precarry_mem_q[precarry_len_q] <= (finish_e_q >> (finish_c_q + 16)) & 16'hffff;
            precarry_len_q <= precarry_len_q + 16'd1;
            if ((finish_c_q + 16) >= 64) begin
              finish_e_q <= 64'd0;
            end else if ((finish_c_q + 16) <= 0) begin
              finish_e_q <= finish_e_q;
            end else begin
              finish_e_q <= finish_e_q & ((64'd1 << (finish_c_q + 16)) - 64'd1);
            end
            finish_c_q <= finish_c_q - 8;
            finish_s_q <= finish_s_q - 8;
          end else begin
            carry_q <= 16'd0;
            carry_index_q <= precarry_len_q - 16'd1;
            tile_len_q <= precarry_len_q;
            state_q <= ST_CARRY;
          end
        end
        ST_CARRY: begin
          carry_q <= carry_sum_w >> 8;
          tile_mem_q[carry_index_q] <= carry_sum_w[7:0];
          if (carry_index_q == 0) begin
            stream_index_q <= 16'd0;
            state_q <= ST_OUTPUT;
          end else begin
            carry_index_q <= carry_index_q - 1;
          end
        end
        ST_OUTPUT: begin
          if (!m_axis_valid || m_axis_ready) begin
            m_axis_valid <= 1'b1;
            if (stream_index_q < 16'd20) begin
              m_axis_data <= prefix_byte_w;
            end else begin
              m_axis_data <= tile_mem_q[stream_index_q - 16'd20];
            end
            m_axis_last <= (stream_index_q == (total_stream_len_w - 16'd1));
            if (stream_index_q == (total_stream_len_w - 16'd1)) begin
              if (m_axis_ready) begin
                state_q <= ST_IDLE;
                stream_index_q <= 16'd0;
              end
            end else begin
              stream_index_q <= stream_index_q + 16'd1;
            end
          end
        end
        default: state_q <= ST_IDLE;
      endcase
    end
  end

  wire _unused_inputs_w = &{
    1'b0,
    CTU_SIZE[0],
    SOURCE_SAMPLE_BITS[0],
    s_axis_valid,
    s_axis_data,
    s_axis_last
  };

endmodule
