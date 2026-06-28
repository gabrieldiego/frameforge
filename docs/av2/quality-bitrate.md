# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md). RTL output utilization
belongs in [output-utilization.md](output-utilization.md).

`scripts/validate.py` reports the FrameForge software bitstream and, when
RTL validation is enabled, the RTL bitstream size. Software and RTL
bitstreams are expected to match exactly for implemented AV2
features. The reference path used here is decode-only; the external
reference-decoder decodes the FrameForge bitstream and its
reconstruction must match the software/RTL reconstruction checksum.

## AV2 analyzer overlap and IBC safety checkpoint

Baseline and current sources:

- Baseline Git SHA: `509b74f7670b9bfff61209f0779c12e256b00f07`
- Current validated source Git SHA: `8b06ee49bb8aa6944afcad0101f0867f84dfa49a`
- Delta columns compare against the previous documented AV2 quality/bitrate
  checkpoint where the same vector or aggregate was present.

Validation result:

- `screenshot-sweep-444`: PASS (64/64).
- `screenshot-multictu-444`: PASS (10/10).
- `racehorses-sweep-420`: PASS (64/64).
- `racehorses-multictu-420`: PASS (10/10).
- `multiframe-smoke`: PASS (4/4).
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.
- Screenshot 4:4:4 remains lossless (`inf` PSNR). RaceHorses 4:2:0 remains
  intentionally lossy with finite PSNR.

Aggregate results:

| Set | Cases | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---:|---|---:|---:|---|
| `screenshot-sweep-444` | 64 | PASS | 763928 (+18016) | 9.2102 (+0.2172) | inf |
| `screenshot-multictu-444` | 10 | PASS | 579256 (+20192) | 6.3072 (+0.2198) | inf |
| `racehorses-sweep-420` | 64 | PASS | 182464 (+0) | 2.1998 (+0.0000) | avg 24.08 dB, range 22.47-33.31 dB |
| `racehorses-multictu-420` | 10 | PASS | 186256 (+0) | 2.0280 (+0.0000) | avg 22.70 dB, range 22.36-23.03 dB |
| `multiframe-smoke` | 4 | PASS | 19680 (+1688) | 4.1000 (+0.3517) | inf |

IBC candidate summary for 4:4:4:

| Set | 8x8 blocks | Raw above matches | Raw left matches | Direct above matches | Direct left matches | Selected above copies | Selected left copies |
|---|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 1296 | 311 | 480 | 311 | 480 | 0 | 0 |
| `screenshot-multictu-444` | 1435 | 578 | 796 | 578 | 796 | 0 | 0 |

