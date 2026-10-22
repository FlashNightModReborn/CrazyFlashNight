#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SVG 光栅化工具发现与渲染（Inkscape 缺失时的本机替代）。

优先级：Inkscape CLI（若实际安装） > Chrome headless > Edge headless。
浏览器模式用等比 HTML 包装保证精确像素尺寸，并用透明背景截图保留 alpha。
所有渲染记录实际使用的渲染器；非 Inkscape 产出在元数据中标注为候选，
待主控在有 Inkscape 的环境复烘核对。
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

INKSCAPE_CANDIDATES = [
    r"C:\Program Files\Inkscape\bin\inkscape.exe",
    r"C:\Program Files (x86)\Inkscape\bin\inkscape.exe",
]
CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]
EDGE_CANDIDATES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]


def find_renderer():
    for exe in INKSCAPE_CANDIDATES:
        if os.path.isfile(exe):
            return ("inkscape", exe)
    if shutil.which("inkscape"):
        return ("inkscape", shutil.which("inkscape"))
    for exe in CHROME_CANDIDATES:
        if os.path.isfile(exe):
            return ("chrome", exe)
    for exe in EDGE_CANDIDATES:
        if os.path.isfile(exe):
            return ("edge", exe)
    return (None, None)


def _svg_viewbox(svg_path):
    with open(svg_path, "rb") as f:
        head = f.read(4096).decode("utf-8", "replace")
    m = re.search(r'viewBox="([^"]+)"', head)
    if not m:
        return None
    return [float(v) for v in re.split(r"[\s,]+", m.group(1).strip())]


def query_bbox(svg_path, element_id):
    """与 Inkscape `--query-id=<id> --query-x/--query-y/--query-width/--query-height`
    同语义的几何包围盒查询。Inkscape 缺失时用 Chrome headless 内联 SVG +
    getBBox() 实测（该元素无自身 transform、祖先无变换时与文档坐标一致）。
    返回 (x, y, width, height)；并标注实际引擎。"""
    kind, exe = find_renderer()
    if kind == "inkscape":
        out = subprocess.run(
            [exe, str(svg_path), "--query-id=%s" % element_id,
             "--query-x", "--query-y", "--query-width", "--query-height"],
            check=True, capture_output=True, text=True).stdout.strip().splitlines()
        return tuple(float(v) for v in out) + ("inkscape",)
    if kind is None:
        raise RuntimeError("无可用 SVG 查询工具（Inkscape/Chrome/Edge 均未发现）")
    svg_path = os.path.abspath(str(svg_path))
    with open(svg_path, encoding="utf-8") as f:
        svg_text = f.read()
    html = ("<!doctype html><html><head><meta charset='utf-8'></head><body>"
            + svg_text
            + "<pre id='bbox-result'></pre><script>"
            "var el=document.getElementById(%s);"
            "var b=el.getBBox();"
            "document.getElementById('bbox-result').textContent=JSON.stringify([b.x,b.y,b.width,b.height]);"
            "</script></body></html>" % (repr(element_id)))
    tmpdir = tempfile.mkdtemp(prefix="cf6bbox-")
    try:
        html_path = os.path.join(tmpdir, "query.html")
        with open(html_path, "w", encoding="utf-8") as f:
            f.write(html)
        dom = subprocess.run(
            [exe, "--headless=new", "--disable-gpu", "--no-first-run",
             "--disable-extensions", "--virtual-time-budget=5000",
             "--user-data-dir=" + os.path.join(tmpdir, "profile"),
             "--dump-dom", "file:///" + html_path.replace("\\", "/")],
            check=True, capture_output=True, text=True, timeout=120).stdout
        m = re.search(r"<pre id=['\"]bbox-result['\"]>([^<]+)</pre>", dom)
        if not m:
            raise RuntimeError("Chrome getBBox 查询无结果: %s #%s" % (svg_path, element_id))
        import json as _json
        vals = _json.loads(m.group(1))
        return tuple(float(v) for v in vals) + (kind,)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def render(svg_path, width, dest):
    """与源包 svg_native.render(path, width, dest) 同接口。
    width 为导出像素宽，等比缩放。返回实际使用的渲染器名。"""
    kind, exe = find_renderer()
    if kind is None:
        raise RuntimeError("无可用 SVG 渲染器（Inkscape/Chrome/Edge 均未发现）")
    svg_path = os.path.abspath(str(svg_path))
    dest = os.path.abspath(str(dest))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if kind == "inkscape":
        subprocess.run([exe, svg_path, "--export-width=%d" % width,
                        "--export-filename=%s" % dest],
                       check=True, capture_output=True)
        return kind
    vb = _svg_viewbox(svg_path)
    if not vb or vb[2] <= 0 or vb[3] <= 0:
        raise RuntimeError("无法确定 SVG 宽高比: %s" % svg_path)
    w = int(round(width))
    h = int(round(width * vb[3] / vb[2]))
    svg_uri = "file:///" + svg_path.replace("\\", "/")
    html = ("<!doctype html><html><head><meta charset='utf-8'>"
            "<style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}"
            "img{display:block;width:%dpx;height:%dpx}</style></head>"
            "<body><img src=\"%s\"></body></html>" % (w, h, svg_uri))
    tmpdir = tempfile.mkdtemp(prefix="cf6svg-")
    try:
        html_path = os.path.join(tmpdir, "wrap.html")
        with open(html_path, "w", encoding="utf-8") as f:
            f.write(html)
        subprocess.run([
            exe, "--headless=new", "--disable-gpu", "--no-first-run",
            "--disable-extensions", "--hide-scrollbars",
            "--default-background-color=00000000",
            "--force-device-scale-factor=1",
            "--user-data-dir=" + os.path.join(tmpdir, "profile"),
            "--window-size=%d,%d" % (w, h),
            "--screenshot=" + dest,
            "file:///" + html_path.replace("\\", "/"),
        ], check=True, capture_output=True, timeout=120)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    if not os.path.isfile(dest):
        raise RuntimeError("浏览器渲染未产出 %s" % dest)
    return kind


if __name__ == "__main__":
    if len(sys.argv) == 1:
        print("renderer:", find_renderer())
    elif len(sys.argv) == 4:
        print("rendered by", render(sys.argv[1], int(sys.argv[2]), sys.argv[3]))
    else:
        print("usage: svgrender.py [svg width dest]", file=sys.stderr)
        sys.exit(2)
