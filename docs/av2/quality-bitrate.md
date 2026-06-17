# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md).

`scripts/validate.py` reports the FrameForge software bitstream, AV2 reference
encoder bitstream, and RTL bitstream sizes. Software and RTL bitstreams are
expected to match exactly for implemented AV2 features. The AV2 reference
encoder bitstream is an external comparison point and is not expected to match
FrameForge byte-for-byte.

## 2026-06-16 Screenshot SW-Only Baseline

Baseline before adding AV2 IBC. This pass intentionally used software/reference
validation only, with RTL and synthesis disabled. Stop-on-failure was left
disabled so every vector remains visible in the report.

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SW_ONLY=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SW_ONLY=1 \
  VALIDATION_WITH_SYNTH=0
```

Results:

```text
screenshot-sweep-444:    64/64 PASS
screenshot-multictu-444: 10/10 PASS
```

### Full Screenshot Sweep

| Vector | Status | SW bits | SW bpp | REF bits | REF bpp |
|---|---|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 | 5.3750 | 280 | 4.3750 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 | 15.5000 | 1800 | 14.0625 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 | 2.1667 | 296 | 1.5417 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 | 2.8750 | 472 | 1.8438 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 | 1.5000 | 296 | 0.9250 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 | 1.3542 | 304 | 0.7917 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 | 15.3214 | 5080 | 11.3393 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 | 13.3125 | 5112 | 9.9844 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 | 14.2500 | 1528 | 11.9375 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 | 18.0312 | 2800 | 10.9375 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 528 | 1.3750 | 304 | 0.7917 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 592 | 1.1562 | 304 | 0.5938 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 | 15.2250 | 6184 | 9.6625 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 744 | 0.9688 | 312 | 0.4062 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 | 11.8839 | 7160 | 7.9911 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 888 | 0.8672 | 312 | 0.3047 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 | 18.4167 | 2504 | 13.0417 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 | 7.1042 | 2144 | 5.5833 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 | 12.1528 | 5064 | 8.7917 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 | 19.0938 | 9264 | 12.0625 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 | 16.0000 | 10160 | 10.5833 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 960 | 0.8333 | 320 | 0.2778 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1064 | 0.7917 | 320 | 0.2381 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23312 | 15.1771 | 12144 | 7.9062 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 | 11.7812 | 1584 | 6.1875 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 | 2.7500 | 1000 | 1.9531 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1824 | 2.3750 | 1056 | 1.3750 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11176 | 10.9141 | 5272 | 5.1484 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1032 | 0.8063 | 312 | 0.2437 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 | 14.4375 | 11360 | 7.3958 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 | 15.2143 | 14992 | 8.3661 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1472 | 0.7188 | 320 | 0.1562 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 | 18.6000 | 3544 | 11.0750 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 | 20.6875 | 7128 | 11.1375 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1792 | 1.8667 | 880 | 0.9167 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 | 17.0562 | 12592 | 9.8375 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22480 | 14.0500 | 12448 | 7.7800 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 | 1.1208 | 944 | 0.4917 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20944 | 9.3500 | 11928 | 5.3250 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2032 | 0.7937 | 400 | 0.1562 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 | 1.7292 | 400 | 1.0417 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 | 20.6458 | 9800 | 12.7604 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15184 | 13.1806 | 8104 | 7.0347 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15832 | 10.3073 | 8080 | 5.2604 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30400 | 15.8333 | 17424 | 9.0750 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1616 | 0.7014 | 304 | 0.1319 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13560 | 5.0446 | 6264 | 2.3304 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2320 | 0.7552 | 400 | 0.1302 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 | 15.5179 | 4168 | 9.3036 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9864 | 11.0089 | 6392 | 7.1339 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 12088 | 8.9940 | 6656 | 4.9524 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 19168 | 10.6964 | 10360 | 5.7812 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37216 | 16.6143 | 20000 | 8.9286 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27016 | 10.0506 | 13744 | 5.1131 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57752 | 18.4158 | 28728 | 9.1607 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 29264 | 8.1652 | 15344 | 4.2812 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 | 10.4375 | 2752 | 5.3750 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 | 15.0859 | 10536 | 10.2891 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13744 | 8.9479 | 7816 | 5.0885 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32136 | 15.6914 | 16736 | 8.1719 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2856 | 1.1156 | 1232 | 0.4813 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50256 | 16.3594 | 27160 | 8.8411 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3840 | 1.0714 | 1488 | 0.4152 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76656 | 18.7148 | 36136 | 8.8223 |

### Screenshot Multi-CTU And Partial Crops

| Vector | Status | SW bits | SW bpp | REF bits | REF bpp |
|---|---|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 89888 | 10.9727 | 45480 | 5.5518 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 46168 | 5.6357 | 20880 | 2.5488 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 16360 | 0.9985 | 4312 | 0.2632 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 48688 | 3.9622 | 23336 | 1.8991 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 104048 | 8.4674 | 54280 | 4.4173 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 60992 | 13.2361 | 29424 | 6.3854 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3096 | 0.6719 | 320 | 0.0694 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4504 | 0.8688 | 536 | 0.1034 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136880 | 12.5809 | 70776 | 6.5051 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 81304 | 8.8220 | 38904 | 4.2214 |

## 2026-06-15 Luma Palette + Lossless Residual 4:4:4

Current subset:

- 8-bit `yuv444p8` input.
- Visible dimensions from 8x8 through 64x64 in 8-pixel steps.
- One visible 8x8 block packet at the RTL interface: 64 Y samples, then 64 U
  samples, then 64 V samples.
- Luma uses AV2 palette syntax as a predictor with up to eight colors per 8x8
  block, followed by lossless luma residual coefficient syntax.
- Chroma uses horizontal BDPCM and lossless `TX_4X4` coefficient coding because
  AV2 palette syntax is luma-only.

Validation:

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=palette-escape-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Measured aggregate across all 64 generated high-color geometries:

```text
validation_cases: 64/64 PASS
software_bitstream_bits_per_luma_pixel_min: 38.8482
software_bitstream_bits_per_luma_pixel_max: 42.1250
software_internal_recon_psnr_vs_input_db: inf for every case
rtl_internal_recon_psnr_vs_input_db: inf for every case
```

Representative 64x64 generated vector:

```text
input_sha256:               07cde1248334643f56a82bc0e6d04001c54d334e180c0a4fe7e72f547867aefe
software_bitstream_sha256:  0451422f362ff26556a47ef4e825018b00cc3fa371c8a87317e3d3b6a2ea7805
rtl_bitstream_sha256:       0451422f362ff26556a47ef4e825018b00cc3fa371c8a87317e3d3b6a2ea7805
software_bitstream_bytes:   19937
software_bitstream_bits_per_luma_pixel: 38.9395
software_bitstream_encoded_to_source_bytes: 1.6225
software_internal_recon_psnr_vs_input_db: inf
rtl_internal_recon_psnr_vs_input_db: inf
```

The AVM reference decode of the FrameForge software bitstream, the AVM
reference encoder reconstruction, the FrameForge software reconstruction, and
the RTL reconstruction all matched the input checksum for every case in this
set.

## 2026-06-14 Luma Palette + Chroma BDPCM 4:4:4

Current subset:

- 8-bit `yuv444p8` input.
- Visible dimensions from 8x8 through 64x64 in 8-pixel steps.
- One visible 8x8 block packet at the RTL interface: 64 Y samples, then 64 U
  samples, then 64 V samples.
- Luma palette only, up to eight colors per 8x8 block.
- Chroma uses horizontal BDPCM and lossless `TX_4X4` coefficient coding because
  AV2 palette syntax is luma-only.

Validation:

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=bdpcm-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Measured aggregate across all 64 generated horizontal-BDPCM geometries:

```text
validation_cases: 64/64 PASS
software_bitstream_bits_per_luma_pixel_min: 3.2812
software_bitstream_bits_per_luma_pixel_max: 6.3750
software_internal_recon_psnr_vs_input_db: inf for every case
rtl_internal_recon_psnr_vs_input_db: inf for every case
```

Representative 64x64 generated vector:

```text
input_sha256:               752b014b3ea1c4835f730304d9b2be97966a267de78a5c1779708bc83dbdb8d3
software_bitstream_sha256:  eb2dd99ef8e27eb105468f6b2ee5fb26d68c64f42b954c395fcd2265fb3f316f
rtl_bitstream_sha256:       eb2dd99ef8e27eb105468f6b2ee5fb26d68c64f42b954c395fcd2265fb3f316f
software_bitstream_bytes:   1700
software_bitstream_bits_per_luma_pixel: 3.3203
software_internal_recon_psnr_vs_input_db: inf
rtl_internal_recon_psnr_vs_input_db: inf
```

The AVM reference decode of the FrameForge software bitstream, the AVM
reference encoder reconstruction, the FrameForge software reconstruction, and
the RTL reconstruction all matched the input checksum for every case in this
set.

## 2026-06-14 Luma Palette 4:4:4 Pre-BDPCM

Historical subset before chroma BDPCM:

- 8-bit `yuv444p8` input.
- Visible dimensions from 8x8 through 64x64 in 8-pixel steps.
- One visible 8x8 block packet at the RTL interface: 64 Y samples, then 64 U
  samples, then 64 V samples.
- Luma palette only, up to eight colors per 8x8 block. Additional luma values
  map to the nearest stored color.
- AVM currently exposes palette coding only for `PLANE_TYPE_Y`; chroma palette
  is not a valid reference-compatible path. Chroma is not yet coded by
  FrameForge AV2, so arbitrary color screenshots are expected to be lossy even
  when SW, RTL, and AVM decode checksums agree.

Lossless luma-bars smoke:

```sh
make validate CODEC=av2 \
  INPUT=verification/generated/test_vectors/av2_luma_palette_bars_64x64_1f_yuv444p8.yuv \
  WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv444p8 VALIDATE_SYNTH=0
