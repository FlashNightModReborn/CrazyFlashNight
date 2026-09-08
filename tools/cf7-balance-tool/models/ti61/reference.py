"""Narrow adapter for explicitly selected mods, not a second general mod engine."""
import math
import xml.etree.ElementTree as ET


def mods_from_source(m):
    result = {}
    for file in ["高等材料_防具专用.xml", "高等材料_通用.xml", "中等材料_通用.xml", "中等材料_防具专用.xml", "中等材料_刀专用.xml", "高等材料_枪械专用.xml"]:
        for mod in ET.fromstring(m.read("data/items/equipment_mods/" + file)).findall("mod"):
            result[mod.findtext("name")] = mod
    return result


def resolve(m, name, enhancement, tier, mods, registry):
    d = m.data(name, 1, tier)
    base = dict(d)
    item_use = m.ITEMS[name].findtext("use")
    native_type = m.ITEMS[name].get("weapontype", "")
    lookup = {item_use, "use:" + item_use, native_type, "weapontype:" + native_type}
    def use_cases(mod):
        return [c for c in mod.findall("stats/useSwitch/use") if any(k in lookup for k in c.get("name", "").split(","))]
    tags = set(m.ITEMS[name].findtext("inherentTags", "").split(","))
    blocked = set(m.ITEMS[name].findtext("blockedTags", "").split(",")) - {""}
    granted_types = set(native_type.split(","))
    seen_tags = set()
    capacity = d["modslot"]
    for installed_count, mod_name in enumerate(mods):
        if installed_count >= capacity:
            raise ValueError("too many mods: " + name)
        mod = registry[mod_name]
        if item_use not in mod.findtext("use", "").split(","):
            raise ValueError("incompatible slot: " + mod_name)
        if item_use in ("手枪", "长枪") and mod.findtext("weapontype"):
            if not granted_types.intersection(mod.findtext("weapontype").split(",")):
                raise ValueError("incompatible firearm subtype: " + mod_name)
        tag = mod.findtext("tag", "")
        if tag and (tag in blocked or tag in seen_tags):
            raise ValueError("blocked or repeated mod tag: " + tag)
        seen_tags.add(tag)
        required = set(mod.findtext("requireTags", "").split(","))
        for case in use_cases(mod):
            required.update(case.findtext("requireTags", "").split(","))
        if (required - {""}) - tags:
            raise ValueError("missing dependency before install: " + mod_name)
        capacity = max(capacity, float(mod.findtext("stats/merge/modslot", str(capacity))))
        tags.update(mod.findtext("provideTags", "").split(","))
        for case in use_cases(mod):
            tags.update(case.findtext("provideTags", "").split(","))
        granted_types.update(mod.findtext("grantsWeapontype", "").split(","))
    flat, percent, merge, cap = {}, {}, {}, {}
    for mod_name in mods:
        mod = registry[mod_name]
        stats = mod.find("stats")
        if stats is None:
            continue
        operators = [op for op in stats if op.tag not in ("useSwitch", "tagSwitch")]
        for case in use_cases(mod):
            operators.extend(case)
        for case in mod.findall("stats/tagSwitch/tag"):
            if case.get("name") in tags:
                operators.extend(case)
        for operator in operators:
            if operator.tag in ("provideTags", "requireTags"):
                continue
            if operator.tag not in ("flat", "percentage", "merge", "cap"):
                raise ValueError("selected mod gained unsupported operator: " + operator.tag)
            target = {"flat": flat, "percentage": percent, "merge": merge, "cap": cap}[operator.tag]
            for el in operator:
                if len(el):
                    raise ValueError("nested operator requires runtime model review")
                value = float(el.text)
                target[el.tag] = max(target.get(el.tag, 0), value) if operator.tag == "merge" else target.get(el.tag, 0) + value
    # Existing operator order: enhancement and ordinary percentages ADD to ONE multiplier.
    for key, value in base.items():
        if isinstance(value, (int, float)) and (key in m.SCALED or key in percent):
            multiplier = (m.ENHANCE[enhancement] if key in m.SCALED else 1) + percent.get(key, 0) / 100
            d[key] = m.rint(value * multiplier)
    for key, value in flat.items():
        d[key] = d.get(key, 0) + value
    for key, value in merge.items():
        old = d.get(key, value)
        d[key] = min(old, value) if old < 0 or value < 0 else max(old, value)
    for key, value in cap.items():
        if key in base and key in d:
            if value > 0:
                d[key] = min(d[key], base[key] + value)
            elif value < 0:
                d[key] = max(d[key], base[key] + value)
        else:
            raise ValueError("absolute cap not supported by selected-model adapter")
    return d


