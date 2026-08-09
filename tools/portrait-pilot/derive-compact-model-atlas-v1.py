#!/usr/bin/env python3
"""Derive a compact model-facing view while retaining the complete human-evidence closure."""

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
V3_CONTROLLER_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas-v3.py")
V3_SPEC = importlib.util.spec_from_file_location("cf7_portrait_feedback_atlas_v3", V3_CONTROLLER_PATH)
if V3_SPEC is None or V3_SPEC.loader is None:
    raise RuntimeError(f"无法加载 feedback atlas v3 controller：{V3_CONTROLLER_PATH}")
v3 = importlib.util.module_from_spec(V3_SPEC)
V3_SPEC.loader.exec_module(v3)
base = v3.base

SCHEMA = "cf7.portrait-pilot-model-atlas-retrieval.v1"
MODE = "all_pass_latest_adjustments_all_anomalies_with_full_evidence_bound"


def patch_count(dimensions: list[int]) -> int:
    return math.ceil(dimensions[0] / 32) * math.ceil(dimensions[1] / 32)


def receipt_reports(calibration: dict[str, Any]) -> list[tuple[Path, dict[str, Any]]]:
    reports: list[tuple[Path, dict[str, Any]]] = []
    for index, record in enumerate(calibration.get("humanReviewReceipts", [])):
        path = base.verify_artifact(record, f"human review receipt {index}")
        report = base.load_json(path, f"human review receipt {index}")
        base.verify_digest(report, "receiptDigest", f"human review receipt {index}")
        reports.append((path, report))
    if not reports:
        raise base.AtlasError("human review receipt 闭包为空")
    return reports


def source_layout(counts: dict[str, int]) -> dict[str, int]:
    pass_columns = min(5, max(1, counts["pass"]))
    pass_rows = math.ceil(counts["pass"] / pass_columns) if counts["pass"] else 0
    correction_rows = math.ceil(counts["adjustment"] / 3) if counts["adjustment"] else 0
    anomaly_rows = math.ceil(counts["anomaly"] / 3) if counts["anomaly"] else 0
    accepted_top = 92 + 142 + 42
    correction_grid_top = accepted_top + pass_rows * 224 + 48
    anomaly_grid_top = correction_grid_top + correction_rows * 238 + (48 if counts["anomaly"] else 0)
    return {
        "passColumns": pass_columns,
        "passRows": pass_rows,
        "acceptedTop": accepted_top,
        "correctionRows": correction_rows,
        "correctionGridTop": correction_grid_top,
        "anomalyRows": anomaly_rows,
        "anomalyGridTop": anomaly_grid_top,
    }


