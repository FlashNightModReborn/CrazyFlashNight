#!/usr/bin/env python3
"""Render one shard with a diagnostic-bound two-role binary-GIF alpha exception."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import math
import sys
from pathlib import Path
from typing import Any

from PIL import Image

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
BASE_RENDERER = Path(__file__).with_name("prepare_pilot.py").resolve()
DIAGNOSTIC_CONTROLLER = Path(__file__).with_name("diagnose-feature-render-fidelity-v1.py").resolve()
ALPHA_POLICY_SOURCE = Path(__file__).with_name("render-feature-large-frame-fidelity-v1.py").resolve()
SAFETY_SCHEMA = "cf7.portrait-pilot-pillow-large-frame-safety.v1"
EXCEPTION_CODE = "binary_gif_alpha_cannot_represent_semtransparent_selected_frame"
EXCEPTION_BINDING = {
    "reviewKey": "敌人-变异犬::default",
    "candidateId": "e06-c05",
    "frame": 64,
}
EXCEPTION_ROLES = {"proposal", "independent_review"}


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise core.PilotError(f"无法加载模块：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


diagnostic_controller = load_module(DIAGNOSTIC_CONTROLLER, "portrait_fidelity_diagnostic_binding")
alpha_policy = diagnostic_controller.alpha_policy


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise core.PilotError(f"{label} 缺失：{path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise core.PilotError(f"{label} 顶层必须是对象")
    return value


def verify_digest(value: dict[str, Any], field: str, label: str) -> None:
    expected = value.get(field)
    envelope = dict(value)
    envelope.pop(field, None)
    if not isinstance(expected, str) or expected != core.sha256_bytes(core.stable_bytes(envelope)):
        raise core.PilotError(f"{label} {field} 不匹配")


def is_exact_exception(row: dict[str, Any]) -> bool:
    return (
        row.get("reviewKey") == EXCEPTION_BINDING["reviewKey"]
        and row.get("candidateId") == EXCEPTION_BINDING["candidateId"]
        and row.get("frame") == EXCEPTION_BINDING["frame"]
        and row.get("role") in EXCEPTION_ROLES
    )


def verify_diagnostic(
    report_path: Path,
    manifest: dict[str, Any],
    model_report: dict[str, Any],
) -> dict[str, Any]:
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        diagnostic_controller.check(argparse.Namespace(report=str(report_path)))
    report = load_json(report_path, "fidelity diagnostic")
    if (
        report.get("sourceDigest") != manifest.get("sourceDigest")
        or report.get("manifestDigest") != manifest.get("manifestDigest")
        or report.get("modelReportDigest") != model_report.get("reportDigest")
    ):
        raise core.PilotError("fidelity diagnostic 与 manifest/model report 不闭合")
    over_limit = [row for row in report.get("rows", []) if not row.get("primaryPassed")]
    if (
        len(over_limit) != 2
        or {row.get("role") for row in over_limit} != EXCEPTION_ROLES
        or any(not is_exact_exception(row) for row in over_limit)
        or any(row.get("alphaRepresentationEvidence", {}).get("passed") is not True for row in over_limit)
    ):
        raise core.PilotError("fidelity diagnostic 未精确证明变异犬双角色例外")
    return report


def safety_record(maximum_dimension: int, maximum_pixels: int) -> dict[str, Any]:
    return {
        "schema": SAFETY_SCHEMA,
        "maxImagePixels": maximum_pixels,
        "pillowHardErrorAbovePixels": maximum_pixels * 2,
        "manifestMaximumSourceFrameDimension": maximum_dimension,
        "boundedByManifest": True,
        "unlimitedRasterDecode": False,
    }


def render(args: argparse.Namespace) -> None:
    manifest_path, manifest, model_report = diagnostic_controller.load_inputs(args.manifest, args.model_report)
    diagnostic_path = Path(args.diagnostic_report).resolve()
    diagnostic_report = verify_diagnostic(diagnostic_path, manifest, model_report)
    maximum_dimension, maximum_pixels = diagnostic_controller.bounded_pixel_limit(manifest)
    limit = float(manifest["featureContract"]["highResolutionRender"]["fidelityMeanAbsoluteErrorLimit"])
    original_metric = core.image_mean_absolute_error
    admitted_calls: list[dict[str, Any]] = []

    def admission_metric(left: Image.Image, right: Image.Image) -> tuple[float, list[float]]:
        mean, channels = original_metric(left, right)
        if mean <= limit:
            return mean, channels
        evidence = alpha_policy.alpha_representation_evidence(left, right)
        if not evidence["passed"]:
            return mean, channels
        admitted_calls.append(
            {
                "primaryMeanAbsoluteError": float(mean),
                "primaryPerChannel": [float(value) for value in channels],
                "representationEvidence": evidence,
            }
        )
        return limit, [limit, limit, limit, limit]

    output_dir = manifest_path.parent
    report_path = output_dir / "render-report.json"
    if report_path.exists():
        raise core.PilotError("render-report.json 已存在，禁止覆盖")
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    original_module_file = core.__file__
    core.image_mean_absolute_error = admission_metric
    try:
        core.__file__ = str(Path(__file__).resolve())
        with contextlib.redirect_stdout(io.StringIO()):
            core.render_feature_refinement(manifest, model_report, output_dir, report_path)
    finally:
        core.__file__ = original_module_file
        core.image_mean_absolute_error = original_metric

    report = load_json(report_path, "render report")
    verify_digest(report, "renderDigest", "base render report")
    exception_rows: list[dict[str, Any]] = []
    actual_values: list[float] = []
    primary_pass_rows = 0
    for row in report.get("rows", []):
        mean, channels, evidence = alpha_policy.recompute_row_fidelity(
            manifest,
            row,
            original_metric,
            maximum_pixels,
        )
        actual_values.append(mean)
        if mean <= limit:
            primary_pass_rows += 1
            row["fidelityComparison"] = {
                "metric": "premultiplied RGBA mean absolute error",
                "meanAbsoluteError": mean,
                "perChannel": dict(zip(("red", "green", "blue", "alpha"), channels)),
                "limit": limit,
                "primaryPassed": True,
                "passedBy": "primary_mae",
                "passed": True,
            }
            continue
        if not is_exact_exception(row) or not evidence["passed"]:
            raise core.PilotError(
                f"未授权的 fidelity 超限：{row.get('role')}/{row.get('reviewKey')} mean={mean:.4f}"
            )
        row["fidelityComparison"] = {
            "metric": "premultiplied RGBA MAE with diagnostic-bound binary-GIF alpha representation exception",
            "meanAbsoluteError": mean,
            "perChannel": dict(zip(("red", "green", "blue", "alpha"), channels)),
            "limit": limit,
            "primaryPassed": False,
            "passedBy": EXCEPTION_CODE,
            "representationException": evidence,
            "passed": True,
        }
        exception_rows.append(
            {
                "role": row["role"],
                **EXCEPTION_BINDING,
                "primaryMeanAbsoluteError": mean,
                "representationEvidence": evidence,
            }
        )

    if (
        len(admitted_calls) != 2
        or len(exception_rows) != 2
        or {row["role"] for row in exception_rows} != EXCEPTION_ROLES
    ):
        raise core.PilotError(
            f"预期恰有变异犬双角色例外：admitted={len(admitted_calls)} report={len(exception_rows)}"
        )

    report["renderer"]["controllerSource"] = core.artifact(Path(__file__).resolve())
    report["renderer"]["baseRendererSource"] = core.artifact(BASE_RENDERER)
    report["renderer"]["alphaExceptionPolicySource"] = core.artifact(ALPHA_POLICY_SOURCE)
    report["renderer"]["diagnosticControllerSource"] = core.artifact(DIAGNOSTIC_CONTROLLER)
    report["renderer"]["fidelityDiagnostic"] = core.artifact(diagnostic_path)
    report["renderer"]["numpy"] = alpha_policy.np.__version__
    report["renderer"]["pillowSafety"] = safety_record(maximum_dimension, maximum_pixels)
    report["fidelitySummary"] = {
        "comparison": "primary premultiplied RGBA MAE; only the diagnostic-bound identity/candidate/frame in both Luna roles may use opaque-core correspondence for binary GIF semitransparency",
        "meanAbsoluteErrorLimit": limit,
        "maximumMeanAbsoluteError": max(actual_values),
        "averageMeanAbsoluteError": sum(actual_values) / len(actual_values),
        "totalRows": len(actual_values),
        "primaryPassedRows": primary_pass_rows,
        "representationExceptionRows": len(exception_rows),
        "passedRows": primary_pass_rows + len(exception_rows),
        "allRowsPassedPrimaryOrException": primary_pass_rows + len(exception_rows) == len(actual_values),
        "exceptionPolicy": {
            "code": EXCEPTION_CODE,
            "binding": EXCEPTION_BINDING,
            "roles": sorted(EXCEPTION_ROLES),
            "diagnosticDigest": diagnostic_report["diagnosticDigest"],
            "minimumSelectedFrameSemiTransparentFraction": alpha_policy.MINIMUM_SEMITRANSPARENT_FRACTION,
            "opaqueCoreAlphaThreshold": alpha_policy.ALPHA_THRESHOLD,
            "minimumOpaqueCoreIoU": alpha_policy.MINIMUM_OPAQUE_CORE_IOU,
            "maximumOpaqueCoreCentroidDistance": alpha_policy.MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE,
            "scope": "candidate correspondence only; no art acceptance and no global threshold relaxation",
        },
        "exceptionRows": exception_rows,
    }
    report["gates"]["premultipliedRgbaPrimaryChecked"] = True
    report["gates"]["binaryGifSemitransparencyExceptionChecked"] = True
    report["gates"]["exceptionIdentityCandidateFrameAndRolesBound"] = True
    report["gates"]["fidelityDiagnosticBound"] = True
    report["gates"]["boundedPillowLargeFrameChecked"] = True
    report["gates"]["allRowsPassedPrimaryOrException"] = True
    report.pop("renderDigest", None)
    report["renderDigest"] = core.sha256_bytes(core.stable_bytes(report))
    core.write_json(report_path, report)
    print(json.dumps(verify_report(manifest_path, Path(args.model_report).resolve(), diagnostic_path, report_path), ensure_ascii=False))


def verify_report(
    manifest_path: Path,
    model_report_path: Path,
    diagnostic_path: Path,
    report_path: Path,
) -> dict[str, Any]:
    _path, manifest, model_report = diagnostic_controller.load_inputs(str(manifest_path), str(model_report_path))
    diagnostic_report = verify_diagnostic(diagnostic_path, manifest, model_report)
    maximum_dimension, maximum_pixels = diagnostic_controller.bounded_pixel_limit(manifest)
    report = load_json(report_path, "render report")
    verify_digest(report, "renderDigest", "render report")
    if (
        report.get("schema") != "cf7.portrait-pilot-render-report.v4"
        or report.get("status") != "automated_checked"
        or report.get("productionReady") is not False
        or report.get("sourceDigest") != manifest.get("sourceDigest")
        or report.get("manifestDigest") != manifest.get("manifestDigest")
        or report.get("modelReportDigest") != model_report.get("reportDigest")
    ):
        raise core.PilotError("render report 跨层摘要或状态不闭合")
    renderer = report.get("renderer", {})
    expected_renderer_records = {
        "controllerSource": core.artifact(Path(__file__).resolve()),
        "baseRendererSource": core.artifact(BASE_RENDERER),
        "alphaExceptionPolicySource": core.artifact(ALPHA_POLICY_SOURCE),
        "diagnosticControllerSource": core.artifact(DIAGNOSTIC_CONTROLLER),
        "fidelityDiagnostic": core.artifact(diagnostic_path),
    }
    if any(renderer.get(key) != value for key, value in expected_renderer_records.items()):
        raise core.PilotError("render report controller/diagnostic 绑定不闭合")
    if renderer.get("pillowSafety") != safety_record(maximum_dimension, maximum_pixels):
        raise core.PilotError("Pillow 大帧安全合同不闭合")
    rows = report.get("rows", [])
    if len(rows) != 24 or {row.get("role") for row in rows} != EXCEPTION_ROLES:
        raise core.PilotError("render report 行数或角色不闭合")
    exceptions: list[dict[str, Any]] = []
    artifact_count = len(expected_renderer_records)
    for row in rows:
        for field in (
            "sourceCandidate",
            "sourceGeometrySvg",
            "sourceHighResolution",
            "sourceSupersample",
            "master",
            "webp80Lossless",
        ):
            core.verify_artifact_record(row[field], f"render artifact {field}")
            artifact_count += 1
        for record in row.get("previews", {}).values():
            core.verify_artifact_record(record, "render preview")
            artifact_count += 1
        fidelity = row.get("fidelityComparison", {})
        if fidelity.get("passed") is not True:
            raise core.PilotError(f"render fidelity 未通过：{row.get('role')}/{row.get('reviewKey')}")
        if fidelity.get("passedBy") == EXCEPTION_CODE:
            exceptions.append(row)
        elif fidelity.get("passedBy") != "primary_mae" or fidelity.get("meanAbsoluteError", math.inf) > fidelity.get("limit", -1):
            raise core.PilotError("primary fidelity 语义非法")
    if (
        len(exceptions) != 2
        or {row.get("role") for row in exceptions} != EXCEPTION_ROLES
        or any(not is_exact_exception(row) for row in exceptions)
        or any(row.get("fidelityComparison", {}).get("representationException", {}).get("passed") is not True for row in exceptions)
    ):
        raise core.PilotError("二值 GIF alpha 例外未精确绑定变异犬双角色")
    summary = report.get("fidelitySummary", {})
    if (
        summary.get("primaryPassedRows") != 22
        or summary.get("representationExceptionRows") != 2
        or summary.get("passedRows") != 24
        or summary.get("allRowsPassedPrimaryOrException") is not True
        or summary.get("exceptionPolicy", {}).get("diagnosticDigest") != diagnostic_report.get("diagnosticDigest")
        or report.get("gates", {}).get("productionWrites") is not False
    ):
        raise core.PilotError("render fidelity summary/gates 不闭合")
    return {
        "status": "automated_checked_with_diagnostic_bound_alpha_exception",
        "report": core.repo_rel(report_path),
        "renderDigest": report["renderDigest"],
        "rows": len(rows),
        "primaryPassedRows": summary["primaryPassedRows"],
        "representationExceptionRows": summary["representationExceptionRows"],
        "maximumMeanAbsoluteError": summary["maximumMeanAbsoluteError"],
        "artifactCount": artifact_count,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve()
    model_report_path = Path(args.model_report).resolve()
    diagnostic_path = Path(args.diagnostic_report).resolve()
    report_path = manifest_path.parent / "render-report.json"
    print(json.dumps(verify_report(manifest_path, model_report_path, diagnostic_path, report_path), ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    for command, handler in (("render", render), ("check", check)):
        command_parser = commands.add_parser(command)
        command_parser.add_argument("--manifest", required=True)
        command_parser.add_argument("--model-report", required=True)
        command_parser.add_argument("--diagnostic-report", required=True)
        command_parser.set_defaults(handler=handler)
    args = parser.parse_args()
    try:
        args.handler(args)
    except (core.PilotError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"portrait feature large-frame fidelity v2 error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
