# AV2 RTL Output Utilization Baselines

This report records the latest RTL simulation throughput counters. Older
measurement sections are intentionally left to git history so this file
stays focused on the current optimization baseline and immediate deltas.

Metric definitions:

- `output_utilization`: accepted output bytes divided by total measured cycles.
- `bubble_rate`: `1 - output_utilization`.
- `cycles/bit`: total measured cycles divided by RTL bitstream bits.
- `cycles/input pixel`: total measured cycles divided by `width * height * frames`.
- Internal block utilization is testbench instrumentation. It is used to find
  pipeline starvation/backpressure and is not part of the codec bitstream contract.

## 2026-06-22 Shared AXI/FIFO Utilization Pass

Validated RTL/source Git SHA:

- `3945b1bc67a20e5cfa2ccf8d05910ab8741deef0`

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity where applicable.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity where applicable.

Target status:

- Requested target: bubble rate below `0.800`.
- Current aggregate results still miss that target. The internal counters show
  the AXI write side accepts every offered beat; the remaining bubbles are
  dominated by codec work and serialized byte-output/carry/CABAC phases rather
  than downstream AXI backpressure.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 64 | 755272 (+0) | 971264 (-5292) | 94409 (+0) | 876855 (-5292) | 0.0972 (+0.000527) | 0.903 (-0.000527) | 1.29 (-0.00701) |
| `screenshot-multictu-444` | 10 | 570480 (+0) | 854094 (-3028) | 71310 (+0) | 782784 (-3028) | 0.0835 (+0.000295) | 0.917 (-0.000295) | 1.5 (-0.00531) |

