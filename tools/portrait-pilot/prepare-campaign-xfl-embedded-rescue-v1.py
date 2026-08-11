#!/usr/bin/env python3
"""Rescue unlinked things5 enemies through an exact XFL-to-SWF placement closure."""

from __future__ import annotations

import argparse
import contextlib
import copy
import importlib.util
import io
import json
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


CONTROLLER_PATH = Path(__file__).resolve()
BASE_CONTROLLER_PATH = CONTROLLER_PATH.with_name("prepare_campaign.py")
ROOT = CONTROLLER_PATH.parents[2]
PILOT_ROOT = ROOT / "tmp" / "portrait-pilot"
THINGS5_SWF = ROOT / "flashswf" / "arts" / "things5.swf"
THINGS5_XFL = ROOT / "flashswf" / "arts" / "things5"
LOADER_XFL = THINGS5_XFL / "LIBRARY" / "加载mc库-黑铁会.xml"
UNUSED_MAI_FLA = ROOT / "flashswf" / "unused" / "不知火舞素材.fla"
TARGET_REFS = (
    "敌人-暴走兽化改造僵尸",
    "敌人-暴走尸母",
    "敌人-暴走改造僵尸",
    "敌人-暴走爆炸僵尸",
    "敌人-暴走重型改造僵尸",
)
UNIMPLEMENTED_REF = "敌人-不知火舞"
INVENTORY_POLICY_SCHEMA = "cf7.portrait-pilot-xfl-embedded-inventory-rescue.v1"
SHARD_POLICY_SCHEMA = "cf7.portrait-pilot-xfl-embedded-source-closure.v1"
RECEIPT_SCHEMA = "cf7.portrait-pilot-xfl-embedded-source-receipt.v1"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 controller：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = load_module(BASE_CONTROLLER_PATH, "cf7_portrait_campaign_base_for_xfl_rescue")
core = base.core
ORIGINAL_VERIFY_INVENTORY = base.verify_inventory
ORIGINAL_LOAD_EXCLUSIONS = base.load_exclusions
ORIGINAL_RESOLVE_BUCKET = base.resolve_bucket
LAST_MAPPING: list[dict[str, Any]] = []
LAST_XML_PATH: Path | None = None


def repo_path(value: str | Path, root: Path, label: str) -> Path:
    return core.ensure_below(Path(value), root, label)


def read_json(path: Path, label: str) -> dict[str, Any]:
    value = core.load_json(path)
    if not isinstance(value, dict):
        raise core.PilotError(f"{label} 顶层必须是对象")
    return value


def add_artifact(records: list[dict[str, Any]], path: Path) -> None:
    record = core.artifact(path)
    if record["path"] not in {entry.get("path") for entry in records if isinstance(entry, dict)}:
        records.append(record)


def target_xfl(ref: str) -> Path:
    path = THINGS5_XFL / "LIBRARY" / f"{ref}.xml"
    if not path.is_file():
        raise core.PilotError(f"XFL 库元件缺失：{ref}")
    return path


def counts_for(items: list[dict[str, Any]], parent_counts: dict[str, Any]) -> dict[str, Any]:
    resolutions = Counter(item["sourceResolution"] for item in items)
    classifications = Counter(item["sourceClassification"] for item in items)
    return {
        **{
            key: value
            for key, value in parent_counts.items()
            if key in ("enemyIdentityCount", "petIdentityCount", "petOnlyIdentityCount")
        },
        "consumerIdentityCount": len(items),
        "reviewUnitCount": sum(len(item["variantKeys"]) for item in items),
        "uniqueSourceIdentityCount": resolutions["unique"],
        "humanSelectedSourceIdentityCount": resolutions["human_selected"],
        "manualMaintenanceIdentityCount": resolutions["manual_maintenance"],
        "sourceChoiceRequiredIdentityCount": resolutions["source_choice_required"],
        "missingSourceIdentityCount": resolutions["missing"],
        "effectiveResolvedIdentityCount": resolutions["unique"] + resolutions["human_selected"],
        "duplicateIdentityCount": classifications["duplicate"],
        "conflictIdentityCount": classifications["conflict"],
    }


