# FrameForge Agent Guide

This file is for AI coding agents working in this repository. It captures the
standing project context, engineering constraints, validation rules, and
preferred workflows so new sessions can start without re-deriving them from
chat history.

The scope of this file is the whole repository.

## Project Goal

FrameForge is a hardware/software video-compression research workspace. The
repository contains:

- Rust software models for codec syntax and reconstruction.
- SystemVerilog RTL implementations of the same encoder subsets.
- Shared verification scripts that compare software, RTL, and external
  reference decoders.
- Shared synthesis/reporting infrastructure for rough Yosys estimates and
  optional Vivado timing/resource checks.

The current deliverable focus is a small but real encoder feature set that can
be validated end-to-end:

- VVC/H.266: 8-bit planar 4:2:0 lossy residual and 4:4:4 lossless
  screen-content subset.
- AV2: 8-bit planar 4:4:4 lossless screen-content path plus a maintained
  lossy 4:2:0 residual path.

FrameForge values spec-aligned, auditable syntax generation over opaque
payloads or trace-only reproduction.

## Read First

At the start of a session, inspect the current tree and read the relevant docs
before making assumptions:

```sh
git status --short
sed -n '1,220p' README.md
sed -n '1,220p' docs/project/feature-matrix.md
sed -n '1,220p' docs/rtl/hardware-interface.md
sed -n '1,220p' docs/rtl/architecture.md
sed -n '1,220p' docs/synthesis.md
sed -n '1,220p' docs/validation/targets.md
```

For AV2 work, also read:

```sh
sed -n '1,260p' docs/av2/roadmap.md
sed -n '1,220p' docs/av2/progress.md
```

For current measurements, read the codec-specific reports:

- `docs/av2/quality-bitrate.md`
- `docs/av2/output-utilization.md`
- `docs/av2/synthesis.md`
- `docs/vvc/quality-bitrate.md`
- `docs/vvc/output-utilization.md`
- `docs/vvc/synthesis.md`

Generated outputs live under `verification/generated/` and `synth/out/`; these
are not source-of-truth documents.

Current numeric validation, bubble-rate, runtime, and synthesis-memory targets
are maintained in `docs/validation/targets.md`. Treat that file as the source
of truth for milestone acceptance thresholds.

Related operational docs:

- `docs/project/feature-matrix.md` for current VVC/AV2 feature status.
- `docs/validation/failure-triage.md` for failure-specific debug workflow.
- `docs/validation/reporting-workflow.md` for report and commit sequencing.
- `docs/validation/local-assets.md` for local manifest and media policy.
- `docs/rtl/architecture.md` for the shared RTL block map.

## Suggested Session Bootstrap

For a new AI session, a good first prompt is:

```text
Please read AGENTS.md first, then inspect git status and the relevant FrameForge
docs before changing code. Follow the repository validation, synthesis, report,
RTL style, and git rules from AGENTS.md.
```

If the session has a specific focus, append one line such as:

```text
Today we are working on AV2 RTL bubble-rate optimization.
```

This is usually better than pasting long historical context. The agent should
derive the current state from committed docs, reports, and the working tree.

## Non-Negotiable Validation Rules

- A regression passes only when every selected vector passes.
- Software and RTL bitstreams must match byte-for-byte for implemented paths.
- Software, RTL, and reference-decoder reconstructions must match by checksum
  for implemented paths.
- VVC validation uses VTM as the external decoder.
- AV2 validation uses AVM/reference-decoder as a decode-only reference. Do not
  use AVM as a bitrate reference encoder in normal validation.
- If one test vector fails, stop treating that regression as passing. Use the
  failure to drive an audit and fix.
- Do not weaken validation criteria to make an incomplete implementation look
  green. Unsupported geometry or syntax can fail as an implementation bug.
- For lossless 4:4:4 paths, reconstruction should match the input and PSNR
  should be infinite.
- For lossy 4:2:0 paths, record PSNR and bitrate deltas.

When debugging a failure, audit the relevant code against the spec or reference
implementation first. Traces are useful evidence, but they should confirm the
audited cause rather than replace the audit.

## Feature Development Loop

For new codec features, use this order unless the user explicitly asks
otherwise:

1. Implement the software model first, with named syntax decisions and local
   reconstruction.
