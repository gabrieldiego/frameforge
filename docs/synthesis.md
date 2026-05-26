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

For actual Zynq timing, use the optional Vivado path.  The scripts first honor
explicit environment overrides, then look for a project-local Vivado install
under `.tools/Xilinx`.  Vivado still requires AMD's installer, account, and
license flow.

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

FrameForge keeps a tracked Vivado install template at
`synth/vivado/install_config.template`.  The generated machine-local config is
written under `.tools/` and remains untracked because it contains absolute local
paths.

Prepare a local install area:

```sh
make vivado-prepare VIVADO_LICENSE="$HOME/Downloads/Xilinx.lic"
make vivado-config
```

If the AMD web installer has already been downloaded, extract it into `.tools`:

```sh
python3 scripts/setup_vivado.py extract \
  --installer "$HOME/Downloads/FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1114_2157_Lin64.bin"
```

Generate an AMD authentication token when needed:

```sh
make vivado-auth
```

Run the install:

```sh
make vivado-install
```

If the checkout is mounted over `sshfs`, prefer running the same commands on the
machine that physically owns the storage device.  The generated config must be
created on that machine so `Destination=` uses the host's real mount path rather
than the sshfs client path.

If Vivado is installed locally by AMD `xsetup` under `.tools/Xilinx`, the
synthesis runner detects:

- `.tools/Xilinx/Vivado/*/bin/vivado`
- `.tools/Xilinx/Vivado/*/settings64.sh`
- `.tools/Xilinx.lic`

You can also point at existing machine-wide resources without using the local
install:

```sh
export SYNTH_VIVADO=/path/to/vivado
export VIVADO_SETTINGS=/path/to/Vivado/2025.2/settings64.sh
export XILINXD_LICENSE_FILE=/path/to/Xilinx.lic
```

Run vendor synthesis:

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
