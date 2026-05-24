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

The current single-CTU subset usually has no available left/above neighbours,
so `availableL = availableA = false`.
