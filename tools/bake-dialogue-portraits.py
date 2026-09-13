#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import html
import io
import json
import re
import shutil
import struct
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from PIL import Image
from dialogue_portrait_variants import plans_for, render_variant_frames

SCHEMA = "cf7-dialogue-portraits-v2"
AUTHORITY_POLICY_SCHEMA = "cf7.dialogue-portrait-source-authority-policy.v1"
INTERNAL_PORTRAIT_EXPORT_NAME = "对话框肖像"
DEFAULT_EXPRESSION = "普通"
HERO_KEYS = {"$PC_CHAR", "玩家", "主角模板"}
SKIP_INTERNAL_KEYS = {"玩家", "主角模板"}
SOURCE_IDS = {"external-swf", "dialogue-ui-sprite"}
IMAGE_SUFFIXES = (".png", ".webp")

# FFDec -swf2xml 把 DefineSpriteTag 的子时间轴包在 <subTags> 里；根时间轴只认
# <tags> 的直接子项，任何 <subTags> 内的 ShowFrame/FrameLabel 只计入该 sprite 自己
# 的帧计数。逐项匹配 open/close 才能区分层级（item 可嵌套，sprite 可再含 sprite）。
SWF_XML_TOKEN_RE = re.compile(
    r'<item\s+type="(?P<itype>[^"]+)"(?P<iattrs>[^>]*?)(?P<iclosed>/?)>'
    r'|</item\s*>'
    r'|<subTags\s*[^>]*>'
    r'|</subTags\s*>'
)
SWF_ITEM_NAME_RE = re.compile(r'\sname="([^"]*)"')
SWF_SPRITE_ID_RE = re.compile(r'\sspriteId="(\d+)"')


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    parser = argparse.ArgumentParser(description="Bake Flash dialogue portraits into Web PNG assets.")
    parser.add_argument("--project-root", default=str(project_root))
    parser.add_argument("--ffdec", default=str(project_root / "tools" / "ffdec" / "ffdec-cli.exe"))
    parser.add_argument("--output-dir", default=str(project_root / "launcher" / "web" / "assets" / "dialogue-portraits"))
    parser.add_argument("--tmp-dir", default=str(project_root / "tmp" / "dialogue-portrait-bake"))
    parser.add_argument(
        "--authority-policy",
        default=str(project_root / "tools" / "dialogue-portrait-source-review" / "authority-policy.json"),
    )
    parser.add_argument(
        "--semantic-baseline-dir",
        default="",
        help=(
            "Existing dialogue portrait output used to suppress internal PNG changes that only alter "
            "fully transparent canvas pixels. Defaults to the pre-bake output directory."
        ),
    )
    parser.add_argument(
        "--review-candidate-dir",
        default=str(project_root / "tmp" / "dialogue-portrait-source-review" / "candidates"),
        help="Ignored cache for rejected-source PNGs used by the human authority review page.",
    )
    parser.add_argument("--zoom", type=int, default=1)
    parser.add_argument("--internal-renderer", choices=["auto", "ffdec", "svg"], default="auto",
                        help="auto preserves legacy 1x PNG exports; HD/WebP uses same-source SVG rasterization.")
    parser.add_argument(
        "--image-format",
        choices=["png", "webp"],
        default="png",
        help=(
            "Final asset encoding. Intermediate FFDec frames and supersample downscaling always stay "
            "PNG; only the manifest-referenced output is encoded. webp is written lossless+exact "
            "(fully transparent pixels keep their RGB), URI extension follows the format."
        ),
    )
    parser.add_argument(
        "--supersample",
        type=int,
        default=3,
        help=(
            "Render-time supersampling (SSAA) factor. FFDec renders at zoom*supersample and every frame is "
            "then downscaled back by 1/supersample with LANCZOS, so the output geometry is byte-identical in "
            "size to running with --zoom alone. FFDec has no -smooth switch: supersampling is the only way to "
            "recover the detail it throws away when crushing a large embedded bitmap down onto a small stage "
            "placement (e.g. The Girl ships a 1672x1980 bitmap displayed at 320x369). 1 disables it."
        ),
    )
    parser.add_argument("--limit", type=int, default=0, help="Only export the first N external portraits; internal still exports.")
    parser.add_argument(
        "--keys",
        default="",
        help=(
            "Comma-separated portrait keys to bake (external list.xml names or SWF stems, and internal "
            "label keys). Bounded subset for trial exports; requires a non-production --output-dir. "
            "Empty bakes everything."
        ),
    )
    parser.add_argument(
        "--expressions",
        default="",
        help=(
            "Comma-separated expression/frame-label names to export per selected key. "
            f"{DEFAULT_EXPRESSION} is always kept because manifest defaultExpression requires it. "
            "Requires a non-production --output-dir. Empty exports all labels."
        ),
    )
    parser.add_argument("--external-only", action="store_true")
    parser.add_argument("--internal-only", action="store_true")
    parser.add_argument("--keep-tmp", action="store_true")
    parser.add_argument("--ffdec-timeout-seconds", type=int, default=180)
    return parser.parse_args()


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def first_child(parent: ET.Element, name: str) -> ET.Element | None:
    for child in list(parent):
        if local_name(child.tag) == name:
            return child
    return None


def iter_desc(parent: ET.Element, name: str):
    for elem in parent.iter():
        if local_name(elem.tag) == name:
            yield elem


def short_hash(value: str, length: int = 12) -> str:
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:length]


def stable_dir(kind: str, key: str) -> str:
    return f"{kind}_{short_hash(key)}"


def stable_file(expression: str, image_format: str = "png") -> str:
    return f"e_{short_hash(expression)}.{image_format}"


def normalize_key(value: Any) -> str:
    return str(value or "").strip()


def alias_candidates(key: str) -> list[str]:
    aliases = []
    values = [
        key,
        key.strip(),
        key.lower(),
        key.upper(),
        key.replace(" ", ""),
        key.replace(" ", "").lower(),
    ]
    for value in values:
        if value and value not in aliases:
            aliases.append(value)
    case_aliases = {
        "boy": "Boy",
        "Boy": "boy",
        "king": "King",
        "King": "king",
        "pig": "Pig",
        "Pig": "pig",
        "shopgirl": "Shop Girl",
        "ShopGirl": "Shop Girl",
        "TheGirl": "The Girl",
    }
    for value in list(aliases):
        alias = case_aliases.get(value)
        if alias and alias not in aliases:
            aliases.append(alias)
    return aliases


