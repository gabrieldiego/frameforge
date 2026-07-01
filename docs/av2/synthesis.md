# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## Streamed entropy output

Baseline and current sources:

- Baseline Git SHA: `7383aee7b77230a85bdd86c5cf151008ba7de553`
- Current validated source Git SHA: `ccc1e283b43c5833c276605f1f583d9c1476f4b3`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/reference-decoder checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: not rerun for this checkpoint.

Yosys synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- RTL top: `ff_av2_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target metadata: 25 MHz
- max visible size: 1024x1024
- timeout/review thresholds: 900 seconds hard stop, 600 seconds review
- memory limit: 3072 MiB
- palette 4:4:4 support: enabled

Yosys synthesis result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time (s) | 629.20 s | 546.80 s | -82.40 s |
| Runner-observed peak child RSS (MiB) | 2453.74 MiB | 2445.40 MiB | -8.34 MiB |
| Topological path length | 122 | 124 | +2 |
| Flattened cells | 137782 | 135832 | -1950 |
| Estimated LCs | 65883 | 63438 | -2445 |
| CARRY4 | 3871 | 4022 | +151 |
| DSP48E1 | 2 | 2 | +0 |
| FDCE | 7714 | 7898 | +184 |
| FDPE | 78 | 78 | +0 |
| FDRE | 20565 | 20852 | +287 |
| FDSE | 133 | 133 | +0 |
| LUT1 | 1392 | 1188 | -204 |
| LUT2 | 16084 | 15759 | -325 |
| LUT3 | 13098 | 12455 | -643 |
| LUT4 | 9478 | 8685 | -793 |
| LUT5 | 12247 | 12188 | -59 |
| LUT6 | 31060 | 30110 | -950 |
| MUXF7 | 7875 | 8092 | +217 |
| MUXF8 | 1705 | 1864 | +159 |
| RAMB36E1 | 30 | 6 | -24 |
| RAM32M | 0 | 0 | +0 |

Critical-path summary:

- Longest Yosys topological path in `ff_av2_encoder`: length 124.
- Reported limiter: the top-level path begins at
  `ff_av2_chroma_bdpcm_symbolizer.scan_q[3]` and feeds the BDPCM scan-boundary
  compare in `rtl/av2/residual/ff_av2_chroma_bdpcm_symbolizer.sv`.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.

Vivado synthesis and timing result:

- Not rerun for this checkpoint; use the previous committed report as the
  latest Vivado timing reference.

Notes:

- The quality/bitrate report was not refreshed for this checkpoint because the
  encoded bitstreams remained byte-exact against the previous baseline.
- Output-utilization deltas include RTL-cycle changes from the streamed
  two-pass entropy-output path.
