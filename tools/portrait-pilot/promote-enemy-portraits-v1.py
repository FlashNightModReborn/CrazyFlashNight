#!/usr/bin/env python3
"""Promote every human-closed enemy portrait into the shared Web asset pack.

This controller deliberately reuses the audited selection/vector machinery from
``promote-team-portraits-v1.py``.  The older controller remains the Team subset
gate; this controller publishes content-addressed subjects first and the runtime
manifest last, while keeping unresolved identities fail-soft only.
"""

from __future__ import annotations

import argparse
import base64
import copy
import datetime as dt
import importlib.util
import json
import lzma
import os
import shutil
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
TEAM_CONTROLLER = Path(__file__).with_name("promote-team-portraits-v1.py")


def load_team_controller() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_team_portrait_promotion", TEAM_CONTROLLER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 Team promotion controller：{TEAM_CONTROLLER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


T = load_team_controller()

EXPECTED_COUNTS = {
    "identityCount": 221,
    "variantCount": 222,
    "humanAcceptedIdentityCount": 216,
    "humanAcceptedVariantCount": 217,
    "pendingHumanReviewIdentityCount": 3,
    "excludedUnimplementedIdentityCount": 1,
    "aliasedIdentityCount": 1,
    "teamIdentityCount": 98,
    "arenaInventoryIdentityCount": 214,
}
SUPPLEMENTAL_PROMOTION_SCHEMA = "cf7.arena-portrait-supplemental-promotion.v1"
SUPPLEMENTAL_EXPECTED_COUNTS = {
    "identityCount": 226,
    "variantCount": 227,
    "humanAcceptedIdentityCount": 221,
    "humanAcceptedVariantCount": 222,
    "pendingHumanReviewIdentityCount": 2,
    "excludedUnimplementedIdentityCount": 1,
    "aliasedIdentityCount": 2,
    "teamIdentityCount": 98,
    "arenaInventoryIdentityCount": 214,
    "arenaSupplementalIdentityCount": 5,
    "arenaCatalogIdentityCount": 214,
}
SUPPLEMENTAL_DIRECT_REVIEW_KEYS = {
    "敌人-红水晶::default",
    "敌人-唐头肌肉男::default",
    "敌人-锯片陷阱::default",
    "敌人-旧型号机器人改::default",
    "敌人-家用机器人::default",
}
SUPPLEMENTAL_FLIP_REVIEW_KEY = "敌人-家用机器人::default"
SUPPLEMENTAL_ALIAS_REF = "敌人-锡蒙利范围光环发生器"
SUPPLEMENTAL_ALIAS_TARGET = "敌人-锡蒙利"
DEFAULT_CAMPAIGN = (
    T.PILOT_ROOT
    / "campaign-shard-r195-internal-subject-feedback203-20260809T100500Z"
    / "candidate-manifest.json"
)
EXPECTED_ALIAS_REF = "敌人-拟态投影"
EXPECTED_ALIAS_TARGET = "敌人-方舟妖姬"
SHIELD_REF = "敌人-盾卫骑士"
DEFAULT_ORIENTATION_REVIEW_ROOT = (
    T.PILOT_ROOT / "orientation-human-review-r204-from-r202-20260809T130000Z"
)
DEFAULT_ORIENTATION_RECEIPT = DEFAULT_ORIENTATION_REVIEW_ROOT / "orientation-human-review-receipt.json"
MODEL_ORIENTATION_SOURCE = "production_visual_audit_model_verified_keep"
HUMAN_ORIENTATION_SOURCE = "explicit_production_orientation_human_audit"


def load_orientation_closure(receipt_path: Path = DEFAULT_ORIENTATION_RECEIPT) -> dict[str, Any]:
    receipt = T.load_json(receipt_path, "方向真人复核回执")
    T.verify_object_digest(receipt, "receiptDigest", "方向真人复核回执")
    if (
        receipt.get("schema") != "cf7.portrait-orientation-human-review-receipt.v1"
        or receipt.get("status") != "human_orientation_reviewed"
        or receipt.get("productionReady") is not False
        or receipt.get("counts")
        != {"total": 39, "keep": 34, "flipX": 5, "modelClosedKeepOutsideReview": 178}
        or receipt.get("gates", {}).get("relativeFlipSemanticsFrozen") is not True
        or receipt.get("gates", {}).get("noProductionWrites") is not True
    ):
        raise T.PromotionError("方向真人复核回执 schema/status/counts/gates 未闭合")
    inputs = receipt.get("inputs") if isinstance(receipt.get("inputs"), dict) else {}
    review_path = T.verify_artifact_record(inputs.get("reviewData"), "方向真人复核数据")
    decisions_path = T.verify_artifact_record(inputs.get("decisions"), "方向真人裁决")
    archived_path = T.verify_artifact_record(inputs.get("archivedDecisions"), "方向真人裁决归档")
    model_path = T.verify_artifact_record(inputs.get("modelReport"), "方向视觉模型报告")
    audit_manifest_path = T.verify_artifact_record(inputs.get("visualAuditManifest"), "方向视觉审计 manifest")
    source_manifest_path = T.verify_artifact_record(inputs.get("sourceProductionManifest"), "方向审计源生产 manifest")
    source_promotion_path = T.verify_artifact_record(
        inputs.get("sourceProductionPromotionReceipt"), "方向审计源生产 promotion receipt"
    )
    controller_paths = [
        T.verify_artifact_record(record, "方向真人复核 controller")
        for record in inputs.get("controllers", [])
    ]
    if decisions_path.read_bytes() != archived_path.read_bytes():
        raise T.PromotionError("方向真人裁决 canonical/archive 字节不一致")

    review = T.load_json(review_path, "方向真人复核数据")
    T.verify_object_digest(review, "reviewDigest", "方向真人复核数据")
    decisions = T.load_json(decisions_path, "方向真人裁决")
    model = T.load_json(model_path, "方向视觉模型报告")
    T.verify_object_digest(model, "reportDigest", "方向视觉模型报告")
    audit_manifest = T.load_json(audit_manifest_path, "方向视觉审计 manifest")
    T.verify_object_digest(audit_manifest, "auditDigest", "方向视觉审计 manifest")
    source_manifest = T.load_json(source_manifest_path, "方向审计源生产 manifest")
    source_promotion = T.load_json(source_promotion_path, "方向审计源 promotion receipt")
    if (
        review.get("schema") != "cf7.portrait-orientation-human-review-data.v1"
        or review.get("items") is None
        or len(review["items"]) != 39
        or review.get("sourceDigest") != receipt.get("sourceDigest")
        or review.get("modelReportDigest") != receipt.get("modelReportDigest")
        or review.get("reviewDigest") != receipt.get("reviewDigest")
        or model.get("schema") != "cf7.production-portrait-orientation-visual-model-report.v1"
        or model.get("status") != "orientation_visual_audit_completed"
        or model.get("reportDigest") != receipt.get("modelReportDigest")
        or model.get("sourceDigest") != receipt.get("sourceDigest")
        or audit_manifest.get("auditDigest") != model.get("input", {}).get("auditDigest")
        or source_manifest.get("manifestDigest") != receipt.get("sourceDigest")
        or T.manifest_digest(source_manifest) != source_manifest.get("manifestDigest")
        or source_promotion.get("manifestDigest") != source_manifest.get("manifestDigest")
    ):
        raise T.PromotionError("方向真人复核 source/review/model/production 摘要未闭合")

    comparisons = model.get("comparisons")
    if not isinstance(comparisons, list) or len(comparisons) != 217:
        raise T.PromotionError("方向视觉模型报告必须闭合 217 项")
    comparison_by_key = {row.get("reviewKey"): row for row in comparisons if isinstance(row, dict)}
    if len(comparison_by_key) != 217 or None in comparison_by_key:
        raise T.PromotionError("方向视觉模型报告 reviewKey 重复或缺失")
    model_closed_keys = {
        key for key, row in comparison_by_key.items() if row.get("disposition") == "model_verified_keep"
    }
    risk_keys = set(comparison_by_key) - model_closed_keys
    if len(model_closed_keys) != 178 or len(risk_keys) != 39:
        raise T.PromotionError("方向视觉模型报告 178/39 分区漂移")
    for key in model_closed_keys:
        row = comparison_by_key[key]
        if (
            row.get("proposal", {}).get("recommendedAction") != "keep"
            or row.get("independentReview", {}).get("recommendedAction") != "keep"
            or float(row.get("minimumConfidence", 0)) < 0.75
        ):
            raise T.PromotionError(f"模型闭合 keep 门漂移：{key}")

    rows = decisions.get("decisions")
    if (
        decisions.get("schema") != "cf7.portrait-orientation-human-decisions.v1"
        or decisions.get("complete") is not True
        or decisions.get("batchId") != review.get("batchId")
        or decisions.get("sourceDigest") != receipt.get("sourceDigest")
        or decisions.get("modelReportDigest") != receipt.get("modelReportDigest")
        or decisions.get("reviewDigest") != receipt.get("reviewDigest")
        or not isinstance(rows, list)
        or len(rows) != 39
    ):
        raise T.PromotionError("方向真人裁决 schema/binding/complete 未闭合")
    human_by_key: dict[str, dict[str, Any]] = {}
    for row in rows:
        key = row.get("reviewKey") if isinstance(row, dict) else None
        if key not in risk_keys or key in human_by_key or row.get("action") not in {"keep", "flip_x"}:
            raise T.PromotionError(f"方向真人裁决 reviewKey/action 非法：{key}")
        human_by_key[key] = row
    if set(human_by_key) != risk_keys:
        raise T.PromotionError("方向真人裁决没有精确覆盖 39 个风险项")
    flip_keys = sorted(key for key, row in human_by_key.items() if row["action"] == "flip_x")
    if flip_keys != receipt.get("flipReviewKeys") or len(flip_keys) != 5:
        raise T.PromotionError("方向真人裁决 flip 集合漂移")

    source_inputs = [
        receipt_path.resolve(),
        review_path,
        decisions_path,
        archived_path,
        model_path,
        audit_manifest_path,
        source_manifest_path,
        source_promotion_path,
        *controller_paths,
    ]
    return {
        "receipt": receipt,
        "receiptPath": receipt_path.resolve(),
        "review": review,
        "model": model,
        "comparisonByKey": comparison_by_key,
        "humanByKey": human_by_key,
        "sourceManifest": source_manifest,
        "sourceInputs": list(dict.fromkeys(path.resolve() for path in source_inputs)),
    }