def run_command(args: list[str], cwd: Path, timeout_seconds: int) -> subprocess.CompletedProcess[str]:
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
    if result.returncode != 0:
        tail = result.stdout[-1600:] if result.stdout else ""
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(args)}\n{tail}")
    return result


def raster_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as fh:
        header = fh.read(24)
    if len(header) >= 24 and header[:8] == b"\x89PNG\r\n\x1a\n":
        width, height = struct.unpack(">II", header[16:24])
        return int(width), int(height)
    if len(header) >= 12 and header[:4] == b"RIFF" and header[8:12] == b"WEBP":
        with Image.open(path) as img:
            return int(img.width), int(img.height)
    return 0, 0


def raster_alpha_bounds(path: Path) -> dict[str, int] | None:
    with Image.open(path) as img:
        alpha = img.convert("RGBA").getchannel("A")
        bbox = alpha.getbbox()
    if not bbox:
        return None
    left, top, right, bottom = bbox
    return {
        "x": int(left),
        "y": int(top),
        "width": int(right - left),
        "height": int(bottom - top),
    }


def normalized_visible_rgba(image: Image.Image, bbox: tuple[int, int, int, int]) -> bytes:
    crop = image.convert("RGBA").crop(bbox)
    pixels = bytearray(crop.tobytes())
    for offset in range(0, len(pixels), 4):
        if pixels[offset + 3] == 0:
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
    return bytes(pixels)


def internal_assets_are_alpha_equivalent(candidate_path: Path, baseline_data: bytes) -> bool:
    with Image.open(candidate_path) as candidate_image, Image.open(io.BytesIO(baseline_data)) as baseline_image:
        candidate = candidate_image.convert("RGBA")
        baseline = baseline_image.convert("RGBA")
        candidate_bbox = candidate.getchannel("A").getbbox()
        baseline_bbox = baseline.getchannel("A").getbbox()
        if candidate_bbox is None or baseline_bbox is None or candidate_bbox != baseline_bbox:
            return False
        return normalized_visible_rgba(candidate, candidate_bbox) == normalized_visible_rgba(baseline, baseline_bbox)


def load_semantic_baseline(baseline_dir: Path) -> dict[str, dict[str, Any]]:
    manifest_path = baseline_dir / "manifest.json"
    if not manifest_path.is_file():
        return {}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema") != SCHEMA:
        raise RuntimeError(f"Unsupported dialogue portrait semantic baseline schema: {manifest.get('schema')}")
    baseline_root = baseline_dir.resolve()
    result: dict[str, dict[str, Any]] = {}
    for entry in manifest.get("entries", {}).values():
        if normalize_key(entry.get("source")) != "dialogue-ui-sprite":
            continue
        for asset in (entry.get("expressions") or {}).values():
            uri = normalize_key(asset.get("uri"))
            if not uri or uri in result:
                raise RuntimeError(f"Invalid or duplicate semantic baseline asset URI: {uri!r}")
            source_path = (baseline_root / Path(uri)).resolve()
            if baseline_root not in source_path.parents or not source_path.is_file():
                raise RuntimeError(f"Semantic baseline asset is missing or escapes its root: {uri}")
            baseline_data = source_path.read_bytes()
            width, height = raster_size(source_path)
            bounds = raster_alpha_bounds(source_path)
            if width != asset.get("width") or height != asset.get("height") or bounds != asset.get("bounds"):
                raise RuntimeError(f"Semantic baseline metadata drift: {uri}")
            result[uri] = {"asset": dict(asset), "raster": baseline_data}
    return result


def read_external_names(list_xml: Path) -> list[str]:
    root = ET.parse(list_xml).getroot()
    names = []
    for node in root.findall(".//portrait"):
        name = normalize_key(node.text)
        if name:
            names.append(name)
    return names


def swf_lookup(portrait_dir: Path) -> dict[str, Path]:
    lookup: dict[str, Path] = {}
    for swf in portrait_dir.glob("*.swf"):
        lookup[swf.stem] = swf
        lookup[swf.stem.lower()] = swf
    return lookup


def parse_selection_csv(raw: str) -> set[str] | None:
    values = {normalize_key(part) for part in (raw or "").split(",")}
    values.discard("")
    return values or None


def ensure_subset_output_dir(
    output_dir: Path,
    production_output_dir: Path,
    selection_active: bool,
) -> None:
    """子集烘焙禁止落在生产资产目录：资产闭包会删除未引用的 PNG/WebP。"""
    if selection_active and output_dir == production_output_dir:
        raise SystemExit(
            "--keys/--expressions subset bakes must use an explicit non-production --output-dir: "
            "the asset closure deletes every unreferenced PNG/WebP in the output directory"
        )


def ensure_review_candidate_dir(review_candidate_dir: Path, project_root: Path) -> None:
    """人审落选来源的候选缓存只允许留在项目 tmp/ 下。"""
    allowed_review_root = (project_root / "tmp").resolve()
    if allowed_review_root not in review_candidate_dir.parents:
        raise RuntimeError(f"Review candidate directory must stay under tmp/: {review_candidate_dir}")


def external_name_selected(name: str, lookup: dict[str, Path], selected_keys: set[str]) -> bool:
    if normalize_key(name) in selected_keys:
        return True
    swf = lookup.get(name) or lookup.get(name.lower())
    return swf is not None and normalize_key(swf.stem) in selected_keys


def filter_expression_frames(
    frames: dict[str, int],
    selected_expressions: set[str] | None,
) -> dict[str, int]:
    if selected_expressions is None:
        return frames
    return {
        expression: frame_no
        for expression, frame_no in frames.items()
        if expression in selected_expressions or expression == DEFAULT_EXPRESSION
    }


