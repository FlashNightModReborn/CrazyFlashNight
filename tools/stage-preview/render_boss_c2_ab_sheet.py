#!/usr/bin/env python3
"""Native pose composition helpers. Geometric placement is separate from human art acceptance."""

import colorsys
import math
from pathlib import Path
import render_audit
from PIL import Image, ImageFilter

from render_v6_6_regions import (HD_H, HD_W, PILOT_DIR, apply_directional_vignette,
    build_stage_bg_canvas, crop_landmark_safe, grade_background)

HIRES_DIR = PILOT_DIR / "boss_hires_poses"


def find_hires_frame(folder_name: str, frame_1based: int) -> Path:
    base = HIRES_DIR / folder_name
    matches = sorted(base.rglob(f"{frame_1based}.png"))
    if len(matches) != 1:
        raise FileNotFoundError(f"Expected one native frame {frame_1based} in {base}; found {len(matches)}")
    return matches[0]


def is_in_sig_hue(deg: float, sig_hues: list[tuple[float, float]]) -> bool:
    for h0, h1 in sig_hues:
        if h0 <= h1:
            if h0 <= deg <= h1:
                return True
        else:
            if deg >= h0 or deg <= h1:
                return True
    return False


def apply_single_signature_color_and_rim(
    sp_im: Image.Image,
    sig_hues: list[tuple[float, float]],
    rim_rgb: tuple[int, int, int] = (235, 242, 255),
    non_sig_sat_mult: float = 0.62,
    sig_sat_mult: float = 1.18,
    ninja_cloak_grade: bool = False,
) -> Image.Image:
    """
    Authentic 2D Flash vector post-processing (ZERO cheap bevel filter!):
    1. NEVER composites any offset-subtracted rim layer on top of `sp`!
       100% of the sprite's native black vector ink outlines remain untouched and razor-sharp.
    2. Single Signature Color (`单一标志色`):
       - Preserves/boosts pixels in `sig_hues` (`sig_sat_mult`), while gently desaturating non-signature hues.
    3. Soft Atmospheric Backlight (`主体轮廓光` — placed strictly BEHIND `sp` on the background layer):
       - A soft Gaussian backlight glow + grounding shadow rendered UNDERNEATH `sp` so the dark ink silhouette
         separates cleanly from the darkened background without any sticker/bevel artifact.
    """
    sp = sp_im.convert("RGBA")
    w, h = sp.size
    px = sp.load()

    emissive = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    em_px = emissive.load()

    for y in range(h):
        yf = y / max(1, h - 1)
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue

            rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
            hv, lv, sv = colorsys.rgb_to_hls(rf, gf, bf)
            deg = hv * 360.0

            # Keep native black ink lines (< 0.12 lightness) crisp and untouched
            if lv < 0.11:
                px[x, y] = (r, g, b, a)
                continue

            in_sig = sv >= 0.10 and is_in_sig_hue(deg, sig_hues)

            # Special grading for Ninja Boss cloaked form (`c1382/144.png`) to 1:1 match Original `stage_34_5`:
            # Darken the helmet dome into deep stealth charcoal while keeping the 4 red eyes blazing,
            # and tone the white cloak collar into gunmetal grey with black buttons intact.
            if ninja_cloak_grade:
                if in_sig and sv > 0.35:
                    ns = min(1.0, sv * 1.30)
                    nl = min(0.95, lv * 1.12)
                    nr, ng, nb = colorsys.hls_to_rgb(hv, nl, ns)
                    ir, ig, ib = int(nr * 255), int(ng * 255), int(nb * 255)
                    px[x, y] = (ir, ig, ib, a)
                    em_px[x, y] = (ir, ig, ib, min(220, int(a * 0.85)))
                    continue
                elif yf < 0.145:
                    nl = lv * 0.34
                    nr, ng, nb = colorsys.hls_to_rgb(hv, nl, sv * 0.30)
                    px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
                    continue
                else:
                    nl = lv * 0.46
                    nr, ng, nb = colorsys.hls_to_rgb(hv, nl, sv * 0.20)
                    px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
                    continue

            if in_sig:
                ns = min(1.0, sv * sig_sat_mult)
                nl = min(0.96, lv)
                nr, ng, nb = colorsys.hls_to_rgb(hv, nl, ns)
                ir = min(255, max(0, int(round(nr * 255))))
                ig = min(255, max(0, int(round(ng * 255))))
                ib = min(255, max(0, int(round(nb * 255))))
                px[x, y] = (ir, ig, ib, a)
                if sv > 0.45 and lv > 0.32:
                    em_a = min(160, int(a * sv * 0.45))
                    em_px[x, y] = (ir, ig, ib, em_a)
            else:
                ns = sv * non_sig_sat_mult
                nl = min(0.95, max(0.04, lv))
                nr, ng, nb = colorsys.hls_to_rgb(hv, nl, ns)
                px[x, y] = (
                    min(255, max(0, int(round(nr * 255)))),
                    min(255, max(0, int(round(ng * 255)))),
                    min(255, max(0, int(round(nb * 255)))),
                    a,
                )

    alpha = sp.getchannel("A")
    pad = 22
    out = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))

    # 1. Deep grounding ambient shadow BEHIND the subject
    sh_a = alpha.point(lambda a: int(a * 0.78)).filter(ImageFilter.GaussianBlur(10))
    sh_layer = Image.new("RGBA", (w, h), (4, 6, 10, 255))
    sh_layer.putalpha(sh_a)
    out.alpha_composite(sh_layer, (pad + 4, pad + 3))

    # 2. Soft atmospheric backlight (`主体轮廓光`) strictly BEHIND `sp` (never painted over `sp`!)
    aura_a = alpha.point(lambda a: int(a * 0.36)).filter(ImageFilter.GaussianBlur(13.0))
    aura_layer = Image.new("RGBA", (w, h), (*rim_rgb, 255))
    aura_layer.putalpha(aura_a)
    out.alpha_composite(aura_layer, (pad - 3, pad - 1))

    rim_back_a = alpha.point(lambda a: int(a * 0.52)).filter(ImageFilter.GaussianBlur(3.2))
    rim_back_layer = Image.new("RGBA", (w, h), (*rim_rgb, 255))
    rim_back_layer.putalpha(rim_back_a)
    out.alpha_composite(rim_back_layer, (pad - 2, pad - 1))

    # 3. Composite the untouched vector sprite `sp` ON TOP (100% native black ink outlines preserved!)
    out.alpha_composite(sp, (pad, pad))

    # 4. Subtle optical bloom only on true emissive pixels (glowing eyes / flame cores)
    em_blur = emissive.filter(ImageFilter.GaussianBlur(5.0))
    out.alpha_composite(em_blur, (pad, pad))
    return out


