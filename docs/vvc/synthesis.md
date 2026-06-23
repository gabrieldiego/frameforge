# VVC Synthesis Baseline

This file records the latest VVC-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-23 Palette CU Serialization Checkpoint

Baseline RTL/source Git SHA:

- `1f2e144c57cb20f7f7ca4aa2c436a6d43162a2c8`

Current RTL/source Git SHA:

- `33e4c40f88f0919ed0189adcb65cea1738e5c5e2`

Validation result:

- Local `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- Local `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- Local `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
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
| Main Yosys elapsed time (s) | 533.70 | 502.40 | -31.30 |
| Runner-observed peak child RSS (MiB) | 2520.32 | 2541.29 | +20.97 |
| Topological path length | 54 | 192 | +138 |
| Flattened cells | 183340 | 195780 | +12440 |
| Estimated LCs | 66597 | 70730 | +4133 |
| CARRY4 | 4190 | 4047 | -143 |
| DSP48E1 | 9 | 11 | +2 |
| FDCE | 20091 | 27366 | +7275 |
| FDPE | 314 | 315 | +1 |
| FDRE | 31160 | 24028 | -7132 |
| FDSE | 8 | 4 | -4 |
| LUT1 | 2058 | 2203 | +145 |
| LUT2 | 23379 | 24091 | +712 |
| LUT3 | 9475 | 9171 | -304 |
| LUT4 | 7837 | 8838 | +1001 |
| LUT5 | 8680 | 11723 | +3043 |
| LUT6 | 37571 | 37957 | +386 |
| MUXF7 | 11505 | 12085 | +580 |
| MUXF8 | 2363 | 2047 | -316 |
| RAMB36E1 | 9 | 6 | -3 |

Critical-path summary:

- Longest topological path in `ff_vvc_encoder`: length 192.
- Reported limiter: palette CU symbolizer first-come palette lookup chain
  from `build_lane_q` through `build_found` into `indices_q`.

Notes:

- The palette CU builder now serializes each accepted 8-sample row one lane
  at a time. This removes the former eight-lane parallel palette lookup from
  the main build path and allowed Yosys to complete again within the hard
  stop, but the serialized single-lane lookup is now the topological limiter.
- Main synthesis runtime improved by 31.30 seconds against the previous
  documented Yosys checkpoint. Peak runner-observed RSS increased by 20.97 MiB.
- Mapped cell and estimated LC counts increased; the area increase should be
  treated as the next VVC optimization target after preserving the functional
  full-regression baseline.
- RAMB36E1 usage dropped from 9 to 6 in the flattened estimate.
- The reported area is still too large for the Z7-10 fabric; this remains a
  pressure target for incremental optimization rather than a fit target.
