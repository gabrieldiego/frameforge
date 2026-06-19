# VVC Synthesis Baselines

This file records VVC-specific synthesis measurements and optimization history.
The shared synthesis process, tool setup, and Vivado flow are documented in
[../synthesis.md](../synthesis.md).

## 2026-06-19 Residual Remainder Scan Trim

Measured after trimming the VVC 4:2:0 residual `abs_remainder` scan in the
4x4 residual symbol emitter. The bitstream syntax, reconstructed samples, AXI
control/data-plane wiring, palette support, and exact-hash IBC synthesis setting
are unchanged from the previous documented baseline.

Baseline and current sources:

- Baseline report Git SHA: `9ccd873d6407a9f112492ef1a153e82d3550e216`
- Baseline validated RTL Git SHA: `7d54a8c42552942b9b7be5ac3941b1a7518bd4af`
- Current validated RTL Git SHA: `65812b2f1d0d2050cbe69c97b981496a8825fd47`
- Baseline mode: previous VVC CABAC emission-throughput checkpoint.
- Current mode: same bitstream syntax, plus residual remainder-scan trimming.

Validation result:

- `racehorses-sweep-420`: OK (64/64)
- `racehorses-multictu-420`: OK (10/10)
- Focused 4:4:4 screenshot smoke check: OK.
- Software and RTL bitstreams matched exactly for all listed RaceHorses vectors.
- Software, RTL, and VTM reconstructions matched for all listed RaceHorses vectors.

Synthesis configuration:

- command: `make synth CODEC=vvc SYNTH_DUT=vvc-encoder`
- DUT: `vvc-encoder`
- RTL top: `ff_vvc_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- exact-hash IBC for 4:4:4: disabled (`SYNTH_SUPPORT_EXACT_HASH_IBC_444=0`)

Synthesis result:

- Top `ff_vvc_encoder` synthesis completed in 469.9 seconds with 2165.48 MiB
  peak child RSS observed by the synthesis runner.
- Runtime exceeded the 300 second review threshold but stayed inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 11.0 seconds.
- Post-synthesis critical-path reporting completed in 80.0 seconds with peak
  memory 2165.48 MiB and topological path length 55.
- The longest topological path remains in `ff_vvc_cabac_syntax_frontend` IBC
  MVD absolute-value and EG1 prefix generation before `m_axis_data`; the
  residual scan trim did not become the reported timing limiter.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_vvc_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 140116 |
| Estimated LCs | 53471 |
| CARRY4 | 4046 |
| DSP48E1 | 9 |
| FDCE | 13166 |
| FDPE | 299 |
| FDRE | 22492 |
| FDSE | 4 |
| LUT1 | 1633 |
| LUT2 | 20491 |
| LUT3 | 7315 |
| LUT4 | 6056 |
| LUT5 | 8055 |
| LUT6 | 28485 |
| MUXF7 | 8705 |
| MUXF8 | 1650 |
| RAMB36E1 | 9 |

Delta from the previous VVC CABAC emission-throughput checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 456.3 s | 469.9 s | +13.6 s |
| Peak synthesis RSS | 2165.60 MiB | 2165.48 MiB | -0.12 MiB |
| Cell report time | 10.8 s | 11.0 s | +0.2 s |
| Critical-path report time | 78.0 s | 80.0 s | +2.0 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 139333 | 140116 | +783 |
| Estimated LCs | 53485 | 53471 | -14 |
| CARRY4 | 4046 | 4046 | +0 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 13156 | 13166 | +10 |
| FDPE | 299 | 299 | +0 |
| FDRE | 22492 | 22492 | +0 |
| FDSE | 4 | 4 | +0 |
| LUT1 | 1443 | 1633 | +190 |
| LUT2 | 20522 | 20491 | -31 |
| LUT3 | 7308 | 7315 | +7 |
| LUT4 | 5553 | 6056 | +503 |
| LUT5 | 8354 | 8055 | -299 |
| LUT6 | 28439 | 28485 | +46 |
| MUXF7 | 8392 | 8705 | +313 |
| MUXF8 | 1629 | 1650 | +21 |
| RAMB36E1 | 9 | 9 | +0 |

The critical-path length stayed at 55 and estimated LCs decreased slightly by
14. Total flattened cells increased by 783, mainly in LUT packing around the
residual symbol emitter control, which is acceptable for the measured 4:2:0
throughput improvement.

## 2026-06-19 CABAC Emission Throughput

Measured after reducing VVC CABAC/output-path bubbles in the bit writer,
stream-writer handoff, residual symbol emitter, and top-level CABAC input
handoff. The bitstream syntax, reconstructed samples, AXI control/data-plane
wiring, palette support, and exact-hash IBC synthesis setting are unchanged
from the previous documented baseline.

Baseline and current sources:

- Baseline report Git SHA: `66e19ca20cf480a0353b211bf535cdcb2d384bbd`
- Baseline validated RTL Git SHA: `999bbcf91ddd45845a2b32c20add79e940c4ca40`
- Current validated RTL Git SHA: `7d54a8c42552942b9b7be5ac3941b1a7518bd4af`
- Baseline mode: previous VVC residual-throughput checkpoint.
- Current mode: same bitstream syntax, plus faster CABAC bit emission,
  stream-writer handoff, residual symbol scheduling, and top-level CABAC input
  handoff.

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
- `racehorses-sweep-420`: OK (64/64)
- `racehorses-multictu-420`: OK (10/10)
- Software and RTL bitstreams matched exactly.
- Software, RTL, and VTM reconstructions matched for every listed vector.

Synthesis configuration:

- command: `make synth CODEC=vvc SYNTH_DUT=vvc-encoder`
- DUT: `vvc-encoder`
- RTL top: `ff_vvc_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- exact-hash IBC for 4:4:4: disabled (`SYNTH_SUPPORT_EXACT_HASH_IBC_444=0`)

Synthesis result:

- Top `ff_vvc_encoder` synthesis completed in 456.3 seconds with 2165.60 MiB
  peak child RSS observed by the synthesis runner.
- Runtime exceeded the 300 second review threshold but stayed inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 10.8 seconds.
- Post-synthesis critical-path reporting completed in 78.0 seconds with peak
  memory 2165.60 MiB and topological path length 55.
- The longest topological path remains in `ff_vvc_cabac_syntax_frontend` IBC
  MVD absolute-value and EG1 prefix generation before `m_axis_data`, so the
  CABAC/output throughput changes did not become the reported timing limiter.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_vvc_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 139333 |
| Estimated LCs | 53485 |
| CARRY4 | 4046 |
| DSP48E1 | 9 |
| FDCE | 13156 |
| FDPE | 299 |
| FDRE | 22492 |
| FDSE | 4 |
| LUT1 | 1443 |
| LUT2 | 20522 |
| LUT3 | 7308 |
| LUT4 | 5553 |
| LUT5 | 8354 |
| LUT6 | 28439 |
| MUXF7 | 8392 |
| MUXF8 | 1629 |
| RAMB36E1 | 9 |

