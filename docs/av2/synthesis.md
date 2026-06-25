# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-25 AV2 4:2:0 Bubble Rate Optimization

Baseline and current sources:

- Baseline Git SHA: `31bb9321589844a4615d8dd87fe96ef6b54f43ed`
- Current validated source Git SHA: `34e1dca8f313dd433452ca27fb81d858d90e1617`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity.
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
| Main Yosys elapsed time (s) | 501.70 s | 518.60 s | +16.90 s |
| Runner-observed peak child RSS (MiB) | 1913.59 MiB | 1933.59 MiB | +20.00 MiB |
| Topological path length | 120 | 120 | +0 |
| Flattened cells | 114106 | 116915 | +2809 |
| Estimated LCs | 53009 | 55189 | +2180 |
| CARRY4 | 3739 | 3739 | +0 |
| DSP48E1 | 1 | 1 | +0 |
| FDCE | 5163 | 5163 | +0 |
| FDPE | 92 | 92 | +0 |
| FDRE | 22907 | 22907 | +0 |
| FDSE | 132 | 132 | +0 |
| LUT1 | 853 | 830 | -23 |
| LUT2 | 13856 | 14075 | +219 |
| LUT3 | 11952 | 12301 | +349 |
| LUT4 | 6938 | 7195 | +257 |
| LUT5 | 10047 | 10414 | +367 |
| LUT6 | 24072 | 25279 | +1207 |
| MUXF7 | 4611 | 4795 | +184 |
| MUXF8 | 1068 | 1184 | +116 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest Yosys topological path in `ff_av2_encoder`: length 120.
- Reported limiter: input FIFO data selection feeding the 4:4:4
  palette-color update path in `ff_av2_palette_analyzer_444`.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.
- The earlier multiplier and chroma sign-lookahead paths no longer dominate
  the synthesis reports.

Vivado synthesis and timing result:

- Not rerun for this checkpoint; use the previous committed report as the
  latest Vivado timing reference.

Notes:

- Current Yosys critical path remains in the AV2 palette analyzer, from the
  input sample FIFO selection into the palette-color update path.
- Bitrate deltas reflect the refreshed validation logs for this checkpoint;
  output-utilization deltas include any RTL-cycle changes from the current
  IBC and entropy-path updates.
