# AV2 Implementation Progress

This document tracks the AV2 path as it grows from the shared FrameForge
infrastructure into a real encoder. The goal is to keep codec-specific work
under `src/av2/`, `rtl/av2/`, `tb/av2/`, and `verification/codecs/av2/`, while
reusing generic infrastructure such as generated test vectors, PSNR/bitrate
reporting, synthesis wrappers, and cocotb/Yosys entry points.

## Current State

- `CODEC=av2` is accepted by the shared script codec registry.
- `cargo run -- av2-encode ...` has a stable CLI slot and validates the basic
  request shape, but bitstream generation is not implemented yet.
- `rtl/av2/ff_av2_encoder.sv` is the initial hardware entry point. It provides a
  synthesis-ready streaming shell with `start`, `busy`, `input_error`, and
  byte-stream handshakes.
- The AV2 top-level interface intentionally mirrors `ff_vvc_encoder` for common
  integration signals. The shared `CTU_SIZE` parameter name is temporary until
  the AV2 block/superblock naming is settled.
- `tb/av2/test_av2_encoder.py` validates the initial AV2 RTL handshakes.
- `make rtl-test CODEC=av2` and `make synth CODEC=av2` route through the shared
  infrastructure.
- `make decoder-setup CODEC=av2` finds or builds AVM under
  `verification/codecs/av2/reference/avm` unless an external path is configured.
- `scripts/reference_encode_av2.py` adapts raw planar YUV to Y4M, invokes the
  AVM encoder, decodes the resulting reference bitstream, and writes a raw
  reconstruction for checksum, bitrate, and PSNR reporting.
- Functional validation with `make validate CODEC=av2 ...` now runs the AVM
  reference encode/decode path first, then intentionally fails at the
  FrameForge AV2 software/RTL comparison boundary until those encoders emit
  real AV2 streams.

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
- `FRAMEFORGE_AV2_ENCODER_CMD` or `FRAMEFORGE_AVM_ENCODER_CMD`: full encoder
  command template when the local AVM command line differs from the default.
  Placeholders include `{encoder}`, `{input}`, `{output}`, `{frames}`,
  `{width}`, `{height}`, `{format}`, `{sampling}`, `{bit_depth}`,
  `{cpu_used}`, and `{cq_level}`.
- `FRAMEFORGE_AV2_DECODER_ARGS` or `FRAMEFORGE_AVM_DECODER_ARGS`: extra
  decoder arguments for reconstruction output. The default is `--rawvideo`.

Manual reference run:

```sh
make decoder-setup CODEC=av2
make reference-av2 \
  INPUT=verification/generated/test_vectors/smoke_8x8_1f_yuv444p8.yuv \
  BITSTREAM=verification/generated/av2_reference/smoke_8x8.av2 \
  RECON=verification/generated/av2_reference/smoke_8x8_recon.yuv \
  WIDTH=8 HEIGHT=8 FRAMES=1 FORMAT=yuv444p8
```

Reference-only validation run:

```sh
make validate CODEC=av2 \
  INPUT=verification/generated/test_vectors/smoke_8x8_1f_yuv444p8.yuv \
  WIDTH=8 HEIGHT=8 FRAMES=1 FORMAT=yuv444p8 \
  VALIDATE_SYNTH=0
```

This command should return failure after the AVM reference artifacts are written,
because FrameForge AV2 software and RTL bitstream comparison is not implemented
yet.

## Current Checks

Last checked on 2026-06-12:

- `cargo test`: passed, including AV2 request-shape and CLI parsing tests.
- `make rtl-test CODEC=av2`: passed 3 cocotb tests for the AV2 top-level
  interface.
- `make synth CODEC=av2 SYNTH_TIMEOUT_SEC=120 SYNTH_WARN_AFTER_SEC=60`: passed
  Yosys synthesis for `ff_av2_encoder` in 4.2 seconds with 127.36 MiB peak RSS.
- `python3 -m py_compile scripts/*.py tb/av2/*.py tb/vvc/*.py`: passed after
  adding the AV2 reference setup and reference encode wrapper.
- `python3 scripts/ensure_reference_decoder.py --codec av2 --no-build
  --print-command`: fails gracefully when no local AVM decoder is configured or
  built.

## Next Implementation Checkpoints

- Define the first AV2 elementary bitstream/container boundary used by
  FrameForge outputs.
- Add the first sequence/header writer in `src/av2/`.
- Add software reconstruction plumbing for the first intra-only picture path.
- Replace the initial RTL byte path with header emission and a first real block
  pipeline.
- Promote the AV2 validation branch from reference-only failure to
  software/reference comparison once `cargo run -- av2-encode ...` produces a
  real stream and reconstruction.
- Add RTL/reference comparison once the AV2 hardware path has a concrete
  bit-exact contract.
