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
- DUT source selection: `vvc-cabac-stream-writer`, derived from `tb/Makefile`
- top: derived from the selected `SYNTH_DUT`
- clock metadata: `50 MHz`

Override these from the command line:

```sh
make synth \
  SYNTH_BOARD=synth/boards/arty-z7-20.env \
  SYNTH_DUT=vvc-cabac-stream-writer \
  SYNTH_CLOCK_MHZ=100
```

`SYNTH_TOP` and `SYNTH_FILELIST` remain available as explicit overrides, but the
normal path reuses the same DUT source selection as RTL simulation to avoid
separate stale synthesis file lists.

Outputs are written under `synth/out/`, which is intentionally gitignored.

## Post-Synthesis Smoke Simulation

For the default CABAC stream writer top, run:

```sh
make synth-postsim
```

This runs Yosys, writes a Xilinx-cell post-synthesis Verilog netlist, compiles it
with Icarus using Yosys' Xilinx simulation cell library, and checks that the
design can leave reset, accept `start`, and eventually assert `done`.

## Recent CABAC Context Results

On June 4, 2026, the VVC CABAC residual-context bank was expanded from 70 to
265 context IDs so the RTL has initialized entries for the H.266 Table 132
last-significant, subblock-coded, significant-coefficient, parity-level, and
absolute-level residual ranges. The first expanded implementation bulk-reset a
packed 40-bit context table and caused the focused context-model Yosys run to
time out at 120 seconds.

The xk265 CABAC context path keeps a narrow initialized context table and
separates context initialization from live context updates. The VVC model uses
the same separation but cannot reuse xk265's 7-bit H.265 state representation:
H.266 stores two adaptive 16-bit probability states per context. To avoid a
wide reset fabric, reset invalidates the VVC table state instead of rewriting
every context entry in one cycle. The per-context rate byte is derived from the
static H.266 init table because it never changes after initialization.

Measured with `make synth SYNTH_DUT=vvc-cabac-context-model
SYNTH_TIMEOUT_SEC=120` on the Arty Z7-10 target:

- Yosys completed in 37.21 seconds user CPU, peak memory 562.55 MB.
- Estimated LCs: 9,677.
- Sequential cells: 8,480 `FDRE` for adaptive state and 265 `FDCE` for the
  valid bitmap.
- Longest topological path length: 11, from context ID bounds/mux through
  initial-state selection, LPS calculation, and `query_lps_full`.

Measured with `make synth SYNTH_DUT=vvc-cabac-stream-writer
SYNTH_TIMEOUT_SEC=120`:

- Yosys completed in 45.27 seconds user CPU, peak memory 567.25 MB.
- Design hierarchy estimated LCs: 11,355.
- Sequential cells: 8,480 `FDRE`, 489 `FDCE`, and 20 `FDPE`.
- Longest topological path length: 33, from `s_axis_ctx_id` through context
  lookup/LPS calculation, CABAC bin renormalization, and stream-writer state
  update.

Yosys still reports the context arrays as register lists because the current
stream writer consumes the queried context in the same cycle. Moving to a true
RAM-backed context table, like a staged xk265-style path, requires a pipeline
boundary between symbol input, context read/update, and bin coding.

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
