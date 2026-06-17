# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Parallel Luma Palette Token Count

Measured after replacing the AV2 luma palette symbolizer's serial unrolled
non-priority-color count with explicit per-index masks and pairwise sums. This
is a synthesis/timing cleanup only; encoded AV2 bitstreams and output
scheduling are unchanged.

Baseline and current sources:

- Baseline Git SHA: `50244062149c2de2216098735676af4fd653c177`
- Current validated source Git SHA: `db00d97a03e6e39ae40be1355f4ff56aba79acb3`
- Baseline mode: direct luma palette neighbor-priority token ordering.
- Current mode: parallel luma palette non-priority token count tree.
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

- Yosys synthesis passed in 266.7 seconds.
- Peak child RSS observed by the synthesis runner was 1388.66 MiB.
- Runtime stayed 33.3 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.4 seconds.
- Post-synthesis critical-path reporting completed in 42.7 seconds with peak
  memory 1388.66 MiB and topological path length 69.
- The longest top-level path now starts at `frame_palette_mode_q`, runs through
  `ff_av2_bitstream_headers` closed-header bit assembly and output-byte
  selection, then reaches `output_byte_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 83101 |
| Estimated LCs | 26674 |
| CARRY4 | 2566 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 469 |
| LUT2 | 6908 |
| LUT3 | 4589 |
| LUT4 | 2552 |
| LUT5 | 2588 |
| LUT6 | 16945 |
| MUXF7 | 3190 |
| MUXF8 | 800 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 266.9 s | 266.7 s | -0.2 s |
| Peak synthesis RSS | 1358.22 MiB | 1388.66 MiB | +30.44 MiB |
| Cell report time | 5.3 s | 5.4 s | +0.1 s |
| Critical-path report time | 42.2 s | 42.7 s | +0.5 s |
| Topological path length | 73 | 69 | -4 |
| Cells | 82595 | 83101 | +506 |
| Estimated LCs | 26561 | 26674 | +113 |
| CARRY4 | 2571 | 2566 | -5 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 422 | 469 | +47 |
| LUT2 | 6841 | 6908 | +67 |
| LUT3 | 4555 | 4589 | +34 |
| LUT4 | 2380 | 2552 | +172 |
| LUT5 | 2617 | 2588 | -29 |
| LUT6 | 17009 | 16945 | -64 |
| MUXF7 | 2907 | 3190 | +283 |
| MUXF8 | 738 | 800 | +62 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The parallel luma palette token-count cleanup reduced the reported topological
path length by 4 and moved the longest top-level path out of the luma
palette/range-coder logic. The tradeoff is a marginal increase of 506 cells and
113 estimated LCs, with BRAM, DSP, and register counts unchanged. Synthesis
runtime stayed effectively flat and remained below the 300 second review
threshold. The next likely timing target is `ff_av2_bitstream_headers`
closed-header bit assembly/output-byte selection.
