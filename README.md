# FrameForge

FrameForge is an open-source hardware video-compression project with SystemVerilog RTL, a Rust software model, VVC/H.266 bitstream generation, and hardware/software verification.

FrameForge is starting with a minimal VVC/H.266 encoder foundation, but the project is not limited to VVC, H.266, screen-content coding, FPGA work, or encoding only. The long-term goal is a practical research workspace for codec block experiments, software golden models, bitstream generation, RTL acceleration, FPGA-oriented blocks, encoder and decoder research, and hardware/software co-verification.

Current status: experimental, not production-ready. The current VVC software and RTL encoders generate Annex-B VVC streams from planar 8-bit YUV 4:2:0 or 4:4:4 input. Larger pictures are emitted as 64x64 CTU-local slices, with one slice per CTU. RTL validation remains bounded by the instantiated maximum geometry parameters. The 4:2:0 path uses fixed 8x8 luma transform blocks and 4x4 chroma transform blocks with local reconstruction, fixed quantization, luma DC plus the first 4x4 low-frequency AC group, and chroma DC plus the 2x2 low-frequency AC group. The 4:4:4 path uses an experimental lossless 8x8 screen-content subset: exact repeated CUs can use CTU-local IBC by 32-bit hash match, and the remaining CUs use palette mode with up to 31 direct palette entries plus raw 8-bit escape values for additional YCbCr/GBR colors. Software, RTL, and VTM-backed validation are wired for the current subset, and unsupported syntax must remain explicit instead of being hidden in sideband payloads. AV2 infrastructure is present as a second codec target; its progress is tracked in [docs/av2/progress.md](docs/av2/progress.md).

## Current Status

- Minimal bitstream utilities and packet structures.
- Clean-room VVC/H.266 first-target modules where exact syntax is known.
- Local reconstruction concepts and software golden models.
- Block traversal and trace output for debugging experiments.
- SystemVerilog RTL blocks using stream-style handshakes.
- cocotb tests with Icarus Verilog as the first open-source simulator target.
- VTM-backed external decoder validation for the current small VVC subset.

## Repository Layout

- `src/` - Rust CLI, encoder framework, bitstream utilities, trace support, and codec software models.
- `docs/` - shared process notes plus codec-specific implementation reports.
- `docs/vvc/` and `docs/av2/` - VVC and AV2 implementation notes, including
  codec-specific synthesis baselines.
- `scripts/` - helper tools such as optional external decoder validation.
- `rtl/vvc/` - VVC SystemVerilog RTL blocks.
- `rtl/av2/` - AV2 SystemVerilog RTL blocks.
- `tb/vvc/` - VVC cocotb verification fixtures.
- `tb/av2/` - AV2 cocotb verification fixtures.
- `Makefile` - common build, test, format, RTL-test, and clean targets.

## Build

Prerequisites:

- Rust stable toolchain with `cargo` and `rustfmt`.
- Python 3.12 or 3.13 for helper scripts and cocotb tests.
- Optional RTL verification tools: cocotb and Icarus Verilog. cocotb can be installed from `requirements-dev.txt`.
- Optional viewing tool: FFmpeg/`ffplay` for inspecting raw YUV reconstructions.

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

Run the portable release sanity check:

```sh
make release-check
```

This checks Rust formatting, Rust tests, Python helper syntax, manifest loading,
smoke vector generation, and the smoke software/RTL/VTM validation set without
running synthesis.

## Quick Manual Workflow

For a first manual experiment, run the commands in this order:

1. Build the Rust encoder:

   ```sh
   make build
   ```

2. Prepare or locate the external VTM decoder:

   ```sh
   make decoder-setup
   ```

3. Generate deterministic test vectors:

   ```sh
   make test-vector-sets
   make test-vectors TEST_VECTOR_SET=smoke
   make test-vectors TEST_VECTOR_SET=sweep-420
   make test-vectors TEST_VECTOR_SET=sweep-444
   ```

4. Encode one vector by hand with `cargo run -- vvc-encode`.

5. Decode the generated `.vvc` with `make validate-decode`.

6. View the raw reconstruction with `ffplay -f rawvideo`.

7. Run `make validate INPUT=... VALIDATE_SYNTH=0` to compare software, RTL, and VTM output for that one vector.

8. Run a named regression set, such as `make validate-smoke VALIDATION_STOP_ON_FAIL=1`.

Use `VALIDATE_SYNTH=0` while experimenting with functional behavior. Synthesis is a separate, slower check; see [docs/synthesis.md](docs/synthesis.md).

