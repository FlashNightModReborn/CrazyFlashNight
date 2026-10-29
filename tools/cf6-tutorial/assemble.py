"""CF6 教学室背景装配：现役矢量元件最小闭包 + native-cache-only 媒体 → 原生 XFL 源 + 环境/地图片段。

只确定性装配源文件；不调用 CS6、不生成或修改任何 SWF、不改源库与其他工具输入。
原教学美术不在 21 图源包内，本工具按 layout.json 用现役宿舍房间壳/高架床/工作台/门灯
矢量元件近似重组教学室，布局（行走带、出生、右侧出口、灯位）取自原作提取事实；
近似处逐条写入 provenance.json，不声称画面与原作等价。
闭包内 7 处 BitmapFill 引用的 5 张纹理：原库 DOMBitmapItem 登记的 href 文件本就不存在
（旧 XFL 现实格式），现役源是原库原生 bin 缓存；本工具逐字复制缓存与媒体元数据，
不生成/解码/重编码任何图像字节。该路线已经 root 探针
tmp/cf6-roguelike-20261021/validation/tutorial-cache-probe-r1/ 真实 CS6 Compiler 0/0 验证。

用法：
    python -X utf8 -B tools/cf6-tutorial/assemble.py          # 生成/刷新全部产物
    python -X utf8 -B tools/cf6-tutorial/assemble.py --check  # 只读核对：源SHA、布局、闭包、产物确定性
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import sys
import math
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
R10_ARCHIVE = HERE / "archive/r10-before-texture-fix/hashes.json"
SOURCE_XFL = ROOT / "flashswf/levels/基地场景合集"
SOURCE_DOM = SOURCE_XFL / "DOMDocument.xml"
# 闭包内 7 处 BitmapFill（正确 tag 为 BitmapFill/bitmapPath，非 DOMBitmapFill）引用 5 张纹理。
# 原库对应 DOMBitmapItem 的 href 文件在 LIBRARY/image 下本就不存在（已核实），现役源是原生 bin
# 缓存；钉值取 root 探针 tutorial-cache-probe-r1/inputs.json 实测（缓存总计 28869 字节）。
# 本工具只逐字复制缓存，不生成 .dat、不恢复/重编码 JPEG 或 PNG 字节。
MEDIA_SOURCE_KIND = "native-cache-only-existing-xfl"
MEDIA_CACHE_PIN = {
    "image/bitmap2252.jpg": {"cache": "M 6 1736924415.dat", "bytes": 18486,
                             "sha256": "744350422af43c01d69336cb74711982697c0cd5638415f6b64c796fda8f5471"},
    "image/bitmap2255.jpg": {"cache": "M 5 1736924415.dat", "bytes": 1932,
                             "sha256": "ec588f8252952296b3b833d752788adc12c9a04903403011a6e919d6b527ddb7"},
    "image/bitmap2259.jpg": {"cache": "M 4 1736924415.dat", "bytes": 1754,
                             "sha256": "19eee04b09e08c97ed65e9500d90731701c6c2c5dccafc81a35e2db397ee91ef"},
    "image/bitmap2261.png": {"cache": "M 3 1736924415.dat", "bytes": 3090,
                             "sha256": "bc66b70bd4c3de8ccd054f815d6394f068af65382381b862e92510294ed03959"},
    "image/bitmap2321.png": {"cache": "M 2 1736924415.dat", "bytes": 3607,
                             "sha256": "55ee411f10aab46351f23d4abbba9c95f82701954fae52a0e1cf51608f48fc59"},
}
# 实际影响输出的生成器/工具与其有限直接依赖（不扩扫全仓）。
TOOL_SOURCES = ["tools/cf6-tutorial/assemble.py", "tools/cf6-map-runtime/build-tutorial.py",
                "tools/rhino-map-assets/build.py", "tools/asset-metrology/xfl_geometry.py",
                "tools/cf6-map-runtime/geometry.py"]

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


def bitmap_refs(symbols):
    """闭包内实际位图引用：BitmapFill/bitmapPath 与 DOMBitmapInstance/libraryItemName。"""
    refs = set()
    for r in symbols.values():
        for fill in r.findall(".//x:BitmapFill", NS):
            refs.add(fill.get("bitmapPath"))
        for inst in r.findall(".//x:DOMBitmapInstance", NS):
            refs.add(inst.get("libraryItemName"))
    refs.discard(None)
    return refs


def build_media(refs, source_xfl=SOURCE_XFL):
    """native-cache-only 媒体闭包：复制原 DOMBitmapItem（去失效 sourceExternalFilepath）+ 原样 bin 缓存。

    只接受钉板内、且原库同条 DOMBitmapItem 的 href 文件本就不存在的引用；
    缺缓存/缓存字节与钉板不符/未声明引用一律拒绝。不生成图像字节。
    返回 (media_items, bin_outputs, manifest)。
    """
    unknown = refs - set(MEDIA_CACHE_PIN)
    assert not unknown, "未声明的位图引用（不在 native-cache 钉板内）：%s" % sorted(unknown)
    items = {item.get("name"): item
             for item in x.read(source_xfl / "DOMDocument.xml").findall("./x:media/x:DOMBitmapItem", NS)}
    media_items, bin_outputs, manifest = [], {}, []
    for name in sorted(refs):
        pin = MEDIA_CACHE_PIN[name]
        assert name in items, "源库 DOMDocument 缺 DOMBitmapItem：" + name
        item = copy.deepcopy(items[name])
        assert item.get("href") == name, "href 与引用名不一致：" + name
        assert not (source_xfl / "LIBRARY" / item.get("href")).is_file(), \
            "原库 href 文件意外存在，cache-only 例外不成立：" + name
        item.attrib.pop("sourceExternalFilepath", None)  # 移除失效外部路径，避免回退
        assert item.get("bitmapDataHRef") == pin["cache"], "缓存名与钉板不符：" + name
        assert "/" not in pin["cache"] and "\\" not in pin["cache"] and ".." not in pin["cache"], pin["cache"]
        cache_path = source_xfl / "bin" / pin["cache"]
        assert cache_path.is_file(), "源原生缓存缺失：" + str(cache_path)
        data = cache_path.read_bytes()
        assert len(data) == pin["bytes"] and hashlib.sha256(data).hexdigest() == pin["sha256"], \
            "源原生缓存与钉板不一致：" + name
        media_items.append(item)
        bin_outputs[pin["cache"]] = data
        manifest.append({
            "name": name,
            "mediaSourceKind": MEDIA_SOURCE_KIND,
            "originalHrefPresent": False,
            "frameRight": int(item.get("frameRight")),
            "frameBottom": int(item.get("frameBottom")),
            "isJPEG": item.get("isJPEG") == "true",
            "compressionType": item.get("compressionType"),
            "sourceCache": {"path": str(cache_path.relative_to(ROOT)).replace("\\", "/"),
                            "sha256": pin["sha256"], "bytes": pin["bytes"]},
            "outputBin": {"path": "flashswf/backgrounds/cf6/CF6_Tutorial_BG/bin/" + pin["cache"],
                          "sha256": pin["sha256"], "bytes": pin["bytes"]},
        })
    return media_items, bin_outputs, manifest


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
        scale = float(p.get("worldScale", s))
        if not math.isfinite(scale) or scale <= 0:
            raise ValueError("摆件缩放必须是有限正数：" + p["role"])
        linear = p.get("worldLinear", [scale, 0, 0, scale])
        if len(linear) != 4 or not all(math.isfinite(float(v)) for v in linear):
            raise ValueError("摆件矩阵必须包含四个有限数：" + p["role"])
        a, b, c, d = map(float, linear)
        if abs(a * d - b * c) < 1e-9:
            raise ValueError("摆件矩阵不能退化：" + p["role"])
        corners = [(a * px + c * py, b * px + d * py)
                   for px in (natural[0], natural[2]) for py in (natural[1], natural[3])]
        mapped = [min(v[0] for v in corners), min(v[1] for v in corners),
                  max(v[0] for v in corners), max(v[1] for v in corners)]
        matrix = {"a": a, "b": b, "c": c, "d": d}
        if "dorm" in p:
            dx, dy = p["dorm"]
            matrix.update(tx=s * dx + mtx, ty=s * dy + mty)
        elif "worldTopLeft" in p:
            matrix.update(tx=p["worldTopLeft"][0] - mapped[0], ty=p["worldTopLeft"][1] - mapped[1])
        elif "worldBottomRight" in p:
            matrix.update(tx=p["worldBottomRight"][0] - mapped[2], ty=p["worldBottomRight"][1] - mapped[3])
        elif "worldBottomLeft" in p:
            matrix.update(tx=p["worldBottomLeft"][0] - mapped[0], ty=p["worldBottomLeft"][1] - mapped[3])
        else:
            raise ValueError("未知摆放锚点：" + p["role"])
        world = [mapped[0] + matrix["tx"], mapped[1] + matrix["ty"],
                 mapped[2] + matrix["tx"], mapped[3] + matrix["ty"]]
        placements.append({"role": p["role"], "symbol": target, "matrix": matrix,
                           "naturalBounds": [round(v, 2) for v in natural],
                           "worldBounds": [round(v, 2) for v in world],
                           "evidence": p["evidence"]})
    order = ["门灯", "门", "工作台", "高架床", "房间壳"]
    groups = {p["group"] for p in layout["placements"]}
    assert groups.issubset(set(order)) and {"门灯", "门", "高架床", "房间壳"}.issubset(groups), "场景分组不完整"
    layers = []
    for group in order:
        if group not in groups:
            continue
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


def build_domdocument(layout, symbols, media_items):
    """规范独立背景两帧合同：首帧子元件初始化，次帧 stop + 归属/active guard；media 闭合位图引用。"""
    doc = ET.Element(x.tag("DOMDocument"), nsmap={None: NS["x"]},
                     width=str(layout["world"]["width"]), height=str(layout["world"]["height"]),
                     frameRate="30", currentTimeline="1", xflVersion="2.2",
                     creatorInfo="Adobe Flash Professional CS6", platform="Windows",
                     versionInfo="Saved by Adobe Flash Windows 12.0 build 481",
                     majorVersion="12", buildNumber="481",
                     playOptionsPlayLoop="false", playOptionsPlayPages="false",
                     playOptionsPlayFrameActions="false")
    media = ET.SubElement(doc, x.tag("media"))
    media.extend(media_items)
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


def build_provenance(layout, geo, placements, stats, provenance, symbols, media_manifest):
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
    extras = [LAYOUT, EVIDENCE, A01 / "DOMDocument.xml", A01 / "PublishSettings.xml", SOURCE_DOM]
    extras += [ROOT / rel for rel in TOOL_SOURCES]
    extras += [ROOT / 'tools/cf6-prop-layout' / rel
               for rel in ('calibrate.py', 'recipe.json', 'depth-recipe.json')]
    extras += [SOURCE_XFL / "bin" / pin["cache"] for pin in MEDIA_CACHE_PIN.values()]
    for extra in extras:
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
        "placementMeasurementSpace": "before the per-instance calibration overlay and final chapter viewport transform",
        "instanceCalibration": "tools/cf6-prop-layout/generated/instance-layout.json contains final world sizes and unchanged ground pivots",
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
                         "bitmaps": len(media_manifest),
                         "bitmapBytes": sum(m["outputBin"]["bytes"] for m in media_manifest),
                         "mediaSourceKind": MEDIA_SOURCE_KIND,
                         "bitmapNote": "5 张纹理以原库原生 bin 缓存逐字闭合（href 原件本就不存在，探针 tutorial-cache-probe-r1 已真实 CS6 0/0）；不生成/重编码图像"},
        "media": media_manifest,
        "integratedByRoot": [
            "BookDefinition 白名单只接受 cf6/CF6_Tutorial_BG.swf，已经 root 真实编译 579/579 测试通过",
            "root 装配器已接 tutorial-map.fragment.json 与 environment.fragment.xml；runtime-index 20 图集合不变（教学为独立输入）",
        ],
        "approximations": [
            "原教学美术缺失：房间壳/高架床/工作台取自现役宿舍房间（基地场景合集），门灯取自素材库-地图元件 门灯光+排气扇，门取 门2",
            "房间壳按宿舍→教学世界 1.383 倍映射；高架床组合、门和灯具使用 layout.json 独立世界锚点及角色标尺缩放",
            "原作墙照片（1443×2）与排气扇动画（1448×2）未复刻；门灯位置按原作灯管位",
            "原作三个补给箱改为标准地面拾取物两份；原作屏外 弃枪/敌人生成器 不进入本作",
            "门方向与原布局一致（右侧）；原生门图使用侧墙仿射摆放，保留独立的原型通行区",
        ],
        "pendingIntegration": [
            "真实 CS6 编译（root）：scripts/compile_test.ps1 -Target 'flashswf/backgrounds/cf6/CF6_Tutorial_BG/CF6_Tutorial_BG.xfl' -PublishOnly -VerifySwf 'flashswf/backgrounds/cf6/CF6_Tutorial_BG.swf'；本线不编译、不生成 SWF",
            "编译产物视觉检查（root）：5 张 native-cache 纹理在 SWF 画面中完整（同等装配探针 tutorial-cache-probe-r1 已 0/0 通过并目视确认）",
            "实机验证（root）：角色体量/行走带/门口与画面一致、空波次清关开放出口、撤退回包",
        ],
        "acceptanceBoundary": "data/source prepared only; deterministic assembly; no CS6 compile, no in-game or art acceptance claimed; approximate recombination, not original artwork",
    }


def render_outputs():
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    symbols, placements, stats, provenance = build_symbols(layout)
    refs = bitmap_refs(symbols)
    media_items, bin_outputs, media_manifest = build_media(refs)
    geo = build_geometry(layout)
    outputs = {}
    for name, r in symbols.items():
        outputs[TARGET / "LIBRARY" / (name + ".xml")] = ET.tostring(r, encoding="utf-8", pretty_print=True)
    outputs[TARGET / "DOMDocument.xml"] = ET.tostring(build_domdocument(layout, symbols, media_items),
                                                      encoding="utf-8", pretty_print=True)
    for cache, data in bin_outputs.items():
        outputs[TARGET / "bin" / cache] = data
    outputs[TARGET / "PublishSettings.xml"] = build_publish_settings().encode("utf-8")
    outputs[TARGET / "CF6_Tutorial_BG.xfl"] = b"PROXY-CS5"
    outputs[HERE / "environment.fragment.xml"] = build_environment(layout, geo).encode("utf-8")
    outputs[HERE / "tutorial-map.fragment.json"] = (
        json.dumps(build_map_fragment(layout, geo), ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    outputs[HERE / "provenance.json"] = (
        json.dumps(build_provenance(layout, geo, placements, stats, provenance, symbols, media_manifest),
                   ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    calibration_spec = importlib.util.spec_from_file_location(
        "cf6_prop_calibration", ROOT / "tools/cf6-prop-layout/calibrate.py")
    calibration = importlib.util.module_from_spec(calibration_spec)
    calibration_spec.loader.exec_module(calibration)
    outputs = calibration.overlay_outputs(outputs)
    return outputs, layout, geo, symbols, placements, refs, media_manifest


def audit(layout, geo, symbols, placements, refs, media_manifest):
    """闭包/脚本白名单/引用/媒体闭合/布局可达静态自检；不代签 CS6 与实机。"""
    for name, r in symbols.items():
        assert r.get("symbolType") == "graphic", name
        assert not r.findall(".//x:Actionscript", NS), "复制件残留脚本：" + name
        assert not any(k.startswith("linkage") for k in r.attrib), name
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
    # 媒体闭合：每个 BitmapFill/DOMBitmapInstance 引用有且仅有一个 DOMBitmapItem 声明，且无未声明引用。
    declared = [m["name"] for m in media_manifest]
    assert len(declared) == len(set(declared)), "媒体重复声明"
    assert refs == set(declared), "位图引用与媒体声明不一一对应：%s vs %s" % (sorted(refs), sorted(declared))
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


def check_static(outputs, refs):
    """确定性核对：产物逐字节一致、源 SHA 未变、归档完好、DOMDocument 合同、白名单与媒体闭包。"""
    for path, content in outputs.items():
        assert path.is_file(), "缺产物：" + str(path)
        assert path.read_bytes() == content, "产物过期：" + str(path)
    provenance = json.loads((HERE / "provenance.json").read_text(encoding="utf-8"))
    for row in provenance["sources"]:
        p = ROOT / row["path"]
        assert p.is_file() and sha256(p) == row["sha256"], "源已变化：" + row["path"]
    for archive in (ARCHIVE, R10_ARCHIVE):
        for row in json.loads(archive.read_text(encoding="utf-8")).items():
            if row[0] == "note":
                continue
            p = archive.parent / row[0]
            assert p.is_file() and sha256(p) == row[1], "归档损坏：%s/%s" % (archive.parent.name, row[0])
    doc_root = x.read(TARGET / "DOMDocument.xml")
    doc = (TARGET / "DOMDocument.xml").read_text(encoding="utf-8")
    assert "linkage" not in doc, "DOMDocument 出现 linkage"
    scripts = [e.text for e in doc_root.findall(".//x:Actionscript/x:script", NS)]
    assert scripts == [GUARD], "脚本白名单只允许根第二帧 guard"
    includes = [i.get("href") for i in doc_root.findall("./x:symbols/x:Include", NS)]
    library = sorted(p.relative_to(TARGET / "LIBRARY").as_posix()
                     for p in (TARGET / "LIBRARY").rglob("*.xml"))
    assert sorted(includes) == library, "Include 与 LIBRARY 文件不一一对应"
    # 媒体闭包：引用 == 声明 == 钉板；缓存存在/非空/路径在自身 bin 内/SHA 与钉板一致；无额外媒体或缓存。
    declared = {}
    for item in doc_root.findall("./x:media/x:DOMBitmapItem", NS):
        name = item.get("name")
        assert name not in declared, "DOMBitmapItem 重复声明：" + name
        declared[name] = item
        assert name in MEDIA_CACHE_PIN, "额外未声明媒体：" + name
        pin = MEDIA_CACHE_PIN[name]
        assert item.get("bitmapDataHRef") == pin["cache"], "缓存名与钉板不符：" + name
        assert "sourceExternalFilepath" not in item.attrib, "残留失效 sourceExternalFilepath：" + name
        assert "/" not in pin["cache"] and "\\" not in pin["cache"] and ".." not in pin["cache"], pin["cache"]
        cache_file = TARGET / "bin" / pin["cache"]
        assert cache_file.is_file() and cache_file.stat().st_size == pin["bytes"] > 0, "原生缓存缺失/为空：" + name
        assert sha256(cache_file) == pin["sha256"], "原生缓存与钉板不一致：" + name
        # href 原件缺失只在原库同条 DOMBitmapItem 本就不存在该文件时接受（钉板 5 项），不补造图片。
        assert not (TARGET / "LIBRARY" / item.get("href")).is_file(), "不允许补造 href 图片：" + name
    assert set(declared) == refs, "媒体声明与闭包引用不闭合：%s vs %s" % (sorted(declared), sorted(refs))
    bin_files = sorted(p.name for p in (TARGET / "bin").glob("*.dat"))
    assert bin_files == sorted(MEDIA_CACHE_PIN[n]["cache"] for n in refs), "bin 目录含额外缓存"
    assert not (TARGET / "CF6_Tutorial_BG.swf").exists(), "本线不创建 SWF"
    return {"outputs": len(outputs), "librarySymbols": len(includes),
            "bitmaps": len(declared),
            "bitmapBytes": sum(MEDIA_CACHE_PIN[n]["bytes"] for n in refs)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if json.loads(LAYOUT.read_text(encoding="utf-8")).get("artRevision") == "r7-bold":
        r7_spec = importlib.util.spec_from_file_location("cf6_tutorial_r7", HERE / "r7.py")
        r7 = importlib.util.module_from_spec(r7_spec)
        r7_spec.loader.exec_module(r7)
        r7.assemble(sys.modules[__name__], args.check)
        return 0
    outputs, layout, geo, symbols, placements, refs, media_manifest = render_outputs()
    report = audit(layout, geo, symbols, placements, refs, media_manifest)
    if args.check:
        summary = check_static(outputs, refs)
        print(json.dumps({"check": "ok", **summary, **report,
                          "collisions": len(geo["collisions"]), "exit": geo["exit"]},
                         ensure_ascii=False))
        return 0
    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    summary = check_static(render_outputs()[0], refs)
    print(json.dumps({"built": "ok", **summary, **report,
                      "collisions": len(geo["collisions"]), "exit": geo["exit"]},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
