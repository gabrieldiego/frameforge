use std::io::{Read, Write};

use crate::picture::{Picture, PixelFormat};

pub const AV2_CODEC_NAME: &str = "av2";
pub const AV2_BITSTREAM_EXTENSION: &str = "av2";
pub const AV2_TEMP_BLACK_444_WIDTH: usize = 64;
pub const AV2_TEMP_BLACK_444_HEIGHT: usize = 64;

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

pub fn av2_encode_temporary_black_444(
    input: &mut dyn Read,
    output: &mut dyn Write,
    recon: Option<&mut dyn Write>,
    request: Av2EncodeRequest,
) -> Result<(), String> {
    request.validate()?;
    validate_temporary_black_444_request(request)?;

    let payload = av2_temporary_black_444_payload();
    let mut frame = vec![0; payload.len()];
    input
        .read_exact(&mut frame)
        .map_err(|err| format!("failed to read AV2 temporary black-frame input: {err}"))?;
    if frame != payload {
        return Err("temporary AV2 encoder expects a black 64x64 yuv444p8 input frame".to_string());
    }

    // TODO(av2): remove this fixed raw-payload shortcut once the first real
    // AV2 sequence/header and picture writer is implemented.
    output
        .write_all(&payload)
        .map_err(|err| format!("failed to write AV2 temporary payload: {err}"))?;
    if let Some(recon) = recon {
        recon
            .write_all(&payload)
            .map_err(|err| format!("failed to write AV2 temporary reconstruction: {err}"))?;
    }
    Ok(())
}

pub fn av2_temporary_black_444_payload() -> Vec<u8> {
    vec![
        0;
        Picture::expected_len(
            AV2_TEMP_BLACK_444_WIDTH,
            AV2_TEMP_BLACK_444_HEIGHT,
            PixelFormat::Yuv444p8,
        )
    ]
}

fn validate_temporary_black_444_request(request: Av2EncodeRequest) -> Result<(), String> {
    if request.geometry.width != AV2_TEMP_BLACK_444_WIDTH
        || request.geometry.height != AV2_TEMP_BLACK_444_HEIGHT
        || request.params.frames != 1
        || request.format != PixelFormat::Yuv444p8
    {
        return Err(
            "temporary AV2 encoder only supports one 64x64 yuv444p8 black frame".to_string(),
        );
    }
    Ok(())
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
    fn av2_temporary_black_444_emits_payload_and_recon() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: AV2_TEMP_BLACK_444_WIDTH,
                height: AV2_TEMP_BLACK_444_HEIGHT,
            },
            format: PixelFormat::Yuv444p8,
        };
        let input = av2_temporary_black_444_payload();
        let mut source = input.as_slice();
        let mut output = Vec::new();
        let mut recon = Vec::new();

        av2_encode_temporary_black_444(&mut source, &mut output, Some(&mut recon), request)
            .expect("temporary AV2 black-frame encode should succeed");

        assert_eq!(output, input);
        assert_eq!(recon, input);
    }

    #[test]
    fn av2_temporary_black_444_rejects_non_black_input() {
        let request = Av2EncodeRequest {
            params: Av2EncodeParams { frames: 1 },
            geometry: Av2VideoGeometry {
                width: AV2_TEMP_BLACK_444_WIDTH,
                height: AV2_TEMP_BLACK_444_HEIGHT,
            },
            format: PixelFormat::Yuv444p8,
        };
        let mut input = av2_temporary_black_444_payload();
        input[0] = 1;
        let mut source = input.as_slice();
        let mut output = Vec::new();

        let result = av2_encode_temporary_black_444(&mut source, &mut output, None, request);

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
