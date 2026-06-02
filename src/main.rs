use std::env;
use std::fs::{self, File};
use std::io::{BufReader, BufWriter, Write};
use std::path::PathBuf;

use frameforge::PixelFormat;

#[derive(Debug)]
enum Command {
    Eos(VvcEosCli),
    Encode(VvcEncodeCli),
    CabacVectorDump(VvcCabacVectorDumpCli),
    PaletteCabacDump(VvcPaletteCabacDumpCli),
    List(VvcListCli),
}

#[derive(Debug)]
struct VvcEosCli {
    output: PathBuf,
}

#[derive(Debug)]
struct VvcEncodeCli {
    input: PathBuf,
    output: PathBuf,
    recon: Option<PathBuf>,
    frames: usize,
    width: usize,
    height: usize,
    max_width: usize,
    max_height: usize,
    format: PixelFormat,
}

#[derive(Debug)]
struct VvcCabacVectorDumpCli {
    input: PathBuf,
    output: PathBuf,
    frames: usize,
    width: usize,
    height: usize,
    format: PixelFormat,
}

#[derive(Debug)]
struct VvcPaletteCabacDumpCli {
    input: PathBuf,
    output: PathBuf,
    width: usize,
    height: usize,
    format: PixelFormat,
}

#[derive(Debug)]
struct VvcListCli {
    input: PathBuf,
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

fn run(command: Command) -> Result<(), String> {
    match command {
        Command::Eos(cli) => run_vvc_eos(cli),
        Command::Encode(cli) => run_vvc_encode(cli),
        Command::CabacVectorDump(cli) => run_vvc_cabac_vector_dump(cli),
        Command::PaletteCabacDump(cli) => run_vvc_palette_cabac_dump(cli),
        Command::List(cli) => run_vvc_list(cli),
    }
}

fn run_vvc_eos(cli: VvcEosCli) -> Result<(), String> {
    let bytes = frameforge::vvc::eos_annex_b();
    fs::write(&cli.output, bytes)
        .map_err(|err| format!("failed to write output '{}': {err}", cli.output.display()))?;
    Ok(())
}

fn run_vvc_encode(cli: VvcEncodeCli) -> Result<(), String> {
    if !cli.format.is_yuv() {
        return Err(format!(
            "VVC encoder expects planar YUV input; got {}x{} {}",
            cli.width, cli.height, cli.format
        ));
    }

    let params = frameforge::vvc::VvcEncodeParams { frames: cli.frames };
    let geometry = frameforge::vvc::VvcVideoGeometry {
        width: cli.width,
        height: cli.height,
    };
    let limits = frameforge::vvc::VvcVideoLimits {
        max_width: cli.max_width,
        max_height: cli.max_height,
    };
    geometry.validate_against(limits)?;
    let input_file = File::open(&cli.input)
        .map_err(|err| format!("failed to open input '{}': {err}", cli.input.display()))?;
    let output_file = File::create(&cli.output)
        .map_err(|err| format!("failed to create output '{}': {err}", cli.output.display()))?;
    let mut input = BufReader::new(input_file);
    let mut output = BufWriter::new(output_file);
    let mut recon_output = if let Some(recon) = cli.recon.as_ref() {
        let file = File::create(recon).map_err(|err| {
            format!(
                "failed to create reconstruction '{}': {err}",
                recon.display()
            )
        })?;
        Some(BufWriter::new(file))
    } else {
        None
    };
    let recon_sink = recon_output.as_mut().map(|writer| writer as &mut dyn Write);
    frameforge::vvc::vvc_yuv_encode_stream_with_limits(
        &mut input,
        &mut output,
        recon_sink,
        params,
        geometry,
        limits,
        cli.format,
    )?;
    output
        .flush()
        .map_err(|err| format!("failed to flush output '{}': {err}", cli.output.display()))?;
    if let Some(writer) = recon_output.as_mut() {
        writer.flush().map_err(|err| {
            format!(
                "failed to flush reconstruction '{}': {err}",
                cli.recon
                    .as_ref()
                    .expect("reconstruction path exists")
                    .display()
            )
        })?;
    }
    Ok(())
}

fn run_vvc_cabac_vector_dump(cli: VvcCabacVectorDumpCli) -> Result<(), String> {
    let params = frameforge::vvc::VvcEncodeParams { frames: cli.frames };
    let geometry = frameforge::vvc::VvcVideoGeometry {
        width: cli.width,
        height: cli.height,
    };
    geometry.validate_against(frameforge::vvc::VvcVideoLimits::max_64x64())?;
    let data = fs::read(&cli.input)
        .map_err(|err| format!("failed to read input '{}': {err}", cli.input.display()))?;
    let json =
        frameforge::vvc::vvc_yuv420_cabac_vector_dump_json(&data, params, geometry, cli.format)?;
    fs::write(&cli.output, json)
        .map_err(|err| format!("failed to write output '{}': {err}", cli.output.display()))?;
    Ok(())
}

fn run_vvc_palette_cabac_dump(cli: VvcPaletteCabacDumpCli) -> Result<(), String> {
    let geometry = frameforge::vvc::VvcVideoGeometry {
        width: cli.width,
        height: cli.height,
    };
    geometry.validate_against(frameforge::vvc::VvcVideoLimits::max_64x64())?;
    let data = fs::read(&cli.input)
        .map_err(|err| format!("failed to read input '{}': {err}", cli.input.display()))?;
    let json = frameforge::vvc::vvc_palette_444_cabac_dump_json(&data, geometry, cli.format)?;
    fs::write(&cli.output, json)
        .map_err(|err| format!("failed to write output '{}': {err}", cli.output.display()))?;
    Ok(())
}

fn run_vvc_list(cli: VvcListCli) -> Result<(), String> {
    let bytes = fs::read(&cli.input)
        .map_err(|err| format!("failed to read bitstream '{}': {err}", cli.input.display()))?;
    for info in frameforge::vvc::parse_annex_b_nal_units(&bytes)? {
        println!(
            "offset={} nal_unit_type={} layer_id={} temporal_id={} payload_len={}",
            info.offset, info.nal_unit_type, info.layer_id, info.temporal_id, info.payload_len
        );
    }
    Ok(())
}

fn parse_cli(args: Vec<String>) -> Result<Command, String> {
    if args.first().map(String::as_str) == Some("vvc-eos") {
        return parse_vvc_eos_cli(args.into_iter().skip(1).collect());
    }
    if args.first().map(String::as_str) == Some("vvc-encode") {
        return parse_vvc_encode_cli(args.into_iter().skip(1).collect());
    }
    if args.first().map(String::as_str) == Some("vvc-cabac-vector-dump") {
        return parse_vvc_cabac_vector_dump_cli(args.into_iter().skip(1).collect());
    }
    if args.first().map(String::as_str) == Some("vvc-palette-cabac-dump") {
        return parse_vvc_palette_cabac_dump_cli(args.into_iter().skip(1).collect());
    }
    if args.first().map(String::as_str) == Some("vvc-list") {
        return parse_vvc_list_cli(args.into_iter().skip(1).collect());
    }
    Err("missing or unknown subcommand".to_string())
}

fn parse_vvc_eos_cli(args: Vec<String>) -> Result<Command, String> {
    let mut output = None;

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--output" => output = Some(next_value(&mut iter, "--output")?.into()),
            "--help" | "-h" => return Err(String::new()),
            other => return Err(format!("unknown vvc-eos argument '{other}'")),
        }
    }

    Ok(Command::Eos(VvcEosCli {
        output: output.ok_or_else(|| "missing --output <path>".to_string())?,
    }))
}

