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

Validation commands:

```sh
make hardware-regression CODEC=vvc HARDWARE_REGRESSION_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `smoke`: OK (6/6)
- `sweep-420`: OK (64/64)
- `sweep-444`: OK (64/64)
- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
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

### Full Screenshot Sweep

Aggregate SW bits: `398840` (0).
Aggregate SW bpp: `4.8085` (0.0000).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 536 (0) | 8.3750 (0.0000) | inf |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 976 (0) | 7.6250 (0.0000) | inf |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 600 (0) | 3.1250 (0.0000) | inf |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 816 (0) | 3.1875 (0.0000) | inf |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 680 (0) | 2.1250 (0.0000) | inf |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 712 (0) | 1.8542 (0.0000) | inf |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 4688 (0) | 10.4643 (0.0000) | inf |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 4344 (0) | 8.4844 (0.0000) | inf |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1112 (0) | 8.6875 (0.0000) | inf |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 2240 (0) | 8.7500 (0.0000) | inf |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 712 (0) | 1.8542 (0.0000) | inf |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 784 (0) | 1.5312 (0.0000) | inf |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 6128 (0) | 9.5750 (0.0000) | inf |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 912 (0) | 1.1875 (0.0000) | inf |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 6200 (0) | 6.9196 (0.0000) | inf |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 1048 (0) | 1.0234 (0.0000) | inf |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 2304 (0) | 12.0000 (0.0000) | inf |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 1496 (0) | 3.8958 (0.0000) | inf |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 2952 (0) | 5.1250 (0.0000) | inf |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 7784 (0) | 10.1354 (0.0000) | inf |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 6080 (0) | 6.3333 (0.0000) | inf |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 1112 (0) | 0.9653 (0.0000) | inf |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1208 (0) | 0.8988 (0.0000) | inf |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 11328 (0) | 7.3750 (0.0000) | inf |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 1512 (0) | 5.9062 (0.0000) | inf |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1376 (0) | 2.6875 (0.0000) | inf |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1544 (0) | 2.0104 (0.0000) | inf |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 4440 (0) | 4.3359 (0.0000) | inf |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1192 (0) | 0.9313 (0.0000) | inf |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 13096 (0) | 8.5260 (0.0000) | inf |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 12696 (0) | 7.0848 (0.0000) | inf |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1576 (0) | 0.7695 (0.0000) | inf |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 3080 (0) | 9.6250 (0.0000) | inf |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 5896 (0) | 9.2125 (0.0000) | inf |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1344 (0) | 1.4000 (0.0000) | inf |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 10104 (0) | 7.8937 (0.0000) | inf |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 11616 (0) | 7.2600 (0.0000) | inf |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2720 (0) | 1.4167 (0.0000) | inf |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 10552 (0) | 4.7107 (0.0000) | inf |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2152 (0) | 0.8406 (0.0000) | inf |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 768 (0) | 2.0000 (0.0000) | inf |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 9792 (0) | 12.7500 (0.0000) | inf |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 7256 (0) | 6.2986 (0.0000) | inf |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 7728 (0) | 5.0312 (0.0000) | inf |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 14960 (0) | 7.7917 (0.0000) | inf |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1720 (0) | 0.7465 (0.0000) | inf |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10256 (0) | 3.8155 (0.0000) | inf |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2408 (0) | 0.7839 (0.0000) | inf |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 3632 (0) | 8.1071 (0.0000) | inf |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 5496 (0) | 6.1339 (0.0000) | inf |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 6280 (0) | 4.6726 (0.0000) | inf |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 9936 (0) | 5.5446 (0.0000) | inf |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 17888 (0) | 7.9857 (0.0000) | inf |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 13432 (0) | 4.9970 (0.0000) | inf |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 25480 (0) | 8.1250 (0.0000) | inf |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 14792 (0) | 4.1272 (0.0000) | inf |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 2344 (0) | 4.5781 (0.0000) | inf |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 8768 (0) | 8.5625 (0.0000) | inf |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 7088 (0) | 4.6146 (0.0000) | inf |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 14128 (0) | 6.8984 (0.0000) | inf |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2440 (0) | 0.9531 (0.0000) | inf |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 23176 (0) | 7.5443 (0.0000) | inf |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3952 (0) | 1.1027 (0.0000) | inf |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 33472 (0) | 8.1719 (0.0000) | inf |

### Screenshot Multi-CTU And Partial Crops

Aggregate SW bits: `319168` (0).
Aggregate SW bpp: `3.4753` (0.0000).

| Vector | Status | SW bits (delta) | SW bpp (delta) | PSNR |
|---|---|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 48360 (0) | 5.9033 (0.0000) | inf |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 22256 (0) | 2.7168 (0.0000) | inf |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 13888 (0) | 0.8477 (0.0000) | inf |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 37776 (0) | 3.0742 (0.0000) | inf |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 52832 (0) | 4.2995 (0.0000) | inf |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 28096 (0) | 6.0972 (0.0000) | inf |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3024 (0) | 0.6562 (0.0000) | inf |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3904 (0) | 0.7531 (0.0000) | inf |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 67400 (0) | 6.1949 (0.0000) | inf |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 41632 (0) | 4.5174 (0.0000) | inf |

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
