# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-21 Palette Analyzer State Area Cut

Measured after removing stale AV2 palette-analyzer state and replacing the
unused 64-entry luma predictor-edge register banks with a single terminal
predictor pair. The current H/V luma intra selector only uses the terminal 8x8
leaf, so the old per-block predictor storage was area-only state. Bitstreams
and output schedules are unchanged.

Baseline and current sources:

- Baseline Vivado report Git SHA:
  `307fcff6555b2c834d69a09d451e7dd2b01519c6`.
- Baseline validated RTL/source Git SHA:
  `6de4af0ca0d44b5f1288bee89311ee37ff3de790`.
- Current validated RTL/source Git SHA:
  `28df2e21c2a44d6ba00e819616a10fb1b9686bf1`.
- Baseline mode: AV2 local IBC, palette 4:4:4, lossy 4:2:0 residual, payload
  byte buffer inferred as block RAM, and a registered BDPCM TXB launch stage.
- Current mode: same codec behavior, with stale palette-analyzer counters,
  palette-cache size storage, and per-block H/V predictor-edge banks removed.
- Delta columns compare against the previous documented AV2 Vivado/Yosys
  checkpoint.

Validation result:

- `screenshot-sweep-444`: PASS, 64/64 vectors, strict SW/RTL bitstream parity
  and SW/RTL/reference-decoder lossless reconstruction parity.
- `screenshot-multictu-444`: PASS, 10/10 vectors, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder lossless reconstruction parity.
- `racehorses-sweep-420` limited 8x8 smoke: PASS, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder reconstruction parity.
- Direct `screenshot_640_sweep_16x16_1f_yuv444p8.yuv` and
  `screenshot_640_sweep_24x24_1f_yuv444p8.yuv` validations: PASS.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis: PASS at 25 MHz with zero setup, hold, or pulse-width
  failing endpoints.

Vivado synthesis configuration:

- command: `make synth-vivado CODEC=av2 SYNTH_DUT=av2-encoder
  SYNTH_TIMEOUT_SEC=1800 SYNTH_WARN_AFTER_SEC=300 SYNTH_MEMORY_LIMIT_MB=0`
- Vivado version: 2025.2.
- RTL top: `ff_av2_encoder`.
- board/device: Arty Z7-10, `xc7z010clg400-1`.
- clock constraint: 25 MHz (`40.000 ns` period), read from XDC before
  `synth_design`.
- Vivado synthesis directive: `Default`.
- Vivado retiming: disabled.
- max visible size: 1024x1024.
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled,
  lossy 4:2:0 residual enabled.

Current Vivado synthesis result:

| Metric | Result |
|---|---:|
| Wrapper elapsed time | 621.0 s |
| `synth_design` elapsed time | 09:24 |
| Runner-observed peak child RSS | 2712.54 MiB |
| Vivado log peak memory | 3339.66 MB |
| Vivado PSS peak, overall | 9213.81 MB |
| Vivado PSS peak, main process | 2695.28 MB |
| Vivado PSS peak, forked workers | 7475.53 MB |
| WNS at 25 MHz | +8.023 ns |
| TNS at 25 MHz | 0.000 ns |
| Setup failing endpoints | 0 |
| Worst hold slack | +0.043 ns |
| Worst pulse-width slack | +18.750 ns |
| Slice LUTs | 25359 / 17600 (144.09%) |
| LUT as logic | 25319 / 17600 (143.86%) |
| LUT as distributed RAM | 40 / 6000 (0.67%) |
| Slice registers | 33627 / 35200 (95.53%) |
| Block RAM tiles | 27 / 60 (45.00%) |
| DSPs | 10 / 80 (12.50%) |
| Bonded IOBs | 482 / 100 (482.00%) |

Yosys synthesis check:

| Metric | Result |
|---|---:|
| Main Yosys elapsed time | 308.5 s |
| Runner-observed peak child RSS | 1583.96 MiB |
| Flattened cells | 88219 |
| Estimated LCs | 30223 |
| RAMB36E1 | 27 |
| RAM32M | 10 |
| DSP48E1 | 13 |

Delta from the previous documented AV2 Vivado checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| `synth_design` elapsed time | 07:38 | 09:24 | +1:46 |
| Full wrapper elapsed time | 520.2 s | 621.0 s | +100.8 s |
| Runner-observed peak child RSS | 2580.86 MiB | 2712.54 MiB | +131.68 MiB |
| Vivado log peak memory | 3213.89 MB | 3339.66 MB | +125.77 MB |
| Vivado PSS peak, overall | 9299.35 MB | 9213.81 MB | -85.54 MB |
| Vivado PSS peak, main process | 2565.17 MB | 2695.28 MB | +130.11 MB |
| Vivado PSS peak, forked workers | 7548.34 MB | 7475.53 MB | -72.81 MB |
| WNS at 25 MHz | +6.763 ns | +8.023 ns | +1.260 ns |
| TNS at 25 MHz | 0.000 ns | 0.000 ns | +0.000 ns |
| Setup failing endpoints | 0 | 0 | +0 |
| Worst hold slack | +0.043 ns | +0.043 ns | +0.000 ns |
| Slice LUTs | 27165 | 25359 | -1806 |
| LUT as logic | 27125 | 25319 | -1806 |
| LUT as distributed RAM | 40 | 40 | +0 |
| Slice registers | 41532 | 33627 | -7905 |
| Block RAM tiles | 27 | 27 | +0 |
| DSPs | 10 | 10 | +0 |
| Bonded IOBs | 482 | 482 | +0 |

Delta from the previous documented AV2 Yosys checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time | 331.0 s | 308.5 s | -22.5 s |
| Runner-observed peak child RSS | 1600.65 MiB | 1583.96 MiB | -16.69 MiB |
| Flattened cells | 97656 | 88219 | -9437 |
| Estimated LCs | 32752 | 30223 | -2529 |
| RAMB36E1 | 27 | 27 | +0 |
| RAM32M | 10 | 10 | +0 |
| DSP48E1 | 13 | 13 | +0 |

Current worst path:

- Source: `palette_col_q_reg[0]/C`.
- Destination: `low_q_reg[54]/D`.
- Data path delay: 31.825 ns, with 11.216 ns logic and 20.609 ns route.
- Logic levels: 37.
- The old BDPCM sample-to-context path remains off the critical path. The new
  worst path runs through palette index/range logic into the range-coder
  `low_q` update, making palette query/range simplification the next natural
  timing target.

Bitrate and output-utilization impact:

| Vector set | Result | Bitrate delta | Cycle observation |
|---|---|---:|---|
| `screenshot-sweep-444` | 64/64 PASS | +0.0000 bpp (+0.00%) | current avg 14.793 cycles/input pixel |
| `screenshot-multictu-444` | 10/10 PASS | +0.0000 bpp (+0.00%) | current avg 12.126 cycles/input pixel |
| `racehorses-sweep-420` 8x8 smoke | PASS | +0.0000 bpp (+0.00%) | unchanged in direct smoke |

Notes:

- The design still meets the 25 MHz Z7-10 Vivado synthesis timing target.
- The area improvement is meaningful in both tools: Vivado reports 1806 fewer
  LUTs and 7905 fewer registers; Yosys reports 9437 fewer flattened cells and
  2529 fewer estimated LCs.
- Vivado runtime and main-process memory increased, so synthesis time remains
  a metric to watch even when the resulting hardware improves.
- The design still exceeds the small Z7-10 fabric capacity in LUTs and I/O
  count, so this board remains a pressure target rather than a fit target for
  the full encoder.
