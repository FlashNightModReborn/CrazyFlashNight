#!/usr/bin/env python3
"""Build the fixed-geometry, exact-shopId portrait asset closure.

The runtime manifest is intentionally small.  All expensive source evidence is
kept in provenance.json so Web consumers do not depend on DialogueView or on
Flash/XFL implementation details.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, __version__ as PILLOW_VERSION


SCHEMA = "cf7-shop-portraits-v1"
PROVENANCE_SCHEMA = "cf7-shop-portrait-provenance-v1"
RECEIPT_SCHEMA = "cf7-shop-portrait-promotion-receipt-v1"
GENERATOR_VERSION = "1.0.0"
GEOMETRY = {"width": 256, "height": 256}
PADDING = 16
EXPECTED_LIST_COUNT = 35
EXPECTED_ACTIVE_COUNT = 34
EXCLUDED_SHOPS = {"幸存老兵-暂时停用"}
DEFAULT_EXPRESSION = "普通"
DIALOGUE_LINKAGE = "对话框肖像"
WEAPON_MASTER = "武器大师"
HEEHO = "heeho君"
HEEHO_MAP_LINKAGE = "地图-彩蛋地图"
HEEHO_OUTER_ITEM = "NPC/NPC-heeho君/NPC-heeho君"
HEEHO_BODY_ITEM = "NPC/NPC-heeho君/霜精"
HEEHO_HAT_ITEM = "NPC/NPC-heeho君/零件/带帽霜精头"
HEEHO_GLASSES_ITEM = "NPC/NPC-heeho君/零件/墨镜"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class BakeError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=str(project_root))
    parser.add_argument(
        "--output-dir",
        default=str(project_root / "launcher" / "web" / "assets" / "shop-portraits"),
    )
    parser.add_argument("--ffdec", default=str(project_root / "tools" / "ffdec" / "ffdec-cli.exe"))
    parser.add_argument("--check", action="store_true", help="Fresh-rebuild and compare without promotion.")
    parser.add_argument("--keep-work", action="store_true")
    parser.add_argument("--ffdec-timeout-seconds", type=int, default=240)
    return parser.parse_args()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def repo_path(path: Path, root: Path, label: str) -> str:
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError as error:
        raise BakeError(f"{label} escapes project root: {path}") from error


def artifact(path: Path, root: Path) -> dict[str, Any]:
    return {
        "path": repo_path(path, root, "artifact"),
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
    }


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def iter_desc(parent: ET.Element, name: str) -> Iterable[ET.Element]:
    for elem in parent.iter():
        if local_name(elem.tag) == name:
            yield elem


def first_child(parent: ET.Element, name: str) -> ET.Element | None:
    for elem in list(parent):
        if local_name(elem.tag) == name:
            return elem
    return None


def require_file(path: Path, label: str) -> Path:
    if not path.is_file():
        raise BakeError(f"Missing {label}: {path}")
    return path


def is_identity(value: Any, max_units: int = 80) -> bool:
    return (
        isinstance(value, str)
        and bool(value)
        and value.strip() == value
        and not value.isspace()
        and value.casefold() != "undefined"
        and len(value.encode("utf-16-le")) // 2 <= max_units
        and not any(unicodedata.category(char) == "Cc" for char in value)
    )


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise BakeError(f"Invalid {label}: {path}: {error}") from error
    if not isinstance(value, dict):
        raise BakeError(f"{label} must be an object: {path}")
    return value


def load_dialogue_baker(root: Path):
    path = require_file(root / "tools" / "bake-dialogue-portraits.py", "dialogue baker")
    spec = importlib.util.spec_from_file_location("cf7_dialogue_portrait_baker", path)
    if spec is None or spec.loader is None:
        raise BakeError(f"Cannot load dialogue baker: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, path


def run_command(args: list[str], cwd: Path, timeout_seconds: int) -> str:
    try:
        result = subprocess.run(
            args,
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as error:
        raise BakeError(f"Command timed out: {' '.join(args)}") from error
    if result.returncode != 0:
        raise BakeError(f"Command failed ({result.returncode}): {' '.join(args)}\n{result.stdout[-2000:]}")
    return result.stdout


def read_active_shops(root: Path) -> tuple[list[str], dict[str, Any]]:
    list_path = require_file(root / "data" / "shops" / "list.xml", "shop list")
    try:
        list_root = ET.parse(list_path).getroot()
    except ET.ParseError as error:
        raise BakeError(f"Invalid shop list: {error}") from error
    all_ids: list[str] = []
    files: list[dict[str, Any]] = []
    for node in list_root.iter("shops"):
        relative = (node.text or "").strip()
        if not relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
            raise BakeError(f"Unsafe shop list path: {relative!r}")
        path = require_file(root / "data" / "shops" / relative, "shop document")
        doc = read_json(path, "shop document")
        shop_id = doc.get("shopId")
        if not is_identity(shop_id):
            raise BakeError(f"Invalid shopId in {path}: {shop_id!r}")
        all_ids.append(shop_id)
        files.append(artifact(path, root))
    if len(all_ids) != EXPECTED_LIST_COUNT or len(set(all_ids)) != EXPECTED_LIST_COUNT:
        raise BakeError(f"Shop list closure drift: count={len(all_ids)} unique={len(set(all_ids))}")
    excluded = [shop_id for shop_id in all_ids if shop_id in EXCLUDED_SHOPS]
    if excluded != ["幸存老兵-暂时停用"]:
        raise BakeError(f"Disabled shop closure drift: {excluded}")
    active = [shop_id for shop_id in all_ids if shop_id not in EXCLUDED_SHOPS]
    if len(active) != EXPECTED_ACTIVE_COUNT or len(set(active)) != EXPECTED_ACTIVE_COUNT:
        raise BakeError(f"Active shop closure drift: count={len(active)} unique={len(set(active))}")
    return active, {
        "list": artifact(list_path, root),
        "listedCount": len(all_ids),
        "activeCount": len(active),
        "excludedShopIds": sorted(EXCLUDED_SHOPS),
        "shopDocuments": files,
    }


def export_assets(root: ET.Element) -> dict[str, list[int]]:
    result: dict[str, list[int]] = {}
    for node in root.iter("item"):
        if node.get("type") != "ExportAssetsTag":
            continue
        tags = node.find("tags")
        names = node.find("names")
        if tags is None or names is None:
            continue
        ids = [int(item.text or "0") for item in tags.findall("item")]
        labels = [item.text or "" for item in names.findall("item")]
        if len(ids) != len(labels):
            raise BakeError("SWF ExportAssets tags/names length mismatch")
        for label, character_id in zip(labels, ids):
            result.setdefault(label, []).append(character_id)
    return result


def definitions(root: ET.Element) -> dict[int, ET.Element]:
    result: dict[int, ET.Element] = {}
    for node in root.iter("item"):
        if node.get("type") != "DefineSpriteTag":
            continue
        character_id = int(node.get("spriteId") or "0")
        if character_id <= 0 or character_id in result:
            raise BakeError(f"Invalid/duplicate DefineSprite id: {character_id}")
        result[character_id] = node
    return result


def unique_export(exports: dict[str, list[int]], name: str) -> int:
    matches = sorted(set(exports.get(name) or []))
    if len(matches) != 1:
        raise BakeError(f"SWF linkage must resolve uniquely: {name!r} -> {matches}")
    return matches[0]


def first_frame_places(sprite: ET.Element) -> list[ET.Element]:
    sub_tags = sprite.find("subTags")
    if sub_tags is None:
        raise BakeError("DefineSprite has no subTags")
    result: list[ET.Element] = []
    for node in sub_tags.findall("item"):
        if node.get("type") == "ShowFrameTag":
            break
        if (node.get("type") or "").startswith("PlaceObject") and int(node.get("characterId") or "0") > 0:
            result.append(node)
    return result


def sprite_labels(sprite: ET.Element) -> dict[str, int]:
    sub_tags = sprite.find("subTags")
    if sub_tags is None:
        raise BakeError("DefineSprite has no subTags")
    frame = 1
    labels: dict[str, int] = {}
    for node in sub_tags.findall("item"):
        if node.get("type") == "FrameLabelTag":
            name = (node.get("name") or "").strip()
            if name and name not in labels:
                labels[name] = frame
        elif node.get("type") == "ShowFrameTag":
            frame += 1
    return labels


def xfl_matrix(instance: ET.Element) -> dict[str, float]:
    matrix_parent = first_child(instance, "matrix")
    matrix = first_child(matrix_parent, "Matrix") if matrix_parent is not None else None
    attrs = matrix.attrib if matrix is not None else {}
    return {
        "a": float(attrs.get("a", "1")),
        "b": float(attrs.get("b", "0")),
        "c": float(attrs.get("c", "0")),
        "d": float(attrs.get("d", "1")),
        "tx": float(attrs.get("tx", "0")),
        "ty": float(attrs.get("ty", "0")),
    }


def swf_matrix(place: ET.Element) -> dict[str, float]:
    matrix = place.find("matrix")
    if matrix is None:
        raise BakeError("SWF placement lacks matrix")
    attrs = matrix.attrib
    has_scale = attrs.get("hasScale") == "true"
    has_rotate = attrs.get("hasRotate") == "true"
    return {
        "a": float(attrs.get("scaleX", "0")) if has_scale else 1.0,
        "b": float(attrs.get("rotateSkew0", "0")) if has_rotate else 0.0,
        "c": float(attrs.get("rotateSkew1", "0")) if has_rotate else 0.0,
        "d": float(attrs.get("scaleY", "0")) if has_scale else 1.0,
        "tx": float(attrs.get("translateX", "0")) / 20.0,
        "ty": float(attrs.get("translateY", "0")) / 20.0,
    }


def matrix_matches(left: dict[str, float], right: dict[str, float]) -> bool:
    return all(math.isclose(left[key], right[key], rel_tol=0.0, abs_tol=0.00005) for key in left)


def unique_symbol_instance_on_frame(path: Path, item_name: str, frame_index: int) -> ET.Element:
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as error:
        raise BakeError(f"Invalid XFL symbol {path}: {error}") from error
    matches: list[ET.Element] = []
    for frame in iter_desc(root, "DOMFrame"):
        start = int(frame.get("index") or "0")
        duration = int(frame.get("duration") or "1")
        if frame_index < start or frame_index >= start + duration:
            continue
        matches.extend(
            node
            for node in iter_desc(frame, "DOMSymbolInstance")
            if node.get("libraryItemName") == item_name
        )
    if len(matches) != 1:
        raise BakeError(
            f"XFL symbol placement must be unique on frame {frame_index}: "
            f"{path} / {item_name} -> {len(matches)}"
        )
    return matches[0]


def unique_place_by_matrix(sprite: ET.Element, expected: dict[str, float], label: str) -> ET.Element:
    matches = [place for place in first_frame_places(sprite) if matrix_matches(swf_matrix(place), expected)]
    if len(matches) != 1:
        ids = [place.get("characterId") for place in matches]
        raise BakeError(f"SWF placement must be unique for {label}: {ids}")
    return matches[0]


def xfl_frame_count(path: Path) -> int:
    root = ET.parse(path).getroot()
    maximum = 0
    for frame in iter_desc(root, "DOMFrame"):
        start = int(frame.get("index") or "0")
        duration = int(frame.get("duration") or "1")
        maximum = max(maximum, start + duration)
    return maximum


def find_sprite_dir(base: Path, character_id: int) -> Path:
    candidates = [
        path
        for path in base.iterdir()
        if path.is_dir() and (path.name == f"DefineSprite_{character_id}" or path.name.startswith(f"DefineSprite_{character_id}_"))
    ]
    if len(candidates) != 1:
        raise BakeError(f"FFDec sprite output must be unique: id={character_id} matches={len(candidates)}")
    return candidates[0]


def export_sprite(
    ffdec: Path,
    root: Path,
    swf: Path,
    character_id: int,
    output: Path,
    timeout_seconds: int,
) -> Path:
    if output.exists():
        raise BakeError(f"Fresh sprite output already exists: {output}")
    output.mkdir(parents=True)
    run_command(
        [
            str(ffdec),
            "-onerror",
            "abort",
            "-ignorebackground",
            "-zoom",
            "1",
            "-format",
            "sprite:png",
            "-selectid",
            str(character_id),
            "-export",
            "sprite",
            str(output),
            str(swf),
        ],
        root,
        timeout_seconds,
    )
    return find_sprite_dir(output, character_id)


def alpha_bounds(image: Image.Image) -> dict[str, int]:
    bbox = image.convert("RGBA").getchannel("A").getbbox()
    if bbox is None:
        raise BakeError("Portrait has empty alpha")
    left, top, right, bottom = bbox
    return {"x": left, "y": top, "width": right - left, "height": bottom - top}


def normalize_portrait(source: Path) -> tuple[bytes, dict[str, int]]:
    with Image.open(source) as opened:
        image = opened.convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise BakeError(f"Source portrait has empty alpha: {source}")
    crop = image.crop(bbox)
    max_width = GEOMETRY["width"] - PADDING * 2
    max_height = GEOMETRY["height"] - PADDING * 2
    scale = min(max_width / crop.width, max_height / crop.height)
    target_width = max(1, min(max_width, round(crop.width * scale)))
    target_height = max(1, min(max_height, round(crop.height * scale)))
    resized = crop.resize((target_width, target_height), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (GEOMETRY["width"], GEOMETRY["height"]), (0, 0, 0, 0))
    x = (GEOMETRY["width"] - target_width) // 2
    y = (GEOMETRY["height"] - target_height) // 2
    canvas.alpha_composite(resized, (x, y))
    import io

    buffer = io.BytesIO()
    canvas.save(buffer, format="PNG", compress_level=9, optimize=False)
    value = buffer.getvalue()
    bounds = alpha_bounds(canvas)
    if bounds["x"] < 0 or bounds["y"] < 0 or bounds["x"] + bounds["width"] > 256 or bounds["y"] + bounds["height"] > 256:
        raise BakeError(f"Normalized bounds escape canvas: {bounds}")
    return value, bounds


def ffdec_version(root: Path) -> str:
    meta = require_file(root / "tools" / "ffdec" / "com.jpexs.decompiler.flash.metainfo.xml", "FFDec metadata")
    release = ET.parse(meta).getroot().find(".//release")
    version = release.get("version") if release is not None else None
    if not version:
        raise BakeError("FFDec metadata has no release version")
    return version


def build_internal_sources(
    root: Path,
    ffdec: Path,
    work: Path,
    timeout_seconds: int,
    shop_ids: list[str],
    dialogue_baker: Any,
) -> tuple[dict[str, Path], dict[str, dict[str, Any]]]:
    swf = require_file(root / "flashswf" / "UI" / "对话框界面.swf", "dialogue UI SWF")
    xfl = require_file(
        root / "flashswf" / "UI" / "对话框界面" / "LIBRARY" / "对话框肖像.xml",
        "dialogue portrait XFL",
    )
    xml_path = work / "dialogue-ui-swf.xml"
    dialogue_baker.export_swf_xml(ffdec, root, swf, xml_path, timeout_seconds)
    swf_root = ET.parse(xml_path).getroot()
    character_id = unique_export(export_assets(swf_root), DIALOGUE_LINKAGE)
    defs = definitions(swf_root)
    sprite = defs.get(character_id)
    if sprite is None:
        raise BakeError(f"Dialogue linkage is not a DefineSprite: {character_id}")
    frame_count = int(sprite.get("frameCount") or "0")
    labels = sprite_labels(sprite)
    ranges = {item["key"]: item for item in dialogue_baker.frame_ranges_from_dialogue_portrait(xfl)}
    if labels.get(WEAPON_MASTER) != 257:
        raise BakeError(f"Current dialogue SWF Weapon Master frame drift: {labels.get(WEAPON_MASTER)}")
    weapon_range = ranges.get(WEAPON_MASTER)
    if weapon_range != {"key": WEAPON_MASTER, "index": 256, "duration": 6}:
        raise BakeError(f"Current dialogue XFL Weapon Master range drift: {weapon_range}")
    frame_dir = export_sprite(ffdec, root, swf, character_id, work / "dialogue-sprite", timeout_seconds)
    images: dict[str, Path] = {}
    evidence: dict[str, dict[str, Any]] = {}
    for shop_id in shop_ids:
        item = ranges.get(shop_id)
        if not item:
            raise BakeError(f"Dialogue XFL has no exact shop portrait: {shop_id}")
        frame = int(item["index"]) + 1
        if labels.get(shop_id) != frame:
            raise BakeError(f"Dialogue XFL/SWF label mismatch: {shop_id} xfl={frame} swf={labels.get(shop_id)}")
        source_png = require_file(frame_dir / f"{frame}.png", f"dialogue frame {shop_id}")
        images[shop_id] = source_png
        evidence[shop_id] = {
            "kind": "dialogue-ui-linkage",
            "sourceSwf": artifact(swf, root),
            "sourceXfl": artifact(xfl, root),
            "linkage": DIALOGUE_LINKAGE,
            "characterId": character_id,
            "declaredFrameCount": frame_count,
            "xflFrameIndex": int(item["index"]),
            "frame1Based": frame,
            "duration": int(item["duration"]),
        }
    return images, evidence


def build_external_source(
    root: Path,
    ffdec: Path,
    work: Path,
    timeout_seconds: int,
    shop_id: str,
    source_path: Path,
    dialogue_baker: Any,
) -> tuple[Path, dict[str, Any]]:
    source_path = require_file(source_path, f"external dialogue SWF for {shop_id}")
    group = work / "external" / hashlib.sha1(shop_id.encode("utf-8")).hexdigest()[:12]
    xml_path = group / "source.xml"
    frames_dir = group / "frames"
    dialogue_baker.export_swf_xml(ffdec, root, source_path, xml_path, timeout_seconds)
    labels = dialogue_baker.timeline_labels_from_swf_xml(xml_path)
    frame = labels.get(DEFAULT_EXPRESSION)
    if not isinstance(frame, int) or frame <= 0:
        raise BakeError(f"External portrait has no valid default frame: {shop_id}")
    dialogue_baker.export_external_frames(
        ffdec,
        root,
        source_path,
        {DEFAULT_EXPRESSION: frame},
        frames_dir,
        1,
        timeout_seconds,
    )
    source_png = require_file(frames_dir / f"{frame}.png", f"external default frame {shop_id}")
    return source_png, {
        "kind": "external-dialogue-swf",
        "sourceSwf": artifact(source_path, root),
        "expression": DEFAULT_EXPRESSION,
        "frame1Based": frame,
    }


def build_heeho_source(
    root: Path,
    ffdec: Path,
    work: Path,
    timeout_seconds: int,
) -> tuple[Path, dict[str, Any]]:
    base = root / "flashswf" / "levels" / "地图-彩蛋地图"
    swf = require_file(root / "flashswf" / "levels" / "地图-彩蛋地图.swf", "heeho map SWF")
    map_xfl = require_file(base / "LIBRARY" / "地图-彩蛋地图.xml", "heeho map linkage XFL")
    outer_xfl = require_file(base / "LIBRARY" / "NPC" / "NPC-heeho君" / "NPC-heeho君.xml", "heeho outer XFL")
    body_xfl = require_file(base / "LIBRARY" / "NPC" / "NPC-heeho君" / "霜精.xml", "heeho body XFL")
    tween_xfls = [
        require_file(base / "LIBRARY" / "NPC" / "NPC-heeho君" / f"补间 {index}.xml", f"heeho tween {index}")
        for index in range(1, 5)
    ]
    map_root = ET.parse(map_xfl).getroot()
    if map_root.get("linkageIdentifier") != HEEHO_MAP_LINKAGE or map_root.get("linkageExportForAS") != "true":
        raise BakeError("heeho map XFL linkage drift")
    map_instance = unique_symbol_instance_on_frame(map_xfl, HEEHO_OUTER_ITEM, 0)
    outer_instance = unique_symbol_instance_on_frame(outer_xfl, HEEHO_BODY_ITEM, 0)
    if xfl_frame_count(outer_xfl) != 10 or xfl_frame_count(body_xfl) != 37:
        raise BakeError("heeho XFL frame-count drift")
    body_root = ET.parse(body_xfl).getroot()
    neutral_heads = [
        node
        for node in iter_desc(body_root, "DOMSymbolInstance")
        if node.get("libraryItemName") == "NPC/NPC-heeho君/补间 1"
    ]
    if len(neutral_heads) != 1:
        raise BakeError("heeho neutral head frame is not unique")
    for tween in tween_xfls:
        tween_root = ET.parse(tween).getroot()
        refs = [node.get("libraryItemName") for node in iter_desc(tween_root, "DOMSymbolInstance")]
        if refs.count(HEEHO_HAT_ITEM) != 1 or refs.count(HEEHO_GLASSES_ITEM) != 1:
            raise BakeError(f"heeho identity accessories drift: {tween}")
        if any(ref and "杰克霜精" in ref for ref in refs):
            raise BakeError(f"heeho source aliases ordinary Jack Frost: {tween}")

    swf_xml = work / "heeho-map-swf.xml"
    run_command([str(ffdec), "-onerror", "abort", "-swf2xml", str(swf), str(swf_xml)], root, timeout_seconds)
    swf_root = ET.parse(swf_xml).getroot()
    defs = definitions(swf_root)
    map_character_id = unique_export(export_assets(swf_root), HEEHO_MAP_LINKAGE)
    map_sprite = defs.get(map_character_id)
    if map_sprite is None:
        raise BakeError("heeho map linkage is not a DefineSprite")
    outer_place = unique_place_by_matrix(map_sprite, xfl_matrix(map_instance), "heeho outer")
    outer_character_id = int(outer_place.get("characterId") or "0")
    outer_sprite = defs.get(outer_character_id)
    if outer_sprite is None or int(outer_sprite.get("frameCount") or "0") != 10:
        raise BakeError(f"heeho outer DefineSprite drift: {outer_character_id}")
    body_place = unique_place_by_matrix(outer_sprite, xfl_matrix(outer_instance), "heeho body")
    body_character_id = int(body_place.get("characterId") or "0")
    body_sprite = defs.get(body_character_id)
    if body_sprite is None or int(body_sprite.get("frameCount") or "0") != 37:
        raise BakeError(f"heeho body DefineSprite drift: {body_character_id}")
    frame_dir = export_sprite(ffdec, root, swf, body_character_id, work / "heeho-sprite", timeout_seconds)
    frame = 1
    source_png = require_file(frame_dir / f"{frame}.png", "heeho neutral frame")
    evidence_xfls = [map_xfl, outer_xfl, body_xfl, *tween_xfls]
    return source_png, {
        "kind": "exact-xfl-swf-pilot",
        "sourceSwf": artifact(swf, root),
        "sourceXfl": [artifact(path, root) for path in evidence_xfls],
        "mapLinkage": HEEHO_MAP_LINKAGE,
        "mapCharacterId": map_character_id,
        "outerLibraryItem": HEEHO_OUTER_ITEM,
        "outerCharacterId": outer_character_id,
        "outerDeclaredFrameCount": 10,
        "bodyLibraryItem": HEEHO_BODY_ITEM,
        "characterId": body_character_id,
        "declaredFrameCount": 37,
        "xflNeutralFrameIndex": 0,
        "frame1Based": frame,
        "identityAccessories": [HEEHO_HAT_ITEM, HEEHO_GLASSES_ITEM],
        "ordinaryJackAlias": False,
    }


def subject_closure(entries: dict[str, dict[str, Any]]) -> str:
    lines = [f"{shop_id}\0{entry['uri']}\0{entry['sha256']}" for shop_id, entry in sorted(entries.items())]
    return sha256_bytes(("\n".join(lines) + "\n").encode("utf-8"))


def build_stage(root: Path, ffdec: Path, stage: Path, work: Path, timeout_seconds: int) -> dict[str, Any]:
    dialogue_baker, dialogue_baker_path = load_dialogue_baker(root)
    active_shops, active_source = read_active_shops(root)
    dialogue_manifest_path = require_file(
        root / "launcher" / "web" / "assets" / "dialogue-portraits" / "manifest.json",
        "dialogue portrait manifest",
    )
    dialogue_manifest = read_json(dialogue_manifest_path, "dialogue portrait manifest")
    if dialogue_manifest.get("schema") != "cf7-dialogue-portraits-v2":
        raise BakeError("Dialogue portrait manifest schema drift")
    dialogue_entries = dialogue_manifest.get("entries")
    if not isinstance(dialogue_entries, dict):
        raise BakeError("Dialogue portrait manifest entries missing")
    source_choices: dict[str, dict[str, Any]] = {}
    internal_ids: list[str] = []
    external_ids: list[str] = []
    for shop_id in active_shops:
        if shop_id == HEEHO:
            source_choices[shop_id] = {"kind": "heeho"}
            continue
        entry = dialogue_entries.get(shop_id)
        if shop_id == WEAPON_MASTER:
            if entry is not None:
                raise BakeError("Weapon Master must be refreshed from current dialogue source, not stale manifest")
            source_choices[shop_id] = {"kind": "internal"}
            internal_ids.append(shop_id)
            continue
        if not isinstance(entry, dict) or entry.get("key") != shop_id:
            raise BakeError(f"Dialogue manifest lacks exact shopId entry: {shop_id}")
        kind = entry.get("source")
        source_path = entry.get("sourcePath")
        if kind == "dialogue-ui-sprite":
            source_choices[shop_id] = {"kind": "internal", "entry": entry}
            internal_ids.append(shop_id)
        elif kind == "external-swf" and isinstance(source_path, str) and source_path:
            source_choices[shop_id] = {"kind": "external", "path": source_path, "entry": entry}
            external_ids.append(shop_id)
        else:
            raise BakeError(f"Unsupported dialogue source for shop {shop_id}: {kind!r}")
    if len(internal_ids) != 8 or len(external_ids) != 25:
        raise BakeError(f"Shop source partition drift: internal={len(internal_ids)} external={len(external_ids)}")

    internal_images, internal_evidence = build_internal_sources(
        root, ffdec, work, timeout_seconds, internal_ids, dialogue_baker
    )
    source_images: dict[str, Path] = dict(internal_images)
    source_evidence: dict[str, dict[str, Any]] = dict(internal_evidence)
    for index, shop_id in enumerate(external_ids, 1):
        print(f"[external {index}/{len(external_ids)}] {shop_id}", flush=True)
        choice = source_choices[shop_id]
        source_path = (root / choice["path"]).resolve()
        repo_path(source_path, root, f"external source for {shop_id}")
        image, evidence = build_external_source(
            root, ffdec, work, timeout_seconds, shop_id, source_path, dialogue_baker
        )
        source_images[shop_id] = image
        source_evidence[shop_id] = evidence
    heeho_image, heeho_evidence = build_heeho_source(root, ffdec, work, timeout_seconds)
    source_images[HEEHO] = heeho_image
    source_evidence[HEEHO] = heeho_evidence
    if set(source_images) != set(active_shops) or set(source_evidence) != set(active_shops):
        raise BakeError("Source image/evidence closure does not equal active shops")

    subjects_dir = stage / "subjects"
    subjects_dir.mkdir(parents=True)
    entries: dict[str, dict[str, Any]] = {}
    provenance_sources: dict[str, dict[str, Any]] = {}
    for shop_id in active_shops:
        source_png = source_images[shop_id]
        extracted_sha = sha256_file(source_png)
        png, bounds = normalize_portrait(source_png)
        output_sha = sha256_bytes(png)
        if not SHA256_RE.fullmatch(output_sha):
            raise BakeError("Internal SHA-256 invariant failed")
        uri = f"subjects/{output_sha}.png"
        subject_path = stage / uri
        if subject_path.exists() and subject_path.read_bytes() != png:
            raise BakeError(f"Content-address collision: {uri}")
        subject_path.write_bytes(png)
        entry = {
            "uri": uri,
            "width": GEOMETRY["width"],
            "height": GEOMETRY["height"],
            "bounds": bounds,
            "sha256": output_sha,
        }
        entries[shop_id] = entry
        provenance_sources[shop_id] = {
            **source_evidence[shop_id],
            "extractedPngSha256": extracted_sha,
            "output": entry,
        }

    manifest = {"schema": SCHEMA, "geometry": GEOMETRY, "entries": entries}
    manifest_bytes = canonical_json(manifest)
    script_path = Path(__file__).resolve()
    ffdec_meta = root / "tools" / "ffdec" / "com.jpexs.decompiler.flash.metainfo.xml"
    ffdec_jar = root / "tools" / "ffdec" / "lib" / "ffdec.jar"
    if not ffdec_jar.is_file():
        ffdec_jar = require_file(root / "tools" / "ffdec" / "ffdec.jar", "FFDec jar")
    provenance = {
        "schema": PROVENANCE_SCHEMA,
        "generatorVersion": GENERATOR_VERSION,
        "geometry": {**GEOMETRY, "padding": PADDING, "fit": "alpha-bounds-contain-center"},
        "toolchain": {
            "generator": artifact(script_path, root),
            "dialogueBaker": artifact(dialogue_baker_path, root),
            "python": platform.python_version(),
            "pillow": PILLOW_VERSION,
            "ffdecVersion": ffdec_version(root),
            "ffdecCli": artifact(ffdec, root),
            "ffdecJar": artifact(ffdec_jar, root),
            "ffdecMetadata": artifact(ffdec_meta, root),
        },
        "activeShopSource": active_source,
        "dialogueManifest": artifact(dialogue_manifest_path, root),
        "sourcePartition": {"externalDialogue": 25, "internalDialogue": 8, "exactXflSwfPilot": 1},
        "sources": provenance_sources,
    }
    provenance_bytes = canonical_json(provenance)
    receipt = {
        "schema": RECEIPT_SCHEMA,
        "promotionOrder": ["subjects", "provenance.json", "promotion-receipt.json", "manifest.json"],
        "subjectsFirst": True,
        "manifestLast": True,
        "shopCount": len(entries),
        "subjectFileCount": len({entry["uri"] for entry in entries.values()}),
        "subjectClosureSha256": subject_closure(entries),
        "provenanceSha256": sha256_bytes(provenance_bytes),
        "manifestSha256": sha256_bytes(manifest_bytes),
    }
    receipt_bytes = canonical_json(receipt)
    (stage / "provenance.json").write_bytes(provenance_bytes)
    (stage / "promotion-receipt.json").write_bytes(receipt_bytes)
    # Runtime authority is materialized last, after every referenced subject and sidecar.
    (stage / "manifest.json").write_bytes(manifest_bytes)
    return {
        "shops": len(entries),
        "subjects": len({entry["uri"] for entry in entries.values()}),
        "manifestSha256": receipt["manifestSha256"],
        "provenanceSha256": receipt["provenanceSha256"],
        "subjectClosureSha256": receipt["subjectClosureSha256"],
        "weaponMaster": provenance_sources[WEAPON_MASTER],
        "heeho": provenance_sources[HEEHO],
    }


def tree_files(path: Path) -> dict[str, bytes]:
    if not path.is_dir():
        return {}
    return {
        file.relative_to(path).as_posix(): file.read_bytes()
        for file in sorted(path.rglob("*"))
        if file.is_file()
    }


def compare_tree(stage: Path, output: Path) -> None:
    expected = tree_files(stage)
    actual = tree_files(output)
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    changed = sorted(path for path in set(expected) & set(actual) if expected[path] != actual[path])
    if missing or extra or changed:
        raise BakeError(f"Shop portrait output drift: missing={missing} extra={extra} changed={changed}")


def atomic_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".promotion-tmp")
    if temporary.exists():
        temporary.unlink()
    shutil.copyfile(source, temporary)
    os.replace(temporary, destination)


def promote_stage(stage: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    subjects = output / "subjects"
    subjects.mkdir(parents=True, exist_ok=True)
    expected_subjects = {path.name for path in (stage / "subjects").glob("*.png")}
    for source in sorted((stage / "subjects").glob("*.png")):
        atomic_copy(source, subjects / source.name)
    atomic_copy(stage / "provenance.json", output / "provenance.json")
    atomic_copy(stage / "promotion-receipt.json", output / "promotion-receipt.json")
    # The runtime authority moves only after all of its referenced files exist.
    atomic_copy(stage / "manifest.json", output / "manifest.json")
    for stale in sorted(subjects.glob("*.png")):
        if stale.name not in expected_subjects:
            stale.unlink()


def main() -> None:
    args = parse_args()
    root = Path(args.project_root).resolve()
    output = Path(args.output_dir).resolve()
    ffdec = require_file(Path(args.ffdec).resolve(), "FFDec CLI")
    repo_path(ffdec, root, "FFDec CLI")
    if args.ffdec_timeout_seconds < 30 or args.ffdec_timeout_seconds > 900:
        raise SystemExit("--ffdec-timeout-seconds must be within 30..900")
    tmp_root = root / "tmp"
    tmp_root.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="shop-portrait-bake-", dir=tmp_root))
    stage = work / "stage"
    stage.mkdir()
    try:
        summary = build_stage(root, ffdec, stage, work / "work", args.ffdec_timeout_seconds)
        if args.check:
            compare_tree(stage, output)
            mode = "check"
        else:
            promote_stage(stage, output)
            compare_tree(stage, output)
            mode = "write"
        print(json.dumps({"status": "passed", "mode": mode, **summary}, ensure_ascii=False, indent=2))
    except BakeError as error:
        raise SystemExit(f"shop portrait bake failed: {error}") from error
    finally:
        if args.keep_work:
            print(f"work={work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
