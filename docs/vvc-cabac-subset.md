# VVC CABAC Subset Notes

These notes cache the H.266/VVC CABAC table entries currently used by
FrameForge's minimal all-intra generated path. Values were checked against the
local ITU-T H.266 V4 PDF (`T-REC-H.266-202601-I!!PDF-E.pdf`) using both
`pdftotext -layout` and rendered page images from `pdftoppm`.

This is not a complete CABAC transcription. Add rows here only when they are
used by the software and RTL implementations.

## Source Pages

| Spec item | PDF page | Printed page |
| --- | ---: | ---: |
| Tables 59-60 | 420 | 406 |
| Tables 72, 75, 76, 79, 81 | 422-424 | 408-410 |
| Tables 112-114 | 431-432 | 417-418 |
| Tables 118-126 | 432-436 | 418-422 |
| Table 127 subset | 439 | 425 |
| Table 132 subset | 450 | 436 |
| Table 133 subset | 454 | 440 |

Rendered check images were generated under `/tmp/frameforge_h266_pages/`.

## Context Initialization Tables

Each row gives `initValue` and `shiftIdx` indexed by `ctxIdx` for the table.
The current encoder uses the I-slice initializationType range from Table 51.

### Table 59: `split_cu_flag`

For I slices, Table 51 maps `split_cu_flag` to ctxIdx `0..8`.

| ctxIdx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 19 | 28 | 38 | 27 | 29 | 38 | 20 | 30 | 31 |
| shiftIdx | 12 | 13 | 8 | 8 | 13 | 12 | 5 | 9 | 9 |

### Table 60: `split_qt_flag`

For I slices, Table 51 maps `split_qt_flag` to ctxIdx `0..5`.

| ctxIdx | 0 | 1 | 2 | 3 | 4 | 5 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 27 | 6 | 15 | 25 | 19 | 37 |
| shiftIdx | 0 | 8 | 8 | 12 | 12 | 8 |

### Table 75: `intra_luma_mpm_flag`

For I slices, Table 51 maps `intra_luma_mpm_flag` to ctxIdx `0`.

| ctxIdx | 0 | 1 | 2 |
| --- | ---: | ---: | ---: |
| initValue | 45 | 36 | 44 |
| shiftIdx | 6 | 6 | 6 |

### Table 72: `intra_luma_ref_idx`

For I slices, Table 51 maps `intra_luma_ref_idx` to ctxIdx `0..1`.

| ctxIdx | 0 | 1 |
| --- | ---: | ---: |
| initValue | 25 | 60 |
| shiftIdx | 5 | 8 |

### Table 76: `intra_luma_not_planar_flag`

For I slices, Table 51 maps `intra_luma_not_planar_flag` to ctxIdx `0..1`.

| ctxIdx | 0 | 1 |
| --- | ---: | ---: |
| initValue | 13 | 28 |
| shiftIdx | 1 | 5 |

### Table 79: `cclm_mode_flag`

For I slices, Table 51 maps `cclm_mode_flag` to ctxIdx `0`.

| ctxIdx | 0 | 1 | 2 |
| --- | ---: | ---: | ---: |
| initValue | 59 | 34 | 26 |
| shiftIdx | 4 | 4 | 4 |

### Table 81: `intra_chroma_pred_mode`

For I slices, Table 51 maps `intra_chroma_pred_mode` to ctxIdx `0`.

| ctxIdx | 0 | 1 | 2 |
| --- | ---: | ---: | ---: |
| initValue | 34 | 25 | 25 |
| shiftIdx | 5 | 5 | 5 |

### Tables 112-114: transform-unit coded flags

For I slices, Table 51 maps:

| Syntax element | I-slice ctxIdx range |
| --- | --- |
| `tu_y_coded_flag` | `0..3` |
| `tu_cb_coded_flag` | `0..1` |
| `tu_cr_coded_flag` | `0..2` |

`tu_y_coded_flag`:

| ctxIdx | 0 | 1 | 2 | 3 |
| --- | ---: | ---: | ---: | ---: |
| initValue | 15 | 12 | 5 | 7 |
| shiftIdx | 5 | 1 | 8 | 9 |

`tu_cb_coded_flag`:

| ctxIdx | 0 | 1 |
| --- | ---: | ---: |
| initValue | 12 | 21 |
| shiftIdx | 5 | 0 |

`tu_cr_coded_flag`:

| ctxIdx | 0 | 1 | 2 |
| --- | ---: | ---: | ---: |
| initValue | 33 | 28 | 36 |
| shiftIdx | 2 | 1 | 0 |

## Binarization Subset

From Table 127:

| Syntax element | Binarization | Inputs |
| --- | --- | --- |
| `split_cu_flag` | FL | `cMax = 1` |
| `split_qt_flag` | FL | `cMax = 1` |
| `intra_luma_mpm_flag` | FL | `cMax = 1` |
| `intra_luma_not_planar_flag` | FL | `cMax = 1` |
| `cclm_mode_flag` | FL | `cMax = 1` |
| `intra_chroma_pred_mode` | clause 9.3.3.8 | none |
| `tu_y_coded_flag` | FL | `cMax = 1` |
| `tu_cb_coded_flag` | FL | `cMax = 1` |
| `tu_cr_coded_flag` | FL | `cMax = 1` |

From Table 132:

| Syntax element | binIdx 0 | binIdx 1 | binIdx 2 | Later bins |
| --- | --- | --- | --- | --- |
| `split_cu_flag` | `0..8`, clause 9.3.4.2.2 | `na` | `na` | `na` |
| `split_qt_flag` | `0..5`, clause 9.3.4.2.2 | `na` | `na` | `na` |
| `intra_luma_mpm_flag` | `0` | `na` | `na` | `na` |
| `intra_luma_not_planar_flag` | `!intra_subpartitions_mode_flag` | `na` | `na` | `na` |
| `cclm_mode_flag` | `0` | `na` | `na` | `na` |
| `intra_chroma_pred_mode` | `0` | `bypass` | `bypass` | `na` |
| `tu_y_coded_flag` | `0..3`, clause 9.3.4.2.5 | `na` | `na` | `na` |
| `tu_cb_coded_flag` | `intra_bdpcm_chroma_flag ? 1 : 0` | `na` | `na` | `na` |
| `tu_cr_coded_flag` | `intra_bdpcm_chroma_flag ? 2 : tu_cb_coded_flag` | `na` | `na` | `na` |

For the current subset, `intra_bdpcm_chroma_flag` is not enabled, so
`tu_cb_coded_flag` uses ctxInc `0`, and `tu_cr_coded_flag` uses ctxInc equal to
the previously coded Cb coded flag for the colocated chroma TU.

## Residual Coding Audit Notes

These rows record residual CABAC context and binarization details that are used
by the current audited subset or must be implemented before enabling broader
transform syntax. They are cached here because the PDF-to-text output for the
large residual tables is easy to misread.

### Table 98: `mts_idx`

For I slices, Table 51 maps `mts_idx` to ctxIdx `0..3`.

| ctxIdx | 0 | 1 | 2 | 3 |
| --- | ---: | ---: | ---: | ---: |
| initValue | 29 | 0 | 28 | 0 |
| shiftIdx | 8 | 0 | 9 | 0 |

Table 132 maps `mts_idx` binIdx `0..3` to ctxInc `0..3`.

### Table 118: `transform_skip_flag`

For I slices, Table 51 maps `transform_skip_flag` to ctxIdx `0..1`.

| ctxIdx | 0 | 1 |
| --- | ---: | ---: |
| initValue | 25 | 9 |
| shiftIdx | 1 | 1 |

Table 132 maps binIdx `0` to ctxInc `0` for luma and `1` for chroma.

### Tables 120-121: last significant coefficient prefixes

For I slices, Table 51 maps both `last_sig_coeff_x_prefix` and
`last_sig_coeff_y_prefix` to ctxIdx `0..22`.

`last_sig_coeff_x_prefix`:

| ctxIdx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 13 | 5 | 4 | 21 | 14 | 4 | 6 | 14 | 21 | 11 | 14 | 7 | 14 | 5 | 11 | 21 | 30 | 22 | 13 | 42 | 12 | 4 | 3 |
| shiftIdx | 8 | 5 | 4 | 5 | 4 | 4 | 5 | 4 | 1 | 0 | 4 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 5 | 4 | 4 |

`last_sig_coeff_y_prefix`:

| ctxIdx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 13 | 5 | 4 | 6 | 13 | 11 | 14 | 6 | 5 | 3 | 14 | 22 | 6 | 4 | 3 | 6 | 22 | 29 | 20 | 34 | 12 | 4 | 3 |
| shiftIdx | 8 | 5 | 8 | 5 | 5 | 4 | 5 | 5 | 4 | 0 | 5 | 4 | 1 | 0 | 0 | 1 | 4 | 0 | 0 | 0 | 6 | 5 | 5 |

