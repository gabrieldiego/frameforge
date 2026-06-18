# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Residual Sign Scan Skip

Measured after making the residual symbolizer jump directly between nonzero
coefficients during sign and high-range emission. This reduces output bubbles
without changing the AV2 bitstream, reference reconstruction, BRAM count, DSP
count, or longest reported topological path. The logic reuses the existing
lower-nonzero scan loop and only adds a small next-scan selector.

Baseline and current sources:

- Baseline Git SHA: `da5f62cf9bcb355a482a443501faa0b3e5c3a8fd`
- Current validated source Git SHA: `33be2008240bf3acecef4a9344ca9e9b01313dc5`
- Baseline mode: EOB-bounded residual scans, known-zero luma residual fast path,
  and pipeline profiler counters.
- Current mode: residual sign scan jumps directly to the next lower nonzero
  coefficient.
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

- Yosys synthesis passed in 303.3 seconds.
- Peak child RSS observed by the synthesis runner was 1428.72 MiB.
- Runtime exceeded the 300 second review threshold by 3.3 seconds, while
  remaining inside the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 6.1 seconds.
- Post-synthesis critical-path reporting completed in 75.3 seconds with peak
  memory 1428.72 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF token-mux path, the entropy op mux, and
  the range coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 84393 |
| Estimated LCs | 28059 |
| CARRY4 | 2239 |
| DSP48E1 | 11 |
| FDCE | 5489 |
| FDPE | 24 |
| FDRE | 29652 |
| FDSE | 14 |
| LUT1 | 349 |
| LUT2 | 6360 |
| LUT3 | 4789 |
| LUT4 | 2423 |
| LUT5 | 3621 |
| LUT6 | 17226 |
| MUXF7 | 2355 |
| MUXF8 | 559 |
| RAMB36E1 | 19 |
| RAM32M | 10 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 310.3 s | 303.3 s | -7.0 s |
| Peak synthesis RSS | 1398.5 MiB | 1428.7 MiB | +30.2 MiB |
| Cell report time | 6.0 s | 6.1 s | +0.1 s |
| Critical-path report time | 77.9 s | 75.3 s | -2.6 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 83911 | 84393 | +482 |
| Estimated LCs | 28054 | 28059 | +5 |
| CARRY4 | 2243 | 2239 | -4 |
| DSP48E1 | 11 | 11 | +0 |
| FDCE | 5489 | 5489 | +0 |
| FDPE | 24 | 24 | +0 |
| FDRE | 29652 | 29652 | +0 |
| FDSE | 14 | 14 | +0 |
| LUT1 | 446 | 349 | -97 |
| LUT2 | 6180 | 6360 | +180 |
| LUT3 | 4806 | 4789 | -17 |
| LUT4 | 2499 | 2423 | -76 |
| LUT5 | 3200 | 3621 | +421 |
| LUT6 | 17549 | 17226 | -323 |
| MUXF7 | 2034 | 2355 | +321 |
| MUXF8 | 449 | 559 | +110 |
| RAMB36E1 | 19 | 19 | +0 |
| RAM32M | 10 | 10 | +0 |
| RAM64M | 1536 | 1536 | +0 |

The residual sign-scan optimization keeps the longest reported topological path
at 55 nodes and leaves BRAM/DSP counts unchanged. It increases the estimate by
482 flattened cells but only 5 estimated LCs, while aggregate cycles fall by
6559 on the full screenshot sweep and 5933 on the multi-CTU/partial set
relative to the previous documented checkpoint. The remaining large bubble
sources are now architectural: serialized tile input, finished prefetches
waiting for leaf entropy, one-byte-per-cycle carry/output, and the staged
post-entropy payload buffer.
