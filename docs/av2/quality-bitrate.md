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

## 2026-06-25 AV2 Bubble Rate Optimization

Baseline and current sources:

- Baseline Git SHA: `6779c2e4b2726adef94cd7921dd62f106e454afb+working-tree`
- Current validated source Git SHA: `31bb9321589844a4615d8dd87fe96ef6b54f43ed`
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
| `screenshot-sweep-444` | 64 | PASS | 749352 (+0) | 9.0344 (+0.0000) | inf |
| `screenshot-multictu-444` | 10 | PASS | 562104 (+0) | 6.1205 (-0.0000) | inf |
| `racehorses-sweep-420` | 64 | PASS | 182464 (+0) | 2.1998 (+0.0000) | avg 24.08 dB, range 22.47-33.31 dB |
| `racehorses-multictu-420` | 10 | PASS | 186256 (+0) | 2.0280 (+0.0000) | avg 22.70 dB, range 22.36-23.03 dB |

IBC candidate summary for 4:4:4:

| Set | 8x8 blocks | Raw above matches | Raw left matches | Direct above matches | Direct left matches | Selected above copies | Selected left copies |
|---|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 1296 | 311 | 480 | 311 | 465 | 10 | 344 |
| `screenshot-multictu-444` | 1435 | 578 | 796 | 578 | 796 | 3 | 676 |

### Screenshot 4:4:4 Full Sweep

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 5.3750 (+0.0000) | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 15.5000 (+0.0000) | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 2.1667 (+0.0000) | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 2.8750 (+0.0000) | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 1.5000 (+0.0000) | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 1.3542 (+0.0000) | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 15.2500 (+0.0000) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6960 (+0) | 13.5938 (+0.0000) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 13.7500 (+0.0000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4880 (+0) | 19.0625 (+0.0000) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (+0) | 1.3125 (+0.0000) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 552 (+0) | 1.0781 (+0.0000) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9208 (+0) | 14.3875 (+0.0000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 704 (+0) | 0.9167 (+0.0000) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10312 (+0) | 11.5089 (+0.0000) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 824 (+0) | 0.8047 (+0.0000) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3632 (+0) | 18.9167 (+0.0000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 6.9583 (+0.0000) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+0) | 12.2361 (+0.0000) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 20.4271 (+0.0000) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15256 (+0) | 15.8917 (+0.0000) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 0.5903 (+0.0000) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 0.5357 (+0.0000) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 21472 (+0) | 13.9792 (+0.0000) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 12.4062 (+0.0000) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1384 (+0) | 2.7031 (+0.0000) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1440 (+0) | 1.8750 (+0.0000) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11816 (+0) | 11.5391 (+0.0000) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 0.5375 (+0.0000) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20232 (+0) | 13.1719 (+0.0000) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26072 (+0) | 14.5491 (+0.0000) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 0.4180 (+0.0000) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 18.9250 (+0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14504 (+0) | 22.6625 (+0.0000) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1296 (+0) | 1.3500 (+0.0000) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21328 (+0) | 16.6625 (+0.0000) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22824 (+0) | 14.2650 (+0.0000) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1712 (+0) | 0.8917 (+0.0000) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19224 (+0) | 8.5821 (+0.0000) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 0.4469 (+0.0000) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 640 (+0) | 1.6667 (+0.0000) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 17104 (+0) | 22.2708 (+0.0000) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14712 (+0) | 12.7708 (+0.0000) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15952 (+0) | 10.3854 (+0.0000) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31720 (+0) | 16.5208 (+0.0000) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 0.3819 (+0.0000) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10856 (+0) | 4.0387 (+0.0000) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 0.4036 (+0.0000) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 15.9643 (+0.0000) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9600 (+0) | 10.7143 (+0.0000) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11736 (+0) | 8.7321 (+0.0000) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18064 (+0) | 10.0804 (+0.0000) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 38912 (+0) | 17.3714 (+0.0000) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22672 (+0) | 8.4345 (+0.0000) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56384 (+0) | 17.9796 (+0.0000) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 27056 (+0) | 7.5491 (+0.0000) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5568 (+0) | 10.8750 (+0.0000) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 17248 (+0) | 16.8438 (+0.0000) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13032 (+0) | 8.4844 (+0.0000) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32824 (+0) | 16.0273 (+0.0000) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2064 (+0) | 0.8063 (+0.0000) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49072 (+0) | 15.9740 (+0.0000) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2536 (+0) | 0.7076 (+0.0000) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74392 (+0) | 18.1621 (+0.0000) | inf |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 85944 (+0) | 10.4912 (+0.0000) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 42560 (+0) | 5.1953 (+0.0000) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 9784 (+0) | 0.5972 (+0.0000) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 42200 (+0) | 3.4342 (+0.0000) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105584 (+0) | 8.5924 (+0.0000) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57192 (+0) | 12.4115 (+0.0000) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 0.3611 (+0.0000) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2984 (+0) | 0.5756 (+0.0000) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136424 (+0) | 12.5390 (+0.0000) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 77768 (+0) | 8.4384 (+0.0000) | inf |

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
