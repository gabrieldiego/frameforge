# AV2 RTL Output Utilization Baselines

This file records AV2 RTL simulation throughput counters per validation
vector. It is separate from quality/bitrate reporting because these numbers
describe testbench-observed output timing, not compression efficiency.

Metric definitions:

- `total_cycles`: RTL cycles from encoder start until the final output byte is
  accepted on `m_axis`.
- `output_active_cycles`: cycles where `m_axis_valid && m_axis_ready` accepted
  one output byte. The AV2 encoder testbench holds `m_axis_ready` high.
- `output_wait_cycles`: `total_cycles - output_active_cycles`.
- `output_utilization`: `output_active_cycles / total_cycles`; this is the
  ratio of cycles outputting data to total cycles.
- `bubble_rate`: `1 - output_utilization`, the fraction of measured cycles
  spent not accepting output bytes.
- `cycles/bit`: `total_cycles / rtl_bitstream_bits`.
- `cycles/input pixel`: `total_cycles / (width * height * frames)`.
- The metrics JSON also records `state_cycles`, `leaf_phase_cycles`,
  `pipeline_cycles`, `entropy_op_cycles`, `pending_push_cycles`, and
  `input_sample_cycles` for AV2-specific profiling. The constants and JSON
  writer for these internal counters live in `tb/av2_metrics.py`; they are
  not part of the shared top-level pass/fail contract.

## 2026-06-21 Palette Index RAM Storage

Measured after moving the AV2 4:4:4 palette index table from a 64-entry
flip-flop bank into `ff_sync_block_ram_1r1w`. This reduces area while keeping
the external palette query handshake and output schedule unchanged.

Baseline and current sources:

- Baseline report Git SHA: `1d39efb13aca62789800ab3f21cb4f1ba9471d19`
- Baseline validated RTL Git SHA: `28df2e21c2a44d6ba00e819616a10fb1b9686bf1`
- Current validated RTL Git SHA: `113d850538d22e12dd5e9a29ed54ab0f25e6aa67`
- Baseline mode: AV2 palette analyzer with terminal predictor-edge state
  collapsed and the palette-index table still stored in flip-flops.
- Current mode: same codec behavior, with one 192-bit palette-index RAM word
  per 8x8 leaf.
- Delta columns compare against the immediate previous validated 4:4:4
  checkpoint. Output scheduling is unchanged, so all cycle deltas are zero.

Validation result:

- `screenshot-sweep-444`: OK (64/64).
- `screenshot-multictu-444`: OK (10/10).
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot-sweep-444 | 64 | 755272 (+0) | 1194284 (+0) | 94409 (+0) | 1099875 (+0) | 0.079 (+0.000) | 0.921 (+0.000) | 1.581 (+0.000) | 14.795 (+0.000) |
| screenshot-multictu-444 | 10 | 570480 (+0) | 1098202 (+0) | 71310 (+0) | 1026892 (+0) | 0.065 (+0.000) | 0.935 (+0.000) | 1.925 (+0.000) | 12.118 (+0.000) |

