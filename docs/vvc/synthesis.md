# VVC Synthesis Baseline

This file records the latest VVC-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-22 Shared AXI/FIFO Utilization Pass

Validated RTL/source Git SHA:

- `3945b1bc67a20e5cfa2ccf8d05910ab8741deef0`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
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
| Main Yosys elapsed time (s) | 469.90 s | 494.40 s | +24.50 s |
| Runner-observed peak child RSS (MiB) | 2165.48 MiB | 2303.87 MiB | +138.39 MiB |
| Topological path length | 55 | 55 | +0 |
| Flattened cells | 140116 | 164059 | +23943 |
| Estimated LCs | 53471 | 62294 | +8823 |
| CARRY4 | 4046 | 4178 | +132 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 13166 | 18467 | +5301 |
| FDPE | 299 | 314 | +15 |
| FDRE | 22492 | 23912 | +1420 |
| FDSE | 4 | 8 | +4 |
| LUT1 | 1633 | 1607 | -26 |
| LUT2 | 20491 | 23549 | +3058 |
| LUT3 | 7315 | 7850 | +535 |
| LUT4 | 6056 | 6577 | +521 |
| LUT5 | 8055 | 9034 | +979 |
| LUT6 | 28485 | 34272 | +5787 |
| MUXF7 | 8705 | 9320 | +615 |
| MUXF8 | 1650 | 1859 | +209 |
| RAMB36E1 | 9 | 9 | +0 |

Critical-path summary:

- Longest topological path in `ff_vvc_encoder`: length 55.
- Reported limiter: CABAC syntax frontend IBC MVD absolute-value / EG1 prefix path.

Notes:

- The shared FIFO/instrumentation pass improved VVC simulation cycles materially but increased estimated area. The topological critical-path length stayed at 55.
- The VVC output byte bubble rate remains high because the 4:2:0 bitstreams are small and the CABAC/residual path, not AXI write readiness, limits throughput.
- The reported area is still too large for the Z7-10 fabric; this remains a pressure target for incremental optimization rather than a fit target.
