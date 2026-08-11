#!/usr/bin/env python3
"""Attach the full human preference history with the frozen Fast3 profile."""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image


CONTROLLER_PATH = Path(__file__).resolve()
V3_CONTROLLER_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas-v3.py")
V3_SPEC = importlib.util.spec_from_file_location("cf7_portrait_feedback_atlas_v3", V3_CONTROLLER_PATH)
if V3_SPEC is None or V3_SPEC.loader is None:
    raise RuntimeError(f"无法加载 feedback atlas v3 controller：{V3_CONTROLLER_PATH}")
v3 = importlib.util.module_from_spec(V3_SPEC)
V3_SPEC.loader.exec_module(v3)
v2 = v3.v2
base = v3.base

SCHEMA = "cf7.portrait-pilot-human-preference-atlas.v4"
MODE = "bound_all_human_labels_with_guided_orientation_and_fast3_execution"
FEEDBACK_SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v3"
MAXIMUM_CONCURRENCY = 3
TIMEOUT_SECONDS = 600


def verify_feedback(feedback: dict[str, Any], shard_size: int) -> dict[str, Any]:
    base.verify_digest(feedback, "feedbackDigest", "feedback report")
    scaling = feedback.get("adaptiveScaling", {})
    profile = scaling.get("executionProfile", {})
    if (
        feedback.get("schema") != FEEDBACK_SCHEMA
        or feedback.get("status") != "human_feedback_calibrated"
        or feedback.get("productionReady") is not False
        or scaling.get("humanReviewPageLimit") is not None
        or scaling.get("reviewConsolidationPolicy") != "single_page_preferred"
        or scaling.get("recommendedNextShardSize") != shard_size
        or scaling.get("maximumConcurrency") != MAXIMUM_CONCURRENCY
        or profile.get("model") != "Luna Max"
        or profile.get("serviceTier") != "fast"
        or profile.get("maximumConcurrency") != MAXIMUM_CONCURRENCY
        or profile.get("timeoutSeconds") != TIMEOUT_SECONDS
        or profile.get("concurrencyIncreaseEligible") is not False
    ):
        raise base.AtlasError("feedback v3 adaptive scaling / Fast3 执行配置与下一 shard 不一致")
    return scaling


def verify_optional_transform_dependencies(reports: list[tuple[Path, dict[str, Any]]], label: str) -> None:
    for index, (_path, report) in enumerate(reports):
        dependency = report.get("renderer", {}).get("baseControllerSource")
        if dependency is not None:
            base.verify_artifact(dependency, f"{label} base controller {index}")


def load_transforms(
    values: list[str], schema: str, status: str, label: str
) -> list[tuple[Path, dict[str, Any]]]:
    reports = v3.load_transform_reports(values, schema, status, label)
    verify_optional_transform_dependencies(reports, label)
    return reports


