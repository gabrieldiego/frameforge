# AV2 Synthesis Baselines

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-16 Luma Intra + IntraBC Syntax Fix

Measured after adding the first AV2 luma H/V intra-prediction selector and
fixing SW/RTL parity for frame-level `allow_intrabc` versus per-leaf
`use_intrabc`. The H/V path is deliberately restricted to terminal 8x8 leaves
with the currently implemented luma-mode context so the syntax remains aligned
with the AV2 reference decoder while later context expansion is still pending.

Baseline and current sources:

- Baseline Git SHA: `d04435fd29ec73e18181c54c2452b869add56b87`
- Current validated source Git SHA: `17ff78397917f320a13809216e957826acd9cbc7`
- Baseline mode: previously documented AV2 left-hash IBC checkpoint.
- Current mode: AV2 software/RTL/reference-decoder validation after adding
  restricted H/V luma intra prediction and fixing IntraBC syntax parity.
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

- Yosys synthesis passed in 305.4 seconds.
- Peak child RSS observed by the synthesis runner was 1341.33 MiB.
- Runtime exceeded the 300 second review threshold by 5.4 seconds but stayed
  inside the 600 second hard timeout.
- Post-synthesis critical-path reporting completed in 50.4 seconds with peak
  memory 1341.33 MiB and topological path length 127.
- The longest top-level path remains in the luma palette/range-coder path,
  from `palette_analyzer.query_palette_colors_q` through
  `ff_av2_luma_palette_symbolizer` delta-bit calculation toward `low_q`.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`yosys -p 'read_json synth/out/arty-z7-10/ff_av2_encoder/ff_av2_encoder.json; hierarchy -top ff_av2_encoder; flatten; stat -tech xilinx'`:

| Metric | Count |
|---|---:|
| Cells | 82642 |
| Estimated LCs | 27327 |
| CARRY4 | 2615 |
| DSP48E1 | 15 |
| FDCE | 4829 |
| FDPE | 24 |
| FDRE | 28451 |
| FDSE | 38 |
| LUT1 | 482 |
| LUT2 | 6254 |
| LUT3 | 4581 |
| LUT4 | 2935 |
| LUT5 | 2783 |
| LUT6 | 17028 |
| MUXF7 | 2847 |
| MUXF8 | 761 |
| RAMB36E1 | 19 |
| RAM32M | 4 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 275.6 s | 305.4 s | +29.8 s |
| Peak synthesis RSS | 1202.92 MiB | 1341.33 MiB | +138.41 MiB |
| Critical-path report time | 41.1 s | 50.4 s | +9.3 s |
| Topological path length | 127 | 127 | 0 |
| Cells | 68721 | 82642 | +13921 |
| Estimated LCs | 23723 | 27327 | +3604 |
| CARRY4 | 2595 | 2615 | +20 |
| DSP48E1 | 15 | 15 | 0 |
| FDCE | 4075 | 4829 | +754 |
| FDPE | 24 | 24 | 0 |
| FDRE | 20129 | 28451 | +8322 |
| FDSE | 38 | 38 | 0 |
| LUT1 | 398 | 482 | +84 |
| LUT2 | 6107 | 6254 | +147 |
| LUT3 | 5271 | 4581 | -690 |
| LUT4 | 2295 | 2935 | +640 |
| LUT5 | 2436 | 2783 | +347 |
| LUT6 | 13721 | 17028 | +3307 |
| MUXF7 | 2650 | 2847 | +197 |
| MUXF8 | 727 | 761 | +34 |
| RAMB36E1 | 19 | 19 | 0 |
| RAM32M | 4 | 4 | 0 |
| RAM64M | 1536 | 1536 | 0 |

The new logic increases register and LUT pressure, but does not add block RAM,
DSP usage, or topological critical-path depth. The synthesis runtime now barely
crosses the review threshold, so future passes should watch the luma
palette/range-coder path and the extra luma predictor state for opportunities
to recover area before widening the intra context model.