```

Measured result:

```text
software_bitstream_sha256: 01b1ad518fdae2bcd1328af9c567b37937fe87b17ba674b20e0c3fff0f1d3533
rtl_bitstream_sha256:      01b1ad518fdae2bcd1328af9c567b37937fe87b17ba674b20e0c3fff0f1d3533
software_bitstream_bytes:  2248
software_bitstream_bits_per_luma_pixel: 4.3906
software_internal_recon_psnr_vs_input_db: inf
rtl_internal_recon_psnr_vs_input_db: inf
```

Local screenshot crop geometry sweep target:

```sh
make test-vectors TEST_VECTOR_SET=screenshot-sweep-444
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

The local manifest `verification/test_vector_sets/local/screenshot-sweep-444.csv`
uses deterministic pseudo-random crops from `screenshot_640x360.png`. These
vectors are not counted as passing until chroma is coded losslessly; the AV2
validation gate now fails if software, REF-decoded software, REF encode/decode,
and input reconstruction checksums do not all match.

Historical lossy luma-only aggregate across all 64 geometries:

```text
software_bitstream_bits_per_luma_pixel_min: 4.3993
software_bitstream_bits_per_luma_pixel_max: 7.2604
software_internal_recon_psnr_vs_input_db_min: 10.20
software_internal_recon_psnr_vs_input_db_max: 24.32
```

Historical lossy 64x64 screenshot crop:

```text
software_bitstream_sha256: 158769ecd0bebe166cee5d8044e6ea24ce05c5e1c5a03cbdad5828ba28c3a6d1
rtl_bitstream_sha256:      158769ecd0bebe166cee5d8044e6ea24ce05c5a03cbdad5828ba28c3a6d1
software_bitstream_bytes:  3284
software_bitstream_bits_per_luma_pixel: 6.4141
software_internal_recon_psnr_vs_input_db: 12.06
rtl_internal_recon_psnr_vs_input_db: 12.06
```

The AVM reference decode of the FrameForge software bitstream matched the
FrameForge software reconstruction on each crop, and RTL reconstruction matched
software reconstruction. Because chroma was not yet coded, these measurements
remain a debugging baseline rather than a passing lossless validation baseline.
