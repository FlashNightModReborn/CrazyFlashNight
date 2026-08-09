#!/usr/bin/env python3
"""Atomically promote the final Arena portrait supplement.

The supplement contains five human-reviewed direct portraits and one explicit
Simonli generator identity alias.  It starts from the already verified shared
portrait pack, writes content-addressed subjects into a staging copy, and rolls
back to the previous pack if the final shared-manifest verifier fails.
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
BASE_CONTROLLER = Path(__file__).with_name("promote-enemy-portraits-v1.py")


def load_base_controller() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_enemy_portrait_base_for_arena_supplement", BASE_CONTROLLER)
    if spec is None or spec.loader is None:
        raise RuntimeError("无法加载通用头像 promotion controller")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


P = load_base_controller()
T = P.T
PILOT_ROOT = T.PILOT_ROOT
SCHEMA = P.SUPPLEMENTAL_PROMOTION_SCHEMA
BASE_MANIFEST_DIGEST = "5FA93F5BAC9093D2EE7F3617479F37A9BB8D41A8882F4318248A9AE81430B4C2"
DEFAULT_REVIEW_BATCH = PILOT_ROOT / "arena-direct-gap-localization-r215-five-fast3-20260809T211500Z"
DEFAULT_ORIENTATION_BATCH = PILOT_ROOT / "arena-direct-gap-orientation-r217-r215-home-robot-20260809T162700Z"
DEFAULT_ALIAS_BATCH = PILOT_ROOT / "arena-alias-r218-simonli-generator-to-simonli-20260809T164500Z"
DEFAULT_EVIDENCE_OUTPUT = PILOT_ROOT / "arena-supplemental-promotion-r219-final6-20260809T170000Z"
DIRECT_UNIT_IDS = {
    "敌人-红水晶": [291],
    "敌人-唐头肌肉男": [368],
    "敌人-锯片陷阱": [379],
    "敌人-旧型号机器人改": [431],
    "敌人-家用机器人": [432],
}
ALIAS_UNIT_IDS = [334]


class SupplementalPromotionError(RuntimeError):
    pass


def load_json(path: Path, label: str) -> dict[str, Any]:
    return T.load_json(path, label)


def run_checked(command: list[str], label: str, timeout: int = 120) -> None:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip()
        raise SupplementalPromotionError(f"{label}失败：{message}")


def ensure_pilot_output(path: Path, *, allow_existing: bool = False) -> Path:
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(PILOT_ROOT.resolve())
    except ValueError as error:
        raise SupplementalPromotionError(f"证据输出越出 tmp/portrait-pilot：{resolved}") from error
    if not relative.parts:
        raise SupplementalPromotionError("证据输出不能是 tmp/portrait-pilot 根目录")
    if resolved.exists() and not allow_existing:
        raise SupplementalPromotionError(f"证据输出已存在，禁止覆盖：{resolved}")
    return resolved


def verify_input_controllers(review_batch: Path, orientation_batch: Path, alias_batch: Path) -> None:
    run_checked(
        ["node", "tools/portrait-pilot/verify-review-decisions.js", "--batch", T.repo_rel(review_batch), "--check"],
        "Arena 五项人审回执校验",
    )
    run_checked(
        [
            sys.executable,
            "tools/portrait-pilot/render-feature-orientation-human-review-v1.py",
            "check",
            "--manifest",
            T.repo_rel(review_batch / "candidate-manifest.json"),
            "--model-report",
            T.repo_rel(review_batch / "model-report.json"),
        ],
        "Arena 五项人审渲染校验",
    )
    run_checked(
        [
            sys.executable,
            "tools/portrait-pilot/render-orientation-adjustment-v2.py",
            "check",
            "--output",
            T.repo_rel(orientation_batch),
        ],
        "家用机器人方向修正校验",
    )
    run_checked(
        [
            sys.executable,
            "tools/portrait-pilot/freeze-arena-portrait-alias-v1.py",
            "check",
            "--output",
            T.repo_rel(alias_batch),
        ],
        "锡蒙利发生器 alias 回执校验",
    )


def collect_inputs(review_batch: Path, orientation_batch: Path, alias_batch: Path) -> dict[str, Any]:
    verify_input_controllers(review_batch, orientation_batch, alias_batch)
    paths = {
        "candidateManifest": review_batch / "candidate-manifest.json",
        "modelReport": review_batch / "model-report.json",
        "directRender": review_batch / "render-report.json",
        "reviewData": review_batch / "review-data.json",
        "decisions": review_batch / "portrait-pilot-review-decisions.json",
        "humanReviewReceipt": review_batch / "human-review-receipt.json",
        "orientationAdjustment": orientation_batch / "orientation-render-report.json",
        "aliasReceipt": alias_batch / "portrait-alias-receipt.json",
    }
    loaded = {name: load_json(path, name) for name, path in paths.items()}
    T.verify_object_digest(loaded["humanReviewReceipt"], "receiptDigest", "Arena 五项人审回执")
    T.verify_object_digest(loaded["directRender"], "renderDigest", "Arena 五项直接渲染", pilot=True)
    T.verify_object_digest(loaded["orientationAdjustment"], "reportDigest", "家用机器人方向修正", pilot=True)
    T.verify_object_digest(loaded["aliasReceipt"], "receiptDigest", "锡蒙利 alias 回执", pilot=True)

    receipt = loaded["humanReviewReceipt"]
    decisions = {
        row.get("reviewKey"): row
        for row in receipt.get("decisions", [])
        if isinstance(row, dict)
    }
    expected_statuses = {
        key: ("adjustment" if key == P.SUPPLEMENTAL_FLIP_REVIEW_KEY else "pass")
        for key in P.SUPPLEMENTAL_DIRECT_REVIEW_KEYS
    }
    if (
        receipt.get("status") != "human_reviewed_refinement_required"
        or receipt.get("productionReady") is not False
        or {key: row.get("status") for key, row in decisions.items()} != expected_statuses
        or any(row.get("blocked") is not False for row in decisions.values())
    ):
        raise SupplementalPromotionError("Arena 五项人审决定不是精确 4 pass + 1 adjustment")

    render = loaded["directRender"]
    direct_rows = [row for row in render.get("rows", []) if isinstance(row, dict)]
    proposal_keys = {
        row.get("reviewKey")
        for row in direct_rows
        if row.get("role") == "proposal"
    }
    if proposal_keys != P.SUPPLEMENTAL_DIRECT_REVIEW_KEYS:
        raise SupplementalPromotionError("Arena 五项 proposal 渲染键漂移")

    orientation = loaded["orientationAdjustment"]
    orientation_rows = orientation.get("rows", [])
    if (
        len(orientation_rows) != 1
        or orientation_rows[0].get("reviewKey") != P.SUPPLEMENTAL_FLIP_REVIEW_KEY
        or orientation_rows[0].get("operation") != "flip_x"
        or orientation_rows[0].get("fidelityComparison", {}).get("passed") is not True
    ):
        raise SupplementalPromotionError("家用机器人 flip_x 产物漂移")

    alias = loaded["aliasReceipt"]
    if (
        alias.get("status") != "human_alias_approved"
        or alias.get("decision", {}).get("sourcePortraitRef") != P.SUPPLEMENTAL_ALIAS_REF
        or alias.get("decision", {}).get("targetPortraitRef") != P.SUPPLEMENTAL_ALIAS_TARGET
        or alias.get("decision", {}).get("action") != "reuse"
    ):
        raise SupplementalPromotionError("锡蒙利发生器 alias 决定漂移")

    review_items = {
        item.get("reviewKey"): item
        for item in loaded["reviewData"].get("items", [])
        if isinstance(item, dict)
    }
    if set(review_items) != P.SUPPLEMENTAL_DIRECT_REVIEW_KEYS:
        raise SupplementalPromotionError("Arena 五项 review item 漂移")
    for review_key, item in review_items.items():
        portrait_ref = review_key.rsplit("::", 1)[0]
        if item.get("consumers", {}).get("arenaUnitIds") != DIRECT_UNIT_IDS[portrait_ref]:
            raise SupplementalPromotionError(f"Arena unit ID 漂移：{review_key}")

    return {
        "paths": paths,
        "loaded": loaded,
        "decisions": decisions,
        "directRows": direct_rows,
        "orientationRow": orientation_rows[0],
        "reviewItems": review_items,
    }


def preserve_base_evidence(output: Path, evidence_output: Path) -> dict[str, Path]:
    evidence_output.mkdir(parents=True)
    result = {
        "baseManifest": evidence_output / "base-manifest.json",
        "basePromotionReceipt": evidence_output / "base-promotion-receipt.json",
    }
    shutil.copyfile(output / "manifest.json", result["baseManifest"])
    shutil.copyfile(output / "promotion-receipt.json", result["basePromotionReceipt"])
    return result


def build_selections(collected: dict[str, Any]) -> dict[str, dict[str, Any]]:
    receipt_path = collected["paths"]["humanReviewReceipt"]
    decisions = {
        key: (row, receipt_path)
        for key, row in collected["decisions"].items()
    }
    direct_path = collected["paths"]["directRender"]
    direct_rows = [(row, direct_path) for row in collected["directRows"]]
    orientation_report = collected["loaded"]["orientationAdjustment"]
    corrections = {
        P.SUPPLEMENTAL_FLIP_REVIEW_KEY: (
            2,
            collected["orientationRow"],
            collected["paths"]["orientationAdjustment"],
            orientation_report,
        )
    }
    selections: dict[str, dict[str, Any]] = {}
    for review_key in sorted(P.SUPPLEMENTAL_DIRECT_REVIEW_KEYS):
        selection = T.accepted_selection(review_key, decisions, direct_rows, corrections)
        if selection is None:
            raise SupplementalPromotionError(f"Arena 增量接受选择缺失：{review_key}")
        selections[review_key] = selection
    return selections


def append_unique_artifacts(existing: list[Any], paths: list[Path]) -> list[Any]:
    result = [copy.deepcopy(record) for record in existing if isinstance(record, dict)]
    seen = {(record.get("path"), record.get("sha256")) for record in result}
    for path in paths:
        record = T.artifact(path)
        key = (record["path"], record["sha256"])
        if key not in seen:
            result.append(record)
            seen.add(key)
    return result


def build_staging(
    output: Path,
    staging: Path,
    evidence_output: Path,
    collected: dict[str, Any],
) -> dict[str, Any]:
    base_manifest = P.check_manifest(output / "manifest.json")
    if base_manifest.get("manifestDigest") != BASE_MANIFEST_DIGEST or base_manifest.get("counts") != P.EXPECTED_COUNTS:
        raise SupplementalPromotionError("基础正式包不是 r205 冻结版本")
    base_evidence = preserve_base_evidence(output, evidence_output)
    shutil.copytree(output, staging)

    selections = build_selections(collected)
    manifest = copy.deepcopy(base_manifest)
    entries = manifest["entries"]
    for review_key, selection in selections.items():
        portrait_ref, variant_key = review_key.rsplit("::", 1)
        accepted_variant = T.write_subject_assets(staging, selection)
        accepted_variant["provenance"]["supplementalScope"] = "arena-direct-gap-r215"
        entry = copy.deepcopy(entries.get(portrait_ref, {}))
        if not entry:
            entry = {
                "portraitRef": portrait_ref,
                "petIds": [],
                "enemyIds": [],
                "status": "ready",
                "defaultVariant": "default",
                "variants": {},
            }
        entry["portraitRef"] = portrait_ref
        entry["arenaUnitIds"] = DIRECT_UNIT_IDS[portrait_ref]
        entry["status"] = "ready"
        entry["defaultVariant"] = "default"
        entry.setdefault("petIds", [])
        entry.setdefault("enemyIds", [])
        entry.setdefault("variants", {})[variant_key] = accepted_variant
        entries[portrait_ref] = entry

    alias_receipt_path = collected["paths"]["aliasReceipt"]
    alias_record = {
        "targetPortraitRef": P.SUPPLEMENTAL_ALIAS_TARGET,
        "variantKey": "default",
        "provenance": T.artifact(alias_receipt_path),
    }
    manifest["aliases"][P.SUPPLEMENTAL_ALIAS_REF] = alias_record
    entries[P.SUPPLEMENTAL_ALIAS_REF] = {
        "portraitRef": P.SUPPLEMENTAL_ALIAS_REF,
        "petIds": [],
        "enemyIds": [],
        "arenaUnitIds": ALIAS_UNIT_IDS,
        "status": "identity_alias",
        "defaultVariant": "default",
        "variants": {
            "default": {
                "status": "identity_alias",
                "targetPortraitRef": P.SUPPLEMENTAL_ALIAS_TARGET,
                "targetVariantKey": "default",
                "reason": "human-approved reuse of the visible Simonli identity for its logic-only range aura generator",
            }
        },
    }

    closure_input_paths = {
        **base_evidence,
        **collected["paths"],
        "controller": Path(__file__),
    }
    closure_inputs = {name: T.artifact(path) for name, path in closure_input_paths.items()}
    orientation_actions = {
        key: ("flip_x" if key == P.SUPPLEMENTAL_FLIP_REVIEW_KEY else "keep")
        for key in sorted(P.SUPPLEMENTAL_DIRECT_REVIEW_KEYS)
    }
    closure: dict[str, Any] = {
        "schema": SCHEMA,
        "status": "arena_supplemental_portraits_promoted",
        "baseManifestDigest": BASE_MANIFEST_DIGEST,
        "directReviewKeys": sorted(P.SUPPLEMENTAL_DIRECT_REVIEW_KEYS),
        "aliasReviewKey": f"{P.SUPPLEMENTAL_ALIAS_REF}::default",
        "orientationActions": orientation_actions,
        "counts": {"directHumanAccepted": 5, "identityAliases": 1, "combinedArenaReady": 217},
        "inputs": closure_inputs,
        "gates": {
            "baseProductionManifestVerified": True,
            "fourPassOneOrientationAdjustmentBound": True,
            "orientationAdjustmentPixelExact": True,
            "explicitSimonliAliasReceiptBound": True,
            "contentAddressedSubjectsWritten": True,
            "productionWrites": True,
        },
    }
    closure["closureDigest"] = T.sha256_bytes(T.stable_bytes(closure))

    manifest["generatedAt"] = T.utc_now()
    manifest["counts"] = copy.deepcopy(P.SUPPLEMENTAL_EXPECTED_COUNTS)
    manifest["sourceEnvelope"]["inputs"] = append_unique_artifacts(
        manifest["sourceEnvelope"].get("inputs", []),
        list(closure_input_paths.values()),
    )
    manifest["supplementalPromotion"] = closure
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = T.manifest_digest(manifest)
    manifest_path = staging / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    old_receipt = load_json(output / "promotion-receipt.json", "基础 promotion receipt")
    receipt: dict[str, Any] = {
        "schema": "cf7.enemy-portrait-promotion-receipt.v1",
        "status": "enemy_portrait_pack_promoted",
        "generatedAt": manifest["generatedAt"],
        "manifest": {
            "path": T.repo_rel(output / "manifest.json"),
            "bytes": manifest_path.stat().st_size,
            "sha256": T.sha256_file(manifest_path),
        },
        "manifestDigest": manifest["manifestDigest"],
        "counts": copy.deepcopy(P.SUPPLEMENTAL_EXPECTED_COUNTS),
        "orientationAudit": copy.deepcopy(manifest["orientationAudit"]),
        "supplementalPromotion": {
            "schema": closure["schema"],
            "closureDigest": closure["closureDigest"],
            "baseManifestDigest": closure["baseManifestDigest"],
            "counts": copy.deepcopy(closure["counts"]),
        },
        "gates": {
            **copy.deepcopy(old_receipt.get("gates", {})),
            "arenaSupplementalHumanReviewPromoted": True,
            "arenaSupplementalOrientationClosed": True,
            "simonliGeneratorAliasBound": True,
            "arenaCatalogCoverageReady": True,
            "supplementalPromotionAtomic": True,
            "productionWrites": True,
        },
    }
    receipt["receiptDigest"] = T.sha256_bytes(T.stable_bytes(receipt))
    (staging / "promotion-receipt.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest


def promote(args: argparse.Namespace) -> None:
    output = T.resolve_output(Path(args.output))
    if not output.is_dir():
        raise SupplementalPromotionError(f"基础正式包不存在：{output}")
    evidence_output = ensure_pilot_output(Path(args.evidence_output), allow_existing=False)
    review_batch = Path(args.review_batch).resolve()
    orientation_batch = Path(args.orientation_batch).resolve()
    alias_batch = Path(args.alias_batch).resolve()
    collected = collect_inputs(review_batch, orientation_batch, alias_batch)

    staging = output.with_name(f"{output.name}.staging-arena-supplement-{os.getpid()}")
    if staging.exists():
        raise SupplementalPromotionError(f"staging 已存在：{staging}")
    manifest = build_staging(output, staging, evidence_output, collected)

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    backup_root = PILOT_ROOT / "enemy-portrait-production-backups"
    backup_root.mkdir(parents=True, exist_ok=True)
    backup = backup_root / f"enemy-portraits-supplement-base-{BASE_MANIFEST_DIGEST[:16].lower()}-{stamp}"
    if backup.exists():
        raise SupplementalPromotionError(f"rollback backup 已存在：{backup}")

    os.replace(output, backup)
    try:
        os.replace(staging, output)
        checked = P.check_manifest(output / "manifest.json")
    except Exception:
        failed_root = PILOT_ROOT / "failed-enemy-promotion-staging"
        failed_root.mkdir(parents=True, exist_ok=True)
        failed = failed_root / f"enemy-portraits.arena-supplement-failed-{stamp}-{os.getpid()}"
        if output.exists():
            os.replace(output, failed)
        if backup.exists():
            os.replace(backup, output)
        raise

    print(json.dumps({
        "status": "arena_supplemental_portraits_promoted",
        "output": T.repo_rel(output),
        "manifestDigest": manifest["manifestDigest"],
        "supplementalClosureDigest": manifest["supplementalPromotion"]["closureDigest"],
        "counts": checked["counts"],
        "rollbackBackup": T.repo_rel(backup),
        "evidenceOutput": T.repo_rel(evidence_output),
    }, ensure_ascii=False))


def preflight(args: argparse.Namespace) -> None:
    output = T.resolve_output(Path(args.output))
    manifest_path = output / "manifest.json"
    manifest = P.check_manifest(manifest_path)
    if manifest.get("manifestDigest") != BASE_MANIFEST_DIGEST:
        raise SupplementalPromotionError(
            f"基础正式包摘要漂移：{manifest.get('manifestDigest')} != {BASE_MANIFEST_DIGEST}"
        )
    evidence_output = ensure_pilot_output(Path(args.evidence_output), allow_existing=False)
    collected = collect_inputs(
        Path(args.review_batch).resolve(),
        Path(args.orientation_batch).resolve(),
        Path(args.alias_batch).resolve(),
    )
    print(json.dumps({
        "status": "arena_supplemental_portraits_preflight_verified",
        "productionWrites": False,
        "baseManifest": T.repo_rel(manifest_path),
        "baseManifestDigest": manifest["manifestDigest"],
        "directReviewKeys": sorted(collected["reviewItems"]),
        "orientationOperation": collected["orientationRow"]["operation"],
        "alias": collected["loaded"]["aliasReceipt"]["decision"],
        "evidenceOutput": T.repo_rel(evidence_output),
    }, ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve()
    manifest = P.check_manifest(manifest_path)
    if not isinstance(manifest.get("supplementalPromotion"), dict):
        raise SupplementalPromotionError("正式包尚未包含 Arena supplement")
    print(json.dumps({
        "status": "arena_supplemental_portraits_verified",
        "manifest": T.repo_rel(manifest_path),
        "manifestDigest": manifest["manifestDigest"],
        "supplementalClosureDigest": manifest["supplementalPromotion"]["closureDigest"],
        "counts": manifest["counts"],
    }, ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    sub = root.add_subparsers(dest="command", required=True)
    preflight_parser = sub.add_parser("preflight")
    preflight_parser.add_argument("--review-batch", default=str(DEFAULT_REVIEW_BATCH))
    preflight_parser.add_argument("--orientation-batch", default=str(DEFAULT_ORIENTATION_BATCH))
    preflight_parser.add_argument("--alias-batch", default=str(DEFAULT_ALIAS_BATCH))
    preflight_parser.add_argument("--evidence-output", default=str(DEFAULT_EVIDENCE_OUTPUT))
    preflight_parser.add_argument("--output", default=str(T.DEFAULT_OUTPUT))
    preflight_parser.set_defaults(handler=preflight)
    promote_parser = sub.add_parser("promote")
    promote_parser.add_argument("--review-batch", default=str(DEFAULT_REVIEW_BATCH))
    promote_parser.add_argument("--orientation-batch", default=str(DEFAULT_ORIENTATION_BATCH))
    promote_parser.add_argument("--alias-batch", default=str(DEFAULT_ALIAS_BATCH))
    promote_parser.add_argument("--evidence-output", default=str(DEFAULT_EVIDENCE_OUTPUT))
    promote_parser.add_argument("--output", default=str(T.DEFAULT_OUTPUT))
    promote_parser.set_defaults(handler=promote)
    check_parser = sub.add_parser("check")
    check_parser.add_argument("--manifest", default=str(T.DEFAULT_OUTPUT / "manifest.json"))
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        args.handler(args)
    except (SupplementalPromotionError, T.PromotionError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"[arena-portrait-supplement] ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
