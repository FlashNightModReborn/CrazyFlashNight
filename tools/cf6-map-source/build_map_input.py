#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CF6 地图 map-input 元数据生成器（K3 地图源资产线，r2）。

产出 tools/cf6-map-source/generated/map-input.json，schema=cf6-map-input.v1，
供 tools/cf6-map-runtime（Astra build.py）只读消费。
合同字段（tools/cf6-map-runtime/map-input.v1.json）：
  id；nativeBounds [x,y,w,h]；worldScale（已核=1）；layers[{id,role,sourceKind,
  png,x,y,width,height,depth}]（role: background|foreground|elevator-scroll|
  door-left|door-right；sourceKind: background|isolated-part）；walkBounds；
  spawn；exit{direction,rect}；collisions。
坐标一律原生 world。走区/出生/出口/碰撞合并自 Astra 的
tools/cf6-map-runtime/route-geometry-overrides.json（绑定原 SWF 提取与
原型适配，含 geometryBasis），本生成器不重复解 SWF。
图层 PNG 只来自独立背景/独立部件，不用全景或预览图；像素尺寸可高于逻辑
尺寸（2x 烘焙），运行时按逻辑 width/height 放置一次。
无源码依据的动态件（门动画、出口演出等）列入 undeliveredDynamics 并说明，
不凭空捏造帧数据。

用法：
  python build_map_input.py            # 生成全部已提取关卡
  python build_map_input.py --stage A01 A02
  python build_map_input.py --check    # 校验生成结果引用、尺寸、透明层完整性
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone, timedelta

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MAPS_ROOT = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图")
OUT_DIR = os.path.join(REPO, "tools", "cf6-map-source", "generated")
OUT_FILE = os.path.join(OUT_DIR, "map-input.json")
GEOMETRY_OVERRIDES = os.path.join(REPO, "tools", "cf6-map-runtime", "route-geometry-overrides.json")

# 关卡 -> (revision, 包内项目相对路径)。包根 = MAPS_ROOT/<stage>-<rev>/<pkgRel>
PACKAGES = {
    "A01": ("R4", "cf6-stage1-redraw-r4"),
    "A02": ("R3", "cf6-stage2-redraw-r3"),
    "A03": ("R1", "cf6-stage3-redraw-r1"),
    "A04": ("R1", "cf6-stage4-redraw-r1"),
    "A05": ("R3", "cf6-stage5-redraw-r3"),
    "A06": ("R2", "cf6-stage6-redraw-r2"),
    "A07": ("R2", "cf6-stage7-redraw-r2"),
    "A08": ("R5", ""),  # R5 包无顶层目录
    "A09": ("R2", "cf6-stage9-redraw-r2"),
    "A10": ("R2", "cf6-stage10-redraw-r2"),
    "A11": ("R2", "cf6-stage11-redraw-r2"),
    "A12": ("R2", "cf6-stage12-redraw-r2"),
    "A13": ("R2", "cf6-stage13-redraw-r2"),
    "A14": ("R2", "cf6-stage14-redraw-r2"),
    "A15": ("R2", "cf6-stage15-redraw-r2"),
    "A16": ("R2", "cf6-stage16-redraw-r2"),
    "A17": ("R2", "cf6-stage17-redraw-r2"),
    "A18": ("R2", "cf6-stage18-redraw-r2"),
    "A19": ("R2", "cf6-stage19-redraw-r2"),
    "A20": ("R2", "cf6-stage20-redraw-r2"),
    "A22": ("R2", "cf6-stage22-redraw-r2"),
}

# 原 CF6 各关背景 sprite 在 gameworld 的统一放置（Astra generated/Axx-original-geometry.json
# display depth1 与各包 registration.json worldPlacement 一致）
BG_PLACEMENT = [673.5, 207.1]

WORLD_SCALE_NOTE = ("worldScale=1 已核：CF7 175cm 裸模站姿 145.19 局部px / 原 CF6 man1 "
                    "外框约 134.17px（tools/cf6-map-runtime/README.md 标尺节）；不按屏宽缩放")


def pkg_dir(stage):
    rev, rel = PACKAGES[stage]
    return os.path.join(MAPS_ROOT, "%s-%s" % (stage, rev), rel)


def repo_rel(path):
    return os.path.relpath(path, REPO).replace("\\", "/")


def pkg_rel(stage, *parts):
    return repo_rel(os.path.join(pkg_dir(stage), *parts))


def load_json(stage, *parts):
    with open(os.path.join(pkg_dir(stage), *parts), encoding="utf-8") as f:
        return json.load(f)


def png_size(rel):
    from PIL import Image
    with Image.open(os.path.join(REPO, rel)) as im:
        return list(im.size)


def bg_world_rect(view_box):
    """背景 sprite 局部 viewBox + 统一放置 -> world 矩形 [x,y,w,h]。"""
    return [round(BG_PLACEMENT[0] + view_box[0], 2),
            round(BG_PLACEMENT[1] + view_box[1], 2),
            view_box[2], view_box[3]]


