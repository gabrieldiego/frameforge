# ASIC Synthesis Research Baseline

This note records the current research baseline for estimating FrameForge as an
ASIC. It is intentionally practical: the goal is not to claim commercial
competitiveness from FPGA reports, but to define a reproducible path from the
existing RTL to standard-cell area, timing, and throughput estimates.

FrameForge currently targets two encoder subsets:

- VVC/H.266: 8-bit planar 4:2:0 lossy residual plus 4:4:4 lossless
  screen-content coding.
- AV2: 8-bit planar 4:4:4 lossless screen-content coding plus a maintained
  lossy 4:2:0 residual path.

The active top-level throughput target is documented in
[validation/targets.md](validation/targets.md): `cycles/input pixel <= 1.000`
for streams whose width and height are both at least 64 pixels. At that rate,
the pixel pipeline needs about 124.4 MHz for 1920x1080 at 60 fps and about
497.7 MHz for 3840x2160 at 60 fps. Those numbers are only raw pixel-throughput
requirements. AXI bandwidth, setup/drain time, entropy burstiness, memory
traffic, and clock closure still need to be measured for every implementation
checkpoint.

## Current Evidence

The current synthesis reports are FPGA-oriented:

- [AV2 synthesis report](av2/synthesis.md)
- [VVC synthesis report](vvc/synthesis.md)

These are useful for catching runaway logic, memory growth, and timing-risk
trends, but they are not ASIC area estimates. LUTs, carry chains, RAMB macros,
and FPGA routing constraints do not map cleanly to standard-cell gates or
metal-dominated ASIC timing.

The following Yosys FPGA-style checkpoints show the relative scale that was
current when this note was written. The Git SHAs are the source commits recorded
by each codec's synthesis report; they are not intended to track repository
`HEAD` after later work lands.

| Codec | Report checkpoint | Baseline source SHA | Current source SHA | Current Yosys target | Estimated LCs | Flattened cells | Topological path |
|---|---|---|---|---|---:|---:|---:|
| AV2 | `Streamed entropy output` in [av2/synthesis.md](av2/synthesis.md) | `7383aee7b77230a85bdd86c5cf151008ba7de553` | `ccc1e283b43c5833c276605f1f583d9c1476f4b3` | Arty Z7-10 metadata, 25 MHz | 63,438 | 135,832 | 124 |
| VVC | `2026-06-29 VVC Report Checkpoint` in [vvc/synthesis.md](vvc/synthesis.md) | `d2cb6801f111a0023d7f982b875faccbf8c17f91` | `28fa335ecfba2e9463e416688f0144bd29f159f3` | Arty Z7-10 metadata, 25 MHz | 72,133 | 196,393 | 192 |

The latest output-utilization reports are also FPGA/RTL simulation metrics, not
ASIC metrics:

- [AV2 output utilization](av2/output-utilization.md)
- [VVC output utilization](vvc/output-utilization.md)

For ASIC planning, the important throughput number is cycles per input pixel.
Bubble rate remains useful to find internal stalls, but it is content-dependent
because highly compressed streams naturally emit fewer bytes.

## Recommended Open ASIC Flow

The first ASIC experiment should be same-flow comparative synthesis, not a
single absolute claim. The useful question is:

> Does a change make FrameForge smaller, faster, or more energy-efficient when
> VVC, AV2, and any comparison RTL are run through the same open flow?

Recommended tool stack:

| Stage | Tool | Role |
|---|---|---|
| RTL synthesis | [Yosys](https://yosyshq.readthedocs.io/projects/yosys/en/latest/) | Verilog/SystemVerilog front end, optimization, and mapping to Liberty standard-cell libraries. |
| Static timing | [OpenSTA](https://openroad.readthedocs.io/en/latest/main/src/sta/README.html) | Gate-level timing with Liberty, SDC, and optional parasitics/activity files. |
| Physical implementation | [OpenROAD](https://openroad.readthedocs.io/en/latest/) or [OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) | Floorplan, placement, CTS, routing, parasitic extraction, and routed timing/power reports. |
| Integrated open flow | [OpenLane 2](https://openlane2.readthedocs.io/en/latest/) | Scripted RTL-to-GDS flow around Yosys/OpenROAD-style tools. |

Yosys is the fastest way to get an initial standard-cell netlist and cell-area
estimate. OpenROAD/OpenLane should be used once the RTL can be cleanly
converted into a cell netlist, because post-placement and post-route timing are
more meaningful than logic-only delay estimates.

The first FrameForge ASIC flow should produce these artifacts per codec:

- synthesized gate-level Verilog;
- Liberty-mapped cell area;
- NAND2-equivalent or gate-equivalent count, computed from a chosen reference
  cell;
- flop count and inferred memory/macros;
- worst negative slack and estimated Fmax;
- post-placement/post-route area and utilization;
- timing path report for the worst paths;
- optional VCD/SAIF-based switching activity for later power estimates.

## Candidate Process Technologies

The open PDK choice controls what an ASIC estimate means. The same RTL should
be run against more than one node once the flow is stable.

| Technology | Public status | Suggested use in FrameForge |
|---|---|---|
| [SkyWater SKY130](https://github.com/google/skywater-pdk) | Open 130 nm PDK, described by the project as experimental/preview for open-source use. | Best first manufacturable-style baseline. Mature enough for open flows, conservative timing, large geometry. |
| [GlobalFoundries GF180MCU](https://github.com/google/gf180mcu-pdk) | Open 180 nm MCU PDK. | Conservative low-density baseline. Useful to expose memory/macros and routing pressure, not a modern video-ASIC performance target. |
| [IHP SG13G2](https://github.com/IHP-GmbH/IHP-Open-PDK) | Open 130 nm BiCMOS PDK with analog/mixed-signal/RF focus and digital support. | Alternative 130 nm baseline, useful if the flow is available locally and gives better standard-cell/memory support. |
| Nangate45 / FreePDK45-style flows | Academic/open 45 nm cell-library baseline, not a foundry production target. | Useful for normalized research comparison and faster projected timing than 130/180 nm. Treat as predictive. |
| ASAP7 | Predictive academic 7 nm PDK/library family. | Useful only for scaling experiments and architectural sensitivity, not for a manufacturable claim. |

The initial implementation should start with SKY130 or GF180 because these are
the most common open-source ASIC flow targets. Once the scripts are stable, a
45 nm or 7 nm predictive run can be added to estimate how much the architecture
benefits from advanced-node scaling.

## Throughput Projections

The most useful projection is based on cycles per input pixel:

```text
required_clock_hz = width * height * frames_per_second * cycles_per_input_pixel
```

For common video rates:

| Target stream | Pixels/s | Required clock at 1.000 cycle/pixel |
|---|---:|---:|
| 1920x1080p60 | 124.4 Mpixel/s | 124.4 MHz |
| 3840x2160p60 | 497.7 Mpixel/s | 497.7 MHz |
| 3840x2160p30 | 248.8 Mpixel/s | 248.8 MHz |
| 7680x4320p30 | 995.3 Mpixel/s | 995.3 MHz |

For a design that runs at `N` cycles per input pixel, multiply the clock
requirement by `N`. For example, a 2.0 cycle/pixel design needs about 249 MHz
for 1080p60 and about 995 MHz for 4Kp60.

Current FrameForge reports show that some paths are already near this target
for selected 4:2:0 AV2 multi-CTU streams, while 4:4:4 screen-content paths and
VVC paths still need throughput work. These reports should be treated as RTL
simulation throughput data, not ASIC timing data.

## Area Projection Method

Do not convert FPGA LUTs directly to ASIC gates. Use these staged estimates
instead:

1. Run the existing FPGA-oriented Yosys/Vivado flow to catch runaway RTL.
2. Run Yosys with a standard-cell Liberty library for the selected process.
3. Convert cell area to a gate-equivalent number using one fixed reference
   cell, usually NAND2.
4. Run OpenROAD/OpenLane placement and routing.
5. Use post-route cell area, die/core area, utilization, WNS/TNS, and routed
   timing as the official ASIC estimate for that checkpoint.
6. Normalize results as:
   - `kGE`;
   - `mm^2`;
   - `kGE / Gpixel/s`;
   - `mm^2 / Gpixel/s`;
   - SRAM or inferred-memory bits;
   - cycles/input pixel;
   - estimated mW or pJ/pixel only after VCD/SAIF activity is available.

The most important comparison is between checkpoints in the same flow. If the
absolute area is inaccurate because the PDK is old or predictive, the delta is
still useful if the tool version, library, constraints, and floorplan are held
constant.

## External Comparison Points

Public commercial encoder IP pages rarely publish area or gate counts. They are
still useful to understand integration style and throughput class.

Allegro DVT's public
[E300 encoder page](https://www.allegrodvt.com/products/e300-series-video-encoder/)
describes a multi-format hardware encoder supporting H.264, H.265, VP9, AV1,
JPEG, and VVC. The same page advertises 4K single-core encoding, APB for
control registers, AXI interfaces for data access, RTL deliverables, C control
software, and a bit-accurate software reference model. This supports
FrameForge's chosen public hardware shape: control-plane registers plus
memory-mapped data access through AXI.

Allegro DVT's public
[D300 decoder page](https://www.allegrodvt.com/products/d300-series-video-decoder/)
similarly documents APB control, AXI data access, RTL source deliverables,
control software, and a software reference model for a multi-format decoder.
Its
[AV2 decoder announcement](https://www.allegrodvt.com/news/pulsar-decoder-ip-support-av2-video-codec/)
states that the D400 AV2 decoder targets high-performance use cases up to 8K
while optimizing silicon footprint, memory bandwidth, and power. These public
pages do not publish usable gate counts or mm2 area.

Academic block-level papers provide more concrete numeric anchors, but they are
not full-encoder comparisons:

- A
  [VVC fractional motion-estimation architecture](https://arxiv.org/abs/2302.06167)
  synthesized in GF 28 nm reports 192k gates, 400 MHz for 4K@30, and 12.64 mW.
  This is one inter-coding block, not a full encoder.
- A
  [VVC transform-block ASIC paper](https://arxiv.org/abs/2002.07461)
  reports a pipelined VVC transform design with 32 multipliers, two pixels per
  cycle, 600 MHz operation, and 4K@48 decoder throughput.
- A
  [VVC inverse-transform ASIC paper](https://arxiv.org/abs/2107.11659)
  reports a pipelined inverse-transform design with 64 multipliers, one sample
  per cycle, 600 MHz operation, and 4K@30 decoder throughput for 4:2:2 content.

These papers are useful as evidence that heavily pipelined codec blocks can
reach several hundred MHz in ASIC flows, but they do not bound FrameForge's
full entropy, prediction, AXI, and reconstruction path.

Reference comparison table:

| Module or IP | Feature implemented | Technology used | Reported result | Source |
|---|---|---|---|---|
| Allegro DVT E300 encoder IP | Multi-format encoder supporting H.264, H.265, VP9, AV1, JPEG, and VVC; APB control and AXI data access; RTL and software model deliverables | Commercial IP, technology node not disclosed | Public page claims 4K encoding in a single core and beyond with multi-core configuration; no public gate count, area, frequency, or power | [E300 encoder page](https://www.allegrodvt.com/products/e300-series-video-encoder/) |
| Allegro DVT D300 decoder IP | Multi-format decoder supporting H.265, H.264, JPEG, AV1, VP9, and VVC variants; APB control and AXI data access | Commercial IP, technology node not disclosed | Public page claims scalable multi-core decoding up to 8K; no public gate count, area, frequency, or power | [D300 decoder page](https://www.allegrodvt.com/products/d300-series-video-decoder/) |
| Allegro DVT D400 AV2 decoder IP | AV2-capable multi-standard decoder IP | Commercial IP, technology node not disclosed | Public announcement claims high-performance use cases up to 8K and optimized silicon footprint, memory bandwidth, and power; no public gate count, area, frequency, or power | [AV2 decoder announcement](https://www.allegrodvt.com/news/pulsar-decoder-ip-support-av2-video-codec/) |
| VVC fractional motion estimation block | Error-surface-based FME for VVC inter coding, 13 CU sizes from 128x128 to 8x8 | GF 28 nm synthesis | 192k gates, 400 MHz for 4K@30, 12.64 mW; 8K@30 at 631 MHz in quadtree-only mode | [arXiv:2302.06167](https://arxiv.org/abs/2302.06167) |
| VVC transform block | Pipelined multi-standard transform block for AVC/HEVC/VVC with DCT/DST support | ASIC target, process not disclosed in the arXiv abstract | 32 regular multipliers, two pixels/cycle, 600 MHz, 4K@48 decoder throughput | [arXiv:2002.07461](https://arxiv.org/abs/2002.07461) |
| VVC inverse-transform block | Pipelined inverse transform with MTS and LFNST support | ASIC target, process not disclosed in the arXiv abstract | 64 regular multipliers, one sample/cycle, 600 MHz, 4K@30 decoder throughput for 4:2:2 | [arXiv:2107.11659](https://arxiv.org/abs/2107.11659) |

## Projected FrameForge ASIC Targets

The table above does not provide enough information to calculate FrameForge
area directly. It does provide useful guardrails:

- A single VVC FME block can be about 192k gates in GF 28 nm while reaching
  400 MHz. FrameForge's current lossless screen-content subset does not include
  full inter motion estimation, so an early AV2/VVC screen-content ASIC core
  should be kept in the same order as a few such blocks, not tens of them.
- Published transform blocks reach 600 MHz when deeply pipelined. FrameForge
  should not assume this for the whole encoder, but it should treat
  several-hundred-MHz ASIC timing as plausible after critical entropy,
  predictor, and AXI paths are pipelined.
- Commercial IP pages emphasize AXI/APB-style system integration and memory
  bandwidth. FrameForge's shared AXI control/read/write interface is aligned
  with this public integration pattern.

Reasonable first targets by open ASIC flow:

| Flow target | What the result means | First-pass FrameForge target | Why this target is useful |
|---|---|---|---|
| SKY130 with Yosys + OpenROAD/OpenLane | Open, reproducible 130 nm physical estimate; conservative timing and large area | Timing-clean at 100-200 MHz for the core clock, with area recorded in kGE and mm2. Treat 1080p60 as the practical throughput target if cycles/input pixel is at or below 1.000. | Establishes a manufacturable-style open baseline and exposes memory, routing, and fanout problems early. |
| GF180MCU with Yosys + OpenROAD/OpenLane | Open, reproducible 180 nm physical estimate; even more conservative density/timing | Timing-clean at 75-150 MHz, with strong pressure to keep memories explicit and small. 1080p60 at one cycle/pixel is a stretch target. | Useful as a worst-case old-node baseline and for checking whether the architecture depends on unrealistic density. |
| IHP SG13G2 with Yosys + OpenROAD/OpenLane | Open 130 nm-class alternative with a different library/process ecosystem | Similar to SKY130: target 100-200 MHz initially, then compare area/timing against SKY130 under the same source SHA. | Gives a second open PDK sanity check so conclusions are not tied to one cell library. |
| Nangate45 or equivalent academic 45 nm flow | Predictive/academic standard-cell comparison, not a production claim | Target 250-500 MHz if the critical paths are kept short. At one cycle/pixel, this starts to cover 4Kp30 and approaches 4Kp60. | Bridges the gap between old open nodes and the 28 nm-class academic hardware references. |
| ASAP7 or equivalent predictive 7 nm flow | Architecture-scaling experiment only | Target 500 MHz or higher for a well-pipelined core. At one cycle/pixel, 4Kp60 becomes the relevant milestone. | Tests whether the architecture scales when cell delays shrink, while still treating the result as non-manufacturing evidence. |

For the first report, the best metric is not one absolute area number. The
report should compare AV2 and VVC under the same flow, at the same source SHA
family, with:

- standard-cell area and kGE;
- post-route WNS/Fmax;
- memory bits and any mapped SRAM macros;
- cycles/input pixel from RTL validation;
- `kGE / Gpixel/s` and `mm2 / Gpixel/s`;
- the worst path module and whether it matches the RTL/Yosys critical-path
  diagnosis.

If the early screen-content encoder exceeds roughly 1-2 MGE before adding full
inter search, deblocking, SAO/CDEF-like filters, or large reference buffers,
that should trigger an area audit. If it cannot close above 125 MHz in 130 nm
or above roughly 250 MHz in a 45 nm academic flow, that should trigger a timing
audit before adding major new coding tools.

The practical comparison set for FrameForge should therefore be:

1. FrameForge AV2 versus FrameForge VVC in the same open ASIC flow.
2. FrameForge current checkpoint versus prior FrameForge checkpoints.
3. If available and synthesizable, an HEVC-like RTL such as the local `xk265`
   hardware tree, run through exactly the same flow.
4. Published academic block numbers only as sanity checks for sub-block scale.

## Technology Scaling Expectations

The following should be treated as planning expectations, not measured results:

- SKY130/GF180: good for open reproducibility and area-ranking, but unlikely to
  be a realistic final node for 4Kp60 full-feature video encoding unless the
  architecture is deeply parallel and area is allowed to grow substantially.
- 45 nm academic flows: useful middle ground for estimating how much timing
  improves once the design leaves FPGA fabric and old open PDKs. Results are
  still research estimates.
- 28 nm-class commercial nodes: public VVC block papers show several-hundred-MHz
  blocks in this class. A production FrameForge-like encoder would likely need
  this class or better for practical 4K throughput if cycles/input pixel remains
  near 1.000.
- 16/12/7 nm-class nodes: likely enough frequency and density for multi-stream
  or 4K/8K variants, but open predictive PDK results should be used only for
  architecture scaling and relative deltas.

The main architectural requirement is not just a faster node. To make advanced
nodes useful, FrameForge must keep moving toward streaming block pipelines,
small local memories, low fanout control, bounded entropy state, and clean
valid/ready boundaries.

## First ASIC Experiment

The first useful ASIC experiment should be deliberately narrow:

1. Select one codec top, preferably AV2 because it is the active growth area.
2. Freeze the validated source SHA and record the same validation summary used
   in `docs/av2/synthesis.md`.
3. Create an ASIC synthesis file list from the same RTL sources used by the
   current FPGA synthesis flow.
4. Run Yosys against SKY130 or GF180 standard-cell Liberty.
5. Record:
   - standard-cell area;
   - NAND2-equivalent count;
   - flop count;
   - inferred memories;
   - worst logic path from OpenSTA;
   - whether memories stayed as flops or mapped to macros.
6. Run OpenROAD/OpenLane with a simple floorplan and one clock.
7. Record post-place and post-route timing, area, utilization, and congestion.
8. Repeat for VVC with identical tool versions and constraints.

Success for the first pass is not "4Kp60 ASIC proven." Success is a repeatable
script that produces stable area/timing deltas for AV2 and VVC from committed
RTL.

## Risks And Open Questions

- SystemVerilog support: Yosys may require preprocessing or small RTL style
  changes before an ASIC flow accepts all current modules.
- Memories: FPGA RAM inference does not automatically become ASIC SRAM macros.
  Large arrays must be audited and either kept small, converted to streaming
  logic, or mapped to explicit SRAM macros.
- AXI interface area: the shared AXI bridge is realistic for SoC integration,
  but it can dominate small-feature subsets. Report core-only and full-top
  numbers separately if needed.
- Entropy timing: entropy coders tend to create serial dependencies. Timing and
  cycles/input pixel must both be watched.
- Open PDK age: 130/180 nm estimates are useful for open reproducibility, not
  modern consumer video-encoder competitiveness.
- Commercial IP opacity: vendors publish feature and interface claims, but not
  enough area/power data for strict public comparisons.

## Source Notes

- [Yosys documentation](https://yosyshq.readthedocs.io/projects/yosys/en/latest/)
  describes Yosys as an open-source RTL synthesis framework with technology
  mapping and cell-library mapping support.
- [OpenROAD documentation](https://openroad.readthedocs.io/en/latest/) describes
  an open-source RTL-to-GDSII tool chain aimed at reducing cost, expertise, and
  schedule barriers for SoC layout generation.
- [OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts)
  provide the integrated script flow around OpenROAD.
- [OpenLane 2](https://openlane2.readthedocs.io/en/latest/) provides another
  scripted open ASIC flow around the same ecosystem.
- [OpenSTA documentation](https://openroad.readthedocs.io/en/latest/main/src/sta/README.html)
  describes a gate-level static timing verifier using Verilog netlists, Liberty
  libraries, SDC constraints, and optional parasitic/activity files.
- [SkyWater SKY130 PDK](https://github.com/google/skywater-pdk) is the public
  open 130 nm PDK baseline.
- [GF180MCU PDK](https://github.com/google/gf180mcu-pdk) is the public open
  GlobalFoundries 180 nm MCU PDK baseline.
- [IHP Open PDK](https://github.com/IHP-GmbH/IHP-Open-PDK) targets the SG13G2
  130 nm BiCMOS process.
- [AV2 specification page](https://av2.aomedia.org/) lists AV2 v1.0.0,
  dated 28 May 2026, and identifies AVM as the corresponding reference
  software.
- [Allegro DVT E300 encoder page](https://www.allegrodvt.com/products/e300-series-video-encoder/)
  documents a commercial multi-format encoder IP with APB control, AXI data
  access, RTL delivery, and bit-accurate software model.
- [Allegro DVT D300 decoder page](https://www.allegrodvt.com/products/d300-series-video-decoder/)
  documents a similar APB/AXI integration model for decoder IP.
- [Allegro DVT AV2 decoder announcement](https://www.allegrodvt.com/news/pulsar-decoder-ip-support-av2-video-codec/)
  gives a public AV2 commercial-IP integration reference, but without area.
- [VVC FME hardware paper](https://arxiv.org/abs/2302.06167) gives a
  GF 28 nm block-level ASIC reference point.
- [VVC transform hardware paper](https://arxiv.org/abs/2002.07461) and
  [VVC inverse-transform hardware paper](https://arxiv.org/abs/2107.11659)
  give block-level transform timing/throughput references.
