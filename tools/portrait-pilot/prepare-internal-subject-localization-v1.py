#!/usr/bin/env python3
"""Turn verified human internal-subject decisions into a locked localization batch.

The source-resolution order is deliberately asymmetric: an outer monster
frame is identity reference only, internal MovieClips are the primary subject
search space, and a Graphic is eligible only as a traceable last-resort
fallback.  One narrowly-scoped Graphic override is currently supported for
the alien egg: the maintainer named ``异形蛋/Symbol 7`` in root frame 1.  That
override is verified independently in packed XFL and compiled SWF XML before
the root frame is cropped to the exact connected subject.  No result is
promoted.
"""

from __future__ import annotations

import argparse
from collections import deque
import copy
import datetime as dt
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
import zlib

from PIL import Image, ImageDraw, ImageOps

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
MANIFEST_SCHEMA = "cf7.enemy-portrait-feature-refinement-candidates.v2"
LOCK_SCHEMA = "cf7.portrait-pilot-selection-lock.v1"
DIRECTIVE_SCHEMA = "cf7.enemy-portrait-graphic-subject-directive.v1"
RESCUE_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-candidates.v1"
DECISION_SCHEMA = "cf7.enemy-portrait-internal-subject-human-decisions.v1"
REVIEW_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-review-data.v1"
MODEL_SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-model-report.v1"
ALIEN_REVIEW_KEY = "敌人-异形蛋::default"
ALIEN_PORTRAIT_REF = "敌人-异形蛋"
ALIEN_FLA = ROOT / "flashswf" / "arts" / "new" / "异形蛋.fla"
ALIEN_SWF = ROOT / "flashswf" / "arts" / "new" / "异形蛋.swf"
ALIEN_ROOT_ITEM = "敌人-异形蛋"
ALIEN_GRAPHIC_ITEM = "异形蛋/Symbol 7"
ALIEN_ROOT_FRAME = 1
ALIEN_ROOT_CHARACTER_ID = 54
ALIEN_SHAPE_ID = 1
PREVIEW_ZOOM = 2
EXPECTED_ROWS = 17
XFL_NS = "http://ns.adobe.com/xfl/2008/"
UNIFORM_RECTANGLE_MAX_VISIBLE_COLORS = 2
UNIFORM_RECTANGLE_MIN_FILL_RATIO = 0.985


class SubjectLocalizationError(core.PilotError):
    pass


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def require_object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise SubjectLocalizationError(f"{label} 必须是对象")
    return value


def require_list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise SubjectLocalizationError(f"{label} 必须是数组")
    return value


