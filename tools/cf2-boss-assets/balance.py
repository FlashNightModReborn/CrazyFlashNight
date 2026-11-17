"""Initial black-iron-referenced budget; never claims a roguelike chapter decision."""
from pathlib import Path
import argparse
import copy
import json
import math
import subprocess
import sys
import xml.etree.ElementTree as E
import build

ROOT, HERE, SPEC = build.ROOT, build.HERE, build.SPEC
sys.path.insert(0,str(ROOT/"tools"))
from unit_registry import preserve_unit_key

PROPERTY_FILE = "CF2重制敌人.xml"
FIELDS = {"最小经验值":"expMin","最大经验值":"expMax","hp_min":"hpMin","hp_max":"hpMax",
          "空手攻击力_min":"atkMin","空手攻击力_max":"atkMax","基本防御力_min":"defMin","基本防御力_max":"defMax"}
FLAG_KEYS = {"阶段":"stage","档次系数":"tierFactor","成长系数":"growthFactor",
             "攻速系数":"atkSpeedFactor","攻击倍率":"atkMultiplier","段数系数":"segmentFactor",
             "速度系数":"speedFactor","高攻低血防系数":"highAtkFactor",
             "霸体系数":"superArmorFactor","高防低血系数":"highDefFactor"}


def observed_actions():
    _,_,source = build.source()
    sk_art = source["坦克大机器人/技能"]
    beam_layers = [build.layers(sk_art)[li] for li in build.beam_layer_indices(sk_art)]
    rows = []
    powers = SPEC["tuning"]
    for name,spec in SPEC["actions"].items():
        end = spec["end"]-spec["start"]+1
        expanded = []
        for frame in range(1,end+1):
            expanded.append(frame)
            if frame==spec.get("loopEnd"):
                for _ in range(powers["loops"]-1):
                    expanded.extend(range(spec["loopStart"],spec["loopEnd"]+1))
        contacts = []
        for clock,frame in enumerate(expanded,1):
            if "hits" in spec:
                if frame in spec["hits"]:
                    kind = "gun" if name=="gatling" else name
                    contacts.append((clock,kind,powers[kind+"Power"],2 if kind=="laser" else 1))
            elif frame==spec.get("brakeHit"):
                contacts.append((clock,"cannon",powers["cannonPower"],1))
            elif spec["loopStart"]<=frame<=spec["loopEnd"]:
                offset = frame-spec["loopStart"]
                if offset%4==0:contacts.append((clock,"gun",powers["gunPower"],1))
                if offset==spec.get("cannonOffset",9):contacts.append((clock,"cannon",powers["cannonPower"],1))
                if offset<40 and offset%4==0:
                    # Existing 榴弹 carries one direct hit and a 0.7-power burst.
                    # This is a per-projectile equivalent budget, not an arena verdict.
                    contacts.append((clock,"grenade",powers["grenadePower"]*1.7,1))
                source_frame = spec["start"]+frame-2
                visible = any(
                    (active_frame:=build.active(bl,source_frame)) is not None
                    and len(active_frame.find("x:elements",build.NS))>0
                    for bl in beam_layers
                )
                if name=="barrage" and offset%6==0 and visible:
                    contacts.append((clock,"laser",powers["laserPower"],2))
        if not contacts:
            raise ValueError("No attack declarations: "+name)
        first,last = contacts[0][0],contacts[-1][0]
        times = max(1,(last-first)/15)
        rows.append({"action":name,"frames":len(expanded),"firstHit":first,"lastHit":last,
                     "contacts":len(contacts),"kinds":{k:sum(c[1]==k for c in contacts) for k in ("melee","gun","cannon","laser","grenade")},
                     "typeWeightedPower":sum(c[2]*c[3] for c in contacts)/len(contacts),
                     "segments":len(contacts)/times})
    return rows


