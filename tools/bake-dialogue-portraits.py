#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import html
import io
import json
import re
import shutil
import struct
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from PIL import Image

SCHEMA = "cf7-dialogue-portraits-v2"
AUTHORITY_POLICY_SCHEMA = "cf7.dialogue-portrait-source-authority-policy.v1"
INTERNAL_PORTRAIT_EXPORT_NAME = "对话框肖像"
DEFAULT_EXPRESSION = "普通"
HERO_KEYS = {"$PC_CHAR", "玩家", "主角模板"}
SKIP_INTERNAL_KEYS = {"玩家", "主角模板"}
SOURCE_IDS = {"external-swf", "dialogue-ui-sprite"}

FRAME_LABEL_RE = re.compile(r'<item\s+type="FrameLabelTag"[^>]*\sname="([^"]*)"')
SHOW_FRAME_RE = re.compile(r'<item\s+type="ShowFrameTag"')


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    parser = argparse.ArgumentParser(description="Bake Flash dialogue portraits into Web PNG assets.")
    parser.add_argument("--project-root", default=str(project_root))
    parser.add_argument("--ffdec", default=str(project_root / "tools" / "ffdec" / "ffdec-cli.exe"))
    parser.add_argument("--output-dir", default=str(project_root / "launcher" / "web" / "assets" / "dialogue-portraits"))
    parser.add_argument("--tmp-dir", default=str(project_root / "tmp" / "dialogue-portrait-bake"))
    parser.add_argument(
        "--authority-policy",
        default=str(project_root / "tools" / "dialogue-portrait-source-review" / "authority-policy.json"),
    )
    parser.add_argument(
        "--semantic-baseline-dir",
        default="",
        help=(
            "Existing dialogue portrait output used to suppress internal PNG changes that only alter "
            "fully transparent canvas pixels. Defaults to the pre-bake output directory."
        ),
    )
    parser.add_argument(
        "--review-candidate-dir",
        default=str(project_root / "tmp" / "dialogue-portrait-source-review" / "candidates"),
        help="Ignored cache for rejected-source PNGs used by the human authority review page.",
    )
    parser.add_argument("--zoom", type=int, default=1)
    parser.add_argument("--limit", type=int, default=0, help="Only export the first N external portraits; internal still exports.")
    parser.add_argument("--external-only", action="store_true")
    parser.add_argument("--internal-only", action="store_true")
    parser.add_argument("--keep-tmp", action="store_true")
    parser.add_argument("--ffdec-timeout-seconds", type=int, default=180)
    return parser.parse_args()


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def first_child(parent: ET.Element, name: str) -> ET.Element | None:
    for child in list(parent):
        if local_name(child.tag) == name:
            return child
    return None


def iter_desc(parent: ET.Element, name: str):
    for elem in parent.iter():
        if local_name(elem.tag) == name:
            yield elem


def short_hash(value: str, length: int = 12) -> str:
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:length]


def stable_dir(kind: str, key: str) -> str:
    return f"{kind}_{short_hash(key)}"


def stable_file(expression: str) -> str:
    return f"e_{short_hash(expression)}.png"


def normalize_key(value: Any) -> str:
    return str(value or "").strip()


def alias_candidates(key: str) -> list[str]:
    aliases = []
    values = [
        key,
        key.strip(),
        key.lower(),
        key.upper(),
        key.replace(" ", ""),
        key.replace(" ", "").lower(),
    ]
    for value in values:
        if value and value not in aliases:
            aliases.append(value)
    case_aliases = {
        "boy": "Boy",
        "Boy": "boy",
        "king": "King",
        "King": "king",
        "pig": "Pig",
        "Pig": "pig",
        "shopgirl": "Shop Girl",
        "ShopGirl": "Shop Girl",
        "TheGirl": "The Girl",
    }
    for value in list(aliases):
        alias = case_aliases.get(value)
        if alias and alias not in aliases:
            aliases.append(alias)
    return aliases


