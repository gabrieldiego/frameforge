# Initial Codec Target Notes

FrameForge is a general codec experimentation and hardware-acceleration lab. The first concrete target is a minimal toy VVC/H.266 encoder foundation, but the architecture should remain broad enough to support other codecs, codec-like bitstreams, decoder work, software golden models, and RTL acceleration.

## Implemented Now

- Rust crate and CLI skeleton.
- VVC Annex-B writer capable of emitting an EOS-only stream for NAL header and bytestream testing.
- VVC skeleton stream containing VPS/SPS/PPS/IDR/EOS/EOB NAL units with placeholder RBSP payloads.
- VVC Annex-B NAL header listing for comparing FrameForge output against VTM output.
- Generated 1- or 2-frame 4x4 YUV420p8 VVC toy stream assembled from one internally generated SPS/PPS sequence header followed by generated picture slice NAL units. The current bitstream path still emits the verified black residual stream.
- External VTM reference-encode helper that can generate a real 4x4 YUV420 VVC stream for validation.
- Basic encoder trait boundary for replacing the placeholder path with real codec implementations.
- Generic bitstream utilities:
  - `BitWriter`
  - byte alignment
  - RBSP trailing bits
  - emulation-prevention byte insertion
- Named VVC syntax writer for `flag`, `u(n)`, `ue(v)`, `se(v)`, toy CABAC packets, RBSP trailing bits, and field-offset tracing.
- Internally generated VVC NAL unit headers with named `forbidden_zero_bit`, `nuh_reserved_zero_bit`, `nuh_layer_id`, `nal_unit_type`, and `nuh_temporal_id_plus1` fields.
- Internally generated toy SPS, PPS, picture header, slice header, and typed toy coding-tree events packetized into the entropy-coded body.
- Rust and RTL toy encoder input handling for 4x4 YUV420p8 frame sequences, currently sampling the first Y/Cb/Cr values and ignoring the rest of the samples.
- Basic placeholder NAL/Annex-B-style structures with TODOs for exact VVC syntax.
- `EncoderParams`, `Picture`, reconstruction buffer skeleton, and fixed block traversal.
- JSONL trace events.
- Optional external decoder wrapper that does not assume a decoder is installed.
- Reference-decoder setup helper that uses local decoder settings first and can clone/build VTM under `verification/reference`.
- SystemVerilog RTL stubs with AXI-stream-style handshakes.
- Minimum RTL encoder shell that drains an input stream and emits a fixed placeholder output packet.
- RTL VVC skeleton emitter that matches Rust `vvc-skeleton` byte-for-byte.
- RTL toy VVC generator that drains a 4x4 YUV420p8 input stream, checks that the current supported samples are all-zero, and emits a sequence header plus per-picture Annex-B start codes, VVC NAL headers, and NAL payload bytes to match the Rust toy stream.
- cocotb/Icarus verification skeleton.
- Local contribution and license files for an open-source starting point.

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
- No screen-content coding tools yet.
- Zero or trivial residual path at first.
- Decoder validation target: generated bitstreams should eventually decode with external tools such as VVdeC or VTM.

## Planned Next

- Replace placeholder output with clean-room VVC parameter set and slice scaffolding where syntax details are confirmed.
- Replace the remaining non-VVC placeholder encode/decode path with the VVC toy encoder as it becomes more capable.
- Replace toy CABAC packets with a minimal arithmetic CABAC writer fed by the same coding-tree events.
- Use the sampled first Y/Cb/Cr values to generate residual syntax so non-black streams decode to the encoder's current lossy representative color.
- Add clean-room VPS/SPS/PPS and a first intra picture after the EOS-only NAL writer is stable.
- Replace placeholder VPS/SPS/PPS and IDR RBSP payloads with real clean-room syntax.
- Define a narrow internal packet model for coding-tree traversal.
- Add a software golden model for one small intra prediction mode.
- Add block-level RTL/software comparison through cocotb.
- Add explicit validation scripts for external decoders once output is expected to be decodable.
- Expand simulator abstraction without tying the project permanently to Icarus Verilog.

## Out Of Scope For Now

- Full VVC conformance.
- Full VVC decoder implementation.
- Imported VTM or VVdeC source code.
- CABAC completeness.
- Transform, quantization, loop filters, inter prediction, B-frames, rate control, or production RDO.
- SCC tools such as palette coding, intra block copy, BDPCM, and transform skip.
- FPGA vendor integration or proprietary EDA requirements.

## VVC Isolation

VVC-specific code belongs in isolated modules such as `src/vvc.rs` or future `src/codecs/vvc/` modules. Generic infrastructure should use names such as `bitstream`, `encoder`, `picture`, `trace`, `packet`, and `golden` where reasonable. The project should not become permanently shaped around VVC terminology when a generic abstraction is sufficient.
