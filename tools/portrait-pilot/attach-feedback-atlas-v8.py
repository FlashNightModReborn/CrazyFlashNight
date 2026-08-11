#!/usr/bin/env python3
"""Append the five approved XFL-rescue portraits to the cumulative preference atlas."""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


CONTROLLER_PATH = Path(__file__).resolve()
ATLAS_V7_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas-v7.py")
FEEDBACK_V8_PATH = CONTROLLER_PATH.with_name("build-feedback-calibration-v8.js")
ROOT = CONTROLLER_PATH.parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
SCHEMA = "cf7.portrait-pilot-human-preference-atlas.v8"
MODE = "bound_186_current_human_labels_106_geometry_and_stage_specific_concurrency"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


atlas7 = load_module(ATLAS_V7_PATH, "cf7_portrait_feedback_atlas_v7_for_v8")
core = atlas7.core
AtlasError = atlas7.AtlasError


def pilot_path(value: str | Path, label: str) -> Path:
    return core.ensure_below(Path(value), PILOT_ROOT, label)


def load_json(path: Path, label: str) -> dict[str, Any]:
    value = core.load_json(path)
    if not isinstance(value, dict):
        raise AtlasError(f"{label} 顶层必须是对象")
    return value


def verify_record(record: dict[str, Any], label: str) -> Path:
    return core.verify_artifact_record(record, label)


def add_artifact(records: list[dict[str, Any]], path: Path) -> None:
    record = core.artifact(path)
    if record["path"] not in {entry.get("path") for entry in records if isinstance(entry, dict)}:
        records.append(record)


