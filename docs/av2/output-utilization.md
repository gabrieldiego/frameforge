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

## AV2 prediction decision block

Baseline and current sources:

- Baseline Git SHA: `28fa335ecfba2e9463e416688f0144bd29f159f3`
- Current validated source Git SHA: `7383aee7b77230a85bdd86c5cf151008ba7de553`
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
| `screenshot-sweep-444` | 64 | 763928 (+0) | 364696 (+0) | 95491 (+0) | 269205 (+0) | 0.262 (-0.000163) | 0.738 (+0.000163) | 0.477 (+0.000396) | 4.4 |
| `screenshot-multictu-444` | 10 | 579256 (+0) | 314164 (+0) | 72407 (+0) | 241757 (+0) | 0.23 (+0.000475) | 0.77 (-0.000475) | 0.542 (+0.000358) | 3.42 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 76899 (+0) | 22808 (+0) | 54091 (+0) | 0.297 (-0.000403) | 0.703 (+0.000403) | 0.421 (+0.000448) | 0.927 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 79826 (+0) | 23282 (+0) | 56544 (+0) | 0.292 (-0.000341) | 0.708 (+0.000341) | 0.429 (-0.000418) | 0.869 |
| `multiframe-smoke` | 4 | 19680 (+0) | 11925 (+0) | 2460 (+0) | 9465 (+0) | 0.206 (+0.000289) | 0.794 (-0.000289) | 0.606 (-5.49e-05) | 2.48 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.262 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0164 |
| Frame reader sample issue | 10.3 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.942 |
| Input FIFO nonempty rate | 0.0281 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.94 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.491 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.151 |
| AV2 carry payload bytes/cycle | 16.3 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 286 (+0) | 43 (+0) | 243 (+0) | 0.15 (+0.00035) | 0.85 (-0.00035) | 0.831 (+0.000395) | 4.47 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 862 (+0) | 248 (+0) | 614 (+0) | 0.288 (-0.000297) | 0.712 (+0.000297) | 0.434 (+0.000476) | 6.73 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 431 (+0) | 52 (+0) | 379 (+0) | 0.121 (-0.00035) | 0.879 (+0.00035) | 1.04 (-0.00394) | 2.24 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 616 (+0) | 92 (+0) | 524 (+0) | 0.149 (+0.000351) | 0.851 (-0.000351) | 0.837 (-4.35e-05) | 2.41 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 584 (+0) | 60 (+0) | 524 (+0) | 0.103 (-0.00026) | 0.897 (+0.00026) | 1.22 (-0.00333) | 1.82 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 658 (+0) | 65 (+0) | 593 (+0) | 0.0988 (-1.58e-05) | 0.901 (+0.000216) | 1.27 (-0.00462) | 1.71 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 3067 (+0) | 854 (+0) | 2213 (+0) | 0.278 (+0.000448) | 0.722 (-0.000448) | 0.449 (-8.31e-05) | 6.85 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 3362 (+0) | 852 (+0) | 2510 (+0) | 0.253 (+0.000421) | 0.747 (-0.000421) | 0.493 (+0.000251) | 6.57 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 826 (+0) | 220 (+0) | 606 (+0) | 0.266 (+0.000344) | 0.734 (-0.000344) | 0.469 (+0.000318) | 6.45 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4872 (+0) | 2003 (+0) | 609 (+0) | 1394 (+0) | 0.304 (+4.39e-05) | 0.696 (-4.39e-05) | 0.411 (+0.000125) | 7.82 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 528 (+0) | 674 (+0) | 66 (+0) | 608 (+0) | 0.0979 (+2.28e-05) | 0.902 (+7.72e-05) | 1.28 (-0.00348) | 1.76 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 592 (+0) | 818 (+0) | 74 (+0) | 744 (+0) | 0.0905 (-3.55e-05) | 0.91 (-0.000465) | 1.38 (+0.00176) | 1.6 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9456 (+0) | 4454 (+0) | 1182 (+0) | 3272 (+0) | 0.265 (+0.000379) | 0.735 (-0.000379) | 0.471 (+2.37e-05) | 6.96 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 744 (+0) | 1173 (+0) | 93 (+0) | 1080 (+0) | 0.0793 (-1.61e-05) | 0.921 (-0.000284) | 1.58 (-0.00339) | 1.53 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10344 (+0) | 5123 (+0) | 1293 (+0) | 3830 (+0) | 0.252 (+0.000391) | 0.748 (-0.000391) | 0.495 (+0.000263) | 5.72 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 888 (+0) | 1580 (+0) | 111 (+0) | 1469 (+0) | 0.0703 (-4.68e-05) | 0.93 (-0.000253) | 1.78 (-0.000721) | 1.54 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3648 (+0) | 1621 (+0) | 456 (+0) | 1165 (+0) | 0.281 (+0.000308) | 0.719 (-0.000308) | 0.444 (+0.000353) | 8.44 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 1372 (+0) | 334 (+0) | 1038 (+0) | 0.243 (+0.00044) | 0.757 (-0.00044) | 0.513 (+0.000473) | 3.57 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+0) | 3059 (+0) | 881 (+0) | 2178 (+0) | 0.288 (+2.62e-06) | 0.712 (-2.62e-06) | 0.434 (+2.38e-05) | 5.31 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 6210 (+0) | 1961 (+0) | 4249 (+0) | 0.316 (-0.000219) | 0.684 (+0.000219) | 0.396 (-0.000156) | 8.09 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15248 (+0) | 6087 (+0) | 1906 (+0) | 4181 (+0) | 0.313 (+0.000126) | 0.687 (-0.000126) | 0.399 (+0.0002) | 6.34 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 960 (+0) | 1634 (+0) | 120 (+0) | 1514 (+0) | 0.0734 (+3.94e-05) | 0.927 (-0.000439) | 1.7 (+0.00208) | 1.42 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1064 (+0) | 1954 (+0) | 133 (+0) | 1821 (+0) | 0.0681 (-3.45e-05) | 0.932 (-6.55e-05) | 1.84 (-0.00353) | 1.45 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 22424 (+0) | 9810 (+0) | 2803 (+0) | 7007 (+0) | 0.286 (-0.000271) | 0.714 (+0.000271) | 0.437 (+0.000478) | 6.39 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 1385 (+0) | 397 (+0) | 988 (+0) | 0.287 (-0.000357) | 0.713 (+0.000357) | 0.436 (+8.31e-05) | 5.41 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (+0) | 1092 (+0) | 176 (+0) | 916 (+0) | 0.161 (+0.000172) | 0.839 (-0.000172) | 0.776 (-0.000432) | 2.13 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1824 (+0) | 1518 (+0) | 228 (+0) | 1290 (+0) | 0.15 (+0.000198) | 0.85 (-0.000198) | 0.832 (+0.000237) | 1.98 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11896 (+0) | 5104 (+0) | 1487 (+0) | 3617 (+0) | 0.291 (+0.00034) | 0.709 (-0.00034) | 0.429 (+5.18e-05) | 4.98 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1032 (+0) | 1786 (+0) | 129 (+0) | 1657 (+0) | 0.0722 (+2.84e-05) | 0.928 (-0.000228) | 1.73 (+0.00062) | 1.4 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20456 (+0) | 9694 (+0) | 2557 (+0) | 7137 (+0) | 0.264 (-0.000229) | 0.736 (+0.000229) | 0.474 (-0.000105) | 6.31 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26008 (+0) | 11288 (+0) | 3251 (+0) | 8037 (+0) | 0.288 (+4.96e-06) | 0.712 (-4.96e-06) | 0.434 (+2.03e-05) | 6.3 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1480 (+0) | 2999 (+0) | 185 (+0) | 2814 (+0) | 0.0617 (-1.28e-05) | 0.938 (+0.000313) | 2.03 (-0.00365) | 1.46 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 2464 (+0) | 757 (+0) | 1707 (+0) | 0.307 (+0.000224) | 0.693 (-0.000224) | 0.407 (-0.000131) | 7.7 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14872 (+0) | 5915 (+0) | 1859 (+0) | 4056 (+0) | 0.314 (+0.000286) | 0.686 (-0.000286) | 0.398 (-0.000273) | 9.24 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1464 (+0) | 1607 (+0) | 183 (+0) | 1424 (+0) | 0.114 (-0.000123) | 0.886 (+0.000123) | 1.1 (-0.00232) | 1.67 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21616 (+0) | 9064 (+0) | 2702 (+0) | 6362 (+0) | 0.298 (+0.000102) | 0.702 (-0.000102) | 0.419 (+0.000319) | 7.08 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22944 (+0) | 9733 (+0) | 2868 (+0) | 6865 (+0) | 0.295 (-0.000332) | 0.705 (+0.000332) | 0.424 (+0.000207) | 6.08 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (+0) | 2852 (+0) | 269 (+0) | 2583 (+0) | 0.0943 (+1.98e-05) | 0.906 (-0.00032) | 1.33 (-0.00472) | 1.49 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19784 (+0) | 9585 (+0) | 2473 (+0) | 7112 (+0) | 0.258 (+7.3e-06) | 0.742 (-7.3e-06) | 0.484 (+0.000482) | 4.28 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2032 (+0) | 3687 (+0) | 254 (+0) | 3433 (+0) | 0.0689 (-9.3e-06) | 0.931 (+0.000109) | 1.81 (+0.00447) | 1.44 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 704 (+0) | 83 (+0) | 621 (+0) | 0.118 (-0.000102) | 0.882 (+0.000102) | 1.06 (+0.000241) | 1.83 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 16960 (+0) | 7231 (+0) | 2120 (+0) | 5111 (+0) | 0.293 (+0.000182) | 0.707 (-0.000182) | 0.426 (+0.000356) | 9.42 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14800 (+0) | 6518 (+0) | 1850 (+0) | 4668 (+0) | 0.284 (-0.000171) | 0.716 (+0.000171) | 0.44 (+0.000405) | 5.66 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15920 (+0) | 7057 (+0) | 1990 (+0) | 5067 (+0) | 0.282 (-1.05e-05) | 0.718 (+1.05e-05) | 0.443 (+0.000279) | 4.59 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31960 (+0) | 12994 (+0) | 3995 (+0) | 8999 (+0) | 0.307 (+0.00045) | 0.693 (-0.00045) | 0.407 (-0.000429) | 6.77 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1624 (+0) | 3041 (+0) | 203 (+0) | 2838 (+0) | 0.0668 (-4.56e-05) | 0.933 (+0.000246) | 1.87 (+0.00254) | 1.32 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 11432 (+0) | 7751 (+0) | 1429 (+0) | 6322 (+0) | 0.184 (+0.000363) | 0.816 (-0.000363) | 0.678 (+9.1e-06) | 2.88 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2328 (+0) | 4261 (+0) | 291 (+0) | 3970 (+0) | 0.0683 (-6.17e-06) | 0.932 (-0.000294) | 1.83 (+0.000326) | 1.39 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 2954 (+0) | 894 (+0) | 2060 (+0) | 0.303 (-0.00036) | 0.697 (+0.00036) | 0.413 (+3.13e-05) | 6.59 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9664 (+0) | 4599 (+0) | 1208 (+0) | 3391 (+0) | 0.263 (-0.000334) | 0.737 (+0.000334) | 0.476 (-0.00011) | 5.13 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11904 (+0) | 5752 (+0) | 1488 (+0) | 4264 (+0) | 0.259 (-0.000307) | 0.741 (+0.000307) | 0.483 (+0.000199) | 4.28 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18376 (+0) | 8378 (+0) | 2297 (+0) | 6081 (+0) | 0.274 (+0.00017) | 0.726 (-0.00017) | 0.456 (-7.92e-05) | 4.68 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 36832 (+0) | 15471 (+0) | 4604 (+0) | 10867 (+0) | 0.298 (-0.000411) | 0.702 (+0.000411) | 0.42 (+4.24e-05) | 6.91 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27208 (+0) | 12389 (+0) | 3401 (+0) | 8988 (+0) | 0.275 (-0.000482) | 0.725 (+0.000482) | 0.455 (+0.000344) | 4.61 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56456 (+0) | 23289 (+0) | 7057 (+0) | 16232 (+0) | 0.303 (+1.86e-05) | 0.697 (-1.86e-05) | 0.413 (-0.000484) | 7.43 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28088 (+0) | 13502 (+0) | 3511 (+0) | 9991 (+0) | 0.26 (+3.56e-05) | 0.74 (-3.56e-05) | 0.481 (-0.000296) | 3.77 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5640 (+0) | 2632 (+0) | 705 (+0) | 1927 (+0) | 0.268 (-0.000143) | 0.732 (+0.000143) | 0.467 (-0.000333) | 5.14 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 16376 (+0) | 6900 (+0) | 2047 (+0) | 4853 (+0) | 0.297 (-0.000333) | 0.703 (+0.000333) | 0.421 (+0.000348) | 6.74 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13264 (+0) | 6352 (+0) | 1658 (+0) | 4694 (+0) | 0.261 (+2.02e-05) | 0.739 (-2.02e-05) | 0.479 (-0.00011) | 4.14 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32936 (+0) | 13583 (+0) | 4117 (+0) | 9466 (+0) | 0.303 (+9.95e-05) | 0.697 (-9.95e-05) | 0.412 (+0.000406) | 6.63 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2824 (+0) | 3696 (+0) | 353 (+0) | 3343 (+0) | 0.0955 (+8.66e-06) | 0.904 (+0.000491) | 1.31 (-0.00122) | 1.44 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49024 (+0) | 20545 (+0) | 6128 (+0) | 14417 (+0) | 0.298 (+0.000272) | 0.702 (-0.000272) | 0.419 (+8.05e-05) | 6.69 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3864 (+0) | 5405 (+0) | 483 (+0) | 4922 (+0) | 0.0894 (-3.83e-05) | 0.911 (-0.000362) | 1.4 (-0.00119) | 1.51 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74368 (+0) | 31655 (+0) | 9296 (+0) | 22359 (+0) | 0.294 (-0.000334) | 0.706 (+0.000334) | 0.426 (-0.000346) | 7.73 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.23 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0144 |
| Frame reader sample issue | 15.5 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.944 |
| Input FIFO nonempty rate | 0.0425 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.936 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.659 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.163 |
| AV2 carry payload bytes/cycle | 8.04 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 86760 (+0) | 41347 (+0) | 10845 (+0) | 30502 (+0) | 0.262 (+0.000292) | 0.738 (-0.000292) | 0.477 (-0.000432) | 5.05 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 44520 (+0) | 25143 (+0) | 5565 (+0) | 19578 (+0) | 0.221 (+0.000334) | 0.779 (-0.000334) | 0.565 (-0.000243) | 3.07 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 15912 (+0) | 24186 (+0) | 1989 (+0) | 22197 (+0) | 0.0822 (+3.77e-05) | 0.918 (-0.000238) | 1.52 (-1.51e-05) | 1.48 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45032 (+0) | 30880 (+0) | 5629 (+0) | 25251 (+0) | 0.182 (+0.000286) | 0.818 (-0.000286) | 0.686 (-0.000265) | 2.51 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105520 (+0) | 51670 (+0) | 13190 (+0) | 38480 (+0) | 0.255 (+0.000274) | 0.745 (-0.000274) | 0.49 (-0.00033) | 4.2 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57616 (+0) | 26149 (+0) | 7202 (+0) | 18947 (+0) | 0.275 (+0.000422) | 0.725 (-0.000422) | 0.454 (-0.00015) | 5.67 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3112 (+0) | 6262 (+0) | 389 (+0) | 5873 (+0) | 0.0621 (+2.07e-05) | 0.938 (-0.000121) | 2.01 (+0.00221) | 1.36 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4504 (+0) | 7541 (+0) | 563 (+0) | 6978 (+0) | 0.0747 (-4.15e-05) | 0.925 (+0.000341) | 1.67 (+0.00429) | 1.45 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 137280 (+0) | 61538 (+0) | 17160 (+0) | 44378 (+0) | 0.279 (-0.000148) | 0.721 (+0.000148) | 0.448 (+0.000266) | 5.66 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79000 (+0) | 39448 (+0) | 9875 (+0) | 29573 (+0) | 0.25 (+0.00033) | 0.75 (-0.00033) | 0.499 (+0.000342) | 4.28 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.297 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.019 |
| Frame reader sample issue | 11.8 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0 |
| AV2 carry payload bytes/cycle | 16.7 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (+0) | 191 (+0) | 38 (+0) | 153 (+0) | 0.199 (-4.71e-05) | 0.801 (+4.71e-05) | 0.628 (+0.000289) | 2.98 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 241 (+0) | 57 (+0) | 184 (+0) | 0.237 (-0.000485) | 0.763 (+0.000485) | 0.529 (-0.000491) | 1.88 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 304 (+0) | 80 (+0) | 224 (+0) | 0.263 (+0.000158) | 0.737 (-0.000158) | 0.475 (+0) | 1.58 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 369 (+0) | 103 (+0) | 266 (+0) | 0.279 (+0.000133) | 0.721 (-0.000133) | 0.448 (-0.000184) | 1.44 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 438 (+0) | 122 (+0) | 316 (+0) | 0.279 (-0.000461) | 0.721 (+0.000461) | 0.449 (-0.00023) | 1.37 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 463 (+0) | 129 (+0) | 334 (+0) | 0.279 (-0.000382) | 0.721 (+0.000382) | 0.449 (-0.000357) | 1.21 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 532 (+0) | 155 (+0) | 377 (+0) | 0.291 (+0.000353) | 0.709 (-0.000353) | 0.429 (+3.23e-05) | 1.19 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 590 (+0) | 174 (+0) | 416 (+0) | 0.295 (-8.47e-05) | 0.705 (+8.47e-05) | 0.424 (-0.000149) | 1.15 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 211 (+0) | 42 (+0) | 169 (+0) | 0.199 (+5.21e-05) | 0.801 (-5.21e-05) | 0.628 (-2.38e-05) | 1.65 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 345 (+0) | 93 (+0) | 252 (+0) | 0.27 (-0.000435) | 0.73 (+0.000435) | 0.464 (-0.00029) | 1.35 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 422 (+0) | 114 (+0) | 308 (+0) | 0.27 (+0.000142) | 0.73 (-0.000142) | 0.463 (-0.000281) | 1.1 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 537 (+0) | 152 (+0) | 385 (+0) | 0.283 (+5.4e-05) | 0.717 (-5.4e-05) | 0.442 (-0.000388) | 1.05 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 667 (+0) | 193 (+0) | 474 (+0) | 0.289 (+0.000355) | 0.711 (-0.000355) | 0.432 (-5.18e-06) | 1.04 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 749 (+0) | 222 (+0) | 527 (+0) | 0.296 (+0.000395) | 0.704 (-0.000395) | 0.422 (-0.000266) | 0.975 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 912 (+0) | 261 (+0) | 651 (+0) | 0.286 (+0.000184) | 0.714 (-0.000184) | 0.437 (-0.000218) | 1.02 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 1006 (+0) | 292 (+0) | 714 (+0) | 0.29 (+0.000258) | 0.71 (-0.000258) | 0.431 (-0.000349) | 0.982 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 284 (+0) | 66 (+0) | 218 (+0) | 0.232 (+0.000394) | 0.768 (-0.000394) | 0.538 (-0.000121) | 1.48 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 445 (+0) | 122 (+0) | 323 (+0) | 0.274 (+0.000157) | 0.726 (-0.000157) | 0.456 (-5.74e-05) | 1.16 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 582 (+0) | 163 (+0) | 419 (+0) | 0.28 (+6.87e-05) | 0.72 (-6.87e-05) | 0.446 (+0.000319) | 1.01 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 716 (+0) | 204 (+0) | 512 (+0) | 0.285 (-8.38e-05) | 0.715 (+8.38e-05) | 0.439 (-0.000275) | 0.932 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 936 (+0) | 275 (+0) | 661 (+0) | 0.294 (-0.000197) | 0.706 (+0.000197) | 0.425 (+0.000455) | 0.975 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 1086 (+0) | 325 (+0) | 761 (+0) | 0.299 (+0.000263) | 0.701 (-0.000263) | 0.418 (-0.000308) | 0.943 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 1293 (+0) | 379 (+0) | 914 (+0) | 0.293 (+0.000117) | 0.707 (-0.000117) | 0.426 (+0.000451) | 0.962 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 1490 (+0) | 448 (+0) | 1042 (+0) | 0.301 (-0.000329) | 0.699 (+0.000329) | 0.416 (-0.000263) | 0.97 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 314 (+0) | 75 (+0) | 239 (+0) | 0.239 (-0.000146) | 0.761 (+0.000146) | 0.523 (+0.000333) | 1.23 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 529 (+0) | 149 (+0) | 380 (+0) | 0.282 (-0.000336) | 0.718 (+0.000336) | 0.444 (-0.000208) | 1.03 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 710 (+0) | 200 (+0) | 510 (+0) | 0.282 (-0.00031) | 0.718 (+0.00031) | 0.444 (-0.00025) | 0.924 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 940 (+0) | 279 (+0) | 661 (+0) | 0.297 (-0.000191) | 0.703 (+0.000191) | 0.421 (+0.000147) | 0.918 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 1220 (+0) | 369 (+0) | 851 (+0) | 0.302 (+0.000459) | 0.698 (-0.000459) | 0.413 (+0.000279) | 0.953 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 1378 (+0) | 418 (+0) | 960 (+0) | 0.303 (+0.000338) | 0.697 (-0.000338) | 0.412 (+8.13e-05) | 0.897 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 1667 (+0) | 489 (+0) | 1178 (+0) | 0.293 (+0.000341) | 0.707 (-0.000341) | 0.426 (+0.000125) | 0.93 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 1877 (+0) | 568 (+0) | 1309 (+0) | 0.303 (-0.000389) | 0.697 (+0.000389) | 0.413 (+7.22e-05) | 0.917 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 386 (+0) | 95 (+0) | 291 (+0) | 0.246 (+0.000114) | 0.754 (-0.000114) | 0.508 (-0.000105) | 1.21 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 664 (+0) | 191 (+0) | 473 (+0) | 0.288 (-0.000349) | 0.712 (+0.000349) | 0.435 (-0.000445) | 1.04 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 873 (+0) | 248 (+0) | 625 (+0) | 0.284 (+7.79e-05) | 0.716 (-7.79e-05) | 0.44 (+2.02e-05) | 0.909 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 1151 (+0) | 344 (+0) | 807 (+0) | 0.299 (-0.000129) | 0.701 (+0.000129) | 0.418 (+0.000241) | 0.899 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 1456 (+0) | 433 (+0) | 1023 (+0) | 0.297 (+0.00039) | 0.703 (-0.00039) | 0.42 (+0.000323) | 0.91 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 1786 (+0) | 552 (+0) | 1234 (+0) | 0.309 (+7.05e-05) | 0.691 (-7.05e-05) | 0.404 (+0.000438) | 0.93 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 2064 (+0) | 612 (+0) | 1452 (+0) | 0.297 (-0.000488) | 0.703 (+0.000488) | 0.422 (-0.000431) | 0.921 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 2292 (+0) | 695 (+0) | 1597 (+0) | 0.303 (+0.000229) | 0.697 (-0.000229) | 0.412 (+0.00023) | 0.895 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 458 (+0) | 121 (+0) | 337 (+0) | 0.264 (+0.000192) | 0.736 (-0.000192) | 0.473 (+0.00014) | 1.19 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 780 (+0) | 228 (+0) | 552 (+0) | 0.292 (+0.000308) | 0.708 (-0.000308) | 0.428 (-0.000368) | 1.02 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 994 (+0) | 285 (+0) | 709 (+0) | 0.287 (-0.00028) | 0.713 (+0.00028) | 0.436 (-3.51e-05) | 0.863 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 1319 (+0) | 394 (+0) | 925 (+0) | 0.299 (-0.000289) | 0.701 (+0.000289) | 0.418 (+0.000464) | 0.859 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 1709 (+0) | 513 (+0) | 1196 (+0) | 0.3 (+0.000176) | 0.7 (-0.000176) | 0.416 (+0.000423) | 0.89 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 2028 (+0) | 627 (+0) | 1401 (+0) | 0.309 (+0.000172) | 0.691 (-0.000172) | 0.404 (+0.000306) | 0.88 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 2435 (+0) | 722 (+0) | 1713 (+0) | 0.297 (-0.000491) | 0.703 (+0.000491) | 0.422 (-0.000428) | 0.906 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 2702 (+0) | 814 (+0) | 1888 (+0) | 0.301 (+0.000258) | 0.699 (-0.000258) | 0.415 (-7.37e-05) | 0.88 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 504 (+0) | 134 (+0) | 370 (+0) | 0.266 (-0.000127) | 0.734 (+0.000127) | 0.47 (+0.000149) | 1.12 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 874 (+0) | 259 (+0) | 615 (+0) | 0.296 (+0.000339) | 0.704 (-0.000339) | 0.422 (-0.000185) | 0.975 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 1156 (+0) | 335 (+0) | 821 (+0) | 0.29 (-0.000208) | 0.71 (+0.000208) | 0.431 (+0.000343) | 0.86 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 1521 (+0) | 461 (+0) | 1060 (+0) | 0.303 (+9.01e-05) | 0.697 (-9.01e-05) | 0.412 (+0.000419) | 0.849 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 1938 (+0) | 587 (+0) | 1351 (+0) | 0.303 (-0.00011) | 0.697 (+0.00011) | 0.413 (-0.000308) | 0.865 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 2388 (+0) | 743 (+0) | 1645 (+0) | 0.311 (+0.000139) | 0.689 (-0.000139) | 0.402 (-0.00025) | 0.888 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 2794 (+0) | 838 (+0) | 1956 (+0) | 0.3 (-7.16e-05) | 0.7 (+7.16e-05) | 0.417 (-0.000234) | 0.891 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 3135 (+0) | 950 (+0) | 2185 (+0) | 0.303 (+3.03e-05) | 0.697 (-3.03e-05) | 0.412 (+0.0005) | 0.875 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 539 (+0) | 148 (+0) | 391 (+0) | 0.275 (-0.000417) | 0.725 (+0.000417) | 0.455 (+0.000236) | 1.05 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 940 (+0) | 280 (+0) | 660 (+0) | 0.298 (-0.000128) | 0.702 (+0.000128) | 0.42 (-0.000357) | 0.918 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 1331 (+0) | 394 (+0) | 937 (+0) | 0.296 (+1.8e-05) | 0.704 (-1.8e-05) | 0.422 (+0.000272) | 0.867 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 1692 (+0) | 514 (+0) | 1178 (+0) | 0.304 (-0.000217) | 0.696 (+0.000217) | 0.411 (+0.000479) | 0.826 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 2184 (+0) | 665 (+0) | 1519 (+0) | 0.304 (+0.000487) | 0.696 (-0.000487) | 0.411 (-0.000474) | 0.853 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 2619 (+0) | 812 (+0) | 1807 (+0) | 0.31 (+4.2e-05) | 0.69 (-4.2e-05) | 0.403 (+0.000171) | 0.853 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 3165 (+0) | 968 (+0) | 2197 (+0) | 0.306 (-0.000155) | 0.694 (+0.000155) | 0.409 (-0.000296) | 0.883 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 3578 (+0) | 1090 (+0) | 2488 (+0) | 0.305 (-0.000361) | 0.695 (+0.000361) | 0.41 (+0.000321) | 0.874 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.292 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0183 |
| Frame reader sample issue | 18.2 |
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
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 7061 (+0) | 2123 (+0) | 4938 (+0) | 0.301 (-0.000334) | 0.699 (+0.000334) | 0.416 (-0.000256) | 0.862 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 7145 (+0) | 2145 (+0) | 5000 (+0) | 0.3 (+0.00021) | 0.7 (-0.00021) | 0.416 (+0.000375) | 0.872 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 13636 (+0) | 3977 (+0) | 9659 (+0) | 0.292 (-0.000346) | 0.708 (+0.000346) | 0.429 (-0.000411) | 0.832 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 10430 (+0) | 3111 (+0) | 7319 (+0) | 0.298 (+0.000274) | 0.702 (-0.000274) | 0.419 (+7.75e-05) | 0.849 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 10052 (+0) | 2827 (+0) | 7225 (+0) | 0.281 (+0.000238) | 0.719 (-0.000238) | 0.444 (+0.000464) | 0.818 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 4228 (+0) | 1227 (+0) | 3001 (+0) | 0.29 (+0.000208) | 0.71 (-0.000208) | 0.431 (-0.000275) | 0.918 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 4159 (+0) | 1242 (+0) | 2917 (+0) | 0.299 (-0.000371) | 0.701 (+0.000371) | 0.419 (-0.000421) | 0.903 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 4922 (+0) | 1423 (+0) | 3499 (+0) | 0.289 (+0.00011) | 0.711 (-0.00011) | 0.432 (+0.000361) | 0.949 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 9952 (+0) | 2819 (+0) | 7133 (+0) | 0.283 (+0.00026) | 0.717 (-0.00026) | 0.441 (+0.000291) | 0.915 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 8241 (+0) | 2388 (+0) | 5853 (+0) | 0.29 (-0.000229) | 0.71 (+0.000229) | 0.431 (+0.000376) | 0.894 |

