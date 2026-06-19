# VVC RTL Output Utilization Baseline

This file records VVC RTL simulation throughput counters per validation vector.
It mirrors the common top-level metrics used by AV2 while avoiding AV2-specific
internal profiler counters.

Metric definitions:

- `total_cycles`: RTL cycles from encoder start until the final output byte is
  accepted on `m_axis`.
- `output_active_cycles`: cycles where `m_axis_valid && m_axis_ready` accepted
  one output byte. The VVC encoder testbench holds `m_axis_ready` high.
- `output_wait_cycles`: `total_cycles - output_active_cycles`.
- `output_utilization`: `output_active_cycles / total_cycles`; this is the
  ratio of cycles outputting data to total measured cycles.
- `bubble_rate`: `1 - output_utilization`, the fraction of measured cycles
  spent not accepting output bytes.
- `cycles/bit`: `total_cycles / rtl_bitstream_bits`.
- `cycles/input pixel`: `total_cycles / (width * height * frames)`.

AV2 has additional codec-internal counters for state, leaf phase, and pipeline
profiling. Those remain AV2-specific instrumentation and are documented only in
the AV2 utilization report.

## 2026-06-19 Source Cache And Luma AC Throughput

Measured after two VVC throughput changes:

- The shared AXI frame reader now keeps a small direct plane-row cache indexed
  by component and local block row, so adjacent horizontal 8x8 blocks can reuse
  source read beats.
- The VVC luma 8x8 residual path now computes each supported AC coefficient in
  one cycle instead of serializing the 16 cell terms across 16 cycles. The
  coefficient values, bitstream syntax, and reconstructions are unchanged.

Baseline and current sources:

- Baseline Git SHA: `f0fc6dd70d0aacccc6a8474560c14f5118defd14`
- Current validated RTL Git SHA: `ffb4179caa0de4a4a4e52f4a21eaf9ddb39efc64`
- Current mode: shared AXI4-Lite control registers, AXI4 memory-mapped source
  reads with a direct plane-row cache, 4-beat packed bitstream write bursts,
  and the faster VVC luma AC residual datapath.
- This is the first documented VVC utilization baseline for the local
  screenshot and RaceHorses crop sets. Future changes should compare against
  these aggregate numbers.

Validation commands:

