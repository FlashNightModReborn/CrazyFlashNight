#!/usr/bin/env python3
"""Build stage-5 picture 1743 R2 from the frozen editable R1 frame.

The frame is native SVG geometry. The flowers and foliage are individually
cropped, contour-masked and rearranged from a credited high-resolution
public-domain source, inside the original oval. This is a hybrid reconstruction,
not an identification of the game's original painting and not a claim that its
raster paint was hand-drawn here.

Run after decor.py, before assemble_interior.py. This script never writes 1742,
the statue, or any other game part. All inputs are bundled for offline rebuilds.
"""

from pathlib import Path
from xml.etree import ElementTree as ET
import base64
import hashlib
import json
import argparse

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from svg_native import write_part, render

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "reference"
PRE = ROOT / "previews"
QA = ROOT / "qa"
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def node(tag, attributes=None, text=None):
    element = ET.Element(f"{{{NS}}}{tag}", attributes or {})
    if text is not None:
        element.text = text
    return element


def id_node(root, ident):
    return next(element for element in root.iter() if element.get("id") == ident)


def reextract(source_path):
    """Optionally regenerate every bundled crop from the audited full source.

    Normal offline rebuilds do not need the full museum download. Its recorded
    hash and exact original-pixel crop rectangles support later source audits.
    """
    specification = json.loads((REF / "painting-r2-source.json").read_text())
    if digest(source_path) != specification["source_original_sha256"]:
        raise ValueError("The full source does not match the audited NGA image")
    source = Image.open(source_path).convert("RGB")
    for tile in specification["tiles"]:
        output = ROOT / tile["file"]
        source.crop(tuple(tile["source_crop_pixels"])).save(
            output, quality=95, subsampling=0, optimize=True)
        if digest(output) != tile["sha256"]:
            raise ValueError(f"Re-extracted crop differs from bundled input: {output.name}")


def tile_element(tile):
    source = ROOT / tile["file"]
    if digest(source) != tile["sha256"]:
        raise ValueError(f"Bundled painting crop changed: {source.name}")
    x, y, width, height = tile["dest"]
    _, _, vw, vh = tile["local_viewbox"]
    group = node("g", {"id": "floral-detail-" + tile["id"],
        "transform": f"translate({x} {y}) rotate({tile['rotation_degrees']} {width/2} {height/2})",
        "opacity": str(tile["opacity"])})
    viewport = node("svg", {"x": "0", "y": "0", "width": str(width),
        "height": str(height), "viewBox": f"0 0 {vw} {vh}",
        "preserveAspectRatio": "none", "overflow": "visible"})
    image = node("image", {"id": "crop-image-" + tile["id"], "x": "0", "y": "0", "width": str(vw), "height": str(vh),
        "preserveAspectRatio": "none", "href": "data:image/jpeg;base64," +
        base64.b64encode(source.read_bytes()).decode()})
    defs = node("defs")
    defs.append(image)
    show = node("use", {"href": "#crop-image-" + tile["id"]})
    if tile["clip_path"]:
        clip = node("clipPath", {"id": "flower-contour-" + tile["id"],
                                 "clipPathUnits": "userSpaceOnUse"})
        clip.append(node("path", {"d": tile["clip_path"]}))
        defs.append(clip)
        show.set("clip-path", "url(#flower-contour-" + tile["id"] + ")")
    if tile.get("tonal_alpha"):
        mask = node("mask", {"id": "flower-matte-" + tile["id"], "maskUnits": "userSpaceOnUse",
            "x": "0", "y": "0", "width": str(vw), "height": str(vh)})
        mask.append(node("use", {"href": "#crop-image-" + tile["id"],
            "filter": "url(#r2FoliageAlpha)" if tile["tonal_alpha"] == "foliage" else "url(#r2FlowerAlpha)"}))
        defs.append(mask)
        show.set("mask", "url(#flower-matte-" + tile["id"] + ")")
    if tile["id"] == "vase-texture":
        show.set("filter", "url(#r2CoolVase)")
    if tile["id"] == "stone-texture":
        show.set("filter", "url(#r2WarmStone)")
    viewport.append(defs)
    image = show
    viewport.append(image)
    group.append(viewport)
    return group


