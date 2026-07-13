#!/usr/bin/env python3
"""Trace symbol dependencies in an uncompressed XFL library without modifying it."""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any
from urllib.parse import unquote


NS = {"x": "http://ns.adobe.com/xfl/2008/"}
REPO_ROOT = Path(__file__).resolve().parents[2]


def repo_path(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else REPO_ROOT / path


def symbol_file(library: Path, name: str) -> Path:
    return library / (unquote(name) + ".xml")


def matrix(instance: ET.Element) -> dict[str, float]:
    node = instance.find("x:matrix/x:Matrix", NS)
    if node is None:
        return {"a": 1.0, "b": 0.0, "c": 0.0, "d": 1.0, "tx": 0.0, "ty": 0.0}
    return {key: float(node.get(key, default)) for key, default in {
        "a": "1", "b": "0", "c": "0", "d": "1", "tx": "0", "ty": "0"
    }.items()}


def inspect_symbol(library: Path, name: str) -> dict[str, Any]:
    path = symbol_file(library, name)
    if not path.exists():
        return {"name": name, "file": None, "missing": True, "instances": []}
    root = ET.parse(path).getroot()
    instances: list[dict[str, Any]] = []
    for layer_index, layer in enumerate(root.findall(".//x:DOMLayer", NS)):
        layer_name = layer.get("name", f"Layer {layer_index + 1}")
        for frame in layer.findall("x:frames/x:DOMFrame", NS):
            frame_index = int(frame.get("index", "0"))
            duration = int(frame.get("duration", "1"))
            for instance in frame.findall("x:elements/x:DOMSymbolInstance", NS):
                child = instance.get("libraryItemName")
                if child:
                    instances.append({
                        "symbol": child,
                        "layer": layer_name,
                        "frame": frame_index,
                        "duration": duration,
                        "matrix": matrix(instance),
                    })
    return {
        "name": name,
        "file": path.relative_to(REPO_ROOT).as_posix() if REPO_ROOT in path.parents else str(path),
        "missing": False,
        "shapeCount": len(root.findall(".//x:DOMShape", NS)),
        "frameCount": max((int(node.get("index", "0")) + int(node.get("duration", "1")) for node in root.findall(".//x:DOMFrame", NS)), default=0),
        "instances": instances,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xfl", required=True, type=Path)
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    xfl = repo_path(args.xfl)
    library = xfl.parent / "LIBRARY"
    if not xfl.exists() or not library.is_dir():
        raise FileNotFoundError(f"无效 XFL 或缺少 LIBRARY：{xfl}")

    queue = [args.symbol]
    seen: set[str] = set()
    symbols: list[dict[str, Any]] = []
    while queue:
        name = queue.pop(0)
        if name in seen:
            continue
        seen.add(name)
        record = inspect_symbol(library, name)
        symbols.append(record)
        for instance in record["instances"]:
            child = instance["symbol"]
            if child not in seen and symbol_file(library, child).exists():
                queue.append(child)

    result = {
        "schemaVersion": 1,
        "xfl": xfl.relative_to(REPO_ROOT).as_posix() if REPO_ROOT in xfl.parents else str(xfl),
        "rootSymbol": args.symbol,
        "symbolCount": len(symbols),
        "symbols": symbols,
    }
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        output = repo_path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
        print(f"OK: {output} ({len(symbols)} symbols)")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ET.ParseError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
