#!/usr/bin/env python3
"""Build and verify the post-human orientation pack without touching production."""

from __future__ import annotations

import argparse
import collections
import copy
import importlib.util
import io
import json
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
CONTROLLER = Path(__file__).with_name("promote-enemy-portraits-v1.py")


class PreflightError(RuntimeError):
    pass


def load_controller() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_orientation_promotion_preflight", CONTROLLER)
    if spec is None or spec.loader is None:
        raise PreflightError("无法加载通用头像 promotion controller")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


E = load_controller()
T = E.T


def output_path(value: str) -> Path:
    resolved = (ROOT / value).resolve()
    try:
        relative = resolved.relative_to(PILOT_ROOT.resolve())
    except ValueError as error:
        raise PreflightError("预演输出必须位于 tmp/portrait-pilot") from error
    if not relative.parts or resolved.exists():
        raise PreflightError("预演输出为空或已存在，拒绝覆盖")
    return resolved


def mirror_png(path: Path) -> bytes:
    with Image.open(path) as opened:
        image = opened.convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        stream = io.BytesIO()
        image.save(stream, format="PNG", optimize=False, compress_level=9)
        return stream.getvalue()


def source_asset(record: dict[str, Any]) -> Path:
    url = record.get("url")
    if not isinstance(url, str) or not url.startswith("assets/enemy-portraits/"):
        raise PreflightError(f"源生产资产 URL 非法：{url}")
    return T.WEB_ROOT / url


def staged_asset(staging: Path, record: dict[str, Any]) -> Path:
    url = record.get("url")
    if not isinstance(url, str):
        raise PreflightError("预演资产 URL 非法")
    return staging / "subjects" / Path(url).name