def fragment(xml):
    return ET.fromstring(f'<g xmlns="{NS}">' + xml + '</g>')


def painting():
    """Recompose actual flower details inside the frozen R1 oval and frame."""
    specification = json.loads((REF / "painting-r2-source.json").read_text())
    frozen_path = REF / "r1-painting.svg"
    frozen = ET.parse(frozen_path).getroot()
    root = ET.fromstring(ET.tostring(frozen))
    if root.attrib != {"viewBox": "0 0 72 89"}:
        raise ValueError("The frozen R1 canvas changed; do not guess registration")
    group = id_node(root, "flower-oil-painting")
    for child in list(group):
        group.remove(child)
    group.append(node("desc", text=specification["description"]))
    group.append(tile_element(specification["tiles"][0]))
    base = fragment('''<defs>
      <filter id="r2FlowerAlpha" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1.02048 3.43296 .34656 0 -.50"/></filter>
      <filter id="r2FoliageAlpha" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1.4882 5.0064 .5054 0 -.48"/></filter>
      <filter id="r2CoolVase" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values=".14 .45 .05 0 .045  .13 .42 .05 0 .042  .17 .52 .06 0 .065  0 0 0 1 0"/></filter>
      <filter id="r2WarmStone" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values=".78 .16 .04 0 0  .32 .52 .07 0 0  .18 .16 .35 0 0  0 0 0 1 0"/></filter>
      <clipPath id="r2VaseBody"><path d="M30.1 52.7C30.4 51.5 40.2 51.5 41.4 52.7C41.2 55.9 40.1 59.3 37.8 60.1L33.7 60C31.2 58.7 30.4 56.1 30.1 52.7Z"/></clipPath>
      <radialGradient id="r2OilField" cx=".44" cy=".34" r=".8"><stop stop-color="#33382a"/><stop offset=".55" stop-color="#20271e"/><stop offset="1" stop-color="#171a14"/></radialGradient>
      <linearGradient id="r2StoneTable" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#716443"/><stop offset=".15" stop-color="#645538"/><stop offset=".55" stop-color="#51452f"/><stop offset="1" stop-color="#30281d"/></linearGradient>
      <linearGradient id="r2VaseGlaze"><stop stop-color="#292b34"/><stop offset=".18" stop-color="#4b4b59"/><stop offset=".39" stop-color="#696774"/><stop offset=".61" stop-color="#555663"/><stop offset=".84" stop-color="#3c404a"/><stop offset="1" stop-color="#2c3038"/></linearGradient>
      <linearGradient id="r2VaseFoot" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#676274"/><stop offset=".45" stop-color="#454251"/><stop offset="1" stop-color="#25252b"/></linearGradient>
    </defs>
    <ellipse id="dark-ground-glaze" cx="36" cy="45.2" rx="20.5" ry="28.7" fill="url(#r2OilField)" opacity=".72"/>
    <g id="reconstructed-stone-ledge">
      <path d="M14 61.1C28 60.1 43 60.7 59 60.1L59 78H14Z" fill="url(#r2StoneTable)"/>
      <path d="M15 62.1Q33 61.3 56 61.9" fill="none" stroke="#8e7951" stroke-width=".45" opacity=".67"/>
      <path d="M16 67.3Q38 68 55 66.9M18 69.6Q38 70.8 53 69.2" fill="none" stroke="#2f2a20" stroke-width=".3" opacity=".48"/>
      <path d="M18 64.4L22.4 64.2M39 64L44 64.2M26 66.6L33 66.3M46 69.1L49 68.8" fill="none" stroke="#a48b59" stroke-width=".14" opacity=".42"/>
    </g>
    <g id="botanical-connective-stems" fill="none" stroke-linecap="round">
      <path d="M35.7 54.4C33.8 44.9 33.6 36.3 34.6 26.6M35.8 54.5C37.2 48 39 40.7 41 34.1M35.8 55Q30.1 46.9 26.2 35.2M36 53.9Q42 46.9 46.4 41.2M35.7 53.9Q27.4 49.3 23.9 46.7" stroke="#454c2b" stroke-width=".62"/>
      <path d="M35.4 52.9C33.8 44.9 33.3 36.3 34.3 27.1M35.6 52.2C37.4 45 38.6 39.9 40.7 35.1M34.6 51.1Q29.9 44 26.1 35.4" stroke="#89865a" stroke-width=".18" opacity=".6"/>
    </g>
    <g id="authored-blue-gray-vase">
      <ellipse cx="35.8" cy="60.8" rx="8.8" ry="1.1" fill="#211e19" opacity=".76"/>
      <path d="M30.1 52.7C30.4 51.5 40.2 51.5 41.4 52.7C41.2 55.9 40.1 59.3 37.8 60.1L33.7 60C31.2 58.7 30.4 56.1 30.1 52.7Z" fill="url(#r2VaseGlaze)"/>
      <ellipse cx="35.8" cy="52.7" rx="5.6" ry="1.18" fill="#222b28"/>
      <path d="M30.3 52.7C31.4 53.8 39.1 54 41.3 52.7" stroke="#8b8490" stroke-width=".25" fill="none" opacity=".7"/>
      <path d="M31.4 54.2C31.9 56.7 32.6 58.7 33.7 59.4M33.1 54.3Q33.4 56.1 34 57.7" fill="none" stroke="#9d94a0" stroke-width=".38" opacity=".5"/>
      <path d="M38.2 54.2Q39 56.3 37.8 58.3M40.4 53.9Q39.9 57.2 38.9 58.5" fill="none" stroke="#242b3a" stroke-width=".7" opacity=".38"/>
      <path d="M33.6 59.7L38 59.8L39.1 60.7Q35.8 61.2 32.4 60.6Z" fill="url(#r2VaseFoot)"/>
      <path d="M32.9 60.5Q35.4 60.8 38.1 60.6" fill="none" stroke="#9b9090" stroke-width=".16" opacity=".65"/>
    </g>''')
    group.extend(list(base))
    # Historical stone and vase surfaces provide irregular, genuine paint variation.
    for ident in ["stone-texture"]:
        tile = next(t for t in specification["tiles"] if t["id"] == ident)
        overlay = tile_element(tile)
        if ident == "vase-texture":
            wrapper = node("g", {"id": "vase-painterly-surface", "clip-path": "url(#r2VaseBody)"})
            wrapper.append(overlay)
            group.append(wrapper)
        else:
            group.insert(len(group)-1, overlay)
    # Remove regular construction-like highlights and sharpened flat shadows.
    ledge = id_node(group, "reconstructed-stone-ledge")
    for line in list(ledge)[1:]: ledge.remove(line)
    vase = id_node(group, "authored-blue-gray-vase")
    for shape in list(vase):
        if shape.tag.endswith("ellipse") and shape.get("cy") == "60.8":
            shape.set("opacity", ".24")
        if shape.get("stroke") in ["#9d94a0", "#242b3a", "#9b9090"]:
            shape.set("opacity", ".14")
    # Broad glazed turning planes, not pasted foliage or mechanical white bars.
    glaze = fragment('''<defs>
      <radialGradient id="r2VaseSoftLight" cx=".4" cy=".32" r=".67"><stop stop-color="#b4acb0" stop-opacity=".27"/><stop offset=".55" stop-color="#8d8796" stop-opacity=".12"/><stop offset="1" stop-color="#777383" stop-opacity="0"/></radialGradient>
      <radialGradient id="r2VaseLowReflection"><stop stop-color="#777b8a" stop-opacity=".19"/><stop offset="1" stop-color="#777b8a" stop-opacity="0"/></radialGradient>
    </defs><g id="subtle-vase-glazes" clip-path="url(#r2VaseBody)">
      <ellipse cx="33.8" cy="55.2" rx="4.3" ry="6.4" fill="url(#r2VaseSoftLight)"/>
      <ellipse cx="37.7" cy="59.1" rx="4.9" ry="2.8" fill="url(#r2VaseLowReflection)"/>
      <path d="M31.1 54.2Q31.6 56.8 32.5 58.1M32.8 56.2L33 56.8M33.1 57.1L33.4 57.6M31.5 55.2L31.7 55.7" fill="none" stroke="#c4b6b7" stroke-width=".11" stroke-linecap="round" opacity=".27"/>
      <path d="M39.8 54.6Q39.6 56.7 38.8 58M38.1 58.2L37.6 58.9M34.3 59.4L35.1 59.6M35 54.3L35.6 54.4" fill="none" stroke="#202833" stroke-width=".16" stroke-linecap="round" opacity=".22"/>
    </g>''')
    vase.insert(2, glaze)
    for shape in list(vase):
        if shape.get("stroke") in ["#9d94a0", "#242b3a", "#9b9090"]:
            vase.remove(shape)
    for tile in specification["tiles"][1:]:
        if tile["layer"] not in ["vase", "stone"]:
            group.append(tile_element(tile))
    # A few distinct, dark finishing leaves join the bouquet into the vase mouth.
    finishing = fragment('''<g id="foreground-leaf-bridges">
      <path d="M34.4 27.1Q34.8 28.1 34.5 29.4" fill="none" stroke="#77784c" stroke-width=".29"/>
      <path d="M34.6 28.5Q32.9 28.4 32.4 27.4Q34.1 27.1 34.6 28.5Z" fill="#3a482e"/>
      <path d="M31.3 54.2C28.7 54.6 27.5 53.6 26.1 51.2C28.7 51 30.2 52.6 31.3 54.2Z" fill="#344531"/>
      <path d="M39.7 53.7C41.7 53.6 43.2 52.4 44.2 50.9C41.9 50.9 40.7 52 39.7 53.7Z" fill="#263a2c"/>
      <path d="M31 54Q28.6 53.1 26.6 51.7M40.1 53.5L43.5 51.4" stroke="#71714c" stroke-width=".14" fill="none"/>
    </g>''')
    group.extend(list(finishing))
    root.find(f"{{{NS}}}title").text = "CF6 1743 R2: recomposed Dutch floral detail in editable carved frame"
    root.find(f"{{{NS}}}desc").text = specification["description"]
    root.insert(2, node("metadata", {"id": "painting-r2-provenance"},
                        json.dumps(specification, ensure_ascii=False, sort_keys=True)))
    part = write_part(ROOT / "parts/bitmap-1743.svg", [0, 0, 72, 89],
                      "".join(ET.tostring(child, encoding="unicode") for child in root))
    unchanged_ids = ["outer-carved-frame", "oval-raised-gold-surround",
                     "chased-edge-highlights", "pictureOval"]
    unchanged = {ident: ET.tostring(id_node(root, ident)) ==
                       ET.tostring(id_node(frozen, ident)) for ident in unchanged_ids}
    if not all(unchanged.values()):
        raise AssertionError("An R1 frame or clipping group changed unexpectedly")
    return part, specification, unchanged


