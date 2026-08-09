#!/usr/bin/env python3
"""Derive compact atlas v3 while retaining superseded follow-up negative evidence."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import math
import sys
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Iterator

from PIL import Image


CONTROLLER_PATH = Path(__file__).resolve()
V2_CONTROLLER_PATH = CONTROLLER_PATH.with_name("derive-compact-model-atlas-v2.py")
ATLAS_V5_CONTROLLER_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas-v5.py")
SCHEMA = "cf7.portrait-pilot-model-atlas-retrieval.v3"
MODE = "all_pass_latest_adjustments_all_anomalies_plus_superseded_followup_negative"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


v2 = load_module(V2_CONTROLLER_PATH, "cf7_portrait_compact_model_atlas_v2")
atlas_v5 = load_module(ATLAS_V5_CONTROLLER_PATH, "cf7_portrait_feedback_atlas_v5")
base = v2.base


def patch_count(dimensions: list[int]) -> int:
    return math.ceil(dimensions[0] / 32) * math.ceil(dimensions[1] / 32)


@contextmanager
def patched_v2() -> Iterator[None]:
    original_controller = v2.CONTROLLER_PATH
    original_schema = v2.SCHEMA
    original_mode = v2.MODE
    original_parent_controller_path = v2.ATLAS_V4_CONTROLLER_PATH
    original_parent_module = v2.atlas_v4
    try:
        v2.CONTROLLER_PATH = CONTROLLER_PATH
        v2.SCHEMA = SCHEMA
        v2.MODE = MODE
        v2.ATLAS_V4_CONTROLLER_PATH = ATLAS_V5_CONTROLLER_PATH
        v2.atlas_v4 = SimpleNamespace(verify_derived=atlas_v5.verify_v5)
        yield
    finally:
        v2.CONTROLLER_PATH = original_controller
        v2.SCHEMA = original_schema
        v2.MODE = original_mode
        v2.ATLAS_V4_CONTROLLER_PATH = original_parent_controller_path
        v2.atlas_v4 = original_parent_module


def append_superseded_panel(manifest_path: Path) -> None:
    manifest = base.load_json(manifest_path, "compact atlas v3 manifest")
    calibration = manifest.get("humanPreferenceCalibration")
    if not isinstance(calibration, dict):
        raise base.AtlasError("compact atlas v3 缺 humanPreferenceCalibration")
    retrieval = calibration.get("modelAtlasRetrieval")
    if not isinstance(retrieval, dict):
        raise base.AtlasError("compact atlas v3 缺 modelAtlasRetrieval")
    parent_path = base.verify_artifact(retrieval.get("parentManifest"), "compact parent atlas v5 manifest")
    parent = base.load_json(parent_path, "compact parent atlas v5 manifest")
    atlas_v5.verify_v5(parent_path)
    parent_calibration = parent.get("humanPreferenceCalibration", {})
    panel_record = parent_calibration.get("supersededFeedbackPanel")
    panel_path = base.verify_artifact(panel_record, "superseded feedback panel")
    compact_path = base.verify_artifact(calibration.get("modelAtlas"), "compact model atlas")

    with Image.open(compact_path) as opened:
        compact = opened.convert("RGB")
    with Image.open(panel_path) as opened:
        panel = opened.convert("RGB")
    if panel.width != compact.width:
        scaled_height = max(1, round(panel.height * compact.width / panel.width))
        panel = panel.resize((compact.width, scaled_height), Image.Resampling.LANCZOS)
    combined = Image.new("RGB", (compact.width, compact.height + panel.height), "#0E171D")
    combined.paste(compact, (0, 0))
    combined.paste(panel, (0, compact.height))
    combined.save(compact_path, format="PNG", optimize=False, compress_level=9)

    compact_dimensions = [combined.width, combined.height]
    full_dimensions = retrieval["fullAtlasDimensions"]
    full_patches = patch_count(full_dimensions)
    compact_patches = patch_count(compact_dimensions)
    if compact_patches >= full_patches:
        raise base.AtlasError("追加 superseded panel 后 compact atlas 不再严格减少视觉 patch")
    compact_record = base.artifact(compact_path)
    calibration["modelAtlas"] = compact_record
    retrieval["modelAtlasDimensions"] = compact_dimensions
    retrieval["fullAtlasPatchCount"] = full_patches
    retrieval["modelAtlasPatchCount"] = compact_patches
    retrieval["patchReductionFraction"] = round(1 - compact_patches / full_patches, 6)
    retrieval["v2ControllerSource"] = base.artifact(V2_CONTROLLER_PATH)
    retrieval["parentAtlasControllerSource"] = base.artifact(ATLAS_V5_CONTROLLER_PATH)
    retrieval["supersededFeedbackPanel"] = panel_record
    retrieval["supersededDecisionEvidenceCount"] = 1
    retrieval["gates"].update(
        {
            "supersededNegativeEvidenceIncluded": True,
            "latestResolvedStateIncluded": True,
        }
    )
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    source_files = [
        compact_record if record.get("path") == compact_record["path"] else record
        for record in source_files
    ]
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (V2_CONTROLLER_PATH, ATLAS_V5_CONTROLLER_PATH, panel_path):
        record = base.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceEnvelope"]["humanPreferenceCalibration"] = calibration
    manifest["humanPreferenceCalibration"] = calibration
    manifest["sourceDigest"] = base.sha256_bytes(base.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = base.sha256_bytes(base.stable_bytes(manifest))
    base.write_json(manifest_path, manifest)


def verify_v3(manifest_path: Path) -> dict[str, Any]:
    with patched_v2(), contextlib.redirect_stdout(io.StringIO()):
        inherited = v2.verify_compact_v2(manifest_path)
    manifest = base.load_json(manifest_path, "compact atlas v3 manifest")
    calibration = manifest.get("humanPreferenceCalibration", {})
    retrieval = calibration.get("modelAtlasRetrieval", {})
    gates = retrieval.get("gates", {})
    if (
        retrieval.get("schema") != SCHEMA
        or retrieval.get("mode") != MODE
        or retrieval.get("controllerSource") != base.artifact(CONTROLLER_PATH)
        or retrieval.get("v2ControllerSource") != base.artifact(V2_CONTROLLER_PATH)
        or retrieval.get("parentAtlasControllerSource") != base.artifact(ATLAS_V5_CONTROLLER_PATH)
        or retrieval.get("supersededDecisionEvidenceCount") != 1
        or gates.get("supersededNegativeEvidenceIncluded") is not True
        or gates.get("latestResolvedStateIncluded") is not True
    ):
        raise base.AtlasError("compact atlas v3 supersession gate 非法")
    parent_path = base.verify_artifact(retrieval.get("parentManifest"), "compact parent atlas v5 manifest")
    parent = base.load_json(parent_path, "compact parent atlas v5 manifest")
    atlas_v5.verify_v5(parent_path)
    if retrieval.get("supersededFeedbackPanel") != parent.get("humanPreferenceCalibration", {}).get(
        "supersededFeedbackPanel"
    ):
        raise base.AtlasError("compact atlas v3 superseded panel 与 parent 漂移")
    compact_path = base.verify_artifact(calibration.get("modelAtlas"), "compact model atlas")
    with Image.open(compact_path) as compact:
        if list(compact.size) != retrieval.get("modelAtlasDimensions"):
            raise base.AtlasError("compact atlas v3 尺寸漂移")
    return {
        **inherited,
        "status": "compact_model_atlas_v3_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "dynamicHumanLabelCount": retrieval["dynamicHumanLabelCount"],
        "supersededNegativeExamples": retrieval["supersededDecisionEvidenceCount"],
        "modelAtlasPatches": retrieval["modelAtlasPatchCount"],
        "patchReductionFraction": retrieval["patchReductionFraction"],
        "productionReady": False,
    }


def derive(args: argparse.Namespace) -> None:
    with patched_v2(), contextlib.redirect_stdout(io.StringIO()):
        v2.derive(args)
    manifest_path = base.repo_path(args.output, "compact atlas v3 output") / "candidate-manifest.json"
    append_superseded_panel(manifest_path)
    print(json.dumps(verify_v3(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_v3(base.repo_path(args.manifest, "compact atlas v3 manifest")), ensure_ascii=False))


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
    except (base.AtlasError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"compact model atlas v3 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
