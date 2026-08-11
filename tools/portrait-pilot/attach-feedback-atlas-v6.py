#!/usr/bin/env python3
"""Attach all 168 current human labels, including the two resolved r125 negatives."""

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

from PIL import Image, ImageDraw, ImageFont, ImageOps


CONTROLLER_PATH = Path(__file__).resolve()
V5_CONTROLLER_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas-v5.py")
RESOLUTION_CONTROLLER_PATH = CONTROLLER_PATH.with_name("build-human-review-resolution-snapshot-v1.py")
SCHEMA = "cf7.portrait-pilot-human-preference-atlas.v6"
MODE = "bound_168_current_human_labels_with_three_negative_followups_and_controlled_fast6"
FEEDBACK_SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v6"
EXPECTED_STATUS_COUNTS = {"pass": 58, "adjustment": 109, "source": 1}


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


v5 = load_module(V5_CONTROLLER_PATH, "cf7_portrait_feedback_atlas_v5_for_v6")
resolution_controller = load_module(
    RESOLUTION_CONTROLLER_PATH, "cf7_portrait_human_review_resolution_snapshot_v1_for_atlas_v6"
)
v4 = v5.v4
base = v5.base
CURRENT_RESOLUTION: tuple[Path, dict[str, Any]] | None = None
CURRENT_RESOLUTION_PANEL_PATH: Path | None = None
ORIGINAL_V5_BUILD_ATLAS = v5.build_atlas_with_supersession


def verify_feedback_v6(feedback: dict[str, Any], effective_shard_size: int) -> dict[str, Any]:
    base.verify_digest(feedback, "feedbackDigest", "feedback v5 report")
    scaling = feedback.get("adaptiveScaling", {})
    profile = scaling.get("executionProfile", {})
    override = scaling.get("humanScaleOverride", {})
    pilot = scaling.get("concurrencyPilot", {})
    if (
        feedback.get("schema") != FEEDBACK_SCHEMA
        or feedback.get("status") != "human_feedback_calibrated"
        or feedback.get("productionReady") is not False
        or scaling.get("recommendedNextShardSize") != 48
        or scaling.get("recommendedSourceGroups") != 12
        or scaling.get("modelItemsPerGroup") != 4
        or scaling.get("maximumConcurrency") != 6
        or profile.get("model") != "Luna Max"
        or profile.get("serviceTier") != "fast"
        or profile.get("maximumConcurrency") != 6
        or profile.get("timeoutSeconds") != 600
        or profile.get("fallbackMaximumConcurrency") != 3
        or pilot.get("policy") != "bounded_fast6_with_fail_closed_fallback_v1"
        or pilot.get("qualityGatesUnchanged") is not True
        or feedback.get("geometryCalibration", {}).get("cumulativeRowCount") != 105
        or len(feedback.get("geometryCalibration", {}).get("rows", [])) != 105
        or feedback.get("gates", {}).get("allHistoricalGeometryRowsBound") is not True
        or override.get("active") is not True
        or override.get("targetShardSize") != 48
        or override.get("targetSourceGroups") != 12
        or not 4 <= effective_shard_size < 48
    ):
        raise base.AtlasError("feedback v5 Fast6 或 48→tail availability clamp 没有闭合")
    return scaling


def row_for(report: dict[str, Any], field: str, review_key: str) -> dict[str, Any]:
    rows = report.get(field, {}).get(review_key, [])
    matches = [row for row in rows if row.get("role") == "independent_review"]
    if len(matches) != 1:
        raise base.AtlasError(f"resolution {field} 缺唯一 independent_review：{review_key}")
    return matches[0]