```sh
make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=racehorses-sweep-420 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=racehorses-multictu-420 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
- `racehorses-sweep-420`: OK (64/64)
- `racehorses-multictu-420`: OK (10/10)
- All listed vectors matched SW/RTL bitstream checksums and SW/RTL/VTM
  reconstruction checksums.
- Bitstream lengths were unchanged, so bitrate deltas remain `+0.0000`.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits | Total cycles | Active cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel | Cycles/pixel range |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| screenshot-sweep-444 | 64 | 398840 | 1581091 | 49855 | 0.031532 | 0.968468 | 3.964224 | 19.062150 | 9.565430-35.325521 |
| screenshot-multictu-444 | 10 | 319168 | 1483255 | 39896 | 0.026898 | 0.973102 | 4.647255 | 16.150601 | 9.439019-22.691176 |
| racehorses-sweep-420 | 64 | 113168 | 1170183 | 14146 | 0.012089 | 0.987911 | 10.340229 | 14.108109 | 13.618490-23.859375 |
| racehorses-multictu-420 | 10 | 92920 | 1251691 | 11615 | 0.009279 | 0.990721 | 13.470631 | 13.629040 | 13.277018-14.036265 |

Per-vector metrics are retained in:

- `verification/generated/validation_logs/screenshot-sweep-444_*.log`
- `verification/generated/validation_logs/screenshot-multictu-444_*.log`
- `verification/generated/validation_logs/racehorses-sweep-420_*.log`
- `verification/generated/validation_logs/racehorses-multictu-420_*.log`

The 4:2:0 RaceHorses sets exercise the luma residual acceleration directly.
The 4:4:4 screenshot sets mostly measure the shared source-cache behavior,
because their current VVC path is dominated by lossless screen-content coding.

## 2026-06-18 AXI Writer FIFO

Measured after optimizing the shared AXI bridge used by every codec target. The
frame reader keeps the previous aligned one-word source cache. The bitstream
writer now has an eight-word FIFO in front of the AXI write channel and emits
bursts of up to four packed AXI words. The VVC codec algorithm, bitstreams, and
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

Validation command:

```sh
make hardware-regression CODEC=vvc HARDWARE_REGRESSION_SYNTH=0
```

Validation result:

- `smoke`: OK (6/6)
- `sweep-420`: OK (64/64)
- `sweep-444`: OK (64/64)
- All listed vectors matched SW/RTL bitstream checksums and SW/RTL/VTM
  reconstruction checksums.
- Bitstream lengths were unchanged, so bitrate deltas remain `+0.0000`.

### Full Geometry Sweeps

`sweep-420`:

- Aggregate RTL bits: `44552` (+0).
- Aggregate total cycles: `1156079` (+0).
- Aggregate output utilization: `0.004817` (+0.000000); bubble rate: `0.995183` (+0.000000).
- Aggregate cycles/bit: `25.948981` (+0.000000).
- Aggregate cycles/input pixel: `13.938067` (+0.000000).
- Per-vector cycles/input pixel range: `13.470703` to `25.609375` (baseline `13.470703` to `25.609375`).

`sweep-444`:

- Aggregate RTL bits: `76144` (+0).
- Aggregate total cycles: `857904` (+0).
- Aggregate output utilization: `0.011094` (+0.000000); bubble rate: `0.988906` (+0.000000).
- Aggregate cycles/bit: `11.266863` (+0.000000).
- Aggregate cycles/input pixel: `10.343171` (+0.000000).
- Per-vector cycles/input pixel range: `9.957520` to `18.906250` (baseline `9.957520` to `18.906250`).

Per-vector metrics are retained in
`verification/generated/validation_logs/sweep-420_*.log` and
`verification/generated/validation_logs/sweep-444_*.log`.

## 2026-06-18 Shared AXI Interface Baseline

Measured after moving public top-level input and output to the shared AXI
wrapper. The smoke set and the full public VVC hardware regression passed on
the same source tree; the full sweep summaries below are the current regression
baseline for the shared top-level metrics.

Validation command:

```sh
make hardware-regression CODEC=vvc HARDWARE_REGRESSION_SYNTH=0
```

Validation result:

- `smoke`: OK (6/6)
- `sweep-420`: OK (64/64)
- `sweep-444`: OK (64/64)
- All listed vectors matched SW/RTL bitstream checksums and SW/RTL/VTM
  reconstruction checksums.

### Full Geometry Sweeps

`sweep-420`:

- Aggregate RTL bits: `44552`.
- Aggregate total cycles: `1469720`.
- Aggregate output utilization: `0.003789`; bubble rate: `0.996211`.
- Aggregate cycles/bit: `32.988867`.
- Aggregate cycles/input pixel: `17.719425`.
- Per-vector cycles/input pixel range: `17.220703` to `29.828125`.

`sweep-444`:

- Aggregate RTL bits: `76144`.
- Aggregate total cycles: `1512396`.
- Aggregate output utilization: `0.006293`; bubble rate: `0.993707`.
- Aggregate cycles/bit: `19.862314`.
- Aggregate cycles/input pixel: `18.233941`.
- Per-vector cycles/input pixel range: `17.832520` to `27.343750`.

Per-vector metrics are retained in
`verification/generated/validation_logs/sweep-420_*.log` and
`verification/generated/validation_logs/sweep-444_*.log`.

### Smoke Set

Aggregate RTL bits: `24392`.
Aggregate total cycles: `574328`.
Aggregate output utilization: `0.005309`; bubble rate: `0.994691`.
Aggregate cycles/bit: `23.545753`.
Aggregate cycles/input pixel: `19.466106`.

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| black_8x8_1f_yuv420p8.yuv | PASS | 568 | 1909 | 71 | 1838 | 0.037192 | 0.962808 | 3.360915 | 29.828125 |
| black_16x16_2f_yuv420p8.yuv | PASS | 784 | 9888 | 98 | 9790 | 0.009911 | 0.990089 | 12.612245 | 19.312500 |
| screen_blocks_16x16_1f_yuv444p8.yuv | PASS | 648 | 5150 | 81 | 5069 | 0.015731 | 0.984269 | 7.945988 | 20.113281 |
| screen_blocks_64x64_1f_yuv444p8.yuv | PASS | 2608 | 73042 | 326 | 72716 | 0.004463 | 0.995537 | 28.006902 | 17.832520 |
| stick_walk_64x64_3f_30fps_yuv420p8.yuv | PASS | 8184 | 241683 | 1023 | 240660 | 0.004233 | 0.995767 | 29.531403 | 19.668376 |
| stick_walk_64x64_3f_30fps_yuv444p8.yuv | PASS | 11600 | 242656 | 1450 | 241206 | 0.005976 | 0.994024 | 20.918621 | 19.747396 |

The poor utilization is expected for this checkpoint. The public AXI wrapper is
currently single-beat and the codec internals still serialize substantial
symbolization and entropy work. Future throughput work should compare against
this table using the same common top-level metrics.
