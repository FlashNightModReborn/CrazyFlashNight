#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CF6 地图 r3 通用图层装配器（K3 地图源资产线，A09-A20/A22）。

r2 的 assemble_a08_backdrop.py 只覆盖 A08。本脚本把同一做法推广到
source-only 的 R2 包：复用包内 reference 数据与 node()/transformed() 装配
语义（逐行对应各包 source/rebuild.py / assemble_scene.py 的同名片段），
按 role 分层输出，不把全景/预览当交付底图：

1. background：仅 role == "environment_backdrop" 的 sprite 子树，viewBox 取
   其在 gameworld 世界坐标的外包围（保留超出逻辑世界的原画延伸，与 A02
   全外包围先例一致）；
2. elevator-scroll（A10/A13）：独立 1875 滚动 tile（1876 的子件），
   loopHeight=541.95 来自包 qa/elevator-state-guidance.json 的
   tileOffsetY；clip 通过对 cabin(backdrop) 与 1884 前景遮挡的 alpha 补集
   实测外包围（相对 tile 图层原点），属原型适配并如实标注；
3. foreground（A10/A13 的 1884 前框）：独立遮挡层；
4. 动态道具：worldFirstFrame 中 environment_prop_or_animation 逐 sprite 出
   帧1独立 SVG+PNG（局部符号坐标，实例矩阵/depth/帧数进 map-input 元数据，
   不烘入底图）。

前置：先跑 python tools/cf6-map-source/run_rebuild.py <stage>
（生成 parts/bitmap-*.svg 与 parts/shape-*.svg）。

用法：
  python assemble_layers_r3.py A09 A10 ...   # 装配并渲染
  python assemble_layers_r3.py --check       # 校验全部已装配图的产物完整
