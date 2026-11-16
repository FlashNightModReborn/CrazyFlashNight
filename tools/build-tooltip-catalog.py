#!/usr/bin/env python3
"""Bake the read-only Tooltip v1 catalog. No equipment/installation calculation.

XML list files, not directory scans, define the inputs. Static item objects
preserve ItemUtil.getItemData's cloned enumeration view; mods retain raw order.
The AS2 projection remains authoritative for calculated values,
registered mods, tier choices, drug effects and discovered acquisition records.
Use --check after changing an input. The manifest binds both sources and output.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = "data/tooltip/tooltip-catalog.json"
MANIFEST = "data/tooltip/tooltip-catalog.manifest.json"
HTML_ENTITIES = {
    "amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'", "nbsp": " ",
    "NewLine": "\n", "copy": "©", "reg": "®", "trade": "™", "deg": "°",
    "plusmn": "±", "sup2": "²", "sup3": "³", "frac14": "¼", "frac12": "½",
    "frac34": "¾", "times": "×", "divide": "÷", "iexcl": "¡", "cent": "¢",
    "pound": "£", "curren": "¤", "yen": "¥", "brvbar": "¦", "sect": "§",
    "uml": "¨", "ordf": "ª", "laquo": "«", "not": "¬", "shy": "\u00ad", "macr": "¯",
}


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def json_bytes(value: object) -> bytes:
    # Do NOT sort nested keys: some old text rules enumerate authored properties.
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":"),
                       allow_nan=False) + "\n").encode("utf-8")


def scalar(value: str) -> object:
    """XMLParser.convertDataTypeFast's data subset; preserve empty/whitespace."""
    if value == "":
        return value
    number = value.strip()
    if number == "":
        # AVM1 Number(" ") is NaN (unlike JS), so the parser keeps the string.
        return value
    if re.fullmatch(r"[+-]?0[xX][0-9a-fA-F]+", number):
        return int(number, 16)
    if re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", number):
        parsed = float(number)
        if not math.isfinite(parsed):
            raise ValueError("Non-finite number in static Tooltip data")
        return int(parsed) if parsed.is_integer() else parsed
    if value in ("true", "True", "TRUE"):
        return True
    if value in ("false", "False", "FALSE"):
        return False
    return value


def decode_html(value: str) -> str:
    """StringUtils.decodeHTMLFast's single pass, case-sensitive entity subset."""
    def decode(match: re.Match) -> str:
        name = match[1]
        if name in HTML_ENTITIES:
            return HTML_ENTITIES[name]
        if re.fullmatch(r"#\d+", name):
            number = int(name[1:])
        elif re.fullmatch(r"#[xX][0-9a-fA-F]+", name):
            number = int(name[2:], 16)
        else:
            return match[0]
        # AVM1 String.fromCharCode consumes a UTF-16 code unit; NUL yields empty.
        code = number & 0xffff
        return chr(code) if code else ""
    return re.sub(r"&([^&;]{0,10});", decode, value)


def xml_value(node: ET.Element) -> object:
    """Restricted XMLParser projection: repeated nodes, leaf types and attrs.

    Existing XML leaf text/CDATA is exposed as text by the Flash XML loader.
    Description/MaterialDetail decode their direct text once more, as the AS2
    parser explicitly does. No CaseSwitch/eval is evaluated in a static catalog.
    """
    children = [c for c in node if isinstance(c.tag, str)]
    if not children:
        if node.text is not None and node.text.strip():
            return scalar(node.text)
        return {k: scalar(v) for k, v in node.attrib.items()} if node.attrib else ""
    result = {k: scalar(v) for k, v in node.attrib.items()}

    def append(key: str, value: object) -> None:
        if key in result:
            previous = result[key]
            if isinstance(previous, list):
                previous.append(value)
            else:
                result[key] = [previous, value]
        else:
            result[key] = value

    # XML.ignoreWhite drops whitespace-only nodes. Existing authored skill 60
    # contains a stray text node; XMLParser retains it under the null node name.
    if node.text and node.text.strip():
        append("null", scalar(node.text))
    for child in children:
        if child.tag == "CaseSwitch":
            raise ValueError("Runtime CaseSwitch cannot be baked into Tooltip catalog")
        if child.tag in ("Description", "MaterialDetail"):
            direct = (child.text or "") + "".join(c.tail or "" for c in child)
            value = decode_html(direct)
        else:
            value = xml_value(child)
        append(child.tag, value)
        if child.tail and child.tail.strip():
            append("null", scalar(child.tail))
    return result


def array(value: object) -> list:
    return value if isinstance(value, list) else [] if value is None else [value]


def item_data_view(value: object) -> object:
    """Bake getItemData -> ObjectUtil.cloneFast's object insertion-order change.

    XMLParser inserts child fields forward. AVM1 for..in walks them backward;
    cloneFast then inserts that sequence into its new object at every level.
    Arrays are copied by numeric index instead. This is representation only,
    not equipment calculation; registry mods do not pass through this clone.
    """
    if isinstance(value, dict):
        return {key: item_data_view(value[key]) for key in reversed(value)
                if not key.startswith("__")}
    if isinstance(value, list):
        return [item_data_view(child) for child in value]
    return value