def tail_missing_refs(tail: dict[str, Any]) -> list[str]:
    return list(
        tail.get("campaign", {})
        .get("sparseSourceAvailabilityPolicy", {})
        .get("availabilityClamp", {})
        .get("missingSourcePortraitRefs", [])
    )


def build_rescue_inventory(
    parent: dict[str, Any],
    parent_path: Path,
    tail: dict[str, Any],
    tail_path: Path,
    batch_id: str,
) -> dict[str, Any]:
    if sorted(tail_missing_refs(tail)) != sorted((*TARGET_REFS, UNIMPLEMENTED_REF)):
        raise core.PilotError("父尾批的 6 条 missing-source truth 已漂移")
    inventory = copy.deepcopy(parent)
    inventory["batchId"] = batch_id
    inventory["createdAt"] = base.utc_now()
    by_ref = {item["portraitRef"]: item for item in inventory["items"]}
    for ref in TARGET_REFS:
        item = by_ref.get(ref)
        if item is None or item.get("sourceResolution") != "missing" or item.get("sources") != []:
            raise core.PilotError(f"XFL rescue 父条目不是纯 missing：{ref}")
        source = {
            "swf": core.repo_rel(THINGS5_SWF),
            "symbolName": ref,
            "orphan": False,
            "xflEmbedded": True,
        }
        item["sourceClassification"] = "unique"
        item["sourceResolution"] = "unique"
        item["sources"] = [source]
        item["selectedSource"] = source
        item["sourceChoiceReceiptDigest"] = None
    if by_ref.get(UNIMPLEMENTED_REF, {}).get("sourceResolution") != "missing":
        raise core.PilotError("不知火舞必须继续保持 missing")

    envelope = inventory["sourceEnvelope"]
    source_files = list(envelope.get("sourceFiles", []))
    for path in (
        CONTROLLER_PATH,
        BASE_CONTROLLER_PATH,
        parent_path,
        tail_path,
        THINGS5_SWF,
        LOADER_XFL,
        UNUSED_MAI_FLA,
        *(target_xfl(ref) for ref in TARGET_REFS),
    ):
        add_artifact(source_files, path)
    policy = {
        "schema": INVENTORY_POLICY_SCHEMA,
        "controllerSource": core.artifact(CONTROLLER_PATH),
        "baseControllerSource": core.artifact(BASE_CONTROLLER_PATH),
        "parentInventory": core.artifact(parent_path),
        "parentTailManifest": core.artifact(tail_path),
        "sourceSwf": core.artifact(THINGS5_SWF),
        "loaderXfl": core.artifact(LOADER_XFL),
        "targetSymbolXfl": [core.artifact(target_xfl(ref)) for ref in TARGET_REFS],
        "rescuedPortraitRefs": sorted(TARGET_REFS),
        "unimplementedPortraitRef": UNIMPLEMENTED_REF,
        "unimplementedFla": core.artifact(UNUSED_MAI_FLA),
        "unimplementedPolicy": "pets_comment_not_considered_implemented_and_only_unused_fla_present",
        "mappingDeferredToFreshFfdecXml": True,
        "rootTimelineFallbackForbidden": True,
        "productionWrites": False,
    }
    envelope["mode"] = "full_consumer_identity_inventory_xfl_embedded_rescue_v1"
    envelope["sourceFiles"] = source_files
    envelope["xflEmbeddedRescuePolicy"] = policy
    inventory["counts"] = counts_for(inventory["items"], parent["counts"])
    inventory["gates"]["missingSourcesBlocked"] = True
    inventory["gates"]["xflEmbeddedSourceRequiresFreshSwfClosure"] = True
    inventory["gates"]["unimplementedUnusedFlaExcluded"] = True
    inventory["sourceDigest"] = core.sha256_bytes(core.stable_bytes(envelope))
    inventory.pop("inventoryDigest", None)
    inventory["inventoryDigest"] = core.sha256_bytes(core.stable_bytes(inventory))
    return inventory