"""
import json
import math
import os
import re
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MAPS_ROOT = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图")
sys.path.insert(0, os.path.join(REPO, "tools", "cf6-map-source", "pydeps"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svgrender  # noqa: E402
from render_layers import render_part, repo_rel, MANIFEST  # noqa: E402

# 关卡 -> 包子目录（相对 MAPS_ROOT/<stage>-R2/）
PACKAGES = {
    "A09": "cf6-stage9-redraw-r2", "A10": "cf6-stage10-redraw-r2",
    "A11": "cf6-stage11-redraw-r2", "A12": "cf6-stage12-redraw-r2",
    "A13": "cf6-stage13-redraw-r2", "A14": "cf6-stage14-redraw-r2",
    "A15": "cf6-stage15-redraw-r2", "A16": "cf6-stage16-redraw-r2",
    "A17": "cf6-stage17-redraw-r2", "A18": "cf6-stage18-redraw-r2",
    "A19": "cf6-stage19-redraw-r2", "A20": "cf6-stage20-redraw-r2",
    "A22": "cf6-stage22-redraw-r2",
}
# 电梯图：滚动 tile sprite、前景 occluder sprite
ELEVATOR = {"A10": {"tile": 1875, "front": 1884},
            "A13": {"tile": 1875, "front": 1884}}
ELEVATOR_LOOP_HEIGHT = 541.95  # qa/elevator-state-guidance.json tileOffsetY（A10/A13 同源）

_counter = 0


def pref(s, p):
    # 逐行对应各包 rebuild/assemble 的 pref()：局部 id 前缀化
    ids = re.findall(r'\bid="([^"]+)"', s)
    for i in sorted(set(ids), key=len, reverse=True):
        s = s.replace('id="%s"' % i, 'id="%s%s"' % (p, i))
        s = s.replace("url(#%s)" % i, "url(#%s%s)" % (p, i))
        s = s.replace('href="#%s"' % i, 'href="#%s%s"' % (p, i))
    return s


class Package:
    def __init__(self, stage):
        self.stage = stage
        self.root = os.path.join(MAPS_ROOT, "%s-R2" % stage, PACKAGES[stage])
        ref = os.path.join(self.root, "reference")
        with open(os.path.join(ref, "environment-original-nodes.json"), encoding="utf-8") as f:
            self.nodes = json.load(f)["nodes"]
        with open(os.path.join(ref, "environment-shape-details.json"), encoding="utf-8") as f:
            self.detail = {a["id"]: a for a in json.load(f)}
        with open(os.path.join(ref, "layout-inventory.json"), encoding="utf-8") as f:
            self.lay = json.load(f)

    def inner(self, p, prefix):
        # 对应包内 svg_native.inner：读 SVG 正文并前缀化
        with open(p, encoding="utf-8") as f:
            s = f.read()
        m = re.search(r"<svg[^>]*>(.*)</svg>", s, re.S)
        return pref(m.group(1), prefix)

    def shape_body(self, cid, prefix):
        # 对应各包 node() 的非 sprite 分支：parts → reused-crate → 原 svgInner
        p = os.path.join(self.root, "parts", "shape-%s.svg" % cid)
        q = os.path.join(self.root, "reference", "reused-crate", "shape-%s.svg" % cid)
        if os.path.isfile(p):
            return self.inner(p, prefix)
        if os.path.isfile(q):
            return self.inner(q, prefix)
        return pref(self.nodes[str(cid)].get("svgInner", ""), prefix + "_")

    def node(self, cid, f=1):
        # 对应各包 node(cid, f, 'new')：帧状态/变色/遮罩语义逐行保留
        global _counter
        _counter += 1
        z = _counter
        a = self.nodes[str(cid)]
        if a["code"] != 39:
            return self.shape_body(cid, "n%d" % z)
        state = a["frames"][(f - 1) % len(a["frames"])]
        body = ""
        masks = []
        for depth, o in sorted(state.items(), key=lambda t: int(t[0])):
            dep = int(depth)
            masks = [v for v in masks if dep <= v[0]]
            if o.get("name") == "area":
                continue
            frag = self.transformed(o, self.node(o["id"], 1 if o["id"] == 254 else f - o["placedAt"] + 1))
            if "clipDepth" in o:
                _counter += 1
                mid = "mask%d" % _counter
                fid = "white%d" % _counter
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

    def transformed(self, o, frag):
        # 对应各包 transformed()/placed()：矩阵 + CXFORM 不变式
        global _counter
        mult = o.get("colorMult", [256] * 4)
        add = o.get("colorAdd", [0] * 4)
        if mult[3] == 0 and add[3] == 0:
            return ""
        if mult != [256] * 4 or add != [0] * 4:
            _counter += 1
            fid = "col%d" % _counter
            filt = ('<filter id="%s" color-interpolation-filters="sRGB"><feComponentTransfer>'
                    % fid + "".join(
                        '<feFunc%s type="linear" slope="%s" intercept="%s"/>'
                        % (c, mult[k] / 256, add[k] / 255)
                        for k, c in enumerate("RGBA")) + "</feComponentTransfer></filter>")
            frag = '<defs>%s</defs><g filter="url(#%s)">%s</g>' % (filt, fid, frag)
        return ('<g transform="matrix(' + " ".join(map(str, o.get("matrix", [1, 0, 0, 1, 0, 0])))
                + ')">' + frag + "</g>")

    # ------------------------------------------------ 几何外包围（viewBox 用）
    def shape_bounds(self, cid):
        d = self.detail.get(cid)
        if d and d.get("viewBox"):
            return [float(v) for v in d["viewBox"]]
        return None

    @staticmethod
    def _xform(m, rect):
        pts = [(rect[0], rect[1]), (rect[0] + rect[2], rect[1]),
               (rect[0], rect[1] + rect[3]), (rect[0] + rect[2], rect[1] + rect[3])]
        xs = [m[0] * px + m[2] * py + m[4] for px, py in pts]
        ys = [m[1] * px + m[3] * py + m[5] for px, py in pts]
        return [min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)]

    def node_bounds(self, cid, f=1, depth_guard=0):
        """节点子树在自身局部坐标的外包围（帧 f）。遮罩件不贡献墨色，跳过。"""
        if depth_guard > 64:
            raise RuntimeError("节点嵌套过深: %s" % cid)
        a = self.nodes[str(cid)]
        if a["code"] != 39:
            return self.shape_bounds(cid)
        state = a["frames"][(f - 1) % len(a["frames"])]
        acc = None
        for _, o in sorted(state.items(), key=lambda t: int(t[0])):
            if o.get("name") == "area" or "clipDepth" in o:
                continue
            mult = o.get("colorMult", [256] * 4)
            add = o.get("colorAdd", [0] * 4)
            if mult[3] == 0 and add[3] == 0:
                continue
            cb = self.node_bounds(o["id"], 1 if o["id"] == 254 else f - o["placedAt"] + 1,
                                  depth_guard + 1)
            if not cb:
                continue
            cb = self._xform(o.get("matrix", [1, 0, 0, 1, 0, 0]), cb)
            if acc is None:
                acc = cb
            else:
                x0 = min(acc[0], cb[0]); y0 = min(acc[1], cb[1])
                acc = [x0, y0, max(acc[0] + acc[2], cb[0] + cb[2]) - x0,
                       max(acc[1] + acc[3], cb[1] + cb[3]) - y0]
        return acc

    def env_objects(self, roles):
        return [o for o in self.lay["worldFirstFrame"] if o.get("role") in roles]

    def root_layers(self):
        return [o for o in (self.lay.get("rootSceneObjects") or [])
                if o.get("role") == "environment_root_layer"]


def write_svg(pkg_root, rel_path, view_box, body):
    out = os.path.join(pkg_root, rel_path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    vb = " ".join(("%.15g" % v) for v in view_box)
    with open(out, "w", encoding="utf-8") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">%s</svg>' % (vb, body))
    return out


def union_rects(rects):
    x0 = min(r[0] for r in rects); y0 = min(r[1] for r in rects)
    return [x0, y0, max(r[0] + r[2] for r in rects) - x0,
            max(r[1] + r[3] for r in rects) - y0]


def build_stage(stage, manifest):
    """装配一张图的全部图层 SVG 并渲染。返回图层/道具清单（供提取器复核）。"""
    global _counter
    pkg = Package(stage)
    produced = {"background": None, "foreground": None, "elevator": None, "props": []}

    # ---- 背景（仅 environment_backdrop，世界坐标外包围为 viewBox）
    bds = pkg.env_objects({"environment_backdrop"})
    assert len(bds) == 1, "%s backdrop 数量异常: %d" % (stage, len(bds))
    o = bds[0]
    _counter = 0
    frag = pkg.transformed(o, pkg.node(o["id"], 1))
    local = pkg.node_bounds(o["id"], 1)
    assert local, "%s backdrop 无外包围" % stage
    world = Package._xform(o.get("matrix", [1, 0, 0, 1, 0, 0]), local)
    world = [round(world[0], 2), round(world[1], 2),
             math.ceil(world[2] * 100) / 100, math.ceil(world[3] * 100) / 100]
    svg_rel = os.path.join("parts", "environment-%s-backdrop.svg" % stage.lower())
    write_svg(pkg.root, svg_rel, world, frag)
    png_name = "background-%d-backdrop.png" % o["id"]
    render_part(pkg.root, os.path.basename(svg_rel), 2.0, manifest)
    src = os.path.join(pkg.root, "baked", os.path.splitext(os.path.basename(svg_rel))[0] + ".png")
    dst = os.path.join(pkg.root, "baked", png_name)
    os.replace(src, dst)
    rec = manifest["renders"].pop(repo_rel(src))
    manifest["renders"][repo_rel(dst)] = rec
    produced["background"] = {"sprite": o["id"], "worldRect": world,
                              "png": repo_rel(dst), "svg": repo_rel(os.path.join(pkg.root, svg_rel))}

    # ---- A10/A13：电梯滚动 tile + 前框前景
    if stage in ELEVATOR:
        spec = ELEVATOR[stage]
        root_layer = pkg.root_layers()[0]
        place = root_layer["matrix"]  # 1876 在根时间轴的放置（gameworld 根矩阵≈identity）
        tile_id = spec["tile"]
        _counter = 0
        tbody = pkg.node(tile_id, 1)
        tvb = pkg.node_bounds(tile_id, 1)
        tile_svg = os.path.join("parts", "elevator-%d-tile.svg" % tile_id)
        write_svg(pkg.root, tile_svg, tvb, tbody)
        render_part(pkg.root, os.path.basename(tile_svg), 2.0, manifest)
        layer_x = round(place[4] + tvb[0], 2)
        layer_y = round(place[5] + tvb[1], 2)
        clip = measure_elevator_clip(pkg, o, spec["front"],
                                     [layer_x, layer_y, tvb[2], tvb[3]])
        produced["elevator"] = {
            "rootSprite": root_layer["id"], "tile": tile_id,
            "png": repo_rel(os.path.join(pkg.root, "baked",
                                         os.path.splitext(os.path.basename(tile_svg))[0] + ".png")),
            "svg": repo_rel(os.path.join(pkg.root, tile_svg)),
            "layerOrigin": [layer_x, layer_y], "logicalSize": [round(tvb[2], 3), round(tvb[3], 3)],
            "loopHeight": ELEVATOR_LOOP_HEIGHT, "clip": clip,
            "rootPlacement": place, "placedAtRootFrame": root_layer.get("placedAt"),
        }
        # 前景 1884（前框/栏杆/上梁遮挡）
        fid = spec["front"]
        fo = next(x for x in pkg.env_objects({"environment_prop_or_animation"})
                  if x["id"] == fid)
        _counter = 0
        fbody = pkg.node(fid, 1)
        fvb = pkg.node_bounds(fid, 1)
        fsvg = os.path.join("parts", "foreground-%d.svg" % fid)
        write_svg(pkg.root, fsvg, fvb, fbody)
        render_part(pkg.root, os.path.basename(fsvg), 2.0, manifest)
        produced["foreground"] = {
            "sprite": fid,
            "png": repo_rel(os.path.join(pkg.root, "baked",
                                         os.path.splitext(os.path.basename(fsvg))[0] + ".png")),
            "svg": repo_rel(os.path.join(pkg.root, fsvg)),
            "worldRect": [round(fo["matrix"][4] + fvb[0], 2), round(fo["matrix"][5] + fvb[1], 2),
                          round(fvb[2], 3), round(fvb[3], 3)],
            "depth": fo["depth"], "matrix": fo["matrix"],
        }

    # ---- 动态道具帧1（电梯图的 1884 已作为前景交付，跳过）
    skip = {ELEVATOR[stage]["front"]} if stage in ELEVATOR else set()
    seen = {}
    for p in pkg.env_objects({"environment_prop_or_animation"}):
        cid = p["id"]
        if cid in skip:
            continue
        if cid not in seen:
            _counter = 0
            body = pkg.node(cid, 1)
            vb = pkg.node_bounds(cid, 1)
            if not vb:
                # 帧1无可视外包围（如 1617 仅 name=area 逻辑子件）：登记而非静默丢弃
                fr = len(pkg.nodes[str(cid)]["frames"]) if pkg.nodes[str(cid)]["code"] == 39 else 1
                seen[cid] = {"error": "帧1无可视外包围（仅 name=area 逻辑子件或空帧，"
                                      "逻辑区域容器非画稿）", "frames": fr}
            else:
                name = "prop-%d-f1" % cid
                write_svg(pkg.root, os.path.join("parts", name + ".svg"), vb, body)
                render_part(pkg.root, name + ".svg", 2.0, manifest)
                frames = len(pkg.nodes[str(cid)]["frames"]) if pkg.nodes[str(cid)]["code"] == 39 else 1
                seen[cid] = {"png": repo_rel(os.path.join(pkg.root, "baked", name + ".png")),
                             "svg": repo_rel(os.path.join(pkg.root, "parts", name + ".svg")),
                             "viewBox": vb, "frames": frames}
        produced["props"].append({
            "id": cid, "depth": p["depth"], "matrix": p["matrix"],
            "name": p.get("name"), "colorMult": p.get("colorMult"),
            **seen[cid]})
    return produced


def measure_elevator_clip(pkg, backdrop_obj, front_id, tile_world):
    """电梯窗口 clip：cabin(backdrop) 与前框(front) 的 alpha 并集对作者视口
    [0,0,600,350] 的补集外包围（实测，非手填）。相对 tile 图层原点返回。
    原包对 1876 无 clipDepth——原作靠层叠遮挡；运行时单矩形 clip 是原型适配，
    遮挡补集外包围保证可见区不被裁掉，cabin/前框不透明区由层顺序继续遮盖。
    """
    _viewport = [0, 0, 600, 350]  # 包 assemble_scene/previews 的 author 视口
    _counter_reset = None
    global _counter
    _counter = 0
    body = pkg.transformed(backdrop_obj, pkg.node(backdrop_obj["id"], 1))
    fo = next(x for x in pkg.env_objects({"environment_prop_or_animation"})
              if x["id"] == front_id)
    body += pkg.transformed(fo, pkg.node(front_id, 1))
    tmp_dir = os.path.join(REPO, "tmp", "cf6-roguelike-20261021", "kimi-maps", "r3", "clip-measure")
    os.makedirs(tmp_dir, exist_ok=True)
    svg_path = os.path.join(tmp_dir, "%s-occluders.svg" % pkg.stage.lower())
    write_svg_path = svg_path
    vb = " ".join(map(str, _viewport))
    with open(write_svg_path, "w", encoding="utf-8") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">%s</svg>' % (vb, body))
    png_path = os.path.join(tmp_dir, "%s-occluders.png" % pkg.stage.lower())
    svgrender.render(svg_path, _viewport[2], png_path)  # 1x 实测 alpha
    from PIL import Image
    with Image.open(png_path) as im:
        im = im.convert("RGBA")
        alpha = im.getchannel("A")
        w, h = im.size
        px = alpha.load()
        xs = []
        ys = []
        for yy in range(h):
            for xx in range(w):
                if px[xx, yy] < 128:  # 遮挡并集之外 = 滚动可见
                    xs.append(xx)
                    ys.append(yy)
    if not xs:
        raise RuntimeError("%s 遮挡补集为空，无法定电梯窗口" % pkg.stage)
    wx0, wy1 = min(xs), max(ys)
    # 世界坐标 = 视口原点(0,0) + 像素（1x）
    clip_world = [float(wx0), float(min(ys)), float(max(xs) - wx0 + 1), float(wy1 - min(ys) + 1)]
    clip = [round(clip_world[0] - tile_world[0], 2), round(clip_world[1] - tile_world[1], 2),
            round(clip_world[2], 2), round(clip_world[3], 2)]
    return {"rect": clip, "worldRect": [round(v, 2) for v in clip_world],
            "basis": ("对 cabin(backdrop)+%d 前框 alpha<128 并集在作者视口 [0,0,600,350] 内"
                      "取补集外包围（1x Chrome 实测，本脚本 measure_elevator_clip）；"
                      "原包 1876 无 clipDepth，原作靠层叠遮挡；此矩形为原型适配，"
                      "保证可见区完整，cabin/前框不透明区由运行时层顺序继续遮盖" % front_id),
            "measureSvg": repo_rel(svg_path), "measurePng": repo_rel(png_path)}


RESULTS = os.path.join(REPO, "tools", "cf6-map-source", "generated", "assemble-r3-results.json")


def main():
    stages = [s for s in sys.argv[1:] if not s.startswith("--")]
    if "--check" in sys.argv:
        return check()
    if not stages:
        print("用法: assemble_layers_r3.py A09 A10 ... | --check", file=sys.stderr)
        return 2
    manifest = {"schema": "cf6-map-source-render-manifest.v1", "renders": {}}
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            manifest = json.load(f)
    results = {}
    if os.path.isfile(RESULTS):
        with open(RESULTS, encoding="utf-8") as f:
            results = json.load(f)["stages"]
    for st in stages:
        print("== assemble", st, flush=True)
        results[st] = build_stage(st, manifest)
        with open(RESULTS, "w", encoding="utf-8") as f:
            json.dump({"schema": "cf6-map-source-assemble-r3.v1", "stages": results},
                      f, ensure_ascii=False, indent=1)
        os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
        with open(MANIFEST, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)
        r = results[st]
        print("   background", r["background"]["worldRect"],
              "| props", len(r["props"]),
              "| elevator" if r["elevator"] else "")
    print("results ->", repo_rel(RESULTS))
    return 0


def check():
    bad = []
    if not os.path.isfile(RESULTS):
        print("尚无", RESULTS, file=sys.stderr)
        return 2
    with open(RESULTS, encoding="utf-8") as f:
        results = json.load(f)["stages"]
    for st, r in sorted(results.items()):
        paths = [r["background"]["png"], r["background"]["svg"]]
        if r.get("foreground"):
            paths += [r["foreground"]["png"], r["foreground"]["svg"]]
        if r.get("elevator"):
            paths += [r["elevator"]["png"], r["elevator"]["svg"]]
            if not (r["elevator"]["loopHeight"] > 0):
                bad.append("%s elevator loopHeight 非法" % st)
            if len(r["elevator"]["clip"]["rect"]) != 4:
                bad.append("%s elevator clip 非法" % st)
        for p in r["props"]:
            paths += [p.get("png"), p.get("svg")]
        for rel in paths:
            if rel and not os.path.isfile(os.path.join(REPO, rel)):
                bad.append("%s 缺失 %s" % (st, rel))
    for b in bad:
        print("ERROR", b)
    print("assemble_r3 check: %d 图, %d 问题" % (len(results), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
