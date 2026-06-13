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
- `src/av2/` contains a named-field writer for the initial sequence header and
  closed-loop-key tile-group header fields. These helpers are kept because the
  bytes are generated from labeled syntax fields rather than stored streams.
- `src/av2/entropy.rs` contains the first Rust AV2 range-writer implementation,
  following the AVM encoder side of the spec descriptors for arithmetic-coded
  literals and symbols.
- `src/av2/tile.rs` contains the first structured black 4:4:4 tile plan. The
  current minimum viable profile disables SDP, extended partitions, palette,
  IBC, loop tools, and CDF updates, then plans one 64x64 superblock as 8x8
  shared luma/chroma leaves with DC intra prediction and zero transform
  coefficients. The plan is intentionally not yet encoded into CDF-backed
  symbols; the range writer still emits only the generated entropy terminator
  until the partition, mode, and coefficient CDF calls are ported.
- `cargo run -- av2-encode ...` validates the staged black `yuv444p8` input
  shape, emits a generated unmuxed OBU skeleton, and writes a black internal
  reconstruction. AVM currently rejects this stream at tile decode because the
  block-level tile syntax is incomplete.
- `rtl/av2/ff_av2_encoder.sv` is a synthesizable integration shell with the same
  top-level handshake shape as the VVC encoder. It reports `input_error` on
  `start` and emits no output until the AV2 tile entropy path exists.
- `tb/av2/test_av2_encoder.py` verifies that the AV2 RTL shell rejects the
  missing entropy implementation instead of emitting a placeholder stream.
- Hard-coded AV2 bitstream blobs, traced entropy operation tables, and opaque
  entropy payload append hooks have been removed. Future AV2 entropy coding
  must be generated from named, spec-auditable syntax decisions in both
  software and RTL.

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

FrameForge AV2 validation currently fails at the AVM decode step:

```sh
make test-vectors TEST_VECTOR_SET=sweep-black-444
make validate-set \
  CODEC=av2 \
  VALIDATION_SET=sweep-black-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

This failure is the expected state until block-level tile syntax is generated.
Treat any opaque AV2 bitstream payload or traced entropy table as a bug.

## Current Checks

Last checked on 2026-06-13:

- `cargo test av2`: passed after adding the generated AV2 entropy writer, the
  narrowed black-444 MVP profile, and the 8x8 tile syntax plan.
- `python3 scripts/validate_decode.py --codec av2
  verification/generated/software_encodes/black_8x8_1f_yuv444p8_mvp.av2
  --output verification/generated/software_encodes/black_8x8_1f_yuv444p8_mvp_refdec.yuv
  --rawvideo`: failed in AVM with `Failed to decode tile data`, confirming the
  generated stream reaches tile decoding before the expected rejection.
- `make rtl-test CODEC=av2 RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64
  RTL_CHROMA_FORMAT_IDC=3`: passed, verifying that the RTL shell rejects encode
  attempts and emits no payload.
- `make validate-set CODEC=av2 VALIDATION_SET=sweep-black-444
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0`: expected failure at the
  first AVM software-bitstream decode because block-level tile syntax is not
  implemented.
- `make synth CODEC=av2`: passed Yosys synthesis for the explicit unsupported
  shell in 3.6 seconds with 127.45 MiB peak RSS. The topological critical-path
  length is 1.

## Next Steps

- Port the first CDF-backed symbols for the existing 8x8 tile plan: split
  partitions down to 8x8, intra DC luma/chroma modes, and all-zero transform
  block coefficient syntax.
- Once software emits a valid stream, decode it through AVM and keep checksum,
  bitrate, and PSNR reporting in the shared validation path.
- Port the same syntax decisions into RTL without byte-stream blobs or traced
  operation tables.
- Re-enable SW/RTL/reference checksum comparison for `sweep-black-444`.
