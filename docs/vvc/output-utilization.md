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

## 2026-06-22 Palette Syntax Scan Skip Checkpoint

Baseline RTL/source Git SHA:

- `e2fd88a0ebc7d05be240f48c61b2db9efad53023`

Current RTL/source Git SHA:

- `1f2e144c57cb20f7f7ca4aa2c436a6d43162a2c8`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.
- Yosys synthesis: PASS at 25 MHz metadata target; runtime exceeded the 300 second review threshold but stayed inside the 600 second hard stop.

Target status:

- Requested target: bubble rate below `0.800`.
- Current aggregate results still miss that target. The grouped palette index
  and escape seeks reduce idle CABAC syntax scan cycles without changing
  encoded bits, but CABAC byte production remains the dominant limiter.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 64 | 113168 (+0) | 269642 (+0) | 14146 (+0) | 255496 (+0) | 0.052 (+0.000) | 0.948 (+0.000) | 2.38 (+0) | 3.25 |
| `racehorses-multictu-420` | 10 | 92920 (+0) | 282276 (+0) | 11615 (+0) | 270661 (+0) | 0.041 (+0.000) | 0.959 (+0.000) | 3.04 (+0) | 3.07 |
| `screenshot-sweep-444` | 64 | 377168 (+0) | 488118 (-19131) | 47146 (+0) | 440972 (-19131) | 0.097 (+0.004) | 0.903 (-0.004) | 1.29 (-0.0458) | 5.88 |
| `screenshot-multictu-444` | 10 | 289000 (+0) | 484863 (-13469) | 36125 (+0) | 448738 (-13469) | 0.075 (+0.002) | 0.925 (-0.003) | 1.68 (-0.0423) | 5.28 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.052 |
| AXI write accepted-beat readiness | 1.000 |
| AXI write bus occupancy | 0.003 |
| Frame reader sample issue | 0.238 |
| Reader-to-FIFO handshake | 0.557 |
| Input FIFO-to-core handshake | 1.000 |
| Input FIFO nonempty rate | 0.457 |
| Input FIFO full rate | 0.255 |
| VVC CTU symbolizer input | 0.947 |
| VVC residual symbolizer input | 0.948 |
| VVC bin FIFO nonempty rate | 0.389 |
| VVC bin FIFO full rate | 0.108 |
| VVC bin FIFO to writer | 0.916 |
| VVC syntax frontend input | 0.970 |
| VVC bin coder input | 0.970 |
| VVC stream emitter | 0.986 |
| VVC RBSP payload handoff | 0.951 |
| VVC CABAC byte handoff | 0.958 |
| VVC bit-writer output | 0.950 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 (+0) | 563 (+0) | 71 (+0) | 492 (+0) | 0.126 (+0.000) | 0.874 (+0.000) | 0.991 (+0) | 8.8 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 (+0) | 771 (+0) | 84 (+0) | 687 (+0) | 0.109 (+0.000) | 0.891 (+0.000) | 1.15 (+0) | 6.02 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 (+0) | 918 (+0) | 90 (+0) | 828 (+0) | 0.098 (+0.000) | 0.902 (+0.000) | 1.27 (+0) | 4.78 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 (+0) | 1127 (+0) | 101 (+0) | 1026 (+0) | 0.090 (+0.000) | 0.910 (+0.000) | 1.39 (+0) | 4.4 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 (+0) | 1291 (+0) | 109 (+0) | 1182 (+0) | 0.084 (+0.000) | 0.916 (+0.000) | 1.48 (+0) | 4.03 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 (+0) | 1525 (+0) | 120 (+0) | 1405 (+0) | 0.079 (+0.000) | 0.921 (+0.000) | 1.59 (+0) | 3.97 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 (+0) | 1720 (+0) | 127 (+0) | 1593 (+0) | 0.074 (+0.000) | 0.926 (+0.000) | 1.69 (+0) | 3.84 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 (+0) | 1948 (+0) | 140 (+0) | 1808 (+0) | 0.072 (+0.000) | 0.928 (+0.000) | 1.74 (+0) | 3.8 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 (+0) | 705 (+0) | 77 (+0) | 628 (+0) | 0.109 (+0.000) | 0.891 (+0.000) | 1.14 (+0) | 5.51 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 (+0) | 1104 (+0) | 101 (+0) | 1003 (+0) | 0.091 (+0.000) | 0.909 (+0.000) | 1.37 (+0) | 4.31 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 1431 (+0) | 114 (+0) | 1317 (+0) | 0.080 (+0.000) | 0.920 (+0.000) | 1.57 (+0) | 3.73 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 (+0) | 1799 (+0) | 130 (+0) | 1669 (+0) | 0.072 (+0.000) | 0.928 (+0.000) | 1.73 (+0) | 3.51 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 (+0) | 2199 (+0) | 149 (+0) | 2050 (+0) | 0.068 (+0.000) | 0.932 (+0.000) | 1.84 (+0) | 3.44 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 (+0) | 2562 (+0) | 161 (+0) | 2401 (+0) | 0.063 (+0.000) | 0.937 (+0.000) | 1.99 (+0) | 3.34 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 (+0) | 2997 (+0) | 180 (+0) | 2817 (+0) | 0.060 (+0.000) | 0.940 (+0.000) | 2.08 (+0) | 3.34 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 (+0) | 3409 (+0) | 200 (+0) | 3209 (+0) | 0.059 (+0.000) | 0.941 (+0.000) | 2.13 (+0) | 3.33 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 (+0) | 874 (+0) | 85 (+0) | 789 (+0) | 0.097 (+0.000) | 0.903 (+0.000) | 1.29 (+0) | 4.55 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 (+0) | 1452 (+0) | 115 (+0) | 1337 (+0) | 0.079 (+0.000) | 0.921 (+0.000) | 1.58 (+0) | 3.78 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 (+0) | 1998 (+0) | 137 (+0) | 1861 (+0) | 0.069 (+0.000) | 0.931 (+0.000) | 1.82 (+0) | 3.47 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 (+0) | 2591 (+0) | 164 (+0) | 2427 (+0) | 0.063 (+0.000) | 0.937 (+0.000) | 1.97 (+0) | 3.37 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 (+0) | 3260 (+0) | 188 (+0) | 3072 (+0) | 0.058 (+0.000) | 0.942 (+0.000) | 2.17 (+0) | 3.4 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 (+0) | 3768 (+0) | 209 (+0) | 3559 (+0) | 0.055 (+0.000) | 0.945 (+0.000) | 2.25 (+0) | 3.27 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 (+0) | 4436 (+0) | 238 (+0) | 4198 (+0) | 0.054 (+0.000) | 0.946 (+0.000) | 2.33 (+0) | 3.3 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 (+0) | 5036 (+0) | 261 (+0) | 4775 (+0) | 0.052 (+0.000) | 0.948 (+0.000) | 2.41 (+0) | 3.28 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 (+0) | 1079 (+0) | 95 (+0) | 984 (+0) | 0.088 (+0.000) | 0.912 (+0.000) | 1.42 (+0) | 4.21 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 (+0) | 1845 (+0) | 133 (+0) | 1712 (+0) | 0.072 (+0.000) | 0.928 (+0.000) | 1.73 (+0) | 3.6 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 (+0) | 2603 (+0) | 163 (+0) | 2440 (+0) | 0.063 (+0.000) | 0.937 (+0.000) | 2 (+0) | 3.39 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 (+0) | 3286 (+0) | 193 (+0) | 3093 (+0) | 0.059 (+0.000) | 0.941 (+0.000) | 2.13 (+0) | 3.21 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 (+0) | 4150 (+0) | 225 (+0) | 3925 (+0) | 0.054 (+0.000) | 0.946 (+0.000) | 2.31 (+0) | 3.24 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 (+0) | 4902 (+0) | 252 (+0) | 4650 (+0) | 0.051 (+0.000) | 0.949 (+0.000) | 2.43 (+0) | 3.19 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 (+0) | 5780 (+0) | 286 (+0) | 5494 (+0) | 0.049 (+0.000) | 0.951 (+0.000) | 2.53 (+0) | 3.23 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 (+0) | 6502 (+0) | 313 (+0) | 6189 (+0) | 0.048 (+0.000) | 0.952 (+0.000) | 2.6 (+0) | 3.17 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 (+0) | 1225 (+0) | 99 (+0) | 1126 (+0) | 0.081 (+0.000) | 0.919 (+0.000) | 1.55 (+0) | 3.83 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 (+0) | 2194 (+0) | 144 (+0) | 2050 (+0) | 0.066 (+0.000) | 0.934 (+0.000) | 1.9 (+0) | 3.43 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 (+0) | 3207 (+0) | 180 (+0) | 3027 (+0) | 0.056 (+0.000) | 0.944 (+0.000) | 2.23 (+0) | 3.34 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 (+0) | 4126 (+0) | 218 (+0) | 3908 (+0) | 0.053 (+0.000) | 0.947 (+0.000) | 2.37 (+0) | 3.22 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 (+0) | 5144 (+0) | 259 (+0) | 4885 (+0) | 0.050 (+0.000) | 0.950 (+0.000) | 2.48 (+0) | 3.21 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 (+0) | 6096 (+0) | 295 (+0) | 5801 (+0) | 0.048 (+0.000) | 0.952 (+0.000) | 2.58 (+0) | 3.17 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 (+0) | 7145 (+0) | 334 (+0) | 6811 (+0) | 0.047 (+0.000) | 0.953 (+0.000) | 2.67 (+0) | 3.19 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 (+0) | 8087 (+0) | 370 (+0) | 7717 (+0) | 0.046 (+0.000) | 0.954 (+0.000) | 2.73 (+0) | 3.16 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 (+0) | 1403 (+0) | 106 (+0) | 1297 (+0) | 0.076 (+0.000) | 0.924 (+0.000) | 1.65 (+0) | 3.65 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 (+0) | 2564 (+0) | 154 (+0) | 2410 (+0) | 0.060 (+0.000) | 0.940 (+0.000) | 2.08 (+0) | 3.34 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 (+0) | 3756 (+0) | 201 (+0) | 3555 (+0) | 0.054 (+0.000) | 0.946 (+0.000) | 2.34 (+0) | 3.26 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 (+0) | 4814 (+0) | 243 (+0) | 4571 (+0) | 0.050 (+0.000) | 0.950 (+0.000) | 2.48 (+0) | 3.13 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 (+0) | 6006 (+0) | 284 (+0) | 5722 (+0) | 0.047 (+0.000) | 0.953 (+0.000) | 2.64 (+0) | 3.13 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 (+0) | 7222 (+0) | 331 (+0) | 6891 (+0) | 0.046 (+0.000) | 0.954 (+0.000) | 2.73 (+0) | 3.13 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 (+0) | 8418 (+0) | 375 (+0) | 8043 (+0) | 0.045 (+0.000) | 0.955 (+0.000) | 2.81 (+0) | 3.13 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 (+0) | 9420 (+0) | 414 (+0) | 9006 (+0) | 0.044 (+0.000) | 0.956 (+0.000) | 2.84 (+0) | 3.07 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 (+0) | 1703 (+0) | 121 (+0) | 1582 (+0) | 0.071 (+0.000) | 0.929 (+0.000) | 1.76 (+0) | 3.8 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 (+0) | 3035 (+0) | 180 (+0) | 2855 (+0) | 0.059 (+0.000) | 0.941 (+0.000) | 2.11 (+0) | 3.39 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 (+0) | 4371 (+0) | 227 (+0) | 4144 (+0) | 0.052 (+0.000) | 0.948 (+0.000) | 2.41 (+0) | 3.25 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 (+0) | 5694 (+0) | 281 (+0) | 5413 (+0) | 0.049 (+0.000) | 0.951 (+0.000) | 2.53 (+0) | 3.18 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 (+0) | 7080 (+0) | 329 (+0) | 6751 (+0) | 0.046 (+0.000) | 0.954 (+0.000) | 2.69 (+0) | 3.16 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 (+0) | 8399 (+0) | 378 (+0) | 8021 (+0) | 0.045 (+0.000) | 0.955 (+0.000) | 2.78 (+0) | 3.12 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 (+0) | 9830 (+0) | 425 (+0) | 9405 (+0) | 0.043 (+0.000) | 0.957 (+0.000) | 2.89 (+0) | 3.13 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 (+0) | 11111 (+0) | 474 (+0) | 10637 (+0) | 0.043 (+0.000) | 0.957 (+0.000) | 2.93 (+0) | 3.1 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 (+0) | 1898 (+0) | 131 (+0) | 1767 (+0) | 0.069 (+0.000) | 0.931 (+0.000) | 1.81 (+0) | 3.71 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 (+0) | 3433 (+0) | 198 (+0) | 3235 (+0) | 0.058 (+0.000) | 0.942 (+0.000) | 2.17 (+0) | 3.35 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 (+0) | 4981 (+0) | 253 (+0) | 4728 (+0) | 0.051 (+0.000) | 0.949 (+0.000) | 2.46 (+0) | 3.24 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 (+0) | 6448 (+0) | 316 (+0) | 6132 (+0) | 0.049 (+0.000) | 0.951 (+0.000) | 2.55 (+0) | 3.15 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 (+0) | 7963 (+0) | 364 (+0) | 7599 (+0) | 0.046 (+0.000) | 0.954 (+0.000) | 2.73 (+0) | 3.11 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 (+0) | 9485 (+0) | 426 (+0) | 9059 (+0) | 0.045 (+0.000) | 0.955 (+0.000) | 2.78 (+0) | 3.09 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 (+0) | 11135 (+0) | 485 (+0) | 10650 (+0) | 0.044 (+0.000) | 0.956 (+0.000) | 2.87 (+0) | 3.11 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 (+0) | 12618 (+0) | 540 (+0) | 12078 (+0) | 0.043 (+0.000) | 0.957 (+0.000) | 2.92 (+0) | 3.08 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.041 |
| AXI write accepted-beat readiness | 1.000 |
| AXI write bus occupancy | 0.002 |
| Frame reader sample issue | 0.232 |
| Reader-to-FIFO handshake | 0.493 |
| Input FIFO-to-core handshake | 1.000 |
| Input FIFO nonempty rate | 0.486 |
| Input FIFO full rate | 0.323 |
| VVC CTU symbolizer input | 0.983 |
| VVC residual symbolizer input | 0.984 |
| VVC bin FIFO nonempty rate | 0.405 |
| VVC bin FIFO full rate | 0.039 |
| VVC bin FIFO to writer | 0.925 |
| VVC syntax frontend input | 0.990 |
| VVC bin coder input | 0.990 |
| VVC stream emitter | 0.997 |
| VVC RBSP payload handoff | 0.996 |
| VVC CABAC byte handoff | 1.000 |
| VVC bit-writer output | 0.996 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 (+0) | 25376 (+0) | 1060 (+0) | 24316 (+0) | 0.042 (+0.000) | 0.958 (+0.000) | 2.99 (+0) | 3.1 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 (+0) | 25100 (+0) | 1027 (+0) | 24073 (+0) | 0.041 (+0.000) | 0.959 (+0.000) | 3.06 (+0) | 3.06 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 (+0) | 49242 (+0) | 1948 (+0) | 47294 (+0) | 0.040 (+0.000) | 0.960 (+0.000) | 3.16 (+0) | 3.01 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 (+0) | 37865 (+0) | 1583 (+0) | 36282 (+0) | 0.042 (+0.000) | 0.958 (+0.000) | 2.99 (+0) | 3.08 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 (+0) | 36394 (+0) | 1405 (+0) | 34989 (+0) | 0.039 (+0.000) | 0.961 (+0.000) | 3.24 (+0) | 2.96 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 (+0) | 14512 (+0) | 632 (+0) | 13880 (+0) | 0.044 (+0.000) | 0.956 (+0.000) | 2.87 (+0) | 3.15 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 (+0) | 14641 (+0) | 633 (+0) | 14008 (+0) | 0.043 (+0.000) | 0.957 (+0.000) | 2.89 (+0) | 3.18 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 (+0) | 16843 (+0) | 739 (+0) | 16104 (+0) | 0.044 (+0.000) | 0.956 (+0.000) | 2.85 (+0) | 3.25 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 (+0) | 33724 (+0) | 1408 (+0) | 32316 (+0) | 0.042 (+0.000) | 0.958 (+0.000) | 2.99 (+0) | 3.1 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 (+0) | 28579 (+0) | 1180 (+0) | 27399 (+0) | 0.041 (+0.000) | 0.959 (+0.000) | 3.03 (+0) | 3.1 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.097 |
| AXI write accepted-beat readiness | 1.000 |
| AXI write bus occupancy | 0.006 |
| Frame reader sample issue | 0.193 |
| Reader-to-FIFO handshake | 0.353 |
| Input FIFO-to-core handshake | 1.000 |
| Input FIFO nonempty rate | 0.508 |
| Input FIFO full rate | 0.405 |
| VVC CTU symbolizer input | 0.082 |
| VVC residual symbolizer input | 0.000 |
| VVC bin FIFO nonempty rate | 0.325 |
| VVC bin FIFO full rate | 0.022 |
| VVC bin FIFO to writer | 0.740 |
| VVC syntax frontend input | 0.969 |
| VVC bin coder input | 0.968 |
| VVC stream emitter | 0.919 |
| VVC RBSP payload handoff | 0.912 |
| VVC CABAC byte handoff | 0.916 |
| VVC bit-writer output | 0.913 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (+0) | 690 (+0) | 67 (+0) | 623 (+0) | 0.097 (+0.000) | 0.903 (+0.000) | 1.29 (+0) | 10.8 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (+0) | 1253 (-77) | 122 (+0) | 1131 (-77) | 0.097 (+0.006) | 0.903 (-0.005) | 1.28 (-0.0762) | 9.79 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 (+0) | 1121 (+0) | 72 (+0) | 1049 (+0) | 0.064 (+0.000) | 0.936 (+0.000) | 1.95 (+0) | 5.84 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 648 (+0) | 1468 (-46) | 81 (+0) | 1387 (-46) | 0.055 (+0.002) | 0.945 (-0.001) | 2.27 (-0.0746) | 5.73 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 624 (+0) | 1572 (+0) | 78 (+0) | 1494 (+0) | 0.050 (+0.000) | 0.950 (+0.000) | 2.52 (+0) | 4.91 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 640 (+0) | 1785 (+0) | 80 (+0) | 1705 (+0) | 0.045 (+0.000) | 0.955 (+0.000) | 2.79 (+0) | 4.65 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (+0) | 3766 (-163) | 586 (+0) | 3180 (-163) | 0.156 (+0.007) | 0.844 (-0.007) | 0.803 (-0.0347) | 8.41 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (+0) | 4036 (-233) | 543 (+0) | 3493 (-233) | 0.135 (+0.008) | 0.865 (-0.008) | 0.929 (-0.0539) | 7.88 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (+0) | 1286 (-64) | 139 (+0) | 1147 (-64) | 0.108 (+0.005) | 0.892 (-0.005) | 1.16 (-0.0535) | 10 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (+0) | 2062 (-68) | 280 (+0) | 1782 (-68) | 0.136 (+0.005) | 0.864 (-0.005) | 0.921 (-0.0305) | 8.05 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 (+0) | 1766 (+0) | 80 (+0) | 1686 (+0) | 0.045 (+0.000) | 0.955 (+0.000) | 2.76 (+0) | 4.6 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 672 (+0) | 2194 (+0) | 84 (+0) | 2110 (+0) | 0.038 (+0.000) | 0.962 (+0.000) | 3.26 (+0) | 4.29 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (+0) | 5075 (-373) | 766 (+0) | 4309 (-373) | 0.151 (+0.010) | 0.849 (-0.010) | 0.828 (-0.0608) | 7.93 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 728 (+0) | 3085 (+0) | 91 (+0) | 2994 (+0) | 0.029 (+0.000) | 0.971 (+0.000) | 4.24 (+0) | 4.02 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6192 (+0) | 6389 (-273) | 774 (+0) | 5615 (-273) | 0.121 (+0.005) | 0.879 (-0.005) | 1.03 (-0.0482) | 7.13 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 792 (+0) | 3981 (+0) | 99 (+0) | 3882 (+0) | 0.025 (+0.000) | 0.975 (+0.000) | 5.03 (+0) | 3.89 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (+0) | 1790 (-9) | 288 (+0) | 1502 (-9) | 0.161 (+0.001) | 0.839 (-0.001) | 0.777 (-0.00409) | 9.32 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 (+0) | 2331 (-99) | 176 (+0) | 2155 (-99) | 0.076 (+0.003) | 0.924 (-0.004) | 1.66 (-0.0745) | 6.07 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2832 (+0) | 3566 (-126) | 354 (+0) | 3212 (-126) | 0.099 (+0.003) | 0.901 (-0.003) | 1.26 (-0.0408) | 6.19 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (+0) | 6197 (-271) | 973 (+0) | 5224 (-271) | 0.157 (+0.007) | 0.843 (-0.007) | 0.796 (-0.0349) | 8.07 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6072 (+0) | 6800 (-507) | 759 (+0) | 6041 (-507) | 0.112 (+0.008) | 0.888 (-0.008) | 1.12 (-0.0801) | 7.08 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 808 (+0) | 4452 (+0) | 101 (+0) | 4351 (+0) | 0.023 (+0.000) | 0.977 (+0.000) | 5.51 (+0) | 3.86 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 848 (+0) | 5157 (+0) | 106 (+0) | 5051 (+0) | 0.021 (+0.000) | 0.979 (+0.000) | 6.08 (+0) | 3.84 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11336 (+0) | 11026 (-528) | 1417 (+0) | 9609 (-528) | 0.129 (+0.006) | 0.871 (-0.006) | 0.973 (-0.0473) | 7.18 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 (+0) | 1780 (-42) | 188 (+0) | 1592 (-42) | 0.106 (+0.003) | 0.894 (-0.003) | 1.18 (-0.0265) | 6.95 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 (+0) | 2722 (-118) | 149 (+0) | 2573 (-118) | 0.055 (+0.002) | 0.945 (-0.003) | 2.28 (-0.0964) | 5.32 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 (+0) | 3447 (-82) | 131 (+0) | 3316 (-82) | 0.038 (+0.001) | 0.962 (-0.001) | 3.29 (-0.0809) | 4.49 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4376 (+0) | 6205 (-432) | 547 (+0) | 5658 (-432) | 0.088 (+0.006) | 0.912 (-0.006) | 1.42 (-0.102) | 6.06 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 848 (+0) | 4906 (+0) | 106 (+0) | 4800 (+0) | 0.022 (+0.000) | 0.978 (+0.000) | 5.79 (+0) | 3.83 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 (+0) | 11664 (-647) | 1604 (+0) | 10060 (-647) | 0.138 (+0.008) | 0.862 (-0.008) | 0.909 (-0.05) | 7.59 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 11960 (+0) | 12174 (-447) | 1495 (+0) | 10679 (-447) | 0.123 (+0.005) | 0.877 (-0.005) | 1.02 (-0.0421) | 6.79 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 984 (+0) | 7719 (+0) | 123 (+0) | 7596 (+0) | 0.016 (+0.000) | 0.984 (+0.000) | 7.84 (+0) | 3.77 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (+0) | 2841 (-266) | 385 (+0) | 2456 (-266) | 0.136 (+0.012) | 0.864 (-0.012) | 0.922 (-0.0876) | 8.88 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (+0) | 5154 (-206) | 737 (+0) | 4417 (-206) | 0.143 (+0.005) | 0.857 (-0.006) | 0.874 (-0.0348) | 8.05 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1152 (+0) | 4279 (-127) | 144 (+0) | 4135 (-127) | 0.034 (+0.001) | 0.966 (-0.001) | 3.71 (-0.106) | 4.46 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (+0) | 9701 (-634) | 1263 (+0) | 8438 (-634) | 0.130 (+0.008) | 0.870 (-0.008) | 0.96 (-0.0599) | 7.58 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 9488 (+0) | 10236 (-551) | 1186 (+0) | 9050 (-551) | 0.116 (+0.006) | 0.884 (-0.006) | 1.08 (-0.0612) | 6.4 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1432 (+0) | 7785 (-119) | 179 (+0) | 7606 (-119) | 0.023 (+0.000) | 0.977 (+0.000) | 5.44 (-0.0835) | 4.05 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10336 (+0) | 13384 (-591) | 1292 (+0) | 12092 (-591) | 0.097 (+0.004) | 0.903 (-0.005) | 1.29 (-0.0551) | 5.97 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1160 (+0) | 9858 (-46) | 145 (+0) | 9713 (-46) | 0.015 (+0.000) | 0.985 (+0.000) | 8.5 (-0.0417) | 3.85 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 (+0) | 1917 (-46) | 90 (+0) | 1827 (-46) | 0.047 (+0.001) | 0.953 (-0.001) | 2.66 (-0.0675) | 4.99 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (+0) | 6904 (-398) | 1224 (+0) | 5680 (-398) | 0.177 (+0.009) | 0.823 (-0.009) | 0.705 (-0.0409) | 8.99 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 (+0) | 7666 (-304) | 901 (+0) | 6765 (-304) | 0.118 (+0.005) | 0.882 (-0.005) | 1.06 (-0.0465) | 6.65 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7424 (+0) | 9564 (-473) | 928 (+0) | 8636 (-473) | 0.097 (+0.005) | 0.903 (-0.005) | 1.29 (-0.0617) | 6.23 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14736 (+0) | 13844 (-741) | 1842 (+0) | 12002 (-741) | 0.133 (+0.007) | 0.867 (-0.007) | 0.939 (-0.0505) | 7.21 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1048 (+0) | 8738 (+0) | 131 (+0) | 8607 (+0) | 0.015 (+0.000) | 0.985 (+0.000) | 8.34 (+0) | 3.79 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9240 (+0) | 15002 (-685) | 1155 (+0) | 13847 (-685) | 0.077 (+0.003) | 0.923 (-0.003) | 1.62 (-0.0764) | 5.58 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 11859 (-46) | 155 (+0) | 11704 (-46) | 0.013 (+0.000) | 0.987 (+0.000) | 9.56 (-0.0363) | 3.86 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (+0) | 3446 (-156) | 454 (+0) | 2992 (-156) | 0.132 (+0.006) | 0.868 (-0.006) | 0.949 (-0.0432) | 7.69 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 (+0) | 5950 (-256) | 727 (+0) | 5223 (-256) | 0.122 (+0.005) | 0.878 (-0.005) | 1.02 (-0.047) | 6.64 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5912 (+0) | 8020 (-285) | 739 (+0) | 7281 (-285) | 0.092 (+0.003) | 0.908 (-0.003) | 1.36 (-0.0434) | 5.97 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9136 (+0) | 10554 (-407) | 1142 (+0) | 9412 (-407) | 0.108 (+0.004) | 0.892 (-0.004) | 1.16 (-0.0448) | 5.89 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17856 (+0) | 16466 (-865) | 2232 (+0) | 14234 (-865) | 0.136 (+0.007) | 0.864 (-0.007) | 0.922 (-0.0488) | 7.35 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10656 (+0) | 14990 (-576) | 1332 (+0) | 13658 (-576) | 0.089 (+0.003) | 0.911 (-0.003) | 1.41 (-0.0533) | 5.58 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25432 (+0) | 23521 (-1191) | 3179 (+0) | 20342 (-1191) | 0.135 (+0.006) | 0.865 (-0.006) | 0.925 (-0.0471) | 7.5 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12904 (+0) | 20246 (-875) | 1613 (+0) | 18633 (-875) | 0.080 (+0.003) | 0.920 (-0.004) | 1.57 (-0.071) | 5.65 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (+0) | 3448 (-183) | 293 (+0) | 3155 (-183) | 0.085 (+0.004) | 0.915 (-0.004) | 1.47 (-0.079) | 6.73 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8752 (+0) | 7701 (-496) | 1094 (+0) | 6607 (-496) | 0.142 (+0.009) | 0.858 (-0.009) | 0.88 (-0.0571) | 7.52 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6888 (+0) | 8664 (-249) | 861 (+0) | 7803 (-249) | 0.099 (+0.003) | 0.901 (-0.002) | 1.26 (-0.0322) | 5.64 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 (+0) | 14463 (-732) | 1760 (+0) | 12703 (-732) | 0.122 (+0.006) | 0.878 (-0.006) | 1.03 (-0.0528) | 7.06 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1592 (+0) | 10222 (-122) | 199 (+0) | 10023 (-122) | 0.019 (+0.000) | 0.981 (+0.000) | 6.42 (-0.0791) | 3.99 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23088 (+0) | 22414 (-1196) | 2886 (+0) | 19528 (-1196) | 0.129 (+0.007) | 0.871 (-0.007) | 0.971 (-0.0492) | 7.3 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1920 (+0) | 14429 (-109) | 240 (+0) | 14189 (-109) | 0.017 (+0.000) | 0.983 (+0.000) | 7.52 (-0.0549) | 4.03 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 (+0) | 31387 (-1595) | 4179 (+0) | 27208 (-1595) | 0.133 (+0.006) | 0.867 (-0.006) | 0.939 (-0.0482) | 7.66 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.075 |
| AXI write accepted-beat readiness | 1.000 |
| AXI write bus occupancy | 0.005 |
| Frame reader sample issue | 0.190 |
| Reader-to-FIFO handshake | 0.329 |
| Input FIFO-to-core handshake | 1.000 |
| Input FIFO nonempty rate | 0.567 |
| Input FIFO full rate | 0.488 |
| VVC CTU symbolizer input | 0.081 |
| VVC residual symbolizer input | 0.000 |
| VVC bin FIFO nonempty rate | 0.267 |
| VVC bin FIFO full rate | 0.016 |
| VVC bin FIFO to writer | 0.753 |
| VVC syntax frontend input | 0.973 |
| VVC bin coder input | 0.971 |
| VVC stream emitter | 0.244 |
| VVC RBSP payload handoff | 0.244 |
| VVC CABAC byte handoff | 0.244 |
| VVC bit-writer output | 0.244 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47464 (+0) | 52580 (-1933) | 5933 (+0) | 46647 (-1933) | 0.113 (+0.004) | 0.887 (-0.004) | 1.11 (-0.0422) | 6.42 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18832 (+0) | 40286 (-806) | 2354 (+0) | 37932 (-806) | 0.058 (+0.001) | 0.942 (-0.001) | 2.14 (-0.0408) | 4.92 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 6288 (+0) | 65392 (-403) | 786 (+0) | 64606 (-403) | 0.012 (+0.000) | 0.988 (+0.000) | 10.4 (-0.101) | 3.99 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33776 (+0) | 62179 (-1755) | 4222 (+0) | 57957 (-1755) | 0.068 (+0.002) | 0.932 (-0.002) | 1.84 (-0.0491) | 5.06 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49064 (+0) | 69751 (-2173) | 6133 (+0) | 63618 (-2173) | 0.088 (+0.003) | 0.912 (-0.003) | 1.42 (-0.0484) | 5.68 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27872 (+0) | 31330 (-1437) | 3484 (+0) | 27846 (-1437) | 0.111 (+0.005) | 0.889 (-0.005) | 1.12 (-0.0559) | 6.8 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1648 (+0) | 18076 (+0) | 206 (+0) | 17870 (+0) | 0.011 (+0.000) | 0.989 (+0.000) | 11 (+0) | 3.92 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2232 (+0) | 20965 (-92) | 279 (+0) | 20686 (-92) | 0.013 (+0.000) | 0.987 (+0.000) | 9.39 (-0.0371) | 4.04 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 62832 (+0) | 70664 (-3319) | 7854 (+0) | 62810 (-3319) | 0.111 (+0.005) | 0.889 (-0.005) | 1.12 (-0.0554) | 6.49 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38992 (+0) | 53640 (-1551) | 4874 (+0) | 48766 (-1551) | 0.091 (+0.003) | 0.909 (-0.003) | 1.38 (-0.0443) | 5.82 |

