# AV2 Implementation Progress

This document tracks the AV2 path as it grows from the shared FrameForge
infrastructure into a real encoder. Codec-specific work belongs under
`src/av2/`, `rtl/av2/`, `tb/av2/`, and `verification/codecs/av2/`; reusable
infrastructure such as test-vector generation, PSNR/bitrate reporting,
synthesis wrappers, and cocotb/Yosys entry points remains shared.

See the [AV2 roadmap](roadmap.md) for the next planned milestones.

## Current State

- `CODEC=av2` is accepted by the shared script codec registry.
- `scripts/reference_encode_av2.py` adapts raw planar YUV to Y4M for the AVM
  decoder path and writes a raw reconstruction for checksum, bitrate, and PSNR
  reporting. FrameForge AV2 validation is decode-only against AVM; it does not
  use AVM as a bitrate reference encoder.
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
  8x8-through-64x64 geometry sweep. The current minimum viable profile fixes
  coding leaves at 8x8 and disables SDP, extended partitions, IBC, loop tools,
  and CDF updates. Any `TX_4X4` symbols in this path are internal AV2
  transform blocks, not public FrameForge input blocks.
- `src/av2/palette.rs` contains the first block-local luma palette detector.
  The current subset works on visible 8x8 `yuv444p8` blocks and keeps up to
  eight luma colors per block as the palette predictor. Additional luma detail
  is carried by the lossless residual path, so high-color luma blocks no longer
  rely on nearest-color reconstruction. AV2 v1.0.0 Sections 5.20.8.1 and
  5.20.8.4 only expose
  luma palette syntax in `palette_mode_info()`; AVM `av2_allow_palette()` also
  accepts `PLANE_TYPE_Y` only. FrameForge AV2 therefore must use an allowed
  residual, BDPCM, or IBC-style path for chroma rather than a private chroma
  palette syntax. The current chroma path uses horizontal/vertical BDPCM plus
  lossless `TX_4X4` coefficient coding, with a local U/V edge-SAD chooser for
  the DPCM direction bit in `read_intra_uv_mode()`.
- `rtl/av2/ff_av2_encoder.sv` is a synthesizable AV2 top using the shared
  FrameForge AXI4-Lite control interface plus AXI4 memory-mapped source-read
  and bitstream-write interfaces. Behind the shared AXI reader, the AV2 core
  still works on visible 8x8 Y/U/V block packets so codec traversal remains
  local to the AV2 encoder rather than part of the board-facing interface.
- `rtl/av2/palette/` contains standalone luma-palette modules:
  `ff_av2_palette_analyzer_444`, `ff_av2_chroma_sample_store`, and
  `ff_av2_luma_palette_symbolizer`.
- `rtl/av2/residual/ff_av2_chroma_bdpcm_symbolizer.sv` emits the first
  reference-aligned lossless coefficient syntax for chroma BDPCM and for the
  luma residual that follows palette prediction. The analyzer fetches each 4x4
  TXB through a RAM-backed sample window before the symbolizer runs, avoiding a
  full-superblock combinational sample mux.
- The `yuv420p8` path now mirrors the VVC-style lossy residual milestone: 8x8
  visible luma leaves and 4x4 chroma transform blocks are encoded with local
  neighbor prediction, quantized residual coefficients, and matched software,
  RTL, and AVM-decoded reconstructions. The current AV2 4:2:0 residual subset
  is intentionally quality-first rather than bitrate-optimized.
- `tb/av2/test_av2_encoder.py` drives the AV2 RTL block-packet stream and
  compares the RTL bitstream checksum against the software-generated bitstream
  through the shared validation path.
- Hard-coded AV2 bitstream blobs, traced entropy operation tables, and opaque
  entropy payload append hooks have been removed. Treat any new opaque AV2
  payload as a bug; future syntax must be generated from named,
  spec-auditable decisions in both software and RTL.

## Palette Compliance Notes

- AV2 v1.0.0 Section 5.20.8.1 `palette_mode_info()` only signals
  `has_palette_y`, `palette_size_y_minus_2`, and luma palette color values.
  There is no U/V palette header syntax in the current reference-compatible
  bitstream.
- AV2 v1.0.0 Section 5.20.8.4 `palette_tokens()` only parses a luma color map
  when `PlaneStart == 0 && PaletteSizeY`. There is no chroma palette color map
  and no palette escape sample syntax.
