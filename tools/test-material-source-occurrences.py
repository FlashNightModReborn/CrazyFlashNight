#!/usr/bin/env python3
"""A1 authored-data oracle for material source occurrence identity.

This script checks only the current XML/JSON authoring closure. It proves that
the source data contains the expected repeated occurrences and stable authored
indexes; it does not prove that the AS2 runtime preserves them. Runtime
non-deduplication remains the responsibility of the focused AS2 fixtures.

No aggregate is silently treated as dynamic: current-data totals are explicit
ratchets and must be reviewed when authored data changes.
"""

import json
from pathlib import Path
import xml.etree.ElementTree as ET


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
DATA_ROOT = REPOSITORY_ROOT / "data"
ITEMS_ROOT = DATA_ROOT / "items"
CRAFTING_ROOT = DATA_ROOT / "crafting"
ENEMY_ROOT = DATA_ROOT / "enemy_properties"
STAGES_ROOT = DATA_ROOT / "stages"

ANDY_CATEGORY = "基础防具"
ANDY_PRODUCT = "Andy套装碎片"
TACTICAL_GRIP = "战术握把"
STAGE_FIXTURE_NAME = "中秋国庆副本"
STAGE_FIXTURE_MATERIAL = "不锈钢材"

EXPECTED_ANDY_RECIPES = (
    {"recipeIndex": 30, "materialName": "国庆纪念币", "authored": "国庆纪念币#5"},
    {"recipeIndex": 31, "materialName": "月之碎片", "authored": "月之碎片#5"},
    {"recipeIndex": 32, "materialName": "剑圣碎片", "authored": "剑圣碎片#5"},
)

EXPECTED_TACTICAL_GRIP_GROUPS = (
    {
        "enemyType": "敌人-重型改造僵尸",
        "variants": (
            {
                "dropIndex": 0,
                "probability": "3",
                "minReverseLevel": "1",
                "maxReverseLevel": "3",
                "quantityMin": None,
                "quantityMax": None,
            },
            {
                "dropIndex": 1,
                "probability": "5",
                "minReverseLevel": "4",
                "maxReverseLevel": None,
                "quantityMin": None,
                "quantityMax": None,
            },
        ),
    },
    {
        "enemyType": "敌人-军阀精英突击兵",
        "variants": (
            {
                "dropIndex": 0,
                "probability": "3",
                "minReverseLevel": None,
                "maxReverseLevel": "2",
                "quantityMin": "1",
                "quantityMax": "1",
            },
            {
                "dropIndex": 1,
                "probability": "5",
                "minReverseLevel": "3",
                "maxReverseLevel": None,
                "quantityMin": "1",
                "quantityMax": "1",
            },
        ),
    },
)

EXPECTED_STAGE_VARIANTS = (
    {
        "rewardIndex": 12,
        "rewardId": "12",
        "acquisitionProbability": "10",
        "quantityMax": "1",
    },
    {
        "rewardIndex": 24,
        "rewardId": "24",
        "acquisitionProbability": "20",
        "quantityMax": "1",
    },
)

EXPECTED_MISSING_STAGE_NAMES = frozenset(
    ("突围", "外交-隧道据点", "同盟卸货站", "外交-黑铁阁")
)

EXPECTED_BASELINES = {
    "materialCatalog": {
        "manifestFileCount": 52,
        "itemCount": 1600,
        "materialCount": 224,
    },
    "crafting": {"categoryCount": 12, "recipeCount": 282},
    "enemies": {
        "manifestFileCount": 14,
        "enemyCount": 214,
        "allDropOccurrenceCount": 219,
        "materialDropOccurrenceCount": 210,
        "materialSourceGroupCount": 119,
        "multiVariantMaterialSourceGroupCount": 70,
        "multiVariantMaterialOccurrenceCount": 161,
        "beyondFirstMaterialOccurrenceCount": 91,
    },
    "stages": {
        "manifestFolderOccurrenceCount": 19,
        "catalogEntryOccurrenceCount": 230,
        "uniqueStageCount": 212,
        "stageDataFileCount": 208,
        "allRewardOccurrenceCount": 1157,
        "materialRewardOccurrenceCount": 331,
        "materialSourceGroupCount": 330,
        "multiVariantMaterialSourceGroupCount": 1,
        "multiVariantMaterialOccurrenceCount": 2,
        "beyondFirstMaterialOccurrenceCount": 1,
    },
}


