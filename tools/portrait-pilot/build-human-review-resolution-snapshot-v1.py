#!/usr/bin/env python3
"""Resolve the two r125 portrait anomalies into one current human-review snapshot."""

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
REPORT_SCHEMA = "cf7.portrait-pilot-human-review-resolution-snapshot.v1"
RECEIPT_SCHEMA = "cf7.portrait-pilot-human-review-receipt.v1"
RENDER_SCHEMA = "cf7.portrait-pilot-resolved-parent-render-report.v2"
BLACK_RECEIPT_SCHEMA = "cf7.enemy-portrait-black-matte-receipt.v1"
BLACK_DATA_SCHEMA = "cf7.enemy-portrait-black-matte-candidates.v1"
ORIENTATION_SCHEMA = "cf7.portrait-pilot-human-orientation-conformance.v1"
STATUSES = ("pass", "adjustment", "wrong_pose", "wrong_subject", "source", "variant_mismatch")
BLACK_WHITE_KEY = "敌人-黑白无常::default"
BLACK_HOLE_KEY = "敌人-迷你黑洞::default"


def load_base():
    spec = importlib.util.spec_from_file_location("cf7_portrait_resolution_base", BASE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 atlas 基础控制器：{BASE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_base()


def load_bound(raw_path: str | Path, digest_field: str, label: str) -> tuple[Path, dict[str, Any]]:
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
            or (row.get("status") != "pass" and not row.get("notes", "").strip())
        ):
            raise base.AtlasError(f"{label} decision 非法：{key}")
        seen.add(key)


def validate_render(report: dict[str, Any], label: str) -> None:
    allowed = {"automated_checked", "automated_checked_human_review_geometry_and_fidelity"}
    if report.get("status") not in allowed or report.get("productionReady") is not False:
        raise base.AtlasError(f"{label} gate 非法：{report.get('status')}")
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


def selected_black_candidate(data: dict[str, Any], receipt: dict[str, Any]) -> dict[str, Any]:
    if (
        data.get("schema") != BLACK_DATA_SCHEMA
        or data.get("productionReady") is not False
        or receipt.get("schema") != BLACK_RECEIPT_SCHEMA
        or receipt.get("status") != "human_black_matte_candidate_verified"
        or receipt.get("productionReady") is not False
        or receipt.get("datasetDigest") != data.get("datasetDigest")
        or receipt.get("counts") != {"rows": 1, "selected": 1, "refine": 0}
    ):
        raise base.AtlasError("black matte data/receipt gate 非法")
    rows = receipt.get("rows", [])
    if len(rows) != 1 or rows[0].get("reviewKey") != BLACK_HOLE_KEY or rows[0].get("status") != "selected":
        raise base.AtlasError("black matte receipt 必须唯一选择迷你黑洞")
    item = next((item for item in data.get("items", []) if item.get("reviewKey") == BLACK_HOLE_KEY), None)
    if item is None:
        raise base.AtlasError("black matte data 缺迷你黑洞")
    selected = next((candidate for candidate in item.get("candidates", []) if candidate.get("candidateId") == rows[0].get("candidateId")), None)
    if selected is None or selected.get("candidateDigest") != rows[0].get("candidateDigest") or selected.get("outputs") != rows[0].get("selectedOutputs"):
        raise base.AtlasError("black matte 选择与候选闭包不一致")
    for record in selected["outputs"].values():
        base.verify_artifact(record, "black matte selected output")
    base.verify_artifact(selected.get("sourceGeometrySvg"), "black matte source SVG")
    return copy.deepcopy(selected)


def resolved_black_hole_rows(base_rows: dict[tuple[str, str], dict[str, Any]], candidate: dict[str, Any]) -> list[dict[str, Any]]:
    source_role = candidate.get("role")
    template = base_rows.get((BLACK_HOLE_KEY, source_role))
    if template is None:
        raise base.AtlasError("black matte 选择缺对应父 render role")
    outputs = candidate["outputs"]
    rows: list[dict[str, Any]] = []
    for role in ("proposal", "independent_review"):
        row = copy.deepcopy(template)
        row["role"] = role
        row["master"] = copy.deepcopy(outputs["master512"])
        row["previews"] = {
            "32": copy.deepcopy(outputs["preview32"]),
            "48": copy.deepcopy(outputs["preview48"]),
            "80": copy.deepcopy(outputs["preview80"]),
        }
        row["sourceSupersample"] = copy.deepcopy(outputs["supersample4096"])
        row["sourceGeometrySvg"] = copy.deepcopy(candidate["sourceGeometrySvg"])
        row.pop("webp80Lossless", None)
        row.pop("fidelityComparison", None)
        row["humanPostprocessResolution"] = {
            "schema": BLACK_RECEIPT_SCHEMA,
            "selectedCandidateId": candidate["candidateId"],
            "selectedSourceRole": source_role,
            "gamma": candidate["gamma"],
            "formula": "v=max(R,G,B)/255; m=v^gamma; A'=A*m; RGB'=RGB/m when m>0 else 0",
            "currentFrameRetained": True,
            "noModelCall": True,
            "roleProjection": role,
        }
        rows.append(row)
    return rows


def evidence_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "reviewKey": row["reviewKey"],
            "role": row["role"],
            "candidateId": row.get("candidateId"),
            "frame": row.get("frame"),
            "featureLabel": row.get("featureLabel"),
            "framingMode": row.get("framingMode"),
            "master": copy.deepcopy(row["master"]),
        }
        for row in sorted(rows, key=lambda item: item["role"])
    ]