def configured_build(m, level, variant, registry, set_id="sword_saint_armor"):
    cfg = m.PARAMS["swordSaintReference"]
    armor = [n for n, it in m.ITEMS.items() if it.findtext("setId") == set_id and (set_id != "sword_saint_armor" or n.startswith("剑圣"))]
    rows = []
    for name in armor:
        is_hand = m.ITEMS[name].findtext("use") == "手部装备"
        if set_id == "sword_saint_armor":
            mods = cfg["handVariants"][variant] if is_hand else cfg["armorMods"]
        else:
            # Current Ti/Garo defaults are ONE slot, not Sword Saint's free three slots.
            mods = ["战术背带", "纳米执行单元", "传感器"] if m.ITEMS[name].findtext("use") == "上装装备" else ["碳纤维布料"]
        rows.append((name, resolve(m, name, 13, "data_4" if set_id == "sword_saint_armor" else "data", mods, registry)))
    blade_name = "血色光剑天秤" if set_id == "titanium_type_61_armor" else cfg["phaseWeapons"][str(level)]
    blade = resolve(m, blade_name, 13, "data", cfg["bladeMods"], registry)
    rows += [(blade_name, blade), (cfg["neck"], m.data(cfg["neck"], 13))]
    if set_id == "titanium_type_61_armor":
        rows += [(n, resolve(m, n, 13, "data", m.PARAMS["titaniumWeaponMods"][n], registry))
                 for n in ["钛合金P90", "钛合金P90", "钛合金QJZ171"]]
    if any(d["level"] > level for _, d in rows):
        raise ValueError("phase weapon exceeds character level")
    total = {k: sum(d.get(k, 0) for _, d in rows) for k in m.STATS}
    hand = next(d for n, d in rows if m.ITEMS[n].findtext("use") == "手部装备")
    tier = m.ITEMS["剑圣手甲"].find(".//initParam/tier_4")
    converted = total["knifepower"] * float(tier.findtext("knifeConvertRate")) if set_id == "sword_saint_armor" else 0
    ordinary_bonus = math.floor(converted * float(tier.findtext("baseRatio")))
    burst_bonus = math.floor(converted * float(tier.findtext("burstRatio")))
    punch = m.growth(10, 150, level) + total["punch"]
    global_vamp = sum(d.get("vampirism", 0) for n, d in rows if m.ITEMS[n].findtext("use") not in ["手部装备", "刀", "长枪", "手枪"])
    return {"set": set_id, "level": level, "variant": variant,
            "items": [{"name": n, "data": d} for n, d in rows],
            "hpMax": m.growth(200, 1000, level) + total["hp"],
            "mpMax": m.growth(100, 900, level) + total["mp"],
            "defence": m.growth(10, 400, level) + total["defence"],
            "damage": total["damage"], "knifeBonus": total["knifepower"], "weight": total["weight"],
            "qjzProgress": m.clamp(-total["weight"], 0, 17) / 17 if set_id == "titanium_type_61_armor" else None,
            "evasion": total["evasion"], "toughnessBonus": total["toughness"], "dodgeVs100": m.dodge_activation(level, 100, total["evasion"]),
            "punchNormal": punch + ordinary_bonus, "punchBurst": punch + ordinary_bonus + burst_bonus,
            "knifeBonusDuringBurst": total["knifepower"] - burst_bonus,
            "bladeVampirism": global_vamp + blade.get("vampirism", 0),
            "unarmedVampirism": global_vamp + hand.get("vampirism", 0)}


