# AV2 RTL Output Utilization Baselines

This report records the latest RTL simulation throughput counters. Older
measurement sections are intentionally left to git history so this file
stays focused on the current optimization baseline and immediate deltas.

Metric definitions:

- `cycles/input pixel`: total measured cycles divided by `width * height * frames`.
  This is the primary top-level throughput metric.
- `output_utilization`: accepted output bytes divided by total measured cycles.
- `bubble_rate`: `1 - output_utilization`.
- `cycles/bit`: total measured cycles divided by RTL bitstream bits.
- Internal block utilization is testbench instrumentation. It is used to find
  pipeline starvation/backpressure and is not part of the codec bitstream contract.
- Bubble rate is retained as a diagnostic and delta metric. Highly compressed
  streams can have high bubble rate even when cycles/input pixel is healthy.

## Streamed entropy output

Baseline and current sources:

- Baseline Git SHA: `7383aee7b77230a85bdd86c5cf151008ba7de553`
- Current validated source Git SHA: `ccc1e283b43c5833c276605f1f583d9c1476f4b3`
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
| `screenshot-sweep-444` | 64 | 763928 (+0) | 681162 (+316466) | 95491 (+0) | 585671 (+316466) | 0.14 (-0.122) | 0.86 (+0.122) | 0.892 (+0.415) | 8.21 |
| `screenshot-multictu-444` | 10 | 579256 (+0) | 584001 (+269837) | 72407 (+0) | 511594 (+269837) | 0.124 (-0.106) | 0.876 (+0.106) | 1.01 (+0.466) | 6.36 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 142376 (+65477) | 22808 (+0) | 119568 (+65477) | 0.16 (-0.137) | 0.84 (+0.137) | 0.78 (+0.359) | 1.72 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 146179 (+66353) | 23282 (+0) | 122897 (+66353) | 0.159 (-0.133) | 0.841 (+0.133) | 0.785 (+0.356) | 1.59 |
| `multiframe-smoke` | 4 | 19680 (+0) | 22496 (+10571) | 2460 (+0) | 20036 (+10571) | 0.109 (-0.0966) | 0.891 (+0.0966) | 1.14 (+0.537) | 4.69 |

