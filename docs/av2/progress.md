# AV2 Implementation Progress

This document tracks the AV2 path as it grows from the shared FrameForge
infrastructure into a real encoder. Codec-specific work belongs under
`src/av2/`, `rtl/av2/`, `tb/av2/`, and `verification/codecs/av2/`; reusable
infrastructure such as test-vector generation, PSNR/bitrate reporting,
synthesis wrappers, and cocotb/Yosys entry points remains shared.

## Current State

- `CODEC=av2` is accepted by the shared script codec registry.
- `scripts/reference_encode_av2.py` adapts raw planar YUV to Y4M, invokes the
  AVM encoder, decodes the resulting reference bitstream, and writes a raw
  reconstruction for checksum, bitrate, and PSNR reporting.
- `make decoder-setup CODEC=av2` finds or builds AVM under
  `verification/codecs/av2/reference/avm` unless an external path is configured.
- `src/av2/` contains a named-field writer for the initial sequence header,
  closed-loop-key tile-group header fields, and the first range-coded tile
  syntax subset. The software encoder generates bytes from labeled syntax
  decisions rather than stored stream payloads.
- `src/av2/entropy.rs` contains the first Rust AV2 range-writer implementation,
  following the AVM encoder side of the spec descriptors for arithmetic-coded
  literals and symbols.
- `src/av2/tile.rs` contains the structured black 4:4:4 tile plan for the full
  8x8-through-64x64 geometry sweep. The current minimum viable profile disables
  SDP, extended partitions, IBC, loop tools, and CDF updates.
- `src/av2/palette.rs` contains the first palette detector. The supported
  palette subset is intentionally narrow: one 64x64 `yuv444p8` frame with two
  luma colors, zero U/V, and the deterministic horizontal bar pattern generated
  by `av2_luma_palette_bars`.
- `rtl/av2/ff_av2_encoder.sv` is a synthesizable AV2 top with the same
  top-level handshake shape as the VVC encoder. It consumes planar 4:4:4 input
  over `s_axis_*`, classifies the current frame as black or the first luma
  palette pattern, and emits a generated OBU stream through `m_axis_*`.
- `rtl/av2/palette/` contains the first standalone palette modules:
  `ff_av2_input_classifier_444` and
  `ff_av2_luma_palette_bars_symbolizer`.
- `tb/av2/test_av2_encoder.py` drives the AV2 RTL input stream and compares the
  RTL bitstream checksum against the software-generated bitstream through the
  shared validation path.
- Hard-coded AV2 bitstream blobs, traced entropy operation tables, and opaque
  entropy payload append hooks have been removed. Treat any new opaque AV2
  payload as a bug; future syntax must be generated from named,
  spec-auditable decisions in both software and RTL.

## Reference Tool Setup

The AV2 reference path uses the AOMedia AVM repository by default. Override it
with local paths when experimenting with a specific build:

- `FRAMEFORGE_AV2_ROOT` or `FRAMEFORGE_AVM_ROOT`: existing AVM checkout/build
  tree to search.
- `FRAMEFORGE_AV2_DECODER` or `FRAMEFORGE_AVM_DECODER`: direct path to
  `avmdec`/`aomdec`.
- `FRAMEFORGE_AV2_ENCODER` or `FRAMEFORGE_AVM_ENCODER`: direct path to
  `avmenc`/`aomenc`.
- `FRAMEFORGE_AV2_REPO` or `FRAMEFORGE_AVM_REPO`: git URL used by
  `make decoder-setup CODEC=av2`.
- `FRAMEFORGE_AV2_REF` or `FRAMEFORGE_AVM_REF`: optional branch or tag.
- `FRAMEFORGE_AV2_BUILD_DIR` or `FRAMEFORGE_AVM_BUILD_DIR`: CMake build
  directory.
- `FRAMEFORGE_AV2_BUILD_TYPE` or `FRAMEFORGE_AVM_BUILD_TYPE`: CMake build
  type, default `Release`.
