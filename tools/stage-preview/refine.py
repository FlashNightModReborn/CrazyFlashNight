"""Targeted, source-preserving composition changes for the stage-preview review.

The inputs remain native Flash exports and the production portrait catalog.  This
module changes placement and grading; it does not repaint character anatomy.
"""
from copy import deepcopy
from PIL import Image, ImageEnhance
import render_v6_base_gate_all16 as base
import render_v6_6_regions as regions
import render_boss_c2_ab_sheet as bosses


def portrait(canvas, name, *, height=1.2, target=(.84, .5), anchor=(.48, .45),
             flip=True, brightness=.92, macro=False):
    subject = regions.prepare_chiaroscuro_bust(
        name, flip_x=flip, brightness=brightness, contrast=1.1,
        saturation=.9, dir_shadow_strength=.18, macro_upper_crop=macro)
    regions.paste_bust_anchored(canvas, subject, height, anchor, target)


def commercial():
    bg = base.build_outdoor_bg_with_sky("gk7_2_BG", sky_brightness=.85)
    canvas = base.crop_landmark_macro(bg, [.518, .188, .175, .148])
    canvas = base.grade_background(canvas, brightness=.86, contrast=1.10, saturation=.72)
    canvas = base.apply_directional_vignette(canvas, start_x_ratio=.54, max_alpha=95,
                                            top_bottom_vignette=20)
    # Preserve the original eyes, cheek, nose, mouth and hood ink lines.  The old
    # procedural face replacement destroyed those features before upscaling.
    portrait(canvas, "敌人-帽子瘦僵尸1", height=2.45, target=(.78, .42),
             anchor=(.25, .39), brightness=.68)
    return canvas


def shantytown():
    bg = base.build_outdoor_bg_with_sky("gk9_2_BG", sky_brightness=.84)
    canvas = base.crop_landmark_macro(bg, [.178, .255, .23, .25])
    canvas = base.grade_background(canvas, brightness=.94, contrast=1.1, saturation=.84)
    canvas = base.apply_directional_vignette(canvas, start_x_ratio=.57, max_alpha=130,
                                            top_bottom_vignette=20)
    portrait(canvas, "敌人-裸体兽化僵尸1", height=1.12, target=(.71, .53), brightness=.75)
    portrait(canvas, "敌人-士兵奔跑僵尸1", height=1.3, target=(.89, .53))
    return canvas


def ringroad():
    canvas=base.crop_landmark_macro(base.build_ringroad_parallax_bg(),[.135,.09,.34,.56])
    canvas=base.grade_background(canvas,brightness=.94,contrast=1.08,saturation=.88,
                                 color_overlay=(18,18,10,14))
    canvas=base.apply_directional_vignette(canvas,start_x_ratio=.55,max_alpha=130,top_bottom_vignette=20)
    portrait(canvas,"敌人-光头军人僵尸1",height=1.06,target=(.69,.52),brightness=.75)
    portrait(canvas,"敌人-兽化变种",height=1.32,target=(.88,.51),brightness=.91)
    return canvas


def normal(entry, environment):
    """Compose explicit per-subject layouts; no implicit upper-64% crop."""
    config = entry["composition"]
    if config.get("source_png"):
        fg = Image.open(regions.PILOT_DIR / config["source_png"]).convert("RGBA")
        if fg.getchannel("A").getbbox():
            fg = fg.crop(fg.getchannel("A").getbbox())
        bg = Image.new("RGBA", fg.size, (16,18,22,255))
        bg.alpha_composite(fg)
        indoor = True
    else:
        bg, fg, indoor = regions.build_stage_bg_canvas(config["selected_bg"], entry["region"], environment)
    if config.get("crop_bounds"):
        x1,y1,x2,y2 = config["crop_bounds"]
        box=(round(x1*bg.width),round(y1*bg.height),round(x2*bg.width),round(y2*bg.height))
        if not (0 <= box[0] < box[2] <= bg.width and 0 <= box[1] < box[3] <= bg.height):
            raise ValueError(f"Out-of-bounds landmark crop: {entry['id']} {box}")
        aspect=(box[2]-box[0])/(box[3]-box[1])
        if abs(aspect-644/276)>.025:
            raise ValueError(f"Landmark crop must preserve aspect ratio: {entry['id']} {aspect}")
        canvas=bg.crop(box).resize((644,276),Image.Resampling.LANCZOS)
    else:
        canvas = regions.crop_landmark_safe(bg, fg, config["crop_box"], indoor)
    grade = regions.REGION_GRADING.get(entry["region"], regions.REGION_GRADING["基地车库"])
    canvas = regions.grade_background(
        canvas, brightness=config.get("brightness", min(.97, grade["brightness"]+.04)),
        contrast=grade["contrast"], saturation=min(.95, grade["saturation"]+.04))
    layouts = config.get("layouts", [])
    canvas = regions.apply_directional_vignette(
        canvas, start_x_ratio=.58 if layouts else .80,
        max_alpha=115 if layouts else 25, top_bottom_vignette=18,
        tint_rgb=grade["vignette_rgb"])
    for item in layouts:
        portrait(canvas, item["spritename"], height=item.get("height", 1.1),
                 target=tuple(item.get("target", [.85,.5])),
                 anchor=tuple(item.get("anchor", [.48,.45])),
                 flip=item.get("flip", True), brightness=item.get("brightness", .92),
                 macro=item.get("macro", False))
    return canvas


def base_layout(entry):
    config = entry["composition"]
    if config.get("outdoor"):
        bg = base.build_outdoor_bg_with_sky(config["bg_stem"], sky_brightness=.86)
    else:
        bg = base.find_raw_ffdec_png(config["bg_stem"])
    canvas = base.crop_landmark_macro(bg, config["crop_box"])
    canvas = base.grade_background(canvas, brightness=.92, contrast=1.08, saturation=.86)
    canvas = base.apply_directional_vignette(canvas, start_x_ratio=.56, max_alpha=115,
                                            top_bottom_vignette=20)
    for item in config["layouts"]:
        portrait(canvas, item["spritename"], height=item["height"],
                 target=tuple(item["target"]), brightness=item.get("brightness",.92))
    return canvas


def boss(entry, environment, original_entry):
    spec = deepcopy(entry["boss"])
    bg = bosses.prepare_boss_bg(original_entry, spec, environment)
    return bosses.build_variant_canvas(bg, spec, spec["col_"+entry.get("variant","A").lower()])


def render(entry, environment, original_entry):
    mode = entry.get("renderer")
    if mode == "commercial":
        return commercial()
    if mode == "shantytown":
        return shantytown()
    if mode == "ringroad":
        return ringroad()
    if mode == "normal":
        return normal(entry, environment)
    if mode == "base_layout":
        return base_layout(entry)
    if mode == "boss":
        return boss(entry, environment, original_entry)
    raise ValueError(f"Unknown refinement renderer for {entry['id']}: {mode}")