### Screenshot 4:4:4 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.14 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00881 |
| Frame reader sample issue | 10.3 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.942 |
| Input FIFO nonempty rate | 0.03 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.94 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.495 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.152 |
| AV2 carry payload bytes/cycle | 1.63e+03 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 535 (+249) | 43 (+0) | 492 (+249) | 0.0804 (-0.0696) | 0.92 (+0.0696) | 1.56 (+0.724) | 8.36 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 1581 (+719) | 248 (+0) | 1333 (+719) | 0.157 (-0.131) | 0.843 (+0.131) | 0.797 (+0.363) | 12.4 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+0) | 822 (+391) | 52 (+0) | 770 (+391) | 0.0633 (-0.0577) | 0.937 (+0.0577) | 1.98 (+0.936) | 4.28 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 1170 (+554) | 92 (+0) | 1078 (+554) | 0.0786 (-0.0704) | 0.921 (+0.0704) | 1.59 (+0.753) | 4.57 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 1122 (+538) | 60 (+0) | 1062 (+538) | 0.0535 (-0.0495) | 0.947 (+0.0495) | 2.34 (+1.12) | 3.51 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 1265 (+607) | 65 (+0) | 1200 (+607) | 0.0514 (-0.0474) | 0.949 (+0.0476) | 2.43 (+1.16) | 3.29 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 5687 (+2620) | 854 (+0) | 4833 (+2620) | 0.15 (-0.128) | 0.85 (+0.128) | 0.832 (+0.383) | 12.7 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 6279 (+2917) | 852 (+0) | 5427 (+2917) | 0.136 (-0.117) | 0.864 (+0.117) | 0.921 (+0.428) | 12.3 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 1525 (+699) | 220 (+0) | 1305 (+699) | 0.144 (-0.122) | 0.856 (+0.122) | 0.866 (+0.397) | 11.9 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4872 (+0) | 3686 (+1683) | 609 (+0) | 3077 (+1683) | 0.165 (-0.139) | 0.835 (+0.139) | 0.757 (+0.346) | 14.4 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 528 (+0) | 1291 (+617) | 66 (+0) | 1225 (+617) | 0.0511 (-0.0468) | 0.949 (+0.0469) | 2.45 (+1.17) | 3.36 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 592 (+0) | 1577 (+759) | 74 (+0) | 1503 (+759) | 0.0469 (-0.0436) | 0.953 (+0.0431) | 2.66 (+1.28) | 3.08 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9456 (+0) | 8301 (+3847) | 1182 (+0) | 7119 (+3847) | 0.142 (-0.123) | 0.858 (+0.123) | 0.878 (+0.407) | 13 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 744 (+0) | 2330 (+1157) | 93 (+0) | 2237 (+1157) | 0.0399 (-0.0394) | 0.96 (+0.0391) | 3.13 (+1.55) | 3.03 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10344 (+0) | 9578 (+4455) | 1293 (+0) | 8285 (+4455) | 0.135 (-0.117) | 0.865 (+0.117) | 0.926 (+0.431) | 10.7 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 888 (+0) | 3137 (+1557) | 111 (+0) | 3026 (+1557) | 0.0354 (-0.0349) | 0.965 (+0.0346) | 3.53 (+1.75) | 3.06 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3648 (+0) | 2990 (+1369) | 456 (+0) | 2534 (+1369) | 0.153 (-0.128) | 0.847 (+0.128) | 0.82 (+0.376) | 15.6 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 2556 (+1184) | 334 (+0) | 2222 (+1184) | 0.131 (-0.112) | 0.869 (+0.112) | 0.957 (+0.444) | 6.66 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+0) | 5661 (+2602) | 881 (+0) | 4780 (+2602) | 0.156 (-0.132) | 0.844 (+0.132) | 0.803 (+0.369) | 9.83 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 11422 (+5212) | 1961 (+0) | 9461 (+5212) | 0.172 (-0.144) | 0.828 (+0.144) | 0.728 (+0.332) | 14.9 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15248 (+0) | 11205 (+5118) | 1906 (+0) | 9299 (+5118) | 0.17 (-0.143) | 0.83 (+0.143) | 0.735 (+0.336) | 11.7 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 960 (+0) | 3236 (+1602) | 120 (+0) | 3116 (+1602) | 0.0371 (-0.0363) | 0.963 (+0.0359) | 3.37 (+1.67) | 2.81 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1064 (+0) | 3863 (+1909) | 133 (+0) | 3730 (+1909) | 0.0344 (-0.0337) | 0.966 (+0.0336) | 3.63 (+1.79) | 2.87 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 22424 (+0) | 18203 (+8393) | 2803 (+0) | 15400 (+8393) | 0.154 (-0.132) | 0.846 (+0.132) | 0.812 (+0.375) | 11.9 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 2550 (+1165) | 397 (+0) | 2153 (+1165) | 0.156 (-0.131) | 0.844 (+0.131) | 0.803 (+0.367) | 9.96 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (+0) | 2082 (+990) | 176 (+0) | 1906 (+990) | 0.0845 (-0.0765) | 0.915 (+0.0765) | 1.48 (+0.703) | 4.07 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1824 (+0) | 2908 (+1390) | 228 (+0) | 2680 (+1390) | 0.0784 (-0.0716) | 0.922 (+0.0716) | 1.59 (+0.762) | 3.79 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11896 (+0) | 9444 (+4340) | 1487 (+0) | 7957 (+4340) | 0.157 (-0.134) | 0.843 (+0.134) | 0.794 (+0.365) | 9.22 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1032 (+0) | 3535 (+1749) | 129 (+0) | 3406 (+1749) | 0.0365 (-0.0357) | 0.964 (+0.0355) | 3.43 (+1.7) | 2.76 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20456 (+0) | 18097 (+8403) | 2557 (+0) | 15540 (+8403) | 0.141 (-0.123) | 0.859 (+0.123) | 0.885 (+0.411) | 11.8 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26008 (+0) | 20981 (+9693) | 3251 (+0) | 17730 (+9693) | 0.155 (-0.133) | 0.845 (+0.133) | 0.807 (+0.373) | 11.7 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1480 (+0) | 5933 (+2934) | 185 (+0) | 5748 (+2934) | 0.0312 (-0.0305) | 0.969 (+0.0308) | 4.01 (+1.98) | 2.9 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 4535 (+2071) | 757 (+0) | 3778 (+2071) | 0.167 (-0.14) | 0.833 (+0.14) | 0.749 (+0.342) | 14.2 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14872 (+0) | 10876 (+4961) | 1859 (+0) | 9017 (+4961) | 0.171 (-0.143) | 0.829 (+0.143) | 0.731 (+0.333) | 17 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1464 (+0) | 3105 (+1498) | 183 (+0) | 2922 (+1498) | 0.0589 (-0.0551) | 0.941 (+0.0551) | 2.12 (+1.02) | 3.23 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21616 (+0) | 16756 (+7692) | 2702 (+0) | 14054 (+7692) | 0.161 (-0.137) | 0.839 (+0.137) | 0.775 (+0.356) | 13.1 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22944 (+0) | 18017 (+8284) | 2868 (+0) | 15149 (+8284) | 0.159 (-0.136) | 0.841 (+0.136) | 0.785 (+0.361) | 11.3 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (+0) | 5594 (+2742) | 269 (+0) | 5325 (+2742) | 0.0481 (-0.0462) | 0.952 (+0.0459) | 2.6 (+1.27) | 2.91 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19784 (+0) | 17916 (+8331) | 2473 (+0) | 15443 (+8331) | 0.138 (-0.12) | 0.862 (+0.12) | 0.906 (+0.422) | 8 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2032 (+0) | 7277 (+3590) | 254 (+0) | 7023 (+3590) | 0.0349 (-0.034) | 0.965 (+0.0341) | 3.58 (+1.77) | 2.84 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+0) | 1348 (+644) | 83 (+0) | 1265 (+644) | 0.0616 (-0.0564) | 0.938 (+0.0564) | 2.03 (+0.97) | 3.51 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 16960 (+0) | 13378 (+6147) | 2120 (+0) | 11258 (+6147) | 0.158 (-0.135) | 0.842 (+0.135) | 0.789 (+0.363) | 17.4 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14800 (+0) | 12093 (+5575) | 1850 (+0) | 10243 (+5575) | 0.153 (-0.131) | 0.847 (+0.131) | 0.817 (+0.377) | 10.5 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15920 (+0) | 13094 (+6037) | 1990 (+0) | 11104 (+6037) | 0.152 (-0.13) | 0.848 (+0.13) | 0.822 (+0.379) | 8.52 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31960 (+0) | 23973 (+10979) | 3995 (+0) | 19978 (+10979) | 0.167 (-0.14) | 0.833 (+0.14) | 0.75 (+0.343) | 12.5 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1624 (+0) | 6004 (+2963) | 203 (+0) | 5801 (+2963) | 0.0338 (-0.033) | 0.966 (+0.0332) | 3.7 (+1.83) | 2.61 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 11432 (+0) | 14815 (+7064) | 1429 (+0) | 13386 (+7064) | 0.0965 (-0.0875) | 0.904 (+0.0875) | 1.3 (+0.618) | 5.51 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2328 (+0) | 8408 (+4147) | 291 (+0) | 8117 (+4147) | 0.0346 (-0.0337) | 0.965 (+0.0334) | 3.61 (+1.78) | 2.74 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 5445 (+2491) | 894 (+0) | 4551 (+2491) | 0.164 (-0.139) | 0.836 (+0.139) | 0.761 (+0.348) | 12.2 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9664 (+0) | 8575 (+3976) | 1208 (+0) | 7367 (+3976) | 0.141 (-0.122) | 0.859 (+0.122) | 0.887 (+0.411) | 9.57 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11904 (+0) | 10740 (+4988) | 1488 (+0) | 9252 (+4988) | 0.139 (-0.12) | 0.861 (+0.12) | 0.902 (+0.419) | 7.99 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18376 (+0) | 15589 (+7211) | 2297 (+0) | 13292 (+7211) | 0.147 (-0.127) | 0.853 (+0.127) | 0.848 (+0.392) | 8.7 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 36832 (+0) | 28623 (+13152) | 4604 (+0) | 24019 (+13152) | 0.161 (-0.137) | 0.839 (+0.137) | 0.777 (+0.357) | 12.8 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27208 (+0) | 23100 (+10711) | 3401 (+0) | 19699 (+10711) | 0.147 (-0.128) | 0.853 (+0.128) | 0.849 (+0.394) | 8.59 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56456 (+0) | 43029 (+19740) | 7057 (+0) | 35972 (+19740) | 0.164 (-0.139) | 0.836 (+0.139) | 0.762 (+0.349) | 13.7 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28088 (+0) | 25229 (+11727) | 3511 (+0) | 21718 (+11727) | 0.139 (-0.121) | 0.861 (+0.121) | 0.898 (+0.417) | 7.04 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5640 (+0) | 4892 (+2260) | 705 (+0) | 4187 (+2260) | 0.144 (-0.124) | 0.856 (+0.124) | 0.867 (+0.4) | 9.55 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 16376 (+0) | 12761 (+5861) | 2047 (+0) | 10714 (+5861) | 0.16 (-0.137) | 0.84 (+0.137) | 0.779 (+0.358) | 12.5 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13264 (+0) | 11857 (+5505) | 1658 (+0) | 10199 (+5505) | 0.14 (-0.121) | 0.86 (+0.121) | 0.894 (+0.415) | 7.72 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32936 (+0) | 25089 (+11506) | 4117 (+0) | 20972 (+11506) | 0.164 (-0.139) | 0.836 (+0.139) | 0.762 (+0.35) | 12.3 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2824 (+0) | 7238 (+3542) | 353 (+0) | 6885 (+3542) | 0.0488 (-0.0467) | 0.951 (+0.0472) | 2.56 (+1.25) | 2.83 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49024 (+0) | 38012 (+17467) | 6128 (+0) | 31884 (+17467) | 0.161 (-0.137) | 0.839 (+0.137) | 0.775 (+0.356) | 12.4 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3864 (+0) | 10600 (+5195) | 483 (+0) | 10117 (+5195) | 0.0456 (-0.0438) | 0.954 (+0.0434) | 2.74 (+1.34) | 2.96 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74368 (+0) | 58642 (+26987) | 9296 (+0) | 49346 (+26987) | 0.159 (-0.135) | 0.841 (+0.135) | 0.789 (+0.363) | 14.3 |

