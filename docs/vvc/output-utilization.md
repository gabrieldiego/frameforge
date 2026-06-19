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
- This is the first detailed VVC utilization baseline for the local screenshot
  and RaceHorses crop sets. Delta fields are marked `baseline`; future reports
  should replace them with numeric deltas against these per-vector rows.

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

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) | Cycles/pixel range |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| screenshot-sweep-444 | 64 (baseline) | 398840 (baseline) | 1581091 (baseline) | 49855 (baseline) | 1531236 (baseline) | 0.031532 (baseline) | 0.968468 (baseline) | 3.964224 (baseline) | 19.062150 (baseline) | 9.565430-35.325521 (baseline) |
| screenshot-multictu-444 | 10 (baseline) | 319168 (baseline) | 1483255 (baseline) | 39896 (baseline) | 1443359 (baseline) | 0.026898 (baseline) | 0.973102 (baseline) | 4.647255 (baseline) | 16.150425 (baseline) | 9.439019-22.691176 (baseline) |
| racehorses-sweep-420 | 64 (baseline) | 113168 (baseline) | 1170183 (baseline) | 14146 (baseline) | 1156037 (baseline) | 0.012089 (baseline) | 0.987911 (baseline) | 10.340229 (baseline) | 14.108109 (baseline) | 13.618490-23.859375 (baseline) |
| racehorses-multictu-420 | 10 (baseline) | 92920 (baseline) | 1251691 (baseline) | 11615 (baseline) | 1240076 (baseline) | 0.009279 (baseline) | 0.990721 (baseline) | 13.470631 (baseline) | 13.629040 (baseline) | 13.277018-14.036265 (baseline) |

