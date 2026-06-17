# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Bitstream Header RTL Split

Measured after moving AV2 sequence-header field selection, closed-frame header
byte construction, OBU length layout, and top-level non-payload byte muxing out
of `ff_av2_encoder` and into `rtl/av2/bitstream`. This is intended as a
structural cleanup only: the SW/RTL/reference-decoder bitstreams are unchanged,
and the top encoder now owns the state machine and staged memories while the
bitstream helper owns header/layout combinational logic.

Baseline and current sources:

- Baseline Git SHA: `ebc77b3258bc516b282e23a31e9b554312acbff2`
- Current validated source Git SHA: `d480045c0914eaafaa170a14bb02c56843187549`
- Baseline mode: previously documented AV2 entropy operation selection and
  range-coder normalization split into submodules.
- Current mode: AV2 bitstream header/layout construction split into a
  dedicated `ff_av2_bitstream_headers` submodule.
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

- Yosys synthesis passed in 295.4 seconds.
- Peak child RSS observed by the synthesis runner was 1377.04 MiB.
- Runtime stayed 4.6 seconds below the 300 second review threshold and inside
  the 600 second hard timeout.
- Post-synthesis flattened-cell reporting completed in 5.7 seconds.
- Post-synthesis critical-path reporting completed in 46.6 seconds with peak
  memory 1377.04 MiB and topological path length 127.
- The longest top-level path remains in the luma palette/range-coder path,
  from `palette_analyzer.query_palette_colors_q` through
  `ff_av2_luma_palette_symbolizer` delta-bit calculation. The extracted
  bitstream header helper does not appear on the reported longest path.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 84654 |
| Estimated LCs | 27599 |
| CARRY4 | 2673 |
| DSP48E1 | 15 |
| FDCE | 4829 |
| FDPE | 24 |
| FDRE | 28451 |
| FDSE | 38 |
| LUT1 | 484 |
| LUT2 | 6543 |
| LUT3 | 4529 |
| LUT4 | 2819 |
| LUT5 | 3048 |
| LUT6 | 17203 |
| MUXF7 | 3755 |
| MUXF8 | 1045 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 303.5 s | 295.4 s | -8.1 s |
| Peak synthesis RSS | 1377.16 MiB | 1377.04 MiB | -0.12 MiB |
| Cell report time | 5.6 s | 5.7 s | +0.1 s |
| Critical-path report time | 49.1 s | 46.6 s | -2.5 s |
| Topological path length | 127 | 127 | 0 |
| Cells | 84647 | 84654 | +7 |
| Estimated LCs | 27323 | 27599 | +276 |
| CARRY4 | 2634 | 2673 | +39 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4829 | 4829 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28451 | 28451 | 0 |
| FDSE | 38 | 38 | 0 |
| LUT1 | 505 | 484 | -21 |
| LUT2 | 6557 | 6543 | -14 |
| LUT3 | 4577 | 4529 | -48 |
| LUT4 | 2796 | 2819 | +23 |
| LUT5 | 2504 | 3048 | +544 |
| LUT6 | 17446 | 17203 | -243 |
| MUXF7 | 3957 | 3755 | -202 |
| MUXF8 | 1168 | 1045 | -123 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The refactor keeps block RAM, DSP usage, registers, and topological
critical-path depth unchanged. Estimated LCs increased by about 1.0%, while raw
cell count is effectively flat and MUX usage decreased. Main synthesis time
moved back under the 300 second review threshold, so the cleanup is acceptable;
future optimization passes should continue watching the luma
palette/range-coder path.
