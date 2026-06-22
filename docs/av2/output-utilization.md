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
  `pipeline_cycles`, `entropy_op_cycles`, `pending_push_cycles`,
  `input_sample_cycles`, and `block_utilization` for AV2-specific profiling.
  The constants and JSON writer for these internal counters live in
  `tb/av2_metrics.py`; they are not part of the shared top-level pass/fail
  contract.

## 2026-06-22 Cached AXI Frame Reader Fast Path

Measured after allowing the shared AXI4 frame reader to keep `sample_valid`
asserted for the next visible sample when it is on the same row and already in
the cached AXI beat. The bitstream and reconstruction are unchanged; this is a
transport/input scheduling optimization plus added AV2 block-utilization
instrumentation.

Baseline and current sources:

- Baseline report Git SHA: `8653c51b3e7f7d2bb61c1d2b18c7a9e0d91a5f59`
- Baseline validated RTL Git SHA: `874fb312adf735387f53551bcbed5254fdc98051`
- Current validated RTL Git SHA: `5b5095a82297d6f39d2b20c147ccf051e267fb0d`
- Baseline mode: AV2 local IBC leaf-order mapping expressed structurally, with
  the shared AXI frame reader returning to `ST_SKIP` between cached samples.
- Current mode: same codec behavior, with cached same-row samples drained on
  consecutive cycles when the downstream block is ready.
- Delta columns compare against the immediate previous validated 4:4:4
  checkpoint. Bitstream-size deltas are zero because the codec syntax did not
  change.

Validation result:

- `screenshot-sweep-444`: OK (64/64).
- `screenshot-multictu-444`: OK (10/10).
- Direct `screenshot_640_sweep_16x16_1f_yuv444p8.yuv`: OK.
- Direct `screenshot_640_sweep_64x64_1f_yuv444p8.yuv`: OK.
- Shared-reader VVC smoke `racehorses_crop_8x8_1f_yuv420p8.yuv`: OK.
- All listed AV2 vectors matched SW/RTL bitstream checksums and
  SW/RTL/reference-decoder reconstruction checksums.

Target status:

- Requested target: bubble rate below `0.800`.
- Current `screenshot-sweep-444` weighted aggregate bubble rate: `0.903`.
- Current `screenshot-multictu-444` weighted aggregate bubble rate: `0.917`.
- The target is not met yet. The new internal counters show that luma/chroma
  residual symbolizers are not the current source of bubbles; the remaining
  issue is serialized frame input, entropy work, carry propagation, and final
  byte output.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Avg cycles/pixel (delta) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot-sweep-444 | 64 | 755272 (+0) | 976556 (-217728) | 94409 (+0) | 882147 (-217728) | 0.097 (+0.018) | 0.903 (-0.018) | 1.293 (-0.288) | 12.170 (-2.625) |
| screenshot-multictu-444 | 10 | 570480 (+0) | 857122 (-241080) | 71310 (+0) | 785812 (-241080) | 0.083 (+0.018) | 0.917 (-0.018) | 1.502 (-0.423) | 9.493 (-2.625) |

Critical pipeline block utilization:

| Block | Sweep cycles/share | Sweep util | Multi-CTU cycles/share | Multi-CTU util | Notes |
|---|---:|---:|---:|---:|---|
| AXI frame reader | 331776 / 34.0% | 0.750 | 365098 / 42.6% | 0.755 | Accepted input samples per input-read cycle; improved but still a major serialized phase. |
| Leaf entropy scheduler | 402127 / 41.2% | 0.965 | 307934 / 35.9% | 0.967 | Entropy ops per leaf cycle; already high, so most leaf cycles are productive syntax work. |
| Chroma fetch/predictor staging | 37557 / 3.8% | 0.304 | 30791 / 3.6% | 0.306 | Prefetch useful ratio excludes cycles where prefetched data is ready but waits for entropy. |
| Carry propagation | 93081 / 9.5% | 1.014 | 70991 / 8.3% | 1.004 | Payload bytes per carry cycle; near one byte/cycle but remains a separate serialized pass. |
| Final byte output | 94409 / 9.7% | 0.097 | 71310 / 8.3% | 0.083 | Final top-level output utilization; still below the 0.200 utilization target. |
| Luma residual symbolizer | 64773 active | 1.000 | 49272 active | 1.000 | Emits an op on every active cycle in these 4:4:4 runs. |
| Chroma BDPCM symbolizer | 265745 active | 1.000 | 198934 active | 1.000 | Emits an op on every active cycle; not the current bubble source. |

