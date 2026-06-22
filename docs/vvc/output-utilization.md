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

## 2026-06-22 Shared AXI/FIFO Utilization Pass

Validated RTL/source Git SHA:

- `3945b1bc67a20e5cfa2ccf8d05910ab8741deef0`

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.

Target status:

- Requested target: bubble rate below `0.800`.
- Current aggregate results still miss that target. The internal counters show
  the AXI write side accepts every offered beat; the remaining bubbles are
  dominated by codec work and serialized byte-output/carry/CABAC phases rather
  than downstream AXI backpressure.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `racehorses-sweep-420` | 64 | 113168 (+0) | 464234 (-153360) | 14146 (+0) | 450088 (-153360) | 0.0305 (+0.00757) | 0.97 (-0.00757) | 4.1 (-1.36) |
| `racehorses-multictu-420` | 10 | 92920 (+0) | 483400 (-168690) | 11615 (+0) | 471785 (-168690) | 0.024 (+0.00622) | 0.976 (-0.00622) | 5.2 (-1.82) |
| `screenshot-sweep-444` | 64 | 377168 (n/a) | 820571 (n/a) | 47146 (n/a) | 773425 (n/a) | 0.0575 (n/a) | 0.943 (n/a) | 2.18 (n/a) |
| `screenshot-multictu-444` | 10 | 289000 (n/a) | 764774 (n/a) | 36125 (n/a) | 728649 (n/a) | 0.0472 (n/a) | 0.953 (n/a) | 2.65 (n/a) |

