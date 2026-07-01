# Synthesis Flow

FrameForge synthesis is codec-aware, but the flow is shared. VVC and AV2 are
built as separate top-level designs, so measured area, timing, elapsed time, and
memory baselines belong in codec-specific reports.

Codec-specific reports:

- [VVC synthesis baselines](vvc/synthesis.md)
- [AV2 synthesis baselines](av2/synthesis.md)

Current synthesis runtime and memory targets are tracked in
[validation/targets.md](validation/targets.md).

The encoder top-level integration interface is shared across codecs and is
documented in [rtl/hardware-interface.md](rtl/hardware-interface.md). Synthesis
reports should continue to be codec-specific because each codec top instantiates
different syntax and coding-tool logic behind that common interface.

## Tool Choices

The default open-source flow uses `oss-cad-suite`:

- `yosys` for synthesis and rough utilization estimates.
- `iverilog`/`vvp` for optional post-synthesis smoke simulation.

This catches unsupported RTL constructs and tracks approximate resource growth.
It is not a replacement for vendor place-and-route timing.

For actual Zynq timing, use the optional Vivado path. The scripts first honor
explicit environment overrides, then look for a project-local Vivado install
under `.tools/Xilinx`. Vivado still requires AMD's installer, account, and
license flow.

The initial board target is the Digilent Arty Z7-10, SKU `410-346-10`, which
uses the Xilinx Zynq-7000 `XC7Z010-1CLG400C`. Board settings live in small
`.env` files so another Zynq-7000 or 7-series board can be selected without
editing the synthesis runner.

## Setup

Install or detect the local open-source synthesis environment:

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

Run synthesis for a codec:

```sh
make synth CODEC=vvc
make synth CODEC=av2
```

Defaults:

- board: `synth/boards/arty-z7-10.env`
- top: derived from the selected `SYNTH_DUT`
- clock metadata: `25 MHz`
- timeout: 900 seconds, with a 600 second review warning
- Yosys memory cap: 3072 MiB
- VVC default DUT: `vvc-cabac-stream-writer`
- AV2 default DUT: `av2-encoder`

Override the DUT, board, clock metadata, timeout, memory cap, and codec-specific
parameters from the command line:

```sh
make synth \
  CODEC=vvc \
  SYNTH_DUT=vvc-encoder \
  SYNTH_BOARD=synth/boards/arty-z7-20.env \
  SYNTH_CLOCK_MHZ=25 \
  SYNTH_TIMEOUT_SEC=900 \
  SYNTH_WARN_AFTER_SEC=600 \
  SYNTH_MEMORY_LIMIT_MB=3072
```

`SYNTH_TOP` and `SYNTH_FILELIST` remain available as explicit overrides, but the
normal path reuses the same DUT source selection as RTL simulation to avoid
separate stale synthesis file lists.

Outputs are written under `synth/out/`, which is intentionally gitignored.

## Post-Synthesis Smoke Simulation

Run Yosys, write a Xilinx-cell post-synthesis Verilog netlist, compile it with
Icarus using Yosys' Xilinx simulation cell library, and run the smoke simulation
when the selected DUT supports it:

```sh
make synth-postsim CODEC=vvc
```

## Vivado Synthesis

FrameForge keeps a tracked Vivado install template at
`synth/vivado/install_config.template`. The generated machine-local config is
written under `.tools/` and remains untracked because it contains absolute local
paths.

The preferred local install helper keeps the Vivado payload, extracted installer,
temporary files, installer home, XDG cache/config state, and license copy under
this checkout's `.tools/` directory. When `bubblewrap` is available, AMD `xsetup`
runs with `/` mounted read-only and `.tools/` as the writable install/cache area:

```sh
./install-vivado-local.sh \
  --installer "/path/to/FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1114_2157_Lin64.bin" \
  --license "/path/to/Xilinx.lic"
```

If the AMD authentication token has expired, regenerate it inside the same
project-local home first:

```sh
./install-vivado-local.sh \
  --installer "/path/to/FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1114_2157_Lin64.bin" \
  --license "/path/to/Xilinx.lic" \
  --force-auth \
  --skip-install
```

Prepare a local install area:

```sh
make vivado-prepare VIVADO_LICENSE="/path/to/Xilinx.lic"
make vivado-config
```

If the AMD web installer has already been downloaded, extract it into `.tools`:

```sh
python3 scripts/setup_vivado.py extract \
  --installer "/path/to/FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1114_2157_Lin64.bin"
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
machine that physically owns the storage device. The generated config must be
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
make synth-vivado CODEC=vvc
```

Vivado defaults to two internal worker threads in this flow. The cap keeps
memory pressure predictable on development machines while still allowing
parallel optimization. Use `SYNTH_VIVADO_MAX_THREADS=0` to leave thread
selection to Vivado, or set an explicit smaller/larger integer for a given run:

```sh
make synth-vivado CODEC=av2 SYNTH_VIVADO_MAX_THREADS=1
```

The generated Vivado TCL creates an in-memory project, reads the configured RTL
file list, runs `synth_design`, applies a clock constraint to `clk`, and writes
utilization and timing summary reports under `synth/out/`.

## Current Scope

This flow is currently a synthesis smoke check. It does not:

- create a board bitstream
- define Arty Z7 pin constraints
- integrate the Zynq PS
- run implementation/place-and-route in the open-source flow
- validate codec conformance

Those steps should be added only after the RTL block interfaces stabilize.
