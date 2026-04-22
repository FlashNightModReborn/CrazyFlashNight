from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

from PIL import Image, ImageDraw


NS = {"x": "http://ns.adobe.com/xfl/2008/"}
AVATAR_DIAMETER = 44
FFDEC_FALLBACK_IDS = {
    "PROPHET头像": 371,
    "排骨头像": 380,
    "机哥头像": 383,
    "阿波头像": 386,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export CF7 map avatar assets and source metadata from XFL sources.")
    parser.add_argument("--clean", action="store_true", help="Delete the output directory before exporting.")
    parser.add_argument(
        "--output",
        default="launcher/web/assets/map/avatars",
        help="Output directory relative to repo root.",
    )
    parser.add_argument(
        "--meta-output",
        default="launcher/web/modules/map-avatar-source-data.js",
        help="Generated JS metadata file relative to repo root.",
    )
    return parser.parse_args()


def load_xml(path: Path) -> ET.Element:
    return ET.fromstring(path.read_text(encoding="utf-8"))


def parse_float(value: str | None, default: float = 0.0) -> float:
    if value is None or value == "":
        return default
    return float(value)


def round2(value: float) -> float:
    return round(float(value), 2)


def resolve_source_file(repo_root: Path, xfl_dir: Path, href: str, symbol_stem: str) -> Path | None:
    library_dir = xfl_dir / "LIBRARY"
    portraits_dir = repo_root / "flashswf" / "portraits" / "profiles"
    candidates = []

    def normalize_profile_key(value: str) -> str:
        return "".join(ch for ch in str(value or "").casefold() if ch.isalnum())

    profile_stem = symbol_stem.removesuffix("头像")
    profile_key = normalize_profile_key(profile_stem)

    # Portrait profiles are the real source of truth for NPC faces.
    # Prefer them over XFL-side bitmap placeholders, otherwise some symbols export as black circles.
    for profile_path in portraits_dir.glob("*.png"):
        if normalize_profile_key(profile_path.stem) == profile_key:
            candidates.append(profile_path)

    if href:
        candidates.extend(
            [
                library_dir / href,
                library_dir / f"{href}.png",
            ]
        )

    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def decode_bitmap_data(dat_path: Path) -> Image.Image:
    data = dat_path.read_bytes()
    row_bytes = int.from_bytes(data[2:4], "little")
    width = int.from_bytes(data[4:6], "little")
    height = int.from_bytes(data[6:8], "little")
    raw = None
    for offset in (28, 24, 20, 32, 16):
        try:
            raw = zlib.decompress(data[offset:])
            break
        except zlib.error:
            continue
    if raw is None:
        raise ValueError(f"Unable to decompress bitmap payload for {dat_path.name}")
    if len(raw) != row_bytes * height:
        raise ValueError(f"Unexpected raw bitmap payload size for {dat_path.name}: {len(raw)} != {row_bytes * height}")
    return Image.frombuffer("RGBA", (width, height), raw, "raw", "ARGB", row_bytes, 1)


def parse_symbol_spec(symbol_path: Path) -> dict:
    symbol_root = load_xml(symbol_path)
    bitmap_node = symbol_root.find(".//x:DOMBitmapInstance", NS)
    if bitmap_node is None:
        raise ValueError(f"{symbol_path.name}: no DOMBitmapInstance")

    matrix_node = bitmap_node.find("./x:matrix/x:Matrix", NS)
    matrix_node = matrix_node if matrix_node is not None else ET.Element("Matrix")

    return {
        "symbolName": symbol_path.stem,
        "bitmapName": bitmap_node.attrib.get("libraryItemName", "").strip(),
        "scaleX": parse_float(matrix_node.attrib.get("a"), 1.0),
        "scaleY": parse_float(matrix_node.attrib.get("d"), parse_float(matrix_node.attrib.get("a"), 1.0)),
        "tx": parse_float(matrix_node.attrib.get("tx"), 0.0),
        "ty": parse_float(matrix_node.attrib.get("ty"), 0.0),
        "size": {"w": AVATAR_DIAMETER, "h": AVATAR_DIAMETER},
    }


def render_symbol_avatar(source_image: Image.Image, spec: dict) -> Image.Image:
    source_rgba = source_image.convert("RGBA")
    scale_x = max(0.01, float(spec["scaleX"]))
    scale_y = max(0.01, float(spec["scaleY"]))
    target_size = (
        max(1, int(round(source_rgba.width * scale_x))),
        max(1, int(round(source_rgba.height * scale_y))),
    )
    if target_size != source_rgba.size:
        source_rgba = source_rgba.resize(target_size, Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (AVATAR_DIAMETER, AVATAR_DIAMETER), (0, 0, 0, 0))
    canvas.paste(source_rgba, (int(round(spec["tx"])), int(round(spec["ty"]))), source_rgba)

    mask = Image.new("L", (AVATAR_DIAMETER, AVATAR_DIAMETER), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, AVATAR_DIAMETER - 1, AVATAR_DIAMETER - 1), fill=255)

    output = Image.new("RGBA", (AVATAR_DIAMETER, AVATAR_DIAMETER), (0, 0, 0, 0))
    output.paste(canvas, (0, 0), mask)
    return output


