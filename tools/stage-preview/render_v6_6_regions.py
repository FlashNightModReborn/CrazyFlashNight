#!/usr/bin/env python3
"""Native region background, grading and portrait placement helpers retained from V6."""

import os
import xml.etree.ElementTree as ET
from pathlib import Path
import render_audit
from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
PILOT_DIR = Path(os.environ.get("CFN_STAGE_PREVIEW_CACHE", ROOT / "tmp/stage-preview-cache"))
RAW_BG_DIR = PILOT_DIR / "raw_bgs"
RAW_MONSTER_DIR = PILOT_DIR / "raw_monsters"

HD_W, HD_H = 644, 276
MID_W, MID_H = 322, 138
THUMB_W, THUMB_H = 161, 69


def load_environment_map() -> dict:
    env_root = ET.parse(ROOT / "data/environment/stage_environment.xml").getroot()
    env_by_bg = {}
    for node in env_root.findall("Environment"):
        bg_url = (node.findtext("BackgroundURL") or "").strip()
        if not bg_url:
            continue
        skies = []
        for sb in node.findall("Skybox"):
            url = (sb.findtext("url") or "").strip()
            rate_str = (sb.findtext("SpeedRate") or "2").strip()
            try:
                rate = float(rate_str)
            except Exception:
                rate = 2.0
            if url:
                skies.append({"url": url, "rate": rate})
        skies.sort(key=lambda x: x["rate"], reverse=True)
        disable_sky = (node.findtext("DisableSky") or "").strip().lower() == "true"
        env_by_bg[bg_url] = {
            "skies": skies,
            "disable_sky": disable_sky,
        }
    return env_by_bg


# Indoor / underground background prefixes where outdoor cloud sky should NOT be injected
INDOOR_PREFIXES = (
    "hthcftnb",
    "hthhftnb",
    "hthhltnb",
    "hthzt_1",
    "hthzt_2",
    "hthzt_3",
    "hthzt_4",
    "hthzt_5",
    "Survival_mode",
    "堕落城下水道_",
    "据点M",
    "诺亚前线基地",
    "nyqxjd",
    "ciyuanta",
    "核电站反应室",
    "军阀秘密基地",
    "武器仓库",
    "尸母巢穴",
    "xyjd_",
    "地图-堕落城酒吧",
)


def is_indoor_bg(bg_name: str, env_info: dict) -> bool:
    if env_info.get("disable_sky"):
        return True
    stem = Path(bg_name).stem
    for pref in INDOOR_PREFIXES:
        if stem.startswith(pref):
            return True
    return False


_SKY_CACHE = {}


def get_default_sky_png() -> Image.Image:
    if "default" not in _SKY_CACHE:
        p = PILOT_DIR / "raw_skybox" / "废城阴间天空" / "1.png"
        _SKY_CACHE["default"] = Image.open(p).convert("RGBA")
    return _SKY_CACHE["default"]


def find_skybox_ffdec_png(sb_url: str) -> Image.Image | None:
    stem = Path(sb_url).stem
    p1 = PILOT_DIR / "raw_skybox" / stem / "1.png"
    if p1.is_file():
        return Image.open(p1).convert("RGBA")
    matches = sorted(RAW_BG_DIR.glob(f"_ffdec_{stem}_*/*.png"))
    if matches:
        return Image.open(matches[0]).convert("RGBA")
    return None


