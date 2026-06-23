# VVC Quality And Bitrate Baseline

This file records the current VVC quality and bitrate checkpoint. Older
intermediate reports are intentionally kept out of this page so the current
baseline is easy to compare against future runs. Use git history for retired
measurements.

Synthesis area/timing belongs in [synthesis.md](synthesis.md). RTL output
utilization belongs in [output-utilization.md](output-utilization.md).

`scripts/validate.py` reports the software Annex-B stream and, when RTL
validation is enabled, the RTL Annex-B stream. Implemented VVC features are
expected to produce bit-exact software and RTL bitstreams. The reference path
is decode-only: VTM decodes the FrameForge bitstream and its reconstruction
must match the software/RTL reconstruction checksum.

## 2026-06-23 VVC Multi-CTU IBC Throughput Checkpoint

Source baseline:

- Baseline Git SHA: `33e4c40f88f0919ed0189adcb65cea1738e5c5e2`
- Current validated RTL/source Git SHA: `d2cb6801f111a0023d7f982b875faccbf8c17f91`
- Delta columns for the refreshed `screenshot-multictu-444` rows compare
  against the previous documented VVC quality/bitrate report. Retained rows
  from the previous full-regression checkpoint keep their previous values until
  the next full VVC regression refresh.

Validation commands:

```sh
make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- Other rows in this file remain from the previous full-regression checkpoint
  until the next full VVC regression refresh.
- 4:4:4 vectors are lossless (`inf` PSNR). 4:2:0 vectors use the current
  lossy residual path.

Aggregate quality/bitrate:

| Set | Cases | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---:|---|---:|---:|---|
| `racehorses-sweep-420` | 64 | PASS | 113168 (+0) | 1.3644 (+0.0000) | avg 23.03 dB, range 19.43-29.32 dB |
| `racehorses-multictu-420` | 10 | PASS | 92920 (+0) | 1.0118 (+0.0000) | avg 22.35 dB, range 22.11-22.74 dB |
| `screenshot-sweep-444` | 64 | PASS | 377168 (-21672) | 4.5473 (-0.2613) | inf |
| `screenshot-multictu-444` | 10 | PASS | 286232 (-2768) | 3.1166 (-0.0302) | inf |

### RaceHorses 4:2:0 Sweep

Aggregate SW bits: `113168` (+0).
Aggregate SW bpp: `1.3644` (+0.0000).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 (+0) | 8.8750 (+0.0000) | 27.17 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 (+0) | 5.2500 (+0.0000) | 21.98 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 (+0) | 3.7500 (+0.0000) | 21.61 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 (+0) | 3.1562 (+0.0000) | 19.82 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 (+0) | 2.7250 (+0.0000) | 20.06 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 (+0) | 2.5000 (+0.0000) | 19.43 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 (+0) | 2.2679 (+0.0000) | 19.53 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 (+0) | 2.1875 (+0.0000) | 19.97 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 (+0) | 4.8125 (+0.0000) | 28.90 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 (+0) | 3.1562 (+0.0000) | 21.09 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 2.3750 (+0.0000) | 26.22 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 (+0) | 2.0312 (+0.0000) | 24.37 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 (+0) | 1.8625 (+0.0000) | 24.09 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 (+0) | 1.6771 (+0.0000) | 26.14 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 (+0) | 1.6071 (+0.0000) | 23.67 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 (+0) | 1.5625 (+0.0000) | 24.00 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 (+0) | 3.5417 (+0.0000) | 29.32 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 (+0) | 2.3958 (+0.0000) | 22.84 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 (+0) | 1.9028 (+0.0000) | 23.33 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 (+0) | 1.7083 (+0.0000) | 22.97 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 (+0) | 1.5667 (+0.0000) | 22.00 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 (+0) | 1.4514 (+0.0000) | 22.20 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 (+0) | 1.4167 (+0.0000) | 22.14 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 (+0) | 1.3594 (+0.0000) | 22.15 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 (+0) | 2.9688 (+0.0000) | 28.16 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 (+0) | 2.0781 (+0.0000) | 22.52 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 (+0) | 1.6979 (+0.0000) | 22.06 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 (+0) | 1.5078 (+0.0000) | 21.37 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 (+0) | 1.4062 (+0.0000) | 21.62 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 (+0) | 1.3125 (+0.0000) | 20.99 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 (+0) | 1.2768 (+0.0000) | 21.29 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 (+0) | 1.2227 (+0.0000) | 21.23 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 (+0) | 2.4750 (+0.0000) | 28.15 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 (+0) | 1.8000 (+0.0000) | 24.04 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 (+0) | 1.5000 (+0.0000) | 23.51 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 (+0) | 1.3625 (+0.0000) | 23.28 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 (+0) | 1.2950 (+0.0000) | 23.73 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 (+0) | 1.2292 (+0.0000) | 23.50 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 (+0) | 1.1929 (+0.0000) | 23.90 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 (+0) | 1.1562 (+0.0000) | 23.60 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 (+0) | 2.2083 (+0.0000) | 28.23 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 (+0) | 1.6042 (+0.0000) | 24.44 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 (+0) | 1.3958 (+0.0000) | 22.96 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 (+0) | 1.2656 (+0.0000) | 22.43 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 (+0) | 1.1833 (+0.0000) | 22.05 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 (+0) | 1.1493 (+0.0000) | 21.50 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 (+0) | 1.1161 (+0.0000) | 21.99 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 (+0) | 1.0781 (+0.0000) | 22.03 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 (+0) | 2.1607 (+0.0000) | 22.29 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 (+0) | 1.6071 (+0.0000) | 22.21 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 (+0) | 1.3512 (+0.0000) | 22.04 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 (+0) | 1.2545 (+0.0000) | 21.81 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 (+0) | 1.1750 (+0.0000) | 22.48 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 (+0) | 1.1250 (+0.0000) | 22.03 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 (+0) | 1.0842 (+0.0000) | 22.41 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 (+0) | 1.0580 (+0.0000) | 22.41 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 (+0) | 2.0469 (+0.0000) | 22.85 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 (+0) | 1.5469 (+0.0000) | 23.20 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 (+0) | 1.3177 (+0.0000) | 23.04 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 (+0) | 1.2344 (+0.0000) | 22.97 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 (+0) | 1.1375 (+0.0000) | 23.10 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 (+0) | 1.1094 (+0.0000) | 22.72 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 (+0) | 1.0826 (+0.0000) | 22.51 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 (+0) | 1.0547 (+0.0000) | 22.55 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

Aggregate SW bits: `92920` (+0).
Aggregate SW bpp: `1.0118` (+0.0000).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 (+0) | 1.0352 (+0.0000) | 22.52 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 (+0) | 1.0029 (+0.0000) | 22.23 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 (+0) | 0.9512 (+0.0000) | 22.16 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 (+0) | 1.0306 (+0.0000) | 22.22 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 (+0) | 0.9147 (+0.0000) | 22.68 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 (+0) | 1.0972 (+0.0000) | 22.74 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 (+0) | 1.0990 (+0.0000) | 22.20 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 (+0) | 1.1404 (+0.0000) | 22.40 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 (+0) | 1.0353 (+0.0000) | 22.11 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 (+0) | 1.0243 (+0.0000) | 22.23 |

### Screenshot 4:4:4 Sweep

Aggregate SW bits: `377168` (-21672).
Aggregate SW bpp: `4.5473` (-0.2613).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (+0) | 8.3750 (+0.0000) | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (+0) | 7.6250 (+0.0000) | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 (-24) | 3.0000 (-0.1250) | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 648 (-168) | 2.5312 (-0.6563) | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 624 (-56) | 1.9500 (-0.1750) | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 640 (-72) | 1.6667 (-0.1875) | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (+0) | 10.4643 (+0.0000) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (+0) | 8.4844 (+0.0000) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (+0) | 8.6875 (+0.0000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (+0) | 8.7500 (+0.0000) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 (-72) | 1.6667 (-0.1875) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 672 (-112) | 1.3125 (-0.2187) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (+0) | 9.5750 (+0.0000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 728 (-184) | 0.9479 (-0.2396) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6192 (-8) | 6.9107 (-0.0089) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 792 (-256) | 0.7734 (-0.2500) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (+0) | 12.0000 (+0.0000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 (-88) | 3.6667 (-0.2291) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2832 (-120) | 4.9167 (-0.2083) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (+0) | 10.1354 (+0.0000) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6072 (-8) | 6.3250 (-0.0083) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 808 (-304) | 0.7014 (-0.2639) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 848 (-360) | 0.6310 (-0.2678) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11336 (+8) | 7.3802 (+0.0052) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 (-8) | 5.8750 (-0.0312) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 (-184) | 2.3281 (-0.3594) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 (-496) | 1.3646 (-0.6458) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4376 (-64) | 4.2734 (-0.0625) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 848 (-344) | 0.6625 (-0.2688) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 (-264) | 8.3542 (-0.1718) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 11960 (-736) | 6.6741 (-0.4107) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 984 (-592) | 0.4805 (-0.2890) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (+0) | 9.6250 (+0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (+0) | 9.2125 (+0.0000) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1152 (-192) | 1.2000 (-0.2000) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (+0) | 7.8937 (+0.0000) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 9488 (-2128) | 5.9300 (-1.3300) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1432 (-1288) | 0.7458 (-0.6709) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10336 (-216) | 4.6143 (-0.0964) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1160 (-992) | 0.4531 (-0.3875) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 (-48) | 1.8750 (-0.1250) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (+0) | 12.7500 (+0.0000) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 (-48) | 6.2569 (-0.0417) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7424 (-304) | 4.8333 (-0.1979) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14736 (-224) | 7.6750 (-0.1167) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1048 (-672) | 0.4549 (-0.2916) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9240 (-1016) | 3.4375 (-0.3780) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (-1168) | 0.4036 (-0.3803) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (+0) | 8.1071 (+0.0000) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 (+320) | 6.4911 (+0.3572) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5912 (-368) | 4.3988 (-0.2738) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9136 (-800) | 5.0982 (-0.4464) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17856 (-32) | 7.9714 (-0.0143) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10656 (-2776) | 3.9643 (-1.0327) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25432 (-48) | 8.1097 (-0.0153) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12904 (-1888) | 3.6004 (-0.5268) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (+0) | 4.5781 (+0.0000) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8752 (-16) | 8.5469 (-0.0156) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6888 (-200) | 4.4844 (-0.1302) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 (-48) | 6.8750 (-0.0234) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1592 (-848) | 0.6219 (-0.3312) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23088 (-88) | 7.5156 (-0.0287) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1920 (-2032) | 0.5357 (-0.5670) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 (-40) | 8.1621 (-0.0098) | inf |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

Aggregate SW bits: `286232` (-2768).
Aggregate SW bpp: `3.1166` (-0.0302).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47296 (-168) | 5.7734 (-0.0205) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18584 (-248) | 2.2686 (-0.0302) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 4992 (-1296) | 0.3047 (-0.0791) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33112 (-664) | 2.6953 (-0.0534) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49416 (+352) | 4.0215 (+0.0286) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27760 (-112) | 6.0243 (-0.0243) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1288 (-360) | 0.2795 (-0.0781) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 1848 (-384) | 0.3565 (-0.0741) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 63200 (+368) | 5.8088 (+0.0338) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38736 (-256) | 4.2023 (-0.0286) | inf |
