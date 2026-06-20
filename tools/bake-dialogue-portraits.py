#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import html
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
INTERNAL_PORTRAIT_SPRITE_ID = 969
DEFAULT_EXPRESSION = "普通"
HERO_KEYS = {"$PC_CHAR", "玩家", "主角模板"}
SKIP_INTERNAL_KEYS = {"玩家", "主角模板"}

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
            str(INTERNAL_PORTRAIT_SPRITE_ID),
            "-export",
            "sprite",
            str(out_dir),
            str(swf),
        ],
        project_root,
        timeout_seconds,
    )
    return find_exported_frame_dir(out_dir, INTERNAL_PORTRAIT_SPRITE_ID)


def copy_asset(src: Path, output_dir: Path, rel_dir: str, expression: str) -> dict[str, Any]:
    dst_rel = Path(rel_dir) / stable_file(expression)
    dst = output_dir / dst_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    width, height = png_size(dst)
    asset = {
        "uri": dst_rel.as_posix(),
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


def append_entry(manifest: dict[str, Any], entry: dict[str, Any]) -> None:
    key = entry["key"]
    manifest["entries"][key] = entry
    for alias in alias_candidates(key):
        if alias != key:
            manifest["aliases"].setdefault(alias, key)
    for alias in entry.get("aliases") or []:
        if alias and alias != key:
            manifest["aliases"].setdefault(alias, key)


def bake_external(args: argparse.Namespace, manifest: dict[str, Any], report: dict[str, Any]) -> None:
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
        append_entry(manifest, entry)
        report["externalEntries"] += 1
        report["externalExpressions"] += len(entry["expressions"])


def bake_internal(args: argparse.Namespace, manifest: dict[str, Any], report: dict[str, Any]) -> None:
    project_root = Path(args.project_root)
    ffdec = Path(args.ffdec)
    ui_dir = project_root / "flashswf" / "UI" / "对话框界面"
    library_dir = ui_dir / "LIBRARY"
    portrait_xml = library_dir / "对话框肖像.xml"
    swf = project_root / "flashswf" / "UI" / "对话框界面.swf"
    tmp_base = Path(args.tmp_dir) / "internal"
    print("[internal] 对话框肖像")
    frame_dir = export_internal_sprite(ffdec, project_root, swf, tmp_base / "sprite", args.zoom, args.ffdec_timeout_seconds)
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
            )
        if entry["expressions"]:
            append_entry(manifest, entry)
            report["internalEntries"] += 1
            report["internalExpressions"] += len(entry["expressions"])


def main() -> None:
    args = parse_args()
    if args.external_only and args.internal_only:
        raise SystemExit("--external-only and --internal-only are mutually exclusive")
    project_root = Path(args.project_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    tmp_dir = Path(args.tmp_dir).resolve()
    if not Path(args.ffdec).exists():
        raise SystemExit(f"Missing FFDec CLI: {args.ffdec}")
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
        "entries": {},
        "aliases": {},
    }
    report: dict[str, Any] = {
        "externalEntries": 0,
        "externalExpressions": 0,
        "internalEntries": 0,
        "internalExpressions": 0,
        "missingExternalSwf": [],
        "missingFrames": [],
    }

    if not args.internal_only:
        bake_external(args, manifest, report)
    if not args.external_only:
        bake_internal(args, manifest, report)

    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report_path = output_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not args.keep_tmp and tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    print(json.dumps({"manifest": str(manifest_path.relative_to(project_root)), "report": report}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
