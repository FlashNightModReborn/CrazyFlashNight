"""Validate emissive lifecycle configuration in the registered item sources.

The item XML is authoritative. This checker does not generate or edit gameplay data.
"""
import argparse
import json
import math
import re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ADAPTERS = {
    "static": None, "blood": "血色光剑初始化", "vocalist": "主唱光剑初始化",
    "libra": "光剑天秤初始化", "inductor": "电感切割刃初始化",
    "lion": "光刀狮子初始化", "capricorn": "光刃摩羯初始化",
}
BODY_USES = {"头部装备", "上装装备", "手部装备", "下装装备", "脚部装备"}
PARAMS = {"group", "adapter", "radius", "energy", "color", "anchor", "channel"}


def inspect_item(item, path="fixture"):
    errors, bindings = [], []
    name = item.findtext("name", "")
    use = item.findtext("use", "")
    for life in item.iter("lifecycle"):
        count = 0
        callbacks = {n.text for n in life.iter("initRoutines")}
        for attr in life:
            init = attr.findtext("init/initRoutines")
            cycle = attr.findtext("cycle/cycleRoutines")
            if init != "装备自发光初始化" and cycle != "装备自发光周期":
                continue
            count += 1
            label = f"{path}: {name}/{attr.tag}"
            def fail(message):
                errors.append(f"{label}: {message}")
            if init != "装备自发光初始化":
                fail("emission requires its matching initializer")
            if attr.findtext("skillInteraction") != "independent" or attr.find("skill") is not None:
                fail("illumination must be independent of battle-skill ownership")
            params = attr.find("init/initParam")
            values = {} if params is None else {n.tag: (n.text or "").strip() for n in params}
            if params is None or len(values) != len(params):
                fail("missing or duplicate parameters")
            if set(values) - PARAMS:
                fail("unknown parameters: " + ",".join(sorted(set(values) - PARAMS)))
            group = values.get("group")
            adapter = values.get("adapter", "static")
            if group not in {"body", "blade"}:
                fail("group must be body or blade")
            elif group == "body" and (use not in BODY_USES or adapter != "static"):
                fail("body contributions require a body equipment slot and static adapter")
            elif group == "blade" and use != "刀":
                fail("blade contributions require use=刀")
            if group == "blade" and cycle != "装备自发光周期":
                fail("dynamic blades require the emissive cycle")
            if group == "body" and cycle not in (None, "装备自发光周期"):
                fail("body contribution has an unrelated cycle")
            if adapter not in ADAPTERS:
                fail("unknown state adapter")
            elif ADAPTERS[adapter] and ADAPTERS[adapter] not in callbacks:
                fail("state adapter has no corresponding authoritative initializer in this lifecycle")
            for key, low, high in (("radius", 1, 320), ("energy", 0, 2), ("color", 0, 0xFFFFFF)):
                try:
                    value = float(values[key])
                    if not math.isfinite(value) or not low <= value <= high or (key == "color" and value != int(value)):
                        raise ValueError()
                except (KeyError, ValueError, OverflowError):
                    fail(f"{key} is missing or outside its finite range")
            for key in ("anchor", "channel"):
                if key in values and (not values[key] or any(c in values[key] for c in ";,|\r\n")):
                    fail(f"invalid {key}")
            bindings.append({"name": name, "path": path, "group": group, "adapter": adapter, "params": values})
        if count > 1:
            errors.append(f"{path}: {name}: duplicate emissive contribution in one lifecycle")
    return errors, bindings


def scan(root=ROOT):
    errors, bindings = [], []
    bridge = (root / "scripts/类定义/org/flashNight/arki/render/EquipmentLightBridge.as").read_text(encoding="utf-8-sig")
    peak = re.search(r"radialPeak:Number\s*=\s*([0-9.]+)", bridge)
    lights = json.loads((root / "data/combat_visuals/local_lights.v1.json").read_text(encoding="utf-8-sig"))
    if not peak or float(peak.group(1)) != lights["muzzles"]["枪火"]["energy"]:
        errors.append("equipment radial peak must match the ordinary muzzle reference")
    for entry in ET.parse(root / "data/items/list.xml").getroot().findall("items"):
        path = "data/items/" + entry.text.strip()
        for item in ET.parse(root / path).getroot().findall("item"):
            found_errors, found_bindings = inspect_item(item, path)
            errors.extend(found_errors)
            bindings.extend(found_bindings)
    return errors, bindings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    errors, bindings = scan()
    result = {"valid": not errors, "bindings": len(bindings),
              "groups": {g: sum(b["group"] == g for b in bindings) for g in ("body", "blade")},
              "adapters": {a: sum(b["adapter"] == a for b in bindings) for a in ADAPTERS}, "errors": errors}
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(("PASS" if not errors else "FAIL") + " equipment emissive: " + json.dumps(result, ensure_ascii=False))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
