# VVC RTL Output Utilization Baseline

This file records the latest VVC RTL simulation throughput counters per
validation vector. Older measurement sections are intentionally left to git
history so this page stays focused on the current optimization baseline.

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

Codec-internal counters are optional and codec-specific. The VVC report keeps
the common top-level metrics in every section, then records selected VVC
CABAC/residual probes only when they are useful for directing throughput work.

## 2026-06-19 Residual Remainder Scan Trim

Measured after trimming the VVC 4:2:0 residual `abs_remainder` pass so the
4x4 residual symbol emitter starts the remainder scan at the latest regular
scan position that can actually emit a remainder. The bitstream syntax and
reconstructions are unchanged; bitrate deltas remain zero for all listed
vectors.

Baseline and current sources:

- Baseline report Git SHA: `9ccd873d6407a9f112492ef1a153e82d3550e216`
- Baseline validated RTL Git SHA: `7d54a8c42552942b9b7be5ac3941b1a7518bd4af`
- Current validated RTL Git SHA: `65812b2f1d0d2050cbe69c97b981496a8825fd47`
- Baseline mode: previous VVC CABAC emission-throughput checkpoint.
- Current mode: same bitstream syntax, plus residual remainder-scan trimming.

Validation result:

- `racehorses-sweep-420`: OK (64/64)
- `racehorses-multictu-420`: OK (10/10)
- Focused `screenshot_640_sweep_64x64_1f_yuv444p8.yuv` 4:4:4 smoke check:
  OK, unchanged from the prior full screenshot sweep.
- All listed RaceHorses vectors matched SW/RTL bitstream checksums and
  SW/RTL/VTM reconstruction checksums.
- Bitstream lengths were unchanged, so bitrate deltas remain `+0.0000`.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) | Cycles/pixel range |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| racehorses-sweep-420 | 64 (+0) | 113168 (+0) | 617594 (-6618) | 14146 (+0) | 603448 (-6618) | 0.0229 (+0.000205) | 0.977 (+0.000) | 5.46 (-0.0627) | 7.45 (-0.0841) | 7.07-15 |
| racehorses-multictu-420 | 10 (+0) | 92920 (+0) | 652090 (-7560) | 11615 (+0) | 640475 (-7560) | 0.0178 (+0.000212) | 0.982 (+0.000188) | 7.02 (-0.0822) | 7.1 (-0.0797) | 6.86-7.43 |

