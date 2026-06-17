# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Entropy RTL Split

Measured after moving the AV2 entropy operation mux and range-coder step out of
`ff_av2_encoder` and into `rtl/av2/entropy`. This is intended as a structural
cleanup only: the SW/RTL/reference-decoder bitstreams are unchanged, the
testbench now taps the entropy wrapper internals directly for traces, and the
synthesis runner now emits a flattened Xilinx-cell report by default after
successful Yosys synthesis.

Baseline and current sources:

- Baseline Git SHA: `17ff78397917f320a13809216e957826acd9cbc7`
- Current validated source Git SHA: `ebc77b3258bc516b282e23a31e9b554312acbff2`
- Baseline mode: previously documented AV2 luma intra + IntraBC syntax fix
  checkpoint.
- Current mode: AV2 entropy operation selection and range-coder normalization
  split into submodules, with automatic flattened cell reporting in the Yosys
  synthesis flow.
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

- Yosys synthesis passed in 303.5 seconds.
- Peak child RSS observed by the synthesis runner was 1377.16 MiB.
- Runtime exceeded the 300 second review threshold by 3.5 seconds but stayed
  inside the 600 second hard timeout.
- Post-synthesis flattened-cell reporting completed in 5.6 seconds.
- Post-synthesis critical-path reporting completed in 49.1 seconds with peak
  memory 1377.16 MiB and topological path length 127.
- The longest top-level path remains in the luma palette/range-coder path,
  from `palette_analyzer.query_palette_colors_q` through
  `ff_av2_luma_palette_symbolizer` delta-bit calculation, through the new
  entropy wrapper, toward `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 84647 |
| Estimated LCs | 27323 |
| CARRY4 | 2634 |
| DSP48E1 | 15 |
| FDCE | 4829 |
| FDPE | 24 |
| FDRE | 28451 |
| FDSE | 38 |
| LUT1 | 505 |
| LUT2 | 6557 |
| LUT3 | 4577 |
| LUT4 | 2796 |
| LUT5 | 2504 |
| LUT6 | 17446 |
| MUXF7 | 3957 |
| MUXF8 | 1168 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 305.4 s | 303.5 s | -1.9 s |
| Peak synthesis RSS | 1341.33 MiB | 1377.16 MiB | +35.83 MiB |
| Critical-path report time | 50.4 s | 49.1 s | -1.3 s |
| Topological path length | 127 | 127 | 0 |
| Cells | 82642 | 84647 | +2005 |
| Estimated LCs | 27327 | 27323 | -4 |
| CARRY4 | 2615 | 2634 | +19 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4829 | 4829 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28451 | 28451 | 0 |
| FDSE | 38 | 38 | 0 |
| LUT1 | 482 | 505 | +23 |
| LUT2 | 6254 | 6557 | +303 |
| LUT3 | 4581 | 4577 | -4 |
| LUT4 | 2935 | 2796 | -139 |
| LUT5 | 2783 | 2504 | -279 |
| LUT6 | 17028 | 17446 | +418 |
| MUXF7 | 2847 | 3957 | +1110 |
| MUXF8 | 761 | 1168 | +407 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The refactor keeps the estimated LC count effectively flat and does not add
block RAM, DSP usage, registers, or topological critical-path depth. The larger
raw cell and MUXF counts appear to be a Yosys mapping side effect from the new
hierarchy, not a meaningful FPGA-area increase. Runtime remains just above the
review threshold, so future optimization passes should continue watching the
luma palette/range-coder path.
