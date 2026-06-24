# AV2 Synthesis Baseline

This file records the latest AV2-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-24 Full AV2 Regression Checkpoint

Baseline and current sources:

- Baseline Git SHA: `3945b1bc67a20e5cfa2ccf8d05910ab8741deef0`
- Current validated source Git SHA: `2ac43800abe655dd03f213a1cb3e70b604fde4c1`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.

Yosys synthesis configuration:

- command: `make synth CODEC=av2 SYNTH_DUT=av2-encoder`
- RTL top: `ff_av2_encoder`
- board/device metadata: Arty Z7-10, `xc7z010clg400-1`
- clock target metadata: 25 MHz
- max visible size: 1024x1024
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- palette 4:4:4 support: enabled

Yosys synthesis result:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Main Yosys elapsed time (s) | 244.40 s | 275.10 s | +30.70 s |
| Runner-observed peak child RSS (MiB) | 1443.55 MiB | 1483.31 MiB | +39.76 MiB |
| Topological path length | 55 | 55 | +0 |
| Flattened cells | 73599 | 80823 | +7224 |
| Estimated LCs | 26306 | 31215 | +4909 |
| CARRY4 | 2648 | 2657 | +9 |
| DSP48E1 | 13 | 15 | +2 |
| FDCE | 4742 | 4771 | +29 |
| FDPE | 27 | 27 | +0 |
| FDRE | 18111 | 18063 | -48 |
| FDSE | 129 | 129 | +0 |
| LUT1 | 682 | 606 | -76 |
| LUT2 | 7980 | 8586 | +606 |
| LUT3 | 5646 | 8579 | +2933 |
| LUT4 | 4667 | 5543 | +876 |
| LUT5 | 3189 | 3557 | +368 |
| LUT6 | 12804 | 13536 | +732 |
| MUXF7 | 4127 | 5541 | +1414 |
| MUXF8 | 786 | 1119 | +333 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest topological path in `ff_av2_encoder`: length 55.
- Reported limiter: palette query/index path through the luma palette
  symbolizer and AV2 range-coder normalization into `low_q`.
- `ff_av2_chroma_sample_store` remains inferred as three `RAMB36E1`
  memories in the hierarchy report.

Notes:

- The retained RTL keeps the scalar palette map path. A row-wide and a
  two-sample map experiment were rejected because they did not improve
  top-level output utilization enough to justify the extra logic.
- The current synthesis is still below the 600 second hard stop and below
  the 3072 MiB memory limit, but it is slower and larger than the previous
  documented AV2 baseline. The next throughput-focused work should target
  packetized input/frame-store integration rather than adding combinational
  palette analyzer fanout.
