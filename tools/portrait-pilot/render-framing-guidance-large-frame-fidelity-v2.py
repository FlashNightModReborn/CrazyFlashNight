#!/usr/bin/env python3
"""Render r42 human framing with a diagnostic-bound GIF alpha exception."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import sys
from pathlib import Path
from typing import Any

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
LEGACY_WRAPPER = Path(__file__).with_name("render-framing-guidance-large-frame-fidelity-v1.py").resolve()
DIAGNOSTIC_CONTROLLER = Path(__file__).with_name("diagnose-feature-render-fidelity-v1.py").resolve()
EXCEPTION_BINDING = {
    "sourceRole": "independent_review",
    "reviewKey": "敌人-变异犬::default",
    "candidateId": "e06-c05",
    "frame": 64,
}


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise core.PilotError(f"无法加载模块：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


legacy = load_module(LEGACY_WRAPPER, "portrait_framing_large_frame_fidelity_v1")
diagnostic_controller = load_module(DIAGNOSTIC_CONTROLLER, "portrait_feature_fidelity_diagnostic_v1")


def verify_diagnostic(path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        diagnostic_controller.check(argparse.Namespace(report=str(path)))
    report = legacy.base.load_json(path, "fidelity diagnostic")
    match = next(
        (
            row
            for row in report.get("rows", [])
            if row.get("reviewKey") == EXCEPTION_BINDING["reviewKey"]
            and row.get("role") == EXCEPTION_BINDING["sourceRole"]
            and row.get("candidateId") == EXCEPTION_BINDING["candidateId"]
            and row.get("frame") == EXCEPTION_BINDING["frame"]
        ),
        None,
    )
    if (
        match is None
        or match.get("primaryPassed") is not False
        or match.get("meanAbsoluteError", 0) <= match.get("limit", 0)
        or match.get("alphaRepresentationEvidence", {}).get("passed") is not True
    ):
        raise core.PilotError("诊断没有精确授权变异犬人工所选角色/候选/帧")
    return report, match


def verify_parent_manifest(dataset: dict[str, Any], diagnostic: dict[str, Any]) -> None:
    manifest_record = dataset.get("parent", {}).get("files", {}).get("candidateManifest")
    manifest_path = core.verify_artifact_record(manifest_record, "人工框选父 candidate manifest")
    manifest = core.load_json(manifest_path)
    if diagnostic.get("manifestDigest") != manifest.get("manifestDigest"):
        raise core.PilotError("fidelity diagnostic 与人工框选父 manifest 不一致")


def patch_legacy_for_current_controller() -> tuple[str, dict[str, Any], Any]:
    original_file = legacy.__file__
    original_binding = legacy.EXCEPTION_BINDING
    original_verifier = legacy.verify_report
    legacy.__file__ = str(Path(__file__).resolve())
    legacy.EXCEPTION_BINDING = dict(EXCEPTION_BINDING)
    return original_file, original_binding, original_verifier


def restore_legacy(state: tuple[str, dict[str, Any], Any]) -> None:
    legacy.__file__, legacy.EXCEPTION_BINDING, legacy.verify_report = state


def render(args: argparse.Namespace) -> None:
    diagnostic_path = Path(args.diagnostic_report).resolve()
    diagnostic, diagnostic_row = verify_diagnostic(diagnostic_path)
    dataset = legacy.dataset_for_render(args.guidance_batch)
    verify_parent_manifest(dataset, diagnostic)

    selected = next(
        (item for item in dataset.get("items", []) if item.get("reviewKey") == EXCEPTION_BINDING["reviewKey"]),
        None,
    )
    if selected is None:
        raise core.PilotError("当前 guidance 不含变异犬人工框选")

    state = patch_legacy_for_current_controller()
    legacy.verify_report = lambda _path: {"status": "pending_diagnostic_binding", "artifactCount": 0}
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            legacy.render(args)
    finally:
        restore_legacy(state)

    report_path = Path(args.output).resolve() / "human-framing-render-report.json"
    report = legacy.base.load_json(report_path, "人工框选渲染报告")
    report["renderer"]["controllerSource"] = core.artifact(Path(__file__).resolve())
    report["renderer"]["legacyWrapperSource"] = core.artifact(LEGACY_WRAPPER)
    report["renderer"]["diagnosticControllerSource"] = core.artifact(DIAGNOSTIC_CONTROLLER)
    report["renderer"]["fidelityDiagnostic"] = core.artifact(diagnostic_path)
    report["fidelitySummary"]["exceptionPolicy"]["diagnosticDigest"] = diagnostic["diagnosticDigest"]
    report["fidelitySummary"]["exceptionPolicy"]["diagnosticBindingRequired"] = True
    report["fidelitySummary"]["exceptionRows"][0]["diagnosticEvidence"] = {
        "diagnosticDigest": diagnostic["diagnosticDigest"],
        "meanAbsoluteError": diagnostic_row["meanAbsoluteError"],
        "alphaRepresentationEvidence": diagnostic_row["alphaRepresentationEvidence"],
        "sourceCandidateSha256": diagnostic_row["sourceCandidate"]["sha256"],
        "sourceHighResolutionSha256": diagnostic_row["sourceHighResolution"]["sha256"],
    }
    report["gates"]["fidelityDiagnosticBound"] = True
    report.pop("reportDigest", None)
    report["reportDigest"] = core.sha256_bytes(core.stable_bytes(report))
    core.write_json(report_path, report)
    print(json.dumps(verify_report(report_path, diagnostic_path), ensure_ascii=False))


def verify_report(report_path: Path, diagnostic_path: Path) -> dict[str, Any]:
    report = legacy.base.load_json(report_path, "人工框选渲染报告")
    dataset = legacy.dataset_for_report(report)
    maximum_dimension, maximum_pixels = legacy.bounded_pixel_limit(dataset)
    diagnostic, diagnostic_row = verify_diagnostic(diagnostic_path)
    verify_parent_manifest(dataset, diagnostic)

    envelope = dict(report)
    digest = envelope.pop("reportDigest", None)
    if digest != core.sha256_bytes(core.stable_bytes(envelope)):
        raise core.PilotError("人工框选诊断绑定 reportDigest 不匹配")

    renderer = report.get("renderer", {})
    expected_renderer = {
        "controllerSource": core.artifact(Path(__file__).resolve()),
        "legacyWrapperSource": core.artifact(LEGACY_WRAPPER),
        "baseRendererSource": core.artifact(legacy.BASE_RENDERER),
        "alphaExceptionPolicySource": core.artifact(legacy.ALPHA_POLICY_SOURCE),
        "diagnosticControllerSource": core.artifact(DIAGNOSTIC_CONTROLLER),
        "fidelityDiagnostic": core.artifact(diagnostic_path),
        "pillowSafety": legacy.safety_record(maximum_dimension, maximum_pixels),
    }
    if any(renderer.get(key) != value for key, value in expected_renderer.items()):
        raise core.PilotError("人工框选 controller/diagnostic/Pillow 绑定不闭合")

    original_base_file = legacy.base.__file__
    try:
        legacy.base.__file__ = str(Path(__file__).resolve())
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            legacy.base.check_render(argparse.Namespace(output=str(report_path.parent)))
    finally:
        legacy.base.__file__ = original_base_file
    base_result = json.loads(captured.getvalue().strip().splitlines()[-1])

    rows = report.get("rows", [])
    if len(rows) != len(dataset.get("items", [])):
        raise core.PilotError("人工框选报告行数与 guidance 不一致")
    exceptions = [
        row
        for row in rows
        if row.get("fidelityComparison", {}).get("passedBy") == legacy.alpha_policy.EXCEPTION_CODE
    ]
    if len(exceptions) != 1:
        raise core.PilotError("人工框选诊断绑定必须恰有一个表示例外")
    exception = exceptions[0]
    selection = exception.get("selectedChoice", {})
    if not (
        exception.get("reviewKey") == EXCEPTION_BINDING["reviewKey"]
        and selection.get("sourceRole") == EXCEPTION_BINDING["sourceRole"]
        and selection.get("candidateId") == EXCEPTION_BINDING["candidateId"]
        and selection.get("frame") == EXCEPTION_BINDING["frame"]
        and selection.get("sourceCandidate", {}).get("sha256") == diagnostic_row["sourceCandidate"]["sha256"]
        and selection.get("sourceHighResolution", {}).get("sha256") == diagnostic_row["sourceHighResolution"]["sha256"]
        and exception.get("fidelityComparison", {}).get("representationException")
        == diagnostic_row["alphaRepresentationEvidence"]
    ):
        raise core.PilotError("人工框选表示例外与诊断行不一致")
    for row in rows:
        fidelity = row.get("fidelityComparison", {})
        if fidelity.get("passed") is not True:
            raise core.PilotError(f"人工框选 fidelity 未通过：{row.get('reviewKey')}")
        if row is not exception and (
            fidelity.get("passedBy") != "primary_mae"
            or fidelity.get("meanAbsoluteError", float("inf")) > fidelity.get("limit", -1)
        ):
            raise core.PilotError("非例外行未通过 primary MAE")

    summary = report.get("fidelitySummary", {})
    expected_primary = len(rows) - 1
    if (
        summary.get("totalRows") != len(rows)
        or summary.get("primaryPassedRows") != expected_primary
        or summary.get("representationExceptionRows") != 1
        or summary.get("passedRows") != len(rows)
        or summary.get("allRowsPassedPrimaryOrException") is not True
        or summary.get("exceptionPolicy", {}).get("diagnosticDigest") != diagnostic["diagnosticDigest"]
        or summary.get("exceptionPolicy", {}).get("bindings") != [EXCEPTION_BINDING]
        or report.get("gates", {}).get("fidelityDiagnosticBound") is not True
        or report.get("gates", {}).get("productionWrites") is not False
    ):
        raise core.PilotError("人工框选 fidelity summary/gates 不闭合")
    return {
        "status": "human_guided_automated_checked_with_diagnostic_bound_alpha_exception",
        "report": core.repo_rel(report_path),
        "reportDigest": report["reportDigest"],
        "rows": len(rows),
        "primaryPassedRows": expected_primary,
        "representationExceptionRows": 1,
        "maximumMeanAbsoluteError": summary["maximumMeanAbsoluteError"],
        "artifactCount": base_result["artifactCount"] + len(expected_renderer),
        "maxImagePixels": maximum_pixels,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    report_path = Path(args.output).resolve() / "human-framing-render-report.json"
    print(json.dumps(verify_report(report_path, Path(args.diagnostic_report).resolve()), ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    render_parser = commands.add_parser("render")
    render_parser.add_argument("--guidance-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.add_argument("--diagnostic-report", required=True)
    render_parser.set_defaults(handler=render)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.add_argument("--diagnostic-report", required=True)
    check_parser.set_defaults(handler=check)
    args = parser.parse_args()
    try:
        args.handler(args)
    except (core.PilotError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"[portrait-framing-large-frame-fidelity-v2] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
