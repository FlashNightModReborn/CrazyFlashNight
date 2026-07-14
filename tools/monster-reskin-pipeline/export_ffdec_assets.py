#!/usr/bin/env python3
"""Read-only FFDec exporter for monster reskin reference packages."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
MANAGED_OUTPUT_ROOT = REPO_ROOT / "tmp" / "monster-reskin"


def repo_path(value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else REPO_ROOT / path


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def load_config(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    required = ["monster", "outputDir", "source", "export"]
    missing = [key for key in required if key not in config]
    if missing:
        raise ValueError(f"配置缺少字段：{', '.join(missing)}")
    for key in ["swf", "rootCharacterId"]:
        if key not in config["source"]:
            raise ValueError(f"source 缺少字段：{key}")
    return config


def safe_recreate(path: Path, staging: Path) -> None:
    resolved = path.resolve()
    root = staging.resolve()
    if resolved != root and root not in resolved.parents:
        raise ValueError(f"拒绝清理 staging 之外的目录：{resolved}")
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def require_safe_staging(path: Path) -> Path:
    resolved = path.resolve()
    root = MANAGED_OUTPUT_ROOT.resolve()
    try:
        relative = resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"export.stagingDir 必须位于 {root} 下：{resolved}") from exc
    if not relative.parts:
        raise ValueError(f"export.stagingDir 不得直接指向受管根目录：{root}")
    return resolved


def run_ffdec(ffdec: Path, swf: Path, output: Path, character_ids: list[int], kind: str, fmt: str, zoom: int) -> None:
    ids = ",".join(str(value) for value in character_ids)
    command = [
        str(ffdec),
        "-onerror", "abort",
        "-ignorebackground",
        "-zoom", str(zoom),
        "-selectid", ids,
        "-format", f"{kind}:{fmt}",
        "-export", kind,
        str(output),
        str(swf),
    ]
    result = subprocess.run(command, cwd=REPO_ROOT, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise RuntimeError(f"FFDec 导出失败（{kind}:{fmt}，ID={ids}，exit={result.returncode}）")


def find_frame_dir(root: Path, character_id: int) -> Path:
    candidates = sorted({path.parent for path in root.rglob("*.png") if path.stem.isdigit()})
    if not candidates:
        raise FileNotFoundError(f"未在 {root} 找到数字帧 PNG")
    exact = [path for path in candidates if path.name == str(character_id) or path.name.startswith(f"DefineSprite_{character_id}")]
    if len(exact) == 1:
        return exact[0]
    if len(candidates) == 1:
        return candidates[0]
    raise FileNotFoundError(f"无法唯一定位 character {character_id} 的帧目录：{candidates}")


def find_id_file(root: Path, character_id: int, suffix: str) -> Path:
    direct = root / f"{character_id}{suffix}"
    if direct.exists():
        return direct
    matches = sorted(root.rglob(f"{character_id}{suffix}"))
    if not matches:
        raise FileNotFoundError(f"未找到 character {character_id} 的 {suffix} 文件：{root}")
    return matches[0]


def svg_origin(svg_path: Path) -> dict[str, float] | None:
    text = svg_path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r'<g\s+transform="matrix\(([^)]+)\)"', text)
    if not match:
        return None
    values = [float(value.strip()) for value in match.group(1).split(",")]
    if len(values) != 6:
        return None
    return {"x": values[4], "y": values[5]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()

    config = load_config(repo_path(args.config))
    export = config["export"]
    source = config["source"]
    ffdec = repo_path(export.get("ffdec", "tools/ffdec/ffdec-cli.exe"))
    swf = repo_path(source["swf"])
    staging = require_safe_staging(repo_path(export["stagingDir"]))

    for path, label in [(ffdec, "FFDec"), (swf, "SWF")]:
        if not path.exists():
            raise FileNotFoundError(f"{label} 不存在：{path}")
    part_ids = [int(part["characterId"]) for part in config.get("parts", [])]
    if not part_ids:
        raise ValueError("parts 不能为空")
    configured_sequences = config.get("sequences", [])
    if configured_sequences:
        sequence_specs = configured_sequences
    else:
        sequence_specs = [{
            "slug": "root",
            "label": "root",
            "characterId": int(source["rootCharacterId"]),
        }]
    sequence_slugs = [item["slug"] for item in sequence_specs]
    if len(sequence_slugs) != len(set(sequence_slugs)):
        raise ValueError("sequences.slug 不得重复")
    sequence_ids = sorted({int(item["characterId"]) for item in sequence_specs})
    if any(character_id < 1 for character_id in sequence_ids):
        raise ValueError("sequences.characterId 必须是正整数")
    if args.check_only:
        print(f"OK: {config['monster']} / {len(sequence_specs)} sequences / {len(part_ids)} parts")
        return 0

    staging.mkdir(parents=True, exist_ok=True)
    sequences_png = staging / "sequences-png"
    parts_png = staging / "parts-png"
    parts_svg = staging / "parts-svg"
    for target in [sequences_png, parts_png, parts_svg]:
        safe_recreate(target, staging)

    run_ffdec(ffdec, swf, sequences_png, sequence_ids, "sprite", "png", int(export.get("rootZoom", 4)))
    run_ffdec(ffdec, swf, parts_png, part_ids, "shape", "png", int(export.get("partZoom", 8)))
    run_ffdec(ffdec, swf, parts_svg, part_ids, "shape", "svg", int(export.get("partZoom", 8)))

    manifest_sequences: list[dict[str, Any]] = []
    for sequence in sequence_specs:
        character_id = int(sequence["characterId"])
        frame_dir = find_frame_dir(sequences_png, character_id)
        manifest_sequences.append({
            "slug": sequence["slug"],
            "label": sequence.get("label", sequence["slug"]),
            "characterId": character_id,
            "frameDir": rel(frame_dir),
            "frameCount": len(list(frame_dir.glob("*.png"))),
        })

    manifest_parts: list[dict[str, Any]] = []
    for part in config["parts"]:
        character_id = int(part["characterId"])
        png = find_id_file(parts_png, character_id, ".png")
        svg = find_id_file(parts_svg, character_id, ".svg")
        origin = part.get("localOriginPx") or svg_origin(svg)
        manifest_parts.append({
            "slug": part["slug"],
            "characterId": character_id,
            "png": rel(png),
            "svg": rel(svg),
            "localOriginPx": origin,
        })

    manifest = {
        "schemaVersion": 2,
        "monster": config["monster"],
        "sourceSwf": rel(swf),
        "root": {
            "characterId": int(source["rootCharacterId"]),
        },
        "sequences": manifest_sequences,
        "parts": manifest_parts,
    }
    if len(manifest_sequences) == 1 and manifest_sequences[0]["slug"] == "root":
        manifest["root"].update({
            "frameDir": manifest_sequences[0]["frameDir"],
            "frameCount": manifest_sequences[0]["frameCount"],
        })
    manifest_path = staging / "export-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"OK: {manifest_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
