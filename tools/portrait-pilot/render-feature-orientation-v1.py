#!/usr/bin/env python3
"""Render feature-localization selections and apply model-decided horizontal orientation."""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageOps


BASE_CONTROLLER = Path(__file__).with_name("prepare_pilot.py").resolve()
EXPECTED_BASE_SHA256 = "41B9BAADB5936F0E916381167048EFE86355F9869974FF95453D565BB3E25B5A"
RESULT_SCHEMA = "cf7.portrait-pilot-feature-selection-orientation.v2"
ORIENTATION_ACTIONS = {"keep", "flip_x"}


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load_base():
    if file_sha256(BASE_CONTROLLER) != EXPECTED_BASE_SHA256:
        raise RuntimeError("基础头像渲染控制器字节已漂移；拒绝运行未经复核的方向渲染包装器")
    spec = importlib.util.spec_from_file_location("portrait_prepare_orientation_base", BASE_CONTROLLER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载基础头像渲染控制器：{BASE_CONTROLLER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def orientation_rows(base, model_report_path: Path) -> tuple[dict[str, object], dict[tuple[str, str], dict[str, object]]]:
    model_report = base.load_json(model_report_path)
    base.verify_digest_object(model_report, "reportDigest", "方向定位模型报告")
    decisions: dict[tuple[str, str], dict[str, object]] = {}
    roles: set[str] = set()
    for run in model_report.get("runs", []):
        role = run.get("role")
        if role not in {"proposal", "independent_review"}:
            raise base.PilotError(f"方向定位模型角色非法：{role}")
        roles.add(role)
        result = run.get("result", {})
        if result.get("schema") != RESULT_SCHEMA:
            raise base.PilotError(f"方向定位结果 schema 非 v2：{role}")
        for selection in result.get("selections", []):
            review_key = selection.get("reviewKey")
            action = selection.get("orientationAction")
            reason = selection.get("orientationReason")
            confidence = selection.get("orientationConfidence")
            key = (str(role), str(review_key))
            if not isinstance(review_key, str) or key in decisions:
                raise base.PilotError("方向定位 reviewKey 缺失或重复")
            if action not in ORIENTATION_ACTIONS:
                raise base.PilotError(f"方向定位 action 非法：{review_key}={action}")
            if not isinstance(reason, str) or not reason.strip() or len(reason) > 160:
                raise base.PilotError(f"方向定位理由为空或过长：{review_key}")
            if not isinstance(confidence, (int, float)) or not math.isfinite(float(confidence)) or not 0 <= float(confidence) <= 1:
                raise base.PilotError(f"方向定位置信度非法：{review_key}")
            decisions[key] = {
                "action": action,
                "reason": reason,
                "confidence": float(confidence),
            }
    if roles != {"proposal", "independent_review"} or not decisions:
        raise base.PilotError("方向定位 A/B 角色或决定为空")
    return model_report, decisions


def apply_orientation(image: Image.Image, action: str) -> Image.Image:
    if action == "keep":
        return image
    if action == "flip_x":
        return ImageOps.mirror(image)
    raise ValueError(f"不支持的方向动作：{action}")


def render_with_orientation(base, args: argparse.Namespace) -> dict[str, object]:
    manifest_path = Path(args.manifest).resolve()
    model_report_path = Path(args.model_report).resolve()
    model_report, decisions = orientation_rows(base, model_report_path)
    manifest = base.verify_manifest(manifest_path)
    eligible = sum(not item.get("blocked") for item in manifest.get("reviewItems", []))
    if len(decisions) != eligible * 2:
        raise base.PilotError(
            f"方向定位决定数不闭合：expected={eligible * 2} actual={len(decisions)}"
        )

    original_compute = base.compute_feature_view_box
    original_crop = base.crop_high_resolution_selection
    orientation_by_geometry: dict[int, dict[str, object]] = {}

    def compute_with_orientation(candidate, selection, geometry_contract, intent_policy=None):
        geometry = original_compute(candidate, selection, geometry_contract, intent_policy)
        orientation_by_geometry[id(geometry)] = {
            "action": selection["orientationAction"],
            "reason": selection["orientationReason"],
            "confidence": float(selection["orientationConfidence"]),
        }
        return geometry

    def crop_with_orientation(high_resolution, candidate, geometry, source_scale, target_size, minimum_size):
        retained, mapping = original_crop(
            high_resolution,
            candidate,
            geometry,
            source_scale,
            target_size,
            minimum_size,
        )
        decision = orientation_by_geometry.get(id(geometry))
        if decision is None:
            raise base.PilotError(f"方向定位几何映射缺失：{candidate.get('candidateId')}")
        retained = apply_orientation(retained, str(decision["action"]))
        mapping = dict(mapping)
        mapping.update({
            "orientationAction": decision["action"],
            "orientationApplied": decision["action"] == "flip_x",
            "orientationOrder": "crop_then_flip_x_before_output_pyramid",
        })
        return retained, mapping

    captured = io.StringIO()
    try:
        base.compute_feature_view_box = compute_with_orientation
        base.crop_high_resolution_selection = crop_with_orientation
        with contextlib.redirect_stdout(captured):
            base.render(args)
    finally:
        base.compute_feature_view_box = original_compute
        base.crop_high_resolution_selection = original_crop

    report_path = manifest_path.parent / "render-report.json"
    report = base.load_json(report_path)
    if report.get("schema") != "cf7.portrait-pilot-render-report.v4":
        raise base.PilotError("方向渲染只接受特征渲染报告 v4")
    for row in report.get("rows", []):
        key = (str(row.get("role")), str(row.get("reviewKey")))
        decision = decisions.get(key)
        if decision is None:
            raise base.PilotError(f"方向渲染行找不到模型决定：{key}")
        mapping = row.get("cropMapping", {})
        if (
            mapping.get("orientationAction") != decision["action"]
            or mapping.get("orientationApplied") is not (decision["action"] == "flip_x")
        ):
            raise base.PilotError(f"方向渲染动作未消费：{key}")
        row["orientationAction"] = decision["action"]
        row["orientationReason"] = decision["reason"]
        row["orientationConfidence"] = decision["confidence"]

    report["renderer"]["baseControllerSource"] = base.artifact(BASE_CONTROLLER)
    report["renderer"]["controllerSource"] = base.artifact(Path(__file__).resolve())
    report["renderer"]["modelReportArtifact"] = base.artifact(model_report_path)
    report["renderer"]["orientationPolicy"] = {
        "version": "canonical_portrait_right_v1",
        "actions": ["keep", "flip_x"],
        "coordinateSpace": "original selected candidate",
        "operationOrder": "crop_then_flip_x_before_512_80_48_32_webp",
        "canonicalDirection": "right",
    }
    report["orientationSummary"] = {
        "rows": len(report["rows"]),
        "flipX": sum(row["orientationAction"] == "flip_x" for row in report["rows"]),
        "keep": sum(row["orientationAction"] == "keep" for row in report["rows"]),
        "proposalIndependentAgreement": sum(
            decisions[("proposal", key)]["action"] == decisions[("independent_review", key)]["action"]
            for key in sorted({review_key for _role, review_key in decisions})
        ),
        "identities": eligible,
    }
    report["gates"].update({
        "modelOrientationDecisionClosed": True,
        "canonicalPortraitDirectionRight": True,
        "orientationAppliedAfterOriginalSpaceCrop": True,
        "orientationAppliedBeforeOutputPyramid": True,
        "historicalControllerPreserved": True,
    })
    report.pop("renderDigest", None)
    report["renderDigest"] = base.sha256_bytes(base.stable_bytes(report))
    base.write_json(report_path, report)
    return report


def verify_render(base, args: argparse.Namespace) -> dict[str, object]:
    manifest_path = Path(args.manifest).resolve()
    model_report_path = Path(args.model_report).resolve()
    model_report, decisions = orientation_rows(base, model_report_path)
    manifest = base.verify_manifest(manifest_path)
    report_path = manifest_path.parent / "render-report.json"
    report = base.load_json(report_path)
    base.verify_digest_object(report, "renderDigest", "方向渲染报告")
    if (
        report.get("schema") != "cf7.portrait-pilot-render-report.v4"
        or report.get("manifestDigest") != manifest.get("manifestDigest")
        or report.get("modelReportDigest") != model_report.get("reportDigest")
    ):
        raise base.PilotError("方向渲染报告与 manifest/model report 不闭合")
    renderer = report.get("renderer", {})
    policy = renderer.get("orientationPolicy", {})
    if (
        base.verify_artifact_record(renderer.get("controllerSource"), "方向渲染控制器") != Path(__file__).resolve()
        or base.verify_artifact_record(renderer.get("baseControllerSource"), "方向渲染基础控制器") != BASE_CONTROLLER
        or base.verify_artifact_record(renderer.get("modelReportArtifact"), "方向定位模型报告") != model_report_path
        or policy.get("version") != "canonical_portrait_right_v1"
        or policy.get("canonicalDirection") != "right"
    ):
        raise base.PilotError("方向渲染控制器或策略闭包漂移")
    expected_count = sum(not item.get("blocked") for item in manifest.get("reviewItems", [])) * 2
    rows = report.get("rows", [])
    if len(rows) != expected_count or len(decisions) != expected_count:
        raise base.PilotError("方向渲染行数不闭合")
    for row in rows:
        key = (str(row.get("role")), str(row.get("reviewKey")))
        decision = decisions.get(key)
        if decision is None or any(
            row.get(field) != decision[source]
            for field, source in (
                ("orientationAction", "action"),
                ("orientationReason", "reason"),
                ("orientationConfidence", "confidence"),
            )
        ):
            raise base.PilotError(f"方向渲染行与模型决定不一致：{key}")
        mapping = row.get("cropMapping", {})
        if (
            mapping.get("orientationAction") != decision["action"]
            or mapping.get("orientationApplied") is not (decision["action"] == "flip_x")
            or mapping.get("orientationOrder") != "crop_then_flip_x_before_output_pyramid"
        ):
            raise base.PilotError(f"方向渲染顺序未闭合：{key}")
        for field in ("sourceSupersample", "master", "webp80Lossless"):
            base.verify_artifact_record(row[field], f"方向渲染 {field} {key}")
        for size in ("80", "48", "32"):
            base.verify_artifact_record(row["previews"][size], f"方向渲染 preview-{size} {key}")
        master_path = base.verify_artifact_record(row["master"], f"方向渲染 master {key}")
        with Image.open(master_path) as image:
            rgba = image.convert("RGBA")
            if rgba.size != (512, 512) or rgba.getchannel("A").getbbox() is None:
                raise base.PilotError(f"方向渲染 master 尺寸或 alpha 非法：{key}")
    gates = report.get("gates", {})
    if not all(gates.get(field) is True for field in (
        "modelOrientationDecisionClosed",
        "canonicalPortraitDirectionRight",
        "orientationAppliedAfterOriginalSpaceCrop",
        "orientationAppliedBeforeOutputPyramid",
        "historicalControllerPreserved",
    )):
        raise base.PilotError("方向渲染 gates 未闭合")
    return report


def self_test() -> None:
    image = Image.new("RGBA", (3, 1), (0, 0, 0, 0))
    image.putpixel((0, 0), (255, 0, 0, 255))
    image.putpixel((2, 0), (0, 0, 255, 255))
    kept = apply_orientation(image, "keep")
    flipped = apply_orientation(image, "flip_x")
    if kept.getpixel((0, 0)) != (255, 0, 0, 255) or flipped.getpixel((0, 0)) != (0, 0, 255, 255):
        raise RuntimeError("方向渲染自检失败")
    print(json.dumps({
        "status": "portrait_orientation_renderer_self_tested",
        "canonicalDirection": "right",
        "cropCoordinateSpace": "original",
        "operation": "crop_then_flip_x",
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
    base = load_base()
    if args.command == "render":
        report = render_with_orientation(base, args)
        print(json.dumps({
            "status": "model_oriented_automated_checked",
            "report": base.repo_rel(Path(args.manifest).resolve().parent / "render-report.json"),
            "renderDigest": report["renderDigest"],
            "rows": len(report["rows"]),
            "flipX": report["orientationSummary"]["flipX"],
        }, ensure_ascii=False))
    else:
        report = verify_render(base, args)
        print(json.dumps({
            "status": "model_oriented_render_verified",
            "renderDigest": report["renderDigest"],
            "rows": len(report["rows"]),
            "flipX": report["orientationSummary"]["flipX"],
        }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