### 4:4:4 Screenshot Full Sweep

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (baseline) | 1246 (baseline) | 67 (baseline) | 1179 (baseline) | 0.053772 (baseline) | 0.946228 (baseline) | 2.324627 (baseline) | 19.468750 (baseline) |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (baseline) | 3066 (baseline) | 122 (baseline) | 2944 (baseline) | 0.039791 (baseline) | 0.960209 (baseline) | 3.141393 (baseline) | 23.953125 (baseline) |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 600 (baseline) | 2443 (baseline) | 75 (baseline) | 2368 (baseline) | 0.030700 (baseline) | 0.969300 (baseline) | 4.071667 (baseline) | 12.723958 (baseline) |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 816 (baseline) | 4365 (baseline) | 102 (baseline) | 4263 (baseline) | 0.023368 (baseline) | 0.976632 (baseline) | 5.349265 (baseline) | 17.050781 (baseline) |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 680 (baseline) | 3649 (baseline) | 85 (baseline) | 3564 (baseline) | 0.023294 (baseline) | 0.976706 (baseline) | 5.366176 (baseline) | 11.403125 (baseline) |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 712 (baseline) | 4205 (baseline) | 89 (baseline) | 4116 (baseline) | 0.021165 (baseline) | 0.978835 (baseline) | 5.905899 (baseline) | 10.950521 (baseline) |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (baseline) | 13473 (baseline) | 586 (baseline) | 12887 (baseline) | 0.043494 (baseline) | 0.956506 (baseline) | 2.873933 (baseline) | 30.073661 (baseline) |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (baseline) | 13678 (baseline) | 543 (baseline) | 13135 (baseline) | 0.039699 (baseline) | 0.960301 (baseline) | 3.148711 (baseline) | 26.714844 (baseline) |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (baseline) | 3353 (baseline) | 139 (baseline) | 3214 (baseline) | 0.041455 (baseline) | 0.958545 (baseline) | 3.015288 (baseline) | 26.195312 (baseline) |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (baseline) | 6492 (baseline) | 280 (baseline) | 6212 (baseline) | 0.043130 (baseline) | 0.956870 (baseline) | 2.898214 (baseline) | 25.359375 (baseline) |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 712 (baseline) | 4339 (baseline) | 89 (baseline) | 4250 (baseline) | 0.020512 (baseline) | 0.979488 (baseline) | 6.094101 (baseline) | 11.299479 (baseline) |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 784 (baseline) | 5350 (baseline) | 98 (baseline) | 5252 (baseline) | 0.018318 (baseline) | 0.981682 (baseline) | 6.823980 (baseline) | 10.449219 (baseline) |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (baseline) | 18615 (baseline) | 766 (baseline) | 17849 (baseline) | 0.041150 (baseline) | 0.958850 (baseline) | 3.037696 (baseline) | 29.085938 (baseline) |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 912 (baseline) | 7726 (baseline) | 114 (baseline) | 7612 (baseline) | 0.014755 (baseline) | 0.985245 (baseline) | 8.471491 (baseline) | 10.059896 (baseline) |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6200 (baseline) | 21277 (baseline) | 775 (baseline) | 20502 (baseline) | 0.036424 (baseline) | 0.963576 (baseline) | 3.431774 (baseline) | 23.746652 (baseline) |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 1048 (baseline) | 10105 (baseline) | 131 (baseline) | 9974 (baseline) | 0.012964 (baseline) | 0.987036 (baseline) | 9.642176 (baseline) | 9.868164 (baseline) |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (baseline) | 6031 (baseline) | 288 (baseline) | 5743 (baseline) | 0.047753 (baseline) | 0.952247 (baseline) | 2.617622 (baseline) | 31.411458 (baseline) |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1496 (baseline) | 6522 (baseline) | 187 (baseline) | 6335 (baseline) | 0.028672 (baseline) | 0.971328 (baseline) | 4.359626 (baseline) | 16.984375 (baseline) |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2952 (baseline) | 11571 (baseline) | 369 (baseline) | 11202 (baseline) | 0.031890 (baseline) | 0.968110 (baseline) | 3.919715 (baseline) | 20.088542 (baseline) |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (baseline) | 22850 (baseline) | 973 (baseline) | 21877 (baseline) | 0.042582 (baseline) | 0.957418 (baseline) | 2.935509 (baseline) | 29.752604 (baseline) |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6080 (baseline) | 22090 (baseline) | 760 (baseline) | 21330 (baseline) | 0.034405 (baseline) | 0.965595 (baseline) | 3.633224 (baseline) | 23.010417 (baseline) |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 1112 (baseline) | 11297 (baseline) | 139 (baseline) | 11158 (baseline) | 0.012304 (baseline) | 0.987696 (baseline) | 10.159173 (baseline) | 9.806424 (baseline) |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1208 (baseline) | 13427 (baseline) | 151 (baseline) | 13276 (baseline) | 0.011246 (baseline) | 0.988754 (baseline) | 11.115066 (baseline) | 9.990327 (baseline) |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11328 (baseline) | 37708 (baseline) | 1416 (baseline) | 36292 (baseline) | 0.037552 (baseline) | 0.962448 (baseline) | 3.328743 (baseline) | 24.549479 (baseline) |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1512 (baseline) | 5170 (baseline) | 189 (baseline) | 4981 (baseline) | 0.036557 (baseline) | 0.963443 (baseline) | 3.419312 (baseline) | 20.195312 (baseline) |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1376 (baseline) | 7518 (baseline) | 172 (baseline) | 7346 (baseline) | 0.022878 (baseline) | 0.977122 (baseline) | 5.463663 (baseline) | 14.683594 (baseline) |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1544 (baseline) | 10082 (baseline) | 193 (baseline) | 9889 (baseline) | 0.019143 (baseline) | 0.980857 (baseline) | 6.529793 (baseline) | 13.127604 (baseline) |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4440 (baseline) | 18571 (baseline) | 555 (baseline) | 18016 (baseline) | 0.029885 (baseline) | 0.970115 (baseline) | 4.182658 (baseline) | 18.135742 (baseline) |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1192 (baseline) | 12984 (baseline) | 149 (baseline) | 12835 (baseline) | 0.011476 (baseline) | 0.988524 (baseline) | 10.892617 (baseline) | 10.143750 (baseline) |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 13096 (baseline) | 41752 (baseline) | 1637 (baseline) | 40115 (baseline) | 0.039208 (baseline) | 0.960792 (baseline) | 3.188149 (baseline) | 27.182292 (baseline) |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 12696 (baseline) | 43716 (baseline) | 1587 (baseline) | 42129 (baseline) | 0.036302 (baseline) | 0.963698 (baseline) | 3.443289 (baseline) | 24.395089 (baseline) |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1576 (baseline) | 19590 (baseline) | 197 (baseline) | 19393 (baseline) | 0.010056 (baseline) | 0.989944 (baseline) | 12.430203 (baseline) | 9.565430 (baseline) |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (baseline) | 9589 (baseline) | 385 (baseline) | 9204 (baseline) | 0.040150 (baseline) | 0.959850 (baseline) | 3.113312 (baseline) | 29.965625 (baseline) |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (baseline) | 18127 (baseline) | 737 (baseline) | 17390 (baseline) | 0.040658 (baseline) | 0.959342 (baseline) | 3.074457 (baseline) | 28.323438 (baseline) |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1344 (baseline) | 11808 (baseline) | 168 (baseline) | 11640 (baseline) | 0.014228 (baseline) | 0.985772 (baseline) | 8.785714 (baseline) | 12.300000 (baseline) |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (baseline) | 33173 (baseline) | 1263 (baseline) | 31910 (baseline) | 0.038073 (baseline) | 0.961927 (baseline) | 3.283155 (baseline) | 25.916406 (baseline) |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 11616 (baseline) | 39688 (baseline) | 1452 (baseline) | 38236 (baseline) | 0.036585 (baseline) | 0.963415 (baseline) | 3.416667 (baseline) | 24.805000 (baseline) |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2720 (baseline) | 23930 (baseline) | 340 (baseline) | 23590 (baseline) | 0.014208 (baseline) | 0.985792 (baseline) | 8.797794 (baseline) | 12.463542 (baseline) |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10552 (baseline) | 42743 (baseline) | 1319 (baseline) | 41424 (baseline) | 0.030859 (baseline) | 0.969141 (baseline) | 4.050701 (baseline) | 19.081696 (baseline) |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2152 (baseline) | 27041 (baseline) | 269 (baseline) | 26772 (baseline) | 0.009948 (baseline) | 0.990052 (baseline) | 12.565520 (baseline) | 10.562891 (baseline) |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 768 (baseline) | 4791 (baseline) | 96 (baseline) | 4695 (baseline) | 0.020038 (baseline) | 0.979962 (baseline) | 6.238281 (baseline) | 12.476562 (baseline) |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (baseline) | 27130 (baseline) | 1224 (baseline) | 25906 (baseline) | 0.045116 (baseline) | 0.954884 (baseline) | 2.770629 (baseline) | 35.325521 (baseline) |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7256 (baseline) | 26132 (baseline) | 907 (baseline) | 25225 (baseline) | 0.034708 (baseline) | 0.965292 (baseline) | 3.601433 (baseline) | 22.684028 (baseline) |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7728 (baseline) | 31047 (baseline) | 966 (baseline) | 30081 (baseline) | 0.031114 (baseline) | 0.968886 (baseline) | 4.017469 (baseline) | 20.212891 (baseline) |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14960 (baseline) | 49274 (baseline) | 1870 (baseline) | 47404 (baseline) | 0.037951 (baseline) | 0.962049 (baseline) | 3.293717 (baseline) | 25.663542 (baseline) |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1720 (baseline) | 22095 (baseline) | 215 (baseline) | 21880 (baseline) | 0.009731 (baseline) | 0.990269 (baseline) | 12.845930 (baseline) | 9.589844 (baseline) |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10256 (baseline) | 47790 (baseline) | 1282 (baseline) | 46508 (baseline) | 0.026826 (baseline) | 0.973174 (baseline) | 4.659711 (baseline) | 17.779018 (baseline) |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2408 (baseline) | 31756 (baseline) | 301 (baseline) | 31455 (baseline) | 0.009479 (baseline) | 0.990521 (baseline) | 13.187708 (baseline) | 10.337240 (baseline) |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (baseline) | 11668 (baseline) | 454 (baseline) | 11214 (baseline) | 0.038910 (baseline) | 0.961090 (baseline) | 3.212555 (baseline) | 26.044643 (baseline) |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5496 (baseline) | 20027 (baseline) | 687 (baseline) | 19340 (baseline) | 0.034304 (baseline) | 0.965696 (baseline) | 3.643923 (baseline) | 22.351562 (baseline) |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 6280 (baseline) | 25743 (baseline) | 785 (baseline) | 24958 (baseline) | 0.030494 (baseline) | 0.969506 (baseline) | 4.099204 (baseline) | 19.154018 (baseline) |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9936 (baseline) | 36198 (baseline) | 1242 (baseline) | 34956 (baseline) | 0.034311 (baseline) | 0.965689 (baseline) | 3.643116 (baseline) | 20.199777 (baseline) |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17888 (baseline) | 58266 (baseline) | 2236 (baseline) | 56030 (baseline) | 0.038376 (baseline) | 0.961624 (baseline) | 3.257267 (baseline) | 26.011607 (baseline) |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 13432 (baseline) | 53404 (baseline) | 1679 (baseline) | 51725 (baseline) | 0.031440 (baseline) | 0.968560 (baseline) | 3.975878 (baseline) | 19.867560 (baseline) |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25480 (baseline) | 83439 (baseline) | 3185 (baseline) | 80254 (baseline) | 0.038172 (baseline) | 0.961828 (baseline) | 3.274686 (baseline) | 26.606824 (baseline) |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 14792 (baseline) | 65208 (baseline) | 1849 (baseline) | 63359 (baseline) | 0.028355 (baseline) | 0.971645 (baseline) | 4.408329 (baseline) | 18.194196 (baseline) |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (baseline) | 10141 (baseline) | 293 (baseline) | 9848 (baseline) | 0.028893 (baseline) | 0.971107 (baseline) | 4.326365 (baseline) | 19.806641 (baseline) |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8768 (baseline) | 27884 (baseline) | 1096 (baseline) | 26788 (baseline) | 0.039306 (baseline) | 0.960694 (baseline) | 3.180201 (baseline) | 27.230469 (baseline) |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 7088 (baseline) | 28498 (baseline) | 886 (baseline) | 27612 (baseline) | 0.031090 (baseline) | 0.968910 (baseline) | 4.020598 (baseline) | 18.553385 (baseline) |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14128 (baseline) | 47972 (baseline) | 1766 (baseline) | 46206 (baseline) | 0.036813 (baseline) | 0.963187 (baseline) | 3.395527 (baseline) | 23.423828 (baseline) |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2440 (baseline) | 27908 (baseline) | 305 (baseline) | 27603 (baseline) | 0.010929 (baseline) | 0.989071 (baseline) | 11.437705 (baseline) | 10.901563 (baseline) |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23176 (baseline) | 76740 (baseline) | 2897 (baseline) | 73843 (baseline) | 0.037751 (baseline) | 0.962249 (baseline) | 3.311184 (baseline) | 24.980469 (baseline) |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3952 (baseline) | 39997 (baseline) | 494 (baseline) | 39503 (baseline) | 0.012351 (baseline) | 0.987649 (baseline) | 10.120698 (baseline) | 11.159877 (baseline) |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33472 (baseline) | 107623 (baseline) | 4184 (baseline) | 103439 (baseline) | 0.038876 (baseline) | 0.961124 (baseline) | 3.215314 (baseline) | 26.275146 (baseline) |

