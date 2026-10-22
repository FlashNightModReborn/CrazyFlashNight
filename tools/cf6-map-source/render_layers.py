#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CF6 地图独立部件 SVG→PNG 渲染器（K3 地图源资产线）。

只渲染包内 parts/ 的独立部件 SVG（不用全景/预览当交付底图）。
输出写入对应包 baked/ 目录，逐张记录到 generated/render-manifest.json：
源 SVG、viewBox、逻辑尺寸、像素尺寸、渲染器、SHA256。
Inkscape 缺失时经 pydeps/svgrender 走 Chrome/Edge headless，产物标注
renderer 字段，属候选烘焙，待有 Inkscape 的环境复烘核对。

用法：
  python render_layers.py <stageRev> <part.svg> [<part.svg> ...] [--scale 2]
  python render_layers.py --check        # 校验 manifest 中产物仍存在且哈希一致
"""
import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone, timedelta

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MAPS_ROOT = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图")
MANIFEST = os.path.join(REPO, "tools", "cf6-map-source", "generated", "render-manifest.json")
sys.path.insert(0, os.path.join(REPO, "tools", "cf6-map-source", "pydeps"))
import svgrender  # noqa: E402


def find_pkg(stage_rev):
    d = os.path.join(MAPS_ROOT, stage_rev)
    if os.path.isdir(os.path.join(d, "parts")) or os.path.isdir(os.path.join(d, "source")):
        return d
    for sub in sorted(os.listdir(d)):
        sd = os.path.join(d, sub)
        if os.path.isdir(os.path.join(sd, "parts")):
            return sd
    raise SystemExit("包不存在: " + stage_rev)


def repo_rel(path):
    return os.path.relpath(path, REPO).replace("\\", "/")


def render_part(pkg_root, svg_name, scale, manifest):
    svg_path = os.path.join(pkg_root, "parts", svg_name)
    if not os.path.isfile(svg_path):
        raise SystemExit("缺部件 SVG: " + svg_path)
    vb = svgrender._svg_viewbox(svg_path)
    if not vb:
        raise SystemExit("无法读取 viewBox: " + svg_path)
    width = int(round(vb[2] * scale))
    png_name = os.path.splitext(svg_name)[0] + ".png"
    dest = os.path.join(pkg_root, "baked", png_name)
    renderer = svgrender.render(svg_path, width, dest)
    from PIL import Image
    with Image.open(dest) as im:
        if im.mode != "RGBA":
            im.convert("RGBA").save(dest)  # 仅模式归一，不重采样不改像素
    with open(dest, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()
    with Image.open(dest) as im:
        px = list(im.size)
    key = repo_rel(dest)
    manifest["renders"][key] = {
        "stagePackage": repo_rel(pkg_root),
        "svg": repo_rel(svg_path),
        "viewBox": vb,
        "logicalSize": [round(vb[2], 3), round(vb[3], 3)],
        "pixelSize": px,
        "scale": scale,
        "renderer": renderer,
        "rendererStatus": "candidate" if renderer != "inkscape" else "inkscape",
        "sha256": sha,
        "renderedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
    }
    print("rendered", key, px, "by", renderer)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage", nargs="?")
    ap.add_argument("parts", nargs="*")
    ap.add_argument("--scale", type=float, default=2.0)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    manifest = {"schema": "cf6-map-source-render-manifest.v1", "renders": {}}
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)

    if args.check:
        bad = []
        for png, rec in sorted(manifest["renders"].items()):
            p = os.path.join(REPO, png)
            if not os.path.isfile(p):
                bad.append("缺失 " + png)
                continue
            with open(p, "rb") as f:
                if hashlib.sha256(f.read()).hexdigest() != rec["sha256"]:
                    bad.append("哈希变化 " + png)
            if not os.path.isfile(os.path.join(REPO, rec["svg"])):
                bad.append("源SVG缺失 " + rec["svg"])
        for b in bad:
            print("ERROR", b)
        print("render-manifest check: %d 项, %d 问题" % (len(manifest["renders"]), len(bad)))
        return 1 if bad else 0

    if not args.stage or not args.parts:
        ap.error("需要 stageRev 与部件文件名")
    pkg = find_pkg(args.stage)
    os.makedirs(os.path.join(pkg, "baked"), exist_ok=True)
    for name in args.parts:
        render_part(pkg, name, args.scale, manifest)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("manifest ->", repo_rel(MANIFEST))
    return 0


if __name__ == "__main__":
    sys.exit(main())
