#!/usr/bin/env python3
"""Generate deterministic YUV test vectors used by Makefile validation sets."""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass
from pathlib import Path


DEFAULT_OUT_DIR = Path("verification/generated/test_vectors")
GEOMETRY_STEPS = range(8, 65, 8)
PALETTE_COLORS_YUV = [
    (18, 128, 128),
    (46, 144, 112),
    (80, 104, 176),
    (120, 160, 96),
    (154, 92, 156),
    (196, 136, 136),
    (220, 96, 96),
    (236, 184, 96),
]


@dataclass(frozen=True)
class TestVector:
    name: str
    width: int
    height: int
    frames: int
    fmt: str
    pattern: str
    fps: int | None = None

    @property
    def filename(self) -> str:
        fps_part = f"_{self.fps}fps" if self.fps is not None else ""
        return f"{self.name}_{self.width}x{self.height}_{self.frames}f{fps_part}_{self.fmt}.yuv"


def vector_sets() -> dict[str, list[TestVector]]:
    sets = {
        "smoke": smoke_vectors(),
        "sweep-420": sweep_vectors("yuv420p8"),
        "sweep-444": sweep_vectors("yuv444p8"),
        "random-short": random_short_vectors(),
        "motion-short": motion_vectors(frames=3),
        "motion-long": motion_vectors(frames=300),
    }
    sets["all-short"] = unique_vectors(
        sets["smoke"] + sets["random-short"] + sets["motion-short"]
    )
    sets["all-sweeps"] = unique_vectors(sets["sweep-420"] + sets["sweep-444"])
    return sets


def smoke_vectors() -> list[TestVector]:
    return [
        TestVector("black", 8, 8, 1, "yuv420p8", "black"),
        TestVector("black", 16, 16, 2, "yuv420p8", "black"),
        TestVector("screen_blocks", 16, 16, 1, "yuv444p8", "screen_blocks"),
        TestVector("screen_blocks", 64, 64, 1, "yuv444p8", "screen_blocks"),
        *motion_vectors(frames=3),
    ]


def sweep_vectors(fmt: str) -> list[TestVector]:
    pattern = "black" if fmt == "yuv420p8" else "screen_blocks"
    return [
        TestVector(pattern, width, height, 1, fmt, pattern)
        for height in GEOMETRY_STEPS
        for width in GEOMETRY_STEPS
    ]


def random_short_vectors() -> list[TestVector]:
    rng = random.Random(0xF0F0_2026)
    vectors: list[TestVector] = []
    used: set[tuple[int, int, str]] = set()
    while len(vectors) < 10:
        width = rng.choice(list(GEOMETRY_STEPS))
        height = rng.choice(list(GEOMETRY_STEPS))
        fmt = "yuv420p8" if len(vectors) % 2 == 0 else "yuv444p8"
        key = (width, height, fmt)
        if key in used:
            continue
        used.add(key)
        frames = rng.randint(1, 5)
        pattern = "moving_blocks" if fmt == "yuv444p8" else "black"
        vectors.append(
            TestVector(
                f"random_short_{len(vectors):02d}",
                width,
                height,
                frames,
                fmt,
                pattern,
            )
        )
    return vectors


def motion_vectors(frames: int) -> list[TestVector]:
    return [
        TestVector("stick_walk", 64, 64, frames, "yuv420p8", "stick_walk", fps=30),
        TestVector("stick_walk", 64, 64, frames, "yuv444p8", "stick_walk", fps=30),
    ]


def unique_vectors(vectors: list[TestVector]) -> list[TestVector]:
    seen: set[str] = set()
    out: list[TestVector] = []
    for vector in vectors:
        if vector.filename in seen:
            continue
        seen.add(vector.filename)
        out.append(vector)
    return out


def generate_vectors(set_name: str, out_dir: Path) -> list[Path]:
    sets = vector_sets()
    if set_name not in sets:
        choices = ", ".join(sorted(sets))
        raise ValueError(f"unknown vector set '{set_name}'; choices: {choices}")

    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for vector in sets[set_name]:
        path = out_dir / vector.filename
        path.write_bytes(generate_yuv(vector))
        paths.append(path)
    return paths


def generate_yuv(vector: TestVector) -> bytes:
    if vector.fmt == "yuv420p8":
        return generate_yuv420p8(vector)
    if vector.fmt == "yuv444p8":
        return generate_yuv444p8(vector)
    raise ValueError(f"unsupported generated format: {vector.fmt}")


