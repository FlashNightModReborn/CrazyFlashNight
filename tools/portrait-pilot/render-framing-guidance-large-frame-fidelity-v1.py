#!/usr/bin/env python3
"""Render human framing with bounded large frames and one exact GIF alpha exception."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
BASE_RENDERER = Path(__file__).with_name("render-framing-guidance.py").resolve()
ALPHA_POLICY_SOURCE = Path(__file__).with_name("render-feature-large-frame-fidelity-v1.py").resolve()
MAXIMUM_SUPPORTED_FRAME_DIMENSION = 16_384
SAFETY_SCHEMA = "cf7.portrait-pilot-human-framing-pillow-large-frame-safety.v1"
EXCEPTION_BINDING = {
    "sourceRole": "proposal",
    "reviewKey": "敌人-方舟妖姬::default",
    "candidateId": "e10-c03",
    "frame": 25,
}


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise core.PilotError(f"无法加载模块：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_module(BASE_RENDERER, "portrait_framing_guidance_fidelity_base")
alpha_policy = load_module(ALPHA_POLICY_SOURCE, "portrait_binary_gif_alpha_policy")


def bounded_pixel_limit(dataset: dict[str, Any]) -> tuple[int, int]:
    manifest_record = dataset.get("parent", {}).get("files", {}).get("candidateManifest")
    manifest_path = core.verify_artifact_record(manifest_record, "人工框选父 candidate manifest")
    manifest = core.load_json(manifest_path)
    contract = manifest.get("featureContract", {}).get("highResolutionRender")
    if not isinstance(contract, dict):
        raise core.PilotError("人工框选父 manifest 缺 highResolutionRender contract")
    maximum_dimension = contract.get("maximumSourceFrameDimension")
    if (
        not isinstance(maximum_dimension, int)
        or isinstance(maximum_dimension, bool)
        or maximum_dimension < 1
        or maximum_dimension > MAXIMUM_SUPPORTED_FRAME_DIMENSION
    ):
        raise core.PilotError(
            f"maximumSourceFrameDimension 必须在 1–{MAXIMUM_SUPPORTED_FRAME_DIMENSION}：{maximum_dimension}"
        )
    return maximum_dimension, maximum_dimension * maximum_dimension


def safety_record(maximum_dimension: int, maximum_pixels: int) -> dict[str, Any]:
    return {
        "schema": SAFETY_SCHEMA,
        "maxImagePixels": maximum_pixels,
        "pillowHardErrorAbovePixels": maximum_pixels * 2,
        "manifestMaximumSourceFrameDimension": maximum_dimension,
        "boundedByManifest": True,
        "unlimitedRasterDecode": False,
    }


def dataset_for_render(guidance_batch: str) -> dict[str, Any]:
    guidance_root = base.ensure_pilot_child(Path(guidance_batch), "框选指导批次", allow_existing=True)
    dataset, _, _, _ = base.verify_guidance_receipt(guidance_root)
    return dataset


def dataset_for_report(report: dict[str, Any]) -> dict[str, Any]:
    path = core.verify_artifact_record(report.get("inputs", {}).get("guidanceData"), "人工框选 guidance data")
    dataset = core.load_json(path)
    if not isinstance(dataset, dict):
        raise core.PilotError("人工框选 guidance data 顶层必须是对象")
    return dataset


def selected_choice(dataset: dict[str, Any], row: dict[str, Any]) -> dict[str, Any]:
    item = next((entry for entry in dataset["items"] if entry["reviewKey"] == row["reviewKey"]), None)
    if item is None:
        raise core.PilotError(f"人工框选报告找不到 guidance item：{row['reviewKey']}")
    selection = row.get("selectedChoice", {})
    choice = next(
        (
            entry
            for entry in item["choices"]
            if entry["sourceRole"] == selection.get("sourceRole")
            and entry["candidateId"] == selection.get("candidateId")
            and entry["frame"] == selection.get("frame")
        ),
        None,
    )
    if choice is None:
        raise core.PilotError(f"人工框选报告选择不在 guidance choices：{row['reviewKey']}")
    return choice


def recompute_fidelity(
    dataset: dict[str, Any],
    row: dict[str, Any],
    metric,
    maximum_pixels: int,
) -> tuple[float, list[float], dict[str, Any]]:
    choice = selected_choice(dataset, row)
    candidate = {
        "candidateId": choice["candidateId"],
        "width": int(choice["candidateWidth"]),
        "height": int(choice["candidateHeight"]),
        "sourceSize": choice["sourceSize"],
        "sourceCropBounds": choice["sourceCropBounds"],
    }
    high_resolution_path = core.verify_artifact_record(
        row["selectedChoice"]["sourceHighResolution"], f"人工框选高分辨率帧 {row['reviewKey']}"
    )
    candidate_path = core.verify_artifact_record(
        row["selectedChoice"]["sourceCandidate"], f"人工框选候选 {row['reviewKey']}"
    )
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    with Image.open(high_resolution_path) as image:
        high_resolution = image.convert("RGBA")
    restored, _source_scale = core.candidate_from_high_resolution(high_resolution, candidate)
    with Image.open(candidate_path) as image:
        bound_candidate = image.convert("RGBA")
    mean, channels = metric(restored, bound_candidate)
    evidence = alpha_policy.alpha_representation_evidence(restored, bound_candidate)
    return float(mean), [float(value) for value in channels], evidence


def is_exact_exception(row: dict[str, Any]) -> bool:
    selection = row.get("selectedChoice", {})
    return (
        row.get("reviewKey") == EXCEPTION_BINDING["reviewKey"]
        and selection.get("sourceRole") == EXCEPTION_BINDING["sourceRole"]
        and selection.get("candidateId") == EXCEPTION_BINDING["candidateId"]
        and selection.get("frame") == EXCEPTION_BINDING["frame"]
    )


def render(args: argparse.Namespace) -> None:
    dataset = dataset_for_render(args.guidance_batch)
    maximum_dimension, maximum_pixels = bounded_pixel_limit(dataset)
    limit = float(dataset["renderContract"]["fidelityMeanAbsoluteErrorLimit"])
    original_metric = base.core.image_mean_absolute_error
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

    Image.MAX_IMAGE_PIXELS = maximum_pixels
    original_module_file = base.__file__
    base.core.image_mean_absolute_error = admission_metric
    try:
        base.__file__ = str(Path(__file__).resolve())
        with contextlib.redirect_stdout(io.StringIO()):
            base.render_guidance(args)
    finally:
        base.__file__ = original_module_file
        base.core.image_mean_absolute_error = original_metric

    report_path = Path(args.output).resolve() / "human-framing-render-report.json"
    report = base.load_json(report_path, "人工框选渲染报告")
    exception_rows: list[dict[str, Any]] = []
    actual_values: list[float] = []
    primary_pass_rows = 0
    for row in report.get("rows", []):
        mean, channels, evidence = recompute_fidelity(dataset, row, original_metric, maximum_pixels)
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
            raise core.PilotError(f"未授权的人工框选 fidelity 超限：{row['reviewKey']} mean={mean:.4f}")
        row["fidelityComparison"] = {
            "metric": "premultiplied RGBA MAE with exact binary-GIF alpha representation exception",
            "meanAbsoluteError": mean,
            "perChannel": dict(zip(("red", "green", "blue", "alpha"), channels)),
            "limit": limit,
            "primaryPassed": False,
            "passedBy": alpha_policy.EXCEPTION_CODE,
            "representationException": evidence,
            "passed": True,
        }
        exception_rows.append(
            {
                **EXCEPTION_BINDING,
                "primaryMeanAbsoluteError": mean,
                "representationEvidence": evidence,
            }
        )

    if len(admitted_calls) != 1 or len(exception_rows) != 1:
        raise core.PilotError(
            f"预期恰有一个人工框选透明表示例外：admitted={len(admitted_calls)} report={len(exception_rows)}"
        )

    report["renderer"]["controllerSource"] = core.artifact(Path(__file__).resolve())
    report["renderer"]["baseRendererSource"] = core.artifact(BASE_RENDERER)
    report["renderer"]["alphaExceptionPolicySource"] = core.artifact(ALPHA_POLICY_SOURCE)
    report["renderer"]["numpy"] = alpha_policy.np.__version__
    report["renderer"]["pillowSafety"] = safety_record(maximum_dimension, maximum_pixels)
    report["fidelitySummary"] = {
        "comparison": "primary premultiplied RGBA MAE; one exact human-selected role/identity/candidate/frame may use opaque-core correspondence when binary GIF cannot represent selected-frame semitransparency",
        "meanAbsoluteErrorLimit": limit,
        "maximumMeanAbsoluteError": max(actual_values),
        "averageMeanAbsoluteError": sum(actual_values) / len(actual_values),
        "totalRows": len(actual_values),
        "primaryPassedRows": primary_pass_rows,
        "representationExceptionRows": len(exception_rows),
        "passedRows": primary_pass_rows + len(exception_rows),
        "allRowsPassedPrimaryOrException": primary_pass_rows + len(exception_rows) == len(actual_values),
        "exceptionPolicy": {
            "code": alpha_policy.EXCEPTION_CODE,
            "bindings": [EXCEPTION_BINDING],
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
    report["gates"]["exceptionRoleIdentityCandidateFrameBound"] = True
    report["gates"]["boundedPillowLargeFrameChecked"] = True
    report["gates"]["allRowsPassedPrimaryOrException"] = True
    report.pop("reportDigest", None)
    report["reportDigest"] = core.sha256_bytes(core.stable_bytes(report))
    core.write_json(report_path, report)
    result = verify_report(report_path)
    print(json.dumps(result, ensure_ascii=False))


def verify_report(report_path: Path) -> dict[str, Any]:
    report = base.load_json(report_path, "人工框选渲染报告")
    dataset = dataset_for_report(report)
    maximum_dimension, maximum_pixels = bounded_pixel_limit(dataset)
    envelope = dict(report)
    digest = envelope.pop("reportDigest", None)
    if digest != core.sha256_bytes(core.stable_bytes(envelope)):
        raise core.PilotError("人工框选大帧例外 reportDigest 不匹配")
    renderer = report.get("renderer", {})
    if renderer.get("controllerSource") != core.artifact(Path(__file__).resolve()):
        raise core.PilotError("人工框选大帧例外未绑定当前 controller")
    if renderer.get("baseRendererSource") != core.artifact(BASE_RENDERER):
        raise core.PilotError("人工框选大帧例外未绑定基础 renderer")
    if renderer.get("alphaExceptionPolicySource") != core.artifact(ALPHA_POLICY_SOURCE):
        raise core.PilotError("人工框选大帧例外未绑定 alpha policy")
    if renderer.get("pillowSafety") != safety_record(maximum_dimension, maximum_pixels):
        raise core.PilotError("人工框选 Pillow 大帧安全合同不闭合")

    original_module_file = base.__file__
    try:
        base.__file__ = str(Path(__file__).resolve())
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            base.check_render(argparse.Namespace(output=str(report_path.parent)))
    finally:
        base.__file__ = original_module_file
    base_result = json.loads(captured.getvalue().strip().splitlines()[-1])

    rows = report.get("rows", [])
    exceptions = [
        row
        for row in rows
        if row.get("fidelityComparison", {}).get("passedBy") == alpha_policy.EXCEPTION_CODE
    ]
    for row in rows:
        fidelity = row.get("fidelityComparison", {})
        if fidelity.get("passed") is not True:
            raise core.PilotError(f"人工框选 fidelity 未通过：{row.get('reviewKey')}")
        if row in exceptions:
            if not is_exact_exception(row) or fidelity.get("representationException", {}).get("passed") is not True:
                raise core.PilotError("人工框选透明表示例外未精确绑定")
        elif fidelity.get("passedBy") != "primary_mae" or fidelity.get("meanAbsoluteError", math.inf) > fidelity.get("limit", -1):
            raise core.PilotError("人工框选 primary fidelity 语义非法")
    summary = report.get("fidelitySummary", {})
    if (
        len(rows) != 12
        or len(exceptions) != 1
        or summary.get("primaryPassedRows") != 11
        or summary.get("representationExceptionRows") != 1
        or summary.get("passedRows") != 12
        or summary.get("allRowsPassedPrimaryOrException") is not True
        or report.get("gates", {}).get("productionWrites") is not False
    ):
        raise core.PilotError("人工框选 fidelity summary/gates 不闭合")
    return {
        "status": "human_guided_automated_checked_with_bounded_large_frame_and_exact_alpha_exception",
        "report": core.repo_rel(report_path),
        "reportDigest": report["reportDigest"],
        "rows": len(rows),
        "primaryPassedRows": summary["primaryPassedRows"],
        "representationExceptionRows": summary["representationExceptionRows"],
        "maximumPrimaryMeanAbsoluteError": summary["maximumMeanAbsoluteError"],
        "artifactCount": base_result["artifactCount"] + 2,
        "maxImagePixels": maximum_pixels,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    report_path = Path(args.output).resolve() / "human-framing-render-report.json"
    print(json.dumps(verify_report(report_path), ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--guidance-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.set_defaults(handler=render)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.set_defaults(handler=check)
    args = parser.parse_args()
    try:
        args.handler(args)
    except (core.PilotError, subprocess.SubprocessError, OSError, ValueError) as error:
        print(f"[portrait-framing-large-frame-fidelity-render] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