def build(args: argparse.Namespace) -> None:
    output = base.repo_path(args.output, "resolution snapshot 输出")
    try:
        output.relative_to(base.PILOT_ROOT.resolve())
    except ValueError as error:
        raise base.AtlasError("resolution snapshot 输出必须位于 tmp/portrait-pilot") from error
    if output.exists():
        raise base.AtlasError(f"输出目录已存在，禁止覆盖：{output}")
    if not args.batch_id or len(args.batch_id) > 128 or not all(character.isalnum() or character in "._-" for character in args.batch_id):
        raise base.AtlasError("batch-id 非法")

    base_receipt_path, base_receipt = load_bound(args.base_receipt, "receiptDigest", "r125 receipt")
    base_render_path, base_render = load_bound(args.base_render, "renderDigest", "r125 render")
    follow_receipt_path, follow_receipt = load_bound(args.black_white_receipt, "receiptDigest", "黑白无常 receipt")
    follow_render_path, follow_render = load_bound(args.black_white_render, "renderDigest", "黑白无常 render")
    orientation_path, orientation = load_bound(args.orientation_conformance, "receiptDigest", "人类方向一致性回执")
    matte_data_path, matte_data = load_bound(args.black_matte_data, "datasetDigest", "black matte data")
    matte_receipt_path, matte_receipt = load_bound(args.black_matte_receipt, "receiptDigest", "black matte receipt")
    validate_receipt(base_receipt, "r125 receipt")
    validate_receipt(follow_receipt, "黑白无常 receipt")
    validate_render(base_render, "r125 render")
    validate_render(follow_render, "黑白无常 render")
    if (
        orientation.get("schema") != ORIENTATION_SCHEMA
        or orientation.get("status") != "human_orientation_directive_conformance_verified"
        or orientation.get("productionReady") is not False
        or [row.get("reviewKey") for row in orientation.get("rows", [])] != [BLACK_WHITE_KEY]
    ):
        raise base.AtlasError("黑白无常人类方向一致性回执非法")
    candidate = selected_black_candidate(matte_data, matte_receipt)

    decisions = decision_map(base_receipt)
    follow_decisions = decision_map(follow_receipt)
    if set(follow_decisions) != {BLACK_WHITE_KEY} or follow_decisions[BLACK_WHITE_KEY].get("status") != "pass":
        raise base.AtlasError("黑白无常 follow-up 必须是唯一 pass")
    if decisions.get(BLACK_WHITE_KEY, {}).get("status") != "wrong_pose" or decisions.get(BLACK_HOLE_KEY, {}).get("status") != "wrong_pose":
        raise base.AtlasError("r125 两条目标异常不再是 wrong_pose")
    if follow_decisions[BLACK_WHITE_KEY].get("updatedAt", "") <= decisions[BLACK_WHITE_KEY].get("updatedAt", ""):
        raise base.AtlasError("黑白无常 follow-up 不晚于 r125")
    decisions[BLACK_WHITE_KEY] = copy.deepcopy(follow_decisions[BLACK_WHITE_KEY])
    black_hole_old = copy.deepcopy(decisions[BLACK_HOLE_KEY])
    decisions[BLACK_HOLE_KEY] = {
        **black_hole_old,
        "status": "pass",
        "notes": f"真人选择黑底转透明 {candidate['candidateId']}，gamma={candidate['gamma']:.2f}；保留原 frame 10 与所选构图。",
        "updatedAt": matte_receipt.get("exportedAt"),
    }
    decision_rows = sorted(decisions.values(), key=lambda row: row["reviewKey"])

    base_rows = render_map(base_render)
    old_black_white_rows = [row for key, row in base_rows.items() if key[0] == BLACK_WHITE_KEY]
    old_black_hole_rows = [row for key, row in base_rows.items() if key[0] == BLACK_HOLE_KEY]
    follow_rows = [row for row in follow_render["rows"] if row.get("reviewKey") == BLACK_WHITE_KEY]
    if {row.get("role") for row in follow_rows} != {"proposal", "independent_review"}:
        raise base.AtlasError("黑白无常 follow-up render 未闭合 A/B")
    current_rows = {key: row for key, row in base_rows.items() if key[0] not in {BLACK_WHITE_KEY, BLACK_HOLE_KEY}}
    for row in follow_rows:
        current_rows[(BLACK_WHITE_KEY, row["role"])] = copy.deepcopy(row)
    black_hole_rows = resolved_black_hole_rows(base_rows, candidate)
    for row in black_hole_rows:
        current_rows[(BLACK_HOLE_KEY, row["role"])] = row
    render_rows = sorted(current_rows.values(), key=lambda row: (row["reviewKey"], row["role"]))
    if len(render_rows) != 48:
        raise base.AtlasError(f"resolved snapshot render rows 必须是 48，实际 {len(render_rows)}")

    provenance = {
        "schema": REPORT_SCHEMA,
        "batchId": args.batch_id,
        "controllerSource": base.artifact(CONTROLLER_PATH),
        "baseReceipt": base.artifact(base_receipt_path),
        "baseRenderReport": base.artifact(base_render_path),
        "blackWhiteReceipt": base.artifact(follow_receipt_path),
        "blackWhiteRenderReport": base.artifact(follow_render_path),
        "orientationConformanceReceipt": base.artifact(orientation_path),
        "blackMatteData": base.artifact(matte_data_path),
        "blackMatteReceipt": base.artifact(matte_receipt_path),
        "resolutionPolicy": "latest_verified_exact_frame_and_human_black_matte_selection_win_while_both_r125_anomalies_remain_negative_evidence",
    }
    source_digest = base.sha256_bytes(base.stable_bytes(provenance))
    review_digest = base.sha256_bytes(base.stable_bytes(decision_rows))
    output.mkdir(parents=True)

    snapshot_receipt = {
        "schema": RECEIPT_SCHEMA,
        "status": "human_reviewed_refinement_required",
        "productionReady": False,
        "batchId": args.batch_id,
        "sourceDigest": source_digest,
        "reviewDigest": review_digest,
        "exportedAt": matte_receipt.get("exportedAt"),
        "verifiedAt": base.utc_now(),
        "inputs": provenance,
        "counts": counts_for(decision_rows),
        "decisions": decision_rows,
        "gates": {
            "exactDigestBinding": True,
            "allRowsReviewed": True,
            "nonPassNotesPresent": True,
            "sourceBlockersRestricted": True,
            "latestVerifiedFollowupsWin": True,
            "supersededDecisionEvidenceBound": True,
            "artAcceptance": False,
            "productionWrites": False,
        },
    }
    snapshot_receipt["receiptDigest"] = base.sha256_bytes(base.stable_bytes(snapshot_receipt))
    snapshot_receipt_path = output / "human-review-receipt.json"
    base.write_json(snapshot_receipt_path, snapshot_receipt)

    snapshot_render = {
        "schema": RENDER_SCHEMA,
        "status": "automated_checked",
        "productionReady": False,
        "batchId": args.batch_id,
        "sourceDigest": source_digest,
        "renderer": {
            "controllerSource": base.artifact(CONTROLLER_PATH),
            "sourceReports": [base.artifact(base_render_path), base.artifact(follow_render_path)],
            "blackMatteData": base.artifact(matte_data_path),
            "blackMatteReceipt": base.artifact(matte_receipt_path),
            "resolutionPolicy": provenance["resolutionPolicy"],
        },
        "rows": render_rows,
        "gates": {
            "uniqueReviewRoleRows": True,
            "latestVerifiedFollowupsWin": True,
            "supersededPixelsNotUsedAsAcceptedPixels": True,
            "blackMatte4096And512HashesBound": True,
            "productionWrites": False,
        },
    }
    snapshot_render["renderDigest"] = base.sha256_bytes(base.stable_bytes(snapshot_render))
    snapshot_render_path = output / "render-report.json"
    base.write_json(snapshot_render_path, snapshot_render)

    report = {
        **provenance,
        "status": "human_review_resolution_snapshot_verified",
        "productionReady": False,
        "supersededDecisions": {
            BLACK_WHITE_KEY: decision_map(base_receipt)[BLACK_WHITE_KEY],
            BLACK_HOLE_KEY: black_hole_old,
        },
        "resolvedDecisions": {
            BLACK_WHITE_KEY: decisions[BLACK_WHITE_KEY],
            BLACK_HOLE_KEY: decisions[BLACK_HOLE_KEY],
        },
        "supersededRows": {
            BLACK_WHITE_KEY: evidence_rows(old_black_white_rows),
            BLACK_HOLE_KEY: evidence_rows(old_black_hole_rows),
        },
        "resolvedRows": {
            BLACK_WHITE_KEY: evidence_rows(follow_rows),
            BLACK_HOLE_KEY: evidence_rows(black_hole_rows),
        },
        "blackMatteSelection": {
            "candidateId": candidate["candidateId"],
            "candidateDigest": candidate["candidateDigest"],
            "sourceRole": candidate["role"],
            "gamma": candidate["gamma"],
            "outputs": candidate["outputs"],
        },
        "snapshotReceipt": base.artifact(snapshot_receipt_path),
        "snapshotRenderReport": base.artifact(snapshot_render_path),
        "counts": {"snapshotDecisions": 24, "snapshotRenderRows": 48, "supersededDecisions": 2, "resolvedDecisions": 2},
        "gates": {
            "sameIdentityFollowups": True,
            "latestVerifiedFollowupsWin": True,
            "supersededNegativeEvidencePreserved": True,
            "acceptedPixelsComeFromVerifiedFollowups": True,
            "humanOrientationDirectivePreserved": True,
            "blackMatteSelectionPreserved": True,
            "productionWrites": False,
        },
    }
    report["reportDigest"] = base.sha256_bytes(base.stable_bytes(report))
    report_path = output / "human-review-resolution-snapshot.json"
    base.write_json(report_path, report)
    print(json.dumps(verify_report(report_path), ensure_ascii=False))


