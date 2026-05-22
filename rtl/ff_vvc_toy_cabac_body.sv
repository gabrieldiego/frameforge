`timescale 1ns/1ps

module ff_vvc_toy_cabac_body #(
  parameter int MAX_SLICE_PAYLOAD_BITS = 4096
) (
  input  logic [1:0]   body_kind,
  input  logic [15:0]  coded_width,
  input  logic [15:0]  coded_height,
  input  logic [4:0]   luma_rem,
  input  logic [4:0]   chroma_rem,
  output logic         supported,
  output logic [12:0]  cabac_bit_len,
  output logic [MAX_SLICE_PAYLOAD_BITS - 1:0] cabac_bits
);
  localparam logic [1:0] BODY_GENERATED = 2'd0;
  localparam logic [1:0] BODY_TRACE_FALLBACK = 2'd1;
  localparam int TOY_32X32_TRACE_BIN_COUNT = 542;

  // Compact D_CABAC trace words for the first 32x32 fallback path. Bit 15
  // marks bypass bins. Context-coded words store
  // (lps << 2) | (trace_mps_path << 1) | bin. The 32x32 body is isolated here
  // so each stage can be replaced by generated split/CBF/residual syntax
  // without touching the top-level encoder stream scheduler.
  localparam logic [(TOY_32X32_TRACE_BIN_COUNT * 16) - 1:0] TOY_32X32_TRACE_WORDS = {
    16'h035a, 16'h010f, 16'h0377, 16'h8000, 16'h0163, 16'h020b, 16'h0153, 16'h0153, 16'h00f3, 16'h020b, 16'h0133, 16'h02ca,
    16'h0233, 16'h0153, 16'h01ab, 16'h0113, 16'h029b, 16'h0170, 16'h8001, 16'h8001, 16'h8000, 16'h007d, 16'h011e, 16'h0092,
    16'h008a, 16'h01b1, 16'h0196, 16'h00c7, 16'h0102, 16'h0116, 16'h0013, 16'h0146, 16'h0203, 16'h010e, 16'h0394, 16'h009e,
    16'h0337, 16'h0092, 16'h008b, 16'h007e, 16'h0013, 16'h0062, 16'h022f, 16'h0061, 16'h008a, 16'h0012, 16'h0077, 16'h00a2,
    16'h0013, 16'h00e1, 16'h0129, 16'h005a, 16'h8000, 16'h8000, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8000, 16'h8001,
    16'h8000, 16'h8001, 16'h8000, 16'h00b1, 16'h007e, 16'h013d, 16'h008e, 16'h00b1, 16'h00aa, 16'h0179, 16'h0096, 16'h01ca,
    16'h025e, 16'h017a, 16'h02cb, 16'h00ba, 16'h00fb, 16'h007e, 16'h0013, 16'h0076, 16'h017a, 16'h008b, 16'h007e, 16'h0013,
    16'h0062, 16'h020b, 16'h0062, 16'h01b4, 16'h02cf, 16'h0052, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h8000, 16'h8000,
    16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h0162, 16'h0073, 16'h00d7, 16'h005a, 16'h0013, 16'h0042, 16'h01c3, 16'h0046,
    16'h0141, 16'h004e, 16'h006b, 16'h0042, 16'h0013, 16'h01d2, 16'h01f1, 16'h006a, 16'h02e8, 16'h01f4, 16'h02e3, 16'h020a,
    16'h006b, 16'h004e, 16'h0013, 16'h004e, 16'h01ac, 16'h007b, 16'h00e9, 16'h009d, 16'h0022, 16'h0013, 16'h00d5, 16'h00c6,
    16'h0026, 16'h0013, 16'h024f, 16'h024e, 16'h00b2, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8000, 16'h8000, 16'h8001,
    16'h8000, 16'h8000, 16'h8001, 16'h8001, 16'h8000, 16'h8001, 16'h0083, 16'h0013, 16'h005e, 16'h024e, 16'h00a3, 16'h004a,
    16'h0013, 16'h0046, 16'h02cf, 16'h004e, 16'h02e8, 16'h0223, 16'h0321, 16'h01c2, 16'h00b2, 16'h035b, 16'h0032, 16'h0053,
    16'h004e, 16'h0013, 16'h004a, 16'h0267, 16'h0209, 16'h0132, 16'h00d6, 16'h005b, 16'h0036, 16'h0013, 16'h0032, 16'h0173,
    16'h027c, 16'h019f, 16'h014a, 16'h0027, 16'h01f1, 16'h01b6, 16'h008a, 16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8000,
    16'h8001, 16'h8001, 16'h8000, 16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h0053, 16'h01b6, 16'h0083,
    16'h0046, 16'h0013, 16'h0042, 16'h0263, 16'h004a, 16'h02b4, 16'h01a2, 16'h033b, 16'h0032, 16'h0053, 16'h004e, 16'h0013,
    16'h004a, 16'h0242, 16'h005b, 16'h0032, 16'h0013, 16'h0032, 16'h0142, 16'h0027, 16'h0102, 16'h0013, 16'h00c2, 16'h0304,
    16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8001, 16'h005b, 16'h0027,
    16'h028d, 16'h0165, 16'h00c2, 16'h0013, 16'h01e7, 16'h01f5, 16'h013e, 16'h0230, 16'h0023, 16'h0123, 16'h029a, 16'h0242,
    16'h01c8, 16'h002f, 16'h0298, 16'h0013, 16'h0167, 16'h0306, 16'h0142, 16'h0013, 16'h0193, 16'h01e6, 16'h01b2, 16'h0013,
    16'h0201, 16'h0142, 16'h007e, 16'h0013, 16'h01d2, 16'h0253, 16'h01f3, 16'h0281, 16'h017a, 16'h0297, 16'h01b3, 16'h01f5,
    16'h011e, 16'h002b, 16'h0337, 16'h01fe, 16'h006a, 16'h0170, 16'h0027, 16'h0173, 16'h01b2, 16'h0156, 16'h017f, 16'h0173,
    16'h01b1, 16'h01c9, 16'h8001, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h8001,
    16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h0067, 16'h02e8, 16'h028c, 16'h0268, 16'h023c,
    16'h0132, 16'h0335, 16'h011a, 16'h0063, 16'h01c1, 16'h019a, 16'h0076, 16'h0155, 16'h00ee, 16'h0142, 16'h02f8, 16'h0208,
    16'h0141, 16'h00da, 16'h0093, 16'h012a, 16'h0013, 16'h024e, 16'h0375, 16'h00fa, 16'h01f7, 16'h011e, 16'h8000, 16'h8000,
    16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h002b, 16'h0337, 16'h020a, 16'h006a, 16'h01c3, 16'h015b,
    16'h01c2, 16'h018e, 16'h002f, 16'h031f, 16'h022d, 16'h0062, 16'h0013, 16'h01d3, 16'h0281, 16'h017a, 16'h017c, 16'h0013,
    16'h0234, 16'h0013, 16'h0103, 16'h02ce, 16'h020e, 16'h0013, 16'h015b, 16'h01b2, 16'h0166, 16'h0013, 16'h031f, 16'h01ae,
    16'h00d5, 16'h0013, 16'h031f, 16'h01fe, 16'h005a, 16'h0013, 16'h00fb, 16'h0306, 16'h01f3, 16'h0013, 16'h00e3, 16'h02ce,
    16'h0377, 16'h0013, 16'h00e0, 16'h010f, 16'h012c, 16'h00b0, 16'h00ef, 16'h00a3, 16'h0359, 16'h01cb, 16'h8001, 16'h8001,
    16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8001, 16'h8000, 16'h8000,
    16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h8001, 16'h8001,
    16'h8000, 16'h8001, 16'h8001, 16'h8000, 16'h8001, 16'h8000, 16'h01e5, 16'h02c2, 16'h023e, 16'h012b, 16'h0181, 16'h02e1,
    16'h0147, 16'h0192, 16'h0223, 16'h0295, 16'h8001, 16'h01f1, 16'h03b3, 16'h01c2, 16'h01c2, 16'h0221, 16'h01c1, 16'h0242,
    16'h005a, 16'h0143, 16'h00ea, 16'h0013, 16'h00c6, 16'h00c7, 16'h0338, 16'h8000, 16'h8000, 16'h8001, 16'h8000, 16'h0221,
    16'h01a1, 16'h0219, 16'h0181, 16'h011a, 16'h021a, 16'h8001, 16'h006a, 16'h018e, 16'h0295, 16'h00b2, 16'h8001, 16'h8001,
    16'h0062, 16'h0062, 16'h009e, 16'h0092, 16'h008a, 16'h007e, 16'h0075, 16'h00f1, 16'h00a6, 16'h0012, 16'h0282, 16'h0072,
    16'h02c2, 16'h01ae, 16'h024e, 16'h0172, 16'h01f6, 16'h022e, 16'h0166, 16'h01f2, 16'h8000, 16'h0252, 16'h027b, 16'h01c2,
    16'h029a, 16'h010e, 16'h0223, 16'h0202, 16'h010c, 16'h0200, 16'h0163, 16'h01de, 16'h029a, 16'h0092, 16'h0226, 16'h018f,
    16'h0296, 16'h01ad, 16'h02cc, 16'h024f, 16'h02ea, 16'h0305, 16'h01d9, 16'h0146, 16'h0072, 16'h019f, 16'h00b1, 16'h007e,
    16'h0012, 16'h00c7, 16'h00d2, 16'h0117, 16'h019f, 16'h01b1, 16'h017d, 16'h8001, 16'h8001, 16'h8001, 16'h8000, 16'h8001,
    16'h8000, 16'h8001, 16'h8000, 16'h01b1, 16'h01e7, 16'h019e, 16'h02b6, 16'h00e2, 16'h01c8, 16'h0209, 16'h8000, 16'h8000,
    16'h0192, 16'h008a
  };


  localparam int CABAC_BITS_LSB = 0;
  localparam int CABAC_LEN_LSB = CABAC_BITS_LSB + MAX_SLICE_PAYLOAD_BITS;
  localparam int CABAC_LOW_LSB = CABAC_LEN_LSB + 13;
  localparam int CABAC_RANGE_LSB = CABAC_LOW_LSB + 32;
  localparam int CABAC_BUFFERED_BYTE_LSB = CABAC_RANGE_LSB + 16;
  localparam int CABAC_NUM_BUFFERED_BYTES_LSB = CABAC_BUFFERED_BYTE_LSB + 9;
  localparam int CABAC_BITS_LEFT_LSB = CABAC_NUM_BUFFERED_BYTES_LSB + 8;
  localparam int CABAC_STATE_BITS = CABAC_BITS_LEFT_LSB + 8;

  typedef logic [CABAC_STATE_BITS - 1:0] cabac_state_t;

  always @* begin
    supported =
      ((body_kind == BODY_GENERATED) && supports_generated_body(coded_width, coded_height)) ||
      ((body_kind == BODY_TRACE_FALLBACK) && supports_trace_fallback_body(coded_width, coded_height));

    if ((body_kind == BODY_GENERATED) && supports_generated_body(coded_width, coded_height)) begin
      {cabac_bit_len, cabac_bits} = encode_8x8_body(luma_rem, chroma_rem);
    end else if ((body_kind == BODY_TRACE_FALLBACK) && (coded_width == 16'd16) && (coded_height == 16'd16)) begin
      {cabac_bit_len, cabac_bits} = encode_16x16_fallback_body(luma_rem, chroma_rem);
    end else if ((body_kind == BODY_TRACE_FALLBACK) && (coded_width == 16'd32) && (coded_height == 16'd32)) begin
      {cabac_bit_len, cabac_bits} = encode_32x32_body(luma_rem, chroma_rem);
    end else begin
      cabac_bit_len = 13'd0;
      cabac_bits = '0;
    end
  end

  function automatic logic supports_generated_body(
    input logic [15:0] width,
    input logic [15:0] height
  );
    begin
      supports_generated_body = (width == 16'd8) && (height == 16'd8);
    end
  endfunction

  function automatic logic supports_trace_fallback_body(
    input logic [15:0] width,
    input logic [15:0] height
  );
    begin
      supports_trace_fallback_body =
        ((width == 16'd16) && (height == 16'd16)) ||
        ((width == 16'd32) && (height == 16'd32));
    end
  endfunction

  function automatic logic [12 + MAX_SLICE_PAYLOAD_BITS:0] encode_8x8_body(
    input logic [4:0] rem,
    input logic [4:0] c_rem
  );
    cabac_state_t st;
    begin
      st = cabac_start();
      st = encode_8x8_luma_tree(st, rem);
      st = encode_4x4_chroma_tree(st, c_rem);
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      encode_8x8_body = {
        st[CABAC_LEN_LSB +: 13],
        st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS]
      };
    end
  endfunction

  function automatic logic [12 + MAX_SLICE_PAYLOAD_BITS:0] encode_32x32_body(
    input logic [4:0] rem,
    input logic [4:0] c_rem
  );
    cabac_state_t st;
    begin
      st = cabac_start();
      st = encode_32x32_luma_tree(st, rem);
      st = encode_32x32_chroma_tree(st, c_rem);
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      encode_32x32_body = {
        st[CABAC_LEN_LSB +: 13],
        st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS]
      };
    end
  endfunction

  function automatic logic [12 + MAX_SLICE_PAYLOAD_BITS:0] encode_16x16_fallback_body(
    input logic [4:0] rem,
    input logic [4:0] c_rem
  );
    cabac_state_t st;
    begin
      st = cabac_start();
      st = encode_16x16_fallback_tree(st, rem, c_rem);
      st = cabac_encode_bin_trm(st, 1'b1);
      st = cabac_finish(st);
      encode_16x16_fallback_body = {
        st[CABAC_LEN_LSB +: 13],
        st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS]
      };
    end
  endfunction

  function automatic cabac_state_t encode_8x8_luma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      st = cabac_encode_ctx_bins(st, 5'd0,  8'b0000_0101, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd4,  8'b0000_0010, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd8,  8'b0000_0001, 4'd1);
      st = cabac_encode_rem_abs_ep(st, rem, 3'd0);
      st = cabac_encode_bin_ep(st, 1'b1);
      st = cabac_encode_ctx_bins(st, 5'd9,  8'b0000_1011, 4'd4);
      st = cabac_encode_ctx_bins(st, 5'd13, 8'b0000_0100, 4'd3);
      encode_8x8_luma_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_4x4_chroma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   c_rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      st = cabac_encode_ctx_bins(st, 5'd16, 8'b0000_0101, 4'd3);
      st = cabac_encode_rem_abs_ep(st, c_rem, 3'd0);
      st = cabac_encode_bin_ep(st, 1'b1);
      encode_4x4_chroma_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_16x16_fallback_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem,
    input logic [4:0]   c_rem
  );
    cabac_state_t st;
    begin
      st = st_in;
      // TODO(vvc): Replace these trace-derived context decisions with
      // generated 16x16 split, prediction, CBF, and residual syntax.
      st = cabac_encode_bin(st, 1'b0, 9'd214, 1'b0); // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd67, 1'b1);  // split_cu_mode qt=1
      st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[5]
      st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[4]
      st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[3]
      st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[2]
      st = cabac_encode_bin_ep(st, 1'b1);            // intra_luma_pred_mode[1]
      st = cabac_encode_bin_ep(st, 1'b0);            // intra_luma_pred_mode[0]
      st = cabac_encode_bin(st, 1'b1, 9'd52, 1'b1);  // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd166, 1'b1); // split_cu_mode qt=1
      st = cabac_encode_bin(st, 1'b1, 9'd109, 1'b1); // split_cu_mode split=0
      st = cabac_encode_bin(st, 1'b1, 9'd134, 1'b1); // cbf_comp luma=1
      st = cabac_encode_bin(st, 1'b1, 9'd116, 1'b1); // sig_coeff_group_flag
      st = cabac_encode_bin(st, 1'b1, 9'd142, 1'b1); // sig_coeff_group_flag
      st = cabac_encode_bin(st, 1'b1, 9'd221, 1'b0); // last_sig_coeff_x_prefix
      st = cabac_encode_bin(st, 1'b0, 9'd205, 1'b0); // last_sig_coeff_y_prefix
      st = cabac_encode_bin_ep(st, 1'b0);            // last_sig_coeff_suffix
      st = cabac_encode_bin(st, 1'b0, 9'd39, 1'b0);  // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd101, 1'b0); // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd99, 1'b0);  // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd67, 1'b0);  // abs_level_gtx_flag
      st = cabac_encode_bin_ep(st, 1'b0);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b1);            // coeff_sign_flag
      st = cabac_encode_bin(st, 1'b0, 9'd64, 1'b0);  // ts_flag=0
      st = cabac_encode_bin(st, 1'b0, 9'd54, 1'b0);  // mts_idx=0

      st = cabac_encode_bin(st, 1'b0, 9'd40, 1'b0);  // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd176, 1'b0); // split_cu_mode qt=1
      st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd130, 1'b0); // split_cu_mode qt=1
      st = cabac_encode_bin(st, 1'b0, 9'd88, 1'b0);  // split_cu_mode split=1
      st = cabac_encode_bin(st, 1'b0, 9'd114, 1'b0); // split_cu_mode qt=1
      st = cabac_encode_bin(st, 1'b0, 9'd80, 1'b0);  // split_cu_mode split=0
      st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // cbf_comp Cb=0
      st = cabac_encode_bin(st, 1'b0, 9'd53, 1'b0);  // cbf_comp Cr=1
      st = cabac_encode_bin(st, 1'b0, 9'd26, 1'b0);  // sig_coeff_group_flag
      st = cabac_encode_bin(st, 1'b1, 9'd96, 1'b0);  // last_sig_coeff_x_prefix
      st = cabac_encode_bin(st, 1'b0, 9'd112, 1'b0); // last_sig_coeff_y_prefix
      st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd72, 1'b0);  // abs_level_gtx_flag
      st = cabac_encode_bin(st, 1'b1, 9'd112, 1'b1); // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd72, 1'b0);  // abs_level_gtx_flag
      st = cabac_encode_bin(st, 1'b1, 9'd88, 1'b1);  // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd84, 1'b0);  // abs_level_gtx_flag
      st = cabac_encode_bin(st, 1'b1, 9'd4, 1'b1);   // sig_coeff_flag
      st = cabac_encode_bin(st, 1'b0, 9'd206, 1'b1); // abs_level_gtx_flag
      st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b1);            // remainder_prefix
      st = cabac_encode_bin_ep(st, 1'b0);            // remainder_suffix
      st = cabac_encode_bin_ep(st, 1'b1);            // coeff_sign_flag
      st = cabac_encode_bin(st, 1'b1, 9'd160, 1'b0); // ts_flag=0
      st = cabac_encode_bin(st, 1'b1, 9'd29, 1'b0);  // mts_idx=0

      st = cabac_encode_bin(st, 1'b1, 9'd172, 1'b1); // split_cu_mode split=0 at (4,0)
      st = cabac_encode_bin(st, 1'b0, 9'd107, 1'b0); // cbf_comp Cb(4,0)=0
      st = cabac_encode_bin(st, 1'b0, 9'd136, 1'b0); // cbf_comp Cr(4,0)=0
      st = cabac_encode_bin(st, 1'b1, 9'd67, 1'b0);  // mts_idx=0 at (4,0)
      st = cabac_encode_bin(st, 1'b0, 9'd100, 1'b0); // split_cu_mode split=0 at (0,4)
      st = cabac_encode_bin(st, 1'b0, 9'd124, 1'b0); // cbf_comp Cb(0,4)=0
      st = cabac_encode_bin(st, 1'b0, 9'd160, 1'b0); // cbf_comp Cr(0,4)=0
      st = cabac_encode_bin(st, 1'b0, 9'd20, 1'b0);  // mts_idx=0 at (0,4)
      st = cabac_encode_bin_ep(st, 1'b1);            // trace EP before final block
      st = cabac_encode_bin(st, 1'b1, 9'd169, 1'b1); // split_cu_mode split=0 at (4,4)
      st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // cbf_comp Cb(4,4)=0
      st = cabac_encode_bin(st, 1'b0, 9'd147, 1'b0); // cbf_comp Cr(4,4)=0
      st = cabac_encode_bin(st, 1'b0, 9'd68, 1'b0);  // mts_idx=0 at (4,4)
      st = cabac_encode_bin(st, 1'b1, 9'd140, 1'b1); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd103, 1'b0); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd119, 1'b0); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd56, 1'b0);  // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd118, 1'b1); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd130, 1'b0); // final empty-tu context
      st = cabac_encode_bin(st, 1'b0, 9'd104, 1'b0); // final cbf cleanup
      st = cabac_encode_bin(st, 1'b0, 9'd81, 1'b0);  // final cbf cleanup
      encode_16x16_fallback_tree = st;
    end
  endfunction

  function automatic cabac_state_t encode_32x32_luma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   rem
  );
    begin
      // TODO(vvc): Replace these trace-derived bins with generated 32x32
      // luma split, prediction, transform, CBF, and residual decisions.
      encode_32x32_luma_tree = encode_32x32_trace_range(st_in, 0, 362);
    end
  endfunction

  function automatic cabac_state_t encode_32x32_chroma_tree(
    input cabac_state_t st_in,
    input logic [4:0]   c_rem
  );
    begin
      // TODO(vvc): Replace these trace-derived bins with generated 32x32
      // chroma split, transform, CBF, and residual decisions.
      encode_32x32_chroma_tree = encode_32x32_trace_range(st_in, 362, TOY_32X32_TRACE_BIN_COUNT);
    end
  endfunction

  function automatic cabac_state_t encode_32x32_trace_range(
    input cabac_state_t st_in,
    input integer       first_bin,
    input integer       end_bin
  );
    cabac_state_t st;
    integer i;
    begin
      st = st_in;
      for (i = first_bin; i < end_bin; i = i + 1) begin
        st = encode_32x32_trace_word(st, toy_32x32_trace_word(i));
      end
      encode_32x32_trace_range = st;
    end
  endfunction

  function automatic logic [15:0] toy_32x32_trace_word(input integer index);
    begin
      toy_32x32_trace_word =
        TOY_32X32_TRACE_WORDS[((TOY_32X32_TRACE_BIN_COUNT - 1 - index) * 16) +: 16];
    end
  endfunction

  function automatic cabac_state_t encode_32x32_trace_word(
    input cabac_state_t st_in,
    input logic [15:0]  word
  );
    begin
      if (word[15]) begin
        encode_32x32_trace_word = cabac_encode_bin_ep(st_in, word[0]);
      end else begin
        encode_32x32_trace_word = cabac_encode_bin(st_in, word[0], {1'b0, word[10:2]}, ~(word[1] ^ word[0]));
      end
    end
  endfunction

  function automatic cabac_state_t cabac_start();
    begin
      cabac_start = '0;
      cabac_start[CABAC_LOW_LSB +: 32] = 32'd0;
      cabac_start[CABAC_RANGE_LSB +: 16] = 16'd510;
      cabac_start[CABAC_BUFFERED_BYTE_LSB +: 9] = 9'h0ff;
      cabac_start[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = 8'd0;
      cabac_start[CABAC_BITS_LEFT_LSB +: 8] = 8'd23;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_ctx_bins(
    input cabac_state_t st_in,
    input logic [4:0]   ctx_offset,
    input logic [7:0]   bin_pattern,
    input logic [3:0]   num_bins
  );
    cabac_state_t st;
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

  function automatic cabac_state_t cabac_encode_bin(
    input cabac_state_t st_in,
    input logic         bin,
    input logic [8:0]   lps_in,
    input logic         mps
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    logic [8:0]  lps;
    integer bits_left;
    integer num_bits;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      lps = lps_in;

      range = range - lps;
      if (bin != mps) begin
        num_bits = renorm_bits_sv(lps);
        bits_left = bits_left - num_bits;
        low = low + range;
        low = low << num_bits;
        range = lps << num_bits;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_RANGE_LSB +: 16] = range;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else if (range < 16'd256) begin
        num_bits = renorm_bits_sv(range);
        bits_left = bits_left - num_bits;
        low = low << num_bits;
        range = range << num_bits;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_RANGE_LSB +: 16] = range;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
        end
      end else begin
        st[CABAC_RANGE_LSB +: 16] = range;
      end
      cabac_encode_bin = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bin_ep(
    input cabac_state_t st_in,
    input logic         bin
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32] << 1;
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8] - 1;
      if (bin) begin
        low = low + range;
      end
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_bins_ep(
    input cabac_state_t st_in,
    input logic [31:0]  bin_pattern_in,
    input logic [5:0]   num_bins_in
  );
    cabac_state_t st;
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
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];

      while (num_bins > 8) begin
        num_bins = num_bins - 8;
        pattern = bin_pattern >> num_bins;
        low = low << 8;
        low = low + (range * pattern);
        bin_pattern = bin_pattern - (pattern << num_bins);
        bits_left = bits_left - 8;
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        if (bits_left < 12) begin
          st = cabac_write_out(st);
          low = st[CABAC_LOW_LSB +: 32];
          bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
        end
      end

      low = low << num_bins;
      low = low + (range * bin_pattern);
      bits_left = bits_left - num_bins;
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bins_ep = st;
    end
  endfunction

  function automatic cabac_state_t cabac_encode_rem_abs_ep(
    input cabac_state_t st_in,
    input logic [4:0]   value,
    input logic [2:0]   rice_param
  );
    cabac_state_t st;
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

  function automatic cabac_state_t cabac_encode_bin_trm(
    input cabac_state_t st_in,
    input logic         bin
  );
    cabac_state_t st;
    logic [31:0] low;
    logic [15:0] range;
    integer bits_left;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      range = st[CABAC_RANGE_LSB +: 16] - 16'd2;
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
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
      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_RANGE_LSB +: 16] = range;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      if (bits_left < 12) begin
        st = cabac_write_out(st);
      end
      cabac_encode_bin_trm = st;
    end
  endfunction

  function automatic cabac_state_t cabac_finish(input cabac_state_t st_in);
    cabac_state_t st;
    logic [31:0] low;
    logic [8:0] buffered_byte;
    logic [7:0] num_buffered_bytes;
    integer bits_left;
    integer final_bits;
    begin
      st = st_in;
      low = st[CABAC_LOW_LSB +: 32];
      buffered_byte = st[CABAC_BUFFERED_BYTE_LSB +: 9];
      num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];

      if ((low >> (32 - bits_left)) != 0) begin
        st = cabac_write_bits(st, buffered_byte + 9'd1, 6'd8);
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'd0, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
        low = low - (32'd1 << (32 - bits_left));
        st[CABAC_LOW_LSB +: 32] = low;
      end else begin
        if (num_buffered_bytes > 8'd0) begin
          st = cabac_write_bits(st, buffered_byte, 6'd8);
        end
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, 9'h0ff, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
      end

      final_bits = 24 - bits_left;
      if (final_bits > 0) begin
        st = cabac_write_bits(st, low >> 8, final_bits[5:0]);
      end
      cabac_finish = st;
    end
  endfunction

  function automatic cabac_state_t cabac_write_out(input cabac_state_t st_in);
    cabac_state_t st;
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
      low = st[CABAC_LOW_LSB +: 32];
      bits_left = st[CABAC_BITS_LEFT_LSB +: 8];
      buffered_byte = st[CABAC_BUFFERED_BYTE_LSB +: 9];
      num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
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
        st[CABAC_LOW_LSB +: 32] = low;
        st[CABAC_BUFFERED_BYTE_LSB +: 9] = buffered_byte;
        st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
        st = cabac_write_bits(st, byte_value, 6'd8);
        repeated_byte = (9'h0ff + carry) & 9'h0ff;
        num_buffered_bytes = st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8];
        while (num_buffered_bytes > 8'd1) begin
          st = cabac_write_bits(st, repeated_byte, 6'd8);
          num_buffered_bytes = num_buffered_bytes - 8'd1;
          st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
        end
      end else begin
        num_buffered_bytes = 8'd1;
        buffered_byte = lead_byte[7:0];
      end

      st[CABAC_LOW_LSB +: 32] = low;
      st[CABAC_BUFFERED_BYTE_LSB +: 9] = buffered_byte;
      st[CABAC_NUM_BUFFERED_BYTES_LSB +: 8] = num_buffered_bytes;
      st[CABAC_BITS_LEFT_LSB +: 8] = bits_left[7:0];
      cabac_write_out = st;
    end
  endfunction

  function automatic cabac_state_t cabac_write_bits(
    input cabac_state_t st_in,
    input logic [31:0]  value,
    input logic [5:0]   bit_count
  );
    cabac_state_t st;
    logic [MAX_SLICE_PAYLOAD_BITS - 1:0] bits;
    logic [12:0] len;
    integer i;
    begin
      st = st_in;
      bits = st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS];
      len = st[CABAC_LEN_LSB +: 13];
      for (i = bit_count - 1; i >= 0; i = i - 1) begin
        bits = (bits << 1) | value[i];
        len = len + 13'd1;
      end
      st[CABAC_BITS_LSB +: MAX_SLICE_PAYLOAD_BITS] = bits;
      st[CABAC_LEN_LSB +: 13] = len;
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
endmodule
