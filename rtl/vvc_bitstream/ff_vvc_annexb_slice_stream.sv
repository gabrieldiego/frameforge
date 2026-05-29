`timescale 1ns/1ps

module ff_vvc_annexb_slice_stream (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       clear,
  input  logic       start,
  input  logic [4:0] nal_unit_type,

  output logic       s_axis_ready,
  input  logic       s_axis_valid,
  input  logic [7:0] s_axis_data,
  input  logic       s_axis_last,

  input  logic       m_axis_ready,
  output logic       m_axis_valid,
  output logic [7:0] m_axis_data,
  output logic       m_axis_last,
  output logic       done
);
  localparam logic [5:0] NAL_LAYER_ID = 6'd0;
  localparam logic [2:0] NAL_TEMPORAL_ID_PLUS1 = 3'd1;
  localparam logic [2:0] ST_IDLE = 3'd0;
  localparam logic [2:0] ST_START_CODE = 3'd1;
  localparam logic [2:0] ST_NAL_HEADER = 3'd2;
  localparam logic [2:0] ST_PREFIX_RBSP = 3'd3;
  localparam logic [2:0] ST_PAYLOAD_RBSP = 3'd4;

  logic [2:0] state_q;
  logic [2:0] byte_index_q;
  logic       ep_clear_q;
  logic       ep_s_valid;
  logic       ep_s_ready;
  logic [7:0] ep_s_data;
  logic       ep_s_last;
  logic       ep_m_valid;
  logic       ep_m_ready;
  logic [7:0] ep_m_data;
  logic       ep_m_last;
  logic [7:0] prefix_byte;
  logic       prefix_last;

  assign prefix_last = byte_index_q == 3'd2;
  assign ep_m_ready = (state_q == ST_PREFIX_RBSP || state_q == ST_PAYLOAD_RBSP) &&
                      (!m_axis_valid || m_axis_ready);
  assign s_axis_ready = (state_q == ST_PAYLOAD_RBSP) && ep_s_ready;

  always_comb begin
    prefix_byte = 8'h00;
    case (byte_index_q)
      3'd0: prefix_byte = 8'hc4;
      3'd1: prefix_byte = 8'h00;
      3'd2: prefix_byte = 8'h70;
      default: prefix_byte = 8'h00;
    endcase
  end

  always_comb begin
    ep_s_valid = 1'b0;
    ep_s_data = 8'h00;
    ep_s_last = 1'b0;
    if (state_q == ST_PREFIX_RBSP) begin
      ep_s_valid = 1'b1;
      ep_s_data = prefix_byte;
      ep_s_last = 1'b0;
    end else if (state_q == ST_PAYLOAD_RBSP) begin
      ep_s_valid = s_axis_valid;
      ep_s_data = s_axis_data;
      ep_s_last = s_axis_last;
    end
  end

  ff_vvc_emulation_prevention_stream rbsp_emulation_prevention (
    .clk(clk),
    .rst_n(rst_n),
    .clear(ep_clear_q || clear),
    .s_axis_valid(ep_s_valid),
    .s_axis_ready(ep_s_ready),
    .s_axis_data(ep_s_data),
    .s_axis_last(ep_s_last),
    .m_axis_ready(ep_m_ready),
    .m_axis_valid(ep_m_valid),
    .m_axis_data(ep_m_data),
    .m_axis_last(ep_m_last),
    .done()
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      byte_index_q <= 3'd0;
      ep_clear_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      done <= 1'b0;
    end else if (clear) begin
      state_q <= ST_IDLE;
      byte_index_q <= 3'd0;
      ep_clear_q <= 1'b0;
      m_axis_valid <= 1'b0;
      m_axis_data <= 8'd0;
      m_axis_last <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      ep_clear_q <= 1'b0;

      if (m_axis_valid && !m_axis_ready) begin
        state_q <= state_q;
      end else begin
        m_axis_valid <= 1'b0;
        m_axis_last <= 1'b0;

        case (state_q)
          ST_IDLE: begin
            if (start) begin
              ep_clear_q <= 1'b1;
              state_q <= ST_START_CODE;
              byte_index_q <= 3'd0;
            end
          end

          ST_START_CODE: begin
            m_axis_valid <= 1'b1;
            m_axis_data <= (byte_index_q == 3'd3) ? 8'h01 : 8'h00;
            if (byte_index_q == 3'd3) begin
              byte_index_q <= 3'd0;
              state_q <= ST_NAL_HEADER;
            end else begin
              byte_index_q <= byte_index_q + 3'd1;
            end
          end

          ST_NAL_HEADER: begin
            m_axis_valid <= 1'b1;
            if (byte_index_q == 3'd0) begin
              m_axis_data <= {2'b00, NAL_LAYER_ID};
              byte_index_q <= 3'd1;
            end else begin
              m_axis_data <= {nal_unit_type, NAL_TEMPORAL_ID_PLUS1};
              byte_index_q <= 3'd0;
              state_q <= ST_PREFIX_RBSP;
            end
          end

          ST_PREFIX_RBSP: begin
            if (ep_m_valid) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= ep_m_data;
              m_axis_last <= 1'b0;
            end
            if (ep_s_valid && ep_s_ready) begin
              if (prefix_last) begin
                byte_index_q <= 3'd0;
                state_q <= ST_PAYLOAD_RBSP;
              end else begin
                byte_index_q <= byte_index_q + 3'd1;
              end
            end
          end

          ST_PAYLOAD_RBSP: begin
            if (ep_m_valid) begin
              m_axis_valid <= 1'b1;
              m_axis_data <= ep_m_data;
              m_axis_last <= ep_m_last;
              if (ep_m_last) begin
                state_q <= ST_IDLE;
                done <= 1'b1;
              end
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
