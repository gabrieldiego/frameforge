# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Continuous Final Output Drain

Measured after changing `ff_av2_encoder` to keep `m_axis_valid` asserted while
draining final OBU bytes. The encoder now prefetches the next output byte during
an accepted transfer instead of returning to an idle/load cycle between bytes.
This changes RTL output timing only; encoded AV2 bitstreams are unchanged.

Baseline and current sources:

- Baseline Git SHA: `3f8e91b67dff42fcf3af8addffc29e8ce5aeb996`
- Current validated source Git SHA: `22acd0ebb02db4dbd406cb174f6898b79e597c29`
- Baseline mode: AV2 luma palette header literals are precomputed and
  registered in `ff_av2_palette_analyzer_444` before they are consumed by
  `ff_av2_luma_palette_symbolizer`.
- Current mode: continuous final-byte output drain in `ff_av2_encoder`.
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

- Yosys synthesis passed in 307.5 seconds.
- Peak child RSS observed by the synthesis runner was 1392.27 MiB.
- Runtime exceeded the 300 second review threshold by 7.5 seconds, but stayed
  inside the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.9 seconds.
- Post-synthesis critical-path reporting completed in 48.2 seconds with peak
  memory 1392.27 MiB and topological path length 78.
- The longest top-level path still starts at `palette_row_q`, runs through
  palette-map neighbor/token ordering, and then enters the entropy range-coder
  path toward `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 84187 |
| Estimated LCs | 27064 |
| CARRY4 | 2646 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28451 |
| FDSE | 38 |
| LUT1 | 524 |
| LUT2 | 6709 |
| LUT3 | 4313 |
| LUT4 | 2695 |
| LUT5 | 2955 |
| LUT6 | 17101 |
| MUXF7 | 3570 |
| MUXF8 | 894 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 294.6 s | 307.5 s | +12.9 s |
| Peak synthesis RSS | 1357.64 MiB | 1392.27 MiB | +34.63 MiB |
| Cell report time | 5.7 s | 5.9 s | +0.2 s |
| Critical-path report time | 46.4 s | 48.2 s | +1.8 s |
| Topological path length | 78 | 78 | 0 |
| Cells | 84102 | 84187 | +85 |
| Estimated LCs | 27387 | 27064 | -323 |
| CARRY4 | 2650 | 2646 | -4 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28451 | 28451 | 0 |
| FDSE | 38 | 38 | 0 |
| LUT1 | 443 | 524 | +81 |
| LUT2 | 6225 | 6709 | +484 |
| LUT3 | 4226 | 4313 | +87 |
| LUT4 | 2719 | 2695 | -24 |
| LUT5 | 2849 | 2955 | +106 |
| LUT6 | 17593 | 17101 | -492 |
| MUXF7 | 3605 | 3570 | -35 |
| MUXF8 | 1015 | 894 | -121 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The continuous output-drain change preserved the reported topological path
length and reduced estimated LCs by 323. Cells increased by 85 and synthesis
runtime crossed the review threshold, so the next area/timing work should still
focus on palette-map token ordering and the entropy range-coder path. BRAM,
DSP, and the large FF bank counts are unchanged.
