#!/usr/bin/env python3
"""Derive native bullet styles from the editable XFL and published source SWF.

The output is visual data only. Collision areas, frame scripts and bullet
lifecycles remain in AS2. The original two triangle families share a visual.
Piercing single bullets and chain units retain separate authored registration,
tint and glow, with read-only FFDec rasterization of their published first frame.
"""

import argparse
import hashlib
import json
import os
import re
import runpy
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / "flashswf/arts/原版素材库-子弹/LIBRARY"
OUTPUT = ROOT / "data/combat_visuals/bullet_styles.v1.json"
ATLAS = ROOT / "data/combat_visuals/bullets-atlas.png"
ZOOM = 2
NS = "{http://ns.adobe.com/xfl/2008/}"
FAMILIES = (
    ("plain", "普通子弹", "子弹-炮弹与爆炸组/普通子弹.xml",
     "单元体-普通子弹", "联弹/单元体-普通子弹.xml"),
    ("enhanced", "加强普通子弹", "子弹-普通与穿刺组/加强普通子弹.xml",
     "单元体-加强普通子弹", "联弹/单元体-加强普通子弹.xml"),
)
SPRITES = (
    ("pierce", "穿刺子弹", None, "子弹-普通与穿刺组/穿刺子弹.xml"),
    ("secondary-pierce", "次级穿刺子弹", None, "子弹-普通与穿刺组/次级穿刺子弹.xml"),
    ("caseless-pierce", "无壳穿刺子弹", None, "子弹-普通与穿刺组/无壳穿刺子弹.xml"),
    ("pierce-chain", None, "单元体-穿刺子弹", "联弹/单元体-穿刺子弹.xml"),
    ("secondary-pierce-chain", None, "单元体-次级穿刺子弹", "联弹/单元体-次级穿刺子弹.xml"),
    ("caseless-pierce-chain", None, "单元体-无壳穿刺子弹", "联弹/单元体-无壳穿刺子弹.xml"),
)
GUN_CHAIN_PREFIXES = (
    "横向联弹", "横向机枪联弹", "横向手枪联弹",
    "纵向联弹", "纵向机枪联弹", "纵向手枪联弹",
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_symbol(relpath):
    path = LIBRARY / relpath
    if not path.is_file() or not path.resolve().is_relative_to(LIBRARY.resolve()):
        raise ValueError("missing or escaped XFL symbol: " + relpath)
    return ET.parse(path).getroot()


def frame_zero_visual(root):
    visuals = []
    for frame in root.iter(NS + "DOMFrame"):
        if frame.get("index") != "0":
            continue
        elements = frame.find(NS + "elements")
        if elements is None:
            continue
        for element in elements:
            if element.tag == NS + "DOMShape":
                visuals.append(element)
            elif element.tag == NS + "DOMSymbolInstance" and element.get("name") != "area":
                visuals.append(element)
    if len(visuals) != 1:
        raise ValueError("expected one visual in " + root.get("name", "?"))
    return visuals[0]


def polygon(shape):
    fills = list(shape.iter(NS + "SolidColor"))
    edges = list(shape.iter(NS + "Edge"))
    if len(fills) != 1 or len(edges) != 1 or shape.find(".//" + NS + "filters") is not None:
        raise ValueError("unsupported vector shape")
    color = fills[0].get("color")
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color or "") or fills[0].get("alpha", "1") != "1":
        raise ValueError("unsupported fill")
    pairs = re.findall(r"(-?\d+)\s+(-?\d+)", edges[0].get("edges", ""))
    points = []
    for x, y in pairs:
        point = (int(x), int(y))
        if point not in points:
            points.append(point)
    if len(points) != 3 or len(pairs) != 6:
        raise ValueError("first native batch only accepts a solid triangle")
    return points, color.upper()