## Manual VVC Streams

Generate the current smallest Annex-B stream:

```sh
cargo run -- vvc-eos --output /tmp/frameforge-eos.vvc
```

This writes only an EOS NAL unit. It is useful for testing VVC NAL header packing and Annex-B output, but it does not contain parameter sets or a picture.

Generate deterministic YUV vectors under `verification/generated/test_vectors`:

```sh
make test-vector-sets
make test-vectors TEST_VECTOR_SET=smoke
make test-vectors TEST_VECTOR_SET=sweep-420
make test-vectors TEST_VECTOR_SET=sweep-444
```

Vector sets are described by CSV manifests under `verification/test_vector_sets`. The generator also reads ignored local manifests from `verification/test_vector_sets/local`, which is where machine-specific source-crop lists belong. `make test-vector-sets` lists both committed manifests and any local manifests present on the current machine.

Useful generated vector sets:

| Set | Contents | Typical use |
|---|---|---|
| `smoke` | Small 4:2:0, 4:4:4, and short motion vectors | First sanity check |
| `all-short` | Smoke vectors plus randomized short vectors | Daily functional regression |
| `sweep-420` | Procedural black 4:2:0 vectors from 8x8 to 64x64 | Residual geometry coverage |
| `sweep-444` | 4:4:4 screen-block vectors from 8x8 to 64x64 | Palette-mode geometry coverage |
| `motion-short` | Three-frame 64x64 motion vectors | Multi-frame behavior |

The generated filenames carry metadata in this form:

```text
<name>_<width>x<height>_<frames>f[_<fps>fps]_<format>.yuv
```

For example, `stick_walk_64x64_3f_30fps_yuv420p8.yuv` means 64x64, three frames, 30 fps, planar 8-bit 4:2:0. The validation scripts can infer those values from the filename. The raw encoder can not infer them; pass `--width`, `--height`, `--frames`, and `--format` explicitly.

Encode one generated 4:2:0 motion vector by hand:

```sh
mkdir -p verification/generated/manual
cargo run -- vvc-encode \
  --input verification/generated/test_vectors/stick_walk_64x64_3f_30fps_yuv420p8.yuv \
  --width 64 --height 64 --frames 3 --format yuv420p8 \
  --output verification/generated/manual/stick_walk_64x64_3f.vvc \
  --recon verification/generated/manual/stick_walk_64x64_3f_recon.yuv
```

Decode the stream with the configured VTM decoder:

```sh
make validate-decode \
  BITSTREAM=verification/generated/manual/stick_walk_64x64_3f.vvc \
  DECODED=verification/generated/manual/stick_walk_64x64_3f_vtm.yuv
```

Inspect the bitstream NAL units and compare reconstruction checksums:

```sh
cargo run -- vvc-list \
  --input verification/generated/manual/stick_walk_64x64_3f.vvc

sha256sum \
  verification/generated/manual/stick_walk_64x64_3f_recon.yuv \
  verification/generated/manual/stick_walk_64x64_3f_vtm.yuv
```

Those two checksums should match. The `--recon` file is FrameForge's internal reconstruction, and the decoded VTM file is what an external decoder reconstructed from the emitted VVC stream.

View the 4:2:0 reconstruction with `ffplay`:

```sh
ffplay -f rawvideo -pixel_format yuv420p -video_size 64x64 -framerate 1 \
  verification/generated/manual/stick_walk_64x64_3f_recon.yuv
```

Use `-pixel_format`, not `-pix_fmt`, when feeding raw video to recent `ffplay`.

Encode and view one generated 4:4:4 palette vector:

```sh
mkdir -p verification/generated/manual
cargo run -- vvc-encode \
  --input verification/generated/test_vectors/screen_blocks_64x64_1f_yuv444p8.yuv \
  --width 64 --height 64 --frames 1 --format yuv444p8 \
  --output verification/generated/manual/screen_blocks_64x64.vvc \
  --recon verification/generated/manual/screen_blocks_64x64_recon.yuv

ffplay -f rawvideo -pixel_format yuv444p -video_size 64x64 -framerate 1 \
  verification/generated/manual/screen_blocks_64x64_recon.yuv
```

Encode any local 4:2:0 YUV file by hand:

```sh
mkdir -p verification/generated/manual
cargo run -- vvc-encode \
  --input /path/to/input_416x240_3f_yuv420p8.yuv \
  --width 416 --height 240 --frames 3 --format yuv420p8 \
  --max-width 416 --max-height 240 \
  --output verification/generated/manual/local_416x240_3f.vvc \
  --recon verification/generated/manual/local_416x240_3f_recon.yuv
```

View that reconstruction:

```sh
ffplay -f rawvideo -pixel_format yuv420p -video_size 416x240 -framerate 1 \
  verification/generated/manual/local_416x240_3f_recon.yuv
```

Local full-frame software encodes are useful for visual inspection. For RTL validation, start with generated vectors and 8x8 through 64x64 manifests before trying larger pictures.

## Validation

Validate one vector against the software encoder, RTL encoder, and VTM decoder:

```sh
make validate \
  INPUT=verification/generated/test_vectors/stick_walk_64x64_3f_30fps_yuv420p8.yuv \
  VALIDATE_SYNTH=0
```

The validation command infers resolution, frame count, and format from names such as `stick_walk_64x64_3f_30fps_yuv420p8.yuv`, `screen_blocks_64x64_1f_yuv444p8.yuv`, or `black_16x16_2f_yuv420p8.yuv`. If the filename does not carry that metadata, pass `WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv420p8`.

Validation writes generated artifacts under `verification/generated/checksums` and prints:

- SHA-256 checksums for the input, software bitstream, RTL bitstream, software reconstruction, RTL reconstruction, and VTM reconstruction when available.
- PSNR of the internal and decoded reconstructions against the input.
- Pass/fail checks that software and RTL bitstreams match exactly, software and RTL internal reconstructions match exactly, and VTM reconstruction matches the emitted picture syntax when that path is supported.

Internal reconstruction is always the reconstruction represented by the emitted VVC picture syntax. For geometries accepted by VTM, it must match the external decoder output. Unsupported features must not be represented as hidden sideband reconstruction.

For one-vector experiments, the important generated files are:

| Suffix | Meaning |
|---|---|
| `_software.vvc` | Annex-B VVC stream produced by the Rust model |
| `_rtl.vvc` | Annex-B VVC stream produced by the RTL testbench |
| `_software_internal_rec.yuv` | Rust model internal reconstruction |
| `_rtl_internal_rec.yuv` | RTL internal reconstruction |
| `_vtm_from_decodable_bitstream.yuv` | VTM reconstruction from the emitted VVC stream |

An ordinary pass ends with lines like:

```text
OK: software and RTL bitstreams match
OK: software and RTL internal reconstructions match
OK: software, RTL, and VTM reconstructions match using RTL VVC bitstream
```

If you only want software plus VTM validation, use `VALIDATE_SW_ONLY=1`. If you want the normal software/RTL/VTM comparison without synthesis, use `VALIDATE_SYNTH=0`.

`RECON_FORMAT=codec` is the default validation output mode. It keeps
reconstructions as raw codec-native planar files under `verification/generated`;
it is not a VP8 or other compressed-video mode. Use `RECON_FORMAT=png` only for
PNG-backed still-image inspection outputs, and use `RECON_FORMAT=rgb24` when a
raw RGB view is more convenient.

Useful validation targets:

```sh
make validate-smoke VALIDATION_STOP_ON_FAIL=1
make validate-all-short VALIDATION_STOP_ON_FAIL=1
make validate-sweep-420 VALIDATION_STOP_ON_FAIL=1
make validate-sweep-444 VALIDATION_STOP_ON_FAIL=1
```

`validate-sweep-420` runs generated 4:2:0 vectors from 8x8 through 64x64. `validate-sweep-444` runs generated 4:4:4 screen-content vectors from 8x8 through 64x64. Add `VALIDATION_LIMIT=<n>` for a short prefix of any named set, or `VALIDATION_WITH_SYNTH=1` only when intentionally running synthesis inside each validation case.

The high-color 4:4:4 palette escape sweep is generated from a deterministic
procedural pattern:

```sh
make test-vectors TEST_VECTOR_SET=palette-escape-444
make validate-set VALIDATION_SET=palette-escape-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

For routine cleanup or RTL feature work, use two levels of regression:

```sh
make release-check
make hardware-regression
```

`release-check` is the portable, fast sanity pass: Rust formatting/tests, Python syntax checks, smoke vector generation, and smoke validation without synthesis. `hardware-regression` is the slower hardware-facing pass: it regenerates and validates the public 4:2:0 and 4:4:4 geometry sweeps with fail-fast enabled, then runs top-encoder synthesis.

Machine-local source-crop manifests can be added to the hardware regression without committing local paths:

```sh
make hardware-regression HARDWARE_REGRESSION_EXTRA_SET=my-local-crops
```

Use `HARDWARE_REGRESSION_SYNTH=0` when you want only the functional sweeps, and `HARDWARE_REGRESSION_SYNTH_DUT=<dut>` only when intentionally synthesizing a sub-block instead of the top encoder.

## Supported Manual Inputs

The current VVC subset is deliberately narrow:

| Input | Current behavior |
|---|---|
| `yuv420p8` / `i420` | 4:2:0 residual path, lossy, validated in software/RTL/VTM |
| `yuv444p8` / `i444` | 4:4:4 screen-content path, lossless for the current 8x8 CU subset, with exact-match IBC for repeated CUs and palette fallback including raw 8-bit escape values beyond the first 31 colors |
| 10/12/16-bit YUV | Accepted by some software paths and normalized for validation, but the main RTL milestone is 8-bit |
| 4:2:2 | Parsed as a format but not the main validated milestone path |

The RTL encoder keeps `SAMPLE_BITS` and `SOURCE_SAMPLE_BITS` as explicit
interface parameters because high-bit-depth input is a planned roadmap item.
That support matters for modern sources where 10-bit or wider samples reduce
visible banding and can improve bitrate efficiency. In the current validated
hardware subset, wider input samples are still normalized to the 8-bit encode
path; treat high-bit-depth coding as future work, not an implemented feature.

Widths and heights must be even. The committed geometry sweeps currently cover 8x8 through 64x64. Larger software encodes are possible by passing `--max-width` and `--max-height`, but RTL validation requires matching `RTL_MAX_VISIBLE_WIDTH` and `RTL_MAX_VISIBLE_HEIGHT` parameters.

The RTL top-level testbench currently feeds input in fixed 8x8 CU/TU order for the validated encoder path. This keeps internal buffering small and is part of the current hardware contract.

## Troubleshooting

If `make validate-decode` cannot find VTM, run:

```sh
make decoder-setup
```

If you want to crop vectors from a local raw YUV sequence, add a CSV manifest under `verification/test_vector_sets/local`. That directory is ignored by git because local manifests can contain machine-specific paths. See `verification/test_vector_sets/README.md` for the manifest format.

```sh
make test-vectors TEST_VECTOR_SET=my-local-crops
```

If `make validate INPUT=...` rejects the input size, check the filename metadata or pass explicit overrides:

```sh
make validate INPUT=/path/to/vector.yuv WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv420p8 VALIDATE_SYNTH=0
```

If `ffplay` says `Option not found` for `pix_fmt`, use `-pixel_format`:

```sh
ffplay -f rawvideo -pixel_format yuv420p -video_size 64x64 -framerate 1 recon.yuv
```

If validation prints `SKIP: VTM crashed`, only the external decoder comparison was skipped. The same run can still validate software/RTL bitstream and internal reconstruction equality.

## RTL / cocotb

The initial simulator target is Icarus Verilog through cocotb:

```sh
make rtl-test
```

Run the RTL generated VVC stream check:

```sh
make rtl-test DUT=vvc-encoder \
  RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 \
  RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64
```

Run the local coding-tree scheduler check without generating a complete stream:

```sh
make rtl-test DUT=vvc-coding-tree-scheduler
```

Run the same RTL VVC encoder with wider input sample buses:

```sh
make rtl-test DUT=vvc-encoder RTL_SAMPLE_BITS=10
make rtl-test DUT=vvc-encoder RTL_SAMPLE_BITS=12
make rtl-test DUT=vvc-encoder RTL_SAMPLE_BITS=16
```

Run the same RTL VVC encoder with wider chroma input planes:

```sh
make rtl-test DUT=vvc-encoder RTL_CHROMA_FORMAT_IDC=3 \
  RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 \
  RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64
