"""Ti61 source-linked design model. Standard library only; never writes game data."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
NS = {"x": "http://ns.adobe.com/xfl/2008/"}
PARAMS = json.loads((HERE / "parameters.json").read_text(encoding="utf-8"))
SOURCES: set[str] = set()
STATS = "hp mp defence damage knifepower gunpower punch force weight evasion rout toughness".split()
SCALED = set("hp mp defence damage knifepower gunpower punch force power".split())


def validate_parameters(params):
    if params["fps"] != 30:
        raise ValueError("this model translates the 30FPS runtime; changing FPS requires formula review")
    for profile in params["profiles"].values():
        for key, value in profile.items():
            if isinstance(value, (int, float)) and (not math.isfinite(value) or value <= 0):
                raise ValueError("invalid positive model parameter: " + key)
        for key in ["pulseFrames", "ammoMaxPerSlotPulse"]:
            if profile[key] != int(profile[key]):
                raise ValueError("fractional discrete parameter: " + key)
        if not 0 < profile["ammoReserveRatio"] < 1:
            raise ValueError("invalid ammo reserve")
        if profile["overloadBasis"] not in ["missing_hp", "armor_damage"]:
            raise ValueError("unsupported overload basis")
    policy = params["policy"]
    if not 0 <= policy["switchToP90BelowMpRatio"] < policy["returnToGunAboveMpRatio"] <= 1:
        raise ValueError("invalid manual-strategy thresholds")


def read(path):
    SOURCES.add(str(path).replace("\\", "/"))
    return (ROOT / path).read_text(encoding="utf-8-sig")


def bind_runtime_profile():
    """Current numeric values come from the same authored XML that Flash loads."""
    profile = PARAMS["profiles"][PARAMS["runtimeProfile"]]
    armor = ET.fromstring(read("data/items/防具_40+级.xml"))
    chest = next(item for item in armor.findall("item")
                 if item.findtext("setId") == "titanium_type_61_armor"
                 and item.findtext("use") == "上装装备")
    parameters = chest.find("lifecycle/attr_0/init/initParam")
    for child in parameters:
        profile[child.tag] = float(child.text)
    pistols = ET.fromstring(read("data/items/武器_手枪_冲锋枪.xml"))
    p90 = next(item for item in pistols.findall("item") if item.findtext("name") == "钛合金P90")
    profile["p90MpPerShot"] = float(p90.findtext("lifecycle/attr_0/init/initParam/extraMpPerShot"))


bind_runtime_profile()
validate_parameters(PARAMS)


def rint(x):
    return math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)


def clamp(x, lo, hi):
    return max(lo, min(hi, x))


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


def load_items():
    result = {}
    for file in ["防具_20-39级.xml", "防具_40+级.xml", "武器_刀_直剑.xml",
                 "武器_手枪_冲锋枪.xml", "武器_长枪_压制机枪.xml", "武器_长枪_机枪.xml",
                 "武器_刀_长柄.xml", "武器_刀_默认.xml", "武器_刀_短兵.xml", "武器_刀_刀剑.xml", "防具_颈部装备.xml"]:
        for item in ET.fromstring(read("data/items/" + file)).findall("item"):
            name = item.findtext("name")
            if name in result:
                raise ValueError("duplicate item: " + name)
            result[name] = item
    return result


def enhancement_table():
    text = read("scripts/类定义/org/flashNight/arki/item/equipment/EquipmentConfigManager.as")
    body = re.search(r"_levelStatList:Array\s*=\s*\[([^]]+)", text).group(1)
    return [float(s) for s in re.findall(r"\d+(?:\.\d+)?", strip_comments(body))]


ITEMS = load_items()
ENHANCE = enhancement_table()


def data(name, enhancement=1, tier="data"):
    item = ITEMS[name]
    raw = {el.tag: el.text for el in item.find("data") if len(el) == 0}
    if tier != "data":
        raw.update({el.tag: el.text for el in item.find(tier) if len(el) == 0})
    if "modslot" not in raw:
        base_level = float(item.findtext("data/level"))
        raw["modslot"] = "0" if item.findtext("use") == "颈部装备" else ("3" if base_level < 12 else "2" if base_level < 30 else "1")
    out = {}
    for k, value in raw.items():
        try:
            value = float(value)
        except (ValueError, TypeError):
            pass
        if k in SCALED:
            value = rint(value * ENHANCE[enhancement])
        out[k] = value
    return out


def growth(lo, hi, level):
    return max(1, math.floor(lo + (hi - lo) * level / 59))


def build(set_id, level, enhancement, weapons=(), sword_tier="data_4", doom=False):
    names = [n for n, it in ITEMS.items() if it.findtext("setId") == set_id]
    if set_id == "sword_saint_armor":
        names = [n for n in names if n.startswith("剑圣")]
    if len(names) != 5:
        raise ValueError("expected five unique armor slots")
    if doom:
        names = [n for n in names if ITEMS[n].findtext("use") != "手部装备"] + ["末日铁拳"]
    totals = {key: 0 for key in STATS}
    armor_damage = armor_hp = 0
    illegal = []
    for name in names + list(weapons):
        tier = sword_tier if name.startswith("剑圣") else "data"
        d = data(name, enhancement, tier)
        if d["level"] > level:
            illegal.append(name)
        for key in STATS:
            totals[key] += d.get(key, 0)
        if name in names:
            armor_damage += d.get("damage", 0)
            armor_hp += d.get("hp", 0)
    return {"set": set_id, "setPieces": 5, "level": level, "enhancement": enhancement,
            "items": names + list(weapons), "illegalItems": illegal,
            "hpMax": growth(200, 1000, level) + totals["hp"],
            "mpMax": growth(100, 900, level) + totals["mp"],
            "defence": growth(10, 400, level) + totals["defence"],
            "basePunch": growth(10, 150, level) + totals["punch"],
            "armorDamage": armor_damage, "armorHp": armor_hp,
            "hasBloodSword": "血色光剑天秤" in weapons, "stats": totals}


def dodge_activation(level, enemy_level, evasion=0, hit_rate=10):
    # Real formula from DodgeHandler: this is activation of dodge SYSTEM, not pure MISS.
    rate = max(1, 10 - 8 * min(level, 60) / 59) / (1 + evasion / 100)
    index = (level * 10 / rate - enemy_level * hit_rate / 3) / 40
    return 0.5 / (1 + math.exp(-index))


def weight_speed(weight, level):
    base = 12 + math.floor(level * 0.6)
    if weight < base:
        return 1 + 0.25 * (1 - max(0, weight) / base)
    if weight <= base * 2:
        return 1
    return 1 - 0.25 * clamp((weight - base * 2) / (base * 2), 0, 1)


def armor_matrix(profile):
    rows = []
    for level in [45, 50, 55, 60]:
        for enhancement in [1, 13]:
            for set_id in ["sword_saint_armor", "titanium_type_61_armor"]:
                for blood in [False, True]:
                    b = build(set_id, level, enhancement, ["血色光剑天秤"] if blood else [])
                    if b["illegalItems"]:
                        continue
                    hp, defence = b["hpMax"], b["defence"]
                    b["hasBloodSword"] = blood
                    b["bloodHpPenalty"] = data("血色光剑天秤", enhancement)["hp"] if blood else 0
                    b["physicalEhpNoDodge"] = max(0, hp) * (defence + 300) / 300
                    b["dodgeSystemActivationVs100"] = dodge_activation(level, 100, b["stats"]["evasion"])
                    b["conditionalPureDodgeShare"] = clamp((level - b["stats"]["weight"]) / 100, 0, 1)
                    shield = profile["strengthRatio"] * max(0, hp) if set_id == "titanium_type_61_armor" else 0
                    # Sufficient shield capacity assumed for ONE ordinary segment only.
                    b["oneHitLethalPostMitigationFullShield"] = max(0, hp) + shield
                    b["oneHitLethalBypass"] = max(0, hp)
                    rows.append(b)
    return rows


def animation_inputs():
    base = "flashswf/arts/things0/LIBRARY/容器/"
    paths = {"wrist": base + "空手攻击容器/平A/空手攻击容器-腕刃1连招.xml",
             "sword": base + "兵器攻击容器/平A/兵器攻击容器-直剑1连招.xml"}
    result = {}
    for kind, path in paths.items():
        tree = ET.fromstring(read(path))
        events = []
        labels = [f for f in tree.findall(".//x:DOMFrame", NS) if f.get("name", "").endswith("连招")]
        duration = max(int(f.get("index")) + int(f.get("duration", "1")) for f in labels)
        for layer in tree.findall(".//x:DOMLayer", NS):
            for f in layer.findall("./x:frames/x:DOMFrame", NS):
                for s in f.findall(".//x:Actionscript/x:script", NS):
                    code = strip_comments(s.text or "")
                    if kind == "wrist":
                        m = re.search(r"子弹属性\.子弹威力\s*=\s*_parent\._parent\.空手攻击力\s*\*\s*([\d.]+)", code)
                        if m and "_root.子弹区域shoot传递(子弹属性)" in code:
                            events.append({"frame": int(f.get("index")), "coefficient": float(m.group(1)), "trigger": "load_once"})
                    else:
                        m = re.search(r"(?m)^子弹威力\s*=\s*_parent\.空手攻击力\s*/\s*([\d.]+)\s*\+\s*_parent\.刀属性\.power(?:\s*\*\s*([\d.]+))?\s*;", code)
                        if m:
                            events.append({"frame": int(f.get("index")), "punchDivisor": float(m.group(1)), "bladeCoefficient": float(m.group(2) or 1), "trigger": "timeline_once"})
        if not events:
            raise ValueError("unrecognized animation source: " + path)
        result[kind] = {"source": path, "durationFrames": duration, "events": events,
                        "status": "authored_spawns_not_measured_hits"}
    return result


def sword_saint_projection():
    animation = animation_inputs()
    hand = ITEMS["剑圣手甲"].find(".//initParam/tier_4")
    cfg = {el.tag: float(el.text) for el in hand}
    period = float(ITEMS["剑圣腿甲"].findtext(".//tier_4/skillCd")) / 1000
    rows = []
    for level in [45, 55, 60]:
        for enhancement in [1, 13]:
            b = build("sword_saint_armor", level, enhancement)
            knife = b["stats"]["knifepower"]
            base = math.floor(knife * cfg["knifeConvertRate"] * cfg["baseRatio"])
            burst = math.floor(knife * cfg["knifeConvertRate"] * cfg["burstRatio"])
            ordinary = b["basePunch"] + base
            powered = ordinary + burst
            duty = min(1, cfg["burstDuration"] / period)
            mean = ordinary + burst * duty
            hits = animation["wrist"]["events"]
            total_coeff = sum(e["coefficient"] for e in hits)
            seconds = animation["wrist"]["durationFrames"] / 30
            # Ten punch passive levels as a COMMON modeling fixture, not a full optimal build.
            raw = (mean * total_coeff * 2 + len(hits) * b["stats"]["damage"]) / seconds
            rows.append({"level": level, "enhancement": enhancement, "armorKnifeBonus": knife,
                         "punchNormal": ordinary, "punchBurst": powered, "punchIdealCycleMean": mean,
                         "burstSeconds": cfg["burstDuration"], "cycleSeconds": period,
                         "knifeBonusDuringBurst": knife - burst,
                         "wristAuthoredRawSpawnDps": raw,
                         "status": "common_fixture_not_full_unarmed_rotation"})
    return {"animation": animation, "rows": rows,
            "benchmarkRule": "User anchor: strongest unarmed rotation outruns sword skills; never replace it by naked wrist autoattacks. Separate burst/normal, stance dwell, skill costs, hit overlap and cancellation. No simultaneous peak sum.",
            "requiredCalibration": ["strongest unarmed rotation real hit timestamps", "knife skill rotation real hit timestamps", "neck/mod loadout", "scan target dodge state and prototype resistance", "stance and cooldown duty"]}


def gun_stats(b, name, extra_damage=0, proposed_base_power=None):
    d = dict(b.get("weaponData", {}).get(name) or data(name, b["enhancement"]))
    if proposed_base_power is not None:
        d["power"] = rint(proposed_base_power * ENHANCE[b["enhancement"]])
    bullet = (d["power"] + b["stats"]["gunpower"]) * 1.8 + 30
    crit_multiplier = 1 + d.get("criticalhit", 0) / 200
    ordinary = (bullet + b["stats"]["damage"] + extra_damage) * crit_multiplier
    frame_gap = math.ceil(d["interval"] * 30 / 1000)
    if name == "钛合金P90":
        segments = [12, 6, 1, 13, 6, 1]
        tail = 12
    else:
        segments, tail = [9, 5, 8, 10], 3
    reload_frames = sum(math.ceil(s * (100 + d["reloadPenalty"]) / 100) for s in segments) + tail
    return {"bulletPower": bullet, "ordinary": ordinary, "critMultiplier": crit_multiplier, "gap": frame_gap,
            "capacity": int(d["capacity"]), "reload": reload_frames}


def apply_boss_hit(hp, maximum, ordinary, rout, slay):
    crumble = max(0, min(math.floor(maximum * rout / 100), maximum - 1))
    maximum -= crumble
    hp -= ordinary + crumble
    if hp < maximum * slay / 100:
        hp = 0
    return hp, maximum


def isolated_ttk(b, name, rout=0, slay=0, pipeline_count=1, proposed_base_power=None):
    if b["illegalItems"]:
        raise ValueError("illegal loadout")
    gun = gun_stats(b, name, proposed_base_power=proposed_base_power)
    hp = maximum = PARAMS["boss"]["hp"]
    ratio = 300 / (PARAMS["boss"]["defence"] + 300)
    frame = 0
    shots = 0
    while hp > 0 and shots < 10000:
        shots += 1
        if name == "钛合金QJZ171":
            pipelines = PARAMS["contactAssumptions"]["qjzSettlementsAlternating"][(shots - 1) % 2]
            segment_scale = 1
        else:
            pipelines = pipeline_count
            segment_scale = PARAMS["contactAssumptions"]["m134OrdinarySegments"] / pipelines
        for _ in range(pipelines):
            hp, maximum = apply_boss_hit(hp, maximum, gun["ordinary"] * ratio * segment_scale, rout, slay)
            if hp <= 0:
                break
        if hp > 0:
            frame += gun["gap"]
            if shots % gun["capacity"] == 0:
                frame += gun["reload"]
    return {"ttk": frame / 30, "shots": shots, "rout": rout, "slay": slay,
            "pipelineAssumption": pipeline_count if name != "钛合金QJZ171" else "alternating_2_3"}


def overload(profile, b, hp, shield):
    if shield > 0 or hp <= 0:
        return 0
    missing = clamp(b["hpMax"] - hp, 0, b["hpMax"])
    if profile["overloadBasis"] == "missing_hp":
        return min(profile["overloadCoefficient"] * missing, profile["overloadCap"] * b["hpMax"])
    return b["armorDamage"] * profile["overloadCoefficient"] * (missing / b["hpMax"]) ** profile["overloadExponent"]


def shield_spec(b, p):
    if p.get("shieldBasis") == "armor_hp":
        capacity = b["armorHp"] * p["shieldArmorHpRatio"]
        return capacity, capacity, capacity / p["fullRechargeSeconds"]
    return b["hpMax"] * p["shieldRatio"], b["hpMax"] * p["strengthRatio"], b["hpMax"] * p["repairHpRatioPerSecond"]


def effective_weight(b, p, shield):
    active = b.get("set") == "titanium_type_61_armor" and b.get("setPieces") == 5 and b.get("hasBloodSword") and shield > 0
    bonus = p.get("bloodServoBonusKg", 0) if active else 0
    return b["stats"]["weight"] - bonus


class EnergyState:
    def __init__(self, b, p, mp_ratio=1, hp_ratio=1):
        self.b, self.p = b, p
        self.hp, self.mp = b["hpMax"] * hp_ratio, b["mpMax"] * mp_ratio
        self.initial_hp = self.hp
        self.initial_mp = self.mp
        self.shield = 0.0
        self.initial_shield_pending = bool(p.get("fullHpInitialShield"))
        self.initial_shield_allowed = True
        self.initial_shield_granted = 0.0
        self.maximum, self.strength, self.repair_per_second = shield_spec(b, p)
        self.paid = False
        self.generated = self.spent = self.healed = self.charged = self.absorbed = self.synthesized = 0.0
        self.startups = self.breaches = 0
        self.shot = [0, 0]
        self.hp_damage = self.self_damage = 0.0

    def hit(self, amount, bypass=False):
        absorb = 0 if bypass else min(amount, self.shield, self.strength)
        old = self.shield
        self.shield -= absorb
        self.absorbed += absorb
        damage = amount - absorb
        remaining = max(0, math.floor(self.hp - damage))
        self.hp_damage += self.hp - remaining
        self.hp = remaining
        if old > 0 and self.shield <= 0:
            self.paid = False
            self.breaches += 1

    def spend(self, cost):
        assert cost >= -1e-8 and self.mp + 1e-8 >= cost
        self.mp -= cost
        self.spent += cost

    def pistol_fire(self, slot, extra_mp=0):
        if self.hp <= 0 or self.shot[slot] >= 50:
            return False
        self.shot[slot] += 1
        base_mp = self.p["ammoMpPerRound"] if self.p.get("baseAmmoCycleEnabled") else 0
        amount = max(0, min(base_mp + extra_mp, self.b["mpMax"] - self.mp))
        self.mp += amount
        self.generated += amount
        return True

    def p90_fire(self, slot):
        return self.pistol_fire(slot, self.p["p90MpPerShot"])

    def constrain_initial_shield_to_previous_health(self, hp, maximum):
        if self.initial_shield_pending:
            self.initial_shield_allowed = self.initial_shield_allowed and (
                math.isfinite(hp) and math.isfinite(maximum) and maximum > 0 and hp >= maximum)

    def pulse(self, reloading=False):
        if self.hp <= 0:
            return
        p, b = self.p, self.b
        if self.initial_shield_pending:
            self.initial_shield_pending = False
            if self.initial_shield_allowed and self.hp >= b["hpMax"]:
                self.initial_shield_granted = self.maximum - self.shield
                self.shield = self.maximum
        dt = p["pulseFrames"] / 30
        if (self.shield <= 0 or p.get("healWhileOnline")) and self.hp < b["hpMax"]:
            requested = (p["healBaseHpRatioPerSecond"] * b["hpMax"] +
                         p["healMissingRatioPerSecond"] * (b["hpMax"] - self.hp)) * dt
            # Integer HP + charge actual increment. Final 1HP requires payment, never free.
            requested = max(1, requested)
            healed = min(b["hpMax"] - self.hp, math.floor(min(requested, self.mp / p["healMpPerPoint"])))
            self.hp += healed
            self.healed += healed
            self.spend(healed * p["healMpPerPoint"])
        if self.shield <= 0:
            if self.hp < b["hpMax"]:
                return
            if not self.paid:
                if self.mp < p["startupMp"]:
                    return
                self.spend(p["startupMp"])
                self.startups += 1
                self.paid = True
        if self.shield < self.maximum:
            delta = min(self.maximum - self.shield, self.repair_per_second * dt,
                        self.mp / p["shieldMpPerPoint"])
            self.shield += delta
            self.charged += delta
            self.spend(delta * p["shieldMpPerPoint"])
            if self.shield > 0:
                self.paid = False
            if self.shield < self.maximum or not p.get("synthesisOnNewlyFull"):
                return
        if reloading:
            return
        for slot in sorted([0, 1], key=lambda s: (-self.shot[s], s)):
            available = max(0, self.mp - b["mpMax"] * p["ammoReserveRatio"])
            n = min(self.shot[slot], math.floor((available + 1e-9) / p["ammoMpPerRound"]), p["ammoMaxPerSlotPulse"])
            self.spend(n * p["ammoMpPerRound"])
            self.shot[slot] -= n
            self.synthesized += n

    def check(self):
        assert abs(self.initial_mp + self.generated - self.spent - self.mp) < 1e-5
        assert abs(self.initial_shield_granted + self.charged - self.absorbed - self.shield) < 1e-5
        assert abs(self.initial_hp + self.healed - self.hp_damage - self.self_damage - self.hp) < 1e-5
        assert -1e-7 <= self.mp <= self.b["mpMax"] + 1e-7
        assert 0 <= self.hp and math.isfinite(self.hp)
        assert all(0 <= n <= 50 for n in self.shot)


def run_pressure(profile, pressure, contact=1.0, mp_ratio=1.0, order="hit_pulse_fire", return_mp_ratio=None, build_override=None):
    b = build_override or build("titanium_type_61_armor", 55, 13, ["血色光剑天秤", "钛合金P90", "钛合金P90", "钛合金QJZ171"])
    state = EnergyState(b, profile, mp_ratio)
    main = gun_stats(b, "钛合金QJZ171")
    p90 = gun_stats(b, "钛合金P90")
    boss_hp = boss_max = PARAMS["boss"]["hp"]
    ratio = 300 / (PARAMS["boss"]["defence"] + 300)
    mode = "qjz"
    switching_until = next_shot = reload_until = 0
    reload_weapon = None
    main_shot = qjz_fired = p90_fired = p90_frames = online_frames = switches = 0
    p90_reloaded_rounds = 0
    boss_killed_at = None
    trace = []
    for frame in range(int(PARAMS["durationSeconds"] * 30) + 1):
        # Complete reload before letting another firing attempt observe an empty magazine.
        if reload_until > 0 and frame == reload_until:
            if reload_weapon == "p90":
                p90_reloaded_rounds += sum(state.shot)
                state.shot = [0, 0]
            reload_until = 0
            reload_weapon = None

        def incoming():
            if frame >= 180 and frame <= pressure.get("lastHitFrame", math.inf) and (frame - 180) % pressure["intervalFrames"] == 0:
                state.hit(pressure["damage"], pressure["bypass"])

        def maintain():
            if frame % profile["pulseFrames"] == 0:
                state.pulse(frame < reload_until)

        if order == "hit_pulse_fire":
            incoming()
            maintain()
        else:
            maintain()
            incoming()
        if state.hp <= 0:
            break
        if frame >= switching_until and frame >= reload_until:
            desired = mode
            policy = PARAMS["policy"]
            if mode == "qjz" and state.mp < b["mpMax"] * policy["switchToP90BelowMpRatio"]:
                desired = "p90"
            threshold = policy["returnToGunAboveMpRatio"] if return_mp_ratio is None else return_mp_ratio
            if mode == "p90" and state.mp >= b["mpMax"] * threshold:
                desired = "qjz"
            if desired != mode:
                mode = desired
                switches += 1
                switching_until = frame + policy["switchFrames"]
                next_shot = max(next_shot, switching_until)
        if frame >= next_shot and frame >= reload_until and frame >= switching_until:
            extra = overload(profile, b, state.hp, state.shield)
            if mode == "qjz":
                qjz_fired += 1
                main_shot += 1
                n = PARAMS["contactAssumptions"]["qjzSettlementsAlternating"][(qjz_fired - 1) % 2]
                progress = clamp(-effective_weight(b, profile, state.shield), 0, 17) / 17 if state.shield > 0 else 0
                # Contact windows deterministic: one second periods; missed shots still cost ammo.
                hits = n if frame % 30 < round(contact * 30) else 0
                ordinary = (main["ordinary"] + extra * main["critMultiplier"]) * ratio
                for _ in range(hits):
                    boss_hp, boss_max = apply_boss_hit(boss_hp, boss_max, ordinary, 0.15 * progress, 10 * progress)
                    if boss_hp <= 0:
                        break
                next_shot = frame + main["gap"]
                if main_shot >= main["capacity"]:
                    reload_until = next_shot + main["reload"]
                    reload_weapon = "qjz"
                    main_shot = 0
            else:
                for slot in [0, 1]:
                    if state.p90_fire(slot):
                        p90_fired += 1
                        if frame % 30 < round(contact * 30):
                            boss_hp -= (p90["ordinary"] + extra * p90["critMultiplier"]) * ratio
                next_shot = frame + p90["gap"]
                if min(state.shot) >= 50:
                    reload_until = next_shot + p90["reload"]
                    reload_weapon = "p90"
            if boss_hp <= 0:
                boss_killed_at = frame / 30
        online_frames += state.shield > 0
        p90_frames += mode == "p90"
        state.check()
        if frame % 30 == 0:
            trace.append({"seconds": frame / 30, "hp": round(state.hp, 2), "mp": round(state.mp, 2),
                          "shield": round(state.shield, 2), "mode": mode,
                          "overload": round(overload(profile, b, state.hp, state.shield), 2)})
        if boss_killed_at is not None:
            break
    state.check()
    p90_remaining = 100 - sum(state.shot)
    assert abs(100 + p90_reloaded_rounds + state.synthesized - p90_fired - p90_remaining) < 1e-8
    return {"pressure": pressure["id"], "contact": contact, "initialMpRatio": mp_ratio, "order": order, "returnMpRatioOverride": return_mp_ratio,
            "elapsed": frame / 30, "bossTtk": boss_killed_at, "alive": state.hp > 0,
            "bossRemainingHp": max(0, boss_hp), "shieldOnlineFraction": online_frames / (frame + 1),
            "p90TimeFraction": p90_frames / (frame + 1), "qjzShots": qjz_fired, "p90Shots": p90_fired,
            "switches": switches, "startups": state.startups, "breaches": state.breaches,
            "mpGenerated": state.generated, "mpSpent": state.spent, "hpHealed": state.healed,
            "initialShieldGranted": state.initial_shield_granted,
            "shieldCharged": state.charged, "ammoSynthesized": state.synthesized,
            "p90ReloadedRounds": p90_reloaded_rounds, "p90RemainingRounds": p90_remaining, "trace": trace}


def compensation_projection(configured):
    p = PARAMS["profiles"]["blood_cost_compensated_candidate"]
    controls = [("unmodified_1", build("titanium_type_61_armor", 55, 1, ["血色光剑天秤"])),
                ("unmodified_13", build("titanium_type_61_armor", 55, 13, ["血色光剑天秤"])),
                ("configured_13", configured)]
    budgets = []
    for name, b in controls:
        loss = max(0, -data("血色光剑天秤", b["enhancement"])["hp"])
        capacity, strength, repair = shield_spec(b, p)
        baseline = b["hpMax"] + loss
        budgets.append({"fixture": name, "hpWithBlood": b["hpMax"], "counterfactualHpWithoutPenalty": baseline,
                        "bloodNegativeHpLoss": loss, "shieldCapacity": capacity, "shieldStrength": strength,
                        "fullShieldBurstBudget": b["hpMax"] + min(capacity, strength),
                        "bulkHeadroomAboveCounterfactual": b["hpMax"] + capacity - baseline,
                        "headroomFractionOfLoss": (capacity - loss) / loss,
                        "headroomFractionOfBaselineHp": (b["hpMax"] + capacity - baseline) / baseline,
                        "fullShieldAndStartupMp": capacity * p["shieldMpPerPoint"] + p["startupMp"],
                        "repairPerSecond": repair, "bypassLethalBudget": b["hpMax"]})
    weights = [{"extraNegativeKg": kg, "effectiveWeight": configured["stats"]["weight"] - kg,
                "qjzProgress": clamp(-(configured["stats"]["weight"] - kg), 0, 17) / 17,
                "additionalWeightBeforeLosingFullFireControl": max(0, -(configured["stats"]["weight"] - kg) - 17)}
               for kg in PARAMS["bloodCompensationAnchor"]["weightCandidatesKg"]]
    pressure = [run_pressure(p, s, build_override=configured) for s in PARAMS["pressureScripts"]]
    pressure.append(run_pressure(p, {"id": "heavy_tail", "damage": 4000, "intervalFrames": 90, "bypass": False}, build_override=configured))
    return {"profile": "blood_cost_compensated_candidate", "budgets": budgets,
            "weightSensitivity": weights, "pressure": pressure,
            "scope": PARAMS["bloodCompensationAnchor"]["scope"]}


def produce():
    # Hash the runtime sources behind the translated formulas, even when not parsed as constants.
    paths = ["scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as",
             "scripts/逻辑/装备函数/血色光剑天秤.as", "scripts/逻辑/装备函数/剑圣手甲.as",
             "scripts/逻辑/装备函数/剑圣腿甲.as",
             "scripts/类定义/org/flashNight/arki/component/StatHandler/DodgeHandler.as",
             "scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as",
             "scripts/类定义/org/flashNight/arki/component/Damage/CrumbleDamageHandle.as",
             "scripts/类定义/org/flashNight/arki/component/Damage/UniversalDamageHandle.as",
             "scripts/类定义/org/flashNight/arki/component/Shield/BaseShield.as",
             "scripts/类定义/org/flashNight/arki/item/equipment/PropertyOperators.as",
             "scripts/类定义/org/flashNight/arki/item/equipment/EquipmentCalculator.as",
             "scripts/类定义/org/flashNight/arki/item/ItemUtil.as",
             "scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/DressupInitializer.as",
             "scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ReloadManager.as",
             "scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponFireCore.as",
             "scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/TitaniumSetRuntime.as",
             "scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/StaticInitializer.as",
             "scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/EquipmentUtil/P90EnergyGenerator.as",
             "scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootInitCore.as",
             "scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/HealApplier.as",
             "scripts/类定义/org/flashNight/arki/unit/UnitUtil.as", PARAMS["boss"]["source"]]
    for path in paths:
        read(path)
    for file in ["model.py", "parameters.json"]:
        read(str((HERE / file).relative_to(ROOT)))
    common = ["血色光剑天秤", "钛合金P90", "钛合金P90"]
    ti = build("titanium_type_61_armor", 60, 13, common + ["钛合金QJZ171"])
    advanced = build("advanced_protective_suit", 60, 13, common + ["M134暴力版"])
    doom = build("advanced_protective_suit", 60, 13, common + ["M134暴力版"], doom=True)
    damage = {"ti_none": isolated_ttk(ti, "钛合金QJZ171"),
              "ti_half": isolated_ttk(ti, "钛合金QJZ171", .075, 5),
              "ti_full": isolated_ttk(ti, "钛合金QJZ171", .15, 10),
              "m134_advanced": isolated_ttk(advanced, "M134暴力版")}
    for n in PARAMS["contactAssumptions"]["m134CrumblePipelinesSensitivity"]:
        damage[f"m134_doom_pipelines_{n}"] = isolated_ttk(doom, "M134暴力版", doom["stats"]["rout"], 0, n)
    power_sweep = [{"proposedBasePower": power, **isolated_ttk(ti, "钛合金QJZ171", .15, 10, proposed_base_power=power)}
                   for power in [2345, 2800, 3200, 3600]]
    pressure = {}
    for name, p in PARAMS["profiles"].items():
        pressure[name] = [run_pressure(p, scenario) for scenario in PARAMS["pressureScripts"]]
    p = PARAMS["profiles"]["glass_cannon_candidate"]
    sensitivity = [run_pressure(p, PARAMS["pressureScripts"][1], c, mp, order)
                   for c in [1.0, 0.7] for mp in [1.0, 0.3]
                   for order in ["hit_pulse_fire", "pulse_hit_fire"]]
    saint = sword_saint_projection()
    import reference
    reference_result = reference.produce(sys.modules[__name__])
    configured_ti = reference.energy_build(sys.modules[__name__], reference_result["tiCurrentSlots55"][0])
    reference_result["tiPressure"] = [run_pressure(p, scenario, build_override=configured_ti)
                                     for scenario in PARAMS["pressureScripts"]]
    compensation = compensation_projection(configured_ti)
    recovery_trap = run_pressure(p, PARAMS["pressureScripts"][0], mp_ratio=.15, return_mp_ratio=.65)
    blood_rows = []
    for name, profile in PARAMS["profiles"].items():
        for enhancement in [1, 13]:
            b = build("titanium_type_61_armor", 55, enhancement, common + ["钛合金QJZ171"])
            for attack_duty in [.5, 1.0]:
                loss = 24 * attack_duty
                base_heal = b["hpMax"] * profile["healBaseHpRatioPerSecond"]
                equilibrium_missing = max(0, (loss - base_heal) / profile["healMissingRatioPerSecond"])
                blood_rows.append({"profile": name, "enhancement": enhancement, "attackStateDuty": attack_duty,
                                   "hpMax": b["hpMax"], "expectedSelfLossPerSecond": loss,
                                   "baseHealingPerSecond": base_heal,
                                   "continuousBreachedEquilibriumMissingRatio": equilibrium_missing / b["hpMax"],
                                   "status": "local_continuous_MP_sufficient_analysis; zero_missing_returns_to_reboot; no_enemy_pressure"})
    return {"status": PARAMS["status"], "parameters": PARAMS,
            "sourceHashes": {s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in sorted(SOURCES)},
            "armorMatrix": armor_matrix(p), "swordSaint": saint, "configuredReference": reference_result, "bossContact": damage,
            "topArmorRaw": build("golden_knight_garo", 60, 13),
            "pressure": pressure, "sensitivity": sensitivity, "recoveryThresholdCounterexample": recovery_trap,
            "qjzPowerSensitivityNotApproved": power_sweep,
            "bloodCompensation": compensation,
            "bloodSwordLocalEquilibria": blood_rows,
            "bloodSwordExpectedSelfDamagePerAttackSecond": {"mean": 24, "variance": 48,
                "formula": "30 * (3/5 + 1/5); independent Bernoulli channels, attack-state time only"}}


def markdown(result):
    lines = ["# 钛合金套装模型输出", "", "状态：离线设计模型；不是实机验收。", "",
             "当前原型数值读取胸甲与钛合金P90的生产XML；历史对照与模拟策略读取 `parameters.json`。源码摘要、完整输入及逐秒曲线见同目录 report.json。", "",
             "强度锚点：维护者转述玩家实测，剑圣四阶约补回1.5个7级档位，达到50+综合性能。钛合金五甲以此为目标，加入171后另以牙狼等毕业构筑为参照；不把档位差当DPS倍率。", "",
             "## 毕业场景有效接触模型", "", "| 构筑 | 秒 |", "|---|---:|"]
    for name, row in result["bossContact"].items():
        lines.append(f"| {name} | {row['ttk']:.2f} |")
    lines += ["", "末日铁拳的1/5条管线是假设敏感性，不能当成已测段数。", "",
              "## 能源与已命中压力脚本", "", "| 参数 | 压力 | 存活 | Boss秒数 | 观察秒数 | 盾在线 | P90时间 | MP支出 |", "|---|---|---|---:|---:|---:|---:|---:|"]
    for name, rows in result["pressure"].items():
        for r in rows:
            ttk = f"{r['bossTtk']:.2f}" if r["bossTtk"] is not None else "未击杀"
            lines.append(f"| {name} | {r['pressure']} | {r['alive']} | {ttk} | {r['elapsed']:.2f} | {r['shieldOnlineFraction']:.1%} | {r['p90TimeFraction']:.1%} | {r['mpSpent']:.1f} |")
    lines += ["", "## 血剑最大生命代价", "", "| 套装 | 人物等级 | 强化 | 血剑 | 有效HP | HP代价 | 对100级躲闪系统触发 |", "|---|---:|---:|---|---:|---:|---:|"]
    for r in result["armorMatrix"]:
        lines.append(f"| {r['set']} | {r['level']} | {r['enhancement']} | {r['hasBloodSword']} | {r['hpMax']:.0f} | {r['bloodHpPenalty']:.0f} | {r['dodgeSystemActivationVs100']:.1%} |")
    lines += ["", "躲闪系统触发率不是纯MISS率；负重量只影响触发后的类型分配。HP非正的构筑不能作为可用样本。", "",
              "## 剑圣四阶空手转换", "", "| 等级 | 强化 | 常驻空手 | 爆发空手 | 理想周期均值 | 爆发剩余刀加成 |", "|---|---:|---:|---:|---:|---:|"]
    for r in result["swordSaint"]["rows"]:
        lines.append(f"| {r['level']} | {r['enhancement']} | {r['punchNormal']:.0f} | {r['punchBurst']:.0f} | {r['punchIdealCycleMean']:.2f} | {r['knifeBonusDuringBurst']:.0f} |")
    lines += ["", "不把裸腕刃普攻作为剑圣最强空手循环；真实动作命中与技能轮转仍为待输入量。", ""]
    lines += ["## 初始MP与有效接触敏感性", "", "| 初始MP | 接触 | 同帧顺序 | Boss秒数 | P90占时 | 切换次数 |", "|---:|---:|---|---:|---:|---:|"]
    for r in result["sensitivity"]:
        ttk = f"{r['bossTtk']:.2f}" if r["bossTtk"] is not None else "未击杀"
        lines.append(f"| {r['initialMpRatio']:.0%} | {r['contact']:.0%} | {r['order']} | {ttk} | {r['p90TimeFraction']:.1%} | {r['switches']} |")
    trap = result["recoveryThresholdCounterexample"]
    lines += ["", f"历史G=C候选的回能目标65%、补弹储备50%反例：{trap['elapsed']:.0f}秒内切换{trap['switches']}次，末次观测MP={trap['trace'][-1]['mp']:.1f}，没有回到171。当前方案已有套装基础返还加P90额外发电，不能沿用这个回能陷阱结论。模拟策略保留25%切入P90、45%切回171，不代表新增自动切枪。", "",
              "## 171本体威力敏感性（未批准改值）", "", "| 试算威力 | 理想TTK秒 |", "|---:|---:|"]
    for r in result["qjzPowerSensitivityNotApproved"]:
        lines.append(f"| {r['proposedBasePower']} | {r['ttk']:.2f} |")
    lines += ["", "这些取值没有经过工作簿重新平衡，不修改四层基础身份，不是正式推荐威力。", "",
              "## 血剑破盾局部平衡", "", "| 参数 | 强化 | 攻击态占时 | 自损每秒 | 基础维生每秒 | 平衡缺血比例 |", "|---|---:|---:|---:|---:|---:|"]
    for r in result["bloodSwordLocalEquilibria"]:
        lines.append(f"| {r['profile']} | {r['enhancement']} | {r['attackStateDuty']:.0%} | {r['expectedSelfLossPerSecond']:.1f} | {r['baseHealingPerSecond']:.1f} | {r['continuousBreachedEquilibriumMissingRatio']:.1%} |")
    lines += ["", "MP充足、无外部攻击的连续局部分析；零缺血会重启，不能把此表视为完整周期仿真。", ""]
    lines += ["## 指定插件与项链的剑圣参照", "", "| 等级 | 手甲分支 | HP | 防御 | 挡拆加成 | 对100级触发 | 常驻/爆发空手 | 刀/空手吸血 |", "|---:|---|---:|---:|---:|---:|---:|---:|"]
    for r in result["configuredReference"]["builds"]:
        lines.append(f"| {r['level']} | {r['variant']} | {r['hpMax']} | {r['defence']} | {r['evasion']} | {r['dodgeVs100']:.1%} | {r['punchNormal']}/{r['punchBurst']} | {r['bladeVampirism']}/{r['unarmedVampirism']} |")
    lines += ["", "四阶均+13。手甲吸血分支牺牲该槽35挡拆；刀的吸血不会自动传给腕刃。", "",
              "## 腕刃命中吸血试验", "", "| 手甲分支 | 接触 | 初始HP | 60秒终值HP | 实际治疗 | 存活 |", "|---|---:|---:|---:|---:|---|"]
    for r in result["configuredReference"]["lifestealTrials"]:
        lines.append(f"| {r['variant']} | {r['contact']:.0%} | {r['initialHp']} | {r['finalHp']} | {r['healed']} | {r['alive']} |")
    lines += ["", "无敌人攻击，从半血开始，目标防御1119；每个XFL发射事件最多按一次接触计。此表只验证吸血量级和超血衰减，不是剑圣完整DPS或生存胜率。", ""]
    b = result["configuredReference"]["tiCurrentSlots55"][0]
    g = result["configuredReference"]["garoReference"]
    lines += ["## 当前合法槽位的钛合金与牙狼", "",
              f"钛合金55级参照：HP {b['hpMax']:.0f}，MP {b['mpMax']:.0f}，防御 {b['defence']:.0f}，重量 {b['weight']:.0f}，无额外伺服时火控进度 {b['qjzProgress']:.1%}。头/腿/手/鞋各碳纤维，胸甲背带/纳米/传感器；刀柄芯/纳米/大吸血；171鱼骨/水冷/扩容，双P90各枪盾。",
              f"牙狼60级参照：HP {g['hpMax']:.0f}，MP {g['mpMax']:.0f}，防御 {g['defence']:.0f}，重量 {g['weight']:.0f}。同类合法防具插件、项链，阶段刀为牙狼剑。不是把剑圣三槽免费给其他套装。", "",
              "| 钛合金压力 | 存活 | Boss秒数 | 观察秒数 |", "|---|---|---:|---:|"]
    for r in result["configuredReference"]["tiPressure"]:
        ttk = f"{r['bossTtk']:.2f}" if r["bossTtk"] is not None else "未击杀"
        lines.append(f"| {r['pressure']} | {r['alive']} | {ttk} | {r['elapsed']:.2f} |")
    lines += ["", "## 血剑代价补偿候选", "", f"五甲提供的HP×50%形成通用盾；单段盾强=盾容量。五甲＋血剑＋专属盾在线时，额外实际减重{PARAMS['profiles']['blood_cost_compensated_candidate']['bloodServoBonusKg']}kg。下面只对同强化标准构筑、满盾且可吸收的普通伤害作补偿承诺。", "",
              "| 配装 | 血剑负HP代价 | 盾容量/盾强 | 补回后余量 | 战斗中从0重建MP |", "|---|---:|---:|---:|---:|"]
    for r in result["bloodCompensation"]["budgets"]:
        lines.append(f"| {r['fixture']} | {r['bloodNegativeHpLoss']:.0f} | {r['shieldCapacity']:.1f} | {r['bulkHeadroomAboveCounterfactual']:.1f} | {r['fullShieldAndStartupMp']:.1f} |")
    lines += ["", "| 额外减重 | 最终重量 | 171进度 | 额外插件余量 |", "|---:|---:|---:|---:|"]
    for r in result["bloodCompensation"]["weightSensitivity"]:
        lines.append(f"| {r['extraNegativeKg']} | {r['effectiveWeight']:.0f} | {r['qjzProgress']:.0%} | {r['additionalWeightBeforeLosingFullFireControl']:.0f} |")
    lines += ["", "| 补偿候选压力 | 存活 | Boss秒数 | 观察秒数 |", "|---|---|---:|---:|"]
    for r in result["bloodCompensation"]["pressure"]:
        ttk = f"{r['bossTtk']:.2f}" if r["bossTtk"] is not None else "未击杀"
        lines.append(f"| {r['pressure']} | {r['alive']} | {ttk} | {r['elapsed']:.2f} |")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "tmp/ti61-model")
    parser.add_argument("--check", action="store_true", help="compare existing reports without writing")
    args = parser.parse_args()
    result = produce()
    outputs = {"report.json": json.dumps(result, ensure_ascii=False, indent=2) + "\n", "report.md": markdown(result)}
    if args.check:
        for name, content in outputs.items():
            if (args.out / name).read_text(encoding="utf-8") != content:
                raise SystemExit("stale output: " + name)
        print("model report matches current inputs")
    else:
        args.out.mkdir(parents=True, exist_ok=True)
        for name, content in outputs.items():
            (args.out / name).write_text(content, encoding="utf-8", newline="\n")
        print(args.out / "report.md")


if __name__ == "__main__":
    main()
