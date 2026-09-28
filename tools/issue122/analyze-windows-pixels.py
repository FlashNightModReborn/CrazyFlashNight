"""Measure captured A/B differences without converting tolerances into acceptance."""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def components(mask):
    remaining = mask.copy()
    height, width = mask.shape
    found = []
    for yy, xx in zip(*np.nonzero(mask)):
        if not remaining[yy, xx]:
            continue
        stack = [(int(xx), int(yy))]
        remaining[yy, xx] = False
        count, left, top, right, bottom = 0, int(xx), int(yy), int(xx), int(yy)
        while stack:
            x, y = stack.pop()
            count += 1
            left, top, right, bottom = min(left, x), min(top, y), max(right, x), max(bottom, y)
            for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if 0 <= nx < width and 0 <= ny < height and remaining[ny, nx]:
                    remaining[ny, nx] = False
                    stack.append((nx, ny))
        found.append({"pixels": count, "bbox": [left, top, right+1, bottom+1]})
    return sorted(found, key=lambda x: x["pixels"], reverse=True)[:10]


def compare(root, a, b, name):
    first = np.asarray(Image.open(root / a).convert("RGBA"), dtype=np.int16)
    second = np.asarray(Image.open(root / b).convert("RGBA"), dtype=np.int16)
    if first.shape != second.shape:
        raise ValueError("Capture dimensions differ: " + name)
    delta = np.abs(first - second)
    maximum = delta.max(axis=2)
    changed = maximum > 0
    result = {
        "name": name, "a": a, "b": b,
        "pixels": int(maximum.size), "changedPixels": int(changed.sum()),
        "changedPercent": float(changed.mean() * 100),
        "meanAbsoluteRgbaDifference": float(delta.mean()),
        "maximumChannelDifference": int(delta.max()),
        "pixelsAtLeast2": int((maximum >= 2).sum()),
        "pixelsAtLeast8": int((maximum >= 8).sum()),
        "pixelsAtLeast16": int((maximum >= 16).sum()),
        "pixelsAtLeast64": int((maximum >= 64).sum()),
        "largestComponentsAtLeast16": components(maximum >= 16),
    }
    diff = np.zeros_like(first, dtype=np.uint8)
    diff[:,:,:3] = np.minimum(delta[:,:,:3] * 8, 255).astype(np.uint8)
    diff[:,:,3] = 255
    Image.fromarray(diff).save(root / (name + "-difference-x8.png"))
    return result


def main():
    root = Path(sys.argv[1]).resolve()
    destination = root / "pixel-analysis.json"
    if destination.exists():
        raise ValueError("Refusing to overwrite existing analysis")
    rows = []
    capture = json.loads((root / "result.json").read_text(encoding="utf-8"))
    cameras = list(dict.fromkeys(row["camera"] for row in capture["cells"]))
    for camera in cameras:
        for lane, a, b in (("gpu","raw","chunked"),("gpu","chunked","nonindexed"),
                           ("gpu","raw","nonindexed"),("software","raw","chunked")):
            name = f"{lane}-{camera}-{a}-vs-{b}"
            rows.append(compare(root, f"{lane}-{camera}-{a}.png", f"{lane}-{camera}-{b}.png", name))
    destination.write_text(json.dumps({"schema": 1, "comparisons": rows,
        "boundary": "Numerical measurements only; no tolerance-based acceptance or driver attribution."},
        ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(json.dumps({key: row[key] for key in ("name", "changedPixels", "changedPercent", "maximumChannelDifference", "pixelsAtLeast16", "largestComponentsAtLeast16")}))


if __name__ == "__main__":
    main()