def render_profile_avatar(source_image: Image.Image) -> Image.Image:
    source_rgba = source_image.convert("RGBA")
    if source_rgba.width <= 0 or source_rgba.height <= 0:
        return Image.new("RGBA", (AVATAR_DIAMETER, AVATAR_DIAMETER), (0, 0, 0, 0))

    crop_size = min(source_rgba.width, source_rgba.height)
    left = max(0, int(round((source_rgba.width - crop_size) / 2)))
    top = max(0, int(round((source_rgba.height - crop_size) / 2 - crop_size * 0.08)))
    top = min(top, max(0, source_rgba.height - crop_size))
    cropped = source_rgba.crop((left, top, left + crop_size, top + crop_size))
    fitted = cropped.resize((AVATAR_DIAMETER, AVATAR_DIAMETER), Image.Resampling.LANCZOS)

    mask = Image.new("L", (AVATAR_DIAMETER, AVATAR_DIAMETER), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, AVATAR_DIAMETER - 1, AVATAR_DIAMETER - 1), fill=255)

    output = Image.new("RGBA", (AVATAR_DIAMETER, AVATAR_DIAMETER), (0, 0, 0, 0))
    output.paste(fitted, (0, 0), mask)
    return output


def extract_avatar_instance_map(map_xml_path: Path) -> dict[str, dict]:
    result: dict[str, dict] = {}
    root = load_xml(map_xml_path)

    for node in root.iter():
        if node.tag.split("}")[-1] != "DOMSymbolInstance":
            continue

        library_item_name = node.attrib.get("libraryItemName", "").strip()
        if "头像合集/" not in library_item_name:
            continue

        symbol_name = library_item_name.split("/")[-1].strip()
        if not symbol_name or symbol_name == "室友头像":
            continue

        center_x = parse_float(node.attrib.get("centerPoint3DX"), 0.0)
        center_y = parse_float(node.attrib.get("centerPoint3DY"), 0.0)
        result[symbol_name] = {
            "symbolName": symbol_name,
            "center": {"x": round2(center_x), "y": round2(center_y)},
            "rect": {
                "x": round2(center_x - (AVATAR_DIAMETER / 2)),
                "y": round2(center_y - (AVATAR_DIAMETER / 2)),
                "w": AVATAR_DIAMETER,
                "h": AVATAR_DIAMETER,
            },
        }
    return result


