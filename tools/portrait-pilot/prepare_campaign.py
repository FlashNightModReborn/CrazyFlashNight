#!/usr/bin/env python3
"""Freeze the full portrait inventory and prepare bounded, reviewable campaign shards."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import datetime as dt
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageSequence, __version__ as PILLOW_VERSION

import prepare_pilot as core
import prepare_source_choices as source_choices


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
PROFILE_PATH = ROOT / "tools" / "portrait-pilot" / "fixtures" / "campaign-feature-inference.v1.json"
REPRESENTATIVE_FIXTURE_PATH = ROOT / "tools" / "portrait-pilot" / "fixtures" / "representative-entities.v1.json"
INVENTORY_SCHEMA = "cf7.enemy-portrait-campaign-inventory.v1"
CAMPAIGN_MODE = "bounded_full_campaign_shard"


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def validate_batch_id(value: str | None) -> str:
    if not isinstance(value, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value) is None:
        raise core.PilotError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    return value


def validate_campaign_feature_profile(profile: dict[str, object]) -> None:
    """Reject campaign geometry whose hard occupancy floor cannot be rendered."""
    core.validate_feature_profile(profile)
    geometry = profile["geometry"]
    safe_margin = geometry["mustIncludeSafeMargin"]
    maximum_rendered_occupancy = 1 - 2 * safe_margin
    for mode, config in geometry["modes"].items():
        if (
            config["minimumRenderedFeatureLongAxisOccupancy"] > maximum_rendered_occupancy + 1e-9
            or config["minimumRenderedFeatureShortAxisOccupancy"] > maximum_rendered_occupancy + 1e-9
        ):
            raise core.PilotError(
                f"framing mode {mode} 占比下限超过 mustIncludeSafeMargin 可实现上限 "
                f"{maximum_rendered_occupancy:.6f}"
            )


def verify_repo_artifact(record: dict[str, object], label: str) -> Path:
    return core.verify_artifact_record(record, label)


def load_representative_fixture() -> tuple[set[str], dict[str, list[str]]]:
    fixture = core.load_json(REPRESENTATIVE_FIXTURE_PATH)
    if not isinstance(fixture, dict):
        raise core.PilotError("代表集 fixture 顶层必须是对象")
    core.validate_fixture(fixture)
    refs: set[str] = set()
    variants: dict[str, list[str]] = {}
    for entity in fixture["entities"]:
        portrait_ref = entity["portraitRef"]
        refs.add(portrait_ref)
        variants[portrait_ref] = [variant["variantKey"] for variant in entity["variants"]]
    return refs, variants


def verify_representative_closure(path: Path) -> dict[str, object]:
    closure = core.load_json(path)
    if not isinstance(closure, dict) or closure.get("schema") != "cf7.enemy-portrait-representative-closure.v1":
        raise core.PilotError("代表集 closure schema 不受支持")
    core.verify_digest_object(closure, "reportDigest", "代表集 closure")
    counts = closure.get("counts", {})
    gates = closure.get("gates", {})
    if (
        closure.get("productionReady") is not False
        or counts.get("eligible") != 12
        or counts.get("eligibleResolved") != 12
        or gates.get("allEligibleVisualsResolved") is not True
        or gates.get("productionWrites") is not False
    ):
        raise core.PilotError("代表集 closure 尚未达到 12/12 eligible 视觉闭包")
    return closure


def resolve_representative_closure(value: str) -> Path:
    path = core.ensure_below(Path(value), PILOT_ROOT, "代表集 closure")
    if path.is_dir():
        path = path / "representative-closure.json"
    if not path.is_file():
        raise core.PilotError(f"代表集 closure 文件缺失：{path}")
    return path


def load_verified_source_choices(batch: Path) -> dict[str, object]:
    batch_root = core.ensure_below(batch, PILOT_ROOT, "选源批目录")
    data_path = batch_root / "source-choice-data.json"
    decisions_path = batch_root / "portrait-pilot-source-choice-decisions.json"
    receipt_path = batch_root / "human-source-choice-receipt.json"
    for label, path in (("data", data_path), ("decisions", decisions_path), ("receipt", receipt_path)):
        if not path.is_file():
            raise core.PilotError(f"选源批缺 {label}：{path.name}")

    data, _ = source_choices.verify_dataset(data_path)
    decisions = core.load_json(decisions_path)
    receipt = core.load_json(receipt_path)
    if not isinstance(decisions, dict) or not isinstance(receipt, dict):
        raise core.PilotError("选源 decisions/receipt 顶层必须是对象")
    core.verify_digest_object(receipt, "receiptDigest", "选源回执")
    if (
        receipt.get("schema") != "cf7.enemy-portrait-source-choice-receipt.v1"
        or receipt.get("productionReady") is not False
        or receipt.get("sourceDigest") != data["sourceDigest"]
        or receipt.get("manifestDigest") != data["manifestDigest"]
        or decisions.get("schema") != "cf7.enemy-portrait-source-choice-decisions.v1"
        or decisions.get("complete") is not True
        or decisions.get("sourceDigest") != data["sourceDigest"]
        or decisions.get("manifestDigest") != data["manifestDigest"]
    ):
        raise core.PilotError("选源 decisions/receipt 与候选数据不闭合")
    if receipt.get("inputs", {}).get("sourceChoiceData") != core.artifact(data_path):
        raise core.PilotError("选源回执未绑定当前 source-choice-data.json")
    if receipt.get("inputs", {}).get("decisions") != core.artifact(decisions_path):
        raise core.PilotError("选源回执未绑定当前 decisions")

    data_items = {item["portraitRef"]: item for item in data["items"]}
    choice_rows: dict[str, dict[str, object]] = {}
    receipt_rows = receipt.get("rows")
    if not isinstance(receipt_rows, list) or len(receipt_rows) != len(data_items):
        raise core.PilotError("选源回执行数不闭合")
    for row in receipt_rows:
        portrait_ref = row.get("portraitRef")
        review_key = row.get("reviewKey")
        item = data_items.get(portrait_ref)
        decision = decisions.get("choices", {}).get(review_key)
        if item is None or not isinstance(decision, dict):
            raise core.PilotError(f"选源回执含未知身份：{portrait_ref}")
        if any(row.get(field) != decision.get(field) for field in ("status", "sourceCandidateKey", "notes", "updatedAt")):
            raise core.PilotError(f"选源回执与决定漂移：{review_key}")
        status = row.get("status")
        source_key = row.get("sourceCandidateKey")
        selected = next((source for source in item["sources"] if source["sourceCandidateKey"] == source_key), None)
        if status == "selected":
            if selected is None or selected.get("renderable") is not True:
                raise core.PilotError(f"选源回执选择了不可渲染来源：{review_key}")
            selected_view = {field: selected.get(field) for field in ("swf", "symbolName", "orphan")}
            if row.get("selectedSource") != selected_view:
                raise core.PilotError(f"选源回执 selectedSource 漂移：{review_key}")
        elif status == "manual_maintenance":
            if source_key is not None or not str(row.get("notes", "")).strip():
                raise core.PilotError(f"人工维护选源决定不闭合：{review_key}")
        else:
            raise core.PilotError(f"选源回执状态非法：{review_key}")
        choice_rows[portrait_ref] = {"receiptRow": row, "sourceItem": item, "selected": selected}

    return {
        "batchRoot": batch_root,
        "dataPath": data_path,
        "decisionsPath": decisions_path,
        "receiptPath": receipt_path,
        "data": data,
        "decisions": decisions,
        "receipt": receipt,
        "rows": choice_rows,
    }


def load_consumer_inventory() -> tuple[dict[str, dict[str, object]], dict[str, int], list[Path]]:
    enemy_files = [
        ROOT / "data" / "enemy_properties" / node.text.strip()
        for node in ET.parse(core.ENEMY_LIST_PATH).getroot().findall("items")
        if node.text and node.text.strip()
    ]
    consumers: dict[str, dict[str, object]] = {}
    enemy_records = 0
    for enemy_file in enemy_files:
        for enemy in ET.parse(enemy_file).getroot():
            enemy_records += 1
            enemy_id = enemy.tag
            override = enemy.findtext("portraitRef")
            portrait_ref = override.strip() if override and override.strip() else enemy_id
            record = consumers.setdefault(portrait_ref, {"enemyIds": [], "petIds": [], "petIdentifiers": []})
            record["enemyIds"].append(enemy_id)

    pet_records = 0
    pet_identifiers: set[str] = set()
    for pet in ET.parse(core.PETS_PATH).getroot().findall("Pet"):
        pet_records += 1
        identifier = pet.findtext("Identifier")
        pet_id = pet.findtext("id")
        if not identifier or pet_id is None:
            continue
        identifier = identifier.strip()
        if not identifier or identifier == "默认":
            continue
        pet_identifiers.add(identifier)
        override = pet.findtext("PortraitRef")
        portrait_ref = override.strip() if override and override.strip() else identifier
        record = consumers.setdefault(portrait_ref, {"enemyIds": [], "petIds": [], "petIdentifiers": []})
        record["petIds"].append(int(pet_id))
        record["petIdentifiers"].append(identifier)

    normalized: dict[str, dict[str, object]] = {}
    for portrait_ref, record in consumers.items():
        if portrait_ref == "默认":
            continue
        normalized[portrait_ref] = {
            "enemy": bool(record["enemyIds"]),
            "enemyIds": sorted(set(record["enemyIds"])),
            "petIds": sorted(set(record["petIds"])),
            "petIdentifiers": sorted(set(record["petIdentifiers"])),
        }
    counts = {
        "enemyRecordCount": enemy_records,
        "enemyIdentityCount": sum(bool(value["enemyIds"]) for value in normalized.values()),
        "petRecordCount": pet_records,
        "petIdentifierCount": len(pet_identifiers),
        "petIdentityCount": sum(bool(value["petIds"]) for value in normalized.values()),
    }
    return normalized, counts, enemy_files


def selected_source_view(source: dict[str, object]) -> dict[str, object]:
    fields = (
        "sourceCandidateKey",
        "swf",
        "symbolName",
        "orphan",
        "rootCharacterId",
        "rootDeclaredFrameCount",
        "renderCharacterId",
        "renderDeclaredFrameCount",
        "renderStrategy",
        "renderStrategyWarning",
    )
    return {field: source.get(field) for field in fields if field in source}


def build_inventory_truth(source_choice_batch: Path) -> tuple[list[dict[str, object]], dict[str, int], list[Path], dict[str, object]]:
    source_choice = load_verified_source_choices(source_choice_batch)
    consumers, consumer_counts, enemy_files = load_consumer_inventory()
    asset_records = core.parse_asset_map()
    _, representative_variants = load_representative_fixture()
    items: list[dict[str, object]] = []

    for portrait_ref in sorted(consumers):
        map_record = asset_records.get(portrait_ref)
        classification = map_record["classification"] if map_record else "missing"
        sources = json.loads(json.dumps(map_record["sources"], ensure_ascii=False)) if map_record else []
        resolution = "missing"
        selected_source = None
        source_choice_digest = None
        if classification == "unique":
            resolution = "unique"
            selected_source = sources[0]
        elif classification in ("duplicate", "conflict"):
            choice = source_choice["rows"].get(portrait_ref)
            if choice and choice["receiptRow"]["status"] == "selected":
                resolution = "human_selected"
                selected_source = selected_source_view(choice["selected"])
                source_choice_digest = source_choice["receipt"]["receiptDigest"]
            elif choice and choice["receiptRow"]["status"] == "manual_maintenance":
                resolution = "manual_maintenance"
                source_choice_digest = source_choice["receipt"]["receiptDigest"]
            else:
                resolution = "source_choice_required"

        items.append(
            {
                "portraitRef": portrait_ref,
                "variantKeys": representative_variants.get(portrait_ref, ["default"]),
                "consumers": consumers[portrait_ref],
                "sourceClassification": classification,
                "sourceResolution": resolution,
                "sources": sources,
                "selectedSource": selected_source,
                "sourceChoiceReceiptDigest": source_choice_digest,
            }
        )

    resolution_counts = Counter(item["sourceResolution"] for item in items)
    classification_counts = Counter(item["sourceClassification"] for item in items)
    counts = {
        **consumer_counts,
        "consumerIdentityCount": len(items),
        "reviewUnitCount": sum(len(item["variantKeys"]) for item in items),
        "uniqueSourceIdentityCount": resolution_counts["unique"],
        "humanSelectedSourceIdentityCount": resolution_counts["human_selected"],
        "manualMaintenanceIdentityCount": resolution_counts["manual_maintenance"],
        "sourceChoiceRequiredIdentityCount": resolution_counts["source_choice_required"],
        "missingSourceIdentityCount": resolution_counts["missing"],
        "effectiveResolvedIdentityCount": resolution_counts["unique"] + resolution_counts["human_selected"],
        "duplicateIdentityCount": classification_counts["duplicate"],
        "conflictIdentityCount": classification_counts["conflict"],
    }
    return items, counts, enemy_files, source_choice


def inventory_source_files(
    enemy_files: list[Path], source_choice: dict[str, object], representative_closure_path: Path
) -> list[dict[str, object]]:
    paths = [
        core.ASSET_MAP_PATH,
        core.ENEMY_LIST_PATH,
        core.PETS_PATH,
        *enemy_files,
        REPRESENTATIVE_FIXTURE_PATH,
        representative_closure_path,
        source_choice["dataPath"],
        source_choice["decisionsPath"],
        source_choice["receiptPath"],
        Path(__file__),
        ROOT / "tools" / "portrait-pilot" / "prepare_pilot.py",
        ROOT / "tools" / "portrait-pilot" / "prepare_source_choices.py",
    ]
    seen: set[Path] = set()
    records = []
    for path in paths:
        resolved = path.resolve()
        if resolved not in seen:
            records.append(core.artifact(resolved))
            seen.add(resolved)
    return records


def build_inventory(args: argparse.Namespace) -> None:
    output_dir = core.ensure_below(Path(args.output), PILOT_ROOT, "inventory 输出目录")
    if output_dir.exists():
        raise core.PilotError(f"输出目录已存在，禁止覆盖：{output_dir}")
    batch_id = validate_batch_id(args.batch_id)
    source_choice_batch = core.ensure_below(Path(args.source_choice_batch), PILOT_ROOT, "选源批目录")
    representative_closure_path = resolve_representative_closure(args.representative_closure)
    representative_closure = verify_representative_closure(representative_closure_path)
    items, counts, enemy_files, source_choice = build_inventory_truth(source_choice_batch)
    output_dir.mkdir(parents=True)
    source_envelope = {
        "batchId": batch_id,
        "mode": "full_consumer_identity_inventory",
        "sourceFiles": inventory_source_files(enemy_files, source_choice, representative_closure_path),
        "sourceChoiceBatch": core.repo_rel(source_choice_batch),
        "sourceChoiceReceiptDigest": source_choice["receipt"]["receiptDigest"],
        "representativeClosureDigest": representative_closure["reportDigest"],
        "consumerRules": {
            "enemyDefaultPortraitRef": "enemyId",
            "enemyOverrideField": "portraitRef",
            "petDefaultPortraitRef": "Identifier",
            "petOverrideField": "PortraitRef",
            "excludedPetIdentifier": "默认",
            "identityKey": "portraitRef + variantKey",
        },
    }
    inventory = {
        "schema": INVENTORY_SCHEMA,
        "phase": "CAMPAIGN_INVENTORY",
        "status": "campaign_inventory_frozen",
        "productionReady": False,
        "batchId": batch_id,
        "createdAt": utc_now(),
        "sourceEnvelope": source_envelope,
        "sourceDigest": core.sha256_bytes(core.stable_bytes(source_envelope)),
        "counts": counts,
        "items": items,
        "gates": {
            "enemyAndPetConsumersUnified": True,
            "sourceChoiceReceiptBound": True,
            "identityAlternativesNotPromotedToVariants": True,
            "missingSourcesBlocked": True,
            "humanReviewRequiredPerShard": True,
            "productionWrites": False,
        },
    }
    inventory["inventoryDigest"] = core.sha256_bytes(core.stable_bytes(inventory))
    inventory_path = output_dir / "portrait-inventory.json"
    core.write_json(inventory_path, inventory)
    checked, artifact_count = verify_inventory(inventory_path)
    print(
        json.dumps(
            {
                "status": checked["status"],
                "path": core.repo_rel(inventory_path),
                "inventoryDigest": checked["inventoryDigest"],
                "sourceDigest": checked["sourceDigest"],
                "counts": checked["counts"],
                "artifactCount": artifact_count,
            },
            ensure_ascii=False,
        )
    )


def verify_inventory(path: Path) -> tuple[dict[str, object], int]:
    inventory_path = core.ensure_below(path, PILOT_ROOT, "inventory")
    inventory = core.load_json(inventory_path)
    if not isinstance(inventory, dict) or inventory.get("schema") != INVENTORY_SCHEMA:
        raise core.PilotError("campaign inventory schema 不受支持")
    digest_input = dict(inventory)
    digest_input.pop("inventoryDigest", None)
    if core.sha256_bytes(core.stable_bytes(digest_input)) != inventory.get("inventoryDigest"):
        raise core.PilotError("campaign inventoryDigest 不匹配")
    envelope = inventory.get("sourceEnvelope")
    if not isinstance(envelope, dict) or core.sha256_bytes(core.stable_bytes(envelope)) != inventory.get("sourceDigest"):
        raise core.PilotError("campaign inventory sourceDigest 不匹配")
    artifact_count = 0
    for record in envelope.get("sourceFiles", []):
        verify_repo_artifact(record, "campaign inventory source")
        artifact_count += 1
    source_choice_batch = ROOT / envelope["sourceChoiceBatch"]
    rebuilt_items, rebuilt_counts, _, source_choice = build_inventory_truth(source_choice_batch)
    if core.stable_bytes(rebuilt_items) != core.stable_bytes(inventory.get("items")):
        raise core.PilotError("campaign inventory 与当前 consumer/source truth 漂移")
    if rebuilt_counts != inventory.get("counts"):
        raise core.PilotError("campaign inventory counts 漂移")
    if envelope.get("sourceChoiceReceiptDigest") != source_choice["receipt"]["receiptDigest"]:
        raise core.PilotError("campaign inventory 选源回执摘要漂移")
    keys = [item["portraitRef"] for item in rebuilt_items]
    if len(keys) != len(set(keys)) or "默认" in keys:
        raise core.PilotError("campaign inventory identity 键重复或包含占位符")
    if inventory.get("productionReady") is not False or inventory.get("gates", {}).get("productionWrites") is not False:
        raise core.PilotError("campaign inventory production gate 非法")
    return inventory, artifact_count


def check_inventory(args: argparse.Namespace) -> None:
    inventory, artifact_count = verify_inventory(Path(args.inventory))
    print(
        json.dumps(
            {
                "status": "campaign_inventory_verified",
                "inventoryDigest": inventory["inventoryDigest"],
                "sourceDigest": inventory["sourceDigest"],
                "counts": inventory["counts"],
                "artifactCount": artifact_count,
            },
            ensure_ascii=False,
        )
    )


def load_exclusions(paths: list[str]) -> tuple[set[str], list[dict[str, object]]]:
    excluded: set[str] = set()
    records: list[dict[str, object]] = []
    for raw_path in paths:
        path = core.ensure_below(Path(raw_path), PILOT_ROOT, "排除 manifest")
        manifest = core.verify_manifest(path)
        for item in manifest.get("reviewItems", []):
            excluded.add(item["portraitRef"])
        for anomaly in manifest.get("campaign", {}).get("resolutionAnomalies", []):
            if isinstance(anomaly.get("portraitRef"), str):
                excluded.add(anomaly["portraitRef"])
        records.append(core.artifact(path))
    return excluded, records


def old_reference_for(item: dict[str, object]) -> dict[str, object] | None:
    matches = []
    for pet_id in item["consumers"]["petIds"]:
        path = ROOT / "launcher" / "web" / "assets" / "pets" / f"pet_{pet_id}.png"
        if path.is_file():
            matches.append(path)
    unique = sorted(set(matches))
    return core.artifact(unique[0]) if len(unique) == 1 else None


def build_campaign_contact_sheet(
    output_dir: Path,
    review_items: list[dict[str, object]],
    output_name: str,
    subtitle: str,
) -> tuple[dict[str, object], dict[str, object]]:
    _stale_record, font_evidence = core.build_feature_contact_sheet(
        output_dir, review_items, output_name, subtitle
    )
    output_path = output_dir / output_name
    font, _ = core.find_font()
    with Image.open(output_path) as opened:
        canvas = opened.convert("RGB")
    draw = ImageDraw.Draw(canvas)
    header_height = 84
    row_height = 286
    for row_index, item in enumerate(review_items):
        top = header_height + row_index * row_height
        fill = "#341E22" if item["blocked"] else ("#1C222A" if row_index % 2 == 0 else "#181E25")
        draw.rectangle((12, top + 130, 326, top + 160), fill=fill)
        draw.text((16, top + 134), "human=none / new campaign", font=font, fill="#F0C674")
    canvas.save(output_path, format="PNG", optimize=False, compress_level=9)
    return core.artifact(output_path), font_evidence


def resolve_bucket(
    output_dir: Path,
    bucket_index: int,
    swf_rel: str,
    rows: list[dict[str, object]],
) -> tuple[dict[str, object], list[dict[str, object]], list[dict[str, object]]]:
    swf_path = ROOT / swf_rel
    if not swf_path.is_file():
        raise core.PilotError(f"来源 SWF 缺失：{swf_rel}")
    xml_path = output_dir / "ffdec-xml" / f"source-{bucket_index:03d}.xml"
    xml_path.parent.mkdir(parents=True, exist_ok=True)
    run = core.run_ffdec(
        ["-onerror", "abort", "-swf2xml", str(swf_path), str(xml_path)],
        output_dir,
        f"source-{bucket_index:03d}-xml",
    )
    exports = core.export_assets_from_xml(xml_path)
    frame_counts = core.sprite_frame_counts(xml_path)
    resolved: list[dict[str, object]] = []
    anomalies: list[dict[str, object]] = []
    for row in rows:
        matches = exports.get(row["portraitRef"], [])
        if len(matches) != 1:
            anomalies.append(
                {
                    "portraitRef": row["portraitRef"],
                    "sourceSwf": swf_rel,
                    "reason": "linkage_character_id_not_unique",
                    "matches": matches,
                }
            )
            continue
        root_id = matches[0]
        if root_id not in frame_counts:
            anomalies.append(
                {
                    "portraitRef": row["portraitRef"],
                    "sourceSwf": swf_rel,
                    "reason": "linkage_root_not_define_sprite",
                    "rootCharacterId": root_id,
                }
            )
            continue
        try:
            man_id = core.first_frame_named_instance(xml_path, root_id, "man")
        except core.PilotError as error:
            anomalies.append(
                {
                    "portraitRef": row["portraitRef"],
                    "sourceSwf": swf_rel,
                    "reason": "named_man_not_unique",
                    "detail": str(error),
                }
            )
            continue
        if man_id is None:
            anomalies.append(
                {
                    "portraitRef": row["portraitRef"],
                    "sourceSwf": swf_rel,
                    "reason": "named_man_missing_root_fallback_forbidden",
                    "rootCharacterId": root_id,
                }
            )
            continue
        if man_id not in frame_counts:
            anomalies.append(
                {
                    "portraitRef": row["portraitRef"],
                    "sourceSwf": swf_rel,
                    "reason": "named_man_not_define_sprite",
                    "rootCharacterId": root_id,
                    "renderCharacterId": man_id,
                }
            )
            continue
        bound = row["selectedSource"]
        if row["sourceResolution"] == "human_selected" and (
            bound.get("rootCharacterId") != root_id or bound.get("renderCharacterId") != man_id
        ):
            anomalies.append(
                {
                    "portraitRef": row["portraitRef"],
                    "sourceSwf": swf_rel,
                    "reason": "human_selected_character_id_drift",
                    "expected": [bound.get("rootCharacterId"), bound.get("renderCharacterId")],
                    "actual": [root_id, man_id],
                }
            )
            continue
        resolved.append(
            {
                **row,
                "rootCharacterId": root_id,
                "rootDeclaredFrameCount": frame_counts[root_id],
                "renderCharacterId": man_id,
                "renderDeclaredFrameCount": frame_counts[man_id],
                "renderStrategy": "first_frame_named_man_instance",
                "renderStrategyWarning": None,
                "sourceSwf": swf_rel,
                "ffdecXmlPath": xml_path,
            }
        )
    return run, resolved, anomalies


def prepare_shard(args: argparse.Namespace) -> None:
    output_dir = core.ensure_below(Path(args.output), PILOT_ROOT, "campaign shard 输出目录")
    if output_dir.exists():
        raise core.PilotError(f"输出目录已存在，禁止覆盖：{output_dir}")
    batch_id = validate_batch_id(args.batch_id)
    shard_size = int(args.shard_size)
    source_groups = int(args.source_groups)
    if shard_size < 4 or shard_size > 48 or source_groups < 1 or source_groups > 12 or shard_size % source_groups:
        raise core.PilotError("shard-size 必须为 4..48 且能被 1..12 的 source-groups 整除")
    per_source = shard_size // source_groups
    if per_source > 16:
        raise core.PilotError("每个来源 SWF 的单 shard 身份数不得超过 16")

    inventory_path = core.ensure_below(Path(args.inventory), PILOT_ROOT, "campaign inventory")
    inventory, _ = verify_inventory(inventory_path)
    representative_closure_path = resolve_representative_closure(args.representative_closure)
    representative_closure = verify_representative_closure(representative_closure_path)
    if representative_closure["reportDigest"] != inventory["sourceEnvelope"]["representativeClosureDigest"]:
        raise core.PilotError("campaign shard 的代表集 closure 与 inventory 漂移")
    profile_path = Path(args.profile).resolve() if args.profile else PROFILE_PATH
    core.ensure_below(profile_path, ROOT, "特征 profile")
    profile = core.load_json(profile_path)
    if not isinstance(profile, dict):
        raise core.PilotError("特征 profile 顶层必须是对象")
    validate_campaign_feature_profile(profile)
    policy = profile["categoryPolicies"].get("unclassified")
    if not isinstance(policy, dict):
        raise core.PilotError("全量 campaign 需要 unclassified 特征策略")
    representative_refs, _ = load_representative_fixture()
    excluded, exclusion_records = load_exclusions(args.exclude_manifest or [])
    excluded.update(representative_refs)

    eligible = [
        item
        for item in inventory["items"]
        if item["sourceResolution"] in ("unique", "human_selected") and item["portraitRef"] not in excluded
    ]
    buckets: dict[str, list[dict[str, object]]] = defaultdict(list)
    for item in eligible:
        buckets[item["selectedSource"]["swf"]].append(item)
    ordered_buckets = sorted(buckets.items(), key=lambda entry: (-len(entry[1]), entry[0]))
    output_dir.mkdir(parents=True)
    ffdec = core.verify_ffdec()
    ffdec_runs: list[dict[str, object]] = []
    probe_swf_records: list[dict[str, object]] = []
    resolution_anomalies: list[dict[str, object]] = []
    selected_groups: list[tuple[str, list[dict[str, object]]]] = []
    bucket_counter = 0
    for swf_rel, rows in ordered_buckets:
        if len(selected_groups) == source_groups:
            break
        if len(rows) < per_source:
            continue
        bucket_counter += 1
        run, resolved, anomalies = resolve_bucket(
            output_dir,
            bucket_counter,
            swf_rel,
            sorted(rows, key=lambda row: row["portraitRef"]),
        )
        ffdec_runs.append(run)
        probe_swf_records.append(core.artifact(ROOT / swf_rel))
        resolution_anomalies.extend(anomalies)
        if len(resolved) >= per_source:
            selected_groups.append((swf_rel, resolved[:per_source]))
    if len(selected_groups) != source_groups:
        raise core.PilotError(
            f"无法组成 {source_groups} 个含 {per_source} 个唯一 man 的来源组；actual={len(selected_groups)}"
        )

    selected_rows = [row for _swf, rows in selected_groups for row in rows]
    entities: list[dict[str, object]] = []
    review_items: list[dict[str, object]] = []
    for index, row in enumerate(selected_rows, start=1):
        entity_code = f"e{index:02d}"
        entity = {
            "entityCode": entity_code,
            "portraitRef": row["portraitRef"],
            "category": "unclassified",
            "notes": "全量 campaign 新身份；由视觉模型先判断人形或非人，再锁定最强身份特征。",
            "variantResolution": "automatic_default",
            "sourceClassification": row["sourceClassification"],
            "sourceResolution": row["sourceResolution"],
            "sources": row["sources"],
            "selectedSource": row["selectedSource"],
            "consumers": row["consumers"],
            "characterId": row["rootCharacterId"],
            "declaredFrameCount": row["rootDeclaredFrameCount"],
            "renderCharacterId": row["renderCharacterId"],
            "renderDeclaredFrameCount": row["renderDeclaredFrameCount"],
            "renderStrategy": row["renderStrategy"],
            "renderStrategyWarning": None,
            "sourceSwf": row["sourceSwf"],
            "ffdecXml": core.artifact(row["ffdecXmlPath"]),
            "candidates": [],
        }
        entities.append(entity)
        review_items.append(
            {
                "reviewCode": f"R{index:02d}",
                "reviewKey": f"{row['portraitRef']}::default",
                "entityCode": entity_code,
                "portraitRef": row["portraitRef"],
                "variantKey": "default",
                "variantResolution": "automatic_default",
                "category": "unclassified",
                "sourceClassification": row["sourceClassification"],
                "sourceResolution": row["sourceResolution"],
                "blocked": False,
                "blockReason": None,
                "oldReference": old_reference_for(row),
                "humanFeedback": None,
                "intentPolicy": json.loads(json.dumps(policy, ensure_ascii=False)),
                "candidates": [],
            }
        )

    entities_by_swf: dict[str, list[dict[str, object]]] = defaultdict(list)
    for entity in entities:
        entities_by_swf[entity["sourceSwf"]].append(entity)
    for group_index, (swf_rel, group_entities) in enumerate(sorted(entities_by_swf.items()), start=1):
        gif_root = output_dir / "ffdec-gif" / f"selected-{group_index:03d}"
        gif_root.mkdir(parents=True)
        render_ids = sorted(set(int(entity["renderCharacterId"]) for entity in group_entities))
        ffdec_runs.append(
            core.run_ffdec(
                [
                    "-onerror",
                    "abort",
                    "-ignorebackground",
                    "-zoom",
                    "2",
                    "-selectid",
                    ",".join(str(value) for value in render_ids),
                    "-format",
                    "sprite:gif",
                    "-export",
                    "sprite",
                    str(gif_root),
                    str(ROOT / swf_rel),
                ],
                output_dir,
                f"selected-{group_index:03d}-gif",
            )
        )
        for entity in group_entities:
            matches = list(gif_root.glob(f"DefineSprite_{entity['renderCharacterId']}*/frames.gif"))
            if len(matches) != 1:
                raise core.PilotError(
                    f"campaign FFDec GIF 不唯一：{entity['portraitRef']} id={entity['renderCharacterId']} matches={len(matches)}"
                )
            gif_path = matches[0]
            inspected = core.inspect_gif_frames(gif_path)
            if not inspected:
                raise core.PilotError(f"campaign man 没有非空帧：{entity['portraitRef']}")
            selected = core.choose_evenly(inspected, 6)
            entity["candidates"] = core.save_selected_frames(
                gif_path,
                selected,
                output_dir / "candidates" / entity["entityCode"],
                entity["entityCode"],
            )
            entity["ffdecGif"] = core.artifact(gif_path)
            with Image.open(gif_path) as exported_gif:
                entity["exportedFrameCount"] = sum(1 for _ in ImageSequence.Iterator(exported_gif))
            entity["usableUniqueFrameCount"] = len(inspected)

    entity_by_code = {entity["entityCode"]: entity for entity in entities}
    for item in review_items:
        item["candidates"] = entity_by_code[item["entityCode"]]["candidates"]

    selected_swf_records = [core.artifact(ROOT / swf_rel) for swf_rel, _rows in selected_groups]
    parent_like = {"sourceEnvelope": {"sourceSwfs": selected_swf_records}}
    original_classifications = [entity["sourceClassification"] for entity in entities]
    try:
        for entity in entities:
            entity["sourceClassification"] = "unique"
        vector_ffdec, vector_runs, selected_swf_records = core.export_vector_candidate_sources(
            output_dir, entities, review_items, parent_like
        )
    finally:
        for entity, classification in zip(entities, original_classifications):
            entity["sourceClassification"] = classification
    if vector_ffdec != ffdec:
        raise core.PilotError("FFDec probe 在 campaign 准备期间漂移")
    ffdec_runs.extend(vector_runs)

    contact_sheet, font_evidence = build_campaign_contact_sheet(
        output_dir,
        review_items,
        "feature-contact-sheet.png",
        "NEW CAMPAIGN: infer humanoid head or non-human signature feature from exact man frames.",
    )
    model_batches = []
    for batch_index, start in enumerate(range(0, len(review_items), 4), start=1):
        batch_items = review_items[start : start + 4]
        model_batch_id = f"campaign-feature-batch-{batch_index:02d}"
        batch_sheet, _ = build_campaign_contact_sheet(
            output_dir,
            batch_items,
            f"{model_batch_id}.png",
            f"{model_batch_id}: {len(batch_items)} new identities; infer feature, frame and normalized boxes.",
        )
        model_batches.append(
            {
                "modelBatchId": model_batch_id,
                "reviewKeys": [item["reviewKey"] for item in batch_items],
                "contactSheet": batch_sheet,
            }
        )

    inventory_sources = inventory["sourceEnvelope"]["sourceFiles"]
    source_paths = [
        inventory_path,
        profile_path,
        REPRESENTATIVE_FIXTURE_PATH,
        representative_closure_path,
        Path(__file__),
        ROOT / "tools" / "portrait-pilot" / "prepare_pilot.py",
        ROOT / "tools" / "portrait-pilot" / "run-visual-pilot.js",
        *[ROOT / record["path"] for record in inventory_sources],
    ]
    source_files: list[dict[str, object]] = []
    seen_source_paths: set[Path] = set()
    for path in source_paths:
        resolved = path.resolve()
        if resolved not in seen_source_paths:
            source_files.append(core.artifact(resolved))
            seen_source_paths.add(resolved)
    source_files.extend(exclusion_records)
    source_envelope = {
        "batchId": batch_id,
        "mode": CAMPAIGN_MODE,
        "inventory": core.artifact(inventory_path),
        "inventoryDigest": inventory["inventoryDigest"],
        "profile": core.artifact(profile_path),
        "sourceFiles": source_files,
        "ffdec": ffdec,
        "sourceSwfs": selected_swf_records,
        "probedSourceSwfs": probe_swf_records,
        "pillowVersion": PILLOW_VERSION,
        "font": font_evidence,
    }
    source_digest = core.sha256_bytes(core.stable_bytes(source_envelope))
    source_counts = Counter(entity["sourceSwf"] for entity in entities)
    campaign = {
        "inventoryDigest": inventory["inventoryDigest"],
        "selectionStrategy": "remaining_identity_count_desc_then_swf_path; portraitRef_ascending; exact_named_man_only",
        "shardSize": shard_size,
        "sourceGroups": source_groups,
        "identitiesPerSourceGroup": per_source,
        "selectedSourceCounts": dict(sorted(source_counts.items())),
        "selectedPortraitRefs": [entity["portraitRef"] for entity in entities],
        "excludedRepresentativeRefs": sorted(representative_refs),
        "excludedPriorRefs": sorted(excluded - representative_refs),
        "resolutionAnomalies": resolution_anomalies,
        "serviceTierRecommendation": "fast",
        "maxConcurrencyRecommendation": 6,
        "expectedModelJobs": len(model_batches) * 2,
    }
    manifest = {
        "schema": "cf7.enemy-portrait-feature-refinement-candidates.v2",
        "phase": "P3_FEATURE_REFINEMENT",
        "status": "campaign_shard_prepared",
        "productionReady": False,
        "batchId": batch_id,
        "createdAt": utc_now(),
        "sourceDigest": source_digest,
        "sourceEnvelope": source_envelope,
        "campaign": campaign,
        "featureContract": {
            "global": profile["globalContract"],
            "geometry": profile["geometry"],
            "highResolutionRender": profile["highResolutionRender"],
            "categoryPolicies": profile["categoryPolicies"],
        },
        "counts": {
            "identityCount": len(entities),
            "reviewUnitCount": len(review_items),
            "eligibleReviewUnitCount": len(review_items),
            "blockedReviewUnitCount": 0,
        },
        "ffdecRuns": ffdec_runs,
        "contactSheet": contact_sheet,
        "modelBatches": model_batches,
        "entities": entities,
        "reviewItems": review_items,
        "gates": {
            "inventoryFrozen": True,
            "representativeSetExcluded": True,
            "exactNamedManRequired": True,
            "linkageRootFallbackForbidden": True,
            "semanticFeatureRequired": True,
            "humanReviewRequired": True,
            "productionWrites": False,
        },
    }
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    manifest_path = output_dir / "candidate-manifest.json"
    core.write_json(manifest_path, manifest)
    checked, artifact_count = verify_shard(manifest_path)
    print(
        json.dumps(
            {
                "status": checked["status"],
                "path": core.repo_rel(manifest_path),
                "manifestDigest": checked["manifestDigest"],
                "sourceDigest": checked["sourceDigest"],
                "identities": checked["counts"]["identityCount"],
                "sourceGroups": checked["campaign"]["sourceGroups"],
                "modelBatches": len(checked["modelBatches"]),
                "expectedModelJobs": checked["campaign"]["expectedModelJobs"],
                "resolutionAnomalies": len(checked["campaign"]["resolutionAnomalies"]),
                "artifactCount": artifact_count,
            },
            ensure_ascii=False,
        )
    )


def verify_shard(path: Path) -> tuple[dict[str, object], int]:
    manifest_path = core.ensure_below(path, PILOT_ROOT, "campaign shard manifest")
    manifest = core.verify_manifest(manifest_path)
    envelope = manifest.get("sourceEnvelope")
    campaign = manifest.get("campaign")
    if (
        not isinstance(envelope, dict)
        or envelope.get("mode") != CAMPAIGN_MODE
        or core.sha256_bytes(core.stable_bytes(envelope)) != manifest.get("sourceDigest")
        or not isinstance(campaign, dict)
    ):
        raise core.PilotError("campaign shard source/campaign envelope 不闭合")
    artifact_count = 0
    for record in [
        envelope.get("inventory"),
        envelope.get("profile"),
        *(envelope.get("sourceFiles") or []),
        *(envelope.get("sourceSwfs") or []),
        *(envelope.get("probedSourceSwfs") or []),
        *(envelope.get("ffdec", {}).get("files") or []),
    ]:
        verify_repo_artifact(record, "campaign shard source")
        artifact_count += 1
    inventory_path = ROOT / envelope["inventory"]["path"]
    inventory, _ = verify_inventory(inventory_path)
    if envelope.get("inventoryDigest") != inventory["inventoryDigest"] or campaign.get("inventoryDigest") != inventory["inventoryDigest"]:
        raise core.PilotError("campaign shard inventoryDigest 漂移")
    profile = core.load_json(ROOT / envelope["profile"]["path"])
    validate_campaign_feature_profile(profile)

    entities = manifest.get("entities")
    review_items = manifest.get("reviewItems")
    if not isinstance(entities, list) or not isinstance(review_items, list) or len(entities) != len(review_items):
        raise core.PilotError("campaign shard entity/review 行数不闭合")
    counts = manifest.get("counts", {})
    if counts != {
        "identityCount": len(entities),
        "reviewUnitCount": len(review_items),
        "eligibleReviewUnitCount": len(review_items),
        "blockedReviewUnitCount": 0,
    }:
        raise core.PilotError("campaign shard counts 不闭合")
    if len(entities) != campaign.get("shardSize") or len(manifest.get("modelBatches", [])) != (len(review_items) + 3) // 4:
        raise core.PilotError("campaign shard size/model batch 数不闭合")
    representative_refs, _ = load_representative_fixture()
    entity_by_code = {entity["entityCode"]: entity for entity in entities}
    portrait_refs: set[str] = set()
    for item in review_items:
        entity = entity_by_code.get(item.get("entityCode"))
        if entity is None or item.get("portraitRef") != entity.get("portraitRef"):
            raise core.PilotError("campaign shard review/entity 键不闭合")
        if item.get("portraitRef") in portrait_refs or item.get("portraitRef") in representative_refs:
            raise core.PilotError("campaign shard 含重复或代表集 identity")
        portrait_refs.add(item["portraitRef"])
        if (
            item.get("blocked") is not False
            or item.get("variantKey") != "default"
            or item.get("category") != "unclassified"
            or item.get("intentPolicy") != profile["categoryPolicies"]["unclassified"]
            or entity.get("renderStrategy") != "first_frame_named_man_instance"
            or entity.get("renderStrategyWarning") is not None
            or item.get("candidates") != entity.get("candidates")
        ):
            raise core.PilotError(f"campaign shard man/feature contract 非法：{item.get('reviewKey')}")
        for candidate in item["candidates"]:
            verify_repo_artifact(candidate["artifact"], "campaign candidate")
            verify_repo_artifact(candidate["vectorArtifact"], "campaign vector candidate")
            artifact_count += 2
    source_counts = Counter(entity["sourceSwf"] for entity in entities)
    expected_per_source = campaign["identitiesPerSourceGroup"]
    if (
        len(source_counts) != campaign.get("sourceGroups")
        or any(count != expected_per_source for count in source_counts.values())
        or dict(sorted(source_counts.items())) != campaign.get("selectedSourceCounts")
        or len(manifest.get("modelBatches", [])) * 2 != campaign.get("expectedModelJobs")
    ):
        raise core.PilotError("campaign shard 来源分组或 Fast 6 job 闭包错误")
    batched_keys = [key for batch in manifest["modelBatches"] for key in batch["reviewKeys"]]
    if sorted(batched_keys) != sorted(item["reviewKey"] for item in review_items):
        raise core.PilotError("campaign shard model batches 未精确覆盖审核键")
    for record in [manifest["contactSheet"], *(batch["contactSheet"] for batch in manifest["modelBatches"])]:
        verify_repo_artifact(record, "campaign contact sheet")
        artifact_count += 1
    for run in manifest.get("ffdecRuns", []):
        for field in ("stdout", "stderr", "commandRecord"):
            verify_repo_artifact(run[field], f"campaign FFDec {field}")
            artifact_count += 1
    if (
        manifest.get("productionReady") is not False
        or manifest.get("gates", {}).get("exactNamedManRequired") is not True
        or manifest.get("gates", {}).get("linkageRootFallbackForbidden") is not True
        or manifest.get("gates", {}).get("productionWrites") is not False
    ):
        raise core.PilotError("campaign shard gate 非法")
    return manifest, artifact_count


def check_shard(args: argparse.Namespace) -> None:
    manifest, artifact_count = verify_shard(Path(args.manifest))
    print(
        json.dumps(
            {
                "status": "campaign_shard_verified",
                "manifestDigest": manifest["manifestDigest"],
                "sourceDigest": manifest["sourceDigest"],
                "identities": manifest["counts"]["identityCount"],
                "sourceGroups": manifest["campaign"]["sourceGroups"],
                "modelBatches": len(manifest["modelBatches"]),
                "expectedModelJobs": manifest["campaign"]["expectedModelJobs"],
                "artifactCount": artifact_count,
            },
            ensure_ascii=False,
        )
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    inventory = subparsers.add_parser("inventory")
    inventory.add_argument("--output", required=True)
    inventory.add_argument("--batch-id", required=True)
    inventory.add_argument("--source-choice-batch", required=True)
    inventory.add_argument("--representative-closure", required=True)
    inventory.set_defaults(handler=build_inventory)
    inventory_check = subparsers.add_parser("check-inventory")
    inventory_check.add_argument("--inventory", required=True)
    inventory_check.set_defaults(handler=check_inventory)
    shard = subparsers.add_parser("prepare-shard")
    shard.add_argument("--inventory", required=True)
    shard.add_argument("--output", required=True)
    shard.add_argument("--batch-id", required=True)
    shard.add_argument("--representative-closure", required=True)
    shard.add_argument("--profile")
    shard.add_argument("--shard-size", type=int, default=12)
    shard.add_argument("--source-groups", type=int, default=3)
    shard.add_argument("--exclude-manifest", action="append", default=[])
    shard.set_defaults(handler=prepare_shard)
    shard_check = subparsers.add_parser("check-shard")
    shard_check.add_argument("--manifest", required=True)
    shard_check.set_defaults(handler=check_shard)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    try:
        args.handler(args)
    except core.PilotError as error:
        print(f"[portrait-campaign] ERROR: {error}", file=__import__("sys").stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