def check_feedback(path: Path, batch_id: str) -> dict[str, Any]:
    completed = subprocess.run(
        [
            "node",
            str(FEEDBACK_V8_PATH.relative_to(ROOT)),
            "--output",
            str(path.parent.relative_to(ROOT)),
            "--batch-id",
            batch_id,
            "--check",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if completed.returncode != 0:
        raise AtlasError(f"feedback v8 check 失败：{completed.stderr.strip() or completed.stdout.strip()}")
    feedback = load_json(path, "feedback v8")
    if feedback.get("feedbackDigest") is None:
        raise AtlasError("feedback v8 digest 缺失")
    return feedback


def fit_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, width: int) -> str:
    value = text
    while value and draw.textbbox((0, 0), value, font=font)[2] > width:
        value = value[:-1]
    return value if value == text else f"{value[:-1]}…"


def build_panel(output: Path, width: int, review: dict[str, Any], decisions: dict[str, Any]) -> list[str]:
    items = review.get("items", [])
    decision_map = decisions.get("decisions", {})
    if len(items) != 5 or set(decision_map) != {item["reviewKey"] for item in items}:
        raise AtlasError("atlas v8 panel 必须闭合 5 条 review/decision")
    if any(decision.get("status") != "pass" for decision in decision_map.values()):
        raise AtlasError("atlas v8 panel 只接受 5 条 pass")
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
    draw.text((20, 12), "LATEST HUMAN PREFERENCES · 5 XFL-NAMED-MAN PASS LABELS", font=title_font, fill="#74E0D1")
    draw.text((20, 49), "真人 5/5 直接通过；以下是历史偏好正样本，不是未来批次的当前候选。", font=small_font, fill="#D2E3E8")
    keys: list[str] = []
    for index, item in enumerate(items):
        key = item["reviewKey"]
        keys.append(key)
        top = header_height + index * row_height
        draw.rectangle((0, top, width, top + row_height), fill="#172129" if index % 2 == 0 else "#111C23")
        draw.line((0, top, width, top), fill="#29404B", width=1)
        proposal = item.get("proposals", {}).get("proposal")
        if not isinstance(proposal, dict):
            raise AtlasError(f"atlas v8 pass 缺 Luna A proposal：{key}")
        preview_path = verify_record(proposal["previews"]["80"], f"atlas v8 preview {key}")
        with Image.open(preview_path) as opened:
            preview = opened.convert("RGBA").resize((92, 92), Image.Resampling.NEAREST)
        checker = Image.new("RGB", (92, 92), "#263640")
        checker.paste(preview, mask=preview.getchannel("A"))
        canvas.paste(checker, (20, top + 18))
        draw.text((132, top + 14), "PASS", font=body_font, fill="#78E0C4")
        draw.text((278, top + 14), fit_text(draw, key, body_font, width - 300), font=body_font, fill="#F1F5F6")
        feature = str(proposal.get("featureLabel", ""))
        orientation = str(proposal.get("orientationAction", "keep"))
        detail = f"feature={feature} · orientation={orientation}"
        draw.text((132, top + 52), fit_text(draw, detail, small_font, width - 155), font=small_font, fill="#AFC5CC")
        draw.text((132, top + 82), "human: 真人直接通过当前识别特写", font=small_font, fill="#D8E4E7")
    canvas.save(output, format="PNG", optimize=False, compress_level=9)
    return keys


def build_calibration(
    manifest_path: Path,
    manifest: dict[str, Any],
    feedback_path: Path,
    feedback: dict[str, Any],
    review_batch: Path,
    review: dict[str, Any],
    receipt: dict[str, Any],
    panel_record: dict[str, Any],
    full_record: dict[str, Any],
    full_dimensions: list[int],
    full_patches: int,
    compact_record: dict[str, Any],
    compact_dimensions: list[int],
    compact_patches: int,
) -> dict[str, Any]:
    parent = manifest["humanPreferenceCalibration"]
    calibration = copy.deepcopy(parent)
    current_keys = [item["reviewKey"] for item in review["items"]]
    previous_keys = parent["coverage"]["reviewKeys"]
    if set(current_keys) & set(previous_keys):
        raise AtlasError("atlas v8 最新 5 labels 与历史 181 labels 重叠")
    proposal_flip_count = sum(
        item.get("proposals", {}).get("proposal", {}).get("orientationAction") == "flip_x"
        for item in review["items"]
    )
    calibration["schema"] = SCHEMA
    calibration["mode"] = MODE
    calibration["controllerSource"] = core.artifact(CONTROLLER_PATH)
    calibration["parentManifest"] = core.artifact(manifest_path)
    calibration["feedbackReport"] = core.artifact(feedback_path)
    calibration["currentHumanReview"] = {
        "reviewData": core.artifact(review_batch / "review-data.json"),
        "decisions": core.artifact(review_batch / "portrait-pilot-review-decisions.json"),
        "receipt": core.artifact(review_batch / "human-review-receipt.json"),
        "receiptDigest": receipt["receiptDigest"],
    }
    calibration["latestPass5FeedbackPanel"] = panel_record
    calibration["atlas"] = full_record
    calibration["modelAtlas"] = compact_record
    calibration["contactSheets"] = atlas7.contact_bindings(manifest)
    calibration["adaptiveScaling"] = copy.deepcopy(feedback["adaptiveScaling"])
    coverage = copy.deepcopy(parent["coverage"])
    coverage.update(
        {
            "mode": MODE,
            "decisionCount": 186,
            "passAnchorCount": int(coverage.get("passAnchorCount", 70)) + 5,
            "adjustmentCount": 110,
            "anomalyCount": 1,
            "guidedCorrectionCount": 106,
            "orientationTransformationCount": int(coverage.get("orientationTransformationCount", 18)) + proposal_flip_count,
            "reviewKeys": sorted([*previous_keys, *current_keys]),
            "dimensions": full_dimensions,
            "latestPass5PanelDimensions": atlas7.image_dimensions(ROOT / panel_record["path"]),
            "all186CurrentHumanLabelsVisualized": True,
            "allHumanLabelsVisualized": True,
            "all106GeometryRowsBound": feedback["geometryCalibration"]["cumulativeRowCount"] == 106,
            "stageSpecificConcurrencyBound": True,
        }
    )
    calibration["coverage"] = coverage
    retrieval = copy.deepcopy(parent["modelAtlasRetrieval"])
    retrieval.update(
        {
            "schema": "cf7.portrait-pilot-model-atlas-retrieval.v8",
            "mode": MODE,
            "controllerSource": core.artifact(CONTROLLER_PATH),
            "parentManifest": core.artifact(manifest_path),
            "fullAtlas": full_record,
            "fullAtlasDimensions": full_dimensions,
            "modelAtlasDimensions": compact_dimensions,
            "fullAtlasPatchCount": full_patches,
            "modelAtlasPatchCount": compact_patches,
            "patchReductionFraction": round(1 - compact_patches / full_patches, 6),
            "dynamicHumanLabelCount": 186,
            "latestHumanLabelCount": 5,
            "cumulativeGeometryRowCount": 106,
            "selectedVisualExampleCount": int(retrieval.get("selectedVisualExampleCount", 78)) + 5,
            "latestPass5Panel": panel_record,
            "stageSpecificConcurrency": {
                "selectionMaximumConcurrency": 6,
                "localizationMaximumConcurrency": 3,
                "concurrencyEightAuthorized": False,
            },
        }
    )
    retrieval["gates"].update(
        {
            "all186CurrentHumanLabelsAvailable": True,
            "all106GeometryRowsAvailable": True,
            "latestFivePassExamplesIncluded": True,
            "stageSpecificConcurrencyBound": True,
            "productionWrites": False,
        }
    )
    calibration["modelAtlasRetrieval"] = retrieval
    calibration["gates"].update(
        {
            "all186CurrentHumanLabelsBound": True,
            "all106GeometryRowsBound": True,
            "latestFivePassExamplesIncluded": True,
            "stageSpecificConcurrencyBound": True,
            "productionWrites": False,
        }
    )
    return calibration


def derive(args: argparse.Namespace) -> None:
    manifest_path = pilot_path(args.manifest, "atlas v8 parent manifest")
    atlas7.verify_v7(manifest_path)
    feedback_path = pilot_path(args.feedback_report, "atlas v8 feedback")
    feedback = check_feedback(feedback_path, args.feedback_batch_id)
    review_batch = pilot_path(args.review_batch, "atlas v8 review batch")
    output = pilot_path(args.output, "atlas v8 output")
    if output.exists():
        raise AtlasError(f"输出已存在，禁止覆盖：{output}")
    manifest = load_json(manifest_path, "atlas v8 parent manifest")
    review = load_json(review_batch / "review-data.json", "atlas v8 review data")
    decisions = load_json(review_batch / "portrait-pilot-review-decisions.json", "atlas v8 decisions")
    receipt = load_json(review_batch / "human-review-receipt.json", "atlas v8 receipt")
    if receipt.get("status") != "human_reviewed_approved" or receipt.get("counts", {}).get("eligiblePassed") != 5:
        raise AtlasError("atlas v8 receipt 必须为 5/5 approved")
    output.mkdir(parents=True)
    parent = manifest["humanPreferenceCalibration"]
    parent_full = verify_record(parent["atlas"], "atlas v8 parent full atlas")
    parent_compact = verify_record(parent["modelAtlas"], "atlas v8 parent compact atlas")
    width = atlas7.image_dimensions(parent_full)[0]
    panel_path = output / "latest5-human-preference-panel.png"
    keys = build_panel(panel_path, width, review, decisions)
    if sorted(keys) != sorted(decisions["decisions"]):
        raise AtlasError("atlas v8 panel reviewKey 漂移")
    full_path = output / "feedback-preference-atlas-186.png"
    compact_path = output / "compact-feedback-model-atlas-186.png"
    full_dimensions, full_patches = atlas7.append_panel(parent_full, panel_path, full_path)
    compact_dimensions, compact_patches = atlas7.append_panel(parent_compact, panel_path, compact_path)
    if compact_patches >= full_patches:
        raise AtlasError("atlas v8 compact patch 未严格减少")
    panel_record = core.artifact(panel_path)
    full_record = core.artifact(full_path)
    compact_record = core.artifact(compact_path)
    calibration = build_calibration(
        manifest_path,
        manifest,
        feedback_path,
        feedback,
        review_batch,
        review,
        receipt,
        panel_record,
        full_record,
        full_dimensions,
        full_patches,
        compact_record,
        compact_dimensions,
        compact_patches,
    )
    manifest["batchId"] = args.batch_id
    manifest["createdAt"] = atlas7.rescue.base.utc_now()
    manifest["humanPreferenceCalibration"] = calibration
    manifest["sourceEnvelope"]["humanPreferenceCalibration"] = calibration
    manifest["sourceEnvelope"]["batchId"] = args.batch_id
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    for path in (
        CONTROLLER_PATH,
        ATLAS_V7_PATH,
        FEEDBACK_V8_PATH,
        manifest_path,
        feedback_path,
        review_batch / "review-data.json",
        review_batch / "portrait-pilot-review-decisions.json",
        review_batch / "human-review-receipt.json",
        panel_path,
        full_path,
        compact_path,
    ):
        add_artifact(source_files, path)
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceDigest"] = core.sha256_bytes(core.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    core.write_json(output / "candidate-manifest.json", manifest)
    print(json.dumps(verify_v8(output / "candidate-manifest.json"), ensure_ascii=False))


def verify_v8(manifest_path: Path) -> dict[str, Any]:
    manifest = core.verify_manifest(manifest_path)
    calibration = manifest.get("humanPreferenceCalibration")
    if not isinstance(calibration, dict) or calibration != manifest.get("sourceEnvelope", {}).get("humanPreferenceCalibration"):
        raise AtlasError("atlas v8 calibration 顶层与 source envelope 漂移")
    parent_path = verify_record(calibration.get("parentManifest"), "atlas v8 parent manifest")
    atlas7.verify_v7(parent_path)
    feedback_path = verify_record(calibration.get("feedbackReport"), "atlas v8 feedback")
    feedback = load_json(feedback_path, "atlas v8 feedback")
    check_feedback(feedback_path, feedback["batchId"])
    panel_path = verify_record(calibration.get("latestPass5FeedbackPanel"), "atlas v8 panel")
    full_path = verify_record(calibration.get("atlas"), "atlas v8 full atlas")
    compact_path = verify_record(calibration.get("modelAtlas"), "atlas v8 compact atlas")
    parent = load_json(parent_path, "atlas v8 parent")
    parent_calibration = parent["humanPreferenceCalibration"]
    parent_full = verify_record(parent_calibration["atlas"], "atlas v8 parent full atlas")
    parent_compact = verify_record(parent_calibration["modelAtlas"], "atlas v8 parent compact atlas")
    atlas7.assert_appended(parent_full, panel_path, full_path, "full atlas v8")
    atlas7.assert_appended(parent_compact, panel_path, compact_path, "compact atlas v8")
    coverage = calibration.get("coverage", {})
    retrieval = calibration.get("modelAtlasRetrieval", {})
    full_dimensions = atlas7.image_dimensions(full_path)
    compact_dimensions = atlas7.image_dimensions(compact_path)
    full_patches = math.ceil(full_dimensions[0] / 32) * math.ceil(full_dimensions[1] / 32)
    compact_patches = math.ceil(compact_dimensions[0] / 32) * math.ceil(compact_dimensions[1] / 32)
    if (
        calibration.get("schema") != SCHEMA
        or calibration.get("mode") != MODE
        or coverage.get("decisionCount") != 186
        or coverage.get("passAnchorCount") != 75
        or coverage.get("adjustmentCount") != 110
        or coverage.get("guidedCorrectionCount") != 106
        or len(coverage.get("reviewKeys", [])) != 186
        or coverage.get("dimensions") != full_dimensions
        or coverage.get("all186CurrentHumanLabelsVisualized") is not True
        or coverage.get("all106GeometryRowsBound") is not True
        or retrieval.get("dynamicHumanLabelCount") != 186
        or retrieval.get("latestHumanLabelCount") != 5
        or retrieval.get("cumulativeGeometryRowCount") != 106
        or retrieval.get("fullAtlasPatchCount") != full_patches
        or retrieval.get("modelAtlasPatchCount") != compact_patches
        or compact_patches >= full_patches
        or retrieval.get("stageSpecificConcurrency", {}).get("selectionMaximumConcurrency") != 6
        or retrieval.get("stageSpecificConcurrency", {}).get("localizationMaximumConcurrency") != 3
        or retrieval.get("stageSpecificConcurrency", {}).get("concurrencyEightAuthorized") is not False
        or calibration.get("gates", {}).get("all186CurrentHumanLabelsBound") is not True
        or calibration.get("gates", {}).get("productionWrites") is not False
    ):
        raise AtlasError("atlas v8 186-label / 106-geometry / stage-concurrency gate 非法")
    artifact_count = 0
    for record in manifest["sourceEnvelope"].get("sourceFiles", []):
        verify_record(record, "atlas v8 source file")
        artifact_count += 1
    return {
        "status": "human_preference_atlas_v8_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "dynamicHumanLabels": 186,
        "geometryRows": 106,
        "recommendedNextShardSize": feedback["adaptiveScaling"]["recommendedNextShardSize"],
        "selectionMaximumConcurrency": 6,
        "localizationMaximumConcurrency": 3,
        "fullAtlasPatches": full_patches,
        "modelAtlasPatches": compact_patches,
        "patchReductionFraction": round(1 - compact_patches / full_patches, 6),
        "artifactCount": artifact_count,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_v8(pilot_path(args.manifest, "atlas v8 manifest")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    derive_parser = commands.add_parser("derive")
    derive_parser.add_argument("--manifest", required=True)
    derive_parser.add_argument("--feedback-report", required=True)
    derive_parser.add_argument("--feedback-batch-id", required=True)
    derive_parser.add_argument("--review-batch", required=True)
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
        print(f"portrait feedback atlas v8 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