def run_command(args: list[str], cwd: Path, timeout_seconds: int) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout_seconds,
    )
    if result.returncode != 0:
        tail = result.stdout[-1600:] if result.stdout else ""
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(args)}\n{tail}")
    return result


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as fh:
        header = fh.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return 0, 0
    width, height = struct.unpack(">II", header[16:24])
    return int(width), int(height)


def png_alpha_bounds(path: Path) -> dict[str, int] | None:
    with Image.open(path) as img:
        alpha = img.convert("RGBA").getchannel("A")
        bbox = alpha.getbbox()
    if not bbox:
        return None
    left, top, right, bottom = bbox
    return {
        "x": int(left),
        "y": int(top),
        "width": int(right - left),
        "height": int(bottom - top),
    }


def normalized_visible_rgba(image: Image.Image, bbox: tuple[int, int, int, int]) -> bytes:
    crop = image.convert("RGBA").crop(bbox)
    pixels = bytearray(crop.tobytes())
    for offset in range(0, len(pixels), 4):
        if pixels[offset + 3] == 0:
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
    return bytes(pixels)


def internal_assets_are_alpha_equivalent(candidate_path: Path, baseline_png: bytes) -> bool:
    with Image.open(candidate_path) as candidate_image, Image.open(io.BytesIO(baseline_png)) as baseline_image:
        candidate = candidate_image.convert("RGBA")
        baseline = baseline_image.convert("RGBA")
        candidate_bbox = candidate.getchannel("A").getbbox()
        baseline_bbox = baseline.getchannel("A").getbbox()
        if candidate_bbox is None or baseline_bbox is None or candidate_bbox != baseline_bbox:
            return False
        return normalized_visible_rgba(candidate, candidate_bbox) == normalized_visible_rgba(baseline, baseline_bbox)


def load_semantic_baseline(baseline_dir: Path) -> dict[str, dict[str, Any]]:
    manifest_path = baseline_dir / "manifest.json"
    if not manifest_path.is_file():
        return {}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema") != SCHEMA:
        raise RuntimeError(f"Unsupported dialogue portrait semantic baseline schema: {manifest.get('schema')}")
    baseline_root = baseline_dir.resolve()
    result: dict[str, dict[str, Any]] = {}
    for entry in manifest.get("entries", {}).values():
        if normalize_key(entry.get("source")) != "dialogue-ui-sprite":
            continue
        for asset in (entry.get("expressions") or {}).values():
            uri = normalize_key(asset.get("uri"))
            if not uri or uri in result:
                raise RuntimeError(f"Invalid or duplicate semantic baseline asset URI: {uri!r}")
            source_path = (baseline_root / Path(uri)).resolve()
            if baseline_root not in source_path.parents or not source_path.is_file():
                raise RuntimeError(f"Semantic baseline asset is missing or escapes its root: {uri}")
            baseline_png = source_path.read_bytes()
            width, height = png_size(source_path)
            bounds = png_alpha_bounds(source_path)
            if width != asset.get("width") or height != asset.get("height") or bounds != asset.get("bounds"):
                raise RuntimeError(f"Semantic baseline metadata drift: {uri}")
            result[uri] = {"asset": dict(asset), "png": baseline_png}
    return result


def read_external_names(list_xml: Path) -> list[str]:
    root = ET.parse(list_xml).getroot()
    names = []
    for node in root.findall(".//portrait"):
        name = normalize_key(node.text)
        if name:
            names.append(name)
    return names


def swf_lookup(portrait_dir: Path) -> dict[str, Path]:
    lookup: dict[str, Path] = {}
    for swf in portrait_dir.glob("*.swf"):
        lookup[swf.stem] = swf
        lookup[swf.stem.lower()] = swf
    return lookup


def export_swf_xml(ffdec: Path, project_root: Path, swf: Path, xml_path: Path, timeout_seconds: int) -> None:
    xml_path.parent.mkdir(parents=True, exist_ok=True)
    run_command([str(ffdec), "-swf2xml", str(swf), str(xml_path)], project_root, timeout_seconds)


