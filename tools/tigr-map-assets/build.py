"""猛虎 G05 交接稿的静态地图装配；原生色面、渐变及轮腔遮罩保持可编辑。"""
from __future__ import annotations
import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("map_xml", ROOT / "tools/rhino-map-assets/build.py")
x = importlib.util.module_from_spec(spec)
spec.loader.exec_module(x)
x.PREFIX = PREFIX = "Codex/猛虎G05/"
x.LAYER = "猛虎G05-静态摆件"
CONFIG = Path(__file__).with_name("placements.json")
NS, ET = x.NS, x.ET


def freeze(source):
    """只读取交接包。冻结零相位，保留遮罩层序及 parentLayerIndex。"""
    result, provenance = {}, []
    def visit(name):
        target = PREFIX + name.removeprefix("Tigr/")
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
        for layer in tl.find("x:layers", NS):
            frames = layer.find("x:frames", NS)
            first = frames[0]
            assert int(first.get("index", 0)) == 0
            for f in list(frames)[1:]:
                frames.remove(f)
            first.set("index", "0")
            first.set("duration", "1")
            for script in first.findall("x:Actionscript", NS):
                first.remove(script)
        result[target] = r
        for inst in r.findall(".//x:DOMSymbolInstance", NS):
            # 作者控制器 g04Apply 的 10° 停驶/停火/停转状态，直接写原生矩阵。
            if name == "Tigr/AA/SharedAssembly" and inst.get("name") == "moving_mc":
                c, s = math.cos(math.radians(10)), math.sin(math.radians(10))
                m = inst.find("x:matrix/x:Matrix", NS)
                m.attrib.clear()
                m.attrib.update({k: str(v) for k, v in dict(
                    a=-0.9945218953682733*c, b=0.021732689536559883*c-0.9781476007338057*s,
                    c=-0.9945218953682733*s, d=0.021732689536559883*s+0.9781476007338057*c).items()})
            inst.set("libraryItemName", visit(inst.get("libraryItemName")))
            inst.set("symbolType", "graphic")
            inst.set("loop", "single frame")
            inst.set("firstFrame", "0")
            inst.attrib.pop("name", None)
        provenance.append(dict(sourceSymbol=name, staticSymbol=target,
                               sourceSha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        return target
    visit("Tigr/Vehicle")
    x.install(x.AUTHORITY, result)
    record = ROOT / "flashswf/arts/new/Codex素材源稿/猛虎运输车G05/来源.json"
    record.parent.mkdir(parents=True, exist_ok=True)
    record.write_text(json.dumps(dict(
        package="G05-猛虎运输车-Animate交接包-20260914.zip", artwork="G04 Final",
        originalFlaSha256="ffac8c612e6450d2eec310713b82bddfa9486cd63e83ff5a769a7a63f56e3629",
        authority=x.AUTHORITY.relative_to(ROOT).as_posix(), namespace=PREFIX,
        scope="零轮转/零转管/零后座、10度俯仰、全层单帧Graphic，保留原生遮罩与渐变；不导入AS3控制器",
        symbols=provenance), ensure_ascii=False, indent=2)+"\n", encoding="utf8")


def number_symbol(number):
    # 原生矢量喷涂车号，避免字体依赖；按车体侧面斜率摆放。
    bars = [(0,0,17,4),(14,0,4,20),(14,19,4,20),(0,35,17,4),(0,19,4,20),(0,0,4,20),(0,17,17,4)]
    digits = {"1": [1,2], "2": [0,1,6,4,3], "3": [0,1,6,2,3], "4": [5,6,1,2], "5": [0,5,6,2,3]}
    shapes=[]
    for pos, digit in enumerate(str(number)):
        for b in digits[digit]:
            a,t,w,h=bars[b];a+=pos*25
            shape=ET.Element(x.tag("DOMShape"))
            style=ET.SubElement(ET.SubElement(shape,x.tag("fills")),x.tag("FillStyle"),index="1")
            ET.SubElement(style,x.tag("SolidColor"),color="#DDD4B8",alpha="0.85")
            coords=[(a,t),(a+w,t),(a+w,t+h),(a,t+h),(a,t)]
            edge="! "+" | ".join(f"{u*20} {v*20}" for u,v in coords)
            ET.SubElement(ET.SubElement(shape,x.tag("edges")),x.tag("Edge"),fillStyle1="1",edges=edge)
            shapes.append(shape)
    name=PREFIX+f"车号/{number}"
    return name,x.symbol(name,[x.layer("固定车号",shapes)])


def variants(symbols):
    # 原稿坐标原点在车底上方。车体中点 x=-36.924；近轮接地中点 y≈78。
    for number in range(41,46):
        mark, r=number_symbol(number);symbols[mark]=r
        # 左向和右向车号分开反射，整车镜像后车号仍正读。
        for right in (False,True):
            pose=("右向" if right else "左向")+str(number)
            mark_matrix=dict(a=-1 if right else 1,b=0.02185 if right else -0.02185,d=1,
                             tx=38 if right else -5,ty=-235)
            symbols[PREFIX+pose+"摆件"]=x.symbol(PREFIX+pose+"摆件",[
                x.layer("车号",[x.instance(mark,dict(mark_matrix,tx=mark_matrix['tx']+36.924,ty=-313))]),
                x.layer("停放总成",[x.instance(PREFIX+"Vehicle",dict(tx=36.924,ty=-78))])])


def check(symbols, configs):
    for name,r in symbols.items():
        assert r.get("symbolType")=="graphic",name
        assert not r.findall(".//x:Actionscript",NS),name
        assert not r.findall(".//x:DOMBitmapInstance",NS),name
        assert not any(k.startswith("linkage") for k in r.attrib),name
        for f in r.findall(".//x:DOMFrame",NS):
            assert f.get("index")=="0" and int(f.get("duration",1))==1,name
        for i in r.findall(".//x:DOMSymbolInstance",NS):
            assert i.get("libraryItemName") in symbols,name
            assert i.get("symbolType")=="graphic" and i.get("loop")=="single frame",name
    near=symbols[PREFIX+"Wheels/NearSet"].find("./x:timeline/x:DOMTimeline/x:layers",NS)
    assert near[0].get("layerType")=="mask" and all(l.get("parentLayerIndex")=="0" for l in near[1:])
    numbers=[]
    for c in configs:
        target=ROOT/c['xfl'];doc=x.read(target/'DOMDocument.xml')
        includes={i.get('href') for i in doc.findall('./x:symbols/x:Include',NS)}
        layers=x.read(target/c['containerXml']).find(c['layersPath'],NS)
        own=[l for l in layers if l.get('name')==x.LAYER];assert len(own)==1
        instances=own[0].findall('.//x:DOMSymbolInstance',NS)
        assert len(instances)==len(x.vehicles(c))
        if c.get('insertBeforeLayer'):
            assert list(layers).index(own[0])+1==next(i for i,l in enumerate(layers) if l.get('name')==c['insertBeforeLayer'])
        for v,i in zip(x.vehicles(c),instances):
            numbers.append(v['vehicleNumber']);name=PREFIX+v['pose']+'摆件'
            assert i.get('libraryItemName')==name
            for k,value in x.placement_matrix(v).items():
                assert abs(float(i.find('x:matrix/x:Matrix',NS).get(k,0))-value)<0.0001
            for name,r in x.closure(symbols,name).items():
                assert name+'.xml' in includes
                assert x.normalized(x.read(target/'LIBRARY'/(name+'.xml')))==x.normalized(r),name
        if c.get('replaceSymbol'):
            assert not any(i.get('libraryItemName')==c['replaceSymbol'] for i in x.read(target/c['containerXml']).findall('.//x:DOMSymbolInstance',NS))
    assert len(numbers)==len(set(numbers))==5
    print(f'猛虎静态检查通过：{len(symbols)}个真源元件，3张地图5辆车，单帧/无脚本/轮腔遮罩及派生一致')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--import-xfl',type=Path);p.add_argument('--check',action='store_true');a=p.parse_args()
    if a.import_xfl and a.check:p.error('导入不能与只读检查混用')
    if a.import_xfl:freeze(a.import_xfl)
    symbols=x.load_authority();assert symbols,'先导入原稿'
    configs=json.loads(CONFIG.read_text('utf8'))['placements']
    if not a.check:
        variants(symbols);x.install(x.AUTHORITY,symbols)
        for c in configs:
            if ROOT/c['xfl']!=x.AUTHORITY:
                selected={}
                for v in x.vehicles(c):selected.update(x.closure(symbols,PREFIX+v['pose']+'摆件'))
                x.install(ROOT/c['xfl'],selected)
            x.place(c)
    check(symbols,configs)

if __name__=='__main__':main()
