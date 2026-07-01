#!/usr/bin/env python3
"""Remove a flat chroma-key background from generated icon art.

This is intentionally small and project-local. It mirrors the repeated
post-processing used during the intelligence-icon draw rounds: remove a flat
key color, keep soft antialiasing, despill edges, and zero tiny alpha noise.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image


def parse_hex_color(value: str) -> tuple[int, int, int]:
    text = value.strip()
    if text.startswith("#"):
        text = text[1:]
    if len(text) != 6:
        raise argparse.ArgumentTypeError(f"expected RRGGBB hex color, got {value!r}")
    try:
        return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid hex color {value!r}") from exc


def remove_key(
    source: Path,
    target: Path,
    key: tuple[int, int, int],
    transparent_distance: float,
    opaque_distance: float,
    alpha_scrub: int,
    despill: bool,
) -> dict[str, int | tuple[int, int]]:
    image = Image.open(source).convert("RGBA")
    output: list[tuple[int, int, int, int]] = []

    if opaque_distance <= transparent_distance:
        raise ValueError("opaque distance must be greater than transparent distance")

    for red, green, blue, alpha in image.getdata():
        distance = math.sqrt(
            (red - key[0]) ** 2 + (green - key[1]) ** 2 + (blue - key[2]) ** 2
        )
        if distance <= transparent_distance:
            new_alpha = 0
        elif distance >= opaque_distance:
            new_alpha = alpha
        else:
            ramp = (distance - transparent_distance) / (opaque_distance - transparent_distance)
            new_alpha = int(alpha * ramp)

        if despill and new_alpha < 255:
            if key[0] >= key[1] and key[0] >= key[2]:
                red = min(red, max(green, blue))
            if key[1] >= key[0] and key[1] >= key[2]:
                green = min(green, max(red, blue))
            if key[2] >= key[0] and key[2] >= key[1]:
                blue = min(blue, max(red, green))

        if new_alpha < alpha_scrub:
            new_alpha = 0
        output.append((red, green, blue, new_alpha))

    image.putdata(output)
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target)

    alphas = [pixel[3] for pixel in output]
    corners = [
        image.getpixel((0, 0))[3],
        image.getpixel((image.width - 1, 0))[3],
        image.getpixel((0, image.height - 1))[3],
        image.getpixel((image.width - 1, image.height - 1))[3],
    ]
    return {
        "size": image.size,
        "transparent": sum(a == 0 for a in alphas),
        "semi": sum(0 < a < 255 for a in alphas),
        "opaque": sum(a == 255 for a in alphas),
        "corners_alpha_zero": int(all(a == 0 for a in corners)),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--key", default="#ff00ff", type=parse_hex_color)
    parser.add_argument("--transparent-distance", default=80.0, type=float)
    parser.add_argument("--opaque-distance", default=135.0, type=float)
    parser.add_argument("--alpha-scrub", default=20, type=int)
    parser.add_argument("--no-despill", action="store_true")
    args = parser.parse_args()

    stats = remove_key(
        args.input,
        args.out,
        args.key,
        args.transparent_distance,
        args.opaque_distance,
        args.alpha_scrub,
        not args.no_despill,
    )
    print(f"wrote {args.out}")
    print(
        "size={size} transparent={transparent} semi={semi} opaque={opaque} "
        "corners_alpha_zero={corners_alpha_zero}".format(**stats)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