- `FRAMEFORGE_AV2_CMAKE_ARGS` or `FRAMEFORGE_AVM_CMAKE_ARGS`: extra CMake
  arguments for AVM. If neither `yasm` nor `nasm` is installed, the helper
  automatically configures AVM with `-DAVM_TARGET_CPU=generic`.
- `FRAMEFORGE_AV2_ENCODER_CMD` or `FRAMEFORGE_AVM_ENCODER_CMD`: full encoder
  command template when the local AVM command line differs from the default.
  Placeholders include `{encoder}`, `{input}`, `{output}`, `{frames}`,
  `{width}`, `{height}`, `{format}`, `{sampling}`, `{bit_depth}`, `{cpu_used}`,
  and `{cq_level}`.
- `FRAMEFORGE_AV2_DECODER_ARGS` or `FRAMEFORGE_AVM_DECODER_ARGS`: extra decoder
  arguments for reconstruction output. The default is `--rawvideo`.

Manual reference run:

```sh
make decoder-setup CODEC=av2
make test-vectors TEST_VECTOR_SET=sweep-black-444
make reference-av2 \
  INPUT=verification/generated/test_vectors/black_64x64_1f_yuv444p8.yuv \
  BITSTREAM=verification/generated/av2_reference/black_64x64.av2 \
  RECON=verification/generated/av2_reference/black_64x64_recon.yuv \
  WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv444p8
```

FrameForge AV2 validation for the current subsets:

```sh
make test-vectors TEST_VECTOR_SET=sweep-black-444
make validate-set \
  CODEC=av2 \
  VALIDATION_SET=sweep-black-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make test-vectors TEST_VECTOR_SET=av2-palette-luma-444
make validate-set \
  CODEC=av2 \
  VALIDATION_SET=av2-palette-luma-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

## Current Checks

Last checked on 2026-06-13:

- `cargo test av2 -- --nocapture`: passed.
- `make -B rtl-test CODEC=av2 DUT=av2-encoder RTL_VISIBLE_WIDTH=64
  RTL_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3`: passed.
- `make validate CODEC=av2
  INPUT=verification/generated/test_vectors/av2_luma_palette_bars_64x64_1f_yuv444p8.yuv
  WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv444p8 VALIDATE_SYNTH=0`: passed. Input,
  software reconstruction, RTL reconstruction, and AVM-decoded reconstruction
  all had SHA-256
  `9b912726e1b5354820c67d65b71e380a5d7644ab0fa5e4fe523341ef47e460f2`.
  Software and RTL bitstream checksums matched at
  `b63ef0fdff1273b8d24da8ddb210b8ea2c4df2a0cf8f2e303e0745024b8bc9f4`.
  The generated FrameForge bitstream was 1962 bytes, or 3.8320 bits per luma
  pixel, and all reported PSNR values were infinite.
- `make validate-set CODEC=av2 VALIDATION_SET=sweep-black-444
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0`: passed all 64 black
  4:4:4 geometries.
- `make validate-set CODEC=av2 VALIDATION_SET=av2-palette-luma-444
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0`: passed the first palette
  smoke vector.
- `make synth CODEC=av2`: passed Yosys synthesis for the structured black plus
  first luma-palette path. The detailed baseline is recorded in
  [synthesis.md](synthesis.md).

## Next Steps

- Generalize palette detection beyond the deterministic 64x64 luma-bar smoke.
- Add chroma palette and escape-value syntax so 4:4:4 palette can become
  lossless for arbitrary input.
- Replace the narrow frame classifier with a real TU/CU-oriented sample ingest
  path as more AV2 block decisions are added.
- Keep checksum, bitrate, and PSNR reporting in the shared validation path as
  new AV2 syntax is added.
- Keep porting syntax decisions into RTL without byte-stream blobs or traced
  operation tables.
