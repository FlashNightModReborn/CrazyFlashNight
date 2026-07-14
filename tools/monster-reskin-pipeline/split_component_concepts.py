#!/usr/bin/env python3
"""Split approved 4x4 component concept sheets into 13 labeled reference crops."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[2]
MANAGED_OUTPUT_ROOT = REPO_ROOT / "tmp" / "monster-reskin"
GRID_COLUMNS = 4
GRID_ROWS = 4


def repo_path(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else REPO_ROOT / path


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def require_within(path: Path, root: Path, label: str, allow_root: bool = False) -> Path:
    resolved = path.resolve()
    resolved_root = root.resolve()
    try:
        relative = resolved.relative_to(resolved_root)
    except ValueError as exc:
        raise ValueError(f"{label} 必须位于 {resolved_root} 下：{resolved}") from exc
    if not allow_root and not relative.parts:
        raise ValueError(f"{label} 不得直接指向受管根目录：{resolved_root}")
    return resolved


def cell_bounds(width: int, height: int, index: int) -> tuple[int, int, int, int]:
    column = index % GRID_COLUMNS
    row = index // GRID_COLUMNS
    return (
        round(column * width / GRID_COLUMNS),
        round(row * height / GRID_ROWS),
        round((column + 1) * width / GRID_COLUMNS),
        round((row + 1) * height / GRID_ROWS),
    )


def normal_parts(config: dict[str, Any]) -> list[dict[str, Any]]:
    parts = [part for part in config["parts"] if part.get("group", "normal-rig") == "normal-rig"]
    if len(parts) != 13:
        raise ValueError(f"组件概念板要求恰好 13 个 normal-rig 零件，当前为 {len(parts)}")
    return parts


def default_split_dir(concept_file: Path) -> Path:
    name = concept_file.stem.removesuffix("-13件组件参考")
    return concept_file.parent / "split" / name


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()

    config = load_json(repo_path(args.config))
    output = require_within(repo_path(config["outputDir"]), MANAGED_OUTPUT_ROOT, "outputDir")
    concepts = config.get("componentConcepts", [])
    if not concepts:
        raise ValueError("配置中没有 componentConcepts")
    parts = normal_parts(config)

    records: list[dict[str, Any]] = []
    for concept in concepts:
        sheet = require_within(output / concept["file"], output, "componentConcepts[].file", allow_root=False)
        if not sheet.exists():
            raise FileNotFoundError(f"缺少组件概念板：{sheet}")
        requested_split_dir = output / concept["splitDir"] if concept.get("splitDir") else default_split_dir(sheet)
        split_dir = require_within(requested_split_dir, output, "componentConcepts[].splitDir", allow_root=False)
        if args.check_only:
            continue
        split_dir.mkdir(parents=True, exist_ok=True)
        for stale in list(split_dir.glob("*.png")) + [split_dir / "manifest.json"]:
            if stale.exists():
                stale.unlink()
        with Image.open(sheet) as source:
            image = source.convert("RGB")
            crops: list[dict[str, Any]] = []
            for index, part in enumerate(parts):
                bounds = cell_bounds(image.width, image.height, index)
                filename = f"{index + 1:02d}_{part['characterId']}_{part['slug']}.png"
                image.crop(bounds).save(split_dir / filename, optimize=True)
                crops.append({
                    "characterId": part["characterId"],
                    "symbol": part.get("symbol", ""),
                    "label": part["label"],
                    "file": filename,
                    "crop": list(bounds),
                })
        record = {
            "variant": concept["variant"],
            "sourceSheet": concept["file"],
            "grid": {"columns": GRID_COLUMNS, "rows": GRID_ROWS},
            "parts": crops,
        }
        (split_dir / "manifest.json").write_text(
            json.dumps(record, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        records.append(record)

    if args.check_only:
        print(f"OK: {len(concepts)} component sheets / {len(parts)} parts each")
    else:
        print(f"OK: split {len(records)} component sheets / {len(parts)} parts each")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, FileNotFoundError, ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
