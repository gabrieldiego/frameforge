# FrameForge

FrameForge is an open-source lab for video compression, bitstream generation, RTL codec blocks, and hardware/software verification.

FrameForge is starting with a minimal VVC/H.266 encoder foundation, but the project is not limited to VVC, H.266, screen-content coding, FPGA work, or encoding only. The long-term goal is a practical research workspace for codec block experiments, software golden models, bitstream generation, RTL acceleration, FPGA-oriented blocks, encoder and decoder research, and hardware/software co-verification.

Current status: skeleton, experimental, not production-ready, and not conforming. The software path can now write and read a tiny FrameForge experimental `ffbs` raw `gray8` intra bitstream. This is useful for end-to-end infrastructure, but it is not a VVC/H.266 bitstream.

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

Prerequisites:

- Rust stable toolchain with `cargo` and `rustfmt`.
- Python 3 for helper scripts and cocotb tests.
- Optional RTL verification tools: cocotb and Icarus Verilog. cocotb can be installed from `requirements-dev.txt`.

Check local tool availability:

```sh
make check-tools
```

For Ubuntu install suggestions without running Make:

```sh
python3 scripts/configure_dev_env.py
```

On Ubuntu, install Python packages such as cocotb in a virtual environment. cocotb currently rejects Python 3.14, so use Python 3.13 or 3.12 for this venv.

If `python3.13` is available from apt:

```sh
sudo apt update && sudo apt install -y python3.13 python3.13-venv python3-pip
rm -rf .venv
python3.13 -m venv .venv
. .venv/bin/activate
python -m pip install -U pip
python -m pip install -r requirements-dev.txt
```

If apt does not provide `python3.13`, use `uv` to install a managed Python:

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
~/.local/bin/uv python install 3.13
rm -rf .venv
~/.local/bin/uv venv --python 3.13 .venv
~/.local/bin/uv pip install --python .venv/bin/python -r requirements-dev.txt
```

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
  --input input.y \
  --width 64 \
  --height 64 \
  --format gray8 \
  --output out.ffbs \
  --trace trace.jsonl
```

Supported placeholder input formats are `yuv420p8` and `gray8`.

The current minimal encoder supports the experimental `ffbs` raw `gray8` path. `yuv420p8` is accepted by the CLI/parser as a planned input format but is not encodable by the current minimal `ffbs` encoder.

Decode an `ffbs` stream back to raw gray samples:

```sh
cargo run -- decode --input out.ffbs --output decoded.y
```

Minimal 4x4 round trip:

```sh
printf '\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020' > /tmp/frameforge-4x4.y
cargo run -- encode --input /tmp/frameforge-4x4.y --width 4 --height 4 --format gray8 --output /tmp/frameforge-4x4.ffbs --trace /tmp/frameforge-4x4.jsonl
cargo run -- decode --input /tmp/frameforge-4x4.ffbs --output /tmp/frameforge-4x4.decoded.y
cmp /tmp/frameforge-4x4.y /tmp/frameforge-4x4.decoded.y
```

Generate the current smallest VVC-shaped Annex-B stream:

```sh
cargo run -- vvc-eos --output /tmp/frameforge-eos.vvc
```

This writes only an EOS NAL unit. It is useful for testing VVC NAL header packing and Annex-B output, but it does not contain parameter sets or a picture.

Generate a larger VVC-shaped scaffold stream:

```sh
cargo run -- vvc-skeleton --output /tmp/frameforge-skeleton.vvc
```

This writes VPS, SPS, PPS, IDR_N_LP, EOS, and EOB NAL units with correct Annex-B start codes and VVC NAL unit headers. The RBSP payloads are deliberately placeholder `rbsp_trailing_bits` only, so this is not a decodable VVC picture stream yet.

Generate the fixed 4x4 black VVC validation fixture:

```sh
cargo run -- vvc-fixture-4x4-black --output /tmp/frameforge-fixture-4x4.vvc
make validate-decode BITSTREAM=/tmp/frameforge-fixture-4x4.vvc DECODED=/tmp/frameforge-fixture-4x4-dec.yuv
```

This writes a fixed Annex-B VVC stream for one black 4x4 YUV420p8 IDR picture. It is a decoder-validation fixture derived from the external VTM reference path, not FrameForge's clean-room VVC encoder implementation.

Generate the fixed 2-frame 4x4 black VVC validation fixture:

```sh
cargo run -- vvc-fixture-4x4-black-video --output /tmp/frameforge-fixture-4x4-2f.vvc
make validate-decode BITSTREAM=/tmp/frameforge-fixture-4x4-2f.vvc DECODED=/tmp/frameforge-fixture-4x4-2f-dec.yuv
```