Delta from the previous VVC residual-throughput checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 439.1 s | 456.3 s | +17.2 s |
| Peak synthesis RSS | 2146.46 MiB | 2165.60 MiB | +19.14 MiB |
| Cell report time | 10.7 s | 10.8 s | +0.1 s |
| Critical-path report time | 74.5 s | 78.0 s | +3.5 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 139497 | 139333 | -164 |
| Estimated LCs | 53283 | 53485 | +202 |
| CARRY4 | 4039 | 4046 | +7 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 13154 | 13156 | +2 |
| FDPE | 299 | 299 | +0 |
| FDRE | 22492 | 22492 | +0 |
| FDSE | 4 | 4 | +0 |
| LUT1 | 1590 | 1443 | -147 |
| LUT2 | 21025 | 20522 | -503 |
| LUT3 | 7075 | 7308 | +233 |
| LUT4 | 5798 | 5553 | -245 |
| LUT5 | 8254 | 8354 | +100 |
| LUT6 | 28080 | 28439 | +359 |
| MUXF7 | 8335 | 8392 | +57 |
| MUXF8 | 1647 | 1629 | -18 |
| RAMB36E1 | 9 | 9 | +0 |

The area and critical-path impact is small: total flattened cells decreased by
164, estimated LCs rose by 202, and the topological critical-path length stayed
at 55. In return, the 4:4:4 screenshot sweep aggregate drops from 1,581,091 to
1,098,761 cycles, screenshot multi-CTU drops from 1,483,255 to 1,090,477 cycles,
4:2:0 RaceHorses sweep drops from 806,007 to 624,212 cycles, and 4:2:0
RaceHorses multi-CTU drops from 848,456 to 659,650 cycles, with no bitrate or
reconstruction changes.

## 2026-06-19 Residual Throughput Follow-Up

Measured after reducing VVC 4:2:0 residual-path bubbles in the luma and chroma
quant/reconstruction blocks. The bitstream syntax, reconstructed samples, AXI
control/data-plane wiring, palette support, and exact-hash IBC synthesis setting
are unchanged from the previous documented baseline.

Baseline and current sources:

- Baseline Git SHA: `ce93d8129d77ab64c032b6c6d71c0aaf66ca995a`
- Current validated RTL Git SHA: `999bbcf91ddd45845a2b32c20add79e940c4ca40`
- Baseline mode: source-cache and luma-AC-throughput checkpoint with detailed
  VVC utilization rows restored in documentation.
- Current mode: same bitstream syntax, plus one-2x2-cell-per-cycle luma
  residual accumulation and one-cycle residual edge reconstruction for luma and
  chroma.

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
- `racehorses-sweep-420`: OK (64/64)
- `racehorses-multictu-420`: OK (10/10)
- Software and RTL bitstreams matched exactly.
- Software, RTL, and VTM reconstructions matched for every listed vector.

Synthesis configuration:

- command: `make synth CODEC=vvc SYNTH_DUT=vvc-encoder`
- DUT: `vvc-encoder`
- RTL top: `ff_vvc_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- exact-hash IBC for 4:4:4: disabled (`SYNTH_SUPPORT_EXACT_HASH_IBC_444=0`)

Synthesis result:

- Top `ff_vvc_encoder` synthesis completed in 439.1 seconds with 2146.46 MiB
  peak child RSS observed by the synthesis runner.
- Runtime exceeded the 300 second review threshold but stayed inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 10.7 seconds.
- Post-synthesis critical-path reporting completed in 74.5 seconds with peak
  memory 2146.46 MiB and topological path length 55.
- The longest topological path remains in `ff_vvc_cabac_syntax_frontend` IBC
  MVD absolute-value and EG1 prefix generation before `m_axis_data`, so the
  faster residual datapath did not become the reported timing limiter.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_vvc_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 139497 |
| Estimated LCs | 53283 |
| CARRY4 | 4039 |
| DSP48E1 | 9 |
| FDCE | 13154 |
| FDPE | 299 |
| FDRE | 22492 |
| FDSE | 4 |
| LUT1 | 1590 |
| LUT2 | 21025 |
| LUT3 | 7075 |
| LUT4 | 5798 |
| LUT5 | 8254 |
| LUT6 | 28080 |
| MUXF7 | 8335 |
| MUXF8 | 1647 |
| RAMB36E1 | 9 |

Delta from the previous source-cache and luma-AC-throughput checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 410.8 s | 439.1 s | +28.3 s |
| Peak synthesis RSS | 1993.60 MiB | 2146.46 MiB | +152.86 MiB |
| Cell report time | 9.8 s | 10.7 s | +0.9 s |
| Critical-path report time | 72.0 s | 74.5 s | +2.5 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 131750 | 139497 | +7747 |
| Estimated LCs | 49378 | 53283 | +3905 |
| CARRY4 | 3283 | 4039 | +756 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 13294 | 13154 | -140 |
| FDPE | 299 | 299 | +0 |
| FDRE | 22492 | 22492 | +0 |
| FDSE | 4 | 4 | +0 |
| LUT1 | 1461 | 1590 | +129 |
| LUT2 | 19886 | 21025 | +1139 |
| LUT3 | 6510 | 7075 | +565 |
| LUT4 | 5352 | 5798 | +446 |
| LUT5 | 7111 | 8254 | +1143 |
| LUT6 | 26393 | 28080 | +1687 |
| MUXF7 | 7535 | 8335 | +800 |
| MUXF8 | 1394 | 1647 | +253 |
| RAMB36E1 | 9 | 9 | +0 |

The area increase is the cost of moving residual reconstruction work out of
serial control states. In return, the 4:2:0 RaceHorses sweep aggregate drops
from 1,170,183 to 806,007 cycles, and the multi-CTU set drops from 1,251,691 to
848,456 cycles, with no bitrate or reconstruction changes. The synthesis
critical path remains unchanged, but the synthesis time and RSS increases should
be watched in the next VVC optimization cycle.

## 2026-06-19 Source Cache And Luma AC Throughput

Measured after adding the shared AXI frame-reader direct plane-row cache and
speeding up the VVC luma 8x8 residual AC coefficient path. The bitstream writer
configuration is unchanged from the previous AXI writer FIFO checkpoint.

Baseline and current sources:

- Baseline Git SHA: `f0fc6dd70d0aacccc6a8474560c14f5118defd14`
- Current validated RTL Git SHA: `ffb4179caa0de4a4a4e52f4a21eaf9ddb39efc64`
- Baseline mode: shared AXI4-Lite control registers, AXI4 memory-mapped
  aligned source word reads with a one-word cache, an eight-word bitstream
  writer FIFO, 4:4:4 palette enabled, exact-hash IBC disabled by default.
- Current mode: direct plane-row source cache, same bitstream writer FIFO, and
  one-cycle-per-coefficient VVC luma AC residual datapath; 4:4:4 palette
  enabled, exact-hash IBC disabled by default.
- Delta columns compare against the previous AXI writer FIFO checkpoint.

Validation configuration:

```sh
make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-sweep-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=screenshot-multictu-444 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=racehorses-sweep-420 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0

make validate-set CODEC=vvc \
  VALIDATION_SET=racehorses-multictu-420 \
  VALIDATION_SET_DIR=verification/test_vector_sets/local \
  VALIDATION_STOP_ON_FAIL=1 \
  VALIDATION_WITH_SYNTH=0
```

Validation result:

- `screenshot-sweep-444`: OK (64/64)
- `screenshot-multictu-444`: OK (10/10)
- `racehorses-sweep-420`: OK (64/64)
- `racehorses-multictu-420`: OK (10/10)
- Software and RTL bitstreams matched exactly.
- Software, RTL, and VTM reconstructions matched for every listed vector.

Synthesis configuration:

- command: `make synth CODEC=vvc SYNTH_DUT=vvc-encoder`
- DUT: `vvc-encoder`
- RTL top: `ff_vvc_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- exact-hash IBC for 4:4:4: disabled (`SYNTH_SUPPORT_EXACT_HASH_IBC_444=0`)