### Full Screenshot Sweep

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 666 (-168) | 43 (+0) | 623 (-168) | 0.065 (+0.013) | 0.935 (-0.013) | 1.936 (-0.488) | 10.406 (-2.625) |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 2154 (-336) | 248 (+0) | 1906 (-336) | 0.115 (+0.015) | 0.885 (-0.015) | 1.086 (-0.169) | 16.828 (-2.625) |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 1420 (-504) | 52 (+0) | 1368 (-504) | 0.037 (+0.010) | 0.963 (-0.010) | 3.413 (-1.212) | 7.396 (-2.625) |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 2012 (-672) | 92 (+0) | 1920 (-672) | 0.046 (+0.012) | 0.954 (-0.012) | 2.734 (-0.913) | 7.859 (-2.625) |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 2177 (-840) | 60 (+0) | 2117 (-840) | 0.028 (+0.008) | 0.972 (-0.008) | 4.535 (-1.750) | 6.803 (-2.625) |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 2519 (-1008) | 65 (+0) | 2454 (-1008) | 0.026 (+0.008) | 0.974 (-0.008) | 4.844 (-1.939) | 6.560 (-2.625) |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (+0) | 7375 (-1176) | 858 (+0) | 6517 (-1176) | 0.116 (+0.016) | 0.884 (-0.016) | 1.074 (-0.172) | 16.462 (-2.625) |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 8106 (-1344) | 852 (+0) | 7254 (-1344) | 0.105 (+0.015) | 0.895 (-0.015) | 1.189 (-0.197) | 15.832 (-2.625) |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (+0) | 2085 (-336) | 228 (+0) | 1857 (-336) | 0.109 (+0.015) | 0.891 (-0.015) | 1.143 (-0.184) | 16.289 (-2.625) |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 4708 (-672) | 577 (+0) | 4131 (-672) | 0.123 (+0.016) | 0.877 (-0.016) | 1.020 (-0.146) | 18.391 (-2.625) |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 472 (+0) | 2365 (-1008) | 59 (+0) | 2306 (-1008) | 0.025 (+0.008) | 0.975 (-0.008) | 5.011 (-2.135) | 6.159 (-2.625) |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 512 (+0) | 2929 (-1344) | 64 (+0) | 2865 (-1344) | 0.022 (+0.007) | 0.978 (-0.007) | 5.721 (-2.625) | 5.721 (-2.625) |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 10937 (-1680) | 1218 (+0) | 9719 (-1680) | 0.111 (+0.014) | 0.889 (-0.014) | 1.122 (-0.173) | 17.089 (-2.625) |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 608 (+0) | 4210 (-2016) | 76 (+0) | 4134 (-2016) | 0.018 (+0.006) | 0.982 (-0.006) | 6.924 (-3.316) | 5.482 (-2.625) |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 12981 (-2352) | 1331 (+0) | 11650 (-2352) | 0.103 (+0.016) | 0.897 (-0.016) | 1.219 (-0.221) | 14.488 (-2.625) |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 696 (+0) | 5488 (-2688) | 87 (+0) | 5401 (-2688) | 0.016 (+0.005) | 0.984 (-0.005) | 7.885 (-3.862) | 5.359 (-2.625) |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 3725 (-504) | 442 (+0) | 3283 (-504) | 0.119 (+0.014) | 0.881 (-0.014) | 1.053 (-0.143) | 19.401 (-2.625) |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 4054 (-1008) | 341 (+0) | 3713 (-1008) | 0.084 (+0.017) | 0.916 (-0.017) | 1.486 (-0.370) | 10.557 (-2.625) |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 8402 (-1512) | 875 (+0) | 7527 (-1512) | 0.104 (+0.016) | 0.896 (-0.016) | 1.200 (-0.216) | 14.587 (-2.625) |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 14593 (-2016) | 1833 (+0) | 12760 (-2016) | 0.126 (+0.016) | 0.874 (-0.016) | 0.995 (-0.138) | 19.001 (-2.625) |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 16404 (-2520) | 1920 (+0) | 14484 (-2520) | 0.117 (+0.016) | 0.883 (-0.016) | 1.068 (-0.164) | 17.087 (-2.625) |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 5913 (-3024) | 85 (+0) | 5828 (-3024) | 0.014 (+0.004) | 0.986 (-0.004) | 8.696 (-4.447) | 5.133 (-2.625) |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 6926 (-3528) | 90 (+0) | 6836 (-3528) | 0.013 (+0.004) | 0.987 (-0.004) | 9.619 (-4.900) | 5.153 (-2.625) |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 25453 (-4032) | 2915 (+0) | 22538 (-4032) | 0.115 (+0.016) | 0.885 (-0.016) | 1.091 (-0.173) | 16.571 (-2.625) |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 3691 (-672) | 377 (+0) | 3314 (-672) | 0.102 (+0.016) | 0.898 (-0.016) | 1.224 (-0.223) | 14.418 (-2.625) |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1328 (+0) | 3595 (-1344) | 166 (+0) | 3429 (-1344) | 0.046 (+0.012) | 0.954 (-0.012) | 2.707 (-1.012) | 7.021 (-2.625) |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1696 (+0) | 5182 (-2016) | 212 (+0) | 4970 (-2016) | 0.041 (+0.012) | 0.959 (-0.012) | 3.055 (-1.189) | 6.747 (-2.625) |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11088 (+0) | 13359 (-2688) | 1386 (+0) | 11973 (-2688) | 0.104 (+0.018) | 0.896 (-0.018) | 1.205 (-0.242) | 13.046 (-2.625) |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 6579 (-3360) | 86 (+0) | 6493 (-3360) | 0.013 (+0.004) | 0.987 (-0.004) | 9.562 (-4.883) | 5.140 (-2.625) |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 25434 (-4032) | 2772 (+0) | 22662 (-4032) | 0.109 (+0.015) | 0.891 (-0.015) | 1.147 (-0.182) | 16.559 (-2.625) |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 29926 (-4704) | 3408 (+0) | 26518 (-4704) | 0.114 (+0.016) | 0.886 (-0.016) | 1.098 (-0.172) | 16.700 (-2.625) |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 9922 (-5376) | 107 (+0) | 9815 (-5376) | 0.011 (+0.004) | 0.989 (-0.004) | 11.591 (-6.280) | 4.845 (-2.625) |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 6205 (-840) | 744 (+0) | 5461 (-840) | 0.120 (+0.014) | 0.880 (-0.014) | 1.043 (-0.141) | 19.391 (-2.625) |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 12990 (-1680) | 1655 (+0) | 11335 (-1680) | 0.127 (+0.014) | 0.873 (-0.014) | 0.981 (-0.127) | 20.297 (-2.625) |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1616 (+0) | 6108 (-2520) | 202 (+0) | 5906 (-2520) | 0.033 (+0.010) | 0.967 (-0.010) | 3.780 (-1.559) | 6.362 (-2.625) |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (+0) | 22784 (-3360) | 2729 (+0) | 20055 (-3360) | 0.120 (+0.016) | 0.880 (-0.016) | 1.044 (-0.154) | 17.800 (-2.625) |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 21976 (+0) | 24618 (-4200) | 2747 (+0) | 21871 (-4200) | 0.112 (+0.017) | 0.888 (-0.017) | 1.120 (-0.191) | 15.386 (-2.625) |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1552 (+0) | 9974 (-5040) | 194 (+0) | 9780 (-5040) | 0.019 (+0.006) | 0.981 (-0.006) | 6.427 (-3.247) | 5.195 (-2.625) |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20568 (+0) | 26184 (-5880) | 2571 (+0) | 23613 (-5880) | 0.098 (+0.018) | 0.902 (-0.018) | 1.273 (-0.286) | 11.689 (-2.625) |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 12310 (-6720) | 143 (+0) | 12167 (-6720) | 0.012 (+0.004) | 0.988 (-0.004) | 10.760 (-5.875) | 4.809 (-2.625) |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 2831 (-1008) | 83 (+0) | 2748 (-1008) | 0.029 (+0.007) | 0.971 (-0.007) | 4.264 (-1.518) | 7.372 (-2.625) |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (+0) | 15876 (-2016) | 1982 (+0) | 13894 (-2016) | 0.125 (+0.014) | 0.875 (-0.014) | 1.001 (-0.127) | 20.672 (-2.625) |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15112 (+0) | 17345 (-3024) | 1889 (+0) | 15456 (-3024) | 0.109 (+0.016) | 0.891 (-0.016) | 1.148 (-0.200) | 15.056 (-2.625) |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15728 (+0) | 19440 (-4032) | 1966 (+0) | 17474 (-4032) | 0.101 (+0.017) | 0.899 (-0.017) | 1.236 (-0.256) | 12.656 (-2.625) |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30328 (+0) | 32003 (-5040) | 3791 (+0) | 28212 (-5040) | 0.118 (+0.016) | 0.882 (-0.016) | 1.055 (-0.166) | 16.668 (-2.625) |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 10980 (-6048) | 110 (+0) | 10870 (-6048) | 0.010 (+0.004) | 0.990 (-0.004) | 12.477 (-6.873) | 4.766 (-2.625) |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13248 (+0) | 24479 (-7056) | 1656 (+0) | 22823 (-7056) | 0.068 (+0.015) | 0.932 (-0.015) | 1.848 (-0.532) | 9.107 (-2.625) |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 14520 (-8064) | 155 (+0) | 14365 (-8064) | 0.011 (+0.004) | 0.989 (-0.004) | 11.710 (-6.503) | 4.727 (-2.625) |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (+0) | 7542 (-1176) | 869 (+0) | 6673 (-1176) | 0.115 (+0.015) | 0.885 (-0.015) | 1.085 (-0.169) | 16.835 (-2.625) |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9808 (+0) | 12045 (-2352) | 1226 (+0) | 10819 (-2352) | 0.102 (+0.017) | 0.898 (-0.017) | 1.228 (-0.240) | 13.443 (-2.625) |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11976 (+0) | 16029 (-3528) | 1497 (+0) | 14532 (-3528) | 0.093 (+0.016) | 0.907 (-0.016) | 1.338 (-0.295) | 11.926 (-2.625) |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18864 (+0) | 22799 (-4704) | 2358 (+0) | 20441 (-4704) | 0.103 (+0.017) | 0.897 (-0.017) | 1.209 (-0.249) | 12.723 (-2.625) |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37184 (+0) | 39047 (-5880) | 4648 (+0) | 34399 (-5880) | 0.119 (+0.016) | 0.881 (-0.016) | 1.050 (-0.158) | 17.432 (-2.625) |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22544 (+0) | 29571 (-7056) | 2818 (+0) | 26753 (-7056) | 0.095 (+0.018) | 0.905 (-0.018) | 1.312 (-0.313) | 11.001 (-2.625) |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+0) | 59475 (-8232) | 7220 (+0) | 52255 (-8232) | 0.121 (+0.014) | 0.879 (-0.014) | 1.030 (-0.142) | 18.965 (-2.625) |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28200 (+0) | 37675 (-9408) | 3525 (+0) | 34150 (-9408) | 0.094 (+0.019) | 0.906 (-0.019) | 1.336 (-0.334) | 10.512 (-2.625) |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (+0) | 7111 (-1344) | 668 (+0) | 6443 (-1344) | 0.094 (+0.015) | 0.906 (-0.015) | 1.331 (-0.251) | 13.889 (-2.625) |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (+0) | 16668 (-2688) | 1931 (+0) | 14737 (-2688) | 0.116 (+0.016) | 0.884 (-0.016) | 1.079 (-0.174) | 16.277 (-2.625) |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13496 (+0) | 17723 (-4032) | 1687 (+0) | 16036 (-4032) | 0.095 (+0.017) | 0.905 (-0.017) | 1.313 (-0.299) | 11.538 (-2.625) |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32040 (+0) | 34248 (-5376) | 4005 (+0) | 30243 (-5376) | 0.117 (+0.016) | 0.883 (-0.016) | 1.069 (-0.168) | 16.723 (-2.625) |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2096 (+0) | 13401 (-6720) | 262 (+0) | 13139 (-6720) | 0.020 (+0.007) | 0.980 (-0.007) | 6.394 (-3.206) | 5.235 (-2.625) |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50160 (+0) | 52486 (-8064) | 6270 (+0) | 46216 (-8064) | 0.119 (+0.015) | 0.881 (-0.015) | 1.046 (-0.161) | 17.085 (-2.625) |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2512 (+0) | 18277 (-9408) | 314 (+0) | 17963 (-9408) | 0.017 (+0.006) | 0.983 (-0.006) | 7.276 (-3.745) | 5.100 (-2.625) |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76552 (+0) | 78522 (-10752) | 9569 (+0) | 68953 (-10752) | 0.122 (+0.015) | 0.878 (-0.015) | 1.026 (-0.140) | 19.170 (-2.625) |

