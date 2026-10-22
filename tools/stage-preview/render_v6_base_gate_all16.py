"""Native base-region background and crop helpers retained from V6."""
import os
from pathlib import Path
from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[2]
PILOT_DIR = Path(os.environ.get("CFN_STAGE_PREVIEW_CACHE", ROOT / "tmp/stage-preview-cache"))

HD_W, HD_H = 644, 276
THUMB_W, THUMB_H = 161, 69


def find_raw_ffdec_png(prefix: str) -> Image.Image:
    raw_bgs = PILOT_DIR / "raw_bgs"
    matches = sorted(raw_bgs.glob(f"_ffdec_{prefix}_*/1.png"))
    if len(matches) != 1:
        raise FileNotFoundError(f"Expected exactly one native background for {prefix}; found {len(matches)}")
    return Image.open(matches[0]).convert("RGBA")


def load_skybox_png(name: str) -> Image.Image:
    p = PILOT_DIR / "raw_skybox" / name / "1.png"
    return Image.open(p).convert("RGBA")


def build_outdoor_bg_with_sky(
    prefix: str,
    sky_brightness: float = 0.78,
    include_far_buildings: bool = False,
    far_buildings_x_ratio: float = 0.18,
    far_buildings_y_ratio: float = 0.08,
    far_buildings_scale: float = 0.62,
    include_far_trees: bool = False,
    far_trees_y_ratio: float = 0.22,
) -> Image.Image:
    """
    Loads the transparent raw FFDec foreground PNG and composites it over the game's
    apocalyptic skybox (`废城阴间天空`), eliminating dead-black sky regions.
    """
    fg = find_raw_ffdec_png(prefix)
    W, H = fg.size

    sky = load_skybox_png("废城阴间天空").resize((W, H), Image.Resampling.LANCZOS)
    sky_rgb = ImageEnhance.Brightness(sky.convert("RGB")).enhance(sky_brightness)
    canvas = sky_rgb.convert("RGBA")

    if include_far_buildings:
        bldg = load_skybox_png("废城远景1")
        # Crop the non-empty top portion of 废城远景1 (which is in the top 320px of 1294x1790)
        bbox = bldg.getchannel("A").getbbox()
        if bbox:
            bldg = bldg.crop((bbox[0], bbox[1], bbox[2], bbox[3]))
        bw = int(round(bldg.width * far_buildings_scale))
        bh = int(round(bldg.height * far_buildings_scale))
        bldg_s = bldg.resize((bw, bh), Image.Resampling.LANCZOS)
        b_rgb = ImageEnhance.Brightness(bldg_s.convert("RGB")).enhance(0.85)
        bldg_s = Image.merge("RGBA", (*b_rgb.split(), bldg_s.getchannel("A")))
        canvas.alpha_composite(bldg_s, (int(round(W * far_buildings_x_ratio)), int(round(H * far_buildings_y_ratio))))

    if include_far_trees:
        trees = load_skybox_png("废城远处树林")
        tw = W
        th = int(round(trees.height * (W / trees.width)))
        trees_s = trees.resize((tw, th), Image.Resampling.LANCZOS)
        t_rgb = ImageEnhance.Brightness(trees_s.convert("RGB")).enhance(0.75)
        trees_s = Image.merge("RGBA", (*t_rgb.split(), trees_s.getchannel("A")))
        canvas.alpha_composite(trees_s, (0, int(round(H * far_trees_y_ratio))))

    canvas.alpha_composite(fg, (0, 0))
    return canvas


def crop_landmark_macro(bg_img: Image.Image, crop_box: list[float]) -> Image.Image:
    W, H = bg_img.size
    x, y, w, h = crop_box
    px0 = int(round(x * W))
    py0 = int(round(y * H))
    pw = max(64, int(round(w * W)))
    ph = max(32, int(round(h * H)))

    target_aspect = HD_W / HD_H
    cx = px0 + pw / 2.0
    cy = py0 + ph / 2.0
    if pw / ph > target_aspect:
        nh = pw / target_aspect
        nw = pw
    else:
        nw = ph * target_aspect
        nh = ph

    x1 = int(round(cx - nw / 2))
    y1 = int(round(cy - nh / 2))
    x2 = int(round(cx + nw / 2))
    y2 = int(round(cy + nh / 2))

    if x1 < 0:
        x2 -= x1
        x1 = 0
    if y1 < 0:
        y2 -= y1
        y1 = 0
    if x2 > W:
        x1 = max(0, x1 - (x2 - W))
        x2 = W
    if y2 > H:
        y1 = max(0, y1 - (y2 - H))
        y2 = H

    cropped = bg_img.crop((x1, y1, max(x1 + 1, x2), max(y1 + 1, y2)))
    return cropped.resize((HD_W, HD_H), Image.Resampling.LANCZOS)


