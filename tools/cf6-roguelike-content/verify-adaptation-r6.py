#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Directed before/after assertions for the r6 placement adaptation (K3 lane).

  python -X utf8 tools/cf6-roguelike-content/verify-adaptation-r6.py

Asserts, against the pre-fix snapshot in
tmp/cf6-roguelike-20261021/kimi-content/r6/pre-fix/:
  A. exactly the 5 declared field paths changed coordinates
     (pre==originalNative, post==newNative); the only other diffs are the
     added placementAdaptation root block and sourceNote text on the 8
     expected maps — no other enemy/field was touched;
  B. economy/shops/choice-rewards fragments are deep-equal pre vs post
     (weapon pools, prices, quantities untouched);
  C. encounter-facts.v1.json sha256 unchanged (historical provenance);
  D. post-fix world points (= newNative - nativeBounds origin, i.e. root
     subtracts the origin exactly once) pass the full 36x18px foot-box +
     walkBounds check on the final environment; A18 also at engine +2y;
  E. A18 referencing wave enemy keeps SpawnIndex=0 and gains no x/y;
  F. per-map enemy Quantity totals unchanged.
Exit 1 on any failure. Read-only: never writes to inputs.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "data/stages/books/cf6-sting-source")
PRE = os.path.join(ROOT, "tmp/cf6-roguelike-20261021/kimi-content/r6/pre-fix")

spec = importlib.util.spec_from_file_location(
    "bpa", os.path.join(ROOT, "tools/cf6-roguelike-content/build-placement-adaptation.py"))
bpa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bpa)

failures = []


def ok(cond, label, detail=""):
    print(("PASS " if cond else "FAIL ") + label + (" — " + detail if detail else ""))
    if not cond:
        failures.append(label)


def load(path):
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def diff(a, b, path, out):
    if type(a) is not type(b):
        out.append((path, a, b))
        return
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a:
                out.append((path + "." + k, "<absent>", b[k]))
            elif k not in b:
                out.append((path + "." + k, a[k], "<absent>"))
            else:
                diff(a[k], b[k], path + "." + k, out)
    elif isinstance(a, list):
        if len(a) != len(b):
            out.append((path + "<len>", len(a), len(b)))
            return
        for i, (x, y) in enumerate(zip(a, b)):
            diff(x, y, "%s[%d]" % (path, i), out)
    elif a != b:
        out.append((path, a, b))


