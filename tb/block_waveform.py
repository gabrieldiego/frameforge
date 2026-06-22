"""Shared block-throughput waveform instrumentation for cocotb tests."""

from __future__ import annotations

import json
import time
from pathlib import Path


STATE_IDLE = 0
STATE_WAITING = 1
STATE_WORKING = 2
STATE_BACKPRESSURE = 3

STATE_INFO = {
    STATE_IDLE: {
        "name": "idle",
        "color": "#808080",
        "description": "No main input transfer and no main output activity.",
    },
    STATE_WAITING: {
        "name": "waiting",
        "color": "#2f80ed",
        "description": "Input side is ready, but the feeding block has no valid payload.",
    },
    STATE_WORKING: {
        "name": "working",
        "color": "#27ae60",
        "description": "Main input or output side transfers payload this cycle.",
    },
    STATE_BACKPRESSURE: {
        "name": "backpressure",
        "color": "#eb5757",
        "description": "Main output has valid payload, but the following block is not ready.",
    },
}


def as_bool(value) -> bool:
    if value is None:
        return False
    return bool(int(value))


def block_state(input_valid, input_ready, output_valid, output_ready) -> int:
    """Classify one cycle from the main input/output handshakes."""

    in_valid = as_bool(input_valid)
    in_ready = as_bool(input_ready)
    out_valid = as_bool(output_valid)
    out_ready = as_bool(output_ready)
    input_fire = in_valid and in_ready
    output_fire = out_valid and out_ready

    if out_valid and not out_ready:
        return STATE_BACKPRESSURE
    if input_fire or output_fire:
        return STATE_WORKING
    if in_ready and not in_valid:
        return STATE_WAITING
    return STATE_IDLE


