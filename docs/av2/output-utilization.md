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

## 2026-06-24 Residual Packet Packing Checkpoint

Baseline and current sources:

- Baseline Git SHA: `a5d5f94c7c73b42920f9405bc41d6c14244de12e`
- Current validated source Git SHA: `d5c8aea952cebba4cd835e6ddf94cdd1e26c7a47`
- Delta columns compare against the previous documented AV2 output-utilization
  checkpoint where the same vector or aggregate was present.

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: FAIL, code 139 during timing optimization before WNS/TNS reporting.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 64 | 749136 (-6136) | 411486 (-330057) | 93642 (-767) | 317844 (-329290) | 0.228 (+0.101) | 0.772 (-0.101) | 0.549 (-0.433) | 4.96 |
| `screenshot-multictu-444` | 10 | 562144 (-8336) | 350778 (-248851) | 70268 (-1042) | 280510 (-247809) | 0.2 (+0.0813) | 0.8 (-0.0813) | 0.624 (-0.426) | 3.82 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 128546 (-36173) | 22808 (+0) | 105738 (-36173) | 0.177 (+0.0394) | 0.823 (-0.0394) | 0.705 (-0.198) | 1.55 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 136036 (-32298) | 23282 (+0) | 112754 (-32298) | 0.171 (+0.0331) | 0.829 (-0.0331) | 0.73 (-0.174) | 1.48 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.228 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0143 |
| Frame reader sample issue | 0.474 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0215 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.95 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.439 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.148 |
| AV2 carry payload bytes/cycle | 8.15 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 351 (-115) | 43 (+0) | 308 (-115) | 0.123 (+0.0302) | 0.877 (-0.0305) | 1.02 (-0.33) | 5.48 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 962 (-852) | 248 (+0) | 714 (-852) | 0.258 (+0.121) | 0.742 (-0.121) | 0.485 (-0.429) | 7.52 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 591 (-263) | 52 (+0) | 539 (-263) | 0.088 (+0.0271) | 0.912 (-0.027) | 1.42 (-0.629) | 3.08 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 803 (-494) | 92 (+0) | 711 (-494) | 0.115 (+0.0437) | 0.885 (-0.0436) | 1.09 (-0.669) | 3.14 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 838 (-407) | 60 (+0) | 778 (-407) | 0.0716 (+0.0234) | 0.928 (-0.0236) | 1.75 (-0.844) | 2.62 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 939 (-501) | 65 (+0) | 874 (-501) | 0.0692 (+0.0241) | 0.931 (-0.0242) | 1.81 (-0.964) | 2.45 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (-32) | 3568 (-2537) | 854 (-4) | 2714 (-2533) | 0.239 (+0.0983) | 0.761 (-0.0983) | 0.522 (-0.367) | 7.96 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6960 (+144) | 3881 (-2812) | 870 (+18) | 3011 (-2830) | 0.224 (+0.0972) | 0.776 (-0.0972) | 0.558 (-0.424) | 7.58 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (-64) | 974 (-697) | 220 (-8) | 754 (-689) | 0.226 (+0.0899) | 0.774 (-0.0899) | 0.553 (-0.363) | 7.61 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4880 (+264) | 2253 (-1760) | 610 (+33) | 1643 (-1793) | 0.271 (+0.127) | 0.729 (-0.127) | 0.462 (-0.407) | 8.8 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 472 (+0) | 860 (-371) | 59 (+0) | 801 (-371) | 0.0686 (+0.0207) | 0.931 (-0.0206) | 1.82 (-0.788) | 2.24 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 512 (+0) | 986 (-523) | 64 (+0) | 922 (-523) | 0.0649 (+0.0225) | 0.935 (-0.0229) | 1.93 (-1.02) | 1.93 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9208 (-536) | 5106 (-3992) | 1151 (-67) | 3955 (-3925) | 0.225 (+0.0914) | 0.775 (-0.0914) | 0.555 (-0.379) | 7.98 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 608 (+0) | 1347 (-727) | 76 (+0) | 1271 (-727) | 0.0564 (+0.0198) | 0.944 (-0.0194) | 2.22 (-1.19) | 1.75 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10312 (-336) | 6037 (-4395) | 1289 (-42) | 4748 (-4353) | 0.214 (+0.0855) | 0.786 (-0.0855) | 0.585 (-0.395) | 6.74 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 696 (+0) | 1702 (-934) | 87 (+0) | 1615 (-934) | 0.0511 (+0.0181) | 0.949 (-0.0181) | 2.45 (-1.34) | 1.66 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3632 (+96) | 1856 (-1245) | 454 (+12) | 1402 (-1257) | 0.245 (+0.102) | 0.755 (-0.102) | 0.511 (-0.366) | 9.67 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (-56) | 1683 (-1302) | 334 (-7) | 1349 (-1295) | 0.198 (+0.0845) | 0.802 (-0.0845) | 0.63 (-0.46) | 4.38 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+48) | 3639 (-3053) | 881 (+6) | 2758 (-3059) | 0.242 (+0.111) | 0.758 (-0.111) | 0.516 (-0.44) | 6.32 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+1024) | 6973 (-5494) | 1961 (+128) | 5012 (-5622) | 0.281 (+0.134) | 0.719 (-0.134) | 0.444 (-0.406) | 9.08 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15256 (-104) | 7023 (-6604) | 1907 (-13) | 5116 (-6591) | 0.272 (+0.131) | 0.728 (-0.131) | 0.46 (-0.427) | 7.32 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 680 (+0) | 1767 (-953) | 85 (+0) | 1682 (-953) | 0.0481 (+0.0169) | 0.952 (-0.0171) | 2.6 (-1.4) | 1.53 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 720 (+0) | 2077 (-1015) | 90 (+0) | 1987 (-1015) | 0.0433 (+0.0142) | 0.957 (-0.0143) | 2.88 (-1.41) | 1.55 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 21472 (-1848) | 11117 (-10077) | 2684 (-231) | 8433 (-9846) | 0.241 (+0.103) | 0.759 (-0.103) | 0.518 (-0.391) | 7.24 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+160) | 1707 (-1137) | 397 (+20) | 1310 (-1157) | 0.233 (+0.0996) | 0.767 (-0.0996) | 0.537 (-0.406) | 6.67 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1384 (+56) | 1373 (-798) | 173 (+7) | 1200 (-805) | 0.126 (+0.0495) | 0.874 (-0.05) | 0.992 (-0.638) | 2.68 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1440 (-256) | 1750 (-1158) | 180 (-32) | 1570 (-1126) | 0.103 (+0.03) | 0.897 (-0.0299) | 1.22 (-0.495) | 2.28 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11816 (+728) | 5757 (-4764) | 1477 (+91) | 4280 (-4855) | 0.257 (+0.125) | 0.743 (-0.125) | 0.487 (-0.462) | 5.62 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 688 (+0) | 1973 (-919) | 86 (+0) | 1887 (-919) | 0.0436 (+0.0139) | 0.956 (-0.0136) | 2.87 (-1.33) | 1.54 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20288 (-1888) | 11138 (-10055) | 2536 (-236) | 8602 (-9819) | 0.228 (+0.0967) | 0.772 (-0.0967) | 0.549 (-0.407) | 7.25 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26072 (-1192) | 13163 (-11647) | 3259 (-149) | 9904 (-11498) | 0.248 (+0.111) | 0.752 (-0.111) | 0.505 (-0.405) | 7.35 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 856 (+0) | 2749 (-1506) | 107 (+0) | 2642 (-1506) | 0.0389 (+0.0138) | 0.961 (-0.0139) | 3.21 (-1.76) | 1.34 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+104) | 2881 (-2270) | 757 (+13) | 2124 (-2283) | 0.263 (+0.119) | 0.737 (-0.119) | 0.476 (-0.389) | 9 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14504 (+1264) | 6399 (-4828) | 1813 (+158) | 4586 (-4986) | 0.283 (+0.136) | 0.717 (-0.136) | 0.441 (-0.407) | 10 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1296 (-320) | 2018 (-1239) | 162 (-40) | 1856 (-1199) | 0.0803 (+0.0183) | 0.92 (-0.0183) | 1.56 (-0.463) | 2.1 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21328 (-504) | 10226 (-9005) | 2666 (-63) | 7560 (-8942) | 0.261 (+0.119) | 0.739 (-0.119) | 0.479 (-0.402) | 7.99 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22824 (+848) | 11139 (-8835) | 2853 (+106) | 8286 (-8941) | 0.256 (+0.118) | 0.744 (-0.118) | 0.488 (-0.421) | 6.96 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 1712 (+160) | 2998 (-1662) | 214 (+20) | 2784 (-1682) | 0.0714 (+0.0298) | 0.929 (-0.0294) | 1.75 (-1.25) | 1.56 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19224 (-1344) | 10746 (-9069) | 2403 (-168) | 8343 (-8901) | 0.224 (+0.0936) | 0.776 (-0.0936) | 0.559 (-0.404) | 4.8 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 1144 (+0) | 3359 (-1870) | 143 (+0) | 3216 (-1870) | 0.0426 (+0.0153) | 0.957 (-0.0156) | 2.94 (-1.63) | 1.31 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 1129 (-408) | 83 (+0) | 1046 (-408) | 0.0735 (+0.0195) | 0.926 (-0.0195) | 1.7 (-0.61) | 2.94 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 17104 (+1248) | 8072 (-5687) | 2138 (+156) | 5934 (-5843) | 0.265 (+0.121) | 0.735 (-0.121) | 0.472 (-0.396) | 10.5 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14712 (-400) | 7546 (-6388) | 1839 (-50) | 5707 (-6338) | 0.244 (+0.108) | 0.756 (-0.108) | 0.513 (-0.409) | 6.55 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15952 (+224) | 8227 (-6928) | 1994 (+28) | 6233 (-6956) | 0.242 (+0.112) | 0.758 (-0.112) | 0.516 (-0.448) | 5.36 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31720 (+1392) | 14825 (-11626) | 3965 (+174) | 10860 (-11800) | 0.267 (+0.124) | 0.733 (-0.124) | 0.467 (-0.405) | 7.72 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 880 (+0) | 2985 (-1628) | 110 (+0) | 2875 (-1628) | 0.0369 (+0.0131) | 0.963 (-0.0129) | 3.39 (-1.85) | 1.3 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 10856 (-2392) | 9152 (-7630) | 1357 (-299) | 7795 (-7331) | 0.148 (+0.0496) | 0.852 (-0.0493) | 0.843 (-0.427) | 3.4 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 1240 (+0) | 3872 (-2159) | 155 (+0) | 3717 (-2159) | 0.04 (+0.0143) | 0.96 (-0.014) | 3.12 (-1.74) | 1.26 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+200) | 3555 (-2497) | 894 (+25) | 2661 (-2522) | 0.251 (+0.107) | 0.749 (-0.107) | 0.497 (-0.374) | 7.94 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9600 (-208) | 5274 (-4284) | 1200 (-26) | 4074 (-4258) | 0.228 (+0.0995) | 0.772 (-0.0995) | 0.549 (-0.426) | 5.89 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11736 (-240) | 6794 (-5247) | 1467 (-30) | 5327 (-5217) | 0.216 (+0.0919) | 0.784 (-0.0919) | 0.579 (-0.431) | 5.06 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18064 (-800) | 9485 (-8343) | 2258 (-100) | 7227 (-8243) | 0.238 (+0.106) | 0.762 (-0.106) | 0.525 (-0.42) | 5.29 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 38912 (+1728) | 18409 (-14176) | 4864 (+216) | 13545 (-14392) | 0.264 (+0.121) | 0.736 (-0.121) | 0.473 (-0.403) | 8.22 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 22672 (+128) | 12208 (-9910) | 2834 (+16) | 9374 (-9926) | 0.232 (+0.105) | 0.768 (-0.105) | 0.538 (-0.443) | 4.54 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56384 (-1376) | 26511 (-24007) | 7048 (-172) | 19463 (-23835) | 0.266 (+0.123) | 0.734 (-0.123) | 0.47 (-0.405) | 8.45 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 27056 (-1144) | 14576 (-13194) | 3382 (-143) | 11194 (-13051) | 0.232 (+0.105) | 0.768 (-0.105) | 0.539 (-0.446) | 4.07 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5568 (+224) | 3248 (-2157) | 696 (+28) | 2552 (-2185) | 0.214 (+0.0903) | 0.786 (-0.0903) | 0.583 (-0.427) | 6.34 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 17248 (+1800) | 8188 (-5631) | 2156 (+225) | 6032 (-5856) | 0.263 (+0.123) | 0.737 (-0.123) | 0.475 (-0.42) | 8 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13032 (-464) | 7270 (-5909) | 1629 (-58) | 5641 (-5851) | 0.224 (+0.0961) | 0.776 (-0.0961) | 0.558 (-0.419) | 4.73 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32824 (+784) | 15324 (-13250) | 4103 (+98) | 11221 (-13348) | 0.268 (+0.128) | 0.732 (-0.128) | 0.467 (-0.425) | 7.48 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2064 (-32) | 3976 (-2045) | 258 (-4) | 3718 (-2041) | 0.0649 (+0.0214) | 0.935 (-0.0209) | 1.93 (-0.944) | 1.55 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49072 (-1088) | 23252 (-20694) | 6134 (-136) | 17118 (-20558) | 0.264 (+0.121) | 0.736 (-0.121) | 0.474 (-0.402) | 7.57 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 2536 (+24) | 5294 (-2784) | 317 (+3) | 4977 (-2787) | 0.0599 (+0.021) | 0.94 (-0.0209) | 2.09 (-1.13) | 1.48 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74392 (-2160) | 35605 (-31590) | 9299 (-270) | 26306 (-31320) | 0.261 (+0.119) | 0.739 (-0.119) | 0.479 (-0.399) | 8.69 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.2 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0125 |
| Frame reader sample issue | 0.479 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0337 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.957 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.474 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.145 |
| AV2 carry payload bytes/cycle | 3.73 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 85944 (-2576) | 45837 (-35628) | 10743 (-322) | 35094 (-35306) | 0.234 (+0.0984) | 0.766 (-0.0984) | 0.533 (-0.387) | 5.6 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 42560 (-1368) | 26370 (-21683) | 5320 (-171) | 21050 (-21512) | 0.202 (+0.0877) | 0.798 (-0.0877) | 0.62 (-0.47) | 3.22 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 9784 (-384) | 21745 (-12970) | 1223 (-48) | 20522 (-12922) | 0.0562 (+0.0196) | 0.944 (-0.0192) | 2.22 (-1.19) | 1.33 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 42200 (-3568) | 33294 (-25166) | 5275 (-446) | 28019 (-24720) | 0.158 (+0.0605) | 0.842 (-0.0604) | 0.789 (-0.491) | 2.71 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105584 (+4112) | 62615 (-36548) | 13198 (+514) | 49417 (-37062) | 0.211 (+0.0828) | 0.789 (-0.0828) | 0.593 (-0.384) | 5.1 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57192 (-3376) | 30088 (-24801) | 7149 (-422) | 22939 (-24379) | 0.238 (+0.0996) | 0.762 (-0.0996) | 0.526 (-0.38) | 6.53 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 1664 (+0) | 5916 (-3271) | 208 (+0) | 5708 (-3271) | 0.0352 (+0.0126) | 0.965 (-0.0122) | 3.56 (-1.96) | 1.28 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 3000 (+0) | 7899 (-3843) | 375 (+0) | 7524 (-3843) | 0.0475 (+0.0156) | 0.953 (-0.0155) | 2.63 (-1.28) | 1.52 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 136424 (+824) | 71795 (-51345) | 17053 (+103) | 54742 (-51448) | 0.238 (+0.0995) | 0.762 (-0.0995) | 0.526 (-0.382) | 6.6 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 77792 (-2000) | 45219 (-33596) | 9724 (-250) | 35495 (-33346) | 0.215 (+0.088) | 0.785 (-0.088) | 0.581 (-0.407) | 4.91 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.177 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0114 |
| Frame reader sample issue | 0.522 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0465 |
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
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (+0) | 260 (-31) | 38 (+0) | 222 (-31) | 0.146 (+0.0152) | 0.854 (-0.0152) | 0.855 (-0.102) | 4.06 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 338 (-64) | 57 (+0) | 281 (-64) | 0.169 (+0.0266) | 0.831 (-0.0266) | 0.741 (-0.141) | 2.64 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 460 (-99) | 80 (+0) | 380 (-99) | 0.174 (+0.0309) | 0.826 (-0.0309) | 0.719 (-0.154) | 2.4 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 545 (-139) | 103 (+0) | 442 (-139) | 0.189 (+0.038) | 0.811 (-0.038) | 0.661 (-0.169) | 2.13 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 665 (-172) | 122 (+0) | 543 (-172) | 0.183 (+0.0375) | 0.817 (-0.0375) | 0.681 (-0.177) | 2.08 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 717 (-184) | 129 (+0) | 588 (-184) | 0.18 (+0.0369) | 0.82 (-0.0369) | 0.695 (-0.178) | 1.87 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 834 (-225) | 155 (+0) | 679 (-225) | 0.186 (+0.0399) | 0.814 (-0.0399) | 0.673 (-0.181) | 1.86 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 910 (-259) | 174 (+0) | 736 (-259) | 0.191 (+0.0422) | 0.809 (-0.0422) | 0.654 (-0.186) | 1.78 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 337 (-38) | 42 (+0) | 295 (-38) | 0.125 (+0.0126) | 0.875 (-0.0126) | 1 (-0.117) | 2.63 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 535 (-123) | 93 (+0) | 442 (-123) | 0.174 (+0.0328) | 0.826 (-0.0328) | 0.719 (-0.165) | 2.09 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 703 (-159) | 114 (+0) | 589 (-159) | 0.162 (+0.0302) | 0.838 (-0.0302) | 0.771 (-0.174) | 1.83 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 854 (-219) | 152 (+0) | 702 (-219) | 0.178 (+0.036) | 0.822 (-0.036) | 0.702 (-0.18) | 1.67 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 1098 (-291) | 193 (+0) | 905 (-291) | 0.176 (+0.0368) | 0.824 (-0.0368) | 0.711 (-0.189) | 1.72 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 1230 (-339) | 222 (+0) | 1008 (-339) | 0.18 (+0.0395) | 0.82 (-0.0395) | 0.693 (-0.19) | 1.6 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 1445 (-403) | 261 (+0) | 1184 (-403) | 0.181 (+0.0396) | 0.819 (-0.0396) | 0.692 (-0.193) | 1.61 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 1576 (-457) | 292 (+0) | 1284 (-457) | 0.185 (+0.0413) | 0.815 (-0.0413) | 0.675 (-0.195) | 1.54 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 478 (-77) | 66 (+0) | 412 (-77) | 0.138 (+0.0191) | 0.862 (-0.0191) | 0.905 (-0.145) | 2.49 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 713 (-172) | 122 (+0) | 591 (-172) | 0.171 (+0.0331) | 0.829 (-0.0331) | 0.731 (-0.176) | 1.86 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 996 (-240) | 163 (+0) | 833 (-240) | 0.164 (+0.0317) | 0.836 (-0.0317) | 0.764 (-0.184) | 1.73 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 1183 (-304) | 204 (+0) | 979 (-304) | 0.172 (+0.0354) | 0.828 (-0.0354) | 0.725 (-0.186) | 1.54 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 1571 (-426) | 275 (+0) | 1296 (-426) | 0.175 (+0.037) | 0.825 (-0.037) | 0.714 (-0.194) | 1.64 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 1796 (-511) | 325 (+0) | 1471 (-511) | 0.181 (+0.04) | 0.819 (-0.04) | 0.691 (-0.196) | 1.56 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 2107 (-604) | 379 (+0) | 1728 (-604) | 0.18 (+0.0399) | 0.82 (-0.0399) | 0.695 (-0.199) | 1.57 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 2372 (-721) | 448 (+0) | 1924 (-721) | 0.189 (+0.0439) | 0.811 (-0.0439) | 0.662 (-0.201) | 1.54 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 565 (-88) | 75 (+0) | 490 (-88) | 0.133 (+0.0177) | 0.867 (-0.0177) | 0.942 (-0.148) | 2.21 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 878 (-215) | 149 (+0) | 729 (-215) | 0.17 (+0.0337) | 0.83 (-0.0337) | 0.737 (-0.18) | 1.71 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 1253 (-297) | 200 (+0) | 1053 (-297) | 0.16 (+0.0306) | 0.84 (-0.0306) | 0.783 (-0.186) | 1.63 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 1553 (-434) | 279 (+0) | 1274 (-434) | 0.18 (+0.0397) | 0.82 (-0.0397) | 0.696 (-0.194) | 1.52 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 2057 (-588) | 369 (+0) | 1688 (-588) | 0.179 (+0.0394) | 0.821 (-0.0394) | 0.697 (-0.199) | 1.61 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 2315 (-670) | 418 (+0) | 1897 (-670) | 0.181 (+0.0406) | 0.819 (-0.0406) | 0.692 (-0.201) | 1.51 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 2726 (-790) | 489 (+0) | 2237 (-790) | 0.179 (+0.0404) | 0.821 (-0.0404) | 0.697 (-0.202) | 1.52 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 3034 (-922) | 568 (+0) | 2466 (-922) | 0.187 (+0.0432) | 0.813 (-0.0432) | 0.668 (-0.203) | 1.48 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 690 (-126) | 95 (+0) | 595 (-126) | 0.138 (+0.0217) | 0.862 (-0.0217) | 0.908 (-0.162) | 2.16 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 1097 (-288) | 191 (+0) | 906 (-288) | 0.174 (+0.0361) | 0.826 (-0.0361) | 0.718 (-0.188) | 1.71 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 1547 (-382) | 248 (+0) | 1299 (-382) | 0.16 (+0.0313) | 0.84 (-0.0313) | 0.78 (-0.192) | 1.61 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 1912 (-543) | 344 (+0) | 1568 (-543) | 0.18 (+0.0399) | 0.82 (-0.0399) | 0.695 (-0.197) | 1.49 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 2487 (-696) | 433 (+0) | 2054 (-696) | 0.174 (+0.0381) | 0.826 (-0.0381) | 0.718 (-0.201) | 1.55 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 2949 (-895) | 552 (+0) | 2397 (-895) | 0.187 (+0.0432) | 0.813 (-0.0432) | 0.668 (-0.202) | 1.54 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 3392 (-997) | 612 (+0) | 2780 (-997) | 0.18 (+0.0414) | 0.82 (-0.0414) | 0.693 (-0.203) | 1.51 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 3740 (-1137) | 695 (+0) | 3045 (-1137) | 0.186 (+0.0428) | 0.814 (-0.0428) | 0.673 (-0.204) | 1.46 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 819 (-170) | 121 (+0) | 698 (-170) | 0.148 (+0.0257) | 0.852 (-0.0257) | 0.846 (-0.174) | 2.13 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 1298 (-349) | 228 (+0) | 1070 (-349) | 0.176 (+0.0377) | 0.824 (-0.0377) | 0.712 (-0.191) | 1.69 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 1795 (-446) | 285 (+0) | 1510 (-446) | 0.159 (+0.0318) | 0.841 (-0.0318) | 0.787 (-0.196) | 1.56 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2227 (-625) | 394 (+0) | 1833 (-625) | 0.177 (+0.0389) | 0.823 (-0.0389) | 0.707 (-0.198) | 1.45 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 2940 (-831) | 513 (+0) | 2427 (-831) | 0.174 (+0.0385) | 0.826 (-0.0385) | 0.716 (-0.203) | 1.53 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 3421 (-1023) | 627 (+0) | 2794 (-1023) | 0.183 (+0.0423) | 0.817 (-0.0423) | 0.682 (-0.204) | 1.48 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 4023 (-1180) | 722 (+0) | 3301 (-1180) | 0.179 (+0.0405) | 0.821 (-0.0405) | 0.697 (-0.204) | 1.5 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 4431 (-1339) | 814 (+0) | 3617 (-1339) | 0.184 (+0.0427) | 0.816 (-0.0427) | 0.68 (-0.206) | 1.44 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 921 (-189) | 134 (+0) | 787 (-189) | 0.145 (+0.0245) | 0.855 (-0.0245) | 0.859 (-0.181) | 2.06 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 1473 (-400) | 259 (+0) | 1214 (-400) | 0.176 (+0.0378) | 0.824 (-0.0378) | 0.711 (-0.193) | 1.64 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 2089 (-527) | 335 (+0) | 1754 (-527) | 0.16 (+0.0324) | 0.84 (-0.0324) | 0.779 (-0.197) | 1.55 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 2574 (-740) | 461 (+0) | 2113 (-740) | 0.179 (+0.0401) | 0.821 (-0.0401) | 0.698 (-0.201) | 1.44 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 3382 (-951) | 587 (+0) | 2795 (-951) | 0.174 (+0.0386) | 0.826 (-0.0386) | 0.72 (-0.203) | 1.51 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 4010 (-1218) | 743 (+0) | 3267 (-1218) | 0.185 (+0.0433) | 0.815 (-0.0433) | 0.675 (-0.205) | 1.49 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 4670 (-1375) | 838 (+0) | 3832 (-1375) | 0.179 (+0.0404) | 0.821 (-0.0404) | 0.697 (-0.205) | 1.49 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 5143 (-1567) | 950 (+0) | 4193 (-1567) | 0.185 (+0.0427) | 0.815 (-0.0427) | 0.677 (-0.206) | 1.43 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 1015 (-211) | 148 (+0) | 867 (-211) | 0.146 (+0.0248) | 0.854 (-0.0248) | 0.857 (-0.183) | 1.98 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 1621 (-435) | 280 (+0) | 1341 (-435) | 0.173 (+0.0367) | 0.827 (-0.0367) | 0.724 (-0.194) | 1.58 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2395 (-625) | 394 (+0) | 2001 (-625) | 0.165 (+0.0345) | 0.835 (-0.0345) | 0.76 (-0.198) | 1.56 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 2894 (-831) | 514 (+0) | 2380 (-831) | 0.178 (+0.0396) | 0.822 (-0.0396) | 0.704 (-0.202) | 1.41 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 3821 (-1086) | 665 (+0) | 3156 (-1086) | 0.174 (+0.038) | 0.826 (-0.038) | 0.718 (-0.204) | 1.49 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 4469 (-1334) | 812 (+0) | 3657 (-1334) | 0.182 (+0.0417) | 0.818 (-0.0417) | 0.688 (-0.205) | 1.45 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 5340 (-1593) | 968 (+0) | 4372 (-1593) | 0.181 (+0.0413) | 0.819 (-0.0413) | 0.69 (-0.205) | 1.49 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 5857 (-1803) | 1090 (+0) | 4767 (-1803) | 0.186 (+0.0441) | 0.814 (-0.0441) | 0.672 (-0.206) | 1.43 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.171 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0107 |
| Frame reader sample issue | 0.546 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0 |
| Input FIFO nonempty rate | 0.0585 |
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
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 11724 (-3279) | 2123 (+0) | 9601 (-3279) | 0.181 (+0.0391) | 0.819 (-0.0391) | 0.69 (-0.193) | 1.43 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 12350 (-2802) | 2145 (+0) | 10205 (-2802) | 0.174 (+0.0317) | 0.826 (-0.0317) | 0.72 (-0.163) | 1.51 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 23083 (-5838) | 3977 (+0) | 19106 (-5838) | 0.172 (+0.0343) | 0.828 (-0.0343) | 0.726 (-0.183) | 1.41 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 18144 (-4055) | 3111 (+0) | 15033 (-4055) | 0.171 (+0.0315) | 0.829 (-0.0315) | 0.729 (-0.163) | 1.48 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 17659 (-3462) | 2827 (+0) | 14832 (-3462) | 0.16 (+0.0261) | 0.84 (-0.0261) | 0.781 (-0.153) | 1.44 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 7081 (-1840) | 1227 (+0) | 5854 (-1840) | 0.173 (+0.0353) | 0.827 (-0.0353) | 0.721 (-0.188) | 1.54 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 6856 (-1835) | 1242 (+0) | 5614 (-1835) | 0.181 (+0.0382) | 0.819 (-0.0382) | 0.69 (-0.185) | 1.49 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 8021 (-2217) | 1423 (+0) | 6598 (-2217) | 0.177 (+0.0384) | 0.823 (-0.0384) | 0.705 (-0.194) | 1.55 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 16923 (-3594) | 2819 (+0) | 14104 (-3594) | 0.167 (+0.0296) | 0.833 (-0.0296) | 0.75 (-0.16) | 1.56 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 14195 (-3376) | 2388 (+0) | 11807 (-3376) | 0.168 (+0.0322) | 0.832 (-0.0322) | 0.743 (-0.177) | 1.54 |