fn parse_vvc_encode_cli(args: Vec<String>) -> Result<Command, String> {
    let mut input = None;
    let mut output = None;
    let mut recon = None;
    let mut frames = 2;
    let mut width = 4;
    let mut height = 4;
    let mut max_width = usize::MAX;
    let mut max_height = usize::MAX;
    let mut format = PixelFormat::Yuv420p8;

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--input" => input = Some(next_value(&mut iter, "--input")?.into()),
            "--output" => output = Some(next_value(&mut iter, "--output")?.into()),
            "--recon" => recon = Some(next_value(&mut iter, "--recon")?.into()),
            "--frames" => frames = parse_usize(next_value(&mut iter, "--frames")?, "--frames")?,
            "--width" => width = parse_usize(next_value(&mut iter, "--width")?, "--width")?,
            "--height" => height = parse_usize(next_value(&mut iter, "--height")?, "--height")?,
            "--max-width" => {
                max_width = parse_usize(next_value(&mut iter, "--max-width")?, "--max-width")?
            }
            "--max-height" => {
                max_height = parse_usize(next_value(&mut iter, "--max-height")?, "--max-height")?
            }
            "--format" => {
                let value = next_value(&mut iter, "--format")?;
                format = value.parse::<PixelFormat>()?;
            }
            "--help" | "-h" => return Err(String::new()),
            other => return Err(format!("unknown vvc-encode argument '{other}'")),
        }
    }

    Ok(Command::Encode(VvcEncodeCli {
        input: input.ok_or_else(|| "missing --input <path>".to_string())?,
        output: output.ok_or_else(|| "missing --output <path>".to_string())?,
        recon,
        frames,
        width,
        height,
        max_width,
        max_height,
        format,
    }))
}

fn parse_vvc_cabac_vector_dump_cli(args: Vec<String>) -> Result<Command, String> {
    let mut input = None;
    let mut output = None;
    let mut frames = 1;
    let mut width = 8;
    let mut height = 8;
    let mut format = PixelFormat::Yuv420p8;

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--input" => input = Some(next_value(&mut iter, "--input")?.into()),
            "--output" => output = Some(next_value(&mut iter, "--output")?.into()),
            "--frames" => frames = parse_usize(next_value(&mut iter, "--frames")?, "--frames")?,
            "--width" => width = parse_usize(next_value(&mut iter, "--width")?, "--width")?,
            "--height" => height = parse_usize(next_value(&mut iter, "--height")?, "--height")?,
            "--format" => {
                let value = next_value(&mut iter, "--format")?;
                format = value.parse::<PixelFormat>()?;
            }
            "--help" | "-h" => return Err(String::new()),
            other => return Err(format!("unknown vvc-cabac-vector-dump argument '{other}'")),
        }
    }

    Ok(Command::CabacVectorDump(VvcCabacVectorDumpCli {
        input: input.ok_or_else(|| "missing --input <path>".to_string())?,
        output: output.ok_or_else(|| "missing --output <path>".to_string())?,
        frames,
        width,
        height,
        format,
    }))
}

