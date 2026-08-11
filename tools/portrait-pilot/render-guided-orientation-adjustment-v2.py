#!/usr/bin/env python3
"""Apply post-crop orientation to a bounded/fidelity-exception human render."""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
BASE_CONTROLLER = Path(__file__).with_name("render-guided-orientation-adjustment.py").resolve()
GUIDED_RENDER_VERIFIER = Path(__file__).with_name(
    "render-framing-guidance-large-frame-fidelity-v1.py"
).resolve()


def load_base():
    spec = importlib.util.spec_from_file_location("portrait_guided_orientation_base", BASE_CONTROLLER)
    if spec is None or spec.loader is None:
        raise core.PilotError("无法加载历史人工框选后方向变换 controller")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_base()


def verify_guided_report_v2(path: Path) -> tuple[dict[str, object], dict[str, object]]:
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
    return report, check


def render(args: argparse.Namespace) -> None:
    original_verifier = base.verify_guided_report
    original_module_file = base.__file__
    try:
        base.verify_guided_report = verify_guided_report_v2
        base.__file__ = str(Path(__file__).resolve())
        base.render_adjustment(args)
    finally:
        base.verify_guided_report = original_verifier
        base.__file__ = original_module_file


def check(args: argparse.Namespace) -> None:
    original_module_file = base.__file__
    try:
        base.__file__ = str(Path(__file__).resolve())
        base.check_adjustment(args)
    finally:
        base.__file__ = original_module_file


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
        print(f"portrait guided orientation v2 error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
