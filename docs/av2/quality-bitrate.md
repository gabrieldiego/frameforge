# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md).

`scripts/validate.py` reports the FrameForge software bitstream, AV2 reference
encoder bitstream, and RTL bitstream sizes. Software and RTL bitstreams are
expected to match exactly for implemented AV2 features. The AV2 reference
encoder bitstream is an external comparison point and is not expected to match
FrameForge byte-for-byte.

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
