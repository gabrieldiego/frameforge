# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md). RTL output utilization
belongs in [output-utilization.md](output-utilization.md).

`scripts/validate.py` reports the FrameForge software bitstream and, when
RTL validation is enabled, the RTL bitstream size. Software and RTL
bitstreams are expected to match exactly for implemented AV2 features. The
AV2 reference path used here is decode-only; these validation runs do not
invoke `avmenc`, `aomenc`, or `vpenc`, and reference-encoder bitrates are
not tracked in this report.

## 2026-06-24 Residual Packet Packing Checkpoint

Baseline and current sources:

- Baseline Git SHA: `2ac43800abe655dd03f213a1cb3e70b604fde4c1`
- Current validated source Git SHA: `d5c8aea952cebba4cd835e6ddf94cdd1e26c7a47`
- Delta columns compare against the previous documented AV2 quality/bitrate
  checkpoint where the same vector or aggregate was present.

Validation result:

- `screenshot-sweep-444`: PASS (64/64).
- `screenshot-multictu-444`: PASS (10/10).
- `racehorses-sweep-420`: PASS (64/64).
- `racehorses-multictu-420`: PASS (10/10).
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.
- Screenshot 4:4:4 remains lossless (`inf` PSNR). RaceHorses 4:2:0 remains
  intentionally lossy with finite PSNR.

Aggregate results:

| Set | Cases | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---:|---|---:|---:|---|
| `screenshot-sweep-444` | 64 | PASS | 749136 (-6136) | 9.0318 (-0.0740) | inf |
| `screenshot-multictu-444` | 10 | PASS | 562144 (-8336) | 6.1209 (-0.0908) | inf |
| `racehorses-sweep-420` | 64 | PASS | 182464 (+0) | 2.1998 (+0.0000) | avg 24.08 dB, range 22.47-33.31 dB |
| `racehorses-multictu-420` | 10 | PASS | 186256 (+0) | 2.0280 (+0.0000) | avg 22.70 dB, range 22.36-23.03 dB |

IBC candidate summary for 4:4:4:

| Set | 8x8 blocks | Raw above matches | Raw left matches | Direct above matches | Direct left matches | Selected above copies | Selected left copies |
|---|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 1296 | 311 | 480 | 311 | 480 | 0 | 361 |
| `screenshot-multictu-444` | 1435 | 578 | 796 | 578 | 796 | 0 | 677 |

### Screenshot 4:4:4 Full Sweep

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 5.3750 (+0.0000) | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 15.5000 (+0.0000) | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 2.1667 (+0.0000) | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 2.8750 (+0.0000) | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 1.5000 (+0.0000) | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 1.3542 (+0.0000) | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (-32) | 15.2500 (-0.0714) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6960 (+144) | 13.5938 (+0.2813) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (-64) | 13.7500 (-0.5000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4880 (+264) | 19.0625 (+1.0313) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 472 (+0) | 1.2292 (+0.0000) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 512 (+0) | 1.0000 (+0.0000) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9208 (-536) | 14.3875 (-0.8375) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 608 (+0) | 0.7917 (+0.0000) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10312 (-336) | 11.5089 (-0.3750) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 696 (+0) | 0.6797 (+0.0000) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3632 (+96) | 18.9167 (+0.5000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (-56) | 6.9583 (-0.1459) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+48) | 12.2361 (+0.0833) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+1024) | 20.4271 (+1.3333) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15256 (-104) | 15.8917 (-0.1083) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 0.5903 (+0.0000) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 0.5357 (+0.0000) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 21472 (-1848) | 13.9792 (-1.2031) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+160) | 12.4062 (+0.6250) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1384 (+56) | 2.7031 (+0.1093) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1440 (-256) | 1.8750 (-0.3333) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11816 (+728) | 11.5391 (+0.7110) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 0.5375 (+0.0000) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20288 (-1888) | 13.2083 (-1.2292) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26072 (-1192) | 14.5491 (-0.6652) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 0.4180 (+0.0000) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+104) | 18.9250 (+0.3250) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14504 (+1264) | 22.6625 (+1.9750) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1296 (-320) | 1.3500 (-0.3333) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21328 (-504) | 16.6625 (-0.3937) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22824 (+848) | 14.2650 (+0.5300) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1712 (+160) | 0.8917 (+0.0834) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19224 (-1344) | 8.5821 (-0.6000) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 0.4469 (+0.0000) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 1.7292 (+0.0000) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 17104 (+1248) | 22.2708 (+1.6250) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14712 (-400) | 12.7708 (-0.3473) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15952 (+224) | 10.3854 (+0.1458) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31720 (+1392) | 16.5208 (+0.7250) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 0.3819 (+0.0000) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10856 (-2392) | 4.0387 (-0.8899) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 0.4036 (+0.0000) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+200) | 15.9643 (+0.4464) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9600 (-208) | 10.7143 (-0.2321) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11736 (-240) | 8.7321 (-0.1786) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18064 (-800) | 10.0804 (-0.4464) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 38912 (+1728) | 17.3714 (+0.7714) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22672 (+128) | 8.4345 (+0.0476) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56384 (-1376) | 17.9796 (-0.4388) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 27056 (-1144) | 7.5491 (-0.3192) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5568 (+224) | 10.8750 (+0.4375) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 17248 (+1800) | 16.8438 (+1.7579) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13032 (-464) | 8.4844 (-0.3021) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32824 (+784) | 16.0273 (+0.3828) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2064 (-32) | 0.8063 (-0.0124) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49072 (-1088) | 15.9740 (-0.3541) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2536 (+24) | 0.7076 (+0.0067) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74392 (-2160) | 18.1621 (-0.5274) | inf |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 85944 (-2576) | 10.4912 (-0.3145) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 42560 (-1368) | 5.1953 (-0.1670) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 9784 (-384) | 0.5972 (-0.0234) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 42200 (-3568) | 3.4342 (-0.2904) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105584 (+4112) | 8.5924 (+0.3346) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57192 (-3376) | 12.4115 (-0.7326) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 0.3611 (+0.0000) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3000 (+0) | 0.5787 (+0.0000) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136424 (+824) | 12.5390 (+0.0758) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 77792 (-2000) | 8.4410 (-0.2170) | inf |

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
