# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-18 AXI Writer FIFO

Measured after optimizing the shared AXI bridge used by every codec target. The
frame reader keeps the previous aligned one-word source cache, and the
bitstream writer now has an eight-word FIFO in front of the AXI write channel
while still emitting bursts of up to four packed AXI words. The AV2 codec
algorithm, bitstreams, and reconstructions are unchanged from the previous AXI
word-cache checkpoint.

Baseline and current sources:

- Baseline Git SHA: `3bfd06419dc094776c36d417a7868ee19b774632`
- Current validated RTL Git SHA: `f0fc6dd70d0aacccc6a8474560c14f5118defd14`
- Baseline mode: shared AXI4-Lite control registers, AXI4 memory-mapped
  aligned source word reads with a one-word cache, and 4-beat packed bitstream
  write bursts.
- Current mode: same source word cache, plus an eight-word bitstream writer
  FIFO that can keep accepting packed words while a previous burst is draining.
- Delta columns compare against the previous AXI word-cache checkpoint.

Validation configuration:

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
- Software and RTL OBU bitstreams matched exactly.
- Software, RTL, and AV2 reference-decoder reconstructions matched the input
  losslessly for every listed vector.

Synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled
- max visible size: 1024x1024

Synthesis result:

- Yosys synthesis passed in 284.6 seconds.
- Peak child RSS observed by the synthesis runner was 1522.92 MiB.
- Runtime stayed below the 300 second review threshold and inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.8 seconds.
- Post-synthesis critical-path reporting completed in 68.5 seconds with peak
  memory 1522.92 MiB and topological path length 55.
- The longest top-level path remains in the palette analyzer, luma palette
  symbolizer, entropy op mux, and range coder normalization path.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 90509 |
| Estimated LCs | 29173 |
| CARRY4 | 2331 |
| DSP48E1 | 13 |
| FDCE | 6355 |
| FDPE | 27 |
| FDRE | 30804 |
| FDSE | 14 |
| LUT1 | 616 |
| LUT2 | 7024 |
| LUT3 | 4848 |
| LUT4 | 2949 |
| LUT5 | 3672 |
| LUT6 | 17704 |
| MUXF7 | 2730 |
| MUXF8 | 659 |
| RAMB36E1 | 19 |
| RAM32M | 10 |
| RAM64M | 1536 |

Delta from the previous AXI word-cache checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 281.7 s | 284.6 s | +2.9 s |
| Peak synthesis RSS | 1447.74 MiB | 1522.92 MiB | +75.18 MiB |
| Cell report time | 5.7 s | 5.8 s | +0.1 s |
| Critical-path report time | 67.9 s | 68.5 s | +0.6 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 89427 | 90509 | +1082 |
| Estimated LCs | 29693 | 29173 | -520 |
| CARRY4 | 2337 | 2331 | -6 |
| DSP48E1 | 13 | 13 | +0 |
| FDCE | 6378 | 6355 | -23 |
| FDPE | 27 | 27 | +0 |
| FDRE | 30228 | 30804 | +576 |
| FDSE | 14 | 14 | +0 |
| LUT1 | 451 | 616 | +165 |
| LUT2 | 6858 | 7024 | +166 |
| LUT3 | 5215 | 4848 | -367 |
| LUT4 | 2930 | 2949 | +19 |
| LUT5 | 3343 | 3672 | +329 |
| LUT6 | 18205 | 17704 | -501 |
| MUXF7 | 2176 | 2730 | +554 |
| MUXF8 | 479 | 659 | +180 |
| RAMB36E1 | 19 | 19 | +0 |
| RAM32M | 10 | 10 | +0 |
| RAM64M | 1536 | 1536 | +0 |

The common AXI writer FIFO reduces estimated LCs while keeping the topological
critical path flat. Synthesis time and peak memory rose slightly, but both stay
inside the current review and hard-stop thresholds.

## 2026-06-18 Shared AXI Interface Baseline

