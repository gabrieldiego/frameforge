# Test Vector Sets

This directory contains CSV manifests for deterministic generated YUV test
vectors. Each manifest is consumed by `scripts/generate_test_vectors.py`.

Committed manifests must be portable. Do not put workstation-local media paths
in committed files.

Local source-crop manifests belong under:

```text
verification/test_vector_sets/local/
```

That directory is ignored by git. Use it for vectors cropped from local YUV
sequences on your machine.

Manifest format:

```text
# generator=scripts/generate_test_vectors.py
# description=Short description of this set.
# source=id=clip,path=/path/to/local.yuv,width=416,height=240,format=yuv420p8
name,width,height,frames,format,pattern,fps,source,crop_x,crop_y
stick_walk,64,64,3,yuv420p8,stick_walk,30,,,
clip_crop,64,64,1,yuv420p8,source_crop,,clip,128,64
```

Supported procedural patterns are:

- `black`
- `screen_blocks`
- `moving_blocks`
- `stick_walk`

The `source_crop` pattern currently supports cropping the first frame from a
planar 8-bit 4:2:0 YUV source.