def visual_style(root, used_sources):
    visual = frame_zero_visual(root)
    transform = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    glow = None
    if visual.tag == NS + "DOMSymbolInstance":
        symbol = visual.get("libraryItemName")
        if not symbol or ".." in Path(symbol).parts:
            raise ValueError("invalid nested visual reference")
        if visual.get("blendMode", "normal") != "normal" or visual.find(NS + "color") is not None:
            raise ValueError("unsupported instance blend or color transform")
        used_sources.add(symbol + ".xml")
        nested = load_symbol(symbol + ".xml")
        visual_shape = frame_zero_visual(nested)
        if visual_shape.tag != NS + "DOMShape":
            raise ValueError("nested visual is not a static shape")
        matrix = visual.find(".//" + NS + "Matrix")
        if matrix is not None:
            transform = tuple(float(matrix.get(key, default)) for key, default in
                              (("a", "1"), ("b", "0"), ("c", "0"),
                               ("d", "1"), ("tx", "0"), ("ty", "0")))
        filter_sets = list(visual.iter(NS + "filters"))
        if len(filter_sets) > 1 or (filter_sets and
                                     (len(filter_sets[0]) != 1 or filter_sets[0][0].tag != NS + "GlowFilter")):
            raise ValueError("unsupported filter stack")
        if filter_sets:
            item = filter_sets[0][0]
            if set(item.attrib) - {"blurX", "blurY", "color"}:
                raise ValueError("unsupported glow settings")
            glow = {
                "color": item.get("color", "#FFFFFF").upper(),
                "blurX": float(item.get("blurX", "4")),
                "blurY": float(item.get("blurY", "4")),
            }
        visual = visual_shape
    points, fill = polygon(visual)
    a, b, c, d, tx, ty = transform
    vertices = [[round(a * x / 20 + c * y / 20 + tx, 6),
                 round(b * x / 20 + d * y / 20 + ty, 6)] for x, y in points]
    return {"verticesPx": vertices, "fill": fill, "glow": glow,
            "registrationPx": [0, 0], "frameIndex": 0}


def collect_source(relpath, used_sources):
    if relpath in used_sources:
        return
    root = load_symbol(relpath)
    used_sources.add(relpath)
    for instance in root.iter(NS + "DOMSymbolInstance"):
        collect_source(instance.get("libraryItemName") + ".xml", used_sources)


def assert_transparent_area():
    # The published first frame includes the invisible collision marker. FFDec
    # never runs scripts: explicitly prove this marker cannot contaminate pixels.
    marker = load_symbol("无AS链接/Symbol 12.xml")
    fills = list(marker.iter(NS + "SolidColor"))
    if len(fills) != 1 or fills[0].get("alpha") != "0":
        raise ValueError("collision marker is no longer fully transparent")
    if list(marker.iter(NS + "LinearGradient")) or list(marker.iter(NS + "RadialGradient")):
        raise ValueError("unsupported collision-marker fill")
    for _, _, _, source in SPRITES[:3]:
        root = load_symbol(source)
        for node in root.iter(NS + "DOMSymbolInstance"):
            if node.get("name") == "area" and node.get("libraryItemName") != "无AS链接/Symbol 13":
                raise ValueError("unreviewed collision marker: " + source)
            if node.get("name") == "area" and (node.find(NS + "color") is not None
                                                  or node.find(NS + "filters") is not None):
                raise ValueError("collision marker has a visual modifier: " + source)
    wrapper = load_symbol("无AS链接/Symbol 13.xml")
    references = list(wrapper.iter(NS + "DOMSymbolInstance"))
    if len(references) != 1 or references[0].get("libraryItemName") != "无AS链接/Symbol 12":
        raise ValueError("collision-marker wrapper changed")
    if list(wrapper.iter(NS + "DOMShape")) or list(wrapper.iter(NS + "color")) or list(wrapper.iter(NS + "filters")):
        raise ValueError("collision-marker wrapper gained visible content")