def energy_build(m, resolved):
    totals = {k: sum(row["data"].get(k, 0) for row in resolved["items"]) for k in m.STATS}
    armor_damage = sum(row["data"].get("damage", 0) for row in resolved["items"]
                       if m.ITEMS[row["name"]].findtext("setId") == "titanium_type_61_armor")
    armor_hp = sum(row["data"].get("hp", 0) for row in resolved["items"]
                  if m.ITEMS[row["name"]].findtext("setId") == "titanium_type_61_armor")
    return {"set": "titanium_type_61_armor", "setPieces": 5, "level": resolved["level"], "enhancement": 13,
            "hpMax": resolved["hpMax"], "mpMax": resolved["mpMax"], "defence": resolved["defence"],
            "armorDamage": armor_damage, "armorHp": armor_hp,
            "hasBloodSword": any(row["name"] == "血色光剑天秤" for row in resolved["items"]),
            "stats": totals, "weaponData": {row["name"]: row["data"] for row in resolved["items"] if m.ITEMS[row["name"]].findtext("use") in ("长枪", "手枪")},
            "illegalItems": []}


def overflow_heal(current, maximum, amount):
    if current <= 0 or maximum <= 0 or amount <= 0:
        return 0
    first = min(amount, max(0, maximum - current))
    excess = amount - first
    cap = maximum * .5
    existing = max(0, current - maximum)
    second = (cap - existing) * (1 - math.exp(-excess / cap)) if excess > 0 and existing < cap else 0
    return math.floor(first + second)


def lifesteal_trial(m, b, contact):
    events = m.animation_inputs()["wrist"]
    hp = initial = math.floor(b["hpMax"] / 2)
    healed = 0
    damage = 0
    admitted = 0
    for frame in range(1800):
        punch = b["punchBurst"] if frame % 720 < 540 else b["punchNormal"]
        for event in events["events"]:
            if frame % events["durationFrames"] != event["frame"]:
                continue
            admitted += 1
            # Evenly omit events, not frames, to avoid animation cadence aliasing.
            if math.floor(admitted * contact) == math.floor((admitted - 1) * contact):
                continue
            # Prototype-target resistance absent: existing crush falls back to physical.
            value = math.floor((punch * event["coefficient"] * 2 + b["damage"]) * 300 / 1419)
            damage += value
            raw = math.floor(value * b["unarmedVampirism"] / 100)
            actual = overflow_heal(hp, b["hpMax"], raw)
            hp += actual
            healed += actual
    return {"variant": b["variant"], "contact": contact, "initialHp": initial, "finalHp": hp,
            "healed": healed, "alive": hp > 0, "spawnContactDamage": damage,
            "status": "wrist_only_60s_no_incoming_no_skill_animation_cost; not_full_rotation_DPS"}


def produce(m):
    m.read(str((m.HERE / "reference.py").relative_to(m.ROOT)))
    for path in ["data/crafting/武器合成.json", "data/crafting/饰品合成.json", "data/shops/npcs/Vanshuther.json",
                 "scripts/类定义/org/flashNight/arki/component/Damage/LifeStealDamageHandle.as",
                 "scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Init/BulletInitializer.as"]:
        m.read(path)
    registry = mods_from_source(m)
    builds = [configured_build(m, level, variant, registry)
              for level in [45, 50, 55, 60] for variant in m.PARAMS["swordSaintReference"]["handVariants"]]
    comparable_ti = [configured_build(m, 55, "all_defensive", registry, "titanium_type_61_armor")]
    return {"builds": builds, "tiCurrentSlots55": comparable_ti,
            "garoReference": configured_build(m, 60, "current_legal_slots", registry, "golden_knight_garo"),
            "lifestealTrials": [lifesteal_trial(m, b, contact) for b in builds if b["level"] == 55 for contact in [.5, 1.0]],
            "meaning": "Specified loadout resolved from selected mod XML; ordinary percentage joins enhancement additively. Phase blades are ordinary acquisition representatives, not exhaustive optimal proof."}
