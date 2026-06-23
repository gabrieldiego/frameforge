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

## 2026-06-23 VVC Full Regression Checkpoint

Baseline RTL/source Git SHA:

- `98ab0d150875b5899c9d08f9848574373707e187`

Current RTL/source Git SHA:

- `33e4c40f88f0919ed0189adcb65cea1738e5c5e2`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.

Delta columns compare against the previous documented VVC output-utilization
report when the same vector was present. Newly covered sets use `n/a` deltas
and become the baseline for the next report.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 64 | 113168 (n/a) | 269162 (n/a) | 14146 (n/a) | 0.0526 (n/a) | 0.947 (n/a) | 2.38 (n/a) | 3.25 (n/a) |
| `racehorses-multictu-420` | 10 | 92920 (n/a) | 281944 (n/a) | 11615 (n/a) | 0.0412 (n/a) | 0.959 (n/a) | 3.03 (n/a) | 3.07 (n/a) |
| `screenshot-sweep-444` | 64 | 377168 (n/a) | 261417 (n/a) | 47146 (n/a) | 0.18 (n/a) | 0.82 (n/a) | 0.693 (n/a) | 3.15 (n/a) |
| `screenshot-multictu-444` | 10 | 289000 (+0) | 239191 (+81228) | 36125 (+0) | 0.151 (-0.078) | 0.849 (+0.078) | 0.828 (+0.281) | 2.6 (+0.884) |

Mean per-vector internal probes:

| Set | Frame reader sample | Reader to FIFO | CABAC byte | Syntax frontend | Bin FIFO full |
|---|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 0.192 | 0.279 | 0.92 | 0.972 | 0.1 |
| `racehorses-multictu-420` | 0.171 | 0.215 | 1 | 0.988 | 0.0445 |
| `screenshot-sweep-444` | 0.432 | 1 | 0.955 | 0.934 | 0.118 |
| `screenshot-multictu-444` | 0.456 | 1 | 0.997 | 0.921 | 0.126 |

