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

## 2026-06-24 VVC Full Regression Checkpoint

Source baseline:

- Baseline Git SHA: `33e4c40f88f0919ed0189adcb65cea1738e5c5e2`
- Current validated RTL/source Git SHA: `d2cb6801f111a0023d7f982b875faccbf8c17f91`
- Delta columns compare the latest run against the previous documented VVC
  quality/bitrate report where the same vector was present.

Validation commands:

```sh
make validate-set CODEC=vvc \
  VALIDATION_SET=racehorses-sweep-420 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=racehorses-multictu-420 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

```

Validation result:

- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/VTM checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- 4:4:4 vectors are lossless (`inf` PSNR). 4:2:0 vectors use the current
  lossy residual path.

Aggregate quality/bitrate:

| Set | Cases | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---:|---|---:|---:|---|
| `racehorses-sweep-420` | 64 | PASS | 113168 (+0) | 1.3644 (+0.0000) | avg 23.03 dB, range 19.43-29.32 dB |
| `racehorses-multictu-420` | 10 | PASS | 92920 (+0) | 1.0118 (+0.0000) | avg 22.35 dB, range 22.11-22.74 dB |
| `screenshot-sweep-444` | 64 | PASS | 377064 (-104) | 4.5460 (-0.0013) | inf |
| `screenshot-multictu-444` | 10 | PASS | 286232 (+0) | 3.1166 (+0.0000) | inf |

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

Aggregate SW bits: `377064` (-104).
Aggregate SW bpp: `4.5460` (-0.0013).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (+0) | 8.3750 (+0.0000) | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (+0) | 7.6250 (+0.0000) | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 (+0) | 3.0000 (+0.0000) | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 640 (-8) | 2.5000 (-0.0312) | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 608 (-16) | 1.9000 (-0.0500) | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 616 (-24) | 1.6042 (-0.0625) | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (+0) | 10.4643 (+0.0000) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (+0) | 8.4844 (+0.0000) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (+0) | 8.6875 (+0.0000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (+0) | 8.7500 (+0.0000) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 (+0) | 1.6667 (+0.0000) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 656 (-16) | 1.2812 (-0.0313) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (+0) | 9.5750 (+0.0000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 688 (-40) | 0.8958 (-0.0521) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6200 (+8) | 6.9196 (+0.0089) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 720 (-72) | 0.7031 (-0.0703) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (+0) | 12.0000 (+0.0000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 (+0) | 3.6667 (+0.0000) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2848 (+16) | 4.9444 (+0.0277) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (+0) | 10.1354 (+0.0000) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6080 (+8) | 6.3333 (+0.0083) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 736 (-72) | 0.6389 (-0.0625) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 752 (-96) | 0.5595 (-0.0715) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11328 (-8) | 7.3750 (-0.0052) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 (+0) | 5.8750 (+0.0000) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 (+0) | 2.3281 (+0.0000) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 (+0) | 1.3646 (+0.0000) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4384 (+8) | 4.2812 (+0.0078) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 776 (-72) | 0.6062 (-0.0563) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 (+0) | 8.3542 (+0.0000) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 12648 (+688) | 7.0580 (+0.3839) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 824 (-160) | 0.4023 (-0.0782) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (+0) | 9.6250 (+0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (+0) | 9.2125 (+0.0000) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1120 (-32) | 1.1667 (-0.0333) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (+0) | 7.8937 (+0.0000) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 10736 (+1248) | 6.7100 (+0.7800) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1296 (-136) | 0.6750 (-0.0708) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10288 (-48) | 4.5929 (-0.0214) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 944 (-216) | 0.3688 (-0.0843) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 (+0) | 1.8750 (+0.0000) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (+0) | 12.7500 (+0.0000) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 (+0) | 6.2569 (+0.0000) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7400 (-24) | 4.8177 (-0.0156) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14728 (-8) | 7.6708 (-0.0042) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (-168) | 0.3819 (-0.0730) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9192 (-48) | 3.4196 (-0.0179) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 992 (-248) | 0.3229 (-0.0807) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (+0) | 8.1071 (+0.0000) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 (+0) | 6.4911 (+0.0000) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5936 (+24) | 4.4167 (+0.0179) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9104 (-32) | 5.0804 (-0.0178) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17880 (+24) | 7.9821 (+0.0107) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10544 (-112) | 3.9226 (-0.0417) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25424 (-8) | 8.1071 (-0.0026) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12760 (-144) | 3.5603 (-0.0401) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (+0) | 4.5781 (+0.0000) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8760 (+8) | 8.5547 (+0.0078) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6872 (-16) | 4.4740 (-0.0104) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 (+0) | 6.8750 (+0.0000) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1464 (-128) | 0.5719 (-0.0500) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23128 (+40) | 7.5286 (+0.0130) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1696 (-224) | 0.4732 (-0.0625) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 (+0) | 8.1621 (+0.0000) | inf |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

Aggregate SW bits: `286232` (+0).
Aggregate SW bpp: `3.1166` (+0.0000).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47296 (+0) | 5.7734 (+0.0000) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18584 (+0) | 2.2686 (+0.0000) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 4992 (+0) | 0.3047 (+0.0000) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33112 (+0) | 2.6947 (-0.0006) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49416 (+0) | 4.0215 (+0.0000) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27760 (+0) | 6.0243 (+0.0000) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1288 (+0) | 0.2795 (+0.0000) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 1848 (+0) | 0.3565 (+0.0000) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 63200 (+0) | 5.8088 (+0.0000) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38736 (+0) | 4.2031 (+0.0008) | inf |