def words(value: object) -> dict:
    return {part.strip(): True for part in str(value).split(",") if part.strip()}


def normalize_mod(raw: dict) -> dict:
    """Normalize display data, never choose a branch or decide installation.

    Mirrors the *representation* written by ModRegistry: percentage points to
    ratios, scalar case nodes to arrays, and explicit tag sets. Acceptance of a
    mod and matching use branches are carried by TooltipInput from AS2.
    """
    mod = copy.deepcopy(raw)
    dictionary_fields = {
        "weapontype": "weapontypeDict", "excludeWeapontype": "excludeWeapontypeDict",
        "grantsWeapontype": "grantsWeapontypeDict", "grantsUse": "grantsUseDict",
        "provideTags": "provideTagDict", "requireTags": "requireTagDict",
        "excludeBulletTypes": "excludeBulletTypeDict", "requireBulletTypes": "requireBulletTypeDict",
    }
    for source, target in dictionary_fields.items():
        if mod.get(source):
            mod[target] = words(mod[source])
    if not mod.get("detachPolicy"):
        mod["detachPolicy"] = "single"
    if mod.get("tag"):
        mod["tagValue"] = mod["tag"]

    def ratios(block: dict) -> None:
        for kind in ("percentage", "multiplier"):
            for key, value in block.get(kind, {}).items():
                if not isinstance(value, (int, float)) or isinstance(value, bool):
                    raise ValueError(f"Non-numeric {mod['name']}.{kind}.{key}")
                block[kind][key] = value * 0.01

    stats = mod.get("stats") or {}
    if not isinstance(stats, dict):
        raise ValueError(f"Invalid stats: {mod.get('name')}")
    ratios(stats)
    for kind, child_key, cases_key in (("baseSwitch", "value", "valueCases"),
                                       ("useSwitch", "use", "useCases"),
                                       ("tagSwitch", "tag", "tagCases"),
                                       ("bulletSwitch", "bullet", "bulletCases")):
        branch = stats.get(kind)
        if not branch:
            continue
        cases = array(branch.get(child_key))
        for case in cases:
            ratios(case)
            if case.get("name"):
                case["lookupDict"] = words(case["name"])
            else:
                case["_isDefault"] = True
            for source, target in (("provideTags", "provideTagDict"), ("requireTags", "requireTagDict")):
                if kind == "useSwitch" and case.get(source):
                    case[target] = words(case[source])
        # Store only the normalized view; raw aliases would duplicate large trees.
        branch.pop(child_key, None)
        branch[cases_key] = cases
        if kind == "baseSwitch" and not branch.get("path"):
            branch["path"] = "data.damagetype"
    if mod.get("skillSwitch"):
        branch = mod["skillSwitch"]
        cases = array(branch.get("use"))
        for case in cases:
            if case.get("name"):
                case["lookupDict"] = words(case["name"])
            else:
                case["_isDefault"] = True
        branch.pop("use", None)
        branch["useCases"] = cases
    return mod


class Sources:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.hashes: dict[str, str] = {}

    def read(self, rel: str) -> bytes:
        path = (self.root / rel).resolve()
        if not path.is_relative_to(self.root):
            raise ValueError(f"Catalog input escapes repository: {rel}")
        raw = path.read_bytes()
        self.hashes[path.relative_to(self.root).as_posix()] = sha256(raw)
        return raw

    def xml(self, rel: str) -> ET.Element:
        raw = self.read(rel)
        if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
            raise ValueError(f"DTD/entities are not catalog inputs: {rel}")
        return ET.fromstring(raw)

    def entries(self, directory: str, tag: str = "items") -> list[str]:
        return [str(e.text) for e in self.xml(directory + "/list.xml").findall(tag)]


