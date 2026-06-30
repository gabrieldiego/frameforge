# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-29 AV2 Report Checkpoint

Baseline and current sources:

- Baseline Git SHA: `509b74f7670b9bfff61209f0779c12e256b00f07`
- Current validated source Git SHA: `28fa335ecfba2e9463e416688f0144bd29f159f3`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/reference-decoder checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: not rerun for this checkpoint.

Yosys synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- RTL top: `ff_av2_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target metadata: 25 MHz
- max visible size: 1024x1024
- timeout/review thresholds: 900 seconds hard stop, 600 seconds review
- memory limit: 3072 MiB
- palette 4:4:4 support: enabled

Yosys synthesis result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time (s) | 579.50 s | 606.20 s | +26.70 s |
| Runner-observed peak child RSS (MiB) | 2074.95 MiB | 2435.23 MiB | +360.28 MiB |
| Topological path length | 120 | 122 | +2 |
| Flattened cells | 123021 | 137682 | +14661 |
| Estimated LCs | 55926 | 65368 | +9442 |
| CARRY4 | 3815 | 3871 | +56 |
| DSP48E1 | 1 | 2 | +1 |
| FDCE | 6382 | 7714 | +1332 |
| FDPE | 92 | 78 | -14 |
| FDRE | 23019 | 20565 | -2454 |
| FDSE | 132 | 133 | +1 |
| LUT1 | 981 | 1159 | +178 |
| LUT2 | 15006 | 16368 | +1362 |
| LUT3 | 12231 | 13129 | +898 |
| LUT4 | 7583 | 8239 | +656 |
| LUT5 | 10142 | 11982 | +1840 |
| LUT6 | 25970 | 32018 | +6048 |
| MUXF7 | 6140 | 8296 | +2156 |
| MUXF8 | 1434 | 1679 | +245 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 0 | -10 |

Critical-path summary:

- Longest Yosys topological path in `ff_av2_encoder`: length 122.
- Reported limiter: input FIFO data selection feeding the 4:4:4
  palette-color update path in `ff_av2_palette_analyzer_444`.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.

Vivado synthesis and timing result:

- Not rerun for this checkpoint; use the previous committed report as the
  latest Vivado timing reference.

Notes:

- Bitrate deltas reflect the refreshed validation logs for this checkpoint;
  output-utilization deltas include any RTL-cycle changes from the current
  RTL updates.
