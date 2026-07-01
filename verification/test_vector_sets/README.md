# Test Vector Sets

This directory contains CSV manifests for deterministic generated YUV test
vectors. Each manifest is consumed by `scripts/generate_test_vectors.py`.
`sweep-black-444.csv` exercises black 4:4:4 geometries from 8x8 through 64x64
in 8-pixel steps and is the first AV2 geometry sweep. `av2-palette-luma-444.csv`
contains the first AV2 palette smoke vector, a 64x64 two-color luma bar pattern
with zero chroma.

Committed manifests must be portable. Do not put workstation-local media paths
in committed files.

For the broader local asset policy, including RaceHorses and screenshot source
handling, see `../../docs/validation/local-assets.md`.

Local source-crop manifests belong under:

```text
verification/test_vector_sets/local/
```

That directory is ignored by git. Use it for vectors cropped from local raw YUV
sequences or local PNG screenshots on your machine.

Manifest format:

```text
# generator=scripts/generate_test_vectors.py
# description=Short description of this set.
# source=id=clip,path=/path/to/local.yuv,width=416,height=240,format=yuv420p8
name,width,height,frames,format,pattern,fps,source,crop_x,crop_y
stick_walk,64,64,3,yuv420p8,stick_walk,30,,,
clip_crop,64,64,1,yuv420p8,source_crop,,clip,128,64
```

PNG screenshot crops use the same `source_crop` shape:

```text
# source=id=screen,path=screenshot_640x360.png,width=640,height=360,format=png_rgba8
screen_crop,64,64,1,yuv444p8,source_crop,,screen,288,144
```

Supported procedural patterns are:

- `black`
- `av2_luma_palette_bars`
- `bdpcm_horizontal`
- `bdpcm_vertical`
- `palette_escape_prng`
- `screen_blocks`
- `transform_skip_left_delta`
- `moving_blocks`
- `stick_walk`

The `source_crop` pattern supports:

- first-frame crops from planar 8-bit 4:2:0 YUV sources into `yuv420p8`
- lossless crops from PNG RGB/RGBA screenshots into `yuv444p8`

PNG sources always imply 4:4:4 encoding in this project. RGB samples are
preserved byte-for-byte as planar GBR components carried through the current
`yuv444p8` encoder path. The `.yuv` suffix is still used because the generated
file is raw planar video. To inspect a generated PNG crop, use:

```bash
ffplay -f rawvideo -pixel_format gbrp -video_size 64x64 \
  verification/generated/test_vectors/screen_crop_64x64_1f_yuv444p8.yuv
```
