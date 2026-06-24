# VVC RTL Output Utilization Baseline

This report records the latest VVC RTL throughput checkpoint. Older detailed
measurement sections are intentionally left to git history so this file stays
focused on the current optimization baseline and immediate deltas.

Metric definitions:

- `output_utilization`: accepted output bytes divided by total measured cycles.
- `bubble_rate`: `1 - output_utilization`.
- `cycles/bit`: total measured cycles divided by RTL bitstream bits.
- `cycles/input pixel`: total measured cycles divided by `width * height * frames`.
- Internal block utilization is testbench instrumentation. It is used to find
  pipeline starvation/backpressure and is not part of the codec bitstream
  contract.

## 2026-06-24 VVC Full Regression Checkpoint

Baseline RTL/source Git SHA:

- `33e4c40f88f0919ed0189adcb65cea1738e5c5e2`

Current RTL/source Git SHA:

- `d2cb6801f111a0023d7f982b875faccbf8c17f91`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.

Delta columns compare against the previous documented VVC output-utilization
report when the same vector or aggregate set was present.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 64 | 113168 (+0) | 269162 (+0) | 14146 (+0) | 0.0526 (+0.000) | 0.947 (+0.000) | 2.378 (-0.002) | 3.245 (-0.005) |
| `racehorses-multictu-420` | 10 | 92920 (+0) | 281944 (+0) | 11615 (+0) | 0.0412 (+0.000) | 0.959 (+0.000) | 3.034 (+0.004) | 3.07 (+0.000) |
| `screenshot-sweep-444` | 64 | 377064 (-104) | 193076 (-68341) | 47133 (-13) | 0.244 (+0.064) | 0.756 (-0.064) | 0.512 (-0.181) | 2.328 (-0.822) |
| `screenshot-multictu-444` | 10 | 286232 (+0) | 159599 (+0) | 35779 (+0) | 0.224 (+0.000) | 0.776 (+0.000) | 0.558 (+0.000) | 1.738 (-0.002) |

Mean per-vector internal probes:

| Set | Frame reader sample | Reader to FIFO | CABAC byte | Syntax frontend | Bin FIFO full |
|---|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 0.192 | 0.279 | 0.92 | 0.972 | 0.1 |
| `racehorses-multictu-420` | 0.171 | 0.215 | 1 | 0.988 | 0.0445 |
| `screenshot-sweep-444` | 0.432 | 1 | 0.81 | 0.93 | 0.157 |
| `screenshot-multictu-444` | 0.456 | 1 | 0.976 | 0.921 | 0.181 |

