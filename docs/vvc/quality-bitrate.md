# VVC Quality And Bitrate Baselines

This document records validation points for reconstruction quality and encoded
bitrate. Synthesis area/timing belongs in [synthesis.md](synthesis.md); this file is
for VVC codec-output metrics that should move as new coding tools are added.

`scripts/validate.py` prints the following bitrate metrics for every encoded
bitstream:

- `<label>_bytes`: encoded Annex-B stream size in bytes.
- `<label>_bits`: encoded Annex-B stream size in bits.
- `<label>_bits_per_luma_pixel`: encoded bits divided by visible luma pixels
  across all frames.
- `<label>_encoded_to_source_bytes`: encoded bytes divided by the raw input
  bytes consumed for the validation run.

PSNR is reported against the validation input. `inf` means byte-exact
reconstruction for the compared stream.

Large local `screenshot*.png` captures are useful screen-content stress
vectors for the Rust encoder and VTM decode path. Keep them out of public
manifests unless they are intentionally added as small derived crops.

The validation scripts intentionally support PNG still images only here. Lossy
screen recordings are not used as source vectors because codec noise would make
lossless screen-content checks ambiguous. A PNG always implies 4:4:4 encoding:
RGB is preserved as planar GBR components carried through the current
`yuv444p8` path.

```bash
make validate INPUT=screenshot_640x360.png INPUT_FORMAT=png \
  RECON_FORMAT=png VALIDATE_SW_ONLY=1 VALIDATE_SYNTH=0
```

Small local screenshot crops can also be listed under
`verification/test_vector_sets/local/` and run as a normal validation set. For
example, this workspace uses:

```bash
make validate-set VALIDATION_SET=screenshot-smoke-444 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

For a full 8x8 through 64x64 local 4:4:4 geometry sweep, use a deterministic
set of pseudo-random crop positions from the same screenshot:

```bash
make validate-set VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

The local manifest records the crop equation so the same positions can be
recreated later from a 640x360 PNG source.

Multi-CTU screenshot crops are kept in a separate local set so they can be run
only when the longer hardware simulation is useful:

```bash
make validate-set VALIDATION_SET=screenshot-multictu-444 \
  RTL_MAX_VISIBLE_WIDTH=192 RTL_MAX_VISIBLE_HEIGHT=192 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

Do not add these full-size screenshots to cocotb RTL regressions; they are too
large for the current simulation loop and should be covered by smaller crops or
generated RTL smoke vectors instead.

Generated screenshot crops remain raw planar files with a `.yuv` suffix. Use
`ffplay -pixel_format gbrp` for these RGB-backed vectors, not `yuv444p`.

## 2026-06-11 IBC 8x8 Hash Smoke

First post-IBC quality/bitrate baseline. The vector is a 16x8 4:4:4 frame whose
second 8x8 block repeats the first block exactly, forcing the new CTU-local
32-bit-hash IBC path after one palette-coded block.

Command:

```bash
python3 scripts/validate.py /tmp/ff_ibc_16x8_yuv444p8.yuv \
  --width 16 --height 8 --frames 1 --format yuv444p8 \
  --max-width 64 --max-height 64 --sw-only --skip-synth
```

Measured result:

```text
software_bitstream_bytes: 299
software_bitstream_bits: 2392
software_bitstream_bits_per_luma_pixel: 18.6875
software_bitstream_encoded_to_source_bytes: 0.7786
software_internal_recon_psnr_vs_input_db: inf
vtm_recon_from_software_bitstream_psnr_vs_input_db: inf
```

Checks:

- Software internal reconstruction matched the input byte-for-byte.
- VTM decoded reconstruction matched the software reconstruction byte-for-byte.
- VTM reconstruction contained decoder-visible chroma.

## 2026-06-11 IBC Screenshot Baselines

The first larger 4:4:4 screen-content baseline uses local PNG screenshots. PNG
inputs are decoded as RGB and carried through the current planar `yuv444p8`
path as GBR component planes. The reconstruction checks are therefore exact
GBR byte comparisons, not visual YCbCr comparisons.

Local RTL crop sets:

```bash
make validate-set VALIDATION_SET=screenshot-smoke-444 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0

