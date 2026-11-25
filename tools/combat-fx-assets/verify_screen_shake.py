#!/usr/bin/env python3
"""Validate data/combat_visuals/screen_shake.v1.json and audit explosion coverage.

Usage:
  python tools/combat-fx-assets/verify_screen_shake.py [--strict-coverage]
"""
from __future__ import annotations
import argparse
import json
import math
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "data/combat_visuals/screen_shake.v1.json"
LIGHT_PROFILES_PATH = ROOT / "data/combat_visuals/light_profiles.xml"

MAX_BYTES = 65536
MAX_PROFILES = 16
MAX_BINDINGS = 256
MAX_KEY_LEN = 128


def _unique_pairs(pairs):
    out = {}
    for k, v in pairs:
        if k in out:
            raise ValueError(f"Duplicate JSON key: {k}")
        out[k] = v
    return out


def _is_number(v) -> bool:
    return type(v) in (int, float) and math.isfinite(v)


def _is_int(v) -> bool:
    return type(v) is int


def verify_catalog(path: Path = CATALOG_PATH) -> dict:
    raw = path.read_bytes()
    if len(raw) > MAX_BYTES:
        raise ValueError(f"screen_shake catalog exceeds {MAX_BYTES} bytes: {len(raw)}")
    data = json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_pairs)
    if not isinstance(data, dict):
        raise ValueError("Root must be a JSON object")
    if data.get("schema") != "cf7-screen-shake.v1":
        raise ValueError(f"Unsupported schema: {data.get('schema')!r}")
    if data.get("ticksPerSecond") != 30:
        raise ValueError(f"ticksPerSecond must be 30, got {data.get('ticksPerSecond')!r}")

    max_offset = data.get("maxTotalOffsetStagePx")
    if not _is_number(max_offset) or not (0 < max_offset <= 64):
        raise ValueError(f"Invalid maxTotalOffsetStagePx: {max_offset!r}")

    profiles = data.get("profiles")
    if not isinstance(profiles, list) or not (1 <= len(profiles) <= MAX_PROFILES):
        raise ValueError(f"profiles must have 1..{MAX_PROFILES} entries")

    by_name: dict[str, int] = {}
    for idx, p in enumerate(profiles, start=1):
        if not isinstance(p, dict):
            raise ValueError(f"profile[{idx}] must be an object")
        pid = p.get("id")
        if not _is_int(pid) or pid != idx:
            raise ValueError(f"profile[{idx}] id must be contiguous {idx}, got {pid!r}")
        name = p.get("name")
        if not isinstance(name, str) or not (1 <= len(name) <= 64) or name in by_name:
            raise ValueError(f"profile[{idx}] invalid or duplicate name: {name!r}")
        prio = p.get("priority")
        if not _is_int(prio) or not (1 <= prio <= 100):
            raise ValueError(f"profile {name}: priority must be int 1..100, got {prio!r}")
        amp = p.get("amplitude")
        if not _is_number(amp) or not (0 <= amp <= 64):
            raise ValueError(f"profile {name}: amplitude must be 0..64, got {amp!r}")
        ticks = p.get("ticks")
        if not _is_int(ticks) or not (1 <= ticks <= 120):
            raise ValueError(f"profile {name}: ticks must be int 1..120, got {ticks!r}")
        freq = p.get("frequency")
        if not _is_number(freq) or not (0.5 <= freq <= 60):
            raise ValueError(f"profile {name}: frequency must be 0.5..60, got {freq!r}")
        radius = p.get("radius")
        if not _is_number(radius) or not (radius == 0 or (1 <= radius <= 100000)):
            raise ValueError(f"profile {name}: radius must be 0 or 1..100000, got {radius!r}")
        by_name[name] = pid

    bindings = data.get("bindings")
    if not isinstance(bindings, dict):
        raise ValueError("bindings must be an object")

    bullets = bindings.get("bullets")
    effects = bindings.get("effects")
    exempt = bindings.get("exemptBullets", [])
    if not isinstance(bullets, dict) or not isinstance(effects, dict):
        raise ValueError("bindings.bullets and bindings.effects must be objects")
    if not isinstance(exempt, list) or not all(isinstance(x, str) and 1 <= len(x) <= MAX_KEY_LEN for x in exempt):
        raise ValueError("bindings.exemptBullets must be a list of non-empty strings")
    if len(bullets) + len(effects) > MAX_BINDINGS:
        raise ValueError(f"Total shake bindings exceed {MAX_BINDINGS}")

    for group_name, mapping in (("bullets", bullets), ("effects", effects)):
        for key, target in mapping.items():
            if not isinstance(key, str) or not (1 <= len(key) <= MAX_KEY_LEN):
                raise ValueError(f"bindings.{group_name}: invalid key {key!r}")
            if not isinstance(target, str) or target not in by_name:
                raise ValueError(f"bindings.{group_name}[{key!r}] references unknown profile {target!r}")

    exempt_set = set(exempt)
    if len(exempt_set) != len(exempt):
        raise ValueError("bindings.exemptBullets contains duplicate entries")
    overlap = set(bullets) & exempt_set
    if overlap:
        raise ValueError(f"bindings.bullets and exemptBullets overlap: {sorted(overlap)}")

    return data


