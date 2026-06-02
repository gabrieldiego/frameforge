#!/usr/bin/env python3
"""Run a configurable synthesis smoke flow for FrameForge RTL."""

from __future__ import annotations

import argparse
import os
import shlex
import shutil
import subprocess
from pathlib import Path


DEFAULT_BOARD = Path("synth/boards/arty-z7-10.env")
DEFAULT_DUT = "vvc-cabac-stream-writer"
DEFAULT_TOP = "ff_vvc_cabac_stream_writer"
LOCAL_LICENSE = Path(".tools/Xilinx.lic")
LOCAL_VIVADO_ROOT = Path(".tools/Xilinx/Vivado")
LOCAL_XILINX_ROOT = Path(".tools/Xilinx")
LOCAL_VIVADO_COMPAT_LIB = Path(".tools/vivado-compat/lib")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--board", type=Path, default=DEFAULT_BOARD)
    parser.add_argument("--dut", default=DEFAULT_DUT)
    parser.add_argument("--filelist", type=Path, default=None)
    parser.add_argument("--top", default=None)
    parser.add_argument("--out-dir", type=Path, default=Path("synth/out"))
    parser.add_argument("--clock-mhz", type=float, default=None)
    parser.add_argument("--tool", choices=("yosys", "vivado"), default="yosys")
    parser.add_argument("--post-synth-smoke", action="store_true")
    args = parser.parse_args()

    board = load_env_file(args.board)
    sources = read_filelist(args.filelist) if args.filelist else tb_verilog_sources(args.dut)
    top = args.top or tb_toplevel(args.dut)
    out_dir = args.out_dir / board.get("BOARD_NAME", "board") / top
    out_dir.mkdir(parents=True, exist_ok=True)
    clock_mhz = args.clock_mhz or float(board.get("DEFAULT_CLOCK_MHZ", "50"))

    if args.tool == "vivado":
        return run_vivado(board, top, sources, out_dir, clock_mhz)

    rc = run_yosys(board, top, sources, out_dir, clock_mhz)
    if rc != 0 or not args.post_synth_smoke:
        return rc
    return run_post_synth_smoke(top, out_dir)


def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, sep, value = stripped.partition("=")
        if not sep:
            continue
        values[key.strip()] = os.environ.get(key.strip(), value.strip())
    return values


def read_filelist(path: Path) -> list[Path]:
    sources: list[Path] = []
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        sources.append(Path(stripped))
    return sources


