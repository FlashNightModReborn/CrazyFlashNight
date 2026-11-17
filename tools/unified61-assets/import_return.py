"""Stage a bound artwork return against live Type61 XFL; --apply replaces art only."""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import shutil
import sys
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OWNER = ROOT / "flashswf/arts/new/Codex专用素材"
PREFIX = "Codex/统合61式/"
NS = {"x": "http://ns.adobe.com/xfl/2008/", "s": "http://www.w3.org/2000/svg"}
PARSER = E.XMLParser(remove_blank_text=True, strip_cdata=False)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def refs(root):
    return list(dict.fromkeys(e.get("libraryItemName") for e in root.findall(".//x:DOMSymbolInstance", NS)))


def write(path, root):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(E.tostring(root, encoding="utf-8", pretty_print=True))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--return-dir", type=Path, required=True)
    ap.add_argument("--baseline-dir", type=Path, required=True)
    ap.add_argument("--work-dir", type=Path, required=True)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    incoming, baseline, work = (p.resolve() for p in (args.return_dir, args.baseline_dir, args.work_dir))
    if work.exists():
        raise ValueError("Use a fresh work directory; existing evidence is preserved")
    archive = OWNER.parent / "Codex素材源稿/统合61式/R01"
    if args.apply and archive.exists():
        raise ValueError("Return archive already exists")
    manifest = json.loads((incoming / "return-manifest.json").read_text("utf-8"))
    catalog = json.loads((baseline / "data/catalog.json").read_text("utf-8"))
    if manifest["sourceSnapshot"] != catalog["sourceSnapshot"]:
        raise ValueError("Return and baseline describe different native snapshots")
    native_root = OWNER / "LIBRARY" / PREFIX
    before = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(native_root.rglob("*.xml"))}
    snapshot = hashlib.sha256(json.dumps(before, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()
    if snapshot != manifest["sourceSnapshot"]:
        raise ValueError("Live XFL changed since this artwork was exported")
    parts = catalog["variants"]["unified"]["parts"]
    expected = {relative for part in parts.values() for relative in part["states"].values()}
    records = {row["path"]: row for row in manifest["files"]}
    actual = {p.relative_to(incoming).as_posix() for p in (incoming / "assets/unified").rglob("*") if p.is_file()}
    if expected != set(records) or actual != expected or len(expected) != 24:
        raise ValueError("Return must contain exactly the expected 24 work SVGs")
    for relative, row in records.items():
        if sha(incoming / relative) != row["sha256"]:
            raise ValueError("Returned SVG hash mismatch: " + relative)
    work.mkdir(parents=True)
    staging = work / "LIBRARY"
    shutil.copytree(native_root, staging / PREFIX)
    builder = load("type61_return_builder", HERE / "build.py")
    revise = load("type61_return_icons", HERE / "revise_native.py")
    writer = builder.writer_module()
    stats, retired_clips = {}, []
    for part_id, part in parts.items():
        for state, relative in part["states"].items():
            original_svg = E.parse(str(baseline / "baseline" / relative), PARSER)
            svg = E.parse(str(incoming / relative), PARSER)
            for key in ("viewBox", "width", "height"):
                if svg.getroot().get(key) != original_svg.getroot().get(key):
                    raise ValueError("Canvas changed: " + relative)
            # The handoff SVG contains the live outer correction. Keep that
            # exact native wrapper unchanged and import its unscaled interior.
            if "forearm" in part_id:
                old = original_svg.getroot().findall("s:g", NS)
                groups = svg.getroot().findall("s:g", NS)
                if len(old) != 1 or len(groups) != 1 or groups[0].get("transform") != old[0].get("transform"):
                    raise ValueError("Forearm baked matrix changed: " + relative)
                groups[0].attrib.pop("transform")
            path = work / "normalized" / relative
            write(path, svg.getroot())
            name = PREFIX + "原生/" + part["skinKey"] + "-" + state
            existing = E.parse(str(staging / (name + ".xml")), PARSER).getroot()
            generated = {}
            stats[relative] = builder.native_art(path, name, generated, writer)
            old_clips, new_clips = refs(existing), refs(generated[name])
            if old_clips and not new_clips and part_id in {"boots", "male_upper_arm", "female_upper_arm"}:
                # R01 removes the old boot debris and the shoulder aperture.
                # Preserve unused legacy helpers, never reference them again.
                retired_clips.extend(old_clips)
            elif len(old_clips) != len(new_clips):
                raise ValueError("Aperture topology needs explicit review: " + relative)
            rename = dict(zip(new_clips, old_clips))
            for generated_name, root in generated.items():
                target_name = rename.get(generated_name, generated_name)
                old_root = E.parse(str(staging / (target_name + ".xml")), PARSER).getroot()
                root.attrib.clear()
                root.attrib.update(old_root.attrib)
                root.find("x:timeline/x:DOMTimeline", NS).set("name", target_name.rsplit("/", 1)[-1])
                for layer in root.findall("x:timeline/x:DOMTimeline/x:layers/x:DOMLayer", NS):
                    if layer.get("name") == "R38 原生分件":
                        layer.set("name", "R01 原生分件")
                for element in root.findall(".//x:DOMSymbolInstance", NS):
                    element.set("libraryItemName", rename.get(element.get("libraryItemName"), element.get("libraryItemName")))
                write(staging / (target_name + ".xml"), root)
    # Existing icon helpers contain copies of the closed artwork. Refresh
    # those copies while leaving both frame masks, shadows and crop intact.
    revise.LIBRARY = staging
    sys.path.insert(0, str(ROOT / "tools/asset-metrology"))
    import xfl_geometry as geometry
    helpers = []
    for icon in catalog["icons"].values():
        raw = PREFIX + "原生/" + parts[icon["part"]]["skinKey"] + "-closed"
        art = builder.instance(raw, icon["matrix"], graphic=True)
        units = revise.icon_units(art, icon["label"], helpers, geometry)
        old_icon = E.parse(str(staging / (PREFIX + "图标-Codex-统合61式" + icon["label"] + ".xml")), PARSER).getroot()
        first = old_icon.findall('.//x:DOMFrame[@index="0"]//x:DOMSymbolInstance', NS)
        new = [element for _, element in reversed(units)]
        if icon["part"] == "boots" and len(new) == 1 and len(first) != 1:
            # The three clipped mud fragments are absent in R01. Both icon
            # frames now mask the complete new boot directly at the old crop.
            layers = old_icon.find("x:timeline/x:DOMTimeline/x:layers", NS)
            script = [layer for layer in layers if layer.find('.//x:Actionscript', NS) is not None]
            masks = [layer for layer in layers if layer.get("layerType") == "mask"]
            shadows = [layer for layer in layers if layer.get("name") == "钛合金同源底影"]
            if len(script) != 1 or len(masks) != 1 or len(shadows) != 1:
                raise ValueError("Unexpected boot icon layers")
            content = builder.layer("R01 靴甲静态图形", parentLayerIndex=1, locked="true")
            for index in (0, 1):
                builder.frame(content.find("x:frames", NS), [copy.deepcopy(art)], index)
            layers[:] = [copy.deepcopy(script[0]), copy.deepcopy(masks[0]), content, copy.deepcopy(shadows[0])]
            write(staging / (old_icon.get("name") + ".xml"), old_icon)
            first = old_icon.findall('.//x:DOMFrame[@index="0"]//x:DOMSymbolInstance', NS)
        if len(first) != len(new):
            raise ValueError("Icon layer topology changed: " + icon["label"])
        for old, current in zip(first, new):
            if old.get("libraryItemName") != current.get("libraryItemName"):
                raise ValueError("Icon source changed: " + icon["label"])
            old_matrix = geometry.matrix(old.find("x:matrix/x:Matrix", NS).attrib)
            new_matrix = geometry.matrix(current.find("x:matrix/x:Matrix", NS).attrib)
            if any(abs(a - b) > 1e-8 for a, b in zip(old_matrix, new_matrix)):
                raise ValueError("Icon crop matrix changed: " + icon["label"])
    staged_files = {p.relative_to(staging).as_posix(): p for p in (staging / PREFIX).rglob("*.xml")}
    live_files = {p.relative_to(OWNER / "LIBRARY").as_posix(): p for p in native_root.rglob("*.xml")}
    if set(staged_files) != set(live_files):
        raise ValueError("Native symbol set changed")
    changed = [relative for relative in staged_files if sha(staged_files[relative]) != sha(live_files[relative])]
    if any(relative[len(PREFIX):].split("/")[0] not in {"原生", "图标分层", "图标-Codex-统合61式装甲鞋.xml"} for relative in changed):
        raise ValueError("Only native art and static icon helpers may change")
    for path in staged_files.values():
        if set(refs(E.parse(str(path), PARSER).getroot())) & set(retired_clips):
            raise ValueError("Removed aperture still has an active consumer")
    report = {"sourceSnapshot": snapshot, "returnManifestSha256": sha(incoming / "return-manifest.json"), "nativeSymbols": len(live_files), "changedFiles": changed, "preservedSymbols": len(live_files) - len(changed), "retainedUnusedClipSymbols": retired_clips, "stats": stats, "mode": "staged", "compiled": False}
    if args.apply:
        if before != {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(native_root.rglob("*.xml"))}:
            raise ValueError("Live art changed while staging")
        backup = work / "before"
        shutil.copytree(native_root, backup / PREFIX)
        shutil.copyfile(OWNER.with_suffix(".swf"), work / "Codex专用素材-before.swf")
        applied = []
        try:
            for relative in changed:
                target = live_files[relative]
                target.write_bytes(staged_files[relative].read_bytes())
                applied.append(relative)
        except Exception:
            for relative in applied:
                if sha(live_files[relative]) == sha(staged_files[relative]):
                    shutil.copyfile(backup / relative, live_files[relative])
            raise
        report["mode"] = "applied"
        shutil.copytree(incoming / "assets", archive / "assets")
        shutil.copyfile(incoming / "return-manifest.json", archive / "return-manifest.json")
        shutil.copytree(incoming / "notes", archive / "notes")
    (work / "import-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "stats"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
