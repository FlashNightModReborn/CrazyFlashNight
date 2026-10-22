#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CF6 地图包内 previews 归档工具（K3 地图源资产线）。

run_rebuild.py 约定：大型 previews 先写包内 previews/（与包自检脚本一致），
完成后由本工具归档到 tmp/cf6-roguelike-20261021/kimi-maps/previews/<stage>-<rev>/，
版本化归档目录只保留消费者需要的图层 PNG 与编辑源。A05-R3/A06-R2/A08-R5 已在
前轮按同法归档（本工具统一记录 sync-manifest.json）。

只移动 <包根>/previews 整目录；reference/ 内部的 provenance 小预览（如
A01 reference/props-original/previews）不动。A07 本轮不建，不同步。
移动（非删除），逐文件记 SHA256/字节数，可重跑：目标已存在同名文件且
SHA 一致则跳过并去重，不一致则报错不覆盖。

用法：
  python sync_previews.py            # 归档全部已处理关卡
  python sync_previews.py A09 A10    # 指定关卡
  python sync_previews.py --check    # 校验包内已无顶层 previews 且 manifest 完整
"""
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone, timedelta

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_map_input import PACKAGES, pkg_dir  # noqa: E402

DEST_ROOT = os.path.join(REPO, "tmp", "cf6-roguelike-20261021", "kimi-maps", "previews")
MANIFEST = os.path.join(DEST_ROOT, "sync-manifest.json")
SKIP_STAGES = {"A07"}  # 车战本轮不建，包保持原样
# 前轮已按同法归档（包内已无 previews/），仅登记
PRE_ARCHIVED = {"A05": "R3", "A06": "R2", "A08": "R5"}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def repo_rel(path):
    return os.path.relpath(path, REPO).replace("\\", "/")


def sync_stage(stage, manifest):
    rev, _ = PACKAGES[stage]
    src = os.path.join(pkg_dir(stage), "previews")
    dest = os.path.join(DEST_ROOT, "%s-%s" % (stage, rev))
    entry = manifest["packages"].setdefault(
        stage, {"revision": rev, "dest": repo_rel(dest), "files": {}})
    if not os.path.isdir(src):
        entry["note"] = "包内无顶层 previews/（已归档或本包不产生）"
        return 0, 0
    moved, skipped = 0, 0
    for dp, _, fs in os.walk(src):
        for f in fs:
            sp = os.path.join(dp, f)
            rel = os.path.relpath(sp, src)
            tp = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(tp), exist_ok=True)
            s = sha256(sp)
            if os.path.isfile(tp):
                if sha256(tp) == s:
                    skipped += 1
                else:
                    raise RuntimeError("目标已存在且内容不同，拒绝覆盖: %s" % tp)
            else:
                shutil.move(sp, tp)
                moved += 1
            entry["files"][rel.replace("\\", "/")] = {
                "sha256": s, "bytes": os.path.getsize(tp)}
    # 清空后移除 previews 目录树（剩余的都是已确认一致的重复文件）
    shutil.rmtree(src)
    entry["syncedAt"] = datetime.now(timezone(timedelta(hours=8))).isoformat()
    entry["source"] = repo_rel(src) + "/（已归档清空）"
    return moved, skipped


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--check" in sys.argv:
        bad = []
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)
        for stage, entry in sorted(manifest["packages"].items()):
            for rel, meta in entry.get("files", {}).items():
                p = os.path.join(REPO, entry["dest"], rel)
                if not os.path.isfile(p):
                    bad.append("%s 缺失 %s" % (stage, rel))
                elif os.path.getsize(p) != meta["bytes"]:
                    bad.append("%s 字节数不符 %s" % (stage, rel))
        for stage in set(PACKAGES) - SKIP_STAGES:
            if os.path.isdir(os.path.join(pkg_dir(stage), "previews")):
                bad.append("%s 包内仍有顶层 previews/" % stage)
        for b in bad:
            print("ERROR", b)
        print("sync_previews check: %d 问题" % len(bad))
        return 1 if bad else 0

    stages = args or sorted(set(PACKAGES) - SKIP_STAGES)
    manifest = {"schema": "cf6-map-source-sync-previews.v1", "packages": {}}
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)
    for stage, rev in PRE_ARCHIVED.items():
        dest = os.path.join(DEST_ROOT, "%s-%s" % (stage, rev))
        if os.path.isdir(dest) and stage not in manifest["packages"]:
            files = {}
            for dp, _, fs in os.walk(dest):
                for f in fs:
                    p = os.path.join(dp, f)
                    rel = os.path.relpath(p, dest).replace("\\", "/")
                    files[rel] = {"sha256": sha256(p), "bytes": os.path.getsize(p)}
            manifest["packages"][stage] = {
                "revision": rev, "dest": repo_rel(dest), "files": files,
                "note": "前轮已归档（r1/r2），本轮补登记"}
    total_m = total_s = 0
    for stage in stages:
        if stage in SKIP_STAGES:
            print("== skip", stage, "（本轮不建）")
            continue
        m, s = sync_stage(stage, manifest)
        total_m += m
        total_s += s
        print("== sync", stage, "moved", m, "dedup", s, flush=True)
        os.makedirs(DEST_ROOT, exist_ok=True)
        with open(MANIFEST, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("done: moved %d, dedup %d -> %s" % (total_m, total_s, repo_rel(MANIFEST)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