def recipe():
    used_sources = set()
    styles = []
    for name, ordinary, ordinary_source, unit, unit_source in FAMILIES:
        ordinary_root = load_symbol(ordinary_source)
        unit_root = load_symbol(unit_source)
        if ordinary_root.get("linkageIdentifier") != ordinary or unit_root.get("linkageIdentifier") != unit:
            raise ValueError("linkage drift in " + name)
        used_sources.update((ordinary_source, unit_source))
        ordinary_style = visual_style(ordinary_root, used_sources)
        unit_style = visual_style(unit_root, used_sources)
        if ordinary_style != unit_style:
            raise ValueError("ordinary and gun-chain visual registration drift: " + name)
        ordinary_style["kind"] = "triangle"
        styles.append({"id": name, "ordinaryLinkage": ordinary,
                       "gunChainUnitLinkage": unit, "visual": ordinary_style})
    assert_transparent_area()
    for name, ordinary, unit, source in SPRITES:
        symbol = load_symbol(source)
        if symbol.get("linkageIdentifier") != (ordinary or unit):
            raise ValueError("sprite linkage drift: " + name)
        collect_source(source, used_sources)
        styles.append({"id": name, "ordinaryLinkage": ordinary,
                       "gunChainUnitLinkage": unit})
    return styles, used_sources


def tool_records():
    tools = [Path(__file__), ROOT / "tools/combat-fx-assets/build.py",
             ROOT / "tools/combat-bullet-visuals/BulletSpriteExporter.java",
             ROOT / "tools/swf-audit/swfscan.py", ROOT / "tools/ffdec/ffdec.jar"]
    tools += sorted((ROOT / "tools/ffdec/lib").glob("*.jar"))
    return [{"path": p.relative_to(ROOT).as_posix(), "sha256": digest(p)} for p in tools]


def header(styles, used_sources):
    return {
        "schema": "cf7-combat-bullet-styles.v1",
        "generator": "tools/combat-bullet-visuals/build.py",
        "generatorSha256": digest(Path(__file__)),
        "sourceSwf": "flashswf/arts/原版素材库-子弹.swf",
        "sourceSwfSha256": digest(ROOT / "flashswf/arts/原版素材库-子弹.swf"),
        "sources": [{"path": "flashswf/arts/原版素材库-子弹/LIBRARY/" + rel,
                     "sha256": digest(LIBRARY / rel)} for rel in sorted(used_sources)],
        "gunChainPrefixes": list(GUN_CHAIN_PREFIXES),
        "tools": tool_records(),
        "styles": styles,
    }