def draw_compact_atlas(
    output_path: Path,
    full_atlas_path: Path,
    font_path: Path,
    decisions: dict[str, dict[str, Any]],
    latest_adjustment_keys: list[str],
    feedback: dict[str, Any],
) -> dict[str, Any]:
    pass_keys = sorted(key for key, row in decisions.items() if row.get("status") == "pass")
    correction_keys = sorted(key for key, row in decisions.items() if row.get("status") == "adjustment")
    anomaly_keys = sorted(key for key, row in decisions.items() if row.get("status") not in {"pass", "adjustment"})
    counts = {"pass": len(pass_keys), "adjustment": len(correction_keys), "anomaly": len(anomaly_keys)}
    layout = source_layout(counts)
    missing = sorted(set(latest_adjustment_keys) - set(correction_keys))
    if missing:
        raise base.AtlasError(f"latest receipt adjustment 不在完整修正图谱中：{missing}")

    width = 1885
    pad = 24
    header_height = 104
    summary_height = 174
    pass_title_height = 42
    pass_grid_height = layout["passRows"] * 224
    correction_title_height = 56
    selected_correction_rows = math.ceil(len(latest_adjustment_keys) / 3) if latest_adjustment_keys else 0
    correction_grid_height = selected_correction_rows * 238
    anomaly_title_height = 48 if anomaly_keys else 0
    anomaly_grid_height = layout["anomalyRows"] * 238
    height = (
        header_height
        + summary_height
        + pass_title_height
        + pass_grid_height
        + correction_title_height
        + correction_grid_height
        + anomaly_title_height
        + anomaly_grid_height
        + pad
    )

    with Image.open(full_atlas_path) as source:
        source.load()
        if source.size[0] != width:
            raise base.AtlasError(f"完整 atlas 宽度漂移：{source.size}")
        canvas = Image.new("RGB", (width, height), "#10151C")
        draw = ImageDraw.Draw(canvas)
        title_font = ImageFont.truetype(str(font_path), 28)
        section_font = ImageFont.truetype(str(font_path), 22)
        body_font = ImageFont.truetype(str(font_path), 17)

        draw.rectangle((0, 0, width, header_height), fill="#172430")
        draw.rectangle((0, 0, 12, height), fill="#43C7B7")
        draw.text((pad, 15), "RETRIEVED HUMAN PREFERENCE VIEW — NOT CANDIDATES", font=title_font, fill="#F4FCFF")
        draw.text(
            (pad, 56),
            "完整原始回执与 96 标签 atlas 仍由 manifest 哈希绑定；本图只压缩单次视觉输入，不改变人类裁决。",
            font=body_font,
            fill="#9FE7DD",
        )

        geometry = feedback.get("geometryCalibration", {})
        summary_lines = [
            f"全量闭包：{len(decisions)} 标签 = {len(pass_keys)} pass + {len(correction_keys)} adjustment + {len(anomaly_keys)} anomaly；"
            f"累计 {len(geometry.get('rows', []))} 个真人框选。",
            f"确定性检索：全部 {len(pass_keys)} 个通过锚点 + 最新回执 {len(latest_adjustment_keys)} 个 adjustment + 全部 {len(anomaly_keys)} 个异常负例。",
            f"真人倍率中位数 {geometry.get('medianZoomIn')}×，范围 {geometry.get('minimumZoomIn')}–{geometry.get('maximumZoomIn')}×；"
            "只用于构图校准，不得机械套倍率。",
            "识别度优先：人形先锁定完整头部；非人推理眼、口器、头甲、核心或不可拆分结构。主焦点留安全区，弱组件允许顶边裁切。",
            "当前候选始终在附件 1；本检索图仅为附件 2 的历史偏好提示，严禁从这里选身份、candidateId 或坐标。",
        ]
        summary_top = header_height
        draw.rectangle((12, summary_top, width, summary_top + summary_height), fill="#1B2028")
        for index, line in enumerate(summary_lines):
            draw.text((pad, summary_top + 8 + index * 32), line, font=body_font, fill="#D6DEE8")

        pass_title_top = summary_top + summary_height
        draw.text((pad, pass_title_top + 8), "ALL HUMAN PASS ANCHORS / 全部真人通过构图", font=section_font, fill="#7EE2A8")
        pass_top = pass_title_top + pass_title_height
        if pass_grid_height:
            region = source.crop((0, layout["acceptedTop"], width, layout["acceptedTop"] + pass_grid_height))
            canvas.paste(region, (0, pass_top))

        correction_title_top = pass_top + pass_grid_height
        draw.rectangle((12, correction_title_top, width, correction_title_top + correction_title_height), fill="#271E22")
        draw.text(
            (pad, correction_title_top + 13),
            "LATEST HUMAN CORRECTIONS / 最近一轮 MODEL INITIAL → HUMAN ACCEPTED",
            font=section_font,
            fill="#FFB3BC",
        )
        correction_top = correction_title_top + correction_title_height
        cell_width = (width - 2 * pad) // 3
        for destination_index, key in enumerate(sorted(latest_adjustment_keys)):
            source_index = correction_keys.index(key)
            source_column = source_index % 3
            source_row = source_index // 3
            destination_column = destination_index % 3
            destination_row = destination_index // 3
            source_left = pad + source_column * cell_width
            source_top = layout["correctionGridTop"] + source_row * 238
            cell = source.crop((source_left, source_top, source_left + cell_width, source_top + 238))
            destination_left = pad + destination_column * cell_width
            destination_top = correction_top + destination_row * 238
            canvas.paste(cell, (destination_left, destination_top))

        anomaly_title_top = correction_top + correction_grid_height
        if anomaly_keys:
            draw.rectangle((12, anomaly_title_top, width, anomaly_title_top + anomaly_title_height), fill="#2A2418")
            draw.text(
                (pad, anomaly_title_top + 10),
                "ALL HUMAN NEGATIVE ROUTES / 全部不可用负例",
                font=section_font,
                fill="#FFD166",
            )
            anomaly_top = anomaly_title_top + anomaly_title_height
            region = source.crop(
                (
                    0,
                    layout["anomalyGridTop"],
                    width,
                    layout["anomalyGridTop"] + anomaly_grid_height,
                )
            )
            canvas.paste(region, (0, anomaly_top))

        canvas.save(output_path, format="PNG", optimize=False, compress_level=9)

    return {
        "dimensions": [width, height],
        "allPassAnchorCount": len(pass_keys),
        "latestAdjustmentCount": len(latest_adjustment_keys),
        "allAnomalyCount": len(anomaly_keys),
        "selectedReviewKeys": sorted(set(pass_keys) | set(latest_adjustment_keys) | set(anomaly_keys)),
        "latestAdjustmentReviewKeys": sorted(latest_adjustment_keys),
    }


