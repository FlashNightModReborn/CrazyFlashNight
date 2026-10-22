#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修复已归档源包的 Windows 工具发现问题（只改归档副本，原 ZIP 不动）。

改动内容（逐包记录到 generated/source-patches.json）：
1. svg_native.py 顶层 `import subprocess,re,fcntl` → 去掉 fcntl（Windows 无此模块）。
2. svg_native.py 的 render() 内 Inkscape/fcntl 锁逻辑 → 优先经
   tools/cf6-map-source/pydeps/svgrender.py 工具发现（Inkscape→Chrome→Edge），
   无 svgrender 可导入时回落原 Inkscape CLI 调用（保留原行为）。
3. source/*.py 中硬编码 Linux 字体路径 /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
   → 运行时解析链：包内 reference/fonts/DejaVuSans.ttf → 专用 Python 的
   matplotlib mpl-data DejaVuSans.ttf → PIL 默认字体。仅影响预览标注文字。
不改画稿设计、几何、注册点与任何生成逻辑。
"""
import json
import os
import re
import sys
from datetime import datetime, timezone, timedelta

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MAPS_ROOT = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图")
LOG = os.path.join(REPO, "tools", "cf6-map-source", "generated", "source-patches.json")

RENDER_RE = re.compile(
    r"def render\(path,width,destination=None\):\n(?:.*\n)*?    return dest\n")

NEW_RENDER = '''def render(path,width,destination=None):
    path=Path(path);dest=Path(destination) if destination else path.with_suffix('.png')
    # PATCHED(cf6-map-source): Windows 无 fcntl/Inkscape 时的工具发现；几何/输出参数不变
    try:
        from svgrender import render as _discover_render
    except ImportError:
        _discover_render=None
    if _discover_render is not None:
        _discover_render(path,int(width),dest)
    else:
        subprocess.run(['inkscape',str(path),'--export-width='+str(width),'--export-filename='+str(dest)],check=True,capture_output=True)
    return dest
'''


def patch_package(pkg_root):
    """pkg_root 为包根（含 source/ 的目录）。返回改动列表。"""
    changes = []
    p = os.path.join(pkg_root, "source", "svg_native.py")
    if not os.path.isfile(p):
        return changes
    with open(p, encoding="utf-8") as f:
        src = f.read()
    orig = src
    if "import subprocess,re,fcntl" in src:
        src = src.replace("import subprocess,re,fcntl", "import subprocess,re")
        changes.append("移除 fcntl 导入（Windows 不可用）")
    if "p.write_text(svg(viewbox,content))" in src:
        src = src.replace("p.write_text(svg(viewbox,content))",
                          "p.write_text(svg(viewbox,content),encoding='utf-8')")
        changes.append("SVG 写盘显式 UTF-8（Windows 默认 cp936 会写坏中文 title）")
    if "PATCHED(cf6-map-source)" not in src:
        src2, n = RENDER_RE.subn(NEW_RENDER, src, count=1)
        if n:
            src = src2
            changes.append("render() 改为 svgrender 工具发现（Inkscape→Chrome→Edge），无 svgrender 时回落原 inkscape 调用")
    if src != orig:
        with open(p, "w", encoding="utf-8") as f:
            f.write(src)
    return changes + patch_font_paths(pkg_root) + patch_tyrant_query(pkg_root)


LINUX_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

FONT_HELPER = '''def _cf6_font(size):
    # PATCHED(cf6-map-source): 硬编码 Linux 字体路径在 Windows 不存在；仅影响预览标注
    cands=[R/'reference/fonts'/'DejaVuSans.ttf']
    try:
        import matplotlib as _mpl, os as _os
        cands.append(Path(_os.path.join(_os.path.dirname(_mpl.__file__),'mpl-data','fonts','ttf','DejaVuSans.ttf')))
    except Exception:
        pass
    for _c in cands:
        if Path(_c).is_file():return ImageFont.truetype(str(_c),size)
    return ImageFont.load_default()
'''


def patch_font_paths(pkg_root):
    """替换 source/*.py 的硬编码 Linux 字体路径。返回改动文件列表。"""
    changes = []
    srcdir = os.path.join(pkg_root, "source")
    if not os.path.isdir(srcdir):
        return changes
    for fn in sorted(os.listdir(srcdir)):
        if not fn.endswith(".py"):
            continue
        p = os.path.join(srcdir, fn)
        with open(p, encoding="utf-8") as f:
            src = f.read()
        if LINUX_FONT not in src and "def _cf6_font" in src:
            continue
        orig = src
        if LINUX_FONT in src:
            src = re.sub(
                r"ImageFont\.truetype\(['\"]" + re.escape(LINUX_FONT) + r"['\"]\s*,\s*(\d+)\)",
                r"_cf6_font(\1)", src)
        needs_helper = "_cf6_font(" in src and "def _cf6_font" not in src
        if needs_helper:
            # 在最后一个顶层 import 行之后插入辅助函数
            lines = src.splitlines(keepends=True)
            ins = 0
            for i, ln in enumerate(lines):
                if re.match(r"^(import |from \S+ import )", ln):
                    ins = i + 1
            lines.insert(ins, FONT_HELPER)
            src = "".join(lines)
        if src != orig:
            with open(p, "w", encoding="utf-8") as f:
                f.write(src)
            changes.append("%s: Linux 字体路径 → 包内/mpl-data 解析链" % fn)
    return changes


TYRANT_QUERY = "  vals=[float(x) for x in subprocess.run(['inkscape',str(out),'--query-id=native-part','--query-x','--query-y','--query-width','--query-height'],capture_output=True,text=True,check=True).stdout.strip().splitlines()]"
TYRANT_QUERY_PATCHED = (
    "  # PATCHED(cf6-map-source): Inkscape 未安装；经 svgrender.query_bbox 工具发现\n"
    "  # （Inkscape 优先，缺失时 Chrome getBBox 实测几何包围盒）。查询只决定 viewBox\n"
    "  # 展示元数据（源注释：viewBox is presentation metadata only），不改几何/注册点\n"
    "  try:\n"
    "   from svgrender import query_bbox as _cf6_qb\n"
    "  except ImportError:\n"
    "   _cf6_qb=None\n"
    "  vals=list(_cf6_qb(out,'native-part')[:4]) if _cf6_qb else [float(x) for x in subprocess.run(['inkscape',str(out),'--query-id=native-part','--query-x','--query-y','--query-width','--query-height'],capture_output=True,text=True,check=True).stdout.strip().splitlines()]")


def patch_tyrant_query(pkg_root):
    """tyrant_culture.py 的直接 inkscape --query-id 调用 → svgrender.query_bbox 工具发现。"""
    p = os.path.join(pkg_root, "source", "tyrant_culture.py")
    if not os.path.isfile(p):
        return []
    with open(p, encoding="utf-8") as f:
        src = f.read()
    if "PATCHED(cf6-map-source)" in src or TYRANT_QUERY not in src:
        return []
    src = src.replace(TYRANT_QUERY, TYRANT_QUERY_PATCHED)
    with open(p, "w", encoding="utf-8") as f:
        f.write(src)
    return ["tyrant_culture.py: inkscape --query-id=native-part → svgrender.query_bbox 工具发现（Inkscape 优先，缺失时 Chrome getBBox；仅决定 viewBox 展示元数据）"]


def find_packages():
    """yield (stageRev, 包根绝对路径)。"""
    for stage_rev in sorted(os.listdir(MAPS_ROOT)):
        d = os.path.join(MAPS_ROOT, stage_rev)
        if not os.path.isdir(d):
            continue
        if os.path.isdir(os.path.join(d, "source")):
            yield stage_rev, d
            continue
        for sub in sorted(os.listdir(d)):
            sd = os.path.join(d, sub)
            if os.path.isdir(os.path.join(sd, "source")):
                yield stage_rev, sd


def main():
    results = {}
    for stage_rev, root in find_packages():
        ch = patch_package(root)
        if ch:
            results[stage_rev] = {"package": os.path.relpath(root, REPO).replace("\\", "/"),
                                  "changes": ch}
            print(stage_rev, "patched:", "; ".join(ch))
        else:
            print(stage_rev, "无需改动")
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    log = {"schema": "cf6-map-source-patches.v1",
           "generatedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
           "note": "仅改归档副本的工具发现；原 Downloads ZIP 未动；不改画稿/注册点",
           "packages": results}
    with open(LOG, "w", encoding="utf-8") as f:
        json.dump(log, f, ensure_ascii=False, indent=1)
    print("log ->", os.path.relpath(LOG, REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
