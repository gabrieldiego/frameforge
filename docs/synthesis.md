# Synthesis Smoke Flow

FrameForge has an optional synthesis path for checking whether the RTL has a
reasonable synthesis surface before it is ready for full FPGA integration.

The initial board target is the Digilent Arty Z7-10, SKU `410-346-10`, which
uses the Xilinx Zynq-7000 `XC7Z010-1CLG400C`.  The scripts keep board settings
in small `.env` files so another Zynq-7000 or 7-series board can be selected
without editing the synthesis runner.

## Tool Choices

The default flow uses `oss-cad-suite`:

- `yosys` for open-source synthesis and utilization estimates
- `iverilog`/`vvp` for optional post-synthesis smoke simulation

This is intended to catch unsupported RTL constructs and track rough resource
growth.  It is not a replacement for vendor place-and-route timing.

For actual Zynq timing, use the optional Vivado path.  Vivado is detected by the
scripts, but it is not downloaded automatically because AMD/Xilinx distribution
requires a separate installer/account/license flow.

## Setup

Install or detect the local synthesis environment:

```sh
make synth-env
```

If you only want to see what is installed:

```sh
make synth-check
```

If `make synth-env` installs `oss-cad-suite`, add it to the current shell:

```sh
export PATH="$PWD/.tools/oss-cad-suite/bin:$PATH"
```

## Open-Source Synthesis

Run the default synthesis smoke target:

```sh
make synth
```

Defaults:

- board: `synth/boards/arty-z7-10.env`
- top: `ff_vvc_cabac_8x8_stream_body`
- file list: `synth/filelists/cabac_8x8.f`
- clock metadata: `50 MHz`

Override these from the command line:

```sh
make synth \
  SYNTH_BOARD=synth/boards/arty-z7-20.env \
  SYNTH_TOP=ff_vvc_cabac_8x8_stream_body \
  SYNTH_FILELIST=synth/filelists/cabac_8x8.f \
  SYNTH_CLOCK_MHZ=100
```

Outputs are written under `synth/out/`, which is intentionally gitignored.

## Post-Synthesis Smoke Simulation

For the default CABAC 8x8 streaming top, run:

```sh
make synth-postsim
```

This runs Yosys, writes a Xilinx-cell post-synthesis Verilog netlist, compiles it
with Icarus using Yosys' Xilinx simulation cell library, and checks that the
design can leave reset, accept `start`, and eventually assert `done`.

## Optional Vivado Synthesis

After installing Vivado separately and placing `vivado` on `PATH`:

```sh
make synth-vivado
```

The generated Vivado TCL creates an in-memory project, reads the configured RTL
file list, runs `synth_design`, applies a clock constraint to `clk`, and writes
utilization and timing summary reports under `synth/out/`.

## Current Scope

This flow is currently a synthesis smoke check.  It does not:

- create a board bitstream
- define Arty Z7 pin constraints
- integrate the Zynq PS
- run implementation/place-and-route in the open-source flow
- validate VVC conformance

Those steps should be added only after the RTL block interfaces stabilize.
