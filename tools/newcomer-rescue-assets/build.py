"""70002 native source ingestion and deterministic publish targets.

The five editable masters are the art authority. Generated publish projects in
tmp/ select one state; CS6 alone produces SWFs and bitmap caches.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "flashswf/backgrounds/70002"
OUT = ROOT / "tmp/newcomer-rescue/publish"
NS = "http://ns.adobe.com/xfl/2008/"
Q = "{" + NS + "}"
ET.register_namespace("", NS)
PACKS = {
    "A": ("CF7-70002-A-Clinic-R15-NativeSource-20261018.zip", "3ee70770f40b026f7037ed5a5adbd148a5296f7c14c66faff5587e4ffca4afed"),
    "B": ("70002-B-R8-editable-source-20261018.zip", "aeefba607525a2e3ff17f52307fd0a6dc19fe3d6a8e2afade661f1a6030997e9"),
    "C": ("C-70002-jeep-cabin-r8-native-review.zip", "ec5abba6b42015504feb086b4cf6f5d30cc35db9ff634108fd67c47c150a9fd6"),
    "D": ("iron-gun-return-raid-r9-disclosure-20261018-source.zip", "87acf292513e5b7bd8d1ffa720101bd2cf7a76b4da2fea02fb7da5878bd92978"),
}
MASTERS = {
    "clinic": ("A", ["Clinic70002-rescue-XFL", "Clinic70002-evacuated-XFL"], ["rescue", "evacuated"]),
    "staging": ("B", ["Staging70002-departure-XFL", "Staging70002-receiving-XFL"], ["departure", "receiving"]),
    "ambush": ("C", ["70002-Ambush-ArtReview-XFL"], ["investigate", "destructible", "detonating", "wreck"]),
    "return": ("D", ["70002-return-XFL"], ["return", "outbound"]),
    "raid": ("D", ["70002-raid-XFL"], ["raid"]),
}
TARGETS = [
    ("staging", 0, "gk6_1_BG_70002_departure", "background"),
    ("return", 1, "gk5_5_BG_70002_outbound", "background"),
    ("clinic", 0, "gk5_4_BG_70002_rescue", "background"),
    ("ambush", 0, "gk5_3_BG_70002", "ambush_background"),
    ("clinic", 1, "gk5_4_BG_70002_evacuated", "background"),
    ("return", 0, "gk5_5_BG_70002_return", "background"),
    ("staging", 1, "gk6_1_BG_70002_receiving", "background"),
    ("raid", 0, "gk6_2_BG_70002_raid", "background"),
    ("ambush", 0, "70002_jeep", "jeep"),
    ("ambush", 0, "70002_station", "station"),
]


def write_xml(path: Path, root: ET.Element) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def scripts(timeline: ET.Element, text: str) -> None:
    layer = ET.Element(Q + "DOMLayer", {"name": "70002 runtime entry"})
    frame = ET.SubElement(ET.SubElement(layer, Q + "frames"), Q + "DOMFrame", {"index": "0"})
    ET.SubElement(ET.SubElement(frame, Q + "Actionscript"), Q + "script").text = text
    ET.SubElement(frame, Q + "elements")
    timeline.find(Q + "layers").insert(0, layer)


def ingest(downloads: Path) -> None:
    if SOURCE.exists():
        raise SystemExit("Masters already exist; edit them in place. Refusing to overwrite art.")
    archives = {}
    for key, (name, digest) in PACKS.items():
        path = downloads / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit("Archive identity mismatch: " + name)
        archive = zipfile.ZipFile(path)
        if archive.testzip() is not None:
            raise SystemExit("Archive CRC failure: " + name)
        archives[key] = archive
    for master, (key, entries, states) in MASTERS.items():
        archive = archives[key]
        bases = [next(n.rsplit("/", 1)[0] for n in archive.namelist()
                      if n.endswith("/native/" + entry + "/DOMDocument.xml")) for entry in entries]
        folder = SOURCE / master
        folder.mkdir(parents=True)
        for name in archive.namelist():
            if not name.startswith(bases[0] + "/") or name.endswith("/"):
                continue
            relative = PurePosixPath(name[len(bases[0]) + 1:])
            if ".." in relative.parts or relative.is_absolute():
                raise SystemExit("Unsafe archive member")
            if str(relative) in ("DOMDocument.xml", "PublishSettings.xml") or relative.suffix == ".xfl" or relative.parts[0] in ("LIBRARY", "bin"):
                target = folder / Path(*relative.parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(name))
        markers = list(folder.glob("*.xfl"))
        if markers:
            markers[0].rename(folder / (master + ".xfl"))
        document = ET.fromstring(archive.read(bases[0] + "/DOMDocument.xml"))
        timelines = document.find(Q + "timelines")
        scenes = list(timelines)
        for base in bases[1:]:
            partner = ET.fromstring(archive.read(base + "/DOMDocument.xml"))
            scenes.extend(copy.deepcopy(list(partner.find(Q + "timelines"))))
        timelines.clear()
        for index, scene in enumerate(scenes):
            scene.set("name", states[index])
            scene.set("currentFrame", "0")
            timelines.append(scene)
        document.set("currentTimeline", "0")
        document.set("frameRate", "30")
        document.set("nextSceneIdentifier", str(len(scenes) + 1))
        for item in document.iter():
            for attribute in ("font", "face"):
                if item.get(attribute) == "Arial Baltic":
                    item.set(attribute, "Arial")
        write_xml(folder / "DOMDocument.xml", document)
    lock = {key: {"file": value[0], "sha256": value[1]} for key, value in PACKS.items()}
    (ROOT / "tools/newcomer-rescue-assets/archive-lock.json").write_text(json.dumps(lock, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Ingested five editable masters; frozen downloads preserved.")


def profile(folder: Path, output: Path) -> None:
    path = folder / "PublishSettings.xml"
    tree = ET.parse(path)
    for node in tree.getroot().iter():
        if node.tag == "flashFileName":
            node.text = str(output)
        elif node.tag in ("html", "gif", "jpeg", "png", "projectorWin", "projectorMac", "swc"):
            node.text = "0"
        elif node.tag in ("DefaultNames", "defaultNames"):
            node.text = "0"
        elif node.tag in ("Version", "ActionScriptVersion"):
            node.text = "2" if node.tag == "ActionScriptVersion" else "8"
    tree.write(path, encoding="utf-8", xml_declaration=True)


def build() -> None:
    for marker in ("compile_state_uncertain.marker", "testloader_scratch_inflight.marker"):
        if (ROOT / "scripts" / marker).exists():
            raise SystemExit("CS6 transaction/recovery is active: " + marker)
    manifest = []
    for master, scene_index, name, kind in TARGETS:
        source = SOURCE / master
        target = OUT / name
        target.mkdir(parents=True, exist_ok=True)
        # Prune only obsolete generated files inside this owned target. A
        # library rename must not leave a second, orphaned edit source in tmp/.
        for existing in (target / "LIBRARY").rglob("*"):
            if existing.is_file() and not (source / "LIBRARY" / existing.relative_to(target / "LIBRARY")).is_file():
                if not existing.resolve().is_relative_to(OUT.resolve()):
                    raise SystemExit("Generated file escaped publish directory")
                existing.unlink()
        shutil.copytree(source / "LIBRARY", target / "LIBRARY", dirs_exist_ok=True)
        if (source / "bin").is_dir():
            shutil.copytree(source / "bin", target / "bin", dirs_exist_ok=True)
        shutil.copy2(source / "PublishSettings.xml", target / "PublishSettings.xml")
        shutil.copy2(source / (master + ".xfl"), target / (name + ".xfl"))
        document = ET.parse(source / "DOMDocument.xml").getroot()
        timelines = document.find(Q + "timelines")
        scenes = list(timelines)
        timelines.clear()
        if kind in ("jeep", "station"):
            timeline = ET.SubElement(timelines, Q + "DOMTimeline", {"name": "Jeep70002"})
            layers = ET.SubElement(timeline, Q + "layers")
            converted = set()
            # Four review scenes become four stopped runtime states. The full
            # explosion clip remains a MovieClip inside the detonating state.
            for index, scene in enumerate(scenes):
                selected = [layer for layer in scene.find(Q + "layers")
                            if layer.get("name") != "原生底图"
                            and (layer.get("name") == "现场证据") == (kind == "station")]
                for layer_index, original in enumerate(selected):
                    while len(layers) <= layer_index:
                        ET.SubElement(ET.SubElement(layers, Q + "DOMLayer", {"name": "state art " + str(len(layers))}), Q + "frames")
                    frame = copy.deepcopy(original.find(Q + "frames/" + Q + "DOMFrame"))
                    frame.set("index", str(index))
                    frame.set("duration", "1")
                    frame.attrib.pop("name", None)
                    frame.attrib.pop("labelType", None)
                    if original.get("name") in ("吉普独立状态", "现场证据"):
                        for instance in frame.findall(".//" + Q + "DOMSymbolInstance"):
                            instance.set("name", "vehicleState" if kind == "jeep" else "stationState")
                            for attr in ("symbolType", "loop", "firstFrame"):
                                instance.attrib.pop(attr, None)
                            path = target / "LIBRARY" / (instance.get("libraryItemName") + ".xml")
                            if path not in converted:
                                symbol = ET.parse(path).getroot()
                                symbol.attrib.pop("symbolType", None)
                                scripts(symbol.find(Q + "timeline/" + Q + "DOMTimeline"), "stop();")
                                write_xml(path, symbol)
                                converted.add(path)
                    layers[layer_index].find(Q + "frames").append(frame)
            runtime = ET.Element(Q + "DOMLayer", {"name": "states"})
            frames = ET.SubElement(runtime, Q + "frames")
            for i, label in enumerate(MASTERS[master][2]):
                frame = ET.SubElement(frames, Q + "DOMFrame", {"index": str(i), "name": label, "labelType": "name"})
                ET.SubElement(ET.SubElement(frame, Q + "Actionscript"), Q + "script").text = "stop();"
                ET.SubElement(frame, Q + "elements")
            layers.insert(0, runtime)
            # Review graphics are preserved in the editable master. Production
            # uses the real one-shot pickup instead of a second painted rifle.
            station_parts = set()
            for rel in ["Jeep70002/StaticSceneEvidence.xml", "Jeep70002/StaticSceneEvidenceFalling.xml", "Jeep70002/StaticSceneEvidenceCollapsed.xml"]:
                item = target / "LIBRARY" / rel
                symbol = ET.parse(item).getroot()
                for symbol_layers in symbol.findall(".//" + Q + "layers"):
                    for layer in list(symbol_layers):
                        refs = [n.get("libraryItemName", "") for n in layer.findall(".//" + Q + "DOMSymbolInstance")]
                        if "枪-长枪-Type56R" in refs or "Jeep70002/RifleContactShadow" in refs:
                            symbol_layers.remove(layer)
                            continue
                        for inst in layer.findall(".//" + Q + "DOMSymbolInstance"):
                            for attr in ("symbolType", "loop", "firstFrame"):
                                inst.attrib.pop(attr, None)
                            part_path = target / "LIBRARY" / (inst.get("libraryItemName") + ".xml")
                            if part_path.is_file() and part_path not in station_parts:
                                part_sym = ET.parse(part_path).getroot()
                                part_sym.attrib.pop("symbolType", None)
                                scripts(part_sym.find(Q + "timeline/" + Q + "DOMTimeline"), "stop();")
                                write_xml(part_path, part_sym)
                                station_parts.add(part_path)
                write_xml(item, symbol)
            if kind == "jeep":
                fuse = target / "LIBRARY/Jeep70002/FuseSmoke.xml"
                symbol = ET.parse(fuse).getroot()
                symbol.attrib.pop("symbolType", None)
                scripts(symbol.find(Q + "timeline/" + Q + "DOMTimeline"), "stop();")
                write_xml(fuse, symbol)
                destructible = target / "LIBRARY/Jeep70002/Destructible.xml"
                symbol = ET.parse(destructible).getroot()
                for inst in symbol.findall(".//" + Q + "DOMSymbolInstance"):
                    if inst.get("libraryItemName") == "Jeep70002/FuseSmoke":
                        for attr in ("symbolType", "loop", "firstFrame"):
                            inst.attrib.pop(attr, None)
                        inst.set("name", "引信特效")
                write_xml(destructible, symbol)
                effect = target / "LIBRARY/特效与子弹/上帝之杖/巨大物理爆炸.xml"
                symbol = ET.parse(effect).getroot()
                symbol.attrib.pop("symbolType", None)
                for timeline_part in symbol.findall(".//" + Q + "DOMTimeline"):
                    final_layer = ET.SubElement(timeline_part.find(Q + "layers"), Q + "DOMLayer", {"name": "runtime stop"})
                    frames = ET.SubElement(final_layer, Q + "frames")
                    ET.SubElement(ET.SubElement(frames, Q + "DOMFrame", {"index": "0", "duration": "77"}), Q + "elements")
                    last = ET.SubElement(frames, Q + "DOMFrame", {"index": "77"})
                    ET.SubElement(ET.SubElement(last, Q + "Actionscript"), Q + "script").text = "stop();"
                    ET.SubElement(last, Q + "elements")
                write_xml(effect, symbol)
                path = target / "LIBRARY/Jeep70002/Detonating.xml"
                symbol = ET.parse(path).getroot()
                for inst in symbol.findall(".//" + Q + "DOMSymbolInstance"):
                    if inst.get("libraryItemName") == "特效与子弹/上帝之杖/巨大物理爆炸":
                        for attr in ("symbolType", "loop", "firstFrame"):
                            inst.attrib.pop(attr, None)
                        inst.set("name", "殉爆特效")
                write_xml(path, symbol)
        else:
            timeline = copy.deepcopy(scenes[scene_index])
            timelines.append(timeline)
            if kind == "ambush_background":
                layers = timeline.find(Q + "layers")
                for layer in list(layers):
                    if layer.get("name") != "原生底图":
                        layers.remove(layer)
                for matrix in timeline.findall(".//" + Q + "Matrix"):
                    matrix.set("tx", "0")
                    matrix.set("ty", "0")
                scripts(timeline, "_root.贴背景图();")
        document.set("currentTimeline", "0")
        # External URL props do not register globally named library exports.
        for path in (target / "LIBRARY").rglob("*.xml"):
            symbol = ET.parse(path).getroot()
            if symbol.get("linkageExportForAS") == "true":
                for key in ("linkageIdentifier", "linkageClassName", "linkageExportForAS", "linkageExportInFirstFrame"):
                    symbol.attrib.pop(key, None)
                write_xml(path, symbol)
        write_xml(target / "DOMDocument.xml", document)
        output = ROOT / ("flashswf/arts" if kind in ("jeep", "station") else "flashswf/backgrounds") / (name + ".swf")
        profile(target, output)
        manifest.append({"master": master, "state": name, "kind": kind,
                         "xfl": str((target / (name + ".xfl")).relative_to(ROOT)), "swf": str(output.relative_to(ROOT))})
    OUT.parent.mkdir(parents=True, exist_ok=True)
    (OUT.parent / "publish-targets.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    record = {"source_sha256": source_sha(), "files": {
        str(p.relative_to(OUT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(OUT.rglob("*")) if p.is_file() and p.suffix not in (".swf", ".fla")}}
    (OUT.parent / "assembly-manifest.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Prepared nine CS6 publish targets; no SWF was synthesized.")


def source_sha():
    digest = hashlib.sha256(Path(__file__).read_bytes())
    for path in sorted(SOURCE.rglob("*")):
        if path.is_file():
            digest.update(path.relative_to(SOURCE).as_posix().encode("utf-8") + b"\0" + hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def check():
    record = json.loads((OUT.parent / "assembly-manifest.json").read_text(encoding="utf-8"))
    if record["source_sha256"] != source_sha():
        raise SystemExit("Publish projects are stale; run build.py")
    for relative, expected in record["files"].items():
        path = OUT / relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit("Generated project changed: " + relative)
    print("Nine publish projects match their source closure and generated file hashes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ingest", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.ingest:
        ingest(args.ingest)
    check() if args.check else build()
