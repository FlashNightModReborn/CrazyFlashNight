"""CF6 教学室背景装配：现役矢量元件最小闭包 → 原生 XFL 源 + 环境/地图片段。

只确定性装配源文件；不调用 CS6、不生成或修改任何 SWF、不改源库与其他工具输入。
原教学美术不在 21 图源包内，本工具按 layout.json 用现役宿舍房间壳/高架床/工作台/门灯
矢量元件近似重组教学室，布局（行走带、出生、右侧出口、灯位）取自原作提取事实；
近似处逐条写入 provenance.json，不声称画面与原作等价。

用法：
    python -X utf8 -B tools/cf6-tutorial/assemble.py          # 生成/刷新全部产物
    python -X utf8 -B tools/cf6-tutorial/assemble.py --check  # 只读核对：源SHA、布局、闭包、产物确定性
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools/asset-metrology"))
sys.path.insert(0, str(ROOT / "tools/cf6-map-runtime"))
import geometry  # cf6-map-runtime 的纯几何原语（不执行 AS）
from xfl_geometry import Geometry, bounds as contour_bounds, segments as edge_segments

spec = importlib.util.spec_from_file_location("map_xml", ROOT / "tools/rhino-map-assets/build.py")
x = importlib.util.module_from_spec(spec)
spec.loader.exec_module(x)
NS, ET = x.NS, x.ET

PREFIX = "Tutorial/"
COMPOSITE = PREFIX + "教学室场景"
TARGET = ROOT / "flashswf/backgrounds/cf6/CF6_Tutorial_BG"
A01 = ROOT / "flashswf/backgrounds/cf6/CF6_A01_BG"
LAYOUT = HERE / "layout.json"
EVIDENCE = HERE / "original-tutorial-geometry.json"
ARCHIVE = HERE / "archive/r9-placeholder/hashes.json"

# 与已运行 CF6_A01_BG 第二帧完全一致的所有权/active guard；独立预览时条件不成立、不烘焙。
GUARD = ('stop();if(_root.gameworld!=undefined && (this===_root.gameworld.背景 || this._parent===_root.gameworld.背景) && '
         '_root._saveExt.bookRun.bookId=="cf6-sting" && _root._saveExt.bookRun.routeId=="historical" && '
         '_root._saveExt.bookRun.outcome=="active" && typeof _root.贴背景图=="function") _root.贴背景图(true);')


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fmt(value):
    return "%g" % round(float(value), 2)


def source_index():
    """每个源库独立索引；子引用只在父元件所属库内解析，不跨库猜名。"""
    index = {}
    for lib in ("flashswf/levels/基地场景合集", "flashswf/arts/new/素材库-地图元件"):
        directory = ROOT / lib / "LIBRARY"
        index[lib] = {path.relative_to(directory).as_posix()[:-4]: path
                      for path in directory.rglob("*.xml")}
    return index


def freeze(name, group, lib, index, symbols, provenance, stats, seen=None):
    """复制源元件为单帧 Graphic：去脚本、去 linkage、帧冻结到 index 0。"""
    if seen is None:
        seen = {}
    target = PREFIX + group + "-" + name.rsplit("/", 1)[-1]
    if name in seen:
        assert seen[name] == target, "同一源元件进入两个组：" + name
        return seen[name]
    if target in symbols:
        return target
    path = index[lib][name]
    r = x.read(path)
    stats["sourceFiles"].append(path)
    r.set("name", target)
    r.set("itemID", x.item_id(target))
    if r.get("symbolType") == "button":
        stats["convertedButtons"] += 1
    r.set("symbolType", "graphic")
    for key in list(r.attrib):
        if key.startswith("linkage"):
            del r.attrib[key]
            stats["removedLinkageAttrs"] += 1
    timeline = r.find("./x:timeline/x:DOMTimeline", NS)
    timeline.set("name", target.rsplit("/", 1)[-1])
    timeline.attrib.pop("currentFrame", None)
    layers = timeline.find("x:layers", NS)
    for lyr in list(layers):
        if lyr.get("layerType") in ("guide", "folder"):
            continue
        frames = lyr.find("x:frames", NS)
        keep = [f for f in frames if int(f.get("index", 0)) == 0]
        if not keep:
            layers.remove(lyr)  # 按钮空层等无内容层不进闭包
            stats["droppedEmptyLayers"] += 1
            continue
        for f in list(frames):
            if f not in keep:
                frames.remove(f)
        for f in keep:
            f.set("index", "0")
            f.set("duration", "1")
            f.attrib.pop("tweenType", None)
            for script in f.findall(".//x:Actionscript", NS):
                script.getparent().remove(script)
                stats["strippedScripts"] += 1
    symbols[target] = r
    seen[name] = target
    provenance.append({"sourceSymbol": name,
                       "sourceFile": str(path.relative_to(ROOT)).replace("\\", "/"),
                       "sourceSha256": sha256(path),
                       "staticSymbol": target})
    for inst in r.findall(".//x:DOMSymbolInstance", NS):
        inst.set("libraryItemName", freeze(inst.get("libraryItemName"), group, lib, index, symbols, provenance, stats, seen))
        if inst.get("symbolType") == "button":
            stats["convertedButtons"] += 1
        inst.set("symbolType", "graphic")
        inst.set("loop", "single frame")
        inst.set("firstFrame", "0")
        inst.attrib.pop("name", None)
        inst.attrib.pop("selected", None)
        inst.attrib.pop("isSelected", None)
    return target


def measure(path):
    library = path.parent
    while library.name != "LIBRARY":
        library = library.parent
    g = Geometry(library)
    return contour_bounds(list(g.symbol(path.relative_to(library).as_posix()[:-4])))


def instance(name, matrix, with_point=True):
    obj = ET.Element(x.tag("DOMSymbolInstance"), libraryItemName=name,
                     symbolType="graphic", loop="single frame", firstFrame="0")
    ET.SubElement(ET.SubElement(obj, x.tag("matrix")), x.tag("Matrix"),
                  **{k: format(v, ".12g") for k, v in matrix.items()})
    if with_point:
        ET.SubElement(ET.SubElement(obj, x.tag("transformationPoint")), x.tag("Point"))
    return obj


def build_symbols(layout):
    """返回 (symbols, placements, stats, provenance)：复制闭包 + 组合教学室场景。"""
    index = source_index()
    symbols, provenance = {}, []
    stats = {"strippedScripts": 0, "convertedButtons": 0, "removedLinkageAttrs": 0,
             "droppedEmptyLayers": 0, "sourceFiles": []}
    m = layout["dormToWorld"]
    s, mtx, mty = m["scale"], m["tx"], m["ty"]
    placements = []
    for p in layout["placements"]:
        lib = p["source"]["xfl"]
        target = freeze(p["source"]["item"], p["group"], lib, index, symbols, provenance, stats)
        natural = measure(index[lib][p["source"]["item"]])
        if "dorm" in p:
            dx, dy = p["dorm"]
            matrix = {"a": s, "b": 0, "c": 0, "d": s, "tx": s * dx + mtx, "ty": s * dy + mty}
        elif "worldTopLeft" in p:
            matrix = {"a": s, "b": 0, "c": 0, "d": s,
                      "tx": p["worldTopLeft"][0] - s * natural[0], "ty": p["worldTopLeft"][1] - s * natural[1]}
        elif "worldBottomRight" in p:
            matrix = {"a": s, "b": 0, "c": 0, "d": s,
                      "tx": p["worldBottomRight"][0] - s * natural[2], "ty": p["worldBottomRight"][1] - s * natural[3]}
        else:
            raise ValueError("未知摆放锚点：" + p["role"])
        world = [matrix["a"] * natural[0] + matrix["tx"], matrix["d"] * natural[1] + matrix["ty"],
                 matrix["a"] * natural[2] + matrix["tx"], matrix["d"] * natural[3] + matrix["ty"]]
        placements.append({"role": p["role"], "symbol": target, "matrix": matrix,
                           "naturalBounds": [round(v, 2) for v in natural],
                           "worldBounds": [round(v, 2) for v in world],
                           "evidence": p["evidence"]})
    order = ["门灯", "门", "工作台", "高架床", "房间壳"]
    layers = []
    for group in order:
        elements = [instance(p["symbol"], p["matrix"]) for p in placements
                    if p["symbol"].startswith(PREFIX + group + "-")]
        assert elements, group
        layers.append(x.layer(group, elements))
    symbols[COMPOSITE] = x.symbol(COMPOSITE, layers)
    return symbols, placements, stats, provenance


def build_geometry(layout):
    """原碰撞实心（墙）减行走孔洞 → 无孔凸多边形；出生/出口/出生线沿用原型适配管线。"""
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    wb = layout["world"]["walkBounds"]
    paths, notes = geometry.collision_paths(evidence)
    # 与 route 覆盖同一语义：偶奇填充即阻挡；行走带是实心外轮廓内的孔洞。
    blocked_paths = paths
    collisions = geometry.filled_trapezoids(blocked_paths, wb)
    spawn, adjusted = geometry.safe_spawn(layout["spawn"], wb, blocked_paths)
    exit_spec = geometry.manual_exit(wb, blocked_paths)
    left = geometry.spawn_line(wb, blocked_paths, "left")
    right = geometry.spawn_line(wb, blocked_paths, "right")
    return {"evidence": evidence, "blockedPaths": blocked_paths, "collisions": collisions,
            "spawn": spawn, "spawnAdjusted": adjusted, "exit": exit_spec,
            "leftSpawnLine": left, "rightSpawnLine": right, "approximations": notes}


def build_domdocument(layout, symbols):
    """规范独立背景两帧合同：首帧子元件初始化，次帧 stop + 归属/active guard。"""
    doc = ET.Element(x.tag("DOMDocument"), nsmap={None: NS["x"]},
                     width=str(layout["world"]["width"]), height=str(layout["world"]["height"]),
                     frameRate="30", currentTimeline="1", xflVersion="2.2",
                     creatorInfo="Adobe Flash Professional CS6", platform="Windows",
                     versionInfo="Saved by Adobe Flash Windows 12.0 build 481",
                     majorVersion="12", buildNumber="481",
                     playOptionsPlayLoop="false", playOptionsPlayPages="false",
                     playOptionsPlayFrameActions="false")
    ET.SubElement(doc, x.tag("media"))
    timelines = ET.SubElement(doc, x.tag("timelines"))
    timeline = ET.SubElement(timelines, x.tag("DOMTimeline"), name="Tutorial Room Native Vector Candidate")
    layers = ET.SubElement(timeline, x.tag("layers"))
    action_layer = ET.SubElement(layers, x.tag("DOMLayer"), name="initialize-then-bake")
    frames = ET.SubElement(action_layer, x.tag("frames"))
    f0 = ET.SubElement(frames, x.tag("DOMFrame"), index="0", duration="1", keyMode="9728")
    ET.SubElement(f0, x.tag("elements"))
    f1 = ET.SubElement(frames, x.tag("DOMFrame"), index="1", duration="1", keyMode="9728")
    script = ET.SubElement(ET.SubElement(f1, x.tag("Actionscript")), x.tag("script"))
    script.text = GUARD
    ET.SubElement(f1, x.tag("elements"))
    room_layer = ET.SubElement(layers, x.tag("DOMLayer"), name="room")
    frames = ET.SubElement(room_layer, x.tag("frames"))
    frame = ET.SubElement(frames, x.tag("DOMFrame"), index="0", duration="2", keyMode="9728")
    elements = ET.SubElement(frame, x.tag("elements"))
    elements.append(instance(COMPOSITE, {"a": 1, "b": 0, "c": 0, "d": 1, "tx": 0, "ty": 0}, with_point=False))
    includes = ET.SubElement(doc, x.tag("symbols"))
    for name, r in sorted(symbols.items()):
        ET.SubElement(includes, x.tag("Include"), href=name + ".xml",
                      loadImmediate="false", itemID=r.get("itemID"))
    return doc


def build_publish_settings():
    """以现役 CF6_A01_BG 发布设置为模板：裸文件名、AS2、Version 15、压缩发布。"""
    text = (A01 / "PublishSettings.xml").read_text(encoding="utf-8")
    assert text.count("CF6_A01_BG.swf") == 1
    text = text.replace("CF6_A01_BG.swf", "CF6_Tutorial_BG.swf")
    text = text.replace("<Width>800</Width>", "<Width>1000</Width>")
    text = text.replace("<Height>452</Height>", "<Height>450</Height>")
    return text


def build_environment(layout, geo):
    lines = ["<?xml version='1.0' encoding='utf-8'?>", "<EnvironmentSettings>", "  <Environment>",
             "    <BackgroundURL>CF6_Tutorial_BG.swf</BackgroundURL>",
             "    <Alignment>true</Alignment>"]
    wb = layout["world"]["walkBounds"]
    for tagname, value in zip(("Xmin", "Ymin", "Xmax", "Ymax"), wb):
        lines.append("    <%s>%s</%s>" % (tagname, fmt(value), tagname))
    lines.append("    <Width>%s</Width>" % fmt(layout["world"]["width"]))
    lines.append("    <Height>%s</Height>" % fmt(layout["world"]["height"]))
    lines += ["    <DisableSky>true</DisableSky>", "    <SpaceCondition>室内</SpaceCondition>",
              "    <MaxIllumination>8</MaxIllumination>", "    <MinIllumination>8</MinIllumination>",
              "    <Door>", "      <Index>1</Index>",
              "      <Direction>%s</Direction>" % geo["exit"]["direction"]]
    for tagname, value in zip(("x0", "y0", "x1", "y1"), geo["exit"]["rect"]):
        lines.append("      <%s>%s</%s>" % (tagname, fmt(value), tagname))
    lines.append("    </Door>")
    for polygon in geo["collisions"]:
        lines.append("    <Collision>")
        for px, py in polygon:
            lines.append("      <Point>%s,%s</Point>" % (fmt(px), fmt(py)))
        lines.append("    </Collision>")
    for tagname, line in (("LeftSpawnLine", geo["leftSpawnLine"]), ("RightSpawnLine", geo["rightSpawnLine"])):
        lines.append("    <%s>" % tagname)
        for sub, value in zip(("x0", "y0", "x1", "y1"), line):
            lines.append("      <%s>%s</%s>" % (sub, fmt(value), sub))
        lines.append("    </%s>" % tagname)
    lines += ["  </Environment>", "</EnvironmentSettings>"]
    return "\n".join(lines) + "\n"


def build_map_fragment(layout, geo):
    return {
        "id": layout["mapId"],
        "title": layout["title"],
        "background": layout["background"],
        "mechanism": {"kind": "exit", "layers": []},
        "dialogue": layout["dialogue"],
        "stage": {
            "BasicInformation": {
                "Background": "flashswf/backgrounds/" + layout["background"],
                "PlayerX": geo["spawn"][0],
                "PlayerY": geo["spawn"][1],
                "EndFrame": "房间",
                "BGM": layout["bgm"],
            },
            "Instances": {"Instance": []},
            "SpawnPoint": {"Point": []},
            "Pickups": {"Pickup": layout["pickups"]},
            "Event": [
                {"EventName": "Start", "Guidance": "引导-拾取", "Message": layout["events"]["start"]},
                {"EventName": "Clear", "Message": layout["events"]["clear"]},
            ],
            "Wave": {"SubWave": [{"WaveInformation": {"Duration": layout["wave"]["Duration"],
                                                       "FinishRequirement": layout["wave"]["FinishRequirement"]},
                                  "EnemyGroup": {"Enemy": []}}]},
        },
    }


def build_provenance(layout, geo, placements, stats, provenance, symbols):
    xfl_files = sorted(p for p in TARGET.rglob("*") if p.is_file()) if TARGET.is_dir() else []
    sizes = {p["role"]: {"worldWidth": round(p["worldBounds"][2] - p["worldBounds"][0], 2),
                         "worldHeight": round(p["worldBounds"][3] - p["worldBounds"][1], 2)}
             for p in placements}
    edge_count = 0
    for r in symbols.values():
        for edge in r.findall(".//x:Edge", NS):
            edge_count += sum(1 for _ in edge_segments(edge.get("edges", "")))
    sources = [{"path": str(p.relative_to(ROOT)).replace("\\", "/"),
                "sha256": sha256(p), "bytes": p.stat().st_size}
               for p in sorted(set(stats["sourceFiles"]))]
    for extra in (LAYOUT, EVIDENCE, A01 / "DOMDocument.xml", A01 / "PublishSettings.xml"):
        sources.append({"path": str(extra.relative_to(ROOT)).replace("\\", "/"),
                        "sha256": sha256(extra), "bytes": extra.stat().st_size})
    return {
        "schema": "cf6-tutorial-assembly.v2",
        "mapId": layout["mapId"],
        "background": layout["background"],
        "xfl": "flashswf/backgrounds/cf6/CF6_Tutorial_BG/CF6_Tutorial_BG.xfl",
        "sources": sources,
        "symbolMapping": provenance,
        "placements": placements,
        "componentSizesWorldPx": sizes,
        "characterReference": "CF7 持枪站姿约 138.38px（tools/cf6-map-runtime/README.md §输入与坐标）；worldScale=1",
        "original": {
            "swfSha256": geo["evidence"]["originalSwfSha256"],
            "rootLabel": "教学关 = 主时间轴第58帧；world sprite = DefineSprite_1499 gameworld；背景 = DefineSprite_1419",
            "walkBounds": layout["world"]["walkBounds"],
            "authoredSpawn": geo["evidence"]["geometry"]["spawn"],
            "originalExitChain": layout["exit"]["originalExitChain"],
            "artAvailable": False,
            "artNote": "原教学图不在 21 图源包内；背景画面为现役素材近似重组，不声称等价",
        },
        "geometry": {
            "status": "originalStaticFillWithPrototypeDerivedEntryExit",
            "collision": "原作 地图 碰撞子树偶奇填充（实心外墙减行走孔洞）按 walkBounds 裁剪分解为无孔凸多边形；与 route 覆盖同一 filled_trapezoids 管线",
            "walkableBand": "后缘 y≈204（含 x182..507 家具凹口）、前缘 y≈449.95、右墙斜边 (716.5,204)→(1020.8,448.95)",
            "spawn": geo["spawn"], "spawnAdjusted": geo["spawnAdjusted"],
            "exit": dict(geo["exit"], note="prototypeDerived CF7 手动右侧出口，不宣称原作自动转场"),
            "leftSpawnLine": geo["leftSpawnLine"], "rightSpawnLine": geo["rightSpawnLine"],
            "approximations": geo["approximations"],
        },
        "scriptWhitelist": {"allowed": ["根时间轴第2帧 stop()+所有权/active guard（与 CF6_A01_BG 逐字一致）"],
                            "guardSha256": hashlib.sha256(GUARD.encode("utf-8")).hexdigest(),
                            "strippedFromCopies": stats["strippedScripts"],
                            "convertedButtons": stats["convertedButtons"],
                            "removedLinkageAttrs": stats["removedLinkageAttrs"],
                            "droppedEmptyLayers": stats["droppedEmptyLayers"]},
        "vectorReport": {"symbols": len(symbols), "edgeSegments": edge_count,
                         "bitmapBytes": 0, "bitmapNote": "闭包零位图，无 bin/ 依赖"},
        "approximations": [
            "原教学美术缺失：房间壳/高架床/工作台取自现役宿舍房间（基地场景合集），门灯取自素材库-地图元件 门灯光+排气扇，门取 门2",
            "宿舍→教学世界统一 1.383 倍映射（行走区 730×178 → 1010×246 对齐原作行走带），家具相对布局保持宿舍原样",
            "原作墙照片（1443×2）与排气扇动画（1448×2）未复刻；门灯位置按原作灯管位",
            "原作三个补给箱改为标准地面拾取物两份；原作屏外 弃枪/敌人生成器 不进入本作",
            "门方向与原布局一致（右侧），门图直立近似原作斜置门",
        ],
        "pendingIntegration": [
            "主控合并 environment.fragment.xml 到 data/environment/stage_environment.xml（本工具不写共享注册表）",
            "主控将 tutorial-map.fragment.json 合入 cf6-sting 章节第 0 项并更新 runtime-index.json",
            "BookDefinition.validCf6 对 TUTORIAL 硬编码 gk1_1_BG.swf，需主控裁决改为 cf6/CF6_Tutorial_BG.swf（AS2 改动不在本线范围）",
            "CS6 编译：scripts/compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_Tutorial_BG/CF6_Tutorial_BG.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_Tutorial_BG.swf'",
            "实机对照：角色体量/行走带/门口与画面一致、空波次清关开放出口、撤退回包",
        ],
        "acceptanceBoundary": "data/source prepared only; deterministic assembly; no CS6 compile, no in-game or art acceptance claimed; approximate recombination, not original artwork",
    }


def render_outputs():
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    symbols, placements, stats, provenance = build_symbols(layout)
    geo = build_geometry(layout)
    outputs = {}
    for name, r in symbols.items():
        outputs[TARGET / "LIBRARY" / (name + ".xml")] = ET.tostring(r, encoding="utf-8", pretty_print=True)
    outputs[TARGET / "DOMDocument.xml"] = ET.tostring(build_domdocument(layout, symbols),
                                                      encoding="utf-8", pretty_print=True)
    outputs[TARGET / "PublishSettings.xml"] = build_publish_settings().encode("utf-8")
    outputs[TARGET / "CF6_Tutorial_BG.xfl"] = b"PROXY-CS5"
    outputs[HERE / "environment.fragment.xml"] = build_environment(layout, geo).encode("utf-8")
    outputs[HERE / "tutorial-map.fragment.json"] = (
        json.dumps(build_map_fragment(layout, geo), ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    outputs[HERE / "provenance.json"] = (
        json.dumps(build_provenance(layout, geo, placements, stats, provenance, symbols),
                   ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return outputs, layout, geo, symbols, placements


def audit(layout, geo, symbols, placements):
    """闭包/脚本白名单/引用/布局可达静态自检；不代签 CS6 与实机。"""
    for name, r in symbols.items():
        assert r.get("symbolType") == "graphic", name
        assert not r.findall(".//x:Actionscript", NS), "复制件残留脚本：" + name
        assert not any(k.startswith("linkage") for k in r.attrib), name
        assert not r.findall(".//x:DOMBitmapInstance", NS), name
        assert not r.findall(".//x:DOMBitmapFill", NS), name
        assert not r.findall(".//x:DOMStaticText", NS), name
        assert not r.findall(".//x:DOMDynamicText", NS), name
        assert not r.findall(".//x:DOMInputText", NS), name
        for f in r.findall(".//x:DOMFrame", NS):
            assert f.get("index") == "0" and int(f.get("duration", 1)) == 1, name
        for i in r.findall(".//x:DOMSymbolInstance", NS):
            assert i.get("libraryItemName") in symbols, "闭包缺引用：%s -> %s" % (name, i.get("libraryItemName"))
            assert i.get("symbolType") == "graphic" and i.get("loop") == "single frame", name
        layers = r.findall("./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer", NS)
        for idx, lyr in enumerate(layers):
            if lyr.get("layerType") == "mask":
                assert [l for l in layers if l.get("parentLayerIndex") == str(idx)], "遮罩断链：" + name
    # 布局可达：5px 点网格出生→出口连通（与 audit-route-geometry 同法，不代签角色半径/AVM1）
    wb = layout["world"]["walkBounds"]
    x0, y0, x1, y1 = wb
    paths = geo["blockedPaths"]

    def free(p):
        return x0 < p[0] < x1 and y0 < p[1] < y1 and sum(geometry.point_inside(p, q) for q in paths) % 2 == 0
    assert free(geo["spawn"]), "出生点不在可行走区"
    for pk in layout["pickups"]:
        assert free([pk["x"], pk["y"]]), "补给点不在可行走区：" + pk["Name"]
    rect = geo["exit"]["rect"]
    assert free([(rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2]), "出口区中心不可行走"
    step = 5
    nx, ny = int((x1 - x0) / step), int((y1 - y0) / step)

    def point(cell):
        return [x0 + (cell[0] + 0.5) * step, y0 + (cell[1] + 0.5) * step]
    cells = {(xi, yi) for xi in range(nx) for yi in range(ny) if free(point((xi, yi)))}
    start = min(cells, key=lambda c: (point(c)[0] - geo["spawn"][0]) ** 2 + (point(c)[1] - geo["spawn"][1]) ** 2)
    targets = {c for c in cells if rect[0] < point(c)[0] < rect[2] and rect[1] < point(c)[1] < rect[3]}
    assert targets, "出口区内无可行走网格点"
    visited, queue = {start}, deque([start])
    while queue:
        cell = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nxt = (cell[0] + dx, cell[1] + dy)
            if nxt in cells and nxt not in visited:
                visited.add(nxt)
                queue.append(nxt)
    assert visited & targets, "出生到出口不连通"
    # 门图与出口区重叠（门口与图像一致）
    door = next(p for p in placements if p["role"] == "出口门")
    db = door["worldBounds"]
    assert db[0] < rect[2] and db[2] > rect[0] and db[1] < rect[3] and db[3] > rect[1], "门图与出口区不相交"
    # 填充等价抽检：分解前后偶奇填充一致（确定性采样）
    import random
    rng = random.Random("TUTORIAL")
    for _ in range(1000):
        p = [rng.uniform(x0, x1), rng.uniform(y0, y1)]
        a = sum(geometry.point_inside(p, q) for q in paths) % 2
        b = sum(geometry.point_inside(p, q) for q in geo["collisions"]) % 2
        assert a == b, "碰撞分解与原始填充不一致"
    return {"freeGridCells": len(cells), "reachableCells": len(visited)}


def check_static(outputs):
    """确定性核对：产物逐字节一致、源 SHA 未变、归档完好、DOMDocument 合同与白名单。"""
    for path, content in outputs.items():
        assert path.is_file(), "缺产物：" + str(path)
        assert path.read_bytes() == content, "产物过期：" + str(path)
    provenance = json.loads((HERE / "provenance.json").read_text(encoding="utf-8"))
    for row in provenance["sources"]:
        p = ROOT / row["path"]
        assert p.is_file() and sha256(p) == row["sha256"], "源已变化：" + row["path"]
    for row in json.loads(ARCHIVE.read_text(encoding="utf-8")).items():
        if row[0] == "note":
            continue
        p = ARCHIVE.parent / row[0]
        assert p.is_file() and sha256(p) == row[1], "归档损坏：" + row[0]
    doc = (TARGET / "DOMDocument.xml").read_text(encoding="utf-8")
    assert "linkage" not in doc, "DOMDocument 出现 linkage"
    scripts = [e.text for e in x.read(TARGET / "DOMDocument.xml").findall(".//x:Actionscript/x:script", NS)]
    assert scripts == [GUARD], "脚本白名单只允许根第二帧 guard"
    includes = [i.get("href") for i in x.read(TARGET / "DOMDocument.xml").findall("./x:symbols/x:Include", NS)]
    library = sorted(p.relative_to(TARGET / "LIBRARY").as_posix()
                     for p in (TARGET / "LIBRARY").rglob("*.xml"))
    assert sorted(includes) == library, "Include 与 LIBRARY 文件不一一对应"
    assert not (TARGET / "CF6_Tutorial_BG.swf").exists(), "本线不创建 SWF"
    return {"outputs": len(outputs), "librarySymbols": len(includes)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs, layout, geo, symbols, placements = render_outputs()
    report = audit(layout, geo, symbols, placements)
    if args.check:
        summary = check_static(outputs)
        print(json.dumps({"check": "ok", **summary, **report,
                          "collisions": len(geo["collisions"]), "exit": geo["exit"]},
                         ensure_ascii=False))
        return 0
    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    summary = check_static(render_outputs()[0])
    print(json.dumps({"built": "ok", **summary, **report,
                      "collisions": len(geo["collisions"]), "exit": geo["exit"]},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
