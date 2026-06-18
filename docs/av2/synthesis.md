# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Payload And Fetch Pipelining

Measured after removing the AV2 post-carry payload-copy sweep, pipelining the
backward carry resolver after its initial read, collecting luma palette colors
while input samples arrive, and pipelining luma/chroma TXB sample fetches from
the analyzer sample store. Encoded AV2 bitstreams are unchanged; this checkpoint
only reduces measured RTL cycles before the final output byte is accepted.

Baseline and current sources:

- Baseline Git SHA: `561f9f3f6cf0587907ddaab98c716ab084c3c256`
- Current validated source Git SHA: `d71698bf9f3d390bdb1eacbb260948499a6ea495`
- Baseline mode: palette query map unpack.
- Current mode: payload/carry and analyzer-fetch pipelining.
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

- Yosys synthesis passed in 268.1 seconds.
- Peak child RSS observed by the synthesis runner was 1332.36 MiB.
- Runtime stayed 31.9 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.5 seconds.
- Post-synthesis critical-path reporting completed in 62.3 seconds with peak
  memory 1332.36 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF token-mux path, the entropy op mux, and
  the range coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 78445 |
| Estimated LCs | 24963 |
| CARRY4 | 2204 |
| DSP48E1 | 11 |
| FDCE | 4911 |
| FDPE | 24 |
| FDRE | 28387 |
| FDSE | 14 |
| LUT1 | 390 |
| LUT2 | 6190 |
| LUT3 | 4167 |
| LUT4 | 2368 |
| LUT5 | 2743 |
| LUT6 | 15685 |
| MUXF7 | 2182 |
| MUXF8 | 497 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 254.6 s | 268.1 s | +13.5 s |
| Peak synthesis RSS | 1298.64 MiB | 1332.36 MiB | +33.72 MiB |
| Cell report time | 5.0 s | 5.5 s | +0.5 s |
| Critical-path report time | 59.4 s | 62.3 s | +2.9 s |
| Topological path length | 55 | 55 | 0 |
| Cells | 78868 | 78445 | -423 |
| Estimated LCs | 24768 | 24963 | +195 |
| CARRY4 | 2196 | 2204 | +8 |
| DSP48E1 | 11 | 11 | 0 |
| FDCE | 4923 | 4911 | -12 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28387 | -16 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 338 | 390 | +52 |
| LUT2 | 6382 | 6190 | -192 |
| LUT3 | 4256 | 4167 | -89 |
| LUT4 | 3057 | 2368 | -689 |
| LUT5 | 2219 | 2743 | +524 |
| LUT6 | 15236 | 15685 | +449 |
| MUXF7 | 2674 | 2182 | -492 |
| MUXF8 | 431 | 497 | +66 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The payload and fetch pipelining keeps the longest reported topological path at
55 nodes, removes 423 flattened cells, and leaves all RAM counts unchanged. The
tradeoff is a 195 LC increase, 13.5 seconds more synthesis time, and 33.72 MiB
more peak RSS. The area increase is marginal relative to the output-cycle
reduction documented in [output-utilization.md](output-utilization.md): the
64x64 screenshot smoke drops from 142611 to 96783 cycles, while the full
screenshot sweep drops by 628283 aggregate cycles with unchanged bitstreams.
The next likely timing target remains the palette-token-to-range-coder path,
especially the analyzer's top-left index lookup and range normalization.
