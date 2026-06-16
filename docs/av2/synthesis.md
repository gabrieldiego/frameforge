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

## 2026-06-14 Luma Palette + Chroma BDPCM

Measured after adding the 4:4:4 chroma horizontal-BDPCM path and moving the
stored U/V sample window into `ff_av2_chroma_sample_store`. The store is kept as
its own hierarchy so Yosys maps the two 4096x8 chroma sample planes into RAM
instead of expanding them into a full-superblock combinational mux.

Configuration:

- command: `make synth CODEC=av2`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- supported RTL input subset: 8-bit 4:4:4, up to 64x64, black frames,
  luma-palette 8x8 blocks with up to eight luma entries per block, and
  horizontal-BDPCM chroma residuals.

Validation before synthesis:

```sh
make rtl-test CODEC=av2 DUT=av2-encoder \
  RTL_VISIBLE_WIDTH=8 RTL_VISIBLE_HEIGHT=8 \
  RTL_CHROMA_FORMAT_IDC=3 RTL_SAMPLE_BITS=8 RTL_SOURCE_SAMPLE_BITS=8
make validate CODEC=av2 \
  INPUT=verification/generated/test_vectors/bdpcm_horizontal_8x8_1f_yuv444p8.yuv \
  WIDTH=8 HEIGHT=8 FRAMES=1 FORMAT=yuv444p8 VALIDATE_SYNTH=0
make validate-set CODEC=av2 \
  VALIDATION_SET=bdpcm-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Result:

- Yosys synthesis passed in 316.6 seconds.
- Peak child RSS observed by the synthesis runner was 1185.96 MiB.
- Runtime exceeded the 300 second review threshold by 16.6 seconds, but stayed
  inside the 600 second hard timeout and 3072 MiB memory cap.
- Post-synthesis critical-path reporting completed in 101.5 seconds with peak
  child RSS of 1283.70 MiB and reported topological path length 129.
- The longest top-level path remains the existing luma-palette/range-coder
  path. The isolated `ff_av2_chroma_sample_store` path length was 1.

Flattened Xilinx-cell estimate from
`yosys -p 'read_json synth/out/arty-z7-10/ff_av2_encoder/ff_av2_encoder.json; hierarchy -top ff_av2_encoder; flatten; stat -tech xilinx'`:

| Metric | Count |
|---|---:|
| Cells | 89138 |
| Estimated LCs | 37418 |
| CARRY4 | 1276 |
| DSP48E1 | 11 |
| FDCE | 19882 |
| FDPE | 103 |
| FDRE | 448 |
| LUT1 | 557 |
| LUT2 | 4350 |
| LUT3 | 3900 |
| LUT4 | 5743 |
| LUT5 | 9765 |
| LUT6 | 18010 |
| MUXF7 | 3633 |
| MUXF8 | 715 |
| RAMB36E1 | 6 |

Delta from the immediately preceding generalized luma-palette baseline:

| Metric | Previous | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 304.8 s | 316.6 s | +11.8 s |
| Peak synthesis RSS | 1094.01 MiB | 1185.96 MiB | +91.95 MiB |
| Cells | 79770 | 89138 | +9368 |
| Estimated LCs | 33892 | 37418 | +3526 |
| Topological path length | 129 | 129 | 0 |
| RAMB36E1 | 4 | 6 | +2 |

The first implementation briefly caused synthesis to time out because the
analyzer exported U/V samples through wide combinational indexed arrays. The
current baseline fixes that by fetching one 4x4 chroma TXB at a time from the
RAM-backed chroma store before starting the BDPCM symbolizer.

## 2026-06-15 Luma Palette + Lossless Residual

Measured after adding the luma residual path for palette-predicted blocks.
Luma is still signalled through AV2 palette syntax, but the palette predictor
is followed by lossless `TX_4X4` coefficient syntax so blocks with more than
eight luma colors reconstruct exactly. Chroma remains horizontal BDPCM with
lossless coefficient coding.

This pass also replaced the analyzer's wide per-cycle dynamic palette query
with a one-leaf metadata cache. The top encoder now loads the current 8x8
leaf's palette colors, indices, row flags, and cache size before entering
`ST_LEAF`. That trades a few block RAMs for a much smaller live combinational
query path.

Configuration:

- command: `make synth CODEC=av2`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- supported RTL input subset: 8-bit 4:4:4, up to 64x64, black frames,
  luma-palette 8x8 predictors with lossless luma residuals, and
  horizontal-BDPCM chroma residuals.

Validation before synthesis:

```sh
make validate CODEC=av2 \
  INPUT=verification/generated/test_vectors/palette_escape_8x8_1f_yuv444p8.yuv \
  WIDTH=8 HEIGHT=8 FRAMES=1 FORMAT=yuv444p8 VALIDATE_SYNTH=0
