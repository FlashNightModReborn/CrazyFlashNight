"""从彩蛋地图选关 FLA 生成 Web 原生美术、布局与音效；--check 只读核对闭包。"""
import argparse
import copy
import hashlib
import importlib.util
import io
import json
import struct
import sys
import tempfile
import wave
import xml.etree.ElementTree as ET
import zipfile
import zlib
from pathlib import Path

from PIL import Image

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "flashswf/UI/彩蛋地图关卡界面.fla"
ENGINE = ROOT / "tools/xfl-ui-svg/xfl_to_svg.py"
OUTPUT = ROOT / "launcher/web/assets/egg-stage-select"
NS = {"x": "http://ns.adobe.com/xfl/2008/"}
SVG_NS = "{http://www.w3.org/2000/svg}"
STAGE = (540, 370)
PREVIEWS = {
    "forest_depth": ("密林深处", "M 3 1729503969.dat", 8.7, 44.75),
    "machine_zone": ("机器游荡区", "M 3 1729510808.dat", 9.1, 129.95),
    "forest_center": ("密林中央", "M 6 1729511538.dat", 9.1, 215),
}
SOUNDS = {
    "panel-enter.wav": "M 5 1729920125.dat",
    "confirm-open.wav": "M 6 1729920125.dat",
    "confirm-cancel.wav": "M 7 1729920125.dat",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_xfl():
    data = bytearray(SOURCE.read_bytes())
    eocd = data.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise RuntimeError("彩蛋选关 FLA 缺少 ZIP EOCD")
    offset = struct.unpack_from("<I", data, eocd + 16)[0]
    struct.pack_into("<I", data, eocd + 12, eocd - offset)
    return io.BytesIO(data)


def decode_bitmap(data):
    if len(data) < 26 or data[:2] != b"\x03\x05":
        raise RuntimeError("不支持的彩蛋位图缓存")
    stride, width, height = struct.unpack_from("<3H", data, 2)
    if stride != width * 4 or width < 1 or height < 1:
        raise RuntimeError("彩蛋位图尺寸无效")
    if data[25] == 1:
        chunks = []
        position = 26
        while True:
            size = struct.unpack_from("<H", data, position)[0]
            position += 2
            if not size:
                break
            chunks.append(data[position:position + size])
            position += size
        pixels = zlib.decompress(b"".join(chunks))
    elif data[25] == 0:
        pixels = data[26:]
    else:
        raise RuntimeError("彩蛋位图压缩标志无效")
    if len(pixels) != stride * height:
        raise RuntimeError("彩蛋位图像素长度不符")
    rgba = bytearray(len(pixels))
    for index in range(0, len(pixels), 4):
        alpha, red, green, blue = pixels[index:index + 4]
        if alpha and alpha != 255:
            red = min(255, (red * 255 + alpha // 2) // alpha)
            green = min(255, (green * 255 + alpha // 2) // alpha)
            blue = min(255, (blue * 255 + alpha // 2) // alpha)
        rgba[index:index + 4] = bytes((red, green, blue, alpha))
    image = Image.frombytes("RGBA", (width, height), bytes(rgba))
    output = io.BytesIO()
    image.save(output, format="PNG", compress_level=9)
    return output.getvalue(), width, height


def pcm_wav(data):
    output = io.BytesIO()
    with wave.open(output, "wb") as stream:
        stream.setnchannels(2)
        stream.setsampwidth(2)
        stream.setframerate(44100)
        stream.writeframes(data)
    return output.getvalue()


def matrix(element):
    row = element.find("x:matrix/x:Matrix", NS)
    keys = ("a", "b", "c", "d", "tx", "ty")
    return [float(row.get(key, "1" if key in ("a", "d") else "0")) for key in keys]


def multiply(left, right):
    a, b, c, d, tx, ty = left
    e, f, g, h, u, v = right
    return [a * e + b * g, a * f + b * h, c * e + d * g,
            c * f + d * h, a * u + b * v + tx, c * u + d * v + ty]


def generate():
    spec = importlib.util.spec_from_file_location("egg_stage_xfl_svg", ENGINE)
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    outputs = {}
    with tempfile.TemporaryDirectory(prefix="egg-stage-art-", dir=ROOT / "tmp") as temporary:
        xfl = Path(temporary) / "xfl"
        with zipfile.ZipFile(read_xfl()) as archive:
            archive.extractall(xfl)
        library = xfl / "LIBRARY"
        document = ET.parse(xfl / "DOMDocument.xml")
        timeline = copy.deepcopy(document.getroot().find(".//x:DOMTimeline", NS))
        for instance in timeline.findall(".//x:DOMSymbolInstance", NS):
            if instance.get("libraryItemName") == "基本框":
                instance.set("symbolType", "graphic")
                instance.set("loop", "stop")
                instance.set("firstFrame", "30")
        wrapper = ET.Element("{%s}DOMSymbolItem" % NS["x"], {"name": "彩蛋选关主界面"})
        wrapper.append(ET.Element("{%s}timeline" % NS["x"]))
        wrapper[0].append(timeline)
        ET.ElementTree(wrapper).write(library / "彩蛋选关主界面.xml", encoding="utf-8", xml_declaration=True)

        def export(symbol, frame, stage):
            report, svg, _ = engine.export(library, symbol, frame, stage, OUTPUT, ["__none__"], {"__none__": "__none__"})
            return report, ET.fromstring(svg)

        report, main = export("彩蛋选关主界面", 39, STAGE)
        for layer in list(main):
            if layer.tag != SVG_NS + "defs" and layer.get("data-layer") != "图层 1":
                main.remove(layer)
        outputs["panel-base.svg"] = ET.tostring(main, encoding="utf-8") + b"\n"
        _, close = export("button/Symbol 538", 0, (12, 12))
        close.set("viewBox", "-6 -6 12 12")
        outputs["close.svg"] = ET.tostring(close, encoding="utf-8") + b"\n"
        confirm_report, confirm = export("弹出框整体", 14, (720, 320))
        outputs["confirm-dialog.svg"] = ET.tostring(confirm, encoding="utf-8") + b"\n"
        for report, allowed in ((report, {"blendMode=hardlight", "blendMode=add", "元素:DOMBitmapInstance", "stroke:DashedStroke"}),
                                (confirm_report, {"stroke:DashedStroke"})):
            unexpected = [row for row in report.unsupported if row.get("feature") not in allowed]
            if unexpected:
                raise RuntimeError(f"彩蛋美术存在未审计降级: {unexpected}")

        preview_layout = {}
        for destination, (layer_name, cache, x, y) in PREVIEWS.items():
            data, width, height = decode_bitmap((xfl / "bin" / cache).read_bytes())
            filename = destination + ".png"
            outputs[filename] = data
            layer = timeline.find(".//x:DOMLayer[@name='%s']" % layer_name, NS)
            instance = layer.find(".//x:DOMSymbolInstance", NS)
            symbol = ET.parse(library / (instance.get("libraryItemName") + ".xml"))
            bitmap = symbol.find(".//x:DOMBitmapInstance", NS)
            combined = multiply(matrix(instance), matrix(bitmap))
            preview_layout[destination] = {
                "file": filename, "x": x, "y": y,
                "width": round(width * combined[0], 4), "height": round(height * combined[3], 4),
            }
        for filename, cache in SOUNDS.items():
            outputs[filename] = pcm_wav((xfl / "bin" / cache).read_bytes())

        text_symbol = ET.parse(library / "文字.xml")
        text_layout = []
        for text in text_symbol.findall(".//x:DOMStaticText", NS):
            runs = ["".join(run.find("x:characters", NS).itertext()) for run in text.findall("x:textRuns/x:DOMTextRun", NS)]
            position = matrix(text)
            text_layout.append({"runs": runs, "x": 323.85 + position[4], "y": 55.05 + position[5]})
        layout = {
            "version": 1, "stage": {"width": STAGE[0], "height": STAGE[1], "frameRate": 24},
            "intro": {"baseDurationMs": 1000 * 31 / 24, "contentDurationMs": 1000 * 8 / 24, "baseAlpha": 0.53},
            "exit": {"durationMs": 1000 * 20 / 24, "contentDurationMs": 1000 * 8 / 24},
            "confirm": {"durationMs": 1000 * 14 / 24, "scale": 0.702301025390625, "x": -37.15, "y": 211.3},
            "previews": preview_layout, "texts": text_layout,
        }
        outputs["layout.json"] = (json.dumps(layout, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    sources = [SOURCE, ENGINE, Path(__file__).resolve()]
    manifest = {
        "version": 1, "authority": SOURCE.relative_to(ROOT).as_posix(),
        "generator": "tools/export-egg-stage-art.py",
        "sources": {path.relative_to(ROOT).as_posix(): digest(path.read_bytes()) for path in sources},
        "timeline": {"frames": 60, "frameRate": 24, "intro": [31, 39], "idle": 39, "exit": [40, 59]},
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
            raise SystemExit("egg stage art closure is stale; run python -X utf8 -B tools/export-egg-stage-art.py")
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, data in expected.items():
            (OUTPUT / name).write_bytes(data)
    print(f"Egg stage art {'verified' if args.check else 'exported'}: {len(expected)} files, {sum(map(len, expected.values()))} bytes")


if __name__ == "__main__":
    main()
