"""从原版地铁线路 FLA 派生 Web 线路底图与站点帧；--check 只读核对完整闭包。"""
import argparse
import copy
import hashlib
import importlib.util
import io
import json
import struct
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "flashswf/UI/地铁线路.fla"
DESCRIPTIONS = ROOT / "data/subway/descriptions.json"
ENGINE = ROOT / "tools/xfl-ui-svg/xfl_to_svg.py"
OUTPUT = ROOT / "launcher/web/assets/subway"
STAGE = (392, 352)
EXCLUDED_LAYERS = {"站点", "按钮", "按钮区域", "执行按钮", "简介"}
ROUTE_LAYERS = tuple(f"线路{number}" for number in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 17, 18, 19, 27, 30)) + ("线路S3",)
XFL_NS = {"x": "http://ns.adobe.com/xfl/2008/"}
ROUTE_RULES = {
    "2": {"requires": ["总备处站", "自由广场站"], "contacts": ["自由广场站"]},
    "4": {"requires": ["总备处站", "新市场站"], "contacts": ["总备处站", "新市场站"]},
    "6": {"requires": ["总备处站", "自由广场站"], "contacts": ["总备处站"]},
    "7": {"requires": ["新市场站", "环线东北站"], "contacts": ["新市场站", "环线东北站"]},
    "8": {"requires": ["总备处站", "新市场站", "自由广场站", "环线东北站"],
        "contacts": ["总备处站", "新市场站", "自由广场站", "环线东北站"]},
    "17": {"requires": ["新市场站", "环线东北站"], "contacts": ["环线东北站"]},
}
STATIONS = {
    "总备处站": {"frame": 4, "x": 247.05, "y": 179.15},
    "新市场站": {"frame": 3, "x": 266.15, "y": 179.2},
    "自由广场站": {"frame": 2, "x": 247, "y": 192.35},
    "环线东北站": {"frame": 3, "x": 266.3, "y": 156.55},
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_xfl():
    data = bytearray(SOURCE.read_bytes())
    eocd = data.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise RuntimeError("地铁线路 FLA 缺少 ZIP EOCD")
    declared_size, offset = struct.unpack_from("<II", data, eocd + 12)
    actual_size = eocd - offset
    if declared_size != actual_size:
        struct.pack_into("<I", data, eocd + 12, actual_size)
    return io.BytesIO(data)


def generate():
    spec = importlib.util.spec_from_file_location("subway_xfl_svg", ENGINE)
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    outputs = {}
    with tempfile.TemporaryDirectory(prefix="subway-art-", dir=ROOT / "tmp") as temporary:
        library = Path(temporary) / "xfl/LIBRARY"
        with zipfile.ZipFile(read_xfl()) as archive:
            archive.extractall(Path(temporary) / "xfl")
        renderer, svg, _ = engine.export(library, "地铁线路UI", 0, STAGE, OUTPUT, [], {})
        root = ET.fromstring(svg)
        for layer in list(root):
            if layer.get("data-layer") in EXCLUDED_LAYERS:
                root.remove(layer)
        outputs["route-map.svg"] = ET.tostring(root, encoding="utf-8") + b"\n"
        ui_path = library / "地铁线路UI.xml"
        document = ET.parse(ui_path)
        for layer in document.findall(".//x:DOMLayer", XFL_NS):
            if layer.get("name") not in ROUTE_LAYERS:
                continue
            for instance in layer.findall(".//x:DOMSymbolInstance", XFL_NS):
                color = instance.find("x:color", XFL_NS)
                if color is not None:
                    instance.remove(color)
        document.write(ui_path, encoding="utf-8", xml_declaration=True)
        _, colored_svg, _ = engine.export(library, "地铁线路UI", 0, STAGE, OUTPUT, [], {})
        colored_root = ET.fromstring(colored_svg)
        route_groups = {layer.get("data-layer"): layer for layer in colored_root if layer.get("data-layer") in ROUTE_LAYERS}
        if set(route_groups) != set(ROUTE_LAYERS):
            raise RuntimeError(f"线路导出闭包不完整: {sorted(set(ROUTE_LAYERS) - set(route_groups))}")
        interaction_root = ET.Element(colored_root.tag, colored_root.attrib)
        for layer_name in ROUTE_LAYERS:
            route_id = layer_name.removeprefix("线路")
            rules = ROUTE_RULES.get(route_id, {"requires": [], "contacts": []})
            group = copy.deepcopy(route_groups[layer_name])
            group.set("class", "subway-route")
            group.set("data-route", route_id)
            group.set("data-requires", " ".join(rules["requires"]))
            group.set("data-contacts", " ".join(rules["contacts"]))
            group.set("tabindex", "0")
            group.set("role", "button")
            group.set("aria-label", f"线路 {route_id}")
            for parent in group.iter():
                for path in list(parent):
                    if path.tag != "{http://www.w3.org/2000/svg}path":
                        continue
                    outline = copy.deepcopy(path)
                    outline.set("class", "subway-route-outline")
                    outline.set("stroke", "#FFFFFF")
                    outline.set("stroke-width", "%g" % (float(path.get("stroke-width", "5")) + 4))
                    outline.set("pointer-events", "none")
                    parent.insert(list(parent).index(path), outline)
                    path.set("class", "subway-route-line")
                    path.set("data-color", path.get("stroke", "#6A6769"))
                    path.set("stroke", "#6A6769")
                    path.set("pointer-events", "stroke")
            interaction_root.append(group)
        outputs["route-interactions.svg"] = ET.tostring(interaction_root, encoding="utf-8") + b"\n"
        descriptions = json.loads(DESCRIPTIONS.read_text(encoding="utf-8"))
        if descriptions.get("version") != 1 or set(descriptions["stations"]) != set(STATIONS) \
                or set(descriptions["routes"]) != {name.removeprefix("线路") for name in ROUTE_LAYERS}:
            raise RuntimeError("data/subway/descriptions.json 的站点或线路闭包不完整")
        outputs["descriptions.json"] = DESCRIPTIONS.read_bytes()
        for frame in range(1, 5):
            station, svg, _ = engine.export(library, "站点素材/站点整体", frame - 1, (20, 13), OUTPUT, [], {})
            if station.unsupported or station.skipped:
                raise RuntimeError(f"站点帧 {frame}: unsupported/skipped art: {station.unsupported} {station.skipped}")
            outputs[f"station-{frame}.svg"] = svg.encode("utf-8")
    sources = [SOURCE, DESCRIPTIONS, ENGINE, Path(__file__).resolve()]
    manifest = {
        "version": 1,
        "authority": SOURCE.relative_to(ROOT).as_posix(),
        "generator": "tools/export-subway-art.py",
        "sources": {path.relative_to(ROOT).as_posix(): digest(path.read_bytes()) for path in sources},
        "route": {"symbol": "地铁线路UI", "frame": 0, "stage": STAGE,
            "excludedLayers": sorted(EXCLUDED_LAYERS), "colorOverlays": list(ROUTE_LAYERS),
            "rules": ROUTE_RULES},
        "stations": STATIONS,
        "files": {name: {"sha256": digest(data), "bytes": len(data)} for name, data in outputs.items()},
    }
    outputs["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = generate()
    if args.check:
        actual = {path.name for path in OUTPUT.iterdir() if path.is_file()} if OUTPUT.exists() else set()
        if actual != set(expected) or any((OUTPUT / name).read_bytes() != data for name, data in expected.items()):
            raise SystemExit("subway art closure is stale; run python -X utf8 -B tools/export-subway-art.py")
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, data in expected.items():
            (OUTPUT / name).write_bytes(data)
    print(f"Subway art {'verified' if args.check else 'exported'}: {len(expected)} files, {sum(map(len, expected.values()))} bytes")


if __name__ == "__main__":
    main()
