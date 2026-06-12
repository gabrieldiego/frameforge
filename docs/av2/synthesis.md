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

## Temporary Black-Frame Payload Note

After this baseline, the AV2 RTL top gained a TODO-marked fixed OBU stream for
one black 64x64 `yuv444p8` frame. The first version was simulation-only. It was
then replaced with the synthesizable fixed-emitter baseline below so AV2
synthesis remains continuously checked while real AV2 syntax emission is
implemented.

## 2026-06-12 Fixed Black-Frame OBU Emitter

Configuration:

- command: `make synth CODEC=av2`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB

Result:

- Yosys synthesis passed in 4.8 seconds.
- Peak child RSS observed by the synthesis runner was 128.29 MiB.
- Post-synthesis critical-path reporting completed in 0.1 seconds and reported
  path length 9.
- Mapped top cell count from `ff_av2_encoder.json`: 173 total cells.
- Primitive breakdown: `BUFG=1`, `CARRY4=4`, `FDCE=18`, `IBUF=48`, `INV=23`,
  `LUT2=7`, `LUT3=8`, `LUT4=8`, `LUT5=15`, `LUT6=18`, `MUXF7=7`, `MUXF8=3`,
  `OBUF=13`.

Comparison to the initial streaming shell:

- Runtime increased by 0.6 seconds.
- Peak RSS increased by 0.93 MiB.
- Reported critical-path length is unchanged at 9.

This remains a bring-up baseline. The fixed byte stream is synthesizable, but it
is still a temporary source until the AV2 syntax generator is implemented in
RTL.
