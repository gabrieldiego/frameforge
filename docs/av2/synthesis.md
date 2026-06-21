# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-21 IBC Leaf-Order Decode Simplification

Measured after replacing the AV2 4:4:4 local IBC leaf-order decode table with
the equivalent structural bit permutation. The hash matcher still scans the
same fixed 8x8 leaf walk and emits the same decisions, but the 64-way decode
table is no longer present in the synthesized RTL.

Baseline and current sources:

- Baseline Vivado report Git SHA:
  `eeef80f49ae3c713e2b3f4f931d9976dc3a1660e`.
- Baseline validated RTL/source Git SHA:
  `113d850538d22e12dd5e9a29ed54ab0f25e6aa67`.
- Current validated RTL/source Git SHA:
  `874fb312adf735387f53551bcbed5254fdc98051`.
- Baseline mode: AV2 palette analyzer using block RAM for palette-index
  storage, with local IBC leaf-order mapping still implemented as a 64-way
  decode table.
- Current mode: same codec behavior, with the local IBC leaf-order mapping
  expressed as the structural row/column bit permutation.
- Delta columns compare against the previous documented AV2 Vivado/Yosys
  checkpoint.

Validation result:

- `screenshot-sweep-444`: PASS, 64/64 vectors, strict SW/RTL bitstream parity
  and SW/RTL/reference-decoder lossless reconstruction parity.
- `screenshot-multictu-444`: PASS, 10/10 vectors, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder lossless reconstruction parity.
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
| Wrapper elapsed time | 526.4 s |
| `synth_design` elapsed time | 07:49 |
| Runner-observed peak child RSS | 2658.08 MiB |
| Vivado log peak memory | 3276.79 MB |
| Vivado PSS peak, overall | 9303.55 MB |
| Vivado PSS peak, main process | 2627.85 MB |
| Vivado PSS peak, forked workers | 7584.20 MB |
| WNS at 25 MHz | +6.574 ns |
| TNS at 25 MHz | 0.000 ns |
| Setup failing endpoints | 0 |
| Worst hold slack | +0.043 ns |
| Worst pulse-width slack | +18.750 ns |
| Slice LUTs | 21986 / 17600 (124.92%) |
| LUT as logic | 21946 / 17600 (124.69%) |
| LUT as distributed RAM | 40 / 6000 (0.67%) |
| Slice registers | 21224 / 35200 (60.30%) |
| Block RAM tiles | 30 / 60 (50.00%) |
| DSPs | 10 / 80 (12.50%) |
| Bonded IOBs | 482 / 100 (482.00%) |

Yosys synthesis check:

| Metric | Result |
|---|---:|
| Main Yosys elapsed time | 235.5 s |
| Runner-observed peak child RSS | 1364.19 MiB |
| Flattened cells | 69688 |
| Estimated LCs | 24760 |
| RAMB36E1 | 30 |
| RAM32M | 10 |
| DSP48E1 | 13 |

Delta from the previous documented AV2 Vivado checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| `synth_design` elapsed time | 08:36 | 07:49 | -0:47 |
| Full wrapper elapsed time | 568.9 s | 526.4 s | -42.5 s |
| Runner-observed peak child RSS | 2653.18 MiB | 2658.08 MiB | +4.90 MiB |
| Vivado log peak memory | 3282.89 MB | 3276.79 MB | -6.10 MB |
| Vivado PSS peak, overall | 9302.14 MB | 9303.55 MB | +1.41 MB |
| Vivado PSS peak, main process | 2623.36 MB | 2627.85 MB | +4.49 MB |
| Vivado PSS peak, forked workers | 7581.71 MB | 7584.20 MB | +2.49 MB |
| WNS at 25 MHz | +6.574 ns | +6.574 ns | +0.000 ns |
| TNS at 25 MHz | 0.000 ns | 0.000 ns | +0.000 ns |
| Setup failing endpoints | 0 | 0 | +0 |
| Worst hold slack | +0.043 ns | +0.043 ns | +0.000 ns |
| Slice LUTs | 22033 | 21986 | -47 |
| LUT as logic | 21993 | 21946 | -47 |
| LUT as distributed RAM | 40 | 40 | +0 |
| Slice registers | 21227 | 21224 | -3 |
| Block RAM tiles | 30 | 30 | +0 |
| DSPs | 10 | 10 | +0 |
| Bonded IOBs | 482 | 482 | +0 |

Delta from the previous documented AV2 Yosys checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time | 228.9 s | 235.5 s | +6.6 s |
| Runner-observed peak child RSS | 1422.55 MiB | 1364.19 MiB | -58.36 MiB |
| Flattened cells | 69696 | 69688 | -8 |
| Estimated LCs | 24686 | 24760 | +74 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |
| DSP48E1 | 13 | 13 | +0 |

Current worst path:

- Source: `control_regs/chroma_format_idc_reg[0]/C`.
- Destination: `low_q_reg[39]/D`.
- Data path delay: 33.274 ns, with 12.297 ns logic and 20.977 ns route.
- Logic levels: 44.
- The WNS margin is unchanged from the previous checkpoint and still
  comfortably meets the 25 MHz target. The control/register to range-coder path
  remains the next timing path to inspect if later feature work erodes this
  margin.

Bitrate and output-utilization impact:

| Vector set | Result | Bitrate delta | Cycle observation |
|---|---|---:|---|
| `screenshot-sweep-444` | 64/64 PASS | +0.0000 bpp (+0.00%) | output schedule unchanged; current avg 14.795 cycles/input pixel |
| `screenshot-multictu-444` | 10/10 PASS | +0.0000 bpp (+0.00%) | output schedule unchanged; current avg 12.118 cycles/input pixel |

Notes:

- The design still meets the 25 MHz Z7-10 Vivado synthesis timing target.
- The RTL cleanup is deliberately small. Vivado reports 47 fewer LUTs and
  three fewer registers with unchanged WNS, BRAM, DSP, and I/O counts.
- Yosys reports eight fewer flattened cells and 58.36 MiB lower peak child RSS,
  while its estimated LC count moved up by 74. Treat the Vivado result as the
  stronger area signal for this FPGA-targeted pass.
- The output-utilization counters stayed baseline on every validated 4:4:4
  vector, so this change does not worsen the current bubble profile.
- The design still exceeds the small Z7-10 fabric capacity in LUTs and I/O
  count, so this board remains a pressure target rather than a fit target for
  the full encoder.
