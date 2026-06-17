# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Luma Palette Header Timing Split

Measured after registering AV2 luma palette header literals at the palette
analyzer query boundary. The symbolizer now selects precomputed first-color,
delta-bits, delta-minus-one, and per-delta literal-width fields instead of
recomputing palette deltas on the entropy-coder input path.

Baseline and current sources:

- Baseline Git SHA: `d480045c0914eaafaa170a14bb02c56843187549`
- Current validated source Git SHA: `3f8e91b67dff42fcf3af8addffc29e8ce5aeb996`
- Baseline mode: previously documented AV2 bitstream header/layout split.
- Current mode: AV2 luma palette header literals are precomputed and registered
  in `ff_av2_palette_analyzer_444` before they are consumed by
  `ff_av2_luma_palette_symbolizer`.
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

- Yosys synthesis passed in 294.6 seconds.
- Peak child RSS observed by the synthesis runner was 1357.64 MiB.
- Runtime stayed 5.4 seconds below the 300 second review threshold and inside
  the 600 second hard timeout.
- Post-synthesis flattened-cell reporting completed in 5.7 seconds.
- Post-synthesis critical-path reporting completed in 46.4 seconds with peak
  memory 1357.64 MiB and topological path length 78.
- The previous longest path through luma palette delta-bit calculation was
  removed. The new longest top-level path starts at `palette_row_q`, runs
  through palette-map neighbor/token ordering, and then enters the entropy
  range-coder path toward `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 84102 |
| Estimated LCs | 27387 |
| CARRY4 | 2650 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28451 |
| FDSE | 38 |
| LUT1 | 443 |
| LUT2 | 6225 |
| LUT3 | 4226 |
| LUT4 | 2719 |
| LUT5 | 2849 |
| LUT6 | 17593 |
| MUXF7 | 3605 |
| MUXF8 | 1015 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 295.4 s | 294.6 s | -0.8 s |
| Peak synthesis RSS | 1377.04 MiB | 1357.64 MiB | -19.40 MiB |
| Cell report time | 5.7 s | 5.7 s | 0.0 s |
| Critical-path report time | 46.6 s | 46.4 s | -0.2 s |
| Topological path length | 127 | 78 | -49 |
| Cells | 84654 | 84102 | -552 |
| Estimated LCs | 27599 | 27387 | -212 |
| CARRY4 | 2673 | 2650 | -23 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4829 | 4923 | +94 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28451 | 28451 | 0 |
| FDSE | 38 | 38 | 0 |
| LUT1 | 484 | 443 | -41 |
| LUT2 | 6543 | 6225 | -318 |
| LUT3 | 4529 | 4226 | -303 |
| LUT4 | 2819 | 2719 | -100 |
| LUT5 | 3048 | 2849 | -199 |
| LUT6 | 17203 | 17593 | +390 |
| MUXF7 | 3755 | 3605 | -150 |
| MUXF8 | 1045 | 1015 | -30 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

This timing split reduced the reported topological path by 38.6% and also
reduced estimated LCs by 212. BRAM, DSP, and the large FF bank counts are
unchanged. The next likely timing target is palette-map token ordering: the new
longest path still goes through `ff_av2_luma_palette_symbolizer`, but no longer
through the palette-header delta arithmetic.
