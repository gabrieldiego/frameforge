# AV2 Synthesis Baselines

This file records AV2-specific synthesis measurements. The shared command
wrapper is documented in [../synthesis.md](../synthesis.md), but AV2 area,
timing, elapsed time, and memory results are tracked separately from VVC.

## 2026-06-12 Integration Shell

Configuration:

- command: `make synth CODEC=av2`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB

Result:

- Yosys synthesis passed in 3.6 seconds.
- Peak child RSS observed by the synthesis runner was 127.45 MiB.
- Post-synthesis critical-path reporting completed in 0.1 seconds and reported
  path length 1.

This measurement covers only the AV2 streaming entry point and explicit
unsupported-encode response. It is useful as a routing and synthesis-wrapper
baseline, not as an estimate of a real AV2 encoder implementation.

## 2026-06-13 Structured Black + First Luma Palette

Configuration:

- command: `make synth CODEC=av2`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- supported RTL input subset: planar 8-bit 4:4:4, up to 64x64, black frames
  plus the deterministic 64x64 two-color luma-palette bars smoke vector.

Validation before synthesis:

```sh
cargo test av2 -- --nocapture
make -B rtl-test CODEC=av2 DUT=av2-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
make validate-set CODEC=av2 VALIDATION_SET=sweep-black-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set CODEC=av2 VALIDATION_SET=av2-palette-luma-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

Result:

- Yosys synthesis passed in 34.6 seconds.
- Peak child RSS observed by the synthesis runner was 302.04 MiB.
- Post-synthesis critical-path reporting completed in 4.8 seconds and reported
  path length 62.
- The critical path remained in the existing partition/range-coder logic, not
  the first palette symbolizer.

Flattened Xilinx-cell estimate from
`yosys -p 'read_json synth/out/arty-z7-10/ff_av2_encoder/ff_av2_encoder.json; hierarchy -top ff_av2_encoder; flatten; stat -tech xilinx'`:

| Metric | Count |
|---|---:|
| Cells | 8076 |
| Estimated LCs | 3387 |
| CARRY4 | 387 |
| DSP48E1 | 14 |
| FDCE | 775 |
| FDPE | 32 |
| FDRE | 450 |
| LUT1 | 30 |
| LUT2 | 1123 |
| LUT3 | 756 |
| LUT4 | 523 |
| LUT5 | 671 |
| LUT6 | 1437 |
| MUXF7 | 543 |
| MUXF8 | 173 |
| RAMB18E1 | 3 |

This is the first useful AV2 encoder synthesis baseline. Comparing it with the
integration shell is only useful to show expected growth from unsupported
plumbing into real generated tile syntax; the shell was not a real encoder area
estimate.

## 2026-06-14 General Luma Palette + Block Packets

Measured after replacing the narrow luma-bars classifier with the general
8x8-block luma palette analyzer and changing the AV2 RTL input contract to the
same visible 8x8 Y/U/V packet shape used by the VVC 4:4:4 path. The codec
walkers remain independent internally; this only aligns the top-level
testbench-facing packet shape.

Configuration:

- command: `make synth CODEC=av2`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- supported RTL input subset: 8-bit 4:4:4, up to 64x64, black frames, and
  luma-palette 8x8 blocks with up to eight luma entries per block.

Validation before synthesis:

```sh
make validate CODEC=av2 \
  INPUT=verification/generated/test_vectors/av2_luma_palette_bars_64x64_1f_yuv444p8.yuv \
  WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv444p8 VALIDATE_SYNTH=0
make test-vectors TEST_VECTOR_SET=screenshot-sweep-444
make validate-set CODEC=av2 VALIDATION_SET=screenshot-sweep-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

Result:

- Yosys synthesis passed in 304.8 seconds.
- Peak child RSS observed by the synthesis runner was 1094.01 MiB.
- Runtime exceeded the 300 second review threshold by 4.8 seconds, but stayed
  inside the 600 second hard timeout and 3072 MiB memory cap.
- Post-synthesis critical-path reporting completed in 96.9 seconds with peak
  child RSS of 1326.54 MiB and reported topological path length 129.
- The reported longest path starts in `palette_analyzer.block_palette_color_q`,
  passes through `ff_av2_luma_palette_symbolizer` delta-bit calculation, and
  reaches the range-coder `low_q` path.

Flattened Xilinx-cell estimate from
`yosys -p 'read_json synth/out/arty-z7-10/ff_av2_encoder/ff_av2_encoder.json; hierarchy -top ff_av2_encoder; flatten; stat -tech xilinx'`:

| Metric | Count |
|---|---:|
| Cells | 79770 |
| Estimated LCs | 33892 |
| CARRY4 | 508 |
| DSP48E1 | 11 |
| FDCE | 18785 |
| FDPE | 99 |
| FDRE | 448 |
| LUT1 | 553 |
| LUT2 | 2549 |
| LUT3 | 2732 |
| LUT4 | 5757 |
| LUT5 | 9481 |
| LUT6 | 15922 |
| MUXF7 | 3361 |
| MUXF8 | 300 |
| RAMB36E1 | 4 |

Compared with the immediately preceding generalized luma-palette working run
before the input-packet alignment, the topological path stayed at 129, main
synthesis RSS was effectively flat, and critical-path reporting was about 8.9
seconds faster. Main synthesis runtime increased by about 9.8 seconds.

Compared with the current documented VVC top encoder 4:4:4 BDPCM baseline
(`docs/vvc/synthesis.md`, June 11, 2026), this AV2 subset is smaller but less
complete:

| Metric | AV2 | VVC | AV2 / VVC |
|---|---:|---:|---:|
| Synthesis time | 304.8 s | 376.3 s | 81.0% |
| Peak synthesis RSS | 1094.01 MiB | 1882.95 MiB | 58.1% |
| Cells | 79770 | 118404 | 67.4% |
| Estimated LCs | 33892 | 45381 | 74.7% |
| Topological path length | 129 | 55 | 234.5% |

The area comparison is encouraging only as a checkpoint, not as an efficiency
claim, because the VVC encoder currently implements more coding tools. The AV2
critical path is the clearer optimization target before adding much more syntax.
Until AV2 reaches approximate feature parity with the current VVC screen-content
subset, any AV2 top synthesis that exceeds the documented VVC top in cells,
estimated LCs, memory, or runtime should be treated as a runaway-design warning
and optimized before more syntax is added.

## Retired Bring-Up Measurements

Temporary AV2 fixed-output emitters existed during validation plumbing bring-up.
Those measurements are intentionally retired because the source streams and
trace-derived entropy data were removed. Future synthesis baselines should only
cover implementations that generate bitstream content from named, spec-auditable
syntax decisions.
