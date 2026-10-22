#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CF6 地图源包本地重建运行器。

对每个 source-only 包执行 `python source/rebuild.py`（包根为 cwd），
解释器优先取环境变量 CF6_PYTHON_EXE（主控提供的专用 Python，含真实
scipy/matplotlib/fontTools），缺省回落 tmp/cf6-py312/Scripts/python.exe，
再回落 sys.executable。PYTHONPATH 注入 tools/cf6-map-source/pydeps
（svgrender 工具发现）。大型 previews 仍写在包内 previews/（与包的自检脚本一致），
完成后可由 sync_previews.py 归档到 tmp。逐包记录 rebuild-report.json。

用法：
  python run_rebuild.py A06 A08 ...
  python run_rebuild.py --all-source-only
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone, timedelta

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MAPS_ROOT = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图")
PYDEPS = os.path.join(REPO, "tools", "cf6-map-source", "pydeps")
REPORT = os.path.join(REPO, "tools", "cf6-map-source", "generated", "rebuild-report.json")
LOG_DIR = os.path.join(REPO, "tmp", "cf6-roguelike-20261021", "kimi-maps", "rebuild-logs")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patch_sources import find_packages, patch_package  # noqa: E402

DEFAULT_PY = os.path.join(REPO, "tmp", "cf6-py312", "Scripts", "python.exe")


def pick_python():
    env = os.environ.get("CF6_PYTHON_EXE")
    if env and os.path.isfile(env):
        return env
    if os.path.isfile(DEFAULT_PY):
        return DEFAULT_PY
    return sys.executable

# 本轮肉鸽范围（A07 车战不建；A01-A05 随包带 baked，重建可选）
ROGUE_STAGES = ["A01", "A02", "A03", "A04", "A05", "A06", "A08", "A09", "A10",
                "A11", "A12", "A13", "A14", "A15", "A16", "A17", "A18", "A19",
                "A20", "A22"]


def run_one(stage_rev, root):
    patch_package(root)
    env = dict(os.environ)
    env["PYTHONPATH"] = PYDEPS + os.pathsep + env.get("PYTHONPATH", "")
    env["PYTHONIOENCODING"] = "utf-8"
    # PATCHED(cf6-map-source): 源脚本用 read_text()/write_text() 缺省编码；
    # Windows 默认 GBK 会读坏 UTF-8 JSON/写坏中文，UTF-8 模式只统一编码，不改逻辑
    env["PYTHONUTF8"] = "1"
    os.makedirs(LOG_DIR, exist_ok=True)
    log_path = os.path.join(LOG_DIR, "%s.log" % stage_rev)
    started = datetime.now(timezone(timedelta(hours=8)))
    with open(log_path, "w", encoding="utf-8") as lf:
        proc = subprocess.run([pick_python(), os.path.join("source", "rebuild.py")],
                              cwd=root, env=env, stdout=lf,
                              stderr=subprocess.STDOUT, timeout=1800)
    finished = datetime.now(timezone(timedelta(hours=8)))
    baked = []
    bd = os.path.join(root, "baked")
    if os.path.isdir(bd):
        baked = sorted(os.listdir(bd))
    return {
        "stage": stage_rev,
        "package": os.path.relpath(root, REPO).replace("\\", "/"),
        "python": pick_python(),
        "exitCode": proc.returncode,
        "startedAt": started.isoformat(),
        "finishedAt": finished.isoformat(),
        "log": os.path.relpath(log_path, REPO).replace("\\", "/"),
        "bakedFiles": baked,
        "status": "ok" if proc.returncode == 0 else "failed",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stages", nargs="*")
    ap.add_argument("--all-source-only", action="store_true")
    args = ap.parse_args()

    all_pkgs = dict(find_packages())
    if args.all_source_only:
        wanted = [sr for sr in all_pkgs
                  if sr.split("-")[0] in ROGUE_STAGES
                  and sr.split("-")[0] not in ("A01", "A02", "A03", "A04", "A05")]
    else:
        wanted = [sr for sr in all_pkgs if sr.split("-")[0] in
                  {s.upper() for s in args.stages}]
    if not wanted:
        print("没有匹配关卡", file=sys.stderr)
        return 2

    results = {}
    if os.path.isfile(REPORT):
        try:
            results = {r["stage"]: r for r in
                       json.load(open(REPORT, encoding="utf-8"))["runs"]}
        except Exception:
            results = {}
    for sr in wanted:
        print("== rebuild", sr, flush=True)
        r = run_one(sr, all_pkgs[sr])
        results[sr] = r
        print("   ", r["status"], "exit", r["exitCode"], "baked:", len(r["bakedFiles"]))
    out = {"schema": "cf6-map-source-rebuild-report.v1",
           "generatedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
           "python": pick_python(),
           "pydeps": "tools/cf6-map-source/pydeps (svgrender 工具发现；scipy/fontTools/matplotlib 用专用Python真实依赖)",
           "runs": sorted(results.values(), key=lambda r: r["stage"])}
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    failed = [r for r in results.values() if r["status"] != "ok"]
    print("report ->", os.path.relpath(REPORT, REPO), "| failed:", len(failed))
    return 1 if any(r["stage"] in wanted for r in failed) else 0


if __name__ == "__main__":
    sys.exit(main())
