#!/usr/bin/env python3
"""Validate a map-production package structure without touching runtime data."""
from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TASKS = ROOT / "map-production" / "tasks.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("task_id")
    ap.add_argument("--strict", action="store_true", help="also require XFL/SWF files")
    args = ap.parse_args()

    data = json.loads(TASKS.read_text(encoding="utf-8"))
    task = next((t for t in data["tasks"] if t["id"] == args.task_id), None)
    if task is None:
        print(f"unknown task: {args.task_id}")
        return 2

    pkg = ROOT / task["packageDir"]
    errors: list[str] = []
    warnings: list[str] = []

    for name in ("design.md", "install.json", "manifest.json", "environment.proposal.xml"):
        if not (pkg / name).is_file():
            errors.append(f"missing {name}")

    install = {}
    if (pkg / "install.json").is_file():
        try:
            install = json.loads((pkg / "install.json").read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"install.json: {exc}")
        else:
            if install.get("taskId") != task["id"]:
                errors.append("install.json taskId mismatch")
            order = install.get("mapOrder") or []
            if len(order) != task["mapCount"]:
                errors.append(f"mapOrder count {len(order)} != mapCount {task['mapCount']}")
            if install.get("installMode") not in {"replace_existing_backgrounds", "new_stage_maps", "state_variant"}:
                errors.append("install.json installMode invalid")

    manifest = {}
    if (pkg / "manifest.json").is_file():
        try:
            manifest = json.loads((pkg / "manifest.json").read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"manifest.json: {exc}")
        else:
            maps = manifest.get("maps") or []
            if len(maps) != task["mapCount"]:
                errors.append(f"manifest maps count {len(maps)} != mapCount {task['mapCount']}")
            names = [m.get("name") for m in maps]
            install_order = [n.removesuffix(".swf") for n in (install.get("mapOrder") or [])]
            if names != install_order:
                errors.append("manifest map order/names differ from install.json")

    env = None
    if (pkg / "environment.proposal.xml").is_file():
        try:
            env = ET.parse(pkg / "environment.proposal.xml").getroot()
        except Exception as exc:
            errors.append(f"environment.proposal.xml: {exc}")
        else:
            entries = env.findall("Environment")
            order = install.get("mapOrder") or []
            if len(entries) != len(order):
                errors.append(f"environment entries {len(entries)} != mapOrder {len(order)}")
            seen = []
            for entry in entries:
                bg = entry.findtext("BackgroundURL")
                seen.append(bg)
                if bg not in order:
                    errors.append(f"environment BackgroundURL not in mapOrder: {bg}")
                for field in ("Width", "Height", "Xmin", "Xmax", "Ymin", "Ymax"):
                    if entry.findtext(field) is None:
                        warnings.append(f"{bg}: missing {field}")
            if len(seen) != len(set(seen)):
                errors.append("duplicate BackgroundURL in environment proposal")

    maps_dir = pkg / "maps"
    for map_name in install.get("mapOrder", []):
        swf = maps_dir / map_name
        xfl = maps_dir / map_name.removesuffix(".swf") / f"{map_name.removesuffix('.swf')}.xfl"
        if args.strict and not swf.is_file():
            errors.append(f"missing SWF: {swf.relative_to(ROOT)}")
        if args.strict and not xfl.is_file():
            errors.append(f"missing XFL: {xfl.relative_to(ROOT)}")
        dom = xfl.parent / "DOMDocument.xml"
        if dom.is_file():
            text = dom.read_text(encoding="utf-8", errors="ignore")
            if "_root.贴背景图();" not in text:
                errors.append(f"{map_name}: XFL missing _root.贴背景图();")
        elif args.strict:
            errors.append(f"missing XFL DOMDocument: {dom.relative_to(ROOT)}")

    print(f"task: {task['id']} {task['stage']} maps={task['mapCount']}")
    for w in warnings:
        print(f"WARN {w}")
    for e in errors:
        print(f"ERROR {e}")
    if errors:
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
