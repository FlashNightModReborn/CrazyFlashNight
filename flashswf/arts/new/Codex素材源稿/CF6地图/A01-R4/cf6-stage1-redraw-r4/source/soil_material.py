"""Deterministic sand/compacted-gravel material, rebuilt from a recipe.

This is deliberately a procedural raster material embedded in a small SVG,
not a claim of hand-drawn vectors. No source artwork is sampled or composited.
The reference is used only to judge hue, scale, directional grain and contrast.

Public API:
    image = generate((324, 300), seed=1611, profile="stage2")
    image4x = generate((1296, 1200), seed=1611, profile="stage2")
    stage1 = generate((800, 452), seed=1580, profile="stage1")
    # palette is a sequence of (normalized_y, (r, g, b)) lighting stops.
    # profile may also be a dictionary overriding a named base profile.

Both resolutions are derived from the same 4x physical-scale master. At 2x/4x
the sand particles have genuine antialiased relief, rather than enlarged 1x
pixels. Horizontal wrapping is built into fields and particle deposition.
Dependencies: Python 3, NumPy, SciPy, Pillow. No network or generative model.
"""
from __future__ import annotations

import argparse
import base64
from io import BytesIO
import json
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, map_coordinates

VERSION = "2.1.0"
ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    "stage2": {
        "world_size": (324, 300), "grain_scale": 1.0, "contrast": 1.0,
        "palette": [(0., (17, 12.5, 8.5)), (.18, (34, 27.0, 18.0)),
                    (.40, (64, 51.5, 34.0)), (.60, (81, 65.2, 43.0)),
                    (1., (82, 66.2, 43.5))],
        "broad_strength": 3.0, "lighting": "stage2",
    },
    "stage1": {
        "world_size": (800, 452), "grain_scale": 1.0, "contrast": .94,
        "palette": [(0., (1, .8, .5)), (.332, (1, .8, .5)),
                    (.387, (12, 9.7, 6.4)), (.498, (43, 34.8, 23)),
                    (.608, (66, 53.5, 35.3)), (.719, (78, 63.2, 41.7)),
                    (1., (77, 62.4, 41.2))],
        "broad_strength": 3.4, "lighting": "stage1",
    },
}


def _normalized(a):
    a = a.astype(np.float32)
    return (a - a.mean()) / max(float(a.std()), 1e-7)


def _noise(rng, shape, sx, sy):
    """Band-limited correlated field. X wraps; Y is not tiled."""
    # Large fields use a coarser raster before interpolation for speed.
    stride = max(1, int(min(sx, sy) / 2.0))
    h, w = shape
    hh, ww = int(np.ceil(h / stride)), int(np.ceil(w / stride))
    white = rng.standard_normal((hh, ww), dtype=np.float32)
    a = gaussian_filter(white, (sy / stride, sx / stride), mode=("reflect", "wrap"))
    if stride != 1:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        a = map_coordinates(a, [yy * hh / h, xx * ww / w], order=3,
                            mode="grid-wrap", prefilter=True)
    return _normalized(a)


def _deposit(height, mineral, rng, grain_scale, scale, density, sizes):
    """Irregular, partly buried gravel grains with faceted physical relief.

    Ellipsoids are not drawn as visible spot decals: they contribute to one
    shaded surface. Distribution varies with soil pockets, not a regular grid.
    """
    h, w = height.shape
    count = int((w / scale) * (h / scale) * density)
    for _ in range(count):
        cx, cy = rng.uniform(0, w), rng.uniform(-3 * scale, h + 3 * scale)
        rx = rng.uniform(*sizes) * grain_scale * scale
        ry = rx * rng.uniform(.35, .72)
        ang = rng.normal(-.08, .30)
        extent = int(np.ceil(rx * 1.5 + scale))
        x0, y0 = int(cx) - extent, max(0, int(cy) - extent)
        x1, y1 = int(cx) + extent + 1, min(h, int(cy) + extent + 1)
        if y1 <= y0:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        dx, dy = xx - cx, yy - cy
        u = (dx * np.cos(ang) + dy * np.sin(ang)) / rx
        v = (-dx * np.sin(ang) + dy * np.cos(ang)) / ry
        # Non-circular chipped profile and varying shoulder hardness.
        radius = u * u + v * v + .10 * np.sin(u * 5 + v * 2)
        mound = np.maximum(0, 1 - radius) ** rng.uniform(.45, 1.15)
        amplitude = rng.uniform(.35, 1.05)
        patch = mound * amplitude
        xs = np.arange(x0, x1) % w
        height[y0:y1, xs] += patch
        mineral[y0:y1, xs] += mound * rng.uniform(-.7, .8)


