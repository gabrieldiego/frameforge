use std::env;
use std::fs;
use std::path::PathBuf;

use frameforge::trace::TraceSink;
use frameforge::{Encoder, EncoderParams, Picture, PixelFormat, PlaceholderEncoder};

#[derive(Debug)]
struct Cli {
    input: PathBuf,
    width: usize,
    height: usize,
    format: PixelFormat,
    output: PathBuf,
    trace: Option<PathBuf>,
}

fn main() {
    match parse_cli(env::args().skip(1).collect()) {
        Ok(cli) => {
            if let Err(err) = run(cli) {
                eprintln!("error: {err}");
                std::process::exit(1);
            }
        }
        Err(err) => {
            eprintln!("{err}");
            eprintln!("{}", usage());
            std::process::exit(2);
        }
    }
}

fn run(cli: Cli) -> Result<(), String> {
    Picture::validate_shape(cli.width, cli.height, cli.format)?;
    let data = fs::read(&cli.input)
        .map_err(|err| format!("failed to read input '{}': {err}", cli.input.display()))?;
    let expected = Picture::expected_len(cli.width, cli.height, cli.format);
    if data.len() < expected {
        return Err(format!(
            "input '{}' is too small for {}x{} {}: got {} bytes, need at least {}",
            cli.input.display(),
            cli.width,
            cli.height,
            cli.format,
            data.len(),
            expected
        ));
    }

    let picture = Picture::new(cli.width, cli.height, cli.format, data);
    let params = EncoderParams::new(cli.width, cli.height, cli.format);
    let mut encoder = PlaceholderEncoder::new(params);
    let result = encoder.encode_picture(&picture)?;

    fs::write(&cli.output, &result.bytes)
        .map_err(|err| format!("failed to write output '{}': {err}", cli.output.display()))?;

    if let Some(path) = cli.trace {
        let mut sink = TraceSink::create(&path)
            .map_err(|err| format!("failed to create trace '{}': {err}", path.display()))?;
        for event in &result.trace_events {
            sink.write(event)
                .map_err(|err| format!("failed to write trace '{}': {err}", path.display()))?;
        }
    }

    Ok(())
}

fn parse_cli(args: Vec<String>) -> Result<Cli, String> {
    let mut input = None;
    let mut width = None;
    let mut height = None;
    let mut format = None;
    let mut output = None;
    let mut trace = None;

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--input" => input = Some(next_value(&mut iter, "--input")?.into()),
            "--width" => width = Some(parse_usize(next_value(&mut iter, "--width")?, "--width")?),
            "--height" => height = Some(parse_usize(next_value(&mut iter, "--height")?, "--height")?),
            "--format" => {
                let value = next_value(&mut iter, "--format")?;
                format = Some(value.parse::<PixelFormat>()?);
            }
            "--output" => output = Some(next_value(&mut iter, "--output")?.into()),
            "--trace" => trace = Some(next_value(&mut iter, "--trace")?.into()),
            "--help" | "-h" => return Err(String::new()),
            other => return Err(format!("unknown argument '{other}'")),
        }
    }

    Ok(Cli {
        input: input.ok_or_else(|| "missing --input <path>".to_string())?,
        width: width.ok_or_else(|| "missing --width <w>".to_string())?,
        height: height.ok_or_else(|| "missing --height <h>".to_string())?,
        format: format.ok_or_else(|| "missing --format <format>".to_string())?,
        output: output.ok_or_else(|| "missing --output <path>".to_string())?,
        trace,
    })
}

fn next_value(iter: &mut impl Iterator<Item = String>, flag: &str) -> Result<String, String> {
    iter.next()
        .ok_or_else(|| format!("missing value for {flag}"))
}

fn parse_usize(value: String, flag: &str) -> Result<usize, String> {
    let parsed = value
        .parse::<usize>()
        .map_err(|_| format!("{flag} expects a positive integer, got '{value}'"))?;
    if parsed == 0 {
        return Err(format!("{flag} expects a positive integer, got 0"));
    }
    Ok(parsed)
}

fn usage() -> &'static str {
    "usage: frameforge --input <path> --width <w> --height <h> --format <format> --output <path> [--trace <path>]"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_cli_accepts_required_args() {
        let cli = parse_cli(vec![
            "--input".into(),
            "in.yuv".into(),
            "--width".into(),
            "64".into(),
            "--height".into(),
            "32".into(),
            "--format".into(),
            "gray8".into(),
            "--output".into(),
            "out.ffbs".into(),
        ])
        .unwrap();

        assert_eq!(cli.width, 64);
        assert_eq!(cli.height, 32);
        assert_eq!(cli.format, PixelFormat::Gray8);
        assert_eq!(cli.trace, None);
    }

    #[test]
    fn parse_cli_rejects_zero_width() {
        let err = parse_cli(vec![
            "--input".into(),
            "in.yuv".into(),
            "--width".into(),
            "0".into(),
            "--height".into(),
            "32".into(),
            "--format".into(),
            "gray8".into(),
            "--output".into(),
            "out.ffbs".into(),
        ])
        .unwrap_err();

        assert!(err.contains("--width"));
    }
}