```

For end-to-end bitstream comparison, prefer `make validate INPUT=... VALIDATE_SYNTH=0`; it drives the same input through the Rust encoder and the RTL testbench, then compares the exact Annex-B stream and reconstruction.

The Makefile uses variables so other simulators can be introduced later:

```sh
make rtl-test SIM=icarus TOPLEVEL_LANG=verilog
```

## External Decoder Validation

External decoder validation is wired for the current small VVC subset. The `vvc-eos` command emits only a VVC EOS NAL unit. The `vvc-encode` command assembles VTM-decodable streams for the current subset, using internally generated sequence and picture NALs plus CABAC-coded slice entropy. Larger software pictures are emitted as one CTU-local slice per 64x64 CTU. Non-4:4:4 inputs use the current 4:2:0 residual path; 4:4:4 inputs use the current lossless screen-content path with CTU-local exact-match IBC and palette fallback with raw escape values. This is still not a conformance claim: the syntax subset is narrow, residual AC coding is intentionally limited to low-frequency coefficients, IBC search is CTU-local and hash-exact only, palette heuristics are intentionally simple, and broader profile/tool combinations are intentionally unsupported.

FrameForge looks for VVC decoder resources in this order:

- `FRAMEFORGE_DECODER`: complete decoder command, optionally with fixed arguments.
- `FRAMEFORGE_VTM_DECODER`: direct path to a built VTM decoder executable.
- `FRAMEFORGE_VTM_ENCODER`: direct path to a built VTM encoder executable.
- `FRAMEFORGE_VTM_ROOT`: path to an existing VTM source/build tree to search.
- `verification/codecs/vvc/reference/vtm`: automatically cloned and built when no configured decoder is found. The helper still accepts the legacy `verification/reference/vtm` location when it already exists.

The automatic VVC/VTM setup can be customized:

- `FRAMEFORGE_REF_DIR`: parent directory for downloaded validation tools.
- `FRAMEFORGE_VTM_REPO`: VTM git repository URL.
- `FRAMEFORGE_VTM_REF`: optional VTM branch or tag.
- `FRAMEFORGE_VTM_BUILD_DIR`: CMake build directory.
- `FRAMEFORGE_VTM_BUILD_TYPE`: CMake build type, default `Release`.
- `FRAMEFORGE_BUILD_JOBS`: optional build parallelism.
- `FRAMEFORGE_GENERATED_DIR`: local generated input directory for helper scripts.

For AV2, the same helper can prepare AVM:

- `FRAMEFORGE_AV2_ROOT` / `FRAMEFORGE_AVM_ROOT`: existing AVM source/build tree.
- `FRAMEFORGE_AV2_DECODER` / `FRAMEFORGE_AVM_DECODER`: direct path to `avmdec` or `aomdec`.
- `FRAMEFORGE_AV2_ENCODER` / `FRAMEFORGE_AVM_ENCODER`: direct path to `avmenc` or `aomenc`.
- `FRAMEFORGE_AV2_REPO` / `FRAMEFORGE_AVM_REPO`: AVM git repository URL.
- `FRAMEFORGE_AV2_REF` / `FRAMEFORGE_AVM_REF`: optional branch or tag.
- `FRAMEFORGE_AV2_ENCODER_CMD` / `FRAMEFORGE_AVM_ENCODER_CMD`: full encoder command template for local AVM command-line differences.

AV2 validation is reference-only for now: `make validate CODEC=av2 ...` runs the AVM reference encode/decode path and then returns failure because FrameForge AV2 software/RTL bitstream generation is not implemented yet. See [docs/av2/progress.md](docs/av2/progress.md) for the current AV2 checkpoint list.

Prepare a decoder:

```sh
make decoder-setup
make decoder-setup CODEC=av2
```

```sh
FRAMEFORGE_DECODER=/path/to/decoder scripts/validate_decode.py --codec vvc out.vvc --output decoded.yuv
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

Reference encode through AVM:

```sh
make reference-av2 \
  INPUT=path/to/input_8x8_1f_yuv444p8.yuv \
  BITSTREAM=out.av2 RECON=rec.yuv \
  WIDTH=8 HEIGHT=8 FRAMES=1 FORMAT=yuv444p8
```

These paths use external reference encoders and do not mean FrameForge's Rust encoders implement the same toolsets. The helpers fail gracefully if the configured decoder or encoder cannot be found or run.

## Non-Goals For The Initial Milestone

- No full VVC encoder.
- No full VVC decoder.
- No conformance claims.
- No VTM or VVdeC source import.
- No inter prediction, B-frames, rate control, real RDO, or compression optimization.
- Screen-content coding is still early: an experimental 4:4:4 palette and exact-match IBC subset exists, but full IBC search/window handling, BDPCM, transform skip, and related tools are not implemented yet.

## Contributing

See `CONTRIBUTING.md`. The short version: keep the early project clean, small, explicit about unsupported behavior, and free of imported reference-code implementations.

## License

FrameForge is licensed under either of:

- Apache License, Version 2.0
- MIT License

at your option.
