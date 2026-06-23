# VVC Synthesis Baseline

This file records the latest VVC-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-22 CABAC FIFO Throughput Checkpoint

Baseline RTL/source Git SHA:

- `3945b1bc67a20e5cfa2ccf8d05910ab8741deef0`

Current RTL/source Git SHA:

- `cc178d3317edc9890e957175f0c5a5d6d8e06c07`

Validation result:

- `make hardware-regression CODEC=vvc`: PASS.
- Public `sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- Public `sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
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
| Main Yosys elapsed time (s) | 494.40 s | 528.00 s | +33.60 s |
| Runner-observed peak child RSS (MiB) | 2303.87 MiB | 2462.58 MiB | +158.71 MiB |
| Topological path length | 55 | 54 | -1 |
| Flattened cells | 164059 | 180301 | +16242 |
| Estimated LCs | 62294 | 66358 | +4064 |
| CARRY4 | 4178 | 4169 | -9 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 18467 | 20007 | +1540 |
| FDPE | 314 | 314 | +0 |
| FDRE | 23912 | 28536 | +4624 |
| FDSE | 8 | 8 | +0 |
| LUT1 | 1607 | 1819 | +212 |
| LUT2 | 23549 | 23647 | +98 |
| LUT3 | 7850 | 9067 | +1217 |
| LUT4 | 6577 | 8055 | +1478 |
| LUT5 | 9034 | 9167 | +133 |
| LUT6 | 34272 | 36806 | +2534 |
| MUXF7 | 9320 | 11669 | +2349 |
| MUXF8 | 1859 | 2406 | +547 |
| RAMB36E1 | 9 | 9 | +0 |

Critical-path summary:

- Longest topological path in `ff_vvc_encoder`: length 54.
- Reported limiter: CABAC syntax frontend IBC MVD absolute-value / EG1 prefix path.

Notes:

- The CABAC throughput pass improved VVC simulation cycles materially while
  keeping the same critical-path family and reducing topological path length by
  one node. The added bounded FIFOs and overlap staging increased FF/LUT area and
  synthesis runtime, so future passes should recover area once the throughput
  shape is stable.
- The VVC output byte bubble rate remains high because the 4:2:0 bitstreams are small and the CABAC/residual path, not AXI write readiness, limits throughput.
- The reported area is still too large for the Z7-10 fabric; this remains a pressure target for incremental optimization rather than a fit target.
