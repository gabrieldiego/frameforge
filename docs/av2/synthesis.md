# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Closed Header Counter Narrowing

Measured after narrowing the AV2 closed-header bit index and tile-loop index
from 32-bit `integer` signals to explicit 7-bit and 3-bit logic. This is a
synthesis cleanup only; encoded AV2 bitstreams and output scheduling are
unchanged.

Baseline and current sources:

- Baseline Git SHA: `db00d97a03e6e39ae40be1355f4ff56aba79acb3`
- Current validated source Git SHA: `fb0c9e5c49edde163f75faa36e922524355cd025`
- Baseline mode: parallel luma palette non-priority token count tree.
- Current mode: narrowed closed-header bit counters.
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

- Yosys synthesis passed in 240.5 seconds.
- Peak child RSS observed by the synthesis runner was 1321.33 MiB.
- Runtime stayed 59.5 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.2 seconds.
- Post-synthesis critical-path reporting completed in 41.8 seconds with peak
  memory 1321.33 MiB and topological path length 69.
- The longest top-level path now starts at `frame_palette_mode_q`, runs through
  `ff_av2_bitstream_headers` closed-header bit assembly and output-byte
  selection, then reaches `output_byte_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 81663 |
| Estimated LCs | 26287 |
| CARRY4 | 2431 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 430 |
| LUT2 | 6838 |
| LUT3 | 4371 |
| LUT4 | 2581 |
| LUT5 | 2526 |
| LUT6 | 16809 |
| MUXF7 | 2856 |
| MUXF8 | 693 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 266.7 s | 240.5 s | -26.2 s |
| Peak synthesis RSS | 1388.66 MiB | 1321.33 MiB | -67.33 MiB |
| Cell report time | 5.4 s | 5.2 s | -0.2 s |
| Critical-path report time | 42.7 s | 41.8 s | -0.9 s |
| Topological path length | 69 | 69 | 0 |
| Cells | 83101 | 81663 | -1438 |
| Estimated LCs | 26674 | 26287 | -387 |
| CARRY4 | 2566 | 2431 | -135 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 469 | 430 | -39 |
| LUT2 | 6908 | 6838 | -70 |
| LUT3 | 4589 | 4371 | -218 |
| LUT4 | 2552 | 2581 | +29 |
| LUT5 | 2588 | 2526 | -62 |
| LUT6 | 16945 | 16809 | -136 |
| MUXF7 | 3190 | 2856 | -334 |
| MUXF8 | 800 | 693 | -107 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The closed-header counter narrowing preserved the reported topological path
length while reducing cells by 1438, estimated LCs by 387, CARRY4 cells by 135,
peak RSS by 67.33 MiB, and synthesis runtime by 26.2 seconds. BRAM, DSP, and
register counts are unchanged. The next likely timing target remains
`ff_av2_bitstream_headers` closed-header bit assembly/output-byte selection.