def base_entry(stage):
    rev, _ = PACKAGES[stage]
    return {
        "id": stage,
        "stage": stage,
        "revision": rev,
        "package": repo_rel(pkg_dir(stage)) + "/",
        "nativeBounds": None,
        "worldScale": 1,
        "worldScaleBasis": WORLD_SCALE_NOTE,
        "layers": [],
        "walkBounds": None,
        "spawn": None,
        "exit": None,
        "collisions": [],
        "props": [],
        "undeliveredDynamics": [],
        "deferredLayers": [],
        "unknowns": [],
        "notes": [],
    }


def apply_geometry(e):
    """合并 Astra route-geometry-overrides（只读引用，不重复解 SWF）。"""
    with open(GEOMETRY_OVERRIDES, encoding="utf-8") as f:
        ov = json.load(f)["maps"].get(e["id"])
    if not ov:
        e["unknowns"] += ["walkBounds", "spawn", "exit", "collisions"]
        e["notes"].append("route-geometry-overrides.json 无本图条目，几何标未知")
        return
    for key in ("walkBounds", "spawn", "exit", "collisions",
                "leftSpawnLine", "rightSpawnLine"):
        if key in ov:
            e[key] = ov[key]
    e["geometryStatus"] = ov.get("geometryStatus")
    e["geometryBasis"] = ov.get("geometryBasis")
    e["geometrySource"] = ("tools/cf6-map-runtime/route-geometry-overrides.json"
                           "（Astra 绑定原 SWF/脚本摘要提取；入口/出口为原型适配，"
                           "见 geometryStatus/geometryBasis）")


def layer(stage, lid, role, kind, png_rel, x, y, w, h, depth, source, basis):
    return {
        "id": lid, "role": role, "sourceKind": kind, "png": png_rel,
        "x": round(x, 2), "y": round(y, 2),
        "width": w, "height": h, "depth": depth,
        "pixelSize": png_size(png_rel) if os.path.isfile(os.path.join(REPO, png_rel)) else None,
        "source": source, "basis": basis,
    }


def prop(stage, pid, kind, svg_rel, png_rel, view_box, instances, frames, basis,
         extra=None):
    p = {
        "id": pid, "kind": kind, "svg": svg_rel, "png": png_rel,
        "viewBox": view_box,
        "logicalSize": [round(view_box[2], 3), round(view_box[3], 3)],
        "pixelSize": png_size(png_rel) if png_rel and os.path.isfile(os.path.join(REPO, png_rel)) else None,
        "instances": instances,
        "frames": frames,
        "registration": "original-native-symbol-space；PNG 左上角 world = 实例点 + viewBox 原点",
        "basis": basis,
    }
    if extra:
        p.update(extra)
    return p