### Screenshot 4:4:4 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.124 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00795 |
| Frame reader sample issue | 15.5 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.944 |
| Input FIFO nonempty rate | 0.0457 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.936 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0.663 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0.164 |
| AV2 carry payload bytes/cycle | 1.42e+03 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 86760 (+0) | 75937 (+34590) | 10845 (+0) | 65092 (+34590) | 0.143 (-0.119) | 0.857 (+0.119) | 0.875 (+0.398) | 9.27 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 44520 (+0) | 46873 (+21730) | 5565 (+0) | 41308 (+21730) | 0.119 (-0.102) | 0.881 (+0.102) | 1.05 (+0.488) | 5.72 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 15912 (+0) | 47257 (+23071) | 1989 (+0) | 45268 (+23071) | 0.0421 (-0.0401) | 0.958 (+0.0399) | 2.97 (+1.45) | 2.88 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45032 (+0) | 58340 (+27460) | 5629 (+0) | 52711 (+27460) | 0.0965 (-0.0855) | 0.904 (+0.0855) | 1.3 (+0.61) | 4.75 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105520 (+0) | 95194 (+43524) | 13190 (+0) | 82004 (+43524) | 0.139 (-0.116) | 0.861 (+0.116) | 0.902 (+0.412) | 7.75 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57616 (+0) | 47816 (+21667) | 7202 (+0) | 40614 (+21667) | 0.151 (-0.124) | 0.849 (+0.124) | 0.83 (+0.376) | 10.4 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3112 (+0) | 12341 (+6079) | 389 (+0) | 11952 (+6079) | 0.0315 (-0.0306) | 0.968 (+0.0305) | 3.97 (+1.96) | 2.68 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4504 (+0) | 14872 (+7331) | 563 (+0) | 14309 (+7331) | 0.0379 (-0.0368) | 0.962 (+0.0371) | 3.3 (+1.63) | 2.87 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 137280 (+0) | 112509 (+50971) | 17160 (+0) | 95349 (+50971) | 0.153 (-0.126) | 0.847 (+0.126) | 0.82 (+0.372) | 10.3 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79000 (+0) | 72862 (+33414) | 9875 (+0) | 62987 (+33414) | 0.136 (-0.114) | 0.864 (+0.114) | 0.922 (+0.423) | 7.91 |