### Full Screenshot Sweep

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 834 (+0) | 43 (+0) | 791 (+0) | 0.052 (+0.000) | 0.948 (+0.000) | 2.424 (+0.000) | 13.031 (+0.000) |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 2490 (+0) | 248 (+0) | 2242 (+0) | 0.100 (+0.000) | 0.900 (+0.000) | 1.255 (+0.000) | 19.453 (+0.000) |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 1924 (+0) | 52 (+0) | 1872 (+0) | 0.027 (+0.000) | 0.973 (+0.000) | 4.625 (+0.000) | 10.021 (+0.000) |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 2684 (+0) | 92 (+0) | 2592 (+0) | 0.034 (+0.000) | 0.966 (+0.000) | 3.647 (+0.000) | 10.484 (+0.000) |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 3017 (+0) | 60 (+0) | 2957 (+0) | 0.020 (+0.000) | 0.980 (+0.000) | 6.285 (+0.000) | 9.428 (+0.000) |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 3527 (+0) | 65 (+0) | 3462 (+0) | 0.018 (+0.000) | 0.982 (+0.000) | 6.783 (+0.000) | 9.185 (+0.000) |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (+0) | 8551 (+0) | 858 (+0) | 7693 (+0) | 0.100 (+0.000) | 0.900 (+0.000) | 1.246 (+0.000) | 19.087 (+0.000) |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 9450 (+0) | 852 (+0) | 8598 (+0) | 0.090 (+0.000) | 0.910 (+0.000) | 1.386 (+0.000) | 18.457 (+0.000) |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (+0) | 2421 (+0) | 228 (+0) | 2193 (+0) | 0.094 (+0.000) | 0.906 (+0.000) | 1.327 (+0.000) | 18.914 (+0.000) |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 5380 (+0) | 577 (+0) | 4803 (+0) | 0.107 (+0.000) | 0.893 (+0.000) | 1.166 (+0.000) | 21.016 (+0.000) |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 472 (+0) | 3373 (+0) | 59 (+0) | 3314 (+0) | 0.017 (+0.000) | 0.983 (+0.000) | 7.146 (+0.000) | 8.784 (+0.000) |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 512 (+0) | 4273 (+0) | 64 (+0) | 4209 (+0) | 0.015 (+0.000) | 0.985 (+0.000) | 8.346 (+0.000) | 8.346 (+0.000) |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 12617 (+0) | 1218 (+0) | 11399 (+0) | 0.097 (+0.000) | 0.903 (+0.000) | 1.295 (+0.000) | 19.714 (+0.000) |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 608 (+0) | 6226 (+0) | 76 (+0) | 6150 (+0) | 0.012 (+0.000) | 0.988 (+0.000) | 10.240 (+0.000) | 8.107 (+0.000) |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 15333 (+0) | 1331 (+0) | 14002 (+0) | 0.087 (+0.000) | 0.913 (+0.000) | 1.440 (+0.000) | 17.113 (+0.000) |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 696 (+0) | 8176 (+0) | 87 (+0) | 8089 (+0) | 0.011 (+0.000) | 0.989 (+0.000) | 11.747 (+0.000) | 7.984 (+0.000) |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 4229 (+0) | 442 (+0) | 3787 (+0) | 0.105 (+0.000) | 0.895 (+0.000) | 1.196 (+0.000) | 22.026 (+0.000) |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 5062 (+0) | 341 (+0) | 4721 (+0) | 0.067 (+0.000) | 0.933 (+0.000) | 1.856 (+0.000) | 13.182 (+0.000) |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 9914 (+0) | 875 (+0) | 9039 (+0) | 0.088 (+0.000) | 0.912 (+0.000) | 1.416 (+0.000) | 17.212 (+0.000) |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 16609 (+0) | 1833 (+0) | 14776 (+0) | 0.110 (+0.000) | 0.890 (+0.000) | 1.133 (+0.000) | 21.626 (+0.000) |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 18924 (+0) | 1920 (+0) | 17004 (+0) | 0.101 (+0.000) | 0.899 (+0.000) | 1.232 (+0.000) | 19.712 (+0.000) |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 8937 (+0) | 85 (+0) | 8852 (+0) | 0.010 (+0.000) | 0.990 (+0.000) | 13.143 (+0.000) | 7.758 (+0.000) |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 10454 (+0) | 90 (+0) | 10364 (+0) | 0.009 (+0.000) | 0.991 (+0.000) | 14.519 (+0.000) | 7.778 (+0.000) |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 29485 (+0) | 2915 (+0) | 26570 (+0) | 0.099 (+0.000) | 0.901 (+0.000) | 1.264 (+0.000) | 19.196 (+0.000) |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 4363 (+0) | 377 (+0) | 3986 (+0) | 0.086 (+0.000) | 0.914 (+0.000) | 1.447 (+0.000) | 17.043 (+0.000) |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1328 (+0) | 4939 (+0) | 166 (+0) | 4773 (+0) | 0.034 (+0.000) | 0.966 (+0.000) | 3.719 (+0.000) | 9.646 (+0.000) |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1696 (+0) | 7198 (+0) | 212 (+0) | 6986 (+0) | 0.029 (+0.000) | 0.971 (+0.000) | 4.244 (+0.000) | 9.372 (+0.000) |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11088 (+0) | 16047 (+0) | 1386 (+0) | 14661 (+0) | 0.086 (+0.000) | 0.914 (+0.000) | 1.447 (+0.000) | 15.671 (+0.000) |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 9939 (+0) | 86 (+0) | 9853 (+0) | 0.009 (+0.000) | 0.991 (+0.000) | 14.446 (+0.000) | 7.765 (+0.000) |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 29466 (+0) | 2772 (+0) | 26694 (+0) | 0.094 (+0.000) | 0.906 (+0.000) | 1.329 (+0.000) | 19.184 (+0.000) |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 34630 (+0) | 3408 (+0) | 31222 (+0) | 0.098 (+0.000) | 0.902 (+0.000) | 1.270 (+0.000) | 19.325 (+0.000) |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 15298 (+0) | 107 (+0) | 15191 (+0) | 0.007 (+0.000) | 0.993 (+0.000) | 17.871 (+0.000) | 7.470 (+0.000) |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 7045 (+0) | 744 (+0) | 6301 (+0) | 0.106 (+0.000) | 0.894 (+0.000) | 1.184 (+0.000) | 22.016 (+0.000) |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 14670 (+0) | 1655 (+0) | 13015 (+0) | 0.113 (+0.000) | 0.887 (+0.000) | 1.108 (+0.000) | 22.922 (+0.000) |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1616 (+0) | 8628 (+0) | 202 (+0) | 8426 (+0) | 0.023 (+0.000) | 0.977 (+0.000) | 5.339 (+0.000) | 8.988 (+0.000) |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (+0) | 26144 (+0) | 2729 (+0) | 23415 (+0) | 0.104 (+0.000) | 0.896 (+0.000) | 1.198 (+0.000) | 20.425 (+0.000) |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 21976 (+0) | 28818 (+0) | 2747 (+0) | 26071 (+0) | 0.095 (+0.000) | 0.905 (+0.000) | 1.311 (+0.000) | 18.011 (+0.000) |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1552 (+0) | 15014 (+0) | 194 (+0) | 14820 (+0) | 0.013 (+0.000) | 0.987 (+0.000) | 9.674 (+0.000) | 7.820 (+0.000) |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20568 (+0) | 32064 (+0) | 2571 (+0) | 29493 (+0) | 0.080 (+0.000) | 0.920 (+0.000) | 1.559 (+0.000) | 14.314 (+0.000) |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 19030 (+0) | 143 (+0) | 18887 (+0) | 0.008 (+0.000) | 0.992 (+0.000) | 16.635 (+0.000) | 7.434 (+0.000) |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 3839 (+0) | 83 (+0) | 3756 (+0) | 0.022 (+0.000) | 0.978 (+0.000) | 5.782 (+0.000) | 9.997 (+0.000) |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (+0) | 17892 (+0) | 1982 (+0) | 15910 (+0) | 0.111 (+0.000) | 0.889 (+0.000) | 1.128 (+0.000) | 23.297 (+0.000) |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15112 (+0) | 20369 (+0) | 1889 (+0) | 18480 (+0) | 0.093 (+0.000) | 0.907 (+0.000) | 1.348 (+0.000) | 17.681 (+0.000) |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15728 (+0) | 23472 (+0) | 1966 (+0) | 21506 (+0) | 0.084 (+0.000) | 0.916 (+0.000) | 1.492 (+0.000) | 15.281 (+0.000) |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30328 (+0) | 37043 (+0) | 3791 (+0) | 33252 (+0) | 0.102 (+0.000) | 0.898 (+0.000) | 1.221 (+0.000) | 19.293 (+0.000) |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 17028 (+0) | 110 (+0) | 16918 (+0) | 0.006 (+0.000) | 0.994 (+0.000) | 19.350 (+0.000) | 7.391 (+0.000) |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13248 (+0) | 31535 (+0) | 1656 (+0) | 29879 (+0) | 0.053 (+0.000) | 0.947 (+0.000) | 2.380 (+0.000) | 11.732 (+0.000) |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 22584 (+0) | 155 (+0) | 22429 (+0) | 0.007 (+0.000) | 0.993 (+0.000) | 18.213 (+0.000) | 7.352 (+0.000) |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (+0) | 8718 (+0) | 869 (+0) | 7849 (+0) | 0.100 (+0.000) | 0.900 (+0.000) | 1.254 (+0.000) | 19.460 (+0.000) |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9808 (+0) | 14397 (+0) | 1226 (+0) | 13171 (+0) | 0.085 (+0.000) | 0.915 (+0.000) | 1.468 (+0.000) | 16.068 (+0.000) |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11976 (+0) | 19557 (+0) | 1497 (+0) | 18060 (+0) | 0.077 (+0.000) | 0.923 (+0.000) | 1.633 (+0.000) | 14.551 (+0.000) |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18864 (+0) | 27503 (+0) | 2358 (+0) | 25145 (+0) | 0.086 (+0.000) | 0.914 (+0.000) | 1.458 (+0.000) | 15.348 (+0.000) |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37184 (+0) | 44927 (+0) | 4648 (+0) | 40279 (+0) | 0.103 (+0.000) | 0.897 (+0.000) | 1.208 (+0.000) | 20.057 (+0.000) |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22544 (+0) | 36627 (+0) | 2818 (+0) | 33809 (+0) | 0.077 (+0.000) | 0.923 (+0.000) | 1.625 (+0.000) | 13.626 (+0.000) |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+0) | 67707 (+0) | 7220 (+0) | 60487 (+0) | 0.107 (+0.000) | 0.893 (+0.000) | 1.172 (+0.000) | 21.590 (+0.000) |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28200 (+0) | 47083 (+0) | 3525 (+0) | 43558 (+0) | 0.075 (+0.000) | 0.925 (+0.000) | 1.670 (+0.000) | 13.137 (+0.000) |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (+0) | 8455 (+0) | 668 (+0) | 7787 (+0) | 0.079 (+0.000) | 0.921 (+0.000) | 1.582 (+0.000) | 16.514 (+0.000) |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (+0) | 19356 (+0) | 1931 (+0) | 17425 (+0) | 0.100 (+0.000) | 0.900 (+0.000) | 1.253 (+0.000) | 18.902 (+0.000) |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13496 (+0) | 21755 (+0) | 1687 (+0) | 20068 (+0) | 0.078 (+0.000) | 0.922 (+0.000) | 1.612 (+0.000) | 14.163 (+0.000) |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32040 (+0) | 39624 (+0) | 4005 (+0) | 35619 (+0) | 0.101 (+0.000) | 0.899 (+0.000) | 1.237 (+0.000) | 19.348 (+0.000) |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2096 (+0) | 20121 (+0) | 262 (+0) | 19859 (+0) | 0.013 (+0.000) | 0.987 (+0.000) | 9.600 (+0.000) | 7.860 (+0.000) |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50160 (+0) | 60550 (+0) | 6270 (+0) | 54280 (+0) | 0.104 (+0.000) | 0.896 (+0.000) | 1.207 (+0.000) | 19.710 (+0.000) |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2512 (+0) | 27685 (+0) | 314 (+0) | 27371 (+0) | 0.011 (+0.000) | 0.989 (+0.000) | 11.021 (+0.000) | 7.725 (+0.000) |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76552 (+0) | 89274 (+0) | 9569 (+0) | 79705 (+0) | 0.107 (+0.000) | 0.893 (+0.000) | 1.166 (+0.000) | 21.795 (+0.000) |

