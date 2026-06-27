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

## 2026-06-26 AV2 Multi-Frame Report Refresh

Baseline and current sources:

- Baseline Git SHA: `34e1dca8f313dd433452ca27fb81d858d90e1617`
- Current validated source Git SHA: `151e8276f495b56c9af0376fde7fb11105921f7f`
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
| `screenshot-sweep-444` | 64 | 749352 (+0) | 414156 (+0) | 93669 (+0) | 320487 (+0) | 0.226 (+0.000168) | 0.774 (-0.000168) | 0.553 (-0.000314) | 4.99 |
| `screenshot-multictu-444` | 10 | 562104 (+0) | 346387 (+0) | 70263 (+0) | 276124 (+0) | 0.203 (-0.000155) | 0.797 (+0.000155) | 0.616 (+0.000233) | 3.77 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 109947 (+0) | 22808 (+0) | 87139 (+0) | 0.207 (+0.000445) | 0.793 (-0.000445) | 0.603 (-0.000432) | 1.33 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 114167 (+0) | 23282 (+0) | 90885 (+0) | 0.204 (-7.07e-05) | 0.796 (+7.07e-05) | 0.613 (-4.26e-05) | 1.24 |
| `multiframe-smoke` | 4 | 20744 (n/a) | 14446 (n/a) | 2593 (n/a) | 11853 (n/a) | 0.179 (n/a) | 0.821 (n/a) | 0.696 (n/a) | 3.01 |

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
| Final byte output | 0.179 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0113 |
| Frame reader sample issue | 0.482 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0446 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.934 |
| AV2 chroma BDPCM op issue | 0.789 |
| AV2 chroma zero-TXB shortcut rate | 0.447 |
| AV2 luma residual op issue | 0.789 |
| AV2 prefetch useful fraction | 0.237 |
| AV2 carry payload bytes/cycle | 16.9 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| multiframe_black_420_16x16_2f_yuv420p8.yuv | PASS | 1936 (n/a) | 950 (n/a) | 242 (n/a) | 708 (n/a) | 0.255 (n/a) | 0.745 (n/a) | 0.491 (n/a) | 1.86 |
| multiframe_black_tall_420_8x24_5f_yuv420p8.yuv | PASS | 3840 (n/a) | 2099 (n/a) | 480 (n/a) | 1619 (n/a) | 0.229 (n/a) | 0.771 (n/a) | 0.547 (n/a) | 2.19 |
| multiframe_motion_444_16x8_2f_yuv444p8.yuv | PASS | 1408 (n/a) | 1007 (n/a) | 176 (n/a) | 831 (n/a) | 0.175 (n/a) | 0.825 (n/a) | 0.715 (n/a) | 3.93 |
| multiframe_motion_wide_444_48x32_2f_yuv444p8.yuv | PASS | 13560 (n/a) | 10390 (n/a) | 1695 (n/a) | 8695 (n/a) | 0.163 (n/a) | 0.837 (n/a) | 0.766 (n/a) | 3.38 |
