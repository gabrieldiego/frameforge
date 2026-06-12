# Initial Codec Target Notes

FrameForge is a general codec experimentation and hardware-acceleration lab. The first concrete target is a minimal VVC/H.266 encoder foundation, but the architecture should remain broad enough to support other codecs, codec-like bitstreams, decoder work, software golden models, and RTL acceleration.

## Implemented Now

- Rust crate and CLI foundation.
- VVC Annex-B writer capable of emitting an EOS-only stream for NAL header and bytestream testing.
- VVC Annex-B NAL header listing for comparing FrameForge output against VTM output.
- Generated VVC frame sequences assembled from internally generated SPS/PPS headers, picture headers, and picture slice NAL units. The current software input path accepts planar YUV 4:2:0, 4:2:2, and 4:4:4 at 8, 10, 12, or 16 bits and can emit larger pictures as a stream of 64x64 CTU-local slices. Samples are reduced to the current 8-bit coding subsets before bitstream generation.
- VTM-backed decode validation for the current subset. Software and RTL bitstreams must match. Software internal reconstruction, RTL internal reconstruction, and VTM reconstruction must match whenever external decode is wired for the selected path.
- Current non-4:4:4 path: internally generated 4:2:0 CTU/CU syntax, CABAC-coded slice entropy, fixed quantization, local reconstruction, and coefficient-coded luma residuals. AC coding is currently limited to the first 4x4 coefficient group.
- Current 4:4:4 path: experimental lossless screen-content coding with 8x8 CUs. Exact repeated CUs can use CTU-local IBC by 32-bit hash match; unmatched CUs fall back to palette coding with up to 31 direct palette entries and raw 8-bit escape values for additional YCbCr/GBR colors.
- External VTM reference-encode helper that can generate a real small-geometry YUV VVC stream for validation.
- Basic encoder trait boundary for adding more codec implementations.
- Generic bitstream utilities:
  - `BitWriter`
  - byte alignment
  - RBSP trailing bits
  - emulation-prevention byte insertion
- Named VVC syntax writer for `flag`, `u(n)`, `ue(v)`, `se(v)`, CABAC packets, RBSP trailing bits, and field-offset tracing.
- Internally generated VVC NAL unit headers with named `forbidden_zero_bit`, `nuh_reserved_zero_bit`, `nuh_layer_id`, `nal_unit_type`, and `nuh_temporal_id_plus1` fields.
- Internally generated SPS, PPS, picture header, slice header, and typed coding-tree events packetized into the entropy-coded body. The generated VVC stream no longer carries private `FFAC` or `FFPL` reserved-NAL payloads.
- Rust VVC encoder input handling for planar YUV frame sequences with 4:2:0, 4:2:2, or 4:4:4 chroma at 8, 10, 12, or 16 bits per sample. Software validation may choose practical size limits, but those limits are caller-supplied checks rather than a compiled encoder geometry ceiling.
- RTL VVC encoder input handling is parameterized with `visible_width`, `visible_height`, `SAMPLE_BITS`, and `chroma_format_idc` for wider input frames, input buses, and chroma planes while emitting the same stream as software for the current subset.
- Software and RTL internal reconstructions must match the reconstruction represented by the emitted VVC bitstream. For geometries currently accepted by VTM, they must also match external decoder output. If VTM terminates with a process crash, only that external decoder comparison is skipped; the same vector remains useful for software/RTL comparison. Unsupported features must not be represented as hidden sideband reconstruction.
- Basic NAL/Annex-B-style structures with TODOs for missing exact VVC syntax.
- `EncoderParams`, `Picture`, reconstruction buffers, and CTU/CU traversal for the current subset.
- JSONL trace events.
- Optional external decoder wrapper that does not assume a decoder is installed.
- Reference-decoder setup helper that uses local decoder settings first and can clone/build VTM under `verification/reference`.
- SystemVerilog RTL blocks with stream-style handshakes.
- RTL VVC generator that drains a parameterized CTU-local leaf stream converted from planar YUV by the testbench, emits sequence headers, per-picture Annex-B start codes, VVC NAL headers, and CABAC-coded NAL payload bytes to match the Rust VVC stream.
- cocotb/Icarus verification fixtures.
- Local contribution and license files for an open-source starting point.

