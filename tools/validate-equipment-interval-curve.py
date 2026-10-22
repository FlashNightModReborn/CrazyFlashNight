"""Read-only XML/identity checks and a numerical reference; AVM1 remains a separate gate."""
from pathlib import Path
import hashlib
import json
import math
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "data/items/equipment_mods/高等材料_枪械专用.xml"

def require(ok, label):
    if not ok:
        raise AssertionError(label)

def rounded(value):
    return math.floor(value + 0.5)

def main():
    mod = next(m for m in ET.parse(MOD).getroot().findall("mod") if m.findtext("name") == "磁稳贯穿弹")
    branches = mod.findall("stats/useSwitch/use")
    machine = next(b for b in branches if b.get("name") == "机枪,压制机枪")
    normal = next(b for b in branches if b.get("name") is None)
    require(len(branches) == 2, "exactly machine and default branches")
    require(machine.findtext("percentage/interval") == "100" and machine.find("flat") is None and machine.find("curve") is None, "machine is an independent doubled interval")
    settings = normal.find("curve/interval")
    require(normal.findtext("percentage/interval") == "20" and normal.find("flat") is None, "normal keeps percentage and retires flat penalty")
    require(settings.findtext("type") == "saturatingAdd", "explicit amplification type")
    amount, pivot = float(settings.findtext("amount")), float(settings.findtext("pivot"))
    require((amount, pivot) == (32, 48), "reviewed K=40 policy")
    require(mod.findtext("excludeBulletTypes") == "pierce" and mod.findtext("tag") == "弹药", "piercing exclusion and ammo exclusivity")
    def reference(interval):
        current = rounded(interval * 1.2)
        return rounded(current + amount / (1 + pivot / current))
    cases = {30:50, 50:78, 80:117, 140:193, 250:328, 500:630, 1500:1831}
    for interval, expected in cases.items():
        require(reference(interval) == expected, f"independent numerical anchor {interval}")
    previous = 0
    for interval in range(1, 2001):
        updated = reference(interval)
        require(interval <= updated <= 2 * interval and updated >= previous, "monotonic positive bounded interval")
        previous = updated
    profiles = 0
    for path in (ROOT / "data/items").glob("武器*.xml"):
        for item in ET.parse(path).getroot().findall("item"):
            for profile in item:
                if not profile.tag.startswith("data") or profile.find("interval") is None:
                    continue
                interval = float(profile.findtext("interval"))
                if interval > 0 and math.isfinite(interval):
                    require(reference(interval) > 0, f"positive reference for {item.findtext('name')}/{profile.tag}")
                    profiles += 1
    sources = [MOD.relative_to(ROOT).as_posix(),
        "scripts/类定义/org/flashNight/arki/item/equipment/PropertyOperators.as",
        "scripts/类定义/org/flashNight/gesh/tooltip/builder/UseSwitchStatsBuilder.as",
        "scripts/类定义/org/flashNight/arki/item/equipment/EquipmentIntervalCurveTest.as",
        "scripts/test-runners/equipment-interval-curve/TestLoader.as.template"]
    hashes = {}
    for rel in sources:
        raw = (ROOT / rel).read_bytes()
        if rel.endswith((".as", ".as.template")):
            require(raw.startswith(bytes.fromhex("efbbbf")), f"BOM {rel}")
        hashes[rel] = hashlib.sha256(raw).hexdigest()
    report = {"status":"STATIC_AND_REFERENCE_ONLY", "weaponProfiles":profiles,
        "referenceAnchors":cases, "sourceSha256":hashes,
        "head":subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(),
        "avm1Executed":False, "gameplayAccepted":False}
    output = ROOT / "tmp/secondary-pierce-20261022/static-reference.json"
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"PASS: XML branches, seven anchors, 1..2000 interval bounds, {profiles} weapon profiles, BOM and source identity. Reference only; AVM1 not executed.")

if __name__ == "__main__":
    main()
