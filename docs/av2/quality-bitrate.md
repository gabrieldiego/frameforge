# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md).

`scripts/validate.py` reports the FrameForge software bitstream, AV2 reference
encoder bitstream, and RTL bitstream sizes. Software and RTL bitstreams are
expected to match exactly for implemented AV2 features. The AV2 reference
encoder bitstream is an external comparison point and is not expected to match
FrameForge byte-for-byte.

## 2026-06-16 Left-Hash IBC Delta

Baseline and current sources:

- Baseline Git SHA: `661040bdf972b384a1f62a19dc39757be8381219`
- Current validated source Git SHA: `d04435fd29ec73e18181c54c2452b869add56b87`
- Baseline mode: AV2 software/reference validation before IBC, RTL and synthesis disabled.
- Current mode: AV2 software/RTL/reference validation with exact SW/RTL bitstream checks enabled.
- Delta columns compare the current FrameForge software bitstream against the baseline FrameForge software bitstream for the same vector.

Validation commands:

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Results:

```text
screenshot-sweep-444:    64/64 PASS
screenshot-multictu-444: 10/10 PASS
```

### Full Screenshot Sweep

Aggregate SW bits: `770752` (-440).
Aggregate SW bpp: `9.2924` (-0.0053).

| Vector | Status | SW bits (delta) | SW bpp (delta) | REF bits | REF bpp | PSNR |
|---|---|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (0) | 5.3750 (0.0000) | 280 | 4.3750 | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (0) | 15.5000 (0.0000) | 1800 | 14.0625 | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 392 (-24) | 2.0417 (-0.1250) | 296 | 1.5417 | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 712 (-24) | 2.7812 (-0.0938) | 472 | 1.8438 | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 456 (-24) | 1.4250 (-0.0750) | 296 | 0.9250 | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 496 (-24) | 1.2917 (-0.0625) | 304 | 0.7917 | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (0) | 15.3214 (0.0000) | 5080 | 11.3393 | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (0) | 13.3125 (0.0000) | 5112 | 9.9844 | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (0) | 14.2500 (0.0000) | 1528 | 11.9375 | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (0) | 18.0312 (0.0000) | 2800 | 10.9375 | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (-24) | 1.3125 (-0.0625) | 304 | 0.7917 | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 576 (-16) | 1.1250 (-0.0312) | 304 | 0.5938 | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (0) | 15.2250 (0.0000) | 6184 | 9.6625 | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 720 (-24) | 0.9375 (-0.0313) | 312 | 0.4062 | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (0) | 11.8839 (0.0000) | 7160 | 7.9911 | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 872 (-16) | 0.8516 (-0.0156) | 312 | 0.3047 | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (0) | 18.4167 (0.0000) | 2504 | 13.0417 | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (0) | 7.1042 (0.0000) | 2144 | 5.5833 | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (0) | 12.1528 (0.0000) | 5064 | 8.7917 | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (0) | 19.0938 (0.0000) | 9264 | 12.0625 | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (0) | 16.0000 (0.0000) | 10160 | 10.5833 | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 944 (-16) | 0.8194 (-0.0139) | 320 | 0.2778 | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1048 (-16) | 0.7798 (-0.0119) | 320 | 0.2381 | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23312 (0) | 15.1771 (0.0000) | 12144 | 7.9062 | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (0) | 11.7812 (0.0000) | 1584 | 6.1875 | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (0) | 2.7500 (0.0000) | 1000 | 1.9531 | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1808 (-16) | 2.3542 (-0.0208) | 1056 | 1.3750 | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11152 (-24) | 10.8906 (-0.0235) | 5272 | 5.1484 | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1008 (-24) | 0.7875 (-0.0188) | 312 | 0.2437 | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (0) | 14.4375 (0.0000) | 11360 | 7.3958 | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (0) | 15.2143 (0.0000) | 14992 | 8.3661 | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1456 (-16) | 0.7109 (-0.0079) | 320 | 0.1562 | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (0) | 18.6000 (0.0000) | 3544 | 11.0750 | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (0) | 20.6875 (0.0000) | 7128 | 11.1375 | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1792 (0) | 1.8667 (0.0000) | 880 | 0.9167 | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (0) | 17.0562 (0.0000) | 12592 | 9.8375 | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22480 (0) | 14.0500 (0.0000) | 12448 | 7.7800 | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (0) | 1.1208 (0.0000) | 944 | 0.4917 | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20944 (0) | 9.3500 (0.0000) | 11928 | 5.3250 | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2016 (-16) | 0.7875 (-0.0062) | 400 | 0.1562 | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (0) | 1.7292 (0.0000) | 400 | 1.0417 | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (0) | 20.6458 (0.0000) | 9800 | 12.7604 | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15152 (-32) | 13.1528 (-0.0278) | 8104 | 7.0347 | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15832 (0) | 10.3073 (0.0000) | 8080 | 5.2604 | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30400 (0) | 15.8333 (0.0000) | 17424 | 9.0750 | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1600 (-16) | 0.6944 (-0.0070) | 304 | 0.1319 | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13560 (0) | 5.0446 (0.0000) | 6264 | 2.3304 | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2304 (-16) | 0.7500 (-0.0052) | 400 | 0.1302 | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (0) | 15.5179 (0.0000) | 4168 | 9.3036 | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9864 (0) | 11.0089 (0.0000) | 6392 | 7.1339 | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 12088 (0) | 8.9940 (0.0000) | 6656 | 4.9524 | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 19168 (0) | 10.6964 (0.0000) | 10360 | 5.7812 | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37216 (0) | 16.6143 (0.0000) | 20000 | 8.9286 | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27016 (0) | 10.0506 (0.0000) | 13744 | 5.1131 | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57752 (0) | 18.4158 (0.0000) | 28728 | 9.1607 | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 29264 (0) | 8.1652 (0.0000) | 15344 | 4.2812 | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (0) | 10.4375 (0.0000) | 2752 | 5.3750 | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (0) | 15.0859 (0.0000) | 10536 | 10.2891 | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13720 (-24) | 8.9323 (-0.0156) | 7816 | 5.0885 | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32104 (-32) | 15.6758 (-0.0156) | 16736 | 8.1719 | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2840 (-16) | 1.1094 (-0.0062) | 1232 | 0.4813 | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50256 (0) | 16.3594 (0.0000) | 27160 | 8.8411 | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3840 (0) | 1.0714 (0.0000) | 1488 | 0.4152 | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76656 (0) | 18.7148 (0.0000) | 36136 | 8.8223 | inf |