Clause 9.3.4.2.4 derives ctxInc from `binIdx`, component, and transform block
size:

```text
if cIdx == 0:
  ctxOffset = offsetY[log2TbSize - 1]
  ctxShift = (log2TbSize + 1) >> 2
  offsetY = {0, 0, 3, 6, 10, 15}
else:
  ctxOffset = 20
  ctxShift = Clip3(0, 2, (2 * log2TbSize) >> 3)

ctxInc = (binIdx >> ctxShift) + ctxOffset
```

The encoder must pass the actual transform-block size into this derivation.
The current residual path emits luma coefficient syntax from generated
coefficient arrays. AC coding is limited to the first 4x4 coefficient group
until scan-position suffix and `sb_coded_flag` coverage is expanded for larger
coefficient groups.

### Tables 122-126: coefficient flags

For I slices, Table 51 maps:

| Syntax element | I-slice ctxIdx range |
| --- | --- |
| `sb_coded_flag` | `0..6` |
| `sig_coeff_flag` | `0..62` |
| `par_level_flag` | `0..32` |
| `abs_level_gtx_flag` | `0..71` |
| `coeff_sign_flag` | `0..5` |

`sb_coded_flag`:

| ctxIdx | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 18 | 31 | 25 | 15 | 18 | 20 | 38 |
| shiftIdx | 8 | 5 | 5 | 8 | 5 | 8 | 8 |

`sig_coeff_flag`, I-slice subset:

| ctxIdx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 25 | 19 | 28 | 14 | 25 | 20 | 29 | 30 | 19 | 37 | 30 | 38 | 11 | 38 | 46 | 54 |
| shiftIdx | 12 | 9 | 9 | 10 | 9 | 9 | 9 | 10 | 8 | 8 | 8 | 10 | 9 | 13 | 8 | 8 |

| ctxIdx | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 27 | 39 | 39 | 39 | 44 | 39 | 39 | 39 | 18 | 39 | 39 | 39 | 27 | 39 | 39 | 39 |
| shiftIdx | 8 | 8 | 8 | 5 | 8 | 0 | 0 | 0 | 8 | 8 | 8 | 8 | 8 | 0 | 4 | 4 |

| ctxIdx | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39 | 40 | 41 | 42 | 43 | 44 | 45 | 46 | 47 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 0 | 39 | 39 | 39 | 25 | 27 | 28 | 37 | 34 | 53 | 53 | 46 | 19 | 46 | 38 | 39 |
| shiftIdx | 0 | 0 | 0 | 0 | 12 | 12 | 9 | 13 | 4 | 5 | 8 | 9 | 8 | 12 | 12 | 8 |

| ctxIdx | 48 | 49 | 50 | 51 | 52 | 53 | 54 | 55 | 56 | 57 | 58 | 59 | 60 | 61 | 62 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 52 | 39 | 39 | 39 | 11 | 39 | 39 | 39 | 19 | 39 | 39 | 39 | 25 | 28 | 38 |
| shiftIdx | 4 | 0 | 0 | 0 | 8 | 8 | 8 | 8 | 4 | 0 | 0 | 0 | 13 | 13 | 8 |

`abs_level_gtx_flag`, first I-slice coefficient-set subset currently needed by
the trace replacement work. The software/RTL tables cache ctxIdx `0..71`; only
`0..31` are expanded below until the remaining rows are needed in docs:

| ctxIdx | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 25 | 25 | 11 | 27 | 20 | 21 | 33 | 12 | 28 | 21 | 22 | 34 | 28 | 29 | 29 | 30 |
| shiftIdx | 9 | 5 | 10 | 13 | 13 | 10 | 9 | 10 | 13 | 13 | 13 | 9 | 10 | 10 | 10 | 13 |

| ctxIdx | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 36 | 29 | 45 | 30 | 23 | 40 | 33 | 27 | 28 | 21 | 37 | 36 | 37 | 45 | 38 | 46 |
| shiftIdx | 8 | 9 | 10 | 10 | 13 | 8 | 8 | 9 | 12 | 12 | 10 | 5 | 9 | 9 | 9 | 13 |

`coeff_sign_flag`:

