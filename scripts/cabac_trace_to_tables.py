#!/usr/bin/env python3
"""Convert VTM D_CABAC traces into FrameForge trace table snippets.

The tool intentionally emits syntax-neutral names. The generated snippets are
review aids for bringing a VTM-observed coding-tree path into the clean-room
software and RTL encoders; they are not a substitute for naming each syntax
decision once the path is understood.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


CTX_RE = re.compile(r"\[(?P<range>\d+):(?P<lps>\d+)\].*MPS=(?P<mps>[01]).*-\s*(?P<bin>[01])\s*$")
EP_RE = re.compile(r"\bEP=(?P<bin>[01])\b")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="VTM trace file produced with --TraceRule='D_CABAC:poc>=0'")
    parser.add_argument(
        "--format",
        choices=("rust", "systemverilog", "summary"),
        default="summary",
        help="snippet format to print",
    )
    parser.add_argument(
        "--name",
        default="trace32",
        help="base name used in generated comments",
    )
    args = parser.parse_args()

    bins = parse_trace(args.trace)
    if args.format == "summary":
        ctx = sum(1 for item in bins if item[0] == "ctx")
        ep = len(bins) - ctx
        print(f"{args.trace}: bins={len(bins)} ctx={ctx} ep={ep}")
    elif args.format == "rust":
        emit_rust(args.name, bins)
    else:
        emit_systemverilog(args.name, bins)
    return 0


def parse_trace(path: Path) -> list[tuple[str, int, int | None, int | None]]:
    out: list[tuple[str, int, int | None, int | None]] = []
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        if match := EP_RE.search(line):
            out.append(("ep", int(match.group("bin")), None, None))
            continue
        if match := CTX_RE.search(line):
            out.append(
                (
                    "ctx",
                    int(match.group("lps")),
                    int(match.group("mps")),
                    int(match.group("bin")),
                )
            )
            continue
        if line.strip():
            raise SystemExit(f"{path}:{line_no}: unsupported D_CABAC trace line: {line}")
    return out


def emit_rust(name: str, bins: list[tuple[str, int, int | None, int | None]]) -> None:
    print(f"// Generated from {name}; replace generic names as syntax decisions are identified.")
    for idx, item in enumerate(bins):
        if item[0] == "ep":
            print(f'    trace_ep("{name} ep[{idx}]", {rust_bool(item[1])}),')
        else:
            _, lps, mps, bin_value = item
            print(
                f'    trace_ctx("{name} ctx[{idx}]", {lps}, '
                f"{rust_bool(mps)}, {rust_bool(bin_value)}),"
            )


def emit_systemverilog(name: str, bins: list[tuple[str, int, int | None, int | None]]) -> None:
    print(f"// Generated from {name}; replace generic comments as syntax decisions are identified.")
    for idx, item in enumerate(bins):
        if item[0] == "ep":
            print(f"st = cabac_encode_bin_ep(st, 1'b{item[1]}); // {name} ep[{idx}]")
        else:
            _, lps, mps, bin_value = item
            print(
                f"st = cabac_encode_bin(st, 1'b{bin_value}, 9'd{lps}, "
                f"1'b{mps}); // {name} ctx[{idx}]"
            )


def rust_bool(value: int | None) -> str:
    if value is None:
        raise AssertionError("missing bool")
    return "true" if value else "false"


if __name__ == "__main__":
    raise SystemExit(main())