### 4:4:4 Screenshot Multi-CTU And Partial Crops

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 48360 (baseline) | 171810 (baseline) | 6045 (baseline) | 165765 (baseline) | 0.035184 (baseline) | 0.964816 (baseline) | 3.552730 (baseline) | 20.972900 (baseline) |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 22256 (baseline) | 118681 (baseline) | 2782 (baseline) | 115899 (baseline) | 0.023441 (baseline) | 0.976559 (baseline) | 5.332540 (baseline) | 14.487427 (baseline) |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 13888 (baseline) | 170043 (baseline) | 1736 (baseline) | 168307 (baseline) | 0.010209 (baseline) | 0.989791 (baseline) | 12.243880 (baseline) | 10.378601 (baseline) |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 37776 (baseline) | 187268 (baseline) | 4722 (baseline) | 182546 (baseline) | 0.025215 (baseline) | 0.974785 (baseline) | 4.957327 (baseline) | 15.239909 (baseline) |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 52832 (baseline) | 217974 (baseline) | 6604 (baseline) | 211370 (baseline) | 0.030297 (baseline) | 0.969703 (baseline) | 4.125795 (baseline) | 17.738770 (baseline) |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 28096 (baseline) | 102144 (baseline) | 3512 (baseline) | 98632 (baseline) | 0.034383 (baseline) | 0.965617 (baseline) | 3.635535 (baseline) | 22.166667 (baseline) |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3024 (baseline) | 43495 (baseline) | 378 (baseline) | 43117 (baseline) | 0.008691 (baseline) | 0.991309 (baseline) | 14.383267 (baseline) | 9.439019 (baseline) |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3904 (baseline) | 53672 (baseline) | 488 (baseline) | 53184 (baseline) | 0.009092 (baseline) | 0.990908 (baseline) | 13.747951 (baseline) | 10.353395 (baseline) |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 67400 (baseline) | 246880 (baseline) | 8425 (baseline) | 238455 (baseline) | 0.034126 (baseline) | 0.965874 (baseline) | 3.662908 (baseline) | 22.691176 (baseline) |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 41632 (baseline) | 171288 (baseline) | 5204 (baseline) | 166084 (baseline) | 0.030382 (baseline) | 0.969618 (baseline) | 4.114335 (baseline) | 18.585938 (baseline) |

