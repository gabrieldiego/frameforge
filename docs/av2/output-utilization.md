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

## 2026-06-25 AV2 4:2:0 Bubble Rate Optimization

Baseline and current sources:

- Baseline Git SHA: `31bb9321589844a4615d8dd87fe96ef6b54f43ed`
- Current validated source Git SHA: `34e1dca8f313dd433452ca27fb81d858d90e1617`
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
| `screenshot-sweep-444` | 64 | 749352 (+0) | 414156 (+0) | 93669 (+0) | 320487 (+0) | 0.226 (+0.000168) | 0.774 (-0.000168) | 0.553 (-0.000314) | 4.99 |
| `screenshot-multictu-444` | 10 | 562104 (+0) | 346387 (+0) | 70263 (+0) | 276124 (+0) | 0.203 (-0.000155) | 0.797 (+0.000155) | 0.616 (+0.000233) | 3.77 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 109947 (-5454) | 22808 (+0) | 87139 (-5454) | 0.207 (+0.00945) | 0.793 (-0.00945) | 0.603 (-0.0294) | 1.33 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 114167 (-6055) | 23282 (+0) | 90885 (-6055) | 0.204 (+0.00993) | 0.796 (-0.00993) | 0.613 (-0.032) | 1.24 |

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
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 286 (+0) | 43 (+0) | 243 (+0) | 0.15 (+0.00035) | 0.85 (-0.00035) | 0.831 (+0.000395) | 4.47 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 922 (+0) | 248 (+0) | 674 (+0) | 0.269 (-1.95e-05) | 0.731 (+1.95e-05) | 0.465 (-0.000282) | 7.2 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 527 (+0) | 52 (+0) | 475 (+0) | 0.0987 (-2.83e-05) | 0.901 (+0.000328) | 1.27 (-0.00317) | 2.74 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 737 (+0) | 92 (+0) | 645 (+0) | 0.125 (-0.00017) | 0.875 (+0.00017) | 1 (+0.00136) | 2.88 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 776 (+0) | 60 (+0) | 716 (+0) | 0.0773 (+1.96e-05) | 0.923 (-0.00032) | 1.62 (-0.00333) | 2.42 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 876 (+0) | 65 (+0) | 811 (+0) | 0.0742 (+9.13e-07) | 0.926 (-0.000201) | 1.68 (+0.00462) | 2.28 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 3683 (+0) | 854 (+0) | 2829 (+0) | 0.232 (-0.000124) | 0.768 (+0.000124) | 0.539 (+8.08e-05) | 8.22 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6960 (+0) | 4009 (+0) | 870 (+0) | 3139 (+0) | 0.217 (+1.17e-05) | 0.783 (-1.17e-05) | 0.576 (+5.75e-06) | 7.83 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 900 (+0) | 220 (+0) | 680 (+0) | 0.244 (+0.000444) | 0.756 (-0.000444) | 0.511 (+0.000364) | 7.03 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4880 (+0) | 2186 (+0) | 610 (+0) | 1576 (+0) | 0.279 (+4.85e-05) | 0.721 (-4.85e-05) | 0.448 (-4.92e-05) | 8.54 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (+0) | 880 (+0) | 63 (+0) | 817 (+0) | 0.0716 (-9.09e-06) | 0.928 (+0.000409) | 1.75 (-0.00397) | 2.29 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 552 (+0) | 1015 (+0) | 69 (+0) | 946 (+0) | 0.068 (-1.97e-05) | 0.932 (+1.97e-05) | 1.84 (-0.00123) | 1.98 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9208 (+0) | 5157 (+0) | 1151 (+0) | 4006 (+0) | 0.223 (+0.000192) | 0.777 (-0.000192) | 0.56 (+5.65e-05) | 8.06 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 704 (+0) | 1519 (+0) | 88 (+0) | 1431 (+0) | 0.0579 (+3.29e-05) | 0.942 (+6.71e-05) | 2.16 (-0.00233) | 1.98 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10312 (+0) | 6232 (+0) | 1289 (+0) | 4943 (+0) | 0.207 (-0.000164) | 0.793 (+0.000164) | 0.604 (+0.000344) | 6.96 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 824 (+0) | 1956 (+0) | 103 (+0) | 1853 (+0) | 0.0527 (-4.15e-05) | 0.947 (+0.000342) | 2.37 (+0.00379) | 1.91 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3632 (+0) | 1793 (+0) | 454 (+0) | 1339 (+0) | 0.253 (+0.000207) | 0.747 (-0.000207) | 0.494 (-0.000333) | 9.34 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 1658 (+0) | 334 (+0) | 1324 (+0) | 0.201 (+0.000448) | 0.799 (-0.000448) | 0.621 (-0.000491) | 4.32 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+0) | 3562 (+0) | 881 (+0) | 2681 (+0) | 0.247 (+0.000333) | 0.753 (-0.000333) | 0.505 (+0.000392) | 6.18 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 7023 (+0) | 1961 (+0) | 5062 (+0) | 0.279 (+0.000225) | 0.721 (-0.000225) | 0.448 (-0.000333) | 9.14 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15256 (+0) | 6865 (+0) | 1907 (+0) | 4958 (+0) | 0.278 (-0.000214) | 0.722 (+0.000214) | 0.45 (-1.31e-05) | 7.15 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 1704 (+0) | 85 (+0) | 1619 (+0) | 0.0499 (-1.74e-05) | 0.95 (+0.000117) | 2.51 (-0.00412) | 1.48 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 2012 (+0) | 90 (+0) | 1922 (+0) | 0.0447 (+3.16e-05) | 0.955 (+0.000268) | 2.79 (+0.00444) | 1.5 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 21472 (+0) | 11515 (+0) | 2684 (+0) | 8831 (+0) | 0.233 (+8.73e-05) | 0.767 (-8.73e-05) | 0.536 (+0.00028) | 7.5 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 1627 (+0) | 397 (+0) | 1230 (+0) | 0.244 (+7.38e-06) | 0.756 (-7.38e-06) | 0.512 (+0.00028) | 6.36 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1384 (+0) | 1377 (+0) | 173 (+0) | 1204 (+0) | 0.126 (-0.000365) | 0.874 (+0.000365) | 0.995 (-5.78e-05) | 2.69 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1440 (+0) | 1683 (+0) | 180 (+0) | 1503 (+0) | 0.107 (-4.81e-05) | 0.893 (+4.81e-05) | 1.17 (-0.00125) | 2.19 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11816 (+0) | 5659 (+0) | 1477 (+0) | 4182 (+0) | 0.261 (+1.77e-07) | 0.739 (-1.77e-07) | 0.479 (-7.31e-05) | 5.53 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 1909 (+0) | 86 (+0) | 1823 (+0) | 0.045 (+4.98e-05) | 0.955 (-4.98e-05) | 2.77 (+0.00471) | 1.49 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20232 (+0) | 11246 (+0) | 2529 (+0) | 8717 (+0) | 0.225 (-0.00012) | 0.775 (+0.00012) | 0.556 (-0.000148) | 7.32 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26072 (+0) | 13507 (+0) | 3259 (+0) | 10248 (+0) | 0.241 (+0.000282) | 0.759 (-0.000282) | 0.518 (+6.54e-05) | 7.54 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 2683 (+0) | 107 (+0) | 2576 (+0) | 0.0399 (-1.93e-05) | 0.96 (+0.000119) | 3.13 (+0.00435) | 1.31 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 2826 (+0) | 757 (+0) | 2069 (+0) | 0.268 (-0.00013) | 0.732 (+0.00013) | 0.467 (-0.000355) | 8.83 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14504 (+0) | 6415 (+0) | 1813 (+0) | 4602 (+0) | 0.283 (-0.000381) | 0.717 (+0.000381) | 0.442 (+0.000292) | 10 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1296 (+0) | 1982 (+0) | 162 (+0) | 1820 (+0) | 0.0817 (+3.56e-05) | 0.918 (+0.000264) | 1.53 (-0.000679) | 2.06 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21328 (+0) | 10428 (+0) | 2666 (+0) | 7762 (+0) | 0.256 (-0.000342) | 0.744 (+0.000342) | 0.489 (-6.53e-05) | 8.15 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22824 (+0) | 11110 (+0) | 2853 (+0) | 8257 (+0) | 0.257 (-0.000204) | 0.743 (+0.000204) | 0.487 (-0.000232) | 6.94 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1712 (+0) | 2988 (+0) | 214 (+0) | 2774 (+0) | 0.0716 (+1.98e-05) | 0.928 (+0.00038) | 1.75 (-0.00467) | 1.56 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19224 (+0) | 11054 (+0) | 2403 (+0) | 8651 (+0) | 0.217 (+0.000387) | 0.783 (-0.000387) | 0.575 (+1.04e-05) | 4.93 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 3291 (+0) | 143 (+0) | 3148 (+0) | 0.0435 (-4.82e-05) | 0.957 (-0.000452) | 2.88 (-0.00325) | 1.29 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 640 (+0) | 1002 (+0) | 80 (+0) | 922 (+0) | 0.0798 (+4.03e-05) | 0.92 (+0.00016) | 1.57 (-0.00438) | 2.61 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 17104 (+0) | 8228 (+0) | 2138 (+0) | 6090 (+0) | 0.26 (-0.000156) | 0.74 (+0.000156) | 0.481 (+5.71e-05) | 10.7 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14712 (+0) | 7551 (+0) | 1839 (+0) | 5712 (+0) | 0.244 (-0.000456) | 0.756 (+0.000456) | 0.513 (+0.000254) | 6.55 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15952 (+0) | 8320 (+0) | 1994 (+0) | 6326 (+0) | 0.24 (-0.000337) | 0.76 (+0.000337) | 0.522 (-0.000435) | 5.42 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31720 (+0) | 14817 (+0) | 3965 (+0) | 10852 (+0) | 0.268 (-0.000402) | 0.732 (+0.000402) | 0.467 (+0.000119) | 7.72 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 2920 (+0) | 110 (+0) | 2810 (+0) | 0.0377 (-2.88e-05) | 0.962 (+0.000329) | 3.32 (-0.00182) | 1.27 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10856 (+0) | 9338 (+0) | 1357 (+0) | 7981 (+0) | 0.145 (+0.00032) | 0.855 (-0.00032) | 0.86 (+0.000169) | 3.47 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 3804 (+0) | 155 (+0) | 3649 (+0) | 0.0407 (+4.66e-05) | 0.959 (+0.000253) | 3.07 (-0.00226) | 1.24 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 3499 (+0) | 894 (+0) | 2605 (+0) | 0.256 (-0.000498) | 0.744 (+0.000498) | 0.489 (+0.000234) | 7.81 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9600 (+0) | 5394 (+0) | 1200 (+0) | 4194 (+0) | 0.222 (+0.000469) | 0.778 (-0.000469) | 0.562 (-0.000125) | 6.02 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11736 (+0) | 6815 (+0) | 1467 (+0) | 5348 (+0) | 0.215 (+0.00026) | 0.785 (-0.00026) | 0.581 (-0.000308) | 5.07 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18064 (+0) | 9544 (+0) | 2258 (+0) | 7286 (+0) | 0.237 (-0.000412) | 0.763 (+0.000412) | 0.528 (+0.000344) | 5.33 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 38912 (+0) | 18567 (+0) | 4864 (+0) | 13703 (+0) | 0.262 (-2.98e-05) | 0.738 (+2.98e-05) | 0.477 (+0.000154) | 8.29 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22672 (+0) | 12314 (+0) | 2834 (+0) | 9480 (+0) | 0.23 (+0.000145) | 0.77 (-0.000145) | 0.543 (+0.000137) | 4.58 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56384 (+0) | 26683 (+0) | 7048 (+0) | 19635 (+0) | 0.264 (+0.000138) | 0.736 (-0.000138) | 0.473 (+0.000237) | 8.51 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 27056 (+0) | 14820 (+0) | 3382 (+0) | 11438 (+0) | 0.228 (+0.000205) | 0.772 (-0.000205) | 0.548 (-0.000247) | 4.14 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5568 (+0) | 3168 (+0) | 696 (+0) | 2472 (+0) | 0.22 (-0.000303) | 0.78 (+0.000303) | 0.569 (-3.45e-05) | 6.19 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 17248 (+0) | 8247 (+0) | 2156 (+0) | 6091 (+0) | 0.261 (+0.000428) | 0.739 (-0.000428) | 0.478 (+0.000142) | 8.05 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13032 (+0) | 7267 (+0) | 1629 (+0) | 5638 (+0) | 0.224 (+0.000164) | 0.776 (-0.000164) | 0.558 (-0.000373) | 4.73 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32824 (+0) | 15462 (+0) | 4103 (+0) | 11359 (+0) | 0.265 (+0.00036) | 0.735 (-0.00036) | 0.471 (+5.78e-05) | 7.55 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2064 (+0) | 3900 (+0) | 258 (+0) | 3642 (+0) | 0.0662 (-4.62e-05) | 0.934 (-0.000154) | 1.89 (-0.000465) | 1.52 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49072 (+0) | 23450 (+0) | 6134 (+0) | 17316 (+0) | 0.262 (-0.000422) | 0.738 (+0.000422) | 0.478 (-0.000131) | 7.63 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2536 (+0) | 5250 (+0) | 317 (+0) | 4933 (+0) | 0.0604 (-1.9e-05) | 0.94 (-0.000381) | 2.07 (+0.000189) | 1.46 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74392 (+0) | 36218 (+0) | 9299 (+0) | 26919 (+0) | 0.257 (-0.000249) | 0.743 (+0.000249) | 0.487 (-0.000147) | 8.84 |

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
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 85944 (+0) | 46880 (+0) | 10743 (+0) | 36137 (+0) | 0.229 (+0.00016) | 0.771 (-0.00016) | 0.545 (+0.000471) | 5.72 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 42560 (+0) | 27191 (+0) | 5320 (+0) | 21871 (+0) | 0.196 (-0.000347) | 0.804 (+0.000347) | 0.639 (-0.000114) | 3.32 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 9784 (+0) | 21634 (+0) | 1223 (+0) | 20411 (+0) | 0.0565 (+3.14e-05) | 0.943 (+0.000469) | 2.21 (+0.00116) | 1.32 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 42200 (+0) | 33388 (+0) | 5275 (+0) | 28113 (+0) | 0.158 (-9.11e-06) | 0.842 (+9.11e-06) | 0.791 (+0.000185) | 2.72 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105584 (+0) | 58312 (+0) | 13198 (+0) | 45114 (+0) | 0.226 (+0.000334) | 0.774 (-0.000334) | 0.552 (+0.000281) | 4.75 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57192 (+0) | 30246 (+0) | 7149 (+0) | 23097 (+0) | 0.236 (+0.000362) | 0.764 (-0.000362) | 0.529 (-0.00015) | 6.56 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 5834 (+0) | 208 (+0) | 5626 (+0) | 0.0357 (-4.69e-05) | 0.964 (+0.000347) | 3.51 (-0.00399) | 1.27 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2984 (+0) | 7685 (+0) | 373 (+0) | 7312 (+0) | 0.0485 (+3.61e-05) | 0.951 (+0.000464) | 2.58 (-0.0046) | 1.48 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136424 (+0) | 69807 (+0) | 17053 (+0) | 52754 (+0) | 0.244 (+0.000288) | 0.756 (-0.000288) | 0.512 (-0.000309) | 6.42 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 77768 (+0) | 45410 (+0) | 9721 (+0) | 35689 (+0) | 0.214 (+7.18e-05) | 0.786 (-7.18e-05) | 0.584 (-8.37e-05) | 4.93 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.207 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0133 |
| Frame reader sample issue | 0.57 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
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
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (+0) | 191 (-5) | 38 (+0) | 153 (-5) | 0.199 (+0.00495) | 0.801 (-0.00495) | 0.628 (-0.0167) | 2.98 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 257 (-11) | 57 (+0) | 200 (-11) | 0.222 (+0.00879) | 0.778 (-0.00879) | 0.564 (-0.0244) | 2.01 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 360 (-14) | 80 (+0) | 280 (-14) | 0.222 (+0.00822) | 0.778 (-0.00822) | 0.562 (-0.0215) | 1.88 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 429 (-17) | 103 (+0) | 326 (-17) | 0.24 (+0.00909) | 0.76 (-0.00909) | 0.521 (-0.0204) | 1.68 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 549 (-20) | 122 (+0) | 427 (-20) | 0.222 (+0.00822) | 0.778 (-0.00822) | 0.562 (-0.0205) | 1.72 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 583 (-27) | 129 (+0) | 454 (-27) | 0.221 (+0.0103) | 0.779 (-0.0103) | 0.565 (-0.0261) | 1.52 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 699 (-30) | 155 (+0) | 544 (-30) | 0.222 (+0.00875) | 0.778 (-0.00875) | 0.564 (-0.0243) | 1.56 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 750 (-34) | 174 (+0) | 576 (-34) | 0.232 (+0.01) | 0.768 (-0.01) | 0.539 (-0.0242) | 1.46 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 253 (-13) | 42 (+0) | 211 (-13) | 0.166 (+0.00801) | 0.834 (-0.00801) | 0.753 (-0.039) | 1.98 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 418 (-17) | 93 (+0) | 325 (-17) | 0.222 (+0.00849) | 0.778 (-0.00849) | 0.562 (-0.0232) | 1.63 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 575 (-27) | 114 (+0) | 461 (-27) | 0.198 (+0.00926) | 0.802 (-0.00926) | 0.63 (-0.0295) | 1.5 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 697 (-35) | 152 (+0) | 545 (-35) | 0.218 (+0.0101) | 0.782 (-0.0101) | 0.573 (-0.0288) | 1.36 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 929 (-38) | 193 (+0) | 736 (-38) | 0.208 (+0.00775) | 0.792 (-0.00775) | 0.602 (-0.0243) | 1.45 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 1029 (-47) | 222 (+0) | 807 (-47) | 0.216 (+0.00974) | 0.784 (-0.00974) | 0.579 (-0.0266) | 1.34 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 1243 (-53) | 261 (+0) | 982 (-53) | 0.21 (+0.00898) | 0.79 (-0.00898) | 0.595 (-0.0257) | 1.39 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 1323 (-65) | 292 (+0) | 1031 (-65) | 0.221 (+0.0107) | 0.779 (-0.0107) | 0.566 (-0.0276) | 1.29 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 368 (-15) | 66 (+0) | 302 (-15) | 0.179 (+0.00735) | 0.821 (-0.00735) | 0.697 (-0.028) | 1.92 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 575 (-28) | 122 (+0) | 453 (-28) | 0.212 (+0.0102) | 0.788 (-0.0102) | 0.589 (-0.0289) | 1.5 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 832 (-40) | 163 (+0) | 669 (-40) | 0.196 (+0.00891) | 0.804 (-0.00891) | 0.638 (-0.031) | 1.44 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 976 (-55) | 204 (+0) | 772 (-55) | 0.209 (+0.011) | 0.791 (-0.011) | 0.598 (-0.034) | 1.27 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 1349 (-57) | 275 (+0) | 1074 (-57) | 0.204 (+0.00785) | 0.796 (-0.00785) | 0.613 (-0.0258) | 1.41 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 1526 (-69) | 325 (+0) | 1201 (-69) | 0.213 (+0.00898) | 0.787 (-0.00898) | 0.587 (-0.0261) | 1.32 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 1833 (-82) | 379 (+0) | 1454 (-82) | 0.207 (+0.00876) | 0.793 (-0.00876) | 0.605 (-0.0274) | 1.36 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 2023 (-96) | 448 (+0) | 1575 (-96) | 0.221 (+0.0105) | 0.779 (-0.0105) | 0.564 (-0.0265) | 1.32 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 440 (-19) | 75 (+0) | 365 (-19) | 0.17 (+0.00745) | 0.83 (-0.00745) | 0.733 (-0.0317) | 1.72 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 716 (-41) | 149 (+0) | 567 (-41) | 0.208 (+0.0111) | 0.792 (-0.0111) | 0.601 (-0.0343) | 1.4 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 1057 (-53) | 200 (+0) | 857 (-53) | 0.189 (+0.00921) | 0.811 (-0.00921) | 0.661 (-0.0334) | 1.38 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 1300 (-71) | 279 (+0) | 1021 (-71) | 0.215 (+0.0106) | 0.785 (-0.0106) | 0.582 (-0.0316) | 1.27 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 1784 (-81) | 369 (+0) | 1415 (-81) | 0.207 (+0.00884) | 0.793 (-0.00884) | 0.604 (-0.0277) | 1.39 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 1978 (-99) | 418 (+0) | 1560 (-99) | 0.211 (+0.0103) | 0.789 (-0.0103) | 0.592 (-0.0295) | 1.29 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 2386 (-112) | 489 (+0) | 1897 (-112) | 0.205 (+0.00895) | 0.795 (-0.00895) | 0.61 (-0.0291) | 1.33 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 2595 (-127) | 568 (+0) | 2027 (-127) | 0.219 (+0.00988) | 0.781 (-0.00988) | 0.571 (-0.0279) | 1.27 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 554 (-25) | 95 (+0) | 459 (-25) | 0.171 (+0.00748) | 0.829 (-0.00748) | 0.729 (-0.0331) | 1.73 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 908 (-47) | 191 (+0) | 717 (-47) | 0.21 (+0.0104) | 0.79 (-0.0104) | 0.594 (-0.0308) | 1.42 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 1317 (-67) | 248 (+0) | 1069 (-67) | 0.188 (+0.00931) | 0.812 (-0.00931) | 0.664 (-0.0342) | 1.37 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 1611 (-90) | 344 (+0) | 1267 (-90) | 0.214 (+0.0115) | 0.786 (-0.0115) | 0.585 (-0.0326) | 1.26 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 2162 (-101) | 433 (+0) | 1729 (-101) | 0.2 (+0.00928) | 0.8 (-0.00928) | 0.624 (-0.0289) | 1.35 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 2541 (-122) | 552 (+0) | 1989 (-122) | 0.217 (+0.0102) | 0.783 (-0.0102) | 0.575 (-0.0276) | 1.32 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 2979 (-142) | 612 (+0) | 2367 (-142) | 0.205 (+0.00944) | 0.795 (-0.00944) | 0.608 (-0.0285) | 1.33 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 3207 (-172) | 695 (+0) | 2512 (-172) | 0.217 (+0.0107) | 0.783 (-0.0107) | 0.577 (-0.0312) | 1.25 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 668 (-29) | 121 (+0) | 547 (-29) | 0.181 (+0.00714) | 0.819 (-0.00714) | 0.69 (-0.0299) | 1.74 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 1081 (-60) | 228 (+0) | 853 (-60) | 0.211 (+0.0109) | 0.789 (-0.0109) | 0.593 (-0.0333) | 1.41 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 1535 (-76) | 285 (+0) | 1250 (-76) | 0.186 (+0.00867) | 0.814 (-0.00867) | 0.673 (-0.0338) | 1.33 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 1879 (-109) | 394 (+0) | 1485 (-109) | 0.21 (+0.0117) | 0.79 (-0.0117) | 0.596 (-0.0349) | 1.22 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 2567 (-121) | 513 (+0) | 2054 (-121) | 0.2 (+0.00884) | 0.8 (-0.00884) | 0.625 (-0.0295) | 1.34 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 2948 (-141) | 627 (+0) | 2321 (-141) | 0.213 (+0.00969) | 0.787 (-0.00969) | 0.588 (-0.0283) | 1.28 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 3544 (-171) | 722 (+0) | 2822 (-171) | 0.204 (+0.00972) | 0.796 (-0.00972) | 0.614 (-0.0294) | 1.32 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 3807 (-197) | 814 (+0) | 2993 (-197) | 0.214 (+0.0108) | 0.786 (-0.0108) | 0.585 (-0.0304) | 1.24 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 756 (-35) | 134 (+0) | 622 (-35) | 0.177 (+0.00825) | 0.823 (-0.00825) | 0.705 (-0.0328) | 1.69 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 1232 (-66) | 259 (+0) | 973 (-66) | 0.21 (+0.0102) | 0.79 (-0.0102) | 0.595 (-0.0314) | 1.38 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 1794 (-98) | 335 (+0) | 1459 (-98) | 0.187 (+0.00973) | 0.813 (-0.00973) | 0.669 (-0.0366) | 1.33 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 2181 (-129) | 461 (+0) | 1720 (-129) | 0.211 (+0.0114) | 0.789 (-0.0114) | 0.591 (-0.0346) | 1.22 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 2954 (-140) | 587 (+0) | 2367 (-140) | 0.199 (+0.00871) | 0.801 (-0.00871) | 0.629 (-0.03) | 1.32 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 3468 (-170) | 743 (+0) | 2725 (-170) | 0.214 (+0.0102) | 0.786 (-0.0102) | 0.583 (-0.0286) | 1.29 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 4123 (-198) | 838 (+0) | 3285 (-198) | 0.203 (+0.00925) | 0.797 (-0.00925) | 0.615 (-0.03) | 1.31 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 4426 (-232) | 950 (+0) | 3476 (-232) | 0.215 (+0.0106) | 0.785 (-0.0106) | 0.582 (-0.0306) | 1.23 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 833 (-43) | 148 (+0) | 685 (-43) | 0.178 (+0.00867) | 0.822 (-0.00867) | 0.704 (-0.0365) | 1.63 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 1355 (-83) | 280 (+0) | 1075 (-83) | 0.207 (+0.0116) | 0.793 (-0.0116) | 0.605 (-0.0371) | 1.32 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2066 (-107) | 394 (+0) | 1672 (-107) | 0.191 (+0.00971) | 0.809 (-0.00971) | 0.655 (-0.0335) | 1.35 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 2452 (-148) | 514 (+0) | 1938 (-148) | 0.21 (+0.0116) | 0.79 (-0.0116) | 0.596 (-0.0357) | 1.2 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 3344 (-163) | 665 (+0) | 2679 (-163) | 0.199 (+0.00886) | 0.801 (-0.00886) | 0.629 (-0.0304) | 1.31 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 3859 (-196) | 812 (+0) | 3047 (-196) | 0.21 (+0.0104) | 0.79 (-0.0104) | 0.594 (-0.0299) | 1.26 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 4724 (-220) | 968 (+0) | 3756 (-220) | 0.205 (+0.00891) | 0.795 (-0.00891) | 0.61 (-0.028) | 1.32 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 5049 (-258) | 1090 (+0) | 3959 (-258) | 0.216 (+0.0109) | 0.784 (-0.0109) | 0.579 (-0.03) | 1.23 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.204 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0128 |
| Frame reader sample issue | 0.599 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
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
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 10038 (-538) | 2123 (+0) | 7915 (-538) | 0.211 (+0.0105) | 0.789 (-0.0105) | 0.591 (-0.032) | 1.23 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 10150 (-517) | 2145 (+0) | 8005 (-517) | 0.211 (+0.0103) | 0.789 (-0.0103) | 0.591 (-0.0305) | 1.24 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 19481 (-1080) | 3977 (+0) | 15504 (-1080) | 0.204 (+0.0111) | 0.796 (-0.0111) | 0.612 (-0.0337) | 1.19 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 14885 (-793) | 3111 (+0) | 11774 (-793) | 0.209 (+0.011) | 0.791 (-0.011) | 0.598 (-0.0319) | 1.21 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 14286 (-866) | 2827 (+0) | 11459 (-866) | 0.198 (+0.0109) | 0.802 (-0.0109) | 0.632 (-0.0383) | 1.16 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 6135 (-309) | 1227 (+0) | 4908 (-309) | 0.2 (+0.01) | 0.8 (-0.01) | 0.625 (-0.031) | 1.33 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 5810 (-291) | 1242 (+0) | 4568 (-291) | 0.214 (+0.00977) | 0.786 (-0.00977) | 0.585 (-0.0293) | 1.26 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 7041 (-334) | 1423 (+0) | 5618 (-334) | 0.202 (+0.0091) | 0.798 (-0.0091) | 0.618 (-0.0295) | 1.36 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 14195 (-724) | 2819 (+0) | 11376 (-724) | 0.199 (+0.00959) | 0.801 (-0.00959) | 0.629 (-0.0326) | 1.3 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 12146 (-603) | 2388 (+0) | 9758 (-603) | 0.197 (+0.00961) | 0.803 (-0.00961) | 0.636 (-0.0312) | 1.32 |
