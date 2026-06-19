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

## 2026-06-19 VVC Throughput Optimization Validation

Measured after optimizing the shared AXI source fetch path and the VVC luma
residual AC coefficient path. These RTL changes do not change the software
encoder algorithm or VVC syntax, so bitrate deltas are zero for existing
documented vectors. This checkpoint adds local RaceHorses 4:2:0 crop coverage
to the quality/bitrate report.

Source baseline:

- Baseline Git SHA: `f0fc6dd70d0aacccc6a8474560c14f5118defd14`
- Current validated RTL Git SHA: `ffb4179caa0de4a4a4e52f4a21eaf9ddb39efc64`
- Current mode: shared AXI top-level interface with a direct plane-row source
  cache, 4:2:0 residual path, and 4:4:4 palette/BDPCM/transform-skip subset.
- Delta columns compare SW and RTL bitstreams for the same current vector.
  All listed deltas are zero because the RTL remains bit-exact with the
  software model.

Validation commands:

```sh
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

make validate-set CODEC=vvc \
  VALIDATION_SET=racehorses-sweep-420 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=racehorses-multictu-420 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
- `racehorses-sweep-420`: OK (64/64)
- `racehorses-multictu-420`: OK (10/10)
- All listed vectors matched SW/RTL bitstream checksums.
- All listed vectors matched SW/RTL/VTM reconstruction checksums.

Aggregate quality/bitrate:

| Set | Cases | Status | SW bits | SW bpp | PSNR |
|---|---:|---|---:|---:|---|
| screenshot-sweep-444 | 64 | PASS | 398840 | 4.8085 | inf |
| screenshot-multictu-444 | 10 | PASS | 319168 | 3.4753 | inf |
| racehorses-sweep-420 | 64 | PASS | 113168 | 1.3644 | avg 23.03 dB, range 19.43-29.32 dB |
| racehorses-multictu-420 | 10 | PASS | 92920 | 1.0118 | avg 22.35 dB, range 22.11-22.74 dB |

The `inf` PSNR entries indicate byte-exact 4:4:4 reconstruction against the
source integer samples. The finite RaceHorses PSNR values are expected for the
current lossy 4:2:0 residual path.

### RaceHorses 4:2:0 Sweep

Aggregate SW bits: `113168`.
Aggregate SW bpp: `1.3644`.

| Vector | Status | SW bits | SW bpp | PSNR |
|---|---|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 568 | 8.8750 | 27.17 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 672 | 5.2500 | 21.98 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 720 | 3.7500 | 21.61 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 808 | 3.1562 | 19.82 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 872 | 2.7250 | 20.06 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 960 | 2.5000 | 19.43 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1016 | 2.2679 | 19.53 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1120 | 2.1875 | 19.97 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 616 | 4.8125 | 28.90 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 808 | 3.1562 | 21.09 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 | 2.3750 | 26.22 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1040 | 2.0312 | 24.37 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1192 | 1.8625 | 24.09 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1288 | 1.6771 | 26.14 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 1440 | 1.6071 | 23.67 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 1600 | 1.5625 | 24.00 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 680 | 3.5417 | 29.32 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 920 | 2.3958 | 22.84 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1096 | 1.9028 | 23.33 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1312 | 1.7083 | 22.97 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 1504 | 1.5667 | 22.00 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 1672 | 1.4514 | 22.20 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 1904 | 1.4167 | 22.14 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 2088 | 1.3594 | 22.15 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 760 | 2.9688 | 28.16 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1064 | 2.0781 | 22.52 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1304 | 1.6979 | 22.06 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 1544 | 1.5078 | 21.37 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 1800 | 1.4062 | 21.62 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 2016 | 1.3125 | 20.99 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 2288 | 1.2768 | 21.29 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 2504 | 1.2227 | 21.23 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 792 | 2.4750 | 28.15 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1152 | 1.8000 | 24.04 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1440 | 1.5000 | 23.51 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 1744 | 1.3625 | 23.28 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 2072 | 1.2950 | 23.73 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 2360 | 1.2292 | 23.50 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 2672 | 1.1929 | 23.90 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 2960 | 1.1562 | 23.60 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 848 | 2.2083 | 28.23 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1232 | 1.6042 | 24.44 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 1608 | 1.3958 | 22.96 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 1944 | 1.2656 | 22.43 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 2272 | 1.1833 | 22.05 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 2648 | 1.1493 | 21.50 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 3000 | 1.1161 | 21.99 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 3312 | 1.0781 | 22.03 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 968 | 2.1607 | 22.29 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 1440 | 1.6071 | 22.21 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 1816 | 1.3512 | 22.04 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 2248 | 1.2545 | 21.81 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 2632 | 1.1750 | 22.48 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 3024 | 1.1250 | 22.03 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 3400 | 1.0842 | 22.41 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 3792 | 1.0580 | 22.41 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1048 | 2.0469 | 22.85 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 1584 | 1.5469 | 23.20 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 2024 | 1.3177 | 23.04 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 2528 | 1.2344 | 22.97 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 2912 | 1.1375 | 23.10 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 3408 | 1.1094 | 22.72 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 3880 | 1.0826 | 22.51 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 4320 | 1.0547 | 22.55 |

### RaceHorses Multi-CTU And Partial Crops

Aggregate SW bits: `92920`.
Aggregate SW bpp: `1.0118`.

| Vector | Status | SW bits | SW bpp | PSNR |
|---|---|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 8480 | 1.0352 | 22.52 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 8216 | 1.0029 | 22.23 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 15584 | 0.9512 | 22.16 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 12664 | 1.0306 | 22.22 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 11240 | 0.9147 | 22.68 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 5056 | 1.0972 | 22.74 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 5064 | 1.0990 | 22.20 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 5912 | 1.1404 | 22.40 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 11264 | 1.0353 | 22.11 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 9440 | 1.0243 | 22.23 |

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
