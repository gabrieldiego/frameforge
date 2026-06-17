# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Range-Coder Count Narrowing

Measured after narrowing AV2 entropy range-coder count and finalization
arithmetic from 32-bit `integer` signals to explicit signed 8-bit logic. This
is a synthesis cleanup only; encoded AV2 bitstreams and output scheduling are
unchanged.

Baseline and current sources:

- Baseline Git SHA: `22acd0ebb02db4dbd406cb174f6898b79e597c29`
- Current validated source Git SHA: `6c7ec6f9938788f89f9755c6eccdbb2142fec39c`
- Baseline mode: continuous final-byte output drain in `ff_av2_encoder`.
- Current mode: signed 8-bit range-coder count and finalization arithmetic.
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

- Yosys synthesis passed in 286.1 seconds.
- Peak child RSS observed by the synthesis runner was 1339.81 MiB.
- Runtime stayed 13.9 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.7 seconds.
- Post-synthesis critical-path reporting completed in 45.3 seconds with peak
  memory 1339.81 MiB and topological path length 78.
- The longest top-level path still starts at `palette_row_q`, runs through
  palette-map neighbor/token ordering, and then enters the entropy range-coder
  path toward `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 82696 |
| Estimated LCs | 27007 |
| CARRY4 | 2572 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 430 |
| LUT2 | 6642 |
| LUT3 | 4562 |
| LUT4 | 2481 |
| LUT5 | 3211 |
| LUT6 | 16753 |
| MUXF7 | 2846 |
| MUXF8 | 650 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 307.5 s | 286.1 s | -21.4 s |
| Peak synthesis RSS | 1392.27 MiB | 1339.81 MiB | -52.46 MiB |
| Cell report time | 5.9 s | 5.7 s | -0.2 s |
| Critical-path report time | 48.2 s | 45.3 s | -2.9 s |
| Topological path length | 78 | 78 | 0 |
| Cells | 84187 | 82696 | -1491 |
| Estimated LCs | 27064 | 27007 | -57 |
| CARRY4 | 2646 | 2572 | -74 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28451 | 28403 | -48 |
| FDSE | 38 | 14 | -24 |
| LUT1 | 524 | 430 | -94 |
| LUT2 | 6709 | 6642 | -67 |
| LUT3 | 4313 | 4562 | +249 |
| LUT4 | 2695 | 2481 | -214 |
| LUT5 | 2955 | 3211 | +256 |
| LUT6 | 17101 | 16753 | -348 |
| MUXF7 | 3570 | 2846 | -724 |
| MUXF8 | 894 | 650 | -244 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The range-coder count narrowing preserved the reported topological path length
while reducing cells by 1491, estimated LCs by 57, CARRY4 cells by 74, and peak
synthesis RSS by 52.46 MiB. Synthesis runtime returned below the 300 second
review threshold. BRAM and DSP counts are unchanged. The next likely timing
target remains palette-map token ordering into the entropy range-coder path.
