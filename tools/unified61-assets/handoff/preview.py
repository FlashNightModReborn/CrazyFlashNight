#!/usr/bin/env python3
"""Standalone Type61 SVG assembly. Python 3.9+, standard library by default."""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import html
import json
import math
import re
import sys
import zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
ET.register_namespace("", SVG)
ET.register_namespace("xlink", XLINK)
ALLOWED_TAGS = {
    "svg", "g", "defs", "title", "desc", "metadata", "path", "rect", "circle",
    "ellipse", "line", "polyline", "polygon", "linearGradient", "radialGradient",
    "stop", "clipPath",
}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def inside(path):
    result = (ROOT / path).resolve()
    if not result.is_relative_to(ROOT):
        raise ValueError("Path leaves this kit: " + str(path))
    return result


def load():
    return read_json(ROOT / "data/catalog.json"), read_json(ROOT / "data/poses.json")


def part_path(catalog, variant, part_id, state="closed", baseline=False):
    part = catalog["variants"][variant]["parts"][part_id]
    value = part["states"].get(state, part["states"]["closed"])
    if baseline and variant == "unified":
        value = "baseline/" + value
    return inside(value)


def namespaced_children(text, prefix):
    root = ET.fromstring(text)
    replacements = {e.get("id"): prefix + e.get("id") for e in root.iter() if e.get("id")}
    for element in root.iter():
        for key, value in list(element.attrib.items()):
            if key == "id":
                element.set(key, replacements[value])
            else:
                value = re.sub(r"url\(#([^)]+)\)", lambda m: "url(#" + replacements.get(m[1], m[1]) + ")", value)
                if key in ("href", "{" + XLINK + "}href") and value.startswith("#"):
                    value = "#" + replacements.get(value[1:], value[1:])
                element.set(key, value)
    return [copy.deepcopy(child) for child in root]


def node(tag, **attributes):
    return ET.Element("{" + SVG + "}" + tag, {k: str(v) for k, v in attributes.items()})


def fmt(value):
    return ("%.9f" % value).rstrip("0").rstrip(".") or "0"


def assembled_group(catalog, pose, variant="unified", gender="male", state="closed",
                    baseline=False, raster=False, prefix="part"):
    group = node("g")
    mapping = catalog["variants"][variant]["fieldsByGender"][gender]
    placed = []
    for index, holder in enumerate(pose["holders"]):
        part_id = mapping.get(holder["field"])
        if not part_id:
            continue
        matrix = holder["matrix"]
        if len(matrix) != 6 or not all(math.isfinite(v) for v in matrix):
            raise ValueError("Invalid pose matrix")
        wrapper = node("g", transform="matrix(" + " ".join(map(fmt, matrix)) + ")")
        wrapper.set("data-part", part_id)
        if raster:
            if state != "closed":
                raise ValueError("Existing exported PNGs cover the closed torso only")
            ref = catalog["variants"][variant]["parts"][part_id]["raster"]
            image = node("image", x=fmt(-ref["originX"] / ref["zoom"]),
                         y=fmt(-ref["originY"] / ref["zoom"]),
                         width=fmt(ref["width"] / ref["zoom"]),
                         height=fmt(ref["height"] / ref["zoom"]))
            image.set("href", "data:image/png;base64," + base64.b64encode(inside(ref["path"]).read_bytes()).decode("ascii"))
            wrapper.append(image)
        else:
            text = part_path(catalog, variant, part_id, state, baseline).read_text(encoding="utf-8")
            wrapper.extend(namespaced_children(text, prefix + str(index) + "_"))
        group.append(wrapper)
        placed.append(part_id)
    if len(placed) != 15 or len(set(placed)) != 12:
        raise ValueError("Expected 15 placements of 12 unique parts: " + pose["id"])
    return group


def to_svg(element):
    return ET.tostring(element, encoding="unicode", short_empty_elements=True) + "\n"


def compose(catalog, pose, variant="unified", gender="male", state="closed",
            height=160, mirror=False, background="transparent", baseline=False, raster=False):
    # One fixed canvas and one scale for all variants and revisions.
    box = catalog["reviewCanvas"]
    width = max(1, round(box[2] / box[3] * height))
    root = node("svg", viewBox=" ".join(map(fmt, box)), width=width, height=height)
    title = node("title")
    title.text = catalog["variants"][variant]["label"] + " / " + pose["label"] + " / " + state
    root.append(title)
    if background != "transparent":
        root.append(node("rect", x=box[0], y=box[1], width=box[2], height=box[3], fill=background))
    group = assembled_group(catalog, pose, variant, gender, state, baseline, raster)
    if mirror:
        group.set("transform", "matrix(-1 0 0 1 0 0)")
    root.append(group)
    return to_svg(root)


