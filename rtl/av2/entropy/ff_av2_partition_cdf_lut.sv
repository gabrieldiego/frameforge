`timescale 1ns/1ps

module ff_av2_partition_cdf_lut (
  input  logic [5:0] split_ctx,
  input  logic [5:0] rect_ctx,
  output logic [31:0] do_split_cdf0,
  output logic [31:0] rect_type_cdf0
);

  // AV2 v1.0.0 Section 8.9.2 maps read_partition() symbols to
  // TileDoSplitCdf[PlaneStart][ctx] and TileRectTypeCdf[PlaneStart][ctx].
  // The black 4:4:4 path disables CDF updates, so these are the first inverse
  // CDF entries initialized from Default_Do_Split_Cdf and Default_Rect_Type_Cdf
  // as listed in the spec default CDF header references.
  always @* begin
    do_split_cdf0 = 32'd0;
    case (split_ctx)
      6'd0: do_split_cdf0 = 32'd4684;
      6'd1: do_split_cdf0 = 32'd9013;
      6'd2: do_split_cdf0 = 32'd9134;
      6'd3: do_split_cdf0 = 32'd13400;
      6'd4: do_split_cdf0 = 32'd7807;
      6'd5: do_split_cdf0 = 32'd17827;
      6'd6: do_split_cdf0 = 32'd16614;
      6'd7: do_split_cdf0 = 32'd26863;
      6'd8: do_split_cdf0 = 32'd10834;
      6'd9: do_split_cdf0 = 32'd22328;
      6'd10: do_split_cdf0 = 32'd20784;
      6'd11: do_split_cdf0 = 32'd29294;
      6'd12: do_split_cdf0 = 32'd12276;
      6'd13: do_split_cdf0 = 32'd25805;
      6'd14: do_split_cdf0 = 32'd24669;
      6'd15: do_split_cdf0 = 32'd31239;
      6'd16: do_split_cdf0 = 32'd8651;
      6'd17: do_split_cdf0 = 32'd24897;
      6'd18: do_split_cdf0 = 32'd9164;
      6'd19: do_split_cdf0 = 32'd24339;
      6'd20: do_split_cdf0 = 32'd5412;
      6'd21: do_split_cdf0 = 32'd10327;
      6'd22: do_split_cdf0 = 32'd23871;
      6'd23: do_split_cdf0 = 32'd25957;
      6'd24: do_split_cdf0 = 32'd15176;
      6'd25: do_split_cdf0 = 32'd27120;
      6'd26: do_split_cdf0 = 32'd27429;
      6'd27: do_split_cdf0 = 32'd31686;
      6'd28: do_split_cdf0 = 32'd6625;
      6'd29: do_split_cdf0 = 32'd21389;
      6'd30: do_split_cdf0 = 32'd12626;
      6'd31: do_split_cdf0 = 32'd25367;
      6'd32: do_split_cdf0 = 32'd6533;
      6'd33: do_split_cdf0 = 32'd9094;
      6'd34: do_split_cdf0 = 32'd20327;
      6'd35: do_split_cdf0 = 32'd22286;
      6'd36: do_split_cdf0 = 32'd12105;
      6'd37: do_split_cdf0 = 32'd28576;
      6'd38: do_split_cdf0 = 32'd27494;
      6'd39: do_split_cdf0 = 32'd32055;
      6'd40: do_split_cdf0 = 32'd4513;
      6'd41: do_split_cdf0 = 32'd5398;
      6'd42: do_split_cdf0 = 32'd9241;
      6'd43: do_split_cdf0 = 32'd11778;
      6'd44: do_split_cdf0 = 32'd6041;
      6'd45: do_split_cdf0 = 32'd11581;
      6'd46: do_split_cdf0 = 32'd7444;
      6'd47: do_split_cdf0 = 32'd14930;
      6'd48: do_split_cdf0 = 32'd6632;
      6'd49: do_split_cdf0 = 32'd16177;
      6'd50: do_split_cdf0 = 32'd12930;
      6'd51: do_split_cdf0 = 32'd22163;
      6'd52: do_split_cdf0 = 32'd9854;
      6'd53: do_split_cdf0 = 32'd20159;
      6'd54: do_split_cdf0 = 32'd21427;
      6'd55: do_split_cdf0 = 32'd28212;
      6'd56: do_split_cdf0 = 32'd8550;
      6'd57: do_split_cdf0 = 32'd19709;
      6'd58: do_split_cdf0 = 32'd17390;
      6'd59: do_split_cdf0 = 32'd26910;
      6'd60: do_split_cdf0 = 32'd11124;
      6'd61: do_split_cdf0 = 32'd25001;
      6'd62: do_split_cdf0 = 32'd24459;
      6'd63: do_split_cdf0 = 32'd31081;
    endcase

    rect_type_cdf0 = 32'd0;
    case (rect_ctx)
      6'd0: rect_type_cdf0 = 32'd18124;
      6'd1: rect_type_cdf0 = 32'd22595;
      6'd2: rect_type_cdf0 = 32'd14239;
      6'd3: rect_type_cdf0 = 32'd16697;
      6'd4: rect_type_cdf0 = 32'd12505;
      6'd5: rect_type_cdf0 = 32'd19955;
      6'd6: rect_type_cdf0 = 32'd6156;
      6'd7: rect_type_cdf0 = 32'd9491;
      6'd8: rect_type_cdf0 = 32'd22174;
      6'd9: rect_type_cdf0 = 32'd25768;
      6'd10: rect_type_cdf0 = 32'd12766;
      6'd11: rect_type_cdf0 = 32'd19879;
      6'd12: rect_type_cdf0 = 32'd18914;
      6'd13: rect_type_cdf0 = 32'd22018;
      6'd14: rect_type_cdf0 = 32'd14388;
      6'd15: rect_type_cdf0 = 32'd15263;
      6'd16: rect_type_cdf0 = 32'd18338;
      6'd17: rect_type_cdf0 = 32'd21214;
      6'd18: rect_type_cdf0 = 32'd12690;
      6'd19: rect_type_cdf0 = 32'd13671;
      6'd20: rect_type_cdf0 = 32'd17490;
      6'd21: rect_type_cdf0 = 32'd22631;
      6'd22: rect_type_cdf0 = 32'd10847;
      6'd23: rect_type_cdf0 = 32'd18147;
      6'd24: rect_type_cdf0 = 32'd13438;
      6'd25: rect_type_cdf0 = 32'd16847;
      6'd26: rect_type_cdf0 = 32'd6550;
      6'd27: rect_type_cdf0 = 32'd8450;
      6'd28: rect_type_cdf0 = 32'd16384;
      6'd29: rect_type_cdf0 = 32'd16384;
      6'd30: rect_type_cdf0 = 32'd16384;
      6'd31: rect_type_cdf0 = 32'd16384;
      6'd32: rect_type_cdf0 = 32'd16384;
      6'd33: rect_type_cdf0 = 32'd16384;
      6'd34: rect_type_cdf0 = 32'd16384;
      6'd35: rect_type_cdf0 = 32'd16384;
      6'd36: rect_type_cdf0 = 32'd16702;
      6'd37: rect_type_cdf0 = 32'd23543;
      6'd38: rect_type_cdf0 = 32'd9919;
      6'd39: rect_type_cdf0 = 32'd17951;
      6'd40: rect_type_cdf0 = 32'd16384;
      6'd41: rect_type_cdf0 = 32'd16384;
      6'd42: rect_type_cdf0 = 32'd16384;
      6'd43: rect_type_cdf0 = 32'd16384;
      6'd44: rect_type_cdf0 = 32'd16384;
      6'd45: rect_type_cdf0 = 32'd16384;
      6'd46: rect_type_cdf0 = 32'd16384;
      6'd47: rect_type_cdf0 = 32'd16384;
      6'd48: rect_type_cdf0 = 32'd14225;
      6'd49: rect_type_cdf0 = 32'd19558;
      6'd50: rect_type_cdf0 = 32'd8401;
      6'd51: rect_type_cdf0 = 32'd14351;
      6'd52: rect_type_cdf0 = 32'd8067;
      6'd53: rect_type_cdf0 = 32'd13857;
      6'd54: rect_type_cdf0 = 32'd3178;
      6'd55: rect_type_cdf0 = 32'd4990;
      6'd56: rect_type_cdf0 = 32'd29368;
      6'd57: rect_type_cdf0 = 32'd31833;
      6'd58: rect_type_cdf0 = 32'd22403;
      6'd59: rect_type_cdf0 = 32'd31045;
      6'd60: rect_type_cdf0 = 32'd16384;
      6'd61: rect_type_cdf0 = 32'd16384;
      6'd62: rect_type_cdf0 = 32'd16384;
      6'd63: rect_type_cdf0 = 32'd16384;
    endcase
  end

endmodule
