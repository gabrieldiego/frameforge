# FrameForge

FrameForge is an open-source lab for video compression, bitstream generation, RTL codec blocks, and hardware/software verification.

FrameForge is starting with a minimal VVC/H.266 encoder foundation, but the project is not limited to VVC, H.266, screen-content coding, FPGA work, or encoding only. The long-term goal is a practical research workspace for codec block experiments, software golden models, bitstream generation, RTL acceleration, FPGA-oriented blocks, encoder and decoder research, and hardware/software co-verification.

Current status: skeleton, experimental, not production-ready, and not conforming. The current VVC toy path can generate a tiny 4x4 stream for software/RTL/VTM validation from planar YUV 4:2:0, 4:2:2, or 4:4:4 input at 8, 10, 12, or 16 bits. The 4:4:4 8-bit input path now emits a first lossless FrameForge palette-token sideband with sixteen per-pixel YUV entries and 4-bit indices. The VTM-visible picture is still the current toy VVC syntax, so this is an SCC foundation step rather than conforming VVC palette coding.

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

Generate the toy 1-frame 4x4 VVC validation stream:

```sh
dd if=/dev/zero of=/tmp/frameforge-toy-4x4-1f.yuv bs=24 count=1
cargo run -- vvc-toy-4x4-video --input /tmp/frameforge-toy-4x4-1f.yuv --frames 1 --output /tmp/frameforge-toy-4x4-1f.vvc
make validate-decode BITSTREAM=/tmp/frameforge-toy-4x4-1f.vvc DECODED=/tmp/frameforge-toy-4x4-1f-dec.yuv
```

This reads a 4x4 planar YUV input and writes a generated Annex-B VVC stream for one IDR picture. FrameForge emits the sequence header, a color-derived Filler Data NAL unit, optional toy palette-token sideband for 4:4:4 input, picture header, slice header, and toy residual packets internally. The VTM-decoded luma is the nearest value on the current toy quantization ladder; decoded chroma is currently quantized to the narrow set encoded by the toy syntax.

Decode the experimental FrameForge palette sideband losslessly for a 4x4 `yuv444p8` stream:

```sh
cargo run -- vvc-toy-4x4-decode --input /tmp/frameforge-toy-4x4-1f.vvc --output /tmp/frameforge-toy-4x4-1f-palette.yuv
```

This decoder reads the reserved `FFPL` sideband. It is a FrameForge experiment and is separate from VTM, which ignores the sideband.

Generate the toy 2-frame 4x4 VVC validation stream:

```sh
dd if=/dev/zero of=/tmp/frameforge-toy-4x4-2f.yuv bs=48 count=1
cargo run -- vvc-toy-4x4-video --input /tmp/frameforge-toy-4x4-2f.yuv --frames 2 --output /tmp/frameforge-toy-4x4-2f.vvc
make validate-decode BITSTREAM=/tmp/frameforge-toy-4x4-2f.vvc DECODED=/tmp/frameforge-toy-4x4-2f-dec.yuv
```

This stream emits one SPS/PPS sequence header followed by two picture slices. It decodes to two 4x4 YUV420p8 frames and is useful for proving that the software and RTL output paths can generate the same short video stream before clean-room VVC picture syntax is complete.

Validate the software stream, RTL stream, and VTM reconstructions with SHA-256 checksums:

```sh
mkdir -p /tmp/frameforge
dd if=/dev/zero of=/tmp/frameforge/black_4x4_1f_yuv420p8.yuv bs=24 count=1
make validate INPUT=/tmp/frameforge/black_4x4_1f_yuv420p8.yuv

dd if=/dev/zero of=/tmp/frameforge/black_4x4_2f_yuv420p8.yuv bs=48 count=1
make validate INPUT=/tmp/frameforge/black_4x4_2f_yuv420p8.yuv
```

The validation command infers resolution, frame count, and format from names such as `black_4x4_2f_yuv420p8.yuv`, `color_4x4_1f_yuv422p10le.yuv`, or `color_4x4_1f_yuv444p8.yuv`. You can override them with `WIDTH=4 HEIGHT=4 FRAMES=2 FORMAT=yuv422p8`. Supported toy input formats are planar `yuv420p`, `yuv422p`, and `yuv444p` at 8, 10, 12, or 16 bits, with common `i420`, `i422`, `i444`, `i010`, `i210`, and `i410` style aliases. Non-420 and high-bit-depth paths normalize samples into the current 8-bit 4:2:0 toy syntax before validation. Validation feeds the input YUV into both the software toy encoder and the RTL testbench, checks that their bitstreams match, taps the software and RTL internal reconstructions, decodes the RTL bitstream with VTM, and checks that the three reconstruction checksums match. For single-frame `yuv444p8`, validation also decodes the FrameForge palette sideband and checks that it matches the input losslessly.

Internal reconstruction is always the reconstruction of the emitted bitstream. If a feature is not encoded into decoded picture syntax yet, the internal reconstruction must match what VTM decodes, not the intended input approximation.

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

Run the RTL VVC skeleton byte-format check:

```sh
make rtl-test DUT=vvc-skeleton
```

Run the RTL generated VVC toy stream check:

```sh
make rtl-test DUT=vvc-toy4x4
```

Run the same RTL toy encoder with wider input sample buses:

```sh
make rtl-test DUT=vvc-toy4x4 RTL_SAMPLE_BITS=10
make rtl-test DUT=vvc-toy4x4 RTL_SAMPLE_BITS=12
make rtl-test DUT=vvc-toy4x4 RTL_SAMPLE_BITS=16
```

Run the same RTL toy encoder with wider chroma input planes:

```sh
make rtl-test DUT=vvc-toy4x4 RTL_CHROMA_FORMAT_IDC=2
make rtl-test DUT=vvc-toy4x4 RTL_CHROMA_FORMAT_IDC=3
```

The Makefile uses variables so other simulators can be introduced later:

```sh
make rtl-test SIM=icarus TOPLEVEL_LANG=verilog
```

## External Decoder Validation

External decoder validation is partially wired. The `vvc-eos` command emits only a VVC EOS NAL unit, and `vvc-skeleton` uses placeholder RBSP payloads. The `vvc-toy-4x4-video` command assembles a tiny VTM-accepted stream from internally scheduled sequence and picture NALs, a color-derived Filler Data NAL, an experimental 4:4:4 palette sideband when applicable, and quantized toy residual payloads; it is an incremental validation path, not a complete clean-room VVC encoder yet.

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
- Screen-content coding is only at the first scaffolding step: the 4:4:4 toy path has a lossless FrameForge palette sideband, but conforming VVC palette coding, intra block copy, BDPCM, transform skip, and related tools are still future work.

## Contributing

See `CONTRIBUTING.md`. The short version: keep the early project clean, small, explicit about unsupported behavior, and free of imported reference-code implementations.

## License

FrameForge is licensed under either of:

- Apache License, Version 2.0
- MIT License

at your option.
