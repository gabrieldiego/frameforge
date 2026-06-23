# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md).

`scripts/validate.py` reports the FrameForge software bitstream and, when
RTL validation is enabled, the RTL bitstream size. Software and RTL
bitstreams are expected to match exactly for implemented AV2 features. The
AV2 reference path used here is decode-only; these validation runs do not
invoke `avmenc`, `aomenc`, or `vpenc`, and reference-encoder bitrates are
not tracked in this report.

## 2026-06-20 AVM-Order Local IBC BVP Stack

Baseline and current sources:

- Baseline Git SHA: `fecba0947c6b46f801f0394a8e0699f68c1c542f`
- Current validated source Git SHA: `307363b80a71d77e19178e972a522c42bf8bfe1c`
- Baseline mode: previous documented AV2 4:4:4 AVM-valid local-hash
  IntraBC checkpoint.
- Current mode: AVM-order spatial BVP stack construction before default
  candidates, while keeping the current conservative left-copy-only selector
  and the same 32-bit local hash table per 8x8 block.
- Delta columns compare against the previous documented AV2 4:4:4 quality
  checkpoint.

Validation result:

- `cargo test av2 --lib`: 25/25 PASS.
- `screenshot-sweep-444`: 64/64 PASS.
- `screenshot-multictu-444`: 10/10 PASS.
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.
- The screenshot 4:4:4 path remains lossless; PSNR is `inf` for every listed
  vector.
- Above-copy and top-row left-copy probes are still disabled because AVM
  rejects those BVs under the current fixed-DRL availability model.

Aggregate results:

| Set | Cases | Status | SW bits (delta) | SW bpp (delta) | Selected IBC copies (delta) | PSNR |
|---|---:|---|---:|---:|---:|---|
| screenshot-sweep-444 | 64 | PASS | 755272 (-80) | 9.1058 (-0.0010) | 361 (+3) | inf |
| screenshot-multictu-444 | 10 | PASS | 570480 (-32) | 6.2117 (-0.0003) | 677 (+1) | inf |

IBC candidate summary:

| Set | 8x8 blocks | Raw above matches | Raw left matches | Direct above matches (delta) | Direct left matches (delta) | Selected above copies (delta) | Selected left copies (delta) |
|---|---:|---:|---:|---:|---:|---:|---:|
| screenshot-sweep-444 | 1296 | 311 | 480 | 311 (+231) | 480 (+40) | 0 (+0) | 361 (+3) |
| screenshot-multictu-444 | 1435 | 578 | 796 | 578 (+494) | 796 (+40) | 0 (+0) | 677 (+1) |