def verify_rescue_inventory(path: Path) -> tuple[dict[str, Any], int]:
    inventory_path = repo_path(path, PILOT_ROOT, "XFL rescue inventory")
    inventory = read_json(inventory_path, "XFL rescue inventory")
    digest_input = dict(inventory)
    digest = digest_input.pop("inventoryDigest", None)
    if core.sha256_bytes(core.stable_bytes(digest_input)) != digest:
        raise core.PilotError("XFL rescue inventoryDigest 不匹配")
    envelope = inventory.get("sourceEnvelope", {})
    if core.sha256_bytes(core.stable_bytes(envelope)) != inventory.get("sourceDigest"):
        raise core.PilotError("XFL rescue sourceDigest 不匹配")
    policy = envelope.get("xflEmbeddedRescuePolicy", {})
    parent_path = core.verify_artifact_record(policy.get("parentInventory"), "XFL rescue parent inventory")
    tail_path = core.verify_artifact_record(policy.get("parentTailManifest"), "XFL rescue parent tail")
    parent, _ = ORIGINAL_VERIFY_INVENTORY(parent_path)
    tail = core.verify_manifest(tail_path)
    if sorted(tail_missing_refs(tail)) != sorted((*TARGET_REFS, UNIMPLEMENTED_REF)):
        raise core.PilotError("XFL rescue parent tail missing refs 漂移")
    parent_by_ref = {item["portraitRef"]: item for item in parent["items"]}
    actual_by_ref = {item["portraitRef"]: item for item in inventory.get("items", [])}
    if set(parent_by_ref) != set(actual_by_ref):
        raise core.PilotError("XFL rescue inventory identity 集漂移")
    for ref, actual in actual_by_ref.items():
        if ref not in TARGET_REFS:
            if actual != parent_by_ref[ref]:
                raise core.PilotError(f"XFL rescue 修改了非目标条目：{ref}")
            continue
        expected_source = {
            "swf": core.repo_rel(THINGS5_SWF),
            "symbolName": ref,
            "orphan": False,
            "xflEmbedded": True,
        }
        if (
            actual.get("sourceClassification") != "unique"
            or actual.get("sourceResolution") != "unique"
            or actual.get("sources") != [expected_source]
            or actual.get("selectedSource") != expected_source
            or actual.get("sourceChoiceReceiptDigest") is not None
        ):
            raise core.PilotError(f"XFL rescue 目标来源不闭合：{ref}")
    if inventory.get("counts") != counts_for(inventory["items"], parent["counts"]):
        raise core.PilotError("XFL rescue inventory counts 漂移")
    if (
        policy.get("schema") != INVENTORY_POLICY_SCHEMA
        or policy.get("controllerSource") != core.artifact(CONTROLLER_PATH)
        or policy.get("baseControllerSource") != core.artifact(BASE_CONTROLLER_PATH)
        or policy.get("rescuedPortraitRefs") != sorted(TARGET_REFS)
        or policy.get("unimplementedPortraitRef") != UNIMPLEMENTED_REF
        or policy.get("mappingDeferredToFreshFfdecXml") is not True
        or policy.get("rootTimelineFallbackForbidden") is not True
        or policy.get("productionWrites") is not False
        or inventory.get("productionReady") is not False
        or inventory.get("gates", {}).get("productionWrites") is not False
    ):
        raise core.PilotError("XFL rescue inventory policy 非法")
    artifact_count = 0
    for record in envelope.get("sourceFiles", []):
        core.verify_artifact_record(record, "XFL rescue inventory source")
        artifact_count += 1
    return inventory, artifact_count