def export_swf_xml(ffdec: Path, project_root: Path, swf: Path, xml_path: Path, timeout_seconds: int) -> None:
    xml_path.parent.mkdir(parents=True, exist_ok=True)
    run_command([str(ffdec), "-swf2xml", str(swf), str(xml_path)], project_root, timeout_seconds)


def swf_xml_timelines(xml_path: Path) -> dict[str, Any]:
    """按时间轴分层收集 FFDec swf2xml 导出的帧标签。

    返回 {"root": {标签: 根帧号}, "sprites": {spriteId: {标签: sprite 内帧号}},
    "rootFrames": 根 ShowFrame 数}。旧实现逐行累计全文 ShowFrameTag，DefineSpriteTag
    <subTags> 内的嵌套帧会抬高其后的根标签帧号（如 Andy Law「侦查2」实际根帧 38 被
    记为 47），嵌套 sprite 的标签也会混进根标签表（如「室友」的 男/女 实际位于
    sprite 6 内）。这里用 <subTags> 开闭维护时间轴栈：栈外只统计根帧，栈内每层
    sprite 独立计数；标签取首次出现，与既有根标签去重语义一致。
    """
    root_labels: dict[str, int] = {}
    sprites: dict[str, dict[str, int]] = {}
    item_stack: list[tuple[str, str | None]] = []
    timeline_stack: list[dict[str, Any]] = []
    frame = 1
    with xml_path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            for match in SWF_XML_TOKEN_RE.finditer(line):
                token = match.group(0)
                if token.startswith("</item"):
                    if item_stack:
                        item_stack.pop()
                    continue
                if token.startswith("</subTags"):
                    if timeline_stack:
                        closed = timeline_stack.pop()
                        if closed["id"] is not None and closed["labels"]:
                            sprites.setdefault(closed["id"], {}).update(closed["labels"])
                    continue
                if token.startswith("<subTags"):
                    sprite_id = next(
                        (sid for itype, sid in reversed(item_stack) if itype == "DefineSpriteTag"),
                        None,
                    )
                    timeline_stack.append({"id": sprite_id, "frame": 1, "labels": {}})
                    continue
                item_type = match.group("itype")
                if item_type == "ShowFrameTag":
                    if timeline_stack:
                        timeline_stack[-1]["frame"] += 1
                    else:
                        frame += 1
                elif item_type == "FrameLabelTag":
                    name_match = SWF_ITEM_NAME_RE.search(token)
                    label = normalize_key(html.unescape(name_match.group(1))) if name_match else ""
                    if label:
                        if timeline_stack:
                            ctx = timeline_stack[-1]
                            ctx["labels"].setdefault(label, ctx["frame"])
                        else:
                            root_labels.setdefault(label, frame)
                if match.group("iclosed") != "/":
                    sprite_id = None
                    if item_type == "DefineSpriteTag":
                        id_match = SWF_SPRITE_ID_RE.search(token)
                        sprite_id = id_match.group(1) if id_match else None
                    item_stack.append((item_type, sprite_id))
    return {"root": root_labels, "sprites": sprites, "rootFrames": frame - 1}


def timeline_labels_from_swf_xml(xml_path: Path) -> dict[str, int]:
    labels = dict(swf_xml_timelines(xml_path)["root"])
    if DEFAULT_EXPRESSION not in labels:
        labels[DEFAULT_EXPRESSION] = 1
    return labels


def find_exported_frame_dir(base: Path, expected_id: int | None = None) -> Path:
    dirs = [p for p in base.iterdir() if p.is_dir()]
    if not dirs:
        return base
    if expected_id is not None:
        for directory in dirs:
            if f"_{expected_id}_" in directory.name or directory.name.endswith(f"_{expected_id}"):
                return directory
    if len(dirs) == 1:
        return dirs[0]
    return base


def exported_asset_id_from_swf_xml(xml_path: Path, export_name: str) -> int | None:
    root = ET.parse(xml_path).getroot()
    for item in iter_desc(root, "item"):
        if item.attrib.get("type") != "ExportAssetsTag":
            continue
        tags = first_child(item, "tags")
        names = first_child(item, "names")
        if tags is None or names is None:
            continue
        tag_values = [normalize_key(child.text) for child in list(tags) if local_name(child.tag) == "item"]
        name_values = [normalize_key(child.text) for child in list(names) if local_name(child.tag) == "item"]
        for raw_id, name in zip(tag_values, name_values):
            if name == export_name and raw_id.isdigit():
                return int(raw_id)
    return None


def ffdec_render_zoom(args: argparse.Namespace) -> int:
    """FFDec 的实际渲染倍率 = 输出缩放 × 超采样。"""
    return max(1, args.zoom) * max(1, args.supersample)


def downscale_supersampled_frames(frame_dir: Path, factor: int) -> None:
    """把超采样渲染出的帧按 1/factor 用 LANCZOS 降回原始尺寸。

    超采样只是渲染期画质手段，产物尺寸必须与不超采样时完全一致，否则 manifest 里的
    width/height 与 portraitWindow 会整体失配。顺序固定：先降采样，再交给 copy_asset
    原样落盘（PNG 保存统一走 compress_level=9，和下游既有产物保持一致）。
    """
    if factor <= 1:
        return
    for path in sorted(frame_dir.glob("*.png")):
        with Image.open(path) as opened:
            image = opened.convert("RGBA")
        width = max(1, round(image.width / factor))
        height = max(1, round(image.height / factor))
        image.resize((width, height), Image.Resampling.LANCZOS).save(
            path, format="PNG", compress_level=9, optimize=False
        )


def export_external_frames(
    ffdec: Path,
    project_root: Path,
    swf: Path,
    labels: dict[str, int],
    out_dir: Path,
    zoom: int,
    timeout_seconds: int,
    selected_only: bool = True,
) -> None:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    selected = ",".join(str(frame) for frame in sorted(set(labels.values())))
    args = [
        str(ffdec),
        "-ignorebackground",
        "-zoom",
        str(zoom),
        "-format",
        "frame:png",
    ]
    if selected and selected_only:
        args += ["-select", selected]
    args += ["-export", "frame", str(out_dir), str(swf)]
    run_command(args, project_root, timeout_seconds)