fn parse_vvc_palette_cabac_dump_cli(args: Vec<String>) -> Result<Command, String> {
    let mut input = None;
    let mut output = None;
    let mut width = 64;
    let mut height = 64;
    let mut format = PixelFormat::Yuv444p8;

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--input" => input = Some(next_value(&mut iter, "--input")?.into()),
            "--output" => output = Some(next_value(&mut iter, "--output")?.into()),
            "--width" => width = parse_usize(next_value(&mut iter, "--width")?, "--width")?,
            "--height" => height = parse_usize(next_value(&mut iter, "--height")?, "--height")?,
            "--format" => {
                let value = next_value(&mut iter, "--format")?;
                format = value.parse::<PixelFormat>()?;
            }
            "--help" | "-h" => return Err(String::new()),
            other => return Err(format!("unknown vvc-palette-cabac-dump argument '{other}'")),
        }
    }

    Ok(Command::PaletteCabacDump(VvcPaletteCabacDumpCli {
        input: input.ok_or_else(|| "missing --input <path>".to_string())?,
        output: output.ok_or_else(|| "missing --output <path>".to_string())?,
        width,
        height,
        format,
    }))
}

fn parse_vvc_list_cli(args: Vec<String>) -> Result<Command, String> {
    let mut input = None;

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--input" => input = Some(next_value(&mut iter, "--input")?.into()),
            "--help" | "-h" => return Err(String::new()),
            other => return Err(format!("unknown vvc-list argument '{other}'")),
        }
    }

    Ok(Command::List(VvcListCli {
        input: input.ok_or_else(|| "missing --input <path>".to_string())?,
    }))
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
    "usage:\n  frameforge vvc-eos --output <vvc>\n  frameforge vvc-encode --input <yuv> --output <vvc> [--recon <yuv>] [--frames <n>] [--width <w> --height <h>] [--max-width <w> --max-height <h>] [--format yuv420p8|yuv422p8|yuv444p8|i420|i422|i444|i010|i210|i410|...]\n  frameforge vvc-cabac-vector-dump --input <yuv420> --output <json> [--frames 1 --width <w> --height <h> --format yuv420p8]\n  frameforge vvc-palette-cabac-dump --input <yuv444> --output <json> [--width <w> --height <h> --format yuv444p8]\n  frameforge vvc-list --input <vvc>"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_cli_rejects_unknown_subcommand() {
        let err = parse_cli(vec!["encode".into(), "--input".into(), "in.yuv".into()]).unwrap_err();

        assert!(err.contains("unknown subcommand"));
    }

    #[test]
    fn parse_cli_accepts_vvc_eos_subcommand() {
        let command =
            parse_cli(vec!["vvc-eos".into(), "--output".into(), "eos.vvc".into()]).unwrap();

        let Command::Eos(cli) = command else {
            panic!("expected vvc-eos command");
        };
        assert_eq!(cli.output, PathBuf::from("eos.vvc"));
    }

    #[test]
    fn parse_cli_accepts_vvc_encode_subcommand() {
        let command = parse_cli(vec![
            "vvc-encode".into(),
            "--input".into(),
            "input_16x16_2f_yuv420p8.yuv".into(),
            "--output".into(),
            "encoded.vvc".into(),
            "--frames".into(),
            "2".into(),
            "--width".into(),
            "4".into(),
            "--height".into(),
            "4".into(),
            "--max-width".into(),
            "64".into(),
            "--max-height".into(),
            "64".into(),
            "--format".into(),
            "yuv420p8".into(),
        ])
        .unwrap();

        let Command::Encode(cli) = command else {
            panic!("expected vvc-encode command");
        };
        assert_eq!(cli.input, PathBuf::from("input_16x16_2f_yuv420p8.yuv"));
        assert_eq!(cli.output, PathBuf::from("encoded.vvc"));
        assert_eq!(cli.frames, 2);
        assert_eq!(cli.width, 4);
        assert_eq!(cli.height, 4);
        assert_eq!(cli.max_width, 64);
        assert_eq!(cli.max_height, 64);
        assert_eq!(cli.format, PixelFormat::Yuv420p8);
    }

    #[test]
    fn parse_cli_accepts_vvc_list_subcommand() {
        let command = parse_cli(vec![
            "vvc-list".into(),
            "--input".into(),
            "reference.vvc".into(),
        ])
        .unwrap();

        let Command::List(cli) = command else {
            panic!("expected vvc-list command");
        };
        assert_eq!(cli.input, PathBuf::from("reference.vvc"));
    }
}
