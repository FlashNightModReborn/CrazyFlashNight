#!/usr/bin/env python
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import time
import zlib
from pathlib import Path
from typing import Any


def load_bake_tool(project_root: Path):
    tools_dir = project_root / "tools"
    sys.path.insert(0, str(tools_dir))
    spec = importlib.util.spec_from_file_location(
        "bake_icons_offline_for_promotion",
        tools_dir / "bake-icons-offline.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load tools/bake-icons-offline.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["bake_icons_offline_for_promotion"] = module
    spec.loader.exec_module(module)
    return module


def parse_args() -> argparse.Namespace:
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description=(
            "Promote audited animated icon candidates one-by-one through bake-icons-offline.py, "
            "with per-candidate reports and a compact summary."
        )
    )
    parser.add_argument(
        "--candidate-report",
        default=str(project_root / "tmp" / "icon-animation-structure-audit.json"),
        help="Structure audit report containing animationStructureCandidates.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(project_root / "tmp" / "icon-animation-candidate-promotion" / "icons"),
        help="Icon output directory. Use launcher/web/icons for production promotion.",
    )
    parser.add_argument(
        "--tmp-root",
        default=str(project_root / "tmp" / "icon-animation-candidate-promotion" / "ffdec"),
        help="Root directory for per-candidate FFDec temporary output.",
    )
    parser.add_argument(
        "--report",
        default=str(project_root / "tmp" / "icon-animation-candidate-promotion" / "summary.json"),
        help="Summary report path.",
    )
    parser.add_argument("--scope", choices=["items", "skills", "all"], default="all")
    parser.add_argument("--name", action="append", default=[], help="Only promote this icon name. May repeat.")
    parser.add_argument("--limit", type=int, default=0, help="Limit promoted candidates after filtering.")
    parser.add_argument(
        "--strategy",
        choices=["all", "direct-layered", "single-child"],
        default="all",
        help="Candidate strategy filter.",
    )
    parser.add_argument(
        "--max-source-frames",
        type=int,
        default=32,
        help="Skip candidates whose longest animated descendant exceeds this frame count. Use 0 to disable.",
    )
    parser.add_argument(
        "--max-animated-icon-bytes",
        type=int,
        default=1_500_000,
        help="Per-icon animated byte budget passed to bake-icons-offline.py. Use 0 to disable.",
    )
    parser.add_argument(
        "--ffdec-timeout-seconds",
        type=int,
        default=120,
        help="Timeout for each FFDec subprocess inside bake-icons-offline.py.",
    )
    parser.add_argument(
        "--candidate-timeout-seconds",
        type=int,
        default=240,
        help="Outer timeout for each candidate bake command. Use 0 to disable.",
    )
    parser.add_argument("--keep-tmp", action="store_true", help="Keep per-candidate FFDec temporary output.")
    parser.add_argument("--dry-run", action="store_true", help="Pass --dry-run to each candidate bake.")
    return parser.parse_args()


def resolve_path(path_text: str, project_root: Path) -> Path:
    path = Path(path_text)
    if not path.is_absolute():
        path = project_root / path
    return path


def normalized_names(raw_names: list[str]) -> set[str]:
    names: set[str] = set()
    for raw in raw_names:
        for part in raw.split(","):
            name = part.strip()
            if name:
                names.add(name)
    return names


def safe_key(value: str) -> str:
    return f"{zlib.crc32(value.encode('utf-8')) & 0xFFFFFFFF:08x}"