def base_raster_transform(selection: dict[str, Any]) -> str:
    if (
        selection.get("rasterNeedsFlip") is True
        and selection.get("orientationSource") == "selected_model_orientation_inherited_after_human_crop"
    ):
        return "flip_x_after_human_crop"
    return "none"


def apply_orientation_closure(
    review_key: str, selection: dict[str, Any], closure: dict[str, Any]
) -> dict[str, Any]:
    comparison = closure["comparisonByKey"].get(review_key)
    if comparison is None:
        raise T.PromotionError(f"方向视觉审计缺接受项：{review_key}")
    result = copy.deepcopy(selection)
    base_flip = result.get("flipX") is True
    base_action = "flip_x" if base_flip else "keep"
    base_raster_flip = result.get("rasterNeedsFlip") is True
    if comparison.get("currentProductionOrientationAction") != base_action:
        raise T.PromotionError(
            f"方向视觉审计不是基于当前可重建动作：{review_key} "
            f"selection={base_action} audited={comparison.get('currentProductionOrientationAction')}"
        )
    disposition = comparison.get("disposition")
    if disposition == "model_verified_keep":
        decision = "model_verified_keep"
        relative_mirror = False
        orientation_source = MODEL_ORIENTATION_SOURCE
    else:
        human = closure["humanByKey"].get(review_key)
        if human is None:
            raise T.PromotionError(f"方向风险项缺真人裁决：{review_key}")
        decision = human["action"]
        relative_mirror = decision == "flip_x"
        orientation_source = HUMAN_ORIENTATION_SOURCE

    final_flip = not base_flip if relative_mirror else base_flip
    final_raster_flip = not base_raster_flip if relative_mirror else base_raster_flip
    original_raster_transform = base_raster_transform(result)
    if not final_raster_flip:
        final_raster_transform = "none"
    elif final_raster_flip == base_raster_flip:
        final_raster_transform = original_raster_transform
    else:
        final_raster_transform = "flip_x_after_production_orientation_audit"
    final_action = "flip_x" if final_flip else "keep"
    receipt = closure["receipt"]
    result["flipX"] = final_flip
    result["rasterNeedsFlip"] = final_raster_flip
    result["orientationSource"] = orientation_source
    result["rasterOrientationTransform"] = final_raster_transform
    result["orientationAudit"] = {
        "schema": "cf7.portrait-orientation-production-lineage.v1",
        "disposition": disposition,
        "decision": decision,
        "sourceProductionAction": base_action,
        "sourceOrientationSource": selection.get("orientationSource"),
        "sourceRasterOrientationTransform": original_raster_transform,
        "relativeMirrorApplied": relative_mirror,
        "finalAction": final_action,
        "finalRasterOrientationTransform": final_raster_transform,
        "modelReportDigest": receipt["modelReportDigest"],
        "reviewDigest": receipt["reviewDigest"],
        "humanReceiptDigest": receipt["receiptDigest"],
    }
    return result


def orientation_manifest_summary(closure: dict[str, Any]) -> dict[str, Any]:
    receipt = closure["receipt"]
    return {
        "schema": "cf7.production-portrait-orientation-closure.v1",
        "sourceProductionDigest": receipt["sourceDigest"],
        "modelReportDigest": receipt["modelReportDigest"],
        "humanReviewDigest": receipt["reviewDigest"],
        "humanReceiptDigest": receipt["receiptDigest"],
        "counts": copy.deepcopy(receipt["counts"]),
        "humanFlipReviewKeys": list(receipt["flipReviewKeys"]),
        "relativeFlipSemantics": True,
        "preservedSourceAssetBindings": 434,
        "preservedSourceAssetFiles": 432,
    }


def preserve_orientation_source_assets(staging: Path, closure: dict[str, Any]) -> dict[str, dict[str, Any]]:
    subject_root = staging / "subjects"
    subject_root.mkdir(parents=True, exist_ok=True)
    records: dict[str, dict[str, Any]] = {}
    bindings = 0
    for entry in closure["sourceManifest"].get("entries", {}).values():
        for variant in entry.get("variants", {}).values():
            if variant.get("status") != "human_accepted":
                continue
            for kind in ("svg", "pngFallback"):
                record = variant.get("subject", {}).get(kind)
                url = record.get("url") if isinstance(record, dict) else None
                if not isinstance(url, str) or not url.startswith("assets/enemy-portraits/subjects/"):
                    raise T.PromotionError(f"方向审计源资产 URL 非法：{url}")
                bindings += 1
                name = Path(url).name
                prior = records.get(name)
                if prior is not None and prior.get("sha256") != record.get("sha256"):
                    raise T.PromotionError(f"方向审计源资产内容寻址碰撞：{name}")
                records[name] = record
    if bindings != 434 or len(records) != 432:
        raise T.PromotionError(f"方向审计源资产计数漂移：bindings={bindings} files={len(records)}")
    for name, record in records.items():
        source = T.DEFAULT_OUTPUT / "subjects" / name
        if (
            not source.is_file()
            or source.stat().st_size != record.get("bytes")
            or T.sha256_file(source) != record.get("sha256")
        ):
            raise T.PromotionError(f"方向审计源历史资产缺失或漂移：{source}")
        target = subject_root / name
        if target.exists():
            if target.read_bytes() != source.read_bytes():
                raise T.PromotionError(f"方向审计源历史资产 staging 碰撞：{name}")
        else:
            shutil.copyfile(source, target)
    return records


