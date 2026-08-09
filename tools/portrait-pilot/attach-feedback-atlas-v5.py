#!/usr/bin/env python3
"""Attach cumulative human feedback with resolved follow-up evidence and Fast3 scaling."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import sys
import textwrap
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from PIL import Image, ImageDraw, ImageFont, ImageOps


CONTROLLER_PATH = Path(__file__).resolve()
V4_CONTROLLER_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas-v4.py")
SUPERSESSION_CONTROLLER_PATH = CONTROLLER_PATH.with_name("build-human-review-supersession-v1.py")
SCHEMA = "cf7.portrait-pilot-human-preference-atlas.v5"
MODE = "bound_latest_human_state_with_superseded_negative_evidence_and_fast3_execution"
FEEDBACK_SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v4"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


v4 = load_module(V4_CONTROLLER_PATH, "cf7_portrait_feedback_atlas_v4")
supersession_controller = load_module(
    SUPERSESSION_CONTROLLER_PATH, "cf7_portrait_human_review_supersession_v1"
)
base = v4.base
ORIGINAL_VERIFY_FEEDBACK = v4.verify_feedback
ORIGINAL_BUILD_ATLAS = v4.v3.build_atlas
CURRENT_SUPERSESSION: tuple[Path, dict[str, Any]] | None = None
CURRENT_PANEL_PATH: Path | None = None


def verify_feedback_v5(feedback: dict[str, Any], shard_size: int) -> dict[str, Any]:
    scaling = ORIGINAL_VERIFY_FEEDBACK(feedback, shard_size)
    override = scaling.get("humanScaleOverride", {})
    if (
        scaling.get("policy") != "human_scale_directive_v1"
        or scaling.get("expectedRevisionBudgetIsGate") is not False
        or scaling.get("expectedRevisionBudgetRole") != "tracking_benchmark_only"
        or scaling.get("eligibleToDoubleByEstimate") is not False
        or override.get("active") is not True
        or override.get("directive") != "double_next_identity_batch"
        or override.get("targetShardSize") != shard_size
        or override.get("targetSourceGroups") != max(1, shard_size // 4)
        or override.get("reviewPageLimit") is not None
        or override.get("expectedRevisionBudgetBlocksScale") is not False
    ):
        raise base.AtlasError("feedback v4 人类扩容指令没有精确闭合到目标 shard")
    return scaling


def role_row(report: dict[str, Any], field: str, role: str = "proposal") -> dict[str, Any]:
    rows = [row for row in report.get(field, []) if row.get("role") == role]
    if len(rows) != 1:
        raise base.AtlasError(f"supersession {field} 缺唯一 {role} row")
    return rows[0]


def draw_master_tile(
    canvas: Image.Image,
    draw: ImageDraw.ImageDraw,
    record: dict[str, Any],
    box: tuple[int, int, int, int],
    label: str,
    label_font: ImageFont.FreeTypeFont,
) -> None:
    path = base.verify_artifact(record, f"supersession {label} master")
    left, top, right, bottom = box
    draw.rounded_rectangle(box, radius=18, fill="#18242D", outline="#4D6978", width=2)
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    available = (right - left - 28, bottom - top - 62)
    contained = ImageOps.contain(image, available, method=Image.Resampling.LANCZOS)
    tile = Image.new("RGBA", contained.size, (15, 23, 29, 255))
    tile.alpha_composite(contained)
    x = left + (right - left - contained.width) // 2
    y = top + 46 + (bottom - top - 54 - contained.height) // 2
    canvas.paste(tile.convert("RGB"), (x, y))
    draw.text((left + 16, top + 12), label, font=label_font, fill="#E9F3F5")


def build_superseded_panel(
    output_path: Path,
    width: int,
    font_path: Path,
    report: dict[str, Any],
) -> dict[str, Any]:
    height = 470
    canvas = Image.new("RGB", (width, height), "#0E171D")
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(str(font_path), 28)
    body_font = ImageFont.truetype(str(font_path), 18)
    small_font = ImageFont.truetype(str(font_path), 16)
    draw.rectangle((0, 0, width, 62), fill="#142732")
    draw.text((24, 15), "真人纠错闭环：旧姿势保留为负例，最终选帧作为正例", font=title_font, fill="#A7F0E4")

    old_row = role_row(report, "supersededRows")
    new_row = role_row(report, "resolvedRows")
    tile_width = min(420, (width - 260) // 2)
    old_box = (70, 82, 70 + tile_width, 408)
    new_box = (width - 70 - tile_width, 82, width - 70, 408)
    draw_master_tile(canvas, draw, old_row["master"], old_box, "已否决姿势", body_font)
    draw_master_tile(canvas, draw, new_row["master"], new_box, "最终通过：空手平A frame 22", body_font)

    middle = width // 2
    draw.text((middle - 44, 205), "→", font=title_font, fill="#63D7C5")
    old_note = report.get("supersededDecision", {}).get("notes", "")
    note_lines = textwrap.wrap(old_note, width=24)[:4]
    note_top = 270
    for index, line in enumerate(note_lines):
        draw.text((middle - 220, note_top + index * 26), line, font=small_font, fill="#E8B7A8")
    draw.text(
        (24, 434),
        "训练声明：无。该面板只作为后续模型的确定性偏好上下文；当前决定仍由真人回执控制。",
        font=small_font,
        fill="#90A7B2",
    )
    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    return {"artifact": base.artifact(output_path), "dimensions": [width, height]}


def build_atlas_with_supersession(
    output_path: Path,
    font_path: Path,
    decisions: dict[str, dict[str, Any]],
    initial: dict[tuple[str, str], dict[str, Any]],
    guided: dict[str, dict[str, Any]],
    orientation_only: dict[str, dict[str, Any]],
    guided_orientation: dict[str, dict[str, Any]],
    feedback: dict[str, Any],
) -> dict[str, Any]:
    global CURRENT_PANEL_PATH
    if CURRENT_SUPERSESSION is None:
        raise base.AtlasError("attach v5 缺 supersession report")
    coverage = ORIGINAL_BUILD_ATLAS(
        output_path,
        font_path,
        decisions,
        initial,
        guided,
        orientation_only,
        guided_orientation,
        feedback,
    )
    _report_path, report = CURRENT_SUPERSESSION
    with Image.open(output_path) as opened:
        atlas = opened.convert("RGB")
    panel_path = output_path.parent / "resolved-followup-preference-panel.png"
    panel = build_superseded_panel(panel_path, atlas.width, font_path, report)
    with Image.open(panel_path) as opened:
        panel_image = opened.convert("RGB")
    combined = Image.new("RGB", (atlas.width, atlas.height + panel_image.height), "#0E171D")
    combined.paste(atlas, (0, 0))
    combined.paste(panel_image, (0, atlas.height))
    combined.save(output_path, format="PNG", optimize=False, compress_level=9)
    CURRENT_PANEL_PATH = panel_path
    coverage["dimensions"] = [combined.width, combined.height]
    coverage["supersededDecisionEvidenceCount"] = 1
    coverage["supersededHumanFeedbackVisualized"] = True
    coverage["latestResolvedStateVisualized"] = True
    coverage["supersededPanelDimensions"] = panel["dimensions"]
    return coverage


@contextmanager
def patched_v4() -> Iterator[None]:
    original_controller = v4.CONTROLLER_PATH
    original_schema = v4.SCHEMA
    original_mode = v4.MODE
    original_feedback_schema = v4.FEEDBACK_SCHEMA
    original_verify_feedback = v4.verify_feedback
    original_build_atlas = v4.v3.build_atlas
    try:
        v4.CONTROLLER_PATH = CONTROLLER_PATH
        v4.SCHEMA = SCHEMA
        v4.MODE = MODE
        v4.FEEDBACK_SCHEMA = FEEDBACK_SCHEMA
        v4.verify_feedback = verify_feedback_v5
        v4.v3.build_atlas = build_atlas_with_supersession
        yield
    finally:
        v4.CONTROLLER_PATH = original_controller
        v4.SCHEMA = original_schema
        v4.MODE = original_mode
        v4.FEEDBACK_SCHEMA = original_feedback_schema
        v4.verify_feedback = original_verify_feedback
        v4.v3.build_atlas = original_build_atlas


def rebind_v5(manifest_path: Path, supersession_path: Path) -> None:
    if CURRENT_PANEL_PATH is None:
        raise base.AtlasError("attach v5 没有生成 superseded preference panel")
    manifest = base.load_json(manifest_path, "atlas v5 manifest")
    calibration = manifest.get("humanPreferenceCalibration")
    if not isinstance(calibration, dict):
        raise base.AtlasError("atlas v5 manifest 缺 humanPreferenceCalibration")
    calibration["v4ControllerSource"] = base.artifact(V4_CONTROLLER_PATH)
    calibration["supersessionControllerSource"] = base.artifact(SUPERSESSION_CONTROLLER_PATH)
    calibration["supersessionReport"] = base.artifact(supersession_path)
    calibration["supersededFeedbackPanel"] = base.artifact(CURRENT_PANEL_PATH)
    calibration["gates"].update(
        {
            "latestVerifiedFollowupWins": True,
            "supersededNegativeEvidencePreserved": True,
            "supersededHumanFeedbackVisualized": True,
        }
    )
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (V4_CONTROLLER_PATH, SUPERSESSION_CONTROLLER_PATH, supersession_path, CURRENT_PANEL_PATH):
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


def verify_v5(manifest_path: Path) -> dict[str, Any]:
    with patched_v4(), contextlib.redirect_stdout(io.StringIO()):
        inherited = v4.verify_derived(manifest_path)
    manifest = base.load_json(manifest_path, "atlas v5 manifest")
    calibration = manifest.get("humanPreferenceCalibration", {})
    coverage = calibration.get("coverage", {})
    gates = calibration.get("gates", {})
    if (
        calibration.get("schema") != SCHEMA
        or calibration.get("mode") != MODE
        or calibration.get("v4ControllerSource") != base.artifact(V4_CONTROLLER_PATH)
        or calibration.get("supersessionControllerSource") != base.artifact(SUPERSESSION_CONTROLLER_PATH)
        or coverage.get("supersededDecisionEvidenceCount") != 1
        or coverage.get("supersededHumanFeedbackVisualized") is not True
        or coverage.get("latestResolvedStateVisualized") is not True
        or gates.get("latestVerifiedFollowupWins") is not True
        or gates.get("supersededNegativeEvidencePreserved") is not True
        or gates.get("supersededHumanFeedbackVisualized") is not True
    ):
        raise base.AtlasError("atlas v5 supersession gate 非法")

    supersession_path = base.verify_artifact(calibration.get("supersessionReport"), "supersession report")
    supersession = base.load_json(supersession_path, "supersession report")
    supersession_controller.verify_report(supersession_path)
    panel_path = base.verify_artifact(calibration.get("supersededFeedbackPanel"), "superseded feedback panel")
    with Image.open(panel_path) as panel:
        if list(panel.size) != coverage.get("supersededPanelDimensions"):
            raise base.AtlasError("superseded feedback panel 尺寸漂移")
    if supersession.get("snapshotReceipt") not in calibration.get("humanReviewReceipts", []):
        raise base.AtlasError("最新 snapshot receipt 未进入 atlas 决定闭包")
    if supersession.get("snapshotRenderReport") not in calibration.get("parentRenderReports", []):
        raise base.AtlasError("最新 snapshot render 未进入 atlas 像素闭包")
    return {
        **inherited,
        "status": "campaign_human_preference_atlas_v5_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "humanLabels": coverage["decisionCount"],
        "supersededNegativeExamples": coverage["supersededDecisionEvidenceCount"],
        "latestResolvedState": supersession["resolvedDecision"]["status"],
        "productionReady": False,
    }


def attach(args: argparse.Namespace) -> None:
    global CURRENT_SUPERSESSION, CURRENT_PANEL_PATH
    supersession_path = base.repo_path(args.supersession_report, "supersession report")
    supersession_controller.verify_report(supersession_path)
    supersession = base.load_json(supersession_path, "supersession report")
    CURRENT_SUPERSESSION = (supersession_path, supersession)
    CURRENT_PANEL_PATH = None
    with patched_v4(), contextlib.redirect_stdout(io.StringIO()):
        v4.attach(args)
    manifest_path = base.repo_path(args.output, "atlas v5 output") / "candidate-manifest.json"
    rebind_v5(manifest_path, supersession_path)
    print(json.dumps(verify_v5(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_v5(base.repo_path(args.manifest, "atlas v5 manifest")), ensure_ascii=False))


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
    except (base.AtlasError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"feedback atlas v5 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
