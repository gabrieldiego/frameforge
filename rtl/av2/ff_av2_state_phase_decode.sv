`timescale 1ns/1ps

module ff_av2_state_phase_decode #(
  parameter logic [4:0] ST_IDLE = 5'd0,
  parameter logic [4:0] ST_TILE_START = 5'd1,
  parameter logic [4:0] ST_INPUT_READ = 5'd2,
  parameter logic [4:0] ST_SEQ_LOAD = 5'd3,
  parameter logic [4:0] ST_SEQ_WRITE = 5'd4,
  parameter logic [4:0] ST_LOAD_BLOCK = 5'd5,
  parameter logic [4:0] ST_PARTITION = 5'd6,
  parameter logic [4:0] ST_LEAF_WAIT = 5'd7,
  parameter logic [4:0] ST_PALETTE_QUERY = 5'd8,
  parameter logic [4:0] ST_LEAF = 5'd9,
  parameter logic [4:0] ST_FINISH_INIT = 5'd10,
  parameter logic [4:0] ST_FINISH_PUSH = 5'd11,
  parameter logic [4:0] ST_CHROMA_FETCH = 5'd12,
  parameter logic [4:0] ST_CARRY_READ = 5'd13,
  parameter logic [4:0] ST_CARRY_WRITE = 5'd14,
  parameter logic [4:0] ST_PAYLOAD_PREFIX = 5'd15,
  parameter logic [4:0] ST_OUTPUT_PREP = 5'd16,
  parameter logic [4:0] ST_OUTPUT_VALID = 5'd17,
  parameter logic [4:0] ST_OUTPUT_PAYLOAD_WAIT = 5'd18,
  parameter logic [4:0] ST_OUTPUT_PAYLOAD_LOAD = 5'd19,
  parameter logic [2:0] PHASE_INTRA = 3'd0,
  parameter logic [2:0] PHASE_PALETTE_HEADER = 3'd1,
  parameter logic [2:0] PHASE_PALETTE_MAP = 3'd2,
  parameter logic [2:0] PHASE_Y_COEFF = 3'd3,
  parameter logic [2:0] PHASE_U_COEFF = 3'd4,
  parameter logic [2:0] PHASE_V_COEFF = 3'd5,
  parameter logic [2:0] PHASE_INTRABC = 3'd6
) (
  input  logic [4:0] state_q,
  input  logic [2:0] phase_q,
  output logic       state_idle_w,
  output logic       state_tile_start_w,
  output logic       state_input_read_w,
  output logic       state_partition_w,
  output logic       state_palette_query_w,
  output logic       state_leaf_w,
  output logic       state_chroma_fetch_w,
  output logic       state_finish_push_w,
  output logic       state_carry_write_w,
  output logic       state_payload_prefix_w,
  output logic       state_output_valid_w,
  output logic       phase_intra_w,
  output logic       phase_palette_header_w,
  output logic       phase_palette_map_w,
  output logic       phase_y_coeff_w,
  output logic       phase_u_coeff_w,
  output logic       phase_v_coeff_w,
  output logic       phase_intrabc_w
);

  assign state_idle_w = (state_q == ST_IDLE);
  assign state_tile_start_w = (state_q == ST_TILE_START);
  assign state_input_read_w = (state_q == ST_INPUT_READ);
  assign state_partition_w = (state_q == ST_PARTITION);
  assign state_palette_query_w = (state_q == ST_PALETTE_QUERY);
  assign state_leaf_w = (state_q == ST_LEAF);
  assign state_chroma_fetch_w = (state_q == ST_CHROMA_FETCH);
  assign state_finish_push_w = (state_q == ST_FINISH_PUSH);
  assign state_carry_write_w = (state_q == ST_CARRY_WRITE);
  assign state_payload_prefix_w = (state_q == ST_PAYLOAD_PREFIX);
  assign state_output_valid_w = (state_q == ST_OUTPUT_VALID);

  assign phase_intra_w = (phase_q == PHASE_INTRA);
  assign phase_palette_header_w = (phase_q == PHASE_PALETTE_HEADER);
  assign phase_palette_map_w = (phase_q == PHASE_PALETTE_MAP);
  assign phase_y_coeff_w = (phase_q == PHASE_Y_COEFF);
  assign phase_u_coeff_w = (phase_q == PHASE_U_COEFF);
  assign phase_v_coeff_w = (phase_q == PHASE_V_COEFF);
  assign phase_intrabc_w = (phase_q == PHASE_INTRABC);

endmodule

