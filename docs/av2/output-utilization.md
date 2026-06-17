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

## 2026-06-17 AV2 Screenshot Throughput Baseline

Source and validation context:

- Baseline Git SHA before instrumentation:
  `9f5c5411b522efe4a8ad6ff2de43bfc6069b7ef8`
- Current validated source Git SHA:
  `d20036a9923a7fbb4e84996fc7940f9665520f88`
- Codec: `av2`
- RTL top: `ff_av2_encoder`
- Output interface: one accepted byte per `m_axis_valid && m_axis_ready` cycle.
- Input pixel denominator: visible luma sample positions, matching the
  bitrate-report denominator.

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

### Full Screenshot Sweep

Aggregate RTL bits: `770848`.
Aggregate total cycles: `2353116`.
Aggregate output utilization: `0.040948`; bubble rate: `0.959052`.
Aggregate cycles/bit: `3.052633`; aggregate cycles/input pixel: `28.369936`.
Per-vector cycles/input pixel range: `13.494792` to `47.407552`.

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 | 1341 | 43 | 1298 | 0.032066 | 0.967934 | 3.898256 | 20.953125 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 | 4848 | 248 | 4600 | 0.051155 | 0.948845 | 2.443548 | 37.875000 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 392 | 2591 | 49 | 2542 | 0.018912 | 0.981088 | 6.609694 | 13.494792 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 712 | 3985 | 89 | 3896 | 0.022334 | 0.977666 | 5.596910 | 15.566406 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 456 | 4382 | 57 | 4325 | 0.013008 | 0.986992 | 9.609649 | 13.693750 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 496 | 5281 | 62 | 5219 | 0.011740 | 0.988260 | 10.647177 | 13.752604 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 | 17254 | 858 | 16396 | 0.049728 | 0.950272 | 2.513695 | 38.513393 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 | 18582 | 852 | 17730 | 0.045851 | 0.954149 | 2.726232 | 36.292969 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 | 4541 | 228 | 4313 | 0.050209 | 0.949791 | 2.489583 | 35.476562 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 | 10874 | 577 | 10297 | 0.053062 | 0.946938 | 2.355719 | 42.476562 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 | 5285 | 63 | 5222 | 0.011921 | 0.988079 | 10.486111 | 13.763021 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 576 | 7079 | 72 | 7007 | 0.010171 | 0.989829 | 12.289931 | 13.826172 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 | 24727 | 1218 | 23509 | 0.049258 | 0.950742 | 2.537664 | 38.635937 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 720 | 10675 | 90 | 10585 | 0.008431 | 0.991569 | 14.826389 | 13.899740 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 | 29925 | 1331 | 28594 | 0.044478 | 0.955522 | 2.810387 | 33.398438 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 872 | 14276 | 109 | 14167 | 0.007635 | 0.992365 | 16.371560 | 13.941406 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 | 8340 | 442 | 7898 | 0.052998 | 0.947002 | 2.358597 | 43.437500 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 | 9388 | 341 | 9047 | 0.036323 | 0.963677 | 3.441349 | 24.447917 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 | 18887 | 875 | 18012 | 0.046328 | 0.953672 | 2.698143 | 32.789931 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 | 34003 | 1833 | 32170 | 0.053907 | 0.946093 | 2.318808 | 44.274740 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 | 37492 | 1920 | 35572 | 0.051211 | 0.948789 | 2.440885 | 39.054167 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 944 | 16082 | 118 | 15964 | 0.007337 | 0.992663 | 17.036017 | 13.960069 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1048 | 18779 | 131 | 18648 | 0.006976 | 0.993024 | 17.918893 | 13.972470 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 | 58886 | 2915 | 55971 | 0.049502 | 0.950498 | 2.525129 | 38.337240 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 | 8191 | 377 | 7814 | 0.046026 | 0.953974 | 2.715849 | 31.996094 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 | 8953 | 176 | 8777 | 0.019658 | 0.980342 | 6.358665 | 17.486328 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1808 | 12495 | 226 | 12269 | 0.018087 | 0.981913 | 6.910951 | 16.269531 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11152 | 31070 | 1394 | 29676 | 0.044866 | 0.955134 | 2.786047 | 30.341797 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1008 | 17869 | 126 | 17743 | 0.007051 | 0.992949 | 17.727183 | 13.960156 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 | 58465 | 2772 | 55693 | 0.047413 | 0.952587 | 2.636409 | 38.063151 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 | 68807 | 3408 | 65399 | 0.049530 | 0.950470 | 2.523731 | 38.396763 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1456 | 28661 | 182 | 28479 | 0.006350 | 0.993650 | 19.684753 | 13.994629 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 | 13940 | 744 | 13196 | 0.053372 | 0.946628 | 2.342070 | 43.562500 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 | 30152 | 1655 | 28497 | 0.054889 | 0.945111 | 2.277341 | 47.112500 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1792 | 15481 | 224 | 15257 | 0.014469 | 0.985531 | 8.638951 | 16.126042 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 | 52800 | 2729 | 50071 | 0.051686 | 0.948314 | 2.418468 | 41.250000 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22480 | 58155 | 2810 | 55345 | 0.048319 | 0.951681 | 2.586966 | 36.346875 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 | 28687 | 269 | 28418 | 0.009377 | 0.990623 | 13.330390 | 14.941146 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20944 | 64059 | 2618 | 61441 | 0.040869 | 0.959131 | 3.058585 | 28.597768 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2016 | 36306 | 252 | 36054 | 0.006941 | 0.993059 | 18.008929 | 14.182031 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 | 6087 | 83 | 6004 | 0.013636 | 0.986364 | 9.167169 | 15.851562 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 | 36409 | 1982 | 34427 | 0.054437 | 0.945563 | 2.296229 | 47.407552 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15152 | 39598 | 1894 | 37704 | 0.047831 | 0.952169 | 2.613384 | 34.373264 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15832 | 46257 | 1979 | 44278 | 0.042783 | 0.957217 | 2.921741 | 30.115234 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30400 | 74987 | 3800 | 71187 | 0.050675 | 0.949325 | 2.466678 | 39.055729 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1600 | 32267 | 200 | 32067 | 0.006198 | 0.993802 | 20.166875 | 14.004774 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13560 | 59687 | 1695 | 57992 | 0.028398 | 0.971602 | 4.401696 | 22.204985 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2304 | 43489 | 288 | 43201 | 0.006622 | 0.993378 | 18.875434 | 14.156576 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 | 17098 | 869 | 16229 | 0.050825 | 0.949175 | 2.459436 | 38.165179 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9864 | 28282 | 1233 | 27049 | 0.043597 | 0.956403 | 2.867194 | 31.564732 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 12088 | 37611 | 1511 | 36100 | 0.040174 | 0.959826 | 3.111433 | 27.984375 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 19168 | 55040 | 2396 | 52644 | 0.043532 | 0.956468 | 2.871452 | 30.714286 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37216 | 91024 | 4652 | 86372 | 0.051107 | 0.948893 | 2.445830 | 40.635714 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27016 | 79759 | 3377 | 76382 | 0.042340 | 0.957660 | 2.952288 | 29.672247 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 | 136538 | 7220 | 129318 | 0.052879 | 0.947121 | 2.363885 | 43.538903 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 29264 | 95185 | 3658 | 91527 | 0.038430 | 0.961570 | 3.252631 | 26.558315 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 | 15564 | 668 | 14896 | 0.042920 | 0.957080 | 2.912425 | 30.398438 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 | 38889 | 1931 | 36958 | 0.049654 | 0.950346 | 2.517413 | 37.977539 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13744 | 42708 | 1718 | 40990 | 0.040227 | 0.959773 | 3.107392 | 27.804688 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32136 | 79864 | 4017 | 75847 | 0.050298 | 0.949702 | 2.485188 | 38.996094 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2856 | 38146 | 357 | 37789 | 0.009359 | 0.990641 | 13.356443 | 14.900781 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50264 | 122816 | 6283 | 116533 | 0.051158 | 0.948842 | 2.443419 | 39.979167 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3840 | 53321 | 480 | 52841 | 0.009002 | 0.990998 | 13.885677 | 14.877511 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76656 | 180896 | 9582 | 171314 | 0.052970 | 0.947030 | 2.359841 | 44.164062 |