def tb_make_value(dut: str, target: str) -> str:
    completed = subprocess.run(
        ["make", "-C", "tb", f"DUT={dut}", target],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    lines = [
        line.strip()
        for line in completed.stdout.splitlines()
        if line.strip() and "Entering directory" not in line and "Leaving directory" not in line
    ]
    if not lines:
        raise SystemExit(f"tb Makefile did not report {target} for DUT={dut}")
    return "\n".join(lines)


def tb_verilog_sources(dut: str) -> list[Path]:
    return [
        (Path("tb") / line).resolve()
        for line in tb_make_value(dut, "print-verilog-sources").splitlines()
    ]


def tb_toplevel(dut: str) -> str:
    return tb_make_value(dut, "print-toplevel").splitlines()[-1]


def find_tool(name: str) -> str:
    local = Path(".tools/oss-cad-suite/bin") / name
    if local.exists():
        return str(local)
    found = shutil.which(name)
    if found:
        return found
    raise SystemExit(
        f"{name} was not found. Run `make synth-env` or set PATH/SYNTH_{name.upper()}."
    )


def find_local_vivado_settings() -> Path | None:
    env_setting = os.environ.get("VIVADO_SETTINGS") or os.environ.get("SYNTH_VIVADO_SETTINGS")
    if env_setting:
        candidate = Path(env_setting)
        if candidate.exists():
            return candidate
        raise SystemExit(f"Configured Vivado settings script does not exist: {candidate}")

    candidates = sorted(LOCAL_VIVADO_ROOT.glob("*/settings64.sh"), reverse=True)
    return candidates[0] if candidates else None


def find_project_vivado_settings() -> Path | None:
    candidates = [
        *sorted(LOCAL_VIVADO_ROOT.glob("*/settings64.sh"), reverse=True),
        *sorted(LOCAL_XILINX_ROOT.glob("*/Vivado/settings64.sh"), reverse=True),
    ]
    return candidates[0] if candidates else None


def find_vivado_command() -> list[str]:
    explicit = os.environ.get("SYNTH_VIVADO") or os.environ.get("VIVADO")
    if explicit:
        return [explicit]

    found = shutil.which("vivado")
    if found:
        return [found]

    local_bins = [
        *sorted(LOCAL_VIVADO_ROOT.glob("*/bin/vivado"), reverse=True),
        *sorted(LOCAL_XILINX_ROOT.glob("*/Vivado/bin/vivado"), reverse=True),
    ]
    if local_bins:
        return [str(local_bins[0])]

    settings = find_project_vivado_settings()
    if settings:
        return ["bash", "-lc", f"source {shlex.quote(str(settings))} >/dev/null && exec vivado \"$@\"", "vivado"]

    raise SystemExit(
        "vivado was not found. Install Vivado under .tools/Xilinx, set VIVADO_SETTINGS, "
        "set SYNTH_VIVADO, or place vivado on PATH."
    )


def vivado_environment() -> dict[str, str]:
    env = os.environ.copy()
    if "XILINXD_LICENSE_FILE" not in env and LOCAL_LICENSE.exists():
        env["XILINXD_LICENSE_FILE"] = str(LOCAL_LICENSE.resolve())
    compat_lib = ensure_vivado_compat_libs()
    if compat_lib:
        existing = env.get("LD_LIBRARY_PATH")
        env["LD_LIBRARY_PATH"] = (
            str(compat_lib.resolve()) if not existing else f"{compat_lib.resolve()}:{existing}"
        )
    return env


def ensure_vivado_compat_libs() -> Path | None:
    """Create project-local compatibility symlinks for newer Ubuntu releases.

    AMD's 2025.2 launcher still loads libncurses.so.5 on some paths. Recent
    Ubuntu installs may only ship ncurses 6, so keep the workaround local to the
    project instead of writing symlinks into /usr/lib.
    """
    system_lib = Path("/usr/lib/x86_64-linux-gnu")
    ncurses6 = system_lib / "libncurses.so.6"
    tinfo6 = system_lib / "libtinfo.so.6"
    if not ncurses6.exists():
        return LOCAL_VIVADO_COMPAT_LIB if LOCAL_VIVADO_COMPAT_LIB.exists() else None

    LOCAL_VIVADO_COMPAT_LIB.mkdir(parents=True, exist_ok=True)
    ncurses5 = LOCAL_VIVADO_COMPAT_LIB / "libncurses.so.5"
    if not ncurses5.exists():
        ncurses5.symlink_to(ncurses6)
    if tinfo6.exists():
        tinfo5 = LOCAL_VIVADO_COMPAT_LIB / "libtinfo.so.5"
        if not tinfo5.exists():
            tinfo5.symlink_to(tinfo6)
    return LOCAL_VIVADO_COMPAT_LIB


def run_yosys(
    board: dict[str, str],
    top: str,
    sources: list[Path],
    out_dir: Path,
    clock_mhz: float,
) -> int:
    yosys = os.environ.get("SYNTH_YOSYS") or find_tool("yosys")
    family = board.get("FPGA_FAMILY", "xc7")
    script = out_dir / "synth_xilinx.ys"
    post_synth = out_dir / f"{top}.post_synth.v"
    json_netlist = out_dir / f"{top}.json"
    log = out_dir / "yosys.log"

    script.write_text(
        "\n".join(
            [
                "# Generated by scripts/run_synth.py",
                *[f"read_verilog -sv {quote_path(source)}" for source in sources],
                f"hierarchy -check -top {top}",
                "proc",
                "opt",
                "fsm",
                "opt",
                "memory",
                "opt",
                f"synth_xilinx -family {family} -top {top}",
                "stat -tech xilinx",
                f"write_json {quote_path(json_netlist)}",
                f"write_verilog -noattr {quote_path(post_synth)}",
                "",
            ]
        )
    )

    print(f"Synthesizing {top} for {board.get('BOARD_NAME')} ({board.get('FPGA_PART')})")
    print(f"Clock target metadata: {clock_mhz:g} MHz")
    print(f"Yosys script: {script}")
    with log.open("w") as log_file:
        completed = subprocess.run([yosys, "-s", str(script)], text=True, stdout=log_file, stderr=subprocess.STDOUT)
    print(f"Yosys log: {log}")
    print(f"Post-synth netlist: {post_synth}")
    if completed.returncode != 0:
        return completed.returncode
    return run_yosys_critical_path_report(yosys, top, sources, out_dir)


def run_yosys_critical_path_report(
    yosys: str,
    top: str,
    sources: list[Path],
    out_dir: Path,
) -> int:
    script = out_dir / "critical_path.ys"
    log = out_dir / "critical_path.log"

    script.write_text(
        "\n".join(
            [
                "# Generated by scripts/run_synth.py",
                "# Coarse pre-mapping longest-path check. Use Vivado timing for device-accurate closure.",
                *[f"read_verilog -sv {quote_path(source)}" for source in sources],
                f"hierarchy -check -top {top}",
                "proc",
                "opt",
                "fsm",
                "opt",
                "memory",
                "opt",
                "flatten",
                "opt",
                "ltp -noff",
                "",
            ]
        )
    )

    print(f"Critical path script: {script}")
    with log.open("w") as log_file:
        completed = subprocess.run([yosys, "-s", str(script)], text=True, stdout=log_file, stderr=subprocess.STDOUT)
    print(f"Critical path log: {log}")
    if completed.returncode == 0:
        print_critical_path_summary(log)
    return completed.returncode


def print_critical_path_summary(log: Path) -> None:
    lines = log.read_text(errors="replace").splitlines()
    for index, line in enumerate(lines):
        if "Longest topological path" in line:
            path = "\n".join(lines[index : min(index + 8, len(lines))])
            print(path)
            return
    print("Critical path summary was not found in the Yosys log.")


def run_vivado(
    board: dict[str, str],
    top: str,
    sources: list[Path],
    out_dir: Path,
    clock_mhz: float,
) -> int:
    vivado_cmd = find_vivado_command()

    tcl = out_dir / "vivado_synth.tcl"
    period_ns = 1000.0 / clock_mhz
    part = board.get("FPGA_PART", "xc7z010clg400-1")
    tcl.write_text(
        "\n".join(
            [
                f"set part {part}",
                f"set top {top}",
                f"set out_dir {out_dir}",
                "create_project -in_memory -part $part",
                *[f"read_verilog -sv {quote_tcl_path(source)}" for source in sources],
                "set_property top $top [current_fileset]",
                "synth_design -top $top -part $part",
                f"create_clock -name ff_synth_clk -period {period_ns:.3f} [get_ports clk]",
                "report_utilization -file $out_dir/vivado_utilization.rpt",
                "report_timing_summary -file $out_dir/vivado_timing_summary.rpt",
                "report_timing -max_paths 20 -sort_by group -file $out_dir/vivado_critical_paths.rpt",
                "write_verilog -force $out_dir/${top}.vivado_post_synth.v",
                "exit",
                "",
            ]
        )
    )
    log = out_dir / "vivado.log"
    journal = out_dir / "vivado.jou"
    print(f"Running Vivado synthesis for {top} on {part}")
    if "XILINXD_LICENSE_FILE" not in os.environ and LOCAL_LICENSE.exists():
        print(f"Using project-local Vivado license: {LOCAL_LICENSE}")
    settings = find_project_vivado_settings()
    if settings:
        print(f"Detected project-local Vivado settings: {settings}")
    with log.open("w") as log_file:
        completed = subprocess.run(
            [
                *vivado_cmd,
                "-mode",
                "batch",
                "-source",
                str(tcl),
                "-log",
                str(log),
                "-journal",
                str(journal),
            ],
            env=vivado_environment(),
            text=True,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
    print(f"Vivado log: {log}")
    return completed.returncode


def run_post_synth_smoke(top: str, out_dir: Path) -> int:
    if top != DEFAULT_TOP:
        print(f"Post-synth smoke is only wired for {DEFAULT_TOP}; skipping {top}.")
        return 0

    iverilog = os.environ.get("SYNTH_IVERILOG") or find_tool("iverilog")
    vvp = os.environ.get("SYNTH_VVP") or find_tool("vvp")
    yosys_config = os.environ.get("SYNTH_YOSYS_CONFIG") or find_tool("yosys-config")
    datdir = subprocess.check_output([yosys_config, "--datdir"], text=True).strip()
    cells_sim = Path(datdir) / "xilinx" / "cells_sim.v"
    netlist = out_dir / f"{top}.post_synth.v"
    tb = out_dir / "post_synth_smoke_tb.v"
    sim = out_dir / "post_synth_smoke.vvp"

    tb.write_text(
        """
`timescale 1ns/1ps
module post_synth_smoke_tb;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg start = 1'b0;
  reg clear = 1'b0;
  reg s_axis_valid = 1'b0;
  reg [2:0] s_axis_kind = 3'd0;
  reg s_axis_bin = 1'b0;
  reg s_axis_ctx_valid = 1'b0;
  reg [4:0] s_axis_ctx_id = 5'd0;
  reg [8:0] s_axis_lps = 9'd4;
  reg s_axis_mps = 1'b0;
  reg s_axis_last = 1'b0;
  wire s_axis_ready;
  reg m_axis_ready = 1'b1;
  wire m_axis_valid;
  wire [7:0] m_axis_data;
  wire m_axis_last;
  wire [2:0] stream_last_byte_bits;
  wire done;
  integer cycles = 0;

  always #5 clk = ~clk;

  ff_vvc_cabac_stream_writer dut (
    .clk(clk), .rst_n(rst_n), .start(start), .clear(clear),
    .s_axis_valid(s_axis_valid), .s_axis_ready(s_axis_ready),
    .s_axis_kind(s_axis_kind), .s_axis_bin(s_axis_bin),
    .s_axis_bins_pattern({31'd0, s_axis_bin}), .s_axis_bins_count(6'd1),
    .s_axis_ctx_valid(s_axis_ctx_valid), .s_axis_ctx_id(s_axis_ctx_id),
    .s_axis_lps(s_axis_lps), .s_axis_mps(s_axis_mps),
    .s_axis_last(s_axis_last),
    .m_axis_ready(m_axis_ready), .m_axis_valid(m_axis_valid),
    .m_axis_data(m_axis_data), .m_axis_last(m_axis_last),
    .stream_last_byte_bits(stream_last_byte_bits), .done(done)
  );

  task send_bin(input [2:0] kind, input bit bin, input bit last);
    begin
      s_axis_kind <= kind;
      s_axis_bin <= bin;
      s_axis_last <= last;
      s_axis_valid <= 1'b1;
      do begin
        @(posedge clk);
      end while (!s_axis_ready);
      s_axis_valid <= 1'b0;
      s_axis_last <= 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;
    send_bin(3'd0, 1'b0, 1'b0);
    send_bin(3'd0, 1'b1, 1'b0);
    send_bin(3'd0, 1'b0, 1'b0);
    send_bin(3'd1, 1'b1, 1'b1);
    while (!done && cycles < 512) begin
      cycles = cycles + 1;
      @(posedge clk);
    end
    if (!done) begin
      $display("FAIL: post-synth smoke timed out");
      $finish(1);
    end
    $display("PASS: post-synth smoke completed in %0d cycles", cycles);
    $finish(0);
  end
endmodule
"""
    )
    cmd = [iverilog, "-g2012", "-o", str(sim), str(cells_sim), str(netlist), str(tb)]
    print("Compiling post-synth smoke simulation")
    subprocess.run(cmd, check=True)
    print("Running post-synth smoke simulation")
    return subprocess.run([vvp, str(sim)], check=False).returncode


def quote_path(path: Path) -> str:
    return shlex.quote(str(path))


def quote_tcl_path(path: Path) -> str:
    return "{" + str(path) + "}"


if __name__ == "__main__":
    raise SystemExit(main())
