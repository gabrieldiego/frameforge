# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-20 Chroma Residual Enable Split

Measured after splitting the AV2 chroma residual enables so the lossy 4:2:0
DC-only path no longer carries the 4:4:4 palette cache-hit shortcut. The
previous Vivado timing input showed pressure through the lossy 4:2:0 residual
path into the range coder; this change keeps the palette predictor/cache
shortcut isolated to the palette path while sharing the common chroma residual
phase and fetch-ready terms.

Baseline and current sources:

- Baseline RTL Git SHA: `64961ede3115ee0941c2da7a519999f0285be8d2`
- Current validated RTL source: this commit.
- Baseline mode: dedicated lossy 4:2:0 DC-delta TXB symbolizer with shared
  chroma residual enable logic.
- Current mode: same encoder behavior, with palette and lossy 4:2:0 chroma
  residual enables split so only the palette side sees the cache-hit shortcut.
- Delta columns compare against the previous documented AV2 synthesis
  checkpoint.

Validation result:

- `cargo test av2 --lib`: OK (25/25).
- `racehorses_crop_48x24_1f_yuv420p8`: OK, strict SW/RTL bitstream parity and
  SW/RTL/reference-decoder reconstruction parity.
- `screenshot_640_sweep_48x24_1f_yuv444p8`: OK, strict SW/RTL bitstream parity
  and SW/RTL/reference-decoder lossless reconstruction parity.
- Yosys synthesis: PASS.
- Vivado was not rerun after this patch. The optimization target remains the
  previous Vivado worst path documented below.

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

- Yosys synthesis passed in 344.8 seconds.
- Peak child RSS observed by the synthesis runner was 1677.21 MiB.
- Runtime exceeded the 300 second review threshold but completed inside the
  600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 6.9 seconds.
- Post-synthesis critical-path reporting completed in 89.8 seconds.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.
- The top `ff_av2_encoder` topological path length improved from 60 to 55.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count | Delta |
|---|---:|---:|
| Cells | 102260 | -131 |
| Estimated LCs | 35289 | +246 |
| CARRY4 | 2540 | +0 |
| DSP48E1 | 13 | +0 |
| FDCE | 4462 | +0 |
| FDPE | 27 | +0 |
| FDRE | 37423 | +0 |
| FDSE | 129 | +0 |
| LUT1 | 661 | +80 |
| LUT2 | 7872 | +197 |
| LUT3 | 6894 | +402 |
| LUT4 | 4123 | -234 |
| LUT5 | 3998 | +37 |
| LUT6 | 20274 | +41 |
| MUXF7 | 4084 | -490 |
| MUXF8 | 696 | -8 |
| RAMB36E1 | 19 | +0 |
| RAM32M | 10 | +0 |
| RAM64M | 1536 | +0 |

Delta from the previous documented AV2 synthesis checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 349.0 s | 344.8 s | -4.2 s |
| Peak synthesis RSS | 1666.98 MiB | 1677.21 MiB | +10.23 MiB |
| Cell-report time | 7.1 s | 6.9 s | -0.2 s |
| Critical-path report time | 91.5 s | 89.8 s | -1.7 s |
| Topological path length | 60 | 55 | -5 |
| Cells | 102391 | 102260 | -131 |
| Estimated LCs | 35043 | 35289 | +246 |

The chroma enable split removes the palette predictor/cache fan-in from the
lossy 4:2:0 residual path. The top Yosys path now moves to the 4:4:4 palette
analyzer/luma-palette-symbolizer path before the range coder. This is a useful
timing tradeoff: it reduces the topological path length and total cell count,
with a small estimated-LC increase and no observed change in smoke-test cycle
counts or encoded bitstreams.

Previous Vivado timing input:

- remote checkout Git SHA: `93ad7fad972aab259830c0daffe5dac62701c4c7`
  (`Document AV2 local IBC checkpoint`), a docs-only child of the baseline
  RTL SHA above.
- command context: `make synth-vivado CODEC=av2 SYNTH_DUT=av2-encoder`
  with a longer wrapper timeout and no wrapper memory cap.
- Vivado version: 2025.2.
- RTL top: `ff_av2_encoder`.
- device: `xc7z010clg400-1`.
- clock constraint: 25 MHz (`40.000 ns` period).
- max visible size: 1024x1024.
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled,
  lossy 4:2:0 residual enabled.

Previous Vivado synthesis result:

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

The previous Vivado worst path started at
`control_regs/chroma_format_idc_reg[0]` and ended at `low_q_reg[63]`. It
crossed the lossy 4:2:0 luma estimator/residual-symbolizer path and the
range-coder step, with a 41.792 ns data path delay, 53 logic levels, and route
delay accounting for about 60% of the path. The DC-delta split removes the
full BDPCM symbolizer from that lossy 4:2:0 path; the next Vivado run should
verify whether the WNS moves to the shorter skip-CDF/range-coder path now
reported by Yosys.
