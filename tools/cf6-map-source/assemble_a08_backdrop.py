#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A08 (R5) 背景与动态件图层装配器（K3 地图源资产线）。

A08-R5 包只重绘环境材质与赛车1823；包内 assemble_scene.py 会把
environment_backdrop 与 environment_prop_or_animation 一起装进
previews 用 environment-a8.svg。本脚本复用同一 reference 数据与同一
node/pref/placed 装配逻辑（逐行复制自包内 source/assemble_scene.py），但：
1. 背景只含 role == "environment_backdrop"（sprite 1825 子树），
   动态件（滑门1430/摄像头1832/生化桶1838/破坏箱1442）不烘入底图；
2. 动态件各出帧1独立 SVG+PNG（放置矩阵不进 PNG，写进 map-input 元数据；
   门1430 的实例级 colorMult 调暗按原样应用到 PNG）。

前置：先跑 python tools/cf6-map-source/run_rebuild.py A08
（生成 parts/bitmap-*.svg 与 parts/shape-*.svg）。

用法：
  python assemble_a08_backdrop.py            # 装配并渲染
  python assemble_a08_backdrop.py --check    # 只校验产物存在与引用完整
"""
import json
import os
import re
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PKG = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图", "A08-R5")
sys.path.insert(0, os.path.join(REPO, "tools", "cf6-map-source", "pydeps"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svgrender  # noqa: E402
from render_layers import render_part, repo_rel, MANIFEST  # noqa: E402

WORLD_VIEWBOX = [0, 0, 1150, 410]  # 包 README：Logical1150x410；根 gameworld 矩阵≈identity
# 动态件帧1：cid -> (局部 viewBox, 输出名)。viewBox 与包 assemble_scene.py 对象对比一致
PROPS = {
    1430: ([-85, -145, 170, 315], "prop-1430-f1"),
    1832: ([-90, -60, 180, 120], "prop-1832-f1"),
    1838: ([-190, -75, 380, 130], "prop-1838-f1"),
}

NODES = json.loads(open(os.path.join(PKG, "reference", "environment-original-nodes.json"),
                        encoding="utf-8").read())["nodes"]
LAY = json.loads(open(os.path.join(PKG, "reference", "layout-inventory.json"),
                      encoding="utf-8").read())
ROOT_WORLD_MATRIX = next(o["matrix"] for o in LAY["rootDisplay"].values()
                         if o.get("name") == "gameworld")
counter = 0


def pref(s, p):
    # 复制自 A08-R5 source/assemble_scene.py：局部 id 前缀化，避免多实例引用冲突
    ids = re.findall(r'\bid="([^"]+)"', s)
    for i in sorted(ids, key=len, reverse=True):
        s = s.replace('id="%s"' % i, 'id="%s%s"' % (p, i))
        s = s.replace("url(#%s)" % i, "url(#%s%s)" % (p, i))
        s = s.replace('href="#%s"' % i, 'href="#%s%s"' % (p, i))
    return s


def inner(p, prefix):
    # 复制自包内 svg_native.inner 的语义：读取 SVG 文件正文（去掉 <svg> 外壳）并前缀化
    with open(p, encoding="utf-8") as f:
        s = f.read()
    m = re.search(r"<svg[^>]*>(.*)</svg>", s, re.S)
    body = m.group(1)
    return pref(body, prefix)


def node(cid, f=1, mode="new"):
    # 复制自 A08-R5 source/assemble_scene.py 的 node()（含帧状态/遮罩/变色逻辑）
    global counter
    counter += 1
    z = counter
    a = NODES[str(cid)]
    if a["code"] != 39:
        p = os.path.join(PKG, "parts", "shape-%s.svg" % cid)
        q = os.path.join(PKG, "reference", "reused-crate", "shape-%s.svg" % cid)
        if mode == "new" and os.path.isfile(p):
            return inner(p, "n%s" % z)
        if mode == "new" and os.path.isfile(q):
            return inner(q, "n%s" % z)
        return pref(a.get("svgInner", ""), "n%s_" % z)
    state = a["frames"][(f - 1) % len(a["frames"])]
    body = ""
    masks = []
    for depth, o in sorted(state.items(), key=lambda t: int(t[0])):
        dep = int(depth)
        masks = [v for v in masks if dep <= v[0]]
        if o.get("name") == "area":
            continue
        mult = o.get("colorMult", [256] * 4)
        add = o.get("colorAdd", [0] * 4)
        if mult[3] == 0 and add[3] == 0:
            continue
        frag = node(o["id"], 1 if o["id"] == 254 else f - o["placedAt"] + 1, mode)
        if mult != [256] * 4 or add != [0] * 4:
            counter += 1
            fid = "col%d" % counter
            filt = ('<filter id="%s" color-interpolation-filters="sRGB"><feComponentTransfer>'
                    % fid + "".join(
                        '<feFunc%s type="linear" slope="%s" intercept="%s"/>'
                        % (c, mult[k] / 256, add[k] / 255)
                        for k, c in enumerate("RGBA")) + "</feComponentTransfer></filter>")
            frag = "<defs>%s</defs><g filter=\"url(#%s)\">%s</g>" % (filt, fid, frag)
        frag = ('<g transform="matrix(' + " ".join(map(str, o["matrix"])) + ')">'
                + frag + "</g>")
        if "clipDepth" in o:
            counter += 1
            mid = "mask%d" % counter
            fid = "white%d" % counter
            body += ('<defs><filter id="%s"><feColorMatrix type="matrix" values="0 0 0 0 1 '
                     '0 0 0 0 1 0 0 0 0 1 0 0 0 1 0"/></filter>'
                     '<mask id="%s" maskUnits="userSpaceOnUse" x="-5000" y="-5000" '
                     'width="10000" height="10000"><g filter="url(#%s)">%s</g></mask></defs>'
                     % (fid, mid, fid, frag))
            masks.append((o["clipDepth"], mid))
            continue
        for _, mid in masks:
            frag = '<g mask="url(#%s)">%s</g>' % (mid, frag)
        body += frag
    return body


def placed(o, frame, mode):
    # 复制自 A08-R5 source/assemble_scene.py 的 placed()
    global counter
    frag = node(o["id"], frame, mode)
    mult = o.get("colorMult", [256] * 4)
    add = o.get("colorAdd", [0] * 4)
    if mult != [256] * 4 or add != [0] * 4:
        counter += 1
        fid = "placecol%d" % counter
        frag = ('<defs><filter id="' + fid + '" color-interpolation-filters="sRGB">'
                "<feComponentTransfer>" + "".join(
                    '<feFunc%s type="linear" slope="%s" intercept="%s"/>'
                    % (c, mult[k] / 256, add[k] / 255)
                    for k, c in enumerate("RGBA")) + "</feComponentTransfer></filter></defs>"
                '<g filter="url(#' + fid + ')">' + frag + "</g>")
    return ('<g transform="matrix(' + " ".join(map(str, o["matrix"])) + ')">'
            + frag + "</g>")


def write_svg(rel_path, view_box, body):
    out = os.path.join(PKG, rel_path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">%s</svg>'
                % (" ".join(map(str, view_box)), body))
    return out


def build():
    global counter
    # 背景：仅 environment_backdrop（sprite1825 子树，含赛车1823 等新材质）
    counter = 0
    env = ""
    for o in LAY["worldFirstFrame"]:
        if o["role"] != "environment_backdrop":
            continue
        env += placed(o, 1, "new")
    env = ('<g transform="matrix(' + " ".join(map(str, ROOT_WORLD_MATRIX)) + ')">'
           + env + "</g>")
    bg_svg = write_svg(os.path.join("parts", "environment-a8-backdrop.svg"),
                       WORLD_VIEWBOX, env)
    print("written", repo_rel(bg_svg))

    # 动态件帧1（局部坐标；门1430 的实例调暗由 map-input 元数据表达，PNG 保持符号原色）
    for cid, (vb, name) in PROPS.items():
        counter = 0
        body = node(cid, 1, "new")
        p = write_svg(os.path.join("parts", name + ".svg"), vb, body)
        print("written", repo_rel(p))
    return [os.path.join("parts", "environment-a8-backdrop.svg")] + [
        os.path.join("parts", v[1] + ".svg") for v in PROPS.values()]


def check():
    bad = []
    rels = [os.path.join("parts", "environment-a8-backdrop.svg"),
            os.path.join("baked", "background-1825-backdrop.png")]
    rels += [os.path.join("parts", v[1] + ".svg") for v in PROPS.values()]
    rels += [os.path.join("baked", v[1] + ".png") for v in PROPS.values()]
    for r in rels:
        if not os.path.isfile(os.path.join(PKG, r)):
            bad.append(r)
    for b in bad:
        print("ERROR 缺失", b)
    print("assemble_a08_backdrop check: %d 项, %d 缺失" % (len(rels), len(bad)))
    return 1 if bad else 0


def main():
    if "--check" in sys.argv:
        return check()
    svgs = build()
    manifest = {"schema": "cf6-map-source-render-manifest.v1", "renders": {}}
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)
    # 渲染：背景 2x（2300 宽），动态件 2x
    render_part(PKG, "environment-a8-backdrop.svg", 2.0, manifest)
    # 背景 PNG 采用合同命名
    src = os.path.join(PKG, "baked", "environment-a8-backdrop.png")
    dst = os.path.join(PKG, "baked", "background-1825-backdrop.png")
    os.replace(src, dst)
    rec = manifest["renders"].pop(repo_rel(src))
    manifest["renders"][repo_rel(dst)] = rec
    for v in PROPS.values():
        render_part(PKG, v[1] + ".svg", 2.0, manifest)
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("manifest ->", repo_rel(MANIFEST))
    return 0


if __name__ == "__main__":
    sys.exit(main())
