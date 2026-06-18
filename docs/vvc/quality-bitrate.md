# VVC Quality And Bitrate Baseline

This file records the current VVC quality and bitrate checkpoint. Older
intermediate reports are intentionally kept out of this page so the current
baseline is easy to compare against future runs. Use git history for retired
measurements.

Synthesis area/timing belongs in [synthesis.md](synthesis.md). RTL output
utilization belongs in [output-utilization.md](output-utilization.md).

`scripts/validate.py` reports the software Annex-B stream and, when RTL
validation is enabled, the RTL Annex-B stream. Implemented VVC features are
expected to produce bit-exact software and RTL bitstreams. The reference path is
decode-only: VTM decodes the FrameForge bitstream and its reconstruction must
match the software/RTL reconstruction checksum.

## 2026-06-18 Shared AXI Interface Baseline

Measured after moving the VVC top-level integration to the shared AXI4-Lite
control interface plus AXI4 memory-mapped source/bitstream data movers. The
codec core still consumes the same internal 8x8/TU stream; the AXI reader and
writer are the public SoC-facing wrapper.

The same validation pass also fixed the multi-frame CRA slice header syntax:
non-IDR slices now signal the required empty `ref_pic_lists()` selection when
`pps_rpl_info_in_ph_flag` is 0, and slice-header byte alignment is emitted once
per H.266 7.3.7.

Source baseline:

- Source base Git SHA: `c6bcfcfae062a8671c4194d3e062f9b195134012`
- Current mode: shared AXI top-level interface, 4:2:0 residual path, 4:4:4
  palette/BDPCM/transform-skip subset, VTM-validated CRA slice headers.
- Delta columns are left out for this checkpoint. Future reports should use
  this table as the baseline and add deltas in parentheses.

Validation command:

```sh
make hardware-regression CODEC=vvc HARDWARE_REGRESSION_SYNTH=0
```

Validation result:

- `smoke`: OK (6/6)
- `sweep-420`: OK (64/64)
- `sweep-444`: OK (64/64)
- All listed vectors matched SW/RTL bitstream checksums.
- All listed vectors matched SW/RTL/VTM reconstruction checksums.
- 4:4:4 vectors are lossless (`inf` PSNR). 4:2:0 vectors use the current lossy
  residual path.

Full-regression aggregate bitrate:

| Set | Cases | Status | SW bits | SW bpp | PSNR |
|---|---:|---|---:|---:|---|
| sweep-420 | 64 | PASS | 44552 | 0.5371 | 49.89 dB |
| sweep-444 | 64 | PASS | 76144 | 0.9180 | inf |

Per-vector full-sweep metrics are retained in
`verification/generated/validation_logs/sweep-420_*.log` and
`verification/generated/validation_logs/sweep-444_*.log`.

Smoke-set aggregate bitrate:

Aggregate SW bits: `24392`.
Aggregate SW bpp over visible luma pixels: `0.8267`.

| Vector | Format | Frames | Status | SW bits | SW bpp | PSNR |
|---|---|---:|---|---:|---:|---:|
| black_8x8_1f_yuv420p8.yuv | yuv420p8 | 1 | PASS | 568 | 8.8750 | 49.89 |
| black_16x16_2f_yuv420p8.yuv | yuv420p8 | 2 | PASS | 784 | 1.5312 | 49.89 |
| screen_blocks_16x16_1f_yuv444p8.yuv | yuv444p8 | 1 | PASS | 648 | 2.5312 | inf |
| screen_blocks_64x64_1f_yuv444p8.yuv | yuv444p8 | 1 | PASS | 2608 | 0.6367 | inf |
| stick_walk_64x64_3f_30fps_yuv420p8.yuv | yuv420p8 | 3 | PASS | 8184 | 0.6660 | 18.56 |
| stick_walk_64x64_3f_30fps_yuv444p8.yuv | yuv444p8 | 3 | PASS | 11600 | 0.9440 | inf |

The `inf` PSNR entries indicate byte-exact reconstruction against the source
integer samples. The finite 4:2:0 PSNR entries are expected for the current
lossy residual implementation.