### Screenshot 4:4:4 Full Sweep

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 5.3750 (+0.0000) | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 15.5000 (+0.0000) | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+8) | 2.1667 (+0.0417) | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 2.8750 (+0.0000) | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 1.5000 (+0.0000) | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 1.3542 (+0.0000) | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 15.2500 (+0.0000) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 13.3125 (+0.0000) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 13.7500 (+0.0000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4872 (-8) | 19.0312 (-0.0313) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 528 (+24) | 1.3750 (+0.0625) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 592 (+40) | 1.1562 (+0.0781) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9456 (-64) | 14.7750 (-0.1000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 744 (+48) | 0.9688 (+0.0626) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10344 (+104) | 11.5446 (+0.1160) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 888 (+64) | 0.8672 (+0.0625) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3648 (-312) | 19.0000 (-1.6250) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 6.9583 (+0.0000) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+280) | 12.2361 (+0.4861) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 20.4271 (+0.0000) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15248 (-8) | 15.8833 (-0.0084) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 960 (+280) | 0.8333 (+0.2430) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1064 (+344) | 0.7917 (+0.2560) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 22424 (+584) | 14.5990 (+0.3802) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 12.4062 (+0.0000) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (+24) | 2.7500 (+0.0469) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1824 (+384) | 2.3750 (+0.5000) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11896 (+40) | 11.6172 (+0.0391) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1032 (+352) | 0.8063 (+0.2751) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20456 (+224) | 13.3177 (+0.1458) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26008 (+0) | 14.5134 (+0.0000) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1480 (+624) | 0.7227 (+0.3047) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 18.9250 (+0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14872 (+816) | 23.2375 (+1.2750) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1464 (+168) | 1.5250 (+0.1750) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21616 (+248) | 16.8875 (+0.1937) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22944 (+640) | 14.3400 (+0.4000) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (+440) | 1.1208 (+0.2291) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19784 (+384) | 8.8321 (+0.1714) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2032 (+888) | 0.7937 (+0.3468) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+24) | 1.7292 (+0.0625) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 16960 (+32) | 22.0833 (+0.0416) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14800 (+80) | 12.8472 (+0.0694) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15920 (+24) | 10.3646 (+0.0156) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31960 (-8) | 16.6458 (-0.0042) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1624 (+744) | 0.7049 (+0.3230) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 11432 (+440) | 4.2530 (+0.1637) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2328 (+1096) | 0.7578 (+0.3568) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 15.9643 (+0.0000) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9664 (+64) | 10.7857 (+0.0714) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11904 (+160) | 8.8571 (+0.1190) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18376 (+304) | 10.2545 (+0.1697) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 36832 (-240) | 16.4429 (-0.1071) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27208 (+4536) | 10.1220 (+1.6875) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56456 (+200) | 18.0026 (+0.0638) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28088 (+1096) | 7.8371 (+0.3059) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5640 (+72) | 11.0156 (+0.1406) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 16376 (-136) | 15.9922 (-0.1328) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13264 (+248) | 8.6354 (+0.1614) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32936 (+320) | 16.0820 (+0.1562) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2824 (+760) | 1.1031 (+0.2968) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49024 (+88) | 15.9583 (+0.0286) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3864 (+1264) | 1.0781 (+0.3527) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74368 (+232) | 18.1562 (+0.0566) | inf |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 86760 (+160) | 10.5908 (+0.0195) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 44520 (+2368) | 5.4346 (+0.2891) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 15912 (+6112) | 0.9712 (+0.3731) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45032 (+3040) | 3.6647 (+0.2474) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105520 (+2664) | 8.5872 (+0.2168) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57616 (+408) | 12.5035 (+0.0886) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3112 (+1448) | 0.6753 (+0.3142) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4504 (+1528) | 0.8688 (+0.2947) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 137280 (+424) | 12.6176 (+0.0389) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79000 (+2040) | 8.5720 (+0.2213) | inf |

### RaceHorses 4:2:0 Full Sweep

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (+0) | 4.7500 (+0.0000) | 33.31 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 3.5625 (+0.0000) | 23.72 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 3.3333 (+0.0000) | 24.37 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 3.2188 (+0.0000) | 23.44 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 3.0500 (+0.0000) | 23.68 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 2.6875 (+0.0000) | 23.69 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 2.7679 (+0.0000) | 22.99 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 2.7188 (+0.0000) | 22.72 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 2.6250 (+0.0000) | 32.71 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 2.9062 (+0.0000) | 23.50 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 2.3750 (+0.0000) | 24.91 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 2.3750 (+0.0000) | 25.44 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 2.4125 (+0.0000) | 25.97 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 2.3125 (+0.0000) | 25.53 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 2.3304 (+0.0000) | 24.58 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 2.2812 (+0.0000) | 24.42 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 2.7500 (+0.0000) | 30.47 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 2.5417 (+0.0000) | 23.59 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 2.2639 (+0.0000) | 23.95 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 2.1250 (+0.0000) | 23.36 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 2.2917 (+0.0000) | 22.93 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 2.2569 (+0.0000) | 22.73 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 2.2560 (+0.0000) | 22.47 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 2.3333 (+0.0000) | 22.47 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 2.3438 (+0.0000) | 28.68 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 2.3281 (+0.0000) | 23.57 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 2.0833 (+0.0000) | 23.84 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 2.1797 (+0.0000) | 23.72 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 2.3062 (+0.0000) | 23.39 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 2.1771 (+0.0000) | 22.93 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 2.1830 (+0.0000) | 22.90 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 2.2188 (+0.0000) | 22.75 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 2.3750 (+0.0000) | 28.02 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 2.3875 (+0.0000) | 23.56 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 2.0667 (+0.0000) | 23.33 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 2.1500 (+0.0000) | 23.18 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 2.1650 (+0.0000) | 23.17 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 2.3000 (+0.0000) | 22.80 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 2.1857 (+0.0000) | 22.86 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 2.1719 (+0.0000) | 22.85 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 2.5208 (+0.0000) | 27.20 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 2.3750 (+0.0000) | 23.94 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 1.9792 (+0.0000) | 23.43 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2.0521 (+0.0000) | 23.12 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 2.1375 (+0.0000) | 23.09 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 2.1771 (+0.0000) | 22.77 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 2.1488 (+0.0000) | 22.90 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 2.1198 (+0.0000) | 22.93 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 2.3929 (+0.0000) | 24.65 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 2.3125 (+0.0000) | 22.94 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 1.9940 (+0.0000) | 22.95 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 2.0580 (+0.0000) | 23.17 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 2.0964 (+0.0000) | 23.17 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 2.2113 (+0.0000) | 22.92 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 2.1378 (+0.0000) | 23.08 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 2.1205 (+0.0000) | 22.94 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 2.3125 (+0.0000) | 24.39 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 2.1875 (+0.0000) | 23.53 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2.0521 (+0.0000) | 23.44 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 2.0078 (+0.0000) | 23.45 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 2.0781 (+0.0000) | 23.38 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 2.1146 (+0.0000) | 23.06 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 2.1607 (+0.0000) | 23.06 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 2.1289 (+0.0000) | 22.93 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 2.0732 (+0.0000) | 22.76 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 2.0947 (+0.0000) | 22.36 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 1.9419 (+0.0000) | 22.66 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 2.0254 (+0.0000) | 22.40 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 1.8405 (+0.0000) | 23.03 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 2.1302 (+0.0000) | 22.97 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 2.1562 (+0.0000) | 22.72 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 2.1960 (+0.0000) | 22.92 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 2.0728 (+0.0000) | 22.81 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 2.0729 (+0.0000) | 22.40 |

### Multi-Frame Smoke

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| multiframe_black_420_16x16_2f_yuv420p8.yuv | PASS | 1936 (+0) | 3.7812 (+0.0000) | inf |
| multiframe_black_tall_420_8x24_5f_yuv420p8.yuv | PASS | 3840 (+0) | 4.0000 (+0.0000) | inf |
| multiframe_motion_444_16x8_2f_yuv444p8.yuv | PASS | 1408 (+120) | 5.5000 (+0.4688) | inf |
| multiframe_motion_wide_444_48x32_2f_yuv444p8.yuv | PASS | 12496 (+1568) | 4.0677 (+0.5104) | inf |
