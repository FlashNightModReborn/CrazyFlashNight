#!/usr/bin/env python3
"""Resolve a human-review follow-up without losing the superseded negative evidence."""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any


CONTROLLER_PATH = Path(__file__).resolve()
BASE_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas.py")
REPORT_SCHEMA = "cf7.portrait-pilot-human-review-supersession.v1"
RECEIPT_SCHEMA = "cf7.portrait-pilot-human-review-receipt.v1"
RENDER_SCHEMA = "cf7.portrait-pilot-resolved-parent-render-report.v1"
STATUSES = ("pass", "adjustment", "wrong_pose", "wrong_subject", "source", "variant_mismatch")


def load_base():
    spec = importlib.util.spec_from_file_location("cf7_portrait_feedback_atlas_base", BASE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 atlas 基础控制器：{BASE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_base()


def load_bound_json(raw_path: str | Path, digest_field: str, label: str) -> tuple[Path, dict[str, Any]]:
    path = base.repo_path(raw_path, label)
    value = base.load_json(path, label)
    base.verify_digest(value, digest_field, label)
    return path, value


def validate_receipt(receipt: dict[str, Any], label: str) -> None:
    decisions = receipt.get("decisions")
    if (
        receipt.get("schema") != RECEIPT_SCHEMA
        or receipt.get("productionReady") is not False
        or not isinstance(decisions, list)
        or receipt.get("counts", {}).get("total") != len(decisions)
    ):
        raise base.AtlasError(f"{label} gate 非法")
    seen: set[str] = set()
    for row in decisions:
        key = row.get("reviewKey")
        if (
            not isinstance(key, str)
            or key in seen
            or row.get("status") not in STATUSES
            or row.get("blocked") is not False
            or not isinstance(row.get("notes"), str)
        ):
            raise base.AtlasError(f"{label} decision 非法或重复：{key}")
        if row["status"] != "pass" and not row["notes"].strip():
            raise base.AtlasError(f"{label} 非通过决定缺备注：{key}")
        seen.add(key)


def validate_render(report: dict[str, Any], label: str) -> None:
    if report.get("status") != "automated_checked" or report.get("productionReady") is not False:
        raise base.AtlasError(f"{label} gate 非法")
    seen: set[tuple[str, str]] = set()
    for row in report.get("rows", []):
        key = (row.get("reviewKey"), row.get("role"))
        if not all(isinstance(part, str) for part in key) or key in seen:
            raise base.AtlasError(f"{label} row 非法或重复：{key}")
        base.verify_artifact(row.get("master"), f"{label} master {key}")
        seen.add(key)


def decision_map(receipt: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {row["reviewKey"]: copy.deepcopy(row) for row in receipt["decisions"]}


def render_map(report: dict[str, Any]) -> dict[tuple[str, str], dict[str, Any]]:
    return {(row["reviewKey"], row["role"]): copy.deepcopy(row) for row in report["rows"]}


def counts_for(decisions: list[dict[str, Any]]) -> dict[str, Any]:
    status_counts = {status: 0 for status in STATUSES}
    for row in decisions:
        status_counts[row["status"]] += 1
    return {
        "total": len(decisions),
        "eligible": len(decisions),
        "eligiblePassed": status_counts["pass"],
        "blocked": 0,
        "statuses": status_counts,
    }


def row_evidence(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    evidence: list[dict[str, Any]] = []
    for row in sorted(rows, key=lambda item: item["role"]):
        evidence.append(
            {
                "reviewKey": row["reviewKey"],
                "role": row["role"],
                "candidateId": row.get("candidateId"),
                "frame": row.get("frame"),
                "featureLabel": row.get("featureLabel"),
                "framingMode": row.get("framingMode"),
                "master": copy.deepcopy(row["master"]),
            }
        )
    return evidence


def build(args: argparse.Namespace) -> None:
    output = base.repo_path(args.output, "supersession 输出")
    try:
        output.relative_to(base.PILOT_ROOT.resolve())
    except ValueError as error:
        raise base.AtlasError("supersession 输出必须位于 tmp/portrait-pilot") from error
    if output.exists():
        raise base.AtlasError(f"输出目录已存在，禁止覆盖：{output}")
    if not args.batch_id or len(args.batch_id) > 128 or not all(
        character.isalnum() or character in "._-" for character in args.batch_id
    ):
        raise base.AtlasError("batch-id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")

    base_receipt_path, base_receipt = load_bound_json(args.base_receipt, "receiptDigest", "base receipt")
    follow_receipt_path, follow_receipt = load_bound_json(args.followup_receipt, "receiptDigest", "follow-up receipt")
    base_render_path, base_render = load_bound_json(args.base_render, "renderDigest", "base render")
    follow_render_path, follow_render = load_bound_json(args.followup_render, "renderDigest", "follow-up render")
    validate_receipt(base_receipt, "base receipt")
    validate_receipt(follow_receipt, "follow-up receipt")
    validate_render(base_render, "base render")
    validate_render(follow_render, "follow-up render")

    target = args.review_key
    base_decisions = decision_map(base_receipt)
    follow_decisions = decision_map(follow_receipt)
    if target not in base_decisions or set(follow_decisions) != {target}:
        raise base.AtlasError("follow-up receipt 必须只覆盖 base receipt 中指定的 reviewKey")
    old_decision = base_decisions[target]
    new_decision = follow_decisions[target]
    if old_decision.get("status") not in {"wrong_pose", "wrong_subject", "source", "variant_mismatch"}:
        raise base.AtlasError("只允许后续裁决取代旧异常状态")
    if new_decision.get("status") not in {"pass", "adjustment"}:
        raise base.AtlasError("follow-up 最终状态必须是 pass 或 adjustment")
    if new_decision.get("updatedAt", "") <= old_decision.get("updatedAt", ""):
        raise base.AtlasError("follow-up 决定时间不晚于被取代决定")

    old_render_rows = [row for row in base_render["rows"] if row.get("reviewKey") == target]
    new_render_rows = [row for row in follow_render["rows"] if row.get("reviewKey") == target]
    expected_roles = {"proposal", "independent_review"}
    if {row.get("role") for row in old_render_rows} != expected_roles or {row.get("role") for row in new_render_rows} != expected_roles:
        raise base.AtlasError("被取代与 follow-up render 都必须闭合 A/B 两个角色")

    current_decisions = dict(base_decisions)
    current_decisions[target] = copy.deepcopy(new_decision)
    current_decision_rows = sorted(current_decisions.values(), key=lambda row: row["reviewKey"])

    current_render_rows = {
        key: row for key, row in render_map(base_render).items() if key[0] != target
    }
    for key, row in render_map(follow_render).items():
        if key[0] != target:
            raise base.AtlasError("follow-up render 含目标身份以外的 row")
        current_render_rows[key] = row
    current_render_row_list = sorted(current_render_rows.values(), key=lambda row: (row["reviewKey"], row["role"]))

    provenance = {
        "schema": REPORT_SCHEMA,
        "batchId": args.batch_id,
        "reviewKey": target,
        "controllerSource": base.artifact(CONTROLLER_PATH),
        "baseReceipt": base.artifact(base_receipt_path),
        "followupReceipt": base.artifact(follow_receipt_path),
        "baseRenderReport": base.artifact(base_render_path),
        "followupRenderReport": base.artifact(follow_render_path),
        "resolutionPolicy": "latest_verified_followup_wins_while_superseded_anomaly_remains_negative_evidence",
    }
    source_digest = base.sha256_bytes(base.stable_bytes(provenance))
    review_digest = base.sha256_bytes(base.stable_bytes(current_decision_rows))
    output.mkdir(parents=True)

    current_receipt = {
        "schema": RECEIPT_SCHEMA,
        "status": "human_reviewed_approved"
        if all(row["status"] == "pass" for row in current_decision_rows)
        else "human_reviewed_refinement_required",
        "productionReady": False,
        "batchId": args.batch_id,
        "sourceDigest": source_digest,
        "reviewDigest": review_digest,
        "exportedAt": follow_receipt.get("exportedAt"),
        "verifiedAt": base.utc_now(),
        "inputs": provenance,
        "counts": counts_for(current_decision_rows),
        "decisions": current_decision_rows,
        "gates": {
            "exactDigestBinding": True,
            "allRowsReviewed": True,
            "nonPassNotesPresent": True,
            "sourceBlockersRestricted": True,
            "latestVerifiedFollowupWins": True,
            "supersededDecisionEvidenceBound": True,
            "artAcceptance": False,
            "productionWrites": False,
        },
    }
    current_receipt["receiptDigest"] = base.sha256_bytes(base.stable_bytes(current_receipt))
    current_receipt_path = output / "human-review-receipt.json"
    base.write_json(current_receipt_path, current_receipt)

    current_render = {
        "schema": RENDER_SCHEMA,
        "status": "automated_checked",
        "productionReady": False,
        "batchId": args.batch_id,
        "sourceDigest": source_digest,
        "renderer": {
            "controllerSource": base.artifact(CONTROLLER_PATH),
            "sourceReports": [base.artifact(base_render_path), base.artifact(follow_render_path)],
            "resolutionPolicy": provenance["resolutionPolicy"],
        },
        "rows": current_render_row_list,
        "gates": {
            "uniqueReviewRoleRows": True,
            "latestVerifiedFollowupWins": True,
            "supersededPixelsNotUsedAsAcceptedPixels": True,
            "productionWrites": False,
        },
    }
    current_render["renderDigest"] = base.sha256_bytes(base.stable_bytes(current_render))
    current_render_path = output / "render-report.json"
    base.write_json(current_render_path, current_render)

    report = {
        **provenance,
        "status": "human_review_supersession_verified",
        "productionReady": False,
        "supersededDecision": old_decision,
        "resolvedDecision": new_decision,
        "supersededRows": row_evidence(old_render_rows),
        "resolvedRows": row_evidence(new_render_rows),
        "snapshotReceipt": base.artifact(current_receipt_path),
        "snapshotRenderReport": base.artifact(current_render_path),
        "counts": {
            "snapshotDecisions": len(current_decision_rows),
            "snapshotRenderRows": len(current_render_row_list),
            "supersededDecisions": 1,
            "resolvedDecisions": 1,
        },
        "gates": {
            "sameIdentityFollowup": True,
            "followupNewerThanSupersededDecision": True,
            "latestVerifiedFollowupWins": True,
            "supersededNegativeEvidencePreserved": True,
            "acceptedPixelsComeFromFollowupRender": True,
            "productionWrites": False,
        },
    }
    report["reportDigest"] = base.sha256_bytes(base.stable_bytes(report))
    report_path = output / "human-review-supersession-report.json"
    base.write_json(report_path, report)
    print(json.dumps(verify_report(report_path), ensure_ascii=False))


def verify_report(path: Path) -> dict[str, Any]:
    report = base.load_json(path, "supersession report")
    base.verify_digest(report, "reportDigest", "supersession report")
    if (
        report.get("schema") != REPORT_SCHEMA
        or report.get("status") != "human_review_supersession_verified"
        or report.get("productionReady") is not False
        or report.get("gates", {}).get("latestVerifiedFollowupWins") is not True
        or report.get("gates", {}).get("supersededNegativeEvidencePreserved") is not True
        or report.get("gates", {}).get("productionWrites") is not False
    ):
        raise base.AtlasError("supersession report gate 非法")
    if report.get("controllerSource") != base.artifact(CONTROLLER_PATH):
        raise base.AtlasError("supersession controller 漂移")

    base_receipt_path = base.verify_artifact(report.get("baseReceipt"), "base receipt")
    follow_receipt_path = base.verify_artifact(report.get("followupReceipt"), "follow-up receipt")
    base_render_path = base.verify_artifact(report.get("baseRenderReport"), "base render")
    follow_render_path = base.verify_artifact(report.get("followupRenderReport"), "follow-up render")
    snapshot_receipt_path = base.verify_artifact(report.get("snapshotReceipt"), "snapshot receipt")
    snapshot_render_path = base.verify_artifact(report.get("snapshotRenderReport"), "snapshot render")

    base_receipt = base.load_json(base_receipt_path, "base receipt")
    follow_receipt = base.load_json(follow_receipt_path, "follow-up receipt")
    snapshot_receipt = base.load_json(snapshot_receipt_path, "snapshot receipt")
    base_render = base.load_json(base_render_path, "base render")
    follow_render = base.load_json(follow_render_path, "follow-up render")
    snapshot_render = base.load_json(snapshot_render_path, "snapshot render")
    for value, digest, label in (
        (base_receipt, "receiptDigest", "base receipt"),
        (follow_receipt, "receiptDigest", "follow-up receipt"),
        (snapshot_receipt, "receiptDigest", "snapshot receipt"),
        (base_render, "renderDigest", "base render"),
        (follow_render, "renderDigest", "follow-up render"),
        (snapshot_render, "renderDigest", "snapshot render"),
    ):
        base.verify_digest(value, digest, label)
    validate_receipt(snapshot_receipt, "snapshot receipt")
    validate_render(snapshot_render, "snapshot render")

    target = report.get("reviewKey")
    expected_decisions = decision_map(base_receipt)
    expected_decisions[target] = decision_map(follow_receipt)[target]
    if snapshot_receipt.get("decisions") != sorted(expected_decisions.values(), key=lambda row: row["reviewKey"]):
        raise base.AtlasError("snapshot receipt 没有精确应用 follow-up 决定")
    expected_rows = {key: row for key, row in render_map(base_render).items() if key[0] != target}
    expected_rows.update(render_map(follow_render))
    if snapshot_render.get("rows") != sorted(expected_rows.values(), key=lambda row: (row["reviewKey"], row["role"])):
        raise base.AtlasError("snapshot render 没有精确应用 follow-up 像素")
    for label, rows in (("superseded", report.get("supersededRows", [])), ("resolved", report.get("resolvedRows", []))):
        if {row.get("role") for row in rows} != {"proposal", "independent_review"}:
            raise base.AtlasError(f"{label} evidence A/B 角色不闭合")
        for row in rows:
            base.verify_artifact(row.get("master"), f"{label} evidence master")
    return {
        "status": "human_review_supersession_verified",
        "report": base.repo_rel(path),
        "reportDigest": report["reportDigest"],
        "reviewKey": target,
        "supersededStatus": report["supersededDecision"]["status"],
        "resolvedStatus": report["resolvedDecision"]["status"],
        "snapshotDecisions": report["counts"]["snapshotDecisions"],
        "snapshotRenderRows": report["counts"]["snapshotRenderRows"],
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_report(base.repo_path(args.report, "supersession report")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--base-receipt", required=True)
    build_parser.add_argument("--base-render", required=True)
    build_parser.add_argument("--followup-receipt", required=True)
    build_parser.add_argument("--followup-render", required=True)
    build_parser.add_argument("--review-key", required=True)
    build_parser.add_argument("--output", required=True)
    build_parser.add_argument("--batch-id", required=True)
    build_parser.set_defaults(handler=build)
    check_parser = commands.add_parser("check")
    check_parser.add_argument("--report", required=True)
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (base.AtlasError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"human review supersession error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
