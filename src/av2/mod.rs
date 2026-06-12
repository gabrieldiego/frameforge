use std::io::{Read, Write};

use crate::bitstream::BitWriter;
use crate::picture::{Picture, PixelFormat};

pub const AV2_CODEC_NAME: &str = "av2";
pub const AV2_BITSTREAM_EXTENSION: &str = "av2";
pub const AV2_FIXED_BLACK_444_WIDTH: usize = 64;
pub const AV2_FIXED_BLACK_444_HEIGHT: usize = 64;

// AV2 v1.0.0 fixed bring-up payloads for one lossless 64x64 yuv444p8 black
// frame. The encoder below writes the length-delimited OBU framing from the
// spec: Annex B bitstream(), section 5.2.2 obu_header(), and section 5.2.3
// trailing_bits(). These payloads are intentionally fixed until the
// sequence_header_obu(), frame_header(), and tile_group_obu() writers are
// expanded from the same syntax tables for non-black or non-64x64 pictures.
const AV2_BLACK_64X64_444_SEQUENCE_HEADER_PAYLOAD: &[u8] = &[
    0x92, 0x06, 0x95, 0x7f, 0xfc, 0x70, 0xe7, 0x36, 0x11, 0xb8, 0x08, 0x80,
];

const AV2_BLACK_64X64_444_CLOSED_LOOP_KEY_PAYLOAD: &[u8] = &[
    0xe2, 0x00, 0x00, 0x00, 0x12, 0x2e, 0x6a, 0x24, 0xb3, 0xe1, 0x80, 0xd0, 0x4c, 0x79, 0xff, 0x4e,
    0xdb, 0x90, 0x36, 0xe7, 0xc0,
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
    append_obu(&mut out, Av2ObuType::TemporalDelimiter, &[]);
    append_obu(
        &mut out,
        Av2ObuType::SequenceHeader,
        AV2_BLACK_64X64_444_SEQUENCE_HEADER_PAYLOAD,
    );
    append_obu(
        &mut out,
        Av2ObuType::ClosedLoopKey,
        AV2_BLACK_64X64_444_CLOSED_LOOP_KEY_PAYLOAD,
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

fn append_obu(out: &mut Vec<u8>, obu_type: Av2ObuType, payload: &[u8]) {
    let header = av2_obu_header(obu_type);
    write_leb128((header.len() + payload.len()) as u32, out);
    out.extend_from_slice(&header);
    out.extend_from_slice(payload);
}

fn av2_obu_header(obu_type: Av2ObuType) -> Vec<u8> {
    let mut writer = BitWriter::new();
    writer.write_bit(false);
    writer.write_bits(obu_type as u64, 5);
    writer.write_bits(0, 2);
    writer.into_bytes()
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
}
