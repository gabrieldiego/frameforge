# FrameForge

FrameForge is an open-source lab for video compression, bitstream generation, RTL codec blocks, and hardware/software verification.

FrameForge is starting with a minimal VVC/H.266 encoder foundation, but the project is not limited to VVC, H.266, screen-content coding, FPGA work, or encoding only. The long-term goal is a practical research workspace for codec block experiments, software golden models, bitstream generation, RTL acceleration, FPGA-oriented blocks, encoder and decoder research, and hardware/software co-verification.

Current status: skeleton, experimental, not production-ready, and not conforming. The encoder currently writes a placeholder file with an explicit `FRAMEFORGE_PLACEHOLDER_NOT_A_VALID_CODEC_BITSTREAM` marker. It is infrastructure for future work, not a decodable VVC bitstream.

## Near-Term Direction

- Minimal bitstream utilities and packet structures.
- Clean-room VVC/H.266 first-target modules where exact syntax is known.
- Local reconstruction concepts and software golden models.
- Block traversal and trace output for debugging experiments.
- SystemVerilog RTL stubs using AXI-stream-style handshakes.
- cocotb tests with Icarus Verilog as the first open-source simulator target.
- Optional external decoder validation once generated streams become meaningful.

## Repository Layout

- `src/` - Rust CLI, encoder framework, bitstream utilities, trace support, and VVC placeholders.
- `docs/` - lightweight subset and design notes.
- `scripts/` - helper tools such as optional external decoder validation.
- `rtl/` - SystemVerilog packages and placeholder codec blocks.
- `tb/` - cocotb verification skeleton.
- `Makefile` - common build, test, format, RTL-test, and clean targets.

## Build

```sh
make build
```

Equivalent Rust command:

```sh
cargo build
```

## Test

```sh
make test
```

Equivalent Rust command:

```sh
cargo test
```

## CLI

```sh
cargo run -- \
  --input input.yuv \
  --width 64 \
  --height 64 \
  --format yuv420p8 \
  --output out.ffbs \
  --trace trace.jsonl
```

Supported placeholder input formats are `yuv420p8` and `gray8`.

## RTL / cocotb

The initial simulator target is Icarus Verilog through cocotb:

```sh
make rtl-test
```

The Makefile uses variables so other simulators can be introduced later:

```sh
make rtl-test SIM=icarus TOPLEVEL_LANG=verilog
```

## External Decoder Validation

External decoder validation is planned but not guaranteed yet because FrameForge does not currently emit a valid codec bitstream.

```sh
FRAMEFORGE_DECODER=/path/to/decoder scripts/validate_decode.py out.vvc --output decoded.yuv
```

The helper fails gracefully if `FRAMEFORGE_DECODER` is not set or the decoder cannot be run.

## Non-Goals For The Initial Milestone

- No full VVC encoder.
- No full VVC decoder.
- No conformance claims.
- No VTM or VVdeC source import.
- No inter prediction, B-frames, rate control, real RDO, or compression optimization.
- No screen-content coding tools yet; palette coding, intra block copy, BDPCM, transform skip, and related techniques are planned areas only.

