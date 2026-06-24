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

## 2026-06-24 Full AV2 Regression Checkpoint

Baseline and current sources:

- Baseline Git SHA: `3945b1bc67a20e5cfa2ccf8d05910ab8741deef0`
- Current validated source Git SHA: `2ac43800abe655dd03f213a1cb3e70b604fde4c1`
- Delta columns compare against the previous documented AV2 output-utilization
  checkpoint where the same vector or aggregate was present. New 4:2:0 output
  utilization rows use `n/a` deltas until the next run.

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- A palette map parallelism experiment was rejected for this checkpoint because
  it increased Yosys area without improving measured top-level utilization; the
  retained RTL keeps the scalar map path.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 64 | 755272 (+0) | 891536 (-79728) | 94409 (+0) | 797127 (-79728) | 0.106 (+0.00869) | 0.894 (-0.00889) | 1.18 (-0.11) | 10.7 |
| `screenshot-multictu-444` | 10 | 570480 (+0) | 766069 (-88025) | 71310 (+0) | 694759 (-88025) | 0.0931 (+0.00959) | 0.907 (-0.0101) | 1.34 (-0.157) | 8.34 |
| `racehorses-sweep-420` | 64 | 182464 (n/a) | 414890 (n/a) | 22808 (n/a) | 392082 (n/a) | 0.055 (n/a) | 0.945 (n/a) | 2.27 (n/a) | 5 |
| `racehorses-multictu-420` | 10 | 186256 (n/a) | 447495 (n/a) | 23282 (n/a) | 424213 (n/a) | 0.052 (n/a) | 0.948 (n/a) | 2.4 (n/a) | 4.87 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.106 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00665 |
| Frame reader sample issue | 0.124 |
| Reader-to-FIFO handshake | 0.152 |
| Input FIFO-to-core handshake | 0.995 |
| Input FIFO nonempty rate | 0.28 |
| Input FIFO full rate | 0.266 |
| AV2 leaf entropy op issue | 0.973 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.455 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.358 |
| AV2 carry payload bytes/cycle | 1.04 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 569 (-44) | 43 (+0) | 526 (-44) | 0.0756 (+0.00547) | 0.924 (-0.00557) | 1.65 (-0.126) | 8.89 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 2034 (-115) | 248 (+0) | 1786 (-115) | 0.122 (+0.00693) | 0.878 (-0.00693) | 1.03 (-0.0548) | 15.9 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 1189 (-210) | 52 (+0) | 1137 (-210) | 0.0437 (+0.00653) | 0.956 (-0.00673) | 2.86 (-0.502) | 6.19 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 1752 (-233) | 92 (+0) | 1660 (-233) | 0.0525 (+0.00621) | 0.947 (-0.00651) | 2.38 (-0.32) | 6.84 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 1812 (-328) | 60 (+0) | 1752 (-328) | 0.0331 (+0.00511) | 0.967 (-0.00511) | 3.77 (-0.685) | 5.66 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 2123 (-351) | 65 (+0) | 2058 (-351) | 0.0306 (+0.00432) | 0.969 (-0.00462) | 4.08 (-0.677) | 5.53 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6864 (+0) | 6911 (-446) | 858 (+0) | 6053 (-446) | 0.124 (+0.00715) | 0.876 (-0.00715) | 1.01 (-0.0632) | 15.4 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 7614 (-469) | 852 (+0) | 6762 (-469) | 0.112 (+0.0069) | 0.888 (-0.0069) | 1.12 (-0.0729) | 14.9 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1824 (+0) | 1891 (-91) | 228 (+0) | 1663 (-91) | 0.121 (+0.00557) | 0.879 (-0.00557) | 1.04 (-0.0533) | 14.8 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4616 (+0) | 4464 (-233) | 577 (+0) | 3887 (-233) | 0.129 (+0.00626) | 0.871 (-0.00626) | 0.967 (-0.0529) | 17.4 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 472 (+0) | 1914 (-423) | 59 (+0) | 1855 (-423) | 0.0308 (+0.00563) | 0.969 (-0.00583) | 4.06 (-0.895) | 4.98 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 512 (+0) | 2424 (-469) | 64 (+0) | 2360 (-469) | 0.0264 (+0.0043) | 0.974 (-0.0044) | 4.73 (-0.916) | 4.73 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9744 (+0) | 10251 (-659) | 1218 (+0) | 9033 (-659) | 0.119 (+0.00682) | 0.881 (-0.00682) | 1.05 (-0.068) | 16 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 608 (+0) | 3453 (-705) | 76 (+0) | 3377 (-705) | 0.022 (+0.00371) | 0.978 (-0.00401) | 5.68 (-1.16) | 4.5 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10648 (+0) | 12049 (-895) | 1331 (+0) | 10718 (-895) | 0.11 (+0.00747) | 0.89 (-0.00747) | 1.13 (-0.0884) | 13.4 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 696 (+0) | 4479 (-941) | 87 (+0) | 4392 (-941) | 0.0194 (+0.00332) | 0.981 (-0.00342) | 6.44 (-1.35) | 4.37 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3536 (+0) | 3438 (-138) | 442 (+0) | 2996 (-138) | 0.129 (+0.00456) | 0.871 (-0.00456) | 0.972 (-0.0377) | 17.9 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2728 (+0) | 3668 (-351) | 341 (+0) | 3327 (-351) | 0.093 (+0.00817) | 0.907 (-0.00797) | 1.34 (-0.125) | 9.55 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7000 (+0) | 7729 (-636) | 875 (+0) | 6854 (-636) | 0.113 (+0.00821) | 0.887 (-0.00821) | 1.1 (-0.0959) | 13.4 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 14664 (+0) | 13858 (-705) | 1833 (+0) | 12025 (-705) | 0.132 (+0.00627) | 0.868 (-0.00627) | 0.945 (-0.048) | 18 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15360 (+0) | 15360 (-990) | 1920 (+0) | 13440 (-990) | 0.125 (+0.008) | 0.875 (-0.008) | 1 (-0.06) | 16 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 4795 (-1059) | 85 (+0) | 4710 (-1059) | 0.0177 (+0.00323) | 0.982 (-0.00273) | 7.05 (-1.56) | 4.16 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 5515 (-1344) | 90 (+0) | 5425 (-1344) | 0.0163 (+0.00322) | 0.984 (-0.00332) | 7.66 (-1.87) | 4.1 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 23320 (+0) | 23978 (-1413) | 2915 (+0) | 21063 (-1413) | 0.122 (+0.00657) | 0.878 (-0.00657) | 1.03 (-0.0618) | 15.6 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3016 (+0) | 3297 (-185) | 377 (+0) | 2920 (-185) | 0.114 (+0.00635) | 0.886 (-0.00635) | 1.09 (-0.0568) | 12.9 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1328 (+0) | 3087 (-469) | 166 (+0) | 2921 (-469) | 0.0538 (+0.00707) | 0.946 (-0.00677) | 2.32 (-0.355) | 6.03 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1696 (+0) | 4287 (-849) | 212 (+0) | 4075 (-849) | 0.0495 (+0.00815) | 0.951 (-0.00845) | 2.53 (-0.502) | 5.58 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11088 (+0) | 12370 (-941) | 1386 (+0) | 10984 (-941) | 0.112 (+0.00805) | 0.888 (-0.00805) | 1.12 (-0.0844) | 12.1 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 5199 (-1321) | 86 (+0) | 5113 (-1321) | 0.0165 (+0.00334) | 0.983 (-0.00354) | 7.56 (-1.92) | 4.06 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 22176 (+0) | 23980 (-1413) | 2772 (+0) | 21208 (-1413) | 0.116 (+0.0066) | 0.884 (-0.0066) | 1.08 (-0.0687) | 15.6 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 27264 (+0) | 28059 (-1793) | 3408 (+0) | 24651 (-1793) | 0.121 (+0.00746) | 0.879 (-0.00746) | 1.03 (-0.0608) | 15.7 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 7954 (-1885) | 107 (+0) | 7847 (-1885) | 0.0135 (+0.00255) | 0.987 (-0.00245) | 9.29 (-2.21) | 3.88 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 5952 (+0) | 5722 (-232) | 744 (+0) | 4978 (-232) | 0.13 (+0.00502) | 0.87 (-0.00502) | 0.961 (-0.0386) | 17.9 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 13240 (+0) | 12384 (-587) | 1655 (+0) | 10729 (-587) | 0.134 (+0.00564) | 0.866 (-0.00564) | 0.935 (-0.0447) | 19.4 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1616 (+0) | 4985 (-1062) | 202 (+0) | 4783 (-1062) | 0.0405 (+0.00712) | 0.959 (-0.00752) | 3.08 (-0.655) | 5.19 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21832 (+0) | 21556 (-1177) | 2729 (+0) | 18827 (-1177) | 0.127 (+0.0066) | 0.873 (-0.0066) | 0.987 (-0.0526) | 16.8 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 21976 (+0) | 22880 (-1652) | 2747 (+0) | 20133 (-1652) | 0.12 (+0.00806) | 0.88 (-0.00806) | 1.04 (-0.0789) | 14.3 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1552 (+0) | 8131 (-1767) | 194 (+0) | 7937 (-1767) | 0.0239 (+0.00426) | 0.976 (-0.00386) | 5.24 (-1.14) | 4.23 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 20568 (+0) | 23875 (-2242) | 2571 (+0) | 21304 (-2242) | 0.108 (+0.00929) | 0.892 (-0.00969) | 1.16 (-0.109) | 10.7 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 9864 (-2357) | 143 (+0) | 9721 (-2357) | 0.0145 (+0.0028) | 0.986 (-0.0025) | 8.62 (-2.08) | 3.85 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 2221 (-279) | 83 (+0) | 2138 (-279) | 0.0374 (+0.00417) | 0.963 (-0.00437) | 3.34 (-0.425) | 5.78 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 15856 (+0) | 15150 (-705) | 1982 (+0) | 13168 (-705) | 0.131 (+0.00583) | 0.869 (-0.00583) | 0.955 (-0.0445) | 19.7 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 15112 (+0) | 16019 (-1275) | 1889 (+0) | 14130 (-1275) | 0.118 (+0.00892) | 0.882 (-0.00892) | 1.06 (-0.08) | 13.9 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15728 (+0) | 17941 (-1413) | 1966 (+0) | 15975 (-1413) | 0.11 (+0.00758) | 0.89 (-0.00758) | 1.14 (-0.0893) | 11.7 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 30328 (+0) | 29936 (-1983) | 3791 (+0) | 26145 (-1983) | 0.127 (+0.00764) | 0.873 (-0.00764) | 0.987 (-0.0629) | 15.6 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 8776 (-2121) | 110 (+0) | 8666 (-2121) | 0.0125 (+0.00243) | 0.987 (-0.00253) | 9.97 (-2.43) | 3.81 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 13248 (+0) | 21651 (-2691) | 1656 (+0) | 19995 (-2691) | 0.0765 (+0.00849) | 0.924 (-0.00849) | 1.63 (-0.206) | 8.05 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 11594 (-2829) | 155 (+0) | 11439 (-2829) | 0.0134 (+0.00267) | 0.987 (-0.00237) | 9.35 (-2.25) | 3.77 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 6952 (+0) | 6855 (-326) | 869 (+0) | 5986 (-326) | 0.127 (+0.00577) | 0.873 (-0.00577) | 0.986 (-0.044) | 15.3 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9808 (+0) | 11179 (-823) | 1226 (+0) | 9953 (-823) | 0.11 (+0.00767) | 0.89 (-0.00767) | 1.14 (-0.0802) | 12.5 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11976 (+0) | 14468 (-1488) | 1497 (+0) | 12971 (-1488) | 0.103 (+0.00967) | 0.897 (-0.00947) | 1.21 (-0.122) | 10.8 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18864 (+0) | 21074 (-1649) | 2358 (+0) | 18716 (-1649) | 0.112 (+0.00789) | 0.888 (-0.00789) | 1.12 (-0.0828) | 11.8 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37184 (+0) | 36653 (-2314) | 4648 (+0) | 32005 (-2314) | 0.127 (+0.00781) | 0.873 (-0.00781) | 0.986 (-0.0643) | 16.4 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22544 (+0) | 27000 (-2475) | 2818 (+0) | 24182 (-2475) | 0.104 (+0.00877) | 0.896 (-0.00837) | 1.2 (-0.112) | 10 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 57760 (+0) | 56224 (-3140) | 7220 (+0) | 49004 (-3140) | 0.128 (+0.00641) | 0.872 (-0.00641) | 0.973 (-0.0566) | 17.9 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28200 (+0) | 34273 (-3301) | 3525 (+0) | 30748 (-3301) | 0.103 (+0.00905) | 0.897 (-0.00885) | 1.22 (-0.115) | 9.56 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5344 (+0) | 6319 (-373) | 668 (+0) | 5651 (-373) | 0.106 (+0.00591) | 0.894 (-0.00571) | 1.18 (-0.0676) | 12.3 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 15448 (+0) | 15672 (-941) | 1931 (+0) | 13741 (-941) | 0.123 (+0.00721) | 0.877 (-0.00721) | 1.01 (-0.0655) | 15.3 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13496 (+0) | 15960 (-1701) | 1687 (+0) | 14273 (-1701) | 0.106 (+0.0102) | 0.894 (-0.0097) | 1.18 (-0.127) | 10.4 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32040 (+0) | 32292 (-1885) | 4005 (+0) | 28287 (-1885) | 0.124 (+0.00702) | 0.876 (-0.00702) | 1.01 (-0.0621) | 15.8 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2096 (+0) | 10653 (-2645) | 262 (+0) | 10391 (-2645) | 0.0246 (+0.00489) | 0.975 (-0.00459) | 5.08 (-1.26) | 4.16 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 50160 (+0) | 49527 (-2829) | 6270 (+0) | 43257 (-2829) | 0.127 (+0.0066) | 0.873 (-0.0066) | 0.987 (-0.0526) | 16.1 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2512 (+0) | 14560 (-3589) | 314 (+0) | 14246 (-3589) | 0.0216 (+0.00427) | 0.978 (-0.00457) | 5.8 (-1.42) | 4.06 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 76552 (+0) | 74639 (-3773) | 9569 (+0) | 65070 (-3773) | 0.128 (+0.0062) | 0.872 (-0.0062) | 0.975 (-0.045) | 18.2 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.0931 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00582 |
| Frame reader sample issue | 0.124 |
| Reader-to-FIFO handshake | 0.146 |
| Input FIFO-to-core handshake | 0.995 |
| Input FIFO nonempty rate | 0.361 |
| Input FIFO full rate | 0.353 |
| AV2 leaf entropy op issue | 0.979 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.501 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.353 |
| AV2 carry payload bytes/cycle | 1.01 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 88520 (+0) | 96336 (-7546) | 11065 (+0) | 85271 (-7546) | 0.115 (+0.00786) | 0.885 (-0.00786) | 1.09 (-0.0817) | 11.8 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 43928 (+0) | 62911 (-7546) | 5491 (+0) | 57420 (-7546) | 0.0873 (+0.00938) | 0.913 (-0.00928) | 1.43 (-0.168) | 7.68 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 10168 (+0) | 64373 (-15092) | 1271 (+0) | 63102 (-15092) | 0.0197 (+0.00374) | 0.98 (-0.00374) | 6.33 (-1.49) | 3.93 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45768 (+0) | 80737 (-11319) | 5721 (+0) | 75016 (-11319) | 0.0709 (+0.00876) | 0.929 (-0.00886) | 1.76 (-0.246) | 6.57 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 101472 (+0) | 121465 (-11319) | 12684 (+0) | 108781 (-11319) | 0.104 (+0.00893) | 0.896 (-0.00843) | 1.2 (-0.113) | 9.88 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 60568 (+0) | 63246 (-4818) | 7571 (+0) | 55675 (-4818) | 0.12 (+0.00871) | 0.88 (-0.00871) | 1.04 (-0.0758) | 13.7 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 17513 (-4242) | 208 (+0) | 17305 (-4242) | 0.0119 (+0.00232) | 0.988 (-0.00188) | 10.5 (-2.58) | 3.8 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3000 (+0) | 21095 (-5415) | 375 (+0) | 20720 (-5415) | 0.0178 (+0.00368) | 0.982 (-0.00378) | 7.03 (-1.81) | 4.07 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 135600 (+0) | 142882 (-11092) | 16950 (+0) | 125932 (-11092) | 0.119 (+0.00863) | 0.881 (-0.00863) | 1.05 (-0.0863) | 13.1 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79792 (+0) | 95511 (-9636) | 9974 (+0) | 85537 (-9636) | 0.104 (+0.00953) | 0.896 (-0.00943) | 1.2 (-0.123) | 10.4 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.055 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00352 |
| Frame reader sample issue | 0.121 |
| Reader-to-FIFO handshake | 0.152 |
| Input FIFO-to-core handshake | 0.738 |
| Input FIFO nonempty rate | 0.406 |
| Input FIFO full rate | 0.378 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 0 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 0 |
| AV2 prefetch useful fraction | 1 |
| AV2 carry payload bytes/cycle | 1.06 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (n/a) | 471 (n/a) | 38 (n/a) | 433 (n/a) | 0.0807 (n/a) | 0.919 (n/a) | 1.55 (n/a) | 7.36 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (n/a) | 793 (n/a) | 57 (n/a) | 736 (n/a) | 0.0719 (n/a) | 0.928 (n/a) | 1.74 (n/a) | 6.2 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (n/a) | 1132 (n/a) | 80 (n/a) | 1052 (n/a) | 0.0707 (n/a) | 0.929 (n/a) | 1.77 (n/a) | 5.9 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (n/a) | 1462 (n/a) | 103 (n/a) | 1359 (n/a) | 0.0705 (n/a) | 0.93 (n/a) | 1.77 (n/a) | 5.71 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (n/a) | 1782 (n/a) | 122 (n/a) | 1660 (n/a) | 0.0685 (n/a) | 0.932 (n/a) | 1.83 (n/a) | 5.57 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (n/a) | 2071 (n/a) | 129 (n/a) | 1942 (n/a) | 0.0623 (n/a) | 0.938 (n/a) | 2.01 (n/a) | 5.39 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (n/a) | 2404 (n/a) | 155 (n/a) | 2249 (n/a) | 0.0645 (n/a) | 0.936 (n/a) | 1.94 (n/a) | 5.37 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (n/a) | 2726 (n/a) | 174 (n/a) | 2552 (n/a) | 0.0638 (n/a) | 0.936 (n/a) | 1.96 (n/a) | 5.32 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (n/a) | 749 (n/a) | 42 (n/a) | 707 (n/a) | 0.0561 (n/a) | 0.944 (n/a) | 2.23 (n/a) | 5.85 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (n/a) | 1420 (n/a) | 93 (n/a) | 1327 (n/a) | 0.0655 (n/a) | 0.935 (n/a) | 1.91 (n/a) | 5.55 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (n/a) | 2008 (n/a) | 114 (n/a) | 1894 (n/a) | 0.0568 (n/a) | 0.943 (n/a) | 2.2 (n/a) | 5.23 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (n/a) | 2644 (n/a) | 152 (n/a) | 2492 (n/a) | 0.0575 (n/a) | 0.943 (n/a) | 2.17 (n/a) | 5.16 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (n/a) | 3278 (n/a) | 193 (n/a) | 3085 (n/a) | 0.0589 (n/a) | 0.941 (n/a) | 2.12 (n/a) | 5.12 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (n/a) | 3889 (n/a) | 222 (n/a) | 3667 (n/a) | 0.0571 (n/a) | 0.943 (n/a) | 2.19 (n/a) | 5.06 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (n/a) | 4531 (n/a) | 261 (n/a) | 4270 (n/a) | 0.0576 (n/a) | 0.942 (n/a) | 2.17 (n/a) | 5.06 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (n/a) | 5162 (n/a) | 292 (n/a) | 4870 (n/a) | 0.0566 (n/a) | 0.943 (n/a) | 2.21 (n/a) | 5.04 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (n/a) | 1095 (n/a) | 66 (n/a) | 1029 (n/a) | 0.0603 (n/a) | 0.94 (n/a) | 2.07 (n/a) | 5.7 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (n/a) | 2046 (n/a) | 122 (n/a) | 1924 (n/a) | 0.0596 (n/a) | 0.94 (n/a) | 2.1 (n/a) | 5.33 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (n/a) | 2948 (n/a) | 163 (n/a) | 2785 (n/a) | 0.0553 (n/a) | 0.945 (n/a) | 2.26 (n/a) | 5.12 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (n/a) | 3843 (n/a) | 204 (n/a) | 3639 (n/a) | 0.0531 (n/a) | 0.947 (n/a) | 2.35 (n/a) | 5 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (n/a) | 4846 (n/a) | 275 (n/a) | 4571 (n/a) | 0.0567 (n/a) | 0.943 (n/a) | 2.2 (n/a) | 5.05 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (n/a) | 5770 (n/a) | 325 (n/a) | 5445 (n/a) | 0.0563 (n/a) | 0.944 (n/a) | 2.22 (n/a) | 5.01 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (n/a) | 6732 (n/a) | 379 (n/a) | 6353 (n/a) | 0.0563 (n/a) | 0.944 (n/a) | 2.22 (n/a) | 5.01 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (n/a) | 7766 (n/a) | 448 (n/a) | 7318 (n/a) | 0.0577 (n/a) | 0.942 (n/a) | 2.17 (n/a) | 5.06 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (n/a) | 1366 (n/a) | 75 (n/a) | 1291 (n/a) | 0.0549 (n/a) | 0.945 (n/a) | 2.28 (n/a) | 5.34 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (n/a) | 2660 (n/a) | 149 (n/a) | 2511 (n/a) | 0.056 (n/a) | 0.944 (n/a) | 2.23 (n/a) | 5.2 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (n/a) | 3827 (n/a) | 200 (n/a) | 3627 (n/a) | 0.0523 (n/a) | 0.948 (n/a) | 2.39 (n/a) | 4.98 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (n/a) | 5122 (n/a) | 279 (n/a) | 4843 (n/a) | 0.0545 (n/a) | 0.946 (n/a) | 2.29 (n/a) | 5 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (n/a) | 6460 (n/a) | 369 (n/a) | 6091 (n/a) | 0.0571 (n/a) | 0.943 (n/a) | 2.19 (n/a) | 5.05 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (n/a) | 7640 (n/a) | 418 (n/a) | 7222 (n/a) | 0.0547 (n/a) | 0.945 (n/a) | 2.28 (n/a) | 4.97 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (n/a) | 8889 (n/a) | 489 (n/a) | 8400 (n/a) | 0.055 (n/a) | 0.945 (n/a) | 2.27 (n/a) | 4.96 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (n/a) | 10187 (n/a) | 568 (n/a) | 9619 (n/a) | 0.0558 (n/a) | 0.944 (n/a) | 2.24 (n/a) | 4.97 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (n/a) | 1716 (n/a) | 95 (n/a) | 1621 (n/a) | 0.0554 (n/a) | 0.945 (n/a) | 2.26 (n/a) | 5.36 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (n/a) | 3316 (n/a) | 191 (n/a) | 3125 (n/a) | 0.0576 (n/a) | 0.942 (n/a) | 2.17 (n/a) | 5.18 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (n/a) | 4779 (n/a) | 248 (n/a) | 4531 (n/a) | 0.0519 (n/a) | 0.948 (n/a) | 2.41 (n/a) | 4.98 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (n/a) | 6398 (n/a) | 344 (n/a) | 6054 (n/a) | 0.0538 (n/a) | 0.946 (n/a) | 2.32 (n/a) | 5 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (n/a) | 7942 (n/a) | 433 (n/a) | 7509 (n/a) | 0.0545 (n/a) | 0.945 (n/a) | 2.29 (n/a) | 4.96 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (n/a) | 9649 (n/a) | 552 (n/a) | 9097 (n/a) | 0.0572 (n/a) | 0.943 (n/a) | 2.19 (n/a) | 5.03 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (n/a) | 11120 (n/a) | 612 (n/a) | 10508 (n/a) | 0.055 (n/a) | 0.945 (n/a) | 2.27 (n/a) | 4.96 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (n/a) | 12714 (n/a) | 695 (n/a) | 12019 (n/a) | 0.0547 (n/a) | 0.945 (n/a) | 2.29 (n/a) | 4.97 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (n/a) | 2062 (n/a) | 121 (n/a) | 1941 (n/a) | 0.0587 (n/a) | 0.941 (n/a) | 2.13 (n/a) | 5.37 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (n/a) | 3977 (n/a) | 228 (n/a) | 3749 (n/a) | 0.0573 (n/a) | 0.943 (n/a) | 2.18 (n/a) | 5.18 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (n/a) | 5650 (n/a) | 285 (n/a) | 5365 (n/a) | 0.0504 (n/a) | 0.95 (n/a) | 2.48 (n/a) | 4.9 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (n/a) | 7586 (n/a) | 394 (n/a) | 7192 (n/a) | 0.0519 (n/a) | 0.948 (n/a) | 2.41 (n/a) | 4.94 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (n/a) | 9497 (n/a) | 513 (n/a) | 8984 (n/a) | 0.054 (n/a) | 0.946 (n/a) | 2.31 (n/a) | 4.95 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (n/a) | 11392 (n/a) | 627 (n/a) | 10765 (n/a) | 0.055 (n/a) | 0.945 (n/a) | 2.27 (n/a) | 4.94 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (n/a) | 13286 (n/a) | 722 (n/a) | 12564 (n/a) | 0.0543 (n/a) | 0.946 (n/a) | 2.3 (n/a) | 4.94 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (n/a) | 15136 (n/a) | 814 (n/a) | 14322 (n/a) | 0.0538 (n/a) | 0.946 (n/a) | 2.32 (n/a) | 4.93 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (n/a) | 2370 (n/a) | 134 (n/a) | 2236 (n/a) | 0.0565 (n/a) | 0.943 (n/a) | 2.21 (n/a) | 5.29 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (n/a) | 4588 (n/a) | 259 (n/a) | 4329 (n/a) | 0.0565 (n/a) | 0.944 (n/a) | 2.21 (n/a) | 5.12 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (n/a) | 6625 (n/a) | 335 (n/a) | 6290 (n/a) | 0.0506 (n/a) | 0.949 (n/a) | 2.47 (n/a) | 4.93 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (n/a) | 8850 (n/a) | 461 (n/a) | 8389 (n/a) | 0.0521 (n/a) | 0.948 (n/a) | 2.4 (n/a) | 4.94 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (n/a) | 11003 (n/a) | 587 (n/a) | 10416 (n/a) | 0.0533 (n/a) | 0.947 (n/a) | 2.34 (n/a) | 4.91 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (n/a) | 13347 (n/a) | 743 (n/a) | 12604 (n/a) | 0.0557 (n/a) | 0.944 (n/a) | 2.25 (n/a) | 4.97 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (n/a) | 15488 (n/a) | 838 (n/a) | 14650 (n/a) | 0.0541 (n/a) | 0.946 (n/a) | 2.31 (n/a) | 4.94 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (n/a) | 17649 (n/a) | 950 (n/a) | 16699 (n/a) | 0.0538 (n/a) | 0.946 (n/a) | 2.32 (n/a) | 4.92 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (n/a) | 2673 (n/a) | 148 (n/a) | 2525 (n/a) | 0.0554 (n/a) | 0.945 (n/a) | 2.26 (n/a) | 5.22 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (n/a) | 5183 (n/a) | 280 (n/a) | 4903 (n/a) | 0.054 (n/a) | 0.946 (n/a) | 2.31 (n/a) | 5.06 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (n/a) | 7588 (n/a) | 394 (n/a) | 7194 (n/a) | 0.0519 (n/a) | 0.948 (n/a) | 2.41 (n/a) | 4.94 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (n/a) | 10045 (n/a) | 514 (n/a) | 9531 (n/a) | 0.0512 (n/a) | 0.949 (n/a) | 2.44 (n/a) | 4.9 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (n/a) | 12564 (n/a) | 665 (n/a) | 11899 (n/a) | 0.0529 (n/a) | 0.947 (n/a) | 2.36 (n/a) | 4.91 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (n/a) | 15120 (n/a) | 812 (n/a) | 14308 (n/a) | 0.0537 (n/a) | 0.946 (n/a) | 2.33 (n/a) | 4.92 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (n/a) | 17686 (n/a) | 968 (n/a) | 16718 (n/a) | 0.0547 (n/a) | 0.945 (n/a) | 2.28 (n/a) | 4.93 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (n/a) | 20172 (n/a) | 1090 (n/a) | 19082 (n/a) | 0.054 (n/a) | 0.946 (n/a) | 2.31 (n/a) | 4.92 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.052 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00326 |
| Frame reader sample issue | 0.121 |
| Reader-to-FIFO handshake | 0.139 |
| Input FIFO-to-core handshake | 0.732 |
| Input FIFO nonempty rate | 0.42 |
| Input FIFO full rate | 0.407 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 0 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 0 |
| AV2 prefetch useful fraction | 1 |
| AV2 carry payload bytes/cycle | 1.01 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (n/a) | 40065 (n/a) | 2123 (n/a) | 37942 (n/a) | 0.053 (n/a) | 0.947 (n/a) | 2.36 (n/a) | 4.89 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (n/a) | 40116 (n/a) | 2145 (n/a) | 37971 (n/a) | 0.0535 (n/a) | 0.947 (n/a) | 2.34 (n/a) | 4.9 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (n/a) | 79084 (n/a) | 3977 (n/a) | 75107 (n/a) | 0.0503 (n/a) | 0.95 (n/a) | 2.49 (n/a) | 4.83 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (n/a) | 59742 (n/a) | 3111 (n/a) | 56631 (n/a) | 0.0521 (n/a) | 0.948 (n/a) | 2.4 (n/a) | 4.86 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (n/a) | 58950 (n/a) | 2827 (n/a) | 56123 (n/a) | 0.048 (n/a) | 0.952 (n/a) | 2.61 (n/a) | 4.8 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (n/a) | 22741 (n/a) | 1227 (n/a) | 21514 (n/a) | 0.054 (n/a) | 0.946 (n/a) | 2.32 (n/a) | 4.94 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (n/a) | 22717 (n/a) | 1242 (n/a) | 21475 (n/a) | 0.0547 (n/a) | 0.945 (n/a) | 2.29 (n/a) | 4.93 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (n/a) | 25691 (n/a) | 1423 (n/a) | 24268 (n/a) | 0.0554 (n/a) | 0.945 (n/a) | 2.26 (n/a) | 4.96 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (n/a) | 53278 (n/a) | 2819 (n/a) | 50459 (n/a) | 0.0529 (n/a) | 0.947 (n/a) | 2.36 (n/a) | 4.9 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (n/a) | 45111 (n/a) | 2388 (n/a) | 42723 (n/a) | 0.0529 (n/a) | 0.947 (n/a) | 2.36 (n/a) | 4.89 |
