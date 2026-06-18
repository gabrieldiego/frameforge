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

## 2026-06-17 Residual Scan Gap Profiling

Measured after bounding residual coefficient scans to the coded EOB range,
adding a known-zero luma TXB fast path, and expanding the AV2 cocotb profiler
with leaf-phase and pipeline counters. The AV2 bitstream and reconstruction are
unchanged; the optimization removes cycles spent walking coefficient positions
that cannot emit symbols.

Baseline and current sources:

- Baseline Git SHA: `c125ea91a2e0643313a77870172c49d0331d5339`
- Current validated source Git SHA: `da5f62cf9bcb355a482a443501faa0b3e5c3a8fd`
- Baseline mode: chroma TXB fetch cache and predictor cache-hit bypass.
- Current mode: EOB-bounded residual scans, known-zero luma residual fast path,
  and pipeline profiler counters.
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
Aggregate total cycles: `934969` (-6541).
Aggregate output utilization: `0.103058` (+0.000716); bubble rate: `0.896942` (-0.000716).
Aggregate cycles/bit: `1.212910` (-0.008485); aggregate cycles/input pixel: `11.272292` (-0.078860).
Per-vector cycles/input pixel range: `4.978299` to `19.666667` (baseline `4.988715` to `19.710938`).
Top aggregate state-cycle counts: `leaf`=416143 (-7504), `input_read`=250192 (+0), `output_valid`=96356 (+0), `carry_write`=95025 (+0), `chroma_fetch`=59006 (+963), `seq_write`=5632 (+0), `partition`=4008 (+0), `palette_query`=3834 (+0), `load_block`=3168, `seq_load`=1216.
Aggregate leaf-phase cycles: `u_coeff`=151939, `v_coeff`=133021, `y_coeff`=69611, `palette_map`=32976, `palette_header`=19542, `intra`=7668, `intrabc`=1386.
Top aggregate pipeline counters: `chroma_bdpcm_enable`=285513, `chroma_bdpcm_active`=275289, `chroma_bdpcm_op_valid`=269945, `leaf_entropy_op_u_coeff`=145296, `leaf_entropy_op_v_coeff`=124602, `leaf_prefetch_active`=119654, `leaf_prefetch_done_wait`=80122, `luma_residual_enable`=72640, `luma_residual_active`=67528, `leaf_entropy_op_y_coeff`=67131, `luma_residual_op_valid`=66306, `fetch_wait_luma`=55965, `leaf_entropy_op_palette_map`=32976, `leaf_entropy_op_palette_header`=19542, `leaf_entropy_gap_v_coeff`=8376, `leaf_entropy_op_intra`=7668, `leaf_entropy_gap_u_coeff`=6635, `chroma_bdpcm_op_gap`=5344, `luma_residual_known_zero`=3332, `luma_residual_zero_fast_start`=3332.

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 570 (-24) | 43 (+0) | 527 (-24) | 0.075439 (+0.003048) | 0.924561 (-0.003048) | 1.656977 (-0.069767) | 8.906250 (-0.375000) |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 2026 (-24) | 248 (+0) | 1778 (-24) | 0.122409 (+0.001433) | 0.877591 (-0.001433) | 1.021169 (-0.012097) | 15.828125 (-0.187500) |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 392 (+0) | 1086 (-24) | 49 (+0) | 1037 (-24) | 0.045120 (+0.000976) | 0.954880 (-0.000976) | 2.770408 (-0.061225) | 5.656250 (-0.125000) |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 712 (+0) | 1648 (-24) | 89 (+0) | 1559 (-24) | 0.054005 (+0.000775) | 0.945995 (-0.000775) | 2.314607 (-0.033708) | 6.437500 (-0.093750) |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 456 (+0) | 1709 (-24) | 57 (+0) | 1652 (-24) | 0.033353 (+0.000462) | 0.966647 (-0.000462) | 3.747807 (-0.052632) | 5.340625 (-0.075000) |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 496 (+0) | 2017 (-24) | 62 (+0) | 1955 (-24) | 0.030739 (+0.000362) | 0.969261 (-0.000362) | 4.066532 (-0.048387) | 5.252604 (-0.062500) |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (+0) | 6937 (-42) | 858 (+0) | 6079 (-42) | 0.123685 (+0.000745) | 0.876315 (-0.000745) | 1.010635 (-0.006119) | 15.484375 (-0.093750) |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 7593 (-154) | 852 (+0) | 6741 (-154) | 0.112209 (+0.002231) | 0.887791 (-0.002231) | 1.113996 (-0.022594) | 14.830078 (-0.300781) |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (+0) | 1885 (-24) | 228 (+0) | 1657 (-24) | 0.120955 (+0.001521) | 0.879045 (-0.001521) | 1.033443 (-0.013158) | 14.726562 (-0.187499) |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 4459 (-64) | 577 (+0) | 3882 (-64) | 0.129401 (+0.001831) | 0.870599 (-0.001831) | 0.965988 (-0.013865) | 17.417969 (-0.250000) |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (+0) | 2023 (-24) | 63 (+0) | 1960 (-24) | 0.031142 (+0.000365) | 0.968858 (-0.000365) | 4.013889 (-0.047619) | 5.268229 (-0.062500) |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 576 (+0) | 2651 (-24) | 72 (+0) | 2579 (-24) | 0.027160 (+0.000244) | 0.972840 (-0.000244) | 4.602431 (-0.041666) | 5.177734 (-0.046875) |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 10234 (-38) | 1218 (+0) | 9016 (-38) | 0.119015 (+0.000440) | 0.880985 (-0.000440) | 1.050287 (-0.003900) | 15.990625 (-0.059375) |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 720 (+0) | 3915 (-24) | 90 (+0) | 3825 (-24) | 0.022989 (+0.000141) | 0.977011 (-0.000141) | 5.437500 (-0.033333) | 5.097656 (-0.031250) |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 12178 (-168) | 1331 (+0) | 10847 (-168) | 0.109295 (+0.001487) | 0.890705 (-0.001487) | 1.143689 (-0.015778) | 13.591518 (-0.187500) |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 872 (+0) | 5177 (-24) | 109 (+0) | 5068 (-24) | 0.021055 (+0.000097) | 0.978945 (-0.000097) | 5.936927 (-0.027523) | 5.055664 (-0.023438) |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 3461 (-64) | 442 (+0) | 3019 (-64) | 0.127709 (+0.002319) | 0.872291 (-0.002319) | 0.978790 (-0.018099) | 18.026042 (-0.333333) |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 3665 (-24) | 341 (+0) | 3324 (-24) | 0.093042 (+0.000605) | 0.906958 (-0.000605) | 1.343475 (-0.008798) | 9.544271 (-0.062500) |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 7709 (-28) | 875 (+0) | 6834 (-28) | 0.113504 (+0.000411) | 0.886496 (-0.000411) | 1.101286 (-0.004000) | 13.383681 (-0.048611) |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 13882 (-72) | 1833 (+0) | 12049 (-72) | 0.132041 (+0.000681) | 0.867959 (-0.000681) | 0.946672 (-0.004910) | 18.075521 (-0.093750) |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 15286 (-24) | 1920 (+0) | 13366 (-24) | 0.125605 (+0.000197) | 0.874395 (-0.000197) | 0.995182 (-0.001563) | 15.922917 (-0.025000) |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 944 (+0) | 5799 (-24) | 118 (+0) | 5681 (-24) | 0.020348 (+0.000084) | 0.979652 (-0.000084) | 6.143008 (-0.025424) | 5.033854 (-0.020834) |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1048 (+0) | 6755 (-24) | 131 (+0) | 6624 (-24) | 0.019393 (+0.000069) | 0.980607 (-0.000069) | 6.445611 (-0.022900) | 5.026042 (-0.017857) |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 24040 (-78) | 2915 (+0) | 21125 (-78) | 0.121256 (+0.000392) | 0.878744 (-0.000392) | 1.030875 (-0.003345) | 15.651042 (-0.050781) |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 3299 (-28) | 377 (+0) | 2922 (-28) | 0.114277 (+0.000962) | 0.885723 (-0.000962) | 1.093833 (-0.009284) | 12.886719 (-0.109375) |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (+0) | 3318 (-24) | 176 (+0) | 3142 (-24) | 0.053044 (+0.000381) | 0.946956 (-0.000381) | 2.356534 (-0.017046) | 6.480469 (-0.046875) |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1808 (+0) | 4739 (-24) | 226 (+0) | 4513 (-24) | 0.047689 (+0.000240) | 0.952311 (-0.000240) | 2.621128 (-0.013275) | 6.170573 (-0.031250) |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11152 (+0) | 12605 (-18) | 1394 (+0) | 11211 (-18) | 0.110591 (+0.000158) | 0.889409 (-0.000158) | 1.130291 (-0.001614) | 12.309570 (-0.017578) |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1008 (+0) | 6436 (-24) | 126 (+0) | 6310 (-24) | 0.019577 (+0.000072) | 0.980423 (-0.000072) | 6.384921 (-0.023809) | 5.028125 (-0.018750) |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 24246 (-573) | 2772 (+0) | 21474 (-573) | 0.114328 (+0.002639) | 0.885672 (-0.002639) | 1.093344 (-0.025839) | 15.785156 (-0.373047) |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 28152 (-194) | 3408 (+0) | 24744 (-194) | 0.121057 (+0.000828) | 0.878943 (-0.000828) | 1.032570 (-0.007116) | 15.709821 (-0.108259) |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1456 (+0) | 10214 (-24) | 182 (+0) | 10032 (-24) | 0.017819 (+0.000042) | 0.982181 (-0.000042) | 7.015110 (-0.016483) | 4.987305 (-0.011718) |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 5706 (-94) | 744 (+0) | 4962 (-94) | 0.130389 (+0.002113) | 0.869611 (-0.002113) | 0.958669 (-0.015793) | 17.831250 (-0.293750) |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 12398 (-136) | 1655 (+0) | 10743 (-136) | 0.133489 (+0.001448) | 0.866511 (-0.001448) | 0.936405 (-0.010272) | 19.371875 (-0.212500) |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1792 (+0) | 5661 (-24) | 224 (+0) | 5437 (-24) | 0.039569 (+0.000167) | 0.960431 (-0.000167) | 3.159040 (-0.013393) | 5.896875 (-0.025000) |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (+0) | 21565 (-86) | 2729 (+0) | 18836 (-86) | 0.126548 (+0.000503) | 0.873452 (-0.000503) | 0.987770 (-0.003939) | 16.847656 (-0.067188) |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22480 (+0) | 23399 (-256) | 2810 (+0) | 20589 (-256) | 0.120091 (+0.001300) | 0.879909 (-0.001300) | 1.040881 (-0.011388) | 14.624375 (-0.160000) |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (+0) | 10252 (-30) | 269 (+0) | 9983 (-30) | 0.026239 (+0.000077) | 0.973761 (-0.000077) | 4.763941 (-0.013940) | 5.339583 (-0.015625) |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20944 (+0) | 25348 (-94) | 2618 (+0) | 22730 (-94) | 0.103282 (+0.000381) | 0.896718 (-0.000381) | 1.210275 (-0.004488) | 11.316071 (-0.041965) |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2016 (+0) | 12917 (-36) | 252 (+0) | 12665 (-36) | 0.019509 (+0.000054) | 0.980491 (-0.000054) | 6.407242 (-0.017857) | 5.045703 (-0.014063) |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 2233 (-48) | 83 (+0) | 2150 (-48) | 0.037170 (+0.000782) | 0.962830 (-0.000782) | 3.362952 (-0.072289) | 5.815104 (-0.125000) |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (+0) | 15104 (-34) | 1982 (+0) | 13122 (-34) | 0.131224 (+0.000295) | 0.868776 (-0.000295) | 0.952573 (-0.002144) | 19.666667 (-0.044271) |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15152 (+0) | 16150 (-76) | 1894 (+0) | 14256 (-76) | 0.117276 (+0.000550) | 0.882724 (-0.000550) | 1.065866 (-0.005016) | 14.019097 (-0.065972) |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15832 (+0) | 18319 (-138) | 1979 (+0) | 16340 (-138) | 0.108030 (+0.000808) | 0.891970 (-0.000808) | 1.157087 (-0.008716) | 11.926432 (-0.089844) |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30400 (+0) | 30232 (-232) | 3800 (+0) | 26432 (-232) | 0.125695 (+0.000958) | 0.874305 (-0.000958) | 0.994474 (-0.007631) | 15.745833 (-0.120834) |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1600 (+0) | 11470 (-24) | 200 (+0) | 11270 (-24) | 0.017437 (+0.000037) | 0.982563 (-0.000037) | 7.168750 (-0.015000) | 4.978299 (-0.010416) |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13560 (+0) | 23111 (-875) | 1695 (+0) | 21416 (-875) | 0.073342 (+0.002676) | 0.926658 (-0.002676) | 1.704351 (-0.064528) | 8.597842 (-0.325521) |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2304 (+0) | 15454 (-36) | 288 (+0) | 15166 (-36) | 0.018636 (+0.000043) | 0.981364 (-0.000043) | 6.707465 (-0.015625) | 5.030599 (-0.011719) |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (+0) | 6846 (-54) | 869 (+0) | 5977 (-54) | 0.126935 (+0.000993) | 0.873065 (-0.000993) | 0.984753 (-0.007767) | 15.281250 (-0.120536) |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9864 (+0) | 11396 (-84) | 1233 (+0) | 10163 (-84) | 0.108196 (+0.000792) | 0.891804 (-0.000792) | 1.155312 (-0.008516) | 12.718750 (-0.093750) |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 12088 (+0) | 14934 (-24) | 1511 (+0) | 13423 (-24) | 0.101179 (+0.000163) | 0.898821 (-0.000163) | 1.235440 (-0.001986) | 11.111607 (-0.017857) |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 19168 (+0) | 21935 (-98) | 2396 (+0) | 19539 (-98) | 0.109232 (+0.000486) | 0.890768 (-0.000486) | 1.144355 (-0.005113) | 12.240513 (-0.054688) |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37216 (+0) | 36929 (-470) | 4652 (+0) | 32277 (-470) | 0.125971 (+0.001583) | 0.874029 (-0.001583) | 0.992288 (-0.012629) | 16.486161 (-0.209821) |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27016 (+0) | 31598 (-220) | 3377 (+0) | 28221 (-220) | 0.106874 (+0.000739) | 0.893126 (-0.000739) | 1.169603 (-0.008144) | 11.755208 (-0.081846) |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+0) | 56164 (-272) | 7220 (+0) | 48944 (-272) | 0.128552 (+0.000619) | 0.871448 (-0.000619) | 0.972368 (-0.004710) | 17.909439 (-0.086734) |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 29264 (+0) | 37339 (-108) | 3658 (+0) | 33681 (-108) | 0.097967 (+0.000282) | 0.902033 (-0.000282) | 1.275936 (-0.003691) | 10.418248 (-0.030134) |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (+0) | 6316 (-48) | 668 (+0) | 5648 (-48) | 0.105763 (+0.000798) | 0.894237 (-0.000798) | 1.181886 (-0.008982) | 12.335938 (-0.093751) |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (+0) | 15724 (-112) | 1931 (+0) | 13793 (-112) | 0.122806 (+0.000869) | 0.877194 (-0.000869) | 1.017866 (-0.007251) | 15.355469 (-0.109375) |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13744 (+0) | 16879 (-44) | 1718 (+0) | 15161 (-44) | 0.101783 (+0.000264) | 0.898217 (-0.000264) | 1.228100 (-0.003201) | 10.988932 (-0.028646) |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32136 (+0) | 32623 (-184) | 4017 (+0) | 28606 (-184) | 0.123134 (+0.000691) | 0.876866 (-0.000691) | 1.015154 (-0.005726) | 15.929199 (-0.089844) |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2856 (+0) | 13593 (-12) | 357 (+0) | 13236 (-12) | 0.026264 (+0.000024) | 0.973736 (-0.000024) | 4.759454 (-0.004201) | 5.309766 (-0.004687) |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50264 (+0) | 49866 (-314) | 6283 (+0) | 43583 (-314) | 0.125998 (+0.000789) | 0.874002 (-0.000789) | 0.992082 (-0.006247) | 16.232422 (-0.102213) |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3840 (+0) | 18992 (-48) | 480 (+0) | 18512 (-48) | 0.025274 (+0.000064) | 0.974726 (-0.000064) | 4.945833 (-0.012500) | 5.299107 (-0.013393) |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76656 (+0) | 74802 (-253) | 9582 (+0) | 65220 (-253) | 0.128098 (+0.000432) | 0.871902 (-0.000432) | 0.975814 (-0.003300) | 18.262207 (-0.061768) |

