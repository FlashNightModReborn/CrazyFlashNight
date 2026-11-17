"""Assemble issue 271's frozen Animate artwork into a private AVM1 library.

Animate natively samples parenting/tweens in an isolated authoring copy. CS6 alone
publishes the flattened motion; original depths, masks and artwork stay intact.
"""
from pathlib import Path, PurePosixPath
from functools import lru_cache
import argparse
import copy
import hashlib
import importlib.util
import json
import math
import re
import shutil
import subprocess
import sys
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ARCHIVE = ROOT / "flashswf/arts/new/Codex素材源稿/CF2大机器人-issue271"
SPEC = json.loads((HERE / "spec.json").read_text("utf-8"))
ANCHOR = SPEC["identity"]["anchor"]
PREFIX = SPEC["identity"]["prefix"]
LINKAGE = SPEC["identity"]["linkage"]
OWNER = ROOT / "flashswf/arts/new" / ANCHOR
NS = {"x": "http://ns.adobe.com/xfl/2008/"}
N = "{" + NS["x"] + "}"
PARSER = E.XMLParser(resolve_entities=False, strip_cdata=False)
MANIFEST = HERE / "native-manifest.json"
MOTION = HERE / "motion-samples.json"
I = (1, 0, 0, 1, 0, 0)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


