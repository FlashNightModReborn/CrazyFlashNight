#!/usr/bin/env python3
"""Prepare the final three Team portrait gaps for real human review.

Lady and Ark Claw have no instance literally named ``man`` on the linkage
root's first frame.  Their visual body is nevertheless isolated at the same
depth-3 character slot used by later action states.  This controller permits
that narrowly verified equivalent while still excluding the root timeline's
health bars, level text and control overlays.  Giant Arm Zombie keeps the
previously human-selected SWF and ordinary named-man strategy.
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import importlib.util
import json
from collections import Counter, defaultdict
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageSequence, __version__ as PILLOW_VERSION


ROOT = Path(__file__).resolve().parents[2]
PILOT_ROOT = (ROOT / "tmp" / "portrait-pilot").resolve()
SCRIPT_DIR = Path(__file__).resolve().parent


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
core = load_module("team_gap_prepare_pilot", SCRIPT_DIR / "prepare_pilot.py")
base = load_module("team_gap_prepare_campaign", SCRIPT_DIR / "prepare_campaign.py")


SCHEMA = "cf7.enemy-portrait-feature-refinement-candidates.v2"
TEAM_GAP_SCHEMA = "cf7.enemy-portrait-team-gap-candidates.v1"
MODE = "team_consumer_gap_human_review_v1"
ARENA_MODE = "arena_direct_gap_human_review_v1"
TEAM_TARGETS = (
    "敌人-Lady",
    "敌人-巨臂僵尸",
    "敌人-方舟爪豪",
)
ARENA_DIRECT_TARGETS = (
    "敌人-红水晶",
    "敌人-唐头肌肉男",
    "敌人-锯片陷阱",
    "敌人-旧型号机器人改",
    "敌人-家用机器人",
)
TARGETS = TEAM_TARGETS
TEAM_DEPTH3_FALLBACKS = {"敌人-Lady", "敌人-方舟爪豪"}
DEPTH3_FALLBACKS = TEAM_DEPTH3_FALLBACKS
EXPECTED_PET_IDS = {
    "敌人-Lady": [94],
    "敌人-巨臂僵尸": [108],
    "敌人-方舟爪豪": [90],
}
EXPECTED_ARENA_UNIT_IDS = {
    "敌人-红水晶": 291,
    "敌人-唐头肌肉男": 368,
    "敌人-锯片陷阱": 379,
    "敌人-旧型号机器人改": 431,
    "敌人-家用机器人": 432,
}
DEFAULT_INVENTORY = (
    PILOT_ROOT
    / "campaign-inventory-r155-xfl-embedded-rescue5-20260808T032000Z"
    / "portrait-inventory.json"
)
DEFAULT_CALIBRATION_MANIFEST = (
    PILOT_ROOT
    / "campaign-shard-r164-xfl-rescue5-feedback186-20260808T045000Z"
    / "candidate-manifest.json"
)
DEFAULT_CLOSURE = PILOT_ROOT / "representative-closure-r13-20260806T031054Z" / "representative-closure.json"


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def validate_batch_id(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value or "") is None:
        raise core.PilotError("batch id 只允许 1–128 位 ASCII 字母、数字、点、下划线或连字符")
    return value


def verify_record(record: dict[str, object], label: str) -> Path:
    return core.verify_artifact_record(record, label)


def verify_frozen_inventory(path: Path) -> tuple[dict[str, object], int]:
    inventory = core.load_json(path)
    if not isinstance(inventory, dict):
        raise core.PilotError("战队缺口 inventory 顶层必须是对象")
    digest_input = copy.deepcopy(inventory)
    digest = digest_input.pop("inventoryDigest", None)
    if core.sha256_bytes(core.stable_bytes(digest_input)) != digest:
        raise core.PilotError("战队缺口 inventoryDigest 漂移")
    envelope = inventory.get("sourceEnvelope")
    if not isinstance(envelope, dict) or core.sha256_bytes(core.stable_bytes(envelope)) != inventory.get("sourceDigest"):
        raise core.PilotError("战队缺口 inventory sourceDigest 漂移")
    artifact_count = 0
    for record in envelope.get("sourceFiles", []):
        verify_record(record, "战队缺口 inventory 来源")
        artifact_count += 1
    if len(inventory.get("items", [])) != inventory.get("counts", {}).get("consumerIdentityCount"):
        raise core.PilotError("战队缺口 inventory identityCount 不闭合")
    return inventory, artifact_count


def build_arena_direct_inventory(inventory: dict[str, object]) -> list[dict[str, object]]:
    units_path = ROOT / "data" / "units" / "units.json"
    units = core.load_json(units_path)
    if not isinstance(units, list):
        raise core.PilotError("Arena units.json 顶层必须是数组")
    unit_ids = {
        str(row.get("spritename", "")).strip(): int(row["id"])
        for row in units
        if isinstance(row, dict) and row.get("spritename") and row.get("id") is not None
    }
    assets = core.parse_asset_map()
    campaign_by_ref = {row["portraitRef"]: row for row in inventory["items"]}
    selected: list[dict[str, object]] = []
    for portrait_ref in ARENA_DIRECT_TARGETS:
        expected_id = EXPECTED_ARENA_UNIT_IDS[portrait_ref]
        if unit_ids.get(portrait_ref) != expected_id:
            raise core.PilotError(
                f"Arena unitId 漂移：{portrait_ref}={unit_ids.get(portrait_ref)} expected={expected_id}"
            )
        if portrait_ref == "敌人-唐头肌肉男":
            row = campaign_by_ref.get(portrait_ref)
            if not isinstance(row, dict) or row.get("sourceResolution") != "human_selected":
                raise core.PilotError("唐头肌肉男必须复用已冻结的人类选源")
            current = copy.deepcopy(row)
        else:
            asset = assets.get(portrait_ref)
            if not isinstance(asset, dict) or asset.get("classification") != "unique":
                raise core.PilotError(f"Arena 直接缺口来源不再唯一：{portrait_ref}")
            sources = copy.deepcopy(asset.get("sources"))
            if not isinstance(sources, list) or len(sources) != 1:
                raise core.PilotError(f"Arena 直接缺口来源数非法：{portrait_ref}")
            current = {
                "portraitRef": portrait_ref,
                "sourceClassification": "unique",
                "sourceResolution": "unique",
                "sources": sources,
                "selectedSource": copy.deepcopy(sources[0]),
                "sourceChoiceDigest": None,
            }
        current["consumers"] = {
            "enemy": False,
            "enemyIds": [],
            "petIds": [],
            "petIdentifiers": [],
            "arenaUnitIds": [expected_id],
        }
        selected.append(current)
    return selected


def first_frame_primary_body_depth3(
    xml_path: Path, root_character_id: int, frame_counts: dict[int, int]
) -> int | None:
    definitions = {
        int(node.attrib["spriteId"]): node
        for node in ET.parse(xml_path).getroot().iter("item")
        if node.attrib.get("type") == "DefineSpriteTag"
    }
    root_sprite = definitions.get(root_character_id)
    sub_tags = root_sprite.find("subTags") if root_sprite is not None else None
    if sub_tags is None:
        return None
    matches: list[int] = []
    for node in sub_tags.findall("item"):
        if node.attrib.get("type") == "ShowFrameTag":
            break
        if node.attrib.get("depth") != "3" or not node.attrib.get("characterId"):
            continue
        character_id = int(node.attrib["characterId"])
        if character_id > 0 and character_id in frame_counts:
            matches.append(character_id)
    unique = sorted(set(matches))
    if len(unique) > 1:
        raise core.PilotError(f"首帧 depth=3 主体不唯一：root={root_character_id} ids={unique}")
    return unique[0] if unique else None


def resolve_target(
    output: Path,
    index: int,
    inventory_row: dict[str, object],
    depth3_fallbacks: set[str],
) -> tuple[dict[str, object], dict[str, object], dict[str, object]]:
    portrait_ref = inventory_row["portraitRef"]
    selected_source = inventory_row["selectedSource"]
    swf_rel = selected_source["swf"]
    swf_path = ROOT / swf_rel
    if not swf_path.is_file():
        raise core.PilotError(f"战队缺口来源 SWF 不存在：{portrait_ref} -> {swf_rel}")
    xml_path = output / "ffdec-xml" / f"source-{index:03d}.xml"
    xml_path.parent.mkdir(parents=True, exist_ok=True)
    xml_run = core.run_ffdec(
        ["-onerror", "abort", "-swf2xml", str(swf_path), str(xml_path)],
        output,
        f"source-{index:03d}-xml",
    )
    exports = core.export_assets_from_xml(xml_path)
    matches = exports.get(portrait_ref, [])
    if len(matches) != 1:
        raise core.PilotError(f"战队缺口 linkage 不唯一：{portrait_ref} matches={matches}")
    root_id = matches[0]
    frame_counts = core.sprite_frame_counts(xml_path)
    if root_id not in frame_counts:
        raise core.PilotError(f"战队缺口 linkage root 不是 sprite：{portrait_ref} id={root_id}")
    render_id = core.first_frame_named_instance(xml_path, root_id, "man")
    strategy = "first_frame_named_man_instance"
    warning = None
    if render_id is None and portrait_ref in depth3_fallbacks:
        render_id = first_frame_primary_body_depth3(xml_path, root_id, frame_counts)
        strategy = "first_frame_primary_body_depth3"
        warning = "named_man_missing; verified unique first-frame depth-3 body excludes root UI"
    if render_id is None or render_id not in frame_counts:
        raise core.PilotError(f"战队缺口没有可验证的内部主体：{portrait_ref}")
    if inventory_row["sourceResolution"] == "human_selected":
        expected = (selected_source.get("rootCharacterId"), selected_source.get("renderCharacterId"))
        if expected != (root_id, render_id):
            raise core.PilotError(
                f"人工选源角色 id 漂移：{portrait_ref} expected={expected} actual={(root_id, render_id)}"
            )
    resolved = {
        **inventory_row,
        "rootCharacterId": root_id,
        "rootDeclaredFrameCount": frame_counts[root_id],
        "renderCharacterId": render_id,
        "renderDeclaredFrameCount": frame_counts[render_id],
        "renderStrategy": strategy,
        "renderStrategyWarning": warning,
        "sourceSwf": swf_rel,
        "ffdecXmlPath": xml_path,
    }
    evidence = {
        "portraitRef": portrait_ref,
        "rootCharacterId": root_id,
        "renderCharacterId": render_id,
        "renderStrategy": strategy,
        "renderStrategyWarning": warning,
        "rootUiExcluded": True,
        "sourceSwf": core.artifact(swf_path),
        "ffdecXml": core.artifact(xml_path),
    }
    return resolved, evidence, xml_run


def prepare(args: argparse.Namespace) -> None:
    output = core.ensure_below(Path(args.output), PILOT_ROOT, "战队缺口审核输出")
    if output.exists():
        raise core.PilotError(f"输出目录已存在，禁止覆盖：{output}")
    batch_id = validate_batch_id(args.batch_id)
    inventory_path = core.ensure_below(Path(args.inventory), PILOT_ROOT, "campaign inventory")
    inventory, _artifact_count = verify_frozen_inventory(inventory_path)
    arena_scope = args.scope == "arena-direct-gaps"
    targets = ARENA_DIRECT_TARGETS if arena_scope else TEAM_TARGETS
    depth3_fallbacks = set() if arena_scope else TEAM_DEPTH3_FALLBACKS
    mode = ARENA_MODE if arena_scope else MODE
    calibration_path = core.ensure_below(
        Path(args.calibration_manifest), PILOT_ROOT, "累计人类偏好 manifest"
    )
    calibration_manifest = core.verify_manifest(calibration_path)
    calibration = calibration_manifest.get("humanPreferenceCalibration")
    if not isinstance(calibration, dict) or calibration.get("coverage", {}).get("decisionCount") != 186:
        raise core.PilotError("累计人类偏好必须精确绑定 186 条真实标注")
    closure_path = base.resolve_representative_closure(args.representative_closure)
    closure = base.verify_representative_closure(closure_path)
    if closure["reportDigest"] != inventory["sourceEnvelope"]["representativeClosureDigest"]:
        raise core.PilotError("战队缺口的代表集 closure 与 inventory 漂移")
    profile_path = Path(args.profile).resolve() if args.profile else base.PROFILE_PATH.resolve()
    core.ensure_below(profile_path, ROOT, "特征 profile")
    profile = core.load_json(profile_path)
    base.validate_campaign_feature_profile(profile)
    policy = profile["categoryPolicies"].get("unclassified")
    if not isinstance(policy, dict):
        raise core.PilotError("战队缺口需要 unclassified 特征策略")

    if arena_scope:
        selected_inventory = build_arena_direct_inventory(inventory)
    else:
        by_ref = {row["portraitRef"]: row for row in inventory["items"]}
        selected_inventory = []
        for portrait_ref in targets:
            row = by_ref.get(portrait_ref)
            if not isinstance(row, dict):
                raise core.PilotError(f"inventory 缺战队 identity：{portrait_ref}")
            if row["sourceResolution"] not in ("unique", "human_selected"):
                raise core.PilotError(f"战队缺口来源仍未解决：{portrait_ref}={row['sourceResolution']}")
            if row["consumers"]["petIds"] != EXPECTED_PET_IDS[portrait_ref]:
                raise core.PilotError(f"战队缺口 petId 漂移：{portrait_ref}={row['consumers']['petIds']}")
            selected_inventory.append(row)

    output.mkdir(parents=True)
    resolved_rows: list[dict[str, object]] = []
    resolution_evidence: list[dict[str, object]] = []
    ffdec_runs: list[dict[str, object]] = []
    for index, row in enumerate(selected_inventory, start=1):
        resolved, evidence, run = resolve_target(output, index, row, depth3_fallbacks)
        resolved_rows.append(resolved)
        resolution_evidence.append(evidence)
        ffdec_runs.append(run)

    entities: list[dict[str, object]] = []
    review_items: list[dict[str, object]] = []
    for index, row in enumerate(resolved_rows, start=1):
        entity_code = f"e{index:02d}"
        entity = {
            "entityCode": entity_code,
            "portraitRef": row["portraitRef"],
            "category": "unclassified",
            "notes": (
                "竞技场全兵种直接来源缺口；复用 186 条真人偏好，优先头部或非人最强身份特征。"
                if arena_scope else
                "战队消费者最后缺口；复用 186 条真人偏好，优先头部或非人最强身份特征。"
            ),
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
            "renderStrategyWarning": row["renderStrategyWarning"],
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
                "oldReference": base.old_reference_for(row),
                "humanFeedback": None,
                "intentPolicy": copy.deepcopy(policy),
                "candidates": [],
            }
        )

    entities_by_swf: dict[str, list[dict[str, object]]] = defaultdict(list)
    for entity in entities:
        entities_by_swf[entity["sourceSwf"]].append(entity)
    for group_index, (swf_rel, group_entities) in enumerate(sorted(entities_by_swf.items()), start=1):
        gif_root = output / "ffdec-gif" / f"selected-{group_index:03d}"
        gif_root.mkdir(parents=True)
        render_ids = sorted({int(entity["renderCharacterId"]) for entity in group_entities})
        ffdec_runs.append(
            core.run_ffdec(
                [
                    "-onerror", "abort", "-ignorebackground", "-zoom", "2",
                    "-selectid", ",".join(str(value) for value in render_ids),
                    "-format", "sprite:gif", "-export", "sprite",
                    str(gif_root), str(ROOT / swf_rel),
                ],
                output,
                f"selected-{group_index:03d}-gif",
            )
        )
        for entity in group_entities:
            matches = list(gif_root.glob(f"DefineSprite_{entity['renderCharacterId']}*/frames.gif"))
            if len(matches) != 1:
                raise core.PilotError(
                    f"战队缺口 GIF 不唯一：{entity['portraitRef']} id={entity['renderCharacterId']}"
                )
            gif_path = matches[0]
            inspected = core.inspect_gif_frames(gif_path)
            if not inspected:
                raise core.PilotError(f"战队缺口内部主体没有非空帧：{entity['portraitRef']}")
            selected = core.choose_evenly(inspected, 6)
            entity["candidates"] = core.save_selected_frames(
                gif_path,
                selected,
                output / "candidates" / entity["entityCode"],
                entity["entityCode"],
            )
            entity["ffdecGif"] = core.artifact(gif_path)
            with Image.open(gif_path) as exported:
                entity["exportedFrameCount"] = sum(1 for _frame in ImageSequence.Iterator(exported))
            entity["usableUniqueFrameCount"] = len(inspected)

    entity_by_code = {entity["entityCode"]: entity for entity in entities}
    for item in review_items:
        item["candidates"] = entity_by_code[item["entityCode"]]["candidates"]

    selected_swf_records = [core.artifact(ROOT / entity["sourceSwf"]) for entity in entities]
    selected_swf_records = list({record["path"]: record for record in selected_swf_records}.values())
    original_classifications = [entity["sourceClassification"] for entity in entities]
    try:
        for entity in entities:
            entity["sourceClassification"] = "unique"
        vector_ffdec, vector_runs, vector_swf_records = core.export_vector_candidate_sources(
            output,
            entities,
            review_items,
            {"sourceEnvelope": {"sourceSwfs": selected_swf_records}},
        )
    finally:
        for entity, classification in zip(entities, original_classifications):
            entity["sourceClassification"] = classification
    ffdec_runs.extend(vector_runs)
    if {record["path"] for record in vector_swf_records} != {record["path"] for record in selected_swf_records}:
        raise core.PilotError("战队缺口 SVG/SWF 来源闭包漂移")

    contact_sheet, font_evidence = base.build_campaign_contact_sheet(
        output,
        review_items,
        "feature-contact-sheet.png",
        "TEAM CLOSURE: infer the strongest identity feature using 186 real human labels.",
    )
    model_batches: list[dict[str, object]] = []
    batch_sheets: list[dict[str, object]] = []
    for start in range(0, len(review_items), 4):
        batch_number = start // 4 + 1
        batch_id_for_model = f"campaign-feature-batch-{batch_number:02d}"
        batch_items = review_items[start : start + 4]
        batch_sheet, _font = base.build_campaign_contact_sheet(
            output,
            batch_items,
            f"{batch_id_for_model}.png",
            (
                "Arena direct gaps; head-first, feature-first, safe-margin framing."
                if arena_scope else
                "Final 3 Team identities; head-first, feature-first, safe-margin framing."
            ),
        )
        batch_sheets.append(batch_sheet)
        model_batches.append(
            {
                "modelBatchId": batch_id_for_model,
                "reviewKeys": [item["reviewKey"] for item in batch_items],
                "contactSheet": batch_sheet,
            }
        )
    calibration_bound = copy.deepcopy(calibration)
    calibration_bound["contactSheets"] = []
    for current_record in (contact_sheet, *batch_sheets):
        current_path = verify_record(current_record, "战队缺口当前候选图")
        with Image.open(current_path) as opened:
            dimensions = [opened.width, opened.height]
        calibration_bound["contactSheets"].append(
            {
                "base": current_record,
                "baseDimensions": dimensions,
                "composite": current_record,
                "compositeDimensions": dimensions,
                "transportPolicy": "current_candidates_sent_separately_from_compact_human_atlas",
            }
        )

    source_paths = [
        inventory_path,
        calibration_path,
        closure_path,
        profile_path,
        Path(__file__),
        SCRIPT_DIR / "prepare_campaign.py",
        SCRIPT_DIR / "prepare_pilot.py",
        SCRIPT_DIR / "run-visual-pilot.js",
        *[ROOT / record["path"] for record in inventory["sourceEnvelope"]["sourceFiles"]],
    ]
    if arena_scope:
        source_paths.extend([ROOT / "data" / "units" / "units.json", core.ASSET_MAP_PATH])
    source_files: list[dict[str, object]] = []
    seen_paths: set[Path] = set()
    for path in source_paths:
        resolved = path.resolve()
        if resolved not in seen_paths:
            source_files.append(core.artifact(resolved))
            seen_paths.add(resolved)
    source_envelope = {
        "batchId": batch_id,
        "mode": mode,
        "scope": args.scope,
        "inventory": core.artifact(inventory_path),
        "inventoryDigest": inventory["inventoryDigest"],
        "humanPreferenceManifest": core.artifact(calibration_path),
        "humanPreferenceDecisionCount": 186,
        "profile": core.artifact(profile_path),
        "representativeClosure": core.artifact(closure_path),
        "sourceFiles": source_files,
        "sourceSwfs": selected_swf_records,
        "ffdec": vector_ffdec,
        "pillowVersion": PILLOW_VERSION,
        "font": font_evidence,
    }
    source_digest = core.sha256_bytes(core.stable_bytes(source_envelope))
    source_counts = Counter(entity["sourceSwf"] for entity in entities)
    manifest: dict[str, object] = {
        "schema": SCHEMA,
        "teamGapSchema": TEAM_GAP_SCHEMA,
        "phase": "P3_FEATURE_REFINEMENT",
        "status": "team_gap_human_review_prepared",
        "productionReady": False,
        "batchId": batch_id,
        "createdAt": utc_now(),
        "sourceDigest": source_digest,
        "sourceEnvelope": source_envelope,
        "campaign": {
            "inventoryDigest": inventory["inventoryDigest"],
            "selectionStrategy": (
                "explicit_arena_direct_gap_closure; named_man_only"
                if arena_scope else
                "explicit_team_consumer_closure; named_man_or_verified_depth3_body"
            ),
            "shardSize": len(targets),
            "sourceGroups": len(source_counts),
            "identitiesPerSourceGroup": None,
            "selectedSourceCounts": dict(sorted(source_counts.items())),
            "selectedPortraitRefs": list(targets),
            "controlledPrimaryBodyFallbackRefs": sorted(depth3_fallbacks),
            "resolutionEvidence": resolution_evidence,
            "serviceTierRecommendation": "fast",
            "maxConcurrencyRecommendation": 6,
            "localizationConcurrencyRecommendation": 3,
            "timeoutSeconds": 600,
            "expectedModelJobs": len(model_batches) * 2,
        },
        "humanPreferenceCalibration": calibration_bound,
        "featureContract": {
            "global": profile["globalContract"],
            "geometry": profile["geometry"],
            "highResolutionRender": profile["highResolutionRender"],
            "categoryPolicies": profile["categoryPolicies"],
        },
        "counts": {
            "identityCount": len(targets),
            "reviewUnitCount": len(targets),
            "eligibleReviewUnitCount": len(targets),
            "blockedReviewUnitCount": 0,
        },
        "ffdecRuns": ffdec_runs,
        "contactSheet": contact_sheet,
        "modelBatches": model_batches,
        "entities": entities,
        "reviewItems": review_items,
        "gates": {
            "inventoryFrozen": True,
            "explicitTeamConsumerClosure": not arena_scope,
            "explicitArenaDirectGapClosure": arena_scope,
            "namedManOrVerifiedDepth3BodyRequired": True,
            "rootTimelineUiExcluded": True,
            "all186HumanLabelsBound": True,
            "semanticFeatureRequired": True,
            "humanReviewRequired": True,
            "productionWrites": False,
        },
    }
    manifest["manifestDigest"] = core.sha256_bytes(core.stable_bytes(manifest))
    manifest_path = output / "candidate-manifest.json"
    core.write_json(manifest_path, manifest)
    checked, artifact_count = verify_manifest(manifest_path)
    print(
        json.dumps(
            {
                "status": checked["status"],
                "manifest": core.repo_rel(manifest_path),
                "manifestDigest": checked["manifestDigest"],
                "sourceDigest": checked["sourceDigest"],
                "reviewKeys": [item["reviewKey"] for item in checked["reviewItems"]],
                "artifactCount": artifact_count,
            },
            ensure_ascii=False,
        )
    )


def verify_manifest(path: Path) -> tuple[dict[str, object], int]:
    manifest_path = core.ensure_below(path, PILOT_ROOT, "战队缺口 manifest")
    manifest = core.verify_manifest(manifest_path)
    if (
        manifest.get("schema") != SCHEMA
        or manifest.get("teamGapSchema") != TEAM_GAP_SCHEMA
        or manifest.get("productionReady") is not False
    ):
        raise core.PilotError("战队缺口 manifest schema/productionReady 非法")
    envelope = manifest.get("sourceEnvelope")
    campaign = manifest.get("campaign")
    mode = envelope.get("mode") if isinstance(envelope, dict) else None
    if mode == ARENA_MODE:
        targets = ARENA_DIRECT_TARGETS
        depth3_fallbacks: set[str] = set()
    elif mode == MODE:
        targets = TEAM_TARGETS
        depth3_fallbacks = TEAM_DEPTH3_FALLBACKS
    else:
        raise core.PilotError(f"消费者缺口 mode 不受支持：{mode}")
    if (
        not isinstance(envelope, dict)
        or core.sha256_bytes(core.stable_bytes(envelope)) != manifest.get("sourceDigest")
        or envelope.get("humanPreferenceDecisionCount") != 186
        or not isinstance(campaign, dict)
    ):
        raise core.PilotError("战队缺口 source/campaign envelope 不闭合")
    artifact_count = 0
    for record in [
        envelope.get("inventory"), envelope.get("humanPreferenceManifest"),
        envelope.get("profile"), envelope.get("representativeClosure"),
        *(envelope.get("sourceFiles") or []), *(envelope.get("sourceSwfs") or []),
        *(envelope.get("ffdec", {}).get("files") or []),
    ]:
        verify_record(record, "战队缺口来源")
        artifact_count += 1
    entities = manifest.get("entities")
    review_items = manifest.get("reviewItems")
    if (
        not isinstance(entities, list)
        or not isinstance(review_items, list)
        or len(entities) != len(targets)
        or len(review_items) != len(targets)
    ):
        raise core.PilotError("战队缺口 entity/review 数不闭合")
    refs = [item.get("portraitRef") for item in review_items]
    if refs != list(targets) or campaign.get("selectedPortraitRefs") != list(targets):
        raise core.PilotError(f"战队缺口 identity 漂移：{refs}")
    if set(campaign.get("controlledPrimaryBodyFallbackRefs", [])) != depth3_fallbacks:
        raise core.PilotError("战队缺口 depth3 受控例外漂移")
    entity_by_code = {entity["entityCode"]: entity for entity in entities}
    for item in review_items:
        entity = entity_by_code.get(item.get("entityCode"))
        if entity is None or item.get("candidates") != entity.get("candidates"):
            raise core.PilotError(f"战队缺口 review/entity 不闭合：{item.get('reviewKey')}")
        expected_strategy = (
            "first_frame_primary_body_depth3"
            if item["portraitRef"] in depth3_fallbacks
            else "first_frame_named_man_instance"
        )
        if entity.get("renderStrategy") != expected_strategy:
            raise core.PilotError(f"战队缺口内部主体策略漂移：{item.get('reviewKey')}")
        for candidate in item["candidates"]:
            verify_record(candidate["artifact"], "战队缺口候选")
            verify_record(candidate["vectorArtifact"], "战队缺口矢量候选")
            artifact_count += 2
    for record in [manifest["contactSheet"], *(batch["contactSheet"] for batch in manifest["modelBatches"])]:
        verify_record(record, "战队缺口 contact sheet")
        artifact_count += 1
    if (
        manifest.get("humanPreferenceCalibration", {}).get("coverage", {}).get("decisionCount") != 186
        or manifest.get("gates", {}).get("humanReviewRequired") is not True
        or manifest.get("gates", {}).get("rootTimelineUiExcluded") is not True
        or manifest.get("gates", {}).get("productionWrites") is not False
    ):
        raise core.PilotError("战队缺口人类偏好/审核 gate 不闭合")
    return manifest, artifact_count


def check(args: argparse.Namespace) -> None:
    manifest, artifact_count = verify_manifest(Path(args.manifest))
    print(
        json.dumps(
            {
                "status": "team_gap_human_review_verified",
                "manifest": core.repo_rel(Path(args.manifest).resolve()),
                "manifestDigest": manifest["manifestDigest"],
                "reviewKeys": [item["reviewKey"] for item in manifest["reviewItems"]],
                "artifactCount": artifact_count,
            },
            ensure_ascii=False,
        )
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--inventory", default=str(DEFAULT_INVENTORY))
    prepare_parser.add_argument("--calibration-manifest", default=str(DEFAULT_CALIBRATION_MANIFEST))
    prepare_parser.add_argument("--representative-closure", default=str(DEFAULT_CLOSURE))
    prepare_parser.add_argument("--profile")
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.add_argument("--batch-id", required=True)
    prepare_parser.add_argument(
        "--scope",
        choices=("team-gaps", "arena-direct-gaps"),
        default="team-gaps",
    )
    prepare_parser.set_defaults(handler=prepare)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--manifest", required=True)
    check_parser.set_defaults(handler=check)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        args.handler(args)
    except core.PilotError as error:
        print(f"[team-gap-review] ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