### Screenshot Multi-CTU And Partial Crops

Aggregate RTL bits: `592008` (+0).
Aggregate total cycles: `844965` (-5321).
Aggregate output utilization: `0.087579` (+0.000548); bubble rate: `0.912421` (-0.000548).
Aggregate cycles/bit: `1.427286` (-0.008988); aggregate cycles/input pixel: `9.200403` (-0.057938).
Per-vector cycles/input pixel range: `4.975694` to `14.109592` (baseline `4.986111` to `14.196832`).
Top aggregate state-cycle counts: `leaf`=334899 (-6484), `input_read`=276987 (+0), `output_valid`=74001 (+0), `carry_write`=73682 (+0), `chroma_fetch`=72434 (+1163), `palette_query`=4299 (+0), `partition`=4284 (+0), `load_block`=2970 (+0), `seq_write`=960, `seq_load`=190.
Aggregate leaf-phase cycles: `u_coeff`=124643, `v_coeff`=95073, `y_coeff`=54553, `palette_map`=31280, `palette_header`=19307, `intra`=8598, `intrabc`=1445.
Top aggregate pipeline counters: `input_backpressure`=364745, `chroma_bdpcm_enable`=220538, `chroma_bdpcm_active`=209074, `chroma_bdpcm_op_valid`=204324, `leaf_entropy_op_u_coeff`=118268, `leaf_prefetch_active`=106185, `leaf_entropy_op_v_coeff`=86029, `fetch_wait_luma`=67917, `leaf_prefetch_done_wait`=66915, `luma_residual_enable`=58215, `luma_residual_active`=52483, `leaf_entropy_op_y_coeff`=52390, `luma_residual_op_valid`=51296, `leaf_entropy_op_palette_map`=31280, `leaf_entropy_op_palette_header`=19307, `leaf_entropy_gap_v_coeff`=9022, `leaf_entropy_op_intra`=8598, `leaf_entropy_gap_u_coeff`=6366, `chroma_bdpcm_op_gap`=4750, `fetch_wait_u`=4517.

