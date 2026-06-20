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

## 2026-06-19 4:2:0 Lossy Residual Baseline

Measured after extending the AV2 `yuv420p8` residual RTL to all RaceHorses
single-superblock crop geometries and selected larger multi-superblock smoke
vectors. This is the first output-utilization baseline for the AV2 4:2:0 path,
so delta columns are intentionally omitted.

Baseline and current sources:

- Baseline Git SHA: none; this is the first AV2 `yuv420p8` utilization
  baseline.
- Current validated RTL Git SHA:
  `3b644b32e731840bb1da774312c5a0c70298f040`

Validation result:

- `racehorses-sweep-420`: OK (64/64).
- Larger 4:2:0 smoke vectors: OK (7/7).
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses-sweep-420 | 64 | 182464 | 559546 | 22808 | 536738 | 0.041 | 0.959 | 3.067 | 6.746 |
| larger RaceHorses 4:2:0 smoke | 7 | 139608 | 455922 | 17451 | 438471 | 0.038 | 0.962 | 3.266 | 6.615 |

### RaceHorses 4:2:0 Sweep

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 | 591 | 38 | 553 | 0.064 | 0.936 | 1.944 | 9.234 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 | 1013 | 57 | 956 | 0.056 | 0.944 | 2.221 | 7.914 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 | 1473 | 80 | 1393 | 0.054 | 0.946 | 2.302 | 7.672 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 | 1903 | 103 | 1800 | 0.054 | 0.946 | 2.309 | 7.434 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 | 2344 | 122 | 2222 | 0.052 | 0.948 | 2.402 | 7.325 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 | 2733 | 129 | 2604 | 0.047 | 0.953 | 2.648 | 7.117 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 | 3187 | 155 | 3032 | 0.049 | 0.951 | 2.570 | 7.114 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 | 3609 | 174 | 3435 | 0.048 | 0.952 | 2.593 | 7.049 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 | 990 | 42 | 948 | 0.042 | 0.958 | 2.946 | 7.734 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 | 1861 | 93 | 1768 | 0.050 | 0.950 | 2.501 | 7.270 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 | 2691 | 114 | 2577 | 0.042 | 0.958 | 2.951 | 7.008 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 | 3527 | 152 | 3375 | 0.043 | 0.957 | 2.900 | 6.889 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 | 4403 | 193 | 4210 | 0.044 | 0.956 | 2.852 | 6.880 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 | 5214 | 222 | 4992 | 0.043 | 0.957 | 2.936 | 6.789 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 | 6098 | 261 | 5837 | 0.043 | 0.957 | 2.920 | 6.806 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 | 6929 | 292 | 6637 | 0.042 | 0.958 | 2.966 | 6.767 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 | 1457 | 66 | 1391 | 0.045 | 0.955 | 2.759 | 7.589 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 | 2708 | 122 | 2586 | 0.045 | 0.955 | 2.775 | 7.052 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 | 3973 | 163 | 3810 | 0.041 | 0.959 | 3.047 | 6.898 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 | 5168 | 204 | 4964 | 0.039 | 0.961 | 3.167 | 6.729 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 | 6534 | 275 | 6259 | 0.042 | 0.958 | 2.970 | 6.806 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 | 7758 | 325 | 7433 | 0.042 | 0.958 | 2.984 | 6.734 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 | 9083 | 379 | 8704 | 0.042 | 0.958 | 2.996 | 6.758 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 | 10417 | 448 | 9969 | 0.043 | 0.957 | 2.907 | 6.782 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 | 1849 | 75 | 1774 | 0.041 | 0.959 | 3.082 | 7.223 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 | 3543 | 149 | 3394 | 0.042 | 0.958 | 2.972 | 6.920 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 | 5194 | 200 | 4994 | 0.039 | 0.961 | 3.246 | 6.763 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 | 6889 | 279 | 6610 | 0.040 | 0.960 | 3.086 | 6.728 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 | 8711 | 369 | 8342 | 0.042 | 0.958 | 2.951 | 6.805 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 | 10291 | 418 | 9873 | 0.041 | 0.959 | 3.077 | 6.700 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 | 12024 | 489 | 11535 | 0.041 | 0.959 | 3.074 | 6.710 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 | 13722 | 568 | 13154 | 0.041 | 0.959 | 3.020 | 6.700 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 | 2320 | 95 | 2225 | 0.041 | 0.959 | 3.053 | 7.250 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 | 4420 | 191 | 4229 | 0.043 | 0.957 | 2.893 | 6.906 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 | 6488 | 248 | 6240 | 0.038 | 0.962 | 3.270 | 6.758 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 | 8607 | 344 | 8263 | 0.040 | 0.960 | 3.128 | 6.724 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 | 10756 | 433 | 10323 | 0.040 | 0.960 | 3.105 | 6.723 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 | 12963 | 552 | 12411 | 0.043 | 0.957 | 2.935 | 6.752 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 | 15039 | 612 | 14427 | 0.041 | 0.959 | 3.072 | 6.714 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 | 17133 | 695 | 16438 | 0.041 | 0.959 | 3.081 | 6.693 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 | 2787 | 121 | 2666 | 0.043 | 0.957 | 2.879 | 7.258 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 | 5302 | 228 | 5074 | 0.043 | 0.957 | 2.907 | 6.904 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 | 7701 | 285 | 7416 | 0.037 | 0.963 | 3.378 | 6.685 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 | 10237 | 394 | 9843 | 0.038 | 0.962 | 3.248 | 6.665 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 | 12874 | 513 | 12361 | 0.040 | 0.960 | 3.137 | 6.705 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 | 15369 | 627 | 14742 | 0.041 | 0.959 | 3.064 | 6.671 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 | 17989 | 722 | 17267 | 0.040 | 0.960 | 3.114 | 6.692 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 | 20439 | 814 | 19625 | 0.040 | 0.960 | 3.139 | 6.653 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 | 3216 | 134 | 3082 | 0.042 | 0.958 | 3.000 | 7.179 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 | 6134 | 259 | 5875 | 0.042 | 0.958 | 2.960 | 6.846 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 | 9018 | 335 | 8683 | 0.037 | 0.963 | 3.365 | 6.710 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 | 11943 | 461 | 11482 | 0.039 | 0.961 | 3.238 | 6.665 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 | 14943 | 587 | 14356 | 0.039 | 0.961 | 3.182 | 6.671 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 | 17987 | 743 | 17244 | 0.041 | 0.959 | 3.026 | 6.692 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 | 20975 | 838 | 20137 | 0.040 | 0.960 | 3.129 | 6.688 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 | 23836 | 950 | 22886 | 0.040 | 0.960 | 3.136 | 6.651 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 | 3640 | 148 | 3492 | 0.041 | 0.959 | 3.074 | 7.109 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 | 6950 | 280 | 6670 | 0.040 | 0.960 | 3.103 | 6.787 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 | 10323 | 394 | 9929 | 0.038 | 0.962 | 3.275 | 6.721 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 | 13580 | 514 | 13066 | 0.038 | 0.962 | 3.303 | 6.631 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 | 17067 | 665 | 16402 | 0.039 | 0.961 | 3.208 | 6.667 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 | 20423 | 812 | 19611 | 0.040 | 0.960 | 3.144 | 6.648 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 | 23957 | 968 | 22989 | 0.040 | 0.960 | 3.094 | 6.684 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 | 27243 | 1090 | 26153 | 0.040 | 0.960 | 3.124 | 6.651 |

