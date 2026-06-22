# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-22 Cached AXI Frame Reader Fast Path

Measured after allowing the shared AXI4 frame reader to keep `sample_valid`
asserted for the next visible sample when it is on the same row and already in
the cached AXI beat. This is a transport/input scheduling optimization; the
AV2 bitstream syntax and reconstruction are unchanged. This checkpoint uses
Yosys for the synthesis delta so utilization work can iterate faster.

Baseline and current sources:

- Baseline synthesis report Git SHA:
  `8653c51b3e7f7d2bb61c1d2b18c7a9e0d91a5f59`.
- Baseline validated RTL/source Git SHA:
  `874fb312adf735387f53551bcbed5254fdc98051`.
- Current validated RTL/source Git SHA:
  `5b5095a82297d6f39d2b20c147ccf051e267fb0d`.
- Baseline mode: AV2 local IBC leaf-order mapping expressed structurally, with
  the shared AXI frame reader returning to `ST_SKIP` between cached samples.
- Current mode: same codec behavior, with cached same-row samples drained on
  consecutive cycles when the downstream block is ready.
- Delta columns compare against the previous documented AV2 Yosys checkpoint.

Validation result:

- `screenshot-sweep-444`: PASS, 64/64 vectors, strict SW/RTL bitstream parity
  and SW/RTL/reference-decoder lossless reconstruction parity.
- `screenshot-multictu-444`: PASS, 10/10 vectors, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder lossless reconstruction parity.
- Direct `screenshot_640_sweep_16x16_1f_yuv444p8.yuv` validation: PASS.
- Direct `screenshot_640_sweep_64x64_1f_yuv444p8.yuv` validation: PASS.
- Shared-reader VVC smoke `racehorses_crop_8x8_1f_yuv420p8.yuv`: PASS.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis: not rerun for this utilization iteration; use the previous
  report for the latest Vivado timing baseline.

Yosys synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- RTL top: `ff_av2_encoder`.
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`.
- clock target metadata: 25 MHz.
- max visible size: 1024x1024.
- feature flags: palette 4:4:4 enabled, lossy 4:2:0 residual enabled.

Yosys synthesis check:

| Metric | Result |
|---|---:|
| Main Yosys elapsed time | 250.4 s |
| Runner-observed peak child RSS | 1378.57 MiB |
| Flattened cells | 69410 |
| Estimated LCs | 24586 |
| RAMB36E1 | 30 |
| RAM32M | 10 |
| DSP48E1 | 13 |

Delta from the previous documented AV2 Yosys checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time | 235.5 s | 250.4 s | +14.9 s |
| Runner-observed peak child RSS | 1364.19 MiB | 1378.57 MiB | +14.38 MiB |
| Flattened cells | 69688 | 69410 | -278 |
| Estimated LCs | 24760 | 24586 | -174 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |
| DSP48E1 | 13 | 13 | +0 |

Current Yosys topological critical path summary:

- Longest topological path in `ff_av2_encoder`: length 55.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.
- The Yosys topological report is useful for relative RTL pressure, but Vivado
  remains the timing authority for the Z7 target.

Bitrate and output-utilization impact:

| Vector set | Result | Bitrate delta | Cycle observation |
|---|---|---:|---|
| `screenshot-sweep-444` | 64/64 PASS | +0.0000 bpp (+0.00%) | weighted total cycles improved 1194284 -> 976556; output util 0.079 -> 0.097 |
| `screenshot-multictu-444` | 10/10 PASS | +0.0000 bpp (+0.00%) | weighted total cycles improved 1098202 -> 857122; output util 0.065 -> 0.083 |

Notes:

- The Yosys area signal improved slightly: 278 fewer flattened cells and 174
  fewer estimated LCs. Runtime and RSS increased modestly, so this should be
  watched if more reader-side lookahead is added.
- The output-utilization counters improved on both validated 4:4:4 sets, but
  the aggregate bubble rate is still above the requested 0.800 ceiling. The
  next meaningful optimization needs to overlap or stream across the currently
  serialized input, entropy, carry propagation, and final output phases.
- The design still exceeds the small Z7-10 fabric capacity in LUTs and I/O
  count, so this board remains a pressure target rather than a fit target for
  the full encoder.
