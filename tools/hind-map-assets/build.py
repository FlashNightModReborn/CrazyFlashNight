"""雌鹿 G04 交接稿 G03R1 坠毁机静态装配；目标 gk1_4_BG（主线34前置关图1 主角迫降场景）。

复用 tools/rhino-map-assets/build.py 的 XML 原语，同 tigr 模式。
与犀牛/猛虎的差异：唯一消费者即 gk1_4_BG 自身，AUTHORITY 直接定为该背景 XFL，
真源与摆放同一工程、一次发布，不为单消费者素材在无关地图间搬运闭包。
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("map_xml", ROOT / "tools/rhino-map-assets/build.py")
x = importlib.util.module_from_spec(spec)
spec.loader.exec_module(x)
x.PREFIX = PREFIX = "Codex/雌鹿G04/"
x.LAYER = "雌鹿G04-静态摆件"
x.AUTHORITY = ROOT / "flashswf/backgrounds/gk1_4_BG_坠毁"
CONFIG = Path(__file__).with_name("placements.json")
NS, ET = x.NS, x.ET


def freeze(source):
    """整元件冻结：保留原生遮罩/parentLayerIndex，只收 index=0 帧。"""
    result, provenance = {}, []

    def visit(name):
        target = PREFIX + name.removeprefix("Hind/")
        if target in result:
            return target
        path = source / "LIBRARY" / (name + ".xml")
        r = x.read(path)
        r.set("name", target)
        r.set("itemID", x.item_id(target))
        r.set("symbolType", "graphic")
        for k in list(r.attrib):
            if k.startswith("linkage"):
                del r.attrib[k]
        tl = r.find("./x:timeline/x:DOMTimeline", NS)
        tl.set("name", target.rsplit("/", 1)[-1])
        tl.attrib.pop("currentFrame", None)
        for lyr in tl.find("x:layers", NS):
            if lyr.get("layerType") in ("guide", "folder"):
                continue
            frames = lyr.find("x:frames", NS)
            keep = [f for f in frames if int(f.get("index", 0)) == 0]
            # FactionSlot 帧0=A兵团徽记、帧1=Warlord；只留 index=0 自然落到 A。
            assert keep, name
            for f in list(frames):
                if f not in keep:
                    frames.remove(f)
            for f in keep:
                f.set("index", "0")
                f.set("duration", "1")
                f.attrib.pop("tweenType", None)
                for script in f.findall(".//x:Actionscript", NS):
                    script.getparent().remove(script)
        result[target] = r
        # 先冻结帧再收集引用，被丢弃帧里的元件（如 WarlordOriginal）不进库。
        for inst in r.findall(".//x:DOMSymbolInstance", NS):
            inst.set("libraryItemName", visit(inst.get("libraryItemName")))
            inst.set("symbolType", "graphic")
            inst.set("loop", "single frame")
            inst.set("firstFrame", "0")
            inst.attrib.pop("name", None)
        provenance.append(dict(sourceSymbol=name, staticSymbol=target,
                               sourceSha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        return target

    visit("Hind/G03R1/Assembly/A_Static")
    # 包装摆件：单层引用总成；残骸自带接地关系，不另加接地阴影。
    result[PREFIX + "坠毁摆件"] = x.symbol(PREFIX + "坠毁摆件", [
        x.layer("坠毁总成", [x.instance(PREFIX + "G03R1/Assembly/A_Static")])])
    x.install(x.AUTHORITY, result)
    record = ROOT / "flashswf/arts/new/Codex素材源稿/雌鹿直升机G04/来源.json"
    data = json.loads(record.read_text(encoding="utf-8"))
    data.update(dict(
        authority=str(x.AUTHORITY.relative_to(ROOT)).replace("\\", "/"), namespace=PREFIX,
        scope=(data.get("scope", "") + "；接入侧只取 G03R1 A 兵团静态坠毁终态闭包，"
               "FactionSlot 冻结 A 帧，全单帧 Graphic，无脚本无位图无 linkage"),
        symbols=provenance))
    record.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("已导入静态真源：", len(result), "元件")


def place(config):
    """gk1_4_BG 为 CS6 另存的新 XFL，无老地图 Edge 换行保护需求，直接序列化插入。"""
    path = ROOT / config["xfl"] / config["containerXml"]
    root = x.read(path, preserve=True)
    layers = root.find(config["layersPath"], NS)
    for old in list(layers):
        if old.get("name") == x.LAYER:
            layers.remove(old)
    elements = []
    for v in x.vehicles(config):
        obj = x.instance(PREFIX + v["pose"] + "摆件", x.placement_matrix(v))
        if v.get("colorMultiplier") is not None:
            m = str(v["colorMultiplier"])
            ET.SubElement(ET.SubElement(obj, x.tag("color")), x.tag("Color"),
                          redMultiplier=m, greenMultiplier=m, blueMultiplier=m)
        elements.append(obj)
    added = x.layer(x.LAYER, elements)
    if config.get("insertBeforeLayer"):
        index = next(i for i, l in enumerate(layers) if l.get("name") == config["insertBeforeLayer"])
    else:
        index = config.get("layerIndex", 0)
    layers.insert(index, added)
    x.write(path, root)


def check(symbols, configs):
    for name, r in symbols.items():
        assert r.get("symbolType") == "graphic", name
        assert not r.findall(".//x:Actionscript", NS), name
        assert not r.findall(".//x:DOMBitmapInstance", NS), name
        assert not r.findall(".//x:DOMText", NS), name
        assert not any(k.startswith("linkage") for k in r.attrib), name
        for f in r.findall(".//x:DOMFrame", NS):
            assert f.get("index") == "0" and int(f.get("duration", 1)) == 1, name
        for i in r.findall(".//x:DOMSymbolInstance", NS):
            assert i.get("libraryItemName") in symbols, name
            assert i.get("symbolType") == "graphic" and i.get("loop") == "single frame", name
    # 原生遮罩链：每个 mask 层后的 masked 层必须仍挂 parentLayerIndex。
    for name, r in symbols.items():
        layers = r.findall("./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer", NS)
        for idx, lyr in enumerate(layers):
            if lyr.get("layerType") == "mask":
                masked = [l for l in layers if l.get("parentLayerIndex") == str(idx)]
                assert masked, "遮罩层没有被遮盖层：" + name
    slot = symbols.get(PREFIX + "Identity/FactionSlot")
    assert slot is not None
    assert any(i.get("libraryItemName") == PREFIX + "Identity/AOriginal"
               for i in slot.findall(".//x:DOMSymbolInstance", NS))
    assert PREFIX + "Identity/WarlordOriginal" not in symbols, "军阀徽记不应进入闭包"
    for c in configs:
        target = ROOT / c["xfl"]
        doc = x.read(target / "DOMDocument.xml")
        includes = {i.get("href") for i in doc.findall("./x:symbols/x:Include", NS)}
        layers = x.read(target / c["containerXml"]).find(c["layersPath"], NS)
        own = [l for l in layers if l.get("name") == x.LAYER]
        assert len(own) == 1
        insts = own[0].findall(".//x:DOMSymbolInstance", NS)
        assert len(insts) == len(x.vehicles(c))
        if c.get("insertBeforeLayer"):
            assert list(layers).index(own[0]) + 1 == next(
                i for i, l in enumerate(layers) if l.get("name") == c["insertBeforeLayer"])
        for v, i in zip(x.vehicles(c), insts):
            name = PREFIX + v["pose"] + "摆件"
            assert i.get("libraryItemName") == name
            for k, value in x.placement_matrix(v).items():
                assert abs(float(i.find("x:matrix/x:Matrix", NS).get(k, 0)) - value) < 0.0001
            for name2, r in x.closure(symbols, name).items():
                assert name2 + ".xml" in includes
                assert x.normalized(x.read(target / "LIBRARY" / (name2 + ".xml"))) == x.normalized(r), name2
        if c.get("replaceSymbol"):
            assert not any(i.get("libraryItemName") == c["replaceSymbol"]
                           for i in x.read(target / c["containerXml"]).findall(".//x:DOMSymbolInstance", NS))
    print("雌鹿静态检查通过：%d个真源元件，%d张地图" % (len(symbols), len(configs)))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--import-xfl", type=Path)
    p.add_argument("--check", action="store_true")
    a = p.parse_args()
    if a.import_xfl and a.check:
        p.error("导入不能与只读检查混用")
    if a.import_xfl:
        freeze(a.import_xfl)
    symbols = x.load_authority()
    assert symbols, "先导入原稿"
    configs = json.loads(CONFIG.read_text("utf-8"))["placements"]
    if not a.check:
        x.install(x.AUTHORITY, symbols)
        for c in configs:
            if ROOT / c["xfl"] != x.AUTHORITY:
                selected = {}
                for v in x.vehicles(c):
                    selected.update(x.closure(symbols, PREFIX + v["pose"] + "摆件"))
                x.install(ROOT / c["xfl"], selected)
            place(c)
    check(symbols, configs)


if __name__ == "__main__":
    main()