def compose_icon(catalog, slot, frame=1, size=24, baseline=False):
    recipe = catalog["icons"][slot]
    root = node("svg", viewBox="-12 -12 24 24", width=size, height=size)
    if frame == 1:
        root.extend(namespaced_children((ROOT / "data/icon-shadow.svg").read_text(encoding="utf-8"), "shadow_"))
    defs = node("defs")
    clip = node("clipPath", id="icon_crop", clipPathUnits="userSpaceOnUse")
    # The exact native crop, rather than a newly invented square.
    clip.extend(namespaced_children((ROOT / "data/icon-crop.svg").read_text(encoding="utf-8"), "crop_"))
    defs.append(clip)
    root.append(defs)
    outer = node("g", **{"clip-path": "url(#icon_crop)"})
    inner = node("g", transform="matrix(" + " ".join(map(fmt, recipe["matrix"])) + ")")
    inner.extend(namespaced_children(part_path(catalog, "unified", recipe["part"], baseline=baseline).read_text("utf-8"), "icon_art_"))
    outer.append(inner)
    root.append(outer)
    return to_svg(root)


def review_pair(catalog, pose, gender, height=160, state="closed", background="#283743"):
    box = catalog["reviewCanvas"]
    width = round(box[2] / box[3] * height)
    root = node("svg", width=width * 2 + 36, height=height + 44,
                viewBox="0 0 " + str(width * 2 + 36) + " " + str(height + 44))
    root.append(node("rect", width="100%", height="100%", fill="#18242f"))
    for index, baseline in enumerate((True, False)):
        px = 12 + index * (width + 12)
        label = node("text", x=px, y=19, fill="#e5edf2", **{"font-size": 12, "font-family": "sans-serif"})
        label.text = ("BASELINE" if baseline else "WORK") + " / " + gender + " / " + str(height) + " px"
        root.append(label)
        text = compose(catalog, pose, gender=gender, state=state, height=height,
                       background=background, baseline=baseline)
        source = ET.fromstring(text)
        nested = node("svg", x=px, y=32, width=width, height=height, viewBox=source.get("viewBox"))
        nested.extend(namespaced_children(text, "compare" + str(index) + "_"))
        root.append(nested)
    return to_svg(root)


def work_hashes(catalog):
    return {relative: hashlib.sha256(inside(relative).read_bytes()).hexdigest()
            for part in catalog["variants"]["unified"]["parts"].values() for relative in part["states"].values()}