def build_stage_bg_canvas(bg_swf: str, region_label: str, env_by_bg: dict) -> tuple[Image.Image, Image.Image | None, bool]:
    """
    Returns (composited_bg_rgba, raw_fg_cropped_rgba, is_indoor).
    Ensures exact same (W, H) dimensions as `<slug>_clean.png` while upgrading outdoor skies
    with the real `废城阴间天空` cloud texture + regional atmospheric tint + `<Skybox>` parallax layers!
    """
    stem = Path(bg_swf).stem
    clean_matches = sorted(RAW_BG_DIR.glob(f"{stem}_*_clean.png"))
    ff_dirs = sorted(RAW_BG_DIR.glob(f"_ffdec_{stem}_*"))

    bg_name = Path(bg_swf).name
    einfo = env_by_bg.get(bg_name, {})
    indoor = is_indoor_bg(bg_name, einfo)

    raw_fg = None
    if ff_dirs:
        pngs = sorted(ff_dirs[0].rglob("*.png"))
        if pngs:
            raw_im = Image.open(pngs[0]).convert("RGBA")
            bbox = raw_im.getchannel("A").getbbox()
            if bbox:
                raw_im = raw_im.crop(bbox)
            raw_fg = raw_im

    if raw_fg is None:
        if clean_matches:
            im = Image.open(clean_matches[0]).convert("RGBA")
            return im, None, indoor
        raise FileNotFoundError(f"Cannot find background image for {bg_swf}")

    W, H = raw_fg.size

    if stem == "gk15_5_BG" and clean_matches:
        im = Image.open(clean_matches[0]).convert("RGBA")
        return im, None, False

    # If indoor and no explicit Skybox, check if clean_png exists
    if indoor and not einfo.get("skies"):
        # Use a dark indoor ambient backdrop behind raw_fg
        base = Image.new("RGBA", (W, H), (16, 18, 22, 255))
        base.alpha_composite(raw_fg, (0, 0))
        return base, raw_fg, True

    # Outdoor or explicit Skybox stage: start from real cloud texture `废城阴间天空`
    sky_src = get_default_sky_png().resize((W, H), Image.Resampling.LANCZOS).convert("RGB")
    if region_label == "雪山":
        # Cold glacial winter sky tint for Snow Mountain outdoor stages
        sky_src = ImageEnhance.Color(sky_src).enhance(0.45)
        sky_src = ImageEnhance.Brightness(sky_src).enhance(1.18)
        sky_src = Image.blend(sky_src, Image.new("RGB", (W, H), (118, 138, 162)), 0.42)
    elif region_label == "基地房顶":
        # Arid desert/wasteland dusk sky for Base Rooftop warlord stages
        sky_src = ImageEnhance.Brightness(sky_src).enhance(0.92)
        sky_src = Image.blend(sky_src, Image.new("RGB", (W, H), (78, 66, 52)), 0.24)
    elif region_label == "地下2层":
        # Scorched wasteland / industrial dusk sky
        sky_src = ImageEnhance.Brightness(sky_src).enhance(0.86)
        sky_src = Image.blend(sky_src, Image.new("RGB", (W, H), (52, 58, 68)), 0.22)
    else:
        sky_src = ImageEnhance.Brightness(sky_src).enhance(0.86)

    canvas = sky_src.convert("RGBA")

    # Composite explicit <Skybox> parallax layers from stage_environment.xml
    for sb in einfo.get("skies", []):
        sb_im = find_skybox_ffdec_png(sb["url"])
        if sb_im is not None:
            sb_bbox = sb_im.getchannel("A").getbbox()
            if sb_bbox:
                sb_im = sb_im.crop(sb_bbox)
            sb_h = int(round(H * 0.72))
            sb_resized = sb_im.resize((W, max(1, sb_h)), Image.Resampling.LANCZOS)
            canvas.alpha_composite(sb_resized, (0, 0))

    canvas.alpha_composite(raw_fg, (0, 0))
    return canvas, raw_fg, False


