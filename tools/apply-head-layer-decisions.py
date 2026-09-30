#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把验收页导出/持久化的逐件拍板结果落到防具 XML。

输入：tmp/head-layer-verdicts/decisions.json（cf7.head-layer-decisions.v1）。
动作映射：
  hairAbove → 在条目 `<data>` 前确保 `<hairAbove>true</hairAbove>`
  helmet    → 把 `<helmet>false</helmet>` 改为 true；缺 helmet 行时在 `<data>` 前插入
  keep      → 显式保持现状，不改 XML（只计数）

只改文本行、不动其余字节；幂等。任何决定指向找不到的装备时非零退出。
用法：python tools/apply-head-layer-decisions.py [--dry-run]
"""

import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DECISIONS_PATH = PROJECT_ROOT / "tmp" / "head-layer-verdicts" / "decisions.json"
ARMOR_GLOB = "防具*.xml"


def load_decisions():
    if not DECISIONS_PATH.exists():
        sys.exit(f"决定文件不存在：{DECISIONS_PATH}（先在验收页拍板或把导出的 JSON 放到该路径）")
    payload = json.loads(DECISIONS_PATH.read_text(encoding="utf-8"))
    if payload.get("schema") != "cf7.head-layer-decisions.v1" or not isinstance(payload.get("decisions"), dict):
        sys.exit("决定文件 schema 不是 cf7.head-layer-decisions.v1")
    return payload["decisions"]


def find_item_block(text, name):
    marker = f"<name>{name}</name>"
    start = text.find(marker)
    if start < 0:
        return None
    end = text.find("</item>", start)
    if end < 0:
        return None
    return start, end


def apply_to_file(path, targets, dry_run):
    text = path.read_text(encoding="utf-8")
    report = []
    dirty = False
    for name, action in targets:
        block = find_item_block(text, name)
        if block is None:
            report.append((name, action, "not-found"))
            continue
        start, end = block
        segment = text[start:end]
        indent_match = re.search(r"\n([ \t]+)<data>", segment)
        if not indent_match:
            report.append((name, action, "no-data-anchor"))
            continue
        indent = indent_match.group(1)
        if action == "hairAbove":
            if "<hairAbove>" in segment:
                report.append((name, action, "already"))
                continue
            segment_new = segment.replace(f"\n{indent}<data>",
                                          f"\n{indent}<hairAbove>true</hairAbove>\n{indent}<data>", 1)
            report.append((name, action, "applied"))
        else:  # helmet
            if re.search(r"<helmet>\s*true\s*</helmet>", segment):
                report.append((name, action, "already"))
                continue
            if re.search(r"<helmet>\s*false\s*</helmet>", segment):
                segment_new = re.sub(r"<helmet>\s*false\s*</helmet>",
                                     "<helmet>true</helmet>", segment, count=1)
            else:
                segment_new = segment.replace(f"\n{indent}<data>",
                                              f"\n{indent}<helmet>true</helmet>\n{indent}<data>", 1)
            report.append((name, action, "applied"))
        if segment_new != segment:
            dirty = True
            text = text[:start] + segment_new + text[end:]
    if dirty and not dry_run:
        path.write_text(text, encoding="utf-8", newline="")
    return report, dirty


def main():
    dry_run = "--dry-run" in sys.argv
    decisions = load_decisions()
    targets = [(name, entry.get("action")) for name, entry in decisions.items()
               if isinstance(entry, dict) and entry.get("action") in ("hairAbove", "helmet")]
    kept = sum(1 for entry in decisions.values()
               if isinstance(entry, dict) and entry.get("action") == "keep")
    print(f"决定条目：{len(decisions)}（keep {kept} 件不改 XML，落地目标 {len(targets)} 件）")
    if not targets:
        print("没有 hairAbove/helmet 动作，未触碰任何 XML。")
        return

    files = sorted((PROJECT_ROOT / "data" / "items").glob(ARMOR_GLOB))
    remaining = dict(targets)
    all_reports = []
    for path in files:
        pending = [(name, action) for name, action in targets if name in remaining]
        if not pending:
            break
        text = path.read_text(encoding="utf-8")
        hit = [(name, action) for name, action in pending if f"<name>{name}</name>" in text]
        if not hit:
            continue
        report, _ = apply_to_file(path, hit, dry_run)
        all_reports.extend(report)
        for name, action, outcome in report:
            if outcome != "not-found":
                remaining.pop(name, None)
    for name, action, outcome in all_reports:
        print(f"  {outcome:>9}  {action:>9}  {name}")
    for name in remaining:
        print(f"  not-found  {remaining[name]:>9}  {name}")
    if remaining:
        print("有决定指向不存在的装备（虚拟装备改 bake 表，不改 XML）。")
        sys.exit(1)
    print(("DRY-RUN 未写入；" if dry_run else "已写入；") + "记得重跑 python tools/bake-dressup-offline.py 并 publish。")


if __name__ == "__main__":
    main()
