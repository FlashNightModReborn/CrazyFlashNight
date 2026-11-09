#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从修改工具 XFL 生成原生修改器的完整底图、独立按钮和几何闭包。"""
import argparse
import hashlib
import importlib.util
import json
import math
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "flashswf/UI/修改工具界面/LIBRARY"
OUTPUT = ROOT / "launcher/web/assets/modifier/native"
ENGINE = ROOT / "tools/xfl-ui-svg/xfl_to_svg.py"
SVG_RENDER = ROOT / "tools/cf6-map-source/pydeps/svgrender.py"
OFFSET = (171.0, 29.0)
STAGE = (843, 456)
PAGES = (("economy", 0), ("items", 10), ("level", 20), ("units", 30))
EXTRA_BUTTONS = {"sprite/通用按钮", "sprite/Symbol 2224"}
TAB_SYMBOLS = {
    "经济栏": "tab:economy",
    "物品栏": "tab:items",
    "关卡栏": "tab:level",
    "兵种栏": "tab:units",
}
COMMON_BUTTONS = {
    ("button/Symbol 928", 5.1, 14.65): "drag",
    ("sprite/Symbol 2224", 460.6, 13.25): "close",
}
GENERIC_BUTTONS = {
    ("economy", 34.35, 136.0): "money",
    ("economy", 34.35, 202.6): "kcoin",
    ("economy", 33.85, 277.85): "test_space",
    ("items", 261.15, 243.5): "item_produce",
    ("items", 261.2, 312.6): "item_search",
    ("level", 30.25, 129.55): "kill_all",
    ("level", 30.25, 185.55): "finish_wave",
    ("level", 30.25, 243.65): "finish_map",
    ("level", 30.25, 299.65): "finish_stage",
    ("level", 295.25, 129.55): "grant_task",
    ("level", 295.65, 186.95): "unlock_stages",
    ("units", 340.95, 299.8): "unit_spawn",
    ("units", 340.95, 345.65): "unit_merc",
    ("units", 211.25, 345.65): "unit_jump",
}
SYMBOL_BUTTONS = {
    ("items", "button/Symbol 1756"): "item_first",
    ("items", "button/Symbol 1751"): "item_prev",
    ("items", "button/Symbol 1750"): "item_next",
    ("items", "button/Symbol 1755"): "item_last",
    ("items", "button/Symbol 2236"): "item_minus",
    ("items", "button/Symbol 2235"): "item_plus",
    ("units", "button/Symbol 1756"): "unit_first",
    ("units", "button/Symbol 1751"): "unit_prev",
    ("units", "button/Symbol 1750"): "unit_next",
    ("units", "button/Symbol 1755"): "unit_last",
    ("units", "button/Symbol 2244"): "level_minus",
    ("units", "button/Symbol 2243"): "level_plus",
    ("units", "button/Symbol 2248"): "count_minus",
    ("units", "button/Symbol 2247"): "count_plus",
}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


engine = module("modifier_xfl_svg", ENGINE)
svg_renderer = module("modifier_svg_render", SVG_RENDER)
NS = engine.NS
SYMBOL_PATHS = {}
for include in ET.parse(LIBRARY.parent / "DOMDocument.xml").getroot().findall(".//x:Include", NS):
    href = include.get("href")
    source = (LIBRARY / href).read_text(encoding="utf-8-sig")
    symbol = ET.fromstring(engine.BARE_AMP.sub("&amp;", source))
    SYMBOL_PATHS[symbol.get("name")] = href[:-4] if href.endswith(".xml") else href