def expected():
    rows = observed_actions()
    tempo = sum(r["firstHit"]+(r["frames"]-r["lastHit"])*0.2 for r in rows)/len(rows)
    speed_band = next((factor for upper,factor in ((9,5),(16,4),(26,3),(41,2))
                       if tempo<upper*1.2),1)
    cfg = SPEC["balance"]
    inputs = {key:cfg[key] for key in ("stage","tierFactor","growthFactor","highAtkFactor","highDefFactor")}
    mean_speed = (cfg["speedMin"]+cfg["speedMax"])/2
    inputs.update(atkSpeedFactor=speed_band,
                  atkMultiplier=round(sum(r["typeWeightedPower"] for r in rows)/len(rows),4),
                  segmentFactor=round(sum(r["segments"] for r in rows)/len(rows),4),
                  speedFactor=1 if mean_speed<=40 else 2 if mean_speed<=60 else 3,
                  superArmorFactor=4+min(0.5,math.floor(cfg["tenacity"]/20)*0.1))
    expression = ("import {computeMonsterRow} from './tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts';"
                  "console.log(JSON.stringify(computeMonsterRow("+json.dumps(inputs)+")));")
    tsx = ROOT/"tools/cf7-balance-tool/node_modules/tsx/dist/cli.mjs"
    command = ["node",str(tsx),"-e",expression] if tsx.exists() else ["node","--input-type=module","-e",expression]
    values = json.loads(subprocess.check_output(command,cwd=ROOT,text=True,encoding="utf-8"))
    identity = SPEC["identity"]
    entry = E.Element(identity["linkage"])
    E.SubElement(entry,"displayname").text=identity["name"]
    for field,formula in FIELDS.items():
        E.SubElement(entry,field).text=str(math.floor(values[formula]+0.5))
    for field,value in {"速度_min":cfg["speedMin"],"速度_max":cfg["speedMax"],
                        "躲闪率_min":100,"躲闪率_max":50,"装备防御力":0,
                        "性别":"男","重量":500,"韧性系数":cfg["tenacity"],
                        "battleRecordAppearance":"fixed"}.items():
        E.SubElement(entry,field).text=str(value)
    resistance=E.SubElement(entry,"魔法抗性")
    for field,value in {"装甲":30,"机械":40,"首领":50}.items():
        E.SubElement(resistance,field).text=str(value)
    flags=E.SubElement(entry,"标识")
    for field,key in FLAG_KEYS.items():
        E.SubElement(flags,field).text=f"{inputs[key]:g}"
    units=json.loads((ROOT/"data/units/units.json").read_text("utf-8-sig"))
    references=[u for u in units if u.get("key")==cfg["reference"]]
    if len(references)!=1:
        raise ValueError("The prototype's reference unit identity changed")
    reference=references[0]
    reference_path=ROOT/"data/enemy_properties/原版敌人 2013-2016.xml"
    reference_entry=E.parse(reference_path).getroot().find(reference["spritename"])
    if reference_entry is None:
        raise ValueError("The prototype's reference properties are missing")
    unit={"id":identity["unitId"],"key":identity["key"],"spritename":identity["linkage"],
          "level":37,"name":identity["name"],"is_hostile":True,"height":SPEC["geometry"]["height"],
          "data":{"primary":None,"secondary":None,"secondary2":None,"melee":None}}
    unit=preserve_unit_key(unit,units,new_key=identity["key"])
    receipt={"schema":"cf2-tank-boss.balance.v1","status":cfg["status"],
             "reference":cfg["reference"],"stageIsBudgetProxy":True,"placementLevelNotDecided":True,
             "formula":"tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts",
             "formulaSha256":build.sha(ROOT/"tools/cf7-balance-tool/packages/core/src/formulas/monsters.ts"),
             "input":inputs,"weightedTempo":tempo,"actions":rows,
             "deathBurst":{"power":SPEC["tuning"]["deathPower"],"laneRange":80,"frame":12},
             "grenadeBudgetBasis":{"template":"榴弹","directPlusBurstEquivalent":1.7,"launchersPerLoop":10,
                                   "source":"flashswf/arts/原版素材库-子弹/LIBRARY/子弹-炮弹与爆炸组/榴弹.xml"},
             "integerPanel":{k:int(entry.find(k).text) for k in FIELDS},
             "referenceSource":{"unitId":reference["id"],"key":reference["key"],"spritename":reference["spritename"],
                                "path":reference_path.relative_to(ROOT).as_posix(),"sha256":build.sha(reference_path),
                                "panel":{k:int(reference_entry.find(k).text) for k in FIELDS},
                                "comparison":"raw XML panel only; not same-level runtime stats or a duel verdict"},
             "scope":"initial source budget; not a duel, player-experience or roguelike-placement verdict"}
    return entry,unit,receipt,units


