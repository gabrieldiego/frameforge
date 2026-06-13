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

## Retired Bring-Up Measurements

Temporary AV2 fixed-output emitters existed during validation plumbing bring-up.
Those measurements are intentionally retired because the source streams and
trace-derived entropy data were removed. Future synthesis baselines should only
cover implementations that generate bitstream content from named, spec-auditable
syntax decisions.