def missing_label_frames(frames_dir: Path, labels: dict[str, int]) -> list[tuple[str, int]]:
    missing = []
    for expression, frame_no in labels.items():
        if not (frames_dir / f"{frame_no}.png").exists():
            missing.append((expression, frame_no))
    return missing


def export_internal_sprite(
    ffdec: Path,
    project_root: Path,
    swf: Path,
    out_dir: Path,
    sprite_id: int,
    zoom: int,
    timeout_seconds: int,
) -> Path:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            str(ffdec),
            "-ignorebackground",
            "-zoom",
            str(zoom),
            "-format",
            "sprite:png",
            "-selectid",
            str(sprite_id),
            "-export",
            "sprite",
            str(out_dir),
            str(swf),
        ],
        project_root,
        timeout_seconds,
    )
    return find_exported_frame_dir(out_dir, sprite_id)


def raster_magic(data: bytes) -> str:
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return ""


def copy_asset(
    src: Path,
    output_dir: Path,
    rel_dir: str,
    expression: str,
    *,
    source_kind: str = "",
    image_format: str = "png",
    semantic_baseline: dict[str, dict[str, Any]] | None = None,
    semantic_noop_assets: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    dst_rel = Path(rel_dir) / stable_file(expression, image_format)
    dst = output_dir / dst_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    uri = dst_rel.as_posix()
    baseline = (semantic_baseline or {}).get(uri)
    # 复用只在同一 URI（后缀即格式）且字节魔数与目标格式一致时成立：
    # 基线里的 PNG 字节绝不能直接写成 .webp 文件。
    reused = (
        source_kind == "dialogue-ui-sprite"
        and baseline is not None
        and raster_magic(baseline["raster"]) == image_format
        and internal_assets_are_alpha_equivalent(src, baseline["raster"])
    )
    if reused:
        dst.write_bytes(baseline["raster"])
        if semantic_noop_assets is not None:
            candidate_width, candidate_height = raster_size(src)
            semantic_noop_assets.append(
                {
                    "uri": uri,
                    "reason": "alpha-equivalent-transparent-canvas-only",
                    "candidateSize": {"width": candidate_width, "height": candidate_height},
                    "reusedSize": {
                        "width": int(baseline["asset"]["width"]),
                        "height": int(baseline["asset"]["height"]),
                    },
                }
            )
    elif image_format == "webp":
        # lossless+exact：RGBA 逐像素保真，全透明像素保留原 RGB（主控实测与
        # 源 PNG RGBA 等值）。中间帧始终是 PNG，仅此最终编码为 webp。
        with Image.open(src) as opened:
            opened.convert("RGBA").save(dst, format="WEBP", lossless=True, exact=True, quality=100, method=6)
    else:
        shutil.copy2(src, dst)
    width, height = raster_size(dst)
    asset = {
        "uri": uri,
        "width": width,
        "height": height,
        "frame": int(src.stem) if src.stem.isdigit() else None,
        "sha256": hashlib.sha256(dst.read_bytes()).hexdigest(),
        "bytes": dst.stat().st_size,
        "format": image_format,
    }
    bounds = raster_alpha_bounds(dst)
    if bounds:
        asset["bounds"] = bounds
    return asset


def labels_from_symbol_xml(xml_path: Path) -> dict[str, int]:
    if not xml_path.exists():
        return {}
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError:
        return {}
    result: dict[str, int] = {}
    for layer in iter_desc(root, "DOMLayer"):
        if layer.attrib.get("name") != "Labels Layer":
            continue
        frames = first_child(layer, "frames")
        if frames is None:
            continue
        for frame in list(frames):
            if local_name(frame.tag) != "DOMFrame":
                continue
            name = normalize_key(frame.attrib.get("name"))
            if name:
                result[name] = int(frame.attrib.get("index") or 0)
        break
    return result


def frame_ranges_from_dialogue_portrait(xfl_xml: Path) -> list[dict[str, Any]]:
    root = ET.parse(xfl_xml).getroot()
    labels: list[dict[str, Any]] = []
    for layer in iter_desc(root, "DOMLayer"):
        if layer.attrib.get("name") != "Labels Layer":
            continue
        frames = first_child(layer, "frames")
        if frames is None:
            continue
        for frame in list(frames):
            if local_name(frame.tag) != "DOMFrame":
                continue
            name = normalize_key(frame.attrib.get("name"))
            if not name:
                continue
            labels.append(
                {
                    "key": name,
                    "index": int(frame.attrib.get("index") or 0),
                    "duration": int(frame.attrib.get("duration") or 1),
                }
            )
        break
    return labels


def symbol_on_frame(xfl_xml: Path, frame_index: int) -> str | None:
    root = ET.parse(xfl_xml).getroot()
    for layer in iter_desc(root, "DOMLayer"):
        name = layer.attrib.get("name") or ""
        if name in {"Labels Layer", "Script Layer"} or layer.attrib.get("layerType") == "mask":
            continue
        frames = first_child(layer, "frames")
        if frames is None:
            continue
        for frame in list(frames):
            if local_name(frame.tag) != "DOMFrame":
                continue
            start = int(frame.attrib.get("index") or 0)
            duration = int(frame.attrib.get("duration") or 1)
            if frame_index < start or frame_index >= start + duration:
                continue
            elements = first_child(frame, "elements")
            if elements is None:
                continue
            for symbol in iter_desc(elements, "DOMSymbolInstance"):
                item = normalize_key(symbol.attrib.get("libraryItemName"))
                if item:
                    return item
    return None


def resolve_library_xml(library_dir: Path, library_item_name: str) -> Path:
    return library_dir / Path(library_item_name + ".xml")


def load_authority_policy(policy_path: Path) -> tuple[dict[str, Any], dict[str, str], str]:
    if not policy_path.exists():
        raise RuntimeError(f"Missing dialogue portrait source authority policy: {policy_path}")
    raw = policy_path.read_bytes()
    policy = json.loads(raw.decode("utf-8"))
    if policy.get("schema") != AUTHORITY_POLICY_SCHEMA:
        raise RuntimeError(f"Unsupported dialogue portrait authority policy schema: {policy.get('schema')}")
    raw_decisions = policy.get("decisions")
    if not isinstance(raw_decisions, dict) or not raw_decisions:
        raise RuntimeError("Dialogue portrait authority policy decisions must be a non-empty object")
    decisions: dict[str, str] = {}
    for raw_key, raw_source in raw_decisions.items():
        key = normalize_key(raw_key)
        source = normalize_key(raw_source)
        if not key or key != raw_key:
            raise RuntimeError(f"Dialogue portrait authority policy key is not normalized: {raw_key!r}")
        if source not in SOURCE_IDS:
            raise RuntimeError(f"Dialogue portrait authority policy has unsupported source for {key}: {source}")
        decisions[key] = source
    return policy, decisions, hashlib.sha256(raw).hexdigest()


def discover_source_collisions(project_root: Path, limit: int = 0) -> list[str]:
    external_names = read_external_names(project_root / "flashswf" / "portraits" / "list.xml")
    if limit > 0:
        external_names = external_names[:limit]
    internal_ranges = frame_ranges_from_dialogue_portrait(
        project_root / "flashswf" / "UI" / "对话框界面" / "LIBRARY" / "对话框肖像.xml"
    )
    internal_names = {
        normalize_key(item.get("key"))
        for item in internal_ranges
        if normalize_key(item.get("key"))
        and not normalize_key(item.get("key")).startswith("--")
        and normalize_key(item.get("key")) not in SKIP_INTERNAL_KEYS
    }
    return [name for name in external_names if name in internal_names]


def validate_authority_policy_coverage(
    decisions: dict[str, str],
    collisions: list[str],
    *,
    require_exact: bool,
) -> None:
    collision_set = set(collisions)
    decision_set = set(decisions)
    missing = sorted(collision_set - decision_set)
    stale = sorted(decision_set - collision_set) if require_exact else []
    if missing or stale:
        raise RuntimeError(
            "Dialogue portrait source authority policy coverage mismatch: "
            + json.dumps({"missing": missing, "stale": stale}, ensure_ascii=False)
        )


def append_entry(
    manifest: dict[str, Any],
    entry: dict[str, Any],
    authority_decisions: dict[str, str],
    report: dict[str, Any],
) -> None:
    key = entry["key"]
    existing = manifest["entries"].get(key)
    if existing is None:
        manifest["entries"][key] = entry
        return
    existing_source = normalize_key(existing.get("source"))
    incoming_source = normalize_key(entry.get("source"))
    if existing_source == incoming_source:
        raise RuntimeError(f"Duplicate dialogue portrait entry within source {incoming_source}: {key}")
    candidates = {existing_source, incoming_source}
    selected_source = authority_decisions.get(key)
    if selected_source is None:
        raise RuntimeError(f"Unreviewed dialogue portrait source collision: {key}")
    if selected_source not in candidates:
        raise RuntimeError(
            f"Dialogue portrait authority for {key} selects {selected_source}, "
            f"but candidates are {sorted(candidates)}"
        )
    selected = existing if existing_source == selected_source else entry
    rejected = entry if selected is existing else existing
    manifest["entries"][key] = selected
    report["sourceCollisions"].append(
        {
            "key": key,
            "candidates": sorted(candidates),
            "selectedSource": selected_source,
            "rejectedSource": rejected["source"],
            "policy": "explicit-human-authority",
        }
    )


def rebuild_aliases(manifest: dict[str, Any]) -> None:
    manifest["aliases"] = {}
    for entry in manifest["entries"].values():
        key = entry["key"]
        for alias in alias_candidates(key):
            if alias != key:
                manifest["aliases"].setdefault(alias, key)
        for alias in entry.get("aliases") or []:
            if alias and alias != key:
                manifest["aliases"].setdefault(alias, key)


def validate_baked_authority(
    manifest: dict[str, Any],
    report: dict[str, Any],
    collisions: list[str],
    authority_decisions: dict[str, str],
) -> None:
    expected = set(collisions)
    observed = {normalize_key(item.get("key")) for item in report["sourceCollisions"]}
    if observed != expected:
        raise RuntimeError(
            "Dialogue portrait baked collision closure mismatch: "
            + json.dumps(
                {
                    "missing": sorted(expected - observed),
                    "unexpected": sorted(observed - expected),
                },
                ensure_ascii=False,
            )
        )
    wrong = []
    for key in collisions:
        actual = normalize_key(manifest["entries"].get(key, {}).get("source"))
        selected = authority_decisions[key]
        if actual != selected:
            wrong.append({"key": key, "selected": selected, "actual": actual or None})
    if wrong:
        raise RuntimeError(
            "Dialogue portrait baked authority postcondition failed: "
            + json.dumps(wrong, ensure_ascii=False)
        )


def on_disk_assets(output_dir: Path) -> set[str]:
    return {
        path.relative_to(output_dir).as_posix()
        for path in output_dir.rglob("*")
        if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
    }


def enforce_asset_closure(
    output_dir: Path,
    manifest: dict[str, Any],
    review_candidate_dir: Path | None = None,
) -> tuple[set[str], list[str]]:
    referenced: set[str] = set()
    for entry in manifest.get("entries", {}).values():
        for asset in (entry.get("expressions") or {}).values():
            uri = normalize_key(asset.get("uri"))
            if not uri or uri in referenced:
                raise RuntimeError(f"Invalid or duplicate dialogue portrait manifest asset URI: {uri!r}")
            referenced.add(uri)
    on_disk = on_disk_assets(output_dir)
    missing = sorted(referenced - on_disk)
    if missing:
        raise RuntimeError(
            "Dialogue portrait asset closure has missing images: "
            + json.dumps(missing, ensure_ascii=False)
        )
    pruned = sorted(on_disk - referenced)
    for uri in pruned:
        source_path = output_dir / Path(uri)
        if review_candidate_dir is not None:
            candidate_path = review_candidate_dir / Path(uri)
            candidate_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, candidate_path)
        source_path.unlink()
    directories = sorted(
        (path for path in output_dir.rglob("*") if path.is_dir()),
        key=lambda path: len(path.parts),
        reverse=True,
    )
    for directory in directories:
        if not any(directory.iterdir()):
            directory.rmdir()
    final_on_disk = on_disk_assets(output_dir)
    if final_on_disk != referenced:
        raise RuntimeError("Dialogue portrait asset closure did not converge after pruning")
    return referenced, pruned


