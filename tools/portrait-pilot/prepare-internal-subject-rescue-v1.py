#!/usr/bin/env python3
"""Prepare reviewable internal-sprite candidates for roots that omitted `man`.

Structural complexity is deliberately only a recall prior.  The generated
manifest keeps every chosen sprite's exact SWF/XML path, preview frame and SVG
frame so a multimodal model and, finally, a human can decide whether it is the
actual monster subject.  This script never promotes production portraits.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageOps

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
UNITS_PATH = ROOT / "data" / "units" / "units.json"
MANIFEST_PATH = ROOT / "launcher" / "web" / "assets" / "enemy-portraits" / "manifest.json"
SCHEMA = "cf7.enemy-portrait-internal-subject-rescue-candidates.v1"
PHASE = "P4_INTERNAL_SUBJECT_RESCUE"
SAMPLE_EXPORTER_PATH = ROOT / "tools" / "portrait-pilot" / "SelectedSpriteSampleExporter.java"
EXPECTED_TARGET_COUNT = 17
MAX_CANDIDATES = 8
MAX_DISCOVERY_DEPTH = 3
SAMPLE_ZOOM = 0.5
MAX_SAMPLE_PIXELS = 64_000_000
HARD_UI_RE = re.compile(
    r"(?:^|[/\\._ -])(area|hitbox|hp|health|name|level|lv|bar)(?:$|[/\\._ -])|"
    r"人物文字信息|控制块|血条|等级|称号|名字|索敌框|碰撞框|按钮框",
    re.IGNORECASE,
)
SOFT_EFFECT_RE = re.compile(
    r"特效|光效|枪口|子弹|弹道|轨迹|烟|火焰|爆炸|effect|bullet|weapon|shadow|影子",
    re.IGNORECASE,
)


class RescueError(core.PilotError):
    pass


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def stable_digest(value: object) -> str:
    return core.sha256_bytes(core.stable_bytes(value))


def accepted_variant(entry: dict[str, object] | None) -> bool:
    if not isinstance(entry, dict):
        return False
    variants = entry.get("variants")
    default_key = entry.get("defaultVariant")
    if not isinstance(variants, dict) or not isinstance(default_key, str):
        return False
    variant = variants.get(default_key)
    return isinstance(variant, dict) and variant.get("status") == "human_accepted" and bool(variant.get("subject"))


def derive_targets(
    explicit_refs: list[str] | None = None,
) -> tuple[list[dict[str, object]], dict[str, object], dict[str, object]]:
    units = core.load_json(UNITS_PATH)
    production = core.load_json(MANIFEST_PATH)
    assets = core.parse_asset_map()
    if not isinstance(units, list) or not isinstance(production, dict):
        raise RescueError("Arena 单位目录或生产头像 manifest 非法")
    ordered_refs: list[str] = []
    seen: set[str] = set()
    for unit in units:
        ref = str(unit.get("spritename", "")).strip() if isinstance(unit, dict) else ""
        if ref and ref not in seen:
            seen.add(ref)
            ordered_refs.append(ref)

    explicit_refs = [value.strip() for value in (explicit_refs or []) if value.strip()]
    if len(explicit_refs) != len(set(explicit_refs)):
        raise RescueError("显式 rescue 目标不得重复")
    explicit_set = set(explicit_refs)
    targets: list[dict[str, object]] = []
    for ref in ordered_refs:
        if explicit_set and ref not in explicit_set:
            continue
        entry = production.get("entries", {}).get(ref)
        if explicit_set:
            if accepted_variant(entry):
                raise RescueError(f"显式 rescue 目标已有生产头像：{ref}")
        elif accepted_variant(entry) or not isinstance(entry, dict) or entry.get("status") != "pending_human_review":
            continue
        asset = assets.get(ref)
        if not isinstance(asset, dict) or asset.get("classification") != "unique":
            continue
        sources = asset.get("sources")
        if not isinstance(sources, list) or len(sources) != 1 or not isinstance(sources[0], dict):
            raise RescueError(f"rescue 目标来源不唯一：{ref}")
        source = sources[0]
        if source.get("orphan") is True or not isinstance(source.get("swf"), str):
            raise RescueError(f"rescue 目标来源不可用：{ref}")
        targets.append(
            {
                "portraitRef": ref,
                "reviewKey": f"{ref}::default",
                "sourceSwf": source["swf"],
                "symbolName": source.get("symbolName"),
            }
        )
    expected_count = len(explicit_refs) if explicit_refs else EXPECTED_TARGET_COUNT
    if explicit_set and {row["portraitRef"] for row in targets} != explicit_set:
        missing = sorted(explicit_set - {str(row["portraitRef"]) for row in targets})
        raise RescueError(f"显式 rescue 目标无法闭合为 Arena 唯一来源：{missing}")
    if len(targets) != expected_count:
        raise RescueError(
            f"当前 Arena 唯一来源 rescue 集合已漂移：{len(targets)} != {expected_count}；"
            "必须复核分类后再升级脚本版本"
        )
    return targets, production, assets


def definition_maps(xml_path: Path) -> tuple[dict[int, ET.Element], dict[int, ET.Element], dict[int, str]]:
    parsed = ET.parse(xml_path).getroot()
    sprites: dict[int, ET.Element] = {}
    shapes: dict[int, ET.Element] = {}
    types: dict[int, str] = {}
    for node in parsed.iter("item"):
        kind = node.attrib.get("type", "")
        if kind == "DefineSpriteTag" and node.attrib.get("spriteId"):
            identifier = int(node.attrib["spriteId"])
            sprites[identifier] = node
            types[identifier] = kind
        elif kind.startswith("DefineShape") and node.attrib.get("shapeId"):
            identifier = int(node.attrib["shapeId"])
            shapes[identifier] = node
            types[identifier] = kind
        else:
            for attribute in ("characterID", "characterId", "fontId", "soundId", "textId", "buttonId", "bitmapId"):
                raw = node.attrib.get(attribute)
                if raw and raw.isdigit() and int(raw) > 0 and int(raw) not in types and kind.startswith("Define"):
                    types[int(raw)] = kind
                    break
    return sprites, shapes, types


def placed_character_id(node: ET.Element) -> int | None:
    if not node.attrib.get("type", "").startswith("PlaceObject"):
        return None
    raw = node.attrib.get("characterId")
    if not raw:
        return None
    value = int(raw)
    return value if value > 0 else None


def timeline_placements(sprite: ET.Element) -> list[dict[str, object]]:
    sub_tags = sprite.find("subTags")
    if sub_tags is None:
        return []
    rows: list[dict[str, object]] = []
    frame_number = 1
    for tag in sub_tags.findall("item"):
        if tag.attrib.get("type") == "ShowFrameTag":
            frame_number += 1
            continue
        character_id = placed_character_id(tag)
        if character_id is None:
            continue
        rows.append(
            {
                "characterId": character_id,
                "firstSeenFrame": frame_number,
                "depth": int(tag.attrib.get("depth", "0")),
                "instanceName": tag.attrib.get("name"),
                "tagType": tag.attrib.get("type"),
            }
        )
    return rows


def structural_metrics(
    candidate_id: int,
    sprites: dict[int, ET.Element],
    shapes: dict[int, ET.Element],
    types: dict[int, str],
) -> dict[str, object]:
    visited_sprites: set[int] = set()
    visited_shapes: set[int] = set()
    leaf_ids: set[int] = set()
    placement_count = 0
    declared_frames = 0
    maximum_depth = 0

    def visit(sprite_id: int, depth: int) -> None:
        nonlocal placement_count, declared_frames, maximum_depth
        if sprite_id in visited_sprites or sprite_id not in sprites:
            return
        visited_sprites.add(sprite_id)
        maximum_depth = max(maximum_depth, depth)
        sprite = sprites[sprite_id]
        declared_frames += int(sprite.attrib.get("frameCount", "0"))
        sub_tags = sprite.find("subTags")
        if sub_tags is None:
            return
        for tag in sub_tags.findall("item"):
            child_id = placed_character_id(tag)
            if child_id is None:
                continue
            placement_count += 1
            if child_id in sprites:
                visit(child_id, depth + 1)
            elif child_id in shapes:
                visited_shapes.add(child_id)
            else:
                leaf_ids.add(child_id)

    visit(candidate_id, 0)
    edge_records = 0
    for shape_id in visited_shapes:
        edge_records += sum(
            1
            for item in shapes[shape_id].iter("item")
            if item.attrib.get("type") in {"StraightEdgeRecord", "CurvedEdgeRecord"}
        )
    complexity = (
        40 * math.log1p(edge_records)
        + 25 * math.log1p(len(visited_shapes))
        + 18 * math.log1p(len(visited_sprites))
        + 12 * math.log1p(placement_count)
        + 5 * math.log1p(len(leaf_ids))
        + min(declared_frames, 240) * 0.35
    )
    return {
        "complexityScore": round(complexity, 6),
        "spriteFrameCount": int(sprites[candidate_id].attrib.get("frameCount", "0")),
        "reachableSpriteCount": len(visited_sprites),
        "reachableShapeCount": len(visited_shapes),
        "reachableLeafCount": len(leaf_ids),
        "edgeRecordCount": edge_records,
        "timelinePlacementCount": placement_count,
        "declaredFrameCountSum": declared_frames,
        "maximumDescendantDepth": maximum_depth,
        "definitionType": types.get(candidate_id, "DefineSpriteTag"),
    }


def discover_candidates(
    root_id: int,
    sprites: dict[int, ET.Element],
    shapes: dict[int, ET.Element],
    types: dict[int, str],
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    root = sprites.get(root_id)
    if root is None:
        raise RescueError(f"root 不是 DefineSprite：{root_id}")
    found: dict[int, dict[str, object]] = {}

    def visit(parent_id: int, path: list[dict[str, object]], depth: int, ancestors: set[int]) -> None:
        if depth > MAX_DISCOVERY_DEPTH or parent_id not in sprites:
            return
        for placement in timeline_placements(sprites[parent_id]):
            child_id = int(placement["characterId"])
            if child_id not in sprites or child_id == root_id:
                continue
            child_path = [*path, placement]
            names = [str(row.get("instanceName") or "") for row in child_path]
            path_text = "/".join(name for name in names if name)
            hard_ui = bool(HARD_UI_RE.search(path_text))
            soft_effect = bool(SOFT_EFFECT_RE.search(path_text))
            initial_root_frame = (
                depth == 1
                and bool(child_path)
                and int(child_path[0].get("firstSeenFrame", 0)) == 1
            )
            row = {
                "spriteId": child_id,
                "rootDepth": depth,
                "initialRootFrameCandidate": initial_root_frame,
                "displayPath": child_path,
                "displayPathText": path_text,
                "hardUiExcluded": hard_ui,
                "softEffectHint": soft_effect,
                **structural_metrics(child_id, sprites, shapes, types),
            }
            row["rankingScore"] = round(
                float(row["complexityScore"])
                + (36 if depth == 1 else 0)
                + (32 if initial_root_frame else 0)
                - (depth - 1) * 12
                - (28 if soft_effect else 0)
                - (400 if hard_ui else 0),
                6,
            )
            prior = found.get(child_id)
            if prior is None or (hard_ui, depth, -float(row["rankingScore"])) < (
                bool(prior["hardUiExcluded"]),
                int(prior["rootDepth"]),
                -float(prior["rankingScore"]),
            ):
                found[child_id] = row
            if depth < MAX_DISCOVERY_DEPTH and child_id not in ancestors:
                visit(child_id, child_path, depth + 1, {*ancestors, child_id})

    visit(root_id, [], 1, {root_id})
    eligible = sorted(
        (row for row in found.values() if not row["hardUiExcluded"]),
        key=lambda row: (-float(row["rankingScore"]), int(row["rootDepth"]), int(row["spriteId"])),
    )
    excluded = sorted(
        (row for row in found.values() if row["hardUiExcluded"]),
        key=lambda row: (int(row["rootDepth"]), int(row["spriteId"])),
    )
    if not eligible:
        return [], excluded

    third = max(1, math.ceil(len(eligible) / 3))
    for index, row in enumerate(eligible):
        row["complexityRank"] = index + 1
        row["complexityTier"] = "high" if index < third else "medium" if index < 2 * third else "low"

    selected: list[dict[str, object]] = []
    selected_ids: set[int] = set()

    def add(row: dict[str, object]) -> None:
        sprite_id = int(row["spriteId"])
        if sprite_id not in selected_ids and len(selected) < MAX_CANDIDATES:
            selected.append(row)
            selected_ids.add(sprite_id)

    for row in eligible:
        if row["initialRootFrameCandidate"] and len(selected) < 4:
            add(row)
    for tier in ("high", "medium", "low"):
        tier_rows = [row for row in eligible if row["complexityTier"] == tier]
        if tier_rows:
            add(tier_rows[0])
    for tier in ("high", "medium", "low"):
        for row in eligible:
            if row["complexityTier"] == tier:
                add(row)
    selected.sort(key=lambda row: int(row["complexityRank"]))
    return selected, excluded


def sample_frames(frame_count: int, maximum: int = 5) -> list[int]:
    if frame_count < 1:
        raise RescueError(f"sprite frameCount 非法：{frame_count}")
    if frame_count <= maximum:
        return list(range(1, frame_count + 1))
    values: list[int] = []
    for slot in range(maximum):
        value = 1 + round(slot * (frame_count - 1) / (maximum - 1))
        if value not in values:
            values.append(value)
    return values


def compile_sample_exporter(output: Path) -> dict[str, object]:
    if not SAMPLE_EXPORTER_PATH.is_file():
        raise RescueError("SelectedSpriteSampleExporter.java 缺失")
    javac = core.find_java_tool("javac")
    java = core.find_java_tool("java")
    class_dir = output / "selected-sprite-sample-exporter-classes"
    if class_dir.exists():
        raise RescueError(f"sample exporter classes 已存在：{class_dir}")
    class_dir.mkdir(parents=True)
    classpath = os.pathsep.join(
        [str(ROOT / "tools" / "ffdec" / "lib" / "*"), str(ROOT / "tools" / "ffdec" / "ffdec.jar")]
    )
    compile_run = core.run_logged_tool(
        [
            str(javac), "-encoding", "UTF-8", "-cp", classpath, "-d", str(class_dir),
            str(SAMPLE_EXPORTER_PATH),
        ],
        output,
        "selected-sprite-sample-exporter-compile",
        120,
    )
    class_files = sorted(class_dir.glob("SelectedSpriteSampleExporter*.class"))
    if len(class_files) < 3:
        raise RescueError("SelectedSpriteSampleExporter 编译闭包不完整")
    runtime_classpath = os.pathsep.join([str(class_dir), classpath])
    return {
        "java": core.external_file_record(java),
        "javac": core.external_file_record(javac),
        "source": core.artifact(SAMPLE_EXPORTER_PATH),
        "classes": [core.artifact(path) for path in class_files],
        "classpathFiles": [
            core.artifact(ROOT / rel_path)
            for rel_path in core.FFDEC_CLOSURE
            if rel_path.endswith(".jar")
        ],
        "compileRun": compile_run,
        "runtimeClasspath": runtime_classpath,
    }


def export_sprite_samples(
    adapter: dict[str, object],
    output: Path,
    swf_path: Path,
    source_index: int,
    frame_specs: dict[int, list[int]],
) -> tuple[dict[str, object], dict[int, dict[int, dict[str, object]]]]:
    export_root = output / "selected-sprite-samples" / f"source-{source_index:03d}"
    if export_root.exists():
        raise RescueError(f"selected sprite samples 已存在：{export_root}")
    spec = ";".join(
        f"{sprite_id}:{','.join(str(frame) for frame in frames)}"
        for sprite_id, frames in sorted(frame_specs.items())
    )
    run = core.run_logged_tool(
        [
            str(adapter["java"]["path"]), "-cp", str(adapter["runtimeClasspath"]),
            "SelectedSpriteSampleExporter", str(swf_path), str(export_root), str(SAMPLE_ZOOM), spec,
        ],
        output,
        f"source-{source_index:03d}-selected-sprite-samples",
        900,
    )
    records: dict[int, dict[int, dict[str, object]]] = {}
    expected_files = 0
    for sprite_id, frames in sorted(frame_specs.items()):
        sprite_directories = [
            path
            for path in export_root.iterdir()
            if path.is_dir() and re.fullmatch(rf"DefineSprite_{sprite_id}(?:_.+)?", path.name)
        ]
        if len(sprite_directories) != 1:
            raise RescueError(
                f"selected sprite sample 目录不唯一：id={sprite_id} matches={len(sprite_directories)}"
            )
        sprite_directory = sprite_directories[0]
        frame_records: dict[int, dict[str, object]] = {}
        for frame in frames:
            path = sprite_directory / f"{frame}.png"
            if not path.is_file():
                raise RescueError(f"selected sprite sample 缺失：id={sprite_id} frame={frame}")
            frame_records[frame] = core.artifact(path)
            expected_files += 1
        records[sprite_id] = frame_records
    actual_files = [path for path in export_root.rglob("*") if path.is_file()]
    if len(actual_files) != expected_files:
        raise RescueError(
            f"selected sprite sample 输出不精确：expected={expected_files} actual={len(actual_files)}"
        )
    return {
        **run,
        "sourceSwf": core.artifact(swf_path),
        "zoom": SAMPLE_ZOOM,
        "frameSpecs": {str(key): value for key, value in sorted(frame_specs.items())},
        "outputs": [record for rows in records.values() for record in rows.values()],
    }, records


def representative_frame(
    sample_records: dict[int, dict[str, object]],
    output_path: Path,
) -> dict[str, object]:
    frames: list[tuple[int, int, tuple[int, int, int, int], Image.Image, dict[str, object]]] = []
    oversized: list[dict[str, object]] = []
    for frame_number, record in sorted(sample_records.items()):
        sample_path = ROOT / record["path"]
        with sample_path.open("rb") as stream:
            header = stream.read(24)
        if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
            raise RescueError(f"sample PNG header 非法：{sample_path}")
        width, height = struct.unpack(">II", header[16:24])
        if width * height > MAX_SAMPLE_PIXELS:
            oversized.append({"frame": frame_number, "width": width, "height": height, "pixels": width * height})
            continue
        with Image.open(sample_path) as image:
            rgba = image.convert("RGBA")
        alpha = rgba.getchannel("A")
        bbox = alpha.getbbox()
        if bbox is None or bbox[2] - bbox[0] < 8 or bbox[3] - bbox[1] < 8:
            continue
        visible_pixels = sum(alpha.histogram()[1:])
        frames.append((visible_pixels, frame_number, bbox, rgba, record))
    if not frames:
        detail = f" oversized={oversized}" if oversized else ""
        raise RescueError(f"内部 sprite 样本没有安全可见帧：{output_path.stem}{detail}")
    visible_pixels, frame_number, bbox, rgba, source_record = max(frames, key=lambda row: (row[0], -row[1]))
    crop_bounds = core.expanded_bbox(bbox, rgba.size)
    cropped = rgba.crop(crop_bounds)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cropped.save(output_path, format="PNG", optimize=False, compress_level=9)
    return {
        "frame": frame_number,
        "sourceSize": list(rgba.size),
        "alphaBounds": list(bbox),
        "sourceCropBounds": list(crop_bounds),
        "visiblePixelCount": visible_pixels,
        "width": cropped.width,
        "height": cropped.height,
        "artifact": core.artifact(output_path),
        "sourceFrameArtifact": source_record,
        "sampleFrameArtifacts": [sample_records[frame] for frame in sorted(sample_records)],
        "oversizedSamplesSkipped": oversized,
    }


def checker(size: tuple[int, int], cell: int = 14) -> Image.Image:
    image = Image.new("RGB", size, "#171d25")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2 == 0:
                draw.rectangle((x, y, min(size[0] - 1, x + cell - 1), min(size[1] - 1, y + cell - 1)), fill="#26303b")
    return image


def fit_candidate(canvas: Image.Image, source_path: Path, box: tuple[int, int, int, int]) -> None:
    left, top, right, bottom = box
    with Image.open(source_path) as source:
        rgba = source.convert("RGBA")
    fitted = ImageOps.contain(rgba, (right - left, bottom - top), Image.Resampling.LANCZOS)
    background = checker((right - left, bottom - top))
    background.paste(fitted, ((background.width - fitted.width) // 2, (background.height - fitted.height) // 2), fitted)
    canvas.paste(background, (left, top))


def draw_sheet(items: list[dict[str, object]], path: Path, title: str) -> None:
    font, _ = core.find_font()
    small = font
    label_width = 300
    cell_width = 205
    row_height = 245
    header_height = 48
    columns = max(len(item["candidates"]) for item in items)
    canvas = Image.new("RGB", (label_width + columns * cell_width, header_height + len(items) * row_height), "#0f141b")
    draw = ImageDraw.Draw(canvas)
    draw.text((14, 12), title, font=font, fill="#f3f6fa")
    for row_index, item in enumerate(items):
        top = header_height + row_index * row_height
        draw.rectangle((0, top, canvas.width - 1, top + row_height - 1), outline="#3b4654", width=1)
        draw.text((12, top + 16), str(item["reviewCode"]), font=font, fill="#5fe0d0")
        draw.text((12, top + 48), str(item["portraitRef"]), font=font, fill="#f3f6fa")
        draw.text((12, top + 82), f"root {item['rootCharacterId']} / no named man", font=small, fill="#aeb8c5")
        draw.text((12, top + 116), "complexity = recall only", font=small, fill="#ffbd66")
        for candidate_index, candidate in enumerate(item["candidates"]):
            left = label_width + candidate_index * cell_width
            fit_candidate(canvas, ROOT / candidate["artifact"]["path"], (left + 8, top + 42, left + cell_width - 8, top + 203))
            draw.text(
                (left + 8, top + 12),
                f"C{candidate_index + 1:02d} s{candidate['spriteId']} f{candidate['frame']}",
                font=small,
                fill="#f3f6fa",
            )
            draw.text(
                (left + 8, top + 211),
                f"rank {candidate['complexityRank']} {candidate['complexityTier']} d{candidate['rootDepth']}",
                font=small,
                fill="#9eabc0",
            )
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path, format="PNG", optimize=False, compress_level=9)


def build(args: argparse.Namespace) -> None:
    output = core.ensure_below(Path(args.output), PILOT_ROOT, "internal subject rescue 输出")
    if output.exists():
        raise RescueError(f"输出目录已存在，禁止覆盖：{output}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.batch_id or ""):
        raise RescueError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    output.mkdir(parents=True)
    targets, _, _ = derive_targets(args.target_ref)
    ffdec = core.verify_ffdec()
    sample_exporter = compile_sample_exporter(output)
    source_groups: dict[str, list[dict[str, object]]] = defaultdict(list)
    for target in targets:
        source_groups[str(target["sourceSwf"])].append(target)

    source_records: list[dict[str, object]] = []
    prepared: list[dict[str, object]] = []
    for source_index, (swf_rel, source_targets) in enumerate(sorted(source_groups.items()), start=1):
        swf_path = ROOT / swf_rel
        if not swf_path.is_file():
            raise RescueError(f"来源 SWF 缺失：{swf_rel}")
        xml_path = output / "ffdec-xml" / f"source-{source_index:03d}.xml"
        xml_path.parent.mkdir(parents=True, exist_ok=True)
        xml_run = core.run_ffdec(
            ["-onerror", "abort", "-swf2xml", str(swf_path), str(xml_path)],
            output,
            f"source-{source_index:03d}-xml",
        )
        exports = core.export_assets_from_xml(xml_path)
        sprites, shapes, types = definition_maps(xml_path)
        source_rows: list[dict[str, object]] = []
        selected_ids: set[int] = set()
        for target in source_targets:
            ref = str(target["portraitRef"])
            matches = exports.get(ref, [])
            if len(matches) != 1:
                raise RescueError(f"linkage root 不唯一：{ref} matches={matches}")
            root_id = int(matches[0])
            if root_id not in sprites:
                raise RescueError(f"linkage root 不是 DefineSprite：{ref} id={root_id}")
            man_id = core.first_frame_named_instance(xml_path, root_id, "man")
            if man_id is not None:
                raise RescueError(f"目标已出现命名 man，必须退出 rescue 路线：{ref} man={man_id}")
            discovered, excluded = discover_candidates(root_id, sprites, shapes, types)
            if not discovered:
                raise RescueError(f"没有可审阅内部影片剪辑候选：{ref} root={root_id}")
            selected_ids.update(int(row["spriteId"]) for row in discovered)
            source_rows.append(
                {
                    **target,
                    "sourceIndex": source_index,
                    "rootCharacterId": root_id,
                    "rootDeclaredFrameCount": int(sprites[root_id].attrib.get("frameCount", "0")),
                    "structuralCandidates": discovered,
                    "hardUiExcludedCandidates": excluded,
                }
            )

        frame_specs: dict[int, list[int]] = {}
        for row in source_rows:
            for structural in row["structuralCandidates"]:
                sprite_id = int(structural["spriteId"])
                frame_specs[sprite_id] = sample_frames(int(structural["spriteFrameCount"]))
        sample_run, sample_records = export_sprite_samples(
            sample_exporter,
            output,
            swf_path,
            source_index,
            frame_specs,
        )
        preview_by_sprite: dict[int, dict[str, object]] = {}
        preview_errors: dict[int, str] = {}
        for sprite_id in sorted(selected_ids):
            preview_path = output / "previews" / f"source-{source_index:03d}" / f"sprite-{sprite_id}.png"
            try:
                preview_by_sprite[sprite_id] = representative_frame(sample_records[sprite_id], preview_path)
            except RescueError as error:
                preview_errors[sprite_id] = str(error)

        for row in source_rows:
            candidates: list[dict[str, object]] = []
            render_excluded: list[dict[str, object]] = []
            review_code = f"ISR-{len(prepared) + 1:02d}"
            for index, structural in enumerate(row.pop("structuralCandidates"), start=1):
                sprite_id = int(structural["spriteId"])
                if sprite_id not in preview_by_sprite:
                    render_excluded.append({**structural, "renderExclusionReason": preview_errors[sprite_id]})
                    continue
                preview = preview_by_sprite[sprite_id]
                candidates.append(
                    {
                        "candidateId": f"{review_code.lower()}-c{index:02d}-s{sprite_id}-f{preview['frame']}",
                        **structural,
                        **preview,
                    }
                )
            if not candidates:
                raise RescueError(f"全部内部候选都无法安全预览：{row['portraitRef']}")
            prepared.append(
                {
                    **row,
                    "reviewCode": review_code,
                    "variantKey": "default",
                    "candidates": candidates,
                    "renderExcludedCandidates": render_excluded,
                }
            )
        source_records.append(
            {
                "sourceIndex": source_index,
                "sourceSwf": core.artifact(swf_path),
                "ffdecXml": core.artifact(xml_path),
                "portraitRefs": sorted(str(row["portraitRef"]) for row in source_rows),
                "selectedSpriteIds": sorted(selected_ids),
                "runs": [xml_run, sample_run],
            }
        )

    prepared.sort(key=lambda row: next(index for index, target in enumerate(targets) if target["portraitRef"] == row["portraitRef"]))
    for index, row in enumerate(prepared, start=1):
        row["reviewCode"] = f"ISR-{index:02d}"
        for candidate_index, candidate in enumerate(row["candidates"], start=1):
            candidate["candidateId"] = (
                f"isr{index:02d}-c{candidate_index:02d}-s{candidate['spriteId']}-f{candidate['frame']}"
            )

    contact_sheet_path = output / "internal-subject-contact-sheet.png"
    draw_sheet(prepared, contact_sheet_path, "CF7 missing-man internal subject rescue · complexity is recall only")
    model_batches: list[dict[str, object]] = []
    for start in range(0, len(prepared), 4):
        batch_rows = prepared[start : start + 4]
        batch_id = f"subject-batch-{start // 4 + 1:02d}"
        sheet_path = output / "model-sheets" / f"{batch_id}.png"
        draw_sheet(batch_rows, sheet_path, f"{args.batch_id} · {batch_id} · inspect every tier")
        model_batches.append(
            {
                "modelBatchId": batch_id,
                "reviewKeys": [str(row["reviewKey"]) for row in batch_rows],
                "contactSheet": core.artifact(sheet_path),
            }
        )

    input_records = {
        "arenaUnits": core.artifact(UNITS_PATH),
        "productionPortraitManifest": core.artifact(MANIFEST_PATH),
        "assetSourceMap": core.artifact(core.ASSET_MAP_PATH),
        "targetReviewKeys": [str(row["reviewKey"]) for row in prepared],
        "sourceSwfs": [record["sourceSwf"] for record in source_records],
    }
    source_digest = stable_digest(input_records)
    manifest: dict[str, object] = {
        "schema": SCHEMA,
        "phase": PHASE,
        "status": "internal_subject_candidates_ready",
        "productionReady": False,
        "humanReviewRequired": True,
        "batchId": args.batch_id,
        "createdAt": utc_now(),
        "sourceDigest": source_digest,
        "inputs": input_records,
        "ffdec": ffdec,
        "selectedSpriteSampleExporter": sample_exporter,
        "sources": source_records,
        "reviewItems": prepared,
        "modelBatches": model_batches,
        "contactSheet": core.artifact(contact_sheet_path),
        "counts": {
            "targetIdentityCount": len(prepared),
            "candidateCount": sum(len(row["candidates"]) for row in prepared),
            "hardUiExcludedCandidateCount": sum(len(row["hardUiExcludedCandidates"]) for row in prepared),
            "renderExcludedCandidateCount": sum(len(row["renderExcludedCandidates"]) for row in prepared),
            "modelBatchCount": len(model_batches),
            "expectedIndependentModelJobs": len(model_batches) * 2,
        },
        "rankingContract": {
            "complexityUse": "candidate_recall_prior_only",
            "discoveryDepth": MAX_DISCOVERY_DEPTH,
            "maximumCandidatesPerIdentity": MAX_CANDIDATES,
            "stratifiedTiers": ["high", "medium", "low"],
            "knownUiNamesHardExcluded": True,
            "multimodalSubjectDecisionRequired": True,
            "humanFinalDecisionRequired": True,
        },
        "gates": {
            "exactArenaPendingUniqueSet": not bool(args.target_ref),
            "explicitArenaTargetSubset": bool(args.target_ref),
            "allRootsLackNamedMan": True,
            "rootFallbackRendered": False,
            "complexitySelectsProductionSubject": False,
            "sourceArtifactsClosed": True,
            "boundedSampleFramesPerSprite": True,
            "boundedSampleCanvasPixels": MAX_SAMPLE_PIXELS,
            "vectorExportDeferredUntilHumanSubjectSelection": True,
            "productionWrites": False,
            "humanArtAcceptance": False,
        },
    }
    manifest["manifestDigest"] = stable_digest(manifest)
    manifest_path = output / "internal-subject-rescue-manifest.json"
    core.write_json(manifest_path, manifest)
    print(
        f"internal subject rescue prepared: {len(prepared)} identities, "
        f"{manifest['counts']['candidateCount']} candidates, digest={manifest['manifestDigest']}"
    )


def check(args: argparse.Namespace) -> None:
    manifest_path = core.ensure_below(Path(args.manifest), PILOT_ROOT, "internal subject rescue manifest")
    manifest = core.load_json(manifest_path)
    if not isinstance(manifest, dict) or manifest.get("schema") != SCHEMA or manifest.get("phase") != PHASE:
        raise RescueError("internal subject rescue manifest schema/phase 不受支持")
    copy = dict(manifest)
    digest = copy.pop("manifestDigest", None)
    if digest != stable_digest(copy):
        raise RescueError("internal subject rescue manifestDigest 漂移")
    input_keys = manifest.get("inputs", {}).get("targetReviewKeys")
    if not isinstance(input_keys, list) or not all(isinstance(value, str) for value in input_keys):
        raise RescueError("rescue targetReviewKeys 非法")
    explicit_refs = None
    if manifest.get("gates", {}).get("explicitArenaTargetSubset") is True:
        explicit_refs = [value.rsplit("::", 1)[0] for value in input_keys]
    targets, _, _ = derive_targets(explicit_refs)
    expected_keys = [str(row["reviewKey"]) for row in targets]
    if manifest.get("inputs", {}).get("targetReviewKeys") != expected_keys:
        raise RescueError("rescue 目标集合与当前 Arena pending unique 集合漂移")
    for label, record in manifest.get("inputs", {}).items():
        if label in {"targetReviewKeys", "sourceSwfs"}:
            continue
        core.verify_artifact_record(record, f"input {label}")
    if stable_digest(manifest["inputs"]) != manifest.get("sourceDigest"):
        raise RescueError("internal subject rescue sourceDigest 漂移")
    items = manifest.get("reviewItems")
    if not isinstance(items, list) or len(items) != len(targets):
        raise RescueError("rescue reviewItems 数量不闭合")
    candidate_ids: set[str] = set()
    review_keys: set[str] = set()
    for item in items:
        review_key = item.get("reviewKey")
        candidates = item.get("candidates")
        if review_key in review_keys or not isinstance(candidates, list) or not 1 <= len(candidates) <= MAX_CANDIDATES:
            raise RescueError(f"rescue row 非法：{review_key}")
        review_keys.add(review_key)
        ranks = [int(candidate["complexityRank"]) for candidate in candidates]
        if ranks != sorted(ranks):
            raise RescueError(f"候选没有按复杂度排序：{review_key}")
        for candidate in candidates:
            candidate_id = candidate.get("candidateId")
            if candidate_id in candidate_ids or int(candidate["spriteId"]) == int(item["rootCharacterId"]):
                raise RescueError(f"候选 ID 重复或错误回退 root：{candidate_id}")
            candidate_ids.add(candidate_id)
            for field in ("artifact", "sourceFrameArtifact"):
                core.verify_artifact_record(candidate[field], f"candidate {candidate_id} {field}")
            samples = candidate.get("sampleFrameArtifacts")
            if not isinstance(samples, list) or not 1 <= len(samples) <= 5:
                raise RescueError(f"candidate sample frame 数量非法：{candidate_id}")
            for sample in samples:
                core.verify_artifact_record(sample, f"candidate {candidate_id} sample")
    exporter = manifest.get("selectedSpriteSampleExporter", {})
    core.verify_artifact_record(exporter.get("source"), "sample exporter source")
    for record in exporter.get("classes", []):
        core.verify_artifact_record(record, "sample exporter class")
    for record in exporter.get("classpathFiles", []):
        core.verify_artifact_record(record, "sample exporter classpath")
    for source in manifest.get("sources", []):
        core.verify_artifact_record(source.get("sourceSwf"), "rescue source SWF")
        core.verify_artifact_record(source.get("ffdecXml"), "rescue source XML")
        for run in source.get("runs", []):
            for field in ("stdout", "stderr", "commandRecord"):
                core.verify_artifact_record(run.get(field), f"rescue run {field}")
    core.verify_artifact_record(manifest["contactSheet"], "rescue contact sheet")
    batched: list[str] = []
    for batch in manifest.get("modelBatches", []):
        if not 1 <= len(batch.get("reviewKeys", [])) <= 4:
            raise RescueError("模型小批必须为 1–4 行")
        batched.extend(batch["reviewKeys"])
        core.verify_artifact_record(batch["contactSheet"], f"model batch {batch.get('modelBatchId')}")
    if sorted(batched) != sorted(review_keys) or len(batched) != len(review_keys):
        raise RescueError("模型小批没有精确覆盖 rescue rows")
    counts = manifest.get("counts", {})
    if counts != {
        "targetIdentityCount": len(items),
        "candidateCount": len(candidate_ids),
        "hardUiExcludedCandidateCount": sum(len(row["hardUiExcludedCandidates"]) for row in items),
        "renderExcludedCandidateCount": sum(len(row["renderExcludedCandidates"]) for row in items),
        "modelBatchCount": len(manifest["modelBatches"]),
        "expectedIndependentModelJobs": len(manifest["modelBatches"]) * 2,
    }:
        raise RescueError("rescue counts 不闭合")
    if manifest.get("productionReady") is not False or manifest.get("gates", {}).get("productionWrites") is not False:
        raise RescueError("rescue 批不得获得生产写权限")
    print(
        f"internal subject rescue check passed: {len(items)} identities, "
        f"{len(candidate_ids)} candidates, digest={digest}"
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--output", required=True)
    build_parser.add_argument("--batch-id", required=True)
    build_parser.add_argument(
        "--target-ref",
        action="append",
        default=[],
        help="只处理指定 Arena portraitRef；可重复。省略时保持历史 17 项闭包",
    )
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--manifest", required=True)
    return result


def main() -> None:
    args = parser().parse_args()
    if args.command == "build":
        build(args)
    else:
        check(args)


if __name__ == "__main__":
    try:
        main()
    except (RescueError, core.PilotError) as error:
        raise SystemExit(str(error)) from error
