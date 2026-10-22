#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CF6 地图源包安全归档工具。

职责：
1. 只读打开 C:/Users/fs/Downloads 下的交接索引 ZIP 与 21 个 source ZIP；
   逐包核对 SHA256 与字节数（权威为索引内 CF6-21张地图-源包总清单.json），
   并用 ZipFile.testzip 做 CRC 校验。
2. 安全解包到 flashswf/arts/new/Codex素材源稿/CF6地图/<STAGE>-<REV>/：
   拒绝绝对路径、盘符与 ".." 目录穿越；A08 R5 包无顶层目录，直接解进自建目录，
   不与其他包混合。
3. 原 ZIP 只读，不移动/删除/覆盖；重复执行时若目标已存在且条目数一致则跳过，
   可用 --force 重解。
4. 输出 input-manifest.json（CF6地图/ 下），记录每包校验结果与归档路径。

用法：
  python archive_sources.py            # 校验 + 解包全部 21 包
  python archive_sources.py --verify-only
  python archive_sources.py --stage A01 A08
  python archive_sources.py --check    # 只复核已归档目录与 manifest 一致
"""
import argparse
import hashlib
import json
import os
import sys
import zipfile
from datetime import datetime, timezone, timedelta

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DOWNLOADS = r"C:\Users\fs\Downloads"
INDEX_ZIP = os.path.join(DOWNLOADS, "CF6-21张地图-交接索引.zip")
INDEX_MANIFEST = "CF6-21张地图-源包总清单.json"
DEST_ROOT = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图")
MANIFEST_OUT = os.path.join(DEST_ROOT, "input-manifest.json")
CHUNK = 1 << 20


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(CHUNK), b""):
            h.update(blk)
    return h.hexdigest()


def safe_members(zf):
    """生成 (ZipInfo, 归一化相对路径)，拒绝目录穿越与绝对路径。"""
    for info in zf.infolist():
        name = info.filename.replace("\\", "/")
        if name.startswith("/") or (len(name) > 1 and name[1] == ":"):
            raise ValueError("拒绝绝对路径条目: %r" % info.filename)
        parts = [p for p in name.split("/") if p not in ("", ".")]
        if any(p == ".." for p in parts):
            raise ValueError("拒绝目录穿越条目: %r" % info.filename)
        yield info, "/".join(parts)


def extract_one(entry, force=False):
    stage, rev = entry["stage"], entry["revision"]
    src = os.path.join(DOWNLOADS, entry["file_name"])
    result = {"stage": stage, "revision": rev, "file": entry["file_name"],
              "expectedSha256": entry["sha256"], "expectedBytes": entry["bytes"]}
    if not os.path.isfile(src):
        result.update(status="missing-zip")
        return result
    result["actualBytes"] = os.path.getsize(src)
    if result["actualBytes"] != entry["bytes"]:
        result.update(status="size-mismatch")
        return result
    digest = sha256_file(src)
    result["actualSha256"] = digest
    if digest != entry["sha256"]:
        result.update(status="sha256-mismatch")
        return result
    with zipfile.ZipFile(src) as zf:
        bad = zf.testzip()
        if bad is not None:
            result.update(status="crc-failed", badMember=bad)
            return result
        members = list(safe_members(zf))
        dest_dir = os.path.join(DEST_ROOT, "%s-%s" % (stage, rev))
        rel_paths = [rel for _, rel in members if rel]
        result["entryCount"] = len(rel_paths)
        result["archiveRoot"] = entry.get("archive_root") or "(无顶层目录)"
        dest_rel = os.path.relpath(dest_dir, REPO).replace("\\", "/")
        result["archivedTo"] = dest_rel + "/"
        if os.path.isdir(dest_dir) and not force:
            existing = []
            for root, _dirs, files in os.walk(dest_dir):
                for fn in files:
                    existing.append(os.path.relpath(os.path.join(root, fn), dest_dir))
            if len(existing) >= len([p for p in rel_paths if not p.endswith("/")]):
                result.update(status="verified-already-archived")
                return result
            result.update(status="dest-exists-incomplete", hint="用 --force 重解")
            return result
        os.makedirs(dest_dir, exist_ok=True)
        written = 0
        for info, rel in members:
            if not rel or rel.endswith("/"):
                continue
            target = os.path.join(dest_dir, *rel.split("/"))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if os.path.exists(target) and os.path.getsize(target) == info.file_size:
                continue
            with zf.open(info) as r, open(target, "wb") as w:
                while True:
                    blk = r.read(CHUNK)
                    if not blk:
                        break
                    w.write(blk)
            written += 1
        result.update(status="archived", filesWritten=written)
    return result


def load_index():
    with zipfile.ZipFile(INDEX_ZIP) as zf:
        bad = zf.testzip()
        if bad is not None:
            raise RuntimeError("索引 ZIP CRC 失败: %s" % bad)
        return json.loads(zf.read(INDEX_MANIFEST).decode("utf-8"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify-only", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--stage", nargs="*", default=None)
    args = ap.parse_args()

    index = load_index()
    entries = index["maps"]
    if args.stage:
        wanted = {s.upper() for s in args.stage}
        entries = [e for e in entries if e["stage"] in wanted]
        missing = wanted - {e["stage"] for e in entries}
        if missing:
            print("索引中无此关卡: %s" % sorted(missing), file=sys.stderr)
            return 2

    results = []
    for e in entries:
        if args.check:
            dest_dir = os.path.join(DEST_ROOT, "%s-%s" % (e["stage"], e["revision"]))
            ok = os.path.isdir(dest_dir)
            results.append({"stage": e["stage"], "revision": e["revision"],
                            "status": "present" if ok else "not-archived"})
            continue
        if args.verify_only:
            src = os.path.join(DOWNLOADS, e["file_name"])
            r = {"stage": e["stage"], "revision": e["revision"], "file": e["file_name"]}
            if not os.path.isfile(src):
                r["status"] = "missing-zip"
            else:
                ok = (os.path.getsize(src) == e["bytes"]
                      and sha256_file(src) == e["sha256"])
                with zipfile.ZipFile(src) as zf:
                    bad = zf.testzip()
                r["status"] = "verified" if ok and bad is None else "FAILED"
            results.append(r)
        else:
            results.append(extract_one(e, force=args.force))

    bad = [r for r in results if r["status"] not in
           ("verified", "archived", "verified-already-archived", "present")]
    out = {
        "schema": "cf6-map-source-input-manifest.v1",
        "generatedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "indexZip": os.path.relpath(INDEX_ZIP, REPO).replace("\\", "/"),
        "indexTitle": index.get("title"),
        "indexDate": index.get("date"),
        "destRoot": os.path.relpath(DEST_ROOT, REPO).replace("\\", "/") + "/",
        "originalZipsReadonly": True,
        "results": results,
        "failed": bad,
    }
    if not args.verify_only:
        os.makedirs(DEST_ROOT, exist_ok=True)
        prev = {}
        if os.path.isfile(MANIFEST_OUT) and not args.stage and not args.check:
            pass  # 全量运行时直接重写
        elif os.path.isfile(MANIFEST_OUT):
            try:
                prev = {r["stage"]: r for r in
                        json.load(open(MANIFEST_OUT, encoding="utf-8"))["results"]}
            except Exception:
                prev = {}
        if prev:
            merged = [prev.get(r["stage"], r) if r["stage"] not in prev else r
                      for r in results]
            known = {r["stage"] for r in results}
            merged += [v for k, v in prev.items() if k not in known]
            out["results"] = merged
            out["failed"] = [r for r in merged if r.get("status") not in
                             ("verified", "archived", "verified-already-archived", "present")]
        with open(MANIFEST_OUT, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)
        print("manifest ->", os.path.relpath(MANIFEST_OUT, REPO))
    for r in results:
        print("%-4s %-3s %s" % (r["stage"], r["revision"], r["status"]))
    if bad:
        print("失败 %d 包" % len(bad), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