def _master(p, palette, seed):
    # Always use the same physical 4x master, regardless of output resolution.
    scale = 4
    bw, bh = p["world_size"]
    w, h = bw * scale, bh * scale
    shape = (h, w)
    rng = np.random.default_rng(seed)
    grain = p["grain_scale"]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    x, y = xx / scale, yy / scale
    yn = y / bh

    # A wide, smooth lighting field sits under three different material scales.
    broad = _noise(rng, shape, 25 * scale, 13 * scale)
    broad2 = _noise(rng, shape, 58 * scale, 29 * scale)
    pockets = _noise(rng, shape, 6.5 * scale, 3.2 * scale)
    compaction = _noise(rng, shape, 14 * scale, 1.8 * scale)
    color = _noise(rng, shape, 2.3 * scale, 1.1 * scale)

    # Particle bed: width exceeds height, but direction meanders locally.
    bed = _noise(rng, shape, .65 * scale * grain, .36 * scale * grain)
    chips = _noise(rng, shape, .39 * scale * grain, .31 * scale * grain)
    # Warping is weak; no repeated hatch pattern or procedural sine stripes.
    warp = _noise(rng, shape, 9 * scale, 5 * scale)
    bed = map_coordinates(bed, [yy + warp * .22 * scale, xx],
                          order=1, mode="grid-wrap", prefilter=False)
    height = bed * .40 + chips * .23
    mineral = np.zeros(shape, np.float32)
    _deposit(height, mineral, rng, grain, scale, .14, (.28, .85))
    _deposit(height, mineral, rng, grain, scale, .032, (.55, 1.65))
    _deposit(height, mineral, rng, grain, scale, .0035, (1.5, 2.8))

    # One consistent near-grazing light, giving bright short edges and dark
    # brown interstices. Only a small albedo term is independent of this relief.
    gy, gx = np.gradient(height, 1 / scale)
    relief = _normalized(-gy - .28 * gx)
    relief = np.tanh(relief * .70) / .53
    tiny = _noise(rng, shape, .15 * scale, .15 * scale)
    amplitude = np.clip(1 + pockets * .11 - compaction * .07, .64, 1.35)
    material = (relief * 22.0 + bed * 4.4 + color * 4.7 +
                chips * 2.6 + mineral * 7.0 + tiny * 5.0) * amplitude
    material += pockets * 4.2 + compaction * 1.2

    stops, colors = zip(*palette)
    base = np.stack([np.interp(yn, stops, np.array(colors)[:, c]) for c in range(3)], -1)
    if p["lighting"] == "stage1":
        # Stage 1's back edge goes almost black. A shallow oblique shelf
        # brightens the middle-left; a broad right-hand basin remains darker.
        # Its depth transition is tied to the stage's ground horizon at y=150,
        # not the top edge / full-height stage2 illumination.
        oblique_y = (y - .055 * (x - .625 * bw)) / bh
        base = np.stack([np.interp(oblique_y, stops, np.array(colors)[:, c])
                         for c in range(3)], -1)
        depth = np.clip((y - .332 * bh) / (.332 * bh), 0, 1)
        right_hollow = np.exp(-((x - .98 * bw) / (.25 * bw)) ** 2
                              - ((y - .72 * bh) / (.26 * bh)) ** 2) * depth
        base -= right_hollow[..., None] * np.array([24., 19.5, 13.])
    lighting = np.clip(base[..., 1] / 65., .16, 1.15)
    low = broad * p["broad_strength"] + broad2 * 1.6
    lum = (material * p["contrast"] + low) * lighting
    # Warm neutral brown. Albedo hue is quieter than luminance relief.
    rgb = base + np.maximum(lum, 0)[..., None] * np.array([1.0, 1.0, .93])
    rgb += np.minimum(lum, 0)[..., None] * np.array([1.0, 1.0, .90])
    rgb += (color * .4)[..., None] * np.array([.5, -.1, -.45])
    return Image.fromarray(np.uint8(np.clip(rgb, 0, 255)), "RGB")


