# AV2 Synthesis Baseline

This file records the latest AV2-specific Yosys synthesis checkpoint.
Older measurements are intentionally left to git history so this page stays
focused on the current baseline and immediate delta. The shared synthesis flow
is documented in [../synthesis.md](../synthesis.md).

## 2026-06-24 Packet Ingress Checkpoint

Baseline and current sources:

- Baseline Git SHA: `2ac43800abe655dd03f213a1cb3e70b604fde4c1`
- Current validated source Git SHA: `a5d5f94c7c73b42920f9405bc41d6c14244de12e`

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
| Main Yosys elapsed time (s) | 275.10 s | 368.20 s | +93.10 s |
| Runner-observed peak child RSS (MiB) | 1483.31 MiB | 1734.85 MiB | +251.54 MiB |
| Topological path length | 55 | 229 | +174 |
| Flattened cells | 80823 | 93311 | +12488 |
| Estimated LCs | 31215 | 37032 | +5817 |
| CARRY4 | 2657 | 2797 | +140 |
| DSP48E1 | 15 | 15 | +0 |
| FDCE | 4771 | 4795 | +24 |
| FDPE | 27 | 27 | +0 |
| FDRE | 18063 | 22674 | +4611 |
| FDSE | 129 | 129 | +0 |
| LUT1 | 606 | 682 | +76 |
| LUT2 | 8586 | 11886 | +3300 |
| LUT3 | 8579 | 7450 | -1129 |
| LUT4 | 5543 | 5412 | -131 |
| LUT5 | 3557 | 5250 | +1693 |
| LUT6 | 13536 | 18920 | +5384 |
| MUXF7 | 5541 | 4187 | -1354 |
| MUXF8 | 1119 | 949 | -170 |
| RAMB36E1 | 30 | 30 | +0 |
| RAM32M | 10 | 10 | +0 |

Critical-path summary:

- Longest topological path in `ff_av2_encoder`: length 229.
- Reported limiter: packet palette insertion in
  `ff_av2_palette_analyzer_444`, through the eight-lane palette-color insert
  chain into `palette_color_q`.
- Longest topological path in `ff_av2_chroma_sample_store`: length 1.
- The sample store is inferred as three `RAMB36E1` memories again after
  removing the stale byte-write fallback from the row-write path.

Notes:

- Packet ingress removes the scalar unpacker from the hot path and lets the
  analyzer, IBC hash matcher, and 4:2:0 DC estimator consume eight samples per
  accepted packet.
- The 4:2:0 residual estimator now consumes cached 4x4 sample sums collected
  during ingress, avoiding a repeated 16-sample adder tree during residual
  coding.
- The bubble-rate target is not fully met yet. Remaining multi-CTU bubbles are
  dominated by serialized leaf entropy/residual work and by byte replay into
  the AXI writer. Future work should target streaming carry/output and a
  shorter packet palette insertion path before adding more syntax.