def font(size):
    return ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", size)


def paste_rgba(board, picture, position):
    picture = picture.convert("RGBA")
    board.paste(picture, position, picture)


def previews(part, specification, unchanged):
    PRE.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    original = Image.open(REF / "bitmap-1743-original.png").convert("RGBA")
    r1_path = REF / "r1-painting.svg"
    for scale in [1, 4, 8, 16]:
        render(part, 72 * scale, PRE / f"painting-r2-{scale}x.png")
    for scale in [1, 8]:
        render(r1_path, 72 * scale, PRE / f"painting-r1-{scale}x.png")
    r1_1x = Image.open(PRE / "painting-r1-1x.png").convert("RGBA")
    r2_1x = Image.open(PRE / "painting-r2-1x.png").convert("RGBA")

    # All panels have identical canvas extent, with no changes to registration.
    scale, margin, header = 8, 20, 64
    tile_width, tile_height = 72 * scale, 89 * scale
    board = Image.new("RGB", (tile_width * 3 + margin * 4,
                             tile_height + header + 76), "#292722")
    draw = ImageDraw.Draw(board)
    pictures = [original.resize((tile_width, tile_height), Image.Resampling.NEAREST),
                Image.open(PRE / "painting-r1-8x.png"),
                Image.open(PRE / "painting-r2-8x.png")]
    labels = ["原图 · 同尺度8倍 · 最近邻", "R1 · 同尺度8倍 · 原生渲染",
              "R2 · 同尺度8倍 · 高清画心+原框"]
    for index, (picture, label) in enumerate(zip(pictures, labels)):
        x = margin + index * (tile_width + margin)
        draw.text((x, 17), label, font=font(23), fill="#f2eadb")
        paste_rgba(board, picture, (x, header))
    draw.text((margin, header + tile_height + 15),
              "均保持72×89原始边界、椭圆位置与注册；R2为开放高清画心+可编辑矢量画框。",
              font=font(20), fill="#d6cdbf")
    board.save(PRE / "painting-original-r1-r2-8x.png")

    # True asset-pixel view: do not scale these 72 x 89 images to fill the card.
    native = Image.new("RGB", (620, 200), "#292722")
    native_draw = ImageDraw.Draw(native)
    for x, label, picture in [(56, "原图 72×89", original),
                              (254, "R1 72×89", r1_1x),
                              (452, "R2 72×89", r2_1x)]:
        native_draw.text((x - 18, 16), label, font=font(18), fill="#f2eadb")
        paste_rgba(native, picture, (x, 52))
    native_draw.text((20, 161), "1:1像素对比；图片本身未放大。", font=font(17), fill="#d6cdbf")
    native.save(PRE / "painting-original-r1-r2-1x.png")

    # Isolate the oval center at 16x, retaining a little frame for visual context.
    high = Image.open(PRE / "painting-r2-16x.png")
    high.crop((14 * 16, 15 * 16, 58 * 16, 75 * 16)).save(
        PRE / "painting-r2-center-16x.png")

    alpha_error = int(np.abs(np.asarray(original.getchannel("A")).astype(int) -
                             np.asarray(r2_1x.getchannel("A")).astype(int)).max())
    if alpha_error:
        raise AssertionError(f"Original alpha changed, max error: {alpha_error}")
    # R2 raster samples must be bit-identical to R1 safely outside the oval.
    yy, xx = np.mgrid[0:89, 0:72]
    outside = ((xx + .5 - 36) / 20.2) ** 2 + ((yy + .5 - 45.2) / 28.3) ** 2 > 1.12
    outside_error = int(np.abs(np.asarray(r1_1x).astype(int) -
                               np.asarray(r2_1x).astype(int))[outside].max())
    report = {
        "asset": "1743", "revision": "R2", "native_size": [72, 89],
        "viewBox": [0, 0, 72, 89], "registration_changed": False,
        "unchanged_R1_groups": unchanged,
        "outside_oval_R1_R2_max_absolute_error": outside_error,
        "original_R2_alpha_max_absolute_error": alpha_error,
        "composition": "High-resolution source crops with editable contours, edge mattes and individual placement; unique botanical details rearranged within the unchanged oval.",
        "construction": "Hybrid: editable native SVG frame, ground, stems, table and vase; individually clipped high-resolution public-domain botanical details.",
        "filters": "Editable tonal-alpha edge mattes plus a stone color matrix. No blur, sharpening, posterization or traced-pixel detail.",
        "source": specification,
        "frozen_R1_sha256": digest(r1_path), "R2_svg_sha256": digest(part),
    }
    (QA / "painting-r2-construction.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2))
    if outside_error:
        raise AssertionError(f"Frame pixels changed outside the oval: {outside_error}")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reextract", type=Path,
                        help="Regenerate audited crops from the matching full NGA JPEG")
    parser.add_argument("--part-only", action="store_true",
                        help="Build only the SVG; skip comparison PNGs and QA report")
    arguments = parser.parse_args()
    if arguments.reextract:
        reextract(arguments.reextract)
    output, specification, unchanged = painting()
    print(output)
    if not arguments.part_only:
        report = previews(output, specification, unchanged)
        print(json.dumps({key: report[key] for key in [
            "native_size", "outside_oval_R1_R2_max_absolute_error",
            "original_R2_alpha_max_absolute_error"]}, ensure_ascii=False))