def verify_derived(manifest_path: Path) -> dict[str, Any]:
    manifest = base.load_json(manifest_path, "derived manifest")
    base.verify_digest(manifest, "manifestDigest", "derived manifest")
    envelope = manifest.get("sourceEnvelope")
    if not isinstance(envelope, dict) or base.sha256_bytes(base.stable_bytes(envelope)) != manifest.get("sourceDigest"):
        raise base.AtlasError("derived sourceDigest 不匹配")
    calibration = envelope.get("humanPreferenceCalibration")
    if (
        not isinstance(calibration, dict)
        or calibration.get("schema") != SCHEMA
        or calibration.get("mode") != MODE
        or calibration.get("gates", {}).get("allHumanLabelsVisualized") is not True
        or calibration.get("gates", {}).get("examplesAreNotCandidates") is not True
        or calibration.get("gates", {}).get("executionProfileBound") is not True
        or calibration.get("gates", {}).get("productionWrites") is not False
    ):
        raise base.AtlasError("derived human preference calibration v4 gate 非法")
    for index, record in enumerate(envelope.get("sourceFiles", [])):
        base.verify_artifact(record, f"source file {index}")
    for field, label in (
        ("controllerSource", "feedback atlas v4 controller"),
        ("v3ControllerSource", "feedback atlas v3 dependency"),
        ("v2ControllerSource", "feedback atlas v2 dependency"),
        ("baseControllerSource", "feedback atlas v1 dependency"),
    ):
        base.verify_artifact(calibration.get(field), label)

    feedback_path = base.verify_artifact(calibration.get("feedbackReport"), "feedback report")
    feedback = base.load_json(feedback_path, "feedback report")
    scaling = verify_feedback(feedback, int(manifest.get("campaign", {}).get("shardSize", 0)))
    if calibration.get("adaptiveScaling") != scaling:
        raise base.AtlasError("atlas v4 adaptive scaling 与 feedback 漂移")
    campaign = manifest.get("campaign", {})
    if (
        campaign.get("modelRecommendation") != "Luna Max"
        or campaign.get("serviceTierRecommendation") != "fast"
        or campaign.get("maxConcurrencyRecommendation") != MAXIMUM_CONCURRENCY
        or campaign.get("timeoutSecondsRecommendation") != TIMEOUT_SECONDS
    ):
        raise base.AtlasError("derived campaign 执行建议未冻结到 Luna Max / Fast3 / 600s")

    orientation_paths = []
    for index, record in enumerate(calibration.get("orientationReports", [])):
        orientation_paths.append(str(base.verify_artifact(record, f"orientation report {index}")))
    guided_orientation_paths = []
    for index, record in enumerate(calibration.get("guidedOrientationReports", [])):
        guided_orientation_paths.append(str(base.verify_artifact(record, f"guided orientation report {index}")))
    if orientation_paths:
        load_transforms(
            orientation_paths,
            v3.STANDARD_ORIENTATION_SCHEMA,
            "human_orientation_adjustment_checked",
            "orientation report",
        )
    if guided_orientation_paths:
        load_transforms(
            guided_orientation_paths,
            v3.GUIDED_ORIENTATION_SCHEMA,
            "human_guided_orientation_adjustment_checked",
            "guided orientation report",
        )

    atlas_path = base.verify_artifact(calibration.get("atlas"), "feedback atlas")
    with Image.open(atlas_path) as atlas:
        if list(atlas.size) != calibration.get("coverage", {}).get("dimensions"):
            raise base.AtlasError("feedback atlas 尺寸漂移")
    expected_sheets = 1 + len(manifest.get("modelBatches", []))
    if len(calibration.get("contactSheets", [])) != expected_sheets:
        raise base.AtlasError("calibrated contact sheet 数不闭合")
    sheet_records = [
        manifest.get("contactSheet"),
        *(batch.get("contactSheet") for batch in manifest.get("modelBatches", [])),
    ]
    for index, record in enumerate(sheet_records):
        path = base.verify_artifact(record, f"calibrated contact sheet {index}")
        evidence = calibration["contactSheets"][index]
        if evidence.get("composite") != record:
            raise base.AtlasError("calibrated contact sheet evidence 漂移")
        with Image.open(path) as image:
            if list(image.size) != evidence.get("compositeDimensions"):
                raise base.AtlasError("calibrated contact sheet 尺寸漂移")

    expected = v2.receipt_counts(calibration)
    coverage = calibration.get("coverage", {})
    expected_pass = expected.get("pass", 0)
    expected_adjustment = expected.get("adjustment", 0)
    expected_anomaly = expected["decisionCount"] - expected_pass - expected_adjustment
    if (
        coverage.get("schema") != SCHEMA
        or coverage.get("mode") != MODE
        or coverage.get("decisionCount") != expected["decisionCount"]
        or coverage.get("passAnchorCount") != expected_pass
        or coverage.get("adjustmentCount") != expected_adjustment
        or coverage.get("guidedCorrectionCount", 0) + coverage.get("orientationOnlyCorrectionCount", 0)
        != expected_adjustment
        or coverage.get("guidedOrientationCount", 0) > coverage.get("guidedCorrectionCount", 0)
        or coverage.get("orientationTransformationCount", 0)
        != coverage.get("orientationOnlyCorrectionCount", 0) + coverage.get("guidedOrientationCount", 0)
        or coverage.get("anomalyCount") != expected_anomaly
        or coverage.get("statusCounts") != {key: value for key, value in expected.items() if key != "decisionCount"}
        or coverage.get("allHumanLabelsVisualized") is not True
        or len(coverage.get("reviewKeys", [])) != expected["decisionCount"]
    ):
        raise base.AtlasError("累计人类标签动态覆盖数不闭合")
    return {
        "status": "campaign_human_preference_atlas_v4_verified",
        "manifest": base.repo_rel(manifest_path),
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "atlasSha256": calibration["atlas"]["sha256"],
        "humanLabels": coverage["decisionCount"],
        "passAnchors": coverage["passAnchorCount"],
        "guidedCorrections": coverage["guidedCorrectionCount"],
        "orientationOnly": coverage["orientationOnlyCorrectionCount"],
        "guidedOrientations": coverage["guidedOrientationCount"],
        "adjustments": coverage["adjustmentCount"],
        "anomalies": coverage["anomalyCount"],
        "contactSheets": expected_sheets,
        "maximumConcurrency": MAXIMUM_CONCURRENCY,
        "productionReady": False,
    }