2. Validate software against the external reference decoder.
3. Implement the matching RTL.
4. Run focused smoke validation.
5. Run the relevant full regression set.
6. Run synthesis when RTL changed.
7. Update reports with bitrate, output-utilization, and synthesis deltas.
8. Commit source changes first when practical, then commit report updates with
   the source SHA recorded in the reports.

Every new syntax path should be traceable in source comments or docs to the
spec/reference-code concept it implements.

## Common Commands

Check tools:

```sh
make check-tools
```

Build and Rust tests:

```sh
make build
make test
```

Portable sanity check without synthesis:

```sh
make release-check
```

Generate/list test vector sets:

```sh
make test-vector-sets
make test-vectors TEST_VECTOR_SET=smoke
```

Validate one set:

```sh
make validate-set \
  CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Run report-backed regression and synthesis:

```sh
make report-codec CODEC=av2 REPORT_SYNTHESIS_TOOL=yosys
make report-codec CODEC=vvc REPORT_SYNTHESIS_TOOL=yosys
```

Use Vivado only when needed for vendor timing/resource confirmation:

```sh
make synth-vivado CODEC=av2
make synth-vivado CODEC=vvc
```

Current synthesis defaults are:

- `SYNTH_CLOCK_MHZ=25`
- `SYNTH_TIMEOUT_SEC=900`
- `SYNTH_WARN_AFTER_SEC=600`
- `SYNTH_MEMORY_LIMIT_MB=3072`
- `SYNTH_MAX_VISIBLE_WIDTH=1024`
- `SYNTH_MAX_VISIBLE_HEIGHT=1024`

## Report Discipline

Reports are intentionally kept as the latest checkpoint plus deltas. Older
results belong to git history, not repeated sections in the markdown.

Update these reports after RTL changes:

- `docs/<codec>/output-utilization.md`
- `docs/<codec>/synthesis.md`

Also update this report when encoder decisions, syntax, prediction, residuals,
or reconstruction behavior changes:

- `docs/<codec>/quality-bitrate.md`

The report generator is:

```sh
python3 scripts/update_codec_reports.py --codec av2 --checkpoint-title "<title>" --synthesis-tool yosys
python3 scripts/update_codec_reports.py --codec vvc --checkpoint-title "<title>" --synthesis-tool yosys
```

Use `--synthesis-tool yosys-vivado` only when Vivado reports are available for
that checkpoint. If Vivado was not rerun, the report should say so explicitly.

Reports should include:

- baseline Git SHA
- current validated Git SHA
- per-vector bitrate/PSNR when algorithmic output changed
- per-vector output utilization and bubble rate when RTL validation ran
- synthesis elapsed time, memory, area estimate, and timing/critical path notes

## RTL Style And Synthesis Constraints

The RTL must be synthesis-ready by default.

- Avoid SystemVerilog `function` and `task` constructs in synthesizable RTL.
  Prefer explicit combinational/sequential logic or small modules.
- Keep two-space indentation in RTL.
- Prefer modules with clear valid/ready-style streaming boundaries.
- Top-level codec modules should mostly instantiate and connect higher-level
  submodules. Push logic into `rtl/<codec>/<block>/` modules when it grows.
- Do not add board-facing debug/observability ports. Testbenches may probe
  internal signals hierarchically.
- Avoid resolution-sized line buffers in codec blocks. `MAX_VISIBLE_WIDTH` and
  `MAX_VISIBLE_HEIGHT` must not quietly instantiate large storage.
- Do not buffer full tiles/frames unless the feature explicitly requires it.
  Prefer TU/block-sized buffers and streaming interfaces.
- Hard-coded bitstreams, entropy operation blobs, and opaque payload append
  hooks are bugs. Generate syntax from named fields and symbols.
- Keep local caches/hashes for IBC and prediction small. Store hashes/metadata
  before storing whole blocks unless exact compare becomes necessary.
- Preserve the shared AXI-facing top-level contract across codecs.

When optimizing bubbles, use testbench block waveform instrumentation instead
of guessing. See `docs/rtl/block-throughput-waveforms.md`.

## Shared Hardware Interface

Both codec top modules expose the same SoC-facing shape:

- AXI4-Lite control/status register slave.
- AXI4 memory-mapped source frame read master.
- AXI4 memory-mapped bitstream write master.

The shared register map is documented in `docs/rtl/hardware-interface.md`.
Codec-specific controls should not be added casually. If a future feature needs
one, document why it cannot be represented as a shared encoder setting.

The internal packet contract currently uses visible 8x8 block packets where
possible. Preserve this unless a codec-specific scan order is clearly cheaper
and documented.

## Codec-Specific Notes

### VVC

- Current top-level public interface uses shared AXI control/read/write.
- Larger pictures are currently emitted as 64x64 CTU-local slices, one slice
  per CTU.
- The 4:2:0 path is lossy and uses fixed 8x8 luma transform blocks and 4x4
  chroma transform blocks.
- The 4:4:4 path is lossless screen content using palette plus escape values,
  residual handling, and CTU-local hash IBC.
- CABAC context labels should be shared/included rather than duplicated when
  practical.

### AV2

- AV2 is the active growth area for lossless screen-content work.
- Keep coding leaves fixed at visible 8x8 blocks for now.
- AV2 palette syntax is luma-only in the current reference-compatible path.
  Chroma must use BDPCM/residual/IBC-style coding, not private chroma palette
  syntax.
- Lossless 4:4:4 currently combines luma palette prediction, luma residual,
  chroma BDPCM, restricted intra prediction, and local hash IBC.
- The lossy 4:2:0 path exists as a comparability guard with VVC.
- Do not reintroduce AV2 hard-coded OBU/bitstream blobs.
- Planned AV2 work is tracked in `docs/av2/roadmap.md`. The next feature work
  should generally come from that roadmap.

## Test Vector Policy

- Committed manifests live under `verification/test_vector_sets/`.
- Machine-local manifests live under `verification/test_vector_sets/local/` and
  should normally remain uncommitted.
- RaceHorses and screenshot source files are local to the developer machine.
  Do not add absolute local paths to public docs or Makefile help.
- Generated vectors and validation outputs are under `verification/generated/`
  and should normally remain uncommitted.
- Use deterministic generation/cropping so results can be reproduced.

Important recurring sets:

- `screenshot-sweep-444`
- `screenshot-multictu-444`
- `racehorses-sweep-420`
- `racehorses-multictu-420`
- `multiframe-smoke`

## Throughput And Bubble Metrics

Bubble-rate work is a first-class optimization target.

Track:

- output utilization
- bubble rate
- cycles per bit
- cycles per input pixel
- block-level waiting/working/backpressure/idle rates

For RTL changes, keep utilization baseline or improve it unless there is a
clear feature reason. The current numeric bubble-rate target is maintained in
`docs/validation/targets.md`.

Use:

```sh
make validate-set CODEC=av2 VALIDATION_SET=<set> VALIDATION_BLOCK_WAVEFORM=1 VALIDATION_WITH_SYNTH=0
```

Inspect the generated `.html`, `.json`, `.vcd`, and `.gtkw` waveform reports
under `verification/generated/checksums/<codec>/`.

## Git And Local-State Rules

- Always check `git status --short` before edits.
- Do not revert or overwrite user changes unless explicitly requested.
- Keep local machine artifacts uncommitted unless the user asks otherwise.
- Prefer small commits that preserve known-good checkpoints.
- If reports depend on a source SHA, commit validated source first, then update
  reports with that SHA and commit the report update separately when practical.
- Do not use destructive git commands such as `git reset --hard` or
  `git checkout --` unless the user explicitly requested that operation.

Common untracked local files that should normally remain local include:

- screenshots used as local sources
- Vivado auth/license helper scripts
- `T-REC-H.266-*.pdf`
- local monitor/resume helper scripts
- `.tools/`
- `verification/generated/`
- `synth/out/`

## Coding Practices

- Use `rg`/`rg --files` for searches.
- Use `apply_patch` for manual file edits.
- Keep generated or mechanical formatting changes separate from logic changes
  when possible.
- Rust changes should pass `cargo fmt` and relevant tests.
- Python helper changes should pass `python3 -m py_compile scripts/*.py`.
- Keep comments concise and useful. Add comments for spec references or
  non-obvious hardware tradeoffs, not for obvious assignments.
- Prefer structured parsing and existing helper APIs over ad hoc string
  manipulation.

## When Unsure

Use this priority order:

1. Preserve bit-exact software/RTL/reference validation.
2. Preserve synthesizability and the shared AXI public interface.
3. Keep the implementation spec-auditable.
4. Keep reports current and concise.
5. Optimize area, timing, and bubble rate incrementally.

If a requested shortcut would hide a bug, weaken validation, add an opaque
payload, or make the RTL harder to synthesize, surface that tradeoff before
continuing.
