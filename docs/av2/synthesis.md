# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## AV2 prediction decision block

Baseline and current sources:

- Baseline Git SHA: `28fa335ecfba2e9463e416688f0144bd29f159f3`
- Current validated source Git SHA: `7383aee7b77230a85bdd86c5cf151008ba7de553`

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
| Main Yosys elapsed time (s) | 606.20 s | 629.20 s | +23.00 s |
| Runner-observed peak child RSS (MiB) | 2435.23 MiB | 2453.74 MiB | +18.51 MiB |
| Topological path length | 122 | 122 | +0 |
| Flattened cells | 137682 | 137782 | +100 |
| Estimated LCs | 65368 | 65883 | +515 |
| CARRY4 | 3871 | 3871 | +0 |
| DSP48E1 | 2 | 2 | +0 |
| FDCE | 7714 | 7714 | +0 |
| FDPE | 78 | 78 | +0 |
| FDRE | 20565 | 20565 | +0 |
| FDSE | 133 | 133 | +0 |
| LUT1 | 1159 | 1392 | +233 |
| LUT2 | 16368 | 16084 | -284 |
| LUT3 | 13129 | 13098 | -31 |
| LUT4 | 8239 | 9478 | +1239 |
| LUT5 | 11982 | 12247 | +265 |
| LUT6 | 32018 | 31060 | -958 |
| MUXF7 | 8296 | 7875 | -421 |
| MUXF8 | 1679 | 1705 | +26 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 0 | 0 | +0 |

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
