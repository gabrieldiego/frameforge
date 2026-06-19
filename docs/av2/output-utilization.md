# AV2 RTL Output Utilization Baselines

This file records AV2 RTL simulation throughput counters per validation vector.
It is separate from quality/bitrate reporting because these numbers describe
testbench-observed output timing, not compression efficiency.

Metric definitions:

- `total_cycles`: RTL cycles from encoder start until the final output byte is
  accepted on `m_axis`.
- `output_active_cycles`: cycles where `m_axis_valid && m_axis_ready` accepted
  one output byte. The AV2 encoder testbench holds `m_axis_ready` high.
- `output_wait_cycles`: `total_cycles - output_active_cycles`.
- `output_utilization`: `output_active_cycles / total_cycles`; this is the
  requested ratio of cycles outputting data to total cycles.
- `bubble_rate`: `1 - output_utilization`, the fraction of measured cycles
  spent not accepting output bytes.
- `cycles/bit`: `total_cycles / rtl_bitstream_bits`.
- `cycles/input pixel`: `total_cycles / (width * height * frames)`.
- The metrics JSON also records `state_cycles`, `leaf_phase_cycles`,
  `pipeline_cycles`, `entropy_op_cycles`, `pending_push_cycles`, and
  `input_sample_cycles` for AV2-specific profiling. The constants and JSON
  writer for these internal counters live in `tb/av2_metrics.py`; they are not
  part of the shared top-level pass/fail contract.

## 2026-06-18 AXI Writer FIFO

Measured after optimizing the shared AXI bridge used by every codec target. The
frame reader keeps the previous aligned one-word source cache. The bitstream
writer now has an eight-word FIFO in front of the AXI write channel and emits
bursts of up to four packed AXI words. The AV2 codec algorithm, bitstreams, and
reconstructions are unchanged from the previous AXI word-cache checkpoint.

Baseline and current sources:

- Baseline Git SHA: `3bfd06419dc094776c36d417a7868ee19b774632`
- Current validated RTL Git SHA: `f0fc6dd70d0aacccc6a8474560c14f5118defd14`
- Baseline mode: shared AXI4-Lite control registers, AXI4 memory-mapped
  aligned source word reads with a one-word cache, and 4-beat packed bitstream
  write bursts.
- Current mode: same source word cache, plus an eight-word bitstream writer
  FIFO that can keep accepting packed words while a previous burst is draining.
- Delta columns compare against the previous AXI word-cache checkpoint.

Validation commands:

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
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.
- Bitstream lengths were unchanged, so bitrate deltas remain `+0.0000`.

### Full Screenshot Sweep

Aggregate RTL bits: `770848` (+0).
Aggregate total cycles: `1268285` (-8793).
Aggregate output utilization: `0.075973` (+0.000523); bubble rate: `0.924027` (-0.000523).
Aggregate cycles/bit: `1.645311` (-0.011407); aggregate cycles/input pixel: `15.290859` (-0.106011).
Per-vector cycles/input pixel range: `9.083767` to `23.684896` (baseline `9.091580` to `23.919271`).

The active output cycles remain `96356`. The improvement comes from reducing
write-side stalls in the shared bitstream writer. The source-read path is
unchanged from the previous checkpoint.

### Screenshot Multi-CTU And Partial Crops

Aggregate RTL bits: `592008` (+0).
Aggregate total cycles: `1216483` (-6908).
Aggregate output utilization: `0.060832` (+0.000344); bubble rate: `0.939168` (-0.000344).
Aggregate cycles/bit: `2.054842` (-0.011669); aggregate cycles/input pixel: `13.245677` (-0.075218).
Per-vector cycles/input pixel range: `9.081380` to `18.097222` (baseline `9.088325` to `18.252170`).

The active output cycles remain `74001`. Per-vector metrics are retained in
`verification/generated/validation_logs/screenshot-multictu-444_*.log`.

## 2026-06-18 Shared AXI Interface Baseline

Measured after moving the AV2 public top-level interface to the shared AXI4-Lite
control plane plus AXI4 memory-mapped frame reader and bitstream writer. The AV2
codec algorithm, bitstreams, and reconstructions are unchanged from the previous
documented checkpoint. The utilization regression is expected for this first
interface pass because the shared frame reader performs single-beat sample reads
instead of bursts.

Baseline and current sources:

- Baseline Git SHA: `33be2008240bf3acecef4a9344ca9e9b01313dc5`
- Source base Git SHA for this run: `c6bcfcfae062a8671c4194d3e062f9b195134012`
- Baseline mode: residual sign scan skip, known-zero luma residual fast path,
  pipeline profiler counters, and direct testbench stream wiring.
- Current mode: shared AXI4-Lite control registers, AXI4 memory-mapped
  single-beat source reads, and AXI4 memory-mapped packed bitstream writes.
- Delta columns compare against the baseline checkpoint above.

Validation commands:

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
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.
- Bitstream lengths were unchanged, so bitrate deltas remain `+0.0000`.

### Full Screenshot Sweep

Aggregate RTL bits: `770848` (+0).
Aggregate total cycles: `1940598` (+1012188).
Aggregate output utilization: `0.049653` (-0.054133); bubble rate: `0.950347` (+0.054133).
Aggregate cycles/bit: `2.517485` (+1.313084); aggregate cycles/input pixel: `23.396484` (+12.203269).
Per-vector cycles/input pixel range: `16.974392` to `32.036458` (baseline `4.973090` to `19.567708`).

The output byte count is unchanged; the active output cycles remain `96356`.
The extra cycles are dominated by the single-beat AXI source fetch path and are
therefore a wrapper-throughput baseline, not a codec-algorithm regression.

Per-vector metrics are retained in
`verification/generated/validation_logs/screenshot-sweep-444_*.log`.

### Screenshot Multi-CTU And Partial Crops

Aggregate RTL bits: `592008` (+0).
Aggregate total cycles: `1953567` (+1114535).
Aggregate output utilization: `0.037880` (-0.050318); bubble rate: `0.962120` (+0.050318).
Aggregate cycles/bit: `3.299900` (+1.882635); aggregate cycles/input pixel: `21.271418` (+12.135617).
Per-vector cycles/input pixel range: `16.971137` to `26.282118` (baseline `4.970486` to `13.987196`).

The output byte count is unchanged; the active output cycles remain `74001`.
The additional cycles again come from the initial single-beat AXI source fetch
path. Per-vector metrics are retained in
`verification/generated/validation_logs/screenshot-multictu-444_*.log`.