### 4:2:0 RaceHorses Full Sweep

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 (baseline) | 1527 (baseline) | 71 (baseline) | 1456 (baseline) | 0.046496 (baseline) | 0.953504 (baseline) | 2.688380 (baseline) | 23.859375 (baseline) |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 (baseline) | 2456 (baseline) | 84 (baseline) | 2372 (baseline) | 0.034202 (baseline) | 0.965798 (baseline) | 3.654762 (baseline) | 19.187500 (baseline) |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 (baseline) | 3291 (baseline) | 90 (baseline) | 3201 (baseline) | 0.027347 (baseline) | 0.972653 (baseline) | 4.570833 (baseline) | 17.140625 (baseline) |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 (baseline) | 4126 (baseline) | 101 (baseline) | 4025 (baseline) | 0.024479 (baseline) | 0.975521 (baseline) | 5.106436 (baseline) | 16.117188 (baseline) |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 (baseline) | 5075 (baseline) | 109 (baseline) | 4966 (baseline) | 0.021478 (baseline) | 0.978522 (baseline) | 5.819954 (baseline) | 15.859375 (baseline) |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 (baseline) | 6002 (baseline) | 120 (baseline) | 5882 (baseline) | 0.019993 (baseline) | 0.980007 (baseline) | 6.252083 (baseline) | 15.630208 (baseline) |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 (baseline) | 6823 (baseline) | 127 (baseline) | 6696 (baseline) | 0.018614 (baseline) | 0.981386 (baseline) | 6.715551 (baseline) | 15.229911 (baseline) |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 (baseline) | 7776 (baseline) | 140 (baseline) | 7636 (baseline) | 0.018004 (baseline) | 0.981996 (baseline) | 6.942857 (baseline) | 15.187500 (baseline) |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 (baseline) | 2351 (baseline) | 77 (baseline) | 2274 (baseline) | 0.032752 (baseline) | 0.967248 (baseline) | 3.816558 (baseline) | 18.367188 (baseline) |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 (baseline) | 4138 (baseline) | 101 (baseline) | 4037 (baseline) | 0.024408 (baseline) | 0.975592 (baseline) | 5.121287 (baseline) | 16.164062 (baseline) |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (baseline) | 5907 (baseline) | 114 (baseline) | 5793 (baseline) | 0.019299 (baseline) | 0.980701 (baseline) | 6.476974 (baseline) | 15.382812 (baseline) |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 (baseline) | 7486 (baseline) | 130 (baseline) | 7356 (baseline) | 0.017366 (baseline) | 0.982634 (baseline) | 7.198077 (baseline) | 14.621094 (baseline) |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 (baseline) | 9479 (baseline) | 149 (baseline) | 9330 (baseline) | 0.015719 (baseline) | 0.984281 (baseline) | 7.952181 (baseline) | 14.810937 (baseline) |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 (baseline) | 11037 (baseline) | 161 (baseline) | 10876 (baseline) | 0.014587 (baseline) | 0.985413 (baseline) | 8.569099 (baseline) | 14.371094 (baseline) |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 (baseline) | 13059 (baseline) | 180 (baseline) | 12879 (baseline) | 0.013784 (baseline) | 0.986216 (baseline) | 9.068750 (baseline) | 14.574777 (baseline) |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 (baseline) | 14672 (baseline) | 200 (baseline) | 14472 (baseline) | 0.013631 (baseline) | 0.986369 (baseline) | 9.170000 (baseline) | 14.328125 (baseline) |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 (baseline) | 3272 (baseline) | 85 (baseline) | 3187 (baseline) | 0.025978 (baseline) | 0.974022 (baseline) | 4.811765 (baseline) | 17.041667 (baseline) |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 (baseline) | 5876 (baseline) | 115 (baseline) | 5761 (baseline) | 0.019571 (baseline) | 0.980429 (baseline) | 6.386957 (baseline) | 15.302083 (baseline) |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 (baseline) | 8514 (baseline) | 137 (baseline) | 8377 (baseline) | 0.016091 (baseline) | 0.983909 (baseline) | 7.768248 (baseline) | 14.781250 (baseline) |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 (baseline) | 11024 (baseline) | 164 (baseline) | 10860 (baseline) | 0.014877 (baseline) | 0.985123 (baseline) | 8.402439 (baseline) | 14.354167 (baseline) |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 (baseline) | 13974 (baseline) | 188 (baseline) | 13786 (baseline) | 0.013454 (baseline) | 0.986546 (baseline) | 9.291223 (baseline) | 14.556250 (baseline) |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 (baseline) | 16238 (baseline) | 209 (baseline) | 16029 (baseline) | 0.012871 (baseline) | 0.987129 (baseline) | 9.711722 (baseline) | 14.095486 (baseline) |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 (baseline) | 19232 (baseline) | 238 (baseline) | 18994 (baseline) | 0.012375 (baseline) | 0.987625 (baseline) | 10.100840 (baseline) | 14.309524 (baseline) |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 (baseline) | 21712 (baseline) | 261 (baseline) | 21451 (baseline) | 0.012021 (baseline) | 0.987979 (baseline) | 10.398467 (baseline) | 14.135417 (baseline) |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 (baseline) | 4187 (baseline) | 95 (baseline) | 4092 (baseline) | 0.022689 (baseline) | 0.977311 (baseline) | 5.509211 (baseline) | 16.355469 (baseline) |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 (baseline) | 7646 (baseline) | 133 (baseline) | 7513 (baseline) | 0.017395 (baseline) | 0.982605 (baseline) | 7.186090 (baseline) | 14.933594 (baseline) |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 (baseline) | 11208 (baseline) | 163 (baseline) | 11045 (baseline) | 0.014543 (baseline) | 0.985457 (baseline) | 8.595092 (baseline) | 14.593750 (baseline) |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 (baseline) | 14436 (baseline) | 193 (baseline) | 14243 (baseline) | 0.013369 (baseline) | 0.986631 (baseline) | 9.349741 (baseline) | 14.097656 (baseline) |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 (baseline) | 18332 (baseline) | 225 (baseline) | 18107 (baseline) | 0.012274 (baseline) | 0.987726 (baseline) | 10.184444 (baseline) | 14.321875 (baseline) |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 (baseline) | 21403 (baseline) | 252 (baseline) | 21151 (baseline) | 0.011774 (baseline) | 0.988226 (baseline) | 10.616567 (baseline) | 13.934245 (baseline) |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 (baseline) | 25357 (baseline) | 286 (baseline) | 25071 (baseline) | 0.011279 (baseline) | 0.988721 (baseline) | 11.082605 (baseline) | 14.150112 (baseline) |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 (baseline) | 28507 (baseline) | 313 (baseline) | 28194 (baseline) | 0.010980 (baseline) | 0.989020 (baseline) | 11.384585 (baseline) | 13.919434 (baseline) |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 (baseline) | 4983 (baseline) | 99 (baseline) | 4884 (baseline) | 0.019868 (baseline) | 0.980132 (baseline) | 6.291667 (baseline) | 15.571875 (baseline) |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 (baseline) | 9272 (baseline) | 144 (baseline) | 9128 (baseline) | 0.015531 (baseline) | 0.984469 (baseline) | 8.048611 (baseline) | 14.487500 (baseline) |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 (baseline) | 13785 (baseline) | 180 (baseline) | 13605 (baseline) | 0.013058 (baseline) | 0.986942 (baseline) | 9.572917 (baseline) | 14.359375 (baseline) |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 (baseline) | 17952 (baseline) | 218 (baseline) | 17734 (baseline) | 0.012143 (baseline) | 0.987857 (baseline) | 10.293578 (baseline) | 14.025000 (baseline) |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 (baseline) | 22445 (baseline) | 259 (baseline) | 22186 (baseline) | 0.011539 (baseline) | 0.988461 (baseline) | 10.832529 (baseline) | 14.028125 (baseline) |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 (baseline) | 26554 (baseline) | 295 (baseline) | 26259 (baseline) | 0.011109 (baseline) | 0.988891 (baseline) | 11.251695 (baseline) | 13.830208 (baseline) |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 (baseline) | 31360 (baseline) | 334 (baseline) | 31026 (baseline) | 0.010651 (baseline) | 0.989349 (baseline) | 11.736527 (baseline) | 14.000000 (baseline) |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 (baseline) | 35344 (baseline) | 370 (baseline) | 34974 (baseline) | 0.010469 (baseline) | 0.989531 (baseline) | 11.940541 (baseline) | 13.806250 (baseline) |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 (baseline) | 5863 (baseline) | 106 (baseline) | 5757 (baseline) | 0.018079 (baseline) | 0.981921 (baseline) | 6.913915 (baseline) | 15.268229 (baseline) |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 (baseline) | 10988 (baseline) | 154 (baseline) | 10834 (baseline) | 0.014015 (baseline) | 0.985985 (baseline) | 8.918831 (baseline) | 14.307292 (baseline) |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 (baseline) | 16394 (baseline) | 201 (baseline) | 16193 (baseline) | 0.012261 (baseline) | 0.987739 (baseline) | 10.195274 (baseline) | 14.230903 (baseline) |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 (baseline) | 21215 (baseline) | 243 (baseline) | 20972 (baseline) | 0.011454 (baseline) | 0.988546 (baseline) | 10.913066 (baseline) | 13.811849 (baseline) |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 (baseline) | 26684 (baseline) | 284 (baseline) | 26400 (baseline) | 0.010643 (baseline) | 0.989357 (baseline) | 11.744718 (baseline) | 13.897917 (baseline) |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 (baseline) | 31575 (baseline) | 331 (baseline) | 31244 (baseline) | 0.010483 (baseline) | 0.989517 (baseline) | 11.924094 (baseline) | 13.704427 (baseline) |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 (baseline) | 37360 (baseline) | 375 (baseline) | 36985 (baseline) | 0.010037 (baseline) | 0.989963 (baseline) | 12.453333 (baseline) | 13.898810 (baseline) |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 (baseline) | 41836 (baseline) | 414 (baseline) | 41422 (baseline) | 0.009896 (baseline) | 0.990104 (baseline) | 12.631643 (baseline) | 13.618490 (baseline) |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 (baseline) | 6939 (baseline) | 121 (baseline) | 6818 (baseline) | 0.017438 (baseline) | 0.982562 (baseline) | 7.168388 (baseline) | 15.488839 (baseline) |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 (baseline) | 12901 (baseline) | 180 (baseline) | 12721 (baseline) | 0.013952 (baseline) | 0.986048 (baseline) | 8.959028 (baseline) | 14.398438 (baseline) |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 (baseline) | 19091 (baseline) | 227 (baseline) | 18864 (baseline) | 0.011890 (baseline) | 0.988110 (baseline) | 10.512665 (baseline) | 14.204613 (baseline) |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 (baseline) | 24842 (baseline) | 281 (baseline) | 24561 (baseline) | 0.011311 (baseline) | 0.988689 (baseline) | 11.050712 (baseline) | 13.862723 (baseline) |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 (baseline) | 31228 (baseline) | 329 (baseline) | 30899 (baseline) | 0.010535 (baseline) | 0.989465 (baseline) | 11.864742 (baseline) | 13.941071 (baseline) |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 (baseline) | 36874 (baseline) | 378 (baseline) | 36496 (baseline) | 0.010251 (baseline) | 0.989749 (baseline) | 12.193783 (baseline) | 13.718006 (baseline) |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 (baseline) | 43529 (baseline) | 425 (baseline) | 43104 (baseline) | 0.009764 (baseline) | 0.990236 (baseline) | 12.802647 (baseline) | 13.880421 (baseline) |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 (baseline) | 48887 (baseline) | 474 (baseline) | 48413 (baseline) | 0.009696 (baseline) | 0.990304 (baseline) | 12.892141 (baseline) | 13.640346 (baseline) |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 (baseline) | 7830 (baseline) | 131 (baseline) | 7699 (baseline) | 0.016731 (baseline) | 0.983269 (baseline) | 7.471374 (baseline) | 15.292969 (baseline) |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 (baseline) | 14621 (baseline) | 198 (baseline) | 14423 (baseline) | 0.013542 (baseline) | 0.986458 (baseline) | 9.230429 (baseline) | 14.278320 (baseline) |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 (baseline) | 21867 (baseline) | 253 (baseline) | 21614 (baseline) | 0.011570 (baseline) | 0.988430 (baseline) | 10.803854 (baseline) | 14.236328 (baseline) |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 (baseline) | 28396 (baseline) | 316 (baseline) | 28080 (baseline) | 0.011128 (baseline) | 0.988872 (baseline) | 11.232595 (baseline) | 13.865234 (baseline) |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 (baseline) | 35641 (baseline) | 364 (baseline) | 35277 (baseline) | 0.010213 (baseline) | 0.989787 (baseline) | 12.239354 (baseline) | 13.922266 (baseline) |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 (baseline) | 41931 (baseline) | 426 (baseline) | 41505 (baseline) | 0.010160 (baseline) | 0.989840 (baseline) | 12.303697 (baseline) | 13.649414 (baseline) |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 (baseline) | 49772 (baseline) | 485 (baseline) | 49287 (baseline) | 0.009744 (baseline) | 0.990256 (baseline) | 12.827835 (baseline) | 13.887277 (baseline) |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 (baseline) | 56101 (baseline) | 540 (baseline) | 55561 (baseline) | 0.009625 (baseline) | 0.990375 (baseline) | 12.986343 (baseline) | 13.696533 (baseline) |

