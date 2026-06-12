use std::io::{Read, Write};

use crate::picture::{Picture, PixelFormat};

mod syntax;

use syntax::{Av2SyntaxPayload, Av2SyntaxWriter};

pub const AV2_CODEC_NAME: &str = "av2";
pub const AV2_BITSTREAM_EXTENSION: &str = "av2";
pub const AV2_FIXED_BLACK_444_WIDTH: usize = 64;
pub const AV2_FIXED_BLACK_444_HEIGHT: usize = 64;

const AV2_PROFILE_BITS: u8 = 5;
const AV2_LEVEL_BITS: u8 = 5;
const AV2_SEQUENCE_PROFILE_CONFIGURABLE: u8 = 4;
const AV2_SEQUENCE_LEVEL_2_0: u8 = 0;
const AV2_CHROMA_FORMAT_444: u32 = 2;
const AV2_BITDEPTH_INDEX_8BIT: u32 = 1;
const AV2_MAX_FRAME_DIMENSION_BITS: u8 = 6;
const AV2_DELTA_DCQUANT_MIN: i8 = -23;
const AV2_MAX_MAX_IBC_DRL_BITS_MINUS_MIN_PLUS_ONE: u16 = 3;

// TODO(av2-entropy): replace this fixed black-tile entropy payload with a
// reusable AV2 entropy/range writer. The surrounding OBU, sequence header, and
// tile-group header are already emitted from named syntax fields below.
const AV2_BLACK_64X64_444_TILE_ENTROPY_PAYLOAD: &[u8] = &[
    0x00, 0x12, 0x2e, 0x6a, 0x24, 0xb3, 0xe1, 0x80, 0xd0, 0x4c, 0x79, 0xff, 0x4e, 0xdb, 0x90, 0x36,
    0xe7, 0xc0,
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Av2ObuType {
    SequenceHeader = 1,
    TemporalDelimiter = 2,
    ClosedLoopKey = 4,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Av2VideoGeometry {
    pub width: usize,
    pub height: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Av2EncodeParams {
    pub frames: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Av2EncodeRequest {
    pub params: Av2EncodeParams,
    pub geometry: Av2VideoGeometry,
    pub format: PixelFormat,
}

impl Av2EncodeRequest {
    pub fn validate(&self) -> Result<(), String> {
        if self.geometry.width == 0 || self.geometry.height == 0 {
            return Err("AV2 encode expects positive dimensions".to_string());
        }
        if self.params.frames == 0 {
            return Err("AV2 encode expects at least one frame".to_string());
        }
        if !self.format.is_yuv() {
            return Err(format!(
                "AV2 encode expects planar YUV input; got {}",
                self.format
            ));
        }
        Ok(())
    }
}

pub fn av2_encode_fixed_black_444(
    input: &mut dyn Read,
    output: &mut dyn Write,
    recon: Option<&mut dyn Write>,
    request: Av2EncodeRequest,
) -> Result<(), String> {
    request.validate()?;
    validate_fixed_black_444_request(request)?;

    let expected_recon = av2_black_64x64_444_reconstruction();
    let mut frame = vec![0; expected_recon.len()];
    input
        .read_exact(&mut frame)
        .map_err(|err| format!("failed to read AV2 fixed black-frame input: {err}"))?;
    if frame != expected_recon {
        return Err("fixed AV2 encoder expects a black 64x64 yuv444p8 input frame".to_string());
    }

    let bitstream = av2_black_64x64_444_bitstream();
    output
        .write_all(&bitstream)
        .map_err(|err| format!("failed to write fixed AV2 bitstream: {err}"))?;
    if let Some(recon) = recon {
        recon
            .write_all(&expected_recon)
            .map_err(|err| format!("failed to write AV2 fixed reconstruction: {err}"))?;
    }
    Ok(())
}

pub fn av2_black_64x64_444_bitstream() -> Vec<u8> {
    let mut out = Vec::new();
    append_obu(
        &mut out,
        Av2ObuType::TemporalDelimiter,
        &Av2SyntaxPayload::empty(),
    );
    append_obu(
        &mut out,
        Av2ObuType::SequenceHeader,
        &av2_black_64x64_444_sequence_header_payload(),
    );
    append_obu(
        &mut out,
        Av2ObuType::ClosedLoopKey,
        &av2_black_64x64_444_closed_loop_key_payload(),
    );
    out
}

pub fn av2_black_64x64_444_reconstruction() -> Vec<u8> {
    vec![
        0;
        Picture::expected_len(
            AV2_FIXED_BLACK_444_WIDTH,
            AV2_FIXED_BLACK_444_HEIGHT,
            PixelFormat::Yuv444p8,
        )
    ]
}

fn validate_fixed_black_444_request(request: Av2EncodeRequest) -> Result<(), String> {
    if request.geometry.width != AV2_FIXED_BLACK_444_WIDTH
        || request.geometry.height != AV2_FIXED_BLACK_444_HEIGHT
        || request.params.frames != 1
        || request.format != PixelFormat::Yuv444p8
    {
        return Err("fixed AV2 encoder only supports one 64x64 yuv444p8 black frame".to_string());
    }
    Ok(())
}

fn av2_black_64x64_444_sequence_header_payload() -> Av2SyntaxPayload {
    let mut writer = Av2SyntaxWriter::new();

    // AV2 v1.0.0 sequence_header_obu(), mirrored from AVM
    // av2_write_sequence_header_obu().
    writer.write_uvlc("sequence_header.seq_header_id", 0);
    writer.write_literal(
        "sequence_header.seq_profile_idc",
        AV2_SEQUENCE_PROFILE_CONFIGURABLE as u64,
        AV2_PROFILE_BITS,
    );
    writer.write_flag("sequence_header.single_picture_header_flag", true);
    writer.write_literal(
        "sequence_header.seq_max_level_idx",
        AV2_SEQUENCE_LEVEL_2_0 as u64,
        AV2_LEVEL_BITS,
    );
    writer.write_uvlc(
        "sequence_header.seq_chroma_format_idc",
        AV2_CHROMA_FORMAT_444,
    );
    writer.write_uvlc("sequence_header.bitdepth_lut_idx", AV2_BITDEPTH_INDEX_8BIT);
    writer.write_literal(
        "sequence_header.num_bits_width_minus_1",
        (AV2_MAX_FRAME_DIMENSION_BITS - 1) as u64,
        4,
    );
    writer.write_literal(
        "sequence_header.num_bits_height_minus_1",
        (AV2_MAX_FRAME_DIMENSION_BITS - 1) as u64,
        4,
    );
    writer.write_literal(
        "sequence_header.max_frame_width_minus_1",
        (AV2_FIXED_BLACK_444_WIDTH - 1) as u64,
        AV2_MAX_FRAME_DIMENSION_BITS,
    );
    writer.write_literal(
        "sequence_header.max_frame_height_minus_1",
        (AV2_FIXED_BLACK_444_HEIGHT - 1) as u64,
        AV2_MAX_FRAME_DIMENSION_BITS,
    );
    writer.write_flag("sequence_header.conf_win_enabled_flag", false);

    write_fixed_black_444_sequence_tools(&mut writer);

    writer.write_flag("sequence_header.film_grain_params_present", false);
    writer.write_flag("sequence_header.seq_extension_present_flag", false);
    writer.trailing_bits();
    writer.finish()
}

fn write_fixed_black_444_sequence_tools(writer: &mut Av2SyntaxWriter) {
    // AV2 v1.0.0 sequence_header() tool groups, mirrored from AVM
    // write_sequence_header(). Values are the fixed AVM choices for one
    // lossless 64x64 yuv444p8 still picture.
    writer.write_flag("sequence_partition.sb_size_is_256", false);
    writer.write_flag("sequence_partition.sb_size_is_128", false);
    writer.write_flag("sequence_partition.enable_sdp", true);
    writer.write_flag("sequence_partition.enable_ext_partitions", true);
    writer.write_flag("sequence_partition.enable_uneven_4way_partitions", true);
    writer.write_flag("sequence_partition.max_pb_aspect_ratio_lt2", false);

    writer.write_flag("sequence_segment.enable_ext_seg", false);
    writer.write_flag("sequence_segment.seq_seg_info_present_flag", false);

    writer.write_flag("sequence_intra.enable_intra_dip", false);
    writer.write_flag("sequence_intra.enable_intra_edge_filter", true);
    writer.write_flag("sequence_intra.enable_mrls", true);
    writer.write_flag("sequence_intra.enable_cfl_intra", true);
    writer.write_literal("sequence_intra.cfl_ds_filter_index", 0, 2);
    writer.write_flag("sequence_intra.enable_mhccp", true);
    writer.write_flag("sequence_intra.enable_ibp", true);

    writer.write_flag("sequence_inter.enable_refmvbank", true);
    writer.write_flag("sequence_inter.is_drl_reorder_disable", false);
    writer.write_flag("sequence_inter.enable_drl_reorder_constraint", false);
    writer.write_quniform(
        "sequence_inter.def_max_bvp_drl_bits_minus_min",
        AV2_MAX_MAX_IBC_DRL_BITS_MINUS_MIN_PLUS_ONE,
        2,
    );
    writer.write_flag("sequence_inter.allow_frame_max_bvp_drl_bits", false);
    writer.write_flag("sequence_inter.enable_bawp", true);

    writer.write_flag("sequence_transform.enable_fsc", true);
    writer.write_flag("sequence_transform.enable_ist", false);
    writer.write_flag("sequence_transform.enable_inter_ist", false);
    writer.write_flag("sequence_transform.enable_chroma_dctonly", false);
    writer.write_flag("sequence_transform.reduced_tx_part_set", false);
    writer.write_flag("sequence_transform.enable_cctx", true);
    writer.write_flag("sequence_transform.enable_tcq_nonzero", false);
    writer.write_flag("sequence_transform.enable_parity_hiding", false);
    writer.write_flag("sequence_transform.separate_uv_delta_q", false);
    writer.write_flag("sequence_transform.equal_ac_dc_q", true);
    writer.write_literal(
        "sequence_transform.base_uv_ac_delta_q_minus_min",
        (0 - AV2_DELTA_DCQUANT_MIN as i16) as u64,
        5,
    );
    writer.write_flag("sequence_transform.uv_ac_delta_q_enabled", false);

    writer.write_flag("sequence_filter.disable_loopfilters_across_tiles", false);
    writer.write_flag("sequence_filter.enable_cdef", false);
    writer.write_flag("sequence_filter.enable_gdf", false);
    writer.write_flag("sequence_filter.enable_restoration", false);
    writer.write_flag("sequence_filter.enable_ccso", false);
    writer.write_literal("sequence_filter.df_par_bits_minus2", 1, 2);

    writer.write_flag("sequence_tile_config.seq_tile_info_present_flag", false);
}

fn av2_black_64x64_444_closed_loop_key_payload() -> Av2SyntaxPayload {
    let mut writer = Av2SyntaxWriter::new();

    // AV2 v1.0.0 tile_group_obu() for a single-tile OBU_CLOSED_LOOP_KEY.
    // The uncompressed header follows AVM write_tilegroup_header() and
    // write_uncompressed_header(); the still-opaque bytes appended below are
    // the entropy-coded black tile payload.
    writer.write_flag("tile_group.first_tile_group_in_frame", true);
    writer.write_uvlc("uncompressed_header.cur_mfh_id", 0);
    writer.write_uvlc("uncompressed_header.seq_header_id", 0);
    writer.write_flag("uncompressed_header.allow_screen_content_tools", false);
    writer.write_flag("uncompressed_header.allow_intrabc", false);
    writer.write_flag("uncompressed_header.disable_cdf_update", false);
    writer.write_flag("tile_info.uniform_spacing_flag", true);
    writer.write_literal("quantization.base_qindex", 0, 8);
    writer.write_flag("segmentation.enabled", false);
    writer.write_flag("quantization_matrix.using_qmatrix", false);
    writer.write_literal("uncompressed_header.reduced_tx_set_used", 0, 2);
    writer.byte_align_zero("tile_group.header_byte_alignment");

    let mut payload = writer.finish();
    payload.append_entropy_payload_bytes(
        "tile_group.black_64x64_entropy_payload",
        AV2_BLACK_64X64_444_TILE_ENTROPY_PAYLOAD,
    );
    payload
}

fn append_obu(out: &mut Vec<u8>, obu_type: Av2ObuType, payload: &Av2SyntaxPayload) {
    let header = av2_obu_header(obu_type);
    write_leb128((header.len() + payload.bytes.len()) as u32, out);
    out.extend_from_slice(&header);
    out.extend_from_slice(&payload.bytes);
}

fn av2_obu_header(obu_type: Av2ObuType) -> Vec<u8> {
    let mut writer = Av2SyntaxWriter::new();
    writer.write_flag("obu_header.obu_header_extension_flag", false);
    writer.write_literal("obu_header.obu_type", obu_type as u64, 5);
    writer.write_literal("obu_header.obu_tlayer_id", 0, 2);
    writer.finish().bytes
}

fn write_leb128(mut value: u32, out: &mut Vec<u8>) {
    loop {
        let mut byte = (value & 0x7f) as u8;
        value >>= 7;
        if value != 0 {
            byte |= 0x80;
        }
        out.push(byte);
        if value == 0 {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::syntax::Av2SyntaxCode;
    use super::*;

    #[test]
    fn av2_accepts_basic_yuv_request_shape() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: 64,
                height: 64,
            },
            format: PixelFormat::Yuv420p8,
        };

        assert!(request.validate().is_ok());
    }

    #[test]
    fn av2_fixed_black_444_emits_bitstream_and_recon() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: AV2_FIXED_BLACK_444_WIDTH,
                height: AV2_FIXED_BLACK_444_HEIGHT,
            },
            format: PixelFormat::Yuv444p8,
        };
        let input = av2_black_64x64_444_reconstruction();
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request)
            .expect("fixed AV2 black-frame encode should succeed");

        assert_eq!(output, av2_black_64x64_444_bitstream());
        assert_ne!(output, input);
        assert_eq!(recon, input);
    }

    #[test]
    fn av2_fixed_black_444_matches_decoder_backed_obu_bytes() {
        assert_eq!(
            av2_black_64x64_444_bitstream(),
            vec![
                0x01, 0x08, 0x0d, 0x04, 0x92, 0x06, 0x95, 0x7f, 0xfc, 0x70, 0xe7, 0x36, 0x11, 0xb8,
                0x08, 0x80, 0x16, 0x10, 0xe2, 0x00, 0x00, 0x00, 0x12, 0x2e, 0x6a, 0x24, 0xb3, 0xe1,
                0x80, 0xd0, 0x4c, 0x79, 0xff, 0x4e, 0xdb, 0x90, 0x36, 0xe7, 0xc0,
            ]
        );
    }

    #[test]
    fn av2_fixed_black_444_sequence_header_has_labeled_fields() {
        let payload = av2_black_64x64_444_sequence_header_payload();

        assert_eq!(
            payload.bytes,
            vec![0x92, 0x06, 0x95, 0x7f, 0xfc, 0x70, 0xe7, 0x36, 0x11, 0xb8, 0x08, 0x80]
        );
        assert_has_field(
            &payload,
            "sequence_header.seq_profile_idc",
            Av2SyntaxCode::Literal,
            1,
            5,
        );
        assert_has_field(
            &payload,
            "sequence_header.max_frame_width_minus_1",
            Av2SyntaxCode::Literal,
            26,
            6,
        );
        assert_has_field(
            &payload,
            "sequence_transform.base_uv_ac_delta_q_minus_min",
            Av2SyntaxCode::Literal,
            72,
            5,
        );
        assert_has_field(
            &payload,
            "trailing_bits",
            Av2SyntaxCode::TrailingBits,
            88,
            8,
        );
    }

    #[test]
    fn av2_fixed_black_444_closed_loop_key_labels_header_and_entropy_payload() {
        let payload = av2_black_64x64_444_closed_loop_key_payload();

        assert_eq!(&payload.bytes[..3], &[0xe2, 0x00, 0x00]);
        assert_eq!(
            &payload.bytes[3..],
            AV2_BLACK_64X64_444_TILE_ENTROPY_PAYLOAD
        );
        assert_has_field(
            &payload,
            "tile_group.first_tile_group_in_frame",
            Av2SyntaxCode::Flag,
            0,
            1,
        );
        assert_has_field(
            &payload,
            "quantization.base_qindex",
            Av2SyntaxCode::Literal,
            7,
            8,
        );
        assert_has_field(
            &payload,
            "tile_group.black_64x64_entropy_payload",
            Av2SyntaxCode::EntropyPayloadBytes,
            24,
            AV2_BLACK_64X64_444_TILE_ENTROPY_PAYLOAD.len() * 8,
        );
    }

    #[test]
    fn av2_fixed_black_444_rejects_non_black_input() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: AV2_FIXED_BLACK_444_WIDTH,
                height: AV2_FIXED_BLACK_444_HEIGHT,
            },
            format: PixelFormat::Yuv444p8,
        };
        let mut input = av2_black_64x64_444_reconstruction();
        input[0] = 1;
        let mut source = input.as_slice();
        let mut output = Vec::new();

        let result = av2_encode_fixed_black_444(&mut source, &mut output, None, request);

        assert!(result.is_err());
    }

    #[test]
    fn av2_rejects_zero_frames() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 0 },
            geometry: Av2VideoGeometry {
                width: 64,
                height: 64,
            },
            format: PixelFormat::Yuv420p8,
        };

        assert!(request.validate().is_err());
    }

    fn assert_has_field(
        payload: &Av2SyntaxPayload,
        name: &'static str,
        code: Av2SyntaxCode,
        bit_offset: usize,
        bit_count: usize,
    ) {
        assert!(
            payload.fields.iter().any(|field| {
                field.name == name
                    && field.code == code
                    && field.bit_offset == bit_offset
                    && field.bit_count == bit_count
            }),
            "missing AV2 syntax field {name} at bit {bit_offset} with {bit_count} bit(s)"
        );
    }
}
