# Block Throughput Waveforms

FrameForge can emit per-block throughput waveforms from the RTL testbenches.
This instrumentation is testbench-only; it does not add FPGA-facing ports or
change the synthesizable encoder interfaces.

Enable the report for a single validation run with:

```sh
python3 scripts/validate.py --codec av2 --block-waveform --skip-synth <vector.yuv>
```

or for a validation set with:

```sh
make validate-set CODEC=av2 VALIDATION_SET=screenshot-sweep-444 VALIDATION_BLOCK_WAVEFORM=1 VALIDATION_WITH_SYNTH=0
```

The validation log prints the generated artifact paths:

- `*_rtl_block_waveform.vcd`: GTKWave-readable state waveform.
- `*_rtl_block_waveform.gtkw`: GTKWave save file that preloads the block state
  signals.
- `*_rtl_block_waveform.html`: color-coded compact timeline.
- `*_rtl_block_waveform.json`: per-block state counts, rates, and run-lengths.
- `*_rtl_block_waveform.legend.json`: state color legend.

Open the waveform with:

```sh
gtkwave <path>_rtl_block_waveform.gtkw
```

VCD does not encode display colors. The color coding is therefore carried by the
HTML report and JSON legend. The VCD also includes one-hot helper signals whose
names include the color hex code, so the GTKWave view remains readable even
without custom viewer coloring.

## State Encoding

The block state is derived only from the main input/output valid-ready
handshakes:

| Code | State | Color | Meaning |
|---:|---|---|---|
| `0` | `idle` | gray `#808080` | No main input transfer and no main output activity. |
| `1` | `waiting` | blue `#2f80ed` | The block input is ready, but the feeding block has no valid payload. |
| `2` | `working` | green `#27ae60` | The main input side or output side transfers payload this cycle. |
| `3` | `backpressure` | red `#eb5757` | The block output has valid payload, but the following block is not ready. |

Backpressure has highest priority, followed by working, waiting, then idle.

## Smoke Reports

Generated on 2026-06-22 with `--block-waveform --skip-synth`.

AV2 16x16 4:4:4 screenshot crop:

- VCD:
  `verification/generated/checksums/av2/screenshot_640_sweep_16x16_1f_yuv444p8_16x16_1f_yuv444p8_rtl_block_waveform.vcd`
- HTML:
  `verification/generated/checksums/av2/screenshot_640_sweep_16x16_1f_yuv444p8_16x16_1f_yuv444p8_rtl_block_waveform.html`
- Total cycles: `4466`

| Block | Idle | Waiting | Working | Backpressure |
|---|---:|---:|---:|---:|
| `axi_reader` | 0.899 | 0.011 | 0.043 | 0.047 |
| `input_fifo` | 0.000 | 0.827 | 0.172 | 0.001 |
| `av2_core` | 0.329 | 0.001 | 0.669 | 0.000 |
| `luma_residual` | 0.000 | 0.882 | 0.118 | 0.000 |
| `chroma_residual` | 0.000 | 0.672 | 0.328 | 0.000 |
| `entropy_coder` | 0.000 | 0.373 | 0.626 | 0.000 |
| `axi_writer` | 0.001 | 0.869 | 0.130 | 0.000 |

VVC 16x16 4:2:0 RaceHorses crop:

- VCD:
  `verification/generated/checksums/vvc/racehorses_crop_16x16_1f_yuv420p8_16x16_1f_yuv420p8_rtl_block_waveform.vcd`
- HTML:
  `verification/generated/checksums/vvc/racehorses_crop_16x16_1f_yuv420p8_16x16_1f_yuv420p8_rtl_block_waveform.html`
- Total cycles: `1277`

| Block | Idle | Waiting | Working | Backpressure |
|---|---:|---:|---:|---:|
| `axi_reader` | 0.861 | 0.025 | 0.094 | 0.020 |
| `input_fifo` | 0.000 | 0.697 | 0.303 | 0.000 |
| `vvc_core_input` | 0.467 | 0.009 | 0.525 | 0.000 |
| `palette_symbolizer` | 0.691 | 0.009 | 0.301 | 0.000 |
| `ctu_symbolizer` | 0.467 | 0.009 | 0.525 | 0.000 |
| `source_symbol_fifo` | 0.597 | 0.145 | 0.258 | 0.000 |
| `residual_symbolizer` | 0.000 | 0.800 | 0.200 | 0.000 |
| `syntax_frontend` | 0.000 | 0.742 | 0.258 | 0.000 |
| `bin_coder` | 0.000 | 0.742 | 0.258 | 0.000 |
| `bin_fifo` | 0.000 | 0.709 | 0.238 | 0.052 |
| `cabac_writer` | 0.063 | 0.704 | 0.233 | 0.000 |
| `rbsp_writer` | 0.000 | 0.969 | 0.031 | 0.001 |
| `axi_writer` | 0.000 | 0.918 | 0.082 | 0.000 |

