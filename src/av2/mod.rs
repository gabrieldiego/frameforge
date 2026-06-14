use std::io::{Read, Write};

use crate::picture::{Picture, PixelFormat};

pub mod entropy;
mod syntax;
mod tile;

use syntax::{Av2SyntaxPayload, Av2SyntaxWriter};
use tile::av2_black_444_tile_entropy_payload;

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
const AV2_DELTA_DCQUANT_MIN: i8 = -23;
const AV2_MAX_MAX_IBC_DRL_BITS_MINUS_MIN_PLUS_ONE: u16 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Av2Black444MvpProfile {
    enable_sdp: bool,
    enable_ext_partitions: bool,
    enable_uneven_4way_partitions: bool,
    enable_intra_edge_filter: bool,
    enable_mrls: bool,
    enable_cfl_intra: bool,
    enable_mhccp: bool,
    enable_ibp: bool,
    enable_refmvbank: bool,
    is_drl_reorder_disable: bool,
    def_max_bvp_drl_bits_minus_min: u16,
    allow_frame_max_bvp_drl_bits: bool,
    enable_bawp: bool,
    enable_fsc: bool,
    enable_idtx_intra: bool,
    enable_chroma_dctonly: bool,
    enable_cctx: bool,
    disable_cdf_update: bool,
}

impl Av2Black444MvpProfile {
    fn current() -> Self {
        Self {
            // Keep the first tile payload on the shared luma/chroma tree. AVM
            // decode_partition() enters separate luma/chroma trees at 64x64
            // when SDP is enabled, which is unnecessary for the first black
            // 4:4:4 bring-up stream.
            enable_sdp: false,
            enable_ext_partitions: false,
            enable_uneven_4way_partitions: false,
            enable_intra_edge_filter: false,
            enable_mrls: false,
            enable_cfl_intra: false,
            enable_mhccp: false,
            enable_ibp: false,
            enable_refmvbank: false,
            is_drl_reorder_disable: true,
            def_max_bvp_drl_bits_minus_min: 0,
            allow_frame_max_bvp_drl_bits: false,
            enable_bawp: false,
            enable_fsc: false,
            // AVM read_sequence_transform_quant_entropy_group_tool_flags()
            // sets IDTX from this bit only when FSC is disabled.
            enable_idtx_intra: true,
            enable_chroma_dctonly: false,
            enable_cctx: false,
            // AV2 v1.0.0 tile_group_obu() calls init_symbol(tileSize) before
            // decode_tile(). Disabling CDF updates keeps this first generated
            // stream independent from traversal history while block syntax is
            // being ported.
            disable_cdf_update: true,
        }
    }
}

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
    let geometry = validate_fixed_black_444_request(request)?;

    let expected_recon = av2_black_444_reconstruction_for_geometry(geometry);
    let mut frame = vec![0; expected_recon.len()];
    input
        .read_exact(&mut frame)
        .map_err(|err| format!("failed to read AV2 fixed black-frame input: {err}"))?;
    if frame != expected_recon {
        return Err(format!(
            "fixed AV2 encoder expects a black {}x{} yuv444p8 input frame",
            geometry.width, geometry.height
        ));
    }

    let bitstream = av2_black_444_bitstream_for_geometry(geometry);
    output
        .write_all(&bitstream)
        .map_err(|err| format!("failed to write AV2 bitstream: {err}"))?;
    if let Some(recon) = recon {
        recon
            .write_all(&expected_recon)
            .map_err(|err| format!("failed to write AV2 reconstruction: {err}"))?;
    }
    Ok(())
}

fn av2_black_444_bitstream_for_geometry(geometry: Av2VideoGeometry) -> Vec<u8> {
    let mut out = Vec::new();
    append_obu(
        &mut out,
        Av2ObuType::TemporalDelimiter,
        &Av2SyntaxPayload::default(),
    );
    append_obu(
        &mut out,
        Av2ObuType::SequenceHeader,
        &av2_black_444_sequence_header_payload(geometry),
    );
    append_obu(
        &mut out,
        Av2ObuType::ClosedLoopKey,
        &av2_black_444_closed_loop_key_payload(geometry),
    );
    out
}

