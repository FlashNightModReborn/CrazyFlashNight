#!/usr/bin/env python3
"""Render frozen human framing guidance with a manifest-bounded Pillow limit."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
BASE_RENDERER = Path(__file__).with_name("render-framing-guidance.py").resolve()
MAXIMUM_SUPPORTED_FRAME_DIMENSION = 16_384
SAFETY_SCHEMA = "cf7.portrait-pilot-human-framing-pillow-large-frame-safety.v1"


def load_base_renderer():
    spec = importlib.util.spec_from_file_location("portrait_framing_guidance_base", BASE_RENDERER)
    if spec is None or spec.loader is None:
        raise core.PilotError("无法加载历史人工框选 renderer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_base_renderer()


def bounded_pixel_limit(dataset: dict[str, object]) -> tuple[int, int]:
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


def safety_record(maximum_dimension: int, maximum_pixels: int) -> dict[str, object]:
    return {
        "schema": SAFETY_SCHEMA,
        "maxImagePixels": maximum_pixels,
        "pillowHardErrorAbovePixels": maximum_pixels * 2,
        "manifestMaximumSourceFrameDimension": maximum_dimension,
        "boundedByManifest": True,
        "unlimitedRasterDecode": False,
    }


def dataset_for_render(guidance_batch: str) -> dict[str, object]:
    guidance_root = base.ensure_pilot_child(Path(guidance_batch), "框选指导批次", allow_existing=True)
    dataset, _, _, _ = base.verify_guidance_receipt(guidance_root)
    return dataset


def dataset_for_check(report: dict[str, object]) -> dict[str, object]:
    record = report.get("inputs", {}).get("guidanceData")
    path = core.verify_artifact_record(record, "人工框选 guidance data")
    dataset = core.load_json(path)
    if not isinstance(dataset, dict):
        raise core.PilotError("人工框选 guidance data 顶层必须是对象")
    return dataset


def rebound_report(report_path: Path, maximum_dimension: int, maximum_pixels: int) -> dict[str, object]:
    report = base.load_json(report_path, "人工框选渲染报告")
    report.get("renderer", {})["pillowSafety"] = safety_record(maximum_dimension, maximum_pixels)
    report.pop("reportDigest", None)
    report["reportDigest"] = core.sha256_bytes(core.stable_bytes(report))
    core.write_json(report_path, report)
    return report


def render(args: argparse.Namespace) -> None:
    dataset = dataset_for_render(args.guidance_batch)
    maximum_dimension, maximum_pixels = bounded_pixel_limit(dataset)
    Image.MAX_IMAGE_PIXELS = maximum_pixels

    original_module_file = base.__file__
    try:
        base.__file__ = str(Path(__file__).resolve())
        with contextlib.redirect_stdout(io.StringIO()):
            base.render_guidance(args)
    finally:
        base.__file__ = original_module_file

    report_path = Path(args.output).resolve() / "human-framing-render-report.json"
    report = rebound_report(report_path, maximum_dimension, maximum_pixels)
    print(
        json.dumps(
            {
                "status": "human_guided_automated_checked_with_bounded_large_frame",
                "report": core.repo_rel(report_path),
                "reportDigest": report["reportDigest"],
                "rows": len(report["rows"]),
                "maximumFidelityMeanAbsoluteError": report["fidelitySummary"]["maximumMeanAbsoluteError"],
                "maxImagePixels": maximum_pixels,
            },
            ensure_ascii=False,
        )
    )


def check(args: argparse.Namespace) -> None:
    report_path = Path(args.output).resolve() / "human-framing-render-report.json"
    report = base.load_json(report_path, "人工框选渲染报告")
    dataset = dataset_for_check(report)
    maximum_dimension, maximum_pixels = bounded_pixel_limit(dataset)
    expected_safety = safety_record(maximum_dimension, maximum_pixels)
    if report.get("renderer", {}).get("pillowSafety") != expected_safety:
        raise core.PilotError("人工框选 Pillow 大帧安全合同不闭合")

    original_module_file = base.__file__
    try:
        base.__file__ = str(Path(__file__).resolve())
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            base.check_render(args)
    finally:
        base.__file__ = original_module_file
    result = json.loads(captured.getvalue().strip().splitlines()[-1])
    print(
        json.dumps(
            {
                "status": "human_framing_bounded_large_frame_render_verified",
                "reportDigest": report["reportDigest"],
                "rows": len(report["rows"]),
                "artifactCount": result["artifactCount"],
                "maxImagePixels": maximum_pixels,
            },
            ensure_ascii=False,
        )
    )


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
        print(f"[portrait-framing-large-frame-render] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