def verify_report(path: Path) -> dict[str, Any]:
    report = base.load_json(path, "resolution snapshot report")
    base.verify_digest(report, "reportDigest", "resolution snapshot report")
    if (
        report.get("schema") != REPORT_SCHEMA
        or report.get("status") != "human_review_resolution_snapshot_verified"
        or report.get("productionReady") is not False
        or report.get("counts") != {"snapshotDecisions": 24, "snapshotRenderRows": 48, "supersededDecisions": 2, "resolvedDecisions": 2}
        or report.get("gates", {}).get("latestVerifiedFollowupsWin") is not True
        or report.get("gates", {}).get("supersededNegativeEvidencePreserved") is not True
        or report.get("gates", {}).get("productionWrites") is not False
        or report.get("controllerSource") != base.artifact(CONTROLLER_PATH)
    ):
        raise base.AtlasError("resolution snapshot report gate 非法")
    for field, label in (
        ("baseReceipt", "base receipt"),
        ("baseRenderReport", "base render"),
        ("blackWhiteReceipt", "black-white receipt"),
        ("blackWhiteRenderReport", "black-white render"),
        ("orientationConformanceReceipt", "orientation conformance"),
        ("blackMatteData", "black matte data"),
        ("blackMatteReceipt", "black matte receipt"),
        ("snapshotReceipt", "snapshot receipt"),
        ("snapshotRenderReport", "snapshot render"),
    ):
        base.verify_artifact(report.get(field), label)
    snapshot_receipt_path = base.verify_artifact(report["snapshotReceipt"], "snapshot receipt")
    snapshot_render_path = base.verify_artifact(report["snapshotRenderReport"], "snapshot render")
    snapshot_receipt = base.load_json(snapshot_receipt_path, "snapshot receipt")
    snapshot_render = base.load_json(snapshot_render_path, "snapshot render")
    base.verify_digest(snapshot_receipt, "receiptDigest", "snapshot receipt")
    base.verify_digest(snapshot_render, "renderDigest", "snapshot render")
    validate_receipt(snapshot_receipt, "snapshot receipt")
    validate_render(snapshot_render, "snapshot render")
    decisions = decision_map(snapshot_receipt)
    if (
        len(decisions) != 24
        or decisions.get(BLACK_WHITE_KEY, {}).get("status") != "pass"
        or decisions.get(BLACK_HOLE_KEY, {}).get("status") != "pass"
        or snapshot_receipt.get("counts", {}).get("statuses", {}).get("wrong_pose") != 0
        or len(snapshot_render.get("rows", [])) != 48
    ):
        raise base.AtlasError("resolution snapshot 当前决定或 render 行不闭合")
    for mapping in (report.get("supersededRows", {}), report.get("resolvedRows", {})):
        if set(mapping) != {BLACK_WHITE_KEY, BLACK_HOLE_KEY}:
            raise base.AtlasError("resolution snapshot evidence key 漂移")
        for rows in mapping.values():
            if {row.get("role") for row in rows} != {"proposal", "independent_review"}:
                raise base.AtlasError("resolution snapshot evidence A/B 不闭合")
            for row in rows:
                base.verify_artifact(row.get("master"), "resolution evidence master")
    selection = report.get("blackMatteSelection", {})
    if selection.get("candidateId") != "independent_review-g075" or selection.get("gamma") != 0.75:
        raise base.AtlasError("black matte 最终人类选择漂移")
    for record in selection.get("outputs", {}).values():
        base.verify_artifact(record, "black matte final output")
    return {
        "status": "human_review_resolution_snapshot_verified",
        "report": base.repo_rel(path),
        "reportDigest": report["reportDigest"],
        "snapshotReceiptDigest": snapshot_receipt["receiptDigest"],
        "snapshotRenderDigest": snapshot_render["renderDigest"],
        "decisions": 24,
        "renderRows": 48,
        "resolved": 2,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify_report(base.repo_path(args.report, "resolution snapshot report")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--base-receipt", required=True)
    build_parser.add_argument("--base-render", required=True)
    build_parser.add_argument("--black-white-receipt", required=True)
    build_parser.add_argument("--black-white-render", required=True)
    build_parser.add_argument("--orientation-conformance", required=True)
    build_parser.add_argument("--black-matte-data", required=True)
    build_parser.add_argument("--black-matte-receipt", required=True)
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
    except (base.AtlasError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"human review resolution snapshot error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
