#!/usr/bin/env python3
"""Attach every frozen human portrait label to a fresh campaign shard.

This controller deliberately leaves attach-feedback-atlas.py unchanged because
existing campaign evidence binds that file byte-for-byte.  It reuses the stable
artifact helpers from v1, removes the two-round count constants, and renders
non-adjustment failures as negative examples instead of dropping them.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


CONTROLLER_PATH = Path(__file__).resolve()
BASE_CONTROLLER_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas.py")
SPEC = importlib.util.spec_from_file_location("cf7_portrait_feedback_atlas_v1", BASE_CONTROLLER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"无法加载基础 feedback atlas controller：{BASE_CONTROLLER_PATH}")
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)

SCHEMA = "cf7.portrait-pilot-human-preference-atlas.v2"
MODE = "bound_all_human_labels_visual_examples"


def build_atlas(
    output_path: Path,
    font_path: Path,
    decisions: dict[str, dict[str, Any]],
    initial_rows: dict[tuple[str, str], dict[str, Any]],
    guided: dict[str, dict[str, Any]],
    orientation_rows: list[dict[str, Any]],
    feedback: dict[str, Any],
) -> dict[str, Any]:
    pass_keys = sorted(key for key, row in decisions.items() if row.get("status") == "pass")
    adjustment_keys = {key for key, row in decisions.items() if row.get("status") == "adjustment"}
    anomaly_keys = sorted(key for key, row in decisions.items() if row.get("status") not in {"pass", "adjustment"})
    guided_keys = set(guided)
    orientation_keys = {row.get("reviewKey") for row in orientation_rows}
    if adjustment_keys != guided_keys | orientation_keys or guided_keys & orientation_keys:
        raise base.AtlasError(
            "全部 adjustment 必须精确分解为 human-guided crop 或 orientation；"
            f"adjustment={len(adjustment_keys)} guided={len(guided_keys)} orientation={len(orientation_keys)}"
        )
    covered = set(pass_keys) | guided_keys | orientation_keys | set(anomaly_keys)
    if set(decisions) != covered:
        raise base.AtlasError("human label 视觉覆盖不闭合")

    accepted: list[dict[str, Any]] = []
    for key in pass_keys:
        initial = initial_rows.get((key, "proposal"))
        if initial is None:
            raise base.AtlasError(f"pass 行缺 proposal master：{key}")
        accepted.append(
            {
                "reviewKey": key,
                "notes": decisions[key].get("notes", ""),
                "master": base.verify_artifact(initial["master"], f"accepted master {key}"),
            }
        )

    corrections: list[dict[str, Any]] = []
    for key in sorted(guided):
        row = guided[key]
        role = row.get("selectedChoice", {}).get("sourceRole")
        initial = initial_rows.get((key, role))
        if initial is None:
            raise base.AtlasError(f"guided 行缺绑定的模型初稿：{key}/{role}")
        corrections.append(
            {
                "reviewKey": key,
                "notes": decisions[key].get("notes", ""),
                "category": base.note_category(decisions[key].get("notes", ""), role),
                "sourceRole": role,
                "initial": base.verify_artifact(initial["master"], f"initial master {key}/{role}"),
                "human": base.verify_artifact(row["master"], f"human master {key}"),
            }
        )
    for row in orientation_rows:
        key = row["reviewKey"]
        if key not in decisions or decisions[key].get("status") != "adjustment":
            raise base.AtlasError(f"orientation 行未绑定 adjustment：{key}")
        corrections.append(
            {
                "reviewKey": key,
                "notes": decisions[key].get("notes", ""),
                "category": "朝向修正：保持明确的正向约定",
                "sourceRole": row.get("sourceRole"),
                "initial": base.verify_artifact(row["parentMaster"], f"orientation parent {key}"),
                "human": base.verify_artifact(row["master"], f"orientation human {key}"),
            }
        )
    corrections.sort(key=lambda row: row["reviewKey"])

    anomalies: list[dict[str, Any]] = []
    for key in anomaly_keys:
        initial = initial_rows.get((key, "proposal")) or initial_rows.get((key, "independent_review"))
        if initial is None:
            raise base.AtlasError(f"异常标签缺模型初稿：{key}")
        anomalies.append(
            {
                "reviewKey": key,
                "status": decisions[key].get("status"),
                "notes": decisions[key].get("notes", ""),
                "initial": base.verify_artifact(initial["master"], f"anomaly initial {key}"),
            }
        )

    width = 1885
    pad = 24
    header_height = 92
    summary_height = 142
    accepted_title_height = 42
    accepted_cell_height = 224
    accepted_columns = min(5, max(1, len(accepted)))
    accepted_rows = math.ceil(len(accepted) / accepted_columns) if accepted else 0
    correction_title_height = 48
    correction_columns = 3
    correction_cell_height = 238
    correction_rows = math.ceil(len(corrections) / correction_columns) if corrections else 0
    anomaly_title_height = 48 if anomalies else 0
    anomaly_cell_height = 238
    anomaly_columns = 3
    anomaly_rows = math.ceil(len(anomalies) / anomaly_columns) if anomalies else 0
    height = (
        header_height
        + summary_height
        + accepted_title_height
        + accepted_rows * accepted_cell_height
        + correction_title_height
        + correction_rows * correction_cell_height
        + anomaly_title_height
        + anomaly_rows * anomaly_cell_height
        + pad
    )
    canvas = Image.new("RGB", (width, height), "#10151C")
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.truetype(str(font_path), 28)
    section_font = ImageFont.truetype(str(font_path), 22)
    body_font = ImageFont.truetype(str(font_path), 17)
    small_font = ImageFont.truetype(str(font_path), 15)

    draw.rectangle((0, 0, width, header_height), fill="#172430")
    draw.rectangle((0, 0, 12, height), fill="#43C7B7")
    draw.text((pad, 16), "BOUND HUMAN PREFERENCE EXAMPLES — NOT CANDIDATES", font=title_font, fill="#F4FCFF")
    draw.text((pad, 54), "全部冻结标签均进入视觉上下文；只校准构图，不得选择示例角色、candidateId 或坐标", font=body_font, fill="#9FE7DD")

    summary_top = header_height
    draw.rectangle((12, summary_top, width, summary_top + summary_height), fill="#1B2028")
    geometry = feedback.get("geometryCalibration", {})
    scaling = feedback.get("adaptiveScaling", {})
    summary_lines = [
        f"完整覆盖：{len(decisions)} 条标签 = {len(accepted)} pass + {len(corrections)} adjustment + {len(anomalies)} anomaly。",
        f"累计框选 {len(geometry.get('rows', []))} 条；中位倍率 {geometry.get('medianZoomIn')}×，范围 "
        f"{geometry.get('minimumZoomIn')}–{geometry.get('maximumZoomIn')}×。小于 1 代表人类为保全特征而放宽，禁止机械放大。",
        "构图目标是最小但完整的身份特写：去除全身/武器/死区，同时完整保留头、发型、耳朵、帽子和透明安全边距。",
        f"规模门：{scaling.get('doubledShardSize')} × {scaling.get('estimatedFailureRate')} = "
        f"{scaling.get('expectedRevisionsAtDoubledSize')}；下一批 {scaling.get('recommendedNextShardSize')}，Fast 并发上限 {scaling.get('maximumConcurrency')}。",
    ]
    for index, line in enumerate(summary_lines):
        draw.text((pad, summary_top + 9 + index * 31), line, font=body_font, fill="#D6DEE8")

    accepted_title_top = summary_top + summary_height
    draw.text((pad, accepted_title_top + 8), "HUMAN PASS ANCHORS / 人类直接通过的构图", font=section_font, fill="#7EE2A8")
    accepted_top = accepted_title_top + accepted_title_height
    accepted_cell_width = (width - 2 * pad) // accepted_columns
    for index, row in enumerate(accepted):
        column = index % accepted_columns
        line = index // accepted_columns
        left = pad + column * accepted_cell_width
        top = accepted_top + line * accepted_cell_height
        right = left + accepted_cell_width - 10
        bottom = top + accepted_cell_height - 10
        draw.rounded_rectangle((left, top, right, bottom), radius=10, fill="#17231F", outline="#3B8D68", width=2)
        image_size = 154
        image_left = left + (right - left - image_size) // 2
        base.paste_contained(canvas, row["master"], (image_left, top + 12, image_left + image_size, top + 12 + image_size))
        draw.text((left + 10, top + 171), base.portrait_name(row["reviewKey"])[:16], font=body_font, fill="#F0F6F3")
        note = row["notes"].strip()
        draw.text((left + 10, top + 196), "PASS" if not note else f"PASS；{note[:16]}", font=small_font, fill="#8BD7AD")

    correction_title_top = accepted_top + accepted_rows * accepted_cell_height
    draw.rectangle((12, correction_title_top, width, correction_title_top + correction_title_height), fill="#271E22")
    draw.text((pad, correction_title_top + 10), "ALL HUMAN CORRECTIONS / MODEL INITIAL → HUMAN ACCEPTED", font=section_font, fill="#FFB3BC")
    grid_top = correction_title_top + correction_title_height
    correction_cell_width = (width - 2 * pad) // correction_columns
    image_size = 144
    for index, row in enumerate(corrections):
        column = index % correction_columns
        line = index // correction_columns
        left = pad + column * correction_cell_width
        top = grid_top + line * correction_cell_height
        right = left + correction_cell_width - 12
        bottom = top + correction_cell_height - 10
        draw.rounded_rectangle((left, top, right, bottom), radius=10, fill="#1D2027", outline="#6A454E", width=2)
        initial_left = left + 14
        human_left = initial_left + image_size + 54
        image_top = top + 42
        draw.text((initial_left, top + 12), "MODEL INITIAL", font=small_font, fill="#E1A4AC")
        draw.text((human_left, top + 12), "HUMAN ACCEPTED", font=small_font, fill="#86E2B1")
        base.paste_contained(canvas, row["initial"], (initial_left, image_top, initial_left + image_size, image_top + image_size))
        base.paste_contained(canvas, row["human"], (human_left, image_top, human_left + image_size, image_top + image_size))
        draw.text((initial_left + image_size + 15, image_top + 55), "→", font=title_font, fill="#FFD166")
        text_left = human_left + image_size + 14
        draw.text((text_left, image_top), base.portrait_name(row["reviewKey"])[:15], font=body_font, fill="#F3F5F8")
        draw.text((text_left, image_top + 27), row["category"][:18], font=small_font, fill="#FFD166")
        for line_index, value in enumerate(base.wrap_text(row["notes"], 18)[:4]):
            draw.text((text_left, image_top + 54 + line_index * 23), value, font=small_font, fill="#BFC7D1")
        draw.text((text_left, bottom - 27), f"source={row['sourceRole']}", font=small_font, fill="#8292A6")

    anomaly_top = grid_top + correction_rows * correction_cell_height
    if anomalies:
        draw.rectangle((12, anomaly_top, width, anomaly_top + anomaly_title_height), fill="#2A2418")
        draw.text((pad, anomaly_top + 10), "HUMAN NEGATIVE ROUTES / 不可用作通过构图", font=section_font, fill="#FFD166")
        anomaly_grid_top = anomaly_top + anomaly_title_height
        anomaly_cell_width = (width - 2 * pad) // anomaly_columns
        for index, row in enumerate(anomalies):
            column = index % anomaly_columns
            line = index // anomaly_columns
            left = pad + column * anomaly_cell_width
            top = anomaly_grid_top + line * anomaly_cell_height
            right = left + anomaly_cell_width - 12
            bottom = top + anomaly_cell_height - 10
            draw.rounded_rectangle((left, top, right, bottom), radius=10, fill="#252016", outline="#8F7436", width=2)
            image_left = left + 14
            image_top = top + 42
            draw.text((image_left, top + 12), f"REJECTED / {str(row['status']).upper()}", font=small_font, fill="#FFD166")
            base.paste_contained(canvas, row["initial"], (image_left, image_top, image_left + image_size, image_top + image_size))
            text_left = image_left + image_size + 20
            draw.text((text_left, image_top), base.portrait_name(row["reviewKey"])[:18], font=body_font, fill="#F3F5F8")
            for line_index, value in enumerate(base.wrap_text(row["notes"], 23)[:6]):
                draw.text((text_left, image_top + 34 + line_index * 23), value, font=small_font, fill="#E7D3A2")

    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    status_counts: dict[str, int] = {}
    for row in decisions.values():
        status = str(row.get("status"))
        status_counts[status] = status_counts.get(status, 0) + 1
    return {
        "schema": SCHEMA,
        "mode": MODE,
        "decisionCount": len(decisions),
        "passAnchorCount": len(accepted),
        "guidedCorrectionCount": len(guided),
        "orientationCorrectionCount": len(orientation_rows),
        "adjustmentCount": len(corrections),
        "anomalyCount": len(anomalies),
        "statusCounts": status_counts,
        "allHumanLabelsVisualized": set(decisions) == covered,
        "reviewKeys": sorted(decisions),
        "dimensions": [width, height],
    }


def receipt_counts(calibration: dict[str, Any]) -> dict[str, int]:
    decisions: dict[str, str] = {}
    for index, record in enumerate(calibration.get("humanReviewReceipts", [])):
        path = base.verify_artifact(record, f"human review receipt {index}")
        receipt = base.load_json(path, f"human review receipt {index}")
        base.verify_digest(receipt, "receiptDigest", f"human review receipt {index}")
        for row in receipt.get("decisions", []):
            key = row.get("reviewKey")
            status = row.get("status")
            if not isinstance(key, str) or not isinstance(status, str) or key in decisions:
                raise base.AtlasError(f"累计人审决定重复或非法：{key}")
            decisions[key] = status
    counts: dict[str, int] = {}
    for status in decisions.values():
        counts[status] = counts.get(status, 0) + 1
    counts["decisionCount"] = len(decisions)
    return counts


def verify_derived(manifest_path: Path) -> dict[str, Any]:
    manifest = base.load_json(manifest_path, "derived manifest")
    base.verify_digest(manifest, "manifestDigest", "derived manifest")
    envelope = manifest.get("sourceEnvelope")
    if not isinstance(envelope, dict) or base.sha256_bytes(base.stable_bytes(envelope)) != manifest.get("sourceDigest"):
        raise base.AtlasError("derived sourceDigest 不匹配")
    calibration = envelope.get("humanPreferenceCalibration")
    if (
        not isinstance(calibration, dict)
        or calibration.get("schema") != SCHEMA
        or calibration.get("mode") != MODE
        or calibration.get("gates", {}).get("allHumanLabelsVisualized") is not True
        or calibration.get("gates", {}).get("examplesAreNotCandidates") is not True
        or calibration.get("gates", {}).get("productionWrites") is not False
    ):
        raise base.AtlasError("derived human preference calibration gate 非法")
    for index, record in enumerate(envelope.get("sourceFiles", [])):
        base.verify_artifact(record, f"source file {index}")
    base.verify_artifact(calibration.get("controllerSource"), "feedback atlas v2 controller")
    base.verify_artifact(calibration.get("baseControllerSource"), "feedback atlas v1 dependency")
    atlas_path = base.verify_artifact(calibration.get("atlas"), "feedback atlas")
    with Image.open(atlas_path) as atlas:
        if list(atlas.size) != calibration.get("coverage", {}).get("dimensions"):
            raise base.AtlasError("feedback atlas 尺寸漂移")
    expected_sheets = 1 + len(manifest.get("modelBatches", []))
    if len(calibration.get("contactSheets", [])) != expected_sheets:
        raise base.AtlasError("calibrated contact sheet 数不闭合")
    records = [manifest.get("contactSheet"), *(batch.get("contactSheet") for batch in manifest.get("modelBatches", []))]
    for index, record in enumerate(records):
        path = base.verify_artifact(record, f"calibrated contact sheet {index}")
        evidence = calibration["contactSheets"][index]
        if evidence.get("composite") != record:
            raise base.AtlasError("calibrated contact sheet evidence 漂移")
        with Image.open(path) as image:
            if list(image.size) != evidence.get("compositeDimensions"):
                raise base.AtlasError("calibrated contact sheet 尺寸漂移")

    expected = receipt_counts(calibration)
    coverage = calibration.get("coverage", {})
    expected_pass = expected.get("pass", 0)
    expected_adjustment = expected.get("adjustment", 0)
    expected_anomaly = expected["decisionCount"] - expected_pass - expected_adjustment
    if (
        coverage.get("decisionCount") != expected["decisionCount"]
        or coverage.get("passAnchorCount") != expected_pass
        or coverage.get("adjustmentCount") != expected_adjustment
        or coverage.get("guidedCorrectionCount", 0) + coverage.get("orientationCorrectionCount", 0) != expected_adjustment
        or coverage.get("anomalyCount") != expected_anomaly
        or coverage.get("statusCounts") != {key: value for key, value in expected.items() if key != "decisionCount"}
        or coverage.get("allHumanLabelsVisualized") is not True
        or len(coverage.get("reviewKeys", [])) != expected["decisionCount"]
    ):
        raise base.AtlasError("累计人类标签动态覆盖数不闭合")
    return {
        "status": "campaign_human_preference_atlas_v2_verified",
        "manifest": base.repo_rel(manifest_path),
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "atlasSha256": calibration["atlas"]["sha256"],
        "humanLabels": coverage["decisionCount"],
        "passAnchors": coverage["passAnchorCount"],
        "adjustments": coverage["adjustmentCount"],
        "anomalies": coverage["anomalyCount"],
        "contactSheets": expected_sheets,
        "productionReady": False,
    }


def attach(args: argparse.Namespace) -> None:
    base_path = base.repo_path(args.base_manifest, "base manifest")
    output_dir = base.repo_path(args.output, "output")
    try:
        output_dir.relative_to(base.PILOT_ROOT.resolve())
    except ValueError as error:
        raise base.AtlasError("output 必须位于 tmp/portrait-pilot") from error
    if output_dir.exists():
        raise base.AtlasError(f"输出目录已存在，禁止覆盖：{output_dir}")
    if not args.batch_id or len(args.batch_id) > 128 or not all(character.isalnum() or character in "._-" for character in args.batch_id):
        raise base.AtlasError("batch-id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")

    manifest = base.load_json(base_path, "base manifest")
    base.verify_digest(manifest, "manifestDigest", "base manifest")
    if base.sha256_bytes(base.stable_bytes(manifest.get("sourceEnvelope"))) != manifest.get("sourceDigest"):
        raise base.AtlasError("base manifest sourceDigest 不匹配")
    if manifest.get("status") != "campaign_shard_prepared" or manifest.get("productionReady") is not False:
        raise base.AtlasError("base manifest 尚不是未投产 campaign shard")
    font_path = base.verify_font(manifest)

    feedback_path = base.repo_path(args.feedback_report, "feedback report")
    feedback = base.load_json(feedback_path, "feedback report")
    base.verify_digest(feedback, "feedbackDigest", "feedback report")
    scaling = feedback.get("adaptiveScaling", {})
    if (
        scaling.get("humanReviewPageLimit") is not None
        or scaling.get("reviewConsolidationPolicy") != "single_page_preferred"
        or scaling.get("recommendedNextShardSize") != manifest.get("campaign", {}).get("shardSize")
        or scaling.get("maximumConcurrency") != 6
    ):
        raise base.AtlasError("feedback adaptive scaling 与下一 shard 不一致")

    receipt_reports = base.load_reports(args.human_review_receipt, "receiptDigest", "human review receipt")
    render_reports = base.load_reports(args.parent_render_report, "renderDigest", "parent render report")
    guided_reports = base.load_reports(args.guided_report, "reportDigest", "human-guided report")
    orientation_path = base.repo_path(args.orientation_report, "orientation report")
    orientation = base.load_json(orientation_path, "orientation report")
    base.verify_digest(orientation, "reportDigest", "orientation report")
    if (
        orientation.get("status") != "human_orientation_adjustment_checked"
        or orientation.get("productionReady") is not False
        or orientation.get("gates", {}).get("modelRerun") is not False
    ):
        raise base.AtlasError("orientation report gate 非法")

    decisions = base.decision_rows(receipt_reports)
    initial = base.role_rows(render_reports)
    guided = base.guided_rows(guided_reports)
    orientation_rows = orientation.get("rows", [])
    geometry_keys = {row.get("reviewKey") for row in feedback.get("geometryCalibration", {}).get("rows", [])}
    if geometry_keys != set(guided):
        raise base.AtlasError("累计 geometry 行与 human-guided visuals 不闭合")

    output_dir.mkdir(parents=True)
    atlas_path = output_dir / "feedback-preference-atlas.png"
    coverage = build_atlas(atlas_path, font_path, decisions, initial, guided, orientation_rows, feedback)
    atlas_record = base.artifact(atlas_path)

    sheet_records: list[dict[str, Any]] = []
    full_sheet = base.composite_sheet(manifest["contactSheet"], atlas_path, output_dir / "feature-contact-sheet-with-feedback.png")
    sheet_records.append(full_sheet)
    model_sheets: list[dict[str, Any]] = []
    for model_batch in manifest["modelBatches"]:
        record = base.composite_sheet(model_batch["contactSheet"], atlas_path, output_dir / f"{model_batch['modelBatchId']}-with-feedback.png")
        sheet_records.append(record)
        model_sheets.append(record["composite"])

    derived = copy.deepcopy(manifest)
    derived.pop("manifestDigest", None)
    derived["batchId"] = args.batch_id
    derived["createdAt"] = base.utc_now()
    derived["contactSheet"] = full_sheet["composite"]
    for model_batch, contact_sheet in zip(derived["modelBatches"], model_sheets):
        model_batch["contactSheet"] = contact_sheet

    evidence_paths = [
        base_path,
        feedback_path,
        orientation_path,
        CONTROLLER_PATH,
        BASE_CONTROLLER_PATH,
        *(path for path, _value in receipt_reports),
        *(path for path, _value in render_reports),
        *(path for path, _value in guided_reports),
        atlas_path,
    ]
    source_files = list(derived["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in evidence_paths:
        record = base.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])

    calibration = {
        "schema": SCHEMA,
        "mode": MODE,
        "baseManifest": base.artifact(base_path),
        "feedbackReport": base.artifact(feedback_path),
        "humanReviewReceipts": [base.artifact(path) for path, _value in receipt_reports],
        "parentRenderReports": [base.artifact(path) for path, _value in render_reports],
        "humanGuidedRenderReports": [base.artifact(path) for path, _value in guided_reports],
        "orientationReport": base.artifact(orientation_path),
        "controllerSource": base.artifact(CONTROLLER_PATH),
        "baseControllerSource": base.artifact(BASE_CONTROLLER_PATH),
        "atlas": atlas_record,
        "coverage": coverage,
        "contactSheets": sheet_records,
        "adaptiveScaling": scaling,
        "gates": {
            "allHumanLabelsVisualized": coverage["allHumanLabelsVisualized"],
            "rawHumanReceiptsBound": True,
            "deterministicHumanOutputsBound": True,
            "examplesAreNotCandidates": True,
            "noHumanPageSizeLimit": True,
            "modelTrainingClaim": False,
            "productionWrites": False,
        },
    }
    derived["sourceEnvelope"]["batchId"] = args.batch_id
    derived["sourceEnvelope"]["sourceFiles"] = source_files
    derived["sourceEnvelope"]["humanPreferenceCalibration"] = calibration
    derived["sourceDigest"] = base.sha256_bytes(base.stable_bytes(derived["sourceEnvelope"]))
    derived["humanPreferenceCalibration"] = calibration
    derived["manifestDigest"] = base.sha256_bytes(base.stable_bytes(derived))
    manifest_path = output_dir / "candidate-manifest.json"
    base.write_json(manifest_path, derived)
    print(json.dumps(verify_derived(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_derived(base.repo_path(args.manifest, "derived manifest")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    attach_parser = commands.add_parser("attach")
    attach_parser.add_argument("--base-manifest", required=True)
    attach_parser.add_argument("--feedback-report", required=True)
    attach_parser.add_argument("--human-review-receipt", action="append", required=True)
    attach_parser.add_argument("--parent-render-report", action="append", required=True)
    attach_parser.add_argument("--guided-report", action="append", required=True)
    attach_parser.add_argument("--orientation-report", required=True)
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
    except (base.AtlasError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"portrait feedback atlas v2 error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
