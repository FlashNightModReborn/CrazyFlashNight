"""磁暴坦克 G08 外交地图单帧原生矢量派生；SWF 只由 Flash CS6 发布。"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as StdET
from pathlib import Path

from lxml import etree as ET

from native_vector import svg_to_xfl_legacy as base
from native_vector.vector_shapes import ShapeConverter

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).with_name("placements.json")
SOURCE = ROOT / "flashswf/arts/new/Codex素材源稿/磁暴坦克G08/source/P22-neutral.svg"
TARGET = ROOT / "flashswf/levels/地图-军阀基地"
DOC = TARGET / "DOMDocument.xml"
CONTAINER = TARGET / "LIBRARY/sprite/新地图/Symbol 51879.xml"
SYMBOL_NAME = "Codex/磁暴坦克G08/水平摆件"
SYMBOL_FILE = TARGET / "LIBRARY" / (SYMBOL_NAME + ".xml")
LAYER = "磁暴坦克G08-静态摆件"
URI = "http://ns.adobe.com/xfl/2008/"
NS = {"x": URI}
EXPECTED_SOURCE_SHA256 = "3a65f61e95703af1716afed0b36d3860b400d53426c203f5f414b417d9abc257"
EXPECTED_SHAPES = 8302


def item_id(name: str) -> str:
    value = int(hashlib.sha256(name.encode("utf-8")).hexdigest()[:8], 16) & 0x7FFFFFFF
    return "6a9f0000-" + format(value, "08x")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def vector_symbol(anchor_x: float, anchor_y: float) -> tuple[bytes, dict]:
    if sha256(SOURCE) != EXPECTED_SOURCE_SHA256:
        raise RuntimeError("归档 SVG 哈希漂移")
    svg = StdET.parse(SOURCE).getroot()
    converter = ShapeConverter(svg)
    shapes = converter.flatten(svg, matrix=(1, 0, 0, 1, -anchor_x, -anchor_y))
    if len(shapes) != EXPECTED_SHAPES:
        raise RuntimeError(f"E3 原生 Shape 计数漂移：{len(shapes)} != {EXPECTED_SHAPES}")
    root = base.E("DOMSymbolItem", {"name": SYMBOL_NAME, "itemID": item_id(SYMBOL_NAME),
                                     "symbolType": "graphic"})
    timeline = base.E("timeline", parent=root)
    dom_timeline = base.E("DOMTimeline", {"name": "水平摆件"}, timeline)
    layers = base.E("layers", parent=dom_timeline)
    layer = base.E("DOMLayer", {"name": "E3水平原生矢量", "color": "#74906A"}, layers)
    frames = base.E("frames", parent=layer)
    frame = base.E("DOMFrame", {"index": "0", "duration": "1", "keyMode": "9728"}, frames)
    elements = base.E("elements", parent=frame)
    for shape in shapes:
        elements.append(shape)
    StdET.indent(root, space="  ")
    data = StdET.tostring(root, encoding="utf-8", xml_declaration=True)
    stats = dict(converter.stats)
    stats.update(native_shapes=len(shapes), output_bytes=len(data))
    return data, stats


def layer_xml(config: dict) -> str:
    scale = config["scale"]
    multiplier = config["colorMultiplier"]
    return f'''        <DOMLayer name="{LAYER}" color="#74906A" autoNamed="false">
          <frames>
            <DOMFrame index="0" keyMode="9728">
              <elements>
                <DOMSymbolInstance libraryItemName="{SYMBOL_NAME}" symbolType="graphic" loop="single frame" firstFrame="0">
                  <matrix><Matrix a="{scale}" b="0" c="0" d="{scale}" tx="{config['x']}" ty="{config['y']}"/></matrix>
                  <transformationPoint><Point/></transformationPoint>
                  <color><Color redMultiplier="{multiplier}" greenMultiplier="{multiplier}" blueMultiplier="{multiplier}"/></color>
                </DOMSymbolInstance>
              </elements>
            </DOMFrame>
          </frames>
        </DOMLayer>'''


def install_document() -> None:
    text = DOC.read_text(encoding="utf-8")
    folder = "Codex/磁暴坦克G08"
    if f'name="{folder}"' not in text:
        entry = f'          <DOMFolderItem name="{folder}" itemID="{item_id(folder)}"/>\n'
        text = text.replace("     </folders>", entry + "     </folders>", 1)
    href = SYMBOL_NAME + ".xml"
    if f'href="{href}"' not in text:
        include = f'          <Include href="{href}" loadImmediate="false" itemID="{item_id(SYMBOL_NAME)}"/>\n'
        text = text.replace("     </symbols>", include + "     </symbols>", 1)
    DOC.write_text(text, encoding="utf-8")


def install_placement(config: dict) -> None:
    text = CONTAINER.read_text(encoding="utf-8")
    text = re.sub(r'\n[ \t]*<DOMLayer\b[^>]*\bname="' + re.escape(LAYER)
                  + r'"[^>]*>.*?</DOMLayer>', "", text, flags=re.S)
    replace = config["replaceSymbol"]
    pattern = (r'\n[ \t]*<DOMSymbolInstance\b[^>]*\blibraryItemName="' + re.escape(replace)
               + r'"[^>]*>.*?</DOMSymbolInstance>')
    text, removed = re.subn(pattern, "", text, count=1, flags=re.S)
    if removed != 1 and replace in text:
        raise RuntimeError("27号犀牛实例不是预期结构")
    anchor = '        <DOMLayer name="' + config["insertBeforeLayer"] + '"'
    if text.count(anchor) != 1:
        raise RuntimeError("地图图层锚点漂移")
    text = text.replace(anchor, layer_xml(config) + "\n" + anchor, 1)
    CONTAINER.write_text(text, encoding="utf-8")


def build(config: dict) -> dict:
    data, stats = vector_symbol(*config["sourceAnchorPx"])
    SYMBOL_FILE.parent.mkdir(parents=True, exist_ok=True)
    SYMBOL_FILE.write_bytes(data)
    install_document()
    install_placement(config)
    return stats


def check(config: dict, regenerate: bool) -> None:
    assert sha256(SOURCE) == EXPECTED_SOURCE_SHA256
    symbol = ET.parse(str(SYMBOL_FILE)).getroot()
    assert symbol.get("symbolType") == "graphic"
    assert not symbol.findall(".//x:Actionscript", NS)
    assert not symbol.findall(".//x:DOMBitmapInstance", NS)
    assert not symbol.findall(".//x:BitmapFill", NS)
    assert not symbol.findall(".//x:DOMSymbolInstance", NS)
    shapes = symbol.findall(".//x:DOMShape", NS)
    assert len(shapes) == EXPECTED_SHAPES
    if regenerate:
        expected, _ = vector_symbol(*config["sourceAnchorPx"])
        assert hashlib.sha256(expected).digest() == hashlib.sha256(SYMBOL_FILE.read_bytes()).digest(), "矢量派生漂移"
    doc = ET.parse(str(DOC)).getroot()
    includes = [i for i in doc.findall("./x:symbols/x:Include", NS) if i.get("href") == SYMBOL_NAME + ".xml"]
    assert len(includes) == 1
    assert not [m for m in doc.findall("./x:media/x:DOMBitmapItem", NS)
                if "磁暴坦克G08" in (m.get("name") or "")]
    root = ET.parse(str(CONTAINER)).getroot()
    layers = root.findall("./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer", NS)
    own = [layer for layer in layers if layer.get("name") == LAYER]
    assert len(own) == 1
    instances = own[0].findall(".//x:DOMSymbolInstance", NS)
    assert len(instances) == 1 and instances[0].get("libraryItemName") == SYMBOL_NAME
    matrix = instances[0].find("./x:matrix/x:Matrix", NS)
    assert abs(float(matrix.get("a")) - config["scale"]) < 1e-9
    assert abs(float(matrix.get("d")) - config["scale"]) < 1e-9
    assert float(matrix.get("tx")) == config["x"] and float(matrix.get("ty")) == config["y"]
    assert not root.xpath('.//x:DOMSymbolInstance[@libraryItemName=$name]', namespaces=NS,
                          name=config["replaceSymbol"])
    assert list(layers).index(own[0]) + 1 == next(i for i, layer in enumerate(layers)
                                                    if layer.get("name") == config["insertBeforeLayer"])
    displayed = 1063 * config["scale"]
    ratio = displayed / 310.512
    assert 1.1 <= ratio <= 1.15
    gradients = len(symbol.findall(".//x:LinearGradient", NS))
    edges = len(symbol.findall(".//x:Edge", NS))
    print(f"磁暴坦克矢量检查通过：{len(shapes)} Shape / {gradients} LinearGradient / {edges} Edge；"
          f"显示宽约{displayed:.3f}px，为27号犀牛的{ratio:.4f}倍；单帧/无脚本/无位图/无子元件引用")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text(encoding="utf-8"))["placement"]
    if args.check:
        check(config, regenerate=True)
        return
    stats = build(config)
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    check(config, regenerate=False)


if __name__ == "__main__":
    main()
