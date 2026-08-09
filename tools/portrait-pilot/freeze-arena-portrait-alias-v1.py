#!/usr/bin/env python3
"""Freeze an explicit human-approved Arena portrait alias.

This controller is intentionally narrow.  It only accepts the Simonli range
aura generator, proves that the extracted internal sprite is a degenerate
single-frame logic graphic rather than a recognisable unit, and binds the
decision to the already promoted Simonli portrait.  It never writes the
production manifest.
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import re
import sys
from pathlib import Path
from typing import Any

from PIL import Image

import prepare_pilot as core


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
SCHEMA = "cf7.arena-portrait-alias-receipt.v1"
SOURCE_REF = "敌人-锡蒙利范围光环发生器"
TARGET_REF = "敌人-锡蒙利"
SOURCE_UNIT_ID = 334
TARGET_UNIT_ID = 335
SOURCE_CHARACTER_ID = 921
DEFAULT_EVIDENCE = PILOT_ROOT / "arena-gap-subject-r212-simonli-20260809T203000Z"
DEFAULT_MANIFEST = ROOT / "launcher" / "web" / "assets" / "enemy-portraits" / "manifest.json"


class AliasError(RuntimeError):
    pass


def load_json(path: Path, label: str) -> dict[str, Any] | list[Any]:
    if not path.is_file():
        raise AliasError(f"{label} 缺失：{path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AliasError(f"{label} 不是合法 JSON：{error}") from error
    if not isinstance(value, (dict, list)):
        raise AliasError(f"{label} 顶层必须是对象或数组")
    return value


def verify_digest(value: dict[str, Any], field: str, label: str) -> None:
    clone = copy.deepcopy(value)
    expected = clone.pop(field, None)
    if not isinstance(expected, str) or core.sha256_bytes(core.stable_bytes(clone)) != expected:
        raise AliasError(f"{label} {field} 漂移")


def ensure_output(path: Path, *, allow_existing: bool) -> Path:
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(PILOT_ROOT.resolve())
    except ValueError as error:
        raise AliasError("输出必须位于 tmp/portrait-pilot") from error
    if not relative.parts:
        raise AliasError("输出不能是 tmp/portrait-pilot 根目录")
    if resolved.exists() and not allow_existing:
        raise AliasError(f"输出已存在，禁止覆盖：{resolved}")
    return resolved


def verify_units() -> dict[str, Any]:
    units_path = ROOT / "data" / "units" / "units.json"
    units = load_json(units_path, "units.json")
    if not isinstance(units, list):
        raise AliasError("units.json 顶层不是数组")
    by_ref = {
        row.get("spritename"): row
        for row in units
        if isinstance(row, dict) and row.get("spritename") in {SOURCE_REF, TARGET_REF}
    }
    source = by_ref.get(SOURCE_REF)
    target = by_ref.get(TARGET_REF)
    if source is None or target is None:
        raise AliasError("锡蒙利 source/target 单位缺失")
    if source.get("id") != SOURCE_UNIT_ID or target.get("id") != TARGET_UNIT_ID:
        raise AliasError(f"锡蒙利相邻单位 ID 漂移：{source.get('id')}/{target.get('id')}")
    return {
        "units": core.artifact(units_path),
        "sourceUnit": {"id": SOURCE_UNIT_ID, "name": source.get("name"), "portraitRef": SOURCE_REF},
        "targetUnit": {"id": TARGET_UNIT_ID, "name": target.get("name"), "portraitRef": TARGET_REF},
    }


def verify_degenerate_evidence(evidence_root: Path) -> dict[str, Any]:
    command_path = evidence_root / "selected-frame-logs" / "source-001-selected-sprite-samples.command.json"
    stdout_path = evidence_root / "selected-frame-logs" / "source-001-selected-sprite-samples.stdout.bin"
    image_path = evidence_root / "selected-sprite-samples" / "source-001" / f"DefineSprite_{SOURCE_CHARACTER_ID}" / "1.png"
    command = load_json(command_path, "透明主体导出命令")
    if not isinstance(command, dict) or command.get("exitCode") != 0:
        raise AliasError("透明主体导出命令未成功闭合")
    stdout = stdout_path.read_text(encoding="utf-8")
    if (
        f"characterId={SOURCE_CHARACTER_ID} frames=1" not in stdout
        or "spriteCount=1" not in stdout
        or "status=selected_sprite_samples_exported" not in stdout
    ):
        raise AliasError("透明主体导出 stdout 与唯一单帧事实不符")
    with Image.open(image_path) as opened:
        rgba = opened.convert("RGBA")
        alpha = rgba.getchannel("A")
        alpha_bbox = alpha.getbbox()
        alpha_extrema = alpha.getextrema()
        size = list(rgba.size)
        colors = rgba.getcolors(maxcolors=1024)
        if colors is None:
            raise AliasError("范围发生器内部 Sprite 颜色数异常")
        visible_pixels = sum(count for count, color in colors if color[3] > 0)
        chromatic_pixels = sum(count for count, color in colors if color[:3] != (0, 0, 0))
    pixel_count = size[0] * size[1]
    visible_ratio = visible_pixels / pixel_count if pixel_count else 1.0
    if (
        size != [57, 3]
        or alpha_bbox != (0, 0, 57, 3)
        or alpha_extrema != (0, 191)
        or visible_pixels != 6
        or visible_ratio > 0.04
        or chromatic_pixels != 0
    ):
        raise AliasError(
            "范围发生器内部 Sprite 不再是已审计的 57x3 退化逻辑图形："
            f"size={size} alpha={alpha_extrema} visible={visible_pixels}/{pixel_count} chromatic={chromatic_pixels}"
        )
    return {
        "exportCommand": core.artifact(command_path),
        "exportStdout": core.artifact(stdout_path),
        "degenerateFrame": {
            **core.artifact(image_path),
            "characterId": SOURCE_CHARACTER_ID,
            "frame": 1,
            "size": size,
            "alphaExtrema": list(alpha_extrema),
            "alphaBounds": list(alpha_bbox),
            "visiblePixels": visible_pixels,
            "pixelCount": pixel_count,
            "visibleRatio": visible_ratio,
            "chromaticPixels": chromatic_pixels,
        },
    }


def verify_target(manifest_path: Path) -> dict[str, Any]:
    manifest = load_json(manifest_path, "正式头像 manifest")
    if not isinstance(manifest, dict):
        raise AliasError("正式头像 manifest 顶层不是对象")
    clone = copy.deepcopy(manifest)
    expected = clone.pop("manifestDigest", None)
    if not isinstance(expected, str) or core.sha256_bytes(core.stable_bytes(clone)) != expected:
        raise AliasError("正式头像 manifestDigest 漂移")
    variant = (
        manifest.get("entries", {})
        .get(TARGET_REF, {})
        .get("variants", {})
        .get("default", {})
    )
    if variant.get("status") != "human_accepted":
        raise AliasError("锡蒙利目标头像不是 human_accepted")
    subject = variant.get("subject", {})
    target_artifacts: dict[str, Any] = {}
    for kind in ("svg", "pngFallback"):
        record = subject.get(kind)
        if not isinstance(record, dict) or not isinstance(record.get("url"), str):
            raise AliasError(f"锡蒙利目标头像缺 {kind}")
        path = ROOT / "launcher" / "web" / record["url"]
        if not path.is_file() or path.stat().st_size != record.get("bytes") or core.sha256_file(path) != record.get("sha256"):
            raise AliasError(f"锡蒙利目标头像 {kind} 漂移")
        target_artifacts[kind] = core.artifact(path)
    return {
        "productionManifestPath": core.repo_rel(manifest_path),
        "productionManifestDigest": manifest["manifestDigest"],
        "targetVariant": {
            "reviewKey": f"{TARGET_REF}::default",
            "status": "human_accepted",
            "svg": target_artifacts["svg"],
            "pngFallback": target_artifacts["pngFallback"],
        },
    }


def build(args: argparse.Namespace) -> None:
    output = ensure_output(Path(args.output), allow_existing=False)
    if args.decision != "reuse":
        raise AliasError("本控制器只接受显式 --decision reuse")
    if not isinstance(args.reason, str) or len(args.reason.strip()) < 4:
        raise AliasError("复用理由过短")
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", args.batch_id) is None:
        raise AliasError("batch id 非法")
    evidence_root = Path(args.evidence).resolve()
    identity_evidence = verify_units()
    source_evidence = verify_degenerate_evidence(evidence_root)
    target_evidence = verify_target(Path(args.manifest).resolve())
    output.mkdir(parents=True)
    receipt: dict[str, Any] = {
        "schema": SCHEMA,
        "status": "human_alias_approved",
        "productionReady": False,
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "batchId": args.batch_id,
        "decision": {
            "action": "reuse",
            "sourcePortraitRef": SOURCE_REF,
            "targetPortraitRef": TARGET_REF,
            "targetVariantKey": "default",
            "reason": args.reason.strip(),
        },
        "identityEvidence": identity_evidence,
        "sourceEvidence": source_evidence,
        "targetEvidence": target_evidence,
        "controller": core.artifact(Path(__file__)),
        "gates": {
            "explicitHumanReuseDecision": True,
            "sourceAndTargetUnitIdsBound": True,
            "sourceInternalSpriteIsSingleFrameDegenerateLogic": True,
            "targetVariantIsHumanAccepted": True,
            "identityAliasDoesNotDuplicateSubject": True,
            "productionWrites": False,
        },
    }
    receipt["receiptDigest"] = core.sha256_bytes(core.stable_bytes(receipt))
    core.write_json(output / "portrait-alias-receipt.json", receipt)
    print(json.dumps({
        "status": receipt["status"],
        "receipt": core.repo_rel(output / "portrait-alias-receipt.json"),
        "receiptDigest": receipt["receiptDigest"],
        "sourcePortraitRef": SOURCE_REF,
        "targetPortraitRef": TARGET_REF,
        "productionWrites": False,
    }, ensure_ascii=False))


def check(args: argparse.Namespace) -> None:
    output = ensure_output(Path(args.output), allow_existing=True)
    path = output / "portrait-alias-receipt.json"
    receipt = load_json(path, "头像 alias 回执")
    if not isinstance(receipt, dict):
        raise AliasError("头像 alias 回执顶层不是对象")
    verify_digest(receipt, "receiptDigest", "头像 alias 回执")
    if (
        receipt.get("schema") != SCHEMA
        or receipt.get("status") != "human_alias_approved"
        or receipt.get("productionReady") is not False
        or receipt.get("decision")
        != {
            "action": "reuse",
            "sourcePortraitRef": SOURCE_REF,
            "targetPortraitRef": TARGET_REF,
            "targetVariantKey": "default",
            "reason": receipt.get("decision", {}).get("reason"),
        }
    ):
        raise AliasError("头像 alias 回执 schema/status/decision 非法")
    expected_gates = {
        "explicitHumanReuseDecision",
        "sourceAndTargetUnitIdsBound",
        "sourceInternalSpriteIsSingleFrameDegenerateLogic",
        "targetVariantIsHumanAccepted",
        "identityAliasDoesNotDuplicateSubject",
    }
    if any(receipt.get("gates", {}).get(key) is not True for key in expected_gates) or receipt.get("gates", {}).get("productionWrites") is not False:
        raise AliasError("头像 alias 回执 gates 未闭合")
    for record in (
        receipt["identityEvidence"]["units"],
        receipt["sourceEvidence"]["exportCommand"],
        receipt["sourceEvidence"]["exportStdout"],
        receipt["sourceEvidence"]["degenerateFrame"],
        receipt["targetEvidence"]["targetVariant"]["svg"],
        receipt["targetEvidence"]["targetVariant"]["pngFallback"],
        receipt["controller"],
    ):
        core.verify_artifact_record(record, "头像 alias 证据")
    verify_units()
    verify_degenerate_evidence(Path(args.evidence).resolve())
    print(json.dumps({
        "status": "human_alias_receipt_verified",
        "receiptDigest": receipt["receiptDigest"],
        "sourcePortraitRef": SOURCE_REF,
        "targetPortraitRef": TARGET_REF,
        "productionWrites": False,
    }, ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    sub = root.add_subparsers(dest="command", required=True)
    build_parser = sub.add_parser("build")
    build_parser.add_argument("--output", required=True)
    build_parser.add_argument("--batch-id", required=True)
    build_parser.add_argument("--decision", choices=("reuse",), required=True)
    build_parser.add_argument("--reason", required=True)
    build_parser.add_argument("--evidence", default=str(DEFAULT_EVIDENCE))
    build_parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    build_parser.set_defaults(handler=build)
    check_parser = sub.add_parser("check")
    check_parser.add_argument("--output", required=True)
    check_parser.add_argument("--evidence", default=str(DEFAULT_EVIDENCE))
    check_parser.set_defaults(handler=check)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        args.handler(args)
    except (AliasError, core.PilotError, OSError, ValueError, KeyError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