### 4:2:0 RaceHorses Full Sweep

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 (+0) | 958 (-4) | 71 (+0) | 887 (-4) | 0.0741 (+0.000313) | 0.926 (-0.000113) | 1.69 (-0.00338) | 15 (-0.0312) |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 (+0) | 1415 (-14) | 84 (+0) | 1331 (-14) | 0.0594 (+0.000564) | 0.941 (-0.000364) | 2.11 (-0.0243) | 11.1 (-0.145) |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 (+0) | 1849 (-17) | 90 (+0) | 1759 (-17) | 0.0487 (+0.000475) | 0.951 (-0.000675) | 2.57 (-0.0219) | 9.63 (-0.0898) |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 (+0) | 2281 (-31) | 101 (+0) | 2180 (-31) | 0.0443 (+0.000579) | 0.956 (-0.000279) | 2.82 (-0.037) | 8.91 (-0.12) |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 (+0) | 2793 (-10) | 109 (+0) | 2684 (-10) | 0.039 (+0.000126) | 0.961 (+0.000) | 3.2 (-0.00702) | 8.73 (-0.0319) |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 (+0) | 3271 (-47) | 120 (+0) | 3151 (-47) | 0.0367 (+0.000486) | 0.963 (-0.000686) | 3.41 (-0.0527) | 8.52 (-0.122) |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 (+0) | 3735 (-38) | 127 (+0) | 3608 (-38) | 0.034 (+0.000303) | 0.966 (+0.000) | 3.68 (-0.0338) | 8.34 (-0.0829) |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 (+0) | 4225 (-45) | 140 (+0) | 4085 (-45) | 0.0331 (+0.000336) | 0.967 (-0.000136) | 3.77 (-0.0377) | 8.25 (-0.088) |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 (+0) | 1359 (+0) | 77 (+0) | 1282 (+0) | 0.0567 (+0.000) | 0.943 (+0.000341) | 2.21 (-0.00383) | 10.6 (+0.0172) |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 (+0) | 2244 (-26) | 101 (+0) | 2143 (-26) | 0.045 (+0.000509) | 0.955 (-0.00101) | 2.78 (-0.0328) | 8.77 (-0.104) |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 3189 (-27) | 114 (+0) | 3075 (-27) | 0.0357 (+0.000348) | 0.964 (-0.000748) | 3.5 (-0.0333) | 8.3 (-0.0753) |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 (+0) | 3992 (-51) | 130 (+0) | 3862 (-51) | 0.0326 (+0.000365) | 0.967 (-0.000565) | 3.84 (-0.0515) | 7.8 (-0.103) |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 (+0) | 5069 (-55) | 149 (+0) | 4920 (-55) | 0.0294 (+0.000294) | 0.971 (-0.000394) | 4.25 (-0.0475) | 7.92 (-0.0897) |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 (+0) | 5786 (-63) | 161 (+0) | 5625 (-63) | 0.0278 (+0.000326) | 0.972 (+0.000174) | 4.49 (-0.0478) | 7.53 (-0.0861) |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 (+0) | 6910 (-88) | 180 (+0) | 6730 (-88) | 0.026 (+0.000349) | 0.974 (+0.000) | 4.8 (-0.0614) | 7.71 (-0.0979) |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 (+0) | 7701 (-104) | 200 (+0) | 7501 (-104) | 0.026 (+0.000371) | 0.974 (+0.000) | 4.81 (-0.0669) | 7.52 (-0.0995) |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 (+0) | 1832 (-13) | 85 (+0) | 1747 (-13) | 0.0464 (+0.000297) | 0.954 (-0.000397) | 2.69 (-0.0159) | 9.54 (-0.0683) |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 (+0) | 3133 (-29) | 115 (+0) | 3018 (-29) | 0.0367 (+0.000306) | 0.963 (-0.000706) | 3.41 (-0.0346) | 8.16 (-0.0711) |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 (+0) | 4571 (-49) | 137 (+0) | 4434 (-49) | 0.03 (+0.000272) | 0.97 (+0.000) | 4.17 (-0.0494) | 7.94 (-0.0842) |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 (+0) | 5803 (-79) | 164 (+0) | 5639 (-79) | 0.0283 (+0.000361) | 0.972 (-0.000261) | 4.42 (-0.057) | 7.56 (-0.104) |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 (+0) | 7473 (-99) | 188 (+0) | 7285 (-99) | 0.0252 (+0.000357) | 0.975 (-0.000157) | 4.97 (-0.0613) | 7.78 (-0.106) |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 (+0) | 8555 (-132) | 209 (+0) | 8346 (-132) | 0.0244 (+0.00033) | 0.976 (-0.00043) | 5.12 (-0.0834) | 7.43 (-0.114) |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 (+0) | 10198 (-145) | 238 (+0) | 9960 (-145) | 0.0233 (+0.000338) | 0.977 (-0.000338) | 5.36 (-0.0739) | 7.59 (-0.112) |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 (+0) | 11390 (-156) | 261 (+0) | 11129 (-156) | 0.0229 (+0.000315) | 0.977 (+0.000) | 5.45 (-0.075) | 7.42 (-0.105) |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 (+0) | 2328 (-12) | 95 (+0) | 2233 (-12) | 0.0408 (+0.000208) | 0.959 (+0.000192) | 3.06 (-0.0168) | 9.09 (-0.0463) |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 (+0) | 4079 (-29) | 133 (+0) | 3946 (-29) | 0.0326 (+0.000206) | 0.967 (-0.000606) | 3.83 (-0.0264) | 7.97 (-0.0532) |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 (+0) | 6021 (-52) | 163 (+0) | 5858 (-52) | 0.0271 (+0.000272) | 0.973 (+0.000) | 4.62 (-0.0427) | 7.84 (-0.0702) |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 (+0) | 7528 (-75) | 193 (+0) | 7335 (-75) | 0.0256 (+0.000238) | 0.974 (-0.000638) | 4.88 (-0.0444) | 7.35 (-0.0684) |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 (+0) | 9695 (-94) | 225 (+0) | 9470 (-94) | 0.0232 (+0.000208) | 0.977 (-0.000208) | 5.39 (-0.0539) | 7.57 (-0.0758) |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 (+0) | 11211 (-109) | 252 (+0) | 10959 (-109) | 0.0225 (+0.000178) | 0.978 (-0.000478) | 5.56 (-0.059) | 7.3 (-0.0712) |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 (+0) | 13451 (-155) | 286 (+0) | 13165 (-155) | 0.0213 (+0.000262) | 0.979 (-0.000262) | 5.88 (-0.0711) | 7.51 (-0.0839) |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 (+0) | 14924 (-129) | 313 (+0) | 14611 (-129) | 0.021 (+0.000173) | 0.979 (+0.000) | 5.96 (-0.0499) | 7.29 (-0.0629) |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 (+0) | 2768 (-10) | 99 (+0) | 2669 (-10) | 0.0358 (+0.000166) | 0.964 (+0.000234) | 3.49 (-0.0151) | 8.65 (-0.03) |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 (+0) | 4902 (-39) | 144 (+0) | 4758 (-39) | 0.0294 (+0.000276) | 0.971 (-0.000376) | 4.26 (-0.0348) | 7.66 (-0.0606) |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 (+0) | 7355 (-67) | 180 (+0) | 7175 (-67) | 0.0245 (+0.000173) | 0.976 (-0.000473) | 5.11 (-0.0424) | 7.66 (-0.0685) |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 (+0) | 9366 (-84) | 218 (+0) | 9148 (-84) | 0.0233 (+0.000176) | 0.977 (-0.000276) | 5.37 (-0.0496) | 7.32 (-0.0628) |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 (+0) | 11896 (-123) | 259 (+0) | 11637 (-123) | 0.0218 (+0.000272) | 0.978 (+0.000228) | 5.74 (-0.0587) | 7.43 (-0.075) |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 (+0) | 13867 (-167) | 295 (+0) | 13572 (-167) | 0.0213 (+0.000274) | 0.979 (-0.000274) | 5.88 (-0.0742) | 7.22 (-0.0876) |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 (+0) | 16549 (-178) | 334 (+0) | 16215 (-178) | 0.0202 (+0.000182) | 0.98 (-0.000182) | 6.19 (-0.0665) | 7.39 (-0.0821) |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 (+0) | 18490 (-173) | 370 (+0) | 18120 (-173) | 0.02 (+0.000211) | 0.98 (+0.000) | 6.25 (-0.0634) | 7.22 (-0.0673) |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 (+0) | 3223 (-12) | 106 (+0) | 3117 (-12) | 0.0329 (+0.000) | 0.967 (+0.000111) | 3.8 (-0.00929) | 8.39 (-0.0268) |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 (+0) | 5804 (-58) | 154 (+0) | 5650 (-58) | 0.0265 (+0.000233) | 0.973 (-0.000533) | 4.71 (-0.049) | 7.56 (-0.0727) |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 (+0) | 8728 (-65) | 201 (+0) | 8527 (-65) | 0.023 (+0.000129) | 0.977 (+0.000) | 5.43 (-0.0421) | 7.58 (-0.0536) |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 (+0) | 11082 (-95) | 243 (+0) | 10839 (-95) | 0.0219 (+0.000227) | 0.978 (+0.000) | 5.7 (-0.0494) | 7.21 (-0.0652) |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 (+0) | 14089 (-103) | 284 (+0) | 13805 (-103) | 0.0202 (+0.000158) | 0.98 (-0.000158) | 6.2 (-0.0489) | 7.34 (-0.052) |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 (+0) | 16524 (-162) | 331 (+0) | 16193 (-162) | 0.02 (+0.000231) | 0.98 (+0.000) | 6.24 (-0.0598) | 7.17 (-0.0681) |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 (+0) | 19720 (-200) | 375 (+0) | 19345 (-200) | 0.019 (+0.000216) | 0.981 (+0.000) | 6.57 (-0.0667) | 7.34 (-0.0737) |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 (+0) | 21723 (-242) | 414 (+0) | 21309 (-242) | 0.0191 (+0.000258) | 0.981 (+0.000) | 6.56 (-0.0711) | 7.07 (-0.0787) |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 (+0) | 3839 (-33) | 121 (+0) | 3718 (-33) | 0.0315 (+0.000319) | 0.968 (-0.000519) | 3.97 (-0.0341) | 8.57 (-0.0708) |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 (+0) | 6826 (-80) | 180 (+0) | 6646 (-80) | 0.0264 (+0.00027) | 0.974 (-0.00037) | 4.74 (-0.0597) | 7.62 (-0.0917) |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 (+0) | 10139 (-66) | 227 (+0) | 9912 (-66) | 0.0224 (+0.000189) | 0.978 (-0.000389) | 5.58 (-0.0369) | 7.54 (-0.0461) |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 (+0) | 13007 (-151) | 281 (+0) | 12726 (-151) | 0.0216 (+0.000204) | 0.978 (-0.000604) | 5.79 (-0.064) | 7.26 (-0.0816) |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 (+0) | 16548 (-167) | 329 (+0) | 16219 (-167) | 0.0199 (+0.000182) | 0.98 (+0.000118) | 6.29 (-0.0628) | 7.39 (-0.0725) |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 (+0) | 19258 (-210) | 378 (+0) | 18880 (-210) | 0.0196 (+0.000228) | 0.98 (-0.000628) | 6.37 (-0.0716) | 7.16 (-0.0756) |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 (+0) | 22968 (-280) | 425 (+0) | 22543 (-280) | 0.0185 (+0.000204) | 0.981 (-0.000504) | 6.76 (-0.0847) | 7.32 (-0.086) |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 (+0) | 25562 (-230) | 474 (+0) | 25088 (-230) | 0.0185 (+0.000143) | 0.981 (-0.000543) | 6.74 (-0.059) | 7.13 (-0.0677) |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 (+0) | 4308 (-21) | 131 (+0) | 4177 (-21) | 0.0304 (+0.000109) | 0.97 (-0.000409) | 4.11 (-0.0193) | 8.41 (-0.0459) |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 (+0) | 7717 (-117) | 198 (+0) | 7519 (-117) | 0.0257 (+0.000358) | 0.974 (-0.000658) | 4.87 (-0.0782) | 7.54 (-0.114) |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 (+0) | 11577 (-113) | 253 (+0) | 11324 (-113) | 0.0219 (+0.000254) | 0.978 (+0.000146) | 5.72 (-0.0601) | 7.54 (-0.0729) |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 (+0) | 14816 (-185) | 316 (+0) | 14500 (-185) | 0.0213 (+0.000228) | 0.979 (-0.000328) | 5.86 (-0.0692) | 7.23 (-0.0856) |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 (+0) | 18738 (-232) | 364 (+0) | 18374 (-232) | 0.0194 (+0.000226) | 0.981 (-0.000426) | 6.43 (-0.0752) | 7.32 (-0.0905) |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 (+0) | 21829 (-264) | 426 (+0) | 21403 (-264) | 0.0195 (+0.000215) | 0.98 (-0.000515) | 6.41 (-0.0748) | 7.11 (-0.0842) |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 (+0) | 26223 (-347) | 485 (+0) | 25738 (-347) | 0.0185 (+0.000195) | 0.982 (-0.000495) | 6.76 (-0.0915) | 7.32 (-0.0933) |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 (+0) | 29184 (-367) | 540 (+0) | 28644 (-367) | 0.0185 (+0.000203) | 0.981 (-0.000503) | 6.76 (-0.0844) | 7.12 (-0.085) |