### RaceHorses 4:2:0 Sweep

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 | 561 (n/a) | 71 | 0.127 (n/a) | 0.873 (n/a) | 0.988 (n/a) | 8.77 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 | 763 (n/a) | 84 | 0.11 (n/a) | 0.89 (n/a) | 1.14 (n/a) | 5.96 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 | 916 (n/a) | 90 | 0.0983 (n/a) | 0.902 (n/a) | 1.27 (n/a) | 4.77 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 | 1112 (n/a) | 101 | 0.0908 (n/a) | 0.909 (n/a) | 1.38 (n/a) | 4.34 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 | 1289 (n/a) | 109 | 0.0846 (n/a) | 0.915 (n/a) | 1.48 (n/a) | 4.03 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 | 1517 (n/a) | 120 | 0.0791 (n/a) | 0.921 (n/a) | 1.58 (n/a) | 3.95 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 | 1718 (n/a) | 127 | 0.0739 (n/a) | 0.926 (n/a) | 1.69 (n/a) | 3.83 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 | 1933 (n/a) | 140 | 0.0724 (n/a) | 0.928 (n/a) | 1.73 (n/a) | 3.78 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 | 703 (n/a) | 77 | 0.11 (n/a) | 0.89 (n/a) | 1.14 (n/a) | 5.49 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 | 1096 (n/a) | 101 | 0.0922 (n/a) | 0.908 (n/a) | 1.36 (n/a) | 4.28 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 | 1429 (n/a) | 114 | 0.0798 (n/a) | 0.92 (n/a) | 1.57 (n/a) | 3.72 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 | 1784 (n/a) | 130 | 0.0729 (n/a) | 0.927 (n/a) | 1.72 (n/a) | 3.48 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 | 2197 (n/a) | 149 | 0.0678 (n/a) | 0.932 (n/a) | 1.84 (n/a) | 3.43 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 | 2554 (n/a) | 161 | 0.063 (n/a) | 0.937 (n/a) | 1.98 (n/a) | 3.33 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 | 2995 (n/a) | 180 | 0.0601 (n/a) | 0.94 (n/a) | 2.08 (n/a) | 3.34 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 | 3394 (n/a) | 200 | 0.0589 (n/a) | 0.941 (n/a) | 2.12 (n/a) | 3.31 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 | 872 (n/a) | 85 | 0.0975 (n/a) | 0.903 (n/a) | 1.28 (n/a) | 4.54 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 | 1444 (n/a) | 115 | 0.0796 (n/a) | 0.92 (n/a) | 1.57 (n/a) | 3.76 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 | 1996 (n/a) | 137 | 0.0686 (n/a) | 0.931 (n/a) | 1.82 (n/a) | 3.47 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 | 2576 (n/a) | 164 | 0.0637 (n/a) | 0.936 (n/a) | 1.96 (n/a) | 3.35 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 | 3258 (n/a) | 188 | 0.0577 (n/a) | 0.942 (n/a) | 2.17 (n/a) | 3.39 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 | 3760 (n/a) | 209 | 0.0556 (n/a) | 0.944 (n/a) | 2.25 (n/a) | 3.26 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 | 4434 (n/a) | 238 | 0.0537 (n/a) | 0.946 (n/a) | 2.33 (n/a) | 3.3 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 | 5021 (n/a) | 261 | 0.052 (n/a) | 0.948 (n/a) | 2.4 (n/a) | 3.27 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 | 1077 (n/a) | 95 | 0.0882 (n/a) | 0.912 (n/a) | 1.42 (n/a) | 4.21 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 | 1837 (n/a) | 133 | 0.0724 (n/a) | 0.928 (n/a) | 1.73 (n/a) | 3.59 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 | 2601 (n/a) | 163 | 0.0627 (n/a) | 0.937 (n/a) | 1.99 (n/a) | 3.39 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 | 3271 (n/a) | 193 | 0.059 (n/a) | 0.941 (n/a) | 2.12 (n/a) | 3.19 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 | 4148 (n/a) | 225 | 0.0542 (n/a) | 0.946 (n/a) | 2.3 (n/a) | 3.24 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 | 4894 (n/a) | 252 | 0.0515 (n/a) | 0.949 (n/a) | 2.43 (n/a) | 3.19 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 | 5778 (n/a) | 286 | 0.0495 (n/a) | 0.951 (n/a) | 2.53 (n/a) | 3.22 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 | 6487 (n/a) | 313 | 0.0483 (n/a) | 0.952 (n/a) | 2.59 (n/a) | 3.17 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 | 1211 (n/a) | 99 | 0.0818 (n/a) | 0.918 (n/a) | 1.53 (n/a) | 3.78 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 | 2186 (n/a) | 144 | 0.0659 (n/a) | 0.934 (n/a) | 1.9 (n/a) | 3.42 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 | 3205 (n/a) | 180 | 0.0562 (n/a) | 0.944 (n/a) | 2.23 (n/a) | 3.34 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 | 4111 (n/a) | 218 | 0.053 (n/a) | 0.947 (n/a) | 2.36 (n/a) | 3.21 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 | 5142 (n/a) | 259 | 0.0504 (n/a) | 0.95 (n/a) | 2.48 (n/a) | 3.21 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 | 6088 (n/a) | 295 | 0.0485 (n/a) | 0.952 (n/a) | 2.58 (n/a) | 3.17 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 | 7143 (n/a) | 334 | 0.0468 (n/a) | 0.953 (n/a) | 2.67 (n/a) | 3.19 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 | 8072 (n/a) | 370 | 0.0458 (n/a) | 0.954 (n/a) | 2.73 (n/a) | 3.15 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 | 1389 (n/a) | 106 | 0.0763 (n/a) | 0.924 (n/a) | 1.64 (n/a) | 3.62 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 | 2556 (n/a) | 154 | 0.0602 (n/a) | 0.94 (n/a) | 2.07 (n/a) | 3.33 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 | 3754 (n/a) | 201 | 0.0535 (n/a) | 0.946 (n/a) | 2.33 (n/a) | 3.26 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 | 4799 (n/a) | 243 | 0.0506 (n/a) | 0.949 (n/a) | 2.47 (n/a) | 3.12 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 | 6004 (n/a) | 284 | 0.0473 (n/a) | 0.953 (n/a) | 2.64 (n/a) | 3.13 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 | 7214 (n/a) | 331 | 0.0459 (n/a) | 0.954 (n/a) | 2.72 (n/a) | 3.13 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 | 8416 (n/a) | 375 | 0.0446 (n/a) | 0.955 (n/a) | 2.81 (n/a) | 3.13 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 | 9405 (n/a) | 414 | 0.044 (n/a) | 0.956 (n/a) | 2.84 (n/a) | 3.06 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 | 1689 (n/a) | 121 | 0.0716 (n/a) | 0.928 (n/a) | 1.74 (n/a) | 3.77 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 | 3027 (n/a) | 180 | 0.0595 (n/a) | 0.941 (n/a) | 2.1 (n/a) | 3.38 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 | 4369 (n/a) | 227 | 0.052 (n/a) | 0.948 (n/a) | 2.41 (n/a) | 3.25 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 | 5679 (n/a) | 281 | 0.0495 (n/a) | 0.951 (n/a) | 2.53 (n/a) | 3.17 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 | 7078 (n/a) | 329 | 0.0465 (n/a) | 0.954 (n/a) | 2.69 (n/a) | 3.16 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 | 8391 (n/a) | 378 | 0.045 (n/a) | 0.955 (n/a) | 2.77 (n/a) | 3.12 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 | 9828 (n/a) | 425 | 0.0432 (n/a) | 0.957 (n/a) | 2.89 (n/a) | 3.13 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 | 11096 (n/a) | 474 | 0.0427 (n/a) | 0.957 (n/a) | 2.93 (n/a) | 3.1 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 | 1884 (n/a) | 131 | 0.0695 (n/a) | 0.93 (n/a) | 1.8 (n/a) | 3.68 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 | 3425 (n/a) | 198 | 0.0578 (n/a) | 0.942 (n/a) | 2.16 (n/a) | 3.34 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 | 4979 (n/a) | 253 | 0.0508 (n/a) | 0.949 (n/a) | 2.46 (n/a) | 3.24 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 | 6433 (n/a) | 316 | 0.0491 (n/a) | 0.951 (n/a) | 2.54 (n/a) | 3.14 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 | 7961 (n/a) | 364 | 0.0457 (n/a) | 0.954 (n/a) | 2.73 (n/a) | 3.11 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 | 9477 (n/a) | 426 | 0.045 (n/a) | 0.955 (n/a) | 2.78 (n/a) | 3.08 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 | 11133 (n/a) | 485 | 0.0436 (n/a) | 0.956 (n/a) | 2.87 (n/a) | 3.11 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 | 12603 (n/a) | 540 | 0.0428 (n/a) | 0.957 (n/a) | 2.92 (n/a) | 3.08 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 | 25346 (n/a) | 1060 | 0.0418 (n/a) | 0.958 (n/a) | 2.99 (n/a) | 3.09 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 | 25070 (n/a) | 1027 | 0.041 (n/a) | 0.959 (n/a) | 3.05 (n/a) | 3.06 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 | 49182 (n/a) | 1948 | 0.0396 (n/a) | 0.96 (n/a) | 3.16 (n/a) | 3 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 | 37820 (n/a) | 1583 | 0.0419 (n/a) | 0.958 (n/a) | 2.99 (n/a) | 3.08 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 | 36349 (n/a) | 1405 | 0.0387 (n/a) | 0.961 (n/a) | 3.23 (n/a) | 2.96 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 | 14496 (n/a) | 632 | 0.0436 (n/a) | 0.956 (n/a) | 2.87 (n/a) | 3.15 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 | 14611 (n/a) | 633 | 0.0433 (n/a) | 0.957 (n/a) | 2.89 (n/a) | 3.17 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 | 16823 (n/a) | 739 | 0.0439 (n/a) | 0.956 (n/a) | 2.85 (n/a) | 3.25 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 | 33700 (n/a) | 1408 | 0.0418 (n/a) | 0.958 (n/a) | 2.99 (n/a) | 3.1 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 | 28547 (n/a) | 1180 | 0.0413 (n/a) | 0.959 (n/a) | 3.02 (n/a) | 3.1 |

