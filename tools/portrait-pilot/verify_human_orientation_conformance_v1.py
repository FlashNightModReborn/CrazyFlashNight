#!/usr/bin/env python3
"""Verify that model and rendered directions conform to a frozen human directive."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import sys

from prepare_pilot import (
    PILOT_ROOT,
    ROOT,
    PilotError,
    artifact,
    load_json,
    repo_rel,
    sha256_bytes,
    stable_bytes,
    verify_artifact_record,
    verify_digest_object,
    write_json,
)


SCHEMA = "cf7.portrait-pilot-human-orientation-conformance.v1"
RECEIPT_NAME = "human-orientation-conformance-receipt.json"


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def require_object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise PilotError(f"{label} 必须是对象")
    return value


def require_list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise PilotError(f"{label} 必须是数组")
    return value


def batch_root(value: str) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(PILOT_ROOT)
    except ValueError as error:
        raise PilotError("批次必须位于 tmp/portrait-pilot 下") from error
    if not path.is_dir():
        raise PilotError(f"批次不存在：{repo_rel(path)}")
    return path


def load_inputs(root: Path) -> tuple[dict[str, object], dict[str, object], dict[str, object]]:
    manifest = require_object(load_json(root / "candidate-manifest.json"), "candidate manifest")
    model = require_object(load_json(root / "model-report.json"), "model report")
    render = require_object(load_json(root / "render-report.json"), "render report")
    verify_digest_object(manifest, "manifestDigest", "candidate manifest")
    verify_digest_object(model, "reportDigest", "model report")
    verify_digest_object(render, "renderDigest", "render report")
    if model.get("manifestDigest") != manifest.get("manifestDigest") or render.get("manifestDigest") != manifest.get("manifestDigest"):
        raise PilotError("manifest/model/render 摘要不一致")
    if render.get("modelReportDigest") != model.get("reportDigest"):
        raise PilotError("render report 未绑定当前 model report")
    return manifest, model, render


def collect_directives(manifest: dict[str, object]) -> dict[str, str]:
    directives: dict[str, str] = {}
    for raw in require_list(manifest.get("reviewItems"), "reviewItems"):
        item = require_object(raw, "review item")
        if item.get("blocked") is True:
            continue
        review_key = str(item.get("reviewKey", ""))
        policy = require_object(item.get("intentPolicy"), f"intentPolicy {review_key}")
        directive = require_object(policy.get("orientationDirective"), f"orientationDirective {review_key}")
        action = directive.get("action")
        if (
            not review_key
            or review_key in directives
            or action not in {"keep", "flip_x"}
            or directive.get("source") != "verified_human_exact_action_frame_directive"
            or directive.get("applyAfterOriginalSpaceCrop") is not True
        ):
            raise PilotError(f"人类方向指令非法：{review_key}")
        directives[review_key] = str(action)
    if not directives:
        raise PilotError("manifest 没有可验证的人类方向指令")
    return directives


def collect_model(model: dict[str, object]) -> dict[tuple[str, str], str]:
    result: dict[tuple[str, str], str] = {}
    for raw_run in require_list(model.get("runs"), "model runs"):
        run = require_object(raw_run, "model run")
        role = str(run.get("role", ""))
        if role not in {"proposal", "independent_review"}:
            raise PilotError(f"模型方向角色非法：{role}")
        selections = require_list(require_object(run.get("result"), "model result").get("selections"), "model selections")
        for raw_selection in selections:
            selection = require_object(raw_selection, "model selection")
            key = (role, str(selection.get("reviewKey", "")))
            action = selection.get("orientationAction")
            if key in result or action not in {"keep", "flip_x"}:
                raise PilotError(f"模型方向行非法：{key}")
            result[key] = str(action)
    return result


def collect_render(render: dict[str, object]) -> dict[tuple[str, str], str]:
    result: dict[tuple[str, str], str] = {}
    for raw_row in require_list(render.get("rows"), "render rows"):
        row = require_object(raw_row, "render row")
        key = (str(row.get("role", "")), str(row.get("reviewKey", "")))
        action = row.get("orientationAction")
        mapping = require_object(row.get("cropMapping"), f"cropMapping {key}")
        if (
            key in result
            or action not in {"keep", "flip_x"}
            or mapping.get("orientationAction") != action
            or mapping.get("orientationApplied") is not (action == "flip_x")
            or mapping.get("orientationOrder") != "crop_then_flip_x_before_output_pyramid"
        ):
            raise PilotError(f"render 方向行非法：{key}")
        result[key] = str(action)
    return result


def build(options: argparse.Namespace) -> dict[str, object]:
    root = batch_root(options.batch)
    receipt_path = root / RECEIPT_NAME
    if receipt_path.exists():
        raise PilotError(f"{RECEIPT_NAME} 已存在，禁止覆盖")
    manifest, model, render = load_inputs(root)
    directives = collect_directives(manifest)
    model_rows = collect_model(model)
    render_rows = collect_render(render)
    expected_keys = {(role, review_key) for review_key in directives for role in ("proposal", "independent_review")}
    if set(model_rows) != expected_keys or set(render_rows) != expected_keys:
        raise PilotError("人类方向指令与模型/render 行集合不闭合")
    rows = []
    for review_key, action in sorted(directives.items()):
        for role in ("proposal", "independent_review"):
            if model_rows[(role, review_key)] != action or render_rows[(role, review_key)] != action:
                raise PilotError(f"模型或 render 违背人类方向指令：{review_key}/{role}")
        rows.append({
            "reviewKey": review_key,
            "orientationAction": action,
            "authority": "verified_human_exact_action_frame_directive",
            "modelRolesConform": ["proposal", "independent_review"],
            "renderRolesConform": ["proposal", "independent_review"],
            "applicationStage": "after_original_space_crop_before_output_pyramid",
        })
    receipt: dict[str, object] = {
        "schema": SCHEMA,
        "status": "human_orientation_directive_conformance_verified",
        "productionReady": False,
        "generatedAt": utc_now(),
        "batchId": manifest.get("batchId"),
        "sourceDigest": manifest.get("sourceDigest"),
        "manifestDigest": manifest.get("manifestDigest"),
        "modelReportDigest": model.get("reportDigest"),
        "renderDigest": render.get("renderDigest"),
        "inputs": {
            "manifest": artifact(root / "candidate-manifest.json"),
            "modelReport": artifact(root / "model-report.json"),
            "renderReport": artifact(root / "render-report.json"),
            "controller": artifact(Path(__file__).resolve()),
        },
        "rows": rows,
        "counts": {"identities": len(rows), "roleRows": len(expected_keys), "flipX": sum(row["orientationAction"] == "flip_x" for row in rows)},
        "gates": {
            "humanDirectiveIsAuthority": True,
            "proposalConforms": True,
            "independentReviewConforms": True,
            "rendererConforms": True,
            "cropCoordinatesRemainOriginalSpace": True,
            "orientationAppliedAfterCrop": True,
            "productionWrites": False,
        },
    }
    receipt["receiptDigest"] = sha256_bytes(stable_bytes(receipt))
    write_json(receipt_path, receipt)
    return receipt


def check(options: argparse.Namespace) -> dict[str, object]:
    root = batch_root(options.batch)
    manifest, model, render = load_inputs(root)
    receipt = require_object(load_json(root / RECEIPT_NAME), "人类方向一致性回执")
    verify_digest_object(receipt, "receiptDigest", "人类方向一致性回执")
    if (
        receipt.get("schema") != SCHEMA
        or receipt.get("status") != "human_orientation_directive_conformance_verified"
        or receipt.get("manifestDigest") != manifest.get("manifestDigest")
        or receipt.get("modelReportDigest") != model.get("reportDigest")
        or receipt.get("renderDigest") != render.get("renderDigest")
        or receipt.get("gates", {}).get("humanDirectiveIsAuthority") is not True
        or receipt.get("gates", {}).get("productionWrites") is not False
    ):
        raise PilotError("人类方向一致性回执闭包漂移")
    for record in require_object(receipt.get("inputs"), "receipt inputs").values():
        verify_artifact_record(require_object(record, "receipt artifact"), "人类方向一致性 artifact")
    return receipt


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("command", choices=["build", "check"])
    result.add_argument("--batch", required=True)
    return result


def main() -> None:
    options = parser().parse_args()
    receipt = build(options) if options.command == "build" else check(options)
    print(json.dumps({
        "status": receipt["status"] if options.command == "build" else "human_orientation_directive_conformance_checked",
        "receiptDigest": receipt["receiptDigest"],
        "identities": receipt["counts"]["identities"],
        "roleRows": receipt["counts"]["roleRows"],
        "flipX": receipt["counts"]["flipX"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (OSError, PilotError, KeyError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1) from error