class GateFailure(Exception):
    pass


def require(condition, message):
    if not condition:
        raise GateFailure(message)


def repo_relative(file_path):
    return file_path.relative_to(REPOSITORY_ROOT).as_posix()


def resolve_under(root, relative_path, context):
    relative = str(relative_path).strip()
    require(relative, f"{context}: empty manifest entry")
    resolved = (root / relative).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError as error:
        raise GateFailure(f"{context}: path escapes manifest root: {relative}") from error
    return resolved


def parse_xml(file_path):
    try:
        return ET.parse(file_path).getroot()
    except (OSError, ET.ParseError) as error:
        raise GateFailure(f"cannot parse {repo_relative(file_path)}: {error}") from error


def element_text(element, context):
    require(len(element) == 0, f"{context}: nested content in scalar <{element.tag}>")
    value = (element.text or "").strip()
    require(value, f"{context}: empty <{element.tag}>")
    return value


def optional_child_text(parent, tag, context):
    matches = parent.findall(tag)
    require(len(matches) <= 1, f"{context}: duplicate <{tag}>")
    if not matches:
        return None
    require(len(matches[0]) == 0, f"{context}: nested content in scalar <{tag}>")
    value = (matches[0].text or "").strip()
    return value or None


def required_child_text(parent, tag, context):
    value = optional_child_text(parent, tag, context)
    require(value is not None, f"{context}: missing or empty <{tag}>")
    return value


def manifest_values(file_path, tag, allow_duplicates=False):
    root = parse_xml(file_path)
    values = [element_text(node, repo_relative(file_path)) for node in root.findall(tag)]
    require(values, f"{repo_relative(file_path)}: no <{tag}> entries")
    if not allow_duplicates:
        require(
            len(values) == len(set(values)),
            f"{repo_relative(file_path)}: duplicate <{tag}> entry",
        )
    return values


