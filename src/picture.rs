use std::fmt;
use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PixelFormat {
    Yuv420p8,
    Gray8,
}

impl FromStr for PixelFormat {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "yuv420p8" | "i420" => Ok(Self::Yuv420p8),
            "gray8" | "y8" => Ok(Self::Gray8),
            other => Err(format!(
                "unsupported format '{other}'; supported formats: yuv420p8, gray8"
            )),
        }
    }
}

impl fmt::Display for PixelFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Yuv420p8 => f.write_str("yuv420p8"),
            Self::Gray8 => f.write_str("gray8"),
        }
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
        match format {
            PixelFormat::Yuv420p8 => width * height * 3 / 2,
            PixelFormat::Gray8 => width * height,
        }
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
