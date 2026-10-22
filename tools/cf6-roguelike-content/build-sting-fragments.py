#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build cf6-sting route source fragments (maps + economy + shops + choice
rewards) from the sourced encounter fact table and live data (units/items/
skills). Round-2: bossEncounter plans consumable by the Astra controller,
npc-shop.v2 tier shops, choice-rewards.v1 pools mergeable by
tools/choice_reward_catalog.py. Round-4: economy.fragment.json carries
chapterEconomy={randomWeapons,eliteWeapons,choices} per the real consumer
contract tools/cf6-prototype/economy-input-contract.json (static gate:
tools/cf6_economy.validate_economy); elite carriers tagged
Parameters.cf6EliteQuota='E#'; shops carry real level metadata for the
root-scheduled cumulative placement (35@A01/40@A08/45@A11/55@A16/60@A19).
Round-6: applies the explicit CF7 placement adaptation table
(placement-adaptation.v1.json, built by build-placement-adaptation.py) for the
r6 geometry fails — identity-guarded, fact table/original coords untouched.

Usage:
  python -X utf8 tools/cf6-roguelike-content/build-sting-fragments.py           # write fragments
  python -X utf8 tools/cf6-roguelike-content/build-sting-fragments.py --check   # validate only

Inputs (read-only, all live or approved sources):
  data/stages/books/cf6-sting-source/encounter-facts.v1.json   (r2 corrected facts)
  data/stages/books/cf6-sting-source/placement-adaptation.v1.json (r6 geometry fixes)
  data/items/list.xml + data/items/*.xml                       (item index derived live)
  data/units/units.json
  data/skills/skills.xml
  tools/cf6-actor-template/actor.fragment.json                 (actor line authority)
  tools/cf6-tutorial/tutorial-map.fragment.json                (独立矢量教学室)
  tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json    (A01炮塔事实,r15接线输入)
  data/rewards/choice-rewards.json                             (base catalog for merge check)

Outputs (exclusive to this line):
  data/stages/books/cf6-sting-source/maps.fragment.json
  data/stages/books/cf6-sting-source/economy.fragment.json
  data/stages/books/cf6-sting-source/shops.fragment.json
  data/stages/books/cf6-sting-source/choice-rewards.fragment.json
"""
import copy
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = r"C:/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight"
SRC = os.path.join(ROOT, "data/stages/books/cf6-sting-source")
UNITS = os.path.join(ROOT, "data/units/units.json")
SKILLS_XML = os.path.join(ROOT, "data/skills/skills.xml")
ACTOR = os.path.join(ROOT, "tools/cf6-actor-template/actor.fragment.json")
TUTORIAL = os.path.join(ROOT, "tools/cf6-tutorial/tutorial-map.fragment.json")
ITEMS_LIST = os.path.join(ROOT, "data/items/list.xml")
CHOICE_BASE = os.path.join(ROOT, "data/rewards/choice-rewards.json")

# ---------------------------------------------------------------------------
# Original-unit -> current 兵种库 id. Each mapping carries its evidence source.
# ---------------------------------------------------------------------------
UNIT_MAP = {
    "zombie":        {"id": 461, "evidence": "units.json#461 spritename=敌人-CF6普通男僵尸"},
    "zombie_turret": {"id": 461, "evidence": "已验证仅普通僵尸适配:原版aw-僵尸-可被炮台打(charId 630)与aw-僵尸(477)帧结构/脚本/尸体计数同构,唯一差异=炮台子弹受击通道;r15该通道已实接线(A01两门炮塔+逐弹目标过滤,见下方TURRET_FILTER_MARKER与maps.fragment A01.turrets),映射461保留外观/行为/死亡计数语义,由Parameters.目标标记区分受击资格,严禁全体461加标记。主控试作采纳,真实消费者待验", "trialAdopted": True},
    "zombie_f":      {"id": 462, "evidence": "units.json#462 spritename=敌人-CF6女僵尸"},
    "alien":         {"id": 460, "evidence": "主控试作采纳prototype-reuse:异形(charId 353)直接复用现役兵种460(完全体克隆兽/暴君克隆兽);外观/体型/行为包与原作异形明确不同源,不声称原版异形等价;专用异形资产不进入本轮24-48h资产扩张。真实消费者待验", "trialAdopted": True},
    "manman":        {"id": 463, "evidence": "units.json#463 spritename=敌人-CF6蛮蛮"},
    "specop":        {"id": 466, "evidence": "tools/cf6-soldier-assets/README.md 兵种466;Parameters.长枪/特种兵初始阶段有文档"},
    "specop_shield": {"id": 467, "evidence": "tools/cf6-soldier-assets/README.md 兵种467;持盾→无盾为同一逻辑敌人"},
    "thug":          {"id": 468, "evidence": "units.json#468 spritename=敌人-CF6光头保安"},
    "thug_tf":       {"id": 469, "evidence": "units.json#469;原版是否变身=1实例专用;变身后继由469自产,不另发460(encounter-review feedback)"},
    "wings":         {"id": 464, "evidence": "units.json#464 spritename=敌人-CF6Wings"},
    "robot_sword":   {"id": 465, "evidence": "units.json#465 spritename=敌人-CF6大刀机器人"},
    "robot_big":     {"id": 472, "evidence": "units.json#472 spritename=敌人-CF6大头机器人"},
    "oldman_human":  {"id": 473, "evidence": "units.json#473 spritename=敌人-CF6老头人形;Parameters.老头变身有文档(tools/cf6-elder-assets),A20须=false"},
    "oldman_robot":  {"id": 474, "evidence": "units.json#474 spritename=敌人-CF6老头机器人;A22仅主Wave生成"},
}

# 兵种相对档次(同级不同兵种不视为等强),用于图内等级分配
UNIT_TIER = {"alien": 0, "zombie": 1, "zombie_turret": 1, "zombie_f": 1, "thug": 2,
             "thug_tf": 2, "wings": 3, "specop": 3, "specop_shield": 3, "manman": 4,
             "robot_sword": 4, "robot_big": 5, "oldman_human": 6, "oldman_robot": 6}

# 原版gunname -> 现役武器名(仅466/467的Parameters.长枪有资产README文档;其余单位不挂参数,只在sourceNote记录)
GUN_MAP = {"g36": "G36", "ak47": "AK47"}

# CF6 A01 教学炮塔逐弹过滤标记(r15 实接线):炮塔子弹侧携带 仅命中目标标记,
# 目标侧携带 目标标记,由 BulletQueueProcessor 主命中循环/injectHit 逐弹消费。
# 仅 sprite630 等价体(zombie_turret)携带;普通 zombie(sprite477 等价,同为兵种461)
# 绝不携带——来源映射证据 tools/cf6-roguelike-content/integration-audit/result-r5.md:59。
TURRET_FILTER_MARKER = "cf6-a01-turret-zombie"
TURRETS_FRAGMENT = os.path.join(ROOT, "tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json")

# ---------------------------------------------------------------------------
# Design doc §5 level ladder (史实敌人等级候选).
# ---------------------------------------------------------------------------
LEVEL_RANGE = {
    "TUTORIAL": (35, 35), "A01": (35, 36), "A02": (36, 37), "A03": (37, 38),
    "A04": (38, 39), "A05": (39, 40), "A06": (40, 41), "A08": (42, 43),
    "A09": (43, 45), "A10": (44, 46), "A11": (45, 47), "A12": (46, 48),
    "A13": (48, 49), "A14": (49, 51), "A15": (50, 53), "A16": (52, 55),
    "A17": (55, 56), "A18": (56, 59), "A19": (58, 60), "A20": (60, 60),
    "A22": (60, 60),
}
BOSS_LEVEL = {"A06": 42, "A17": 57, "A20": 60, "A22": 60}
BOSS_UNIT = {"A06": "manman", "A17": "robot_big", "A20": "oldman_human", "A22": "oldman_robot"}
MAP_TITLE = {
    "A01": "外围入口", "A02": "废车场", "A03": "室内第一段",
    "A04": "室内第二段", "A05": "室内深处", "A06": "蛮斧刽子手", "A08": "抵达设施",
    "A09": "设施外围", "A10": "第一段升降战", "A11": "实验区入口", "A12": "实验区推进",
    "A13": "第二段升降与盾兵战", "A14": "实验设施深部", "A15": "深部推进",
    "A16": "大头战前整备", "A17": "大头机器人与护卫", "A18": "Wings混合遭遇",
    "A19": "终战前混合精英", "A20": "老头人形战", "A22": "老头机器人战",
}
MAP_ORDER = ["TUTORIAL", "A01", "A02", "A03", "A04", "A05", "A06", "A08", "A09", "A10",
             "A11", "A12", "A13", "A14", "A15", "A16", "A17", "A18", "A19", "A20", "A22"]

# E1-E5 精英配额(设计文档§7;先抽定再装备,最终击杀掉落,替代该阶段免费长枪配额)。
# candidates=§7"先抽定再装备"候选清单(首个=作者态载体装备/掉落,消费端抽定后整枪替换);
# 载体以 Parameters.cf6EliteQuota='E#' 标记(tools/cf6-prototype/economy-input-contract.json)。
ELITES = {
    "A09": {"quota": "E1", "weapon": "SAI GRY 幽灵", "entry": 466,
            "candidates": ["SAI GRY 幽灵"],
            "note": "既有静态带盾特种兵×1转为无盾入口466,占原467名额,图敌人总数不变(设计配额适配;r5核对A09总数9)"},
    "A13": {"quota": "E2", "weapon": "TTI Gen 12", "entry": 467,
            "candidates": ["TTI Gen 12", "T181C"],
            "note": "持盾队长、小Boss;两阶段最终死亡后掉落,不在破盾时发"},
    "A14": {"quota": "E3", "weapon": "HK416战术版", "entry": 466,
            "candidates": ["HK416战术版", "PKM战术版"],
            "note": "既有静态带盾特种兵×2中指定1名转无盾入口466,占原467名额,图敌人总数不变(r5核对A14总数9)"},
    "A17": {"quota": "E4", "weapon": "战术-QBU-191", "entry": 467,
            "candidates": ["战术-QBU-191", "钛合金QJZ171"],
            "note": "持盾重装精英,既有静态带盾特种兵×1;在bossEncounter hpRatio=1组(禁InstanceName,以cf6EliteQuota标记)"},
    "A19": {"quota": "E5", "weapon": "远古诛神枪", "entry": 467,
            "candidates": ["远古诛神枪", "量子能量枪"],
            "note": "终战前强精英,既有静态带盾特种兵×2中指定1名,保留原入口467"},
}
ELITE_QUOTA_MAPS = {ELITES[m]["quota"]: m for m in ELITES}

# 普通随机池节点(设计文档§5/§6;每节点≥2真实长枪候选,候选全局互不重复,
# 且与精英E1-E5候选/自选配给枪/固定补给枪零交集;购买渠道独立,设计明示同型号可
# 同时进采购与随机池:DD MK18战术版/M60E3/AA12丧尸/高斯枪/RShG4)。
# 偏差:§5点名的钛合金P90(A11)与KRISS印花集(A18)现役use=手枪,不满足消费合同
# randomWeapons长枪约束,不进随机池(钛合金P90留商店二档采购);以同级真实长枪补足。
RANDOM_POOLS = {
    "A04": ["DD MK18战术版", "诺亚方舟护士狙击步枪"],
    "A08": ["M60E3", "追月连弩", "NA45"],
    "A11": ["OPDW17EXL", "XM25"],
    "A12": ["AA12丧尸", "非规格步枪"],
    "A17": ["高斯枪", "FSC7"],
    "A18": ["RShG4", "G1111"],
}

# 固定补给(设计文档§5补给职责+§6规则)。位置取原版弃枪/补给箱坐标(native-original)。
# 教学无免费枪:演员模板已装备M4A1战术版+镜之虎彻(主控批准教学版本)。
FIXED_SUPPLIES = {
    "A01": [{"name": "极品UZI战术版", "kind": "gun", "n": 1, "note": "副武器补给(手枪位)"}],
    "A02": [{"name": "AWP", "kind": "gun", "n": 1, "note": "搜索点远距打法"}],
    "A03": [{"name": "AA12战术版", "kind": "gun", "n": 1, "note": "地面近距清场"}],
    "A05": [{"name": "强化石", "kind": "item", "n": 2}, {"name": "普通hp药剂", "kind": "item", "n": 2}],
    "A04": [{"name": "突击步枪通用弹药", "kind": "item", "n": 3, "note": "固定弹药"}],
    "A08": [{"name": "普通hp药剂", "kind": "item", "n": 2}, {"name": "突击步枪通用弹药", "kind": "item", "n": 2}],
    "A10": [{"name": "CAR冲锋枪", "kind": "gun", "n": 1, "note": "到站达45级后提供"}],
    "A12": [{"name": "普通hp药剂", "kind": "item", "n": 1}, {"name": "突击步枪钨芯穿甲弹", "kind": "item", "n": 2}],
    "A15": [{"name": "战术-QBZ-192", "kind": "gun", "n": 1, "note": "图末达52级后提供,手枪位"}],
    "A20": [{"name": "普通hp药剂", "kind": "item", "n": 2}, {"name": "突击步枪钨芯穿甲弹", "kind": "item", "n": 2}],
    "A22": [{"name": "普通hp药剂", "kind": "item", "n": 2, "note": "原版A22救护包×2同位置"}],
}
AMMO_TRIAL_CLIPS = 3

# ---------------------------------------------------------------------------
# Boss 增援计划(Astra控制器确定接口)。有限上限=原自由生成器死亡预算之和,
# 明确是适配(prototypeDerived);Boss死亡即取消未发与现存增援,取消不产奖励。
# 初始杂兵全部放 hpRatio=1 组;主Wave仅Boss一名。ranged=True 仅供maxRanged节流。
# intervalFrames=45:原出兵节奏约22帧/门(frame10→frame24→frame2),并发1;适配取2倍。
# ---------------------------------------------------------------------------
def _sup(key, level, qty, ranged, side, xy=None, params=None):
    e = {"Type": "兵种%d" % UNIT_MAP[key]["id"], "Level": level, "Quantity": qty,
         "ranged": ranged, "SpawnIndex": side}
    if xy is not None:
        e["x"], e["y"] = round(xy[0], 1), round(xy[1], 1)
    if params:
        e["Parameters"] = params
    return e


def boss_plans(item_index):
    """Return {mapId: bossEncounter plan}. x/y 为 native-original 坐标,主控统一变换。"""
    plans = {}

    # ---- A06 蛮蛮(463,L42)。原:2路特种兵(g36)各预算15/并发1 + 5个摆放杂兵。
    spec = lambda side, qty, xy=None: _sup("specop", 41, qty, True, side, xy,
                                           {"长枪": "G36", "特种兵初始阶段": 2})
    plans["A06"] = {
        "instanceName": "cf6Boss_A06", "maxAlive": 2, "maxRanged": 2, "intervalFrames": 45,
        "groups": [
            {"hpRatio": 1.0, "enemies": [
                _sup("zombie", 40, 1, False, "left", [556.45, 263.5]),
                _sup("zombie", 40, 1, False, "left", [417.45, 258.3]),
                _sup("zombie", 40, 1, False, "right", [1264.4, 278.7]),
                _sup("thug", 40, 1, False, "right", [1273.15, 371.15]),
                _sup("thug", 40, 1, False, "left", [366.3, 380.25]),
                spec("left", 1, [5.0, 305.45]), spec("right", 1, [1491.7, 305.45])]},
            {"hpRatio": 0.8, "enemies": [spec("left", 4), spec("right", 4)]},
            {"hpRatio": 0.6, "enemies": [spec("left", 4), spec("right", 4)]},
            {"hpRatio": 0.4, "enemies": [spec("left", 3), spec("right", 3)]},
            {"hpRatio": 0.2, "enemies": [spec("left", 3), spec("right", 3)]},
        ],
        "derivation": "prototypeDerived:特种兵上限30=原两路死亡预算各15(出兵不减预算,实发量unknown);初始2+增援28。摆放5杂兵按原坐标。",
    }

    # ---- A17 大头机器人(472,L57)。原:2路变身保安各15 + 6摆放 + 5卵;E4精英在hpRatio=1组。
    tf = lambda side, qty, xy=None: _sup("thug_tf", 56, qty, False, side, xy)
    e4_ammo = ammo_of(ELITES["A17"]["weapon"], item_index)
    plans["A17"] = {
        "instanceName": "cf6Boss_A17", "maxAlive": 4, "maxRanged": 2, "intervalFrames": 45,
        "groups": [
            {"hpRatio": 1.0, "enemies": [
                _sup("specop_shield", 56, 1, True, "left", [161.1, 372.65], {
                    "称号": "E4精英", "cf6EliteQuota": "E4", "长枪": ELITES["A17"]["weapon"],
                    "不掉装备": True, "保留屏外尸体": True,
                    "掉落物": [
                        {"名字": ELITES["A17"]["weapon"], "概率": 100, "最小数量": 1, "最大数量": 1, "总数": 1},
                        {"名字": e4_ammo, "概率": 100, "最小数量": AMMO_TRIAL_CLIPS,
                         "最大数量": AMMO_TRIAL_CLIPS, "总数": AMMO_TRIAL_CLIPS}]}),
                _sup("robot_sword", 56, 1, False, "left", [112.75, 428.5]),
                _sup("robot_sword", 56, 1, False, "right", [1296.15, 448.4]),
                _sup("thug_tf", 56, 1, False, "left", [247.65, 468.5]),
                _sup("zombie", 55, 1, False, "right", [1365.4, 389.55]),
                _sup("alien", 55, 5, False, "right"),
                tf("left", 1, [4.0, 369.9]), tf("right", 1, [1546.9, 416.3])]},
            {"hpRatio": 0.8, "enemies": [tf("left", 4), tf("right", 4)]},
            {"hpRatio": 0.6, "enemies": [tf("left", 4), tf("right", 4)]},
            {"hpRatio": 0.4, "enemies": [tf("left", 3), tf("right", 3)]},
            {"hpRatio": 0.2, "enemies": [tf("left", 3), tf("right", 3)]},
        ],
        "derivation": "prototypeDerived:变身保安上限31=摆放1+原两路预算各15;异形5=卵数(460主控试作采纳prototype-reuse,外观/体型/行为与原作异形不同源,真实消费者待验);E4精英替代既有静态盾兵。",
    }

    # ---- A20 老头人形(473,L60,变身=false)。原四路:盾5/Wings5/僵尸15/变身保安15。
    shield = lambda side, qty, xy=None: _sup("specop_shield", 60, qty, True, side, xy, {"长枪": "AK47"})
    wing = lambda side, qty, xy=None: _sup("wings", 60, qty, True, side, xy)
    zom = lambda side, qty, xy=None: _sup("zombie", 60, qty, False, side, xy)
    tfg = lambda side, qty, xy=None: _sup("thug_tf", 60, qty, False, side, xy)
    plans["A20"] = {
        "instanceName": "cf6Boss_A20", "maxAlive": 4, "maxRanged": 2, "intervalFrames": 45,
        "groups": [
            {"hpRatio": 1.0, "enemies": [
                shield("left", 2, [185.0, 162.0]), wing("right", 2, [1414.9, 455.7]),
                zom("right", 1, [1103.95, 225.75]), tfg("right", 1, [1250.95, 338.75])]},
            {"hpRatio": 0.75, "enemies": [zom("left", 4), tfg("right", 4), shield("left", 2), wing("right", 2)]},
            {"hpRatio": 0.5, "enemies": [zom("left", 5), tfg("right", 5), shield("left", 1), wing("right", 1)]},
            {"hpRatio": 0.25, "enemies": [zom("left", 5), tfg("right", 5)]},
        ],
        "derivation": "prototypeDerived:四路上限=原各门死亡预算(盾5/Wings5/僵尸15/变身15);原门触发演出(door1/2/4)属机关线,首版按血量阈值发兵。",
    }

    # ---- A22 老头机器人(474,L60,仅主Wave生成)。原四路各15:蛮蛮/大头/异形/大刀。
    man = lambda side, qty, xy=None: _sup("manman", 60, qty, False, side, xy)
    big = lambda side, qty, xy=None: _sup("robot_big", 60, qty, True, side, xy)
    ali = lambda side, qty, xy=None: _sup("alien", 60, qty, False, side, xy)
    swd = lambda side, qty, xy=None: _sup("robot_sword", 60, qty, True, side, xy)
    plans["A22"] = {
        "instanceName": "cf6Boss_A22", "maxAlive": 4, "maxRanged": 2, "intervalFrames": 45,
        "groups": [
            {"hpRatio": 1.0, "enemies": [
                man("right", 1, [1414.9, 455.7]), big("right", 1, [1103.95, 225.75]),
                ali("right", 1, [1250.95, 338.75]), swd("left", 1, [185.0, 162.0])]},
            {"hpRatio": 0.75, "enemies": [man("left", 5), big("right", 5), ali("left", 5), swd("right", 5)]},
            {"hpRatio": 0.5, "enemies": [man("left", 5), big("right", 5), ali("left", 5), swd("right", 5)]},
            {"hpRatio": 0.25, "enemies": [man("left", 4), big("right", 4), ali("left", 4), swd("right", 4)]},
        ],
        "derivation": "prototypeDerived:四路上限各15=原各门死亡预算;474不在增援组(Boss唯一,主Wave生成);异形为460主控试作采纳prototype-reuse(非原版异形等价,真实消费者待验)。",
    }
    return plans


# ---------------------------------------------------------------------------
# 经济/商店/配给候选。
# ---------------------------------------------------------------------------
ECONOMY = {
    "startingMoney": {"value": 30000, "status": "candidate-pending-freeze",
                      "note": "设计文档§12待冻结参数;首版试玩输入"},
    "startingSkillPoints": {"value": 0, "status": "candidate",
                            "note": "史实Andy 35项技能已满级;SP仅作商店购买项流通,不预发"},
}

# 4档商店(npc-shop.v2,独立shopId,主控合入data/shops/npcs/+list.xml)。
# 价格沿data/items真实price;基础货每档相同,枪/弹按档。档位等级区间用于--check。
# level=主控裁定投放等级(累计投放 35@A01/40@A08/45@A11/55@A16/60@A19),
# 避免旧方案A11提前投放50-55档;商品池本轮不变,仅补真实level元数据。
SHOP_TIERS = [
    {"shopId": "书中-CF6毒刺-一档", "title": "迷之盔甲君 · 毒刺一档(35-40)",
     "band": [35, 40], "level": 35, "guns": ["M60E3", "DD MK18战术版"],
     "ammo": ["机枪贫铀穿甲弹", "突击步枪钨芯穿甲弹"],
     "skills": ["寸拳", "旋风腿", "龟派气功", "口才"]},
    {"shopId": "书中-CF6毒刺-二档", "title": "迷之盔甲君 · 毒刺二档(45)",
     "band": [45, 45], "level": 45, "guns": ["钛合金P90", "AA12丧尸"],
     "ammo": ["冲锋枪钢芯穿甲弹", "00号鹿弹"],
     "skills": ["气动波", "裂地拳", "拳脚空中连招", "铁匠"]},
    {"shopId": "书中-CF6毒刺-三档", "title": "迷之盔甲君 · 毒刺三档(50-55)",
     "band": [50, 55], "level": 55, "guns": ["高斯枪", "钛合金QJZ171"],
     "ammo": ["能量电池", "机枪贫铀穿甲弹"],
     "skills": ["兽王崩拳", "径庭拳/黑闪", "内力爆发"]},
    {"shopId": "书中-CF6毒刺-四档", "title": "迷之盔甲君 · 毒刺四档(60)",
     "band": [56, 60], "level": 60, "guns": ["RShG4", "M134暴力版的PIG版"],
     "ammo": ["复合火箭弹弹药", "机枪贫铀穿甲弹"],
     "skills": ["一瞬千击", "觉醒震地", "扭转乾坤"]},
]
SHOP_BASE_GOODS = ["技能点", "K点", "强化石", "普通hp药剂", "突击步枪通用弹药"]
SHOP_MED_HIGH = "大HP药剂"  # 三/四档追加

# map → 商店档位/技能名单/真实投放等级。NPC坐标由主控几何集成,本片段不提供坐标。
# 投放节奏为主控裁定(累计投放):35@A01/40@A08/45@A11/55@A16/60@A19;
# A08累进重开一档(40级档口),高档不提前。
SHOP_SCHEDULE = {"A01": 35, "A08": 40, "A11": 45, "A16": 55, "A19": 60}
SHOP_PLACEMENT = [
    {"map": "A01", "shopId": "书中-CF6毒刺-一档", "level": 35, "note": "开局30000金币首购点"},
    {"map": "A08", "shopId": "书中-CF6毒刺-一档", "level": 40, "note": "A06 Boss战后过场;累计投放(root集成:后续档口累进含前档货)"},
    {"map": "A11", "shopId": "书中-CF6毒刺-二档", "level": 45, "note": "实验区入口过场;45档,不再提前投放50-55档"},
    {"map": "A16", "shopId": "书中-CF6毒刺-三档", "level": 55, "note": "大头战前整备;55档"},
    {"map": "A19", "shopId": "书中-CF6毒刺-四档", "level": 60, "note": "终战前毕业档;60档"},
]

# 自选配给:5个阶段节点(候选,主控加生成与AS2数据接线)。
# 池/捆 ID 必须 cf6. 前缀(choice_reward_catalog.merge_catalogs 强制);kCost 必须为0
# (CF6 prototype 规则),K点价差方案仅作economy文档内的提案保留。
CHOICE_CHECKPOINTS = [
    {"afterMap": "A04", "poolId": "cf6.sting.t1", "levelCeiling": 40, "choiceItem": "书中CF6毒刺自选配给包·一"},
    {"afterMap": "A08", "poolId": "cf6.sting.t2", "levelCeiling": 45, "choiceItem": "书中CF6毒刺自选配给包·二"},
    {"afterMap": "A12", "poolId": "cf6.sting.t3", "levelCeiling": 50, "choiceItem": "书中CF6毒刺自选配给包·三"},
    {"afterMap": "A16", "poolId": "cf6.sting.t4", "levelCeiling": 55, "choiceItem": "书中CF6毒刺自选配给包·四"},
    {"afterMap": "A19", "poolId": "cf6.sting.t5", "levelCeiling": 60, "choiceItem": "书中CF6毒刺自选配给包·五"},
]
# 每池3候选:1枪械装载+1补给捆+1技能捆。枪避开精英E1-E5/固定补给/商店同型。
CHOICE_TIERS = [
    {"tier": "t1", "grade": "low", "gun": "巴雷特",
     "supplies": [{"itemName": "突击步枪通用弹药", "quantity": 6},
                  {"itemName": "普通hp药剂", "quantity": 3},
                  {"itemName": "强化石", "quantity": 2}],
     "skill": "小跳"},
    {"tier": "t2", "grade": "medium", "gun": "G111",
     "supplies": [{"itemName": "00号鹿弹", "quantity": 4},
                  {"itemName": "大HP药剂", "quantity": 1},
                  {"itemName": "强化石", "quantity": 2}],
     "skill": "拳脚攻击"},
    {"tier": "t3", "grade": "medium", "gun": "M134暴力版",
     "supplies": [{"itemName": "机枪贫铀穿甲弹", "quantity": 3},
                  {"itemName": "大HP药剂", "quantity": 2},
                  {"itemName": "强化石", "quantity": 3}],
     "skill": "升龙拳"},
    {"tier": "t4", "grade": "medium", "gun": "战术-QBZ-191",
     "supplies": [{"itemName": "能量电池", "quantity": 3},
                  {"itemName": "大HP药剂", "quantity": 2},
                  {"itemName": "强化石", "quantity": 3}],
     "skill": "聚气"},
    {"tier": "t5", "grade": "high", "gun": "紫色幻想",
     "supplies": [{"itemName": "突击步枪钨芯穿甲弹", "quantity": 6},
                  {"itemName": "大HP药剂", "quantity": 2},
                  {"itemName": "强化石", "quantity": 4}],
     "skill": "霸体"},
]

# K点价差提案(不进merge片段;validator对cf6-sting强制kCost=0,待主控裁决后由生成器放开)
K_COST_PROPOSAL = {
    "status": "proposal-not-in-merged-fragment",
    "note": "参照repair-campus付费卡:高档配给卡可按K点计价(如t4/t5枪卡50-200K点),确认付费才扣K点;现役merge_catalogs对cf6-sting强制kCost=0,需主控裁决后由主控调整生成规则",
    "suggested": [{"poolId": "cf6.sting.t4", "bundleSuffix": "gun", "kCost": 50},
                  {"poolId": "cf6.sting.t5", "bundleSuffix": "gun", "kCost": 200}],
}


def load_json(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# CF7 落点适配表(placement-adaptation.v1.json,由 build-placement-adaptation.py
# 生成;r6 几何失败 6 项=5 个独立落点的有界源数据适配)。原始事实表与原坐标
# 保持历史来源不变;只有身份(map+kind+原坐标+兵种)精确匹配的字段被移动,
# 其余一律原样通过;条目未被消费或重复命中即拒绝生成(不偷偷挪更多敌人)。
# ---------------------------------------------------------------------------
ADAPTATION_FILE = os.path.join(SRC, "placement-adaptation.v1.json")


class Adaptation:
    def __init__(self):
        if not os.path.isfile(ADAPTATION_FILE):
            raise SystemExit("缺 placement-adaptation.v1.json:先运行 "
                             "tools/cf6-roguelike-content/build-placement-adaptation.py;"
                             "不生成未修复 r6 几何失败的片段")
        doc = load_json(ADAPTATION_FILE)
        if doc.get("schema") != "cf6-placement-adaptation.v1":
            raise SystemExit("placement-adaptation schema 不符: %s" % doc.get("schema"))
        self.doc = doc
        self.by_key = {}
        self.consumed = {}
        self.notes = {}
        for e in doc["entries"]:
            key = (e["map"], e["kind"], round(e["originalNative"][0], 1),
                   round(e["originalNative"][1], 1))
            if key in self.by_key:
                raise SystemExit("适配表键重复: %s" % (key,))
            self.by_key[key] = e

    def apply(self, mid, kind, unit_type, xy):
        """Return (xy, note|None)。仅精确身份匹配才移动,其余原样返回。"""
        key = (mid, kind, round(xy[0], 1), round(xy[1], 1))
        e = self.by_key.get(key)
        if e is None:
            return xy, None
        if e["unit"] is not None and unit_type != e["unit"]:
            raise SystemExit("适配身份不符:%s %s 当前Type=%s,表记录=%s;拒绝盲挪"
                             % (mid, e["fieldPath"], unit_type, e["unit"]))
        if key in self.consumed:
            raise SystemExit("适配条目重复命中:%s(%s)" % (e["id"], e["fieldPath"]))
        self.consumed[key] = e["id"]
        note = ("CF7适配[%s]:%s;移至native(%s,%s)=世界(%s,%s),36x18px脚底盒1px栅格"
                "全自由+严格walkBounds内+5px参考格可达,位移%.1fpx;事实表原坐标保留"
                "不改(placement-adaptation.v1.json)"
                % (e["id"], e["reason"], e["newNative"][0], e["newNative"][1],
                   e["targetWorld"][0], e["targetWorld"][1], e["distanceMovedPx"]))
        self.notes.setdefault(mid, []).append(note)
        return list(e["newNative"]), note

    def take_notes(self, mid):
        return self.notes.pop(mid, [])

    def assert_all_consumed(self):
        missing = [e["id"] for k, e in self.by_key.items() if k not in self.consumed]
        if missing:
            raise SystemExit("适配条目未被消费:%s;源点或几何身份已漂移,拒绝生成" % missing)


def load_item_index():
    """从现役 data/items 确定性派生名称索引(不把tmp索引当真源)。"""
    idx = {}
    for entry in ET.parse(ITEMS_LIST).findall("items"):
        path = os.path.join(ROOT, "data/items", entry.text)
        if not os.path.isfile(path):
            continue
        for it in ET.parse(path).findall("item"):
            name = it.findtext("name")
            try:
                price = int(it.findtext("price", "0") or 0)
            except ValueError:
                price = -1  # 如 'pirceless' 等原文本:不可购标记,不参与价格断言
            idx[name] = {"clipname": it.findtext("data/clipname"),
                         "level": int(it.findtext("data/level", "0") or 0),
                         "price": price,
                         "use": it.findtext("use"), "type": it.findtext("type")}
    return idx


def ammo_of(weapon, item_index):
    e = item_index.get(weapon)
    return e["clipname"] if e else None


def enemy(unit_key, level, qty, xy=None, spawn=None, name=None, params=None, interval=None):
    u = UNIT_MAP[unit_key]
    e = {"Type": "兵种%d" % u["id"], "Level": level, "Quantity": qty}
    if interval is not None:
        e["Interval"] = interval
    if xy is not None:
        e["x"], e["y"] = round(xy[0], 1), round(xy[1], 1)
    if spawn is not None:
        e["SpawnIndex"] = spawn
    if name:
        e["InstanceName"] = name
    if params:
        e["Parameters"] = params
    return e


def level_for(map_id, unit_key, boss=False):
    lo, hi = LEVEL_RANGE[map_id]
    if boss:
        return BOSS_LEVEL[map_id]
    t = UNIT_TIER[unit_key]
    if lo == hi:
        return lo
    span = hi - lo
    return lo + min(span, max(0, round(span * t / 3.0)))


def key_of(unit_key, transform):
    if unit_key == "thug" and transform == 1:
        return "thug_tf"
    return unit_key


def gun_params(unit_key, gun):
    """仅466/467的Parameters.长枪有资产README文档;其余单位不挂,记录在note。"""
    if gun and unit_key in ("specop", "specop_shield"):
        p = {"长枪": GUN_MAP[gun]}
        if unit_key == "specop":
            p["特种兵初始阶段"] = 2
        return p
    return None


def elite_enemy(mid, elite, item_index, xy):
    w = elite["weapon"]
    key = "specop" if elite["entry"] == 466 else "specop_shield"
    params = {
        "称号": elite["quota"] + "精英", "cf6EliteQuota": elite["quota"], "长枪": w,
        "不掉装备": True, "保留屏外尸体": True,
        "掉落物": [
            {"名字": w, "概率": 100, "最小数量": 1, "最大数量": 1, "总数": 1},
            {"名字": ammo_of(w, item_index), "概率": 100, "最小数量": AMMO_TRIAL_CLIPS,
             "最大数量": AMMO_TRIAL_CLIPS, "总数": AMMO_TRIAL_CLIPS}],
    }
    if elite["entry"] == 466:
        params["特种兵初始阶段"] = 2
    return enemy(key, level_for(mid, key), 1, xy=xy,
                 name="elite_" + elite["quota"].lower(), params=params)


def build_boss_map(fact, mid, plan, item_index, notes):
    """主Wave仅Boss一名(InstanceName与plan相同);杂兵全在bossEncounter组。"""
    b = fact["boss"]
    params = {"称号": "Boss", "保留屏外尸体": True}
    if mid == "A20":
        params["老头变身"] = False
        notes.append("A20老头人形关闭自动变身(Parameters.老头变身=false,elder-assets文档);A21由机关线演出")
    if b.get("gun"):
        params["长枪"] = GUN_MAP[b["gun"]]
        notes.append("原版boss gunname=%s,候选映射Parameters.长枪=%s;该参数在兵种%d的消费未见资产README文档,待主控实机核"
                     % (b["gun"], GUN_MAP[b["gun"]], UNIT_MAP[BOSS_UNIT[mid]]["id"]))
    boss = enemy(BOSS_UNIT[mid], BOSS_LEVEL[mid], 1, xy=b["xy"],
                 name=plan["instanceName"], params=params)
    stage = {
        "BasicInformation": {"PlayerX": round(fact["spawn"][0], 1), "PlayerY": round(fact["spawn"][1], 1)},
        "Wave": {"SubWave": [{"WaveInformation": {"Duration": 0, "FinishRequirement": 0},
                              "EnemyGroup": {"Enemy": [boss]}}]},
        "Instances": {"Instance": []},
        "Pickups": {"Pickup": build_pickups(fact, mid, item_index, notes)},
    }
    notes.append("Boss死亡即取消未发与现存增援,取消不产奖励(控制器语义);原自由生成器死亡预算仅作有限上限")
    if mid == "A22":
        notes.append("474仅由主Wave生成,增援组不含474")
    if mid == "A17":
        notes.append(ELITES["A17"]["note"])
    return stage


def build_pickups(fact, mid, item_index, notes):
    pickups = []
    supply = FIXED_SUPPLIES.get(mid, [])
    spots = [p["xy"] for p in fact["pickups"] if p.get("xy")] or [[fact["spawn"][0] + 60, fact["spawn"][1]]]
    for i, s in enumerate(supply):
        xy = spots[min(i, len(spots) - 1)]
        pickups.append({"Name": s["name"], "Value": s["n"], "x": round(xy[0], 1), "y": round(xy[1], 1)})
        if s["kind"] == "gun":
            clip = ammo_of(s["name"], item_index)
            if clip:
                pickups.append({"Name": clip, "Value": AMMO_TRIAL_CLIPS,
                                "x": round(xy[0] + 40, 1), "y": round(xy[1], 1)})
        if s.get("note"):
            notes.append("补给 %s:%s" % (s["name"], s["note"]))
    return pickups


def build_regular_map(fact, mid, item_index, notes, adapt):
    subwaves = []
    spawn_points = []
    initial = []
    elite = ELITES.get(mid)
    elite_used = False

    for s in fact["statics"]:
        key = key_of(s["unitKey"], s.get("transform"))
        if elite and not elite_used and s["unitKey"] == "specop_shield":
            ekey = "specop" if elite["entry"] == 466 else "specop_shield"
            xy, _ = adapt.apply(mid, "waveEnemy", "兵种%d" % UNIT_MAP[ekey]["id"], s["xy"])
            initial.append(elite_enemy(mid, elite, item_index, xy))
            elite_used = True
            notes.append("%s: %s" % (elite["quota"], elite["note"]))
            continue
        xy, _ = adapt.apply(mid, "waveEnemy", "兵种%d" % UNIT_MAP[key]["id"], s["xy"])
        params = gun_params(key, s.get("gun"))
        if key == "zombie_turret":
            # sprite630 等价体仅证实存在于 A01;若事实表漂移到他图即拒绝生成(身份守卫)。
            if mid != "A01":
                raise SystemExit("zombie_turret 出现于非A01地图 %s:炮塔过滤标记语义仅限A01,拒绝生成" % mid)
            params = dict(params or {})
            params["目标标记"] = TURRET_FILTER_MARKER
        initial.append(enemy(key, level_for(mid, key), 1, xy=xy, params=params))
        if s.get("gun") and key not in ("specop", "specop_shield"):
            notes.append("原版%s携带%s;该兵种无文档化长枪参数,仅记录不挂参" % (s["unit"], s["gun"]))

    def add_generator_wave(g, target, publish):
        pxy, _ = adapt.apply(mid, "spawnPoint", None, g["xy"])
        spawn_points.append({"x": round(pxy[0], 1), "y": round(pxy[1], 1),
                             "QuantityMax": g["concurrent"]})
        idx = len(spawn_points) - 1
        key = key_of(g["unitKey"], g.get("transform"))
        params = gun_params(key, g.get("gun"))
        if publish:
            params = dict(params or {})
            params["publishStageEvent"] = True
        target.append(enemy(key, level_for(mid, key), g["remainingDeathBudget"],
                            spawn=idx, interval=100, params=params))

    if mid == "A01":
        # 主控裁定:461×20,分组2+5+5+5+3,以20死亡阈值有限化;不称原版固定20。
        # r15修正:原free生成器charId 1585=aw-僵尸-可被炮台打(zombie_turret,预算15/并发5,
        # xy 783.95,323.1),不是普通zombie;按源enemy kind改投zombie_turret并注入目标标记,
        # 普通/女僵尸不加(严禁全体461加标记)。
        for grp in (5, 5, 5, 3):
            spawn_points.append({"x": 783.95, "y": 323.1, "QuantityMax": 5})
            idx = len(spawn_points) - 1
            subwaves.append({"WaveInformation": {"Duration": 0, "FinishRequirement": 0},
                             "EnemyGroup": {"Enemy": [enemy("zombie_turret", level_for(mid, "zombie_turret"), grp,
                                                            spawn=idx, interval=100,
                                                            params={"目标标记": TURRET_FILTER_MARKER})]}})
        notes.append("prototypeDerived:A01=静态2+增援18共20只461(分组5/5/5/3),以原出口20死亡阈值有限化;"
                     "原自由生成器死亡预算15出兵不减、补位不裁,实发量unknown;休眠模板(僵尸15/光头男5)无激活证据不投送")
        notes.append("r15接线:静态630等价体(617.0,319.0)与4组增援均携带Parameters.目标标记=%s;"
                     "A01两门教学炮塔(133.8,202.4)/(249.8,430.9)经Cf6TutorialTurretService逐弹过滤只伤该标记目标"
                     % TURRET_FILTER_MARKER)
    else:
        for g in fact["generators"]:
            if g["initialState"] != "free":
                continue
            publish = mid in ("A03", "A04") and g.get("door") is not None
            add_generator_wave(g, initial, publish)
            if publish:
                notes.append("%s门生成器(%s):波次敌人带Parameters.publishStageEvent=true,木门按实际UnitSpawn播放;坐标为原生门口点"
                             % (g.get("door"), g["unit"]))
            elif g.get("door"):
                notes.append("生成器原挂%s门演出;机关线未接,首版直接生成" % g.get("door"))
    if initial:
        subwaves.insert(0, {"WaveInformation": {"Duration": 0, "FinishRequirement": 0},
                            "EnemyGroup": {"Enemy": initial}})

    # 触发区生成器(1868,仅A09/A14/A18已证实):顺序第二波次(适配,机关线可替换为Trigger)
    for g in fact["generators"]:
        if g["initialState"] != "stopped" or g.get("instance") is None:
            continue
        if not any(t["target"] == g.get("instance") for t in fact["triggerZones"]):
            continue
        wave = []
        add_generator_wave(g, wave, False)
        subwaves.append({"WaveInformation": {"Duration": 0, "FinishRequirement": 0},
                         "EnemyGroup": {"Enemy": wave}})
        notes.append("生成器%s原由触发区(1868)玩家踩区激活,本片段改为顺序第二波次(适配)" % g.get("instance"))

    # 异形卵(A15):每卵1只,原走近触发;候选直接投送,触发演出待机关线
    if fact["alienEggs"]:
        subwaves.append({"WaveInformation": {"Duration": 0, "FinishRequirement": 0},
                         "EnemyGroup": {"Enemy": [enemy("alien", level_for(mid, "alien"),
                                                        fact["alienEggs"], interval=300)]}})
        notes.append("异形卵×%d:原版走近孵化各1只hp200异形;本片段按只数直接投送(460主控试作采纳prototype-reuse,真实消费者待验)" % fact["alienEggs"])

    dormant = [g for g in fact["generators"]
               if g["initialState"] == "stopped"
               and not any(t["target"] == g.get("instance") for t in fact["triggerZones"])]
    if dormant:
        dtxt = ["%s(%s 预算%d/并发%d)" % (g.get("instance") or "未命名", g["unit"],
                                          g["remainingDeathBudget"], g["concurrent"]) for g in dormant]
        notes.append("停止态生成器无脚本触发源(全SWF已穷举),不投送:%s;原版是否可激活=unknown" % ";".join(dtxt))

    if not subwaves:  # 过场图(A08/A16):空波次自动显示通关箭头
        subwaves.append({"WaveInformation": {"Duration": 0, "FinishRequirement": 0},
                         "EnemyGroup": {"Enemy": []}})

    stage = {
        "BasicInformation": {"PlayerX": round(fact["spawn"][0], 1), "PlayerY": round(fact["spawn"][1], 1)},
        "Wave": {"SubWave": subwaves},
        "Instances": {"Instance": []},
        "Pickups": {"Pickup": build_pickups(fact, mid, item_index, notes)},
    }
    if spawn_points:
        stage["SpawnPoint"] = {"Point": spawn_points}
    return stage


def load_turret_block():
    """从 tutorial-turrets.fragment.json 派生 A01 炮塔挂接块(native-original 坐标;
    主控 build-chapter 统一乘 viewport 装配倍率 128/75 一次,本片段不再乘任何倍率)。"""
    doc = load_json(TURRETS_FRAGMENT)
    if doc.get("schema") != "cf6-tutorial-turrets.v1" or doc.get("coordinateSpace") != "native-original":
        raise SystemExit("tutorial-turrets fragment schema/coordinateSpace 不符: %s" % doc.get("schema"))
    if doc["targetMap"]["mapId"] != "A01":
        raise SystemExit("tutorial-turrets fragment 目标图非A01: %s" % doc["targetMap"].get("mapId"))
    sym = doc["turretSymbol"]
    asset = sym["assetSwf"]
    if doc["behaviorOriginal"]["fire"]["function"] != "_root.汽车_子弹区域shoot":
        raise SystemExit("炮塔原作发射入口事实漂移,拒绝生成")
    inst = []
    for i in doc["instances"]:
        if i["facing"] != "right":
            raise SystemExit("炮塔实例朝向事实漂移: %s" % i.get("id"))
        inst.append({"name": i["id"], "x": i["x"], "y": i["y"], "facing": i["facing"]})
    return {
        "coordinateSpace": "native-original",
        "coordinateNote": "x/y为原作native坐标;主控build-chapter统一乘viewport装配倍率128/75一次后写入mechanism.turrets,勿与runtime坐标混用",
        "assetUrl": asset["assetUrl"],
        "linkage": asset["linkage"],
        "filterMarker": TURRET_FILTER_MARKER,
        "fireIntervalFrames": sym["fireCycleFrames"],
        "fireFrameOffset": sym["fireFrame"] - 1,  # 原作帧12(1基)射击 -> 0基偏移11
        "instances": inst,
        "source": "tools/cf6-tutorial-turrets/tutorial-turrets.fragment.json",
    }


def build_maps(facts, item_index, turret_block):
    plans = boss_plans(item_index)
    adapt = Adaptation()
    # bossEncounter 增援落点适配(身份守卫在 apply 内;A20/A22 同坐标分属不同图键)
    for bmid, plan in plans.items():
        for g in plan["groups"]:
            for e in g["enemies"]:
                if "x" in e and "y" in e:
                    xy, _ = adapt.apply(bmid, "bossEnemy", e["Type"], (e["x"], e["y"]))
                    e["x"], e["y"] = round(xy[0], 1), round(xy[1], 1)
    maps = []
    tutorial = load_json(TUTORIAL)
    maps.append({
        "id": "TUTORIAL", "title": tutorial["title"], "background": tutorial["background"],
        "dialogue": tutorial["dialogue"], "stage": tutorial["stage"],
        "sourceNote": {
            "provenance": "tools/cf6-tutorial/tutorial-map.fragment.json（独立教学室装配产物，直接复用）",
            "notes": ["初始M4A1战术版+镜之虎彻已在actor,教学不发第二把枪/其他免费枪",
                      "教学室不安排额外敌人；移动、装备与补给引导后正常出门，首场战斗教学在A01",
                      "教学布局以tools/cf6-tutorial原作几何与素材装配为准；不采用旧事实草案中的教学出生点候选"]},
    })
    for fact in facts["maps"]:
        if fact["id"] == "tutorial":
            continue
        mid = fact["id"]
        notes = []
        if mid in plans:
            plan = plans[mid]
            stage = build_boss_map(fact, mid, plan, item_index, notes)
            notes.append(plan["derivation"])
            dormant = [g for g in fact["generators"] if g["initialState"] == "stopped"]
            if dormant:
                notes.append("停止态模板%d个无激活证据,不投送(unknown)" % len(dormant))
            m = {"id": mid, "title": MAP_TITLE[mid],
                 "background": "cf6/CF6_%s_BG.swf" % mid,
                 "dialogue": fact["dialogue"], "stage": stage,
                 "bossEncounter": {k: plan[k] for k in
                                   ("instanceName", "maxAlive", "maxRanged", "intervalFrames", "groups")}}
        else:
            stage = build_regular_map(fact, mid, item_index, notes, adapt)
            m = {"id": mid, "title": MAP_TITLE[mid],
                 "background": "cf6/CF6_%s_BG.swf" % mid,
                 "dialogue": fact["dialogue"], "stage": stage}
        if mid == "A16":
            notes.append("模板出口需要杀死数0→a12为复制模板;对白链实际目标a17(encounter-review确认);章节按路线顺序A16→A17,不回A12")
        if mid == "A01":
            m["turrets"] = turret_block
        notes.extend(adapt.take_notes(mid))
        m["sourceNote"] = {
            "coordinateSpace": "native-original",
            "originalWorldSprite": fact["worldSprite"],
            "exitRule": fact["exits"],
            "originalKillThreshold": fact["exits"][0].get("required") if fact["exits"] else None,
            "levelRange": list(LEVEL_RANGE[mid]),
            "notes": notes,
        }
        maps.append(m)
    order = {m: i for i, m in enumerate(MAP_ORDER)}
    maps.sort(key=lambda m: order[m["id"]])
    adapt.assert_all_consumed()
    return {
        "schema": "cf6-sting-maps.v2",
        "status": "candidate",
        "coordinateSpace": "native-original",
        "coordinateNote": "全部spawn/敌人/拾取/生成点x/y均为原版native坐标;主控最终集成时统一变换一次,不要与runtime-index已变换坐标混用",
        "placementAdaptation": {
            "file": "placement-adaptation.v1.json", "schema": "cf6-placement-adaptation.v1",
            "applied": len(adapt.consumed),
            "status": "adopted-trial(主控试作采纳;真实消费者待验,不称原作完全复现)",
            "note": "r6几何失败5落点的有界源数据适配(原字段路径/原坐标/目的世界坐标/反算native/碰撞理由见该文件);"
                    "事实表与原坐标保持历史来源不变;未适配项(A06/A17屏外对称增援、A17 Boss原作高度、教学既有门)"
                    "保持不改,列该文件unchangedPendingOnMachine实机待核"},
        "chapterContract": {"schema": "playable-book.v1", "id": "cf6-sting", "routeId": "historical",
                            "stageName": "书中历险-毒刺行动"},
        "actorSource": "tools/cf6-actor-template/actor.fragment.json (主控集成时并入)",
        "merchantNote": "商人NPC不进maps:坐标由主控几何集成;模板与落点见shops.fragment.json",
        "maps": maps,
    }


def build_shops(item_index, skill_catalog):
    shops = []
    for tier in SHOP_TIERS:
        catalog = {}
        goods = list(SHOP_BASE_GOODS)
        if tier["band"][0] >= 50:
            goods.append(SHOP_MED_HIGH)
        goods += tier["guns"] + tier["ammo"]
        for i, name in enumerate(goods):
            catalog[str(i)] = name
        shops.append({"schema": "npc-shop.v2", "shopId": tier["shopId"],
                      "title": tier["title"], "level": tier["level"],
                      "goodsLevels": {n: item_index[n]["level"] for n in goods},
                      "catalog": catalog})
    placement = []
    for p in SHOP_PLACEMENT:
        tier = next(t for t in SHOP_TIERS if t["shopId"] == p["shopId"])
        trainer = {str(i): s for i, s in enumerate(tier["skills"])}
        placement.append({
            "map": p["map"], "shopId": p["shopId"], "level": p["level"], "note": p["note"],
            "skills": tier["skills"],
            "instanceTemplate": {
                "Identifier": "生存战-迷之盔甲君",
                "x": None, "y": None,
                "coordinateStatus": "pending-geometry-integration(主控求合法点后填;本片段不提供伪坐标)",
                "Parameters": {"商店检索名": tier["shopId"], "技能检索名": tier["shopId"],
                               "可学的技能": trainer, "任务名": tier["shopId"], "默认对话": []}},
        })
    return {
        "schema": "cf6-sting-shops.v2",
        "status": "candidate-consumable",
        "consumeContract": "每档为完整npc-shop.v2,主控合入data/shops/npcs/<shopId>.json并在data/shops/list.xml登记;分类走默认自动分类;价格=data/items真实price",
        "placementSchedule": "主控裁定累计投放:35@A01/40@A08/45@A11/55@A16/60@A19;level/goodsLevels为真实等级元数据(data/items派生),商品池本轮不变",
        "purchaseChain": "技能点/K点/强化石均为data/items现役物品(use=货币/材料),沿现役商店购买链金币消费;与书中-迷之盔甲君在售强化石同链,无新链路",
        "shops": shops,
        "placement": placement,
    }


def build_choice_fragment(item_index, skill_catalog, actor_skill_names):
    bundles = []
    pools = []
    tier_no = {"t1": "一", "t2": "二", "t3": "三", "t4": "四", "t5": "五"}
    for t in CHOICE_TIERS:
        cp = next(c for c in CHOICE_CHECKPOINTS if c["poolId"] == "cf6.sting." + t["tier"])
        gun = t["gun"]
        clip = ammo_of(gun, item_index)
        gun_bundle = {
            "id": "cf6.sting.%s.gun" % t["tier"],
            "name": "毒刺%s枪械捆" % tier_no[t["tier"]],
            "title": "%s 装载" % gun,
            "description": "%s一把,附配套弹药与急救。史实候选,未实测平衡。" % gun,
            "grade": t["grade"],
            "weapon": gun, "mods": [],
            "consumables": [{"name": clip, "count": 6}, {"name": "普通hp药剂", "count": 2}],
        }
        supply_bundle = {
            "id": "cf6.sting.%s.supply" % t["tier"],
            "name": "毒刺%s补给捆" % tier_no[t["tier"]],
            "title": "阶段补给 · %s" % tier_no[t["tier"]],
            "description": "弹药/治疗/强化石组合,按阶段梯度。",
            "grade": t["grade"],
            "items": t["supplies"],
        }
        skill_bundle = {
            "id": "cf6.sting.%s.skill" % t["tier"],
            "name": "毒刺%s技能捆" % tier_no[t["tier"]],
            "title": "技能传授 · %s" % t["skill"],
            "description": "直接传授1级%s(史实Andy未满技能)。" % t["skill"],
            "grade": t["grade"],
            "items": [],
            "skills": [{"skillKey": t["skill"], "level": 1}],
        }
        bundles += [gun_bundle, supply_bundle, skill_bundle]
        pools.append({
            "id": cp["poolId"], "version": 1,
            "title": "毒刺行动 · 阶段配给%s" % tier_no[t["tier"]],
            "itemName": cp["choiceItem"],
            "scope": {"kind": "book", "bookId": "cf6-sting"},
            "maxItemLevel": cp["levelCeiling"],
            "chooseCount": 1, "rerolls": 0,
            "groups": [{"id": "main", "draw": 3, "entries": [
                {"bundleId": gun_bundle["id"], "weight": 1},
                {"bundleId": supply_bundle["id"], "weight": 1},
                {"bundleId": skill_bundle["id"], "weight": 1}]}],
        })
    return {"schema": "choice-rewards.v1", "bundles": bundles, "pools": pools}


def _weapon_choices(weapons, item_index):
    """消费合同候选行:ammo=现役data/clipname,ammoCount=包装少量试用(3弹匣)。"""
    return [{"weapon": w, "ammo": ammo_of(w, item_index), "ammoCount": AMMO_TRIAL_CLIPS}
            for w in weapons]


def build_economy(actor_skills, item_index):
    budget = []
    shop_by_map = {p["map"]: p for p in SHOP_PLACEMENT}
    choice_by_map = {c["afterMap"]: c for c in CHOICE_CHECKPOINTS}
    for mid in MAP_ORDER:
        if mid == "TUTORIAL":
            continue
        row = {"map": mid,
               "guaranteedGold": 0,
               "fixedSupplies": [s["name"] + ("×%d" % s["n"] if s["n"] > 1 else "")
                                 for s in FIXED_SUPPLIES.get(mid, [])],
               "randomPool": RANDOM_POOLS.get(mid),
               "elite": None, "shopTier": None, "shopLevel": None, "choiceNode": None}
        if mid in shop_by_map:
            row["shopTier"] = shop_by_map[mid]["shopId"]
            row["shopLevel"] = shop_by_map[mid]["level"]
        if mid in ELITES:
            row["elite"] = "%s:%s" % (ELITES[mid]["quota"], "/".join(ELITES[mid]["candidates"]))
        if mid in choice_by_map:
            c = choice_by_map[mid]
            row["choiceNode"] = {"poolId": c["poolId"], "choiceItem": c["choiceItem"],
                                 "levelCeiling": c["levelCeiling"], "candidates": 3}
        budget.append(row)
    # 主控合并对象:chapter.economy 原值=chapterEconomy,三数组严格按
    # tools/cf6-prototype/economy-input-contract.json(cf6-economy-input.v1);
    # Astra静态门=tools/cf6_economy.validate_economy。
    chapter_economy = {
        "randomWeapons": [{"mapId": mid, "choices": _weapon_choices(RANDOM_POOLS[mid], item_index)}
                          for mid in MAP_ORDER if mid in RANDOM_POOLS],
        "eliteWeapons": [{"mapId": ELITE_QUOTA_MAPS[q], "quota": q,
                          "choices": _weapon_choices(ELITES[ELITE_QUOTA_MAPS[q]]["candidates"], item_index)}
                         for q in ("E1", "E2", "E3", "E4", "E5")],
        "choices": [{"mapId": c["afterMap"], "poolId": c["poolId"], "itemName": c["choiceItem"]}
                    for c in CHOICE_CHECKPOINTS],
    }
    return {
        "schema": "cf6-sting-economy.v3",
        "status": "candidate-not-balanced",
        "chapterEconomy": chapter_economy,
        "chapterEconomyContract": "tools/cf6-prototype/economy-input-contract.json(cf6-economy-input.v1):"
                                  "randomWeapons每图一行2..16候选/eliteWeapons=E1..E5配额(E1可1候选,E2-E5≥2)/choices=5池exact mapId+poolId+itemName;"
                                  "精英候选不进随机/配给/固定拾取,随机候选跨图不重复;种子抽取与装配归BookRunRules+Astra消费端",
        "lever": {"currency": "金币",
                  "unitPrices": {"技能点": item_index["技能点"]["price"],
                                 "K点": item_index["K点"]["price"],
                                 "强化石": item_index["强化石"]["price"]},
                  "source": "data/items/消耗品_货币.xml,收集品_材料.xml 真实price"},
        "startingMoney": ECONOMY["startingMoney"],
        "startingSkillPoints": ECONOMY["startingSkillPoints"],
        "level60Boundary": "actor固定60级/经验157526193;maps无任何经验值/技能点掉落,局外不发经验/SP;SP仅经商店金币购买技能点物品流通",
        "goldIncomeGap": "maps未作者金币掉落:逐图保证金币=0。金币总账由root+Astra另行冻结balance-input.json"
                         "(入口原生拾取总量候选91万+起始3万);本线不重复加金币、不改经济单价,勿当已平衡",
        "leverExample": "例:档1购M60E3(390000)远超30000起始金,印证金币产出依赖balance-input总账;"
                        "档内可及项:技能点×20=30000,或强化石×100=30000(单杠杆折算,未实测)",
        "shopsRef": "shops.fragment.json(4档npc-shop.v2+NPC模板+落点;真实level元数据,主控累计投放35@A01/40@A08/45@A11/55@A16/60@A19)",
        "choiceRewardsRef": "choice-rewards.fragment.json(choice_reward_catalog.BOOK_SOURCES已登记该路径,merge即校验)",
        "choiceCheckpoints": [dict(c, note="配给包物品已在data/items/消耗品_自选配给.xml(use=礼包,主控已生成);"
                                           "投递靠既有playerChoice拾取/背包打开链,本线不向固定Pickups手塞同一包")
                              for c in CHOICE_CHECKPOINTS],
        "kPointPricingProposal": K_COST_PROPOSAL,
        "mapBudget": budget,
        "eliteQuotas": {k: {"quota": v["quota"], "weapon": v["weapon"], "candidates": v["candidates"], "map": k,
                            "rule": "先抽定再装备,最终击杀掉落所持同型号,替代该阶段免费长枪配额,不另放武器箱;"
                                    "载体Parameters.cf6EliteQuota=%s;消费端替换其武器/弹药掉落为抽定枪强化1+配套弹药,不混金币/其他奖励"
                                    % v["quota"]}
                        for k, v in ELITES.items()},
        "skillWhitelist": {
            "rule": "史实Andy已满级技能不进商店/配给;按NPC固定清单(35项)排除,与显示名无关",
            "excludedMaxedSkills": actor_skills,
        },
        "carryOut": "对外奖励=0;局内金币/K点/经验/技能不带出",
    }


def check(maps_doc, econ, shops_doc, choice_frag, item_index, units, actor, skill_catalog,
          turret_block):
    errors = []
    warns = []
    unit_ids = {u["id"] for u in units}
    for key, u in UNIT_MAP.items():
        if u["id"] not in unit_ids:
            errors.append("UNIT_MAP %s -> 兵种%d 不存在" % (key, u["id"]))
        if u.get("trialAdopted"):
            warns.append("主控试作采纳映射(真实消费者待验):%s->兵种%d" % (key, u["id"]))
    a = actor["actor"]
    if a["level"] != 60 or a["experience"] != 157526193:
        errors.append("actor level/experience 不符合同")
    for e in a["equipment"]:
        if e["enhancement"] != 11:
            errors.append("actor equipment %s 强化!=11" % e["name"])
    ids = [m["id"] for m in maps_doc["maps"]]
    if ids != MAP_ORDER:
        errors.append("maps顺序不符: %s" % ids)
    # --- 落点适配已应用(坐标级断言;几何重验归 build-placement-adaptation.py --check) ---
    adoc = load_json(ADAPTATION_FILE)
    pa = maps_doc.get("placementAdaptation") or {}
    if pa.get("schema") != "cf6-placement-adaptation.v1" or pa.get("applied") != len(adoc["entries"]):
        errors.append("placementAdaptation 汇总与适配表不符: %s" % pa)
    mmap = {m["id"]: m for m in maps_doc["maps"]}

    def _resolve(doc, path):
        node = doc
        for tok in path.split("."):
            mm = re.match(r"^([^\[\]]+)((?:\[\d+\])*)$", tok)
            node = node[mm.group(1)]
            for i in re.findall(r"\[(\d+)\]", mm.group(2)):
                node = node[int(i)]
        return node

    for e in adoc["entries"]:
        cur = _resolve(mmap[e["map"]], e["fieldPath"])
        if abs(cur.get("x", -1) - e["newNative"][0]) > 0.051 \
                or abs(cur.get("y", -1) - e["newNative"][1]) > 0.051:
            errors.append("%s %s 未应用适配(当前%s,%s;应%s,%s)"
                          % (e["map"], e["fieldPath"], cur.get("x"), cur.get("y"),
                             e["newNative"][0], e["newNative"][1]))
    elite_weapons = {w: k for k, v in ELITES.items() for w in v["candidates"]}
    supply_guns = {s["name"] for v in FIXED_SUPPLIES.values() for s in v if s["kind"] == "gun"}
    choice_guns = [b["weapon"] for b in choice_frag["bundles"] if "weapon" in b]
    choice_items = {c["choiceItem"] for c in CHOICE_CHECKPOINTS}
    boss_ids = {"A06", "A17", "A20", "A22"}

    # --- chapterEconomy 消费合同(tools/cf6-prototype/economy-input-contract.json,
    #     静态门=tools/cf6_economy.validate_economy;此处镜像同约束,不另立口径) ---
    ce = econ.get("chapterEconomy") or {}
    if set(ce) != {"randomWeapons", "eliteWeapons", "choices"}:
        errors.append("chapterEconomy字段集不符(应恰为randomWeapons/eliteWeapons/choices)")
    map_id_set = set(MAP_ORDER)

    def check_weapon_options(mid, options, minimum, where):
        names = set()
        if type(options) is not list or not minimum <= len(options) <= 16:
            errors.append("%s %s候选数越界(需%d..16)" % (mid, where, minimum))
            return names
        lo, hi = LEVEL_RANGE.get(mid, (1, 60))
        for opt in options:
            if set(opt) != {"weapon", "ammo", "ammoCount"}:
                errors.append("%s %s候选字段集不符" % (mid, where))
                continue
            w = opt["weapon"]
            e = item_index.get(w)
            if e is None or e["type"] != "武器" or e["use"] != "长枪":
                errors.append("%s %s非现役长枪: %s" % (mid, where, w))
                continue
            if not (1 <= e["level"] <= 60):
                errors.append("%s %s武器等级越界: %s(%d)" % (mid, where, w, e["level"]))
            if where == "randomWeapons" and not (lo - 5 <= e["level"] <= hi):
                errors.append("%s %s候选%s等级%d偏离关卡梯度%s" % (mid, where, w, e["level"], (lo, hi)))
            if opt["ammo"] != e["clipname"]:
                errors.append("%s %s弹药与clipname不符: %s" % (mid, where, w))
            am = item_index.get(opt["ammo"])
            if am is None or am["use"] != "弹夹":
                errors.append("%s %s弹药非现役弹夹: %s" % (mid, where, opt["ammo"]))
            if type(opt["ammoCount"]) is not int or not 1 <= opt["ammoCount"] <= 30:
                errors.append("%s %s ammoCount越界: %s" % (mid, where, opt["ammoCount"]))
            if w in names:
                errors.append("%s %s候选重复: %s" % (mid, where, w))
            names.add(w)
        return names

    random_names = set()
    seen_random_maps = set()
    for row in ce.get("randomWeapons", []):
        if set(row) != {"mapId", "choices"}:
            errors.append("randomWeapons行字段集不符: %s" % row.get("mapId"))
            continue
        mid = row["mapId"]
        if mid not in map_id_set or mid in seen_random_maps:
            errors.append("randomWeapons未知/重复mapId: %s" % mid)
        seen_random_maps.add(mid)
        if mid not in RANDOM_POOLS or [o["weapon"] for o in row["choices"]] != RANDOM_POOLS[mid]:
            errors.append("randomWeapons %s与RANDOM_POOLS真源不符" % mid)
        names = check_weapon_options(mid, row["choices"], 2, "randomWeapons")
        for w in names:
            if w in elite_weapons or w in random_names:
                errors.append("randomWeapons %s与精英/他图随机候选重复: %s" % (mid, w))
            if w in supply_guns or w in choice_guns:
                errors.append("randomWeapons %s与固定补给/配给枪重复: %s" % (mid, w))
        random_names |= names

    seen_quotas = set()
    for row in ce.get("eliteWeapons", []):
        if set(row) != {"mapId", "quota", "choices"}:
            errors.append("eliteWeapons行字段集不符: %s" % row.get("quota"))
            continue
        q = row["quota"]
        if q not in ELITE_QUOTA_MAPS or q in seen_quotas or row["mapId"] != ELITE_QUOTA_MAPS[q]:
            errors.append("eliteWeapons quota未知/重复/落图不符: %s@%s" % (q, row["mapId"]))
            continue
        seen_quotas.add(q)
        expected = ELITES[row["mapId"]]["candidates"]
        if [o["weapon"] for o in row["choices"]] != expected:
            errors.append("eliteWeapons %s候选与ELITES真源(设计§7)不符" % q)
        check_weapon_options(row["mapId"], row["choices"], 1 if q == "E1" else 2, "eliteWeapons")
    if seen_quotas != set(ELITE_QUOTA_MAPS):
        errors.append("eliteWeapons缺配额行: %s" % (set(ELITE_QUOTA_MAPS) - seen_quotas))

    pool_by_id = {p["id"]: p for p in choice_frag["pools"]}
    seen_choice_maps, seen_choice_pools = set(), set()
    for row in ce.get("choices", []):
        if set(row) != {"mapId", "poolId", "itemName"}:
            errors.append("choices行字段集不符: %s" % row.get("poolId"))
            continue
        if (row["mapId"] not in map_id_set or row["mapId"] in seen_choice_maps
                or row["poolId"] in seen_choice_pools):
            errors.append("choices未知/重复投递: %s@%s" % (row["poolId"], row["mapId"]))
        seen_choice_maps.add(row["mapId"])
        seen_choice_pools.add(row["poolId"])
        pool = pool_by_id.get(row["poolId"])
        if pool is None or pool["itemName"] != row["itemName"] \
                or pool["scope"] != {"kind": "book", "bookId": "cf6-sting"}:
            errors.append("choices池身份/scope不符: %s" % row["poolId"])
    if seen_choice_pools != set(pool_by_id):
        errors.append("choices未覆盖全部cf6-sting池: %s" % (set(pool_by_id) - seen_choice_pools))

    for m in maps_doc["maps"]:
        mid = m["id"]
        bg_expect = "cf6/CF6_Tutorial_BG.swf" if mid == "TUTORIAL" else "cf6/CF6_%s_BG.swf" % mid
        if m["background"] != bg_expect:
            errors.append("%s background 不符: %s" % (mid, m["background"]))
        sw = m["stage"]["Wave"]["SubWave"]
        if not (1 <= len(sw) <= 64):
            errors.append("%s SubWave数越界" % mid)
        if m["stage"]["BasicInformation"].get("BookBoss") is not None:
            errors.append("%s 含BookBoss" % mid)

        def scan_enemy(e, where, in_boss_plan):
            if not e["Type"].startswith("兵种") or int(e["Type"][2:]) not in unit_ids:
                errors.append("%s 非法Type %s" % (mid, e["Type"]))
            if not (1 <= e["Level"] <= 60):
                errors.append("%s 等级越界 %s" % (mid, e["Level"]))
            params = e.get("Parameters") or {}
            gun = params.get("长枪")
            if gun and gun not in item_index:
                errors.append("%s %s长枪不存在: %s" % (mid, where, gun))
            for d in params.get("掉落物") or []:
                if d["名字"] not in item_index:
                    errors.append("%s %s掉落物不存在: %s" % (mid, where, d["名字"]))
                if d["名字"] in ("经验值", "技能点"):
                    errors.append("%s %s违反60级边界:掉落%s" % (mid, where, d["名字"]))
                if "cf6EliteQuota" not in params and (
                        d["名字"] in elite_weapons or d["名字"] in random_names or d["名字"] in choice_items):
                    errors.append("%s %s非精英掉落侵占随机/精英/配给来源: %s" % (mid, where, d["名字"]))
            if in_boss_plan:
                if set(e) - {"Type", "Level", "Quantity", "ranged", "SpawnIndex", "x", "y", "Parameters"}:
                    errors.append("%s %s增援含保留字段" % (mid, where))
                if type(e.get("ranged")) is not bool:
                    errors.append("%s %s增援缺ranged布尔" % (mid, where))
                if any(k in params for k in ("cf6BossOwnerToken", "cf6SupportIdentity",
                                             "publishStageEvent", "产生源", "InstanceName")):
                    errors.append("%s %s增援Parameters含保留键" % (mid, where))

        for w in sw:
            for e in w["EnemyGroup"]["Enemy"]:
                scan_enemy(e, "wave", False)
        for p in m["stage"]["Pickups"]["Pickup"]:
            if p["Name"] not in item_index:
                errors.append("%s 拾取物不存在: %s" % (mid, p["Name"]))
            if p["Name"] in elite_weapons:
                errors.append("%s 精英武器%s重复放箱" % (mid, p["Name"]))
            if p["Name"] in random_names:
                errors.append("%s 固定拾取与随机池武器重复: %s" % (mid, p["Name"]))
            if p["Name"] in choice_items:
                errors.append("%s 配给包手塞进固定拾取: %s" % (mid, p["Name"]))
        for line in m["dialogue"]:
            if not (1 <= len(line["text"]) <= 160) or len(line["speaker"]) > 40:
                errors.append("%s 对话越界" % mid)
        # --- bossEncounter 合同 ---
        if mid in boss_ids:
            plan = m.get("bossEncounter")
            if plan is None:
                errors.append("%s 缺bossEncounter" % mid)
                continue
            if set(plan) != {"instanceName", "maxAlive", "maxRanged", "intervalFrames", "groups"}:
                errors.append("%s bossEncounter字段集不符" % mid)
            if plan["instanceName"] != "cf6Boss_" + mid:
                errors.append("%s instanceName不符" % mid)
            if not (1 <= plan["maxAlive"] <= 8 and 0 <= plan["maxRanged"] <= plan["maxAlive"]
                    and 1 <= plan["intervalFrames"] <= 1800):
                errors.append("%s boss cap/interval越界" % mid)
            if len(sw) != 1 or len(sw[0]["EnemyGroup"]["Enemy"]) != 1:
                errors.append("%s 主Wave非单Boss" % mid)
            else:
                b = sw[0]["EnemyGroup"]["Enemy"][0]
                if b.get("InstanceName") != plan["instanceName"] or b["Quantity"] != 1:
                    errors.append("%s 主Wave Boss身份不符" % mid)
                if b["Type"] != "兵种%d" % UNIT_MAP[BOSS_UNIT[mid]]["id"]:
                    errors.append("%s 主Wave Boss兵种不符" % mid)
                if mid == "A20" and (b.get("Parameters") or {}).get("老头变身") is not False:
                    errors.append("A20 Boss老头变身!=false")
            prev, total = 2, 0
            for g in plan["groups"]:
                if set(g) != {"hpRatio", "enemies"} or not (0 < g["hpRatio"] <= 1) or not g["hpRatio"] < prev:
                    errors.append("%s hpRatio未降序" % mid)
                prev = g["hpRatio"]
                for e in g["enemies"]:
                    scan_enemy(e, "bossEncounter", True)
                    if e.get("InstanceName"):
                        errors.append("%s 增援带InstanceName" % mid)
                    if e["ranged"] and plan["maxRanged"] == 0:
                        errors.append("%s ranged队列无法推进" % mid)
                    total += e["Quantity"]
            if total > 128:
                errors.append("%s 增援总量>128" % mid)
            if mid == "A22":
                for g in plan["groups"]:
                    for e in g["enemies"]:
                        if e["Type"] == "兵种474":
                            errors.append("A22增援组含474")
        elif "bossEncounter" in m:
            errors.append("%s 非Boss图带bossEncounter" % mid)
    # 精英配额载体:Parameters.cf6EliteQuota='E#' 全局恰好5个,落图/兵种/Quantity按合同;
    # 载体掉落必须全部落在该配额候选武器+配套弹药内(消费端整枪替换,不混金币/其他奖励)
    marked = {}
    for m in maps_doc["maps"]:
        mid = m["id"]
        pool = [e for w in m["stage"]["Wave"]["SubWave"] for e in w["EnemyGroup"]["Enemy"]]
        pool += [e for g in m.get("bossEncounter", {}).get("groups", []) for e in g["enemies"]]
        for e in pool:
            q = (e.get("Parameters") or {}).get("cf6EliteQuota")
            if q is None:
                continue
            if q not in ELITE_QUOTA_MAPS or q in marked or ELITE_QUOTA_MAPS[q] != mid:
                errors.append("%s cf6EliteQuota标记未知/重复/落图不符: %s" % (mid, q))
                continue
            if e["Type"] not in ("兵种466", "兵种467") or e["Quantity"] != 1:
                errors.append("%s %s载体非唯一466/467特种兵" % (mid, q))
            marked[q] = e
    for q, mid in ELITE_QUOTA_MAPS.items():
        if q not in marked:
            errors.append("%s 缺cf6EliteQuota=%s载体" % (mid, q))
            continue
        elite = ELITES[mid]
        params = marked[q].get("Parameters") or {}
        if params.get("长枪") != elite["weapon"]:
            errors.append("%s %s载体作者态长枪不符(应=候选首项%s)" % (mid, q, elite["weapon"]))
        allowed = set(elite["candidates"]) | {ammo_of(w, item_index) for w in elite["candidates"]}
        for d in params.get("掉落物") or []:
            if d["名字"] not in allowed:
                errors.append("%s %s载体掉落混入候选外奖励: %s" % (mid, q, d["名字"]))
    if "E4" in marked:
        a17 = next(x for x in maps_doc["maps"] if x["id"] == "A17")
        if not any(e is marked["E4"] for g in a17["bossEncounter"]["groups"] for e in g["enemies"]):
            errors.append("A17 E4载体不在bossEncounter增援组(禁InstanceName,控制器生成scope唯一名)")
    # --- A01 教学炮塔挂接块与逐弹过滤标记普查(r15) ---
    for m in maps_doc["maps"]:
        mid = m["id"]
        if mid == "A01":
            if m.get("turrets") != turret_block:
                errors.append("A01 turrets 块与 tutorial-turrets.fragment.json 派生不符")
        elif "turrets" in m:
            errors.append("%s 非A01地图携带炮塔配置" % mid)
    marked_entries = 0
    marked_qty = 0
    for m in maps_doc["maps"]:
        mid = m["id"]
        pool = [e for w in m["stage"]["Wave"]["SubWave"] for e in w["EnemyGroup"]["Enemy"]]
        pool += [e for g in m.get("bossEncounter", {}).get("groups", []) for e in g["enemies"]]
        for e in pool:
            mark = (e.get("Parameters") or {}).get("目标标记")
            if mark is None:
                continue
            if mark != TURRET_FILTER_MARKER:
                errors.append("%s 未知目标标记: %s" % (mid, mark))
                continue
            if mid != "A01" or e["Type"] != "兵种461":
                errors.append("%s 目标标记落在非A01或非461敌人: %s" % (mid, e["Type"]))
            marked_entries += 1
            marked_qty += e["Quantity"]
    if marked_entries != 5 or marked_qty != 19:
        errors.append("目标标记普查不符: 条目=%d(应5=静态630×1+增援4组), 只数=%d(应19=1+5+5+5+3);"
                      "普通/女僵尸严禁携带" % (marked_entries, marked_qty))
    # --- 商店 ---
    shop_ids = set()
    for s in shops_doc["shops"]:
        if s["shopId"] in shop_ids:
            errors.append("shopId重复: %s" % s["shopId"])
        shop_ids.add(s["shopId"])
        tier = next(t for t in SHOP_TIERS if t["shopId"] == s["shopId"])
        if s.get("level") != tier["level"]:
            errors.append("%s level元数据与档位不符" % s["shopId"])
        names = list(s["catalog"].values())
        gl = s.get("goodsLevels") or {}
        if set(gl) != set(names):
            errors.append("%s goodsLevels未精确覆盖目录" % s["shopId"])
        for n, lv in gl.items():
            if n in item_index and item_index[n]["level"] != lv:
                errors.append("%s goodsLevels[%s]=%s与data/items不符" % (s["shopId"], n, lv))
        if len(names) != len(set(names)):
            errors.append("%s 目录重复" % s["shopId"])
        for n in names:
            if n not in item_index:
                errors.append("%s 商品不存在: %s" % (s["shopId"], n))
        for g in tier["guns"]:
            lv = item_index[g]["level"]
            if not (tier["band"][0] <= lv <= tier["band"][1]):
                errors.append("%s %s等级%d超档位%s" % (s["shopId"], g, lv, tier["band"]))
            if g in supply_guns:
                errors.append("%s %s与固定补给重复" % (s["shopId"], g))
            # 购买渠道独立:精英候选/随机池同型号不必从商店删除(主控r4指示;设计§5/§7双渠道)
            if item_index[g]["clipname"] not in s["catalog"].values():
                errors.append("%s 缺%s配套弹种%s" % (s["shopId"], g, item_index[g]["clipname"]))
    for p in shops_doc["placement"]:
        if p["shopId"] not in shop_ids:
            errors.append("落点引用未知shopId: %s" % p["shopId"])
        if p.get("level") != SHOP_SCHEDULE.get(p["map"]):
            errors.append("落点%s level与主控投放节奏(35@A01/40@A08/45@A11/55@A16/60@A19)不符" % p["map"])
        if p["instanceTemplate"]["x"] is not None or p["instanceTemplate"]["y"] is not None:
            errors.append("NPC模板不得带伪坐标")
        for sk in p["skills"]:
            if sk not in skill_catalog:
                errors.append("商店技能不存在: %s" % sk)
            if sk in [x["name"] for x in actor["actor"]["skills"]]:
                errors.append("商店技能与35项固定满级重复: %s" % sk)
    if {p["map"] for p in shops_doc["placement"]} != set(SHOP_SCHEDULE):
        errors.append("落点图集与SHOP_SCHEDULE不符")
    # --- 经济边界 ---
    if econ["startingMoney"]["value"] != 30000 or econ["startingSkillPoints"]["value"] != 0:
        errors.append("起始经济偏离候选")
    if (econ["lever"]["unitPrices"]["技能点"] != 1500 or econ["lever"]["unitPrices"]["K点"] != 50
            or econ["lever"]["unitPrices"]["强化石"] != 300):
        errors.append("单杠杆价格与真实源不符")
    for c in econ["choiceCheckpoints"]:
        pack = item_index.get(c["choiceItem"])
        if pack is None:
            errors.append("配给包物品缺失(主控已生成进data/items/消耗品_自选配给.xml): %s" % c["choiceItem"])
        elif pack["use"] != "礼包":
            errors.append("配给包物品use非礼包: %s" % c["choiceItem"])
    excluded = [s["name"] for s in econ["skillWhitelist"]["excludedMaxedSkills"]]
    if excluded != [s["name"] for s in actor["actor"]["skills"]]:
        errors.append("技能排除清单与actor固定清单不一致")
    # --- 配给片段:真实merge校验(choice_reward_catalog已登记BOOK_SOURCES路径) ---
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import choice_reward_catalog as crc
    base = load_json(CHOICE_BASE)
    try:
        crc.merge_catalogs(base, [("cf6-sting", choice_frag)])
    except ValueError as exc:
        errors.append("choice-rewards merge校验失败: %s" % exc)
    for g in choice_guns:
        if g in elite_weapons:
            errors.append("配给枪与精英配额重复: %s" % g)
        if g in supply_guns:
            errors.append("配给枪与固定补给重复: %s" % g)
        if g in random_names:
            errors.append("配给枪与随机池重复: %s" % g)
        if any(g in t["guns"] for t in SHOP_TIERS):
            errors.append("配给枪与商店同型: %s" % g)
    for b in choice_frag["bundles"]:
        for sk in b.get("skills", []):
            if sk["skillKey"] in excluded:
                errors.append("配给技能与35项固定满级重复: %s" % sk["skillKey"])
    return errors, warns


def main():
    facts = load_json(os.path.join(SRC, "encounter-facts.v1.json"))
    item_index = load_item_index()
    units = load_json(UNITS)
    actor = load_json(ACTOR)
    skill_catalog = {s.findtext("Name") for s in ET.parse(SKILLS_XML).findall("Skill")
                     if s.findtext("Name") and s.findtext("Name").strip()}

    maps_doc = build_maps(facts, item_index, load_turret_block())
    econ = build_economy(actor["actor"]["skills"], item_index)
    shops_doc = build_shops(item_index, skill_catalog)
    choice_frag = build_choice_fragment(item_index, skill_catalog,
                                        [s["name"] for s in actor["actor"]["skills"]])
    errors, warns = check(maps_doc, econ, shops_doc, choice_frag,
                          item_index, units, actor, skill_catalog, load_turret_block())
    for w in warns:
        print("WARN:", w)
    if errors:
        for e in errors:
            print("ERROR:", e)
        sys.exit(1)
    if "--check" in sys.argv:
        ce = econ["chapterEconomy"]
        print("check OK: maps=%d, bosses=%d, shops=%d, choicePools=%d, "
              "chapterEconomy(random=%d,elite=%d,choice=%d), warnings=%d"
              % (len(maps_doc["maps"]), sum(1 for m in maps_doc["maps"] if "bossEncounter" in m),
                 len(shops_doc["shops"]), len(choice_frag["pools"]),
                 len(ce["randomWeapons"]), len(ce["eliteWeapons"]), len(ce["choices"]), len(warns)))
        return
    for name, doc in (("maps.fragment.json", maps_doc), ("economy.fragment.json", econ),
                      ("shops.fragment.json", shops_doc),
                      ("choice-rewards.fragment.json", choice_frag)):
        with open(os.path.join(SRC, name), "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, indent=1)
    ce = econ["chapterEconomy"]
    print("wrote maps/economy/shops/choice-rewards fragments: maps=%d, bosses=%d, shops=%d, pools=%d, "
          "chapterEconomy(random=%d,elite=%d,choice=%d), warnings=%d"
          % (len(maps_doc["maps"]), sum(1 for m in maps_doc["maps"] if "bossEncounter" in m),
             len(shops_doc["shops"]), len(choice_frag["pools"]),
             len(ce["randomWeapons"]), len(ce["eliteWeapons"]), len(ce["choices"]), len(warns)))


if __name__ == "__main__":
    main()
