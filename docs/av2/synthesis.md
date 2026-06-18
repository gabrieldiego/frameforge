# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 TXB Sample Prefetch During Entropy Emission

Measured after prefetching analyzer sample-store data for the next transform
block while the current transform block is emitting entropy symbols. This
scheduling change reduces output bubbles without changing the AV2 bitstream,
reference reconstruction, or BRAM footprint. The cost is a modest increase in
control and mux logic around the analyzer fetch interface.

Baseline and current sources:

- Baseline Git SHA: `1dbdb05bed336861b76d4ee27a162464d0d743ab`
- Current validated source Git SHA: `7f0ac7ee85b6ac6d5ef7c9ef8b402897e9843590`
- Baseline mode: chroma-drain overlap and residual TXB pre-arm.
- Current mode: TXB sample prefetch during entropy emission.
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

- Yosys synthesis passed in 273.3 seconds.
- Peak child RSS observed by the synthesis runner was 1296.33 MiB.
- Runtime stayed 26.7 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.3 seconds.
- Post-synthesis critical-path reporting completed in 65.1 seconds with peak
  memory 1296.33 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF token-mux path, the entropy op mux, and
  the range coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 78519 |
| Estimated LCs | 25382 |
| CARRY4 | 2213 |
| DSP48E1 | 11 |
| FDCE | 4912 |
| FDPE | 24 |
| FDRE | 28390 |
| FDSE | 14 |
| LUT1 | 330 |
| LUT2 | 6115 |
| LUT3 | 4521 |
| LUT4 | 2210 |
| LUT5 | 2337 |
| LUT6 | 16314 |
| MUXF7 | 2032 |
| MUXF8 | 403 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 255.1 s | 273.3 s | +18.2 s |
| Peak synthesis RSS | 1287.34 MiB | 1296.33 MiB | +8.99 MiB |
| Cell report time | 5.0 s | 5.3 s | +0.3 s |
| Critical-path report time | 61.3 s | 65.1 s | +3.8 s |
| Topological path length | 55 | 55 | 0 |
| Cells | 78290 | 78519 | +229 |
| Estimated LCs | 24884 | 25382 | +498 |
| CARRY4 | 2203 | 2213 | +10 |
| DSP48E1 | 11 | 11 | 0 |
| FDCE | 4912 | 4912 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28387 | 28390 | +3 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 343 | 330 | -13 |
| LUT2 | 6326 | 6115 | -211 |
| LUT3 | 4195 | 4521 | +326 |
| LUT4 | 2760 | 2210 | -550 |
| LUT5 | 2304 | 2337 | +33 |
| LUT6 | 15625 | 16314 | +689 |
| MUXF7 | 2028 | 2032 | +4 |
| MUXF8 | 420 | 403 | -17 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The TXB prefetch scheduler keeps the longest reported topological path at 55
nodes and leaves all RAM counts unchanged. The added request muxing and prefetch
state increased the estimate by 229 flattened cells and 498 estimated LCs, while
aggregate cycles fell by 126598 on the full screenshot sweep and 107566 on the
multi-CTU/partial set. The next likely throughput target is the staged
pre-carry/output path; removing more bubbles there will likely require a broader
streaming carry resolver rather than another local fetch scheduler.