def xfl_loader_positions() -> dict[str, dict[str, int]]:
    ns = {"x": "http://ns.adobe.com/xfl/2008/"}
    tree = ET.parse(LOADER_XFL)
    found: dict[str, dict[str, int]] = {}
    for frame in tree.findall(".//x:DOMFrame", ns):
        frame_index = int(frame.get("index", "0"))
        for instance in frame.findall(".//x:DOMSymbolInstance", ns):
            ref = instance.get("libraryItemName")
            if ref not in TARGET_REFS:
                continue
            matrix = instance.find("./x:matrix/x:Matrix", ns)
            if matrix is None or ref in found:
                raise core.PilotError(f"XFL loader target placement 不唯一：{ref}")
            found[ref] = {
                "xflFrameIndex": frame_index,
                "translateX": round(float(matrix.get("tx", "0")) * 20),
                "translateY": round(float(matrix.get("ty", "0")) * 20),
            }
    if set(found) != set(TARGET_REFS):
        raise core.PilotError("XFL loader 未覆盖全部 rescue target")
    return found


def sprite_subtags(xml_path: Path, sprite_id: int) -> list[ET.Element]:
    active: ET.Element | None = None
    for event, element in ET.iterparse(xml_path, events=("start", "end")):
        if (
            event == "start"
            and element.tag == "item"
            and element.get("type") == "DefineSpriteTag"
            and element.get("spriteId") == str(sprite_id)
        ):
            active = element
        elif event == "end" and active is element:
            subtags = active.find("subTags")
            if subtags is None:
                raise core.PilotError(f"DefineSprite {sprite_id} 缺 subTags")
            return list(subtags)
        elif event == "end" and active is None:
            element.clear()
    raise core.PilotError(f"DefineSprite 缺失：{sprite_id}")


def loader_placements(xml_path: Path, loader_id: int) -> list[dict[str, int]]:
    frame = 1
    placements: list[dict[str, int]] = []
    for tag in sprite_subtags(xml_path, loader_id):
        kind = tag.get("type", "")
        if kind == "ShowFrameTag":
            frame += 1
        elif kind.startswith("PlaceObject") and tag.get("characterId"):
            matrix = tag.find("matrix")
            if matrix is not None:
                placements.append(
                    {
                        "swfFrame": frame,
                        "rootCharacterId": int(tag.get("characterId", "0")),
                        "depth": int(tag.get("depth", "0")),
                        "translateX": int(matrix.get("translateX", "0")),
                        "translateY": int(matrix.get("translateY", "0")),
                    }
                )
    return placements


def derive_mapping(xml_path: Path) -> list[dict[str, Any]]:
    exports = core.export_assets_from_xml(xml_path)
    loader_ids = exports.get("加载mc库-黑铁会", [])
    if len(loader_ids) != 1:
        raise core.PilotError(f"加载mc库-黑铁会 linkage 不唯一：{loader_ids}")
    loader_id = int(loader_ids[0])
    frame_counts = core.sprite_frame_counts(xml_path)
    positions = xfl_loader_positions()
    placements = loader_placements(xml_path, loader_id)
    mappings: list[dict[str, Any]] = []
    for ref in sorted(TARGET_REFS):
        expected = positions[ref]
        matches = [
            row
            for row in placements
            if row["translateX"] == expected["translateX"]
            and row["translateY"] == expected["translateY"]
            and row["swfFrame"] == expected["xflFrameIndex"] + 1
        ]
        if len(matches) != 1:
            raise core.PilotError(f"XFL→SWF placement 不唯一：{ref}/{matches}")
        root_id = matches[0]["rootCharacterId"]
        man_id = core.first_frame_named_instance(xml_path, root_id, "man")
        if man_id is None or root_id not in frame_counts or man_id not in frame_counts:
            raise core.PilotError(f"XFL rescue 首帧唯一 man 不闭合：{ref}/{root_id}/{man_id}")
        symbol_path = target_xfl(ref)
        symbol_tree = ET.parse(symbol_path)
        named_man_count = sum(
            1
            for instance in symbol_tree.findall(".//{http://ns.adobe.com/xfl/2008/}DOMSymbolInstance")
            if instance.get("name") == "man"
        )
        if named_man_count < 1:
            raise core.PilotError(f"XFL symbol 没有命名 man：{ref}")
        mappings.append(
            {
                "portraitRef": ref,
                "xflSymbol": core.artifact(symbol_path),
                "xflFrameIndex": expected["xflFrameIndex"],
                "swfFrame": matches[0]["swfFrame"],
                "depth": matches[0]["depth"],
                "translateXTwips": expected["translateX"],
                "translateYTwips": expected["translateY"],
                "rootCharacterId": root_id,
                "rootDeclaredFrameCount": int(frame_counts[root_id]),
                "renderCharacterId": int(man_id),
                "renderDeclaredFrameCount": int(frame_counts[man_id]),
                "xflNamedManInstanceCount": named_man_count,
            }
        )
    return mappings


