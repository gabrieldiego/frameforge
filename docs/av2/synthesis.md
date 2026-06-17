# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Direct Closed Header Assembly

Measured after replacing the AV2 closed-header repeated dynamic bit writes with
direct fixed-field assignments plus a single contiguous tile-info mask. This is
a synthesis cleanup only; encoded AV2 bitstreams and output scheduling are
unchanged.

Baseline and current sources:

- Baseline Git SHA: `fb0c9e5c49edde163f75faa36e922524355cd025`
- Current validated source Git SHA: `0059f7a8f61fa78529b075e699d7b118de7882f4`
- Baseline mode: narrowed closed-header bit counters.
- Current mode: direct closed-header field assembly.
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

- Yosys synthesis passed in 235.2 seconds.
- Peak child RSS observed by the synthesis runner was 1304.47 MiB.
- Runtime stayed 64.8 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.1 seconds.
- Post-synthesis critical-path reporting completed in 41.2 seconds with peak
  memory 1304.47 MiB and topological path length 66.
- The longest top-level path now starts at
  `palette_analyzer.luma_fetch_txb_samples`, runs through the luma palette
  residual symbolizer's transform/residual context accumulation, and reaches
  `entropy_context_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 78870 |
| Estimated LCs | 25127 |
| CARRY4 | 2269 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 442 |
| LUT2 | 6532 |
| LUT3 | 4424 |
| LUT4 | 2208 |
| LUT5 | 2637 |
| LUT6 | 15858 |
| MUXF7 | 1931 |
| MUXF8 | 435 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 240.5 s | 235.2 s | -5.3 s |
| Peak synthesis RSS | 1321.33 MiB | 1304.47 MiB | -16.86 MiB |
| Cell report time | 5.2 s | 5.1 s | -0.1 s |
| Critical-path report time | 41.8 s | 41.2 s | -0.6 s |
| Topological path length | 69 | 66 | -3 |
| Cells | 81663 | 78870 | -2793 |
| Estimated LCs | 26287 | 25127 | -1160 |
| CARRY4 | 2431 | 2269 | -162 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 430 | 442 | +12 |
| LUT2 | 6838 | 6532 | -306 |
| LUT3 | 4371 | 4424 | +53 |
| LUT4 | 2581 | 2208 | -373 |
| LUT5 | 2526 | 2637 | +111 |
| LUT6 | 16809 | 15858 | -951 |
| MUXF7 | 2856 | 1931 | -925 |
| MUXF8 | 693 | 435 | -258 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The direct closed-header assembly reduced the reported topological path length
by 3 and moved the longest top-level path out of `ff_av2_bitstream_headers`.
It also reduced cells by 2793, estimated LCs by 1160, CARRY4 cells by 162, peak
RSS by 16.86 MiB, and synthesis runtime by 5.3 seconds. BRAM, DSP, and register
counts are unchanged. The next likely timing target is luma palette residual
symbolization, especially transform/residual context accumulation into
`entropy_context_q`.
