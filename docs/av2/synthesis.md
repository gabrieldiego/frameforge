# AV2 Synthesis Baseline

This file records the latest AV2-specific synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-25 AV2 Timing Cleanup Checkpoint

Baseline and current sources:

- Baseline Git SHA: `d5c8aea952cebba4cd835e6ddf94cdd1e26c7a47`
- Current validated source Git SHA: `48ba35795881b898d28fbd6de13cac61147ac108`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: PASS at 25 MHz target, WNS is positive.

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
| Main Yosys elapsed time (s) | 515.80 s | 438.60 s | -77.20 s |
| Runner-observed peak child RSS (MiB) | 1808.88 MiB | 1820.45 MiB | +11.57 MiB |
| Topological path length | 230 | 120 | -110 |
| Flattened cells | 103191 | 104877 | +1686 |
| Estimated LCs | 42880 | 43866 | +986 |
| CARRY4 | 3545 | 3660 | +115 |
| DSP48E1 | 15 | 1 | -14 |
| FDCE | 4889 | 5119 | +230 |
| FDPE | 93 | 92 | -1 |
| FDRE | 22797 | 22812 | +15 |
| FDSE | 131 | 132 | +1 |
| LUT1 | 926 | 742 | -184 |
| LUT2 | 13865 | 13717 | -148 |
| LUT3 | 9520 | 9925 | +405 |
| LUT4 | 6641 | 6146 | -495 |
| LUT5 | 5416 | 5868 | +452 |
| LUT6 | 21303 | 21927 | +624 |
| MUXF7 | 4456 | 4896 | +440 |
| MUXF8 | 1076 | 1245 | +169 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest Yosys topological path in `ff_av2_encoder`: length 120.
- Reported limiter: input FIFO data selection feeding the 4:4:4
  palette-color update path in `ff_av2_palette_analyzer_444`.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.
- The earlier multiplier and chroma sign-lookahead paths no longer dominate
  the synthesis reports.

Vivado synthesis configuration:

- command: `make synth-vivado CODEC=av2 SYNTH_DUT=av2-encoder SYNTH_TIMEOUT_SEC=1200 SYNTH_WARN_AFTER_SEC=300 SYNTH_VIVADO_MAX_THREADS=1 SYNTH_MEMORY_LIMIT_MB=4096`
- RTL top: `ff_av2_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target: 25 MHz
- max visible size: 1024x1024
- palette 4:4:4 support: enabled

Vivado synthesis and timing result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Vivado total elapsed time (s) | n/a | 868.00 s | n/a |
| Vivado synth_design elapsed time (s) | n/a | 787.00 s | n/a |
| Vivado synth_design peak memory (MiB) | n/a | 3095.78 MiB | n/a |
| Vivado WNS (ns) | n/a | 3.683 ns | n/a |
| Vivado WHS (ns) | n/a | 0.043 ns | n/a |
| Vivado critical data path delay (ns) | n/a | 36.166 ns | n/a |
| Vivado critical logic levels | n/a | 36 | n/a |
| Vivado Slice LUTs | n/a | 44502 | n/a |
| Vivado Slice Registers | n/a | 27635 | n/a |
| Vivado Block RAM Tiles | n/a | 30 | n/a |
| Vivado DSPs | n/a | 0 | n/a |

Vivado critical-path summary:

- Setup timing met at 25 MHz with positive WNS.
- Current critical path is route-dominated inside the AV2 palette analyzer,
  from `input_sample_fifo/data_q_reg` into `palette_color_q`.
- Vivado reports 0 DSP use after replacing the synthesis-visible multiply
  cones in the AV2/range-reader hot paths.

Notes:

- The frame reader now stages segment-origin row offsets and keeps the
  per-sample address path to local 64-row shift/add arithmetic.
- AV2 tile sample/count arithmetic and range-coder products are implemented
  as bounded shift/add logic rather than synthesis-visible multipliers.
- Chroma BDPCM sign emission returned to the one-sign-per-nonzero form used
  by the software model; the previous lookahead path was both fragile and
  a timing liability.
- Bitrate deltas are zero across the refreshed AV2 validation sets, so this
  checkpoint is a synthesis/timing cleanup rather than an encoder-algorithm
  change.
