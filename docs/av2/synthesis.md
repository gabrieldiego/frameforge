# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-20 AVM-Order Local IBC BVP Stack

Measured after changing the AV2 4:4:4 exact-hash IntraBC BVP stack to follow
the AVM spatial-candidate order before default BVs. The implementation still
stores only one 32-bit hash per 8x8 block inside the current 64x64 tile and
does not fetch any IBC context from external memory.

Baseline and current sources:

- Baseline Git SHA: `fecba0947c6b46f801f0394a8e0699f68c1c542f`
- Current validated RTL Git SHA: `307363b80a71d77e19178e972a522c42bf8bfe1c`
- Baseline mode: previous documented AV2 AVM-valid local hash IBC checkpoint.
- Current mode: AVM-order spatial BVP stack with conservative left-copy-only
  IBC selection.
- Delta columns compare against the previous documented AV2 synthesis
  checkpoint.

Validation result:

- `cargo test av2 --lib`: OK (25/25).
- `screenshot-sweep-444`: OK (64/64), strict SW/RTL bitstream parity and
  SW/RTL/reference-decoder lossless reconstruction parity.
- `screenshot-multictu-444`: OK (10/10), same parity checks.
- Yosys synthesis: PASS.
- Vivado `synth_design`: PASS on the remote Vivado checkout.
- Vivado post-synthesis Z7-10 fit/timing: FAIL at 25 MHz. The netlist exceeds
  the xc7z010 LUT/register capacity and has negative setup slack.

Yosys synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled,
  lossy 4:2:0 residual enabled
- max visible size: 1024x1024

Yosys synthesis result:

- Yosys synthesis passed in 415.8 seconds.
- Peak child RSS observed by the synthesis runner was 1695.05 MiB.
- Runtime exceeded the 300 second review threshold but completed inside the
  600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 7.1 seconds.
- Post-synthesis critical-path reporting completed in 100.6 seconds.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.
- The top `ff_av2_encoder` topological path length remains 63.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count | Delta |
|---|---:|---:|
| Cells | 102869 | +161 |
| Estimated LCs | 35808 | -93 |
| CARRY4 | 2581 | -1 |
| DSP48E1 | 13 | +0 |
| FDCE | 4502 | +0 |
| FDPE | 35 | +0 |
| FDRE | 37423 | +0 |
| FDSE | 129 | +0 |
| LUT1 | 409 | +77 |
| LUT2 | 8264 | +589 |
| LUT3 | 7042 | +264 |
| LUT4 | 4569 | +34 |
| LUT5 | 4039 | +103 |
| LUT6 | 20158 | -494 |
| MUXF7 | 3781 | -523 |
| MUXF8 | 678 | +7 |
| RAMB36E1 | 19 | +0 |
| RAM32M | 10 | +0 |
| RAM64M | 1536 | +0 |

Delta from the previous documented AV2 synthesis checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 357.0 s | 415.8 s | +58.8 s |
| Peak synthesis RSS | 1660.32 MiB | 1695.05 MiB | +34.73 MiB |
| Cell-report time | 7.2 s | 7.1 s | -0.1 s |
| Critical-path report time | 93.5 s | 100.6 s | +7.1 s |
| Topological path length | 63 | 63 | +0 |
| Cells | 102708 | 102869 | +161 |
| Estimated LCs | 35901 | 35808 | -93 |

The BVP-stack change slightly reduces the estimated LC count while preserving
the topological path length. Runtime and peak RSS rose modestly; because the
design still completes under the hard synthesis limits, this remains an
acceptable functional checkpoint. Future IBC work should continue watching
the entropy-op and range-coder path because it remains the top path in the
Yosys report.

Vivado synthesis configuration:

- remote checkout Git SHA: `93ad7fad972aab259830c0daffe5dac62701c4c7`
  (`Document AV2 local IBC checkpoint`); this is a docs-only child of the
  current validated RTL SHA above.
- command context: `make synth-vivado CODEC=av2 SYNTH_DUT=av2-encoder`
  with a longer wrapper timeout and no wrapper memory cap.
- Vivado version: 2025.2.
- RTL top: `ff_av2_encoder`.
- device: `xc7z010clg400-1`.
- clock constraint: 25 MHz (`40.000 ns` period).
- max visible size: 1024x1024.
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled,
  lossy 4:2:0 residual enabled.

Vivado synthesis result:

| Metric | Result |
|---|---:|
| `synth_design` elapsed time | 15:47 |
| Full Vivado batch elapsed time | about 21:06 |
| Vivado log peak memory | 3065.31 MB |
| Vivado PSS peak, overall | 6454.57 MB |
| Vivado PSS peak, forked | 6078.84 MB |
| WNS at 25 MHz | -1.944 ns |
| TNS at 25 MHz | -102.321 ns |
| Setup failing endpoints | 100 |
| Worst hold slack | +0.043 ns |
| Slice LUTs | 44143 / 17600 (250.81%) |
| LUT as logic | 31815 / 17600 (180.77%) |
| LUT as distributed RAM | 12328 / 6000 (205.47%) |
| Slice registers | 41562 / 35200 (118.07%) |
| Block RAM tiles | 19 / 60 (31.67%) |
| DSPs | 10 / 80 (12.50%) |
| Bonded IOBs | 482 / 100 (482.00%) |

Largest Vivado-reported local instances:

| Instance | Cells |
|---|---:|
| `palette_analyzer` | 52631 |
| `control_regs` | 6633 |
| `frame_reader` | 6018 |
| `local_hash_ibc` | 5154 |
| `bitstream_writer` | 2276 |
| `chroma_bdpcm_symbolizer` | 1972 |

The worst Vivado timing path starts at
`control_regs/chroma_format_idc_reg[0]` and ends at `low_q_reg[63]`. It crosses
the lossy 4:2:0 luma estimator/residual-symbolizer path and the range-coder
step, with a 41.792 ns data path delay, 53 logic levels, and route delay
accounting for about 60% of the path. This confirms the next AV2 optimization
cycle should focus on registering the 4:2:0 residual/entropy handoff and
reducing the palette/analyzer distributed-RAM footprint before treating Z7-10
as a realistic fit target.