### 4:2:0 RaceHorses Multi-CTU And Partial Crops

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 (baseline) | 112216 (baseline) | 1060 (baseline) | 111156 (baseline) | 0.009446 (baseline) | 0.990554 (baseline) | 13.233019 (baseline) | 13.698242 (baseline) |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 (baseline) | 111133 (baseline) | 1027 (baseline) | 110106 (baseline) | 0.009241 (baseline) | 0.990759 (baseline) | 13.526412 (baseline) | 13.566040 (baseline) |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 (baseline) | 220219 (baseline) | 1948 (baseline) | 218271 (baseline) | 0.008846 (baseline) | 0.991154 (baseline) | 14.131096 (baseline) | 13.441101 (baseline) |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 (baseline) | 168091 (baseline) | 1583 (baseline) | 166508 (baseline) | 0.009418 (baseline) | 0.990582 (baseline) | 13.273136 (baseline) | 13.679281 (baseline) |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 (baseline) | 163148 (baseline) | 1405 (baseline) | 161743 (baseline) | 0.008612 (baseline) | 0.991388 (baseline) | 14.514947 (baseline) | 13.277018 (baseline) |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 (baseline) | 64147 (baseline) | 632 (baseline) | 63515 (baseline) | 0.009852 (baseline) | 0.990148 (baseline) | 12.687302 (baseline) | 13.920790 (baseline) |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 (baseline) | 63525 (baseline) | 633 (baseline) | 62892 (baseline) | 0.009965 (baseline) | 0.990035 (baseline) | 12.544431 (baseline) | 13.785807 (baseline) |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 (baseline) | 72764 (baseline) | 739 (baseline) | 72025 (baseline) | 0.010156 (baseline) | 0.989844 (baseline) | 12.307848 (baseline) | 14.036265 (baseline) |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 (baseline) | 149476 (baseline) | 1408 (baseline) | 148068 (baseline) | 0.009420 (baseline) | 0.990580 (baseline) | 13.270241 (baseline) | 13.738603 (baseline) |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 (baseline) | 126972 (baseline) | 1180 (baseline) | 125792 (baseline) | 0.009293 (baseline) | 0.990707 (baseline) | 13.450424 (baseline) | 13.777344 (baseline) |

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
