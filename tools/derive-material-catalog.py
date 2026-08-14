#!/usr/bin/env python3
"""Derive and verify the legacy material dictionary from the authored catalog.

`derive` is the only write mode. `--check` is pure read-only verification and
compares the tracked generated artifacts byte-for-byte with an in-memory build.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape as xml_escape


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPOSITORY_ROOT / "data/dictionaries/material_catalog.xml"
DICTIONARY_PATH = REPOSITORY_ROOT / "data/dictionaries/material_dictionary.xml"
SIDECAR_PATH = REPOSITORY_ROOT / "data/dictionaries/material_dictionary.generated.json"
ITEMS_ROOT = REPOSITORY_ROOT / "data/items"
ITEM_MANIFEST_PATH = ITEMS_ROOT / "list.xml"
MODS_ROOT = ITEMS_ROOT / "equipment_mods"
MOD_MANIFEST_PATH = MODS_ROOT / "list.xml"
MOD_PRESENTATION_DEFAULT = "ui_presentation.xml"
FOOD_MATERIAL_FILE = "消耗品_材料_食材.xml"
CRAFTING_MANIFEST_PATH = REPOSITORY_ROOT / "data/crafting/list.xml"
EQUIPMENT_CONFIG_PATH = REPOSITORY_ROOT / "data/equipment/equipment_config.xml"
EQUIPMENT_TUNING_SERVICE_PATH = (
    REPOSITORY_ROOT
    / "scripts/类定义/org/flashNight/arki/item/EquipmentTuningService.as"
)
INFRASTRUCTURE_PATH = REPOSITORY_ROOT / "data/infrastructure/infrastructure.xml"
INFRASTRUCTURE_UI_PATH = (
    REPOSITORY_ROOT / "flashswf/UI/平板电脑界面/LIBRARY/基建内容整体.xml"
)

CATALOG_SCHEMA_VERSION = 1
GENERATOR_VERSION = "material-catalog-producer.v2"
SIDECAR_SCHEMA = "cf7.material-dictionary-generated.v2"
ALLOWED_TYPE_IDS = ("equipment_mod", "food", "general")
PURPOSE_EQUIPMENT_TUNING = "system:equipment_tuning"
PURPOSE_INFRASTRUCTURE_UPGRADE = "system:infrastructure_upgrade"
CONTROLLED_PURPOSES = {
    PURPOSE_EQUIPMENT_TUNING: {
        "label": "装备改装",
        "order": 0,
        "consumerEvidence": "EquipmentTuningService",
    },
    PURPOSE_INFRASTRUCTURE_UPGRADE: {
        "label": "基建升级",
        "order": 1,
        "consumerEvidence": "InfrastructureUpgradeUI",
    },
}
EQUIPMENT_TUNING_EXCEPTIONS = (
    "强化石",
    "二阶复合防御组件",
    "三阶复合防御组件",
    "四阶复合防御组件",
    "墨冰战术涂料",
    "狱火战术涂料",
)
TIER_EVIDENCE_EXCEPTIONS = EQUIPMENT_TUNING_EXCEPTIONS[1:]
SINGLE_LINE_CONTROL_RE = re.compile(r"[\x00-\x1f\x7f-\x9f]")
MULTILINE_CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")
PURPOSE_ID_RE = re.compile(r"^[a-z][a-z0-9_.:-]{0,127}$")
EVIDENCE_ID_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.:-]{0,127}$")
MAX_SAFE_INTEGER = 9007199254740991
MAX_MATERIALS = 4096
MAX_DIRECT_PURPOSES_PER_MATERIAL = 128
MAX_TAXONOMY_ENTRIES = 1024
TAXONOMY_FIXED_ENTRY_COUNT = 25


class GateFailure(RuntimeError):
    """Raised when an authored or generated material contract is invalid."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise GateFailure(message)


def repo_relative(path: Path) -> str:
    return path.resolve().relative_to(REPOSITORY_ROOT.resolve()).as_posix()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def parse_xml_bytes(value: bytes, context: str) -> ET.Element:
    try:
        return ET.fromstring(value)
    except ET.ParseError as error:
        raise GateFailure(f"{context}: XML parse failed: {error}") from error