def generate(size=(324, 300), palette=None, seed=1611, profile="stage2"):
    """Return a Pillow RGB texture at output size, from the shared 4x recipe.

    A string profile chooses stage1 (800x452) or stage2 (324x300) world scale.
    A dict supports {"base": "stage1", "contrast": .9, "grain_scale": 1.1,
    "world_size": (800,452), "lighting": "stage1", "broad_strength": 3.0}.
    Palette is [(0., (r,g,b)), ..., (1., (r,g,b))]. The stage1 lighting
    profile applies a separately modelled diagonal shelf/right-hand hollow;
    lighting="custom" gives ordinary palette interpolation.
    """
    if isinstance(profile, str):
        p = dict(PROFILES[profile])
    else:
        p = dict(PROFILES[profile.get("base", "stage2")])
        p.update(profile)
    palette = palette if palette is not None else p["palette"]
    master = _master(p, palette, int(seed))
    size = tuple(map(int, size))
    return master if master.size == size else master.resize(size, Image.Resampling.LANCZOS)


def write_svg(image, path, world_size=(324, 300)):
    """Embed the high-quality master so the SVG has no external file dependency."""
    blob = BytesIO()
    image.save(blob, format="PNG", optimize=True)
    data = base64.b64encode(blob.getvalue()).decode("ascii")
    w, h = world_size
    text = (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n'
            f'<title>Compacted sand and gravel, deterministic material {VERSION}</title>\n'
            '<desc>Self-contained procedural raster bake. Editable recipe: source/soil_material.py. '
            'No original texture pixels are reused. Horizontal fields wrap for four adjoining fills.</desc>\n'
            f'<image width="{w}" height="{h}" preserveAspectRatio="none" '
            f'xlink:href="data:image/png;base64,{data}"/>\n</svg>\n')
    Path(path).write_text(text)


def bake_stage2(root=ROOT):
    root = Path(root)
    out = root / "source" / "materials"
    out.mkdir(exist_ok=True)
    master = generate((1296, 1200), seed=1611, profile="stage2")
    for scale in (1, 2, 4):
        im = master if scale == 4 else master.resize((324 * scale, 300 * scale), Image.Resampling.LANCZOS)
        im.save(out / f"soil-stage2-{scale}x.png")
    write_svg(master.resize((648, 600), Image.Resampling.LANCZOS), root / "parts" / "bitmap-1611.svg")
    return master


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", choices=["stage1", "stage2"], default="stage2")
    ap.add_argument("--output")
    ap.add_argument("--scale", type=int, choices=[1, 2, 4], default=1)
    args = ap.parse_args()
    if args.stage == "stage2" and not args.output:
        bake_stage2()
    else:
        world = PROFILES[args.stage]["world_size"]
        im = generate(tuple(n * args.scale for n in world), seed=1580 if args.stage == "stage1" else 1611, profile=args.stage)
        im.save(args.output or ROOT / "source" / "materials" / f"soil-{args.stage}-{args.scale}x.png")
