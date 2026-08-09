#!/usr/bin/env python3
"""Derive a compact view from atlas v4 with a dynamic human-label header."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from PIL import Image, ImageDraw, ImageFont


CONTROLLER_PATH = Path(__file__).resolve()
V1_CONTROLLER_PATH = CONTROLLER_PATH.with_name("derive-compact-model-atlas-v1.py")
ATLAS_V4_CONTROLLER_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas-v4.py")
SCHEMA = "cf7.portrait-pilot-model-atlas-retrieval.v2"
MODE = "all_pass_latest_adjustments_all_anomalies_from_atlas_v4"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


legacy = load_module(V1_CONTROLLER_PATH, "cf7_portrait_compact_atlas_v1")
atlas_v4 = load_module(ATLAS_V4_CONTROLLER_PATH, "cf7_portrait_feedback_atlas_v4")
base = legacy.base
ORIGINAL_DRAW = legacy.draw_compact_atlas


def draw_dynamic_label_header(
    output_path: Path,
    full_atlas_path: Path,
    font_path: Path,
    decisions: dict[str, dict[str, Any]],
    latest_adjustment_keys: list[str],
    feedback: dict[str, Any],
) -> dict[str, Any]:
    view = ORIGINAL_DRAW(
        output_path,
        full_atlas_path,
        font_path,
        decisions,
        latest_adjustment_keys,
        feedback,
    )
    label_count = len(decisions)
    header_text = (
        f"完整原始回执与 {label_count} 标签 atlas 仍由 manifest 哈希绑定；"
        "本图只压缩单次视觉输入，不改变人类裁决。"
    )
    with Image.open(output_path) as opened:
        canvas = opened.convert("RGB")
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((18, 48, canvas.width - 18, 91), fill="#172430")
    body_font = ImageFont.truetype(str(font_path), 17)
    draw.text((24, 56), header_text, font=body_font, fill="#9FE7DD")
    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    view["dynamicHumanLabelCount"] = label_count
    view["headerText"] = header_text
    return view


@contextmanager
def patched_legacy() -> Iterator[None]:
    original_controller = legacy.CONTROLLER_PATH
    original_schema = legacy.SCHEMA
    original_mode = legacy.MODE
    original_draw = legacy.draw_compact_atlas
    original_parent_verifier = legacy.v3.verify_derived
    try:
        legacy.CONTROLLER_PATH = CONTROLLER_PATH
        legacy.SCHEMA = SCHEMA
        legacy.MODE = MODE
        legacy.draw_compact_atlas = draw_dynamic_label_header
        legacy.v3.verify_derived = atlas_v4.verify_derived
        yield
    finally:
        legacy.CONTROLLER_PATH = original_controller
        legacy.SCHEMA = original_schema
        legacy.MODE = original_mode
        legacy.draw_compact_atlas = original_draw
        legacy.v3.verify_derived = original_parent_verifier


def rebind_dependencies(manifest_path: Path) -> dict[str, Any]:
    manifest = base.load_json(manifest_path, "compact model atlas v2 manifest")
    retrieval = manifest.get("humanPreferenceCalibration", {}).get("modelAtlasRetrieval")
    if not isinstance(retrieval, dict):
        raise base.AtlasError("compact model atlas v2 缺 retrieval")
    label_count = int(retrieval.get("allHumanLabelCount", 0))
    retrieval["baseControllerSource"] = base.artifact(V1_CONTROLLER_PATH)
    retrieval["parentAtlasControllerSource"] = base.artifact(ATLAS_V4_CONTROLLER_PATH)
    retrieval["dynamicHumanLabelCount"] = label_count
    retrieval["headerText"] = (
        f"完整原始回执与 {label_count} 标签 atlas 仍由 manifest 哈希绑定；"
        "本图只压缩单次视觉输入，不改变人类裁决。"
    )
    retrieval["gates"]["dynamicHumanLabelHeader"] = True

    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (V1_CONTROLLER_PATH, ATLAS_V4_CONTROLLER_PATH):
        record = base.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceEnvelope"]["humanPreferenceCalibration"] = manifest["humanPreferenceCalibration"]
    manifest["sourceDigest"] = base.sha256_bytes(base.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = base.sha256_bytes(base.stable_bytes(manifest))
    base.write_json(manifest_path, manifest)
    return manifest


def verify_compact_v2(manifest_path: Path) -> dict[str, Any]:
    captured = io.StringIO()
    with patched_legacy(), contextlib.redirect_stdout(captured):
        result = legacy.verify_compact(manifest_path)
    manifest = base.load_json(manifest_path, "compact model atlas v2 manifest")
    retrieval = manifest.get("humanPreferenceCalibration", {}).get("modelAtlasRetrieval", {})
    parent_path = base.verify_artifact(retrieval.get("parentManifest"), "compact parent atlas v4 manifest")
    atlas_v4.verify_derived(parent_path)
    expected_base = base.artifact(V1_CONTROLLER_PATH)
    expected_parent_controller = base.artifact(ATLAS_V4_CONTROLLER_PATH)
    expected_controller = base.artifact(CONTROLLER_PATH)
    label_count = int(retrieval.get("allHumanLabelCount", 0))
    expected_header = (
        f"完整原始回执与 {label_count} 标签 atlas 仍由 manifest 哈希绑定；"
        "本图只压缩单次视觉输入，不改变人类裁决。"
    )
    if (
        retrieval.get("controllerSource") != expected_controller
        or retrieval.get("baseControllerSource") != expected_base
        or retrieval.get("parentAtlasControllerSource") != expected_parent_controller
        or retrieval.get("dynamicHumanLabelCount") != label_count
        or retrieval.get("headerText") != expected_header
        or retrieval.get("gates", {}).get("dynamicHumanLabelHeader") is not True
    ):
        raise base.AtlasError("compact model atlas v2 controller/header 绑定不闭合")
    result["status"] = "compact_model_atlas_v2_verified"
    result["dynamicHumanLabelCount"] = label_count
    return result


def derive(args: argparse.Namespace) -> None:
    with patched_legacy(), contextlib.redirect_stdout(io.StringIO()):
        legacy.derive(args)
    manifest_path = Path(args.output).resolve() / "candidate-manifest.json"
    rebind_dependencies(manifest_path)
    print(json.dumps(verify_compact_v2(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(
        json.dumps(
            verify_compact_v2(base.repo_path(args.manifest, "compact model atlas v2 manifest")),
            ensure_ascii=False,
        )
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    derive_parser = commands.add_parser("derive")
    derive_parser.add_argument("--manifest", required=True)
    derive_parser.add_argument("--latest-human-review-receipt", required=True)
    derive_parser.add_argument("--output", required=True)
    derive_parser.add_argument("--batch-id", required=True)
    derive_parser.set_defaults(handler=derive)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--manifest", required=True)
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (base.AtlasError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"compact model atlas v2 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
