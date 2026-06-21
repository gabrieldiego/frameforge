# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-21 Palette Index RAM Storage

Measured after moving the AV2 4:4:4 palette index table from a 64-entry
flip-flop bank into `ff_sync_block_ram_1r1w`. The analyzer still presents the
same query handshake and emits the same symbol schedule, but the wide per-leaf
index storage is no longer synthesized as registers.

Baseline and current sources:

- Baseline Vivado report Git SHA:
  `1d39efb13aca62789800ab3f21cb4f1ba9471d19`.
- Baseline validated RTL/source Git SHA:
  `28df2e21c2a44d6ba00e819616a10fb1b9686bf1`.
- Current validated RTL/source Git SHA:
  `113d850538d22e12dd5e9a29ed54ab0f25e6aa67`.
- Baseline mode: AV2 palette analyzer with stale state removed and terminal
  predictor-edge storage collapsed, but with the 64-entry palette-index table
  still held in flip-flops.
- Current mode: same codec behavior, with one 192-bit palette-index RAM word
  per 8x8 leaf.
- Delta columns compare against the previous documented AV2 Vivado/Yosys
  checkpoint.

Validation result:

- `screenshot-sweep-444`: PASS, 64/64 vectors, strict SW/RTL bitstream parity
  and SW/RTL/reference-decoder lossless reconstruction parity.
- `screenshot-multictu-444`: PASS, 10/10 vectors, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder lossless reconstruction parity.
- `racehorses-sweep-420` limited 8x8 smoke: PASS, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder reconstruction parity.
- Direct `screenshot_640_sweep_16x16_1f_yuv444p8.yuv` validation: PASS.
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
| Wrapper elapsed time | 568.9 s |
| `synth_design` elapsed time | 08:36 |
| Runner-observed peak child RSS | 2653.18 MiB |
| Vivado log peak memory | 3282.89 MB |
| Vivado PSS peak, overall | 9302.14 MB |
| Vivado PSS peak, main process | 2623.36 MB |
| Vivado PSS peak, forked workers | 7581.71 MB |
| WNS at 25 MHz | +6.574 ns |
| TNS at 25 MHz | 0.000 ns |
| Setup failing endpoints | 0 |
| Worst hold slack | +0.043 ns |
| Worst pulse-width slack | +18.750 ns |
| Slice LUTs | 22033 / 17600 (125.19%) |
| LUT as logic | 21993 / 17600 (124.96%) |
| LUT as distributed RAM | 40 / 6000 (0.67%) |
| Slice registers | 21227 / 35200 (60.30%) |
| Block RAM tiles | 30 / 60 (50.00%) |
| DSPs | 10 / 80 (12.50%) |
| Bonded IOBs | 482 / 100 (482.00%) |

Yosys synthesis check:

| Metric | Result |
|---|---:|
| Main Yosys elapsed time | 228.9 s |
| Runner-observed peak child RSS | 1422.55 MiB |
| Flattened cells | 69696 |
| Estimated LCs | 24686 |
| RAMB36E1 | 30 |
| RAM32M | 10 |
| DSP48E1 | 13 |

Delta from the previous documented AV2 Vivado checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| `synth_design` elapsed time | 09:24 | 08:36 | -0:48 |
| Full wrapper elapsed time | 621.0 s | 568.9 s | -52.1 s |
| Runner-observed peak child RSS | 2712.54 MiB | 2653.18 MiB | -59.36 MiB |
| Vivado log peak memory | 3339.66 MB | 3282.89 MB | -56.77 MB |
| Vivado PSS peak, overall | 9213.81 MB | 9302.14 MB | +88.33 MB |
| Vivado PSS peak, main process | 2695.28 MB | 2623.36 MB | -71.92 MB |
| Vivado PSS peak, forked workers | 7475.53 MB | 7581.71 MB | +106.18 MB |
| WNS at 25 MHz | +8.023 ns | +6.574 ns | -1.449 ns |
| TNS at 25 MHz | 0.000 ns | 0.000 ns | +0.000 ns |
| Setup failing endpoints | 0 | 0 | +0 |
| Worst hold slack | +0.043 ns | +0.043 ns | +0.000 ns |
| Slice LUTs | 25359 | 22033 | -3326 |
| LUT as logic | 25319 | 21993 | -3326 |
| LUT as distributed RAM | 40 | 40 | +0 |
| Slice registers | 33627 | 21227 | -12400 |
| Block RAM tiles | 27 | 30 | +3 |
| DSPs | 10 | 10 | +0 |
| Bonded IOBs | 482 | 482 | +0 |

Delta from the previous documented AV2 Yosys checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time | 308.5 s | 228.9 s | -79.6 s |
| Runner-observed peak child RSS | 1583.96 MiB | 1422.55 MiB | -161.41 MiB |
| Flattened cells | 88219 | 69696 | -18523 |
| Estimated LCs | 30223 | 24686 | -5537 |
| RAMB36E1 | 27 | 30 | +3 |
| RAM32M | 10 | 10 | +0 |
| DSP48E1 | 13 | 13 | +0 |

Current worst path:

- Source: `control_regs/chroma_format_idc_reg[0]/C`.
- Destination: `low_q_reg[39]/D`.
- Data path delay: 33.274 ns, with 12.297 ns logic and 20.977 ns route.
- Logic levels: 44.
- The WNS margin reduced from the previous checkpoint but still comfortably
  meets the 25 MHz target. The control/register to range-coder path is now the
  next timing path to inspect if later feature work erodes this margin.

Bitrate and output-utilization impact:

| Vector set | Result | Bitrate delta | Cycle observation |
|---|---|---:|---|
| `screenshot-sweep-444` | 64/64 PASS | +0.0000 bpp (+0.00%) | output schedule unchanged; current avg 14.795 cycles/input pixel |
| `screenshot-multictu-444` | 10/10 PASS | +0.0000 bpp (+0.00%) | output schedule unchanged; current avg 12.118 cycles/input pixel |
| `racehorses-sweep-420` 8x8 smoke | PASS | +0.0000 bpp (+0.00%) | unchanged in direct smoke |

Notes:

- The design still meets the 25 MHz Z7-10 Vivado synthesis timing target.
- The area improvement is meaningful in both tools: Vivado reports 3326 fewer
  LUTs and 12400 fewer registers; Yosys reports 18523 fewer flattened cells
  and 5537 fewer estimated LCs.
- The optimization trades three additional block RAM tiles for a large register
  and LUT reduction. Vivado and Yosys elapsed time also improved.
- The design still exceeds the small Z7-10 fabric capacity in LUTs and I/O
  count, so this board remains a pressure target rather than a fit target for
  the full encoder.
