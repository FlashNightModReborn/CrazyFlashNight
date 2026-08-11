#!/usr/bin/env python3
"""Prepare localization views from a verified exact-frame human directive."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

import prepare_frame_reselection_localization_v1 as base
from prepare_pilot import (
    ROOT,
    PilotError,
    artifact,
    load_json,
    sha256_bytes,
    stable_bytes,
    verify_artifact_record,
    verify_digest_object,
    write_json,
)


BASE_PATH = ROOT / "tools/portrait-pilot/prepare_frame_reselection_localization_v1.py"
EXPECTED_BASE_SHA256 = "A6F6C41B4CFB854B0FB5A0EE4207B99C189501001CE415C502F9F328B5B78FF8"
DIRECTIVE: dict[str, object] | None = None
ORIGINAL_BUILD_MANIFEST = base.build_manifest


def require_object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise PilotError(f"{label} 必须是对象")
    return value


def require_list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise PilotError(f"{label} 必须是数组")
    return value


def pin_base() -> None:
    digest = hashlib.sha256(BASE_PATH.read_bytes()).hexdigest().upper()
    if digest != EXPECTED_BASE_SHA256:
        raise PilotError(f"基础选帧定位控制器字节漂移：{digest}")


def dedupe_artifacts(records: list[dict[str, object]]) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    seen: set[tuple[object, object]] = set()
    for record in records:
        key = (record.get("path"), record.get("sha256"))
        if key not in seen:
            result.append(record)
            seen.add(key)
    return result


def directive_build_manifest(*args: object, **kwargs: object) -> dict[str, object]:
    manifest = ORIGINAL_BUILD_MANIFEST(*args, **kwargs)
    directive = require_object(DIRECTIVE, "运行期人类指令")
    entities = require_list(manifest.get("entities"), "manifest entities")
    review_items = require_list(manifest.get("reviewItems"), "manifest reviewItems")
    if len(entities) != 1 or len(review_items) != 1:
        raise PilotError("精确选帧定位只接受单行 manifest")
    entity = require_object(entities[0], "manifest entity")
    item = require_object(review_items[0], "manifest review item")
    source_envelope = require_object(manifest.get("sourceEnvelope"), "manifest sourceEnvelope")
    campaign = require_object(manifest.get("campaign"), "manifest campaign")

    entity.update({
        "renderStrategy": "human_selected_exact_action_state_instance",
        "vectorSourceStrategy": "ffdec_sprite_svg_human_selected_exact_action_frame",
        "notes": directive["entityNotes"],
    })
    item["humanFeedback"] = {
        "source": "verified_human_exact_action_frame_directive",
        "receiptDigest": require_object(source_envelope.get("humanFrameReselection"), "humanFrameReselection")["receiptDigest"],
        "candidateId": require_object(source_envelope.get("humanFrameReselection"), "humanFrameReselection")["candidateId"],
        "frame": require_object(source_envelope.get("humanFrameReselection"), "humanFrameReselection")["frame"],
        "actionPath": directive["actionPath"],
        "instruction": directive["localizationInstruction"],
        "orientationAction": directive["orientationAction"],
        "humanDirective": directive["humanDirective"],
    }
    item["intentPolicy"] = {
        "defaultMode": directive["defaultMode"],
        "reasoningHint": directive["reasoningHint"],
        "orientationDirective": {
            "action": directive["orientationAction"],
            "source": "verified_human_exact_action_frame_directive",
            "applyAfterOriginalSpaceCrop": True,
        },
        "constraintSource": "verified_human_exact_action_frame_directive",
    }

    source_files = [
        copy.deepcopy(record)
        for record in require_list(source_envelope.get("sourceFiles"), "sourceEnvelope.sourceFiles")
        if isinstance(record, dict)
    ]
    source_files.append(artifact(Path(__file__).resolve()))
    source_envelope.update({
        "mode": "verified_human_exact_action_frame_localization_v2",
        "sourceFiles": dedupe_artifacts(source_files),
        "humanDirective": {
            "actionPath": directive["actionPath"],
            "instruction": directive["humanDirective"],
            "orientationAction": directive["orientationAction"],
            "localizationInstruction": directive["localizationInstruction"],
        },
    })
    frame_selection = require_object(source_envelope.get("humanFrameReselection"), "humanFrameReselection")
    frame_selection.update({
        "actionPath": directive["actionPath"],
        "orientationAction": directive["orientationAction"],
        "humanDirective": directive["humanDirective"],
    })
    campaign.update({
        "selectionStrategy": "verified_human_exact_action_frame_then_localization_only",
        "humanOrientationDirective": directive["orientationAction"],
    })
    manifest["gates"] = {
        "verifiedHumanFrameSelection": True,
        "selectedExactActionStateInstance": True,
        "humanOrientationDirectiveBound": True,
        "oldModelGeometryDiscarded": True,
        "localizationOnly": True,
        "humanTargetGeometryExcluded": True,
        "productionWrites": False,
    }
    manifest["sourceDigest"] = sha256_bytes(stable_bytes(source_envelope))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = sha256_bytes(stable_bytes(manifest))
    return manifest


def postprocess(output_root: Path, directive: dict[str, object]) -> dict[str, object]:
    manifest_path = output_root / "candidate-manifest.json"
    source_path = output_root / "selection-source-data.json"
    view_path = output_root / "localization-view-manifest.json"
    manifest = require_object(load_json(manifest_path), "candidate manifest")
    source_data = require_object(load_json(source_path), "selection source data")
    view_report = require_object(load_json(view_path), "localization view manifest")
    review_item = require_object(require_list(manifest.get("reviewItems"), "reviewItems")[0], "review item")
    review_code = review_item["reviewCode"]

    selection = require_object(source_data.get("selection"), "selection source selection")
    selection.update({
        "actionPath": directive["actionPath"],
        "humanDirective": directive["humanDirective"],
        "orientationAction": directive["orientationAction"],
    })
    render_contract = require_object(source_data.get("renderContract"), "selection renderContract")
    render_contract.update({
        "orientationAction": directive["orientationAction"],
        "orientationApplicationStage": "after_original_space_crop_before_output_pyramid",
        "orientationAppliedDuringLocalizationView": False,
    })
    controller = require_object(source_data.get("controller"), "selection controller")
    controller_files = [
        copy.deepcopy(record)
        for record in require_list(controller.get("files"), "selection controller files")
        if isinstance(record, dict)
    ]
    controller_files.append(artifact(Path(__file__).resolve()))
    controller["files"] = dedupe_artifacts(controller_files)
    controller["sourceClosureDigest"] = sha256_bytes(stable_bytes(controller["files"]))
    source_rows = require_list(source_data.get("rows"), "selection source rows")
    if len(source_rows) != 1:
        raise PilotError("selection source rows 必须为一行")
    require_object(source_rows[0], "selection source row").update({
        "reviewCode": review_code,
        "actionPath": directive["actionPath"],
        "orientationDirective": directive["orientationAction"],
    })
    source_data.pop("sourceDataDigest", None)
    source_data["sourceDataDigest"] = sha256_bytes(stable_bytes(source_data))
    write_json(source_path, source_data)

    view_input = require_object(view_report.get("input"), "view input")
    view_input["sourceReviewData"] = artifact(source_path)
    view_input["sourceReviewDigest"] = source_data["sourceDataDigest"]
    view_render = require_object(view_report.get("renderContract"), "view renderContract")
    view_render.update({
        "orientationAction": directive["orientationAction"],
        "orientationCoordinateSpace": "unflipped exact frame normalized 0..1",
        "orientationApplicationStage": "renderer_after_crop",
    })
    view_report["controller"] = artifact(Path(__file__).resolve())
    view_report["baseController"] = artifact(BASE_PATH)
    view_rows = require_list(view_report.get("rows"), "view rows")
    if len(view_rows) != 1:
        raise PilotError("localization view rows 必须为一行")
    require_object(view_rows[0], "view row").update({
        "reviewCode": review_code,
        "actionPath": directive["actionPath"],
        "orientationDirective": directive["orientationAction"],
    })
    gates = require_object(view_report.get("gates"), "view gates")
    gates["humanOrientationDirectiveBound"] = True
    gates["orientationNotAppliedToLocalizationCoordinates"] = True
    view_report.pop("viewDigest", None)
    view_report["viewDigest"] = sha256_bytes(stable_bytes(view_report))
    write_json(view_path, view_report)
    return view_report


def directive_from_args(options: argparse.Namespace) -> dict[str, object]:
    return {
        "actionPath": options.action_path,
        "humanDirective": options.human_directive,
        "localizationInstruction": options.localization_instruction,
        "reasoningHint": options.reasoning_hint,
        "entityNotes": options.entity_notes,
        "defaultMode": options.default_mode,
        "orientationAction": options.orientation_action,
    }


def render(options: argparse.Namespace) -> dict[str, object]:
    global DIRECTIVE
    pin_base()
    directive = directive_from_args(options)
    DIRECTIVE = directive
    base.build_manifest = directive_build_manifest
    try:
        base_args = argparse.Namespace(
            frame_batch=options.frame_batch,
            output=options.output,
            batch_id=options.batch_id,
            max_dimension=options.max_dimension,
        )
        base.render(base_args)
    finally:
        base.build_manifest = ORIGINAL_BUILD_MANIFEST
        DIRECTIVE = None
    output_root = base.pilot_child(options.output, "输出目录", must_exist=True)
    return postprocess(output_root, directive)


def check(options: argparse.Namespace) -> dict[str, object]:
    pin_base()
    output_root = base.pilot_child(options.output, "输出目录", must_exist=True)
    report = base.check(argparse.Namespace(output=options.output))
    manifest = require_object(load_json(output_root / "candidate-manifest.json"), "candidate manifest")
    source_data = require_object(load_json(output_root / "selection-source-data.json"), "selection source data")
    view_report = require_object(load_json(output_root / "localization-view-manifest.json"), "localization view manifest")
    verify_digest_object(manifest, "manifestDigest", "candidate manifest")
    verify_digest_object(source_data, "sourceDataDigest", "selection source data")
    verify_digest_object(view_report, "viewDigest", "localization view manifest")
    verify_artifact_record(require_object(view_report.get("controller"), "view controller"), "directive view controller")
    item = require_object(require_list(manifest.get("reviewItems"), "reviewItems")[0], "review item")
    feedback = require_object(item.get("humanFeedback"), "humanFeedback")
    policy = require_object(item.get("intentPolicy"), "intentPolicy")
    orientation = require_object(policy.get("orientationDirective"), "orientationDirective")
    selection = require_object(source_data.get("selection"), "source selection")
    view_row = require_object(require_list(view_report.get("rows"), "view rows")[0], "view row")
    expected_orientation = feedback.get("orientationAction")
    if (
        expected_orientation not in {"keep", "flip_x"}
        or orientation.get("action") != expected_orientation
        or selection.get("orientationAction") != expected_orientation
        or view_row.get("orientationDirective") != expected_orientation
    ):
        raise PilotError("人类方向指令没有跨 manifest/source/view 闭合")
    if view_report.get("gates", {}).get("humanOrientationDirectiveBound") is not True:
        raise PilotError("人类方向指令 gate 缺失")
    return {
        "status": "human_exact_frame_localization_views_checked",
        "viewDigest": report["viewDigest"],
        "manifestDigest": manifest["manifestDigest"],
        "sourceDataDigest": source_data["sourceDataDigest"],
        "orientationAction": expected_orientation,
        "reviewKey": item["reviewKey"],
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("--frame-batch", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.add_argument("--max-dimension", type=int, default=2048)
    render_parser.add_argument("--action-path", required=True)
    render_parser.add_argument("--human-directive", required=True)
    render_parser.add_argument("--localization-instruction", required=True)
    render_parser.add_argument("--reasoning-hint", required=True)
    render_parser.add_argument("--entity-notes", required=True)
    render_parser.add_argument("--default-mode", choices=["head_closeup", "feature_closeup", "feature_group", "full_subject"], required=True)
    render_parser.add_argument("--orientation-action", choices=["keep", "flip_x"], required=True)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--output", required=True)
    return result


def main() -> None:
    options = parser().parse_args()
    report = render(options) if options.command == "render" else check(options)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, PilotError, KeyError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
