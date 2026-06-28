# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## AV2 Packet Flow Timing Check

Baseline and current sources:

- Baseline Git SHA: `151e8276f495b56c9af0376fde7fb11105921f7f`
- Current validated source Git SHA: `509b74f7670b9bfff61209f0779c12e256b00f07`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/reference-decoder checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: not rerun for this checkpoint.

Yosys synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder SYNTH_TIMEOUT_SEC=900`
- RTL top: `ff_av2_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target metadata: 25 MHz
- max visible size: 1024x1024
- timeout/review thresholds: 900 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- palette 4:4:4 support: enabled

Yosys synthesis result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time (s) | 569.90 s | 579.50 s | +9.60 s |
| Runner-observed peak child RSS (MiB) | 1961.34 MiB | 2074.95 MiB | +113.61 MiB |
| Topological path length | 120 | 120 | +0 |
| Flattened cells | 117383 | 123021 | +5638 |
| Estimated LCs | 55268 | 55926 | +658 |
| CARRY4 | 3772 | 3815 | +43 |
| DSP48E1 | 1 | 1 | +0 |
| FDCE | 5163 | 6382 | +1219 |
| FDPE | 92 | 92 | +0 |
| FDRE | 23019 | 23019 | +0 |
| FDSE | 132 | 132 | +0 |
| LUT1 | 863 | 981 | +118 |
| LUT2 | 14092 | 15006 | +914 |
| LUT3 | 12791 | 12231 | -560 |
| LUT4 | 7139 | 7583 | +444 |
| LUT5 | 9918 | 10142 | +224 |
| LUT6 | 25420 | 25970 | +550 |
| MUXF7 | 4711 | 6140 | +1429 |
| MUXF8 | 1329 | 1434 | +105 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest Yosys topological path in `ff_av2_encoder`: length 120.
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
