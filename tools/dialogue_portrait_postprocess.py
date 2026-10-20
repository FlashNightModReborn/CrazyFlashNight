"""Opt-in, deterministic portrait effects shared by the baker and native XFL builder.

Coordinates, expressions and transparent canvas belong to the original portrait.
Profiles add color/alpha treatment, silhouette glow and fine scanlines only.
Existing authored Boy/Blue radio art remains the visual reference, unchanged.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageFilter

POLICY = Path("flashswf/portraits/postprocess.json")
ALGORITHM = "radio-color-alpha-scan-glow-v1"


def recipes(project_root: Path) -> dict:
    path = project_root / POLICY
    if not path.exists():
        return {}
    policy = json.loads(path.read_text(encoding="utf-8"))
    if policy.get("schema") != "cf7.dialogue-portrait-postprocess.v1":
        raise ValueError("Unknown dialogue portrait postprocess schema")
    result = {}
    for key, entry in policy["entries"].items():
        if entry["source"] == key or entry["source"] in policy["entries"]:
            raise ValueError("Portrait effects require a direct original source; no cycles/chains")
        profile = policy["profiles"][entry["profile"]]
        for name in ("low", "high", "glowColor"):
            if len(profile[name]) != 3 or any(type(v) is not int or not 0 <= v <= 255 for v in profile[name]):
                raise ValueError("Invalid portrait color: " + name)
        for name in ("colorRetention", "opacity", "scanDarken", "glowOpacity"):
            if not 0 <= profile[name] <= 1:
                raise ValueError("Invalid portrait strength: " + name)
        if not 1 <= profile["scanPeriod"] <= 16 or not 0 <= profile["glowRadius"] <= 8:
            raise ValueError("Unbounded portrait scan/glow profile")
        identity = json.dumps({"algorithm": ALGORITHM, "profile": profile}, sort_keys=True).encode()
        result[key] = dict(entry, settings=profile, algorithm=ALGORITHM,
                           profileSha256=hashlib.sha256(identity).hexdigest())
    return result


def color_matrix(profile: dict) -> list[float]:
    """Flash ColorMatrixFilter/Pillow affine RGB coefficients, with identical alpha."""
    keep = profile["colorRetention"]
    matrix = []
    for channel in range(3):
        slope = (profile["high"][channel] - profile["low"][channel]) / 255 * (1 - keep)
        matrix.extend([slope * weight + (keep if i == channel else 0)
                       for i, weight in enumerate((.2126, .7152, .0722))])
        matrix.extend([0, profile["low"][channel] * (1 - keep)])
    matrix.extend([0, 0, 0, profile["opacity"], 0])
    return matrix


def apply(image: Image.Image, profile: dict, scale: float) -> Image.Image:
    image = image.convert("RGBA")
    matrix = color_matrix(profile)
    rgb = image.convert("RGB").convert("RGB", tuple(v for i, v in enumerate(matrix[:15]) if i % 5 != 3))
    rgb.putalpha(image.getchannel("A").point(lambda a: round(a * profile["opacity"])))
    # Row transforms retain alpha; no opaque scanline/background rectangles.
    period = profile["scanPeriod"] * scale
    width = max(1, round(scale))
    for logical in range(round(image.height / period) + 1):
        y = round(logical * period)
        if y >= image.height:
            break
        box = (0, y, image.width, min(image.height, y + width))
        row = rgb.crop(box)
        red, green, blue, alpha = row.split()
        lut = [round(i * profile["scanDarken"]) for i in range(256)]
        row = Image.merge("RGBA", (red.point(lut), green.point(lut), blue.point(lut), alpha))
        rgb.paste(row, box)
    glow = Image.new("RGBA", image.size, tuple(profile["glowColor"]) + (0,))
    glow.putalpha(image.getchannel("A").filter(ImageFilter.GaussianBlur(profile["glowRadius"] * scale))
                  .point(lambda a: round(a * profile["glowOpacity"])))
    return Image.alpha_composite(glow, rgb)


def process_frame(source: Path, destination: Path, recipe: dict, scale: float) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        apply(image, recipe["settings"], scale).save(destination)
    return destination


def provenance(recipe: dict, source_swf: Path, project_root: Path) -> dict:
    return {"algorithm": recipe["algorithm"], "profile": recipe["profile"],
            "profileSha256": recipe["profileSha256"], "sourceKey": recipe["source"],
            "sourcePath": source_swf.relative_to(project_root).as_posix(),
            "sourceSha256": hashlib.sha256(source_swf.read_bytes()).hexdigest()}
