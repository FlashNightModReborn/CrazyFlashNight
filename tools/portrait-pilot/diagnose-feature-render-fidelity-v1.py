#!/usr/bin/env python3
"""Render all feature rows into an isolated diagnostic batch and measure fidelity."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
BASE_RENDERER = Path(__file__).with_name("prepare_pilot.py").resolve()
ALPHA_POLICY_SOURCE = Path(__file__).with_name("render-feature-large-frame-fidelity-v1.py").resolve()
SCHEMA = "cf7.portrait-pilot-feature-fidelity-diagnostic.v1"
MAXIMUM_SUPPORTED_FRAME_DIMENSION = 16_384


def load_policy():
    spec = importlib.util.spec_from_file_location("portrait_fidelity_diagnostic_alpha_policy", ALPHA_POLICY_SOURCE)
    if spec is None or spec.loader is None:
        raise core.PilotError("无法加载 alpha 表示诊断策略")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


alpha_policy = load_policy()


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise core.PilotError(f"{label} 缺失：{path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise core.PilotError(f"{label} 顶层必须是对象")
    return value


def ensure_output(value: str, allow_existing: bool = False) -> Path:
    output = Path(value).resolve()
    try:
        relative = output.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise core.PilotError("诊断输出必须位于 tmp/portrait-pilot 下") from error
    if not relative.parts:
        raise core.PilotError("诊断输出不能是 portrait-pilot 根目录")
    if output.exists() and not allow_existing:
        raise core.PilotError(f"诊断输出已存在：{output}")
    return output


def verify_digest(value: dict[str, Any], field: str, label: str) -> None:
    expected = value.get(field)
    envelope = dict(value)
    envelope.pop(field, None)
    if not isinstance(expected, str) or expected != core.sha256_bytes(core.stable_bytes(envelope)):
        raise core.PilotError(f"{label} {field} 不匹配")


def load_inputs(manifest_arg: str, model_report_arg: str) -> tuple[Path, dict[str, Any], dict[str, Any]]:
    manifest_path = Path(manifest_arg).resolve()
    model_report_path = Path(model_report_arg).resolve()
    manifest = load_json(manifest_path, "manifest")
    model_report = load_json(model_report_path, "model report")
    verify_digest(manifest, "manifestDigest", "manifest")
    verify_digest(model_report, "reportDigest", "model report")
    if (
        model_report.get("sourceDigest") != manifest.get("sourceDigest")
        or model_report.get("manifestDigest") != manifest.get("manifestDigest")
    ):
        raise core.PilotError("manifest/model report 摘要不闭合")
    expected_base = next(
        (
            record
            for record in manifest.get("sourceEnvelope", {}).get("sourceFiles", [])
            if record.get("path") == "tools/portrait-pilot/prepare_pilot.py"
        ),
        None,
    )
    if expected_base != core.artifact(BASE_RENDERER):
        raise core.PilotError("manifest 未绑定当前基础 renderer")
    return manifest_path, manifest, model_report


def bounded_pixel_limit(manifest: dict[str, Any]) -> tuple[int, int]:
    contract = manifest.get("featureContract", {}).get("highResolutionRender")
    if not isinstance(contract, dict):
        raise core.PilotError("manifest 缺 highResolutionRender contract")
    maximum_dimension = contract.get("maximumSourceFrameDimension")
    if (
        not isinstance(maximum_dimension, int)
        or isinstance(maximum_dimension, bool)
        or maximum_dimension < 1
        or maximum_dimension > MAXIMUM_SUPPORTED_FRAME_DIMENSION
    ):
        raise core.PilotError("maximumSourceFrameDimension 越界")
    return maximum_dimension, maximum_dimension * maximum_dimension


def run(args: argparse.Namespace) -> None:
    manifest_path, manifest, model_report = load_inputs(args.manifest, args.model_report)
    output = ensure_output(args.output)
    if not args.batch_id or len(args.batch_id) > 128:
        raise core.PilotError("诊断 batch id 非法")
    maximum_dimension, maximum_pixels = bounded_pixel_limit(manifest)
    limit = float(manifest["featureContract"]["highResolutionRender"]["fidelityMeanAbsoluteErrorLimit"])
    original_metric = core.image_mean_absolute_error
    admitted_calls: list[dict[str, Any]] = []

    def diagnostic_metric(left: Image.Image, right: Image.Image) -> tuple[float, list[float]]:
        mean, channels = original_metric(left, right)
        if mean > limit:
            admitted_calls.append(
                {
                    "meanAbsoluteError": float(mean),
                    "perChannel": [float(value) for value in channels],
                    "alphaEvidence": alpha_policy.alpha_representation_evidence(left, right),
                }
            )
            return limit, [limit, limit, limit, limit]
        return mean, channels

    output.mkdir(parents=True)
    base_report_path = output / "diagnostic-base-render-report.json"
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    original_module_file = core.__file__
    core.image_mean_absolute_error = diagnostic_metric
    try:
        core.__file__ = str(Path(__file__).resolve())
        with contextlib.redirect_stdout(io.StringIO()):
            core.render_feature_refinement(manifest, model_report, output, base_report_path)
    finally:
        core.__file__ = original_module_file
        core.image_mean_absolute_error = original_metric

    base_report = load_json(base_report_path, "诊断基础渲染报告")
    verify_digest(base_report, "renderDigest", "诊断基础渲染报告")
    rows: list[dict[str, Any]] = []
    for row in base_report.get("rows", []):
        mean, channels, evidence = alpha_policy.recompute_row_fidelity(
            manifest,
            row,
            original_metric,
            maximum_pixels,
        )
        rows.append(
            {
                "role": row["role"],
                "reviewKey": row["reviewKey"],
                "candidateId": row["candidateId"],
                "frame": row["frame"],
                "meanAbsoluteError": mean,
                "perChannel": dict(zip(("red", "green", "blue", "alpha"), channels)),
                "limit": limit,
                "primaryPassed": mean <= limit,
                "alphaRepresentationEvidence": evidence,
                "sourceCandidate": row["sourceCandidate"],
                "sourceHighResolution": row["sourceHighResolution"],
            }
        )
    over_limit = [row for row in rows if not row["primaryPassed"]]
    diagnostic = {
        "schema": SCHEMA,
        "status": "diagnostic_only",
        "productionReady": False,
        "batchId": args.batch_id,
        "sourceDigest": manifest["sourceDigest"],
        "manifestDigest": manifest["manifestDigest"],
        "modelReportDigest": model_report["reportDigest"],
        "inputs": {
            "manifest": core.artifact(manifest_path),
            "modelReport": core.artifact(Path(args.model_report).resolve()),
            "baseRenderReport": core.artifact(base_report_path),
        },
        "controller": {
            "source": core.artifact(Path(__file__).resolve()),
            "baseRendererSource": core.artifact(BASE_RENDERER),
            "alphaEvidenceSource": core.artifact(ALPHA_POLICY_SOURCE),
            "maximumSourceFrameDimension": maximum_dimension,
            "maxImagePixels": maximum_pixels,
            "unlimitedRasterDecode": False,
        },
        "summary": {
            "rows": len(rows),
            "primaryPassedRows": len(rows) - len(over_limit),
            "overLimitRows": len(over_limit),
            "alphaEvidencePassedRows": len([row for row in over_limit if row["alphaRepresentationEvidence"]["passed"]]),
            "admittedCallsDuringDiagnosticRender": len(admitted_calls),
            "maximumMeanAbsoluteError": max(row["meanAbsoluteError"] for row in rows),
        },
        "rows": rows,
        "gates": {
            "allRowsMeasured": len(rows) == 24,
            "diagnosticAdmissionIsNotAcceptance": True,
            "globalThresholdUnchanged": True,
            "boundedPillowDecode": True,
            "productionWrites": False,
        },
    }
    diagnostic["diagnosticDigest"] = core.sha256_bytes(core.stable_bytes(diagnostic))
    report_path = output / "fidelity-diagnostic.json"
    core.write_json(report_path, diagnostic)
    print(
        json.dumps(
            {
                "status": diagnostic["status"],
                "report": core.repo_rel(report_path),
                "diagnosticDigest": diagnostic["diagnosticDigest"],
                "summary": diagnostic["summary"],
                "overLimit": [
                    {
                        "role": row["role"],
                        "reviewKey": row["reviewKey"],
                        "candidateId": row["candidateId"],
                        "frame": row["frame"],
                        "meanAbsoluteError": row["meanAbsoluteError"],
                        "alphaEvidencePassed": row["alphaRepresentationEvidence"]["passed"],
                    }
                    for row in over_limit
                ],
            },
            ensure_ascii=False,
        )
    )


def check(args: argparse.Namespace) -> None:
    report_path = Path(args.report).resolve()
    report = load_json(report_path, "fidelity diagnostic")
    if report.get("schema") != SCHEMA or report.get("status") != "diagnostic_only" or report.get("productionReady") is not False:
        raise core.PilotError("fidelity diagnostic schema 或状态非法")
    verify_digest(report, "diagnosticDigest", "fidelity diagnostic")
    records = [
        *report["inputs"].values(),
        report["controller"]["source"],
        report["controller"]["baseRendererSource"],
        report["controller"]["alphaEvidenceSource"],
    ]
    for row in report["rows"]:
        records.extend((row["sourceCandidate"], row["sourceHighResolution"]))
    for record in records:
        core.verify_artifact_record(record, "fidelity diagnostic artifact")
    summary = report["summary"]
    if (
        len(report["rows"]) != 24
        or summary["rows"] != 24
        or summary["overLimitRows"] != len([row for row in report["rows"] if not row["primaryPassed"]])
        or report["gates"].get("diagnosticAdmissionIsNotAcceptance") is not True
        or report["gates"].get("productionWrites") is not False
    ):
        raise core.PilotError("fidelity diagnostic 闭包非法")
    print(json.dumps({"status": "feature_fidelity_diagnostic_verified", "diagnosticDigest": report["diagnosticDigest"], "summary": summary, "artifactCount": len(records)}, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    run_parser = commands.add_parser("run")
    run_parser.add_argument("--manifest", required=True)
    run_parser.add_argument("--model-report", required=True)
    run_parser.add_argument("--output", required=True)
    run_parser.add_argument("--batch-id", required=True)
    run_parser.set_defaults(handler=run)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--report", required=True)
    check_parser.set_defaults(handler=check)
    args = parser.parse_args()
    try:
        args.handler(args)
    except (core.PilotError, subprocess.SubprocessError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"portrait fidelity diagnostic error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
