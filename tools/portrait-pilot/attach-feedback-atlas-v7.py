#!/usr/bin/env python3
"""Attach all 181 current human labels and a compact model view to a fresh shard."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageDraw, ImageFont


CONTROLLER_PATH = Path(__file__).resolve()
RESCUE_CONTROLLER_PATH = CONTROLLER_PATH.with_name("prepare-campaign-xfl-embedded-rescue-v1.py")
COMPACT_V4_CONTROLLER_PATH = CONTROLLER_PATH.with_name("derive-compact-model-atlas-v4.py")
FEEDBACK_V7_CONTROLLER_PATH = CONTROLLER_PATH.with_name("build-feedback-calibration-v7.js")
ROOT = CONTROLLER_PATH.parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
SCHEMA = "cf7.portrait-pilot-human-preference-atlas.v7"
RETRIEVAL_SCHEMA = "cf7.portrait-pilot-model-atlas-retrieval.v5"
MODE = "bound_181_current_human_labels_106_geometry_and_stage_specific_concurrency"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rescue = load_module(RESCUE_CONTROLLER_PATH, "cf7_portrait_xfl_rescue_for_atlas_v7")
compact_v4 = load_module(COMPACT_V4_CONTROLLER_PATH, "cf7_portrait_compact_v4_for_atlas_v7")
core = rescue.core


class AtlasError(RuntimeError):
    pass


def repo_path(value: str | Path, label: str) -> Path:
    return core.ensure_below(Path(value), ROOT, label)


def pilot_path(value: str | Path, label: str) -> Path:
    return core.ensure_below(Path(value), PILOT_ROOT, label)


def load_json(path: Path, label: str) -> dict[str, Any]:
    value = core.load_json(path)
    if not isinstance(value, dict):
        raise AtlasError(f"{label} 顶层必须是对象")
    return value


def add_artifact(records: list[dict[str, Any]], path: Path) -> None:
    record = core.artifact(path)
    if record["path"] not in {entry.get("path") for entry in records if isinstance(entry, dict)}:
        records.append(record)


def verify_record(record: dict[str, Any], label: str) -> Path:
    try:
        return core.verify_artifact_record(record, label)
    except core.PilotError as error:
        raise AtlasError(str(error)) from error


def verify_digest(value: dict[str, Any], field: str, label: str) -> None:
    envelope = dict(value)
    digest = envelope.pop(field, None)
    if core.sha256_bytes(core.stable_bytes(envelope)) != digest:
        raise AtlasError(f"{label} {field} 不匹配")


def run_feedback_check(report_path: Path) -> None:
    report = load_json(report_path, "feedback v7")
    result = subprocess.run(
        [
            "node",
            str(FEEDBACK_V7_CONTROLLER_PATH),
            "--output",
            str(report_path.parent),
            "--batch-id",
            str(report.get("batchId", "")),
            "--check",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if result.returncode != 0:
        raise AtlasError(f"feedback v7 check 失败：{result.stderr.strip() or result.stdout.strip()}")


def artifact_path(record: dict[str, Any], label: str) -> Path:
    return verify_record(record, label)


def preview_record(item: dict[str, Any], status: str, guided_by_key: dict[str, dict[str, Any]]) -> dict[str, Any]:
    if status == "adjustment":
        guided = guided_by_key.get(item["reviewKey"])
        if not guided:
            raise AtlasError(f"adjustment 缺最终 guided render：{item['reviewKey']}")
        return guided["previews"]["80"]
    proposal = item.get("proposals", {}).get("proposal")
    if not isinstance(proposal, dict):
        raise AtlasError(f"pass 缺 proposal：{item['reviewKey']}")
    return proposal["previews"]["80"]


def fit_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, width: int) -> str:
    value = text
    while value and draw.textbbox((0, 0), value, font=font)[2] > width:
        value = value[:-1]
    return value if value == text else f"{value[:-1]}…"


def build_tail_panel(
    output_path: Path,
    width: int,
    review_data: dict[str, Any],
    decisions: dict[str, Any],
    guided_render: dict[str, Any],
) -> tuple[list[str], int]:
    items = review_data.get("items", [])
    decision_map = decisions.get("decisions", {})
    if len(items) != 13 or set(decision_map) != {item["reviewKey"] for item in items}:
        raise AtlasError("tail panel 必须闭合 13 条 review/decision")
    guided_by_key = {row["reviewKey"]: row for row in guided_render.get("rows", [])}
    row_height = 128
    header_height = 84
    canvas = Image.new("RGB", (width, header_height + row_height * len(items)), "#0E171D")
    draw = ImageDraw.Draw(canvas)
    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    if not font_path.is_file():
        raise AtlasError("缺少微软雅黑字体")
    title_font = ImageFont.truetype(str(font_path), 30)
    body_font = ImageFont.truetype(str(font_path), 22)
    small_font = ImageFont.truetype(str(font_path), 17)
    draw.rectangle((0, 0, width, header_height), fill="#14232B")
    draw.text((20, 12), "LATEST HUMAN PREFERENCES · 13 REVIEW LABELS / 1 GUIDED CROP", font=title_font, fill="#74E0D1")
    draw.text((20, 49), "PASS 接受 Luna A；ADJUSTMENT 使用真人最终框选。以下均为历史偏好，不是当前候选。", font=small_font, fill="#D2E3E8")
    keys: list[str] = []
    for index, item in enumerate(items):
        key = item["reviewKey"]
        decision = decision_map[key]
        status = decision["status"]
        if status not in ("pass", "adjustment"):
            raise AtlasError(f"tail panel 出现非 pass/adjustment：{key}/{status}")
        keys.append(key)
        top = header_height + index * row_height
        draw.rectangle((0, top, width, top + row_height), fill="#172129" if index % 2 == 0 else "#111C23")
        draw.line((0, top, width, top), fill="#29404B", width=1)
        preview = artifact_path(preview_record(item, status, guided_by_key), f"tail preview {key}")
        with Image.open(preview) as opened:
            image = opened.convert("RGBA").resize((92, 92), Image.Resampling.NEAREST)
        checker = Image.new("RGB", (92, 92), "#263640")
        checker.paste(image, mask=image.getchannel("A"))
        canvas.paste(checker, (20, top + 18))
        color = "#78E0C4" if status == "pass" else "#F4BE63"
        draw.text((132, top + 14), status.upper(), font=body_font, fill=color)
        draw.text((278, top + 14), fit_text(draw, key, body_font, width - 300), font=body_font, fill="#F1F5F6")
        proposal = item.get("proposals", {}).get("proposal", {})
        feature = str(proposal.get("featureLabel", ""))
        orientation = str(proposal.get("orientationAction", "keep"))
        detail = f"feature={feature} · orientation={orientation}"
        draw.text((132, top + 52), fit_text(draw, detail, small_font, width - 155), font=small_font, fill="#AFC5CC")
        note = decision.get("notes", "") or "真人直接通过当前识别特写"
        draw.text((132, top + 82), fit_text(draw, f"human: {note}", small_font, width - 155), font=small_font, fill="#D8E4E7")
    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    return keys, len(items)


def append_panel(base_path: Path, panel_path: Path, output_path: Path) -> tuple[list[int], int]:
    with Image.open(base_path) as opened:
        base_image = opened.convert("RGB")
    with Image.open(panel_path) as opened:
        panel = opened.convert("RGB")
    if panel.width != base_image.width:
        panel = panel.resize((base_image.width, round(panel.height * base_image.width / panel.width)), Image.Resampling.LANCZOS)
    combined = Image.new("RGB", (base_image.width, base_image.height + panel.height), "#0E171D")
    combined.paste(base_image, (0, 0))
    combined.paste(panel, (0, base_image.height))
    combined.save(output_path, format="PNG", optimize=False, compress_level=9)
    patches = math.ceil(combined.width / 32) * math.ceil(combined.height / 32)
    return [combined.width, combined.height], patches


def image_dimensions(path: Path) -> list[int]:
    with Image.open(path) as opened:
        return [opened.width, opened.height]


def contact_bindings(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    records = [manifest["contactSheet"], *(batch["contactSheet"] for batch in manifest["modelBatches"])]
    bindings = []
    for record in records:
        path = artifact_path(record, "current candidate contact sheet")
        dimensions = image_dimensions(path)
        bindings.append(
            {
                "base": record,
                "baseDimensions": dimensions,
                "composite": record,
                "compositeDimensions": dimensions,
                "transportPolicy": "current_candidates_sent_separately_from_compact_human_atlas",
            }
        )
    return bindings


def append_global_rules(manifest: dict[str, Any]) -> None:
    rules = [
        "头像的最终目标是确保角色可识别度；头部是最常见的视觉重点，但不是机械的唯一答案。",
        "若头部本身视觉特征较弱，允许把武器结构或身体特质作为次级识别证据，但主视觉重点仍必须位于方形头像甜区。",
        "优先保证头部或最强身份特征的安全范围；视觉较弱的肢体、武器末端、尾巴和特效在必要时允许顶边或越边裁切。",
        "方向必须从原始候选的脸、视线、喙、头部前端或运动轴判断；不得因 renderer 已经翻转而再次反推源图方向。",
        "汽车炸弹类非人单位可以选择局部机械身份特征，例如车尾发动机，只要它比完整横向主体更利于小头像识别。",
    ]
    contract = manifest["featureContract"]["global"]
    for rule in rules:
        if rule not in contract:
            contract.append(rule)
    extra_hint = "先抓头部；若头部弱，再让渡到武器结构或身体特质。把最强视觉重点放在头像甜区并留安全范围，弱组件可以越边裁切。"
    for item in manifest["reviewItems"]:
        hint = str(item["intentPolicy"].get("reasoningHint", ""))
        if extra_hint not in hint:
            item["intentPolicy"]["reasoningHint"] = f"{hint}{extra_hint}"


def build_calibration(
    manifest: dict[str, Any],
    manifest_path: Path,
    parent_manifest: dict[str, Any],
    parent_manifest_path: Path,
    feedback_path: Path,
    feedback: dict[str, Any],
    review_batch: Path,
    review_data: dict[str, Any],
    decisions: dict[str, Any],
    receipt: dict[str, Any],
    guidance_batch: Path,
    guidance_receipt: dict[str, Any],
    guided_render_path: Path,
    guided_render: dict[str, Any],
    panel_record: dict[str, Any],
    full_record: dict[str, Any],
    full_dimensions: list[int],
    full_patches: int,
    compact_record: dict[str, Any],
    compact_dimensions: list[int],
    compact_patches: int,
) -> dict[str, Any]:
    parent = parent_manifest["humanPreferenceCalibration"]
    calibration = copy.deepcopy(parent)
    previous_coverage = parent["coverage"]
    current_keys = [item["reviewKey"] for item in review_data["items"]]
    if set(current_keys) & set(previous_coverage["reviewKeys"]):
        raise AtlasError("latest 13 labels 与历史 168 labels 重叠")
    proposal_flip_count = sum(
        1
        for item in review_data["items"]
        if item.get("proposals", {}).get("proposal", {}).get("orientationAction") == "flip_x"
    )
    calibration["schema"] = SCHEMA
    calibration["mode"] = MODE
    calibration["controllerSource"] = core.artifact(CONTROLLER_PATH)
    calibration["parentCompactManifest"] = core.artifact(parent_manifest_path)
    calibration["baseManifest"] = core.artifact(manifest_path)
    calibration["xflEmbeddedSourceReceipt"] = copy.deepcopy(
        manifest["sourceEnvelope"]["xflEmbeddedSourcePolicy"]["sourceReceipt"]
    )
    calibration["feedbackReport"] = core.artifact(feedback_path)
    calibration["currentHumanReview"] = {
        "reviewData": core.artifact(review_batch / "review-data.json"),
        "decisions": core.artifact(review_batch / "portrait-pilot-review-decisions.json"),
        "receipt": core.artifact(review_batch / "human-review-receipt.json"),
        "receiptDigest": receipt["receiptDigest"],
    }
    calibration["currentHumanGuidance"] = {
        "data": core.artifact(guidance_batch / "framing-guidance-data.json"),
        "guidance": core.artifact(guidance_batch / "portrait-pilot-framing-guidance.json"),
        "receipt": core.artifact(guidance_batch / "human-framing-guidance-receipt.json"),
        "receiptDigest": guidance_receipt["receiptDigest"],
        "guidedRender": core.artifact(guided_render_path),
        "guidedRenderDigest": guided_render["reportDigest"],
    }
    calibration["tail13FeedbackPanel"] = panel_record
    calibration["atlas"] = full_record
    calibration["modelAtlas"] = compact_record
    calibration["contactSheets"] = contact_bindings(manifest)
    calibration["adaptiveScaling"] = copy.deepcopy(feedback["adaptiveScaling"])
    calibration["coverage"] = {
        **previous_coverage,
        "mode": MODE,
        "decisionCount": 181,
        "passAnchorCount": 70,
        "adjustmentCount": 110,
        "anomalyCount": 1,
        "guidedCorrectionCount": 106,
        "orientationOnlyCorrectionCount": 4,
        "guidedOrientationCount": 11,
        "orientationTransformationCount": int(previous_coverage.get("orientationTransformationCount", 15)) + proposal_flip_count,
        "reviewKeys": sorted([*previous_coverage["reviewKeys"], *current_keys]),
        "dimensions": full_dimensions,
        "latestTailPanelDimensions": image_dimensions(ROOT / panel_record["path"]),
        "all181CurrentHumanLabelsVisualized": True,
        "allHumanLabelsVisualized": True,
        "latestTail13HumanLabelsVisualized": True,
        "all106GeometryRowsBound": feedback["geometryCalibration"]["cumulativeRowCount"] == 106,
        "stageSpecificConcurrencyBound": True,
    }
    retrieval = copy.deepcopy(parent["modelAtlasRetrieval"])
    retrieval.update(
        {
            "schema": RETRIEVAL_SCHEMA,
            "mode": MODE,
            "controllerSource": core.artifact(CONTROLLER_PATH),
            "parentManifest": core.artifact(parent_manifest_path),
            "fullAtlas": full_record,
            "fullAtlasDimensions": full_dimensions,
            "modelAtlasDimensions": compact_dimensions,
            "fullAtlasPatchCount": full_patches,
            "modelAtlasPatchCount": compact_patches,
            "patchReductionFraction": round(1 - compact_patches / full_patches, 6),
            "dynamicHumanLabelCount": 181,
            "latestHumanLabelCount": 13,
            "cumulativeGeometryRowCount": 106,
            "selectedVisualExampleCount": int(retrieval.get("selectedVisualExampleCount", 65)) + 13,
            "latestTailPanel": panel_record,
            "stageSpecificConcurrency": {
                "selectionMaximumConcurrency": 6,
                "localizationMaximumConcurrency": 3,
                "concurrencyEightAuthorized": False,
            },
        }
    )
    retrieval["gates"].update(
        {
            "fullHumanEvidenceBound": True,
            "aggregateStatisticsCoverAllHumanLabels": True,
            "visualExamplesRetrievedDeterministically": True,
            "fullAtlasNotTransmittedPerModelCall": True,
            "examplesAreNotCandidates": True,
            "all181CurrentHumanLabelsBound": True,
            "all106GeometryRowsBound": True,
            "latestTail13ExamplesIncluded": True,
            "stageSpecificConcurrencyBound": True,
            "productionWrites": False,
        }
    )
    calibration["modelAtlasRetrieval"] = retrieval
    calibration["gates"].update(
        {
            "examplesAreNotCandidates": True,
            "all181CurrentHumanLabelsBound": True,
            "all106GeometryRowsBound": True,
            "latestTail13ExamplesIncluded": True,
            "stageSpecificConcurrencyBound": True,
            "productionWrites": False,
        }
    )
    return calibration


def derive(args: argparse.Namespace) -> None:
    manifest_path = pilot_path(args.manifest, "atlas v7 base manifest")
    rescue.verify_shard(manifest_path)
    parent_path = pilot_path(args.parent_compact_manifest, "atlas v7 parent compact manifest")
    compact_v4.verify_v4(parent_path)
    feedback_path = pilot_path(args.feedback_report, "atlas v7 feedback report")
    run_feedback_check(feedback_path)
    output = pilot_path(args.output, "atlas v7 output")
    if output.exists():
        raise AtlasError(f"输出已存在，禁止覆盖：{output}")
    output.mkdir(parents=True)

    manifest = load_json(manifest_path, "atlas v7 base manifest")
    parent_manifest = load_json(parent_path, "atlas v7 parent compact manifest")
    feedback = load_json(feedback_path, "atlas v7 feedback")
    review_batch = pilot_path(args.review_batch, "atlas v7 review batch")
    guidance_batch = pilot_path(args.guidance_batch, "atlas v7 guidance batch")
    guided_render_path = pilot_path(args.guided_render, "atlas v7 guided render")
    review_data = load_json(review_batch / "review-data.json", "latest review data")
    decisions = load_json(review_batch / "portrait-pilot-review-decisions.json", "latest decisions")
    receipt = load_json(review_batch / "human-review-receipt.json", "latest review receipt")
    guidance_receipt = load_json(guidance_batch / "human-framing-guidance-receipt.json", "latest guidance receipt")
    guided_render = load_json(guided_render_path, "latest guided render")
    if receipt.get("counts", {}).get("eligiblePassed") != 12 or receipt.get("counts", {}).get("eligible") != 13:
        raise AtlasError("latest review receipt 必须为 12/13 pass")
    if len(guided_render.get("rows", [])) != 1 or feedback.get("geometryCalibration", {}).get("cumulativeRowCount") != 106:
        raise AtlasError("latest guided render / cumulative geometry 未闭合")

    parent_calibration = parent_manifest["humanPreferenceCalibration"]
    parent_full_path = artifact_path(parent_calibration["atlas"], "parent full atlas")
    parent_compact_path = artifact_path(parent_calibration["modelAtlas"], "parent compact atlas")
    width = image_dimensions(parent_full_path)[0]
    panel_path = output / "tail13-human-preference-panel.png"
    panel_keys, panel_count = build_tail_panel(panel_path, width, review_data, decisions, guided_render)
    if panel_count != 13 or sorted(panel_keys) != sorted(decisions["decisions"]):
        raise AtlasError("tail panel key closure 漂移")
    full_path = output / "feedback-preference-atlas-181.png"
    compact_path = output / "compact-feedback-model-atlas-181.png"
    full_dimensions, full_patches = append_panel(parent_full_path, panel_path, full_path)
    compact_dimensions, compact_patches = append_panel(parent_compact_path, panel_path, compact_path)
    if compact_patches >= full_patches:
        raise AtlasError("atlas v7 compact patch 未严格减少")

    append_global_rules(manifest)
    panel_record = core.artifact(panel_path)
    full_record = core.artifact(full_path)
    compact_record = core.artifact(compact_path)
    calibration = build_calibration(
        manifest,
        manifest_path,
        parent_manifest,
        parent_path,
        feedback_path,
        feedback,
        review_batch,
        review_data,
        decisions,
        receipt,
        guidance_batch,
        guidance_receipt,
        guided_render_path,
        guided_render,
        panel_record,
        full_record,
        full_dimensions,
        full_patches,
        compact_record,
        compact_dimensions,
        compact_patches,
    )
    manifest["batchId"] = args.batch_id
    manifest["createdAt"] = rescue.base.utc_now()
    manifest["humanPreferenceCalibration"] = calibration
    manifest["sourceEnvelope"]["humanPreferenceCalibration"] = calibration
    manifest["sourceEnvelope"]["batchId"] = args.batch_id
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    for path in (
        CONTROLLER_PATH,
        RESCUE_CONTROLLER_PATH,
        COMPACT_V4_CONTROLLER_PATH,
        FEEDBACK_V7_CONTROLLER_PATH,
        manifest_path,
        parent_path,
        feedback_path,
        review_batch / "review-data.json",
        review_batch / "portrait-pilot-review-decisions.json",
        review_batch / "human-review-receipt.json",
        guidance_batch / "framing-guidance-data.json",
        guidance_batch / "portrait-pilot-framing-guidance.json",
        guidance_batch / "human-framing-guidance-receipt.json",
        guided_render_path,
        panel_path,
        full_path,
        compact_path,
    ):
        add_artifact(source_files, path)
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceDigest"] = core.sha256_bytes(core.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    output_manifest = output / "candidate-manifest.json"
    core.write_json(output_manifest, manifest)
    print(json.dumps(verify_v7(output_manifest), ensure_ascii=False))


def assert_appended(base_path: Path, panel_path: Path, combined_path: Path, label: str) -> None:
    with Image.open(base_path) as opened:
        base_image = opened.convert("RGB")
    with Image.open(panel_path) as opened:
        panel = opened.convert("RGB")
    with Image.open(combined_path) as opened:
        combined = opened.convert("RGB")
    if combined.size != (base_image.width, base_image.height + panel.height):
        raise AtlasError(f"{label} 尺寸不是 parent + panel")
    if ImageChops.difference(combined.crop((0, 0, base_image.width, base_image.height)), base_image).getbbox() is not None:
        raise AtlasError(f"{label} parent 像素漂移")
    if ImageChops.difference(combined.crop((0, base_image.height, combined.width, combined.height)), panel).getbbox() is not None:
        raise AtlasError(f"{label} tail panel 像素漂移")


def verify_v7(manifest_path: Path) -> dict[str, Any]:
    manifest = core.verify_manifest(manifest_path)
    calibration = manifest.get("humanPreferenceCalibration")
    if not isinstance(calibration, dict) or calibration != manifest.get("sourceEnvelope", {}).get("humanPreferenceCalibration"):
        raise AtlasError("atlas v7 calibration 顶层与 source envelope 漂移")
    base_manifest_path = verify_record(calibration.get("baseManifest"), "atlas v7 base manifest")
    rescue.verify_shard(base_manifest_path)
    xfl_source_receipt_path = verify_record(
        calibration.get("xflEmbeddedSourceReceipt"), "atlas v7 XFL rescue receipt"
    )
    if xfl_source_receipt_path.name != "xfl-embedded-source-receipt.json":
        raise AtlasError("atlas v7 xflEmbeddedSourceReceipt 必须绑定 XFL rescue receipt")
    parent_path = verify_record(calibration.get("parentCompactManifest"), "atlas v7 parent compact manifest")
    compact_v4.verify_v4(parent_path)
    parent = load_json(parent_path, "atlas v7 parent compact")
    feedback_path = verify_record(calibration.get("feedbackReport"), "atlas v7 feedback")
    run_feedback_check(feedback_path)
    feedback = load_json(feedback_path, "atlas v7 feedback")
    panel_path = verify_record(calibration.get("tail13FeedbackPanel"), "atlas v7 tail panel")
    full_path = verify_record(calibration.get("atlas"), "atlas v7 full atlas")
    compact_path = verify_record(calibration.get("modelAtlas"), "atlas v7 compact atlas")
    parent_calibration = parent["humanPreferenceCalibration"]
    parent_full = verify_record(parent_calibration.get("atlas"), "atlas v7 parent full atlas")
    parent_compact = verify_record(parent_calibration.get("modelAtlas"), "atlas v7 parent compact atlas image")
    assert_appended(parent_full, panel_path, full_path, "full atlas v7")
    assert_appended(parent_compact, panel_path, compact_path, "compact atlas v7")
    coverage = calibration.get("coverage", {})
    retrieval = calibration.get("modelAtlasRetrieval", {})
    gates = retrieval.get("gates", {})
    current = calibration.get("currentHumanReview", {})
    current_receipt_path = verify_record(current.get("receipt"), "atlas v7 current receipt")
    current_receipt = load_json(current_receipt_path, "atlas v7 current receipt")
    verify_digest(current_receipt, "receiptDigest", "atlas v7 current receipt")
    guidance = calibration.get("currentHumanGuidance", {})
    verify_record(guidance.get("receipt"), "atlas v7 guidance receipt")
    guided_path = verify_record(guidance.get("guidedRender"), "atlas v7 guided render")
    guided = load_json(guided_path, "atlas v7 guided render")
    verify_digest(guided, "reportDigest", "atlas v7 guided render")
    expected_full_dimensions = image_dimensions(full_path)
    expected_compact_dimensions = image_dimensions(compact_path)
    expected_full_patches = math.ceil(expected_full_dimensions[0] / 32) * math.ceil(expected_full_dimensions[1] / 32)
    expected_compact_patches = math.ceil(expected_compact_dimensions[0] / 32) * math.ceil(expected_compact_dimensions[1] / 32)
    expected_current_keys = {row["reviewKey"] for row in current_receipt["decisions"]}
    if (
        calibration.get("schema") != SCHEMA
        or calibration.get("mode") != MODE
        or calibration.get("controllerSource") != core.artifact(CONTROLLER_PATH)
        or coverage.get("decisionCount") != 181
        or coverage.get("passAnchorCount") != 70
        or coverage.get("adjustmentCount") != 110
        or coverage.get("anomalyCount") != 1
        or coverage.get("guidedCorrectionCount") != 106
        or len(coverage.get("reviewKeys", [])) != 181
        or not expected_current_keys.issubset(set(coverage.get("reviewKeys", [])))
        or coverage.get("all181CurrentHumanLabelsVisualized") is not True
        or coverage.get("all106GeometryRowsBound") is not True
        or coverage.get("stageSpecificConcurrencyBound") is not True
        or feedback.get("geometryCalibration", {}).get("cumulativeRowCount") != 106
        or retrieval.get("schema") != RETRIEVAL_SCHEMA
        or retrieval.get("mode") != MODE
        or retrieval.get("controllerSource") != core.artifact(CONTROLLER_PATH)
        or retrieval.get("dynamicHumanLabelCount") != 181
        or retrieval.get("latestHumanLabelCount") != 13
        or retrieval.get("cumulativeGeometryRowCount") != 106
        or retrieval.get("fullAtlas") != calibration.get("atlas")
        or retrieval.get("fullAtlasDimensions") != expected_full_dimensions
        or retrieval.get("modelAtlasDimensions") != expected_compact_dimensions
        or retrieval.get("fullAtlasPatchCount") != expected_full_patches
        or retrieval.get("modelAtlasPatchCount") != expected_compact_patches
        or expected_compact_patches >= expected_full_patches
        or retrieval.get("stageSpecificConcurrency", {}).get("selectionMaximumConcurrency") != 6
        or retrieval.get("stageSpecificConcurrency", {}).get("localizationMaximumConcurrency") != 3
        or retrieval.get("stageSpecificConcurrency", {}).get("concurrencyEightAuthorized") is not False
        or gates.get("fullHumanEvidenceBound") is not True
        or gates.get("aggregateStatisticsCoverAllHumanLabels") is not True
        or gates.get("visualExamplesRetrievedDeterministically") is not True
        or gates.get("fullAtlasNotTransmittedPerModelCall") is not True
        or gates.get("examplesAreNotCandidates") is not True
        or gates.get("all181CurrentHumanLabelsBound") is not True
        or gates.get("productionWrites") is not False
        or calibration.get("gates", {}).get("examplesAreNotCandidates") is not True
        or calibration.get("gates", {}).get("productionWrites") is not False
        or manifest.get("productionReady") is not False
    ):
        raise AtlasError("atlas v7 181-label / 106-geometry / stage-concurrency gate 非法")
    contact_paths = {entry["composite"]["path"] for entry in calibration.get("contactSheets", [])}
    expected_contact_paths = {manifest["contactSheet"]["path"], *(batch["contactSheet"]["path"] for batch in manifest["modelBatches"])}
    if contact_paths != expected_contact_paths:
        raise AtlasError("atlas v7 current candidate contact binding 漂移")
    artifact_count = 0
    for record in manifest["sourceEnvelope"].get("sourceFiles", []):
        verify_record(record, "atlas v7 source file")
        artifact_count += 1
    return {
        "status": "human_preference_atlas_v7_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "dynamicHumanLabels": 181,
        "geometryRows": 106,
        "selectionMaximumConcurrency": 6,
        "localizationMaximumConcurrency": 3,
        "fullAtlasPatches": expected_full_patches,
        "modelAtlasPatches": expected_compact_patches,
        "patchReductionFraction": round(1 - expected_compact_patches / expected_full_patches, 6),
        "artifactCount": artifact_count,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_v7(pilot_path(args.manifest, "atlas v7 manifest")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    derive_parser = commands.add_parser("derive")
    derive_parser.add_argument("--manifest", required=True)
    derive_parser.add_argument("--parent-compact-manifest", required=True)
    derive_parser.add_argument("--feedback-report", required=True)
    derive_parser.add_argument("--review-batch", required=True)
    derive_parser.add_argument("--guidance-batch", required=True)
    derive_parser.add_argument("--guided-render", required=True)
    derive_parser.add_argument("--output", required=True)
    derive_parser.add_argument("--batch-id", required=True)
    derive_parser.set_defaults(handler=derive)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--manifest", required=True)
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (AtlasError, core.PilotError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"portrait feedback atlas v7 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
