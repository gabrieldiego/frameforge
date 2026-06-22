# AV2 Synthesis Baseline

This file records the latest AV2-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-22 Shared AXI/FIFO Utilization Pass

Validated RTL/source Git SHA:

- `3945b1bc67a20e5cfa2ccf8d05910ab8741deef0`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- Focused AV2 64x64 smoke after the timing fix: PASS.
- Yosys synthesis: PASS at 25 MHz metadata target.

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
| Main Yosys elapsed time (s) | 250.40 s | 244.40 s | -6.00 s |
| Runner-observed peak child RSS (MiB) | 1378.57 MiB | 1443.55 MiB | +64.98 MiB |
| Topological path length | 55 | 55 | +0 |
| Flattened cells | 69410 | 73599 | +4189 |
| Estimated LCs | 24586 | 26306 | +1720 |
| CARRY4 | n/a | 2648 | n/a |
| DSP48E1 | 13 | 13 | +0 |
| FDCE | n/a | 4742 | n/a |
| FDPE | n/a | 27 | n/a |
| FDRE | n/a | 18111 | n/a |
| FDSE | n/a | 129 | n/a |
| LUT1 | n/a | 682 | n/a |
| LUT2 | n/a | 7980 | n/a |
| LUT3 | n/a | 5646 | n/a |
| LUT4 | n/a | 4667 | n/a |
| LUT5 | n/a | 3189 | n/a |
| LUT6 | n/a | 12804 | n/a |
| MUXF7 | n/a | 4127 | n/a |
| MUXF8 | n/a | 786 | n/a |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest topological path in `ff_av2_encoder`: length 55.
- Reported limiter: palette analyzer row/control logic after the timing-safe registered chroma zero-TXB shortcut.

Notes:

- The first same-cycle chroma zero-TXB shortcut reduced cycles but pushed the Yosys topological path to 71; the kept version registers the zero shortcut and restores the path length to 55.
- Area increased versus the previous documented AV2 Yosys baseline, mainly from the shared input FIFO and added instrumentation/control. The critical path did not regress.
- Bubble rate remains above the requested 0.800 target, so the next optimization needs to address serialized codec phases rather than AXI write readiness.
