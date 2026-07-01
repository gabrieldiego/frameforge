# Local Assets And Test Vector Manifests

FrameForge uses deterministic generated vectors plus optional local media
sources. This page documents what belongs in git and what should remain local
to a developer machine.

## Portable Manifests

Committed manifests live under:

```text
verification/test_vector_sets/
```

They must be portable. Do not commit absolute workstation paths, private media
paths, generated outputs, or machine-specific source filenames unless the source
asset itself is committed and portable.

List available manifests:

```sh
make test-vector-sets
```

Generate one set:

```sh
make test-vectors TEST_VECTOR_SET=smoke
```

## Local Manifests

Machine-local manifests live under:

```text
verification/test_vector_sets/local/
```

That directory is ignored by git. Use it for:

- RaceHorses crops from a local YUV sequence.
- PNG screenshot crop sweeps.
- Multi-CTU local source crops.
- Any source path that is valid only on one workstation.

Do not move these local manifests into public docs or Makefile help with
absolute paths.

## Local Source Assets

Common local sources include:

- `RaceHorses_416x240_30.yuv`
- `screenshot_640x360.png`
- `screenshot_2560x1440.png`

These files are useful for validation, but they should normally remain
untracked. If a future source asset needs to be public, document its license and
add a portable fetch/generation path first.

## PNG Screenshot Policy

PNG input is used as a lossless still-image source for 4:4:4 screen-content
validation.

Current policy:

- PNG sources imply 4:4:4 validation.
- RGB/RGBA samples are preserved byte-for-byte through the generated planar
  stream.
- Generated files still use the `.yuv` suffix because they are raw planar
  video.
- Lossless codec validation must reconstruct bytes exactly equal to the
  generated planar input.

Viewing a generated PNG crop:

```sh
ffplay -f rawvideo -pixel_format gbrp -video_size 64x64 \
  verification/generated/test_vectors/screen_crop_64x64_1f_yuv444p8.yuv
```

## RaceHorses Policy

RaceHorses crops are local 4:2:0 natural-video guards. They are intentionally
used for lossy residual validation and PSNR/bitrate tracking.

Use local manifests for:

- `racehorses-sweep-420`
- `racehorses-multictu-420`

Do not hard-code the local source path in committed public docs. If the path
changes, update the local manifest only.

## Generated Outputs

Generated vectors and logs normally stay untracked:

- `verification/generated/test_vectors/`
- `verification/generated/validation_logs/`
- `verification/generated/checksums/`
- `verification/generated/software_encodes/`
- `synth/out/`

Reports in `docs/` are the committed summaries. Generated artifacts are
reproducible support files, not the long-term record.

## Reproducibility Rule

Any generated set should be reproducible from:

- the manifest;
- the generator script;
- deterministic crop positions or seeds;
- the named local source asset when the set is machine-local.

If a future test cannot be reproduced, document why before relying on it for a
milestone.