def resolve_rescue_bucket(
    output_dir: Path,
    bucket_index: int,
    swf_rel: str,
    rows: list[dict[str, Any]],
) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    global LAST_MAPPING, LAST_XML_PATH
    if swf_rel != core.repo_rel(THINGS5_SWF) or {row["portraitRef"] for row in rows} != set(TARGET_REFS):
        return ORIGINAL_RESOLVE_BUCKET(output_dir, bucket_index, swf_rel, rows)
    xml_path = output_dir / "ffdec-xml" / f"source-{bucket_index:03d}.xml"
    xml_path.parent.mkdir(parents=True, exist_ok=True)
    run = core.run_ffdec(
        ["-onerror", "abort", "-swf2xml", str(THINGS5_SWF), str(xml_path)],
        output_dir,
        f"source-{bucket_index:03d}-xml",
    )
    mapping = derive_mapping(xml_path)
    by_ref = {entry["portraitRef"]: entry for entry in mapping}
    resolved = []
    for row in rows:
        entry = by_ref[row["portraitRef"]]
        resolved.append(
            {
                **row,
                "rootCharacterId": entry["rootCharacterId"],
                "rootDeclaredFrameCount": entry["rootDeclaredFrameCount"],
                "renderCharacterId": entry["renderCharacterId"],
                "renderDeclaredFrameCount": entry["renderDeclaredFrameCount"],
                "renderStrategy": "first_frame_named_man_instance",
                "renderStrategyWarning": None,
                "sourceSwf": swf_rel,
                "ffdecXmlPath": xml_path,
            }
        )
    LAST_MAPPING = mapping
    LAST_XML_PATH = xml_path
    return run, resolved, []


def transitive_exclusions(paths: list[str]) -> tuple[set[str], list[dict[str, Any]]]:
    excluded, records = ORIGINAL_LOAD_EXCLUSIONS(paths)
    for value in paths:
        manifest = core.verify_manifest(repo_path(value, PILOT_ROOT, "XFL rescue exclusion manifest"))
        excluded.update(manifest.get("campaign", {}).get("excludedPriorRefs", []))
    return excluded, records


@contextmanager
def patched_base() -> Iterator[None]:
    original_verify = base.verify_inventory
    original_load = base.load_exclusions
    original_resolve = base.resolve_bucket
    try:
        base.verify_inventory = verify_rescue_inventory
        base.load_exclusions = transitive_exclusions
        base.resolve_bucket = resolve_rescue_bucket
        yield
    finally:
        base.verify_inventory = original_verify
        base.load_exclusions = original_load
        base.resolve_bucket = original_resolve