def timeline_labels_from_swf_xml(xml_path: Path) -> dict[str, int]:
    labels: dict[str, int] = {}
    frame = 1
    with xml_path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = FRAME_LABEL_RE.search(line)
            if m:
                label = normalize_key(html.unescape(m.group(1)))
                if label and label not in labels:
                    labels[label] = frame
            if SHOW_FRAME_RE.search(line):
                frame += 1
    if DEFAULT_EXPRESSION not in labels:
        labels[DEFAULT_EXPRESSION] = 1
    return labels


def find_exported_frame_dir(base: Path, expected_id: int | None = None) -> Path:
    dirs = [p for p in base.iterdir() if p.is_dir()]
    if not dirs:
        return base
    if expected_id is not None:
        for directory in dirs:
            if f"_{expected_id}_" in directory.name or directory.name.endswith(f"_{expected_id}"):
                return directory
    if len(dirs) == 1:
        return dirs[0]
    return base


def exported_asset_id_from_swf_xml(xml_path: Path, export_name: str) -> int | None:
    root = ET.parse(xml_path).getroot()
    for item in iter_desc(root, "item"):
        if item.attrib.get("type") != "ExportAssetsTag":
            continue
        tags = first_child(item, "tags")
        names = first_child(item, "names")
        if tags is None or names is None:
            continue
        tag_values = [normalize_key(child.text) for child in list(tags) if local_name(child.tag) == "item"]
        name_values = [normalize_key(child.text) for child in list(names) if local_name(child.tag) == "item"]
        for raw_id, name in zip(tag_values, name_values):
            if name == export_name and raw_id.isdigit():
                return int(raw_id)
    return None


def export_external_frames(
    ffdec: Path,
    project_root: Path,
    swf: Path,
    labels: dict[str, int],
    out_dir: Path,
    zoom: int,
    timeout_seconds: int,
    selected_only: bool = True,
) -> None:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    selected = ",".join(str(frame) for frame in sorted(set(labels.values())))
    args = [
        str(ffdec),
        "-ignorebackground",
        "-zoom",
        str(zoom),
        "-format",
        "frame:png",
    ]
    if selected and selected_only:
        args += ["-select", selected]
    args += ["-export", "frame", str(out_dir), str(swf)]
    run_command(args, project_root, timeout_seconds)


def missing_label_frames(frames_dir: Path, labels: dict[str, int]) -> list[tuple[str, int]]:
    missing = []
    for expression, frame_no in labels.items():
        if not (frames_dir / f"{frame_no}.png").exists():
            missing.append((expression, frame_no))
    return missing


def export_internal_sprite(
    ffdec: Path,
    project_root: Path,
    swf: Path,
    out_dir: Path,
    sprite_id: int,
    zoom: int,
    timeout_seconds: int,
) -> Path:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            str(ffdec),
            "-ignorebackground",
            "-zoom",
            str(zoom),
            "-format",
            "sprite:png",
            "-selectid",
            str(sprite_id),
            "-export",
            "sprite",
            str(out_dir),
            str(swf),
        ],
        project_root,
        timeout_seconds,
    )
    return find_exported_frame_dir(out_dir, sprite_id)