### Larger RaceHorses 4:2:0 Smoke

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| RaceHorses_136x80_1f_yuv420p8.yuv | PASS | 20608 | 71494 | 2576 | 68918 | 0.036 | 0.964 | 3.469 | 6.571 |
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 | 54207 | 2123 | 52084 | 0.039 | 0.961 | 3.192 | 6.617 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 | 54258 | 2145 | 52113 | 0.040 | 0.960 | 3.162 | 6.623 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 | 107342 | 3977 | 103365 | 0.037 | 0.963 | 3.374 | 6.552 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 | 72402 | 2819 | 69583 | 0.039 | 0.961 | 3.210 | 6.655 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 | 61379 | 2388 | 58991 | 0.039 | 0.961 | 3.213 | 6.660 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 | 34840 | 1423 | 33417 | 0.041 | 0.959 | 3.060 | 6.721 |

## 2026-06-19 Direct Plane-Row Source Cache Recheck

Measured after the shared AXI frame reader was changed to keep a small direct
plane-row cache indexed by component and local block row. The AV2 codec
algorithm, bitstreams, and reconstructions are unchanged from the last detailed
AV2 utilization report; this section restores per-vector rows so future
throughput work has a concrete delta baseline again.

Baseline and current sources:

- Baseline Git SHA: `33be2008240bf3acecef4a9344ca9e9b01313dc5`
- Current validated RTL Git SHA: `ffb4179caa0de4a4a4e52f4a21eaf9ddb39efc64`
- Baseline mode: residual sign scan skip, known-zero luma residual fast path,
  pipeline profiler counters, and direct testbench stream wiring.
