# AV2 Roadmap (Lossless 4:4:4 Screen Content Focus)

This roadmap is scoped to building a practical, spec-aligned **lossless 4:4:4 screen-content encoder** path for FrameForge AV2.
It is organized for incremental validation, with each item tied to concrete
validation and synthesis checkpoints.

## North Star

- Encode RGB-like screen content in 4:4:4 losslessly from `screenshot_*.png`-derived
  planar inputs.
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
  - one full AV2 sweep including `screenshot-sweep-444` and `screenshot-multictu-444`,
  - one Yosys synthesis baseline and documented delta.

## Roadmap

### Phase 0 — Baseline and Confidence

1. Baseline pass
   - Freeze current working lossless 4:4:4 palette + luma residual + chroma BDPCM path.
   - Keep 8-bit, fixed 8x8 leaf TBs, and 1024x1024 test ceilings.
   - Required checks: `screenshot-sweep-444` + `screenshot-multictu-444` pass.

2. Test coverage hardening
   - Add/keep local manifests for screen-content geometry sweeps and partial/multi-CTU crops.
   - Ensure all validation outputs include SW/RTL/REF checksum and PSNR.
   - Add at least one small 8x8 / 16x16 smoke sanity vector for quick local regression.

3. Documentation and tracing baseline
   - Keep `docs/av2/quality-bitrate.md` and `docs/av2/synthesis.md` as mandatory
     artifacts for every feature milestone.
   - Add syntax traceability notes when a new block is implemented.

### Phase 1 — Feature Completeness for Lossless 4:4:4 Screens

1. Palette path stability
   - Make sure palette coding on 8x8 remains robust for frequent-color screen blocks.
   - Add stress cases with:
     - small solid regions,
     - frequent edges,
     - large text/GUI-like transitions.
   - Verify bitstream/RECON parity remains stable and deterministic.

2. Residual fallback robustness
   - Expand lossless residual/BDPCM decision coverage for blocks that miss palette
     compactness.
   - Add explicit decision-rule tests: palette hit / not-hit / fallback path.
   - Keep BDPCM lossless and block-local in syntax implementation.

3. Chroma behavior for arbitrary colors
   - Validate chroma-only failure modes are never silently dropped.
   - Ensure fallback coding remains lossless for all 4:4:4 screen-style inputs.

4. Partitioning sanity for screen blocks
   - Confirm all 8x8, 16x16, ..., 64x64 non-rectangular/screen-aligned tile shapes in
     screenshot manifests are supported without behavior changes.

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
   - Evaluate IBC/IBC-hash candidates once base predictor coverage is stable.
   - Add directional/linear prediction refinements only if compatible with lossless
     requirement and AVM reference behavior.

2. Configurability
   - Add explicit compile/runtime flags for screen-optimized mode vs generic mode.
   - Keep default behavior conservative, synthesizable, and validated.

## Immediate next milestones (next 1–2 cycles)

- ✅ Complete the current regression and synthesis checkpoint (done).
- [ ] Add screen-content-specific manifest with randomized crop ordering for regression
  replayability and seed logging.
- [ ] Run screenshot full sweep and multi-CTU sweep after each syntax change.
- [ ] Reduce active critical path in luma-palette delta coding and measure with
  `docs/av2/synthesis.md`.
- [ ] Add one end-to-end “screen scene” baseline (single source screenshot crop run)
  that records bits, bpp, and PSNR/inf-lossless status.

## Acceptance for each milestone

- **Functional**: all relevant AV2 validation sets passed with strict checksum parity.
- **Quality**: lossless reconstruction (infinite PSNR where input is integer-valued and exact),
  no silent error paths.
- **Synthesis**: completion under budget and deltas documented.
- **Spec alignment**: syntax decisions mapped to AV2 section references in source comments/docs.

