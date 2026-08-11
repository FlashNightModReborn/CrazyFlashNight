#!/usr/bin/env python3
"""Render an orientation-aware portrait in a fresh, manifest-bounded large-frame workspace."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp/portrait-pilot"
ORIENTATION_CONTROLLER = Path(__file__).with_name("render-feature-orientation-v1.py").resolve()
EXPECTED_ORIENTATION_SHA256 = "F9C70E63B100AD132AC76486B3293A34407A305A998D5CA493ECD54B3722D4BA"
MAXIMUM_ALLOWED_AXIS = 16_384


class RetryError(RuntimeError):
    pass


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load_orientation():
    if file_sha256(ORIENTATION_CONTROLLER) != EXPECTED_ORIENTATION_SHA256:
        raise RetryError("方向渲染控制器字节已漂移")
    spec = importlib.util.spec_from_file_location("portrait_orientation_large_retry_base", ORIENTATION_CONTROLLER)
    if spec is None or spec.loader is None:
        raise RetryError("无法加载方向渲染控制器")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_json(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RetryError(f"{label} 不是合法 JSON：{error}") from error
    if not isinstance(value, dict):
        raise RetryError(f"{label} 必须是对象")
    return value


def pilot_path(value: str, label: str, must_exist: bool) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise RetryError(f"{label} 必须位于 tmp/portrait-pilot 下") from error
    if must_exist and not path.exists():
        raise RetryError(f"{label} 不存在：{path}")
    if not must_exist and path.exists():
        raise RetryError(f"{label} 已存在，禁止覆盖：{path}")
    return path


def manifest_axis(manifest: dict[str, object]) -> int:
    try:
        maximum_axis = int(manifest["featureContract"]["highResolutionRender"]["maximumSourceFrameDimension"])
    except (KeyError, TypeError, ValueError) as error:
        raise RetryError("manifest 缺合法 maximumSourceFrameDimension") from error
    if maximum_axis < 1 or maximum_axis > MAXIMUM_ALLOWED_AXIS:
        raise RetryError(f"maximumSourceFrameDimension 越界：{maximum_axis}")
    return maximum_axis


def decorate(base, report_path: Path, maximum_axis: int, original_limit: int | None, source_manifest: Path, source_model: Path) -> dict[str, object]:
    report = read_json(report_path, "方向 render report")
    base.verify_digest_object(report, "renderDigest", "方向 render report")
    renderer = report.get("renderer")
    if not isinstance(renderer, dict) or "boundedLargeFrameDecode" in renderer:
        raise RetryError("方向 render report renderer 非法或已装饰")
    renderer["boundedLargeFrameDecode"] = {
        "controllerSource": base.artifact(Path(__file__).resolve()),
        "maximumSourceFrameDimension": maximum_axis,
        "maximumDecodedPixels": maximum_axis * maximum_axis,
        "originalPillowMaxImagePixels": original_limit,
        "scope": "fresh isolated retry render process only",
        "unboundedDecode": False,
    }
    renderer["isolatedRetry"] = {
        "reason": "standard orientation renderer exceeded Pillow default pixel threshold before report creation",
        "sourceManifest": base.artifact(source_manifest),
        "sourceModelReport": base.artifact(source_model),
        "copiedInputsByteIdentical": True,
        "sourceBatchMutated": False,
    }
    report["gates"]["boundedLargeFrameDecode"] = True
    report["gates"]["isolatedRetryPreservedSourceBatch"] = True
    report.pop("renderDigest", None)
    report["renderDigest"] = base.sha256_bytes(base.stable_bytes(report))
    base.write_json(report_path, report)
    return report


def render(options: argparse.Namespace) -> dict[str, object]:
    orientation = load_orientation()
    base = orientation.load_base()
    source_manifest = pilot_path(options.manifest, "来源 manifest", must_exist=True)
    source_model = pilot_path(options.model_report, "来源 model report", must_exist=True)
    if not source_manifest.is_file() or not source_model.is_file():
        raise RetryError("来源 manifest/model report 必须是文件")
    manifest = base.verify_manifest(source_manifest)
    model_report = read_json(source_model, "model report")
    base.verify_digest_object(model_report, "reportDigest", "model report")
    if model_report.get("sourceDigest") != manifest.get("sourceDigest"):
        raise RetryError("manifest/model report sourceDigest 不一致")
    output_root = pilot_path(options.output, "输出目录", must_exist=False)
    output_root.mkdir(parents=False)
    copied_manifest = output_root / "candidate-manifest.json"
    copied_model = output_root / "model-report.json"
    shutil.copy2(source_manifest, copied_manifest)
    shutil.copy2(source_model, copied_model)
    if file_sha256(copied_manifest) != file_sha256(source_manifest) or file_sha256(copied_model) != file_sha256(source_model):
        raise RetryError("隔离重试输入复制不一致")

    maximum_axis = manifest_axis(manifest)
    original_limit = Image.MAX_IMAGE_PIXELS
    try:
        Image.MAX_IMAGE_PIXELS = maximum_axis * maximum_axis
        report = orientation.render_with_orientation(
            base,
            argparse.Namespace(manifest=str(copied_manifest), model_report=str(copied_model)),
        )
    finally:
        Image.MAX_IMAGE_PIXELS = original_limit
    report_path = output_root / "render-report.json"
    if not report_path.is_file() or report.get("renderDigest") is None:
        raise RetryError("隔离大帧方向渲染未生成 report")
    return decorate(base, report_path, maximum_axis, original_limit, source_manifest, source_model)


def check(options: argparse.Namespace) -> dict[str, object]:
    orientation = load_orientation()
    base = orientation.load_base()
    output_root = pilot_path(options.output, "输出目录", must_exist=True)
    manifest_path = output_root / "candidate-manifest.json"
    model_path = output_root / "model-report.json"
    report = orientation.verify_render(
        base,
        argparse.Namespace(manifest=str(manifest_path), model_report=str(model_path)),
    )
    bounded = report.get("renderer", {}).get("boundedLargeFrameDecode")
    retry = report.get("renderer", {}).get("isolatedRetry")
    if not isinstance(bounded, dict) or not isinstance(retry, dict):
        raise RetryError("render report 缺大帧或隔离重试闭包")
    maximum_axis = int(bounded.get("maximumSourceFrameDimension", -1))
    if (
        maximum_axis < 1
        or maximum_axis > MAXIMUM_ALLOWED_AXIS
        or bounded.get("maximumDecodedPixels") != maximum_axis * maximum_axis
        or bounded.get("unboundedDecode") is not False
        or retry.get("copiedInputsByteIdentical") is not True
        or retry.get("sourceBatchMutated") is not False
    ):
        raise RetryError("大帧隔离重试边界不闭合")
    base.verify_artifact_record(bounded.get("controllerSource"), "大帧方向重试控制器")
    base.verify_artifact_record(retry.get("sourceManifest"), "来源 manifest")
    base.verify_artifact_record(retry.get("sourceModelReport"), "来源 model report")
    return report


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    render_parser = commands.add_parser("render")
    render_parser.add_argument("--manifest", required=True)
    render_parser.add_argument("--model-report", required=True)
    render_parser.add_argument("--output", required=True)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--output", required=True)
    return result


def main() -> None:
    options = parser().parse_args()
    report = render(options) if options.command == "render" else check(options)
    print(json.dumps({
        "status": "model_oriented_bounded_large_frame_checked" if options.command == "check" else "model_oriented_bounded_large_frame_rendered",
        "renderDigest": report["renderDigest"],
        "rows": len(report.get("rows", [])),
        "flipX": report.get("orientationSummary", {}).get("flipX"),
        "maximumDecodedPixels": report["renderer"]["boundedLargeFrameDecode"]["maximumDecodedPixels"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RetryError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