def canonical(node):
    return None if node is None else (node.tag,(node.text or "").strip(),tuple(canonical(c) for c in node))


def unit_text(text,unit):
    current=json.loads(text)
    matching=[u for u in current if u["id"]==unit["id"] or u.get("key")==unit["key"] or u["spritename"]==unit["spritename"]]
    if matching and (len(matching)!=1 or matching[0]["id"]!=unit["id"] or matching[0]["spritename"]!=unit["spritename"]):
        raise ValueError("New tank unit registration collided")
    encoded="\n  ".join(json.dumps(unit,ensure_ascii=False,indent=2).splitlines())
    pos=text.index("[")+1
    decoder=json.JSONDecoder()
    while True:
        while text[pos].isspace() or text[pos]==",":pos+=1
        if text[pos]=="]":break
        row,end=decoder.raw_decode(text,pos)
        if row["id"]==unit["id"]:
            return text if row==unit else text[:pos]+encoded+text[end:]
        pos=end
    if unit["id"]<=max(u["id"] for u in current):
        raise ValueError("New tank ID is no longer above the registry maximum")
    return text[:pos].rstrip()+",\n  "+encoded+"\n"+text[pos:]


def enemy_text(text,entry):
    old=E.fromstring(text).findall(entry.tag)
    if len(old)>1:raise ValueError("Duplicate tank properties")
    if old and canonical(old[0])==canonical(entry):return text
    entry=copy.deepcopy(entry);entry.tail=None;E.indent(entry,space="    ",level=1)
    encoded=E.tostring(entry,encoding="unicode")
    if old:
        start=text.index("<"+entry.tag+">");end=text.index("</"+entry.tag+">",start)+len(entry.tag)+3
        return text[:start]+encoded+text[end:]
    return text.replace("</root>","    "+encoded+"\n</root>",1)


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--write",action="store_true");args=parser.parse_args()
    entry,unit,receipt,_=expected()
    path=ROOT/"data/enemy_properties"/PROPERTY_FILE
    old=path.read_text("utf-8") if path.exists() else '<?xml version="1.0" encoding="UTF-8"?>\n<root>\n    <!-- 阶段5仅借用黑铁作原型预算，不代表闪2肉鸽出场章节；暂无正式掉落。 -->\n</root>\n'
    updated=enemy_text(old,entry)
    upath=ROOT/"data/units/units.json";units=upath.read_text("utf-8-sig");registered=unit_text(units,unit)
    lpath=ROOT/"data/enemy_properties/list.xml";listing=lpath.read_text("utf-8")
    declaration="<items>"+PROPERTY_FILE+"</items>"
    new_listing=listing if declaration in listing else listing.replace("</root>","  "+declaration+"\n</root>",1)
    if args.write:
        for p,before,after in ((path,old,updated),(upath,units,registered),(lpath,listing,new_listing)):
            if not p.exists() or before!=after:p.write_text(after,encoding="utf-8",newline="\n")
        (HERE/"balance-inputs.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    assert canonical(E.parse(path).getroot().find(entry.tag))==canonical(entry)
    assert next(u for u in json.loads(upath.read_text("utf-8-sig")) if u["id"]==unit["id"])==unit
    assert sum(e.text==PROPERTY_FILE for e in E.parse(lpath).getroot())==1
    assert json.loads((HERE/"balance-inputs.json").read_text("utf-8"))==receipt
    print(json.dumps({"ok":True,"unitId":unit["id"],"input":receipt["input"],"panel":receipt["integerPanel"]},ensure_ascii=False))


if __name__=="__main__":
    if hasattr(sys.stdout,"reconfigure"):sys.stdout.reconfigure(encoding="utf-8")
    main()
