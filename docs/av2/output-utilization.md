# AV2 RTL Output Utilization Baselines

This file records AV2 RTL simulation throughput counters per validation vector.
It is separate from quality/bitrate reporting because these numbers describe
testbench-observed output timing, not compression efficiency.

Metric definitions:

- `total_cycles`: RTL cycles from encoder start until the final output byte is
  accepted on `m_axis`.
- `output_active_cycles`: cycles where `m_axis_valid && m_axis_ready` accepted
  one output byte. The AV2 encoder testbench holds `m_axis_ready` high.
- `output_wait_cycles`: `total_cycles - output_active_cycles`.
- `output_utilization`: `output_active_cycles / total_cycles`; this is the
  requested ratio of cycles outputting data to total cycles.
- `bubble_rate`: `1 - output_utilization`, the fraction of measured cycles
  spent not accepting output bytes.
- `cycles/bit`: `total_cycles / rtl_bitstream_bits`.
- `cycles/input pixel`: `total_cycles / (width * height * frames)`.
- The metrics JSON also records `state_cycles`, `leaf_phase_cycles`,
  `pipeline_cycles`, `entropy_op_cycles`, `pending_push_cycles`, and
  `input_sample_cycles` for profiling; these are auxiliary counters and are not
  part of the pass/fail contract.

## 2026-06-17 Residual Sign Scan Skip

Measured after making the residual symbolizer jump directly between nonzero
coefficients during sign and high-range emission. The AV2 bitstream and
reconstruction are unchanged; the optimization removes cycles spent decrementing
through zero coefficients after the base pass.

Baseline and current sources:

- Baseline Git SHA: `da5f62cf9bcb355a482a443501faa0b3e5c3a8fd`
- Current validated source Git SHA: `33be2008240bf3acecef4a9344ca9e9b01313dc5`
- Baseline mode: EOB-bounded residual scans, known-zero luma residual fast path,
  and pipeline profiler counters.
- Current mode: residual sign scan jumps directly to the next lower nonzero
  coefficient.
- Delta columns compare against the baseline checkpoint above.

Validation commands:

```sh
make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=av2 \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
- All listed vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.
- Bitstream lengths were unchanged, so bitrate deltas remain `+0.0000`.

### Full Screenshot Sweep

Aggregate RTL bits: `770848` (+0).
Aggregate total cycles: `928410` (-6559).
Aggregate output utilization: `0.103786` (+0.000728); bubble rate: `0.896214` (-0.000728).
Aggregate cycles/bit: `1.204401` (-0.008509); aggregate cycles/input pixel: `11.193215` (-0.079077).
Per-vector cycles/input pixel range: `4.973090` to `19.567708` (baseline `4.978299` to `19.666667`).
Top aggregate state-cycle counts: `leaf`=409577 (-6566), `input_read`=250192 (+0), `output_valid`=96356 (+0), `carry_write`=95025 (+0), `chroma_fetch`=59013 (+7), `seq_write`=5632 (+0), `partition`=4008 (+0), `palette_query`=3834 (+0), `load_block`=3168 (+0), `seq_load`=1216 (+0).
Aggregate leaf-phase cycles: `u_coeff`=149863, `v_coeff`=129757, `y_coeff`=68385, `palette_map`=32976, `palette_header`=19542, `intra`=7668, `intrabc`=1386.
Top aggregate pipeline counters: `chroma_bdpcm_enable`=280173, `chroma_bdpcm_active`=269949, `chroma_bdpcm_op_valid`=269949, `leaf_entropy_op_u_coeff`=145296, `leaf_entropy_op_v_coeff`=124602, `leaf_prefetch_active`=118548, `leaf_prefetch_done_wait`=79022, `luma_residual_enable`=71418, `leaf_entropy_op_y_coeff`=67131, `luma_residual_active`=66306, `luma_residual_op_valid`=66306, `fetch_wait_luma`=55972, `leaf_entropy_op_palette_map`=32976, `leaf_entropy_op_palette_header`=19542, `leaf_entropy_op_intra`=7668, `leaf_entropy_gap_v_coeff`=5112, `leaf_entropy_gap_u_coeff`=4559, `luma_residual_known_zero`=3332, `luma_residual_zero_fast_start`=3332, `fetch_wait_u`=3041.

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 558 (-12) | 43 (+0) | 515 (-12) | 0.077061 (+0.001622) | 0.922939 (-0.001622) | 1.622093 (-0.034884) | 8.718750 (-0.187500) |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 2014 (-12) | 248 (+0) | 1766 (-12) | 0.123138 (+0.000729) | 0.876862 (-0.000729) | 1.015121 (-0.006048) | 15.734375 (-0.093750) |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 392 (+0) | 1074 (-12) | 49 (+0) | 1025 (-12) | 0.045624 (+0.000504) | 0.954376 (-0.000504) | 2.739796 (-0.030612) | 5.593750 (-0.062500) |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 712 (+0) | 1636 (-12) | 89 (+0) | 1547 (-12) | 0.054401 (+0.000396) | 0.945599 (-0.000396) | 2.297753 (-0.016854) | 6.390625 (-0.046875) |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 456 (+0) | 1697 (-12) | 57 (+0) | 1640 (-12) | 0.033589 (+0.000236) | 0.966411 (-0.000236) | 3.721491 (-0.026316) | 5.303125 (-0.037500) |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 496 (+0) | 2005 (-12) | 62 (+0) | 1943 (-12) | 0.030923 (+0.000184) | 0.969077 (-0.000184) | 4.042339 (-0.024193) | 5.221354 (-0.031250) |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (+0) | 6844 (-93) | 858 (+0) | 5986 (-93) | 0.125365 (+0.001680) | 0.874635 (-0.001680) | 0.997086 (-0.013549) | 15.276786 (-0.207589) |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 7546 (-47) | 852 (+0) | 6694 (-47) | 0.112908 (+0.000699) | 0.887092 (-0.000699) | 1.107101 (-0.006895) | 14.738281 (-0.091797) |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (+0) | 1873 (-12) | 228 (+0) | 1645 (-12) | 0.121730 (+0.000775) | 0.878270 (-0.000775) | 1.026864 (-0.006579) | 14.632812 (-0.093749) |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 4423 (-36) | 577 (+0) | 3846 (-36) | 0.130454 (+0.001053) | 0.869546 (-0.001053) | 0.958189 (-0.007799) | 17.277344 (-0.140625) |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (+0) | 2011 (-12) | 63 (+0) | 1948 (-12) | 0.031328 (+0.000186) | 0.968672 (-0.000186) | 3.990079 (-0.023810) | 5.236979 (-0.031250) |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 576 (+0) | 2639 (-12) | 72 (+0) | 2567 (-12) | 0.027283 (+0.000123) | 0.972717 (-0.000123) | 4.581597 (-0.020834) | 5.154297 (-0.023437) |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 10169 (-65) | 1218 (+0) | 8951 (-65) | 0.119776 (+0.000761) | 0.880224 (-0.000761) | 1.043617 (-0.006670) | 15.889062 (-0.101562) |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 720 (+0) | 3903 (-12) | 90 (+0) | 3813 (-12) | 0.023059 (+0.000070) | 0.976941 (-0.000070) | 5.420833 (-0.016667) | 5.082031 (-0.015625) |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 11945 (-233) | 1331 (+0) | 10614 (-233) | 0.111427 (+0.002132) | 0.888573 (-0.002132) | 1.121807 (-0.021882) | 13.331473 (-0.260045) |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 872 (+0) | 5165 (-12) | 109 (+0) | 5056 (-12) | 0.021104 (+0.000049) | 0.978896 (-0.000049) | 5.923165 (-0.013762) | 5.043945 (-0.011719) |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 3402 (-59) | 442 (+0) | 2960 (-59) | 0.129924 (+0.002215) | 0.870076 (-0.002215) | 0.962104 (-0.016686) | 17.718750 (-0.307292) |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 3646 (-19) | 341 (+0) | 3305 (-19) | 0.093527 (+0.000485) | 0.906473 (-0.000485) | 1.336510 (-0.006965) | 9.494792 (-0.049479) |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 7682 (-27) | 875 (+0) | 6807 (-27) | 0.113903 (+0.000399) | 0.886097 (-0.000399) | 1.097429 (-0.003857) | 13.336806 (-0.046875) |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 13759 (-123) | 1833 (+0) | 11926 (-123) | 0.133222 (+0.001181) | 0.866778 (-0.001181) | 0.938284 (-0.008388) | 17.915365 (-0.160156) |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 15272 (-14) | 1920 (+0) | 13352 (-14) | 0.125720 (+0.000115) | 0.874280 (-0.000115) | 0.994271 (-0.000911) | 15.908333 (-0.014584) |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 944 (+0) | 5787 (-12) | 118 (+0) | 5669 (-12) | 0.020391 (+0.000043) | 0.979609 (-0.000043) | 6.130297 (-0.012711) | 5.023438 (-0.010416) |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1048 (+0) | 6743 (-12) | 131 (+0) | 6612 (-12) | 0.019428 (+0.000035) | 0.980572 (-0.000035) | 6.434160 (-0.011451) | 5.017113 (-0.008929) |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 23800 (-240) | 2915 (+0) | 20885 (-240) | 0.122479 (+0.001223) | 0.877521 (-0.001223) | 1.020583 (-0.010292) | 15.494792 (-0.156250) |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 3269 (-30) | 377 (+0) | 2892 (-30) | 0.115326 (+0.001049) | 0.884674 (-0.001049) | 1.083886 (-0.009947) | 12.769531 (-0.117188) |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (+0) | 3300 (-18) | 176 (+0) | 3124 (-18) | 0.053333 (+0.000289) | 0.946667 (-0.000289) | 2.343750 (-0.012784) | 6.445312 (-0.035157) |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1808 (+0) | 4721 (-18) | 226 (+0) | 4495 (-18) | 0.047871 (+0.000182) | 0.952129 (-0.000182) | 2.611173 (-0.009955) | 6.147135 (-0.023438) |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11152 (+0) | 12532 (-73) | 1394 (+0) | 11138 (-73) | 0.111235 (+0.000644) | 0.888765 (-0.000644) | 1.123745 (-0.006546) | 12.238281 (-0.071289) |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1008 (+0) | 6424 (-12) | 126 (+0) | 6298 (-12) | 0.019614 (+0.000037) | 0.980386 (-0.000037) | 6.373016 (-0.011905) | 5.018750 (-0.009375) |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 23787 (-459) | 2772 (+0) | 21015 (-459) | 0.116534 (+0.002206) | 0.883466 (-0.002206) | 1.072646 (-0.020698) | 15.486328 (-0.298828) |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 27865 (-287) | 3408 (+0) | 24457 (-287) | 0.122304 (+0.001247) | 0.877696 (-0.001247) | 1.022044 (-0.010526) | 15.549665 (-0.160156) |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1456 (+0) | 10202 (-12) | 182 (+0) | 10020 (-12) | 0.017840 (+0.000021) | 0.982160 (-0.000021) | 7.006868 (-0.008242) | 4.981445 (-0.005860) |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 5676 (-30) | 744 (+0) | 4932 (-30) | 0.131078 (+0.000689) | 0.868922 (-0.000689) | 0.953629 (-0.005040) | 17.737500 (-0.093750) |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 12290 (-108) | 1655 (+0) | 10635 (-108) | 0.134662 (+0.001173) | 0.865338 (-0.001173) | 0.928248 (-0.008157) | 19.203125 (-0.168750) |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1792 (+0) | 5643 (-18) | 224 (+0) | 5419 (-18) | 0.039695 (+0.000126) | 0.960305 (-0.000126) | 3.148996 (-0.010044) | 5.878125 (-0.018750) |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (+0) | 21400 (-165) | 2729 (+0) | 18671 (-165) | 0.127523 (+0.000975) | 0.872477 (-0.000975) | 0.980213 (-0.007557) | 16.718750 (-0.128906) |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22480 (+0) | 23225 (-174) | 2810 (+0) | 20415 (-174) | 0.120990 (+0.000899) | 0.879010 (-0.000899) | 1.033141 (-0.007740) | 14.515625 (-0.108750) |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (+0) | 10232 (-20) | 269 (+0) | 9963 (-20) | 0.026290 (+0.000051) | 0.973710 (-0.000051) | 4.754647 (-0.009294) | 5.329167 (-0.010416) |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20944 (+0) | 25142 (-206) | 2618 (+0) | 22524 (-206) | 0.104129 (+0.000847) | 0.895871 (-0.000847) | 1.200439 (-0.009836) | 11.224107 (-0.091964) |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2016 (+0) | 12895 (-22) | 252 (+0) | 12643 (-22) | 0.019542 (+0.000033) | 0.980458 (-0.000033) | 6.396329 (-0.010913) | 5.037109 (-0.008594) |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 2209 (-24) | 83 (+0) | 2126 (-24) | 0.037574 (+0.000404) | 0.962426 (-0.000404) | 3.326807 (-0.036145) | 5.752604 (-0.062500) |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (+0) | 15028 (-76) | 1982 (+0) | 13046 (-76) | 0.131887 (+0.000663) | 0.868113 (-0.000663) | 0.947780 (-0.004793) | 19.567708 (-0.098959) |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15152 (+0) | 16032 (-118) | 1894 (+0) | 14138 (-118) | 0.118139 (+0.000863) | 0.881861 (-0.000863) | 1.058078 (-0.007788) | 13.916667 (-0.102430) |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15832 (+0) | 18175 (-144) | 1979 (+0) | 16196 (-144) | 0.108886 (+0.000856) | 0.891114 (-0.000856) | 1.147991 (-0.009096) | 11.832682 (-0.093750) |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30400 (+0) | 29981 (-251) | 3800 (+0) | 26181 (-251) | 0.126747 (+0.001052) | 0.873253 (-0.001052) | 0.986217 (-0.008257) | 15.615104 (-0.130729) |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1600 (+0) | 11458 (-12) | 200 (+0) | 11258 (-12) | 0.017455 (+0.000018) | 0.982545 (-0.000018) | 7.161250 (-0.007500) | 4.973090 (-0.005209) |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13560 (+0) | 22559 (-552) | 1695 (+0) | 20864 (-552) | 0.075136 (+0.001794) | 0.924864 (-0.001794) | 1.663643 (-0.040708) | 8.392485 (-0.205357) |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2304 (+0) | 15432 (-22) | 288 (+0) | 15144 (-22) | 0.018663 (+0.000027) | 0.981337 (-0.000027) | 6.697917 (-0.009548) | 5.023438 (-0.007161) |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (+0) | 6803 (-43) | 869 (+0) | 5934 (-43) | 0.127738 (+0.000803) | 0.872262 (-0.000803) | 0.978567 (-0.006186) | 15.185268 (-0.095982) |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9864 (+0) | 11315 (-81) | 1233 (+0) | 10082 (-81) | 0.108970 (+0.000774) | 0.891030 (-0.000774) | 1.147101 (-0.008211) | 12.628348 (-0.090402) |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 12088 (+0) | 14840 (-94) | 1511 (+0) | 13329 (-94) | 0.101819 (+0.000640) | 0.898181 (-0.000640) | 1.227664 (-0.007776) | 11.041667 (-0.069940) |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 19168 (+0) | 21777 (-158) | 2396 (+0) | 19381 (-158) | 0.110024 (+0.000792) | 0.889976 (-0.000792) | 1.136112 (-0.008243) | 12.152344 (-0.088169) |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37216 (+0) | 36508 (-421) | 4652 (+0) | 31856 (-421) | 0.127424 (+0.001453) | 0.872576 (-0.001453) | 0.980976 (-0.011312) | 16.298214 (-0.187947) |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27016 (+0) | 31407 (-191) | 3377 (+0) | 28030 (-191) | 0.107524 (+0.000650) | 0.892476 (-0.000650) | 1.162533 (-0.007070) | 11.684152 (-0.071056) |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+0) | 55846 (-318) | 7220 (+0) | 48626 (-318) | 0.129284 (+0.000732) | 0.870716 (-0.000732) | 0.966863 (-0.005505) | 17.808036 (-0.101403) |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 29264 (+0) | 37191 (-148) | 3658 (+0) | 33533 (-148) | 0.098357 (+0.000390) | 0.901643 (-0.000390) | 1.270879 (-0.005057) | 10.376953 (-0.041295) |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (+0) | 6281 (-35) | 668 (+0) | 5613 (-35) | 0.106352 (+0.000589) | 0.893648 (-0.000589) | 1.175337 (-0.006549) | 12.267578 (-0.068360) |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (+0) | 15564 (-160) | 1931 (+0) | 13633 (-160) | 0.124068 (+0.001262) | 0.875932 (-0.001262) | 1.007509 (-0.010357) | 15.199219 (-0.156250) |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13744 (+0) | 16783 (-96) | 1718 (+0) | 15065 (-96) | 0.102365 (+0.000582) | 0.897635 (-0.000582) | 1.221115 (-0.006985) | 10.926432 (-0.062500) |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32136 (+0) | 32430 (-193) | 4017 (+0) | 28413 (-193) | 0.123867 (+0.000733) | 0.876133 (-0.000733) | 1.009149 (-0.006005) | 15.834961 (-0.094238) |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2856 (+0) | 13583 (-10) | 357 (+0) | 13226 (-10) | 0.026283 (+0.000019) | 0.973717 (-0.000019) | 4.755952 (-0.003502) | 5.305859 (-0.003907) |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50264 (+0) | 49572 (-294) | 6283 (+0) | 43289 (-294) | 0.126745 (+0.000747) | 0.873255 (-0.000747) | 0.986233 (-0.005849) | 16.136719 (-0.095703) |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3840 (+0) | 18953 (-39) | 480 (+0) | 18473 (-39) | 0.025326 (+0.000052) | 0.974674 (-0.000052) | 4.935677 (-0.010156) | 5.288225 (-0.010882) |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76656 (+0) | 74487 (-315) | 9582 (+0) | 64905 (-315) | 0.128640 (+0.000542) | 0.871360 (-0.000542) | 0.971705 (-0.004109) | 18.185303 (-0.076904) |

### Screenshot Multi-CTU And Partial Crops

Aggregate RTL bits: `592008` (+0).
Aggregate total cycles: `839032` (-5933).
Aggregate output utilization: `0.088198` (+0.000619); bubble rate: `0.911802` (-0.000619).
Aggregate cycles/bit: `1.417265` (-0.010022); aggregate cycles/input pixel: `9.135801` (-0.064601).
Per-vector cycles/input pixel range: `4.970486` to `13.987196` (baseline `4.975694` to `14.109592`).
Top aggregate state-cycle counts: `leaf`=328966 (-5933), `input_read`=276987 (+0), `output_valid`=74001 (+0), `carry_write`=73682 (+0), `chroma_fetch`=72434 (+0), `palette_query`=4299 (+0), `partition`=4284 (+0), `load_block`=2970 (+0), `seq_write`=960 (+0), `seq_load`=190 (+0).
Aggregate leaf-phase cycles: `u_coeff`=123187, `v_coeff`=91783, `y_coeff`=53366, `palette_map`=31280, `palette_header`=19307, `intra`=8598, `intrabc`=1445.
Top aggregate pipeline counters: `input_backpressure`=360521, `chroma_bdpcm_enable`=215792, `chroma_bdpcm_active`=204328, `chroma_bdpcm_op_valid`=204328, `leaf_entropy_op_u_coeff`=118268, `leaf_prefetch_active`=105110, `leaf_entropy_op_v_coeff`=86029, `fetch_wait_luma`=67917, `leaf_prefetch_done_wait`=65840, `luma_residual_enable`=57028, `leaf_entropy_op_y_coeff`=52390, `luma_residual_active`=51296, `luma_residual_op_valid`=51296, `leaf_entropy_op_palette_map`=31280, `leaf_entropy_op_palette_header`=19307, `leaf_entropy_op_intra`=8598, `leaf_entropy_gap_v_coeff`=5732, `leaf_entropy_gap_u_coeff`=4910, `fetch_wait_u`=4517, `luma_residual_known_zero`=4384.

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 89904 (+0) | 100657 (-962) | 11238 (+0) | 89419 (-962) | 0.111646 (+0.001056) | 0.888354 (-0.001056) | 1.119605 (-0.010701) | 12.287231 (-0.117432) |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 46184 (+0) | 70491 (-363) | 5773 (+0) | 64718 (-363) | 0.081897 (+0.000420) | 0.918103 (-0.000420) | 1.526308 (-0.007860) | 8.604858 (-0.044312) |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 16384 (+0) | 85933 (-174) | 2048 (+0) | 83885 (-174) | 0.023833 (+0.000049) | 0.976167 (-0.000049) | 5.244934 (-0.010620) | 5.244934 (-0.010620) |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 48696 (+0) | 91599 (-791) | 6087 (+0) | 85512 (-791) | 0.066453 (+0.000569) | 0.933547 (-0.000569) | 1.881037 (-0.016244) | 7.454346 (-0.064371) |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 104056 (+0) | 129603 (-1049) | 13007 (+0) | 116596 (-1049) | 0.100360 (+0.000805) | 0.899640 (-0.000805) | 1.245512 (-0.010081) | 10.547119 (-0.085368) |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 61016 (+0) | 64453 (-564) | 7627 (+0) | 56826 (-564) | 0.118334 (+0.001026) | 0.881666 (-0.001026) | 1.056329 (-0.009244) | 13.987196 (-0.122396) |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3096 (+0) | 22904 (-24) | 387 (+0) | 22517 (-24) | 0.016897 (+0.000018) | 0.983103 (-0.000018) | 7.397933 (-0.007752) | 4.970486 (-0.005208) |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4488 (+0) | 26488 (-48) | 561 (+0) | 25927 (-48) | 0.021179 (+0.000038) | 0.978821 (-0.000038) | 5.901961 (-0.010695) | 5.109568 (-0.009259) |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136880 (+0) | 146458 (-1056) | 17110 (+0) | 129348 (-1056) | 0.116825 (+0.000836) | 0.883175 (-0.000836) | 1.069974 (-0.007714) | 13.461213 (-0.097059) |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 81304 (+0) | 100446 (-902) | 10163 (+0) | 90283 (-902) | 0.101179 (+0.000901) | 0.898821 (-0.000901) | 1.235437 (-0.011095) | 10.899089 (-0.097873) |