Synthesis result:

- Top `ff_vvc_encoder` synthesis completed in 410.8 seconds with 1993.60 MiB
  peak child RSS observed by the synthesis runner.
- Runtime exceeded the 300 second review threshold but stayed inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 9.8 seconds.
- Post-synthesis critical-path reporting completed in 72.0 seconds with peak
  memory 1993.60 MiB and topological path length 55.
- The longest topological path remains in `ff_vvc_cabac_syntax_frontend` IBC
  MVD absolute-value and EG1 prefix generation before `m_axis_data`.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_vvc_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 131750 |
| Estimated LCs | 49378 |
| CARRY4 | 3283 |
| DSP48E1 | 9 |
| FDCE | 13294 |
| FDPE | 299 |
| FDRE | 22492 |
| FDSE | 4 |
| LUT1 | 1461 |
| LUT2 | 19886 |
| LUT3 | 6510 |
| LUT4 | 5352 |
| LUT5 | 7111 |
| LUT6 | 26393 |
| MUXF7 | 7535 |
| MUXF8 | 1394 |
| RAMB36E1 | 9 |

Delta from the previous AXI writer FIFO checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 380.6 s | 410.8 s | +30.2 s |
| Peak synthesis RSS | 1935.25 MiB | 1993.60 MiB | +58.35 MiB |
| Cell report time | 8.9 s | 9.8 s | +0.9 s |
| Critical-path report time | 68.4 s | 72.0 s | +3.6 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 123744 | 131750 | +8006 |
| Estimated LCs | 46881 | 49378 | +2497 |
| CARRY4 | 3170 | 3283 | +113 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 13431 | 13294 | -137 |
| FDPE | 299 | 299 | +0 |
| FDRE | 18748 | 22492 | +3744 |
| FDSE | 4 | 4 | +0 |
| LUT1 | 1362 | 1461 | +99 |
| LUT2 | 19417 | 19886 | +469 |
| LUT3 | 6275 | 6510 | +235 |
| LUT4 | 4806 | 5352 | +546 |
| LUT5 | 6900 | 7111 | +211 |
| LUT6 | 24732 | 26393 | +1661 |
| MUXF7 | 6570 | 7535 | +965 |
| MUXF8 | 1308 | 1394 | +86 |
| RAMB36E1 | 9 | 9 | +0 |

The throughput work keeps the reported topological critical path flat. Area
increases are concentrated in the direct plane-row source cache and the
parallel luma AC accumulation tree. The cache payload/address registers are
valid-bit guarded and intentionally not reset, which reduced the first
post-change estimate before this documented run.

## 2026-06-18 AXI Writer FIFO

Measured after optimizing the shared AXI bridge used by every codec target. The
frame reader keeps the previous aligned one-word source cache, and the
bitstream writer now has an eight-word FIFO in front of the AXI write channel
while still emitting bursts of up to four packed AXI words. The VVC codec
algorithm, bitstreams, and reconstructions are unchanged from the previous AXI
word-cache checkpoint.

Baseline and current sources:

- Baseline Git SHA: `3bfd06419dc094776c36d417a7868ee19b774632`
- Current validated RTL Git SHA: `f0fc6dd70d0aacccc6a8474560c14f5118defd14`
- Baseline mode: shared AXI4-Lite control registers, AXI4 memory-mapped
  aligned source word reads with a one-word cache, 4-beat packed bitstream
  write bursts, 4:4:4 palette enabled, exact-hash IBC disabled by default.
- Current mode: same source word cache, plus an eight-word bitstream writer
  FIFO that can keep accepting packed words while a previous burst is draining;
  4:4:4 palette enabled, exact-hash IBC disabled by default.
- Delta columns compare against the previous AXI word-cache checkpoint.

Validation configuration:

```sh
make hardware-regression CODEC=vvc HARDWARE_REGRESSION_SYNTH=0
```

Validation result:

- `smoke`: OK (6/6)
- `sweep-420`: OK (64/64)
- `sweep-444`: OK (64/64)
- Software and RTL bitstreams matched exactly.
- Software, RTL, and VTM reconstructions matched for every smoke and sweep
  vector.

Synthesis configuration:

- command: `make synth CODEC=vvc SYNTH_DUT=vvc-encoder`
- DUT: `vvc-encoder`
- RTL top: `ff_vvc_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- exact-hash IBC for 4:4:4: disabled (`SYNTH_SUPPORT_EXACT_HASH_IBC_444=0`)

Synthesis result:

- Top `ff_vvc_encoder` synthesis completed in 380.6 seconds with 1935.25 MiB
  peak child RSS observed by the synthesis runner.
- Runtime exceeded the 300 second review threshold but stayed inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 8.9 seconds.
- Post-synthesis critical-path reporting completed in 68.4 seconds with peak
  memory 1935.25 MiB and topological path length 55.
- The longest topological path remains in `ff_vvc_cabac_syntax_frontend` IBC
  MVD absolute-value and EG1 prefix generation before `m_axis_data`.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_vvc_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 123744 |
| Estimated LCs | 46881 |
| CARRY4 | 3170 |
| DSP48E1 | 9 |
| FDCE | 13431 |
| FDPE | 299 |
| FDRE | 18748 |
| FDSE | 4 |
| LUT1 | 1362 |
| LUT2 | 19417 |
| LUT3 | 6275 |
| LUT4 | 4806 |
| LUT5 | 6900 |
| LUT6 | 24732 |
| MUXF7 | 6570 |
| MUXF8 | 1308 |
| RAMB36E1 | 9 |

Delta from the previous AXI word-cache checkpoint:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 377.4 s | 380.6 s | +3.2 s |
| Peak synthesis RSS | 1969.30 MiB | 1935.25 MiB | -34.05 MiB |
| Cell report time | 8.8 s | 8.9 s | +0.1 s |
| Critical-path report time | 68.2 s | 68.4 s | +0.2 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 123613 | 123744 | +131 |
| Estimated LCs | 46762 | 46881 | +119 |
| CARRY4 | 3176 | 3170 | -6 |
| DSP48E1 | 9 | 9 | +0 |
| FDCE | 13454 | 13431 | -23 |
| FDPE | 299 | 299 | +0 |
| FDRE | 18172 | 18748 | +576 |
| FDSE | 4 | 4 | +0 |
| LUT1 | 1684 | 1362 | -322 |
| LUT2 | 18989 | 19417 | +428 |
| LUT3 | 6039 | 6275 | +236 |
| LUT4 | 4830 | 4806 | -24 |
| LUT5 | 7134 | 6900 | -234 |
| LUT6 | 24699 | 24732 | +33 |
| MUXF7 | 7036 | 6570 | -466 |
| MUXF8 | 1388 | 1308 | -80 |
| RAMB36E1 | 9 | 9 | +0 |

The common AXI writer FIFO keeps the topological critical path flat and slightly
reduces peak memory. The estimated-LC increase is small for the VVC top and is
isolated to the shared bitstream writer rather than new codec logic.

## 2026-06-18 Shared AXI Interface Baseline

Measured after moving the VVC top-level integration to the shared AXI4-Lite
control interface plus AXI4 memory-mapped source/bitstream data movers, and
after aligning CRA slice headers with H.266 7.3.7/7.3.9 so multi-frame 4:4:4
streams decode in VTM.

Baseline and current sources:

- Baseline source: previous documented 4:4:4 BDPCM top-encoder synthesis
  checkpoint.
- Source base Git SHA for this run: `c6bcfcfae062a8671c4194d3e062f9b195134012`
- Current mode: shared AXI4-Lite control registers, AXI4 memory-mapped single
  beat source reads, AXI4 memory-mapped packed bitstream writes, 4:4:4 palette
  enabled, exact-hash IBC disabled by default.

Validation configuration:

```sh
make hardware-regression CODEC=vvc HARDWARE_REGRESSION_SYNTH=0
```

Validation result:

- `smoke`: OK (6/6)
- `sweep-420`: OK (64/64)
- `sweep-444`: OK (64/64)
- Software and RTL bitstreams matched exactly.
- Software, RTL, and VTM reconstructions matched for every smoke and sweep
  vector.

Synthesis configuration:

- command: `make synth CODEC=vvc SYNTH_DUT=vvc-encoder`
- DUT: `vvc-encoder`
- RTL top: `ff_vvc_encoder`
- board: `synth/boards/arty-z7-10.env`
- clock metadata: `25 MHz`
- timeout/review thresholds: 600 seconds hard stop, 300 seconds review
- memory limit: 3072 MiB
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- exact-hash IBC for 4:4:4: disabled (`SYNTH_SUPPORT_EXACT_HASH_IBC_444=0`)

Synthesis result:

- Top `ff_vvc_encoder` synthesis completed in 391.0 seconds with 1944.94 MiB
  peak child RSS observed by the synthesis runner.
- Runtime exceeded the 300 second review threshold but stayed inside the 600
  second hard timeout and 3072 MiB memory limit.
- Post-synthesis flattened-cell reporting completed in 9.0 seconds.
- Post-synthesis critical-path reporting completed in 69.6 seconds with peak
  memory 1944.94 MiB and topological path length 55.
- The longest topological path remains in `ff_vvc_cabac_syntax_frontend` IBC
  MVD absolute-value and EG1 prefix generation before `m_axis_data`.

Flattened Xilinx-cell estimate from
`synth/out/arty-z7-10/ff_vvc_encoder/cell_report.log`:

| Metric | Count |
|---|---:|
| Cells | 122311 |
| Estimated LCs | 46446 |
| CARRY4 | 3165 |
| DSP48E1 | 9 |
| FDCE | 13265 |
| FDPE | 299 |
| FDRE | 17596 |
| FDSE | 4 |
| LUT1 | 1584 |
| LUT2 | 19485 |
| LUT3 | 5880 |
| LUT4 | 4892 |
| LUT5 | 6846 |
| LUT6 | 24471 |
| MUXF7 | 6904 |
| MUXF8 | 1370 |
| RAMB36E1 | 9 |

Delta from the previous documented VVC top-synthesis baseline:

| Metric | Baseline | Current | Delta |
|---|---:|---:|---:|
| Synthesis time | 376.3 s | 391.0 s | +14.7 s |
| Peak synthesis RSS | 1883.0 MiB | 1944.9 MiB | +61.9 MiB |
| Critical-path report time | 68.3 s | 69.6 s | +1.3 s |
| Topological path length | 55 | 55 | +0 |
| Cells | 118404 | 122311 | +3907 |
| Estimated LCs | 45381 | 46446 | +1065 |

The AXI wrapper and CRA slice-header fix increase area modestly and do not
lengthen the reported topological critical path. The runtime remains above the
review threshold, so future top-level interface work should watch synthesis
time and memory as well as area.

## Recent CABAC Context Results

On June 4, 2026, the VVC CABAC residual-context bank was expanded from 70 to
265 context IDs so the RTL has initialized entries for the H.266 Table 132
last-significant, subblock-coded, significant-coefficient, parity-level, and
absolute-level residual ranges. The first expanded implementation bulk-reset a
packed 40-bit context table and caused the focused context-model Yosys run to
time out at 120 seconds.

The xk265 CABAC context path keeps a narrow initialized context table and
separates context initialization from live context updates. The VVC model uses
the same separation but cannot reuse xk265's 7-bit H.265 state representation:
H.266 stores two adaptive 16-bit probability states per context. To avoid a
wide reset fabric, reset invalidates the VVC table state instead of rewriting
every context entry in one cycle. The per-context rate byte is derived from the
static H.266 init table because it never changes after initialization.

Measured with `make synth SYNTH_DUT=vvc-cabac-context-model
SYNTH_TIMEOUT_SEC=120` on the Arty Z7-10 target:

- Yosys completed in 37.21 seconds user CPU, peak memory 562.55 MB.
- Estimated LCs: 9,677.
- Sequential cells: 8,480 `FDRE` for adaptive state and 265 `FDCE` for the
  valid bitmap.
- Longest topological path length: 11, from context ID bounds/mux through
  initial-state selection, LPS calculation, and `query_lps_full`.

Measured with `make synth SYNTH_DUT=vvc-cabac-stream-writer
SYNTH_TIMEOUT_SEC=120`:

- Yosys completed in 45.27 seconds user CPU, peak memory 567.25 MB.
- Design hierarchy estimated LCs: 11,355.
- Sequential cells: 8,480 `FDRE`, 489 `FDCE`, and 20 `FDPE`.
- Longest topological path length: 33, from `s_axis_ctx_id` through context
  lookup/LPS calculation, CABAC bin renormalization, and stream-writer state
  update.

Yosys still reports the context arrays as register lists because the current
stream writer consumes the queried context in the same cycle. Moving to a true
RAM-backed context table, like a staged xk265-style path, requires a pipeline
boundary between symbol input, context read/update, and bin coding.

## Top Encoder Baseline

Measured on June 7, 2026 at commit `e8d2624` with a verbose diagnostic run:

```sh
make synth SYNTH_DUT=vvc-encoder SYNTH_TIMEOUT_SEC=900 SYNTH_MEMORY_LIMIT_MB=6144 SYNTH_YOSYS_QUIET=0
```

Configuration:

- target: Arty Z7-10 (`xc7z010clg400-1`)
- clock metadata: 50 MHz
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- synthesis timeout: 900 seconds for measurement; routine synthesis now uses a
  300 second review threshold and a 600 second hard timeout
- synthesis memory cap: 6144 MiB for measurement; routine synthesis now uses a
  3072 MiB Yosys memory cap
- Yosys quiet logging: disabled for the measurement so module pressure points
  are visible in the log
- chroma residual subset: DC plus the 2x2 low-frequency AC group

Result:

- Top `ff_vvc_encoder` synthesis completed in 306.8 seconds with 1792.47 MB
  peak memory. This exceeds the current 300 second review threshold but is
  inside the 600 second default timeout.
- Estimated area: 44,096 LCs and 107,946 total cells, including 16,348 `FDRE`,
  8,288 `FDCE`, 288 `FDPE`, 4 `FDSE`, 24,558 `LUT6`, 11,795 `LUT2`,
  9,299 `MUXF7`, 1,772 `MUXF8`, 3,776 `CARRY4`, 7 `DSP48E1`, and 3 `RAMB36E1`.
- Post-synthesis critical-path reporting completed in 73.5 seconds and reported
  a peak memory of 1781.84 MB.
- Longest topological path length: 155, from `current_ctu_y_q` through visible
  CTU geometry and luma quantizer visibility/control into
  `luma_quant_recon.negative`.
- Compared with the June 6, 2026 baseline, timing stayed at path length 155.
  Runtime increased from 288.1 to 306.8 seconds, and critical-path report memory
  increased from 1301.47 to 1781.84 MB.
- Reports and artifacts:
  `synth/out/arty-z7-10/ff_vvc_encoder/yosys.log`,
  `synth/out/arty-z7-10/ff_vvc_encoder/critical_path.log`,
  `synth/out/arty-z7-10/ff_vvc_encoder/ff_vvc_encoder.post_synth.v`.

## Top Encoder Timing Optimization

Measured on June 8, 2026 after replacing the top-level 64-bit luma visibility
mask with per-TU visible column/row counts passed into
`ff_vvc_luma_quant_recon_8x8`.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

This run was made before the default memory cap was raised from 2048 to 3072
MiB. The higher default leaves margin for the ongoing optimization work because
the critical-path pass still approaches 2 GiB.

Result:

- Longest topological path improved from 155 to 146. The old path ran through
  the generated `luma_quant_visible_mask_w` mux chain into
  `luma_quant_recon.negative`; after this change the longest path moves into
  the chroma quant/reconstruction reference update path.
- Critical-path reporting completed in about 60 seconds with 1774.43 MB peak
  memory.
- Quiet top synthesis completed in roughly 291 seconds by artifact timestamps.
  The runner now records elapsed time and observed child RSS explicitly so
  future quiet runs leave a direct benchmark line in the log.
- Post-synth netlist restat reported 107,602 total cells and 44,291 estimated
  LCs. Compared with the June 7 baseline, total cells decreased by 344 while
  estimated LCs increased by 195.
- The luma quant/reconstruction module itself improved from 6,050 to 5,867
  estimated LCs, matching the intended removal of the visibility-mask muxing
  pressure.

## Top Encoder Chroma Edge Optimization

Measured on June 8, 2026 after changing `ff_vvc_chroma_quant_recon_420` to
emit only the reconstructed bottom row and right column needed by the 4:2:0
neighbour-reference path. The module no longer exports a full 4x4 reconstructed
sample block because the current RTL only consumes those edge samples for the
next chroma TU.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 282.4 seconds with 1808.77 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 54.9 seconds. The Yosys report itself
  recorded 1612.48 MB peak memory; the runner observed the same 1808.77 MiB
  peak child RSS across the full synthesis plus report flow.
- Longest topological path improved from 146 to 103. The path still starts at
  visible CTU geometry, but now runs through chroma TU ordering and the chroma
  quant/reconstruction edge update instead of the previous full reconstructed
  chroma-sample mux chain.
- Post-synth netlist restat reported 106,350 total cells and 43,758 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 1,252
  and estimated LCs decreased by 533.
- The standalone `ff_vvc_chroma_quant_recon_420` module restat reported 9,180
  cells and 5,808 estimated LCs.

## Top Encoder Sequential Chroma Quantization

Measured on June 8, 2026 after converting `ff_vvc_chroma_quant_recon_420` from
a fully combinational 4x4 transform/quant/reconstruction block into a small
registered datapath. The Cb and Cr instances still run in parallel, but each
instance now accumulates the 16 chroma samples over time, registers the DC and
2x2 low-frequency AC levels, and reconstructs only the bottom/right neighbour
edges used by the next chroma TU.

This trades the previous one-cycle chroma TU calculation for a short sequential
TU pass, but removes the full residual-to-reconstruction chain from the
top-level combinational timing path.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 272.2 seconds with 1750.73 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 54.8 seconds. The Yosys report itself
  recorded 1627.06 MB peak memory.
- Longest topological path improved from 103 to 58. The path now ends at the
  chroma AC accumulator register instead of continuing through chroma
  quantization, inverse transform, clipping, and neighbour-reference update.
- Post-synth netlist restat reported 101,591 total cells and 37,819 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 4,759
  and estimated LCs decreased by 5,939.
- The standalone `ff_vvc_chroma_quant_recon_420` module restat reported 4,709
  cells and 1,829 estimated LCs, down from 9,180 cells and 5,808 estimated LCs.

## Top Encoder Chroma Input Registering

Measured on June 8, 2026 after adding an input-load state to
`ff_vvc_chroma_quant_recon_420`. Each chroma quant/reconstruction instance now
latches the 4x4 sample TU plus its top/left neighbour references before the
sample-accumulation pass. This cuts the path from top-level chroma TU geometry
and neighbour-reference muxing into the chroma AC accumulator.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 273.0 seconds with 1729.66 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.0 seconds.
- Longest topological path improved from 58 to 52. The path moved out of the
  chroma quantizer and now ends in the residual symbol emitter's coefficient
  scan/rice-prefix path.
- Post-synth netlist restat reported 101,435 total cells and 37,957 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 156 and
  estimated LCs increased by 138, keeping area effectively flat while improving
  timing.
- The standalone `ff_vvc_chroma_quant_recon_420` module restat reported 5,254
  cells and 2,023 estimated LCs; the increase is the expected cost of the
  registered input samples and references.

## Top Encoder Residual Remainder Registering

Measured on June 8, 2026 after registering the residual symbol emitter's
remainder prefix/suffix EP payloads before presenting them on `m_axis_data`.
The regular residual scan captures the payload after the `gt3` decision, and
the second-pass residual path uses a short prep subphase before prefix/suffix
emission. This removes remainder construction from the output mux timing path.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 270.4 seconds with 1690.82 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.2 seconds.
- Longest topological path improved from 52 to 49. The path remains in the
  residual symbol emitter's scan/rice path, but no longer carries the full
  remainder prefix/suffix payload construction through the output mux.
- Post-synth netlist restat reported 97,960 total cells and 36,737 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 3,475
  and estimated LCs decreased by 1,220.
- The standalone `ff_vvc_residual_symbol_emitter_4x4` module restat reported
  3,608 cells and 1,543 estimated LCs. The local module grew slightly from the
  added payload registers, but the top-level netlist simplified overall.

## Top Encoder Residual Neighbor Table

Measured on June 8, 2026 after replacing the residual symbol emitter's dynamic
4x4 local-neighbor loop with a fixed scan-position neighbor table. The table
keeps the VVC residual local-template candidates explicit for each supported
4x4 scan position and avoids inferring local coordinate arithmetic and dynamic
coefficient indexing in the rice/remainder path.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 271.5 seconds with 1683.05 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.7 seconds.
- Longest topological path improved from 49 to 47. The residual emitter is no
  longer the longest path; the reported path now runs through the Annex B header
  width/slice-count Exp-Golomb path.
- Post-synth netlist restat reported 97,813 total cells and 36,608 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 147 and
  estimated LCs decreased by 129.
- The standalone `ff_vvc_residual_symbol_emitter_4x4` module restat reported
  3,854 cells and 1,607 estimated LCs. The local module grows because the
  neighbor table is explicit, but the top-level netlist simplifies and the
  residual path stops limiting the topological timing report.

## Top Encoder Direct CTU Geometry

Measured on June 8, 2026 after deriving Annex B header CTU column and row counts
directly from the visible dimensions. Since `ceil(ceil(visible, 8) / 64)` is
equivalent to `ceil(visible / 64)`, the header can keep coded-width/height
alignment for SPS dimensions and crop offsets while avoiding that alignment
logic on the CTU-count and slice-count path.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The smoke test passed all three cocotb encoder checks, including the luma AC and
chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 273.2 seconds with 1683.44 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.2 seconds.
- Longest topological path improved from 47 to 45. The path remains in the
  Annex B header slice-count Exp-Golomb path, but no longer passes through the
  coded-width alignment stage.
- Post-synth netlist restat reported 97,714 total cells and 36,602 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 99 and
  estimated LCs decreased by 6.
- The standalone `ff_vvc_annexb_header` module restat reported 1,438 cells and
  725 estimated LCs, down from 1,537 cells and 747 estimated LCs.

## Top Encoder Bounded Annex B Slice Count

Measured on June 8, 2026 after threading the encoder's configured
`MAX_VISIBLE_WIDTH` and `MAX_VISIBLE_HEIGHT` parameters into the Annex B header.
For the current 1024x1024 synthesis target, the PPS rectangular-slice count is
bounded to 16 CTU columns by 16 CTU rows, so the slice-count UE path uses a
bounded 8-bit `slice_count_minus1` value instead of a generic 16-bit UE helper.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=128 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=128 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

The 64x64 single-CTU smoke and 128x64 two-CTU smoke both passed all three
cocotb encoder checks, including the luma AC and chroma AC pattern cases.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 271.0 seconds with 1693.26 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 55.1 seconds.
- Longest topological path improved from 45 to 40. The Annex B slice-count UE
  path is no longer the longest path; the reported path now runs through the
  4:4:4 palette CU symbolizer's index lookup/update path.
- Post-synth netlist restat reported 97,535 total cells and 36,570 estimated
  LCs. Compared with the previous June 8 pass, total cells decreased by 179 and
  estimated LCs decreased by 32.
- The standalone `ff_vvc_annexb_header` module restat reported 1,176 cells and
  559 estimated LCs, down from 1,438 cells and 725 estimated LCs.

## Top Encoder Palette Index Bank Narrowing

Measured on June 8, 2026 after storing palette CU sample indices as 5-bit
internal entries instead of byte-wide entries. The externally visible palette
symbol packet format remains byte-aligned; the narrower bank only reduces the
internal 8x8 CU index storage and muxing. The previous longest path through the
palette CU lookup/update path moved out of the top critical path report.

Validation:

```sh
make rtl-test DUT=vvc-palette-cu-symbolizer
make rtl-test DUT=vvc-palette-symbolizer
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

