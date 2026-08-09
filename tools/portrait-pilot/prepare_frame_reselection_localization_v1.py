#!/usr/bin/env python3
"""Prepare a one-row localization batch from a verified human frame selection."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import math
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageDraw

from prepare_pilot import (
    PILOT_ROOT,
    ROOT,
    PilotError,
    artifact,
    compile_selected_frame_exporter,
    export_selected_sprite_frames,
    load_json,
    repo_rel,
    sha256_bytes,
    stable_bytes,
    verify_artifact_record,
    verify_digest_object,
    write_json,
)


MANIFEST_SCHEMA = "cf7.enemy-portrait-feature-refinement-candidates.v2"
SOURCE_SCHEMA = "cf7.portrait-pilot-human-frame-selection-source-data.v1"
VIEW_SCHEMA = "cf7.portrait-pilot-localization-views.v1"
RECEIPT_SCHEMA = "cf7.enemy-portrait-frame-reselection-receipt.v1"


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def require_object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise PilotError(f"{label} 必须是对象")
    return value


def require_list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise PilotError(f"{label} 必须是数组")
    return value


def pilot_child(value: str, label: str, must_exist: bool) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise PilotError(f"{label} 必须位于 tmp/portrait-pilot 下") from error
    if must_exist and not path.is_dir():
        raise PilotError(f"{label} 不存在：{repo_rel(path)}")
    if not must_exist and path.exists():
        raise PilotError(f"{label} 已存在，禁止覆盖：{repo_rel(path)}")
    return path


def verify_frame_batch(batch_root: Path) -> tuple[dict[str, object], dict[str, object]]:
    completed = subprocess.run(
        [
            "node",
            str(ROOT / "tools/portrait-pilot/verify-frame-reselection.js"),
            "--batch",
            repo_rel(batch_root),
            "--check",
        ],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise PilotError(f"人类选帧回执验证失败：{detail}")
    data = require_object(load_json(batch_root / "frame-reselection-data.json"), "选帧数据")
    receipt = require_object(load_json(batch_root / "human-frame-reselection-receipt.json"), "选帧回执")
    if receipt.get("schema") != RECEIPT_SCHEMA or receipt.get("status") != "human_frame_reselection_verified":
        raise PilotError("选帧回执不是已验证 selected 状态")
    if receipt.get("datasetDigest") != data.get("datasetDigest") or receipt.get("sourceDigest") != data.get("sourceDigest"):
        raise PilotError("选帧回执与候选数据摘要不一致")
    return data, receipt


def unique_row(rows: object, key: str, value: object, label: str) -> dict[str, object]:
    matches = [row for row in require_list(rows, label) if isinstance(row, dict) and row.get(key) == value]
    if len(matches) != 1:
        raise PilotError(f"{label} 未命中唯一 {key}={value}")
    return matches[0]


def dedupe_artifacts(records: list[dict[str, object]]) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    seen: set[tuple[object, object]] = set()
    for record in records:
        key = (record.get("path"), record.get("sha256"))
        if key not in seen:
            result.append(record)
            seen.add(key)
    return result


def candidate_with_vector_scale(candidate: dict[str, object]) -> dict[str, object]:
    result = copy.deepcopy(candidate)
    source_size = require_list(result.get("sourceSize"), "候选 sourceSize")
    vector_size = require_list(result.get("vectorCanvasSize"), "候选 vectorCanvasSize")
    if len(source_size) != 2 or len(vector_size) != 2:
        raise PilotError("候选 sourceSize/vectorCanvasSize 非二维")
    scales = [float(source_size[index]) / float(vector_size[index]) for index in range(2)]
    if any(not 1.95 <= scale <= 2.05 for scale in scales):
        raise PilotError(f"选帧 PNG 与 SVG 画布不是受支持的 zoom=2 映射：{scales}")
    result["rasterToVectorScale"] = scales
    result["visualSha256"] = require_object(result.get("artifact"), "候选 PNG").get("sha256")
    return result


def build_manifest(
    parent_manifest: dict[str, object],
    parent_manifest_path: Path,
    frame_root: Path,
    data: dict[str, object],
    receipt: dict[str, object],
    selected_row: dict[str, object],
    candidate: dict[str, object],
    batch_id: str,
) -> dict[str, object]:
    review_key = str(selected_row["reviewKey"])
    portrait_ref = str(selected_row["portraitRef"])
    parent_item = unique_row(parent_manifest.get("reviewItems"), "reviewKey", review_key, "父 manifest reviewItems")
    parent_entity = unique_row(parent_manifest.get("entities"), "portraitRef", portrait_ref, "父 manifest entities")
    source_selection = require_object(data.get("sourceSelection"), "动作选帧 sourceSelection")
    swf_selection = require_object(source_selection.get("swf"), "动作选帧 swf")
    render_character_id = int(swf_selection["renderCharacterId"])
    render_frame_count = int(swf_selection["renderDeclaredFrameCount"])

    entity = copy.deepcopy(parent_entity)
    entity.update({
        "candidates": [copy.deepcopy(candidate)],
        "exportedFrameCount": render_frame_count,
        "usableUniqueFrameCount": int(require_object(data.get("generation"), "动作选帧 generation").get("usableUniqueFrameCount", 0)),
        "renderCharacterId": render_character_id,
        "renderDeclaredFrameCount": render_frame_count,
        "renderStrategy": "human_selected_action_state_named_man_instance",
        "renderStrategyWarning": None,
        "vectorSourceStrategy": "ffdec_sprite_svg_human_selected_action_man_frame",
        "vectorSpriteDirectory": str(Path(require_object(candidate["vectorArtifact"], "候选 SVG")["path"]).parent.as_posix()),
        "notes": "人类已锁定空手攻击状态内的平a man 帧；后续只在该帧重新定位机械头部特写。",
    })

    item = copy.deepcopy(parent_item)
    item.update({
        "candidates": [copy.deepcopy(candidate)],
        "humanFeedback": {
            "source": "verified_human_frame_reselection",
            "receiptDigest": receipt["receiptDigest"],
            "candidateId": selected_row["candidateId"],
            "frame": selected_row["frame"],
            "actionPath": "空手攻击 → 双枪狂徒/sprite/平a → man",
            "instruction": "该单位为人形；完整机械头面是唯一主焦点。featureBox 紧贴完整头盔/面罩并止于下颌，排除枪、手臂、胸腰和腿；mustIncludeBox 只允许少量不可分的颈部结构。",
        },
        "intentPolicy": {
            "defaultMode": "head_closeup",
            "reasoningHint": "人类已从空手攻击的平a man 时间轴锁定 frame 22。只定位完整机械头部：四枚蓝色面部感应点、白色面罩、头顶及后颈黑色连接结构共同定义身份；枪械、手、肩胸和下半身不得进入 featureBox。",
            "constraintSource": "verified_human_frame_reselection",
        },
        "blocked": False,
        "blockReason": None,
    })

    calibration = copy.deepcopy(parent_manifest.get("humanPreferenceCalibration"))
    model_batch_id = "human-frame-selected-localization-01"
    if isinstance(calibration, dict):
        contact_sheets = require_list(calibration.get("contactSheets"), "humanPreferenceCalibration.contactSheets")
        contact_sheets.append({
            "modelBatchId": model_batch_id,
            "base": copy.deepcopy(candidate["artifact"]),
            "composite": copy.deepcopy(candidate["artifact"]),
            "purpose": "preflight_only_localization_view_replaces_model_images",
        })

    frame_data_record = artifact(frame_root / "frame-reselection-data.json")
    frame_decisions_record = artifact(frame_root / "portrait-pilot-frame-reselection.json")
    frame_receipt_record = artifact(frame_root / "human-frame-reselection-receipt.json")
    controller_record = artifact(Path(__file__).resolve())
    source_envelope = copy.deepcopy(require_object(parent_manifest.get("sourceEnvelope"), "父 sourceEnvelope"))
    source_envelope.pop("promptExperiment", None)
    source_files = [copy.deepcopy(record) for record in require_list(source_envelope.get("sourceFiles"), "父 sourceFiles") if isinstance(record, dict)]
    source_files.extend([artifact(parent_manifest_path), frame_data_record, frame_decisions_record, frame_receipt_record, controller_record])
    source_envelope.update({
        "batchId": batch_id,
        "mode": "verified_human_frame_reselection_localization_v1",
        "sourceFiles": dedupe_artifacts(source_files),
        "humanPreferenceCalibration": calibration,
        "humanFrameReselection": {
            "data": frame_data_record,
            "decisions": frame_decisions_record,
            "receipt": frame_receipt_record,
            "receiptDigest": receipt["receiptDigest"],
            "reviewKey": review_key,
            "candidateId": selected_row["candidateId"],
            "frame": selected_row["frame"],
            "oldGeometryReused": False,
            "productionWrites": False,
        },
    })
    source_digest = sha256_bytes(stable_bytes(source_envelope))

    campaign = copy.deepcopy(require_object(parent_manifest.get("campaign"), "父 campaign"))
    campaign.pop("promptExperiment", None)
    campaign.update({
        "selectedPortraitRefs": [portrait_ref],
        "selectedSourceCounts": {str(entity["sourceSwf"]): 1},
        "shardSize": 1,
        "sourceGroups": 1,
        "identitiesPerSourceGroup": 1,
        "expectedModelJobs": 2,
        "selectionStrategy": "verified_human_frame_reselection_then_localization_only",
        "frameReselectionReceiptDigest": receipt["receiptDigest"],
    })
    manifest: dict[str, object] = {
        "schema": MANIFEST_SCHEMA,
        "phase": "P3_FEATURE_REFINEMENT",
        "status": "human_frame_selected_localization_ready",
        "productionReady": False,
        "batchId": batch_id,
        "createdAt": utc_now(),
        "campaign": campaign,
        "contactSheet": copy.deepcopy(candidate["artifact"]),
        "counts": {
            "entityCount": 1,
            "candidateCount": 1,
            "reviewUnitCount": 1,
            "eligibleReviewUnitCount": 1,
            "blockedReviewUnitCount": 0,
        },
        "entities": [entity],
        "featureContract": copy.deepcopy(parent_manifest["featureContract"]),
        "ffdecRuns": copy.deepcopy(require_object(data.get("generation"), "动作选帧 generation").get("runs", [])),
        "gates": {
            "verifiedHumanFrameSelection": True,
            "selectedActionStateNamedMan": True,
            "oldModelGeometryDiscarded": True,
            "localizationOnly": True,
            "humanTargetGeometryExcluded": True,
            "productionWrites": False,
        },
        "humanPreferenceCalibration": calibration,
        "modelBatches": [{
            "modelBatchId": model_batch_id,
            "reviewKeys": [review_key],
            "contactSheet": copy.deepcopy(candidate["artifact"]),
        }],
        "reviewItems": [item],
        "sourceEnvelope": source_envelope,
        "sourceDigest": source_digest,
    }
    manifest["manifestDigest"] = sha256_bytes(stable_bytes(manifest))
    return manifest


def checkerboard(size: tuple[int, int], cell: int) -> Image.Image:
    image = Image.new("RGBA", size, (31, 36, 43, 255))
    draw = ImageDraw.Draw(image)
    for top in range(0, size[1], cell):
        for left in range(0, size[0], cell):
            if (left // cell + top // cell) % 2 == 0:
                draw.rectangle((left, top, min(size[0] - 1, left + cell - 1), min(size[1] - 1, top + cell - 1)), fill=(45, 52, 61, 255))
    return image


def render_localization_view(
    high_path: Path,
    candidate: dict[str, object],
    output_path: Path,
    max_dimension: int,
) -> tuple[list[int], list[int], list[int]]:
    with Image.open(high_path) as opened:
        source = opened.convert("RGBA")
    source_size = [float(value) for value in require_list(candidate.get("sourceSize"), "候选 sourceSize")]
    bounds = [float(value) for value in require_list(candidate.get("sourceCropBounds"), "候选 sourceCropBounds")]
    if len(source_size) != 2 or len(bounds) != 4:
        raise PilotError("候选源坐标不闭合")
    scale_x = source.width / source_size[0]
    scale_y = source.height / source_size[1]
    pixels = [
        round(bounds[0] * scale_x), round(bounds[1] * scale_y),
        round(bounds[2] * scale_x), round(bounds[3] * scale_y),
    ]
    left, top, right, bottom = pixels
    if left < 0 or top < 0 or right > source.width or bottom > source.height or left >= right or top >= bottom:
        raise PilotError(f"高分辨率选帧裁切越界：{pixels}/{source.size}")
    cropped = source.crop((left, top, right, bottom))
    if max(cropped.size) + 2 < max_dimension:
        raise PilotError(f"高分辨率选帧不足以无放大生成 {max_dimension}px 定位图：{cropped.size}")
    resize_scale = min(1.0, max_dimension / max(cropped.size))
    view_size = (max(1, round(cropped.width * resize_scale)), max(1, round(cropped.height * resize_scale)))
    if view_size != cropped.size:
        cropped = cropped.resize(view_size, Image.Resampling.LANCZOS)
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
    return pixels, [background.width, background.height], [source.width, source.height]


def render(args: argparse.Namespace) -> dict[str, object]:
    if args.max_dimension < 1024 or args.max_dimension > 4096:
        raise PilotError("max-dimension 必须为 1024–4096")
    frame_root = pilot_child(args.frame_batch, "选帧批次", must_exist=True)
    output_root = pilot_child(args.output, "输出目录", must_exist=False)
    data, receipt = verify_frame_batch(frame_root)
    rows = require_list(receipt.get("rows"), "选帧回执行")
    if len(rows) != 1:
        raise PilotError("当前控制器只接受一行人类选帧回执")
    selected_row = require_object(rows[0], "选帧回执行")
    if selected_row.get("status") != "selected" or not isinstance(selected_row.get("candidateId"), str):
        raise PilotError("选帧回执没有 selected candidate")
    data_item = unique_row(data.get("items"), "reviewKey", selected_row["reviewKey"], "选帧数据 items")
    candidate_raw = unique_row(data_item.get("candidates"), "candidateId", selected_row["candidateId"], "选帧候选")
    if selected_row["candidateId"] in require_list(data_item.get("rejectedCandidateIds"), "已否决候选"):
        raise PilotError("选帧回执选择了已否决候选")
    candidate = candidate_with_vector_scale(candidate_raw)
    verify_artifact_record(require_object(candidate.get("artifact"), "候选 PNG"), "候选 PNG")
    verify_artifact_record(require_object(candidate.get("vectorArtifact"), "候选 SVG"), "候选 SVG")

    parent_files = require_object(require_object(data.get("parent"), "选帧 parent").get("files"), "选帧 parent.files")
    parent_manifest_record = require_object(parent_files.get("candidateManifest"), "父 candidate manifest")
    parent_manifest_path = verify_artifact_record(parent_manifest_record, "父 candidate manifest")
    parent_manifest = require_object(load_json(parent_manifest_path), "父 candidate manifest")
    verify_digest_object(parent_manifest, "manifestDigest", "父 candidate manifest")
    if not args.batch_id or any(character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-" for character in args.batch_id):
        raise PilotError("batch id 非法")

    output_root.mkdir(parents=False)
    manifest = build_manifest(
        parent_manifest,
        parent_manifest_path,
        frame_root,
        data,
        receipt,
        selected_row,
        candidate,
        args.batch_id,
    )
    manifest_path = output_root / "candidate-manifest.json"
    write_json(manifest_path, manifest)

    entity = require_object(require_list(manifest["entities"], "manifest entities")[0], "manifest entity")
    high_contract = require_object(require_object(manifest["featureContract"], "featureContract").get("highResolutionRender"), "highResolutionRender")
    maximum_frame_dimension = int(high_contract["maximumSourceFrameDimension"])
    maximum_zoom = int(high_contract["maximumZoom"])
    vector_size = [float(value) for value in require_list(candidate["vectorCanvasSize"], "vectorCanvasSize")]
    scales = [float(value) for value in require_list(candidate["rasterToVectorScale"], "rasterToVectorScale")]
    vector_crop_long = max(float(candidate["width"]) / scales[0], float(candidate["height"]) / scales[1])
    requested_zoom = max(1, math.ceil(args.max_dimension / vector_crop_long))
    zoom_cap = math.floor(maximum_frame_dimension / max(vector_size))
    selected_zoom = min(requested_zoom, zoom_cap, maximum_zoom)
    if selected_zoom < requested_zoom:
        raise PilotError(f"定位图在有界帧合同内无法保持真源：requested={requested_zoom} selected={selected_zoom}")

    source_swf_rel = str(entity["sourceSwf"])
    source_records = {
        record["path"]: record
        for record in require_list(require_object(manifest["sourceEnvelope"], "sourceEnvelope").get("sourceSwfs"), "sourceSwfs")
        if isinstance(record, dict) and isinstance(record.get("path"), str)
    }
    source_record = require_object(source_records.get(source_swf_rel), "来源 SWF")
    swf_path = verify_artifact_record(source_record, "来源 SWF")
    adapter = compile_selected_frame_exporter(output_root, "human-frame-localization-v1")
    group_id = f"human-frame-character-{entity['renderCharacterId']}"
    export_run, frame_records = export_selected_sprite_frames(
        adapter,
        output_root,
        swf_path,
        int(entity["renderCharacterId"]),
        [int(candidate["frame"])],
        selected_zoom,
        group_id,
        "human-frame-localization-v1",
    )
    export_run.update({
        "groupId": group_id,
        "requestedZoom": requested_zoom,
        "maximumZoomFromFrameDimension": zoom_cap,
        "maximumSourceFrameDimension": maximum_frame_dimension,
    })
    high_record = require_object(frame_records.get(int(candidate["frame"])), "高分辨率选帧")
    high_path = verify_artifact_record(high_record, "高分辨率选帧")
    view_path = output_root / "views" / f"R09-{candidate['candidateId']}.png"
    pixel_crop, view_size, high_size = render_localization_view(high_path, candidate, view_path, args.max_dimension)

    controller_files = [
        artifact(Path(__file__).resolve()),
        artifact(ROOT / "tools/portrait-pilot/prepare_pilot.py"),
        artifact(ROOT / "tools/portrait-pilot/SelectedSpriteFrameExporter.java"),
    ]
    source_data: dict[str, object] = {
        "schema": SOURCE_SCHEMA,
        "status": "human_frame_selection_source_ready",
        "productionReady": False,
        "generatedAt": utc_now(),
        "input": {
            "manifest": artifact(manifest_path),
            "manifestDigest": manifest["manifestDigest"],
            "sourceDigest": manifest["sourceDigest"],
            "frameReselectionData": artifact(frame_root / "frame-reselection-data.json"),
            "frameReselectionReceipt": artifact(frame_root / "human-frame-reselection-receipt.json"),
            "frameReselectionReceiptDigest": receipt["receiptDigest"],
        },
        "selection": {
            "reviewKey": selected_row["reviewKey"],
            "candidateId": candidate["candidateId"],
            "frame": candidate["frame"],
            "renderCharacterId": entity["renderCharacterId"],
            "actionPath": "空手攻击 → 双枪狂徒/sprite/平a → man",
        },
        "renderContract": {
            "purpose": "verified_human_frame_localization_only",
            "maxDimension": args.max_dimension,
            "maximumSourceFrameDimension": maximum_frame_dimension,
            "maximumZoom": maximum_zoom,
            "selectedZoom": selected_zoom,
            "oldFeatureGeometryConsumed": False,
            "candidatePixelsChanged": False,
        },
        "adapter": {key: value for key, value in adapter.items() if key != "runtimeClasspath"},
        "exportRuns": [export_run],
        "controller": {
            "files": controller_files,
            "sourceClosureDigest": sha256_bytes(stable_bytes(controller_files)),
        },
        "rows": [{
            "reviewCode": "R09",
            "reviewKey": selected_row["reviewKey"],
            "candidateId": candidate["candidateId"],
            "candidateArtifact": candidate["artifact"],
            "sourceGeometrySvg": candidate["vectorArtifact"],
            "sourceHighResolution": high_record,
            "selectedFrameZoom": selected_zoom,
            "featureGeometryConsumed": False,
        }],
        "counts": {"rows": 1, "sourceGroups": 1, "uniqueFrames": 1},
        "gates": {
            "verifiedHumanFrameSelection": True,
            "exactCandidateHashBinding": True,
            "featureGeometryConsumed": False,
            "humanTargetGeometryExcluded": True,
            "boundedSourceFrameDecode": True,
            "productionWrites": False,
        },
    }
    source_data["sourceDataDigest"] = sha256_bytes(stable_bytes(source_data))
    source_path = output_root / "selection-source-data.json"
    write_json(source_path, source_data)

    view_report: dict[str, object] = {
        "schema": VIEW_SCHEMA,
        "status": "localization_views_ready",
        "productionReady": False,
        "generatedAt": utc_now(),
        "input": {
            "manifest": artifact(manifest_path),
            "manifestDigest": manifest["manifestDigest"],
            "sourceReviewData": artifact(source_path),
            "sourceReviewDigest": source_data["sourceDataDigest"],
            "lockRole": "verified_human_frame_reselection",
            "selectionLock": None,
            "selectionDigest": receipt["receiptDigest"],
        },
        "renderContract": {
            "maxDimension": args.max_dimension,
            "gridStep": 0.1,
            "coordinateSpace": "human-locked candidate normalized 0..1",
            "targetHumanGeometryTransmitted": False,
            "sourceMode": "verified_human_frame_direct_export_v1",
        },
        "controller": artifact(Path(__file__).resolve()),
        "rows": [{
            "reviewCode": "R09",
            "reviewKey": selected_row["reviewKey"],
            "lockedRole": "verified_human_frame_reselection",
            "candidateId": candidate["candidateId"],
            "candidateArtifact": candidate["artifact"],
            "candidateWidth": candidate["width"],
            "candidateHeight": candidate["height"],
            "sourceSize": candidate["sourceSize"],
            "sourceCropBounds": candidate["sourceCropBounds"],
            "sourceHighResolution": high_record,
            "sourceHighResolutionSize": high_size,
            "sourceHighResolutionPixelCrop": pixel_crop,
            "selectedFrameZoom": selected_zoom,
            "viewSize": view_size,
            "view": artifact(view_path),
            "normalizedCoordinatesMatchCandidate": True,
        }],
        "counts": {"rows": 1, "uniqueViews": 1},
        "gates": {
            "exactCandidateHashBinding": True,
            "deterministicSelectionLock": True,
            "verifiedHumanFrameSelection": True,
            "highResolutionSourceVerified": True,
            "normalizedCandidateMapping": True,
            "humanTargetGeometryExcluded": True,
            "oldModelGeometryConsumed": False,
            "productionWrites": False,
        },
    }
    view_report["viewDigest"] = sha256_bytes(stable_bytes(view_report))
    write_json(output_root / "localization-view-manifest.json", view_report)
    return view_report


def check(args: argparse.Namespace) -> dict[str, object]:
    output_root = pilot_child(args.output, "输出目录", must_exist=True)
    manifest_path = output_root / "candidate-manifest.json"
    source_path = output_root / "selection-source-data.json"
    view_path = output_root / "localization-view-manifest.json"
    manifest = require_object(load_json(manifest_path), "candidate manifest")
    source_data = require_object(load_json(source_path), "selection source data")
    view_report = require_object(load_json(view_path), "localization view manifest")
    verify_digest_object(manifest, "manifestDigest", "candidate manifest")
    verify_digest_object(source_data, "sourceDataDigest", "selection source data")
    verify_digest_object(view_report, "viewDigest", "localization view manifest")
    if sha256_bytes(stable_bytes(require_object(manifest.get("sourceEnvelope"), "sourceEnvelope"))) != manifest.get("sourceDigest"):
        raise PilotError("manifest sourceDigest 不匹配")
    if manifest.get("schema") != MANIFEST_SCHEMA or view_report.get("schema") != VIEW_SCHEMA:
        raise PilotError("manifest 或 localization view schema 漂移")
    if view_report.get("input", {}).get("manifestDigest") != manifest.get("manifestDigest"):
        raise PilotError("localization view 未绑定当前 manifest")
    verify_artifact_record(require_object(view_report.get("controller"), "view controller"), "view controller")
    verify_artifact_record(require_object(view_report.get("input", {}).get("manifest"), "view manifest artifact"), "view manifest artifact")
    verify_artifact_record(require_object(view_report.get("input", {}).get("sourceReviewData"), "view source data artifact"), "view source data artifact")
    rows = require_list(view_report.get("rows"), "view rows")
    if len(rows) != 1 or view_report.get("gates", {}).get("oldModelGeometryConsumed") is not False:
        raise PilotError("localization view 行数或旧几何门非法")
    row = require_object(rows[0], "view row")
    verify_artifact_record(require_object(row.get("candidateArtifact"), "view candidate"), "view candidate")
    verify_artifact_record(require_object(row.get("sourceHighResolution"), "view high resolution"), "view high resolution")
    image_path = verify_artifact_record(require_object(row.get("view"), "view image"), "view image")
    with Image.open(image_path) as image:
        if list(image.size) != row.get("viewSize"):
            raise PilotError("localization view 图像尺寸不匹配")
    return view_report


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--frame-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.add_argument("--max-dimension", type=int, default=2048)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    return result


def main() -> None:
    args = parser().parse_args()
    report = render(args) if args.command == "render" else check(args)
    print(json.dumps({
        "status": report["status"] if args.command == "render" else "human_frame_localization_views_verified",
        "viewDigest": report["viewDigest"],
        "counts": report["counts"],
        "oldModelGeometryConsumed": report["gates"]["oldModelGeometryConsumed"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, PilotError, KeyError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
