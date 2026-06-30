# VVC RTL Output Utilization Baselines

This report records the latest RTL simulation throughput counters. Older
measurement sections are intentionally left to git history so this file
stays focused on the current optimization baseline and immediate deltas.

Metric definitions:

- `output_utilization`: accepted output bytes divided by total measured cycles.
- `bubble_rate`: `1 - output_utilization`.
- `cycles/bit`: total measured cycles divided by RTL bitstream bits.
- `cycles/input pixel`: total measured cycles divided by `width * height * frames`.
- Internal block utilization is testbench instrumentation. It is used to find
  pipeline starvation/backpressure and is not part of the codec bitstream contract.

## 2026-06-29 VVC Report Checkpoint

Baseline and current sources:

- Baseline Git SHA: `d2cb6801f111a0023d7f982b875faccbf8c17f91`
- Current validated source Git SHA: `28fa335ecfba2e9463e416688f0144bd29f159f3`
- Delta columns compare against the previous documented VVC output-utilization
  checkpoint where the same vector or aggregate was present.

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/VTM checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: PASS at 25 MHz target, WNS is positive.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 64 | 113168 (n/a) | 269058 (n/a) | 14146 (n/a) | 254912 (n/a) | 0.0526 (n/a) | 0.947 (n/a) | 2.38 (n/a) | 3.24 |
| `racehorses-multictu-420` | 10 | 92920 (n/a) | 281959 (n/a) | 11615 (n/a) | 270344 (n/a) | 0.0412 (n/a) | 0.959 (n/a) | 3.03 (n/a) | 3.07 |
| `screenshot-sweep-444` | 64 | 377064 (n/a) | 192968 (n/a) | 47133 (n/a) | 145835 (n/a) | 0.244 (n/a) | 0.756 (n/a) | 0.512 (n/a) | 2.33 |
| `screenshot-multictu-444` | 10 | 286232 (n/a) | 159519 (n/a) | 35779 (n/a) | 123740 (n/a) | 0.224 (n/a) | 0.776 (n/a) | 0.557 (n/a) | 1.74 |
| `multiframe-smoke` | 4 | 5184 (n/a) | 9799 (n/a) | 648 (n/a) | 9151 (n/a) | 0.0661 (n/a) | 0.934 (n/a) | 1.89 (n/a) | 2.04 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0526 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00279 |
| Frame reader sample issue | 0.177 |
| Reader-to-FIFO handshake | 0.233 |
| Frame reader current cache hit rate | 0 |
| Frame reader advance cache hit rate | 0.399 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.461 |
| Input FIFO full rate | 0.422 |
| CTU symbol issue | 0.947 |
| CTU residual symbol issue | 0.948 |
| VVC syntax frontend issue | 0.97 |
| VVC transform-skip residual issue | 0 |
| CABAC bin coder input issue | 0.97 |
| CABAC bin FIFO writer issue | 0.916 |
| CABAC bin FIFO nonempty rate | 0.266 |
| CABAC bin FIFO full rate | 0.108 |
| CABAC byte output issue | 0.953 |
| CABAC bit writer byte issue | 0.945 |
| RBSP payload issue | 0.918 |
| Stream writer emit issue | 0.983 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 (n/a) | 561 (n/a) | 71 (n/a) | 490 (n/a) | 0.127 (n/a) | 0.873 (n/a) | 0.988 (n/a) | 8.77 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 (n/a) | 763 (n/a) | 84 (n/a) | 679 (n/a) | 0.11 (n/a) | 0.89 (n/a) | 1.14 (n/a) | 5.96 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 (n/a) | 916 (n/a) | 90 (n/a) | 826 (n/a) | 0.0983 (n/a) | 0.902 (n/a) | 1.27 (n/a) | 4.77 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 (n/a) | 1112 (n/a) | 101 (n/a) | 1011 (n/a) | 0.0908 (n/a) | 0.909 (n/a) | 1.38 (n/a) | 4.34 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 (n/a) | 1287 (n/a) | 109 (n/a) | 1178 (n/a) | 0.0847 (n/a) | 0.915 (n/a) | 1.48 (n/a) | 4.02 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 (n/a) | 1515 (n/a) | 120 (n/a) | 1395 (n/a) | 0.0792 (n/a) | 0.921 (n/a) | 1.58 (n/a) | 3.95 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 (n/a) | 1716 (n/a) | 127 (n/a) | 1589 (n/a) | 0.074 (n/a) | 0.926 (n/a) | 1.69 (n/a) | 3.83 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 (n/a) | 1931 (n/a) | 140 (n/a) | 1791 (n/a) | 0.0725 (n/a) | 0.927 (n/a) | 1.72 (n/a) | 3.77 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 (n/a) | 703 (n/a) | 77 (n/a) | 626 (n/a) | 0.11 (n/a) | 0.89 (n/a) | 1.14 (n/a) | 5.49 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 (n/a) | 1096 (n/a) | 101 (n/a) | 995 (n/a) | 0.0922 (n/a) | 0.908 (n/a) | 1.36 (n/a) | 4.28 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (n/a) | 1429 (n/a) | 114 (n/a) | 1315 (n/a) | 0.0798 (n/a) | 0.92 (n/a) | 1.57 (n/a) | 3.72 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 (n/a) | 1784 (n/a) | 130 (n/a) | 1654 (n/a) | 0.0729 (n/a) | 0.927 (n/a) | 1.72 (n/a) | 3.48 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 (n/a) | 2195 (n/a) | 149 (n/a) | 2046 (n/a) | 0.0679 (n/a) | 0.932 (n/a) | 1.84 (n/a) | 3.43 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 (n/a) | 2552 (n/a) | 161 (n/a) | 2391 (n/a) | 0.0631 (n/a) | 0.937 (n/a) | 1.98 (n/a) | 3.32 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 (n/a) | 2993 (n/a) | 180 (n/a) | 2813 (n/a) | 0.0601 (n/a) | 0.94 (n/a) | 2.08 (n/a) | 3.34 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 (n/a) | 3392 (n/a) | 200 (n/a) | 3192 (n/a) | 0.059 (n/a) | 0.941 (n/a) | 2.12 (n/a) | 3.31 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 (n/a) | 871 (n/a) | 85 (n/a) | 786 (n/a) | 0.0976 (n/a) | 0.902 (n/a) | 1.28 (n/a) | 4.54 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 (n/a) | 1444 (n/a) | 115 (n/a) | 1329 (n/a) | 0.0796 (n/a) | 0.92 (n/a) | 1.57 (n/a) | 3.76 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 (n/a) | 1994 (n/a) | 137 (n/a) | 1857 (n/a) | 0.0687 (n/a) | 0.931 (n/a) | 1.82 (n/a) | 3.46 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 (n/a) | 2574 (n/a) | 164 (n/a) | 2410 (n/a) | 0.0637 (n/a) | 0.936 (n/a) | 1.96 (n/a) | 3.35 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 (n/a) | 3256 (n/a) | 188 (n/a) | 3068 (n/a) | 0.0577 (n/a) | 0.942 (n/a) | 2.16 (n/a) | 3.39 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 (n/a) | 3758 (n/a) | 209 (n/a) | 3549 (n/a) | 0.0556 (n/a) | 0.944 (n/a) | 2.25 (n/a) | 3.26 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 (n/a) | 4432 (n/a) | 238 (n/a) | 4194 (n/a) | 0.0537 (n/a) | 0.946 (n/a) | 2.33 (n/a) | 3.3 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 (n/a) | 5019 (n/a) | 261 (n/a) | 4758 (n/a) | 0.052 (n/a) | 0.948 (n/a) | 2.4 (n/a) | 3.27 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 (n/a) | 1076 (n/a) | 95 (n/a) | 981 (n/a) | 0.0883 (n/a) | 0.912 (n/a) | 1.42 (n/a) | 4.2 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 (n/a) | 1837 (n/a) | 133 (n/a) | 1704 (n/a) | 0.0724 (n/a) | 0.928 (n/a) | 1.73 (n/a) | 3.59 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 (n/a) | 2599 (n/a) | 163 (n/a) | 2436 (n/a) | 0.0627 (n/a) | 0.937 (n/a) | 1.99 (n/a) | 3.38 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 (n/a) | 3269 (n/a) | 193 (n/a) | 3076 (n/a) | 0.059 (n/a) | 0.941 (n/a) | 2.12 (n/a) | 3.19 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 (n/a) | 4146 (n/a) | 225 (n/a) | 3921 (n/a) | 0.0543 (n/a) | 0.946 (n/a) | 2.3 (n/a) | 3.24 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 (n/a) | 4892 (n/a) | 252 (n/a) | 4640 (n/a) | 0.0515 (n/a) | 0.948 (n/a) | 2.43 (n/a) | 3.18 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 (n/a) | 5776 (n/a) | 286 (n/a) | 5490 (n/a) | 0.0495 (n/a) | 0.95 (n/a) | 2.52 (n/a) | 3.22 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 (n/a) | 6485 (n/a) | 313 (n/a) | 6172 (n/a) | 0.0483 (n/a) | 0.952 (n/a) | 2.59 (n/a) | 3.17 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 (n/a) | 1210 (n/a) | 99 (n/a) | 1111 (n/a) | 0.0818 (n/a) | 0.918 (n/a) | 1.53 (n/a) | 3.78 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 (n/a) | 2184 (n/a) | 144 (n/a) | 2040 (n/a) | 0.0659 (n/a) | 0.934 (n/a) | 1.9 (n/a) | 3.41 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 (n/a) | 3203 (n/a) | 180 (n/a) | 3023 (n/a) | 0.0562 (n/a) | 0.944 (n/a) | 2.22 (n/a) | 3.34 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 (n/a) | 4109 (n/a) | 218 (n/a) | 3891 (n/a) | 0.0531 (n/a) | 0.947 (n/a) | 2.36 (n/a) | 3.21 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 (n/a) | 5140 (n/a) | 259 (n/a) | 4881 (n/a) | 0.0504 (n/a) | 0.95 (n/a) | 2.48 (n/a) | 3.21 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 (n/a) | 6086 (n/a) | 295 (n/a) | 5791 (n/a) | 0.0485 (n/a) | 0.952 (n/a) | 2.58 (n/a) | 3.17 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 (n/a) | 7141 (n/a) | 334 (n/a) | 6807 (n/a) | 0.0468 (n/a) | 0.953 (n/a) | 2.67 (n/a) | 3.19 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 (n/a) | 8070 (n/a) | 370 (n/a) | 7700 (n/a) | 0.0458 (n/a) | 0.954 (n/a) | 2.73 (n/a) | 3.15 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 (n/a) | 1388 (n/a) | 106 (n/a) | 1282 (n/a) | 0.0764 (n/a) | 0.924 (n/a) | 1.64 (n/a) | 3.61 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 (n/a) | 2554 (n/a) | 154 (n/a) | 2400 (n/a) | 0.0603 (n/a) | 0.94 (n/a) | 2.07 (n/a) | 3.33 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 (n/a) | 3752 (n/a) | 201 (n/a) | 3551 (n/a) | 0.0536 (n/a) | 0.946 (n/a) | 2.33 (n/a) | 3.26 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 (n/a) | 4797 (n/a) | 243 (n/a) | 4554 (n/a) | 0.0507 (n/a) | 0.949 (n/a) | 2.47 (n/a) | 3.12 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 (n/a) | 6002 (n/a) | 284 (n/a) | 5718 (n/a) | 0.0473 (n/a) | 0.953 (n/a) | 2.64 (n/a) | 3.13 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 (n/a) | 7212 (n/a) | 331 (n/a) | 6881 (n/a) | 0.0459 (n/a) | 0.954 (n/a) | 2.72 (n/a) | 3.13 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 (n/a) | 8414 (n/a) | 375 (n/a) | 8039 (n/a) | 0.0446 (n/a) | 0.955 (n/a) | 2.8 (n/a) | 3.13 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 (n/a) | 9403 (n/a) | 414 (n/a) | 8989 (n/a) | 0.044 (n/a) | 0.956 (n/a) | 2.84 (n/a) | 3.06 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 (n/a) | 1687 (n/a) | 121 (n/a) | 1566 (n/a) | 0.0717 (n/a) | 0.928 (n/a) | 1.74 (n/a) | 3.77 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 (n/a) | 3025 (n/a) | 180 (n/a) | 2845 (n/a) | 0.0595 (n/a) | 0.94 (n/a) | 2.1 (n/a) | 3.38 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 (n/a) | 4367 (n/a) | 227 (n/a) | 4140 (n/a) | 0.052 (n/a) | 0.948 (n/a) | 2.4 (n/a) | 3.25 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 (n/a) | 5677 (n/a) | 281 (n/a) | 5396 (n/a) | 0.0495 (n/a) | 0.951 (n/a) | 2.53 (n/a) | 3.17 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 (n/a) | 7076 (n/a) | 329 (n/a) | 6747 (n/a) | 0.0465 (n/a) | 0.954 (n/a) | 2.69 (n/a) | 3.16 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 (n/a) | 8389 (n/a) | 378 (n/a) | 8011 (n/a) | 0.0451 (n/a) | 0.955 (n/a) | 2.77 (n/a) | 3.12 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 (n/a) | 9826 (n/a) | 425 (n/a) | 9401 (n/a) | 0.0433 (n/a) | 0.957 (n/a) | 2.89 (n/a) | 3.13 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 (n/a) | 11094 (n/a) | 474 (n/a) | 10620 (n/a) | 0.0427 (n/a) | 0.957 (n/a) | 2.93 (n/a) | 3.1 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 (n/a) | 1882 (n/a) | 131 (n/a) | 1751 (n/a) | 0.0696 (n/a) | 0.93 (n/a) | 1.8 (n/a) | 3.68 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 (n/a) | 3423 (n/a) | 198 (n/a) | 3225 (n/a) | 0.0578 (n/a) | 0.942 (n/a) | 2.16 (n/a) | 3.34 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 (n/a) | 4977 (n/a) | 253 (n/a) | 4724 (n/a) | 0.0508 (n/a) | 0.949 (n/a) | 2.46 (n/a) | 3.24 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 (n/a) | 6431 (n/a) | 316 (n/a) | 6115 (n/a) | 0.0491 (n/a) | 0.951 (n/a) | 2.54 (n/a) | 3.14 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 (n/a) | 7959 (n/a) | 364 (n/a) | 7595 (n/a) | 0.0457 (n/a) | 0.954 (n/a) | 2.73 (n/a) | 3.11 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 (n/a) | 9475 (n/a) | 426 (n/a) | 9049 (n/a) | 0.045 (n/a) | 0.955 (n/a) | 2.78 (n/a) | 3.08 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 (n/a) | 11131 (n/a) | 485 (n/a) | 10646 (n/a) | 0.0436 (n/a) | 0.956 (n/a) | 2.87 (n/a) | 3.11 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 (n/a) | 12601 (n/a) | 540 (n/a) | 12061 (n/a) | 0.0429 (n/a) | 0.957 (n/a) | 2.92 (n/a) | 3.08 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0412 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00248 |
| Frame reader sample issue | 0.17 |
| Reader-to-FIFO handshake | 0.213 |
| Frame reader current cache hit rate | 0 |
| Frame reader advance cache hit rate | 0.431 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.488 |
| Input FIFO full rate | 0.47 |
| CTU symbol issue | 0.983 |
| CTU residual symbol issue | 0.984 |
| VVC syntax frontend issue | 0.99 |
| VVC transform-skip residual issue | 0 |
| CABAC bin coder input issue | 0.99 |
| CABAC bin FIFO writer issue | 0.925 |
| CABAC bin FIFO nonempty rate | 0.217 |
| CABAC bin FIFO full rate | 0.0387 |
| CABAC byte output issue | 1 |
| CABAC bit writer byte issue | 0.995 |
| RBSP payload issue | 0.998 |
| Stream writer emit issue | 0.997 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 (n/a) | 25342 (n/a) | 1060 (n/a) | 24282 (n/a) | 0.0418 (n/a) | 0.958 (n/a) | 2.99 (n/a) | 3.09 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 (n/a) | 25072 (n/a) | 1027 (n/a) | 24045 (n/a) | 0.041 (n/a) | 0.959 (n/a) | 3.05 (n/a) | 3.06 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 (n/a) | 49186 (n/a) | 1948 (n/a) | 47238 (n/a) | 0.0396 (n/a) | 0.96 (n/a) | 3.16 (n/a) | 3 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 (n/a) | 37814 (n/a) | 1583 (n/a) | 36231 (n/a) | 0.0419 (n/a) | 0.958 (n/a) | 2.99 (n/a) | 3.08 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 (n/a) | 36356 (n/a) | 1405 (n/a) | 34951 (n/a) | 0.0386 (n/a) | 0.961 (n/a) | 3.23 (n/a) | 2.96 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 (n/a) | 14492 (n/a) | 632 (n/a) | 13860 (n/a) | 0.0436 (n/a) | 0.956 (n/a) | 2.87 (n/a) | 3.14 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 (n/a) | 14613 (n/a) | 633 (n/a) | 13980 (n/a) | 0.0433 (n/a) | 0.957 (n/a) | 2.89 (n/a) | 3.17 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 (n/a) | 16827 (n/a) | 739 (n/a) | 16088 (n/a) | 0.0439 (n/a) | 0.956 (n/a) | 2.85 (n/a) | 3.25 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 (n/a) | 33706 (n/a) | 1408 (n/a) | 32298 (n/a) | 0.0418 (n/a) | 0.958 (n/a) | 2.99 (n/a) | 3.1 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 (n/a) | 28551 (n/a) | 1180 (n/a) | 27371 (n/a) | 0.0413 (n/a) | 0.959 (n/a) | 3.02 (n/a) | 3.1 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.244 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0147 |
| Frame reader sample issue | 0.441 |
| Reader-to-FIFO handshake | 1 |
| Frame reader current cache hit rate | 0 |
| Frame reader advance cache hit rate | 0.366 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| CTU symbol issue | 0.0259 |
| CTU residual symbol issue | 0 |
| VVC syntax frontend issue | 0.901 |
| VVC transform-skip residual issue | 0.218 |
| CABAC bin coder input issue | 0.893 |
| CABAC bin FIFO writer issue | 0.722 |
| CABAC bin FIFO nonempty rate | 0.775 |
| CABAC bin FIFO full rate | 0.236 |
| CABAC byte output issue | 0.929 |
| CABAC bit writer byte issue | 0.926 |
| RBSP payload issue | 0.927 |
| Stream writer emit issue | 0.931 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (n/a) | 384 (n/a) | 67 (n/a) | 317 (n/a) | 0.174 (n/a) | 0.826 (n/a) | 0.716 (n/a) | 6 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (n/a) | 654 (n/a) | 122 (n/a) | 532 (n/a) | 0.187 (n/a) | 0.813 (n/a) | 0.67 (n/a) | 5.11 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 (n/a) | 408 (n/a) | 72 (n/a) | 336 (n/a) | 0.176 (n/a) | 0.824 (n/a) | 0.708 (n/a) | 2.12 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 640 (n/a) | 502 (n/a) | 80 (n/a) | 422 (n/a) | 0.159 (n/a) | 0.841 (n/a) | 0.784 (n/a) | 1.96 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 608 (n/a) | 429 (n/a) | 76 (n/a) | 353 (n/a) | 0.177 (n/a) | 0.823 (n/a) | 0.706 (n/a) | 1.34 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 616 (n/a) | 437 (n/a) | 77 (n/a) | 360 (n/a) | 0.176 (n/a) | 0.824 (n/a) | 0.709 (n/a) | 1.14 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (n/a) | 2105 (n/a) | 586 (n/a) | 1519 (n/a) | 0.278 (n/a) | 0.722 (n/a) | 0.449 (n/a) | 4.7 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (n/a) | 2052 (n/a) | 543 (n/a) | 1509 (n/a) | 0.265 (n/a) | 0.735 (n/a) | 0.472 (n/a) | 4.01 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (n/a) | 700 (n/a) | 139 (n/a) | 561 (n/a) | 0.199 (n/a) | 0.801 (n/a) | 0.629 (n/a) | 5.47 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (n/a) | 1105 (n/a) | 280 (n/a) | 825 (n/a) | 0.253 (n/a) | 0.747 (n/a) | 0.493 (n/a) | 4.32 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 (n/a) | 455 (n/a) | 80 (n/a) | 375 (n/a) | 0.176 (n/a) | 0.824 (n/a) | 0.711 (n/a) | 1.18 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 656 (n/a) | 471 (n/a) | 82 (n/a) | 389 (n/a) | 0.174 (n/a) | 0.826 (n/a) | 0.718 (n/a) | 0.92 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (n/a) | 2712 (n/a) | 766 (n/a) | 1946 (n/a) | 0.282 (n/a) | 0.718 (n/a) | 0.443 (n/a) | 4.24 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 688 (n/a) | 613 (n/a) | 86 (n/a) | 527 (n/a) | 0.14 (n/a) | 0.86 (n/a) | 0.891 (n/a) | 0.798 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6200 (n/a) | 3021 (n/a) | 775 (n/a) | 2246 (n/a) | 0.257 (n/a) | 0.743 (n/a) | 0.487 (n/a) | 3.37 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 720 (n/a) | 803 (n/a) | 90 (n/a) | 713 (n/a) | 0.112 (n/a) | 0.888 (n/a) | 1.12 (n/a) | 0.784 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (n/a) | 1070 (n/a) | 288 (n/a) | 782 (n/a) | 0.269 (n/a) | 0.731 (n/a) | 0.464 (n/a) | 5.57 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 (n/a) | 879 (n/a) | 176 (n/a) | 703 (n/a) | 0.2 (n/a) | 0.8 (n/a) | 0.624 (n/a) | 2.29 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2848 (n/a) | 1504 (n/a) | 356 (n/a) | 1148 (n/a) | 0.237 (n/a) | 0.763 (n/a) | 0.528 (n/a) | 2.61 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (n/a) | 3420 (n/a) | 973 (n/a) | 2447 (n/a) | 0.285 (n/a) | 0.715 (n/a) | 0.439 (n/a) | 4.45 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6080 (n/a) | 3082 (n/a) | 760 (n/a) | 2322 (n/a) | 0.247 (n/a) | 0.753 (n/a) | 0.507 (n/a) | 3.21 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 736 (n/a) | 902 (n/a) | 92 (n/a) | 810 (n/a) | 0.102 (n/a) | 0.898 (n/a) | 1.23 (n/a) | 0.783 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 752 (n/a) | 1287 (n/a) | 94 (n/a) | 1193 (n/a) | 0.073 (n/a) | 0.927 (n/a) | 1.71 (n/a) | 0.958 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11328 (n/a) | 5229 (n/a) | 1416 (n/a) | 3813 (n/a) | 0.271 (n/a) | 0.729 (n/a) | 0.462 (n/a) | 3.4 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 (n/a) | 836 (n/a) | 188 (n/a) | 648 (n/a) | 0.225 (n/a) | 0.775 (n/a) | 0.556 (n/a) | 3.27 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 (n/a) | 847 (n/a) | 149 (n/a) | 698 (n/a) | 0.176 (n/a) | 0.824 (n/a) | 0.711 (n/a) | 1.65 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 (n/a) | 798 (n/a) | 131 (n/a) | 667 (n/a) | 0.164 (n/a) | 0.836 (n/a) | 0.761 (n/a) | 1.04 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4384 (n/a) | 2356 (n/a) | 548 (n/a) | 1808 (n/a) | 0.233 (n/a) | 0.767 (n/a) | 0.537 (n/a) | 2.3 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 776 (n/a) | 1282 (n/a) | 97 (n/a) | 1185 (n/a) | 0.0757 (n/a) | 0.924 (n/a) | 1.65 (n/a) | 1 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 (n/a) | 5659 (n/a) | 1604 (n/a) | 4055 (n/a) | 0.283 (n/a) | 0.717 (n/a) | 0.441 (n/a) | 3.68 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 12648 (n/a) | 5845 (n/a) | 1581 (n/a) | 4264 (n/a) | 0.27 (n/a) | 0.73 (n/a) | 0.462 (n/a) | 3.26 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 824 (n/a) | 1558 (n/a) | 103 (n/a) | 1455 (n/a) | 0.0661 (n/a) | 0.934 (n/a) | 1.89 (n/a) | 0.761 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (n/a) | 1514 (n/a) | 385 (n/a) | 1129 (n/a) | 0.254 (n/a) | 0.746 (n/a) | 0.492 (n/a) | 4.73 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (n/a) | 2746 (n/a) | 737 (n/a) | 2009 (n/a) | 0.268 (n/a) | 0.732 (n/a) | 0.466 (n/a) | 4.29 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1120 (n/a) | 1195 (n/a) | 140 (n/a) | 1055 (n/a) | 0.117 (n/a) | 0.883 (n/a) | 1.07 (n/a) | 1.24 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (n/a) | 4700 (n/a) | 1263 (n/a) | 3437 (n/a) | 0.269 (n/a) | 0.731 (n/a) | 0.465 (n/a) | 3.67 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 10736 (n/a) | 4838 (n/a) | 1342 (n/a) | 3496 (n/a) | 0.277 (n/a) | 0.723 (n/a) | 0.451 (n/a) | 3.02 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1296 (n/a) | 1704 (n/a) | 162 (n/a) | 1542 (n/a) | 0.0951 (n/a) | 0.905 (n/a) | 1.31 (n/a) | 0.887 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10288 (n/a) | 4913 (n/a) | 1286 (n/a) | 3627 (n/a) | 0.262 (n/a) | 0.738 (n/a) | 0.478 (n/a) | 2.19 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 944 (n/a) | 1962 (n/a) | 118 (n/a) | 1844 (n/a) | 0.0601 (n/a) | 0.94 (n/a) | 2.08 (n/a) | 0.766 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 (n/a) | 538 (n/a) | 90 (n/a) | 448 (n/a) | 0.167 (n/a) | 0.833 (n/a) | 0.747 (n/a) | 1.4 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (n/a) | 4063 (n/a) | 1224 (n/a) | 2839 (n/a) | 0.301 (n/a) | 0.699 (n/a) | 0.415 (n/a) | 5.29 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 (n/a) | 3401 (n/a) | 901 (n/a) | 2500 (n/a) | 0.265 (n/a) | 0.735 (n/a) | 0.472 (n/a) | 2.95 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7400 (n/a) | 3779 (n/a) | 925 (n/a) | 2854 (n/a) | 0.245 (n/a) | 0.755 (n/a) | 0.511 (n/a) | 2.46 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14728 (n/a) | 6573 (n/a) | 1841 (n/a) | 4732 (n/a) | 0.28 (n/a) | 0.72 (n/a) | 0.446 (n/a) | 3.42 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (n/a) | 1770 (n/a) | 110 (n/a) | 1660 (n/a) | 0.0621 (n/a) | 0.938 (n/a) | 2.01 (n/a) | 0.768 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9192 (n/a) | 4690 (n/a) | 1149 (n/a) | 3541 (n/a) | 0.245 (n/a) | 0.755 (n/a) | 0.51 (n/a) | 1.74 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 992 (n/a) | 2336 (n/a) | 124 (n/a) | 2212 (n/a) | 0.0531 (n/a) | 0.947 (n/a) | 2.35 (n/a) | 0.76 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (n/a) | 1747 (n/a) | 454 (n/a) | 1293 (n/a) | 0.26 (n/a) | 0.74 (n/a) | 0.481 (n/a) | 3.9 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 (n/a) | 2718 (n/a) | 727 (n/a) | 1991 (n/a) | 0.267 (n/a) | 0.733 (n/a) | 0.467 (n/a) | 3.03 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5936 (n/a) | 3083 (n/a) | 742 (n/a) | 2341 (n/a) | 0.241 (n/a) | 0.759 (n/a) | 0.519 (n/a) | 2.29 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9104 (n/a) | 4145 (n/a) | 1138 (n/a) | 3007 (n/a) | 0.275 (n/a) | 0.725 (n/a) | 0.455 (n/a) | 2.31 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17880 (n/a) | 7869 (n/a) | 2235 (n/a) | 5634 (n/a) | 0.284 (n/a) | 0.716 (n/a) | 0.44 (n/a) | 3.51 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10544 (n/a) | 5318 (n/a) | 1318 (n/a) | 4000 (n/a) | 0.248 (n/a) | 0.752 (n/a) | 0.504 (n/a) | 1.98 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25424 (n/a) | 11231 (n/a) | 3178 (n/a) | 8053 (n/a) | 0.283 (n/a) | 0.717 (n/a) | 0.442 (n/a) | 3.58 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12760 (n/a) | 6284 (n/a) | 1595 (n/a) | 4689 (n/a) | 0.254 (n/a) | 0.746 (n/a) | 0.492 (n/a) | 1.75 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (n/a) | 1437 (n/a) | 293 (n/a) | 1144 (n/a) | 0.204 (n/a) | 0.796 (n/a) | 0.613 (n/a) | 2.81 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8760 (n/a) | 3844 (n/a) | 1095 (n/a) | 2749 (n/a) | 0.285 (n/a) | 0.715 (n/a) | 0.439 (n/a) | 3.75 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6872 (n/a) | 3204 (n/a) | 859 (n/a) | 2345 (n/a) | 0.268 (n/a) | 0.732 (n/a) | 0.466 (n/a) | 2.09 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 (n/a) | 6562 (n/a) | 1760 (n/a) | 4802 (n/a) | 0.268 (n/a) | 0.732 (n/a) | 0.466 (n/a) | 3.2 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1464 (n/a) | 2545 (n/a) | 183 (n/a) | 2362 (n/a) | 0.0719 (n/a) | 0.928 (n/a) | 1.74 (n/a) | 0.994 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23128 (n/a) | 10381 (n/a) | 2891 (n/a) | 7490 (n/a) | 0.278 (n/a) | 0.722 (n/a) | 0.449 (n/a) | 3.38 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1696 (n/a) | 3666 (n/a) | 212 (n/a) | 3454 (n/a) | 0.0578 (n/a) | 0.942 (n/a) | 2.16 (n/a) | 1.02 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 (n/a) | 14807 (n/a) | 4179 (n/a) | 10628 (n/a) | 0.282 (n/a) | 0.718 (n/a) | 0.443 (n/a) | 3.61 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.224 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0139 |
| Frame reader sample issue | 0.453 |
| Reader-to-FIFO handshake | 1 |
| Frame reader current cache hit rate | 0 |
| Frame reader advance cache hit rate | 0.386 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| CTU symbol issue | 0.0279 |
| CTU residual symbol issue | 0 |
| VVC syntax frontend issue | 0.901 |
| VVC transform-skip residual issue | 0.543 |
| CABAC bin coder input issue | 0.893 |
| CABAC bin FIFO writer issue | 0.736 |
| CABAC bin FIFO nonempty rate | 0.725 |
| CABAC bin FIFO full rate | 0.228 |
| CABAC byte output issue | 0.989 |
| CABAC bit writer byte issue | 0.987 |
| RBSP payload issue | 0.987 |
| Stream writer emit issue | 0.991 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47296 (n/a) | 20764 (n/a) | 5912 (n/a) | 14852 (n/a) | 0.285 (n/a) | 0.715 (n/a) | 0.439 (n/a) | 2.53 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18584 (n/a) | 11899 (n/a) | 2323 (n/a) | 9576 (n/a) | 0.195 (n/a) | 0.805 (n/a) | 0.64 (n/a) | 1.45 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 4992 (n/a) | 12389 (n/a) | 624 (n/a) | 11765 (n/a) | 0.0504 (n/a) | 0.95 (n/a) | 2.48 (n/a) | 0.756 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33112 (n/a) | 18958 (n/a) | 4139 (n/a) | 14819 (n/a) | 0.218 (n/a) | 0.782 (n/a) | 0.573 (n/a) | 1.54 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49416 (n/a) | 24357 (n/a) | 6177 (n/a) | 18180 (n/a) | 0.254 (n/a) | 0.746 (n/a) | 0.493 (n/a) | 1.98 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27760 (n/a) | 13075 (n/a) | 3470 (n/a) | 9605 (n/a) | 0.265 (n/a) | 0.735 (n/a) | 0.471 (n/a) | 2.84 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1288 (n/a) | 3531 (n/a) | 161 (n/a) | 3370 (n/a) | 0.0456 (n/a) | 0.954 (n/a) | 2.74 (n/a) | 0.766 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 1848 (n/a) | 5152 (n/a) | 231 (n/a) | 4921 (n/a) | 0.0448 (n/a) | 0.955 (n/a) | 2.79 (n/a) | 0.994 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 63200 (n/a) | 30247 (n/a) | 7900 (n/a) | 22347 (n/a) | 0.261 (n/a) | 0.739 (n/a) | 0.479 (n/a) | 2.78 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38736 (n/a) | 19147 (n/a) | 4842 (n/a) | 14305 (n/a) | 0.253 (n/a) | 0.747 (n/a) | 0.494 (n/a) | 2.08 |

