# AV2 Synthesis Baseline

This file records the latest AV2-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-24 Residual Packet Packing Checkpoint

Baseline and current sources:

- Baseline Git SHA: `a5d5f94c7c73b42920f9405bc41d6c14244de12e`
- Current validated source Git SHA: `d5c8aea952cebba4cd835e6ddf94cdd1e26c7a47`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: FAIL, code 139 during timing optimization before WNS/TNS reporting.

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
| Main Yosys elapsed time (s) | 368.20 s | 515.80 s | +147.60 s |
| Runner-observed peak child RSS (MiB) | 1734.85 MiB | 1808.88 MiB | +74.03 MiB |
| Topological path length | 229 | 230 | +1 |
| Flattened cells | 93311 | 103191 | +9880 |
| Estimated LCs | 37032 | 42880 | +5848 |
| CARRY4 | 2797 | 3545 | +748 |
| DSP48E1 | 15 | 15 | +0 |
| FDCE | 4795 | 4889 | +94 |
| FDPE | 27 | 93 | +66 |
| FDRE | 22674 | 22797 | +123 |
| FDSE | 129 | 131 | +2 |
| LUT1 | 682 | 926 | +244 |
| LUT2 | 11886 | 13865 | +1979 |
| LUT3 | 7450 | 9520 | +2070 |
| LUT4 | 5412 | 6641 | +1229 |
| LUT5 | 5250 | 5416 | +166 |
| LUT6 | 18920 | 21303 | +2383 |
| MUXF7 | 4187 | 4456 | +269 |
| MUXF8 | 949 | 1076 | +127 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest topological path in `ff_av2_encoder`: length 230.
- Reported limiter: input FIFO data selection feeding the 4:4:4 packet
  palette insertion path in `ff_av2_palette_analyzer_444`, through the
  packet palette-color insertion chain into `palette_color_q`.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.
- The residual symbolizer no longer appears on the longest Yosys
  topological path after packing sign and high-range literal bypass runs.

Vivado timing attempt:

- Command: `make synth-vivado CODEC=av2 SYNTH_DUT=av2-encoder SYNTH_TIMEOUT_SEC=2400 SYNTH_WARN_AFTER_SEC=300`.
- Default two-thread run exited with code 139 after 496.7 seconds during
  timing optimization, before timing summary reports were written.
- Single-thread retry (`SYNTH_VIVADO_MAX_THREADS=1`) exited with code 139
  after 600.1 seconds at the same phase.
- Existing `vivado_timing_summary.rpt` artifacts in `synth/out` are from
  an older run and were not used for this checkpoint.

Notes:

- Chroma residual signs are grouped up to four adjacent low-range signs,
  and literal coefficient sign plus high-range bypass bits are emitted as
  one range-coder operation when the combined width fits the literal port.
- This improves simulation throughput without changing SW/RTL bitstream
  parity or reconstruction checksums.
- Remaining Yosys critical path pressure is now dominated by packet palette
  insertion rather than the residual bypass packing logic.