def audit_explosion_coverage(data: dict) -> list[str]:
    covered = set(data["bindings"]["bullets"]) | set(data["bindings"].get("exemptBullets", []))
    discovered: set[str] = set()

    # 1. Explosion-marked bindings in light_profiles.xml
    if LIGHT_PROFILES_PATH.is_file():
        doc = ET.fromstring(LIGHT_PROFILES_PATH.read_bytes())
        explosion_profiles = {
            el.attrib["id"]
            for el in doc.findall("./Profiles/Profile")
            if el.attrib.get("isExplosion") == "true" and "爆炸" in el.attrib["id"]
        }
        for el in doc.findall("./Bindings/Binding"):
            if el.attrib.get("kind") in ("asset", "projectile") and el.attrib.get("profile") in explosion_profiles:
                key = el.attrib.get("key", "")
                if "爆炸" in key:
                    discovered.add(key)

    # 2. Spawned bullet types with 爆炸 in scripts/data/flashswf
    proc = subprocess.run(
        ["git", "grep", "-I", "-h", "-E", r"子弹种类|<bulletType>", "--", "scripts", "data", "flashswf/arts"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="ignore",
    )
    if proc.returncode in (0, 1):
        pat_b = re.compile(r'子弹种类\s*[:=]\s*["\']([^"\']+)["\']')
        pat_x = re.compile(r"<bulletType>([^<]+)</bulletType>")
        for pat in (pat_b, pat_x):
            for m in pat.finditer(proc.stdout):
                val = m.group(1).strip()
                if "爆炸" in val:
                    discovered.add(val)

    return sorted(discovered - covered)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict-coverage", action="store_true",
                        help="Fail if any discovered *爆炸* bullet is missing from bullets/exemptBullets")
    args = parser.parse_args()

    data = verify_catalog()
    missing = audit_explosion_coverage(data)
    print(
        f"[OK] screen_shake.v1.json valid: profiles={len(data['profiles'])}, "
        f"bullets={len(data['bindings']['bullets'])}, "
        f"effects={len(data['bindings']['effects'])}, "
        f"exemptBullets={len(data['bindings'].get('exemptBullets', []))}"
    )
    if missing:
        prefix = "[FAIL]" if args.strict_coverage else "[WARN]"
        print(f"{prefix} Uncategorized *爆炸* bullets ({len(missing)}): {', '.join(missing)}")
        if args.strict_coverage:
            return 1
    else:
        print("[OK] Explosion coverage audit: 0 uncategorized *爆炸* bullets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
