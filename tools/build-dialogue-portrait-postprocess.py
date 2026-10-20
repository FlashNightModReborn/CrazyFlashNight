"""Generate CS6-native portrait effects from the same profile as the Web baker.

Original art is read-only. BitmapData captures it once, then applies color/alpha,
alpha-preserving scanlines and a silhouette glow. No SWF is synthesized here.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
import xml.etree.ElementTree as E
from pathlib import Path

from dialogue_portrait_postprocess import recipes, color_matrix, POLICY

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/cf7-balance-tool/models/ti61"))
from jk_source import read_fla

Q = "{http://ns.adobe.com/xfl/2008/}"
E.register_namespace("", Q[1:-1])


def xml_bytes(root):
    return E.tostring(root, encoding="utf-8", xml_declaration=True)


def native_script(width, height, profile):
    matrix = ",".join(f"{value:.10g}" for value in color_matrix(profile))
    color = sum(c << (16 - i * 8) for i, c in enumerate(profile["glowColor"]))
    return f'''import flash.display.BitmapData;
import flash.geom.Matrix;
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.geom.ColorTransform;
import flash.filters.ColorMatrixFilter;
import flash.filters.GlowFilter;
stop();
var source:MovieClip=this.__radioSource;
var bitmap:BitmapData=new BitmapData({width},{height},true,0);
bitmap.draw(source,new Matrix());
bitmap.applyFilter(bitmap,bitmap.rectangle,new Point(),new ColorMatrixFilter([{matrix}]));
var scan:ColorTransform=new ColorTransform({profile['scanDarken']},{profile['scanDarken']},{profile['scanDarken']},1);
for(var scanY:Number=0;scanY<{height};scanY+={profile['scanPeriod']}){{
    bitmap.colorTransform(new Rectangle(0,scanY,{width},1),scan);
}}
source._visible=false;
var picture:MovieClip=this.createEmptyMovieClip("__radioPicture",this.getNextHighestDepth());
picture.attachBitmap(bitmap,0,"auto",true);
picture.filters=[new GlowFilter({color},{profile['glowOpacity']},{profile['glowRadius']*2},{profile['glowRadius']*2},1,2,false,false)];
picture.cacheAsBitmap=true;
this.__radioBitmap=bitmap;
this.onUnload=function():Void{{this.__radioBitmap.dispose();}};
'''


def build(key, check=False):
    recipe = recipes(ROOT)[key]
    portrait_root = ROOT / "flashswf/portraits"
    source = portrait_root / (recipe["source"] + ".fla")
    files, identity = read_fla(source)
    document = E.fromstring(files["DOMDocument.xml"])
    timeline = document.find(Q + "timelines/" + Q + "DOMTimeline")
    layers = timeline.find(Q + "layers")
    if any(int(f.get("index", "0")) + int(f.get("duration", "1")) > 1
           for f in layers.iter(Q + "DOMFrame")):
        raise ValueError("Native postprocess requires a single-frame source; explicit mapping needed for animation")
    expected = {name: data for name, data in files.items()
                if data and name.startswith(("LIBRARY/", "bin/"))}
    symbol = E.Element(Q + "DOMSymbolItem", {"name": "RadioPostprocessSource"})
    source_timeline = E.SubElement(E.SubElement(symbol, Q + "timeline"), Q + "DOMTimeline",
                                   {"name": "RadioPostprocessSource"})
    source_layers = E.SubElement(source_timeline, Q + "layers")
    for layer in layers:
        if layer.get("name") == "as" or layer.get("outline") == "true":
            continue
        source_layers.append(copy.deepcopy(layer))
    expected["LIBRARY/RadioPostprocessSource.xml"] = xml_bytes(symbol)
    E.SubElement(document.find(Q + "symbols"), Q + "Include", {"href": "RadioPostprocessSource.xml"})
    layers.clear()
    layer = E.SubElement(layers, Q + "DOMLayer", {"name": "radio postprocess"})
    frame = E.SubElement(E.SubElement(layer, Q + "frames"), Q + "DOMFrame", {"index": "0"})
    E.SubElement(E.SubElement(frame, Q + "Actionscript"), Q + "script").text = native_script(
        int(document.get("width", "1024")), int(document.get("height", "576")), recipe["settings"])
    elements = E.SubElement(frame, Q + "elements")
    E.SubElement(elements, Q + "DOMSymbolInstance", {"libraryItemName": "RadioPostprocessSource", "name": "__radioSource"})
    document.set("currentTimeline", "0")
    expected["DOMDocument.xml"] = xml_bytes(document)
    expected[key + ".xfl"] = b"PROXY-CS5"
    profile = E.fromstring(files["PublishSettings.xml"])
    for field in profile.iter():
        if field.tag == "flashFileName":
            field.text = str(portrait_root / (key + ".swf"))
        elif field.tag in ("html", "DefaultNames", "defaultNames"):
            field.text = "0"
    expected["PublishSettings.xml"] = xml_bytes(profile)
    expected["postprocess-source.json"] = (json.dumps({
        "source": source.relative_to(ROOT).as_posix(), "sourceSha256": identity["sha256"],
        "recipe": recipe, "policySha256": hashlib.sha256((ROOT / POLICY).read_bytes()).hexdigest(),
        "generatorSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    }, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    output = portrait_root / key
    for name, content in expected.items():
        path = output / name
        if check:
            if not path.is_file() or path.read_bytes() != content:
                raise SystemExit("Native portrait postprocess is stale: " + name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    print(("Verified" if check else "Generated") + " native portrait postprocess: " + key)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--key", required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build(args.key, args.check)