All four smoke checks passed. The 4:4:4 top smoke covers the palette path, and
the 4:2:0 top smoke covers the residual path.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 266.9 seconds with 1662.09 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 53.0 seconds.
- Longest topological path remained 40. The reported path now runs through
  CTU-visible-height/chroma-TU geometry into `s_axis_ready`, instead of through
  the palette CU index lookup/update path.
- Post-synth netlist restat reported 97,070 total cells and 35,319 estimated
  LCs. Compared with the bounded Annex B baseline, total cells decreased by 465
  and estimated LCs decreased by 1,251.
- The standalone parameterized `ff_vvc_palette_cu_symbolizer` restat reported
  5,259 cells and 2,407 estimated LCs with the narrowed 5-bit index bank.

## Top Encoder Luma Edge Optimization

Measured on June 8, 2026 after changing `ff_vvc_luma_quant_recon_8x8` to emit
only the reconstructed bottom row and right column needed by the luma
neighbour-reference path. The module no longer exports a sparse 8x8
reconstructed-sample bus because the current top-level RTL only consumes those
edge samples for the next 8x8 luma TU.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
```

Both top smoke checks passed all three cocotb encoder checks. The 4:2:0 run
covers the residual path, and the 4:4:4 run covers the palette path while
sharing the same luma quant/reconstruction interface.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 253.1 seconds with 1535.06 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 52.6 seconds.
- Longest topological path remained 40. The reported path still runs through
  CTU-visible-height/chroma-TU geometry into `s_axis_ready`.
- Post-synth netlist restat reported 91,841 total cells and 33,774 estimated
  LCs. Compared with the palette index bank baseline, total cells decreased by
  5,229 and estimated LCs decreased by 1,545.
- The standalone `ff_vvc_luma_quant_recon_8x8` module restat reported 10,326
  cells and 4,129 estimated LCs with the edge-only reconstruction output.

## Top Encoder Streamed Luma Edge Reconstruction

Measured on June 8, 2026 after removing the 32-entry intermediate vertical
inverse-transform bank from `ff_vvc_luma_quant_recon_8x8`. The luma
quant/reconstruction block now streams the vertical and horizontal inverse
transform phases per reconstructed edge sample, preserving the same rounded
vertical intermediate result while keeping only the live accumulators needed for
the current bottom-row or right-column sample.

This trades additional luma-TU reconstruction cycles for lower register and mux
pressure. The current encoder accepts that latency because the optimization pass
is targeting area and timing before throughput tuning.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
```

