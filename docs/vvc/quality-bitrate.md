# VVC Quality And Bitrate Baselines

This file records VVC-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md). RTL output utilization
belongs in [output-utilization.md](output-utilization.md).

`scripts/validate.py` reports the FrameForge software bitstream and, when
RTL validation is enabled, the RTL bitstream size. Software and RTL
bitstreams are expected to match exactly for implemented VVC
features. The reference path used here is decode-only; the external
VTM decodes the FrameForge bitstream and its
reconstruction must match the software/RTL reconstruction checksum.

## 2026-06-29 VVC Report Checkpoint

Baseline and current sources:

- Baseline Git SHA: `d2cb6801f111a0023d7f982b875faccbf8c17f91`
- Current validated source Git SHA: `28fa335ecfba2e9463e416688f0144bd29f159f3`
- Delta columns compare against the previous documented VVC quality/bitrate
  checkpoint where the same vector or aggregate was present.

Validation result:

- `racehorses-sweep-420`: PASS (64/64).
- `racehorses-multictu-420`: PASS (10/10).
- `screenshot-sweep-444`: PASS (64/64).
- `screenshot-multictu-444`: PASS (10/10).
- `multiframe-smoke`: PASS (4/4).
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/VTM reconstruction checksums.
- Screenshot 4:4:4 remains lossless (`inf` PSNR). RaceHorses 4:2:0 remains
  intentionally lossy with finite PSNR.

Aggregate results:

| Set | Cases | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---:|---|---:|---:|---|
| `racehorses-sweep-420` | 64 | PASS | 113168 (+0) | 1.3644 (-0.0000) | avg 23.03 dB, range 19.43-29.32 dB |
| `racehorses-multictu-420` | 10 | PASS | 92920 (+0) | 1.0118 (-0.0000) | avg 22.35 dB, range 22.11-22.74 dB |
| `screenshot-sweep-444` | 64 | PASS | 377064 (+0) | 4.5460 (+0.0000) | inf |
| `screenshot-multictu-444` | 10 | PASS | 286232 (+0) | 3.1166 (+0.0000) | inf |
| `multiframe-smoke` | 4 | PASS | 5184 (n/a) | 1.0800 (n/a) | avg 49.89 dB, range 49.89-49.89 dB |

### RaceHorses 4:2:0 Full Sweep

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

### Screenshot 4:4:4 Full Sweep

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (+0) | 8.3750 (+0.0000) | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (+0) | 7.6250 (+0.0000) | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 576 (+0) | 3.0000 (+0.0000) | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 640 (+0) | 2.5000 (+0.0000) | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 608 (+0) | 1.9000 (+0.0000) | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 616 (+0) | 1.6042 (+0.0000) | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (+0) | 10.4643 (+0.0000) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (+0) | 8.4844 (+0.0000) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (+0) | 8.6875 (+0.0000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (+0) | 8.7500 (+0.0000) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 640 (+0) | 1.6667 (+0.0000) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 656 (+0) | 1.2812 (+0.0000) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (+0) | 9.5750 (+0.0000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 688 (+0) | 0.8958 (+0.0000) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6200 (+0) | 6.9196 (+0.0000) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 720 (+0) | 0.7031 (+0.0000) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (+0) | 12.0000 (+0.0000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1408 (+0) | 3.6667 (+0.0000) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2848 (+0) | 4.9444 (+0.0000) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (+0) | 10.1354 (+0.0000) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6080 (+0) | 6.3333 (+0.0000) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 736 (+0) | 0.6389 (+0.0000) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 752 (+0) | 0.5595 (+0.0000) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11328 (+0) | 7.3750 (+0.0000) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1504 (+0) | 5.8750 (+0.0000) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1192 (+0) | 2.3281 (+0.0000) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1048 (+0) | 1.3646 (+0.0000) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4384 (+0) | 4.2812 (+0.0000) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 776 (+0) | 0.6062 (+0.0000) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 12832 (+0) | 8.3542 (+0.0000) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 12648 (+0) | 7.0580 (+0.0000) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 824 (+0) | 0.4023 (+0.0000) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (+0) | 9.6250 (+0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (+0) | 9.2125 (+0.0000) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1120 (+0) | 1.1667 (+0.0000) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (+0) | 7.8937 (+0.0000) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 10736 (+0) | 6.7100 (+0.0000) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1296 (+0) | 0.6750 (+0.0000) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10288 (+0) | 4.5929 (+0.0000) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 944 (+0) | 0.3688 (+0.0000) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 720 (+0) | 1.8750 (+0.0000) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (+0) | 12.7500 (+0.0000) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7208 (+0) | 6.2569 (+0.0000) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7400 (+0) | 4.8177 (+0.0000) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14728 (+0) | 7.6708 (+0.0000) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 0.3819 (+0.0000) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 9192 (+0) | 3.4196 (+0.0000) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 992 (+0) | 0.3229 (+0.0000) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (+0) | 8.1071 (+0.0000) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5816 (+0) | 6.4911 (+0.0000) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 5936 (+0) | 4.4167 (+0.0000) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9104 (+0) | 5.0804 (+0.0000) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17880 (+0) | 7.9821 (+0.0000) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 10544 (+0) | 3.9226 (+0.0000) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25424 (+0) | 8.1071 (+0.0000) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 12760 (+0) | 3.5603 (+0.0000) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (+0) | 4.5781 (+0.0000) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8760 (+0) | 8.5547 (+0.0000) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 6872 (+0) | 4.4740 (+0.0000) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14080 (+0) | 6.8750 (+0.0000) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 1464 (+0) | 0.5719 (+0.0000) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23128 (+0) | 7.5286 (+0.0000) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 1696 (+0) | 0.4732 (+0.0000) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33432 (+0) | 8.1621 (+0.0000) | inf |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47296 (+0) | 5.7734 (+0.0000) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18584 (+0) | 2.2686 (+0.0000) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 4992 (+0) | 0.3047 (+0.0000) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33112 (+0) | 2.6947 (+0.0000) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49416 (+0) | 4.0215 (+0.0000) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27760 (+0) | 6.0243 (+0.0000) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1288 (+0) | 0.2795 (+0.0000) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 1848 (+0) | 0.3565 (+0.0000) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 63200 (+0) | 5.8088 (+0.0000) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38736 (+0) | 4.2031 (+0.0000) | inf |

### Multi-Frame Smoke

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| multiframe_black_420_16x16_2f_yuv420p8.yuv | PASS | 784 (n/a) | 1.5312 (n/a) | 49.89 |
| multiframe_black_tall_420_8x24_5f_yuv420p8.yuv | PASS | 1288 (n/a) | 1.3417 (n/a) | 49.89 |
| multiframe_motion_444_16x8_2f_yuv444p8.yuv | PASS | 784 (n/a) | 3.0625 (n/a) | inf |
| multiframe_motion_wide_444_48x32_2f_yuv444p8.yuv | PASS | 2328 (n/a) | 0.7578 (n/a) | inf |
