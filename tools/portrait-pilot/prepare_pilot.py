#!/usr/bin/env python3
"""Prepare and deterministically render isolated CF7 portrait pilot rounds."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageSequence, ImageStat, __version__ as PILLOW_VERSION


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
FIXTURE_PATH = ROOT / "tools" / "portrait-pilot" / "fixtures" / "representative-entities.v1.json"
FEATURE_PROFILE_PATH = ROOT / "tools" / "portrait-pilot" / "fixtures" / "feature-refinement.v1.json"
SELECTED_FRAME_EXPORTER_PATH = ROOT / "tools" / "portrait-pilot" / "SelectedSpriteFrameExporter.java"
ASSET_MAP_PATH = ROOT / "data" / "items" / "asset_source_map.xml"
ENEMY_LIST_PATH = ROOT / "data" / "enemy_properties" / "list.xml"
PETS_PATH = ROOT / "data" / "merc" / "pets.xml"
FFDEC_PATH = ROOT / "tools" / "ffdec" / "ffdec-cli.exe"
FFDEC_EXPECTED_VERSION = "21.1.1"
FFDEC_CLOSURE = {
    "tools/ffdec/ffdec-cli.exe": "C03AD5D22008246B9F2523A70830502ED0D01610F4054912B43AE70F58DDDD86",
    "tools/ffdec/ffdec-cli.jar": "3FE309A320F9136A46F5FF84E21E96903B8DD8D94B829DE4895BAAE9B486B6C7",
    "tools/ffdec/ffdec.jar": "7F75B47152D955BE5CCC853EB259A1A7910EA9A0BD2B41CF9B9085BCFB003952",
    "tools/ffdec/lib/ffdec_lib.jar": "49E4DA602A9000E3556C788A9653312A7B1E2EC0A7C6B8FF9E075C6B67B03630",
}


class PilotError(RuntimeError):
    pass


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def stable_bytes(value: object) -> bytes:
    def normalize(entry: object) -> object:
        if isinstance(entry, dict):
            return {key: normalize(child) for key, child in entry.items()}
        if isinstance(entry, list):
            return [normalize(child) for child in entry]
        if isinstance(entry, float) and entry.is_integer():
            return int(entry)
        return entry

    return json.dumps(
        normalize(value),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def repo_rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def ensure_below(path: Path, parent: Path, label: str) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(parent.resolve())
    except ValueError as error:
        raise PilotError(f"{label} 必须位于 {parent}") from error
    return resolved


def artifact(path: Path) -> dict[str, object]:
    return {
        "path": repo_rel(path),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_fixture(fixture: dict[str, object]) -> None:
    if fixture.get("schema") != "cf7.portrait-pilot-representative-set.v1":
        raise PilotError("代表集 schema 不受支持")
    entities = fixture.get("entities")
    if not isinstance(entities, list) or len(entities) != 14:
        raise PilotError("P2 代表集必须恰有 14 个 identity")
    keys: set[str] = set()
    review_count = 0
    for entity in entities:
        if not isinstance(entity, dict):
            raise PilotError("代表集 entity 必须是对象")
        portrait_ref = entity.get("portraitRef")
        variants = entity.get("variants")
        if not isinstance(portrait_ref, str) or not isinstance(variants, list) or not variants:
            raise PilotError("代表集 identity/variants 不闭合")
        for variant in variants:
            key = f"{portrait_ref}::{variant.get('variantKey')}"
            if key in keys:
                raise PilotError(f"重复审核键：{key}")
            keys.add(key)
            review_count += 1
    if review_count != 15:
        raise PilotError("P2 代表集必须恰有 15 个审核单元")


def parse_asset_map() -> dict[str, dict[str, object]]:
    root = ET.parse(ASSET_MAP_PATH).getroot()
    records: dict[str, dict[str, object]] = {}
    for node in root.findall("asset"):
        records[node.attrib["id"]] = {
            "classification": "unique",
            "sources": [
                {
                    "swf": node.attrib["swf"],
                    "symbolName": node.attrib.get("symbolName"),
                    "orphan": node.attrib.get("orphan") == "true",
                }
            ],
        }
    for classification in ("duplicate", "conflict"):
        for node in root.findall(classification):
            records[node.attrib["id"]] = {
                "classification": classification,
                "sources": [
                    {
                        "swf": source.attrib["swf"],
                        "symbolName": source.attrib.get("symbolName"),
                        "orphan": source.attrib.get("orphan") == "true",
                    }
                    for source in node.findall("source")
                ],
            }
    return records


def load_consumers() -> tuple[set[str], dict[str, list[int]], list[Path]]:
    enemy_files = [
        ROOT / "data" / "enemy_properties" / node.text.strip()
        for node in ET.parse(ENEMY_LIST_PATH).getroot().findall("items")
        if node.text and node.text.strip()
    ]
    enemy_ids: set[str] = set()
    for enemy_file in enemy_files:
        for child in ET.parse(enemy_file).getroot():
            enemy_ids.add(child.tag)
    pet_ids: dict[str, list[int]] = {}
    for pet in ET.parse(PETS_PATH).getroot().findall("Pet"):
        identifier = pet.findtext("Identifier")
        pet_id = pet.findtext("id")
        if identifier and pet_id is not None:
            pet_ids.setdefault(identifier.strip(), []).append(int(pet_id))
    return enemy_ids, pet_ids, enemy_files


def verify_ffdec() -> dict[str, object]:
    files = []
    for rel_path, expected_hash in FFDEC_CLOSURE.items():
        full_path = ROOT / rel_path
        if not full_path.is_file():
            raise PilotError(f"FFDec 闭包缺文件：{rel_path}")
        actual_hash = sha256_file(full_path)
        if actual_hash != expected_hash:
            raise PilotError(f"FFDec 闭包 hash 漂移：{rel_path}")
        files.append({"path": rel_path, "bytes": full_path.stat().st_size, "sha256": actual_hash})
    completed = subprocess.run(
        [str(FFDEC_PATH), "-help"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    version_text = (completed.stdout + b"\n" + completed.stderr).decode("utf-8", errors="replace")
    if completed.returncode != 0 or FFDEC_EXPECTED_VERSION not in version_text:
        raise PilotError("FFDec 版本探针失败或版本漂移")
    return {
        "version": FFDEC_EXPECTED_VERSION,
        "probeOutputSha256": sha256_bytes(completed.stdout + b"\n" + completed.stderr),
        "files": files,
    }


def run_ffdec(args: list[str], output_dir: Path, name: str, timeout_seconds: int = 360) -> dict[str, object]:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    started = time.monotonic()
    try:
        completed = subprocess.run(
            [str(FFDEC_PATH), *args],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise PilotError(f"FFDec 超时：{name}") from error
    log_dir = output_dir / "ffdec-logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    stdout_path = log_dir / f"{name}.stdout.bin"
    stderr_path = log_dir / f"{name}.stderr.bin"
    stdout_path.write_bytes(completed.stdout)
    stderr_path.write_bytes(completed.stderr)
    command_path = log_dir / f"{name}.command.json"
    command_record = {
        "argv": [repo_rel(FFDEC_PATH), *args],
        "startedAt": started_at,
        "durationMs": round((time.monotonic() - started) * 1000),
        "exitCode": completed.returncode,
        "stdout": artifact(stdout_path),
        "stderr": artifact(stderr_path),
    }
    write_json(command_path, command_record)
    if completed.returncode != 0:
        raise PilotError(f"FFDec 非零退出：{name} exit={completed.returncode}")
    return {**command_record, "commandRecord": artifact(command_path)}


def external_file_record(path: Path) -> dict[str, object]:
    resolved = path.resolve()
    return {
        "path": str(resolved),
        "bytes": resolved.stat().st_size,
        "sha256": sha256_file(resolved),
    }


def find_java_tool(name: str) -> Path:
    executable = f"{name}.exe" if os.name == "nt" else name
    discovered = shutil.which(name)
    candidates: list[Path] = [Path(discovered)] if discovered else []
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        candidates.append(Path(java_home) / "bin" / executable)
    if os.name == "nt":
        for env_name in ("ProgramFiles", "ProgramFiles(x86)"):
            root = os.environ.get(env_name)
            if not root:
                continue
            adobe_root = Path(root) / "Adobe"
            if adobe_root.is_dir():
                candidates.extend(sorted(adobe_root.glob(f"Adobe Animate */jre/bin/{executable}"), reverse=True))
    for candidate in candidates:
        if candidate and candidate.is_file():
            return candidate.resolve()
    raise PilotError(f"找不到 {name}；高分辨率逐帧 FFDec adapter 需要 Java 编译/运行环境")


def run_logged_tool(
    argv: list[str],
    output_dir: Path,
    name: str,
    timeout_seconds: int,
) -> dict[str, object]:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    started = time.monotonic()
    try:
        completed = subprocess.run(
            argv,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise PilotError(f"外部工具超时：{name}") from error
    log_dir = output_dir / "selected-frame-logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    stdout_path = log_dir / f"{name}.stdout.bin"
    stderr_path = log_dir / f"{name}.stderr.bin"
    stdout_path.write_bytes(completed.stdout)
    stderr_path.write_bytes(completed.stderr)
    command_path = log_dir / f"{name}.command.json"
    command_record = {
        "argv": argv,
        "startedAt": started_at,
        "durationMs": round((time.monotonic() - started) * 1000),
        "exitCode": completed.returncode,
        "stdout": artifact(stdout_path),
        "stderr": artifact(stderr_path),
    }
    write_json(command_path, command_record)
    if completed.returncode != 0:
        stderr_tail = completed.stderr.decode("utf-8", errors="replace")[-800:]
        raise PilotError(f"外部工具非零退出：{name} exit={completed.returncode} stderr={stderr_tail}")
    return {**command_record, "commandRecord": artifact(command_path)}


def compile_selected_frame_exporter(output_dir: Path, attempt_tag: str) -> dict[str, object]:
    if not SELECTED_FRAME_EXPORTER_PATH.is_file():
        raise PilotError("SelectedSpriteFrameExporter.java 缺失")
    javac = find_java_tool("javac")
    java = find_java_tool("java")
    class_dir = output_dir / f"selected-frame-exporter-classes-{attempt_tag}"
    if class_dir.exists():
        raise PilotError(f"selected-frame-exporter-classes-{attempt_tag} 已存在，拒绝覆盖")
    class_dir.mkdir(parents=True)
    classpath = os.pathsep.join(
        [str(ROOT / "tools" / "ffdec" / "lib" / "*"), str(ROOT / "tools" / "ffdec" / "ffdec.jar")]
    )
    compile_run = run_logged_tool(
        [
            str(javac),
            "-encoding",
            "UTF-8",
            "-cp",
            classpath,
            "-d",
            str(class_dir),
            str(SELECTED_FRAME_EXPORTER_PATH),
        ],
        output_dir,
        f"selected-frame-exporter-{attempt_tag}-compile",
        120,
    )
    class_path = class_dir / "SelectedSpriteFrameExporter.class"
    inner_class_path = class_dir / "SelectedSpriteFrameExporter$AbortHandler.class"
    if not class_path.is_file() or not inner_class_path.is_file():
        raise PilotError("SelectedSpriteFrameExporter 编译产物不闭合")
    runtime_classpath = os.pathsep.join([str(class_dir), classpath])
    return {
        "java": external_file_record(java),
        "javac": external_file_record(javac),
        "source": artifact(SELECTED_FRAME_EXPORTER_PATH),
        "classes": [artifact(class_path), artifact(inner_class_path)],
        "classpathFiles": [artifact(ROOT / rel_path) for rel_path in FFDEC_CLOSURE if rel_path.endswith(".jar")],
        "compileRun": compile_run,
        "classDirectory": repo_rel(class_dir),
        "runtimeClasspath": runtime_classpath,
    }


def export_selected_sprite_frames(
    adapter: dict[str, object],
    output_dir: Path,
    swf_path: Path,
    character_id: int,
    frames: list[int],
    zoom: int,
    group_id: str,
    attempt_tag: str,
) -> tuple[dict[str, object], dict[int, dict[str, object]]]:
    export_root = output_dir / f"selected-high-resolution-{attempt_tag}" / group_id
    if export_root.exists():
        raise PilotError(f"高分辨率逐帧目录已存在：{export_root}")
    frame_csv = ",".join(str(frame) for frame in frames)
    run = run_logged_tool(
        [
            str(adapter["java"]["path"]),
            "-cp",
            str(adapter["runtimeClasspath"]),
            "SelectedSpriteFrameExporter",
            str(swf_path),
            str(export_root),
            str(character_id),
            str(zoom),
            frame_csv,
        ],
        output_dir,
        f"{attempt_tag}-{group_id}-selected-frames",
        900,
    )
    sprite_dir = export_root / f"DefineSprite_{character_id}"
    records: dict[int, dict[str, object]] = {}
    for frame in frames:
        frame_path = sprite_dir / f"{frame}.png"
        if not frame_path.is_file():
            raise PilotError(f"FFDec selected frame 缺失：id={character_id} frame={frame}")
        records[frame] = artifact(frame_path)
    actual_files = [path for path in export_root.rglob("*") if path.is_file()]
    if len(actual_files) != len(frames):
        raise PilotError(
            f"FFDec selected frame 输出不精确：id={character_id} expected={len(frames)} actual={len(actual_files)}"
        )
    return {
        **run,
        "sourceSwf": artifact(swf_path),
        "characterId": character_id,
        "frames": frames,
        "zoom": zoom,
        "outputs": [records[frame] for frame in frames],
    }, records


def export_assets_from_xml(xml_path: Path) -> dict[str, list[int]]:
    root = ET.parse(xml_path).getroot()
    exports: dict[str, list[int]] = {}
    for node in root.iter("item"):
        if node.attrib.get("type") != "ExportAssetsTag":
            continue
        tags_node = node.find("tags")
        names_node = node.find("names")
        if tags_node is None or names_node is None:
            continue
        tags = [int(item.text) for item in tags_node.findall("item") if item.text]
        names = [item.text or "" for item in names_node.findall("item")]
        if len(tags) != len(names):
            raise PilotError(f"ExportAssets tags/names 数量不一致：{xml_path}")
        for name, tag in zip(names, tags):
            exports.setdefault(name, []).append(tag)
    return exports


def sprite_frame_counts(xml_path: Path) -> dict[int, int]:
    counts: dict[int, int] = {}
    for node in ET.parse(xml_path).getroot().iter("item"):
        if node.attrib.get("type") == "DefineSpriteTag":
            counts[int(node.attrib["spriteId"])] = int(node.attrib.get("frameCount", "0"))
    return counts


def first_frame_named_instance(xml_path: Path, root_character_id: int, instance_name: str) -> int | None:
    definitions = {
        int(node.attrib["spriteId"]): node
        for node in ET.parse(xml_path).getroot().iter("item")
        if node.attrib.get("type") == "DefineSpriteTag"
    }
    root_sprite = definitions.get(root_character_id)
    if root_sprite is None:
        return None
    sub_tags = root_sprite.find("subTags")
    if sub_tags is None:
        return None
    matches: list[int] = []
    for node in sub_tags.findall("item"):
        if node.attrib.get("type") == "ShowFrameTag":
            break
        if node.attrib.get("name") == instance_name and node.attrib.get("characterId"):
            character_id = int(node.attrib["characterId"])
            if character_id > 0:
                matches.append(character_id)
    unique = sorted(set(matches))
    if len(unique) > 1:
        raise PilotError(
            f"首帧命名实例不唯一：root={root_character_id} name={instance_name} ids={unique}"
        )
    return unique[0] if unique else None


def expanded_bbox(bbox: tuple[int, int, int, int], size: tuple[int, int]) -> tuple[int, int, int, int]:
    left, top, right, bottom = bbox
    padding = max(4, round(max(right - left, bottom - top) * 0.06))
    return (
        max(0, left - padding),
        max(0, top - padding),
        min(size[0], right + padding),
        min(size[1], bottom + padding),
    )


def inspect_gif_frames(gif_path: Path) -> list[dict[str, object]]:
    frames: list[dict[str, object]] = []
    seen: set[str] = set()
    with Image.open(gif_path) as image:
        for index, frame in enumerate(ImageSequence.Iterator(image), start=1):
            rgba = frame.convert("RGBA")
            bbox = rgba.getchannel("A").getbbox()
            if not bbox or bbox[2] - bbox[0] < 8 or bbox[3] - bbox[1] < 8:
                continue
            crop_box = expanded_bbox(bbox, rgba.size)
            cropped = rgba.crop(crop_box)
            visual_hash = sha256_bytes(
                f"{cropped.width}x{cropped.height}:".encode("ascii") + cropped.tobytes()
            )
            if visual_hash in seen:
                continue
            seen.add(visual_hash)
            frames.append(
                {
                    "frame": index,
                    "sourceSize": list(rgba.size),
                    "alphaBounds": list(bbox),
                    "cropBounds": list(crop_box),
                    "visualSha256": visual_hash,
                }
            )
    return frames


def choose_evenly(frames: list[dict[str, object]], maximum: int) -> list[dict[str, object]]:
    if len(frames) <= maximum:
        return frames
    indexes = []
    for slot in range(maximum):
        index = round(slot * (len(frames) - 1) / (maximum - 1))
        if index not in indexes:
            indexes.append(index)
    return [frames[index] for index in indexes]


def save_selected_frames(
    gif_path: Path,
    selected: list[dict[str, object]],
    destination: Path,
    entity_code: str,
) -> list[dict[str, object]]:
    destination.mkdir(parents=True, exist_ok=True)
    selected_by_frame = {int(row["frame"]): row for row in selected}
    results: list[dict[str, object]] = []
    with Image.open(gif_path) as image:
        for index, frame in enumerate(ImageSequence.Iterator(image), start=1):
            if index not in selected_by_frame:
                continue
            row = selected_by_frame[index]
            rgba = frame.convert("RGBA")
            crop_bounds = tuple(int(value) for value in row["cropBounds"])
            cropped = rgba.crop(crop_bounds)
            candidate_number = len(results) + 1
            candidate_id = f"{entity_code}-c{candidate_number:02d}"
            output_path = destination / f"c{candidate_number:02d}-frame-{index:04d}.png"
            cropped.save(output_path, format="PNG", optimize=False, compress_level=9)
            results.append(
                {
                    "candidateId": candidate_id,
                    "frame": index,
                    "sourceSize": row["sourceSize"],
                    "alphaBounds": row["alphaBounds"],
                    "sourceCropBounds": row["cropBounds"],
                    "visualSha256": row["visualSha256"],
                    "artifact": artifact(output_path),
                    "width": cropped.width,
                    "height": cropped.height,
                }
            )
    if len(results) != len(selected):
        raise PilotError(f"GIF 二次读取未闭合：{gif_path}")
    return results


def find_font() -> tuple[ImageFont.FreeTypeFont | ImageFont.ImageFont, dict[str, object]]:
    candidates = [
        Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts" / "msyh.ttc",
        Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts" / "consola.ttf",
        Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts" / "arial.ttf",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), 18), {
                "path": str(candidate),
                "sha256": sha256_file(candidate),
            }
    return ImageFont.load_default(), {"path": "Pillow.default", "sha256": None}


def checker(size: tuple[int, int], cell: int = 16) -> Image.Image:
    image = Image.new("RGB", size, "#20252c")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2 == 0:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill="#2c333d")
    return image


def paste_contained(canvas: Image.Image, source: Image.Image, box: tuple[int, int, int, int]) -> None:
    left, top, right, bottom = box
    max_width = right - left
    max_height = bottom - top
    scale = min(max_width / source.width, max_height / source.height)
    size = (max(1, round(source.width * scale)), max(1, round(source.height * scale)))
    resized = source.resize(size, Image.Resampling.LANCZOS)
    x = left + (max_width - size[0]) // 2
    y = top + (max_height - size[1]) // 2
    canvas.paste(resized, (x, y), resized)


def build_contact_sheet(
    output_dir: Path,
    review_items: list[dict[str, object]],
    output_name: str = "contact-sheet.png",
    subtitle: str = "R=row, C=candidate. Red rows are source blockers and have no selectable candidate.",
) -> tuple[dict[str, object], dict[str, object]]:
    font, font_evidence = find_font()
    label_width = 250
    cell_width = 205
    row_height = 230
    header_height = 72
    width = label_width + 6 * cell_width
    height = header_height + len(review_items) * row_height
    canvas = Image.new("RGB", (width, height), "#15191f")
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 14), "CF7 PORTRAIT P2 / REPRESENTATIVE BLIND CANDIDATES", font=font, fill="#f2f5f8")
    draw.text((18, 40), subtitle, font=font, fill="#9eabb8")
    for row_index, item in enumerate(review_items):
        top = header_height + row_index * row_height
        blocked = bool(item["blocked"])
        draw.rectangle((0, top, width, top + row_height - 1), fill="#341e22" if blocked else ("#1c222a" if row_index % 2 == 0 else "#181e25"))
        draw.line((0, top, width, top), fill="#3c4653")
        draw.text((16, top + 18), item["reviewCode"], font=font, fill="#ff9da7" if blocked else "#7dd3fc")
        draw.text((16, top + 47), str(item["category"])[:24], font=font, fill="#d8dee7")
        draw.text((16, top + 76), f"variant={item['variantKey']}", font=font, fill="#aeb8c4")
        if item.get("variantResolution") == "timeline_visual_proposal_human_verified":
            draw.text((16, top + 105), "variant-source=A/B+HUMAN", font=font, fill="#f0c674")
        if blocked:
            draw.text((16, top + 136), f"BLOCKED: {item['sourceClassification']}", font=font, fill="#ff8d98")
            continue
        for candidate_index, candidate in enumerate(item["candidates"]):
            cell_left = label_width + candidate_index * cell_width
            cell_top = top + 10
            background = checker((cell_width - 12, 174))
            canvas.paste(background, (cell_left + 6, cell_top + 28))
            candidate_path = ROOT / candidate["artifact"]["path"]
            with Image.open(candidate_path) as source:
                paste_contained(
                    canvas,
                    source.convert("RGBA"),
                    (cell_left + 12, cell_top + 34, cell_left + cell_width - 12, cell_top + 194),
                )
            label = f"C{candidate_index + 1:02d} / f{candidate['frame']}"
            draw.text((cell_left + 8, cell_top + 3), label, font=font, fill="#f0c674")
    output_path = output_dir / output_name
    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    return artifact(output_path), font_evidence


def verify_digest_object(value: dict[str, object], digest_field: str, label: str) -> None:
    digest = value.get(digest_field)
    if not isinstance(digest, str):
        raise PilotError(f"{label} 缺 {digest_field}")
    envelope = dict(value)
    envelope.pop(digest_field, None)
    if sha256_bytes(stable_bytes(envelope)) != digest:
        raise PilotError(f"{label} {digest_field} 不匹配")


def verify_artifact_record(record: dict[str, object], label: str) -> Path:
    if not isinstance(record, dict):
        raise PilotError(f"{label} artifact 不是对象")
    record_path = record.get("path")
    record_bytes = record.get("bytes")
    record_sha = record.get("sha256")
    if not isinstance(record_path, str) or not isinstance(record_bytes, int) or not isinstance(record_sha, str):
        raise PilotError(f"{label} artifact 记录不闭合")
    file_path = (ROOT / record_path).resolve()
    ensure_below(file_path, ROOT, label)
    if not file_path.is_file():
        raise PilotError(f"{label} artifact 缺失：{record_path}")
    if file_path.stat().st_size != record_bytes or sha256_file(file_path) != record_sha:
        raise PilotError(f"{label} artifact 字节闭包不匹配：{record_path}")
    return file_path


def validate_feature_profile(profile: dict[str, object]) -> None:
    if profile.get("schema") != "cf7.portrait-pilot-feature-refinement-profile.v1":
        raise PilotError("特征精修 profile schema 不受支持")
    if not isinstance(profile.get("batchId"), str) or not profile["batchId"]:
        raise PilotError("特征精修 profile 缺 batchId")
    if not isinstance(profile.get("globalContract"), list) or not profile["globalContract"]:
        raise PilotError("特征精修 profile 缺全局构图合同")
    geometry = profile.get("geometry")
    if not isinstance(geometry, dict) or not isinstance(geometry.get("modes"), dict):
        raise PilotError("特征精修 geometry 不闭合")
    safe_margin = geometry.get("mustIncludeSafeMargin")
    if not isinstance(safe_margin, (int, float)) or not 0.02 <= safe_margin <= 0.2:
        raise PilotError("mustIncludeSafeMargin 必须位于 0.02..0.2")
    required_modes = {"head_closeup", "feature_closeup", "feature_group", "full_subject"}
    if set(geometry["modes"]) != required_modes:
        raise PilotError("特征精修 framing mode 不闭合")
    for mode, config in geometry["modes"].items():
        if not isinstance(config, dict):
            raise PilotError(f"framing mode 配置非法：{mode}")
        for field in (
            "featureWidthOccupancy",
            "featureHeightOccupancy",
            "minimumRenderedFeatureLongAxisOccupancy",
            "minimumRenderedFeatureShortAxisOccupancy",
        ):
            value = config.get(field)
            if not isinstance(value, (int, float)) or not 0.2 <= value <= 0.9:
                raise PilotError(f"framing mode {mode}/{field} 越界")
        if config["minimumRenderedFeatureShortAxisOccupancy"] > config["minimumRenderedFeatureLongAxisOccupancy"]:
            raise PilotError(f"framing mode {mode} 长短轴占比下限顺序错误")
        anchor = config.get("featureAnchor")
        if (
            not isinstance(anchor, list)
            or len(anchor) != 2
            or any(not isinstance(value, (int, float)) or not 0.1 <= value <= 0.9 for value in anchor)
        ):
            raise PilotError(f"framing mode {mode}/featureAnchor 非法")
    high_resolution = profile.get("highResolutionRender")
    if not isinstance(high_resolution, dict):
        raise PilotError("特征精修 highResolutionRender 缺失")
    for field, minimum, maximum in (
        ("targetSupersampleSize", 1024, 4096),
        ("minimumSourceCropSize", 512, 4096),
        ("maximumSourceFrameDimension", 4096, 16384),
        ("maximumZoom", 8, 64),
        ("fidelityMeanAbsoluteErrorLimit", 1, 32),
    ):
        value = high_resolution.get(field)
        if not isinstance(value, int) or not minimum <= value <= maximum:
            raise PilotError(f"highResolutionRender/{field} 越界")
    policies = profile.get("categoryPolicies")
    if not isinstance(policies, dict) or not policies:
        raise PilotError("特征精修 categoryPolicies 缺失")
    for category, policy in policies.items():
        if (
            not isinstance(policy, dict)
            or policy.get("defaultMode") not in required_modes
            or not isinstance(policy.get("reasoningHint"), str)
            or not policy["reasoningHint"].strip()
        ):
            raise PilotError(f"类别策略非法：{category}")
    review_overrides = profile.get("reviewKeyOverrides", {})
    if not isinstance(review_overrides, dict):
        raise PilotError("特征精修 reviewKeyOverrides 必须是对象")
    for review_key, override in review_overrides.items():
        if not isinstance(review_key, str) or not review_key or not isinstance(override, dict):
            raise PilotError("特征精修 reviewKeyOverride 键值非法")
        if set(override) != {"reasoningHint", "requiredFeatureRegion", "requiredMustIncludeRegion"}:
            raise PilotError(f"reviewKeyOverride 字段不闭合：{review_key}")
        if not isinstance(override["reasoningHint"], str) or not override["reasoningHint"].strip():
            raise PilotError(f"reviewKeyOverride reasoningHint 为空：{review_key}")
        required_feature = normalized_box(override["requiredFeatureRegion"], "requiredFeatureRegion")
        required_must = normalized_box(override["requiredMustIncludeRegion"], "requiredMustIncludeRegion")
        tolerance = 1e-6
        if (
            required_feature[0] < required_must[0] - tolerance
            or required_feature[1] < required_must[1] - tolerance
            or required_feature[2] > required_must[2] + tolerance
            or required_feature[3] > required_must[3] + tolerance
        ):
            raise PilotError(f"requiredFeatureRegion 必须包含在 requiredMustIncludeRegion 内：{review_key}")


def load_refinement_parent(source_batch: Path) -> dict[str, object]:
    batch_root = ensure_below(source_batch, PILOT_ROOT, "反馈批目录")
    required = {
        "manifest": batch_root / "candidate-manifest.json",
        "reviewData": batch_root / "review-data.json",
        "decisions": batch_root / "portrait-pilot-review-decisions.json",
        "receipt": batch_root / "human-review-receipt.json",
    }
    for label, file_path in required.items():
        if not file_path.is_file():
            raise PilotError(f"反馈批缺 {label}：{file_path.name}")
    manifest = load_json(required["manifest"])
    review_data = load_json(required["reviewData"])
    decisions = load_json(required["decisions"])
    receipt = load_json(required["receipt"])
    if not all(isinstance(value, dict) for value in (manifest, review_data, decisions, receipt)):
        raise PilotError("反馈批 JSON 顶层必须为对象")
    supported_parents = {
        ("cf7.enemy-portrait-candidates.v1", "P2"),
        ("cf7.enemy-portrait-feature-refinement-candidates.v1", "P3_FEATURE_REFINEMENT"),
        ("cf7.enemy-portrait-feature-refinement-candidates.v2", "P3_FEATURE_REFINEMENT"),
    }
    if (manifest.get("schema"), manifest.get("phase")) not in supported_parents:
        raise PilotError("特征精修父批 schema/phase 不受支持")
    verify_digest_object(manifest, "manifestDigest", "父 candidate manifest")
    if review_data.get("schema") not in {
        "cf7.portrait-pilot-review-data.v1",
        "cf7.portrait-pilot-review-data.v2",
    }:
        raise PilotError("父 review data schema 不受支持")
    review_envelope = {
        "schema": review_data.get("schema"),
        "sourceDigest": review_data.get("sourceDigest"),
        "manifestDigest": review_data.get("manifestDigest"),
        "modelReportDigest": review_data.get("modelReportDigest"),
        "renderDigest": review_data.get("renderDigest"),
        "decisionSchema": review_data.get("decisionSchema"),
        "reviewer": review_data.get("reviewer"),
        "statuses": review_data.get("statuses"),
        "items": review_data.get("items"),
    }
    if review_data.get("schema") == "cf7.portrait-pilot-review-data.v2":
        review_envelope["decisionSemantics"] = review_data.get("decisionSemantics")
        review_envelope["counts"] = review_data.get("counts")
    if sha256_bytes(stable_bytes(review_envelope)) != review_data.get("reviewDigest"):
        raise PilotError("父 reviewDigest 不匹配")
    if decisions.get("schema") != "cf7.portrait-pilot-review-decisions.v1" or decisions.get("complete") is not True:
        raise PilotError("父决定文件未完整导出")
    if (
        decisions.get("batchId") != review_data.get("batchId")
        or decisions.get("sourceDigest") != review_data.get("sourceDigest")
        or decisions.get("reviewDigest") != review_data.get("reviewDigest")
    ):
        raise PilotError("父决定文件 digest 绑定不一致")
    if receipt.get("schema") != "cf7.portrait-pilot-human-review-receipt.v1":
        raise PilotError("父人审收据 schema 不受支持")
    verify_digest_object(receipt, "receiptDigest", "父人审收据")
    if receipt.get("status") != "human_reviewed_refinement_required":
        raise PilotError("父人审结论不是 refinement_required")
    for name, key in (("reviewData", "reviewData"), ("decisions", "decisions")):
        record = receipt.get("inputs", {}).get(key)
        if not isinstance(record, dict):
            raise PilotError(f"父收据缺 {key} artifact")
        if required[name].stat().st_size != record.get("bytes") or sha256_file(required[name]) != record.get("sha256"):
            raise PilotError(f"父收据 {key} artifact 已漂移")
    review_items = review_data.get("items")
    decision_map = decisions.get("decisions")
    if not isinstance(review_items, list) or not review_items or not isinstance(decision_map, dict):
        raise PilotError("父人审行数不闭合")
    review_counts = review_data.get("counts")
    if (
        not isinstance(review_counts, dict)
        or review_counts.get("total") != len(review_items)
        or review_counts.get("eligible") + review_counts.get("blocked") != len(review_items)
    ):
        raise PilotError("父 review data counts 不闭合")
    expected_keys = {item.get("reviewKey") for item in review_items}
    if set(decision_map) != expected_keys:
        raise PilotError("父决定映射没有覆盖全部审核键")
    refinement_keys: list[str] = []
    carried_pass_keys: list[str] = []
    blocked_keys: list[str] = []
    for item in review_items:
        decision = decision_map[item["reviewKey"]]
        if decision.get("status") != "pass" and not str(decision.get("notes", "")).strip():
            raise PilotError(f"父非通过项缺备注：{item['reviewKey']}")
        if item.get("blocked"):
            if decision.get("status") != "source":
                raise PilotError(f"父来源阻断项必须保持 source：{item['reviewKey']}")
            blocked_keys.append(item["reviewKey"])
        elif decision.get("status") == "pass":
            carried_pass_keys.append(item["reviewKey"])
        elif decision.get("status") == "adjustment":
            refinement_keys.append(item["reviewKey"])
        else:
            raise PilotError(
                f"语义精修只接受 adjustment；{item['reviewKey']}={decision.get('status')} 必须转来源/姿态异常队列"
            )
    if not refinement_keys:
        raise PilotError("父人审没有 adjustment 项，禁止创建空精修批")
    return {
        "batchRoot": batch_root,
        "paths": required,
        "manifest": manifest,
        "reviewData": review_data,
        "decisions": decisions,
        "receipt": receipt,
        "refinementKeys": refinement_keys,
        "carriedPassKeys": carried_pass_keys,
        "blockedKeys": blocked_keys,
    }


def paste_gridded_candidate(
    canvas: Image.Image,
    source: Image.Image,
    box: tuple[int, int, int, int],
    font: ImageFont.FreeTypeFont | ImageFont.ImageFont,
) -> None:
    left, top, right, bottom = box
    width = right - left
    height = bottom - top
    background = checker((width, height), 14)
    canvas.paste(background, (left, top))
    scale = min((width - 30) / source.width, (height - 30) / source.height)
    size = (max(1, round(source.width * scale)), max(1, round(source.height * scale)))
    resized = source.resize(size, Image.Resampling.LANCZOS)
    image_left = left + (width - size[0]) // 2
    image_top = top + (height - size[1]) // 2
    canvas.paste(resized, (image_left, image_top), resized)
    draw = ImageDraw.Draw(canvas)
    for index in range(11):
        x = image_left + round(index * size[0] / 10)
        y = image_top + round(index * size[1] / 10)
        line_color = "#F8D66D" if index in (0, 5, 10) else "#7DD3FC"
        draw.line((x, image_top, x, image_top + size[1]), fill=line_color, width=1)
        draw.line((image_left, y, image_left + size[0], y), fill=line_color, width=1)
    draw.rectangle(
        (image_left, image_top, image_left + size[0], image_top + size[1]),
        outline="#FFFFFF",
        width=1,
    )
    draw.text((image_left + 2, image_top + 2), "0", font=font, fill="#FFFFFF")
    draw.text((image_left + size[0] - 20, image_top + 2), "1", font=font, fill="#FFFFFF")
    draw.text((image_left + 2, image_top + size[1] - 22), "1", font=font, fill="#FFFFFF")


def build_feature_contact_sheet(
    output_dir: Path,
    review_items: list[dict[str, object]],
    output_name: str,
    subtitle: str,
) -> tuple[dict[str, object], dict[str, object]]:
    font, font_evidence = find_font()
    tick_font = font.font_variant(size=13) if isinstance(font, ImageFont.FreeTypeFont) else font
    label_width = 330
    reference_width = 205
    cell_width = 225
    row_height = 286
    header_height = 84
    width = label_width + reference_width + 6 * cell_width
    height = header_height + len(review_items) * row_height
    canvas = Image.new("RGB", (width, height), "#15191f")
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 12), "CF7 PORTRAIT / SEMANTIC FEATURE REFINEMENT", font=font, fill="#F2F5F8")
    draw.text((18, 40), subtitle, font=font, fill="#9EABB8")
    for row_index, item in enumerate(review_items):
        top = header_height + row_index * row_height
        blocked = bool(item["blocked"])
        fill = "#341E22" if blocked else ("#1C222A" if row_index % 2 == 0 else "#181E25")
        draw.rectangle((0, top, width, top + row_height - 1), fill=fill)
        draw.line((0, top, width, top), fill="#3C4653")
        draw.text((16, top + 14), item["reviewCode"], font=font, fill="#FF9DA7" if blocked else "#7DD3FC")
        draw.text((16, top + 43), str(item["category"])[:28], font=font, fill="#D8DEE7")
        draw.text((16, top + 72), f"variant={item['variantKey']}", font=font, fill="#AEB8C4")
        if blocked:
            draw.text((16, top + 112), f"BLOCKED: {item['sourceClassification']}", font=font, fill="#FF8D98")
            continue
        policy = item["intentPolicy"]
        draw.text((16, top + 105), f"default={policy['defaultMode']}", font=font, fill="#F0C674")
        draw.text((16, top + 134), "human=adjustment", font=font, fill="#F0C674")
        reference_left = label_width
        draw.text((reference_left + 8, top + 8), "OLD REF", font=font, fill="#B7F0D8")
        ref_box = (reference_left + 8, top + 38, reference_left + reference_width - 8, top + row_height - 12)
        canvas.paste(checker((ref_box[2] - ref_box[0], ref_box[3] - ref_box[1])), (ref_box[0], ref_box[1]))
        if item.get("oldReference"):
            with Image.open(ROOT / item["oldReference"]["path"]) as reference:
                paste_contained(canvas, reference.convert("RGBA"), ref_box)
        else:
            draw.text((ref_box[0] + 28, ref_box[1] + 90), "NO OLD REF", font=font, fill="#7F8B99")
        for candidate_index, candidate in enumerate(item["candidates"]):
            cell_left = label_width + reference_width + candidate_index * cell_width
            draw.text(
                (cell_left + 8, top + 8),
                f"C{candidate_index + 1:02d} / f{candidate['frame']}",
                font=font,
                fill="#F0C674",
            )
            candidate_box = (cell_left + 7, top + 38, cell_left + cell_width - 7, top + row_height - 12)
            with Image.open(ROOT / candidate["artifact"]["path"]) as source:
                paste_gridded_candidate(canvas, source.convert("RGBA"), candidate_box, tick_font)
    output_path = output_dir / output_name
    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    return artifact(output_path), font_evidence


def parse_svg_dimension(value: str | None, label: str) -> float:
    if not isinstance(value, str):
        raise PilotError(f"SVG 缺 {label}")
    normalized = value.strip()
    if normalized.endswith("px"):
        normalized = normalized[:-2]
    try:
        parsed = float(normalized)
    except ValueError as error:
        raise PilotError(f"SVG {label} 非数值：{value}") from error
    if not math.isfinite(parsed) or parsed <= 0:
        raise PilotError(f"SVG {label} 必须为正数：{value}")
    return parsed


def svg_canvas_size(svg_path: Path) -> tuple[float, float]:
    root = ET.parse(svg_path).getroot()
    return parse_svg_dimension(root.get("width"), "width"), parse_svg_dimension(root.get("height"), "height")


def export_vector_candidate_sources(
    output_dir: Path,
    entities: list[dict[str, object]],
    review_items: list[dict[str, object]],
    parent_manifest: dict[str, object],
) -> tuple[dict[str, object], list[dict[str, object]], list[dict[str, object]]]:
    ffdec = verify_ffdec()
    parent_swf_records = {
        record["path"]: record for record in parent_manifest.get("sourceEnvelope", {}).get("sourceSwfs", [])
    }
    unique_by_swf: dict[str, list[dict[str, object]]] = {}
    for entity in entities:
        if entity["sourceClassification"] == "unique":
            unique_by_swf.setdefault(entity["sourceSwf"], []).append(entity)

    ffdec_runs: list[dict[str, object]] = []
    swf_evidence: list[dict[str, object]] = []
    for source_index, (swf_rel, source_entities) in enumerate(sorted(unique_by_swf.items()), start=1):
        swf_path = ROOT / swf_rel
        parent_record = parent_swf_records.get(swf_rel)
        if parent_record is None:
            raise PilotError(f"父批未绑定来源 SWF：{swf_rel}")
        verify_artifact_record(parent_record, f"父来源 SWF {swf_rel}")
        current_record = artifact(swf_path)
        swf_evidence.append(current_record)
        export_dir = output_dir / "ffdec-svg" / f"source-{source_index:03d}"
        export_dir.mkdir(parents=True)
        ffdec_runs.append(
            run_ffdec(
                [
                    "-onerror",
                    "abort",
                    "-ignorebackground",
                    "-selectid",
                    ",".join(str(entity["renderCharacterId"]) for entity in source_entities),
                    "-format",
                    "sprite:svg",
                    "-export",
                    "sprite",
                    str(export_dir),
                    str(swf_path),
                ],
                output_dir,
                f"source-{source_index:03d}-svg",
                timeout_seconds=600,
            )
        )
        for entity in source_entities:
            matches = list(export_dir.glob(f"DefineSprite_{entity['renderCharacterId']}*"))
            if len(matches) != 1 or not matches[0].is_dir():
                raise PilotError(
                    f"FFDec SVG 目录不唯一：{entity['portraitRef']} id={entity['renderCharacterId']} matches={len(matches)}"
                )
            sprite_dir = matches[0]
            entity["vectorSourceStrategy"] = "ffdec_sprite_svg_exact_man_frame"
            entity["vectorSpriteDirectory"] = repo_rel(sprite_dir)
            for candidate in entity["candidates"]:
                svg_path = sprite_dir / f"{candidate['frame']}.svg"
                if not svg_path.is_file():
                    raise PilotError(f"FFDec SVG 缺候选帧：{entity['portraitRef']} frame={candidate['frame']}")
                svg_width, svg_height = svg_canvas_size(svg_path)
                source_width, source_height = (float(value) for value in candidate["sourceSize"])
                ratio_x = source_width / svg_width
                ratio_y = source_height / svg_height
                if not 1.95 <= ratio_x <= 2.05 or not 1.95 <= ratio_y <= 2.05:
                    raise PilotError(
                        f"父 zoom=2 栅格与 SVG 画布映射不闭合：{candidate['candidateId']} ratio={ratio_x:.4f},{ratio_y:.4f}"
                    )
                candidate["vectorArtifact"] = artifact(svg_path)
                candidate["vectorCanvasSize"] = [svg_width, svg_height]
                candidate["rasterToVectorScale"] = [ratio_x, ratio_y]

    candidates_by_id = {
        candidate["candidateId"]: candidate
        for entity in entities
        for candidate in entity["candidates"]
    }
    for item in review_items:
        item["candidates"] = [candidates_by_id[candidate["candidateId"]] for candidate in item["candidates"]]
    return ffdec, ffdec_runs, swf_evidence


def refine(args: argparse.Namespace) -> None:
    output_dir = ensure_below(Path(args.output), PILOT_ROOT, "输出目录")
    if output_dir.exists():
        raise PilotError(f"输出目录已存在，禁止覆盖：{output_dir}")
    profile_path = Path(args.profile).resolve() if args.profile else FEATURE_PROFILE_PATH
    ensure_below(profile_path, ROOT, "特征精修 profile")
    profile = load_json(profile_path)
    if not isinstance(profile, dict):
        raise PilotError("特征精修 profile 顶层必须是对象")
    validate_feature_profile(profile)
    parent = load_refinement_parent(Path(args.source_batch))
    batch_id = args.batch_id or profile["batchId"]
    if not isinstance(batch_id, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", batch_id) is None:
        raise PilotError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    output_dir.mkdir(parents=True)

    parent_manifest = parent["manifest"]
    decisions = parent["decisions"]["decisions"]
    refinement_keys = set(parent["refinementKeys"])
    review_items = json.loads(
        json.dumps(
            [item for item in parent_manifest["reviewItems"] if item["reviewKey"] in refinement_keys],
            ensure_ascii=False,
        )
    )
    entity_codes = {item["entityCode"] for item in review_items}
    entities = json.loads(
        json.dumps(
            [entity for entity in parent_manifest["entities"] if entity["entityCode"] in entity_codes],
            ensure_ascii=False,
        )
    )
    if len(review_items) != len(refinement_keys) or len(entities) != len(entity_codes):
        raise PilotError("选择性精修审核项与实体闭包不一致")
    policies = profile["categoryPolicies"]
    review_overrides = profile.get("reviewKeyOverrides", {})
    for item in review_items:
        decision = decisions[item["reviewKey"]]
        item["humanFeedback"] = {
            "status": decision["status"],
            "notes": decision["notes"].strip(),
            "updatedAt": decision["updatedAt"],
        }
        if not item["blocked"]:
            policy = policies.get(item["category"])
            if not isinstance(policy, dict):
                raise PilotError(f"缺类别特征策略：{item['category']}")
            resolved_policy = json.loads(json.dumps(policy, ensure_ascii=False))
            override = review_overrides.get(item["reviewKey"])
            if isinstance(override, dict):
                resolved_policy["reasoningHint"] = (
                    f"{resolved_policy['reasoningHint']} {override['reasoningHint']}"
                )
                resolved_policy["requiredFeatureRegion"] = override["requiredFeatureRegion"]
                resolved_policy["requiredMustIncludeRegion"] = override["requiredMustIncludeRegion"]
                resolved_policy["constraintSource"] = "manual_review_key_override"
            item["intentPolicy"] = resolved_policy
        else:
            item["intentPolicy"] = None
        for candidate in item["candidates"]:
            verify_artifact_record(candidate["artifact"], f"父候选 {candidate['candidateId']}")
        if item.get("oldReference"):
            verify_artifact_record(item["oldReference"], f"旧参考 {item['reviewKey']}")

    ffdec, ffdec_runs, swf_evidence = export_vector_candidate_sources(
        output_dir,
        entities,
        review_items,
        parent_manifest,
    )
    contact_sheet, font_evidence = build_feature_contact_sheet(
        output_dir,
        review_items,
        "feature-contact-sheet.png",
        "OLD REF is composition context. Candidate grids map exact PNG-normalized coordinates 0..1.",
    )
    eligible_items = [item for item in review_items if not item["blocked"]]
    model_batches: list[dict[str, object]] = []
    for batch_index, start in enumerate(range(0, len(eligible_items), 4), start=1):
        batch_items = eligible_items[start : start + 4]
        model_batch_id = f"feature-batch-{batch_index:02d}"
        batch_sheet, _ = build_feature_contact_sheet(
            output_dir,
            batch_items,
            f"{model_batch_id}.png",
            f"{model_batch_id}: {len(batch_items)} rows. Infer the signature feature, then read boxes from the exact grid.",
        )
        model_batches.append(
            {
                "modelBatchId": model_batch_id,
                "reviewKeys": [item["reviewKey"] for item in batch_items],
                "contactSheet": batch_sheet,
            }
        )
    parent_records = [artifact(path) for path in parent["paths"].values()]
    source_envelope = {
        "batchId": batch_id,
        "mode": "semantic_feature_refinement_selective",
        "profile": artifact(profile_path),
        "sourceFiles": [artifact(profile_path), *parent_records],
        "ffdec": ffdec,
        "sourceSwfs": swf_evidence,
        "parentSourceDigest": parent_manifest["sourceDigest"],
        "parentManifestDigest": parent_manifest["manifestDigest"],
        "parentReviewDigest": parent["reviewData"]["reviewDigest"],
        "parentReceiptDigest": parent["receipt"]["receiptDigest"],
        "pillowVersion": PILLOW_VERSION,
        "font": font_evidence,
    }
    source_digest = sha256_bytes(stable_bytes(source_envelope))
    manifest = {
        "schema": "cf7.enemy-portrait-feature-refinement-candidates.v2",
        "phase": "P3_FEATURE_REFINEMENT",
        "status": "human_feedback_bound",
        "productionReady": False,
        "batchId": batch_id,
        "createdAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "sourceDigest": source_digest,
        "sourceEnvelope": source_envelope,
        "parent": {
            "batchId": parent_manifest["batchId"],
            "sourceDigest": parent_manifest["sourceDigest"],
            "manifestDigest": parent_manifest["manifestDigest"],
            "reviewDigest": parent["reviewData"]["reviewDigest"],
            "receiptDigest": parent["receipt"]["receiptDigest"],
            "artAcceptance": False,
            "refinementKeys": sorted(parent["refinementKeys"]),
            "carriedPassKeys": sorted(parent["carriedPassKeys"]),
            "blockedKeys": sorted(parent["blockedKeys"]),
        },
        "featureContract": {
            "global": profile["globalContract"],
            "geometry": profile["geometry"],
            "highResolutionRender": profile["highResolutionRender"],
            "categoryPolicies": profile["categoryPolicies"],
        },
        "counts": {
            "identityCount": len(entities),
            "reviewUnitCount": len(review_items),
            "eligibleReviewUnitCount": len(eligible_items),
            "blockedReviewUnitCount": len(review_items) - len(eligible_items),
        },
        "ffdecRuns": ffdec_runs,
        "contactSheet": contact_sheet,
        "modelBatches": model_batches,
        "entities": entities,
        "reviewItems": review_items,
        "gates": {
            "parentHumanFeedbackBound": True,
            "selectiveRefinementOnly": True,
            "semanticFeatureRequired": True,
            "sourceBlockersNonSignable": True,
            "humanReviewRequired": True,
            "productionWrites": False,
        },
    }
    manifest["manifestDigest"] = sha256_bytes(stable_bytes(manifest))
    manifest_path = output_dir / "candidate-manifest.json"
    write_json(manifest_path, manifest)
    print(
        json.dumps(
            {
                "status": manifest["status"],
                "output": repo_rel(output_dir),
                "manifest": repo_rel(manifest_path),
                "manifestDigest": manifest["manifestDigest"],
                "sourceDigest": source_digest,
                "parentReceiptDigest": parent["receipt"]["receiptDigest"],
                "eligible": len(eligible_items),
                "blocked": len(review_items) - len(eligible_items),
            },
            ensure_ascii=False,
        )
    )


def prepare(args: argparse.Namespace) -> None:
    output_dir = ensure_below(Path(args.output), PILOT_ROOT, "输出目录")
    if output_dir.exists():
        raise PilotError(f"输出目录已存在，禁止覆盖：{output_dir}")
    output_dir.mkdir(parents=True)

    fixture = load_json(FIXTURE_PATH)
    if not isinstance(fixture, dict):
        raise PilotError("代表集 JSON 必须是对象")
    validate_fixture(fixture)
    asset_records = parse_asset_map()
    enemy_ids, pet_ids, enemy_files = load_consumers()
    ffdec = verify_ffdec()

    source_files = [FIXTURE_PATH, ASSET_MAP_PATH, ENEMY_LIST_PATH, PETS_PATH, *enemy_files]
    source_file_evidence = [artifact(path) for path in source_files]
    entities: list[dict[str, object]] = []
    review_items: list[dict[str, object]] = []
    unique_by_swf: dict[str, list[dict[str, object]]] = {}

    for entity_index, fixture_entity in enumerate(fixture["entities"], start=1):
        portrait_ref = fixture_entity["portraitRef"]
        map_record = asset_records.get(portrait_ref, {"classification": "missing", "sources": []})
        classification = map_record["classification"]
        if classification != fixture_entity["expectedClassification"]:
            raise PilotError(
                f"代表集来源分类漂移：{portrait_ref} expected={fixture_entity['expectedClassification']} actual={classification}"
            )
        entity_code = f"e{entity_index:02d}"
        entity = {
            "entityCode": entity_code,
            "portraitRef": portrait_ref,
            "category": fixture_entity["category"],
            "notes": fixture_entity["notes"],
            "variantResolution": fixture_entity.get("variantResolution", "automatic_default"),
            "sourceClassification": classification,
            "sources": map_record["sources"],
            "consumers": {
                "enemy": portrait_ref in enemy_ids,
                "petIds": sorted(pet_ids.get(portrait_ref, [])),
            },
            "candidates": [],
        }
        entities.append(entity)
        if classification == "unique":
            source = map_record["sources"][0]
            unique_by_swf.setdefault(source["swf"], []).append(entity)
        for variant in fixture_entity["variants"]:
            review_code = f"R{len(review_items) + 1:02d}"
            old_reference = variant["oldReference"]
            old_artifact = None
            if old_reference is not None:
                old_path = ROOT / old_reference
                if not old_path.is_file():
                    raise PilotError(f"旧头像参考缺失：{old_reference}")
                old_artifact = artifact(old_path)
            review_items.append(
                {
                    "reviewCode": review_code,
                    "reviewKey": f"{portrait_ref}::{variant['variantKey']}",
                    "entityCode": entity_code,
                    "portraitRef": portrait_ref,
                    "variantKey": variant["variantKey"],
                    "variantResolution": fixture_entity.get("variantResolution", "automatic_default"),
                    "category": fixture_entity["category"],
                    "sourceClassification": classification,
                    "blocked": classification != "unique",
                    "blockReason": None if classification == "unique" else f"source_{classification}",
                    "oldReference": old_artifact,
                    "candidates": [],
                }
            )

    ffdec_runs: list[dict[str, object]] = []
    swf_evidence: list[dict[str, object]] = []
    for source_index, (swf_rel, source_entities) in enumerate(sorted(unique_by_swf.items()), start=1):
        swf_path = ROOT / swf_rel
        if not swf_path.is_file():
            raise PilotError(f"来源 SWF 缺失：{swf_rel}")
        swf_evidence.append(artifact(swf_path))
        xml_path = output_dir / "ffdec-xml" / f"source-{source_index:03d}.xml"
        xml_path.parent.mkdir(parents=True, exist_ok=True)
        ffdec_runs.append(
            run_ffdec(
                ["-onerror", "abort", "-swf2xml", str(swf_path), str(xml_path)],
                output_dir,
                f"source-{source_index:03d}-xml",
            )
        )
        exports = export_assets_from_xml(xml_path)
        frame_counts = sprite_frame_counts(xml_path)
        render_character_ids: list[int] = []
        for entity in source_entities:
            matches = exports.get(entity["portraitRef"], [])
            if len(matches) != 1:
                raise PilotError(
                    f"linkage → characterId 不唯一：{entity['portraitRef']} matches={matches} source={swf_rel}"
                )
            character_id = matches[0]
            if character_id not in frame_counts:
                raise PilotError(f"linkage 不是可导出的 DefineSprite：{entity['portraitRef']} id={character_id}")
            man_character_id = first_frame_named_instance(xml_path, character_id, "man")
            render_character_id = man_character_id or character_id
            if render_character_id not in frame_counts:
                raise PilotError(
                    f"渲染目标不是 DefineSprite：{entity['portraitRef']} root={character_id} render={render_character_id}"
                )
            entity["characterId"] = character_id
            entity["declaredFrameCount"] = frame_counts[character_id]
            entity["renderCharacterId"] = render_character_id
            entity["renderDeclaredFrameCount"] = frame_counts[render_character_id]
            entity["renderStrategy"] = (
                "first_frame_named_man_instance" if man_character_id is not None else "linkage_root_fallback"
            )
            entity["renderStrategyWarning"] = None if man_character_id is not None else "named_man_missing"
            entity["sourceSwf"] = swf_rel
            render_character_ids.append(render_character_id)
        export_dir = output_dir / "ffdec-gif" / f"source-{source_index:03d}"
        export_dir.mkdir(parents=True)
        ffdec_runs.append(
            run_ffdec(
                [
                    "-onerror",
                    "abort",
                    "-ignorebackground",
                    "-zoom",
                    "2",
                    "-selectid",
                    ",".join(str(value) for value in sorted(set(render_character_ids))),
                    "-format",
                    "sprite:gif",
                    "-export",
                    "sprite",
                    str(export_dir),
                    str(swf_path),
                ],
                output_dir,
                f"source-{source_index:03d}-gif",
            )
        )
        for entity in source_entities:
            matches = list(export_dir.glob(f"DefineSprite_{entity['renderCharacterId']}*/frames.gif"))
            if len(matches) != 1:
                raise PilotError(
                    f"FFDec GIF 产物不唯一：{entity['portraitRef']} id={entity['renderCharacterId']} matches={len(matches)}"
                )
            gif_path = matches[0]
            inspected = inspect_gif_frames(gif_path)
            if not inspected:
                raise PilotError(f"FFDec GIF 没有非空帧：{entity['portraitRef']}")
            selected = choose_evenly(inspected, int(fixture["maxCandidatesPerReview"]))
            candidates = save_selected_frames(
                gif_path,
                selected,
                output_dir / "candidates" / entity["entityCode"],
                entity["entityCode"],
            )
            entity["ffdecXml"] = artifact(xml_path)
            entity["ffdecGif"] = artifact(gif_path)
            with Image.open(gif_path) as exported_gif:
                entity["exportedFrameCount"] = sum(1 for _ in ImageSequence.Iterator(exported_gif))
            entity["usableUniqueFrameCount"] = len(inspected)
            entity["candidates"] = candidates

    entity_by_code = {entity["entityCode"]: entity for entity in entities}
    for item in review_items:
        item["candidates"] = entity_by_code[item["entityCode"]]["candidates"]
    eligible_count = sum(not item["blocked"] for item in review_items)
    blocker_count = sum(bool(item["blocked"]) for item in review_items)
    if eligible_count != 12 or blocker_count != 3:
        raise PilotError(f"代表集闭包错误：eligible={eligible_count} blocker={blocker_count}")

    contact_sheet, font_evidence = build_contact_sheet(output_dir, review_items)
    eligible_review_items = [item for item in review_items if not item["blocked"]]
    model_batches: list[dict[str, object]] = []
    for batch_index, start in enumerate(range(0, len(eligible_review_items), 4), start=1):
        batch_items = eligible_review_items[start : start + 4]
        batch_id = f"model-batch-{batch_index:02d}"
        batch_sheet, _ = build_contact_sheet(
            output_dir,
            batch_items,
            f"{batch_id}.png",
            f"{batch_id}: exactly {len(batch_items)} eligible rows; return each global review key once.",
        )
        model_batches.append(
            {
                "modelBatchId": batch_id,
                "reviewKeys": [item["reviewKey"] for item in batch_items],
                "contactSheet": batch_sheet,
            }
        )
    source_envelope = {
        "batchId": fixture["batchId"],
        "fixture": artifact(FIXTURE_PATH),
        "sourceFiles": source_file_evidence,
        "ffdec": ffdec,
        "sourceSwfs": swf_evidence,
        "pillowVersion": PILLOW_VERSION,
        "font": font_evidence,
    }
    source_digest = sha256_bytes(stable_bytes(source_envelope))
    manifest = {
        "schema": "cf7.enemy-portrait-candidates.v1",
        "phase": "P2",
        "status": "frames_extracted",
        "productionReady": False,
        "batchId": fixture["batchId"],
        "createdAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "sourceDigest": source_digest,
        "sourceEnvelope": source_envelope,
        "counts": {
            "identityCount": len(entities),
            "reviewUnitCount": len(review_items),
            "eligibleReviewUnitCount": eligible_count,
            "blockedReviewUnitCount": blocker_count,
        },
        "ffdecRuns": ffdec_runs,
        "contactSheet": contact_sheet,
        "modelBatches": model_batches,
        "entities": entities,
        "reviewItems": review_items,
        "gates": {
            "sourceBlockersNonSignable": True,
            "humanReviewRequired": True,
            "productionWrites": False,
        },
    }
    manifest["manifestDigest"] = sha256_bytes(stable_bytes(manifest))
    manifest_path = output_dir / "candidate-manifest.json"
    write_json(manifest_path, manifest)
    print(
        json.dumps(
            {
                "status": manifest["status"],
                "output": repo_rel(output_dir),
                "manifest": repo_rel(manifest_path),
                "manifestDigest": manifest["manifestDigest"],
                "sourceDigest": source_digest,
                "eligible": eligible_count,
                "blocked": blocker_count,
            },
            ensure_ascii=False,
        )
    )


def verify_manifest(manifest_path: Path) -> dict[str, object]:
    manifest = load_json(manifest_path)
    supported = {
        "cf7.enemy-portrait-candidates.v1",
        "cf7.enemy-portrait-feature-refinement-candidates.v1",
        "cf7.enemy-portrait-feature-refinement-candidates.v2",
    }
    if not isinstance(manifest, dict) or manifest.get("schema") not in supported:
        raise PilotError("候选 manifest schema 不受支持")
    manifest_digest = manifest.get("manifestDigest")
    without_digest = dict(manifest)
    without_digest.pop("manifestDigest", None)
    computed = sha256_bytes(stable_bytes(without_digest))
    if computed != manifest_digest:
        raise PilotError("候选 manifestDigest 不匹配")
    for item in manifest["reviewItems"]:
        for candidate in item["candidates"]:
            candidate_path = ROOT / candidate["artifact"]["path"]
            if sha256_file(candidate_path) != candidate["artifact"]["sha256"]:
                raise PilotError(f"候选 artifact hash 不匹配：{candidate_path}")
            if candidate.get("vectorArtifact"):
                verify_artifact_record(candidate["vectorArtifact"], f"候选 SVG {candidate['candidateId']}")
    return manifest


def render_selection(source: Image.Image, crop_box: list[float]) -> Image.Image:
    if len(crop_box) != 4 or any(not isinstance(value, (int, float)) for value in crop_box):
        raise PilotError("模型 cropBox 非法")
    x0, y0, x1, y1 = (float(value) for value in crop_box)
    if not (0 <= x0 < x1 <= 1 and 0 <= y0 < y1 <= 1):
        raise PilotError(f"模型 cropBox 越界：{crop_box}")
    if x1 - x0 < 0.2 or y1 - y0 < 0.2:
        raise PilotError(f"模型 cropBox 过窄：{crop_box}")
    left = max(0, min(source.width - 1, math.floor(x0 * source.width)))
    top = max(0, min(source.height - 1, math.floor(y0 * source.height)))
    right = max(left + 1, min(source.width, math.ceil(x1 * source.width)))
    bottom = max(top + 1, min(source.height, math.ceil(y1 * source.height)))
    crop = source.crop((left, top, right, bottom))
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    safe = 456
    scale = min(safe / crop.width, safe / crop.height)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    resized = crop.resize(size, Image.Resampling.LANCZOS)
    canvas.alpha_composite(resized, ((512 - size[0]) // 2, (512 - size[1]) // 2))
    return canvas


def normalized_box(value: object, label: str) -> tuple[float, float, float, float]:
    if (
        not isinstance(value, list)
        or len(value) != 4
        or any(not isinstance(entry, (int, float)) or not math.isfinite(float(entry)) for entry in value)
    ):
        raise PilotError(f"{label} 必须是四个有限数字")
    x0, y0, x1, y1 = (float(entry) for entry in value)
    if not 0 <= x0 < x1 <= 1 or not 0 <= y0 < y1 <= 1:
        raise PilotError(f"{label} 越出 0..1 或顺序错误：{value}")
    return x0, y0, x1, y1


def compute_feature_view_box(
    candidate: dict[str, object],
    selection: dict[str, object],
    geometry_contract: dict[str, object],
    intent_policy: dict[str, object] | None = None,
) -> dict[str, object]:
    feature = normalized_box(selection.get("featureBox"), "featureBox")
    must_include = normalized_box(selection.get("mustIncludeBox"), "mustIncludeBox")
    tolerance = 1e-6
    if (
        feature[0] < must_include[0] - tolerance
        or feature[1] < must_include[1] - tolerance
        or feature[2] > must_include[2] + tolerance
        or feature[3] > must_include[3] + tolerance
    ):
        raise PilotError(f"featureBox 必须包含在 mustIncludeBox 内：{candidate['candidateId']}")
    if isinstance(intent_policy, dict):
        for box, field in (
            (feature, "requiredFeatureRegion"),
            (must_include, "requiredMustIncludeRegion"),
        ):
            required_value = intent_policy.get(field)
            if required_value is None:
                continue
            required = normalized_box(required_value, field)
            if (
                box[0] > required[0] + tolerance
                or box[1] > required[1] + tolerance
                or box[2] < required[2] - tolerance
                or box[3] < required[3] - tolerance
            ):
                raise PilotError(
                    f"人工维护特征区域未被模型方框完整包含：{candidate['candidateId']} {field}={required_value}"
                )
    mode = selection.get("framingMode")
    modes = geometry_contract.get("modes", {})
    config = modes.get(mode) if isinstance(modes, dict) else None
    if not isinstance(config, dict):
        raise PilotError(f"framingMode 不受支持：{mode}")
    safe = float(geometry_contract["mustIncludeSafeMargin"])
    width = float(candidate["width"])
    height = float(candidate["height"])
    fx0, fy0, fx1, fy1 = feature[0] * width, feature[1] * height, feature[2] * width, feature[3] * height
    mx0, my0, mx1, my1 = (
        must_include[0] * width,
        must_include[1] * height,
        must_include[2] * width,
        must_include[3] * height,
    )
    feature_width = fx1 - fx0
    feature_height = fy1 - fy0
    must_width = mx1 - mx0
    must_height = my1 - my0
    usable = 1 - 2 * safe
    side = max(
        feature_width / float(config["featureWidthOccupancy"]),
        feature_height / float(config["featureHeightOccupancy"]),
        must_width / usable,
        must_height / usable,
        8.0,
    )
    anchor_x, anchor_y = (float(value) for value in config["featureAnchor"])
    feature_center_x = (fx0 + fx1) / 2
    feature_center_y = (fy0 + fy1) / 2
    desired_left = feature_center_x - anchor_x * side
    desired_top = feature_center_y - anchor_y * side
    left_lower = mx1 - (1 - safe) * side
    left_upper = mx0 - safe * side
    top_lower = my1 - (1 - safe) * side
    top_upper = my0 - safe * side
    if left_lower > left_upper + tolerance or top_lower > top_upper + tolerance:
        raise PilotError(f"安全边距几何不可满足：{candidate['candidateId']}")
    left = min(max(desired_left, left_lower), left_upper)
    top = min(max(desired_top, top_lower), top_upper)

    crop_left, crop_top, _, _ = (float(value) for value in candidate["sourceCropBounds"])
    ratio_x, ratio_y = (float(value) for value in candidate["rasterToVectorScale"])
    center_vector_x = (crop_left + left + side / 2) / ratio_x
    center_vector_y = (crop_top + top + side / 2) / ratio_y
    vector_side = max(side / ratio_x, side / ratio_y)
    vector_left = center_vector_x - vector_side / 2
    vector_top = center_vector_y - vector_side / 2

    def map_box(box: tuple[float, float, float, float]) -> list[float]:
        x0, y0, x1, y1 = box
        full_x0 = (crop_left + x0 * width) / ratio_x
        full_y0 = (crop_top + y0 * height) / ratio_y
        full_x1 = (crop_left + x1 * width) / ratio_x
        full_y1 = (crop_top + y1 * height) / ratio_y
        return [
            (full_x0 - vector_left) / vector_side,
            (full_y0 - vector_top) / vector_side,
            (full_x1 - vector_left) / vector_side,
            (full_y1 - vector_top) / vector_side,
        ]

    rendered_feature = map_box(feature)
    rendered_must = map_box(must_include)
    if min(rendered_must[0], rendered_must[1]) < safe - 0.005 or max(rendered_must[2], rendered_must[3]) > 1 - safe + 0.005:
        raise PilotError(f"高分辨率映射后 mustInclude 安全边距失守：{candidate['candidateId']}")
    rendered_width = rendered_feature[2] - rendered_feature[0]
    rendered_height = rendered_feature[3] - rendered_feature[1]
    rendered_long = max(rendered_width, rendered_height)
    rendered_short = min(rendered_width, rendered_height)
    minimum_long = float(config["minimumRenderedFeatureLongAxisOccupancy"])
    minimum_short = float(config["minimumRenderedFeatureShortAxisOccupancy"])
    if rendered_long + tolerance < minimum_long or rendered_short + tolerance < minimum_short:
        raise PilotError(
            f"特征占比不满足 {mode} 下限：{candidate['candidateId']} "
            f"actual={rendered_long:.4f}/{rendered_short:.4f} minimum={minimum_long:.4f}/{minimum_short:.4f}"
        )
    return {
        "featureLabel": selection["featureLabel"],
        "framingMode": mode,
        "featureBox": list(feature),
        "mustIncludeBox": list(must_include),
        "candidateCropWindow": [left, top, side, side],
        "vectorViewBox": [vector_left, vector_top, vector_side, vector_side],
        "renderedFeatureBox": rendered_feature,
        "renderedFeatureLongAxisOccupancy": rendered_long,
        "renderedFeatureShortAxisOccupancy": rendered_short,
        "minimumRenderedFeatureLongAxisOccupancy": minimum_long,
        "minimumRenderedFeatureShortAxisOccupancy": minimum_short,
        "renderedMustIncludeBox": rendered_must,
        "mustIncludeSafeMargin": safe,
        "safeMarginVerified": True,
        "virtualTransparentPadding": vector_left < 0 or vector_top < 0,
    }


def image_mean_absolute_error(left: Image.Image, right: Image.Image) -> tuple[float, list[float]]:
    if left.size != right.size:
        raise PilotError(f"保真度比较尺寸不一致：left={left.size} right={right.size}")
    def premultiplied(image: Image.Image) -> Image.Image:
        red, green, blue, alpha = image.convert("RGBA").split()
        return Image.merge(
            "RGBA",
            (
                ImageChops.multiply(red, alpha),
                ImageChops.multiply(green, alpha),
                ImageChops.multiply(blue, alpha),
                alpha,
            ),
        )

    difference = ImageChops.difference(premultiplied(left), premultiplied(right))
    per_channel = [float(value) for value in ImageStat.Stat(difference).mean]
    return sum(per_channel) / len(per_channel), per_channel


def candidate_from_high_resolution(
    source: Image.Image,
    candidate: dict[str, object],
) -> tuple[Image.Image, tuple[float, float]]:
    source_width, source_height = (float(value) for value in candidate["sourceSize"])
    if source_width <= 0 or source_height <= 0:
        raise PilotError(f"候选 sourceSize 非法：{candidate['candidateId']}")
    scale_x = source.width / source_width
    scale_y = source.height / source_height
    if abs(scale_x - scale_y) / max(scale_x, scale_y) > 0.01:
        raise PilotError(f"高分辨率逐帧缩放非等比：{candidate['candidateId']}={scale_x:.6f},{scale_y:.6f}")
    crop_left, crop_top, crop_right, crop_bottom = (
        float(value) for value in candidate["sourceCropBounds"]
    )
    candidate_width = int(candidate["width"])
    candidate_height = int(candidate["height"])
    restored = source.transform(
        (candidate_width, candidate_height),
        Image.Transform.EXTENT,
        (
            crop_left * scale_x,
            crop_top * scale_y,
            crop_right * scale_x,
            crop_bottom * scale_y,
        ),
        Image.Resampling.BICUBIC,
    )
    return restored, (scale_x, scale_y)


def crop_high_resolution_selection(
    source: Image.Image,
    candidate: dict[str, object],
    geometry: dict[str, object],
    scale: tuple[float, float],
    target_size: int,
    minimum_size: int,
) -> tuple[Image.Image, dict[str, object]]:
    crop_left, crop_top, _, _ = (float(value) for value in candidate["sourceCropBounds"])
    window_left, window_top, window_width, window_height = (
        float(value) for value in geometry["candidateCropWindow"]
    )
    if abs(window_width - window_height) > 1e-6:
        raise PilotError(f"特征裁切窗口不是正方形：{candidate['candidateId']}")
    scale_x, scale_y = scale
    center_x = (crop_left + window_left + window_width / 2) * scale_x
    center_y = (crop_top + window_top + window_height / 2) * scale_y
    native_side = int(math.ceil(max(window_width * scale_x, window_height * scale_y)))
    if native_side < minimum_size:
        raise PilotError(
            f"高分辨率来源裁切不足：{candidate['candidateId']} actual={native_side} minimum={minimum_size}"
        )
    raw_left = int(round(center_x - native_side / 2))
    raw_top = int(round(center_y - native_side / 2))
    canvas = Image.new("RGBA", (native_side, native_side), (0, 0, 0, 0))
    source_left = max(0, raw_left)
    source_top = max(0, raw_top)
    source_right = min(source.width, raw_left + native_side)
    source_bottom = min(source.height, raw_top + native_side)
    if source_left >= source_right or source_top >= source_bottom:
        raise PilotError(f"高分辨率特征裁切完全越出来源：{candidate['candidateId']}")
    region = source.crop((source_left, source_top, source_right, source_bottom))
    canvas.alpha_composite(region, (source_left - raw_left, source_top - raw_top))
    if canvas.getchannel("A").getbbox() is None:
        raise PilotError(f"高分辨率特征裁切无可见像素：{candidate['candidateId']}")
    retained = canvas
    downsampled = native_side > target_size
    if downsampled:
        retained = canvas.resize((target_size, target_size), Image.Resampling.LANCZOS)
    return retained, {
        "sourceScale": [scale_x, scale_y],
        "sourceCenter": [center_x, center_y],
        "rawCropOrigin": [raw_left, raw_top],
        "nativeSourceCropSize": native_side,
        "retainedSupersampleSize": retained.width,
        "targetSupersampleSize": target_size,
        "downsampledToTarget": downsampled,
        "upscaled": False,
        "virtualTransparentPadding": (
            raw_left < 0
            or raw_top < 0
            or raw_left + native_side > source.width
            or raw_top + native_side > source.height
        ),
    }


def render_feature_refinement(
    manifest: dict[str, object],
    model_report: dict[str, object],
    output_dir: Path,
    render_report_path: Path,
) -> None:
    if model_report.get("schema") != "cf7.portrait-pilot-feature-model-report.v1":
        raise PilotError("特征精修模型报告 schema 不受支持")
    review_by_key = {item["reviewKey"]: item for item in manifest["reviewItems"] if not item["blocked"]}
    entities_by_code = {entity["entityCode"]: entity for entity in manifest["entities"]}
    geometry_contract = manifest.get("featureContract", {}).get("geometry")
    high_resolution_contract = manifest.get("featureContract", {}).get("highResolutionRender")
    if not isinstance(geometry_contract, dict):
        raise PilotError("特征精修 manifest 缺 geometry contract")
    if not isinstance(high_resolution_contract, dict):
        raise PilotError("特征精修 manifest 缺 highResolutionRender contract")
    target_size = int(high_resolution_contract["targetSupersampleSize"])
    minimum_size = int(high_resolution_contract["minimumSourceCropSize"])
    maximum_frame_dimension = int(high_resolution_contract["maximumSourceFrameDimension"])
    maximum_zoom = int(high_resolution_contract["maximumZoom"])
    fidelity_limit = float(high_resolution_contract["fidelityMeanAbsoluteErrorLimit"])

    row_specs: list[dict[str, object]] = []
    seen_job_ids: set[str] = set()
    seen_roles: set[str] = set()
    for run in model_report["runs"]:
        role = run["role"]
        seen_roles.add(role)
        for selection in run["result"]["selections"]:
            item = review_by_key.get(selection["reviewKey"])
            if item is None:
                raise PilotError(f"特征模型报告含未知或阻断审核键：{selection['reviewKey']}")
            entity = entities_by_code.get(item["entityCode"])
            if entity is None:
                raise PilotError(f"审核项找不到实体：{item['reviewKey']}")
            candidates = {candidate["candidateId"]: candidate for candidate in item["candidates"]}
            candidate = candidates.get(selection["candidateId"])
            if candidate is None:
                raise PilotError(f"特征模型报告候选不在白名单：{selection['candidateId']}")
            entity_candidate = next(
                (entry for entry in entity["candidates"] if entry["candidateId"] == candidate["candidateId"]),
                None,
            )
            if entity_candidate is None or entity_candidate["vectorArtifact"] != candidate["vectorArtifact"]:
                raise PilotError(f"实体与审核项候选闭包不一致：{candidate['candidateId']}")
            verify_artifact_record(candidate["vectorArtifact"], f"SVG 几何候选 {candidate['candidateId']}")
            verify_artifact_record(candidate["artifact"], f"栅格保真度候选 {candidate['candidateId']}")
            geometry = compute_feature_view_box(candidate, selection, geometry_contract, item.get("intentPolicy"))
            job_id = f"{role}-{item['reviewCode']}"
            if job_id in seen_job_ids:
                raise PilotError(f"重复高分辨率渲染 job：{job_id}")
            seen_job_ids.add(job_id)
            requested_zoom = max(1, int(math.ceil(target_size / float(geometry["vectorViewBox"][2]))))
            row_specs.append(
                {
                    "jobId": job_id,
                    "role": role,
                    "item": item,
                    "entity": entity,
                    "candidate": candidate,
                    "selection": selection,
                    "geometry": geometry,
                    "requestedZoom": requested_zoom,
                }
            )
    expected_rows = len(review_by_key) * 2
    if seen_roles != {"proposal", "independent_review"} or len(row_specs) != expected_rows:
        raise PilotError(
            f"特征精修渲染行数或角色不闭合：roles={sorted(seen_roles)} "
            f"expected={expected_rows} actual={len(row_specs)}"
        )

    source_swf_records = {
        record["path"]: record for record in manifest.get("sourceEnvelope", {}).get("sourceSwfs", [])
    }
    groups: dict[tuple[str, int], dict[str, object]] = {}
    for spec in row_specs:
        entity = spec["entity"]
        key = (entity["sourceSwf"], int(entity["renderCharacterId"]))
        group = groups.setdefault(
            key,
            {
                "sourceSwf": key[0],
                "characterId": key[1],
                "frames": set(),
                "specs": [],
            },
        )
        group["frames"].add(int(spec["candidate"]["frame"]))
        group["specs"].append(spec)

    attempt_number = 1
    while (
        (output_dir / f"selected-frame-exporter-classes-v{attempt_number}").exists()
        or (output_dir / f"selected-high-resolution-v{attempt_number}").exists()
        or (output_dir / f"renders-v{attempt_number}").exists()
    ):
        attempt_number += 1
    attempt_tag = f"v{attempt_number}"
    render_root = output_dir / f"renders-{attempt_tag}"
    adapter = compile_selected_frame_exporter(output_dir, attempt_tag)
    selected_frame_records: dict[tuple[str, int, int], dict[str, object]] = {}
    high_resolution_runs: list[dict[str, object]] = []
    for group_index, (key, group) in enumerate(sorted(groups.items()), start=1):
        source_swf, character_id = key
        source_record = source_swf_records.get(source_swf)
        if source_record is None:
            raise PilotError(f"特征精修 manifest 未绑定来源 SWF：{source_swf}")
        swf_path = verify_artifact_record(source_record, f"来源 SWF {source_swf}")
        maximum_canvas_axis = max(
            max(float(value) for value in spec["candidate"]["vectorCanvasSize"])
            for spec in group["specs"]
        )
        zoom_cap_from_frame = int(math.floor(maximum_frame_dimension / maximum_canvas_axis))
        requested_zoom = max(int(spec["requestedZoom"]) for spec in group["specs"])
        selected_zoom = min(requested_zoom, zoom_cap_from_frame, maximum_zoom)
        if selected_zoom < 1:
            raise PilotError(f"高分辨率逐帧无法满足画布上限：{source_swf} id={character_id}")
        for spec in group["specs"]:
            estimated_crop = float(spec["geometry"]["vectorViewBox"][2]) * selected_zoom
            if estimated_crop + 1 < minimum_size:
                raise PilotError(
                    f"高分辨率逐帧在上限内仍不足：{spec['jobId']} "
                    f"estimated={estimated_crop:.2f} minimum={minimum_size} zoom={selected_zoom}"
                )
            spec["selectedZoom"] = selected_zoom
        frames = sorted(group["frames"])
        group_id = f"source-{group_index:03d}-character-{character_id}"
        run, records = export_selected_sprite_frames(
            adapter,
            output_dir,
            swf_path,
            character_id,
            frames,
            selected_zoom,
            group_id,
            attempt_tag,
        )
        run["groupId"] = group_id
        run["requestedZoom"] = requested_zoom
        run["maximumZoomFromFrameDimension"] = zoom_cap_from_frame
        run["maximumSourceFrameDimension"] = maximum_frame_dimension
        high_resolution_runs.append(run)
        for frame, record in records.items():
            selected_frame_records[(source_swf, character_id, frame)] = record

    rows: list[dict[str, object]] = []
    png_bytes = 0
    webp_bytes = 0
    source_supersample_bytes = 0
    fidelity_values: list[float] = []
    for spec in row_specs:
        entity = spec["entity"]
        candidate = spec["candidate"]
        selection = spec["selection"]
        frame_key = (entity["sourceSwf"], int(entity["renderCharacterId"]), int(candidate["frame"]))
        high_resolution_record = selected_frame_records.get(frame_key)
        if high_resolution_record is None:
            raise PilotError(f"选定高分辨率帧未闭合：{spec['jobId']}")
        high_resolution_path = verify_artifact_record(high_resolution_record, f"高分辨率帧 {spec['jobId']}")
        candidate_path = verify_artifact_record(candidate["artifact"], f"保真度候选 {spec['jobId']}")
        selected_zoom = int(spec["selectedZoom"])
        with Image.open(high_resolution_path) as high_resolution_image:
            high_resolution = high_resolution_image.convert("RGBA")
        vector_width, vector_height = (float(value) for value in candidate["vectorCanvasSize"])
        expected_width = vector_width * selected_zoom
        expected_height = vector_height * selected_zoom
        if abs(high_resolution.width - expected_width) > 2 or abs(high_resolution.height - expected_height) > 2:
            raise PilotError(
                f"高分辨率帧与 SVG 几何画布不一致：{spec['jobId']} "
                f"actual={high_resolution.size} expected={expected_width:.2f}x{expected_height:.2f}"
            )
        restored_candidate, source_scale = candidate_from_high_resolution(high_resolution, candidate)
        with Image.open(candidate_path) as candidate_image:
            candidate_rgba = candidate_image.convert("RGBA")
        fidelity_mean, fidelity_channels = image_mean_absolute_error(restored_candidate, candidate_rgba)
        if fidelity_mean > fidelity_limit:
            raise PilotError(
                f"高分辨率帧保真度失败：{spec['jobId']} mean={fidelity_mean:.4f} limit={fidelity_limit:.4f}"
            )
        fidelity_values.append(fidelity_mean)
        supersample, crop_mapping = crop_high_resolution_selection(
            high_resolution,
            candidate,
            spec["geometry"],
            source_scale,
            target_size,
            minimum_size,
        )
        if supersample.width != supersample.height or supersample.width < minimum_size or supersample.width > target_size:
            raise PilotError(f"保留超采样尺寸非法：{spec['jobId']}={supersample.size}")
        role_dir = render_root / spec["role"] / spec["item"]["reviewCode"]
        role_dir.mkdir(parents=True, exist_ok=True)
        supersample_path = role_dir / "source-supersample.png"
        master_path = role_dir / "master-512.png"
        webp_path = role_dir / "preview-80-lossless.webp"
        if any(path.exists() for path in (supersample_path, master_path, webp_path)):
            raise PilotError(f"高分辨率渲染产物已存在，拒绝覆盖：{spec['jobId']}")
        supersample.save(supersample_path, format="PNG", optimize=False, compress_level=9)
        master = supersample.resize((512, 512), Image.Resampling.LANCZOS)
        if master.getchannel("A").getbbox() is None:
            raise PilotError(f"最终 512 头像无可见像素：{spec['jobId']}")
        master.save(master_path, format="PNG", optimize=False, compress_level=9)
        previews: dict[str, dict[str, object]] = {}
        for size in (80, 48, 32):
            preview = master.resize((size, size), Image.Resampling.LANCZOS)
            preview_path = role_dir / f"preview-{size}.png"
            if preview_path.exists():
                raise PilotError(f"预览产物已存在，拒绝覆盖：{preview_path}")
            preview.save(preview_path, format="PNG", optimize=False, compress_level=9)
            previews[str(size)] = artifact(preview_path)
            png_bytes += preview_path.stat().st_size
        master.resize((80, 80), Image.Resampling.LANCZOS).save(
            webp_path,
            format="WEBP",
            lossless=True,
            method=6,
        )
        png_bytes += master_path.stat().st_size
        webp_bytes += webp_path.stat().st_size
        source_supersample_bytes += supersample_path.stat().st_size
        rows.append(
            {
                "role": spec["role"],
                "reviewCode": spec["item"]["reviewCode"],
                "reviewKey": spec["item"]["reviewKey"],
                "candidateId": candidate["candidateId"],
                "frame": candidate["frame"],
                "featureLabel": selection["featureLabel"],
                "framingMode": selection["framingMode"],
                "featureBox": selection["featureBox"],
                "mustIncludeBox": selection["mustIncludeBox"],
                "geometry": spec["geometry"],
                "confidence": selection["confidence"],
                "flags": selection["flags"],
                "sourceCandidate": candidate["artifact"],
                "sourceGeometrySvg": candidate["vectorArtifact"],
                "sourceHighResolution": high_resolution_record,
                "sourceSupersample": artifact(supersample_path),
                "sourceSupersampleSize": supersample.width,
                "selectedFrameZoom": selected_zoom,
                "cropMapping": crop_mapping,
                "fidelityComparison": {
                    "metric": "premultiplied RGBA mean absolute error",
                    "meanAbsoluteError": fidelity_mean,
                    "perChannel": {
                        "red": fidelity_channels[0],
                        "green": fidelity_channels[1],
                        "blue": fidelity_channels[2],
                        "alpha": fidelity_channels[3],
                    },
                    "limit": fidelity_limit,
                    "passed": True,
                },
                "master": artifact(master_path),
                "previews": previews,
                "webp80Lossless": artifact(webp_path),
            }
        )

    source_high_resolution_bytes = sum(
        int(record["bytes"])
        for run in high_resolution_runs
        for record in run["outputs"]
    )
    report = {
        "schema": "cf7.portrait-pilot-render-report.v4",
        "status": "automated_checked",
        "productionReady": False,
        "batchId": manifest["batchId"],
        "sourceDigest": manifest["sourceDigest"],
        "manifestDigest": manifest["manifestDigest"],
        "modelReportDigest": model_report["reportDigest"],
        "renderAttempt": attempt_tag,
        "selectedFrameAdapter": adapter,
        "highResolutionRuns": high_resolution_runs,
        "renderer": {
            "controllerSource": artifact(Path(__file__)),
            "python": sys.version.split()[0],
            "pillow": PILLOW_VERSION,
            "pixelSource": "FFDec FrameExporter API selected exact man frame PNG",
            "geometrySource": "FFDec sprite:svg exact man frame, mapping only",
            "targetSupersampleSize": target_size,
            "minimumSourceCropSize": minimum_size,
            "maximumSourceFrameDimension": maximum_frame_dimension,
            "maximumZoom": maximum_zoom,
            "masterSize": 512,
            "previewSizes": [80, 48, 32],
            "transparent": True,
            "virtualCropPadding": True,
            "noUpscale": True,
        },
        "fidelitySummary": {
            "comparison": "selected high-resolution frame mapped back to the bound P2 candidate in premultiplied RGBA; invisible transparent-palette RGB is ignored",
            "meanAbsoluteErrorLimit": fidelity_limit,
            "maximumMeanAbsoluteError": max(fidelity_values),
            "averageMeanAbsoluteError": sum(fidelity_values) / len(fidelity_values),
            "passedRows": len(fidelity_values),
        },
        "formatComparison": {
            "pngBytes": png_bytes,
            "webp80LosslessBytes": webp_bytes,
            "selectedHighResolutionFrameBytes": source_high_resolution_bytes,
            "sourceSupersampleBytes": source_supersample_bytes,
            "note": "PNG 总量含 512/80/48/32；WebP 总量仅含 80px lossless；选帧原图与最高 4096 的保真裁切是证据/母版，不进入产品体积比较。",
        },
        "rows": rows,
        "gates": {
            "semanticFeatureExplicit": True,
            "renderedFeatureOccupancyChecked": True,
            "mustIncludeSafeMarginChecked": True,
            "selectedFramesOnly": True,
            "frameSpecificTransformsPreserved": True,
            "geometrySvgNotUsedAsPixels": True,
            "noCandidateRasterUpscale": True,
            "minimumSourceCropSizeChecked": True,
            "dimensionsAndAlphaChecked": True,
            "artifactHashesClosed": True,
            "humanReviewRequired": True,
            "productionWrites": False,
        },
    }
    report["renderDigest"] = sha256_bytes(stable_bytes(report))
    write_json(render_report_path, report)
    print(
        json.dumps(
            {
                "status": report["status"],
                "report": repo_rel(render_report_path),
                "renderDigest": report["renderDigest"],
                "rows": len(rows),
                "selectedFrameRuns": len(high_resolution_runs),
                "maximumFidelityMeanAbsoluteError": max(fidelity_values),
            },
            ensure_ascii=False,
        )
    )


def render(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve()
    report_path = Path(args.model_report).resolve()
    manifest = verify_manifest(manifest_path)
    model_report = load_json(report_path)
    if not isinstance(model_report, dict) or model_report.get("schema") not in {
        "cf7.portrait-pilot-model-report.v1",
        "cf7.portrait-pilot-feature-model-report.v1",
    }:
        raise PilotError("模型报告 schema 不受支持")
    verify_digest_object(model_report, "reportDigest", "模型报告")
    if model_report.get("sourceDigest") != manifest["sourceDigest"]:
        raise PilotError("模型报告 sourceDigest 已陈旧")
    output_dir = ensure_below(manifest_path.parent, PILOT_ROOT, "候选批目录")
    render_report_path = output_dir / "render-report.json"
    if render_report_path.exists():
        raise PilotError("render-report.json 已存在，禁止覆盖")

    if manifest.get("phase") == "P3_FEATURE_REFINEMENT":
        render_feature_refinement(manifest, model_report, output_dir, render_report_path)
        return

    review_by_key = {item["reviewKey"]: item for item in manifest["reviewItems"] if not item["blocked"]}
    rows: list[dict[str, object]] = []
    png_bytes = 0
    webp_bytes = 0
    for run in model_report["runs"]:
        role = run["role"]
        selections = run["result"]["selections"]
        for selection in selections:
            item = review_by_key.get(selection["reviewKey"])
            if item is None:
                raise PilotError(f"模型报告含未知或阻断审核键：{selection['reviewKey']}")
            candidates = {candidate["candidateId"]: candidate for candidate in item["candidates"]}
            candidate = candidates.get(selection["candidateId"])
            if candidate is None:
                raise PilotError(f"模型报告候选不在白名单：{selection['candidateId']}")
            source_path = ROOT / candidate["artifact"]["path"]
            with Image.open(source_path) as image:
                master = render_selection(image.convert("RGBA"), selection["cropBox"])
            role_dir = output_dir / "renders" / role / item["reviewCode"]
            role_dir.mkdir(parents=True, exist_ok=True)
            master_path = role_dir / "master-512.png"
            master.save(master_path, format="PNG", optimize=False, compress_level=9)
            previews: dict[str, dict[str, object]] = {}
            for size in (80, 48, 32):
                preview = master.resize((size, size), Image.Resampling.LANCZOS)
                preview_path = role_dir / f"preview-{size}.png"
                preview.save(preview_path, format="PNG", optimize=False, compress_level=9)
                previews[str(size)] = artifact(preview_path)
                png_bytes += preview_path.stat().st_size
            webp_path = role_dir / "preview-80-lossless.webp"
            master.resize((80, 80), Image.Resampling.LANCZOS).save(
                webp_path,
                format="WEBP",
                lossless=True,
                method=6,
            )
            png_bytes += master_path.stat().st_size
            webp_bytes += webp_path.stat().st_size
            rows.append(
                {
                    "role": role,
                    "reviewCode": item["reviewCode"],
                    "reviewKey": item["reviewKey"],
                    "candidateId": selection["candidateId"],
                    "frame": candidate["frame"],
                    "cropBox": selection["cropBox"],
                    "focalPoint": selection["focalPoint"],
                    "confidence": selection["confidence"],
                    "flags": selection["flags"],
                    "sourceCandidate": candidate["artifact"],
                    "master": artifact(master_path),
                    "previews": previews,
                    "webp80Lossless": artifact(webp_path),
                }
            )
    expected_rows = len(review_by_key) * 2
    if len(rows) != expected_rows:
        raise PilotError(f"确定性渲染行数不闭合：expected={expected_rows} actual={len(rows)}")
    report = {
        "schema": "cf7.portrait-pilot-render-report.v1",
        "status": "automated_checked",
        "productionReady": False,
        "batchId": manifest["batchId"],
        "sourceDigest": manifest["sourceDigest"],
        "manifestDigest": manifest["manifestDigest"],
        "modelReportDigest": model_report["reportDigest"],
        "renderer": {
            "python": sys.version.split()[0],
            "pillow": PILLOW_VERSION,
            "masterSize": 512,
            "previewSizes": [80, 48, 32],
            "transparent": True,
        },
        "formatComparison": {
            "pngBytes": png_bytes,
            "webp80LosslessBytes": webp_bytes,
            "note": "PNG 总量含 512/80/48/32；WebP 总量仅含 80px lossless，不作等量压缩率结论。",
        },
        "rows": rows,
        "gates": {
            "dimensionsAndAlphaChecked": True,
            "artifactHashesClosed": True,
            "humanReviewRequired": True,
            "productionWrites": False,
        },
    }
    report["renderDigest"] = sha256_bytes(stable_bytes(report))
    write_json(render_report_path, report)
    print(
        json.dumps(
            {
                "status": report["status"],
                "report": repo_rel(render_report_path),
                "renderDigest": report["renderDigest"],
                "rows": len(rows),
            },
            ensure_ascii=False,
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.set_defaults(handler=prepare)
    refine_parser = subparsers.add_parser("refine")
    refine_parser.add_argument("--source-batch", required=True)
    refine_parser.add_argument("--output", required=True)
    refine_parser.add_argument("--profile")
    refine_parser.add_argument("--batch-id")
    refine_parser.set_defaults(handler=refine)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--manifest", required=True)
    render_parser.add_argument("--model-report", required=True)
    render_parser.set_defaults(handler=render)
    args = parser.parse_args()
    try:
        args.handler(args)
    except PilotError as error:
        print(f"[portrait-pilot] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
