# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-17 Range Coder Datapath Narrowing

Measured after narrowing the AV2 range coder's probability-scaling datapath to
the 16-bit `rng` interval used by the entropy coder normalization path. This is
a synthesis cleanup only; encoded AV2 bitstreams and output scheduling are
unchanged.

Baseline and current sources:

- Baseline Git SHA: `1c68cec7173dc4aa40e50370834d85587470665c`
- Current validated source Git SHA: `e2cac734b0ca685fc3e26258b27a2a2715531daa`
- Baseline mode: palette token ranking cleanup.
- Current mode: range coder datapath narrowing.
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

- Yosys synthesis passed in 234.3 seconds.
- Peak child RSS observed by the synthesis runner was 1304.85 MiB.
- Runtime stayed 65.7 seconds below the 300 second review threshold and inside
  the 600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.0 seconds.
- Post-synthesis critical-path reporting completed in 41.0 seconds with peak
  memory 1304.85 MiB and topological path length 57.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer's top-left query logic, the luma palette symbolizer's
  priority-before-count/token-rank/CDF path, the entropy op mux, and the range
  coder normalization path to `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 78444 |
| Estimated LCs | 25016 |
| CARRY4 | 2214 |
| DSP48E1 | 11 |
| FDCE | 4923 |
| FDPE | 24 |
| FDRE | 28403 |
| FDSE | 14 |
| LUT1 | 247 |
| LUT2 | 6282 |
| LUT3 | 4088 |
| LUT4 | 2435 |
| LUT5 | 2850 |
| LUT6 | 15643 |
| MUXF7 | 2084 |
| MUXF8 | 466 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 237.8 s | 234.3 s | -3.5 s |
| Peak synthesis RSS | 1315.14 MiB | 1304.85 MiB | -10.29 MiB |
| Cell report time | 5.0 s | 5.0 s | 0.0 s |
| Critical-path report time | 41.7 s | 41.0 s | -0.7 s |
| Topological path length | 57 | 57 | 0 |
| Cells | 78445 | 78444 | -1 |
| Estimated LCs | 25061 | 25016 | -45 |
| CARRY4 | 2243 | 2214 | -29 |
| DSP48E1 | 15 | 11 | -4 |
| FDCE | 4923 | 4923 | 0 |
| FDPE | 24 | 24 | 0 |
| FDRE | 28403 | 28403 | 0 |
| FDSE | 14 | 14 | 0 |
| LUT1 | 252 | 247 | -5 |
| LUT2 | 6447 | 6282 | -165 |
| LUT3 | 4545 | 4088 | -457 |
| LUT4 | 2358 | 2435 | +77 |
| LUT5 | 2294 | 2850 | +556 |
| LUT6 | 15864 | 15643 | -221 |
| MUXF7 | 1850 | 2084 | +234 |
| MUXF8 | 454 | 466 | +12 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The range-coder datapath narrowing removes four inferred DSP blocks and 29
`CARRY4` cells by avoiding 32-bit probability-scaling multiplies where the AV2
normalization interval is already bounded to 16 bits. The longest topological
path remains at 57 nodes, so this is an area/resource cleanup rather than a new
timing breakthrough. The next likely timing target remains the
palette-token-to-range-coder path, especially CDF selection and range
normalization.
