# VVC Synthesis Baseline

This file records the latest VVC-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-22 CABAC Output Overlap Checkpoint

Baseline RTL/source Git SHA:

- `cc178d3317edc9890e957175f0c5a5d6d8e06c07`

Current RTL/source Git SHA:

- `e2fd88a0ebc7d05be240f48c61b2db9efad53023`

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
| Main Yosys elapsed time (s) | 528.00 s | 541.30 s | +13.30 s |
| Runner-observed peak child RSS (MiB) | 2462.58 MiB | 2498.41 MiB | +35.83 MiB |
| Topological path length | 54 | 54 | +0 |
| Flattened cells | 180301 | 181835 | +1534 |
| Estimated LCs | 66358 | 66242 | -116 |
| CARRY4 | 4169 | 4173 | +4 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 20007 | 20011 | +4 |
| FDPE | 314 | 314 | +0 |
| FDRE | 28536 | 31160 | +2624 |
| FDSE | 8 | 8 | +0 |
| LUT1 | 1819 | 1946 | +127 |
| LUT2 | 23647 | 22781 | -866 |
| LUT3 | 9067 | 9439 | +372 |
| LUT4 | 8055 | 8192 | +137 |
| LUT5 | 9167 | 9299 | +132 |
| LUT6 | 36806 | 36737 | -69 |
| MUXF7 | 11669 | 11201 | -468 |
| MUXF8 | 2406 | 1928 | -478 |
| RAMB36E1 | 9 | 9 | +0 |

Critical-path summary:

- Longest topological path in `ff_vvc_encoder`: length 54.
- Reported limiter: CABAC syntax frontend IBC MVD absolute-value / EG1 prefix path.

Notes:

- Direct CABAC byte handoff and post-write bypass-bin fusion reduce writer
  stalls. Source-symbol prefill overlaps CTU/palette symbol production with
  header emission before the CABAC payload is released.
- A deeper CABAC bin FIFO was evaluated but rejected for this checkpoint. It
  improved the 64x64 4:4:4 screenshot crop from 32982 to 32637 cycles, but
  raised flattened cells to 187546 and FDREs to 33208, so the committed
  checkpoint keeps the bin FIFO depth at 32.
- The VVC output byte bubble rate remains high because the 4:2:0 bitstreams
  are small and the CABAC/residual path, not AXI write readiness, limits
  throughput.
- The reported area is still too large for the Z7-10 fabric; this remains a pressure target for incremental optimization rather than a fit target.