This stream decodes to two 4x4 YUV420p8 frames and is useful for proving that the software and RTL output paths can represent a short video stream before clean-room VVC picture syntax is implemented.

Inspect NAL headers in any Annex-B VVC stream:

```sh
cargo run -- vvc-list --input /tmp/frameforge-skeleton.vvc
cargo run -- vvc-list --input /tmp/frameforge-reference-4x4.vvc
```

Generate a real minimal VVC stream with the external VTM reference encoder:

```sh
make reference-vvc BITSTREAM=/tmp/frameforge-reference-4x4.vvc RECON=/tmp/frameforge-reference-4x4-rec.yuv
make validate-decode BITSTREAM=/tmp/frameforge-reference-4x4.vvc DECODED=/tmp/frameforge-reference-4x4-dec.yuv
```

This path uses VTM as an external validation/reference tool and does not mean FrameForge's own Rust encoder emits conforming VVC yet.

## RTL / cocotb

The initial simulator target is Icarus Verilog through cocotb:

```sh
make rtl-test
```

Run the RTL `ffbs` byte-format check:

```sh
make rtl-test DUT=ffbs
```

Run the RTL VVC skeleton byte-format check:

```sh
make rtl-test DUT=vvc-skeleton
```

Run the RTL fixed VVC fixture byte-format check:

```sh
make rtl-test DUT=vvc-fixture4x4
```

Run the RTL fixed 2-frame VVC fixture byte-format check:

```sh
make rtl-test DUT=vvc-fixture4x4-2frame
```

The Makefile uses variables so other simulators can be introduced later:

```sh
make rtl-test SIM=icarus TOPLEVEL_LANG=verilog
```

## External Decoder Validation

External decoder validation is partially wired. The current `ffbs` stream is decoded by FrameForge itself, `vvc-eos` emits only a VVC EOS NAL unit, and `vvc-skeleton` uses placeholder RBSP payloads. The `vvc-fixture-4x4-black` command emits a fixed VTM-derived validation fixture that VTM can decode, but this is not yet a real FrameForge VVC encoder path.

FrameForge looks for decoder resources in this order:

- `FRAMEFORGE_DECODER`: complete decoder command, optionally with fixed arguments.
- `FRAMEFORGE_VTM_DECODER`: direct path to a built VTM decoder executable.
- `FRAMEFORGE_VTM_ENCODER`: direct path to a built VTM encoder executable.
- `FRAMEFORGE_VTM_ROOT`: path to an existing VTM source/build tree to search.
- `verification/reference/vtm`: automatically cloned and built when no configured decoder is found.

The automatic VTM setup can be customized:

- `FRAMEFORGE_REF_DIR`: parent directory for downloaded validation tools.
- `FRAMEFORGE_VTM_REPO`: VTM git repository URL.
- `FRAMEFORGE_VTM_REF`: optional VTM branch or tag.
- `FRAMEFORGE_VTM_BUILD_DIR`: CMake build directory.
- `FRAMEFORGE_VTM_BUILD_TYPE`: CMake build type, default `Release`.
- `FRAMEFORGE_BUILD_JOBS`: optional build parallelism.
- `FRAMEFORGE_GENERATED_DIR`: local generated input directory for helper scripts.

Prepare a decoder:

```sh
make decoder-setup
```

```sh
FRAMEFORGE_DECODER=/path/to/decoder scripts/validate_decode.py out.vvc --output decoded.yuv
```

or:

```sh
make validate-decode BITSTREAM=out.vvc DECODED=decoded.yuv
```

Reference encode through VTM:

```sh
make reference-vvc BITSTREAM=out.vvc RECON=rec.yuv
make reference-vvc BITSTREAM=out-2f.vvc RECON=rec-2f.yuv FRAMES=2
```

The helper fails gracefully if `FRAMEFORGE_DECODER` is not set or the decoder cannot be run.

## Non-Goals For The Initial Milestone

- No full VVC encoder.
- No full VVC decoder.
- No conformance claims.
- No VTM or VVdeC source import.
- No inter prediction, B-frames, rate control, real RDO, or compression optimization.
- No screen-content coding tools yet; palette coding, intra block copy, BDPCM, transform skip, and related techniques are planned areas only.

## Contributing

See `CONTRIBUTING.md`. The short version: keep the early project clean, small, explicit about unsupported behavior, and free of imported reference-code implementations.

## License

FrameForge is licensed under either of:

- Apache License, Version 2.0
- MIT License

at your option.