pub fn av2_black_444_trace_jsonl(request: Av2EncodeRequest) -> Result<String, String> {
    request.validate()?;
    let geometry = validate_fixed_black_444_request(request)?;
    let sequence = av2_black_444_sequence_header_payload(geometry);
    let closed_loop_header = av2_black_444_closed_loop_key_header_payload();
    let entropy = av2_black_444_tile_entropy_payload(geometry, Av2Black444MvpProfile::current());
    let mut lines = String::new();

    push_av2_trace_line(
        &mut lines,
        "obu",
        "obu.temporal_delimiter",
        "AV2 v1.0.0 Section 5.4 OBU syntax",
        "header+payload",
        0,
        16,
    );
    for field in &sequence.fields {
        push_av2_trace_line(
            &mut lines,
            "sequence_header",
            field.name,
            av2_spec_section_for_syntax_field(field.name),
            &format!("{:?}", field.code),
            field.bit_offset,
            field.bit_count,
        );
    }
    push_av2_trace_line(
        &mut lines,
        "obu",
        "obu.closed_loop_key",
        "AV2 v1.0.0 Sections 5.19 and 5.20.1 tile group syntax",
        "header",
        0,
        8,
    );
    for field in &closed_loop_header.fields {
        push_av2_trace_line(
            &mut lines,
            "closed_loop_key_header",
            field.name,
            av2_spec_section_for_syntax_field(field.name),
            &format!("{:?}", field.code),
            field.bit_offset,
            field.bit_count,
        );
    }
    for field in &entropy.fields {
        push_av2_entropy_trace_line(&mut lines, field);
    }
    Ok(lines)
}

pub fn av2_black_64x64_444_reconstruction() -> Vec<u8> {
    av2_black_444_reconstruction_for_geometry(Av2VideoGeometry {
        width: 64,
        height: 64,
    })
}

pub fn av2_black_444_reconstruction(geometry: Av2VideoGeometry) -> Option<Vec<u8>> {
    validate_fixed_black_444_geometry(geometry).map(av2_black_444_reconstruction_for_geometry)
}

fn av2_black_444_reconstruction_for_geometry(geometry: Av2VideoGeometry) -> Vec<u8> {
    vec![0; Picture::expected_len(geometry.width, geometry.height, PixelFormat::Yuv444p8,)]
}

fn validate_fixed_black_444_request(request: Av2EncodeRequest) -> Result<Av2VideoGeometry, String> {
    if request.params.frames != 1 || request.format != PixelFormat::Yuv444p8 {
        return Err(
            "fixed AV2 encoder only supports one yuv444p8 black frame at 8-pixel geometry"
                .to_string(),
        );
    }
    validate_fixed_black_444_geometry(request.geometry).ok_or_else(|| {
        "fixed AV2 encoder only supports 8x8 through 64x64 yuv444p8 black frames in 8-pixel steps"
            .to_string()
    })
}

fn validate_fixed_black_444_geometry(geometry: Av2VideoGeometry) -> Option<Av2VideoGeometry> {
    let supported = (8..=64).contains(&geometry.width)
        && (8..=64).contains(&geometry.height)
        && geometry.width % 8 == 0
        && geometry.height % 8 == 0;
    supported.then_some(geometry)
}

fn av2_black_444_sequence_header_payload(geometry: Av2VideoGeometry) -> Av2SyntaxPayload {
    let mut writer = Av2SyntaxWriter::new();
    let width_bits = av2_frame_dimension_bits(geometry.width);
    let height_bits = av2_frame_dimension_bits(geometry.height);

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
        (width_bits - 1) as u64,
        4,
    );
    writer.write_literal(
        "sequence_header.num_bits_height_minus_1",
        (height_bits - 1) as u64,
        4,
    );
    writer.write_literal(
        "sequence_header.max_frame_width_minus_1",
        (geometry.width - 1) as u64,
        width_bits,
    );
    writer.write_literal(
        "sequence_header.max_frame_height_minus_1",
        (geometry.height - 1) as u64,
        height_bits,
    );
    writer.write_flag("sequence_header.conf_win_enabled_flag", false);

    write_fixed_black_444_sequence_tools(&mut writer);

    writer.write_flag("sequence_header.film_grain_params_present", false);
    writer.write_flag("sequence_header.seq_extension_present_flag", false);
    writer.trailing_bits();
    writer.finish()
}

