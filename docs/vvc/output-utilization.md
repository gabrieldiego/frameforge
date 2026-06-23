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

## 2026-06-22 CABAC Output Overlap Checkpoint

Baseline RTL/source Git SHA:

- `cc178d3317edc9890e957175f0c5a5d6d8e06c07`

Current RTL/source Git SHA:

- `e2fd88a0ebc7d05be240f48c61b2db9efad53023`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.
- Yosys synthesis: PASS at 25 MHz metadata target; runtime exceeded the 300 second review threshold but stayed inside the 600 second hard stop.

Target status:

- Requested target: bubble rate below `0.800`.
- Current aggregate results still miss that target. The CABAC output overlap
  improves cycles without changing encoded bits, but source-symbol production
  and the serialized CABAC byte stream remain the dominant limiters.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 64 | 113168 (+0) | 269642 (-15541) | 14146 (+0) | 255496 (-15541) | 0.0525 (+0.00286) | 0.948 (-0.00246) | 2.38 (-0.137) | 3.25 |
| `racehorses-multictu-420` | 10 | 92920 (+0) | 282276 (-3090) | 11615 (+0) | 270661 (-3090) | 0.0411 (+0.000448) | 0.959 (-0.000148) | 3.04 (-0.0322) | 3.07 |
| `screenshot-sweep-444` | 64 | 377168 (+0) | 507249 (-62620) | 47146 (+0) | 460103 (-62620) | 0.0929 (+0.0102) | 0.907 (-0.00994) | 1.34 (-0.165) | 6.12 |
| `screenshot-multictu-444` | 10 | 289000 (+0) | 498332 (-44745) | 36125 (+0) | 462207 (-44745) | 0.0725 (+0.00599) | 0.928 (-0.00549) | 1.72 (-0.156) | 5.43 |

