"""Validate production encounter references and the complete native art closure."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib
import xml.etree.ElementTree as E

from PIL import Image
from build import ROOT, SOURCE, TARGETS, Q
from stage import build as stage_bytes, DEST, ACTOR_SOURCE


def require(condition, description):
    if not condition:
        raise SystemExit(description)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_portrait_skin(dressup, key):
    skin = dressup["skinKeys"].get(key, {})
    require(skin.get("covered") and skin.get("frames"), "Portrait has a missing live dressup part: " + key)
    require(all((ROOT / "launcher/web/assets/dressup" / f["uri"]).is_file() for f in skin["frames"]), "Portrait part references absent image frames: " + key)


def swf(path):
    data = path.read_bytes()
    require(data[:3] in (b"FWS", b"CWS"), "Invalid SWF: " + str(path))
    body = zlib.decompress(data[8:]) if data[:3] == b"CWS" else data[8:]
    require(len(body) + 8 == struct.unpack_from("<I", data, 4)[0], "SWF length mismatch")
    rectangle_length = ((body[0] >> 3) * 4 + 5 + 7) // 8
    frame_count = struct.unpack_from("<H", body, rectangle_length + 2)[0]
    return frame_count, len(data)


def validate(require_published=False):
    require(DEST.read_bytes() == stage_bytes(), "Production XML differs from encounter authority")
    stage = E.parse(DEST).getroot()
    rooms = stage.findall("SubStage")
    require([int(r.get("id")) for r in rooms] == list(range(8)), "Eight sequential rooms required")
    units = {str(u["id"]): u for u in json.loads((ROOT / "data/units/units.json").read_text(encoding="utf-8-sig"))}
    # This side quest is available after main quest 13. Audit the actual sprite
    # identity, not its generic name: unit 9 uses the enhanced-beast art folder.
    early_zombies = {"1", "2", "3", "4", "5", "6", "8", "293"}
    raid_units = {"13", "44", "45", "48", "49", "456", "458"}
    quests = {t["id"]: t for t in json.loads((ROOT / "data/task/iron_spear_tasks.json").read_text(encoding="utf-8"))["tasks"]}
    require(quests[70001]["get_requirements"] == [13] and quests[70002]["get_requirements"] == [70001], "Re-audit the zombie roster if the earliest main-story gate changes")
    first_defense = E.parse(ROOT / "data/stages/基地门口/第一防线.xml").getroot()
    encountered = {r.findtext("Type", "").removeprefix("兵种") for r in first_defense.findall(".//Enemy")}
    require(early_zombies <= encountered, "Early zombie roster no longer matches the completed first-defense stage")
    for room in rooms:
        rid = int(room.get("id"))
        basic = room.find("BasicInformation")
        env = basic.find("Environment")
        px = float(basic.findtext("PlayerX"))
        py = float(basic.findtext("PlayerY"))
        require(float(env.findtext("Xmin")) <= px <= float(env.findtext("Xmax")), "Spawn X out of bounds")
        require(float(env.findtext("Ymin")) <= py <= float(env.findtext("Ymax")), "Spawn Y out of bounds")
        require(env.findtext("Door/Direction") == ("左" if rid < 3 else "右"), "Exit direction mismatch, including jeep turnaround")
        require(not room.findall("Instances/Instance[Identifier='地图箭头']"), "Do not point at locked exits with ground arrows")
        pts = room.findall("SpawnPoint/Point")
        doorways = {(1, 450, 345), (2, 230, 345), (4, 230, 345), (5, 450, 345), (5, 1475, 345)}
        for p in pts:
            sx, sy = int(p.findtext("x")), int(p.findtext("y"))
            require(sx <= 125 or sx >= 1650 or (rid, sx, sy) in doorways,
                    f"Room {rid} SpawnPoint ({sx},{sy}) must be at a map edge or verified building doorway")
        if rid in (0, 1, 2):
            require(px >= 1600 and all(float(p.findtext("x")) < 1000 for p in pts), "Outbound rooms must spawn threats ahead on the western approach, never behind the right-side entry")
        elif rid == 3:
            require(px >= 1600 and all(float(p.findtext("x")) <= 125 for p in pts), "Jeep hold lanes must surge from the western map entrance past the jeep, never mid-street or behind cover")
        elif rid in (4, 5, 6):
            for row in room.findall("Wave/SubWave/EnemyGroup/Enemy"):
                sidx = int(row.findtext("SpawnIndex"))
                if sidx >= 0 and float(pts[sidx].findtext("x")) < 250 and row.find("x") is None:
                    require(int(row.findtext("Delay", "0")) >= (2000 if rid in (4, 5) else 1200), "Return rooms must delay rear pursuit spawns so enemies do not appear on top of PlayerX=100 at frame 0")
        elif rid == 7:
            require(1100 <= px <= 1450 and all(float(p.findtext("x")) < 700 for p in pts), "Raid finale must place the player in the right-side defense garrison facing left-side bandit breach routes")
        callbacks = room.findall(".//Callback/Name") + room.findall(".//CallbackFunction/Name")
        require(all(c.text in ("NewcomerRescueBegin", "NewcomerRescueSignal") for c in callbacks), "Unknown callback")
        events = {ev.findtext("EventName") for ev in room.findall("Event")}
        for ev in room.findall("Event"):
            following = ev.findtext("FollowingEvent/EventName")
            require(not following or (bool(ev.findall("Dialogue")) and following in events), "Invalid dialogue continuation")
        for row in room.findall(".//Enemy"):
            key = row.findtext("Type", "").removeprefix("兵种")
            require(key in units, "Unknown enemy unit ID: " + key)
            require(key in early_zombies | raid_units, "Unit is outside the pre-14 zombie roster and authorized raid cast: " + key)
            require(rid == 7 or key in early_zombies, "Pre-raid waves must use already encountered zombies")
            require(key not in ("11", "14", "15"), "Giant/alien placeholder accidentally enters rescue encounter")
        for polygon in env.findall("Collision"):
            require(len(polygon.findall("Point")) >= 3, "Malformed collision polygon")
    require(rooms[1].findtext("BasicInformation/Background").endswith("/gk5_5_BG_70002_outbound.swf"), "Outbound exit must use the dedicated torn-doorway map without return-trip markings")
    require(rooms[3].findtext("Wave/SubWave[@id='1']/WaveInformation/Duration") == "75", "Hold duration drift")
    lanes = rooms[3].findall("SpawnPoint/Point")
    require(len(lanes) == 6 and sum(int(p.findtext("QuantityMax")) for p in lanes) == 48, "Dense horde needs six bounded 8-unit lanes")
    horde = rooms[3].findall("Wave/SubWave[@id='1']/EnemyGroup/Enemy")
    require(sum(int(e.findtext("Quantity")) for e in horde) == 745, "Horde reserve drift")
    fodder = [e for e in horde if int(e.findtext("Interval")) <= 550]
    require(len(fodder) == 6 and sum(int(e.findtext("Quantity")) for e in fodder) == 720
            and len({e.findtext("Type") for e in fodder}) == 6
            and {int(e.findtext("SpawnIndex")) for e in fodder} == set(range(6))
            and all(int(e.findtext("Delay")) == 0 for e in fodder), "Use six distinct sustained early-zombie streams")
    destructible = E.parse(SOURCE / "ambush/LIBRARY/Jeep70002/Destructible.xml").getroot()
    fuse_fx = destructible.find(".//" + Q + "DOMSymbolInstance[@libraryItemName='Jeep70002/FuseSmoke']")
    require(fuse_fx is not None and fuse_fx.get("name") == "引信特效", "Destructible jeep must include named FuseSmoke clip")
    for rel in ("StaticSceneEvidence.xml", "StaticSceneEvidenceFalling.xml", "StaticSceneEvidenceCollapsed.xml"):
        st_doc = E.parse(SOURCE / "ambush/LIBRARY/Jeep70002" / rel).getroot()
        st_names = {i.get("name") for i in st_doc.findall(".//" + Q + "DOMSymbolInstance") if i.get("name")}
        require(st_names == {"groundProps", "coverProp", "initiatorProp", "corpseProp", "crateProp"}, "Station evidence must split into five depth-sorted child props: " + rel)
    impact = E.parse(SOURCE / "ambush/LIBRARY/Jeep70002/Detonating.xml").getroot()
    cue = impact.find(".//" + Q + "DOMFrame[@name='wreck']")
    require(cue is not None and cue.get("index") == "7", "Wreck must appear under explosion frame 8")
    fx_layer = impact.find(".//" + Q + "DOMLayer[@name='FX外部选帧']/" + Q + "frames")
    require(len(fx_layer) == 1 and fx_layer[0].get("duration") == "78", "The same explosion instance must span the body change")
    for i in (3, 4, 5):
        require(all(p.findtext("NoCount") == "true" for p in rooms[i].findall("SpawnPoint/Point")), "NoCount must be on spawn points")
    for i in (4, 5):
        require(rooms[i].findtext("Trigger/Xmin") == "1690", "Pursuit exit boundary drift")
        require(rooms[i].findtext("Event[EventName='TriggerPressed']/StageProgress") == "ForceFinishWave", "Pursuit cannot require hostile clear")
    sheriff = rooms[7].find("Event[EventName='RescueReserveDeploy']/Enemy")
    for row in rooms[7].findall("Wave/SubWave/EnemyGroup/Enemy"):
        require(row.findtext("IsHostile") == "true", "Raid enemies must be explicitly hostile")
        require(units[row.findtext("Type").removeprefix("兵种")]["spritename"] != "主角-男", "Use dedicated bandit sprites, not dressup humanoids")
    require({"兵种44", "兵种45", "兵种48", "兵种49"}.issubset({e.findtext("Type") for e in rooms[7].findall(".//Enemy")}), "Dedicated male bandit mix is incomplete")
    require(rooms[2].findtext("Event[EventName='WaveFinished']/FollowingEvent/EventName") == "RescueClinicExplained", "Clinic operation requires dialogue guidance")
    require(rooms[3].findtext("Event[EventName='Start']/FollowingEvent/EventName") == "RescueJeepBriefed", "Investigation requires dialogue guidance")
    require(sheriff.findtext("Type") == "兵种458" and sheriff.findtext("IsHostile") == "false", "Use existing independent sheriff boss as ally")
    require(units["458"]["spritename"] == "敌人-前治安官", "Sheriff linkage drift")
    require(units["13"]["spritename"] == "敌人-僵尸1-狗", "Do not replace global dog while cloud art is pending")
    require(rooms[7].findtext("Wave/SubWave[@id='1']/WaveInformation/Duration") == "10", "Refit window drift")
    drop = rooms[7].find("Wave/SubWave[@id='0']/EnemyGroup/Enemy/Parameters/掉落物")
    require(drop.findtext("名字") == "八门金锁镇暴弹" and drop.findtext("概率") == "100", "Teaching drone must yield one plugin")
    assault_drop = rooms[7].find("Wave/SubWave[@id='2']/EnemyGroup/Enemy[InstanceName='rescue_drone_assault']/Parameters/掉落物")
    require(assault_drop is not None and assault_drop.findtext("名字") == "盗贼踩点记号单" and assault_drop.findtext("概率") == "100", "Assault drone must yield the bandit scouting intelligence")

    intel_names = ["车队外勤散页", "卫生所交接草单", "吉普断后纪要", "盗贼踩点记号单"]
    dictionary = E.parse(ROOT / "data/dictionaries/information_dictionary.xml").getroot()
    item_root = E.parse(ROOT / "data/items/收集品_情报.xml").getroot()
    indexes = [i.text for i in dictionary.findall("Item/Index")]
    require(len(indexes) == len(set(indexes)), "Intelligence indexes must be unique")
    for name in intel_names:
        item = next((i for i in item_root.findall("item") if i.findtext("name") == name), None)
        require(item is not None and item.findtext("maxvalue") == "1" and item.findtext("use") == "情报", "Missing collectible intelligence item: " + name)
        entry = next((i for i in dictionary.findall("Item") if i.findtext("Name") == name), None)
        require(entry is not None and [p.get("PageKey") for p in entry.findall("Information")] == ["1_1", "1_2"], "Two-page intelligence entry required: " + name)
        body = json.loads((ROOT / "data/intelligence_h5" / (name + ".json")).read_text(encoding="utf-8-sig"))
        legacy = re.sub(r"<[^>]+>", "", (ROOT / "data/intelligence" / (name + ".txt")).read_text(encoding="utf-8-sig"))
        texts = [node.get("text", "") for page in body["pages"] for b in page["blocks"] for node in b.get("content", [])]
        require(body["itemName"] == name and all(t in legacy for t in texts), "Legacy/H5 text parity failed: " + name)
    room2_pickups = {p.findtext("Name"): (float(p.findtext("x")), float(p.findtext("y"))) for p in rooms[2].findall("Pickups/Pickup")}
    room3_pickups = {p.findtext("Name"): (float(p.findtext("x")), float(p.findtext("y"))) for p in rooms[3].findall("Pickups/Pickup")}
    require(set(room2_pickups) == {"车队外勤散页", "卫生所交接草单"} and set(room3_pickups) == {"吉普断后纪要"}, "Field intelligence pickups must be placed at the clinic street and jeep ambush site")

    task = quests[70002]
    require("下挂镇暴装置#1" in task["rewards"], "Task delivery reward missing")
    require(task["recommended_level"] == "20-25", "Preparation level must match the harder side quest")
    require(all(d.findtext("Char") == "前治安官（无线电）" and d.findtext("Title") == "第一防线·无线电" for d in stage.findall(".//Dialogue") if d.findtext("Name") == "前治安官"), "Remote sheriff must use radio portrait and title")
    require(not any("按互动键" in (d.findtext("Text") or "") for d in stage.findall(".//Dialogue")), "Keep input prompts in Message banners, not in character dialogue")
    require(rooms[2].findtext("Event[EventName='WaveFinished']/Parameter") == "1", "Clinic contact must follow both combat waves")

    actors = json.loads(ACTOR_SOURCE.read_text(encoding="utf-8"))
    require(set(actors) == {"卫生所幸存者", "防线哨兵", "老兵通话记录"}, "All supporting speakers need a fixed portrait identity")
    require(len({(a["Gender"], a["FaceType"], a["HairStyle"], a["BodyArmor"]) for a in actors.values()}) == 3, "Supporting portraits must be distinguishable")
    dressup = json.loads((ROOT / "launcher/web/assets/dressup/manifest.json").read_text(encoding="utf-8"))
    clothing = {i.findtext("name"): i for i in E.parse(ROOT / "data/items/防具_0-19级.xml").getroot()}
    slots = {"HeadEquipment": "头部装备", "BodyArmor": "上装装备", "LegArmor": "下装装备", "HandGear": "手部装备", "FootGear": "脚部装备", "NeckGear": "颈部装备"}
    for actor in actors.values():
        require(actor["Gender"] in ("男", "女") and 1 <= actor["Level"] <= 3, "Portrait-only actors use explicit low-level identities")
        for field in ("FaceType", "HairStyle"):
            require_portrait_skin(dressup, actor[field])
        for field, slot in slots.items():
            name = actor[field]
            if not name:
                continue
            item = clothing.get(name)
            require(item is not None and item.findtext("use") == slot and int(item.findtext("data/level")) <= 3, "Portrait clothing must be a real level 1-3 item in the correct slot: " + name)
            parts = dressup["items"].get(name, {}).get("fieldsByGender", {}).get(actor["Gender"])
            require(bool(parts), "Portrait clothing has no live dressup mapping: " + name)
            for key in parts.values():
                require_portrait_skin(dressup, key)
    for line in stage.findall(".//Dialogue"):
        speaker = line.findtext("Name")
        if speaker in actors:
            expected_char = "主角模板#普通（无线电）" if speaker == "老兵通话记录" else "主角模板"
            require(line.findtext("Char") == expected_char and all(line.findtext(k, "") == str(v) for k, v in actors[speaker].items()), "Supporting dialogue lost its own fixed appearance: " + speaker)
        elif speaker == "$PC":
            require(line.findtext("Char", "").startswith("$PC_CHAR") and line.findtext("Title") == "$PC_TITLE" and line.find("Gender") is None, "Player dialogue must retain the player's own appearance and title")
        else:
            require(speaker == "前治安官", "Unknown dialogue speaker must not fall back to the player")

    cache_count = symbol_count = total_source_bytes = 0
    masters = {}
    for folder in sorted(SOURCE.iterdir()):
        root = E.parse(folder / "DOMDocument.xml").getroot()
        names = set()
        documents = [root]
        for path in sorted((folder / "LIBRARY").rglob("*.xml")):
            symbol = E.parse(path).getroot()
            require(symbol.get("name") not in names, "Duplicate library symbol in " + folder.name)
            names.add(symbol.get("name"))
            documents.append(symbol)
            symbol_count += 1
        bitmap_names = set()
        for item in root.findall(".//" + Q + "DOMBitmapItem"):
            bitmap_names.add(item.get("name"))
            original = folder / "LIBRARY" / item.get("href")
            cache = folder / "bin" / item.get("bitmapDataHRef")
            require(original.is_file() and cache.is_file() and cache.stat().st_size > 0, "Missing bitmap original/native cache: " + str(cache))
            with Image.open(original) as im:
                require((int(item.get("frameRight")), int(item.get("frameBottom"))) == (im.width * 20, im.height * 20), "Native bitmap bounds must use twips")
            cache_count += 1
        for item in root.findall(".//" + Q + "Include"):
            require((folder / "LIBRARY" / item.get("href")).is_file(), "Missing XFL Include")
        for document in documents:
            for elements in document.iter():
                if elements.tag in (Q + "elements", Q + "members"):
                    require(len(elements.findall(Q + "DOMShape")) < 2, "CS6 merges sibling drawing palettes: " + folder.name)
            for ref in document.findall(".//" + Q + "DOMSymbolInstance"):
                require(ref.get("libraryItemName") in names, "Missing library symbol: " + str(ref.attrib))
            for ref in document.findall(".//" + Q + "BitmapFill"):
                require(ref.get("bitmapPath") in bitmap_names, "Missing bitmap fill")
        files = sorted(p for p in folder.rglob("*") if p.is_file() and p.suffix not in (".fla", ".swf"))
        closure = hashlib.sha256()
        for path in files:
            closure.update(path.relative_to(folder).as_posix().encode("utf-8") + b"\0" + bytes.fromhex(digest(path)))
            total_source_bytes += path.stat().st_size
        masters[folder.name] = closure.hexdigest()
    artifacts = []
    for master, _, name, kind in TARGETS:
        path = ROOT / ("flashswf/arts" if kind in ("jeep", "station") else "flashswf/backgrounds") / (name + ".swf")
        if not path.is_file():
            require(not require_published, "Unpublished artifact: " + str(path))
            continue
        frames, size = swf(path)
        require(kind not in ("jeep", "station") or frames == 4, "Runtime prop must contain four stopped states")
        artifacts.append({"file": str(path.relative_to(ROOT)), "bytes": size, "sha256": digest(path), "master": master, "master_closure_sha256": masters[master]})
    result = {"status": "source_validated", "gameplayE2e": False, "standardEntryVerified": False,
              "rooms": 8, "masters": masters, "symbols": symbol_count, "bitmap_caches": cache_count,
              "source_bytes": total_source_bytes, "artifacts": artifacts}
    (ROOT / "tools/newcomer-rescue-assets/publish-manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"70002 validated: 8 rooms, 5 masters, {symbol_count} symbols, {cache_count} complete bitmap caches, {len(artifacts)}/{len(TARGETS)} SWFs; {total_source_bytes:,} source bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-published", action="store_true")
    validate(parser.parse_args().require_published)
