use std::fmt;
use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PixelFormat {
    Yuv420p8,
    Yuv420p10,
    Yuv420p12,
    Yuv420p16,
    Yuv422p8,
    Yuv422p10,
    Yuv422p12,
    Yuv422p16,
    Yuv444p8,
    Yuv444p10,
    Yuv444p12,
    Yuv444p16,
    Gray8,
    Gray10,
    Gray12,
    Gray16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SampleBitDepth {
    Eight,
    Ten,
    Twelve,
    Sixteen,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChromaSampling {
    Monochrome,
    Cs420,
    Cs422,
    Cs444,
}

impl ChromaSampling {
    pub fn chroma_plane_samples(self, width: usize, height: usize) -> Option<usize> {
        let luma = width.checked_mul(height)?;
        match self {
            Self::Monochrome => Some(0),
            Self::Cs420 => luma.checked_div(4),
            Self::Cs422 => luma.checked_div(2),
            Self::Cs444 => Some(luma),
        }
    }
}

impl SampleBitDepth {
    pub fn bits(self) -> u8 {
        match self {
            Self::Eight => 8,
            Self::Ten => 10,
            Self::Twelve => 12,
            Self::Sixteen => 16,
        }
    }

    pub fn bytes_per_sample(self) -> usize {
        if self.bits() <= 8 {
            1
        } else {
            2
        }
    }

    pub fn max_sample(self) -> u16 {
        (1u32.checked_shl(self.bits() as u32).unwrap() - 1) as u16
    }
}

impl FromStr for PixelFormat {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "yuv420p8" | "i420" => Ok(Self::Yuv420p8),
            "yuv420p10" | "yuv420p10le" | "i010" => Ok(Self::Yuv420p10),
            "yuv420p12" | "yuv420p12le" | "i012" => Ok(Self::Yuv420p12),
            "yuv420p16" | "yuv420p16le" | "i016" => Ok(Self::Yuv420p16),
            "yuv422p8" | "i422" => Ok(Self::Yuv422p8),
            "yuv422p10" | "yuv422p10le" | "i210" => Ok(Self::Yuv422p10),
            "yuv422p12" | "yuv422p12le" | "i212" => Ok(Self::Yuv422p12),
            "yuv422p16" | "yuv422p16le" | "i216" => Ok(Self::Yuv422p16),
            "yuv444p8" | "i444" => Ok(Self::Yuv444p8),
            "yuv444p10" | "yuv444p10le" | "i410" => Ok(Self::Yuv444p10),
            "yuv444p12" | "yuv444p12le" | "i412" => Ok(Self::Yuv444p12),
            "yuv444p16" | "yuv444p16le" | "i416" => Ok(Self::Yuv444p16),
            "gray8" | "y8" => Ok(Self::Gray8),
            "gray10" | "gray10le" | "y10" | "y10le" => Ok(Self::Gray10),
            "gray12" | "gray12le" | "y12" | "y12le" => Ok(Self::Gray12),
            "gray16" | "gray16le" | "y16" | "y16le" => Ok(Self::Gray16),
            other => Err(format!(
                "unsupported format '{other}'; supported formats: yuv420p, yuv422p, yuv444p, and gray at 8/10/12/16 bits"
            )),
        }
    }
}

impl fmt::Display for PixelFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Yuv420p8 => f.write_str("yuv420p8"),
            Self::Yuv420p10 => f.write_str("yuv420p10le"),
            Self::Yuv420p12 => f.write_str("yuv420p12le"),
            Self::Yuv420p16 => f.write_str("yuv420p16le"),
            Self::Yuv422p8 => f.write_str("yuv422p8"),
            Self::Yuv422p10 => f.write_str("yuv422p10le"),
            Self::Yuv422p12 => f.write_str("yuv422p12le"),
            Self::Yuv422p16 => f.write_str("yuv422p16le"),
            Self::Yuv444p8 => f.write_str("yuv444p8"),
            Self::Yuv444p10 => f.write_str("yuv444p10le"),
            Self::Yuv444p12 => f.write_str("yuv444p12le"),
            Self::Yuv444p16 => f.write_str("yuv444p16le"),
            Self::Gray8 => f.write_str("gray8"),
            Self::Gray10 => f.write_str("gray10le"),
            Self::Gray12 => f.write_str("gray12le"),
            Self::Gray16 => f.write_str("gray16le"),
        }
    }
}