def attach(args: argparse.Namespace) -> None:
    base_path = base.repo_path(args.base_manifest, "base manifest")
    output_dir = base.repo_path(args.output, "output")
    try:
        output_dir.relative_to(base.PILOT_ROOT.resolve())
    except ValueError as error:
        raise base.AtlasError("output 必须位于 tmp/portrait-pilot") from error
    if output_dir.exists():
        raise base.AtlasError(f"输出目录已存在，禁止覆盖：{output_dir}")
    if not args.batch_id or len(args.batch_id) > 128 or not all(
        character.isalnum() or character in "._-" for character in args.batch_id
    ):
        raise base.AtlasError("batch-id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")

    manifest = base.load_json(base_path, "base manifest")
    base.verify_digest(manifest, "manifestDigest", "base manifest")
    if base.sha256_bytes(base.stable_bytes(manifest.get("sourceEnvelope"))) != manifest.get("sourceDigest"):
        raise base.AtlasError("base manifest sourceDigest 不匹配")
    if manifest.get("status") != "campaign_shard_prepared" or manifest.get("productionReady") is not False:
        raise base.AtlasError("base manifest 尚不是未投产 campaign shard")
    font_path = base.verify_font(manifest)

    feedback_path = base.repo_path(args.feedback_report, "feedback report")
    feedback = base.load_json(feedback_path, "feedback report")
    scaling = verify_feedback(feedback, int(manifest.get("campaign", {}).get("shardSize", 0)))
    receipt_reports = base.load_reports(args.human_review_receipt, "receiptDigest", "human review receipt")
    render_reports = base.load_reports(args.parent_render_report, "renderDigest", "parent render report")
    guided_reports = base.load_reports(args.guided_report, "reportDigest", "human-guided report")
    orientation_reports = load_transforms(
        args.orientation_report,
        v3.STANDARD_ORIENTATION_SCHEMA,
        "human_orientation_adjustment_checked",
        "orientation report",
    )
    guided_orientation_reports = load_transforms(
        args.guided_orientation_report,
        v3.GUIDED_ORIENTATION_SCHEMA,
        "human_guided_orientation_adjustment_checked",
        "guided orientation report",
    )

    decisions = base.decision_rows(receipt_reports)
    initial = base.role_rows(render_reports)
    guided = base.guided_rows(guided_reports)
    orientation_only = v3.keyed_transform_rows(orientation_reports, "orientation report")
    guided_orientation = v3.keyed_transform_rows(guided_orientation_reports, "guided orientation report")
    geometry_keys = {row.get("reviewKey") for row in feedback.get("geometryCalibration", {}).get("rows", [])}
    if geometry_keys != set(guided):
        raise base.AtlasError("累计 geometry 行与 human-guided visuals 不闭合")

    output_dir.mkdir(parents=True)
    atlas_path = output_dir / "feedback-preference-atlas.png"
    coverage = v3.build_atlas(
        atlas_path,
        font_path,
        decisions,
        initial,
        guided,
        orientation_only,
        guided_orientation,
        feedback,
    )
    coverage["schema"] = SCHEMA
    coverage["mode"] = MODE
    atlas_record = base.artifact(atlas_path)

    sheet_records: list[dict[str, Any]] = []
    full_sheet = base.composite_sheet(
        manifest["contactSheet"], atlas_path, output_dir / "feature-contact-sheet-with-feedback.png"
    )
    sheet_records.append(full_sheet)
    model_sheets: list[dict[str, Any]] = []
    for model_batch in manifest["modelBatches"]:
        record = base.composite_sheet(
            model_batch["contactSheet"],
            atlas_path,
            output_dir / f"{model_batch['modelBatchId']}-with-feedback.png",
        )
        sheet_records.append(record)
        model_sheets.append(record["composite"])

    derived = copy.deepcopy(manifest)
    derived.pop("manifestDigest", None)
    derived["batchId"] = args.batch_id
    derived["createdAt"] = base.utc_now()
    derived["contactSheet"] = full_sheet["composite"]
    for model_batch, contact_sheet in zip(derived["modelBatches"], model_sheets):
        model_batch["contactSheet"] = contact_sheet
    derived["campaign"]["modelRecommendation"] = "Luna Max"
    derived["campaign"]["serviceTierRecommendation"] = "fast"
    derived["campaign"]["maxConcurrencyRecommendation"] = MAXIMUM_CONCURRENCY
    derived["campaign"]["timeoutSecondsRecommendation"] = TIMEOUT_SECONDS

    orientation_paths = [path for path, _report in orientation_reports]
    guided_orientation_paths = [path for path, _report in guided_orientation_reports]
    evidence_paths = [
        base_path,
        feedback_path,
        CONTROLLER_PATH,
        V3_CONTROLLER_PATH,
        v3.V2_CONTROLLER_PATH,
        v2.BASE_CONTROLLER_PATH,
        *orientation_paths,
        *guided_orientation_paths,
        *(path for path, _value in receipt_reports),
        *(path for path, _value in render_reports),
        *(path for path, _value in guided_reports),
        atlas_path,
    ]
    source_files = list(derived["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in evidence_paths:
        record = base.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])

    calibration = {
        "schema": SCHEMA,
        "mode": MODE,
        "baseManifest": base.artifact(base_path),
        "feedbackReport": base.artifact(feedback_path),
        "humanReviewReceipts": [base.artifact(path) for path, _value in receipt_reports],
        "parentRenderReports": [base.artifact(path) for path, _value in render_reports],
        "humanGuidedRenderReports": [base.artifact(path) for path, _value in guided_reports],
        "orientationReports": [base.artifact(path) for path in orientation_paths],
        "guidedOrientationReports": [base.artifact(path) for path in guided_orientation_paths],
        "controllerSource": base.artifact(CONTROLLER_PATH),
        "v3ControllerSource": base.artifact(V3_CONTROLLER_PATH),
        "v2ControllerSource": base.artifact(v3.V2_CONTROLLER_PATH),
        "baseControllerSource": base.artifact(v2.BASE_CONTROLLER_PATH),
        "atlas": atlas_record,
        "coverage": coverage,
        "contactSheets": sheet_records,
        "adaptiveScaling": scaling,
        "gates": {
            "allHumanLabelsVisualized": coverage["allHumanLabelsVisualized"],
            "rawHumanReceiptsBound": True,
            "deterministicHumanOutputsBound": True,
            "guidedOrientationReplacesGuidedCropWithoutDoubleCounting": True,
            "examplesAreNotCandidates": True,
            "noHumanPageSizeLimit": True,
            "executionProfileBound": True,
            "modelTrainingClaim": False,
            "productionWrites": False,
        },
    }
    derived["sourceEnvelope"]["batchId"] = args.batch_id
    derived["sourceEnvelope"]["sourceFiles"] = source_files
    derived["sourceEnvelope"]["humanPreferenceCalibration"] = calibration
    derived["sourceDigest"] = base.sha256_bytes(base.stable_bytes(derived["sourceEnvelope"]))
    derived["humanPreferenceCalibration"] = calibration
    derived["manifestDigest"] = base.sha256_bytes(base.stable_bytes(derived))
    manifest_path = output_dir / "candidate-manifest.json"
    base.write_json(manifest_path, derived)
    print(json.dumps(verify_derived(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_derived(base.repo_path(args.manifest, "derived manifest")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    attach_parser = commands.add_parser("attach")
    attach_parser.add_argument("--base-manifest", required=True)
    attach_parser.add_argument("--feedback-report", required=True)
    attach_parser.add_argument("--human-review-receipt", action="append", required=True)
    attach_parser.add_argument("--parent-render-report", action="append", required=True)
    attach_parser.add_argument("--guided-report", action="append", required=True)
    attach_parser.add_argument("--orientation-report", action="append", required=True)
    attach_parser.add_argument("--guided-orientation-report", action="append", required=True)
    attach_parser.add_argument("--output", required=True)
    attach_parser.add_argument("--batch-id", required=True)
    attach_parser.set_defaults(handler=attach)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--manifest", required=True)
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (base.AtlasError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"portrait feedback atlas v4 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