def run(output: Path) -> dict[str, Any]:
    output.mkdir(parents=True)
    manifest = E.build_pack(
        T.DEFAULT_INVENTORY,
        E.DEFAULT_CAMPAIGN,
        T.DEFAULT_REPRESENTATIVE_CLOSURE,
        T.DEFAULT_TEAM_GAP_BATCH,
        output,
    )
    if T.manifest_digest(manifest) != manifest.get("manifestDigest"):
        raise PreflightError("预演 manifestDigest 漂移")
    closure = E.load_orientation_closure()
    source_manifest = T.load_json(
        T.verify_artifact_record(
            closure["receipt"]["inputs"]["sourceProductionManifest"], "方向审计源生产 manifest"
        ),
        "方向审计源生产 manifest",
    )
    decisions = closure["humanByKey"]
    orientation_counts: collections.Counter[str] = collections.Counter()
    historical_asset_bindings = 0
    historical_asset_files: set[str] = set()
    unchanged = 0
    mirrored = 0
    accepted = 0
    final_flip_keys: list[str] = []
    for portrait_ref, entry in manifest["entries"].items():
        for variant_key, variant in entry["variants"].items():
            if variant.get("status") != "human_accepted":
                continue
            accepted += 1
            review_key = f"{portrait_ref}::{variant_key}"
            source_variant = source_manifest["entries"][portrait_ref]["variants"][variant_key]
            current_action = source_variant["provenance"]["orientationAction"]
            final_action = variant["provenance"]["orientationAction"]
            orientation_counts[variant["provenance"]["orientationSource"]] += 1
            if final_action == "flip_x":
                final_flip_keys.append(review_key)
            for kind in ("svg", "pngFallback"):
                record = variant["subject"][kind]
                path = staged_asset(output, record)
                if (
                    not path.is_file()
                    or path.stat().st_size != record.get("bytes")
                    or T.sha256_file(path) != record.get("sha256")
                ):
                    raise PreflightError(f"预演资产闭包漂移：{review_key}/{kind}")
            decision = decisions.get(review_key)
            if decision is not None and decision["action"] == "flip_x":
                expected_action = "keep" if current_action == "flip_x" else "flip_x"
                if final_action != expected_action:
                    raise PreflightError(f"真人相对 flip 未切换最终动作：{review_key}")
                source_png = source_asset(source_variant["subject"]["pngFallback"])
                actual_png = staged_asset(output, variant["subject"]["pngFallback"]).read_bytes()
                if actual_png != mirror_png(source_png):
                    raise PreflightError(f"真人相对 flip 的 PNG 不是当前生产像素精确镜像：{review_key}")
                mirrored += 1
            else:
                if final_action != current_action:
                    raise PreflightError(f"keep/model-keep 意外改变方向：{review_key}")
                if (
                    variant["subject"]["pngFallback"]["sha256"]
                    != source_variant["subject"]["pngFallback"]["sha256"]
                ):
                    raise PreflightError(f"keep/model-keep 意外改变 PNG 主体哈希：{review_key}")
                if variant["subject"]["svg"]["sha256"] != source_variant["subject"]["svg"]["sha256"]:
                    source_svg = T.verify_artifact_record(
                        variant["provenance"].get("sourceVectorFrame"),
                        f"兼容变换源 SVG {review_key}",
                    )
                    expected_svg = T.build_cropped_svg(
                        source_svg,
                        variant["subject"]["svg"]["viewBox"],
                        variant["subject"]["svg"].get("flipX") is True,
                    )
                    actual_svg = staged_asset(output, variant["subject"]["svg"]).read_bytes()
                    transforms = variant["subject"]["svg"].get("compatibilityTransforms", [])
                    if (
                        actual_svg != expected_svg
                        or not transforms
                        or any(row.get("kind") != "strip_empty_ffdec_filters" for row in transforms)
                        or variant["provenance"].get("svgCompatibilityTransform")
                        != "strip_empty_ffdec_filters"
                    ):
                        raise PreflightError(f"keep/model-keep SVG 改变未被兼容变换精确解释：{review_key}")
                unchanged += 1

    for portrait_ref, entry in source_manifest["entries"].items():
        for variant_key, variant in entry["variants"].items():
            if variant.get("status") != "human_accepted":
                continue
            review_key = f"{portrait_ref}::{variant_key}"
            for kind in ("svg", "pngFallback"):
                record = variant["subject"][kind]
                path = staged_asset(output, record)
                if (
                    not path.is_file()
                    or path.stat().st_size != record.get("bytes")
                    or T.sha256_file(path) != record.get("sha256")
                ):
                    raise PreflightError(f"历史审计源资产未被新包保留：{review_key}/{kind}")
                historical_asset_bindings += 1
                historical_asset_files.add(record["sha256"])

    if (
        accepted != 217
        or mirrored != 5
        or unchanged != 212
        or historical_asset_bindings != 434
        or len(historical_asset_files) != 432
        or orientation_counts
        != collections.Counter({E.MODEL_ORIENTATION_SOURCE: 178, E.HUMAN_ORIENTATION_SOURCE: 39})
    ):
        raise PreflightError(
            f"预演 217/178/39/5/212 计数漂移：accepted={accepted} mirrored={mirrored} "
            f"unchanged={unchanged} historical={historical_asset_bindings}/{len(historical_asset_files)} "
            f"sources={dict(orientation_counts)}"
        )
    expected_team_flips = T.EXPECTED_FLIPPED_VARIANTS.symmetric_difference(T.ORIENTATION_AUDIT_TEAM_TOGGLES)
    team_refs = {
        item["portraitRef"]
        for item in T.load_json(T.DEFAULT_INVENTORY, "portrait inventory").get("items", [])
        if (item.get("consumers") or {}).get("petIds")
    }
    actual_team_flips = {key for key in final_flip_keys if key.split("::", 1)[0] in team_refs}
    if actual_team_flips != expected_team_flips:
        raise PreflightError("预演 Team 最终方向集合漂移")
    receipt_path = output / "promotion-receipt.json"
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PreflightError(f"预演 promotion receipt 不可读：{error}") from error
    if not isinstance(receipt, dict):
        raise PreflightError("预演 promotion receipt 顶层必须是对象")
    clone = copy.deepcopy(receipt)
    receipt_digest = clone.pop("receiptDigest", None)
    if T.sha256_bytes(T.stable_bytes(clone)) != receipt_digest:
        raise PreflightError("预演 promotion receiptDigest 漂移")
    return {
        "status": "orientation_promotion_preflight_verified",
        "manifestDigest": manifest["manifestDigest"],
        "accepted": accepted,
        "orientationUnchangedVariants": unchanged,
        "exactMirroredPngs": mirrored,
        "preservedHistoricalAssetBindings": historical_asset_bindings,
        "preservedHistoricalSubjectFiles": len(historical_asset_files),
        "orientationSources": dict(sorted(orientation_counts.items())),
        "humanFlipReviewKeys": closure["receipt"]["flipReviewKeys"],
        "finalTeamFlipCount": len(actual_team_flips),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        result = run(output_path(args.output))
    except (PreflightError, T.PromotionError, OSError, ValueError, KeyError) as error:
        print(f"[orientation-promotion-preflight] ERROR: {error}")
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
