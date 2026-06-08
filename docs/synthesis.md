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

## Top Encoder Baseline

Measured on June 7, 2026 at commit `e8d2624` with a verbose diagnostic run:

```sh
make synth SYNTH_DUT=vvc-encoder SYNTH_TIMEOUT_SEC=900 SYNTH_MEMORY_LIMIT_MB=6144 SYNTH_YOSYS_QUIET=0
```

Configuration:

- target: Arty Z7-10 (`xc7z010clg400-1`)
- clock metadata: 50 MHz
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- synthesis timeout: 900 seconds for measurement; routine synthesis now uses a
  300 second review threshold and a 600 second hard timeout
- synthesis memory cap: 6144 MiB for measurement; routine synthesis now uses a
  3072 MiB Yosys memory cap
- Yosys quiet logging: disabled for the measurement so module pressure points
  are visible in the log
- chroma residual subset: DC plus the 2x2 low-frequency AC group

Result:

- Top `ff_vvc_encoder` synthesis completed in 306.8 seconds with 1792.47 MB
  peak memory. This exceeds the current 300 second review threshold but is
  inside the 600 second default timeout.
- Estimated area: 44,096 LCs and 107,946 total cells, including 16,348 `FDRE`,
  8,288 `FDCE`, 288 `FDPE`, 4 `FDSE`, 24,558 `LUT6`, 11,795 `LUT2`,
  9,299 `MUXF7`, 1,772 `MUXF8`, 3,776 `CARRY4`, 7 `DSP48E1`, and 3 `RAMB36E1`.
- Post-synthesis critical-path reporting completed in 73.5 seconds and reported
  a peak memory of 1781.84 MB.
- Longest topological path length: 155, from `current_ctu_y_q` through visible
  CTU geometry and luma quantizer visibility/control into
  `luma_quant_recon.negative`.
- Compared with the June 6, 2026 baseline, timing stayed at path length 155.
  Runtime increased from 288.1 to 306.8 seconds, and critical-path report memory
  increased from 1301.47 to 1781.84 MB.
- Reports and artifacts:
  `synth/out/arty-z7-10/ff_vvc_encoder/yosys.log`,
  `synth/out/arty-z7-10/ff_vvc_encoder/critical_path.log`,
  `synth/out/arty-z7-10/ff_vvc_encoder/ff_vvc_encoder.post_synth.v`.

## Top Encoder Timing Optimization

Measured on June 8, 2026 after replacing the top-level 64-bit luma visibility
mask with per-TU visible column/row counts passed into
`ff_vvc_luma_quant_recon_8x8`.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

This run was made before the default memory cap was raised from 2048 to 3072
MiB. The higher default leaves margin for the ongoing optimization work because
the critical-path pass still approaches 2 GiB.

Result:

- Longest topological path improved from 155 to 146. The old path ran through
  the generated `luma_quant_visible_mask_w` mux chain into
  `luma_quant_recon.negative`; after this change the longest path moves into
  the chroma quant/reconstruction reference update path.
- Critical-path reporting completed in about 60 seconds with 1774.43 MB peak
  memory.
- Quiet top synthesis completed in roughly 291 seconds by artifact timestamps.
  The runner now records elapsed time and observed child RSS explicitly so
  future quiet runs leave a direct benchmark line in the log.
- Post-synth netlist restat reported 107,602 total cells and 44,291 estimated
  LCs. Compared with the June 7 baseline, total cells decreased by 344 while
  estimated LCs increased by 195.
- The luma quant/reconstruction module itself improved from 6,050 to 5,867
  estimated LCs, matching the intended removal of the visibility-mask muxing
  pressure.

## Top Encoder Chroma Edge Optimization

Measured on June 8, 2026 after changing `ff_vvc_chroma_quant_recon_420` to
emit only the reconstructed bottom row and right column needed by the 4:2:0
neighbour-reference path. The module no longer exports a full 4x4 reconstructed
sample block because the current RTL only consumes those edge samples for the
next chroma TU.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 282.4 seconds with 1808.77 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 54.9 seconds. The Yosys report itself
  recorded 1612.48 MB peak memory; the runner observed the same 1808.77 MiB
  peak child RSS across the full synthesis plus report flow.
- Longest topological path improved from 146 to 103. The path still starts at
  visible CTU geometry, but now runs through chroma TU ordering and the chroma
  quant/reconstruction edge update instead of the previous full reconstructed
  chroma-sample mux chain.
- Post-synth netlist restat reported 106,350 total cells and 43,758 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 1,252
  and estimated LCs decreased by 533.
- The standalone `ff_vvc_chroma_quant_recon_420` module restat reported 9,180
  cells and 5,808 estimated LCs.

## Top Encoder Sequential Chroma Quantization

Measured on June 8, 2026 after converting `ff_vvc_chroma_quant_recon_420` from
a fully combinational 4x4 transform/quant/reconstruction block into a small
registered datapath. The Cb and Cr instances still run in parallel, but each
instance now accumulates the 16 chroma samples over time, registers the DC and
2x2 low-frequency AC levels, and reconstructs only the bottom/right neighbour
edges used by the next chroma TU.

This trades the previous one-cycle chroma TU calculation for a short sequential
TU pass, but removes the full residual-to-reconstruction chain from the
top-level combinational timing path.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 272.2 seconds with 1750.73 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 54.8 seconds. The Yosys report itself
  recorded 1627.06 MB peak memory.
- Longest topological path improved from 103 to 58. The path now ends at the
  chroma AC accumulator register instead of continuing through chroma
  quantization, inverse transform, clipping, and neighbour-reference update.
