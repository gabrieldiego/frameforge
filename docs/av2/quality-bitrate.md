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

## 2026-06-24 Full AV2 Regression Checkpoint

Baseline and current sources:

- Baseline Git SHA for 4:4:4 deltas: `307363b80a71d77e19178e972a522c42bf8bfe1c`
- Baseline Git SHA for 4:2:0 deltas: `3b644b32e731840bb1da774312c5a0c70298f040`
- Current validated source Git SHA: `2ac43800abe655dd03f213a1cb3e70b604fde4c1`
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
| `screenshot-sweep-444` | 64 | PASS | 755272 (+0) | 9.1058 (+0.0000) | inf |
| `screenshot-multictu-444` | 10 | PASS | 570480 (+0) | 6.2117 (+0.0000) | inf |
| `racehorses-sweep-420` | 64 | PASS | 182464 (+0) | 2.1998 (+0.0000) | avg 24.08 dB, range 22.47-33.31 dB |
| `racehorses-multictu-420` | 10 | PASS | 186256 (n/a) | 2.0280 (n/a) | avg 22.70 dB, range 22.36-23.03 dB |

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
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (+0) | 15.3214 (+0.0000) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 13.3125 (+0.0000) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (+0) | 14.2500 (+0.0000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 18.0312 (+0.0001) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 472 (+0) | 1.2292 (+0.0000) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 512 (+0) | 1.0000 (+0.0000) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 15.2250 (+0.0000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 608 (+0) | 0.7917 (+0.0000) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 11.8839 (+0.0000) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 696 (+0) | 0.6797 (+0.0000) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 18.4167 (+0.0000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 7.1042 (+0.0000) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 12.1528 (+0.0000) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 19.0938 (-0.0001) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 16.0000 (+0.0000) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 0.5903 (+0.0000) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 0.5357 (+0.0000) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 15.1823 (+0.0000) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 11.7812 (+0.0000) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1328 (+0) | 2.5938 (+0.0000) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1696 (+0) | 2.2083 (+0.0000) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11088 (+0) | 10.8281 (+0.0000) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 0.5375 (+0.0000) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 14.4375 (+0.0000) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 15.2143 (+0.0000) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 0.4180 (+0.0000) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 18.6000 (+0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 20.6875 (+0.0000) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1616 (+0) | 1.6833 (+0.0000) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (+0) | 17.0562 (+0.0000) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 21976 (+0) | 13.7350 (+0.0000) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1552 (+0) | 0.8083 (+0.0000) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20568 (+0) | 9.1821 (+0.0000) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 0.4469 (+0.0000) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 1.7292 (+0.0000) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (+0) | 20.6458 (+0.0000) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15112 (+0) | 13.1181 (+0.0000) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15728 (+0) | 10.2396 (+0.0000) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30328 (+0) | 15.7958 (+0.0000) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 0.3819 (+0.0000) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13248 (+0) | 4.9286 (+0.0000) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 0.4036 (+0.0000) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (+0) | 15.5179 (+0.0000) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9808 (+0) | 10.9464 (+0.0000) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11976 (+0) | 8.9107 (+0.0000) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18864 (+0) | 10.5268 (+0.0000) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37184 (+0) | 16.6000 (+0.0000) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22544 (+0) | 8.3869 (+0.0000) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+0) | 18.4184 (+0.0000) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28200 (+0) | 7.8683 (+0.0000) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (+0) | 10.4375 (+0.0000) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (+0) | 15.0859 (+0.0000) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13496 (+0) | 8.7865 (+0.0000) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32040 (+0) | 15.6445 (+0.0000) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2096 (+0) | 0.8187 (+0.0000) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50160 (+0) | 16.3281 (+0.0000) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2512 (+0) | 0.7009 (+0.0000) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76552 (+0) | 18.6895 (+0.0000) | inf |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 88520 (+0) | 10.8057 (+0.0000) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 43928 (+0) | 5.3623 (+0.0000) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 10168 (+0) | 0.6206 (+0.0000) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45768 (+0) | 3.7246 (+0.0000) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 101472 (+0) | 8.2578 (+0.0000) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 60568 (+0) | 13.1441 (+0.0000) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 0.3611 (+0.0000) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3000 (+0) | 0.5787 (+0.0000) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 135600 (+0) | 12.4632 (+0.0000) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79792 (+0) | 8.6580 (+0.0000) | inf |

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
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (n/a) | 2.0254 (n/a) | 22.40 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (n/a) | 1.8405 (n/a) | 23.03 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (n/a) | 2.1302 (n/a) | 22.97 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (n/a) | 2.1562 (n/a) | 22.72 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 2.1960 (+0.0000) | 22.92 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 2.0728 (+0.0000) | 22.81 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 2.0729 (+0.0000) | 22.40 |