def build(root: Path = ROOT) -> tuple[dict, dict]:
    sources = Sources(root)
    # Bind generator and the source contracts whose representation we bake.
    sources.read("tools/build-tooltip-catalog.py")
    for source in (
        "scripts/类定义/org/flashNight/gesh/xml/XMLParser.as",
        "scripts/类定义/org/flashNight/gesh/object/ObjectUtil.as",
        "scripts/类定义/org/flashNight/gesh/string/StringUtils.as",
        "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
        "scripts/类定义/org/flashNight/arki/item/equipment/ModRegistry.as",
    ):
        sources.read(source)
    items: dict = {}
    duplicate_items = []
    item_list = sources.xml("data/items/list.xml")
    sets_name = item_list.findtext("itemSets")
    sets = {}
    if sets_name:
        for node in sources.xml("data/items/" + sets_name).findall("set"):
            row = xml_value(node)
            sets[str(row["id"])] = row
    for entry in item_list.findall("items"):
        for node in sources.xml("data/items/" + str(entry.text)).findall("item"):
            item = xml_value(node)
            name = str(item["name"])
            # These aren't Tooltip display inputs. ID allocation remains AS2's.
            item.pop("id", None)
            item.pop("balance", None)
            if item.get("setId") in sets:
                meta = sets[item["setId"]]
                item["setName"] = meta.get("name", "")
                item["setOrder"] = meta.get("order", 0)
            if name in items:
                # ItemUtil traverses the concatenated Array with AVM1 for..in
                # (reverse index order). Its final dictionary keeps the first
                # authored occurrence. Preserve, and expose, existing duplicates.
                duplicate_items.append({"name": name, "same": items[name] == item})
                continue
            items[name] = item_data_view(item)

    mods = {}
    for entry in sources.entries("data/items/equipment_mods"):
        doc = xml_value(sources.xml("data/items/equipment_mods/" + entry))
        for raw in array(doc.get("mod")):
            raw["modGrade"] = doc.get("modGrade")
            raw["catalogScope"] = doc.get("catalogScope")
            name = str(raw["name"])
            if name in mods:
                raise ValueError(f"Duplicate mod identity: {name}")
            mods[name] = normalize_mod(raw)

    levels = []
    equipment = sources.xml("data/equipment/equipment_config.xml")
    for node in equipment.findall("EquipmentConfig/LevelStatList/Level"):
        index = int(node.attrib["index"])
        if index != len(levels):
            raise ValueError("LevelStatList must have dense explicit indices")
        levels.append(scalar(node.text or ""))

    # BootSequencer enumerates the keyed category object in AVM1 reverse order.
    # Within a category the physical array order is retained (last recipe wins).
    # This is catalog indexing only: no recipe eligibility or transaction logic.
    recipes = {}
    categories = sources.entries("data/crafting", "list")
    for category in reversed(categories):
        rows = json.loads(sources.read("data/crafting/" + category + ".json").decode("utf-8-sig"))
        for recipe in rows:
            requirements = []
            for encoded in recipe.get("materials", []):
                is_quantity = "##" in encoded
                parts = encoded.split("##" if is_quantity else "#")
                if len(parts) < 2:
                    raise ValueError(f"Malformed recipe material: {encoded}")
                req = {"name": parts[0], "value": scalar(parts[1]), "isQuantity": is_quantity}
                if len(parts) > 2 and parts[2]:
                    req["tier"] = parts[2]
                requirements.append(req)
            recipes[str(recipe["name"])] = {"materials": requirements}
    reverse: dict[str, list[str]] = {}
    for product, recipe in recipes.items():
        for name in dict.fromkeys(req["name"] for req in recipe["materials"]):
            reverse.setdefault(name, []).append(product)
    for products in reverse.values():
        products.sort(key=lambda s: s.encode("utf-16-be"))

    enemy_names = {}
    for entry in sources.entries("data/enemy_properties"):
        for node in sources.xml("data/enemy_properties/" + entry):
            if isinstance(node.tag, str):
                enemy_names[node.tag] = node.findtext("displayname") or node.tag
    magic_source = sources.read("scripts/类定义/org/flashNight/arki/component/Damage/MagicDamageTypes.as").decode("utf-8-sig")
    magic_literal = re.search(r"magicDamageTypesHash:Object\s*=\s*\{([^}]+)\}", magic_source)
    if not magic_literal:
        raise ValueError("Magic damage type source changed shape")
    magic_types = dict.fromkeys(re.findall(r"([\w\u0080-\uffff]+)\s*:\s*true", magic_literal[1]), True)
    skills = {}
    for node in sources.xml("data/skills/skills.xml").findall("Skill"):
        skill = xml_value(node)
        skills[str(skill["Name"])] = skill
    catalog = {"version": 1, "contentVersion": "sha256:" + sha256(json_bytes(sources.hashes)),
               "items": items, "mods": mods, "levelStatList": levels,
               "recipes": recipes, "recipesUsing": reverse, "obtainRecords": {},
               "enemyNames": enemy_names, "magicDamageTypes": magic_types, "skills": skills}
    output = json_bytes(catalog)
    manifest = {"version": 1, "output": OUTPUT, "outputSha256": sha256(output),
                "contentVersion": catalog["contentVersion"],
                "sourceFiles": dict(sorted(sources.hashes.items())),
                "counts": {"items": len(items), "mods": len(mods), "recipes": len(recipes),
                           "skills": len(skills), "enemyNames": len(enemy_names)},
                "bytes": len(output),
                "duplicateItems": duplicate_items,
                "evidence": "source-derived; XML/AVM1 equivalence still requires fresh Flash capture"}
    return catalog, manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    catalog, manifest = build()
    outputs = {OUTPUT: json_bytes(catalog), MANIFEST: json_bytes(manifest)}
    stale = [rel for rel, raw in outputs.items()
             if not (ROOT / rel).is_file() or (ROOT / rel).read_bytes() != raw]
    if args.check and stale:
        print("Stale Tooltip catalog: " + ", ".join(stale), file=sys.stderr)
        return 1
    if not args.check:
        for rel in stale:
            path = ROOT / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(outputs[rel])
    print(json.dumps({"ok": True, "check": args.check, "updated": len(stale),
                      "contentVersion": catalog["contentVersion"], **manifest["counts"],
                      "bytes": manifest["bytes"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
