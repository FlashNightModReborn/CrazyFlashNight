#!/usr/bin/env python3
"""Render orientation-aware review candidates with a diagnostic-bound occupancy bypass."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
ORIENTATION_CONTROLLER = Path(__file__).with_name("render-feature-orientation-v1.py").resolve()
BASE_CONTROLLER = Path(__file__).with_name("prepare_pilot.py").resolve()
RECOVERY_CONTROLLER = Path(__file__).with_name("derive-localization-first-answer-report-v1.js").resolve()
EXPECTED_ORIENTATION_SHA256 = "F9C70E63B100AD132AC76486B3293A34407A305A998D5CA493ECD54B3722D4BA"
EXPECTED_BASE_SHA256 = "41B9BAADB5936F0E916381167048EFE86355F9869974FF95453D565BB3E25B5A"
EXPECTED_RECOVERY_SHA256 = "3462E4EB69A5CB278B245A9573DA95A386D2CE2BC63676473FC4EEA939DFFFE4"
RECOVERY_VERSION = "portrait-pilot-localization-first-answer-human-review-v1"
ACCEPTANCE_SCOPE = "locked_candidate_feature_geometry_and_orientation_for_human_review_only"
SAFETY_SCHEMA = "cf7.portrait-pilot-pillow-large-frame-safety.v1"


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载模块：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_controllers():
    if file_sha256(ORIENTATION_CONTROLLER) != EXPECTED_ORIENTATION_SHA256:
        raise RuntimeError("方向渲染控制器字节已漂移")
    if file_sha256(BASE_CONTROLLER) != EXPECTED_BASE_SHA256:
        raise RuntimeError("基础渲染控制器字节已漂移")
    if file_sha256(RECOVERY_CONTROLLER) != EXPECTED_RECOVERY_SHA256:
        raise RuntimeError("首答恢复控制器字节已漂移")
    orientation = load_module(ORIENTATION_CONTROLLER, "portrait_orientation_human_review_base")
    base = orientation.load_base()
    return orientation, base


def stable_selection(selection: dict[str, Any]) -> bytes:
    return json.dumps(
        selection,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def selection_digest(selection: dict[str, Any]) -> str:
    return hashlib.sha256(stable_selection(selection)).hexdigest().upper()


def load_recovery_model(base, model_report_path: Path) -> tuple[dict[str, Any], set[tuple[str, str]], set[str]]:
    report = base.load_json(model_report_path)
    base.verify_digest_object(report, "reportDigest", "首答恢复模型报告")
    gates = report.get("gates", {})
    if (
        report.get("schema") != "cf7.portrait-pilot-feature-model-report.v1"
        or report.get("status") != "candidate_proposed"
        or report.get("productionReady") is not False
        or report.get("humanReviewRequired") is not True
        or report.get("acceptanceScope") != ACCEPTANCE_SCOPE
        or report.get("controller", {}).get("version") != RECOVERY_VERSION
        or gates.get("strictFeatureOccupancyAccepted") is not False
        or gates.get("featureGeometryForwardedOnlyForHumanReview") is not True
        or gates.get("humanArtAcceptance") is not False
        or gates.get("productionWrites") is not False
    ):
        raise base.PilotError("模型报告不是受支持的首答几何人审恢复闭包")
    controller_files = report.get("controller", {}).get("files", [])
    recovery_record = next(
        (record for record in controller_files if record.get("path") == base.repo_rel(RECOVERY_CONTROLLER)),
        None,
    )
    if recovery_record is None or base.verify_artifact_record(recovery_record, "首答恢复控制器") != RECOVERY_CONTROLLER:
        raise base.PilotError("模型报告未绑定首答恢复控制器")

    violations: set[tuple[str, str]] = set()
    violation_signatures: set[str] = set()
    merged_selections: dict[tuple[str, str], dict[str, Any]] = {}
    for run in report.get("runs", []):
        role = str(run.get("role"))
        for selection in run.get("result", {}).get("selections", []):
            merged_selections[(role, str(selection.get("reviewKey")))] = selection
        for batch in run.get("batches", []):
            attempts = batch.get("attempts", [])
            if len(attempts) != 1 or attempts[0].get("attemptNumber") != 1:
                raise base.PilotError("首答恢复批次不是唯一 attempt-1")
            for row in attempts[0].get("occupancyViolations", []):
                violations.add((role, str(row.get("reviewKey"))))
    for key in violations:
        selection = merged_selections.get(key)
        if selection is None:
            raise base.PilotError(f"占比违规找不到模型 selection：{key}")
        violation_signatures.add(selection_digest(selection))
    counts = report.get("counts", {})
    if (
        len(violations) != counts.get("occupancyViolationSelections")
        or len({review_key for _role, review_key in violations}) != counts.get("occupancyViolationReviewKeys")
        or not violations
    ):
        raise base.PilotError("模型报告占比违规计数不闭合")
    comparison_keys = {
        str(row.get("reviewKey"))
        for row in report.get("comparisons", [])
        if row.get("geometryHardGateViolation") is True
    }
    if comparison_keys != {review_key for _role, review_key in violations}:
        raise base.PilotError("模型 comparison 未逐行绑定占比违规")
    return report, violations, violation_signatures


def safety_record(maximum_dimension: int, maximum_pixels: int) -> dict[str, Any]:
    return {
        "schema": SAFETY_SCHEMA,
        "maxImagePixels": maximum_pixels,
        "pillowHardErrorAbovePixels": maximum_pixels * 2,
        "manifestMaximumSourceFrameDimension": maximum_dimension,
        "boundedByManifest": True,
        "unlimitedRasterDecode": False,
    }


def occupancy_recovery_renderer(base, model_report: dict[str, Any], violation_signatures: set[str]):
    original = base.compute_feature_view_box

    def compute(candidate, selection, geometry_contract, intent_policy=None):
        relaxed = copy.deepcopy(geometry_contract)
        for config in relaxed.get("modes", {}).values():
            config["minimumRenderedFeatureLongAxisOccupancy"] = 0.0
            config["minimumRenderedFeatureShortAxisOccupancy"] = 0.0
        geometry = original(candidate, selection, relaxed, intent_policy)
        config = geometry_contract["modes"][selection["framingMode"]]
        minimum_long = float(config["minimumRenderedFeatureLongAxisOccupancy"])
        minimum_short = float(config["minimumRenderedFeatureShortAxisOccupancy"])
        rendered_long = float(geometry["renderedFeatureLongAxisOccupancy"])
        rendered_short = float(geometry["renderedFeatureShortAxisOccupancy"])
        strict = rendered_long + 1e-6 >= minimum_long and rendered_short + 1e-6 >= minimum_short
        signature = selection_digest(selection)
        if strict == (signature in violation_signatures):
            raise base.PilotError(
                f"占比旁路与模型诊断不一致：{selection.get('reviewKey')} strict={strict} signature={signature}"
            )
        geometry["minimumRenderedFeatureLongAxisOccupancy"] = minimum_long
        geometry["minimumRenderedFeatureShortAxisOccupancy"] = minimum_short
        geometry["strictFeatureOccupancyAccepted"] = strict
        geometry["occupancyGateBypassedForHumanReview"] = not strict
        geometry["occupancyRecoverySelectionSha256"] = signature
        geometry["occupancyRecoveryModelReportDigest"] = model_report["reportDigest"]
        return geometry

    return original, compute


def render(args: argparse.Namespace) -> dict[str, Any]:
    orientation, base = load_controllers()
    manifest_path = Path(args.manifest).resolve()
    model_report_path = Path(args.model_report).resolve()
    manifest = base.verify_manifest(manifest_path)
    model_report, violations, signatures = load_recovery_model(base, model_report_path)
    if (
        model_report.get("sourceDigest") != manifest.get("sourceDigest")
        or model_report.get("manifestDigest") != manifest.get("manifestDigest")
    ):
        raise base.PilotError("首答恢复模型报告与 manifest 不闭合")
    report_path = manifest_path.parent / "render-report.json"
    if report_path.exists():
        raise base.PilotError("render-report.json 已存在，禁止覆盖")
    maximum_dimension = int(manifest["featureContract"]["highResolutionRender"]["maximumSourceFrameDimension"])
    if maximum_dimension < 1 or maximum_dimension > 32768:
        raise base.PilotError("manifest maximumSourceFrameDimension 超出有界渲染允许范围")
    maximum_pixels = maximum_dimension * maximum_dimension
    original_max_pixels = Image.MAX_IMAGE_PIXELS
    original_compute, recovery_compute = occupancy_recovery_renderer(base, model_report, signatures)
    base.compute_feature_view_box = recovery_compute
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    try:
        report = orientation.render_with_orientation(base, args)
    finally:
        base.compute_feature_view_box = original_compute
        Image.MAX_IMAGE_PIXELS = original_max_pixels

    actual_violations: set[tuple[str, str]] = set()
    for row in report.get("rows", []):
        geometry = row.get("geometry", {})
        key = (str(row.get("role")), str(row.get("reviewKey")))
        bypassed = geometry.get("occupancyGateBypassedForHumanReview") is True
        if bypassed:
            actual_violations.add(key)
        if (
            bypassed == (geometry.get("strictFeatureOccupancyAccepted") is True)
            or geometry.get("occupancyRecoveryModelReportDigest") != model_report["reportDigest"]
            or geometry.get("occupancyRecoverySelectionSha256") != selection_digest({
                "reviewKey": row["reviewKey"],
                "candidateId": row["candidateId"],
                "featureLabel": row["featureLabel"],
                "framingMode": row["framingMode"],
                "featureBox": row["featureBox"],
                "mustIncludeBox": row["mustIncludeBox"],
                "orientationAction": row["orientationAction"],
                "orientationReason": row["orientationReason"],
                "orientationConfidence": row["orientationConfidence"],
                "confidence": row["confidence"],
                "flags": row["flags"],
            })
        ):
            raise base.PilotError(f"渲染行占比恢复证据漂移：{key}")
    if actual_violations != violations:
        raise base.PilotError("渲染行与模型占比违规集合不一致")

    report["renderer"]["humanReviewOccupancyRecoveryControllerSource"] = base.artifact(Path(__file__).resolve())
    report["renderer"]["humanReviewOccupancyRecoveryModelControllerSource"] = base.artifact(RECOVERY_CONTROLLER)
    report["renderer"]["humanReviewOccupancyRecoveryModelReportArtifact"] = base.artifact(model_report_path)
    report["renderer"]["pillowSafety"] = safety_record(maximum_dimension, maximum_pixels)
    report["renderer"]["occupancyRecoveryPolicy"] = {
        "version": "diagnostic_bound_human_review_occupancy_v1",
        "scope": "render human-review candidates only; no art acceptance and no production write",
        "selectionGeometryChanged": False,
        "manifestGeometryContractChanged": False,
        "safeMarginAndContainmentPreserved": True,
        "fidelityGatePreserved": True,
    }
    report["occupancyRecoverySummary"] = {
        "rows": len(report.get("rows", [])),
        "strictlyAcceptedRows": len(report.get("rows", [])) - len(actual_violations),
        "bypassedForHumanReviewRows": len(actual_violations),
        "reviewKeys": sorted({review_key for _role, review_key in actual_violations}),
        "roleReviewKeys": [
            {"role": role, "reviewKey": review_key}
            for role, review_key in sorted(actual_violations)
        ],
        "modelReportDigest": model_report["reportDigest"],
    }
    report["status"] = "automated_checked_human_review_geometry"
    report["gates"].update({
        "strictFeatureOccupancyAccepted": False,
        "occupancyRecoveryBoundToModelDiagnostics": True,
        "occupancyRecoverySelectionGeometryUnchanged": True,
        "occupancyRecoveryManifestContractUnchanged": True,
        "boundedPillowLargeFrameChecked": True,
        "humanReviewRequired": True,
        "humanArtAcceptance": False,
        "productionWrites": False,
    })
    report.pop("renderDigest", None)
    report["renderDigest"] = base.sha256_bytes(base.stable_bytes(report))
    base.write_json(report_path, report)
    return verify(args)


def verify(args: argparse.Namespace) -> dict[str, Any]:
    orientation, base = load_controllers()
    manifest_path = Path(args.manifest).resolve()
    model_report_path = Path(args.model_report).resolve()
    model_report, violations, _signatures = load_recovery_model(base, model_report_path)
    report = orientation.verify_render(base, args)
    renderer = report.get("renderer", {})
    if (
        base.verify_artifact_record(
            renderer.get("humanReviewOccupancyRecoveryControllerSource"),
            "占比恢复渲染控制器",
        ) != Path(__file__).resolve()
        or base.verify_artifact_record(
            renderer.get("humanReviewOccupancyRecoveryModelControllerSource"),
            "占比恢复模型控制器",
        ) != RECOVERY_CONTROLLER
        or base.verify_artifact_record(
            renderer.get("humanReviewOccupancyRecoveryModelReportArtifact"),
            "占比恢复模型报告",
        ) != model_report_path
    ):
        raise base.PilotError("占比恢复 renderer artifact 闭包漂移")
    actual = {
        (str(row.get("role")), str(row.get("reviewKey")))
        for row in report.get("rows", [])
        if row.get("geometry", {}).get("occupancyGateBypassedForHumanReview") is True
    }
    summary = report.get("occupancyRecoverySummary", {})
    safety = renderer.get("pillowSafety", {})
    maximum_dimension = int(base.verify_manifest(manifest_path)["featureContract"]["highResolutionRender"]["maximumSourceFrameDimension"])
    gates = report.get("gates", {})
    if (
        report.get("status") != "automated_checked_human_review_geometry"
        or report.get("modelReportDigest") != model_report.get("reportDigest")
        or actual != violations
        or summary.get("bypassedForHumanReviewRows") != len(violations)
        or summary.get("modelReportDigest") != model_report.get("reportDigest")
        or safety != safety_record(maximum_dimension, maximum_dimension * maximum_dimension)
        or gates.get("strictFeatureOccupancyAccepted") is not False
        or not all(gates.get(field) is True for field in (
            "occupancyRecoveryBoundToModelDiagnostics",
            "occupancyRecoverySelectionGeometryUnchanged",
            "occupancyRecoveryManifestContractUnchanged",
            "boundedPillowLargeFrameChecked",
            "humanReviewRequired",
        ))
        or gates.get("humanArtAcceptance") is not False
        or gates.get("productionWrites") is not False
    ):
        raise base.PilotError("占比恢复 render report 状态、计数或 gates 不闭合")
    return report


def self_test() -> None:
    orientation, _base = load_controllers()
    orientation.self_test()
    sample = {"reviewKey": "x", "candidateId": "c", "featureBox": [0, 0, 1, 1]}
    digest = selection_digest(sample)
    if len(digest) != 64 or not all(character in "0123456789ABCDEF" for character in digest):
        raise RuntimeError("selection digest 自检失败")
    print(json.dumps({
        "status": "human_review_occupancy_renderer_self_tested",
        "selectionDigest": digest,
        "strictFeatureOccupancyAccepted": False,
        "humanArtAcceptance": False,
    }, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("render", "check"):
        command = subparsers.add_parser(name)
        command.add_argument("--manifest", required=True)
        command.add_argument("--model-report", required=True)
    subparsers.add_parser("self-test")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    if args.command == "self-test":
        self_test()
        return
    report = render(args) if args.command == "render" else verify(args)
    print(json.dumps({
        "status": "human_review_occupancy_render_verified" if args.command == "check" else report["status"],
        "renderDigest": report["renderDigest"],
        "rows": len(report["rows"]),
        "flipX": report["orientationSummary"]["flipX"],
        "occupancyBypassRows": report["occupancyRecoverySummary"]["bypassedForHumanReviewRows"],
        "humanArtAcceptance": report["gates"]["humanArtAcceptance"],
        "productionWrites": report["gates"]["productionWrites"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
