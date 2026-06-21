# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-21 Payload BRAM Area Optimization

Measured after moving the AV2 payload byte buffer out of the main encoder FSM
array and into an explicit synchronous 1-write/1-read block-RAM wrapper. The
bitstream is unchanged, but Vivado now maps the 32 KiB payload store to BRAM
instead of distributed RAM.

Baseline and current sources:

- Baseline Vivado report Git SHA:
  `3d2b2303cd67599afa6df6de64e86f6dc2f28efd`.
- Current validated RTL/source Git SHA:
  `ed53f2e953f2aa5a84b977e5e7ed4ee47f6fd765`.
- Baseline mode: AV2 local IBC, palette 4:4:4, lossy 4:2:0 residual, and the
  previous payload byte buffer inferred by Vivado as distributed RAM.
- Current mode: same codec behavior, with the payload byte buffer inferred as
  block RAM through `ff_sync_block_ram_1r1w`.
- Delta columns compare against the previous documented AV2 Vivado checkpoint.

Validation result:

- `racehorses-sweep-420` limited 8x8 smoke: PASS, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder reconstruction parity.
- `screenshot-sweep-444` limited 8x8 smoke: PASS, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder lossless reconstruction parity.
- Direct `screenshot_640_sweep_16x16_1f_yuv444p8.yuv` validation: PASS,
  strict SW/RTL bitstream parity and lossless reconstruction parity. Output
  utilization stayed at `0.108`, matching the previous detailed utilization
  table for this vector.
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
| Wrapper elapsed time | 487.0 s |
| `synth_design` elapsed time | 07:01 |
| Runner-observed peak child RSS | 2613.69 MiB |
| Vivado log peak memory | 3244.88 MB |
| Vivado PSS peak, overall | 9352.54 MB |
| Vivado PSS peak, main process | 2596.28 MB |
| Vivado PSS peak, forked workers | 7596.98 MB |
| WNS at 25 MHz | +3.372 ns |
| TNS at 25 MHz | 0.000 ns |
| Setup failing endpoints | 0 |
| Worst hold slack | +0.043 ns |
| Slice LUTs | 27675 / 17600 (157.24%) |
| LUT as logic | 27635 / 17600 (157.02%) |
| LUT as distributed RAM | 40 / 6000 (0.67%) |
| Slice registers | 41519 / 35200 (117.95%) |
| Block RAM tiles | 27 / 60 (45.00%) |
| DSPs | 10 / 80 (12.50%) |
| Bonded IOBs | 482 / 100 (482.00%) |

Yosys synthesis check:

| Metric | Result |
|---|---:|
| Main Yosys elapsed time | 315.8 s |
| Runner-observed peak child RSS | 1632.57 MiB |
| Flattened cells | 98386 |
| Estimated LCs | 33157 |
| RAMB36E1 | 27 |
| RAM32M | 10 |
| DSP48E1 | 13 |

Delta from the previous documented AV2 Vivado checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| `synth_design` elapsed time | 09:48 | 07:01 | -2:47 |
| Full wrapper elapsed time | 682.7 s | 487.0 s | -195.7 s |
| Vivado log peak memory | 3302.32 MB | 3244.88 MB | -57.44 MB |
| Vivado PSS peak, overall | 9348.03 MB | 9352.54 MB | +4.51 MB |
| Vivado PSS peak, forked workers | 7594.19 MB | 7596.98 MB | +2.79 MB |
| WNS at 25 MHz | +3.942 ns | +3.372 ns | -0.570 ns |
| TNS at 25 MHz | 0.000 ns | 0.000 ns | +0.000 ns |
| Setup failing endpoints | 0 | 0 | +0 |
| Worst hold slack | +0.043 ns | +0.043 ns | +0.000 ns |
| Slice LUTs | 43126 | 27675 | -15451 |
| LUT as logic | 30798 | 27635 | -3163 |
| LUT as distributed RAM | 12328 | 40 | -12288 |
| Slice registers | 41503 | 41519 | +16 |
| Block RAM tiles | 19 | 27 | +8 |
| DSPs | 10 | 10 | +0 |
| Bonded IOBs | 482 | 482 | +0 |

Current worst path:

- Source: `cached_chroma_samples_valid_q_reg[3]/C`.
- Destination: `chroma_bdpcm_symbolizer/entropy_context_q_reg[0]/D`.
- Data path delay: 36.477 ns, with 12.689 ns logic and 23.788 ns route.
- Logic levels: 52.
- The current timing target remains the chroma BDPCM symbolizer context path.

Notes:

- The design still meets the 25 MHz Z7-10 Vivado synthesis timing target.
- This is primarily an area and synthesis-time improvement. Output-utilization
  smoke metrics stayed unchanged because the byte stream and output handshake
  schedule are unchanged.
- The payload byte buffer now accounts for 8 additional BRAM tiles instead of
  12,288 distributed-RAM LUTs. The design still exceeds the small Z7-10 fabric
  capacity in LUTs, registers, and I/O count, so this board remains a pressure
  target rather than a fit target for the full encoder.