### RaceHorses 4:2:0 Full Sweep

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.16 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0102 |
| Frame reader sample issue | 11.7 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0 |
| AV2 carry payload bytes/cycle | 268 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_crop_8x8_1f_yuv420p8.yuv | PASS | 304 (+0) | 346 (+155) | 38 (+0) | 308 (+155) | 0.11 (-0.0892) | 0.89 (+0.0892) | 1.14 (+0.51) | 5.41 |
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 437 (+196) | 57 (+0) | 380 (+196) | 0.13 (-0.107) | 0.87 (+0.107) | 0.958 (+0.429) | 3.41 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 549 (+245) | 80 (+0) | 469 (+245) | 0.146 (-0.117) | 0.854 (+0.117) | 0.858 (+0.383) | 2.86 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 669 (+300) | 103 (+0) | 566 (+300) | 0.154 (-0.125) | 0.846 (+0.125) | 0.812 (+0.364) | 2.61 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 798 (+360) | 122 (+0) | 676 (+360) | 0.153 (-0.126) | 0.847 (+0.126) | 0.818 (+0.369) | 2.49 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 843 (+380) | 129 (+0) | 714 (+380) | 0.153 (-0.126) | 0.847 (+0.126) | 0.817 (+0.368) | 2.2 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 969 (+437) | 155 (+0) | 814 (+437) | 0.16 (-0.131) | 0.84 (+0.131) | 0.781 (+0.352) | 2.16 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 1078 (+488) | 174 (+0) | 904 (+488) | 0.161 (-0.134) | 0.839 (+0.134) | 0.774 (+0.35) | 2.11 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 386 (+175) | 42 (+0) | 344 (+175) | 0.109 (-0.0902) | 0.891 (+0.0902) | 1.15 (+0.521) | 3.02 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 628 (+283) | 93 (+0) | 535 (+283) | 0.148 (-0.122) | 0.852 (+0.122) | 0.844 (+0.38) | 2.45 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 772 (+350) | 114 (+0) | 658 (+350) | 0.148 (-0.122) | 0.852 (+0.122) | 0.846 (+0.383) | 2.01 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 979 (+442) | 152 (+0) | 827 (+442) | 0.155 (-0.128) | 0.845 (+0.128) | 0.805 (+0.363) | 1.91 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 1248 (+581) | 193 (+0) | 1055 (+581) | 0.155 (-0.134) | 0.845 (+0.134) | 0.808 (+0.376) | 1.95 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 1410 (+661) | 222 (+0) | 1188 (+661) | 0.157 (-0.139) | 0.843 (+0.139) | 0.794 (+0.372) | 1.84 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 1713 (+801) | 261 (+0) | 1452 (+801) | 0.152 (-0.134) | 0.848 (+0.134) | 0.82 (+0.383) | 1.91 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 1895 (+889) | 292 (+0) | 1603 (+889) | 0.154 (-0.136) | 0.846 (+0.136) | 0.811 (+0.38) | 1.85 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 511 (+227) | 66 (+0) | 445 (+227) | 0.129 (-0.103) | 0.871 (+0.103) | 0.968 (+0.43) | 2.66 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 812 (+367) | 122 (+0) | 690 (+367) | 0.15 (-0.124) | 0.85 (+0.124) | 0.832 (+0.376) | 2.11 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 1068 (+486) | 163 (+0) | 905 (+486) | 0.153 (-0.127) | 0.847 (+0.127) | 0.819 (+0.373) | 1.85 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 1308 (+592) | 204 (+0) | 1104 (+592) | 0.156 (-0.129) | 0.844 (+0.129) | 0.801 (+0.362) | 1.7 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 1743 (+807) | 275 (+0) | 1468 (+807) | 0.158 (-0.136) | 0.842 (+0.136) | 0.792 (+0.367) | 1.82 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 2028 (+942) | 325 (+0) | 1703 (+942) | 0.16 (-0.139) | 0.84 (+0.139) | 0.78 (+0.362) | 1.76 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 2422 (+1129) | 379 (+0) | 2043 (+1129) | 0.156 (-0.137) | 0.844 (+0.137) | 0.799 (+0.373) | 1.8 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 2784 (+1294) | 448 (+0) | 2336 (+1294) | 0.161 (-0.14) | 0.839 (+0.14) | 0.777 (+0.361) | 1.81 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 569 (+255) | 75 (+0) | 494 (+255) | 0.132 (-0.107) | 0.868 (+0.107) | 0.948 (+0.425) | 2.22 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 965 (+436) | 149 (+0) | 816 (+436) | 0.154 (-0.128) | 0.846 (+0.128) | 0.81 (+0.366) | 1.88 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 1296 (+586) | 200 (+0) | 1096 (+586) | 0.154 (-0.128) | 0.846 (+0.128) | 0.81 (+0.366) | 1.69 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 1721 (+781) | 279 (+0) | 1442 (+781) | 0.162 (-0.135) | 0.838 (+0.135) | 0.771 (+0.35) | 1.68 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 2274 (+1054) | 369 (+0) | 1905 (+1054) | 0.162 (-0.14) | 0.838 (+0.14) | 0.77 (+0.357) | 1.78 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 2569 (+1191) | 418 (+0) | 2151 (+1191) | 0.163 (-0.14) | 0.837 (+0.14) | 0.768 (+0.356) | 1.67 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 3115 (+1448) | 489 (+0) | 2626 (+1448) | 0.157 (-0.136) | 0.843 (+0.136) | 0.796 (+0.37) | 1.74 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 3494 (+1617) | 568 (+0) | 2926 (+1617) | 0.163 (-0.14) | 0.837 (+0.14) | 0.769 (+0.356) | 1.71 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 710 (+324) | 95 (+0) | 615 (+324) | 0.134 (-0.112) | 0.866 (+0.112) | 0.934 (+0.426) | 2.22 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 1217 (+553) | 191 (+0) | 1026 (+553) | 0.157 (-0.131) | 0.843 (+0.131) | 0.796 (+0.361) | 1.9 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 1603 (+730) | 248 (+0) | 1355 (+730) | 0.155 (-0.129) | 0.845 (+0.129) | 0.808 (+0.368) | 1.67 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 2111 (+960) | 344 (+0) | 1767 (+960) | 0.163 (-0.136) | 0.837 (+0.136) | 0.767 (+0.349) | 1.65 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 2724 (+1268) | 433 (+0) | 2291 (+1268) | 0.159 (-0.138) | 0.841 (+0.138) | 0.786 (+0.366) | 1.7 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 3323 (+1537) | 552 (+0) | 2771 (+1537) | 0.166 (-0.143) | 0.834 (+0.143) | 0.752 (+0.348) | 1.73 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 3853 (+1789) | 612 (+0) | 3241 (+1789) | 0.159 (-0.138) | 0.841 (+0.138) | 0.787 (+0.365) | 1.72 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 4262 (+1970) | 695 (+0) | 3567 (+1970) | 0.163 (-0.14) | 0.837 (+0.14) | 0.767 (+0.355) | 1.66 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 838 (+380) | 121 (+0) | 717 (+380) | 0.144 (-0.12) | 0.856 (+0.12) | 0.866 (+0.393) | 2.18 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 1432 (+652) | 228 (+0) | 1204 (+652) | 0.159 (-0.133) | 0.841 (+0.133) | 0.785 (+0.357) | 1.86 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 1829 (+835) | 285 (+0) | 1544 (+835) | 0.156 (-0.131) | 0.844 (+0.131) | 0.802 (+0.366) | 1.59 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2418 (+1099) | 394 (+0) | 2024 (+1099) | 0.163 (-0.136) | 0.837 (+0.136) | 0.767 (+0.349) | 1.57 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 3187 (+1478) | 513 (+0) | 2674 (+1478) | 0.161 (-0.139) | 0.839 (+0.139) | 0.777 (+0.361) | 1.66 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 3763 (+1735) | 627 (+0) | 3136 (+1735) | 0.167 (-0.142) | 0.833 (+0.142) | 0.75 (+0.346) | 1.63 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 4534 (+2099) | 722 (+0) | 3812 (+2099) | 0.159 (-0.138) | 0.841 (+0.138) | 0.785 (+0.363) | 1.69 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 5027 (+2325) | 814 (+0) | 4213 (+2325) | 0.162 (-0.139) | 0.838 (+0.139) | 0.772 (+0.357) | 1.64 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 917 (+413) | 134 (+0) | 783 (+413) | 0.146 (-0.12) | 0.854 (+0.12) | 0.855 (+0.385) | 2.05 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 1594 (+720) | 259 (+0) | 1335 (+720) | 0.162 (-0.134) | 0.838 (+0.134) | 0.769 (+0.347) | 1.78 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 2124 (+968) | 335 (+0) | 1789 (+968) | 0.158 (-0.132) | 0.842 (+0.132) | 0.793 (+0.362) | 1.58 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 2790 (+1269) | 461 (+0) | 2329 (+1269) | 0.165 (-0.138) | 0.835 (+0.138) | 0.757 (+0.345) | 1.56 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 3605 (+1667) | 587 (+0) | 3018 (+1667) | 0.163 (-0.14) | 0.837 (+0.14) | 0.768 (+0.355) | 1.61 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 4429 (+2041) | 743 (+0) | 3686 (+2041) | 0.168 (-0.143) | 0.832 (+0.143) | 0.745 (+0.343) | 1.65 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 5189 (+2395) | 838 (+0) | 4351 (+2395) | 0.161 (-0.139) | 0.839 (+0.139) | 0.774 (+0.357) | 1.65 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 5820 (+2685) | 950 (+0) | 4870 (+2685) | 0.163 (-0.14) | 0.837 (+0.14) | 0.766 (+0.354) | 1.62 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 985 (+446) | 148 (+0) | 837 (+446) | 0.15 (-0.125) | 0.85 (+0.125) | 0.832 (+0.377) | 1.92 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 1721 (+781) | 280 (+0) | 1441 (+781) | 0.163 (-0.135) | 0.837 (+0.135) | 0.768 (+0.348) | 1.68 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 2442 (+1111) | 394 (+0) | 2048 (+1111) | 0.161 (-0.135) | 0.839 (+0.135) | 0.775 (+0.353) | 1.59 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 3107 (+1415) | 514 (+0) | 2593 (+1415) | 0.165 (-0.139) | 0.835 (+0.139) | 0.756 (+0.345) | 1.52 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 4062 (+1878) | 665 (+0) | 3397 (+1878) | 0.164 (-0.14) | 0.836 (+0.14) | 0.764 (+0.353) | 1.59 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 4859 (+2240) | 812 (+0) | 4047 (+2240) | 0.167 (-0.143) | 0.833 (+0.143) | 0.748 (+0.345) | 1.58 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 5867 (+2702) | 968 (+0) | 4899 (+2702) | 0.165 (-0.141) | 0.835 (+0.141) | 0.758 (+0.349) | 1.64 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 6635 (+3057) | 1090 (+0) | 5545 (+3057) | 0.164 (-0.141) | 0.836 (+0.141) | 0.761 (+0.351) | 1.62 |