def copy_asset(
    src: Path,
    output_dir: Path,
    rel_dir: str,
    expression: str,
    *,
    source_kind: str = "",
    semantic_baseline: dict[str, dict[str, Any]] | None = None,
    semantic_noop_assets: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    dst_rel = Path(rel_dir) / stable_file(expression)
    dst = output_dir / dst_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    uri = dst_rel.as_posix()
    baseline = (semantic_baseline or {}).get(uri)
    reused = (
        source_kind == "dialogue-ui-sprite"
        and baseline is not None
        and internal_assets_are_alpha_equivalent(src, baseline["png"])
    )
    if reused:
        dst.write_bytes(baseline["png"])
        if semantic_noop_assets is not None:
            candidate_width, candidate_height = png_size(src)
            semantic_noop_assets.append(
                {
                    "uri": uri,
                    "reason": "alpha-equivalent-transparent-canvas-only",
                    "candidateSize": {"width": candidate_width, "height": candidate_height},
                    "reusedSize": {
                        "width": int(baseline["asset"]["width"]),
                        "height": int(baseline["asset"]["height"]),
                    },
                }
            )
    else:
        shutil.copy2(src, dst)
    width, height = png_size(dst)
    asset = {
        "uri": uri,
        "width": width,
        "height": height,
        "frame": int(src.stem) if src.stem.isdigit() else None,
    }
    bounds = png_alpha_bounds(dst)
    if bounds:
        asset["bounds"] = bounds
    return asset


def labels_from_symbol_xml(xml_path: Path) -> dict[str, int]:
    if not xml_path.exists():
        return {}
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError:
        return {}
    result: dict[str, int] = {}
    for layer in iter_desc(root, "DOMLayer"):
        if layer.attrib.get("name") != "Labels Layer":
            continue
        frames = first_child(layer, "frames")
        if frames is None:
            continue
        for frame in list(frames):
            if local_name(frame.tag) != "DOMFrame":
                continue
            name = normalize_key(frame.attrib.get("name"))
            if name:
                result[name] = int(frame.attrib.get("index") or 0)
        break
    return result


def frame_ranges_from_dialogue_portrait(xfl_xml: Path) -> list[dict[str, Any]]:
    root = ET.parse(xfl_xml).getroot()
    labels: list[dict[str, Any]] = []
    for layer in iter_desc(root, "DOMLayer"):
        if layer.attrib.get("name") != "Labels Layer":
            continue
        frames = first_child(layer, "frames")
        if frames is None:
            continue
        for frame in list(frames):
            if local_name(frame.tag) != "DOMFrame":
                continue
            name = normalize_key(frame.attrib.get("name"))
            if not name:
                continue
            labels.append(
                {
                    "key": name,
                    "index": int(frame.attrib.get("index") or 0),
                    "duration": int(frame.attrib.get("duration") or 1),
                }
            )
        break
    return labels


def symbol_on_frame(xfl_xml: Path, frame_index: int) -> str | None:
    root = ET.parse(xfl_xml).getroot()
    for layer in iter_desc(root, "DOMLayer"):
        name = layer.attrib.get("name") or ""
        if name in {"Labels Layer", "Script Layer"} or layer.attrib.get("layerType") == "mask":
            continue
        frames = first_child(layer, "frames")
        if frames is None:
            continue
        for frame in list(frames):
            if local_name(frame.tag) != "DOMFrame":
                continue
            start = int(frame.attrib.get("index") or 0)
            duration = int(frame.attrib.get("duration") or 1)
            if frame_index < start or frame_index >= start + duration:
                continue
            elements = first_child(frame, "elements")
            if elements is None:
                continue
            for symbol in iter_desc(elements, "DOMSymbolInstance"):
                item = normalize_key(symbol.attrib.get("libraryItemName"))
                if item:
                    return item
    return None


def resolve_library_xml(library_dir: Path, library_item_name: str) -> Path:
    return library_dir / Path(library_item_name + ".xml")


def load_authority_policy(policy_path: Path) -> tuple[dict[str, Any], dict[str, str], str]:
    if not policy_path.exists():
        raise RuntimeError(f"Missing dialogue portrait source authority policy: {policy_path}")
    raw = policy_path.read_bytes()
    policy = json.loads(raw.decode("utf-8"))
    if policy.get("schema") != AUTHORITY_POLICY_SCHEMA:
        raise RuntimeError(f"Unsupported dialogue portrait authority policy schema: {policy.get('schema')}")
    raw_decisions = policy.get("decisions")
    if not isinstance(raw_decisions, dict) or not raw_decisions:
        raise RuntimeError("Dialogue portrait authority policy decisions must be a non-empty object")
    decisions: dict[str, str] = {}
    for raw_key, raw_source in raw_decisions.items():
        key = normalize_key(raw_key)
        source = normalize_key(raw_source)
        if not key or key != raw_key:
            raise RuntimeError(f"Dialogue portrait authority policy key is not normalized: {raw_key!r}")
        if source not in SOURCE_IDS:
            raise RuntimeError(f"Dialogue portrait authority policy has unsupported source for {key}: {source}")
        decisions[key] = source
    return policy, decisions, hashlib.sha256(raw).hexdigest()


def discover_source_collisions(project_root: Path, limit: int = 0) -> list[str]:
    external_names = read_external_names(project_root / "flashswf" / "portraits" / "list.xml")
    if limit > 0:
        external_names = external_names[:limit]
    internal_ranges = frame_ranges_from_dialogue_portrait(
        project_root / "flashswf" / "UI" / "对话框界面" / "LIBRARY" / "对话框肖像.xml"
    )
    internal_names = {
        normalize_key(item.get("key"))
        for item in internal_ranges
        if normalize_key(item.get("key"))
        and not normalize_key(item.get("key")).startswith("--")
        and normalize_key(item.get("key")) not in SKIP_INTERNAL_KEYS
    }
    return [name for name in external_names if name in internal_names]


def validate_authority_policy_coverage(
    decisions: dict[str, str],
    collisions: list[str],
    *,
    require_exact: bool,
) -> None:
    collision_set = set(collisions)
    decision_set = set(decisions)
    missing = sorted(collision_set - decision_set)
    stale = sorted(decision_set - collision_set) if require_exact else []
    if missing or stale:
        raise RuntimeError(
            "Dialogue portrait source authority policy coverage mismatch: "
            + json.dumps({"missing": missing, "stale": stale}, ensure_ascii=False)
        )


def append_entry(
    manifest: dict[str, Any],
    entry: dict[str, Any],
    authority_decisions: dict[str, str],
    report: dict[str, Any],
) -> None:
    key = entry["key"]
    existing = manifest["entries"].get(key)
    if existing is None:
        manifest["entries"][key] = entry
        return
    existing_source = normalize_key(existing.get("source"))
    incoming_source = normalize_key(entry.get("source"))
    if existing_source == incoming_source:
        raise RuntimeError(f"Duplicate dialogue portrait entry within source {incoming_source}: {key}")
    candidates = {existing_source, incoming_source}
    selected_source = authority_decisions.get(key)
    if selected_source is None:
        raise RuntimeError(f"Unreviewed dialogue portrait source collision: {key}")
    if selected_source not in candidates:
        raise RuntimeError(
            f"Dialogue portrait authority for {key} selects {selected_source}, "
            f"but candidates are {sorted(candidates)}"
        )
    selected = existing if existing_source == selected_source else entry
    rejected = entry if selected is existing else existing
    manifest["entries"][key] = selected
    report["sourceCollisions"].append(
        {
            "key": key,
            "candidates": sorted(candidates),
            "selectedSource": selected_source,
            "rejectedSource": rejected["source"],
            "policy": "explicit-human-authority",
        }
    )


def rebuild_aliases(manifest: dict[str, Any]) -> None:
    manifest["aliases"] = {}
    for entry in manifest["entries"].values():
        key = entry["key"]
        for alias in alias_candidates(key):
            if alias != key:
                manifest["aliases"].setdefault(alias, key)
        for alias in entry.get("aliases") or []:
            if alias and alias != key:
                manifest["aliases"].setdefault(alias, key)


def validate_baked_authority(
    manifest: dict[str, Any],
    report: dict[str, Any],
    collisions: list[str],
    authority_decisions: dict[str, str],
) -> None:
    expected = set(collisions)
    observed = {normalize_key(item.get("key")) for item in report["sourceCollisions"]}
    if observed != expected:
        raise RuntimeError(
            "Dialogue portrait baked collision closure mismatch: "
            + json.dumps(
                {
                    "missing": sorted(expected - observed),
                    "unexpected": sorted(observed - expected),
                },
                ensure_ascii=False,
            )
        )
    wrong = []
    for key in collisions:
        actual = normalize_key(manifest["entries"].get(key, {}).get("source"))
        selected = authority_decisions[key]
        if actual != selected:
            wrong.append({"key": key, "selected": selected, "actual": actual or None})
    if wrong:
        raise RuntimeError(
            "Dialogue portrait baked authority postcondition failed: "
            + json.dumps(wrong, ensure_ascii=False)
        )


def enforce_asset_closure(
    output_dir: Path,
    manifest: dict[str, Any],
    review_candidate_dir: Path | None = None,
) -> tuple[set[str], list[str]]:
    referenced: set[str] = set()
    for entry in manifest.get("entries", {}).values():
        for asset in (entry.get("expressions") or {}).values():
            uri = normalize_key(asset.get("uri"))
            if not uri or uri in referenced:
                raise RuntimeError(f"Invalid or duplicate dialogue portrait manifest asset URI: {uri!r}")
            referenced.add(uri)
    on_disk = {path.relative_to(output_dir).as_posix() for path in output_dir.rglob("*.png")}
    missing = sorted(referenced - on_disk)
    if missing:
        raise RuntimeError(
            "Dialogue portrait asset closure has missing PNGs: "
            + json.dumps(missing, ensure_ascii=False)
        )
    pruned = sorted(on_disk - referenced)
    for uri in pruned:
        source_path = output_dir / Path(uri)
        if review_candidate_dir is not None:
            candidate_path = review_candidate_dir / Path(uri)
            candidate_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, candidate_path)
        source_path.unlink()
    directories = sorted(
        (path for path in output_dir.rglob("*") if path.is_dir()),
        key=lambda path: len(path.parts),
        reverse=True,
    )
    for directory in directories:
        if not any(directory.iterdir()):
            directory.rmdir()
    final_on_disk = {path.relative_to(output_dir).as_posix() for path in output_dir.rglob("*.png")}
    if final_on_disk != referenced:
        raise RuntimeError("Dialogue portrait asset closure did not converge after pruning")
    return referenced, pruned


