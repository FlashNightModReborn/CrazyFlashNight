#!/usr/bin/env python3
"""Derive exact near-threshold vector/raster correspondence evidence for one bound frame."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
DIAGNOSTIC_CONTROLLER = Path(__file__).with_name(
    "diagnose-feature-render-fidelity-human-review-v1.py"
).resolve()
EXPECTED_DIAGNOSTIC_CONTROLLER_SHA256 = "E26198E6DA4A0F839888E3ADE0E0E444BEF6C7B8C4E1640F17845F9F42D579FF"
SCHEMA = "cf7.portrait-pilot-near-threshold-rasterization-evidence.v1"
OUTPUT_NAME = "near-threshold-rasterization-evidence.json"
EXCEPTION_CODE = "near_threshold_vector_rasterization_with_strict_shape_correspondence"
REVIEW_CODE = "R22"
CANDIDATE_ID = "e22-c01"
FRAME = 1
ROLES = {"proposal", "independent_review"}
MAXIMUM_MAE = 8.25
MAXIMUM_EXCESS = 0.25
MAXIMUM_ALPHA_MAE = 2.0
MINIMUM_OPAQUE_CORE_IOU = 0.98
MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE = 0.002
EDGE_THRESHOLD = 32
EDGE_TOLERANCE_PIXELS = 1
MINIMUM_EDGE_RECALL = 0.99
MAXIMUM_ALPHA_BBOX_DELTA = 1


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
    if file_sha256(DIAGNOSTIC_CONTROLLER) != EXPECTED_DIAGNOSTIC_CONTROLLER_SHA256:
        raise RuntimeError("人审 fidelity diagnostic controller 字节已漂移")
    diagnostic = load_module(DIAGNOSTIC_CONTROLLER, "portrait_near_threshold_diagnostic")
    human_renderer, alpha_policy, base = diagnostic.load_dependencies()
    return diagnostic, human_renderer, alpha_policy, base


def ensure_output(value: str, must_exist: bool) -> Path:
    output = Path(value).resolve()
    try:
        relative = output.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise RuntimeError("证据输出必须位于 tmp/portrait-pilot 下") from error
    if not relative.parts:
        raise RuntimeError("证据输出不能是 portrait-pilot 根目录")
    if must_exist and not output.is_file():
        raise RuntimeError("近阈值证据文件缺失")
    if not must_exist and output.exists():
        raise RuntimeError("近阈值证据文件已存在，禁止覆盖")
    if output.name != OUTPUT_NAME:
        raise RuntimeError(f"证据输出文件名必须是 {OUTPUT_NAME}")
    return output


def opaque_center(mask: np.ndarray) -> tuple[float, float] | None:
    y_values, x_values = np.nonzero(mask)
    if len(x_values) == 0:
        return None
    return float(x_values.mean() / mask.shape[1]), float(y_values.mean() / mask.shape[0])


def edge_mask(premultiplied_rgb: np.ndarray) -> np.ndarray:
    luminance = np.clip(
        premultiplied_rgb[:, :, 0] * 0.2126
        + premultiplied_rgb[:, :, 1] * 0.7152
        + premultiplied_rgb[:, :, 2] * 0.0722,
        0,
        255,
    ).astype(np.uint8)
    edges = np.asarray(Image.fromarray(luminance).filter(ImageFilter.FIND_EDGES), dtype=np.uint8)
    return edges >= EDGE_THRESHOLD


def dilate(mask: np.ndarray) -> np.ndarray:
    size = EDGE_TOLERANCE_PIXELS * 2 + 1
    image = Image.fromarray((mask.astype(np.uint8) * 255))
    return np.asarray(image.filter(ImageFilter.MaxFilter(size)), dtype=np.uint8) > 0


def correspondence_evidence(selected: Image.Image, candidate: Image.Image) -> dict[str, Any]:
    if selected.size != candidate.size:
        raise RuntimeError("近阈值证据比较尺寸不一致")
    left = np.asarray(selected.convert("RGBA"), dtype=np.float64)
    right = np.asarray(candidate.convert("RGBA"), dtype=np.float64)
    left_alpha = left[:, :, 3]
    right_alpha = right[:, :, 3]
    left_core = left_alpha > 128
    right_core = right_alpha > 128
    intersection = int(np.logical_and(left_core, right_core).sum())
    union = int(np.logical_or(left_core, right_core).sum())
    core_iou = float(intersection / union) if union else 1.0
    left_center = opaque_center(left_core)
    right_center = opaque_center(right_core)
    centroid_distance = (
        math.inf if left_center is None or right_center is None else math.dist(left_center, right_center)
    )
    alpha_mae = float(np.abs(left_alpha - right_alpha).mean())
    left_premultiplied = left[:, :, :3] * (left_alpha[:, :, None] / 255.0)
    right_premultiplied = right[:, :, :3] * (right_alpha[:, :, None] / 255.0)
    left_edges = edge_mask(left_premultiplied)
    right_edges = edge_mask(right_premultiplied)
    left_recall = float(np.logical_and(left_edges, dilate(right_edges)).sum() / max(1, left_edges.sum()))
    right_recall = float(np.logical_and(right_edges, dilate(left_edges)).sum() / max(1, right_edges.sum()))
    left_bbox = selected.getchannel("A").getbbox()
    right_bbox = candidate.getchannel("A").getbbox()
    if left_bbox is None or right_bbox is None:
        bbox_delta = math.inf
    else:
        bbox_delta = max(abs(left_bbox[index] - right_bbox[index]) for index in range(4))
    passed = (
        alpha_mae <= MAXIMUM_ALPHA_MAE
        and core_iou >= MINIMUM_OPAQUE_CORE_IOU
        and centroid_distance <= MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE
        and left_recall >= MINIMUM_EDGE_RECALL
        and right_recall >= MINIMUM_EDGE_RECALL
        and bbox_delta <= MAXIMUM_ALPHA_BBOX_DELTA
    )
    return {
        "code": EXCEPTION_CODE,
        "selectedFrameRgbaSha256": hashlib.sha256(selected.convert("RGBA").tobytes()).hexdigest().upper(),
        "candidateRgbaSha256": hashlib.sha256(candidate.convert("RGBA").tobytes()).hexdigest().upper(),
        "size": list(selected.size),
        "alphaMeanAbsoluteError": alpha_mae,
        "maximumAlphaMeanAbsoluteError": MAXIMUM_ALPHA_MAE,
        "opaqueCoreAlphaThreshold": 128,
        "opaqueCoreIoU": core_iou,
        "minimumOpaqueCoreIoU": MINIMUM_OPAQUE_CORE_IOU,
        "opaqueCoreCentroidDistance": centroid_distance,
        "maximumOpaqueCoreCentroidDistance": MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE,
        "edgeThreshold": EDGE_THRESHOLD,
        "edgeTolerancePixels": EDGE_TOLERANCE_PIXELS,
        "selectedEdgeRecallWithinTolerance": left_recall,
        "candidateEdgeRecallWithinTolerance": right_recall,
        "minimumEdgeRecall": MINIMUM_EDGE_RECALL,
        "selectedAlphaBoundingBox": list(left_bbox or ()),
        "candidateAlphaBoundingBox": list(right_bbox or ()),
        "maximumAlphaBoundingBoxCoordinateDelta": bbox_delta,
        "allowedMaximumAlphaBoundingBoxCoordinateDelta": MAXIMUM_ALPHA_BBOX_DELTA,
        "passed": passed,
    }


def derive(diagnostic_path: Path, generated_at: str) -> dict[str, Any]:
    diagnostic_controller, human_renderer, alpha_policy, base = load_dependencies()
    diagnostic_report = diagnostic_controller.check(argparse.Namespace(report=str(diagnostic_path)))
    manifest_path = base.verify_artifact_record(
        diagnostic_report["inputs"]["manifest"], "近阈值证据 manifest"
    )
    model_report_path = base.verify_artifact_record(
        diagnostic_report["inputs"]["modelReport"], "近阈值证据 model report"
    )
    base_report_path = base.verify_artifact_record(
        diagnostic_report["inputs"]["baseRenderReport"], "近阈值证据 base render report"
    )
    manifest = base.verify_manifest(manifest_path)
    model_report, _violations, _signatures = human_renderer.load_recovery_model(base, model_report_path)
    base_report = base.load_json(base_report_path)
    base.verify_digest_object(base_report, "renderDigest", "近阈值证据 base render report")
    review_item = next(
        (item for item in manifest["reviewItems"] if item.get("reviewCode") == REVIEW_CODE),
        None,
    )
    if review_item is None:
        raise base.PilotError(f"manifest 缺 reviewCode={REVIEW_CODE}")
    review_key = review_item["reviewKey"]
    candidate = next(
        (row for row in review_item["candidates"] if row.get("candidateId") == CANDIDATE_ID),
        None,
    )
    if candidate is None or candidate.get("frame") != FRAME:
        raise base.PilotError("近阈值例外 candidate/frame 绑定漂移")
    over_limit = [row for row in diagnostic_report["rows"] if not row["primaryPassed"]]
    if (
        len(over_limit) != 2
        or {row["role"] for row in over_limit} != ROLES
        or any(
            row["reviewKey"] != review_key
            or row["candidateId"] != CANDIDATE_ID
            or row["frame"] != FRAME
            for row in over_limit
        )
    ):
        raise base.PilotError("近阈值诊断超限集合不是精确双角色绑定")
    base_rows = {
        (row["role"], row["reviewKey"]): row
        for row in base_report["rows"]
    }
    evidence_rows: list[dict[str, Any]] = []
    maximum_pixels = int(diagnostic_report["controller"]["maxImagePixels"])
    original_max_pixels = Image.MAX_IMAGE_PIXELS
    Image.MAX_IMAGE_PIXELS = maximum_pixels
    try:
        for row in sorted(over_limit, key=lambda value: value["role"]):
            rendered = base_rows.get((row["role"], row["reviewKey"]))
            if rendered is None:
                raise base.PilotError("近阈值诊断行找不到 base render row")
            high_resolution_path = base.verify_artifact_record(
                rendered["sourceHighResolution"], "近阈值 high resolution"
            )
            candidate_path = base.verify_artifact_record(
                rendered["sourceCandidate"], "近阈值 candidate"
            )
            with Image.open(high_resolution_path) as image:
                selected_frame = image.convert("RGBA")
            restored, _scale = base.candidate_from_high_resolution(selected_frame, candidate)
            with Image.open(candidate_path) as image:
                bound_candidate = image.convert("RGBA")
            evidence = correspondence_evidence(restored, bound_candidate)
            primary_mae = float(row["meanAbsoluteError"])
            excess = primary_mae - float(row["limit"])
            admitted = (
                float(row["limit"]) == 8.0
                and 8.0 < primary_mae <= MAXIMUM_MAE
                and 0 < excess <= MAXIMUM_EXCESS
                and evidence["passed"]
            )
            evidence_rows.append({
                "role": row["role"],
                "reviewCode": REVIEW_CODE,
                "reviewKey": review_key,
                "candidateId": CANDIDATE_ID,
                "frame": FRAME,
                "primaryMeanAbsoluteError": primary_mae,
                "globalLimit": float(row["limit"]),
                "excessOverGlobalLimit": excess,
                "maximumAdmittedMeanAbsoluteError": MAXIMUM_MAE,
                "maximumAdmittedExcess": MAXIMUM_EXCESS,
                "sourceCandidate": rendered["sourceCandidate"],
                "sourceHighResolution": rendered["sourceHighResolution"],
                "correspondence": evidence,
                "admittedForHumanReviewCandidateCorrespondence": admitted,
            })
    finally:
        Image.MAX_IMAGE_PIXELS = original_max_pixels
    if not all(row["admittedForHumanReviewCandidateCorrespondence"] for row in evidence_rows):
        raise base.PilotError("近阈值轮廓证据不足，拒绝生成允许证据")
    if (
        len({row["sourceCandidate"]["sha256"] for row in evidence_rows}) != 1
        or len({row["sourceHighResolution"]["sha256"] for row in evidence_rows}) != 1
        or len({row["primaryMeanAbsoluteError"] for row in evidence_rows}) != 1
    ):
        raise base.PilotError("近阈值双角色没有绑定同一像素来源与 MAE")
    report = {
        "schema": SCHEMA,
        "status": "diagnostic_only_correspondence_proven",
        "productionReady": False,
        "humanReviewRequired": True,
        "generatedAt": generated_at,
        "batchId": diagnostic_report["batchId"],
        "sourceDigest": manifest["sourceDigest"],
        "manifestDigest": manifest["manifestDigest"],
        "modelReportDigest": model_report["reportDigest"],
        "diagnosticDigest": diagnostic_report["diagnosticDigest"],
        "inputs": {
            "manifest": base.artifact(manifest_path),
            "modelReport": base.artifact(model_report_path),
            "fidelityDiagnostic": base.artifact(diagnostic_path),
            "diagnosticBaseRenderReport": base.artifact(base_report_path),
        },
        "controller": {
            "source": base.artifact(Path(__file__).resolve()),
            "diagnosticControllerSource": base.artifact(DIAGNOSTIC_CONTROLLER),
            "humanReviewRendererSource": base.artifact(Path(human_renderer.__file__).resolve()),
            "alphaEvidenceSource": base.artifact(Path(alpha_policy.__file__).resolve()),
            "numpy": np.__version__,
            "pillow": Image.__version__ if hasattr(Image, "__version__") else None,
        },
        "exceptionPolicy": {
            "code": EXCEPTION_CODE,
            "binding": {
                "reviewCode": REVIEW_CODE,
                "reviewKey": review_key,
                "candidateId": CANDIDATE_ID,
                "frame": FRAME,
                "roles": sorted(ROLES),
            },
            "maximumMeanAbsoluteError": MAXIMUM_MAE,
            "maximumExcessOverGlobalLimit": MAXIMUM_EXCESS,
            "maximumAlphaMeanAbsoluteError": MAXIMUM_ALPHA_MAE,
            "minimumOpaqueCoreIoU": MINIMUM_OPAQUE_CORE_IOU,
            "maximumOpaqueCoreCentroidDistance": MAXIMUM_OPAQUE_CORE_CENTROID_DISTANCE,
            "edgeThreshold": EDGE_THRESHOLD,
            "edgeTolerancePixels": EDGE_TOLERANCE_PIXELS,
            "minimumBidirectionalEdgeRecall": MINIMUM_EDGE_RECALL,
            "maximumAlphaBoundingBoxCoordinateDelta": MAXIMUM_ALPHA_BBOX_DELTA,
            "scope": "candidate correspondence for human review only; no art acceptance and no global threshold change",
        },
        "rows": evidence_rows,
        "summary": {
            "rows": len(evidence_rows),
            "roles": sorted({row["role"] for row in evidence_rows}),
            "maximumPrimaryMeanAbsoluteError": max(row["primaryMeanAbsoluteError"] for row in evidence_rows),
            "minimumOpaqueCoreIoU": min(row["correspondence"]["opaqueCoreIoU"] for row in evidence_rows),
            "maximumOpaqueCoreCentroidDistance": max(
                row["correspondence"]["opaqueCoreCentroidDistance"] for row in evidence_rows
            ),
            "minimumSelectedEdgeRecall": min(
                row["correspondence"]["selectedEdgeRecallWithinTolerance"] for row in evidence_rows
            ),
            "minimumCandidateEdgeRecall": min(
                row["correspondence"]["candidateEdgeRecallWithinTolerance"] for row in evidence_rows
            ),
        },
        "gates": {
            "exactIdentityCandidateFrameAndRolesBound": True,
            "onlyDiagnosticOverLimitRowsAdmitted": True,
            "nearThresholdBounded": True,
            "strictAlphaAndShapeCorrespondenceProven": True,
            "globalFidelityThresholdUnchanged": True,
            "diagnosticAdmissionIsNotArtAcceptance": True,
            "humanArtAcceptance": False,
            "productionWrites": False,
        },
    }
    report["evidenceDigest"] = base.sha256_bytes(base.stable_bytes(report))
    return report


def build(args: argparse.Namespace) -> dict[str, Any]:
    output = ensure_output(args.output, False)
    diagnostic_path = Path(args.diagnostic_report).resolve()
    report = derive(diagnostic_path, __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def check(args: argparse.Namespace) -> dict[str, Any]:
    output = ensure_output(args.output, True)
    _diagnostic, _human_renderer, _alpha_policy, base = load_dependencies()
    report = json.loads(output.read_text(encoding="utf-8"))
    base.verify_digest_object(report, "evidenceDigest", "近阈值栅格证据")
    if (
        report.get("schema") != SCHEMA
        or report.get("status") != "diagnostic_only_correspondence_proven"
        or report.get("productionReady") is not False
        or report.get("humanReviewRequired") is not True
    ):
        raise base.PilotError("近阈值栅格证据 schema/status 非法")
    for record in [*report["inputs"].values(), *(
        record for key, record in report["controller"].items() if key.endswith("Source") or key == "source"
    )]:
        base.verify_artifact_record(record, "近阈值栅格证据 artifact")
    expected = derive(
        base.verify_artifact_record(report["inputs"]["fidelityDiagnostic"], "近阈值 fidelity diagnostic"),
        report["generatedAt"],
    )
    if base.stable_bytes(expected) != base.stable_bytes(report):
        raise base.PilotError("近阈值栅格证据不可由冻结诊断确定性重放")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--diagnostic-report", required=True)
    build_parser.add_argument("--output", required=True)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = build(args) if args.command == "build" else check(args)
    print(json.dumps({
        "status": "near_threshold_rasterization_evidence_verified" if args.command == "check" else report["status"],
        "evidenceDigest": report["evidenceDigest"],
        "summary": report["summary"],
        "binding": report["exceptionPolicy"]["binding"],
        "humanArtAcceptance": report["gates"]["humanArtAcceptance"],
        "productionWrites": report["gates"]["productionWrites"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
