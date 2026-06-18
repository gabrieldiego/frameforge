# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Chroma Drain Overlap And TXB Pre-Arm

Measured after allowing the AV2 palette analyzer to consume U/V samples while
its luma pad/sort/map pass runs, and after arming the residual symbolizers on
the final TXB fetch-done cycle. Encoded AV2 bitstreams are unchanged; this
checkpoint only removes input/analyzer stalls and one residual setup cycle per
fetched TXB.

Baseline and current sources:

- Baseline Git SHA: `d71698bf9f3d390bdb1eacbb260948499a6ea495`
- Current validated source Git SHA: `1dbdb05bed336861b76d4ee27a162464d0d743ab`
- Baseline mode: payload/carry and analyzer-fetch pipelining.
- Current mode: chroma-drain overlap and residual TXB pre-arm.
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

- Yosys synthesis passed in 255.1 seconds.
- Peak child RSS observed by the synthesis runner was 1287.34 MiB.
- Runtime stayed 44.9 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.0 seconds.
- Post-synthesis critical-path reporting completed in 61.3 seconds with peak
  memory 1287.34 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF token-mux path, the entropy op mux, and
  the range coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 78290 |
| Estimated LCs | 24884 |
| CARRY4 | 2203 |
| DSP48E1 | 11 |
| FDCE | 4912 |
| FDPE | 24 |
| FDRE | 28387 |
| FDSE | 14 |
| LUT1 | 343 |
| LUT2 | 6326 |
| LUT3 | 4195 |
| LUT4 | 2760 |
| LUT5 | 2304 |
| LUT6 | 15625 |
| MUXF7 | 2028 |
| MUXF8 | 420 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 268.1 s | 255.1 s | -13.0 s |
| Peak synthesis RSS | 1332.36 MiB | 1287.34 MiB | -45.02 MiB |
| Cell report time | 5.5 s | 5.0 s | -0.5 s |
| Critical-path report time | 62.3 s | 61.3 s | -1.0 s |
| Topological path length | 55 | 55 | 0 |
| Cells | 78445 | 78290 | -155 |
| Estimated LCs | 24963 | 24884 | -79 |
| CARRY4 | 2204 | 2203 | -1 |
| DSP48E1 | 11 | 11 | 0 |
| FDCE | 4911 | 4912 | +1 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28387 | 28387 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 390 | 343 | -47 |
| LUT2 | 6190 | 6326 | +136 |
| LUT3 | 4167 | 4195 | +28 |
| LUT4 | 2368 | 2760 | +392 |
| LUT5 | 2743 | 2304 | -439 |
| LUT6 | 15685 | 15625 | -60 |
| MUXF7 | 2182 | 2028 | -154 |
| MUXF8 | 497 | 420 | -77 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The chroma-drain overlap and TXB pre-arm keep the longest reported topological
path at 55 nodes, remove 155 flattened cells, reduce estimated LCs by 79, and
leave all RAM counts unchanged. Synthesis time and peak RSS also improve
slightly. The output-cycle reduction documented in
[output-utilization.md](output-utilization.md) is 128060 aggregate cycles on the
full screenshot sweep and 134923 aggregate cycles on the multi-CTU/partial set,
with unchanged bitstreams. The next likely throughput target is TXB prefetch
from the analyzer sample store; the next likely timing target remains the
palette-token-to-range-coder path, especially the analyzer's top-left index
lookup and range normalization.
