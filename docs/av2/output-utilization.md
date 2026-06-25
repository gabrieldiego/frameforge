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

## 2026-06-25 AV2 Bubble Rate Optimization

Baseline and current sources:

- Baseline Git SHA: `6779c2e4b2726adef94cd7921dd62f106e454afb+working-tree`
- Current validated source Git SHA: `31bb9321589844a4615d8dd87fe96ef6b54f43ed`
- Delta columns compare against the previous documented AV2 output-utilization
  checkpoint where the same vector or aggregate was present.

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: not rerun for this checkpoint.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 64 | 749352 (+0) | 414156 (-10654) | 93669 (+0) | 320487 (-10654) | 0.226 (+0.00617) | 0.774 (-0.00617) | 0.553 (-0.0143) | 4.99 |
| `screenshot-multictu-444` | 10 | 562104 (+0) | 346387 (-18925) | 70263 (+0) | 276124 (-18925) | 0.203 (+0.0108) | 0.797 (-0.0108) | 0.616 (-0.0338) | 3.77 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 115401 (-14169) | 22808 (+0) | 92593 (-14169) | 0.198 (+0.0216) | 0.802 (-0.0216) | 0.632 (-0.0775) | 1.39 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 120222 (-16326) | 23282 (+0) | 96940 (-16326) | 0.194 (+0.0227) | 0.806 (-0.0227) | 0.645 (-0.0875) | 1.31 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.226 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0142 |
| Frame reader sample issue | 0.434 |
| Reader-to-FIFO handshake | 0.89 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.075 |
| Input FIFO full rate | 0.0111 |
| AV2 leaf entropy op issue | 0.951 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.437 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.147 |
| AV2 carry payload bytes/cycle | 16.3 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 286 (-81) | 43 (+0) | 243 (-81) | 0.15 (+0.0333) | 0.85 (-0.0333) | 0.831 (-0.239) | 4.47 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 922 (-91) | 248 (+0) | 674 (-91) | 0.269 (+0.024) | 0.731 (-0.024) | 0.465 (-0.0463) | 7.2 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 527 (-80) | 52 (+0) | 475 (-80) | 0.0987 (+0.013) | 0.901 (-0.0127) | 1.27 (-0.193) | 2.74 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 737 (-82) | 92 (+0) | 645 (-82) | 0.125 (+0.0128) | 0.875 (-0.0128) | 1 (-0.109) | 2.88 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 776 (-78) | 60 (+0) | 716 (-78) | 0.0773 (+0.00702) | 0.923 (-0.00732) | 1.62 (-0.163) | 2.42 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 876 (-80) | 65 (+0) | 811 (-80) | 0.0742 (+0.0062) | 0.926 (-0.0062) | 1.68 (-0.155) | 2.28 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 3683 (-128) | 854 (+0) | 2829 (-128) | 0.232 (+0.00788) | 0.768 (-0.00788) | 0.539 (-0.0189) | 8.22 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6960 (+0) | 4009 (-129) | 870 (+0) | 3139 (-129) | 0.217 (+0.00701) | 0.783 (-0.00701) | 0.576 (-0.019) | 7.83 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 900 (-90) | 220 (+0) | 680 (-90) | 0.244 (+0.0224) | 0.756 (-0.0224) | 0.511 (-0.0506) | 7.03 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4880 (+0) | 2186 (-116) | 610 (+0) | 1576 (-116) | 0.279 (+0.014) | 0.721 (-0.014) | 0.448 (-0.024) | 8.54 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (+0) | 880 (-79) | 63 (+0) | 817 (-79) | 0.0716 (+0.00589) | 0.928 (-0.00559) | 1.75 (-0.154) | 2.29 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 552 (+0) | 1015 (-78) | 69 (+0) | 946 (-78) | 0.068 (+0.00488) | 0.932 (-0.00498) | 1.84 (-0.141) | 1.98 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9208 (+0) | 5157 (-147) | 1151 (+0) | 4006 (-147) | 0.223 (+0.00619) | 0.777 (-0.00619) | 0.56 (-0.0159) | 8.06 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 704 (+0) | 1519 (-80) | 88 (+0) | 1431 (-80) | 0.0579 (+0.00293) | 0.942 (-0.00293) | 2.16 (-0.112) | 1.98 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10312 (+0) | 6232 (-155) | 1289 (+0) | 4943 (-155) | 0.207 (+0.00484) | 0.793 (-0.00484) | 0.604 (-0.0147) | 6.96 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 824 (+0) | 1956 (-82) | 103 (+0) | 1853 (-82) | 0.0527 (+0.00216) | 0.947 (-0.00166) | 2.37 (-0.0962) | 1.91 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3632 (+0) | 1793 (-105) | 454 (+0) | 1339 (-105) | 0.253 (+0.0142) | 0.747 (-0.0142) | 0.494 (-0.0293) | 9.34 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 1658 (-95) | 334 (+0) | 1324 (-95) | 0.201 (+0.0104) | 0.799 (-0.0104) | 0.621 (-0.0355) | 4.32 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+0) | 3562 (-129) | 881 (+0) | 2681 (-129) | 0.247 (+0.00833) | 0.753 (-0.00833) | 0.505 (-0.0186) | 6.18 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 7023 (-196) | 1961 (+0) | 5062 (-196) | 0.279 (+0.00723) | 0.721 (-0.00723) | 0.448 (-0.0123) | 9.14 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15256 (+0) | 6865 (-195) | 1907 (+0) | 4958 (-195) | 0.278 (+0.00779) | 0.722 (-0.00779) | 0.45 (-0.013) | 7.15 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 1704 (-80) | 85 (+0) | 1619 (-80) | 0.0499 (+0.00228) | 0.95 (-0.00188) | 2.51 (-0.114) | 1.48 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 2012 (-81) | 90 (+0) | 1922 (-81) | 0.0447 (+0.00173) | 0.955 (-0.00173) | 2.79 (-0.116) | 1.5 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 21472 (+0) | 11515 (-244) | 2684 (+0) | 8831 (-244) | 0.233 (+0.00509) | 0.767 (-0.00509) | 0.536 (-0.0117) | 7.5 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 1627 (-101) | 397 (+0) | 1230 (-101) | 0.244 (+0.014) | 0.756 (-0.014) | 0.512 (-0.0317) | 6.36 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1384 (+0) | 1377 (-84) | 173 (+0) | 1204 (-84) | 0.126 (+0.00764) | 0.874 (-0.00764) | 0.995 (-0.0651) | 2.69 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1440 (+0) | 1683 (-87) | 180 (+0) | 1503 (-87) | 0.107 (+0.00495) | 0.893 (-0.00495) | 1.17 (-0.0613) | 2.19 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11816 (+0) | 5659 (-166) | 1477 (+0) | 4182 (-166) | 0.261 (+0.007) | 0.739 (-0.007) | 0.479 (-0.0141) | 5.53 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 1909 (-80) | 86 (+0) | 1823 (-80) | 0.045 (+0.00185) | 0.955 (-0.00205) | 2.77 (-0.115) | 1.49 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20232 (+0) | 11246 (-233) | 2529 (+0) | 8717 (-233) | 0.225 (+0.00488) | 0.775 (-0.00488) | 0.556 (-0.0111) | 7.32 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26072 (+0) | 13507 (-279) | 3259 (+0) | 10248 (-279) | 0.241 (+0.00528) | 0.759 (-0.00528) | 0.518 (-0.0109) | 7.54 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 2683 (-83) | 107 (+0) | 2576 (-83) | 0.0399 (+0.00118) | 0.96 (-0.000881) | 3.13 (-0.0957) | 1.31 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 2826 (-121) | 757 (+0) | 2069 (-121) | 0.268 (+0.0109) | 0.732 (-0.0109) | 0.467 (-0.0204) | 8.83 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14504 (+0) | 6415 (-187) | 1813 (+0) | 4602 (-187) | 0.283 (+0.00762) | 0.717 (-0.00762) | 0.442 (-0.0127) | 10 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1296 (+0) | 1982 (-85) | 162 (+0) | 1820 (-85) | 0.0817 (+0.00334) | 0.918 (-0.00374) | 1.53 (-0.0607) | 2.06 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21328 (+0) | 10428 (-241) | 2666 (+0) | 7762 (-241) | 0.256 (+0.00566) | 0.744 (-0.00566) | 0.489 (-0.0111) | 8.15 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22824 (+0) | 11110 (-253) | 2853 (+0) | 8257 (-253) | 0.257 (+0.0058) | 0.743 (-0.0058) | 0.487 (-0.0112) | 6.94 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1712 (+0) | 2988 (-88) | 214 (+0) | 2774 (-88) | 0.0716 (+0.00202) | 0.928 (-0.00162) | 1.75 (-0.0547) | 1.56 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19224 (+0) | 11054 (-226) | 2403 (+0) | 8651 (-226) | 0.217 (+0.00439) | 0.783 (-0.00439) | 0.575 (-0.012) | 4.93 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 3291 (-85) | 143 (+0) | 3148 (-85) | 0.0435 (+0.00105) | 0.957 (-0.00145) | 2.88 (-0.0733) | 1.29 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 640 (+0) | 1002 (-79) | 80 (+0) | 922 (-79) | 0.0798 (+0.00584) | 0.92 (-0.00584) | 1.57 (-0.124) | 2.61 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 17104 (+0) | 8228 (-208) | 2138 (+0) | 6090 (-208) | 0.26 (+0.00684) | 0.74 (-0.00684) | 0.481 (-0.0119) | 10.7 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14712 (+0) | 7551 (-189) | 1839 (+0) | 5712 (-189) | 0.244 (+0.00554) | 0.756 (-0.00554) | 0.513 (-0.0127) | 6.55 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15952 (+0) | 8320 (-199) | 1994 (+0) | 6326 (-199) | 0.24 (+0.00566) | 0.76 (-0.00566) | 0.522 (-0.0124) | 5.42 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31720 (+0) | 14817 (-322) | 3965 (+0) | 10852 (-322) | 0.268 (+0.0056) | 0.732 (-0.0056) | 0.467 (-0.00988) | 7.72 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 2920 (-82) | 110 (+0) | 2810 (-82) | 0.0377 (+0.00107) | 0.962 (-0.000671) | 3.32 (-0.0918) | 1.27 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10856 (+0) | 9338 (-159) | 1357 (+0) | 7981 (-159) | 0.145 (+0.00232) | 0.855 (-0.00232) | 0.86 (-0.0148) | 3.47 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 3804 (-85) | 155 (+0) | 3649 (-85) | 0.0407 (+0.000847) | 0.959 (-0.000747) | 3.07 (-0.0723) | 1.24 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 3499 (-130) | 894 (+0) | 2605 (-130) | 0.256 (+0.0095) | 0.744 (-0.0095) | 0.489 (-0.0178) | 7.81 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9600 (+0) | 5394 (-150) | 1200 (+0) | 4194 (-150) | 0.222 (+0.00647) | 0.778 (-0.00647) | 0.562 (-0.0161) | 6.02 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11736 (+0) | 6815 (-166) | 1467 (+0) | 5348 (-166) | 0.215 (+0.00526) | 0.785 (-0.00526) | 0.581 (-0.0143) | 5.07 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18064 (+0) | 9544 (-216) | 2258 (+0) | 7286 (-216) | 0.237 (+0.00559) | 0.763 (-0.00559) | 0.528 (-0.0117) | 5.33 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 38912 (+0) | 18567 (-380) | 4864 (+0) | 13703 (-380) | 0.262 (+0.00497) | 0.738 (-0.00497) | 0.477 (-0.00985) | 8.29 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22672 (+0) | 12314 (-253) | 2834 (+0) | 9480 (-253) | 0.23 (+0.00414) | 0.77 (-0.00414) | 0.543 (-0.0109) | 4.58 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56384 (+0) | 26683 (-516) | 7048 (+0) | 19635 (-516) | 0.264 (+0.00514) | 0.736 (-0.00514) | 0.473 (-0.00876) | 8.51 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 27056 (+0) | 14820 (-286) | 3382 (+0) | 11438 (-286) | 0.228 (+0.00421) | 0.772 (-0.00421) | 0.548 (-0.0102) | 4.14 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5568 (+0) | 3168 (-118) | 696 (+0) | 2472 (-118) | 0.22 (+0.0077) | 0.78 (-0.0077) | 0.569 (-0.021) | 6.19 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 17248 (+0) | 8247 (-210) | 2156 (+0) | 6091 (-210) | 0.261 (+0.00643) | 0.739 (-0.00643) | 0.478 (-0.0119) | 8.05 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13032 (+0) | 7267 (-175) | 1629 (+0) | 5638 (-175) | 0.224 (+0.00516) | 0.776 (-0.00516) | 0.558 (-0.0134) | 4.73 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32824 (+0) | 15462 (-330) | 4103 (+0) | 11359 (-330) | 0.265 (+0.00536) | 0.735 (-0.00536) | 0.471 (-0.00994) | 7.55 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2064 (+0) | 3900 (-92) | 258 (+0) | 3642 (-92) | 0.0662 (+0.00155) | 0.934 (-0.00115) | 1.89 (-0.0405) | 1.52 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49072 (+0) | 23450 (-458) | 6134 (+0) | 17316 (-458) | 0.262 (+0.00458) | 0.738 (-0.00458) | 0.478 (-0.00913) | 7.63 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2536 (+0) | 5250 (-94) | 317 (+0) | 4933 (-94) | 0.0604 (+0.00108) | 0.94 (-0.00138) | 2.07 (-0.0398) | 1.46 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74392 (+0) | 36218 (-657) | 9299 (+0) | 26919 (-657) | 0.257 (+0.00475) | 0.743 (-0.00475) | 0.487 (-0.00915) | 8.84 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.203 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0127 |
| Frame reader sample issue | 0.453 |
| Reader-to-FIFO handshake | 0.91 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0887 |
| Input FIFO full rate | 0.0117 |
| AV2 leaf entropy op issue | 0.959 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.474 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.144 |
| AV2 carry payload bytes/cycle | 8.65 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 85944 (+0) | 46880 (-1106) | 10743 (+0) | 36137 (-1106) | 0.229 (+0.00516) | 0.771 (-0.00516) | 0.545 (-0.0125) | 5.72 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 42560 (+0) | 27191 (-111) | 5320 (+0) | 21871 (-111) | 0.196 (+0.000653) | 0.804 (-0.000653) | 0.639 (-0.00211) | 3.32 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 9784 (+0) | 21634 (-370) | 1223 (+0) | 20411 (-370) | 0.0565 (+0.000931) | 0.943 (-0.000531) | 2.21 (-0.0388) | 1.32 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 42200 (+0) | 33388 (-735) | 5275 (+0) | 28113 (-735) | 0.158 (+0.00299) | 0.842 (-0.00299) | 0.791 (-0.0178) | 2.72 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105584 (+0) | 58312 (-6205) | 13198 (+0) | 45114 (-6205) | 0.226 (+0.0213) | 0.774 (-0.0213) | 0.552 (-0.0587) | 4.75 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57192 (+0) | 30246 (-945) | 7149 (+0) | 23097 (-945) | 0.236 (+0.00736) | 0.764 (-0.00736) | 0.529 (-0.0161) | 6.56 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 5834 (-116) | 208 (+0) | 5626 (-116) | 0.0357 (+0.000653) | 0.964 (-0.000653) | 3.51 (-0.074) | 1.27 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2984 (+0) | 7685 (-210) | 373 (+0) | 7312 (-210) | 0.0485 (+0.00134) | 0.951 (-0.00154) | 2.58 (-0.0746) | 1.48 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136424 (+0) | 69807 (-4130) | 17053 (+0) | 52754 (-4130) | 0.244 (+0.0133) | 0.756 (-0.0133) | 0.512 (-0.0303) | 6.42 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 77768 (+0) | 45410 (-4997) | 9721 (+0) | 35689 (-4997) | 0.214 (+0.0211) | 0.786 (-0.0211) | 0.584 (-0.0641) | 4.93 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.198 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0126 |
| Frame reader sample issue | 0.57 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.157 |
| AV2 carry payload bytes/cycle | 16.6 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (+0) | 196 (-80) | 38 (+0) | 158 (-80) | 0.194 (+0.0559) | 0.806 (-0.0559) | 0.645 (-0.263) | 3.06 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 268 (-86) | 57 (+0) | 211 (-86) | 0.213 (+0.0517) | 0.787 (-0.0517) | 0.588 (-0.188) | 2.09 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 374 (-102) | 80 (+0) | 294 (-102) | 0.214 (+0.0459) | 0.786 (-0.0459) | 0.584 (-0.16) | 1.95 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 446 (-115) | 103 (+0) | 343 (-115) | 0.231 (+0.0469) | 0.769 (-0.0469) | 0.541 (-0.14) | 1.74 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 569 (-112) | 122 (+0) | 447 (-112) | 0.214 (+0.0354) | 0.786 (-0.0354) | 0.583 (-0.115) | 1.78 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 610 (-123) | 129 (+0) | 481 (-123) | 0.211 (+0.0355) | 0.789 (-0.0355) | 0.591 (-0.119) | 1.59 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 729 (-121) | 155 (+0) | 574 (-121) | 0.213 (+0.0306) | 0.787 (-0.0306) | 0.588 (-0.0971) | 1.63 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 784 (-142) | 174 (+0) | 610 (-142) | 0.222 (+0.0339) | 0.778 (-0.0339) | 0.563 (-0.102) | 1.53 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 266 (-87) | 42 (+0) | 224 (-87) | 0.158 (+0.0389) | 0.842 (-0.0389) | 0.792 (-0.258) | 2.08 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 435 (-116) | 93 (+0) | 342 (-116) | 0.214 (+0.0448) | 0.786 (-0.0448) | 0.585 (-0.156) | 1.7 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 602 (-117) | 114 (+0) | 488 (-117) | 0.189 (+0.0304) | 0.811 (-0.0304) | 0.66 (-0.128) | 1.57 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 732 (-138) | 152 (+0) | 580 (-138) | 0.208 (+0.0327) | 0.792 (-0.0327) | 0.602 (-0.113) | 1.43 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 967 (-147) | 193 (+0) | 774 (-147) | 0.2 (+0.0266) | 0.8 (-0.0266) | 0.626 (-0.0957) | 1.51 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 1076 (-170) | 222 (+0) | 854 (-170) | 0.206 (+0.0283) | 0.794 (-0.0283) | 0.606 (-0.0961) | 1.4 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 1296 (-165) | 261 (+0) | 1035 (-165) | 0.201 (+0.0224) | 0.799 (-0.0224) | 0.621 (-0.0793) | 1.45 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 1388 (-204) | 292 (+0) | 1096 (-204) | 0.21 (+0.0274) | 0.79 (-0.0274) | 0.594 (-0.0878) | 1.36 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 383 (-111) | 66 (+0) | 317 (-111) | 0.172 (+0.0383) | 0.828 (-0.0383) | 0.725 (-0.211) | 1.99 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 603 (-126) | 122 (+0) | 481 (-126) | 0.202 (+0.0353) | 0.798 (-0.0353) | 0.618 (-0.129) | 1.57 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 872 (-140) | 163 (+0) | 709 (-140) | 0.187 (+0.0259) | 0.813 (-0.0259) | 0.669 (-0.107) | 1.51 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 1031 (-168) | 204 (+0) | 827 (-168) | 0.198 (+0.0279) | 0.802 (-0.0279) | 0.632 (-0.103) | 1.34 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 1406 (-181) | 275 (+0) | 1131 (-181) | 0.196 (+0.0226) | 0.804 (-0.0226) | 0.639 (-0.0819) | 1.46 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 1595 (-217) | 325 (+0) | 1270 (-217) | 0.204 (+0.0248) | 0.796 (-0.0248) | 0.613 (-0.0835) | 1.38 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 1915 (-208) | 379 (+0) | 1536 (-208) | 0.198 (+0.0189) | 0.802 (-0.0189) | 0.632 (-0.0684) | 1.42 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 2119 (-269) | 448 (+0) | 1671 (-269) | 0.211 (+0.0234) | 0.789 (-0.0234) | 0.591 (-0.0748) | 1.38 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 459 (-122) | 75 (+0) | 384 (-122) | 0.163 (+0.0344) | 0.837 (-0.0344) | 0.765 (-0.203) | 1.79 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 757 (-137) | 149 (+0) | 608 (-137) | 0.197 (+0.0298) | 0.803 (-0.0298) | 0.635 (-0.115) | 1.48 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 1110 (-159) | 200 (+0) | 910 (-159) | 0.18 (+0.0222) | 0.82 (-0.0222) | 0.694 (-0.0993) | 1.45 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 1371 (-198) | 279 (+0) | 1092 (-198) | 0.204 (+0.0255) | 0.796 (-0.0255) | 0.614 (-0.0888) | 1.34 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 1865 (-208) | 369 (+0) | 1496 (-208) | 0.198 (+0.0199) | 0.802 (-0.0199) | 0.632 (-0.0702) | 1.46 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 2077 (-254) | 418 (+0) | 1659 (-254) | 0.201 (+0.0223) | 0.799 (-0.0223) | 0.621 (-0.0759) | 1.35 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 2498 (-244) | 489 (+0) | 2009 (-244) | 0.196 (+0.0178) | 0.804 (-0.0178) | 0.639 (-0.0625) | 1.39 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 2722 (-328) | 568 (+0) | 2154 (-328) | 0.209 (+0.0227) | 0.791 (-0.0227) | 0.599 (-0.072) | 1.33 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 579 (-127) | 95 (+0) | 484 (-127) | 0.164 (+0.0291) | 0.836 (-0.0291) | 0.762 (-0.167) | 1.81 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 955 (-158) | 191 (+0) | 764 (-158) | 0.2 (+0.028) | 0.8 (-0.028) | 0.625 (-0.103) | 1.49 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 1384 (-179) | 248 (+0) | 1136 (-179) | 0.179 (+0.0202) | 0.821 (-0.0202) | 0.698 (-0.0904) | 1.44 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 1701 (-227) | 344 (+0) | 1357 (-227) | 0.202 (+0.0242) | 0.798 (-0.0242) | 0.618 (-0.0829) | 1.33 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 2263 (-240) | 433 (+0) | 1830 (-240) | 0.191 (+0.0183) | 0.809 (-0.0183) | 0.653 (-0.0697) | 1.41 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 2663 (-302) | 552 (+0) | 2111 (-302) | 0.207 (+0.0213) | 0.793 (-0.0213) | 0.603 (-0.068) | 1.39 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 3121 (-287) | 612 (+0) | 2509 (-287) | 0.196 (+0.0161) | 0.804 (-0.0161) | 0.637 (-0.0585) | 1.39 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 3379 (-377) | 695 (+0) | 2684 (-377) | 0.206 (+0.0207) | 0.794 (-0.0207) | 0.608 (-0.0683) | 1.32 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 697 (-138) | 121 (+0) | 576 (-138) | 0.174 (+0.0286) | 0.826 (-0.0286) | 0.72 (-0.143) | 1.82 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 1141 (-173) | 228 (+0) | 913 (-173) | 0.2 (+0.0258) | 0.8 (-0.0258) | 0.626 (-0.0945) | 1.49 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 1611 (-200) | 285 (+0) | 1326 (-200) | 0.177 (+0.0199) | 0.823 (-0.0199) | 0.707 (-0.0874) | 1.4 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 1988 (-255) | 394 (+0) | 1594 (-255) | 0.198 (+0.0222) | 0.802 (-0.0222) | 0.631 (-0.0813) | 1.29 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 2688 (-268) | 513 (+0) | 2175 (-268) | 0.191 (+0.0168) | 0.809 (-0.0168) | 0.655 (-0.065) | 1.4 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 3089 (-348) | 627 (+0) | 2462 (-348) | 0.203 (+0.021) | 0.797 (-0.021) | 0.616 (-0.0692) | 1.34 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 3715 (-324) | 722 (+0) | 2993 (-324) | 0.194 (+0.0153) | 0.806 (-0.0153) | 0.643 (-0.0558) | 1.38 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 4004 (-443) | 814 (+0) | 3190 (-443) | 0.203 (+0.0203) | 0.797 (-0.0203) | 0.615 (-0.0681) | 1.3 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 791 (-146) | 134 (+0) | 657 (-146) | 0.169 (+0.0264) | 0.831 (-0.0264) | 0.738 (-0.136) | 1.77 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 1298 (-191) | 259 (+0) | 1039 (-191) | 0.2 (+0.0255) | 0.8 (-0.0255) | 0.626 (-0.0926) | 1.45 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 1892 (-213) | 335 (+0) | 1557 (-213) | 0.177 (+0.0181) | 0.823 (-0.0181) | 0.706 (-0.079) | 1.41 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 2310 (-280) | 461 (+0) | 1849 (-280) | 0.2 (+0.0216) | 0.8 (-0.0216) | 0.626 (-0.0756) | 1.29 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 3094 (-304) | 587 (+0) | 2507 (-304) | 0.19 (+0.0167) | 0.81 (-0.0167) | 0.659 (-0.0651) | 1.38 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 3638 (-388) | 743 (+0) | 2895 (-388) | 0.204 (+0.0192) | 0.796 (-0.0192) | 0.612 (-0.065) | 1.35 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 4321 (-365) | 838 (+0) | 3483 (-365) | 0.194 (+0.0149) | 0.806 (-0.0149) | 0.645 (-0.0545) | 1.38 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 4658 (-501) | 950 (+0) | 3708 (-501) | 0.204 (+0.02) | 0.796 (-0.02) | 0.613 (-0.0661) | 1.3 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 876 (-155) | 148 (+0) | 728 (-155) | 0.169 (+0.0249) | 0.831 (-0.0249) | 0.74 (-0.131) | 1.71 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 1438 (-199) | 280 (+0) | 1158 (-199) | 0.195 (+0.0237) | 0.805 (-0.0237) | 0.642 (-0.089) | 1.4 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2173 (-238) | 394 (+0) | 1779 (-238) | 0.181 (+0.0183) | 0.819 (-0.0183) | 0.689 (-0.0756) | 1.41 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 2600 (-310) | 514 (+0) | 2086 (-310) | 0.198 (+0.0207) | 0.802 (-0.0207) | 0.632 (-0.0757) | 1.27 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 3507 (-330) | 665 (+0) | 2842 (-330) | 0.19 (+0.0166) | 0.81 (-0.0166) | 0.659 (-0.0618) | 1.37 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 4055 (-430) | 812 (+0) | 3243 (-430) | 0.2 (+0.0192) | 0.8 (-0.0192) | 0.624 (-0.0658) | 1.32 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 4944 (-412) | 968 (+0) | 3976 (-412) | 0.196 (+0.0148) | 0.804 (-0.0148) | 0.638 (-0.0536) | 1.38 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 5307 (-566) | 1090 (+0) | 4217 (-566) | 0.205 (+0.0194) | 0.795 (-0.0194) | 0.609 (-0.0654) | 1.3 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.194 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0121 |
| Frame reader sample issue | 0.599 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.157 |
| AV2 carry payload bytes/cycle | 8.09 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 10576 (-1180) | 2123 (+0) | 8453 (-1180) | 0.201 (+0.0197) | 0.799 (-0.0197) | 0.623 (-0.0693) | 1.29 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 10667 (-1715) | 2145 (+0) | 8522 (-1715) | 0.201 (+0.0281) | 0.799 (-0.0281) | 0.622 (-0.1) | 1.3 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 20561 (-2586) | 3977 (+0) | 16584 (-2586) | 0.193 (+0.0214) | 0.807 (-0.0214) | 0.646 (-0.0818) | 1.25 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 15678 (-2514) | 3111 (+0) | 12567 (-2514) | 0.198 (+0.0274) | 0.802 (-0.0274) | 0.63 (-0.101) | 1.28 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 15152 (-2555) | 2827 (+0) | 12325 (-2555) | 0.187 (+0.0266) | 0.813 (-0.0266) | 0.67 (-0.113) | 1.23 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 6444 (-669) | 1227 (+0) | 5217 (-669) | 0.19 (+0.0174) | 0.81 (-0.0174) | 0.656 (-0.0685) | 1.4 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 6101 (-787) | 1242 (+0) | 4859 (-787) | 0.204 (+0.0236) | 0.796 (-0.0236) | 0.614 (-0.079) | 1.32 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 7375 (-710) | 1423 (+0) | 5952 (-710) | 0.193 (+0.0169) | 0.807 (-0.0169) | 0.648 (-0.0622) | 1.42 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 14919 (-2100) | 2819 (+0) | 12100 (-2100) | 0.189 (+0.023) | 0.811 (-0.023) | 0.662 (-0.0935) | 1.37 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 12749 (-1510) | 2388 (+0) | 10361 (-1510) | 0.187 (+0.0203) | 0.813 (-0.0203) | 0.667 (-0.0787) | 1.38 |
