# AV2 Synthesis Baselines

This file records AV2-specific synthesis measurements. The shared command
wrapper is documented in [../synthesis.md](../synthesis.md), but AV2 area,
timing, elapsed time, and memory results are tracked separately from VVC.

## 2026-06-12 Initial Top-Level Entry

Configuration:

- command: `make synth CODEC=av2 SYNTH_TIMEOUT_SEC=120 SYNTH_WARN_AFTER_SEC=60`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`

Result:

- Yosys synthesis passed in 4.2 seconds.
- Peak child RSS observed by the synthesis runner was 127.36 MiB.
- Post-synthesis critical-path reporting completed in 0.1 seconds and reported
  path length 9.

This measurement covers only the initial AV2 streaming entry point. It is useful
as a routing and synthesis-wrapper baseline, not as an estimate of a real AV2
encoder implementation.