def require_ascii_batch_id(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value or ""):
        raise SubjectLocalizationError("batch-id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    return value


def pilot_child(value: str, label: str, must_exist: bool) -> Path:
    path = core.ensure_below(Path(value), PILOT_ROOT, label)
    if must_exist and not path.is_dir():
        raise SubjectLocalizationError(f"{label} 不存在：{core.repo_rel(path)}")
    if not must_exist and path.exists():
        raise SubjectLocalizationError(f"{label} 已存在，禁止覆盖：{core.repo_rel(path)}")
    return path


def stable_digest(value: object) -> str:
    return core.sha256_bytes(core.stable_bytes(value))


def dedupe_artifacts(records: list[dict[str, object]]) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    seen: set[tuple[object, object]] = set()
    for record in records:
        key = (record.get("path"), record.get("sha256"))
        if key not in seen:
            result.append(record)
            seen.add(key)
    return result


def unique_row(rows: object, key: str, value: object, label: str) -> dict[str, object]:
    matches = [row for row in require_list(rows, label) if isinstance(row, dict) and row.get(key) == value]
    if len(matches) != 1:
        raise SubjectLocalizationError(f"{label} 未命中唯一 {key}={value}")
    return matches[0]


def candidate_visual_sanity(record: dict[str, object], label: str) -> dict[str, object]:
    """Reject only an objective non-subject class, never rank artistic quality.

    A nearly solid one/two-colour rectangle is a UI/effect primitive rather
    than a recognizable monster subject.  The narrow predicate intentionally
    leaves silhouettes, abstract units, low-colour sprites, and all artistic
    judgments to the human reviewer.
    """
    path = core.verify_artifact_record(record, label)
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise SubjectLocalizationError(f"{label} 没有可见像素")
    crop = image.crop(bounds)
    visible = [(red, green, blue, value) for red, green, blue, value in crop.getdata() if value > 0]
    if not visible:
        raise SubjectLocalizationError(f"{label} 没有可见像素")
    visible_colors: set[tuple[int, int, int]] = set()
    for red, green, blue, _ in visible:
        visible_colors.add((red, green, blue))
        if len(visible_colors) > UNIFORM_RECTANGLE_MAX_VISIBLE_COLORS:
            break
    area = crop.width * crop.height
    fill_ratio = len(visible) / max(1, area)
    uniform_solid_rectangle = (
        crop.width >= 8
        and crop.height >= 8
        and len(visible_colors) <= UNIFORM_RECTANGLE_MAX_VISIBLE_COLORS
        and fill_ratio >= UNIFORM_RECTANGLE_MIN_FILL_RATIO
    )
    return {
        "alphaBounds": list(bounds),
        "visiblePixelCount": len(visible),
        "boundingArea": area,
        "alphaFillRatio": round(fill_ratio, 6),
        "visibleColorCountCapped": len(visible_colors),
        "visibleColorCountCap": UNIFORM_RECTANGLE_MAX_VISIBLE_COLORS + 1,
        "uniformSolidRectangle": uniform_solid_rectangle,
        "scope": "objective_non_subject_raster_gate_only",
    }


def verify_human_decisions(rescue_root: Path) -> None:
    completed = subprocess.run(
        [
            "node",
            str(ROOT / "tools/portrait-pilot/verify-internal-subject-review-decisions-v1.js"),
            "--review",
            core.repo_rel(rescue_root / "internal-subject-review-data.json"),
            "--decisions",
            core.repo_rel(rescue_root / "internal-subject-human-decisions.json"),
        ],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise SubjectLocalizationError(f"内部主体人工决定验证失败：{detail}")


def load_rescue_inputs(rescue_root: Path) -> dict[str, object]:
    verify_human_decisions(rescue_root)
    paths = {
        "manifest": rescue_root / "internal-subject-rescue-manifest.json",
        "model": rescue_root / "internal-subject-model-report.json",
        "review": rescue_root / "internal-subject-review-data.json",
        "decisions": rescue_root / "internal-subject-human-decisions.json",
    }
    values = {key: require_object(core.load_json(path), key) for key, path in paths.items()}
    manifest = values["manifest"]
    model = values["model"]
    review = values["review"]
    decisions = values["decisions"]
    core.verify_digest_object(manifest, "manifestDigest", "rescue manifest")
    core.verify_digest_object(model, "reportDigest", "rescue model report")
    core.verify_digest_object(review, "reviewDigest", "rescue review data")
    if manifest.get("schema") != RESCUE_SCHEMA or model.get("schema") != MODEL_SCHEMA:
        raise SubjectLocalizationError("rescue manifest/model schema 不受支持")
    if review.get("schema") != REVIEW_SCHEMA or decisions.get("schema") != DECISION_SCHEMA:
        raise SubjectLocalizationError("rescue review/decision schema 不受支持")
    bindings = (
        decisions.get("sourceDigest") == manifest.get("sourceDigest"),
        decisions.get("manifestDigest") == manifest.get("manifestDigest"),
        decisions.get("modelReportDigest") == model.get("reportDigest"),
        decisions.get("reviewDigest") == review.get("reviewDigest"),
        review.get("manifestDigest") == manifest.get("manifestDigest"),
        review.get("modelReportDigest") == model.get("reportDigest"),
    )
    if not all(bindings):
        raise SubjectLocalizationError("内部主体人工决定输入摘要没有闭合")
    if len(require_list(decisions.get("decisions"), "human decisions")) != EXPECTED_ROWS:
        raise SubjectLocalizationError(f"内部主体人工决定必须恰有 {EXPECTED_ROWS} 行")
    return {"paths": paths, **values}


def read_packed_xfl_entries(path: Path) -> dict[str, bytes]:
    """Read FLA's local ZIP records.

    CS6 accepts this packed XFL although Python's central-directory parser is
    stricter than .NET for this particular archive.  Local records carry
    complete sizes and CRCs, so reading them directly remains deterministic.
    """
    data = path.read_bytes()
    offset = 0
    entries: dict[str, bytes] = {}
    while offset + 4 <= len(data) and data[offset : offset + 4] == b"PK\x03\x04":
        if offset + 30 > len(data):
            raise SubjectLocalizationError("FLA local ZIP header 截断")
        (
            _version,
            flags,
            method,
            _mtime,
            _mdate,
            expected_crc,
            compressed_size,
            uncompressed_size,
            name_length,
            extra_length,
        ) = struct.unpack_from("<HHHHHIIIHH", data, offset + 4)
        if flags & 0x0008:
            raise SubjectLocalizationError("FLA 使用了未受支持的数据描述符 local record")
        name_start = offset + 30
        name_end = name_start + name_length
        payload_start = name_end + extra_length
        payload_end = payload_start + compressed_size
        if payload_end > len(data):
            raise SubjectLocalizationError("FLA local ZIP payload 截断")
        encoding = "utf-8" if flags & 0x0800 else "cp437"
        name = data[name_start:name_end].decode(encoding)
        compressed = data[payload_start:payload_end]
        if method == 0:
            payload = compressed
        elif method == 8:
            payload = zlib.decompress(compressed, -15)
        else:
            raise SubjectLocalizationError(f"FLA ZIP compression method 不受支持：{method}")
        if len(payload) != uncompressed_size or zlib.crc32(payload) & 0xFFFFFFFF != expected_crc:
            raise SubjectLocalizationError(f"FLA entry 字节或 CRC 不匹配：{name}")
        if name in entries:
            if entries[name] != payload:
                raise SubjectLocalizationError(f"FLA entry 同名但字节不同：{name}")
        else:
            entries[name] = payload
        offset = payload_end
    if not entries:
        raise SubjectLocalizationError("FLA 没有可读 packed XFL local records")
    return entries


def zip_entry_record(archive: Path, name: str, payload: bytes) -> dict[str, object]:
    return {
        "archive": core.artifact(archive),
        "entry": name,
        "bytes": len(payload),
        "sha256": core.sha256_bytes(payload),
    }


def local_name(node: ET.Element) -> str:
    return node.tag.rsplit("}", 1)[-1]


def graphic_xfl_mapping() -> dict[str, object]:
    entries = read_packed_xfl_entries(ALIEN_FLA)
    graphic_name = f"LIBRARY/{ALIEN_GRAPHIC_ITEM}.xml"
    root_name = f"LIBRARY/{ALIEN_ROOT_ITEM}.xml"
    if graphic_name not in entries or root_name not in entries:
        raise SubjectLocalizationError("异形蛋 FLA 缺指定 root/Graphic XFL entry")
    graphic = ET.fromstring(entries[graphic_name])
    root = ET.fromstring(entries[root_name])
    if graphic.attrib.get("name") != ALIEN_GRAPHIC_ITEM or graphic.attrib.get("symbolType") != "graphic":
        raise SubjectLocalizationError("异形蛋 Symbol 7 不是指定 Graphic")
    graphic_frames = [node for node in graphic.iter() if local_name(node) == "DOMFrame"]
    graphic_shapes = [node for node in graphic.iter() if local_name(node).startswith("DOMShape")]
    graphic_instances = [node for node in graphic.iter() if local_name(node) == "DOMSymbolInstance"]
    if len(graphic_frames) != 1 or graphic_frames[0].attrib.get("index") != "0":
        raise SubjectLocalizationError("异形蛋 Symbol 7 不是单帧 Graphic")
    if len(graphic_shapes) != 1 or graphic_instances:
        raise SubjectLocalizationError("异形蛋 Symbol 7 不是单一矢量 Shape")
    if root.attrib.get("linkageIdentifier") != ALIEN_ROOT_ITEM or root.attrib.get("linkageExportForAS") != "true":
        raise SubjectLocalizationError("异形蛋 root linkage 不匹配")
    placements: list[dict[str, object]] = []
    for layer in [node for node in root.iter() if local_name(node) == "DOMLayer"]:
        for frame in [node for node in layer.iter() if local_name(node) == "DOMFrame"]:
            start = int(frame.attrib.get("index", "-1"))
            duration = int(frame.attrib.get("duration", "1"))
            if not start <= ALIEN_ROOT_FRAME - 1 < start + duration:
                continue
            for instance in [node for node in frame.iter() if local_name(node) == "DOMSymbolInstance"]:
                if instance.attrib.get("libraryItemName") != ALIEN_GRAPHIC_ITEM:
                    continue
                matrices = [node for node in instance.iter() if local_name(node) == "Matrix"]
                if len(matrices) != 1:
                    raise SubjectLocalizationError("异形蛋 Symbol 7 placement matrix 不唯一")
                matrix = matrices[0]
                placements.append(
                    {
                        "layer": layer.attrib.get("name"),
                        "frameIndex": start,
                        "duration": duration,
                        "symbolType": instance.attrib.get("symbolType"),
                        "loop": instance.attrib.get("loop"),
                        "matrix": {
                            "tx": float(matrix.attrib.get("tx", "0")),
                            "ty": float(matrix.attrib.get("ty", "0")),
                        },
                    }
                )
    if len(placements) != 1:
        raise SubjectLocalizationError(f"异形蛋 root 第 1 帧没有唯一 Symbol 7 placement：{len(placements)}")
    placement = placements[0]
    if (
        placement["layer"] != "Layer 8"
        or placement["frameIndex"] != 0
        or placement["duration"] != 118
        or placement["symbolType"] != "graphic"
        or placement["loop"] != "loop"
        or placement["matrix"] != {"tx": -46.45, "ty": -84.15}
    ):
        raise SubjectLocalizationError(f"异形蛋 Symbol 7 placement 漂移：{placement}")
    return {
        "fla": core.artifact(ALIEN_FLA),
        "rootItem": ALIEN_ROOT_ITEM,
        "graphicItem": ALIEN_GRAPHIC_ITEM,
        "rootFrame": ALIEN_ROOT_FRAME,
        "graphicSymbolType": "graphic",
        "graphicFrameCount": 1,
        "graphicShapeCount": 1,
        "placement": placement,
        "rootEntry": zip_entry_record(ALIEN_FLA, root_name, entries[root_name]),
        "graphicEntry": zip_entry_record(ALIEN_FLA, graphic_name, entries[graphic_name]),
    }


def graphic_swf_mapping(xml_path: Path, xfl: dict[str, object]) -> dict[str, object]:
    parsed = ET.parse(xml_path).getroot()
    exports = core.export_assets_from_xml(xml_path)
    roots = exports.get(ALIEN_ROOT_ITEM, [])
    if roots != [ALIEN_ROOT_CHARACTER_ID]:
        raise SubjectLocalizationError(f"异形蛋 SWF linkage root 漂移：{roots}")
    items = list(parsed.iter("item"))
    root_matches = [
        node
        for node in items
        if node.attrib.get("type") == "DefineSpriteTag"
        and int(node.attrib.get("spriteId", "-1")) == ALIEN_ROOT_CHARACTER_ID
    ]
    if len(root_matches) != 1 or int(root_matches[0].attrib.get("frameCount", "0")) != 147:
        raise SubjectLocalizationError("异形蛋 SWF root sprite/frameCount 漂移")
    sub_tags = root_matches[0].find("subTags")
    if sub_tags is None:
        raise SubjectLocalizationError("异形蛋 SWF root 缺 subTags")
    first_frame: list[ET.Element] = []
    for node in sub_tags.findall("item"):
        if node.attrib.get("type") == "ShowFrameTag":
            break
        first_frame.append(node)
    placements = [
        node
        for node in first_frame
        if node.attrib.get("type", "").startswith("PlaceObject")
        and int(node.attrib.get("characterId", "-1")) == ALIEN_SHAPE_ID
    ]
    if len(placements) != 1 or int(placements[0].attrib.get("depth", "-1")) != 1:
        raise SubjectLocalizationError("异形蛋 root frame 1 没有唯一 depth 1 Shape 1 placement")
    matrix = placements[0].find("matrix")
    if matrix is None:
        raise SubjectLocalizationError("异形蛋编译 Shape placement 缺 matrix")
    translate = {
        "translateX": int(matrix.attrib.get("translateX", "0")),
        "translateY": int(matrix.attrib.get("translateY", "0")),
    }
    xfl_matrix = require_object(require_object(xfl["placement"], "XFL placement")["matrix"], "XFL matrix")
    expected_translate = {
        "translateX": round(float(xfl_matrix["tx"]) * 20),
        "translateY": round(float(xfl_matrix["ty"]) * 20),
    }
    if translate != expected_translate or translate != {"translateX": -929, "translateY": -1683}:
        raise SubjectLocalizationError(f"异形蛋 XFL/SWF twip matrix 不闭合：{translate}/{expected_translate}")
    shapes = [
        node
        for node in items
        if node.attrib.get("type", "").startswith("DefineShape")
        and int(node.attrib.get("shapeId", "-1")) == ALIEN_SHAPE_ID
    ]
    if len(shapes) != 1 or shapes[0].attrib.get("type") != "DefineShape4Tag":
        raise SubjectLocalizationError("异形蛋 Symbol 7 没有编译为唯一 DefineShape4 1")
    return {
        "swf": core.artifact(ALIEN_SWF),
        "ffdecXml": core.artifact(xml_path),
        "rootCharacterId": ALIEN_ROOT_CHARACTER_ID,
        "rootFrameCount": 147,
        "rootFrame": ALIEN_ROOT_FRAME,
        "shapeId": ALIEN_SHAPE_ID,
        "shapeType": "DefineShape4Tag",
        "placementDepth": 1,
        "matrixTwips": translate,
        "xflMatrixTimes20": expected_translate,
    }


def connected_components(alpha: Image.Image) -> list[dict[str, object]]:
    width, height = alpha.size
    pixels = alpha.tobytes()
    seen = bytearray(width * height)
    components: list[dict[str, object]] = []
    for start in range(width * height):
        if seen[start] or pixels[start] == 0:
            continue
        seen[start] = 1
        queue: deque[int] = deque([start])
        count = 0
        min_x = width
        min_y = height
        max_x = -1
        max_y = -1
        while queue:
            index = queue.popleft()
            y, x = divmod(index, width)
            count += 1
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                row = next_y * width
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    child = row + next_x
                    if not seen[child] and pixels[child] != 0:
                        seen[child] = 1
                        queue.append(child)
        components.append(
            {
                "visiblePixelCount": count,
                "alphaBounds": [min_x, min_y, max_x + 1, max_y + 1],
                "width": max_x - min_x + 1,
                "height": max_y - min_y + 1,
            }
        )
    return sorted(components, key=lambda row: int(row["visiblePixelCount"]), reverse=True)


def save_candidate(
    source_path: Path,
    output_path: Path,
    candidate_id: str,
    frame: int,
    component_only: bool = False,
) -> tuple[dict[str, object], list[dict[str, object]]]:
    with Image.open(source_path) as opened:
        source = opened.convert("RGBA")
    alpha = source.getchannel("A")
    components = connected_components(alpha) if component_only else []
    if component_only:
        if not components:
            raise SubjectLocalizationError(f"候选没有可见连通主体：{candidate_id}")
        alpha_bounds = tuple(int(value) for value in components[0]["alphaBounds"])
        visible_pixels = int(components[0]["visiblePixelCount"])
    else:
        bbox = alpha.getbbox()
        if bbox is None:
            raise SubjectLocalizationError(f"候选没有可见像素：{candidate_id}")
        alpha_bounds = bbox
        visible_pixels = sum(alpha.histogram()[1:])
    crop_bounds = core.expanded_bbox(alpha_bounds, source.size)
    cropped = source.crop(crop_bounds)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cropped.save(output_path, format="PNG", optimize=False, compress_level=9)
    candidate = {
        "candidateId": candidate_id,
        "frame": frame,
        "sourceSize": list(source.size),
        "alphaBounds": list(alpha_bounds),
        "sourceCropBounds": list(crop_bounds),
        "visiblePixelCount": visible_pixels,
        "width": cropped.width,
        "height": cropped.height,
        "artifact": core.artifact(output_path),
        "sourceFrameArtifact": core.artifact(source_path),
        "visualSha256": core.sha256_bytes(cropped.tobytes()),
    }
    return candidate, components


def export_selected_frames_compatible(
    adapter: dict[str, object],
    output: Path,
    swf_path: Path,
    character_id: int,
    frames: list[int],
    group_id: str,
) -> tuple[dict[str, object], dict[int, dict[str, object]]]:
    """Export exact frames while accepting FFDec's unique linkage suffix."""
    attempt_tag = "internal-subject-preview-v1"
    export_root = output / f"selected-high-resolution-{attempt_tag}" / group_id
    if export_root.exists():
        raise SubjectLocalizationError(f"选中帧目录已存在：{core.repo_rel(export_root)}")
    frame_csv = ",".join(str(frame) for frame in frames)
    run = core.run_logged_tool(
        [
            str(require_object(adapter.get("java"), "adapter java")["path"]),
            "-cp",
            str(adapter["runtimeClasspath"]),
            "SelectedSpriteFrameExporter",
            str(swf_path),
            str(export_root),
            str(character_id),
            str(PREVIEW_ZOOM),
            frame_csv,
        ],
        output,
        f"{attempt_tag}-{group_id}-selected-frames",
        900,
    )
    sprite_directories = [
        path
        for path in export_root.iterdir()
        if path.is_dir() and re.fullmatch(rf"DefineSprite_{character_id}(?:_.+)?", path.name)
    ]
    if len(sprite_directories) != 1:
        raise SubjectLocalizationError(
            f"FFDec 选中帧目录不唯一：id={character_id} matches={len(sprite_directories)}"
        )
    records: dict[int, dict[str, object]] = {}
    for frame in frames:
        frame_path = sprite_directories[0] / f"{frame}.png"
        if not frame_path.is_file():
            raise SubjectLocalizationError(f"FFDec selected frame 缺失：id={character_id} frame={frame}")
        records[frame] = core.artifact(frame_path)
    actual_files = [path for path in export_root.rglob("*") if path.is_file()]
    if len(actual_files) != len(frames):
        raise SubjectLocalizationError(
            f"FFDec selected frame 输出不精确：id={character_id} expected={len(frames)} actual={len(actual_files)}"
        )
    return {
        **run,
        "sourceSwf": core.artifact(swf_path),
        "characterId": character_id,
        "frames": frames,
        "zoom": PREVIEW_ZOOM,
        "spriteDirectory": core.repo_rel(sprite_directories[0]),
        "outputs": [records[frame] for frame in frames],
    }, records


def export_graphic_shape(output: Path, swf_path: Path) -> dict[str, object]:
    graphic_root = output / "graphic-directive"
    png_dir = graphic_root / "shape-png"
    svg_dir = graphic_root / "shape-svg"
    png_dir.mkdir(parents=True)
    svg_dir.mkdir(parents=True)
    png_run = core.run_ffdec(
        [
            "-onerror", "abort", "-ignorebackground", "-zoom", str(PREVIEW_ZOOM),
            "-selectid", str(ALIEN_SHAPE_ID), "-format", "shape:png",
            "-export", "shape", str(png_dir), str(swf_path),
        ],
        output,
        "alien-egg-shape-1-png",
    )
    svg_run = core.run_ffdec(
        [
            "-onerror", "abort", "-ignorebackground", "-selectid", str(ALIEN_SHAPE_ID),
            "-format", "shape:svg", "-export", "shape", str(svg_dir), str(swf_path),
        ],
        output,
        "alien-egg-shape-1-svg",
    )
    png_path = png_dir / f"{ALIEN_SHAPE_ID}.png"
    svg_path = svg_dir / f"{ALIEN_SHAPE_ID}.svg"
    if not png_path.is_file() or not svg_path.is_file():
        raise SubjectLocalizationError("异形蛋 Shape 1 PNG/SVG 导出不闭合")
    with Image.open(png_path) as opened:
        shape = opened.convert("RGBA")
    bbox = shape.getchannel("A").getbbox()
    if bbox is None:
        raise SubjectLocalizationError("异形蛋 Shape 1 导出为空")
    return {
        "shapeId": ALIEN_SHAPE_ID,
        "zoom": PREVIEW_ZOOM,
        "png": core.artifact(png_path),
        "svg": core.artifact(svg_path),
        "pngSize": list(shape.size),
        "alphaBounds": list(bbox),
        "visiblePixelCount": sum(shape.getchannel("A").histogram()[1:]),
        "runs": [png_run, svg_run],
    }


def validate_graphic_component(
    candidate: dict[str, object],
    components: list[dict[str, object]],
    shape: dict[str, object],
) -> dict[str, object]:
    if len(components) < 2:
        raise SubjectLocalizationError("异形蛋 root frame 没有同时呈现主体与外围 UI，证据结构漂移")
    first = components[0]
    second = components[1]
    if int(first["visiblePixelCount"]) <= int(second["visiblePixelCount"]) * 5:
        raise SubjectLocalizationError("异形蛋完整卵体不再是显著最大连通主体")
    shape_bounds = [int(value) for value in require_list(shape["alphaBounds"], "Shape alpha bounds")]
    shape_size = [shape_bounds[2] - shape_bounds[0], shape_bounds[3] - shape_bounds[1]]
    component_size = [int(first["width"]), int(first["height"])]
    dimension_delta = [abs(component_size[index] - shape_size[index]) for index in range(2)]
    pixel_delta_ratio = abs(int(first["visiblePixelCount"]) - int(shape["visiblePixelCount"])) / max(
        1, int(shape["visiblePixelCount"])
    )
    if max(dimension_delta) > 2 or pixel_delta_ratio > 0.01:
        raise SubjectLocalizationError(
            f"异形蛋 root 最大连通主体与 Shape 1 不闭合：dim={dimension_delta} pixels={pixel_delta_ratio:.6f}"
        )
    if candidate.get("alphaBounds") != first.get("alphaBounds"):
        raise SubjectLocalizationError("异形蛋候选没有使用最大连通主体")
    return {
        "componentCount": len(components),
        "largestComponent": first,
        "secondLargestVisiblePixelCount": second["visiblePixelCount"],
        "shapeAlphaSize": shape_size,
        "dimensionDelta": dimension_delta,
        "visiblePixelDeltaRatio": pixel_delta_ratio,
        "largestComponentMatchesCompiledShape": True,
    }


def draw_contact_sheet(items: list[dict[str, object]], output_path: Path, title: str) -> dict[str, object]:
    font, _ = core.find_font()
    row_height = 220
    label_width = 350
    image_width = 330
    header_height = 54
    canvas = Image.new("RGB", (label_width + image_width, header_height + row_height * len(items)), "#10161e")
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 14), title, font=font, fill="#F3F6FA")
    for index, item in enumerate(items):
        top = header_height + index * row_height
        draw.rectangle((0, top, canvas.width - 1, top + row_height - 1), outline="#3B4654", width=1)
        draw.text((14, top + 20), str(item["reviewCode"]), font=font, fill="#55E0D0")
        draw.text((14, top + 58), str(item["portraitRef"]), font=font, fill="#F3F6FA")
        draw.text((14, top + 98), "human subject locked", font=font, fill="#FFBD66")
        candidate = require_object(require_list(item["candidates"], "item candidates")[0], "candidate")
        draw.text((14, top + 136), f"{candidate['candidateId']} / f{candidate['frame']}", font=font, fill="#AEB8C5")
        with Image.open(ROOT / str(require_object(candidate["artifact"], "candidate artifact")["path"])) as opened:
            subject = opened.convert("RGBA")
        fitted = ImageOps.contain(subject, (image_width - 30, row_height - 24), Image.Resampling.LANCZOS)
        checker = Image.new("RGB", (image_width - 20, row_height - 20), "#202833")
        checker_draw = ImageDraw.Draw(checker)
        for y in range(0, checker.height, 16):
            for x in range(0, checker.width, 16):
                if (x // 16 + y // 16) % 2 == 0:
                    checker_draw.rectangle((x, y, min(checker.width - 1, x + 15), min(checker.height - 1, y + 15)), fill="#303B48")
        checker.paste(fitted, ((checker.width - fitted.width) // 2, (checker.height - fitted.height) // 2), fitted)
        canvas.paste(checker, (label_width + 10, top + 10))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    return core.artifact(output_path)


def build(args: argparse.Namespace) -> dict[str, object]:
    rescue_root = pilot_child(args.rescue_batch, "rescue 批次", must_exist=True)
    output = pilot_child(args.output, "内部主体定位输出", must_exist=False)
    batch_id = require_ascii_batch_id(args.batch_id)
    parent_manifest_path = core.ensure_below(Path(args.preference_manifest), ROOT, "偏好父 manifest")
    if not parent_manifest_path.is_file():
        raise SubjectLocalizationError("偏好父 manifest 缺失")
    parent_manifest = require_object(core.load_json(parent_manifest_path), "偏好父 manifest")
    core.verify_digest_object(parent_manifest, "manifestDigest", "偏好父 manifest")
    if parent_manifest.get("schema") != MANIFEST_SCHEMA or parent_manifest.get("phase") != "P3_FEATURE_REFINEMENT":
        raise SubjectLocalizationError("偏好父 manifest schema/phase 不受支持")
    inputs = load_rescue_inputs(rescue_root)
    rescue_manifest = require_object(inputs["manifest"], "rescue manifest")
    decisions = require_object(inputs["decisions"], "human decisions")
    items = require_list(rescue_manifest.get("reviewItems"), "rescue reviewItems")
    decision_rows = require_list(decisions.get("decisions"), "human decisions")
    if len(items) != EXPECTED_ROWS or len(decision_rows) != EXPECTED_ROWS:
        raise SubjectLocalizationError("rescue items/decisions 行数漂移")
    source_records = [
        copy.deepcopy(require_object(source.get("sourceSwf"), "rescue source SWF"))
        for source in require_list(rescue_manifest.get("sources"), "rescue sources")
        if isinstance(source, dict)
    ]
    source_records = dedupe_artifacts(source_records)
    source_by_path = {str(record["path"]): record for record in source_records}
    for record in source_records:
        core.verify_artifact_record(record, "rescue source SWF")

    selected_specs: list[dict[str, object]] = []
    for item_raw in items:
        item = require_object(item_raw, "rescue item")
        decision = unique_row(decision_rows, "reviewKey", item.get("reviewKey"), "human decisions")
        if item.get("reviewKey") == ALIEN_REVIEW_KEY:
            if decision.get("decision") != "none" or decision.get("candidateId") is not None:
                raise SubjectLocalizationError("异形蛋人工决定必须保留 none，再由显式 Graphic 指令接管")
            if "Symbol 7" not in str(decision.get("note", "")):
                raise SubjectLocalizationError("异形蛋人工备注没有明确 Symbol 7")
            character_id = ALIEN_ROOT_CHARACTER_ID
            frame = ALIEN_ROOT_FRAME
            candidate_id = "isr01-human-graphic-root54-shape1-f1"
            selected_rescue_candidate = None
        else:
            if decision.get("decision") != "select" or not isinstance(decision.get("candidateId"), str):
                raise SubjectLocalizationError(f"非异形蛋行必须显式 select：{item.get('reviewKey')}")
            selected_rescue_candidate = unique_row(
                item.get("candidates"), "candidateId", decision["candidateId"], "rescue candidates"
            )
            character_id = int(selected_rescue_candidate["spriteId"])
            frame = int(selected_rescue_candidate["frame"])
            candidate_id = str(decision["candidateId"])
            preflight_sanity = candidate_visual_sanity(
                require_object(selected_rescue_candidate["artifact"], "selected rescue candidate artifact"),
                f"人工选择 {item.get('reviewKey')} / {candidate_id}",
            )
            if preflight_sanity["uniformSolidRectangle"] is True:
                review_item = unique_row(
                    require_object(inputs["review"], "review data").get("items"),
                    "reviewKey",
                    item.get("reviewKey"),
                    "review items",
                )
                model = require_object(review_item.get("model"), "review model")
                proposal = require_object(model.get("proposal"), "proposal")
                independent = require_object(model.get("independentReview"), "independent review")
                consensus = (
                    proposal.get("decision") == "select"
                    and proposal.get("candidateId") == independent.get("candidateId")
                    and proposal.get("candidateId") != candidate_id
                )
                suggestion = f"；A/B 一致建议 {proposal.get('candidateId')}" if consensus else ""
                raise SubjectLocalizationError(
                    f"人工选择触发客观非主体门：{item.get('reviewKey')} / {candidate_id} "
                    f"是近乎纯色的实心矩形{suggestion}。请先运行单项复核页重新确认。"
                )
        preflight_sanity = None if selected_rescue_candidate is None else preflight_sanity
        source_swf = str(item["sourceSwf"])
        if source_swf not in source_by_path:
            raise SubjectLocalizationError(f"rescue source 未绑定：{source_swf}")
        selected_specs.append(
            {
                "item": item,
                "decision": decision,
                "sourceSwf": source_swf,
                "characterId": character_id,
                "frame": frame,
                "candidateId": candidate_id,
                "selectedRescueCandidate": selected_rescue_candidate,
                "preflightSubjectSanity": preflight_sanity,
            }
        )

    output.mkdir(parents=True)
    adapter = core.compile_selected_frame_exporter(output, "internal-subject-preview-v1")
    groups: dict[tuple[str, int], dict[str, object]] = {}
    for spec in selected_specs:
        key = (str(spec["sourceSwf"]), int(spec["characterId"]))
        group = groups.setdefault(key, {"frames": set(), "specs": []})
        require_object(group, "selected group")["frames"].add(int(spec["frame"]))  # type: ignore[union-attr]
        require_object(group, "selected group")["specs"].append(spec)  # type: ignore[union-attr]
    frame_records: dict[tuple[str, int, int], dict[str, object]] = {}
    export_runs: list[dict[str, object]] = []
    for index, ((source_swf, character_id), group_raw) in enumerate(sorted(groups.items()), start=1):
        group = require_object(group_raw, "selected group")
        frames = sorted(int(frame) for frame in group["frames"])  # type: ignore[arg-type]
        swf_path = core.verify_artifact_record(source_by_path[source_swf], f"来源 SWF {source_swf}")
        run, records = export_selected_frames_compatible(
            adapter,
            output,
            swf_path,
            character_id,
            frames,
            f"source-{index:03d}-character-{character_id}",
        )
        run["groupId"] = f"source-{index:03d}-character-{character_id}"
        export_runs.append(run)
        for frame, record in records.items():
            frame_records[(source_swf, character_id, frame)] = record

    alien_source = next(source for source in rescue_manifest["sources"] if source["sourceSwf"]["path"] == ALIEN_SWF.relative_to(ROOT).as_posix())
    alien_xml_path = core.verify_artifact_record(require_object(alien_source["ffdecXml"], "alien FFDec XML"), "alien FFDec XML")
    xfl_mapping = graphic_xfl_mapping()
    swf_mapping = graphic_swf_mapping(alien_xml_path, xfl_mapping)
    graphic_shape = export_graphic_shape(output, ALIEN_SWF)

    prepared_items: list[dict[str, object]] = []
    entities: list[dict[str, object]] = []
    graphic_components: list[dict[str, object]] = []
    for index, spec in enumerate(selected_specs, start=1):
        source_record = frame_records.get((str(spec["sourceSwf"]), int(spec["characterId"]), int(spec["frame"])))
        if not isinstance(source_record, dict):
            raise SubjectLocalizationError(f"选中帧导出缺失：{spec['item']['reviewKey']}")
        source_path = core.verify_artifact_record(source_record, "选中帧")
        candidate_path = output / "candidates" / f"isr{index:02d}" / f"c01-frame-{int(spec['frame']):04d}.png"
        candidate, components = save_candidate(
            source_path,
            candidate_path,
            str(spec["candidateId"]),
            int(spec["frame"]),
            component_only=spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY,
        )
        final_sanity = candidate_visual_sanity(
            require_object(candidate["artifact"], "re-exported candidate artifact"),
            f"重导主体 {spec['item']['reviewKey']} / {spec['candidateId']}",
        )
        if final_sanity["uniformSolidRectangle"] is True:
            raise SubjectLocalizationError(
                f"重导主体触发客观非主体门：{spec['item']['reviewKey']} / {spec['candidateId']}"
            )
        candidate["subjectSanity"] = final_sanity
        if isinstance(spec.get("preflightSubjectSanity"), dict):
            candidate["preflightSubjectSanity"] = copy.deepcopy(spec["preflightSubjectSanity"])
        candidate.update(
            {
                "humanSubjectSource": "verified_graphic_directive"
                if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY
                else "verified_internal_subject_review",
                "humanDecisionNote": str(spec["decision"].get("note", "")),
            }
        )
        if isinstance(spec.get("selectedRescueCandidate"), dict):
            rescue_candidate = require_object(spec["selectedRescueCandidate"], "selected rescue candidate")
            candidate["selectedRescueCandidate"] = {
                "candidateId": rescue_candidate["candidateId"],
                "spriteId": rescue_candidate["spriteId"],
                "frame": rescue_candidate["frame"],
                "artifact": copy.deepcopy(rescue_candidate["artifact"]),
                "sourceFrameArtifact": copy.deepcopy(rescue_candidate["sourceFrameArtifact"]),
            }
        if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY:
            graphic_components = components
        entity_code = f"isr{index:02d}"
        entity = {
            "entityCode": entity_code,
            "portraitRef": spec["item"]["portraitRef"],
            "category": "unclassified",
            "sourceClassification": "unique",
            "sourceResolution": "verified_human_internal_subject",
            "sourceSwf": spec["sourceSwf"],
            "characterId": spec["item"]["rootCharacterId"],
            "declaredFrameCount": spec["item"]["rootDeclaredFrameCount"],
            "renderCharacterId": spec["characterId"],
            "renderDeclaredFrameCount": (
                spec["item"]["rootDeclaredFrameCount"]
                if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY
                else require_object(spec["selectedRescueCandidate"], "selected candidate")["spriteFrameCount"]
            ),
            "renderStrategy": "verified_root_graphic_shape_crop"
            if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY
            else "verified_human_internal_sprite_frame",
            "renderStrategyWarning": None,
            "vectorSourceStrategy": "ffdec_root_sprite_svg_exact_graphic_frame"
            if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY
            else "ffdec_sprite_svg_human_selected_internal_frame",
            "candidates": [candidate],
            "exportedFrameCount": 1,
            "usableUniqueFrameCount": 1,
            "selectedSource": {
                "swf": spec["sourceSwf"],
                "symbolName": spec["item"].get("symbolName"),
                "orphan": False,
            },
            "variantResolution": "human_locked_default",
            "notes": "人类已锁定完整异形蛋 Graphic；本阶段只做构图定位。"
            if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY
            else "人类已锁定内部主体 sprite/frame；本阶段只做构图定位。",
        }
        item = {
            "reviewCode": f"ISR-{index:02d}",
            "reviewKey": spec["item"]["reviewKey"],
            "portraitRef": spec["item"]["portraitRef"],
            "variantKey": "default",
            "variantResolution": "human_locked_default",
            "entityCode": entity_code,
            "category": "unclassified",
            "sourceClassification": "unique",
            "sourceResolution": "verified_human_internal_subject",
            "oldReference": None,
            "blocked": False,
            "blockReason": None,
            "candidates": [candidate],
            "humanFeedback": {
                "source": "verified_human_graphic_subject_directive"
                if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY
                else "verified_human_internal_subject_review",
                "decisionReviewDigest": decisions["reviewDigest"],
                "selectedCandidateId": spec["candidateId"],
                "selectedCharacterId": spec["characterId"],
                "selectedFrame": spec["frame"],
                "humanNote": spec["decision"].get("note", ""),
                "instruction": (
                    "将完整卵体作为不可拆分的身份主体：保留顶端斑块、中央胚体纹理、蛋壳轮廓和底部有机基座；"
                    "不要把血条、等级、名称或孵化特效纳入头像。"
                    if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY
                    else "主体与帧已由人类确认；不得换帧或换内部元件。只推理最能确保 80px 可识别度的特征特写。"
                ),
            },
            "intentPolicy": {
                "defaultMode": "full_subject" if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY else "feature_closeup",
                "reasoningHint": (
                    "这是方向弱、整体轮廓即身份的非人单位。以完整蛋体和底座为 feature_group/full_subject，保持安全边距；"
                    "不允许把局部纹理放大到失去蛋形。"
                    if spec["item"]["reviewKey"] == ALIEN_REVIEW_KEY
                    else "先从锁定主体判断人形或非人：人形优先完整头脸特写；头弱时才受控让渡到武器结构或身体特质。"
                    "最强视觉重点留在甜区和安全范围内，弱组件允许顶边/侧边裁切。"
                ),
                "constraintSource": "verified_human_internal_subject_selection",
            },
        }
        entities.append(entity)
        prepared_items.append(item)

    ffdec, svg_runs, swf_evidence = core.export_vector_candidate_sources(
        output,
        entities,
        prepared_items,
        {"sourceEnvelope": {"sourceSwfs": source_records}},
    )
    for entity in entities:
        entity["vectorSourceStrategy"] = (
            "ffdec_root_sprite_svg_exact_graphic_frame_with_verified_shape_identity"
            if entity["portraitRef"] == ALIEN_PORTRAIT_REF
            else "ffdec_sprite_svg_human_selected_internal_frame"
        )
    graphic_match = validate_graphic_component(
        require_object(require_list(prepared_items[0]["candidates"], "alien candidates")[0], "alien candidate"),
        graphic_components,
        graphic_shape,
    )

    combined_sheet = draw_contact_sheet(prepared_items, output / "internal-subject-locked-contact-sheet.png", batch_id)
    model_batches: list[dict[str, object]] = []
    contact_bindings: list[dict[str, object]] = []
    for start in range(0, len(prepared_items), 4):
        batch_items = prepared_items[start : start + 4]
        model_batch_id = f"internal-subject-localization-{start // 4 + 1:02d}"
        sheet = draw_contact_sheet(
            batch_items,
            output / "model-sheets" / f"{model_batch_id}.png",
            f"{batch_id} · {model_batch_id} · human subject locked",
        )
        model_batches.append(
            {
                "modelBatchId": model_batch_id,
                "reviewKeys": [str(item["reviewKey"]) for item in batch_items],
                "contactSheet": sheet,
            }
        )
        contact_bindings.append(
            {
                "modelBatchId": model_batch_id,
                "base": copy.deepcopy(sheet),
                "composite": copy.deepcopy(sheet),
                "purpose": "preflight_only_localization_views_replace_model_images",
            }
        )

    directive: dict[str, object] = {
        "schema": DIRECTIVE_SCHEMA,
        "status": "verified_human_graphic_subject_directive",
        "productionReady": False,
        "generatedAt": utc_now(),
        "reviewKey": ALIEN_REVIEW_KEY,
        "humanDecision": core.artifact(inputs["paths"]["decisions"]),
        "humanReviewDigest": decisions["reviewDigest"],
        "humanNote": unique_row(decision_rows, "reviewKey", ALIEN_REVIEW_KEY, "human decisions")["note"],
        "xfl": xfl_mapping,
        "swf": swf_mapping,
        "compiledShape": graphic_shape,
        "rootFrameIsolation": graphic_match,
        "candidate": copy.deepcopy(prepared_items[0]["candidates"][0]),
        "controller": core.artifact(Path(__file__).resolve()),
        "gates": {
            "maintainerNamedLibraryItem": True,
            "singleFrameGraphic": True,
            "singleVectorShape": True,
            "xflRootFramePlacementUnique": True,
            "xflSwfTwipMatrixMatches": True,
            "compiledShapeIdentityMatches": True,
            "largestConnectedRootComponentMatchesShape": True,
            "outerUiExcludedByVerifiedCrop": True,
            "genericShapeGuessingAuthorized": False,
            "graphicUsedOnlyAfterMovieClipSearchFailed": True,
            "rootFrameUsedAsIdentityReferenceOnly": True,
            "productionWrites": False,
        },
    }
    directive["directiveDigest"] = stable_digest(directive)
    directive_path = output / "graphic-subject-directive.json"
    core.write_json(directive_path, directive)

    calibration = copy.deepcopy(parent_manifest.get("humanPreferenceCalibration"))
    if isinstance(calibration, dict):
        calibration["contactSheets"] = contact_bindings
    feature_contract = copy.deepcopy(require_object(parent_manifest.get("featureContract"), "featureContract"))
    global_rules = [str(rule) for rule in require_list(feature_contract.get("global"), "featureContract.global")]
    global_rules = [
        (
            "候选主体和帧已经由真人逐项锁定；包括一个经 XFL/SWF 双重验证的 Graphic。"
            "不得换主体、换帧或把外层血条、等级、名称当作身份特征。"
            if "候选像素已经由管线限定为怪物内部首帧命名 man" in rule
            else rule
        )
        for rule in global_rules
    ]
    global_rules.append("本阶段只输出锁定候选中的 feature/must-include 几何与朝向；人工主体选择优先于模型。")
    global_rules.append("纯色实心矩形等客观非主体会在昂贵定位前失败关闭；该门不评价艺术质量，也不替代真人主体裁决。")
    feature_contract["global"] = global_rules

    input_records = {
        "rescueManifest": core.artifact(inputs["paths"]["manifest"]),
        "rescueModelReport": core.artifact(inputs["paths"]["model"]),
        "rescueReviewData": core.artifact(inputs["paths"]["review"]),
        "humanDecisions": core.artifact(inputs["paths"]["decisions"]),
        "preferenceParentManifest": core.artifact(parent_manifest_path),
        "graphicDirective": core.artifact(directive_path),
        "controller": core.artifact(Path(__file__).resolve()),
    }
    parent_envelope = require_object(parent_manifest.get("sourceEnvelope"), "parent sourceEnvelope")
    source_files = [copy.deepcopy(record) for record in require_list(parent_envelope.get("sourceFiles"), "parent sourceFiles") if isinstance(record, dict)]
    source_files.extend(copy.deepcopy(list(input_records.values())))
    source_envelope: dict[str, object] = {
        "batchId": batch_id,
        "mode": "verified_human_internal_subject_localization_v1",
        "ffdec": ffdec,
        "profile": copy.deepcopy(parent_envelope.get("profile")),
        "font": copy.deepcopy(parent_envelope.get("font")),
        "pillowVersion": copy.deepcopy(parent_envelope.get("pillowVersion")),
        "sourceFiles": dedupe_artifacts(source_files),
        "sourceSwfs": source_records,
        "humanPreferenceCalibration": calibration,
        "humanInternalSubjectSelection": {
            **input_records,
            "decisionReviewDigest": decisions["reviewDigest"],
            "selectedInternalSpriteRows": EXPECTED_ROWS - 1,
            "verifiedGraphicRows": 1,
            "oldModelGeometryConsumed": False,
            "productionWrites": False,
        },
    }
    source_digest = stable_digest(source_envelope)

    campaign = {
        "selectedPortraitRefs": [str(item["portraitRef"]) for item in prepared_items],
        "selectedSourceCounts": {
            source: sum(1 for entity in entities if entity["sourceSwf"] == source)
            for source in sorted({str(entity["sourceSwf"]) for entity in entities})
        },
        "shardSize": len(prepared_items),
        "sourceGroups": len(source_records),
        "identitiesPerSourceGroup": 4,
        "expectedModelJobs": len(model_batches) * 2,
        "selectionStrategy": "verified_human_internal_subject_then_localization_only",
        "serviceTierRecommendation": "fast",
        "selectionMaximumConcurrency": 6,
        "localizationMaximumConcurrency": 3,
        "timeoutSeconds": 600,
    }
    manifest: dict[str, object] = {
        "schema": MANIFEST_SCHEMA,
        "phase": "P3_FEATURE_REFINEMENT",
        "status": "human_internal_subjects_locked_localization_ready",
        "productionReady": False,
        "batchId": batch_id,
        "createdAt": utc_now(),
        "campaign": campaign,
        "contactSheet": combined_sheet,
        "counts": {
            "entityCount": len(entities),
            "candidateCount": len(prepared_items),
            "reviewUnitCount": len(prepared_items),
            "eligibleReviewUnitCount": len(prepared_items),
            "blockedReviewUnitCount": 0,
        },
        "entities": entities,
        "featureContract": feature_contract,
        "ffdecRuns": export_runs + svg_runs + require_list(graphic_shape["runs"], "shape runs"),
        "gates": {
            "verifiedHumanInternalSubjectSelections": True,
            "verifiedHumanGraphicDirective": True,
            "selectedSubjectPixelsReexportedAtZoom2": True,
            "oldModelGeometryDiscarded": True,
            "localizationOnly": True,
            "humanTargetGeometryExcluded": True,
            "obviousNonSubjectRasterRejected": True,
            "graphicFallbackRequiresRootPlacementTrace": True,
            "productionWrites": False,
        },
        "humanPreferenceCalibration": calibration,
        "modelBatches": model_batches,
        "reviewItems": prepared_items,
        "sourceEnvelope": source_envelope,
        "sourceDigest": source_digest,
    }
    manifest["manifestDigest"] = stable_digest(manifest)
    manifest_path = output / "candidate-manifest.json"
    core.write_json(manifest_path, manifest)

    lock_rows: list[dict[str, object]] = []
    for item, spec in zip(prepared_items, selected_specs):
        candidate = require_object(require_list(item["candidates"], "lock candidates")[0], "lock candidate")
        lock_rows.append(
            {
                "reviewCode": item["reviewCode"],
                "reviewKey": item["reviewKey"],
                "candidateAgreement": (
                    require_object(require_object(unique_row(inputs["review"]["items"], "reviewKey", item["reviewKey"], "review items")["model"], "model")["comparison"], "comparison").get("candidateAgreement") is True
                    if item["reviewKey"] != ALIEN_REVIEW_KEY
                    else False
                ),
                "lockedRole": "verified_human_graphic_subject_directive"
                if item["reviewKey"] == ALIEN_REVIEW_KEY
                else "verified_human_internal_subject_review",
                "candidateId": candidate["candidateId"],
                "candidateArtifact": copy.deepcopy(candidate["artifact"]),
                "arbitrationReason": "maintainer_named_graphic_symbol_7"
                if item["reviewKey"] == ALIEN_REVIEW_KEY
                else "explicit_human_candidate_selection",
                "humanDecision": {
                    "decision": spec["decision"]["decision"],
                    "candidateId": spec["decision"].get("candidateId"),
                    "note": spec["decision"].get("note", ""),
                },
            }
        )
    lock: dict[str, object] = {
        "schema": LOCK_SCHEMA,
        "status": "human_subject_selection_locked",
        "productionReady": False,
        "generatedAt": utc_now(),
        "input": {
            "manifest": core.artifact(manifest_path),
            "manifestDigest": manifest["manifestDigest"],
            "sourceDigest": manifest["sourceDigest"],
            "modelReport": core.artifact(inputs["paths"]["model"]),
            "modelReportDigest": inputs["model"]["reportDigest"],
            "humanDecisions": core.artifact(inputs["paths"]["decisions"]),
            "humanReviewDigest": decisions["reviewDigest"],
            "graphicDirective": core.artifact(directive_path),
            "graphicDirectiveDigest": directive["directiveDigest"],
        },
        "arbitrationPolicy": {
            "authority": "verified_human_internal_subject_review",
            "modelSelectionMayOverrideHuman": False,
            "candidatePixelsChanged": False,
            "featureGeometryAccepted": False,
            "humanTargetGeometryUsed": False,
        },
        "controller": core.artifact(Path(__file__).resolve()),
        "rows": lock_rows,
        "counts": {
            "rows": len(lock_rows),
            "humanInternalSpriteLocks": len(lock_rows) - 1,
            "humanGraphicDirectiveLocks": 1,
            "candidateAgreements": sum(1 for row in lock_rows if row["candidateAgreement"]),
        },
        "gates": {
            "exactCandidateHashBinding": True,
            "humanAuthorityBound": True,
            "localizationRequired": True,
            "humanTargetGeometryExcluded": True,
            "obviousNonSubjectRasterRejected": True,
            "productionWrites": False,
        },
    }
    lock["selectionDigest"] = stable_digest(lock)
    core.write_json(output / "selection-lock.json", lock)
    return check(argparse.Namespace(output=core.repo_rel(output)))


def check(args: argparse.Namespace) -> dict[str, object]:
    output = pilot_child(args.output, "内部主体定位输出", must_exist=True)
    manifest_path = output / "candidate-manifest.json"
    lock_path = output / "selection-lock.json"
    directive_path = output / "graphic-subject-directive.json"
    manifest = require_object(core.load_json(manifest_path), "candidate manifest")
    lock = require_object(core.load_json(lock_path), "selection lock")
    directive = require_object(core.load_json(directive_path), "graphic directive")
    core.verify_digest_object(manifest, "manifestDigest", "candidate manifest")
    core.verify_digest_object(lock, "selectionDigest", "selection lock")
    core.verify_digest_object(directive, "directiveDigest", "graphic directive")
    if stable_digest(require_object(manifest.get("sourceEnvelope"), "sourceEnvelope")) != manifest.get("sourceDigest"):
        raise SubjectLocalizationError("candidate manifest sourceDigest 不匹配")
    if manifest.get("schema") != MANIFEST_SCHEMA or lock.get("schema") != LOCK_SCHEMA:
        raise SubjectLocalizationError("candidate manifest/selection lock schema 漂移")
    if directive.get("schema") != DIRECTIVE_SCHEMA or directive.get("status") != "verified_human_graphic_subject_directive":
        raise SubjectLocalizationError("graphic directive schema/status 漂移")
    if manifest.get("productionReady") is not False or lock.get("productionReady") is not False:
        raise SubjectLocalizationError("内部主体定位输出不得获得生产权限")
    for record in (
        manifest.get("contactSheet"),
        lock.get("input", {}).get("manifest"),
        lock.get("input", {}).get("modelReport"),
        lock.get("input", {}).get("humanDecisions"),
        lock.get("input", {}).get("graphicDirective"),
        lock.get("controller"),
        directive.get("humanDecision"),
        directive.get("controller"),
    ):
        core.verify_artifact_record(require_object(record, "bound artifact"), "bound artifact")
    for entry_label in ("rootEntry", "graphicEntry"):
        entry = require_object(require_object(directive["xfl"], "directive xfl")[entry_label], entry_label)
        core.verify_artifact_record(require_object(entry["archive"], "entry archive"), "entry archive")
    for record in require_list(require_object(directive["compiledShape"], "compiled shape")["runs"], "shape runs"):
        for field in ("stdout", "stderr", "commandRecord"):
            core.verify_artifact_record(require_object(record[field], f"shape run {field}"), f"shape run {field}")
    for field in ("png", "svg"):
        core.verify_artifact_record(require_object(require_object(directive["compiledShape"], "compiled shape")[field], field), field)

    items = require_list(manifest.get("reviewItems"), "manifest reviewItems")
    entities = require_list(manifest.get("entities"), "manifest entities")
    rows = require_list(lock.get("rows"), "selection lock rows")
    if len(items) != EXPECTED_ROWS or len(entities) != EXPECTED_ROWS or len(rows) != EXPECTED_ROWS:
        raise SubjectLocalizationError("manifest/lock 17 行闭包漂移")
    item_keys = {str(item["reviewKey"]) for item in items if isinstance(item, dict)}
    row_keys = {str(row["reviewKey"]) for row in rows if isinstance(row, dict)}
    if len(item_keys) != EXPECTED_ROWS or item_keys != row_keys:
        raise SubjectLocalizationError("manifest/lock reviewKey 不闭合")
    for item_raw in items:
        item = require_object(item_raw, "manifest item")
        candidates = require_list(item.get("candidates"), "manifest candidates")
        if len(candidates) != 1:
            raise SubjectLocalizationError(f"人类锁定定位行必须恰有一个候选：{item.get('reviewKey')}")
        candidate = require_object(candidates[0], "manifest candidate")
        for field in ("artifact", "sourceFrameArtifact", "vectorArtifact"):
            core.verify_artifact_record(require_object(candidate[field], f"candidate {field}"), f"candidate {field}")
        current_sanity = candidate_visual_sanity(
            require_object(candidate["artifact"], "candidate artifact"),
            f"已锁定主体 {item.get('reviewKey')}",
        )
        if current_sanity != candidate.get("subjectSanity") or current_sanity["uniformSolidRectangle"] is not False:
            raise SubjectLocalizationError(f"主体客观语义门漂移：{item.get('reviewKey')}")
        row = unique_row(rows, "reviewKey", item["reviewKey"], "selection rows")
        if row.get("candidateId") != candidate.get("candidateId") or row.get("candidateArtifact") != candidate.get("artifact"):
            raise SubjectLocalizationError(f"selection lock 候选漂移：{item.get('reviewKey')}")
    model_batches = require_list(manifest.get("modelBatches"), "model batches")
    if len(model_batches) != math.ceil(EXPECTED_ROWS / 4):
        raise SubjectLocalizationError("model batch 数量不闭合")
    batched: list[str] = []
    for batch in model_batches:
        batch = require_object(batch, "model batch")
        keys = [str(value) for value in require_list(batch.get("reviewKeys"), "batch reviewKeys")]
        if not 1 <= len(keys) <= 4:
            raise SubjectLocalizationError("model batch 必须为 1–4 行")
        batched.extend(keys)
        core.verify_artifact_record(require_object(batch["contactSheet"], "batch contact sheet"), "batch contact sheet")
    if sorted(batched) != sorted(item_keys) or len(batched) != EXPECTED_ROWS:
        raise SubjectLocalizationError("model batch 没有精确覆盖全部 reviewKey")
    calibration = require_object(manifest.get("humanPreferenceCalibration"), "human preference calibration")
    if len(require_list(calibration.get("contactSheets"), "calibration contactSheets")) != len(model_batches):
        raise SubjectLocalizationError("humanPreferenceCalibration contactSheets 未重绑当前模型批")
    for field in ("atlas", "modelAtlas"):
        record = calibration.get(field)
        if isinstance(record, dict):
            core.verify_artifact_record(record, f"calibration {field}")

    xfl_now = graphic_xfl_mapping()
    swf_xml = core.verify_artifact_record(require_object(require_object(directive["swf"], "directive swf")["ffdecXml"], "directive ffdec xml"), "directive ffdec xml")
    swf_now = graphic_swf_mapping(swf_xml, xfl_now)
    if xfl_now != directive.get("xfl") or swf_now != directive.get("swf"):
        raise SubjectLocalizationError("Graphic XFL/SWF 映射不可由当前来源重放")
    if directive.get("gates", {}).get("genericShapeGuessingAuthorized") is not False:
        raise SubjectLocalizationError("Graphic 指令意外授权了通用 Shape 猜测")
    if (
        directive.get("gates", {}).get("graphicUsedOnlyAfterMovieClipSearchFailed") is not True
        or directive.get("gates", {}).get("rootFrameUsedAsIdentityReferenceOnly") is not True
        or manifest.get("gates", {}).get("obviousNonSubjectRasterRejected") is not True
        or manifest.get("gates", {}).get("graphicFallbackRequiresRootPlacementTrace") is not True
        or lock.get("gates", {}).get("obviousNonSubjectRasterRejected") is not True
    ):
        raise SubjectLocalizationError("内部 MovieClip → Graphic fallback 或客观非主体门漂移")
    return {
        "status": "human_internal_subject_localization_batch_verified",
        "manifestDigest": manifest["manifestDigest"],
        "selectionDigest": lock["selectionDigest"],
        "directiveDigest": directive["directiveDigest"],
        "counts": manifest["counts"],
        "modelBatches": len(model_batches),
        "productionWrites": False,
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--rescue-batch", required=True)
    render_parser.add_argument("--preference-manifest", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    return result


def main() -> None:
    args = parser().parse_args()
    report = build(args) if args.command == "render" else check(args)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, core.PilotError, KeyError, TypeError, ValueError, ET.ParseError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
