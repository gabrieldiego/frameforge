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
make validate-set CODEC=av2 VALIDATION_SET=screenshot-444-sweep VALIDATION_BLOCK_WAVEFORM=1 VALIDATION_WITH_SYNTH=0
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
- Total cycles: `4697`

| Block | Idle | Waiting | Working | Backpressure |
|---|---:|---:|---:|---:|
| `axi_reader` | 0.816 | 0.010 | 0.174 | 0.000 |
| `input_fifo` | 0.000 | 0.816 | 0.184 | 0.000 |
| `av2_core` | 0.313 | 0.050 | 0.636 | 0.000 |
| `luma_residual` | 0.000 | 0.888 | 0.112 | 0.000 |
| `chroma_residual` | 0.000 | 0.688 | 0.312 | 0.000 |
| `entropy_coder` | 0.000 | 0.404 | 0.595 | 0.000 |
| `axi_writer` | 0.001 | 0.875 | 0.124 | 0.000 |

VVC 16x16 4:2:0 RaceHorses crop:

- VCD:
  `verification/generated/checksums/vvc/racehorses_crop_16x16_1f_yuv420p8_16x16_1f_yuv420p8_rtl_block_waveform.vcd`
- HTML:
  `verification/generated/checksums/vvc/racehorses_crop_16x16_1f_yuv420p8_16x16_1f_yuv420p8_rtl_block_waveform.html`
- Total cycles: `1813`

| Block | Idle | Waiting | Working | Backpressure |
|---|---:|---:|---:|---:|
| `axi_reader` | 0.753 | 0.018 | 0.229 | 0.000 |
| `input_fifo` | 0.000 | 0.629 | 0.217 | 0.154 |
| `vvc_core_input` | 0.472 | 0.017 | 0.370 | 0.142 |
| `palette_symbolizer` | 0.771 | 0.017 | 0.212 | 0.000 |
| `ctu_symbolizer` | 0.472 | 0.017 | 0.370 | 0.142 |
| `residual_symbolizer` | 0.000 | 0.746 | 0.141 | 0.113 |
| `syntax_frontend` | 0.589 | 0.096 | 0.312 | 0.003 |
| `bin_coder` | 0.000 | 0.680 | 0.300 | 0.020 |
| `cabac_writer` | 0.048 | 0.790 | 0.162 | 0.000 |
| `rbsp_writer` | 0.000 | 0.978 | 0.022 | 0.001 |
| `axi_writer` | 0.000 | 0.942 | 0.058 | 0.000 |
