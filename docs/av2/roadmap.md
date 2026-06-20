# AV2 Roadmap (Lossless 4:4:4 Screen Content And Lossy 4:2:0 Video)

This roadmap is scoped to building a practical, spec-aligned **lossless 4:4:4
screen-content encoder** path plus a maintained **lossy 4:2:0 video residual**
path for FrameForge AV2. It is organized for incremental validation, with each
item tied to concrete validation and synthesis checkpoints.

## North Star

- Encode RGB-like screen content in 4:4:4 losslessly from `screenshot_*.png`-derived
  planar inputs.
- Encode natural-video `yuv420p8` inputs with a simple VVC-style lossy residual
  path so AV2 and VVC share a comparable 4:2:0 validation target.
- Maintain SW/RTL bitstream and reconstruction parity with AVM reference.
- Keep implementation synthesizable and regression-friendly.
- Preserve the shared FrameForge test infra and avoid hard-coded bitstreams.

## Guiding Constraints

- Keep the public AV2 top-level input contract at 8x8 visible packet blocks
  (64 Y, then 64 U, then 64 V samples) for now.
- Prefer 8-bit operation initially; keep higher bit-depth path as cleanup work.
- Any new syntax path must be generated from named, spec-referenced software
  decisions and mirrored in RTL (no opaque blobs).
- A feature is considered complete only after at least:
  - one focused SW-only validation pass,
  - one full AV2 sweep for the affected format, such as
    `screenshot-sweep-444` + `screenshot-multictu-444` for 4:4:4 or
    `racehorses-sweep-420` plus larger 4:2:0 guards for `yuv420p8`,
  - one Yosys synthesis baseline and documented delta.

## Feature Baseline Routine

Use this routine for every new AV2 coding tool or RTL cleanup. Any RTL change
must refresh both the output-utilization and synthesis reports. Changes that
also affect encoder decisions, syntax, prediction, residuals, or other
bitstream-generating algorithms must refresh the bitrate report as well.

1. Commit the validated SW/RTL source first, before writing the report docs.
2. Run the required validation sets with strict SW/RTL/REF checksum parity.
3. Update `output-utilization.md` with per-vector RTL output utilization,
   bubble rate, cycles/bit, and cycles/input pixel when RTL validation is run.
4. Run `make synth CODEC=av2` on the committed source and capture elapsed time,
   peak RSS, critical-path length, and flattened Xilinx-cell estimates.
5. Update `synthesis.md` with area/timing/memory deltas against the previous
   synthesis baseline, including both baseline and current source Git SHA1s.
6. If the encoder algorithm changed, update `quality-bitrate.md` with
   per-vector bits/bpp and deltas against the previous report baseline,
   including both baseline and current source Git SHA1s.
7. Commit the report/doc update separately from the source checkpoint.

## Implemented Baseline

The current validated AV2 baseline is no longer just palette bring-up. Treat
these blocks as implemented, with future work focused on widening decisions and
reducing cost rather than proving the plumbing again:

- 8x8 visible Y/U/V packet input contract shared with the VVC 4:4:4 testbench.
- 64x64 superblock/tile walking with partial and multi-superblock screenshot
  crop coverage.
- Luma-only AV2 palette syntax for 8x8 leaves, using up to eight palette colors
  as a predictor.
- Lossless luma residual coefficient coding after palette or non-DC luma intra
  prediction.
- Lossless horizontal chroma BDPCM plus coefficient coding for 4:4:4 chroma.
- Exact-hash IntraBC path using local 8x8 hashes for AVM-valid left-copy
  candidates inside the current 64x64 tile. Above candidates are instrumented
  but deferred until the full AVM availability/BVP stack is modeled.
- First restricted luma intra prediction path with DC, vertical, and horizontal
  modes where the currently implemented context model is valid.
- Strict SW/RTL/reference-decoder checksum validation and per-milestone
  bitrate/output-utilization/synthesis delta reporting.
- Lossy 4:2:0 residual support for 8x8 luma leaves and colocated 4x4 chroma
  transform blocks, validated on the RaceHorses crop sweep and larger
  multi-superblock smoke vectors.

## Roadmap

### Phase 0 — Baseline and Confidence

1. Baseline pass
   - Done: freeze current working lossless 4:4:4 palette + luma residual +
     chroma BDPCM + local left-copy hash IBC + restricted H/V intra path.
   - Keep 8-bit, fixed 8x8 coding leaves, and synthesis-visible geometry
     ceilings that do not create resolution-sized line buffers.
   - Required checks remain `screenshot-sweep-444` + `screenshot-multictu-444`.