### RaceHorses 4:2:0 Multi-CTU And Partial Crops

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.159 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.0107 |
| Frame reader sample issue | 18.1 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 1 |
| Input FIFO nonempty rate | 0 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 1.07 |
| AV2 chroma BDPCM op issue | 1 |
| AV2 chroma zero-TXB shortcut rate | 0 |
| AV2 luma residual op issue | 1 |
| AV2 prefetch useful fraction | 0 |
| AV2 carry payload bytes/cycle | 410 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 12859 (+5798) | 2123 (+0) | 10736 (+5798) | 0.165 (-0.136) | 0.835 (+0.136) | 0.757 (+0.341) | 1.57 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 13015 (+5870) | 2145 (+0) | 10870 (+5870) | 0.165 (-0.135) | 0.835 (+0.135) | 0.758 (+0.342) | 1.59 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 24921 (+11285) | 3977 (+0) | 20944 (+11285) | 0.16 (-0.132) | 0.84 (+0.132) | 0.783 (+0.354) | 1.52 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 19015 (+8585) | 3111 (+0) | 15904 (+8585) | 0.164 (-0.134) | 0.836 (+0.134) | 0.764 (+0.345) | 1.55 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 18441 (+8389) | 2827 (+0) | 15614 (+8389) | 0.153 (-0.128) | 0.847 (+0.128) | 0.815 (+0.371) | 1.5 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 7753 (+3525) | 1227 (+0) | 6526 (+3525) | 0.158 (-0.132) | 0.842 (+0.132) | 0.79 (+0.359) | 1.68 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 7605 (+3446) | 1242 (+0) | 6363 (+3446) | 0.163 (-0.136) | 0.837 (+0.136) | 0.765 (+0.346) | 1.65 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 9107 (+4185) | 1423 (+0) | 7684 (+4185) | 0.156 (-0.133) | 0.844 (+0.133) | 0.8 (+0.368) | 1.76 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 18339 (+8387) | 2819 (+0) | 15520 (+8387) | 0.154 (-0.129) | 0.846 (+0.129) | 0.813 (+0.372) | 1.69 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 15124 (+6883) | 2388 (+0) | 12736 (+6883) | 0.158 (-0.132) | 0.842 (+0.132) | 0.792 (+0.361) | 1.64 |

