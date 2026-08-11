#!/usr/bin/env python3
"""Versioned orientation renderer accepting explicit standalone reverse wording."""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import re
import sys
from pathlib import Path


BASE_CONTROLLER = Path(__file__).with_name("render-orientation-adjustment.py").resolve()
EXPLICIT_ORIENTATION_NOTE = r"方向反转|反转|头朝右|头朝左|朝向|翻转"
BASE_ORIENTATION_NOTE = r"方向反转|头朝右|头朝左|朝向"


def load_base():
    spec = importlib.util.spec_from_file_location("portrait_orientation_adjustment_base", BASE_CONTROLLER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载基础控制器：{BASE_CONTROLLER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rewrite_report(base, output: str) -> dict[str, object]:
    report_path = Path(output).resolve() / "orientation-render-report.json"
    report = base.load_json(report_path, "方向变换报告")
    report["renderer"]["controllerSource"] = base.core.artifact(Path(__file__))
    report["renderer"]["baseControllerSource"] = base.core.artifact(BASE_CONTROLLER)
    report["renderer"]["acceptedOrientationNotePattern"] = EXPLICIT_ORIENTATION_NOTE
    report["gates"]["standaloneReverseKeywordAccepted"] = True
    report.pop("reportDigest", None)
    report["reportDigest"] = base.core.sha256_bytes(base.core.stable_bytes(report))
    base.core.write_json(report_path, report)
    return report


def render_adjustment(base, args: argparse.Namespace) -> None:
    original_search = base.re.search

    def compatible_search(pattern, string, flags=0):
        if pattern == BASE_ORIENTATION_NOTE:
            pattern = EXPLICIT_ORIENTATION_NOTE
        return original_search(pattern, string, flags)

    captured = io.StringIO()
    try:
        base.re.search = compatible_search
        with contextlib.redirect_stdout(captured):
            base.render_adjustment(args)
    finally:
        base.re.search = original_search
    report = rewrite_report(base, args.output)
    print(json.dumps({
        "status": "human_orientation_adjustment_v2_checked",
        "report": base.core.repo_rel(Path(args.output).resolve() / "orientation-render-report.json"),
        "reportDigest": report["reportDigest"],
        "rows": len(report["rows"]),
        "standaloneReverseKeywordAccepted": True,
    }, ensure_ascii=False))


def check_adjustment(base, args: argparse.Namespace) -> None:
    report_path = Path(args.output).resolve() / "orientation-render-report.json"
    report = base.load_json(report_path, "方向变换报告")
    renderer = report.get("renderer", {})
    gates = report.get("gates", {})
    if (
        renderer.get("acceptedOrientationNotePattern") != EXPLICIT_ORIENTATION_NOTE
        or gates.get("standaloneReverseKeywordAccepted") is not True
    ):
        raise base.core.PilotError("v2 单独反转关键词契约缺失")
    base.core.verify_artifact_record(renderer["baseControllerSource"], "方向变换 v2 基础控制器")
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        base.check_adjustment(args)
    print(json.dumps({
        "status": "human_orientation_adjustment_v2_verified",
        "reportDigest": report["reportDigest"],
        "rows": len(report["rows"]),
        "standaloneReverseKeywordAccepted": True,
    }, ensure_ascii=False))


def main() -> None:
    base = load_base()
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--source-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.add_argument("--review-key", required=True)
    render_parser.add_argument(
        "--source-role", choices=("proposal", "independent_review"), default="proposal"
    )
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.command == "render":
        render_adjustment(base, args)
    else:
        check_adjustment(base, args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, re.error) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