def bake_external(
    args: argparse.Namespace,
    manifest: dict[str, Any],
    report: dict[str, Any],
    authority_decisions: dict[str, str],
) -> None:
    project_root = Path(args.project_root)
    ffdec = Path(args.ffdec)
    portrait_dir = project_root / "flashswf" / "portraits"
    lookup = swf_lookup(portrait_dir)
    names = read_external_names(portrait_dir / "list.xml")
    if args.limit > 0:
        names = names[: args.limit]
    tmp_base = Path(args.tmp_dir) / "external"
    for index, name in enumerate(names, 1):
        swf = lookup.get(name) or lookup.get(name.lower())
        if not swf or not swf.exists():
            report["missingExternalSwf"].append(name)
            continue
        key = swf.stem
        print(f"[external {index}/{len(names)}] {key}")
        stem_id = stable_dir("external", key)
        xml_path = tmp_base / stem_id / "source.xml"
        frames_dir = tmp_base / stem_id / "frames"
        export_swf_xml(ffdec, project_root, swf, xml_path, args.ffdec_timeout_seconds)
        labels = timeline_labels_from_swf_xml(xml_path)
        export_external_frames(ffdec, project_root, swf, labels, frames_dir, args.zoom, args.ffdec_timeout_seconds)
        if missing_label_frames(frames_dir, labels):
            export_external_frames(
                ffdec,
                project_root,
                swf,
                labels,
                frames_dir,
                args.zoom,
                args.ffdec_timeout_seconds,
                selected_only=False,
            )
        entry = {
            "key": key,
            "aliases": [a for a in alias_candidates(name) if a != key],
            "source": "external-swf",
            "sourcePath": swf.relative_to(project_root).as_posix(),
            "defaultExpression": DEFAULT_EXPRESSION,
            "expressions": {},
        }
        for expression, frame_no in sorted(labels.items(), key=lambda item: (item[1], item[0])):
            frame_path = frames_dir / f"{frame_no}.png"
            if not frame_path.exists():
                report["missingFrames"].append({"key": key, "expression": expression, "frame": frame_no})
                continue
            entry["expressions"][expression] = copy_asset(
                frame_path,
                Path(args.output_dir),
                f"external/{stable_dir('p', key)}",
                expression,
            )
        append_entry(manifest, entry, authority_decisions, report)
        report["externalEntries"] += 1
        report["externalExpressions"] += len(entry["expressions"])


