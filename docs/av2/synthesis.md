# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Residual Scan Gap Profiling

Measured after bounding residual coefficient scans to the coded EOB range,
adding a known-zero luma TXB fast path, and expanding the AV2 cocotb profiler
with leaf-phase and pipeline counters. This reduces output bubbles without
changing the AV2 bitstream, reference reconstruction, BRAM count, or DSP count.
The cost is a small increase in local registers and LUTs around the palette
analyzer and residual symbolizer control.

Baseline and current sources:

- Baseline Git SHA: `c125ea91a2e0643313a77870172c49d0331d5339`
- Current validated source Git SHA: `da5f62cf9bcb355a482a443501faa0b3e5c3a8fd`
- Baseline mode: chroma TXB fetch cache and predictor cache-hit bypass.
- Current mode: EOB-bounded residual scans, known-zero luma residual fast path,
  and pipeline profiler counters.
- Delta columns compare against the previous documented AV2 top-synthesis
  baseline for the same DUT and board.

Validation configuration:

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)

Synthesis configuration:

- command: `make synth CODEC=av2`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled

Synthesis result:

- Yosys synthesis passed in 310.3 seconds.
- Peak child RSS observed by the synthesis runner was 1398.53 MiB.
- Runtime exceeded the 300 second review threshold by 10.3 seconds, while
  remaining inside the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 6.0 seconds.
- Post-synthesis critical-path reporting completed in 77.9 seconds with peak
  memory 1398.53 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF token-mux path, the entropy op mux, and
  the range coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 83911 |
| Estimated LCs | 28054 |
| CARRY4 | 2243 |
| DSP48E1 | 11 |
| FDCE | 5489 |
| FDPE | 24 |
| FDRE | 29652 |
| FDSE | 14 |
| LUT1 | 446 |
| LUT2 | 6180 |
| LUT3 | 4806 |
| LUT4 | 2499 |
| LUT5 | 3200 |
| LUT6 | 17549 |
| MUXF7 | 2034 |
| MUXF8 | 449 |
| RAMB36E1 | 19 |
| RAM32M | 10 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 296.7 s | 310.3 s | +13.6 s |
| Peak synthesis RSS | 1379.5 MiB | 1398.5 MiB | +19.0 MiB |
| Cell report time | 5.6 s | 6.0 s | +0.4 s |
| Critical-path report time | 68.6 s | 77.9 s | +9.3 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 83788 | 83911 | +123 |
| Estimated LCs | 27765 | 28054 | +289 |
| CARRY4 | 2226 | 2243 | +17 |
| DSP48E1 | 11 | 11 | +0 |
| FDCE | 5488 | 5489 | +1 |
| FDPE | 24 | 24 | +0 |
| FDRE | 29588 | 29652 | +64 |
| FDSE | 14 | 14 | +0 |
| LUT1 | 349 | 446 | +97 |
| LUT2 | 6187 | 6180 | -7 |
| LUT3 | 5569 | 4806 | -763 |
| LUT4 | 2267 | 2499 | +232 |
| LUT5 | 2929 | 3200 | +271 |
| LUT6 | 17000 | 17549 | +549 |
| MUXF7 | 2241 | 2034 | -207 |
| MUXF8 | 447 | 449 | +2 |
| RAMB36E1 | 19 | 19 | +0 |
| RAM32M | 10 | 10 | +0 |
| RAM64M | 1536 | 1536 | +0 |

The residual scan-gap optimization keeps the longest reported topological path
at 55 nodes and leaves BRAM/DSP counts unchanged. It increases the estimate by
123 flattened cells and 289 estimated LCs, while aggregate cycles fall by 6541
on the full screenshot sweep and 5321 on the multi-CTU/partial set relative to
the previous documented checkpoint. The new profiler counters show that the
next large bubble sources are input backpressure between tiles, finished
prefetches waiting for leaf entropy, and remaining chroma coefficient emission
gaps.