def crop_and_orient_subject(im_src: Image.Image, flip_x: bool = False) -> Image.Image:
    """Trim transparent padding only; preserve the native pose pixels."""
    im = im_src.convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if bbox:
        im = im.crop(bbox)
    if flip_x:
        im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return im


def place_subject_on_canvas(
    canvas: Image.Image,
    subj: Image.Image,
    scale_h: float = 1.20,
    max_w_ratio: float = 1.80,
    anchor_xy: tuple[float, float] = (0.50, 0.50),
    target_xy: tuple[float, float] = (0.72, 0.52),
    top_y: float | None = None,
    visible_ry: float | None = None,
    ry_range: tuple[float, float] | None = None,
    rx_right_edge: float | None = None,
) -> Image.Image:
    bbox = subj.getchannel("A").getbbox()
    if bbox:
        subj = subj.crop(bbox)
    cw, ch = subj.size

    if ry_range is not None:
        ry0, ry1 = ry_range
        th = max(1, int(round(HD_H / max(0.05, ry1 - ry0))))
        tw = max(1, int(round(cw * (th / max(1, ch)))))
        scaled = subj.resize((tw, th), Image.Resampling.LANCZOS)
        py = int(round(-ry0 * th))
        if rx_right_edge is not None:
            px = int(round(HD_W - rx_right_edge * tw))
        else:
            px = int(round(target_xy[0] * HD_W - anchor_xy[0] * tw))
    elif top_y is not None and visible_ry is not None:
        span_h_px = HD_H * (1.03 - top_y)
        th = max(1, int(round(span_h_px / max(0.12, visible_ry))))
        tw = max(1, int(round(cw * (th / max(1, ch)))))
        scaled = subj.resize((tw, th), Image.Resampling.LANCZOS)
        px = int(round(target_xy[0] * HD_W - anchor_xy[0] * tw))
        py = int(round(top_y * HD_H))
    else:
        th = int(round(HD_H * scale_h))
        tw = max(1, int(round(cw * (th / max(1, ch)))))
        max_w = int(round(HD_W * max_w_ratio))
        if tw > max_w:
            tw = max_w
            th = max(1, int(round(ch * (tw / max(1, cw)))))
        scaled = subj.resize((tw, th), Image.Resampling.LANCZOS)
        px = int(round(target_xy[0] * HD_W - anchor_xy[0] * tw))
        py = int(round(target_xy[1] * HD_H - anchor_xy[1] * th))

    out = canvas.copy()
    out.alpha_composite(scaled, (px, py))
    render_audit.record(scaled,px,py)
    return out


