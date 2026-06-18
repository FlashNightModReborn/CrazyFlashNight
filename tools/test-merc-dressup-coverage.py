#!/usr/bin/env python
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "launcher/web/assets/dressup/manifest.json"
MERCENARIES_PATH = PROJECT_ROOT / "data/merc/mercenaries.json"
HAIRSTYLE_PATH = PROJECT_ROOT / "data/items/hairstyle.xml"

SLOT_NAMES = (
    "head",
    "body",
    "hand",
    "leg",
    "foot",
    "neck",
    "primary",
    "secondary1",
    "secondary2",
    "melee",
    "grenade",
)
RENDERED_SLOTS = {
    "head",
    "body",
    "hand",
    "leg",
    "foot",
    "primary",
    "secondary1",
    "secondary2",
    "melee",
    "grenade",
}
BASIC_FALLBACK_FIELDS = {
    "身体",
    "上臂",
    "左下臂",
    "右下臂",
    "左手",
    "右手",
    "屁股",
    "左大腿",
    "右大腿",
    "小腿",
    "脚",
}

# Compatibility aliases should resolve current checked-in mercenary equipment
# without falling back to holder basic children.
ALLOWED_BASIC_FALLBACK_SKINS: set[str] = set()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def xml_text(value: str) -> str:
    return (
        value.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", '"')
        .replace("&apos;", "'")
        .replace("&amp;", "&")
    )


def parse_hair_map() -> dict[int, str]:
    xml = HAIRSTYLE_PATH.read_text(encoding="utf-8")
    result: dict[int, str] = {}
    pattern = re.compile(
        r'<Hair\s+id="(\d+)"[\s\S]*?<Identifier>([\s\S]*?)</Identifier>[\s\S]*?</Hair>'
    )
    for match in pattern.finditer(xml):
        result[int(match.group(1))] = xml_text(match.group(2).strip())
    return result


def normalize_gender(merc: dict[str, Any]) -> str:
    gender = str(merc.get("gender") or "")
    return "女" if gender in ("女", "主角-女") else "男"


def strip_item_suffix(value: Any) -> str:
    if value is None:
        return ""
    return str(value).split("#", 1)[0].strip()


def is_resolved_skin(skin: dict[str, Any] | None) -> bool:
    return bool(skin and skin.get("covered") is not False and skin.get("export"))


def main() -> None:
    manifest = read_json(MANIFEST_PATH)
    mercenaries = read_json(MERCENARIES_PATH)
    hair_map = parse_hair_map()
    items = manifest.get("items") or {}
    skin_keys = manifest.get("skinKeys") or {}

    failures: list[str] = []
    total_equips = 0
    rendered_equips = 0
    resolved_parts = 0
    fallback_parts = 0
    non_rendered_equips = 0

    for merc in mercenaries:
        gender = normalize_gender(merc)
        equipment = merc.get("equipment") or {}

        for slot in SLOT_NAMES:
            item_name = strip_item_suffix(equipment.get(slot))
            if not item_name:
                continue
            total_equips += 1
            item = items.get(item_name)
            if not item:
                failures.append(f"{merc.get('name')} {slot} missing manifest item: {item_name}")
                continue
            fields = (item.get("fieldsByGender") or {}).get(gender) or {}
            if slot not in RENDERED_SLOTS:
                non_rendered_equips += 1
                if fields:
                    failures.append(f"{merc.get('name')} {slot} unexpectedly renders fields: {item_name}")
                continue
            rendered_equips += 1
            if not fields:
                failures.append(f"{merc.get('name')} {slot} has no render fields: {item_name}")
                continue
            for field, skin_key in fields.items():
                skin = skin_keys.get(skin_key)
                if is_resolved_skin(skin):
                    resolved_parts += 1
                    continue
                if skin_key in ALLOWED_BASIC_FALLBACK_SKINS and field in BASIC_FALLBACK_FIELDS:
                    fallback_parts += 1
                    continue
                status = "missing" if not skin else "uncovered" if skin.get("covered") is False else "missing-export"
                failures.append(
                    f"{merc.get('name')} {slot} {item_name} field={field} skin={skin_key} {status}"
                )

        face = merc.get("face")
        face_key = "女变装-基本脸型" if int(face or 1) == 0 else "男变装-基本脸型"
        if not is_resolved_skin(skin_keys.get(face_key)):
            failures.append(f"{merc.get('name')} face unresolved: {face_key}")

        hair = merc.get("hair")
        hair_key = hair_map.get(int(hair)) if hair not in (None, "") else ""
        if hair_key and hair_key != "光头" and not is_resolved_skin(skin_keys.get(hair_key)):
            failures.append(f"{merc.get('name')} hair unresolved: {hair_key}")

    unresolved_allowed = sorted(ALLOWED_BASIC_FALLBACK_SKINS)
    payload = {
        "mercenaries": len(mercenaries),
        "totalEquips": total_equips,
        "renderedEquips": rendered_equips,
        "nonRenderedEquips": non_rendered_equips,
        "resolvedParts": resolved_parts,
        "basicFallbackParts": fallback_parts,
        "allowedBasicFallbackSkinKeys": unresolved_allowed,
        "failures": failures[:20],
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