class ModifierRenderer(engine.Renderer):
    def load(self, name):
        root = super().load(SYMBOL_PATHS.get(name, name))
        for element in root.iter("{%s}DOMSymbolInstance" % NS["x"]):
            if element.get("libraryItemName") in EXTRA_BUTTONS:
                element.set("symbolType", "button")
        return root

    def element_to_svg(self, element, where, ct=engine.CT_IDENTITY):
        tag = element.tag.rsplit("}", 1)[-1]
        if element.get("isVisible") == "false":
            return ""
        if tag == "DOMSymbolInstance" and element.get("libraryItemName") == "物品图标位置示意":
            return ""
        if tag == "DOMShape" and where == "修改工具界面:四界面" \
                and not element.findall("./x:fills/x:FillStyle", NS) \
                and element.findall("./x:strokes/x:StrokeStyle", NS):
            return ""
        if tag == "DOMGroup":
            group_matrix = element.find("./x:matrix/x:Matrix", NS)
            members = element.find("./x:members", NS)
            if group_matrix is not None and members is not None:
                for member in members:
                    member_matrix = member.find("./x:matrix/x:Matrix", NS)
                    if member_matrix is not None and member_matrix.attrib == group_matrix.attrib:
                        element = __import__("copy").deepcopy(element)
                        members = element.find("./x:members", NS)
                        for copied in members:
                            copied_matrix = copied.find("./x:matrix/x:Matrix", NS)
                            if copied_matrix is not None and copied_matrix.attrib == group_matrix.attrib:
                                copied.remove(copied.find("./x:matrix", NS))
                        break
        return super().element_to_svg(element, where, ct)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_digest(path):
    return hashlib.sha256(Path(path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def point_key(value):
    return round(float(value), 2)


def action_for(rec, page):
    symbol = rec["symbol"]
    matrix = rec["matrix"]
    if rec.get("layer") in TAB_SYMBOLS:
        return TAB_SYMBOLS[rec["layer"]]
    common = COMMON_BUTTONS.get((symbol, point_key(matrix[4]), point_key(matrix[5])))
    if common:
        return common
    if symbol == "sprite/通用按钮":
        return GENERIC_BUTTONS.get((page, point_key(matrix[4]), point_key(matrix[5])))
    return SYMBOL_BUTTONS.get((page, symbol))


def shifted(rect):
    return [rect[0] + OFFSET[0], rect[1] + OFFSET[1],
            rect[2] + OFFSET[0], rect[3] + OFFSET[1]]


def translated_svg(svg):
    marker = "</defs>"
    head, tail = svg.split(marker, 1)
    body = tail[:tail.rindex("</svg>")]
    return (head + marker + '\n<g transform="translate(%g %g)">' % OFFSET
            + body + "</g></svg>\n")


def render_frame(page, frame, directory):
    renderer = ModifierRenderer(LIBRARY, [])
    renderer.separate_buttons = True
    root = renderer.load("修改工具界面")
    layers = root.findall("./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer", NS)
    mask_cid = {}
    masked_name = {}
    for index, layer in enumerate(layers):
        parent = layer.get("parentLayerIndex")
        if parent is not None:
            masked_name.setdefault(int(parent), layer.get("name", "layer%d" % index))
    for index, layer, elements in renderer.frame_elements(root, frame, "修改工具界面"):
        if layer.get("layerType") == "mask":
            items = renderer.elements_to_d(elements, "修改工具界面:mask")
            mask_cid[index] = renderer.new_def(engine.clip_items_to_xml(items))
            renderer.clips["clip:" + masked_name.get(index, "mask%d" % index)] = "".join(
                item[0] for item in items)
    parts = []
    for index, layer, elements in renderer.frame_elements(root, frame, "修改工具界面"):
        if layer.get("layerType") == "mask" or elements is None or not len(elements):
            continue
        name = layer.get("name", "layer%d" % index)
        before = len(renderer.buttons)
        body = renderer.elements_to_svg(elements, "修改工具界面:" + name)
        for rec in renderer.buttons[before:]:
            rec["layer"] = name
        clip = renderer._mask_index_of(layers, index)
        if clip in mask_cid and body:
            body = '<g clip-path="url(#%s)">%s</g>' % (mask_cid[clip], body)
        if body:
            parts.append((index, name, body))
    parts.sort(key=lambda item: -item[0])
    body = "".join('<g data-layer="%s">%s</g>' % (engine.escape(name), value)
                   for _, name, value in parts)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">\n'
           '<defs>%s</defs>\n%s</svg>\n' % (STAGE[0], STAGE[1], STAGE[0], STAGE[1],
                                            "".join(renderer.defs), body))
    svg = translated_svg(svg)
    bounds = renderer.symbol_bbox("修改工具界面", frame)
    if not bounds:
        raise RuntimeError(page + ": empty XFL frame")
    visible = shifted(bounds)
    if visible[0] < 0 or visible[1] < 0 or visible[2] > STAGE[0] or visible[3] > STAGE[1]:
        raise RuntimeError(page + ": clipped XFL frame: " + repr(visible))

    buttons = {}
    for rec in renderer.buttons:
        if rec.get("hitTestOnly"):
            continue
        action = action_for(rec, page)
        if not action:
            raise RuntimeError(page + ": unmapped button " + rec["symbol"] + " " + repr(rec["matrix"]))
        rec["id"] = action.replace(":", "-")
        local = rec["upLocalBBox"]
        asset_local = [local[0] - 2, local[1] - 2, local[2] + 2, local[3] + 2]
        buttons[action] = {
            "assetRect": shifted(renderer._rect_by_matrix(rec["matrix"], asset_local)),
            "hitRect": shifted(rec["hitRect"]),
            "flipX": rec["matrix"][0] < 0,
            "states": rec["states"],
        }
    engine.write_button_svgs(renderer, directory)
    for action, rec in buttons.items():
        for state, relative in list(rec["states"].items()):
            rec["states"][state] = relative[:-4] + ".png"
    return renderer, svg, buttons


def frame_geometry(page, frame):
    renderer = ModifierRenderer(LIBRARY, [])
    root = renderer.load("修改工具界面")
    result = {}
    for _, layer, elements in renderer.frame_elements(root, frame, "修改工具界面"):
        if elements is None:
            continue
        if layer.get("name") == "预览框遮罩":
            for element in elements:
                if element.tag.rsplit("}", 1)[-1] != "DOMSymbolInstance":
                    continue
                matrix = engine.parse_matrix(element.find("./x:matrix/x:Matrix", NS))
                bounds = renderer.symbol_bbox(element.get("libraryItemName"), 0)
                result["unitFrameMask"] = shifted(renderer._rect_by_matrix(matrix, bounds))
        if page == "units" and layer.get("name") == "四界面":
            rows = []
            for element in elements:
                if element.get("libraryItemName") != "兵种图标":
                    continue
                matrix = engine.parse_matrix(element.find("./x:matrix/x:Matrix", NS))
                bounds = renderer.symbol_bbox("兵种图标", 0)
                rows.append(shifted(renderer._rect_by_matrix(matrix, bounds)))
            if len(rows) != 8:
                raise RuntimeError("units: expected eight source rows")
            result["unitRows"] = rows
    return result


def generate(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "buttons").mkdir(exist_ok=True)
    layout = {"version": 1, "width": STAGE[0], "height": STAGE[1], "pages": {}}
    sources = {ENGINE, SVG_RENDER, Path(__file__).resolve()}
    rendered = {}
    for page, frame in PAGES:
        renderer, svg, buttons = render_frame(page, frame, directory)
        sources.update(renderer.sources)
        svg_path = directory / (page + ".svg")
        svg_path.write_text(svg, encoding="utf-8")
        background = "native-" + page + ".png"
        svg_renderer.render(str(svg_path), STAGE[0], str(directory / background))
        svg_path.unlink()
        for action, rec in buttons.items():
            for state, relative in list(rec["states"].items()):
                source_svg = directory / (relative[:-4] + ".svg")
                width = max(1, int(math.ceil(rec["assetRect"][2] - rec["assetRect"][0])))
                key = (digest(source_svg), width)
                if key not in rendered:
                    target = directory / relative
                    svg_renderer.render(str(source_svg), width, str(target))
                    rendered[key] = target
                elif rendered[key].resolve() != (directory / relative).resolve():
                    shutil.copyfile(rendered[key], directory / relative)
                source_svg.unlink()
        layout["pages"][page] = {"background": background, "buttons": buttons}
        layout.update(frame_geometry(page, frame))
    if "unitFrameMask" not in layout or "unitRows" not in layout:
        raise RuntimeError("unit preview mask/rows missing")
    (directory / "layout.json").write_text(
        json.dumps(layout, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    files = {}
    for path in sorted(directory.rglob("*")):
        if path.is_file() and path.name != "manifest.json":
            files[path.relative_to(directory).as_posix()] = {
                "sha256": digest(path), "bytes": path.stat().st_size}
    manifest = {
        "version": 1,
        "authority": "flashswf/UI/修改工具界面/LIBRARY/修改工具界面.xml",
        "generator": "tools/export-modifier-art.py",
        "sourceHashEncoding": "utf8-lf",
        "sources": {path.relative_to(ROOT).as_posix(): source_digest(path)
                    for path in sorted(sources, key=str)},
        "files": files,
    }
    (directory / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def compare(directory):
    expected = set()
    actual = set()
    for path in directory.rglob("*"):
        if path.is_file():
            actual.add(path.relative_to(directory).as_posix())
    with tempfile.TemporaryDirectory(prefix="modifier-art-check-") as temp:
        generate(temp)
        for path in Path(temp).rglob("*"):
            if path.is_file():
                expected.add(path.relative_to(temp).as_posix())
        if actual != expected:
            raise SystemExit("modifier art file set differs; run python tools/export-modifier-art.py")
        for relative in sorted(expected):
            if (directory / relative).read_bytes() != (Path(temp) / relative).read_bytes():
                raise SystemExit("modifier art is stale: " + relative)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        if not OUTPUT.exists():
            raise SystemExit("modifier art is missing")
        compare(OUTPUT)
    else:
        if OUTPUT.exists():
            shutil.rmtree(OUTPUT)
        generate(OUTPUT)
    print("Modifier art " + ("verified" if args.check else "exported") + ": " + str(OUTPUT))


if __name__ == "__main__":
    main()
