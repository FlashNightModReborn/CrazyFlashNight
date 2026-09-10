"""Source-bound JK / Ti61 follow-up. Offline standard-library sensitivity model.

No asset, equipment, save or runtime writes. Source projection and proposed
parameters are separate; target contact and player policy remain assumptions.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import random
import statistics
import subprocess

import model as m
import reference as r
import jk_source

HERE, ROOT = m.HERE, m.ROOT
CONFIG = json.loads((HERE / "jk_followup_parameters.json").read_text(encoding="utf-8"))
TI, ADVANCED = "titanium_type_61_armor", "advanced_protective_suit"
QJZ, M134, BLOOD = "钛合金QJZ171", "M134暴力版", "血色光剑天秤"
PROFILE = m.PARAMS["profiles"][m.PARAMS["runtimeProfile"]]


def configured(set_id=TI, weapon=QJZ, blood_tier=13, level=60, proposed_power=None, neck=None):
    registry = r.mods_from_source(m)
    armor = [n for n, it in m.ITEMS.items() if it.findtext("setId") == set_id]
    assert len(armor) == 5
    rows = []
    for name in armor:
        mods = ["战术背带", "纳米执行单元", "传感器"] if m.ITEMS[name].findtext("use") == "上装装备" else ["碳纤维布料"]
        rows.append({"name": name, "mods": mods, "data": r.resolve(m, name, 13, "data", mods, registry)})
    if blood_tier:
        name = BLOOD
        mods = m.PARAMS["swordSaintReference"]["bladeMods"]
        rows.append({"name": name, "mods": mods, "data": r.resolve(m, name, blood_tier, "data", mods, registry)})
    neck = neck or m.PARAMS["swordSaintReference"]["neck"]
    rows.append({"name": neck, "mods": [], "data": m.data(neck, 13)})
    for name in ["钛合金P90", "钛合金P90", weapon]:
        mods = ["矢量偏转枪盾"] if name == "钛合金P90" else CONFIG["mainMods"]
        # Project a proposed XML base in memory, using the SAME mod resolver.
        original = m.ITEMS[name].find("data/power").text
        try:
            if name == weapon and proposed_power is not None:
                m.ITEMS[name].find("data/power").text = str(proposed_power)
            d = r.resolve(m, name, 13, "data", mods, registry)
        finally:
            m.ITEMS[name].find("data/power").text = original
        rows.append({"name": name, "mods": mods, "data": d})
    totals = {key: sum(row["data"].get(key, 0) for row in rows) for key in m.STATS}
    b = {"set": set_id, "setPieces": 5, "level": level, "enhancement": 13, "items": rows,
         "hpMax": m.growth(200, 1000, level) + totals["hp"],
         "mpMax": m.growth(100, 900, level) + totals["mp"],
         "defence": m.growth(10, 400, level) + totals["defence"],
         "armorHp": sum(row["data"].get("hp", 0) for row in rows[:5]),
         "armorDamage": sum(row["data"].get("damage", 0) for row in rows[:5]),
         "stats": totals, "hasBloodSword": set_id == TI and bool(blood_tier),
         "bloodLoss": -m.data(BLOOD, blood_tier)["hp"] if blood_tier and set_id == TI else 0,
         "weaponData": {row["name"]: row["data"] for row in rows if m.ITEMS[row["name"]].findtext("use") in ("长枪", "手枪")},
         "illegalItems": [row["name"] for row in rows if row["data"]["level"] > level]}
    if b["illegalItems"]:
        raise ValueError("illegal loadout: " + str(b["illegalItems"]))
    if weapon == QJZ:
        assert b["weaponData"][weapon]["capacity"] == CONFIG["mainCapacity"]
    return b


def quantile(values, q):
    s = sorted(values)
    return s[min(len(s) - 1, math.ceil(q * len(s)) - 1)]


def summary(values):
    return {"min": min(values), "median": statistics.median(values), "p90": quantile(values, .9), "max": max(values)}


def shield_capacity(b, coefficient):
    return b["armorHp"] * PROFILE["shieldArmorHpRatio"] + coefficient * b["bloodLoss"]


def contact_segments(event, profile):
    bullet = event["bullet"]
    if "纵向" in bullet:
        return profile["vertical"]
    if "横向" in bullet:
        return profile["horizontal"]
    if "穿透" in bullet or "穿刺" in bullet:
        return profile["piercing"]
    # Melee split is linked to the candidate; duration never creates extra loads.
    return event["split"] * profile["melee"]


def event_damage(event, defence, profile):
    ratio = 1 if event["type"] == "真伤" else 300 / (300 + defence)
    return event["power"] * ratio * contact_segments(event, profile)


def pressure_catalog(runs, defence):
    rows = []
    for contact_id, contacts in CONFIG["contactProfiles"].items():
        for attack in sorted({run["spec"]["attack"] for run in runs}):
            for hp_ratio in [1, .3]:
                group = [run for run in runs if run["spec"]["attack"] == attack and run["spec"]["bossHpRatio"] == hp_ratio and not run["spec"]["resetEmitterOnLoop"]]
                rows.append({"contact": contact_id, "attack": attack, "bossHpRatio": hp_ratio,
                             "emissions": summary([len(x["emissions"]) for x in group]),
                             "seconds": summary([x["durationFrames"] / 30 for x in group]),
                             "damage": summary([sum(event_damage(e, defence, contacts) for e in x["emissions"]) for x in group]),
                             "trueDamage": summary([sum(event_damage(e, defence, contacts) for e in x["emissions"] if e["type"] == "真伤") for x in group])})
    pairs = []
    for contact_id, contacts in CONFIG["contactProfiles"].items():
        group = [run for run in runs if run["spec"]["attack"] in CONFIG["rangedPool"] and not run["spec"]["resetEmitterOnLoop"]]
        damage = [sum(event_damage(e, defence, contacts) for e in run["emissions"]) for run in group]
        totals = [a + b for a in damage for b in damage]
        for gap in [0, 15, 30]:
            pairs.append({"contact": contact_id, "gapFrames": gap, "twoAttacks": summary(totals),
                          "shieldForSampleMaximumAndReserve": max(totals) * (1 + CONFIG["reserveRatio"]),
                          "conditionalPoolDps": sum(damage) / sum((run["durationFrames"] + gap) / 30 for run in group),
                          "meaning": "equal weighting within ranged branch, not empirical AI frequency"})
    loops = []
    for run in runs:
        if run["spec"]["resetEmitterOnLoop"]:
            loops.append({"attack": run["spec"]["attack"], "emissions": len(run["emissions"]),
                          "damageAllCandidates": sum(event_damage(e, defence, CONFIG["contactProfiles"]["all_emissions_once"]) for e in run["emissions"])})
    return {"attacks": rows, "rangedPairs": pairs, "displayListLoopSensitivity": loops}


def vulnerability(age, peak, duration=None, hold=None):
    duration = duration if duration is not None else CONFIG["ray"]["durationFrames"]
    hold = hold if hold is not None else CONFIG["ray"]["holdFrames"]
    if age < 0 or age >= duration:
        return 0
    return peak if age <= hold else peak * (duration - age) / (duration - hold)


def firing_schedule(b, weapon, policy="roll_cd", ray_capacity=8, horizon=5400, flight=4, ray_interval=None):
    gun = m.gun_stats(b, weapon)
    roll = CONFIG["roll"]
    ray_interval = ray_interval or CONFIG["ray"]["intervalFrames"]
    ammo, rays = gun["capacity"], ray_capacity
    next_main = next_ray = next_roll = blocked = 0
    refill_at, refill_kind = -1, ""
    buff_until = -1
    main, ray, reloads, coverage = [], [], [], set()
    # Skill starts ready, but there is no reason to refill two already-full magazines.
    next_roll = roll["cooldownFrames"]
    for t in range(horizon):
        if t == refill_at:
            if refill_kind != "F_assumed":
                ammo = gun["capacity"]
            rays = ray_capacity
        if t < blocked:
            continue
        do_roll = policy == "roll_cd" and t >= next_roll
        do_roll |= policy == "roll_empty" and ammo == 0 and t >= next_roll
        # Explicit adversarial F strategy: refill as soon as the ray magazine empties
        # and its last mark has expired. Duration is a scenario, not measured F time.
        do_fast = policy.startswith("fast_") and rays == 0 and t >= next_ray and ammo > 0
        if do_roll or do_fast or ammo == 0:
            if do_roll:
                length, delay, refill_kind = roll["animationFrames"], roll["refillFrame"], "roll"
                next_roll = t + roll["cooldownFrames"]
                buff_until = t + 2 + roll["buffFrames"]
            elif do_fast:
                length = delay = int(policy.split("_")[1])
                refill_kind = "F_assumed"
            else:
                length = delay = gun["reload"]
                refill_kind = "normal"
            refill_at, blocked = t + delay, t + length
            next_main = max(next_main, blocked)
            reloads.append({"frame": t, "kind": refill_kind, "unusedMainRounds": ammo, "duration": length})
            continue
        if rays > 0 and t >= next_ray:
            ray.append(t)
            rays -= 1
            next_ray = t + ray_interval
            coverage.update(range(t, min(horizon, t + CONFIG["ray"]["durationFrames"])))
        if t >= next_main:
            main.append({"frame": t, "arrival": t + flight, "rollBuff": t < buff_until})
            ammo -= 1
            next_main = t + gun["gap"]
    active_frames = horizon - sum(min(x["duration"], horizon - x["frame"]) for x in reloads)
    return {"main": main, "ray": ray, "reloads": reloads,
            "wallCoverage": len(coverage) / horizon,
            "activeCoverage": len([t for t in coverage if not any(x["frame"] <= t < x["frame"] + x["duration"] for x in reloads)]) / active_frames,
            "mainDuty": len(main) * gun["gap"] / horizon, "horizonFrames": horizon}


def actor_damage(hp, maximum, raw_pre_multi, segments, rout, slay, rng, counters):
    """JK lazy-dodge and counter sensitivity; no AI/reaction animation projection.

    Counter reads pre-chain ordinary damage. It must not see M134's ten-segment
    total as one enormous hit. Returning MISS cancels later crumble / execute.
    """
    ordinary = raw_pre_multi * 300 / (1119 + 300)
    if counters:
        if hp >= maximum * .5:
            dodge = 0 if ordinary < .05 * maximum else min(.56, .56 * ordinary * 2 / maximum)
        else:
            dodge = 0 if ordinary < .025 * maximum else min(.56, .56 * ordinary * 5 / maximum)
        if rng.random() < dodge:
            return hp, maximum
        ratio = ordinary / hp
        if ratio >= .003:
            p = min(5 + ratio * 1000, 30)
            if rng.random() * 100 < p:
                return hp, maximum
            if rng.random() * 100 < p * 1.8:
                ordinary *= 1 - p * .015
    return m.apply_boss_hit(hp, maximum, ordinary * segments, rout, slay)


def outgoing(b, weapon=QJZ, peak=0, ray_capacity=8, policy="roll_cd", flight=4,
             counters=False, seed=1, online_fraction=1, schedule=None,
             missing_hp_ratio=0, ray_hit_rate=1, crumble_vulnerability=False):
    schedule = schedule or firing_schedule(b, weapon, policy, ray_capacity, flight=flight)
    gun = m.gun_stats(b, weapon)
    rng = random.Random(seed)
    hp = maximum = m.PARAMS["boss"]["hp"]
    ray_index, last_ray, ray_hits, main_hits, main_buff_sum, raw_ray_damage = 0, -100000, 0, 0, 0., 0.
    # Ray is stipulated as post-mitigation fixed 100 damage/contact for budgeting.
    # It is NOT a proposed XML power and does not inherit global flat damage.
    for shot in schedule["main"]:
        t = shot["arrival"]
        while ray_index < len(schedule["ray"]) and schedule["ray"][ray_index] <= t:
            ray_frame = schedule["ray"][ray_index]
            ray_index += 1
            # Deterministic missing rays for a bounded contact sensitivity.
            admitted = math.floor(ray_index * ray_hit_rate) > math.floor((ray_index - 1) * ray_hit_rate)
            if peak and admitted:
                last_ray = ray_frame
                ray_damage = CONFIG["ray"]["directDamagePerContact"]
                if CONFIG["ray"].get("directDamageBeforeDefence"):
                    ray_damage = math.floor(ray_damage * 300 / 1419)
                raw_ray_damage += ray_damage
                hp -= ray_damage
                ray_hits += 1
        buff = vulnerability(t - last_ray, peak)
        main_buff_sum += buff
        main_hits += 1
        raw = gun["ordinary"] + (CONFIG["roll"]["gunPowerBuff"] * 1.8 * gun["critMultiplier"] if shot["rollBuff"] else 0)
        if missing_hp_ratio and online_fraction == 0 and b["set"] == TI:
            raw += m.overload(PROFILE, b, b["hpMax"] * (1 - missing_hp_ratio), 0) * gun["critMultiplier"]
        raw *= 1 + buff
        if weapon == QJZ:
            count = 2 + (main_hits - 1) % 2
            # Alternating deterministic online windows, not randomized extra hits.
            online = online_fraction >= 1 or (t % 300) < 300 * online_fraction
            progress = (m.clamp(-(b["stats"]["weight"] - (PROFILE["bloodServoBonusKg"] if b["hasBloodSword"] else 0)), 0, 17) / 17) if online else 0
            for _ in range(count):
                rout = .15 * progress * (1 + buff if crumble_vulnerability else 1)
                hp, maximum = actor_damage(hp, maximum, raw, 1, rout, 10 * progress, rng, counters)
                if hp <= 0:
                    break
        else:
            # Five independent collision pipelines; two chain segments each.
            for _ in range(5):
                hp, maximum = actor_damage(hp, maximum, raw, 2, 0, 0, rng, counters)
                if hp <= 0:
                    break
        if hp <= 0:
            return {"ttk": t / 30, "mainShots": main_hits, "rayShots": ray_index if peak else 0, "rayHits": ray_hits,
                    "meanMainBuff": main_buff_sum / main_hits, "rayDirect": raw_ray_damage,
                    "rolls": sum(x["kind"] == "roll" and x["frame"] <= t for x in schedule["reloads"]),
                    "rayClipsLoadedIncludingInitial": (1 + sum(x["frame"] + x["duration"] <= t for x in schedule["reloads"])) if peak and ray_index else 0,
                    "mainClipsLoadedIncludingInitial": 1 + sum(x["kind"] != "F_assumed" and x["frame"] + x["duration"] <= t for x in schedule["reloads"]),
                    "status": "conditional_source_formula_ttk_not_field"}
    return {"ttk": None, "mainShots": main_hits, "remainingHp": hp}


class CandidateEnergy(m.EnergyState):
    def __init__(self, b, coefficient=24, mp_cost=.012, hp_ratio=1, mp_ratio=1, blood_true=True):
        p = dict(PROFILE, shieldMpPerPoint=mp_cost)
        super().__init__(b, p, hp_ratio=hp_ratio, mp_ratio=mp_ratio)
        self.maximum = self.strength = shield_capacity(b, coefficient)
        self.repair_per_second = self.maximum / p["fullRechargeSeconds"]
        self.blood_true = blood_true and b["hasBloodSword"]
        self.skill_granted = self.execution_removed = 0.
        self.skill_ready = 0
        self.skill_casts = 0

    def hit_event(self, event, profile, damage_factor=1):
        amount = event_damage(event, self.b["defence"], profile) * damage_factor
        # Execute tests unabsorbed prospective HP and RAW bullet power vs strength.
        # Fractional/contact aggregation is only a pressure scenario; execute is
        # checked per effective segment to avoid manufacturing a multi-shot slay.
        n = contact_segments(event, profile)
        if n <= 0:
            return
        unit = amount / n
        for index in range(math.ceil(n)):
            d = unit * min(1, n - index)
            if (event["slay"] and self.hp - d < self.b["hpMax"] * event["slay"] / 100
                    and event["power"] > (self.strength if self.shield > 0 else 0)):
                self.execution_removed += self.shield
                self.shield = 0
                self.hp_damage += self.hp
                self.hp = 0
                return
            super().hit(d, event["type"] == "真伤" and not self.blood_true)
            if self.hp <= 0:
                return

    def blood_skill(self, frame, cost_ratio=.35, cooldown=24):
        cost = math.ceil(self.b["hpMax"] * cost_ratio)
        if (not self.b["hasBloodSword"] or self.hp <= cost or frame < self.skill_ready
                or self.shield >= self.maximum or self.hp <= 0):
            return False
        self.hp -= cost
        self.self_damage += cost
        self.skill_granted += self.maximum - self.shield
        self.shield = self.maximum
        self.paid = False
        self.skill_ready = frame + int(cooldown * 30)
        self.skill_casts += 1
        return True

    def check(self):
        assert abs(self.initial_mp + self.generated - self.spent - self.mp) < 1e-5
        assert abs(self.initial_shield_granted + self.charged + self.skill_granted - self.absorbed - self.execution_removed - self.shield) < 1e-4
        assert abs(self.initial_hp + self.healed - self.hp_damage - self.self_damage - self.hp) < 1e-5
        assert -1e-7 <= self.mp <= self.b["mpMax"] + 1e-7
        assert 0 <= self.shield <= self.maximum + 1e-7


def recovery(b, coefficient, mp_cost, hp_ratio=.65, p90=False, skill=False):
    s = CandidateEnergy(b, coefficient, mp_cost, hp_ratio=hp_ratio)
    s.initial_shield_pending = False
    if skill:
        s.blood_skill(0)
    full_at = None
    for t in range(5401):
        if p90 and t % 3 == 0:
            # Explicit upper-bound supply: available reserves and no reload time.
            for slot in [0, 1]:
                if s.shot[slot] == 50:
                    s.shot[slot] = 0
                s.p90_fire(slot)
        if t % 6 == 0:
            s.pulse()
        if s.shield >= s.maximum - 1e-6:
            full_at = t / 30
            break
    s.check()
    return {"k": coefficient, "mpCost": mp_cost, "initialHpRatio": hp_ratio, "p90SupplyUpperBound": p90,
            "bloodSkill": skill, "fullAt": full_at, "hp": s.hp, "mp": s.mp, "shield": s.shield,
            "mpSpent": s.spent, "mpGenerated": s.generated}


def pressure_trial(b, runs, coefficient=24, mp_cost=.012, contact_id="working", skill=False,
                   cooldown=24, cost=.35, seed=1, gap=15, potion=False, blood_true=True):
    rng = random.Random(seed)
    pool = [run for run in runs if run["spec"]["attack"] in CONFIG["rangedPool"] and run["spec"]["bossHpRatio"] == 1 and not run["spec"]["resetEmitterOnLoop"]]
    events, t = {}, 90
    while t < 5400:
        run = rng.choice(pool)
        for e in run["emissions"]:
            events.setdefault(t + e["tick"], []).append(e)
        t += run["durationFrames"] + gap
    s = CandidateEnergy(b, coefficient, mp_cost, blood_true=blood_true)
    s.pulse()
    online, potion_hp, potion_mp = 0, 0., 0.
    # Fixed incoming sequence. No claim that the dead enemy keeps attacking in a
    # coupled duel; outgoing TTK is a separate upper bound on required endurance.
    for t in range(5400):
        if potion and t and t % 900 == 0:
            dh = max(0, 1.3 * b["hpMax"] - s.hp)
            dm = b["mpMax"] - s.mp
            s.hp += dh
            s.initial_hp += dh
            s.mp += dm
            s.initial_mp += dm
            potion_hp += dh
            potion_mp += dm
        if t and t % CONFIG["roll"]["cooldownFrames"] == 0 and s.mp >= CONFIG["roll"]["mpCost"]:
            s.spend(CONFIG["roll"]["mpCost"])
        if skill and s.shield < .3 * s.maximum:
            s.blood_skill(t, cost, cooldown)
        for event in events.get(t, []):
            s.hit_event(event, CONFIG["contactProfiles"][contact_id])
            if s.hp <= 0:
                break
        if s.hp <= 0:
            break
        if t % 6 == 0:
            s.pulse()
        online += s.shield > 0
    s.check()
    return {"seconds": (t + 1) / 30, "censoredAt180": s.hp > 0, "onlineFraction": online / (t + 1),
            "skillCasts": s.skill_casts, "breaches": s.breaches, "mpSpent": s.spent,
            "hp": s.hp, "shield": s.shield, "potionHp": potion_hp, "potionMp": potion_mp}


def two_attack_trial(b, first, second, k, mp_cost, mp_ratio, phase=0, hit_first=True):
    s = CandidateEnergy(b, k, mp_cost, mp_ratio=mp_ratio)
    s.pulse()
    events = {}
    for offset, run in [(0, first), (first["durationFrames"], second)]:
        for event in run["emissions"]:
            events.setdefault(offset + event["tick"], []).append(event)
    end = max(events)
    minimum = s.shield
    for t in range(end + 1):
        if not hit_first and (t + phase) % 6 == 0:
            s.pulse()
        for event in events.get(t, []):
            s.hit_event(event, CONFIG["contactProfiles"]["all_emissions_once"], 1.15)
            minimum = min(minimum, s.shield)
            if s.hp <= 0:
                break
        if s.hp <= 0:
            break
        if hit_first and (t + phase) % 6 == 0:
            s.pulse()
    s.check()
    return {"survived": s.hp > 0, "shieldNeverBroke": minimum > 0, "minimumShield": minimum,
            "remainingHp": s.hp, "remainingMp": s.mp, "mpSpent": s.spent}


def produce(attacks_path):
    source_runs = json.loads(attacks_path.read_text(encoding="utf-8"))
    runs = source_runs["results"]
    ti, advanced = configured(), configured(ADVANCED, M134)
    if any(x["spec"]["defence"] != ti["defence"] or not x["completed"] for x in runs):
        raise ValueError("attack projection is truncated or has a different target defence")
    if source_runs["sourceIdentity"] != jk_source.collect()["identity"]:
        raise ValueError("attack projection belongs to a different FLA")
    pressure = pressure_catalog(runs, ti["defence"])
    shields = []
    for tier in [0] + CONFIG["bloodEnhancements"]:
        b = configured(blood_tier=tier)
        for k in CONFIG["shieldCoefficients"]:
            capacity = shield_capacity(b, k)
            shields.append({"bloodTier": tier, "hp": b["hpMax"], "loss": b["bloodLoss"], "k": k,
                            "shield": capacity, "hpPlusShield": b["hpMax"] + capacity,
                            "alchemyHpPlusShield": b["hpMax"] * 1.3 + capacity,
                            "trueShield": b["hasBloodSword"],
                            "rechargeMpOld": capacity * .08 + PROFILE["startupMp"]})
    fire = []
    for weapon, b in [(QJZ, ti), (M134, advanced), (M134, configured(TI, M134))]:
        peaks = CONFIG["ray"]["peaks"] if weapon == QJZ else [0]
        for peak in peaks:
            for policy in (["roll_cd", "roll_empty"] if weapon == QJZ else ["normal"]):
                schedule = firing_schedule(b, weapon, policy, 8 if peak else 0)
                trials = [outgoing(b, weapon, peak, 8 if peak else 0, policy, counters=True, seed=seed, schedule=schedule) for seed in range(1, 33)]
                fire.append({"weapon": weapon, "set": b["set"], "peak": peak, "rayCapacity": 8 if peak else 0,
                             "policy": policy, "noCounter": outgoing(b, weapon, peak, policy=policy, schedule=schedule),
                             "counterSensitivity": summary([v["ttk"] for v in trials]),
                             "meaning": "all non-counter hits admitted; expected crit, fixed contact"})
    coverage = []
    for capacity in CONFIG["ray"]["capacities"]:
        for policy in ["roll_cd", "roll_empty", "normal", "fast_12", "fast_24", "fast_42"]:
            for flight in CONFIG["ray"]["mainArrivalFrames"]:
                s = firing_schedule(ti, QJZ, policy, capacity, flight=flight)
                out = outgoing(ti, QJZ, 1.5, capacity, policy, flight=flight, schedule=s)
                coverage.append({"capacity": capacity, "policy": policy, "flightFrames": flight,
                                 "wallCoverage": s["wallCoverage"], "activeCoverage": s["activeCoverage"],
                                 "mainDuty": s["mainDuty"], "ttk": out["ttk"], "meanMainBuff": out["meanMainBuff"],
                                 "rollsIn180": sum(x["kind"] == "roll" for x in s["reloads"]),
                                 "refillsIn180": len(s["reloads"])})
    ammo = []
    for base in [2345, 2552]:
        b = configured(proposed_power=base)
        for peak in [0, 1.5]:
            ammo.append({"basePower": base, "peak": peak, "enhancedPower": b["weaponData"][QJZ]["power"],
                         "ordinaryPreDefence": m.gun_stats(b, QJZ)["ordinary"],
                         "result": outgoing(b, QJZ, peak)})
    recoveries = [recovery(ti, k, c, hp, p90) for k in [24, 40, 48, 64]
                  for c in CONFIG["shieldMpCosts"] for hp in [1, .65] for p90 in [False, True]]
    blood_skill = [{"cost": c, "initialHpRatio": hp, "afterHpRatio": hp - math.ceil(ti["hpMax"] * c) / ti["hpMax"],
                    "costHp": math.ceil(ti["hpMax"] * c), "lowHpJkTrigger": hp - c < .35}
                   for c in CONFIG["bloodSkill"]["hpMaxCostRatios"] for hp in [1.3, 1, .7, .5]]
    trials = []
    for k in [0, 24, 40, 48, 64]:
        for contact_id in ["working", "all_emissions_once"]:
            for skill in [False, True]:
                values = [pressure_trial(ti, runs, k, .012 if k else .08, contact_id, skill, seed=seed, blood_true=bool(k)) for seed in range(1, 33)]
                trials.append({"k": k, "contact": contact_id, "skill": skill, "survival": summary([v["seconds"] for v in values]),
                               "online": summary([v["onlineFraction"] for v in values]), "skillCasts": summary([v["skillCasts"] for v in values]),
                               "survived180": sum(v["censoredAt180"] for v in values)})
    skill_sensitivity = []
    for cost in CONFIG["bloodSkill"]["hpMaxCostRatios"]:
        for cd in CONFIG["bloodSkill"]["cooldownSeconds"]:
            for potion in [False, True]:
                values = [pressure_trial(ti, runs, 24, .012, skill=True, cost=cost, cooldown=cd, potion=potion, seed=seed) for seed in range(1, 17)]
                skill_sensitivity.append({"cost": cost, "cooldown": cd, "externalFullPotionEvery30s": potion,
                                          "survival": summary([v["seconds"] for v in values]),
                                          "casts": summary([v["skillCasts"] for v in values]),
                                          "survived180": sum(v["censoredAt180"] for v in values)})
    online = [{"fraction": f, "peak": peak, "result": outgoing(ti, QJZ, peak, online_fraction=f)}
              for f in [0, .5, 1] for peak in [0, 1.5]]
    cadence = []
    for interval in [27, 45]:
        for policy in ["roll_cd", "fast_12", "fast_24", "fast_42"]:
            s = firing_schedule(ti, QJZ, policy, 8, ray_interval=interval)
            cadence.append({"interval": interval, "policy": policy,
                            "wallCoverage": s["wallCoverage"], "activeCoverage": s["activeCoverage"],
                            "ttk": outgoing(ti, QJZ, 1.5, schedule=s)["ttk"]})
    envelope = []
    peak_regular = max(x["damageAllCandidates"] for x in pressure["displayListLoopSensitivity"])
    space = next(x["damage"]["max"] for x in pressure["attacks"] if x["contact"] == "all_emissions_once" and x["attack"] == "空间斩" and x["bossHpRatio"] == 1)
    for kind, damage in [("ranged_including_9_shot_crouch", peak_regular), ("normal_space_slash_zero_charge", space)]:
        for extra_margin in [0, .15]:
            required = damage * 2 * 1.15 * (1 + extra_margin)
            envelope.append({"scope": kind, "twoAttacksMeanVariance": damage * 2, "varianceFactor": 1.15,
                             "extraReserve": extra_margin, "requiredShieldIgnoringRepair": required,
                             "minimumK": (required - ti["armorHp"] * .5) / ti["bloodLoss"]})
    candidate_trials = []
    for k, mp in [(48, .02), (64, .016)]:
        for contact in ["working", "all_emissions_once"]:
            for cd in [18, 24, 30]:
                for potion in [False, True]:
                    values = [pressure_trial(ti, runs, k, mp, contact, True, cooldown=cd, seed=seed, potion=potion) for seed in range(1, 17)]
                    candidate_trials.append({"k": k, "mpCost": mp, "contact": contact, "skillCooldown": cd,
                                             "externalFullPotionEvery30s": potion,
                                             "survival": summary([v["seconds"] for v in values]),
                                             "casts": summary([v["skillCasts"] for v in values]),
                                             "survived180": sum(v["censoredAt180"] for v in values)})
    overload = []
    for weapon in [QJZ, M134]:
        b = configured(TI, weapon)
        for missing in [0, .3, .5, .8]:
            flat = m.overload(PROFILE, b, b["hpMax"] * (1 - missing), 0)
            g = m.gun_stats(b, weapon)
            overload.append({"weapon": weapon, "fixedMissingHpRatio": missing, "flatPerSegment": flat,
                             "ordinaryIncrease": flat * g["critMultiplier"] / g["ordinary"],
                             "result": outgoing(b, weapon, peak=0, policy="normal", online_fraction=0, missing_hp_ratio=missing)})
    ray_misses = [{"admitted": admitted, "result": outgoing(ti, QJZ, 1.5, ray_hit_rate=admitted)} for admitted in [.5, .8, 1]]
    two_attacks = []
    for name, reset in [("长枪蹲射", True), ("腰射", False), ("枪斗术", False), ("空间斩", False)]:
        run = next(x for x in runs if x["spec"]["attack"] == name and x["spec"]["resetEmitterOnLoop"] == reset and x["spec"]["bossHpRatio"] == 1)
        for k, cost in [(24, .012), (40, .02), (48, .02), (64, .016)]:
            for mp in [0, .1, .25, 1]:
                values = [two_attack_trial(ti, run, run, k, cost, mp, phase, order) for phase in range(6) for order in [False, True]]
                two_attacks.append({"attackTwice": name, "crouchReloadSensitivity": reset, "k": k, "mpCost": cost,
                                    "initialMpRatio": mp, "all12SchedulesSurvive": all(v["survived"] for v in values),
                                    "all12SchedulesShieldSurvives": all(v["shieldNeverBroke"] for v in values),
                                    "minimumShield": min(v["minimumShield"] for v in values),
                                    "minimumHp": min(v["remainingHp"] for v in values),
                                    "maximumMpSpent": max(v["mpSpent"] for v in values)})
    guard = max(e["power"] for run in runs if run["spec"]["attack"] in CONFIG["rangedPool"] for e in run["emissions"] if e["slay"])
    sources = set(m.SOURCES) | {jk_source.FLA, "flashswf/arts/new/武装JK.swf"}
    sources.update(str(p.relative_to(ROOT)).replace("\\", "/") for p in HERE.glob("jk_*.py"))
    sources.update(str(p.relative_to(ROOT)).replace("\\", "/") for p in [HERE / "jk_script_sampler.js", HERE / "jk_followup_parameters.json", HERE / "reference.py", HERE / "model.py", HERE / "parameters.json"])
    for path in ["scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/TitaniumSetRuntime.as",
                 "scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/RespawnEventComponent.as",
                 "scripts/类定义/org/flashNight/arki/unit/Action/Skill/SkillReloadCore.as", "data/skills/skills.xml",
                 "scripts/类定义/org/flashNight/arki/component/Damage/ExecuteDamageHandle.as",
                 "flashswf/arts/things0/LIBRARY/容器/技能容器/技能容器-翻滚换弹.xml",
                 "scripts/类定义/org/flashNight/arki/unit/Action/Shoot/LongGunSubWeaponCore.as",
                 "scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootInitCore.as",
                 "scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ReloadManager.as",
                 "scripts/类定义/org/flashNight/arki/component/StatHandler/DodgeHandler.as",
                 "scripts/类定义/org/flashNight/arki/component/Damage/UniversalDamageHandle.as",
                 "scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as",
                 "scripts/类定义/org/flashNight/arki/component/Damage/DamageManagerFactory.as",
                 "scripts/类定义/org/flashNight/arki/component/Buff/Effect/ToughnessVulnerabilityController.as",
                 "scripts/类定义/org/flashNight/arki/item/drug/DrugContext.as",
                 "scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as",
                 "scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as",
                 "data/stages/副本任务/挑战战斗天才.xml", "data/items/消耗品_弹夹.xml",
                 "tools/cf7-balance-tool/packages/core/src/formulas/weapons.ts",
                 "tools/cf7-balance-tool/models/ti61/test_jk_followup.py",
                 "tools/cf7-balance-tool/models/ti61/test_jk_sampler.js"]:
        sources.add(path)
    manifest = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sorted(sources)}
    return {"status": "offline_candidate_not_implemented_not_field_verified", "parameters": CONFIG,
            "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "sourceManifest": manifest, "attackInputSha256": hashlib.sha256(attacks_path.read_bytes()).hexdigest(),
            "boss": {"level": 100, "difficulty": 2.5, "attack": 21482.5, "hp": 3770762.5, "defence": 1119},
            "loadouts": {"titanium": ti, "advancedM134": advanced}, "pressure": pressure, "shieldScan": shields,
            "rawExecuteGuard": guard, "firepower": fire, "coverage": coverage, "ammo": ammo,
            "recoveries": recoveries, "bloodSkillCosts": blood_skill, "pressureTrials": trials,
            "bloodSkillSensitivity": skill_sensitivity, "onlineSensitivity": online, "cadenceSensitivity": cadence,
            "twoAttackEnvelope": envelope, "candidateTrials": candidate_trials,
            "overloadSensitivity": overload, "rayContactSensitivity": ray_misses, "twoAttackTrials": two_attacks}


def markdown(result):
    b = result["loadouts"]["titanium"]
    lines = ["# 钛合金61 / 血剑 / 171 对 JK 的离线推演", "",
             "状态：候选设计；未修改生产装备、技能、SWF，未进行 Flash 实战验收。数值来自当前源码与显式接触假设。", "",
             f"源码基线：`{result['head']}`。完整逐文件 SHA-256 与参数、全部扫描见同目录 report.json。", "",
             f"主样本：60 级、五甲 +13、血剑 +13、171 鱼骨/水冷、60 发、不扩容。HP {b['hpMax']:.0f}、MP {b['mpMax']:.0f}、DEF {b['defence']:.0f}；五甲 HP {b['armorHp']:.0f}，血剑固有负 HP {b['bloodLoss']:.0f}。", "",
             "## JK 不是一个常数 DPS", "",
             "下表为同一招式的发射候选全部接触一次时，已减伤的伤害范围；多段弹按指定 10/8 段计，伤害波动取均值。源码另有 0.85–1.15 倍粉红噪声波动。它既不是实际命中伤害，也不是绝对上界（穿透重叠、反制、无敌蓄力仍可能更高）。", "",
             "| 招式 | 完整动作秒数 | 伤害最小—最大 | 真伤最大 |", "|---|---:|---:|---:|"]
    for row in result["pressure"]["attacks"]:
        if row["contact"] == "all_emissions_once" and row["bossHpRatio"] == 1:
            lines.append(f"| {row['attack']} | {row['seconds']['min']:.2f}–{row['seconds']['max']:.2f} | {row['damage']['min']:.0f}–{row['damage']['max']:.0f} | {row['trueDamage']['max']:.0f} |")
    lines += ["", "`working` 接触假设为纵向弹 4 段、横向弹 2 段、穿透弹 1 次、近战候选各一次；`all_emissions_once` 为纵向 10 段、横向 8 段。都尚未经过测试员录像标定。单喷有循环，完整攻势不能按第一喷计。", "",
              "| 220–500 距离分支 | 两招样本最大 | 留 15% 余量所需盾 | 分支条件平均 DPS（间隔 0.5s） |", "|---|---:|---:|---:|"]
    for row in result["pressure"]["rangedPairs"]:
        if row["gapFrames"] == 15:
            lines.append(f"| {row['contact']} | {row['twoAttacks']['max']:.0f} | {row['shieldForSampleMaximumAndReserve']:.0f} | {row['conditionalPoolDps']:.0f} |")
    lines += ["", f"此外，普通远程带斩杀弹的原始威力最高 {result['rawExecuteGuard']:.1f}。现役斩杀在扣盾前预判 HP，再用原始威力比较盾强；只按减伤后两招总和设计，低 HP 时仍有穿盾斩杀漏洞。", "",
              "普通空间斩属于中距离招式池，不能统称为必躲大招后排除。无敌蓄力附加攻击不在上表零蓄力场景中。蹲射同关键帧实例是否重建还有 7/9 次发射敏感性。", "",
              "更保守的两招包络（不借过程中的自动修复）如下。此前的单个 15% 系数可用于吃掉最高伤害波动；若还要求额外余量，必须另外乘，不能重复使用同一份余量。", "",
              "| 范围 | 两招均值伤害 | 另留余量 | 含最高 1.15 波动所需盾 | 最小 k |", "|---|---:|---:|---:|---:|"]
    for row in result["twoAttackEnvelope"]:
        lines.append(f"| {row['scope']} | {row['twoAttacksMeanVariance']:.0f} | {row['extraReserve']:.0%} | {row['requiredShieldIgnoringRepair']:.0f} | {row['minimumK']:.2f} |")
    lines += ["",
              "## 血剑与盾", "", "候选 S = 0.5 × 五甲实际 HP 贡献 + k × 血剑强化后的固有负 HP。转入项不读取当前血量、药剂超血或其他插件扣血；血剑存在时共享盾池可抗普通真伤。", "",
              "| 血剑 | k | HP | 盾 | HP + 盾 | 原 0.08 MP/盾下重启满充成本 |", "|---|---:|---:|---:|---:|---:|"]
    for row in result["shieldScan"]:
        if row["bloodTier"] in [1, 13] and row["k"] in [24, 40, 48, 64]:
            lines.append(f"| +{row['bloodTier']} | {row['k']} | {row['hp']:.0f} | {row['shield']:.0f} | {row['hpPlusShield']:.0f} | {row['rechargeMpOld']:.0f} |")
    lines += ["", "k > 1.3 可以覆盖最高 30% 炼金超血的静态机会成本，但这只是消除低强化套利的条件，不能独自证明承压或循环平衡。8 秒充满与 MP 单价必须一起校准。", "",
              "| k | MP/盾 | 满 HP、空盾起步，无外部 MP：满充秒数 | 双 P90 理想持续供电上界：满充秒数 |", "|---|---:|---:|---:|"]
    for k in [24, 48, 64]:
        for c in [.012, .02, .08]:
            rs = [v for v in result["recoveries"] if v["k"] == k and v["mpCost"] == c and v["initialHpRatio"] == 1]
            display = lambda v: f"{v['fullAt']:.1f}" if v['fullAt'] is not None else "180 秒内未满"
            lines.append(f"| {k} | {c} | {display(next(v for v in rs if not v['p90SupplyUpperBound']))} | {display(next(v for v in rs if v['p90SupplyUpperBound']))} |")
    lines += ["", "血剑战技：候选按最大 HP 支付 35%、独立冷却 24 秒、非致死检查，立即补满已损失盾量。满盾/死亡/未穿套/冷却中应无扣费。冷却归属角色，换武器、复活不可重置。", "",
              "从 130% 超血释放后约剩 95%，从满血释放后约剩 65%；成本 ≤30% 会被炼金超血完整覆盖。残血连续使用还可能把角色推入 JK 低于 35% HP 的斩杀空间斩分支。测试没有把药剂当免费来源。", "",
              "两轮完整普通空间斩的逐帧检查：所有候选接触、统一采用 1.15 波动、招间零额外停顿、没有战技/药剂/闪避/无敌蓄力；枚举 6 个修复脉冲相位及受击前后两种脉冲顺序。", "",
              "| k | 初始 MP | 12 种顺序均存活且盾未破 | 最低剩余盾 | 期间最大耗 MP |", "|---|---:|---|---:|---:|"]
    for row in result["twoAttackTrials"]:
        if row["attackTwice"] == "空间斩" and row["k"] in [48, 64]:
            lines.append(f"| {row['k']} | {row['initialMpRatio']:.0%} | {row['all12SchedulesShieldSurvives']} | {row['minimumShield']:.0f} | {row['maximumMpSpent']:.0f} |")
    lines += ["",
              "## 171 与暴力 M134", "",
              "M134 主参照为先进防护服五甲、同等合法防具插件、血剑、双 P90 与鱼骨/水冷；不是极限最优 M134 构筑。另保留同钛甲 M134 控制。项链沿用既有刀剑项链，是明确控制项，不声称枪械最优。", "",
              "反制列为 32 个固定种子的条件敏感性；已处理 JK 受击反制在霰弹展开前结算，未重建反制动画、走位、取消与硬直。", "",
              "| 配装 | 标记峰值 | 换弹策略 | 无反制 TTK | 反制敏感性中位 / 最大 |", "|---|---:|---|---:|---:|"]
    for row in result["firepower"]:
        if row["peak"] in [0, 1, 1.5, 2] and row["policy"] in ["roll_cd", "normal"]:
            label = ("钛甲" if row["set"] == TI else "先进防护服") + row["weapon"]
            policy_label = "每 12 秒翻滚" if row['policy'] == 'roll_cd' else "1800 发内持续射击"
            lines.append(f"| {label} | +{row['peak']:.0%} | {policy_label} | {row['noCounter']['ttk']:.2f}s | {row['counterSensitivity']['median']:.2f} / {row['counterSensitivity']['max']:.2f}s |")
    lines += ["", "标记设定：副射命中一次到峰值，0.9 秒线性衰退，最短射击间隔 1.5 秒，重复命中刷新到峰值、同类取最大，主弹不刷新。副射间隔不会被主副仓换弹重置。收益开放给队友及其他武器；此表只算单兵。副射每次实际伤害按 100 建模，不等于 XML 威力填 100。", "",
              "| 副仓 | 换弹策略 | 射击时段覆盖 | 主弹平均增伤（峰值 +150%） | TTK |", "|---|---|---:|---:|---:|"]
    for row in result["coverage"]:
        if row["capacity"] in [8, 12] and row["flightFrames"] == 4:
            lines.append(f"| {row['capacity']} | {row['policy']} | {row['activeCoverage']:.1%} | {row['meanMainBuff']:.1%} | {row['ttk']:.2f}s |")
    lines += ["", "翻滚源为 12 秒冷却、70 MP、约 13 帧动画、第 8 帧装填，并补副仓。F 行是 12/24/42 帧停火的敏感性，不是实测换弹耗时；F 只补副仓，主仓仍需换弹。主仓 R 与副仓联装的额外负担未计，故 F 策略偏乐观。", "",
              "翻滚旧时间轴声明的 +150 长枪威力未计入收益：现役 ShootInitCore 读取 weaponData.power，没有找到这项旧字段进入当前射击伤害的接线。这里不将写入动画字段等同有效伤害提升。", "",
              "若副射间隔也设为 0.9 秒，F 快装会把效果覆盖推到接近全程。建议用 0.9 秒效果 / 1.5 秒最短副射间隔形成约 60% 的长期时间上限，8 发副仓用于翻滚节奏与时机取舍；弹量本身只作软预算。两种间隔的对照在 JSON cadenceSensitivity。", "",
              "高温自锐式针弹只是弹夹物品名，不自带伤害乘区。若另行批准把基础威力 2345 改到预算候选 2552，必须重新走武器平衡记录；下表只有离线候选。", "",
              "| 基础威力 | 峰值 | 普通伤害（减伤前） | TTK |", "|---|---:|---:|---:|"]
    for row in result["ammo"]:
        lines.append(f"| {row['basePower']} | +{row['peak']:.0%} | {row['ordinaryPreDefence']:.1f} | {row['result']['ttk']:.2f}s |")
    lines += ["", "## 持续压力与喘息", "",
              "下表为固定距离分支等权抽取招式、招间 0.5 秒、首招 3 秒后开始、无闪避/走位/药剂/P90 停火供电的独立承压情景；有 MP 时每 12 秒支付翻滚 70 MP，但不借其无敌漏算入伤。敌人不因输出死亡，故不是胜率。战技在盾低于 30% 时尝试使用。", "",
              "| k | 接触情景 | 35% / 24s 战技 | 生存秒数中位 / 最小 / 最大 |", "|---|---|---|---:|"]
    for row in result["pressureTrials"]:
        lines.append(f"| {row['k']} | {row['contact']} | {row['skill']} | {row['survival']['median']:.1f} / {row['survival']['min']:.1f} / {row['survival']['max']:.1f} |")
    lines += ["", "这组压力结果用于暴露容量、循环和战技的取舍，不能证明完全站桩毕业；能接两轮也不等于无限续盾。药剂每 30 秒补至 130% HP / 100% MP 的乐观输入、18/24/30 秒冷却和 20/30/35/40% 耗血另在 JSON 扫描，不能外推成药剂实际冷却或供给。", "",
              "候选 A（k=48，0.02 MP/盾）、候选 B（k=64，0.016 MP/盾）的独立扫描见 candidateTrials。两者满血空盾重启均约消耗 80%–84% 满蓝；在 working 接触与每 30 秒外部补药的乐观情景中均可能持续存活 180 秒。容量旋钮不能独自封住外部治疗/供能或满血重装带来的循环收益。", "",
              "## 过载、射线命中与协同边界", "",
              "固定残血的过载只作瞬时敏感性，不是假定人物能一直压血不死。半血时钛甲 M134 普通火力增加约 44.4%，171 约 9.3%；只剩 20% HP 时分别约 89.9% 与 18.8%。这证实按段平加偏向 M134，但不能照搬另一报告的裸装百分比，也不能用加盾消除这个收益结构。", "",
              "射线有效命中从 100% 降到 80%/50%，默认峰值 +150% 的收益明显降低，完整结果见 rayContactSensitivity；未命中仍消耗副弹。到达时差 0/4/8 帧也分别计算，不能把时间平均增伤等同主弹平均增伤。", "",
              "可以复用灰蛊的目标承伤系数承载方式，不能直接复制其命中堆层、节点击溃、满层斩杀或涂层设定。原插件排除穿刺弹，171 内置引导采用独立配置。共享给队友是已接受收益；模型不扣所谓协同预算，也不伪造单兵可同时拿两把长枪。", "",
              "## 实现与验收约束", "",
              "1. 复活修复为必须完成项。TitaniumSetRuntime.tick 在 HP≤0 时拆除套装 group；RespawnEventComponent 仅复原资源和状态，没有重建该 group。应在正式复活完成后幂等恢复装备效果，避免全量属性重算抹掉临时 Buff；确认没有重复周期任务、HUD/盾层/火控/发电都恢复。此轮未修生产代码。",
              "2. 血剑换装只用固有强化负 HP 建立贡献，拆装及时撤销额外容量及真伤能力；不得从临时缺血、溢出治疗或主动自损递归增盾。现有约定允许满血重装免费满盾，本轮没有批准修改这一旧约定；若继续保留，它会绕过大盾的回充与战技成本，不能再声称循环完全受战技冷却控制。需在实装方案中明确保留它的收益，或改为同生命期继承盾缺口。",
              "3. 真伤只进入有限池；主动耗血不走可被自己护盾抵消的伤害入口。击溃、斩杀、反伤和普通真伤分别测试，不能把抗真伤等同免疫所有机制。",
              "4. 射线使用独立、明确的普通伤害预算；不能意外继承全局附伤、失血过载、击溃/斩杀、吸血和主弹刷新。当前副武器 power≤0 会回退 2500，不可用填零充当无伤害实现。共享易伤只放大约定伤害部分，不放大 HP 上限击溃；同类不相乘。",
              "5. 模型契约验证不等于 Flash 编译、实际走位碰撞、正式入口复活验收。首轮实测只需同配装满盾录像、完整招式命中与掉盾/掉血、连续两轮、翻滚前后主副弹量。", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=ROOT / "tmp/ti61-jk-20260910")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--refresh-sources", action="store_true", help="re-read FLA and regenerate source attack projection")
    args = parser.parse_args()
    if args.refresh_sources:
        if args.check:
            parser.error("--check does not regenerate derived files")
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "source.json").write_text(json.dumps(jk_source.collect(), ensure_ascii=False, indent=2), encoding="utf-8")
        subprocess.run(["node", str(HERE / "jk_script_sampler.js"), "--source", str(args.out / "source.json"),
                        "--out", str(args.out / "attacks.json"), "--samples", str(CONFIG["seeds"]),
                        "--defence", str(configured()["defence"])], check=True, cwd=ROOT)
    result = produce(args.out / "attacks.json")
    outputs = {"report.json": json.dumps(result, ensure_ascii=False, indent=2) + "\n", "report.md": markdown(result)}
    for name, content in outputs.items():
        path = args.out / name
        if args.check:
            if path.read_text(encoding="utf-8") != content:
                raise SystemExit("model output drift: " + name)
        else:
            args.out.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
    print(json.dumps({"status": "checked" if args.check else "written", "out": str(args.out), "sources": len(result["sourceManifest"]), "attacks": len(result["pressure"]["attacks"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
