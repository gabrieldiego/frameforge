# Failure Triage Playbook

Use this checklist when a FrameForge validation, report, or synthesis run
fails. The goal is to converge on the real implementation bug without weakening
the regression definition.

## General Rule

Do not convert a failing regression into a passing one by relaxing checks. A
PASS means all selected vectors satisfy the current validation contract in
`docs/validation/targets.md`.

When one vector fails:

1. Stop treating the regression as valid.
2. Identify the first failing vector and failure type.
3. Audit the relevant SW and RTL path against the spec or reference
   implementation.
4. Use traces and waveforms to confirm the audited cause.
5. Fix the class of bug, not only the single symptom.
6. Rerun the smallest reproducer first, then the affected full set.

## SW/RTL Bitstream Mismatch

Likely causes:

- Software and RTL made different mode decisions.
- Symbol order differs.
- Context initialization or update differs.
- A block/coded-unit scan order differs.
- RTL emitted stale state across frame, CTU, superblock, or tile boundary.

Triage:

- Compare software syntax trace and RTL symbol trace for the first divergent
  symbol when available.
- Audit the syntax module that owns the divergent symbol.
- Check frame/block counters and reset conditions.
- Check internal block order and edge padding.
- Do not copy a software bug into RTL. If software is wrong, fix software and
  then mirror the spec-aligned behavior in RTL.

## Reconstruction Checksum Mismatch

Likely causes:

- Internal reconstruction path differs between SW and RTL.
- Reference decoder reconstructs a different prediction/residual path than the
  local model expected.
- Lossless path introduced rounding, clipping, color-plane swap, or stale
  predictor state.
- 4:2:0 chroma geometry or frame stride is wrong.

Triage:

- For lossless 4:4:4, compare input and each reconstruction byte-for-byte.
- Confirm the pixel format used for checksum and viewing.
- For PNG-derived 4:4:4 screenshots, remember that the planar `.yuv` stream is
  carrying byte-preserved GBR-like samples through the codec path.
- For lossy 4:2:0, inspect PSNR deltas and make sure finite PSNR is expected.
- Audit predictor, residual, inverse/reconstruction, and edge handling together.

## Reference Decoder Failure

Likely causes:

- Invalid syntax field value.
- Missing required header/tool flag.
- Entropy context mismatch.
- Tile/frame boundary syntax is malformed.
- OBU/NAL payload length or termination is wrong.

Triage:

- Keep the bitstream failure visible.
- Reduce to the smallest vector that still fails.
- Audit the syntax section around the last successfully decoded element.
- Use reference decoder traces only to locate the region; implement from the
  spec/reference-code behavior, not from opaque payload copying.

## Lossless PSNR Is Finite

This is always a failure for the current 4:4:4 lossless paths.

Triage:

- Compare input and reconstruction checksums first.
- Check plane ordering, color conversion, and PNG import/export paths.
- Check residual losslessness and coefficient range.
- Check clipping and signed-difference handling.
- Check whether the mode decision accidentally selected a lossy path.

No loss, quantization, rounding drift, or color change is tolerated in
lossless validation.

## Bubble Rate Regressed

Use this when `bubble_rate` worsens or misses the current target in
`docs/validation/targets.md`.

Triage:

- Generate block throughput waveforms with `VALIDATION_BLOCK_WAVEFORM=1`.
- Inspect waiting, working, idle, and backpressure rates.
- Find the first block that starves downstream work or backpressures upstream
  work for a sustained interval.
- Check whether the design serialized analysis and entropy that could overlap.
- Check whether AXI reader/writer width is being used effectively.
- Prefer small FIFO/staging changes or block-local streaming changes before
  large buffering changes.

Do not add large tile/frame buffers to improve simulation speed unless the area
and synthesis impact are justified.

## Yosys Timeout Or Memory Spike

Triage:

- Check whether new arrays scale with `MAX_VISIBLE_WIDTH`,
  `MAX_VISIBLE_HEIGHT`, CTU count, tile count, or frame size.
- Search for large packed/unpacked arrays in synthesizable modules.
- Look for combinational loops or very wide if/case mux trees.
- Check whether a generated table or hard-coded blob entered RTL.
- Synthesize the suspected submodule alone if possible.
- Compare topological path length, cell counts, and primitive deltas against
  the previous report.

The current limits are documented in `docs/validation/targets.md`. A pass above
the review threshold still requires design-complexity review.

## Vivado Timing Miss

Triage:

- Inspect WNS, WHS, data path delay, and logic levels.
- Identify whether the path is logic-dominated or route-dominated.
- Compare against the Yosys topological limiter.
- Prefer registering module boundaries, reducing fan-out, or splitting wide
  mux/priority chains.
- Do not lower the clock target to hide a regression unless the user explicitly
  changes the project target.

## Reporting Failure

Triage:

- Check that validation logs and checksum JSON exist for the requested codec.
- Check whether Vivado reports are available before using
  `--synthesis-tool yosys-vivado`.
- If reports are regenerated from existing artifacts, state that no new full
  regression was run.
- Keep baseline and current SHAs meaningful. Do not let reports silently compare
  against unrelated or missing checkpoints.
