# VVC Synthesis Baseline

This file records the latest VVC-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-23 Multi-CTU IBC Throughput Checkpoint

Baseline RTL/source Git SHA:

- `33e4c40f88f0919ed0189adcb65cea1738e5c5e2`

Current RTL/source Git SHA:

- `d2cb6801f111a0023d7f982b875faccbf8c17f91`

Validation result:

- Local `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target; runtime exceeded the 300
  second review threshold but stayed inside the 600 second hard stop.

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
| Main Yosys elapsed time (s) | 502.40 | 510.20 | +7.80 |
| Runner-observed peak child RSS (MiB) | 2541.29 | 2515.68 | -25.61 |
| Topological path length | 192 | 192 | +0 |
| Flattened cells | 195780 | 195299 | -481 |
| Estimated LCs | 70730 | 71281 | +551 |
| CARRY4 | 4047 | 4079 | +32 |
| DSP48E1 | 11 | 11 | +0 |
| FDCE | 27366 | 26909 | -457 |
| FDPE | 315 | 314 | -1 |
| FDRE | 24028 | 23788 | -240 |
| FDSE | 4 | 4 | +0 |
| LUT1 | 2203 | 2194 | -9 |
| LUT2 | 24091 | 24054 | -37 |
| LUT3 | 9171 | 9174 | +3 |
| LUT4 | 8838 | 8864 | +26 |
| LUT5 | 11723 | 11581 | -142 |
| LUT6 | 37957 | 38654 | +697 |
| MUXF7 | 12085 | 12130 | +45 |
| MUXF8 | 2047 | 2125 | +78 |
| RAMB36E1 | 6 | 6 | +0 |

Critical-path summary:

- Longest topological path in `ff_vvc_encoder`: length 192.
- Reported limiter: palette CU symbolizer first-come palette lookup chain
  from `build_lane_q` through `build_found` into `indices_q`.

Notes:

- The IBC hash matcher now resolves only the local A1/B1/B0 exact-hash
  candidate subset at the end of each 8x8 TU. This avoids the unsynthesizable
  64-way CTU search while allowing palette leaf payload emission to resume as
  soon as the requested TU has arrived.
- Main synthesis runtime increased by 7.80 seconds against the previous
  documented Yosys checkpoint, while peak runner-observed RSS dropped by
  25.61 MiB and flattened cells dropped by 481.
- Estimated LCs increased by 551, mainly from LUT6/MUX distribution changes.
  Keep this as an area watch item, but the change remains within the same
  topological path length and completes under the 3 GiB memory cap.
- The reported area is still too large for the Z7-10 fabric; this remains a
  pressure target for incremental optimization rather than a fit target.
