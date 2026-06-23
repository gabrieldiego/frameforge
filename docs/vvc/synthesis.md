# VVC Synthesis Baseline

This file records the latest VVC-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-22 Palette Syntax Scan Skip Checkpoint

Baseline RTL/source Git SHA:

- `e2fd88a0ebc7d05be240f48c61b2db9efad53023`

Current RTL/source Git SHA:

- `1f2e144c57cb20f7f7ca4aa2c436a6d43162a2c8`

Validation result:

- Local `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- Local `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- Local `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- Local `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target; runtime exceeded the 300 second review threshold but stayed inside the 600 second hard stop.

Yosys synthesis configuration:

- command: `make synth CODEC=vvc SYNTH_DUT=vvc-encoder`
- RTL top: `ff_vvc_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target metadata: 25 MHz
- max visible size: 1024x1024
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- palette 4:4:4 support: enabled

Yosys synthesis result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time (s) | 541.30 s | 533.70 s | -7.60 s |
| Runner-observed peak child RSS (MiB) | 2498.41 MiB | 2520.32 MiB | +21.91 MiB |
| Topological path length | 54 | 54 | +0 |
| Flattened cells | 181835 | 183340 | +1505 |
| Estimated LCs | 66242 | 66597 | +355 |
| CARRY4 | 4173 | 4190 | +17 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 20011 | 20091 | +80 |
| FDPE | 314 | 314 | +0 |
| FDRE | 31160 | 31160 | +0 |
| FDSE | 8 | 8 | +0 |
| LUT1 | 1946 | 2058 | +112 |
| LUT2 | 22781 | 23379 | +598 |
| LUT3 | 9439 | 9475 | +36 |
| LUT4 | 8192 | 7837 | -355 |
| LUT5 | 9299 | 8680 | -619 |
| LUT6 | 36737 | 37571 | +834 |
| MUXF7 | 11201 | 11505 | +304 |
| MUXF8 | 1928 | 2363 | +435 |
| RAMB36E1 | 9 | 9 | +0 |

Critical-path summary:

- Longest topological path in `ff_vvc_encoder`: length 54.
- Reported limiter: CABAC syntax frontend IBC MVD absolute-value / EG1 prefix path.

Notes:

- Palette index-level coding now builds a per-subset emit mask while processing
  run-copy flags. The syntax frontend uses a grouped seek to skip idle palette
  index positions without putting a 16-way priority selector on the emit path.
- Palette escape coding records escape positions in a 64-bit CU mask and loads a
  registered 16-sample active subset before escape values are coded. Escape seek
  also uses four-position groups to keep the critical path at the prior baseline.
- The 64x64 screenshot 4:4:4 smoke improved from 32982 cycles at the baseline
  to 31387 cycles with this checkpoint while preserving exact SW/RTL/VTM bitstream
  and reconstruction checksums.
- The VVC output byte bubble rate remains high because the bitstreams are small
  and CABAC byte production, not AXI write readiness, is the dominant limiter.
- The reported area is still too large for the Z7-10 fabric; this remains a pressure target for incremental optimization rather than a fit target.