def bake_internal(
    args: argparse.Namespace,
    manifest: dict[str, Any],
    report: dict[str, Any],
    authority_decisions: dict[str, str],
    semantic_baseline: dict[str, dict[str, Any]],
    semantic_noop_assets: list[dict[str, Any]],
) -> None:
    project_root = Path(args.project_root)
    ffdec = Path(args.ffdec)
    ui_dir = project_root / "flashswf" / "UI" / "对话框界面"
    library_dir = ui_dir / "LIBRARY"
    portrait_xml = library_dir / "对话框肖像.xml"
    swf = project_root / "flashswf" / "UI" / "对话框界面.swf"
    tmp_base = Path(args.tmp_dir) / "internal"
    print("[internal] 对话框肖像")
    swf_xml = tmp_base / "source.xml"
    export_swf_xml(ffdec, project_root, swf, swf_xml, args.ffdec_timeout_seconds)
    sprite_id = exported_asset_id_from_swf_xml(swf_xml, INTERNAL_PORTRAIT_EXPORT_NAME)
    if sprite_id is None:
        raise RuntimeError(f"Cannot resolve exported symbol {INTERNAL_PORTRAIT_EXPORT_NAME} in {swf}")
    report["internalPortraitSpriteId"] = sprite_id
    frame_dir = export_internal_sprite(
        ffdec,
        project_root,
        swf,
        tmp_base / "sprite",
        sprite_id,
        args.zoom,
        args.ffdec_timeout_seconds,
    )
    ranges = frame_ranges_from_dialogue_portrait(portrait_xml)
    for item in ranges:
        key = item["key"]
        if key.startswith("--") or key in SKIP_INTERNAL_KEYS:
            continue
        start = int(item["index"])
        duration = int(item["duration"])
        entry = {
            "key": key,
            "aliases": [],
            "source": "dialogue-ui-sprite",
            "sourcePath": swf.relative_to(project_root).as_posix(),
            "defaultExpression": DEFAULT_EXPRESSION,
            "expressions": {},
        }
        expression_frames: dict[str, int] = {DEFAULT_EXPRESSION: start + 1}
        symbol_name = symbol_on_frame(portrait_xml, start)
        if symbol_name:
            child_labels = labels_from_symbol_xml(resolve_library_xml(library_dir, symbol_name))
            for expression, child_index in child_labels.items():
                if expression in {"刷新", "男", "女"}:
                    continue
                frame_no = start + int(child_index) + 1
                if frame_no >= start + 1 and frame_no <= start + max(duration, 1):
                    expression_frames[expression] = frame_no
        for expression, frame_no in sorted(expression_frames.items(), key=lambda item: (item[1], item[0])):
            frame_path = frame_dir / f"{frame_no}.png"
            if not frame_path.exists():
                report["missingFrames"].append({"key": key, "expression": expression, "frame": frame_no})
                continue
            entry["expressions"][expression] = copy_asset(
                frame_path,
                Path(args.output_dir),
                f"internal/{stable_dir('p', key)}",
                expression,
                source_kind="dialogue-ui-sprite",
                semantic_baseline=semantic_baseline,
                semantic_noop_assets=semantic_noop_assets,
            )
        if entry["expressions"]:
            append_entry(manifest, entry, authority_decisions, report)
            report["internalEntries"] += 1
            report["internalExpressions"] += len(entry["expressions"])