2. Test coverage hardening
   - Done: keep local manifests for screen-content geometry sweeps and
     partial/multi-superblock crops.
   - Ensure all validation outputs include SW/RTL/REF checksum and PSNR.
   - Add at least one small 8x8 / 16x16 smoke sanity vector for quick local regression.

3. Documentation and tracing baseline
   - Done: keep `docs/av2/quality-bitrate.md`,
     `docs/av2/output-utilization.md`, and `docs/av2/synthesis.md` as
     mandatory artifacts for every feature milestone.
   - Add syntax traceability notes when a new block is implemented.

### Phase 1 — Feature Completeness for Lossless 4:4:4 Screens

1. Prediction decision block
   - Add a small SW/RTL decision block that chooses between the currently
     implemented predictors: luma palette+residual, DC residual, H/V intra
     residual, and local hash IBC.
   - Keep the first version simple: deterministic priority or rough bit-count
     estimates are acceptable; exact RDO can come later.
   - The block should emit explicit trace labels explaining why each 8x8 leaf
     chose a mode.

2. Luma intra expansion
   - Widen the luma-mode context model so vertical/horizontal prediction can be
     used on non-terminal leaves without relying on the current context guard.
   - Add one new simple predictor mode at a time, starting with the mode that
     has the lowest syntax/context cost in AVM for screen edges.
   - Keep residual coding lossless so a bad predictor only costs bitrate.

3. IntraBC candidate block
   - Done: expand immediate-left hash IBC into a local, DRL-aware left-copy
     candidate module while tracking above matches for future enablement.
   - Store hashes and candidate metadata, not whole blocks, unless a later
     exact-compare stage proves necessary.
   - Keep the search local and deterministic first; full virtual-buffer/window
     behavior can be staged after the candidate syntax is stable.
   - Next: model the full AVM block-vector predictor stack before enabling
     non-terminal copies or additional candidates such as above-left. A
     fixed-DRL non-terminal experiment was rejected by the reference decoder at
     `screenshot_640_sweep_24x8_1f_yuv444p8.yuv`.

4. Chroma prediction/BDPCM expansion
   - Add vertical chroma BDPCM beside the current horizontal path.
   - Add a simple direction chooser using local SAD or a rough bit proxy.
   - Keep chroma lossless and block-local; any non-BDPCM fallback must still
     round-trip exactly through the reference decoder.

5. Palette path stability
   - Make sure palette coding on 8x8 remains robust for frequent-color screen blocks.
   - Add stress cases with:
     - small solid regions,
     - frequent edges,
     - large text/GUI-like transitions.
   - Verify bitstream/RECON parity remains stable and deterministic.

6. Residual fallback robustness
   - Expand lossless residual/BDPCM decision coverage for blocks that miss
     palette compactness.
   - Add explicit decision-rule tests: palette hit / not-hit / fallback path.
   - Keep BDPCM lossless and block-local in syntax implementation.

7. Chroma behavior for arbitrary colors
   - Validate chroma-only failure modes are never silently dropped.
   - Ensure fallback coding remains lossless for all 4:4:4 screen-style inputs.

8. Partitioning sanity for screen blocks
   - Confirm all 8x8, 16x16, ..., 64x64 non-rectangular/screen-aligned tile shapes in
     screenshot manifests are supported without behavior changes.

### Phase 1b — Maintained Lossy 4:2:0 Video Path

1. Residual baseline
   - Done: add AV2 `yuv420p8` software/RTL residual coding with strict
     software/RTL bitstream parity and AVM-decoded reconstruction parity.
   - Done: validate the RaceHorses 8x8-through-64x64 crop sweep and a short
     set of larger/multi-superblock RaceHorses vectors.
   - Keep this path simple and local while the lossless 4:4:4 path remains the
     primary feature focus.

2. Future residual improvements
   - Reuse VVC residual lessons where possible: fewer bubbles, simpler
     transform-block buffering, and bounded coefficient scans.
   - Keep every quality-changing change documented in `quality-bitrate.md`
     because 4:2:0 is lossy and PSNR deltas matter.
   - Treat RaceHorses 4:2:0 sweeps as a guard for shared entropy, residual, and
     AXI-interface changes even when the feature work targets 4:4:4.

### Phase 2 — Screen Throughput and Multi-CTU Robustness

1. Multi-CTU ordering
   - Keep 8x8 packet input while improving internal slice/tile walking for
     partial-CTU and multi-CTU screen crops.
   - Ensure per-CTU progression is deterministic and restart-safe.

2. Reconstruction streaming correctness
   - Audit reconstruction path for multi-CTU carryover and context gating.
   - Add regression vectors specifically for 136x80 / 192x64 / 72x128-style partial crops.

