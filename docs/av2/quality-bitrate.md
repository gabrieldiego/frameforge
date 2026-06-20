# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md).

`scripts/validate.py` reports the FrameForge software bitstream and, when
RTL validation is enabled, the RTL bitstream size. Software and RTL
bitstreams are expected to match exactly for implemented AV2 features. The
AV2 reference path used here is decode-only; these validation runs do not
invoke `avmenc`, `aomenc`, or `vpenc`, and reference-encoder bitrates are
not tracked in this report.

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

## 2026-06-16 Luma Intra + IntraBC Syntax Fix Delta

Baseline and current sources:

- Baseline Git SHA: `d04435fd29ec73e18181c54c2452b869add56b87`
- Current validated source Git SHA: `17ff78397917f320a13809216e957826acd9cbc7`
- Baseline mode: previously documented AV2 left-hash IBC checkpoint.
- Current mode: AV2 software/RTL/reference-decoder validation after fixing
  frame-level `allow_intrabc` and per-leaf `use_intrabc` syntax parity.
- Delta columns compare the current FrameForge software bitstream against
  the baseline FrameForge software bitstream for the same vector.

Validation commands:

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Results:

```text
screenshot-sweep-444:    64/64 PASS
screenshot-multictu-444: 10/10 PASS
```

### Full Screenshot Sweep

Aggregate SW bits: `770848` (+96).
Aggregate SW bpp: `9.2936` (+0.0012).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (0) | 5.3750 (0.0000) | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (0) | 15.5000 (0.0000) | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 392 (0) | 2.0417 (0.0000) | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 712 (0) | 2.7812 (0.0000) | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 456 (0) | 1.4250 (0.0000) | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 496 (0) | 1.2917 (0.0000) | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (0) | 15.3214 (0.0000) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (0) | 13.3125 (0.0000) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (0) | 14.2500 (0.0000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (0) | 18.0312 (0.0000) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (0) | 1.3125 (0.0000) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 576 (0) | 1.1250 (0.0000) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (0) | 15.2250 (0.0000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 720 (0) | 0.9375 (0.0000) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (0) | 11.8839 (0.0000) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 872 (0) | 0.8516 (0.0000) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (0) | 18.4167 (0.0000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (0) | 7.1042 (0.0000) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (0) | 12.1528 (0.0000) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (0) | 19.0938 (0.0000) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (0) | 16.0000 (0.0000) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 944 (0) | 0.8194 (0.0000) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1048 (0) | 0.7798 (0.0000) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+8) | 15.1823 (+0.0052) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (0) | 11.7812 (0.0000) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (0) | 2.7500 (0.0000) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1808 (0) | 2.3542 (0.0000) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11152 (0) | 10.8906 (0.0000) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1008 (0) | 0.7875 (0.0000) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (0) | 14.4375 (0.0000) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (0) | 15.2143 (0.0000) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1456 (0) | 0.7109 (0.0000) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (0) | 18.6000 (0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (0) | 20.6875 (0.0000) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1792 (0) | 1.8667 (0.0000) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (0) | 17.0562 (0.0000) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22480 (0) | 14.0500 (0.0000) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (0) | 1.1208 (0.0000) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20944 (0) | 9.3500 (0.0000) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2016 (0) | 0.7875 (0.0000) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (0) | 1.7292 (0.0000) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (0) | 20.6458 (0.0000) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15152 (0) | 13.1528 (0.0000) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15832 (0) | 10.3073 (0.0000) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30400 (0) | 15.8333 (0.0000) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1600 (0) | 0.6944 (0.0000) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13560 (0) | 5.0446 (0.0000) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2304 (0) | 0.7500 (0.0000) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (0) | 15.5179 (0.0000) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9864 (0) | 11.0089 (0.0000) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 12088 (0) | 8.9940 (0.0000) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 19168 (0) | 10.6964 (0.0000) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37216 (0) | 16.6143 (0.0000) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27016 (0) | 10.0506 (0.0000) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+8) | 18.4184 (+0.0026) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 29264 (0) | 8.1652 (0.0000) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (0) | 10.4375 (0.0000) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (0) | 15.0859 (0.0000) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13744 (+24) | 8.9479 (+0.0156) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32136 (+32) | 15.6914 (+0.0156) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2856 (+16) | 1.1156 (+0.0063) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50264 (+8) | 16.3620 (+0.0026) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3840 (0) | 1.0714 (0.0000) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76656 (0) | 18.7148 (0.0000) | inf |

### Screenshot Multi-CTU And Partial Crops

Aggregate SW bits: `592008` (+312).
Aggregate SW bpp: `6.4461` (+0.0034).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 89904 (+16) | 10.9746 (+0.0020) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 46184 (+24) | 5.6377 (+0.0029) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 16384 (+96) | 1.0000 (+0.0059) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 48696 (+64) | 3.9629 (+0.0052) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 104056 (+40) | 8.4681 (+0.0033) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 61016 (+24) | 13.2413 (+0.0052) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3096 (+16) | 0.6719 (+0.0035) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4488 (+16) | 0.8657 (+0.0031) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136880 (0) | 12.5809 (0.0000) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 81304 (+16) | 8.8220 (+0.0017) | inf |

All listed vectors matched SW/RTL bitstream checksums and SW/RTL/reference-decoder reconstruction checksums. The `inf` PSNR entries indicate lossless reconstruction against the integer-valued source vectors.