# ---------------------------------------------------------------- A01 (R4)
def extract_a01():
    e = base_entry("A01")
    layout = load_json("A01", "source", "scene-layout.json")
    reg = load_json("A01", "baked", "registration.json")
    vb = layout["viewBox"]  # [-3.45,-5.85,800,452] gameworld1592 世界范围
    e["nativeBounds"] = vb
    bw, bh = reg["replacementBitmapSize"]  # 800x452
    m = reg["originalBitmapToShapeMatrix"]
    bx = layout["background_placement"][0] + m[4]
    by = layout["background_placement"][1] + m[5]
    e["layers"].append(layer(
        "A01", "background", "background", "background",
        pkg_rel("A01", "baked", "background-1580-r4-800x452.png"),
        bx, by, bw, bh, 0,
        {"svg": pkg_rel("A01", "parts", "background-1581.svg"),
         "partsSvg": [pkg_rel("A01", "parts", n) for n in [
             "01-night-soil.svg", "02-wreck-pile.svg", "03-metal-floor.svg",
             "04-wall.svg", "05-markings-lights.svg"]],
         "matrix": m,
         "placementInGameworld": layout["background_placement"]},
        "source/scene-layout.json viewBox + baked/registration.json；"
        "reference/scene-identification.txt §二（gameworld1592 世界范围 -3.45,-5.85,800,452）"))
    lamp = layout["lamp_world"]  # [53.2,27.45]；1410/1411 同在 1582 内部 translate(-620.3,-179.65)
    e["layers"].append(layer(
        "A01", "yellow-lamp-glow", "background", "isolated-part",
        pkg_rel("A01", "baked", "prop-1411.png"),
        lamp[0] - 99.9, lamp[1] - 84.75, 199.8, 169.5, 1,
        {"svg": pkg_rel("A01", "parts", "prop-1411.svg"),
         "matrix": [1, 0, 0, 1, -620.3, -179.65],
         "matrixSpace": "symbol-1582 内部 translate；world=background_placement+matrix"},
        "reference/scene-identification.txt §二：光晕1411为原生矢量，与黄灯同在1582内部"
        "translate(-620.3,-179.65)；Chrome 候选烘焙（render-manifest.json）"))
    e["layers"].append(layer(
        "A01", "yellow-lamp", "background", "isolated-part",
        pkg_rel("A01", "baked", "prop-1410.png"),
        lamp[0] - 69, lamp[1] - 12.5, 138, 25, 2,
        {"svg": pkg_rel("A01", "parts", "prop-1410.svg"),
         "matrix": [1, 0, 0, 1, -620.3, -179.65],
         "matrixSpace": "symbol-1582 内部 translate；world=background_placement+matrix"},
        "reference/scene-identification.txt §二：独立黄灯 shape1410→bitmap1409；"
        "source/scene-layout.json lamp_world；Chrome 候选烘焙"))
    e["alternateLayers"] = [
        {"id": "background-without-glow",
         "png": pkg_rel("A01", "baked", "background-1580-r4-without-glow-800x452.png"),
         "note": "无青光晕底图，与独立青晕叠加等价于默认底图"},
        {"id": "cyan-glow",
         "png": pkg_rel("A01", "baked", "cyan-glow-800x452.png"),
         "x": round(bx, 2), "y": round(by, 2), "width": bw, "height": bh,
         "note": "半透明青晕（alpha 0-73），叠加层；源 parts/06-optional-light-glow.svg"},
    ]
    e["props"] = [
        prop("A01", "turret-1591", "dynamic-unit",
             pkg_rel("A01", "parts", "prop-1591.svg"),
             pkg_rel("A01", "baked", "prop-1591.png"),
             [-80, -94.923, 183.175, 97.923],
             [{"x": 133.8, "y": 202.4, "depth": 152},
              {"x": 249.8, "y": 430.9, "depth": 160}],
             18,
             "scene-identification.txt §三B：同一 sprite1591 两份实例；PNG 为重绘首帧"
             "（qa/props-symbol-coordinate-map.json），第12帧枪口效果506保留原矢量未烘"),
        prop("A01", "crate-1442", "breakable-crate",
             pkg_rel("A01", "parts", "prop-1442.svg"),
             pkg_rel("A01", "baked", "prop-1442.png"),
             [-34, -61.5, 68, 63],
             [{"x": 75.1, "y": 427.35, "depth": 212}],
             11,
             "scene-identification.txt §三C：破坏箱11帧，完好1436+破碎1437-1441；"
             "PNG 为完好帧，碎片 SVG 在 parts/shape-1436..1441.svg"),
    ]
    e["notes"] = [
        "隐形地图 shape1583(sprite1584, depth5, alpha=0) 为原逻辑资产；走区/碰撞/出口几何"
        "已由 Astra 从原 SWF 提取（见 geometrySource），本包不再标未知",
        "炮台/破坏箱为游戏单位（原 depth 152/160/212），PNG 交付为首帧独立部件，"
        "由玩法配置生成，不烘入静态底图",
        "baked 底图由画师 Inkscape 管线随包交付；道具 PNG 为本机 Chrome headless 候选烘焙",
    ]
    return e


# ---------------------------------------------------------------- A02 (R3)
def extract_a02():
    e = base_entry("A02")
    reg = load_json("A02", "baked", "registration.json")
    flat = reg["optionalFlattenedBackground"]
    rect = bg_world_rect(flat["nativeViewBox"])  # [-43.45,24.1,1330.9,469.8]
    e["nativeBounds"] = rect
    e["layers"].append(layer(
        "A02", "background", "background", "background",
        pkg_rel("A02", "baked", "background-1613.png"),
        rect[0], rect[1], rect[2], rect[3], 0,
        {"svg": pkg_rel("A02", "parts", "background-1613.svg"),
         "viewBox": flat["nativeViewBox"],
         "placementInGameworld": flat["worldPlacement"]},
        "baked/registration.json optionalFlattenedBackground：保持原生 viewBox 比例，"
        "不拉伸到逻辑1250x450；已含全部机械/废墟/土材质，不含根天空/城市/交互箱"))
    city = reg["optionalCityLayer"]
    cv = city["nativeViewBox"]
    e["layers"].append(layer(
        "A02", "city-parallax", "background", "isolated-part",
        pkg_rel("A02", "baked", "city-shape-1598.png"),
        cv[0], cv[1], cv[2], cv[3], 1,
        {"svg": pkg_rel("A02", "parts", "shape-1598.svg"),
         "viewBox": cv},
        "baked/registration.json optionalCityLayer：根级独立视差层，原半速横移；"
        "原型按初始相位(-0.75,-1)静态压平（README.txt），视差行为待运行时决定"))
    e["props"] = [
        prop("A02", "crate-1442", "breakable-crate",
             pkg_rel("A02", "parts", "prop-1442.svg"),
             pkg_rel("A02", "baked", "prop-1442.png"),
             [-34, -61.5, 68, 63],
             [{"x": 488.55, "y": 274.4, "depth": 499}],
             11,
             "README.txt：箱1442及6片clip沿用首关素材与原逻辑；实例位置/depth 见 "
             "tools/cf6-map-runtime/generated/A02-original-geometry.json display"),
    ]
    e["deferredLayers"] = [
        {"id": "sky", "png": pkg_rel("A02", "baked", "bitmap-1595.png"),
         "note": "原作为屏幕固定层 600x187（registration.json sky 项），无世界坐标注册；"
                 "不虚构世界放置，是否以 CF7 天空/静态层补偿由主控决定"},
    ]
    e["notes"] = [
        "逻辑地图 1250x450，完整视觉外包围 1330.9x469.8（SCOPE.txt）；nativeBounds 取后者",
        "天空缺失区在底图为透明；环境若 DisableSky 将显黑，见 deferredLayers",
    ]
    return e


