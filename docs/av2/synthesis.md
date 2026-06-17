# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Palette Token Ranking Cleanup

Measured after replacing the AV2 luma palette token rank calculation's full
8-entry priority-hit mask with a direct count of priority colors below the
current palette index. This is a synthesis cleanup only; encoded AV2 bitstreams
and output scheduling are unchanged.

Baseline and current sources:

- Baseline Git SHA: `88dbd0f5809a69d9b5fd2e4411bf27ca09ec9898`
- Current validated source Git SHA: `1c68cec7173dc4aa40e50370834d85587470665c`
- Baseline mode: residual entropy context cleanup.
- Current mode: palette token ranking cleanup.
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

- Yosys synthesis passed in 237.8 seconds.
- Peak child RSS observed by the synthesis runner was 1315.14 MiB.
- Runtime stayed 62.2 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.0 seconds.
- Post-synthesis critical-path reporting completed in 41.7 seconds with peak
  memory 1315.14 MiB and topological path length 57.
- The longest top-level path now starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF path, the entropy op mux, and the range
  coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 78445 |
| Estimated LCs | 25061 |
| CARRY4 | 2243 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 252 |
| LUT2 | 6447 |
| LUT3 | 4545 |
| LUT4 | 2358 |
| LUT5 | 2294 |
| LUT6 | 15864 |
| MUXF7 | 1850 |
| MUXF8 | 454 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 234.7 s | 237.8 s | +3.1 s |
| Peak synthesis RSS | 1286.67 MiB | 1315.14 MiB | +28.47 MiB |
| Cell report time | 5.0 s | 5.0 s | 0.0 s |
| Critical-path report time | 41.9 s | 41.7 s | -0.2 s |
| Topological path length | 61 | 57 | -4 |
| Cells | 77824 | 78445 | +621 |
| Estimated LCs | 24551 | 25061 | +510 |
| CARRY4 | 2243 | 2243 | 0 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 268 | 252 | -16 |
| LUT2 | 6547 | 6447 | -100 |
| LUT3 | 4189 | 4545 | +356 |
| LUT4 | 2231 | 2358 | +127 |
| LUT5 | 2354 | 2294 | -60 |
| LUT6 | 15713 | 15864 | +151 |
| MUXF7 | 1767 | 1850 | +83 |
| MUXF8 | 367 | 454 | +87 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The palette token ranking cleanup reduced the reported topological path length
by 4 by replacing the full priority-hit mask/popcount path with a direct
priority-before count. The tradeoff is a 621-cell and 510-estimated-LC increase
against the immediate `88dbd0f` baseline, plus 28.47 MiB peak RSS and 3.1 seconds
of synthesis runtime. BRAM, DSP, CARRY4, and register counts are unchanged. The
current result is still smaller than the earlier direct-header checkpoint
(`0059f7a`, 25127 estimated LCs) while improving the topological path from 66 to
57. The next likely timing target remains the palette-token-to-range-coder path,
especially CDF selection and range normalization.
