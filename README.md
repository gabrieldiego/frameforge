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
  --input input.yuv \
  --width 64 \
  --height 64 \
  --format yuv420p8 \
  --output out.ffbs \
  --trace trace.jsonl
```

Supported placeholder input formats are `yuv420p8` and `gray8`.

The output is intentionally marked as placeholder data and is not a valid VVC/H.266 or other codec bitstream.

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

FrameForge looks for decoder resources in this order:

- `FRAMEFORGE_DECODER`: complete decoder command, optionally with fixed arguments.
- `FRAMEFORGE_VTM_DECODER`: direct path to a built VTM decoder executable.
- `FRAMEFORGE_VTM_ROOT`: path to an existing VTM source/build tree to search.
- `verification/reference/vtm`: automatically cloned and built when no configured decoder is found.

The automatic VTM setup can be customized:

- `FRAMEFORGE_REF_DIR`: parent directory for downloaded validation tools.
- `FRAMEFORGE_VTM_REPO`: VTM git repository URL.
- `FRAMEFORGE_VTM_REF`: optional VTM branch or tag.
- `FRAMEFORGE_VTM_BUILD_DIR`: CMake build directory.
- `FRAMEFORGE_VTM_BUILD_TYPE`: CMake build type, default `Release`.
- `FRAMEFORGE_BUILD_JOBS`: optional build parallelism.

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
