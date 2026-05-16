# -*- coding: utf-8 -*-
"""
parse-gt.py — 把 scripts/flashlog.txt 里 GT_* 行解析回 launcher/perf/tooltip-regression/tooltip-truth.json。

输出位置在 perf/tooltip-regression/ 下而不是 launcher/web/assets/——是 dev-only 中间产物，
不进 runtime 包也不进 git（launcher/perf/.gitignore 排除）。需要时重新跑本脚本生成。

输入 GT 行协议见 TooltipGroundTruthDump.as:
    GT_META|<k=v,...>
    GT_HEAD|<col1|col2|...>
    GT_POSE_HEAD|<col1|col2|...>
    GT_ITEM|<name>|<type>|<use>|dT|dM|dL|iT|iM|iL|introW|mainW|introTH|mainTH|introBgH|mainBgH|mainBgFlr
    GT_HTML_INTRO|<name>|<introHtml escaped>
    GT_HTML_DESC|<name>|<descHtml escaped>
    GT_POSE|<name>|mouseY|branch|tipsY|rightBgY|rightBgH|offset
    GT_TOTAL|<n>

HTML escape: | → _，\n → ¶，\r → ¤。本脚本反向。

输出 JSON：
    {
        meta: {...},
        count: int,
        items: [{
            name, type, use, dT, dM, dL, iT, iM, iL,
            introW, mainW, introTH, mainTH, introBgH, mainBgH, mainBgFlr,
            introHtml, descHtml,
            poses: [{mouseY, branch, tipsY, rightBgY, rightBgH, offset}, ...]
        }, ...]
    }
"""
import json
import os
import sys
from collections import OrderedDict


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
DEFAULT_LOG = os.path.join(REPO_ROOT, "scripts", "flashlog.txt")
DEFAULT_OUT = os.path.join(os.path.dirname(__file__), "tooltip-truth.json")


def unescape_line(s):
    return s.replace("¶", "\n").replace("¤", "\r")


def parse_meta(line):
    body = line.split("|", 1)[1]
    meta = {}
    for pair in body.split(","):
        if not pair:
            continue
        k, _, v = pair.partition("=")
        try:
            if "." in v:
                meta[k] = float(v)
            else:
                meta[k] = int(v)
        except ValueError:
            meta[k] = v
    return meta


def to_num(s):
    try:
        if "." in s:
            return float(s)
        return int(s)
    except ValueError:
        return s


def parse(log_path, out_path):
    items = OrderedDict()
    meta = None
    total = None

    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n").rstrip("\r")
            if not line:
                continue
            if line.startswith("GT_META|"):
                meta = parse_meta(line)
            elif line.startswith("GT_HEAD|") or line.startswith("GT_POSE_HEAD|"):
                continue
            elif line.startswith("GT_TOTAL|"):
                total = int(line.split("|", 1)[1])
            elif line.startswith("GT_ITEM|"):
                parts = line.split("|")
                # GT_ITEM|name|type|use|dT|dM|dL|iT|iM|iL|introW|mainW|introTH|mainTH|introBgH|mainBgH|mainBgFlr
                if len(parts) < 17:
                    continue
                name = parts[1]
                items[name] = OrderedDict([
                    ("name", name),
                    ("type", parts[2]),
                    ("use", parts[3]),
                    ("dT", to_num(parts[4])),
                    ("dM", to_num(parts[5])),
                    ("dL", to_num(parts[6])),
                    ("iT", to_num(parts[7])),
                    ("iM", to_num(parts[8])),
                    ("iL", to_num(parts[9])),
                    ("introW", to_num(parts[10])),
                    ("mainW", to_num(parts[11])),
                    ("introTH", to_num(parts[12])),
                    ("mainTH", to_num(parts[13])),
                    ("introBgH", to_num(parts[14])),
                    ("mainBgH", to_num(parts[15])),
                    ("mainBgFlr", to_num(parts[16])),
                    ("introHtml", ""),
                    ("descHtml", ""),
                    ("poses", []),
                ])
            elif line.startswith("GT_HTML_INTRO|"):
                parts = line.split("|", 2)
                if len(parts) == 3 and parts[1] in items:
                    items[parts[1]]["introHtml"] = unescape_line(parts[2])
            elif line.startswith("GT_HTML_DESC|"):
                parts = line.split("|", 2)
                if len(parts) == 3 and parts[1] in items:
                    items[parts[1]]["descHtml"] = unescape_line(parts[2])
            elif line.startswith("GT_POSE|"):
                parts = line.split("|")
                # GT_POSE|name|mouseY|branch|tipsY|rightBgY|rightBgH|offset
                if len(parts) < 8:
                    continue
                name = parts[1]
                if name not in items:
                    continue
                items[name]["poses"].append(OrderedDict([
                    ("mouseY", to_num(parts[2])),
                    ("branch", parts[3]),
                    ("tipsY", to_num(parts[4])),
                    ("rightBgY", to_num(parts[5])),
                    ("rightBgH", to_num(parts[6])),
                    ("offset", to_num(parts[7])),
                ]))

    out = OrderedDict([
        ("meta", meta or {}),
        ("count", total if total is not None else len(items)),
        ("items", list(items.values())),
    ])
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    size_kb = os.path.getsize(out_path) / 1024
    print("[OK] wrote %d items, %d poses, %.1f KB → %s" % (
        len(items), sum(len(i["poses"]) for i in items.values()), size_kb, out_path))


if __name__ == "__main__":
    log = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LOG
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT
    parse(log, out)