# ---------------------------------------------------------------- A03/A04/A05 同构室内
def extract_interior(stage, bg_svg, door_notes, props, extra_notes):
    e = base_entry(stage)
    reg = load_json(stage, "baked", "registration.json")
    bg = reg["background"]
    rect = bg_world_rect(bg["viewBox"])
    e["nativeBounds"] = rect
    e["layers"].append(layer(
        stage, "background", "background", "background",
        pkg_rel(stage, "baked", bg["png"]),
        rect[0], rect[1], rect[2], rect[3], 0,
        {"svg": pkg_rel(stage, "parts", bg_svg),
         "viewBox": bg["viewBox"],
         "placementInGameworld": bg["worldPlacement"]},
        "baked/registration.json background：含墙灯与原光晕（includesWallLightsAndOriginalGlow）"))
    fg = reg["foreground"]
    fv = fg["viewBox"]
    e["layers"].append(layer(
        stage, "foreground", "foreground", "isolated-part",
        pkg_rel(stage, "baked", fg["png"]),
        fv[0], fv[1], fv[2], fv[3], 10,
        {"svg": pkg_rel(stage, "parts", "foreground-1727.svg"),
         "viewBox": fv,
         "cameraParallax": fg.get("cameraParallax")},
        "baked/registration.json foreground：顶部前景遮挡带，原 cameraParallax 1.2；"
        "原型静态压平，视差行为待运行时决定"))
    e["props"] = props
    e["undeliveredDynamics"] = door_notes
    e["notes"] = [
        "worldLogicalSize %s，视口 600x350（registration.json）" % reg.get("worldLogicalSize"),
        "门/出口演出帧与矩阵保留在原包记录（registration.json 各项），包未烘 PNG；"
        "机制以 CF7 标准手动出口（geometrySource 原型适配）",
    ] + extra_notes
    return e


def crate_prop_via_a01(stage, x, y, depth):
    return prop(stage, "crate-1442", "breakable-crate",
                pkg_rel("A01", "parts", "prop-1442.svg"),
                pkg_rel("A01", "baked", "prop-1442.png"),
                [-34, -61.5, 68, 63],
                [{"x": x, "y": y, "depth": depth}],
                11,
                "同一原符号1442；本包 reference/reused-crate/shape-1436..1441.svg 为同源碎片，"
                "装配 PNG 复用 A01-R4 烘焙；实例位置/depth 见 tools/cf6-map-runtime/generated/"
                "%s-original-geometry.json display" % stage)


def extract_a03():
    return extract_interior(
        "A03", "background-1706.svg",
        [{"id": "door1714", "world": [536.45, 114.95], "depth": 21, "frames": 9,
          "basis": "registration.json door1714（9原帧/矩阵/clipDepth 保留）；"
                   "geometry display depth21 name door1", "reason": "包未烘门帧 PNG"},
         {"id": "exit1720", "world": [1198.4, 112.4], "depth": 28, "frames": 174,
          "basis": "registration.json exit1720（174原帧含角色与遮罩，仅静态采样）",
          "reason": "出口演出不烘入静态底图"}],
        [crate_prop_via_a01("A03", 378.1, 444.0, 349)],
        [])


def extract_a04():
    return extract_interior(
        "A04", "background-1728.svg",
        [{"id": "door1714-1", "world": [536.45, 114.95], "depth": 21, "frames": 9,
          "basis": "registration.json door1714；geometry display depth21 name door1",
          "reason": "包未烘门帧 PNG"},
         {"id": "door1714-2", "world": [945.45, 114.95], "depth": 89, "frames": 9,
          "basis": "geometry display depth89 name door2", "reason": "包未烘门帧 PNG"},
         {"id": "arrival1729", "world": [668.45, 226.95], "depth": 96, "frames": 174,
          "basis": "registration.json arrival1729/arrivalOverridesRealPlayer",
          "reason": "入场演出不烘入静态底图"},
         {"id": "barrel1736", "world": [[816.7, 204.95], [1070.7, 204.95], [403.75, 208.95]],
          "depth": [336, 343, 350], "frames": 16,
          "basis": "registration.json barrel1736（16原帧，新材质经原碎片clip）；"
                   "材质 baked/bitmap-1731.png 已交付",
          "reason": "桶体帧序列未装配为 PNG"}],
        [],
        [])


