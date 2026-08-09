#!/usr/bin/env python3
"""Render a feature report with a process-local, manifest-bounded Pillow pixel limit.

This adapter exists for already-frozen manifests whose vector frame dimensions are
within the declared 16,384px contract but whose total pixel count exceeds Pillow's
generic decompression-bomb default.  It does not relax the manifest's axis bound,
and it records itself in the resulting render report.
"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_PATH = Path(__file__).with_name("prepare_pilot.py")
MAXIMUM_ALLOWED_AXIS = 16_384
SCHEMA = "cf7.portrait-pilot-render-report.v4"


class LargeFrameError(RuntimeError):
    pass


def load_pilot_module():
    spec = importlib.util.spec_from_file_location("cf7_portrait_prepare_pilot", PILOT_PATH)
    if spec is None or spec.loader is None:
        raise LargeFrameError("无法加载 prepare_pilot.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_json(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise LargeFrameError(f"{label} 不是合法 JSON：{error}") from error
    if not isinstance(value, dict):
        raise LargeFrameError(f"{label} 必须是对象")
    return value


def manifest_axis(manifest_path: Path) -> int:
    manifest = read_json(manifest_path, "manifest")
    contract = manifest.get("featureContract", {}).get("highResolutionRender", {})
    try:
        maximum_axis = int(contract["maximumSourceFrameDimension"])
    except (KeyError, TypeError, ValueError) as error:
        raise LargeFrameError("manifest 缺合法 maximumSourceFrameDimension") from error
    if maximum_axis < 1 or maximum_axis > MAXIMUM_ALLOWED_AXIS:
        raise LargeFrameError(
            f"maximumSourceFrameDimension 越出受控范围：{maximum_axis}/{MAXIMUM_ALLOWED_AXIS}"
        )
    return maximum_axis


def decorate_report(module, report_path: Path, maximum_axis: int, original_limit: int | None) -> dict[str, object]:
    report = read_json(report_path, "render report")
    module.verify_digest_object(report, "renderDigest", "render report")
    if report.get("schema") != SCHEMA or report.get("productionReady") is not False:
        raise LargeFrameError("render report schema/productionReady 非法")
    renderer = report.get("renderer")
    if not isinstance(renderer, dict):
        raise LargeFrameError("render report 缺 renderer")
    if int(renderer.get("maximumSourceFrameDimension", -1)) != maximum_axis:
        raise LargeFrameError("render report 与 manifest 最大帧轴不一致")
    if "boundedLargeFrameDecode" in renderer:
        raise LargeFrameError("render report 已存在 boundedLargeFrameDecode")
    renderer["boundedLargeFrameDecode"] = {
        "controllerSource": module.artifact(Path(__file__).resolve()),
        "maximumSourceFrameDimension": maximum_axis,
        "maximumDecodedPixels": maximum_axis * maximum_axis,
        "originalPillowMaxImagePixels": original_limit,
        "scope": "this render process only",
        "unboundedDecode": False,
    }
    report.pop("renderDigest", None)
    report["renderDigest"] = module.sha256_bytes(module.stable_bytes(report))
    module.write_json(report_path, report)
    return report


def verify_report(module, report_path: Path) -> dict[str, object]:
    report = read_json(report_path, "render report")
    module.verify_digest_object(report, "renderDigest", "render report")
    if report.get("schema") != SCHEMA or report.get("productionReady") is not False:
        raise LargeFrameError("render report schema/productionReady 非法")
    bounded = report.get("renderer", {}).get("boundedLargeFrameDecode")
    if not isinstance(bounded, dict) or bounded.get("unboundedDecode") is not False:
        raise LargeFrameError("render report 缺受控大帧解码闭包")
    maximum_axis = int(bounded.get("maximumSourceFrameDimension", -1))
    if maximum_axis < 1 or maximum_axis > MAXIMUM_ALLOWED_AXIS:
        raise LargeFrameError("render report 最大帧轴越界")
    if bounded.get("maximumDecodedPixels") != maximum_axis * maximum_axis:
        raise LargeFrameError("render report 像素上限不闭合")
    module.verify_artifact_record(bounded.get("controllerSource"), "大帧渲染控制器")
    for run in report.get("highResolutionRuns", []):
        for output in run.get("outputs", []):
            module.verify_artifact_record(output, "高分辨率帧")
    return report


def render(args: argparse.Namespace) -> dict[str, object]:
    manifest_path = Path(args.manifest).resolve()
    model_report_path = Path(args.model_report).resolve()
    maximum_axis = manifest_axis(manifest_path)
    module = load_pilot_module()
    output_dir = manifest_path.parent
    report_path = output_dir / "render-report.json"
    if report_path.exists():
        raise LargeFrameError("render-report.json 已存在，禁止覆盖")
    original_limit = Image.MAX_IMAGE_PIXELS
    try:
        Image.MAX_IMAGE_PIXELS = maximum_axis * maximum_axis
        with contextlib.redirect_stdout(io.StringIO()):
            module.render(argparse.Namespace(manifest=str(manifest_path), model_report=str(model_report_path)))
    finally:
        Image.MAX_IMAGE_PIXELS = original_limit
    if not report_path.is_file():
        raise LargeFrameError("底层渲染未生成 render-report.json")
    return decorate_report(module, report_path, maximum_axis, original_limit)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    commands = result.add_subparsers(dest="command", required=True)
    render_parser = commands.add_parser("render")
    render_parser.add_argument("--manifest", required=True)
    render_parser.add_argument("--model-report", required=True)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--report", required=True)
    return result


def main() -> None:
    args = parser().parse_args()
    module = load_pilot_module()
    if args.command == "render":
        report = render(args)
        status = report["status"]
    else:
        report = verify_report(module, Path(args.report).resolve())
        status = "bounded_large_frame_render_verified"
    print(json.dumps({
        "status": status,
        "renderDigest": report["renderDigest"],
        "rows": len(report.get("rows", [])),
        "renderAttempt": report.get("renderAttempt"),
        "maximumDecodedPixels": report["renderer"]["boundedLargeFrameDecode"]["maximumDecodedPixels"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (LargeFrameError, RuntimeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=__import__("sys").stderr)
        raise SystemExit(1)
