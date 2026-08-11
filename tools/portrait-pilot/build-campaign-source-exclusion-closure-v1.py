#!/usr/bin/env python3
"""Close the two remaining missing portrait refs as verified non-runtime exclusions."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


CONTROLLER_PATH = Path(__file__).resolve()
ATLAS_V8_PATH = CONTROLLER_PATH.with_name("attach-feedback-atlas-v8.py")
ROOT = CONTROLLER_PATH.parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
SERPENT_REF = "敌人-Serpent"
MAI_REF = "敌人-不知火舞"
SERPENT_SWF = ROOT / "flashswf" / "arts" / "new" / "天网豪华单间.swf"
SERPENT_FLA = ROOT / "flashswf" / "arts" / "new" / "天网豪华单间.fla"
MAI_FLA = ROOT / "flashswf" / "unused" / "不知火舞素材.fla"
ENEMY_PROPERTIES = ROOT / "data" / "enemy_properties" / "天网.xml"
UNITS = ROOT / "data" / "units" / "units.json"
ASSET_MAP = ROOT / "data" / "items" / "asset_source_map.xml"
PETS = ROOT / "data" / "merc" / "pets.xml"
PET_BACKUP = ROOT / "data" / "units" / "宠物库原始数据备份.txt"
SAVE_REPAIR = ROOT / "launcher" / "data" / "save_repair_dict.json"
SCHEMA = "cf7.portrait-pilot-source-exclusion-closure.v1"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


atlas8 = load_module(ATLAS_V8_PATH, "cf7_portrait_feedback_atlas_v8_for_source_closure")
core = atlas8.core
ClosureError = atlas8.AtlasError


def pilot_path(value: str | Path, label: str) -> Path:
    return core.ensure_below(Path(value), PILOT_ROOT, label)


def load_json(path: Path, label: str) -> dict[str, Any]:
    value = core.load_json(path)
    if not isinstance(value, dict):
        raise ClosureError(f"{label} 顶层必须是对象")
    return value


def verify_record(record: dict[str, Any], label: str) -> Path:
    return core.verify_artifact_record(record, label)


def digest_report(report: dict[str, Any]) -> str:
    envelope = dict(report)
    envelope.pop("closureDigest", None)
    return core.sha256_bytes(core.stable_bytes(envelope))


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def fla_evidence() -> dict[str, Any]:
    # This CS6 FLA has a legacy ZIP central directory that .NET accepts but
    # Python's strict zipfile rejects. Use the read-only Windows parser that is
    # also available to Flash authoring tooling, and bind its deterministic JSON.
    powershell = r'''
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $env:CF7_PORTRAIT_SERPENT_FLA))
try {
  $linkages = @()
  $serpentEntries = @()
  $componentUsers = @()
  $armsNamedMan = 0
  foreach ($entry in $archive.Entries) {
    if ($entry.FullName -like 'LIBRARY/Serpent/*.xml') { $serpentEntries += $entry.FullName }
    if (-not $entry.FullName.EndsWith('.xml')) { continue }
    $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
    try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
    foreach ($match in [regex]::Matches($content, 'linkageIdentifier="([^"]+)"')) {
      $linkages += $match.Groups[1].Value
    }
    $refs = @([regex]::Matches($content, 'libraryItemName="(Serpent/[^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($refs.Count -gt 0) {
      $componentUsers += [pscustomobject]@{ entry = $entry.FullName; references = $refs }
    }
    if ($entry.FullName -eq 'LIBRARY/敌人-ArmsArius.xml') {
      $armsNamedMan = [regex]::Matches($content, 'name="man"').Count
    }
  }
  [pscustomobject]@{
    linkageIdentifiers = @($linkages | Sort-Object -Unique)
    serpentLibraryEntries = @($serpentEntries | Sort-Object)
    componentUsers = @($componentUsers | Sort-Object entry)
    armsNamedManInstanceCount = $armsNamedMan
  } | ConvertTo-Json -Depth 12 -Compress
} finally {
  $archive.Dispose()
}
'''
    process_env = os.environ.copy()
    process_env["CF7_PORTRAIT_SERPENT_FLA"] = str(SERPENT_FLA)
    completed = subprocess.run(
        ["powershell", "-NoProfile", "-Command", powershell],
        cwd=ROOT,
        env=process_env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
        check=False,
    )
    if completed.returncode != 0:
        raise ClosureError(f"Windows FLA parser 失败：{completed.stderr.strip() or completed.stdout.strip()}")
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise ClosureError(f"Windows FLA parser 输出非法：{error}") from error
    linkage_names = parsed["linkageIdentifiers"]
    serpent_library_entries = parsed["serpentLibraryEntries"]
    serpent_component_users = parsed["componentUsers"]
    arms_named_man_count = parsed["armsNamedManInstanceCount"]
    if (
        SERPENT_REF in linkage_names
        or "敌人-ArmsArius" not in linkage_names
        or len(serpent_library_entries) != 9
        or arms_named_man_count != 9
    ):
        raise ClosureError(
            "Serpent FLA linkage/component closure 漂移："
            f"linkages={linkage_names} entries={len(serpent_library_entries)} man={arms_named_man_count}"
        )
    return {
        "archive": core.artifact(SERPENT_FLA),
        "linkageIdentifiers": linkage_names,
        "serpentRootLinkagePresent": False,
        "armsAriusRootLinkagePresent": True,
        "internalSerpentLibraryEntryCount": len(serpent_library_entries),
        "internalSerpentLibraryEntries": serpent_library_entries,
        "internalSerpentComponentUsers": serpent_component_users,
        "armsAriusNamedManInstanceCount": arms_named_man_count,
        "interpretation": "Serpent is an internal body-part namespace consumed by ArmsArius assets, not an exported enemy root.",
    }


def exact_runtime_references(needle: str) -> list[dict[str, Any]]:
    suffixes = {".xml", ".json", ".txt", ".as"}
    records: list[dict[str, Any]] = []
    for root in (ROOT / "data", ROOT / "launcher"):
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in suffixes:
                continue
            content = text(path)
            count = content.count(needle)
            if count:
                records.append({"artifact": core.artifact(path), "occurrences": count})
    return records


def export_evidence(output: Path) -> dict[str, Any]:
    ffdec = core.verify_ffdec()
    xml_dir = output / "ffdec-xml"
    xml_dir.mkdir(parents=True)
    xml_path = xml_dir / "serpent-source.xml"
    run = core.run_ffdec(
        ["-onerror", "abort", "-swf2xml", str(SERPENT_SWF), str(xml_path)],
        output,
        "serpent-source-swf2xml",
    )
    exports = core.export_assets_from_xml(xml_path)
    names = sorted(exports)
    if SERPENT_REF in exports or "敌人-ArmsArius" not in exports:
        raise ClosureError("Serpent compiled SWF export closure 漂移")
    return {
        "sourceSwf": core.artifact(SERPENT_SWF),
        "ffdecXml": core.artifact(xml_path),
        "ffdec": ffdec,
        "ffdecRun": run,
        "exportedIdentifiers": names,
        "exportedIdentifierCount": len(names),
        "serpentRootExportPresent": False,
        "armsAriusRootExportPresent": True,
    }


def serpent_entry(export: dict[str, Any], fla: dict[str, Any]) -> dict[str, Any]:
    units_occurrences = text(UNITS).count(SERPENT_REF)
    asset_map_occurrences = text(ASSET_MAP).count(SERPENT_REF)
    enemy_occurrences = text(ENEMY_PROPERTIES).count(SERPENT_REF)
    repair_occurrences = text(SAVE_REPAIR).count(SERPENT_REF)
    references = exact_runtime_references(SERPENT_REF)
    paths = {row["artifact"]["path"] for row in references}
    expected_paths = {core.repo_rel(ENEMY_PROPERTIES), core.repo_rel(SAVE_REPAIR)}
    if (
        units_occurrences != 0
        or asset_map_occurrences != 0
        or enemy_occurrences != 2
        or repair_occurrences != 1
        or paths != expected_paths
        or export["serpentRootExportPresent"] is not False
        or fla["serpentRootLinkagePresent"] is not False
    ):
        raise ClosureError("Serpent runtime consumer/source evidence 漂移")
    return {
        "portraitRef": SERPENT_REF,
        "inventoryResolution": "missing",
        "classification": "dormant_enemy_property_without_runtime_unit_or_exported_root",
        "decision": "exclude_from_portrait_campaign_until_runtime_implementation",
        "evidence": {
            "enemyProperty": core.artifact(ENEMY_PROPERTIES),
            "enemyPropertyTagOccurrences": enemy_occurrences,
            "units": core.artifact(UNITS),
            "unitSpriteNameOccurrences": units_occurrences,
            "assetSourceMap": core.artifact(ASSET_MAP),
            "assetMapOccurrences": asset_map_occurrences,
            "saveRepairDictionary": core.artifact(SAVE_REPAIR),
            "saveRepairAllowlistOccurrences": repair_occurrences,
            "allDataAndLauncherTextReferences": references,
            "fla": fla,
            "compiledSwf": export,
        },
        "gates": {
            "enemyPropertyDefinitionPresent": True,
            "runtimeUnitConsumerAbsent": True,
            "runtimeAssetMapEntryAbsent": True,
            "exportedEnemyRootAbsent": True,
            "internalPartsNotPromotedAsRoot": True,
            "armsAriusPortraitNotAliased": True,
            "humanArtAcceptanceRequiredIfImplementedLater": True,
            "productionWrites": False,
        },
    }


def mai_entry() -> dict[str, Any]:
    pets_text = text(PETS)
    backup_text = text(PET_BACKUP)
    if (
        '<Pet>        <!-- 不考虑实装-->' not in pets_text
        or f"<Identifier>{MAI_REF}</Identifier>" not in pets_text
        or MAI_REF not in backup_text
        or not MAI_FLA.is_file()
    ):
        raise ClosureError("不知火舞未实装证据漂移")
    runtime_files = [
        path
        for path in (ROOT / "flashswf").rglob("*")
        if path.is_file() and "不知火舞" in path.name and "unused" not in {part.lower() for part in path.parts}
    ]
    if runtime_files:
        raise ClosureError(f"不知火舞出现 runtime 素材：{runtime_files}")
    return {
        "portraitRef": MAI_REF,
        "inventoryResolution": "missing",
        "classification": "explicitly_not_considered_for_implementation_and_unused_fla_only",
        "decision": "exclude_from_portrait_campaign_until_runtime_implementation",
        "evidence": {
            "petsConfig": core.artifact(PETS),
            "notConsideredForImplementationComment": "不考虑实装",
            "legacyPetBackup": core.artifact(PET_BACKUP),
            "unusedFla": core.artifact(MAI_FLA),
            "runtimeNamedAssetCount": 0,
        },
        "gates": {
            "explicitNonImplementationCommentPresent": True,
            "onlyUnusedFlaPresent": True,
            "runtimeCompiledSourceAbsent": True,
            "humanArtAcceptanceRequiredIfImplementedLater": True,
            "productionWrites": False,
        },
    }


def build(args: argparse.Namespace) -> None:
    inventory_path = pilot_path(args.inventory, "source closure inventory")
    manifest_path = pilot_path(args.manifest, "source closure manifest")
    representative_path = pilot_path(args.representative_closure, "representative closure")
    review_batch = pilot_path(args.latest_review_batch, "latest review batch")
    output = pilot_path(args.output, "source closure output")
    if output.exists():
        raise ClosureError(f"输出已存在，禁止覆盖：{output}")
    output.mkdir(parents=True)
    inventory = load_json(inventory_path, "source closure inventory")
    atlas8.verify_v8(manifest_path)
    manifest = load_json(manifest_path, "source closure manifest")
    representative = load_json(representative_path, "representative closure")
    latest_receipt_path = review_batch / "human-review-receipt.json"
    latest_receipt = load_json(latest_receipt_path, "latest human review receipt")
    missing = sorted(item["portraitRef"] for item in inventory["items"] if item["sourceResolution"] == "missing")
    if missing != sorted([SERPENT_REF, MAI_REF]) or inventory["counts"]["missingSourceIdentityCount"] != 2:
        raise ClosureError(f"inventory missing source 集合漂移：{missing}")
    serpent_blockers = [row for row in representative.get("blockers", []) if row.get("portraitRef") == SERPENT_REF]
    if len(serpent_blockers) != 1 or serpent_blockers[0].get("blockReason") != "source_missing":
        raise ClosureError("representative Serpent source blocker 未闭合")
    if latest_receipt.get("status") != "human_reviewed_approved" or latest_receipt.get("counts", {}).get("eligiblePassed") != 5:
        raise ClosureError("latest five XFL-rescue rows 未 5/5 approved")
    export = export_evidence(output)
    fla = fla_evidence()
    entries = [serpent_entry(export, fla), mai_entry()]
    prior = set(manifest["campaign"]["excludedPriorRefs"])
    representative_refs = set(manifest["campaign"]["excludedRepresentativeRefs"])
    selected = set(manifest["campaign"]["selectedPortraitRefs"])
    routed = prior | representative_refs | selected | {MAI_REF}
    inventory_refs = {item["portraitRef"] for item in inventory["items"]}
    if routed != inventory_refs or SERPENT_REF not in representative_refs:
        raise ClosureError("campaign inventory route closure 漂移")
    report: dict[str, Any] = {
        "schema": SCHEMA,
        "status": "all_actionable_portrait_sources_closed",
        "productionReady": False,
        "generatedAt": atlas8.atlas7.rescue.base.utc_now(),
        "batchId": args.batch_id,
        "inputs": {
            "controllerSource": core.artifact(CONTROLLER_PATH),
            "inventory": core.artifact(inventory_path),
            "inventoryDigest": inventory["inventoryDigest"],
            "latestPreferenceManifest": core.artifact(manifest_path),
            "manifestDigest": manifest["manifestDigest"],
            "representativeClosure": core.artifact(representative_path),
            "representativeClosureDigest": representative["reportDigest"],
            "latestFivePassReceipt": core.artifact(latest_receipt_path),
            "latestFivePassReceiptDigest": latest_receipt["receiptDigest"],
        },
        "counts": {
            "consumerIdentityCount": inventory["counts"]["consumerIdentityCount"],
            "sourceResolvedIdentityCount": inventory["counts"]["effectiveResolvedIdentityCount"],
            "verifiedNonRuntimeExclusionCount": 2,
            "actionableMissingSourceCount": 0,
            "routedIdentityCount": len(routed),
        },
        "entries": entries,
        "routing": {
            "priorProcessedCount": len(prior),
            "representativeCount": len(representative_refs),
            "latestRescuedCount": len(selected),
            "explicitUnusedOnlyCount": 1,
            "allInventoryIdentitiesRouted": True,
        },
        "gates": {
            "exactTwoMissingRefsReconciled": True,
            "allSourceResolvedIdentitiesProcessed": True,
            "serpentNotAliasedToArmsArius": True,
            "unusedMaiNotPromoted": True,
            "futureImplementationRequiresFreshSourceAndHumanReview": True,
            "noAutomaticArtAcceptance": True,
            "productionWrites": False,
        },
    }
    report["closureDigest"] = digest_report(report)
    core.write_json(output / "source-exclusion-closure.json", report)
    print(json.dumps(verify(output / "source-exclusion-closure.json"), ensure_ascii=False))


def verify(report_path: Path) -> dict[str, Any]:
    report = load_json(report_path, "source exclusion closure")
    if digest_report(report) != report.get("closureDigest"):
        raise ClosureError("source exclusion closureDigest 不匹配")
    inventory_path = verify_record(report.get("inputs", {}).get("inventory"), "source closure inventory")
    manifest_path = verify_record(report.get("inputs", {}).get("latestPreferenceManifest"), "source closure manifest")
    representative_path = verify_record(report.get("inputs", {}).get("representativeClosure"), "source closure representative")
    receipt_path = verify_record(report.get("inputs", {}).get("latestFivePassReceipt"), "source closure latest receipt")
    verify_record(report.get("inputs", {}).get("controllerSource"), "source closure controller")
    inventory = load_json(inventory_path, "source closure inventory")
    atlas8.verify_v8(manifest_path)
    representative = load_json(representative_path, "source closure representative")
    receipt = load_json(receipt_path, "source closure latest receipt")
    entries = {entry.get("portraitRef"): entry for entry in report.get("entries", [])}
    if set(entries) != {SERPENT_REF, MAI_REF}:
        raise ClosureError("source exclusion entry 集合漂移")
    serpent = entries[SERPENT_REF]
    mai = entries[MAI_REF]
    verify_record(serpent["evidence"]["fla"]["archive"], "Serpent FLA")
    verify_record(serpent["evidence"]["compiledSwf"]["sourceSwf"], "Serpent SWF")
    verify_record(serpent["evidence"]["compiledSwf"]["ffdecXml"], "Serpent FFDec XML")
    verify_record(mai["evidence"]["unusedFla"], "Mai unused FLA")
    if (
        report.get("schema") != SCHEMA
        or report.get("status") != "all_actionable_portrait_sources_closed"
        or report.get("productionReady") is not False
        or report["inputs"].get("inventoryDigest") != inventory["inventoryDigest"]
        or report["inputs"].get("representativeClosureDigest") != representative["reportDigest"]
        or report["inputs"].get("latestFivePassReceiptDigest") != receipt["receiptDigest"]
        or report.get("counts", {}).get("consumerIdentityCount") != 221
        or report.get("counts", {}).get("sourceResolvedIdentityCount") != 219
        or report.get("counts", {}).get("verifiedNonRuntimeExclusionCount") != 2
        or report.get("counts", {}).get("actionableMissingSourceCount") != 0
        or report.get("counts", {}).get("routedIdentityCount") != 221
        or serpent.get("classification") != "dormant_enemy_property_without_runtime_unit_or_exported_root"
        or serpent.get("evidence", {}).get("compiledSwf", {}).get("serpentRootExportPresent") is not False
        or serpent.get("evidence", {}).get("fla", {}).get("serpentRootLinkagePresent") is not False
        or mai.get("classification") != "explicitly_not_considered_for_implementation_and_unused_fla_only"
        or mai.get("evidence", {}).get("runtimeNamedAssetCount") != 0
        or report.get("routing", {}).get("allInventoryIdentitiesRouted") is not True
        or report.get("gates", {}).get("serpentNotAliasedToArmsArius") is not True
        or report.get("gates", {}).get("productionWrites") is not False
    ):
        raise ClosureError("source exclusion closure gate 非法")
    return {
        "status": "campaign_source_exclusion_closure_verified",
        "closureDigest": report["closureDigest"],
        "consumerIdentities": 221,
        "sourceResolvedIdentities": 219,
        "verifiedNonRuntimeExclusions": 2,
        "actionableMissingSources": 0,
        "productionReady": False,
    }


def check(args: argparse.Namespace) -> None:
    print(json.dumps(verify(pilot_path(args.report, "source exclusion closure")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--inventory", required=True)
    build_parser.add_argument("--manifest", required=True)
    build_parser.add_argument("--representative-closure", required=True)
    build_parser.add_argument("--latest-review-batch", required=True)
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
    except (ClosureError, core.PilotError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        print(f"portrait campaign source exclusion closure error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
