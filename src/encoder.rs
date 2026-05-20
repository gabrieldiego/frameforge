use crate::bitstream::{rbsp_trailing_bits, AnnexBWriter, BitWriter, NalUnit, NalUnitKind};
use crate::picture::{Picture, PixelFormat, ReconstructionBuffer};
use crate::trace::TraceEvent;

pub const PLACEHOLDER_MAGIC: &[u8] = b"FRAMEFORGE_PLACEHOLDER_NOT_A_VALID_CODEC_BITSTREAM\n";
pub const PLACEHOLDER_VERSION: u8 = 1;

#[derive(Debug, Clone)]
pub struct EncoderParams {
    pub width: usize,
    pub height: usize,
    pub format: PixelFormat,
    pub block_size: usize,
}

impl EncoderParams {
    pub fn new(width: usize, height: usize, format: PixelFormat) -> Self {
        Self {
            width,
            height,
            format,
            block_size: 64,
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        Picture::validate_shape(self.width, self.height, self.format)?;
        if self.block_size == 0 {
            return Err("block size must be non-zero".to_string());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Block {
    pub x: usize,
    pub y: usize,
    pub w: usize,
    pub h: usize,
}

pub fn traverse_blocks(width: usize, height: usize, block_size: usize) -> Vec<Block> {
    assert!(block_size > 0, "block size must be non-zero");
    let mut blocks = Vec::new();
    let mut y = 0;
    while y < height {
        let mut x = 0;
        while x < width {
            blocks.push(Block {
                x,
                y,
                w: block_size.min(width - x),
                h: block_size.min(height - y),
            });
            x += block_size;
        }
        y += block_size;
    }
    blocks
}

#[derive(Debug, Default)]
pub struct EncodeResult {
    pub bytes: Vec<u8>,
    pub trace_events: Vec<TraceEvent>,
}

pub trait Encoder {
    fn encode_picture(&mut self, picture: &Picture) -> Result<EncodeResult, String>;
}

pub struct PlaceholderEncoder {
    params: EncoderParams,
    recon: ReconstructionBuffer,
}

impl PlaceholderEncoder {
    pub fn new(params: EncoderParams) -> Self {
        params
            .validate()
            .expect("invalid encoder parameters for placeholder encoder");
        let recon = ReconstructionBuffer::new(params.width, params.height, params.format);
        Self { params, recon }
    }
}

impl Encoder for PlaceholderEncoder {
    fn encode_picture(&mut self, picture: &Picture) -> Result<EncodeResult, String> {
        self.params.validate()?;
        if picture.width != self.params.width
            || picture.height != self.params.height
            || picture.format != self.params.format
        {
            return Err("picture dimensions or format do not match encoder parameters".to_string());
        }

        let mut trace_events = vec![TraceEvent::new(
            "encode",
            "FrameForge placeholder encode; output is not a valid codec bitstream",
        )];

        for block in traverse_blocks(
            self.params.width,
            self.params.height,
            self.params.block_size,
        ) {
            trace_events.push(
                TraceEvent::new("traverse", "visit coding block")
                    .with_block(block.x, block.y, block.w, block.h),
            );
        }

        let mut rbsp = BitWriter::new();
        rbsp.write_bits(0x4652_4647, 32);
        rbsp.write_bits(PLACEHOLDER_VERSION as u64, 8);
        rbsp.write_bits(self.params.width as u64, 16);
        rbsp.write_bits(self.params.height as u64, 16);
        rbsp.write_bool(matches!(self.params.format, PixelFormat::Yuv420p8));
        rbsp_trailing_bits(&mut rbsp);

        let mut payload = PLACEHOLDER_MAGIC.to_vec();
        payload.extend_from_slice(&rbsp.into_bytes());
        let _ = self.recon.as_slice();

        let mut writer = AnnexBWriter::new();
        writer.push(NalUnit {
            kind: NalUnitKind::FrameForgePlaceholder,
            temporal_id: 0,
            payload,
        });

        Ok(EncodeResult {
            bytes: writer.into_bytes(),
            trace_events,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn traversal_count_for_non_multiple_frame() {
        let blocks = traverse_blocks(130, 65, 64);
        assert_eq!(blocks.len(), 6);
        assert_eq!(
            blocks.last(),
            Some(&Block {
                x: 128,
                y: 64,
                w: 2,
                h: 1
            })
        );
    }

    #[test]
    fn encoder_params_reject_zero_dimensions() {
        let params = EncoderParams::new(0, 64, PixelFormat::Gray8);
        assert!(params.validate().is_err());
    }

    #[test]
    fn encoder_params_reject_odd_yuv420_dimensions() {
        let params = EncoderParams::new(63, 64, PixelFormat::Yuv420p8);
        assert!(params.validate().is_err());
    }

    #[test]
    fn placeholder_encoder_emits_marked_output() {
        let params = EncoderParams::new(4, 4, PixelFormat::Gray8);
        let picture = Picture::new(4, 4, PixelFormat::Gray8, vec![0; 16]);
        let mut encoder = PlaceholderEncoder::new(params);

        let result = encoder.encode_picture(&picture).unwrap();
        assert!(result.bytes.starts_with(&[0, 0, 0, 1]));
        assert!(result
            .bytes
            .windows(PLACEHOLDER_MAGIC.len())
            .any(|window| window == PLACEHOLDER_MAGIC));
        assert!(!result.trace_events.is_empty());
    }
}
