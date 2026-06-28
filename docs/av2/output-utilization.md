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

## AV2 Packet Flow Timing Check

Baseline and current sources:

- Baseline Git SHA: `151e8276f495b56c9af0376fde7fb11105921f7f`
- Current validated source Git SHA: `509b74f7670b9bfff61209f0779c12e256b00f07`
- Delta columns compare against the previous documented AV2 output-utilization
  checkpoint where the same vector or aggregate was present.

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/reference-decoder checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: not rerun for this checkpoint.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 64 | 745912 (-3440) | 403995 (-10161) | 93239 (-430) | 310756 (-9731) | 0.231 (+0.00479) | 0.769 (-0.00479) | 0.542 (-0.0114) | 4.87 |
| `screenshot-multictu-444` | 10 | 559064 (-3040) | 337769 (-8618) | 69883 (-380) | 267886 (-8238) | 0.207 (+0.0039) | 0.793 (-0.0039) | 0.604 (-0.0118) | 3.68 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 109947 (+0) | 22808 (+0) | 87139 (+0) | 0.207 (+0.000445) | 0.793 (-0.000445) | 0.603 (-0.000432) | 1.33 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 114167 (+0) | 23282 (+0) | 90885 (+0) | 0.204 (-7.07e-05) | 0.796 (+7.07e-05) | 0.613 (-4.26e-05) | 1.24 |
| `multiframe-smoke` | 4 | 17992 (-2752) | 13544 (-902) | 2249 (-344) | 11295 (-558) | 0.166 (-0.0129) | 0.834 (+0.0129) | 0.753 (+0.0568) | 2.82 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.231 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0145 |
| Frame reader sample issue | 0.474 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.968 |
| Input FIFO nonempty rate | 0.0228 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.951 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.442 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.149 |
| AV2 carry payload bytes/cycle | 16.3 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 294 (+8) | 43 (+0) | 251 (+8) | 0.146 (-0.00374) | 0.854 (+0.00374) | 0.855 (+0.0237) | 4.59 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 889 (-33) | 248 (+0) | 641 (-33) | 0.279 (+0.00997) | 0.721 (-0.00997) | 0.448 (-0.0169) | 6.95 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 408 (-8) | 535 (+8) | 51 (-1) | 484 (+9) | 0.0953 (-0.00337) | 0.905 (+0.00367) | 1.31 (+0.0413) | 2.79 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 737 (+0) | 92 (+0) | 645 (+0) | 0.125 (-0.00017) | 0.875 (+0.00017) | 1 (+0.00136) | 2.88 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 784 (+8) | 60 (+0) | 724 (+8) | 0.0765 (-0.000769) | 0.923 (+0.000469) | 1.63 (+0.0133) | 2.45 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 883 (+7) | 65 (+0) | 818 (+7) | 0.0736 (-0.000587) | 0.926 (+0.000387) | 1.7 (+0.0181) | 2.3 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 3505 (-178) | 854 (+0) | 2651 (-178) | 0.244 (+0.0117) | 0.756 (-0.0117) | 0.513 (-0.026) | 7.82 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (-144) | 3795 (-214) | 852 (-18) | 2943 (-196) | 0.225 (+0.00751) | 0.775 (-0.00751) | 0.557 (-0.0192) | 7.41 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 900 (+0) | 220 (+0) | 680 (+0) | 0.244 (+0.000444) | 0.756 (-0.000444) | 0.511 (+0.000364) | 7.03 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4880 (+0) | 2155 (-31) | 610 (+0) | 1545 (-31) | 0.283 (+0.00406) | 0.717 (-0.00406) | 0.442 (-0.0064) | 8.42 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (+0) | 888 (+8) | 63 (+0) | 825 (+8) | 0.0709 (-0.000654) | 0.929 (+0.00105) | 1.76 (+0.0119) | 2.31 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 552 (+0) | 1022 (+7) | 69 (+0) | 953 (+7) | 0.0675 (-0.000485) | 0.932 (+0.000485) | 1.85 (+0.0114) | 2 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9520 (+312) | 5067 (-90) | 1190 (+39) | 3877 (-129) | 0.235 (+0.0119) | 0.765 (-0.0119) | 0.532 (-0.0278) | 7.92 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 696 (-8) | 1525 (+6) | 87 (-1) | 1438 (+7) | 0.057 (-0.000851) | 0.943 (+0.000951) | 2.19 (+0.0311) | 1.99 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10240 (-72) | 5990 (-242) | 1280 (-9) | 4710 (-233) | 0.214 (+0.00669) | 0.786 (-0.00669) | 0.585 (-0.019) | 6.69 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 824 (+0) | 1964 (+8) | 103 (+0) | 1861 (+8) | 0.0524 (-0.000256) | 0.948 (+0.000556) | 2.38 (+0.0135) | 1.92 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3960 (+328) | 1914 (+121) | 495 (+41) | 1419 (+80) | 0.259 (+0.00562) | 0.741 (-0.00562) | 0.483 (-0.0107) | 9.97 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 1625 (-33) | 334 (+0) | 1291 (-33) | 0.206 (+0.00454) | 0.794 (-0.00454) | 0.608 (-0.0128) | 4.23 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 6768 (-280) | 3438 (-124) | 846 (-35) | 2592 (-89) | 0.246 (-0.000927) | 0.754 (+0.000927) | 0.508 (+0.00298) | 5.97 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 6826 (-197) | 1961 (+0) | 4865 (-197) | 0.287 (+0.00828) | 0.713 (-0.00828) | 0.435 (-0.0129) | 8.89 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15256 (+0) | 6844 (-21) | 1907 (+0) | 4937 (-21) | 0.279 (+0.000638) | 0.721 (-0.000638) | 0.449 (-0.00139) | 7.13 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 1712 (+8) | 85 (+0) | 1627 (+8) | 0.0496 (-0.00025) | 0.95 (+0.00035) | 2.52 (+0.00765) | 1.49 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 2020 (+8) | 90 (+0) | 1930 (+8) | 0.0446 (-0.000146) | 0.955 (+0.000446) | 2.81 (+0.0156) | 1.5 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 21840 (+368) | 11149 (-366) | 2730 (+46) | 8419 (-412) | 0.245 (+0.0119) | 0.755 (-0.0119) | 0.51 (-0.0255) | 7.26 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 1631 (+4) | 397 (+0) | 1234 (+4) | 0.243 (-0.000591) | 0.757 (+0.000591) | 0.514 (+0.00154) | 6.37 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1384 (+0) | 1328 (-49) | 173 (+0) | 1155 (-49) | 0.13 (+0.00427) | 0.87 (-0.00427) | 0.96 (-0.0355) | 2.59 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1440 (+0) | 1679 (-4) | 180 (+0) | 1499 (-4) | 0.107 (+0.000207) | 0.893 (-0.000207) | 1.17 (-0.00403) | 2.19 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11856 (+40) | 5633 (-26) | 1482 (+5) | 4151 (-31) | 0.263 (+0.00209) | 0.737 (-0.00209) | 0.475 (-0.00388) | 5.5 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 680 (-8) | 1916 (+7) | 85 (-1) | 1831 (+8) | 0.0444 (-0.000637) | 0.956 (+0.000637) | 2.82 (+0.0476) | 1.5 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20232 (+0) | 10910 (-336) | 2529 (+0) | 8381 (-336) | 0.232 (+0.00681) | 0.768 (-0.00681) | 0.539 (-0.0168) | 7.1 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26008 (-64) | 12963 (-544) | 3251 (-8) | 9712 (-536) | 0.251 (+0.00979) | 0.749 (-0.00979) | 0.498 (-0.0196) | 7.23 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 2690 (+7) | 107 (+0) | 2583 (+7) | 0.0398 (-0.000123) | 0.96 (+0.000223) | 3.14 (+0.0125) | 1.31 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 2792 (-34) | 757 (+0) | 2035 (-34) | 0.271 (+0.00313) | 0.729 (-0.00313) | 0.461 (-0.00597) | 8.72 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14056 (-448) | 6080 (-335) | 1757 (-56) | 4323 (-279) | 0.289 (+0.00598) | 0.711 (-0.00598) | 0.433 (-0.00944) | 9.5 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1296 (+0) | 1962 (-20) | 162 (+0) | 1800 (-20) | 0.0826 (+0.000869) | 0.917 (-0.000569) | 1.51 (-0.0161) | 2.04 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21368 (+40) | 10080 (-348) | 2671 (+5) | 7409 (-353) | 0.265 (+0.00898) | 0.735 (-0.00898) | 0.472 (-0.0173) | 7.88 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22304 (-520) | 10758 (-352) | 2788 (-65) | 7970 (-287) | 0.259 (+0.00216) | 0.741 (-0.00216) | 0.482 (-0.00466) | 6.72 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1712 (+0) | 2945 (-43) | 214 (+0) | 2731 (-43) | 0.0727 (+0.00107) | 0.927 (-0.000666) | 1.72 (-0.0298) | 1.53 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19400 (+176) | 10681 (-373) | 2425 (+22) | 8256 (-395) | 0.227 (+0.01) | 0.773 (-0.01) | 0.551 (-0.0244) | 4.77 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 3299 (+8) | 143 (+0) | 3156 (+8) | 0.0433 (-0.000154) | 0.957 (-0.000346) | 2.88 (+0.00374) | 1.29 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 640 (+0) | 1012 (+10) | 80 (+0) | 932 (+10) | 0.0791 (-0.000749) | 0.921 (+0.000949) | 1.58 (+0.0112) | 2.64 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 16928 (-176) | 7926 (-302) | 2116 (-22) | 5810 (-280) | 0.267 (+0.00697) | 0.733 (-0.00697) | 0.468 (-0.0128) | 10.3 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14720 (+8) | 7454 (-97) | 1840 (+1) | 5614 (-98) | 0.247 (+0.00285) | 0.753 (-0.00285) | 0.506 (-0.00661) | 6.47 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15896 (-56) | 8100 (-220) | 1987 (-7) | 6113 (-213) | 0.245 (+0.00531) | 0.755 (-0.00531) | 0.51 (-0.0124) | 5.27 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31968 (+248) | 14660 (-157) | 3996 (+31) | 10664 (-188) | 0.273 (+0.00458) | 0.727 (-0.00458) | 0.459 (-0.00842) | 7.64 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 2927 (+7) | 110 (+0) | 2817 (+7) | 0.0376 (-0.000119) | 0.962 (+0.000419) | 3.33 (+0.00614) | 1.27 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10992 (+136) | 9203 (-135) | 1374 (+17) | 7829 (-152) | 0.149 (+0.0043) | 0.851 (-0.0043) | 0.837 (-0.0228) | 3.42 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1232 (-8) | 3810 (+6) | 154 (-1) | 3656 (+7) | 0.0404 (-0.00028) | 0.96 (+0.00058) | 3.09 (+0.0225) | 1.24 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 3460 (-39) | 894 (+0) | 2566 (-39) | 0.258 (+0.00238) | 0.742 (-0.00238) | 0.484 (-0.00522) | 7.72 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9600 (+0) | 5198 (-196) | 1200 (+0) | 3998 (-196) | 0.231 (+0.00886) | 0.769 (-0.00886) | 0.541 (-0.0205) | 5.8 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11744 (+8) | 6703 (-112) | 1468 (+1) | 5235 (-113) | 0.219 (+0.00401) | 0.781 (-0.00401) | 0.571 (-0.0102) | 4.99 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18072 (+8) | 9332 (-212) | 2259 (+1) | 7073 (-213) | 0.242 (+0.00507) | 0.758 (-0.00507) | 0.516 (-0.0116) | 5.21 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 37072 (-1840) | 17624 (-943) | 4634 (-230) | 12990 (-713) | 0.263 (+0.000937) | 0.737 (-0.000937) | 0.475 (-0.0016) | 7.87 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22672 (+0) | 12040 (-274) | 2834 (+0) | 9206 (-274) | 0.235 (+0.00538) | 0.765 (-0.00538) | 0.531 (-0.0119) | 4.48 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56256 (-128) | 26026 (-657) | 7032 (-16) | 18994 (-641) | 0.27 (+0.00619) | 0.73 (-0.00619) | 0.463 (-0.0104) | 8.3 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 26992 (-64) | 14401 (-419) | 3374 (-8) | 11027 (-411) | 0.234 (+0.00629) | 0.766 (-0.00629) | 0.534 (-0.0145) | 4.02 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5568 (+0) | 3149 (-19) | 696 (+0) | 2453 (-19) | 0.221 (+0.00102) | 0.779 (-0.00102) | 0.566 (-0.00345) | 6.15 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 16512 (-736) | 7820 (-427) | 2064 (-92) | 5756 (-335) | 0.264 (+0.00294) | 0.736 (-0.00294) | 0.474 (-0.00441) | 7.64 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13016 (-16) | 7170 (-97) | 1627 (-2) | 5543 (-95) | 0.227 (+0.00292) | 0.773 (-0.00292) | 0.551 (-0.00714) | 4.67 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32616 (-208) | 15047 (-415) | 4077 (-26) | 10970 (-389) | 0.271 (+0.00595) | 0.729 (-0.00595) | 0.461 (-0.00966) | 7.35 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2064 (+0) | 3900 (+0) | 258 (+0) | 3642 (+0) | 0.0662 (-4.62e-05) | 0.934 (-0.000154) | 1.89 (-0.000465) | 1.52 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 48936 (-136) | 22868 (-582) | 6117 (-17) | 16751 (-565) | 0.267 (+0.00549) | 0.733 (-0.00549) | 0.467 (-0.0107) | 7.44 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2600 (+64) | 5263 (+13) | 325 (+8) | 4938 (+5) | 0.0618 (+0.00135) | 0.938 (-0.00175) | 2.02 (-0.0458) | 1.47 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74136 (-256) | 35094 (-1124) | 9267 (-32) | 25827 (-1092) | 0.264 (+0.00706) | 0.736 (-0.00706) | 0.473 (-0.0136) | 8.57 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.207 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0129 |
| Frame reader sample issue | 0.479 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.973 |
| Input FIFO nonempty rate | 0.0358 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.959 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.475 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.145 |
| AV2 carry payload bytes/cycle | 8.25 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 86600 (+656) | 45965 (-915) | 10825 (+82) | 35140 (-997) | 0.236 (+0.00651) | 0.764 (-0.00651) | 0.531 (-0.0142) | 5.61 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 42152 (-408) | 26330 (-861) | 5269 (-51) | 21061 (-810) | 0.2 (+0.00411) | 0.8 (-0.00411) | 0.625 (-0.0144) | 3.21 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 9800 (+16) | 21541 (-93) | 1225 (+2) | 20316 (-95) | 0.0569 (+0.000368) | 0.943 (+0.000132) | 2.2 (-0.0119) | 1.31 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 41992 (-208) | 32806 (-582) | 5249 (-26) | 27557 (-556) | 0.16 (+0.002) | 0.84 (-0.002) | 0.781 (-0.00976) | 2.67 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 102856 (-2728) | 55851 (-2461) | 12857 (-341) | 42994 (-2120) | 0.23 (+0.0042) | 0.77 (-0.0042) | 0.543 (-0.009) | 4.55 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57208 (+16) | 29488 (-758) | 7151 (+2) | 22337 (-760) | 0.243 (+0.00651) | 0.757 (-0.00651) | 0.515 (-0.0135) | 6.4 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 5848 (+14) | 208 (+0) | 5640 (+14) | 0.0356 (-0.000132) | 0.964 (+0.000432) | 3.51 (+0.00442) | 1.27 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2976 (-8) | 7718 (+33) | 372 (-1) | 7346 (+34) | 0.0482 (-0.000301) | 0.952 (+0.000801) | 2.59 (+0.0134) | 1.49 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136856 (+432) | 68387 (-1420) | 17107 (+54) | 51280 (-1474) | 0.25 (+0.00615) | 0.75 (-0.00615) | 0.5 (-0.0123) | 6.29 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 76960 (-808) | 43835 (-1575) | 9620 (-101) | 34215 (-1474) | 0.219 (+0.00546) | 0.781 (-0.00546) | 0.57 (-0.0144) | 4.76 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.207 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0133 |
| Frame reader sample issue | 0.57 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0 |
| AV2 carry payload bytes/cycle | 16.6 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (+0) | 191 (+0) | 38 (+0) | 153 (+0) | 0.199 (-4.71e-05) | 0.801 (+4.71e-05) | 0.628 (+0.000289) | 2.98 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 257 (+0) | 57 (+0) | 200 (+0) | 0.222 (-0.00021) | 0.778 (+0.00021) | 0.564 (-0.000404) | 2.01 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 360 (+0) | 80 (+0) | 280 (+0) | 0.222 (+0.000222) | 0.778 (-0.000222) | 0.562 (+0.0005) | 1.88 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 429 (+0) | 103 (+0) | 326 (+0) | 0.24 (+9.32e-05) | 0.76 (-9.32e-05) | 0.521 (-0.000369) | 1.68 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 549 (+0) | 122 (+0) | 427 (+0) | 0.222 (+0.000222) | 0.778 (-0.000222) | 0.562 (+0.0005) | 1.72 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 583 (+0) | 129 (+0) | 454 (+0) | 0.221 (+0.000269) | 0.779 (-0.000269) | 0.565 (-7.75e-05) | 1.52 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 699 (+0) | 155 (+0) | 544 (+0) | 0.222 (-0.000255) | 0.778 (+0.000255) | 0.564 (-0.00029) | 1.56 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 750 (+0) | 174 (+0) | 576 (+0) | 0.232 (+0) | 0.768 (+0) | 0.539 (-0.000207) | 1.46 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 253 (+0) | 42 (+0) | 211 (+0) | 0.166 (+7.91e-06) | 0.834 (-7.91e-06) | 0.753 (-2.38e-05) | 1.98 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 418 (+0) | 93 (+0) | 325 (+0) | 0.222 (+0.000488) | 0.778 (-0.000488) | 0.562 (-0.000172) | 1.63 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 575 (+0) | 114 (+0) | 461 (+0) | 0.198 (+0.000261) | 0.802 (-0.000261) | 0.63 (+0.000482) | 1.5 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 697 (+0) | 152 (+0) | 545 (+0) | 0.218 (+7.75e-05) | 0.782 (-7.75e-05) | 0.573 (+0.000191) | 1.36 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 929 (+0) | 193 (+0) | 736 (+0) | 0.208 (-0.00025) | 0.792 (+0.00025) | 0.602 (-0.000316) | 1.45 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 1029 (+0) | 222 (+0) | 807 (+0) | 0.216 (-0.000257) | 0.784 (+0.000257) | 0.579 (+0.000392) | 1.34 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 1243 (+0) | 261 (+0) | 982 (+0) | 0.21 (-2.41e-05) | 0.79 (+2.41e-05) | 0.595 (+0.000307) | 1.39 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 1323 (+0) | 292 (+0) | 1031 (+0) | 0.221 (-0.000289) | 0.779 (+0.000289) | 0.566 (+0.000353) | 1.29 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 368 (+0) | 66 (+0) | 302 (+0) | 0.179 (+0.000348) | 0.821 (-0.000348) | 0.697 (-3.03e-05) | 1.92 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 575 (+0) | 122 (+0) | 453 (+0) | 0.212 (+0.000174) | 0.788 (-0.000174) | 0.589 (+0.000139) | 1.5 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 832 (+0) | 163 (+0) | 669 (+0) | 0.196 (-8.65e-05) | 0.804 (+8.65e-05) | 0.638 (+3.68e-05) | 1.44 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 976 (+0) | 204 (+0) | 772 (+0) | 0.209 (+1.64e-05) | 0.791 (-1.64e-05) | 0.598 (+3.92e-05) | 1.27 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 1349 (+0) | 275 (+0) | 1074 (+0) | 0.204 (-0.000145) | 0.796 (+0.000145) | 0.613 (+0.000182) | 1.41 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 1526 (+0) | 325 (+0) | 1201 (+0) | 0.213 (-2.49e-05) | 0.787 (+2.49e-05) | 0.587 (-7.69e-05) | 1.32 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 1833 (+0) | 379 (+0) | 1454 (+0) | 0.207 (-0.000235) | 0.793 (+0.000235) | 0.605 (-0.000449) | 1.36 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 2023 (+0) | 448 (+0) | 1575 (+0) | 0.221 (+0.000453) | 0.779 (-0.000453) | 0.564 (+0.000453) | 1.32 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 440 (+0) | 75 (+0) | 365 (+0) | 0.17 (+0.000455) | 0.83 (-0.000455) | 0.733 (+0.000333) | 1.72 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 716 (+0) | 149 (+0) | 567 (+0) | 0.208 (+0.000101) | 0.792 (-0.000101) | 0.601 (-0.000329) | 1.4 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 1057 (+0) | 200 (+0) | 857 (+0) | 0.189 (+0.000215) | 0.811 (-0.000215) | 0.661 (-0.000375) | 1.38 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 1300 (+0) | 279 (+0) | 1021 (+0) | 0.215 (-0.000385) | 0.785 (+0.000385) | 0.582 (+0.000437) | 1.27 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 1784 (+0) | 369 (+0) | 1415 (+0) | 0.207 (-0.000161) | 0.793 (+0.000161) | 0.604 (+0.000336) | 1.39 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 1978 (+0) | 418 (+0) | 1560 (+0) | 0.211 (+0.000325) | 0.789 (-0.000325) | 0.592 (-0.000493) | 1.29 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 2386 (+0) | 489 (+0) | 1897 (+0) | 0.205 (-5.45e-05) | 0.795 (+5.45e-05) | 0.61 (-8.18e-05) | 1.33 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 2595 (+0) | 568 (+0) | 2027 (+0) | 0.219 (-0.000118) | 0.781 (+0.000118) | 0.571 (+8.27e-05) | 1.27 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 554 (+0) | 95 (+0) | 459 (+0) | 0.171 (+0.00048) | 0.829 (-0.00048) | 0.729 (-5.26e-05) | 1.73 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 908 (+0) | 191 (+0) | 717 (+0) | 0.21 (+0.000352) | 0.79 (-0.000352) | 0.594 (+0.000241) | 1.42 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 1317 (+0) | 248 (+0) | 1069 (+0) | 0.188 (+0.000307) | 0.812 (-0.000307) | 0.664 (-0.00019) | 1.37 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 1611 (+0) | 344 (+0) | 1267 (+0) | 0.214 (-0.000468) | 0.786 (+0.000468) | 0.585 (+0.000392) | 1.26 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 2162 (+0) | 433 (+0) | 1729 (+0) | 0.2 (+0.000278) | 0.8 (-0.000278) | 0.624 (+0.000134) | 1.35 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 2541 (+0) | 552 (+0) | 1989 (+0) | 0.217 (+0.000237) | 0.783 (-0.000237) | 0.575 (+0.000408) | 1.32 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 2979 (+0) | 612 (+0) | 2367 (+0) | 0.205 (+0.000438) | 0.795 (-0.000438) | 0.608 (+0.000456) | 1.33 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 3207 (+0) | 695 (+0) | 2512 (+0) | 0.217 (-0.000287) | 0.783 (+0.000287) | 0.577 (-0.000201) | 1.25 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 668 (+0) | 121 (+0) | 547 (+0) | 0.181 (+0.000138) | 0.819 (-0.000138) | 0.69 (+8.26e-05) | 1.74 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 1081 (+0) | 228 (+0) | 853 (+0) | 0.211 (-8.42e-05) | 0.789 (+8.42e-05) | 0.593 (-0.000346) | 1.41 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 1535 (+0) | 285 (+0) | 1250 (+0) | 0.186 (-0.000332) | 0.814 (+0.000332) | 0.673 (+0.000246) | 1.33 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 1879 (+0) | 394 (+0) | 1485 (+0) | 0.21 (-0.000314) | 0.79 (+0.000314) | 0.596 (+0.000129) | 1.22 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 2567 (+0) | 513 (+0) | 2054 (+0) | 0.2 (-0.000156) | 0.8 (+0.000156) | 0.625 (+0.000487) | 1.34 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 2948 (+0) | 627 (+0) | 2321 (+0) | 0.213 (-0.000313) | 0.787 (+0.000313) | 0.588 (-0.000281) | 1.28 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 3544 (+0) | 722 (+0) | 2822 (+0) | 0.204 (-0.000275) | 0.796 (+0.000275) | 0.614 (-0.000427) | 1.32 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 3807 (+0) | 814 (+0) | 2993 (+0) | 0.214 (-0.000183) | 0.786 (+0.000183) | 0.585 (-0.000387) | 1.24 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 756 (+0) | 134 (+0) | 622 (+0) | 0.177 (+0.000249) | 0.823 (-0.000249) | 0.705 (+0.000224) | 1.69 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 1232 (+0) | 259 (+0) | 973 (+0) | 0.21 (+0.000227) | 0.79 (-0.000227) | 0.595 (-0.000405) | 1.38 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 1794 (+0) | 335 (+0) | 1459 (+0) | 0.187 (-0.000266) | 0.813 (+0.000266) | 0.669 (+0.000403) | 1.33 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 2181 (+0) | 461 (+0) | 1720 (+0) | 0.211 (+0.000371) | 0.789 (-0.000371) | 0.591 (+0.000377) | 1.22 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 2954 (+0) | 587 (+0) | 2367 (+0) | 0.199 (-0.000286) | 0.801 (+0.000286) | 0.629 (+4.6e-05) | 1.32 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 3468 (+0) | 743 (+0) | 2725 (+0) | 0.214 (+0.000245) | 0.786 (-0.000245) | 0.583 (+0.000445) | 1.29 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 4123 (+0) | 838 (+0) | 3285 (+0) | 0.203 (+0.00025) | 0.797 (-0.00025) | 0.615 (+5.97e-06) | 1.31 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 4426 (+0) | 950 (+0) | 3476 (+0) | 0.215 (-0.000359) | 0.785 (+0.000359) | 0.582 (+0.000368) | 1.23 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 833 (+0) | 148 (+0) | 685 (+0) | 0.178 (-0.000329) | 0.822 (+0.000329) | 0.704 (-0.000453) | 1.63 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 1355 (+0) | 280 (+0) | 1075 (+0) | 0.207 (-0.000358) | 0.793 (+0.000358) | 0.605 (-8.93e-05) | 1.32 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2066 (+0) | 394 (+0) | 1672 (+0) | 0.191 (-0.000293) | 0.809 (+0.000293) | 0.655 (+0.000457) | 1.35 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 2452 (+0) | 514 (+0) | 1938 (+0) | 0.21 (-0.000375) | 0.79 (+0.000375) | 0.596 (+0.000304) | 1.2 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 3344 (+0) | 665 (+0) | 2679 (+0) | 0.199 (-0.000136) | 0.801 (+0.000136) | 0.629 (-0.000429) | 1.31 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 3859 (+0) | 812 (+0) | 3047 (+0) | 0.21 (+0.000417) | 0.79 (-0.000417) | 0.594 (+5.79e-05) | 1.26 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 4724 (+0) | 968 (+0) | 3756 (+0) | 0.205 (-8.89e-05) | 0.795 (+8.89e-05) | 0.61 (+2.07e-05) | 1.32 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 5049 (+0) | 1090 (+0) | 3959 (+0) | 0.216 (-0.000116) | 0.784 (+0.000116) | 0.579 (+1.38e-05) | 1.23 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.204 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0128 |
| Frame reader sample issue | 0.599 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0 |
| AV2 carry payload bytes/cycle | 8.09 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 10038 (+0) | 2123 (+0) | 7915 (+0) | 0.211 (+0.000496) | 0.789 (-0.000496) | 0.591 (+2.68e-05) | 1.23 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 10150 (+0) | 2145 (+0) | 8005 (+0) | 0.211 (+0.00033) | 0.789 (-0.00033) | 0.591 (+0.000492) | 1.24 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 19481 (+0) | 3977 (+0) | 15504 (+0) | 0.204 (+0.000148) | 0.796 (-0.000148) | 0.612 (+0.000302) | 1.19 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 14885 (+0) | 3111 (+0) | 11774 (+0) | 0.209 (+2.35e-06) | 0.791 (-2.35e-06) | 0.598 (+7.94e-05) | 1.21 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 14286 (+0) | 2827 (+0) | 11459 (+0) | 0.198 (-0.000114) | 0.802 (+0.000114) | 0.632 (-0.000323) | 1.16 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 6135 (+0) | 1227 (+0) | 4908 (+0) | 0.2 (+0) | 0.8 (+0) | 0.625 (+0) | 1.33 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 5810 (+0) | 1242 (+0) | 4568 (+0) | 0.214 (-0.000231) | 0.786 (+0.000231) | 0.585 (-0.000258) | 1.26 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 7041 (+0) | 1423 (+0) | 5618 (+0) | 0.202 (+0.000102) | 0.798 (-0.000102) | 0.618 (+0.0005) | 1.36 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 14195 (+0) | 2819 (+0) | 11376 (+0) | 0.199 (-0.000409) | 0.801 (+0.000409) | 0.629 (+0.000434) | 1.3 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 12146 (+0) | 2388 (+0) | 9758 (+0) | 0.197 (-0.000392) | 0.803 (+0.000392) | 0.636 (-0.000217) | 1.32 |