def build():
    from PIL import Image, __version__ as pillow_version
    styles, used_sources = recipe()
    helper = runpy.run_path(str(ROOT / "tools/combat-fx-assets/build.py"))
    names = helper["exports"]()
    classpath = os.pathsep.join([str(ROOT / "tools/ffdec/lib/*"), str(ROOT / "tools/ffdec/ffdec.jar")])
    with tempfile.TemporaryDirectory(prefix="cf7-bullet-sprites-") as temp_name:
        temp = Path(temp_name)
        classes = temp / "classes"
        classes.mkdir()
        subprocess.run([str(helper["java_tool"]("javac")), "-encoding", "UTF-8", "-cp", classpath,
                        "-d", str(classes), str(ROOT / "tools/combat-bullet-visuals/BulletSpriteExporter.java")],
                       check=True, timeout=120)
        plan = temp / "plan.tsv"
        plan.write_text("\n".join(str(i) + "\t" + str(names[ordinary or unit]) + "\t0"
                        for i, (_, ordinary, unit, _) in enumerate(SPRITES, len(FAMILIES))), encoding="utf-8")
        raster = temp / "raster"
        subprocess.run([str(helper["java_tool"]("java")), "-Xmx1g", "-cp", str(classes) + os.pathsep + classpath,
                        "BulletSpriteExporter", str(ROOT / "flashswf/arts/原版素材库-子弹.swf"),
                        str(plan), str(raster), str(ZOOM)], check=True, timeout=180)
        images = []
        for line in (raster / "frames.tsv").read_text(encoding="utf-8").splitlines():
            cols = line.split("\t")
            index, frame, xmin, ymin = map(int, cols[:4])
            if frame != 0:
                raise ValueError("only the authored stationary flight frame is supported")
            with Image.open(cols[6]) as raw:
                image = raw.convert("RGBA")
                box = image.getbbox()
                if box is None:
                    raise ValueError("empty piercing bullet raster")
                if box[0] < 2 or box[1] < 2 or box[2] > image.width - 2 or box[3] > image.height - 2:
                    raise ValueError("bullet filter extends to rendering viewport edge")
                image = image.crop(box)
                if max(image.size) > 1020:
                    raise ValueError("bullet sprite exceeds raster budget")
                images.append((index, image.copy(), [round(xmin / 20 + box[0] / ZOOM, 6),
                                                    round(ymin / 20 + box[1] / ZOOM, 6)]))
        if sorted(i for i, _, _ in images) != list(range(len(FAMILIES), len(styles))):
            raise ValueError("incomplete bullet sprite raster set")
        images.sort(key=lambda item: (-item[1].height, -item[1].width, item[0]))
        placements = []
        width, x, y, row_height = 1024, 2, 2, 0
        for index, image, offset in images:
            if x + image.width + 2 > width:
                x, y, row_height = 2, y + row_height + 4, 0
            styles[index]["visual"] = {"kind": "sprite", "atlasRectPx": [x, y, image.width, image.height],
                "offsetPx": offset, "sizePx": [image.width / ZOOM, image.height / ZOOM],
                "registrationPx": [0, 0], "frameIndex": 0}
            placements.append((x, y, image))
            x += image.width + 4
            row_height = max(row_height, image.height)
        height = ((y + row_height + 2 + 7) // 8) * 8
        if height > 1024:
            raise ValueError("bullet atlas exceeds texture budget")
        atlas = Image.new("RGBA", (width, height))
        for x, y, image in placements:
            atlas.paste(image, (x, y))
        ATLAS.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(ATLAS, optimize=False, compress_level=9)
    catalog = header(styles, used_sources)
    catalog["atlas"] = {"path": ATLAS.relative_to(ROOT).as_posix(), "sha256": digest(ATLAS),
                        "width": width, "height": height, "scale": ZOOM,
                        "pillowVersion": pillow_version}
    return catalog


def verify():
    catalog = json.loads(OUTPUT.read_text(encoding="utf-8"))
    styles, used_sources = recipe()
    expected = header(styles, used_sources)
    for key, value in expected.items():
        if key != "styles" and catalog.get(key) != value:
            raise ValueError("stale bullet catalog field: " + key)
    actual_styles = catalog["styles"]
    if len(actual_styles) != len(styles):
        raise ValueError("bullet style set differs from recipe")
    for actual, expected_style in zip(actual_styles, styles):
        for key, value in expected_style.items():
            if actual.get(key) != value:
                raise ValueError("stale bullet style: " + expected_style["id"])
    atlas = catalog["atlas"]
    png = ATLAS.read_bytes()
    if atlas["path"] != ATLAS.relative_to(ROOT).as_posix() or atlas["sha256"] != digest(ATLAS):
        raise ValueError("bullet atlas integrity mismatch")
    if len(png) > 1024 * 1024 or png[:16] != b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR" or png[24:29] != bytes((8, 6, 0, 0, 0)):
        raise ValueError("bullet atlas must be bounded RGBA PNG")
    width, height = struct.unpack(">II", png[16:24])
    if [width, height] != [atlas["width"], atlas["height"]] or not 1 <= min(width, height) <= max(width, height) <= 1024 or atlas["scale"] != ZOOM:
        raise ValueError("invalid bullet atlas dimensions")
    for style in actual_styles[len(FAMILIES):]:
        visual = style["visual"]
        if visual["kind"] != "sprite" or visual["frameIndex"] != 0 or visual["registrationPx"] != [0, 0]:
            raise ValueError("invalid bullet sprite identity")
        x, y, w, h = visual["atlasRectPx"]
        if min(x, y) < 2 or min(w, h) < 1 or x + w + 2 > width or y + h + 2 > height:
            raise ValueError("bullet sprite outside atlas")
        if visual["sizePx"] != [w / ZOOM, h / ZOOM] or len(visual["offsetPx"]) != 2:
            raise ValueError("bullet sprite registration differs from raster scale")
    print(f"combat bullet styles: 2 triangles, 6 source sprites, {width}x{height}, {len(png)} bytes; closure matches")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare derived output with XFL sources")
    args = parser.parse_args()
    if args.check:
        verify()
        return
    rendered = (json.dumps(build(), ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(rendered)
    print("wrote " + str(OUTPUT.relative_to(ROOT)))


if __name__ == "__main__":
    main()