| ctxIdx | 0 | 1 | 2 | 3 | 4 | 5 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| initValue | 12 | 17 | 46 | 28 | 25 | 46 |
| shiftIdx | 1 | 4 | 4 | 5 | 8 | 8 |

## Left/Above Context Derivation

From Table 133 and clause 9.3.4.2.2:

`split_qt_flag`:

| Field | Rule |
| --- | --- |
| `condL` | `CqtDepth[chType][xNbL][yNbL] > cqtDepth` |
| `condA` | `CqtDepth[chType][xNbA][yNbA] > cqtDepth` |
| `ctxSetIdx` | `cqtDepth >= 2` |

`split_cu_flag`:

| Field | Rule |
| --- | --- |
| `condL` | `CbHeight[chType][xNbL][yNbL] < cbHeight` |
| `condA` | `CbWidth[chType][xNbA][yNbA] < cbWidth` |
| `ctxSetIdx` | `(allowSplitBtVer + allowSplitBtHor + allowSplitTtVer + allowSplitTtHor + 2 * allowSplitQt - 1) / 2` |

For both rows above, the context increment is:

```text
ctxInc = (condL && availableL) + (condA && availableA) + ctxSetIdx * 3
```

The current CTU-local slice subset usually has no available left/above
neighbours across slice boundaries, so `availableL = availableA = false`. Keep
these as separately named inputs in code rather than folding them into `condL` /
`condA`; future multi-CTU slices will need to compute neighbour availability
independently from the condition values.

## SW Context Audit Status

The Rust reference model now keeps the currently used CABAC context families in
one auditable path before they are mirrored into RTL. The table below is scoped
to syntax that FrameForge emits or is preparing to emit; unsupported syntax must
add a row here before being enabled in a stream.

| Path | Syntax element | Context range used | Spec reference | SW status |
| --- | --- | --- | --- | --- |
| 4:2:0 residual | `last_sig_coeff_x_prefix` | `0..22`, currently DC and first-subblock AC prefixes | Table 132, clause 9.3.4.2.4 | init table and ctx derivation implemented |
| 4:2:0 residual | `last_sig_coeff_y_prefix` | `0..22`, currently DC and first-subblock AC prefixes | Table 132, clause 9.3.4.2.4 | init table and ctx derivation implemented |
| 4:2:0 residual | `sb_coded_flag` | `0..6` | Table 132, clause 9.3.4.2.6 | init table and ctx derivation implemented; full multi-subblock emission still TODO |
| 4:2:0 residual | `sig_coeff_flag` | `0..62` | Table 132, clauses 9.3.4.2.7-9.3.4.2.8 | init table and ctx derivation implemented |
| 4:2:0 residual | `par_level_flag` | `0..32` | Table 132, clause 9.3.4.2.9 | init table and ctx derivation implemented |
| 4:2:0 residual | `abs_level_gtx_flag` | `0..71` | Table 132, clause 9.3.4.2.9 | init table and ctx derivation implemented |
| 4:2:0 residual | `coeff_sign_flag` | bypass for regular transform, `0..5` only for transform-skip signs | Table 132, clause 9.3.4.2.10 | regular path bypass implemented; transform-skip path labelled and gated |
| 4:4:4 palette | `pred_mode_plt_flag` | `0` for I-slice initType 0 | Tables 51, 67, 132 | init table corrected and gated by `sps_palette_enabled_flag` |
| 4:4:4 palette | `palette_transpose_flag` | `0` for I-slice initType 0 | Tables 51, 100, 132 | init table corrected |
| 4:4:4 palette | `copy_above_palette_indices_flag` | `0` for I-slice initType 0 | Tables 51, 99, 132 | init table corrected; current encoder emits index runs only |
| 4:4:4 palette | `run_copy_flag` | `0..7` for I-slice initType 0 | Tables 51, 101, 132, 134 | init table and ctxInc derivation implemented for index and copy-above previous run types |

Tool enablement is centralized in `VvcSyntaxToolFlags`. SPS fields and CABAC
syntax decisions read the same `VvcSliceSyntaxConfig`, so palette, transform
skip, MTS, LFNST, dependent quantization, sign-data hiding, MRL, and CCLM can be
audited from a single configuration object. Residual AC coding is not a separate
tool gate: the residual path always accepts a coefficient vector, and the current
forward transform may simply leave AC coefficients at zero until non-DC
quantization is implemented.