def read_bytes(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError as error:
        raise GateFailure(f"cannot read {repo_relative(path)}: {error}") from error


def read_xml(path: Path) -> tuple[bytes, ET.Element]:
    value = read_bytes(path)
    return value, parse_xml_bytes(value, repo_relative(path))


def reject_attributes(element: ET.Element, context: str) -> None:
    require(not element.attrib, f"{context}: attributes are not allowed")


def scalar_text(element: ET.Element, context: str, *, preserve: bool = False) -> str:
    reject_attributes(element, context)
    require(len(element) == 0, f"{context}: nested scalar content is not allowed")
    value = element.text or ""
    require(value.strip(), f"{context}: value must not be empty")
    if preserve:
        require(
            MULTILINE_CONTROL_RE.search(value) is None,
            f"{context}: control characters other than tab/newline are not allowed",
        )
        return value
    require(
        SINGLE_LINE_CONTROL_RE.search(value) is None,
        f"{context}: control characters are not allowed",
    )
    result = value.strip()
    require(result.lower() != "undefined", f"{context}: undefined sentinel is not allowed")
    return result


def utf16_units(value: str) -> int:
    return len(value.encode("utf-16-le")) // 2


def require_identity(value: str, maximum: int, context: str) -> None:
    length = utf16_units(value)
    require(1 <= length <= maximum, f"{context}: identity length must be 1..{maximum} UTF-16 units")
    require(value.strip(), f"{context}: identity must not trim empty")
    require(value.strip().lower() != "undefined", f"{context}: undefined sentinel is not allowed")
    require(SINGLE_LINE_CONTROL_RE.search(value) is None, f"{context}: control characters are not allowed")


def require_multiline(value: str, maximum: int, context: str) -> None:
    require(utf16_units(value) <= maximum,
            f"{context}: multiline length must be <= {maximum} UTF-16 units")
    require(MULTILINE_CONTROL_RE.search(value) is None,
            f"{context}: control characters other than tab/newline are not allowed")


def exact_children(
    element: ET.Element,
    context: str,
    *,
    required: tuple[str, ...],
    optional: tuple[str, ...] = (),
    repeated: tuple[str, ...] = (),
) -> dict[str, list[ET.Element]]:
    reject_attributes(element, context)
    allowed = set(required) | set(optional) | set(repeated)
    grouped: dict[str, list[ET.Element]] = {tag: [] for tag in allowed}
    for child in element:
        require(child.tag in allowed, f"{context}: unknown <{child.tag}>")
        grouped[child.tag].append(child)
    for tag in required:
        require(len(grouped[tag]) == 1, f"{context}: expected exactly one <{tag}>")
    for tag in optional:
        require(len(grouped[tag]) <= 1, f"{context}: duplicate <{tag}>")
    return grouped


def resolve_manifest_path(root: Path, relative: str, context: str) -> Path:
    require(relative, f"{context}: empty manifest path")
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError as error:
        raise GateFailure(f"{context}: path escapes manifest root: {relative}") from error
    require(candidate.is_file(), f"{context}: missing referenced file: {relative}")
    return candidate


def manifest_scalars(path: Path, tag: str) -> tuple[bytes, list[str]]:
    raw, root = read_xml(path)
    require(root.tag == "root", f"{repo_relative(path)}: root must be <root>")
    values = [
        scalar_text(child, f"{repo_relative(path)} <{tag}>[{index}]")
        for index, child in enumerate(root.findall(tag))
    ]
    require(values, f"{repo_relative(path)}: no <{tag}> entries")
    require(len(values) == len(set(values)), f"{repo_relative(path)}: duplicate <{tag}>")
    return raw, values


@dataclass(frozen=True)
class MaterialFact:
    name: str
    source_file: str
    source_file_index: int
    item_index: int
    expected_type_id: str = ""


@dataclass(frozen=True)
class PurposeRecord:
    purpose_id: str
    label: str
    order: int
    consumer_evidence: str


@dataclass(frozen=True)
class CatalogMaterial:
    name: str
    type_id: str
    legacy_visible: bool
    legacy_information: str | None
    authored_direct_purpose_ids: tuple[str, ...]


@dataclass(frozen=True)
class CatalogModel:
    purposes: tuple[PurposeRecord, ...]
    materials: tuple[CatalogMaterial, ...]


@dataclass(frozen=True)
class InputFacts:
    materials: tuple[MaterialFact, ...]
    mod_names: frozenset[str]
    crafting_categories: tuple[str, ...]
    infrastructure_material_names: frozenset[str]
    infrastructure_material_occurrence_count: int
    input_files: tuple[tuple[Path, bytes], ...]


@dataclass(frozen=True)
class BuildResult:
    catalog: CatalogModel
    facts: InputFacts
    dictionary_bytes: bytes
    sidecar_bytes: bytes
    sidecar: dict


def validate_mod_presentation(root: ET.Element, context: str) -> None:
    require(root.tag == "root", f"{context}: root must be <root>")
    grouped = exact_children(
        root,
        context,
        required=("fallbackRole",),
        repeated=("grade", "scope", "role", "tagDefault"),
    )
    expected = {
        "grade": ("low", "medium", "high", "special"),
        "scope": ("armor", "firearm", "blade", "fist", "universal", "underbarrel"),
        "role": ("firepower", "precision", "stability", "sustain", "utility", "mechanism"),
    }
    role_ids: set[str] = set()
    for kind in ("grade", "scope", "role"):
        nodes = grouped[kind]
        require(len(nodes) == len(expected[kind]), f"{context}: {kind} exact-set mismatch")
        actual_ids: list[str] = []
        for index, node in enumerate(nodes):
            required = ("id", "label")
            if kind == "grade":
                required += ("color",)
            elif kind == "role":
                required += ("symbol",)
            fields = exact_children(node, f"{context} {kind}[{index}]", required=required)
            identity = scalar_text(fields["id"][0], f"{context} {kind}[{index}]/id")
            label = scalar_text(fields["label"][0], f"{context} {kind}[{index}]/label")
            require_identity(identity, 256, f"{context} {kind}[{index}]/id")
            require_identity(label, 512, f"{context} {kind}[{index}]/label")
            actual_ids.append(identity)
            if kind == "grade":
                color = scalar_text(fields["color"][0], f"{context} grade[{index}]/color")
                require(re.fullmatch(r"#[0-9A-Fa-f]{6}", color) is not None,
                        f"{context}: invalid grade color {color}")
            elif kind == "role":
                symbol = scalar_text(fields["symbol"][0], f"{context} role[{index}]/symbol")
                require(symbol in {
                    "triangle-solid", "triangle-outline", "square-outline",
                    "circle-outline", "diamond-outline", "star-solid",
                }, f"{context}: invalid role symbol {symbol}")
                role_ids.add(identity)
        require(tuple(actual_ids) == expected[kind],
                f"{context}: {kind} physical order/exact IDs drift")
    seen_tags: set[str] = set()
    for index, node in enumerate(grouped["tagDefault"]):
        fields = exact_children(node, f"{context} tagDefault[{index}]", required=("tag", "role"))
        tag = scalar_text(fields["tag"][0], f"{context} tagDefault[{index}]/tag")
        role = scalar_text(fields["role"][0], f"{context} tagDefault[{index}]/role")
        require_identity(tag, 128, f"{context} tagDefault[{index}]/tag")
        require(tag not in seen_tags, f"{context}: duplicate tagDefault {tag}")
        require(role in role_ids, f"{context}: unknown tagDefault role {role}")
        seen_tags.add(tag)
    fallback = scalar_text(grouped["fallbackRole"][0], f"{context}/fallbackRole")
    require(fallback in role_ids, f"{context}: unknown fallbackRole {fallback}")


def load_mod_names() -> tuple[frozenset[str], list[tuple[Path, bytes]]]:
    manifest_raw, file_names = manifest_scalars(MOD_MANIFEST_PATH, "items")
    input_files: list[tuple[Path, bytes]] = [(MOD_MANIFEST_PATH, manifest_raw)]
    _, manifest_root = read_xml(MOD_MANIFEST_PATH)
    presentation_nodes = manifest_root.findall("uiPresentation")
    require(len(presentation_nodes) == 1,
            f"{repo_relative(MOD_MANIFEST_PATH)}: expected one <uiPresentation>")
    presentation_name = scalar_text(
        presentation_nodes[0], f"{repo_relative(MOD_MANIFEST_PATH)}/uiPresentation"
    )
    presentation_path = resolve_manifest_path(
        MODS_ROOT, presentation_name or MOD_PRESENTATION_DEFAULT,
        repo_relative(MOD_MANIFEST_PATH),
    )
    presentation_raw, presentation_root = read_xml(presentation_path)
    validate_mod_presentation(presentation_root, repo_relative(presentation_path))
    input_files.append((presentation_path, presentation_raw))
    names: list[str] = []
    for file_index, file_name in enumerate(file_names):
        path = resolve_manifest_path(MODS_ROOT, file_name, repo_relative(MOD_MANIFEST_PATH))
        raw, root = read_xml(path)
        input_files.append((path, raw))
        require(root.tag == "root", f"{repo_relative(path)}: root must be <root>")
        for mod_index, mod in enumerate(root.findall("mod")):
            matches = mod.findall("name")
            context = f"{repo_relative(path)} mod[{mod_index}]"
            require(len(matches) == 1, f"{context}: expected exactly one <name>")
            name = scalar_text(matches[0], f"{context}/name")
            require_identity(name, 128, f"{context}/name")
            names.append(name)
    require(len(names) == len(set(names)), "equipment mod names must be unique")
    return frozenset(names), input_files


def load_item_materials(mod_names: frozenset[str]) -> tuple[
    tuple[MaterialFact, ...], list[tuple[Path, bytes]]
]:
    manifest_raw, file_names = manifest_scalars(ITEM_MANIFEST_PATH, "items")
    input_files: list[tuple[Path, bytes]] = [(ITEM_MANIFEST_PATH, manifest_raw)]
    materials: list[MaterialFact] = []
    seen: set[str] = set()
    for file_index, file_name in enumerate(file_names):
        path = resolve_manifest_path(ITEMS_ROOT, file_name, repo_relative(ITEM_MANIFEST_PATH))
        raw, root = read_xml(path)
        input_files.append((path, raw))
        require(root.tag == "root", f"{repo_relative(path)}: root must be <root>")
        for item_index, item in enumerate(root.findall("item")):
            context = f"{repo_relative(path)} item[{item_index}]"
            name_nodes = item.findall("name")
            use_nodes = item.findall("use")
            require(len(name_nodes) == 1, f"{context}: expected exactly one <name>")
            require(len(use_nodes) <= 1, f"{context}: duplicate <use>")
            name = scalar_text(name_nodes[0], f"{context}/name")
            require_identity(name, 128, f"{context}/name")
            use = (
                scalar_text(use_nodes[0], f"{context}/use") if use_nodes else None
            )
            if use != "材料":
                continue
            require(name not in seen, f"{context}: duplicate material identity {name}")
            seen.add(name)
            if name in mod_names:
                expected_type_id = "equipment_mod"
            elif file_name == FOOD_MATERIAL_FILE:
                expected_type_id = "food"
            else:
                expected_type_id = "general"
            materials.append(
                MaterialFact(
                    name=name,
                    source_file=file_name,
                    source_file_index=file_index,
                    item_index=item_index,
                    expected_type_id=expected_type_id,
                )
            )
    require(materials, "item manifest contains no materials")
    material_names = {material.name for material in materials}
    missing_mod_items = sorted(mod_names - material_names)
    require(
        not missing_mod_items,
        "equipment mods without material items: " + ", ".join(missing_mod_items),
    )
    return tuple(materials), input_files


def validate_equipment_tuning_evidence(material_names: set[str]) -> list[tuple[Path, bytes]]:
    equipment_raw, equipment_root = read_xml(EQUIPMENT_CONFIG_PATH)
    tier_materials = {
        str(node.attrib.get("material", "")).strip()
        for node in equipment_root.findall("./EquipmentConfig/TierSystem/TierMapping")
    }
    for name in TIER_EVIDENCE_EXCEPTIONS:
        require(name in tier_materials, f"equipment tuning tier evidence missing {name}")
    service_raw = read_bytes(EQUIPMENT_TUNING_SERVICE_PATH)
    try:
        service_text = service_raw.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise GateFailure(
            f"{repo_relative(EQUIPMENT_TUNING_SERVICE_PATH)}: invalid UTF-8"
        ) from error
    require(
        'materialDeltas["强化石"]' in service_text
        and 'materialNames["强化石"]' in service_text,
        "equipment tuning enhancement evidence missing 强化石",
    )
    for name in EQUIPMENT_TUNING_EXCEPTIONS:
        require(name in material_names, f"equipment tuning exception is not a material: {name}")
    return [
        (EQUIPMENT_CONFIG_PATH, equipment_raw),
        (EQUIPMENT_TUNING_SERVICE_PATH, service_raw),
    ]


def parse_infrastructure_upgrade_materials(
    raw: bytes, material_names: set[str]
) -> tuple[frozenset[str], int]:
    context = repo_relative(INFRASTRUCTURE_PATH)
    root = parse_xml_bytes(raw, context)
    require(root.tag == "root", f"{context}: root must be <root>")
    reject_attributes(root, context)
    infrastructures = list(root)
    require(infrastructures, f"{context}: no <Infrastructure> entries")
    require(
        all(node.tag == "Infrastructure" for node in infrastructures),
        f"{context}: root may only contain <Infrastructure>",
    )

    seen_infrastructures: set[str] = set()
    required_materials: set[str] = set()
    occurrence_count = 0
    for infrastructure_index, infrastructure in enumerate(infrastructures):
        infrastructure_context = f"{context} Infrastructure[{infrastructure_index}]"
        grouped = exact_children(
            infrastructure,
            infrastructure_context,
            required=("Name",),
            repeated=("Level",),
        )
        infrastructure_name = scalar_text(
            grouped["Name"][0], f"{infrastructure_context}/Name"
        )
        require_identity(
            infrastructure_name, 128, f"{infrastructure_context}/Name"
        )
        require(
            infrastructure_name not in seen_infrastructures,
            f"{infrastructure_context}: duplicate infrastructure {infrastructure_name}",
        )
        seen_infrastructures.add(infrastructure_name)
        levels = grouped["Level"]
        require(levels, f"{infrastructure_context}: no <Level> entries")
        for level_index, level in enumerate(levels):
            level_context = f"{infrastructure_context} Level[{level_index}]"
            require(
                set(level.attrib) == {"id"},
                f"{level_context}: expected exact id attribute",
            )
            level_id = str(level.attrib["id"])
            require(
                re.fullmatch(r"0|[1-9][0-9]*", level_id) is not None
                and int(level_id) <= MAX_SAFE_INTEGER,
                f"{level_context}: invalid id",
            )
            require(
                all(
                    child.tag in {"Description", "Price", "Material", "Skill"}
                    for child in level
                ),
                f"{level_context}: unknown child",
            )
            seen_level_materials: set[str] = set()
            for material_index, material in enumerate(level.findall("Material")):
                material_context = f"{level_context} Material[{material_index}]"
                fields = exact_children(
                    material,
                    material_context,
                    required=("Name", "Value"),
                )
                name = scalar_text(fields["Name"][0], f"{material_context}/Name")
                require_identity(name, 128, f"{material_context}/Name")
                value = parse_non_negative_integer(
                    fields["Value"][0], f"{material_context}/Value"
                )
                require(value > 0, f"{material_context}: Value must be positive")
                require(
                    name in material_names,
                    f"{material_context}: unknown material {name}",
                )
                require(
                    name not in seen_level_materials,
                    f"{material_context}: duplicate material in one level {name}",
                )
                seen_level_materials.add(name)
                required_materials.add(name)
                occurrence_count += 1
    require(required_materials, f"{context}: no infrastructure material requirements")
    return frozenset(required_materials), occurrence_count


def load_infrastructure_upgrade_facts(
    material_names: set[str],
) -> tuple[frozenset[str], int, list[tuple[Path, bytes]]]:
    infrastructure_raw = read_bytes(INFRASTRUCTURE_PATH)
    required_materials, occurrence_count = parse_infrastructure_upgrade_materials(
        infrastructure_raw, material_names
    )
    ui_raw = read_bytes(INFRASTRUCTURE_UI_PATH)
    try:
        ui_text = ui_raw.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise GateFailure(
            f"{repo_relative(INFRASTRUCTURE_UI_PATH)}: invalid UTF-8"
        ) from error
    for snippet in (
        "function 生成材料需求数组()",
        "_root.getRequirementFromTask(this.材料需求数组)",
        "_root.itemSubmit(itemArr)",
    ):
        require(
            snippet in ui_text,
            f"{repo_relative(INFRASTRUCTURE_UI_PATH)}: "
            f"InfrastructureUpgradeUI evidence missing {snippet}",
        )
    return required_materials, occurrence_count, [
        (INFRASTRUCTURE_PATH, infrastructure_raw),
        (INFRASTRUCTURE_UI_PATH, ui_raw),
    ]


def load_input_facts() -> InputFacts:
    mod_names, mod_inputs = load_mod_names()
    materials, item_inputs = load_item_materials(mod_names)
    material_names = {material.name for material in materials}
    evidence_inputs = validate_equipment_tuning_evidence(material_names)
    (
        infrastructure_material_names,
        infrastructure_material_occurrence_count,
        infrastructure_inputs,
    ) = load_infrastructure_upgrade_facts(material_names)
    crafting_raw, crafting_categories = manifest_scalars(
        CRAFTING_MANIFEST_PATH, "list"
    )
    for category in crafting_categories:
        require_identity(category, 256, f"{repo_relative(CRAFTING_MANIFEST_PATH)} category")
        require_identity(
            f"recipe:{category}", 256,
            f"{repo_relative(CRAFTING_MANIFEST_PATH)} recipe-purpose id",
        )
        recipe_path = resolve_manifest_path(
            CRAFTING_MANIFEST_PATH.parent,
            f"{category}.json",
            repo_relative(CRAFTING_MANIFEST_PATH),
        )
        try:
            recipes = json.loads(read_bytes(recipe_path).decode("utf-8-sig"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise GateFailure(f"{repo_relative(recipe_path)}: invalid recipe JSON") from error
        require(isinstance(recipes, list), f"{repo_relative(recipe_path)}: expected array")
    catalog_raw = read_bytes(CATALOG_PATH)
    inputs = (
        [(CATALOG_PATH, catalog_raw)]
        + item_inputs
        + mod_inputs
        + evidence_inputs
        + infrastructure_inputs
        + [(CRAFTING_MANIFEST_PATH, crafting_raw)]
    )
    seen_paths: set[Path] = set()
    unique_inputs: list[tuple[Path, bytes]] = []
    for path, raw in inputs:
        resolved = path.resolve()
        if resolved in seen_paths:
            continue
        seen_paths.add(resolved)
        unique_inputs.append((path, raw))
    return InputFacts(
        materials=materials,
        mod_names=mod_names,
        crafting_categories=tuple(crafting_categories),
        infrastructure_material_names=infrastructure_material_names,
        infrastructure_material_occurrence_count=infrastructure_material_occurrence_count,
        input_files=tuple(unique_inputs),
    )


def parse_non_negative_integer(element: ET.Element, context: str) -> int:
    value = scalar_text(element, context)
    require(re.fullmatch(r"0|[1-9][0-9]*", value) is not None, f"{context}: invalid integer")
    result = int(value)
    require(result <= MAX_SAFE_INTEGER, f"{context}: integer exceeds JS safe range")
    return result


def parse_catalog_bytes(raw: bytes, facts: InputFacts) -> CatalogModel:
    context = repo_relative(CATALOG_PATH)
    root = parse_xml_bytes(raw, context)
    require(root.tag == "root", f"{context}: root must be <root>")
    grouped = exact_children(
        root,
        context,
        required=("schemaVersion",),
        repeated=("DirectPurpose", "Material"),
    )
    require(grouped["DirectPurpose"], f"{context}: no <DirectPurpose>")
    require(grouped["Material"], f"{context}: no <Material>")
    require(len(grouped["Material"]) <= MAX_MATERIALS,
            f"{context}: material count exceeds {MAX_MATERIALS}")
    require(
        TAXONOMY_FIXED_ENTRY_COUNT + len(facts.crafting_categories)
        + len(grouped["DirectPurpose"]) <= MAX_TAXONOMY_ENTRIES,
        f"{context}: taxonomy entry count exceeds {MAX_TAXONOMY_ENTRIES}",
    )
    schema_version = parse_non_negative_integer(
        grouped["schemaVersion"][0], f"{context}/schemaVersion"
    )
    require(
        schema_version == CATALOG_SCHEMA_VERSION,
        f"{context}: unsupported schemaVersion {schema_version}",
    )

    purposes: list[PurposeRecord] = []
    seen_purpose_ids: set[str] = set()
    seen_purpose_orders: set[int] = set()
    for index, node in enumerate(grouped["DirectPurpose"]):
        purpose_context = f"{context} DirectPurpose[{index}]"
        fields = exact_children(
            node,
            purpose_context,
            required=("id", "label", "order", "consumerEvidence"),
        )
        purpose_id = scalar_text(fields["id"][0], f"{purpose_context}/id")
        label = scalar_text(fields["label"][0], f"{purpose_context}/label")
        order = parse_non_negative_integer(fields["order"][0], f"{purpose_context}/order")
        evidence = scalar_text(
            fields["consumerEvidence"][0], f"{purpose_context}/consumerEvidence"
        )
        require_identity(purpose_id, 256, f"{purpose_context}/id")
        require_identity(label, 512, f"{purpose_context}/label")
        require_identity(evidence, 256, f"{purpose_context}/consumerEvidence")
        require(PURPOSE_ID_RE.fullmatch(purpose_id) is not None, f"{purpose_context}: invalid id")
        require(EVIDENCE_ID_RE.fullmatch(evidence) is not None, f"{purpose_context}: invalid evidence id")
        require(purpose_id not in seen_purpose_ids, f"{purpose_context}: duplicate id {purpose_id}")
        require(order not in seen_purpose_orders, f"{purpose_context}: duplicate order {order}")
        seen_purpose_ids.add(purpose_id)
        seen_purpose_orders.add(order)
        purposes.append(PurposeRecord(purpose_id, label, order, evidence))
    require(
        [purpose.order for purpose in purposes] == list(range(len(purposes))),
        f"{context}: DirectPurpose physical order/order must be continuous 0..N-1",
    )
    actual_purpose_specs = {
        purpose.purpose_id: {
            "label": purpose.label,
            "order": purpose.order,
            "consumerEvidence": purpose.consumer_evidence,
        }
        for purpose in purposes
    }
    require(
        actual_purpose_specs == CONTROLLED_PURPOSES,
        f"{context}: controlled direct-purpose registry drift",
    )

    materials: list[CatalogMaterial] = []
    seen_names: set[str] = set()
    registered_purposes = set(actual_purpose_specs)
    for index, node in enumerate(grouped["Material"]):
        material_context = f"{context} Material[{index}]"
        fields = exact_children(
            node,
            material_context,
            required=("Name", "typeId", "legacyVisible"),
            optional=("legacyInformation",),
            repeated=("authoredDirectPurposeId",),
        )
        child_tags = [child.tag for child in node]
        expected_prefix = ["Name", "typeId", "legacyVisible"]
        require(
            child_tags[:3] == expected_prefix,
            f"{material_context}: fields must begin Name/typeId/legacyVisible",
        )
        tail = child_tags[3:]
        if tail and tail[0] == "legacyInformation":
            tail = tail[1:]
        require(
            all(tag == "authoredDirectPurposeId" for tag in tail),
            f"{material_context}: authored purpose fields must be last",
        )
        name = scalar_text(fields["Name"][0], f"{material_context}/Name")
        require_identity(name, 128, f"{material_context}/Name")
        type_id = scalar_text(fields["typeId"][0], f"{material_context}/typeId")
        visible_text = scalar_text(
            fields["legacyVisible"][0], f"{material_context}/legacyVisible"
        )
        require(visible_text in ("true", "false"), f"{material_context}: invalid legacyVisible")
        legacy_visible = visible_text == "true"
        legacy_information = (
            scalar_text(
                fields["legacyInformation"][0],
                f"{material_context}/legacyInformation",
                preserve=True,
            )
            if fields["legacyInformation"]
            else None
        )
        purpose_ids = tuple(
            scalar_text(child, f"{material_context}/authoredDirectPurposeId[{purpose_index}]")
            for purpose_index, child in enumerate(fields["authoredDirectPurposeId"])
        )
        if legacy_information is not None:
            require_multiline(
                legacy_information, 20000, f"{material_context}/legacyInformation"
            )
        require(
            len(purpose_ids) <= MAX_DIRECT_PURPOSES_PER_MATERIAL,
            f"{material_context}: too many authored direct purposes",
        )
        for purpose_index, purpose_id in enumerate(purpose_ids):
            require_identity(
                purpose_id, 256,
                f"{material_context}/authoredDirectPurposeId[{purpose_index}]",
            )
        require(name not in seen_names, f"{material_context}: duplicate material {name}")
        seen_names.add(name)
        require(type_id in ALLOWED_TYPE_IDS, f"{material_context}: unknown typeId {type_id}")
        require(
            legacy_visible == (legacy_information is not None),
            f"{material_context}: legacyInformation must exist exactly when legacyVisible=true",
        )
        require(
            len(purpose_ids) == len(set(purpose_ids)),
            f"{material_context}: duplicate authoredDirectPurposeId",
        )
        for purpose_id in purpose_ids:
            require(
                purpose_id in registered_purposes,
                f"{material_context}: unknown authored direct purpose {purpose_id}",
            )
        materials.append(
            CatalogMaterial(
                name=name,
                type_id=type_id,
                legacy_visible=legacy_visible,
                legacy_information=legacy_information,
                authored_direct_purpose_ids=purpose_ids,
            )
        )

    fact_by_name = {material.name: material for material in facts.materials}
    catalog_names = [material.name for material in materials]
    missing = [material.name for material in facts.materials if material.name not in seen_names]
    unknown = [name for name in catalog_names if name not in fact_by_name]
    require(not missing, f"{context}: materials missing from catalog: {', '.join(missing)}")
    require(not unknown, f"{context}: unknown catalog materials: {', '.join(unknown)}")
    require(
        len(catalog_names) == len(facts.materials),
        f"{context}: material exact-set cardinality mismatch",
    )
    for material in materials:
        expected_type = fact_by_name[material.name].expected_type_id
        require(
            material.type_id == expected_type,
            f"{context}: {material.name} typeId expected {expected_type}, found {material.type_id}",
        )

    legacy_materials = [material for material in materials if material.legacy_visible]
    require(len(legacy_materials) == 58, f"{context}: expected 58 legacy-visible materials")
    require(
        materials[:58] == legacy_materials,
        f"{context}: legacy-visible materials must be the physical 58-item prefix",
    )
    exception_set = set(EQUIPMENT_TUNING_EXCEPTIONS)
    authored_infrastructure_names: set[str] = set()
    for material in materials:
        has_authored_tuning = PURPOSE_EQUIPMENT_TUNING in material.authored_direct_purpose_ids
        require(
            has_authored_tuning == (material.name in exception_set),
            f"{context}: {material.name} equipment-tuning authored exception mismatch",
        )
        if PURPOSE_INFRASTRUCTURE_UPGRADE in material.authored_direct_purpose_ids:
            authored_infrastructure_names.add(material.name)
        if material.name in facts.mod_names:
            require(
                PURPOSE_EQUIPMENT_TUNING
                not in material.authored_direct_purpose_ids,
                f"{context}: machine-derived mod {material.name} must not duplicate "
                "authored equipment-tuning purpose",
            )
    missing_infrastructure = sorted(
        facts.infrastructure_material_names - authored_infrastructure_names
    )
    extra_infrastructure = sorted(
        authored_infrastructure_names - facts.infrastructure_material_names
    )
    require(
        not missing_infrastructure and not extra_infrastructure,
        f"{context}: infrastructure-upgrade authored purpose mismatch; "
        f"missing={','.join(missing_infrastructure) or '-'}; "
        f"extra={','.join(extra_infrastructure) or '-'}",
    )
    return CatalogModel(tuple(purposes), tuple(materials))


def render_dictionary(catalog: CatalogModel) -> bytes:
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', "<root>"]
    for material in catalog.materials:
        if not material.legacy_visible:
            continue
        require(material.legacy_information is not None, f"{material.name}: missing legacy summary")
        lines.extend(
            (
                "  <Material>",
                f"    <Name>{xml_escape(material.name)}</Name>",
                f"    <Information>{xml_escape(material.legacy_information)}</Information>",
                "  </Material>",
            )
        )
    lines.append("</root>")
    # The legacy loader artifact historically has no terminal newline. Keep
    # that byte contract so the initial migration is a zero-diff projection.
    return "\n".join(lines).encode("utf-8")


def build_source_digest(input_records: list[dict[str, str]]) -> str:
    digest = hashlib.sha256()
    digest.update(b"cf7.material-catalog-inputs.v1\0")
    for record in input_records:
        digest.update(record["path"].encode("utf-8"))
        digest.update(b"\0")
        digest.update(record["sha256"].encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest().upper()


def render_sidecar(
    catalog: CatalogModel, facts: InputFacts, dictionary_bytes: bytes
) -> tuple[dict, bytes]:
    input_records = [
        {"path": repo_relative(path), "sha256": sha256_bytes(raw)}
        for path, raw in facts.input_files
    ]
    type_counts = {
        type_id: sum(1 for material in catalog.materials if material.type_id == type_id)
        for type_id in ALLOWED_TYPE_IDS
    }
    authored_reference_count = sum(
        len(material.authored_direct_purpose_ids) for material in catalog.materials
    )
    legacy_count = sum(1 for material in catalog.materials if material.legacy_visible)
    sidecar = {
        "schema": SIDECAR_SCHEMA,
        "generator": {
            "path": repo_relative(Path(__file__)),
            "version": GENERATOR_VERSION,
            "sha256": sha256_bytes(read_bytes(Path(__file__))),
        },
        "sourceDigest": build_source_digest(input_records),
        "inputs": input_records,
        "catalog": {
            "path": repo_relative(CATALOG_PATH),
            "schemaVersion": CATALOG_SCHEMA_VERSION,
            "entryCount": len(catalog.materials),
            "archiveOrderFirst": 0,
            "archiveOrderLast": len(catalog.materials) - 1,
            "typeCounts": type_counts,
            "directPurposeCount": len(catalog.purposes),
            "authoredDirectPurposeReferenceCount": authored_reference_count,
            "machineDerivedEquipmentTuningCount": len(facts.mod_names),
            "equipmentTuningDistinctCount": len(facts.mod_names)
            + len(EQUIPMENT_TUNING_EXCEPTIONS),
        },
        "crafting": {
            "manifestPath": repo_relative(CRAFTING_MANIFEST_PATH),
            "categoryCount": len(facts.crafting_categories),
            "categoryOrder": list(facts.crafting_categories),
        },
        "infrastructure": {
            "path": repo_relative(INFRASTRUCTURE_PATH),
            "consumerEvidencePath": repo_relative(INFRASTRUCTURE_UI_PATH),
            "materialOccurrenceCount": facts.infrastructure_material_occurrence_count,
            "materialCount": len(facts.infrastructure_material_names),
        },
        "legacyProjection": {
            "path": repo_relative(DICTIONARY_PATH),
            "entryCount": legacy_count,
            "sha256": sha256_bytes(dictionary_bytes),
        },
    }
    value = (
        json.dumps(sidecar, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    ).encode("utf-8")
    return sidecar, value


def build_outputs() -> BuildResult:
    facts = load_input_facts()
    catalog_raw = dict(facts.input_files)[CATALOG_PATH]
    catalog = parse_catalog_bytes(catalog_raw, facts)
    dictionary_bytes = render_dictionary(catalog)
    sidecar, sidecar_bytes = render_sidecar(catalog, facts, dictionary_bytes)
    return BuildResult(catalog, facts, dictionary_bytes, sidecar_bytes, sidecar)


def atomic_write(path: Path, value: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=f".{path.name}.", suffix=".tmp", dir=path.parent, delete=False
        ) as temporary:
            temporary.write(value)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_name = temporary.name
        os.replace(temporary_name, path)
        temporary_name = None
    finally:
        if temporary_name is not None:
            try:
                Path(temporary_name).unlink()
            except FileNotFoundError:
                pass


def derive() -> BuildResult:
    result = build_outputs()
    atomic_write(DICTIONARY_PATH, result.dictionary_bytes)
    # Manifest-last: a crash after the dictionary write leaves --check stale.
    atomic_write(SIDECAR_PATH, result.sidecar_bytes)
    return result


def check() -> BuildResult:
    first = build_outputs()
    second = build_outputs()
    require(
        first.dictionary_bytes == second.dictionary_bytes
        and first.sidecar_bytes == second.sidecar_bytes,
        "in-memory derivation is not byte-deterministic",
    )
    actual_dictionary = read_bytes(DICTIONARY_PATH)
    actual_sidecar = read_bytes(SIDECAR_PATH)
    require(
        actual_dictionary == first.dictionary_bytes,
        f"{repo_relative(DICTIONARY_PATH)} is stale; run derive explicitly",
    )
    require(
        actual_sidecar == first.sidecar_bytes,
        f"{repo_relative(SIDECAR_PATH)} is stale; run derive explicitly",
    )
    return first


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("derive",))
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify tracked outputs without writing",
    )
    args = parser.parse_args()
    if args.check == (args.command == "derive"):
        parser.error("choose exactly one of `derive` or `--check`")
    return args


def main() -> int:
    args = parse_args()
    try:
        result = check() if args.check else derive()
    except GateFailure as error:
        print(f"[material-catalog] FAIL: {error}")
        return 1
    action = "check" if args.check else "derive"
    print(
        f"[material-catalog] {action} PASS "
        f"materials={len(result.catalog.materials)} "
        f"legacy={result.sidecar['legacyProjection']['entryCount']} "
        f"purposes={len(result.catalog.purposes)} "
        f"categories={len(result.facts.crafting_categories)} "
        f"infrastructureMaterials={len(result.facts.infrastructure_material_names)} "
        f"infrastructureOccurrences={result.facts.infrastructure_material_occurrence_count} "
        f"dictionarySha256={result.sidecar['legacyProjection']['sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