3. Runtime behavior
   - Keep first-fail semantics in validation to reduce debug time.
   - Keep run-time reports for per-vector and final aggregate status.

### Phase 3 — Synthesis-Cost Optimization (post-functional)

1. Critical-path cleanup
   - Target `palette_analyzer -> palette_delta -> range coder` path.
   - Remove excess sequential fan-out in high-frequency symbolizer logic.

2. Buffer and storage optimization
   - Review staged carry/sample buffers for opportunities to stream data without
     changing semantics.
   - Prioritize FF reductions while preserving lossless behavior.

3. Compile-time and synthesis quality
   - Keep default Yosys cap at 600s/300s review unless objective function degrades.
   - Gate larger syntax expansions behind verified feature flags.

### Phase 4 — Extension Work (after lossless baseline is stable)

1. Syntax extensions that benefit screen content
   - Widen IBC/IBC-hash candidates once base predictor coverage is stable.
   - Add directional/linear prediction refinements only if compatible with lossless
     requirement and AVM reference behavior.

2. Configurability
   - Add explicit compile/runtime flags for screen-optimized mode vs generic mode.
   - Keep default behavior conservative, synthesizable, and validated.

## Immediate next milestones (next 1–2 cycles)

- ✅ Complete the current regression and synthesis checkpoint (done).
- ✅ Validate screenshot full sweep and multi-superblock crops for the current
  lossless 4:4:4 AV2 baseline.
- [ ] Add the prediction decision block so mode selection becomes its own
  auditable module instead of being spread across palette analysis and tile
  emission.
- [ ] Add vertical chroma BDPCM and a tiny direction chooser.
- ✅ Expand IBC from immediate-left only to a local DRL-aware left-copy
  hash-candidate set, with above candidates counted but not selected yet.
- [ ] Model the AVM IntraBC BVP stack so non-terminal and wider local IBC
  candidates can be enabled safely.
- [ ] Reduce active critical path in luma-palette delta coding and measure with
  `docs/av2/synthesis.md` after the next functional block lands.
- [ ] Add one end-to-end “screen scene” baseline (single source screenshot crop
  run) that records bits, bpp, and PSNR/inf-lossless status.

## Feature Set to Implement Across Cycles

Use this as the recurring feature checklist for each active development cycle:

- **Codec syntax support**
  - Prediction decision module for palette, residual, intra, BDPCM, and IBC
    modes
  - Palette predictor refinements (luma-only per current AV2 spec shape)
  - Residual path coverage for all 8x8 leaves (palette residual + BDPCM variants)
  - Additional predictor modes with strict fallback ordering
  - Intra prediction context and mode expansion for screen content
  - IBC BVP-stack modeling and hash-candidate expansion beyond left-copy only
  - Block-tree and partition decision support
  - Optional entropy/range-coder context/state updates once correctness is stable
  - Chroma-robust fallback policy (no silent failures on non-palette blocks)
  - Screen-aware coding-tool tuning hooks

- **Format and input coverage**
- 4:4:4 arbitrary-color full-frame/screenshot cases
- 4:2:0 RaceHorses crop and multi-superblock cases
- Multi-CTU geometry support with deterministic ordering
  - Partial-CTU edge cases and non-tile-aligned crops
  - Deterministic seed/replay support for pseudo-random screen crop generation

- **Validation and quality**
  - SW/RTL/REF checksum parity under every new syntax path
  - Bits-per-sample/bpp tracking in `quality-bitrate` baseline docs
  - Regression-set-specific failure taxonomy (palette miss, residual miss, context miss)
  - Screenshot-based smoke + full sweeps as the recurring regression gate

- **Synthesis and implementation**
  - Timing cleanup on the active critical path
  - Register/FF/LUT carry reduction where behavior permits
  - ROM/RAM reuse and staging reduction in sample windows
  - Removal of temporary test-only plumbing and debug-only branches

- **Tooling and docs**
  - Section-linked implementation comments for new syntax in both SW/RTL
  - Test-vector manifest growth for each new operating point
  - Explicitly documented synthesis and quality deltas per milestone
  - Clear PASS/FAIL definitions for each feature gate

When a cycle is planned, pick 2–3 items from this list and bind them to:
one SW change, one RTL change, one validation set, and one synthesis baseline.

## Acceptance for each milestone

- **Functional**: all relevant AV2 validation sets passed with strict checksum parity.
- **Quality**: lossless reconstruction (infinite PSNR where input is integer-valued and exact),
  no silent error paths.
- **Synthesis**: completion under budget and deltas documented.
- **Spec alignment**: syntax decisions mapped to AV2 section references in source comments/docs.