make validate CODEC=av2 \
  INPUT=verification/generated/test_vectors/palette_escape_64x64_1f_yuv444p8.yuv \
  WIDTH=64 HEIGHT=64 FRAMES=1 FORMAT=yuv444p8 VALIDATE_SYNTH=0
make validate-set CODEC=av2 \
  VALIDATION_SET=palette-escape-444 \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Result:

- Yosys synthesis passed in 188.4 seconds.
- Peak child RSS observed by the synthesis runner was 1134.36 MiB.
- Runtime stayed below the 300 second review threshold and inside the 600
  second hard timeout and 3072 MiB memory cap.
- Post-synthesis critical-path reporting completed in 24.8 seconds with peak
  child RSS of 1134.36 MiB and reported topological path length 126.
- The longest top-level path starts in
  `palette_analyzer.query_palette_colors_q`, passes through
  `ff_av2_luma_palette_symbolizer` palette-delta bit calculation, and reaches
  the range-coder `low_q` path.
- Isolated `ff_av2_palette_analyzer_444` synthesis now passes in 89.3 seconds
  with peak RSS 564.67 MiB. Before the metadata-cache rewrite, the same
  isolated analyzer timed out at 240 seconds.

Flattened Xilinx-cell estimate from
`yosys -p 'read_json synth/out/arty-z7-10/ff_av2_encoder/ff_av2_encoder.json; hierarchy -top ff_av2_encoder; flatten; stat -tech xilinx'`:

| Metric | Count |
|---|---:|
| Cells | 56106 |
| Estimated LCs | 18635 |
| CARRY4 | 2165 |
| DSP48E1 | 11 |
| FDCE | 3216 |
| FDPE | 44 |
| FDRE | 18880 |
| LUT1 | 505 |
| LUT2 | 5403 |
| LUT3 | 3726 |
| LUT4 | 2143 |
| LUT5 | 2217 |
| LUT6 | 10549 |
| MUXF7 | 2186 |
| MUXF8 | 601 |
| RAMB36E1 | 19 |

Delta from the immediately preceding luma-palette plus chroma-BDPCM baseline:

| Metric | Previous | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 316.6 s | 188.4 s | -128.2 s |
| Peak synthesis RSS | 1185.96 MiB | 1134.36 MiB | -51.60 MiB |
| Cells | 89138 | 56106 | -33032 |
| Estimated LCs | 37418 | 18635 | -18783 |
| Topological path length | 129 | 126 | -3 |
| RAMB36E1 | 6 | 19 | +13 |

The area reduction comes from removing the analyzer's wide dynamic block
palette query from the active symbolizer path. The RAM increase is expected:
the current lossless path stores the Y/U/V sample planes and a larger staged
tile payload. The staged carry buffer remains a known optimization target once
the next functional blocks are in place.

## Retired Bring-Up Measurements

Temporary AV2 fixed-output emitters existed during validation plumbing bring-up.
Those measurements are intentionally retired because the source streams and
trace-derived entropy data were removed. Future synthesis baselines should only
cover implementations that generate bitstream content from named, spec-auditable
syntax decisions.