### Screenshot Multi-CTU And Partial Crops

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel (delta) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 88520 (+0) | 104096 (-21504) | 11065 (+0) | 93031 (-21504) | 0.106 (+0.018) | 0.894 (-0.018) | 1.176 (-0.243) | 12.707 (-2.625) |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 43928 (+0) | 70694 (-21504) | 5491 (+0) | 65203 (-21504) | 0.078 (+0.018) | 0.922 (-0.018) | 1.609 (-0.490) | 8.630 (-2.625) |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 10168 (+0) | 79922 (-43008) | 1271 (+0) | 78651 (-43008) | 0.016 (+0.006) | 0.984 (-0.006) | 7.860 (-4.230) | 4.878 (-2.625) |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45768 (+0) | 92499 (-32256) | 5721 (+0) | 86778 (-32256) | 0.062 (+0.016) | 0.938 (-0.016) | 2.021 (-0.705) | 7.528 (-2.625) |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 101472 (+0) | 133199 (-32256) | 12684 (+0) | 120515 (-32256) | 0.095 (+0.018) | 0.905 (-0.018) | 1.313 (-0.318) | 10.840 (-2.625) |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 60568 (+0) | 68212 (-12096) | 7571 (+0) | 60641 (-12096) | 0.111 (+0.017) | 0.889 (-0.017) | 1.126 (-0.200) | 14.803 (-2.625) |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 21931 (-12096) | 208 (+0) | 21723 (-12096) | 0.009 (+0.003) | 0.991 (-0.003) | 13.180 (-7.269) | 4.759 (-2.625) |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3000 (+0) | 26748 (-13608) | 375 (+0) | 26373 (-13608) | 0.014 (+0.005) | 0.986 (-0.005) | 8.916 (-4.536) | 5.160 (-2.625) |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 135600 (+0) | 154361 (-28560) | 16950 (+0) | 137411 (-28560) | 0.110 (+0.017) | 0.890 (-0.017) | 1.138 (-0.211) | 14.188 (-2.625) |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79792 (+0) | 105460 (-24192) | 9974 (+0) | 95486 (-24192) | 0.095 (+0.018) | 0.905 (-0.018) | 1.322 (-0.303) | 11.443 (-2.625) |

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