Measured after moving the AV2 top-level integration to the shared AXI4-Lite
control interface plus AXI4 memory-mapped source/bitstream data movers. The
internal AV2 block stream and codec syntax are unchanged; this checkpoint
captures the public SoC-facing wrapper cost.

Baseline and current sources:

- Baseline Git SHA: `33be2008240bf3acecef4a9344ca9e9b01313dc5`
- Source base Git SHA for this run: `c6bcfcfae062a8671c4194d3e062f9b195134012`
- Baseline mode: residual sign scan skip, known-zero luma residual fast path,
  pipeline profiler counters, and direct testbench stream wiring.
- Current mode: shared AXI4-Lite control registers, AXI4 memory-mapped single
  beat source reads, and AXI4 memory-mapped packed bitstream writes.
- Delta columns compare against the previous documented AV2 top-synthesis
  baseline for the same DUT and board.

Validation configuration:

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
- Software and RTL OBU bitstreams matched exactly.
- Software, RTL, and AV2 reference-decoder reconstructions matched the input
  losslessly for every listed vector.

Synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- feature flags: palette 4:4:4 enabled, exact-hash IBC 4:4:4 enabled
- max visible size: 1024x1024

Synthesis result:

- Yosys synthesis passed in 294.2 seconds.
- Peak child RSS observed by the synthesis runner was 1449.40 MiB.
- Runtime stayed below the 300 second review threshold and inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.6 seconds.
- Post-synthesis critical-path reporting completed in 71.2 seconds with peak
  memory 1449.40 MiB and topological path length 55.
- The longest top-level path still starts at `palette_row_q`, runs through the
  palette analyzer, luma palette symbolizer, entropy op mux, and range coder
  normalization path.
- The isolated `ff_av2_chroma_sample_store` path length remains 1.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 87420 |
| Estimated LCs | 28151 |
| CARRY4 | 2335 |
| DSP48E1 | 13 |
| FDCE | 6189 |
| FDPE | 27 |
| FDRE | 29652 |
| FDSE | 14 |
| LUT1 | 397 |
| LUT2 | 7340 |
| LUT3 | 4559 |
| LUT4 | 2786 |
| LUT5 | 3180 |
| LUT6 | 17626 |
| MUXF7 | 2200 |
| MUXF8 | 465 |
| RAMB36E1 | 19 |
| RAM32M | 10 |
| RAM64M | 1536 |

Delta from the previous documented top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 303.3 s | 294.2 s | -9.1 s |
| Peak synthesis RSS | 1428.7 MiB | 1449.4 MiB | +20.7 MiB |
| Cell report time | 6.1 s | 5.6 s | -0.5 s |
| Critical-path report time | 75.3 s | 71.2 s | -4.1 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 84393 | 87420 | +3027 |
| Estimated LCs | 28059 | 28151 | +92 |
| CARRY4 | 2239 | 2335 | +96 |
| DSP48E1 | 11 | 13 | +2 |
| FDCE | 5489 | 6189 | +700 |
| FDPE | 24 | 27 | +3 |
| FDRE | 29652 | 29652 | +0 |
| FDSE | 14 | 14 | +0 |
| LUT1 | 349 | 397 | +48 |
| LUT2 | 6360 | 7340 | +980 |
| LUT3 | 4789 | 4559 | -230 |
| LUT4 | 2423 | 2786 | +363 |
| LUT5 | 3621 | 3180 | -441 |
| LUT6 | 17226 | 17626 | +400 |
| MUXF7 | 2355 | 2200 | -155 |
| MUXF8 | 559 | 465 | -94 |
| RAMB36E1 | 19 | 19 | +0 |
| RAM32M | 10 | 10 | +0 |
| RAM64M | 1536 | 1536 | +0 |

The AXI wrapper increased the flattened cell count but left estimated LCs
almost flat and did not lengthen the reported topological critical path. Future
AXI burst work should compare against this checkpoint and is expected to improve
throughput before it materially changes codec-area estimates.