def receipt_for(manifest: dict[str, Any], batch_id: str) -> dict[str, Any]:
    if LAST_XML_PATH is None or len(LAST_MAPPING) != len(TARGET_REFS):
        raise core.PilotError("XFL rescue mapping evidence 未闭合")
    receipt = {
        "schema": RECEIPT_SCHEMA,
        "status": "xfl_embedded_named_man_sources_verified",
        "productionReady": False,
        "batchId": batch_id,
        "generatedAt": base.utc_now(),
        "sourceSwf": core.artifact(THINGS5_SWF),
        "ffdecXml": core.artifact(LAST_XML_PATH),
        "loaderXfl": core.artifact(LOADER_XFL),
        "loaderExportName": "加载mc库-黑铁会",
        "mappingMethod": "xfl_frame_and_exact_twip_translation_to_swf_placeobject_then_first_frame_unique_named_man",
        "mappings": LAST_MAPPING,
        "gates": {
            "allFiveTargetsMapped": True,
            "exactXflSwfPlacementMatched": True,
            "firstFrameUniqueNamedManRequired": True,
            "outerMonsterRootNotRendered": True,
            "linkageRootFallbackForbidden": True,
            "humanArtAcceptance": False,
            "productionWrites": False,
        },
    }
    receipt["receiptDigest"] = core.sha256_bytes(core.stable_bytes(receipt))
    return receipt


def rebind_manifest(manifest_path: Path, receipt_path: Path, parent_tail_path: Path) -> None:
    manifest = core.verify_manifest(manifest_path)
    receipt = read_json(receipt_path, "XFL rescue receipt")
    policy = {
        "schema": SHARD_POLICY_SCHEMA,
        "controllerSource": core.artifact(CONTROLLER_PATH),
        "baseControllerSource": core.artifact(BASE_CONTROLLER_PATH),
        "parentTailManifest": core.artifact(parent_tail_path),
        "sourceReceipt": core.artifact(receipt_path),
        "sourceReceiptDigest": receipt["receiptDigest"],
        "rescuedPortraitRefs": sorted(TARGET_REFS),
        "unimplementedPortraitRef": UNIMPLEMENTED_REF,
        "selectionMaximumConcurrency": 6,
        "localizationMaximumConcurrency": 3,
        "serviceTier": "fast",
        "timeoutSeconds": 600,
        "outerMonsterRootNotRendered": True,
        "rootTimelineFallbackForbidden": True,
        "productionWrites": False,
    }
    source_files = list(manifest["sourceEnvelope"].get("sourceFiles", []))
    for path in (CONTROLLER_PATH, BASE_CONTROLLER_PATH, parent_tail_path, receipt_path, LOADER_XFL, *[target_xfl(ref) for ref in TARGET_REFS]):
        add_artifact(source_files, path)
    manifest["sourceEnvelope"]["sourceFiles"] = source_files
    manifest["sourceEnvelope"]["xflEmbeddedSourcePolicy"] = policy
    manifest["campaign"]["xflEmbeddedSourcePolicy"] = policy
    manifest["campaign"]["selectionStrategy"] = "xfl_exact_frame_twip_mapping_then_first_frame_unique_named_man"
    manifest["campaign"]["serviceTierRecommendation"] = "fast"
    manifest["campaign"]["maxConcurrencyRecommendation"] = 6
    manifest["campaign"]["localizationConcurrencyRecommendation"] = 3
    manifest["sourceDigest"] = core.sha256_bytes(core.stable_bytes(manifest["sourceEnvelope"]))
    manifest.pop("manifestDigest", None)
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    core.write_json(manifest_path, manifest)


def verify_receipt(receipt_path: Path) -> dict[str, Any]:
    receipt = read_json(receipt_path, "XFL rescue receipt")
    envelope = dict(receipt)
    digest = envelope.pop("receiptDigest", None)
    if core.sha256_bytes(core.stable_bytes(envelope)) != digest:
        raise core.PilotError("XFL rescue receiptDigest 不匹配")
    xml_path = core.verify_artifact_record(receipt.get("ffdecXml"), "XFL rescue receipt FFDec XML")
    expected = derive_mapping(xml_path)
    if receipt.get("mappings") != expected:
        raise core.PilotError("XFL rescue receipt mapping 与当前 XFL/SWF 漂移")
    if (
        receipt.get("schema") != RECEIPT_SCHEMA
        or receipt.get("status") != "xfl_embedded_named_man_sources_verified"
        or receipt.get("productionReady") is not False
        or receipt.get("gates", {}).get("outerMonsterRootNotRendered") is not True
        or receipt.get("gates", {}).get("linkageRootFallbackForbidden") is not True
        or receipt.get("gates", {}).get("productionWrites") is not False
    ):
        raise core.PilotError("XFL rescue receipt gate 非法")
    return receipt