def extract_a05():
    return extract_interior(
        "A05", "background-1745.svg",
        [{"id": "grandDoor1750", "world": [653.7, 112.95], "depth": 88, "frames": 40,
          "basis": "registration.json grandDoor1750（40原帧，原depth）；geometry display depth88",
          "reason": "包未烘大门帧 PNG"},
         {"id": "arrival1729", "world": [1190.45, 231.4], "depth": 26, "frames": 174,
          "basis": "registration.json arrival1729/arrivalOverridesRealPlayer",
          "reason": "入场演出不烘入静态底图"}],
        [crate_prop_via_a01("A05", 288.7, 230.5, 474)],
        [])


# ---------------------------------------------------------------- A06 (R2)
def extract_a06():
    e = base_entry("A06")
    vb = [-676.95, -240.5, 1522.95, 483.3]  # parts/background-1762.svg viewBox
    rect = bg_world_rect(vb)  # [-3.45,-33.4,1522.95,483.3]
    e["nativeBounds"] = rect
    e["layers"].append(layer(
        "A06", "background", "background", "background",
        pkg_rel("A06", "baked", "background-1762.png"),
        rect[0], rect[1], rect[2], rect[3], 0,
        {"svg": pkg_rel("A06", "parts", "background-1762.svg"),
         "viewBox": vb,
         "placementInGameworld": BG_PLACEMENT},
        "source/assemble_scene.py：node(1762) 独立背景 sprite（不含天空1754），"
        "viewBox 即包内写盘值；bake.py 以 2x(3046px) 渲染；本轮真实 scipy 重建"))
    e["deferredLayers"] = [
        {"id": "sky", "svg": "sprite 1754（包 reference/environment-original-nodes.json）",
         "png": pkg_rel("A06", "baked", "bitmap-1740.png"),
         "note": "天空为独立 sprite，包预览按 translate(400,73.5) 屏幕位放置、宽景才横向延展；"
                 "无世界注册依据，不虚构放置（assemble_scene.py 注释）"},
    ]
    e["undeliveredDynamics"] = [
        {"id": "sprite1585", "world": [[5.0, 305.45], [1491.7, 305.45]], "depth": [91, 93],
         "basis": "geometry display depth91/93 id1585；本包未识别其语义/未重绘",
         "reason": "无源码依据，标未知"},
    ]
    e["notes"] = [
        "R2 范围仅 bitmap1753 返修（README-R2.txt）；boss/翅膀/对话框为原角色逻辑资产，不在地图层",
        "A06 机制为战斗后 90 帧转场（Astra README 机关表），无门/电梯图层要求",
    ]
    return e


# ---------------------------------------------------------------- A08 (R5)
def extract_a08():
    e = base_entry("A08")
    # 包声明逻辑世界 1150x410，根 gameworld 矩阵≈identity（reference/layout-inventory.json）
    e["nativeBounds"] = [0, 0, 1150, 410]
    e["layers"].append(layer(
        "A08", "background", "background", "background",
        pkg_rel("A08", "baked", "background-1825-backdrop.png"),
        0, 0, 1150, 410, 0,
        {"svg": pkg_rel("A08", "parts", "environment-a8-backdrop.svg"),
         "rootWorldMatrix": [1.000030517578125, 0, 0, 1.0, 0.0, 0.0]},
        "tools/cf6-map-source/assemble_a08_backdrop.py：仅 role=environment_backdrop "
        "（sprite1825，含赛车1823/通风口/墙面等新材质），按 layout-inventory 根矩阵一次应用；"
        "动态件（门1430/摄像头1832/桶1838/箱1442）不烘入底图"))
    e["props"] = [
        prop("A08", "door-1430", "animated-door",
             pkg_rel("A08", "parts", "prop-1430-f1.svg"),
             pkg_rel("A08", "baked", "prop-1430-f1.png"),
             [-85, -145, 170, 315],
             [{"x": 688.75, "y": 116.2, "depth": 120,
               "colorMult": [210, 210, 210, 256]}],
             59,
             "README.md：59帧滑门1430保留在参考时间轴；PNG 为帧1静态候选；"
             "实例见 A08-original-geometry.json display depth120"),
        prop("A08", "camera-1832", "animated-prop",
             pkg_rel("A08", "parts", "prop-1832-f1.svg"),
             pkg_rel("A08", "baked", "prop-1832-f1.png"),
             [-90, -60, 180, 120],
             [{"x": 515.5, "y": 0.95, "depth": 118}],
             147,
             "README.md：147帧悬挂摄像头1832（含镜像三态，原矩阵保留）；PNG 为帧1"),
        prop("A08", "barrel-1838", "animated-prop",
             pkg_rel("A08", "parts", "prop-1838-f1.svg"),
             pkg_rel("A08", "baked", "prop-1838-f1.png"),
             [-190, -75, 380, 130],
             [{"x": 1096.4, "y": 182.2, "depth": 137},
              {"x": 1146.4, "y": 184.2, "depth": 144},
              {"x": 450.4, "y": 173.15, "depth": 151}],
             16,
             "README.md：16帧生化桶1838（RGB闪烁/碎片clip保留）；PNG 为帧1"),
        prop("A08", "crate-1442", "breakable-crate",
             pkg_rel("A01", "parts", "prop-1442.svg"),
             pkg_rel("A01", "baked", "prop-1442.png"),
             [-34, -61.5, 68, 63],
             [{"x": 932.5, "y": 228.2, "depth": 130},
              {"x": 1018.5, "y": 225.2, "depth": 205}],
             11,
             "README.md：reused six crate shape1436-1441；装配 PNG 复用 A01-R4 同符号烘焙"),
    ]
    e["notes"] = [
        "R5 范围仅赛车1823返修；其余环境材质沿用 R2（README-R5.txt）",
        "本关无根天空层（README.md）；逻辑世界 1150x410 小于 walkBounds 上限 "
        "1250/500——walk/exit 为 Astra 原型适配值，按 geometryBasis 消费",
    ]
    return e