### Full Screenshot Sweep

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
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 18.0312 (+0.0000) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 472 (+0) | 1.2292 (+0.0000) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 512 (+0) | 1.0000 (+0.0000) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 15.2250 (+0.0000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 608 (+0) | 0.7917 (+0.0000) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 11.8839 (+0.0000) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 696 (+0) | 0.6797 (+0.0000) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 18.4167 (+0.0000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 7.1042 (+0.0000) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 12.1528 (+0.0000) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 19.0938 (+0.0000) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 16.0000 (+0.0000) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 0.5903 (+0.0000) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 0.5357 (+0.0000) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 15.1823 (+0.0000) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 11.7812 (+0.0000) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1328 (+0) | 2.5938 (+0.0000) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1696 (-32) | 2.2083 (-0.0417) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11088 (-24) | 10.8281 (-0.0235) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 0.5375 (+0.0000) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 14.4375 (+0.0000) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 15.2143 (+0.0000) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 0.4180 (+0.0000) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 18.6000 (+0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 20.6875 (+0.0000) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1616 (-24) | 1.6833 (-0.0250) | inf |
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

### Screenshot Multi-CTU And Partial Crops

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 88520 (+0) | 10.8057 (+0.0000) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 43928 (-32) | 5.3623 (-0.0039) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 10168 (+0) | 0.6206 (+0.0000) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45768 (+0) | 3.7246 (+0.0000) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 101472 (+0) | 8.2578 (+0.0000) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 60568 (+0) | 13.1441 (+0.0000) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 0.3611 (+0.0000) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3000 (+0) | 0.5787 (+0.0000) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 135600 (+0) | 12.4632 (+0.0000) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79792 (+0) | 8.6580 (+0.0000) | inf |
## 2026-06-19 4:2:0 Lossy Residual Baseline

Baseline and current sources:

- Baseline Git SHA: none; this is the first AV2 `yuv420p8` residual baseline.
- Current validated source Git SHA:
  `3b644b32e731840bb1da774312c5a0c70298f040`
- Current mode: AV2 lossy 4:2:0 residual path with 8x8 visible luma leaves,
  colocated 4x4 chroma transform blocks, local neighbor prediction, and strict
  SW/RTL/reference-decoder reconstruction parity.
- Delta columns are intentionally omitted for this first 4:2:0 checkpoint.

Validation result:

- `racehorses-sweep-420`: 64/64 PASS.
- Larger 4:2:0 smoke vectors: 7/7 PASS.
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.
- Finite PSNR is expected: this AV2 4:2:0 path is intentionally lossy.

Aggregate results:

| Set | Cases | Status | SW bits | SW bpp | PSNR |
|---|---:|---|---:|---:|---|
| racehorses-sweep-420 | 64 | PASS | 182464 | 2.1998 | avg 24.08 dB, range 22.47-33.31 dB |
| larger RaceHorses 4:2:0 smoke | 7 | PASS | 139608 | 2.0254 | avg 22.54 dB, range 21.87-22.92 dB |

### RaceHorses 4:2:0 Sweep

| Vector | Status | SW bits | SW bpp | PSNR |
|---|---|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 | 4.7500 | 33.31 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 | 3.5625 | 23.72 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 | 3.3333 | 24.37 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 | 3.2188 | 23.44 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 | 3.0500 | 23.68 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 | 2.6875 | 23.69 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 | 2.7679 | 22.99 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 | 2.7188 | 22.72 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 | 2.6250 | 32.71 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 | 2.9062 | 23.50 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 | 2.3750 | 24.91 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 | 2.3750 | 25.44 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 | 2.4125 | 25.97 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 | 2.3125 | 25.53 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 | 2.3304 | 24.58 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 | 2.2812 | 24.42 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 | 2.7500 | 30.47 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 | 2.5417 | 23.59 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 | 2.2639 | 23.95 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 | 2.1250 | 23.36 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 | 2.2917 | 22.93 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 | 2.2569 | 22.73 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 | 2.2560 | 22.47 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 | 2.3333 | 22.47 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 | 2.3438 | 28.68 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 | 2.3281 | 23.57 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 | 2.0833 | 23.84 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 | 2.1797 | 23.72 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 | 2.3062 | 23.39 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 | 2.1771 | 22.93 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 | 2.1830 | 22.90 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 | 2.2188 | 22.75 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 | 2.3750 | 28.02 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 | 2.3875 | 23.56 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 | 2.0667 | 23.33 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 | 2.1500 | 23.18 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 | 2.1650 | 23.17 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 | 2.3000 | 22.80 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 | 2.1857 | 22.86 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 | 2.1719 | 22.85 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 | 2.5208 | 27.20 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 | 2.3750 | 23.94 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 | 1.9792 | 23.43 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 | 2.0521 | 23.12 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 | 2.1375 | 23.09 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 | 2.1771 | 22.77 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 | 2.1488 | 22.90 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 | 2.1198 | 22.93 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 | 2.3929 | 24.65 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 | 2.3125 | 22.94 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 | 1.9940 | 22.95 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 | 2.0580 | 23.17 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 | 2.0964 | 23.17 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 | 2.2113 | 22.92 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 | 2.1378 | 23.08 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 | 2.1205 | 22.94 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 | 2.3125 | 24.39 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 | 2.1875 | 23.53 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 | 2.0521 | 23.44 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 | 2.0078 | 23.45 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 | 2.0781 | 23.38 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 | 2.1146 | 23.06 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 | 2.1607 | 23.06 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 | 2.1289 | 22.93 |

### Larger RaceHorses 4:2:0 Smoke

| Vector | Status | SW bits | SW bpp | PSNR |
|---|---|---:|---:|---:|
| RaceHorses_136x80_1f_yuv420p8.yuv | PASS | 20608 | 1.8941 | 21.87 |
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 | 2.0732 | 22.76 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 | 2.0947 | 22.36 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 | 1.9419 | 22.66 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 | 2.0728 | 22.81 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 | 2.0729 | 22.40 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 | 2.1960 | 22.92 |