def bake_external(
    args: argparse.Namespace,
    manifest: dict[str, Any],
    report: dict[str, Any],
    authority_decisions: dict[str, str],
    selected_keys: set[str] | None = None,
    selected_expressions: set[str] | None = None,
) -> None:
    project_root = Path(args.project_root)
    ffdec = Path(args.ffdec)
    portrait_dir = project_root / "flashswf" / "portraits"
    lookup = swf_lookup(portrait_dir)
    names = read_external_names(portrait_dir / "list.xml")
    if selected_keys is not None:
        names = [name for name in names if external_name_selected(name, lookup, selected_keys)]
    if args.limit > 0:
        names = names[: args.limit]
    tmp_base = Path(args.tmp_dir) / "external"
    for index, name in enumerate(names, 1):
        swf = lookup.get(name) or lookup.get(name.lower())
        if not swf or not swf.exists():
            report["missingExternalSwf"].append(name)
            continue
        key = swf.stem
        print(f"[external {index}/{len(names)}] {key}")
        stem_id = stable_dir("external", key)
        xml_path = tmp_base / stem_id / "source.xml"
        frames_dir = tmp_base / stem_id / "frames"
        export_swf_xml(ffdec, project_root, swf, xml_path, args.ffdec_timeout_seconds)
        timelines = swf_xml_timelines(xml_path)
        if timelines["sprites"]:
            # 嵌套 sprite 自带标签 = 运行时变体（如「室友」按玩家性别选 男/女 帧）。
            # 静态根帧导出不能等价复现，先把逐 sprite 标签写进报告供变体裁决使用。
            report["nestedTimelineLabels"][key] = {
                sprite_id: dict(sprite_labels)
                for sprite_id, sprite_labels in sorted(
                    timelines["sprites"].items(), key=lambda item: int(item[0])
                )
            }
        variant_plans = plans_for(key, timelines)
        if variant_plans:
            if selected_expressions is not None:
                variant_plans = [p for p in variant_plans
                                 if p["expression"] == DEFAULT_EXPRESSION or p["expression"] in selected_expressions]
            variant_dir = tmp_base / stem_id / "variants"
            results = render_variant_frames(ffdec, project_root, swf, variant_plans,
                                            variant_dir, args.zoom * args.supersample,
                                            args.ffdec_timeout_seconds)
            for sprite_id in {r["sourceSpriteId"] for r in results}:
                downscale_supersampled_frames(variant_dir / "frames" / f"sprite_{sprite_id}", args.supersample)
            entries = {}
            for result in results:
                variant_key = result["key"]
                entry = entries.setdefault(variant_key, {
                    "key": variant_key, "aliases": [], "source": "external-swf",
                    "sourcePath": swf.relative_to(project_root).as_posix(), "sourceKey": key,
                    "sourceSpriteId": result["sourceSpriteId"], "coordinateSpace": "sprite-natural",
                    "selection": result["selection"], "defaultExpression": DEFAULT_EXPRESSION,
                    "expressions": {},
                })
                asset = copy_asset(variant_dir / result["png"], Path(args.output_dir),
                                   f"external/{stable_dir('p', variant_key)}", result["expression"],
                                   image_format=args.image_format)
                asset["rasterization"] = {"renderer": result["renderer"],
                                          "sourceSpriteId": result["sourceSpriteId"],
                                          "zoom": args.zoom, "supersample": args.supersample,
                                          "resolutionScale": result["resolutionScale"],
                                          "minimumVisibleHeight": result["minimumVisibleHeight"] // args.supersample}
                entry["expressions"][result["expression"]] = asset
            for entry in entries.values():
                append_entry(manifest, entry, authority_decisions, report)
                report["externalEntries"] += 1
                report["externalExpressions"] += len(entry["expressions"])
            continue
        labels = dict(timelines["root"])
        if DEFAULT_EXPRESSION not in labels:
            labels[DEFAULT_EXPRESSION] = 1
        labels = filter_expression_frames(labels, selected_expressions)
        render_zoom = ffdec_render_zoom(args)
        export_external_frames(ffdec, project_root, swf, labels, frames_dir, render_zoom, args.ffdec_timeout_seconds)
        if missing_label_frames(frames_dir, labels):
            # 回退重导（不带 -select）写到独立子目录，避免整目录删除再重建。
            frames_dir = tmp_base / stem_id / "frames-all"
            export_external_frames(
                ffdec,
                project_root,
                swf,
                labels,
                frames_dir,
                render_zoom,
                args.ffdec_timeout_seconds,
                selected_only=False,
            )
        downscale_supersampled_frames(frames_dir, args.supersample)
        entry = {
            "key": key,
            "aliases": [a for a in alias_candidates(name) if a != key],
            "source": "external-swf",
            "sourcePath": swf.relative_to(project_root).as_posix(),
            "defaultExpression": DEFAULT_EXPRESSION,
            "expressions": {},
        }
        for expression, frame_no in sorted(labels.items(), key=lambda item: (item[1], item[0])):
            frame_path = frames_dir / f"{frame_no}.png"
            if not frame_path.exists():
                report["missingFrames"].append({"key": key, "expression": expression, "frame": frame_no})
                continue
            entry["expressions"][expression] = copy_asset(
                frame_path,
                Path(args.output_dir),
                f"external/{stable_dir('p', key)}",
                expression,
                image_format=args.image_format,
            )
        append_entry(manifest, entry, authority_decisions, report)
        report["externalEntries"] += 1
        report["externalExpressions"] += len(entry["expressions"])


def bake_internal(
    args: argparse.Namespace,
    manifest: dict[str, Any],
    report: dict[str, Any],
    authority_decisions: dict[str, str],
    semantic_baseline: dict[str, dict[str, Any]],
    semantic_noop_assets: list[dict[str, Any]],
    selected_keys: set[str] | None = None,
    selected_expressions: set[str] | None = None,
) -> None:
    project_root = Path(args.project_root)
    ffdec = Path(args.ffdec)
    ui_dir = project_root / "flashswf" / "UI" / "对话框界面"
    library_dir = ui_dir / "LIBRARY"
    portrait_xml = library_dir / "对话框肖像.xml"
    swf = project_root / "flashswf" / "UI" / "对话框界面.swf"
    tmp_base = Path(args.tmp_dir) / "internal"
    print("[internal] 对话框肖像")
    swf_xml = tmp_base / "source.xml"
    export_swf_xml(ffdec, project_root, swf, swf_xml, args.ffdec_timeout_seconds)
    sprite_id = exported_asset_id_from_swf_xml(swf_xml, INTERNAL_PORTRAIT_EXPORT_NAME)
    if sprite_id is None:
        raise RuntimeError(f"Cannot resolve exported symbol {INTERNAL_PORTRAIT_EXPORT_NAME} in {swf}")
    report["internalPortraitSpriteId"] = sprite_id
    plans = []
    ranges = frame_ranges_from_dialogue_portrait(portrait_xml)
    for item in ranges:
        key = item["key"]
        if key.startswith("--") or key in SKIP_INTERNAL_KEYS:
            continue
        if selected_keys is not None and normalize_key(key) not in selected_keys:
            continue
        start = int(item["index"])
        duration = int(item["duration"])
        entry = {
            "key": key,
            "aliases": [],
            "source": "dialogue-ui-sprite",
            "sourcePath": swf.relative_to(project_root).as_posix(),
            "defaultExpression": DEFAULT_EXPRESSION,
            "expressions": {},
        }
        expression_frames: dict[str, int] = {DEFAULT_EXPRESSION: start + 1}
        symbol_name = symbol_on_frame(portrait_xml, start)
        if symbol_name:
            child_labels = labels_from_symbol_xml(resolve_library_xml(library_dir, symbol_name))
            for expression, child_index in child_labels.items():
                if expression in {"刷新", "男", "女"}:
                    continue
                frame_no = start + int(child_index) + 1
                if frame_no >= start + 1 and frame_no <= start + max(duration, 1):
                    expression_frames[expression] = frame_no
        expression_frames = filter_expression_frames(expression_frames, selected_expressions)
        plans.append((entry, expression_frames))

    if not plans:
        return
    renderer = args.internal_renderer
    if renderer == "auto":
        renderer = "ffdec" if args.zoom == 1 and args.image_format == "png" else "svg"
    raster_evidence = {}
    if renderer == "svg":
        # Java2D 在 sprite981 的武器大师曲线上确定失败；SVG 保留同一源的形状和剪裁，
        # 只栅格化实际需要的帧，避免为了29个静态立绘逐一渲染262帧。
        from dialogue_svg_fallback import recover_sprite_frames

        frame_dir = tmp_base / "svg-pixels"
        wanted = sorted({frame for _, frames in plans for frame in frames.values()})
        raster_evidence = recover_sprite_frames(
            ffdec, project_root, swf, sprite_id, wanted, frame_dir, tmp_base / "svg-source",
            ffdec_render_zoom(args), args.ffdec_timeout_seconds,
        )
        downscale_supersampled_frames(frame_dir, args.supersample)
    else:
        frame_dir = export_internal_sprite(ffdec, project_root, swf, tmp_base / "sprite",
                                           sprite_id, args.zoom, args.ffdec_timeout_seconds)
    report["internalRenderer"] = renderer
    for entry, expression_frames in plans:
        key = entry["key"]
        for expression, frame_no in sorted(expression_frames.items(), key=lambda item: (item[1], item[0])):
            frame_path = frame_dir / f"{frame_no}.png"
            if not frame_path.exists():
                report["missingFrames"].append({"key": key, "expression": expression, "frame": frame_no})
                continue
            entry["expressions"][expression] = copy_asset(
                frame_path,
                Path(args.output_dir),
                f"internal/{stable_dir('p', key)}",
                expression,
                source_kind="dialogue-ui-sprite",
                image_format=args.image_format,
                semantic_baseline=semantic_baseline,
                semantic_noop_assets=semantic_noop_assets,
            )
            if frame_no in raster_evidence:
                entry["expressions"][expression]["rasterization"] = raster_evidence[frame_no]
        if entry["expressions"]:
            append_entry(manifest, entry, authority_decisions, report)
            report["internalEntries"] += 1
            report["internalExpressions"] += len(entry["expressions"])


def main() -> None:
    args = parse_args()
    if args.zoom < 1 or args.zoom > 4 or args.supersample < 1 or args.supersample > 4:
        raise SystemExit("zoom and supersample must each be in 1..4")
    if args.zoom * args.supersample > 8:
        raise SystemExit("combined render zoom must not exceed 8")
    if args.external_only and args.internal_only:
        raise SystemExit("--external-only and --internal-only are mutually exclusive")
    project_root = Path(args.project_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    tmp_dir = Path(args.tmp_dir).resolve()
    authority_policy_path = Path(args.authority_policy).resolve()
    semantic_baseline_dir = (
        Path(args.semantic_baseline_dir).resolve()
        if args.semantic_baseline_dir
        else output_dir
    )
    review_candidate_dir = Path(args.review_candidate_dir).resolve()
    selected_keys = parse_selection_csv(args.keys)
    selected_expressions = parse_selection_csv(args.expressions)
    production_output_dir = (
        project_root / "launcher" / "web" / "assets" / "dialogue-portraits"
    ).resolve()
    ensure_subset_output_dir(
        output_dir,
        production_output_dir,
        selected_keys is not None or selected_expressions is not None
        or args.external_only or args.internal_only or args.limit > 0,
    )
    full_bake = (
        not args.external_only
        and not args.internal_only
        and args.limit == 0
        and selected_keys is None
        and selected_expressions is None
    )
    if not Path(args.ffdec).exists():
        raise SystemExit(f"Missing FFDec CLI: {args.ffdec}")
    authority_policy, authority_decisions, authority_policy_digest = load_authority_policy(authority_policy_path)
    collisions = (
        discover_source_collisions(project_root, args.limit)
        if not args.external_only and not args.internal_only
        else []
    )
    if selected_keys is not None:
        portrait_lookup = swf_lookup(project_root / "flashswf" / "portraits")
        collisions = [
            name
            for name in collisions
            if external_name_selected(name, portrait_lookup, selected_keys)
        ]
    validate_authority_policy_coverage(
        authority_decisions,
        collisions,
        require_exact=full_bake,
    )
    semantic_baseline = load_semantic_baseline(semantic_baseline_dir)
    active_review_candidate_dir: Path | None = None
    if full_bake:
        ensure_review_candidate_dir(review_candidate_dir, project_root)
        if review_candidate_dir.exists():
            shutil.rmtree(review_candidate_dir)
        review_candidate_dir.mkdir(parents=True, exist_ok=True)
        active_review_candidate_dir = review_candidate_dir
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    if tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    manifest: dict[str, Any] = {
        "schema": SCHEMA,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "zoom": args.zoom,
        "baseSize": {"width": 1024 * args.zoom, "height": 576 * args.zoom},
        # 复刻原版对话框取景：外部立绘透过 flashswf/UI/对话框界面 元件里的固定遮罩窗口显示。
        # 外部 SWF 在「外部立绘层」原点、100% 放置，遮罩与 SWF 共用同一坐标系，故该矩形直接是
        # 1024×576 舞台 PNG 上的裁剪框（mask 解析自 LIBRARY/对话框界面.xml 的 mask 层）。所有 pose
        # 共用此窗口 + 同一缩放 → web 端不再按各自包围盒 fit（消除「一张铺满一张很扁」）。
        # 内置 sprite（对话框肖像）取景在另一坐标系，故此处仅给 external-swf；其余走包围盒兜底。
        "portraitWindow": {
            "external-swf": {
                "x": 30 * args.zoom,
                "y": 30 * args.zoom,
                "width": 880 * args.zoom,
                "height": 375 * args.zoom,
            },
        },
        "heroKeys": sorted(HERO_KEYS),
        "sourceAuthority": {
            "schema": AUTHORITY_POLICY_SCHEMA,
            "policyPath": authority_policy_path.relative_to(project_root).as_posix(),
            "policySha256": authority_policy_digest,
            "collisionPolicy": "explicit-human-authority",
        },
        "entries": {},
        "aliases": {},
    }
    report: dict[str, Any] = {
        "externalEntries": 0,
        "externalExpressions": 0,
        "internalEntries": 0,
        "internalExpressions": 0,
        "internalPortraitSpriteId": None,
        # 超采样只影响画质、不影响几何，故只进 report，不改 manifest schema。
        "supersample": args.supersample,
        "renderZoom": ffdec_render_zoom(args),
        # 最终资产编码（png/webp）同样只进 report：manifest URI 后缀即格式。
        "imageFormat": args.image_format,
        "missingExternalSwf": [],
        "missingFrames": [],
        "sourceAuthority": {
            "policyPath": authority_policy_path.relative_to(project_root).as_posix(),
            "policySha256": authority_policy_digest,
            "reviewReceipt": authority_policy.get("reviewReceipt"),
        },
        "sourceCollisions": [],
        # 外部源里「嵌套 sprite 内标签」清单（如 室友 的 sprite6 男/女 帧）。
        # 普通根标签修复不覆盖这类运行时变体，需要单独的变体选择与取帧规则。
        "nestedTimelineLabels": {},
        "selection": {
            "keys": sorted(selected_keys) if selected_keys else [],
            "expressions": sorted(selected_expressions) if selected_expressions else [],
        },
        "unmatchedKeys": [],
    }
    semantic_noop_assets: list[dict[str, Any]] = []

    if not args.internal_only:
        bake_external(args, manifest, report, authority_decisions, selected_keys, selected_expressions)
    if not args.external_only:
        bake_internal(
            args,
            manifest,
            report,
            authority_decisions,
            semantic_baseline,
            semantic_noop_assets,
            selected_keys,
            selected_expressions,
        )
    rebuild_aliases(manifest)
    if selected_keys is not None:
        baked_keys = {normalize_key(key) for key in manifest["entries"]}
        baked_keys.update(
            normalize_key(alias)
            for entry in manifest["entries"].values()
            for alias in entry.get("aliases") or []
        )
        baked_keys.update(normalize_key(entry["sourceKey"]) for entry in manifest["entries"].values()
                          if entry.get("sourceKey"))
        report["unmatchedKeys"] = sorted(selected_keys - baked_keys)
    report["sourceCollisions"].sort(key=lambda item: item["key"])
    validate_baked_authority(manifest, report, collisions, authority_decisions)
    referenced_assets, pruned_assets = enforce_asset_closure(
        output_dir,
        manifest,
        active_review_candidate_dir,
    )
    retained_semantic_noops = sorted(
        (item for item in semantic_noop_assets if item["uri"] in referenced_assets),
        key=lambda item: item["uri"],
    )
    report["semanticNoopReuse"] = {
        "algorithm": "internal-alpha-bounds-and-visible-rgba-v1",
        "count": len(retained_semantic_noops),
        "assets": retained_semantic_noops,
    }
    report["assetClosure"] = {
        "referencedPngs": sum(uri.endswith(".png") for uri in referenced_assets),
        "onDiskPngs": sum(uri.endswith(".png") for uri in referenced_assets),
        "prunedPngs": sum(uri.endswith(".png") for uri in pruned_assets),
        "prunedAssets": pruned_assets,
        "referencedAssets": len(referenced_assets),
        "onDiskAssets": len(referenced_assets),
        "totalBytes": sum((output_dir / uri).stat().st_size for uri in referenced_assets),
    }
    manifest["generatorInputs"] = [
        {"path": source.relative_to(project_root).as_posix(),
         "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        for source in (project_root / "tools" / "bake-dialogue-portraits.py",
                       project_root / "tools" / "dialogue_svg_fallback.py",
                       project_root / "tools" / "dialogue_portrait_variants.py",
                       project_root / "tools" / "dialogue-portrait-source-review" / "requirements.txt")
    ]

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report_path = output_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not args.keep_tmp and tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    print(json.dumps({"manifest": str(manifest_path.relative_to(project_root)), "report": report}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
