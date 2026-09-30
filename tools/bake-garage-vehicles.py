#!/usr/bin/env python3
"""从已发布的基地 SWF 烘焙三辆车，沿用物品素材工作台的 FFDec 内核。"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import struct
import uuid
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

from PIL import Image, ImageOps, __version__ as pillow_version

ROOT = Path(__file__).resolve().parent.parent
SOURCE = "flashswf/levels/基地场景合集"
SWF = SOURCE + ".swf"
OUTPUT = ROOT / "launcher/web/assets/garage-vehicles"
VEHICLES = {"bicycle": "自行车", "motorcycle": "越野摩托车", "offroad": "越野车"}


def sha(path):
    path = Path(path)
    data = path.read_bytes()
    # Git/Windows checkout 可改换行；文本来源按同一 LF 配方绑定，二进制仍核原始字节。
    if path.suffix.lower() in (".py", ".xml", ".bat"):
        data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return hashlib.sha256(data).hexdigest()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def tags(data, start=0):
    cursor = start
    while cursor + 2 <= len(data):
        header = struct.unpack_from("<H", data, cursor)[0]
        cursor += 2
        code, length = header >> 6, header & 63
        if length == 63:
            length = struct.unpack_from("<I", data, cursor)[0]
            cursor += 4
        if cursor + length > len(data):
            raise ValueError("truncated SWF tag")
        yield code, data[cursor:cursor + length]
        cursor += length
        if code == 0:
            break


def vehicle_ids():
    # 车库的三个 compiled opener 绑定实际 character ID，不能硬编码发布前的 ID。
    scanner = load_module("garage_swfscan", "tools/swf-audit/swfscan.py")
    raw = (ROOT / SWF).read_bytes()
    if raw[:3] not in (b"CWS", b"FWS"):
        raise ValueError("expected Flash CS6 CWS/FWS")
    data = zlib.decompress(raw[8:]) if raw[:3] == b"CWS" else raw[8:]
    bits = scanner.Bits(data)
    width = bits.u(5)
    for _ in range(4):
        bits.s(width)
    bits.align()
    found = {key: [] for key in VEHICLES}

    def visit(part, start=0):
        for code, body in tags(part, start):
            if code == 39:
                visit(body, 4)
            elif code in (26, 70) and body[0] & 2 and "打开车库购车".encode() in body:
                offset = 3 if code == 26 else 4
                if code == 70 and (body[1] & 8 or body[1] & 16):
                    _, offset = scanner.read_string(body, offset)
                character_id = struct.unpack_from("<H", body, offset)[0]
                for key in VEHICLES:
                    if key.encode() + b"\0" in body:
                        found[key].append(character_id)
    visit(data, bits.byte + 4)
    if any(len(ids) != 1 for ids in found.values()):
        raise ValueError("garage opener identity is missing or ambiguous: " + repr(found))
    return {key: ids[0] for key, ids in found.items()}


def source_files():
    sources = {ROOT / (SOURCE + "/LIBRARY/地图/车库.xml")}

    def collect(symbol):
        source = ROOT / (SOURCE + "/LIBRARY/" + symbol + ".xml")
        if source in sources:
            return
        sources.add(source)
        for instance in ET.parse(source).getroot().iter():
            if instance.tag.rsplit("}", 1)[-1] == "DOMSymbolInstance":
                collect(instance.attrib["libraryItemName"])
    for name in VEHICLES.values():
        collect("sprite/" + name)
    return {path.relative_to(ROOT).as_posix(): sha(path) for path in sorted(sources)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="再生至 tmp 并核对来源、字节和精确文件集合")
    checking = parser.parse_args().check
    core = load_module("garage_workbench_core", "tools/asset-workbench/core.py")
    env, ffdec, readiness = core.tool_environment()
    if not readiness["ready"]:
        raise ValueError(readiness["problems"])
    # 环境只属于本次离线 CLI，不改变用户/系统的 Java 配置。
    os.environ.update(env)
    icons = core.module("bake-icons-offline")
    sources = source_files()
    swf_sha = sha(ROOT / SWF)
    previous_path = OUTPUT / "manifest.json"
    if previous_path.exists():
        previous = json.loads(previous_path.read_text(encoding="utf-8"))
        if previous.get("sourceSwf", {}).get("sha256") == swf_sha and previous.get("sources") != sources:
            raise ValueError("XFL changed without a new published SWF; publish the base XFL before baking")
    identifiers = vehicle_ids()
    scratch = ROOT / "tmp/u13/vehicle-bake" / uuid.uuid4().hex
    scratch.mkdir(parents=True)
    export_result, export_error = icons.export_sprites(ffdec, ROOT, scratch, SWF, list(identifiers.values()), 2, 120)
    if export_error:
        raise ValueError(export_error)
    tools = [Path(__file__).relative_to(ROOT).as_posix(), "tools/bake-icons-offline.py",
             "tools/asset-workbench/core.py", "tools/swf-audit/swfscan.py", "tools/ffdec/ffdec.jar", "tools/ffdec/ffdec.bat"]
    manifest = {"schema": "cf7.garage-vehicle-images.v1", "recipe": "ffdec-first-frame-trim-lanczos-lossless-webp-v1",
                "textHashMode": "utf8-lf",
                "sourceSwf": {"path": SWF, "sha256": swf_sha}, "sources": sources,
                "tools": {tool: sha(ROOT / tool) for tool in tools},
                "renderer": {"pillow": pillow_version, "sourceZoom": 2, "widthLimit": 960, "heightLimit": 640}, "vehicles": {}}
    total_bytes = 0
    for key, name in VEHICLES.items():
        frame = icons.find_exported_frame(scratch, SWF, identifiers[key], 1)
        if frame is None:
            raise ValueError("missing first frame: " + key)
        with Image.open(frame) as source:
            image = source.convert("RGBA")
        bounds = image.getchannel("A").getbbox()
        if bounds is None:
            raise ValueError("empty vehicle: " + key)
        image = image.crop(bounds)
        mirrored = key in ("bicycle", "motorcycle")
        if mirrored:
            image = ImageOps.mirror(image)
        # 统一朝向，裁掉时间轴留白，按显示尺寸等比缩小；保留原稿 alpha 和细节。
        image.thumbnail((960, 640), Image.Resampling.LANCZOS)
        destination = scratch / (key + ".webp")
        image.save(destination, "WEBP", lossless=True, quality=100, method=6, exact=True)
        with Image.open(destination) as encoded:
            if encoded.convert("RGBA").tobytes() != image.tobytes():
                raise ValueError("lossless encoding changed pixels")
        size = destination.stat().st_size
        if size > 512 * 1024:
            raise ValueError("vehicle exceeds 512 KiB: " + key)
        total_bytes += size
        manifest["vehicles"][key] = {"symbol": "sprite/" + name, "characterId": identifiers[key], "frame": 1,
            "mirrorX": mirrored, "sourceAlphaBounds": list(bounds), "uri": "assets/garage-vehicles/" + key + ".webp",
            "width": image.width, "height": image.height, "bytes": size, "sha256": sha(destination),
            "pixelSha256": hashlib.sha256(image.tobytes()).hexdigest()}
    if total_bytes > 1024 * 1024:
        raise ValueError("vehicle images exceed 1 MiB")
    manifest["totalBytes"] = total_bytes
    text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    expected = sorted([key + ".webp" for key in VEHICLES] + ["manifest.json"])
    if checking:
        if sorted(path.name for path in OUTPUT.iterdir()) != expected:
            raise ValueError("unexpected vehicle asset file set")
        if previous_path.read_text(encoding="utf-8") != text:
            raise ValueError("stale vehicle manifest; rerun the baker")
        for key in VEHICLES:
            if sha(OUTPUT / (key + ".webp")) != manifest["vehicles"][key]["sha256"]:
                raise ValueError("vehicle pixels differ from regenerated source: " + key)
    else:
        if OUTPUT.exists() and any(path.name not in expected for path in OUTPUT.iterdir()):
            raise ValueError("preserve unexpected files before baking")
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for key in VEHICLES:
            core.atomic_bytes(OUTPUT / (key + ".webp"), (scratch / (key + ".webp")).read_bytes())
        core.atomic_bytes(previous_path, text.encode("utf-8"))
    print(json.dumps({"ok": True, "check": checking, "vehicles": 3, "totalBytes": total_bytes, "exportRecovery": export_result}, ensure_ascii=False))


if __name__ == "__main__":
    main()