class BlockWaveformWriter:
    """Write a compact VCD and companion colored throughput reports."""

    def __init__(self, vcd_path, block_names, summary_path=None):
        self.enabled = bool(vcd_path)
        self.block_names = list(block_names)
        self.summary_path = Path(summary_path) if summary_path else None
        self.total_cycles = 0
        self.counts = {
            name: {info["name"]: 0 for info in STATE_INFO.values()}
            for name in self.block_names
        }
        self.runs = {name: [] for name in self.block_names}
        self._last_state = {name: None for name in self.block_names}
        self._last_change_cycle = {name: 0 for name in self.block_names}
        self._last_values = {}
        self._ids = {}
        self._handle = None
        if not self.enabled:
            return
        self.vcd_path = Path(vcd_path)
        self.vcd_path.parent.mkdir(parents=True, exist_ok=True)
        self._open_vcd()

    def _open_vcd(self):
        self._handle = self.vcd_path.open("w", encoding="utf-8")
        self._handle.write(f"$date {time.strftime('%Y-%m-%d %H:%M:%S')} $end\n")
        self._handle.write("$version FrameForge block waveform instrumentation $end\n")
        self._handle.write("$timescale 1ns $end\n")
        self._handle.write("$scope module frameforge_blocks $end\n")
        index = 0
        for block in self.block_names:
            state_id = self._vcd_id(index)
            index += 1
            self._ids[(block, "state")] = state_id
            self._handle.write(f"$var wire 2 {state_id} {block}_state $end\n")
            for state, info in STATE_INFO.items():
                signal = info["name"]
                signal_id = self._vcd_id(index)
                index += 1
                self._ids[(block, signal)] = signal_id
                color_name = info["color"].lstrip("#")
                self._handle.write(
                    f"$var wire 1 {signal_id} {block}_{signal}_{color_name} $end\n"
                )
        self._handle.write("$upscope $end\n")
        self._handle.write("$enddefinitions $end\n")

    @staticmethod
    def _vcd_id(index: int) -> str:
        chars = []
        while True:
            chars.append(chr(33 + (index % 94)))
            index = index // 94
            if index == 0:
                return "".join(chars)

    def sample(self, cycle: int, states: dict[str, int]):
        if not self.enabled:
            return
        self.total_cycles = max(self.total_cycles, cycle + 1)
        changes = []
        for block in self.block_names:
            state = int(states.get(block, STATE_IDLE))
            state_name = STATE_INFO[state]["name"]
            self.counts[block][state_name] += 1
            self._update_run(block, state, cycle)
            values = [(self._ids[(block, "state")], f"b{state:02b}")]
            for candidate, info in STATE_INFO.items():
                values.append(
                    (
                        self._ids[(block, info["name"])],
                        "1" if state == candidate else "0",
                    )
                )
            for signal_id, value in values:
                if self._last_values.get(signal_id) == value:
                    continue
                self._last_values[signal_id] = value
                if value.startswith("b"):
                    changes.append(f"{value} {signal_id}\n")
                else:
                    changes.append(f"{value}{signal_id}\n")
        if changes:
            self._handle.write(f"#{cycle}\n")
            self._handle.writelines(changes)

    def _update_run(self, block: str, state: int, cycle: int):
        last = self._last_state[block]
        if last is None:
            self._last_state[block] = state
            self._last_change_cycle[block] = cycle
            return
        if last == state:
            return
        start = self._last_change_cycle[block]
        self.runs[block].append(
            {
                "start": start,
                "cycles": cycle - start,
                "state": STATE_INFO[last]["name"],
                "color": STATE_INFO[last]["color"],
            }
        )
        self._last_state[block] = state
        self._last_change_cycle[block] = cycle

    def close(self):
        if not self.enabled:
            return
        for block in self.block_names:
            state = self._last_state[block]
            if state is None:
                continue
            start = self._last_change_cycle[block]
            self.runs[block].append(
                {
                    "start": start,
                    "cycles": max(0, self.total_cycles - start),
                    "state": STATE_INFO[state]["name"],
                    "color": STATE_INFO[state]["color"],
                }
            )
        if self._handle is not None:
            self._handle.close()
            self._handle = None
        if self.summary_path is None:
            self.summary_path = self.vcd_path.with_suffix(".json")
        self.summary_path.parent.mkdir(parents=True, exist_ok=True)
        summary = self._summary()
        self.summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
        self._write_legend(summary)
        self._write_gtkw()
        self._write_html(summary)

    def _summary(self):
        blocks = {}
        for block in self.block_names:
            counts = self.counts[block]
            blocks[block] = {
                "counts": counts,
                "rates": {
                    state: (count / self.total_cycles if self.total_cycles else 0.0)
                    for state, count in counts.items()
                },
                "runs": self.runs[block],
            }
        return {
            "vcd": str(self.vcd_path),
            "gtkw": str(self.vcd_path.with_suffix(".gtkw")),
            "html": str(self.vcd_path.with_suffix(".html")),
            "total_cycles": self.total_cycles,
            "state_encoding": {
                str(code): info for code, info in STATE_INFO.items()
            },
            "blocks": blocks,
        }

    def _write_legend(self, summary):
        legend_path = self.vcd_path.with_suffix(".legend.json")
        legend = {
            "note": "VCD does not carry viewer colors; use this legend or the HTML report.",
            "states": summary["state_encoding"],
        }
        legend_path.write_text(json.dumps(legend, indent=2, sort_keys=True) + "\n")

    def _write_gtkw(self):
        gtkw_path = self.vcd_path.with_suffix(".gtkw")
        lines = [
            "[*] FrameForge block throughput waveform\n",
            f"[dumpfile] \"{self.vcd_path}\"\n",
            "[timestart] 0\n",
            "[size] 1600 900\n",
            "[treeopen] frameforge_blocks.\n",
            "@28\n",
        ]
        for block in self.block_names:
            lines.append(f"frameforge_blocks.{block}_state[1:0]\n")
        lines.append("@22\n")
        for block in self.block_names:
            for info in STATE_INFO.values():
                color_name = info["color"].lstrip("#")
                lines.append(
                    f"frameforge_blocks.{block}_{info['name']}_{color_name}\n"
                )
        gtkw_path.write_text("".join(lines))

    def _write_html(self, summary):
        html_path = self.vcd_path.with_suffix(".html")
        state_legend = "\n".join(
            (
                f'<span class="legend-item"><span class="swatch" '
                f'style="background:{info["color"]}"></span>{info["name"]}</span>'
            )
            for info in STATE_INFO.values()
        )
        rows = []
        total = max(1, self.total_cycles)
        for block in self.block_names:
            segments = []
            for run in self.runs[block]:
                width = max(0.02, (run["cycles"] / total) * 100.0)
                title = (
                    f'{block}: {run["state"]} '
                    f'cycles {run["start"]}..{run["start"] + run["cycles"] - 1}'
                )
                segments.append(
                    f'<span class="segment" title="{title}" '
                    f'style="width:{width:.6f}%;background:{run["color"]}"></span>'
                )
            rates = summary["blocks"][block]["rates"]
            rows.append(
                '<div class="row">'
                f'<div class="name">{block}</div>'
                f'<div class="bar">{"".join(segments)}</div>'
                '<div class="rates">'
                f'idle {rates["idle"]:.3f} '
                f'wait {rates["waiting"]:.3f} '
                f'work {rates["working"]:.3f} '
                f'back {rates["backpressure"]:.3f}'
                "</div></div>"
            )
        html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>FrameForge Block Throughput</title>
  <style>
    body {{ font: 13px sans-serif; margin: 24px; color: #1f2933; }}
    .legend {{ margin: 12px 0 20px; }}
    .legend-item {{ margin-right: 18px; white-space: nowrap; }}
    .swatch {{ display: inline-block; width: 12px; height: 12px; margin-right: 5px; vertical-align: -1px; }}
    .row {{ display: grid; grid-template-columns: 220px minmax(360px, 1fr) 300px; gap: 12px; align-items: center; margin: 8px 0; }}
    .name {{ font-family: monospace; }}
    .bar {{ display: flex; height: 18px; background: #eef2f5; overflow: hidden; border: 1px solid #c9d2da; }}
    .segment {{ display: block; min-width: 1px; height: 100%; }}
    .rates {{ font-family: monospace; font-size: 12px; color: #435261; }}
  </style>
</head>
<body>
  <h1>FrameForge Block Throughput</h1>
  <p>Total cycles: {self.total_cycles}</p>
  <div class="legend">{state_legend}</div>
  {"".join(rows)}
</body>
</html>
"""
        html_path.write_text(html)
