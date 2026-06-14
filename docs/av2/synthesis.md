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

## 2026-06-13 Structured Black + First Luma Palette

Configuration:

- command: `make synth CODEC=av2`
- DUT: `av2-encoder`
- RTL top: `ff_av2_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- supported RTL input subset: planar 8-bit 4:4:4, up to 64x64, black frames
  plus the deterministic 64x64 two-color luma-palette bars smoke vector.

Validation before synthesis:

```sh
cargo test av2 -- --nocapture
make -B rtl-test CODEC=av2 DUT=av2-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
make validate-set CODEC=av2 VALIDATION_SET=sweep-black-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set CODEC=av2 VALIDATION_SET=av2-palette-luma-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
```

Result:

- Yosys synthesis passed in 34.6 seconds.
- Peak child RSS observed by the synthesis runner was 302.04 MiB.
- Post-synthesis critical-path reporting completed in 4.8 seconds and reported
  path length 62.
- The critical path remained in the existing partition/range-coder logic, not
  the first palette symbolizer.

Flattened Xilinx-cell estimate from
`yosys -p 'read_json synth/out/arty-z7-10/ff_av2_encoder/ff_av2_encoder.json; hierarchy -top ff_av2_encoder; flatten; stat -tech xilinx'`:

| Metric | Count |
|---|---:|
| Cells | 8076 |
| Estimated LCs | 3387 |
| CARRY4 | 387 |
| DSP48E1 | 14 |
| FDCE | 775 |
| FDPE | 32 |
| FDRE | 450 |
| LUT1 | 30 |
| LUT2 | 1123 |
| LUT3 | 756 |
| LUT4 | 523 |
| LUT5 | 671 |
| LUT6 | 1437 |
| MUXF7 | 543 |
| MUXF8 | 173 |
| RAMB18E1 | 3 |

This is the first useful AV2 encoder synthesis baseline. Comparing it with the
integration shell is only useful to show expected growth from unsupported
plumbing into real generated tile syntax; the shell was not a real encoder area
estimate.

## Retired Bring-Up Measurements

Temporary AV2 fixed-output emitters existed during validation plumbing bring-up.
Those measurements are intentionally retired because the source streams and
trace-derived entropy data were removed. Future synthesis baselines should only
cover implementations that generate bitstream content from named, spec-auditable
syntax decisions.