EXTRACTORS = {"A01": extract_a01, "A02": extract_a02, "A03": extract_a03,
              "A04": extract_a04, "A05": extract_a05, "A06": extract_a06,
              "A08": extract_a08}


# ---------------------------------------------------------------- r3 通用（A09-A20/A22）
ASSEMBLE_R3 = os.path.join(OUT_DIR, "assemble-r3-results.json")

# 道具中性命名：仅有原作/前轮证据的给语义名，其余保持 sprite-<cid> 不臆测
PROP_NAMES = {1442: "crate-1442", 1430: "door-1430", 1862: "door-1862",
              1832: "camera-1832", 1838: "barrel-1838"}
PROP_KINDS = {1442: "breakable-crate", 1430: "animated-door", 1862: "animated-door"}


def load_assemble_r3():
    with open(ASSEMBLE_R3, encoding="utf-8") as f:
        return json.load(f)["stages"]


# 根时间轴 ui_overlay（layout-inventory.json rootSceneObjects，非环境层，无世界注册）
UI_OVERLAY_ROOT = {
    "A15": [{"id": "ui-gogogo-1700",
             "note": "根时间轴 ui_overlay（placedAt 帧157，translate(308.5,76.45)，"
                     "9帧，role=ui_overlay，name=gogogo）；非环境层，无世界注册依据，"
                     "不虚构放置（演出/UI 资产，待主控决策归属）"}],
    "A17": [{"id": "ui-overlay-1783",
             "note": "根时间轴 ui_overlay（placedAt 帧169，translate(111,23)，1帧，"
                     "role=ui_overlay）；非环境层，无世界注册依据，不虚构放置"}],
}


