#!/usr/bin/env python3
"""Build a fresh review batch with occupancy and exact near-threshold fidelity evidence."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
HUMAN_REVIEW_RENDERER = Path(__file__).with_name("render-feature-orientation-human-review-v1.py").resolve()
DIAGNOSTIC_CONTROLLER = Path(__file__).with_name(
    "diagnose-feature-render-fidelity-human-review-v1.py"
).resolve()
EVIDENCE_CONTROLLER = Path(__file__).with_name(
    "derive-near-threshold-rasterization-evidence-v1.py"
).resolve()
EXPECTED_HUMAN_REVIEW_RENDERER_SHA256 = "C8D5655DC78AB638A56DEA98DE30C38FB7E25FB072D7A606B3DFF398568169A9"
EXPECTED_DIAGNOSTIC_CONTROLLER_SHA256 = "E26198E6DA4A0F839888E3ADE0E0E444BEF6C7B8C4E1640F17845F9F42D579FF"
EXPECTED_EVIDENCE_CONTROLLER_SHA256 = "7E8C70F15B6DAF0CEF3A370E823607AFDA4894902D033F6D75CB00CD31827375"
PROVENANCE_SCHEMA = "cf7.portrait-pilot-render-retry-input.v1"
PROVENANCE_NAME = "render-retry-input.json"


def file_sha256(path: Path) -> str:
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
        raise RuntimeError("人审占比 renderer 字节已漂移")
    if file_sha256(DIAGNOSTIC_CONTROLLER) != EXPECTED_DIAGNOSTIC_CONTROLLER_SHA256:
        raise RuntimeError("人审 fidelity diagnostic controller 字节已漂移")
    if file_sha256(EVIDENCE_CONTROLLER) != EXPECTED_EVIDENCE_CONTROLLER_SHA256:
        raise RuntimeError("近阈值证据 controller 字节已漂移")
    human_renderer = load_module(HUMAN_REVIEW_RENDERER, "portrait_final_human_review_renderer")
    diagnostic_controller = load_module(DIAGNOSTIC_CONTROLLER, "portrait_final_fidelity_diagnostic")
    evidence_controller = load_module(EVIDENCE_CONTROLLER, "portrait_final_fidelity_evidence")
    orientation, base = human_renderer.load_controllers()
    _human_again, alpha_policy, _base_again = diagnostic_controller.load_dependencies()
    return human_renderer, diagnostic_controller, evidence_controller, orientation, alpha_policy, base


def ensure_output(value: str, must_exist: bool) -> Path:
    output = Path(value).resolve()
    try:
        relative = output.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise RuntimeError("最终渲染输出必须位于 tmp/portrait-pilot 下") from error
    if not relative.parts:
        raise RuntimeError("最终渲染输出不能是 portrait-pilot 根目录")
    if must_exist and not output.is_dir():
        raise RuntimeError("最终渲染输出缺失")
    if not must_exist and output.exists():
        raise RuntimeError("最终渲染输出已存在，禁止覆盖")
    return output


def verify_source_file(path: Path, label: str) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(ROOT.resolve())
    except ValueError as error:
        raise RuntimeError(f"{label} 必须位于仓库内") from error
    if not resolved.is_file():
        raise RuntimeError(f"{label} 缺失：{resolved}")
    return resolved


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest().upper()


def load_bound_reports(
    base,
    diagnostic_controller,
    evidence_controller,
    diagnostic_path: Path,
    evidence_path: Path,
):
    diagnostic_report = diagnostic_controller.check(argparse.Namespace(report=str(diagnostic_path)))
    evidence_report = evidence_controller.check(argparse.Namespace(output=str(evidence_path)))
    if (
        evidence_report.get("diagnosticDigest") != diagnostic_report.get("diagnosticDigest")
        or evidence_report.get("sourceDigest") != diagnostic_report.get("sourceDigest")
        or evidence_report.get("manifestDigest") != diagnostic_report.get("manifestDigest")
        or evidence_report.get("modelReportDigest") != diagnostic_report.get("modelReportDigest")
        or evidence_report.get("gates", {}).get("diagnosticAdmissionIsNotArtAcceptance") is not True
        or evidence_report.get("gates", {}).get("humanArtAcceptance") is not False
        or evidence_report.get("gates", {}).get("productionWrites") is not False
    ):
        raise base.PilotError("近阈值证据与 fidelity diagnostic 不闭合")
    return diagnostic_report, evidence_report


def build_provenance(
    base,
    source_manifest: Path,
    source_model: Path,
    copied_manifest: Path,
    copied_model: Path,
    diagnostic_path: Path,
    evidence_path: Path,
    diagnostic_report: dict[str, Any],
    evidence_report: dict[str, Any],
) -> dict[str, Any]:
    report = {
        "schema": PROVENANCE_SCHEMA,
        "status": "render_retry_inputs_frozen",
        "productionReady": False,
        "humanReviewRequired": True,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "controller": base.artifact(Path(__file__).resolve()),
        "source": {
            "manifest": base.artifact(source_manifest),
            "modelReport": base.artifact(source_model),
            "fidelityDiagnostic": base.artifact(diagnostic_path),
            "nearThresholdEvidence": base.artifact(evidence_path),
        },
        "output": {
            "manifest": base.artifact(copied_manifest),
            "modelReport": base.artifact(copied_model),
        },
        "binding": {
            "diagnosticDigest": diagnostic_report["diagnosticDigest"],
            "evidenceDigest": evidence_report["evidenceDigest"],
            "sourceDigest": diagnostic_report["sourceDigest"],
            "manifestDigest": diagnostic_report["manifestDigest"],
            "modelReportDigest": diagnostic_report["modelReportDigest"],
        },
        "gates": {
            "manifestBytesCopiedWithoutChange": source_manifest.read_bytes() == copied_manifest.read_bytes(),
            "modelReportBytesCopiedWithoutChange": source_model.read_bytes() == copied_model.read_bytes(),
            "failedRenderPreservedInSourceBatch": True,
            "freshOutputDirectory": True,
            "humanArtAcceptance": False,
            "productionWrites": False,
        },
    }
    report["provenanceDigest"] = base.sha256_bytes(base.stable_bytes(report))
    return report


def allowed_fidelity_rows(evidence_report: dict[str, Any]) -> tuple[dict[tuple[str, str], dict[str, Any]], set[tuple[str, str]]]:
    rows = {
        (str(row["role"]), str(row["reviewKey"])): row
        for row in evidence_report.get("rows", [])
    }
    if len(rows) != 2 or {role for role, _key in rows} != {"proposal", "independent_review"}:
        raise RuntimeError("近阈值证据不是精确双角色集合")
    return rows, set(rows)


def admission_metric(base, evidence_controller, evidence_report: dict[str, Any]):
    original_metric = base.image_mean_absolute_error
    limit = float(next(iter(evidence_report["rows"]))["globalLimit"])
    allowed_pairs = {
        (
            row["correspondence"]["selectedFrameRgbaSha256"],
            row["correspondence"]["candidateRgbaSha256"],
        )
        for row in evidence_report["rows"]
    }
    admitted_calls: list[dict[str, Any]] = []

    def metric(left: Image.Image, right: Image.Image) -> tuple[float, list[float]]:
        mean, channels = original_metric(left, right)
        if mean <= limit:
            return mean, channels
        pair = (rgba_sha256(left), rgba_sha256(right))
        correspondence = evidence_controller.correspondence_evidence(left, right)
        if (
            pair not in allowed_pairs
            or mean > float(evidence_report["exceptionPolicy"]["maximumMeanAbsoluteError"])
            or mean - limit > float(evidence_report["exceptionPolicy"]["maximumExcessOverGlobalLimit"])
            or correspondence.get("passed") is not True
        ):
            return mean, channels
        admitted_calls.append({
            "primaryMeanAbsoluteError": float(mean),
            "primaryPerChannel": [float(value) for value in channels],
            "selectedFrameRgbaSha256": pair[0],
            "candidateRgbaSha256": pair[1],
            "correspondence": correspondence,
        })
        return limit, [limit, limit, limit, limit]

    return original_metric, metric, admitted_calls


def recompute_row(base, alpha_policy, evidence_controller, manifest, row, original_metric, maximum_pixels):
    candidate = alpha_policy.candidate_record(manifest, row["reviewKey"], row["candidateId"])
    high_resolution_path = base.verify_artifact_record(
        row["sourceHighResolution"], f"最终 fidelity selected frame {row['role']}/{row['reviewKey']}"
    )
    candidate_path = base.verify_artifact_record(
        row["sourceCandidate"], f"最终 fidelity candidate {row['role']}/{row['reviewKey']}"
    )
    original_max = Image.MAX_IMAGE_PIXELS
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    try:
        with Image.open(high_resolution_path) as image:
            selected_frame = image.convert("RGBA")
        restored, _scale = base.candidate_from_high_resolution(selected_frame, candidate)
        with Image.open(candidate_path) as image:
            bound_candidate = image.convert("RGBA")
    finally:
        Image.MAX_IMAGE_PIXELS = original_max
    mean, channels = original_metric(restored, bound_candidate)
    correspondence = evidence_controller.correspondence_evidence(restored, bound_candidate)
    return float(mean), [float(value) for value in channels], correspondence


def decorate_report(
    base,
    human_renderer,
    alpha_policy,
    evidence_controller,
    report: dict[str, Any],
    manifest: dict[str, Any],
    model_report: dict[str, Any],
    occupancy_violations: set[tuple[str, str]],
    diagnostic_path: Path,
    evidence_path: Path,
    evidence_report: dict[str, Any],
    provenance_path: Path,
    admitted_calls: list[dict[str, Any]],
    original_metric,
) -> dict[str, Any]:
    allowed_rows, allowed_keys = allowed_fidelity_rows(evidence_report)
    maximum_dimension = int(manifest["featureContract"]["highResolutionRender"]["maximumSourceFrameDimension"])
    maximum_pixels = maximum_dimension * maximum_dimension
    limit = float(manifest["featureContract"]["highResolutionRender"]["fidelityMeanAbsoluteErrorLimit"])
    actual_occupancy: set[tuple[str, str]] = set()
    exception_rows: list[dict[str, Any]] = []
    fidelity_values: list[float] = []
    primary_rows = 0
    for row in report.get("rows", []):
        key = (str(row["role"]), str(row["reviewKey"]))
        geometry = row.get("geometry", {})
        bypassed = geometry.get("occupancyGateBypassedForHumanReview") is True
        if bypassed:
            actual_occupancy.add(key)
        selection = {
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
        }
        if (
            bypassed == (geometry.get("strictFeatureOccupancyAccepted") is True)
            or geometry.get("occupancyRecoveryModelReportDigest") != model_report["reportDigest"]
            or geometry.get("occupancyRecoverySelectionSha256") != human_renderer.selection_digest(selection)
        ):
            raise base.PilotError(f"最终渲染占比恢复证据漂移：{key}")
        mean, channels, correspondence = recompute_row(
            base, alpha_policy, evidence_controller, manifest, row, original_metric, maximum_pixels
        )
        fidelity_values.append(mean)
        if mean <= limit:
            primary_rows += 1
            row["fidelityComparison"] = {
                "metric": "premultiplied RGBA mean absolute error",
                "meanAbsoluteError": mean,
                "perChannel": dict(zip(("red", "green", "blue", "alpha"), channels)),
                "limit": limit,
                "primaryPassed": True,
                "passedBy": "primary_mae",
                "passed": True,
            }
            if key in allowed_keys:
                raise base.PilotError(f"证据绑定行已不再超限，拒绝陈旧例外：{key}")
            continue
        evidence_row = allowed_rows.get(key)
        if (
            evidence_row is None
            or row["candidateId"] != evidence_row["candidateId"]
            or row["frame"] != evidence_row["frame"]
            or abs(mean - float(evidence_row["primaryMeanAbsoluteError"])) > 1e-12
            or base.stable_bytes(correspondence) != base.stable_bytes(evidence_row["correspondence"])
        ):
            raise base.PilotError(f"未授权或漂移的 fidelity 超限：{key} mean={mean:.6f}")
        row["fidelityComparison"] = {
            "metric": "premultiplied RGBA MAE with exact near-threshold vector/raster shape correspondence",
            "meanAbsoluteError": mean,
            "perChannel": dict(zip(("red", "green", "blue", "alpha"), channels)),
            "limit": limit,
            "primaryPassed": False,
            "passedBy": evidence_report["exceptionPolicy"]["code"],
            "correspondenceEvidence": correspondence,
            "evidenceDigest": evidence_report["evidenceDigest"],
            "passed": True,
        }
        exception_rows.append({
            "role": row["role"],
            "reviewKey": row["reviewKey"],
            "candidateId": row["candidateId"],
            "frame": row["frame"],
            "primaryMeanAbsoluteError": mean,
            "correspondenceEvidence": correspondence,
        })
    if actual_occupancy != occupancy_violations:
        raise base.PilotError("最终渲染占比违规集合不一致")
    if { (row["role"], row["reviewKey"]) for row in exception_rows } != allowed_keys:
        raise base.PilotError("最终渲染 fidelity 例外集合不一致")
    if len(admitted_calls) != len(allowed_keys):
        raise base.PilotError("底层 fidelity admission 次数不闭合")

    report["renderer"]["humanReviewOccupancyRecoveryControllerSource"] = base.artifact(HUMAN_REVIEW_RENDERER)
    report["renderer"]["humanReviewFidelityControllerSource"] = base.artifact(Path(__file__).resolve())
    report["renderer"]["fidelityDiagnostic"] = base.artifact(diagnostic_path)
    report["renderer"]["nearThresholdRasterizationEvidence"] = base.artifact(evidence_path)
    report["renderer"]["renderRetryInput"] = base.artifact(provenance_path)
    report["renderer"]["pillowSafety"] = human_renderer.safety_record(maximum_dimension, maximum_pixels)
    report["renderer"]["occupancyRecoveryPolicy"] = {
        "version": "diagnostic_bound_human_review_occupancy_v1",
        "selectionGeometryChanged": False,
        "manifestGeometryContractChanged": False,
        "safeMarginAndContainmentPreserved": True,
        "scope": "human review only; no art acceptance and no production write",
    }
    report["occupancyRecoverySummary"] = {
        "rows": len(report["rows"]),
        "strictlyAcceptedRows": len(report["rows"]) - len(actual_occupancy),
        "bypassedForHumanReviewRows": len(actual_occupancy),
        "reviewKeys": sorted({review_key for _role, review_key in actual_occupancy}),
        "roleReviewKeys": [
            {"role": role, "reviewKey": review_key}
            for role, review_key in sorted(actual_occupancy)
        ],
        "modelReportDigest": model_report["reportDigest"],
    }
    report["fidelitySummary"] = {
        "comparison": "primary premultiplied RGBA MAE; only the evidence-bound identity/candidate/frame in both roles may use near-threshold vector/raster shape correspondence",
        "meanAbsoluteErrorLimit": limit,
        "maximumMeanAbsoluteError": max(fidelity_values),
        "averageMeanAbsoluteError": sum(fidelity_values) / len(fidelity_values),
        "totalRows": len(fidelity_values),
        "primaryPassedRows": primary_rows,
        "nearThresholdCorrespondenceRows": len(exception_rows),
        "passedRows": primary_rows + len(exception_rows),
        "allRowsPassedPrimaryOrEvidence": primary_rows + len(exception_rows) == len(fidelity_values),
        "exceptionPolicy": evidence_report["exceptionPolicy"],
        "diagnosticDigest": evidence_report["diagnosticDigest"],
        "evidenceDigest": evidence_report["evidenceDigest"],
        "exceptionRows": exception_rows,
    }
    report["status"] = "automated_checked_human_review_geometry_and_fidelity"
    report["gates"].update({
        "strictFeatureOccupancyAccepted": False,
        "occupancyRecoveryBoundToModelDiagnostics": True,
        "occupancyRecoverySelectionGeometryUnchanged": True,
        "occupancyRecoveryManifestContractUnchanged": True,
        "boundedPillowLargeFrameChecked": True,
        "premultipliedRgbaPrimaryChecked": True,
        "nearThresholdCorrespondenceEvidenceChecked": True,
        "exceptionIdentityCandidateFrameAndRolesBound": True,
        "fidelityDiagnosticBound": True,
        "allRowsPassedPrimaryOrEvidence": True,
        "humanReviewRequired": True,
        "humanArtAcceptance": False,
        "productionWrites": False,
    })
    report.pop("renderDigest", None)
    report["renderDigest"] = base.sha256_bytes(base.stable_bytes(report))
    return report


def render(args: argparse.Namespace) -> dict[str, Any]:
    human_renderer, diagnostic_controller, evidence_controller, orientation, alpha_policy, base = load_dependencies()
    source_manifest = verify_source_file(Path(args.manifest), "source manifest")
    source_model = verify_source_file(Path(args.model_report), "source model report")
    diagnostic_path = verify_source_file(Path(args.diagnostic_report), "fidelity diagnostic")
    evidence_path = verify_source_file(Path(args.rasterization_evidence), "near-threshold evidence")
    output = ensure_output(args.output, False)
    diagnostic_report, evidence_report = load_bound_reports(
        base, diagnostic_controller, evidence_controller, diagnostic_path, evidence_path
    )
    source_manifest_data = base.verify_manifest(source_manifest)
    source_model_data, source_violations, _source_signatures = human_renderer.load_recovery_model(base, source_model)
    if (
        source_model_data["sourceDigest"] != source_manifest_data["sourceDigest"]
        or source_model_data["manifestDigest"] != source_manifest_data["manifestDigest"]
        or evidence_report["sourceDigest"] != source_manifest_data["sourceDigest"]
        or evidence_report["modelReportDigest"] != source_model_data["reportDigest"]
    ):
        raise base.PilotError("最终渲染 source manifest/model/diagnostic/evidence 不闭合")

    output.mkdir(parents=True)
    copied_manifest = output / "candidate-manifest.json"
    copied_model = output / "model-report.json"
    shutil.copyfile(source_manifest, copied_manifest)
    shutil.copyfile(source_model, copied_model)
    provenance = build_provenance(
        base,
        source_manifest,
        source_model,
        copied_manifest,
        copied_model,
        diagnostic_path,
        evidence_path,
        diagnostic_report,
        evidence_report,
    )
    provenance_path = output / PROVENANCE_NAME
    base.write_json(provenance_path, provenance)
    manifest = base.verify_manifest(copied_manifest)
    model_report, occupancy_violations, occupancy_signatures = human_renderer.load_recovery_model(base, copied_model)
    if occupancy_violations != source_violations:
        raise base.PilotError("复制后的模型占比违规集合漂移")

    maximum_dimension = int(manifest["featureContract"]["highResolutionRender"]["maximumSourceFrameDimension"])
    maximum_pixels = maximum_dimension * maximum_dimension
    original_max_pixels = Image.MAX_IMAGE_PIXELS
    original_compute, recovery_compute = human_renderer.occupancy_recovery_renderer(
        base, model_report, occupancy_signatures
    )
    original_metric, metric, admitted_calls = admission_metric(base, evidence_controller, evidence_report)
    base.compute_feature_view_box = recovery_compute
    base.image_mean_absolute_error = metric
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    render_args = argparse.Namespace(manifest=str(copied_manifest), model_report=str(copied_model))
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            report = orientation.render_with_orientation(base, render_args)
    finally:
        base.compute_feature_view_box = original_compute
        base.image_mean_absolute_error = original_metric
        Image.MAX_IMAGE_PIXELS = original_max_pixels
    report = decorate_report(
        base,
        human_renderer,
        alpha_policy,
        evidence_controller,
        report,
        manifest,
        model_report,
        occupancy_violations,
        diagnostic_path,
        evidence_path,
        evidence_report,
        provenance_path,
        admitted_calls,
        original_metric,
    )
    base.write_json(output / "render-report.json", report)
    return verify(argparse.Namespace(output=str(output)))


def verify_provenance(base, output: Path) -> dict[str, Any]:
    path = output / PROVENANCE_NAME
    report = base.load_json(path)
    base.verify_digest_object(report, "provenanceDigest", "render retry input")
    if (
        report.get("schema") != PROVENANCE_SCHEMA
        or report.get("status") != "render_retry_inputs_frozen"
        or report.get("productionReady") is not False
        or report.get("humanReviewRequired") is not True
    ):
        raise base.PilotError("render retry input schema/status 非法")
    for record in [report["controller"], *report["source"].values(), *report["output"].values()]:
        base.verify_artifact_record(record, "render retry input artifact")
    gates = report.get("gates", {})
    if (
        not all(gates.get(field) is True for field in (
            "manifestBytesCopiedWithoutChange",
            "modelReportBytesCopiedWithoutChange",
            "failedRenderPreservedInSourceBatch",
            "freshOutputDirectory",
        ))
        or gates.get("humanArtAcceptance") is not False
        or gates.get("productionWrites") is not False
    ):
        raise base.PilotError("render retry input gates 不闭合")
    if (
        base.verify_artifact_record(report["output"]["manifest"], "retry copied manifest") != output / "candidate-manifest.json"
        or base.verify_artifact_record(report["output"]["modelReport"], "retry copied model") != output / "model-report.json"
    ):
        raise base.PilotError("render retry input 输出路径漂移")
    return report


def verify(args: argparse.Namespace) -> dict[str, Any]:
    human_renderer, diagnostic_controller, evidence_controller, orientation, alpha_policy, base = load_dependencies()
    output = ensure_output(args.output, True)
    provenance = verify_provenance(base, output)
    manifest_path = output / "candidate-manifest.json"
    model_report_path = output / "model-report.json"
    manifest = base.verify_manifest(manifest_path)
    model_report, occupancy_violations, _signatures = human_renderer.load_recovery_model(base, model_report_path)
    diagnostic_path = base.verify_artifact_record(
        provenance["source"]["fidelityDiagnostic"], "retry fidelity diagnostic"
    )
    evidence_path = base.verify_artifact_record(
        provenance["source"]["nearThresholdEvidence"], "retry near-threshold evidence"
    )
    diagnostic_report, evidence_report = load_bound_reports(
        base, diagnostic_controller, evidence_controller, diagnostic_path, evidence_path
    )
    render_args = argparse.Namespace(manifest=str(manifest_path), model_report=str(model_report_path))
    report = orientation.verify_render(base, render_args)
    renderer = report.get("renderer", {})
    for field, expected, label in (
        ("humanReviewOccupancyRecoveryControllerSource", HUMAN_REVIEW_RENDERER, "占比恢复 renderer"),
        ("humanReviewFidelityControllerSource", Path(__file__).resolve(), "最终 fidelity renderer"),
        ("fidelityDiagnostic", diagnostic_path, "fidelity diagnostic"),
        ("nearThresholdRasterizationEvidence", evidence_path, "near-threshold evidence"),
        ("renderRetryInput", output / PROVENANCE_NAME, "render retry input"),
    ):
        if base.verify_artifact_record(renderer.get(field), label) != expected:
            raise base.PilotError(f"{label} artifact 路径漂移")
    actual_occupancy = {
        (str(row["role"]), str(row["reviewKey"]))
        for row in report["rows"]
        if row.get("geometry", {}).get("occupancyGateBypassedForHumanReview") is True
    }
    allowed_rows, allowed_keys = allowed_fidelity_rows(evidence_report)
    exception_rows = {
        (str(row["role"]), str(row["reviewKey"])): row
        for row in report["rows"]
        if row.get("fidelityComparison", {}).get("primaryPassed") is False
    }
    if actual_occupancy != occupancy_violations or set(exception_rows) != allowed_keys:
        raise base.PilotError("最终 render report 占比或 fidelity 例外集合漂移")
    maximum_dimension = int(manifest["featureContract"]["highResolutionRender"]["maximumSourceFrameDimension"])
    maximum_pixels = maximum_dimension * maximum_dimension
    original_metric = base.image_mean_absolute_error
    for key, row in exception_rows.items():
        mean, channels, correspondence = recompute_row(
            base, alpha_policy, evidence_controller, manifest, row, original_metric, maximum_pixels
        )
        bound = allowed_rows[key]
        fidelity = row["fidelityComparison"]
        if (
            abs(mean - float(bound["primaryMeanAbsoluteError"])) > 1e-12
            or base.stable_bytes(channels) != base.stable_bytes([
                fidelity["perChannel"][channel] for channel in ("red", "green", "blue", "alpha")
            ])
            or base.stable_bytes(correspondence) != base.stable_bytes(bound["correspondence"])
            or fidelity.get("passedBy") != evidence_report["exceptionPolicy"]["code"]
            or fidelity.get("evidenceDigest") != evidence_report["evidenceDigest"]
            or fidelity.get("passed") is not True
        ):
            raise base.PilotError(f"最终 fidelity 例外行不可重放：{key}")
    summary = report.get("fidelitySummary", {})
    occupancy_summary = report.get("occupancyRecoverySummary", {})
    gates = report.get("gates", {})
    if (
        report.get("status") != "automated_checked_human_review_geometry_and_fidelity"
        or report.get("sourceDigest") != manifest.get("sourceDigest")
        or report.get("manifestDigest") != manifest.get("manifestDigest")
        or report.get("modelReportDigest") != model_report.get("reportDigest")
        or summary.get("nearThresholdCorrespondenceRows") != len(allowed_keys)
        or summary.get("passedRows") != len(report["rows"])
        or summary.get("diagnosticDigest") != diagnostic_report.get("diagnosticDigest")
        or summary.get("evidenceDigest") != evidence_report.get("evidenceDigest")
        or occupancy_summary.get("bypassedForHumanReviewRows") != len(occupancy_violations)
        or renderer.get("pillowSafety") != human_renderer.safety_record(maximum_dimension, maximum_pixels)
        or not all(gates.get(field) is True for field in (
            "occupancyRecoveryBoundToModelDiagnostics",
            "occupancyRecoverySelectionGeometryUnchanged",
            "occupancyRecoveryManifestContractUnchanged",
            "boundedPillowLargeFrameChecked",
            "premultipliedRgbaPrimaryChecked",
            "nearThresholdCorrespondenceEvidenceChecked",
            "exceptionIdentityCandidateFrameAndRolesBound",
            "fidelityDiagnosticBound",
            "allRowsPassedPrimaryOrEvidence",
            "humanReviewRequired",
        ))
        or gates.get("strictFeatureOccupancyAccepted") is not False
        or gates.get("humanArtAcceptance") is not False
        or gates.get("productionWrites") is not False
    ):
        raise base.PilotError("最终 render report 状态、摘要或 gates 不闭合")
    return report


def self_test() -> None:
    human_renderer, _diagnostic, evidence_controller, orientation, _alpha, _base = load_dependencies()
    orientation.self_test()
    image = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    image.paste((255, 0, 0, 255), (1, 1, 7, 7))
    evidence = evidence_controller.correspondence_evidence(image, image)
    if evidence.get("passed") is not True or human_renderer.selection_digest({"x": 1}) == "":
        raise RuntimeError("最终人审 fidelity renderer 自检失败")
    print(json.dumps({
        "status": "human_review_fidelity_renderer_self_tested",
        "exactCorrespondencePassed": True,
        "humanArtAcceptance": False,
        "productionWrites": False,
    }, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    render_parser = commands.add_parser("render")
    render_parser.add_argument("--manifest", required=True)
    render_parser.add_argument("--model-report", required=True)
    render_parser.add_argument("--diagnostic-report", required=True)
    render_parser.add_argument("--rasterization-evidence", required=True)
    render_parser.add_argument("--output", required=True)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--output", required=True)
    commands.add_parser("self-test")
    args = parser.parse_args()
    if args.command == "self-test":
        self_test()
        return
    report = render(args) if args.command == "render" else verify(args)
    print(json.dumps({
        "status": "human_review_geometry_fidelity_render_verified" if args.command == "check" else report["status"],
        "renderDigest": report["renderDigest"],
        "rows": len(report["rows"]),
        "flipX": report["orientationSummary"]["flipX"],
        "occupancyBypassRows": report["occupancyRecoverySummary"]["bypassedForHumanReviewRows"],
        "nearThresholdCorrespondenceRows": report["fidelitySummary"]["nearThresholdCorrespondenceRows"],
        "maximumMeanAbsoluteError": report["fidelitySummary"]["maximumMeanAbsoluteError"],
        "humanArtAcceptance": report["gates"]["humanArtAcceptance"],
        "productionWrites": report["gates"]["productionWrites"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
