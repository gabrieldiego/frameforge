# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md).

`scripts/validate.py` reports the FrameForge software bitstream and, when
RTL validation is enabled, the RTL bitstream size. Software and RTL
bitstreams are expected to match exactly for implemented AV2 features. The
AV2 reference path used here is decode-only; these validation runs do not
invoke `avmenc`, `aomenc`, or `vpenc`, and reference-encoder bitrates are
not tracked in this report.

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
