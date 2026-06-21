# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-21 BDPCM Launch Pipeline Timing Cut

Measured after inserting a one-cycle launch pipeline stage in the AV2 BDPCM
TXB symbolizer. Nonzero 4x4 TXBs now register transformed levels first, then
derive the AV2 v1.0.0 Section 5.20.7.27 EOB, coefficient-context, and
base-range tables from the registered levels. The bitstream is unchanged, but
the old sample-to-context path is no longer the Vivado critical path.

Baseline and current sources:

- Baseline Vivado report Git SHA:
  `243c3f491e3f3fef66a4b3a534dfe8ed8af9b949`.
- Baseline validated RTL/source Git SHA:
  `ed53f2e953f2aa5a84b977e5e7ed4ee47f6fd765`.
- Current validated RTL/source Git SHA:
  `6de4af0ca0d44b5f1288bee89311ee37ff3de790`.
- Baseline mode: AV2 local IBC, palette 4:4:4, lossy 4:2:0 residual, and the
  payload byte buffer inferred as block RAM through `ff_sync_block_ram_1r1w`.
- Current mode: same codec behavior, with a registered BDPCM TXB launch stage
  before EOB/context/base-range derivation.
- Delta columns compare against the previous documented AV2 Vivado checkpoint.

Validation result:

- `racehorses-sweep-420` limited 8x8 smoke: PASS, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder reconstruction parity.
- `screenshot-sweep-444` limited 8x8 smoke: PASS, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder lossless reconstruction parity.
- Direct `screenshot_640_sweep_16x16_1f_yuv444p8.yuv` validation: PASS,
  strict SW/RTL bitstream parity and lossless reconstruction parity.
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
| Wrapper elapsed time | 520.2 s |
| `synth_design` elapsed time | 07:38 |
| Runner-observed peak child RSS | 2580.86 MiB |
| Vivado log peak memory | 3213.89 MB |
| Vivado PSS peak, overall | 9299.35 MB |
| Vivado PSS peak, main process | 2565.17 MB |
| Vivado PSS peak, forked workers | 7548.34 MB |
| WNS at 25 MHz | +6.763 ns |
| TNS at 25 MHz | 0.000 ns |
| Setup failing endpoints | 0 |
| Worst hold slack | +0.043 ns |
| Slice LUTs | 27165 / 17600 (154.35%) |
| LUT as logic | 27125 / 17600 (154.12%) |
| LUT as distributed RAM | 40 / 6000 (0.67%) |
| Slice registers | 41532 / 35200 (117.99%) |
| Block RAM tiles | 27 / 60 (45.00%) |
| DSPs | 10 / 80 (12.50%) |
| Bonded IOBs | 482 / 100 (482.00%) |

Yosys synthesis check:

| Metric | Result |
|---|---:|
| Main Yosys elapsed time | 331.0 s |
| Runner-observed peak child RSS | 1600.65 MiB |
| Flattened cells | 97656 |
| Estimated LCs | 32752 |
| RAMB36E1 | 27 |
| RAM32M | 10 |
| DSP48E1 | 13 |

Delta from the previous documented AV2 Vivado checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| `synth_design` elapsed time | 07:01 | 07:38 | +0:37 |
| Full wrapper elapsed time | 487.0 s | 520.2 s | +33.2 s |
| Runner-observed peak child RSS | 2613.69 MiB | 2580.86 MiB | -32.83 MiB |
| Vivado log peak memory | 3244.88 MB | 3213.89 MB | -30.99 MB |
| Vivado PSS peak, overall | 9352.54 MB | 9299.35 MB | -53.19 MB |
| Vivado PSS peak, main process | 2596.28 MB | 2565.17 MB | -31.11 MB |
| Vivado PSS peak, forked workers | 7596.98 MB | 7548.34 MB | -48.64 MB |
| WNS at 25 MHz | +3.372 ns | +6.763 ns | +3.391 ns |
| TNS at 25 MHz | 0.000 ns | 0.000 ns | +0.000 ns |
| Setup failing endpoints | 0 | 0 | +0 |
| Worst hold slack | +0.043 ns | +0.043 ns | +0.000 ns |
| Slice LUTs | 27675 | 27165 | -510 |
| LUT as logic | 27635 | 27125 | -510 |
| LUT as distributed RAM | 40 | 40 | +0 |
| Slice registers | 41519 | 41532 | +13 |
| Block RAM tiles | 27 | 27 | +0 |
| DSPs | 10 | 10 | +0 |
| Bonded IOBs | 482 | 482 | +0 |

Delta from the previous documented AV2 Yosys checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time | 315.8 s | 331.0 s | +15.2 s |
| Runner-observed peak child RSS | 1632.57 MiB | 1600.65 MiB | -31.92 MiB |
| Flattened cells | 98386 | 97656 | -730 |
| Estimated LCs | 33157 | 32752 | -405 |
| RAMB36E1 | 27 | 27 | +0 |
| RAM32M | 10 | 10 | +0 |
| DSP48E1 | 13 | 13 | +0 |

Current worst path:

- Source: `control_regs/chroma_format_idc_reg[0]/C`.
- Destination: `low_q_reg[14]/D`.
- Data path delay: 33.085 ns, with 11.814 ns logic and 21.271 ns route.
- Logic levels: 42.
- The old BDPCM sample-to-context path is no longer the critical path. The
  current path runs through luma fetch, palette residual selection, and the
  range-coder `low_q` update.

Output-utilization smoke impact:

| Vector | Bits | Baseline cycles | Current cycles | Baseline util | Current util | Delta |
|---|---:|---:|---:|---:|---:|---:|
| `screenshot_640_sweep_8x8_1f_yuv444p8.yuv` | 344 | 826 | 834 | 0.052 | 0.052 | +8 cycles |
| `screenshot_640_sweep_16x16_1f_yuv444p8.yuv` | 4616 | 5340 | 5380 | 0.108 | 0.107 | +40 cycles |
| `racehorses_crop_8x8_1f_yuv420p8.yuv` | 304 | 591 | 591 | 0.064 | 0.064 | +0 cycles |

Notes:

- The design still meets the 25 MHz Z7-10 Vivado synthesis timing target.
- This is primarily a timing and area improvement. The small output-utilization
  penalty on nonzero 4:4:4 TXBs is the expected cost of the added launch
  register stage.
- The design still exceeds the small Z7-10 fabric capacity in LUTs, registers,
  and I/O count, so this board remains a pressure target rather than a fit
  target for the full encoder.
