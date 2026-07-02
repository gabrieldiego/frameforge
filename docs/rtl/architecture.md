# RTL Architecture Map

This page gives a high-level map of the current RTL organization. It is meant
to help agents find the right block before changing logic.

## Shared Top-Level Shape

Both codec encoder tops expose the same integration shape:

- AXI4-Lite control/status register slave.
- AXI4 memory-mapped source-frame read master.
- AXI4 memory-mapped bitstream write master.

The register map and public interface contract are documented in
`docs/rtl/hardware-interface.md`.

Do not add public debug ports for observability. Testbenches should probe
internal wires hierarchically when they need extra counters or waveforms.

## Modularity Rule For New Features

New RTL feature work should start by defining the module boundary. Do not add a
new predictor, mode decision, entropy side path, cost model, or sample-store
state machine directly into a codec top as bring-up glue.

Preferred pattern:

```text
rtl/<codec>/<feature>/ff_<codec>_<feature>_<role>.sv
  -> optional smaller helper modules in the same folder
  -> codec top instantiates and wires the feature top
```

The codec top should remain mostly structural: register/config plumbing,
submodule instantiation, and narrow handoff logic. If the top-level file gains
new feature state, counters, or mode-specific conditionals, treat that as a
refactoring trigger before the feature is called complete.

This rule is intentionally active during feature bring-up, not only during
post-feature cleanup. Small modules make SW/RTL parity, block waveforms,
synthesis reports, and later optimization easier to audit.

## Shared RTL

Shared modules live under:

```text
rtl/common/
```

Current responsibilities include:

- AXI4-Lite register decode.
- Source-frame address generation and AXI read glue.
- Internal input FIFO/unpack logic.
- Bitstream byte packing and AXI write glue.
- Shared utility definitions that are codec-independent.

Shared RTL should not contain codec syntax decisions. If a block needs to know
VVC CABAC syntax or AV2 range-coder symbols, it belongs under the codec folder.

## VVC RTL

VVC-specific modules live under:

```text
rtl/vvc/
```

Current conceptual pipeline:

```text
AXI frame reader
  -> internal CTU/TU sample stream
  -> VVC coding tree / palette / residual symbolization
  -> CABAC syntax frontend
  -> CABAC bin coder and byte writer
  -> RBSP / Annex-B bitstream writer
  -> AXI bitstream writer
```

Current design constraints:

- 64x64 CTU-local slices for the current large-picture subset.
- 8x8 luma and 4x4 chroma transform-block assumptions for 4:2:0.
- Lossless 4:4:4 screen path with palette, residual/escape handling, and local
  hash IBC.
- CABAC labels/contexts should be shared through common includes/packages where
  practical instead of duplicated across modules.

When VVC bubble rate regresses, start with the block throughput probes around
the CTU symbolizer, syntax frontend, bin coder, bin FIFO, CABAC byte writer,
RBSP writer, and AXI writer.

## AV2 RTL

AV2-specific modules live under:

```text
rtl/av2/
```

Current conceptual pipeline:

```text
AXI frame reader
  -> internal visible 8x8 Y/U/V block stream
  -> AV2 mode analysis and sample stores
  -> luma palette / intra / IBC / residual decisions
  -> chroma BDPCM / residual decisions
  -> AV2 range-coded entropy stream
  -> OBU/tile payload assembly
  -> AXI bitstream writer
```

Important subdirectories:

- `rtl/av2/bitstream/`
- `rtl/av2/entropy/`
- `rtl/av2/ibc/`
- `rtl/av2/palette/`
- `rtl/av2/residual/`

The top-level AV2 encoder should mostly instantiate these higher-level blocks.
If logic grows inside `ff_av2_encoder.sv`, prefer factoring it into the
appropriate subdirectory once behavior is stable.

Current AV2 constraints:

- Visible coding leaves are fixed at 8x8 for now.
- Palette syntax is luma-only in the reference-compatible AV2 path.
- Chroma lossless behavior uses BDPCM/residual paths.
- IBC is local hash-based and intentionally limited until the full AVM BVP
  stack is modeled.
- No hard-coded OBU payloads or generated entropy operation blobs are allowed.

## Throughput Probes

Throughput instrumentation belongs in testbenches and validation helpers, not
as board-facing RTL ports.

The block-state model is documented in:

```text
docs/rtl/block-throughput-waveforms.md
```

Use it when optimizing:

- cycles per input pixel;
- output utilization;
- bubble rate;
- cycles per bit;
- waiting/working/backpressure/idle rates for internal blocks.

Cycles per input pixel is the top-level throughput metric. Bubble rate is kept
as a diagnostic signal for locating local starvation or backpressure, especially
when a larger vector misses the current throughput target.

## Area And Timing Watchpoints

When changing RTL, watch for:

- arrays scaling with visible width, height, tile count, or frame count;
- large combinational mux chains over blocks, samples, or palette entries;
- inferred register banks where small RAMs or streaming FIFOs would suffice;
- fan-out from mode-decision state into entropy paths;
- analysis and entropy stages that are serialized but could overlap;
- full tile/frame buffering where block/TU-sized storage is enough.

If a change increases Yosys runtime, memory, area, or topological path length
without a feature reason, treat it as a design bug to audit before committing.