### Screenshot Multi-CTU And Partial Crops

Aggregate RTL bits: `592008`.
Aggregate total cycles: `2185721`.
Aggregate output utilization: `0.033857`; bubble rate: `0.966143`.
Aggregate cycles/bit: `3.692046`; aggregate cycles/input pixel: `23.799227`.
Per-vector cycles/input pixel range: `14.091797` to `34.998481`.

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 89904 | 256444 | 11238 | 245206 | 0.043822 | 0.956178 | 2.852420 | 31.304199 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 46184 | 184072 | 5773 | 178299 | 0.031363 | 0.968637 | 3.985623 | 22.469727 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 16384 | 242235 | 2048 | 240187 | 0.008455 | 0.991545 | 14.784851 | 14.784851 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 48696 | 243920 | 6087 | 237833 | 0.024955 | 0.975045 | 5.009036 | 19.850260 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 104056 | 333750 | 13007 | 320743 | 0.038972 | 0.961028 | 3.207408 | 27.160645 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 61016 | 161273 | 7627 | 153646 | 0.047292 | 0.952708 | 2.643126 | 34.998481 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3096 | 64935 | 387 | 64548 | 0.005960 | 0.994040 | 20.973837 | 14.091797 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4488 | 74762 | 561 | 74201 | 0.007504 | 0.992496 | 16.658200 | 14.421682 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136880 | 367936 | 17110 | 350826 | 0.046503 | 0.953497 | 2.688019 | 33.817647 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 81304 | 256394 | 10163 | 246231 | 0.039638 | 0.960362 | 3.153523 | 27.820530 |