Critical internal block utilization:

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0525 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00278 |
| Frame reader sample issue | 0.237 |
| Reader-to-FIFO handshake | 0.533 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.457 |
| Input FIFO full rate | 0.255 |
| VVC CTU symbolizer input | 0.948 |
| VVC residual symbolizer input | 0.948 |
| VVC source-symbol FIFO nonempty rate | 0.43 |
| VVC source-symbol FIFO full rate | 0.117 |
| VVC bin FIFO nonempty rate | 0.389 |
| VVC bin FIFO full rate | 0.108 |
| VVC bin FIFO to writer | 0.917 |
| VVC syntax frontend input | 0.97 |
| VVC bin coder input | 0.97 |
| VVC stream emitter | 0.985 |
| VVC RBSP payload handoff | 0.949 |
| VVC CABAC byte handoff | 0.956 |
| VVC bit-writer output | 0.947 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 (+0) | 563 (-160) | 71 (+0) | 492 (-160) | 0.126 (+0.0279) | 0.874 (-0.0281) | 0.991 (-0.279) | 8.8 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 (+0) | 771 (-165) | 84 (+0) | 687 (-165) | 0.109 (+0.0192) | 0.891 (-0.0189) | 1.15 (-0.243) | 6.02 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 (+0) | 918 (-203) | 90 (+0) | 828 (-203) | 0.098 (+0.0177) | 0.902 (-0.018) | 1.27 (-0.285) | 4.78 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 (+0) | 1127 (-199) | 101 (+0) | 1026 (-199) | 0.0896 (+0.0134) | 0.91 (-0.0136) | 1.39 (-0.245) | 4.4 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 (+0) | 1291 (-258) | 109 (+0) | 1182 (-258) | 0.0844 (+0.014) | 0.916 (-0.0144) | 1.48 (-0.299) | 4.03 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 (+0) | 1525 (-260) | 120 (+0) | 1405 (-260) | 0.0787 (+0.0115) | 0.921 (-0.0117) | 1.59 (-0.271) | 3.97 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 (+0) | 1720 (-260) | 127 (+0) | 1593 (-260) | 0.0738 (+0.00974) | 0.926 (-0.00984) | 1.69 (-0.257) | 3.84 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 (+0) | 1948 (-260) | 140 (+0) | 1808 (-260) | 0.0719 (+0.00847) | 0.928 (-0.00887) | 1.74 (-0.231) | 3.8 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 (+0) | 705 (-173) | 77 (+0) | 628 (-173) | 0.109 (+0.0215) | 0.891 (-0.0212) | 1.14 (-0.286) | 5.51 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 (+0) | 1104 (-173) | 101 (+0) | 1003 (-173) | 0.0915 (+0.0124) | 0.909 (-0.0125) | 1.37 (-0.214) | 4.31 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 1431 (-215) | 114 (+0) | 1317 (-215) | 0.0797 (+0.0104) | 0.92 (-0.0107) | 1.57 (-0.231) | 3.73 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 (+0) | 1799 (-236) | 130 (+0) | 1669 (-236) | 0.0723 (+0.00836) | 0.928 (-0.00826) | 1.73 (-0.23) | 3.51 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 (+0) | 2199 (-257) | 149 (+0) | 2050 (-257) | 0.0678 (+0.00706) | 0.932 (-0.00676) | 1.84 (-0.215) | 3.44 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 (+0) | 2562 (-258) | 161 (+0) | 2401 (-258) | 0.0628 (+0.00574) | 0.937 (-0.00584) | 1.99 (-0.201) | 3.34 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 (+0) | 2997 (-242) | 180 (+0) | 2817 (-242) | 0.0601 (+0.00446) | 0.94 (-0.00406) | 2.08 (-0.169) | 3.34 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 (+0) | 3409 (-238) | 200 (+0) | 3209 (-238) | 0.0587 (+0.00387) | 0.941 (-0.00367) | 2.13 (-0.149) | 3.33 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 (+0) | 874 (-204) | 85 (+0) | 789 (-204) | 0.0973 (+0.0185) | 0.903 (-0.0183) | 1.29 (-0.305) | 4.55 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 (+0) | 1452 (-211) | 115 (+0) | 1337 (-211) | 0.0792 (+0.01) | 0.921 (-0.0102) | 1.58 (-0.232) | 3.78 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 (+0) | 1998 (-251) | 137 (+0) | 1861 (-251) | 0.0686 (+0.00767) | 0.931 (-0.00757) | 1.82 (-0.227) | 3.47 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 (+0) | 2591 (-255) | 164 (+0) | 2427 (-255) | 0.0633 (+0.0057) | 0.937 (-0.0053) | 1.97 (-0.195) | 3.37 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 (+0) | 3260 (-245) | 188 (+0) | 3072 (-245) | 0.0577 (+0.00407) | 0.942 (-0.00367) | 2.17 (-0.162) | 3.4 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 (+0) | 3768 (-259) | 209 (+0) | 3559 (-259) | 0.0555 (+0.00357) | 0.945 (-0.00347) | 2.25 (-0.156) | 3.27 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 (+0) | 4436 (-243) | 238 (+0) | 4198 (-243) | 0.0537 (+0.00275) | 0.946 (-0.00265) | 2.33 (-0.13) | 3.3 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 (+0) | 5036 (-239) | 261 (+0) | 4775 (-239) | 0.0518 (+0.00233) | 0.948 (-0.00283) | 2.41 (-0.118) | 3.28 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 (+0) | 1079 (-202) | 95 (+0) | 984 (-202) | 0.088 (+0.0138) | 0.912 (-0.014) | 1.42 (-0.27) | 4.21 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 (+0) | 1845 (-237) | 133 (+0) | 1712 (-237) | 0.0721 (+0.00819) | 0.928 (-0.00809) | 1.73 (-0.226) | 3.6 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 (+0) | 2603 (-258) | 163 (+0) | 2440 (-258) | 0.0626 (+0.00562) | 0.937 (-0.00562) | 2 (-0.194) | 3.39 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 (+0) | 3286 (-254) | 193 (+0) | 3093 (-254) | 0.0587 (+0.00423) | 0.941 (-0.00373) | 2.13 (-0.162) | 3.21 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 (+0) | 4150 (-256) | 225 (+0) | 3925 (-256) | 0.0542 (+0.00312) | 0.946 (-0.00322) | 2.31 (-0.144) | 3.24 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 (+0) | 4902 (-257) | 252 (+0) | 4650 (-257) | 0.0514 (+0.00261) | 0.949 (-0.00241) | 2.43 (-0.128) | 3.19 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 (+0) | 5780 (-243) | 286 (+0) | 5494 (-243) | 0.0495 (+0.00198) | 0.951 (-0.00248) | 2.53 (-0.104) | 3.23 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 (+0) | 6502 (-240) | 313 (+0) | 6189 (-240) | 0.0481 (+0.00174) | 0.952 (-0.00214) | 2.6 (-0.0934) | 3.17 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 (+0) | 1225 (-270) | 99 (+0) | 1126 (-270) | 0.0808 (+0.0146) | 0.919 (-0.0148) | 1.55 (-0.343) | 3.83 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 (+0) | 2194 (-258) | 144 (+0) | 2050 (-258) | 0.0656 (+0.00693) | 0.934 (-0.00663) | 1.9 (-0.225) | 3.43 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 (+0) | 3207 (-258) | 180 (+0) | 3027 (-258) | 0.0561 (+0.00423) | 0.944 (-0.00413) | 2.23 (-0.183) | 3.34 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 (+0) | 4126 (-256) | 218 (+0) | 3908 (-256) | 0.0528 (+0.00314) | 0.947 (-0.00284) | 2.37 (-0.144) | 3.22 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 (+0) | 5144 (-257) | 259 (+0) | 4885 (-257) | 0.0503 (+0.00235) | 0.95 (-0.00235) | 2.48 (-0.127) | 3.21 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 (+0) | 6096 (-257) | 295 (+0) | 5801 (-257) | 0.0484 (+0.00199) | 0.952 (-0.00239) | 2.58 (-0.107) | 3.17 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 (+0) | 7145 (-243) | 334 (+0) | 6811 (-243) | 0.0467 (+0.00155) | 0.953 (-0.00175) | 2.67 (-0.086) | 3.19 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 (+0) | 8087 (-241) | 370 (+0) | 7717 (-241) | 0.0458 (+0.00135) | 0.954 (-0.00175) | 2.73 (-0.0779) | 3.16 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 (+0) | 1403 (-277) | 106 (+0) | 1297 (-277) | 0.0756 (+0.0125) | 0.924 (-0.0126) | 1.65 (-0.326) | 3.65 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 (+0) | 2564 (-257) | 154 (+0) | 2410 (-257) | 0.0601 (+0.00546) | 0.94 (-0.00506) | 2.08 (-0.209) | 3.34 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 (+0) | 3756 (-257) | 201 (+0) | 3555 (-257) | 0.0535 (+0.00341) | 0.946 (-0.00351) | 2.34 (-0.164) | 3.26 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 (+0) | 4814 (-255) | 243 (+0) | 4571 (-255) | 0.0505 (+0.00258) | 0.95 (-0.00248) | 2.48 (-0.134) | 3.13 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 (+0) | 6006 (-257) | 284 (+0) | 5722 (-257) | 0.0473 (+0.00199) | 0.953 (-0.00229) | 2.64 (-0.117) | 3.13 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 (+0) | 7222 (-257) | 331 (+0) | 6891 (-257) | 0.0458 (+0.00153) | 0.954 (-0.00183) | 2.73 (-0.0927) | 3.13 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 (+0) | 8418 (-243) | 375 (+0) | 8043 (-243) | 0.0445 (+0.00125) | 0.955 (-0.00155) | 2.81 (-0.084) | 3.13 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 (+0) | 9420 (-243) | 414 (+0) | 9006 (-243) | 0.0439 (+0.00115) | 0.956 (-0.000949) | 2.84 (-0.0758) | 3.07 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 (+0) | 1703 (-256) | 121 (+0) | 1582 (-256) | 0.0711 (+0.00925) | 0.929 (-0.00905) | 1.76 (-0.261) | 3.8 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 (+0) | 3035 (-257) | 180 (+0) | 2855 (-257) | 0.0593 (+0.00461) | 0.941 (-0.00431) | 2.11 (-0.182) | 3.39 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 (+0) | 4371 (-258) | 227 (+0) | 4144 (-258) | 0.0519 (+0.00293) | 0.948 (-0.00293) | 2.41 (-0.143) | 3.25 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 (+0) | 5694 (-243) | 281 (+0) | 5413 (-243) | 0.0494 (+0.00205) | 0.951 (-0.00235) | 2.53 (-0.107) | 3.18 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 (+0) | 7080 (-255) | 329 (+0) | 6751 (-255) | 0.0465 (+0.00157) | 0.954 (-0.00147) | 2.69 (-0.1) | 3.16 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 (+0) | 8399 (-256) | 378 (+0) | 8021 (-256) | 0.045 (+0.00131) | 0.955 (-0.00101) | 2.78 (-0.0826) | 3.12 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 (+0) | 9830 (-258) | 425 (+0) | 9405 (-258) | 0.0432 (+0.00113) | 0.957 (-0.00123) | 2.89 (-0.0788) | 3.13 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 (+0) | 11111 (-255) | 474 (+0) | 10637 (-255) | 0.0427 (+0.00096) | 0.957 (-0.00066) | 2.93 (-0.0699) | 3.1 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 (+0) | 1898 (-249) | 131 (+0) | 1767 (-249) | 0.069 (+0.00802) | 0.931 (-0.00802) | 1.81 (-0.239) | 3.71 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 (+0) | 3433 (-252) | 198 (+0) | 3235 (-252) | 0.0577 (+0.00398) | 0.942 (-0.00368) | 2.17 (-0.163) | 3.35 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 (+0) | 4981 (-258) | 253 (+0) | 4728 (-258) | 0.0508 (+0.00249) | 0.949 (-0.00279) | 2.46 (-0.129) | 3.24 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 (+0) | 6448 (-242) | 316 (+0) | 6132 (-242) | 0.049 (+0.00181) | 0.951 (-0.00201) | 2.55 (-0.0994) | 3.15 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 (+0) | 7963 (-240) | 364 (+0) | 7599 (-240) | 0.0457 (+0.00131) | 0.954 (-0.00171) | 2.73 (-0.0855) | 3.11 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 (+0) | 9485 (-258) | 426 (+0) | 9059 (-258) | 0.0449 (+0.00121) | 0.955 (-0.000913) | 2.78 (-0.0768) | 3.09 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 (+0) | 11135 (-256) | 485 (+0) | 10650 (-256) | 0.0436 (+0.000956) | 0.956 (-0.000556) | 2.87 (-0.0702) | 3.11 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 (+0) | 12618 (-251) | 540 (+0) | 12078 (-251) | 0.0428 (+0.000796) | 0.957 (-0.000796) | 2.92 (-0.0592) | 3.08 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0411 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00248 |
| Frame reader sample issue | 0.232 |
| Reader-to-FIFO handshake | 0.486 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.486 |
| Input FIFO full rate | 0.323 |
| VVC CTU symbolizer input | 0.983 |
| VVC residual symbolizer input | 0.984 |
| VVC source-symbol FIFO nonempty rate | 0.391 |
| VVC source-symbol FIFO full rate | 0.0272 |
| VVC bin FIFO nonempty rate | 0.405 |
| VVC bin FIFO full rate | 0.0389 |
| VVC bin FIFO to writer | 0.925 |
| VVC syntax frontend input | 0.99 |
| VVC bin coder input | 0.99 |
| VVC stream emitter | 0.997 |
| VVC RBSP payload handoff | 0.996 |
| VVC CABAC byte handoff | 1 |
| VVC bit-writer output | 0.996 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 (+0) | 25376 (-344) | 1060 (+0) | 24316 (-344) | 0.0418 (+0.000572) | 0.958 (-0.000772) | 2.99 (-0.0375) | 3.1 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 (+0) | 25100 (-276) | 1027 (+0) | 24073 (-276) | 0.0409 (+0.000416) | 0.959 (-0.000916) | 3.06 (-0.035) | 3.06 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 (+0) | 49242 (-299) | 1948 (+0) | 47294 (-299) | 0.0396 (+0.00026) | 0.96 (-0.00056) | 3.16 (-0.0202) | 3.01 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 (+0) | 37865 (-466) | 1583 (+0) | 36282 (-466) | 0.0418 (+0.000506) | 0.958 (-0.000806) | 2.99 (-0.04) | 3.08 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 (+0) | 36394 (-318) | 1405 (+0) | 34989 (-318) | 0.0386 (+0.000305) | 0.961 (-0.000605) | 3.24 (-0.0321) | 2.96 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 (+0) | 14512 (-249) | 632 (+0) | 13880 (-249) | 0.0436 (+0.00075) | 0.956 (-0.00055) | 2.87 (-0.0497) | 3.15 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 (+0) | 14641 (-272) | 633 (+0) | 14008 (-272) | 0.0432 (+0.000835) | 0.957 (-0.00123) | 2.89 (-0.0488) | 3.18 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 (+0) | 16843 (-282) | 739 (+0) | 16104 (-282) | 0.0439 (+0.000676) | 0.956 (-0.000876) | 2.85 (-0.051) | 3.25 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 (+0) | 33724 (-307) | 1408 (+0) | 32316 (-307) | 0.0418 (+0.000351) | 0.958 (-0.000751) | 2.99 (-0.026) | 3.1 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 (+0) | 28579 (-277) | 1180 (+0) | 27399 (-277) | 0.0413 (+0.000389) | 0.959 (-0.000289) | 3.03 (-0.0326) | 3.1 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0929 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00559 |
| Frame reader sample issue | 0.193 |
| Reader-to-FIFO handshake | 0.344 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.489 |
| Input FIFO full rate | 0.389 |
| VVC CTU symbolizer input | 0.021 |
| VVC residual symbolizer input | 0 |
| VVC source-symbol FIFO nonempty rate | 0.428 |
| VVC source-symbol FIFO full rate | 0.364 |
| VVC bin FIFO nonempty rate | 0.313 |
| VVC bin FIFO full rate | 0.0213 |
| VVC bin FIFO to writer | 0.724 |
| VVC syntax frontend input | 0.965 |
| VVC bin coder input | 0.963 |
| VVC stream emitter | 0.967 |
| VVC RBSP payload handoff | 0.964 |
| VVC CABAC byte handoff | 0.965 |
| VVC bit-writer output | 0.963 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (+0) | 690 (-200) | 67 (+0) | 623 (-200) | 0.0971 (+0.0218) | 0.903 (-0.0221) | 1.29 (-0.373) | 10.8 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (+0) | 1330 (-228) | 122 (+0) | 1208 (-228) | 0.0917 (+0.0134) | 0.908 (-0.0137) | 1.36 (-0.237) | 10.4 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 (+0) | 1121 (-213) | 72 (+0) | 1049 (-213) | 0.0642 (+0.0102) | 0.936 (-0.0102) | 1.95 (-0.374) | 5.84 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 648 (+0) | 1514 (-237) | 81 (+0) | 1433 (-237) | 0.0535 (+0.0072) | 0.946 (-0.0075) | 2.34 (-0.364) | 5.91 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 624 (+0) | 1572 (-220) | 78 (+0) | 1494 (-220) | 0.0496 (+0.00612) | 0.95 (-0.00562) | 2.52 (-0.351) | 4.91 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 640 (+0) | 1785 (-223) | 80 (+0) | 1705 (-223) | 0.0448 (+0.00502) | 0.955 (-0.00482) | 2.79 (-0.351) | 4.65 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (+0) | 3929 (-892) | 586 (+0) | 3343 (-892) | 0.149 (+0.0271) | 0.851 (-0.0271) | 0.838 (-0.192) | 8.77 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (+0) | 4269 (-693) | 543 (+0) | 3726 (-693) | 0.127 (+0.0182) | 0.873 (-0.0182) | 0.983 (-0.157) | 8.34 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (+0) | 1350 (-250) | 139 (+0) | 1211 (-250) | 0.103 (+0.0161) | 0.897 (-0.016) | 1.21 (-0.226) | 10.5 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (+0) | 2130 (-550) | 280 (+0) | 1850 (-550) | 0.131 (+0.0275) | 0.869 (-0.0275) | 0.951 (-0.249) | 8.32 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 (+0) | 1766 (-220) | 80 (+0) | 1686 (-220) | 0.0453 (+0.005) | 0.955 (-0.0053) | 2.76 (-0.341) | 4.6 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 672 (+0) | 2194 (-228) | 84 (+0) | 2110 (-228) | 0.0383 (+0.00359) | 0.962 (-0.00329) | 3.26 (-0.335) | 4.29 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (+0) | 5448 (-1147) | 766 (+0) | 4682 (-1147) | 0.141 (+0.0246) | 0.859 (-0.0246) | 0.889 (-0.191) | 8.51 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 728 (+0) | 3085 (-237) | 91 (+0) | 2994 (-237) | 0.0295 (+0.0021) | 0.971 (-0.0025) | 4.24 (-0.322) | 4.02 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6192 (+0) | 6662 (-1135) | 774 (+0) | 5888 (-1135) | 0.116 (+0.0169) | 0.884 (-0.0172) | 1.08 (-0.184) | 7.44 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 792 (+0) | 3981 (-246) | 99 (+0) | 3882 (-246) | 0.0249 (+0.00147) | 0.975 (-0.00187) | 5.03 (-0.313) | 3.89 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (+0) | 1799 (-607) | 288 (+0) | 1511 (-607) | 0.16 (+0.0401) | 0.84 (-0.0401) | 0.781 (-0.259) | 9.37 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 (+0) | 2430 (-380) | 176 (+0) | 2254 (-380) | 0.0724 (+0.00983) | 0.928 (-0.00943) | 1.73 (-0.274) | 6.33 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2832 (+0) | 3692 (-725) | 354 (+0) | 3338 (-725) | 0.0959 (+0.0158) | 0.904 (-0.0159) | 1.3 (-0.256) | 6.41 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (+0) | 6468 (-1433) | 973 (+0) | 5495 (-1433) | 0.15 (+0.0274) | 0.85 (-0.0274) | 0.831 (-0.189) | 8.42 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6072 (+0) | 7307 (-975) | 759 (+0) | 6548 (-975) | 0.104 (+0.0123) | 0.896 (-0.0119) | 1.2 (-0.157) | 7.61 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 808 (+0) | 4452 (-249) | 101 (+0) | 4351 (-249) | 0.0227 (+0.00119) | 0.977 (-0.00169) | 5.51 (-0.31) | 3.86 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 848 (+0) | 5157 (-256) | 106 (+0) | 5051 (-256) | 0.0206 (+0.000955) | 0.979 (-0.000555) | 6.08 (-0.299) | 3.84 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11336 (+0) | 11554 (-1701) | 1417 (+0) | 10137 (-1701) | 0.123 (+0.0156) | 0.877 (-0.0156) | 1.02 (-0.151) | 7.52 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 (+0) | 1822 (-507) | 188 (+0) | 1634 (-507) | 0.103 (+0.0225) | 0.897 (-0.0222) | 1.21 (-0.339) | 7.12 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 (+0) | 2840 (-346) | 149 (+0) | 2691 (-346) | 0.0525 (+0.00566) | 0.948 (-0.00546) | 2.38 (-0.287) | 5.55 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 (+0) | 3529 (-263) | 131 (+0) | 3398 (-263) | 0.0371 (+0.00262) | 0.963 (-0.00212) | 3.37 (-0.253) | 4.6 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4376 (+0) | 6637 (-513) | 547 (+0) | 6090 (-513) | 0.0824 (+0.00592) | 0.918 (-0.00542) | 1.52 (-0.113) | 6.48 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 848 (+0) | 4906 (-255) | 106 (+0) | 4800 (-255) | 0.0216 (+0.00111) | 0.978 (-0.000606) | 5.79 (-0.305) | 3.83 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 (+0) | 12311 (-1921) | 1604 (+0) | 10707 (-1921) | 0.13 (+0.0173) | 0.87 (-0.0173) | 0.959 (-0.151) | 8.01 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 11960 (+0) | 12621 (-2020) | 1495 (+0) | 11126 (-2020) | 0.118 (+0.0165) | 0.882 (-0.0165) | 1.06 (-0.165) | 7.04 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 984 (+0) | 7719 (-276) | 123 (+0) | 7596 (-276) | 0.0159 (+0.000535) | 0.984 (-0.000935) | 7.84 (-0.275) | 3.77 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (+0) | 3107 (-484) | 385 (+0) | 2722 (-484) | 0.124 (+0.0169) | 0.876 (-0.0169) | 1.01 (-0.161) | 9.71 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (+0) | 5360 (-954) | 737 (+0) | 4623 (-954) | 0.138 (+0.0205) | 0.863 (-0.0205) | 0.909 (-0.161) | 8.38 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1152 (+0) | 4406 (-430) | 144 (+0) | 4262 (-430) | 0.0327 (+0.00288) | 0.967 (-0.00268) | 3.82 (-0.375) | 4.59 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (+0) | 10335 (-1324) | 1263 (+0) | 9072 (-1324) | 0.122 (+0.0142) | 0.878 (-0.0142) | 1.02 (-0.127) | 8.07 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 9488 (+0) | 10787 (-1252) | 1186 (+0) | 9601 (-1252) | 0.11 (+0.0114) | 0.89 (-0.0109) | 1.14 (-0.133) | 6.74 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1432 (+0) | 7904 (-285) | 179 (+0) | 7725 (-285) | 0.0226 (+0.000747) | 0.977 (-0.000647) | 5.52 (-0.2) | 4.12 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10336 (+0) | 13975 (-1451) | 1292 (+0) | 12683 (-1451) | 0.0925 (+0.00865) | 0.908 (-0.00845) | 1.35 (-0.138) | 6.24 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1160 (+0) | 9904 (-349) | 145 (+0) | 9759 (-349) | 0.0146 (+0.000541) | 0.985 (-0.000641) | 8.54 (-0.302) | 3.87 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 (+0) | 1963 (-367) | 90 (+0) | 1873 (-367) | 0.0458 (+0.00725) | 0.954 (-0.00685) | 2.73 (-0.514) | 5.11 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (+0) | 7302 (-1779) | 1224 (+0) | 6078 (-1779) | 0.168 (+0.0326) | 0.832 (-0.0326) | 0.746 (-0.181) | 9.51 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 (+0) | 7970 (-1241) | 901 (+0) | 7069 (-1241) | 0.113 (+0.0152) | 0.887 (-0.015) | 1.11 (-0.174) | 6.92 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7424 (+0) | 10037 (-948) | 928 (+0) | 9109 (-948) | 0.0925 (+0.00796) | 0.908 (-0.00846) | 1.35 (-0.128) | 6.53 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14736 (+0) | 14585 (-2120) | 1842 (+0) | 12743 (-2120) | 0.126 (+0.0163) | 0.874 (-0.0163) | 0.99 (-0.14) | 7.6 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1048 (+0) | 8738 (-292) | 131 (+0) | 8607 (-292) | 0.015 (+0.000492) | 0.985 (+8.01e-06) | 8.34 (-0.282) | 3.79 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9240 (+0) | 15687 (-1343) | 1155 (+0) | 14532 (-1343) | 0.0736 (+0.00583) | 0.926 (-0.00563) | 1.7 (-0.142) | 5.84 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 11905 (-438) | 155 (+0) | 11750 (-438) | 0.013 (+0.00042) | 0.987 (-1.97e-05) | 9.6 (-0.349) | 3.88 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (+0) | 3602 (-768) | 454 (+0) | 3148 (-768) | 0.126 (+0.022) | 0.874 (-0.022) | 0.992 (-0.208) | 8.04 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 (+0) | 6206 (-1093) | 727 (+0) | 5479 (-1093) | 0.117 (+0.0175) | 0.883 (-0.0171) | 1.07 (-0.183) | 6.93 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5912 (+0) | 8305 (-848) | 739 (+0) | 7566 (-848) | 0.089 (+0.00828) | 0.911 (-0.00798) | 1.4 (-0.145) | 6.18 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9136 (+0) | 10961 (-1543) | 1142 (+0) | 9819 (-1543) | 0.104 (+0.0129) | 0.896 (-0.0132) | 1.2 (-0.17) | 6.12 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17856 (+0) | 17331 (-2823) | 2232 (+0) | 15099 (-2823) | 0.129 (+0.0178) | 0.871 (-0.0178) | 0.971 (-0.159) | 7.74 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10656 (+0) | 15566 (-1689) | 1332 (+0) | 14234 (-1689) | 0.0856 (+0.00837) | 0.914 (-0.00857) | 1.46 (-0.159) | 5.79 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25432 (+0) | 24712 (-4000) | 3179 (+0) | 21533 (-4000) | 0.129 (+0.0176) | 0.871 (-0.0176) | 0.972 (-0.158) | 7.88 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12904 (+0) | 21121 (-1827) | 1613 (+0) | 19508 (-1827) | 0.0764 (+0.00607) | 0.924 (-0.00637) | 1.64 (-0.143) | 5.89 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (+0) | 3631 (-365) | 293 (+0) | 3338 (-365) | 0.0807 (+0.00739) | 0.919 (-0.00769) | 1.55 (-0.151) | 7.09 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8752 (+0) | 8197 (-1321) | 1094 (+0) | 7103 (-1321) | 0.133 (+0.0185) | 0.867 (-0.0185) | 0.937 (-0.153) | 8 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6888 (+0) | 8913 (-1094) | 861 (+0) | 8052 (-1094) | 0.0966 (+0.0106) | 0.903 (-0.0106) | 1.29 (-0.156) | 5.8 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 (+0) | 15195 (-1863) | 1760 (+0) | 13435 (-1863) | 0.116 (+0.0128) | 0.884 (-0.0128) | 1.08 (-0.131) | 7.42 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1592 (+0) | 10344 (-303) | 199 (+0) | 10145 (-303) | 0.0192 (+0.000538) | 0.981 (-0.000238) | 6.5 (-0.193) | 4.04 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23088 (+0) | 23610 (-3155) | 2886 (+0) | 20724 (-3155) | 0.122 (+0.0142) | 0.878 (-0.0142) | 1.02 (-0.137) | 7.69 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1920 (+0) | 14538 (-315) | 240 (+0) | 14298 (-315) | 0.0165 (+0.000308) | 0.983 (-0.000508) | 7.57 (-0.168) | 4.06 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 (+0) | 32982 (-5210) | 4179 (+0) | 28803 (-5210) | 0.127 (+0.0177) | 0.873 (-0.0177) | 0.987 (-0.153) | 8.05 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0725 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00449 |
| Frame reader sample issue | 0.19 |
| Reader-to-FIFO handshake | 0.324 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.552 |
| Input FIFO full rate | 0.475 |
| VVC CTU symbolizer input | 0.0267 |
| VVC residual symbolizer input | 0 |
| VVC source-symbol FIFO nonempty rate | 0.328 |
| VVC source-symbol FIFO full rate | 0.285 |
| VVC bin FIFO nonempty rate | 0.26 |
| VVC bin FIFO full rate | 0.018 |
| VVC bin FIFO to writer | 0.731 |
| VVC syntax frontend input | 0.963 |
| VVC bin coder input | 0.961 |
| VVC stream emitter | 0.182 |
| VVC RBSP payload handoff | 0.182 |
| VVC CABAC byte handoff | 0.182 |
| VVC bit-writer output | 0.182 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47464 (+0) | 54513 (-7750) | 5933 (+0) | 48580 (-7750) | 0.109 (+0.0135) | 0.891 (-0.0138) | 1.15 (-0.161) | 6.65 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18832 (+0) | 41092 (-2605) | 2354 (+0) | 38738 (-2605) | 0.0573 (+0.00339) | 0.943 (-0.00329) | 2.18 (-0.138) | 5.02 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 6288 (+0) | 65795 (-1029) | 786 (+0) | 65009 (-1029) | 0.0119 (+0.000146) | 0.988 (+5.38e-05) | 10.5 (-0.136) | 4.02 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33776 (+0) | 63934 (-5324) | 4222 (+0) | 59712 (-5324) | 0.066 (+0.00504) | 0.934 (-0.00504) | 1.89 (-0.157) | 5.2 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49064 (+0) | 71924 (-7106) | 6133 (+0) | 65791 (-7106) | 0.0853 (+0.00767) | 0.915 (-0.00727) | 1.47 (-0.144) | 5.85 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27872 (+0) | 32767 (-3957) | 3484 (+0) | 29283 (-3957) | 0.106 (+0.0114) | 0.894 (-0.0113) | 1.18 (-0.144) | 7.11 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1648 (+0) | 18076 (-447) | 206 (+0) | 17870 (-447) | 0.0114 (+0.000296) | 0.989 (-0.000396) | 11 (-0.232) | 3.92 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2232 (+0) | 21057 (-714) | 279 (+0) | 20778 (-714) | 0.0132 (+0.00045) | 0.987 (-0.00025) | 9.43 (-0.316) | 4.06 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 62832 (+0) | 73983 (-9503) | 7854 (+0) | 66129 (-9503) | 0.106 (+0.0121) | 0.894 (-0.0122) | 1.18 (-0.153) | 6.8 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38992 (+0) | 55191 (-6310) | 4874 (+0) | 50317 (-6310) | 0.0883 (+0.00901) | 0.912 (-0.00931) | 1.42 (-0.165) | 5.99 |
