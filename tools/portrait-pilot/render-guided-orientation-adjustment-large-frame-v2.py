#!/usr/bin/env python3
"""Apply explicit post-crop flips to bounded large-frame human renders."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import re
import subprocess
import sys
from pathlib import Path

import prepare_pilot as core


BASE_CONTROLLER = Path(__file__).with_name("render-guided-orientation-adjustment.py").resolve()
GUIDED_RENDER_VERIFIER = Path(__file__).with_name(
    "render-framing-guidance-large-frame-v1.py"
).resolve()
EXPLICIT_ORIENTATION_NOTE = re.compile(r"方向反转|反转|头朝右|头朝左|朝向|翻转")


def load_base():
    spec = importlib.util.spec_from_file_location(
        "portrait_guided_orientation_large_frame_v2_base", BASE_CONTROLLER
    )
    if spec is None or spec.loader is None:
        raise core.PilotError("无法加载人工框选后方向变换 controller")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_base()


def verify_bounded_large_frame_report(path: Path) -> tuple[dict[str, object], dict[str, object]]:
    if path.name != "human-framing-render-report.json":
        raise core.PilotError("人工框选渲染必须指向批次目录或 human-framing-render-report.json")
    report = base.load_json(path, "human framing render report")
    check = base.run_json(
        [
            sys.executable,
            str(GUIDED_RENDER_VERIFIER),
            "check",
            "--output",
            core.repo_rel(path.parent),
        ],
        "有界大帧人工框选渲染验证",
    )
    if check.get("reportDigest") != report.get("reportDigest"):
        raise core.PilotError("人工框选渲染 verifier 与 reportDigest 不一致")
    if check.get("status") != "human_framing_bounded_large_frame_render_verified":
        raise core.PilotError("人工框选渲染 verifier 状态非法")
    return report, check


def bind_base_controller(report_path: Path) -> dict[str, object]:
    report = base.load_json(report_path, "人工框选后方向变换报告")
    renderer = report.get("renderer")
    if not isinstance(renderer, dict):
        raise core.PilotError("人工框选后方向变换报告缺 renderer")
    renderer["baseControllerSource"] = core.artifact(BASE_CONTROLLER)
    report.pop("reportDigest", None)
    report["reportDigest"] = core.sha256_bytes(core.stable_bytes(report))
    core.write_json(report_path, report)
    return report


def render(args: argparse.Namespace) -> None:
    original_verifier = base.verify_guided_report
    original_module_file = base.__file__
    original_orientation_note = base.ORIENTATION_NOTE
    try:
        base.verify_guided_report = verify_bounded_large_frame_report
        base.ORIENTATION_NOTE = EXPLICIT_ORIENTATION_NOTE
        base.__file__ = str(Path(__file__).resolve())
        with contextlib.redirect_stdout(io.StringIO()):
            base.render_adjustment(args)
    finally:
        base.verify_guided_report = original_verifier
        base.ORIENTATION_NOTE = original_orientation_note
        base.__file__ = original_module_file

    report_path = Path(args.output).resolve() / base.REPORT_NAME
    report = bind_base_controller(report_path)
    print(
        json.dumps(
            {
                "status": "human_guided_orientation_adjustment_large_frame_checked",
                "report": core.repo_rel(report_path),
                "reportDigest": report["reportDigest"],
                "rows": len(report["rows"]),
                "fidelityMeanAbsoluteError": report["rows"][0]["fidelityComparison"][
                    "meanAbsoluteError"
                ],
            },
            ensure_ascii=False,
        )
    )


def check(args: argparse.Namespace) -> None:
    report_path = Path(args.output).resolve() / base.REPORT_NAME
    report = base.load_json(report_path, "人工框选后方向变换报告")
    expected_base = core.artifact(BASE_CONTROLLER)
    if report.get("renderer", {}).get("baseControllerSource") != expected_base:
        raise core.PilotError("人工框选后方向变换没有绑定复用的基础 controller")

    original_module_file = base.__file__
    captured = io.StringIO()
    try:
        base.__file__ = str(Path(__file__).resolve())
        with contextlib.redirect_stdout(captured):
            base.check_adjustment(args)
    finally:
        base.__file__ = original_module_file
    result = json.loads(captured.getvalue().strip().splitlines()[-1])
    result["status"] = "human_guided_orientation_adjustment_large_frame_verified"
    result["artifactCount"] = int(result["artifactCount"]) + 1
    print(json.dumps(result, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    render_parser = commands.add_parser("render")
    render_parser.add_argument("--review-batch", required=True)
    render_parser.add_argument("--guidance-batch", required=True)
    render_parser.add_argument("--guided-render", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.add_argument("--review-key", required=True)
    render_parser.set_defaults(handler=render)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.set_defaults(handler=check)
    args = parser.parse_args()
    try:
        args.handler(args)
    except (core.PilotError, subprocess.SubprocessError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"portrait guided orientation large-frame v2 error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
