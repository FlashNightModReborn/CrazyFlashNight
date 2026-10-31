#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Assemble a candidate cf6-sting chapter in tmp (never the live path) and run
the REAL validate_cf6 from tools/build-book-definition.py against it.

  python -X utf8 tools/cf6-roguelike-content/check-chapter.py

Inputs: cf6-sting-source fragments + actor fragment. Output:
  tmp/cf6-roguelike-20261021/kimi-content/candidate/cf6-sting.candidate.json
"""
import importlib.util
import json
import os
import sys
import xml.etree.ElementTree as ET

ROOT = r"C:/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight"
SRC = os.path.join(ROOT, "data/stages/books/cf6-sting-source")
OUT = os.path.join(ROOT, "tmp/cf6-roguelike-20261021/kimi-content/candidate/cf6-sting.candidate.json")


def load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def main():
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    spec = importlib.util.spec_from_file_location(
        "bbd", os.path.join(ROOT, "tools/build-book-definition.py"))
    bbd = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bbd)

    actor = load(os.path.join(ROOT, "tools/cf6-actor-template/actor.fragment.json"))["actor"]
    maps_doc = load(os.path.join(SRC, "maps.fragment.json"))
    econ = load(os.path.join(SRC, "economy.fragment.json"))

    chapter = {
        "schema": "playable-book.v1",
        "id": "cf6-sting",
        "routeId": "historical",
        "stageName": "书中历险-毒刺行动",
        "title": "闪客快打6·毒刺行动(史实路线)",
        "startingMoney": econ["startingMoney"]["value"],
        "startingSkillPoints": econ["startingSkillPoints"]["value"],
        "actor": actor,
        # chapter.economy 原值=economy.fragment.json的chapterEconomy
        # (tools/cf6-prototype/economy-input-contract.json cf6-economy-input.v1);
        # 缺了它 validate_economy 无对象可验,"校验通过"不能说明经济字段已装配。
        "economy": econ["chapterEconomy"],
        # bossEncounter 必须显式带入候选,否则 validate_cf6_boss 无对象可验,
        # "校验通过"不能说明Boss配置已装配(主控inbox 2026-10-21)。
        "maps": [{k: m[k] for k in ("id", "title", "background", "dialogue", "stage", "bossEncounter")
                  if k in m}
                 for m in maps_doc["maps"]],
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(chapter, f, ensure_ascii=False, indent=1)

    items = {}
    pack = os.path.join(ROOT, "data/items/消耗品_书中配给.xml")
    import glob
    for path in glob.glob(os.path.join(ROOT, "data/items/*.xml")):
        if os.path.abspath(path) == os.path.abspath(pack):
            continue
        for item in ET.parse(path).findall(".//item"):
            items[item.findtext("name")] = item
    skills = ET.parse(os.path.join(ROOT, "data/skills/skills.xml")).findall("Skill")
    reg = bbd.UnitRegistry.load(ROOT)
    units = set(reg.by_id)
    chapter = bbd.normalize_book_units(chapter, reg)

    try:
        bbd.validate_cf6(chapter, items, skills, units)
        print("validate_cf6 OK (strict, backgrounds present) ->", OUT)
        report_boss(chapter)
        report_economy(chapter)
        return
    except ValueError as exc:
        strict_error = str(exc)
    # backgrounds are the map line's deliverable; report per-map availability separately
    missing_bg = []
    for m in chapter["maps"]:
        bg = os.path.join(ROOT, "flashswf/backgrounds", m["background"])
        if not os.path.isfile(bg):
            missing_bg.append(m["background"])
    bbd.validate_cf6(chapter, items, skills, units, require_backgrounds=False)
    print("validate_cf6 OK (require_backgrounds=False) ->", OUT)
    report_boss(chapter)
    report_economy(chapter)
    print("strict failure was:", strict_error)
    print("missing backgrounds (%d): %s" % (len(missing_bg), ", ".join(missing_bg)))


def report_boss(chapter):
    for m in chapter["maps"]:
        plan = m.get("bossEncounter")
        if not plan:
            continue
        total = sum(e["Quantity"] for g in plan["groups"] for e in g["enemies"])
        print("bossEncounter %s: %s maxAlive=%d maxRanged=%d interval=%d groups=%d supportTotal=%d"
              % (m["id"], plan["instanceName"], plan["maxAlive"], plan["maxRanged"],
                 plan["intervalFrames"], len(plan["groups"]), total))


def report_economy(chapter):
    ce = chapter.get("economy")
    if not ce:
        print("economy: MISSING (chapterEconomy未带入候选)")
        return
    print("economy: randomWeapons=%d eliteWeapons=%d choices=%d -> %s"
          % (len(ce["randomWeapons"]), len(ce["eliteWeapons"]), len(ce["choices"]),
             ", ".join("%s@%s" % (r["quota"], r["mapId"]) for r in ce["eliteWeapons"])))


if __name__ == "__main__":
    main()
