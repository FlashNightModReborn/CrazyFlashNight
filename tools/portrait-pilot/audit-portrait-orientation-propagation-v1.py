#!/usr/bin/env python3
"""Audit orientation lineage for every promoted enemy portrait variant.

This audit is intentionally split from visual judgement.  It proves whether the
published SVG/PNG preserved a direction decision that already exists in the
signed Luna/human pipeline, and it explicitly identifies older rows for which
the historical model schema never recorded a direction decision.
"""

from __future__ import annotations

import argparse
import collections
import copy
import importlib.util
import io
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
ENEMY_CONTROLLER = Path(__file__).with_name("promote-enemy-portraits-v1.py")
SUPPLEMENT_CONTROLLER = Path(__file__).with_name("promote-arena-portrait-supplement-v1.py")
REPORT_NAME = "orientation-propagation-audit.json"
REPORT_SCHEMA = "cf7.portrait-orientation-propagation-audit.v1"


class AuditError(RuntimeError):
    pass


def load_enemy_controller() -> Any:
    spec = importlib.util.spec_from_file_location("cf7_enemy_portrait_promotion_audit", ENEMY_CONTROLLER)
    if spec is None or spec.loader is None:
        raise AuditError(f"无法加载头像发布器：{ENEMY_CONTROLLER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


E = load_enemy_controller()
T = E.T


def load_supplement_controller() -> Any:
    spec = importlib.util.spec_from_file_location(
        "cf7_arena_portrait_supplement_for_orientation_audit",
        SUPPLEMENT_CONTROLLER,
    )
    if spec is None or spec.loader is None:
        raise AuditError(f"无法加载 Arena 头像增量发布器：{SUPPLEMENT_CONTROLLER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S = load_supplement_controller()


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AuditError(f"{label}不可读：{path}: {error}") from error
    if not isinstance(value, dict):
        raise AuditError(f"{label}顶层必须是对象：{path}")
    return value


def pilot_child(path: Path, label: str, *, allow_existing: bool) -> Path:
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(PILOT_ROOT.resolve())
    except ValueError as error:
        raise AuditError(f"{label}必须位于 tmp/portrait-pilot：{resolved}") from error
    if not relative.parts:
        raise AuditError(f"{label}不得是 tmp/portrait-pilot 根目录")
    if resolved.exists() and not allow_existing:
        raise AuditError(f"{label}已存在，禁止覆盖：{resolved}")
    return resolved


def mirrored_png_bytes(path: Path) -> bytes:
    with Image.open(path) as opened:
        transformed = opened.convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        stream = io.BytesIO()
        transformed.save(stream, format="PNG", optimize=False, compress_level=9)
        return stream.getvalue()


def selections() -> tuple[dict[str, dict[str, Any]], list[Path], dict[str, Any]]:
    decisions, direct_rows, corrections, calibration_manifests = T.collect_calibration(
        E.DEFAULT_CAMPAIGN,
        expected_decision_count=203,
        expected_statuses={"adjustment": 116, "pass": 86, "source": 1},
        expected_correction_count=116,
    )
    gap_decisions, gap_direct_rows, gap_inputs = T.collect_team_gap(T.DEFAULT_TEAM_GAP_BATCH)
    if set(decisions).intersection(gap_decisions):
        raise AuditError("累计回执与 Team 尾项回执发生 reviewKey 重叠")
    decisions.update(gap_decisions)
    direct_rows.extend(gap_direct_rows)
    representatives = T.representative_selections(T.DEFAULT_REPRESENTATIVE_CLOSURE, direct_rows)
    orientation_closure = E.load_orientation_closure()
    inventory = T.load_json(T.DEFAULT_INVENTORY, "portrait inventory")
    result: dict[str, dict[str, Any]] = {}
    for item in inventory.get("items", []):
        portrait_ref = item.get("portraitRef")
        for variant_key in item.get("variantKeys") or ["default"]:
            review_key = f"{portrait_ref}::{variant_key}"
            selection = E.selection_for(review_key, decisions, direct_rows, corrections, representatives)
            if selection is not None:
                selection = E.apply_orientation_closure(review_key, selection, orientation_closure)
                if review_key in result:
                    raise AuditError(f"接受选择重复：{review_key}")
                result[review_key] = selection
    inputs = [
        T.DEFAULT_INVENTORY,
        E.DEFAULT_CAMPAIGN,
        T.DEFAULT_REPRESENTATIVE_CLOSURE,
        T.DEFAULT_TEAM_GAP_BATCH / "human-review-receipt.json",
        *calibration_manifests,
        *gap_inputs,
        *orientation_closure["sourceInputs"],
    ]
    unique_inputs = list(dict.fromkeys(path.resolve() for path in inputs))
    return result, unique_inputs, orientation_closure


def supplemental_selections(manifest: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], list[Path]]:
    closure = E.check_supplemental_promotion(manifest)
    inputs = closure["inputs"]
    human_receipt = T.verify_artifact_record(inputs["humanReviewReceipt"], "Arena 增量人审回执")
    orientation = T.verify_artifact_record(inputs["orientationAdjustment"], "Arena 增量方向修正")
    alias_receipt = T.verify_artifact_record(inputs["aliasReceipt"], "Arena 增量 alias 回执")
    collected = S.collect_inputs(human_receipt.parent, orientation.parent, alias_receipt.parent)
    result = S.build_selections(collected)
    if set(result) != E.SUPPLEMENTAL_DIRECT_REVIEW_KEYS:
        raise AuditError("Arena 增量方向选择键漂移")
    lineage = list(collected["paths"].values()) + [SUPPLEMENT_CONTROLLER]
    return result, lineage


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest = T.load_json(manifest_path, "通用敌人头像 manifest")
    supplemental = isinstance(manifest.get("supplementalPromotion"), dict)
    expected_counts = E.SUPPLEMENTAL_EXPECTED_COUNTS if supplemental else E.EXPECTED_COUNTS
    if (
        manifest.get("schema") != "cf7.enemy-portrait-manifest.v1"
        or manifest.get("status") != "human_accepted_portraits_promoted"
        or T.manifest_digest(manifest) != manifest.get("manifestDigest")
        or manifest.get("counts") != expected_counts
    ):
        raise AuditError("通用敌人头像 manifest schema/status/digest/counts 未闭合")
    expected, lineage_inputs, orientation_closure = selections()
    if supplemental:
        additional, additional_inputs = supplemental_selections(manifest)
        if set(expected).intersection(additional):
            raise AuditError("基础方向选择与 Arena 增量方向选择发生重叠")
        expected.update(additional)
        lineage_inputs = list(dict.fromkeys([*lineage_inputs, *additional_inputs]))
    accepted_rows: list[tuple[str, dict[str, Any]]] = []
    for portrait_ref, entry in manifest.get("entries", {}).items():
        for variant_key, variant in entry.get("variants", {}).items():
            if variant.get("status") == "human_accepted":
                accepted_rows.append((f"{portrait_ref}::{variant_key}", variant))
    accepted_rows.sort(key=lambda value: value[0])
    expected_accepted = expected_counts["humanAcceptedVariantCount"]
    if len(accepted_rows) != expected_accepted or set(key for key, _variant in accepted_rows) != set(expected):
        raise AuditError(
            f"生产接受集与来源选择不闭合：production={len(accepted_rows)} selection={len(expected)}"
        )

    rows: list[dict[str, Any]] = []
    source_counts: collections.Counter[str] = collections.Counter()
    action_mismatches = 0
    svg_mismatches = 0
    png_mismatches = 0
    unassessed = 0
    for review_key, variant in accepted_rows:
        selection = expected[review_key]
        expected_action = "flip_x" if selection["flipX"] else "keep"
        orientation_source = selection["orientationSource"]
        source_counts[orientation_source] += 1
        if orientation_source == "legacy_orientation_unassessed":
            unassessed += 1
        provenance = variant.get("provenance", {})
        current_action = provenance.get("orientationAction")
        action_mismatch = current_action != expected_action
        action_mismatches += int(action_mismatch)

        expected_svg = T.build_cropped_svg(
            selection["sourceSvg"], selection["viewBox"], selection["flipX"]
        )
        current_svg = variant["subject"]["svg"]
        svg_mismatch = current_svg.get("sha256") != T.sha256_bytes(expected_svg)
        svg_mismatches += int(svg_mismatch)

        master_path: Path = selection["masterPath"]
        expected_png = (
            mirrored_png_bytes(master_path)
            if selection.get("rasterNeedsFlip") is True
            else master_path.read_bytes()
        )
        current_png = variant["subject"]["pngFallback"]
        png_mismatch = current_png.get("sha256") != T.sha256_bytes(expected_png)
        png_mismatches += int(png_mismatch)

        rows.append(
            {
                "reviewKey": review_key,
                "resolution": selection["resolution"],
                "currentOrientationAction": current_action,
                "expectedOrientationAction": expected_action,
                "orientationSource": orientation_source,
                "rasterNeedsFlipAfterHumanCrop": selection.get("rasterNeedsFlip") is True,
                "actionMismatch": action_mismatch,
                "svgMismatch": svg_mismatch,
                "pngFallbackMismatch": png_mismatch,
                "legacyVisualAuditRequired": orientation_source == "legacy_orientation_unassessed",
                "decisionNotes": selection["decision"].get("notes", ""),
                "acceptedMaster": T.artifact(master_path),
                "productionSvg": copy.deepcopy(current_svg),
                "productionPngFallback": copy.deepcopy(current_png),
            }
        )

    report: dict[str, Any] = {
        "schema": REPORT_SCHEMA,
        "status": "orientation_propagation_audited",
        "productionReady": False,
        "generatedAt": T.utc_now(),
        "scope": {
            "acceptedVariantCount": len(rows),
            "contract": "canonical portrait-right; symmetric, frontal, or directionless subjects keep",
            "visualJudgementIncluded": False,
        },
        "inputs": {
            "productionManifest": T.artifact(manifest_path),
            "lineageArtifacts": [T.artifact(path) for path in lineage_inputs],
            "controller": T.artifact(Path(__file__)),
            "promotionControllers": [
                T.artifact(ENEMY_CONTROLLER),
                T.artifact(ENEMY_CONTROLLER.with_name("promote-team-portraits-v1.py")),
                *([T.artifact(SUPPLEMENT_CONTROLLER)] if supplemental else []),
            ],
            "orientationClosure": T.artifact(orientation_closure["receiptPath"]),
        },
        "orientationAudit": E.orientation_manifest_summary(orientation_closure),
        "supplementalPromotion": (
            {
                "closureDigest": manifest["supplementalPromotion"]["closureDigest"],
                "directReviewKeys": sorted(E.SUPPLEMENTAL_DIRECT_REVIEW_KEYS),
                "orientationActions": copy.deepcopy(manifest["supplementalPromotion"]["orientationActions"]),
            }
            if supplemental
            else None
        ),
        "counts": {
            "acceptedVariants": len(rows),
            "actionMismatches": action_mismatches,
            "svgMismatches": svg_mismatches,
            "pngFallbackMismatches": png_mismatches,
            "legacyVisualAuditRequired": unassessed,
            "orientationSources": dict(sorted(source_counts.items())),
        },
        "rows": rows,
        "gates": {
            "allAcceptedVariantsBound": len(rows) == expected_accepted,
            "signedDirectionPropagationChecked": True,
            "svgAndPngCheckedIndependently": True,
            "legacyMissingDirectionNotTreatedAsKeepEvidence": True,
            "visualDirectionAuditStillRequired": unassessed > 0,
            "fullVisualAuditClosureApplied": unassessed == 0,
            "allRiskRowsBoundToHumanDecision": source_counts.get(E.HUMAN_ORIENTATION_SOURCE, 0) == 39,
            "allModelClosedKeepsBound": source_counts.get(E.MODEL_ORIENTATION_SOURCE, 0) == 178,
            "allSupplementalHumanReviewedDirectionsBound": (
                source_counts.get("direct_model_orientation", 0) == 4
                and source_counts.get("explicit_human_post_crop_flip", 0) == 1
                if supplemental
                else True
            ),
            "productionWrites": False,
        },
    }
    report["reportDigest"] = T.sha256_bytes(T.stable_bytes(report))
    return report


def verify_report(report_path: Path, *, require_current_manifest: bool) -> dict[str, Any]:
    report = load_json(report_path, "方向传播审计")
    clone = copy.deepcopy(report)
    digest = clone.pop("reportDigest", None)
    if report.get("schema") != REPORT_SCHEMA or digest != T.sha256_bytes(T.stable_bytes(clone)):
        raise AuditError("方向传播审计 schema 或 reportDigest 漂移")
    T.verify_artifact_record(report["inputs"]["controller"], "方向审计 controller")
    for record in report["inputs"].get("promotionControllers", []):
        T.verify_artifact_record(record, "方向审计 promotion controller")
    T.verify_artifact_record(report["inputs"].get("orientationClosure"), "方向审计完整视觉闭包")
    manifest_path = T.verify_artifact_record(report["inputs"]["productionManifest"], "方向审计生产 manifest")
    for record in report["inputs"].get("lineageArtifacts", []):
        T.verify_artifact_record(record, "方向审计 lineage artifact")
    if require_current_manifest:
        current = build_report(manifest_path)
        comparable = copy.deepcopy(report)
        comparable.pop("generatedAt", None)
        comparable.pop("reportDigest", None)
        rebuilt = copy.deepcopy(current)
        rebuilt.pop("generatedAt", None)
        rebuilt.pop("reportDigest", None)
        if T.stable_bytes(comparable) != T.stable_bytes(rebuilt):
            raise AuditError("方向传播审计与当前生产/来源状态不一致")
    return report


def command_build(args: argparse.Namespace) -> None:
    output = pilot_child(Path(args.output), "方向审计输出", allow_existing=False)
    manifest_path = Path(args.manifest).resolve()
    report = build_report(manifest_path)
    output.mkdir(parents=True)
    report_path = output / REPORT_NAME
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "status": report["status"],
                "report": T.repo_rel(report_path),
                "reportDigest": report["reportDigest"],
                "counts": report["counts"],
            },
            ensure_ascii=False,
        )
    )


def command_check(args: argparse.Namespace) -> None:
    output = pilot_child(Path(args.output), "方向审计输出", allow_existing=True)
    report = verify_report(output / REPORT_NAME, require_current_manifest=args.current)
    print(
        json.dumps(
            {
                "status": "orientation_propagation_audit_verified",
                "reportDigest": report["reportDigest"],
                "counts": report["counts"],
            },
            ensure_ascii=False,
        )
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    sub = result.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build")
    build.add_argument("--manifest", default=str(T.DEFAULT_OUTPUT / "manifest.json"))
    build.add_argument("--output", required=True)
    build.set_defaults(handler=command_build)
    check = sub.add_parser("check")
    check.add_argument("--output", required=True)
    check.add_argument("--current", action="store_true")
    check.set_defaults(handler=command_check)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        args.handler(args)
    except (AuditError, T.PromotionError, OSError, KeyError, ValueError) as error:
        print(f"[portrait-orientation-audit] ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
