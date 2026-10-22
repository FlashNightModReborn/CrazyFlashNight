"""Validate CF6 layer inputs and generate native CS6 import recipes + environment fragments.

Only the root-owned CS6 session executes the recipes. No SWF bytes are written here.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
import re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ROUTE = [f"A{i:02}" for i in range(1, 23) if i not in (7, 21)]
ROLES = {"background", "foreground", "elevator-scroll", "door-left", "door-right"}


def numbers(value, count):
    return isinstance(value, list) and len(value) == count and all(
        isinstance(n, (int, float)) and not isinstance(n, bool) and math.isfinite(n) for n in value)


def inside(point, polygon):
    x,y=point;found=False
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:found=not found
    return found


def relative_file(value):
    p = Path(value)
    if p.is_absolute() or ".." in p.parts:
        raise ValueError(f"unsafe asset path: {value}")
    p = (ROOT / p).resolve()
    if not p.is_relative_to(ROOT) or not p.is_file():
        raise ValueError(f"missing asset: {value}")
    return p


def normalize(data, overrides=None):
    """Accept source index maps keyed by A-number; runtime overlays remain separately attributed."""
    data=copy.deepcopy(data)
    if isinstance(data.get("maps"),dict):
        data["maps"]=[dict(row,id=key) for key,row in data["maps"].items()]
    data['maps'].sort(key=lambda row: (ROUTE+['TUTORIAL']).index(row['id']) if row['id'] in ROUTE+['TUTORIAL'] else 999)
    for m in data.get("maps",[]):
        patch=(overrides or {}).get("maps",{}).get(m["id"],{})
        for key in ("worldScale","walkBounds","spawn","exit","collisions","leftSpawnLine","rightSpawnLine","geometryStatus","geometryBasis"):
            if key in patch:m[key]=patch[key]
        for layer in m.get("layers",[]):
            kind=patch.get("layerSourceKinds",{}).get(layer["id"])
            if kind is not None:layer["sourceKind"]=kind
    return data


def validate(data):
    if data.get("schema") != "cf6-map-input.v1":
        raise ValueError("schema must be cf6-map-input.v1")
    seen = set()
    for m in data["maps"]:
        key = m["id"]
        if key not in ROUTE + ["TUTORIAL"] or key in seen:
            raise ValueError(f"invalid/duplicate enabled map: {key}")
        seen.add(key)
        for name, size in [("nativeBounds", 4), ("walkBounds", 4), ("spawn", 2)]:
            if not numbers(m.get(name), size):
                raise ValueError(f"{key}: invalid {name}")
        if m['nativeBounds'][2]<=0 or m['nativeBounds'][3]<=0:
            raise ValueError(f"{key}: invalid native image extent")
        if not isinstance(m.get("worldScale"), (int, float)) or not 0.25 <= m["worldScale"] <= 4:
            raise ValueError(f"{key}: explicit calibrated worldScale required")
        x0, y0, x1, y1 = m["walkBounds"]
        if not x0 < x1 or not y0 < y1 or not x0 <= m["spawn"][0] <= x1 or not y0 <= m["spawn"][1] <= y1:
            raise ValueError(f"{key}: invalid walk rectangle/spawn")
        if not isinstance(m.get("exit"),dict) or not numbers(m["exit"].get("rect"), 4) or m["exit"].get("direction") not in ["左", "右", "上", "下"]:
            raise ValueError(f"{key}: invalid exit")
        er=m['exit']['rect']
        if not er[0]<er[2] or not er[1]<er[3]:raise ValueError(f"{key}: inverted exit rectangle")
        for polygon in m["collisions"]:
            if len(polygon) < 3 or not all(numbers(p, 2) for p in polygon):
                raise ValueError(f"{key}: invalid collision polygon")
            if inside(m['spawn'],polygon):raise ValueError(f"{key}: spawn is inside collision")
        for field in ('leftSpawnLine','rightSpawnLine'):
            if field in m and not numbers(m[field],4):raise ValueError(f'{key}: invalid {field}')
        backgrounds = 0
        layer_ids = set()
        for layer in m["layers"]:
            if not re.fullmatch(r"[a-z][a-z0-9-]{0,47}", layer["id"]) or layer["id"] in layer_ids or layer["role"] not in ROLES:
                raise ValueError(f"{key}: duplicate layer/invalid role")
            layer_ids.add(layer["id"])
            if layer.get("sourceKind") not in ("background", "isolated-part"):
                raise ValueError(f"{key}/{layer['id']}: scene previews are not runtime art")
            if not numbers([layer[k] for k in ["x", "y", "width", "height", "depth"]], 5):
                raise ValueError(f"{key}: invalid layer placement")
            if layer["width"] <= 0 or layer["height"] <= 0:
                raise ValueError(f"{key}: nonpositive image extent")
            if layer["role"] == "elevator-scroll" and (not isinstance(layer.get("loopHeight"), (float, int))
                    or not layer["loopHeight"] > 0 or not numbers(layer.get("clip"), 4)):
                raise ValueError(f"{key}: elevator requires native loopHeight and clipping rectangle")
            path = relative_file(layer["png"])
            if path.suffix.lower() != ".png" or path.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                raise ValueError(f"{key}: PNG layer required")
            if layer["role"] == "background": backgrounds += 1
        if not backgrounds:
            raise ValueError(f"{key}: missing independent background")
        if key in ("A10", "A13") and "elevator-scroll" not in {x["role"] for x in m["layers"]}:
            raise ValueError(f"{key}: elevator scroll cannot be flattened or omitted")
    if not seen: raise ValueError("no playable map inputs supplied")
    return data


def coordinates(m):
    scale = m["worldScale"]
    ox, oy = m["nativeBounds"][:2]
    return lambda p: [round((p[0] - ox) * scale, 4), round((p[1] - oy) * scale, 4)]


def environment(m):
    xy = coordinates(m)
    env = ET.Element("Environment")
    a, b = xy(m["walkBounds"][:2]), xy(m["walkBounds"][2:])
    for key, value in dict(BackgroundURL=f"CF6_{m['id']}_BG.swf", Alignment="true",
        Xmin=a[0], Ymin=a[1], Xmax=b[0], Ymax=b[1],
        Width=max(m["nativeBounds"][2]*m["worldScale"],b[0]), Height=max(m["nativeBounds"][3]*m["worldScale"],b[1]),
        DisableSky="true", SpaceCondition="室内", MaxIllumination=8, MinIllumination=8).items():
        ET.SubElement(env, key).text = str(value)
    door = ET.SubElement(env, "Door")
    a, b = xy(m["exit"]["rect"][:2]), xy(m["exit"]["rect"][2:])
    for key, value in dict(Index=1, Direction=m["exit"]["direction"], x0=a[0], y0=a[1], x1=b[0], y1=b[1]).items():
        ET.SubElement(door, key).text = str(value)
    for polygon in m["collisions"]:
        item = ET.SubElement(env, "Collision")
        for point in polygon:
            ET.SubElement(item, "Point").text = ",".join(map(str, xy(point)))
    for field,tag in [('leftSpawnLine','LeftSpawnLine'),('rightSpawnLine','RightSpawnLine')]:
        if field in m:
            line=ET.SubElement(env,tag)
            a,b=xy(m[field][:2]),xy(m[field][2:])
            for key,value in dict(x0=a[0],y0=a[1],x1=b[0],y1=b[1]).items():ET.SubElement(line,key).text=str(value)
    return env


def jsfl(m, layers, name, xfl):
    # CS6 imports PNG pixels itself and writes its own bitmap cache and native XFL.
    # No document other than the freshly created owned document is saved/closed.
    assets = []
    xy = coordinates(m)
    for layer in sorted(layers, key=lambda row: row["depth"]):
        x, y = xy([layer["x"], layer["y"]])
        assets.append(dict(path=str((ROOT/layer["png"]).resolve()), id=layer["id"],
            x=x,y=y,width=layer["width"]*m["worldScale"],height=layer["height"]*m["worldScale"]))
    frame_script='stop();_root.贴背景图();' if name==f"CF6_{m['id']}_BG" else 'stop();'
    return r"""// Generated recipe. Run only in the root-owned CS6 session.