def verify_compact(manifest_path: Path) -> dict[str, Any]:
    manifest = base.load_json(manifest_path, "compact model atlas manifest")
    base.verify_digest(manifest, "manifestDigest", "compact model atlas manifest")
    envelope = manifest.get("sourceEnvelope")
    if not isinstance(envelope, dict) or base.sha256_bytes(base.stable_bytes(envelope)) != manifest.get("sourceDigest"):
        raise base.AtlasError("compact manifest sourceDigest 不匹配")
    calibration = manifest.get("humanPreferenceCalibration")
    if not isinstance(calibration, dict) or envelope.get("humanPreferenceCalibration") != calibration:
        raise base.AtlasError("compact calibration 顶层与 source envelope 漂移")
    retrieval = calibration.get("modelAtlasRetrieval")
    gates = retrieval.get("gates", {}) if isinstance(retrieval, dict) else {}
    required_true = (
        "fullHumanEvidenceBound",
        "aggregateStatisticsCoverAllHumanLabels",
        "allPassAnchorsIncluded",
        "latestReceiptAdjustmentsIncluded",
        "allAnomaliesIncluded",
        "visualExamplesRetrievedDeterministically",
        "fullAtlasNotTransmittedPerModelCall",
        "examplesAreNotCandidates",
    )
    if (
        not isinstance(retrieval, dict)
        or retrieval.get("schema") != SCHEMA
        or retrieval.get("mode") != MODE
        or any(gates.get(name) is not True for name in required_true)
        or gates.get("productionWrites") is not False
    ):
        raise base.AtlasError("compact model atlas retrieval gate 非法")
    for index, record in enumerate(envelope.get("sourceFiles", [])):
        base.verify_artifact(record, f"compact source file {index}")
    full_path = base.verify_artifact(calibration.get("atlas"), "complete human preference atlas")
    compact_path = base.verify_artifact(calibration.get("modelAtlas"), "compact model atlas")
    base.verify_artifact(retrieval.get("controllerSource"), "compact model atlas controller")
    base.verify_artifact(retrieval.get("parentManifest"), "compact parent manifest")
    base.verify_artifact(retrieval.get("latestHumanReviewReceipt"), "latest human review receipt")
    if retrieval.get("fullAtlas") != calibration.get("atlas") or full_path == compact_path:
        raise base.AtlasError("compact/full atlas 绑定漂移")
    with Image.open(full_path) as full_image, Image.open(compact_path) as compact_image:
        full_dimensions = list(full_image.size)
        compact_dimensions = list(compact_image.size)
    if (
        retrieval.get("fullAtlasDimensions") != full_dimensions
        or retrieval.get("modelAtlasDimensions") != compact_dimensions
        or retrieval.get("fullAtlasPatchCount") != patch_count(full_dimensions)
        or retrieval.get("modelAtlasPatchCount") != patch_count(compact_dimensions)
        or retrieval.get("modelAtlasPatchCount") >= retrieval.get("fullAtlasPatchCount")
    ):
        raise base.AtlasError("compact atlas 尺寸或 patch reduction 漂移")
    coverage = calibration.get("coverage", {})
    if (
        retrieval.get("allHumanLabelCount") != coverage.get("decisionCount")
        or retrieval.get("allPassAnchorCount") != coverage.get("passAnchorCount")
        or retrieval.get("allAnomalyCount") != coverage.get("anomalyCount")
        or len(retrieval.get("latestAdjustmentReviewKeys", [])) != retrieval.get("latestAdjustmentCount")
    ):
        raise base.AtlasError("compact retrieval 覆盖计数漂移")
    return {
        "status": "compact_model_atlas_verified",
        "manifest": base.repo_rel(manifest_path),
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "fullHumanLabels": retrieval["allHumanLabelCount"],
        "visualExamples": len(retrieval["selectedReviewKeys"]),
        "fullAtlasPatches": retrieval["fullAtlasPatchCount"],
        "modelAtlasPatches": retrieval["modelAtlasPatchCount"],
        "patchReductionFraction": retrieval["patchReductionFraction"],
        "productionReady": False,
    }


