# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Residual Entropy Context Cleanup

Measured after replacing the AV2 residual cumulative-level context adder chain
with a saturated reduction tree and a scan-order EOB priority mask. This is a
synthesis cleanup only; encoded AV2 bitstreams and output scheduling are
unchanged.

Baseline and current sources:

- Baseline Git SHA: `0059f7a8f61fa78529b075e699d7b118de7882f4`
- Current validated source Git SHA: `88dbd0f5809a69d9b5fd2e4411bf27ca09ec9898`
- Baseline mode: direct closed-header field assembly.
- Current mode: residual entropy context cleanup.
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

- Yosys synthesis passed in 234.7 seconds.
- Peak child RSS observed by the synthesis runner was 1286.67 MiB.
- Runtime stayed 65.3 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.0 seconds.
- Post-synthesis critical-path reporting completed in 41.9 seconds with peak
  memory 1286.67 MiB and topological path length 61.
- The longest top-level path now starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority/token/CDF path, the entropy op mux, and the range coder normalization
  path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 77824 |
| Estimated LCs | 24551 |
| CARRY4 | 2243 |
| DSP48E1 | 15 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 268 |
| LUT2 | 6547 |
| LUT3 | 4189 |
| LUT4 | 2231 |
| LUT5 | 2354 |
| LUT6 | 15713 |
| MUXF7 | 1767 |
| MUXF8 | 367 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 235.2 s | 234.7 s | -0.5 s |
| Peak synthesis RSS | 1304.47 MiB | 1286.67 MiB | -17.80 MiB |
| Cell report time | 5.1 s | 5.0 s | -0.1 s |
| Critical-path report time | 41.2 s | 41.9 s | +0.7 s |
| Topological path length | 66 | 61 | -5 |
| Cells | 78870 | 77824 | -1046 |
| Estimated LCs | 25127 | 24551 | -576 |
| CARRY4 | 2269 | 2243 | -26 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 442 | 268 | -174 |
| LUT2 | 6532 | 6547 | +15 |
| LUT3 | 4424 | 4189 | -235 |
| LUT4 | 2208 | 2231 | +23 |
| LUT5 | 2637 | 2354 | -283 |
| LUT6 | 15858 | 15713 | -145 |
| MUXF7 | 1931 | 1767 | -164 |
| MUXF8 | 435 | 367 | -68 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The residual context cleanup reduced the reported topological path length by 5
and moved the longest top-level path out of the luma palette residual
symbolizer. It also reduced cells by 1046, estimated LCs by 576, CARRY4 cells by
26, peak RSS by 17.80 MiB, and synthesis runtime by 0.5 seconds. BRAM, DSP, and
register counts are unchanged. The next likely timing target is the luma palette
symbolizer path that starts at top-left neighbor lookup and feeds the range
coder through palette token CDF selection.