fn av2_frame_dimension_bits(dimension: usize) -> u8 {
    assert!(dimension > 0, "AV2 frame dimension must be positive");
    let max_index = (dimension - 1) as u64;
    (64 - max_index.leading_zeros()) as u8
}

fn write_fixed_black_444_sequence_tools(writer: &mut Av2SyntaxWriter) {
    let profile = Av2Black444MvpProfile::current();

    // AV2 v1.0.0 sequence_header() tool groups, mirrored from AVM
    // write_sequence_header(). Values are the fixed AVM choices for one
    // black yuv444p8 still picture in the minimum viable bitstream subset.
    writer.write_flag("sequence_partition.sb_size_is_256", false);
    writer.write_flag("sequence_partition.sb_size_is_128", false);
    writer.write_flag("sequence_partition.enable_sdp", profile.enable_sdp);
    writer.write_flag(
        "sequence_partition.enable_ext_partitions",
        profile.enable_ext_partitions,
    );
    if profile.enable_ext_partitions {
        writer.write_flag(
            "sequence_partition.enable_uneven_4way_partitions",
            profile.enable_uneven_4way_partitions,
        );
    }
    writer.write_flag("sequence_partition.max_pb_aspect_ratio_lt2", false);

    writer.write_flag("sequence_segment.enable_ext_seg", false);
    writer.write_flag("sequence_segment.seq_seg_info_present_flag", false);

    writer.write_flag("sequence_intra.enable_intra_dip", false);
    writer.write_flag(
        "sequence_intra.enable_intra_edge_filter",
        profile.enable_intra_edge_filter,
    );
    writer.write_flag("sequence_intra.enable_mrls", profile.enable_mrls);
    writer.write_flag("sequence_intra.enable_cfl_intra", profile.enable_cfl_intra);
    writer.write_literal("sequence_intra.cfl_ds_filter_index", 0, 2);
    writer.write_flag("sequence_intra.enable_mhccp", profile.enable_mhccp);
    writer.write_flag("sequence_intra.enable_ibp", profile.enable_ibp);

    writer.write_flag("sequence_inter.enable_refmvbank", profile.enable_refmvbank);
    writer.write_flag(
        "sequence_inter.is_drl_reorder_disable",
        profile.is_drl_reorder_disable,
    );
    if !profile.is_drl_reorder_disable {
        writer.write_flag("sequence_inter.enable_drl_reorder_constraint", false);
    }
    writer.write_quniform(
        "sequence_inter.def_max_bvp_drl_bits_minus_min",
        AV2_MAX_MAX_IBC_DRL_BITS_MINUS_MIN_PLUS_ONE,
        profile.def_max_bvp_drl_bits_minus_min,
    );
    writer.write_flag(
        "sequence_inter.allow_frame_max_bvp_drl_bits",
        profile.allow_frame_max_bvp_drl_bits,
    );
    writer.write_flag("sequence_inter.enable_bawp", profile.enable_bawp);

    writer.write_flag("sequence_transform.enable_fsc", profile.enable_fsc);
    if !profile.enable_fsc {
        writer.write_flag(
            "sequence_transform.enable_idtx_intra",
            profile.enable_idtx_intra,
        );
    }
    writer.write_flag("sequence_transform.enable_ist", false);
    writer.write_flag("sequence_transform.enable_inter_ist", false);
    writer.write_flag(
        "sequence_transform.enable_chroma_dctonly",
        profile.enable_chroma_dctonly,
    );
    writer.write_flag("sequence_transform.reduced_tx_part_set", false);
    writer.write_flag("sequence_transform.enable_cctx", profile.enable_cctx);
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

fn av2_black_444_closed_loop_key_header_payload() -> Av2SyntaxPayload {
    let profile = Av2Black444MvpProfile::current();
    let mut writer = Av2SyntaxWriter::new();

    // AV2 v1.0.0 tile_group_obu() for a single-tile OBU_CLOSED_LOOP_KEY.
    // The uncompressed header follows AVM write_tilegroup_header() and
    // write_uncompressed_header(). The tile entropy payload is generated by
    // the AV2 range writer below; the current MVP emits a 64x64 DC intra block
    // with DC-only residual TXBs for a lossless black 4:4:4 frame.
    writer.write_flag("tile_group.first_tile_group_in_frame", true);
    writer.write_uvlc("uncompressed_header.cur_mfh_id", 0);
    writer.write_uvlc("uncompressed_header.seq_header_id", 0);
    writer.write_flag("uncompressed_header.allow_screen_content_tools", false);
    writer.write_flag("uncompressed_header.allow_intrabc", false);
    writer.write_flag(
        "uncompressed_header.disable_cdf_update",
        profile.disable_cdf_update,
    );
    writer.write_flag("tile_info.uniform_spacing_flag", true);
    writer.write_literal("quantization.base_qindex", 0, 8);
    writer.write_flag("segmentation.enabled", false);
    writer.write_flag("quantization_matrix.using_qmatrix", false);
    writer.write_literal("uncompressed_header.reduced_tx_set_used", 0, 2);
    writer.byte_align_zero("tile_group.header_byte_alignment");

    writer.finish()
}

fn av2_black_444_closed_loop_key_payload(geometry: Av2VideoGeometry) -> Av2SyntaxPayload {
    let mut payload = av2_black_444_closed_loop_key_header_payload();
    let entropy = av2_black_444_tile_entropy_payload(geometry, Av2Black444MvpProfile::current());
    let bit_offset = payload.bytes.len() * 8;
    payload.fields.push(syntax::Av2SyntaxField {
        name: "tile_group.tile_entropy_payload",
        code: syntax::Av2SyntaxCode::TileEntropyPayload,
        bit_offset,
        bit_count: entropy.bytes.len() * 8,
    });
    payload.bytes.extend_from_slice(&entropy.bytes);
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

fn push_av2_trace_line(
    out: &mut String,
    phase: &str,
    name: &str,
    spec: &str,
    code: &str,
    bit_offset: usize,
    bit_count: usize,
) {
    out.push_str(&format!(
        "{{\"codec\":\"av2\",\"source\":\"software\",\"phase\":\"{}\",\"name\":\"{}\",\"spec\":\"{}\",\"code\":\"{}\",\"bit_offset\":{},\"bit_count\":{}}}\n",
        escape_json(phase),
        escape_json(name),
        escape_json(spec),
        escape_json(code),
        bit_offset,
        bit_count
    ));
}

fn push_av2_entropy_trace_line(out: &mut String, field: &entropy::Av2EntropyField) {
    let mut line = format!(
        "{{\"codec\":\"av2\",\"source\":\"software\",\"phase\":\"tile_entropy\",\"name\":\"{}\",\"spec\":\"{}\",\"code\":\"{}\",\"bit_offset\":{},\"bit_count\":{}",
        escape_json(field.name),
        escape_json(av2_spec_section_for_entropy_field(field.name)),
        escape_json(&format!("{:?}", field.code)),
        field.symbol_offset,
        field.bit_count
    );
    if let Some(symbol) = field.symbol {
        line.push_str(&format!(",\"symbol\":{symbol}"));
    }
    if let Some(value) = field.literal_value {
        line.push_str(&format!(",\"literal_value\":{value}"));
    }
    if let Some(fl) = field.fl {
        line.push_str(&format!(",\"fl\":{fl}"));
    }
    if let Some(fh) = field.fh {
        line.push_str(&format!(",\"fh\":{fh}"));
    }
    if let Some(fl_inc) = field.fl_inc {
        line.push_str(&format!(",\"fl_inc\":{fl_inc}"));
    }
    if let Some(fh_inc) = field.fh_inc {
        line.push_str(&format!(",\"fh_inc\":{fh_inc}"));
    }
    line.push_str("}\n");
    out.push_str(&line);
}

fn av2_spec_section_for_syntax_field(name: &str) -> &'static str {
    if name.starts_with("sequence_header.") || name.starts_with("sequence_") {
        "AV2 v1.0.0 Section 5.4.1 sequence_header_obu()"
    } else if name.starts_with("tile_group.") || name.starts_with("uncompressed_header.") {
        "AV2 v1.0.0 Sections 5.19 and 5.20.1 tile_group_obu()"
    } else if name.starts_with("tile_info.")
        || name.starts_with("quantization.")
        || name.starts_with("segmentation.")
        || name.starts_with("quantization_matrix.")
    {
        "AV2 v1.0.0 Section 5.20.1 uncompressed header syntax"
    } else if name == "trailing_bits" {
        "AV2 v1.0.0 Section 5.4.1 trailing bits"
    } else {
        "AV2 v1.0.0 syntax"
    }
}

fn av2_spec_section_for_entropy_field(name: &str) -> &'static str {
    if name.starts_with("tile.partition.") {
        "AV2 v1.0.0 Section 5.20.3.2 partition()"
    } else if name.starts_with("tile.intra.") {
        "AV2 v1.0.0 Section 5.20.5.3 intra_frame_mode_info()"
    } else if name.starts_with("tile.coeff.") {
        "AV2 v1.0.0 Sections 5.20.7.24 and 5.20.7.25 transform coefficient syntax"
    } else {
        "AV2 v1.0.0 tile entropy syntax"
    }
}