def derive(args: argparse.Namespace) -> None:
    parent_path = base.repo_path(args.manifest, "full atlas manifest")
    output_dir = base.repo_path(args.output, "output")
    try:
        output_dir.relative_to(base.PILOT_ROOT.resolve())
    except ValueError as error:
        raise base.AtlasError("output 必须位于 tmp/portrait-pilot") from error
    if output_dir.exists():
        raise base.AtlasError(f"输出目录已存在，禁止覆盖：{output_dir}")
    if not args.batch_id or len(args.batch_id) > 128 or not all(character.isalnum() or character in "._-" for character in args.batch_id):
        raise base.AtlasError("batch-id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")

    v3.verify_derived(parent_path)
    parent = base.load_json(parent_path, "full atlas manifest")
    calibration = parent["humanPreferenceCalibration"]
    reports = receipt_reports(calibration)
    decisions = base.decision_rows(reports)

    latest_path = base.repo_path(args.latest_human_review_receipt, "latest human review receipt")
    latest_report = base.load_json(latest_path, "latest human review receipt")
    base.verify_digest(latest_report, "receiptDigest", "latest human review receipt")
    latest_record = base.artifact(latest_path)
    if latest_record not in calibration["humanReviewReceipts"]:
        raise base.AtlasError("latest human review receipt 未进入完整人类证据闭包")
    latest_adjustment_keys = sorted(
        row["reviewKey"]
        for row in latest_report.get("decisions", [])
        if row.get("blocked") is False and row.get("status") == "adjustment"
    )
    if not latest_adjustment_keys:
        raise base.AtlasError("latest human review receipt 没有 adjustment")

    feedback_path = base.verify_artifact(calibration.get("feedbackReport"), "feedback report")
    feedback = base.load_json(feedback_path, "feedback report")
    base.verify_digest(feedback, "feedbackDigest", "feedback report")
    full_atlas_path = base.verify_artifact(calibration.get("atlas"), "complete human preference atlas")
    font_path = base.verify_font(parent)

    output_dir.mkdir(parents=True)
    compact_path = output_dir / "compact-feedback-model-atlas.png"
    view = draw_compact_atlas(compact_path, full_atlas_path, font_path, decisions, latest_adjustment_keys, feedback)
    compact_record = base.artifact(compact_path)
    full_dimensions = calibration["coverage"]["dimensions"]
    compact_dimensions = view["dimensions"]
    full_patches = patch_count(full_dimensions)
    compact_patches = patch_count(compact_dimensions)

    derived = copy.deepcopy(parent)
    derived.pop("manifestDigest", None)
    derived["batchId"] = args.batch_id
    derived["createdAt"] = base.utc_now()
    compact_calibration = copy.deepcopy(calibration)
    compact_calibration["modelAtlas"] = compact_record
    compact_calibration["modelAtlasRetrieval"] = {
        "schema": SCHEMA,
        "mode": MODE,
        "parentManifest": base.artifact(parent_path),
        "controllerSource": base.artifact(CONTROLLER_PATH),
        "latestHumanReviewReceipt": latest_record,
        "fullAtlas": calibration["atlas"],
        "fullAtlasDimensions": full_dimensions,
        "modelAtlasDimensions": compact_dimensions,
        "allHumanLabelCount": calibration["coverage"]["decisionCount"],
        "allPassAnchorCount": view["allPassAnchorCount"],
        "latestAdjustmentCount": view["latestAdjustmentCount"],
        "allAnomalyCount": view["allAnomalyCount"],
        "selectedReviewKeys": view["selectedReviewKeys"],
        "latestAdjustmentReviewKeys": view["latestAdjustmentReviewKeys"],
        "fullAtlasPatchCount": full_patches,
        "modelAtlasPatchCount": compact_patches,
        "patchReductionFraction": round(1 - compact_patches / full_patches, 6),
        "gates": {
            "fullHumanEvidenceBound": True,
            "aggregateStatisticsCoverAllHumanLabels": True,
            "allPassAnchorsIncluded": True,
            "latestReceiptAdjustmentsIncluded": True,
            "allAnomaliesIncluded": True,
            "visualExamplesRetrievedDeterministically": True,
            "fullAtlasNotTransmittedPerModelCall": True,
            "examplesAreNotCandidates": True,
            "productionWrites": False,
        },
    }
    source_files = list(derived["sourceEnvelope"].get("sourceFiles", []))
    seen = {record.get("path") for record in source_files if isinstance(record, dict)}
    for path in (parent_path, CONTROLLER_PATH, latest_path, compact_path):
        record = base.artifact(path)
        if record["path"] not in seen:
            source_files.append(record)
            seen.add(record["path"])
    derived["sourceEnvelope"]["batchId"] = args.batch_id
    derived["sourceEnvelope"]["sourceFiles"] = source_files
    derived["sourceEnvelope"]["humanPreferenceCalibration"] = compact_calibration
    derived["sourceDigest"] = base.sha256_bytes(base.stable_bytes(derived["sourceEnvelope"]))
    derived["humanPreferenceCalibration"] = compact_calibration
    derived["manifestDigest"] = base.sha256_bytes(base.stable_bytes(derived))
    manifest_path = output_dir / "candidate-manifest.json"
    base.write_json(manifest_path, derived)
    print(json.dumps(verify_compact(manifest_path), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_compact(base.repo_path(args.manifest, "compact model atlas manifest")), ensure_ascii=False))


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
        print(f"compact model atlas error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
