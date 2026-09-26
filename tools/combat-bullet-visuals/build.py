#!/usr/bin/env python3
"""Derive the first native bullet styles from the editable XFL library.

The output is visual data only. Collision areas, frame scripts and bullet
lifecycles remain in AS2. Both ordinary and gun-chain linkages in a family must
resolve to the same local-space visual; any future source drift fails closed.
"""

import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / "flashswf/arts/原版素材库-子弹/LIBRARY"
OUTPUT = ROOT / "data/combat_visuals/bullet_styles.v1.json"
NS = "{http://ns.adobe.com/xfl/2008/}"
FAMILIES = (
    ("plain", "普通子弹", "子弹-炮弹与爆炸组/普通子弹.xml",
     "单元体-普通子弹", "联弹/单元体-普通子弹.xml"),
    ("enhanced", "加强普通子弹", "子弹-普通与穿刺组/加强普通子弹.xml",
     "单元体-加强普通子弹", "联弹/单元体-加强普通子弹.xml"),
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


def build():
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
        styles.append({"id": name, "ordinaryLinkage": ordinary,
                       "gunChainUnitLinkage": unit, "visual": ordinary_style})
    return {
        "schema": "cf7-combat-bullet-styles.v1",
        "generator": "tools/combat-bullet-visuals/build.py",
        "generatorSha256": digest(Path(__file__)),
        "sourceSwf": "flashswf/arts/原版素材库-子弹.swf",
        "sourceSwfSha256": digest(ROOT / "flashswf/arts/原版素材库-子弹.swf"),
        "sources": [{"path": "flashswf/arts/原版素材库-子弹/LIBRARY/" + rel,
                     "sha256": digest(LIBRARY / rel)} for rel in sorted(used_sources)],
        "gunChainPrefixes": list(GUN_CHAIN_PREFIXES),
        "styles": styles,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare derived output with XFL sources")
    args = parser.parse_args()
    rendered = (json.dumps(build(), ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != rendered:
            raise SystemExit("stale combat bullet style catalog: run build.py")
        print("combat bullet styles: source and output match")
        return
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(rendered)
    print("wrote " + str(OUTPUT.relative_to(ROOT)))


if __name__ == "__main__":
    main()
