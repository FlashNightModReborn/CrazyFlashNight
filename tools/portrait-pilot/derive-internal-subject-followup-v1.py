#!/usr/bin/env python3
"""Derive a one-identity localization follow-up from a verified full rescue batch."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
REPORT_SCHEMA = "cf7.enemy-portrait-internal-subject-followup.v1"
RECONFIRM_SCHEMA = "cf7.enemy-portrait-internal-subject-reconfirmation-receipt.v1"


class FollowupError(core.PilotError):
    pass


def read_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise FollowupError(f"{label} 缺失：{path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise FollowupError(f"{label} 不是合法 JSON：{error}") from error
    if not isinstance(value, dict):
        raise FollowupError(f"{label} 顶层必须是对象")
    return value


def ensure_pilot_child(value: str, label: str, allow_existing: bool = False) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = ROOT / path
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise FollowupError(f"{label} 必须位于 tmp/portrait-pilot 下") from error
    if not relative.parts:
        raise FollowupError(f"{label} 不能是 tmp/portrait-pilot 根目录")
    if resolved.exists() and not allow_existing:
        raise FollowupError(f"{label} 已存在，禁止覆盖：{resolved}")
    return resolved


def resolve_repo(value: str, label: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = ROOT / path
    resolved = path.resolve()
    try:
        resolved.relative_to(ROOT)
    except ValueError as error:
        raise FollowupError(f"{label} 越出仓库：{resolved}") from error
    if not resolved.is_file():
        raise FollowupError(f"{label} 缺失：{resolved}")
    return resolved


def digest_object(value: dict[str, Any], field: str) -> str:
    envelope = copy.deepcopy(value)
    actual = envelope.pop(field, None)
    expected = core.sha256_bytes(core.stable_bytes(envelope))
    if actual != expected:
        raise FollowupError(f"{field} 不匹配")
    return expected


def run_parent_check(parent_root: Path) -> dict[str, Any]:
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools" / "portrait-pilot" / "prepare-internal-subject-localization-v1.py"),
            "check",
            "--output",
            core.repo_rel(parent_root),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=120,
    )
    if completed.returncode != 0:
        raise FollowupError(f"父批验证失败：{completed.stderr.strip() or completed.stdout.strip()}")
    try:
        result = json.loads(completed.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as error:
        raise FollowupError("父批验证没有返回合法 JSON") from error
    return result


def exact_row(rows: list[dict[str, Any]], key: str, value: str, label: str) -> dict[str, Any]:
    matches = [row for row in rows if row.get(key) == value]
    if len(matches) != 1:
        raise FollowupError(f"{label} 缺唯一 {key}={value}")
    return matches[0]


def verify_reconfirmation(path: Path, review_key: str) -> dict[str, Any]:
    receipt = read_json(path, "主体重选回执")
    digest_object(receipt, "receiptDigest")
    if (
        receipt.get("schema") != RECONFIRM_SCHEMA
        or receipt.get("status") != "human_subject_reconfirmation_recorded"
        or receipt.get("reviewKey") != review_key
        or receipt.get("gates", {}).get("productionWrites") is not False
    ):
        raise FollowupError("主体重选回执 schema、reviewKey 或 gate 非法")
    recorded = receipt.get("recordedDecision")
    selected = receipt.get("selectedCandidate")
    if (
        not isinstance(recorded, dict)
        or not isinstance(selected, dict)
        or recorded.get("decision") != "select"
        or recorded.get("candidateId") != selected.get("candidateId")
    ):
        raise FollowupError("主体重选回执没有冻结唯一候选")
    core.verify_artifact_record(receipt["output"]["canonicalDecisions"], "主体重选 canonical decisions")
    core.verify_artifact_record(receipt["output"]["archivedDecisions"], "主体重选 archive decisions")
    core.verify_artifact_record(selected["artifact"], "主体重选候选")
    return receipt


def source_swf(entity: dict[str, Any], item: dict[str, Any]) -> str | None:
    for value in (entity.get("sourceSwf"), item.get("sourceSwf")):
        if isinstance(value, str) and value:
            return value
    source = entity.get("source")
    if isinstance(source, dict):
        value = source.get("swf") or source.get("path")
        if isinstance(value, str) and value.endswith(".swf"):
            return value
    return None


def derive_manifest(
    parent: dict[str, Any],
    parent_path: Path,
    parent_lock_path: Path,
    receipt_path: Path,
    receipt: dict[str, Any],
    review_key: str,
    batch_id: str,
) -> dict[str, Any]:
    item = exact_row(parent.get("reviewItems", []), "reviewKey", review_key, "父 manifest reviewItems")
    if item.get("blocked") is not False or len(item.get("candidates", [])) != 1:
        raise FollowupError("follow-up 目标必须是一个 eligible 的单候选行")
    candidate = item["candidates"][0]
    selected_id = receipt["selectedCandidate"]["candidateId"]
    if candidate.get("candidateId") != selected_id or item.get("humanFeedback", {}).get("selectedCandidateId") != selected_id:
        raise FollowupError("父 manifest 没有消费当前主体重选候选")
    entity = exact_row(parent.get("entities", []), "entityCode", item.get("entityCode"), "父 manifest entities")
    parent_batch = next(
        (batch for batch in parent.get("modelBatches", []) if review_key in batch.get("reviewKeys", [])),
        None,
    )
    if not isinstance(parent_batch, dict):
        raise FollowupError("父 manifest modelBatches 没有覆盖 follow-up 行")

    manifest = copy.deepcopy(parent)
    manifest["batchId"] = batch_id
    manifest["createdAt"] = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    manifest["status"] = "human_internal_subject_single_identity_followup_localization_ready"
    manifest["reviewItems"] = [copy.deepcopy(item)]
    manifest["entities"] = [copy.deepcopy(entity)]
    manifest["counts"] = {
        "blockedReviewUnitCount": 0,
        "candidateCount": 1,
        "eligibleReviewUnitCount": 1,
        "entityCount": 1,
        "reviewUnitCount": 1,
    }
    swf = source_swf(entity, item)
    manifest["campaign"] = {
        **copy.deepcopy(parent.get("campaign", {})),
        "expectedModelJobs": 2,
        "identitiesPerSourceGroup": 1,
        "selectedPortraitRefs": [item["portraitRef"]],
        "selectedSourceCounts": {swf: 1} if swf else {},
        "selectionStrategy": "verified_human_internal_subject_single_identity_followup_localization_only",
        "shardSize": 1,
        "sourceGroups": 1,
    }
    model_batch_id = "internal-subject-followup-localization-01"
    manifest["modelBatches"] = [{
        "contactSheet": copy.deepcopy(parent_batch["contactSheet"]),
        "modelBatchId": model_batch_id,
        "reviewKeys": [review_key],
    }]
    calibration = manifest.get("humanPreferenceCalibration")
    if not isinstance(calibration, dict):
        raise FollowupError("父 manifest 缺人类偏好校准")
    bindings = [
        entry for entry in calibration.get("contactSheets", [])
        if entry.get("composite", {}).get("path") == parent_batch["contactSheet"]["path"]
        and entry.get("composite", {}).get("sha256") == parent_batch["contactSheet"]["sha256"]
    ]
    if len(bindings) != 1:
        raise FollowupError("父 manifest 缺唯一 contactSheet calibration binding")
    binding = copy.deepcopy(bindings[0])
    binding["modelBatchId"] = model_batch_id
    binding["purpose"] = "preflight_only_single_identity_localization_view_replaces_model_image"
    calibration["contactSheets"] = [binding]

    controller_record = core.artifact(Path(__file__))
    parent_record = core.artifact(parent_path)
    lock_record = core.artifact(parent_lock_path)
    receipt_record = core.artifact(receipt_path)
    envelope = manifest.get("sourceEnvelope")
    if not isinstance(envelope, dict):
        raise FollowupError("父 manifest 缺 sourceEnvelope")
    if core.sha256_bytes(core.stable_bytes(envelope)) != parent.get("sourceDigest"):
        raise FollowupError("父 manifest sourceEnvelope/sourceDigest 不匹配")
    manifest["followup"] = {
        "schema": REPORT_SCHEMA,
        "reviewKey": review_key,
        "selectedCandidateId": selected_id,
        "parentManifest": parent_record,
        "parentManifestDigest": parent["manifestDigest"],
        "parentSelectionLock": lock_record,
        "reconfirmationReceipt": receipt_record,
        "reconfirmationReceiptDigest": receipt["receiptDigest"],
    }
    manifest["gates"] = {
        **copy.deepcopy(parent.get("gates", {})),
        "singleIdentityFollowup": True,
        "exactReconfirmationReceiptBound": True,
        "otherParentRowsExcludedFromModel": True,
        "productionWrites": False,
    }
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    return manifest


def derive_lock(
    parent_lock: dict[str, Any],
    parent_lock_path: Path,
    parent_manifest_path: Path,
    manifest_path: Path,
    manifest: dict[str, Any],
    receipt_path: Path,
    receipt: dict[str, Any],
    review_key: str,
) -> dict[str, Any]:
    row = exact_row(parent_lock.get("rows", []), "reviewKey", review_key, "父 selection lock rows")
    if row.get("candidateId") != receipt["selectedCandidate"]["candidateId"]:
        raise FollowupError("父 selection lock 没有消费当前重选候选")
    lock = copy.deepcopy(parent_lock)
    lock["generatedAt"] = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    lock["controller"] = core.artifact(Path(__file__))
    lock["rows"] = [copy.deepcopy(row)]
    lock["counts"] = {
        "candidateAgreements": 1 if row.get("candidateAgreement") is True else 0,
        "humanGraphicDirectiveLocks": 0,
        "humanInternalSpriteLocks": 1,
        "rows": 1,
    }
    lock["input"] = {
        **copy.deepcopy(parent_lock.get("input", {})),
        "manifest": core.artifact(manifest_path),
        "manifestDigest": manifest["manifestDigest"],
        "parentManifest": core.artifact(parent_manifest_path),
        "parentManifestDigest": digest_object(read_json(parent_manifest_path, "父 manifest"), "manifestDigest"),
        "parentSelectionLock": core.artifact(parent_lock_path),
        "reconfirmationReceipt": core.artifact(receipt_path),
        "reconfirmationReceiptDigest": receipt["receiptDigest"],
    }
    lock["gates"] = {
        **copy.deepcopy(parent_lock.get("gates", {})),
        "singleIdentityFollowup": True,
        "exactReconfirmationReceiptBound": True,
        "otherParentRowsExcludedFromModel": True,
        "productionWrites": False,
    }
    lock.pop("selectionDigest", None)
    lock["selectionDigest"] = core.sha256_bytes(core.stable_bytes(lock))
    return lock


def verify_output(output_root: Path) -> dict[str, Any]:
    manifest_path = output_root / "candidate-manifest.json"
    lock_path = output_root / "selection-lock.json"
    report_path = output_root / "internal-subject-followup.json"
    manifest = read_json(manifest_path, "follow-up manifest")
    lock = read_json(lock_path, "follow-up selection lock")
    report = read_json(report_path, "follow-up report")
    digest_object(manifest, "manifestDigest")
    digest_object(lock, "selectionDigest")
    digest_object(report, "reportDigest")
    if core.sha256_bytes(core.stable_bytes(manifest.get("sourceEnvelope"))) != manifest.get("sourceDigest"):
        raise FollowupError("follow-up sourceEnvelope/sourceDigest 不匹配")
    if (
        manifest.get("status") != "human_internal_subject_single_identity_followup_localization_ready"
        or manifest.get("productionReady") is not False
        or manifest.get("counts") != {
            "blockedReviewUnitCount": 0,
            "candidateCount": 1,
            "eligibleReviewUnitCount": 1,
            "entityCount": 1,
            "reviewUnitCount": 1,
        }
        or len(manifest.get("reviewItems", [])) != 1
        or len(manifest.get("entities", [])) != 1
        or len(manifest.get("modelBatches", [])) != 1
        or len(lock.get("rows", [])) != 1
        or lock.get("counts", {}).get("rows") != 1
    ):
        raise FollowupError("follow-up manifest/lock 行数或状态非法")
    review_key = manifest["reviewItems"][0]["reviewKey"]
    if (
        manifest["modelBatches"][0].get("reviewKeys") != [review_key]
        or lock["rows"][0].get("reviewKey") != review_key
        or report.get("reviewKey") != review_key
        or manifest.get("gates", {}).get("otherParentRowsExcludedFromModel") is not True
        or lock.get("gates", {}).get("otherParentRowsExcludedFromModel") is not True
    ):
        raise FollowupError("follow-up reviewKey 闭包或隔离 gate 非法")
    candidate = manifest["reviewItems"][0]["candidates"][0]
    if candidate.get("candidateId") != lock["rows"][0].get("candidateId"):
        raise FollowupError("follow-up manifest 与 lock 候选不一致")
    for record, label in (
        (manifest["contactSheet"], "follow-up contact sheet"),
        (manifest["modelBatches"][0]["contactSheet"], "follow-up model sheet"),
        (candidate["artifact"], "follow-up candidate"),
        (candidate["vectorArtifact"], "follow-up vector candidate"),
        (lock["input"]["manifest"], "follow-up lock manifest"),
        (lock["input"]["reconfirmationReceipt"], "follow-up reconfirmation receipt"),
        (report["outputs"]["manifest"], "follow-up report manifest"),
        (report["outputs"]["selectionLock"], "follow-up report selection lock"),
    ):
        core.verify_artifact_record(record, label)
    return {
        "status": "internal_subject_single_identity_followup_verified",
        "reviewKey": review_key,
        "selectedCandidateId": candidate["candidateId"],
        "manifestDigest": manifest["manifestDigest"],
        "selectionDigest": lock["selectionDigest"],
        "reportDigest": report["reportDigest"],
        "productionWrites": False,
    }


def render(args: argparse.Namespace) -> None:
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.batch_id) is None:
        raise FollowupError("batch-id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    parent_root = ensure_pilot_child(args.parent_batch, "父批", allow_existing=True)
    output_root = ensure_pilot_child(args.output, "输出目录")
    parent_path = parent_root / "candidate-manifest.json"
    parent_lock_path = parent_root / "selection-lock.json"
    parent = read_json(parent_path, "父 manifest")
    parent_lock = read_json(parent_lock_path, "父 selection lock")
    parent_check = run_parent_check(parent_root)
    if parent_check.get("manifestDigest") != digest_object(parent, "manifestDigest"):
        raise FollowupError("父批 verifier 与 manifestDigest 不一致")
    digest_object(parent_lock, "selectionDigest")
    receipt_path = resolve_repo(args.reconfirmation_receipt, "主体重选回执")
    receipt = verify_reconfirmation(receipt_path, args.review_key)
    output_root.mkdir(parents=False)
    manifest_path = output_root / "candidate-manifest.json"
    lock_path = output_root / "selection-lock.json"
    manifest = derive_manifest(
        parent,
        parent_path,
        parent_lock_path,
        receipt_path,
        receipt,
        args.review_key,
        args.batch_id,
    )
    core.write_json(manifest_path, manifest)
    lock = derive_lock(
        parent_lock,
        parent_lock_path,
        parent_path,
        manifest_path,
        manifest,
        receipt_path,
        receipt,
        args.review_key,
    )
    core.write_json(lock_path, lock)
    report = {
        "schema": REPORT_SCHEMA,
        "status": "internal_subject_single_identity_followup_ready",
        "productionReady": False,
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "batchId": args.batch_id,
        "reviewKey": args.review_key,
        "selectedCandidateId": receipt["selectedCandidate"]["candidateId"],
        "parent": {
            "manifest": core.artifact(parent_path),
            "manifestDigest": parent["manifestDigest"],
            "selectionLock": core.artifact(parent_lock_path),
            "selectionDigest": parent_lock["selectionDigest"],
        },
        "reconfirmationReceipt": core.artifact(receipt_path),
        "reconfirmationReceiptDigest": receipt["receiptDigest"],
        "controller": core.artifact(Path(__file__)),
        "outputs": {
            "manifest": core.artifact(manifest_path),
            "selectionLock": core.artifact(lock_path),
        },
        "gates": {
            "exactHumanReconfirmationBound": True,
            "singleReviewKey": True,
            "otherParentRowsModelRerun": False,
            "localizationOnly": True,
            "productionWrites": False,
        },
    }
    report["reportDigest"] = core.sha256_bytes(core.stable_bytes(report))
    core.write_json(output_root / "internal-subject-followup.json", report)
    print(json.dumps(verify_output(output_root), ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    output_root = ensure_pilot_child(args.output, "输出目录", allow_existing=True)
    print(json.dumps(verify_output(output_root), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    render_parser = commands.add_parser("render")
    render_parser.add_argument("--parent-batch", required=True)
    render_parser.add_argument("--reconfirmation-receipt", required=True)
    render_parser.add_argument("--review-key", required=True)
    render_parser.add_argument("--output", required=True)
    render_parser.add_argument("--batch-id", required=True)
    render_parser.set_defaults(handler=render)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.set_defaults(handler=check)
    return result


def main() -> None:
    args = parser().parse_args()
    args.handler(args)


if __name__ == "__main__":
    try:
        main()
    except (FollowupError, core.PilotError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1)