### 4:2:0 RaceHorses Multi-CTU And Partial Crops

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 (+0) | 58385 (-764) | 1060 (+0) | 57325 (-764) | 0.0182 (+0.000255) | 0.982 (-0.000155) | 6.89 (-0.095) | 7.13 (-0.0929) |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 (+0) | 57854 (-632) | 1027 (+0) | 56827 (-632) | 0.0178 (+0.000152) | 0.982 (+0.000248) | 7.04 (-0.0784) | 7.06 (-0.0777) |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 (+0) | 113688 (-1310) | 1948 (+0) | 111740 (-1310) | 0.0171 (+0.000235) | 0.983 (-0.000135) | 7.3 (-0.0848) | 6.94 (-0.081) |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 (+0) | 87078 (-1071) | 1583 (+0) | 85495 (-1071) | 0.0182 (+0.000179) | 0.982 (-0.000179) | 6.88 (-0.084) | 7.09 (-0.0836) |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 (+0) | 84355 (-835) | 1405 (+0) | 82950 (-835) | 0.0167 (+0.000156) | 0.983 (-0.000656) | 7.5 (-0.0751) | 6.86 (-0.0652) |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 (+0) | 33821 (-429) | 632 (+0) | 33189 (-429) | 0.0187 (+0.000187) | 0.981 (-0.000687) | 6.69 (-0.0807) | 7.34 (-0.0904) |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 (+0) | 33271 (-349) | 633 (+0) | 32638 (-349) | 0.019 (+0.000226) | 0.981 (+0.000) | 6.57 (-0.0699) | 7.22 (-0.0797) |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 (+0) | 38536 (-427) | 739 (+0) | 37797 (-427) | 0.0192 (+0.000177) | 0.981 (-0.000177) | 6.52 (-0.0717) | 7.43 (-0.0864) |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 (+0) | 78350 (-996) | 1408 (+0) | 76942 (-996) | 0.018 (+0.000271) | 0.982 (+0.000) | 6.96 (-0.0842) | 7.2 (-0.0887) |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 (+0) | 66752 (-747) | 1180 (+0) | 65572 (-747) | 0.0177 (+0.000177) | 0.982 (-0.000677) | 7.07 (-0.0788) | 7.24 (-0.0769) |