| Vector | Status | RTL bits | Total cycles | Active cycles | Wait cycles | Output util | Bubble rate | Cycles/bit | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 89904 (+0) | 101619 (-1016) | 11238 (+0) | 90381 (-1016) | 0.110590 (+0.001095) | 0.889410 (-0.001095) | 1.130306 (-0.011301) | 12.404663 (-0.124024) |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 46184 (+0) | 70854 (-264) | 5773 (+0) | 65081 (-264) | 0.081477 (+0.000302) | 0.918523 (-0.000302) | 1.534168 (-0.005716) | 8.649170 (-0.032226) |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 16384 (+0) | 86107 (-220) | 2048 (+0) | 84059 (-220) | 0.023784 (+0.000060) | 0.976216 (-0.000060) | 5.255554 (-0.013428) | 5.255554 (-0.013428) |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 48696 (+0) | 92390 (-910) | 6087 (+0) | 86303 (-910) | 0.065884 (+0.000643) | 0.934116 (-0.000643) | 1.897281 (-0.018687) | 7.518717 (-0.074056) |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 104056 (+0) | 130652 (-969) | 13007 (+0) | 117645 (-969) | 0.099555 (+0.000733) | 0.900445 (-0.000733) | 1.255593 (-0.009312) | 10.632487 (-0.078857) |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 61016 (+0) | 65017 (-402) | 7627 (+0) | 57390 (-402) | 0.117308 (+0.000721) | 0.882692 (-0.000721) | 1.065573 (-0.006588) | 14.109592 (-0.087240) |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3096 (+0) | 22928 (-48) | 387 (+0) | 22541 (-48) | 0.016879 (+0.000035) | 0.983121 (-0.000035) | 7.405685 (-0.015504) | 4.975694 (-0.010417) |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4488 (+0) | 26536 (-96) | 561 (+0) | 25975 (-96) | 0.021141 (+0.000076) | 0.978859 (-0.000076) | 5.912656 (-0.021390) | 5.118827 (-0.018519) |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136880 (+0) | 147514 (-816) | 17110 (+0) | 130404 (-816) | 0.115989 (+0.000638) | 0.884011 (-0.000638) | 1.077688 (-0.005962) | 13.558272 (-0.075000) |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 81304 (+0) | 101348 (-580) | 10163 (+0) | 91185 (-580) | 0.100278 (+0.000570) | 0.899722 (-0.000570) | 1.246532 (-0.007133) | 10.996962 (-0.062934) |