- AVM v1.0.0 mirrors this by accepting palette only for `PLANE_TYPE_Y` in
  `av2_allow_palette()`, and by keeping `palette_size[1] == 0`.
- Therefore a FrameForge AV2 PASS for arbitrary 4:4:4 screenshots cannot be
  implemented as palette-only coding. The current compliant lossless path
  combines 8x8 luma palette prediction, lossless luma residual coefficient
  coding for any palette prediction error, and horizontal-BDPCM chroma
  residuals.
- AV2 v1.0.0 Section 5.20.7.23 `residual()` uses `TX_4X4` transform blocks in
  lossless mode. These 4x4 units are transform blocks only; the FrameForge AV2
  coding leaf and RTL input packet remain fixed at visible 8x8 Y/U/V blocks.

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

# Local, when screenshot_640x360.png and the local manifest are present:
make test-vectors TEST_VECTOR_SET=screenshot-sweep-444
make validate-set \
  CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

## Historical Checks

These older checks are kept as implementation history. Current measurements and
deltas live in `quality-bitrate.md`, `output-utilization.md`, and
`synthesis.md`.

Last checked on 2026-06-15:

- `make validate CODEC=av2
  INPUT=verification/generated/test_vectors/av2_luma_palette_bars_64x64_1f_yuv444p8.yuv
  WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv444p8 VALIDATE_SYNTH=0`: passed. Input,
  software reconstruction, RTL reconstruction, and AVM-decoded reconstruction
  all had SHA-256
  `9b912726e1b5354820c67d65b71e380a5d7644ab0fa5e4fe523341ef47e460f2`.
  Software and RTL bitstream checksums matched at
  `01b1ad518fdae2bcd1328af9c567b37937fe87b17ba674b20e0c3fff0f1d3533`.
  The generated FrameForge bitstream was 2248 bytes, or 4.3906 bits per luma
  pixel, and all reported PSNR values were infinite.
- `make validate-set CODEC=av2 VALIDATION_SET=sweep-black-444
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0`: passed all 64 black
  4:4:4 geometries.
- `make validate-set CODEC=av2 VALIDATION_SET=bdpcm-444
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0`: passed all 64
  horizontal-BDPCM 4:4:4 geometries with matching SW/RTL bitstreams and
  lossless SW/RTL/REF reconstructions.
- `make validate-set CODEC=av2 VALIDATION_SET=palette-escape-444
  VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0`: passed all 64 high-color
  generated 4:4:4 geometries with matching SW/RTL bitstreams and lossless
  SW/RTL/REF reconstructions. The representative 64x64 vector generated a
  19937-byte FrameForge bitstream at 38.9395 bits per luma pixel; all reported
  PSNR values were infinite.
- `make synth CODEC=av2`: passed Yosys synthesis for the luma-palette,
  lossless 4:4:4 residual path, and the current lossy 4:2:0 residual path. The
  detailed baseline is recorded in
  [synthesis.md](synthesis.md), and quality/bitrate measurements are recorded
  in [quality-bitrate.md](quality-bitrate.md).
- The AV2 `racehorses-sweep-420` local validation set passed all 64 geometries
  from 8x8 through 64x64 with strict software/RTL bitstream parity and matching
  software, RTL, and AVM-decoded reconstructions. The current sweep average is
  2.1998 bits per luma pixel and 24.08 dB PSNR.

## Next Steps

- Validate the local screenshot crop set again as a real screen-content
  workload now that the generated high-color sweep is lossless.
- Use the 4:2:0 RaceHorses residual baseline as the next video-content guard
  when changing shared residual, entropy, or top-level AXI behavior.
- Optimize the current luma-palette symbolizer path; synthesis reports the
  palette delta-bit calculation through the range coder as the current
  topological critical path.
- Replace the staged tile carry buffer with a streaming carry resolver after
  the next functional blocks are in place.
- Continue expanding the block partition and luma-palette decisions while
  keeping the internal codec-core packet contract at visible 8x8 Y/U/V blocks
  unless a codec-specific order is clearly cheaper.
- Keep checksum, bitrate, and PSNR reporting in the shared validation path as
  new AV2 syntax is added.
- Keep porting syntax decisions into RTL without byte-stream blobs or traced
  operation tables.
