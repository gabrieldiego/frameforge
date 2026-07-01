# Current Validation And Synthesis Targets

This document records the current project-wide targets for FrameForge
validation, output-utilization, and synthesis runs. These are working
constraints for AI agents and developers; codec-specific measured baselines live
in `docs/vvc/` and `docs/av2/`.

Current as of 2026-06-30.

## Functional Correctness

Functional correctness is the first gate. A regression is not considered
passing unless every selected vector passes.

Required checks for implemented paths:

- Software and RTL bitstreams match byte-for-byte.
- Software, RTL, and reference-decoder reconstructions match by checksum.
- VVC uses VTM as the reference decoder.
- AV2 uses AVM/reference-decoder as a decode-only reference.
- Lossless 4:4:4 vectors must reconstruct to bytes that are 100% identical to
  the input. No loss, rounding drift, color change, or format-side alteration is
  tolerated in lossless mode.
- Lossless 4:4:4 vectors report infinite PSNR because the reconstruction is
  exactly equal to the input.
- Lossy 4:2:0 vectors report PSNR and bitrate; quality-changing changes must
  update the codec quality/bitrate report.

Do not change validation scripts to hide known failures. Unsupported syntax or
geometry should fail visibly until implemented.

See `failure-triage.md` for the debug workflow when one of these gates fails.

## Required Regression Coverage

For shared encoder, RTL, or reporting changes, run the affected codec sets:

- `screenshot-sweep-444`
- `screenshot-multictu-444`
- `racehorses-sweep-420`
- `racehorses-multictu-420`
- `multiframe-smoke`

Use local manifests from `verification/test_vector_sets/local` when the
RaceHorses and screenshot sources are available on the machine.

For fast debug loops, a focused smoke vector is acceptable before the full set.
Before a change is called validated, the relevant full set must pass.

## Output Utilization Target

The current bubble-rate target is:

- `bubble_rate <= 0.600` for every stream whose visible resolution is at least
  64x64 pixels.

Interpret "at least 64x64" as both visible width and visible height being
greater than or equal to 64 pixels. Smaller vectors are still useful for
correctness, but fixed setup/drain costs can dominate their utilization
metrics.

The primary top-level metrics are:

- `output_utilization = accepted output bytes / total measured cycles`
- `bubble_rate = 1 - output_utilization`
- `cycles/bit = total measured cycles / RTL bitstream bits`
- `cycles/input pixel = total measured cycles / (width * height * frames)`

When an RTL change worsens bubble rate or cycles/pixel, generate block-level
throughput waveforms and inspect the internal waiting/working/backpressure/idle
states before optimizing. The workflow is documented in
`docs/rtl/block-throughput-waveforms.md`.

For report updates, preserve per-vector utilization and bubble-rate tables in:

- `docs/av2/output-utilization.md`
- `docs/vvc/output-utilization.md`

## Yosys Synthesis Targets

Yosys is the default synthesis feedback loop for routine RTL changes. It is a
rough area/timing estimate and a synthesizability check, not final vendor
timing closure.

Current default command shape:

```sh
make synth CODEC=av2 SYNTH_DUT=av2-encoder
make synth CODEC=vvc SYNTH_DUT=vvc-encoder
```

Current shared synthesis settings:

- clock metadata: `25 MHz`
- max visible size: `1024x1024`
- hard timeout: `900` seconds
- review threshold: `600` seconds
- memory cap: `3072 MiB`
- board metadata: `synth/boards/arty-z7-10.env`
- 4:4:4 palette support: enabled

Targets and review triggers:

- A normal top-encoder Yosys run should complete under the 900 second hard
  timeout.
- Any run over 600 seconds should be treated as a design-complexity review
  trigger, even if it passes.
- Peak observed child RSS must stay under the configured 3072 MiB cap.
- A significant memory increase should trigger an audit of new buffers,
  widened arrays, generated muxes, and inferred register banks.
- Topological path length should not grow without a corresponding feature
  reason. If it grows, document the likely limiter in the synthesis report.
- Area growth is acceptable for real features, but unexpected LUT/FF/RAM growth
  should be traced before committing the milestone.

Record Yosys elapsed time, peak memory, topological path length, flattened
cells, estimated LCs, and notable Xilinx primitive deltas in:

- `docs/av2/synthesis.md`
- `docs/vvc/synthesis.md`

## Vivado Timing Target

Vivado is the vendor timing/resource confirmation path. Use it after larger RTL
changes, timing-sensitive optimizations, or before claiming that a milestone is
timing-clean.

Current Vivado target:

- 25 MHz clock on the configured Zynq-7000 board metadata.
- Positive setup WNS.
- Memory and runtime should remain bounded; unexpectedly long or high-memory
  Vivado runs are treated as design-complexity signals.

Vivado is slower than Yosys. It can run in parallel with long validation when
the machine has enough CPU and memory headroom.

## Reporting Targets

For RTL changes:

- run relevant validation;
- run Yosys synthesis;
- update output-utilization and synthesis reports.

For algorithmic encoder changes:

- update quality/bitrate reports as well;
- include per-vector bits, bpp, PSNR, and deltas.

Reports should include baseline and current Git SHA values. When practical,
commit validated source first, then regenerate reports using that source commit
as the current SHA and commit the reports separately.

See `reporting-workflow.md` for the full report-generation lifecycle.

## Design Constraints That Affect Validation

These constraints are not numeric targets, but they are part of the current
validation contract:

- Codec top modules share an AXI4-Lite control plane plus AXI4 memory-mapped
  source-read and bitstream-write ports.
- Do not add public debug ports for validation; testbenches can probe internal
  signals hierarchically.
- Avoid resolution-sized internal buffers. `MAX_VISIBLE_WIDTH` and
  `MAX_VISIBLE_HEIGHT` should not instantiate line/frame storage in codec
  blocks.
- Keep internal processing based on small block/TU-sized storage where possible.
- Hard-coded bitstreams, opaque entropy payloads, and trace-derived operation
  blobs are not acceptable implementation shortcuts.
- New syntax must be generated from named software decisions and mirrored in
  synthesizable RTL.
