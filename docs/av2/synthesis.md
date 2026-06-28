# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## AV2 analyzer overlap and IBC safety checkpoint

Baseline and current sources:

- Baseline Git SHA: `509b74f7670b9bfff61209f0779c12e256b00f07`
- Current validated source Git SHA: `8b06ee49bb8aa6944afcad0101f0867f84dfa49a`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/reference-decoder checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: PASS at 25 MHz target, WNS is positive.

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
| Main Yosys elapsed time (s) | 579.50 s | 559.20 s | -20.30 s |
| Runner-observed peak child RSS (MiB) | 2074.95 MiB | 1917.12 MiB | -157.83 MiB |
| Topological path length | 120 | 122 | +2 |
| Flattened cells | 123021 | 116638 | -6383 |
| Estimated LCs | 55926 | 52585 | -3341 |
| CARRY4 | 3815 | 3819 | +4 |
| DSP48E1 | 1 | 1 | +0 |
| FDCE | 6382 | 6562 | +180 |
| FDPE | 92 | 78 | -14 |
| FDRE | 23019 | 20939 | -2080 |
| FDSE | 132 | 132 | +0 |
| LUT1 | 981 | 827 | -154 |
| LUT2 | 15006 | 14697 | -309 |
| LUT3 | 12231 | 11090 | -1141 |
| LUT4 | 7583 | 7176 | -407 |
| LUT5 | 10142 | 9780 | -362 |
| LUT6 | 25970 | 24539 | -1431 |
| MUXF7 | 6140 | 5486 | -654 |
| MUXF8 | 1434 | 1310 | -124 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest Yosys topological path in `ff_av2_encoder`: length 122.
- Reported limiter: input FIFO data selection feeding the 4:4:4
  palette-color update path in `ff_av2_palette_analyzer_444`.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.

Vivado synthesis configuration:

- command: `make synth-vivado CODEC=av2 SYNTH_DUT=av2-encoder SYNTH_TIMEOUT_SEC=1800 SYNTH_WARN_AFTER_SEC=600 SYNTH_VIVADO_MAX_THREADS=1 SYNTH_MEMORY_LIMIT_MB=4096`
- RTL top: `ff_av2_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target: 25 MHz
- max visible size: 1024x1024
- palette 4:4:4 support: enabled

Vivado synthesis and timing result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Vivado total elapsed time (s) | n/a | 1127.00 s | n/a |
| Vivado synth_design elapsed time (s) | n/a | 1024.00 s | n/a |
| Vivado synth_design peak memory (MiB) | n/a | 3343.42 MiB | n/a |
| Vivado WNS (ns) | n/a | 2.160 ns | n/a |
| Vivado WHS (ns) | n/a | 0.043 ns | n/a |
| Vivado critical data path delay (ns) | n/a | 37.689 ns | n/a |
| Vivado critical logic levels | n/a | 51 | n/a |
| Vivado Slice LUTs | n/a | 59036 | n/a |
| Vivado Slice Registers | n/a | 27320 | n/a |
| Vivado Block RAM Tiles | n/a | 30 | n/a |
| Vivado DSPs | n/a | 0 | n/a |

Vivado critical-path summary:

- Setup timing met at 25 MHz with positive WNS.
- Current critical path is route-dominated inside the AV2 palette analyzer,
  from `input_sample_fifo/data_q_reg` into `palette_color_q`.

Notes:

- Bitrate deltas reflect the refreshed validation logs for this checkpoint;
  output-utilization deltas include any RTL-cycle changes from the current
  RTL updates.
