#!/usr/bin/env python3
"""Focused contract tests for the authored material catalog producer."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
PRODUCER_PATH = REPOSITORY_ROOT / "tools/derive-material-catalog.py"
EXPECTED_LEGACY_SHA256 = "012D1415B7DA4E78F05E06D5728B1F33EF6E767A627DB35993E91A8EAEC3DDC8"
EXPECTED_ARCHIVE_ORDER_SHA256 = "4D77BEF3BADBD2635229FB5ACFE358CD7EA8DC53CBA8B5D055F6B88208D90F2E"
EXPECTED_TYPE_COUNTS = {"equipment_mod": 105, "food": 45, "general": 74}
EXPECTED_CRAFTING_CATEGORIES = (
    "铁枪会",
    "属性武器",
    "烹饪",
    "化学生产",
    "武器合成",
    "饰品合成",
    "进阶防具",
    "基础防具",
    "公社防具",
    "黑白契约",
    "插件合成",
    "大学装备",
)


def load_producer():
    spec = importlib.util.spec_from_file_location("cf7_material_catalog_producer", PRODUCER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load material catalog producer")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def expect_gate_failure(producer, label, callback, message_fragment=None):
    try:
        callback()
    except producer.GateFailure as error:
        if message_fragment is not None:
            require(
                message_fragment in str(error),
                f"{label}: expected error containing {message_fragment!r}, got {error!r}",
            )
        return
    raise AssertionError(f"{label}: expected GateFailure")


def catalog_fixture_bytes(root):
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def archive_order_digest(materials):
    digest = hashlib.sha256(b"cf7.material-archive-order.v1\0")
    for material in materials:
        digest.update(material.name.encode("utf-8"))
        digest.update(b"\0")
    return digest.hexdigest().upper()


def main():
    producer = load_producer()
    first = producer.build_outputs()
    second = producer.build_outputs()
    require(first.dictionary_bytes == second.dictionary_bytes, "dictionary derivation drift")
    require(first.sidecar_bytes == second.sidecar_bytes, "sidecar derivation drift")
    require(
        first.sidecar["schema"] == "cf7.material-dictionary-generated.v2"
        and first.sidecar["generator"]["version"]
        == "material-catalog-producer.v2",
        "material catalog sidecar/generator version drift",
    )
    require(len(first.catalog.materials) == 224, "material baseline must be 224")
    require(len(first.catalog.purposes) == 2, "direct-purpose registry must contain two entries")
    require(
        tuple(purpose.purpose_id for purpose in first.catalog.purposes)
        == (
            producer.PURPOSE_EQUIPMENT_TUNING,
            producer.PURPOSE_INFRASTRUCTURE_UPGRADE,
        ),
        "controlled direct-purpose identity/order drift",
    )
    require(
        first.facts.crafting_categories == EXPECTED_CRAFTING_CATEGORIES,
        "crafting category authored order drift",
    )
    require(
        any(
            producer.repo_relative(path)
            == "data/items/equipment_mods/ui_presentation.xml"
            for path, _ in first.facts.input_files
        ),
        "mod ui presentation is missing from generated input closure",
    )
    input_paths = {
        producer.repo_relative(path) for path, _ in first.facts.input_files
    }
    require(
        "data/infrastructure/infrastructure.xml" in input_paths,
        "infrastructure requirements are missing from generated input closure",
    )
    require(
        "flashswf/UI/平板电脑界面/LIBRARY/基建内容整体.xml" in input_paths,
        "InfrastructureUpgradeUI evidence is missing from generated input closure",
    )
    require(
        len(first.facts.infrastructure_material_names) == 21,
        "infrastructure material exact-set baseline must be 21",
    )
    require(
        first.facts.infrastructure_material_occurrence_count == 67,
        "infrastructure material occurrence baseline must be 67",
    )
    require(
        first.sidecar["infrastructure"]
        == {
            "path": "data/infrastructure/infrastructure.xml",
            "consumerEvidencePath": (
                "flashswf/UI/平板电脑界面/LIBRARY/基建内容整体.xml"
            ),
            "materialOccurrenceCount": 67,
            "materialCount": 21,
        },
        "infrastructure sidecar closure drift",
    )

    infrastructure_ui_raw = producer.read_bytes(producer.INFRASTRUCTURE_UI_PATH)
    transaction_evidence = (
        "var assetSnapshot = _root.捕获玩家物资快照()",
        "var assetTransaction = _root.开始玩家物资事务(assetContext)",
        "_root.itemSubmit(itemArr, assetContext)",
        "_root.提交玩家物资事务(assetTransaction)",
        "_root.恢复玩家物资快照(assetSnapshot)",
        "_root.结算玩家物资事务异常(assetTransaction,",
    )
    original_read_bytes = producer.read_bytes
    try:
        for snippet in transaction_evidence:
            snippet_bytes = snippet.encode("utf-8")
            require(
                snippet_bytes in infrastructure_ui_raw,
                f"production infrastructure transaction evidence missing: {snippet}",
            )

            def read_without_evidence(path: Path, missing=snippet_bytes) -> bytes:
                if path == producer.INFRASTRUCTURE_UI_PATH:
                    return infrastructure_ui_raw.replace(missing, b"")
                return original_read_bytes(path)

            producer.read_bytes = read_without_evidence
            expect_gate_failure(
                producer,
                f"missing infrastructure transaction evidence: {snippet}",
                lambda: producer.load_infrastructure_upgrade_facts(
                    {material.name for material in first.catalog.materials}
                ),
                "InfrastructureUpgradeUI evidence missing",
            )
    finally:
        producer.read_bytes = original_read_bytes

    type_counts = {
        type_id: sum(
            1 for material in first.catalog.materials if material.type_id == type_id
        )
        for type_id in producer.ALLOWED_TYPE_IDS
    }
    require(type_counts == EXPECTED_TYPE_COUNTS, f"material type counts drift: {type_counts}")
    require(
        producer.sha256_bytes(first.dictionary_bytes) == EXPECTED_LEGACY_SHA256,
        "legacy 58 summary/order bytes drift",
    )
    require(
        first.dictionary_bytes == producer.read_bytes(producer.DICTIONARY_PATH),
        "tracked legacy dictionary is stale",
    )
    require(
        first.sidecar_bytes == producer.read_bytes(producer.SIDECAR_PATH),
        "tracked generated sidecar is stale",
    )

    legacy = [material for material in first.catalog.materials if material.legacy_visible]
    require(len(legacy) == 58, "legacy-visible count drift")
    require(list(first.catalog.materials[:58]) == legacy, "legacy entries are not the prefix")
    require(
        archive_order_digest(first.catalog.materials) == EXPECTED_ARCHIVE_ORDER_SHA256,
        "authored archive-order ratchet drifted from the reviewed 58+166 migration",
    )
    authored_tuning_names = {
        material.name
        for material in first.catalog.materials
        if producer.PURPOSE_EQUIPMENT_TUNING
        in material.authored_direct_purpose_ids
    }
    require(
        authored_tuning_names == set(producer.EQUIPMENT_TUNING_EXCEPTIONS),
        "equipment-tuning exception closure drift",
    )
    require(
        not (authored_tuning_names & set(first.facts.mod_names)),
        "machine-derived mods must not duplicate authored equipment tuning",
    )
    authored_infrastructure_names = {
        material.name
        for material in first.catalog.materials
        if producer.PURPOSE_INFRASTRUCTURE_UPGRADE
        in material.authored_direct_purpose_ids
    }
    require(
        authored_infrastructure_names
        == set(first.facts.infrastructure_material_names),
        "infrastructure authored-purpose exact set drift",
    )
    require(
        len(authored_infrastructure_names & set(first.facts.mod_names)) == 18,
        "infrastructure purpose must remain valid on the 18 machine-derived mods",
    )
    require(
        sum(
            len(material.authored_direct_purpose_ids)
            for material in first.catalog.materials
        )
        == 27,
        "authored direct-purpose reference baseline must be 6+21",
    )

    before_mtimes = (
        producer.DICTIONARY_PATH.stat().st_mtime_ns,
        producer.SIDECAR_PATH.stat().st_mtime_ns,
    )
    producer.check()
    after_mtimes = (
        producer.DICTIONARY_PATH.stat().st_mtime_ns,
        producer.SIDECAR_PATH.stat().st_mtime_ns,
    )
    require(before_mtimes == after_mtimes, "--check semantics wrote generated outputs")

    catalog_raw = producer.read_bytes(producer.CATALOG_PATH)

    missing_root = ET.fromstring(catalog_raw)
    missing_root.remove(missing_root.findall("Material")[-1])
    expect_gate_failure(
        producer,
        "missing material",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(missing_root), first.facts
        ),
        "materials missing from catalog",
    )

    duplicate_root = ET.fromstring(catalog_raw)
    duplicate_root.append(copy.deepcopy(duplicate_root.findall("Material")[0]))
    expect_gate_failure(
        producer,
        "duplicate material",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(duplicate_root), first.facts
        ),
        "duplicate material",
    )

    unknown_root = ET.fromstring(catalog_raw)
    unknown_material = copy.deepcopy(unknown_root.findall("Material")[0])
    unknown_material.find("Name").text = "不存在的材料"
    unknown_root.append(unknown_material)
    expect_gate_failure(
        producer,
        "unknown material",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(unknown_root), first.facts
        ),
        "unknown catalog materials",
    )

    type_root = ET.fromstring(catalog_raw)
    type_root.findall("Material")[0].find("typeId").text = "unknown_type"
    expect_gate_failure(
        producer,
        "unknown type",
        lambda: producer.parse_catalog_bytes(catalog_fixture_bytes(type_root), first.facts),
        "unknown typeId",
    )

    c1_identity_root = ET.fromstring(catalog_raw)
    c1_identity_root.findall("Material")[0].find("Name").text += "\u0085"
    expect_gate_failure(
        producer,
        "C1 identity control",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(c1_identity_root), first.facts
        ),
        "control characters are not allowed",
    )

    c1_summary_root = ET.fromstring(catalog_raw)
    c1_summary_root.findall("Material")[0].find("legacyInformation").text += "\u0085"
    expect_gate_failure(
        producer,
        "C1 multiline control",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(c1_summary_root), first.facts
        ),
        "control characters other than tab/newline are not allowed",
    )

    summary_max_root = ET.fromstring(catalog_raw)
    summary_max_root.findall("Material")[0].find("legacyInformation").text = "摘" * 20000
    producer.parse_catalog_bytes(catalog_fixture_bytes(summary_max_root), first.facts)
    summary_over_root = ET.fromstring(catalog_raw)
    summary_over_root.findall("Material")[0].find("legacyInformation").text = "摘" * 20001
    expect_gate_failure(
        producer,
        "summary max plus one",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(summary_over_root), first.facts
        ),
        "multiline length must be <= 20000 UTF-16 units",
    )

    name_over_root = ET.fromstring(catalog_raw)
    name_over_root.findall("Material")[0].find("Name").text = "材" * 129
    expect_gate_failure(
        producer,
        "name max plus one",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(name_over_root), first.facts
        ),
        "identity length must be 1..128 UTF-16 units",
    )

    producer.require_identity("😀" * 64, 128, "fixture/astral-name")
    expect_gate_failure(
        producer,
        "astral identity max plus one code point",
        lambda: producer.require_identity("😀" * 65, 128, "fixture/astral-name"),
        "identity length must be 1..128 UTF-16 units",
    )
    producer.require_multiline("😀" * 10000, 20000, "fixture/astral-summary")
    expect_gate_failure(
        producer,
        "astral multiline max plus one code point",
        lambda: producer.require_multiline(
            "😀" * 10001, 20000, "fixture/astral-summary"
        ),
        "multiline length must be <= 20000 UTF-16 units",
    )

    undefined_root = ET.fromstring(catalog_raw)
    undefined_root.findall("Material")[0].find("Name").text = " UnDeFiNeD "
    expect_gate_failure(
        producer,
        "undefined identity sentinel",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(undefined_root), first.facts
        ),
        "undefined sentinel",
    )

    unsafe_integer = ET.fromstring("<order>9007199254740992</order>")
    expect_gate_failure(
        producer,
        "integer max plus one",
        lambda: producer.parse_non_negative_integer(unsafe_integer, "fixture/order"),
        "exceeds JS safe range",
    )
    safe_integer = ET.fromstring("<order>9007199254740991</order>")
    require(
        producer.parse_non_negative_integer(safe_integer, "fixture/order")
        == producer.MAX_SAFE_INTEGER,
        "JS safe integer boundary rejected",
    )

    purpose_root = ET.fromstring(catalog_raw)
    purpose_target = next(
        material
        for material in purpose_root.findall("Material")
        if material.find("authoredDirectPurposeId") is not None
    )
    purpose_target.find("authoredDirectPurposeId").text = "system:unknown"
    expect_gate_failure(
        producer,
        "unknown purpose",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(purpose_root), first.facts
        ),
        "unknown authored direct purpose",
    )

    missing_infrastructure_root = ET.fromstring(catalog_raw)
    missing_infrastructure_target = next(
        material
        for material in missing_infrastructure_root.findall("Material")
        if material.findtext("authoredDirectPurposeId")
        == producer.PURPOSE_INFRASTRUCTURE_UPGRADE
    )
    missing_infrastructure_target.remove(
        next(
            purpose
            for purpose in missing_infrastructure_target.findall(
                "authoredDirectPurposeId"
            )
            if purpose.text == producer.PURPOSE_INFRASTRUCTURE_UPGRADE
        )
    )
    expect_gate_failure(
        producer,
        "missing infrastructure purpose",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(missing_infrastructure_root), first.facts
        ),
        "infrastructure-upgrade authored purpose mismatch",
    )

    extra_infrastructure_root = ET.fromstring(catalog_raw)
    extra_infrastructure_target = next(
        material
        for material in extra_infrastructure_root.findall("Material")
        if material.findtext("Name")
        not in first.facts.infrastructure_material_names
    )
    ET.SubElement(
        extra_infrastructure_target, "authoredDirectPurposeId"
    ).text = producer.PURPOSE_INFRASTRUCTURE_UPGRADE
    expect_gate_failure(
        producer,
        "extra infrastructure purpose",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(extra_infrastructure_root), first.facts
        ),
        "infrastructure-upgrade authored purpose mismatch",
    )

    direct_cap_root = ET.fromstring(catalog_raw)
    direct_cap_material = direct_cap_root.findall("Material")[0]
    for _ in range(producer.MAX_DIRECT_PURPOSES_PER_MATERIAL + 1):
        ET.SubElement(direct_cap_material, "authoredDirectPurposeId").text = (
            producer.PURPOSE_EQUIPMENT_TUNING
        )
    expect_gate_failure(
        producer,
        "per-material direct purpose cap",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(direct_cap_root), first.facts
        ),
        "too many authored direct purposes",
    )

    taxonomy_cap_root = ET.fromstring(catalog_raw)
    purpose_template = copy.deepcopy(taxonomy_cap_root.findall("DirectPurpose")[0])
    current_purposes = len(taxonomy_cap_root.findall("DirectPurpose"))
    allowed_purposes = (
        producer.MAX_TAXONOMY_ENTRIES
        - producer.TAXONOMY_FIXED_ENTRY_COUNT
        - len(first.facts.crafting_categories)
    )
    for _ in range(allowed_purposes - current_purposes + 1):
        taxonomy_cap_root.append(copy.deepcopy(purpose_template))
    expect_gate_failure(
        producer,
        "taxonomy total cap",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(taxonomy_cap_root), first.facts
        ),
        "taxonomy entry count exceeds",
    )

    material_cap_root = ET.fromstring(catalog_raw)
    material_template = copy.deepcopy(material_cap_root.findall("Material")[0])
    for _ in range(
        producer.MAX_MATERIALS - len(material_cap_root.findall("Material")) + 1
    ):
        material_cap_root.append(copy.deepcopy(material_template))
    expect_gate_failure(
        producer,
        "material total cap",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(material_cap_root), first.facts
        ),
        "material count exceeds",
    )

    missing_summary_root = ET.fromstring(catalog_raw)
    first_material = missing_summary_root.findall("Material")[0]
    first_material.remove(first_material.find("legacyInformation"))
    expect_gate_failure(
        producer,
        "missing legacy summary",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(missing_summary_root), first.facts
        ),
        "legacyInformation must exist",
    )

    redundant_purpose_root = ET.fromstring(catalog_raw)
    first_mod = next(
        material
        for material in redundant_purpose_root.findall("Material")
        if material.findtext("Name") in first.facts.mod_names
    )
    ET.SubElement(first_mod, "authoredDirectPurposeId").text = (
        producer.PURPOSE_EQUIPMENT_TUNING
    )
    expect_gate_failure(
        producer,
        "redundant mod purpose",
        lambda: producer.parse_catalog_bytes(
            catalog_fixture_bytes(redundant_purpose_root), first.facts
        ),
        "equipment-tuning authored exception mismatch",
    )

    order_root = ET.fromstring(catalog_raw)
    material_nodes = order_root.findall("Material")
    first_index = list(order_root).index(material_nodes[58])
    second_index = list(order_root).index(material_nodes[59])
    first_node = copy.deepcopy(material_nodes[58])
    second_node = copy.deepcopy(material_nodes[59])
    order_root.remove(material_nodes[58])
    order_root.remove(material_nodes[59])
    order_root.insert(first_index, second_node)
    order_root.insert(second_index, first_node)
    reordered = producer.parse_catalog_bytes(catalog_fixture_bytes(order_root), first.facts)
    require(
        reordered.materials[58].name == first.catalog.materials[59].name
        and reordered.materials[59].name == first.catalog.materials[58].name,
        "authored non-legacy order must be preserved instead of re-sorted by manifest/name",
    )
    require(
        archive_order_digest(reordered.materials) != EXPECTED_ARCHIVE_ORDER_SHA256,
        "archive-order ratchet must observe authored non-legacy reordering",
    )

    print(
        "[test-material-catalog] PASS "
        f"materials={len(first.catalog.materials)} legacy={len(legacy)} "
        f"types={type_counts} mods={len(first.facts.mod_names)} "
        f"authoredExceptions={len(authored_tuning_names)} "
        f"infrastructure={len(authored_infrastructure_names)}/"
        f"{first.facts.infrastructure_material_occurrence_count} "
        f"categories={len(first.facts.crafting_categories)}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, RuntimeError) as error:
        print(f"[test-material-catalog] FAIL: {error}")
        raise SystemExit(1)
