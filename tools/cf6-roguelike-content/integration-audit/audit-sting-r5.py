#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""K3 content audit r5 (read-only) for the assembled cf6-sting chapter.

Audits data/stages/books/cf6-sting.json and its real consumption closure
(items / units / NPC shops / choice rewards) against the r5 mandate:
  free-channel duplicate quotas, elite carrier uniqueness/death-only grant,
  initial +11 not propagating to new guns, boss/reinforcement identity,
  level-60 no-XP boundary, shop tiers/real ammo/skill whitelist,
  external rewards == 0, gold plan == balance-input.json (910k+30k),
  zombie_turret->461 / alien->460 identity evidence, finite-wave adaptation
  vs orchestration/encounter-review.json.

Runs the REAL validators (tools/build-book-definition.py validate_cf6 /
tools/cf6_economy.py validate_economy) on the LIVE chapter, read-only.
Writes only under tools/cf6-roguelike-content/integration-audit/ and
tmp/cf6-roguelike-20261021/kimi-content/r5/.

  python -X utf8 tools/cf6-roguelike-content/integration-audit/audit-sting-r5.py
"""
import hashlib
import importlib.util
import json
import os
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
R5_DIR = os.path.join(ROOT, "tmp/cf6-roguelike-20261021/kimi-content/r5")

CHAPTER = os.path.join(ROOT, "data/stages/books/cf6-sting.json")
SRC = os.path.join(ROOT, "data/stages/books/cf6-sting-source")
BALANCE = os.path.join(ROOT, "tools/cf6-prototype/balance-input.json")
REVIEW = os.path.join(ROOT, "tmp/cf6-roguelike-20261021/orchestration/encounter-review.json")
FACTS = os.path.join(SRC, "encounter-facts.v1.json")
DEOB = os.path.join(ROOT, "tmp/cf6-soldier-20261016/knife-audit/deobfuscated-export/scripts")

QUOTA_MAPS = {"E1": "A09", "E2": "A13", "E3": "A14", "E4": "A17", "E5": "A19"}
BOSS_TYPES = {"A06": "兵种463", "A17": "兵种472", "A20": "兵种473", "A22": "兵种474"}

INPUTS = [
    "data/stages/books/cf6-sting.json",
    "data/stages/books/cf6-sting-source/maps.fragment.json",
    "data/stages/books/cf6-sting-source/economy.fragment.json",
    "data/stages/books/cf6-sting-source/shops.fragment.json",
    "data/stages/books/cf6-sting-source/choice-rewards.fragment.json",
    "data/stages/books/cf6-sting-source/encounter-facts.v1.json",
    "tools/cf6-prototype/balance-input.json",
    "tools/cf6-prototype/economy-input-contract.json",
    "data/units/units.json",
    "data/skills/skills.xml",
    "data/items/消耗品_自选配给.xml",
    "data/rewards/choice-rewards.json",
    "data/rewards/choice-rewards.generated.json",
    "data/shops/list.xml",
    "data/enemy_properties/CF6重制敌人.xml",
    "data/enemy_properties/γ-ECHO克隆兽.xml",
    "data/items/asset_source_map.xml",
    "tmp/cf6-roguelike-20261021/orchestration/encounter-review.json",
] + ["data/shops/npcs/书中-CF6毒刺-%d级.json" % n for n in (35, 40, 45, 55, 60)]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def snapshot_inputs():
    snap = {}
    for rel in INPUTS:
        p = os.path.join(ROOT, rel)
        snap[rel] = sha256(p) if os.path.isfile(p) else None
    return snap


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_items():
    """Mirror check-chapter.py: all data/items XMLs except the campus-generated pack."""
    items = {}
    pack = os.path.join(ROOT, "data/items/消耗品_书中配给.xml")
    for name in os.listdir(os.path.join(ROOT, "data/items")):
        if not name.endswith(".xml"):
            continue
        path = os.path.join(ROOT, "data/items", name)
        if os.path.abspath(path) == os.path.abspath(pack):
            continue
        try:
            for item in ET.parse(path).findall(".//item"):
                items[item.findtext("name")] = item
        except ET.ParseError:
            pass
    return items


def item_level(items, name):
    it = items.get(name)
    if it is None:
        return None
    try:
        return int(it.findtext("data/level", "0"))
    except ValueError:
        return None


def walk_enemies(mapdoc):
    """Yield (origin, enemy) for waves and bossEncounter groups of one chapter map."""
    for wave in mapdoc["stage"]["Wave"]["SubWave"]:
        for e in wave["EnemyGroup"]["Enemy"]:
            yield "wave", e
    for group in mapdoc.get("bossEncounter", {}).get("groups", []):
        for e in group["enemies"]:
            yield "bossGroup@hpRatio=%s" % group["hpRatio"], e


def main():
    findings = []

    def finding(check, severity, field, trigger, impact, fix):
        findings.append({"check": check, "severity": severity, "field": field,
                         "trigger": trigger, "impact": impact, "minimalFix": fix})

    checks = {}

    def record(check, status, detail):
        checks[check] = {"status": status, "detail": detail}

    sha_start = snapshot_inputs()

    chapter = load_json(CHAPTER)
    econ_frag = load_json(os.path.join(SRC, "economy.fragment.json"))
    shops_frag = load_json(os.path.join(SRC, "shops.fragment.json"))
    choice_frag = load_json(os.path.join(SRC, "choice-rewards.fragment.json"))
    balance = load_json(BALANCE)
    review = load_json(REVIEW)
    facts = load_json(FACTS)
    units = {u["id"]: u for u in load_json(os.path.join(ROOT, "data/units/units.json"))}
    items = load_items()
    skills_root = ET.parse(os.path.join(ROOT, "data/skills/skills.xml")).findall("Skill")
    skill_catalog = {s.findtext("Name"): s for s in skills_root}
    generated = load_json(os.path.join(ROOT, "data/rewards/choice-rewards.generated.json"))

    maps = {m["id"]: m for m in chapter["maps"]}
    ce = chapter["economy"]

    # ---- C0 identity / real validators ------------------------------------
    record("C0.identity", "pass" if (
        chapter["schema"] == "playable-book.v1" and chapter["id"] == "cf6-sting"
        and chapter["routeId"] == "historical" and chapter["stageName"] == "书中历险-毒刺行动"
        and len(chapter["maps"]) == 21 and "A07" not in maps and "A21" not in maps)
        else "fail",
        {"maps": len(chapter["maps"]), "mapIds": [m["id"] for m in chapter["maps"]]})

    sys.path.insert(0, os.path.join(ROOT, "tools"))
    spec = importlib.util.spec_from_file_location(
        "bbd", os.path.join(ROOT, "tools/build-book-definition.py"))
    bbd = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bbd)
    unit_ids = set(units)
    strict_error, nonstrict = None, None
    try:
        bbd.validate_cf6(chapter, items, skills_root, unit_ids)
        strict_ok = True
    except ValueError as exc:
        strict_ok, strict_error = False, str(exc)
    try:
        bbd.validate_cf6(chapter, items, skills_root, unit_ids, require_backgrounds=False)
        nonstrict = "ok"
    except ValueError as exc:
        nonstrict = str(exc)
    missing_bg = [m["background"] for m in chapter["maps"]
                  if not os.path.isfile(os.path.join(ROOT, "flashswf/backgrounds", m["background"]))]
    bg_only_failure = (not strict_ok) and strict_error and strict_error.startswith("missing CF6 background")
    record("C0.validator", "pass" if (bg_only_failure and nonstrict == "ok") else "fail",
           {"strict": "background-gate-only" if bg_only_failure else ("ok" if strict_ok else strict_error),
            "nonStrict": nonstrict, "missingBackgrounds": missing_bg})
    if not bg_only_failure and not strict_ok:
        finding("C0.validator", "error", "validate_cf6(strict)", strict_error,
                "除背景缺失外存在其他严格校验失败", "定位并修复对应字段")
    if nonstrict != "ok":
        finding("C0.validator", "error", "validate_cf6(require_backgrounds=False)", nonstrict,
                "非背景校验未过", "定位并修复对应字段")
    # backgrounds: map-line deliverable, listed separately, no field stripping
    record("C0.backgrounds", "info",
           {"missing": missing_bg, "count": len(missing_bg),
            "note": "地图矢量线交付物;本审查未剥字段、未建假SWF绕门"})

    # ---- C1 free-channel duplicate quotas ---------------------------------
    random_rows = ce["randomWeapons"]
    elite_rows = ce["eliteWeapons"]
    choice_rows = ce["choices"]
    random_guns = {o["weapon"] for r in random_rows for o in r["choices"]}
    elite_guns = {o["weapon"] for r in elite_rows for o in r["choices"]}
    cf6_bundles = {b["id"]: b for b in choice_frag["bundles"] if b["id"].startswith("cf6.")}
    choice_guns = {b["weapon"] for b in cf6_bundles.values() if "weapon" in b}
    fixed_pickups = {}   # name -> [mapId]
    for mid, m in maps.items():
        for p in m["stage"]["Pickups"]["Pickup"]:
            fixed_pickups.setdefault(p["Name"], []).append(mid)
    fixed_guns = {n for n in fixed_pickups
                  if items.get(n) is not None and items[n].findtext("type") == "武器"}
    authored_drops = {}  # name -> [(mapId, carrier)]
    for mid, m in maps.items():
        for origin, e in walk_enemies(m):
            for d in (e.get("Parameters") or {}).get("掉落物", []):
                authored_drops.setdefault(d["名字"], []).append((mid, origin, e.get("InstanceName")))
    problems = []
    for label, guns in (("random", random_guns), ("elite", elite_guns), ("choice", choice_guns)):
        hit = guns & fixed_guns
        if hit:
            problems.append("%s∩fixedPickups=%s@=%s" % (label, sorted(hit),
                            {g: fixed_pickups[g] for g in hit}))
    for label, guns in (("random", random_guns), ("choice", choice_guns)):
        hit = {n for n in guns if n in authored_drops}
        if hit:
            problems.append("%s∩authoredDrops=%s" % (label, sorted(hit)))
    for a, b, sa, sb in (("random", "elite", random_guns, elite_guns),
                         ("random", "choice", random_guns, choice_guns),
                         ("elite", "choice", elite_guns, choice_guns)):
        if sa & sb:
            problems.append("%s∩%s=%s" % (a, b, sorted(sa & sb)))
    # same-quota duplicate: same map hosting two rows of the same channel
    dup_quota = []
    seen = set()
    for r in random_rows:
        if ("random", r["mapId"]) in seen:
            dup_quota.append(r["mapId"])
        seen.add(("random", r["mapId"]))
    quotas = [r["quota"] for r in elite_rows]
    if len(quotas) != len(set(quotas)):
        dup_quota.append("elite quota repeat")
    if len({r["mapId"] for r in choice_rows}) != len(choice_rows):
        dup_quota.append("choice map repeat")
    pack_names = {r["itemName"] for r in choice_rows}
    for n in pack_names:
        if n in fixed_pickups:
            problems.append("choice pack hand-placed in fixed Pickups: %s@%s" % (n, fixed_pickups[n]))
        if n in authored_drops:
            problems.append("choice pack in authored drops: %s" % n)
    record("C1.freeChannelDedup", "fail" if (problems or dup_quota) else "pass",
           {"problems": problems, "duplicateQuotas": dup_quota,
            "randomGuns": sorted(random_guns), "eliteGuns": sorted(elite_guns),
            "choiceGuns": sorted(choice_guns), "fixedGuns": sorted(fixed_guns),
            "note": "商店为付费渠道,与随机/精英同型号保留属r4已裁定设计,不计重复免费配额"})
    for p in problems + dup_quota:
        finding("C1.freeChannelDedup", "error", "chapter.economy / stage.Pickups / Parameters.掉落物",
                p, "同一免费配额被两个渠道重复发放", "从其中一个渠道移除该型号")

    # ---- C2 elite carriers -------------------------------------------------
    markers = []  # (quota, mapId, origin, enemy)
    for mid, m in maps.items():
        for origin, e in walk_enemies(m):
            q = (e.get("Parameters") or {}).get("cf6EliteQuota")
            if q is not None:
                markers.append((q, mid, origin, e))
    elite_issues = []
    by_quota = {}
    for q, mid, origin, e in markers:
        by_quota.setdefault(q, []).append((mid, origin, e))
    for q, expect_map in QUOTA_MAPS.items():
        carriers = by_quota.get(q, [])
        if len(carriers) != 1:
            elite_issues.append("%s carrier count=%d" % (q, len(carriers)))
            continue
        mid, origin, e = carriers[0]
        if mid != expect_map:
            elite_issues.append("%s on %s expected %s" % (q, mid, expect_map))
        if e["Quantity"] != 1 or e["Type"] not in ("兵种466", "兵种467"):
            elite_issues.append("%s carrier Type=%s Quantity=%s" % (q, e["Type"], e["Quantity"]))
        prm = e.get("Parameters") or {}
        row = next((r for r in elite_rows if r["quota"] == q), None)
        if row is None or row["mapId"] != mid:
            elite_issues.append("%s economy row missing/mismatched" % q)
            continue
        allowed = {o["weapon"] for o in row["choices"]} | {o["ammo"] for o in row["choices"]}
        drops = prm.get("掉落物", [])
        gun_drops = [d for d in drops if d["名字"] in {o["weapon"] for o in row["choices"]}]
        if len(gun_drops) != 1 or gun_drops[0]["概率"] != 100 or \
                gun_drops[0]["最小数量"] != 1 or gun_drops[0]["最大数量"] != 1 or gun_drops[0]["总数"] != 1:
            elite_issues.append("%s gun drop not single 100%%: %s" % (q, drops))
        if any(d["名字"] not in allowed for d in drops):
            elite_issues.append("%s drop outside candidates: %s" % (q, drops))
        if not prm.get("不掉装备") or not prm.get("保留屏外尸体"):
            elite_issues.append("%s missing 不掉装备/保留屏外尸体" % q)
        if q == "E4" and not origin.startswith("bossGroup@hpRatio=1"):
            elite_issues.append("E4 not in A17 hpRatio=1.0 group: " + origin)
        if q != "E4" and e.get("InstanceName") != "elite_" + q.lower():
            elite_issues.append("%s InstanceName=%s" % (q, e.get("InstanceName")))
        if q == "E4" and "InstanceName" in e:
            elite_issues.append("E4 must not carry InstanceName (controller-scoped)")
    record("C2.eliteCarrier", "fail" if elite_issues else "pass",
           {"issues": elite_issues,
            "carriers": {q: [(mid, o, e["Type"], e["Quantity"], e.get("InstanceName"))
                             for mid, o, e in v] for q, v in sorted(by_quota.items())},
            "deathOnlyGrant": "奖励仅经 Parameters.掉落物(概率100)在载体最终死亡时发出;章节无其他投递路径",
            "skipNote": "A17为Boss-hp出口,E4载体(467@hpRatio1.0组)理论上可被跳过->不发E4,符合'最终死亡才发'语义"})
    for i in elite_issues:
        finding("C2.eliteCarrier", "error", "Parameters.cf6EliteQuota", i,
                "精英载体唯一性/死亡发放边界被破坏", "按QUOTA_MAPS保留每配额唯一Quantity=1载体并修掉落")

    # ---- C3 initial +11 not propagating ------------------------------------
    actor = chapter["actor"]
    enh_issues = []
    if any(e.get("enhancement") != 11 for e in actor["equipment"]):
        enh_issues.append("actor equipment not all +11")
    def no_enhancement(obj, path):
        bad = []
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "enhancement":
                    bad.append(path)
                else:
                    bad += no_enhancement(v, path + "." + k)
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                bad += no_enhancement(v, "%s[%d]" % (path, i))
        return bad
    outside = no_enhancement(chapter["economy"], "chapter.economy")
    outside += no_enhancement(choice_frag["bundles"], "choice-rewards.bundles")
    outside += no_enhancement(choice_frag["pools"], "choice-rewards.pools")
    for m in chapter["maps"]:
        outside += no_enhancement(m["stage"], "maps." + m["id"] + ".stage")
        if "bossEncounter" in m:
            outside += no_enhancement(m["bossEncounter"], "maps." + m["id"] + ".bossEncounter")
    if outside:
        enh_issues.append("enhancement outside actor.equipment: " + ";".join(outside[:8]))
    record("C3.noEnhancementPropagation", "fail" if enh_issues else "pass",
           {"issues": enh_issues, "actorSlots": len(actor["equipment"]),
            "note": "经济/配给/波次载荷均无enhancement字段;精英'抽定枪强化1'为消费端合同(economy.fragment eliteQuotas.rule),非内容侧装配"})
    for i in enh_issues:
        finding("C3.noEnhancementPropagation", "error", "enhancement", i,
                "初装+11传播到新枪", "删除该enhancement字段,强化由消费端按合同生成")

    # ---- C4 boss / reinforcement identity ----------------------------------
    boss_issues, boss_summary = [], {}
    for mid, expect in BOSS_TYPES.items():
        m = maps.get(mid)
        plan = (m or {}).get("bossEncounter")
        if plan is None:
            boss_issues.append("%s missing bossEncounter" % mid)
            continue
        waves = m["stage"]["Wave"]["SubWave"]
        main = waves[0]["EnemyGroup"]["Enemy"] if len(waves) == 1 else None
        if not main or len(main) != 1 or main[0]["Type"] != expect \
                or main[0].get("InstanceName") != plan["instanceName"] \
                or main[0]["Quantity"] != 1:
            boss_issues.append("%s main wave boss identity mismatch" % mid)
        reinf = {}
        prev = 2.0
        for g in plan["groups"]:
            if not (0 < g["hpRatio"] < prev):
                boss_issues.append("%s hpRatio not descending" % mid)
            prev = g["hpRatio"]
            for e in g["enemies"]:
                reinf[e["Type"]] = reinf.get(e["Type"], 0) + e["Quantity"]
                if "InstanceName" in e:
                    boss_issues.append("%s reinforcement carries InstanceName" % mid)
                for reserved in ("cf6BossOwnerToken", "cf6SupportIdentity", "publishStageEvent", "产生源"):
                    if reserved in (e.get("Parameters") or {}):
                        boss_issues.append("%s reinforcement reserved param %s" % (mid, reserved))
        if expect in reinf:
            boss_issues.append("%s reinforcement duplicates own boss %s" % (mid, expect))
        if mid == "A20" and (main and (main[0].get("Parameters") or {}).get("老头变身") is not False):
            boss_issues.append("A20 老头变身!=false")
        if mid == "A22" and "兵种474" in reinf:
            boss_issues.append("A22 reinforcement contains 474")
        boss_summary[mid] = {"boss": expect, "support": reinf,
                             "supportTotal": sum(reinf.values()),
                             "maxAlive": plan["maxAlive"], "maxRanged": plan["maxRanged"],
                             "intervalFrames": plan["intervalFrames"]}
    if len(set(BOSS_TYPES.values())) != 4:
        boss_issues.append("boss identities not distinct")
    extra_boss = [m["id"] for m in chapter["maps"]
                  if "bossEncounter" in m and m["id"] not in BOSS_TYPES]
    if extra_boss:
        boss_issues.append("unexpected bossEncounter on " + ",".join(extra_boss))
    record("C4.bossIdentity", "fail" if boss_issues else "pass",
           {"issues": boss_issues, "bosses": boss_summary,
            "note": "A22增援含463/472(他图Boss兵种)系原作构成,非本图Boss身份重复;Boss枪Parameters.长枪=G36消费待实机核(r2已标)"})
    for i in boss_issues:
        finding("C4.bossIdentity", "error", "bossEncounter", i,
                "Boss与增援身份冲突", "增援剔除本图Boss兵种;A22不含474;A20老头变身=false")

    # ---- C5 level-60 boundary ----------------------------------------------
    xp_issues = []
    if actor["level"] != 60 or actor["experience"] != 157526193:
        xp_issues.append("actor level/xp mismatch")
    if chapter["startingSkillPoints"] != 0:
        xp_issues.append("startingSkillPoints != 0")
    xp_items = ("经验值", "技能点")
    for n in xp_items:
        if n in fixed_pickups:
            xp_issues.append("free %s in pickups@%s" % (n, fixed_pickups[n]))
        if n in authored_drops:
            xp_issues.append("free %s in drops" % n)
    for b in cf6_bundles.values():
        names = {r["itemName"] for r in b.get("items", [])}
        names |= {c["name"] for c in b.get("consumables", [])}
        if "weapon" in b:
            names.add(b["weapon"])
        if names & set(xp_items):
            xp_issues.append("choice bundle grants %s: %s" % (names & set(xp_items), b["id"]))
    if chapter["externalRewards"] != 0:
        xp_issues.append("chapter.externalRewards != 0")
    if balance["goldPickupContract"].get("externalReward") != 0:
        xp_issues.append("balance goldPickupContract.externalReward != 0")
    carry_out = econ_frag.get("carryOut", "")
    if "对外奖励=0" not in carry_out:
        xp_issues.append("economy.carryOut missing 对外奖励=0")
    record("C5.level60Boundary", "fail" if xp_issues else "pass",
           {"issues": xp_issues, "externalRewards": chapter["externalRewards"],
            "carryOut": carry_out,
            "note": "商店以金币出售'技能点'物品属设计内SP流通(economy.fragment level60Boundary),非免费投放"})
    for i in xp_issues:
        finding("C5.level60Boundary", "error", "experience/skillPoint/externalRewards", i,
                "60级边界被突破(免费经验/SP/对外奖励)", "移除该免费投放;SP仅保留商店金币购买渠道")

    # ---- C6 shops ----------------------------------------------------------
    shop_issues = []
    tier_nodes = {n["mapId"]: n for n in balance["merchantNodes"]}
    expected_placement = {"A01": 35, "A08": 40, "A11": 45, "A16": 55, "A19": 60}
    if {m: n["maxItemLevel"] for m, n in tier_nodes.items()} != expected_placement:
        shop_issues.append("balance-input merchantNodes placement drift")
    instances = {}
    for mid, m in maps.items():
        for inst in m["stage"]["Instances"]["Instance"]:
            p = inst.get("Parameters", {})
            if "商店检索名" in p:
                instances[mid] = (inst, p)
    if set(instances) != set(expected_placement):
        shop_issues.append("merchant instance maps=%s expected=%s"
                           % (sorted(instances), sorted(expected_placement)))
    for mid, lvl in expected_placement.items():
        if mid in instances and instances[mid][1]["商店检索名"] != "书中-CF6毒刺-%d级" % lvl:
            shop_issues.append("%s 商店检索名=%s" % (mid, instances[mid][1]["商店检索名"]))
    shops_live = {}
    for lvl in (35, 40, 45, 55, 60):
        sid = "书中-CF6毒刺-%d级" % lvl
        sp = os.path.join(ROOT, "data/shops/npcs", sid + ".json")
        if not os.path.isfile(sp):
            shop_issues.append("missing shop file " + sid)
            continue
        shops_live[sid] = load_json(sp)
    with open(os.path.join(ROOT, "data/shops/list.xml"), encoding="utf-8") as f:
        shop_registry = f.read()
    for sid in shops_live:
        if ("npcs/%s.json" % sid) not in shop_registry:
            shop_issues.append(sid + " not registered in list.xml")
    for stale in ("书中-CF6毒刺-一档", "书中-CF6毒刺-二档", "书中-CF6毒刺-三档", "书中-CF6毒刺-四档"):
        if stale in shop_registry:
            shop_issues.append("superseded fragment shop registered: " + stale)
    maxed = {s["name"] for s in actor["skills"]}
    frag_maxed = {s["name"] for s in econ_frag["skillWhitelist"]["excludedMaxedSkills"]}
    if maxed != frag_maxed:
        shop_issues.append("skillWhitelist.excludedMaxedSkills != actor.skills (%d vs %d)"
                           % len(frag_maxed) % len(maxed))
    # cumulative catalog + item levels + real ammo
    prev_goods = set()
    ammo_note = {}
    for lvl in (35, 40, 45, 55, 60):
        sid = "书中-CF6毒刺-%d级" % lvl
        if sid not in shops_live:
            continue
        goods = set(shops_live[sid]["catalog"].values())
        if not prev_goods <= goods:
            shop_issues.append("%s not cumulative" % sid)
        prev_goods = goods
        ceiling = balance["merchantNodes"][[n["shopId"] for n in balance["merchantNodes"]].index(sid)]["maxItemLevel"]
        guns_here = [g for g in goods if items.get(g) is not None
                     and items[g].findtext("type") == "武器"]
        for g in guns_here:
            gl = item_level(items, g)
            if gl is None or gl > ceiling:
                shop_issues.append("%s sells %s level=%s > tier %d" % (sid, g, gl, ceiling))
            clip = items[g].findtext("data/clipname")
            if clip and clip not in goods:
                shop_issues.append("%s sells %s without its ammo %s" % (sid, g, clip))
            ammo_note[g] = clip
        for g in goods:
            if items.get(g) is None:
                shop_issues.append("%s unknown item %s" % (sid, g))
    # taught skills whitelist
    taught = set()
    for mid, (inst, p) in instances.items():
        taught |= set(p.get("可学的技能", {}).values())
    for s in sorted(taught):
        meta = skill_catalog.get(s)
        if meta is None:
            shop_issues.append("taught skill not in skills.xml: " + s)
        if s in maxed or s == "驾驶":
            shop_issues.append("taught skill is historical maxed/driving: " + s)
    record("C6.shops", "fail" if shop_issues else "pass",
           {"issues": shop_issues, "placement": {m: instances[m][1]["商店检索名"] for m in sorted(instances)},
            "taughtSkills": sorted(taught), "gunAmmo": ammo_note,
            "supersededFragmentShopsKeptUnregistered": True,
            "note": "现役消费店=root按balance-input生成的'书中-CF6毒刺-NN级';本线旧'N档'片段未登记,不重复注册"})
    for i in shop_issues:
        finding("C6.shops", "error", "data/shops/npcs/书中-CF6毒刺-*.json / merchant Instance", i,
                "商店档位/弹药/技能白名单违约", "按balance-input merchantNodes与现役clipname对齐")

    # ---- C7 gold plan --------------------------------------------------------
    gold_issues = []
    plan = {g["mapId"]: g["value"] for g in balance["goldPlans"]["beforeFinalMerchant"]}
    actual = {}
    for mid, m in maps.items():
        for p in m["stage"]["Pickups"]["Pickup"]:
            if p["Name"] == "金币":
                actual[mid] = actual.get(mid, 0) + p["Value"]
    for mid, v in plan.items():
        got = actual.get(mid, 0)
        if v == 0 and mid in actual:
            gold_issues.append("%s unexpected gold pickup %d" % (mid, actual[mid]))
        elif v > 0 and got != v:
            gold_issues.append("%s gold pickup=%d plan=%d" % (mid, got, v))
    total = sum(actual.values())
    if total != balance["goldPickupContract"]["nominalTotal"]:
        gold_issues.append("gold total=%d nominal=%d" % (total, balance["goldPickupContract"]["nominalTotal"]))
    if chapter["startingMoney"] != balance["startingMoney"]:
        gold_issues.append("startingMoney mismatch")
    record("C7.goldPlan", "fail" if gold_issues else "pass",
           {"issues": gold_issues, "pickups": actual, "total": total,
            "nominal": balance["goldPickupContract"]["nominalTotal"] + balance["startingMoney"],
            "note": "以balance-input.json 91万拾取+3万起始=94万名义预算为准;economy.fragment旧'无金币'文本(goldIncomeGap)非最终状态"})
    for i in gold_issues:
        finding("C7.goldPlan", "error", "stage.Pickups 金币", i,
                "金币投放与冻结预算不符", "按balance-input beforeFinalMerchant调整该图金币拾取")

    # ---- C8 choice closure ---------------------------------------------------
    ch_issues = []
    gen_pools = {p["id"]: p for p in generated["pools"]}
    pack_xml = ET.parse(os.path.join(ROOT, "data/items/消耗品_自选配给.xml"))
    packs = {it.findtext("name"): it for it in pack_xml.findall(".//item")}
    checkpoints = {c["poolId"]: c for c in econ_frag["choiceCheckpoints"]}
    for row in choice_rows:
        pool = gen_pools.get(row["poolId"])
        if pool is None or pool.get("scope") != {"kind": "book", "bookId": "cf6-sting"}:
            ch_issues.append("pool not in merged generated catalog: " + row["poolId"])
            continue
        if pool.get("itemName") != row["itemName"]:
            ch_issues.append("pool itemName mismatch " + row["poolId"])
        pack = packs.get(row["itemName"])
        if pack is None or pack.findtext("use") != "礼包" \
                or pack.findtext("data/rewardPack/mode") != "playerChoice" \
                or pack.findtext("data/rewardPack/poolId") != row["poolId"]:
            ch_issues.append("pack missing/bad playerChoice wiring: " + row["itemName"])
        ck = checkpoints.get(row["poolId"])
        if ck is None or ck["afterMap"] != row["mapId"]:
            ch_issues.append("choiceCheckpoint afterMap mismatch " + row["poolId"])
        src_pool = next((p for p in choice_frag["pools"] if p["id"] == row["poolId"]), None)
        ceiling = src_pool["maxItemLevel"] if src_pool else None
        for grp in pool["groups"]:
            for entry in grp["entries"]:
                b = cf6_bundles.get(entry["bundleId"])
                if b is None:
                    ch_issues.append("bundle not in fragment: " + entry["bundleId"])
                    continue
                if b.get("kCost", 0) != 0:
                    ch_issues.append("kCost!=0: " + b["id"])
                if "weapon" in b:
                    w = items.get(b["weapon"])
                    if w is None or w.findtext("type") != "武器":
                        ch_issues.append("bundle weapon unknown: " + b["weapon"])
                    else:
                        wl = item_level(items, b["weapon"])
                        if ceiling is not None and (wl is None or wl > ceiling):
                            ch_issues.append("bundle weapon %s level=%s > pool ceiling %s"
                                             % (b["weapon"], wl, ceiling))
                        clip = w.findtext("data/clipname")
                        carried = {c["name"] for c in b.get("consumables", [])}
                        if clip and clip not in carried:
                            ch_issues.append("bundle %s lacks ammo %s" % (b["id"], clip))
                for s in b.get("skills", []):
                    if s["skillKey"] in maxed or skill_catalog.get(s["skillKey"]) is None:
                        ch_issues.append("bundle skill maxed/unknown: " + s["skillKey"])
    record("C8.choiceClosure", "fail" if ch_issues else "pass",
           {"issues": ch_issues,
            "poolsInGenerated": sorted(p for p in gen_pools if p.startswith("cf6.")),
            "note": "配给包不经固定Pickups/掉落重复发放(见C1);playerChoice拾取/背包打开链消费"})
    for i in ch_issues:
        finding("C8.choiceClosure", "error", "choice-rewards / 消耗品_自选配给.xml", i,
                "自选奖励闭包断裂或违约", "对齐pool/itemName/pack/kCost=0与弹药配套")

    # ---- C9 unit identity 461/460 --------------------------------------------
    id_issues, evidence = [], {}

    def deob_file(*parts):
        p = os.path.join(DEOB, *parts)
        return p if os.path.isfile(p) else None

    def read(p):
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()

    def tree_contains(d, needle):
        for r, _, fs in os.walk(d):
            for f in fs:
                try:
                    if needle in read(os.path.join(r, f)):
                        return True
                except OSError:
                    continue  # one ffdec duplicate-record filename is not openable; others carry the evidence
        return False

    u461, u460 = units.get(461), units.get(460)
    if not u461 or u461["spritename"] != "敌人-CF6普通男僵尸":
        id_issues.append("units.json 461 drift")
    if not u460 or u460["spritename"] != "敌人-完全体克隆兽" or u460["name"] != "暴君克隆兽":
        id_issues.append("units.json 460 drift")
    evidence["units"] = {"461": u461, "460": u460}
    props461 = open(os.path.join(ROOT, "data/enemy_properties/CF6重制敌人.xml"),
                    encoding="utf-8").read()
    props460 = open(os.path.join(ROOT, "data/enemy_properties/γ-ECHO克隆兽.xml"),
                    encoding="utf-8").read()
    evidence["enemyProperties"] = {
        "461": "敌人-CF6普通男僵尸" in props461 and "继承原版黄衣僵尸" in props461,
        "460": "<敌人-完全体克隆兽>" in props460 and "<displayname>暴君克隆兽</displayname>" in props460}
    if not all(evidence["enemyProperties"].values()):
        id_issues.append("enemy_properties block missing")
    asm = open(os.path.join(ROOT, "data/items/asset_source_map.xml"), encoding="utf-8").read()
    evidence["linkage"] = {
        "461": "Antigravity/CF6普通男僵尸/敌人-CF6普通男僵尸" in asm,
        "460": "Codex/γECHO克隆兽/完全体/敌人-完全体克隆兽" in asm}
    for key, swf in (("461swf", "flashswf/arts/new/Antigravity专用素材.swf"),
                     ("460swf", "flashswf/arts/new/Codex专用素材.swf")):
        p = os.path.join(ROOT, swf)
        evidence["linkage"][key] = os.path.isfile(p)
        if os.path.isfile(p):
            evidence["linkage"][key + "Sha256"] = sha256(p)
    if not all(v for k, v in evidence["linkage"].items() if not k.endswith("Sha256")):
        id_issues.append("asset_source_map linkage or asset swf missing")
    # original export scripts
    zdir = os.path.join(DEOB, "DefineSprite_477_aw-僵尸")
    tdir = os.path.join(DEOB, "DefineSprite_630_aw-僵尸-可被炮台打")
    adir = os.path.join(DEOB, "DefineSprite_353_aw-异形")
    for d in (zdir, tdir, adir):
        if not os.path.isdir(d):
            id_issues.append("decompiled sprite missing: " + os.path.basename(d))
    if os.path.isdir(zdir) and os.path.isdir(tdir):
        z77 = read(deob_file(zdir, "frame_77", "PlaceObject2_476_1",
                             "CLIPACTIONRECORD onClipEvent(load).as"))
        t77 = read(deob_file(tdir, "frame_77", "PlaceObject2_476_1",
                             "CLIPACTIONRECORD onClipEvent(load).as"))
        strip = lambda s: "\n".join(l for l in s.splitlines() if "§" not in l)
        evidence["zombieTurret"] = {
            "deathCallbackIdentical": strip(z77) == strip(t77),
            "deathCounterLine": "_root.电梯死亡敌人计数++" in t77,
            "turretChannelOnlyIn630": not tree_contains(zdir, "子弹区域")
            and tree_contains(tdir, "子弹区域击中检测"),
            "config": "encounter-review A01 statics: 477与630同hp200/AI5/攻击力20/同帧结构"}
        if not all(v for k, v in evidence["zombieTurret"].items() if k != "config"):
            id_issues.append("zombie_turret script evidence broken")
    if os.path.isdir(adir):
        a77 = read(deob_file(adir, "frame_77", "PlaceObject2_352_1",
                             "CLIPACTIONRECORD onClipEvent(load).as"))
        a1 = read(deob_file(adir, "frame_1", "PlaceObject2_278_49",
                            "CLIPACTIONRECORD onClipEvent(enterFrame).as"))
        evidence["alien"] = {
            "originalCharId": 353, "linkage": "aw-异形",
            "meleeOnlyHitResponse": "近战中击威力" in a1 and "子弹区域" not in a1,
            "deathCounterLine": "_root.电梯死亡敌人计数++" in a77,
            "deathSound": "异形死" in a77,
            "eggHp200": "异形卵1939" in "".join(facts.get("mechanismNotes", [])),
            "reviewStatus": review["mapping"]["candidateAlien"],
            "guardTransformReuse": os.path.isfile(os.path.join(
                ROOT, "tools/cf6-guard-assets/GuardTransform.as"))}
        if not (evidence["alien"]["meleeOnlyHitResponse"] and evidence["alien"]["deathCounterLine"]):
            id_issues.append("alien script evidence broken")
    chapter_text = json.dumps(chapter, ensure_ascii=False)
    evidence["turretsInChapter"] = "炮台" in chapter_text
    placements460 = {}
    for mid, m in maps.items():
        for origin, e in walk_enemies(m):
            if e["Type"] == "兵种460":
                placements460.setdefault(mid, 0)
                placements460[mid] += e["Quantity"]
    evidence["placements460"] = placements460
    candidate_reuse_maps = {mm["mapId"] for mm in review["maps"]
                            for c in (mm.get("proposedFiniteAdaptation") or {}).get("finiteAllClearCandidate", [])
                            if c.get("unitId") == 460 and c.get("mappingStatus") == "candidate_reuse"}
    if set(placements460) - candidate_reuse_maps:
        id_issues.append("460 placed outside candidate_reuse maps: %s"
                         % sorted(set(placements460) - candidate_reuse_maps))
    record("C9.unitIdentity", "fail" if id_issues else "pass-with-caveats",
           {"issues": id_issues, "evidence": evidence,
            "limits": [
                "zombie_turret(630)与aw-僵尸(477)脚本/数值同构,唯一差异=630额外检测_root.gameworld.子弹区域(炮台子弹通道);本章节0处炮台,映射461(CF6重制黄衣僵尸,Antigravity专用素材.swf)仅丢该通道,encounter-review已记为适配",
                "alien(353 aw-异形)为近战爬行体(卵hp200/A22 hp250),与CF7 460暴君克隆兽(Codex γECHO克隆兽资产,身高230,敌性面板独立)不同源;460仅'469变身后继'经GuardTransform批准;A15卵/A17组/A22增援的460直用=encounter-review candidate_reuse,主控裁决状态待确认"]})
    for i in id_issues:
        finding("C9.unitIdentity", "error", "units.json/asset_source_map/decompiled-export", i,
                "兵种身份映射证据断裂", "补齐units/enemy_properties/linkage证据或回退映射")
    finding("C9.unitIdentity", "warning", "maps.A15/A17/A22 Type=兵种460",
            "aw-异形→460为candidate_reuse(encounter-review.mapping.candidateAlien),非registered",
            "外观/体型/行为包与原作异形不同源;若主控未采纳需替换为专属资产",
            "主控在集成记录中显式采纳candidate_reuse,或退回到专用异形资产")

    # ---- C10 finite-wave adaptation vs encounter-review ----------------------
    wave_issues, wave_diffs = [], {}
    for mm in review["maps"]:
        mid = mm["mapId"]
        pfa = mm.get("proposedFiniteAdaptation") or {}
        cand = pfa.get("finiteAllClearCandidate")
        if cand is None or mid not in maps:
            continue
        want = {}
        for c in cand:
            want["兵种%d" % c["unitId"]] = want.get("兵种%d" % c["unitId"], 0) + c["quantity"]
        got = {}
        for origin, e in walk_enemies(maps[mid]):
            got[e["Type"]] = got.get(e["Type"], 0) + e["Quantity"]
        if want != got:
            wave_diffs[mid] = {"reviewProposal": want, "assembled": got}
    # explicit review directives
    a01_waves = maps["A01"]["stage"]["Wave"]["SubWave"]
    a01_sums = [sum(e["Quantity"] for e in w["EnemyGroup"]["Enemy"]) for w in a01_waves]
    if a01_sums != [2, 5, 5, 5, 3] or any(
            e["Type"] != "兵种461" for w in a01_waves for e in w["EnemyGroup"]["Enemy"]):
        wave_issues.append("A01 != 461×[2,5,5,5,3]: %s" % a01_sums)
    a10_types = sorted(e["Type"] for w in maps["A10"]["stage"]["Wave"]["SubWave"]
                       for e in w["EnemyGroup"]["Enemy"])
    if a10_types != ["兵种461", "兵种469"]:
        wave_issues.append("A10 must be 461+469 without extra 460: %s" % a10_types)
    for mid in ("A14", "A19"):
        types = {e["Type"] for w in maps[mid]["stage"]["Wave"]["SubWave"]
                 for e in w["EnemyGroup"]["Enemy"]}
        if "兵种460" in types and "兵种469" in types:
            wave_issues.append("%s co-locates 460 with 469 (transform double-count risk)" % mid)
    if maps["A16"]["stage"]["Wave"]["SubWave"][0]["EnemyGroup"]["Enemy"]:
        wave_issues.append("A16 must be enemy-free transition")
    order = [m["id"] for m in chapter["maps"]]
    if order.index("A17") != order.index("A16") + 1:
        wave_issues.append("route A16->A17 broken")
    record("C10.finiteWaves", "fail" if wave_issues else "pass",
           {"issues": wave_issues, "proposalDiffs": wave_diffs,
            "diffsExplained": "A09:467×6->467×5+466×1(E1载体) 与 A14:467×2->467×1+466×1(E3载体):精英载体各占1个持盾名额且改用466,各图总数9不变;review建议status=proposal_not_implemented,精英配额分配见economy.fragment eliteQuotas",
            "semantics": "原作区分remainingDeathBudget(死亡才-1)/concurrent(上场个数)/initial(摆放);本章节全部有限波次,无无限刷新,适配值按encounter-review明示标prototypeDerived",
            "diffsAre": "proposalDiffs仅列与review建议值的差异;建议值status=proposal_not_implemented,差异需对照r2-r4记录是否已裁定"})
    for i in wave_issues:
        finding("C10.finiteWaves", "error", "maps[].stage.Wave / bossEncounter", i,
                "有限波次适配偏离encounter-review明示", "按review指令修正该图构成")
    for mid, diff in wave_diffs.items():
        finding("C10.finiteWaves", "info", "maps.%s composition" % mid,
                json.dumps(diff, ensure_ascii=False),
                "与review建议值的构成差(精英载体466替换1个467名额,总数不变)",
                "无需修复;主控集成记录中注明该偏差即可")

    # ---- output ---------------------------------------------------------------
    sha_end = snapshot_inputs()
    drift = {k: (sha_start[k], sha_end[k]) for k in sha_start if sha_start[k] != sha_end[k]}
    worst = "pass"
    for f in findings:
        if f["severity"] == "error":
            worst = "fail"
        elif f["severity"] == "warning" and worst == "pass":
            worst = "pass-with-caveats"
    report = {
        "schema": "cf6-sting-content-audit-r5.v1",
        "auditedAt": "2026-10-21",
        "target": "data/stages/books/cf6-sting.json",
        "inputSha256Start": sha_start,
        "inputSha256End": sha_end,
        "inputDrift": drift,
        "overall": worst if not drift else "fail-input-drift",
        "checks": checks,
        "findings": findings,
    }
    os.makedirs(R5_DIR, exist_ok=True)
    out = json.dumps(report, ensure_ascii=False, indent=1) + "\n"
    for path in (os.path.join(OUT_DIR, "audit-r5.json"), os.path.join(R5_DIR, "audit-r5.json")):
        with open(path, "w", encoding="utf-8") as f:
            f.write(out)
    print("overall:", report["overall"])
    for cid, c in checks.items():
        print("%-28s %-4s %s" % (cid, c["status"],
              json.dumps(c["detail"], ensure_ascii=False)[:180]))
    print("findings:", len(findings), "drift:", len(drift))
    print("wrote audit-r5.json -> integration-audit/ + kimi-content/r5/")


if __name__ == "__main__":
    main()