make validate-set VALIDATION_SET=screenshot-multictu-444 \
  RTL_MAX_VISIBLE_WIDTH=192 RTL_MAX_VISIBLE_HEIGHT=192 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

Measured RTL/VTM result across the three smoke crops and five multi-CTU crops:

```text
vectors_passed: 8
software_bitstream_bytes_min: 781
software_bitstream_bytes_max: 6159
software_bitstream_bits_per_luma_pixel_min: 0.3813
software_bitstream_bits_per_luma_pixel_max: 8.4707
software_internal_recon_psnr_vs_input_db: inf for all 8 vectors
vtm_recon_from_software_bitstream_psnr_vs_input_db: inf for all 8 vectors
```

The direct 64x64 PNG smoke crop used for the first software/VTM check measured
4337 bytes, 8.4707 bits per luma pixel, and `inf` PSNR.

Full screenshot software/VTM validation:

```bash
make validate INPUT=screenshot_640x360.png INPUT_FORMAT=png \
  RECON_FORMAT=png VALIDATE_SW_ONLY=1 VALIDATE_SYNTH=0
```

Measured result:

```text
input_raw_gbr_bytes: 691200
software_bitstream_bytes: 120243
software_bitstream_bits: 961944
software_bitstream_bits_per_luma_pixel: 4.1751
software_bitstream_encoded_to_source_bytes: 0.1740
software_internal_recon_psnr_vs_input_db: inf
vtm_recon_from_software_bitstream_psnr_vs_input_db: inf
png_view_sha256: 470075aba959ef8883221d187896b7d1bb4db67f857e5ccef0cabb217303cdea
```

The 2560x1440 screenshot was also tried as a software-only stress vector, but
the current parameter-set path exceeded VTM's explicit tile-column limit. Keep
640x360 as the documented large-screenshot baseline until the PPS tiling model
is generalized.

## 2026-06-11 RaceHorses 4:2:0 Baselines

IBC and palette changes must not regress the current lossy 4:2:0 residual path.
The RaceHorses crop sweep remains the chroma residual guard for that path:

```bash
make validate-set VALIDATION_SET=racehorses-sweep-420 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

Measured result:

```text
vectors_passed: 64
software_bitstream_bytes_min: 71
software_bitstream_bytes_max: 540
software_bitstream_bits_per_luma_pixel_min: 1.0547
software_bitstream_bits_per_luma_pixel_max: 8.8750
software_internal_recon_psnr_vs_input_db_min: 19.43
software_internal_recon_psnr_vs_input_db_max: 29.32
```

The 64x64 RaceHorses crop guard measured 540 bytes, 1.0547 bits per luma pixel,
and 22.55 dB PSNR.

The scaled 136x80 one-frame RaceHorses vector is the larger routine 4:2:0 guard:

```bash
make validate \
  INPUT=verification/generated/test_vectors/RaceHorses_136x80_1f_yuv420p8.yuv \
  RTL_MAX_VISIBLE_WIDTH=136 RTL_MAX_VISIBLE_HEIGHT=80 \
  VALIDATE_SYNTH=0
```

Measured result:

```text
ctus_emitted: 6
software_bitstream_bytes: 1436
software_bitstream_bits: 11488
software_bitstream_bits_per_luma_pixel: 1.0559
software_bitstream_encoded_to_source_bytes: 0.0880
software_internal_recon_psnr_vs_input_db: 22.17
vtm_recon_from_software_bitstream_psnr_vs_input_db: 22.17
```

## 2026-06-11 4:4:4 Transform-Skip Residual Baselines

The first transform-skip residual subset keeps 4:4:4 reconstruction lossless
while allowing a runtime left-neighbour IBC CU to code a small residual instead
of falling back to palette for the whole 8x8 CU. Exact-hash IBC is disabled in
the default encoder/synthesis path until its candidate search is updated to use
the final runtime BVP/HMVP state.

Main validation commands:

```bash
make validate-set VALIDATION_SET=transform-skip-444 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0