### Screenshot 4:4:4 Sweep

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 | 384 (n/a) | 67 | 0.174 (n/a) | 0.826 (n/a) | 0.716 (n/a) | 6 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 | 654 (n/a) | 122 | 0.187 (n/a) | 0.813 (n/a) | 0.67 (n/a) | 5.11 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 | 410 (n/a) | 72 | 0.176 (n/a) | 0.824 (n/a) | 0.712 (n/a) | 2.14 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 648 | 510 (n/a) | 81 | 0.159 (n/a) | 0.841 (n/a) | 0.787 (n/a) | 1.99 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 624 | 530 (n/a) | 78 | 0.147 (n/a) | 0.853 (n/a) | 0.849 (n/a) | 1.66 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 640 | 566 (n/a) | 80 | 0.141 (n/a) | 0.859 (n/a) | 0.884 (n/a) | 1.47 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 | 2318 (n/a) | 586 | 0.253 (n/a) | 0.747 (n/a) | 0.494 (n/a) | 5.17 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 | 2320 (n/a) | 543 | 0.234 (n/a) | 0.766 (n/a) | 0.534 (n/a) | 4.53 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 | 700 (n/a) | 139 | 0.199 (n/a) | 0.801 (n/a) | 0.629 (n/a) | 5.47 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 | 1105 (n/a) | 280 | 0.253 (n/a) | 0.747 (n/a) | 0.493 (n/a) | 4.32 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 | 628 (n/a) | 80 | 0.127 (n/a) | 0.873 (n/a) | 0.981 (n/a) | 1.64 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 672 | 655 (n/a) | 84 | 0.128 (n/a) | 0.872 (n/a) | 0.975 (n/a) | 1.28 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 | 3288 (n/a) | 766 | 0.233 (n/a) | 0.767 (n/a) | 0.537 (n/a) | 5.14 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 728 | 941 (n/a) | 91 | 0.0967 (n/a) | 0.903 (n/a) | 1.29 (n/a) | 1.23 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6192 | 3904 (n/a) | 774 | 0.198 (n/a) | 0.802 (n/a) | 0.63 (n/a) | 4.36 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 792 | 1208 (n/a) | 99 | 0.082 (n/a) | 0.918 (n/a) | 1.53 (n/a) | 1.18 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 | 1069 (n/a) | 288 | 0.269 (n/a) | 0.731 (n/a) | 0.464 (n/a) | 5.57 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 | 1053 (n/a) | 176 | 0.167 (n/a) | 0.833 (n/a) | 0.748 (n/a) | 2.74 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2832 | 1964 (n/a) | 354 | 0.18 (n/a) | 0.82 (n/a) | 0.694 (n/a) | 3.41 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 | 3877 (n/a) | 973 | 0.251 (n/a) | 0.749 (n/a) | 0.498 (n/a) | 5.05 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6072 | 3990 (n/a) | 759 | 0.19 (n/a) | 0.81 (n/a) | 0.657 (n/a) | 4.16 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 808 | 1359 (n/a) | 101 | 0.0743 (n/a) | 0.926 (n/a) | 1.68 (n/a) | 1.18 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 848 | 1817 (n/a) | 106 | 0.0583 (n/a) | 0.942 (n/a) | 2.14 (n/a) | 1.35 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11336 | 6597 (n/a) | 1417 | 0.215 (n/a) | 0.785 (n/a) | 0.582 (n/a) | 4.29 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 | 980 (n/a) | 188 | 0.192 (n/a) | 0.808 (n/a) | 0.652 (n/a) | 3.83 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 | 1141 (n/a) | 149 | 0.131 (n/a) | 0.869 (n/a) | 0.957 (n/a) | 2.23 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 | 1430 (n/a) | 131 | 0.0916 (n/a) | 0.908 (n/a) | 1.36 (n/a) | 1.86 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4376 | 3076 (n/a) | 547 | 0.178 (n/a) | 0.822 (n/a) | 0.703 (n/a) | 3 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 848 | 1774 (n/a) | 106 | 0.0598 (n/a) | 0.94 (n/a) | 2.09 (n/a) | 1.39 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 | 6961 (n/a) | 1604 | 0.23 (n/a) | 0.77 (n/a) | 0.542 (n/a) | 4.53 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 11960 | 7526 (n/a) | 1495 | 0.199 (n/a) | 0.801 (n/a) | 0.629 (n/a) | 4.2 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 984 | 2256 (n/a) | 123 | 0.0545 (n/a) | 0.945 (n/a) | 2.29 (n/a) | 1.1 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 | 1710 (n/a) | 385 | 0.225 (n/a) | 0.775 (n/a) | 0.555 (n/a) | 5.34 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 | 3116 (n/a) | 737 | 0.237 (n/a) | 0.763 (n/a) | 0.528 (n/a) | 4.87 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1152 | 1909 (n/a) | 144 | 0.0754 (n/a) | 0.925 (n/a) | 1.66 (n/a) | 1.99 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 | 5742 (n/a) | 1263 | 0.22 (n/a) | 0.78 (n/a) | 0.568 (n/a) | 4.49 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 9488 | 6066 (n/a) | 1186 | 0.196 (n/a) | 0.804 (n/a) | 0.639 (n/a) | 3.79 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1432 | 2794 (n/a) | 179 | 0.0641 (n/a) | 0.936 (n/a) | 1.95 (n/a) | 1.46 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10336 | 7517 (n/a) | 1292 | 0.172 (n/a) | 0.828 (n/a) | 0.727 (n/a) | 3.36 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1160 | 3303 (n/a) | 145 | 0.0439 (n/a) | 0.956 (n/a) | 2.85 (n/a) | 1.29 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 | 908 (n/a) | 90 | 0.0991 (n/a) | 0.901 (n/a) | 1.26 (n/a) | 2.36 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 | 4701 (n/a) | 1224 | 0.26 (n/a) | 0.74 (n/a) | 0.48 (n/a) | 6.12 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 | 4637 (n/a) | 901 | 0.194 (n/a) | 0.806 (n/a) | 0.643 (n/a) | 4.03 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7424 | 5176 (n/a) | 928 | 0.179 (n/a) | 0.821 (n/a) | 0.697 (n/a) | 3.37 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14736 | 8827 (n/a) | 1842 | 0.209 (n/a) | 0.791 (n/a) | 0.599 (n/a) | 4.6 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1048 | 2583 (n/a) | 131 | 0.0507 (n/a) | 0.949 (n/a) | 2.46 (n/a) | 1.12 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9240 | 8085 (n/a) | 1155 | 0.143 (n/a) | 0.857 (n/a) | 0.875 (n/a) | 3.01 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 | 3778 (n/a) | 155 | 0.041 (n/a) | 0.959 (n/a) | 3.05 (n/a) | 1.23 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 | 2152 (n/a) | 454 | 0.211 (n/a) | 0.789 (n/a) | 0.593 (n/a) | 4.8 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 | 3442 (n/a) | 727 | 0.211 (n/a) | 0.789 (n/a) | 0.592 (n/a) | 3.84 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5912 | 4516 (n/a) | 739 | 0.164 (n/a) | 0.836 (n/a) | 0.764 (n/a) | 3.36 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9136 | 5744 (n/a) | 1142 | 0.199 (n/a) | 0.801 (n/a) | 0.629 (n/a) | 3.21 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17856 | 10600 (n/a) | 2232 | 0.211 (n/a) | 0.789 (n/a) | 0.594 (n/a) | 4.73 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10656 | 7876 (n/a) | 1332 | 0.169 (n/a) | 0.831 (n/a) | 0.739 (n/a) | 2.93 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25432 | 15484 (n/a) | 3179 | 0.205 (n/a) | 0.795 (n/a) | 0.609 (n/a) | 4.94 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12904 | 10476 (n/a) | 1613 | 0.154 (n/a) | 0.846 (n/a) | 0.812 (n/a) | 2.92 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 | 1887 (n/a) | 293 | 0.155 (n/a) | 0.845 (n/a) | 0.805 (n/a) | 3.69 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8752 | 4792 (n/a) | 1094 | 0.228 (n/a) | 0.772 (n/a) | 0.548 (n/a) | 4.68 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6888 | 4838 (n/a) | 861 | 0.178 (n/a) | 0.822 (n/a) | 0.702 (n/a) | 3.15 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 | 8526 (n/a) | 1760 | 0.206 (n/a) | 0.794 (n/a) | 0.606 (n/a) | 4.16 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1592 | 3924 (n/a) | 199 | 0.0507 (n/a) | 0.949 (n/a) | 2.46 (n/a) | 1.53 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23088 | 13724 (n/a) | 2886 | 0.21 (n/a) | 0.79 (n/a) | 0.594 (n/a) | 4.47 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1920 | 5634 (n/a) | 240 | 0.0426 (n/a) | 0.957 (n/a) | 2.93 (n/a) | 1.57 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 | 19959 (n/a) | 4179 | 0.209 (n/a) | 0.791 (n/a) | 0.597 (n/a) | 4.87 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47464 | 29830 (+9001) | 5933 | 0.199 (-0.086) | 0.801 (+0.086) | 0.628 (+0.189) | 3.64 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18832 | 17740 (+6057) | 2354 | 0.133 (-0.068) | 0.867 (+0.068) | 0.942 (+0.322) | 2.17 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 6288 | 21957 (+9551) | 786 | 0.0358 (-0.028) | 0.964 (+0.027) | 3.49 (+1.522) | 1.34 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33776 | 27017 (+8021) | 4222 | 0.156 (-0.066) | 0.844 (+0.066) | 0.8 (+0.238) | 2.2 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49064 | 36457 (+12592) | 6133 | 0.168 (-0.089) | 0.832 (+0.089) | 0.743 (+0.257) | 2.97 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27872 | 18996 (+5935) | 3484 | 0.183 (-0.084) | 0.817 (+0.084) | 0.682 (+0.213) | 4.12 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1648 | 5105 (+1571) | 206 | 0.0404 (-0.018) | 0.96 (+0.018) | 3.1 (+0.958) | 1.11 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2232 | 8451 (+3349) | 279 | 0.033 (-0.022) | 0.967 (+0.022) | 3.79 (+1.496) | 1.63 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 62832 | 43228 (+13721) | 7854 | 0.182 (-0.084) | 0.818 (+0.084) | 0.688 (+0.218) | 3.97 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38992 | 30410 (+11430) | 4874 | 0.16 (-0.097) | 0.84 (+0.097) | 0.78 (+0.293) | 3.3 |

Regenerated waveform artifacts, when enabled for a vector, are under
`verification/generated/checksums/vvc/`. Use the matching
`*_rtl_block_waveform.html` file for the color-coded block-state timeline or
`*_rtl_block_waveform.gtkw` for GTKWave.