def main():
    adapt = load(os.path.join(SRC, "placement-adaptation.v1.json"))
    pre_maps = load(os.path.join(PRE, "maps.fragment.json"))
    post_maps = load(os.path.join(SRC, "maps.fragment.json"))
    pre_by_id = {m["id"]: m for m in pre_maps["maps"]}
    post_by_id = {m["id"]: m for m in post_maps["maps"]}
    idx_by_id = {m["id"]: i for i, m in enumerate(post_maps["maps"])}

    # --- A1: the 5 declared fields moved exactly as recorded ---
    for e in adapt["entries"]:
        mid = e["map"]
        pre_node = bpa.get_path(pre_by_id[mid], e["fieldPath"])
        post_node = bpa.get_path(post_by_id[mid], e["fieldPath"])
        ok(abs(pre_node["x"] - e["originalNative"][0]) <= 0.051
           and abs(pre_node["y"] - e["originalNative"][1]) <= 0.051,
           "A1 %s pre == originalNative" % e["id"],
           "(%s,%s)" % (pre_node["x"], pre_node["y"]))
        ok(abs(post_node["x"] - e["newNative"][0]) <= 0.051
           and abs(post_node["y"] - e["newNative"][1]) <= 0.051,
           "A1 %s post == newNative" % e["id"],
           "(%s,%s)" % (post_node["x"], post_node["y"]))

    # --- A2: full diff contains only allowed changes ---
    allowed_xy = set()
    for e in adapt["entries"]:
        base = "maps[%d].%s" % (idx_by_id[e["map"]], e["fieldPath"])
        allowed_xy.add(base + ".x")
        allowed_xy.add(base + ".y")
    notes_maps = {"A02", "A09", "A14", "A15", "A17", "A18", "A20", "A22"}
    notes_re = re.compile(r"^maps\[(\d+)\]\.sourceNote\.notes")
    diffs = []
    diff(pre_maps, post_maps, "", diffs)
    bad = []
    for path, a, b in diffs:
        p = path.lstrip(".")
        if p in allowed_xy:
            continue
        if p.startswith("placementAdaptation"):
            continue
        m = notes_re.match(p)
        if m and post_maps["maps"][int(m.group(1))]["id"] in notes_maps:
            continue
        bad.append((p, a, b))
    ok(not bad, "A2 only 5 coordinate fields + notes/adaptation-block changed",
       "%d diffs total, %d unexpected" % (len(diffs), len(bad)))
    for p, a, b in bad[:10]:
        print("   unexpected diff:", p, repr(a)[:80], "->", repr(b)[:80])

    # --- B: economy/shops/choice fragments deep-equal ---
    for name in ("economy.fragment.json", "shops.fragment.json",
                 "choice-rewards.fragment.json"):
        same = load(os.path.join(PRE, name)) == load(os.path.join(SRC, name))
        ok(same, "B %s unchanged (pools/prices/quantities)" % name)

    # --- C: facts file untouched ---
    ok(sha256(os.path.join(SRC, "encounter-facts.v1.json"))
       == adapt["inputSha256"]["encounter-facts.v1.json"],
       "C encounter-facts.v1.json sha256 unchanged")

    # --- D: geometry at post-fix world points (root subtracts origin once) ---
    import xml.etree.ElementTree as ET
    envs = {n.findtext("BackgroundURL"): bpa.Env(n)
            for n in ET.parse(os.path.join(
                ROOT, "tools/cf6-map-runtime/generated/environment.fragment.xml"))
            .getroot().findall("Environment")}
    mapinput = load(os.path.join(ROOT, "tools/cf6-map-source/generated/map-input.json"))["maps"]
    if isinstance(mapinput, list):
        mapinput = {m["id"]: m for m in mapinput}
    for e in adapt["entries"]:
        nb = mapinput[e["map"]]["nativeBounds"]
        world = (e["newNative"][0] - nb[0], e["newNative"][1] - nb[1])
        ok(abs(world[0] - e["targetWorld"][0]) <= 0.001
           and abs(world[1] - e["targetWorld"][1]) <= 0.001,
           "D %s world == newNative - origin (single subtraction)" % e["id"],
           "(%.2f,%.2f)" % world)
        offsets = [[0, 2]] if e["id"] == "A18-spawnpoint-0" else []
        free, ev = bpa.verify_foot_box(envs["CF6_%s_BG.swf" % e["map"]], world, offsets)
        ok(free, "D %s foot-box 36x18 all-free + walkBounds" % e["id"],
           "; ".join("%s:%s" % (o["offset"], o["freeSamples"]) for o in ev["offsetChecks"]))

    # --- E: A18 referencing wave enemy intact ---
    a18w = post_by_id["A18"]["stage"]["Wave"]["SubWave"][1]["EnemyGroup"]["Enemy"][0]
    ok(a18w.get("SpawnIndex") == 0 and "x" not in a18w and "y" not in a18w
       and a18w.get("Type") == "兵种463",
       "E A18 Wave[1][0] keeps SpawnIndex=0, no x/y added")

    # --- F: per-map enemy Quantity totals unchanged ---
    def totals(doc):
        out = {}
        for m in doc["maps"]:
            t = sum(e["Quantity"] for w in m["stage"]["Wave"]["SubWave"]
                    for e in w["EnemyGroup"]["Enemy"])
            t += sum(e["Quantity"] for g in m.get("bossEncounter", {}).get("groups", [])
                     for e in g["enemies"])
            out[m["id"]] = t
        return out
    ok(totals(pre_maps) == totals(post_maps), "F per-map enemy Quantity totals unchanged",
       json.dumps(totals(post_maps), ensure_ascii=False))

    if failures:
        print("\n%d assertion(s) FAILED" % len(failures))
        sys.exit(1)
    print("\nall assertions passed")


if __name__ == "__main__":
    main()