make validate-set VALIDATION_SET=screenshot-multictu-444 \
  RTL_MAX_VISIBLE_WIDTH=192 RTL_MAX_VISIBLE_HEIGHT=192 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0

make validate-set VALIDATION_SET=racehorses-sweep-420 \
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

Measured result for the 64x64 transform-skip 4:4:4 vector:

```text
software_bitstream_bytes: 568
software_bitstream_bits: 4544
software_bitstream_bits_per_luma_pixel: 1.1094
software_bitstream_encoded_to_source_bytes: 0.0462
software_internal_recon_psnr_vs_input_db: inf
rtl_internal_recon_psnr_vs_input_db: inf
vtm_recon_from_decodable_bitstream_psnr_vs_input_db: inf
```

Measured result for the horizontal 192x64 screenshot multi-CTU guard:

```text
software_bitstream_bytes: 4681
software_bitstream_bits: 37448
software_bitstream_bits_per_luma_pixel: 3.0475
software_bitstream_encoded_to_source_bytes: 0.1270
software_internal_recon_psnr_vs_input_db: inf
rtl_internal_recon_psnr_vs_input_db: inf
vtm_recon_from_decodable_bitstream_psnr_vs_input_db: inf
```

Measured result for the vertical 64x192 screenshot multi-CTU guard:

```text
software_bitstream_bytes: 6593
software_bitstream_bits: 52744
software_bitstream_bits_per_luma_pixel: 4.2923
software_bitstream_encoded_to_source_bytes: 0.1788
software_internal_recon_psnr_vs_input_db: inf
rtl_internal_recon_psnr_vs_input_db: inf
vtm_recon_from_decodable_bitstream_psnr_vs_input_db: inf
```

The full 640x360 screenshot software/VTM validation remains lossless with the
default exact-hash IBC gate disabled:

```text
input_raw_gbr_bytes: 691200
software_bitstream_bytes: 127179
software_bitstream_bits: 1017432
software_bitstream_bits_per_luma_pixel: 4.4159
software_bitstream_encoded_to_source_bytes: 0.1840
software_internal_recon_psnr_vs_input_db: inf
vtm_recon_from_software_bitstream_psnr_vs_input_db: inf
```

The 4:2:0 RaceHorses 64x64 crop guard remained unchanged from the previous
residual baseline at 540 bytes, 1.0547 bits per luma pixel, and 22.55 dB PSNR.

## 2026-06-11 4:4:4 Horizontal BDPCM Baseline

The first BDPCM subset adds horizontal BDPCM for 8x8 4:4:4 CUs whose residuals
fit in the top-left 4x4 coefficient group. Reconstruction remains lossless
against the source, RTL, and VTM.

Main validation commands:

```bash
make validate INPUT=verification/generated/test_vectors/bdpcm_horizontal_64x64_1f_yuv444p8.yuv \
  VALIDATE_SYNTH=0

make hardware-regression HARDWARE_REGRESSION_EXTRA_SET=bdpcm-444 \
  HARDWARE_REGRESSION_SYNTH=0
```

Measured result for the 64x64 BDPCM 4:4:4 guard:

```text
software_bitstream_bytes: 1593
software_bitstream_bits: 12744
software_bitstream_bits_per_luma_pixel: 3.1113
software_bitstream_encoded_to_source_bytes: 0.1296
software_internal_recon_psnr_vs_input_db: inf
rtl_internal_recon_psnr_vs_input_db: inf
vtm_recon_from_decodable_bitstream_psnr_vs_input_db: inf
```

The public hardware regression passed 192 SW/RTL/VTM geometry cases: 64 4:2:0
black-frame sweep vectors, 64 4:4:4 screen-block sweep vectors, and 64 4:4:4
BDPCM-horizontal sweep vectors.
