"""把战斗吉普 P13 的受损保留态静态派生到废城环线地图3。"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path

from lxml import etree as ET

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).with_name("placements.json")
URI = "http://ns.adobe.com/xfl/2008/"
NS = {"x": URI}
PREFIX = "Codex/战斗吉普P13/"
LAYER = "战斗吉普P13-受损保留"


def tag(name: str) -> str:
    return "{" + URI + "}" + name


def read(path: Path, preserve: bool = False):
    return ET.parse(str(path), ET.XMLParser(remove_blank_text=not preserve)).getroot()


def write(path: Path, root) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(ET.tostring(root, encoding="utf-8", pretty_print=True))


def item_id(name: str) -> str:
    value = int(hashlib.sha256(name.encode("utf-8")).hexdigest()[:8], 16) & 0x7FFFFFFF
    return "6b010000-" + format(value, "08x")


def remapped_name(source_name: str) -> str:
    if source_name.startswith("Jeep/G01/"):
        return PREFIX + source_name.removeprefix("Jeep/G01/")
    if source_name.startswith("Jeep/Source/"):
        return PREFIX + "Source/" + source_name.removeprefix("Jeep/Source/")
    raise ValueError("超出战斗吉普来源命名空间：" + source_name)


def freeze_closure(source: Path, start: str):
    result = {}

    def visit(source_name: str) -> str:
        target_name = remapped_name(source_name)
        if target_name in result:
            return target_name
        path = source / "LIBRARY" / (source_name + ".xml")
        root = copy.deepcopy(read(path))
        root.set("name", target_name)
        root.set("itemID", item_id(target_name))
        root.set("symbolType", "graphic")
        for key in list(root.attrib):
            if key.startswith("linkage"):
                del root.attrib[key]
        timeline = root.find("./x:timeline/x:DOMTimeline", NS)
        timeline.set("name", target_name.rsplit("/", 1)[-1])
        timeline.attrib.pop("currentFrame", None)
        result[target_name] = root
        for script in list(root.findall(".//x:Actionscript", NS)):
            script.getparent().remove(script)
        for frame in root.findall(".//x:DOMFrame", NS):
            if int(frame.get("index", 0)) != 0 or int(frame.get("duration", 1)) != 1:
                raise ValueError("来源不是单帧静态元件：" + source_name)
            frame.attrib.pop("tweenType", None)
        for inst in root.findall(".//x:DOMSymbolInstance", NS):
            inst.set("libraryItemName", visit(inst.get("libraryItemName")))
            inst.set("symbolType", "graphic")
            inst.set("loop", "single frame")
            inst.set("firstFrame", "0")
            inst.attrib.pop("name", None)
        return target_name

    vehicle_name = visit(start)
    shadow_name = PREFIX + "接地阴影"
    outer = shadow_shape(230, 18, 0.12)
    inner = shadow_shape(195, 12, 0.18)
    result[shadow_name] = make_symbol(shadow_name, [make_symbol_layer("柔和接地", [outer, inner])])
    wrapper_name = PREFIX + "受损保留摆件"
    result[wrapper_name] = make_symbol(wrapper_name, [
        make_symbol_layer("受损车辆", [instance(vehicle_name, None)]),
        make_symbol_layer("接地影", [instance(shadow_name, None)]),
    ])
    return result, wrapper_name


def make_symbol_layer(name: str, elements):
    layer = ET.Element(tag("DOMLayer"), name=name, color="#74906A", autoNamed="false")
    frame = ET.SubElement(ET.SubElement(layer, tag("frames")), tag("DOMFrame"),
                          index="0", keyMode="9728")
    ET.SubElement(frame, tag("elements")).extend(elements)
    return layer


def make_symbol(name: str, layers):
    root = ET.Element(tag("DOMSymbolItem"), nsmap={None: URI}, name=name,
                      itemID=item_id(name), symbolType="graphic")
    timeline = ET.SubElement(ET.SubElement(root, tag("timeline")), tag("DOMTimeline"),
                             name=name.rsplit("/", 1)[-1])
    ET.SubElement(timeline, tag("layers")).extend(layers)
    return root


def shadow_shape(half_width: int, half_height: int, alpha: float):
    shape = ET.Element(tag("DOMShape"))
    ET.SubElement(ET.SubElement(shape, tag("matrix")), tag("Matrix"), tx="251.5", ty="222")
    style = ET.SubElement(ET.SubElement(shape, tag("fills")), tag("FillStyle"), index="1")
    ET.SubElement(style, tag("SolidColor"), color="#000000", alpha=format(alpha, ".3g"))
    x = half_width * 20
    y = half_height * 20
    edges = (
        f"! {-x} 0 [ {-x} {-y} 0 {-y} "
        f"[ {x} {-y} {x} 0 [ {x} {y} 0 {y} [ {-x} {y} {-x} 0"
    )
    ET.SubElement(ET.SubElement(shape, tag("edges")), tag("Edge"), fillStyle1="1", edges=edges)
    return shape


def install(target: Path, symbols) -> None:
    doc = read(target / "DOMDocument.xml", preserve=True)
    includes = doc.find("x:symbols", NS)
    for entry in list(includes):
        if entry.get("href", "").startswith(PREFIX):
            includes.remove(entry)
    folders = doc.find("x:folders", NS)
    if folders is None:
        folders = ET.Element(tag("folders"))
        doc.insert(0, folders)
    existing = {f.get("name") for f in folders}
    needed = set()
    for name in symbols:
        parts = name.split("/")[:-1]
        needed.update("/".join(parts[:i]) for i in range(1, len(parts) + 1))
    for name in sorted(needed - existing):
        ET.SubElement(folders, tag("DOMFolderItem"), name=name, itemID=item_id(name))
    for name, root in sorted(symbols.items()):
        write(target / "LIBRARY" / (name + ".xml"), root)
        ET.SubElement(includes, tag("Include"), href=name + ".xml", itemID=root.get("itemID"))
    owned = (target / "LIBRARY" / PREFIX).resolve()
    if owned.exists():
        for path in owned.rglob("*.xml"):
            name = path.relative_to(target / "LIBRARY").as_posix()[:-4]
            if name not in symbols:
                path.unlink()
    write(target / "DOMDocument.xml", doc)


def placement_matrix(config):
    radians = math.radians(config.get("rotationDegrees", 0))
    scale = config["scale"]
    sign = -1 if config.get("mirror") else 1
    return {
        "a": sign * scale * math.cos(radians),
        "b": sign * scale * math.sin(radians),
        "c": -scale * math.sin(radians),
        "d": scale * math.cos(radians),
        "tx": config["x"],
        "ty": config["y"],
    }


def instance(name: str, matrix):
    result = ET.Element(tag("DOMSymbolInstance"), libraryItemName=name,
                        symbolType="graphic", loop="single frame", firstFrame="0")
    if matrix:
        ET.SubElement(ET.SubElement(result, tag("matrix")), tag("Matrix"),
                      **{key: format(value, ".12g") for key, value in matrix.items()})
    ET.SubElement(ET.SubElement(result, tag("transformationPoint")), tag("Point"))
    return result


def make_layer(root_name: str, matrix):
    layer = ET.Element(tag("DOMLayer"), nsmap={None: URI}, name=LAYER,
                       color="#74906A", autoNamed="false")
    frame = ET.SubElement(ET.SubElement(layer, tag("frames")), tag("DOMFrame"),
                          index="0", keyMode="9728")
    elements = ET.SubElement(frame, tag("elements"))
    elements.append(instance(root_name, matrix))
    return layer


def place(target: Path, root_name: str, config) -> None:
    path = target / config["containerXml"]
    root = read(path, preserve=True)
    layers = root.find("./x:timelines/x:DOMTimeline/x:layers", NS)
    for old in list(layers):
        if old.get("name") == LAYER:
            layers.remove(old)
    layer = make_layer(root_name, placement_matrix(config["placement"]))
    index = next(i for i, item in enumerate(layers)
                 if item.get("name") == config["insertBeforeLayer"])
    layers.insert(index, layer)
    write(path, root)


def normalized(root):
    root = copy.deepcopy(root)
    ignored = {"itemID", "lastModified", "lastUniqueIdentifier", "selected", "isSelected",
               "current", "centerPoint3DX", "centerPoint3DY", "lastModifiedDate"}
    for element in root.iter():
        if element.text is not None and not element.text.strip():
            element.text = None
        element.tail = None
        for key in ignored:
            element.attrib.pop(key, None)
        attrs = sorted(element.attrib.items())
        element.attrib.clear()
        element.attrib.update(attrs)
    return ET.tostring(root, method="c14n")


def check(target: Path, symbols, root_name: str, config) -> None:
    for name, root in symbols.items():
        assert root.get("symbolType") == "graphic", name
        assert not root.findall(".//x:Actionscript", NS), name
        assert not root.findall(".//x:DOMBitmapInstance", NS), name
        assert not any(key.startswith("linkage") for key in root.attrib), name
        for inst in root.findall(".//x:DOMSymbolInstance", NS):
            assert inst.get("libraryItemName") in symbols, (name, inst.get("libraryItemName"))
            assert inst.get("symbolType") == "graphic" and inst.get("loop") == "single frame", name
    doc = read(target / "DOMDocument.xml")
    includes = {entry.get("href") for entry in doc.findall("./x:symbols/x:Include", NS)}
    for name, expected in symbols.items():
        assert name + ".xml" in includes, name
        actual = read(target / "LIBRARY" / (name + ".xml"))
        assert normalized(actual) == normalized(expected), name
    layers = doc.find("./x:timelines/x:DOMTimeline/x:layers", NS)
    own = [layer for layer in layers if layer.get("name") == LAYER]
    assert len(own) == 1
    anchor = next(i for i, layer in enumerate(layers) if layer.get("name") == config["insertBeforeLayer"])
    assert list(layers).index(own[0]) + 1 == anchor
    placed = own[0].findall(".//x:DOMSymbolInstance", NS)
    assert len(placed) == 1 and placed[0].get("libraryItemName") == root_name
    actual = placed[0].find("./x:matrix/x:Matrix", NS)
    for key, value in placement_matrix(config["placement"]).items():
        assert abs(float(actual.get(key, 0)) - value) < 0.0001, key
    environment = read(ROOT / "data/environment/stage_environment.xml")
    candidates = []
    for item in environment.findall("./Environment"):
        url = item.find("BackgroundURL")
        if url is not None and url.text == "废城环线地图3.swf":
            candidates.append(item)
    assert len(candidates) == 1, "废城环线地图3环境项必须唯一"
    polygons = []
    for collision in candidates[0].findall("Collision"):
        polygons.append([tuple(int(value) for value in point.text.split(","))
                         for point in collision.findall("Point")])
    expected_collision = [tuple(point) for point in config["collision"]]
    assert polygons.count(expected_collision) == 1, "战斗吉普碰撞区缺失或重复"
    print(f"战斗吉普静态检查通过：{len(symbols)} 个元件，1 张地图")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    source = ROOT / config["source"]
    target = ROOT / config["target"]
    symbols, root_name = freeze_closure(source, config["sourceSymbol"])
    if not args.check:
        install(target, symbols)
        place(target, root_name, config)
    check(target, symbols, root_name, config)


if __name__ == "__main__":
    main()