The RTL CABAC stream ABI reserves 10 bits for context IDs in
`SYMBOL_BIN_CTX` records (`s_axis_data[17:8]`). The currently instantiated RTL
context bank only contains the audited subset used by residual DC/early AC and
palette mode, but the packet format will not need to change when more VVC
context sets are added.

## Palette And Transform Syntax Surface

This checklist records the syntax elements that must be supported before
FrameForge can claim the palette and transform paths are complete for the current
all-intra subset. Rows marked implemented are present in the Rust reference
model; rows marked restricted are legal only for the stated current subset.

| Path | Syntax element | Gate / condition | Coding in current SW model | Status |
| --- | --- | --- | --- | --- |
| Transform | `transform_skip_flag` | `sps_transform_skip_enabled_flag` and TU-level TS allowed | Context-coded with luma/chroma ctxInc split | Implemented, disabled by default profile flags |
| Transform | `mts_idx` | `sps_explicit_mts_intra_enabled_flag`, MTS allowed, no TS | Context-coded zero index | Implemented for `mts_idx = 0` only |
| Transform | `lfnst_idx` | `sps_lfnst_enabled_flag` and LFNST constraints | Not emitted while flag is false | TODO before enabling non-zero LFNST |
| Transform | `tu_y_coded_flag` | Luma transform unit | Context-coded QtCbf[Y] | Implemented |
| Transform | `tu_cb_coded_flag` | Chroma transform unit | Context-coded QtCbf[Cb] | Implemented for current 4:2:0 path |
| Transform | `tu_cr_coded_flag` | Chroma transform unit | Context-coded QtCbf[Cr] using Cb-dependent ctxInc | Implemented for current 4:2:0 path |
| Residual | `last_sig_coeff_x_prefix` / `last_sig_coeff_y_prefix` | Non-empty residual TU | Context-coded prefixes from TB size and component | Implemented for luma, current AC limited to first 4x4 subblock |
| Residual | `last_sig_coeff_x_suffix` / `last_sig_coeff_y_suffix` | Prefix group greater than 3 | Bypass-coded suffix | TODO before coefficients outside early groups are enabled |
| Residual | `sb_coded_flag` | Non-first/non-last significant subblock | Context-coded from right/lower or left/above TS neighbours | Context model implemented; multi-subblock emission TODO |
| Residual | `sig_coeff_flag` | Non-inferred coefficient significance | Context-coded from local template stats | Implemented for current coefficient-vector path |
| Residual | `abs_level_gtx_flag` | Significant coefficient regular pass | Context-coded greater-than flags | Implemented for levels that fit current regular-pass subset |
| Residual | `par_level_flag` | `absLevel > 1` regular pass | Context-coded parity flag | Implemented |
| Residual | `abs_remainder` | `absLevel > 3` or bypass pass | Bypass Rice code with fixed rice parameter | Restricted: Rice adaptation still TODO |
| Residual | `dec_abs_level` | Bypass fallback after context-bin budget | Not emitted by current subset | TODO before large coefficients/full pass-2 are enabled |
| Residual | `coeff_sign_flag` | Significant coefficient | Bypass for regular transform; context-coded for TS signs | Implemented for regular path, TS labelled |
| Palette | `pred_mode_plt_flag` | Palette CU mode decision | Context-coded mode flag | Implemented for current all-palette 4:4:4 path |
| Palette | `palette_predictor_run` | Non-empty previous palette predictor | Bypass EG0 | Implemented for current no-reuse signalling |
| Palette | `num_signalled_palette_entries` | Predictor has room for new entries | Bypass EG0 | Implemented |
| Palette | `new_palette_entries` | Signalled palette entries | Bypass fixed-length samples at bit depth | Implemented for 8-bit 4:4:4 entries |
| Palette | `palette_escape_val_present_flag` | Palette has at least one entry | Bypass flag | Implemented as false; escape values TODO |
| Palette | `palette_transpose_flag` | More than one index symbol | Context-coded rotation/transpose flag | Implemented as horizontal scan |
| Palette | `run_copy_flag` | Palette index-map run identity | Context-coded with Table 134 ctxInc | Implemented for index runs |
| Palette | `copy_above_palette_indices_flag` | Run type can switch to copy-above | Context-coded flag | Context implemented; copy-above runs TODO |
| Palette | `palette_idx_idc` | New index-run symbol | Bypass truncated binary with index redundancy removal | Implemented for current index runs |
| Palette | `palette_escape_val` | Escape index selected | Bypass EG5 | TODO before escape coding is enabled |