native = module("cf2_tank_native", ROOT / "tools/cf6-zombie-assets/build.py")
native.SHARED_HELPERS = {old: PREFIX + "CF7/" + old for old in native.SHARED_HELPERS}
H = native.SHARED_HELPERS
death_visual = module("cf2_tank_explosion", ROOT / "tools/cf6-headbot-assets/robot_death.py")
bitmap = module("cf2_tank_bitmap", HERE/"bitmap.py")
PORT_MAPS = {}
PORT_LAYERS = {"gun":"theboss机枪手","cannon":"theboss炮塔","beam":"图层_6","grenade":"theboss炮塔"}
BEAM_PART = "1.特效/Codex4/大刀机器人/CF7/Symbol 195"
BLENDED_SYMBOLS = {"1.特效/元件 1","1.特效/元件 6","1.特效/发光",BEAM_PART,"特效与子弹/地面裂开/sprite 415"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mul(a, b):
    return (a[0]*b[0]+a[2]*b[1], a[1]*b[0]+a[3]*b[1],
            a[0]*b[2]+a[2]*b[3], a[1]*b[2]+a[3]*b[3],
            a[0]*b[4]+a[2]*b[5]+a[4], a[1]*b[4]+a[3]*b[5]+a[5])


def matrix(item):
    node = item.find("x:matrix/x:Matrix", NS)
    return tuple(float(node.get(k, I[i])) if node is not None else I[i]
                 for i, k in enumerate(("a", "b", "c", "d", "tx", "ty")))


def replace_matrix(item, value):
    old = item.find("x:matrix", NS)
    if old is not None:
        item.remove(old)
    native.set_matrix(item, value)


def as_literal(value):
    if isinstance(value, dict):
        if any(not re.fullmatch(r"[^\W\d]\w*", k) for k in value):
            raise ValueError("AS2 configuration keys must be explicit identifiers")
        return "{" + ",".join(k + ":" + as_literal(v) for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "[" + ",".join(as_literal(v) for v in value) + "]"
    return json.dumps(value, ensure_ascii=False, allow_nan=False)


@lru_cache(maxsize=1)
def source():
    origin = json.loads((ARCHIVE / "archive-origin.json").read_text("utf-8"))
    archive = ARCHIVE / origin["archive"]
    if sha(archive) != origin["sha256"] or archive.stat().st_size != origin["bytes"]:
        raise ValueError("Frozen artist archive identity changed")
    folder = ROOT / "tmp/cf2-boss/source" / origin["sha256"][:16]
    if not folder.exists():
        listing = subprocess.check_output(["tar", "-tf", str(archive)])
        try:
            names = listing.decode("utf-8").splitlines()
        except UnicodeDecodeError:
            names = listing.decode("gbk").splitlines()
        for name in names:
            path = PurePosixPath(name.replace("\\", "/"))
            if path.is_absolute() or ".." in path.parts or ":" in name:
                raise ValueError("Unsafe artist archive path: " + name)
        folder.mkdir(parents=True)
        subprocess.run(["tar", "-xf", str(archive), "-C", str(folder)], check=True)
    expected = {r["path"] for r in origin["files"]}
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file()}
    if actual != expected:
        raise ValueError("Artist extraction has missing or unexpected members")
    for row in origin["files"]:
        if sha(folder / row["path"]) != row["sha256"]:
            raise ValueError("Artist extraction changed: " + row["path"])
    symbols = {}
    for path in sorted((folder / "LIBRARY").rglob("*.xml")):
        item = E.parse(str(path), PARSER).getroot()
        if item.get("name") in symbols:
            raise ValueError("Duplicate source symbol: " + item.get("name"))
        symbols[item.get("name")] = item
    return folder, E.parse(str(folder / "DOMDocument.xml"), PARSER).getroot(), symbols


def layers(item):
    return item.findall("x:timeline/x:DOMTimeline/x:layers/x:DOMLayer", NS)


def frames(layer):
    return layer.findall("x:frames/x:DOMFrame", NS)


def active(layer, index):
    return next((f for f in frames(layer)
                 if int(f.get("index", 0)) <= index <
                 int(f.get("index", 0)) + int(f.get("duration", 1))), None)


def total(item):
    return max((int(f.get("index", 0)) + int(f.get("duration", 1))
                for layer in layers(item) for f in frames(layer)), default=1)


def clean_metadata(item):
    """Remove author caches/scripts, retaining real matrices, easing and masks."""
    for text in list(item.findall(".//x:DOMStaticText", NS)):
        content="".join(text.itertext()).strip()
        characters="".join(text.findall(".//x:characters",NS)[0].itertext()) if text.findall(".//x:characters",NS) else ""
        if characters=="全弹发射还包含那十个榴弹炮":
            text.getparent().remove(text)
    for script in list(item.findall(".//x:Actionscript", NS)):
        script.getparent().remove(script)
    for node in item.iter():
        for key in list(node.attrib):
            if (key.startswith("linkage") or key in {
                    "itemID", "lastModified", "lastUniqueIdentifier", "selected",
                    "isSelected", "current", "currentFrame", "layerDepthEnabled",
                    "rigPropagationMatrix", "layerRiggingIndex", "centerPoint3DX",
                    "centerPoint3DY", "cacheAsBitmap", "persistentData"}):
                del node.attrib[key]
        # DOMLayer.parentLayerIndex is a CS6 mask. DOMFrame's is an Animate rig.
        if node.tag == N + "DOMFrame":
            node.attrib.pop("parentLayerIndex", None)
    return item


def clone_symbol(item, name):
    result = clean_metadata(copy.deepcopy(item))
    result.set("name", name)
    result.set("itemID", native.item_id(name))
    result.find("x:timeline/x:DOMTimeline", NS).set("name", name.rsplit("/", 1)[-1])
    return result


def graphic(name, first=0):
    item = native.instance(name)
    item.set("firstFrame", str(first))
    item.set("loop", "play once")
    return item


def beam_layer_indices(art):
    result=[]
    for li,layer in enumerate(layers(art)):
        if any(inst.get("libraryItemName")==BEAM_PART
               for frame in frames(layer)
               for inst in frame.findall("x:elements/x:DOMSymbolInstance",NS)):
            result.append(li)
    return result


def beam_box_matrix(art,poses,fi):
    """Build one compact beam hitbox around the active laser sweep intersection."""
    seen=set()
    rays=[]
    for li in beam_layer_indices(art):
        for row in poses[fi].get(li,[]):
            m=row["matrix"]
            key=(round(m[0],1),round(m[1],1),round(m[4],1),round(m[5],1))
            if key not in seen:
                seen.add(key)
                rays.append(m)
    if not rays:
        return None
    ground_hits=[]
    segments=[]
    for a,b,_c,_d,tx,ty in rays:
        p1=(a*12.5+tx,b*12.5+ty)
        p2=(-a*12.5+tx,-b*12.5+ty)
        d1=(p1[0]-845.0)**2+(p1[1]-260.0)**2
        d2=(p2[0]-845.0)**2+(p2[1]-260.0)**2
        org,tip=(p1,p2) if d1<=d2 else (p2,p1)
        segments.append((org,tip))
        if tip[1]>org[1]+40.0:
            t=(780.0-org[1])/(tip[1]-org[1])
            if 0.05<=t<=1.05:
                gx=max(-480.0,min(1550.0,org[0]+t*(tip[0]-org[0])))
                ground_hits.append(gx)
    if ground_hits:
        ix_list=sorted(ground_hits)
        if 45<=fi<=101 and len(ix_list)>1:
            prog=max(0.0,min(1.0,(fi-60)/32.0))
            cx=ix_list[min(len(ix_list)-1,int(round(prog*(len(ix_list)-1))))]
        else:
            cx=sum(ix_list)/len(ix_list)
        return (280.0/25.0,0.0,0.0,200.0/25.0,cx,755.0)
    org,tip=segments[0]
    ax=max(-550.0,min(1550.0,org[0]+0.28*(tip[0]-org[0])))
    ay=max(120.0,min(680.0,org[1]+0.28*(tip[1]-org[1])))
    return (280.0/25.0,0.0,0.0,200.0/25.0,ax,ay)


@lru_cache(maxsize=1)
def native_motion():
    data=json.loads(MOTION.read_text("utf-8"))
    origin=json.loads((ARCHIVE/"archive-origin.json").read_text("utf-8"))
    if (data.get("schema")!="cf2-tank-boss.native-motion.v1"
            or data.get("archiveSha256")!=origin["sha256"]
            or data.get("samplerSha256")!=sha(HERE/"sample-motion.jsfl.template")
            or not data.get("version","").startswith("WIN 24,")):
        raise ValueError("Native motion samples do not belong to this artist/sampler")
    _,_,original=source()
    result={}
    for label,action in data["actions"].items():
        art=original["坦克大机器人/"+label]
        art_layers=layers(art)
        if (action["frameCount"]!=total(art) or len(action["poses"])!=total(art)
                or action["layers"]!=[l.get("name") for l in layers(art)]):
            raise ValueError("Native motion timeline identity changed: "+label)
        needed={li for li,layer in enumerate(art_layers)
                if any(f.get("parentLayerIndex") is not None for f in frames(layer))}
        if label=="技能":
            needed.update(li for li,layer in enumerate(art_layers) if layer.get("name") in PORT_LAYERS.values())
            needed.update(beam_layer_indices(art))
        elif label=="跑步走路":
            needed.update(li for li,layer in enumerate(art_layers) if layer.get("name")=="theboss底盘")
        poses=[]
        for pose in action["poses"]:
            rows={}
            for row in pose:
                # Unparented multi-element FX keep their original native XML;
                # only baked art and named interfaces consume sampled rows.
                if row["layer"] not in needed:continue
                rows.setdefault(row["layer"],[]).append(row)
            poses.append(rows)
        result[label]=poses
    if set(result)!={"常态","跑步走路","平a","技能","死亡"}:
        raise ValueError("Native motion action closure changed")
    return result


def add_port(symbols, source_label, port, layer_name, tip=I):
    """Named MC interfaces use the same native sampled matrices as the artwork."""
    _, _, original = source()
    art = original["坦克大机器人/" + source_label]
    src_layers = [l for l in layers(art) if l.get("name") == layer_name]
    if len(src_layers) != 1:
        raise ValueError("Ambiguous native port layer: " + layer_name)
    src_layer = src_layers[0]
    li=layers(art).index(src_layer)
    count = total(art)
    base = PREFIX + "接口/" + source_label + "/" + port
    leaf = base + "/"+source_label+"_"+port+"_接口叶"
    port_frames=[]
    poses=native_motion()[source_label]
    for fi in range(count):
        if port=="beam":
            mat=beam_box_matrix(art,poses,fi)
            elements=[] if mat is None else [native.instance(
                PREFIX+"攻击矩形",matrix=mat,symbol_type="movie clip",name="point")]
        else:
            rows=poses[fi].get(li,[])
            if port=="gun":
                candidates=[index for index,layer in enumerate(layers(art))
                            if layer.get("name") in ("theboss机枪手","theboss斧头手")]
                # The artist's two-frame hand symbol is gun on frame 0, axe on 1.
                # Stationary barrage swaps those hands; layer names alone lie.
                rows=[row for index in candidates for row in poses[fi].get(index,[])
                      if row["part"]=="待整理防具相关汇总/theboss机枪手" and row["firstFrame"]==0]
            if len(rows)>1:
                raise ValueError("Named combat port needs one authored instance: "+base)
            row=rows[0] if rows else None
            elements=[] if row is None else [native.instance(
                PREFIX+"攻击矩形",matrix=mul(row["matrix"],tip),symbol_type="movie clip",name="point")]
        port_frames.append(native.frame(fi,elements=elements))
    symbols[leaf]=native.symbol(leaf,[
        native.layer("原生取样接口",port_frames),
        native.layer("私有时钟",[native.frame(0,count,script="stop();")])],symbol_type="movie clip")
    root_name = base + "/"+source_label+"_"+port+"_接口总装"
    symbols[root_name] = native.symbol(root_name, [native.layer("原生变换分支", [native.frame(
        elements=[native.instance(leaf,symbol_type="movie clip",name="c0")],script="stop();")])],symbol_type="movie clip")
    PORT_MAPS[port] = [0]*count
    return root_name


def add_ports(symbols):
    shape = E.Element(N+"DOMShape")
    fills = E.SubElement(shape,N+"fills")
    E.SubElement(E.SubElement(fills,N+"FillStyle",index="1"),N+"SolidColor",color="#00FF00")
    E.SubElement(E.SubElement(shape,N+"edges"),N+"Edge",fillStyle1="1",
                 edges="!-250 -250|250 -250|250 250|-250 250|-250 -250")
    box = PREFIX+"攻击矩形图形"
    symbols[box] = native.symbol(box,[native.layer("25像素中心矩形",[native.frame(elements=[shape])])],
                                  symbol_type="movie clip")
    symbols[PREFIX+"攻击矩形"] = native.symbol(PREFIX+"攻击矩形",[
        native.layer("区域",[native.frame(elements=[native.instance(box,symbol_type="movie clip",name="area")])])
    ],symbol_type="movie clip")
    gun = SPEC["geometry"]["gunMuzzle"]
    cannon = SPEC["geometry"]["cannonMuzzle"]
    return {
        "gun": add_port(symbols,"技能","gun",PORT_LAYERS["gun"],(1,0,0,1,*gun)),
        "cannon": add_port(symbols,"技能","cannon",PORT_LAYERS["cannon"],(1,0,0,1,*cannon)),
        "beam": add_port(symbols,"技能","beam",PORT_LAYERS["beam"]),
        "grenade": add_port(symbols,"技能","grenade",PORT_LAYERS["grenade"])
    }


def rig_layers(label, original, symbols):
    """Bake only parented display layers from native authoring samples."""
    src_layers = layers(original)
    count = total(original)
    result = []
    poses=native_motion()[label]
    for li, src_layer in enumerate(src_layers):
        if label=="跑步走路" and src_layer.get("name")=="示例用管线":
            dipan_li=next(i for i,l in enumerate(src_layers) if l.get("name")=="theboss底盘")
            output_frames=[]
            for fi in range(count):
                dm=poses[fi][dipan_li][0]["matrix"]
                inst=native.instance("待整理防具相关汇总/示例用管线",
                                     matrix=(1,0,0,1,dm[4]+483.5,dm[5]-48.25),symbol_type="graphic")
                inst.set("loop","single frame")
                inst.set("firstFrame","0")
                output_frames.append(native.frame(fi,elements=[inst]))
            attrs={k:v for k,v in src_layer.attrib.items()
                   if k in ("layerType","parentLayerIndex","locked")}
            result.append(native.layer(src_layer.get("name"),output_frames,**attrs))
            continue
        if not any(f.get("parentLayerIndex") is not None for f in frames(src_layer)):
            result.append(clean_metadata(copy.deepcopy(src_layer)))
            continue
        output_frames = []
        for fi in range(count):
            rows=poses[fi].get(li,[])
            elements=[]
            if rows:
                frame=active(src_layer,fi)
                originals=frame.findall("x:elements/x:DOMSymbolInstance",NS)
                if [inst.get("libraryItemName") for inst in originals]!=[row["part"] for row in rows]:
                    raise ValueError("Native sample part mismatch: "+label+"/"+str(li)+"/"+str(fi))
                for original_inst,row in zip(originals,rows):
                    inst=clean_metadata(copy.deepcopy(original_inst))
                    replace_matrix(inst,row["matrix"])
                    if row["part"] in BLENDED_SYMBOLS or inst.get("blendMode"):
                        inst.set("symbolType","movie clip")
                        inst.attrib.pop("loop",None)
                        inst.attrib.pop("firstFrame",None)
                    else:
                        inst.set("symbolType","graphic")
                        inst.set("loop","single frame")
                        if row["firstFrame"] is not None:
                            inst.set("firstFrame",str(row["firstFrame"]))
                    old_color=inst.find("x:color",NS)
                    if old_color is not None:inst.remove(old_color)
                    if row["colorMult"]!=[100]*4 or row["colorAdd"]!=[0]*4:
                        color=E.SubElement(E.SubElement(inst,N+"color"),N+"Color")
                        for index,channel in enumerate(("red","green","blue","alpha")):
                            color.set(channel+"Multiplier",native.num(row["colorMult"][index]/100))
                            color.set(channel+"Offset",native.num(row["colorAdd"][index]))
                    elements.append(inst)
            output_frames.append(native.frame(fi,elements=elements))
        attrs = {k: v for k, v in src_layer.attrib.items()
                  if k in ("layerType", "parentLayerIndex", "locked")}
        result.append(native.layer(src_layer.get("name"), output_frames, **attrs))
    return result


def import_art():
    folder, doc, original = source()
    required = set()

    def visit(name):
        if name in required:
            return
        if name not in original:
            raise ValueError("Missing artist symbol: " + name)
        required.add(name)
        for item in original[name].findall(".//x:DOMSymbolInstance", NS):
            visit(item.get("libraryItemName"))

    for label in ("常态", "跑步走路", "平a", "技能", "死亡"):
        visit("坦克大机器人/" + label)
    rename = {old: PREFIX + "原画/" + old for old in required}
    symbols = {}
    for old in sorted(required):
        if old == "1.特效/阴影":
            # Runtime uses one independently grounded shadow, not donor globals.
            symbols[rename[old]] = native.symbol(rename[old], [native.layer("空", [native.frame()])])
        elif old.startswith("坦克大机器人/") and not old.endswith("/死亡"):
            art_layers=rig_layers(old.rsplit("/",1)[-1],original[old],symbols)
            art_layers.append(native.layer("私有外部时钟",[native.frame(0,total(original[old]),script="stop();")]))
            symbols[rename[old]] = native.symbol(rename[old],art_layers,symbol_type="movie clip")
        else:
            symbols[rename[old]] = clone_symbol(original[old], rename[old])
            symbols[rename[old]].set("symbolType","movie clip" if old in BLENDED_SYMBOLS else "graphic")
    for tree in symbols.values():
        for instance in tree.findall(".//x:DOMSymbolInstance", NS):
            ref = instance.get("libraryItemName")
            if ref in rename:
                instance.set("libraryItemName", rename[ref])
                has_filters=(instance.find("x:filters",NS) is not None
                             and len(instance.find("x:filters",NS))>0)
                if ref!="1.特效/阴影" and (ref in BLENDED_SYMBOLS or instance.get("blendMode") or has_filters):
                    instance.set("symbolType","movie clip")
                    instance.attrib.pop("loop",None)
                    instance.attrib.pop("firstFrame",None)
                else:
                    instance.set("symbolType","graphic")
                    instance.set("loop",instance.get("loop","loop"))
                    instance.set("firstFrame",instance.get("firstFrame","0"))
    media_by_name = {m.get("name"): m for m in doc.findall("x:media/*", NS)}
    aliases = {}
    for name in media_by_name:
        short = name.rsplit("/", 1)[-1]
        if short in aliases:
            raise ValueError("Ambiguous bitmap basename: " + short)
        aliases[short] = name
    media = {}
    for tree in symbols.values():
        for node in tree.iter():
            key = ("bitmapPath" if node.tag == N+"BitmapFill" else
                   "libraryItemName" if node.tag == N+"DOMBitmapInstance" else None)
            if key is None:
                continue
            ref = node.get(key)
            old = ref if ref in media_by_name else aliases.get(ref)
            if old is None:
                raise ValueError("Unresolved bitmap: " + str(ref))
            new = PREFIX + "位图/" + old.rsplit("/", 1)[-1]
            node.set(key, new)
            entry = copy.deepcopy(media_by_name[old])
            entry.set("name", new)
            entry.set("itemID", native.item_id(new))
            entry.attrib.pop("sourceExternalFilepath", None)
            media[new] = entry
    return symbols, media, rename, folder


def body_matrix():
    geometry = SPEC["geometry"]
    scale = geometry["scale"]
    sign=-1 if geometry.get("mirror",False) else 1
    return (scale*sign, 0, 0, scale, -geometry["ground"][0]*scale*sign,
            -geometry["ground"][1]*scale)


def add_body(symbols, name, art, start, count, mode, action=None, ports=None):
    source_label=art.rsplit("/",1)[-1]
    control = {0: {"script": 'tankMode="'+mode+'";tankFrameIdentity={};tankArtStart='
                   +str(start)+';tankArtKey="'+source_label+'";stop();_parent.tankSyncArt(this);'}}
    if mode == "attack":
        control[0]["script"] += '_parent.tankBeginAttack(this,"'+action+'");'
    elif mode == "death":
        control[0]["script"] += "_parent.tankBeginDeath(this);"
    if mode == "hit":
        art_frames = [native.frame(fi, 1, [
            native.instance(art, matrix=(1,0,0,1,dx,0), symbol_type="movie clip", name="tankArt",
                            script="onClipEvent(load){this.gotoAndStop("+str(start)+");}")
        ]) for fi, dx in enumerate((22,-16,11,-7,4,-2,0,0)[:count])]
    else:
        art_frames = [native.frame(0, count, [
            native.instance(art, symbol_type="movie clip", name="tankArt",
                            script="onClipEvent(load){this.gotoAndStop("+str(start)+");}")])]
    body_layers = [
        native.make_sparse_layer("单位私有时钟", count, control),
        native.layer("原画", art_frames),
        native.layer("内部驱动", [native.frame(0, count, [
            native.instance(PREFIX+"行为驱动", symbol_type="movie clip", name="tankBodyDriver",
                            script="onClipEvent(load){bodyIdentity=_parent.tankFrameIdentity;}"
                            "onClipEvent(enterFrame){_parent._parent.tankBodyTick(_parent,bodyIdentity);}")])])
    ]
    if ports:
        body_layers.append(native.layer("同步原生接口",[native.frame(0,count,[
            native.instance(port_name,symbol_type="movie clip",name="tankPort_"+key,alpha_mult=0,
                            script="onClipEvent(load){this._visible=false;stop();}")
            for key,port_name in ports.items()])]))
    symbols[name] = native.symbol(name,body_layers,symbol_type="movie clip")


def slice_symbol(base_tree, new_name, start_1based, count):
    """Slice a multi-action timeline so Frame 1 is the action's native start."""
    s0 = start_1based - 1
    e0 = s0 + count - 1
    result = copy.deepcopy(base_tree)
    result.set("name", new_name)
    result.set("itemID", native.item_id(new_name))
    result.set("symbolType", "movie clip")
    result.find("x:timeline/x:DOMTimeline", NS).set("name", new_name.rsplit("/", 1)[-1])
    for layer in layers(result):
        frames_el = layer.find("x:frames", NS)
        old_frames = list(frames_el)
        for f in old_frames:
            frames_el.remove(f)
        if layer.get("name") == "私有外部时钟":
            frames_el.append(native.frame(0, count, script="stop();"))
            continue
        for f in old_frames:
            idx = int(f.get("index", 0))
            dur = int(f.get("duration", 1))
            lo = max(idx, s0)
            hi = min(idx + dur - 1, e0)
            if lo <= hi:
                nf = copy.deepcopy(f)
                nf.set("index", str(lo - s0))
                new_dur = hi - lo + 1
                if new_dur > 1:
                    nf.set("duration", str(new_dur))
                else:
                    nf.attrib.pop("duration", None)
                frames_el.append(nf)
    return result


def build_symbols():
    PORT_MAPS.clear()
    symbols, media, rename, folder = import_art()
    symbols.update(native.clone_shared_helpers())
    driver = PREFIX + "行为驱动"
    symbols[driver] = native.symbol(driver, [native.layer("空", [native.frame(script="stop();")])],
                                    symbol_type="movie clip")
    ports = add_ports(symbols)
    bodies = {}
    for label, source_label, mode, count in (
            ("站立", "常态", "idle", 30), ("行走", "跑步走路", "idle", 18),
            ("被击", "常态", "hit", 8)):
        name = PREFIX + "动作/" + label
        add_body(symbols, name, rename["坦克大机器人/" + source_label], 1, count, mode)
        bodies[label] = name
    for action, spec in SPEC["actions"].items():
        name = PREFIX + "动作/" + action
        count = spec["end"]-spec["start"]+1
        base_art = rename["坦克大机器人/" + spec["source"]]
        if spec["source"] == "技能":
            art_name = PREFIX + "动作切片/" + action
            symbols[art_name] = slice_symbol(symbols[base_art], art_name, spec["start"], count)
            add_body(symbols, name, art_name, 1, count, "attack", action, ports)
        else:
            add_body(symbols, name, base_art, 1, count, "attack", action, None)
        bodies[action] = name
    add_death(symbols, rename, bodies)
    root_name = PREFIX + LINKAGE
    state_rows = [(1, "空手站立", "站立"), (9, "空手行走", "行走"),
                  (19, "空手跑", "行走"), (29, "空手跳", "站立"),
                  (37, "空手攻击", "melee"), (41, "近战", "melee"),
                  (51, "机枪射击", "gatling"), (61, "激光扫射", "laser"),
                  (71, "全弹发射", "barrage"), (81, "移动全弹", "mobile"),
                  (91, "拾取", "站立"), (96, "躲闪", "站立"),
                  (101, "被击", "被击"), (109, "击倒", "被击"),
                  (117, "倒地", "被击"), (125, "被投", "被击"),
                  (133, "血腥死", "死亡"), (150, "消失", None)]
    placements = {}
    for si, (index, _, body) in enumerate(state_rows[:-1]):
        end = state_rows[si+1][0]
        placements[index] = {"duration": end-index, "elements": [
            native.instance(bodies[body], matrix=body_matrix(), symbol_type="movie clip", name="man")]}
    ai = (HERE / "TankBossAI.as").read_text("utf-8-sig")
    init = ('tankTuning=' + as_literal(SPEC["tuning"]) + ";\n"
            'tankActions=' + as_literal(SPEC["actions"]) + ";\n"
            'tankPortMaps=' + as_literal(PORT_MAPS) + ";\n"
            'tankGrenadeMuzzles=' + as_literal(SPEC["geometry"]["grenadeMuzzles"]) + ";\n"
            'tankMeleeAreas=' + as_literal(SPEC["geometry"]["meleeAreas"]) + ";\n"
            'x轴攻击范围=0;y轴攻击范围=35;x轴保持距离=320;攻击欲望=3;命中率=30;击中效果="火花";\n'
            '男_攻击呐喊_库=[];男_中招呐喊_库=[];男_击倒呐喊_库=[];\n'
            '女_攻击呐喊_库=[];女_中招呐喊_库=[];女_击倒呐喊_库=[];\n'
            'if(typeof _root.初始化敌人模板=="function"){初始化敌人模板=_root.初始化敌人模板;初始化敌人模板();}\n'
            'x轴攻击范围=0;if(unitAI.data!=null)unitAI.data.xrange=0;area._visible=false;\n'
            + ai)
    x, y, w, h = SPEC["geometry"]["area"]
    symbols[root_name] = native.symbol(root_name, [
        native.make_sparse_layer("状态标签", 155, {i: {"name": state, "label_type": "name"}
                                                  for i, state, _ in state_rows}),
        native.make_sparse_layer("初始化", 155, {0: {"script": init},
                                                 150: {"script": "hp=0;tankCancelAttack();"}}),
        native.make_sparse_layer("私有行为", 155, {0: {"duration": 150, "elements": [
            native.instance(driver, symbol_type="movie clip", name="tankDriver",
                            script="onClipEvent(load){unitIdentity=_parent.tankIdentity;}"
                            "onClipEvent(enterFrame){_parent.tankTick(unitIdentity);}") ]}}),
        native.make_sparse_layer("文字信息", 155, {0: {"duration": 150, "elements": [
            native.instance(H["Symbol 32"], matrix=(1,0,0,1,0,-295),
                            symbol_type="movie clip", name="人物文字信息")]}}),
        native.make_sparse_layer("受击区域", 155, {0: {"duration": 133, "elements": [
            native.instance(H["Symbol 19"], matrix=(w/25,0,0,h/25,x,y),
                            symbol_type="movie clip", name="area", alpha_mult=0,
                            script="onClipEvent(load){this._visible=false;}")]}}),
        native.make_sparse_layer("通用仇恨", 155, {0: {"duration": 29, "elements": [
            native.instance(H["思考标签"], symbol_type="movie clip")]}}),
        native.make_sparse_layer("动作", 155, placements),
        native.make_sparse_layer("接地阴影", 155, {0: {"duration": 150, "elements": [
            native.instance(H["Symbol 2"], matrix=(1.95,0,0,0.42,0,0),
                            symbol_type="movie clip", name="tankShadow")]}})
    ], symbol_type="movie clip", linkage=LINKAGE, export_first_frame=True)
    return symbols, root_name, media, folder


def add_death(symbols, rename, bodies):
    """Explode this robot's own components; no inherited CF6 nuclear attack."""
    _, _, original = source()
    parts = []
    for layer in layers(original["坦克大机器人/死亡"]):
        if layer.get("name") == "影子":
            continue
        for inst in frames(layer)[0].findall("x:elements/x:DOMSymbolInstance", NS):
            if inst.get("libraryItemName") in rename:
                parts.append((rename[inst.get("libraryItemName")], matrix(inst)))
    count = 100
    fragments_name = PREFIX + "死亡/自有机体碎片"
    fragment_instances = []
    for index, (part, transform) in enumerate(parts, 1):
        name = PREFIX + "死亡/碎片" + str(index)
        content=name+"图形"
        art=native.instance(part)
        art.set("loop","single frame")
        art.set("firstFrame","0")
        symbols[content]=native.symbol(content,[native.layer("冻结原生分件",[native.frame(elements=[art])])],
                                       symbol_type="movie clip")
        symbols[name] = native.symbol(name, [native.layer("原始分件", [
            native.frame(elements=[native.instance(content, matrix=(*transform[:4],0,0),
                                                   symbol_type="movie clip",name="piece")])])],
            symbol_type="movie clip")
        fragment_instances.append(native.instance(name, matrix=(1,0,0,1,*transform[4:]),
                                                 symbol_type="movie clip", name="碎片"+str(index)))
    symbols[fragments_name] = native.symbol(fragments_name, [native.layer("预制碎片", [
        native.frame(elements=fragment_instances, script="stop();")])], symbol_type="movie clip")
    name = PREFIX + "动作/死亡"
    visual_trees = death_visual.source_trees()
    fx_names = {old:PREFIX+"死亡/爆裂/"+old.replace("/","_") for old in visual_trees}
    for old, tree in visual_trees.items():
        clone = clone_symbol(tree,fx_names[old])
        clone.set("symbolType","graphic")
        for inst in clone.findall(".//x:DOMSymbolInstance",NS):
            inst.set("libraryItemName",fx_names[inst.get("libraryItemName")])
            inst.set("symbolType","graphic")
            inst.set("loop","play once")
        symbols[fx_names[old]]=clone
    gx,gy=SPEC["geometry"]["ground"]
    symbols[name] = native.symbol(name, [
        native.make_sparse_layer("死亡控制", count, {
            0: {"script": 'tankMode="death";tankFrameIdentity={};_parent.tankBeginDeath(this);stop();'},
            11: {"script": "_parent.tankBurstDeath(this);"}}),
        native.make_sparse_layer("完整机体", count, {0: {"duration": 12, "elements": [
            graphic(rename["坦克大机器人/死亡"])]}}),
        native.make_sparse_layer("散落机体", count, {12: {"duration": count-12, "elements": [
            native.instance(fragments_name, symbol_type="movie clip", name="尸体碎片",
                script="onClipEvent(load){_parent._parent.tankStartFragments(this,"+str(len(parts))+");}")]}}),
        native.make_sparse_layer("无脚本机械爆裂",count,{10:{"duration":13,"elements":[
            native.instance(fx_names[death_visual.EXPLOSION],matrix=(4,0,0,4,gx,gy-210))]}}),
        native.layer("内部驱动", [native.frame(0, count, [
            native.instance(PREFIX+"行为驱动", symbol_type="movie clip", name="tankBodyDriver",
                script="onClipEvent(load){bodyIdentity=_parent.tankFrameIdentity;}"
                "onClipEvent(enterFrame){_parent._parent.tankBodyTick(_parent,bodyIdentity);}")])])
    ], symbol_type="movie clip")
    bodies["死亡"] = name


def guard():
    if not MANIFEST.exists():
        if OWNER.exists() and any(p.is_file() for p in OWNER.rglob("*")):
            raise ValueError("Refusing to adopt an existing untracked artwork workspace")
        return
    manifest = json.loads(MANIFEST.read_text("utf-8"))
    expected = {r["path"]: r for r in manifest["outputs"]}
    actual = {p.relative_to(OWNER).as_posix() for p in OWNER.rglob("*") if p.is_file()}
    if actual != set(expected):
        raise ValueError("Native file set changed outside the generator")
    for rel, row in expected.items():
        if sha(OWNER / rel) != row["sha256"]:
            raise ValueError("Preserve external artwork edits before regeneration: " + rel)


def inputs():
    paths = [HERE/"build.py", HERE/"spec.json", HERE/"TankBossAI.as",
             HERE/"bitmap.py",
             HERE/"motion-samples.json",HERE/"sample-motion.jsfl.template",HERE/"sample-motion.py",
             ARCHIVE/"archive-origin.json", ARCHIVE/"大机器人完整版.rar",
             ROOT/"tools/cf6-zombie-assets/build.py",
             ROOT/"flashswf/arts/new/Codex黑仔素材/PublishSettings.xml"]
    paths += [native.THINGS1/(old+".xml") for old in sorted(H)]
    paths += death_visual.input_paths()
    return [{"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p)} for p in paths]


def assemble():
    guard()
    symbols, root_name, media, folder = build_symbols()
    guard()
    symbols[ANCHOR] = native.symbol(ANCHOR, [native.layer("入口", [native.frame(
        script="stop();", elements=[native.instance(root_name, symbol_type="movie clip")])])],
        symbol_type="movie clip", linkage=ANCHOR, export_rs=True,
        url="flashswf/arts/new/"+ANCHOR+".swf")
    folder_names = {"/".join(name.split("/")[:i]) for name in [*symbols,*media]
                    for i in range(1,len(name.split("/")))}
    if folder_names.intersection(symbols) or folder_names.intersection(media):
        raise ValueError("Flash library folders and symbols share a namespace")
    written = set()

    def write(rel, data):
        target = OWNER / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes()!=data:
            pending=target.with_name(target.name+".cf2-write.tmp")
            if pending.exists():
                raise ValueError("Unresolved generated-file write: "+str(pending))
            pending.write_bytes(data)
            pending.replace(target)
        written.add(rel)

    for name, tree in sorted(symbols.items()):
        write("LIBRARY/"+name+".xml", native.xml_bytes(tree))
    doc = E.Element(N+"DOMDocument", nsmap={None:NS["x"]}, width="1024", height="576",
                    frameRate="30", xflVersion="2.2", creatorInfo="Adobe Flash Professional CS6",
                    platform="Windows", majorVersion="12", buildNumber="481",
                    versionInfo="Saved by Adobe Flash Windows 12.0 build 481",
                    backgroundColor="#333333")
    folders = E.SubElement(doc, N+"folders")
    for name in sorted(folder_names):
        E.SubElement(folders, N+"DOMFolderItem", name=name, itemID=native.item_id(name))
    # XFL is ordered XML: CS6 silently discards media declared after symbols.
    medias = E.SubElement(doc, N+"media")
    includes = E.SubElement(doc, N+"symbols")
    for name in sorted(symbols):
        E.SubElement(includes, N+"Include", href=name+".xml",
                     itemID=native.item_id(name), loadImmediate="false")
    for name, entry in sorted(media.items()):
        cache=entry.get("bitmapDataHRef")
        if not cache:raise ValueError("Frozen artist bitmap cache is missing")
        width=int(entry.get("frameRight"))//20
        height=int(entry.get("frameBottom"))//20
        href=name if name.lower().endswith(".png") else name+".png"
        original=(folder/"bin"/cache).read_bytes()
        encoded=bitmap.png(original,width,height)
        entry.set("href",href)
        entry.set("sourceExternalFilepath","./LIBRARY/"+href)
        entry.set("bitmapDataHRef",cache)
        write("LIBRARY/"+href,encoded)
        write("bin/"+cache,bitmap.cache(original,width,height))
        medias.append(entry)
    tl = E.SubElement(E.SubElement(doc,N+"timelines"),N+"DOMTimeline",name="场景 1")
    E.SubElement(tl,N+"layers").append(native.layer("共享入口", [native.frame(
        script="stop();", elements=[native.instance(ANCHOR,symbol_type="movie clip")])]))
    write("DOMDocument.xml", native.xml_bytes(doc))
    write(ANCHOR+".xfl", b"PROXY-CS5\n")
    write("MobileSettings.xml", b"")
    pub = (ROOT/"flashswf/arts/new/Codex黑仔素材/PublishSettings.xml").read_text("utf-8")
    pub = pub.replace("Codex黑仔素材",ANCHOR)
    write("PublishSettings.xml", pub.encode("utf-8"))
    if MANIFEST.exists():
        old = json.loads(MANIFEST.read_text("utf-8"))
        for row in old["outputs"]:
            if row["path"] not in written:
                (OWNER/row["path"]).unlink()  # Exact prior generated members, guarded above.
    manifest = {"schema":"cf2-tank-boss.native.v1","owner":OWNER.relative_to(ROOT).as_posix(),
                "source":ARCHIVE.relative_to(ROOT).as_posix(),"buildInputs":inputs(),
                "symbols":len(symbols),"bitmaps":len(media),"actions":SPEC["actions"],
                "excludedArtistAnnotations":["全弹发射还包含那十个榴弹炮"],
                "bitmapConversion":"validated premultiplied ARGB DAT -> actual LIBRARY PNG plus compact Adobe cache; media precedes symbols",
                "outputs":[{"path":rel,"sha256":sha(OWNER/rel),"bytes":(OWNER/rel).stat().st_size}
                           for rel in sorted(written)]}
    MANIFEST.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    print(json.dumps({"generated":True,"symbols":len(symbols),"bitmaps":len(media),
                      "sourceBytes":sum(r["bytes"] for r in manifest["outputs"])},ensure_ascii=False))


def check():
    source()
    guard()
    manifest = json.loads(MANIFEST.read_text("utf-8"))
    if manifest["buildInputs"] != inputs():
        raise ValueError("Generator inputs changed; regenerate through the guarded build")
    names = set()
    carrier_basenames=set()
    doc=E.parse(str(OWNER/"DOMDocument.xml"),PARSER)
    folder_names={e.get("name") for e in doc.findall("x:folders/x:DOMFolderItem",NS)}
    for path in sorted((OWNER/"LIBRARY").rglob("*.xml")):
        item = E.parse(str(path),PARSER).getroot()
        names.add(item.get("name"))
        name=item.get("name")
        if name.startswith((PREFIX+"骨架/",PREFIX+"接口/")):
            basename=name.rsplit("/",1)[-1]
            if basename in carrier_basenames:
                raise ValueError("CS6 carrier timeline basename collision: "+basename)
            carrier_basenames.add(basename)
        if item.findall(".//x:DOMFrame[@parentLayerIndex]",NS):
            raise ValueError("Unconverted Animate frame-parent relation")
        if any("rigPropagationMatrix" in el.attrib or "layerRiggingIndex" in el.attrib for el in item.iter()):
            raise ValueError("Animate author cache entered the CS6 source")
    if names.intersection(folder_names):
        raise ValueError("Flash library symbol/folder name collision")
    for path in (OWNER/"LIBRARY").rglob("*.xml"):
        for inst in E.parse(str(path),PARSER).findall(".//x:DOMSymbolInstance",NS):
            if inst.get("libraryItemName") not in names:
                raise ValueError("Unresolved native symbol: "+inst.get("libraryItemName"))
    if not (HERE/"TankBossAI.as").read_bytes().startswith(b"\xef\xbb\xbf"):
        raise ValueError("AS2 source lost its UTF-8 BOM")
    print(json.dumps({"ok":True,"symbols":len(names),"bitmaps":manifest["bitmaps"]}))


if __name__ == "__main__":
    if hasattr(sys.stdout,"reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--build",action="store_true")
    parser.add_argument("--check",action="store_true")
    args = parser.parse_args()
    if args.build:
        assemble()
    check()
