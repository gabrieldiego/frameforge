# Initial Codec Target Notes

FrameForge is a general codec experimentation and hardware-acceleration lab. The first concrete target is a minimal toy VVC/H.266 encoder foundation, but the architecture should remain broad enough to support other codecs, codec-like bitstreams, decoder work, software golden models, and RTL acceleration.

## Implemented Now

- Rust crate and CLI skeleton.
- Placeholder encoder output with an explicit not-valid-bitstream marker.
- Generic bitstream utilities:
  - `BitWriter`
  - byte alignment
  - RBSP trailing bits
  - emulation-prevention byte insertion
- Basic placeholder NAL/Annex-B-style structures with TODOs for exact VVC syntax.
- `EncoderParams`, `Picture`, reconstruction buffer skeleton, and fixed block traversal.
- JSONL trace events.
- Optional external decoder wrapper that does not assume a decoder is installed.
- SystemVerilog RTL stubs with AXI-stream-style handshakes.
- cocotb/Icarus verification skeleton.

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