Both top smoke checks passed all three cocotb encoder checks. The 4:2:0 smoke
simulation time increased from about 857 us to about 924 us because luma edge
reconstruction is now streamed instead of using the precomputed vertical bank.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 246.6 seconds with 1564.70 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 49.0 seconds.
- Longest topological path remained 40. The reported path still runs through
  CTU-visible-height/chroma-TU geometry into `s_axis_ready`.
- Post-synth netlist restat reported 91,178 total cells and 33,666 estimated
  LCs. Compared with the luma edge-output baseline, total cells decreased by
  663 and estimated LCs decreased by 108.
- The standalone `ff_vvc_luma_quant_recon_8x8` module restat reported 7,715
  cells and 3,411 estimated LCs, down from 10,326 cells and 4,129 estimated
  LCs with the previous intermediate vertical bank.

## Top Encoder Narrow Luma Residual Banks

Measured on June 8, 2026 after narrowing the luma quant/reconstruction
`cell_sum_q` and `coeff_level_q` banks. In the current fixed 8x8 luma subset,
each 2x2 residual cell sum is bounded by four 8-bit residuals, and the
quantized coefficient range used by the model fits in a signed 9-bit level.
The datapath keeps the same sign extension before inverse scaling.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
```

Both top smoke checks passed all three cocotb encoder checks.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 245.5 seconds with 1540.01 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 48.4 seconds.
- Longest topological path remained 40. The reported path still runs through
  CTU-visible-height/chroma-TU geometry into `s_axis_ready`.
- Post-synth netlist restat reported 90,749 total cells and 33,563 estimated
  LCs. Compared with the streamed luma edge baseline, total cells decreased by
  429 and estimated LCs decreased by 103.
- The standalone `ff_vvc_luma_quant_recon_8x8` module restat reported 7,421
  cells and 3,338 estimated LCs, down from 7,715 cells and 3,411 estimated LCs.

## Top Encoder Narrow Chroma AC Datapath

Measured on June 8, 2026 after narrowing the 4:2:0 chroma quant/reconstruction
AC accumulators, quantization intermediates, and reconstruction sums from 64
bits to 32 bits. The fixed 4x4 chroma TU residual range and transform basis
constants remain well inside signed 32-bit range, so the narrowed datapath keeps
the same quantized DC/AC levels and reconstructed edge samples.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
```

Both top smoke checks passed all three cocotb encoder checks. The 4:2:0 run
covers the narrowed chroma residual datapath, including the chroma AC pattern
case.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 243.9 seconds with 1558.48 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 48.1 seconds.
- Longest topological path remained 40. The reported path still runs through
  CTU-visible-height/chroma-TU geometry into `s_axis_ready`.