### Multi-Frame Smoke

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.206 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.013 |
| Frame reader sample issue | 5.3 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.959 |
| Input FIFO nonempty rate | 0.0564 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.942 |
| AV2 chroma BDPCM op issue | 0.744 |
| AV2 chroma zero-TXB shortcut rate | 0.442 |
| AV2 luma residual op issue | 0.744 |
| AV2 prefetch useful fraction | 0.231 |
| AV2 carry payload bytes/cycle | 17.1 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| multiframe_black_420_16x16_2f_yuv420p8.yuv | PASS | 1936 (+0) | 950 (+0) | 242 (+0) | 708 (+0) | 0.255 (-0.000263) | 0.745 (+0.000263) | 0.491 (-0.000298) | 1.86 |
| multiframe_black_tall_420_8x24_5f_yuv420p8.yuv | PASS | 3840 (+0) | 2099 (+0) | 480 (+0) | 1619 (+0) | 0.229 (-0.00032) | 0.771 (+0.00032) | 0.547 (-0.000385) | 2.19 |
| multiframe_motion_444_16x8_2f_yuv444p8.yuv | PASS | 1408 (+0) | 956 (+0) | 176 (+0) | 780 (+0) | 0.184 (+0.0001) | 0.816 (-0.0001) | 0.679 (-2.27e-05) | 3.73 |
| multiframe_motion_wide_444_48x32_2f_yuv444p8.yuv | PASS | 12496 (+0) | 7920 (+0) | 1562 (+0) | 6358 (+0) | 0.197 (+0.000222) | 0.803 (-0.000222) | 0.634 (-0.000197) | 2.58 |
