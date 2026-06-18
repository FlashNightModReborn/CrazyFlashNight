from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET
import zlib
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from asset_timeline_export import FrameDedupeIndex, compressed_timeline_entries

try:
    from PIL import Image
except ImportError:
    Image = None


BARE_AMPERSAND_RE = re.compile(r"&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9_.:-]*;)")
ATTACH_RE = re.compile(
    r'attachMovie\(\s*_parent\._parent\._parent\.([A-Za-z0-9_\u4e00-\u9fff]+)\s*,\s*"([^"]+)"'
)
SVG_MATRIX_RE = re.compile(
    r'<g\s+transform="matrix\(\s*[-0-9.]+\s*,\s*[-0-9.]+\s*,\s*[-0-9.]+\s*,\s*[-0-9.]+\s*,\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*\)"'
)
SCRIPT_DEFINE_DIR_RE = re.compile(r"^DefineSprite_(\d+)(?:_|$)")
SCRIPT_FRAME_DIR_RE = re.compile(r"^frame_(\d+)$")
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT_RE = re.compile(r"//.*?(?=\r?\n|$)")
STOP_CALL_RE = re.compile(r"\bstop\s*\(\s*\)\s*;?")

BODY_FIELDS = ("身体", "上臂", "左下臂", "右下臂")
LOWER_FIELDS = ("屁股", "左大腿", "右大腿", "小腿")
HAND_FIELDS = ("左手", "右手")
WEAPON_DRESSUP_FIELDS = ("dressup1", "dressup2", "dressup3")

DEFAULT_GENDERS = ("男", "女")
IGNORED_ITEM_XML = {"asset_source_map.xml", "list.xml", "bullets_cases.xml", "missileConfigs.xml"}
DRESSUP_TIMELINE_IDENTITY_KEYS = ("uri", "width", "height", "originX", "originY")
DRESSUP_FACE_SKINS = ("男变装-基本脸型", "女变装-基本脸型")
PRESERVED_EXPORT_KEYS = ("export", "frames", "timelineFrames", "nestedAnimation")
DRESSUP_CONFLICT_SOURCE_PREFERENCES = {
    "刀-方钢锤": (
        ("flashswf/arts/new/雾人装备调整.swf", "1.冷兵器/钝器/方钢锤/刀-方钢锤"),
    ),
    "刀-激光剑": (
        ("flashswf/arts/new/乔恩.swf", "冷兵器/激光剑/刀-激光剑"),
        ("flashswf/arts/new/我的素材7421.swf", "冷兵器/激光剑/刀-激光剑"),
    ),
    "刀-长墨白铁": (
        ("flashswf/arts/new/雾人装备调整.swf", "1.冷兵器/长柄/01.长墨白铁/刀-长墨白铁"),
    ),
    "男变装-基本脸型": (
        ("flashswf/UI/对话框界面.swf", "sprite/主角/男变装-基本脸型"),
        ("flashswf/arts/things0.swf", "sprite/男变装-基本脸型"),
    ),
    "男变装-废城军装上装上臂": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城军装上装上臂"),
    ),
    "男变装-废城军装下装右大腿": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城军装下装右大腿"),
    ),
    "男变装-废城军装下装小腿": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城军装下装小腿"),
    ),
    "男变装-废城军装下装左大腿": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城军装下装左大腿"),
    ),
    "男变装-废城军装手套右手": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城军装手套右手"),
    ),
    "男变装-废城军装手套左手": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城军装手套左手"),
    ),
    "男变装-废城军装脚": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城军装脚"),
    ),
    "男变装-废城军装面具帽": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城军装面具帽"),
    ),
    "男变装-废城防弹军装上装身体": (
        ("flashswf/arts/new/原体融合生物.swf", "男变装-废城防弹军装上装身体"),
    ),
    "男变装-牙狼铠上臂": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/男变装-牙狼铠上臂"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/男变装-牙狼铠上臂"),
    ),
    "男变装-牙狼铠右下臂": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/牙狼右下臂"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/牙狼右下臂"),
    ),
    "男变装-牙狼铠右大腿": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/牙狼右大腿"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/牙狼右大腿"),
    ),
    "男变装-牙狼铠头盔": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/男变装-牙狼铠头盔"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/男变装-牙狼铠头盔"),
    ),
    "男变装-牙狼铠小腿": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/牙狼小腿"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/牙狼小腿"),
    ),
    "男变装-牙狼铠屁股": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/牙狼屁股"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/牙狼屁股"),
    ),
    "男变装-牙狼铠左下臂": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/牙狼左下臂"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/牙狼左下臂"),
    ),
    "男变装-牙狼铠左大腿": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/牙狼左大腿"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/牙狼左大腿"),
    ),
    "男变装-牙狼铠战鞋": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/男变装-牙狼铠鞋子"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/男变装-牙狼铠鞋子"),
    ),
    "男变装-牙狼铠身体": (
        ("flashswf/levels/地图-彩蛋地图.swf", "所有素材/牙狼素材/男变装-牙狼铠身体"),
        ("flashswf/arts/new/伊恩的素材.swf", "牙狼素材/男变装-牙狼铠身体"),
    ),
    "枪-手枪-COLT PYTHON": (
        ("flashswf/arts/things.swf", "1.枪械相关/手枪/枪-手枪-COLT PYTHON"),
    ),
    "枪-手枪-Glock 18": (
        ("flashswf/arts/things.swf", "1.枪械相关/手枪/枪-手枪-Glock 18"),
    ),
    "枪-手枪-Mossberg500": (
        ("flashswf/arts/things.swf", "1.枪械相关/手枪/枪-手枪-Mossberg500"),
    ),
    "枪-手枪-m9": (
        ("flashswf/UI/对话框界面.swf", "sprite/主角/枪械&女体/Symbol 1121"),
        ("flashswf/arts/things.swf", "1.枪械相关/手枪/枪-手枪-m9"),
    ),
    "枪-长枪-G36": (
        ("flashswf/UI/对话框界面.swf", "sprite/主角/枪械&女体/Symbol 1105"),
        ("flashswf/arts/things.swf", "1.枪械相关/长枪/枪-长枪-G36"),
    ),
    "枪-长枪-能量狙击枪": (
        ("flashswf/arts/new/乔恩.swf", "枪械/能量狙击枪/能量狙击枪"),
        ("flashswf/arts/new/我的素材7421.swf", "枪械/能量狙击枪/能量狙击枪"),
    ),
}


@dataclass(frozen=True)
class Matrix:
    a: float = 1.0
    b: float = 0.0
    c: float = 0.0
    d: float = 1.0
    tx: float = 0.0
    ty: float = 0.0

    def to_json(self) -> dict[str, float]:
        return {
            "a": round(self.a, 6),
            "b": round(self.b, 6),
            "c": round(self.c, 6),
            "d": round(self.d, 6),
            "tx": round(self.tx, 6),
            "ty": round(self.ty, 6),
        }


IDENTITY = Matrix()


def multiply(left: Matrix, right: Matrix) -> Matrix:
    return Matrix(
        a=left.a * right.a + left.c * right.b,
        b=left.b * right.a + left.d * right.b,
        c=left.a * right.c + left.c * right.d,
        d=left.b * right.c + left.d * right.d,
        tx=left.a * right.tx + left.c * right.ty + left.tx,
        ty=left.b * right.tx + left.d * right.ty + left.ty,
    )


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description=(
            "Build Web dressup manifests from data/items, asset_source_map.xml, "
            "and the dialogue portrait XFL rig. This is the offline metadata side "
            "of the Canvas paper-doll pipeline."
        )
    )
    parser.add_argument(
        "--output-dir",
        default=str(project_root / "launcher" / "web" / "assets" / "dressup"),
        help="Output directory for manifest/report JSON. Default: launcher/web/assets/dressup.",
    )
    parser.add_argument(
        "--genders",
        choices=["both", "male", "female"],
        default="both",
        help="Gender expansion for upper/lower dressup keys. Default: both.",
    )
    parser.add_argument(
        "--no-write",
        action="store_true",
        help="Analyze only; do not write launcher/web/assets/dressup files.",
    )
    parser.add_argument(
        "--export-assets",
        action="store_true",
        help="Use FFDec to export covered skin keys as PNG frame files and write export metadata.",
    )
    parser.add_argument("--limit", type=int, default=0, help="Only process the first N skin keys when exporting assets.")
    parser.add_argument("--name", action="append", default=[], help="Only export the named skin key; repeatable.")
    parser.add_argument(
        "--ffdec",
        default=str(project_root / "tools" / "ffdec" / "ffdec-cli.exe"),
        help="FFDec CLI executable path.",
    )
    parser.add_argument("--zoom", type=int, default=2, help="FFDec sprite export zoom. Default: 2.")
    parser.add_argument("--fps", type=float, default=24.0, help="Frame rate metadata for exported frame sequences. Default: 24.")
    parser.add_argument(
        "--static-stop-policy",
        choices=["auto", "off"],
        default="auto",
        help=(
            "When exporting equipment assets, collapse multi-frame sprites with a plain frame-1 stop() "
            "timeline script to a first-frame PNG. Default: auto."
        ),
    )
    parser.add_argument(
        "--tmp-dir",
        default=str(project_root / "tmp" / "dressup-bake-offline"),
        help="Temporary FFDec export directory. Default: tmp/dressup-bake-offline.",
    )
    parser.add_argument(
        "--asset-dir",
        default="skins",
        help="Asset directory under --output-dir for exported PNG frames. Default: skins.",
    )
    parser.add_argument(
        "--ffdec-timeout-seconds",
        type=int,
        default=120,
        help="Timeout for each FFDec subprocess. Use 0 to disable. Default: 120.",
    )
    parser.add_argument("--keep-tmp", action="store_true", help="Keep temporary FFDec exports after completion.")
    return parser.parse_args()


def xml_text(path: Path) -> str:
    return BARE_AMPERSAND_RE.sub("&amp;", path.read_text(encoding="utf-8-sig"))


def xml_root(path: Path) -> ET.Element:
    try:
        return ET.fromstring(xml_text(path))
    except ET.ParseError as exc:
        raise ET.ParseError(f"{path}: {exc}") from exc


def child_text(element: ET.Element, tag: str) -> str:
    child = element.find(tag)
    if child is None or child.text is None:
        return ""
    return child.text.strip()


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def iter_children_named(element: ET.Element, name: str) -> list[ET.Element]:
    return [child for child in list(element) if local_name(child.tag) == name]


def first_child_named(element: ET.Element, name: str) -> ET.Element | None:
    for child in list(element):
        if local_name(child.tag) == name:
            return child
    return None