def extract_r3(stage):
    """A09-A20/A22 通用提取：图层/道具来自 assemble_layers_r3.py 实测产物清单，
    几何来自 route-geometry-overrides（apply_geometry）。"""
    e = base_entry(stage)
    res = load_assemble_r3()[stage]
    bg = res["background"]
    rect = list(bg["worldRect"])
    e["layers"].append(layer(
        stage, "background", "background", "background",
        bg["png"], rect[0], rect[1], rect[2], rect[3], 1,
        {"svg": bg["svg"], "backdropSprite": bg["sprite"],
         "placementInGameworld": "layout-inventory.json worldFirstFrame environment_backdrop"},
        "assemble_layers_r3.py：仅 environment_backdrop 子树（sprite %d），"
        "viewBox=世界外包围（保留超出逻辑世界的原画延伸）；2x Chrome 候选烘焙" % bg["sprite"]))
    union = [rect]
    if res.get("elevator"):
        ev = res["elevator"]
        lo = ev["layerOrigin"]
        ls = ev["logicalSize"]
        e["layers"].append(layer(
            stage, "elevator-scroll", "elevator-scroll", "isolated-part",
            ev["png"], lo[0], lo[1], ls[0], ls[1], 0,
            {"svg": ev["svg"], "rootSprite": ev["rootSprite"], "tile": ev["tile"],
             "rootPlacement": ev["rootPlacement"],
             "placedAtRootFrame": ev["placedAtRootFrame"],
             "clipBasis": ev["clip"]["basis"],
             "clipMeasure": {"svg": ev["clip"]["measureSvg"], "png": ev["clip"]["measurePng"]}},
            "qa/elevator-state-guidance.json：1876 共37帧/双 tile/间隔541.95，勿冻入背景；"
            "tile 为隔离 1875 子件，loopHeight=541.95 原生"))
        e["layers"][-1]["loopHeight"] = ev["loopHeight"]
        e["layers"][-1]["clip"] = ev["clip"]["rect"]
        union.append([lo[0], lo[1], ls[0], ls[1]])
        e["notes"].append(
            "电梯滚动层在原作置于根时间轴第 %s 帧（depth1），坐标根≈世界"
            "（gameworld 根矩阵≈identity）；运行时 37 位置循环由 Cf6MapMechanism 驱动"
            % ev["placedAtRootFrame"])
    if res.get("foreground"):
        fg = res["foreground"]
        fr = fg["worldRect"]
        e["layers"].append(layer(
            stage, "foreground", "foreground", "isolated-part",
            fg["png"], fr[0], fr[1], fr[2], fr[3], 10,
            {"svg": fg["svg"], "sprite": fg["sprite"],
             "matrix": fg["matrix"], "originalDepth": fg["depth"]},
            "layout-inventory.json worldFirstFrame depth %d：1884 前框/栏杆/上梁为独立"
            "前景遮挡（电梯窗口的前侧遮罩），未烘入底图" % fg["depth"]))
        union.append(fr)
    x0 = min(r[0] for r in union); y0 = min(r[1] for r in union)
    e["nativeBounds"] = [round(x0, 2), round(y0, 2),
                         round(max(r[0] + r[2] for r in union) - x0, 2),
                         round(max(r[1] + r[3] for r in union) - y0, 2)]
    for p in res["props"]:
        if "error" in p:
            e["unknowns"].append("prop %d: %s" % (p["id"], p["error"]))
            continue
        inst = {"x": p["matrix"][4], "y": p["matrix"][5], "depth": p["depth"]}
        if p["matrix"][:4] != [1, 0, 0, 1]:
            inst["matrix"] = p["matrix"]
        if p.get("colorMult") and p["colorMult"] != [256] * 4:
            inst["colorMult"] = p["colorMult"]
        if p.get("name"):
            inst["name"] = p["name"]
        pid = PROP_NAMES.get(p["id"], "sprite-%d" % p["id"])
        # 同图同 sprite 多实例合并为一个 prop 条目
        existing = next((x for x in e["props"] if x["id"] == pid), None)
        if existing:
            existing["instances"].append(inst)
            continue
        e["props"].append(prop(
            stage, pid, PROP_KINDS.get(p["id"], "animated-prop"),
            p["svg"], p["png"], p["viewBox"], [inst], p["frames"],
            "layout-inventory.json worldFirstFrame environment_prop_or_animation；"
            "帧1独立部件 PNG（2x Chrome 候选），原帧序列 %d 帧未逐帧烘焙" % p["frames"],
            {"delivery": "frame1-only"}))
    # 根级 ui_overlay（非环境层，不虚构世界放置，仅登记来源）
    for ov in UI_OVERLAY_ROOT.get(stage, []):
        e["deferredLayers"].append(ov)
    # A18/A20 根级固定层 1956：屏幕锚定 600x200，无世界注册（同 A02 天空先例）
    if stage in ("A18", "A20"):
        e["deferredLayers"] = [
            {"id": "root-1956",
             "note": "根时间轴固定层（placedAt %s，translate(300,75)，源 600x200）；"
                     "包 rebuild.py panorama_note：fixed root 1956 covers only source "
                     "600x200 and is never repeated or stretched；无世界注册依据，"
                     "不虚构放置（同 A02 天空先例，待主控决策补偿）"
                     % ("178" if stage == "A18" else "188")}]
    e["notes"].append("世界逻辑尺寸见包 layout-inventory worldLoad.logicalBackgroundSize；"
                      "全部 PNG 为 Chrome headless 候选烘焙（render-manifest.json）")
    return e


for _s in ("A09", "A10", "A11", "A12", "A13", "A14", "A15", "A16", "A17",
           "A18", "A19", "A20", "A22"):
    EXTRACTORS[_s] = (lambda s: lambda: extract_r3(s))(_s)


# ---------------------------------------------------------------- check
LAYER_ID_RE = re.compile(r"[a-z][a-z0-9-]{0,47}")


