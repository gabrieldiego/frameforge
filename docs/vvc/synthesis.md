# VVC Synthesis Baseline

This file records the latest VVC-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-29 VVC Report Checkpoint

Baseline and current sources:

- Baseline Git SHA: `d2cb6801f111a0023d7f982b875faccbf8c17f91`
- Current validated source Git SHA: `28fa335ecfba2e9463e416688f0144bd29f159f3`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/VTM checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: PASS at 25 MHz target, WNS is positive.

Yosys synthesis configuration:

- command: `make synth CODEC=vvc SYNTH_DUT=vvc-encoder`
- RTL top: `ff_vvc_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target metadata: 25 MHz
- max visible size: 1024x1024
- timeout/review thresholds: 900 seconds hard stop, 600 seconds review
- memory limit: 3072 MiB
- palette 4:4:4 support: enabled

Yosys synthesis result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time (s) | 510.20 s | 573.20 s | +63.00 s |
| Runner-observed peak child RSS (MiB) | 2515.68 MiB | 2522.21 MiB | +6.53 MiB |
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
| RAM32M | n/a | 0 | n/a |

Critical-path summary:

- Longest Yosys topological path in `ff_vvc_encoder`: length 192.
- Reported limiter: palette CU symbolizer first-come palette lookup chain
  from `build_lane_q` through `build_found` into `indices_q`.

Vivado synthesis configuration:

- command: `make synth-vivado CODEC=vvc SYNTH_DUT=vvc-encoder SYNTH_TIMEOUT_SEC=1800 SYNTH_WARN_AFTER_SEC=600 SYNTH_VIVADO_MAX_THREADS=1 SYNTH_MEMORY_LIMIT_MB=4096`
- RTL top: `ff_vvc_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target: 25 MHz
- max visible size: 1024x1024
- palette 4:4:4 support: enabled

Vivado synthesis and timing result:

- Not rerun for this checkpoint; Vivado reports were not available.
- Re-run with `REPORT_SYNTHESIS_TOOL=yosys-vivado` after running Vivado synthesis.

Notes:

- Bitrate deltas reflect the refreshed validation logs for this checkpoint;
  output-utilization deltas include any RTL-cycle changes from the current
  RTL updates.
