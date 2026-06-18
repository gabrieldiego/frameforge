# AV2 Synthesis Baseline

This file records the current AV2-specific synthesis checkpoint. The shared
command wrapper is documented in [../synthesis.md](../synthesis.md), but AV2
area, timing, elapsed time, and memory results are tracked separately from VVC.

Older bring-up and intermediate optimization checkpoints are intentionally kept
out of this report so the document remains focused on the current validated
baseline and its immediate delta. Use git history for retired measurements.

## 2026-06-18 AXI Word Cache And Burst Writer

Measured after optimizing the shared AXI bridge used by every codec target. The
frame reader now fetches aligned full-width AXI words with a one-word cache,
and the bitstream writer now emits up to four packed AXI words per INCR burst.
The AV2 codec algorithm, bitstreams, and reconstructions are unchanged from the
shared AXI interface baseline below.

Baseline and current sources:

- Baseline Git SHA: `fda5b7fe85f85bb88c2775927046d443fa2f7fce`
- Current validated RTL Git SHA: `3bfd06419dc094776c36d417a7868ee19b774632`
- Baseline mode: shared AXI4-Lite control registers, AXI4 memory-mapped
  single-beat source reads, and AXI4 memory-mapped packed bitstream writes.
- Current mode: shared AXI4-Lite control registers, AXI4 memory-mapped aligned
  source word reads with a one-word cache, and 4-beat packed bitstream write
  bursts.
- Delta columns compare against the shared AXI interface baseline below.

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

- Yosys synthesis passed in 281.7 seconds.
- Peak child RSS observed by the synthesis runner was 1447.74 MiB.
- Runtime stayed below the 300 second review threshold and inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 5.7 seconds.
- Post-synthesis critical-path reporting completed in 67.9 seconds with peak
  memory 1447.74 MiB and topological path length 55.
- The longest top-level path remains in the palette analyzer, luma palette
  symbolizer, entropy op mux, and range coder normalization path.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_av2_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 89427 |
| Estimated LCs | 29693 |
| CARRY4 | 2337 |
| DSP48E1 | 13 |
| FDCE | 6378 |
| FDPE | 27 |
| FDRE | 30228 |
| FDSE | 14 |
| LUT1 | 451 |
| LUT2 | 6858 |
| LUT3 | 5215 |
| LUT4 | 2930 |
| LUT5 | 3343 |
| LUT6 | 18205 |
| MUXF7 | 2176 |
| MUXF8 | 479 |
| RAMB36E1 | 19 |
| RAM32M | 10 |
| RAM64M | 1536 |

Delta from the shared AXI interface baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 294.2 s | 281.7 s | -12.5 s |
| Peak synthesis RSS | 1449.40 MiB | 1447.74 MiB | -1.66 MiB |
| Cell report time | 5.6 s | 5.7 s | +0.1 s |
| Critical-path report time | 71.2 s | 67.9 s | -3.3 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 87420 | 89427 | +2007 |
| Estimated LCs | 28151 | 29693 | +1542 |
| CARRY4 | 2335 | 2337 | +2 |
| DSP48E1 | 13 | 13 | +0 |
| FDCE | 6189 | 6378 | +189 |
| FDPE | 27 | 27 | +0 |
| FDRE | 29652 | 30228 | +576 |
| FDSE | 14 | 14 | +0 |
| LUT1 | 397 | 451 | +54 |
| LUT2 | 7340 | 6858 | -482 |
| LUT3 | 4559 | 5215 | +656 |
| LUT4 | 2786 | 2930 | +144 |
| LUT5 | 3180 | 3343 | +163 |
| LUT6 | 17626 | 18205 | +579 |
| MUXF7 | 2200 | 2176 | -24 |
| MUXF8 | 465 | 479 | +14 |
| RAMB36E1 | 19 | 19 | +0 |
| RAM32M | 10 | 10 | +0 |
| RAM64M | 1536 | 1536 | +0 |

The common AXI optimization adds the read-word cache and a four-word output
burst queue. The topological critical path stayed flat, synthesis runtime and
memory improved slightly, and the area increase is isolated to the shared data
movement wrapper rather than new codec logic.

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