- Current mode: shared AXI4-Lite control registers, AXI4 memory-mapped source
  reads with a direct plane-row cache, and packed AXI bitstream writes.
- Delta columns compare against the last detailed per-vector AV2 output
  utilization report. The current values in this section should become the
  baseline for the next AV2 throughput delta.

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

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) | Cycles/pixel range |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| screenshot-sweep-444 | 64 (+0) | 770848 (+0) | 1228109 (+299699) | 96356 (+0) | 1131753 (+299699) | 0.078459 (-0.025327) | 0.921541 (+0.025327) | 1.593192 (+0.388791) | 14.806484 (+3.613269) | 8.521267-23.122396 (+3.548177/+3.554688) |
| screenshot-multictu-444 | 10 (+0) | 592008 (+0) | 1168279 (+329247) | 74001 (+0) | 1094278 (+329247) | 0.063342 (-0.024856) | 0.936658 (+0.024856) | 1.973418 (+0.556153) | 12.720808 (+3.585007) | 8.518880-17.659722 (+3.548394/+3.672526) |

### Full Screenshot Sweep

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 826 (+268) | 43 (+0) | 783 (+268) | 0.052058 (-0.025003) | 0.947942 (+0.025003) | 2.401163 (+0.779070) | 12.906250 (+4.187500) |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 2474 (+460) | 248 (+0) | 2226 (+460) | 0.100243 (-0.022895) | 0.899757 (+0.022895) | 1.246976 (+0.231855) | 19.328125 (+3.593750) |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 392 (+0) | 1797 (+723) | 49 (+0) | 1748 (+723) | 0.027268 (-0.018356) | 0.972732 (+0.018356) | 4.584184 (+1.844388) | 9.359375 (+3.765625) |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 712 (+0) | 2548 (+912) | 89 (+0) | 2459 (+912) | 0.034929 (-0.019472) | 0.965071 (+0.019472) | 3.578652 (+1.280899) | 9.953125 (+3.562500) |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 456 (+0) | 2874 (+1177) | 57 (+0) | 2817 (+1177) | 0.019833 (-0.013756) | 0.980167 (+0.013756) | 6.302632 (+2.581141) | 8.981250 (+3.678125) |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 496 (+0) | 3373 (+1368) | 62 (+0) | 3311 (+1368) | 0.018381 (-0.012542) | 0.981619 (+0.012542) | 6.800403 (+2.758064) | 8.783854 (+3.562500) |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (+0) | 8473 (+1629) | 858 (+0) | 7615 (+1629) | 0.101263 (-0.024102) | 0.898737 (+0.024102) | 1.234411 (+0.237325) | 18.912946 (+3.636160) |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 9366 (+1820) | 852 (+0) | 8514 (+1820) | 0.090967 (-0.021941) | 0.909033 (+0.021941) | 1.374120 (+0.267019) | 18.292969 (+3.554688) |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (+0) | 2404 (+531) | 228 (+0) | 2176 (+531) | 0.094842 (-0.026888) | 0.905158 (+0.026888) | 1.317982 (+0.291118) | 18.781250 (+4.148438) |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 5340 (+917) | 577 (+0) | 4763 (+917) | 0.108052 (-0.022402) | 0.891948 (+0.022402) | 1.156846 (+0.198657) | 20.859375 (+3.582031) |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (+0) | 3451 (+1440) | 63 (+0) | 3388 (+1440) | 0.018256 (-0.013072) | 0.981744 (+0.013072) | 6.847222 (+2.857143) | 8.986979 (+3.750000) |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 576 (+0) | 4458 (+1819) | 72 (+0) | 4386 (+1819) | 0.016151 (-0.011132) | 0.983849 (+0.011132) | 7.739583 (+3.157986) | 8.707031 (+3.552734) |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 12519 (+2350) | 1218 (+0) | 11301 (+2350) | 0.097292 (-0.022484) | 0.902708 (+0.022484) | 1.284791 (+0.241174) | 19.560938 (+3.671876) |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 720 (+0) | 6631 (+2728) | 90 (+0) | 6541 (+2728) | 0.013573 (-0.009486) | 0.986427 (+0.009486) | 9.209722 (+3.788889) | 8.634115 (+3.552084) |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 15201 (+3256) | 1331 (+0) | 13870 (+3256) | 0.087560 (-0.023867) | 0.912440 (+0.023867) | 1.427592 (+0.305785) | 16.965402 (+3.633929) |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 872 (+0) | 8802 (+3637) | 109 (+0) | 8693 (+3637) | 0.012384 (-0.008720) | 0.987616 (+0.008720) | 10.094037 (+4.170872) | 8.595703 (+3.551758) |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 4197 (+795) | 442 (+0) | 3755 (+795) | 0.105313 (-0.024611) | 0.894687 (+0.024611) | 1.186934 (+0.224830) | 21.859375 (+4.140625) |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 5012 (+1366) | 341 (+0) | 4671 (+1366) | 0.068037 (-0.025490) | 0.931963 (+0.025490) | 1.837243 (+0.500733) | 13.052083 (+3.557291) |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 9838 (+2156) | 875 (+0) | 8963 (+2156) | 0.088941 (-0.024962) | 0.911059 (+0.024962) | 1.405429 (+0.308000) | 17.079861 (+3.743055) |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 16488 (+2729) | 1833 (+0) | 14655 (+2729) | 0.111172 (-0.022050) | 0.888828 (+0.022050) | 1.124386 (+0.186102) | 21.468750 (+3.553385) |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 18791 (+3519) | 1920 (+0) | 16871 (+3519) | 0.102177 (-0.023543) | 0.897823 (+0.023543) | 1.223372 (+0.229101) | 19.573958 (+3.665625) |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 944 (+0) | 9879 (+4092) | 118 (+0) | 9761 (+4092) | 0.011945 (-0.008446) | 0.988055 (+0.008446) | 10.465042 (+4.334745) | 8.575521 (+3.552083) |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1048 (+0) | 11625 (+4882) | 131 (+0) | 11494 (+4882) | 0.011269 (-0.008159) | 0.988731 (+0.008159) | 11.092557 (+4.658397) | 8.649554 (+3.632441) |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 29253 (+5453) | 2915 (+0) | 26338 (+5453) | 0.099648 (-0.022831) | 0.900352 (+0.022831) | 1.254417 (+0.233834) | 19.044922 (+3.550130) |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 4327 (+1058) | 377 (+0) | 3950 (+1058) | 0.087127 (-0.028199) | 0.912873 (+0.028199) | 1.434682 (+0.350796) | 16.902344 (+4.132813) |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (+0) | 5121 (+1821) | 176 (+0) | 4945 (+1821) | 0.034368 (-0.018965) | 0.965632 (+0.018965) | 3.637074 (+1.293324) | 10.001953 (+3.556641) |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1808 (+0) | 7594 (+2873) | 226 (+0) | 7368 (+2873) | 0.029760 (-0.018111) | 0.970240 (+0.018111) | 4.200221 (+1.589048) | 9.888021 (+3.740886) |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11152 (+0) | 16170 (+3638) | 1394 (+0) | 14776 (+3638) | 0.086209 (-0.025026) | 0.913791 (+0.025026) | 1.449964 (+0.326219) | 15.791016 (+3.552735) |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1008 (+0) | 11114 (+4690) | 126 (+0) | 10988 (+4690) | 0.011337 (-0.008277) | 0.988663 (+0.008277) | 11.025794 (+4.652778) | 8.682813 (+3.664063) |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 29239 (+5452) | 2772 (+0) | 26467 (+5452) | 0.094805 (-0.021729) | 0.905195 (+0.021729) | 1.318497 (+0.245851) | 19.035807 (+3.549479) |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 34368 (+6503) | 3408 (+0) | 30960 (+6503) | 0.099162 (-0.023142) | 0.900838 (+0.023142) | 1.260563 (+0.238519) | 19.178571 (+3.628906) |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1456 (+0) | 17472 (+7270) | 182 (+0) | 17290 (+7270) | 0.010417 (-0.007423) | 0.989583 (+0.007423) | 12.000000 (+4.993132) | 8.531250 (+3.549805) |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 6996 (+1320) | 744 (+0) | 6252 (+1320) | 0.106346 (-0.024732) | 0.893654 (+0.024732) | 1.175403 (+0.221774) | 21.862500 (+4.125000) |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 14566 (+2276) | 1655 (+0) | 12911 (+2276) | 0.113621 (-0.021041) | 0.886379 (+0.021041) | 1.100151 (+0.171903) | 22.759375 (+3.556250) |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1792 (+0) | 9232 (+3589) | 224 (+0) | 9008 (+3589) | 0.024263 (-0.015432) | 0.975737 (+0.015432) | 5.151786 (+2.002790) | 9.616667 (+3.738542) |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (+0) | 25945 (+4545) | 2729 (+0) | 23216 (+4545) | 0.105184 (-0.022339) | 0.894816 (+0.022339) | 1.188393 (+0.208180) | 20.269531 (+3.550781) |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22480 (+0) | 29086 (+5861) | 2810 (+0) | 26276 (+5861) | 0.096610 (-0.024380) | 0.903390 (+0.024380) | 1.293861 (+0.260720) | 18.178750 (+3.663125) |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (+0) | 17045 (+6813) | 269 (+0) | 16776 (+6813) | 0.015782 (-0.010508) | 0.984218 (+0.010508) | 7.920539 (+3.165892) | 8.877604 (+3.548437) |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20944 (+0) | 33273 (+8131) | 2618 (+0) | 30655 (+8131) | 0.078682 (-0.025447) | 0.921318 (+0.025447) | 1.588665 (+0.388226) | 14.854018 (+3.629911) |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2016 (+0) | 21981 (+9086) | 252 (+0) | 21729 (+9086) | 0.011464 (-0.008078) | 0.988536 (+0.008078) | 10.903274 (+4.506945) | 8.586328 (+3.549219) |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 3791 (+1582) | 83 (+0) | 3708 (+1582) | 0.021894 (-0.015680) | 0.978106 (+0.015680) | 5.709337 (+2.382530) | 9.872396 (+4.119792) |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (+0) | 17758 (+2730) | 1982 (+0) | 15776 (+2730) | 0.111612 (-0.020275) | 0.888388 (+0.020275) | 1.119955 (+0.172175) | 23.122396 (+3.554688) |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15152 (+0) | 20339 (+4307) | 1894 (+0) | 18445 (+4307) | 0.093122 (-0.025017) | 0.906878 (+0.025017) | 1.342331 (+0.284253) | 17.655382 (+3.738715) |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15832 (+0) | 23629 (+5454) | 1979 (+0) | 21650 (+5454) | 0.083753 (-0.025133) | 0.916247 (+0.025133) | 1.492484 (+0.344493) | 15.383464 (+3.550782) |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30400 (+0) | 37011 (+7030) | 3800 (+0) | 33211 (+7030) | 0.102672 (-0.024075) | 0.897328 (+0.024075) | 1.217467 (+0.231250) | 19.276563 (+3.661459) |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1600 (+0) | 19633 (+8175) | 200 (+0) | 19433 (+8175) | 0.010187 (-0.007268) | 0.989813 (+0.007268) | 12.270625 (+5.109375) | 8.521267 (+3.548177) |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13560 (+0) | 32313 (+9754) | 1695 (+0) | 30618 (+9754) | 0.052456 (-0.022680) | 0.947544 (+0.022680) | 2.382965 (+0.719322) | 12.021205 (+3.628720) |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2304 (+0) | 26332 (+10900) | 288 (+0) | 26044 (+10900) | 0.010937 (-0.007726) | 0.989063 (+0.007726) | 11.428819 (+4.730902) | 8.571615 (+3.548177) |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (+0) | 8649 (+1846) | 869 (+0) | 7780 (+1846) | 0.100474 (-0.027264) | 0.899526 (+0.027264) | 1.244102 (+0.265535) | 19.305804 (+4.120536) |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9864 (+0) | 14497 (+3182) | 1233 (+0) | 13264 (+3182) | 0.085052 (-0.023918) | 0.914948 (+0.023918) | 1.469688 (+0.322587) | 16.179688 (+3.551340) |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 12088 (+0) | 19864 (+5024) | 1511 (+0) | 18353 (+5024) | 0.076067 (-0.025752) | 0.923933 (+0.025752) | 1.643283 (+0.415619) | 14.779762 (+3.738095) |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 19168 (+0) | 28137 (+6360) | 2396 (+0) | 25741 (+6360) | 0.085155 (-0.024869) | 0.914845 (+0.024869) | 1.467915 (+0.331803) | 15.701451 (+3.549107) |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37216 (+0) | 44710 (+8202) | 4652 (+0) | 40058 (+8202) | 0.104048 (-0.023376) | 0.895952 (+0.023376) | 1.201365 (+0.220389) | 19.959821 (+3.661607) |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27016 (+0) | 40947 (+9540) | 3377 (+0) | 37570 (+9540) | 0.082472 (-0.025052) | 0.917528 (+0.025052) | 1.515657 (+0.353124) | 15.233259 (+3.549107) |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+0) | 67227 (+11381) | 7220 (+0) | 60007 (+11381) | 0.107397 (-0.021887) | 0.892603 (+0.021887) | 1.163902 (+0.197039) | 21.437181 (+3.629145) |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 29264 (+0) | 49906 (+12715) | 3658 (+0) | 46248 (+12715) | 0.073298 (-0.025059) | 0.926702 (+0.025059) | 1.705372 (+0.434493) | 13.924665 (+3.547712) |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (+0) | 8389 (+2108) | 668 (+0) | 7721 (+2108) | 0.079628 (-0.026724) | 0.920372 (+0.026724) | 1.569798 (+0.394461) | 16.384766 (+4.117188) |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (+0) | 19199 (+3635) | 1931 (+0) | 17268 (+3635) | 0.100578 (-0.023490) | 0.899422 (+0.023490) | 1.242815 (+0.235306) | 18.749023 (+3.549804) |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13744 (+0) | 22525 (+5742) | 1718 (+0) | 20807 (+5742) | 0.076271 (-0.026094) | 0.923729 (+0.026094) | 1.638897 (+0.417782) | 14.664714 (+3.738282) |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32136 (+0) | 39700 (+7270) | 4017 (+0) | 35683 (+7270) | 0.101184 (-0.022683) | 0.898816 (+0.022683) | 1.235375 (+0.226226) | 19.384766 (+3.549805) |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2856 (+0) | 22956 (+9373) | 357 (+0) | 22599 (+9373) | 0.015551 (-0.010732) | 0.984449 (+0.010732) | 8.037815 (+3.281863) | 8.967187 (+3.661328) |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50264 (+0) | 60471 (+10899) | 6283 (+0) | 54188 (+10899) | 0.103901 (-0.022844) | 0.896099 (+0.022844) | 1.203068 (+0.216835) | 19.684570 (+3.547851) |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3840 (+0) | 31957 (+13004) | 480 (+0) | 31477 (+13004) | 0.015020 (-0.010306) | 0.984980 (+0.010306) | 8.322135 (+3.386458) | 8.916574 (+3.628349) |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76656 (+0) | 89020 (+14533) | 9582 (+0) | 79438 (+14533) | 0.107639 (-0.021001) | 0.892361 (+0.021001) | 1.161292 (+0.189587) | 21.733398 (+3.548095) |