### Multi-Frame Smoke

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0661 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00327 |
| Frame reader sample issue | 0.375 |
| Reader-to-FIFO handshake | 0.745 |
| Frame reader current cache hit rate | 0 |
| Frame reader advance cache hit rate | 0.343 |
| Input FIFO-to-core handshake | 0.477 |
| Input FIFO nonempty rate | 0.22 |
| Input FIFO full rate | 0.0921 |
| CTU symbol issue | 0.497 |
| CTU residual symbol issue | 0.477 |
| VVC syntax frontend issue | 1 |
| VVC transform-skip residual issue | 0 |
| CABAC bin coder input issue | 1 |
| CABAC bin FIFO writer issue | 0.779 |
| CABAC bin FIFO nonempty rate | 0.0837 |
| CABAC bin FIFO full rate | 0 |
| CABAC byte output issue | 0.757 |
| CABAC bit writer byte issue | 0.731 |
| RBSP payload issue | 0.747 |
| Stream writer emit issue | 0.818 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| multiframe_black_420_16x16_2f_yuv420p8.yuv | PASS | 784 (n/a) | 1533 (n/a) | 98 (n/a) | 1435 (n/a) | 0.0639 (n/a) | 0.936 (n/a) | 1.96 (n/a) | 2.99 |
| multiframe_black_tall_420_8x24_5f_yuv420p8.yuv | PASS | 1288 (n/a) | 3140 (n/a) | 161 (n/a) | 2979 (n/a) | 0.0513 (n/a) | 0.949 (n/a) | 2.44 (n/a) | 3.27 |
| multiframe_motion_444_16x8_2f_yuv444p8.yuv | PASS | 784 (n/a) | 784 (n/a) | 98 (n/a) | 686 (n/a) | 0.125 (n/a) | 0.875 (n/a) | 1 (n/a) | 3.06 |
| multiframe_motion_wide_444_48x32_2f_yuv444p8.yuv | PASS | 2328 (n/a) | 4342 (n/a) | 291 (n/a) | 4051 (n/a) | 0.067 (n/a) | 0.933 (n/a) | 1.87 (n/a) | 1.41 |
