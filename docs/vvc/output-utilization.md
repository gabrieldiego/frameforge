# VVC RTL Output Utilization Baseline

This report records the latest VVC RTL throughput checkpoint. Older detailed
measurement sections are intentionally left to git history so this file stays
focused on the current optimization baseline and immediate deltas.

Metric definitions:

- `output_utilization`: accepted output bytes divided by total measured cycles.
- `bubble_rate`: `1 - output_utilization`.
- `cycles/bit`: total measured cycles divided by RTL bitstream bits.
- `cycles/input pixel`: total measured cycles divided by `width * height * frames`.
- Internal block utilization is testbench instrumentation. It is used to find
  pipeline starvation/backpressure and is not part of the codec bitstream
  contract.

## 2026-06-23 AXI Reader And Palette Packet Checkpoint

Baseline RTL/source Git SHA:

- `1f2e144c57cb20f7f7ca4aa2c436a6d43162a2c8`

Current RTL/source Git SHA:

- `98ab0d150875b5899c9d08f9848574373707e187`

Validation result:

- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/VTM checksum parity.
- Smoke: `racehorses_crop_64x64_1f_yuv420p8.yuv` PASS, strict SW/RTL/VTM
  checksum parity. PSNR: 22.55 dB.
- Synthesis was not rerun for this utilization-only checkpoint.

Target status:

- Requested target: aggregate multi-CTU bubble rate below `0.800`.
- Current `screenshot-multictu-444` aggregate bubble rate: `0.771`.
- Seven of ten vectors are below `0.800` individually. The three remaining
  outliers are very low-byte grid/vertical-partial streams where fixed
  per-CTU/input traversal time dominates the byte-output metric.

Implementation notes:

- The common AXI frame reader now issues the next read address while the current
  packet is accepted, removing one address-phase bubble from the reader loop.
- Palette CU symbols now pack four palette indices into one internal source
  packet. The CABAC frontend expands the packet back into the spec-visible index
  syntax, so SW/RTL/VTM bitstreams and reconstructions remain unchanged.
- The regenerated waveforms show the reader cache is active on adjacent 8-pixel
  blocks. The next large improvement for the low-byte outliers would require a
  wider internal packet/leaf interface or deeper prefetching, not another small
  CABAC-side cleanup.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-multictu-444` | 10 | 289000 (+0) | 157963 (-326900) | 36125 (+0) | 121838 (-326900) | 0.229 (+0.154) | 0.771 (-0.154) | 0.547 (-1.13) | 1.72 (-3.56) |

Internal aggregate observations:

| Probe | Rate |
|---|---:|
| Final byte output | 0.229 |
| Frame reader sample issue | 0.458 |
| Frame reader to FIFO handoff | 1.000 |
| Frame reader advance cache hit | 0.413 |
| AXI write accepted-beat readiness | 1.000 |

Per-vector top-level metrics:

| Vector | Status | RTL bits | Total cycles (delta) | Active cycles | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 47464 | 20829 (-31751) | 5933 | 0.285 (+0.172) | 0.715 (-0.172) | 0.439 (-0.671) | 2.54 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 18832 | 11683 (-28603) | 2354 | 0.201 (+0.143) | 0.799 (-0.143) | 0.620 (-1.52) | 1.43 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 6288 | 12406 (-52986) | 786 | 0.0634 (+0.0514) | 0.937 (-0.0514) | 1.97 (-8.43) | 0.757 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 33776 | 18996 (-43183) | 4222 | 0.222 (+0.154) | 0.778 (-0.154) | 0.562 (-1.28) | 1.55 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 49064 | 23865 (-45886) | 6133 | 0.257 (+0.169) | 0.743 (-0.169) | 0.486 (-0.934) | 1.94 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 27872 | 13061 (-18269) | 3484 | 0.267 (+0.156) | 0.733 (-0.156) | 0.469 (-0.651) | 2.83 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1648 | 3534 (-14542) | 206 | 0.0583 (+0.0473) | 0.942 (-0.0473) | 2.14 (-8.86) | 0.767 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2232 | 5102 (-15863) | 279 | 0.0547 (+0.0417) | 0.945 (-0.0417) | 2.29 (-7.10) | 0.984 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 62832 | 29507 (-41157) | 7854 | 0.266 (+0.155) | 0.734 (-0.155) | 0.470 (-0.650) | 2.71 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 38992 | 18980 (-34660) | 4874 | 0.257 (+0.166) | 0.743 (-0.166) | 0.487 (-0.893) | 2.06 |

Regenerated waveform artifacts are under `verification/generated/checksums/vvc/`
for each vector. Use the matching `*_rtl_block_waveform.html` file for the
color-coded block-state timeline or `*_rtl_block_waveform.gtkw` for GTKWave.
