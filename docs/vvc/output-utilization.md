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

## 2026-06-22 CABAC FIFO Utilization Checkpoint

Baseline RTL/source Git SHA:

- `3945b1bc67a20e5cfa2ccf8d05910ab8741deef0`

Current RTL/source Git SHA:

- `f9077cf78f0faf98ca5659b84e852e29603322a0`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.

Target status:

- Requested target: bubble rate below `0.800`.
- Current aggregate results still miss that target. AXI output readiness is
  not limiting the stream; the remaining bubbles are dominated by serialized
  CABAC/bit-writer work and codec-side source symbol production.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 64 | 113168 (+0) | 285183 (-179051) | 14146 (+0) | 271037 (-179051) | 0.0496 (+0.0191) | 0.95 (-0.0196) | 2.52 (-1.58) | 3.44 |
| `racehorses-multictu-420` | 10 | 92920 (+0) | 285366 (-198034) | 11615 (+0) | 273751 (-198034) | 0.0407 (+0.0167) | 0.959 (-0.0167) | 3.07 (-2.13) | 3.11 |
| `screenshot-sweep-444` | 64 | 377168 (+0) | 569869 (-250702) | 47146 (+0) | 522723 (-250702) | 0.0827 (+0.0252) | 0.917 (-0.0257) | 1.51 (-0.669) | 6.87 |
| `screenshot-multictu-444` | 10 | 289000 (+0) | 543077 (-221697) | 36125 (+0) | 506952 (-221697) | 0.0665 (+0.0193) | 0.933 (-0.0195) | 1.88 (-0.771) | 5.91 |