def expected_preserved_subjects(runtime_subject_names: set[str]) -> list[dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {
        Path(record["url"]).name: copy.deepcopy(record)
        for record in T.evidence_preserved_subject_records()
    }
    for record in T.evidence_svg_basis_subject_records():
        name = Path(record["url"]).name
        if name not in runtime_subject_names and name not in records:
            records[name] = copy.deepcopy(record)
    return [records[name] for name in sorted(records)]


def runtime_subject_names(manifest: dict[str, Any]) -> set[str]:
    return {
        Path(record["url"]).name
        for entry in manifest.get("entries", {}).values()
        for variant in entry.get("variants", {}).values()
        if variant.get("status") == "human_accepted"
        for record in (variant["subject"]["svg"], variant["subject"]["pngFallback"])
    }


def preserve_expected_evidence_assets(
    staging: Path,
    expected: list[dict[str, Any]],
    existing: dict[str, dict[str, Any]],
) -> None:
    subject_root = staging / "subjects"
    for record in expected:
        name = Path(record["url"]).name
        source = T.DEFAULT_OUTPUT / "subjects" / name
        if (
            not source.is_file()
            or source.stat().st_size != record.get("bytes")
            or T.sha256_file(source) != record.get("sha256")
        ):
            raise T.PromotionError(f"immutable evidence basis 历史资产缺失或漂移：{source}")
        target = subject_root / name
        if target.is_file():
            if target.stat().st_size != record["bytes"] or T.sha256_file(target) != record["sha256"]:
                raise T.PromotionError(f"immutable evidence basis staging 碰撞：{name}")
        else:
            shutil.copyfile(source, target)
        previous = existing.get(name)
        if previous is not None and previous.get("sha256") != record["sha256"]:
            raise T.PromotionError(f"immutable evidence basis 内容寻址碰撞：{name}")
        existing[name] = record


def selection_for(
    review_key: str,
    decisions: dict[str, tuple[dict[str, Any], Path]],
    direct_rows: list[tuple[dict[str, Any], Path]],
    corrections: dict[str, tuple[int, dict[str, Any], Path, dict[str, Any]]],
    representatives: dict[str, dict[str, Any]],
) -> dict[str, Any] | None:
    return T.accepted_selection(review_key, decisions, direct_rows, corrections) or representatives.get(review_key)


def build_pack(
    inventory_path: Path,
    campaign_path: Path,
    closure_path: Path,
    team_gap_batch: Path,
    staging: Path,
    logical_output: Path | None = None,
) -> dict[str, Any]:
    logical_output = staging if logical_output is None else logical_output
    inventory = T.load_json(inventory_path, "portrait inventory")
    decisions, direct_rows, corrections, calibration_manifests = T.collect_calibration(
        campaign_path,
        expected_decision_count=203,
        expected_statuses={"adjustment": 116, "pass": 86, "source": 1},
        expected_correction_count=116,
    )
    gap_decisions, gap_direct_rows, gap_inputs = T.collect_team_gap(team_gap_batch)
    overlap = set(decisions).intersection(gap_decisions)
    if overlap:
        raise T.PromotionError(f"Team 尾项决定与累计回执重复：{sorted(overlap)}")
    decisions.update(gap_decisions)
    direct_rows.extend(gap_direct_rows)
    representatives = T.representative_selections(closure_path, direct_rows)
    aliases = T.alias_manifest_record()
    orientation_closure = load_orientation_closure()
    preserved_source_records = preserve_orientation_source_assets(staging, orientation_closure)
    orientation_applied: set[str] = set()

    items = sorted(inventory.get("items", []), key=lambda item: item.get("portraitRef", ""))
    if len(items) != EXPECTED_COUNTS["identityCount"]:
        raise T.PromotionError(f"通用头像 inventory identity 漂移：expected=221 actual={len(items)}")

    entries: dict[str, Any] = {}
    accepted_variants = 0
    accepted_identities: set[str] = set()
    pending_refs: set[str] = set()
    excluded_refs: set[str] = set()
    alias_refs: set[str] = set()

    for item in items:
        portrait_ref = str(item.get("portraitRef") or "")
        if not portrait_ref:
            raise T.PromotionError("通用头像 inventory 含空 portraitRef")
        consumers = item.get("consumers") if isinstance(item.get("consumers"), dict) else {}
        pet_ids = sorted(int(value) for value in consumers.get("petIds", []))
        enemy_ids = sorted(str(value) for value in consumers.get("enemyIds", []))
        variant_keys = list(item.get("variantKeys") or ["default"])
        default_variant = "orange" if portrait_ref == T.JK_REF else variant_keys[0]
        variants: dict[str, Any] = {}

        for variant_key in variant_keys:
            review_key = f"{portrait_ref}::{variant_key}"
            selection = selection_for(review_key, decisions, direct_rows, corrections, representatives)
            legacy = T.legacy_url(pet_ids, portrait_ref, variant_key)
            if selection is not None:
                selection = apply_orientation_closure(review_key, selection, orientation_closure)
                orientation_applied.add(review_key)
                variant = T.write_subject_assets(staging, selection)
                accepted_variants += 1
            elif portrait_ref in aliases:
                alias = aliases[portrait_ref]
                variant = {
                    "status": "identity_alias",
                    "targetPortraitRef": alias["targetPortraitRef"],
                    "targetVariantKey": alias.get("variantKey", "default"),
                    "reason": "human-reviewed identity reuse; resolver follows the signed aliases table",
                }
                alias_refs.add(portrait_ref)
            elif portrait_ref == T.UNIMPLEMENTED_REF:
                variant = {
                    "status": "excluded_unimplemented",
                    "reason": "pets.xml explicitly marks this asset as not implemented; only unused FLA exists",
                }
                excluded_refs.add(portrait_ref)
            else:
                variant = {
                    "status": "pending_human_review",
                    "reason": "no human-accepted selection is closed in the current provenance envelope",
                }
                pending_refs.add(portrait_ref)
            if legacy:
                variant["legacyUrl"] = legacy
            variants[variant_key] = variant

        statuses = {variant.get("status") for variant in variants.values()}
        if statuses == {"human_accepted"}:
            entry_status = "ready"
            accepted_identities.add(portrait_ref)
        elif portrait_ref in alias_refs:
            entry_status = "identity_alias"
        elif portrait_ref in excluded_refs:
            entry_status = "excluded_unimplemented"
        else:
            entry_status = "pending_human_review"
        entries[portrait_ref] = {
            "portraitRef": portrait_ref,
            "petIds": pet_ids,
            "enemyIds": enemy_ids,
            "status": entry_status,
            "defaultVariant": default_variant,
            "variants": variants,
        }

    team_refs = {
        item["portraitRef"]
        for item in items
        if (item.get("consumers") or {}).get("petIds")
    }
    arena_refs = {
        item["portraitRef"]
        for item in items
        if (item.get("consumers") or {}).get("enemyIds")
    }
    counts = {
        "identityCount": len(entries),
        "variantCount": sum(len(entry["variants"]) for entry in entries.values()),
        "humanAcceptedIdentityCount": len(accepted_identities),
        "humanAcceptedVariantCount": accepted_variants,
        "pendingHumanReviewIdentityCount": len(pending_refs),
        "excludedUnimplementedIdentityCount": len(excluded_refs),
        "aliasedIdentityCount": len(alias_refs),
        "teamIdentityCount": len(team_refs),
        "arenaInventoryIdentityCount": len(arena_refs),
    }
    if counts != EXPECTED_COUNTS:
        raise T.PromotionError(f"通用头像闭包计数漂移：{counts}")
    if orientation_applied != set(orientation_closure["comparisonByKey"]):
        raise T.PromotionError(
            f"方向全量闭包与 217 个接受项不一致：applied={len(orientation_applied)} "
            f"audited={len(orientation_closure['comparisonByKey'])}"
        )
    if excluded_refs != {T.UNIMPLEMENTED_REF} or alias_refs != {EXPECTED_ALIAS_REF}:
        raise T.PromotionError(
            f"通用头像受控例外漂移：excluded={sorted(excluded_refs)} aliases={sorted(alias_refs)}"
        )
    shield = entries.get(SHIELD_REF, {}).get("variants", {}).get("default", {})
    if shield.get("status") != "human_accepted" or shield.get("provenance", {}).get("resolution") != "human_guided_adjustment":
        raise T.PromotionError("盾卫骑士已闭合人工框选结果未进入通用包")

    runtime_names = runtime_subject_names({"entries": entries})
    expected_preserved = expected_preserved_subjects(runtime_names)
    preserve_expected_evidence_assets(staging, expected_preserved, preserved_source_records)
    expected_by_name = {Path(record["url"]).name: record for record in expected_preserved}
    preserved_subjects: list[dict[str, Any]] = []
    for name, record in sorted(preserved_source_records.items()):
        if name in runtime_names:
            continue
        target = staging / "subjects" / name
        expected = expected_by_name.get(name)
        if expected is None:
            raise T.PromotionError(f"未声明的 preserved subject：{name}")
        preserved_subjects.append({
            "url": f"assets/enemy-portraits/subjects/{name}",
            "bytes": target.stat().st_size,
            "sha256": T.sha256_file(target),
            "purpose": expected["purpose"],
        })
    if preserved_subjects != expected_preserved:
        raise T.PromotionError("方向审计 preserved subject evidence 与 immutable evidence pack 漂移")

    source_records = [T.artifact(inventory_path), T.artifact(campaign_path), T.artifact(closure_path)]
    source_records.extend(T.artifact(path) for path in calibration_manifests if path != campaign_path.resolve())
    source_records.extend(T.artifact(path) for path in gap_inputs)
    source_records.append(T.artifact(T.ALIAS_RECEIPT))
    source_records.extend(T.artifact(path) for path in orientation_closure["sourceInputs"])
    source_records.extend((T.artifact(TEAM_CONTROLLER), T.artifact(Path(__file__))))
    manifest: dict[str, Any] = {
        "schema": "cf7.enemy-portrait-manifest.v1",
        "status": "human_accepted_portraits_promoted",
        "generatedAt": T.utc_now(),
        "consumerContract": {
            "identityKey": "portraitRef + variantKey",
            "primaryFormat": "per-variant subject.preferredFormat; PNG is primary for every SVG containing embedded raster images",
            "fallbackFormat": "the alternate signed subject format, then caller legacy asset",
            "presentationOwnedBy": "launcher/web/modules/portrait-resolver.js and consumer CSS",
            "unresolvedPolicy": "pending/excluded identities expose no unsigned modern subject",
            "teamCompatible": True,
            "arenaCompatible": True,
        },
        "counts": counts,
        "sourceEnvelope": {"inputs": source_records},
        "evidencePack": T.artifact(T.EVIDENCE_PACK),
        "orientationAudit": orientation_manifest_summary(orientation_closure),
        "preservedEvidence": {
            "schema": "cf7.enemy-portrait-preserved-evidence.v1",
            "subjects": preserved_subjects,
        },
        "aliases": aliases,
        "entries": entries,
    }
    manifest["manifestDigest"] = T.manifest_digest(manifest)
    manifest_path = staging / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    receipt = {
        "schema": "cf7.enemy-portrait-promotion-receipt.v1",
        "status": "enemy_portrait_pack_promoted",
        "generatedAt": manifest["generatedAt"],
        "manifest": {
            "path": T.repo_rel(logical_output / "manifest.json"),
            "bytes": manifest_path.stat().st_size,
            "sha256": T.sha256_file(manifest_path),
        },
        "manifestDigest": manifest["manifestDigest"],
        "counts": counts,
        "orientationAudit": copy.deepcopy(manifest["orientationAudit"]),
        "gates": {
            "allHumanClosedSelectionsPromoted": True,
            "arenaAcceptedOutsideTeamPromoted": True,
            "unresolvedIdentitiesFailSoftOnly": True,
            "identityAliasReceiptBound": True,
            "shieldKnightHumanGuidancePromoted": True,
            "runtimeManifestPublishedLast": True,
            "allPreviouslyAcceptedTeamVariantsPromoted": True,
            "allTeamVariantsWithRuntimeSourcesPromoted": True,
            "jkTwoDistinctVariantsPromoted": True,
            "directPassOrientationAppliedToSvg": True,
            "humanCropSelectedOrientationInherited": True,
            "fullProductionOrientationVisualAuditBound": True,
            "modelClosedOrientationKeepsPreserved": True,
            "allOrientationRiskRowsHumanReviewed": True,
            "humanRelativeOrientationFlipsApplied": True,
            "svgPrimaryAndExactPngFallbackBound": True,
            "allPngMastersHaveTransparentBackground": True,
            "threeLateSourceResolutionsHumanAccepted": True,
            "seventeenInternalSubjectResolutionsHumanAccepted": True,
            "maiRemainsExplicitlyUnimplemented": True,
            "presentationSeparatedFromIdentityManifest": True,
            "productionWrites": True,
        },
    }
    receipt["receiptDigest"] = T.sha256_bytes(T.stable_bytes(receipt))
    (staging / "promotion-receipt.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def accepted_subject_files(
    manifest: dict[str, Any], asset_root: Path
) -> tuple[int, set[str], set[str], set[str], set[str]]:
    accepted = 0
    accepted_refs: set[str] = set()
    pending: set[str] = set()
    excluded: set[str] = set()
    aliased: set[str] = set()
    for portrait_ref, entry in manifest.get("entries", {}).items():
        variants = entry.get("variants")
        if not isinstance(variants, dict) or entry.get("defaultVariant") not in variants:
            raise T.PromotionError(f"通用头像 variant/default 不闭合：{portrait_ref}")
        ready = True
        for variant_key, variant in variants.items():
            status = variant.get("status")
            if status == "human_accepted":
                accepted += 1
                subject = variant.get("subject", {})
                for kind in ("svg", "pngFallback"):
                    record = subject.get(kind)
                    if not isinstance(record, dict) or not isinstance(record.get("url"), str):
                        raise T.PromotionError(f"通用头像 subject 缺失：{portrait_ref}::{variant_key}/{kind}")
                    path = T.subject_asset_path(asset_root, record["url"])
                    if path.stat().st_size != record.get("bytes") or T.sha256_file(path) != record.get("sha256"):
                        raise T.PromotionError(f"通用头像产物漂移：{record['url']}")
                png_path = T.subject_asset_path(asset_root, subject["pngFallback"]["url"])
                svg_path = T.subject_asset_path(asset_root, subject["svg"]["url"])
                representation = T.svg_representation_evidence(svg_path.read_bytes(), png_path.read_bytes())
                if (
                    subject.get("preferredFormat") != representation["preferredFormat"]
                    or subject["svg"].get("embeddedRasterCount") != representation["embeddedRasterCount"]
                    or subject["svg"].get("isRasterHeavy") != representation["isRasterHeavy"]
                ):
                    raise T.PromotionError(f"通用头像 SVG/PNG representation 证据漂移：{portrait_ref}::{variant_key}")
                expected_alpha = {key: subject["pngFallback"][key] for key in ("size", "alphaExtrema", "visibleBounds")}
                if T.png_alpha_evidence(png_path) != expected_alpha:
                    raise T.PromotionError(f"通用头像 alpha 证据漂移：{portrait_ref}::{variant_key}")
                review_key = f"{portrait_ref}::{variant_key}"
                flip_x = subject["svg"].get("flipX") is True
                expected_action = "flip_x" if flip_x else "keep"
                provenance = variant.get("provenance", {})
                if provenance.get("orientationAction") != expected_action:
                    raise T.PromotionError(f"通用头像方向 provenance 漂移：{review_key}")
                orientation_source = provenance.get("orientationSource")
                raster_transform = provenance.get("rasterOrientationTransform")
                if orientation_source not in T.ORIENTATION_SOURCES:
                    raise T.PromotionError(f"通用头像方向证据来源非法：{review_key}={orientation_source}")
                orientation_audit = provenance.get("orientationAudit")
                if orientation_source in {MODEL_ORIENTATION_SOURCE, HUMAN_ORIENTATION_SOURCE}:
                    if not isinstance(orientation_audit, dict):
                        raise T.PromotionError(f"通用头像方向全量审计 lineage 缺失：{review_key}")
                    if orientation_audit.get("finalAction") != expected_action:
                        raise T.PromotionError(f"通用头像方向全量审计 finalAction 漂移：{review_key}")
                    decision = orientation_audit.get("decision")
                    base_action = orientation_audit.get("sourceProductionAction")
                    if orientation_source == MODEL_ORIENTATION_SOURCE:
                        if decision != "model_verified_keep" or base_action != expected_action:
                            raise T.PromotionError(f"通用头像模型方向闭合 lineage 漂移：{review_key}")
                    elif decision == "keep":
                        if base_action != expected_action:
                            raise T.PromotionError(f"通用头像真人 keep lineage 漂移：{review_key}")
                    elif decision == "flip_x":
                        if base_action == expected_action:
                            raise T.PromotionError(f"通用头像真人 flip 未切换方向：{review_key}")
                    else:
                        raise T.PromotionError(f"通用头像真人方向决定非法：{review_key}={decision}")
                    expected_transform = orientation_audit.get("finalRasterOrientationTransform")
                else:
                    if orientation_audit is not None:
                        raise T.PromotionError(f"通用头像旧方向来源不得携带全量审计 lineage：{review_key}")
                    expected_transform = (
                        "flip_x_after_human_crop"
                        if orientation_source == "selected_model_orientation_inherited_after_human_crop" and flip_x
                        else "none"
                    )
                if raster_transform != expected_transform:
                    raise T.PromotionError(
                        f"通用头像 PNG 方向变换漂移：{review_key} expected={expected_transform} actual={raster_transform}"
                    )
                if orientation_source == "legacy_orientation_unassessed" and flip_x:
                    raise T.PromotionError(f"未审计旧头像不得凭空反转：{review_key}")
                svg_text = svg_path.read_text(encoding="utf-8")
                has_flip = 'data-cf7-portrait-flip="x"' in svg_text
                if has_flip != flip_x:
                    raise T.PromotionError(f"通用头像 SVG 方向标记漂移：{review_key}")
                if T.empty_ffdec_filter_ids(svg_text):
                    raise T.PromotionError(f"通用头像 SVG 仍含 Chromium 空白 filter：{review_key}")
                source_svg = T.verify_artifact_record(provenance.get("sourceVectorFrame"), "通用头像源矢量帧")
                source_filter_ids = T.empty_ffdec_filter_ids(source_svg.read_text(encoding="utf-8"))
                expected_compatibility = ([{
                    "kind": "strip_empty_ffdec_filters",
                    "filterIds": source_filter_ids,
                }] if source_filter_ids else [])
                if subject["svg"].get("compatibilityTransforms", []) != expected_compatibility:
                    raise T.PromotionError(f"通用头像 SVG 兼容变换证据漂移：{review_key}")
                expected_transform = "strip_empty_ffdec_filters" if source_filter_ids else None
                if provenance.get("svgCompatibilityTransform") != expected_transform:
                    raise T.PromotionError(f"通用头像 SVG 兼容 provenance 漂移：{review_key}")
            elif status == "pending_human_review":
                ready = False
                pending.add(portrait_ref)
                if variant.get("subject"):
                    raise T.PromotionError(f"待人审 identity 不得暴露 subject：{portrait_ref}")
            elif status == "excluded_unimplemented":
                ready = False
                excluded.add(portrait_ref)
                if variant.get("subject"):
                    raise T.PromotionError(f"未实装 identity 不得暴露 subject：{portrait_ref}")
            elif status == "identity_alias":
                ready = False
                aliased.add(portrait_ref)
                if variant.get("subject"):
                    raise T.PromotionError(f"别名 identity 不得复制 subject：{portrait_ref}")
            else:
                raise T.PromotionError(f"通用头像状态非法：{portrait_ref}::{variant_key}={status}")
        if ready:
            accepted_refs.add(portrait_ref)
    return accepted, accepted_refs, pending, excluded, aliased


def check_aliases(manifest: dict[str, Any], *, supplemental: bool = False) -> None:
    aliases = manifest.get("aliases") if isinstance(manifest.get("aliases"), dict) else {}
    expected_aliases = {EXPECTED_ALIAS_REF}
    if supplemental:
        expected_aliases.add(SUPPLEMENTAL_ALIAS_REF)
    if set(aliases) != expected_aliases:
        raise T.PromotionError(f"通用头像 alias 集合漂移：{sorted(aliases)}")
    alias = aliases[EXPECTED_ALIAS_REF]
    if alias.get("targetPortraitRef") != EXPECTED_ALIAS_TARGET:
        raise T.PromotionError("拟态投影 alias target 漂移")
    for source_ref, expected_target in (
        (EXPECTED_ALIAS_REF, EXPECTED_ALIAS_TARGET),
        *(([(SUPPLEMENTAL_ALIAS_REF, SUPPLEMENTAL_ALIAS_TARGET)]) if supplemental else []),
    ):
        row = aliases[source_ref]
        if row.get("targetPortraitRef") != expected_target or row.get("variantKey", "default") != "default":
            raise T.PromotionError(f"头像 alias target 漂移：{source_ref}")
        target = manifest.get("entries", {}).get(expected_target, {})
        variant = target.get("variants", {}).get("default", {})
        if variant.get("status") != "human_accepted":
            raise T.PromotionError(f"头像 alias target 未绑定 human_accepted variant：{source_ref}")
        T.verify_artifact_record(row.get("provenance"), f"头像 alias provenance：{source_ref}")


def load_base_evidence_archive(value: Any) -> tuple[dict[str, Any], dict[str, Any], dict[str, bytes]]:
    if (
        not isinstance(value, dict)
        or value.get("schema") != "cf7.enemy-portrait-base-evidence-archive.v1"
        or value.get("encoding") != "sha256-base64-json+xz+base64"
    ):
        raise T.PromotionError("Arena 增量基础 evidence archive schema/encoding 非法")
    records = value.get("files")
    expected_names = {"manifest.json", "promotion-receipt.json"}
    if not isinstance(records, dict) or set(records) != expected_names:
        raise T.PromotionError("Arena 增量基础 evidence archive files exact-set 漂移")
    try:
        compressed = base64.b64decode("".join(value.get("dataChunks", [])), validate=True)
    except (TypeError, ValueError) as error:
        raise T.PromotionError("Arena 增量基础 evidence archive base64 非法") from error
    if (
        len(compressed) != value.get("compressedBytes")
        or T.sha256_bytes(compressed) != value.get("compressedSha256")
    ):
        raise T.PromotionError("Arena 增量基础 evidence archive 压缩字节漂移")
    try:
        archive_bytes = lzma.decompress(compressed)
        encoded_blobs = json.loads(archive_bytes.decode("utf-8"))
    except (lzma.LZMAError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise T.PromotionError(f"Arena 增量基础 evidence archive 解压失败：{error}") from error
    if len(archive_bytes) != value.get("uncompressedBytes") or not isinstance(encoded_blobs, dict):
        raise T.PromotionError("Arena 增量基础 evidence archive 长度/结构漂移")
    if set(encoded_blobs) != expected_names:
        raise T.PromotionError("Arena 增量基础 evidence archive blob exact-set 漂移")
    blobs: dict[str, bytes] = {}
    parsed: dict[str, dict[str, Any]] = {}
    for name in sorted(expected_names):
        record = records[name]
        if not isinstance(record, dict) or set(record) != {"bytes", "sha256"}:
            raise T.PromotionError(f"Arena 增量基础 evidence record 非法：{name}")
        try:
            blob = base64.b64decode(encoded_blobs[name], validate=True)
            document = json.loads(blob.decode("utf-8"))
        except (TypeError, ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise T.PromotionError(f"Arena 增量基础 evidence 文件不可读：{name}") from error
        if (
            not isinstance(document, dict)
            or len(blob) != record.get("bytes")
            or T.sha256_bytes(blob) != record.get("sha256")
        ):
            raise T.PromotionError(f"Arena 增量基础 evidence 文件摘要漂移：{name}")
        blobs[name] = blob
        parsed[name] = document
    return parsed["manifest.json"], parsed["promotion-receipt.json"], blobs


def check_supplemental_promotion(manifest: dict[str, Any]) -> dict[str, Any]:
    closure = manifest.get("supplementalPromotion")
    if not isinstance(closure, dict):
        raise T.PromotionError("Arena 增量 promotion closure 缺失")
    T.verify_object_digest(closure, "closureDigest", "Arena 增量 promotion closure")
    if (
        closure.get("schema") != SUPPLEMENTAL_PROMOTION_SCHEMA
        or closure.get("status") != "arena_supplemental_portraits_promoted"
        or not isinstance(closure.get("baseManifestDigest"), str)
        or set(closure.get("directReviewKeys", [])) != SUPPLEMENTAL_DIRECT_REVIEW_KEYS
        or closure.get("aliasReviewKey") != f"{SUPPLEMENTAL_ALIAS_REF}::default"
        or closure.get("orientationActions")
        != {
            key: ("flip_x" if key == SUPPLEMENTAL_FLIP_REVIEW_KEY else "keep")
            for key in sorted(SUPPLEMENTAL_DIRECT_REVIEW_KEYS)
        }
        or closure.get("counts") != {"directHumanAccepted": 5, "identityAliases": 1, "combinedArenaReady": 217}
    ):
        raise T.PromotionError("Arena 增量 promotion closure schema/status/rows 漂移")

    inputs = closure.get("inputs") if isinstance(closure.get("inputs"), dict) else {}
    human_receipt_path = T.verify_artifact_record(inputs.get("humanReviewReceipt"), "Arena 增量人审回执")
    review_data_path = T.verify_artifact_record(inputs.get("reviewData"), "Arena 增量 review data")
    direct_render_path = T.verify_artifact_record(inputs.get("directRender"), "Arena 增量直接渲染")
    orientation_path = T.verify_artifact_record(inputs.get("orientationAdjustment"), "Arena 增量方向修正")
    alias_receipt_path = T.verify_artifact_record(inputs.get("aliasReceipt"), "Arena 增量 alias 回执")
    T.verify_artifact_record(inputs.get("controller"), "Arena 增量 promotion controller")

    base_manifest, base_receipt, base_blobs = load_base_evidence_archive(closure.get("baseEvidence"))
    if (
        T.manifest_digest(base_manifest) != closure["baseManifestDigest"]
        or base_manifest.get("manifestDigest") != closure["baseManifestDigest"]
        or base_manifest.get("schema") != "cf7.enemy-portrait-manifest.v1"
        or base_manifest.get("status") != "human_accepted_portraits_promoted"
        or base_manifest.get("counts") != EXPECTED_COUNTS
        or isinstance(base_manifest.get("supplementalPromotion"), dict)
    ):
        raise T.PromotionError("Arena 增量基础 manifest 漂移")
    expected_base_preserved = expected_preserved_subjects(runtime_subject_names(base_manifest))
    if (
        base_manifest.get("preservedEvidence", {}).get("subjects") != expected_base_preserved
        or manifest.get("preservedEvidence", {}).get("subjects") != expected_base_preserved
    ):
        raise T.PromotionError("Arena 增量基础/最终 preserved evidence exact-set 漂移")
    T.verify_object_digest(base_receipt, "receiptDigest", "Arena 增量基础 promotion receipt")
    base_manifest_record = base_receipt.get("manifest")
    if (
        base_receipt.get("schema") != "cf7.enemy-portrait-promotion-receipt.v1"
        or base_receipt.get("status") != "enemy_portrait_pack_promoted"
        or base_receipt.get("manifestDigest") != closure["baseManifestDigest"]
        or base_receipt.get("counts") != EXPECTED_COUNTS
        or base_receipt.get("generatedAt") != base_manifest.get("generatedAt")
        or not isinstance(base_manifest_record, dict)
        or base_manifest_record.get("path") != T.repo_rel(T.DEFAULT_OUTPUT / "manifest.json")
        or base_manifest_record.get("bytes") != len(base_blobs["manifest.json"])
        or base_manifest_record.get("sha256") != T.sha256_bytes(base_blobs["manifest.json"])
    ):
        raise T.PromotionError("Arena 增量基础 promotion receipt 漂移")

    human_receipt = T.load_json(human_receipt_path, "Arena 增量人审回执")
    T.verify_object_digest(human_receipt, "receiptDigest", "Arena 增量人审回执")
    statuses = {
        str(row.get("reviewKey")): str(row.get("status"))
        for row in human_receipt.get("decisions", [])
        if isinstance(row, dict)
    }
    expected_statuses = {
        key: ("adjustment" if key == SUPPLEMENTAL_FLIP_REVIEW_KEY else "pass")
        for key in SUPPLEMENTAL_DIRECT_REVIEW_KEYS
    }
    if (
        human_receipt.get("schema") != "cf7.portrait-pilot-human-review-receipt.v1"
        or human_receipt.get("status") != "human_reviewed_refinement_required"
        or human_receipt.get("productionReady") is not False
        or statuses != expected_statuses
        or human_receipt.get("counts", {}).get("eligiblePassed") != 4
        or human_receipt.get("gates", {}).get("productionWrites") is not False
    ):
        raise T.PromotionError("Arena 增量人审回执未闭合 4 pass + 1 adjustment")

    review_data = T.load_json(review_data_path, "Arena 增量 review data")
    direct_render = T.load_json(direct_render_path, "Arena 增量直接渲染")
    T.verify_object_digest(direct_render, "renderDigest", "Arena 增量直接渲染", pilot=True)
    direct_by_key = {
        row.get("reviewKey"): row
        for row in direct_render.get("rows", [])
        if isinstance(row, dict) and row.get("role") == "proposal"
    }
    if (
        set(direct_by_key) != SUPPLEMENTAL_DIRECT_REVIEW_KEYS
        or review_data.get("renderDigest") != direct_render.get("renderDigest")
        or review_data.get("reviewDigest") != human_receipt.get("reviewDigest")
    ):
        raise T.PromotionError("Arena 增量 review/render 键或摘要漂移")

    orientation = T.load_json(orientation_path, "Arena 增量方向修正")
    T.verify_object_digest(orientation, "reportDigest", "Arena 增量方向修正", pilot=True)
    orientation_rows = orientation.get("rows", [])
    if (
        orientation.get("schema") != "cf7.portrait-pilot-orientation-render-report.v1"
        or len(orientation_rows) != 1
        or orientation_rows[0].get("reviewKey") != SUPPLEMENTAL_FLIP_REVIEW_KEY
        or orientation_rows[0].get("operation") != "flip_x"
        or orientation_rows[0].get("fidelityComparison", {}).get("passed") is not True
    ):
        raise T.PromotionError("Arena 增量方向修正未闭合家用机器人 flip_x")

    alias_receipt = T.load_json(alias_receipt_path, "Arena 增量 alias 回执")
    T.verify_object_digest(alias_receipt, "receiptDigest", "Arena 增量 alias 回执", pilot=True)
    if (
        alias_receipt.get("schema") != "cf7.arena-portrait-alias-receipt.v1"
        or alias_receipt.get("status") != "human_alias_approved"
        or alias_receipt.get("productionReady") is not False
        or alias_receipt.get("decision", {}).get("sourcePortraitRef") != SUPPLEMENTAL_ALIAS_REF
        or alias_receipt.get("decision", {}).get("targetPortraitRef") != SUPPLEMENTAL_ALIAS_TARGET
        or alias_receipt.get("decision", {}).get("action") != "reuse"
    ):
        raise T.PromotionError("Arena 增量 alias 回执漂移")

    entries = manifest.get("entries", {})
    for review_key, expected_action in closure["orientationActions"].items():
        portrait_ref, variant_key = review_key.rsplit("::", 1)
        variant = entries.get(portrait_ref, {}).get("variants", {}).get(variant_key, {})
        provenance = variant.get("provenance", {})
        if (
            variant.get("status") != "human_accepted"
            or provenance.get("orientationAction") != expected_action
            or provenance.get("humanReceipt", {}).get("sha256") != inputs["humanReviewReceipt"]["sha256"]
        ):
            raise T.PromotionError(f"Arena 增量接受项 provenance 漂移：{review_key}")
        expected_report = inputs["orientationAdjustment"] if review_key == SUPPLEMENTAL_FLIP_REVIEW_KEY else inputs["directRender"]
        if provenance.get("acceptedRenderReport", {}).get("sha256") != expected_report["sha256"]:
            raise T.PromotionError(f"Arena 增量接受渲染绑定漂移：{review_key}")

    alias_entry = entries.get(SUPPLEMENTAL_ALIAS_REF, {})
    alias_variant = alias_entry.get("variants", {}).get("default", {})
    if (
        alias_entry.get("status") != "identity_alias"
        or alias_variant.get("status") != "identity_alias"
        or alias_variant.get("targetPortraitRef") != SUPPLEMENTAL_ALIAS_TARGET
        or alias_variant.get("subject") is not None
    ):
        raise T.PromotionError("锡蒙利发生器 alias entry 漂移")

    envelope_hashes = {
        record.get("sha256")
        for record in manifest.get("sourceEnvelope", {}).get("inputs", [])
        if isinstance(record, dict)
    }
    required_hashes = {
        record.get("sha256") for record in inputs.values() if isinstance(record, dict)
    }
    if not required_hashes.issubset(envelope_hashes):
        raise T.PromotionError("Arena 增量 sourceEnvelope 未绑定完整输入")
    return closure


def check_team_subset(manifest: dict[str, Any]) -> None:
    inventory = T.load_json(T.DEFAULT_INVENTORY, "portrait inventory")
    team_refs = {
        item["portraitRef"]
        for item in inventory.get("items", [])
        if (item.get("consumers") or {}).get("petIds")
    }
    if len(team_refs) != 98 or not team_refs.issubset(manifest.get("entries", {})):
        raise T.PromotionError("通用包未闭合 98 个 Team identity 子集")
    accepted = 0
    excluded: set[str] = set()
    flipped: set[str] = set()
    for portrait_ref in team_refs:
        entry = manifest["entries"][portrait_ref]
        for variant_key, variant in entry["variants"].items():
            if variant.get("status") == "human_accepted":
                accepted += 1
                if variant.get("subject", {}).get("svg", {}).get("flipX") is True:
                    flipped.add(f"{portrait_ref}::{variant_key}")
            elif variant.get("status") == "excluded_unimplemented":
                excluded.add(portrait_ref)
            else:
                raise T.PromotionError(f"Team identity 在通用包中退化：{portrait_ref}::{variant_key}")
    expected_flipped = T.EXPECTED_FLIPPED_VARIANTS.symmetric_difference(T.ORIENTATION_AUDIT_TEAM_TOGGLES)
    if accepted != 98 or excluded != {T.UNIMPLEMENTED_REF} or flipped != expected_flipped:
        raise T.PromotionError(
            f"Team 子集闭包漂移：accepted={accepted} excluded={sorted(excluded)} "
            f"expectedFlipped={sorted(expected_flipped)} actualFlipped={sorted(flipped)}"
        )
    jk = manifest["entries"][T.JK_REF]
    if set(jk["variants"]) != {"orange", "white"} or jk.get("defaultVariant") != "orange":
        raise T.PromotionError("通用包 JK 双头像合同漂移")
    if jk["variants"]["orange"]["subject"]["pngFallback"]["sha256"] == jk["variants"]["white"]["subject"]["pngFallback"]["sha256"]:
        raise T.PromotionError("通用包 JK 双头像像素相同")


def verify_manifest_artifact_closure(value: Any, location: str = "manifest") -> int:
    verified = 0
    if isinstance(value, dict):
        if {"path", "bytes", "sha256"}.issubset(value):
            T.verify_artifact_record(value, f"通用敌人头像 provenance {location}")
            verified += 1
        for key, child in value.items():
            verified += verify_manifest_artifact_closure(child, f"{location}/{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            verified += verify_manifest_artifact_closure(child, f"{location}/{index}")
    return verified


def check_manifest(manifest_path: Path, *, logical_output: Path | None = None) -> dict[str, Any]:
    manifest = T.load_json(manifest_path, "通用敌人头像 manifest")
    if manifest.get("schema") != "cf7.enemy-portrait-manifest.v1":
        raise T.PromotionError("通用敌人头像 manifest schema 非法")
    if manifest.get("status") != "human_accepted_portraits_promoted":
        raise T.PromotionError("通用敌人头像 manifest 尚未 promotion")
    if T.manifest_digest(manifest) != manifest.get("manifestDigest"):
        raise T.PromotionError("通用敌人头像 manifestDigest 漂移")
    evidence_pack_path = T.verify_artifact_record(manifest.get("evidencePack"), "通用敌人头像 immutable evidence pack")
    if evidence_pack_path.resolve() != T.EVIDENCE_PACK.resolve():
        raise T.PromotionError("通用敌人头像 immutable evidence pack 路径漂移")
    if verify_manifest_artifact_closure(manifest) < 1:
        raise T.PromotionError("通用敌人头像 provenance artifact closure 为空")
    supplemental = isinstance(manifest.get("supplementalPromotion"), dict)
    expected_counts = SUPPLEMENTAL_EXPECTED_COUNTS if supplemental else EXPECTED_COUNTS
    entries = manifest.get("entries")
    if not isinstance(entries, dict) or len(entries) != expected_counts["identityCount"]:
        raise T.PromotionError("通用敌人头像 identityCount 不闭合")
    asset_root = manifest_path.parent
    accepted, accepted_refs, pending, excluded, aliased = accepted_subject_files(manifest, asset_root)
    actual_counts = {
        "identityCount": len(entries),
        "variantCount": sum(len(entry["variants"]) for entry in entries.values()),
        "humanAcceptedIdentityCount": len(accepted_refs),
        "humanAcceptedVariantCount": accepted,
        "pendingHumanReviewIdentityCount": len(pending),
        "excludedUnimplementedIdentityCount": len(excluded),
        "aliasedIdentityCount": len(aliased),
        "teamIdentityCount": 98,
        "arenaInventoryIdentityCount": 214,
    }
    if supplemental:
        actual_counts.update({
            "arenaSupplementalIdentityCount": 5,
            "arenaCatalogIdentityCount": 214,
        })
    if manifest.get("counts") != expected_counts or actual_counts != expected_counts:
        raise T.PromotionError(f"通用敌人头像计数漂移：manifest={manifest.get('counts')} actual={actual_counts}")
    orientation_closure = load_orientation_closure()
    expected_orientation_summary = orientation_manifest_summary(orientation_closure)
    if manifest.get("orientationAudit") != expected_orientation_summary:
        raise T.PromotionError("通用敌人头像方向全量闭包摘要漂移")
    envelope_inputs = manifest.get("sourceEnvelope", {}).get("inputs", [])
    envelope_by_path = {
        record.get("path"): record for record in envelope_inputs if isinstance(record, dict)
    }
    envelope_hashes = {
        record.get("sha256") for record in envelope_inputs if isinstance(record, dict)
    }
    for controller in (TEAM_CONTROLLER, Path(__file__)):
        expected_controller = T.artifact(controller)
        if envelope_by_path.get(expected_controller["path"]) != expected_controller:
            raise T.PromotionError(f"通用敌人头像 sourceEnvelope 未绑定当前 promotion controller：{controller.name}")
    required_orientation_hashes = {
        T.artifact(path).get("sha256") for path in orientation_closure["sourceInputs"]
    }
    if not required_orientation_hashes.issubset(envelope_hashes):
        raise T.PromotionError("通用敌人头像 sourceEnvelope 未绑定完整方向审计闭包")
    expected_aliases = {EXPECTED_ALIAS_REF, *({SUPPLEMENTAL_ALIAS_REF} if supplemental else set())}
    if excluded != {T.UNIMPLEMENTED_REF} or aliased != expected_aliases:
        raise T.PromotionError("通用敌人头像受控例外集合漂移")
    check_aliases(manifest, supplemental=supplemental)
    supplemental_closure = check_supplemental_promotion(manifest) if supplemental else None
    if not supplemental and manifest.get("preservedEvidence", {}).get("subjects") != expected_preserved_subjects(
        runtime_subject_names(manifest)
    ):
        raise T.PromotionError("通用敌人头像 preserved evidence exact-set 漂移")
    check_team_subset(manifest)
    T.verify_exact_subject_fileset(manifest, asset_root)
    shield = entries[SHIELD_REF]["variants"]["default"]
    if shield.get("status") != "human_accepted" or shield.get("provenance", {}).get("resolution") != "human_guided_adjustment":
        raise T.PromotionError("盾卫骑士人工框选 provenance 漂移")

    receipt_path = manifest_path.parent / "promotion-receipt.json"
    receipt = T.load_json(receipt_path, "通用敌人头像 promotion receipt")
    if receipt.get("schema") != "cf7.enemy-portrait-promotion-receipt.v1":
        raise T.PromotionError("通用敌人头像 receipt schema 非法")
    if receipt.get("manifestDigest") != manifest["manifestDigest"] or receipt.get("counts") != expected_counts:
        raise T.PromotionError("通用敌人头像 promotion receipt 漂移")
    expected_manifest_path = (manifest_path.parent if logical_output is None else logical_output) / "manifest.json"
    manifest_record = receipt.get("manifest")
    if (
        not isinstance(manifest_record, dict)
        or manifest_record.get("path") != T.repo_rel(expected_manifest_path)
        or manifest_record.get("bytes") != manifest_path.stat().st_size
        or manifest_record.get("sha256") != T.sha256_file(manifest_path)
        or receipt.get("status") != "enemy_portrait_pack_promoted"
        or receipt.get("generatedAt") != manifest.get("generatedAt")
    ):
        raise T.PromotionError("通用敌人头像 promotion receipt manifest/status/generatedAt 漂移")
    if receipt.get("orientationAudit") != expected_orientation_summary:
        raise T.PromotionError("通用敌人头像 promotion receipt 方向摘要漂移")
    required_gates = {
        "allHumanClosedSelectionsPromoted",
        "arenaAcceptedOutsideTeamPromoted",
        "unresolvedIdentitiesFailSoftOnly",
        "identityAliasReceiptBound",
        "shieldKnightHumanGuidancePromoted",
        "runtimeManifestPublishedLast",
        "allPreviouslyAcceptedTeamVariantsPromoted",
        "allTeamVariantsWithRuntimeSourcesPromoted",
        "jkTwoDistinctVariantsPromoted",
        "directPassOrientationAppliedToSvg",
        "humanCropSelectedOrientationInherited",
        "fullProductionOrientationVisualAuditBound",
        "modelClosedOrientationKeepsPreserved",
        "allOrientationRiskRowsHumanReviewed",
        "humanRelativeOrientationFlipsApplied",
        "svgPrimaryAndExactPngFallbackBound",
        "allPngMastersHaveTransparentBackground",
        "threeLateSourceResolutionsHumanAccepted",
        "seventeenInternalSubjectResolutionsHumanAccepted",
        "maiRemainsExplicitlyUnimplemented",
        "presentationSeparatedFromIdentityManifest",
        "productionWrites",
    }
    if any(receipt.get("gates", {}).get(key) is not True for key in required_gates):
        raise T.PromotionError("通用敌人头像 promotion receipt gates 未闭合")
    if supplemental:
        supplemental_gates = {
            "arenaSupplementalHumanReviewPromoted",
            "arenaSupplementalOrientationClosed",
            "simonliGeneratorAliasBound",
            "arenaCatalogCoverageReady",
            "supplementalManifestPublishedLast",
        }
        if (
            any(receipt.get("gates", {}).get(key) is not True for key in supplemental_gates)
            or receipt.get("supplementalPromotion") != {
                "schema": supplemental_closure["schema"],
                "closureDigest": supplemental_closure["closureDigest"],
                "baseManifestDigest": supplemental_closure["baseManifestDigest"],
                "counts": supplemental_closure["counts"],
            }
        ):
            raise T.PromotionError("Arena 增量 promotion receipt closure/gates 漂移")
    clone = copy.deepcopy(receipt)
    expected_receipt_digest = clone.pop("receiptDigest", None)
    if T.sha256_bytes(T.stable_bytes(clone)) != expected_receipt_digest:
        raise T.PromotionError("通用敌人头像 receiptDigest 漂移")
    return manifest


def atomic_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.publish-{os.getpid()}.tmp")
    if temporary.exists():
        raise T.PromotionError(f"发布临时文件已存在：{temporary}")
    try:
        with source.open("rb") as reader, temporary.open("xb") as writer:
            shutil.copyfileobj(reader, writer, length=1024 * 1024)
            writer.flush()
            os.fsync(writer.fileno())
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def publish_staged_pack(
    staging: Path,
    output: Path,
    backup: Path | None,
    *,
    fault_hook: Any | None = None,
) -> dict[str, Any]:
    def checkpoint(name: str) -> None:
        if fault_hook is not None:
            fault_hook(name)

    checked_staging = check_manifest(staging / "manifest.json", logical_output=output)
    output.mkdir(parents=True, exist_ok=True)
    output_subjects = output / "subjects"
    output_subjects.mkdir(parents=True, exist_ok=True)
    staging_subjects = staging / "subjects"
    desired = {path.name: path for path in staging_subjects.iterdir() if path.is_file()}
    existing = {path.name: path for path in output_subjects.iterdir() if path.is_file()}
    new_names = set(desired) - set(existing)
    stale_names = set(existing) - set(desired)
    for name in sorted(set(desired).intersection(existing)):
        if desired[name].read_bytes() != existing[name].read_bytes():
            raise T.PromotionError(f"内容寻址 subject 碰撞：{name}")

    old_manifest = output / "manifest.json"
    old_receipt = output / "promotion-receipt.json"
    if backup is not None:
        backup.mkdir(parents=True, exist_ok=True)
        if old_manifest.is_file() and not (backup / "manifest.json").exists():
            atomic_copy(old_manifest, backup / "manifest.json")
        if old_receipt.is_file() and not (backup / "promotion-receipt.json").exists():
            atomic_copy(old_receipt, backup / "promotion-receipt.json")
        for name in sorted(stale_names):
            frozen = backup / "subjects" / name
            if not frozen.exists():
                atomic_copy(existing[name], frozen)

    receipt_switched = False
    manifest_switched = False
    try:
        for name in sorted(new_names):
            atomic_copy(desired[name], output_subjects / name)
        checkpoint("subjects_published")
        atomic_copy(staging / "promotion-receipt.json", output / "promotion-receipt.json")
        receipt_switched = True
        checkpoint("receipt_published")
        # This is the sole runtime authority switch. Every referenced subject is
        # content-addressed and present before this single-file replacement.
        atomic_copy(staging / "manifest.json", output / "manifest.json")
        manifest_switched = True
        checkpoint("manifest_published")
        for name in sorted(stale_names):
            (output_subjects / name).unlink()
        checkpoint("stale_cleanup_completed")
        checkpoint("before_final_check")
        checked = check_manifest(output / "manifest.json")
    except Exception:
        if backup is not None:
            for name in sorted(stale_names):
                frozen = backup / "subjects" / name
                if frozen.is_file():
                    atomic_copy(frozen, output_subjects / name)
            if receipt_switched and (backup / "promotion-receipt.json").is_file():
                atomic_copy(backup / "promotion-receipt.json", output / "promotion-receipt.json")
            if manifest_switched and (backup / "manifest.json").is_file():
                atomic_copy(backup / "manifest.json", output / "manifest.json")
        if backup is not None or not manifest_switched:
            for name in sorted(new_names):
                candidate = output_subjects / name
                if candidate.is_file():
                    candidate.unlink()
        raise
    if checked.get("manifestDigest") != checked_staging.get("manifestDigest"):
        raise T.PromotionError("manifest-last 发布后 digest 漂移")
    shutil.rmtree(staging)
    return checked


def promote(args: argparse.Namespace) -> None:
    output = T.resolve_output(Path(args.output))
    replacing = output.exists()
    if replacing and not args.replace_existing:
        raise T.PromotionError(f"生产输出已存在，禁止覆盖；先运行 check 或显式替换：{output}")
    staging = output.with_name(f"{output.name}.staging-enemy-{os.getpid()}")
    if staging.exists():
        raise T.PromotionError(f"staging 已存在，禁止覆盖：{staging}")
    staging.mkdir(parents=True)
    manifest = build_pack(
        Path(args.inventory).resolve(),
        Path(args.campaign_manifest).resolve(),
        Path(args.representative_closure).resolve(),
        Path(args.team_gap_batch).resolve(),
        staging,
        output,
    )
    backup: Path | None = None
    if replacing:
        old = T.load_json(output / "manifest.json", "上一版头像 manifest")
        old_digest = old.get("manifestDigest")
        if not isinstance(old_digest, str):
            raise T.PromotionError("上一版头像 manifest 缺 digest")
        backup_root = T.PILOT_ROOT / "enemy-portrait-production-backups"
        backup_root.mkdir(parents=True, exist_ok=True)
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        backup = backup_root / f"enemy-portraits-{old_digest[:16].lower()}-{stamp}"
        if backup.exists():
            raise T.PromotionError(f"上一版备份已存在，禁止覆盖：{backup}")
    checked = publish_staged_pack(staging, output, backup)
    print(json.dumps({
        "status": "enemy_portrait_pack_promoted",
        "output": T.repo_rel(output),
        "manifestDigest": manifest["manifestDigest"],
        "counts": checked["counts"],
        "rollbackBackup": T.repo_rel(backup) if backup is not None else None,
    }, ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    path = Path(args.manifest).resolve()
    manifest = check_manifest(path)
    print(json.dumps({
        "status": "enemy_portrait_pack_verified",
        "manifest": T.repo_rel(path),
        "manifestDigest": manifest["manifestDigest"],
        "counts": manifest["counts"],
    }, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    promote_parser = sub.add_parser("promote")
    promote_parser.add_argument("--inventory", default=str(T.DEFAULT_INVENTORY))
    promote_parser.add_argument("--campaign-manifest", default=str(DEFAULT_CAMPAIGN))
    promote_parser.add_argument("--representative-closure", default=str(T.DEFAULT_REPRESENTATIVE_CLOSURE))
    promote_parser.add_argument("--team-gap-batch", default=str(T.DEFAULT_TEAM_GAP_BATCH))
    promote_parser.add_argument("--output", default=str(T.DEFAULT_OUTPUT))
    promote_parser.add_argument("--replace-existing", action="store_true")
    promote_parser.set_defaults(handler=promote)
    check_parser = sub.add_parser("check")
    check_parser.add_argument("--manifest", default=str(T.DEFAULT_OUTPUT / "manifest.json"))
    check_parser.set_defaults(handler=check)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        args.handler(args)
    except (T.PromotionError, OSError, ValueError, KeyError) as error:
        print(f"[enemy-portrait-promotion] ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
