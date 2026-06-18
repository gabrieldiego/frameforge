# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Chroma TXB Fetch Cache

Measured after adding per-leaf U/V sample caches, cached V predictor samples,
small chroma edge predictor caches, and cache-hit bypasses around
`ST_CHROMA_FETCH`. This reduces output bubbles without changing the AV2
bitstream, reference reconstruction, or BRAM count. The cost is higher local
register and mux usage in the AV2 top and palette analyzer path.

Baseline and current sources:

- Baseline Git SHA: `7f0ac7ee85b6ac6d5ef7c9ef8b402897e9843590`
- Current validated source Git SHA: `c125ea91a2e0643313a77870172c49d0331d5339`
- Baseline mode: TXB sample prefetch during entropy emission.
- Current mode: chroma TXB fetch cache and predictor cache-hit bypass.
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

- Yosys synthesis passed in 296.7 seconds.
- Peak child RSS observed by the synthesis runner was 1379.55 MiB.
- Runtime stayed 3.3 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.6 seconds.
- Post-synthesis critical-path reporting completed in 68.6 seconds with peak
  memory 1379.55 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF token-mux path, the entropy op mux, and
  the range coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 83788 |
| Estimated LCs | 27765 |
| CARRY4 | 2226 |
| DSP48E1 | 11 |
| FDCE | 5488 |
| FDPE | 24 |
| FDRE | 29588 |
| FDSE | 14 |
| LUT1 | 349 |
| LUT2 | 6187 |
| LUT3 | 5569 |
| LUT4 | 2267 |
| LUT5 | 2929 |
| LUT6 | 17000 |
| MUXF7 | 2241 |
| MUXF8 | 447 |
| RAMB36E1 | 19 |
| RAM32M | 10 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 273.3 s | 296.7 s | +23.4 s |
| Peak synthesis RSS | 1296.33 MiB | 1379.55 MiB | +83.22 MiB |
| Cell report time | 5.3 s | 5.6 s | +0.3 s |
| Critical-path report time | 65.1 s | 68.6 s | +3.5 s |
| Topological path length | 55 | 55 | 0 |
| Cells | 78519 | 83788 | +5269 |
| Estimated LCs | 25382 | 27765 | +2383 |
| CARRY4 | 2213 | 2226 | +13 |
| DSP48E1 | 11 | 11 | 0 |
| FDCE | 4912 | 5488 | +576 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28390 | 29588 | +1198 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 330 | 349 | +19 |
| LUT2 | 6115 | 6187 | +72 |
| LUT3 | 4521 | 5569 | +1048 |
| LUT4 | 2210 | 2267 | +57 |
| LUT5 | 2337 | 2929 | +592 |
| LUT6 | 16314 | 17000 | +686 |
| MUXF7 | 2032 | 2241 | +209 |
| MUXF8 | 403 | 447 | +44 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 10 | +6 |
| RAM64M | 1536 | 1536 | 0 |

The chroma fetch cache keeps the longest reported topological path at 55 nodes
and leaves BRAM/DSP counts unchanged. It increases the estimate by 5269
flattened cells and 2383 estimated LCs, mostly from cached chroma TXB registers
and predictor muxing, while aggregate cycles fall by 145967 on the full
screenshot sweep and 192420 on the multi-CTU/partial set relative to the
previous documented checkpoint. Further large bubble reductions will likely
need one of the larger architectural changes still visible in the state-cycle
profile: a wider input interface, a streaming carry resolver, or multi-symbol
entropy emission.