### Screenshot Multi-CTU And Partial Crops

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 88520 (+0) | 125600 (+0) | 11065 (+0) | 114535 (+0) | 0.088 (+0.000) | 0.912 (+0.000) | 1.419 (+0.000) | 15.332 (+0.000) |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 43928 (+0) | 92198 (+0) | 5491 (+0) | 86707 (+0) | 0.060 (+0.000) | 0.940 (+0.000) | 2.099 (+0.000) | 11.255 (+0.000) |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 10168 (+0) | 122930 (+0) | 1271 (+0) | 121659 (+0) | 0.010 (+0.000) | 0.990 (+0.000) | 12.090 (+0.000) | 7.503 (+0.000) |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45768 (+0) | 124755 (+0) | 5721 (+0) | 119034 (+0) | 0.046 (+0.000) | 0.954 (+0.000) | 2.726 (+0.000) | 10.153 (+0.000) |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 101472 (+0) | 165455 (+0) | 12684 (+0) | 152771 (+0) | 0.077 (+0.000) | 0.923 (+0.000) | 1.631 (+0.000) | 13.465 (+0.000) |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 60568 (+0) | 80308 (+0) | 7571 (+0) | 72737 (+0) | 0.094 (+0.000) | 0.906 (+0.000) | 1.326 (+0.000) | 17.428 (+0.000) |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 34027 (+0) | 208 (+0) | 33819 (+0) | 0.006 (+0.000) | 0.994 (+0.000) | 20.449 (+0.000) | 7.384 (+0.000) |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3000 (+0) | 40356 (+0) | 375 (+0) | 39981 (+0) | 0.009 (+0.000) | 0.991 (+0.000) | 13.452 (+0.000) | 7.785 (+0.000) |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 135600 (+0) | 182921 (+0) | 16950 (+0) | 165971 (+0) | 0.093 (+0.000) | 0.907 (+0.000) | 1.349 (+0.000) | 16.813 (+0.000) |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79792 (+0) | 129652 (+0) | 9974 (+0) | 119678 (+0) | 0.077 (+0.000) | 0.923 (+0.000) | 1.625 (+0.000) | 14.068 (+0.000) |