Critical internal block utilization:

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0972 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00611 |
| Frame reader sample issue | 0.754 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.256 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.973 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.466 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.366 |
| AV2 carry payload bytes/cycle | 1.04 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 613 (-53) | 43 (+0) | 570 (-53) | 0.0701 (+0.00515) | 0.93 (-0.00515) | 1.78 (-0.154) | 9.58 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 2149 (-5) | 248 (+0) | 1901 (-5) | 0.115 (+0.000403) | 0.885 (-0.000403) | 1.08 (-0.00283) | 16.8 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 1399 (-21) | 52 (+0) | 1347 (-21) | 0.0372 (+0.000169) | 0.963 (-0.000169) | 3.36 (-0.05) | 7.29 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 1985 (-27) | 92 (+0) | 1893 (-27) | 0.0463 (+0.000348) | 0.954 (-0.000348) | 2.7 (-0.037) | 7.75 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 2140 (-37) | 60 (+0) | 2080 (-37) | 0.028 (+3.74e-05) | 0.972 (-3.74e-05) | 4.46 (-0.0767) | 6.69 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 2474 (-45) | 65 (+0) | 2409 (-45) | 0.0263 (+0.000273) | 0.974 (-0.000273) | 4.76 (-0.0863) | 6.44 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (+0) | 7357 (-18) | 858 (+0) | 6499 (-18) | 0.117 (+0.000624) | 0.883 (-0.000624) | 1.07 (-0.00218) | 16.4 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 8083 (-23) | 852 (+0) | 7231 (-23) | 0.105 (+0.000406) | 0.895 (-0.000406) | 1.19 (-0.00311) | 15.8 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (+0) | 1982 (-103) | 228 (+0) | 1754 (-103) | 0.115 (+0.00604) | 0.885 (-0.00604) | 1.09 (-0.0564) | 15.5 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 4697 (-11) | 577 (+0) | 4120 (-11) | 0.123 (-0.000156) | 0.877 (+0.000156) | 1.02 (-0.00245) | 18.3 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 472 (+0) | 2337 (-28) | 59 (+0) | 2278 (-28) | 0.0252 (+0.000246) | 0.975 (-0.000246) | 4.95 (-0.0597) | 6.09 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 512 (+0) | 2893 (-36) | 64 (+0) | 2829 (-36) | 0.0221 (+0.000122) | 0.978 (-0.000122) | 5.65 (-0.0706) | 5.65 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 10910 (-27) | 1218 (+0) | 9692 (-27) | 0.112 (+0.000641) | 0.888 (-0.000641) | 1.12 (-0.00234) | 17 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 608 (+0) | 4158 (-52) | 76 (+0) | 4082 (-52) | 0.0183 (+0.000278) | 0.982 (-0.000278) | 6.84 (-0.0852) | 5.41 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 12944 (-37) | 1331 (+0) | 11613 (-37) | 0.103 (-0.000172) | 0.897 (+0.000172) | 1.22 (-0.00337) | 14.4 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 696 (+0) | 5420 (-68) | 87 (+0) | 5333 (-68) | 0.0161 (+5.17e-05) | 0.984 (-5.17e-05) | 7.79 (-0.0976) | 5.29 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 3576 (-149) | 442 (+0) | 3134 (-149) | 0.124 (+0.0046) | 0.876 (-0.0046) | 1.01 (-0.0417) | 18.6 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 4019 (-35) | 341 (+0) | 3678 (-35) | 0.0848 (+0.000847) | 0.915 (-0.000847) | 1.47 (-0.0128) | 10.5 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 8365 (-37) | 875 (+0) | 7490 (-37) | 0.105 (+0.000603) | 0.895 (-0.000603) | 1.2 (-0.005) | 14.5 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 14563 (-30) | 1833 (+0) | 12730 (-30) | 0.126 (-0.000133) | 0.874 (+0.000133) | 0.993 (-0.00189) | 19 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 16350 (-54) | 1920 (+0) | 14430 (-54) | 0.117 (+0.000431) | 0.883 (-0.000431) | 1.06 (-0.00355) | 17 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 5854 (-59) | 85 (+0) | 5769 (-59) | 0.0145 (+0.00052) | 0.985 (-0.00052) | 8.61 (-0.0872) | 5.08 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 6859 (-67) | 90 (+0) | 6769 (-67) | 0.0131 (+0.000121) | 0.987 (-0.000121) | 9.53 (-0.0926) | 5.1 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 25391 (-62) | 2915 (+0) | 22476 (-62) | 0.115 (-0.000196) | 0.885 (+0.000196) | 1.09 (-0.00219) | 16.5 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 3482 (-209) | 377 (+0) | 3105 (-209) | 0.108 (+0.00627) | 0.892 (-0.00627) | 1.15 (-0.0695) | 13.6 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1328 (+0) | 3556 (-39) | 166 (+0) | 3390 (-39) | 0.0467 (+0.000682) | 0.953 (-0.000682) | 2.68 (-0.0293) | 6.95 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1696 (+0) | 5136 (-46) | 212 (+0) | 4924 (-46) | 0.0413 (+0.000277) | 0.959 (-0.000277) | 3.03 (-0.0267) | 6.69 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11088 (+0) | 13311 (-48) | 1386 (+0) | 11925 (-48) | 0.104 (+0.000124) | 0.896 (-0.000124) | 1.2 (-0.00451) | 13 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 6520 (-59) | 86 (+0) | 6434 (-59) | 0.0132 (+0.00019) | 0.987 (-0.00019) | 9.48 (-0.0853) | 5.09 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 25393 (-41) | 2772 (+0) | 22621 (-41) | 0.109 (+0.000164) | 0.891 (-0.000164) | 1.15 (-0.00193) | 16.5 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 29852 (-74) | 3408 (+0) | 26444 (-74) | 0.114 (+0.000163) | 0.886 (-0.000163) | 1.09 (-0.00308) | 16.7 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 9839 (-83) | 107 (+0) | 9732 (-83) | 0.0109 (-0.000125) | 0.989 (+0.000125) | 11.5 (-0.0968) | 4.8 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 5954 (-251) | 744 (+0) | 5210 (-251) | 0.125 (+0.00496) | 0.875 (-0.00496) | 1 (-0.0427) | 18.6 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 12971 (-19) | 1655 (+0) | 11316 (-19) | 0.128 (+0.000592) | 0.872 (-0.000592) | 0.98 (-0.00132) | 20.3 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1616 (+0) | 6047 (-61) | 202 (+0) | 5845 (-61) | 0.0334 (+0.000405) | 0.967 (-0.000405) | 3.74 (-0.038) | 6.3 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (+0) | 22733 (-51) | 2729 (+0) | 20004 (-51) | 0.12 (+4.57e-05) | 0.88 (-4.57e-05) | 1.04 (-0.00273) | 17.8 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 21976 (+0) | 24532 (-86) | 2747 (+0) | 21785 (-86) | 0.112 (-2.38e-05) | 0.888 (+2.38e-05) | 1.12 (-0.00369) | 15.3 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1552 (+0) | 9898 (-76) | 194 (+0) | 9704 (-76) | 0.0196 (+0.0006) | 0.98 (-0.0006) | 6.38 (-0.0494) | 5.16 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20568 (+0) | 26117 (-67) | 2571 (+0) | 23546 (-67) | 0.0984 (+0.000442) | 0.902 (-0.000442) | 1.27 (-0.00321) | 11.7 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 12221 (-89) | 143 (+0) | 12078 (-89) | 0.0117 (-0.000299) | 0.988 (+0.000299) | 10.7 (-0.0773) | 4.77 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 2500 (-331) | 83 (+0) | 2417 (-331) | 0.0332 (+0.0042) | 0.967 (-0.0042) | 3.77 (-0.499) | 6.51 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (+0) | 15855 (-21) | 1982 (+0) | 13873 (-21) | 0.125 (+7.88e-06) | 0.875 (-7.88e-06) | 1 (-0.00106) | 20.6 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15112 (+0) | 17294 (-51) | 1889 (+0) | 15405 (-51) | 0.109 (+0.000229) | 0.891 (-0.000229) | 1.14 (-0.00361) | 15 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15728 (+0) | 19354 (-86) | 1966 (+0) | 17388 (-86) | 0.102 (+0.000581) | 0.898 (-0.000581) | 1.23 (-0.00546) | 12.6 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30328 (+0) | 31919 (-84) | 3791 (+0) | 28128 (-84) | 0.119 (+0.000769) | 0.881 (-0.000769) | 1.05 (-0.00254) | 16.6 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 10897 (-83) | 110 (+0) | 10787 (-83) | 0.0101 (+9.45e-05) | 0.99 (-9.45e-05) | 12.4 (-0.094) | 4.73 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13248 (+0) | 24342 (-137) | 1656 (+0) | 22686 (-137) | 0.068 (+3.06e-05) | 0.932 (-3.06e-05) | 1.84 (-0.0106) | 9.06 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 14423 (-97) | 155 (+0) | 14268 (-97) | 0.0107 (-0.000253) | 0.989 (+0.000253) | 11.6 (-0.0785) | 4.69 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (+0) | 7181 (-361) | 869 (+0) | 6312 (-361) | 0.121 (+0.00601) | 0.879 (-0.00601) | 1.03 (-0.0521) | 16 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9808 (+0) | 12002 (-43) | 1226 (+0) | 10776 (-43) | 0.102 (+0.00015) | 0.898 (-0.00015) | 1.22 (-0.00431) | 13.4 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11976 (+0) | 15956 (-73) | 1497 (+0) | 14459 (-73) | 0.0938 (+0.000821) | 0.906 (-0.000821) | 1.33 (-0.00567) | 11.9 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18864 (+0) | 22723 (-76) | 2358 (+0) | 20365 (-76) | 0.104 (+0.000772) | 0.896 (-0.000772) | 1.2 (-0.00443) | 12.7 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37184 (+0) | 38967 (-80) | 4648 (+0) | 34319 (-80) | 0.119 (+0.00028) | 0.881 (-0.00028) | 1.05 (-0.00205) | 17.4 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22544 (+0) | 29475 (-96) | 2818 (+0) | 26657 (-96) | 0.0956 (+0.000606) | 0.904 (-0.000606) | 1.31 (-0.00456) | 11 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+0) | 59364 (-111) | 7220 (+0) | 52144 (-111) | 0.122 (+0.000623) | 0.878 (-0.000623) | 1.03 (-0.00223) | 18.9 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28200 (+0) | 37574 (-101) | 3525 (+0) | 34049 (-101) | 0.0938 (-0.000185) | 0.906 (+0.000185) | 1.33 (-0.00359) | 10.5 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (+0) | 6692 (-419) | 668 (+0) | 6024 (-419) | 0.0998 (+0.00582) | 0.9 (-0.00582) | 1.25 (-0.0788) | 13.1 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (+0) | 16613 (-55) | 1931 (+0) | 14682 (-55) | 0.116 (+0.000234) | 0.884 (-0.000234) | 1.08 (-0.00359) | 16.2 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13496 (+0) | 17661 (-62) | 1687 (+0) | 15974 (-62) | 0.0955 (+0.000521) | 0.904 (-0.000521) | 1.31 (-0.00439) | 11.5 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32040 (+0) | 34177 (-71) | 4005 (+0) | 30172 (-71) | 0.117 (+0.000184) | 0.883 (-0.000184) | 1.07 (-0.0023) | 16.7 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2096 (+0) | 13298 (-103) | 262 (+0) | 13036 (-103) | 0.0197 (-0.000298) | 0.98 (+0.000298) | 6.34 (-0.0495) | 5.19 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50160 (+0) | 52356 (-130) | 6270 (+0) | 46086 (-130) | 0.12 (+0.000757) | 0.88 (-0.000757) | 1.04 (-0.00222) | 17 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2512 (+0) | 18149 (-128) | 314 (+0) | 17835 (-128) | 0.0173 (+0.000301) | 0.983 (-0.000301) | 7.22 (-0.0511) | 5.06 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76552 (+0) | 78412 (-110) | 9569 (+0) | 68843 (-110) | 0.122 (+3.49e-05) | 0.878 (-3.49e-05) | 1.02 (-0.0017) | 19.1 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0835 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00522 |
| Frame reader sample issue | 0.753 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0.323 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.98 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.51 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.36 |
| AV2 carry payload bytes/cycle | 1.01 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 60568 (+0) | 68064 (-148) | 7571 (+0) | 60493 (-148) | 0.111 (+0.000234) | 0.889 (-0.000234) | 1.12 (-0.00224) | 14.8 |
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 88520 (+0) | 103882 (-214) | 11065 (+0) | 92817 (-214) | 0.107 (+0.000515) | 0.893 (-0.000515) | 1.17 (-0.00246) | 12.7 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45768 (+0) | 92056 (-443) | 5721 (+0) | 86335 (-443) | 0.0621 (+0.000147) | 0.938 (-0.000147) | 2.01 (-0.00964) | 7.49 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 21755 (-176) | 208 (+0) | 21547 (-176) | 0.00956 (+0.000561) | 0.99 (-0.000561) | 13.1 (-0.106) | 4.72 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3000 (+0) | 26510 (-238) | 375 (+0) | 26135 (-238) | 0.0141 (+0.000146) | 0.986 (-0.000146) | 8.84 (-0.0793) | 5.11 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 135600 (+0) | 153974 (-387) | 16950 (+0) | 137024 (-387) | 0.11 (+8.35e-05) | 0.89 (-8.35e-05) | 1.14 (-0.0025) | 14.2 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 43928 (+0) | 70457 (-237) | 5491 (+0) | 64966 (-237) | 0.0779 (-6.59e-05) | 0.922 (+6.59e-05) | 1.6 (-0.00508) | 8.6 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79792 (+0) | 105147 (-313) | 9974 (+0) | 95173 (-313) | 0.0949 (-0.000142) | 0.905 (+0.000142) | 1.32 (-0.00424) | 11.4 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 10168 (+0) | 79465 (-457) | 1271 (+0) | 78194 (-457) | 0.016 (-5.54e-06) | 0.984 (+5.54e-06) | 7.82 (-0.0448) | 4.85 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 101472 (+0) | 132784 (-415) | 12684 (+0) | 120100 (-415) | 0.0955 (+0.000524) | 0.904 (-0.000524) | 1.31 (-0.00442) | 10.8 |
