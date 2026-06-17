# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Palette Query Map Unpack

Measured after unpacking the selected AV2 luma palette map into 64 registered
3-bit query entries during the existing palette query cycle. This removes the
packed-vector multiply-by-3 part-select from per-token query reads. This is a
synthesis cleanup only; encoded AV2 bitstreams and output scheduling are
unchanged.

Baseline and current sources:

- Baseline Git SHA: `f8a3c0bf8931504e690088fe96d454c780316e44`
- Current validated source Git SHA: `561f9f3f6cf0587907ddaab98c716ab084c3c256`
- Baseline mode: palette CDF token mux cleanup.
- Current mode: palette query map unpack.
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

- Yosys synthesis passed in 254.6 seconds.
- Peak child RSS observed by the synthesis runner was 1298.64 MiB.
- Runtime stayed 45.4 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.0 seconds.
- Post-synthesis critical-path reporting completed in 59.4 seconds with peak
  memory 1298.64 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF token-mux path, the entropy op mux, and
  the range coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 78868 |
| Estimated LCs | 24768 |
| CARRY4 | 2196 |
| DSP48E1 | 11 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 338 |
| LUT2 | 6382 |
| LUT3 | 4256 |
| LUT4 | 3057 |
| LUT5 | 2219 |
| LUT6 | 15236 |
| MUXF7 | 2674 |
| MUXF8 | 431 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 234.5 s | 254.6 s | +20.1 s |
| Peak synthesis RSS | 1291.31 MiB | 1298.64 MiB | +7.33 MiB |
| Cell report time | 5.0 s | 5.0 s | 0.0 s |
| Critical-path report time | 40.9 s | 59.4 s | +18.5 s |
| Topological path length | 55 | 55 | 0 |
| Cells | 78583 | 78868 | +285 |
| Estimated LCs | 25058 | 24768 | -290 |
| CARRY4 | 2213 | 2196 | -17 |
| DSP48E1 | 11 | 11 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 351 | 338 | -13 |
| LUT2 | 6225 | 6382 | +157 |
| LUT3 | 4445 | 4256 | -189 |
| LUT4 | 2466 | 3057 | +591 |
| LUT5 | 2328 | 2219 | -109 |
| LUT6 | 15819 | 15236 | -583 |
| MUXF7 | 2141 | 2674 | +533 |
| MUXF8 | 480 | 431 | -49 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The palette query map unpack keeps the longest reported topological path at 55
nodes but reduces estimated LCs by 290 and `CARRY4` cells by 17. The tradeoff is
285 more flattened cells, a 20.1 second longer Yosys synthesis pass, and an 18.5
second longer critical-path report. The run still stays under the 300 second
review threshold and well below the memory cap. The next likely timing target
remains the palette-token-to-range-coder path, especially the analyzer's
top-left index lookup and range normalization.