VVC 64x64 4:2:0 RaceHorses crop:

- VCD:
  `verification/generated/checksums/vvc/racehorses_crop_64x64_1f_yuv420p8_64x64_1f_yuv420p8_rtl_block_waveform.vcd`
- HTML:
  `verification/generated/checksums/vvc/racehorses_crop_64x64_1f_yuv420p8_64x64_1f_yuv420p8_rtl_block_waveform.html`
- Total cycles: `12869`

| Block | Idle | Waiting | Working | Backpressure |
|---|---:|---:|---:|---:|
| `axi_reader` | 0.678 | 0.040 | 0.149 | 0.133 |
| `input_fifo` | 0.000 | 0.522 | 0.478 | 0.000 |
| `vvc_core_input` | 0.145 | 0.001 | 0.854 | 0.000 |
| `palette_symbolizer` | 0.521 | 0.001 | 0.477 | 0.000 |
| `ctu_symbolizer` | 0.145 | 0.001 | 0.854 | 0.000 |
| `source_symbol_fifo` | 0.508 | 0.048 | 0.410 | 0.034 |
| `residual_symbolizer` | 0.000 | 0.664 | 0.336 | 0.000 |
| `syntax_frontend` | 0.000 | 0.555 | 0.410 | 0.035 |
| `bin_coder` | 0.000 | 0.555 | 0.410 | 0.035 |
| `bin_fifo` | 0.000 | 0.533 | 0.393 | 0.074 |
| `cabac_writer` | 0.074 | 0.541 | 0.385 | 0.000 |
| `rbsp_writer` | 0.000 | 0.963 | 0.037 | 0.000 |
| `axi_writer` | 0.000 | 0.956 | 0.044 | 0.000 |

## VVC Multi-CTU Checkpoint

Generated on 2026-06-23 with:

```sh
make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_BLOCK_WAVEFORM=1 \
  VALIDATION_WITH_SYNTH=0 \
  VALIDATION_STOP_ON_FAIL=1
```

All ten vectors passed strict SW/RTL/VTM checksum parity. The aggregate final
output bubble rate for the set was `0.771`.

Representative waveform artifacts:

| Vector | VCD | HTML |
|---|---|---|
| `screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv` | `verification/generated/checksums/vvc/screenshot_640_multictu_h2_128x64_1f_yuv444p8_128x64_1f_yuv444p8_rtl_block_waveform.vcd` | `verification/generated/checksums/vvc/screenshot_640_multictu_h2_128x64_1f_yuv444p8_128x64_1f_yuv444p8_rtl_block_waveform.html` |
| `screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv` | `verification/generated/checksums/vvc/screenshot_640_multictu_grid2_128x128_1f_yuv444p8_128x128_1f_yuv444p8_rtl_block_waveform.vcd` | `verification/generated/checksums/vvc/screenshot_640_multictu_grid2_128x128_1f_yuv444p8_128x128_1f_yuv444p8_rtl_block_waveform.html` |

Representative block rates:

| Vector | Final output util | Bubble | AXI reader work | Palette work | Syntax work | CABAC writer work | AXI writer work |
|---|---:|---:|---:|---:|---:|---:|---:|
| `h2_128x64` | 0.285 | 0.715 | 0.221 | 0.255 | 0.763 | 0.963 | 0.295 |
| `grid2_128x128` | 0.063 | 0.937 | 0.743 | 0.032 | 0.367 | 0.358 | 0.066 |

The `h2`, `h3`, `v2`, `v3`, `partial_h2`, `partial_wide`, and `partial_tall`
vectors were individually at or below the historical `0.800` bubble target used
for that checkpoint. Current bubble-rate targets are maintained in
`docs/validation/targets.md`. The grid and vertical-partial outliers have very
small bitstreams, so fixed CTU traversal and input fetch work dominate the
byte-output metric even though the reader and CABAC handoff paths are active.
