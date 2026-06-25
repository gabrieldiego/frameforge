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

## 2026-06-25 AV2 IBC Hash Expansion Checkpoint

Baseline and current sources:

- Baseline Git SHA: `48ba35795881b898d28fbd6de13cac61147ac108`
- Current validated source Git SHA: `6779c2e4b2726adef94cd7921dd62f106e454afb+working-tree`
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
| `screenshot-sweep-444` | 64 | 749352 (+216) | 424810 (+550) | 93669 (+27) | 331141 (+523) | 0.22 (-0.000504) | 0.78 (+0.000504) | 0.567 (+0.000903) | 5.12 |
| `screenshot-multictu-444` | 10 | 562104 (-40) | 365312 (+3273) | 70263 (-5) | 295049 (+3278) | 0.192 (-0.00166) | 0.808 (+0.00166) | 0.65 (+0.0059) | 3.98 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 129570 (+0) | 22808 (+0) | 106762 (+0) | 0.176 (+2.84e-05) | 0.824 (-2.84e-05) | 0.71 (+0.000113) | 1.56 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 136548 (+0) | 23282 (+0) | 113266 (+0) | 0.171 (-0.000496) | 0.829 (+0.000496) | 0.733 (+0.00012) | 1.49 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.22 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0139 |
| Frame reader sample issue | 0.428 |
| Reader-to-FIFO handshake | 0.89 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0731 |
| Input FIFO full rate | 0.0108 |
| AV2 leaf entropy op issue | 0.951 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.438 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.147 |
| AV2 carry payload bytes/cycle | 8.15 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 367 (+0) | 43 (+0) | 324 (+0) | 0.117 (+0.000166) | 0.883 (-0.000166) | 1.07 (-0.00314) | 5.73 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 1013 (+0) | 248 (+0) | 765 (+0) | 0.245 (-0.000183) | 0.755 (+0.000183) | 0.511 (-0.000415) | 7.91 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 607 (+0) | 52 (+0) | 555 (+0) | 0.0857 (-3.28e-05) | 0.914 (+0.000333) | 1.46 (-0.000865) | 3.16 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 819 (+0) | 92 (+0) | 727 (+0) | 0.112 (+0.000332) | 0.888 (-0.000332) | 1.11 (+0.00277) | 3.2 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 854 (+0) | 60 (+0) | 794 (+0) | 0.0703 (-4.24e-05) | 0.93 (-0.000258) | 1.78 (-0.000833) | 2.67 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 956 (+0) | 65 (+0) | 891 (+0) | 0.068 (-8.37e-06) | 0.932 (+8.37e-06) | 1.84 (-0.00154) | 2.49 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 3811 (+0) | 854 (+0) | 2957 (+0) | 0.224 (+8.82e-05) | 0.776 (-8.82e-05) | 0.558 (-0.000184) | 8.51 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6960 (+0) | 4138 (+0) | 870 (+0) | 3268 (+0) | 0.21 (+0.000246) | 0.79 (-0.000246) | 0.595 (-0.00046) | 8.08 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 990 (+0) | 220 (+0) | 770 (+0) | 0.222 (+0.000222) | 0.778 (-0.000222) | 0.562 (+0.0005) | 7.73 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4880 (+0) | 2302 (+0) | 610 (+0) | 1692 (+0) | 0.265 (-1.3e-05) | 0.735 (+1.3e-05) | 0.472 (-0.000279) | 8.99 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 504 (+32) | 959 (+83) | 63 (+4) | 896 (+79) | 0.0657 (-0.00171) | 0.934 (+0.00131) | 1.9 (+0.0428) | 2.5 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 552 (+40) | 1093 (+90) | 69 (+5) | 1024 (+85) | 0.0631 (-0.000671) | 0.937 (+0.000871) | 1.98 (+0.0201) | 2.13 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9208 (+0) | 5304 (+0) | 1151 (+0) | 4153 (+0) | 0.217 (+6.03e-06) | 0.783 (-6.03e-06) | 0.576 (+2.09e-05) | 8.29 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 704 (+96) | 1599 (+235) | 88 (+12) | 1511 (+223) | 0.055 (-0.000666) | 0.945 (+0.000966) | 2.27 (+0.0313) | 2.08 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10312 (+0) | 6387 (+0) | 1289 (+0) | 5098 (+0) | 0.202 (-0.000184) | 0.798 (+0.000184) | 0.619 (+0.000375) | 7.13 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 824 (+128) | 2038 (+319) | 103 (+16) | 1935 (+303) | 0.0505 (-6.03e-05) | 0.949 (+0.00046) | 2.47 (+0.0033) | 1.99 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3632 (+0) | 1898 (+0) | 454 (+0) | 1444 (+0) | 0.239 (+0.000199) | 0.761 (-0.000199) | 0.523 (-0.000423) | 9.89 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 1753 (+0) | 334 (+0) | 1419 (+0) | 0.191 (-0.000469) | 0.809 (+0.000469) | 0.656 (+6.29e-05) | 4.57 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+0) | 3691 (+0) | 881 (+0) | 2810 (+0) | 0.239 (-0.000311) | 0.761 (+0.000311) | 0.524 (-0.000305) | 6.41 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 7219 (+0) | 1961 (+0) | 5258 (+0) | 0.272 (-0.000356) | 0.728 (+0.000356) | 0.46 (+0.000161) | 9.4 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15256 (+0) | 7060 (+0) | 1907 (+0) | 5153 (+0) | 0.27 (+0.000113) | 0.73 (-0.000113) | 0.463 (-0.000231) | 7.35 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 1784 (+0) | 85 (+0) | 1699 (+0) | 0.0476 (+4.57e-05) | 0.952 (+0.000354) | 2.62 (+0.00353) | 1.55 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 2093 (+0) | 90 (+0) | 2003 (+0) | 0.043 (+4.78e-07) | 0.957 (-4.78e-07) | 2.91 (-0.00306) | 1.56 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 21472 (+0) | 11759 (+0) | 2684 (+0) | 9075 (+0) | 0.228 (+0.000251) | 0.772 (-0.000251) | 0.548 (-0.000357) | 7.66 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 1728 (+0) | 397 (+0) | 1331 (+0) | 0.23 (-0.000255) | 0.77 (+0.000255) | 0.544 (+8.06e-05) | 6.75 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1384 (+0) | 1461 (+0) | 173 (+0) | 1288 (+0) | 0.118 (+0.000412) | 0.882 (-0.000412) | 1.06 (-0.00436) | 2.85 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1440 (+0) | 1770 (+0) | 180 (+0) | 1590 (+0) | 0.102 (-0.000305) | 0.898 (+0.000305) | 1.23 (-0.000833) | 2.3 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11816 (+0) | 5825 (+0) | 1477 (+0) | 4348 (+0) | 0.254 (-0.000438) | 0.746 (+0.000438) | 0.493 (-2.44e-05) | 5.69 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 1989 (+0) | 86 (+0) | 1903 (+0) | 0.0432 (+3.78e-05) | 0.957 (-0.000238) | 2.89 (+0.000988) | 1.55 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20232 (-56) | 11479 (-113) | 2529 (-7) | 8950 (-106) | 0.22 (+0.00132) | 0.78 (-0.00132) | 0.567 (-0.00363) | 7.47 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26072 (+0) | 13786 (+0) | 3259 (+0) | 10527 (+0) | 0.236 (+0.000399) | 0.764 (-0.000399) | 0.529 (-0.000234) | 7.69 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 2766 (+0) | 107 (+0) | 2659 (+0) | 0.0387 (-1.6e-05) | 0.961 (+0.000316) | 3.23 (+0.00131) | 1.35 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 2947 (+0) | 757 (+0) | 2190 (+0) | 0.257 (-0.000129) | 0.743 (+0.000129) | 0.487 (-0.000375) | 9.21 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14504 (+0) | 6602 (+0) | 1813 (+0) | 4789 (+0) | 0.275 (-0.000386) | 0.725 (+0.000386) | 0.455 (+0.000185) | 10.3 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1296 (+0) | 2067 (+0) | 162 (+0) | 1905 (+0) | 0.0784 (-2.55e-05) | 0.922 (-0.000374) | 1.59 (+0.00491) | 2.15 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21328 (+0) | 10669 (+0) | 2666 (+0) | 8003 (+0) | 0.25 (-0.000117) | 0.75 (+0.000117) | 0.5 (+0.000234) | 8.34 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22824 (+0) | 11363 (+0) | 2853 (+0) | 8510 (+0) | 0.251 (+7.81e-05) | 0.749 (-7.81e-05) | 0.498 (-0.000147) | 7.1 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1712 (+0) | 3076 (+0) | 214 (+0) | 2862 (+0) | 0.0696 (-2.91e-05) | 0.93 (+0.000429) | 1.8 (-0.00327) | 1.6 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19224 (+0) | 11280 (+0) | 2403 (+0) | 8877 (+0) | 0.213 (+3.19e-05) | 0.787 (-3.19e-05) | 0.587 (-0.000233) | 5.04 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 3376 (+0) | 143 (+0) | 3233 (+0) | 0.0424 (-4.22e-05) | 0.958 (-0.000358) | 2.95 (+0.00105) | 1.32 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 640 (-24) | 1081 (-64) | 80 (-3) | 1001 (-61) | 0.074 (+0.00151) | 0.926 (-0.00201) | 1.69 (-0.0309) | 2.82 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 17104 (+0) | 8436 (+0) | 2138 (+0) | 6298 (+0) | 0.253 (+0.000438) | 0.747 (-0.000438) | 0.493 (+0.000218) | 11 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14712 (+0) | 7740 (+0) | 1839 (+0) | 5901 (+0) | 0.238 (-0.000403) | 0.762 (+0.000403) | 0.526 (+0.000101) | 6.72 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15952 (+0) | 8519 (+0) | 1994 (+0) | 6525 (+0) | 0.234 (+6.5e-05) | 0.766 (-6.5e-05) | 0.534 (+3.96e-05) | 5.55 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31720 (+0) | 15139 (+0) | 3965 (+0) | 11174 (+0) | 0.262 (-9.37e-05) | 0.738 (+9.37e-05) | 0.477 (+0.00027) | 7.88 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 3002 (+0) | 110 (+0) | 2892 (+0) | 0.0366 (+4.22e-05) | 0.963 (+0.000358) | 3.41 (+0.00136) | 1.3 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10856 (+0) | 9497 (+0) | 1357 (+0) | 8140 (+0) | 0.143 (-0.000113) | 0.857 (+0.000113) | 0.875 (-0.000184) | 3.53 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 3889 (+0) | 155 (+0) | 3734 (+0) | 0.0399 (-4.4e-05) | 0.96 (+0.000144) | 3.14 (-0.00371) | 1.27 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 3629 (+0) | 894 (+0) | 2735 (+0) | 0.246 (+0.000349) | 0.754 (-0.000349) | 0.507 (+0.000411) | 8.1 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9600 (+0) | 5544 (+0) | 1200 (+0) | 4344 (+0) | 0.216 (+0.00045) | 0.784 (-0.00045) | 0.578 (-0.0005) | 6.19 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11736 (+0) | 6981 (+0) | 1467 (+0) | 5514 (+0) | 0.21 (+0.000142) | 0.79 (-0.000142) | 0.595 (-0.000164) | 5.19 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18064 (+0) | 9760 (+0) | 2258 (+0) | 7502 (+0) | 0.231 (+0.000352) | 0.769 (-0.000352) | 0.54 (+0.000301) | 5.45 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 38912 (+0) | 18947 (+0) | 4864 (+0) | 14083 (+0) | 0.257 (-0.000284) | 0.743 (+0.000284) | 0.487 (-8.08e-05) | 8.46 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22672 (+0) | 12567 (+0) | 2834 (+0) | 9733 (+0) | 0.226 (-0.000489) | 0.774 (+0.000489) | 0.554 (+0.000296) | 4.68 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56384 (+0) | 27199 (+0) | 7048 (+0) | 20151 (+0) | 0.259 (+0.000127) | 0.741 (-0.000127) | 0.482 (+0.000389) | 8.67 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 27056 (+0) | 15106 (+0) | 3382 (+0) | 11724 (+0) | 0.224 (-0.000115) | 0.776 (+0.000115) | 0.558 (+0.000323) | 4.21 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5568 (+0) | 3286 (+0) | 696 (+0) | 2590 (+0) | 0.212 (-0.000192) | 0.788 (+0.000192) | 0.59 (+0.000158) | 6.42 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 17248 (+0) | 8457 (+0) | 2156 (+0) | 6301 (+0) | 0.255 (-6.33e-05) | 0.745 (+6.33e-05) | 0.49 (+0.000318) | 8.26 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13032 (+0) | 7442 (+0) | 1629 (+0) | 5813 (+0) | 0.219 (-0.000107) | 0.781 (+0.000107) | 0.571 (+5.59e-05) | 4.85 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32824 (+0) | 15792 (+0) | 4103 (+0) | 11689 (+0) | 0.26 (-0.000185) | 0.74 (+0.000185) | 0.481 (+0.000111) | 7.71 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2064 (+0) | 3992 (+0) | 258 (+0) | 3734 (+0) | 0.0646 (+2.93e-05) | 0.935 (+0.000371) | 1.93 (+0.00411) | 1.56 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49072 (+0) | 23908 (+0) | 6134 (+0) | 17774 (+0) | 0.257 (-0.000433) | 0.743 (+0.000433) | 0.487 (+0.000202) | 7.78 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2536 (+0) | 5344 (+0) | 317 (+0) | 5027 (+0) | 0.0593 (+1.89e-05) | 0.941 (-0.000319) | 2.11 (-0.00274) | 1.49 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74392 (+0) | 36875 (+0) | 9299 (+0) | 27576 (+0) | 0.252 (+0.000176) | 0.748 (-0.000176) | 0.496 (-0.000315) | 9 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.192 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.012 |
| Frame reader sample issue | 0.45 |
| Reader-to-FIFO handshake | 0.909 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0841 |
| Input FIFO full rate | 0.0111 |
| AV2 leaf entropy op issue | 0.959 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.472 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.143 |
| AV2 carry payload bytes/cycle | 3.46 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 85944 (+0) | 47986 (+0) | 10743 (+0) | 37243 (+0) | 0.224 (-0.000122) | 0.776 (+0.000122) | 0.558 (+0.00034) | 5.86 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 42560 (+0) | 27302 (+0) | 5320 (+0) | 21982 (+0) | 0.195 (-0.000142) | 0.805 (+0.000142) | 0.641 (+0.000494) | 3.33 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 9784 (+0) | 22004 (+0) | 1223 (+0) | 20781 (+0) | 0.0556 (-1.92e-05) | 0.944 (+0.000419) | 2.25 (-0.00102) | 1.34 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 42200 (+0) | 34123 (+0) | 5275 (+0) | 28848 (+0) | 0.155 (-0.000412) | 0.845 (+0.000412) | 0.809 (-0.000398) | 2.78 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105584 (+0) | 64517 (+0) | 13198 (+0) | 51319 (+0) | 0.205 (-0.000434) | 0.795 (+0.000434) | 0.611 (+4.9e-05) | 5.25 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57192 (+0) | 31191 (+0) | 7149 (+0) | 24042 (+0) | 0.229 (+0.000201) | 0.771 (-0.000201) | 0.545 (+0.000373) | 6.77 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 5950 (+0) | 208 (+0) | 5742 (+0) | 0.035 (-4.2e-05) | 0.965 (+4.2e-05) | 3.58 (-0.00428) | 1.29 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 2984 (-16) | 7895 (-68) | 373 (-2) | 7522 (-66) | 0.0472 (+0.000145) | 0.953 (-0.000245) | 2.65 (-0.00422) | 1.52 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136424 (+0) | 73937 (+0) | 17053 (+0) | 56884 (+0) | 0.231 (-0.000358) | 0.769 (+0.000358) | 0.542 (-3.52e-05) | 6.8 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 77768 (-24) | 50407 (+3341) | 9721 (-3) | 40686 (+3344) | 0.193 (-0.0141) | 0.807 (+0.0141) | 0.648 (+0.0432) | 5.47 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.176 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0113 |
| Frame reader sample issue | 0.509 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0461 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.983 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.161 |
| AV2 carry payload bytes/cycle | 8.28 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (+0) | 276 (+0) | 38 (+0) | 238 (+0) | 0.138 (-0.000319) | 0.862 (+0.000319) | 0.908 (-0.000105) | 4.31 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 354 (+0) | 57 (+0) | 297 (+0) | 0.161 (+1.69e-05) | 0.839 (-1.69e-05) | 0.776 (+0.000316) | 2.77 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 476 (+0) | 80 (+0) | 396 (+0) | 0.168 (+6.72e-05) | 0.832 (-6.72e-05) | 0.744 (-0.00025) | 2.48 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 561 (+0) | 103 (+0) | 458 (+0) | 0.184 (-0.000399) | 0.816 (+0.000399) | 0.681 (-0.000175) | 2.19 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 681 (+0) | 122 (+0) | 559 (+0) | 0.179 (+0.000148) | 0.821 (-0.000148) | 0.698 (-0.000254) | 2.13 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 733 (+0) | 129 (+0) | 604 (+0) | 0.176 (-1.09e-05) | 0.824 (+1.09e-05) | 0.71 (+0.000271) | 1.91 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 850 (+0) | 155 (+0) | 695 (+0) | 0.182 (+0.000353) | 0.818 (-0.000353) | 0.685 (+0.000484) | 1.9 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 926 (+0) | 174 (+0) | 752 (+0) | 0.188 (-9.5e-05) | 0.812 (+9.5e-05) | 0.665 (+0.00023) | 1.81 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 353 (+0) | 42 (+0) | 311 (+0) | 0.119 (-1.98e-05) | 0.881 (+1.98e-05) | 1.05 (+0.000595) | 2.76 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 551 (+0) | 93 (+0) | 458 (+0) | 0.169 (-0.000216) | 0.831 (+0.000216) | 0.741 (-0.000409) | 2.15 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 719 (+0) | 114 (+0) | 605 (+0) | 0.159 (-0.000446) | 0.841 (+0.000446) | 0.788 (+0.000377) | 1.87 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 870 (+0) | 152 (+0) | 718 (+0) | 0.175 (-0.000287) | 0.825 (+0.000287) | 0.715 (+0.000461) | 1.7 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 1114 (+0) | 193 (+0) | 921 (+0) | 0.173 (+0.00025) | 0.827 (-0.00025) | 0.722 (-0.000497) | 1.74 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 1246 (+0) | 222 (+0) | 1024 (+0) | 0.178 (+0.00017) | 0.822 (-0.00017) | 0.702 (-0.000423) | 1.62 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 1461 (+0) | 261 (+0) | 1200 (+0) | 0.179 (-0.000355) | 0.821 (+0.000355) | 0.7 (-0.000287) | 1.63 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 1592 (+0) | 292 (+0) | 1300 (+0) | 0.183 (+0.000417) | 0.817 (-0.000417) | 0.682 (-0.000493) | 1.55 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 494 (+0) | 66 (+0) | 428 (+0) | 0.134 (-0.000397) | 0.866 (+0.000397) | 0.936 (-0.000394) | 2.57 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 729 (+0) | 122 (+0) | 607 (+0) | 0.167 (+0.000353) | 0.833 (-0.000353) | 0.747 (-7.38e-05) | 1.9 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 1012 (+0) | 163 (+0) | 849 (+0) | 0.161 (+6.72e-05) | 0.839 (-6.72e-05) | 0.776 (+7.36e-05) | 1.76 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 1199 (+0) | 204 (+0) | 995 (+0) | 0.17 (+0.000142) | 0.83 (-0.000142) | 0.735 (-0.000319) | 1.56 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 1587 (+0) | 275 (+0) | 1312 (+0) | 0.173 (+0.000283) | 0.827 (-0.000283) | 0.721 (+0.000364) | 1.65 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 1812 (+0) | 325 (+0) | 1487 (+0) | 0.179 (+0.00036) | 0.821 (-0.00036) | 0.697 (-7.69e-05) | 1.57 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 2123 (+0) | 379 (+0) | 1744 (+0) | 0.179 (-0.000479) | 0.821 (+0.000479) | 0.7 (+0.000198) | 1.58 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 2388 (+0) | 448 (+0) | 1940 (+0) | 0.188 (-0.000395) | 0.812 (+0.000395) | 0.666 (+0.000295) | 1.55 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 581 (+0) | 75 (+0) | 506 (+0) | 0.129 (+8.78e-05) | 0.871 (-8.78e-05) | 0.968 (+0.000333) | 2.27 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 894 (+0) | 149 (+0) | 745 (+0) | 0.167 (-0.000333) | 0.833 (+0.000333) | 0.75 (+0) | 1.75 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 1269 (+0) | 200 (+0) | 1069 (+0) | 0.158 (-0.000396) | 0.842 (+0.000396) | 0.793 (+0.000125) | 1.65 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 1569 (+0) | 279 (+0) | 1290 (+0) | 0.178 (-0.00018) | 0.822 (+0.00018) | 0.703 (-4.3e-05) | 1.53 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 2073 (+0) | 369 (+0) | 1704 (+0) | 0.178 (+2.89e-06) | 0.822 (-2.89e-06) | 0.702 (+0.000236) | 1.62 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 2331 (+0) | 418 (+0) | 1913 (+0) | 0.179 (+0.000322) | 0.821 (-0.000322) | 0.697 (+6.94e-05) | 1.52 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 2742 (+0) | 489 (+0) | 2253 (+0) | 0.178 (+0.000337) | 0.822 (-0.000337) | 0.701 (-7.98e-05) | 1.53 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 3050 (+0) | 568 (+0) | 2482 (+0) | 0.186 (+0.00023) | 0.814 (-0.00023) | 0.671 (+0.000215) | 1.49 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 706 (+0) | 95 (+0) | 611 (+0) | 0.135 (-0.000439) | 0.865 (+0.000439) | 0.929 (-5.26e-05) | 2.21 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 1113 (+0) | 191 (+0) | 922 (+0) | 0.172 (-0.000392) | 0.828 (+0.000392) | 0.728 (+0.000403) | 1.74 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 1563 (+0) | 248 (+0) | 1315 (+0) | 0.159 (-0.000331) | 0.841 (+0.000331) | 0.788 (-0.000198) | 1.63 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 1928 (+0) | 344 (+0) | 1584 (+0) | 0.178 (+0.000423) | 0.822 (-0.000423) | 0.701 (-0.000419) | 1.51 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 2503 (+0) | 433 (+0) | 2070 (+0) | 0.173 (-7.59e-06) | 0.827 (+7.59e-06) | 0.723 (-0.000425) | 1.56 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 2965 (+0) | 552 (+0) | 2413 (+0) | 0.186 (+0.000172) | 0.814 (-0.000172) | 0.671 (+0.000422) | 1.54 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 3408 (+0) | 612 (+0) | 2796 (+0) | 0.18 (-0.000423) | 0.82 (+0.000423) | 0.696 (+7.84e-05) | 1.52 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 3756 (+0) | 695 (+0) | 3061 (+0) | 0.185 (+3.73e-05) | 0.815 (-3.73e-05) | 0.676 (-0.00046) | 1.47 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 835 (+0) | 121 (+0) | 714 (+0) | 0.145 (-8.98e-05) | 0.855 (+8.98e-05) | 0.863 (-0.000397) | 2.17 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 1314 (+0) | 228 (+0) | 1086 (+0) | 0.174 (-0.000484) | 0.826 (+0.000484) | 0.72 (+0.000395) | 1.71 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 1811 (+0) | 285 (+0) | 1526 (+0) | 0.157 (+0.000372) | 0.843 (-0.000372) | 0.794 (+0.000298) | 1.57 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2243 (+0) | 394 (+0) | 1849 (+0) | 0.176 (-0.000342) | 0.824 (+0.000342) | 0.712 (-0.000388) | 1.46 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 2956 (+0) | 513 (+0) | 2443 (+0) | 0.174 (-0.000455) | 0.826 (+0.000455) | 0.72 (+0.000273) | 1.54 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 3437 (+0) | 627 (+0) | 2810 (+0) | 0.182 (+0.000427) | 0.818 (-0.000427) | 0.685 (+0.000207) | 1.49 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 4039 (+0) | 722 (+0) | 3317 (+0) | 0.179 (-0.000243) | 0.821 (+0.000243) | 0.699 (+0.000273) | 1.5 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 4447 (+0) | 814 (+0) | 3633 (+0) | 0.183 (+4.47e-05) | 0.817 (-4.47e-05) | 0.683 (-0.000107) | 1.45 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 937 (+0) | 134 (+0) | 803 (+0) | 0.143 (+9.61e-06) | 0.857 (-9.61e-06) | 0.874 (+6.72e-05) | 2.09 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 1489 (+0) | 259 (+0) | 1230 (+0) | 0.174 (-5.78e-05) | 0.826 (+5.78e-05) | 0.719 (-0.000371) | 1.66 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 2105 (+0) | 335 (+0) | 1770 (+0) | 0.159 (+0.000145) | 0.841 (-0.000145) | 0.785 (+0.000448) | 1.57 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 2590 (+0) | 461 (+0) | 2129 (+0) | 0.178 (-7.72e-06) | 0.822 (+7.72e-06) | 0.702 (+0.000278) | 1.45 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 3398 (+0) | 587 (+0) | 2811 (+0) | 0.173 (-0.000251) | 0.827 (+0.000251) | 0.724 (-0.000405) | 1.52 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 4026 (+0) | 743 (+0) | 3283 (+0) | 0.185 (-0.00045) | 0.815 (+0.00045) | 0.677 (+0.000322) | 1.5 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 4686 (+0) | 838 (+0) | 3848 (+0) | 0.179 (-0.000169) | 0.821 (+0.000169) | 0.699 (-1.43e-05) | 1.49 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 5159 (+0) | 950 (+0) | 4209 (+0) | 0.184 (+0.000144) | 0.816 (-0.000144) | 0.679 (-0.000184) | 1.44 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 1031 (+0) | 148 (+0) | 883 (+0) | 0.144 (-0.00045) | 0.856 (+0.00045) | 0.871 (-0.000223) | 2.01 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 1637 (+0) | 280 (+0) | 1357 (+0) | 0.171 (+4.46e-05) | 0.829 (-4.46e-05) | 0.731 (-0.000196) | 1.6 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2411 (+0) | 394 (+0) | 2017 (+0) | 0.163 (+0.000418) | 0.837 (-0.000418) | 0.765 (-8.88e-05) | 1.57 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 2910 (+0) | 514 (+0) | 2396 (+0) | 0.177 (-0.000368) | 0.823 (+0.000368) | 0.708 (-0.000315) | 1.42 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 3837 (+0) | 665 (+0) | 3172 (+0) | 0.173 (+0.000312) | 0.827 (-0.000312) | 0.721 (+0.000241) | 1.5 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 4485 (+0) | 812 (+0) | 3673 (+0) | 0.181 (+4.79e-05) | 0.819 (-4.79e-05) | 0.69 (+0.000425) | 1.46 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 5356 (+0) | 968 (+0) | 4388 (+0) | 0.181 (-0.000268) | 0.819 (+0.000268) | 0.692 (-0.000368) | 1.49 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 5873 (+0) | 1090 (+0) | 4783 (+0) | 0.186 (-0.000405) | 0.814 (+0.000405) | 0.674 (-0.000491) | 1.43 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.171 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0107 |
| Frame reader sample issue | 0.539 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0583 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.986 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.161 |
| AV2 carry payload bytes/cycle | 2.68 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 11756 (+0) | 2123 (+0) | 9633 (+0) | 0.181 (-0.000411) | 0.819 (+0.000411) | 0.692 (+0.000181) | 1.44 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 12382 (+0) | 2145 (+0) | 10237 (+0) | 0.173 (+0.000235) | 0.827 (-0.000235) | 0.722 (-0.000438) | 1.51 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 23147 (+0) | 3977 (+0) | 19170 (+0) | 0.172 (-0.000185) | 0.828 (+0.000185) | 0.728 (-0.000473) | 1.41 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 18192 (+0) | 3111 (+0) | 15081 (+0) | 0.171 (+9.23e-06) | 0.829 (-9.23e-06) | 0.731 (-4.53e-05) | 1.48 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 17707 (+0) | 2827 (+0) | 14880 (+0) | 0.16 (-0.000346) | 0.84 (+0.000346) | 0.783 (-5.87e-05) | 1.44 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 7113 (+0) | 1227 (+0) | 5886 (+0) | 0.173 (-0.000499) | 0.827 (+0.000499) | 0.725 (-0.000367) | 1.54 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 6888 (+0) | 1242 (+0) | 5646 (+0) | 0.18 (+0.000314) | 0.82 (-0.000314) | 0.693 (+0.000237) | 1.49 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 8085 (+0) | 1423 (+0) | 6662 (+0) | 0.176 (+4.95e-06) | 0.824 (-4.95e-06) | 0.71 (+0.000207) | 1.56 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 17019 (+0) | 2819 (+0) | 14200 (+0) | 0.166 (-0.000362) | 0.834 (+0.000362) | 0.755 (-0.000344) | 1.56 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 14259 (+0) | 2388 (+0) | 11871 (+0) | 0.167 (+0.000473) | 0.833 (-0.000473) | 0.746 (+0.000388) | 1.55 |