def read_json(file_path):
    try:
        return json.loads(file_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as error:
        raise GateFailure(f"cannot parse {repo_relative(file_path)}: {error}") from error


def assert_baseline(section, actual):
    expected = EXPECTED_BASELINES[section]
    for key, expected_value in expected.items():
        actual_value = actual.get(key)
        require(
            actual_value == expected_value,
            f"{section}.{key}: expected current baseline {expected_value}, found {actual_value}",
        )


def load_material_catalog():
    manifest = ITEMS_ROOT / "list.xml"
    files = manifest_values(manifest, "items")
    material_names = set()
    item_count = 0

    for relative_path in files:
        file_path = resolve_under(ITEMS_ROOT, relative_path, repo_relative(manifest))
        root = parse_xml(file_path)
        for item_index, item in enumerate(root.findall("item")):
            context = f"{repo_relative(file_path)} item[{item_index}]"
            item_name = required_child_text(item, "name", context)
            item_count += 1
            if optional_child_text(item, "use", context) != "材料":
                continue
            require(
                item_name not in material_names,
                f"{context}: duplicate material identity {item_name}",
            )
            material_names.add(item_name)

    summary = {
        "manifestFileCount": len(files),
        "itemCount": item_count,
        "materialCount": len(material_names),
    }
    assert_baseline("materialCatalog", summary)
    return material_names, summary


def audit_crafting(material_names):
    manifest = CRAFTING_ROOT / "list.xml"
    categories = manifest_values(manifest, "list")
    require(
        categories.count(ANDY_CATEGORY) == 1,
        f"crafting manifest must contain exactly one {ANDY_CATEGORY} category",
    )

    recipe_count = 0
    target_occurrences = []
    for category in categories:
        file_path = resolve_under(
            CRAFTING_ROOT, f"{category}.json", repo_relative(manifest)
        )
        recipes = read_json(file_path)
        require(isinstance(recipes, list), f"{repo_relative(file_path)}: expected array")
        recipe_count += len(recipes)
        if category != ANDY_CATEGORY:
            continue
        target_occurrences = [
            (recipe_index, recipe)
            for recipe_index, recipe in enumerate(recipes)
            if isinstance(recipe, dict) and recipe.get("name") == ANDY_PRODUCT
        ]

    require(
        len(target_occurrences) == len(EXPECTED_ANDY_RECIPES),
        f"{ANDY_CATEGORY}: expected three {ANDY_PRODUCT} occurrences, "
        f"found {len(target_occurrences)}",
    )

    projected = []
    for occurrence_index, ((recipe_index, recipe), expected) in enumerate(
        zip(target_occurrences, EXPECTED_ANDY_RECIPES)
    ):
        context = f"{ANDY_CATEGORY} recipe[{recipe_index}]"
        require(recipe_index == expected["recipeIndex"], f"{context}: recipeIndex drift")
        materials = recipe.get("materials")
        require(isinstance(materials, list), f"{context}: materials must be an array")
        require(len(materials) == 1, f"{context}: expected one authored material")
        require(materials[0] == expected["authored"], f"{context}: material drift")
        require(expected["materialName"] in material_names, f"{context}: input is not a material")
        require(ANDY_PRODUCT in material_names, f"{context}: product is not a material")
        projected.append(
            {
                "occurrenceIndex": occurrence_index,
                "category": ANDY_CATEGORY,
                "recipeIndex": recipe_index,
                "productName": ANDY_PRODUCT,
                "materialName": expected["materialName"],
                "quantity": materials[0].rsplit("#", 1)[1],
            }
        )

    require(
        len({entry["materialName"] for entry in projected}) == 3,
        f"{ANDY_PRODUCT}: expected three distinct input materials",
    )
    summary = {
        "categoryCount": len(categories),
        "recipeCount": recipe_count,
        "andyRecipeOccurrences": projected,
    }
    assert_baseline("crafting", summary)
    return summary


def group_occurrences(occurrences, key_fields):
    groups = {}
    for occurrence in occurrences:
        key = tuple(occurrence[field] for field in key_fields)
        variants = groups.setdefault(key, [])
        occurrence["occurrenceIndex"] = len(variants)
        variants.append(occurrence)
    require(
        sum(len(variants) for variants in groups.values()) == len(occurrences),
        "occurrence grouping lost authored records",
    )
    return groups


def multi_metrics(groups):
    multi_groups = [variants for variants in groups.values() if len(variants) > 1]
    multi_occurrences = sum(len(variants) for variants in multi_groups)
    return {
        "multiVariantMaterialSourceGroupCount": len(multi_groups),
        "multiVariantMaterialOccurrenceCount": multi_occurrences,
        "beyondFirstMaterialOccurrenceCount": multi_occurrences - len(multi_groups),
    }


def audit_enemy_drops(material_names):
    manifest = ENEMY_ROOT / "list.xml"
    files = manifest_values(manifest, "items")
    enemy_types = set()
    material_occurrences = []
    enemy_count = 0
    all_drop_count = 0

    for relative_path in files:
        file_path = resolve_under(ENEMY_ROOT, relative_path, repo_relative(manifest))
        root = parse_xml(file_path)
        for enemy in list(root):
            if not enemy.tag.startswith("敌人-"):
                continue
            context = f"{repo_relative(file_path)} <{enemy.tag}>"
            require(enemy.tag not in enemy_types, f"{context}: duplicate enemy identity")
            enemy_types.add(enemy.tag)
            enemy_count += 1
            for drop_index, drop in enumerate(enemy.findall("掉落物")):
                drop_context = f"{context} 掉落物[{drop_index}]"
                item_name = required_child_text(drop, "名字", drop_context)
                all_drop_count += 1
                if item_name not in material_names:
                    continue
                material_occurrences.append(
                    {
                        "itemName": item_name,
                        "enemyType": enemy.tag,
                        "dropIndex": drop_index,
                        "probability": optional_child_text(drop, "概率", drop_context),
                        "minReverseLevel": optional_child_text(
                            drop, "最小逆向等级", drop_context
                        ),
                        "maxReverseLevel": optional_child_text(
                            drop, "最大逆向等级", drop_context
                        ),
                        "quantityMin": optional_child_text(drop, "最小数量", drop_context),
                        "quantityMax": optional_child_text(drop, "最大数量", drop_context),
                    }
                )

    groups = group_occurrences(material_occurrences, ("itemName", "enemyType"))
    exact_groups = []
    for expected_group in EXPECTED_TACTICAL_GRIP_GROUPS:
        enemy_type = expected_group["enemyType"]
        variants = groups.get((TACTICAL_GRIP, enemy_type), [])
        require(len(variants) == 2, f"{TACTICAL_GRIP}/{enemy_type}: expected two variants")
        for occurrence_index, (actual, expected) in enumerate(
            zip(variants, expected_group["variants"])
        ):
            require(actual["occurrenceIndex"] == occurrence_index, "enemy occurrenceIndex drift")
            for field, expected_value in expected.items():
                require(
                    actual[field] == expected_value,
                    f"{TACTICAL_GRIP}/{enemy_type}[{occurrence_index}].{field}: "
                    f"expected {expected_value}, found {actual[field]}",
                )
        exact_groups.append(
            {
                "itemName": TACTICAL_GRIP,
                "enemyType": enemy_type,
                "variants": [
                    {
                        field: variant[field]
                        for field in (
                            "occurrenceIndex",
                            "dropIndex",
                            "probability",
                            "minReverseLevel",
                            "maxReverseLevel",
                            "quantityMin",
                            "quantityMax",
                        )
                    }
                    for variant in variants
                ],
            }
        )

    tactical_groups = [
        variants for (item_name, _enemy_type), variants in groups.items()
        if item_name == TACTICAL_GRIP
    ]
    require(len(tactical_groups) == 2, f"{TACTICAL_GRIP}: expected two enemy groups")
    require(sum(map(len, tactical_groups)) == 4, f"{TACTICAL_GRIP}: expected four occurrences")

    summary = {
        "manifestFileCount": len(files),
        "enemyCount": enemy_count,
        "allDropOccurrenceCount": all_drop_count,
        "materialDropOccurrenceCount": len(material_occurrences),
        "materialSourceGroupCount": len(groups),
        **multi_metrics(groups),
        "tacticalGripRequiredGroups": exact_groups,
    }
    assert_baseline("enemies", summary)
    return summary


def load_stage_catalog():
    manifest = STAGES_ROOT / "list.xml"
    folders = manifest_values(manifest, "stages", allow_duplicates=True)
    stages = {}
    catalog_count = 0

    for folder in folders:
        list_path = resolve_under(
            STAGES_ROOT, f"{folder}/__list__.xml", repo_relative(manifest)
        )
        root = parse_xml(list_path)
        for stage_index, stage_info in enumerate(root.findall("StageInfo")):
            context = f"{repo_relative(list_path)} StageInfo[{stage_index}]"
            stage_name = required_child_text(stage_info, "Name", context)
            stage_type = required_child_text(stage_info, "Type", context)
            data_path = resolve_under(
                STAGES_ROOT, f"{folder}/{stage_name}.xml", context
            )
            if stage_name in stages:
                require(
                    stages[stage_name]["dataPath"] == data_path,
                    f"{context}: stage name resolves to multiple files",
                )
            stages[stage_name] = {
                "stageName": stage_name,
                "stageType": stage_type,
                "dataPath": data_path,
            }
            catalog_count += 1

    return folders, catalog_count, stages


def audit_stage_rewards(material_names):
    folders, catalog_count, stages = load_stage_catalog()
    missing = []
    material_occurrences = []
    stage_data_file_count = 0
    all_reward_count = 0

    for stage in stages.values():
        file_path = stage["dataPath"]
        if not file_path.is_file():
            missing.append(stage)
            continue
        root = parse_xml(file_path)
        stage_data_file_count += 1
        rewards_nodes = root.findall("Rewards")
        require(len(rewards_nodes) <= 1, f"{repo_relative(file_path)}: duplicate Rewards")
        if not rewards_nodes:
            continue
        for reward_index, reward in enumerate(rewards_nodes[0].findall("Reward")):
            context = f"{repo_relative(file_path)} Reward[{reward_index}]"
            item_name = required_child_text(reward, "Name", context)
            all_reward_count += 1
            if item_name not in material_names:
                continue
            material_occurrences.append(
                {
                    "itemName": item_name,
                    "stageName": stage["stageName"],
                    "rewardIndex": reward_index,
                    "rewardId": reward.get("id"),
                    "acquisitionProbability": optional_child_text(
                        reward, "AcquisitionProbability", context
                    ),
                    "quantityMax": optional_child_text(reward, "QuantityMax", context),
                }
            )

    missing_names = {stage["stageName"] for stage in missing}
    require(
        missing_names == EXPECTED_MISSING_STAGE_NAMES,
        "stage missing-data allowlist drift: expected "
        f"{sorted(EXPECTED_MISSING_STAGE_NAMES)}, found {sorted(missing_names)}",
    )

    groups = group_occurrences(material_occurrences, ("itemName", "stageName"))
    fixture_variants = groups.get((STAGE_FIXTURE_MATERIAL, STAGE_FIXTURE_NAME), [])
    require(
        len(fixture_variants) == 2,
        f"{STAGE_FIXTURE_NAME}/{STAGE_FIXTURE_MATERIAL}: expected two occurrences",
    )
    for occurrence_index, (actual, expected) in enumerate(
        zip(fixture_variants, EXPECTED_STAGE_VARIANTS)
    ):
        require(actual["occurrenceIndex"] == occurrence_index, "stage occurrenceIndex drift")
        for field, expected_value in expected.items():
            require(
                actual[field] == expected_value,
                f"{STAGE_FIXTURE_NAME}/{STAGE_FIXTURE_MATERIAL}[{occurrence_index}].{field}: "
                f"expected {expected_value}, found {actual[field]}",
            )

    summary = {
        "manifestFolderOccurrenceCount": len(folders),
        "catalogEntryOccurrenceCount": catalog_count,
        "uniqueStageCount": len(stages),
        "stageDataFileCount": stage_data_file_count,
        "missingStageDataFileCount": len(missing),
        "missingStageNames": sorted(missing_names),
        "allRewardOccurrenceCount": all_reward_count,
        "materialRewardOccurrenceCount": len(material_occurrences),
        "materialSourceGroupCount": len(groups),
        **multi_metrics(groups),
        "requiredDuplicateGroup": {
            "itemName": STAGE_FIXTURE_MATERIAL,
            "stageName": STAGE_FIXTURE_NAME,
            "variants": [
                {
                    field: variant[field]
                    for field in (
                        "occurrenceIndex",
                        "rewardIndex",
                        "rewardId",
                        "acquisitionProbability",
                        "quantityMax",
                    )
                }
                for variant in fixture_variants
            ],
        },
    }
    assert_baseline("stages", summary)
    return summary


def main():
    material_names, material_summary = load_material_catalog()
    summary = {
        "schema": "material-source-occurrence-authored-data.v1",
        "materialCatalog": material_summary,
        "crafting": audit_crafting(material_names),
        "enemies": audit_enemy_drops(material_names),
        "stages": audit_stage_rewards(material_names),
    }
    print("[test-material-source-occurrences] PASS")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


try:
    main()
except GateFailure as error:
    print(f"[test-material-source-occurrences] FAIL: {error}")
    raise SystemExit(1) from error