impl PixelFormat {
    pub fn bit_depth(self) -> SampleBitDepth {
        match self {
            Self::Yuv420p8 | Self::Yuv422p8 | Self::Yuv444p8 | Self::Gray8 => SampleBitDepth::Eight,
            Self::Yuv420p10 | Self::Yuv422p10 | Self::Yuv444p10 | Self::Gray10 => {
                SampleBitDepth::Ten
            }
            Self::Yuv420p12 | Self::Yuv422p12 | Self::Yuv444p12 | Self::Gray12 => {
                SampleBitDepth::Twelve
            }
            Self::Yuv420p16 | Self::Yuv422p16 | Self::Yuv444p16 | Self::Gray16 => {
                SampleBitDepth::Sixteen
            }
        }
    }

    pub fn bytes_per_sample(self) -> usize {
        self.bit_depth().bytes_per_sample()
    }

    pub fn is_yuv420(self) -> bool {
        matches!(
            self,
            Self::Yuv420p8 | Self::Yuv420p10 | Self::Yuv420p12 | Self::Yuv420p16
        )
    }

    pub fn is_yuv(self) -> bool {
        self.chroma_sampling()
            .is_some_and(|sampling| sampling != ChromaSampling::Monochrome)
    }

    pub fn chroma_sampling(self) -> Option<ChromaSampling> {
        match self {
            Self::Yuv420p8 | Self::Yuv420p10 | Self::Yuv420p12 | Self::Yuv420p16 => {
                Some(ChromaSampling::Cs420)
            }
            Self::Yuv422p8 | Self::Yuv422p10 | Self::Yuv422p12 | Self::Yuv422p16 => {
                Some(ChromaSampling::Cs422)
            }
            Self::Yuv444p8 | Self::Yuv444p10 | Self::Yuv444p12 | Self::Yuv444p16 => {
                Some(ChromaSampling::Cs444)
            }
            Self::Gray8 | Self::Gray10 | Self::Gray12 | Self::Gray16 => {
                Some(ChromaSampling::Monochrome)
            }
        }
    }

    pub fn chroma_plane_samples(self, width: usize, height: usize) -> Option<usize> {
        self.chroma_sampling()?.chroma_plane_samples(width, height)
    }
}

#[derive(Debug, Clone)]
pub struct Picture {
    pub width: usize,
    pub height: usize,
    pub format: PixelFormat,
    pub data: Vec<u8>,
}

impl Picture {
    pub fn new(width: usize, height: usize, format: PixelFormat, data: Vec<u8>) -> Self {
        Self {
            width,
            height,
            format,
            data,
        }
    }

    pub fn expected_len(width: usize, height: usize, format: PixelFormat) -> usize {
        Self::checked_len(width, height, format).expect("picture dimensions overflow usize")
    }

    pub fn checked_len(width: usize, height: usize, format: PixelFormat) -> Option<usize> {
        let luma = width.checked_mul(height)?;
        let bytes_per_sample = format.bytes_per_sample();
        match format {
            PixelFormat::Yuv420p8
            | PixelFormat::Yuv420p10
            | PixelFormat::Yuv420p12
            | PixelFormat::Yuv420p16
            | PixelFormat::Yuv422p8
            | PixelFormat::Yuv422p10
            | PixelFormat::Yuv422p12
            | PixelFormat::Yuv422p16
            | PixelFormat::Yuv444p8
            | PixelFormat::Yuv444p10
            | PixelFormat::Yuv444p12
            | PixelFormat::Yuv444p16 => {
                let chroma_plane = format.chroma_plane_samples(width, height)?;
                luma.checked_add(chroma_plane.checked_mul(2)?)?
                    .checked_mul(bytes_per_sample)
            }
            PixelFormat::Gray8
            | PixelFormat::Gray10
            | PixelFormat::Gray12
            | PixelFormat::Gray16 => luma.checked_mul(bytes_per_sample),
        }
    }

