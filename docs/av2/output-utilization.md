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

## AV2 analyzer overlap and IBC safety checkpoint

Baseline and current sources:

- Baseline Git SHA: `509b74f7670b9bfff61209f0779c12e256b00f07`
- Current validated source Git SHA: `8b06ee49bb8aa6944afcad0101f0867f84dfa49a`
- Delta columns compare against the previous documented AV2 output-utilization
  checkpoint where the same vector or aggregate was present.

Validation result:

- `screenshot-sweep-444`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `screenshot-multictu-444`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-sweep-420`: PASS (64/64), strict SW/RTL/reference-decoder checksum parity.
- `racehorses-multictu-420`: PASS (10/10), strict SW/RTL/reference-decoder checksum parity.
- `multiframe-smoke`: PASS (4/4), strict SW/RTL/reference-decoder checksum parity.
- Yosys synthesis: PASS at 25 MHz metadata target.
- Vivado synthesis/timing: PASS at 25 MHz target, WNS is positive.

Aggregate top-level RTL utilization:

| Set | Cases | RTL bits (delta) | Total cycles (delta) | Active cycles (delta) | Wait cycles (delta) | Output util (delta) | Bubble rate (delta) | Cycles/bit (delta) | Cycles/pixel |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `screenshot-sweep-444` | 64 | 763928 (+18016) | 364696 (-39299) | 95491 (+2252) | 269205 (-41551) | 0.262 (+0.0308) | 0.738 (-0.0308) | 0.477 (-0.0646) | 4.4 |
| `screenshot-multictu-444` | 10 | 579256 (+20192) | 314164 (-23605) | 72407 (+2524) | 241757 (-26129) | 0.23 (+0.0235) | 0.77 (-0.0235) | 0.542 (-0.0616) | 3.42 |
| `racehorses-sweep-420` | 64 | 182464 (+0) | 76899 (-33048) | 22808 (+0) | 54091 (-33048) | 0.297 (+0.0896) | 0.703 (-0.0896) | 0.421 (-0.182) | 0.927 |
| `racehorses-multictu-420` | 10 | 186256 (+0) | 79826 (-34341) | 23282 (+0) | 56544 (-34341) | 0.292 (+0.0877) | 0.708 (-0.0877) | 0.429 (-0.184) | 0.869 |
| `multiframe-smoke` | 4 | 19680 (+1688) | 11925 (-1619) | 2460 (+211) | 9465 (-1830) | 0.206 (+0.0403) | 0.794 (-0.0403) | 0.606 (-0.147) | 2.48 |

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
| screenshot_640_sweep_8x8_1f_yuv444p8.yuv | PASS | 344 (+0) | 286 (-8) | 43 (+0) | 243 (-8) | 0.15 (+0.00435) | 0.85 (-0.00435) | 0.831 (-0.0236) | 4.47 |
| screenshot_640_sweep_16x8_1f_yuv444p8.yuv | PASS | 1984 (+0) | 862 (-27) | 248 (+0) | 614 (-27) | 0.288 (+0.0087) | 0.712 (-0.0087) | 0.434 (-0.0135) | 6.73 |
| screenshot_640_sweep_24x8_1f_yuv444p8.yuv | PASS | 416 (+8) | 431 (-104) | 52 (+1) | 379 (-105) | 0.121 (+0.0253) | 0.879 (-0.0256) | 1.04 (-0.274) | 2.24 |
| screenshot_640_sweep_32x8_1f_yuv444p8.yuv | PASS | 736 (+0) | 616 (-121) | 92 (+0) | 524 (-121) | 0.149 (+0.0244) | 0.851 (-0.0244) | 0.837 (-0.163) | 2.41 |
| screenshot_640_sweep_40x8_1f_yuv444p8.yuv | PASS | 480 (+0) | 584 (-200) | 60 (+0) | 524 (-200) | 0.103 (+0.0262) | 0.897 (-0.0257) | 1.22 (-0.413) | 1.82 |
| screenshot_640_sweep_48x8_1f_yuv444p8.yuv | PASS | 520 (+0) | 658 (-225) | 65 (+0) | 593 (-225) | 0.0988 (+0.0252) | 0.901 (-0.0248) | 1.27 (-0.435) | 1.71 |
| screenshot_640_sweep_56x8_1f_yuv444p8.yuv | PASS | 6832 (+0) | 3067 (-438) | 854 (+0) | 2213 (-438) | 0.278 (+0.0344) | 0.722 (-0.0344) | 0.449 (-0.0641) | 6.85 |
| screenshot_640_sweep_64x8_1f_yuv444p8.yuv | PASS | 6816 (+0) | 3362 (-433) | 852 (+0) | 2510 (-433) | 0.253 (+0.0284) | 0.747 (-0.0284) | 0.493 (-0.0637) | 6.57 |
| screenshot_640_sweep_8x16_1f_yuv444p8.yuv | PASS | 1760 (+0) | 826 (-74) | 220 (+0) | 606 (-74) | 0.266 (+0.0223) | 0.734 (-0.0223) | 0.469 (-0.0417) | 6.45 |
| screenshot_640_sweep_16x16_1f_yuv444p8.yuv | PASS | 4872 (-8) | 2003 (-152) | 609 (-1) | 1394 (-151) | 0.304 (+0.021) | 0.696 (-0.021) | 0.411 (-0.0309) | 7.82 |
| screenshot_640_sweep_24x16_1f_yuv444p8.yuv | PASS | 528 (+24) | 674 (-214) | 66 (+3) | 608 (-217) | 0.0979 (+0.027) | 0.902 (-0.0269) | 1.28 (-0.483) | 1.76 |
| screenshot_640_sweep_32x16_1f_yuv444p8.yuv | PASS | 592 (+40) | 818 (-204) | 74 (+5) | 744 (-209) | 0.0905 (+0.023) | 0.91 (-0.0225) | 1.38 (-0.468) | 1.6 |
| screenshot_640_sweep_40x16_1f_yuv444p8.yuv | PASS | 9456 (-64) | 4454 (-613) | 1182 (-8) | 3272 (-605) | 0.265 (+0.0304) | 0.735 (-0.0304) | 0.471 (-0.061) | 6.96 |
| screenshot_640_sweep_48x16_1f_yuv444p8.yuv | PASS | 744 (+48) | 1173 (-352) | 93 (+6) | 1080 (-358) | 0.0793 (+0.0223) | 0.921 (-0.0223) | 1.58 (-0.613) | 1.53 |
| screenshot_640_sweep_56x16_1f_yuv444p8.yuv | PASS | 10344 (+104) | 5123 (-867) | 1293 (+13) | 3830 (-880) | 0.252 (+0.0384) | 0.748 (-0.0384) | 0.495 (-0.0897) | 5.72 |
| screenshot_640_sweep_64x16_1f_yuv444p8.yuv | PASS | 888 (+64) | 1580 (-384) | 111 (+8) | 1469 (-392) | 0.0703 (+0.0179) | 0.93 (-0.0183) | 1.78 (-0.601) | 1.54 |
| screenshot_640_sweep_8x24_1f_yuv444p8.yuv | PASS | 3648 (-312) | 1621 (-293) | 456 (-39) | 1165 (-254) | 0.281 (+0.0223) | 0.719 (-0.0223) | 0.444 (-0.0386) | 8.44 |
| screenshot_640_sweep_16x24_1f_yuv444p8.yuv | PASS | 2672 (+0) | 1372 (-253) | 334 (+0) | 1038 (-253) | 0.243 (+0.0374) | 0.757 (-0.0374) | 0.513 (-0.0945) | 3.57 |
| screenshot_640_sweep_24x24_1f_yuv444p8.yuv | PASS | 7048 (+280) | 3059 (-379) | 881 (+35) | 2178 (-414) | 0.288 (+0.042) | 0.712 (-0.042) | 0.434 (-0.074) | 5.31 |
| screenshot_640_sweep_32x24_1f_yuv444p8.yuv | PASS | 15688 (+0) | 6210 (-616) | 1961 (+0) | 4249 (-616) | 0.316 (+0.0288) | 0.684 (-0.0288) | 0.396 (-0.0392) | 8.09 |
| screenshot_640_sweep_40x24_1f_yuv444p8.yuv | PASS | 15248 (-8) | 6087 (-757) | 1906 (-1) | 4181 (-756) | 0.313 (+0.0341) | 0.687 (-0.0341) | 0.399 (-0.0498) | 6.34 |
| screenshot_640_sweep_48x24_1f_yuv444p8.yuv | PASS | 960 (+280) | 1634 (-78) | 120 (+35) | 1514 (-113) | 0.0734 (+0.0238) | 0.927 (-0.0234) | 1.7 (-0.818) | 1.42 |
| screenshot_640_sweep_56x24_1f_yuv444p8.yuv | PASS | 1064 (+344) | 1954 (-66) | 133 (+43) | 1821 (-109) | 0.0681 (+0.0235) | 0.932 (-0.0231) | 1.84 (-0.974) | 1.45 |
| screenshot_640_sweep_64x24_1f_yuv444p8.yuv | PASS | 22424 (+584) | 9810 (-1339) | 2803 (+73) | 7007 (-1412) | 0.286 (+0.0407) | 0.714 (-0.0407) | 0.437 (-0.0725) | 6.39 |
| screenshot_640_sweep_8x32_1f_yuv444p8.yuv | PASS | 3176 (+0) | 1385 (-246) | 397 (+0) | 988 (-246) | 0.287 (+0.0436) | 0.713 (-0.0436) | 0.436 (-0.0779) | 5.41 |
| screenshot_640_sweep_16x32_1f_yuv444p8.yuv | PASS | 1408 (+24) | 1092 (-236) | 176 (+3) | 916 (-239) | 0.161 (+0.0312) | 0.839 (-0.0312) | 0.776 (-0.184) | 2.13 |
| screenshot_640_sweep_24x32_1f_yuv444p8.yuv | PASS | 1824 (+384) | 1518 (-161) | 228 (+48) | 1290 (-209) | 0.15 (+0.0432) | 0.85 (-0.0432) | 0.832 (-0.338) | 1.98 |
| screenshot_640_sweep_32x32_1f_yuv444p8.yuv | PASS | 11896 (+40) | 5104 (-529) | 1487 (+5) | 3617 (-534) | 0.291 (+0.0283) | 0.709 (-0.0283) | 0.429 (-0.0459) | 4.98 |
| screenshot_640_sweep_40x32_1f_yuv444p8.yuv | PASS | 1032 (+352) | 1786 (-130) | 129 (+44) | 1657 (-174) | 0.0722 (+0.0278) | 0.928 (-0.0282) | 1.73 (-1.09) | 1.4 |
| screenshot_640_sweep_48x32_1f_yuv444p8.yuv | PASS | 20456 (+224) | 9694 (-1216) | 2557 (+28) | 7137 (-1244) | 0.264 (+0.0318) | 0.736 (-0.0318) | 0.474 (-0.0651) | 6.31 |
| screenshot_640_sweep_56x32_1f_yuv444p8.yuv | PASS | 26008 (+0) | 11288 (-1675) | 3251 (+0) | 8037 (-1675) | 0.288 (+0.037) | 0.712 (-0.037) | 0.434 (-0.064) | 6.3 |
| screenshot_640_sweep_64x32_1f_yuv444p8.yuv | PASS | 1480 (+624) | 2999 (+309) | 185 (+78) | 2814 (+231) | 0.0617 (+0.0219) | 0.938 (-0.0217) | 2.03 (-1.11) | 1.46 |
| screenshot_640_sweep_8x40_1f_yuv444p8.yuv | PASS | 6056 (+0) | 2464 (-328) | 757 (+0) | 1707 (-328) | 0.307 (+0.0362) | 0.693 (-0.0362) | 0.407 (-0.0541) | 7.7 |
| screenshot_640_sweep_16x40_1f_yuv444p8.yuv | PASS | 14872 (+816) | 5915 (-165) | 1859 (+102) | 4056 (-267) | 0.314 (+0.0253) | 0.686 (-0.0253) | 0.398 (-0.0353) | 9.24 |
| screenshot_640_sweep_24x40_1f_yuv444p8.yuv | PASS | 1464 (+168) | 1607 (-355) | 183 (+21) | 1424 (-376) | 0.114 (+0.0313) | 0.886 (-0.0309) | 1.1 (-0.412) | 1.67 |
| screenshot_640_sweep_32x40_1f_yuv444p8.yuv | PASS | 21616 (+248) | 9064 (-1016) | 2702 (+31) | 6362 (-1047) | 0.298 (+0.0331) | 0.702 (-0.0331) | 0.419 (-0.0527) | 7.08 |
| screenshot_640_sweep_40x40_1f_yuv444p8.yuv | PASS | 22944 (+640) | 9733 (-1025) | 2868 (+80) | 6865 (-1105) | 0.295 (+0.0357) | 0.705 (-0.0357) | 0.424 (-0.0578) | 6.08 |
| screenshot_640_sweep_48x40_1f_yuv444p8.yuv | PASS | 2152 (+440) | 2852 (-93) | 269 (+55) | 2583 (-148) | 0.0943 (+0.0216) | 0.906 (-0.0213) | 1.33 (-0.395) | 1.49 |
| screenshot_640_sweep_56x40_1f_yuv444p8.yuv | PASS | 19784 (+384) | 9585 (-1096) | 2473 (+48) | 7112 (-1144) | 0.258 (+0.031) | 0.742 (-0.031) | 0.484 (-0.0665) | 4.28 |
| screenshot_640_sweep_64x40_1f_yuv444p8.yuv | PASS | 2032 (+888) | 3687 (+388) | 254 (+111) | 3433 (+277) | 0.0689 (+0.0256) | 0.931 (-0.0259) | 1.81 (-1.07) | 1.44 |
| screenshot_640_sweep_8x48_1f_yuv444p8.yuv | PASS | 664 (+24) | 704 (-308) | 83 (+3) | 621 (-311) | 0.118 (+0.0388) | 0.882 (-0.0389) | 1.06 (-0.52) | 1.83 |
| screenshot_640_sweep_16x48_1f_yuv444p8.yuv | PASS | 16960 (+32) | 7231 (-695) | 2120 (+4) | 5111 (-699) | 0.293 (+0.0262) | 0.707 (-0.0262) | 0.426 (-0.0416) | 9.42 |
| screenshot_640_sweep_24x48_1f_yuv444p8.yuv | PASS | 14800 (+80) | 6518 (-936) | 1850 (+10) | 4668 (-946) | 0.284 (+0.0368) | 0.716 (-0.0368) | 0.44 (-0.0656) | 5.66 |
| screenshot_640_sweep_32x48_1f_yuv444p8.yuv | PASS | 15920 (+24) | 7057 (-1043) | 1990 (+3) | 5067 (-1046) | 0.282 (+0.037) | 0.718 (-0.037) | 0.443 (-0.0667) | 4.59 |
| screenshot_640_sweep_40x48_1f_yuv444p8.yuv | PASS | 31960 (-8) | 12994 (-1666) | 3995 (-1) | 8999 (-1665) | 0.307 (+0.0344) | 0.693 (-0.0344) | 0.407 (-0.0524) | 6.77 |
| screenshot_640_sweep_48x48_1f_yuv444p8.yuv | PASS | 1624 (+744) | 3041 (+114) | 203 (+93) | 2838 (+21) | 0.0668 (+0.0292) | 0.933 (-0.0288) | 1.87 (-1.46) | 1.32 |
| screenshot_640_sweep_56x48_1f_yuv444p8.yuv | PASS | 11432 (+440) | 7751 (-1452) | 1429 (+55) | 6322 (-1507) | 0.184 (+0.0354) | 0.816 (-0.0354) | 0.678 (-0.159) | 2.88 |
| screenshot_640_sweep_64x48_1f_yuv444p8.yuv | PASS | 2328 (+1096) | 4261 (+451) | 291 (+137) | 3970 (+314) | 0.0683 (+0.0279) | 0.932 (-0.0283) | 1.83 (-1.26) | 1.39 |
| screenshot_640_sweep_8x56_1f_yuv444p8.yuv | PASS | 7152 (+0) | 2954 (-506) | 894 (+0) | 2060 (-506) | 0.303 (+0.0446) | 0.697 (-0.0446) | 0.413 (-0.071) | 6.59 |
| screenshot_640_sweep_16x56_1f_yuv444p8.yuv | PASS | 9664 (+64) | 4599 (-599) | 1208 (+8) | 3391 (-607) | 0.263 (+0.0317) | 0.737 (-0.0317) | 0.476 (-0.0651) | 5.13 |
| screenshot_640_sweep_24x56_1f_yuv444p8.yuv | PASS | 11904 (+160) | 5752 (-951) | 1488 (+20) | 4264 (-971) | 0.259 (+0.0397) | 0.741 (-0.0397) | 0.483 (-0.0878) | 4.28 |
| screenshot_640_sweep_32x56_1f_yuv444p8.yuv | PASS | 18376 (+304) | 8378 (-954) | 2297 (+38) | 6081 (-992) | 0.274 (+0.0322) | 0.726 (-0.0322) | 0.456 (-0.0601) | 4.68 |
| screenshot_640_sweep_40x56_1f_yuv444p8.yuv | PASS | 36832 (-240) | 15471 (-2153) | 4604 (-30) | 10867 (-2123) | 0.298 (+0.0346) | 0.702 (-0.0346) | 0.42 (-0.055) | 6.91 |
| screenshot_640_sweep_48x56_1f_yuv444p8.yuv | PASS | 27208 (+4536) | 12389 (+349) | 3401 (+567) | 8988 (-218) | 0.275 (+0.0395) | 0.725 (-0.0395) | 0.455 (-0.0757) | 4.61 |
| screenshot_640_sweep_56x56_1f_yuv444p8.yuv | PASS | 56456 (+200) | 23289 (-2737) | 7057 (+25) | 16232 (-2762) | 0.303 (+0.033) | 0.697 (-0.033) | 0.413 (-0.0505) | 7.43 |
| screenshot_640_sweep_64x56_1f_yuv444p8.yuv | PASS | 28088 (+1096) | 13502 (-899) | 3511 (+137) | 9991 (-1036) | 0.26 (+0.026) | 0.74 (-0.026) | 0.481 (-0.0533) | 3.77 |
| screenshot_640_sweep_8x64_1f_yuv444p8.yuv | PASS | 5640 (+72) | 2632 (-517) | 705 (+9) | 1927 (-526) | 0.268 (+0.0469) | 0.732 (-0.0469) | 0.467 (-0.0993) | 5.14 |
| screenshot_640_sweep_16x64_1f_yuv444p8.yuv | PASS | 16376 (-136) | 6900 (-920) | 2047 (-17) | 4853 (-903) | 0.297 (+0.0327) | 0.703 (-0.0327) | 0.421 (-0.0527) | 6.74 |
| screenshot_640_sweep_24x64_1f_yuv444p8.yuv | PASS | 13264 (+248) | 6352 (-818) | 1658 (+31) | 4694 (-849) | 0.261 (+0.034) | 0.739 (-0.034) | 0.479 (-0.0721) | 4.14 |
| screenshot_640_sweep_32x64_1f_yuv444p8.yuv | PASS | 32936 (+320) | 13583 (-1464) | 4117 (+40) | 9466 (-1504) | 0.303 (+0.0321) | 0.697 (-0.0321) | 0.412 (-0.0486) | 6.63 |
| screenshot_640_sweep_40x64_1f_yuv444p8.yuv | PASS | 2824 (+760) | 3696 (-204) | 353 (+95) | 3343 (-299) | 0.0955 (+0.0293) | 0.904 (-0.0295) | 1.31 (-0.581) | 1.44 |
| screenshot_640_sweep_48x64_1f_yuv444p8.yuv | PASS | 49024 (+88) | 20545 (-2323) | 6128 (+11) | 14417 (-2334) | 0.298 (+0.0313) | 0.702 (-0.0313) | 0.419 (-0.0479) | 6.69 |
| screenshot_640_sweep_56x64_1f_yuv444p8.yuv | PASS | 3864 (+1264) | 5405 (+142) | 483 (+158) | 4922 (-16) | 0.0894 (+0.0276) | 0.911 (-0.0274) | 1.4 (-0.621) | 1.51 |
| screenshot_640_sweep_64x64_1f_yuv444p8.yuv | PASS | 74368 (+232) | 31655 (-3439) | 9296 (+29) | 22359 (-3468) | 0.294 (+0.0297) | 0.706 (-0.0297) | 0.426 (-0.0473) | 7.73 |

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
| screenshot_640_multictu_h2_128x64_1f_yuv444p8.yuv | PASS | 86760 (+160) | 41347 (-4618) | 10845 (+20) | 30502 (-4638) | 0.262 (+0.0263) | 0.738 (-0.0263) | 0.477 (-0.0544) | 5.05 |
| screenshot_640_multictu_v2_64x128_1f_yuv444p8.yuv | PASS | 44520 (+2368) | 25143 (-1187) | 5565 (+296) | 19578 (-1483) | 0.221 (+0.0213) | 0.779 (-0.0213) | 0.565 (-0.0602) | 3.07 |
| screenshot_640_multictu_grid2_128x128_1f_yuv444p8.yuv | PASS | 15912 (+6112) | 24186 (+2645) | 1989 (+764) | 22197 (+1881) | 0.0822 (+0.0253) | 0.918 (-0.0252) | 1.52 (-0.68) | 1.48 |
| screenshot_640_multictu_h3_192x64_1f_yuv444p8.yuv | PASS | 45032 (+3040) | 30880 (-1926) | 5629 (+380) | 25251 (-2306) | 0.182 (+0.0223) | 0.818 (-0.0223) | 0.686 (-0.0953) | 2.51 |
| screenshot_640_multictu_v3_64x192_1f_yuv444p8.yuv | PASS | 105520 (+2664) | 51670 (-4181) | 13190 (+333) | 38480 (-4514) | 0.255 (+0.0253) | 0.745 (-0.0253) | 0.49 (-0.0533) | 4.2 |
| screenshot_640_partial_h2_72x64_1f_yuv444p8.yuv | PASS | 57616 (+408) | 26149 (-3339) | 7202 (+51) | 18947 (-3390) | 0.275 (+0.0324) | 0.725 (-0.0324) | 0.454 (-0.0612) | 5.67 |
| screenshot_640_partial_v2_64x72_1f_yuv444p8.yuv | PASS | 3112 (+1448) | 6262 (+414) | 389 (+181) | 5873 (+233) | 0.0621 (+0.0265) | 0.938 (-0.0261) | 2.01 (-1.5) | 1.36 |
| screenshot_640_partial_grid2_72x72_1f_yuv444p8.yuv | PASS | 4504 (+1528) | 7541 (-177) | 563 (+191) | 6978 (-368) | 0.0747 (+0.0265) | 0.925 (-0.0267) | 1.67 (-0.916) | 1.45 |
| screenshot_640_partial_wide_136x80_1f_yuv444p8.yuv | PASS | 137280 (+424) | 61538 (-6849) | 17160 (+53) | 44378 (-6902) | 0.279 (+0.0289) | 0.721 (-0.0289) | 0.448 (-0.0517) | 5.66 |
| screenshot_640_partial_tall_72x128_1f_yuv444p8.yuv | PASS | 79000 (+2040) | 39448 (-4387) | 9875 (+255) | 29573 (-4642) | 0.25 (+0.0313) | 0.75 (-0.0313) | 0.499 (-0.0707) | 4.28 |

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
| racehorses_crop_16x8_1f_yuv420p8.yuv | PASS | 456 (+0) | 241 (-16) | 57 (+0) | 184 (-16) | 0.237 (+0.0145) | 0.763 (-0.0145) | 0.529 (-0.0355) | 1.88 |
| racehorses_crop_24x8_1f_yuv420p8.yuv | PASS | 640 (+0) | 304 (-56) | 80 (+0) | 224 (-56) | 0.263 (+0.0412) | 0.737 (-0.0412) | 0.475 (-0.087) | 1.58 |
| racehorses_crop_32x8_1f_yuv420p8.yuv | PASS | 824 (+0) | 369 (-60) | 103 (+0) | 266 (-60) | 0.279 (+0.0391) | 0.721 (-0.0391) | 0.448 (-0.0732) | 1.44 |
| racehorses_crop_40x8_1f_yuv420p8.yuv | PASS | 976 (+0) | 438 (-111) | 122 (+0) | 316 (-111) | 0.279 (+0.0565) | 0.721 (-0.0565) | 0.449 (-0.113) | 1.37 |
| racehorses_crop_48x8_1f_yuv420p8.yuv | PASS | 1032 (+0) | 463 (-120) | 129 (+0) | 334 (-120) | 0.279 (+0.0576) | 0.721 (-0.0576) | 0.449 (-0.116) | 1.21 |
| racehorses_crop_56x8_1f_yuv420p8.yuv | PASS | 1240 (+0) | 532 (-167) | 155 (+0) | 377 (-167) | 0.291 (+0.0694) | 0.709 (-0.0694) | 0.429 (-0.135) | 1.19 |
| racehorses_crop_64x8_1f_yuv420p8.yuv | PASS | 1392 (+0) | 590 (-160) | 174 (+0) | 416 (-160) | 0.295 (+0.0629) | 0.705 (-0.0629) | 0.424 (-0.115) | 1.15 |
| racehorses_crop_8x16_1f_yuv420p8.yuv | PASS | 336 (+0) | 211 (-42) | 42 (+0) | 169 (-42) | 0.199 (+0.0331) | 0.801 (-0.0331) | 0.628 (-0.125) | 1.65 |
| racehorses_crop_16x16_1f_yuv420p8.yuv | PASS | 744 (+0) | 345 (-73) | 93 (+0) | 252 (-73) | 0.27 (+0.0476) | 0.73 (-0.0476) | 0.464 (-0.0983) | 1.35 |
| racehorses_crop_24x16_1f_yuv420p8.yuv | PASS | 912 (+0) | 422 (-153) | 114 (+0) | 308 (-153) | 0.27 (+0.0721) | 0.73 (-0.0721) | 0.463 (-0.167) | 1.1 |
| racehorses_crop_32x16_1f_yuv420p8.yuv | PASS | 1216 (+0) | 537 (-160) | 152 (+0) | 385 (-160) | 0.283 (+0.0651) | 0.717 (-0.0651) | 0.442 (-0.131) | 1.05 |
| racehorses_crop_40x16_1f_yuv420p8.yuv | PASS | 1544 (+0) | 667 (-262) | 193 (+0) | 474 (-262) | 0.289 (+0.0814) | 0.711 (-0.0814) | 0.432 (-0.17) | 1.04 |
| racehorses_crop_48x16_1f_yuv420p8.yuv | PASS | 1776 (+0) | 749 (-280) | 222 (+0) | 527 (-280) | 0.296 (+0.0804) | 0.704 (-0.0804) | 0.422 (-0.157) | 0.975 |
| racehorses_crop_56x16_1f_yuv420p8.yuv | PASS | 2088 (+0) | 912 (-331) | 261 (+0) | 651 (-331) | 0.286 (+0.0762) | 0.714 (-0.0762) | 0.437 (-0.158) | 1.02 |
| racehorses_crop_64x16_1f_yuv420p8.yuv | PASS | 2336 (+0) | 1006 (-317) | 292 (+0) | 714 (-317) | 0.29 (+0.0693) | 0.71 (-0.0693) | 0.431 (-0.135) | 0.982 |
| racehorses_crop_8x24_1f_yuv420p8.yuv | PASS | 528 (+0) | 284 (-84) | 66 (+0) | 218 (-84) | 0.232 (+0.0534) | 0.768 (-0.0534) | 0.538 (-0.159) | 1.48 |
| racehorses_crop_16x24_1f_yuv420p8.yuv | PASS | 976 (+0) | 445 (-130) | 122 (+0) | 323 (-130) | 0.274 (+0.0622) | 0.726 (-0.0622) | 0.456 (-0.133) | 1.16 |
| racehorses_crop_24x24_1f_yuv420p8.yuv | PASS | 1304 (+0) | 582 (-250) | 163 (+0) | 419 (-250) | 0.28 (+0.0841) | 0.72 (-0.0841) | 0.446 (-0.192) | 1.01 |
| racehorses_crop_32x24_1f_yuv420p8.yuv | PASS | 1632 (+0) | 716 (-260) | 204 (+0) | 512 (-260) | 0.285 (+0.0759) | 0.715 (-0.0759) | 0.439 (-0.159) | 0.932 |
| racehorses_crop_40x24_1f_yuv420p8.yuv | PASS | 2200 (+0) | 936 (-413) | 275 (+0) | 661 (-413) | 0.294 (+0.0898) | 0.706 (-0.0898) | 0.425 (-0.188) | 0.975 |
| racehorses_crop_48x24_1f_yuv420p8.yuv | PASS | 2600 (+0) | 1086 (-440) | 325 (+0) | 761 (-440) | 0.299 (+0.0863) | 0.701 (-0.0863) | 0.418 (-0.169) | 0.943 |
| racehorses_crop_56x24_1f_yuv420p8.yuv | PASS | 3032 (+0) | 1293 (-540) | 379 (+0) | 914 (-540) | 0.293 (+0.0861) | 0.707 (-0.0861) | 0.426 (-0.179) | 0.962 |
| racehorses_crop_64x24_1f_yuv420p8.yuv | PASS | 3584 (+0) | 1490 (-533) | 448 (+0) | 1042 (-533) | 0.301 (+0.0797) | 0.699 (-0.0797) | 0.416 (-0.148) | 0.97 |
| racehorses_crop_8x32_1f_yuv420p8.yuv | PASS | 600 (+0) | 314 (-126) | 75 (+0) | 239 (-126) | 0.239 (+0.0689) | 0.761 (-0.0689) | 0.523 (-0.21) | 1.23 |
| racehorses_crop_16x32_1f_yuv420p8.yuv | PASS | 1192 (+0) | 529 (-187) | 149 (+0) | 380 (-187) | 0.282 (+0.0737) | 0.718 (-0.0737) | 0.444 (-0.157) | 1.03 |
| racehorses_crop_24x32_1f_yuv420p8.yuv | PASS | 1600 (+0) | 710 (-347) | 200 (+0) | 510 (-347) | 0.282 (+0.0927) | 0.718 (-0.0927) | 0.444 (-0.217) | 0.924 |
| racehorses_crop_32x32_1f_yuv420p8.yuv | PASS | 2232 (+0) | 940 (-360) | 279 (+0) | 661 (-360) | 0.297 (+0.0818) | 0.703 (-0.0818) | 0.421 (-0.161) | 0.918 |
| racehorses_crop_40x32_1f_yuv420p8.yuv | PASS | 2952 (+0) | 1220 (-564) | 369 (+0) | 851 (-564) | 0.302 (+0.0955) | 0.698 (-0.0955) | 0.413 (-0.191) | 0.953 |
| racehorses_crop_48x32_1f_yuv420p8.yuv | PASS | 3344 (+0) | 1378 (-600) | 418 (+0) | 960 (-600) | 0.303 (+0.0923) | 0.697 (-0.0923) | 0.412 (-0.18) | 0.897 |
| racehorses_crop_56x32_1f_yuv420p8.yuv | PASS | 3912 (+0) | 1667 (-719) | 489 (+0) | 1178 (-719) | 0.293 (+0.0883) | 0.707 (-0.0883) | 0.426 (-0.184) | 0.93 |
| racehorses_crop_64x32_1f_yuv420p8.yuv | PASS | 4544 (+0) | 1877 (-718) | 568 (+0) | 1309 (-718) | 0.303 (+0.0836) | 0.697 (-0.0836) | 0.413 (-0.158) | 0.917 |
| racehorses_crop_8x40_1f_yuv420p8.yuv | PASS | 760 (+0) | 386 (-168) | 95 (+0) | 291 (-168) | 0.246 (+0.0751) | 0.754 (-0.0751) | 0.508 (-0.221) | 1.21 |
| racehorses_crop_16x40_1f_yuv420p8.yuv | PASS | 1528 (+0) | 664 (-244) | 191 (+0) | 473 (-244) | 0.288 (+0.0777) | 0.712 (-0.0777) | 0.435 (-0.159) | 1.04 |
| racehorses_crop_24x40_1f_yuv420p8.yuv | PASS | 1984 (+0) | 873 (-444) | 248 (+0) | 625 (-444) | 0.284 (+0.0961) | 0.716 (-0.0961) | 0.44 (-0.224) | 0.909 |
| racehorses_crop_32x40_1f_yuv420p8.yuv | PASS | 2752 (+0) | 1151 (-460) | 344 (+0) | 807 (-460) | 0.299 (+0.0849) | 0.701 (-0.0849) | 0.418 (-0.167) | 0.899 |
| racehorses_crop_40x40_1f_yuv420p8.yuv | PASS | 3464 (+0) | 1456 (-706) | 433 (+0) | 1023 (-706) | 0.297 (+0.0974) | 0.703 (-0.0974) | 0.42 (-0.204) | 0.91 |
| racehorses_crop_48x40_1f_yuv420p8.yuv | PASS | 4416 (+0) | 1786 (-755) | 552 (+0) | 1234 (-755) | 0.309 (+0.0921) | 0.691 (-0.0921) | 0.404 (-0.171) | 0.93 |
| racehorses_crop_56x40_1f_yuv420p8.yuv | PASS | 4896 (+0) | 2064 (-915) | 612 (+0) | 1452 (-915) | 0.297 (+0.0915) | 0.703 (-0.0915) | 0.422 (-0.186) | 0.921 |
| racehorses_crop_64x40_1f_yuv420p8.yuv | PASS | 5560 (+0) | 2292 (-915) | 695 (+0) | 1597 (-915) | 0.303 (+0.0862) | 0.697 (-0.0862) | 0.412 (-0.165) | 0.895 |
| racehorses_crop_8x48_1f_yuv420p8.yuv | PASS | 968 (+0) | 458 (-210) | 121 (+0) | 337 (-210) | 0.264 (+0.0832) | 0.736 (-0.0832) | 0.473 (-0.217) | 1.19 |
| racehorses_crop_16x48_1f_yuv420p8.yuv | PASS | 1824 (+0) | 780 (-301) | 228 (+0) | 552 (-301) | 0.292 (+0.0813) | 0.708 (-0.0813) | 0.428 (-0.165) | 1.02 |
| racehorses_crop_24x48_1f_yuv420p8.yuv | PASS | 2280 (+0) | 994 (-541) | 285 (+0) | 709 (-541) | 0.287 (+0.101) | 0.713 (-0.101) | 0.436 (-0.237) | 0.863 |
| racehorses_crop_32x48_1f_yuv420p8.yuv | PASS | 3152 (+0) | 1319 (-560) | 394 (+0) | 925 (-560) | 0.299 (+0.0887) | 0.701 (-0.0887) | 0.418 (-0.178) | 0.859 |
| racehorses_crop_40x48_1f_yuv420p8.yuv | PASS | 4104 (+0) | 1709 (-858) | 513 (+0) | 1196 (-858) | 0.3 (+0.1) | 0.7 (-0.1) | 0.416 (-0.209) | 0.89 |
| racehorses_crop_48x48_1f_yuv420p8.yuv | PASS | 5016 (+0) | 2028 (-920) | 627 (+0) | 1401 (-920) | 0.309 (+0.0962) | 0.691 (-0.0962) | 0.404 (-0.184) | 0.88 |
| racehorses_crop_56x48_1f_yuv420p8.yuv | PASS | 5776 (+0) | 2435 (-1109) | 722 (+0) | 1713 (-1109) | 0.297 (+0.0925) | 0.703 (-0.0925) | 0.422 (-0.192) | 0.906 |
| racehorses_crop_64x48_1f_yuv420p8.yuv | PASS | 6512 (+0) | 2702 (-1105) | 814 (+0) | 1888 (-1105) | 0.301 (+0.0873) | 0.699 (-0.0873) | 0.415 (-0.17) | 0.88 |
| racehorses_crop_8x56_1f_yuv420p8.yuv | PASS | 1072 (+0) | 504 (-252) | 134 (+0) | 370 (-252) | 0.266 (+0.0889) | 0.734 (-0.0889) | 0.47 (-0.235) | 1.12 |
| racehorses_crop_16x56_1f_yuv420p8.yuv | PASS | 2072 (+0) | 874 (-358) | 259 (+0) | 615 (-358) | 0.296 (+0.0863) | 0.704 (-0.0863) | 0.422 (-0.173) | 0.975 |
| racehorses_crop_24x56_1f_yuv420p8.yuv | PASS | 2680 (+0) | 1156 (-638) | 335 (+0) | 821 (-638) | 0.29 (+0.103) | 0.71 (-0.103) | 0.431 (-0.238) | 0.86 |
| racehorses_crop_32x56_1f_yuv420p8.yuv | PASS | 3688 (+0) | 1521 (-660) | 461 (+0) | 1060 (-660) | 0.303 (+0.0921) | 0.697 (-0.0921) | 0.412 (-0.179) | 0.849 |
| racehorses_crop_40x56_1f_yuv420p8.yuv | PASS | 4696 (+0) | 1938 (-1016) | 587 (+0) | 1351 (-1016) | 0.303 (+0.104) | 0.697 (-0.104) | 0.413 (-0.216) | 0.865 |
| racehorses_crop_48x56_1f_yuv420p8.yuv | PASS | 5944 (+0) | 2388 (-1080) | 743 (+0) | 1645 (-1080) | 0.311 (+0.0971) | 0.689 (-0.0971) | 0.402 (-0.181) | 0.888 |
| racehorses_crop_56x56_1f_yuv420p8.yuv | PASS | 6704 (+0) | 2794 (-1329) | 838 (+0) | 1956 (-1329) | 0.3 (+0.0969) | 0.7 (-0.0969) | 0.417 (-0.198) | 0.891 |
| racehorses_crop_64x56_1f_yuv420p8.yuv | PASS | 7600 (+0) | 3135 (-1291) | 950 (+0) | 2185 (-1291) | 0.303 (+0.088) | 0.697 (-0.088) | 0.412 (-0.169) | 0.875 |
| racehorses_crop_8x64_1f_yuv420p8.yuv | PASS | 1184 (+0) | 539 (-294) | 148 (+0) | 391 (-294) | 0.275 (+0.0966) | 0.725 (-0.0966) | 0.455 (-0.249) | 1.05 |
| racehorses_crop_16x64_1f_yuv420p8.yuv | PASS | 2240 (+0) | 940 (-415) | 280 (+0) | 660 (-415) | 0.298 (+0.0909) | 0.702 (-0.0909) | 0.42 (-0.185) | 0.918 |
| racehorses_crop_24x64_1f_yuv420p8.yuv | PASS | 3152 (+0) | 1331 (-735) | 394 (+0) | 937 (-735) | 0.296 (+0.105) | 0.704 (-0.105) | 0.422 (-0.233) | 0.867 |
| racehorses_crop_32x64_1f_yuv420p8.yuv | PASS | 4112 (+0) | 1692 (-760) | 514 (+0) | 1178 (-760) | 0.304 (+0.0938) | 0.696 (-0.0938) | 0.411 (-0.185) | 0.826 |
| racehorses_crop_40x64_1f_yuv420p8.yuv | PASS | 5320 (+0) | 2184 (-1160) | 665 (+0) | 1519 (-1160) | 0.304 (+0.105) | 0.696 (-0.105) | 0.411 (-0.218) | 0.853 |
| racehorses_crop_48x64_1f_yuv420p8.yuv | PASS | 6496 (+0) | 2619 (-1240) | 812 (+0) | 1807 (-1240) | 0.31 (+0.1) | 0.69 (-0.1) | 0.403 (-0.191) | 0.853 |
| racehorses_crop_56x64_1f_yuv420p8.yuv | PASS | 7744 (+0) | 3165 (-1559) | 968 (+0) | 2197 (-1559) | 0.306 (+0.101) | 0.694 (-0.101) | 0.409 (-0.201) | 0.883 |
| racehorses_crop_64x64_1f_yuv420p8.yuv | PASS | 8720 (+0) | 3578 (-1471) | 1090 (+0) | 2488 (-1471) | 0.305 (+0.0886) | 0.695 (-0.0886) | 0.41 (-0.169) | 0.874 |

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
| racehorses_multictu_h2_128x64_1f_yuv420p8.yuv | PASS | 16984 (+0) | 7061 (-2977) | 2123 (+0) | 4938 (-2977) | 0.301 (+0.0897) | 0.699 (-0.0897) | 0.416 (-0.175) | 0.862 |
| racehorses_multictu_v2_64x128_1f_yuv420p8.yuv | PASS | 17160 (+0) | 7145 (-3005) | 2145 (+0) | 5000 (-3005) | 0.3 (+0.0892) | 0.7 (-0.0892) | 0.416 (-0.175) | 0.872 |
| racehorses_multictu_grid2_128x128_1f_yuv420p8.yuv | PASS | 31816 (+0) | 13636 (-5845) | 3977 (+0) | 9659 (-5845) | 0.292 (+0.0877) | 0.708 (-0.0877) | 0.429 (-0.183) | 0.832 |
| racehorses_multictu_h3_192x64_1f_yuv420p8.yuv | PASS | 24888 (+0) | 10430 (-4455) | 3111 (+0) | 7319 (-4455) | 0.298 (+0.0893) | 0.702 (-0.0893) | 0.419 (-0.179) | 0.849 |
| racehorses_multictu_v3_64x192_1f_yuv420p8.yuv | PASS | 22616 (+0) | 10052 (-4234) | 2827 (+0) | 7225 (-4234) | 0.281 (+0.0832) | 0.719 (-0.0832) | 0.444 (-0.188) | 0.818 |
| racehorses_partial_h2_72x64_1f_yuv420p8.yuv | PASS | 9816 (+0) | 4228 (-1907) | 1227 (+0) | 3001 (-1907) | 0.29 (+0.0902) | 0.71 (-0.0902) | 0.431 (-0.194) | 0.918 |
| racehorses_partial_v2_64x72_1f_yuv420p8.yuv | PASS | 9936 (+0) | 4159 (-1651) | 1242 (+0) | 2917 (-1651) | 0.299 (+0.0846) | 0.701 (-0.0846) | 0.419 (-0.166) | 0.903 |
| racehorses_partial_grid2_72x72_1f_yuv420p8.yuv | PASS | 11384 (+0) | 4922 (-2119) | 1423 (+0) | 3499 (-2119) | 0.289 (+0.0871) | 0.711 (-0.0871) | 0.432 (-0.186) | 0.949 |
| racehorses_partial_wide_136x80_1f_yuv420p8.yuv | PASS | 22552 (+0) | 9952 (-4243) | 2819 (+0) | 7133 (-4243) | 0.283 (+0.0843) | 0.717 (-0.0843) | 0.441 (-0.188) | 0.915 |
| racehorses_partial_tall_72x128_1f_yuv420p8.yuv | PASS | 19104 (+0) | 8241 (-3905) | 2388 (+0) | 5853 (-3905) | 0.29 (+0.0928) | 0.71 (-0.0928) | 0.431 (-0.205) | 0.894 |

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
| multiframe_motion_444_16x8_2f_yuv444p8.yuv | PASS | 1408 (+120) | 956 (-16) | 176 (+15) | 780 (-31) | 0.184 (+0.0181) | 0.816 (-0.0181) | 0.679 (-0.076) | 3.73 |
| multiframe_motion_wide_444_48x32_2f_yuv444p8.yuv | PASS | 12496 (+1568) | 7920 (-1603) | 1562 (+196) | 6358 (-1799) | 0.197 (+0.0542) | 0.803 (-0.0542) | 0.634 (-0.237) | 2.58 |
