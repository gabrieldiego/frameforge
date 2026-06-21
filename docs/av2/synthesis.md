# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-20 DC-Delta TXB Timing Split

Measured after using the previous Vivado timing report to split the lossy
4:2:0 DC-only residual path out of the general chroma BDPCM symbolizer. The
new `ff_av2_dc_delta_txb_symbolizer` emits the same single-coefficient TXB
symbol stream for lossy 4:2:0 luma/chroma residuals without carrying the full
16-coefficient BDPCM scan, context, and residual arrays through the
residual-to-range-coder timing path.

Baseline and current sources:

- Baseline RTL Git SHA: `307363b80a71d77e19178e972a522c42bf8bfe1c`
- Current RTL source: working tree after `fc3c15b9f1801a0ba40f2dde99c47bb54c475c90`
- Baseline mode: AVM-order local IBC BVP stack with lossy 4:2:0 DC residuals
  emitted through the parameterized `ff_av2_chroma_bdpcm_symbolizer`.
- Current mode: same encoder behavior, with lossy 4:2:0 DC residuals emitted
  through a dedicated DC-delta TXB symbolizer.
- Delta columns compare against the previous documented AV2 synthesis
  checkpoint.

Validation result:

- `cargo test av2 --lib`: OK (25/25).
- `racehorses-sweep-420`: OK (64/64), strict SW/RTL bitstream parity and
  SW/RTL/reference-decoder reconstruction parity.
- `screenshot-sweep-444`: OK (64/64), strict SW/RTL bitstream parity and
  SW/RTL/reference-decoder lossless reconstruction parity.
- `screenshot-multictu-444`: OK (10/10), same parity checks.
- Yosys synthesis: PASS.
- Vivado was not rerun after this patch. The optimization target was the
  previous Vivado worst path documented below.

Yosys synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled,
  lossy 4:2:0 residual enabled
- max visible size: 1024x1024

Yosys synthesis result:

- Yosys synthesis passed in 349.0 seconds.
- Peak child RSS observed by the synthesis runner was 1666.98 MiB.
- Runtime exceeded the 300 second review threshold but completed inside the
  600 second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 7.1 seconds.
- Post-synthesis critical-path reporting completed in 91.5 seconds.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.
- The top `ff_av2_encoder` topological path length improved from 63 to 60.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count | Delta |
|---|---:|---:|
| Cells | 102391 | -478 |
| Estimated LCs | 35043 | -765 |
| CARRY4 | 2540 | -41 |
| DSP48E1 | 13 | +0 |
| FDCE | 4462 | -40 |
| FDPE | 27 | -8 |
| FDRE | 37423 | +0 |
| FDSE | 129 | +0 |
| LUT1 | 581 | +172 |
| LUT2 | 7675 | -589 |
| LUT3 | 6492 | -550 |
| LUT4 | 4357 | -212 |
| LUT5 | 3961 | -78 |
| LUT6 | 20233 | +75 |
| MUXF7 | 4574 | +793 |
| MUXF8 | 704 | +26 |
| RAMB36E1 | 19 | +0 |
| RAM32M | 10 | +0 |
| RAM64M | 1536 | +0 |

Delta from the previous documented AV2 synthesis checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 415.8 s | 349.0 s | -66.8 s |
| Peak synthesis RSS | 1695.05 MiB | 1666.98 MiB | -28.07 MiB |
| Cell-report time | 7.1 s | 7.1 s | +0.0 s |
| Critical-path report time | 100.6 s | 91.5 s | -9.1 s |
| Topological path length | 63 | 60 | -3 |
| Cells | 102869 | 102391 | -478 |
| Estimated LCs | 35808 | 35043 | -765 |

The timing-guided split reduced the reported topological path, total cells,
estimated LCs, synthesis runtime, and peak RSS without changing the encoded
bitstreams. The new Yosys top path still ends in the entropy range coder, but
it now starts from phase/control logic through the lossy 4:2:0 chroma DC
skip-CDF path rather than carrying the full BDPCM scan machinery.

Previous Vivado timing input:

- remote checkout Git SHA: `93ad7fad972aab259830c0daffe5dac62701c4c7`
  (`Document AV2 local IBC checkpoint`), a docs-only child of the baseline
  RTL SHA above.
- command context: `make synth-vivado CODEC=av2 SYNTH_DUT=av2-encoder`
  with a longer wrapper timeout and no wrapper memory cap.
- Vivado version: 2025.2.
- RTL top: `ff_av2_encoder`.
- device: `xc7z010clg400-1`.
- clock constraint: 25 MHz (`40.000 ns` period).
- max visible size: 1024x1024.
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled,
  lossy 4:2:0 residual enabled.

Previous Vivado synthesis result:

| Metric | Result |
|---|---:|
| `synth_design` elapsed time | 15:47 |
| Full Vivado batch elapsed time | about 21:06 |
| Vivado log peak memory | 3065.31 MB |
| Vivado PSS peak, overall | 6454.57 MB |
| Vivado PSS peak, forked | 6078.84 MB |
| WNS at 25 MHz | -1.944 ns |
| TNS at 25 MHz | -102.321 ns |
| Setup failing endpoints | 100 |
| Worst hold slack | +0.043 ns |
| Slice LUTs | 44143 / 17600 (250.81%) |
| LUT as logic | 31815 / 17600 (180.77%) |
| LUT as distributed RAM | 12328 / 6000 (205.47%) |
| Slice registers | 41562 / 35200 (118.07%) |
| Block RAM tiles | 19 / 60 (31.67%) |
| DSPs | 10 / 80 (12.50%) |
| Bonded IOBs | 482 / 100 (482.00%) |

The previous Vivado worst path started at
`control_regs/chroma_format_idc_reg[0]` and ended at `low_q_reg[63]`. It
crossed the lossy 4:2:0 luma estimator/residual-symbolizer path and the
range-coder step, with a 41.792 ns data path delay, 53 logic levels, and route
delay accounting for about 60% of the path. The DC-delta split removes the
full BDPCM symbolizer from that lossy 4:2:0 path; the next Vivado run should
verify whether the WNS moves to the shorter skip-CDF/range-coder path now
reported by Yosys.
