use std::fs::File;
use std::io::{self, BufWriter, Write};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TraceEvent {
    pub phase: String,
    pub message: String,
    pub x: Option<usize>,
    pub y: Option<usize>,
    pub w: Option<usize>,
    pub h: Option<usize>,
}

impl TraceEvent {
    pub fn new(phase: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            phase: phase.into(),
            message: message.into(),
            x: None,
            y: None,
            w: None,
            h: None,
        }
    }

    pub fn with_block(mut self, x: usize, y: usize, w: usize, h: usize) -> Self {
        self.x = Some(x);
        self.y = Some(y);
        self.w = Some(w);
        self.h = Some(h);
        self
    }

    pub fn to_json_line(&self) -> String {
        let mut fields = vec![
            format!("\"phase\":\"{}\"", escape_json(&self.phase)),
            format!("\"message\":\"{}\"", escape_json(&self.message)),
        ];
        if let Some(x) = self.x {
            fields.push(format!("\"x\":{x}"));
        }
        if let Some(y) = self.y {
            fields.push(format!("\"y\":{y}"));
        }
        if let Some(w) = self.w {
            fields.push(format!("\"w\":{w}"));
        }
        if let Some(h) = self.h {
            fields.push(format!("\"h\":{h}"));
        }
        format!("{{{}}}", fields.join(","))
    }
}

pub struct TraceSink {
    writer: BufWriter<File>,
}

impl TraceSink {
    pub fn create(path: impl AsRef<Path>) -> io::Result<Self> {
        Ok(Self {
            writer: BufWriter::new(File::create(path)?),
        })
    }

    pub fn write(&mut self, event: &TraceEvent) -> io::Result<()> {
        writeln!(self.writer, "{}", event.to_json_line())
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
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn trace_event_creates_jsonl_record() {
        let event =
            TraceEvent::new("encode", "placeholder \"bitstream\"").with_block(0, 16, 16, 16);
        assert_eq!(
            event.to_json_line(),
            "{\"phase\":\"encode\",\"message\":\"placeholder \\\"bitstream\\\"\",\"x\":0,\"y\":16,\"w\":16,\"h\":16}"
        );
    }

    #[test]
    fn trace_sink_writes_jsonl_file() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!("frameforge-trace-{unique}.jsonl"));

        {
            let mut sink = TraceSink::create(&path).unwrap();
            sink.write(&TraceEvent::new("test", "jsonl")).unwrap();
        }

        let contents = fs::read_to_string(&path).unwrap();
        let _ = fs::remove_file(&path);
        assert_eq!(contents, "{\"phase\":\"test\",\"message\":\"jsonl\"}\n");
    }
}
