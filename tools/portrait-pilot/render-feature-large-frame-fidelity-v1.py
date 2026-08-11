#!/usr/bin/env python3
"""Render one large-frame shard with one exact binary-GIF alpha exception."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
BASE_RENDERER = ROOT / "tools" / "portrait-pilot" / "prepare_pilot.py"
MAXIMUM_SUPPORTED_FRAME_DIMENSION = 16_384
SAFETY_SCHEMA = "cf7.portrait-pilot-pillow-large-frame-safety.v1"
EXCEPTION_CODE = "binary_gif_alpha_cannot_represent_semtransparent_selected_frame"
EXCEPTION_BINDING = {
    "role": "proposal",
    "reviewKey": "敌人-方舟妖姬::default",
    "candidateId": "e10-c03",
    "frame": 25,
}
ALPHA_THRESHOLD = 128
MINIMUM_SEMITRANSPARENT_FRACTION = 0.05
MINIMUM_OPAQUE_CORE_IOU = 0.80
MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE = 0.02


class FidelityError(RuntimeError):
    pass


def load_core():
    spec = importlib.util.spec_from_file_location("cf7_portrait_prepare_pilot_large_fidelity", BASE_RENDERER)
    if spec is None or spec.loader is None:
        raise FidelityError("无法加载基础 renderer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


core = load_core()


def repo_path(value: str | Path, label: str) -> Path:
    candidate = Path(value)
    resolved = candidate.resolve() if candidate.is_absolute() else (ROOT / candidate).resolve()
    try:
        resolved.relative_to(ROOT.resolve())
    except ValueError as error:
        raise FidelityError(f"{label} 必须位于仓库内：{resolved}") from error
    return resolved


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise FidelityError(f"{label} 缺失：{path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise FidelityError(f"{label} 顶层必须是对象")
    return value


def verify_digest(value: dict[str, Any], field: str, label: str) -> None:
    expected = value.get(field)
    envelope = dict(value)
    envelope.pop(field, None)
    actual = core.sha256_bytes(core.stable_bytes(envelope))
    if not isinstance(expected, str) or actual != expected:
        raise FidelityError(f"{label} {field} 不匹配")


def verify_base_renderer_bound(manifest: dict[str, Any]) -> None:
    expected = next(
        (
            record
            for record in manifest.get("sourceEnvelope", {}).get("sourceFiles", [])
            if record.get("path") == "tools/portrait-pilot/prepare_pilot.py"
        ),
        None,
    )
    if expected is None or expected != core.artifact(BASE_RENDERER):
        raise FidelityError("manifest 未绑定当前基础 renderer source")


def bounded_pixel_limit(manifest: dict[str, Any]) -> tuple[int, int]:
    contract = manifest.get("featureContract", {}).get("highResolutionRender")
    if not isinstance(contract, dict):
        raise FidelityError("manifest 缺 highResolutionRender contract")
    maximum_dimension = contract.get("maximumSourceFrameDimension")
    if (
        not isinstance(maximum_dimension, int)
        or isinstance(maximum_dimension, bool)
        or maximum_dimension < 1
        or maximum_dimension > MAXIMUM_SUPPORTED_FRAME_DIMENSION
    ):
        raise FidelityError(
            f"maximumSourceFrameDimension 必须在 1–{MAXIMUM_SUPPORTED_FRAME_DIMENSION}：{maximum_dimension}"
        )
    return maximum_dimension, maximum_dimension * maximum_dimension


def rgba_sha256(image: Image.Image) -> str:
    rgba = image.convert("RGBA")
    envelope = f"{rgba.width}x{rgba.height}:RGBA:".encode("ascii") + rgba.tobytes()
    return hashlib.sha256(envelope).hexdigest().upper()


def opaque_center(mask: np.ndarray) -> tuple[float, float] | None:
    y_values, x_values = np.nonzero(mask)
    if len(x_values) == 0:
        return None
    return float(x_values.mean() / mask.shape[1]), float(y_values.mean() / mask.shape[0])


def alpha_representation_evidence(
    selected_frame_restored: Image.Image,
    bound_gif_candidate: Image.Image,
) -> dict[str, Any]:
    if selected_frame_restored.size != bound_gif_candidate.size:
        raise FidelityError("alpha 例外比较尺寸不一致")
    selected = np.asarray(selected_frame_restored.convert("RGBA"), dtype=np.uint8)
    candidate = np.asarray(bound_gif_candidate.convert("RGBA"), dtype=np.uint8)
    selected_alpha = selected[:, :, 3]
    candidate_alpha = candidate[:, :, 3]
    candidate_levels = [int(value) for value in np.unique(candidate_alpha)]
    candidate_binary = set(candidate_levels).issubset({0, 255}) and len(candidate_levels) == 2
    selected_semitransparent_fraction = float(np.mean((selected_alpha > 0) & (selected_alpha < 255)))
    candidate_core = candidate_alpha > ALPHA_THRESHOLD
    selected_core = selected_alpha > ALPHA_THRESHOLD
    intersection = int(np.logical_and(candidate_core, selected_core).sum())
    union = int(np.logical_or(candidate_core, selected_core).sum())
    opaque_core_iou = float(intersection / union) if union else 1.0
    candidate_center = opaque_center(candidate_core)
    selected_center = opaque_center(selected_core)
    centroid_distance = (
        math.inf
        if candidate_center is None or selected_center is None
        else math.dist(candidate_center, selected_center)
    )
    passed = (
        candidate_binary
        and selected_semitransparent_fraction >= MINIMUM_SEMITRANSPARENT_FRACTION
        and opaque_core_iou >= MINIMUM_OPAQUE_CORE_IOU
        and centroid_distance <= MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE
    )
    return {
        "code": EXCEPTION_CODE,
        "boundGifCandidateRgbaSha256": rgba_sha256(bound_gif_candidate),
        "selectedFrameRestoredRgbaSha256": rgba_sha256(selected_frame_restored),
        "boundGifCandidateAlphaLevels": candidate_levels,
        "boundGifCandidateBinaryAlpha": candidate_binary,
        "selectedFrameSemiTransparentFraction": round(selected_semitransparent_fraction, 9),
        "minimumSelectedFrameSemiTransparentFraction": MINIMUM_SEMITRANSPARENT_FRACTION,
        "opaqueCoreAlphaThreshold": ALPHA_THRESHOLD,
        "opaqueCoreIoU": round(opaque_core_iou, 9),
        "minimumOpaqueCoreIoU": MINIMUM_OPAQUE_CORE_IOU,
        "opaqueCoreCentroidDistance": round(centroid_distance, 9),
        "maximumOpaqueCoreCentroidDistance": MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE,
        "passed": passed,
    }


def candidate_record(manifest: dict[str, Any], review_key: str, candidate_id: str) -> dict[str, Any]:
    item = next((row for row in manifest["reviewItems"] if row["reviewKey"] == review_key), None)
    if item is None:
        raise FidelityError(f"render row 找不到 review item：{review_key}")
    candidate = next((row for row in item["candidates"] if row["candidateId"] == candidate_id), None)
    if candidate is None:
        raise FidelityError(f"render row 找不到 candidate：{review_key}/{candidate_id}")
    return candidate


def recompute_row_fidelity(
    manifest: dict[str, Any],
    row: dict[str, Any],
    original_metric,
    maximum_pixels: int,
) -> tuple[float, list[float], dict[str, Any]]:
    candidate = candidate_record(manifest, row["reviewKey"], row["candidateId"])
    high_resolution_path = core.verify_artifact_record(
        row["sourceHighResolution"], f"selected frame {row['role']}/{row['reviewKey']}"
    )
    candidate_path = core.verify_artifact_record(
        row["sourceCandidate"], f"bound candidate {row['role']}/{row['reviewKey']}"
    )
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    with Image.open(high_resolution_path) as image:
        selected_frame = image.convert("RGBA")
    restored, _scale = core.candidate_from_high_resolution(selected_frame, candidate)
    with Image.open(candidate_path) as image:
        bound_candidate = image.convert("RGBA")
    mean, channels = original_metric(restored, bound_candidate)
    evidence = alpha_representation_evidence(restored, bound_candidate)
    return float(mean), [float(value) for value in channels], evidence


def is_exact_exception(row: dict[str, Any]) -> bool:
    return all(row.get(field) == value for field, value in EXCEPTION_BINDING.items())


def load_bound_inputs(manifest_path: Path, model_report_path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    if manifest_path.parent != model_report_path.parent:
        raise FidelityError("manifest 与 model report 必须属于同一批次")
    manifest = load_json(manifest_path, "manifest")
    model_report = load_json(model_report_path, "model report")
    verify_digest(manifest, "manifestDigest", "manifest")
    verify_digest(model_report, "reportDigest", "model report")
    if (
        model_report.get("sourceDigest") != manifest.get("sourceDigest")
        or model_report.get("manifestDigest") != manifest.get("manifestDigest")
    ):
        raise FidelityError("manifest/model report 摘要不闭合")
    verify_base_renderer_bound(manifest)
    return manifest, model_report


def render(args: argparse.Namespace) -> None:
    manifest_path = repo_path(args.manifest, "manifest")
    model_report_path = repo_path(args.model_report, "model report")
    manifest, _model_report = load_bound_inputs(manifest_path, model_report_path)
    maximum_dimension, maximum_pixels = bounded_pixel_limit(manifest)
    limit = float(manifest["featureContract"]["highResolutionRender"]["fidelityMeanAbsoluteErrorLimit"])
    original_metric = core.image_mean_absolute_error
    admitted_calls: list[dict[str, Any]] = []

    def admission_metric(left: Image.Image, right: Image.Image) -> tuple[float, list[float]]:
        mean, channels = original_metric(left, right)
        if mean <= limit:
            return mean, channels
        evidence = alpha_representation_evidence(left, right)
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

    report_path = manifest_path.parent / "render-report.json"
    if report_path.exists():
        raise FidelityError("render-report.json 已存在，禁止覆盖")
    core.image_mean_absolute_error = admission_metric
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    captured = io.StringIO()
    try:
        with contextlib.redirect_stdout(captured):
            core.render(argparse.Namespace(manifest=str(manifest_path), model_report=str(model_report_path)))
    finally:
        core.image_mean_absolute_error = original_metric
    if not report_path.is_file():
        raise FidelityError("基础 renderer 未生成 report")
    report = load_json(report_path, "render report")
    verify_digest(report, "renderDigest", "base render report")

    exception_rows: list[dict[str, Any]] = []
    actual_values: list[float] = []
    primary_pass_rows = 0
    for row in report.get("rows", []):
        mean, channels, evidence = recompute_row_fidelity(
            manifest, row, original_metric, maximum_pixels
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
            raise FidelityError(
                f"未授权的 fidelity 超限：{row.get('role')}/{row.get('reviewKey')} mean={mean:.4f}"
            )
        row["fidelityComparison"] = {
            "metric": "premultiplied RGBA MAE with exact binary-GIF alpha representation exception",
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
                **EXCEPTION_BINDING,
                "primaryMeanAbsoluteError": mean,
                "representationEvidence": evidence,
            }
        )

    if len(admitted_calls) != 1 or len(exception_rows) != 1:
        raise FidelityError(
            f"预期恰有一个逐角色绑定例外：admitted={len(admitted_calls)} report={len(exception_rows)}"
        )

    report["renderer"]["controllerSource"] = core.artifact(Path(__file__).resolve())
    report["renderer"]["baseRendererSource"] = core.artifact(BASE_RENDERER)
    report["renderer"]["numpy"] = np.__version__
    report["renderer"]["pillowSafety"] = {
        "schema": SAFETY_SCHEMA,
        "maxImagePixels": maximum_pixels,
        "pillowHardErrorAbovePixels": maximum_pixels * 2,
        "manifestMaximumSourceFrameDimension": maximum_dimension,
        "boundedByManifest": True,
        "unlimitedRasterDecode": False,
    }
    report["fidelitySummary"] = {
        "comparison": "primary premultiplied RGBA MAE; only one exact role/identity/candidate/frame may use opaque-core correspondence when binary GIF cannot represent selected-frame semitransparency",
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
            "bindings": [EXCEPTION_BINDING],
            "minimumSelectedFrameSemiTransparentFraction": MINIMUM_SEMITRANSPARENT_FRACTION,
            "opaqueCoreAlphaThreshold": ALPHA_THRESHOLD,
            "minimumOpaqueCoreIoU": MINIMUM_OPAQUE_CORE_IOU,
            "maximumOpaqueCoreCentroidDistance": MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE,
            "scope": "candidate correspondence only; no art acceptance and no global threshold relaxation",
        },
        "exceptionRows": exception_rows,
    }
    report["gates"]["premultipliedRgbaPrimaryChecked"] = True
    report["gates"]["binaryGifSemitransparencyExceptionChecked"] = True
    report["gates"]["exceptionRoleIdentityCandidateFrameBound"] = True
    report["gates"]["boundedPillowLargeFrameChecked"] = True
    report["gates"]["allRowsPassedPrimaryOrException"] = True
    report.pop("renderDigest", None)
    report["renderDigest"] = core.sha256_bytes(core.stable_bytes(report))
    core.write_json(report_path, report)
    checked = verify_report(manifest_path, model_report_path, report_path)
    checked["baseRendererOutput"] = captured.getvalue().strip()
    print(json.dumps(checked, ensure_ascii=False))


def verify_report(manifest_path: Path, model_report_path: Path, report_path: Path) -> dict[str, Any]:
    manifest, model_report = load_bound_inputs(manifest_path, model_report_path)
    maximum_dimension, maximum_pixels = bounded_pixel_limit(manifest)
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
        raise FidelityError("render report 跨层摘要或状态不闭合")
    renderer = report.get("renderer", {})
    if renderer.get("controllerSource") != core.artifact(Path(__file__).resolve()):
        raise FidelityError("render report 未绑定当前 controller")
    if renderer.get("baseRendererSource") != core.artifact(BASE_RENDERER):
        raise FidelityError("render report 未绑定基础 renderer")
    expected_safety = {
        "schema": SAFETY_SCHEMA,
        "maxImagePixels": maximum_pixels,
        "pillowHardErrorAbovePixels": maximum_pixels * 2,
        "manifestMaximumSourceFrameDimension": maximum_dimension,
        "boundedByManifest": True,
        "unlimitedRasterDecode": False,
    }
    if renderer.get("pillowSafety") != expected_safety:
        raise FidelityError("Pillow 大帧安全合同不闭合")
    expected_rows = len([item for item in manifest["reviewItems"] if not item["blocked"]]) * 2
    rows = report.get("rows", [])
    if len(rows) != expected_rows or {row.get("role") for row in rows} != {"proposal", "independent_review"}:
        raise FidelityError("render report 行数或角色不闭合")
    exceptions: list[dict[str, Any]] = []
    artifact_count = 2
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
            raise FidelityError(f"render fidelity 未通过：{row.get('role')}/{row.get('reviewKey')}")
        if fidelity.get("passedBy") == EXCEPTION_CODE:
            exceptions.append(row)
        elif fidelity.get("passedBy") != "primary_mae" or fidelity.get("meanAbsoluteError", math.inf) > fidelity.get("limit", -1):
            raise FidelityError("primary fidelity 语义非法")
    if len(exceptions) != 1 or not is_exact_exception(exceptions[0]):
        raise FidelityError("二值 GIF alpha 例外未精确绑定唯一行")
    if exceptions[0].get("fidelityComparison", {}).get("representationException", {}).get("passed") is not True:
        raise FidelityError("二值 GIF alpha 例外缺核心对应证据")
    summary = report.get("fidelitySummary", {})
    if (
        summary.get("primaryPassedRows") != expected_rows - 1
        or summary.get("representationExceptionRows") != 1
        or summary.get("passedRows") != expected_rows
        or summary.get("allRowsPassedPrimaryOrException") is not True
        or report.get("gates", {}).get("productionWrites") is not False
    ):
        raise FidelityError("render fidelity summary/gates 不闭合")
    return {
        "status": "automated_checked",
        "report": core.repo_rel(report_path),
        "renderDigest": report["renderDigest"],
        "rows": len(rows),
        "primaryPassedRows": summary["primaryPassedRows"],
        "representationExceptionRows": summary["representationExceptionRows"],
        "maximumPrimaryMeanAbsoluteError": summary["maximumMeanAbsoluteError"],
        "artifactCount": artifact_count,
        "maxImagePixels": maximum_pixels,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    manifest_path = repo_path(args.manifest, "manifest")
    model_report_path = repo_path(args.model_report, "model report")
    report_path = manifest_path.parent / "render-report.json"
    print(json.dumps(verify_report(manifest_path, model_report_path, report_path), ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command, handler in (("render", render), ("check", check)):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--manifest", required=True)
        subparser.add_argument("--model-report", required=True)
        subparser.set_defaults(handler=handler)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