### RaceHorses 4:2:0 Sweep

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 | 561 (+0) | 71 | 0.127 (+0.000) | 0.873 (+0.000) | 0.988 (+0.000) | 8.766 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 | 763 (+0) | 84 | 0.11 (+0.000) | 0.89 (+0.000) | 1.135 (-0.005) | 5.961 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 | 916 (+0) | 90 | 0.0983 (+0.000) | 0.902 (+0.000) | 1.272 (+0.002) | 4.771 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 | 1112 (+0) | 101 | 0.0908 (+0.000) | 0.909 (+0.000) | 1.376 (-0.004) | 4.344 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 | 1289 (+0) | 109 | 0.0846 (+0.000) | 0.915 (+0.000) | 1.478 (-0.002) | 4.028 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 | 1517 (+0) | 120 | 0.0791 (+0.000) | 0.921 (+0.000) | 1.58 (+0.000) | 3.951 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 | 1718 (+0) | 127 | 0.0739 (+0.000) | 0.926 (+0.000) | 1.691 (+0.001) | 3.835 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 | 1933 (+0) | 140 | 0.0724 (+0.000) | 0.928 (+0.000) | 1.726 (-0.004) | 3.775 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 | 703 (+0) | 77 | 0.11 (+0.000) | 0.89 (+0.000) | 1.141 (+0.001) | 5.492 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 | 1096 (+0) | 101 | 0.0922 (+0.000) | 0.908 (+0.000) | 1.356 (-0.004) | 4.281 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 | 1429 (+0) | 114 | 0.0798 (+0.000) | 0.92 (+0.000) | 1.567 (-0.003) | 3.721 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 | 1784 (+0) | 130 | 0.0729 (+0.000) | 0.927 (+0.000) | 1.715 (-0.005) | 3.484 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 | 2197 (+0) | 149 | 0.0678 (+0.000) | 0.932 (+0.000) | 1.843 (+0.003) | 3.433 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 | 2554 (+0) | 161 | 0.063 (+0.000) | 0.937 (+0.000) | 1.983 (+0.003) | 3.326 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 | 2995 (+0) | 180 | 0.0601 (+0.000) | 0.94 (+0.000) | 2.08 (+0.000) | 3.343 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 | 3394 (+0) | 200 | 0.0589 (+0.000) | 0.941 (+0.000) | 2.121 (+0.001) | 3.314 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 | 872 (+0) | 85 | 0.0975 (+0.000) | 0.903 (+0.000) | 1.282 (+0.002) | 4.542 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 | 1444 (+0) | 115 | 0.0796 (+0.000) | 0.92 (+0.000) | 1.57 (+0.000) | 3.76 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 | 1996 (+0) | 137 | 0.0686 (+0.000) | 0.931 (+0.000) | 1.821 (+0.001) | 3.465 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 | 2576 (+0) | 164 | 0.0637 (+0.000) | 0.936 (+0.000) | 1.963 (+0.003) | 3.354 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 | 3258 (+0) | 188 | 0.0577 (+0.000) | 0.942 (+0.000) | 2.166 (-0.004) | 3.394 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 | 3760 (+0) | 209 | 0.0556 (+0.000) | 0.944 (+0.000) | 2.249 (-0.001) | 3.264 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 | 4434 (+0) | 238 | 0.0537 (+0.000) | 0.946 (+0.000) | 2.329 (-0.001) | 3.299 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 | 5021 (+0) | 261 | 0.052 (+0.000) | 0.948 (+0.000) | 2.405 (+0.005) | 3.269 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 | 1077 (+0) | 95 | 0.0882 (+0.000) | 0.912 (+0.000) | 1.417 (-0.003) | 4.207 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 | 1837 (+0) | 133 | 0.0724 (+0.000) | 0.928 (+0.000) | 1.727 (-0.003) | 3.588 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 | 2601 (+0) | 163 | 0.0627 (+0.000) | 0.937 (+0.000) | 1.995 (+0.005) | 3.387 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 | 3271 (+0) | 193 | 0.059 (+0.000) | 0.941 (+0.000) | 2.119 (-0.001) | 3.194 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 | 4148 (+0) | 225 | 0.0542 (+0.000) | 0.946 (+0.000) | 2.304 (+0.004) | 3.241 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 | 4894 (+0) | 252 | 0.0515 (+0.000) | 0.949 (+0.000) | 2.428 (-0.002) | 3.186 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 | 5778 (+0) | 286 | 0.0495 (+0.000) | 0.951 (+0.000) | 2.525 (-0.005) | 3.224 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 | 6487 (+0) | 313 | 0.0483 (+0.000) | 0.952 (+0.000) | 2.591 (+0.001) | 3.167 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 | 1211 (+0) | 99 | 0.0818 (+0.000) | 0.918 (+0.000) | 1.529 (-0.001) | 3.784 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 | 2186 (+0) | 144 | 0.0659 (+0.000) | 0.934 (+0.000) | 1.898 (-0.002) | 3.416 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 | 3205 (+0) | 180 | 0.0562 (+0.000) | 0.944 (+0.000) | 2.226 (-0.004) | 3.339 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 | 4111 (+0) | 218 | 0.053 (+0.000) | 0.947 (+0.000) | 2.357 (-0.003) | 3.212 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 | 5142 (+0) | 259 | 0.0504 (+0.000) | 0.95 (+0.000) | 2.482 (+0.002) | 3.214 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 | 6088 (+0) | 295 | 0.0485 (+0.000) | 0.952 (+0.000) | 2.58 (+0.000) | 3.171 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 | 7143 (+0) | 334 | 0.0468 (+0.000) | 0.953 (+0.000) | 2.673 (+0.003) | 3.189 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 | 8072 (+0) | 370 | 0.0458 (+0.000) | 0.954 (+0.000) | 2.727 (-0.003) | 3.153 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 | 1389 (+0) | 106 | 0.0763 (+0.000) | 0.924 (+0.000) | 1.638 (-0.002) | 3.617 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 | 2556 (+0) | 154 | 0.0603 (+0.000) | 0.94 (+0.000) | 2.075 (+0.005) | 3.328 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 | 3754 (+0) | 201 | 0.0535 (+0.000) | 0.946 (+0.000) | 2.335 (+0.005) | 3.259 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 | 4799 (+0) | 243 | 0.0506 (+0.000) | 0.949 (+0.000) | 2.469 (-0.001) | 3.124 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 | 6004 (+0) | 284 | 0.0473 (+0.000) | 0.953 (+0.000) | 2.643 (+0.003) | 3.127 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 | 7214 (+0) | 331 | 0.0459 (+0.000) | 0.954 (+0.000) | 2.724 (+0.004) | 3.131 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 | 8416 (+0) | 375 | 0.0446 (+0.000) | 0.955 (+0.000) | 2.805 (-0.005) | 3.131 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 | 9405 (+0) | 414 | 0.044 (+0.000) | 0.956 (+0.000) | 2.84 (+0.000) | 3.062 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 | 1689 (+0) | 121 | 0.0716 (+0.000) | 0.928 (+0.000) | 1.745 (+0.005) | 3.77 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 | 3027 (+0) | 180 | 0.0595 (+0.000) | 0.941 (+0.000) | 2.102 (+0.002) | 3.378 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 | 4369 (+0) | 227 | 0.052 (+0.000) | 0.948 (+0.000) | 2.406 (-0.004) | 3.251 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 | 5679 (+0) | 281 | 0.0495 (+0.000) | 0.951 (+0.000) | 2.526 (-0.004) | 3.169 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 | 7078 (+0) | 329 | 0.0465 (+0.000) | 0.954 (+0.000) | 2.689 (-0.001) | 3.16 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 | 8391 (+0) | 378 | 0.045 (+0.000) | 0.955 (+0.000) | 2.775 (+0.005) | 3.122 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 | 9828 (+0) | 425 | 0.0432 (+0.000) | 0.957 (+0.000) | 2.891 (+0.001) | 3.134 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 | 11096 (+0) | 474 | 0.0427 (+0.000) | 0.957 (+0.000) | 2.926 (-0.004) | 3.096 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 | 1884 (+0) | 131 | 0.0695 (+0.000) | 0.93 (+0.000) | 1.798 (-0.002) | 3.68 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 | 3425 (+0) | 198 | 0.0578 (+0.000) | 0.942 (+0.000) | 2.162 (+0.002) | 3.345 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 | 4979 (+0) | 253 | 0.0508 (+0.000) | 0.949 (+0.000) | 2.46 (+0.000) | 3.242 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 | 6433 (+0) | 316 | 0.0491 (+0.000) | 0.951 (+0.000) | 2.545 (+0.005) | 3.141 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 | 7961 (+0) | 364 | 0.0457 (+0.000) | 0.954 (+0.000) | 2.734 (+0.004) | 3.11 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 | 9477 (+0) | 426 | 0.045 (+0.000) | 0.955 (+0.000) | 2.781 (+0.001) | 3.085 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 | 11133 (+0) | 485 | 0.0436 (+0.000) | 0.956 (+0.000) | 2.869 (-0.001) | 3.106 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 | 12603 (+0) | 540 | 0.0428 (+0.000) | 0.957 (+0.000) | 2.917 (-0.003) | 3.077 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 | 25346 (+0) | 1060 | 0.0418 (+0.000) | 0.958 (+0.000) | 2.989 (-0.001) | 3.094 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 | 25070 (+0) | 1027 | 0.041 (+0.000) | 0.959 (+0.000) | 3.051 (+0.001) | 3.06 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 | 49182 (+0) | 1948 | 0.0396 (+0.000) | 0.96 (+0.000) | 3.156 (-0.004) | 3.002 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 | 37820 (+0) | 1583 | 0.0419 (+0.000) | 0.958 (+0.000) | 2.986 (-0.004) | 3.078 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 | 36349 (+0) | 1405 | 0.0387 (+0.000) | 0.961 (+0.000) | 3.234 (+0.004) | 2.958 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 | 14496 (+0) | 632 | 0.0436 (+0.000) | 0.956 (+0.000) | 2.867 (-0.003) | 3.146 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 | 14611 (+0) | 633 | 0.0433 (+0.000) | 0.957 (+0.000) | 2.885 (-0.005) | 3.171 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 | 16823 (+0) | 739 | 0.0439 (+0.000) | 0.956 (+0.000) | 2.846 (-0.004) | 3.245 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 | 33700 (+0) | 1408 | 0.0418 (+0.000) | 0.958 (+0.000) | 2.992 (+0.002) | 3.097 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 | 28547 (+0) | 1180 | 0.0413 (+0.000) | 0.959 (+0.000) | 3.024 (+0.004) | 3.098 |

