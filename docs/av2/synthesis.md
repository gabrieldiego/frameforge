# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Luma Palette Token Ordering

Measured after replacing the AV2 luma palette symbolizer's temporary
eight-entry color-order/status arrays with direct neighbor-priority token
generation. This is a synthesis cleanup only; encoded AV2 bitstreams and
output scheduling are unchanged.

Baseline and current sources:

- Baseline Git SHA: `6c7ec6f9938788f89f9755c6eccdbb2142fec39c`
- Current validated source Git SHA: `50244062149c2de2216098735676af4fd653c177`
- Baseline mode: signed 8-bit range-coder count and finalization arithmetic.
- Current mode: direct luma palette neighbor-priority token ordering.
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

- Yosys synthesis passed in 266.9 seconds.
- Peak child RSS observed by the synthesis runner was 1358.22 MiB.
- Runtime stayed 33.1 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.3 seconds.
- Post-synthesis critical-path reporting completed in 42.2 seconds with peak
  memory 1358.22 MiB and topological path length 73.
- The longest top-level path still starts at `palette_row_q`, runs through
  palette analyzer neighbor lookup, luma palette token generation, entropy op
  muxing, and range-coder normalization toward `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 82595 |
| Estimated LCs | 26561 |
| CARRY4 | 2571 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 422 |
| LUT2 | 6841 |
| LUT3 | 4555 |
| LUT4 | 2380 |
| LUT5 | 2617 |
| LUT6 | 17009 |
| MUXF7 | 2907 |
| MUXF8 | 738 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 286.1 s | 266.9 s | -19.2 s |
| Peak synthesis RSS | 1339.81 MiB | 1358.22 MiB | +18.41 MiB |
| Cell report time | 5.7 s | 5.3 s | -0.4 s |
| Critical-path report time | 45.3 s | 42.2 s | -3.1 s |
| Topological path length | 78 | 73 | -5 |
| Cells | 82696 | 82595 | -101 |
| Estimated LCs | 27007 | 26561 | -446 |
| CARRY4 | 2572 | 2571 | -1 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 430 | 422 | -8 |
| LUT2 | 6642 | 6841 | +199 |
| LUT3 | 4562 | 4555 | -7 |
| LUT4 | 2481 | 2380 | -101 |
| LUT5 | 3211 | 2617 | -594 |
| LUT6 | 16753 | 17009 | +256 |
| MUXF7 | 2846 | 2907 | +61 |
| MUXF8 | 650 | 738 | +88 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The direct luma palette token-ordering cleanup reduced the reported topological
path length by 5, cells by 101, and estimated LCs by 446. Synthesis runtime
fell by 19.2 seconds and remained below the 300 second review threshold. Peak
RSS increased by 18.41 MiB but stayed well inside the 3072 MiB limit. BRAM and
DSP counts are unchanged. The next likely timing target remains the luma
palette token path and its handoff into entropy op muxing/range-coder
normalization.