def verify_shard(manifest_path: Path) -> dict[str, Any]:
    with patched_base(), contextlib.redirect_stdout(io.StringIO()):
        manifest, artifact_count = base.verify_shard(manifest_path)
    envelope_policy = manifest.get("sourceEnvelope", {}).get("xflEmbeddedSourcePolicy")
    campaign_policy = manifest.get("campaign", {}).get("xflEmbeddedSourcePolicy")
    if not isinstance(envelope_policy, dict) or envelope_policy != campaign_policy:
        raise core.PilotError("XFL rescue shard policy 顶层与 source envelope 漂移")
    receipt_path = core.verify_artifact_record(envelope_policy.get("sourceReceipt"), "XFL rescue source receipt")
    receipt = verify_receipt(receipt_path)
    refs = sorted(item["portraitRef"] for item in manifest["reviewItems"])
    entity_map = {entity["portraitRef"]: entity for entity in manifest["entities"]}
    receipt_map = {entry["portraitRef"]: entry for entry in receipt["mappings"]}
    if refs != sorted(TARGET_REFS):
        raise core.PilotError(f"XFL rescue shard 身份不闭合：{refs}")
    for ref in TARGET_REFS:
        entity = entity_map[ref]
        mapping = receipt_map[ref]
        if (
            entity["characterId"] != mapping["rootCharacterId"]
            or entity["renderCharacterId"] != mapping["renderCharacterId"]
            or entity["renderStrategy"] != "first_frame_named_man_instance"
        ):
            raise core.PilotError(f"XFL rescue entity/man 漂移：{ref}")
    if (
        envelope_policy.get("schema") != SHARD_POLICY_SCHEMA
        or envelope_policy.get("controllerSource") != core.artifact(CONTROLLER_PATH)
        or envelope_policy.get("baseControllerSource") != core.artifact(BASE_CONTROLLER_PATH)
        or envelope_policy.get("sourceReceiptDigest") != receipt["receiptDigest"]
        or envelope_policy.get("rescuedPortraitRefs") != sorted(TARGET_REFS)
        or envelope_policy.get("unimplementedPortraitRef") != UNIMPLEMENTED_REF
        or envelope_policy.get("selectionMaximumConcurrency") != 6
        or envelope_policy.get("localizationMaximumConcurrency") != 3
        or envelope_policy.get("outerMonsterRootNotRendered") is not True
        or envelope_policy.get("rootTimelineFallbackForbidden") is not True
        or envelope_policy.get("productionWrites") is not False
    ):
        raise core.PilotError("XFL rescue shard policy 非法")
    return {
        "status": "campaign_xfl_embedded_rescue_shard_verified",
        "manifestDigest": manifest["manifestDigest"],
        "sourceDigest": manifest["sourceDigest"],
        "identities": len(refs),
        "modelBatches": len(manifest["modelBatches"]),
        "selectionMaximumConcurrency": 6,
        "localizationMaximumConcurrency": 3,
        "receiptDigest": receipt["receiptDigest"],
        "artifactCount": artifact_count + 1,
        "productionReady": False,
    }


def build_inventory_command(args: argparse.Namespace) -> None:
    output = repo_path(args.output, PILOT_ROOT, "XFL rescue inventory output")
    if output.exists():
        raise core.PilotError(f"输出已存在，禁止覆盖：{output}")
    parent_path = repo_path(args.parent_inventory, PILOT_ROOT, "parent inventory")
    tail_path = repo_path(args.parent_tail_manifest, PILOT_ROOT, "parent tail manifest")
    parent, _ = ORIGINAL_VERIFY_INVENTORY(parent_path)
    tail = core.verify_manifest(tail_path)
    inventory = build_rescue_inventory(parent, parent_path, tail, tail_path, base.validate_batch_id(args.batch_id))
    output.mkdir(parents=True)
    inventory_path = output / "portrait-inventory.json"
    core.write_json(inventory_path, inventory)
    checked, artifact_count = verify_rescue_inventory(inventory_path)
    print(json.dumps({
        "status": "campaign_xfl_embedded_rescue_inventory_frozen",
        "path": core.repo_rel(inventory_path),
        "inventoryDigest": checked["inventoryDigest"],
        "rescuedIdentities": len(TARGET_REFS),
        "remainingMissingSources": checked["counts"]["missingSourceIdentityCount"],
        "artifactCount": artifact_count,
        "productionReady": False,
    }, ensure_ascii=False))


