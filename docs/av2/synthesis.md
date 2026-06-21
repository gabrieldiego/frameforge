# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-21 Vivado Timing Closure

Measured after registering the AV2 DC-delta zero-TXB decision before emitting
the skip symbol. The previous Vivado report showed a failing path from the
lossy 4:2:0 residual estimator into the range coder. This change removes that
same-cycle estimator-to-range-coder path while preserving the emitted
`coeffs()` syntax.

Baseline and current sources:

- Baseline Vivado report Git SHA: `93ad7fad972aab259830c0daffe5dac62701c4c7`
  (`Document AV2 local IBC checkpoint`), a docs-only child of RTL SHA
  `64961ede3115ee0941c2da7a519999f0285be8d2`.
- Current validated RTL/source Git SHA:
  `3d2b2303cd67599afa6df6de64e86f6dc2f28efd`.
- Baseline mode: AV2 local IBC, palette 4:4:4, and lossy 4:2:0 residual with
  the DC zero-TXB skip emitted directly from the estimator path.
- Current mode: same codec behavior, with the DC zero-TXB decision registered
  before entropy emission and the Vivado clock constraint read before
  `synth_design`.
- Delta columns compare against the previous documented AV2 Vivado checkpoint.

Validation result:

- `python3 -m py_compile scripts/run_synth.py scripts/setup_vivado.py
  scripts/install_synth_env.py`: PASS.
- `racehorses-sweep-420` limited 8x8 smoke: PASS, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder reconstruction parity.
- `screenshot-sweep-444` limited 8x8 smoke: PASS, strict SW/RTL bitstream
  parity and SW/RTL/reference-decoder lossless reconstruction parity.
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
| Wrapper elapsed time | 682.7 s |
| `synth_design` elapsed time | 09:48 |
| Runner-observed peak child RSS | 2674.39 MiB |
| Vivado log peak memory | 3302.32 MB |
| Vivado PSS peak, overall | 9348.03 MB |
| Vivado PSS peak, main process | 2658.39 MB |
| Vivado PSS peak, forked workers | 7594.19 MB |
| WNS at 25 MHz | +3.942 ns |
| TNS at 25 MHz | 0.000 ns |
| Setup failing endpoints | 0 |
| Worst hold slack | +0.043 ns |
| Slice LUTs | 43126 / 17600 (245.03%) |
| LUT as logic | 30798 / 17600 (174.99%) |
| LUT as distributed RAM | 12328 / 6000 (205.47%) |
| Slice registers | 41503 / 35200 (117.91%) |
| Block RAM tiles | 19 / 60 (31.67%) |
| DSPs | 10 / 80 (12.50%) |
| Bonded IOBs | 482 / 100 (482.00%) |

Delta from the previous documented AV2 Vivado checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| `synth_design` elapsed time | 15:47 | 09:48 | -5:59 |
| Full wrapper elapsed time | about 21:06 | 11:22.7 | about -9:43 |
| Vivado log peak memory | 3065.31 MB | 3302.32 MB | +237.01 MB |
| Vivado PSS peak, overall | 6454.57 MB | 9348.03 MB | +2893.46 MB |
| Vivado PSS peak, forked workers | 6078.84 MB | 7594.19 MB | +1515.35 MB |
| WNS at 25 MHz | -1.944 ns | +3.942 ns | +5.886 ns |
| TNS at 25 MHz | -102.321 ns | 0.000 ns | +102.321 ns |
| Setup failing endpoints | 100 | 0 | -100 |
| Worst hold slack | +0.043 ns | +0.043 ns | +0.000 ns |
| Slice LUTs | 44143 | 43126 | -1017 |
| LUT as logic | 31815 | 30798 | -1017 |
| LUT as distributed RAM | 12328 | 12328 | +0 |
| Slice registers | 41562 | 41503 | -59 |
| Block RAM tiles | 19 | 19 | +0 |
| DSPs | 10 | 10 | +0 |
| Bonded IOBs | 482 | 482 | +0 |

Current worst path:

- Source: `cached_chroma_samples_valid_q_reg[3]/C`.
- Destination: `chroma_bdpcm_symbolizer/entropy_context_q_reg[0]/D`.
- Data path delay: 35.907 ns, with 12.565 ns logic and 23.342 ns route.
- The previous `low_q_reg` range-coder path now has positive slack; the new
  timing target is the chroma BDPCM symbolizer context path.

Notes:

- The design now meets the 25 MHz Z7-10 Vivado synthesis timing target.
- Area also improved slightly versus the previous documented Vivado checkpoint,
  but the design still exceeds the small Z7-10 fabric capacity in LUTs,
  registers, distributed RAM, and I/O count. Treat this board as a consistent
  timing/area pressure target rather than a fit target for the full encoder.
- A `PerformanceOptimized` plus retiming run was tested but abandoned before
  completion because Vivado moved into a high-memory timing-aware mapping phase
  and reported zero retiming moves. The adopted baseline remains the default
  directive with retiming disabled.