def write_metadata_js(path: Path, entries: dict[str, dict]) -> None:
    payload = json.dumps(entries, ensure_ascii=True, indent=2)
    content = (
        "var MapAvatarSourceData = (function() {\n"
        "    'use strict';\n\n"
        f"    var _entries = {payload};\n\n"
        "    var _entriesByAssetUrl = {};\n\n"
        "    function clone(value) {\n"
        "        return value ? JSON.parse(JSON.stringify(value)) : null;\n"
        "    }\n\n"
        "    function normalizeSymbolName(value) {\n"
        "        return String(value || '')\n"
            "            .replace(/^.*[\\\\/]/, '')\n"
            "            .replace(/\\.png$/i, '')\n"
            "            .trim();\n"
        "    }\n\n"
        "    Object.keys(_entries).forEach(function(key) {\n"
        "        var entry = _entries[key];\n"
        "        if (!entry || !entry.assetUrl) return;\n"
        "        _entriesByAssetUrl[normalizeSymbolName(entry.assetUrl)] = entry;\n"
        "    });\n\n"
        "    function getBySymbolName(symbolName) {\n"
        "        var key = normalizeSymbolName(symbolName);\n"
        "        return _entries[key] ? clone(_entries[key]) : null;\n"
        "    }\n\n"
        "    function getByAssetUrl(assetUrl) {\n"
        "        var key = normalizeSymbolName(assetUrl);\n"
        "        if (_entriesByAssetUrl[key]) {\n"
        "            return clone(_entriesByAssetUrl[key]);\n"
        "        }\n"
        "        var entryKeys = Object.keys(_entries);\n"
        "        for (var i = 0; i < entryKeys.length; i += 1) {\n"
        "            var entry = _entries[entryKeys[i]];\n"
        "            if (entry && normalizeSymbolName(entry.assetUrl) === key) {\n"
        "                return clone(entry);\n"
        "            }\n"
        "        }\n"
        "        return getBySymbolName(assetUrl);\n"
        "    }\n\n"
        "    function getAll() {\n"
        "        return clone(_entries);\n"
        "    }\n\n"
        "    return {\n"
        "        getBySymbolName: getBySymbolName,\n"
        "        getByAssetUrl: getByAssetUrl,\n"
        "        getAll: getAll\n"
        "    };\n"
        "})();\n"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def export_with_ffdec(ffdec_cli: Path, swf_path: Path, output_dir: Path, symbol_names: list[str]) -> dict[str, Path]:
    if not symbol_names:
        return {}

    temp_dir = output_dir.parents[3] / "tmp_ffdec_avatar_export"
    if temp_dir.exists():
        shutil.rmtree(temp_dir)

    ids = ",".join(str(FFDEC_FALLBACK_IDS[name]) for name in symbol_names)
    subprocess.run(
        [str(ffdec_cli), "-format", "sprite:png", "-selectid", ids, "-export", "sprite", str(temp_dir), str(swf_path)],
        check=True,
    )

    results = {}
    for symbol_name in symbol_names:
        sprite_id = FFDEC_FALLBACK_IDS[symbol_name]
        exported_png = temp_dir / f"DefineSprite_{sprite_id}" / "1.png"
        if exported_png.exists():
            results[symbol_name] = exported_png
    return results


def main() -> None:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    xfl_dir = repo_root / "flashswf" / "UI" / "地图界面"
    dom_path = xfl_dir / "DOMDocument.xml"
    avatar_dir = xfl_dir / "LIBRARY" / "头像合集"
    map_xml_path = xfl_dir / "LIBRARY" / "地图界面.xml"
    output_dir = repo_root / args.output
    meta_output = repo_root / args.meta_output
    ffdec_cli = repo_root / "tools" / "ffdec" / "ffdec-cli.exe"
    swf_path = repo_root / "flashswf" / "UI" / "地图界面.swf"

    if args.clean and output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    dom_root = load_xml(dom_path)
    bitmap_items = {}
    for item in dom_root.findall(".//x:DOMBitmapItem", NS):
        item_name = item.attrib.get("name", "").strip()
        bitmap_items[item_name] = {
            "href": item.attrib.get("href", "").strip(),
            "bitmapDataHRef": item.attrib.get("bitmapDataHRef", "").strip(),
            "sourceExternalFilepath": item.attrib.get("sourceExternalFilepath", "").strip(),
        }

    symbol_specs: dict[str, dict] = {}
    for symbol_path in sorted(avatar_dir.glob("*头像.xml")):
        if symbol_path.name == "室友头像.xml":
            continue
        try:
            spec = parse_symbol_spec(symbol_path)
            symbol_specs[symbol_path.stem] = spec
        except Exception:
            continue

    instance_map = extract_avatar_instance_map(map_xml_path)
    metadata_entries: dict[str, dict] = {}
    exported = 0
    skipped = []
    ffdec_needed = []

    for symbol_path in sorted(avatar_dir.glob("*头像.xml")):
        if symbol_path.name == "室友头像.xml":
            continue

        symbol_name = symbol_path.stem
        spec = symbol_specs.get(symbol_name)
        if not spec:
            skipped.append(f"{symbol_name}: missing symbol spec")
            continue

        bitmap_meta = bitmap_items.get(spec["bitmapName"])
        if not bitmap_meta:
            skipped.append(f"{symbol_name}: missing DOMBitmapItem for {spec['bitmapName']}")
            continue

        output_path = output_dir / f"{symbol_name}.png"
        rendered = None
        source_file = resolve_source_file(repo_root, xfl_dir, bitmap_meta["href"], symbol_name)
        try:
            if source_file is not None:
                source_image = Image.open(source_file)
                if "flashswf/portraits/profiles" in source_file.as_posix().replace("\\", "/"):
                    rendered = render_profile_avatar(source_image)
                else:
                    rendered = render_symbol_avatar(source_image, spec)
            else:
                bitmap_data_ref = bitmap_meta["bitmapDataHRef"]
                if not bitmap_data_ref:
                    raise ValueError("no resolvable href or bitmapDataHRef")
                dat_path = xfl_dir / "bin" / bitmap_data_ref
                if not dat_path.exists():
                    raise ValueError(f"missing bitmapDataHRef {bitmap_data_ref}")
                rendered = render_symbol_avatar(decode_bitmap_data(dat_path), spec)
        except Exception as exc:
            if symbol_name in FFDEC_FALLBACK_IDS:
                ffdec_needed.append(symbol_name)
            else:
                skipped.append(f"{symbol_name}: {exc}")
            rendered = None

        if rendered is not None:
            rendered.save(output_path)
            exported += 1

        entry = {
            "symbolName": symbol_name,
            "assetUrl": f"assets/map/avatars/{symbol_name}.png",
            "size": {"w": AVATAR_DIAMETER, "h": AVATAR_DIAMETER},
            "crop": {
                "scaleX": round2(spec["scaleX"]),
                "scaleY": round2(spec["scaleY"]),
                "tx": round2(spec["tx"]),
                "ty": round2(spec["ty"]),
            },
        }
        if symbol_name in instance_map:
            entry.update(instance_map[symbol_name])
        metadata_entries[symbol_name] = entry

    if ffdec_needed and ffdec_cli.exists():
        exported_pngs = export_with_ffdec(ffdec_cli, swf_path, output_dir, ffdec_needed)
        for symbol_name in ffdec_needed:
            output_path = output_dir / f"{symbol_name}.png"
            exported_png = exported_pngs.get(symbol_name)
            if exported_png is None:
                skipped.append(f"{symbol_name}: FFDec fallback export missing sprite output")
                continue
            shutil.copyfile(exported_png, output_path)
            exported += 1

    for symbol_name, entry in metadata_entries.items():
        output_path = output_dir / f"{symbol_name}.png"
        if output_path.exists():
            with Image.open(output_path) as img:
                entry["assetSize"] = {"w": img.width, "h": img.height}

    write_metadata_js(meta_output, metadata_entries)

    print(f"[map-avatar] exported {exported} assets -> {output_dir}")
    print(f"[map-avatar] wrote metadata -> {meta_output}")
    if skipped:
        print("[map-avatar] skipped:")
        for item in skipped:
            print(f"  - {item}")


if __name__ == "__main__":
    main()
