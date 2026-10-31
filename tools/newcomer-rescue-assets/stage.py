"""70002's eight-room encounter source. Dog art is intentionally replaceable."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "data/stages/副本任务/新人救援.xml"
ACTOR_SOURCE = ROOT / "tools/newcomer-rescue-assets/source/dialogue-actors.json"
DIALOGUE_ACTORS = json.loads(ACTOR_SOURCE.read_text(encoding="utf-8"))

# Room-specific spawn points placed strictly at left/right map boundaries or verified building doorways:
# - Room 0 (gk6_1_BG_70002_departure, PlayerX=1650 moving Left): all 4 lanes at the West/Left map entrance.
# - Room 1 (gk5_5_BG_70002_outbound, PlayerX=1640 moving Left): 3 West map-edge lanes + upper-left building doorway (450, 345).
# - Room 2 (gk5_4_BG_70002_rescue, PlayerX=1670 moving Left): 3 West map-edge lanes + upper-left building doorway (230, 345).
# - Room 3 (gk5_3_BG_70002, PlayerX=1660 entering Right): all 6 horde lanes along the West/Left map entrance (x=75..125).
# - Room 4 (gk5_4_BG_70002_evacuated, PlayerX=100 moving Right): 2 West delayed pursuit lanes + doorway (230, 345) + East entrance (1660, 540).
# - Room 5 (gk5_5_BG_70002_return, PlayerX=100 moving Right): 2 West delayed pursuit lanes + doorways (450, 345) & (1475, 345).
# - Room 6 (gk6_1_BG_70002_receiving, PlayerX=100 moving Right): all 4 lanes at the West/Left map entrance (delayed behind PlayerX=100).
# - Room 7 (gk6_2_BG_70002_raid, PlayerX=1220 facing Left): all 4 bandit breach lanes at the West/Left map entrance.
ROOM_LANES = {
    0: [(80, 430), (90, 500), (100, 575), (115, 645)],
    1: [(85, 480), (110, 635), (450, 345), (95, 560)],
    2: [(85, 480), (110, 635), (230, 345), (95, 560)],
    3: [(75, 415), (85, 465), (95, 515), (105, 565), (115, 615), (125, 665)],
    4: [(90, 495), (115, 645), (230, 345), (1660, 540)],
    5: [(90, 495), (115, 645), (450, 345), (1475, 345)],
    6: [(85, 430), (95, 510), (105, 585), (115, 650)],
    7: [(85, 555), (95, 650), (80, 415), (105, 485)],
}


def node(parent, tag, value=None):
    child = E.SubElement(parent, tag)
    if value is not None:
        child.text = str(value).lower() if isinstance(value, bool) else str(value)
    return child


def fields(parent, values):
    for key, value in values.items():
        if isinstance(value, dict):
            fields(node(parent, key), value)
        elif isinstance(value, list):
            for item in value:
                fields(node(parent, key), item)
        else:
            node(parent, key, value)
    return parent


def enemy(parent, unit, quantity=1, level=18, interval=1700, spawn=0, **extra):
    import sys as _sys
    if str(ROOT / "tools") not in _sys.path: _sys.path.insert(0, str(ROOT / "tools"))
    from unit_registry import UnitRegistry as _UR
    _u = _UR.load(ROOT).get(unit)
    data = dict(Type=_u.get("key") or ("兵种" + str(unit)), IsHostile=True, Level=level, Quantity=quantity,
                Interval=interval, Delay=0, SpawnIndex=spawn)
    data.update(extra)
    return fields(node(parent, "Enemy"), data)


def pickup(stage, name, x, y, value=1):
    pickups = stage.find("Pickups")
    if pickups is None:
        pickups = node(stage, "Pickups")
    idx = len(pickups.findall("Pickup"))
    return fields(E.SubElement(pickups, "Pickup", {"id": str(idx)}),
                  {"Name": name, "Value": value, "x": x, "y": y})


def event(stage, name, parameter=None, signal=None, follow=None, lines=(), progress=None, message=None):
    result = node(stage, "Event")
    node(result, "EventName", name)
    if parameter is not None:
        node(result, "Parameter", parameter)
    for i, (raw_speaker, text) in enumerate(lines):
        speaker, _, emotion = raw_speaker.partition("#")
        char_suffix = f"#{emotion}" if emotion else ""
        dialogue = E.SubElement(result, "Dialogue", {"id": str(i)})
        line = {
            "Name": speaker,
            "Title": "$PC_TITLE" if speaker == "$PC" else "第一防线·无线电",
            "Char": ("$PC_CHAR" + char_suffix) if speaker == "$PC"
                    else "前治安官（无线电）" if speaker == "前治安官"
                    else "主角模板#普通（无线电）" if speaker == "老兵通话记录"
                    else "主角模板",
            "Text": text,
        }
        if speaker not in ("$PC", "前治安官"):
            if speaker not in DIALOGUE_ACTORS:
                raise ValueError("Dialogue actor needs an explicit portrait identity: " + speaker)
            actor = DIALOGUE_ACTORS[speaker]
            if not all(actor.get(k) for k in ("Gender", "FaceType", "HairStyle", "BodyArmor")):
                raise ValueError("Dialogue actor has an incomplete portrait identity: " + speaker)
            # StageInfo turns these fields into the dialogue target's appearance.
            # No combat unit, random equipment or player fallback is involved.
            line.update(actor)
        fields(dialogue, line)
    if follow:
        fields(node(result, "FollowingEvent"), {"EventName": follow})
    if signal:
        fields(node(result, "Callback"), {"Name": "NewcomerRescueSignal", "Parameter": signal})
    if progress:
        node(result, "StageProgress", progress)
    if message:
        node(result, "Message", message)
    return result


def wave(stage, index=0, duration=0, requirement=0):
    waves = stage.find("Wave")
    if waves is None:
        waves = node(stage, "Wave")
    current = E.SubElement(waves, "SubWave", {"id": str(index)})
    fields(node(current, "WaveInformation"), {"Duration": duration, "FinishRequirement": requirement})
    return node(current, "EnemyGroup")


def supply(parent, name, quantity):
    return fields(node(parent, "掉落物"), {"名字": name, "概率": 100,
                                            "最小数量": quantity, "最大数量": quantity})


def build():
    root = E.Element("GameStage")
    root.append(E.Comment("70002：八段救援；战犬暂用兵种13。伤员不作为战场背景人物。由 tools/newcomer-rescue-assets/stage.py 生成。"))
    rewards = node(root, "Rewards")
    for i, (name, chance, amount) in enumerate([("普通hp药剂", 4, 2), ("普通mp药剂", 4, 2), ("12号霰弹弹药", 5, 2)]):
        fields(E.SubElement(rewards, "Reward", {"id": str(i)}),
               {"Name": name, "AcquisitionProbability": chance, "QuantityMax": amount})
    backgrounds = ["gk6_1_BG_70002_departure", "gk5_5_BG_70002_outbound", "gk5_4_BG_70002_rescue", "gk5_3_BG_70002",
                   "gk5_4_BG_70002_evacuated", "gk5_5_BG_70002_return", "gk6_1_BG_70002_receiving", "gk6_2_BG_70002_raid"]
    # Travel west to the jeep, turn around there, then return east via the clinic;
    # Room 7 positions the player inside the right-side defense garrison facing the western breach.
    player_x = [1650, 1640, 1670, 1660, 100, 100, 100, 1220]
    player_y = [560, 560, 560, 560, 560, 560, 560, 530]
    exits = ["左", "左", "左", "右", "右", "右", "右", "右"]
    original_backgrounds = ["gk6_1_BG", "gk5_5_BG", "gk5_4_BG", "gk5_3_BG", "gk5_4_BG", "gk5_5_BG", "gk6_1_BG", "gk6_2_BG"]
    environment_source = E.parse(ROOT / "data/environment/stage_environment.xml").getroot()
    environments = {e.findtext("BackgroundURL"): e for e in environment_source.findall("Environment")}
    layout = json.loads((ROOT / "tools/newcomer-rescue-assets/source/layouts.json").read_text(encoding="utf-8"))["rooms"]
    rooms = []
    for i, background in enumerate(backgrounds):
        room = E.SubElement(root, "SubStage", {"id": str(i)})
        rooms.append(room)
        basic = fields(node(room, "BasicInformation"), {"Background": "flashswf/backgrounds/" + background + ".swf",
                                                        "PlayerX": player_x[i], "PlayerY": player_y[i]})
        env = copy.deepcopy(environments[original_backgrounds[i] + ".swf"])
        basic.append(env)
        env.find("BackgroundURL").text = background + ".swf"
        for existing_door in list(env.findall("Door")):
            env.remove(existing_door)
        fields(node(env, "Door"), {"Index": 1, "Direction": exits[i]})
        for obstacle in layout.get(str(i), []):
            collision = node(env, "Collision")
            for x, y in obstacle["polygon"]:
                node(collision, "Point", f"{x:g},{y:g}")
        fields(node(basic, "CallbackFunction"), {"Name": "NewcomerRescueBegin", "Parameter": i})
        points = node(room, "SpawnPoint")
        lanes = ROOM_LANES[i]
        for p, (x, y) in enumerate(lanes):
            point = fields(E.SubElement(points, "Point", {"id": str(p)}),
                           {"x": x, "y": y, "QuantityMax": 8 if i == 3 else 6})
            if i in (3, 4, 5):
                node(point, "NoCount", True)
        # Use the native clear arrow, which appears only once passage is allowed.
        node(room, "Instances")
        event(room, "RescueAssetFailed", progress="Fail", message="场景资源没有正确载入，请返回后重新进入本关。")

    # Room 0: First Defense Line Outer Edge (Outbound East -> West)
    event(rooms[0], "Start", lines=[
        ("前治安官", "各小队注意，七〇〇〇二号救援现在开始。公社回撤第一防线的外勤车队在西街遇袭，货车半路趴窝，幸存的新人刚借路边的仁爱卫生所筑起临时工事求援。沿外缘公路往左推进，先把接应通道撕开！"),
        ("$PC#严肃", "收到。外围哨位交给你们，我顺着大路进去把他们接回防线。")])
    g = wave(rooms[0])
    enemy(g, 3, 1, 21, 1000, 2, x=480, y=450)
    enemy(g, 8, 1, 21, 1000, 3, x=520, y=580)
    enemy(g, 3, 5, 21, 1100, 0)
    enemy(g, 8, 3, 22, 1800, 1)
    enemy(g, 5, 2, 22, 2800, 2, Delay=1200)

    # Room 1: Suburb Exit Road & Third-Faction Observer Drone (Outbound East -> West)
    event(rooms[1], "Start", signal="observer", lines=[
        ("$PC#思考", "街口被尸群堵死了……等等，电线杆上方悬着一架旧式安保涂装的侦察机，只盯着防线方向却不开火。")])
    event(rooms[1], "RescueDroneReported", lines=[
        ("前治安官", "我也截到了它的短波回传。那是附近盗贼放出来的“望风鸢”，正在趁我们抽调人手摸第一防线的底——哪怕现在打掉它，外围空虚的消息也已经传出去了。别恋战，先去卫生所救人！")])
    g = wave(rooms[1])
    enemy(g, 3, 1, 22, 1000, 2, x=1120, y=495)
    enemy(g, 5, 1, 23, 1000, 3, x=1040, y=545)
    enemy(g, 2, 1, 22, 1000, 2, x=960, y=470)
    enemy(g, 3, 8, 22, 1000, 0)
    enemy(g, 8, 6, 23, 1400, 1)
    enemy(g, 5, 3, 23, 2600, 2, Delay=800)
    enemy(g, 293, 1, 23, 3500, 3, Delay=1500)
    g = wave(rooms[1], 1)
    enemy(g, 6, 9, 23, 1100, 0)
    enemy(g, 3, 5, 24, 2200, 1)
    enemy(g, 5, 4, 23, 2400, 2, Delay=600)
    enemy(g, 8, 2, 24, 3000, 3, Delay=1200)
    fields(E.SubElement(rooms[1], "Trigger", {"id": "0"}), {"Xmax": 1450})
    event(rooms[1], "TriggerPressed", 0, signal="report")

    # Room 2: Ren'ai Clinic Street Outbound (East -> West, Stalled Truck & Motorcycle Blast Crater)
    pickup(rooms[2], "车队外勤散页", 520, 600)
    pickup(rooms[2], "卫生所交接草单", 1390, 415)
    event(rooms[2], "Start", lines=[
        ("$PC#严肃", "回撤的厢式货车就抛锚在街心，左边矮墙还有摩托撞毁和定向雷起爆的焦痕。先把围在卫生所门外的尸群清干净！")])
    g = wave(rooms[2])
    enemy(g, 5, 1, 24, 1000, 3, x=1310, y=420)
    enemy(g, 2, 1, 22, 1000, 2, x=1220, y=465)
    enemy(g, 3, 1, 23, 1000, 2, x=980, y=445)
    enemy(g, 2, 1, 22, 1000, 3, x=760, y=540)
    enemy(g, 2, 9, 22, 1000, 2, Delay=400)
    enemy(g, 8, 7, 23, 1300, 1)
    enemy(g, 5, 2, 24, 2800, 3, Delay=800)
    enemy(g, 3, 2, 24, 3200, 0, Delay=1000)
    g = wave(rooms[2], 1)
    enemy(g, 6, 12, 23, 1000, 0)
    enemy(g, 3, 5, 24, 2200, 1)
    enemy(g, 5, 4, 23, 2400, 2, Delay=800)
    enemy(g, 293, 2, 24, 3800, 3, Delay=1500)
    event(rooms[2], "WaveFinished", 1, follow="RescueClinicExplained", lines=[
        ("前治安官", "街口清出来了。去右上方仁爱卫生所的正门对一下口令，确认里面临时困守的人能不能跟上撤离。"),
        ("$PC", "明白。跟他们接上线以后，我再往西去查那辆断后的吉普。")])
    event(rooms[2], "RescueClinicExplained", signal="clinic", message="靠近右上方卫生所门口，按互动键联络幸存者。")
    event(rooms[2], "RescueClinicContact", follow="RescueClinicReady", lines=[
        ("卫生所幸存者", "是第一防线派来接应的吗？我们原本跟车队往防线回撤，在西面十字路口遭了盗贼冷枪又撞上尸潮……货车逃到这儿彻底趴窝，老陈叔见路边这间卫生所门窗还结实，才带我们钉死大门权充临时工事！"),
        ("卫生所幸存者", "骑摩托的老陈叔逼着我们弃了车里搬不动的重器械、只背随身急救包，自己引爆左街角的定向雷把追尾尸群引开了……"),
        ("$PC#严肃", "他替你们争出了活路。车厢里的重器械先别管，扶好伤员、背紧随身急救包，在门后等我的撤离信号。"),
        ("卫生所幸存者", "往西的十字路口还有老周叔他们断后的黄皮吉普！刚才电台里说盗贼在撬车上的快拆件，底舱的诱爆雷也没响……"),
        ("$PC", "我去西街把底舱引爆，替你们把尸潮钉在那边。听见爆炸声打开通道，你们就顺着门外清出来的路直奔第一防线！")])
    event(rooms[2], "RescueClinicReady", signal="clinic_done")

    # Room 3: Yellow Jeep Ambush, Investigation & 75s Horde Hold (Enter Right x=1660, Hold vs West Horde, Exit Right)
    pickup(rooms[3], "吉普断后纪要", 1490, 495)
    event(rooms[3], "Start", follow="RescueJeepBriefed", lines=[
        ("$PC#严肃", "左边路障口就是断后的黄皮吉普，尸群正从西街往这边涌。右边车门掩体后倒着另一名护卫老兵，旁边还放着他留下的步枪、弹药和手雷箱。"),
        ("前治安官", "别贸然靠近吉普车身。先去右侧掩体旁检查老兵留下的通话记录，弄清楚他们断后时为什么没能引爆底舱。")])
    event(rooms[3], "RescueJeepBriefed", signal="jeep_ready", message="靠近右侧掩体旁的通话记录，按互动键查看。")
    event(rooms[3], "RescueJeepInvestigated", follow="RescueJeepUnlocked", lines=[
        ("老兵通话记录", "……车顶机枪卡死了，我们把吉普横在西街路障口断后！货车别管我们，能往防线开多远开多远，实在撑不住就找路边结实的屋子先顶住！"),
        ("老兵通话记录", "咳……后街摸上来的盗贼看穿了底舱的四箱高爆雷和死人线，趁尸群压住我们，把车顶值钱的火控座和加密匣快拆件全撬走了，还顺手剪断了起爆线……"),
        ("$PC#愤怒", "快拆件被卸得干干净净，底舱的四箱高爆雷倒还留在原位。那帮盗贼算准了老兵被尸群缠住，抢完值钱货就溜了。"),
        ("前治安官", "起爆线断了就别去车边接！拿上掩体旁老兵留下的五六式和手雷，退到右侧掩体后面，直接开火打爆吉普底舱！"),
        ("$PC#严肃", "明白。引爆之后我守住东面路口，把西街涌来的尸潮全钉在这儿，给卫生所的人腾出撤离时间！")])
    event(rooms[3], "RescueJeepUnlocked", signal="jeep_unlock", message="攻击吉普弹药舱；短引信启动后立即远离车辆。")
    event(rooms[3], "UnitDeath", "战斗吉普", progress="ForceFinishWave", signal="hold", message="继续坚守 75 秒，掩护卫生所撤离。")
    event(rooms[3], "WaveFinished", 1, follow="RescueHoldDone", lines=[
        ("卫生所幸存者", "西街的爆炸把尸群全吸引过去了！我们已经带着伤员和随身急救包撤出卫生所，正顺着东面大路往第一防线赶！"),
        ("前治安官", "干得好，尸潮主力已经被拖在西街了。现在掉头往右撤回卫生所方向，顺手清掉贴上来的零星尾巴，别跟后面的尸海死磕！"),
        ("$PC", "收到，我交替掩护往回撤。")])
    event(rooms[3], "RescueHoldDone", signal="hold_done")
    g = wave(rooms[3], 0, requirement=-1)
    enemy(g, 3, 1, 23, 1000, 5, x=720, y=450)
    enemy(g, 5, 1, 24, 1000, 5, x=760, y=545)
    enemy(g, 3, 16, 23, 1200, 0)
    enemy(g, 8, 12, 23, 1500, 2, Delay=500)
    enemy(g, 5, 5, 24, 3200, 3, Delay=900)
    enemy(g, 293, 2, 24, 5000, 4, Delay=1800)
    g = wave(rooms[3], 1, 75, -1)
    # Third Assembly Point pattern: six sustained streams of familiar, cheap
    # zombie sprites pouring from the West/Left suburb past the burning jeep wreck.
    # Quantity is a reserve, not an obligation to spawn/kill all 745 in 75s.
    for unit, level, interval, lane in [(3, 22, 500, 0), (2, 22, 550, 1),
                                        (1, 23, 450, 2), (8, 23, 450, 3),
                                        (4, 22, 550, 4), (6, 22, 500, 5)]:
        enemy(g, unit, 120, level, interval, lane)
    enemy(g, 5, 6, 24, 6500, 0, Delay=5000)
    enemy(g, 3, 8, 24, 6000, 1, Delay=7000)
    enemy(g, 5, 6, 24, 7500, 4, Delay=9000)
    enemy(g, 8, 3, 24, 12500, 2, Delay=12000)
    enemy(g, 293, 2, 24, 18000, 5, Delay=18000)

    # Rooms 4 & 5: Return Fighting Retreat (West -> East, PlayerX=100 -> Trigger Xmin=1690)
    for i, (pre_a, pre_b) in [(4, (640, 1180)), (5, (580, 1060))]:
        fields(E.SubElement(rooms[i], "Trigger", {"id": "0"}), {"Xmin": 1690})
        event(rooms[i], "TriggerPressed", 0, signal="escape", progress="ForceFinishWave")
        g = wave(rooms[i], requirement=-1)
        enemy(g, 3, 1, 23, 1000, 2, x=pre_a, y=505)
        enemy(g, 5, 1, 24, 1000, 3, x=pre_b, y=555)
        enemy(g, 3, 6, 24, 2200, 2, Delay=2000 if i == 4 else 0)
        enemy(g, 5, 2, 24, 3400, 3, Delay=600)
        enemy(g, 6, 22, 23, 1050, 0, Delay=2200)
        enemy(g, 8, 18, 24, 1300, 1, Delay=2600)
    event(rooms[4], "Start", lines=[
        ("$PC", "卫生所这边的临时工事已经撤空了，只剩下街心抛锚的货车和搬不走的重器械。西面还有尾巴咬在后面。"),
        ("前治安官", "别管车厢里的死物！清开挡路的零散尸群，顺着右边通道快速脱身！")])
    event(rooms[5], "Start", lines=[
        ("前治安官", "当心！哨兵发现刚才在西街撬吉普快拆件的那伙盗贼，顺着救援队的撤离痕迹抄了北侧平行路，正赶在防线换防前往入口摸——别在半路恋战，全速回防！"),
        ("$PC#严肃", "怪不得刚才那架“望风鸢”在半路盯梢报信。我马上赶回防线入口！")])

    # Room 6: First Defense Line Receiving Gate (West -> East)
    event(rooms[6], "Start", lines=[
        ("前治安官", "救援队和随身医疗包已经进内门了！把跟到防线铁丝网外的最后这股尸群清干净，准备封门！"),
        ("$PC", "交给我，马上清场。")])
    g = wave(rooms[6])
    enemy(g, 3, 1, 23, 1000, 0, x=430, y=510)
    enemy(g, 5, 1, 24, 1000, 1, x=680, y=560)
    enemy(g, 3, 6, 23, 1150, 0, Delay=1200)
    enemy(g, 5, 2, 24, 2200, 1, Delay=1500)
    enemy(g, 8, 3, 23, 1400, 2, Delay=1800)
    event(rooms[6], "WaveFinished", 0, follow="RescueReceivingDone", lines=[
        ("前治安官", "外门落锁！医疗组按交接单清点伤员，急救包直接送进内侧帐篷！"),
        ("防线哨兵", "警长！侧翼折线通道有动静——盗贼带着战犬和无人机从左边破口冲进来了！"),
        ("$PC#严肃", "是冲着防线外缘的战备箱来的。我去内侧沙袋阵地堵住他们！")])
    event(rooms[6], "RescueReceivingDone", signal="receiving_done")

    # Room 7: Bandit Raid Finale (Player in Right-side Defense Garrison x=1220 facing Left/West Breach)
    crate = fields(E.SubElement(rooms[7].find("Instances"), "Instance", {"id": "0"}),
                   {"Identifier": "资源箱", "x": 1160, "y": 400})
    params = node(crate, "Parameters")
    supply(params, "SPAS12", 1)
    supply(params, "12号霰弹弹药", 4)
    event(rooms[7], "Start", lines=[
        ("防线哨兵", "他们先放战犬顺着左侧折线通道扑过来了！天上还有挂着镇暴头的无人机在压我们的沙袋火线！"),
        ("前治安官", "稳住阵脚！沙袋后方的战备箱里有霰弹枪和十二号鹿弹。等无人机压低高度投射时轰它的机头，别对着高空白费子弹！")])
    g = wave(rooms[7], 0)
    drone = enemy(g, 456, 1, 23, spawn=2, Delay=500, InstanceName="rescue_drone_teaching")
    supply(node(drone, "Parameters"), "八门金锁镇暴弹", 1)
    enemy(g, 13, 5, 23, 650, 0, Delay=0, Parameters={"名字": "盗贼战犬", "newcomerDogPlaceholder": True})
    enemy(g, 44, 3, 23, 2200, 0, Delay=2600)
    enemy(g, 45, 3, 23, 1900, 1, Delay=3200)
    event(rooms[7], "WaveFinished", 0, follow="RescueReserveDeploy", lines=[
        ("$PC#思考", "打碎投射头后，里面掉出了一枚西南自治区旧式安保规格的八门金锁镇暴弹芯。"),
        ("前治安官", "那是审判日前就已量产的自治区安保标准件，不用改装就能直接压进霰弹枪膛。趁现在抓紧换弹整备，我带预备队从后门出来接应你！")])
    reserve = event(rooms[7], "RescueReserveDeploy", message="整备窗口：可将八门金锁镇暴弹装到兼容霰弹枪上。")
    enemy(reserve, 458, 1, 24, spawn=-1, IsHostile=False, InstanceName="rescue_sheriff", x=1350, y=470)
    g = wave(rooms[7], 1, 10, -1)
    g = wave(rooms[7], 2)
    assault_drone = enemy(g, 456, 1, 24, spawn=2, Delay=600, InstanceName="rescue_drone_assault")
    supply(node(assault_drone, "Parameters"), "盗贼踩点记号单", 1)
    enemy(g, 456, 1, 24, spawn=3, Delay=6500, InstanceName="rescue_drone_flank")
    enemy(g, 44, 6, 24, 2200, 0, Delay=1800)
    enemy(g, 45, 6, 24, 2000, 1, Delay=2200)
    enemy(g, 48, 3, 24, 5500, 2, Delay=3800)
    enemy(g, 49, 5, 24, 3400, 3, Delay=2800)
    enemy(g, 13, 6, 24, 1300, 0, Delay=0, Parameters={"名字": "盗贼战犬", "newcomerDogPlaceholder": True})
    event(rooms[7], "WaveFinished", 2, follow="RescueRaidDone", lines=[
        ("前治安官", "守住防线缺口，别追溃散的尾巴！先把伤员和随身药包护送进内门，各哨位重新封锁通道！"),
        ("$PC#严肃", "击落的主攻无人机里有一份踩点记号单。吉普上的火控座和加密匣已经被他们提前转运走了，刚才这伙人只是顺着撤离尾巴来扑防线物资箱的。"),
        ("前治安官", "拿自治区旧式安保平台拼装的“望风鸢”踩点、专挑军规快拆件下手……只要把弹芯和接口记录托中间人送去铁枪会核对出厂批次，这伙人的拆件销赃线就跑不远。你先回前线调度板复命，这笔账我们接着算。")])
    event(rooms[7], "RescueRaidDone", signal="raid_done", progress="Finish")
    E.indent(root, space="    ")
    return E.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    content = build()
    if args.check:
        if not DEST.exists() or DEST.read_bytes() != content:
            raise SystemExit("70002 stage XML is stale")
        print("70002 stage XML matches its encounter source")
    else:
        DEST.write_bytes(content)
        print("Wrote eight-room 70002 encounter")