def generate_yuv420p8(vector: TestVector) -> bytes:
    out = bytearray()
    for frame in range(vector.frames):
        y_plane, u444, v444 = render_frame(vector, frame)
        u_plane = bytearray()
        v_plane = bytearray()
        for y in range(0, vector.height, 2):
            for x in range(0, vector.width, 2):
                u_sum = (
                    u444[pixel_index(vector, x, y)]
                    + u444[pixel_index(vector, x + 1, y)]
                    + u444[pixel_index(vector, x, y + 1)]
                    + u444[pixel_index(vector, x + 1, y + 1)]
                )
                v_sum = (
                    v444[pixel_index(vector, x, y)]
                    + v444[pixel_index(vector, x + 1, y)]
                    + v444[pixel_index(vector, x, y + 1)]
                    + v444[pixel_index(vector, x + 1, y + 1)]
                )
                u_plane.append(u_sum // 4)
                v_plane.append(v_sum // 4)
        out.extend(y_plane)
        out.extend(u_plane)
        out.extend(v_plane)
    return bytes(out)


def generate_yuv444p8(vector: TestVector) -> bytes:
    out = bytearray()
    for frame in range(vector.frames):
        y_plane, u_plane, v_plane = render_frame(vector, frame)
        out.extend(y_plane)
        out.extend(u_plane)
        out.extend(v_plane)
    return bytes(out)


def render_frame(vector: TestVector, frame: int) -> tuple[bytearray, bytearray, bytearray]:
    y_plane = bytearray(vector.width * vector.height)
    u_plane = bytearray(vector.width * vector.height)
    v_plane = bytearray(vector.width * vector.height)

    for y in range(vector.height):
        for x in range(vector.width):
            yy, uu, vv = sample_yuv(vector, x, y, frame)
            idx = pixel_index(vector, x, y)
            y_plane[idx] = yy
            u_plane[idx] = uu
            v_plane[idx] = vv

    return y_plane, u_plane, v_plane


def sample_yuv(vector: TestVector, x: int, y: int, frame: int) -> tuple[int, int, int]:
    if vector.pattern == "black":
        return 0, 0, 0
    if vector.pattern == "screen_blocks":
        return palette_tile_sample(x, y, frame)
    if vector.pattern == "moving_blocks":
        return moving_blocks_sample(vector, x, y, frame)
    if vector.pattern == "stick_walk":
        return stick_walk_sample(x, y, frame)
    raise ValueError(f"unsupported pattern: {vector.pattern}")


def palette_tile_sample(x: int, y: int, frame: int) -> tuple[int, int, int]:
    tile_x = x // 8
    tile_y = y // 8
    color_idx = (tile_x + (tile_y * 3) + frame) % len(PALETTE_COLORS_YUV)
    return PALETTE_COLORS_YUV[color_idx]


def moving_blocks_sample(vector: TestVector, x: int, y: int, frame: int) -> tuple[int, int, int]:
    yy, uu, vv = palette_tile_sample(x, y, frame)
    block_x = (frame * 8) % max(8, vector.width)
    block_y = (frame * 5) % max(8, vector.height)
    if block_x <= x < min(vector.width, block_x + 8) and block_y <= y < min(vector.height, block_y + 8):
        return 236, 184, 96
    return yy, uu, vv


def stick_walk_sample(x: int, y: int, frame: int) -> tuple[int, int, int]:
    phase = frame % 30
    body_x = 14 + ((frame * 2) % 36)
    bounce = 2 if phase < 15 else 0
    ground_y = 54
    head_y = 18 - bounce
    torso_top = 27 - bounce
    torso_bottom = 40 - bounce
    body_color = (232, 118, 72)
    accent = (72, 164, 218)
    ground = (42, 148, 78)
    sky = (20, 36, 68)

    if y >= ground_y:
        return ground
    if (x - body_x) * (x - body_x) + (y - head_y) * (y - head_y) <= 5 * 5:
        return body_color
    if abs(x - body_x) <= 2 and torso_top <= y <= torso_bottom:
        return body_color
    if torso_top + 2 <= y <= torso_top + 4 and abs(x - body_x) <= 9:
        return accent

    stride = -1 if phase < 15 else 1
    if abs((x - body_x) - stride * (y - torso_bottom)) <= 1 and torso_bottom <= y <= 50:
        return body_color
    if abs((x - body_x) + stride * (y - torso_bottom)) <= 1 and torso_bottom <= y <= 50:
        return body_color
    if y == 50 and abs(x - (body_x + (stride * 10))) <= 4:
        return body_color
    if y == 50 and abs(x - (body_x - (stride * 10))) <= 4:
        return body_color

    # Two moving square markers keep the sequence visibly changing while
    # preserving the current 4:4:4 palette subset's low per-CU color count.
    marker_x = (frame * 3) % 56
    marker_color = PALETTE_COLORS_YUV[(frame // 10) % len(PALETTE_COLORS_YUV)]
    if marker_x <= x < marker_x + 8 and 6 <= y < 14:
        return marker_color
    return sky


def pixel_index(vector: TestVector, x: int, y: int) -> int:
    return y * vector.width + x


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--set",
        default="smoke",
        choices=sorted(vector_sets()),
        help="named vector set to generate",
    )
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args()

    paths = generate_vectors(args.set, args.out_dir)
    print(f"Generated {len(paths)} test vector(s) in {args.out_dir}")
    for path in paths:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
