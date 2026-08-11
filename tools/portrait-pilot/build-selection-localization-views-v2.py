#!/usr/bin/env python3
"""Build selection-locked localization views without consuming discarded feature geometry."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

import prepare_pilot as core
from prepare_pilot import compile_selected_frame_exporter


ROOT = Path(__file__).resolve().parents[2]
PORTRAIT_TMP = ROOT / "tmp" / "portrait-pilot"
VIEW_SCHEMA = "cf7.portrait-pilot-localization-views.v1"
SOURCE_SCHEMA = "cf7.portrait-pilot-selection-source-data.v1"
LOCK_SCHEMA = "cf7.portrait-pilot-selection-lock.v1"
SOURCE_NAME = "selection-source-data.json"
VIEW_NAME = "localization-view-manifest.json"


class ViewError(RuntimeError):
    pass


def stable_bytes(value: object) -> bytes:
    def normalize(entry: object) -> object:
        if isinstance(entry, dict):
            return {key: normalize(child) for key, child in entry.items()}
        if isinstance(entry, list):
            return [normalize(child) for child in entry]
        if isinstance(entry, float) and entry.is_integer():
            return int(entry)
        return entry

    return json.dumps(normalize(value), ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def repo_rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def artifact(path: Path) -> dict[str, object]:
    path = path.resolve()
    return {"path": repo_rel(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def export_selected_sprite_frames_compatible(
    adapter: dict[str, object],
    output_dir: Path,
    swf_path: Path,
    character_id: int,
    frames: list[int],
    zoom: int,
    group_id: str,
    attempt_tag: str,
) -> tuple[dict[str, object], dict[int, dict[str, object]]]:
    """Accept FFDec's unique linkage suffix without weakening id binding."""
    export_root = output_dir / f"selected-high-resolution-{attempt_tag}" / group_id
    if export_root.exists():
        raise ViewError(f"高分辨率逐帧目录已存在：{export_root}")
    frame_csv = ",".join(str(frame) for frame in frames)
    java_record = adapter.get("java")
    if not isinstance(java_record, dict) or not isinstance(java_record.get("path"), str):
        raise ViewError("selected-frame adapter java 记录不闭合")
    run = core.run_logged_tool(
        [
            java_record["path"],
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
    sprite_directories = [
        child
        for child in export_root.iterdir()
        if child.is_dir() and re.fullmatch(rf"DefineSprite_{character_id}(?:_.+)?", child.name)
    ]
    if len(sprite_directories) != 1:
        raise ViewError(
            f"FFDec selected frame 目录不唯一：id={character_id} matches={len(sprite_directories)}"
        )
    records: dict[int, dict[str, object]] = {}
    for frame in frames:
        frame_path = sprite_directories[0] / f"{frame}.png"
        if not frame_path.is_file():
            raise ViewError(f"FFDec selected frame 缺失：id={character_id} frame={frame}")
        records[frame] = artifact(frame_path)
    actual_files = [child for child in export_root.rglob("*") if child.is_file()]
    if len(actual_files) != len(frames):
        raise ViewError(
            f"FFDec selected frame 输出不精确：id={character_id} expected={len(frames)} actual={len(actual_files)}"
        )
    return {
        **run,
        "sourceSwf": artifact(swf_path),
        "characterId": character_id,
        "frames": frames,
        "zoom": zoom,
        "spriteDirectory": repo_rel(sprite_directories[0]),
        "outputs": [records[frame] for frame in frames],
    }, records


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ViewError(f"{label} 读取失败：{error}") from error
    if not isinstance(value, dict):
        raise ViewError(f"{label} 必须是对象")
    return value


def verify_digest(value: dict[str, Any], field: str, label: str) -> None:
    digest = value.get(field)
    envelope = dict(value)
    envelope.pop(field, None)
    if not isinstance(digest, str) or sha256_bytes(stable_bytes(envelope)) != digest:
        raise ViewError(f"{label} {field} 不匹配")


def resolve_repo(value: str, label: str) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError as error:
        raise ViewError(f"{label} 越界") from error
    if not path.is_file():
        raise ViewError(f"{label} 缺失：{path}")
    return path


def resolve_output(value: str, must_exist: bool) -> Path:
    output = (ROOT / value).resolve()
    try:
        output.relative_to(PORTRAIT_TMP)
    except ValueError as error:
        raise ViewError("output 必须位于 tmp/portrait-pilot") from error
    if output == PORTRAIT_TMP:
        raise ViewError("output 不能是 portrait-pilot 根目录")
    if must_exist and not output.is_dir():
        raise ViewError("localization output 缺失")
    if not must_exist and output.exists():
        raise ViewError("localization output 已存在，禁止覆盖")
    return output


def verify_record(record: object, label: str) -> Path:
    if not isinstance(record, dict) or not isinstance(record.get("path"), str):
        raise ViewError(f"{label} artifact 非法")
    path = resolve_repo(record["path"], label)
    if path.stat().st_size != record.get("bytes") or sha256_file(path) != record.get("sha256"):
        raise ViewError(f"{label} artifact 字节闭包不匹配")
    return path


def checkerboard(size: tuple[int, int], cell: int) -> Image.Image:
    image = Image.new("RGBA", size, (31, 36, 43, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2 == 0:
                draw.rectangle((x, y, min(size[0] - 1, x + cell - 1), min(size[1] - 1, y + cell - 1)), fill=(45, 52, 61, 255))
    return image


def render_view(
    source_path: Path,
    candidate: dict[str, Any],
    output_path: Path,
    max_dimension: int,
) -> tuple[list[int], list[int], list[int]]:
    with Image.open(source_path) as opened:
        source = opened.convert("RGBA")
    source_size = candidate.get("sourceSize")
    crop_bounds = candidate.get("sourceCropBounds")
    if not isinstance(source_size, list) or len(source_size) != 2 or not isinstance(crop_bounds, list) or len(crop_bounds) != 4:
        raise ViewError(f"候选源坐标非法：{candidate.get('candidateId')}")
    scale_x = source.width / float(source_size[0])
    scale_y = source.height / float(source_size[1])
    left = round(float(crop_bounds[0]) * scale_x)
    top = round(float(crop_bounds[1]) * scale_y)
    right = round(float(crop_bounds[2]) * scale_x)
    bottom = round(float(crop_bounds[3]) * scale_y)
    if left < 0 or top < 0 or right > source.width or bottom > source.height or left >= right or top >= bottom:
        raise ViewError(f"高分辨率候选裁切越界：{candidate.get('candidateId')} {[left, top, right, bottom]}/{source.size}")
    cropped = source.crop((left, top, right, bottom))
    if max(cropped.size) + 2 < max_dimension:
        raise ViewError(f"高分辨率候选不足以生成无放大定位图：{candidate.get('candidateId')} {cropped.size}")
    resize_scale = min(1.0, max_dimension / max(cropped.size))
    target_size = (max(1, round(cropped.width * resize_scale)), max(1, round(cropped.height * resize_scale)))
    if target_size != cropped.size:
        cropped = cropped.resize(target_size, Image.Resampling.LANCZOS)
    background = checkerboard(cropped.size, max(16, round(max(cropped.size) / 64)))
    background.alpha_composite(cropped)
    overlay = Image.new("RGBA", background.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    line_width = max(1, round(max(background.size) / 900))
    for index in range(11):
        x = round(index * (background.width - 1) / 10)
        y = round(index * (background.height - 1) / 10)
        color = (100, 235, 255, 150) if index in (0, 5, 10) else (255, 255, 255, 75)
        draw.line((x, 0, x, background.height - 1), fill=color, width=line_width)
        draw.line((0, y, background.width - 1, y), fill=color, width=line_width)
        if 0 < index < 10:
            label = f".{index}"
            draw.text((x + 3, 3), label, fill=(255, 255, 255, 210), stroke_width=1, stroke_fill=(0, 0, 0, 220))
            draw.text((3, y + 2), label, fill=(255, 255, 255, 210), stroke_width=1, stroke_fill=(0, 0, 0, 220))
    background.alpha_composite(overlay)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    background.convert("RGB").save(output_path, format="PNG", optimize=True)
    return [left, top, right, bottom], [background.width, background.height], [source.width, source.height]


def load_inputs(args: argparse.Namespace) -> tuple[Path, dict[str, Any], Path, dict[str, Any]]:
    manifest_path = resolve_repo(args.manifest, "manifest")
    manifest = read_json(manifest_path, "manifest")
    verify_digest(manifest, "manifestDigest", "manifest")
    if manifest.get("phase") != "P3_FEATURE_REFINEMENT" or manifest.get("productionReady") is not False:
        raise ViewError("manifest phase/productionReady 非法")
    lock_path = resolve_repo(args.selection_lock, "selection lock")
    lock = read_json(lock_path, "selection lock")
    verify_digest(lock, "selectionDigest", "selection lock")
    if lock.get("schema") != LOCK_SCHEMA or lock.get("productionReady") is not False:
        raise ViewError("selection lock schema/productionReady 非法")
    bound_manifest = verify_record(lock.get("input", {}).get("manifest"), "selection lock manifest")
    verify_record(lock.get("input", {}).get("modelReport"), "selection lock model report")
    verify_record(lock.get("controller"), "selection lock controller")
    lock_manifest_digest = lock.get("input", {}).get("manifestDigest")
    if bound_manifest != manifest_path:
        experiment = manifest.get("sourceEnvelope", {}).get("promptExperiment")
        parent = experiment.get("parentManifest") if isinstance(experiment, dict) else None
        parent_path = verify_record(parent, "prompt experiment parent manifest") if isinstance(parent, dict) else None
        if (
            parent_path != bound_manifest
            or parent.get("manifestDigest") != lock_manifest_digest
            or experiment.get("candidatePixelsReusedWithoutChange") is not True
            or experiment.get("targetHumanGeometryTransmittedToModel") is not False
        ):
            raise ViewError("selection lock 未绑定当前 manifest 或其像素不变的显式父 manifest")
    elif lock_manifest_digest != manifest.get("manifestDigest"):
        raise ViewError("selection lock manifestDigest 与当前 manifest 不一致")
    return manifest_path, manifest, lock_path, lock


def selected_specs(manifest: dict[str, Any], lock: dict[str, Any], max_dimension: int) -> list[dict[str, Any]]:
    items = {item["reviewKey"]: item for item in manifest.get("reviewItems", []) if not item.get("blocked")}
    entities = {entity["entityCode"]: entity for entity in manifest.get("entities", [])}
    locks = {row.get("reviewKey"): row for row in lock.get("rows", [])}
    if len(locks) != len(lock.get("rows", [])) or set(locks) != set(items):
        raise ViewError("selection lock 与 manifest eligible reviewKey 不闭合")
    specs: list[dict[str, Any]] = []
    for review_key in sorted(items):
        item = items[review_key]
        row = locks[review_key]
        entity = entities.get(item.get("entityCode"))
        if not isinstance(entity, dict):
            raise ViewError(f"manifest entity 缺失：{review_key}")
        candidate = next((entry for entry in item.get("candidates", []) if entry.get("candidateId") == row.get("candidateId")), None)
        if not isinstance(candidate, dict):
            raise ViewError(f"锁定候选不在 manifest：{review_key}/{row.get('candidateId')}")
        verify_record(row.get("candidateArtifact"), f"selection lock candidate {review_key}")
        verify_record(candidate.get("artifact"), f"manifest candidate {review_key}")
        verify_record(candidate.get("vectorArtifact"), f"manifest vector candidate {review_key}")
        if row.get("candidateArtifact", {}).get("sha256") != candidate.get("artifact", {}).get("sha256"):
            raise ViewError(f"selection lock 候选 hash 漂移：{review_key}")
        scales = candidate.get("rasterToVectorScale")
        if not isinstance(scales, list) or len(scales) != 2 or min(float(value) for value in scales) <= 0:
            raise ViewError(f"rasterToVectorScale 非法：{review_key}")
        vector_crop_long = max(float(candidate["width"]) / float(scales[0]), float(candidate["height"]) / float(scales[1]))
        requested_zoom = max(1, math.ceil(max_dimension / vector_crop_long))
        specs.append({
            "reviewKey": review_key,
            "item": item,
            "entity": entity,
            "lock": row,
            "candidate": candidate,
            "requestedZoom": requested_zoom,
        })
    return specs


def build(args: argparse.Namespace) -> dict[str, Any]:
    if args.max_dimension < 1024 or args.max_dimension > 4096:
        raise ViewError("max-dimension 必须为 1024–4096")
    manifest_path, manifest, lock_path, lock = load_inputs(args)
    output = resolve_output(args.output, False)
    output.mkdir(parents=True)
    specs = selected_specs(manifest, lock, args.max_dimension)
    high_contract = manifest.get("featureContract", {}).get("highResolutionRender", {})
    maximum_frame_dimension = int(high_contract.get("maximumSourceFrameDimension", 0))
    maximum_zoom = int(high_contract.get("maximumZoom", 0))
    if maximum_frame_dimension < args.max_dimension or maximum_zoom < 1:
        raise ViewError("manifest 高分辨率合同非法")
    source_records = {record["path"]: record for record in manifest.get("sourceEnvelope", {}).get("sourceSwfs", [])}
    groups: dict[tuple[str, int], dict[str, Any]] = {}
    for spec in specs:
        entity = spec["entity"]
        key = (entity["sourceSwf"], int(entity["renderCharacterId"]))
        group = groups.setdefault(key, {"sourceSwf": key[0], "characterId": key[1], "frames": set(), "specs": []})
        group["frames"].add(int(spec["candidate"]["frame"]))
        group["specs"].append(spec)
    adapter = compile_selected_frame_exporter(output, "localization-v2")
    selected_frames: dict[tuple[str, int, int], dict[str, object]] = {}
    export_runs: list[dict[str, Any]] = []
    for index, (key, group) in enumerate(sorted(groups.items()), start=1):
        source_swf, character_id = key
        source_record = source_records.get(source_swf)
        if not isinstance(source_record, dict):
            raise ViewError(f"manifest 未绑定来源 SWF：{source_swf}")
        swf_path = verify_record(source_record, f"来源 SWF {source_swf}")
        maximum_canvas_axis = max(max(float(value) for value in spec["candidate"]["vectorCanvasSize"]) for spec in group["specs"])
        zoom_cap = math.floor(maximum_frame_dimension / maximum_canvas_axis)
        requested_zoom = max(int(spec["requestedZoom"]) for spec in group["specs"])
        selected_zoom = min(requested_zoom, zoom_cap, maximum_zoom)
        if selected_zoom < requested_zoom:
            raise ViewError(
                f"定位图在有界帧合同内无法保持 {args.max_dimension}px 真源：{source_swf} id={character_id} "
                f"requested={requested_zoom} selected={selected_zoom}"
            )
        for spec in group["specs"]:
            spec["selectedZoom"] = selected_zoom
        frames = sorted(group["frames"])
        group_id = f"source-{index:03d}-character-{character_id}"
        run, records = export_selected_sprite_frames_compatible(
            adapter,
            output,
            swf_path,
            character_id,
            frames,
            selected_zoom,
            group_id,
            "localization-v2",
        )
        run["groupId"] = group_id
        run["requestedZoom"] = requested_zoom
        run["maximumZoomFromFrameDimension"] = zoom_cap
        run["maximumSourceFrameDimension"] = maximum_frame_dimension
        export_runs.append(run)
        for frame, record in records.items():
            selected_frames[(source_swf, character_id, frame)] = record
    rows: list[dict[str, Any]] = []
    source_rows: list[dict[str, Any]] = []
    for spec in specs:
        entity = spec["entity"]
        candidate = spec["candidate"]
        key = (entity["sourceSwf"], int(entity["renderCharacterId"]), int(candidate["frame"]))
        high_record = selected_frames.get(key)
        if not isinstance(high_record, dict):
            raise ViewError(f"锁定帧高分辨率导出未闭合：{spec['reviewKey']}")
        high_path = verify_record(high_record, f"锁定帧 {spec['reviewKey']}")
        view_path = output / "views" / f"{spec['item']['reviewCode']}-{candidate['candidateId']}.png"
        pixel_crop, view_size, source_size = render_view(high_path, candidate, view_path, args.max_dimension)
        row = {
            "reviewCode": spec["item"]["reviewCode"],
            "reviewKey": spec["reviewKey"],
            "lockedRole": spec["lock"]["lockedRole"],
            "candidateId": candidate["candidateId"],
            "candidateArtifact": candidate["artifact"],
            "candidateWidth": candidate["width"],
            "candidateHeight": candidate["height"],
            "sourceSize": candidate["sourceSize"],
            "sourceCropBounds": candidate["sourceCropBounds"],
            "sourceHighResolution": high_record,
            "sourceHighResolutionSize": source_size,
            "sourceHighResolutionPixelCrop": pixel_crop,
            "selectedFrameZoom": spec["selectedZoom"],
            "viewSize": view_size,
            "view": artifact(view_path),
            "normalizedCoordinatesMatchCandidate": True,
        }
        rows.append(row)
        source_rows.append({
            "reviewCode": row["reviewCode"],
            "reviewKey": row["reviewKey"],
            "candidateId": row["candidateId"],
            "candidateArtifact": row["candidateArtifact"],
            "sourceGeometrySvg": candidate["vectorArtifact"],
            "sourceHighResolution": high_record,
            "selectedFrameZoom": spec["selectedZoom"],
            "featureGeometryConsumed": False,
        })
    controller_files = [
        artifact(Path(__file__).resolve()),
        artifact(ROOT / "tools" / "portrait-pilot" / "build-localization-views.py"),
        artifact(ROOT / "tools" / "portrait-pilot" / "prepare_pilot.py"),
    ]
    sanitized_adapter = {key: value for key, value in adapter.items() if key != "runtimeClasspath"}
    source_data: dict[str, Any] = {
        "schema": SOURCE_SCHEMA,
        "status": "selection_source_frames_ready",
        "productionReady": False,
        "generatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "input": {
            "manifest": artifact(manifest_path),
            "manifestDigest": manifest["manifestDigest"],
            "sourceDigest": manifest["sourceDigest"],
            "selectionLock": artifact(lock_path),
            "selectionDigest": lock["selectionDigest"],
        },
        "renderContract": {
            "purpose": "selected_frame_localization_only",
            "maxDimension": args.max_dimension,
            "maximumSourceFrameDimension": maximum_frame_dimension,
            "maximumZoom": maximum_zoom,
            "featureGeometryConsumed": False,
            "candidatePixelsChanged": False,
        },
        "adapter": sanitized_adapter,
        "exportRuns": export_runs,
        "controller": {"files": controller_files, "sourceClosureDigest": sha256_bytes(stable_bytes(controller_files))},
        "rows": source_rows,
        "counts": {"rows": len(source_rows), "sourceGroups": len(export_runs), "uniqueFrames": len(selected_frames)},
        "gates": {
            "deterministicSelectionLock": True,
            "exactCandidateHashBinding": True,
            "featureGeometryConsumed": False,
            "humanTargetGeometryExcluded": True,
            "boundedSourceFrameDecode": True,
            "productionWrites": False,
        },
    }
    source_data["sourceDataDigest"] = sha256_bytes(stable_bytes(source_data))
    source_path = output / SOURCE_NAME
    source_path.write_text(json.dumps(source_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report: dict[str, Any] = {
        "schema": VIEW_SCHEMA,
        "status": "localization_views_ready",
        "productionReady": False,
        "generatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "input": {
            "manifest": artifact(manifest_path),
            "manifestDigest": manifest["manifestDigest"],
            "sourceReviewData": artifact(source_path),
            "sourceReviewDigest": source_data["sourceDataDigest"],
            "lockRole": "deterministic_per_row",
            "selectionLock": artifact(lock_path),
            "selectionDigest": lock["selectionDigest"],
        },
        "renderContract": {
            "maxDimension": args.max_dimension,
            "gridStep": 0.1,
            "coordinateSpace": "locked candidate normalized 0..1",
            "targetHumanGeometryTransmitted": False,
            "sourceMode": "direct_locked_frame_export_v2",
        },
        "controller": artifact(Path(__file__).resolve()),
        "rows": rows,
        "counts": {"rows": len(rows), "uniqueViews": len({row["view"]["sha256"] for row in rows})},
        "gates": {
            "exactCandidateHashBinding": True,
            "deterministicSelectionLock": True,
            "highResolutionSourceVerified": True,
            "normalizedCandidateMapping": True,
            "featureGeometryConsumed": False,
            "humanTargetGeometryExcluded": True,
            "productionWrites": False,
        },
    }
    report["viewDigest"] = sha256_bytes(stable_bytes(report))
    (output / VIEW_NAME).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def check(args: argparse.Namespace) -> dict[str, Any]:
    output = resolve_output(args.output, True)
    source_path = output / SOURCE_NAME
    view_path = output / VIEW_NAME
    source_data = read_json(source_path, "selection source data")
    verify_digest(source_data, "sourceDataDigest", "selection source data")
    if source_data.get("schema") != SOURCE_SCHEMA or source_data.get("productionReady") is not False:
        raise ViewError("selection source data schema/productionReady 非法")
    verify_record(source_data.get("input", {}).get("manifest"), "source manifest")
    verify_record(source_data.get("input", {}).get("selectionLock"), "source selection lock")
    for record in source_data.get("controller", {}).get("files", []):
        verify_record(record, "source controller")
    if source_data.get("gates", {}).get("featureGeometryConsumed") is not False:
        raise ViewError("selection source data 消费了不应进入选帧阶段的 feature geometry")
    for row in source_data.get("rows", []):
        verify_record(row.get("candidateArtifact"), f"source candidate {row.get('reviewKey')}")
        verify_record(row.get("sourceGeometrySvg"), f"source SVG {row.get('reviewKey')}")
        verify_record(row.get("sourceHighResolution"), f"source high resolution {row.get('reviewKey')}")
        if row.get("featureGeometryConsumed") is not False:
            raise ViewError(f"source row geometry gate 非法：{row.get('reviewKey')}")
    report = read_json(view_path, "localization view manifest")
    verify_digest(report, "viewDigest", "localization view manifest")
    if report.get("schema") != VIEW_SCHEMA or report.get("status") != "localization_views_ready" or report.get("productionReady") is not False:
        raise ViewError("localization view manifest schema/status 非法")
    verify_record(report.get("input", {}).get("manifest"), "view manifest")
    bound_source = verify_record(report.get("input", {}).get("sourceReviewData"), "view source data")
    verify_record(report.get("input", {}).get("selectionLock"), "view selection lock")
    verify_record(report.get("controller"), "view controller")
    if bound_source != source_path or report.get("input", {}).get("sourceReviewDigest") != source_data.get("sourceDataDigest"):
        raise ViewError("localization view 未绑定 selection source data")
    rows = report.get("rows")
    if not isinstance(rows, list) or len(rows) != report.get("counts", {}).get("rows"):
        raise ViewError("localization view rows/counts 不闭合")
    if len(rows) != source_data.get("counts", {}).get("rows"):
        raise ViewError("localization view 与 source rows 不闭合")
    for row in rows:
        verify_record(row.get("candidateArtifact"), f"view candidate {row.get('reviewKey')}")
        verify_record(row.get("sourceHighResolution"), f"view high resolution {row.get('reviewKey')}")
        image_path = verify_record(row.get("view"), f"view {row.get('reviewKey')}")
        with Image.open(image_path) as image:
            if list(image.size) != row.get("viewSize"):
                raise ViewError(f"view 尺寸不匹配：{row.get('reviewKey')}")
        if row.get("normalizedCoordinatesMatchCandidate") is not True:
            raise ViewError(f"view 坐标映射未闭合：{row.get('reviewKey')}")
    if report.get("gates", {}).get("featureGeometryConsumed") is not False:
        raise ViewError("localization view 消费了 selection-stage feature geometry")
    return report


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    subparsers = result.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--manifest", required=True)
    render_parser.add_argument("--selection-lock", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--max-dimension", type=int, default=2048)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    return result


def main() -> None:
    args = parser().parse_args()
    report = build(args) if args.command == "render" else check(args)
    print(json.dumps({
        "status": report["status"] if args.command == "render" else "selection_localization_views_verified",
        "viewDigest": report["viewDigest"],
        "counts": report["counts"],
        "featureGeometryConsumed": report["gates"]["featureGeometryConsumed"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except ViewError as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1)
