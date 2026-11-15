#!/usr/bin/env python3
"""Build a detached, reviewable Type61 art handoff without changing game assets."""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import importlib.util
import json
import math
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone, timedelta
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TEMPLATES = HERE / "handoff"
NS = {"x": "http://ns.adobe.com/xfl/2008/"}
SVG = "http://www.w3.org/2000/svg"
IDENTITY = (1, 0, 0, 1, 0, 0)
SLOTS = {"head": "头部装甲", "chest": "胸甲", "legs": "腿甲", "hands": "手甲", "boots": "装甲鞋"}
FIELDS = {"面具": "head", "身体": "torso", "上臂": "upper_arm", "左下臂": "forearm_left",
          "右下臂": "forearm_right", "屁股": "pelvis", "左大腿": "thigh_left",
          "右大腿": "thigh_right", "小腿": "calf", "左手": "glove_left", "右手": "glove_right", "脚": "boots"}
SHARED = {"head", "glove_left", "glove_right", "boots"}
POSE_IDS = {"空手站立": "idle", "长枪站立": "rifle", "手枪站立": "pistol",
            "手枪2站立": "pistol2", "双枪站立": "dual_pistols", "兵器站立": "melee", "手雷站立": "grenade"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def json_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def build(destination, make_png=True):
    destination = destination.resolve()
    if destination == ROOT or destination.is_relative_to(ROOT / "flashswf"):
        raise ValueError("Use a dedicated handoff output directory")
    marker = destination / ".type61-handoff"
    if destination.exists() and any(destination.iterdir()) and not marker.exists():
        raise ValueError("Destination already contains other work")
    destination.mkdir(parents=True, exist_ok=True)
    marker.write_text("type61-ai-kit-v1\n", encoding="utf-8")
    x = load_module("type61_xflsvg", ROOT / "tools/xfl-ui-svg/xfl_to_svg.py")
    # Include Bezier controls in the conservative crop bound. This does not
    # change paths, matrices or the XFL-to-SVG renderer.
    class Renderer(x.Renderer):
        def shape_to_svg(self, shape, transform, where, ct=x.CT_IDENTITY):
            # Flash stores a planar fill graph as unordered edges. Connect
            # directed boundaries before handing them to an SVG path: closing
            # every isolated Edge would introduce triangular fill fragments.
            clone = copy.deepcopy(shape)
            output_edges = clone.find("./x:edges", NS)
            if output_edges is None:
                return super().shape_to_svg(shape, transform, where, ct)
            original_edges = list(shape.findall("./x:edges/x:Edge", NS))
            buckets = {}
            for edge in original_edges:
                segments = x.edge_segments(edge.get("edges", ""))
                f1, f0 = edge.get("fillStyle1", "0"), edge.get("fillStyle0", "0")
                if f1 == f0:
                    continue
                if f1 != "0":
                    buckets.setdefault(f1, []).extend(segments)
                if f0 != "0":
                    buckets.setdefault(f0, []).extend(x.reverse_segments(segments))
            output_edges.clear()

            def coord(value):
                return ("%.9f" % (value * 20)).rstrip("0").rstrip(".") or "0"

            for fill, segments in buckets.items():
                remaining = collections.Counter(segments)
                for segment in list(remaining):
                    reverse = tuple(reversed(segment))
                    if reverse == segment:
                        remaining[segment] = 0
                    elif remaining[segment] and remaining[reverse]:
                        cancelled = min(remaining[segment], remaining[reverse])
                        remaining[segment] -= cancelled
                        remaining[reverse] -= cancelled
                graph = collections.defaultdict(list)
                pending = []
                for segment, count in remaining.items():
                    for _ in range(count):
                        graph[segment[0]].append(len(pending))
                        pending.append(segment)
                used = set()
                for index, first in enumerate(pending):
                    if index in used:
                        continue
                    used.add(index)
                    chain = [first]
                    while chain[-1][-1] != first[0]:
                        choices = graph.get(chain[-1][-1], [])
                        while choices and choices[-1] in used:
                            choices.pop()
                        if not choices:
                            break
                        next_index = choices.pop()
                        used.add(next_index)
                        chain.append(pending[next_index])
                    commands = ["!" + " ".join(map(coord, chain[0][0]))]
                    for segment in chain:
                        commands.append(("[" if len(segment) == 3 else "|") +
                                        " ".join(coord(v) for p in segment[1:] for v in p))
                    ET.SubElement(output_edges, "{" + NS["x"] + "}Edge",
                                  {"fillStyle1": fill, "edges": "".join(commands)})
            # Strokes keep their own graph and do not implicitly close.
            for edge in original_edges:
                if edge.get("strokeStyle", "0") != "0":
                    stroke = copy.deepcopy(edge)
                    stroke.set("fillStyle0", "0")
                    stroke.set("fillStyle1", "0")
                    output_edges.append(stroke)
            return super().shape_to_svg(clone, transform, where, ct)

        def _bbox_elements(self, elements, transform, stack, points):
            for element in elements:
                kind = element.tag.rsplit("}", 1)[-1]
                own = element.find("./x:matrix/x:Matrix", NS)
                combined = x.multiply(transform, x.parse_matrix(own)) if own is not None else transform
                if kind == "DOMGroup":
                    members = element.find("./x:members", NS)
                    if members is not None:
                        self._bbox_elements(members, combined, stack, points)
                elif kind == "DOMSymbolInstance":
                    name = element.get("libraryItemName")
                    if name:
                        bounds = self.symbol_bbox(name, int(element.get("firstFrame", 0)), combined, stack)
                        if bounds:
                            points.extend([(bounds[0], bounds[1]), (bounds[2], bounds[3])])
                elif kind == "DOMShape":
                    for edge in element.findall("./x:edges/x:Edge", NS):
                        for segment in x.edge_segments(edge.get("edges", "")):
                            points.extend(x.transform_point(combined, p) for p in segment)

    source_hashes = {}
    reports = []
    bounds_by_part = {}

    def source(path):
        path = path.resolve()
        if not path.is_relative_to(ROOT):
            raise ValueError("Source outside project")
        relative = path.relative_to(ROOT).as_posix()
        value = sha(path)
        if relative in source_hashes and source_hashes[relative] != value:
            raise ValueError("Source changed during export: " + relative)
        source_hashes[relative] = value
        return path

    def export_svg(library, symbol, frame, target, fixed_box=None):
        renderer = Renderer(library, [])
        body = renderer.render_symbol(symbol, frame, symbol)
        if renderer.unsupported or renderer.fields:
            raise ValueError("Incomplete export: " + symbol + " " + str(renderer.unsupported))
        bounds = renderer.symbol_bbox(symbol, frame)
        if not bounds:
            raise ValueError("Empty symbol: " + symbol)
        if fixed_box:
            box = fixed_box
        else:
            # Padding covers local stroke expansion and keeps (0, 0) visible.
            left = math.floor(min(bounds[0] - 6, -3))
            top = math.floor(min(bounds[1] - 6, -3))
            right = math.ceil(max(bounds[2] + 6, 3))
            bottom = math.ceil(max(bounds[3] + 6, 3))
            box = [left, top, right - left, bottom - top]
        def f(number):
            return ("%.9f" % number).rstrip("0").rstrip(".") or "0"
        metadata = json.dumps({"sourceSymbol": symbol, "sourceFrame": frame + 1,
                               "registration": [0, 0], "scope": "Native XFL static vector export"}, ensure_ascii=False)
        text = ('<svg xmlns="' + SVG + '" viewBox="' + " ".join(map(f, box)) +
                '" width="' + f(box[2]) + '" height="' + f(box[3]) + '">\n' +
                "<title>" + symbol.rsplit("/", 1)[-1] + "</title>\n" +
                "<metadata>" + metadata.replace("&", "&amp;").replace("<", "&lt;") + "</metadata>\n" +
                "<defs>" + "".join(renderer.defs) + "</defs>\n" + body + "\n</svg>\n")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        for path in renderer.sources:
            source(path)
        record = {"path": target.relative_to(destination).as_posix(), "sourceSymbol": symbol,
                  "sourceFrame": frame + 1, "viewBox": box, "conservativeArtBounds": bounds,
                  "sources": sorted(path.relative_to(ROOT).as_posix() for path in renderer.sources),
                  "unsupported": renderer.unsupported, "warnings": sorted(renderer.warnings),
                  "skipped": renderer.skipped}
        reports.append(record)
        return record

    manifest_path = source(ROOT / "launcher/web/assets/dressup/manifest.json")
    manifest = json.loads(manifest_path.read_text("utf-8"))
    archive_manifest = json.loads(source(HERE / "source/source-manifest.json").read_text("utf-8"))
    for row in archive_manifest["files"]:
        path = source(HERE / "source" / row["path"])
        if sha(path) != row["sha256"]:
            raise ValueError("Archived R38 input drift: " + row["path"])
    catalog = {"schema": 1, "variants": {}, "reviewCanvas": None, "icons": {},
               "coordinateSystem": "Flash symbol-local pixels, registration (0,0), y down. All part matrices already baked from live XFL."}
    from PIL import Image
    for variant, prefix, label in (("unified", "统合", "统合61"), ("regular", "", "普通61"), ("titanium", "钛合金", "钛合金61")):
        spec = {"label": label, "editable": variant == "unified", "parts": {}, "fieldsByGender": {}}
        skin_to_id = {}
        for gender, cn in (("male", "男"), ("female", "女")):
            fields = {}
            for part_name in SLOTS.values():
                fields.update(manifest["items"][prefix + "61式" + part_name]["fieldsByGender"][cn])
            mapped = {}
            for field, skin in fields.items():
                short = FIELDS[field]
                part_id = short if short in SHARED else gender + "_" + short
                if skin in skin_to_id and skin_to_id[skin] != part_id:
                    raise ValueError("Unexpected shared skin mapping")
                skin_to_id[skin] = part_id
                mapped[field] = part_id
            spec["fieldsByGender"][gender] = mapped
        for skin, part_id in sorted(skin_to_id.items(), key=lambda pair: pair[1]):
            row = manifest["skinKeys"][skin]
            asset = row["asset"]
            library = ROOT / Path(asset["swf"]).with_suffix("") / "LIBRARY"
            states = ("closed", "open", "fire") if variant == "unified" and part_id.endswith("_torso") else ("closed",)
            part = {"label": skin.replace("变装-Codex-统合61式", "·统合61·").replace("变装-", "·"),
                    "skinKey": skin, "sourceSymbol": asset["symbolName"], "registration": [0, 0],
                    "states": {}, "sharedAcrossGenders": part_id in SHARED}
            for index, state in enumerate(states):
                relative = (("assets/unified/" + state + "/" + part_id +
                             ("" if state == "closed" else "_" + state) + ".svg")
                            if variant == "unified" else "references/" + variant + "/svg/" + part_id + ".svg")
                record = export_svg(library, asset["symbolName"], index, destination / relative)
                part["states"][state] = relative
                bounds_by_part[(variant, part_id, state)] = record["conservativeArtBounds"]
                if variant == "unified":
                    baseline = destination / "baseline" / relative
                    baseline.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(destination / relative, baseline)
            frame = row["frames"][0]
            image_path = source(ROOT / "launcher/web/assets/dressup" / frame["uri"])
            relative = "references/native-png/" + variant + "/" + part_id + ".png"
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(image_path, target)
            part["raster"] = {"path": relative, "originX": frame["originX"], "originY": frame["originY"],
                              "width": frame["width"], "height": frame["height"], "zoom": row["export"]["zoom"],
                              "boundary": "Existing Web-exported closed frame; not a fresh Flash capture"}
            spec["parts"][part_id] = part
        if len(spec["parts"]) != 20:
            raise ValueError("Expected 20 gender-union parts")
        catalog["variants"][variant] = spec

    # Extract the current battle rig. Keep exact holder order and six values.
    poses = {"schema": 1, "boundary": "Static authored/held keys only; no tween interpolation or gameplay execution",
             "genders": {"male": [], "female": []}}
    for gender, cn in (("male", "男"), ("female", "女")):
        for label, row in manifest["rigs"]["battle"]["genders"][cn]["states"].items():
            holders = [{"field": holder["field"].removesuffix("_装扮"),
                        "matrix": [holder["matrix"][k] for k in ("a", "b", "c", "d", "tx", "ty")],
                        "sourcePath": holder.get("path", [])}
                       for holder in row["holders"] if holder["field"].removesuffix("_装扮") in FIELDS]
            if len(holders) != 15:
                raise ValueError("Unexpected battle rig placement count")
            poses["genders"][gender].append({"id": POSE_IDS[label], "label": label, "group": "current_battle",
                                            "source": "Supplied current Dressup manifest", "frame": row["frame"], "holders": holders})
    # Additional exact weapon keys are resolved from current XFL, rather than
    # carrying stale layer elements across action branches.
    review = load_module("type61_handoff_posekeys", HERE / "review_poses.py")
    original_baker_loader = review.load_baker

    def focused_baker():
        baker = original_baker_loader()

        class LazySymbols(dict):
            def __init__(self, library):
                super().__init__()
                self.library = Path(library).resolve()

            def get(self, name, default=None):
                if name not in self:
                    path = (self.library / (name + ".xml")).resolve()
                    if not path.is_relative_to(self.library):
                        raise ValueError("Pose symbol path leaves its library")
                    if not path.is_file():
                        return default
                    self[name] = baker.parse_symbol_file(source(path))
                return dict.get(self, name, default)

            def __getitem__(self, name):
                value = self.get(name)
                if value is None:
                    raise KeyError(name)
                return value

        baker.load_xfl_symbols = LazySymbols
        return baker

    review.load_baker = focused_baker
    extra = review.pose_keys()
    for path in (ROOT / "flashswf/arts/things0/LIBRARY/主角-男.xml",
                 ROOT / "flashswf/arts/things0/LIBRARY/sprite/兵器待机.xml",
                 ROOT / "tools/bake-dressup-offline.py", HERE / "review_poses.py"):
        source(path)
    for gender in ("male", "female"):
        for index, row in enumerate(extra):
            holders = [{"field": h["field"].removesuffix("_装扮"),
                        "matrix": [h["matrix"][k] for k in ("a", "b", "c", "d", "tx", "ty")]}
                       for h in row["holders"] if h["field"].removesuffix("_装扮") in FIELDS]
            if len(holders) != 15:
                raise ValueError("Unexpected weapon key placement count")
            poses["genders"][gender].append({"id": "weapon_key_" + str(index + 1), "label": row["label"],
                                            "group": "weapon_keys", "source": "Current things0 authored weapon key; shared geometry with gender-specific armor",
                                            "frame": row["frame"], "holders": holders})
    authored = json.loads(source(HERE / "source/assembly.json").read_text("utf-8"))
    for index, row in enumerate(authored["poses"]):
        gender = "male" if row["recommendedSkinGender"] == "男" else "female"
        holders = [{"field": h["field"].removesuffix("_装扮"),
                    "matrix": [h["matrix"][k] for k in ("a", "b", "c", "d", "tx", "ty")]}
                   for h in row["holders"] if h["field"].removesuffix("_装扮") in FIELDS]
        poses["genders"][gender].append({"id": "authored_" + str(index + 1), "label": row["label"],
                                        "group": "archived_authored", "sourceCommit": authored["sourceCommit"],
                                        "source": "Preserved R38 author matrix reference; not a current walk/attack rig", "holders": holders})

    # Fixed review canvas across all supplied states, all three sets and both
    # directions. Never independently auto-fit before/after revisions.
    xs, ys = [0], [0]
    for gender, rows in poses["genders"].items():
        for pose in rows:
            for variant, spec in catalog["variants"].items():
                for holder in pose["holders"]:
                    part_id = spec["fieldsByGender"][gender][holder["field"]]
                    states = spec["parts"][part_id]["states"]
                    for state in states:
                        b = bounds_by_part[(variant, part_id, state)]
                        for u, v in ((b[0], b[1]), (b[0], b[3]), (b[2], b[1]), (b[2], b[3])):
                            px, py = x.transform_point(holder["matrix"], (u, v))
                            xs.extend([px, -px]); ys.append(py)
    left, right = math.floor(min(xs) - 8), math.ceil(max(xs) + 8)
    top, bottom = math.floor(min(ys) - 8), math.ceil(max(ys) + 8)
    catalog["reviewCanvas"] = [left, top, right - left, bottom - top]

    owner_library = ROOT / "flashswf/arts/new/Codex专用素材/LIBRARY"
    owner_prefix = "Codex/统合61式/"
    icon_parts = {"head": "head", "chest": "male_torso", "legs": "male_pelvis", "hands": "glove_right", "boots": "boots"}
    head = ET.parse(source(owner_library / (owner_prefix + "图标-Codex-统合61式头部装甲.xml"))).getroot()
    layers = head.findall("./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer", NS)
    crop = next(layer for layer in layers if layer.get("layerType") == "mask").find(".//x:DOMShape", NS)
    shadow = next(layer for layer in layers if layer.get("name") == "钛合金同源底影").find(".//x:DOMShape", NS)
    for filename, shape in (("icon-crop.svg", crop), ("icon-shadow.svg", shadow)):
        rr = Renderer(owner_library, [])
        body = rr.shape_to_svg(shape, "", filename)
        text = '<svg xmlns="' + SVG + '" viewBox="-12 -12 24 24" width="24" height="24"><defs>' + "".join(rr.defs) + "</defs>" + body + "</svg>\n"
        if filename == "icon-crop.svg":
            # A browser clipPath accepts paths directly, not arbitrary nested
            # groups. Cairo happens to accept those groups, so flatten this
            # native single-shape crop explicitly for both renderers.
            parsed = ET.fromstring(text)
            flattened = ET.Element("{" + SVG + "}svg", {"viewBox": "-12 -12 24 24", "width": "24", "height": "24"})
            for path in parsed.findall(".//{" + SVG + "}path"):
                ET.SubElement(flattened, "{" + SVG + "}path",
                              {"d": path.get("d"), "fill": "#ffffff", "fill-rule": "nonzero"})
            ET.register_namespace("", SVG)
            text = ET.tostring(flattened, encoding="unicode") + "\n"
        target = destination / "data" / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
    icon_manifest_path = source(ROOT / "launcher/web/icons/manifest.json")
    icon_manifest = json.loads(icon_manifest_path.read_text("utf-8"))
    for slot, cn in SLOTS.items():
        symbol = owner_prefix + "图标-Codex-统合61式" + cn
        root = ET.parse(source(owner_library / (symbol + ".xml"))).getroot()
        matrices = [x.parse_matrix(a.find("./x:matrix/x:Matrix", NS)) for a in root.findall(".//x:DOMSymbolInstance", NS)]
        if not matrices or any(any(abs(a - b) > 1e-9 for a, b in zip(matrices[0], m)) for m in matrices):
            raise ValueError("Icon needs a richer composition recipe: " + slot)
        catalog["icons"][slot] = {"label": cn, "part": icon_parts[slot], "matrix": matrices[0],
                                  "frames": {"1": "Same closed art and crop, with native radial shadow",
                                             "2": "Same closed art and crop, without radial shadow"},
                                  "canvas": [-12, -12, 24, 24]}
        for variant, keyprefix in (("unified", "Codex-统合"), ("regular", ""), ("titanium", "钛合金")):
            key = keyprefix + "61式" + cn
            for frame in (1, 2):
                relative = icon_manifest[key].get("f" + str(frame))
                if not relative:
                    continue
                origin = source(ROOT / "launcher/web/icons" / relative)
                target = destination / "references/native-icons" / variant / (slot + "_f" + str(frame) + ".png")
                target.parent.mkdir(parents=True, exist_ok=True)
                Image.open(origin).convert("RGBA").save(target)
        for frame in (0, 1):
            export_svg(owner_library, symbol, frame, destination / "references/native-icons/unified" / (slot + "_f" + str(frame + 1) + ".svg"), [-12, -12, 24, 24])

    # Focused native source snapshot supports the Windows return integration.
    snapshot_root = owner_library / "Codex/统合61式"
    for path in sorted(snapshot_root.rglob("*.xml")):
        source(path)
        target = destination / "source_snapshot/unified-native" / path.relative_to(snapshot_root)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    # Preserve semantic author groups as a read-only historical reference.
    for row in archive_manifest["files"]:
        target = destination / "references/r38-archive" / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(HERE / "source" / row["path"], target)
    json_write(destination / "references/r38-archive/source-manifest.json", archive_manifest)
    json_write(destination / "references/r38-archive/assembly.json", authored)
    patches = []
    for gender, cn in (("male", "男"), ("female", "女")):
        for side, en in (("左", "left"), ("右", "right")):
            name = owner_prefix + cn + "变装-Codex-统合61式胸甲" + side + "下臂"
            root = ET.parse(source(owner_library / (name + ".xml"))).getroot()
            patches.append({"part": gender + "_forearm_" + en, "matrixBakedIntoWorkSvg": x.parse_matrix(root.find(".//x:DOMSymbolInstance/x:matrix/x:Matrix", NS)),
                            "purpose": "Preserve reviewed elbow/wrist coverage without moving the registration or changing transverse width"})

    constraints = {
        "schema": 1, "editableSet": "unified", "uniquePartsPerGender": 12, "placementsPerPose": 15,
        "uniquePartsGenderUnion": 20, "workSvgFiles": 24, "registration": [0, 0],
        "sharedAcrossGenders": sorted(SHARED),
        "reusedTwicePerPose": ["upper_arm", "calf", "boots"],
        "reuseOrientation": "The six standing battle states reuse these original-direction parts without mirroring. Do not bake left-only/right-only structures or strong world-space light into them.",
        "torsoStateFrames": {"closed": 1, "open": 2, "fire": 3},
        "cannonPort": {"instance": "炮口位置", "matrix": [1, -0.6, 0.25, 0.95, 47, -19],
                       "originInTorso": [47, -19], "forwardLocalVector": [1, -0.6]},
        "forearmCorrections": patches,
        "icon": {"crop": [-12, -12, 24, 24], "frame1": "Closed detail crop plus radial shadow",
                 "frame2": "Same art/matrix/crop, shadow omitted"},
        "reviewPixelHeights": [96, 128, 160, 240, 320], "gamePixelHeightVerified": False,
        "motionBoundary": "Static held/authored key comparison; does not validate continuous motion, timing or gameplay.",
        "sourceAuthority": "The live native XFL remains authoritative. Work SVGs are a detached edit candidate.",
    }
    json_write(destination / "data/constraints.json", constraints)
    json_write(destination / "data/export-report.json", reports)
    palette = collections.Counter()
    for part in catalog["variants"]["unified"]["parts"].values():
        for element in ET.parse(destination / part["states"]["closed"]).iter():
            for attr in ("fill", "stroke", "stop-color"):
                value = element.get(attr, "")
                if value.startswith("#"):
                    palette[value] += 1
    json_write(destination / "data/palette-reference.json",
               {"scope": "Frequent colors in current unified vectors; not an exclusive color whitelist",
                "colors": [{"color": c, "occurrences": n} for c, n in palette.most_common(24)]})
    tool_files = [Path(__file__), ROOT / "tools/xfl-ui-svg/xfl_to_svg.py"]
    for path in tool_files:
        source(path)
    for path in sorted(TEMPLATES.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            source(path)
            relative = path.relative_to(TEMPLATES)
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    git_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    snapshot_hashes = {k: v for k, v in sorted(source_hashes.items()) if k.startswith("flashswf/arts/new/Codex专用素材/LIBRARY/Codex/统合61式/")}
    snapshot_id = hashlib.sha256(json.dumps(snapshot_hashes, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()
    catalog["sourceSnapshot"] = snapshot_id
    json_write(destination / "data/catalog.json", catalog)
    json_write(destination / "data/poses.json", poses)
    source_report = {"schema": 1, "createdAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
                     "gitHead": git_head, "nativeSnapshotId": snapshot_id, "nativeSymbols": len(snapshot_hashes),
                     "archiveSvgHashesVerified": len(archive_manifest["files"]),
                     "pixelReferenceScope": "Existing Web export artifacts copied as-is, not a new SWF/Flash capture",
                     "sourceFiles": dict(sorted(source_hashes.items())),
                     "unchangedSourceCheck": "Pending end-of-build comparison"}
    portable = load_module("type61_portable_preview", destination / "preview.py")
    portable.verify_candidate(catalog)
    portable.write_viewer(catalog, poses)
    # Rebuildable illustrations shipped for chat environments without execution.
    examples = destination / "examples"
    examples.mkdir(exist_ok=True)
    views = []
    for gender in ("male", "female"):
        pose = next(p for p in poses["genders"][gender] if p["id"] == "idle")
        for variant in ("regular", "titanium", "unified"):
            text = portable.compose(catalog, pose, variant, gender, height=360, background="#283743")
            target = examples / ("family_" + gender + "_" + variant + ".svg")
            target.write_text(text, encoding="utf-8")
            if make_png:
                portable.png(text, target.with_suffix(".png"))
            views.append((gender, variant, target))
    for gender, rows in poses["genders"].items():
        for pose in rows:
            if pose["group"] not in ("current_battle", "weapon_keys"):
                continue
            text = portable.compose(catalog, pose, "unified", gender, height=320, background="#283743")
            target = examples / "poses" / (gender + "_" + pose["id"] + ".svg")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8")
            if make_png:
                portable.png(text, target.with_suffix(".png"))
        idle = next(p for p in rows if p["id"] == "idle")
        for state in ("open", "fire"):
            text = portable.compose(catalog, idle, "unified", gender, state, height=320, background="#283743")
            target = examples / ("torso_" + gender + "_" + state + ".svg")
            target.write_text(text, encoding="utf-8")
            if make_png:
                portable.png(text, target.with_suffix(".png"))
    if make_png:
        make_boards(destination, catalog, poses, portable)
    for relative, expected in source_hashes.items():
        if sha(ROOT / relative) != expected:
            raise ValueError("Source changed during handoff build: " + relative)
    source_report["unchangedSourceCheck"] = "All recorded source bytes matched at the end of the build"
    json_write(destination / "data/source-provenance.json", source_report)
    files = {}
    for path in sorted(destination.rglob("*")):
        if path.is_file() and path.name != "MANIFEST.json" and "__pycache__" not in path.parts:
            files[path.relative_to(destination).as_posix()] = {"sha256": sha(path), "bytes": path.stat().st_size}
    json_write(destination / "MANIFEST.json", {"schema": 1, "sourceSnapshot": snapshot_id, "files": files})
    archive = destination.with_suffix(".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in sorted(destination.rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts:
                z.write(path, destination.name + "/" + path.relative_to(destination).as_posix())
    with zipfile.ZipFile(archive) as z:
        bad = z.testzip()
        if bad:
            raise ValueError("Archive CRC failed: " + bad)
    print(json.dumps({"directory": str(destination), "archive": str(archive),
                      "archiveBytes": archive.stat().st_size, "files": len(files) + 1,
                      "nativeSymbols": len(snapshot_hashes), "workSvgFiles": 24,
                      "poses": {g: len(rows) for g, rows in poses["genders"].items()},
                      "snapshot": snapshot_id}, ensure_ascii=False, indent=2))
    return archive


def make_boards(destination, catalog, poses, portable):
    """Review-only contact sheets. Artwork is rendered, never repainted."""
    from PIL import Image, ImageDraw, ImageFont
    import io
    font = ImageFont.load_default(size=18)
    small = ImageFont.load_default(size=14)
    variants = ("regular", "titanium", "unified")
    size = Image.open(destination / "examples/family_male_unified.png").size
    cw, ch = size[0] + 24, size[1] + 56
    board = Image.new("RGB", (cw * 3, ch * 2 + 54), "#17212b")
    draw = ImageDraw.Draw(board)
    draw.text((16, 12), "TYPE 61 / Same pose and scale / Offline static assembly", font=font, fill="#e5edf2")
    for row, gender in enumerate(("male", "female")):
        for col, variant in enumerate(variants):
            image = Image.open(destination / ("examples/family_" + gender + "_" + variant + ".png")).convert("RGBA")
            px, py = col * cw + 12, row * ch + 82
            board.paste(image, (px, py), image)
            draw.text((px, py - 26), variant.upper() + " / " + gender, font=font, fill="#e2eaf0")
    board.save(destination / "examples/family-comparison.png")
    # Pixel samples use identical viewBox and remain at actual generated size.
    board = Image.new("RGB", (1000, 490), "#17212b")
    draw = ImageDraw.Draw(board)
    draw.text((18, 12), "UNIFIED / Review canvas pixels / NOT certified in-game size", font=font, fill="#e5edf2")
    pose = next(p for p in poses["genders"]["male"] if p["id"] == "idle")
    x = 18
    for height in (96, 128, 160, 240):
        text = portable.compose(catalog, pose, height=height, background="#786d55")
        import cairosvg
        pixels = cairosvg.svg2png(bytestring=text.encode("utf-8"))
        image = Image.open(io.BytesIO(pixels)).convert("RGBA")
        draw.text((x, 48), str(height) + " px canvas", font=small, fill="#b9cbd6")
        board.paste(image, (x, 80), image)
        enlarged = image.resize((image.width * 2, image.height * 2), Image.Resampling.NEAREST)
        if height == 96:
            board.paste(enlarged, (18, 220), enlarged)
            draw.text((18, 420), "96 px / 2x nearest", font=small, fill="#b9cbd6")
        x += image.width + 24
    board.save(destination / "examples/small-size-review.png")
    rows = []
    for slot in catalog["icons"]:
        for frame in (1, 2):
            text = portable.compose_icon(catalog, slot, frame)
            target = destination / "examples" / ("icon_" + slot + "_f" + str(frame) + ".svg")
            target.write_text(text, encoding="utf-8")
            portable.png(text, target.with_suffix(".png"))
            rows.append((slot, frame, target.with_suffix(".png")))
    board = Image.new("RGB", (800, 290), "#17212b")
    draw = ImageDraw.Draw(board)
    draw.text((16, 10), "24 px icons / 4x nearest / f1 inventory, f2 drop", font=font, fill="#e5edf2")
    for index, slot in enumerate(catalog["icons"]):
        draw.text((index * 158 + 12, 44), slot, font=small, fill="#c4d4dd")
        for frame in (1, 2):
            image = Image.open(destination / "examples" / ("icon_" + slot + "_f" + str(frame) + ".png")).convert("RGBA")
            image = image.resize((96, 96), Image.Resampling.NEAREST)
            board.paste(image, (index * 158 + 12, 70 + (frame - 1) * 105), image)
    board.save(destination / "examples/icon-review.png")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--no-png", action="store_true", help="Skip rendered review examples")
    args = ap.parse_args()
    build(args.output, not args.no_png)


if __name__ == "__main__":
    main()
