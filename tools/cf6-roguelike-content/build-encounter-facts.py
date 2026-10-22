#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build encounter-facts.v1.json — the sourced original-encounter fact table for the
cf6-sting historical route.

Inputs (all read-only):
  tmp/cf6-roguelike-20261021/kimi-content/extract/instances/<MAP>.json
    (per-instance configs parsed from the decompiled original SWF scripts)
  tmp/cf6-roguelike-20261021/kimi-content/extract/instances/tutorial.json (hand-added below)

Output:
  data/stages/books/cf6-sting-source/encounter-facts.v1.json

Every numeric/structural claim carries provenance: the original world sprite id,
the instance depth, and the decompiled script path. Fields that could not be
restored from the SWF are explicitly marked "unknown" — never guessed.
"""
import json
import os

ROOT = r"C:/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight"
INST = os.path.join(ROOT, "tmp/cf6-roguelike-20261021/kimi-content/extract/instances")
OUT_DIR = os.path.join(ROOT, "data/stages/books/cf6-sting-source")
SCRIPT_BASE = "tmp/cf6-soldier-20261016/knife-audit/deobfuscated-export/scripts"
SWF_SHA256 = "b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01"

# Original unit linkage -> roguelike-side candidate key (current-engine id resolved separately).
UNIT_KEY = {
    "aw-僵尸": "zombie", "aw-僵尸-可被炮台打": "zombie_turret", "aw-僵尸-女": "zombie_f",
    "aw-异形": "alien", "aw-蛮蛮": "manman", "敌人-特种兵": "specop",
    "敌人-特种兵-带盾": "specop_shield", "敌人-光头男": "thug", "敌人-wings": "wings",
    "敌人-大刀机器人": "robot_sword", "敌人-大头机器人": "robot_big",
    "敌人-老头人形": "oldman_human", "敌人-老头机器人": "oldman_robot",
}

# Hand-extracted tutorial facts (world sprite 1499; geometry json does not cover it).
TUTORIAL = {
    "worldSprite": 1499, "mainFrame": 58, "killThreshold": 0, "exitTarget": "s1",
    "walkBounds": [50, 150, 1000, 500],
    "spawn": [150, 325],
    "spawnNote": "man1摆放坐标未提取(无geometry覆盖);候选取walkBounds左侧中部",
    "generators": [
        {"instance": "敌人生成器2", "unit": "敌人-光头男", "remainingDeathBudget": 5, "concurrent": 2, "hp": 100, "transform": None, "initialState": "stopped", "trigger": "unknown", "xy": None},
        {"instance": "敌人生成器1", "unit": "aw-异形", "remainingDeathBudget": 5, "concurrent": 2, "hp": 10, "transform": None, "initialState": "stopped", "trigger": "unknown", "xy": None},
    ],
    "dialogue": [
        {"speaker": "Andy Law", "text": "操作方法：WSAD控制移动，J为射击，K为换弹夹。空格为跳过对话。"},
        {"speaker": "Andy Law", "text": "熟悉操作了吗？出门看看吧，我感觉有情况！"},
        {"speaker": "Andy Law", "text": "对了，方向键和换弹夹键可以搓招哦。"},
    ],
    "pickups": [
        {"kind": "crate_gun", "gun": "m4"},
        {"kind": "crate", "content": "救护包"},
        {"kind": "dropped_gun", "gun": "super gun", "note": "教学作弊枪 弹夹20000"},
    ],
}

# r2 修正:按 tmp/cf6-roguelike-20261021/orchestration/encounter-review.json
# (reviewedK3Facts sha256=c53ae8ca…,反馈 feedbackToK3) 纠正 r1 的错误语义:
#  - "僵尸型敌人总个数" 是剩余死亡预算,仅死亡时-1;出兵不减、补位不裁剪(字段改名 remainingDeathBudget)。
#  - 不能据 A01 静态+预算=17<20 证明双计数是关卡所需;未钳制补位已使"固定17"为伪前提。
#  - 光头男 是否变身==1 在 frame77 尸体剪辑 load 时确实跳变身(888证据),r1"不变身"结论作废。
MECHANISM_NOTES = [
    "击杀计数:源单位最终死亡在尸体剪辑load时 _root.电梯死亡敌人计数++(已核僵尸477/630回调,每源单位一次死亡借记)。A09/A12/A13/A14/A18/A19 的'需要杀死数'与'自由生成器死亡预算+静态+已证实触发生成器预算'数值相等;该相等只说明阈值按此口径标定,不证明实际生成总数、也不证明每杀恰好记1次。任何双计数分支需逐帧路径证据,且不得在现代奖励口径复现。",
    "生成器(sprite 1434/1585):'僵尸型敌人总个数'是剩余死亡预算——仅源单位最终死亡时-1;出兵(attachMovie)不减预算,补位(上场个数-场上实际人数)不按剩余预算裁剪;故预算B并发C的源模型可发B..B+C-1只(源模型,非AVM1实跑)。出兵动作在frame10,frame24 gotoAndPlay(2)循环,无预编波次分组。实例onClipEvent(load)首行stop()者为停止态。",
    "停止态生成器的激活:全SWF脚本与pcode常量池穷举搜索,仅触发区sprite 1868(A09→敌人生成器1,A14→敌人生成器x,A18→敌人生成器1)引用生成器实例名;其余图的停止态生成器无任何脚本触发,记trigger=unknown(不捏造)。",
    "A01:活跃生成器死亡预算15+静态2=17<出口阈值20;停止态生成器(僵尸15+光头男5)无触发源。不能据17<20证明双计数为关卡所需——未钳制补位已使'固定总生成17'成为伪前提;原版整图真实逐局生成总量=unknown。首版461×20是对出口死亡阈值20的有限化适配(prototypeDerived),不称原版固定20。",
    "触发区1868:玩家hitTest→把指定生成器挪到触发区位置并play()。",
    "异形卵1939:玩家走近(hitTest)→play→frame24 attachMovie aw-异形×1(hp200)→stop;每卵1只,卵生成物死亡计入击杀计数。A15的5卵=出口所需5杀,数值匹配(同上,不证明生成总数)。",
    "Boss出口1766:监视 _root.gameworld[需要杀死者].hp<=0→play→frame70 切镜.目标帧转场;Boss实例名均为'boss',配1783血条(_root.gameworld.boss.hp)。",
    "老头人形(975)原版脚本无任何变身逻辑;变身是光头男(888)尸体剪辑的'是否变身==1'分支。现役引擎老头单位自动变身需在底座关闭(Parameters.老头变身=false),属引擎侧要求。",
    "光头男(888)'是否变身==1'时,frame77尸体剪辑(PlaceObject2_611_1)onClipEvent(load)进入变身分支:_parent.gotoAndStop('变身'),变身链经sprite887 frame70 attachMovie('aw-异形')生成后继;是否变身!=1不进入该分支。同剪辑line10存在 _root.电梯死亡敌人计数++,其相对变身分支的归属未逐行核定,变身路径是否同时记数=unknown。现役映射:是否变身=1的光头男=兵种469(CF6光头保安·变身型),变身后继由469内部处理,投送469时不另发460。逐图标注:A10静态×1,A12静态×2,A14生成器x(是否变身=1,预算7),A15/A16生成器x(停止态),A17静态×1+两路活跃生成器(各预算15),A19生成器2(预算5),A20生成器(预算15)。",
    "车战A07与演出A21不在本批;出口目标帧s1-s7为原版关间商店帧,肉鸽路线不接。A16模板出口(需要杀死数0→a12)为复制模板,对白链实际目标为a17(主控审查确认),章节按路线顺序A16→A17,不回A12。",
]


def prov(map_id, world, extra=""):
    return {
        "swfSha256": SWF_SHA256,
        "worldSprite": world,
        "scriptBase": "%s/DefineSprite_%s/frame_1" % (SCRIPT_BASE, world),
        "note": extra or "逐实例 onClipEvent(load) 配置解析",
    }


def convert(map_id):
    p = os.path.join(INST, "%s.json" % map_id)
    d = json.load(open(p, encoding="utf-8"))
    world = d["worldSprite"]
    gens = []
    for g in d["generators"]:
        c = g["config"]
        gens.append({
            "instance": g["name"], "charId": g["charId"], "depth": g["depth"], "xy": g["xy"],
            "unit": c.get("兵种"), "unitKey": UNIT_KEY.get(c.get("兵种"), "unknown"),
            # r2: 总个数=剩余死亡预算(仅死亡-1,出兵不减、补位不裁剪),非预定spawn总数
            "remainingDeathBudget": c.get("僵尸型敌人总个数"), "concurrent": c.get("僵尸型敌人上场个数"),
            "hp": c.get("hp"), "ai": c.get("AI"), "gun": c.get("gunname"),
            "transform": c.get("是否变身"),
            "door": c.get("目标门"),
            "initialState": "stopped" if c.get("stop") else "free",
            "trigger": "unknown" if c.get("stop") else None,
        })
    statics = []
    for s in d["statics"]:
        c = s["config"]
        statics.append({
            "unit": s["kind"], "unitKey": UNIT_KEY.get(s["kind"], "unknown"),
            "depth": s["depth"], "xy": s["xy"], "hp": c.get("hp"), "ai": c.get("AI"),
            "gun": c.get("gunname"), "transform": c.get("是否变身"),
        })
    exits = []
    for e in d["exits"]:
        c = e["config"]
        exits.append({
            "charId": e["charId"], "depth": e["depth"],
            "type": "bossKill" if "需要杀死者" in c else "killCount",
            "required": c.get("需要杀死数"), "bossInstance": c.get("需要杀死者"),
            "targetFrame": c.get("目标帧"),
        })
    exit_note = None
    if map_id == "A16":
        exit_note = ("模板出口需要杀死数0→a12为复制模板;对白链实际目标a17(主控审查 encounter-review 确认),"
                     "章节按路线顺序A16→A17,不回A12")
    triggers = [{"depth": t["depth"], "xy": t["xy"], "target": t["config"].get("指定敌人生成器")}
                for t in d["triggers"]]
    eggs = sum(1 for x in d["misc"] if x["charId"] in (1939, 887))
    pickups = []
    for pk in d["pickups"]:
        c = pk["config"]
        item = {"kind": pk["kind"], "depth": pk["depth"], "xy": pk["xy"]}
        if c.get("gunname"):
            item["gun"] = c.get("gunname")
            item["ammoInMag"] = c.get("弹夹内子弹")
        if c.get("内部物"):
            item["content"] = c.get("内部物")
        pickups.append(item)
    dialogue = []
    for x in d["misc"]:
        if x["charId"] == 1455:
            c = x["config"]
            n = c.get("几段话", 0) or 0
            for i in range(1, int(n) + 1):
                dialogue.append({"speaker": c.get("头像%d" % i), "text": c.get("talk%d" % i)})
    turrets = sum(1 for x in d["misc"] if x["charId"] == 1591)
    aa_turrets = sum(1 for x in d["misc"] if x["charId"] in (1838, 1736))
    boss = None
    for s in statics:
        if s["unit"] in ("aw-蛮蛮", "敌人-大头机器人", "敌人-老头人形", "敌人-老头机器人") and map_id in ("A06", "A17", "A20", "A22"):
            boss = dict(s)
    result = {
        "id": map_id, "worldSprite": world, "mainFrame": d["mainFrame"],
        "walkBounds": d["walkBounds"], "spawn": d["spawn"],
        "generators": gens, "statics": statics, "exits": exits,
        "triggerZones": triggers, "alienEggs": eggs,
        "turrets": turrets, "antiEnemyTurrets": aa_turrets,
        "pickups": pickups, "dialogue": dialogue, "boss": boss,
        "provenance": prov(map_id, world),
    }
    if exit_note:
        result["exitNote"] = exit_note
    return result


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    order = ["tutorial"] + ["A%02d" % i for i in range(1, 7)] + ["A%02d" % i for i in range(8, 21)] + ["A22"]
    maps = []
    for m in order:
        if m == "tutorial":
            t = TUTORIAL
            maps.append({
                "id": "tutorial", "worldSprite": t["worldSprite"], "mainFrame": t["mainFrame"],
                "walkBounds": t["walkBounds"], "spawn": t["spawn"],
                "generators": [dict(g, unitKey=UNIT_KEY.get(g["unit"], "unknown")) for g in t["generators"]],
                "statics": [], "exits": [{"type": "killCount", "required": t["killThreshold"],
                                           "targetFrame": t["exitTarget"], "charId": 1430}],
                "triggerZones": [], "alienEggs": 0, "turrets": 0, "antiEnemyTurrets": 0,
                "pickups": t["pickups"], "dialogue": t["dialogue"], "boss": None,
                "provenance": {"swfSha256": SWF_SHA256, "worldSprite": 1499,
                               "scriptBase": SCRIPT_BASE + "/DefineSprite_1499/frame_1",
                               "note": "手工提取;含教学对话"},
            })
        else:
            maps.append(convert(m))
    doc = {
        "schema": "cf6-encounter-facts.v1",
        "source": {
            "exe": "CrazyFlasherSeries/exes/crazyflasher6-cn_secure.exe",
            "exeSha256": "3523806f0e250ebf8ffe32683d027c7712578711ec99803d341673a22253d18c",
            "swfSha256": SWF_SHA256,
            "decompiledScripts": SCRIPT_BASE,
        },
        "counterRule": "电梯死亡敌人计数>=需要杀死数 开出口;Boss图为 boss.hp<=0",
        "mechanismNotes": MECHANISM_NOTES,
        "maps": maps,
    }
    out = os.path.join(OUT_DIR, "encounter-facts.v1.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    print("wrote", out, "maps:", len(maps))


if __name__ == "__main__":
    main()