### Multi-Frame Smoke

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.166 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0106 |
| Frame reader sample issue | 0.481 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.984 |
| Input FIFO nonempty rate | 0.0461 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.937 |
| AV2 chroma BDPCM op issue | 0.775 |
| AV2 chroma zero-TXB shortcut rate | 0.494 |
| AV2 luma residual op issue | 0.775 |
| AV2 prefetch useful fraction | 0.244 |
| AV2 carry payload bytes/cycle | 17.1 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| multiframe_black_420_16x16_2f_yuv420p8.yuv | PASS | 1936 (+0) | 950 (+0) | 242 (+0) | 708 (+0) | 0.255 (-0.000263) | 0.745 (+0.000263) | 0.491 (-0.000298) | 1.86 |
| multiframe_black_tall_420_8x24_5f_yuv420p8.yuv | PASS | 3840 (+0) | 2099 (+0) | 480 (+0) | 1619 (+0) | 0.229 (-0.00032) | 0.771 (+0.00032) | 0.547 (-0.000385) | 2.19 |
| multiframe_motion_444_16x8_2f_yuv444p8.yuv | PASS | 1288 (-120) | 972 (-35) | 161 (-15) | 811 (-20) | 0.166 (-0.00936) | 0.834 (+0.00936) | 0.755 (+0.0397) | 3.8 |
| multiframe_motion_wide_444_48x32_2f_yuv444p8.yuv | PASS | 10928 (-2632) | 9523 (-867) | 1366 (-329) | 8157 (-538) | 0.143 (-0.0196) | 0.857 (+0.0196) | 0.871 (+0.105) | 3.1 |