def crop_landmark_safe(
    bg_img: Image.Image,
    raw_fg: Image.Image | None,
    crop_box: list[float],
    is_indoor: bool,
) -> Image.Image:
    """
    Crops `bg_img` to `[x, y, w, h]` fitted to 644x276 (2.333:1 aspect ratio).
    For indoor stages (`is_indoor=True`), automatically checks `raw_fg` alpha in the top rows
    of the crop box and shifts `y1` down if the crop box accidentally includes transparent
    ceiling margin above the indoor wall (preventing the `stage_0_13 医院` black top bar bug!).
    """
    W, H = bg_img.size
    x, y, w, h = crop_box
    px0 = int(round(x * W))
    py0 = int(round(y * H))
    pw = max(64, int(round(w * W)))
    ph = max(32, int(round(h * H)))

    target_aspect = HD_W / HD_H
    # Always honor the horizontal landmark span `pw` so wide `h` values don't blow up `nw`!
    nw = min(float(W), float(pw))
    nh = nw / target_aspect
    if nh > H:
        nh = float(H)
        nw = nh * target_aspect

    cx = px0 + pw / 2.0
    x1 = int(round(cx - nw / 2))
    x2 = int(round(cx + nw / 2))
    if x1 < 0:
        x2 -= x1
        x1 = 0
    if x2 > W:
        x1 = max(0, x1 - (x2 - W))
        x2 = W

    # Initial vertical placement: upper-middle of [py0, py0 + ph]
    cy = py0 + min(float(ph), nh * 1.15) / 2.0
    y1 = int(round(cy - nh / 2))
    y2 = int(round(cy + nh / 2))
    if y1 < 0:
        y2 -= y1
        y1 = 0
    if y2 > H:
        y1 = max(0, y1 - (y2 - H))
        y2 = H

    # Content-Aware Vertical Framing Guard for INDOOR scenes only (`is_indoor=True`)
    if is_indoor and raw_fg is not None:
        check_x2 = max(x1 + 16, min(W, x1 + int((x2 - x1) * 0.68)))
        span_w = max(1, check_x2 - x1)
        fg_crop = raw_fg.crop((x1, 0, check_x2, H))
        fg_px = fg_crop.load()

        # Find the first row `y_solid` from top where >= threshold of horizontal landmark span is opaque & non-dead-black
        thresh = 0.88
        y_solid = 0
        for ty in range(0, H - 4, 2):
            good = 0
            for tx in range(0, span_w, 2):
                r, g, b, a = fg_px[tx, ty]
                if a >= 180 and (r > 24 or g > 24 or b > 26):
                    good += 1
            if (good / max(1, (span_w + 1) // 2)) >= thresh:
                y_solid = ty
                break

        min_y1 = y_solid
        # In tall (>1000px) Noah indoor scenes (`nyqxjd*`), the top 27% is a dark ceiling overhang above the room wall
        if H > 1000:
            min_y1 = max(min_y1, int(round(H * 0.27)))

        if y1 < min_y1:
            y1 = min(min_y1, max(0, H - int(round(nh))))
            y2 = min(H, y1 + int(round(nh)))

    cropped = bg_img.crop((x1, y1, max(x1 + 1, x2), max(y1 + 1, y2)))
    return cropped.resize((HD_W, HD_H), Image.Resampling.LANCZOS)


# Regional Color Grading Profiles
REGION_GRADING = {
    "基地车库": {
        "brightness": 0.92,
        "contrast": 1.08,
        "saturation": 0.88,
        "overlay": (18, 16, 14, 14),
        "vignette_rgb": (10, 10, 12),
    },
    "黑铁会总部": {
        "brightness": 0.90,
        "contrast": 1.10,
        "saturation": 0.88,
        "overlay": (16, 12, 18, 16),
        "vignette_rgb": (10, 8, 12),
    },
    "地下2层": {
        "brightness": 0.90,
        "contrast": 1.10,
        "saturation": 0.88,
        "overlay": (12, 16, 20, 16),
        "vignette_rgb": (8, 10, 14),
    },
    "基地房顶": {
        "brightness": 0.92,
        "contrast": 1.09,
        "saturation": 0.88,
        "overlay": (22, 18, 12, 16),
        "vignette_rgb": (12, 10, 8),
    },
    "诺亚前线基地深处": {
        "brightness": 0.90,
        "contrast": 1.10,
        "saturation": 0.88,
        "overlay": (10, 18, 20, 16),
        "vignette_rgb": (6, 10, 14),
    },
    "雪山": {
        "brightness": 0.93,
        "contrast": 1.08,
        "saturation": 0.90,
        "overlay": (12, 18, 26, 14),
        "vignette_rgb": (8, 12, 18),
    },
}


def grade_background(
    bg_img: Image.Image,
    brightness: float = 0.90,
    contrast: float = 1.08,
    saturation: float = 0.88,
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
    start_x_ratio: float = 0.46,
    max_alpha: int = 165,
    tint_rgb: tuple[int, int, int] = (8, 8, 12),
    top_bottom_vignette: int = 28,
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


def prepare_chiaroscuro_bust(
    sp_name: str,
    flip_x: bool = True,
    brightness: float = 0.95,
    contrast: float = 1.15,
    saturation: float = 0.94,
    dir_shadow_strength: float = 0.24,
    ambient_tint: tuple[int, int, int] = (20, 20, 18),
    tint_strength: float = 0.06,
    macro_upper_crop: bool = True,
) -> Image.Image:
    sp_raw = Image.open(RAW_MONSTER_DIR / f"{sp_name}_bust.png").convert("RGBA")
    bbox = sp_raw.getchannel("A").getbbox()
    if bbox:
        sp_raw = sp_raw.crop(bbox)

    # Macro Head-and-Shoulder Zoom for all humanoid half-body busts:
    # Even when a character holds a horizontal rifle/blade (making width ~= height),
    # any humanoid bust (`height >= 330`) has waist/hips in the bottom 36%.
    # Cropping to the upper 64% zooms straight into the Head, Goggles/Beret, Shoulders, and Weapon!
    is_non_humanoid_crawler = any(k in sp_name for k in ("无人机", "基因虫", "三头犬", "猎犬"))
    if macro_upper_crop and (not is_non_humanoid_crawler) and sp_raw.height >= 330:
        crop_h = max(64, int(round(sp_raw.height * 0.64)))
        sp_upper = sp_raw.crop((0, 0, sp_raw.width, crop_h))
        ubbox = sp_upper.getchannel("A").getbbox()
        if ubbox:
            sp_raw = sp_upper.crop(ubbox)

    rgb = sp_raw.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    if tint_strength > 0:
        rgb = Image.blend(rgb, Image.new("RGB", rgb.size, ambient_tint), tint_strength)
    sp = Image.merge("RGBA", (*rgb.split(), sp_raw.getchannel("A")))

    if flip_x:
        sp = sp.transpose(Image.Transpose.FLIP_LEFT_RIGHT)

    w, h = sp.size
    px = sp.load()
    for y in range(h):
        ny = y / h
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            nx = x / w
            right_shade = max(0.0, (nx - 0.64) / 0.36) * dir_shadow_strength
            bottom_shade = max(0.0, (ny - 0.76) / 0.24) * (dir_shadow_strength * 0.55)
            mult = max(0.46, 1.0 - right_shade - bottom_shade)
            px[x, y] = (int(r * mult), int(g * mult), int(b * mult), a)

    pad = 28
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    sh_a = sp.getchannel("A").point(lambda a: int(a * 0.85)).filter(ImageFilter.GaussianBlur(11))
    sh_layer = Image.new("RGBA", sp.size, (6, 8, 10, 255))
    sh_layer.putalpha(sh_a)
    canvas.alpha_composite(sh_layer, (pad - 6, pad + 3))
    canvas.alpha_composite(sp, (pad, pad))
    return canvas


def paste_bust_anchored(
    canvas: Image.Image,
    sp: Image.Image,
    scale_h_ratio: float,
    anchor_xy: tuple[float, float],
    target_xy: tuple[float, float],
):
    target_h = int(round(HD_H * scale_h_ratio))
    target_w = max(1, int(round(sp.width * (target_h / sp.height))))
    sp_scaled = sp.resize((target_w, target_h), Image.Resampling.LANCZOS)
    px = int(round(target_xy[0] * HD_W - anchor_xy[0] * target_w))
    py = int(round(target_xy[1] * HD_H - anchor_xy[1] * target_h))
    canvas.alpha_composite(sp_scaled, (px, py))
    render_audit.record(sp_scaled,px,py)