### Screenshot Multi-CTU And Partial Crops

Aggregate SW bits: `591696` (-232).
Aggregate SW bpp: `6.4426` (-0.0025).

| Vector | Status | SW bits (delta) | SW bpp (delta) | REF bits | REF bpp | PSNR |
|---|---|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 89888 (0) | 10.9727 (0.0000) | 45480 | 5.5518 | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 46160 (-8) | 5.6348 (-0.0009) | 20880 | 2.5488 | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 16288 (-72) | 0.9941 (-0.0044) | 4312 | 0.2632 | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 48632 (-56) | 3.9577 (-0.0045) | 23336 | 1.8991 | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 104016 (-32) | 8.4648 (-0.0026) | 54280 | 4.4173 | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 60992 (0) | 13.2361 (0.0000) | 29424 | 6.3854 | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3080 (-16) | 0.6684 (-0.0035) | 320 | 0.0694 | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4472 (-32) | 0.8627 (-0.0061) | 536 | 0.1034 | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136880 (0) | 12.5809 (0.0000) | 70776 | 6.5051 | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 81288 (-16) | 8.8203 (-0.0017) | 38904 | 4.2214 | inf |

All listed vectors matched SW/RTL bitstream checksums and SW/RTL/reference reconstruction checksums. The `inf` PSNR entries indicate lossless reconstruction against the integer-valued source vectors.
