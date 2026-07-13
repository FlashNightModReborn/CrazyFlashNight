#!/usr/bin/env python3
"""Synthetic smoke test for the reskin package builder."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw


TOOL_DIR = Path(__file__).resolve().parent
BUILDER = TOOL_DIR / "build_reference_package.py"


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="monster-reskin-") as temp_value:
        temp = Path(temp_value)
        frames = temp / "frames"
        parts_png = temp / "parts-png"
        parts_svg = temp / "parts-svg"
        staging = temp / "staging"
        output = temp / "package"
        for path in [frames, parts_png, parts_svg, staging]:
            path.mkdir(parents=True)

        for frame in [1, 2, 3]:
            image = Image.new("RGBA", (320, 220), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            draw.rectangle((10, 10, 140, 40), fill=(60, 220, 60, 255))
            draw.ellipse((120 + frame * 8, 100, 240 + frame * 8, 180), fill=(100, 70, 50, 255), outline=(0, 0, 0, 255), width=3)
            image.save(frames / f"{frame}.png")
        part = Image.new("RGBA", (120, 80), (0, 0, 0, 0))
        ImageDraw.Draw(part).ellipse((10, 10, 110, 70), fill=(110, 80, 60, 255))
        part.save(parts_png / "7.png")
        (parts_svg / "7.svg").write_text(
            '<svg xmlns="http://www.w3.org/2000/svg"><g transform="matrix(4, 0, 0, 4, 40, 30)"><path d="M0 0L1 1"/></g></svg>\n',
            encoding="utf-8",
        )
        export_manifest = {
            "root": {"frameDir": str(frames), "frameCount": 3},
            "parts": [{"slug": "body", "characterId": 7, "png": str(parts_png / "7.png"), "svg": str(parts_svg / "7.svg"), "localOriginPx": {"x": 40, "y": 30}}],
        }
        (staging / "export-manifest.json").write_text(json.dumps(export_manifest), encoding="utf-8")
        config = {
            "monster": "smoke-dog",
            "outputDir": str(output),
            "ignoreTopFraction": 0.25,
            "heroFrame": 2,
            "source": {"xfl": "fixture.xfl", "swf": "fixture.swf", "rootCharacterId": 99},
            "export": {"stagingDir": str(staging)},
            "keyposes": [
                {"slug": "idle", "label": "idle", "frame": 1},
                {"slug": "attack", "label": "attack", "frame": 2},
            ],
            "parts": [{"slug": "body", "label": "body", "symbol": "Symbol 1", "characterId": 7, "group": "normal-rig"}],
            "guardrails": ["keep origin"],
        }
        config_path = temp / "config.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        result = subprocess.run([sys.executable, str(BUILDER), "--config", str(config_path)], text=True, capture_output=True, encoding="utf-8")
        if result.returncode != 0:
            print(result.stdout)
            print(result.stderr, file=sys.stderr)
            return result.returncode
        expected = [
            output / "whole/core.png",
            output / "sheets/keyposes.png",
            output / "sheets/parts-normal-rig.png",
            output / "manifest.json",
            output / "README.md",
        ]
        missing = [str(path) for path in expected if not path.exists()]
        if missing:
            print(f"ERROR: missing {missing}", file=sys.stderr)
            return 1
        manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        if manifest["exportedSequenceFrameCount"] != 3 or len(manifest["parts"]) != 1:
            print("ERROR: bad manifest", file=sys.stderr)
            return 1
    print("OK: monster-reskin-pipeline smoke")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
