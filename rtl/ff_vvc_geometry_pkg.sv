package ff_vvc_geometry_pkg;
  // Keep this in sync with frameforge::vvc::VVC_CODED_DIMENSION_GRANULARITY
  // and scripts/validate.py. It is the current validation-path coded-picture
  // luma dimension alignment, not a general statement about every VVC profile.
  localparam int VVC_CODED_DIMENSION_GRANULARITY = 8;

  function automatic logic [15:0] ff_vvc_coded_dimension(input logic [15:0] value);
    begin
      if (value <= VVC_CODED_DIMENSION_GRANULARITY[15:0]) begin
        ff_vvc_coded_dimension = VVC_CODED_DIMENSION_GRANULARITY[15:0];
      end else begin
        ff_vvc_coded_dimension =
          ((value + VVC_CODED_DIMENSION_GRANULARITY[15:0] - 16'd1) /
           VVC_CODED_DIMENSION_GRANULARITY[15:0]) *
          VVC_CODED_DIMENSION_GRANULARITY[15:0];
      end
    end
  endfunction
endpackage
