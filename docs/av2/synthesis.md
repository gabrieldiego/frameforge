# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-25 AV2 IBC Hash Expansion Checkpoint

Baseline and current sources:

- Baseline Git SHA: `48ba35795881b898d28fbd6de13cac61147ac108`
- Current validated source Git SHA: `6779c2e4b2726adef94cd7921dd62f106e454afb+working-tree`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: not rerun for this checkpoint.

Yosys synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- RTL top: `ff_av2_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target metadata: 25 MHz
- max visible size: 1024x1024
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- palette 4:4:4 support: enabled

Yosys synthesis result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time (s) | 438.60 s | 494.50 s | +55.90 s |
| Runner-observed peak child RSS (MiB) | 1820.45 MiB | 1790.58 MiB | -29.87 MiB |
| Topological path length | 120 | 120 | +0 |
| Flattened cells | 104877 | 105492 | +615 |
| Estimated LCs | 43866 | 44616 | +750 |
| CARRY4 | 3660 | 3660 | +0 |
| DSP48E1 | 1 | 1 | +0 |
| FDCE | 5119 | 5119 | +0 |
| FDPE | 92 | 92 | +0 |
| FDRE | 22812 | 22812 | +0 |
| FDSE | 132 | 132 | +0 |
| LUT1 | 742 | 718 | -24 |
| LUT2 | 13717 | 13482 | -235 |
| LUT3 | 9925 | 10792 | +867 |
| LUT4 | 6146 | 5853 | -293 |
| LUT5 | 5868 | 6081 | +213 |
| LUT6 | 21927 | 21890 | -37 |
| MUXF7 | 4896 | 4862 | -34 |
| MUXF8 | 1245 | 1294 | +49 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest Yosys topological path in `ff_av2_encoder`: length 120.
- Reported limiter: input FIFO data selection feeding the 4:4:4
  palette-color update path in `ff_av2_palette_analyzer_444`.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.
- The earlier multiplier and chroma sign-lookahead paths no longer dominate
  the synthesis reports.

Vivado synthesis and timing result:

- Not rerun for this checkpoint; use the previous committed report as the
  latest Vivado timing reference.

Notes:

- Current Yosys critical path remains in the AV2 palette analyzer, from the
  input sample FIFO selection into the palette-color update path.
- Bitrate deltas reflect the refreshed validation logs for this checkpoint;
  output-utilization deltas include any RTL-cycle changes from the current
  IBC and entropy-path updates.