def draw_tile(
    canvas: Image.Image,
    draw: ImageDraw.ImageDraw,
    record: dict[str, Any],
    box: tuple[int, int, int, int],
    label: str,
    font: ImageFont.FreeTypeFont,
) -> None:
    path = base.verify_artifact(record, f"resolution panel {label}")
    left, top, right, bottom = box
    draw.rounded_rectangle(box, radius=16, fill="#18242D", outline="#4D6978", width=2)
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    contained = ImageOps.contain(image, (right - left - 24, bottom - top - 54), method=Image.Resampling.LANCZOS)
    tile = Image.new("RGBA", contained.size, (15, 23, 29, 255))
    tile.alpha_composite(contained)
    canvas.paste(tile.convert("RGB"), (left + (right - left - contained.width) // 2, top + 42), tile)
    draw.text((left + 14, top + 10), label, font=font, fill="#E9F3F5")


def build_resolution_panel(
    output_path: Path,
    width: int,
    font_path: Path,
    report: dict[str, Any],
) -> dict[str, Any]:
    height = 810
    canvas = Image.new("RGB", (width, height), "#0E171D")
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(str(font_path), 28)
    body_font = ImageFont.truetype(str(font_path), 18)
    small_font = ImageFont.truetype(str(font_path), 16)
    draw.rectangle((0, 0, width, 62), fill="#142732")
    draw.text((24, 15), "真人纠错闭环：双子构图与黑底转透明", font=title_font, fill="#A7F0E4")
    keys = ["敌人-黑白无常::default", "敌人-迷你黑洞::default"]
    labels = ["黑白无常：frame 1 → 血腥死 frame 249 + 反转", "迷你黑洞：黑底污染 → gamma 0.75 透明通道"]
    tile_width = min(430, (width - 230) // 2)
    for index, (review_key, row_label) in enumerate(zip(keys, labels)):
        top = 82 + index * 350
        draw.text((24, top), row_label, font=body_font, fill="#F0C674")
        old_box = (70, top + 42, 70 + tile_width, top + 320)
        new_box = (width - 70 - tile_width, top + 42, width - 70, top + 320)
        draw_tile(canvas, draw, row_for(report, "supersededRows", review_key)["master"], old_box, "旧结果（负例）", body_font)
        draw_tile(canvas, draw, row_for(report, "resolvedRows", review_key)["master"], new_box, "真人最终结果（正例）", body_font)
        draw.text((width // 2 - 18, top + 164), "→", font=title_font, fill="#63D7C5")
    draw.text(
        (24, 777),
        "训练声明：无。该面板仅作为本轮 Luna 的确定性偏好上下文，真人回执仍是唯一决定来源。",
        font=small_font,
        fill="#90A7B2",
    )
    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    return {"artifact": base.artifact(output_path), "dimensions": [width, height]}


def build_atlas_v6(
    output_path: Path,
    font_path: Path,
    decisions: dict[str, dict[str, Any]],
    initial: dict[tuple[str, str], dict[str, Any]],
    guided: dict[str, dict[str, Any]],
    orientation_only: dict[str, dict[str, Any]],
    guided_orientation: dict[str, dict[str, Any]],
    feedback: dict[str, Any],
) -> dict[str, Any]:
    global CURRENT_RESOLUTION_PANEL_PATH
    if CURRENT_RESOLUTION is None:
        raise base.AtlasError("attach v6 缺 resolution snapshot")
    coverage = ORIGINAL_V5_BUILD_ATLAS(
        output_path,
        font_path,
        decisions,
        initial,
        guided,
        orientation_only,
        guided_orientation,
        feedback,
    )
    _resolution_path, report = CURRENT_RESOLUTION
    with Image.open(output_path) as opened:
        atlas = opened.convert("RGB")
    panel_path = output_path.parent / "resolved-r125-two-anomalies-preference-panel.png"
    panel = build_resolution_panel(panel_path, atlas.width, font_path, report)
    with Image.open(panel_path) as opened:
        panel_image = opened.convert("RGB")
    combined = Image.new("RGB", (atlas.width, atlas.height + panel_image.height), "#0E171D")
    combined.paste(atlas, (0, 0))
    combined.paste(panel_image, (0, atlas.height))
    combined.save(output_path, format="PNG", optimize=False, compress_level=9)
    CURRENT_RESOLUTION_PANEL_PATH = panel_path
    coverage["dimensions"] = [combined.width, combined.height]
    coverage["supersededDecisionEvidenceCount"] = 3
    coverage["resolvedR125NegativeEvidenceCount"] = 2
    coverage["resolutionPanelDimensions"] = panel["dimensions"]
    coverage["latestResolvedStateVisualized"] = True
    coverage["all168CurrentHumanLabelsVisualized"] = coverage.get("decisionCount") == 168
    return coverage


@contextmanager
def patched_v5() -> Iterator[None]:
    originals = {
        "controller": v5.CONTROLLER_PATH,
        "schema": v5.SCHEMA,
        "mode": v5.MODE,
        "feedback_schema": v5.FEEDBACK_SCHEMA,
        "verify_feedback": v5.verify_feedback_v5,
        "build_atlas": v5.build_atlas_with_supersession,
        "verify_v5": v5.verify_v5,
        "maximum_concurrency": v4.MAXIMUM_CONCURRENCY,
    }
    try:
        v5.CONTROLLER_PATH = CONTROLLER_PATH
        v5.SCHEMA = SCHEMA
        v5.MODE = MODE
        v5.FEEDBACK_SCHEMA = FEEDBACK_SCHEMA
        v5.verify_feedback_v5 = verify_feedback_v6
        v5.build_atlas_with_supersession = build_atlas_v6
        v5.verify_v5 = lambda _manifest_path: {"status": "atlas_v6_rebind_pending"}
        v4.MAXIMUM_CONCURRENCY = 6
        yield
    finally:
        v5.CONTROLLER_PATH = originals["controller"]
        v5.SCHEMA = originals["schema"]
        v5.MODE = originals["mode"]
        v5.FEEDBACK_SCHEMA = originals["feedback_schema"]
        v5.verify_feedback_v5 = originals["verify_feedback"]
        v5.build_atlas_with_supersession = originals["build_atlas"]
        v5.verify_v5 = originals["verify_v5"]
        v4.MAXIMUM_CONCURRENCY = originals["maximum_concurrency"]


def rebind_v6(manifest_path: Path, resolution_path: Path) -> None:
    if CURRENT_RESOLUTION_PANEL_PATH is None:
        raise base.AtlasError("attach v6 没有生成 r125 resolution panel")
    manifest = base.load_json(manifest_path, "atlas v6 manifest")
    calibration = manifest.get("humanPreferenceCalibration")
    if not isinstance(calibration, dict):
        raise base.AtlasError("atlas v6 manifest 缺 humanPreferenceCalibration")
    calibration["v5ControllerSource"] = base.artifact(V5_CONTROLLER_PATH)
    calibration["resolutionControllerSource"] = base.artifact(RESOLUTION_CONTROLLER_PATH)
    calibration["resolutionReport"] = base.artifact(resolution_path)
    calibration["resolvedR125FeedbackPanel"] = base.artifact(CURRENT_RESOLUTION_PANEL_PATH)
    calibration["gates"].update(
        {
            "all168CurrentHumanLabelsVisualized": True,
            "threeSupersededNegativeExamplesPreserved": True,
            "resolvedR125HumanFeedbackVisualized": True,
            "controlledFast6Bound": True,
            "fast3FallbackBound": True,
        }
    )
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (
        V5_CONTROLLER_PATH,
        RESOLUTION_CONTROLLER_PATH,
        resolution_path,
        CURRENT_RESOLUTION_PANEL_PATH,
    ):
        record = base.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])
    manifest["campaign"]["modelRecommendation"] = "Luna Max"
    manifest["campaign"]["serviceTierRecommendation"] = "fast"
    manifest["campaign"]["maxConcurrencyRecommendation"] = 6
    manifest["campaign"]["fallbackConcurrencyRecommendation"] = 3
    manifest["campaign"]["timeoutSecondsRecommendation"] = 600
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceEnvelope"]["humanPreferenceCalibration"] = calibration
    manifest["humanPreferenceCalibration"] = calibration
    manifest["sourceDigest"] = base.sha256_bytes(base.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = base.sha256_bytes(base.stable_bytes(manifest))
    base.write_json(manifest_path, manifest)


def verify_v6(manifest_path: Path) -> dict[str, Any]:
    with patched_v5(), v5.patched_v4(), contextlib.redirect_stdout(io.StringIO()):
        inherited = v4.verify_derived(manifest_path)
    manifest = base.load_json(manifest_path, "atlas v6 manifest")
    calibration = manifest.get("humanPreferenceCalibration", {})
    coverage = calibration.get("coverage", {})
    gates = calibration.get("gates", {})
    if (
        calibration.get("schema") != SCHEMA
        or calibration.get("mode") != MODE
        or calibration.get("v5ControllerSource") != base.artifact(V5_CONTROLLER_PATH)
        or calibration.get("resolutionControllerSource") != base.artifact(RESOLUTION_CONTROLLER_PATH)
        or coverage.get("decisionCount") != 168
        or coverage.get("statusCounts") != EXPECTED_STATUS_COUNTS
        or coverage.get("passAnchorCount") != 58
        or coverage.get("adjustmentCount") != 109
        or coverage.get("anomalyCount") != 1
        or coverage.get("supersededDecisionEvidenceCount") != 3
        or coverage.get("resolvedR125NegativeEvidenceCount") != 2
        or coverage.get("all168CurrentHumanLabelsVisualized") is not True
        or gates.get("all168CurrentHumanLabelsVisualized") is not True
        or gates.get("threeSupersededNegativeExamplesPreserved") is not True
        or gates.get("resolvedR125HumanFeedbackVisualized") is not True
        or gates.get("controlledFast6Bound") is not True
        or gates.get("fast3FallbackBound") is not True
    ):
        raise base.AtlasError("atlas v6 168-label / negative-evidence gate 非法")
    resolution_path = base.verify_artifact(calibration.get("resolutionReport"), "r125 resolution report")
    resolution = base.load_json(resolution_path, "r125 resolution report")
    resolution_controller.verify_report(resolution_path)
    panel_path = base.verify_artifact(calibration.get("resolvedR125FeedbackPanel"), "r125 resolution panel")
    with Image.open(panel_path) as panel:
        if list(panel.size) != coverage.get("resolutionPanelDimensions"):
            raise base.AtlasError("r125 resolution panel 尺寸漂移")
    if resolution.get("snapshotReceipt") not in calibration.get("humanReviewReceipts", []):
        raise base.AtlasError("r140 snapshot receipt 未进入 168-label 决定闭包")
    if resolution.get("snapshotRenderReport") not in calibration.get("parentRenderReports", []):
        raise base.AtlasError("r140 snapshot render 未进入 168-label 像素闭包")
    scaling = calibration.get("adaptiveScaling", {})
    campaign = manifest.get("campaign", {})
    if (
        scaling.get("maximumConcurrency") != 6
        or scaling.get("executionProfile", {}).get("fallbackMaximumConcurrency") != 3
        or campaign.get("maxConcurrencyRecommendation") != 6
        or campaign.get("fallbackConcurrencyRecommendation") != 3
        or campaign.get("timeoutSecondsRecommendation") != 600
    ):
        raise base.AtlasError("atlas v6 Fast6/Fast3 fallback 执行闭包非法")
    return {
        **inherited,
        "status": "campaign_human_preference_atlas_v6_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "humanLabels": 168,
        "passes": 58,
        "adjustments": 109,
        "sourceAnomalies": 1,
        "supersededNegativeExamples": 3,
        "maximumConcurrency": 6,
        "fallbackMaximumConcurrency": 3,
        "productionReady": False,
    }


def attach(args: argparse.Namespace) -> None:
    global CURRENT_RESOLUTION, CURRENT_RESOLUTION_PANEL_PATH
    resolution_path = base.repo_path(args.resolution_report, "resolution snapshot report")
    resolution_controller.verify_report(resolution_path)
    resolution = base.load_json(resolution_path, "resolution snapshot report")
    CURRENT_RESOLUTION = (resolution_path, resolution)
    CURRENT_RESOLUTION_PANEL_PATH = None
    with patched_v5(), contextlib.redirect_stdout(io.StringIO()):
        v5.attach(args)
    manifest_path = base.repo_path(args.output, "atlas v6 output") / "candidate-manifest.json"
    rebind_v6(manifest_path, resolution_path)
    print(json.dumps(verify_v6(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_v6(base.repo_path(args.manifest, "atlas v6 manifest")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    attach_parser = commands.add_parser("attach")
    attach_parser.add_argument("--base-manifest", required=True)
    attach_parser.add_argument("--feedback-report", required=True)
    attach_parser.add_argument("--human-review-receipt", action="append", required=True)
    attach_parser.add_argument("--parent-render-report", action="append", required=True)
    attach_parser.add_argument("--guided-report", action="append", required=True)
    attach_parser.add_argument("--orientation-report", action="append", required=True)
    attach_parser.add_argument("--guided-orientation-report", action="append", required=True)
    attach_parser.add_argument("--supersession-report", required=True)
    attach_parser.add_argument("--resolution-report", required=True)
    attach_parser.add_argument("--output", required=True)
    attach_parser.add_argument("--batch-id", required=True)
    attach_parser.set_defaults(handler=attach)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--manifest", required=True)
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (base.AtlasError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"feedback atlas v6 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
