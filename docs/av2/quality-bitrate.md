# AV2 Quality And Bitrate Baselines

This file records AV2-specific quality and bitrate checkpoints. Synthesis
area/timing belongs in [synthesis.md](synthesis.md).

`scripts/validate.py` reports the FrameForge software bitstream, AV2 reference
encoder bitstream, and RTL bitstream sizes. Software and RTL bitstreams are
expected to match exactly for implemented AV2 features. The AV2 reference
encoder bitstream is an external comparison point and is not expected to match
FrameForge byte-for-byte.

## 2026-06-14 Luma Palette 4:4:4

Current subset:

- 8-bit `yuv444p8` input.
- Visible dimensions from 8x8 through 64x64 in 8-pixel steps.
- One visible 8x8 block packet at the RTL interface: 64 Y samples, then 64 U
  samples, then 64 V samples.
- Luma palette only, up to eight colors per 8x8 block. Additional luma values
  map to the nearest stored color.
- Chroma is not yet coded by FrameForge AV2. Arbitrary color screenshots are
  therefore expected to be lossy even when SW, RTL, and AVM decode checksums
  agree.

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

Local screenshot crop geometry sweep:

```sh
make test-vectors TEST_VECTOR_SET=screenshot-sweep-444
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

The local manifest `verification/test_vector_sets/local/screenshot-sweep-444.csv`
uses deterministic pseudo-random crops from `screenshot_640x360.png`.

Measured aggregate across all 64 geometries:

```text
software_bitstream_bits_per_luma_pixel_min: 4.3993
software_bitstream_bits_per_luma_pixel_max: 7.2604
software_internal_recon_psnr_vs_input_db_min: 10.20
software_internal_recon_psnr_vs_input_db_max: 24.32
```

Measured 64x64 screenshot crop:

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
software reconstruction. The AVM reference encode/decode of the original input
remained lossless for these still images, as expected for the external reference
path.
