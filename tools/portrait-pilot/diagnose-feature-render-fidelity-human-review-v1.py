#!/usr/bin/env python3
"""Measure all recovery-bound human-review render rows without accepting MAE exceptions."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
HUMAN_REVIEW_RENDERER = Path(__file__).with_name("render-feature-orientation-human-review-v1.py").resolve()
ALPHA_POLICY_SOURCE = Path(__file__).with_name("render-feature-large-frame-fidelity-v1.py").resolve()
EXPECTED_HUMAN_REVIEW_RENDERER_SHA256 = "C8D5655DC78AB638A56DEA98DE30C38FB7E25FB072D7A606B3DFF398568169A9"
EXPECTED_ALPHA_POLICY_SHA256 = "611EB422DD4EDFE0564B1284031154AA7C3584A1813B8865AB6FAE9D1AD2FAD0"
SCHEMA = "cf7.portrait-pilot-feature-fidelity-diagnostic.v2"
MAXIMUM_SUPPORTED_FRAME_DIMENSION = 16_384


def file_sha256(path: Path) -> str:
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载模块：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_dependencies():
    if file_sha256(HUMAN_REVIEW_RENDERER) != EXPECTED_HUMAN_REVIEW_RENDERER_SHA256:
        raise RuntimeError("人审占比恢复 renderer 字节已漂移")
    if file_sha256(ALPHA_POLICY_SOURCE) != EXPECTED_ALPHA_POLICY_SHA256:
        raise RuntimeError("alpha 表示诊断策略字节已漂移")
    human_renderer = load_module(HUMAN_REVIEW_RENDERER, "portrait_human_review_fidelity_renderer")
    alpha_policy = load_module(ALPHA_POLICY_SOURCE, "portrait_human_review_fidelity_alpha_policy")
    _orientation, base = human_renderer.load_controllers()
    return human_renderer, alpha_policy, base


def ensure_output(value: str, must_exist: bool) -> Path:
    output = Path(value).resolve()
    try:
        relative = output.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise RuntimeError("诊断输出必须位于 tmp/portrait-pilot 下") from error
    if not relative.parts:
        raise RuntimeError("诊断输出不能是 portrait-pilot 根目录")
    if must_exist and not output.is_dir():
        raise RuntimeError("诊断输出缺失")
    if not must_exist and output.exists():
        raise RuntimeError(f"诊断输出已存在：{output}")
    return output


def bounded_pixel_limit(manifest: dict[str, Any]) -> tuple[int, int]:
    maximum_dimension = manifest.get("featureContract", {}).get("highResolutionRender", {}).get(
        "maximumSourceFrameDimension"
    )
    if (
        not isinstance(maximum_dimension, int)
        or isinstance(maximum_dimension, bool)
        or maximum_dimension < 1
        or maximum_dimension > MAXIMUM_SUPPORTED_FRAME_DIMENSION
    ):
        raise RuntimeError("maximumSourceFrameDimension 越界")
    return maximum_dimension, maximum_dimension * maximum_dimension


def load_inputs(base, human_renderer, manifest_arg: str, model_report_arg: str):
    manifest_path = Path(manifest_arg).resolve()
    model_report_path = Path(model_report_arg).resolve()
    manifest = base.verify_manifest(manifest_path)
    model_report, violations, signatures = human_renderer.load_recovery_model(base, model_report_path)
    if (
        model_report.get("sourceDigest") != manifest.get("sourceDigest")
        or model_report.get("manifestDigest") != manifest.get("manifestDigest")
    ):
        raise base.PilotError("manifest/model report 摘要不闭合")
    return manifest_path, model_report_path, manifest, model_report, violations, signatures


def run(args: argparse.Namespace) -> dict[str, Any]:
    human_renderer, alpha_policy, base = load_dependencies()
    manifest_path, model_report_path, manifest, model_report, violations, signatures = load_inputs(
        base, human_renderer, args.manifest, args.model_report
    )
    output = ensure_output(args.output, False)
    if not args.batch_id or len(args.batch_id) > 128:
        raise base.PilotError("诊断 batch id 非法")
    maximum_dimension, maximum_pixels = bounded_pixel_limit(manifest)
    limit = float(manifest["featureContract"]["highResolutionRender"]["fidelityMeanAbsoluteErrorLimit"])
    expected_rows = sum(not item.get("blocked") for item in manifest.get("reviewItems", [])) * 2
    original_metric = base.image_mean_absolute_error
    admitted_calls: list[dict[str, Any]] = []

    def diagnostic_metric(left: Image.Image, right: Image.Image) -> tuple[float, list[float]]:
        mean, channels = original_metric(left, right)
        if mean > limit:
            admitted_calls.append({
                "meanAbsoluteError": float(mean),
                "perChannel": [float(value) for value in channels],
                "alphaEvidence": alpha_policy.alpha_representation_evidence(left, right),
            })
            return limit, [limit, limit, limit, limit]
        return mean, channels

    output.mkdir(parents=True)
    base_report_path = output / "diagnostic-base-render-report.json"
    original_max_pixels = Image.MAX_IMAGE_PIXELS
    original_module_file = base.__file__
    original_compute, recovery_compute = human_renderer.occupancy_recovery_renderer(base, model_report, signatures)
    base.image_mean_absolute_error = diagnostic_metric
    base.compute_feature_view_box = recovery_compute
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    try:
        base.__file__ = str(Path(__file__).resolve())
        with contextlib.redirect_stdout(io.StringIO()):
            base.render_feature_refinement(manifest, model_report, output, base_report_path)
    finally:
        base.__file__ = original_module_file
        base.image_mean_absolute_error = original_metric
        base.compute_feature_view_box = original_compute
        Image.MAX_IMAGE_PIXELS = original_max_pixels

    base_report = base.load_json(base_report_path)
    base.verify_digest_object(base_report, "renderDigest", "诊断基础渲染报告")
    rows: list[dict[str, Any]] = []
    for row in base_report.get("rows", []):
        mean, channels, evidence = alpha_policy.recompute_row_fidelity(
            manifest,
            row,
            original_metric,
            maximum_pixels,
        )
        rows.append({
            "role": row["role"],
            "reviewKey": row["reviewKey"],
            "candidateId": row["candidateId"],
            "frame": row["frame"],
            "meanAbsoluteError": mean,
            "perChannel": dict(zip(("red", "green", "blue", "alpha"), channels)),
            "limit": limit,
            "primaryPassed": mean <= limit,
            "alphaRepresentationEvidence": evidence,
            "occupancyGateBypassedForHumanReview": row.get("geometry", {}).get(
                "occupancyGateBypassedForHumanReview"
            ) is True,
            "sourceCandidate": row["sourceCandidate"],
            "sourceHighResolution": row["sourceHighResolution"],
        })
    if len(rows) != expected_rows:
        raise base.PilotError(f"诊断渲染行数不闭合：expected={expected_rows} actual={len(rows)}")
    actual_occupancy = {
        (str(row["role"]), str(row["reviewKey"]))
        for row in rows
        if row["occupancyGateBypassedForHumanReview"]
    }
    if actual_occupancy != violations:
        raise base.PilotError("诊断渲染与占比恢复违规集合不一致")
    over_limit = [row for row in rows if not row["primaryPassed"]]
    diagnostic = {
        "schema": SCHEMA,
        "status": "diagnostic_only",
        "productionReady": False,
        "humanReviewRequired": True,
        "batchId": args.batch_id,
        "sourceDigest": manifest["sourceDigest"],
        "manifestDigest": manifest["manifestDigest"],
        "modelReportDigest": model_report["reportDigest"],
        "inputs": {
            "manifest": base.artifact(manifest_path),
            "modelReport": base.artifact(model_report_path),
            "baseRenderReport": base.artifact(base_report_path),
        },
        "controller": {
            "source": base.artifact(Path(__file__).resolve()),
            "baseRendererSource": base.artifact(Path(human_renderer.BASE_CONTROLLER)),
            "humanReviewRendererSource": base.artifact(HUMAN_REVIEW_RENDERER),
            "alphaEvidenceSource": base.artifact(ALPHA_POLICY_SOURCE),
            "maximumSourceFrameDimension": maximum_dimension,
            "maxImagePixels": maximum_pixels,
            "unlimitedRasterDecode": False,
        },
        "summary": {
            "rows": len(rows),
            "primaryPassedRows": len(rows) - len(over_limit),
            "overLimitRows": len(over_limit),
            "alphaEvidencePassedRows": len([
                row for row in over_limit if row["alphaRepresentationEvidence"]["passed"]
            ]),
            "admittedCallsDuringDiagnosticRender": len(admitted_calls),
            "maximumMeanAbsoluteError": max(row["meanAbsoluteError"] for row in rows),
            "occupancyBypassRows": len(actual_occupancy),
        },
        "rows": rows,
        "gates": {
            "allRowsMeasured": len(rows) == expected_rows,
            "diagnosticAdmissionIsNotAcceptance": True,
            "globalThresholdUnchanged": True,
            "occupancyRecoveryBoundToModelDiagnostics": True,
            "boundedPillowDecode": True,
            "humanArtAcceptance": False,
            "productionWrites": False,
        },
    }
    diagnostic["diagnosticDigest"] = base.sha256_bytes(base.stable_bytes(diagnostic))
    report_path = output / "fidelity-diagnostic.json"
    base.write_json(report_path, diagnostic)
    return diagnostic


def check(args: argparse.Namespace) -> dict[str, Any]:
    human_renderer, _alpha_policy, base = load_dependencies()
    report_path = Path(args.report).resolve()
    report = base.load_json(report_path)
    base.verify_digest_object(report, "diagnosticDigest", "fidelity diagnostic")
    if (
        report.get("schema") != SCHEMA
        or report.get("status") != "diagnostic_only"
        or report.get("productionReady") is not False
        or report.get("humanReviewRequired") is not True
    ):
        raise base.PilotError("fidelity diagnostic schema 或状态非法")
    records = [
        *report["inputs"].values(),
        report["controller"]["source"],
        report["controller"]["baseRendererSource"],
        report["controller"]["humanReviewRendererSource"],
        report["controller"]["alphaEvidenceSource"],
    ]
    for row in report["rows"]:
        records.extend((row["sourceCandidate"], row["sourceHighResolution"]))
    for record in records:
        base.verify_artifact_record(record, "fidelity diagnostic artifact")
    manifest_path = base.verify_artifact_record(report["inputs"]["manifest"], "diagnostic manifest")
    model_report_path = base.verify_artifact_record(report["inputs"]["modelReport"], "diagnostic model report")
    manifest = base.verify_manifest(manifest_path)
    model_report, violations, _signatures = human_renderer.load_recovery_model(base, model_report_path)
    expected_rows = sum(not item.get("blocked") for item in manifest.get("reviewItems", [])) * 2
    summary = report["summary"]
    over_limit = [row for row in report["rows"] if not row["primaryPassed"]]
    actual_occupancy = {
        (str(row["role"]), str(row["reviewKey"]))
        for row in report["rows"]
        if row["occupancyGateBypassedForHumanReview"]
    }
    gates = report.get("gates", {})
    if (
        report.get("sourceDigest") != manifest.get("sourceDigest")
        or report.get("manifestDigest") != manifest.get("manifestDigest")
        or report.get("modelReportDigest") != model_report.get("reportDigest")
        or len(report["rows"]) != expected_rows
        or summary.get("rows") != expected_rows
        or summary.get("overLimitRows") != len(over_limit)
        or summary.get("occupancyBypassRows") != len(violations)
        or actual_occupancy != violations
        or not all(gates.get(field) is True for field in (
            "allRowsMeasured",
            "diagnosticAdmissionIsNotAcceptance",
            "globalThresholdUnchanged",
            "occupancyRecoveryBoundToModelDiagnostics",
            "boundedPillowDecode",
        ))
        or gates.get("humanArtAcceptance") is not False
        or gates.get("productionWrites") is not False
    ):
        raise base.PilotError("fidelity diagnostic 闭包非法")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    run_parser = commands.add_parser("run")
    run_parser.add_argument("--manifest", required=True)
    run_parser.add_argument("--model-report", required=True)
    run_parser.add_argument("--output", required=True)
    run_parser.add_argument("--batch-id", required=True)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--report", required=True)
    args = parser.parse_args()
    report = run(args) if args.command == "run" else check(args)
    over_limit = [row for row in report["rows"] if not row["primaryPassed"]]
    print(json.dumps({
        "status": "feature_fidelity_human_review_diagnostic_verified" if args.command == "check" else report["status"],
        "diagnosticDigest": report["diagnosticDigest"],
        "summary": report["summary"],
        "overLimit": [{
            "role": row["role"],
            "reviewKey": row["reviewKey"],
            "candidateId": row["candidateId"],
            "frame": row["frame"],
            "meanAbsoluteError": row["meanAbsoluteError"],
            "alphaEvidencePassed": row["alphaRepresentationEvidence"]["passed"],
        } for row in over_limit],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
