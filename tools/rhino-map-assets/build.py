"""犀牛 R09 静态地图分件导入及派生同步；SWF 只由 CS6 发布。"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import sys
from pathlib import Path

from lxml import etree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/asset-metrology"))
from xfl_geometry import segments
NS = {"x": "http://ns.adobe.com/xfl/2008/"}
URI = NS["x"]
PREFIX = "Codex/犀牛R09/"
AUTHORITY = ROOT / "flashswf/levels/地图-军阀基地"
CONFIG = Path(__file__).with_name("placements.json")
LAYER = "犀牛R09-静态摆件"
PARSER = ET.XMLParser(remove_blank_text=True)


def tag(name):
    return "{" + URI + "}" + name


def read(path, preserve=False):
    return ET.parse(str(path), ET.XMLParser(remove_blank_text=not preserve)).getroot()


def write(path, root):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(ET.tostring(root, encoding="utf-8", pretty_print=True))


def item_id(name):
    return "6a9f0000-" + hashlib.sha256(name.encode("utf-8")).hexdigest()[:8]


def instance(name, transform=None):
    result = ET.Element(tag("DOMSymbolInstance"), libraryItemName=name,
                        symbolType="graphic", loop="single frame", firstFrame="0")
    if transform:
        ET.SubElement(ET.SubElement(result, tag("matrix")), tag("Matrix"),
                      **{k: format(v, ".12g") for k, v in transform.items()})
    ET.SubElement(ET.SubElement(result, tag("transformationPoint")), tag("Point"))
    return result


def layer(name, elements):
    result = ET.Element(tag("DOMLayer"), nsmap={None: URI}, name=name, color="#74906A", autoNamed="false")
    frame = ET.SubElement(ET.SubElement(result, tag("frames")), tag("DOMFrame"),
                         index="0", keyMode="9728")
    container = ET.SubElement(frame, tag("elements"))
    container.extend(elements)
    return result


def symbol(name, layers):
    root = ET.Element(tag("DOMSymbolItem"), nsmap={None: URI}, name=name,
                      itemID=item_id(name), symbolType="graphic")
    timeline = ET.SubElement(ET.SubElement(root, tag("timeline")), tag("DOMTimeline"),
                            name=name.rsplit("/", 1)[-1])
    ET.SubElement(timeline, tag("layers")).extend(layers)
    return root


def install(xfl, symbols):
    """只写本命名空间；不改其他作者的库项或脚本。"""
    doc = read(xfl / "DOMDocument.xml", preserve=True)
    includes = doc.find("x:symbols", NS)
    for entry in list(includes):
        if entry.get("href", "").startswith(PREFIX):
            includes.remove(entry)
    folders = doc.find("x:folders", NS)
    if folders is None:
        folders = ET.Element(tag("folders"))
        doc.insert(0, folders)
    existing = {f.get("name") for f in folders}
    needed = set()
    for name in symbols:
        parts = name.split("/")[:-1]
        needed.update("/".join(parts[:i]) for i in range(1, len(parts) + 1))
    for name in sorted(needed - existing):
        entry = ET.SubElement(folders, tag("DOMFolderItem"), name=name, itemID=item_id(name))
        entry.tail = folders[0].tail
    for name, root in sorted(symbols.items()):
        write(xfl / "LIBRARY" / (name + ".xml"), root)
        entry = ET.SubElement(includes, tag("Include"), href=name + ".xml", itemID=root.get("itemID"))
        entry.tail = includes[0].tail
    owned = (xfl / "LIBRARY" / PREFIX).resolve()
    for path in owned.rglob("*.xml"):
        name = path.relative_to(xfl / "LIBRARY").as_posix()[:-4]
        if name not in symbols:
            assert path.resolve().is_relative_to(owned)
            path.unlink()  # 只清除本生成器此前写入、现已退出该场景闭包的文件。
    write(xfl / "DOMDocument.xml", doc)


def import_handoff(source):
    """将两个端点姿态变成真正单帧 Graphic，保留原生色面与分件矩阵。"""
    source = source.resolve()
    roots = {}
    provenance = []

    def freeze(name, pose=0, selected_frame=0):
        if name == "Rhino/Gun/Elevation":
            selected_frame = pose * 2
        variants = {
            "Rhino/Vehicle": "平射总成" if pose == 0 else "抬炮15度总成",
            "Rhino/Turret": "Turret/平射" if pose == 0 else "Turret/抬炮15度",
            "Rhino/Gun/Elevation": "Gun/平射" if pose == 0 else "Gun/抬炮15度",
        }
        target = PREFIX + variants.get(name, name.removeprefix("Rhino/"))
        if target in roots:
            return target
        path = source / "LIBRARY" / (name + ".xml")
        original = read(path)
        output = []
        roots[target] = None
        for old_layer in original.findall("./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer", NS):
            if old_layer.get("layerType") in ("guide", "folder"):
                continue
            if old_layer.get("layerType") in ("mask", "masked"):
                raise ValueError("需要显式处理遮罩：" + name)
            frames = [f for f in old_layer.findall("./x:frames/x:DOMFrame", NS)
                      if int(f.get("index", 0)) <= selected_frame
                      < int(f.get("index", 0)) + int(f.get("duration", 1))]
            if not frames:
                continue
            if len(frames) != 1 or frames[0].get("tweenType"):
                raise ValueError("需要明确的静态关键帧：" + name)
            elements = frames[0].find("x:elements", NS)
            if elements is None or not len(elements):
                continue
            copies = []
            for element in elements:
                if element.get("name") in ("muzzle_mc", "muzzleDirection_mc"):
                    continue
                obj = copy.deepcopy(element)
                for script in obj.findall(".//x:Actionscript", NS):
                    script.getparent().remove(script)
                for obj_instance in ([obj] if obj.tag == tag("DOMSymbolInstance") else []) + obj.findall(".//x:DOMSymbolInstance", NS):
                    child_name = obj_instance.get("libraryItemName")
                    child_frame = int(obj_instance.get("firstFrame", 0))
                    obj_instance.set("libraryItemName", freeze(child_name, pose, child_frame))
                    obj_instance.set("symbolType", "graphic")
                    obj_instance.set("loop", "single frame")
                    obj_instance.set("firstFrame", "0")
                    obj_instance.attrib.pop("name", None)
                copies.append(obj)
            if copies:
                output.append(layer(old_layer.get("name"), copies))
        roots[target] = symbol(target, output)
        provenance.append({"sourceSymbol": name, "sourceFrame": selected_frame + 1,
                           "sourceSha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                           "staticSymbol": target})
        return target

    freeze("Rhino/Vehicle", 0)
    freeze("Rhino/Vehicle", 15)
    # 独立接地阴影，缩放和倾斜跟随总成；不引入位图或滤镜。
    shadow = ET.Element(tag("DOMShape"))
    style = ET.SubElement(ET.SubElement(shadow, tag("fills")), tag("FillStyle"), index="1")
    ET.SubElement(style, tag("SolidColor"), color="#000000", alpha="0.18")
    edge = "! -11000 0 [ -11000 -340 0 -340 [ 11000 -340 11000 0 [ 11000 340 0 340 [ -11000 340 -11000 0"
    ET.SubElement(ET.SubElement(shadow, tag("edges")), tag("Edge"), fillStyle1="1", edges=edge)
    roots[PREFIX + "接地阴影"] = symbol(PREFIX + "接地阴影", [layer("柔和接地", [shadow])])
    for label in ("平射", "抬炮15度"):
        roots[PREFIX + label + "摆件"] = symbol(PREFIX + label + "摆件", [
            layer("原生静态分件", [instance(PREFIX + label + "总成")]),
            layer("接地阴影", [instance(PREFIX + "接地阴影")]),
        ])
    install(AUTHORITY, roots)
    record = ROOT / "flashswf/arts/new/Codex素材源稿/犀牛坦克R09/来源.json"
    record.parent.mkdir(parents=True, exist_ok=True)
    record.write_text(json.dumps({
        "source": "R09-犀牛坦克-Animate交付包 / Rhino-R09-XFL",
        "originalFlaSha256": "a38f444503cca625ed7ebb5cea1719c2518758cc87d55e9413912ec73810524a",
        "sourceDocumentSha256": hashlib.sha256((source / "DOMDocument.xml").read_bytes()).hexdigest(),
        "authority": str(AUTHORITY.relative_to(ROOT)).replace("\\", "/"),
        "namespace": PREFIX, "scope": "只导入零履带相位下平射及15度抬炮，全部单帧Graphic，无AS3代码",
        "symbols": provenance,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("已导入静态真源：", len(roots), "元件")


def load_authority():
    return {r.get("name"): r for p in sorted((AUTHORITY / "LIBRARY" / PREFIX).rglob("*.xml"))
            for r in [read(p)]}


def closure(symbols, start):
    selected = {}
    def visit(name):
        if name in selected:
            return
        r = symbols[name]
        selected[name] = r
        for i in r.findall(".//x:DOMSymbolInstance", NS):
            visit(i.get("libraryItemName"))
    visit(start)
    return selected


def right_facing_variant(symbols):
    """整车由摆放矩阵镜像；编号和圆徽在局部再反射一次以保持可读。"""
    pairs = [("Turret/抬炮15度", "Turret/右向抬炮15度"),
             ("抬炮15度总成", "右向抬炮15度总成"),
             ("抬炮15度摆件", "右向抬炮15度摆件")]
    remap = {PREFIX + old: PREFIX + new for old, new in pairs}
    for old, new in pairs:
        r = copy.deepcopy(symbols[PREFIX + old])
        r.set("name", PREFIX + new)
        r.set("itemID", item_id(PREFIX + new))
        r.find("./x:timeline/x:DOMTimeline", NS).set("name", new.rsplit("/", 1)[-1])
        for i in r.findall(".//x:DOMSymbolInstance", NS):
            name = i.get("libraryItemName")
            if name in remap:
                i.set("libraryItemName", remap[name])
            if name == PREFIX + "Parts/turret-tactical-mark":
                old_matrix = i.find("x:matrix", NS)
                if old_matrix is not None:
                    # 交付件在炮塔中本来为单位矩阵；不覆盖未知改稿变换。
                    values = old_matrix.find("x:Matrix", NS).attrib
                    assert all(abs(float(values.get(k, default)) - default) < 1e-8
                               for k, default in {"a": 1, "b": 0, "c": 0, "d": 1, "tx": 0, "ty": 0}.items())
                    i.remove(old_matrix)
                mat = ET.Element(tag("matrix"))
                # 实测该组 x 范围 [-53.3, 68.35]，围绕其中心反射，不改变占位框。
                ET.SubElement(mat, tag("Matrix"), a="-1", d="1", tx="15.05")
                i.insert(0, mat)
        symbols[PREFIX + new] = r


def numbered_variants(symbols):
    """沿用27号的原生刷印笔画拼出28/29；不用字体，也没有运行时随机编号。"""
    original = symbols[PREFIX + "Parts/turret-tactical-mark"]
    for number in (22, 23, 25, 26, 28, 29):
        name = PREFIX + "Parts/turret-tactical-mark-" + str(number)
        mark = copy.deepcopy(original)
        mark.set("name", name)
        mark.set("itemID", item_id(name))
        mark.find("./x:timeline/x:DOMTimeline", NS).set("name", name.rsplit("/", 1)[-1])
        paint = next(l for l in mark.findall(".//x:DOMLayer", NS) if l.get("name") == "色面 1")
        paint.set("name", "固定车号" + str(number))
        elements = paint.find("./x:frames/x:DOMFrame/x:elements", NS)
        groups = elements.findall("x:DOMGroup", NS)
        assert len(groups) == 8, "27号原生刷印分件发生变化，需要重新核对笔画"
        # 第二位沿用同一组刷印笔画，保持字宽、色彩及模板风格。
        if number == 22:
            for old in groups[5:]:
                elements.remove(old)
            additions = [(i, {"tx": 31}) for i in range(5)]
        else:
            additions = [(2, {"tx": 31}), (4, {"tx": 31})]
            if number in (25, 26, 28, 29):
                additions.append((6, {"a": -1, "d": 1, "tx": -16.2}))
            if number in (25, 26):
                elements.remove(groups[6])
            if number in (26, 28):
                additions.append((3, {"tx": 31}))
        for index, transform in additions:
            addition = copy.deepcopy(groups[index])
            assert addition.find("x:matrix", NS) is None
            # CS6 的 DOMGroup 不接受实例式 matrix；直接变换原生边坐标。
            # 保留二次曲线，镜像时交换边两侧填充，不能只改坐标后反转内外。
            for edge in addition.findall(".//x:Edge", NS):
                commands = []
                for segment in segments(edge.get("edges", "")):
                    coords = [(round((x * transform.get("a", 1) + transform.get("tx", 0)) * 20),
                               round(y * 20)) for x, y in segment]
                    commands.append("! " + " ".join(map(str, coords[0])) + (" [ " if len(coords) == 3 else " | ")
                                    + " ".join(str(v) for pair in coords[1:] for v in pair))
                edge.set("edges", " ".join(commands))
                if transform.get("a", 1) < 0:
                    left, right = edge.get("fillStyle0"), edge.get("fillStyle1")
                    edge.attrib.pop("fillStyle0", None)
                    edge.attrib.pop("fillStyle1", None)
                    if left is not None:
                        edge.set("fillStyle1", left)
                    if right is not None:
                        edge.set("fillStyle0", right)
            elements.append(addition)
        symbols[name] = mark
    variants = [(n, ["Turret/平射", "平射总成", "平射摆件"],
                 ["Turret/平射" + str(n), "平射" + str(n) + "总成", "平射" + str(n) + "摆件"])
                for n in (22, 23, 25, 26, 28)]
    variants.append(
        (29, ["Turret/右向抬炮15度", "右向抬炮15度总成", "右向抬炮15度摆件"],
         ["Turret/右向抬炮15度29", "右向抬炮15度29总成", "右向抬炮15度29摆件"]))
    for number, old_names, new_names in variants:
        remap = {PREFIX + old: PREFIX + new for old, new in zip(old_names, new_names)}
        remap[PREFIX + "Parts/turret-tactical-mark"] = PREFIX + "Parts/turret-tactical-mark-" + str(number)
        for old, new in zip(old_names, new_names):
            r = copy.deepcopy(symbols[PREFIX + old])
            r.set("name", PREFIX + new)
            r.set("itemID", item_id(PREFIX + new))
            r.find("./x:timeline/x:DOMTimeline", NS).set("name", new.rsplit("/", 1)[-1])
            for i in r.findall(".//x:DOMSymbolInstance", NS):
                if i.get("libraryItemName") in remap:
                    i.set("libraryItemName", remap[i.get("libraryItemName")])
            symbols[PREFIX + new] = r


def placement_matrix(config):
    radians = math.radians(config.get("rotationDegrees", 0))
    scale = config["scale"]
    sign = -1 if config.get("mirror") else 1
    return {"a": sign * scale * math.cos(radians), "b": sign * scale * math.sin(radians),
            "c": -scale * math.sin(radians), "d": scale * math.cos(radians),
            "tx": config["x"], "ty": config["y"]}


def vehicles(config):
    return [dict(config, **v) for v in config.get("vehicles", [{}])]


def place(config):
    path = ROOT / config["xfl"] / config["containerXml"]
    root = read(path, preserve=True)
    layers = root.find(config["layersPath"], NS)
    for old in list(layers):
        if old.get("name") == LAYER:
            layers.remove(old)
    replacement = config.get("replaceSymbol")
    if replacement:
        for old in root.findall(".//x:DOMSymbolInstance", NS):
            if old.get("libraryItemName") == replacement:
                old.getparent().remove(old)
    elements = []
    for vehicle in vehicles(config):
        obj = instance(PREFIX + vehicle["pose"] + "摆件", placement_matrix(vehicle))
        if vehicle.get("colorMultiplier") is not None:
            multiplier = str(vehicle["colorMultiplier"])
            ET.SubElement(ET.SubElement(obj, tag("color")), tag("Color"),
                          redMultiplier=multiplier, greenMultiplier=multiplier, blueMultiplier=multiplier)
        elements.append(obj)
    added = layer(LAYER, elements)
    ET.indent(added, space="  ", level=4)
    added.tail = layers[0].tail if len(layers) else "\n"
    if ROOT / config["xfl"] == AUTHORITY:
        # 老地图的 Edge 属性含原始换行；只插入自己的图层，避免序列化改写其他色面。
        content = path.read_text(encoding="utf-8")
        content = re.sub(r'\n[ \t]*<(?:\w+:)?DOMLayer\b[^>]*\bname="' + re.escape(LAYER)
                         + r'"[^>]*>.*?</(?:\w+:)?DOMLayer>', "", content, flags=re.S)
        added.tail = None
        text = "        " + ET.tostring(added, encoding="unicode").replace(' xmlns="' + URI + '"', "")
        if config.get("insertBeforeLayer"):
            anchor = '        <DOMLayer name="' + config["insertBeforeLayer"] + '"'
            assert content.count(anchor) == 1
            content = content.replace(anchor, text + "\n" + anchor, 1)
        else:
            assert content.count("<layers>") == 1
            content = content.replace("<layers>", "<layers>\n" + text, 1)
        path.write_text(content, encoding="utf-8")
        return
    index = config.get("layerIndex", 0)
    if config.get("insertBeforeLayer"):
        index = next(i for i, l in enumerate(layers) if l.get("name") == config["insertBeforeLayer"])
    layers.insert(index, added)
    write(path, root)


def normalized(root):
    """忽略 CS6 的编辑器状态与缓存标识；保留几何、色面、时间轴和引用。"""
    root = copy.deepcopy(root)
    ignored = {"itemID", "lastModified", "lastUniqueIdentifier", "selected", "isSelected",
               "current", "centerPoint3DX", "centerPoint3DY", "lastModifiedDate"}
    for e in root.iter():
        if e.text is not None and not e.text.strip():
            e.text = None
        e.tail = None
        for key in ignored:
            e.attrib.pop(key, None)
        # 属性顺序不影响 XML 语义。
        values = sorted(e.attrib.items())
        e.attrib.clear()
        e.attrib.update(values)
    return ET.tostring(root, method="c14n")


def check(symbols, configs):
    count = 0
    all_vehicles = [v for c in configs for v in vehicles(c)]
    assert len({v["vehicleNumber"] for v in all_vehicles}) == len(all_vehicles), "所有车号必须互不相同"
    for name, r in symbols.items():
        assert r.get("symbolType") == "graphic", name
        assert not r.findall(".//x:Actionscript", NS), name
        assert not r.findall(".//x:DOMBitmapInstance", NS), name
        assert not r.findall(".//x:DOMGroup/x:matrix", NS), "CS6 分组不接受实例矩阵：" + name
        assert not any(k.startswith("linkage") for k in r.attrib), name
        for f in r.findall(".//x:DOMFrame", NS):
            assert f.get("index") == "0" and int(f.get("duration", 1)) == 1, name
        for i in r.findall(".//x:DOMSymbolInstance", NS):
            assert i.get("libraryItemName") in symbols, name
            assert i.get("symbolType") == "graphic" and i.get("loop") == "single frame", name
    for config in all_vehicles:
        xfl = ROOT / config["xfl"]
        expected = closure(symbols, PREFIX + config["pose"] + "摆件")
        number = config["vehicleNumber"]
        assert PREFIX + "Parts/turret-tactical-mark" + ("" if number == 27 else "-" + str(number)) in expected
        doc = read(xfl / "DOMDocument.xml")
        includes = {i.get("href") for i in doc.findall("./x:symbols/x:Include", NS)}
        for name, r in expected.items():
            assert name + ".xml" in includes, "缺少 Include：" + name
            actual = read(xfl / "LIBRARY" / (name + ".xml"))
            assert normalized(actual) == normalized(r), "派生分件偏离真源：" + str(xfl) + "/" + name
        root = read(xfl / config["containerXml"])
        layers = root.find(config["layersPath"], NS)
        placed = [l for l in layers if l.get("name") == LAYER]
        assert len(placed) == 1, config["name"]
        candidates = [i for i in placed[0].findall(".//x:DOMSymbolInstance", NS)
                      if i.get("libraryItemName") == PREFIX + config["pose"] + "摆件"]
        assert len(candidates) == 1
        i = candidates[0]
        assert i.get("libraryItemName") == PREFIX + config["pose"] + "摆件"
        actual = i.find("./x:matrix/x:Matrix", NS)
        for key, value in placement_matrix(config).items():
            assert abs(float(actual.get(key, 0)) - value) < 0.0001, (config["name"], key)
        if config.get("insertBeforeLayer"):
            assert list(layers).index(placed[0]) + 1 == next(
                n for n, l in enumerate(layers) if l.get("name") == config["insertBeforeLayer"]), "后景层次错误"
        if config.get("colorMultiplier") is not None:
            color = i.find("./x:color/x:Color", NS)
            assert color is not None
            assert all(abs(float(color.get(channel)) - config["colorMultiplier"]) < 1e-6
                       for channel in ("redMultiplier", "greenMultiplier", "blueMultiplier"))
        if config.get("replaceSymbol"):
            assert not any(i.get("libraryItemName") == config["replaceSymbol"]
                           for i in root.findall(".//x:DOMSymbolInstance", NS)), config["name"]
        if config.get("collisionWorld"):
            envs = read(ROOT / "data/environment/stage_environment.xml")
            env = next(e for e in envs if e.findtext("BackgroundURL") == xfl.name + ".swf")
            collisions = [[[float(v) for v in p.text.split(",")] for p in c.findall("Point")]
                          for c in env.findall("Collision")]
            assert config["collisionWorld"] in collisions, "坦克接地区域碰撞未同步"
        count += len(expected)
    print(f"静态检查通过：{len(symbols)}个真源元件、{len(configs)}张地图/{len(all_vehicles)}辆坦克、{count}个派生引用；无脚本/循环/位图实例")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--import-xfl", type=Path, help="首次导入外部完整XFL；后续编辑地图-军阀基地中的静态真源")
    parser.add_argument("--check", action="store_true", help="只读核对派生、摆放和静态开销边界")
    args = parser.parse_args()
    if args.import_xfl and args.check:
        parser.error("导入与只读检查不能同时使用")
    if args.import_xfl:
        import_handoff(args.import_xfl)
    symbols = load_authority()
    if not symbols:
        raise SystemExit("没有犀牛静态真源")
    configs = json.loads(CONFIG.read_text(encoding="utf-8"))["placements"]
    if not args.check:
        right_facing_variant(symbols)
        numbered_variants(symbols)
        install(AUTHORITY, symbols)
        for config in configs:
            target = ROOT / config["xfl"]
            if target != AUTHORITY:
                selected = {}
                for vehicle in vehicles(config):
                    selected.update(closure(symbols, PREFIX + vehicle["pose"] + "摆件"))
                install(target, selected)
            place(config)
    check(symbols, configs)


if __name__ == "__main__":
    main()