(function () {
function canonicalDocumentURI(value) {
  try { return encodeURI(decodeURI(value)); } catch (uriError) { return value; }
}
// Convert only our known absolute paths, never arbitrary open documents.
var target = FLfile.platformPathToURI(%s);
var receipt = FLfile.platformPathToURI(%s + String(new Date().getTime()) + ".txt");
if (!FLfile.write(receipt, "CF6_NATIVE_IMPORT_STARTED\n" + target + "\n"))
  throw new Error("Cannot write native import receipt before creating document");
var assets = %s;
var doc = null;
try {
if (FLfile.exists(target)) throw new Error("Refusing to overwrite existing XFL: " + target);
doc = fl.createDocument();
if (!doc) throw new Error("Native document creation failed");
doc.asVersion = 2;
doc.frameRate = 30;
doc.width = %s; doc.height = %s;
var timeline = doc.getTimeline();
for (var i=0; i<assets.length; i++) {
  var a=assets[i];
  if (i>0) timeline.addNewLayer(a.id, "normal", true);
  timeline.layers[timeline.currentLayer].name=a.id;
  var sourceURI=FLfile.platformPathToURI(a.path);
  if (!FLfile.exists(sourceURI)) throw new Error("Missing PNG: " + a.path);
  doc.importFile(canonicalDocumentURI(sourceURI), false);
  if (doc.selection.length !== 1) throw new Error("Expected one PNG instance: " + a.id);
  var item=doc.selection[0];
  item.libraryItem.compressionType="lossless";
  item.libraryItem.useImportedJPEGData=false;
  item.libraryItem.allowSmoothing=true;
  item.width=a.width; item.height=a.height; item.x=a.x; item.y=a.y;
  doc.selectNone();
}
timeline.addNewLayer("stop", "normal", true);
timeline.layers[timeline.currentLayer].frames[0].actionScript=%s;
if (!fl.saveDocument(doc,canonicalDocumentURI(target))) throw new Error("XFL save failed");
if (!FLfile.write(receipt,"CF6_NATIVE_IMPORT_SAVED\n"+target+"\n","append"))
  throw new Error("Native XFL saved but receipt append failed");
fl.trace("CF6_NATIVE_IMPORT_READY %s " + target);
} catch (importError) {
  FLfile.write(receipt,"CF6_NATIVE_IMPORT_ERROR\n"+String(importError)+"\n","append");
  throw importError;
} finally {
  // This handle is assigned only by our createDocument; never use active document.
  if (doc) fl.closeDocument(doc, false);
}
})();
""" % (json.dumps(str(xfl.resolve()),ensure_ascii=False),
           json.dumps(str(ROOT/"tmp/cf6-map-runtime/native-import"/(name+"-")),ensure_ascii=False),
           json.dumps(assets, ensure_ascii=False),
           max(1, round(m["nativeBounds"][2]*m["worldScale"])), max(1, round(m["nativeBounds"][3]*m["worldScale"])),
           json.dumps(frame_script,ensure_ascii=False),name)


def build(data, mechanisms=None):
    outputs = {}
    envs = ET.Element("EnvironmentSettings")
    index = {"schema":"cf6-map-runtime.v1", "maps":[]}
    for m in data["maps"]:
        name = f"CF6_{m['id']}_BG"
        source = ROOT / "flashswf/backgrounds/cf6" / name / (name+".xfl")
        outputs[HERE / "generated" / (name+".jsfl")] = jsfl(m, [x for x in m["layers"] if x["role"]=="background"], name, source).encode("utf-8")
        envs.append(environment(m))
        row = {"id":m["id"], "background":f"cf6/{name}.swf", "xfl":source.relative_to(ROOT).as_posix(),
               "spawn":coordinates(m)(m["spawn"]), "layers":[], "inputs":[]}
        row["geometryStatus"]=m.get("geometryStatus","source-declared")
        row["geometryBasis"]=m.get("geometryBasis",m.get("basis",""))
        row["pendingDynamics"]=m.get("undeliveredDynamics",[])
        row["deferredLayers"]=m.get("deferredLayers",[])
        row["runtimeProps"]=[]
        for prop in m.get('props',[]):
            item={k:prop[k] for k in ('id','kind','png','svg','viewBox','frames') if k in prop}
            item['instances']=[dict(instance,x=coordinates(m)([instance['x'],instance['y']])[0],
                y=coordinates(m)([instance['x'],instance['y']])[1]) for instance in prop.get('instances',[])]
            item['status']='separate gameplay consumer required; not flattened into background'
            row['runtimeProps'].append(item)
        for layer in m["layers"]:
            path = ROOT/layer["png"]
            row["inputs"].append({"path":layer["png"],"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"bytes":path.stat().st_size})
            if layer["role"] == "background": continue
            dynamic_name = f"CF6_{m['id']}_{layer['id']}"
            dynamic_xfl = source.parent.parent / dynamic_name / (dynamic_name+".xfl")
            # Isolated part SWF has local origin; world placement remains explicit in config.
            local = dict(m, nativeBounds=[0,0,layer["width"],layer["height"]])
            item = dict(layer, x=0, y=0)
            outputs[HERE / "generated" / (dynamic_name+".jsfl")] = jsfl(local,[item],dynamic_name,dynamic_xfl).encode("utf-8")
            x,y = coordinates(m)([layer["x"],layer["y"]])
            dynamic={"id":layer["id"],"role":layer["role"],"url":f"flashswf/backgrounds/cf6/{dynamic_name}.swf",
                "x":x,"y":y,"width":layer["width"]*m["worldScale"],"height":layer["height"]*m["worldScale"],"depth":layer["depth"],
                "xfl":dynamic_xfl.relative_to(ROOT).as_posix(),"sourcePng":layer["png"]}
            if layer["role"]=="elevator-scroll":
                dynamic.update(loopHeight=layer["loopHeight"]*m["worldScale"],clip=[v*m["worldScale"] for v in layer["clip"]])
            row["layers"].append(dynamic)
        row["layers"].sort(key=lambda layer:layer["depth"])
        row["mechanism"]={"kind":"door" if any(x["role"].startswith("door-") for x in row["layers"]) else "exit",
                          "layers":[{k:v for k,v in x.items() if k not in ("xfl","sourcePng")} for x in row["layers"]]}
        extra=(mechanisms or {}).get('maps',{}).get(m['id'])
        if extra:
            row['sequenceBindings']=copy.deepcopy(extra['layers'])
            row['mechanism']['kind']=extra['kind']
            for layer in extra['layers']:
                if layer['role'] not in ('door-spawn-sequence','door-exit-sequence') or not 2<=layer['frames']<=120:
                    raise ValueError('invalid native door sequence: '+m['id'])
                if not layer['url'].startswith('flashswf/backgrounds/cf6/') or '..' in layer['url']:
                    raise ValueError('invalid native door URL: '+m['id'])
                item={k:v for k,v in layer.items() if k not in ('xfl','basis')}
                item['x'],item['y']=coordinates(m)([layer['x'],layer['y']])
                item['width']*=m['worldScale'];item['height']*=m['worldScale']
                if item['role']=='door-spawn-sequence':
                    item['spawnX'],item['spawnY']=coordinates(m)([layer['spawnX'],layer['spawnY']])
                    item['spawnRadius']*=m['worldScale']
                row['mechanism']['layers'].append(item)
            delivered={x['basis']['originalSprite'] for x in extra['layers']}
            row['pendingDynamics']=[x for x in row['pendingDynamics'] if not any(str(sprite) in x['id'] for sprite in delivered)]
        index["maps"].append(row)
    ET.indent(envs)
    outputs[HERE/"generated/environment.fragment.xml"] = ET.tostring(envs,encoding="utf-8",xml_declaration=True)+b"\n"
    outputs[HERE/"generated/runtime-index.json"] = (json.dumps(index,ensure_ascii=False,indent=2)+"\n").encode()
    return outputs


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--overrides",type=Path)
    parser.add_argument("--mechanisms",type=Path,default=HERE/'generated/door-mechanism-overrides.json')
    parser.add_argument("--check",action="store_true")
    parser.add_argument("--metadata-only",action="store_true",help="Update coordinate/runtime index and environment only; do not emit legacy bitmap recipes")
    args=parser.parse_args()
    overlays=json.loads(args.overrides.read_text(encoding="utf-8-sig")) if args.overrides else None
    data=validate(normalize(json.loads(args.input.read_text(encoding="utf-8-sig")),overlays))
    mechanisms=json.loads(args.mechanisms.read_text(encoding='utf-8')) if args.mechanisms.is_file() else None
    outputs=build(data,mechanisms)
    if args.metadata_only:outputs={path:content for path,content in outputs.items() if path.name in ('runtime-index.json','environment.fragment.xml')}
    stale=[]
    for path,content in outputs.items():
        if args.check:
            if not path.exists() or path.read_bytes()!=content: stale.append(path.relative_to(ROOT).as_posix())
        else:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
    index=json.loads(outputs[HERE/"generated/runtime-index.json"])
    if not args.check and not args.metadata_only:
        (ROOT/'tmp/cf6-map-runtime/native-import').mkdir(parents=True,exist_ok=True)
        for row in index["maps"]:
            (ROOT/row["xfl"]).parent.mkdir(parents=True,exist_ok=True)
            for layer in row["layers"]: (ROOT/layer["xfl"]).parent.mkdir(parents=True,exist_ok=True)
    expected={p.name for p in outputs if p.suffix==".jsfl"}
    extra=({p.name for p in (HERE/"generated").glob("CF6_*.jsfl")}-expected) if not args.metadata_only else set()
    if extra: stale.extend("unexpected recipe: "+p for p in sorted(extra))
    if stale: raise SystemExit("stale outputs: "+", ".join(stale))
    print(f"{'checked' if args.check else 'generated'} {len(outputs)} artifacts; native CS6 import/compile remains required")


if __name__ == "__main__": main()