### Screenshot Multi-CTU And Partial Crops

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 89904 (+0) | 129718 (+29061) | 11238 (+0) | 118480 (+29061) | 0.086634 (-0.025012) | 0.913366 (+0.025012) | 1.442850 (+0.323245) | 15.834717 (+3.547486) |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 46184 (+0) | 99550 (+29059) | 5773 (+0) | 93777 (+29059) | 0.057991 (-0.023906) | 0.942009 (+0.023906) | 2.155508 (+0.629200) | 12.152100 (+3.547242) |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 16384 (+0) | 144051 (+58118) | 2048 (+0) | 142003 (+58118) | 0.014217 (-0.009616) | 0.985783 (+0.009616) | 8.792175 (+3.547241) | 8.792175 (+3.547241) |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 48696 (+0) | 135186 (+43587) | 6087 (+0) | 129099 (+43587) | 0.045027 (-0.021426) | 0.954973 (+0.021426) | 2.776121 (+0.895084) | 11.001465 (+3.547119) |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 104056 (+0) | 173190 (+43587) | 13007 (+0) | 160183 (+43587) | 0.075102 (-0.025258) | 0.924898 (+0.025258) | 1.664392 (+0.418880) | 14.094238 (+3.547119) |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 61016 (+0) | 81376 (+16923) | 7627 (+0) | 73749 (+16923) | 0.093725 (-0.024609) | 0.906275 (+0.024609) | 1.333683 (+0.277354) | 17.659722 (+3.672526) |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3096 (+0) | 39255 (+16351) | 387 (+0) | 38868 (+16351) | 0.009859 (-0.007038) | 0.990141 (+0.007038) | 12.679264 (+5.281331) | 8.518880 (+3.548394) |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4488 (+0) | 45529 (+19041) | 561 (+0) | 44968 (+19041) | 0.012322 (-0.008857) | 0.987678 (+0.008857) | 10.144608 (+4.242647) | 8.782600 (+3.673032) |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136880 (+0) | 186132 (+39674) | 17110 (+0) | 169022 (+39674) | 0.091924 (-0.024901) | 0.908076 (+0.024901) | 1.359819 (+0.289845) | 17.107721 (+3.646508) |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 81304 (+0) | 134292 (+33846) | 10163 (+0) | 124129 (+33846) | 0.075678 (-0.025501) | 0.924322 (+0.025501) | 1.651727 (+0.416290) | 14.571615 (+3.672526) |
