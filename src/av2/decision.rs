use super::palette::Av2LumaIntraMode;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Av2LeafPredictionMode {
    IntrabcCopy {
        drl_idx: u8,
    },
    Intra {
        luma_mode: Av2LumaIntraMode,
        use_luma_palette: bool,
        use_bdpcm_uv: bool,
        chroma_bdpcm_horz: bool,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Av2LeafResidualMode {
    None,
    BlackDc,
    LumaPalette { chroma_bdpcm_horz: bool },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Av2LeafPredictionDecision {
    pub(crate) intrabc_flag: bool,
    pub(crate) prediction: Av2LeafPredictionMode,
    pub(crate) residual: Av2LeafResidualMode,
}

pub(crate) fn decide_leaf_prediction(
    allow_intrabc: bool,
    ibc_drl_idx: Option<u8>,
    luma_palette_enabled: bool,
    luma_mode: Av2LumaIntraMode,
    chroma_bdpcm_horz: bool,
) -> Av2LeafPredictionDecision {
    // AV2 v1.0.0 Sections 5.20.5.1 and 5.20.8: IntraBC returns from
    // intra-frame mode parsing before palette/intra residual syntax. Keep that
    // priority explicit here so later rate decisions do not accidentally layer
    // residual syntax onto copied blocks.
    if allow_intrabc {
        if let Some(drl_idx) = ibc_drl_idx {
            return Av2LeafPredictionDecision {
                intrabc_flag: true,
                prediction: Av2LeafPredictionMode::IntrabcCopy { drl_idx },
                residual: Av2LeafResidualMode::None,
            };
        }
    }

    let use_luma_palette = luma_palette_enabled && luma_mode == Av2LumaIntraMode::Dc;
    let residual = if luma_palette_enabled {
        Av2LeafResidualMode::LumaPalette { chroma_bdpcm_horz }
    } else {
        Av2LeafResidualMode::BlackDc
    };

    Av2LeafPredictionDecision {
        intrabc_flag: false,
        prediction: Av2LeafPredictionMode::Intra {
            luma_mode,
            use_luma_palette,
            use_bdpcm_uv: luma_palette_enabled,
            chroma_bdpcm_horz,
        },
        residual,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intrabc_copy_suppresses_intra_residual() {
        let decision = decide_leaf_prediction(true, Some(1), true, Av2LumaIntraMode::Dc, true);

        assert_eq!(
            decision.prediction,
            Av2LeafPredictionMode::IntrabcCopy { drl_idx: 1 }
        );
        assert_eq!(decision.residual, Av2LeafResidualMode::None);
        assert!(decision.intrabc_flag);
    }

    #[test]
    fn dc_palette_intra_enables_palette_residual() {
        let decision = decide_leaf_prediction(true, None, true, Av2LumaIntraMode::Dc, false);

        assert_eq!(
            decision.prediction,
            Av2LeafPredictionMode::Intra {
                luma_mode: Av2LumaIntraMode::Dc,
                use_luma_palette: true,
                use_bdpcm_uv: true,
                chroma_bdpcm_horz: false,
            }
        );
        assert_eq!(
            decision.residual,
            Av2LeafResidualMode::LumaPalette {
                chroma_bdpcm_horz: false
            }
        );
        assert!(!decision.intrabc_flag);
    }

    #[test]
    fn non_palette_path_keeps_black_dc_residual() {
        let decision =
            decide_leaf_prediction(false, Some(0), false, Av2LumaIntraMode::Horizontal, true);

        assert_eq!(
            decision.prediction,
            Av2LeafPredictionMode::Intra {
                luma_mode: Av2LumaIntraMode::Horizontal,
                use_luma_palette: false,
                use_bdpcm_uv: false,
                chroma_bdpcm_horz: true,
            }
        );
        assert_eq!(decision.residual, Av2LeafResidualMode::BlackDc);
        assert!(!decision.intrabc_flag);
    }
}