def add_radial_light_bloom(
    canvas: Image.Image,
    center_xy: tuple[float, float],
    radius_xy: tuple[float, float],
    rgb: tuple[int, int, int],
    max_alpha: int = 95,
) -> Image.Image:
    """Adds a soft theatrical spotlight / environmental glow onto the background."""
    overlay = Image.new("RGBA", (HD_W, HD_H), (0, 0, 0, 0))
    px = overlay.load()
    cx = center_xy[0] * HD_W
    cy = center_xy[1] * HD_H
    rx = max(1.0, radius_xy[0] * HD_W)
    ry = max(1.0, radius_xy[1] * HD_H)

    for y in range(HD_H):
        dy = (y - cy) / ry
        dy2 = dy * dy
        if dy2 >= 1.0:
            continue
        for x in range(HD_W):
            dx = (x - cx) / rx
            d2 = dx * dx + dy2
            if d2 < 1.0:
                falloff = (1.0 - math.sqrt(d2)) ** 2.1
                a = int(max_alpha * falloff)
                if a > 0:
                    px[x, y] = (*rgb, a)
    return Image.alpha_composite(canvas.convert("RGBA"), overlay)


def prepare_boss_bg(entry: dict, spec: dict, env_by_bg: dict) -> Image.Image:
    """
    Applies focal landmark camera crop (`crop_box_override` / `bg_override`),
    background desaturation & darkening (`背景降饱和压暗`), stage-specific theatrical lighting,
    and right-side directional vignette so the Boss subject pops with maximum tension.
    """
    bg_swf = spec.get("bg_override") or entry["selected_bg"]
    crop_box = spec.get("crop_box_override") or entry["crop_box"]
    region_label = spec["region"]

    bg_canvas, raw_fg, is_indoor = build_stage_bg_canvas(bg_swf, region_label, env_by_bg)
    canvas = crop_landmark_safe(bg_canvas, raw_fg, crop_box, is_indoor)

    bg_grade = spec.get("bg_grade", {})
    canvas = grade_background(
        canvas,
        brightness=bg_grade.get("brightness", 0.72),
        contrast=bg_grade.get("contrast", 1.14),
        saturation=bg_grade.get("saturation", 0.56),
        color_overlay=(10, 12, 18, 22),
    )

    for lgt in spec.get("stage_lights", []):
        canvas = add_radial_light_bloom(
            canvas,
            center_xy=lgt["center"],
            radius_xy=lgt["radius"],
            rgb=lgt["rgb"],
            max_alpha=lgt.get("alpha", 80),
        )

    canvas = apply_directional_vignette(
        canvas,
        start_x_ratio=0.40,
        max_alpha=138,
        tint_rgb=(6, 8, 14),
        top_bottom_vignette=32,
    )
    return canvas


def build_variant_canvas(base_bg, spec, col_cfg):
    if col_cfg["type"] != "hires":
        raise ValueError("Only native selected-frame subjects are supported")
    raw = Image.open(find_hires_frame(col_cfg["folder"], col_cfg["frame"]))
    subject = crop_and_orient_subject(raw, flip_x=col_cfg.get("flip_x", False))
    processed = apply_single_signature_color_and_rim(
        subject, spec["sig_hues"], spec.get("rim_rgb", (235,242,255)),
        non_sig_sat_mult=col_cfg.get("non_sig_sat_mult", .62),
        sig_sat_mult=col_cfg.get("sig_sat_mult", 1.18))
    return place_subject_on_canvas(
        base_bg, processed, scale_h=col_cfg.get("scale_h",1.18),
        max_w_ratio=col_cfg.get("max_w",1.3),
        anchor_xy=col_cfg.get("anchor_xy",(.5,.5)),
        target_xy=col_cfg.get("target_xy",(.72,.52)),
        top_y=col_cfg.get("top_y"), visible_ry=col_cfg.get("visible_ry"),
        ry_range=col_cfg.get("ry_range"), rx_right_edge=col_cfg.get("rx_right_edge"))