Critical internal block utilization:

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0496 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00263 |
| Frame reader sample issue | 0.238 |
| Reader-to-FIFO handshake | 0.56 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.432 |
| Input FIFO full rate | 0.241 |
| VVC CTU symbolizer input | 1 |
| VVC residual symbolizer input | 1 |
| VVC source-symbol FIFO nonempty rate | 0.342 |
| VVC bin FIFO nonempty rate | 0.406 |
| VVC bin FIFO full rate | 0.0237 |
| VVC bin FIFO to writer | 0.831 |
| VVC syntax frontend input | 0.988 |
| VVC bin coder input | 0.988 |
| VVC stream emitter | 0.992 |
| VVC RBSP payload handoff | 0.992 |
| VVC CABAC byte handoff | 1 |
| VVC bit-writer output | 0.99 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 (+0) | 723 (-112) | 71 (+0) | 652 (-112) | 0.0982 (+0.0132) | 0.902 (-0.0132) | 1.27 (-0.197) | 11.3 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 (+0) | 936 (-278) | 84 (+0) | 852 (-278) | 0.0897 (+0.0205) | 0.91 (-0.0207) | 1.39 (-0.417) | 7.31 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 (+0) | 1121 (-400) | 90 (+0) | 1031 (-400) | 0.0803 (+0.0211) | 0.92 (-0.0213) | 1.56 (-0.553) | 5.84 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 (+0) | 1326 (-545) | 101 (+0) | 1225 (-545) | 0.0762 (+0.0222) | 0.924 (-0.0222) | 1.64 (-0.679) | 5.18 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 (+0) | 1549 (-698) | 109 (+0) | 1440 (-698) | 0.0704 (+0.0219) | 0.93 (-0.0214) | 1.78 (-0.804) | 4.84 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 (+0) | 1785 (-846) | 120 (+0) | 1665 (-846) | 0.0672 (+0.0216) | 0.933 (-0.0212) | 1.86 (-0.881) | 4.65 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 (+0) | 1980 (-988) | 127 (+0) | 1853 (-988) | 0.0641 (+0.0213) | 0.936 (-0.0211) | 1.95 (-0.971) | 4.42 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 (+0) | 2208 (-1168) | 140 (+0) | 2068 (-1168) | 0.0634 (+0.0219) | 0.937 (-0.0224) | 1.97 (-1.04) | 4.31 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 (+0) | 878 (-222) | 77 (+0) | 801 (-222) | 0.0877 (+0.0177) | 0.912 (-0.0177) | 1.43 (-0.365) | 6.86 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 (+0) | 1277 (-536) | 101 (+0) | 1176 (-536) | 0.0791 (+0.0234) | 0.921 (-0.0231) | 1.58 (-0.66) | 4.99 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 1646 (-804) | 114 (+0) | 1532 (-804) | 0.0693 (+0.0228) | 0.931 (-0.0223) | 1.8 (-0.885) | 4.29 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 (+0) | 2035 (-1066) | 130 (+0) | 1905 (-1066) | 0.0639 (+0.022) | 0.936 (-0.0219) | 1.96 (-1.02) | 3.97 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 (+0) | 2456 (-1378) | 149 (+0) | 2307 (-1378) | 0.0607 (+0.0218) | 0.939 (-0.0217) | 2.06 (-1.16) | 3.84 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 (+0) | 2820 (-1615) | 161 (+0) | 2659 (-1615) | 0.0571 (+0.0208) | 0.943 (-0.0211) | 2.19 (-1.25) | 3.67 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 (+0) | 3239 (-1940) | 180 (+0) | 3059 (-1940) | 0.0556 (+0.0208) | 0.944 (-0.0206) | 2.25 (-1.35) | 3.61 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 (+0) | 3647 (-2243) | 200 (+0) | 3447 (-2243) | 0.0548 (+0.0208) | 0.945 (-0.0208) | 2.28 (-1.4) | 3.56 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 (+0) | 1078 (-359) | 85 (+0) | 993 (-359) | 0.0788 (+0.0196) | 0.921 (-0.0198) | 1.59 (-0.525) | 5.61 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 (+0) | 1663 (-809) | 115 (+0) | 1548 (-809) | 0.0692 (+0.0227) | 0.931 (-0.0222) | 1.81 (-0.882) | 4.33 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 (+0) | 2249 (-1226) | 137 (+0) | 2112 (-1226) | 0.0609 (+0.0215) | 0.939 (-0.0219) | 2.05 (-1.12) | 3.9 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 (+0) | 2846 (-1627) | 164 (+0) | 2682 (-1627) | 0.0576 (+0.0209) | 0.942 (-0.0206) | 2.17 (-1.24) | 3.71 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 (+0) | 3505 (-2128) | 188 (+0) | 3317 (-2128) | 0.0536 (+0.0202) | 0.946 (-0.0206) | 2.33 (-1.42) | 3.65 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 (+0) | 4027 (-2496) | 209 (+0) | 3818 (-2496) | 0.0519 (+0.0199) | 0.948 (-0.0199) | 2.41 (-1.49) | 3.5 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 (+0) | 4679 (-2962) | 238 (+0) | 4441 (-2962) | 0.0509 (+0.0198) | 0.949 (-0.0199) | 2.46 (-1.55) | 3.48 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 (+0) | 5275 (-3426) | 261 (+0) | 5014 (-3426) | 0.0495 (+0.0195) | 0.951 (-0.0195) | 2.53 (-1.64) | 3.43 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 (+0) | 1281 (-516) | 95 (+0) | 1186 (-516) | 0.0742 (+0.0213) | 0.926 (-0.0212) | 1.69 (-0.674) | 5 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 (+0) | 2082 (-1106) | 133 (+0) | 1949 (-1106) | 0.0639 (+0.0222) | 0.936 (-0.0219) | 1.96 (-1.04) | 4.07 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 (+0) | 2861 (-1653) | 163 (+0) | 2698 (-1653) | 0.057 (+0.0209) | 0.943 (-0.021) | 2.19 (-1.27) | 3.73 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 (+0) | 3540 (-2177) | 193 (+0) | 3347 (-2177) | 0.0545 (+0.0207) | 0.945 (-0.0205) | 2.29 (-1.41) | 3.46 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 (+0) | 4406 (-2790) | 225 (+0) | 4181 (-2790) | 0.0511 (+0.0198) | 0.949 (-0.0201) | 2.45 (-1.55) | 3.44 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 (+0) | 5159 (-3321) | 252 (+0) | 4907 (-3321) | 0.0488 (+0.0191) | 0.951 (-0.0188) | 2.56 (-1.65) | 3.36 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 (+0) | 6023 (-3937) | 286 (+0) | 5737 (-3937) | 0.0475 (+0.0188) | 0.953 (-0.0185) | 2.63 (-1.72) | 3.36 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 (+0) | 6742 (-4531) | 313 (+0) | 6429 (-4531) | 0.0464 (+0.0186) | 0.954 (-0.0184) | 2.69 (-1.81) | 3.29 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 (+0) | 1495 (-606) | 99 (+0) | 1396 (-606) | 0.0662 (+0.0191) | 0.934 (-0.0192) | 1.89 (-0.762) | 4.67 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 (+0) | 2452 (-1329) | 144 (+0) | 2308 (-1329) | 0.0587 (+0.0206) | 0.941 (-0.0207) | 2.13 (-1.15) | 3.83 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 (+0) | 3465 (-2026) | 180 (+0) | 3285 (-2026) | 0.0519 (+0.0191) | 0.948 (-0.0189) | 2.41 (-1.4) | 3.61 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 (+0) | 4382 (-2734) | 218 (+0) | 4164 (-2734) | 0.0497 (+0.0191) | 0.95 (-0.0187) | 2.51 (-1.57) | 3.42 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 (+0) | 5401 (-3421) | 259 (+0) | 5142 (-3421) | 0.048 (+0.0186) | 0.952 (-0.019) | 2.61 (-1.65) | 3.38 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 (+0) | 6353 (-4114) | 295 (+0) | 6058 (-4114) | 0.0464 (+0.0182) | 0.954 (-0.0184) | 2.69 (-1.75) | 3.31 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 (+0) | 7388 (-4874) | 334 (+0) | 7054 (-4874) | 0.0452 (+0.018) | 0.955 (-0.0182) | 2.76 (-1.83) | 3.3 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 (+0) | 8328 (-5633) | 370 (+0) | 7958 (-5633) | 0.0444 (+0.0179) | 0.956 (-0.0174) | 2.81 (-1.91) | 3.25 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 (+0) | 1680 (-740) | 106 (+0) | 1574 (-740) | 0.0631 (+0.0193) | 0.937 (-0.0191) | 1.98 (-0.869) | 4.38 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 (+0) | 2821 (-1632) | 154 (+0) | 2667 (-1632) | 0.0546 (+0.02) | 0.945 (-0.0196) | 2.29 (-1.32) | 3.67 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 (+0) | 4013 (-2440) | 201 (+0) | 3812 (-2440) | 0.0501 (+0.019) | 0.95 (-0.0191) | 2.5 (-1.51) | 3.48 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 (+0) | 5069 (-3282) | 243 (+0) | 4826 (-3282) | 0.0479 (+0.0188) | 0.952 (-0.0189) | 2.61 (-1.69) | 3.3 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 (+0) | 6263 (-4063) | 284 (+0) | 5979 (-4063) | 0.0453 (+0.0178) | 0.955 (-0.0173) | 2.76 (-1.78) | 3.26 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 (+0) | 7479 (-4934) | 331 (+0) | 7148 (-4934) | 0.0443 (+0.0176) | 0.956 (-0.0173) | 2.82 (-1.87) | 3.25 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 (+0) | 8661 (-5808) | 375 (+0) | 8286 (-5808) | 0.0433 (+0.0174) | 0.957 (-0.0173) | 2.89 (-1.93) | 3.22 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 (+0) | 9663 (-6569) | 414 (+0) | 9249 (-6569) | 0.0428 (+0.0173) | 0.957 (-0.0168) | 2.92 (-1.98) | 3.15 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 (+0) | 1959 (-941) | 121 (+0) | 1838 (-941) | 0.0618 (+0.0201) | 0.938 (-0.0198) | 2.02 (-0.976) | 4.37 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 (+0) | 3292 (-1953) | 180 (+0) | 3112 (-1953) | 0.0547 (+0.0204) | 0.945 (-0.0207) | 2.29 (-1.35) | 3.67 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 (+0) | 4629 (-2878) | 227 (+0) | 4402 (-2878) | 0.049 (+0.0188) | 0.951 (-0.019) | 2.55 (-1.58) | 3.44 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 (+0) | 5937 (-3900) | 281 (+0) | 5656 (-3900) | 0.0473 (+0.0187) | 0.953 (-0.0183) | 2.64 (-1.74) | 3.31 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 (+0) | 7335 (-4845) | 329 (+0) | 7006 (-4845) | 0.0449 (+0.0179) | 0.955 (-0.0179) | 2.79 (-1.84) | 3.27 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 (+0) | 8655 (-5811) | 378 (+0) | 8277 (-5811) | 0.0437 (+0.0176) | 0.956 (-0.0177) | 2.86 (-1.92) | 3.22 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 (+0) | 10088 (-6803) | 425 (+0) | 9663 (-6803) | 0.0421 (+0.0169) | 0.958 (-0.0171) | 2.97 (-2) | 3.22 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 (+0) | 11366 (-7827) | 474 (+0) | 10892 (-7827) | 0.0417 (+0.017) | 0.958 (-0.0167) | 3 (-2.06) | 3.17 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 (+0) | 2147 (-1086) | 131 (+0) | 2016 (-1086) | 0.061 (+0.0205) | 0.939 (-0.02) | 2.05 (-1.03) | 4.19 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 (+0) | 3685 (-2221) | 198 (+0) | 3487 (-2221) | 0.0537 (+0.0202) | 0.946 (-0.0197) | 2.33 (-1.4) | 3.6 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 (+0) | 5239 (-3295) | 253 (+0) | 4986 (-3295) | 0.0483 (+0.0187) | 0.952 (-0.0183) | 2.59 (-1.63) | 3.41 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 (+0) | 6690 (-4475) | 316 (+0) | 6374 (-4475) | 0.0472 (+0.0189) | 0.953 (-0.0192) | 2.65 (-1.77) | 3.27 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 (+0) | 8203 (-5508) | 364 (+0) | 7839 (-5508) | 0.0444 (+0.0179) | 0.956 (-0.0174) | 2.82 (-1.89) | 3.2 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 (+0) | 9743 (-6595) | 426 (+0) | 9317 (-6595) | 0.0437 (+0.0176) | 0.956 (-0.0177) | 2.86 (-1.93) | 3.17 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 (+0) | 11391 (-7821) | 485 (+0) | 10906 (-7821) | 0.0426 (+0.0174) | 0.957 (-0.0176) | 2.94 (-2.01) | 3.18 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 (+0) | 12869 (-8984) | 540 (+0) | 12329 (-8984) | 0.042 (+0.0173) | 0.958 (-0.017) | 2.98 (-2.08) | 3.14 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0407 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00245 |
| Frame reader sample issue | 0.232 |
| Reader-to-FIFO handshake | 0.493 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.481 |
| Input FIFO full rate | 0.319 |
| VVC CTU symbolizer input | 0.995 |
| VVC residual symbolizer input | 0.994 |
| VVC source-symbol FIFO nonempty rate | 0.408 |
| VVC bin FIFO nonempty rate | 0.446 |
| VVC bin FIFO full rate | 0.192 |
| VVC bin FIFO to writer | 0.83 |
| VVC syntax frontend input | 0.909 |
| VVC bin coder input | 0.908 |
| VVC stream emitter | 0.997 |
| VVC RBSP payload handoff | 0.997 |
| VVC CABAC byte handoff | 1 |
| VVC bit-writer output | 0.996 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 (+0) | 25720 (-18003) | 1060 (+0) | 24660 (-18003) | 0.0412 (+0.017) | 0.959 (-0.0172) | 3.03 (-2.13) | 3.14 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 (+0) | 25376 (-17816) | 1027 (+0) | 24349 (-17816) | 0.0405 (+0.0167) | 0.96 (-0.0165) | 3.09 (-2.17) | 3.1 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 (+0) | 49541 (-34823) | 1948 (+0) | 47593 (-34823) | 0.0393 (+0.0162) | 0.961 (-0.0163) | 3.18 (-2.23) | 3.02 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 (+0) | 38331 (-26754) | 1583 (+0) | 36748 (-26754) | 0.0413 (+0.017) | 0.959 (-0.0173) | 3.03 (-2.11) | 3.12 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 (+0) | 36712 (-25650) | 1405 (+0) | 35307 (-25650) | 0.0383 (+0.0158) | 0.962 (-0.0153) | 3.27 (-2.28) | 2.99 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 (+0) | 14761 (-10094) | 632 (+0) | 14129 (-10094) | 0.0428 (+0.0174) | 0.957 (-0.0178) | 2.92 (-2) | 3.2 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 (+0) | 14913 (-10178) | 633 (+0) | 14280 (-10178) | 0.0424 (+0.0172) | 0.958 (-0.0174) | 2.94 (-2.01) | 3.24 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 (+0) | 17125 (-11459) | 739 (+0) | 16386 (-11459) | 0.0432 (+0.0173) | 0.957 (-0.0172) | 2.9 (-1.93) | 3.3 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 (+0) | 34031 (-23293) | 1408 (+0) | 32623 (-23293) | 0.0414 (+0.0168) | 0.959 (-0.0164) | 3.02 (-2.07) | 3.13 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 (+0) | 28856 (-19964) | 1180 (+0) | 27676 (-19964) | 0.0409 (+0.0167) | 0.959 (-0.0169) | 3.06 (-2.11) | 3.13 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0827 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00497 |
| Frame reader sample issue | 0.194 |
| Reader-to-FIFO handshake | 0.354 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.435 |
| Input FIFO full rate | 0.347 |
| VVC CTU symbolizer input | 0.0527 |
| VVC residual symbolizer input | 0 |
| VVC source-symbol FIFO nonempty rate | 0.424 |
| VVC bin FIFO nonempty rate | 0.409 |
| VVC bin FIFO full rate | 0.162 |
| VVC bin FIFO to writer | 0.534 |
| VVC syntax frontend input | 0.749 |
| VVC bin coder input | 0.738 |
| VVC stream emitter | 0.996 |
| VVC RBSP payload handoff | 0.994 |
| VVC CABAC byte handoff | 1 |
| VVC bit-writer output | 0.994 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (+0) | 890 (-50.0) | 67 (+0) | 823 (-50.0) | 0.0753 (+0.00398) | 0.925 (-0.00428) | 1.66 (-0.0896) | 13.9 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (+0) | 1558 (-418) | 122 (+0) | 1436 (-418) | 0.0783 (+0.0166) | 0.922 (-0.0163) | 1.6 (-0.424) | 12.2 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 (+0) | 1334 (-232) | 72 (+0) | 1262 (-232) | 0.054 (+0.00797) | 0.946 (-0.00797) | 2.32 (-0.404) | 6.95 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 648 (+0) | 1751 (-344) | 81 (+0) | 1670 (-344) | 0.0463 (+0.00756) | 0.954 (-0.00726) | 2.7 (-0.528) | 6.84 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 624 (+0) | 1792 (-378) | 78 (+0) | 1714 (-378) | 0.0435 (+0.00763) | 0.956 (-0.00753) | 2.87 (-0.608) | 5.6 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 640 (+0) | 2008 (-412) | 80 (+0) | 1928 (-412) | 0.0398 (+0.00674) | 0.96 (-0.00684) | 3.14 (-0.642) | 5.23 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (+0) | 4821 (-2025) | 586 (+0) | 4235 (-2025) | 0.122 (+0.036) | 0.878 (-0.0356) | 1.03 (-0.432) | 10.8 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (+0) | 4962 (-2287) | 543 (+0) | 4419 (-2287) | 0.109 (+0.0345) | 0.891 (-0.0344) | 1.14 (-0.528) | 9.69 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (+0) | 1600 (-422) | 139 (+0) | 1461 (-422) | 0.0869 (+0.0182) | 0.913 (-0.0179) | 1.44 (-0.381) | 12.5 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (+0) | 2680 (-839) | 280 (+0) | 2400 (-839) | 0.104 (+0.0249) | 0.896 (-0.0245) | 1.2 (-0.374) | 10.5 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 (+0) | 1986 (-550) | 80 (+0) | 1906 (-550) | 0.0403 (+0.00878) | 0.96 (-0.00828) | 3.1 (-0.857) | 5.17 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 672 (+0) | 2422 (-546) | 84 (+0) | 2338 (-546) | 0.0347 (+0.00638) | 0.965 (-0.00668) | 3.6 (-0.816) | 4.73 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (+0) | 6595 (-3208) | 766 (+0) | 5829 (-3208) | 0.116 (+0.038) | 0.884 (-0.0381) | 1.08 (-0.524) | 10.3 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 728 (+0) | 3322 (-835) | 91 (+0) | 3231 (-835) | 0.0274 (+0.00549) | 0.973 (-0.00539) | 4.56 (-1.15) | 4.33 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6192 (+0) | 7797 (-3613) | 774 (+0) | 7023 (-3613) | 0.0993 (+0.0315) | 0.901 (-0.0313) | 1.26 (-0.581) | 8.7 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 792 (+0) | 4227 (-1120) | 99 (+0) | 4128 (-1120) | 0.0234 (+0.00492) | 0.977 (-0.00442) | 5.34 (-1.41) | 4.13 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (+0) | 2406 (-626) | 288 (+0) | 2118 (-626) | 0.12 (+0.0247) | 0.88 (-0.0247) | 1.04 (-0.276) | 12.5 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 (+0) | 2810 (-988) | 176 (+0) | 2634 (-988) | 0.0626 (+0.0163) | 0.937 (-0.0166) | 2 (-0.704) | 7.32 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2832 (+0) | 4417 (-1767) | 354 (+0) | 4063 (-1767) | 0.0801 (+0.0229) | 0.92 (-0.0231) | 1.56 (-0.62) | 7.67 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (+0) | 7901 (-3391) | 973 (+0) | 6928 (-3391) | 0.123 (+0.0369) | 0.877 (-0.0371) | 1.02 (-0.435) | 10.3 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6072 (+0) | 8282 (-4118) | 759 (+0) | 7523 (-4118) | 0.0916 (+0.0304) | 0.908 (-0.0306) | 1.36 (-0.676) | 8.63 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 808 (+0) | 4701 (-1251) | 101 (+0) | 4600 (-1251) | 0.0215 (+0.00448) | 0.979 (-0.00448) | 5.82 (-1.55) | 4.08 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 848 (+0) | 5413 (-1823) | 106 (+0) | 5307 (-1823) | 0.0196 (+0.00498) | 0.98 (-0.00458) | 6.38 (-2.15) | 4.03 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11336 (+0) | 13255 (-6474) | 1417 (+0) | 11838 (-6474) | 0.107 (+0.0351) | 0.893 (-0.0349) | 1.17 (-0.571) | 8.63 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 (+0) | 2329 (-559) | 188 (+0) | 2141 (-559) | 0.0807 (+0.0156) | 0.919 (-0.0157) | 1.55 (-0.371) | 9.1 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 (+0) | 3186 (-1081) | 149 (+0) | 3037 (-1081) | 0.0468 (+0.0119) | 0.953 (-0.0118) | 2.67 (-0.907) | 6.22 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 (+0) | 3792 (-1475) | 131 (+0) | 3661 (-1475) | 0.0345 (+0.00965) | 0.965 (-0.00955) | 3.62 (-1.41) | 4.94 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4376 (+0) | 7150 (-3293) | 547 (+0) | 6603 (-3293) | 0.0765 (+0.0241) | 0.923 (-0.0245) | 1.63 (-0.756) | 6.98 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 848 (+0) | 5161 (-1838) | 106 (+0) | 5055 (-1838) | 0.0205 (+0.00544) | 0.979 (-0.00554) | 6.09 (-2.16) | 4.03 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 (+0) | 14232 (-6794) | 1604 (+0) | 12628 (-6794) | 0.113 (+0.0364) | 0.887 (-0.0367) | 1.11 (-0.531) | 9.27 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 11960 (+0) | 14641 (-7278) | 1495 (+0) | 13146 (-7278) | 0.102 (+0.0339) | 0.898 (-0.0341) | 1.22 (-0.606) | 8.17 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 984 (+0) | 7995 (-2255) | 123 (+0) | 7872 (-2255) | 0.0154 (+0.00338) | 0.985 (-0.00338) | 8.12 (-2.28) | 3.9 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (+0) | 3591 (-1582) | 385 (+0) | 3206 (-1582) | 0.107 (+0.0328) | 0.893 (-0.0332) | 1.17 (-0.514) | 11.2 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (+0) | 6314 (-3033) | 737 (+0) | 5577 (-3033) | 0.117 (+0.0379) | 0.883 (-0.0377) | 1.07 (-0.519) | 9.87 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1152 (+0) | 4836 (-2038) | 144 (+0) | 4692 (-2038) | 0.0298 (+0.00888) | 0.97 (-0.00878) | 4.2 (-1.77) | 5.04 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (+0) | 11659 (-5764) | 1263 (+0) | 10396 (-5764) | 0.108 (+0.0358) | 0.892 (-0.0363) | 1.15 (-0.566) | 9.11 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 9488 (+0) | 12039 (-6525) | 1186 (+0) | 10853 (-6525) | 0.0985 (+0.0346) | 0.901 (-0.0345) | 1.27 (-0.691) | 7.52 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1432 (+0) | 8189 (-2849) | 179 (+0) | 8010 (-2849) | 0.0219 (+0.00566) | 0.978 (-0.00586) | 5.72 (-1.99) | 4.27 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10336 (+0) | 15426 (-8047) | 1292 (+0) | 14134 (-8047) | 0.0838 (+0.0288) | 0.916 (-0.0288) | 1.49 (-0.778) | 6.89 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1160 (+0) | 10253 (-3134) | 145 (+0) | 10108 (-3134) | 0.0141 (+0.00334) | 0.986 (-0.00314) | 8.84 (-2.66) | 4.01 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 (+0) | 2330 (-463) | 90 (+0) | 2240 (-463) | 0.0386 (+0.00643) | 0.961 (-0.00663) | 3.24 (-0.644) | 6.07 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (+0) | 9081 (-4146) | 1224 (+0) | 7857 (-4146) | 0.135 (+0.0423) | 0.865 (-0.0418) | 0.927 (-0.423) | 11.8 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 (+0) | 9211 (-4894) | 901 (+0) | 8310 (-4894) | 0.0978 (+0.0339) | 0.902 (-0.0338) | 1.28 (-0.682) | 8 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7424 (+0) | 10985 (-5014) | 928 (+0) | 10057 (-5014) | 0.0845 (+0.0265) | 0.916 (-0.0265) | 1.48 (-0.68) | 7.15 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14736 (+0) | 16705 (-8838) | 1842 (+0) | 14863 (-8838) | 0.11 (+0.0382) | 0.89 (-0.0383) | 1.13 (-0.596) | 8.7 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1048 (+0) | 9030 (-2561) | 131 (+0) | 8899 (-2561) | 0.0145 (+0.00321) | 0.985 (-0.00351) | 8.62 (-2.48) | 3.92 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9240 (+0) | 17030 (-8273) | 1155 (+0) | 15875 (-8273) | 0.0678 (+0.0222) | 0.932 (-0.0218) | 1.84 (-0.897) | 6.34 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 12343 (-3611) | 155 (+0) | 12188 (-3611) | 0.0126 (+0.00284) | 0.987 (-0.00256) | 9.95 (-2.95) | 4.02 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (+0) | 4370 (-1648) | 454 (+0) | 3916 (-1648) | 0.104 (+0.0285) | 0.896 (-0.0289) | 1.2 (-0.457) | 9.75 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 (+0) | 7299 (-3162) | 727 (+0) | 6572 (-3162) | 0.0996 (+0.0301) | 0.9 (-0.0306) | 1.25 (-0.545) | 8.15 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5912 (+0) | 9153 (-4527) | 739 (+0) | 8414 (-4527) | 0.0807 (+0.0267) | 0.919 (-0.0267) | 1.55 (-0.762) | 6.81 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9136 (+0) | 12504 (-5440) | 1142 (+0) | 11362 (-5440) | 0.0913 (+0.0277) | 0.909 (-0.0273) | 1.37 (-0.591) | 6.98 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17856 (+0) | 20154 (-10412) | 2232 (+0) | 17922 (-10412) | 0.111 (+0.0377) | 0.889 (-0.0377) | 1.13 (-0.581) | 9 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10656 (+0) | 17255 (-7551) | 1332 (+0) | 15923 (-7551) | 0.0772 (+0.0235) | 0.923 (-0.0232) | 1.62 (-0.711) | 6.42 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25432 (+0) | 28712 (-14706) | 3179 (+0) | 25533 (-14706) | 0.111 (+0.0375) | 0.889 (-0.0377) | 1.13 (-0.581) | 9.16 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12904 (+0) | 22948 (-9732) | 1613 (+0) | 21335 (-9732) | 0.0703 (+0.0209) | 0.93 (-0.0213) | 1.78 (-0.752) | 6.4 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (+0) | 3996 (-1824) | 293 (+0) | 3703 (-1824) | 0.0733 (+0.023) | 0.927 (-0.0233) | 1.7 (-0.775) | 7.8 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8752 (+0) | 9518 (-4871) | 1094 (+0) | 8424 (-4871) | 0.115 (+0.0389) | 0.885 (-0.0389) | 1.09 (-0.552) | 9.29 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6888 (+0) | 10007 (-4821) | 861 (+0) | 9146 (-4821) | 0.086 (+0.0279) | 0.914 (-0.028) | 1.45 (-0.697) | 6.51 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 (+0) | 17058 (-8031) | 1760 (+0) | 15298 (-8031) | 0.103 (+0.033) | 0.897 (-0.0332) | 1.21 (-0.568) | 8.33 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1592 (+0) | 10647 (-4325) | 199 (+0) | 10448 (-4325) | 0.0187 (+0.00539) | 0.981 (-0.00569) | 6.69 (-2.71) | 4.16 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23088 (+0) | 26765 (-13178) | 2886 (+0) | 23879 (-13178) | 0.108 (+0.0355) | 0.892 (-0.0358) | 1.16 (-0.571) | 8.71 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1920 (+0) | 14853 (-6038) | 240 (+0) | 14613 (-6038) | 0.0162 (+0.00466) | 0.984 (-0.00516) | 7.74 (-3.16) | 4.14 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 (+0) | 38192 (-17374) | 4179 (+0) | 34013 (-17374) | 0.109 (+0.0342) | 0.891 (-0.0344) | 1.14 (-0.518) | 9.32 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0665 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00412 |
| Frame reader sample issue | 0.19 |
| Reader-to-FIFO handshake | 0.329 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.506 |
| Input FIFO full rate | 0.436 |
| VVC CTU symbolizer input | 0.0501 |
| VVC residual symbolizer input | 0 |
| VVC source-symbol FIFO nonempty rate | 0.366 |
| VVC bin FIFO nonempty rate | 0.352 |
| VVC bin FIFO full rate | 0.153 |
| VVC bin FIFO to writer | 0.531 |
| VVC syntax frontend input | 0.724 |
| VVC bin coder input | 0.714 |
| VVC stream emitter | 0.251 |
| VVC RBSP payload handoff | 0.251 |
| VVC CABAC byte handoff | 0.251 |
| VVC bit-writer output | 0.251 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47464 (+0) | 62263 (-26462) | 5933 (+0) | 56330 (-26462) | 0.0953 (+0.0284) | 0.905 (-0.0283) | 1.31 (-0.558) | 7.6 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18832 (+0) | 43697 (-16427) | 2354 (+0) | 41343 (-16427) | 0.0539 (+0.0147) | 0.946 (-0.0149) | 2.32 (-0.87) | 5.33 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 6288 (+0) | 66824 (-21202) | 786 (+0) | 66038 (-21202) | 0.0118 (+0.00283) | 0.988 (-0.00276) | 10.6 (-3.37) | 4.08 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33776 (+0) | 69258 (-25575) | 4222 (+0) | 65036 (-25575) | 0.061 (+0.0165) | 0.939 (-0.016) | 2.05 (-0.759) | 5.64 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49064 (+0) | 79030 (-33111) | 6133 (+0) | 72897 (-33111) | 0.0776 (+0.0229) | 0.922 (-0.0226) | 1.61 (-0.679) | 6.43 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27872 (+0) | 36724 (-17972) | 3484 (+0) | 33240 (-17972) | 0.0949 (+0.0312) | 0.905 (-0.0309) | 1.32 (-0.642) | 7.97 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1648 (+0) | 18523 (-5104) | 206 (+0) | 18317 (-5104) | 0.0111 (+0.0024) | 0.989 (-0.00212) | 11.2 (-3.06) | 4.02 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2232 (+0) | 21771 (-7777) | 279 (+0) | 21492 (-7777) | 0.0128 (+0.00338) | 0.987 (-0.00382) | 9.75 (-3.45) | 4.2 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 62832 (+0) | 83486 (-40121) | 7854 (+0) | 75632 (-40121) | 0.0941 (+0.0306) | 0.906 (-0.0301) | 1.33 (-0.641) | 7.67 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38992 (+0) | 61501 (-27946) | 4874 (+0) | 56627 (-27946) | 0.0793 (+0.0248) | 0.921 (-0.0253) | 1.58 (-0.713) | 6.67 |