    pub fn validate_shape(width: usize, height: usize, format: PixelFormat) -> Result<(), String> {
        if width == 0 || height == 0 {
            return Err("picture width and height must be non-zero".to_string());
        }
        if format.is_yuv420() && (!width.is_multiple_of(2) || !height.is_multiple_of(2)) {
            return Err("yuv420p formats require even width and height".to_string());
        }
        if matches!(format.chroma_sampling(), Some(ChromaSampling::Cs422))
            && !width.is_multiple_of(2)
        {
            return Err("yuv422p formats require even width".to_string());
        }
        Self::checked_len(width, height, format)
            .ok_or_else(|| "picture dimensions overflow addressable memory".to_string())?;
        Ok(())
    }
}

#[derive(Debug, Clone)]
pub struct ReconstructionBuffer {
    pub width: usize,
    pub height: usize,
    pub format: PixelFormat,
    samples: Vec<u8>,
}

impl ReconstructionBuffer {
    pub fn new(width: usize, height: usize, format: PixelFormat) -> Self {
        Self {
            width,
            height,
            format,
            samples: vec![0; Picture::expected_len(width, height, format)],
        }
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.samples
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_planar_yuv420_bit_depth_formats() {
        assert_eq!("yuv420p8".parse::<PixelFormat>(), Ok(PixelFormat::Yuv420p8));
        assert_eq!(
            "yuv420p10le".parse::<PixelFormat>(),
            Ok(PixelFormat::Yuv420p10)
        );
        assert_eq!(
            "yuv420p12".parse::<PixelFormat>(),
            Ok(PixelFormat::Yuv420p12)
        );
        assert_eq!("i016".parse::<PixelFormat>(), Ok(PixelFormat::Yuv420p16));
        assert_eq!("i422".parse::<PixelFormat>(), Ok(PixelFormat::Yuv422p8));
        assert_eq!(
            "yuv422p10le".parse::<PixelFormat>(),
            Ok(PixelFormat::Yuv422p10)
        );
        assert_eq!("i444".parse::<PixelFormat>(), Ok(PixelFormat::Yuv444p8));
        assert_eq!(
            "yuv444p16".parse::<PixelFormat>(),
            Ok(PixelFormat::Yuv444p16)
        );
    }

    #[test]
    fn computes_high_bit_depth_frame_lengths() {
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Yuv420p8), 24);
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Yuv420p10), 48);
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Yuv420p12), 48);
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Yuv420p16), 48);
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Yuv422p8), 32);
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Yuv422p10), 64);
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Yuv444p8), 48);
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Yuv444p16), 96);
        assert_eq!(Picture::expected_len(4, 4, PixelFormat::Gray16), 32);
    }

    #[test]
    fn exposes_format_bit_depth_properties() {
        assert_eq!(PixelFormat::Yuv420p8.bit_depth().bits(), 8);
        assert_eq!(PixelFormat::Yuv420p10.bit_depth().bits(), 10);
        assert_eq!(PixelFormat::Yuv420p12.bit_depth().max_sample(), 4095);
        assert_eq!(PixelFormat::Yuv420p16.bytes_per_sample(), 2);
        assert!(PixelFormat::Yuv420p16.is_yuv420());
        assert!(PixelFormat::Yuv422p8.is_yuv());
        assert!(PixelFormat::Yuv444p16.is_yuv());
        assert!(!PixelFormat::Gray16.is_yuv420());
        assert!(!PixelFormat::Gray16.is_yuv());
        assert_eq!(
            PixelFormat::Yuv422p8.chroma_sampling(),
            Some(ChromaSampling::Cs422)
        );
        assert_eq!(PixelFormat::Yuv444p8.chroma_plane_samples(4, 4), Some(16));
    }
}