def record_render(catalog, paths, complete=False):
    target = ROOT / "rendered/render-manifest.json"
    current = work_hashes(catalog)
    old = read_json(target) if target.is_file() else {}
    if old.get("workFiles") != current:
        old = {}
    records = old.get("renders", {})
    for path in paths:
        records[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(target, {"schema": 1, "workFiles": current, "renders": records,
                        "reviewSuiteComplete": bool(complete or old.get("reviewSuiteComplete")),
                        "boundary": "Static rendered reviews of these exact candidate SVG bytes"})


def png(svg, path):
    try:
        import cairosvg
    except (ImportError, OSError) as ex:
        raise RuntimeError("PNG rendering needs the optional CairoSVG dependency. SVG/HTML assembly needs no extra dependency. See README.md.") from ex
    cairosvg.svg2png(bytestring=svg.encode("utf-8"), write_to=str(path))


def payload(catalog, poses):
    files = {}
    for variant, spec in catalog["variants"].items():
        for part_id, part in spec["parts"].items():
            for state, relative in part["states"].items():
                files[relative] = inside(relative).read_text("utf-8")
                if variant == "unified":
                    base = "baseline/" + relative
                    files[base] = inside(base).read_text("utf-8")
            raster = part["raster"]["path"]
            files[raster] = "data:image/png;base64," + base64.b64encode(inside(raster).read_bytes()).decode("ascii")
    for relative in ("data/icon-shadow.svg", "data/icon-crop.svg"):
        files[relative] = inside(relative).read_text("utf-8")
    return {"catalog": catalog, "poses": poses, "files": files}


def write_viewer(catalog, poses):
    content = payload(catalog, poses)
    encoded = json.dumps(content, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    template = (ROOT / "viewer/index.template.html").read_text("utf-8")
    template = template.replace("/*__CSS__*/", (ROOT / "viewer/viewer.css").read_text("utf-8"))
    template = template.replace("/*__JS__*/", (ROOT / "viewer/viewer.js").read_text("utf-8"))
    template = template.replace("/*__DATA__*/", encoded)
    (ROOT / "preview.html").write_text(template, encoding="utf-8")


def verify_candidate(catalog):
    errors = []
    work = ROOT / "assets/unified"
    expected = set()
    for part in catalog["variants"]["unified"]["parts"].values():
        for state, relative in part["states"].items():
            path = inside(relative)
            expected.add(path)
            try:
                text = path.read_text(encoding="utf-8")
                if "<!DOCTYPE" in text.upper() or "<!ENTITY" in text.upper():
                    raise ValueError("External XML declarations are unsupported")
                root = ET.fromstring(text)
                original = ET.parse(inside("baseline/" + relative)).getroot()
                if root.tag != "{" + SVG + "}svg":
                    raise ValueError("Expected an SVG root")
                for key in ("viewBox", "width", "height"):
                    if root.get(key) != original.get(key):
                        raise ValueError("Preserve " + key + " and the local registration coordinate system")
                ids = [e.get("id") for e in root.iter() if e.get("id")]
                if len(ids) != len(set(ids)):
                    raise ValueError("Duplicate SVG ids")
                identifiers = set(ids)
                drawable = 0
                for e in root.iter():
                    local = e.tag.rsplit("}", 1)[-1]
                    if local not in ALLOWED_TAGS:
                        raise ValueError("Unsupported SVG element: " + local)
                    drawable += local in {"path", "rect", "circle", "ellipse", "line", "polyline", "polygon"}
                    for key, value in e.attrib.items():
                        attr = key.rsplit("}", 1)[-1].lower()
                        if attr.startswith("on") or attr in {"href", "src"}:
                            raise ValueError("Scripts and external/embedded resources are not allowed")
                        if attr in {"filter", "mask", "vector-effect", "style"}:
                            raise ValueError("Unsupported attribute for native return: " + attr)
                        if "url(" in value:
                            for ref in re.findall(r"url\(([^)]+)\)", value):
                                if not ref.startswith("#") or ref[1:] not in identifiers:
                                    raise ValueError("Unresolved or external paint/clip reference: " + ref)
                if not drawable:
                    raise ValueError("Empty art")
            except Exception as ex:
                errors.append(str(path.relative_to(ROOT)) + ": " + str(ex))
    actual = {p.resolve() for p in work.rglob("*") if p.is_file()}
    extras = sorted(str(p.relative_to(ROOT)) for p in actual - expected)
    if extras:
        errors.append("Unexpected files in assets/unified: " + ", ".join(extras))
    if errors:
        raise ValueError("\n".join(errors))
    return len(expected)


def verify_package():
    manifest = read_json(ROOT / "MANIFEST.json")
    bad = []
    for relative, record in manifest["files"].items():
        path = inside(relative)
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != record["sha256"]:
            bad.append(relative)
    if bad:
        raise ValueError("Changed or missing package files:\n" + "\n".join(bad))
    return len(manifest["files"])


def make_return(catalog, poses, output):
    verify_candidate(catalog)
    baseline = read_json(ROOT / "MANIFEST.json")
    render_path = ROOT / "rendered/render-manifest.json"
    if not render_path.is_file():
        raise ValueError("Generate a fresh review first: python preview.py --review")
    render_report = read_json(render_path)
    if render_report.get("workFiles") != work_hashes(catalog) or not render_report.get("reviewSuiteComplete"):
        raise ValueError("Reviews are incomplete or stale after SVG changes. Run python preview.py --review again.")
    for relative, digest in render_report["renders"].items():
        path = inside(relative)
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError("A generated review was changed or removed; regenerate it: " + relative)
    # Immutable references and coordinate recipes must remain the supplied baseline.
    immutable = {}
    for relative, record in baseline["files"].items():
        if relative.startswith(("baseline/", "references/", "data/", "source_snapshot/")):
            p = inside(relative)
            if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != record["sha256"]:
                raise ValueError("Restore the read-only reference or recipe before returning: " + relative)
            immutable[relative] = record["sha256"]
    changed = []
    files = []
    for part in catalog["variants"]["unified"]["parts"].values():
        for relative in part["states"].values():
            data = inside(relative).read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            changed.append({"path": relative, "sha256": digest,
                            "changed": digest != baseline["files"][relative]["sha256"]})
            files.append(relative)
    report = {"schema": 1, "sourceSnapshot": catalog["sourceSnapshot"],
              "baseManifestSha256": hashlib.sha256((ROOT / "MANIFEST.json").read_bytes()).hexdigest(),
              "files": changed, "generatedReviewFiles": render_report["renders"],
              "boundary": "Candidate artwork only. No Flash compile or gameplay claim."}
    write_json(ROOT / "rendered/return-manifest.json", report)
    report_path = ROOT / "rendered/return-manifest.json"
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ValueError("Return archive already exists; choose a new revision filename")
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative in sorted(set(files)):
            archive.write(inside(relative), "type61-return/" + relative)
        archive.write(report_path, "type61-return/return-manifest.json")
        for path in sorted((ROOT / "rendered").rglob("*")):
            if path.is_file() and path != report_path and path.suffix.lower() in {".svg", ".png", ".json"}:
                archive.write(path, "type61-return/rendered/" + path.relative_to(ROOT / "rendered").as_posix())
        for path in sorted((ROOT / "return-notes").rglob("*")):
            if path.is_file():
                archive.write(path, "type61-return/notes/" + path.relative_to(ROOT / "return-notes").as_posix())
    print(output)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--variant", choices=("unified", "regular", "titanium"), default="unified")
    ap.add_argument("--gender", choices=("male", "female"), default="male")
    ap.add_argument("--pose", default="idle")
    ap.add_argument("--state", choices=("closed", "open", "fire"), default="closed")
    ap.add_argument("--height", type=int, default=160, help="Canvas height in pixels; this is not a certified in-game character height")
    ap.add_argument("--background", default="transparent")
    ap.add_argument("--mirror", action="store_true")
    ap.add_argument("--raster", action="store_true", help="Existing exported pixels, closed state only")
    ap.add_argument("--all", action="store_true", help="All current rig poses for both genders")
    ap.add_argument("--review", action="store_true", help="Complete return review: poses, torso states, before/after pixel sizes, backgrounds, directions and icons")
    ap.add_argument("--png", action="store_true", help="Also render PNG using optional CairoSVG")
    ap.add_argument("--output", default="rendered/current.svg")
    ap.add_argument("--refresh-viewer", action="store_true")
    ap.add_argument("--verify", action="store_true", help="Validate the 24 editable SVGs and their coordinate contracts")
    ap.add_argument("--verify-package", action="store_true", help="Verify the original package hashes before starting work")
    ap.add_argument("--return-zip", help="Create a new archive with all 24 work SVGs, notes and rendered reviews")
    args = ap.parse_args()
    catalog, poses = load()
    if not 32 <= args.height <= 4096:
        ap.error("--height must be between 32 and 4096")
    if args.verify_package:
        print("Package hashes OK:", verify_package())
        return
    if args.verify:
        print("Editable SVG contracts OK:", verify_candidate(catalog))
        return
    if args.return_zip:
        make_return(catalog, poses, args.return_zip)
        return
    if args.refresh_viewer:
        write_viewer(catalog, poses)
        print(ROOT / "preview.html")
        return
    rows = [(args.gender, p) for p in poses["genders"][args.gender] if p["id"] == args.pose]
    if args.all or args.review:
        rows = [(gender, p) for gender, values in poses["genders"].items()
                for p in values if p["group"] in ("current_battle", "weapon_keys")]
    if not rows:
        ap.error("Unknown pose. Available: " + ", ".join(p["id"] for p in poses["genders"][args.gender]))
    written = []

    def emit(target, text):
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        written.append(target)
        if args.png:
            png(text, target.with_suffix(".png"))
            written.append(target.with_suffix(".png"))
        print(target.relative_to(ROOT))

    for gender, pose in rows:
        target = (ROOT / "rendered" / (args.variant + "_" + gender + "_" + pose["id"] + "_" + args.state + ".svg")
                  if args.all or args.review else inside(args.output))
        text = compose(catalog, pose, args.variant, gender, args.state, args.height, args.mirror,
                       args.background, raster=args.raster)
        emit(target, text)
    if args.all or args.review:
        for slot in catalog["icons"]:
            for frame in (1, 2):
                target = ROOT / "rendered" / ("icon_" + slot + "_f" + str(frame) + ".svg")
                text = compose_icon(catalog, slot, frame)
                emit(target, text)
    if args.review:
        for gender, values in poses["genders"].items():
            idle = next(p for p in values if p["id"] == "idle")
            for state in ("open", "fire"):
                emit(ROOT / "rendered" / ("torso_" + gender + "_" + state + ".svg"),
                     review_pair(catalog, idle, gender, 240, state))
            for height in (96, 128, 160, 320):
                emit(ROOT / "rendered" / ("compare_" + gender + "_" + str(height) + ".svg"),
                     review_pair(catalog, idle, gender, height))
            for label, bg, mirror in (("light", "#ded9c9", False), ("dark", "#10161d", False),
                                      ("mirrored", "#786d55", True)):
                emit(ROOT / "rendered" / (gender + "_" + label + ".svg"),
                     compose(catalog, idle, gender=gender, height=240, background=bg, mirror=mirror))
        print("Complete review generated for the current 24 SVGs.")
    record_render(catalog, written, complete=args.review)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("ERROR:", error, file=sys.stderr)
        sys.exit(1)
