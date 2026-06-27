# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-26 AV2 Multi-Frame Report Refresh

Baseline and current sources:

- Baseline Git SHA: `34e1dca8f313dd433452ca27fb81d858d90e1617`
- Current validated source Git SHA: `151e8276f495b56c9af0376fde7fb11105921f7f`

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
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- palette 4:4:4 support: enabled

Yosys synthesis result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time (s) | 518.60 s | 569.90 s | +51.30 s |
| Runner-observed peak child RSS (MiB) | 1933.59 MiB | 1961.34 MiB | +27.75 MiB |
| Topological path length | 120 | 120 | +0 |
| Flattened cells | 116915 | 117383 | +468 |
| Estimated LCs | 55189 | 55268 | +79 |
| CARRY4 | 3739 | 3772 | +33 |
| DSP48E1 | 1 | 1 | +0 |
| FDCE | 5163 | 5163 | +0 |
| FDPE | 92 | 92 | +0 |
| FDRE | 22907 | 23019 | +112 |
| FDSE | 132 | 132 | +0 |
| LUT1 | 830 | 863 | +33 |
| LUT2 | 14075 | 14092 | +17 |
| LUT3 | 12301 | 12791 | +490 |
| LUT4 | 7195 | 7139 | -56 |
| LUT5 | 10414 | 9918 | -496 |
| LUT6 | 25279 | 25420 | +141 |
| MUXF7 | 4795 | 4711 | -84 |
| MUXF8 | 1184 | 1329 | +145 |
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