def selected_candidates(
    bake_tool: Any,
    report_path: Path,
    *,
    strategy: str,
    max_source_frames: int,
    names: set[str],
    limit: int,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    data = json.loads(report_path.read_text(encoding="utf-8-sig"))
    candidates: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for payload in data.get("animationStructureCandidates") or []:
        name = str(payload.get("name") or "")
        if not name or (names and name not in names):
            continue
        keep, reason = bake_tool.animation_candidate_filter_decision(
            payload,
            strategy=strategy,
            max_source_frames=max_source_frames,
        )
        if keep:
            candidates.append(payload)
            if limit > 0 and len(candidates) >= limit:
                break
        else:
            skipped.append(
                {
                    "name": name,
                    "classification": payload.get("classification"),
                    "maxNestedDescendantFrameCount": payload.get("maxNestedDescendantFrameCount"),
                    "reason": reason,
                }
            )
    return candidates, {"filteredSkipped": skipped[:200]}


def summarize_candidate_report(report_path: Path) -> dict[str, Any]:
    if not report_path.exists():
        return {"outcome": "missing_report"}
    data = json.loads(report_path.read_text(encoding="utf-8-sig"))
    counts = data.get("counts") or {}
    outcome = "static"
    if counts.get("animated_icon_budget_skipped"):
        outcome = "budget-static"
    elif counts.get("animated_visual_static_downgraded"):
        outcome = "visual-static"
    elif counts.get("nested_icon_canvas_manifest_entries") or counts.get("nested_icon_layered_manifest_entries"):
        outcome = "animated"
    elif counts.get("animated_manifest_entries"):
        outcome = "parent-animated"
    elif data.get("nestedIconCanvasUnsupported") or data.get("nestedIconLayeredUnsupported"):
        outcome = "unsupported-static"

    return {
        "outcome": outcome,
        "counts": {
            key: counts.get(key)
            for key in (
                "processed",
                "created",
                "updated",
                "unchanged",
                "layout_protected",
                "nested_icon_canvas_manifest_entries",
                "nested_icon_canvas_unique_frame_images",
                "nested_icon_canvas_timeline_entries",
                "nested_icon_layered_manifest_entries",
                "nested_icon_layered_unique_frame_images",
                "nested_icon_layered_timeline_entries",
                "animated_manifest_entries",
                "animated_icon_bytes",
                "animated_icon_budget_skipped",
                "animated_visual_static_downgraded",
            )
            if counts.get(key) is not None
        },
        "nestedIconCanvas": data.get("nestedIconCanvas", [])[:3],
        "nestedIconLayered": data.get("nestedIconLayered", [])[:3],
        "budgetSkipped": data.get("animatedIconBudgetSkipped", [])[:3],
        "visualStatic": data.get("animatedVisualStaticDowngraded", [])[:3],
        "unsupported": (data.get("nestedIconCanvasUnsupported") or data.get("nestedIconLayeredUnsupported") or [])[:3],
    }


def main() -> int:
    args = parse_args()
    project_root = Path(__file__).resolve().parents[1]
    bake_tool = load_bake_tool(project_root)
    candidate_report = resolve_path(args.candidate_report, project_root)
    output_dir = resolve_path(args.output_dir, project_root)
    tmp_root = resolve_path(args.tmp_root, project_root)
    summary_path = resolve_path(args.report, project_root)
    if not candidate_report.exists():
        raise SystemExit(f"Missing candidate report: {candidate_report}")
    if args.max_source_frames < 0:
        raise SystemExit("--max-source-frames must be non-negative.")

    names = normalized_names(args.name)
    candidates, filter_info = selected_candidates(
        bake_tool,
        candidate_report,
        strategy=args.strategy,
        max_source_frames=args.max_source_frames,
        names=names,
        limit=args.limit,
    )
    summary: dict[str, Any] = {
        "tool": "tools/promote-icon-animation-candidates.py",
        "candidateReport": str(candidate_report),
        "outputDir": str(output_dir),
        "tmpRoot": str(tmp_root),
        "strategy": args.strategy,
        "maxSourceFrames": args.max_source_frames,
        "maxAnimatedIconBytes": args.max_animated_icon_bytes,
        "dryRun": bool(args.dry_run),
        "candidateCount": len(candidates),
        "candidates": [],
        **filter_info,
    }

    report_dir = summary_path.parent / (summary_path.stem + "-candidate-reports")
    report_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    tmp_root.mkdir(parents=True, exist_ok=True)

    start = time.time()
    for payload in candidates:
        name = str(payload.get("name") or "")
        key = safe_key(name)
        candidate_tmp = tmp_root / key
        candidate_report_path = report_dir / f"{key}.json"
        cmd = [
            sys.executable,
            str(project_root / "tools" / "bake-icons-offline.py"),
            "--scope",
            args.scope,
            "--name",
            name,
            "--export-animated-frames",
            "--animation-candidates-only",
            "--animation-candidate-report",
            str(candidate_report),
            "--animated-candidate-max-source-frames",
            str(args.max_source_frames),
            "--max-animated-icon-bytes",
            str(args.max_animated_icon_bytes),
            "--output-dir",
            str(output_dir),
            "--tmp-dir",
            str(candidate_tmp),
            "--report",
            str(candidate_report_path),
            "--ffdec-timeout-seconds",
            str(args.ffdec_timeout_seconds),
        ]
        if args.keep_tmp:
            cmd.append("--keep-tmp")
        if args.dry_run:
            cmd.append("--dry-run")

        item: dict[str, Any] = {
            "name": name,
            "classification": payload.get("classification"),
            "maxNestedDescendantFrameCount": payload.get("maxNestedDescendantFrameCount"),
            "parentPlainFrame1Stop": payload.get("parentPlainFrame1Stop"),
            "report": str(candidate_report_path),
        }
        candidate_start = time.time()
        try:
            result = subprocess.run(
                cmd,
                cwd=str(project_root),
                text=True,
                encoding="utf-8",
                errors="replace",
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=args.candidate_timeout_seconds if args.candidate_timeout_seconds > 0 else None,
            )
            item["exitCode"] = result.returncode
            item["outputTail"] = (result.stdout or "")[-2000:]
            item.update(summarize_candidate_report(candidate_report_path))
        except subprocess.TimeoutExpired as exc:
            item["exitCode"] = 124
            output = exc.stdout if isinstance(exc.stdout, str) else ""
            item["outputTail"] = (output or "")[-2000:]
            item["outcome"] = "timeout"
        item["elapsedSeconds"] = round(time.time() - candidate_start, 3)
        summary["candidates"].append(item)
        print(
            "[icon-animation-promote] {name}: {outcome} exit={exitCode} elapsed={elapsed}s".format(
                name=name,
                outcome=item.get("outcome"),
                exitCode=item.get("exitCode"),
                elapsed=item["elapsedSeconds"],
            )
        )

    outcomes: dict[str, int] = {}
    for item in summary["candidates"]:
        outcome = str(item.get("outcome") or "unknown")
        outcomes[outcome] = outcomes.get(outcome, 0) + 1
    summary["outcomes"] = outcomes
    summary["elapsedSeconds"] = round(time.time() - start, 3)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "[icon-animation-promote] candidates={count} outcomes={outcomes} report={report}".format(
            count=len(candidates),
            outcomes=outcomes,
            report=summary_path,
        )
    )
    return 1 if any((item.get("exitCode") or 0) != 0 for item in summary["candidates"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