def descendants_named(element: ET.Element, name: str) -> list[ET.Element]:
    return [node for node in element.iter() if local_name(node.tag) == name]


def genders_from_arg(value: str) -> tuple[str, ...]:
    if value == "male":
        return ("男",)
    if value == "female":
        return ("女",)
    return DEFAULT_GENDERS


def add_skin(
    skin_keys: dict[str, dict[str, Any]],
    key: str,
    use: str,
    item_name: str,
    source_file: str,
) -> None:
    if not key:
        return
    entry = skin_keys.setdefault(key, {"uses": set(), "items": set(), "sourceFiles": set()})
    entry["uses"].add(use or "<empty>")
    entry["items"].add(item_name)
    entry["sourceFiles"].add(source_file)


def derive_item_fields(use: str, dressup: str, genders: tuple[str, ...]) -> dict[str, dict[str, str]]:
    fields: dict[str, dict[str, str]] = {}
    if not dressup:
        return fields
    if use == "上装装备":
        for gender in genders:
            fields[gender] = {field: gender + dressup + field for field in BODY_FIELDS}
    elif use == "下装装备":
        for gender in genders:
            fields[gender] = {field: gender + dressup + field for field in LOWER_FIELDS}
    elif use == "手部装备":
        shared = {field: dressup + field for field in HAND_FIELDS}
        for gender in genders:
            fields[gender] = dict(shared)
    elif use == "头部装备":
        for gender in genders:
            fields[gender] = {"面具": dressup}
    elif use == "脚部装备":
        for gender in genders:
            fields[gender] = {"脚": dressup}
    elif use == "刀":
        for gender in genders:
            fields[gender] = {"刀_装扮": dressup, "刀1_装扮": dressup}
    elif use == "长枪":
        for gender in genders:
            fields[gender] = {"长枪_装扮": dressup}
    elif use == "手枪":
        for gender in genders:
            fields[gender] = {"手枪_装扮": dressup, "手枪2_装扮": dressup}
    elif use == "手雷":
        for gender in genders:
            fields[gender] = {"手雷_装扮": dressup}
    else:
        for gender in genders:
            fields[gender] = {"dressup": dressup}
    return fields


def merge_gender_fields(target: dict[str, dict[str, str]], extra: dict[str, dict[str, str]]) -> None:
    for gender, fields in extra.items():
        target.setdefault(gender, {}).update(fields)


def add_appearance_skin_keys(project_root: Path, skin_keys: dict[str, dict[str, Any]]) -> None:
    for key in DRESSUP_FACE_SKINS:
        add_skin(skin_keys, key, "脸型", key, "appearance:face")

    hairstyle_path = project_root / "data" / "items" / "hairstyle.xml"
    if not hairstyle_path.exists():
        return
    root = xml_root(hairstyle_path)
    for hair in root.findall("Hair"):
        key = child_text(hair, "Identifier")
        if not key or key == "光头":
            continue
        add_skin(skin_keys, key, "发型", key, hairstyle_path.name)


def load_items(project_root: Path, genders: tuple[str, ...]) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    items_dir = project_root / "data" / "items"
    items: dict[str, Any] = {}
    skin_keys: dict[str, dict[str, Any]] = {}

    for path in sorted(items_dir.glob("*.xml")):
        if path.name in IGNORED_ITEM_XML:
            continue
        root = xml_root(path)
        for item in root.findall("item"):
            name = child_text(item, "name") or f"{path.name}:{len(items)}"
            use = child_text(item, "use")
            data = item.find("data")
            if data is None:
                continue
            dressup = child_text(data, "dressup")
            fields_by_gender = derive_item_fields(use, dressup, genders)
            for gender_fields in fields_by_gender.values():
                for key in gender_fields.values():
                    add_skin(skin_keys, key, use, name, path.name)

            if use == "刀":
                for field_name, target_field in (
                    ("dressup1", "刀1_装扮"),
                    ("dressup2", "刀2_装扮"),
                    ("dressup3", "刀3_装扮"),
                ):
                    value = child_text(data, field_name)
                    if value:
                        for gender in genders:
                            fields_by_gender.setdefault(gender, {})[target_field] = value
                        add_skin(skin_keys, value, f"{use}:{field_name}", name, path.name)

            items[name] = {
                "use": use,
                "icon": child_text(item, "icon"),
                "dressup": dressup,
                "helmet": child_text(item, "helmet").lower() == "true",
                "fieldsByGender": fields_by_gender,
                "sourceFile": path.name,
            }
    add_appearance_skin_keys(project_root, skin_keys)
    return items, skin_keys


def load_asset_map(project_root: Path) -> dict[str, dict[str, Any]]:
    path = project_root / "data" / "items" / "asset_source_map.xml"
    root = xml_root(path)
    sources: dict[str, list[dict[str, str]]] = defaultdict(list)
    for asset in root.findall("asset"):
        asset_id = (asset.get("id") or "").strip()
        if not asset_id:
            continue
        sources[asset_id].append(
            {
                "swf": asset.get("swf") or "",
                "symbolName": asset.get("symbolName") or "",
            }
        )
    result: dict[str, dict[str, Any]] = {}
    for asset_id, matches in sources.items():
        result[asset_id] = {
            "swf": matches[0]["swf"],
            "symbolName": matches[0]["symbolName"],
            "conflict": len(matches) > 1,
            "matches": matches if len(matches) > 1 else None,
        }
    for conflict in root.findall("conflict"):
        asset_id = (conflict.get("id") or "").strip()
        preferences = DRESSUP_CONFLICT_SOURCE_PREFERENCES.get(asset_id)
        if not preferences:
            continue
        matches = [
            {
                "swf": source.get("swf") or "",
                "symbolName": source.get("symbolName") or "",
            }
            for source in conflict.findall("source")
        ]
        chosen = None
        for expected_swf, expected_symbol in preferences:
            for match in matches:
                if match["swf"] == expected_swf and match["symbolName"] == expected_symbol:
                    chosen = match
                    break
                if match["swf"] == expected_swf and not match["symbolName"] and expected_symbol:
                    chosen = {
                        "swf": expected_swf,
                        "symbolName": expected_symbol,
                    }
                    break
            if chosen:
                break
        if chosen:
            result[asset_id] = {
                "swf": chosen["swf"],
                "symbolName": chosen["symbolName"],
                "conflict": False,
                "resolvedConflict": True,
                "matches": matches,
            }
    return result


def parse_matrix(instance: ET.Element) -> Matrix:
    matrix_wrapper = first_child_named(instance, "matrix")
    matrix_node = first_child_named(matrix_wrapper, "Matrix") if matrix_wrapper is not None else None
    if matrix_node is None:
        return IDENTITY
    return Matrix(
        a=float(matrix_node.get("a", "1")),
        b=float(matrix_node.get("b", "0")),
        c=float(matrix_node.get("c", "0")),
        d=float(matrix_node.get("d", "1")),
        tx=float(matrix_node.get("tx", "0")),
        ty=float(matrix_node.get("ty", "0")),
    )


def parse_script(instance: ET.Element) -> str:
    action = first_child_named(instance, "Actionscript")
    if action is None:
        return ""
    script = first_child_named(action, "script")
    if script is None or script.text is None:
        return ""
    return script.text


def parse_symbol_file(path: Path) -> dict[str, Any]:
    root = xml_root(path)
    name = root.get("name") or path.stem
    linkage_identifier = root.get("linkageIdentifier") or ""
    frames: list[dict[str, Any]] = []
    labels: dict[int, str] = {}
    for frame in descendants_named(root, "DOMFrame"):
        index = int(frame.get("index", "0"))
        label = frame.get("name")
        if label:
            labels[index] = label
        instances = []
        elements = first_child_named(frame, "elements")
        if elements is not None:
            for instance in iter_children_named(elements, "DOMSymbolInstance"):
                script = parse_script(instance)
                instances.append(
                    {
                        "libraryItemName": instance.get("libraryItemName") or "",
                        "name": instance.get("name") or "",
                        "matrix": parse_matrix(instance),
                        "script": script,
                        "attachCalls": ATTACH_RE.findall(script),
                    }
                )
        frames.append({"index": index, "label": label or "", "instances": instances})
    return {
        "name": name,
        "path": str(path),
        "linkageIdentifier": linkage_identifier,
        "labels": labels,
        "frames": frames,
    }


def load_xfl_symbols(library_dir: Path) -> dict[str, dict[str, Any]]:
    symbols: dict[str, dict[str, Any]] = {}
    for path in sorted(library_dir.rglob("*.xml")):
        try:
            symbol = parse_symbol_file(path)
        except ET.ParseError:
            continue
        symbols[symbol["name"]] = symbol
    return symbols


def first_instance(symbol: dict[str, Any], library_name: str | None = None, instance_name: str | None = None) -> dict[str, Any] | None:
    for frame in symbol["frames"]:
        for instance in frame["instances"]:
            if library_name is not None and instance["libraryItemName"] != library_name:
                continue
            if instance_name is not None and instance["name"] != instance_name:
                continue
            return {"frame": frame["index"], **instance}
    return None


def basic_instance(symbols: dict[str, dict[str, Any]], symbol_name: str) -> dict[str, Any] | None:
    symbol = symbols.get(symbol_name)
    if symbol is None:
        return None
    instance = first_instance(symbol, instance_name="基本款")
    if instance is None:
        return None
    basic_symbol = symbols.get(instance["libraryItemName"])
    linkage_id = basic_symbol.get("linkageIdentifier") if basic_symbol else ""
    return {
        "libraryItemName": instance["libraryItemName"],
        "linkageId": linkage_id or "",
        "matrix": instance["matrix"].to_json(),
    }