def grade_background(
    bg_img: Image.Image,
    brightness: float = 0.90,
    contrast: float = 1.08,
    saturation: float = 0.85,
    color_overlay: tuple[int, int, int, int] | None = None,
) -> Image.Image:
    rgb = bg_img.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    out = rgb.convert("RGBA")
    if color_overlay and color_overlay[3] > 0:
        ov = Image.new("RGBA", out.size, color_overlay)
        out = Image.alpha_composite(out, ov)
    return out


def apply_directional_vignette(
    canvas: Image.Image,
    start_x_ratio: float = 0.45,
    max_alpha: int = 165,
    tint_rgb: tuple[int, int, int] = (8, 8, 12),
    top_bottom_vignette: int = 32,
) -> Image.Image:
    w, h = canvas.size
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = overlay.load()
    sx = int(w * start_x_ratio)
    span = max(1, w - sx)
    tr, tg, tb = tint_rgb
    for y in range(h):
        ny = abs((y / h) - 0.5) * 2.0
        tb_a = int(top_bottom_vignette * (ny ** 2.2))
        for x in range(w):
            if x >= sx:
                t = (x - sx) / span
                ra = int(max_alpha * (t ** 1.45))
            else:
                ra = 0
            a = min(255, max(tb_a, ra))
            if a > 0:
                px[x, y] = (tr, tg, tb, a)
    return Image.alpha_composite(canvas, overlay)


def build_ringroad_parallax_bg() -> Image.Image:
    """
    Reconstructs the exact 4-layer parallax scene of `stage_0_12 废城环线`:
    1. 废城阴间天空 (apocalyptic dark green-grey clouds)
    2. 废城远处巨大多高楼 (ruined skyscrapers + Ferris wheel = '废城')
    3. 废城环线树林 (olive pine trees & power poles along the highway)
    4. 废城环线地图3 (fallen streetlight pole + wooden ladder + guardrail + yellow-dashed cracked highway = '环线')
    """
    fg = find_raw_ffdec_png("废城环线地图3")
    W, H = fg.size  # 2808 x 731

    # Create a taller composite canvas (2808 x 820) so the skyscrapers and pine trees have generous headroom above the road
    comp_h = 820
    road_y_offset = comp_h - H  # 89px headroom above fg

    sky = load_skybox_png("废城阴间天空").resize((W, comp_h), Image.Resampling.LANCZOS)
    sky_rgb = ImageEnhance.Brightness(sky.convert("RGB")).enhance(0.88)
    canvas = sky_rgb.convert("RGBA")

    # Layer 2: 废城远处巨大多高楼 (839 x 326): note that the tilted tower & Ferris wheel are at x=280..680 inside this PNG!
    # Placing hr_img (scale=0.82) at x=195 puts the tilted tower & Ferris wheel at canvas x=425..755 (nx=0.14..0.46 of the crop),
    # right inside the gap between the left pine trees and 100% to the left of the monsters!
    highrise = load_skybox_png("废城远处巨大多高楼")
    hr_scale = 0.82
    hr_w = int(round(highrise.width * hr_scale))
    hr_h = int(round(highrise.height * hr_scale))
    hr_img = highrise.resize((hr_w, hr_h), Image.Resampling.LANCZOS)
    hr_rgb = ImageEnhance.Brightness(hr_img.convert("RGB")).enhance(0.96)
    hr_img = Image.merge("RGBA", (*hr_rgb.split(), hr_img.getchannel("A")))
    canvas.alpha_composite(hr_img, (195, 78))

    # Layer 3: 废城环线树林 (2869 x 327)
    forest = load_skybox_png("废城环线树林")
    fw = int(round(forest.width * 0.90))
    fh = int(round(forest.height * 0.90))
    forest_img = forest.resize((fw, fh), Image.Resampling.LANCZOS)
    f_rgb = ImageEnhance.Brightness(forest_img.convert("RGB")).enhance(0.88)
    forest_img = Image.merge("RGBA", (*f_rgb.split(), forest_img.getchannel("A")))
    canvas.alpha_composite(forest_img, (20, 134))

    # Layer 4: Foreground highway (废城环线地图3)
    canvas.alpha_composite(fg, (0, road_y_offset))
    return canvas