fn escape_json(value: &str) -> String {
    let mut out = String::new();
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
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
    fn av2_fixed_black_444_emits_generated_obu_stream_and_reconstruction() {
        for geometry in supported_black_444_geometries() {
            let request = Av2EncodeRequest {
                params: Av2EncodeParams { frames: 1 },
                geometry,
                format: PixelFormat::Yuv444p8,
            };
            let input =
                av2_black_444_reconstruction(geometry).expect("supported AV2 fixed black geometry");
            let mut source = input.as_slice();
            let mut output = Vec::new();
            let mut recon = Vec::new();

            let result =
                av2_encode_fixed_black_444(&mut source, &mut output, Some(&mut recon), request);

            result.expect("AV2 OBU encode should succeed");
            assert_eq!(output, av2_black_444_bitstream_for_geometry(geometry));
            assert_eq!(&output[..2], &[0x01, 0x08]);
            assert_ne!(output, input);
            assert_eq!(recon, input);
        }
    }

    #[test]
    fn av2_fixed_black_444_sequence_header_has_labeled_fields() {
        let payload = av2_black_444_sequence_header_payload(Av2VideoGeometry {
            width: 64,
            height: 64,
        });

        assert_eq!(
            payload.bytes,
            vec![0x92, 0x06, 0x95, 0x7f, 0xfc, 0x00, 0x01, 0x08, 0x06, 0xe0, 0x22]
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
            70,
            5,
        );
        assert_has_field(
            &payload,
            "trailing_bits",
            Av2SyntaxCode::TrailingBits,
            86,
            2,
        );
    }

    #[test]
    fn av2_fixed_black_444_closed_loop_key_labels_header_fields() {
        let payload = av2_black_444_closed_loop_key_header_payload();

        assert_eq!(payload.bytes, vec![0xe6, 0x00, 0x00]);
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
    }

    #[test]
    fn av2_fixed_black_444_closed_loop_key_carries_generated_tile_entropy_payload() {
        let payload = av2_black_444_closed_loop_key_payload(Av2VideoGeometry {
            width: 64,
            height: 64,
        });

        assert_eq!(&payload.bytes[..3], &[0xe6, 0x00, 0x00]);
        assert!(payload.bytes.len() > 3);
        let entropy_field = payload
            .fields
            .iter()
            .find(|field| field.name == "tile_group.tile_entropy_payload")
            .expect("missing AV2 tile entropy payload field");
        assert_eq!(entropy_field.code, Av2SyntaxCode::TileEntropyPayload);
        assert_eq!(entropy_field.bit_offset, 24);
        assert_eq!(entropy_field.bit_count, (payload.bytes.len() - 3) * 8);
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

    fn supported_black_444_geometries() -> Vec<Av2VideoGeometry> {
        let mut geometries = Vec::new();
        for height in (8..=64).step_by(8) {
            for width in (8..=64).step_by(8) {
                geometries.push(Av2VideoGeometry { width, height });
            }
        }
        geometries
    }
}
