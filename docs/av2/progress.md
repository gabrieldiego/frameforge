# AV2 Implementation Progress

This document tracks the AV2 path as it grows from the shared FrameForge
infrastructure into a real encoder. The goal is to keep codec-specific work
under `src/av2/`, `rtl/av2/`, `tb/av2/`, and `verification/codecs/av2/`, while
reusing generic infrastructure such as generated test vectors, PSNR/bitrate
reporting, synthesis wrappers, and cocotb/Yosys entry points.

## Current State

- `CODEC=av2` is accepted by the shared script codec registry.
- `cargo run -- av2-encode ...` currently implements a temporary fixed path for
  one black 64x64 `yuv444p8` frame. It writes the same raw black-frame payload
  to the `.av2` output and optional reconstruction so the verification pipeline
  can compare software and RTL byte-for-byte before real AV2 syntax exists.
- `rtl/av2/ff_av2_encoder.sv` is the initial hardware entry point. It provides a
  streaming shell with `start`, `busy`, `input_error`, and byte-stream
  handshakes.
- `rtl/av2/ff_av2_encoder.sv` also contains a TODO-marked temporary
  simulation-only fixed payload for one black 64x64 4:4:4 frame. It deliberately
  ignores input samples and is not intended to synthesize.
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
- Functional validation with `make validate CODEC=av2 ...` now supports the
  temporary black-frame vector. It runs FrameForge software, AVM reference
  encode/decode, and RTL simulation, then checks that software payload,
  software reconstruction, reference reconstruction, RTL payload, and RTL
  reconstruction all match the black 64x64 `yuv444p8` input.

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
  `{width}`, `{height}`, `{format}`, `{sampling}`, `{bit_depth}`,
  `{cpu_used}`, and `{cq_level}`.
- `FRAMEFORGE_AV2_DECODER_ARGS` or `FRAMEFORGE_AVM_DECODER_ARGS`: extra
  decoder arguments for reconstruction output. The default is `--rawvideo`.

Manual reference run:

```sh
make decoder-setup CODEC=av2
make test-vectors TEST_VECTOR_SET=av2-smoke
make reference-av2 \
  INPUT=verification/generated/test_vectors/black_64x64_1f_yuv444p8.yuv \
  BITSTREAM=verification/generated/av2_reference/black_64x64.av2 \
  RECON=verification/generated/av2_reference/black_64x64_recon.yuv \
  WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv444p8
```

Temporary software/reference/RTL validation run:

```sh
make test-vectors TEST_VECTOR_SET=av2-smoke
make validate CODEC=av2 \
  INPUT=verification/generated/test_vectors/black_64x64_1f_yuv444p8.yuv \
  WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv444p8 \
  VALIDATE_SYNTH=0
```

This command should pass only for the temporary black 64x64 `yuv444p8` vector.
Other AV2 inputs fail clearly until real AV2 syntax emission exists.

## Current Checks

Last checked on 2026-06-12:

- `cargo test`: passed, including AV2 request-shape and CLI parsing tests.
- `make rtl-test CODEC=av2`: passed cocotb tests for the AV2 top-level
  interface and temporary black-frame payload.
- Historical pre-temporary-path synthesis:
  `make synth CODEC=av2 SYNTH_TIMEOUT_SEC=120 SYNTH_WARN_AFTER_SEC=60` passed
  Yosys synthesis for `ff_av2_encoder` in 4.2 seconds with 127.36 MiB peak RSS.
- `python3 -m py_compile scripts/*.py tb/av2/*.py tb/vvc/*.py`: passed after
  adding the AV2 reference setup and reference encode wrapper.
- `python3 scripts/ensure_reference_decoder.py --codec av2 --no-build
  --print-command`: fails gracefully when no local AVM decoder is configured or
  built.

## Next Implementation Checkpoints

- Replace the temporary raw black-frame payload with the first real AV2
  elementary bitstream/container boundary used by FrameForge outputs.
- Add the first sequence/header writer in `src/av2/`.
- Add software reconstruction plumbing for the first intra-only picture path.
- Replace the initial RTL byte path with header emission and a first real block
  pipeline.
- Replace temporary SW/RTL raw-payload comparison with real AV2 software/RTL
  bitstream comparison.
- Add full RTL/reference comparison once the AV2 hardware path emits a
  decodable AV2 stream.
