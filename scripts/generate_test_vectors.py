#!/usr/bin/env python3
"""Generate deterministic YUV test vectors from manifest files."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - exercised only by PNG-backed local manifests.
    Image = None


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = Path("verification/generated/test_vectors")
DEFAULT_SET_DIR = REPO_ROOT / "verification" / "test_vector_sets"
LOCAL_SET_DIR = "local"
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
class TestVectorSource:
    id: str
    path: Path
    width: int
    height: int
    fmt: str


@dataclass(frozen=True)
class TestVector:
    name: str
    width: int
    height: int
    frames: int
    fmt: str
    pattern: str
    fps: int | None = None
    source: str | None = None
    crop_x: int | None = None
    crop_y: int | None = None

    @property
    def filename(self) -> str:
        fps_part = f"_{self.fps}fps" if self.fps is not None else ""
        return f"{self.name}_{self.width}x{self.height}_{self.frames}f{fps_part}_{self.fmt}.yuv"


@dataclass(frozen=True)
class TestVectorSet:
    name: str
    manifest: Path
    generator: str
    description: str
    vectors: list[TestVector]
    sources: dict[str, TestVectorSource]


def vector_sets(set_dir: Path = DEFAULT_SET_DIR) -> dict[str, TestVectorSet]:
    sets: dict[str, TestVectorSet] = {}
    for path in vector_set_paths(set_dir):
        loaded = load_vector_set(path)
        sets[loaded.name] = loaded
    return sets


def vector_set_paths(set_dir: Path) -> list[Path]:
    paths = sorted(set_dir.glob("*.csv")) if set_dir.exists() else []
    local_dir = set_dir / LOCAL_SET_DIR
    if local_dir.exists():
        paths.extend(sorted(local_dir.glob("*.csv")))
    return paths


def load_vector_set(path: Path) -> TestVectorSet:
    generator = "scripts/generate_test_vectors.py"
    description = ""
    sources: dict[str, TestVectorSource] = {}
    rows: list[str] = []

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("#"):
            body = line[1:].strip()
            if body.startswith("generator="):
                generator = body.removeprefix("generator=").strip()
            elif body.startswith("description="):
                description = body.removeprefix("description=").strip()
            elif body.startswith("source="):
                source = parse_source(body.removeprefix("source="))
                sources[source.id] = source
            continue
        rows.append(raw_line)

    if not rows:
        raise ValueError(f"test vector manifest has no CSV rows: {path}")

    reader = csv.DictReader(rows)
    vectors = [parse_vector(row, path) for row in reader]
    if not vectors:
        raise ValueError(f"test vector manifest has no vectors: {path}")

    return TestVectorSet(
        name=path.stem,
        manifest=path,
        generator=generator,
        description=description,
        vectors=vectors,
        sources=sources,
    )


def parse_source(value: str) -> TestVectorSource:
    fields = parse_key_value_fields(value)
    return TestVectorSource(
        id=required_field(fields, "id", "source"),
        path=Path(required_field(fields, "path", "source")),
        width=parse_positive_int(required_field(fields, "width", "source"), "source width"),
        height=parse_positive_int(required_field(fields, "height", "source"), "source height"),
        fmt=required_field(fields, "format", "source"),
    )


def parse_key_value_fields(value: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for field in next(csv.reader([value], skipinitialspace=True)):
        key, sep, item = field.partition("=")
        if not sep:
            raise ValueError(f"expected key=value source field, got '{field}'")
        out[key.strip()] = item.strip()
    return out


def parse_vector(row: dict[str, str], path: Path) -> TestVector:
    context = f"{path}:{row.get('name', '').strip() or '<unnamed>'}"
    return TestVector(
        name=required_field(row, "name", context),
        width=parse_positive_int(required_field(row, "width", context), "width"),
        height=parse_positive_int(required_field(row, "height", context), "height"),
        frames=parse_positive_int(required_field(row, "frames", context), "frames"),
        fmt=required_field(row, "format", context),
        pattern=required_field(row, "pattern", context),
        fps=parse_optional_int(row.get("fps", ""), "fps"),
        source=optional_field(row.get("source", "")),
        crop_x=parse_optional_int(row.get("crop_x", ""), "crop_x"),
        crop_y=parse_optional_int(row.get("crop_y", ""), "crop_y"),
    )


def required_field(row: dict[str, str], key: str, context: str) -> str:
    value = row.get(key, "").strip()
    if not value:
        raise ValueError(f"missing {key} in {context}")
    return value


def optional_field(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def parse_positive_int(value: str, field: str) -> int:
    try:
        parsed = int(value)
    except ValueError as err:
        raise ValueError(f"{field} expects an integer, got '{value}'") from err
    if parsed <= 0:
        raise ValueError(f"{field} expects a positive integer, got {parsed}")
    return parsed


def parse_optional_int(value: str | None, field: str) -> int | None:
    stripped = optional_field(value)
    if stripped is None:
        return None
    try:
        parsed = int(stripped)
    except ValueError as err:
        raise ValueError(f"{field} expects an integer, got '{stripped}'") from err
    if parsed < 0:
        raise ValueError(f"{field} expects a non-negative integer, got {parsed}")
    return parsed


def generate_vectors(set_name: str, out_dir: Path, set_dir: Path = DEFAULT_SET_DIR) -> list[Path]:
    sets = vector_sets(set_dir)
    if set_name not in sets:
        choices = ", ".join(sorted(sets)) or "<none>"
        raise ValueError(f"unknown vector set '{set_name}'; choices: {choices}")

    vector_set = sets[set_name]
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for vector in vector_set.vectors:
        path = out_dir / vector.filename
        path.write_bytes(generate_yuv(vector, vector_set.sources))
        paths.append(path)
    return paths


def generate_yuv(vector: TestVector, sources: dict[str, TestVectorSource]) -> bytes:
    if vector.pattern == "source_crop":
        return generate_source_crop(vector, sources)
    if vector.fmt == "yuv420p8":
        return generate_yuv420p8(vector)
    if vector.fmt == "yuv444p8":
        return generate_yuv444p8(vector)
    raise ValueError(f"unsupported generated format: {vector.fmt}")


def generate_source_crop(vector: TestVector, sources: dict[str, TestVectorSource]) -> bytes:
    if vector.source is None:
        raise ValueError(f"{vector.filename} uses source_crop but has no source id")
    if vector.source not in sources:
        raise ValueError(f"{vector.filename} references unknown source '{vector.source}'")
    if vector.crop_x is None or vector.crop_y is None:
        raise ValueError(f"{vector.filename} uses source_crop but has no crop_x/crop_y")
    if vector.frames != 1:
        raise ValueError("source_crop vectors currently use the first frame only")

    source = sources[vector.source]
    if not source.path.exists():
        raise ValueError(f"source file is missing for '{source.id}': {source.path}")
    if vector.crop_x + vector.width > source.width or vector.crop_y + vector.height > source.height:
        raise ValueError(f"{vector.filename} crop exceeds source dimensions")

    if source.fmt in {"png_rgb8", "png_rgba8"} and vector.fmt == "yuv444p8":
        return generate_png_yuv444_crop(vector, source)

    if source.fmt != "yuv420p8" or vector.fmt != "yuv420p8":
        raise ValueError(
            "source_crop supports yuv420p8->yuv420p8 and PNG RGB/RGBA->yuv444p8"
        )

    frame_size = source.width * source.height * 3 // 2
    source_frame = source.path.read_bytes()[:frame_size]
    if len(source_frame) != frame_size:
        raise ValueError(f"{source.id} source is smaller than one {source.width}x{source.height} frame")

    y_size = source.width * source.height
    uv_size = y_size // 4
    source_y = source_frame[:y_size]
    source_u = source_frame[y_size : y_size + uv_size]
    source_v = source_frame[y_size + uv_size : y_size + (uv_size * 2)]

    out = bytearray()
    for row in range(vector.height):
        start = (vector.crop_y + row) * source.width + vector.crop_x
        out.extend(source_y[start : start + vector.width])

    chroma_width = vector.width // 2
    chroma_height = vector.height // 2
    source_chroma_width = source.width // 2
    crop_chroma_x = vector.crop_x // 2
    crop_chroma_y = vector.crop_y // 2
    for plane in (source_u, source_v):
        for row in range(chroma_height):
            start = (crop_chroma_y + row) * source_chroma_width + crop_chroma_x
            out.extend(plane[start : start + chroma_width])
    return bytes(out)


def generate_png_yuv444_crop(vector: TestVector, source: TestVectorSource) -> bytes:
    if Image is None:
        raise ValueError(
            "PNG-backed source_crop vectors require Pillow; install requirements-dev.txt"
        )

    with Image.open(source.path) as image:
        if image.size != (source.width, source.height):
            raise ValueError(
                f"{source.id} declares {source.width}x{source.height}, "
                f"but PNG is {image.size[0]}x{image.size[1]}"
            )
        # Preserve screen-capture RGB exactly by carrying it as planar GBR
        # through the current yuv444p8 component path. The .yuv extension is
        # just a raw-video container convention; use ffplay -pixel_format gbrp
        # when visualizing these local screenshot crops.
        crop = image.convert("RGB").crop(
            (
                vector.crop_x,
                vector.crop_y,
                vector.crop_x + vector.width,
                vector.crop_y + vector.height,
            )
        )
        red_plane, green_plane, blue_plane = crop.split()
        return green_plane.tobytes() + blue_plane.tobytes() + red_plane.tobytes()


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
    if vector.pattern == "transform_skip_left_delta":
        return transform_skip_left_delta_sample(x, y, frame)
    if vector.pattern == "palette_escape_prng":
        return palette_escape_prng_sample(vector, x, y, frame)
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


def transform_skip_left_delta_sample(x: int, y: int, frame: int) -> tuple[int, int, int]:
    tile_x = x // 8
    tile_y = y // 8
    pair_x = tile_x & ~1
    local_x = x & 7
    local_y = y & 7
    y_sample = (48 + (pair_x * 29) + (tile_y * 37) + (frame * 11)) & 0xFF
    cb_sample = (80 + (pair_x * 17) + (tile_y * 23) + (frame * 13)) & 0xFF
    cr_sample = (112 + (pair_x * 19) + (tile_y * 31) + (frame * 7)) & 0xFF
    if (tile_x & 1) and local_x < 4 and local_y < 4:
        y_sample = (y_sample + 3) & 0xFF
        cb_sample = (cb_sample + 4) & 0xFF
        cr_sample = (cr_sample + 5) & 0xFF
    return y_sample, cb_sample, cr_sample


def palette_escape_prng_sample(vector: TestVector, x: int, y: int, frame: int) -> tuple[int, int, int]:
    abs_x = x + (vector.crop_x or 0)
    abs_y = y + (vector.crop_y or 0)
    mix = (
        (abs_x * 0x45D9F3B)
        ^ (abs_y * 0x119DE1F3)
        ^ ((abs_x + 17) * (abs_y + 29) * 0x1B873593)
        ^ (frame * 0x85EBCA6B)
    ) & 0xFFFFFFFF
    mix ^= (mix >> 16)
    mix = (mix * 0x7FEB352D) & 0xFFFFFFFF
    mix ^= (mix >> 15)
    mix = (mix * 0x846CA68B) & 0xFFFFFFFF
    mix ^= (mix >> 16)
    y_sample = mix & 0xFF
    cb_sample = ((mix >> 8) ^ (abs_x * 37) ^ (frame * 19)) & 0xFF
    cr_sample = ((mix >> 16) ^ (abs_y * 53) ^ (frame * 23)) & 0xFF
    return y_sample, cb_sample, cr_sample


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
    parser.add_argument("--set", default="smoke", help="named vector set manifest to generate")
    parser.add_argument("--set-dir", type=Path, default=DEFAULT_SET_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--list-sets", action="store_true", help="list available vector set manifests")
    args = parser.parse_args()

    if args.list_sets:
        for name, vector_set in sorted(vector_sets(args.set_dir).items()):
            print(f"{name}\t{len(vector_set.vectors)}\t{vector_set.manifest}")
        return 0

    paths = generate_vectors(args.set, args.out_dir, args.set_dir)
    print(f"Generated {len(paths)} test vector(s) in {args.out_dir}")
    for path in paths:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