Critical internal block utilization:

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0305 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00161 |
| Frame reader sample issue | 0.593 |
| Reader-to-FIFO handshake | 0.816 |
| Input FIFO-to-core handshake | 0.558 |
| Input FIFO nonempty rate | 0.481 |
| Input FIFO full rate | 0.114 |
| VVC CTU symbolizer input | 0.527 |
| VVC residual symbolizer input | 0.538 |
| VVC syntax frontend input | 0.985 |
| VVC bin coder input | 0.905 |
| VVC stream emitter | 0.982 |
| VVC RBSP payload handoff | 0.993 |
| VVC CABAC byte handoff | 1 |
| VVC bit-writer output | 1 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 (+0) | 835 (-123) | 71 (+0) | 764 (-123) | 0.085 (+0.0109) | 0.915 (-0.011) | 1.47 (-0.22) | 13 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 (+0) | 1214 (-201) | 84 (+0) | 1130 (-201) | 0.0692 (+0.00979) | 0.931 (-0.0102) | 1.81 (-0.303) | 9.48 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 (+0) | 1521 (-328) | 90 (+0) | 1431 (-328) | 0.0592 (+0.0105) | 0.941 (-0.0102) | 2.11 (-0.458) | 7.92 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 (+0) | 1871 (-410) | 101 (+0) | 1770 (-410) | 0.054 (+0.00968) | 0.946 (-0.00998) | 2.32 (-0.504) | 7.31 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 (+0) | 2247 (-546) | 109 (+0) | 2138 (-546) | 0.0485 (+0.00951) | 0.951 (-0.00951) | 2.58 (-0.623) | 7.02 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 (+0) | 2631 (-640) | 120 (+0) | 2511 (-640) | 0.0456 (+0.00891) | 0.954 (-0.00861) | 2.74 (-0.669) | 6.85 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 (+0) | 2968 (-767) | 127 (+0) | 2841 (-767) | 0.0428 (+0.00879) | 0.957 (-0.00879) | 2.92 (-0.759) | 6.62 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 (+0) | 3376 (-849) | 140 (+0) | 3236 (-849) | 0.0415 (+0.00837) | 0.959 (-0.00847) | 3.01 (-0.756) | 6.59 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 (+0) | 1100 (-259) | 77 (+0) | 1023 (-259) | 0.07 (+0.0133) | 0.93 (-0.013) | 1.79 (-0.424) | 8.59 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 (+0) | 1813 (-431) | 101 (+0) | 1712 (-431) | 0.0557 (+0.0107) | 0.944 (-0.0107) | 2.24 (-0.536) | 7.08 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 2450 (-739) | 114 (+0) | 2336 (-739) | 0.0465 (+0.0108) | 0.953 (-0.0105) | 2.69 (-0.814) | 6.38 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 (+0) | 3101 (-891) | 130 (+0) | 2971 (-891) | 0.0419 (+0.00932) | 0.958 (-0.00892) | 2.98 (-0.858) | 6.06 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 (+0) | 3834 (-1235) | 149 (+0) | 3685 (-1235) | 0.0389 (+0.00946) | 0.961 (-0.00986) | 3.22 (-1.03) | 5.99 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 (+0) | 4435 (-1351) | 161 (+0) | 4274 (-1351) | 0.0363 (+0.0085) | 0.964 (-0.0083) | 3.44 (-1.05) | 5.77 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 (+0) | 5179 (-1731) | 180 (+0) | 4999 (-1731) | 0.0348 (+0.00876) | 0.965 (-0.00876) | 3.6 (-1.2) | 5.78 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 (+0) | 5890 (-1811) | 200 (+0) | 5690 (-1811) | 0.034 (+0.00796) | 0.966 (-0.00796) | 3.68 (-1.13) | 5.75 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 (+0) | 1437 (-395) | 85 (+0) | 1352 (-395) | 0.0592 (+0.0128) | 0.941 (-0.0132) | 2.11 (-0.577) | 7.48 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 (+0) | 2472 (-661) | 115 (+0) | 2357 (-661) | 0.0465 (+0.00982) | 0.953 (-0.00952) | 2.69 (-0.723) | 6.44 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 (+0) | 3475 (-1096) | 137 (+0) | 3338 (-1096) | 0.0394 (+0.00942) | 0.961 (-0.00942) | 3.17 (-0.999) | 6.03 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 (+0) | 4473 (-1330) | 164 (+0) | 4309 (-1330) | 0.0367 (+0.00836) | 0.963 (-0.00866) | 3.41 (-1.01) | 5.82 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 (+0) | 5633 (-1840) | 188 (+0) | 5445 (-1840) | 0.0334 (+0.00817) | 0.967 (-0.00837) | 3.75 (-1.22) | 5.87 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 (+0) | 6523 (-2032) | 209 (+0) | 6314 (-2032) | 0.032 (+0.00764) | 0.968 (-0.00804) | 3.9 (-1.22) | 5.66 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 (+0) | 7641 (-2557) | 238 (+0) | 7403 (-2557) | 0.0311 (+0.00785) | 0.969 (-0.00815) | 4.01 (-1.35) | 5.69 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 (+0) | 8701 (-2689) | 261 (+0) | 8440 (-2689) | 0.03 (+0.0071) | 0.97 (-0.007) | 4.17 (-1.28) | 5.66 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 (+0) | 1797 (-531) | 95 (+0) | 1702 (-531) | 0.0529 (+0.0121) | 0.947 (-0.0119) | 2.36 (-0.696) | 7.02 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 (+0) | 3188 (-891) | 133 (+0) | 3055 (-891) | 0.0417 (+0.00912) | 0.958 (-0.00872) | 3 (-0.834) | 6.23 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 (+0) | 4514 (-1507) | 163 (+0) | 4351 (-1507) | 0.0361 (+0.00901) | 0.964 (-0.00911) | 3.46 (-1.16) | 5.88 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 (+0) | 5717 (-1811) | 193 (+0) | 5524 (-1811) | 0.0338 (+0.00816) | 0.966 (-0.00776) | 3.7 (-1.18) | 5.58 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 (+0) | 7196 (-2499) | 225 (+0) | 6971 (-2499) | 0.0313 (+0.00807) | 0.969 (-0.00827) | 4 (-1.39) | 5.62 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 (+0) | 8480 (-2731) | 252 (+0) | 8228 (-2731) | 0.0297 (+0.00722) | 0.97 (-0.00772) | 4.21 (-1.35) | 5.52 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 (+0) | 9960 (-3491) | 286 (+0) | 9674 (-3491) | 0.0287 (+0.00741) | 0.971 (-0.00771) | 4.35 (-1.53) | 5.56 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 (+0) | 11273 (-3651) | 313 (+0) | 10960 (-3651) | 0.0278 (+0.00677) | 0.972 (-0.00677) | 4.5 (-1.46) | 5.5 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 (+0) | 2101 (-667) | 99 (+0) | 2002 (-667) | 0.0471 (+0.0113) | 0.953 (-0.0111) | 2.65 (-0.837) | 6.57 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 (+0) | 3781 (-1121) | 144 (+0) | 3637 (-1121) | 0.0381 (+0.00869) | 0.962 (-0.00909) | 3.28 (-0.978) | 5.91 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 (+0) | 5491 (-1864) | 180 (+0) | 5311 (-1864) | 0.0328 (+0.00828) | 0.967 (-0.00878) | 3.81 (-1.3) | 5.72 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 (+0) | 7116 (-2250) | 218 (+0) | 6898 (-2250) | 0.0306 (+0.00734) | 0.969 (-0.00764) | 4.08 (-1.29) | 5.56 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 (+0) | 8822 (-3074) | 259 (+0) | 8563 (-3074) | 0.0294 (+0.00756) | 0.971 (-0.00736) | 4.26 (-1.48) | 5.51 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 (+0) | 10467 (-3400) | 295 (+0) | 10172 (-3400) | 0.0282 (+0.00688) | 0.972 (-0.00718) | 4.44 (-1.44) | 5.45 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 (+0) | 12262 (-4287) | 334 (+0) | 11928 (-4287) | 0.0272 (+0.00704) | 0.973 (-0.00724) | 4.59 (-1.6) | 5.47 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 (+0) | 13961 (-4529) | 370 (+0) | 13591 (-4529) | 0.0265 (+0.0065) | 0.973 (-0.0065) | 4.72 (-1.53) | 5.45 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 (+0) | 2420 (-803) | 106 (+0) | 2314 (-803) | 0.0438 (+0.0109) | 0.956 (-0.0108) | 2.85 (-0.946) | 6.3 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 (+0) | 4453 (-1351) | 154 (+0) | 4299 (-1351) | 0.0346 (+0.00808) | 0.965 (-0.00758) | 3.61 (-1.1) | 5.8 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 (+0) | 6453 (-2275) | 201 (+0) | 6252 (-2275) | 0.0311 (+0.00815) | 0.969 (-0.00815) | 4.01 (-1.42) | 5.6 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 (+0) | 8351 (-2731) | 243 (+0) | 8108 (-2731) | 0.0291 (+0.0072) | 0.971 (-0.0071) | 4.3 (-1.4) | 5.44 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 (+0) | 10326 (-3763) | 284 (+0) | 10042 (-3763) | 0.0275 (+0.0073) | 0.972 (-0.0075) | 4.54 (-1.66) | 5.38 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 (+0) | 12413 (-4111) | 331 (+0) | 12082 (-4111) | 0.0267 (+0.00667) | 0.973 (-0.00667) | 4.69 (-1.55) | 5.39 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 (+0) | 14469 (-5251) | 375 (+0) | 14094 (-5251) | 0.0259 (+0.00692) | 0.974 (-0.00692) | 4.82 (-1.75) | 5.38 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 (+0) | 16232 (-5491) | 414 (+0) | 15818 (-5491) | 0.0255 (+0.00641) | 0.974 (-0.00651) | 4.9 (-1.66) | 5.28 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 (+0) | 2900 (-939) | 121 (+0) | 2779 (-939) | 0.0417 (+0.0102) | 0.958 (-0.00972) | 3 (-0.974) | 6.47 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 (+0) | 5245 (-1581) | 180 (+0) | 5065 (-1581) | 0.0343 (+0.00792) | 0.966 (-0.00832) | 3.64 (-1.1) | 5.85 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 (+0) | 7507 (-2632) | 227 (+0) | 7280 (-2632) | 0.0302 (+0.00784) | 0.97 (-0.00824) | 4.13 (-1.45) | 5.59 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 (+0) | 9837 (-3170) | 281 (+0) | 9556 (-3170) | 0.0286 (+0.00697) | 0.971 (-0.00657) | 4.38 (-1.41) | 5.49 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 (+0) | 12180 (-4368) | 329 (+0) | 11851 (-4368) | 0.027 (+0.00711) | 0.973 (-0.00701) | 4.63 (-1.66) | 5.44 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 (+0) | 14466 (-4792) | 378 (+0) | 14088 (-4792) | 0.0261 (+0.00653) | 0.974 (-0.00613) | 4.78 (-1.59) | 5.38 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 (+0) | 16891 (-6077) | 425 (+0) | 16466 (-6077) | 0.0252 (+0.00666) | 0.975 (-0.00616) | 4.97 (-1.79) | 5.39 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 (+0) | 19193 (-6369) | 474 (+0) | 18719 (-6369) | 0.0247 (+0.0062) | 0.975 (-0.0057) | 5.06 (-1.68) | 5.36 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 (+0) | 3233 (-1075) | 131 (+0) | 3102 (-1075) | 0.0405 (+0.0101) | 0.959 (-0.0105) | 3.08 (-1.03) | 6.31 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 (+0) | 5906 (-1811) | 198 (+0) | 5708 (-1811) | 0.0335 (+0.00783) | 0.966 (-0.00753) | 3.73 (-1.14) | 5.77 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 (+0) | 8534 (-3043) | 253 (+0) | 8281 (-3043) | 0.0296 (+0.00775) | 0.97 (-0.00765) | 4.22 (-1.5) | 5.56 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 (+0) | 11165 (-3651) | 316 (+0) | 10849 (-3651) | 0.0283 (+0.007) | 0.972 (-0.0073) | 4.42 (-1.44) | 5.45 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 (+0) | 13711 (-5027) | 364 (+0) | 13347 (-5027) | 0.0265 (+0.00715) | 0.973 (-0.00755) | 4.71 (-1.72) | 5.36 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 (+0) | 16338 (-5491) | 426 (+0) | 15912 (-5491) | 0.0261 (+0.00657) | 0.974 (-0.00607) | 4.79 (-1.62) | 5.32 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 (+0) | 19212 (-7011) | 485 (+0) | 18727 (-7011) | 0.0252 (+0.00674) | 0.975 (-0.00724) | 4.95 (-1.81) | 5.36 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 (+0) | 21853 (-7331) | 540 (+0) | 21313 (-7331) | 0.0247 (+0.00621) | 0.975 (-0.00571) | 5.06 (-1.7) | 5.34 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.024 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00145 |
| Frame reader sample issue | 0.566 |
| Reader-to-FIFO handshake | 0.763 |
| Input FIFO-to-core handshake | 0.554 |
| Input FIFO nonempty rate | 0.514 |
| Input FIFO full rate | 0.15 |
| VVC CTU symbolizer input | 0.525 |
| VVC residual symbolizer input | 0.537 |
| VVC syntax frontend input | 0.982 |
| VVC bin coder input | 0.903 |
| VVC stream emitter | 0.99 |
| VVC RBSP payload handoff | 0.997 |
| VVC CABAC byte handoff | 1 |
| VVC bit-writer output | 1 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 (+0) | 24855 (-8966) | 632 (+0) | 24223 (-8966) | 0.0254 (+0.00673) | 0.975 (-0.00643) | 4.92 (-1.77) | 5.39 |
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 (+0) | 43723 (-14662) | 1060 (+0) | 42663 (-14662) | 0.0242 (+0.00604) | 0.976 (-0.00624) | 5.16 (-1.73) | 5.34 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 (+0) | 65085 (-21993) | 1583 (+0) | 63502 (-21993) | 0.0243 (+0.00612) | 0.976 (-0.00632) | 5.14 (-1.74) | 5.3 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 (+0) | 25091 (-8180) | 633 (+0) | 24458 (-8180) | 0.0252 (+0.00623) | 0.975 (-0.00623) | 4.95 (-1.62) | 5.45 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 (+0) | 28584 (-9952) | 739 (+0) | 27845 (-9952) | 0.0259 (+0.00665) | 0.974 (-0.00685) | 4.83 (-1.69) | 5.51 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 (+0) | 57324 (-21026) | 1408 (+0) | 55916 (-21026) | 0.0246 (+0.00656) | 0.975 (-0.00656) | 5.09 (-1.87) | 5.27 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 (+0) | 43192 (-14662) | 1027 (+0) | 42165 (-14662) | 0.0238 (+0.00598) | 0.976 (-0.00578) | 5.26 (-1.78) | 5.27 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 (+0) | 48820 (-17932) | 1180 (+0) | 47640 (-17932) | 0.0242 (+0.00647) | 0.976 (-0.00617) | 5.17 (-1.9) | 5.3 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 (+0) | 84364 (-29324) | 1948 (+0) | 82416 (-29324) | 0.0231 (+0.00599) | 0.977 (-0.00609) | 5.41 (-1.89) | 5.15 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 (+0) | 62362 (-21993) | 1405 (+0) | 60957 (-21993) | 0.0225 (+0.00583) | 0.977 (-0.00553) | 5.55 (-1.95) | 5.08 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0575 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00346 |
| Frame reader sample issue | 0.738 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.303 |
| Input FIFO full rate | 0 |
| VVC CTU symbolizer input | 0.02 |
| VVC residual symbolizer input | 0 |
| VVC syntax frontend input | 0.702 |
| VVC bin coder input | 0.572 |
| VVC stream emitter | 0.986 |
| VVC RBSP payload handoff | 0.995 |
| VVC CABAC byte handoff | 1 |
| VVC bit-writer output | 1 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (n/a) | 940 (n/a) | 67 (n/a) | 873 (n/a) | 0.0713 (n/a) | 0.929 (n/a) | 1.75 (n/a) | 14.7 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (n/a) | 1976 (n/a) | 122 (n/a) | 1854 (n/a) | 0.0617 (n/a) | 0.938 (n/a) | 2.02 (n/a) | 15.4 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 (n/a) | 1566 (n/a) | 72 (n/a) | 1494 (n/a) | 0.046 (n/a) | 0.954 (n/a) | 2.72 (n/a) | 8.16 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 648 (n/a) | 2095 (n/a) | 81 (n/a) | 2014 (n/a) | 0.0387 (n/a) | 0.961 (n/a) | 3.23 (n/a) | 8.18 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 624 (n/a) | 2170 (n/a) | 78 (n/a) | 2092 (n/a) | 0.0359 (n/a) | 0.964 (n/a) | 3.48 (n/a) | 6.78 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 640 (n/a) | 2420 (n/a) | 80 (n/a) | 2340 (n/a) | 0.0331 (n/a) | 0.967 (n/a) | 3.78 (n/a) | 6.3 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (n/a) | 6846 (n/a) | 586 (n/a) | 6260 (n/a) | 0.0856 (n/a) | 0.914 (n/a) | 1.46 (n/a) | 15.3 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (n/a) | 7249 (n/a) | 543 (n/a) | 6706 (n/a) | 0.0749 (n/a) | 0.925 (n/a) | 1.67 (n/a) | 14.2 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (n/a) | 2022 (n/a) | 139 (n/a) | 1883 (n/a) | 0.0687 (n/a) | 0.931 (n/a) | 1.82 (n/a) | 15.8 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (n/a) | 3519 (n/a) | 280 (n/a) | 3239 (n/a) | 0.0796 (n/a) | 0.92 (n/a) | 1.57 (n/a) | 13.7 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 (n/a) | 2536 (n/a) | 80 (n/a) | 2456 (n/a) | 0.0315 (n/a) | 0.968 (n/a) | 3.96 (n/a) | 6.6 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 672 (n/a) | 2968 (n/a) | 84 (n/a) | 2884 (n/a) | 0.0283 (n/a) | 0.972 (n/a) | 4.42 (n/a) | 5.8 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (n/a) | 9803 (n/a) | 766 (n/a) | 9037 (n/a) | 0.0781 (n/a) | 0.922 (n/a) | 1.6 (n/a) | 15.3 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 728 (n/a) | 4157 (n/a) | 91 (n/a) | 4066 (n/a) | 0.0219 (n/a) | 0.978 (n/a) | 5.71 (n/a) | 5.41 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6192 (n/a) | 11410 (n/a) | 774 (n/a) | 10636 (n/a) | 0.0678 (n/a) | 0.932 (n/a) | 1.84 (n/a) | 12.7 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 792 (n/a) | 5347 (n/a) | 99 (n/a) | 5248 (n/a) | 0.0185 (n/a) | 0.981 (n/a) | 6.75 (n/a) | 5.22 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (n/a) | 3032 (n/a) | 288 (n/a) | 2744 (n/a) | 0.095 (n/a) | 0.905 (n/a) | 1.32 (n/a) | 15.8 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 (n/a) | 3798 (n/a) | 176 (n/a) | 3622 (n/a) | 0.0463 (n/a) | 0.954 (n/a) | 2.7 (n/a) | 9.89 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2832 (n/a) | 6184 (n/a) | 354 (n/a) | 5830 (n/a) | 0.0572 (n/a) | 0.943 (n/a) | 2.18 (n/a) | 10.7 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (n/a) | 11292 (n/a) | 973 (n/a) | 10319 (n/a) | 0.0862 (n/a) | 0.914 (n/a) | 1.45 (n/a) | 14.7 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6072 (n/a) | 12400 (n/a) | 759 (n/a) | 11641 (n/a) | 0.0612 (n/a) | 0.939 (n/a) | 2.04 (n/a) | 12.9 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 808 (n/a) | 5952 (n/a) | 101 (n/a) | 5851 (n/a) | 0.017 (n/a) | 0.983 (n/a) | 7.37 (n/a) | 5.17 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 848 (n/a) | 7236 (n/a) | 106 (n/a) | 7130 (n/a) | 0.0146 (n/a) | 0.985 (n/a) | 8.53 (n/a) | 5.38 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11336 (n/a) | 19729 (n/a) | 1417 (n/a) | 18312 (n/a) | 0.0718 (n/a) | 0.928 (n/a) | 1.74 (n/a) | 12.8 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 (n/a) | 2888 (n/a) | 188 (n/a) | 2700 (n/a) | 0.0651 (n/a) | 0.935 (n/a) | 1.92 (n/a) | 11.3 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 (n/a) | 4267 (n/a) | 149 (n/a) | 4118 (n/a) | 0.0349 (n/a) | 0.965 (n/a) | 3.58 (n/a) | 8.33 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 (n/a) | 5267 (n/a) | 131 (n/a) | 5136 (n/a) | 0.0249 (n/a) | 0.975 (n/a) | 5.03 (n/a) | 6.86 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4376 (n/a) | 10443 (n/a) | 547 (n/a) | 9896 (n/a) | 0.0524 (n/a) | 0.948 (n/a) | 2.39 (n/a) | 10.2 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 848 (n/a) | 6999 (n/a) | 106 (n/a) | 6893 (n/a) | 0.0151 (n/a) | 0.985 (n/a) | 8.25 (n/a) | 5.47 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 (n/a) | 21026 (n/a) | 1604 (n/a) | 19422 (n/a) | 0.0763 (n/a) | 0.924 (n/a) | 1.64 (n/a) | 13.7 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 11960 (n/a) | 21919 (n/a) | 1495 (n/a) | 20424 (n/a) | 0.0682 (n/a) | 0.932 (n/a) | 1.83 (n/a) | 12.2 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 984 (n/a) | 10250 (n/a) | 123 (n/a) | 10127 (n/a) | 0.012 (n/a) | 0.988 (n/a) | 10.4 (n/a) | 5 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (n/a) | 5173 (n/a) | 385 (n/a) | 4788 (n/a) | 0.0744 (n/a) | 0.926 (n/a) | 1.68 (n/a) | 16.2 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (n/a) | 9347 (n/a) | 737 (n/a) | 8610 (n/a) | 0.0788 (n/a) | 0.921 (n/a) | 1.59 (n/a) | 14.6 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1152 (n/a) | 6874 (n/a) | 144 (n/a) | 6730 (n/a) | 0.0209 (n/a) | 0.979 (n/a) | 5.97 (n/a) | 7.16 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (n/a) | 17423 (n/a) | 1263 (n/a) | 16160 (n/a) | 0.0725 (n/a) | 0.928 (n/a) | 1.72 (n/a) | 13.6 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 9488 (n/a) | 18564 (n/a) | 1186 (n/a) | 17378 (n/a) | 0.0639 (n/a) | 0.936 (n/a) | 1.96 (n/a) | 11.6 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1432 (n/a) | 11038 (n/a) | 179 (n/a) | 10859 (n/a) | 0.0162 (n/a) | 0.984 (n/a) | 7.71 (n/a) | 5.75 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10336 (n/a) | 23473 (n/a) | 1292 (n/a) | 22181 (n/a) | 0.055 (n/a) | 0.945 (n/a) | 2.27 (n/a) | 10.5 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1160 (n/a) | 13387 (n/a) | 145 (n/a) | 13242 (n/a) | 0.0108 (n/a) | 0.989 (n/a) | 11.5 (n/a) | 5.23 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 (n/a) | 2793 (n/a) | 90 (n/a) | 2703 (n/a) | 0.0322 (n/a) | 0.968 (n/a) | 3.88 (n/a) | 7.27 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (n/a) | 13227 (n/a) | 1224 (n/a) | 12003 (n/a) | 0.0925 (n/a) | 0.907 (n/a) | 1.35 (n/a) | 17.2 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 (n/a) | 14105 (n/a) | 901 (n/a) | 13204 (n/a) | 0.0639 (n/a) | 0.936 (n/a) | 1.96 (n/a) | 12.2 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7424 (n/a) | 15999 (n/a) | 928 (n/a) | 15071 (n/a) | 0.058 (n/a) | 0.942 (n/a) | 2.16 (n/a) | 10.4 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14736 (n/a) | 25543 (n/a) | 1842 (n/a) | 23701 (n/a) | 0.0721 (n/a) | 0.928 (n/a) | 1.73 (n/a) | 13.3 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1048 (n/a) | 11591 (n/a) | 131 (n/a) | 11460 (n/a) | 0.0113 (n/a) | 0.989 (n/a) | 11.1 (n/a) | 5.03 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9240 (n/a) | 25303 (n/a) | 1155 (n/a) | 24148 (n/a) | 0.0456 (n/a) | 0.954 (n/a) | 2.74 (n/a) | 9.41 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (n/a) | 15954 (n/a) | 155 (n/a) | 15799 (n/a) | 0.00972 (n/a) | 0.99 (n/a) | 12.9 (n/a) | 5.19 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (n/a) | 6018 (n/a) | 454 (n/a) | 5564 (n/a) | 0.0754 (n/a) | 0.925 (n/a) | 1.66 (n/a) | 13.4 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 (n/a) | 10461 (n/a) | 727 (n/a) | 9734 (n/a) | 0.0695 (n/a) | 0.931 (n/a) | 1.8 (n/a) | 11.7 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5912 (n/a) | 13680 (n/a) | 739 (n/a) | 12941 (n/a) | 0.054 (n/a) | 0.946 (n/a) | 2.31 (n/a) | 10.2 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9136 (n/a) | 17944 (n/a) | 1142 (n/a) | 16802 (n/a) | 0.0636 (n/a) | 0.936 (n/a) | 1.96 (n/a) | 10 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17856 (n/a) | 30566 (n/a) | 2232 (n/a) | 28334 (n/a) | 0.073 (n/a) | 0.927 (n/a) | 1.71 (n/a) | 13.6 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10656 (n/a) | 24806 (n/a) | 1332 (n/a) | 23474 (n/a) | 0.0537 (n/a) | 0.946 (n/a) | 2.33 (n/a) | 9.23 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25432 (n/a) | 43418 (n/a) | 3179 (n/a) | 40239 (n/a) | 0.0732 (n/a) | 0.927 (n/a) | 1.71 (n/a) | 13.8 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12904 (n/a) | 32680 (n/a) | 1613 (n/a) | 31067 (n/a) | 0.0494 (n/a) | 0.951 (n/a) | 2.53 (n/a) | 9.12 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (n/a) | 5820 (n/a) | 293 (n/a) | 5527 (n/a) | 0.0503 (n/a) | 0.95 (n/a) | 2.48 (n/a) | 11.4 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8752 (n/a) | 14389 (n/a) | 1094 (n/a) | 13295 (n/a) | 0.076 (n/a) | 0.924 (n/a) | 1.64 (n/a) | 14.1 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6888 (n/a) | 14828 (n/a) | 861 (n/a) | 13967 (n/a) | 0.0581 (n/a) | 0.942 (n/a) | 2.15 (n/a) | 9.65 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 (n/a) | 25089 (n/a) | 1760 (n/a) | 23329 (n/a) | 0.0702 (n/a) | 0.93 (n/a) | 1.78 (n/a) | 12.3 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1592 (n/a) | 14972 (n/a) | 199 (n/a) | 14773 (n/a) | 0.0133 (n/a) | 0.987 (n/a) | 9.4 (n/a) | 5.85 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23088 (n/a) | 39943 (n/a) | 2886 (n/a) | 37057 (n/a) | 0.0723 (n/a) | 0.928 (n/a) | 1.73 (n/a) | 13 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1920 (n/a) | 20891 (n/a) | 240 (n/a) | 20651 (n/a) | 0.0115 (n/a) | 0.989 (n/a) | 10.9 (n/a) | 5.83 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 (n/a) | 55566 (n/a) | 4179 (n/a) | 51387 (n/a) | 0.0752 (n/a) | 0.925 (n/a) | 1.66 (n/a) | 13.6 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0472 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00292 |
| Frame reader sample issue | 0.74 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.36 |
| Input FIFO full rate | 0 |
| VVC CTU symbolizer input | 0.0207 |
| VVC residual symbolizer input | 0 |
| VVC syntax frontend input | 0.703 |
| VVC bin coder input | 0.571 |
| VVC stream emitter | 0.214 |
| VVC RBSP payload handoff | 0.214 |
| VVC CABAC byte handoff | 0.214 |
| VVC bit-writer output | 0.999 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27872 (n/a) | 54696 (n/a) | 3484 (n/a) | 51212 (n/a) | 0.0637 (n/a) | 0.936 (n/a) | 1.96 (n/a) | 11.9 |
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47464 (n/a) | 88725 (n/a) | 5933 (n/a) | 82792 (n/a) | 0.0669 (n/a) | 0.933 (n/a) | 1.87 (n/a) | 10.8 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33776 (n/a) | 94833 (n/a) | 4222 (n/a) | 90611 (n/a) | 0.0445 (n/a) | 0.955 (n/a) | 2.81 (n/a) | 7.72 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1648 (n/a) | 23627 (n/a) | 206 (n/a) | 23421 (n/a) | 0.00872 (n/a) | 0.991 (n/a) | 14.3 (n/a) | 5.13 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2232 (n/a) | 29548 (n/a) | 279 (n/a) | 29269 (n/a) | 0.00944 (n/a) | 0.991 (n/a) | 13.2 (n/a) | 5.7 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 62832 (n/a) | 123607 (n/a) | 7854 (n/a) | 115753 (n/a) | 0.0635 (n/a) | 0.936 (n/a) | 1.97 (n/a) | 11.4 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18832 (n/a) | 60124 (n/a) | 2354 (n/a) | 57770 (n/a) | 0.0392 (n/a) | 0.961 (n/a) | 3.19 (n/a) | 7.34 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38992 (n/a) | 89447 (n/a) | 4874 (n/a) | 84573 (n/a) | 0.0545 (n/a) | 0.946 (n/a) | 2.29 (n/a) | 9.71 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 6288 (n/a) | 88026 (n/a) | 786 (n/a) | 87240 (n/a) | 0.00893 (n/a) | 0.991 (n/a) | 14 (n/a) | 5.37 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49064 (n/a) | 112141 (n/a) | 6133 (n/a) | 106008 (n/a) | 0.0547 (n/a) | 0.945 (n/a) | 2.29 (n/a) | 9.13 |