def main() -> None:
    args = parse_args()
    if args.external_only and args.internal_only:
        raise SystemExit("--external-only and --internal-only are mutually exclusive")
    project_root = Path(args.project_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    tmp_dir = Path(args.tmp_dir).resolve()
    authority_policy_path = Path(args.authority_policy).resolve()
    semantic_baseline_dir = (
        Path(args.semantic_baseline_dir).resolve()
        if args.semantic_baseline_dir
        else output_dir
    )
    review_candidate_dir = Path(args.review_candidate_dir).resolve()
    full_bake = not args.external_only and not args.internal_only and args.limit == 0
    if not Path(args.ffdec).exists():
        raise SystemExit(f"Missing FFDec CLI: {args.ffdec}")
    authority_policy, authority_decisions, authority_policy_digest = load_authority_policy(authority_policy_path)
    collisions = (
        discover_source_collisions(project_root, args.limit)
        if not args.external_only and not args.internal_only
        else []
    )
    validate_authority_policy_coverage(
        authority_decisions,
        collisions,
        require_exact=not args.external_only and not args.internal_only and args.limit == 0,
    )
    semantic_baseline = load_semantic_baseline(semantic_baseline_dir)
    active_review_candidate_dir: Path | None = None
    if full_bake:
        allowed_review_root = (project_root / "tmp").resolve()
        if allowed_review_root not in review_candidate_dir.parents:
            raise RuntimeError(f"Review candidate directory must stay under tmp/: {review_candidate_dir}")
        if review_candidate_dir.exists():
            shutil.rmtree(review_candidate_dir)
        review_candidate_dir.mkdir(parents=True, exist_ok=True)
        active_review_candidate_dir = review_candidate_dir
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    if tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    manifest: dict[str, Any] = {
        "schema": SCHEMA,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "zoom": args.zoom,
        "baseSize": {"width": 1024 * args.zoom, "height": 576 * args.zoom},
        # 复刻原版对话框取景：外部立绘透过 flashswf/UI/对话框界面 元件里的固定遮罩窗口显示。
        # 外部 SWF 在「外部立绘层」原点、100% 放置，遮罩与 SWF 共用同一坐标系，故该矩形直接是
        # 1024×576 舞台 PNG 上的裁剪框（mask 解析自 LIBRARY/对话框界面.xml 的 mask 层）。所有 pose
        # 共用此窗口 + 同一缩放 → web 端不再按各自包围盒 fit（消除「一张铺满一张很扁」）。
        # 内置 sprite（对话框肖像）取景在另一坐标系，故此处仅给 external-swf；其余走包围盒兜底。
        "portraitWindow": {
            "external-swf": {
                "x": 30 * args.zoom,
                "y": 30 * args.zoom,
                "width": 880 * args.zoom,
                "height": 375 * args.zoom,
            },
        },
        "heroKeys": sorted(HERO_KEYS),
        "sourceAuthority": {
            "schema": AUTHORITY_POLICY_SCHEMA,
            "policyPath": authority_policy_path.relative_to(project_root).as_posix(),
            "policySha256": authority_policy_digest,
            "collisionPolicy": "explicit-human-authority",
        },
        "entries": {},
        "aliases": {},
    }
    report: dict[str, Any] = {
        "externalEntries": 0,
        "externalExpressions": 0,
        "internalEntries": 0,
        "internalExpressions": 0,
        "internalPortraitSpriteId": None,
        "missingExternalSwf": [],
        "missingFrames": [],
        "sourceAuthority": {
            "policyPath": authority_policy_path.relative_to(project_root).as_posix(),
            "policySha256": authority_policy_digest,
            "reviewReceipt": authority_policy.get("reviewReceipt"),
        },
        "sourceCollisions": [],
    }
    semantic_noop_assets: list[dict[str, Any]] = []

    if not args.internal_only:
        bake_external(args, manifest, report, authority_decisions)
    if not args.external_only:
        bake_internal(
            args,
            manifest,
            report,
            authority_decisions,
            semantic_baseline,
            semantic_noop_assets,
        )
    rebuild_aliases(manifest)
    report["sourceCollisions"].sort(key=lambda item: item["key"])
    validate_baked_authority(manifest, report, collisions, authority_decisions)
    referenced_assets, pruned_assets = enforce_asset_closure(
        output_dir,
        manifest,
        active_review_candidate_dir,
    )
    retained_semantic_noops = sorted(
        (item for item in semantic_noop_assets if item["uri"] in referenced_assets),
        key=lambda item: item["uri"],
    )
    report["semanticNoopReuse"] = {
        "algorithm": "internal-alpha-bounds-and-visible-rgba-v1",
        "count": len(retained_semantic_noops),
        "assets": retained_semantic_noops,
    }
    report["assetClosure"] = {
        "referencedPngs": len(referenced_assets),
        "onDiskPngs": len(referenced_assets),
        "prunedPngs": len(pruned_assets),
        "prunedAssets": pruned_assets,
    }

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report_path = output_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not args.keep_tmp and tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    print(json.dumps({"manifest": str(manifest_path.relative_to(project_root)), "report": report}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