### Multi-Frame Smoke

| Block/probe | Utilization/rate |
|---|---:|
| Final byte output | 0.109 |
| AXI write accepted-beat readiness | 1 |
| AXI write bus occupancy | 0.00689 |
| Frame reader sample issue | 5.31 |
| Reader-to-FIFO handshake | 1 |
| Input FIFO-to-core handshake | 0.959 |
| Input FIFO nonempty rate | 0.0597 |
| Input FIFO full rate | 0 |
| AV2 leaf entropy op issue | 0.942 |
| AV2 chroma BDPCM op issue | 0.749 |
| AV2 chroma zero-TXB shortcut rate | 0.445 |
| AV2 luma residual op issue | 0.749 |
| AV2 prefetch useful fraction | 0.232 |
| AV2 carry payload bytes/cycle | 278 |

Per-vector top-level metrics:

| Vector | Status | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| multiframe_black_420_16x16_2f_yuv420p8.yuv | PASS | 1936 (+0) | 1747 (+797) | 242 (+0) | 1505 (+797) | 0.139 (-0.116) | 0.861 (+0.116) | 0.902 (+0.411) | 3.41 |
| multiframe_black_tall_420_8x24_5f_yuv420p8.yuv | PASS | 3840 (+0) | 3908 (+1809) | 480 (+0) | 3428 (+1809) | 0.123 (-0.106) | 0.877 (+0.106) | 1.02 (+0.471) | 4.07 |
| multiframe_motion_444_16x8_2f_yuv444p8.yuv | PASS | 1408 (+0) | 1808 (+852) | 176 (+0) | 1632 (+852) | 0.0973 (-0.0867) | 0.903 (+0.0867) | 1.28 (+0.605) | 7.06 |
| multiframe_motion_wide_444_48x32_2f_yuv444p8.yuv | PASS | 12496 (+0) | 15033 (+7113) | 1562 (+0) | 13471 (+7113) | 0.104 (-0.0931) | 0.896 (+0.0931) | 1.2 (+0.569) | 4.89 |
