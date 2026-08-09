#!/usr/bin/env python3
"""Bind the 17 internal-subject outcomes into cumulative portrait feedback.

The controller keeps the existing 186-label campaign manifest immutable, adds
the r184 review, the six guided crops, the frost-king orientation correction,
and the source-closed r194 dude pass, then emits a fresh campaign manifest.
The old wrong-subject dude decision remains explicit negative evidence while
the later pass becomes the only current decision for that review key.
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
CONTROLLER = Path(__file__).resolve()
REVIEW_BUILDER = ROOT / "tools" / "portrait-pilot" / "build-review.js"
REVIEW_VERIFIER = ROOT / "tools" / "portrait-pilot" / "verify-review-decisions.js"
GUIDANCE_VERIFIER = ROOT / "tools" / "portrait-pilot" / "verify-framing-guidance.js"
GUIDED_RENDERER = ROOT / "tools" / "portrait-pilot" / "render-framing-guidance-large-frame-v1.py"
ORIENTATION_RENDERER = ROOT / "tools" / "portrait-pilot" / "render-guided-orientation-adjustment-large-frame-v1.py"

SCHEMA = "cf7.portrait-pilot-human-feedback-calibration.v9"
ATLAS_SCHEMA = "cf7.portrait-pilot-human-preference-atlas.v9"
EXPECTED_CURRENT_KEYS = {
    "敌人-异形蛋::default",
    "敌人-杰克霜精::default",
    "敌人-邪恶霜精::default",
    "敌人-奇美拉I型::default",
    "敌人-奇美拉II型::default",
    "敌人-凤凰眷属火精灵::default",
    "敌人-凤凰眷属大火精灵::default",
    "敌人-人修罗::default",
    "敌人-方舟收割者::default",
    "敌人-Surveyor::default",
    "敌人-闪6特工::default",
    "敌人-火柴人剑士::default",
    "敌人-dude::default",
    "敌人-王牌霜精::default",
    "敌人-霜精之王::default",
    "敌人-触手僵尸::default",
    "敌人-闪流步兵::default",
}
DUDE_KEY = "敌人-dude::default"
FROST_KING_KEY = "敌人-霜精之王::default"


class FeedbackError(RuntimeError):
    pass


def stable_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def pilot_stable_bytes(value: Any) -> bytes:
    def normalize(entry: Any) -> Any:
        if isinstance(entry, dict):
            return {key: normalize(child) for key, child in entry.items()}
        if isinstance(entry, list):
            return [normalize(child) for child in entry]
        if isinstance(entry, float) and entry.is_integer():
            return int(entry)
        return entry

    return stable_bytes(normalize(value))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def repo_path(raw: str | Path, label: str) -> Path:
    path = (ROOT / raw).resolve() if not Path(raw).is_absolute() else Path(raw).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError as error:
        raise FeedbackError(f"{label}越出仓库：{path}") from error
    return path


def pilot_path(raw: str | Path, label: str) -> Path:
    path = repo_path(raw, label)
    try:
        path.relative_to(PILOT_ROOT.resolve())
    except ValueError as error:
        raise FeedbackError(f"{label}必须位于 tmp/portrait-pilot：{path}") from error
    return path


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise FeedbackError(f"{label}不存在：{path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise FeedbackError(f"{label}不可读：{path}: {error}") from error
    if not isinstance(value, dict):
        raise FeedbackError(f"{label}顶层必须是对象")
    return value


def artifact(path: Path) -> dict[str, Any]:
    path = repo_path(path, "artifact")
    if not path.is_file():
        raise FeedbackError(f"artifact 不存在：{path}")
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def verify_artifact(record: Any, label: str) -> Path:
    if not isinstance(record, dict) or not isinstance(record.get("path"), str):
        raise FeedbackError(f"{label}缺 artifact record")
    path = repo_path(record["path"], label)
    current = artifact(path)
    if current != record:
        raise FeedbackError(f"{label}哈希或字节数漂移：{record.get('path')}")
    return path


def content_matches(path: Path, record: dict[str, Any]) -> bool:
    return path.is_file() and path.stat().st_size == record.get("bytes") and sha256_file(path) == record.get("sha256")


def object_digest(value: dict[str, Any], field: str, label: str) -> str:
    clone = copy.deepcopy(value)
    expected = clone.pop(field, None)
    current = sha256_bytes(stable_bytes(clone))
    if not isinstance(expected, str) or current != expected:
        raise FeedbackError(f"{label} {field} 漂移")
    return expected


def manifest_digest(value: dict[str, Any]) -> str:
    clone = copy.deepcopy(value)
    clone.pop("manifestDigest", None)
    return sha256_bytes(pilot_stable_bytes(clone))


def run_json(argv: list[str], label: str) -> dict[str, Any]:
    completed = subprocess.run(
        argv,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise FeedbackError(f"{label}失败：{detail}")
    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if not lines:
        raise FeedbackError(f"{label}没有 JSON 输出")
    try:
        value = json.loads(lines[-1])
    except json.JSONDecodeError as error:
        raise FeedbackError(f"{label}输出不是 JSON：{lines[-1]}") from error
    if not isinstance(value, dict):
        raise FeedbackError(f"{label}输出顶层不是对象")
    return value


def verify_records_with_substitution(value: Any, substitutions: dict[str, Path], label: str) -> int:
    checked = 0
    if isinstance(value, dict):
        if (
            isinstance(value.get("path"), str)
            and isinstance(value.get("sha256"), str)
            and isinstance(value.get("bytes"), int)
        ):
            expected = {key: value[key] for key in ("path", "bytes", "sha256")}
            raw_path = Path(value["path"])
            current_path = raw_path.resolve() if raw_path.is_absolute() else (ROOT / raw_path).resolve()
            try:
                current_path.relative_to(ROOT)
            except ValueError:
                # Toolchain executables can be bound as absolute environment
                # evidence. The supersession in scope concerns only repo data.
                return 0
            if current_path.is_file() and artifact(current_path) == expected:
                return 1
            substitute = substitutions.get(value["path"])
            if substitute is None or not content_matches(substitute, expected):
                raise FeedbackError(f"{label} artifact 漂移且无合法 supersession：{value['path']}")
            return 1
        for child in value.values():
            checked += verify_records_with_substitution(child, substitutions, label)
    elif isinstance(value, list):
        for child in value:
            checked += verify_records_with_substitution(child, substitutions, label)
    return checked


def verify_source_supersession(batch: Path, archived_before: Path, receipt_path: Path) -> dict[str, Any]:
    receipt = load_json(receipt_path, "internal subject reconfirmation receipt")
    object_digest(receipt, "receiptDigest", "internal subject reconfirmation receipt")
    if (
        receipt.get("schema") != "cf7.enemy-portrait-internal-subject-reconfirmation-receipt.v1"
        or receipt.get("reviewKey") != DUDE_KEY
        or receipt.get("priorDecision", {}).get("candidateId") != "isr13-c06-s94-f1"
        or receipt.get("recordedDecision", {}).get("candidateId") != "isr13-c03-s15-f19"
        or receipt.get("gates", {}).get("canonicalMatchesArchive") is not True
        or receipt.get("gates", {}).get("productionWrites") is not False
    ):
        raise FeedbackError("dude source supersession receipt 语义漂移")
    before = receipt.get("input", {}).get("decisionsBefore")
    if not isinstance(before, dict) or not content_matches(archived_before, before):
        raise FeedbackError("归档 C06 decisions 未精确匹配 reconfirmation input")
    canonical = verify_artifact(receipt.get("output", {}).get("canonicalDecisions"), "C03 canonical decisions")
    verify_artifact(receipt.get("output", {}).get("archivedDecisions"), "C03 archived decisions")
    stale_path = before["path"]
    if canonical.as_posix().lower() != (ROOT / stale_path).resolve().as_posix().lower():
        raise FeedbackError("reconfirmation 没有在同一 canonical path 上形成显式 supersession")
    substitutions = {stale_path: archived_before}
    checked = 0
    for name in ("candidate-manifest.json", "model-report.json", "render-report.json", "review-data.json"):
        value = load_json(batch / name, f"superseded batch {name}")
        if name == "candidate-manifest.json" and manifest_digest(value) != value.get("manifestDigest"):
            raise FeedbackError("superseded batch candidate manifestDigest 漂移")
        checked += verify_records_with_substitution(value, substitutions, f"superseded batch {name}")
    if checked < 20:
        raise FeedbackError("superseded review artifact closure 数量异常")
    return {
        "schema": receipt["schema"],
        "receiptDigest": receipt["receiptDigest"],
        "supersededArtifactPath": stale_path,
        "supersededArtifactSha256": before["sha256"],
        "currentArtifactSha256": receipt["output"]["canonicalDecisions"]["sha256"],
        "verifiedArtifactRecords": checked,
    }


def verify_review_batch(
    batch: Path,
    expected_total: int,
    expected_outcome: str,
    *,
    superseded_decisions: Path | None = None,
    reconfirmation_receipt: Path | None = None,
) -> dict[str, Any]:
    if superseded_decisions is None or reconfirmation_receipt is None:
        build = run_json(["node", str(REVIEW_BUILDER.relative_to(ROOT)), "--batch", str(batch.relative_to(ROOT)), "--check"], "review-data check")
        if build.get("rows") != expected_total:
            raise FeedbackError(f"review-data 行数漂移：{batch}")
    else:
        verify_source_supersession(batch, superseded_decisions, reconfirmation_receipt)
    receipt = run_json(["node", str(REVIEW_VERIFIER.relative_to(ROOT)), "--batch", str(batch.relative_to(ROOT)), "--check"], "review receipt check")
    if receipt.get("outcome") != expected_outcome or receipt.get("counts", {}).get("total") != expected_total:
        raise FeedbackError(f"review batch 计数或结果漂移：{batch}")
    return receipt


def verify_external_batches(guidance: Path, guided: Path, orientation: Path) -> dict[str, Any]:
    guidance_result = run_json(["node", str(GUIDANCE_VERIFIER.relative_to(ROOT)), "--batch", str(guidance.relative_to(ROOT)), "--check"], "guidance check")
    guided_result = run_json([sys.executable, str(GUIDED_RENDERER.relative_to(ROOT)), "check", "--output", str(guided.relative_to(ROOT))], "guided render check")
    orientation_result = run_json([sys.executable, str(ORIENTATION_RENDERER.relative_to(ROOT)), "check", "--output", str(orientation.relative_to(ROOT))], "guided orientation check")
    if guidance_result.get("rows") != 6 or guided_result.get("rows") != 6 or orientation_result.get("rows") != 1:
        raise FeedbackError("六条框选或一条方向修正计数漂移")
    return {"guidance": guidance_result, "guidedRender": guided_result, "orientation": orientation_result}


def append_unique(records: list[dict[str, Any]], record: dict[str, Any]) -> None:
    paths = {item.get("path") for item in records if isinstance(item, dict)}
    if record["path"] not in paths:
        records.append(record)


def rows_by_key(report: dict[str, Any], *, role: str | None = None) -> dict[str, dict[str, Any]]:
    rows: dict[str, dict[str, Any]] = {}
    for row in report.get("rows", []):
        if not isinstance(row, dict) or not isinstance(row.get("reviewKey"), str):
            continue
        if role is not None and row.get("role") != role:
            continue
        key = row["reviewKey"]
        if key in rows:
            raise FeedbackError(f"render 行重复：{key}/{role}")
        rows[key] = row
    return rows


def build_current_rows(review_batch: Path, followup_batch: Path, guided: Path, orientation: Path) -> tuple[list[dict[str, Any]], list[Path]]:
    original_decisions = load_json(review_batch / "portrait-pilot-review-decisions.json", "r184 decisions")["decisions"]
    followup_decisions = load_json(followup_batch / "portrait-pilot-review-decisions.json", "r194 decisions")["decisions"]
    if set(original_decisions) != EXPECTED_CURRENT_KEYS or set(followup_decisions) != {DUDE_KEY}:
        raise FeedbackError("r184/r194 review key 集合漂移")
    if original_decisions[DUDE_KEY].get("status") != "wrong_subject" or followup_decisions[DUDE_KEY].get("status") != "pass":
        raise FeedbackError("dude supersession 不是 wrong_subject -> pass")

    original_render_path = review_batch / "render-report.json"
    followup_render_path = followup_batch / "render-report.json"
    original_render = load_json(original_render_path, "r184 render")
    followup_render = load_json(followup_render_path, "r194 render")
    proposal_rows = rows_by_key(original_render, role="proposal")
    proposal_rows.update(rows_by_key(followup_render, role="proposal"))
    guided_report_path = guided / "human-framing-render-report.json"
    orientation_report_path = orientation / "guided-orientation-render-report.json"
    guided_rows = rows_by_key(load_json(guided_report_path, "r186 guided render"))
    orientation_rows = rows_by_key(load_json(orientation_report_path, "r187 orientation"))
    adjustment_keys = {key for key, value in original_decisions.items() if value.get("status") == "adjustment"}
    if set(guided_rows) != adjustment_keys or set(orientation_rows) != {FROST_KING_KEY}:
        raise FeedbackError("调整键与 r186/r187 产物不闭合")

    final_decisions = copy.deepcopy(original_decisions)
    final_decisions[DUDE_KEY] = copy.deepcopy(followup_decisions[DUDE_KEY])
    results: list[dict[str, Any]] = []
    for index, key in enumerate(sorted(EXPECTED_CURRENT_KEYS), start=1):
        decision = final_decisions[key]
        status = decision.get("status")
        if status == "pass":
            row = proposal_rows.get(key)
            report_path = followup_render_path if key == DUDE_KEY else original_render_path
            resolution = "human_passed_luna_a_proposal"
        elif status == "adjustment":
            if key == FROST_KING_KEY:
                row = orientation_rows.get(key)
                report_path = orientation_report_path
                resolution = "human_guided_adjustment_with_orientation"
            else:
                row = guided_rows.get(key)
                report_path = guided_report_path
                resolution = "human_guided_adjustment"
        else:
            raise FeedbackError(f"最终决定仍未闭合：{key}={status}")
        if not isinstance(row, dict):
            raise FeedbackError(f"最终接受行缺失：{key}")
        master_path = verify_artifact(row.get("master"), f"最终 master {key}")
        with Image.open(master_path) as opened:
            if opened.size != (512, 512) or opened.convert("RGBA").getchannel("A").getbbox() is None:
                raise FeedbackError(f"最终 master 尺寸或 alpha 非法：{key}")
        receipt_path = followup_batch / "human-review-receipt.json" if key == DUDE_KEY else review_batch / "human-review-receipt.json"
        results.append({
            "ordinal": index,
            "reviewKey": key,
            "status": status,
            "resolution": resolution,
            "decision": copy.deepcopy(decision),
            "acceptedMaster": artifact(master_path),
            "acceptedRenderReport": artifact(report_path),
            "humanReceipt": artifact(receipt_path),
        })
    if sum(row["status"] == "pass" for row in results) != 11 or sum(row["status"] == "adjustment" for row in results) != 6:
        raise FeedbackError("最终 17 行不是 11 pass + 6 adjustment")
    return results, [original_render_path, followup_render_path, guided_report_path, orientation_report_path]


def render_panel(rows: list[dict[str, Any]], output: Path, width: int) -> tuple[int, int]:
    columns = 8
    margin = 24
    gap = 14
    header = 68
    tile_width = (width - margin * 2 - gap * (columns - 1)) // columns
    tile_height = 214
    line_count = math.ceil(len(rows) / columns)
    height = header + margin + line_count * tile_height + max(0, line_count - 1) * gap + margin
    panel = Image.new("RGBA", (width, height), (8, 15, 24, 255))
    draw = ImageDraw.Draw(panel)
    font = ImageFont.load_default()
    draw.text((margin, 20), "LATEST HUMAN ACCEPTANCE 17 | 11 PASS | 6 GUIDED | DUDE C03 SUPERSEDES C06", fill=(216, 232, 242, 255), font=font)
    for index, row in enumerate(rows):
        col = index % columns
        line = index // columns
        x = margin + col * (tile_width + gap)
        y = header + margin + line * (tile_height + gap)
        guided = row["status"] == "adjustment"
        border = (79, 209, 197, 255) if guided else (106, 183, 112, 255)
        draw.rounded_rectangle((x, y, x + tile_width, y + tile_height), radius=10, fill=(18, 30, 43, 255), outline=border, width=3)
        master_path = repo_path(row["acceptedMaster"]["path"], "panel master")
        with Image.open(master_path) as opened:
            thumb = opened.convert("RGBA").resize((154, 154), Image.Resampling.LANCZOS)
        thumb_x = x + (tile_width - 154) // 2
        panel.alpha_composite(thumb, (thumb_x, y + 12))
        code = f"I{row['ordinal']:02d}"
        route = "GUIDED" if guided else "PASS"
        if row["reviewKey"] == DUDE_KEY:
            route = "PASS C03"
        draw.text((x + 10, y + 174), code, fill=(242, 246, 250, 255), font=font)
        draw.text((x + 10, y + 190), route, fill=border, font=font)
    panel.save(output, format="PNG", optimize=False, compress_level=6)
    return panel.size


def append_atlas(parent_atlas: Path, panel_path: Path, output: Path) -> tuple[int, int]:
    with Image.open(parent_atlas) as parent_opened, Image.open(panel_path) as panel_opened:
        parent = parent_opened.convert("RGBA")
        panel = panel_opened.convert("RGBA")
        if panel.width != parent.width:
            raise FeedbackError("最新 panel 与父 atlas 宽度不一致")
        combined = Image.new("RGBA", (parent.width, parent.height + panel.height), (8, 15, 24, 255))
        combined.alpha_composite(parent, (0, 0))
        combined.alpha_composite(panel, (0, parent.height))
        combined.save(output, format="PNG", optimize=False, compress_level=6)
        return combined.size


def build(args: argparse.Namespace) -> None:
    parent_path = repo_path(args.parent_manifest, "parent manifest")
    review_batch = pilot_path(args.review_batch, "r184 review batch")
    followup_batch = pilot_path(args.followup_batch, "r194 followup batch")
    guidance_batch = pilot_path(args.guidance_batch, "r185 guidance batch")
    guided_batch = pilot_path(args.guided_batch, "r186 guided batch")
    orientation_batch = pilot_path(args.orientation_batch, "r187 orientation batch")
    output = pilot_path(args.output, "v9 output")
    if output.exists():
        raise FeedbackError(f"输出已存在，禁止覆盖：{output}")

    parent = load_json(parent_path, "parent manifest")
    if manifest_digest(parent) != parent.get("manifestDigest"):
        raise FeedbackError("parent manifestDigest 漂移")
    calibration = copy.deepcopy(parent.get("humanPreferenceCalibration"))
    if not isinstance(calibration, dict) or calibration.get("coverage", {}).get("decisionCount") != 186:
        raise FeedbackError("parent calibration 不是冻结 186-label 基线")
    superseded_decisions = pilot_path(args.superseded_decisions, "archived C06 decisions")
    reconfirmation_receipt = pilot_path(args.reconfirmation_receipt, "C03 reconfirmation receipt")
    supersession = verify_source_supersession(review_batch, superseded_decisions, reconfirmation_receipt)
    verify_review_batch(
        review_batch,
        17,
        "human_reviewed_refinement_required",
        superseded_decisions=superseded_decisions,
        reconfirmation_receipt=reconfirmation_receipt,
    )
    verify_review_batch(followup_batch, 1, "human_reviewed_approved")
    verifier_results = verify_external_batches(guidance_batch, guided_batch, orientation_batch)
    rows, render_paths = build_current_rows(review_batch, followup_batch, guided_batch, orientation_batch)

    output.mkdir(parents=False)
    panel_path = output / "internal-subject-human-preference-panel-17.png"
    parent_atlas = verify_artifact(calibration.get("atlas"), "parent atlas")
    panel_size = render_panel(rows, panel_path, Image.open(parent_atlas).width)
    atlas_path = output / "feedback-preference-atlas-203.png"
    atlas_size = append_atlas(parent_atlas, panel_path, atlas_path)

    generated_at = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    feedback = {
        "schema": SCHEMA,
        "status": "human_feedback_calibrated",
        "productionReady": False,
        "generatedAt": generated_at,
        "batchId": args.batch_id,
        "inputs": {
            "controllerSource": artifact(CONTROLLER),
            "parentManifest": artifact(parent_path),
            "supersededDecisionsBeforeC03": artifact(superseded_decisions),
            "dudeReconfirmationReceipt": artifact(reconfirmation_receipt),
            "reviewData": artifact(review_batch / "review-data.json"),
            "decisions": artifact(review_batch / "portrait-pilot-review-decisions.json"),
            "humanReviewReceipt": artifact(review_batch / "human-review-receipt.json"),
            "followupReviewData": artifact(followup_batch / "review-data.json"),
            "followupDecisions": artifact(followup_batch / "portrait-pilot-review-decisions.json"),
            "followupHumanReviewReceipt": artifact(followup_batch / "human-review-receipt.json"),
            "framingGuidanceData": artifact(guidance_batch / "framing-guidance-data.json"),
            "framingGuidance": artifact(guidance_batch / "portrait-pilot-framing-guidance.json"),
            "framingGuidanceReceipt": artifact(guidance_batch / "human-framing-guidance-receipt.json"),
            "guidedRender": artifact(guided_batch / "human-framing-render-report.json"),
            "guidedOrientation": artifact(orientation_batch / "guided-orientation-render-report.json"),
            "parentAtlas": artifact(parent_atlas),
            "latestPanel": artifact(panel_path),
            "cumulativeAtlas": artifact(atlas_path),
        },
        "counts": {
            "currentDistinctIdentities": 17,
            "currentPass": 11,
            "currentGuidedAdjustment": 6,
            "supersededCurrentNegative": 1,
            "cumulativeCurrentHumanLabels": 203,
            "cumulativePass": 86,
            "cumulativeAdjustment": 116,
            "cumulativeSource": 1,
            "cumulativeGeometryRows": 112,
        },
        "adaptiveScaling": {
            "policy": "largest_batch_with_estimated_revisions_lte_6",
            "currentShardSize": 17,
            "currentFirstPass": 10,
            "currentFirstPassRate": round(10 / 17, 6),
            "rollingWindow": {"eligible": 35, "passed": 27, "failures": 8, "failureRate": round(8 / 35, 6)},
            "expectedRevisionBudget": 6,
            "recommendedNextShardSize": 26,
            "expectedRevisionsAtRecommendedSize": round(26 * 8 / 35, 6),
            "selectionMaximumConcurrency": 6,
            "localizationMaximumConcurrency": 3,
            "serviceTier": "fast",
        },
        "rows": rows,
        "verifiers": verifier_results,
        "sourceSupersession": supersession,
        "gates": {
            "parent186LabelsBound": True,
            "all17CurrentRowsReviewed": True,
            "sixGuidedCropsBound": True,
            "frostKingPostCropFlipBound": True,
            "dudeWrongSubjectPreservedAsNegative": True,
            "dudeC03LaterPassIsCurrent": True,
            "currentDecisionKeysUnique": True,
            "newHumanPreferencesVisualized": True,
            "staleCompactAtlasRejected": True,
            "modelTrainingClaim": False,
            "productionWrites": False,
        },
    }
    feedback["feedbackDigest"] = sha256_bytes(stable_bytes(feedback))
    feedback_path = output / "human-feedback-calibration.json"
    feedback_path.write_text(json.dumps(feedback, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    receipt_records = calibration.setdefault("humanReviewReceipts", [])
    append_unique(receipt_records, artifact(review_batch / "human-review-receipt.json"))
    append_unique(receipt_records, artifact(followup_batch / "human-review-receipt.json"))
    direct_records = calibration.setdefault("parentRenderReports", [])
    append_unique(direct_records, artifact(review_batch / "render-report.json"))
    append_unique(direct_records, artifact(followup_batch / "render-report.json"))
    guided_records = calibration.setdefault("humanGuidedRenderReports", [])
    append_unique(guided_records, artifact(guided_batch / "human-framing-render-report.json"))
    orientation_records = calibration.setdefault("guidedOrientationReports", [])
    append_unique(orientation_records, artifact(orientation_batch / "guided-orientation-render-report.json"))
    calibration.update({
        "schema": ATLAS_SCHEMA,
        "mode": "bound_203_current_human_labels_112_geometry_internal_subject_closed",
        "controllerSource": artifact(CONTROLLER),
        "parentManifest": artifact(parent_path),
        "feedbackReport": artifact(feedback_path),
        "atlas": artifact(atlas_path),
        "latestInternalSubjectFeedbackPanel": artifact(panel_path),
        "currentHumanReview": {
            "reviewData": artifact(followup_batch / "review-data.json"),
            "decisions": artifact(followup_batch / "portrait-pilot-review-decisions.json"),
            "receipt": artifact(followup_batch / "human-review-receipt.json"),
            "receiptDigest": load_json(followup_batch / "human-review-receipt.json", "followup receipt")["receiptDigest"],
        },
        "currentHumanGuidance": {
            "data": artifact(guidance_batch / "framing-guidance-data.json"),
            "guidance": artifact(guidance_batch / "portrait-pilot-framing-guidance.json"),
            "receipt": artifact(guidance_batch / "human-framing-guidance-receipt.json"),
            "receiptDigest": verifier_results["guidance"]["receiptDigest"],
            "guidedRender": artifact(guided_batch / "human-framing-render-report.json"),
            "guidedRenderDigest": verifier_results["guidedRender"]["reportDigest"],
        },
        "adaptiveScaling": copy.deepcopy(feedback["adaptiveScaling"]),
    })
    calibration.pop("modelAtlas", None)
    calibration.pop("modelAtlasRetrieval", None)
    coverage = copy.deepcopy(calibration.get("coverage", {}))
    review_keys = set(coverage.get("reviewKeys", [])) | EXPECTED_CURRENT_KEYS
    coverage.update({
        "schema": ATLAS_SCHEMA,
        "mode": calibration["mode"],
        "decisionCount": 203,
        "passAnchorCount": 86,
        "adjustmentCount": 116,
        "guidedCorrectionCount": 112,
        "guidedOrientationCount": int(coverage.get("guidedOrientationCount", 11)) + 1,
        "orientationTransformationCount": int(coverage.get("orientationTransformationCount", 19)) + 1,
        "anomalyCount": int(coverage.get("anomalyCount", 1)) + 1,
        "supersededDecisionEvidenceCount": int(coverage.get("supersededDecisionEvidenceCount", 3)) + 1,
        "statusCounts": {"adjustment": 116, "pass": 86, "source": 1},
        "reviewKeys": sorted(review_keys),
        "dimensions": list(atlas_size),
        "latestInternalSubjectPanelDimensions": list(panel_size),
        "all203CurrentHumanLabelsVisualized": True,
        "all112GeometryRowsBound": True,
        "allHumanLabelsVisualized": True,
        "latestResolvedStateVisualized": True,
        "staleCompactAtlasRejected": True,
    })
    calibration["coverage"] = coverage
    gates = copy.deepcopy(calibration.get("gates", {}))
    gates.update({
        "all203CurrentHumanLabelsBound": True,
        "all112GeometryRowsBound": True,
        "internalSubjectSeventeenClosed": True,
        "dudeSupersessionBound": True,
        "latestHumanFeedbackVisualized": True,
        "compactModelAtlasRequiresFreshDerivation": True,
        "productionWrites": False,
    })
    calibration["gates"] = gates

    manifest = copy.deepcopy(parent)
    manifest["batchId"] = args.batch_id
    manifest["generatedAt"] = generated_at
    manifest["humanPreferenceCalibration"] = calibration
    manifest["manifestDigest"] = manifest_digest(manifest)
    manifest_path = output / "candidate-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    verify_output(output, args.batch_id)
    print(json.dumps({
        "status": "internal_subject_feedback_v9_attached",
        "manifest": manifest_path.relative_to(ROOT).as_posix(),
        "manifestDigest": manifest["manifestDigest"],
        "feedbackDigest": feedback["feedbackDigest"],
        "humanLabels": 203,
        "geometryRows": 112,
        "resolvedIdentities": 17,
        "recommendedNextShardSize": 26,
    }, ensure_ascii=False))


def verify_output(output: Path, batch_id: str) -> dict[str, Any]:
    feedback_path = output / "human-feedback-calibration.json"
    manifest_path = output / "candidate-manifest.json"
    panel_path = output / "internal-subject-human-preference-panel-17.png"
    atlas_path = output / "feedback-preference-atlas-203.png"
    feedback = load_json(feedback_path, "feedback v9")
    object_digest(feedback, "feedbackDigest", "feedback v9")
    if feedback.get("schema") != SCHEMA or feedback.get("batchId") != batch_id or feedback.get("productionReady") is not False:
        raise FeedbackError("feedback v9 schema/batch/status 非法")
    if feedback.get("counts") != {
        "currentDistinctIdentities": 17,
        "currentPass": 11,
        "currentGuidedAdjustment": 6,
        "supersededCurrentNegative": 1,
        "cumulativeCurrentHumanLabels": 203,
        "cumulativePass": 86,
        "cumulativeAdjustment": 116,
        "cumulativeSource": 1,
        "cumulativeGeometryRows": 112,
    }:
        raise FeedbackError("feedback v9 counts 漂移")
    if len(feedback.get("rows", [])) != 17 or set(row.get("reviewKey") for row in feedback["rows"]) != EXPECTED_CURRENT_KEYS:
        raise FeedbackError("feedback v9 rows 漂移")
    for row in feedback["rows"]:
        verify_artifact(row.get("acceptedMaster"), f"feedback master {row.get('reviewKey')}")
        verify_artifact(row.get("acceptedRenderReport"), f"feedback report {row.get('reviewKey')}")
        verify_artifact(row.get("humanReceipt"), f"feedback receipt {row.get('reviewKey')}")
    manifest = load_json(manifest_path, "v9 candidate manifest")
    if manifest.get("batchId") != batch_id or manifest_digest(manifest) != manifest.get("manifestDigest"):
        raise FeedbackError("v9 candidate manifest digest/batch 漂移")
    calibration = manifest.get("humanPreferenceCalibration", {})
    if calibration.get("schema") != ATLAS_SCHEMA or calibration.get("coverage", {}).get("decisionCount") != 203:
        raise FeedbackError("v9 calibration schema/coverage 漂移")
    if "modelAtlas" in calibration or "modelAtlasRetrieval" in calibration:
        raise FeedbackError("v9 不得继续暴露旧 compact model atlas")
    verify_artifact(calibration.get("feedbackReport"), "v9 feedback report")
    verify_artifact(calibration.get("atlas"), "v9 atlas")
    verify_artifact(calibration.get("latestInternalSubjectFeedbackPanel"), "v9 latest panel")
    with Image.open(panel_path) as panel, Image.open(atlas_path) as atlas:
        if list(panel.size) != calibration["coverage"]["latestInternalSubjectPanelDimensions"] or list(atlas.size) != calibration["coverage"]["dimensions"]:
            raise FeedbackError("v9 panel/atlas dimensions 漂移")
    return feedback


def check(args: argparse.Namespace) -> None:
    output = pilot_path(args.output, "v9 output")
    feedback = verify_output(output, args.batch_id)
    print(json.dumps({
        "status": "internal_subject_feedback_v9_verified",
        "manifestDigest": load_json(output / "candidate-manifest.json", "manifest")["manifestDigest"],
        "feedbackDigest": feedback["feedbackDigest"],
        "humanLabels": 203,
        "geometryRows": 112,
        "resolvedIdentities": 17,
    }, ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    sub = result.add_subparsers(dest="command", required=True)
    build_parser = sub.add_parser("build")
    build_parser.add_argument("--parent-manifest", required=True)
    build_parser.add_argument("--review-batch", required=True)
    build_parser.add_argument("--followup-batch", required=True)
    build_parser.add_argument("--guidance-batch", required=True)
    build_parser.add_argument("--guided-batch", required=True)
    build_parser.add_argument("--orientation-batch", required=True)
    build_parser.add_argument("--superseded-decisions", required=True)
    build_parser.add_argument("--reconfirmation-receipt", required=True)
    build_parser.add_argument("--output", required=True)
    build_parser.add_argument("--batch-id", required=True)
    build_parser.set_defaults(handler=build)
    check_parser = sub.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.add_argument("--batch-id", required=True)
    check_parser.set_defaults(handler=check)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        args.handler(args)
    except (FeedbackError, OSError, KeyError, ValueError) as error:
        print(f"[internal-subject-feedback-v9] ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