## 2026-06-19 4:2:0 Lossy Residual Baseline

Measured after extending the AV2 `yuv420p8` residual RTL to all RaceHorses
single-superblock crop geometries and selected larger multi-superblock smoke
vectors. This is the first output-utilization baseline for the AV2 4:2:0 path,
so delta columns are intentionally omitted.

Baseline and current sources:

- Baseline Git SHA: none; this is the first AV2 `yuv420p8` utilization
  baseline.
- Current validated RTL Git SHA:
  `3b644b32e731840bb1da774312c5a0c70298f040`

Validation result:

- `racehorses-sweep-420`: OK (64/64).
- Larger 4:2:0 smoke vectors: OK (7/7).
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses-sweep-420 | 64 | 182464 | 559546 | 22808 | 536738 | 0.041 | 0.959 | 3.067 | 6.746 |
| larger RaceHorses 4:2:0 smoke | 7 | 139608 | 455922 | 17451 | 438471 | 0.038 | 0.962 | 3.266 | 6.615 |

### RaceHorses 4:2:0 Sweep

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 | 591 | 38 | 553 | 0.064 | 0.936 | 1.944 | 9.234 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 | 1013 | 57 | 956 | 0.056 | 0.944 | 2.221 | 7.914 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 | 1473 | 80 | 1393 | 0.054 | 0.946 | 2.302 | 7.672 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 | 1903 | 103 | 1800 | 0.054 | 0.946 | 2.309 | 7.434 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 | 2344 | 122 | 2222 | 0.052 | 0.948 | 2.402 | 7.325 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 | 2733 | 129 | 2604 | 0.047 | 0.953 | 2.648 | 7.117 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 | 3187 | 155 | 3032 | 0.049 | 0.951 | 2.570 | 7.114 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 | 3609 | 174 | 3435 | 0.048 | 0.952 | 2.593 | 7.049 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 | 990 | 42 | 948 | 0.042 | 0.958 | 2.946 | 7.734 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 | 1861 | 93 | 1768 | 0.050 | 0.950 | 2.501 | 7.270 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 | 2691 | 114 | 2577 | 0.042 | 0.958 | 2.951 | 7.008 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 | 3527 | 152 | 3375 | 0.043 | 0.957 | 2.900 | 6.889 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 | 4403 | 193 | 4210 | 0.044 | 0.956 | 2.852 | 6.880 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 | 5214 | 222 | 4992 | 0.043 | 0.957 | 2.936 | 6.789 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 | 6098 | 261 | 5837 | 0.043 | 0.957 | 2.920 | 6.806 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 | 6929 | 292 | 6637 | 0.042 | 0.958 | 2.966 | 6.767 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 | 1457 | 66 | 1391 | 0.045 | 0.955 | 2.759 | 7.589 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 | 2708 | 122 | 2586 | 0.045 | 0.955 | 2.775 | 7.052 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 | 3973 | 163 | 3810 | 0.041 | 0.959 | 3.047 | 6.898 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 | 5168 | 204 | 4964 | 0.039 | 0.961 | 3.167 | 6.729 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 | 6534 | 275 | 6259 | 0.042 | 0.958 | 2.970 | 6.806 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 | 7758 | 325 | 7433 | 0.042 | 0.958 | 2.984 | 6.734 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 | 9083 | 379 | 8704 | 0.042 | 0.958 | 2.996 | 6.758 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 | 10417 | 448 | 9969 | 0.043 | 0.957 | 2.907 | 6.782 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 | 1849 | 75 | 1774 | 0.041 | 0.959 | 3.082 | 7.223 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 | 3543 | 149 | 3394 | 0.042 | 0.958 | 2.972 | 6.920 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 | 5194 | 200 | 4994 | 0.039 | 0.961 | 3.246 | 6.763 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 | 6889 | 279 | 6610 | 0.040 | 0.960 | 3.086 | 6.728 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 | 8711 | 369 | 8342 | 0.042 | 0.958 | 2.951 | 6.805 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 | 10291 | 418 | 9873 | 0.041 | 0.959 | 3.077 | 6.700 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 | 12024 | 489 | 11535 | 0.041 | 0.959 | 3.074 | 6.710 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 | 13722 | 568 | 13154 | 0.041 | 0.959 | 3.020 | 6.700 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 | 2320 | 95 | 2225 | 0.041 | 0.959 | 3.053 | 7.250 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 | 4420 | 191 | 4229 | 0.043 | 0.957 | 2.893 | 6.906 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 | 6488 | 248 | 6240 | 0.038 | 0.962 | 3.270 | 6.758 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 | 8607 | 344 | 8263 | 0.040 | 0.960 | 3.128 | 6.724 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 | 10756 | 433 | 10323 | 0.040 | 0.960 | 3.105 | 6.723 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 | 12963 | 552 | 12411 | 0.043 | 0.957 | 2.935 | 6.752 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 | 15039 | 612 | 14427 | 0.041 | 0.959 | 3.072 | 6.714 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 | 17133 | 695 | 16438 | 0.041 | 0.959 | 3.081 | 6.693 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 | 2787 | 121 | 2666 | 0.043 | 0.957 | 2.879 | 7.258 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 | 5302 | 228 | 5074 | 0.043 | 0.957 | 2.907 | 6.904 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 | 7701 | 285 | 7416 | 0.037 | 0.963 | 3.378 | 6.685 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 | 10237 | 394 | 9843 | 0.038 | 0.962 | 3.248 | 6.665 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 | 12874 | 513 | 12361 | 0.040 | 0.960 | 3.137 | 6.705 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 | 15369 | 627 | 14742 | 0.041 | 0.959 | 3.064 | 6.671 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 | 17989 | 722 | 17267 | 0.040 | 0.960 | 3.114 | 6.692 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 | 20439 | 814 | 19625 | 0.040 | 0.960 | 3.139 | 6.653 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 | 3216 | 134 | 3082 | 0.042 | 0.958 | 3.000 | 7.179 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 | 6134 | 259 | 5875 | 0.042 | 0.958 | 2.960 | 6.846 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 | 9018 | 335 | 8683 | 0.037 | 0.963 | 3.365 | 6.710 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 | 11943 | 461 | 11482 | 0.039 | 0.961 | 3.238 | 6.665 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 | 14943 | 587 | 14356 | 0.039 | 0.961 | 3.182 | 6.671 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 | 17987 | 743 | 17244 | 0.041 | 0.959 | 3.026 | 6.692 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 | 20975 | 838 | 20137 | 0.040 | 0.960 | 3.129 | 6.688 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 | 23836 | 950 | 22886 | 0.040 | 0.960 | 3.136 | 6.651 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 | 3640 | 148 | 3492 | 0.041 | 0.959 | 3.074 | 7.109 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 | 6950 | 280 | 6670 | 0.040 | 0.960 | 3.103 | 6.787 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 | 10323 | 394 | 9929 | 0.038 | 0.962 | 3.275 | 6.721 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 | 13580 | 514 | 13066 | 0.038 | 0.962 | 3.303 | 6.631 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 | 17067 | 665 | 16402 | 0.039 | 0.961 | 3.208 | 6.667 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 | 20423 | 812 | 19611 | 0.040 | 0.960 | 3.144 | 6.648 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 | 23957 | 968 | 22989 | 0.040 | 0.960 | 3.094 | 6.684 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 | 27243 | 1090 | 26153 | 0.040 | 0.960 | 3.124 | 6.651 |

### Larger RaceHorses 4:2:0 Smoke

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| RaceHorses_136x80_1f_yuv420p8.yuv | PASS | 20608 | 71494 | 2576 | 68918 | 0.036 | 0.964 | 3.469 | 6.571 |
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 | 54207 | 2123 | 52084 | 0.039 | 0.961 | 3.192 | 6.617 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 | 54258 | 2145 | 52113 | 0.040 | 0.960 | 3.162 | 6.623 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 | 107342 | 3977 | 103365 | 0.037 | 0.963 | 3.374 | 6.552 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 | 72402 | 2819 | 69583 | 0.039 | 0.961 | 3.210 | 6.655 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 | 61379 | 2388 | 58991 | 0.039 | 0.961 | 3.213 | 6.660 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 | 34840 | 1423 | 33417 | 0.041 | 0.959 | 3.060 | 6.721 |