def gender_man_instances(template: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    pending = []
    for frame in template["frames"]:
        label = frame["label"]
        for instance in frame["instances"]:
            if instance["name"] != "man":
                continue
            item = {"frame": frame["index"], **instance}
            if label in DEFAULT_GENDERS:
                result[label] = item
            else:
                pending.append(item)
    for gender, item in zip(DEFAULT_GENDERS, pending):
        result.setdefault(gender, item)
    return result


def record_holder(
    holders: list[dict[str, Any]],
    symbols: dict[str, dict[str, Any]],
    gender: str,
    symbol_name: str,
    instance: dict[str, Any],
    matrix: Matrix,
    path: list[str],
) -> None:
    script = instance["script"]
    for field, attach_name in instance["attachCalls"]:
        fallback_basic = "基本款._visible = 1" in script or "基本款._visible=1" in script
        basic = basic_instance(symbols, instance["libraryItemName"]) if fallback_basic else None
        holders.append(
            {
                "gender": gender,
                "field": field,
                "attachName": attach_name,
                "hostSymbol": symbol_name,
                "hostInstanceName": instance["name"],
                "targetLibraryItemName": instance["libraryItemName"],
                "matrix": matrix.to_json(),
                "fallbackBasic": fallback_basic,
                "hideBasicOnAttach": "基本款._visible = 0" in script or "基本款._visible=0" in script,
                "syncFrameToBasic": "gotoAndStop(this.基本款._currentframe)" in script,
                "basic": basic,
                "path": path + [symbol_name, instance["libraryItemName"]],
            }
        )


def traverse_holders(
    symbols: dict[str, dict[str, Any]],
    gender: str,
    symbol_name: str,
    parent_matrix: Matrix,
    holders: list[dict[str, Any]],
    path: list[str],
    visited: set[tuple[str, str]],
) -> None:
    visit_key = (gender, symbol_name)
    if visit_key in visited or len(path) > 32:
        return
    visited.add(visit_key)
    symbol = symbols.get(symbol_name)
    if symbol is None:
        return
    for frame in symbol["frames"]:
        # The dialogue pose uses static holder symbols. Use key frame 0 plus unlabeled frames;
        # labeled expression timelines are exported as nested assets later.
        if frame["index"] != 0 and frame["label"]:
            continue
        for instance in frame["instances"]:
            matrix = multiply(parent_matrix, instance["matrix"])
            if instance["attachCalls"]:
                record_holder(holders, symbols, gender, symbol_name, instance, matrix, path)
            child_name = instance["libraryItemName"]
            if child_name in symbols:
                traverse_holders(symbols, gender, child_name, matrix, holders, path + [symbol_name], visited)


def build_dialogue_rig(project_root: Path) -> dict[str, Any]:
    library_dir = project_root / "flashswf" / "UI" / "对话框界面" / "LIBRARY"
    symbols = load_xfl_symbols(library_dir)
    portrait = symbols.get("对话框肖像")
    template = symbols.get("对话框UI/对话-主角模板")
    if portrait is None or template is None:
        return {"error": "missing_dialogue_portrait_symbols"}

    portrait_instance = first_instance(portrait, library_name="对话框UI/对话-主角模板")
    man_instances = gender_man_instances(template)
    genders: dict[str, Any] = {}
    for gender, man in man_instances.items():
        base_matrix = man["matrix"]
        if portrait_instance is not None:
            base_matrix = multiply(portrait_instance["matrix"], base_matrix)
        holders: list[dict[str, Any]] = []
        traverse_holders(
            symbols,
            gender,
            man["libraryItemName"],
            base_matrix,
            holders,
            [],
            set(),
        )
        genders[gender] = {
            "frame": man["frame"],
            "manSymbol": man["libraryItemName"],
            "matrix": base_matrix.to_json(),
            "holders": holders,
        }

    return {
        "source": "flashswf/UI/对话框界面/对话框界面.xfl",
        "portraitSymbol": "对话框肖像",
        "templateSymbol": "对话框UI/对话-主角模板",
        "portraitTemplateMatrix": portrait_instance["matrix"].to_json() if portrait_instance else IDENTITY.to_json(),
        "genders": genders,
    }


def finalize_skin_keys(skin_keys: dict[str, dict[str, Any]], assets: dict[str, dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key in sorted(skin_keys):
        entry = skin_keys[key]
        asset = assets.get(key)
        result[key] = {
            "covered": asset is not None,
            "asset": asset,
            "uses": sorted(entry["uses"]),
            "items": sorted(entry["items"]),
            "sourceFiles": sorted(entry["sourceFiles"]),
        }
    return result


def build_manifest(project_root: Path, genders: tuple[str, ...]) -> tuple[dict[str, Any], dict[str, Any]]:
    items, skin_keys_raw = load_items(project_root, genders)
    assets = load_asset_map(project_root)
    skin_keys = finalize_skin_keys(skin_keys_raw, assets)
    missing = {key: value for key, value in skin_keys.items() if not value["covered"]}
    rig = build_dialogue_rig(project_root)
    manifest = {
        "schema": "cf7-dressup-manifest-v1",
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "genders": list(genders),
        "items": items,
        "skinKeys": skin_keys,
        "rig": rig,
    }
    report = {
        "schema": "cf7-dressup-report-v1",
        "counts": {
            "items": len(items),
            "skinKeys": len(skin_keys),
            "coveredSkinKeys": len(skin_keys) - len(missing),
            "missingSkinKeys": len(missing),
            "holdersMale": len(rig.get("genders", {}).get("男", {}).get("holders", [])),
            "holdersFemale": len(rig.get("genders", {}).get("女", {}).get("holders", [])),
        },
        "missingSummary": summarize_missing_skin_keys(missing),
        "missingSkinKeys": missing,
    }
    return manifest, report


def summarize_missing_skin_keys(missing: dict[str, Any]) -> dict[str, Any]:
    by_use: Counter[str] = Counter()
    by_prefix: Counter[str] = Counter()
    prefixes = ("男变装-", "女变装-", "刀-", "枪-长枪-", "枪-手枪-", "手雷-", "发型-")
    for key, entry in missing.items():
        uses = entry.get("uses") or ["<unknown>"]
        for use in uses:
            by_use[str(use)] += 1
        prefix = "<other>"
        for candidate in prefixes:
            if key.startswith(candidate):
                prefix = candidate
                break
        by_prefix[prefix] += 1
    return {
        "byUse": dict(sorted(by_use.items())),
        "byPrefix": dict(sorted(by_prefix.items())),
    }


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def safe_key(value: str) -> str:
    return f"{zlib.crc32(value.encode('utf-8')) & 0xFFFFFFFF:08x}"


def resolve_path(path_text: str, project_root: Path) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return project_root / path


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def validate_tmp_dir(tmp_dir: Path, project_root: Path) -> None:
    resolved_tmp = tmp_dir.resolve()
    allowed_parent = (project_root / "tmp").resolve()
    if not is_relative_to(resolved_tmp, allowed_parent):
        raise SystemExit(f"--tmp-dir must stay under {allowed_parent}")
    if resolved_tmp == allowed_parent or resolved_tmp == project_root.resolve():
        raise SystemExit("--tmp-dir must name a dedicated subdirectory under tmp/.")


def run_command(
    args: list[str],
    cwd: Path,
    timeout_seconds: int | None = None,
) -> subprocess.CompletedProcess[str]:
    timeout = timeout_seconds if timeout_seconds and timeout_seconds > 0 else None
    try:
        return subprocess.run(
            args,
            cwd=str(cwd),
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout if isinstance(exc.stdout, str) else ""
        return subprocess.CompletedProcess(args, 124, output + f"\n[timeout after {timeout_seconds}s]")


def remove_tree(path: Path, *, required: bool = True) -> None:
    if not path.exists():
        return
    target = long_path(path)
    last_error: OSError | None = None
    for _attempt in range(3):
        try:
            shutil.rmtree(target)
            return
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
    if required and last_error is not None:
        raise last_error
    shutil.rmtree(target, ignore_errors=True)


def long_path(path: Path) -> str:
    text = str(path.resolve())
    if os.name != "nt" or text.startswith("\\\\?\\"):
        return text
    if text.startswith("\\\\"):
        return "\\\\?\\UNC\\" + text[2:]
    return "\\\\?\\" + text


def load_symbol_class(
    ffdec: Path, project_root: Path, tmp_dir: Path, swf_rel: str, timeout_seconds: int | None = None
) -> tuple[dict[str, int], dict[str, Any] | None]:
    swf_path = project_root / swf_rel
    if not swf_path.exists():
        return {}, {"swf": swf_rel, "error": "missing_swf"}

    out_dir = tmp_dir / "symbols" / safe_key(swf_rel)
    if out_dir.exists():
        remove_tree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    result = run_command([str(ffdec), "-export", "symbolClass", str(out_dir), str(swf_path)], project_root, timeout_seconds)
    if result.returncode != 0:
        return {}, {
            "swf": swf_rel,
            "error": "symbolClass_failed",
            "exitCode": result.returncode,
            "outputTail": result.stdout[-2000:],
        }
    csv_path = out_dir / "symbols.csv"
    if not csv_path.exists():
        return {}, {"swf": swf_rel, "error": "symbols_csv_missing"}
    mapping: dict[str, int] = {}
    for raw in csv_path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw.strip()
        if not line or ";" not in line:
            continue
        char_id_text, linkage_id = line.split(";", 1)
        try:
            mapping[linkage_id] = int(char_id_text)
        except ValueError:
            continue
    return mapping, None


def raw_export_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "raw" / safe_key(swf_rel)


def raw_svg_export_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "raw-svg" / safe_key(swf_rel)


def raw_script_export_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "raw-script" / safe_key(swf_rel)


def raw_xml_export_path(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "raw-xml" / safe_key(swf_rel) / "swf.xml"


def raw_layer_base_xml_path(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "layer-base" / safe_key(swf_rel) / "swf.xml"


def raw_layer_base_swf_path(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "layer-base" / safe_key(swf_rel) / "base.swf"


def raw_layer_base_export_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "layer-base-png" / safe_key(swf_rel)


def raw_layer_base_svg_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "layer-base-svg" / safe_key(swf_rel)


def raw_nested_layer_export_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "nested-layer-png" / safe_key(swf_rel)


def raw_nested_layer_svg_dir(tmp_dir: Path, swf_rel: str) -> Path:
    return tmp_dir / "nested-layer-svg" / safe_key(swf_rel)


def export_sprites(
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    swf_rel: str,
    character_ids: list[int],
    zoom: int,
    timeout_seconds: int | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    return export_sprites_from_swf(
        ffdec,
        project_root,
        project_root / swf_rel,
        raw_export_dir(tmp_dir, swf_rel),
        swf_rel,
        character_ids,
        zoom,
        timeout_seconds,
    )


def export_sprites_from_swf(
    ffdec: Path,
    project_root: Path,
    swf_path: Path,
    out_dir: Path,
    swf_label: str,
    character_ids: list[int],
    zoom: int,
    timeout_seconds: int | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    if not character_ids:
        return None, None
    if out_dir.exists():
        remove_tree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    unique_ids = sorted(set(character_ids))
    select_id = ",".join(str(i) for i in unique_ids)
    result = run_command(
        [
            str(ffdec),
            "-zoom",
            str(zoom),
            "-format",
            "sprite:png",
            "-selectid",
            select_id,
            "-export",
            "sprite",
            str(out_dir),
            str(swf_path),
        ],
        project_root,
        timeout_seconds,
    )
    if result.returncode == 0:
        return None, None

    failed: list[dict[str, Any]] = []
    recovered = 0
    for character_id in unique_ids:
        retry = run_command(
            [
                str(ffdec),
                "-zoom",
                str(zoom),
                "-format",
                "sprite:png",
                "-selectid",
                str(character_id),
                "-export",
                "sprite",
                str(out_dir),
                str(swf_path),
            ],
            project_root,
            timeout_seconds,
        )
        if retry.returncode == 0:
            recovered += 1
        else:
            failed.append(
                {
                    "characterId": character_id,
                    "exitCode": retry.returncode,
                    "outputTail": retry.stdout[-1200:],
                }
            )

    fallback = {
        "swf": swf_label,
        "batchExitCode": result.returncode,
        "requested": len(unique_ids),
        "recovered": recovered,
        "failed": len(failed),
    }
    if failed:
        fallback["failedCharacterIds"] = [item["characterId"] for item in failed]
        fallback["failedSamples"] = failed[:5]
        return {
            "swf": swf_label,
            "error": "sprite_export_partial_failed",
            "batchExitCode": result.returncode,
            "requested": len(unique_ids),
            "recovered": recovered,
            "failed": len(failed),
            "failedCharacterIds": fallback["failedCharacterIds"],
            "outputTail": result.stdout[-2000:],
        }, fallback
    return None, fallback


def export_swf_xml(
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    swf_rel: str,
    timeout_seconds: int | None = None,
) -> tuple[Path | None, dict[str, Any] | None]:
    swf_path = project_root / swf_rel
    xml_path = raw_xml_export_path(tmp_dir, swf_rel)
    xml_path.parent.mkdir(parents=True, exist_ok=True)
    if xml_path.exists():
        xml_path.unlink()
    result = run_command([str(ffdec), "-swf2xml", str(swf_path), str(xml_path)], project_root, timeout_seconds)
    if result.returncode == 0 and xml_path.exists():
        return xml_path, None
    error = "swf_xml_timeout" if result.returncode == 124 else "swf_xml_export_failed"
    return None, {
        "swf": swf_rel,
        "error": error,
        "exitCode": result.returncode,
        "outputTail": result.stdout[-2000:],
    }


def xml2swf(
    ffdec: Path,
    project_root: Path,
    xml_path: Path,
    swf_path: Path,
    swf_rel: str,
    timeout_seconds: int | None = None,
) -> dict[str, Any] | None:
    swf_path.parent.mkdir(parents=True, exist_ok=True)
    if swf_path.exists():
        swf_path.unlink()
    result = run_command([str(ffdec), "-xml2swf", str(xml_path), str(swf_path)], project_root, timeout_seconds)
    if result.returncode == 0 and swf_path.exists():
        return None
    return {
        "swf": swf_rel,
        "error": "xml2swf_failed",
        "exitCode": result.returncode,
        "outputTail": result.stdout[-2000:],
    }


def export_scripts(
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    swf_rel: str,
    timeout_seconds: int | None = None,
) -> dict[str, Any] | None:
    swf_path = project_root / swf_rel
    out_dir = raw_script_export_dir(tmp_dir, swf_rel)
    if out_dir.exists():
        remove_tree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    result = run_command(
        [
            str(ffdec),
            "-format",
            "script:as",
            "-export",
            "script",
            str(out_dir),
            str(swf_path),
        ],
        project_root,
        timeout_seconds,
    )
    if result.returncode == 0:
        return None
    return {
        "swf": swf_rel,
        "error": "script_export_failed",
        "exitCode": result.returncode,
        "outputTail": result.stdout[-2000:],
    }


def export_sprite_svgs(
    ffdec: Path,
    project_root: Path,
    tmp_dir: Path,
    swf_rel: str,
    character_ids: list[int],
    zoom: int,
    timeout_seconds: int | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    return export_sprite_svgs_from_swf(
        ffdec,
        project_root,
        project_root / swf_rel,
        raw_svg_export_dir(tmp_dir, swf_rel),
        swf_rel,
        character_ids,
        zoom,
        timeout_seconds,
    )


def export_sprite_svgs_from_swf(
    ffdec: Path,
    project_root: Path,
    swf_path: Path,
    out_dir: Path,
    swf_label: str,
    character_ids: list[int],
    zoom: int,
    timeout_seconds: int | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    if not character_ids:
        return None, None
    if out_dir.exists():
        remove_tree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    unique_ids = sorted(set(character_ids))
    select_id = ",".join(str(i) for i in unique_ids)
    result = run_command(
        [
            str(ffdec),
            "-zoom",
            str(zoom),
            "-format",
            "sprite:svg",
            "-selectid",
            select_id,
            "-export",
            "sprite",
            str(out_dir),
            str(swf_path),
        ],
        project_root,
        timeout_seconds,
    )
    if result.returncode == 0:
        return None, None

    return {
        "swf": swf_label,
        "error": "sprite_svg_export_failed",
        "exitCode": result.returncode,
        "requested": len(unique_ids),
        "outputTail": result.stdout[-2000:],
    }, None


def is_safe_export_dir_name(directory_name: str, character_id: int) -> bool:
    prefix = f"DefineSprite_{character_id}"
    return directory_name == prefix or directory_name.startswith(prefix + "_")


def find_exported_frame_paths(tmp_dir: Path, swf_rel: str, character_id: int) -> list[Path]:
    return find_exported_frame_paths_in_dir(raw_export_dir(tmp_dir, swf_rel), character_id)


def find_exported_frame_paths_in_dir(base: Path, character_id: int) -> list[Path]:
    if not base.exists():
        return []
    for directory in base.iterdir():
        if directory.is_dir() and is_safe_export_dir_name(directory.name, character_id):
            frames = [p for p in directory.glob("*.png") if p.stem.isdigit()]
            return sorted(frames, key=lambda path: int(path.stem))
    return []


def find_exported_svg_paths(tmp_dir: Path, swf_rel: str, character_id: int) -> list[Path]:
    return find_exported_svg_paths_in_dir(raw_svg_export_dir(tmp_dir, swf_rel), character_id)


def find_exported_svg_paths_in_dir(base: Path, character_id: int) -> list[Path]:
    if not base.exists():
        return []
    for directory in base.iterdir():
        if directory.is_dir() and is_safe_export_dir_name(directory.name, character_id):
            frames = [p for p in directory.glob("*.svg") if p.stem.isdigit()]
            return sorted(frames, key=lambda path: int(path.stem))
    return []


def script_define_id(path_part: str) -> int | None:
    match = SCRIPT_DEFINE_DIR_RE.match(path_part)
    if not match:
        return None
    return int(match.group(1))


def script_frame_number(path_part: str) -> int | None:
    match = SCRIPT_FRAME_DIR_RE.match(path_part)
    if not match:
        return None
    return int(match.group(1))


def compact_action_script(script: str) -> str:
    without_block = BLOCK_COMMENT_RE.sub("", script)
    without_line = LINE_COMMENT_RE.sub("", without_block)
    return re.sub(r"\s+", "", without_line)


def is_plain_stop_script(script: str) -> bool:
    compact = compact_action_script(script)
    return compact in ("stop();", "stop()")


def collect_timeline_scripts(tmp_dir: Path, swf_rel: str) -> dict[int, dict[str, Any]]:
    base = raw_script_export_dir(tmp_dir, swf_rel) / "scripts"
    controls: dict[int, dict[str, Any]] = defaultdict(lambda: {"frameScripts": defaultdict(list), "clipActions": []})
    if not base.exists():
        return {}
    for path in base.rglob("*.as"):
        rel_parts = path.relative_to(base).parts
        char_id: int | None = None
        frame_number: int | None = None
        for part in rel_parts:
            if char_id is None:
                char_id = script_define_id(part)
            if frame_number is None:
                frame_number = script_frame_number(part)
        if char_id is None:
            continue
        try:
            script = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        is_clip_action = any("CLIPACTIONRECORD" in part or "onClipEvent" in part for part in rel_parts)
        if is_clip_action:
            controls[char_id]["clipActions"].append({"frame": frame_number, "path": path.name})
        else:
            controls[char_id]["frameScripts"][frame_number or 0].append(script)
    return controls


def parse_xml_matrix(element: ET.Element | None) -> Matrix:
    if element is None:
        return IDENTITY
    has_scale = element.get("hasScale") == "true"
    has_rotate = element.get("hasRotate") == "true"
    a = float(element.get("scaleX") or 1) if has_scale else 1.0
    d = float(element.get("scaleY") or 1) if has_scale else 1.0
    c = float(element.get("rotateSkew0") or 0) if has_rotate else 0.0
    b = float(element.get("rotateSkew1") or 0) if has_rotate else 0.0
    tx = float(element.get("translateX") or 0) / 20.0
    ty = float(element.get("translateY") or 0) / 20.0
    return Matrix(a=a, b=b, c=c, d=d, tx=tx, ty=ty)


def parse_sprite_graph(xml_path: Path) -> dict[int, dict[str, Any]]:
    root = ET.parse(xml_path).getroot()
    graph: dict[int, dict[str, Any]] = {}
    for item in root.iter("item"):
        if item.get("type") != "DefineSpriteTag":
            continue
        sprite_id_text = item.get("spriteId")
        if not sprite_id_text:
            continue
        sprite_id = int(sprite_id_text)
        children: list[int] = []
        children_by_frame: dict[int, list[int]] = defaultdict(list)
        child_instances: list[dict[str, Any]] = []
        frame = 1
        sub_tags = first_child_named(item, "subTags")
        if sub_tags is None:
            continue
        for child in list(sub_tags):
            child_type = child.get("type") or ""
            child_id = child.get("characterId")
            if child_type.startswith("PlaceObject") and child_id:
                character_id = int(child_id)
                children.append(character_id)
                children_by_frame[frame].append(character_id)
                instance: dict[str, int] = {"characterId": character_id, "frame": frame}
                depth = child.get("depth")
                if depth and depth.lstrip("-").isdigit():
                    instance["depth"] = int(depth)
                matrix_node = first_child_named(child, "matrix")
                instance["matrix"] = parse_xml_matrix(matrix_node)
                child_instances.append(instance)
            if child_type == "ShowFrameTag":
                frame += 1
        graph[sprite_id] = {
            "frameCount": int(item.get("frameCount") or 0),
            "children": list(dict.fromkeys(children)),
            "childrenByFrame": {
                str(frame_number): list(dict.fromkeys(frame_children))
                for frame_number, frame_children in children_by_frame.items()
            },
            "childInstances": child_instances,
        }
    return graph


def has_plain_frame1_stop(controls: dict[int, dict[str, Any]], character_id: int) -> bool:
    control = controls.get(character_id) or {}
    frame_scripts = control.get("frameScripts") or {}
    return any(is_plain_stop_script(script) for script in (frame_scripts.get(1) or []))


def animated_descendants(
    graph: dict[int, dict[str, Any]],
    controls: dict[int, dict[str, Any]],
    character_id: int,
    *,
    max_depth: int = 8,
) -> list[dict[str, Any]]:
    animated: list[dict[str, Any]] = []
    visited: set[tuple[int, bool]] = set()

    def child_ids_for(info: dict[str, Any], frame1_only: bool) -> list[int]:
        if frame1_only:
            return list((info.get("childrenByFrame") or {}).get("1") or [])
        return list(info.get("children") or [])

    def visit(sprite_id: int, depth: int, path: list[int], frame1_only: bool) -> None:
        visit_key = (sprite_id, frame1_only)
        if depth > max_depth or visit_key in visited:
            return
        visited.add(visit_key)
        info = graph.get(sprite_id)
        if not info:
            return
        for child_id in child_ids_for(info, frame1_only):
            child = graph.get(child_id)
            if not child:
                continue
            child_frames = int(child.get("frameCount") or 0)
            child_path = path + [child_id]
            child_stopped = has_plain_frame1_stop(controls, child_id)
            if child_frames > 1 and not child_stopped:
                animated.append(
                    {
                        "characterId": child_id,
                        "frameCount": child_frames,
                        "depth": depth + 1,
                        "path": child_path,
                    }
                )
            visit(child_id, depth + 1, child_path, child_stopped)

    visit(character_id, 0, [character_id], has_plain_frame1_stop(controls, character_id))
    animated.sort(key=lambda item: (item["depth"], -item["frameCount"], item["characterId"]))
    return animated


def first_frame_instance(
    graph: dict[int, dict[str, Any]],
    parent_id: int,
    child_id: int,
) -> dict[str, Any] | None:
    info = graph.get(parent_id) or {}
    for instance in info.get("childInstances") or []:
        if instance.get("frame") == 1 and instance.get("characterId") == child_id:
            return instance
    return None


def accumulated_frame1_matrix(
    graph: dict[int, dict[str, Any]],
    path: list[int],
) -> Matrix | None:
    matrix = IDENTITY
    for index in range(len(path) - 1):
        instance = first_frame_instance(graph, path[index], path[index + 1])
        if not instance:
            return None
        matrix = multiply(matrix, instance.get("matrix") or IDENTITY)
    return matrix


def direct_layer_draw_order(
    graph: dict[int, dict[str, Any]],
    parent_id: int,
    child_id: int,
) -> str:
    info = graph.get(parent_id) or {}
    target = first_frame_instance(graph, parent_id, child_id)
    if not target or "depth" not in target:
        return "over"
    target_depth = int(target["depth"])
    sibling_depths = [
        int(instance["depth"])
        for instance in (info.get("childInstances") or [])
        if instance.get("frame") == 1
        and instance.get("characterId") != child_id
        and "depth" in instance
    ]
    if sibling_depths and target_depth < min(sibling_depths):
        return "under"
    return "over"


def nested_layer_plans(
    graph: dict[int, dict[str, Any]],
    playback: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], set[tuple[int, int]], int, int]:
    nested = playback.get("nestedAnimation") or {}
    descendants = nested.get("autoPlayingDescendants") or []
    top_layers: list[dict[str, Any]] = []
    flat_layers: list[dict[str, Any]] = []
    unsupported = 0
    composited = 0
    removals: set[tuple[int, int]] = set()

    def is_prefix(prefix: list[int], value: list[int]) -> bool:
        return len(prefix) < len(value) and value[: len(prefix)] == prefix

    for descendant in sorted(descendants, key=lambda item: len(item.get("path") or [])):
        path = [int(part) for part in (descendant.get("path") or [])]
        if len(path) < 2:
            unsupported += 1
            continue
        child_id = path[-1]
        parent_layer: dict[str, Any] | None = None
        for candidate in flat_layers:
            candidate_path = candidate.get("path") or []
            if is_prefix(candidate_path, path):
                if parent_layer is None or len(candidate_path) > len(parent_layer.get("path") or []):
                    parent_layer = candidate
        relative_path = path
        if parent_layer is not None:
            parent_path = parent_layer.get("path") or []
            relative_path = [parent_path[-1]] + path[len(parent_path):]
        matrix = accumulated_frame1_matrix(graph, relative_path)
        if matrix is None:
            if parent_layer is not None and int(parent_layer.get("sourceFrameCount") or 1) > 1:
                parent_layer.setdefault("compositedDescendants", []).append(descendant)
                composited += 1
                continue
            unsupported += 1
            continue
        source_parent_id = path[-2]
        layer = {
            "characterId": child_id,
            "sourceParentId": source_parent_id,
            "sourceFrameCount": int(descendant.get("frameCount") or 1),
            "matrix": matrix.to_json(),
            "drawOrder": direct_layer_draw_order(graph, source_parent_id, child_id),
            "path": path,
            "layers": [],
        }
        if parent_layer is None:
            if len(path) > 2:
                layer["compositeNote"] = "flattened-static-chain"
            top_layers.append(layer)
        else:
            parent_layer.setdefault("layers", []).append(layer)
        flat_layers.append(layer)
        removals.add((source_parent_id, child_id))
    return top_layers, flat_layers, removals, unsupported, composited


def remove_direct_layer_children(
    xml_path: Path,
    out_xml_path: Path,
    removals: set[tuple[int, int]],
) -> int:
    tree = ET.parse(xml_path)
    root = tree.getroot()
    removed = 0
    for item in root.iter("item"):
        if item.get("type") != "DefineSpriteTag":
            continue
        sprite_id_text = item.get("spriteId")
        if not sprite_id_text:
            continue
        parent_id = int(sprite_id_text)
        sub_tags = first_child_named(item, "subTags")
        if sub_tags is None:
            continue
        frame = 1
        for child in list(sub_tags):
            child_type = child.get("type") or ""
            child_id = child.get("characterId")
            if (
                frame == 1
                and child_type.startswith("PlaceObject")
                and child_id
                and (parent_id, int(child_id)) in removals
            ):
                sub_tags.remove(child)
                removed += 1
                continue
            if child_type == "ShowFrameTag":
                frame += 1
    out_xml_path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(out_xml_path, encoding="utf-8", xml_declaration=True)
    return removed


def playback_metadata(
    controls: dict[int, dict[str, Any]],
    sprite_graph: dict[int, dict[str, Any]],
    character_id: int,
    source_frame_count: int,
    static_stop_policy: str,
) -> dict[str, Any]:
    control = controls.get(character_id) or {}
    frame_scripts = control.get("frameScripts") or {}
    frame_numbers = sorted(frame for frame in frame_scripts if frame)
    frame1_scripts = frame_scripts.get(1) or []
    has_frame1_stop = any(STOP_CALL_RE.search(script) for script in frame1_scripts)
    has_plain_frame1_stop = any(is_plain_stop_script(script) for script in frame1_scripts)
    metadata: dict[str, Any] = {
        "playback": "loop" if source_frame_count > 1 else "static",
        "sourceFrameCount": source_frame_count,
    }
    if frame_numbers:
        metadata["timelineScriptFrames"] = frame_numbers
    if control.get("clipActions"):
        metadata["hasClipActions"] = True
    if has_frame1_stop:
        metadata["hasFrame1Stop"] = True
    nested_animation = animated_descendants(sprite_graph, controls, character_id) if sprite_graph else []
    if nested_animation:
        metadata["nestedAnimation"] = {
            "autoPlayingDescendants": nested_animation,
            "descendantCount": len(nested_animation),
            "maxDescendantFrameCount": max(item["frameCount"] for item in nested_animation),
            "strategy": "layered-or-sampled-required",
        }
        if static_stop_policy == "auto" and source_frame_count > 1 and has_plain_frame1_stop:
            metadata["playback"] = "static-parent-nested-animation"
            metadata["staticReason"] = "frame1_plain_stop_with_nested_animation"
            metadata["collapsedFrameCount"] = source_frame_count - 1
        elif source_frame_count <= 1:
            metadata["playback"] = "nested-animation"
    if (
        static_stop_policy == "auto"
        and source_frame_count > 1
        and has_plain_frame1_stop
        and not nested_animation
    ):
        metadata["playback"] = "static-first-frame"
        metadata["staticReason"] = "frame1_plain_stop"
        metadata["collapsedFrameCount"] = source_frame_count - 1
    return metadata


def purge_unreferenced_frame_files(
    asset_dir: Path,
    file_prefix: str,
    referenced_file_names: set[str],
    no_write: bool,
) -> int:
    purged = 0
    if no_write or not asset_dir.exists():
        return purged
    prefix = f"{file_prefix}_"
    for path in asset_dir.glob(f"{file_prefix}_*.png"):
        suffix = path.stem.removeprefix(prefix)
        if not suffix.isdigit():
            continue
        if path.name in referenced_file_names:
            continue
        path.unlink()
        purged += 1
    return purged


def svg_frame_origins(svg_paths: list[Path]) -> dict[int, tuple[float, float]]:
    origins: dict[int, tuple[float, float]] = {}
    for path in svg_paths:
        try:
            frame_index = int(path.stem)
        except ValueError:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        match = SVG_MATRIX_RE.search(text)
        if match:
            origins[frame_index] = (float(match.group(1)), float(match.group(2)))
    return origins


def image_size(path: Path) -> tuple[int, int] | None:
    if Image is None:
        return None
    try:
        with Image.open(path) as image:
            return image.size
    except Exception:
        return None


def frame_pixel_digest(path: Path) -> str:
    if Image is not None:
        try:
            with Image.open(path) as image:
                rgba = image.convert("RGBA")
                digest = hashlib.sha256()
                digest.update(f"{rgba.width}x{rgba.height}:".encode("ascii"))
                digest.update(rgba.tobytes())
                return "rgba:" + digest.hexdigest()
        except Exception:
            pass
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return "file:" + digest.hexdigest()


def selected_skin_keys(manifest: dict[str, Any], names: set[str], limit: int) -> list[str]:
    keys: list[str] = []
    for key, entry in manifest["skinKeys"].items():
        if names and key not in names:
            continue
        if not entry.get("covered") or not entry.get("asset"):
            continue
        if entry["asset"].get("conflict"):
            continue
        keys.append(key)
        if limit > 0 and len(keys) >= limit:
            break
    return keys


def export_asset_identity(entry: dict[str, Any]) -> tuple[Any, ...]:
    asset = entry.get("asset") or {}
    return (
        bool(entry.get("covered")),
        asset.get("swf") or "",
        asset.get("symbolName") or "",
        bool(asset.get("conflict")),
    )


def preserve_incremental_skin_exports(
    manifest: dict[str, Any],
    existing_manifest: dict[str, Any],
    target_keys: set[str],
) -> int:
    preserved = 0
    existing_skin_keys = existing_manifest.get("skinKeys") or {}
    for key, entry in (manifest.get("skinKeys") or {}).items():
        if key in target_keys:
            continue
        existing_entry = existing_skin_keys.get(key)
        if not existing_entry or not existing_entry.get("export"):
            continue
        if export_asset_identity(entry) != export_asset_identity(existing_entry):
            continue
        for field in PRESERVED_EXPORT_KEYS:
            if field in existing_entry:
                entry[field] = copy.deepcopy(existing_entry[field])
        preserved += 1
    return preserved


def exported_frame_entries(
    frames: list[Path],
    asset_dir: Path,
    asset_dir_name: str,
    file_prefix: str,
    no_write: bool,
    origins: dict[int, tuple[float, float]] | None = None,
    dedupe_stats: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    frame_entries: list[dict[str, Any]] = []
    dedupe = FrameDedupeIndex()
    for index, source in enumerate(frames, start=1):
        digest = frame_pixel_digest(source)
        frame_ref = dedupe.resolve(digest, index, f"{file_prefix}_{index}.png")
        file_name = frame_ref.filename
        if not frame_ref.is_duplicate:
            destination = asset_dir / file_name
            if not no_write:
                shutil.copy2(source, destination)
            if dedupe_stats is not None:
                dedupe_stats["uniqueFrameImages"] += 1
        else:
            if dedupe_stats is not None:
                dedupe_stats["duplicateFrameRefs"] += 1
        size = image_size(source)
        frame_entry: dict[str, Any] = {
            "uri": f"{asset_dir_name}/{file_name}",
            "frame": index,
            "sourceFrame": index,
        }
        if frame_ref.duplicate_of_frame is not None:
            frame_entry["duplicateOfFrame"] = frame_ref.duplicate_of_frame
        if size:
            frame_entry["width"] = size[0]
            frame_entry["height"] = size[1]
        if origins and index in origins:
            origin_x, origin_y = origins[index]
            frame_entry["originX"] = round(origin_x, 6)
            frame_entry["originY"] = round(origin_y, 6)
        frame_entries.append(frame_entry)
    return frame_entries


def export_metadata(
    frame_entries: list[dict[str, Any]],
    zoom: int,
    fps: float,
    playback: dict[str, Any] | None = None,
    timeline_entries: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    first = frame_entries[0]
    metadata = {
        "format": "png-sequence" if len(frame_entries) > 1 else "png",
        "zoom": zoom,
        "fps": fps,
        "frameCount": len(frame_entries),
        "uri": first["uri"],
        "width": first.get("width"),
        "height": first.get("height"),
    }
    if playback:
        metadata.update(playback)
        metadata["frameCount"] = len(frame_entries)
        metadata["format"] = "png-sequence" if len(frame_entries) > 1 else "png"
    if timeline_entries is not None and len(timeline_entries) < len(frame_entries):
        metadata["logicalFrameCount"] = len(frame_entries)
        metadata["timelineFrameCount"] = len(timeline_entries)
        metadata["compressedFrameRefs"] = len(frame_entries) - len(timeline_entries)
    return metadata


def note_static_collapse(
    export_report: dict[str, Any],
    skin_key: str,
    character_id: int,
    playback: dict[str, Any],
) -> None:
    if not playback.get("staticReason") or int(playback.get("collapsedFrameCount") or 0) <= 0:
        return
    collapsed = int(playback.get("collapsedFrameCount") or 0)
    export_report["staticStopSkinKeys"] += 1
    export_report["staticStopCollapsedFrames"] += collapsed
    export_report["staticStopSamples"].append(
        {
            "skinKey": skin_key,
            "characterId": character_id,
            "sourceFrameCount": playback.get("sourceFrameCount"),
            "playback": playback.get("playback"),
            "reason": playback.get("staticReason"),
        }
    )


def note_nested_animation(
    export_report: dict[str, Any],
    skin_key: str,
    character_id: int,
    playback: dict[str, Any],
) -> None:
    nested = playback.get("nestedAnimation")
    if not nested:
        return
    export_report["nestedAnimationSkinKeys"] += 1
    export_report["nestedAnimationSamples"].append(
        {
            "skinKey": skin_key,
            "characterId": character_id,
            "playback": playback.get("playback"),
            "sourceFrameCount": playback.get("sourceFrameCount"),
            "descendantCount": nested.get("descendantCount"),
            "maxDescendantFrameCount": nested.get("maxDescendantFrameCount"),
            "sampleDescendants": nested.get("autoPlayingDescendants", [])[:5],
        }
    )


def parent_timeline_collapses(playback: dict[str, Any]) -> bool:
    return playback.get("playback") in ("static-first-frame", "static-parent-nested-animation")


def attach_direct_layer_exports(
    playback: dict[str, Any],
    layer_plans: list[dict[str, Any]],
    layer_frame_dir: Path,
    layer_svg_dir: Path,
    asset_dir: Path,
    asset_dir_name: str,
    file_prefix: str,
    no_write: bool,
    zoom: int,
    fps: float,
    export_report: dict[str, Any],
) -> None:
    if not layer_plans:
        return

    def export_layer(layer: dict[str, Any]) -> dict[str, Any] | None:
        character_id = int(layer["characterId"])
        frames = find_exported_frame_paths_in_dir(layer_frame_dir, character_id)
        if not frames:
            export_report["missingNestedLayerFrame"].append(
                {"characterId": character_id, "sourceParentId": layer.get("sourceParentId")}
            )
            return None
        origins = svg_frame_origins(find_exported_svg_paths_in_dir(layer_svg_dir, character_id))
        layer_prefix = f"{file_prefix}_layer{character_id}"
        frame_entries = exported_frame_entries(
            frames,
            asset_dir,
            asset_dir_name,
            layer_prefix,
            no_write,
            origins,
            export_report,
        )
        referenced_file_names = {Path(entry["uri"]).name for entry in frame_entries}
        export_report["purgedStaleFrames"] += purge_unreferenced_frame_files(
            asset_dir,
            layer_prefix,
            referenced_file_names,
            no_write,
        )
        timeline_entries = compressed_timeline_entries(
            frame_entries,
            export_report,
            owner=f"{file_prefix}#layer{character_id}",
            identity_keys=DRESSUP_TIMELINE_IDENTITY_KEYS,
        )
        layer_export = export_metadata(frame_entries, zoom, fps, timeline_entries=timeline_entries)
        child_exports: list[dict[str, Any]] = []
        for child in layer.get("layers") or []:
            child_export = export_layer(child)
            if child_export is not None:
                child_exports.append(child_export)
        if child_exports:
            layer_export["nestedAnimation"] = {
                "strategy": "direct-layered",
                "layers": child_exports,
            }
        exported = {
            "characterId": character_id,
            "sourceParentId": layer.get("sourceParentId"),
            "sourceFrameCount": layer.get("sourceFrameCount"),
            "matrix": layer.get("matrix"),
            "drawOrder": layer.get("drawOrder") or "over",
            "path": layer.get("path"),
            "export": layer_export,
            "frames": frame_entries,
        }
        if len(timeline_entries) < len(frame_entries):
            exported["timelineFrames"] = timeline_entries
        if layer.get("compositeNote"):
            exported["compositeNote"] = layer.get("compositeNote")
        if layer.get("compositedDescendants"):
            exported["compositedDescendants"] = layer.get("compositedDescendants")
        export_report["exportedNestedLayerKeys"] += 1
        export_report["exportedNestedLayerFrames"] += len(frame_entries)
        return exported

    exported_layers = [
        exported
        for exported in (export_layer(layer) for layer in layer_plans)
        if exported is not None
    ]
    if exported_layers:
        nested = playback.setdefault("nestedAnimation", {})
        nested["strategy"] = "direct-layered"
        nested["layers"] = exported_layers
        if len(exported_layers) < len(layer_plans):
            nested["missingLayerExports"] = len(layer_plans) - len(exported_layers)


def iter_basic_holders(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    holders: list[dict[str, Any]] = []
    for gender_data in (manifest.get("rig", {}).get("genders") or {}).values():
        for holder in gender_data.get("holders", []):
            basic = holder.get("basic")
            if holder.get("fallbackBasic") and basic and basic.get("linkageId"):
                holders.append(holder)
    return holders


def export_skin_assets(
    manifest: dict[str, Any],
    report: dict[str, Any],
    project_root: Path,
    output_dir: Path,
    asset_dir_name: str,
    tmp_dir: Path,
    ffdec: Path,
    zoom: int,
    names: set[str],
    limit: int,
    no_write: bool,
    fps: float,
    static_stop_policy: str,
    timeout_seconds: int,
) -> None:
    if not ffdec.exists():
        raise SystemExit(f"Missing FFDec CLI: {ffdec}")
    validate_tmp_dir(tmp_dir, project_root)
    if tmp_dir.exists():
        remove_tree(tmp_dir)
    tmp_dir.mkdir(parents=True, exist_ok=True)
    asset_dir = output_dir / asset_dir_name
    if not no_write:
        asset_dir.mkdir(parents=True, exist_ok=True)

    export_report: dict[str, Any] = {
        "selectedSkinKeys": 0,
        "resolvedSkinKeys": 0,
        "exportedSkinKeys": 0,
        "exportedFrames": 0,
        "resolvedBasicKeys": 0,
        "exportedBasicKeys": 0,
        "exportedBasicFrames": 0,
        "missingSymbol": [],
        "missingBasicSymbol": [],
        "symbolErrors": [],
        "exportErrors": [],
        "metadataErrors": [],
        "exportFallbacks": [],
        "missingFrame": [],
        "missingBasicFrame": [],
        "timelineScriptErrors": [],
        "spriteGraphErrors": [],
        "staticStopSkinKeys": 0,
        "staticStopCollapsedFrames": 0,
        "purgedStaleFrames": 0,
        "staticStopSamples": [],
        "nestedAnimationSkinKeys": 0,
        "nestedAnimationSamples": [],
        "nestedLayerUnsupportedDescendants": 0,
        "nestedLayerCompositedDescendants": 0,
        "exportedNestedLayerKeys": 0,
        "exportedNestedLayerFrames": 0,
        "missingNestedLayerFrame": [],
        "uniqueFrameImages": 0,
        "duplicateFrameRefs": 0,
        "timelineLogicalFrames": 0,
        "timelineFrameEntries": 0,
        "timelineCompressedFrameRefs": 0,
        "timelineCompressionSamples": [],
    }

    keys = selected_skin_keys(manifest, names, limit)
    export_report["selectedSkinKeys"] = len(keys)
    by_swf: dict[str, list[tuple[str, int]]] = defaultdict(list)

    symbol_maps: dict[str, dict[str, int]] = {}
    for key in keys:
        asset = manifest["skinKeys"][key]["asset"]
        swf_rel = asset.get("swf") or ""
        if not swf_rel:
            export_report["missingSymbol"].append({"skinKey": key, "reason": "missing_swf"})
            continue
        if swf_rel not in symbol_maps:
            symbol_map, error = load_symbol_class(
                ffdec,
                project_root,
                tmp_dir,
                swf_rel,
                timeout_seconds,
            )
            symbol_maps[swf_rel] = symbol_map
            if error:
                export_report["symbolErrors"].append(error)
        symbol_map = symbol_maps[swf_rel]
        char_id = symbol_map.get(key)
        if char_id is None and asset.get("symbolName"):
            char_id = symbol_map.get(asset["symbolName"])
        if char_id is None:
            export_report["missingSymbol"].append(
                {
                    "skinKey": key,
                    "swf": swf_rel,
                    "symbolName": asset.get("symbolName") or "",
                }
            )
            continue
        by_swf[swf_rel].append((key, char_id))
        export_report["resolvedSkinKeys"] += 1

    for swf_rel, targets in by_swf.items():
        error, fallback = export_sprites(
            ffdec,
            project_root,
            tmp_dir,
            swf_rel,
            [char_id for _, char_id in targets],
            zoom,
            timeout_seconds,
        )
        if fallback:
            export_report["exportFallbacks"].append(fallback)
        if error:
            export_report["exportErrors"].append(error)
        metadata_error, _metadata_fallback = export_sprite_svgs(
            ffdec,
            project_root,
            tmp_dir,
            swf_rel,
            [char_id for _, char_id in targets],
            zoom,
            timeout_seconds,
        )
        if metadata_error:
            export_report["metadataErrors"].append(metadata_error)

        timeline_controls: dict[int, dict[str, Any]] = {}
        sprite_graph: dict[int, dict[str, Any]] = {}
        if static_stop_policy != "off":
            script_error = export_scripts(ffdec, project_root, tmp_dir, swf_rel, timeout_seconds)
            if script_error:
                export_report["timelineScriptErrors"].append(script_error)
            else:
                timeline_controls = collect_timeline_scripts(tmp_dir, swf_rel)
            xml_path, graph_error = export_swf_xml(
                ffdec,
                project_root,
                tmp_dir,
                swf_rel,
                timeout_seconds,
            )
            if graph_error:
                export_report["spriteGraphErrors"].append(graph_error)
            elif xml_path:
                try:
                    sprite_graph = parse_sprite_graph(xml_path)
                except Exception as exc:
                    export_report["spriteGraphErrors"].append(
                        {
                            "swf": swf_rel,
                            "error": "swf_xml_parse_failed",
                            "message": str(exc),
                        }
                    )

        target_context: dict[str, dict[str, Any]] = {}
        layer_removals: set[tuple[int, int]] = set()
        layer_child_ids: set[int] = set()
        layer_parent_ids: set[int] = set()

        for key, char_id in targets:
            frames = find_exported_frame_paths(tmp_dir, swf_rel, char_id)
            if not frames:
                export_report["missingFrame"].append(
                    {"skinKey": key, "swf": swf_rel, "characterId": char_id}
                )
                continue
            playback = playback_metadata(timeline_controls, sprite_graph, char_id, len(frames), static_stop_policy)
            layer_plans, flat_layer_plans, removals, unsupported_layers, composited_layers = (
                nested_layer_plans(sprite_graph, playback) if sprite_graph else ([], [], set(), 0, 0)
            )
            export_report["nestedLayerUnsupportedDescendants"] += unsupported_layers
            export_report["nestedLayerCompositedDescendants"] += composited_layers
            if unsupported_layers and playback.get("nestedAnimation"):
                playback["nestedAnimation"]["unsupportedDescendantCount"] = unsupported_layers
            if composited_layers and playback.get("nestedAnimation"):
                playback["nestedAnimation"]["compositedDescendantCount"] = composited_layers
            if layer_plans and playback.get("nestedAnimation"):
                playback["nestedAnimation"]["directLayerCandidateCount"] = len(flat_layer_plans)
            layer_removals.update(removals)
            for layer in flat_layer_plans:
                layer_child_ids.add(int(layer["characterId"]))
            if layer_plans:
                layer_parent_ids.add(char_id)
            target_context[key] = {
                "characterId": char_id,
                "frames": frames,
                "playback": playback,
                "layerPlans": layer_plans,
            }

        base_frame_dir: Path | None = None
        base_svg_dir: Path | None = None
        layer_frame_dir: Path | None = None
        layer_svg_dir: Path | None = None
        if layer_removals and static_stop_policy != "off":
            xml_path = raw_xml_export_path(tmp_dir, swf_rel)
            if xml_path.exists():
                base_xml = raw_layer_base_xml_path(tmp_dir, swf_rel)
                base_swf = raw_layer_base_swf_path(tmp_dir, swf_rel)
                removed = remove_direct_layer_children(xml_path, base_xml, layer_removals)
                if removed:
                    layer_error = xml2swf(
                        ffdec,
                        project_root,
                        base_xml,
                        base_swf,
                        swf_rel,
                        timeout_seconds,
                    )
                    if layer_error:
                        export_report["exportErrors"].append(layer_error)
                    else:
                        base_frame_dir = raw_layer_base_export_dir(tmp_dir, swf_rel)
                        base_svg_dir = raw_layer_base_svg_dir(tmp_dir, swf_rel)
                        base_error, base_fallback = export_sprites_from_swf(
                            ffdec,
                            project_root,
                            base_swf,
                            base_frame_dir,
                            f"{swf_rel}#layer-base",
                            sorted(layer_parent_ids),
                            zoom,
                            timeout_seconds,
                        )
                        if base_fallback:
                            export_report["exportFallbacks"].append(base_fallback)
                        if base_error:
                            export_report["exportErrors"].append(base_error)
                            base_frame_dir = None
                        base_svg_error, _base_svg_fallback = export_sprite_svgs_from_swf(
                            ffdec,
                            project_root,
                            base_swf,
                            base_svg_dir,
                            f"{swf_rel}#layer-base",
                            sorted(layer_parent_ids),
                            zoom,
                            timeout_seconds,
                        )
                        if base_svg_error:
                            export_report["metadataErrors"].append(base_svg_error)
                            base_svg_dir = None
                layer_frame_dir = raw_nested_layer_export_dir(tmp_dir, swf_rel)
                layer_svg_dir = raw_nested_layer_svg_dir(tmp_dir, swf_rel)
                layer_error, layer_fallback = export_sprites_from_swf(
                    ffdec,
                    project_root,
                    project_root / swf_rel,
                    layer_frame_dir,
                    f"{swf_rel}#nested-layer",
                    sorted(layer_child_ids),
                    zoom,
                    timeout_seconds,
                )
                if layer_fallback:
                    export_report["exportFallbacks"].append(layer_fallback)
                if layer_error:
                    export_report["exportErrors"].append(layer_error)
                    layer_frame_dir = None
                layer_svg_error, _layer_svg_fallback = export_sprite_svgs_from_swf(
                    ffdec,
                    project_root,
                    project_root / swf_rel,
                    layer_svg_dir,
                    f"{swf_rel}#nested-layer",
                    sorted(layer_child_ids),
                    zoom,
                    timeout_seconds,
                )
                if layer_svg_error:
                    export_report["metadataErrors"].append(layer_svg_error)
                    layer_svg_dir = None

        for key, context in target_context.items():
            char_id = int(context["characterId"])
            playback = context["playback"]
            layer_plans = context["layerPlans"]
            frames = context["frames"]
            origins = svg_frame_origins(find_exported_svg_paths(tmp_dir, swf_rel, char_id))
            if layer_plans and base_frame_dir:
                base_frames = find_exported_frame_paths_in_dir(base_frame_dir, char_id)
                if base_frames:
                    frames = base_frames
                    origins = svg_frame_origins(find_exported_svg_paths_in_dir(base_svg_dir, char_id)) if base_svg_dir else origins
            frames_to_write = frames[:1] if parent_timeline_collapses(playback) else frames
            file_prefix = safe_key(key)
            frame_entries = exported_frame_entries(
                frames_to_write,
                asset_dir,
                asset_dir_name,
                file_prefix,
                no_write,
                origins,
                export_report,
            )
            if layer_plans and base_frame_dir and layer_frame_dir and layer_svg_dir:
                attach_direct_layer_exports(
                    playback,
                    layer_plans,
                    layer_frame_dir,
                    layer_svg_dir,
                    asset_dir,
                    asset_dir_name,
                    file_prefix,
                    no_write,
                    zoom,
                    fps,
                    export_report,
                )
            referenced_file_names = {Path(entry["uri"]).name for entry in frame_entries}
            export_report["purgedStaleFrames"] += purge_unreferenced_frame_files(
                asset_dir,
                file_prefix,
                referenced_file_names,
                no_write,
            )
            note_static_collapse(export_report, key, char_id, playback)
            note_nested_animation(export_report, key, char_id, playback)
            timeline_entries = compressed_timeline_entries(
                frame_entries,
                export_report,
                owner=key,
                identity_keys=DRESSUP_TIMELINE_IDENTITY_KEYS,
            )
            skin_entry = manifest["skinKeys"][key]
            skin_entry["export"] = export_metadata(frame_entries, zoom, fps, playback, timeline_entries)
            skin_entry["frames"] = frame_entries
            if len(timeline_entries) < len(frame_entries):
                skin_entry["timelineFrames"] = timeline_entries
            else:
                skin_entry.pop("timelineFrames", None)
            export_report["exportedSkinKeys"] += 1
            export_report["exportedFrames"] += len(frame_entries)

    export_basic_assets(
        manifest,
        export_report,
        project_root,
        asset_dir,
        asset_dir_name,
        tmp_dir,
        ffdec,
        zoom,
        no_write,
        fps,
        symbol_maps,
        timeout_seconds,
    )

    for list_key in (
        "missingSymbol",
        "missingBasicSymbol",
        "symbolErrors",
        "exportErrors",
        "metadataErrors",
        "exportFallbacks",
        "missingFrame",
        "missingBasicFrame",
        "timelineScriptErrors",
        "spriteGraphErrors",
        "staticStopSamples",
        "nestedAnimationSamples",
        "missingNestedLayerFrame",
        "timelineCompressionSamples",
    ):
        export_report[list_key] = export_report[list_key][:200]
    report["assetExport"] = export_report
    report["counts"]["exportedSkinKeys"] = export_report["exportedSkinKeys"]
    report["counts"]["exportedFrames"] = export_report["exportedFrames"]
    report["counts"]["exportedBasicKeys"] = export_report["exportedBasicKeys"]
    report["counts"]["exportedBasicFrames"] = export_report["exportedBasicFrames"]
    report["counts"]["metadataErrors"] = len(export_report["metadataErrors"])
    report["counts"]["timelineScriptErrors"] = len(export_report["timelineScriptErrors"])
    report["counts"]["spriteGraphErrors"] = len(export_report["spriteGraphErrors"])
    report["counts"]["staticStopSkinKeys"] = export_report["staticStopSkinKeys"]
    report["counts"]["staticStopCollapsedFrames"] = export_report["staticStopCollapsedFrames"]
    report["counts"]["purgedStaleFrames"] = export_report["purgedStaleFrames"]
    report["counts"]["nestedAnimationSkinKeys"] = export_report["nestedAnimationSkinKeys"]
    report["counts"]["nestedLayerUnsupportedDescendants"] = export_report["nestedLayerUnsupportedDescendants"]
    report["counts"]["nestedLayerCompositedDescendants"] = export_report["nestedLayerCompositedDescendants"]
    report["counts"]["exportedNestedLayerKeys"] = export_report["exportedNestedLayerKeys"]
    report["counts"]["exportedNestedLayerFrames"] = export_report["exportedNestedLayerFrames"]
    report["counts"]["uniqueFrameImages"] = export_report["uniqueFrameImages"]
    report["counts"]["duplicateFrameRefs"] = export_report["duplicateFrameRefs"]
    report["counts"]["timelineLogicalFrames"] = export_report["timelineLogicalFrames"]
    report["counts"]["timelineFrameEntries"] = export_report["timelineFrameEntries"]
    report["counts"]["timelineCompressedFrameRefs"] = export_report["timelineCompressedFrameRefs"]
    attach_animation_summary(manifest, report)


def export_basic_assets(
    manifest: dict[str, Any],
    export_report: dict[str, Any],
    project_root: Path,
    asset_dir: Path,
    asset_dir_name: str,
    tmp_dir: Path,
    ffdec: Path,
    zoom: int,
    no_write: bool,
    fps: float,
    symbol_maps: dict[str, dict[str, int]],
    timeout_seconds: int | None = None,
) -> None:
    dialogue_swf = "flashswf/UI/对话框界面.swf"
    holders = iter_basic_holders(manifest)
    by_linkage: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for holder in holders:
        linkage_id = holder["basic"].get("linkageId")
        if linkage_id:
            by_linkage[linkage_id].append(holder)
    if not by_linkage:
        return

    if dialogue_swf not in symbol_maps:
        symbol_map, error = load_symbol_class(ffdec, project_root, tmp_dir, dialogue_swf, timeout_seconds)
        symbol_maps[dialogue_swf] = symbol_map
        if error:
            export_report["symbolErrors"].append(error)
    symbol_map = symbol_maps[dialogue_swf]

    targets: list[tuple[str, int]] = []
    for linkage_id in sorted(by_linkage):
        char_id = symbol_map.get(linkage_id)
        if char_id is None:
            export_report["missingBasicSymbol"].append({"linkageId": linkage_id, "swf": dialogue_swf})
            continue
        targets.append((linkage_id, char_id))
        export_report["resolvedBasicKeys"] += 1
    if not targets:
        return

    error, fallback = export_sprites(
        ffdec,
        project_root,
        tmp_dir,
        dialogue_swf,
        [char_id for _, char_id in targets],
        zoom,
        timeout_seconds,
    )
    if fallback:
        export_report["exportFallbacks"].append(fallback)
    if error:
        export_report["exportErrors"].append(error)
    metadata_error, _metadata_fallback = export_sprite_svgs(
        ffdec,
        project_root,
        tmp_dir,
        dialogue_swf,
        [char_id for _, char_id in targets],
        zoom,
        timeout_seconds,
    )
    if metadata_error:
        export_report["metadataErrors"].append(metadata_error)

    for linkage_id, char_id in targets:
        frames = find_exported_frame_paths(tmp_dir, dialogue_swf, char_id)
        if not frames:
            export_report["missingBasicFrame"].append(
                {"linkageId": linkage_id, "swf": dialogue_swf, "characterId": char_id}
            )
            continue
        origins = svg_frame_origins(find_exported_svg_paths(tmp_dir, dialogue_swf, char_id))
        frame_entries = exported_frame_entries(
            frames,
            asset_dir,
            asset_dir_name,
            f"basic_{safe_key(linkage_id)}",
            no_write,
            origins,
            export_report,
        )
        referenced_file_names = {Path(entry["uri"]).name for entry in frame_entries}
        export_report["purgedStaleFrames"] += purge_unreferenced_frame_files(
            asset_dir,
            f"basic_{safe_key(linkage_id)}",
            referenced_file_names,
            no_write,
        )
        timeline_entries = compressed_timeline_entries(
            frame_entries,
            export_report,
            owner=f"basic:{linkage_id}",
            identity_keys=DRESSUP_TIMELINE_IDENTITY_KEYS,
        )
        metadata = export_metadata(frame_entries, zoom, fps, timeline_entries=timeline_entries)
        for holder in by_linkage[linkage_id]:
            holder["basic"]["export"] = metadata
            holder["basic"]["frames"] = frame_entries
            if len(timeline_entries) < len(frame_entries):
                holder["basic"]["timelineFrames"] = timeline_entries
            else:
                holder["basic"].pop("timelineFrames", None)
        export_report["exportedBasicKeys"] += 1
        export_report["exportedBasicFrames"] += len(frame_entries)


def attach_animation_summary(manifest: dict[str, Any], report: dict[str, Any]) -> None:
    animated: list[dict[str, Any]] = []
    static_collapsed: list[dict[str, Any]] = []
    nested_animation: list[dict[str, Any]] = []
    for key, entry in manifest["skinKeys"].items():
        export = entry.get("export") or {}
        frame_count = int(export.get("frameCount") or 0)
        nested = export.get("nestedAnimation")
        if nested:
            layers = nested.get("layers") or []
            nested_animation.append(
                {
                    "skinKey": key,
                    "playback": export.get("playback"),
                    "frameCount": frame_count,
                    "sourceFrameCount": export.get("sourceFrameCount"),
                    "descendantCount": nested.get("descendantCount"),
                    "maxDescendantFrameCount": nested.get("maxDescendantFrameCount"),
                    "layerCount": len(layers),
                    "strategy": nested.get("strategy"),
                    "unsupportedDescendantCount": nested.get("unsupportedDescendantCount", 0),
                    "compositedDescendantCount": nested.get("compositedDescendantCount", 0),
                    "uses": entry.get("uses", []),
                    "uri": export.get("uri"),
                }
            )
        if frame_count > 1:
            animated.append(
                {
                    "skinKey": key,
                    "frameCount": frame_count,
                    "playback": export.get("playback"),
                    "uses": entry.get("uses", []),
                    "uri": export.get("uri"),
                }
            )
        elif int(export.get("sourceFrameCount") or 0) > 1:
            static_collapsed.append(
                {
                    "skinKey": key,
                    "sourceFrameCount": export.get("sourceFrameCount"),
                    "playback": export.get("playback"),
                    "staticReason": export.get("staticReason"),
                    "nestedAnimation": bool(nested),
                    "uses": entry.get("uses", []),
                    "uri": export.get("uri"),
                }
            )
    animated.sort(key=lambda item: (-item["frameCount"], item["skinKey"]))
    static_collapsed.sort(key=lambda item: (-int(item["sourceFrameCount"] or 0), item["skinKey"]))
    nested_animation.sort(
        key=lambda item: (-int(item["maxDescendantFrameCount"] or 0), item["skinKey"])
    )
    report["counts"]["animatedSkinKeys"] = len(animated)
    report["counts"]["staticCollapsedSkinKeys"] = len(static_collapsed)
    report["counts"]["nestedAnimationSkinKeys"] = len(nested_animation)
    report["animatedSkinKeys"] = animated[:200]
    report["staticCollapsedSkinKeys"] = static_collapsed[:200]
    report["nestedAnimationSkinKeys"] = nested_animation[:200]


def main() -> int:
    args = parse_args()
    project_root = Path(__file__).resolve().parents[1]
    output_dir = resolve_path(args.output_dir, project_root)
    genders = genders_from_arg(args.genders)
    manifest, report = build_manifest(project_root, genders)
    tmp_dir = resolve_path(args.tmp_dir, project_root)
    preserved_skin_exports = 0
    if args.export_assets:
        if (args.name or args.limit > 0) and not args.no_write:
            existing_manifest_path = output_dir / "manifest.json"
            if existing_manifest_path.exists():
                existing_manifest = json.loads(existing_manifest_path.read_text(encoding="utf-8-sig"))
                target_keys = set(selected_skin_keys(manifest, set(args.name), args.limit))
                preserved_skin_exports = preserve_incremental_skin_exports(
                    manifest,
                    existing_manifest,
                    target_keys,
                )
        export_skin_assets(
            manifest,
            report,
            project_root,
            output_dir,
            args.asset_dir,
            tmp_dir,
            resolve_path(args.ffdec, project_root),
            args.zoom,
            set(args.name),
            args.limit,
            args.no_write,
            args.fps,
            args.static_stop_policy,
            args.ffdec_timeout_seconds,
        )
        if preserved_skin_exports:
            report.setdefault("assetExport", {})["preservedSkinKeyExports"] = preserved_skin_exports
            report.setdefault("counts", {})["preservedSkinKeyExports"] = preserved_skin_exports
    if not args.no_write:
        write_json(output_dir / "manifest.json", manifest)
        write_json(output_dir / "report.json", report)
    if args.export_assets and not args.keep_tmp and tmp_dir.exists():
        remove_tree(tmp_dir, required=False)
    print(json.dumps(report["counts"], ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