- Post-synth netlist restat reported 101,591 total cells and 37,819 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 4,759
  and estimated LCs decreased by 5,939.
- The standalone `ff_vvc_chroma_quant_recon_420` module restat reported 4,709
  cells and 1,829 estimated LCs, down from 9,180 cells and 5,808 estimated LCs.

## Top Encoder Chroma Input Registering

Measured on June 8, 2026 after adding an input-load state to
`ff_vvc_chroma_quant_recon_420`. Each chroma quant/reconstruction instance now
latches the 4x4 sample TU plus its top/left neighbour references before the
sample-accumulation pass. This cuts the path from top-level chroma TU geometry
and neighbour-reference muxing into the chroma AC accumulator.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 273.0 seconds with 1729.66 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.0 seconds.
- Longest topological path improved from 58 to 52. The path moved out of the
  chroma quantizer and now ends in the residual symbol emitter's coefficient
  scan/rice-prefix path.
- Post-synth netlist restat reported 101,435 total cells and 37,957 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 156 and
  estimated LCs increased by 138, keeping area effectively flat while improving
  timing.
- The standalone `ff_vvc_chroma_quant_recon_420` module restat reported 5,254
  cells and 2,023 estimated LCs; the increase is the expected cost of the
  registered input samples and references.

## Top Encoder Residual Remainder Registering

Measured on June 8, 2026 after registering the residual symbol emitter's
remainder prefix/suffix EP payloads before presenting them on `m_axis_data`.
The regular residual scan captures the payload after the `gt3` decision, and
the second-pass residual path uses a short prep subphase before prefix/suffix
emission. This removes remainder construction from the output mux timing path.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 270.4 seconds with 1690.82 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.2 seconds.
- Longest topological path improved from 52 to 49. The path remains in the
  residual symbol emitter's scan/rice path, but no longer carries the full
  remainder prefix/suffix payload construction through the output mux.
- Post-synth netlist restat reported 97,960 total cells and 36,737 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 3,475
  and estimated LCs decreased by 1,220.
- The standalone `ff_vvc_residual_symbol_emitter_4x4` module restat reported
  3,608 cells and 1,543 estimated LCs. The local module grew slightly from the
  added payload registers, but the top-level netlist simplified overall.

## Top Encoder Residual Neighbor Table

Measured on June 8, 2026 after replacing the residual symbol emitter's dynamic
4x4 local-neighbor loop with a fixed scan-position neighbor table. The table
keeps the VVC residual local-template candidates explicit for each supported
4x4 scan position and avoids inferring local coordinate arithmetic and dynamic
coefficient indexing in the rice/remainder path.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 271.5 seconds with 1683.05 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.7 seconds.
- Longest topological path improved from 49 to 47. The residual emitter is no
  longer the longest path; the reported path now runs through the Annex B header
  width/slice-count Exp-Golomb path.
- Post-synth netlist restat reported 97,813 total cells and 36,608 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 147 and
  estimated LCs decreased by 129.
- The standalone `ff_vvc_residual_symbol_emitter_4x4` module restat reported
  3,854 cells and 1,607 estimated LCs. The local module grows because the
  neighbor table is explicit, but the top-level netlist simplifies and the
  residual path stops limiting the topological timing report.

## Top Encoder Direct CTU Geometry

Measured on June 8, 2026 after deriving Annex B header CTU column and row counts
directly from the visible dimensions. Since `ceil(ceil(visible, 8) / 64)` is
equivalent to `ceil(visible / 64)`, the header can keep coded-width/height
alignment for SPS dimensions and crop offsets while avoiding that alignment
logic on the CTU-count and slice-count path.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 273.2 seconds with 1683.44 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.2 seconds.
- Longest topological path improved from 47 to 45. The path remains in the
  Annex B header slice-count Exp-Golomb path, but no longer passes through the
  coded-width alignment stage.
- Post-synth netlist restat reported 97,714 total cells and 36,602 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 99 and
  estimated LCs decreased by 6.
- The standalone `ff_vvc_annexb_header` module restat reported 1,438 cells and
  725 estimated LCs, down from 1,537 cells and 747 estimated LCs.

## Top Encoder Bounded Annex B Slice Count

Measured on June 8, 2026 after threading the encoder's configured
`MAX_VISIBLE_WIDTH` and `MAX_VISIBLE_HEIGHT` parameters into the Annex B header.
For the current 1024x1024 synthesis target, the PPS rectangular-slice count is
bounded to 16 CTU columns by 16 CTU rows, so the slice-count UE path uses a
bounded 8-bit `slice_count_minus1` value instead of a generic 16-bit UE helper.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=128 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=128 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The 64x64 single-CTU smoke and 128x64 two-CTU smoke both passed all three
cocotb encoder checks, including the luma AC and chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 271.0 seconds with 1693.26 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.1 seconds.
- Longest topological path improved from 45 to 40. The Annex B slice-count UE
  path is no longer the longest path; the reported path now runs through the
  4:4:4 palette CU symbolizer's index lookup/update path.
- Post-synth netlist restat reported 97,535 total cells and 36,570 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 179 and
  estimated LCs decreased by 32.
- The standalone `ff_vvc_annexb_header` module restat reported 1,176 cells and
  559 estimated LCs, down from 1,438 cells and 725 estimated LCs.

## Optional Vivado Synthesis

FrameForge keeps a tracked Vivado install template at
`synth/vivado/install_config.template`.  The generated machine-local config is
written under `.tools/` and remains untracked because it contains absolute local
paths.

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
