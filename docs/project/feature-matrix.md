# Current Codec Feature Matrix

This page summarizes the current implemented feature surface. It is a quick
orientation aid; detailed measured baselines remain in the codec-specific
quality, utilization, and synthesis reports.

Current as of 2026-06-30.

## Summary

| Area | VVC/H.266 | AV2 |
|---|---|---|
| Rust software model | Implemented for current subset | Implemented for current subset |
| RTL encoder top | Shared AXI control/read/write interface | Shared AXI control/read/write interface |
| External decoder validation | VTM decode path | AVM/reference-decoder decode path |
| Bitstream parity | SW/RTL byte-exact for implemented paths | SW/RTL byte-exact for implemented paths |
| Reconstruction parity | SW/RTL/REF checksum parity | SW/RTL/REF checksum parity |
| Primary screen-content target | 4:4:4 lossless | 4:4:4 lossless |
| Natural-video guard target | 4:2:0 lossy RaceHorses crops | 4:2:0 lossy RaceHorses crops |
| Multi-frame validation | `multiframe-smoke` | `multiframe-smoke` |
| Synthesis report | `docs/vvc/synthesis.md` | `docs/av2/synthesis.md` |
| Output-utilization report | `docs/vvc/output-utilization.md` | `docs/av2/output-utilization.md` |
| Quality/bitrate report | `docs/vvc/quality-bitrate.md` | `docs/av2/quality-bitrate.md` |

## Coding Tools

| Tool or Path | VVC/H.266 | AV2 | Notes |
|---|---|---|---|
| 4:4:4 lossless screen content | Yes | Yes | Lossless means byte-identical reconstruction. |
| 4:2:0 lossy residual | Yes | Yes | Quality tracked by PSNR and bitrate. |
| Palette | Yes | Luma-only | AV2 palette is luma-only in the current reference-compatible syntax. |
| Palette escape/raw samples | Yes | No private chroma escape syntax | AV2 arbitrary color recovery uses residual/BDPCM paths. |
| Lossless residual | Yes | Yes | Used as fallback/correction path. |
| Chroma BDPCM | Not the primary current path | Horizontal and vertical | AV2 uses BDPCM for lossless 4:4:4 chroma. |
| Transform-skip style residual | Yes | Limited/current subset | Keep block-local and reconstruct exactly for lossless modes. |
| Intra prediction | Limited | Restricted luma modes | AV2 has DC/vertical/horizontal-style restricted support. |
| IBC/IntraBC | CTU-local exact-hash subset | Local hash left-copy subset | Wider candidate/BVP support is future work. |
| Multi-CTU or multi-superblock | Yes | Yes | Partial and multi-block crops are in recurring reports. |
| Entropy coding | CABAC subset | AV2 range-coder subset | No opaque bitstream blobs are acceptable. |

## Input And Block Model

Both codec tops use the same board-facing AXI shape:

- AXI4-Lite control/status registers.
- AXI4 memory-mapped source-frame read.
- AXI4 memory-mapped bitstream write.

Internally, the current design keeps small block-oriented codec cores:

- VVC uses fixed 64x64 CTU boundaries with one CTU-local slice for the current
  subset.
- VVC 4:2:0 uses 8x8 luma transform blocks and colocated 4x4 chroma transform
  blocks.
- AV2 keeps visible coding leaves fixed at 8x8 for now.
- AV2 4:4:4 internally processes visible 8x8 Y/U/V blocks after the shared AXI
  reader/unpacker.

The AXI interface is the public hardware contract. Internal block packet order
may be probed by testbenches, but it is not a board integration interface.

## Validation Sets To Keep Aligned

The recurring cross-codec guard sets are:

- `screenshot-sweep-444`
- `screenshot-multictu-444`
- `racehorses-sweep-420`
- `racehorses-multictu-420`
- `multiframe-smoke`

When a shared interface or validation script changes, run the affected sets for
both codecs unless the change is demonstrably codec-local.

## Known Deliberate Limitations

- The default hardware target is still a small Zynq-7000 metadata target for
  measurement, not a final fit target for all implemented features.
- Yosys timing/path metrics are useful trend indicators, not final timing
  closure.
- Vivado timing is the current vendor timing reference, but it is not run for
  every minor documentation or software-only change.
- AV2 IBC is intentionally local and hash-based. Full AVM block-vector
  predictor stack support is still future work.
- Larger bit depths are intentionally kept as future work; 8-bit is the
  validated baseline.