### Screenshot 4:4:4 Sweep

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 | 384 (+0) | 67 | 0.174 (+0.000) | 0.826 (+0.000) | 0.716 (+0.000) | 6 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 | 654 (+0) | 122 | 0.187 (+0.000) | 0.813 (+0.000) | 0.67 (+0.000) | 5.109 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 | 408 (-2) | 72 | 0.176 (+0.000) | 0.824 (+0.000) | 0.708 (-0.004) | 2.125 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 640 | 503 (-7) | 80 | 0.159 (+0.000) | 0.841 (+0.000) | 0.786 (-0.001) | 1.965 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 608 | 429 (-101) | 76 | 0.177 (+0.030) | 0.823 (-0.030) | 0.706 (-0.143) | 1.341 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 616 | 437 (-129) | 77 | 0.176 (+0.035) | 0.824 (-0.035) | 0.709 (-0.175) | 1.138 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 | 2105 (-213) | 586 | 0.278 (+0.025) | 0.722 (-0.025) | 0.449 (-0.045) | 4.699 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 | 2052 (-268) | 543 | 0.265 (+0.031) | 0.735 (-0.031) | 0.472 (-0.062) | 4.008 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 | 700 (+0) | 139 | 0.199 (+0.000) | 0.801 (+0.000) | 0.629 (+0.000) | 5.469 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 | 1105 (+0) | 280 | 0.253 (+0.000) | 0.747 (+0.000) | 0.493 (+0.000) | 4.316 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 | 455 (-173) | 80 | 0.176 (+0.049) | 0.824 (-0.049) | 0.711 (-0.270) | 1.185 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 656 | 471 (-184) | 82 | 0.174 (+0.046) | 0.826 (-0.046) | 0.718 (-0.257) | 0.92 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 | 2714 (-574) | 766 | 0.282 (+0.049) | 0.718 (-0.049) | 0.443 (-0.094) | 4.241 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 688 | 615 (-326) | 86 | 0.14 (+0.043) | 0.86 (-0.043) | 0.894 (-0.396) | 0.801 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6200 | 3022 (-882) | 775 | 0.256 (+0.058) | 0.744 (-0.058) | 0.487 (-0.143) | 3.373 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 720 | 805 (-403) | 90 | 0.112 (+0.030) | 0.888 (-0.030) | 1.118 (-0.412) | 0.786 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 | 1070 (+1) | 288 | 0.269 (+0.000) | 0.731 (+0.000) | 0.464 (+0.000) | 5.573 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 | 880 (-173) | 176 | 0.2 (+0.033) | 0.8 (-0.033) | 0.625 (-0.123) | 2.292 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2848 | 1505 (-459) | 356 | 0.237 (+0.057) | 0.763 (-0.057) | 0.528 (-0.166) | 2.613 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 | 3420 (-457) | 973 | 0.285 (+0.034) | 0.715 (-0.034) | 0.439 (-0.059) | 4.453 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6080 | 3085 (-905) | 760 | 0.246 (+0.056) | 0.754 (-0.056) | 0.507 (-0.150) | 3.214 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 736 | 904 (-455) | 92 | 0.102 (+0.027) | 0.898 (-0.028) | 1.228 (-0.452) | 0.785 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 752 | 1289 (-528) | 94 | 0.0729 (+0.015) | 0.927 (-0.015) | 1.714 (-0.426) | 0.959 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11328 | 5231 (-1366) | 1416 | 0.271 (+0.056) | 0.729 (-0.056) | 0.462 (-0.120) | 3.406 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 | 836 (-144) | 188 | 0.225 (+0.033) | 0.775 (-0.033) | 0.556 (-0.096) | 3.266 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 | 848 (-293) | 149 | 0.176 (+0.045) | 0.824 (-0.045) | 0.711 (-0.246) | 1.656 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 | 800 (-630) | 131 | 0.164 (+0.072) | 0.836 (-0.072) | 0.763 (-0.597) | 1.042 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4384 | 2358 (-718) | 548 | 0.232 (+0.054) | 0.768 (-0.054) | 0.538 (-0.165) | 2.303 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 776 | 1284 (-490) | 97 | 0.0755 (+0.016) | 0.924 (-0.016) | 1.655 (-0.435) | 1.003 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 | 5663 (-1298) | 1604 | 0.283 (+0.053) | 0.717 (-0.053) | 0.441 (-0.101) | 3.687 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 12648 | 5846 (-1680) | 1581 | 0.27 (+0.071) | 0.73 (-0.071) | 0.462 (-0.167) | 3.262 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 824 | 1560 (-696) | 103 | 0.066 (+0.012) | 0.934 (-0.011) | 1.893 (-0.397) | 0.762 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 | 1515 (-195) | 385 | 0.254 (+0.029) | 0.746 (-0.029) | 0.492 (-0.063) | 4.734 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 | 2746 (-370) | 737 | 0.268 (+0.031) | 0.732 (-0.031) | 0.466 (-0.062) | 4.291 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1120 | 1197 (-712) | 140 | 0.117 (+0.042) | 0.883 (-0.042) | 1.069 (-0.591) | 1.247 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 | 4703 (-1039) | 1263 | 0.269 (+0.049) | 0.731 (-0.049) | 0.465 (-0.103) | 3.674 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 10736 | 4840 (-1226) | 1342 | 0.277 (+0.081) | 0.723 (-0.081) | 0.451 (-0.188) | 3.025 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1296 | 1706 (-1088) | 162 | 0.095 (+0.031) | 0.905 (-0.031) | 1.316 (-0.634) | 0.889 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10288 | 4916 (-2601) | 1286 | 0.262 (+0.090) | 0.738 (-0.090) | 0.478 (-0.249) | 2.195 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 944 | 1964 (-1339) | 118 | 0.0601 (+0.016) | 0.94 (-0.016) | 2.081 (-0.769) | 0.767 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 | 539 (-369) | 90 | 0.167 (+0.068) | 0.833 (-0.068) | 0.749 (-0.511) | 1.404 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 | 4064 (-637) | 1224 | 0.301 (+0.041) | 0.699 (-0.041) | 0.415 (-0.065) | 5.292 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 | 3401 (-1236) | 901 | 0.265 (+0.071) | 0.735 (-0.071) | 0.472 (-0.171) | 2.952 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7400 | 3780 (-1396) | 925 | 0.245 (+0.066) | 0.755 (-0.066) | 0.511 (-0.186) | 2.461 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14728 | 6575 (-2252) | 1841 | 0.28 (+0.071) | 0.72 (-0.071) | 0.446 (-0.153) | 3.424 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 | 1772 (-811) | 110 | 0.0621 (+0.011) | 0.938 (-0.011) | 2.014 (-0.446) | 0.769 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9192 | 4694 (-3391) | 1149 | 0.245 (+0.102) | 0.755 (-0.102) | 0.511 (-0.364) | 1.746 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 992 | 2338 (-1440) | 124 | 0.053 (+0.012) | 0.947 (-0.012) | 2.357 (-0.693) | 0.761 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 | 1747 (-405) | 454 | 0.26 (+0.049) | 0.74 (-0.049) | 0.481 (-0.112) | 3.9 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 | 2719 (-723) | 727 | 0.267 (+0.056) | 0.733 (-0.056) | 0.468 (-0.124) | 3.035 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5936 | 3085 (-1431) | 742 | 0.241 (+0.077) | 0.759 (-0.077) | 0.52 (-0.244) | 2.295 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9104 | 4148 (-1596) | 1138 | 0.274 (+0.075) | 0.726 (-0.075) | 0.456 (-0.173) | 2.315 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17880 | 7872 (-2728) | 2235 | 0.284 (+0.073) | 0.716 (-0.073) | 0.44 (-0.154) | 3.514 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10544 | 5322 (-2554) | 1318 | 0.248 (+0.079) | 0.752 (-0.079) | 0.505 (-0.234) | 1.98 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25424 | 11235 (-4249) | 3178 | 0.283 (+0.078) | 0.717 (-0.078) | 0.442 (-0.167) | 3.583 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12760 | 6288 (-4188) | 1595 | 0.254 (+0.100) | 0.746 (-0.100) | 0.493 (-0.319) | 1.754 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 | 1438 (-449) | 293 | 0.204 (+0.049) | 0.796 (-0.049) | 0.613 (-0.192) | 2.809 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8760 | 3847 (-945) | 1095 | 0.285 (+0.057) | 0.715 (-0.057) | 0.439 (-0.109) | 3.757 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6872 | 3205 (-1633) | 859 | 0.268 (+0.090) | 0.732 (-0.090) | 0.466 (-0.236) | 2.087 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 | 6566 (-1960) | 1760 | 0.268 (+0.062) | 0.732 (-0.062) | 0.466 (-0.140) | 3.206 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1464 | 2547 (-1377) | 183 | 0.0718 (+0.021) | 0.928 (-0.021) | 1.74 (-0.720) | 0.995 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23128 | 10387 (-3337) | 2891 | 0.278 (+0.068) | 0.722 (-0.068) | 0.449 (-0.145) | 3.381 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1696 | 3668 (-1966) | 212 | 0.0578 (+0.015) | 0.942 (-0.015) | 2.163 (-0.767) | 1.023 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 | 14814 (-5145) | 4179 | 0.282 (+0.073) | 0.718 (-0.073) | 0.443 (-0.154) | 3.617 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47296 | 20775 (+0) | 5912 | 0.285 (+0.000) | 0.715 (+0.000) | 0.439 (+0.000) | 2.536 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18584 | 11899 (+0) | 2323 | 0.195 (+0.000) | 0.805 (+0.000) | 0.64 (+0.000) | 1.453 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 4992 | 12385 (+0) | 624 | 0.0504 (+0.000) | 0.95 (+0.000) | 2.481 (+0.001) | 0.756 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33112 | 18975 (+0) | 4139 | 0.218 (+0.000) | 0.782 (+0.000) | 0.573 (+0.000) | 1.544 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49416 | 24369 (+0) | 6177 | 0.253 (+0.000) | 0.747 (+0.000) | 0.493 (+0.000) | 1.983 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27760 | 13083 (+0) | 3470 | 0.265 (+0.000) | 0.735 (+0.000) | 0.471 (+0.000) | 2.839 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1288 | 3529 (+0) | 161 | 0.0456 (+0.000) | 0.954 (+0.000) | 2.74 (+0.000) | 0.766 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 1848 | 5154 (+0) | 231 | 0.0448 (+0.000) | 0.955 (+0.000) | 2.789 (-0.001) | 0.994 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 63200 | 30270 (+0) | 7900 | 0.261 (+0.000) | 0.739 (+0.000) | 0.479 (+0.000) | 2.782 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38736 | 19160 (+0) | 4842 | 0.253 (+0.000) | 0.747 (+0.000) | 0.495 (+0.000) | 2.079 |

Regenerated waveform artifacts, when enabled for a vector, are under
`verification/generated/checksums/vvc/`. Use the matching
`*_rtl_block_waveform.html` file for the color-coded block-state timeline or
`*_rtl_block_waveform.vcd` plus `*_rtl_block_waveform.gtkw` for GTKWave.