- Post-synth netlist restat reported 88,663 total cells and 33,278 estimated
  LCs. Compared with the narrow luma residual-bank baseline, total cells
  decreased by 2,086 and estimated LCs decreased by 285.
- The standalone `ff_vvc_chroma_quant_recon_420` module restat reported 4,505
  cells and 1,715 estimated LCs, down from 5,238 cells and 1,921 estimated LCs.

## Top Encoder Narrow Chroma Reconstruction Banks

Measured on June 8, 2026 after narrowing the 4:2:0 chroma residual-sum,
dequantized-coefficient, and vertical reconstruction registers. The narrowed
registers are sign-extended back to 32 bits before the shift-add transform
macros so the arithmetic width at each multiply-equivalent operation remains
unchanged.

Validation:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
```

Both top smoke checks passed all three cocotb encoder checks. An intermediate
version that fed narrowed registers directly into the shift-add macros failed
the 4:2:0 smoke because the shifts occurred at the narrowed register width; the
accepted version keeps explicit 32-bit sign-extension wires at those macro
inputs.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 242.4 seconds with 1542.87 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 47.8 seconds.
- Longest topological path remained 40. The reported path still runs through
  CTU-visible-height/chroma-TU geometry into `s_axis_ready`.
- Post-synth netlist restat reported 87,985 total cells and 32,892 estimated
  LCs. Compared with the narrow chroma AC datapath baseline, total cells
  decreased by 678 and estimated LCs decreased by 386.
- The standalone `ff_vvc_chroma_quant_recon_420` module restat reported 4,129
  cells and 1,620 estimated LCs, down from 4,505 cells and 1,715 estimated LCs.

## Top Encoder Lossless Palette Escape Coding

Measured on June 11, 2026 after adding raw 8-bit palette escape coding to the
current 4:4:4 palette path. Palette slices use the QP4 initialization path so
`palette_escape_val` reconstructs losslessly for the current 8-bit subset, and
the context model selects that QP4 initialization only for lossless palette
slices.

Validation:

```sh
cargo test vvc_palette_444
make rtl-test DUT=vvc-palette-cu-symbolizer
make rtl-test DUT=vvc-cabac-context-model
make rtl-test DUT=vvc-cabac-stream-writer
make rtl-test DUT=vvc-cabac-pipeline
make rtl-test DUT=vvc-cabac
make test-vectors TEST_VECTOR_SET=palette-escape-444
make validate INPUT=verification/generated/test_vectors/palette_escape_64x64_1f_yuv444p8.yuv VALIDATE_SYNTH=0
make validate-set VALIDATION_SET=palette-escape-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate INPUT=verification/generated/test_vectors/racehorses_crop_64x64_1f_yuv420p8.yuv VALIDATE_SYNTH=0
```

The 64x64 palette-escape smoke and all 64 generated palette-escape geometry
vectors passed with lossless reconstruction (`inf` PSNR). The 4:2:0 RaceHorses
crop guard passed on the existing lossy residual path with software, RTL, and
VTM reconstruction checksums matching; its PSNR was 22.55 dB.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 273.4 seconds with 1594.46 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 56.2 seconds with the same observed peak
  child RSS.
- Longest topological path remained 40. The reported path still starts at
  `current_ctu_y_q` and runs through visible CTU/chroma-TU geometry into
  `s_axis_ready`.
- Post-synth netlist restat reported 98,584 total cells and 36,067 estimated
  LCs. Compared with the narrow chroma reconstruction-bank baseline, total
  cells increased by 10,599 and estimated LCs increased by 3,175.
- The local area growth is concentrated in the new raw palette escape storage
  and common CABAC palette syntax expansion. Restat reported
  `ff_vvc_palette_cu_symbolizer` at 9,208 cells and 3,174 estimated LCs, and
  `ff_vvc_cabac_syntax_frontend` at 8,798 cells and 2,735 estimated LCs.
- Runtime stayed under the 300 second review threshold, memory stayed well below
  the 3072 MiB Yosys cap, and the topological path length did not regress.

## Top Encoder CTU-Local IBC Hash Matcher

Measured on June 11, 2026 after adding the first 4:4:4 IBC path. The feature
uses an exact 32-bit hash match over previously coded 8x8 CUs inside the current
64x64 CTU-local slice, then falls back to lossless palette coding for unmatched
CUs. The initial combinational implementation searched all 64 hash entries in
one cycle and was rejected before baselining: Yosys completed in 402.8 seconds
with 1836.38 MiB peak child RSS, but the longest topological path was 266 and
ran through the IBC hash table compare fabric.

The committed baseline scans one candidate per cycle. A 4:4:4 CU takes 192
input sample cycles, so the 64-entry CTU-local search completes before the next
CU can require its final IBC/palette decision.

Validation:

```sh
make validate-set VALIDATION_SET=screenshot-smoke-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set VALIDATION_SET=screenshot-multictu-444 RTL_MAX_VISIBLE_WIDTH=192 RTL_MAX_VISIBLE_HEIGHT=192 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set VALIDATION_SET=racehorses-sweep-420 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate INPUT=verification/generated/test_vectors/RaceHorses_136x80_1f_yuv420p8.yuv RTL_MAX_VISIBLE_WIDTH=136 RTL_MAX_VISIBLE_HEIGHT=80 VALIDATE_SYNTH=0
```

The screenshot smoke and multi-CTU 4:4:4 sets passed losslessly against VTM. The
RaceHorses 4:2:0 sweep and the scaled 136x80 RaceHorses guard also passed,
preserving the existing lossy residual path.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Result:

- Top `ff_vvc_encoder` synthesis completed in 416.9 seconds with 1824.41 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 79.6 seconds with the same observed peak
  child RSS.
- Longest topological path increased from 40 to 55. The new reported path runs
  through `ff_vvc_cabac_syntax_frontend` IBC MVD absolute-value and EG1 prefix
  generation before `m_axis_data`.
- Post-synth netlist restat reported 125,999 total cells and 46,273 estimated
  LCs. Compared with the lossless palette escape baseline, total cells increased
  by 27,415 and estimated LCs increased by 10,206.
- The largest new local block is `ff_vvc_ibc_hash_matcher`, at 23,485 primitive
  cells in the post-synth JSON. Its area is dominated by CTU-local hash/BV/MVD
  register tables and search-control logic.
- `ff_vvc_cabac_syntax_frontend` grew from 8,798 cells and 2,735 estimated LCs
  to 11,987 cells and 4,283 estimated LCs because it now expands IBC CU packets
  into skip, pred-mode, merge, MVD, and coded-flag syntax.
- `ff_vvc_palette_cu_symbolizer` stayed roughly flat at 9,191 cells and 3,072
  estimated LCs.
- Runtime exceeds the 300 second review threshold but remains inside the 600
  second hard timeout and the 3072 MiB Yosys memory cap. Treat future increases
  from this point as a synthesis-efficiency regression unless they come with a
  deliberate new coding tool.

## Top Encoder 4:4:4 Transform-Skip Residual

Measured on June 11, 2026 after adding the first 4:4:4 transform-skip residual
path. The current runtime IBC subset only uses the spatial left 8x8 CU as the
predictor and codes the changed top-left 4x4 residual coefficients with
transform skip. The older exact-hash IBC matcher is left in the source tree as a
future/debug block, but it is disabled in the default top synthesis because its
precomputed BVDs do not yet account for runtime transform-skip IBC decisions in
the H.266 8.6.2.2 BVP/HMVP state.

Validation:

```sh
cargo test vvc_palette_444_uses
make validate-set VALIDATION_SET=all-sweeps VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set VALIDATION_SET=transform-skip-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set VALIDATION_SET=palette-escape-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set VALIDATION_SET=screenshot-smoke-444 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set VALIDATION_SET=screenshot-multictu-444 RTL_MAX_VISIBLE_WIDTH=192 RTL_MAX_VISIBLE_HEIGHT=192 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate-set VALIDATION_SET=racehorses-sweep-420 VALIDATION_STOP_ON_FAIL=1 VALIDATION_WITH_SYNTH=0
make validate INPUT=verification/generated/test_vectors/RaceHorses_136x80_1f_yuv420p8.yuv RTL_MAX_VISIBLE_WIDTH=136 RTL_MAX_VISIBLE_HEIGHT=80 VALIDATE_SYNTH=0
```

Before commit, the final synthesis-area cleanup was guarded with top-level
smoke tests instead of rerunning the full sweeps:

```sh
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=3
make rtl-test DUT=vvc-encoder RTL_VISIBLE_WIDTH=64 RTL_VISIBLE_HEIGHT=64 RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CHROMA_FORMAT_IDC=1
```

Both smokes passed all three cocotb encoder checks.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Configuration:

- target: Arty Z7-10 (`xc7z010clg400-1`)
- clock metadata: 25 MHz
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- exact-hash IBC for 4:4:4: disabled (`SYNTH_SUPPORT_EXACT_HASH_IBC_444=0`)
- synthesis timeout: 600 seconds, with a 300 second review threshold
- synthesis memory cap: 3072 MiB

Result:

- Top `ff_vvc_encoder` synthesis completed in 386.4 seconds with 1853.02 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 71.8 seconds with the same observed peak
  child RSS.
- Longest topological path stayed at 55. The reported path remains in
  `ff_vvc_cabac_syntax_frontend` IBC MVD absolute-value and EG1 prefix
  generation before `m_axis_data`.
- Post-synth netlist restat reported 114,656 total cells and 44,106 estimated
  LCs. Compared with the CTU-local IBC hash matcher baseline, total cells
  decreased by 11,343 and estimated LCs decreased by 2,167 because the inactive
  exact-hash matcher is no longer synthesized by default.
- Compared with an intermediate ungated transform-skip run, the default gate
  removed 24,945 cells and 8,695 estimated LCs, reduced Yosys synthesis time
  from 470.8 to 386.4 seconds, and reduced peak child RSS from 2058.77 to
  1853.02 MiB.
- Compared with the lossless palette escape baseline, total cells are still up
  by 16,072 and estimated LCs are up by 8,039. The growth comes from
  transform-skip residual packet collection/emission and IBC syntax expansion in
  the CABAC frontend, not from the disabled exact-hash matcher.
- Restat reported the largest local blocks as the CABAC context model at
  29,478 cells and 12,293 estimated LCs, the CABAC syntax frontend at 12,934
  cells and 4,590 estimated LCs, the CTU residual symbolizer at 6,831 cells and
  4,439 estimated LCs, and the palette CU symbolizer at 9,286 cells and 3,097
  estimated LCs.

## Top Encoder 4:4:4 BDPCM

Measured on June 11, 2026 after adding the first 4:4:4 horizontal BDPCM path.
The current subset only tries horizontal BDPCM for 8x8 CUs that have a
left-neighbour predictor and nonzero coefficients confined to the top-left 4x4
group. Wider BDPCM direction and block-size coverage remains future work.

Validation:

```sh
cargo test vvc_
make validate INPUT=verification/generated/test_vectors/bdpcm_horizontal_64x64_1f_yuv444p8.yuv VALIDATE_SYNTH=0
make hardware-regression HARDWARE_REGRESSION_EXTRA_SET=bdpcm-444 HARDWARE_REGRESSION_SYNTH=0
```

The hardware regression passed all 192 SW/RTL/VTM geometry cases: the public
4:2:0 sweep, the public 4:4:4 screen-block sweep, and the new 4:4:4 BDPCM
sweep.

Synthesis:

```sh
make synth SYNTH_DUT=vvc-encoder
```

Configuration:

- target: Arty Z7-10 (`xc7z010clg400-1`)
- clock metadata: 25 MHz
- max visible size: 1024x1024
- 4:4:4 palette support: enabled
- exact-hash IBC for 4:4:4: disabled (`SYNTH_SUPPORT_EXACT_HASH_IBC_444=0`)
- synthesis timeout: 600 seconds, with a 300 second review threshold
- synthesis memory cap: 3072 MiB

Result:

- Top `ff_vvc_encoder` synthesis completed in 376.3 seconds with 1882.95 MiB
  peak child RSS observed by the synthesis runner.
- Critical-path reporting completed in 68.3 seconds with the same observed peak
  child RSS.
- Longest topological path stayed at 55. The reported path remains in
  `ff_vvc_cabac_syntax_frontend` IBC MVD absolute-value and EG1 prefix
  generation before `m_axis_data`, so BDPCM did not introduce the top reported
  timing path.
- Post-synth netlist restat reported 118,404 total cells and 45,381 estimated
  LCs. Compared with the 4:4:4 transform-skip residual baseline, total cells
  increased by 3,748 and estimated LCs increased by 1,275.
- Runtime stayed inside the 600 second hard timeout but exceeded the 300 second
  review threshold. Peak child RSS increased by about 30 MiB from the previous
  top-encoder baseline and remains inside the 3072 MiB cap.

## Top Encoder Vivado Z7-10 Timing Snapshot

Measured on June 9, 2026 with Vivado 2025.2 after the narrow chroma
reconstruction-bank baseline. This is a post-synthesis-only vendor snapshot for
the Arty Z7-10 target, not a placed/routed implementation result.

Configuration:

- target: Arty Z7-10 (`xc7z010clg400-1`)
- top: `ff_vvc_encoder`
- clock constraint: 50 MHz, 20.000 ns period
- max visible size: 1024x1024
- 4:4:4 palette support: enabled

Result:

- Vivado `synth_design` completed in 15:49 elapsed time.
- Reported Vivado memory: 2815 MB peak for the main process; the Vivado log
  also reported 5450 MB peak overall PSS across forked synthesis workers.
- Utilization on Z7-10: 23,022 LUTs out of 17,600, or 130.81%; 22,616
  registers out of 35,200, or 64.25%; 3 BRAM tiles out of 60; 5 DSPs out of
  80. The current design therefore does not fit the Z7-10 by LUT count.
- The 50 MHz timing constraint failed with WNS -15.797 ns and TNS
  -22,186.822 ns across 2,021 failing setup endpoints. Hold timing was clean
  with WHS 0.137 ns.
- The worst setup path ran from `current_ctu_y_q_reg[0]/C` to
  `cb_chroma_quant_recon/left_ref_q_reg[31]/D`. Vivado reported 35.646 ns data
  path delay, with 13.697 ns logic and 21.949 ns estimated routing.
- The failing 50 MHz constraint implies a post-synthesis minimum period of
  roughly 35.8 ns, or about 27.9 MHz, before placement/routing. Until the
  geometry-to-chroma reconstruction path is pipelined and the design fits the
  selected device, treat 25 MHz as the realistic near-term clock target for
  board-level planning.