## RTL Input Stream Contract

The software model and generated YUV files remain planar YUV: all luma samples,
then all Cb samples, then all Cr samples. The current RTL top does not consume
that storage order directly. The cocotb driver converts each frame into a
CTU-local coding-tree leaf stream:

```text
for each active 8x8 leaf in coding-tree order:
  8x8 Y samples
  colocated Cb samples
  colocated Cr samples
```

For the current 4:2:0 residual path, the colocated chroma blocks are 4x4. For
the current 4:4:4 screen-content path, they are 8x8. This is an intentional hardware
simplification: the input side only needs a TU-sized live buffer instead of a
full 64x64 CTU fetch buffer. If dynamic partitioning becomes necessary later,
the same contract can be widened to 16x16 leaves or eventually to full CTU
raster fetches.

## First VVC/H.266 Subset Target

- All-intra only at first.
- Single picture initially.
- One tile initially.
- One slice initially.
- Fixed traversal initially.
- No inter prediction.
- No B-frames.
- No rate control.
- No real RDO.
- Screen-content coding remains narrow: only the current experimental 4:4:4 palette plus exact-match IBC subset is present.
- Residual path currently supports coefficient-coded luma residuals with AC limited to the first 4x4 coefficient group.
- 4:4:4 screen-content path includes a restricted horizontal BDPCM mode for 8x8
  leaves. It predicts from the immediate left sample, keeps coefficients in the
  first 4x4 group, infers transform skip as required by H.266 7.4.12.11, and is
  intended as a simple lossless building block before broader intra prediction.
- Decoder validation target: generated bitstreams for the current subset should decode with external tools such as VTM.

## Planned Next

- Continue auditing clean-room VVC parameter set, slice, CTU/CU, residual, and palette syntax against the standard as new syntax elements are enabled.
- Expand residual coding beyond the first 4x4 coefficient group, including scan-position suffixes and subblock-coded flags for larger transform blocks.
- Add independent decoded chroma residual support beyond the current limited non-4:4:4 path.
- Keep software, RTL, and external-decoder reconstructions identical as more color and residual cases are added.
- Carry profile or operating-point constraints separately from the generic sample bit-depth plumbing once real VVC profile handling is added.
- Continue VVC palette coding by extending the current SPS palette enable path, CU palette syntax, CABAC contexts, palette predictor reuse, palette entries, copy/run flags, indices, and escape-value behavior from the standard.
- Expand IBC beyond CTU-local exact 8x8 hash matches when there is a clear verification target for the wider search window and predictor list.
- Keep the internal syntax packet model narrow and stream-oriented as coding-tree traversal grows.
- Add a software golden model for one small intra prediction mode.
- Add block-level RTL/software comparison through cocotb.
- Expand simulator abstraction without tying the project permanently to Icarus Verilog.

## Out Of Scope For Now

- Full VVC conformance.
- Full VVC decoder implementation.
- Imported VTM or VVdeC source code.
- CABAC completeness beyond syntax elements currently audited and emitted.
- Complete transform/quantization, loop filters, inter prediction, B-frames, rate control, or production RDO.
- Complete SCC tools such as full IBC search/window handling, broader BDPCM
  direction/block-size coverage, transform skip, and broader palette
  predictor/copy-above behavior.
- FPGA vendor integration or proprietary EDA requirements.

## VVC Isolation

VVC-specific code belongs in isolated modules such as `src/vvc/` or future `src/codecs/vvc/` modules. Generic infrastructure should use names such as `bitstream`, `encoder`, `picture`, `trace`, `packet`, and `golden` where reasonable. The project should not become permanently shaped around VVC terminology when a generic abstraction is sufficient.
