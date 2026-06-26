# VVC Synthesis Baseline

This file records the latest VVC-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-25 Multi-Frame Stream-Termination Checkpoint

Baseline RTL/source Git SHA:

- `d2cb6801f111a0023d7f982b875faccbf8c17f91`

Current RTL/source Git SHA:

- `918788950cb449d4403a0c375493de48ac486d01`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/VTM checksum parity.
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
| Main Yosys elapsed time (s) | 510.20 | 567.80 | +57.60 |
| Runner-observed peak child RSS (MiB) | 2515.68 | 2521.39 | +5.71 |
| Topological path length | 192 | 192 | +0 |
| Flattened cells | 195299 | 196393 | +1094 |
| Estimated LCs | 71281 | 72133 | +852 |
| CARRY4 | 4079 | 4131 | +52 |
| DSP48E1 | 11 | 7 | -4 |
| FDCE | 26909 | 27138 | +229 |
| FDPE | 314 | 314 | +0 |
| FDRE | 23788 | 23788 | +0 |
| FDSE | 4 | 4 | +0 |
| LUT1 | 2194 | 2250 | +56 |
| LUT2 | 24054 | 24962 | +908 |
| LUT3 | 9174 | 8939 | -235 |
| LUT4 | 8864 | 8711 | -153 |
| LUT5 | 11581 | 11704 | +123 |
| LUT6 | 38654 | 39123 | +469 |
| MUXF7 | 12130 | 11529 | -601 |
| MUXF8 | 2125 | 2135 | +10 |
| RAMB36E1 | 6 | 6 | +0 |

Critical-path summary:

- Longest topological path in `ff_vvc_encoder`: length 192.
- Reported limiter: palette CU symbolizer first-come palette lookup chain
  from `build_lane_q` through `build_found` into `indices_q`.

Notes:

- The VVC top now separates per-frame `m_axis_last` observability from the
  AXI bitstream writer's stream-final marker. This lets multi-frame streams
  drain all frames instead of stopping after the first frame boundary.
- Main synthesis runtime increased by 57.60 seconds against the previous
  documented Yosys checkpoint, while peak runner-observed RSS increased by
  5.71 MiB and remained under the 3 GiB cap.
- Estimated LCs increased by 852 and flattened cells increased by 1094. Keep
  this as an area watch item; the topological path length stayed at 192.
- The reported area is still too large for the Z7-10 fabric; this remains a
  pressure target for incremental optimization rather than a fit target.