def check(doc):
    from PIL import Image
    errors, warnings = [], []
    roles = {"background", "foreground", "elevator-scroll", "door-left", "door-right"}
    kinds = {"background", "isolated-part"}
    for stage, e in sorted(doc["maps"].items()):
        nb = e.get("nativeBounds")
        if not nb or len(nb) != 4 or nb[2] <= 0 or nb[3] <= 0:
            errors.append("%s: nativeBounds 缺失/非法" % stage)
        if e.get("worldScale") != 1:
            warnings.append("%s: worldScale=%r（已核应为1）" % (stage, e.get("worldScale")))
        bgs = [ly for ly in e.get("layers", []) if ly.get("role") == "background"]
        if not bgs:
            errors.append("%s: 无 background 图层" % stage)
        for field, n in (("walkBounds", 4), ("spawn", 2)):
            v = e.get(field)
            if not (isinstance(v, list) and len(v) == n):
                errors.append("%s: %s 缺失" % (stage, field))
        wb = e.get("walkBounds")
        sp = e.get("spawn")
        if wb and sp and not (wb[0] <= sp[0] <= wb[2] and wb[1] <= sp[1] <= wb[3]):
            errors.append("%s: spawn 不在 walkBounds 内" % stage)
        ex = e.get("exit") or {}
        if not (isinstance(ex.get("rect"), list) and len(ex["rect"]) == 4
                and ex["rect"][0] < ex["rect"][2] and ex["rect"][1] < ex["rect"][3]
                and ex.get("direction") in ("左", "右", "上", "下")):
            errors.append("%s: exit 非法" % stage)
        for poly in e.get("collisions", []):
            if len(poly) < 3:
                errors.append("%s: 碰撞多边形少于3点" % stage)
        seen_ids = set()
        for ly in e.get("layers", []):
            lid = ly.get("id", "")
            if not LAYER_ID_RE.fullmatch(lid):
                errors.append("%s/%s: layer id 不合合同正则" % (stage, lid))
            if lid in seen_ids:
                errors.append("%s: layer id 重复 %s" % (stage, lid))
            seen_ids.add(lid)
            if ly.get("role") not in roles:
                errors.append("%s/%s: 非法 role %r" % (stage, lid, ly.get("role")))
            if ly.get("sourceKind") not in kinds:
                errors.append("%s/%s: 非法 sourceKind %r" % (stage, lid, ly.get("sourceKind")))
            png = os.path.join(REPO, ly.get("png", ""))
            if not os.path.isfile(png):
                errors.append("%s/%s: PNG 不存在 %s" % (stage, lid, ly.get("png")))
                continue
            with Image.open(png) as im:
                if im.mode != "RGBA":
                    errors.append("%s/%s: PNG 非 RGBA" % (stage, lid))
                pw, ph = im.size
                lw, lh = ly.get("width"), ly.get("height")
                if pw < lw - 1 or ph < lh - 1:
                    warnings.append("%s/%s: PNG 像素 %sx%s 低于逻辑 %sx%s"
                                    % (stage, lid, pw, ph, lw, lh))
                if abs(pw / ph - lw / lh) > 0.02 * (lw / lh):
                    errors.append("%s/%s: PNG 宽高比 %s 与逻辑 %sx%s 不符"
                                  % (stage, lid, im.size, lw, lh))
                if ly.get("role") in ("foreground", "elevator-scroll",
                                      "door-left", "door-right"):
                    a = im.getchannel("A").getextrema()
                    if a[0] >= 255:
                        errors.append("%s/%s: 遮挡/动态层不应全不透明" % (stage, lid))
            src = ly.get("source", {})
            for key in ("svg", "json"):
                if key in src and isinstance(src[key], str):
                    if not os.path.isfile(os.path.join(REPO, src[key])):
                        errors.append("%s/%s: 源文件缺失 %s" % (stage, lid, src[key]))
            for psvg in src.get("partsSvg", []):
                if not os.path.isfile(os.path.join(REPO, psvg)):
                    errors.append("%s/%s: parts SVG 缺失 %s" % (stage, lid, psvg))
        for pr in e.get("props", []):
            for key in ("svg", "png"):
                v = pr.get(key)
                if v and not os.path.isfile(os.path.join(REPO, v)):
                    errors.append("%s/prop %s: 缺失 %s" % (stage, pr.get("id"), v))
        for field in ("walkBounds", "spawn", "exit"):
            if e.get(field) is None and field not in e.get("unknowns", []):
                warnings.append("%s: %s 为 null 但未列入 unknowns" % (stage, field))
    return errors, warnings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    if args.check:
        if not os.path.isfile(OUT_FILE):
            print("尚未生成 %s" % OUT_FILE, file=sys.stderr)
            return 2
        with open(OUT_FILE, encoding="utf-8") as f:
            doc = json.load(f)
        errors, warnings = check(doc)
        for w in warnings:
            print("WARN  " + w)
        for er in errors:
            print("ERROR " + er)
        print("check: %d error(s), %d warning(s)" % (len(errors), len(warnings)))
        return 1 if errors else 0

    stages = args.stage or sorted(EXTRACTORS)
    unknown = [s for s in stages if s not in EXTRACTORS]
    if unknown:
        print("尚无提取器: %s" % unknown, file=sys.stderr)
        return 2

    doc = {"schema": "cf6-map-input.v1",
           "generatedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
           "generator": "tools/cf6-map-source/build_map_input.py",
           "sourceManifest": repo_rel(os.path.join(MAPS_ROOT, "input-manifest.json")),
           "geometryOverrides": repo_rel(GEOMETRY_OVERRIDES),
           "coordinateSpace": "native world (gameworld 坐标, worldScale=1)",
           "maps": {}}
    if os.path.isfile(OUT_FILE):
        with open(OUT_FILE, encoding="utf-8") as f:
            doc["maps"] = json.load(f)["maps"]
    for s in stages:
        e = EXTRACTORS[s]()
        apply_geometry(e)
        doc["maps"][s] = e
        print("extracted", s)
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    print("written", repo_rel(OUT_FILE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