def prepare_shard_command(args: argparse.Namespace) -> None:
    inventory_path = repo_path(args.inventory, PILOT_ROOT, "XFL rescue inventory")
    verify_rescue_inventory(inventory_path)
    tail_path = repo_path(args.parent_tail_manifest, PILOT_ROOT, "XFL rescue parent tail")
    output = repo_path(args.output, PILOT_ROOT, "XFL rescue shard output")
    namespace = argparse.Namespace(
        inventory=str(inventory_path),
        output=str(output),
        batch_id=base.validate_batch_id(args.batch_id),
        representative_closure=args.representative_closure,
        profile=args.profile,
        shard_size=5,
        source_groups=1,
        exclude_manifest=[str(tail_path)],
    )
    global LAST_MAPPING, LAST_XML_PATH
    LAST_MAPPING = []
    LAST_XML_PATH = None
    with patched_base(), contextlib.redirect_stdout(io.StringIO()):
        base.prepare_shard(namespace)
    manifest_path = output / "candidate-manifest.json"
    manifest = core.verify_manifest(manifest_path)
    receipt = receipt_for(manifest, args.batch_id)
    receipt_path = output / "xfl-embedded-source-receipt.json"
    core.write_json(receipt_path, receipt)
    rebind_manifest(manifest_path, receipt_path, tail_path)
    print(json.dumps(verify_shard(manifest_path), ensure_ascii=False))


def check_inventory_command(args: argparse.Namespace) -> None:
    inventory, artifact_count = verify_rescue_inventory(repo_path(args.inventory, PILOT_ROOT, "XFL rescue inventory"))
    print(json.dumps({
        "status": "campaign_xfl_embedded_rescue_inventory_verified",
        "inventoryDigest": inventory["inventoryDigest"],
        "rescuedIdentities": len(TARGET_REFS),
        "artifactCount": artifact_count,
        "productionReady": False,
    }, ensure_ascii=False))


def check_shard_command(args: argparse.Namespace) -> None:
    print(json.dumps(verify_shard(repo_path(args.manifest, PILOT_ROOT, "XFL rescue shard manifest")), ensure_ascii=False))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build-inventory")
    build.add_argument("--parent-inventory", required=True)
    build.add_argument("--parent-tail-manifest", required=True)
    build.add_argument("--output", required=True)
    build.add_argument("--batch-id", required=True)
    build.set_defaults(handler=build_inventory_command)
    check_inventory = commands.add_parser("check-inventory")
    check_inventory.add_argument("--inventory", required=True)
    check_inventory.set_defaults(handler=check_inventory_command)
    prepare = commands.add_parser("prepare-shard")
    prepare.add_argument("--inventory", required=True)
    prepare.add_argument("--parent-tail-manifest", required=True)
    prepare.add_argument("--output", required=True)
    prepare.add_argument("--batch-id", required=True)
    prepare.add_argument("--representative-closure", required=True)
    prepare.add_argument("--profile")
    prepare.set_defaults(handler=prepare_shard_command)
    check_shard = commands.add_parser("check-shard")
    check_shard.add_argument("--manifest", required=True)
    check_shard.set_defaults(handler=check_shard_command)
    return root


def main() -> int:
    try:
        args = parser().parse_args()
        args.handler(args)
        return 0
    except (core.PilotError, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, ET.ParseError) as error:
        print(f"portrait XFL embedded rescue error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
