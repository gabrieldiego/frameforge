# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Palette CDF Token Mux Cleanup

Measured after replacing the AV2 luma palette map-token CDF arrays with named
CDF endpoints and an explicit token interval mux. This is a synthesis cleanup
only; encoded AV2 bitstreams and output scheduling are unchanged.

Baseline and current sources:

- Baseline Git SHA: `e2cac734b0ca685fc3e26258b27a2a2715531daa`
- Current validated source Git SHA: `f8a3c0bf8931504e690088fe96d454c780316e44`
- Baseline mode: range coder datapath narrowing.
- Current mode: palette CDF token mux cleanup.
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

- Yosys synthesis passed in 234.5 seconds.
- Peak child RSS observed by the synthesis runner was 1291.31 MiB.
- Runtime stayed 65.5 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.0 seconds.
- Post-synthesis critical-path reporting completed in 40.9 seconds with peak
  memory 1291.31 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF token-mux path, the entropy op mux, and
  the range coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 78583 |
| Estimated LCs | 25058 |
| CARRY4 | 2213 |
| DSP48E1 | 11 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 351 |
| LUT2 | 6225 |
| LUT3 | 4445 |
| LUT4 | 2466 |
| LUT5 | 2328 |
| LUT6 | 15819 |
| MUXF7 | 2141 |
| MUXF8 | 480 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 234.3 s | 234.5 s | +0.2 s |
| Peak synthesis RSS | 1304.85 MiB | 1291.31 MiB | -13.54 MiB |
| Cell report time | 5.0 s | 5.0 s | 0.0 s |
| Critical-path report time | 41.0 s | 40.9 s | -0.1 s |
| Topological path length | 57 | 55 | -2 |
| Cells | 78444 | 78583 | +139 |
| Estimated LCs | 25016 | 25058 | +42 |
| CARRY4 | 2214 | 2213 | -1 |
| DSP48E1 | 11 | 11 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 247 | 351 | +104 |
| LUT2 | 6282 | 6225 | -57 |
| LUT3 | 4088 | 4445 | +357 |
| LUT4 | 2435 | 2466 | +31 |
| LUT5 | 2850 | 2328 | -522 |
| LUT6 | 15643 | 15819 | +176 |
| MUXF7 | 2084 | 2141 | +57 |
| MUXF8 | 466 | 480 | +14 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The palette CDF token mux cleanup removes the dynamic CDF-array read from the
map-token path and reduces the longest reported topological path by 2 nodes.
The tradeoff is modest: 139 more cells and 42 more estimated LCs, with one fewer
`CARRY4`, unchanged DSP/BRAM/register counts, and 13.54 MiB lower peak RSS. The
next likely timing target remains the palette-token-to-range-coder path,
especially the analyzer's top-left index lookup and range normalization.
