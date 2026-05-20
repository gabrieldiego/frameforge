use crate::picture::{Picture, PixelFormat};

pub const FFBS_MAGIC: &[u8; 4] = b"FFBS";
pub const FFBS_VERSION: u8 = 1;
pub const CODEC_RAW_GRAY8_INTRA: u8 = 1;

const HEADER_LEN: usize = 4 + 1 + 1 + 2 + 2 + 1 + 4;
const FORMAT_GRAY8: u8 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FfbsHeader {
    pub version: u8,
    pub codec_id: u8,
    pub width: usize,
    pub height: usize,
    pub format: PixelFormat,
    pub payload_len: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodedFfbs {
    pub header: FfbsHeader,
    pub samples: Vec<u8>,
}

pub fn encode_raw_gray8(picture: &Picture) -> Result<Vec<u8>, String> {
    if picture.format != PixelFormat::Gray8 {
        return Err("ffbs raw-gray8 encoder currently supports only gray8 input".to_string());
    }
    Picture::validate_shape(picture.width, picture.height, picture.format)?;
    let expected = Picture::expected_len(picture.width, picture.height, picture.format);
    if picture.data.len() < expected {
        return Err(format!(
            "picture has {} bytes, expected at least {}",
            picture.data.len(),
            expected
        ));
    }
    if picture.width > u16::MAX as usize || picture.height > u16::MAX as usize {
        return Err("ffbs header currently stores width and height as u16".to_string());
    }
    if expected > u32::MAX as usize {
        return Err("ffbs payload is too large for the current u32 length field".to_string());
    }

    let mut out = Vec::with_capacity(HEADER_LEN + expected);
    out.extend_from_slice(FFBS_MAGIC);
    out.push(FFBS_VERSION);
    out.push(CODEC_RAW_GRAY8_INTRA);
    out.extend_from_slice(&(picture.width as u16).to_be_bytes());
    out.extend_from_slice(&(picture.height as u16).to_be_bytes());
    out.push(FORMAT_GRAY8);
    out.extend_from_slice(&(expected as u32).to_be_bytes());
    out.extend_from_slice(&picture.data[..expected]);
    Ok(out)
}

pub fn decode(bytes: &[u8]) -> Result<DecodedFfbs, String> {
    if bytes.len() < HEADER_LEN {
        return Err(format!(
            "ffbs stream is too short: got {} bytes, need at least {}",
            bytes.len(),
            HEADER_LEN
        ));
    }
    if &bytes[0..4] != FFBS_MAGIC {
        return Err("ffbs magic mismatch".to_string());
    }

    let version = bytes[4];
    if version != FFBS_VERSION {
        return Err(format!(
            "unsupported ffbs version {version}; expected {FFBS_VERSION}"
        ));
    }

    let codec_id = bytes[5];
    if codec_id != CODEC_RAW_GRAY8_INTRA {
        return Err(format!("unsupported ffbs codec id {codec_id}"));
    }

    let width = u16::from_be_bytes([bytes[6], bytes[7]]) as usize;
    let height = u16::from_be_bytes([bytes[8], bytes[9]]) as usize;
    let format = match bytes[10] {
        FORMAT_GRAY8 => PixelFormat::Gray8,
        other => return Err(format!("unsupported ffbs pixel format id {other}")),
    };
    Picture::validate_shape(width, height, format)?;

    let payload_len = u32::from_be_bytes([bytes[11], bytes[12], bytes[13], bytes[14]]) as usize;
    let expected = Picture::expected_len(width, height, format);
    if payload_len != expected {
        return Err(format!(
            "ffbs payload length {payload_len} does not match expected {expected}"
        ));
    }
    if bytes.len() != HEADER_LEN + payload_len {
        return Err(format!(
            "ffbs stream size mismatch: got {} bytes, expected {}",
            bytes.len(),
            HEADER_LEN + payload_len
        ));
    }

    Ok(DecodedFfbs {
        header: FfbsHeader {
            version,
            codec_id,
            width,
            height,
            format,
            payload_len,
        },
        samples: bytes[HEADER_LEN..].to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_gray8_round_trip_4x4() {
        let samples: Vec<u8> = (0..16).collect();
        let picture = Picture::new(4, 4, PixelFormat::Gray8, samples.clone());

        let bytes = encode_raw_gray8(&picture).unwrap();
        assert_eq!(&bytes[0..4], FFBS_MAGIC);

        let decoded = decode(&bytes).unwrap();
        assert_eq!(decoded.header.width, 4);
        assert_eq!(decoded.header.height, 4);
        assert_eq!(decoded.header.format, PixelFormat::Gray8);
        assert_eq!(decoded.samples, samples);
    }

    #[test]
    fn rejects_non_ffbs_magic() {
        assert!(decode(b"not a frameforge bitstream").is_err());
    }
}
