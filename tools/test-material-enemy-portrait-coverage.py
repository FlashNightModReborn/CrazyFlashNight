#!/usr/bin/env python3
"""Offline exact-set gate for material-drop enemy portraits.

The set is derived from authored item/enemy XML on every run; no identity
count is hard-coded. Every derived ``敌人-*`` key must directly name a ready
entry in the enemy portrait manifest. Aliases, case folding, prefix removal,
and fuzzy matching are deliberately excluded.

This gate does not generate runtime rows or change discovery semantics. The
material UI may invoke EnemyPortraits only after AS2 has returned a discovered
structured source row.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
ITEM_ROOT = ROOT / "data" / "items"
ENEMY_ROOT = ROOT / "data" / "enemy_properties"
WEB_ROOT = ROOT / "launcher" / "web"
MANIFEST_PATH = WEB_ROOT / "assets" / "enemy-portraits" / "manifest.json"
SUPPORTED_SCHEMAS = {
    "cf7.team-enemy-portrait-manifest.v1",
    "cf7.enemy-portrait-manifest.v1",
}


class GateFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise GateFailure(message)


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def parse_xml(path: Path) -> ET.Element:
    try:
        return ET.parse(path).getroot()
    except (OSError, ET.ParseError) as error:
        raise GateFailure(f"cannot parse {relative(path)}: {error}") from error


def scalar(node: ET.Element | None, context: str) -> str:
    require(node is not None, f"{context}: missing scalar")
    require(len(node) == 0, f"{context}: nested scalar")
    value = (node.text or "").strip()
    require(bool(value), f"{context}: empty scalar")
    return value


def manifest_paths(root: Path, manifest: Path, tag: str) -> list[Path]:
    document = parse_xml(manifest)
    values = [scalar(node, f"{relative(manifest)} <{tag}>")
              for node in document.findall(tag)]
    require(bool(values), f"{relative(manifest)}: no <{tag}> entries")
    require(len(values) == len(set(values)),
            f"{relative(manifest)}: duplicate <{tag}> entry")
    paths: list[Path] = []
    root_resolved = root.resolve()
    for value in values:
        candidate = (root / value).resolve()
        try:
            candidate.relative_to(root_resolved)
        except ValueError as error:
            raise GateFailure(
                f"{relative(manifest)}: path escapes root: {value}") from error
        require(candidate.is_file(), f"missing authored file: {relative(candidate)}")
        paths.append(candidate)
    return paths


def material_names() -> set[str]:
    names: set[str] = set()
    for path in manifest_paths(ITEM_ROOT, ITEM_ROOT / "list.xml", "items"):
        for index, item in enumerate(parse_xml(path).findall("item")):
            context = f"{relative(path)} item[{index}]"
            name = scalar(item.find("name"), f"{context}/name")
            use_node = item.find("use")
            use = (use_node.text or "").strip() if use_node is not None else ""
            if use != "材料":
                continue
            require(name not in names, f"{context}: duplicate material identity {name}")
            names.add(name)
    require(bool(names), "authored item data yielded no materials")
    return names


def material_enemy_identities(materials: set[str]) -> tuple[set[str], int]:
    identities: set[str] = set()
    occurrences = 0
    seen_enemies: set[str] = set()
    for path in manifest_paths(ENEMY_ROOT, ENEMY_ROOT / "list.xml", "items"):
        for enemy in list(parse_xml(path)):
            if not enemy.tag.startswith("敌人-"):
                continue
            context = f"{relative(path)} <{enemy.tag}>"
            require(enemy.tag not in seen_enemies,
                    f"{context}: duplicate enemy identity")
            seen_enemies.add(enemy.tag)
            for drop_index, drop in enumerate(enemy.findall("掉落物")):
                name = scalar(drop.find("名字"),
                              f"{context}/掉落物[{drop_index}]/名字")
                if name not in materials:
                    continue
                occurrences += 1
                identities.add(enemy.tag)
    require(bool(identities), "authored enemy data yielded no material-drop identities")
    return identities, occurrences


def read_manifest() -> dict:
    try:
        value = json.loads(MANIFEST_PATH.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as error:
        raise GateFailure(f"cannot parse {relative(MANIFEST_PATH)}: {error}") from error
    require(isinstance(value, dict), "enemy portrait manifest must be an object")
    require(value.get("schema") in SUPPORTED_SCHEMAS,
            f"unsupported enemy portrait manifest schema: {value.get('schema')!r}")
    require(isinstance(value.get("entries"), dict),
            "enemy portrait manifest entries must be an object")
    return value


def accepted_default(entry: object) -> tuple[dict | None, str]:
    if not isinstance(entry, dict):
        return None, "missing_entry"
    default_variant = entry.get("defaultVariant")
    variants = entry.get("variants")
    if not isinstance(default_variant, str) or not isinstance(variants, dict):
        return None, "missing_default_variant"
    variant = variants.get(default_variant)
    if not isinstance(variant, dict) or variant.get("status") != "human_accepted":
        return None, "default_variant_not_ready"
    subject = variant.get("subject")
    if not isinstance(subject, dict):
        return None, "missing_subject"
    return subject, "ready"


def asset_path(binding: object, field: str) -> Path | None:
    if not isinstance(binding, dict):
        return None
    url = binding.get("url")
    if not isinstance(url, str) or not url.startswith("assets/enemy-portraits/subjects/"):
        return None
    candidate = (WEB_ROOT / Path(url)).resolve()
    try:
        candidate.relative_to(WEB_ROOT.resolve())
    except ValueError:
        return None
    if field == "svg" and candidate.suffix.lower() != ".svg":
        return None
    if field == "pngFallback" and candidate.suffix.lower() != ".png":
        return None
    return candidate


def audit() -> dict:
    materials = material_names()
    identities, occurrence_count = material_enemy_identities(materials)
    manifest = read_manifest()
    entries = manifest["entries"]
    ready: list[str] = []
    missing: list[dict[str, str]] = []
    checked_assets = 0

    for enemy_type in sorted(identities):
        # Direct own-key lookup is the contract: aliases/fuzzy identities do not
        # count as material archive coverage.
        if enemy_type not in entries:
            missing.append({"enemyType": enemy_type, "reason": "missing_exact_entry"})
            continue
        subject, status = accepted_default(entries[enemy_type])
        if subject is None:
            missing.append({"enemyType": enemy_type, "reason": status})
            continue
        bad_binding = None
        for field in ("svg", "pngFallback"):
            candidate = asset_path(subject.get(field), field)
            if candidate is None:
                bad_binding = f"invalid_{field}_binding"
                break
            if not candidate.is_file():
                bad_binding = f"missing_{field}_asset"
                break
            checked_assets += 1
        if bad_binding:
            missing.append({"enemyType": enemy_type, "reason": bad_binding})
            continue
        ready.append(enemy_type)

    require(len(ready) + len(missing) == len(identities),
            "portrait coverage partition mismatch")
    return {
        "schema": "cf7.material-enemy-portrait-coverage.v1",
        "source": {
            "itemManifest": relative(ITEM_ROOT / "list.xml"),
            "enemyManifest": relative(ENEMY_ROOT / "list.xml"),
            "portraitManifest": relative(MANIFEST_PATH),
        },
        "materialCount": len(materials),
        "materialDropOccurrenceCount": occurrence_count,
        "total": len(identities),
        "ready": len(ready),
        "missing": len(missing),
        "checkedAssetBindingCount": checked_assets,
        "readyEnemyTypes": ready,
        "missingEnemyTypes": missing,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args()
    result = audit()
    if arguments.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(
            "Material enemy portrait coverage: "
            f"{result['ready']}/{result['total']} ready; "
            f"{result['materialDropOccurrenceCount']} material-drop occurrences; "
            f"{result['checkedAssetBindingCount']} exact asset bindings checked."
        )
        for missing in result["missingEnemyTypes"]:
            print(
                f"ERROR: {missing['enemyType']}: {missing['reason']}",
                file=sys.stderr,
            )
    return 1 if result["missing"] else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GateFailure as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
