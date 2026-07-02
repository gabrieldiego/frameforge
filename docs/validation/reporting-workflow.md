# Reporting Workflow

FrameForge reports are part of the engineering contract. They document whether
a feature changed bitrate, output utilization, synthesis cost, or timing.

## Report Types

Each codec has three main reports:

| Report | When to update |
|---|---|
| `docs/<codec>/quality-bitrate.md` | Encoder decisions, syntax, prediction, residuals, reconstruction, or quality changed. |
| `docs/<codec>/output-utilization.md` | RTL changed or validation cycle metrics changed. |
| `docs/<codec>/synthesis.md` | RTL changed or synthesis settings/results changed. |

Older measurements should stay in git history. Keep the markdown focused on the
latest checkpoint and immediate deltas.

## Preferred Commit Order

When practical:

1. Implement and validate source changes.
2. Run the relevant regression and synthesis.
3. Commit validated source changes.
4. Regenerate reports using the source commit SHA as the current SHA.
5. Commit report changes separately.

This keeps report SHAs meaningful and makes it easy to identify which source
commit produced a measured checkpoint.

For small documentation-only changes, no validation report update is required.

## Standard Report Cycle

For AV2:

```sh
make report-codec CODEC=av2 REPORT_SYNTHESIS_TOOL=yosys
```

For VVC:

```sh
make report-codec CODEC=vvc REPORT_SYNTHESIS_TOOL=yosys
```

The `report-codec` target runs the recurring report-backed regression sets,
runs synthesis, and then updates the codec reports.

Use Vivado mode only when Vivado synthesis was intentionally run for the
checkpoint:

```sh
make report-codec CODEC=av2 REPORT_SYNTHESIS_TOOL=yosys-vivado
```

If Vivado reports are missing, report generation should say that Vivado was not
rerun rather than failing with a stale or misleading result.

## Manual Report Regeneration

When validation and synthesis were already run and you only need to refresh the
markdown from existing artifacts:

```sh
python3 scripts/update_codec_reports.py \
  --codec av2 \
  --checkpoint-title "YYYY-MM-DD AV2 Report Checkpoint" \
  --synthesis-tool yosys
```

Useful optional flags:

- `--current-sha <sha>` records an explicit validated source SHA.
- `--baseline-ref <ref>` reads baseline metrics from reports at a git ref.
- `--output-baseline-sha <sha>` overrides output-utilization baseline SHA.
- `--quality-baseline-sha <sha>` overrides quality/bitrate baseline SHA.
- `--synthesis-baseline-sha <sha>` overrides synthesis baseline SHA.

Use explicit SHAs when generating reports after a source commit has already
been made or when comparing against a known milestone.

## What To Include

Quality/bitrate reports should include:

- validation result per set;
- per-vector SW bit counts and bpp;
- PSNR, including `inf` for lossless paths;
- deltas against the previous relevant checkpoint;
- feature-specific summaries when useful, such as IBC candidate counts.

Output-utilization reports should include:

- per-set aggregate RTL bits, cycles, active cycles, wait cycles;
- cycles per input pixel as the primary throughput metric;
- output utilization, bubble rate, and cycles per bit as secondary diagnostic
  metrics;
- per-vector rows;
- relevant internal probe rates when available.

Bubble-rate regressions are still useful for locating local stalls, especially
with block waveforms, but they are not the top-level throughput acceptance gate.
The current numeric target is maintained in `docs/validation/targets.md`.

Synthesis reports should include:

- Yosys elapsed time and peak memory;
- topological path length and likely limiter;
- flattened cells, estimated LCs, and notable primitives;
- Vivado WNS/WHS/resource data when run;
- baseline and current Git SHAs.

## When Full Regression Is Not Practical

If a full regression cannot be run in the current session:

- fix known report-generation or documentation problems first;
- do not claim a fresh validation checkpoint;
- regenerate reports from existing artifacts only if that is explicitly useful;
- clearly state that reports came from available artifacts.

Functional or RTL source changes should not be called validated until the
relevant regression and synthesis targets have actually passed.
