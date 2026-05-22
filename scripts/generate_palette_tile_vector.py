#!/usr/bin/env python3
"""Generate a small 4:4:4 palette-oriented screen-content test vector."""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path


DEFAULT_OUT_DIR = Path("verification/test_vectors")
WIDTH = 64
HEIGHT = 64
TILE = 8


def clamp_u8(value: float) -> int:
    return max(0, min(255, round(value)))


def rgb_to_yuv444(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    r, g, b = rgb
    y = clamp_u8((0.299 * r) + (0.587 * g) + (0.114 * b))
    u = clamp_u8((-0.168736 * r) - (0.331264 * g) + (0.5 * b) + 128)
    v = clamp_u8((0.5 * r) - (0.418688 * g) - (0.081312 * b) + 128)
    return y, u, v


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, pixels: list[tuple[int, int, int]]) -> None:
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(pixels[y * width + x])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n"
    data += png_chunk(b"IHDR", ihdr)
    data += png_chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
    data += png_chunk(b"IEND", b"")
    path.write_bytes(data)


def generate() -> tuple[bytes, list[tuple[int, int, int]]]:
    palette = [
        (28, 44, 92),
        (210, 64, 56),
        (64, 170, 92),
        (242, 196, 65),
        (152, 84, 190),
        (56, 184, 204),
        (236, 126, 48),
        (224, 224, 214),
        (42, 42, 42),
        (124, 206, 74),
        (190, 54, 118),
        (72, 112, 210),
    ]
    tile_map = [
        [0, 0, 1, 1, 2, 2, 3, 3],
        [0, 4, 4, 1, 2, 5, 5, 3],
        [6, 4, 7, 7, 7, 7, 5, 8],
        [6, 6, 7, 9, 9, 7, 8, 8],
        [10, 10, 7, 9, 9, 7, 11, 11],
        [10, 7, 7, 7, 7, 7, 11, 3],
        [0, 4, 4, 1, 2, 5, 5, 3],
        [0, 0, 1, 1, 2, 2, 3, 3],
    ]
    rgb_pixels: list[tuple[int, int, int]] = []
    y_plane = bytearray()
    u_plane = bytearray()
    v_plane = bytearray()

    for y in range(HEIGHT):
        for x in range(WIDTH):
            color = palette[tile_map[y // TILE][x // TILE]]
            yy, uu, vv = rgb_to_yuv444(color)
            rgb_pixels.append(color)
            y_plane.append(yy)
            u_plane.append(uu)
            v_plane.append(vv)

    return bytes(y_plane + u_plane + v_plane), rgb_pixels


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    yuv, rgb_pixels = generate()
    base = "palette_tiles_64x64_1f_yuv444p8"
    yuv_path = args.out_dir / f"{base}.yuv"
    png_path = args.out_dir / f"{base}.png"
    yuv_path.write_bytes(yuv)
    write_png(png_path, WIDTH, HEIGHT, rgb_pixels)
    print(yuv_path)
    print(png_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
