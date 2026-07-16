#!/usr/bin/env python3
"""Convert CF7 map runtime images to pixel-verified lossless WebP."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, features


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pair",
        nargs=2,
        action="append",
        metavar=("SOURCE", "OUTPUT"),
        help="Convert one source image to one .webp output; may be repeated.",
    )
    parser.add_argument(
        "--tree",
        help="Convert every PNG below this directory to a sibling .webp file.",
    )
    parser.add_argument(
        "--delete-source",
        action="store_true",
        help="Delete each source only after the lossless pixel verification succeeds.",
    )
    parser.add_argument("--method", type=int, default=6, choices=range(0, 7))
    return parser.parse_args()


def convert(source: Path, output: Path, method: int, delete_source: bool) -> tuple[int, int]:
    if not source.is_file():
        raise FileNotFoundError(source)
    if output.suffix.lower() != ".webp":
        raise ValueError(f"output must end in .webp: {output}")

    with Image.open(source) as image:
        rgba = image.convert("RGBA")
        source_pixels = rgba.tobytes()
        size = rgba.size
        icc_profile = image.info.get("icc_profile")

    output.parent.mkdir(parents=True, exist_ok=True)
    save_args = {
        "format": "WEBP",
        "lossless": True,
        "exact": True,
        "method": method,
    }
    if icc_profile:
        save_args["icc_profile"] = icc_profile
    rgba.save(output, **save_args)

    with Image.open(output) as decoded:
        decoded_rgba = decoded.convert("RGBA")
        if decoded_rgba.size != size or decoded_rgba.tobytes() != source_pixels:
            output.unlink(missing_ok=True)
            raise RuntimeError(f"lossless pixel verification failed: {source} -> {output}")

    source_bytes = source.stat().st_size
    output_bytes = output.stat().st_size
    if delete_source:
        source.unlink()
    return source_bytes, output_bytes


def main() -> None:
    args = parse_args()
    if not features.check("webp"):
        raise SystemExit("Pillow was built without WebP support")

    pairs = [(Path(source), Path(output)) for source, output in (args.pair or [])]
    if args.tree:
        tree = Path(args.tree)
        pairs.extend((source, source.with_suffix(".webp")) for source in sorted(tree.rglob("*.png")))
    if not pairs:
        raise SystemExit("provide at least one --pair or --tree")

    source_total = 0
    output_total = 0
    for source, output in pairs:
        source_bytes, output_bytes = convert(source, output, args.method, args.delete_source)
        source_total += source_bytes
        output_total += output_bytes
        print(f"[map-webp] {source} -> {output} ({source_bytes} -> {output_bytes})")

    saving = (1 - output_total / source_total) * 100 if source_total else 0
    print(
        f"[map-webp] converted={len(pairs)} sourceBytes={source_total} "
        f"webpBytes={output_total} saving={saving:.1f}%"
    )


if __name__ == "__main__":
    main()
