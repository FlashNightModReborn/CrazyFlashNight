#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the explicit CF7 placement adaptation table for the r6 geometry fails
(K3 content lane). Never edits encounter-facts.v1.json (historical provenance
stays), never touches data/stages/books/cf6-sting.json (root assembles), never
moves any enemy beyond the 5 declared landing spots.

  python -X utf8 tools/cf6-roguelike-content/build-placement-adaptation.py
      write mode: current maps.fragment.json must still hold the ORIGINAL
      coordinates; computes adapted points and writes
      data/stages/books/cf6-sting-source/placement-adaptation.v1.json
  python -X utf8 tools/cf6-roguelike-content/build-placement-adaptation.py --check
      verify mode: maps.fragment.json must already hold the ADAPTED
      coordinates (generator applied); re-verifies identity, geometry and
      input hashes. Exit 2 on any mismatch (refuse, never silently adjust).

Geometry authority: final environment walkBounds/Collision from
tools/cf6-map-runtime/generated/environment.fragment.xml (world space);
inverse transform uses nativeBounds origin from
tools/cf6-map-source/generated/map-input.json (worldScale must be 1), so root
assembly still subtracts the origin exactly once.
Safety rule: a candidate is the nearest point whose whole 36x18px foot box
(+/-18 x, +/-9 y) is collision-free on a 1px lattice AND strictly inside
walkBounds AND reachable from PlayerX/Y on the 5px reference grid; raw floats
hugging a collision edge are rejected by construction.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import deque

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from unit_registry import UnitRegistry
REGISTRY = UnitRegistry.load(ROOT)
SRC = os.path.join(ROOT, "data/stages/books/cf6-sting-source")
ENV_XML = os.path.join(ROOT, "tools/cf6-map-runtime/generated/environment.fragment.xml")
MAPINPUT = os.path.join(ROOT, "tools/cf6-map-source/generated/map-input.json")
RIDX = os.path.join(ROOT, "tools/cf6-map-runtime/generated/runtime-index.json")
FACTS = os.path.join(SRC, "encounter-facts.v1.json")
FRAG = os.path.join(SRC, "maps.fragment.json")
OUT = os.path.join(SRC, "placement-adaptation.v1.json")

FOOT_HALF_X = 18.0
FOOT_HALF_Y = 9.0
TOL = 0.051  # native coords are rounded to 0.1 in the fragment

# Declared r6 fail landing spots (5). Identity guards: the tool REFUSES when
# the current source point, the fact-table provenance, or the geometry
# premise does not match exactly what the r6 audit established.
TARGETS = [
    {"id": "A02-wave-0-3", "map": "A02", "kind": "waveEnemy",
     "fieldPath": "stage.Wave.SubWave[0].EnemyGroup.Enemy[3]",
     "unit": "cf6.生化僵尸.男", "originalNative": [828.8, 441.9],
     "factPath": ["statics", 3], "factIdentity": {"unit": "aw-僵尸", "xy": [828.75, 441.85]},
     "originalProvenance": "原作 display[13] id=477 depth=336 (aw-僵尸) — 作者摆放实例",
     "reason": "原作摆放位于原始 even-odd 填充体内;CF7 环境语义把填充转为实体 Collision,"
               "出生点落入多边形内部、玩家不可达(r6 fail#1)"},
    {"id": "A02-wave-0-5", "map": "A02", "kind": "waveEnemy",
     "fieldPath": "stage.Wave.SubWave[0].EnemyGroup.Enemy[5]",
     "unit": "cf6.生化僵尸.男", "originalNative": [1085.8, 463.9],
     "factPath": ["statics", 5], "factIdentity": {"unit": "aw-僵尸", "xy": [1085.75, 463.85]},
     "originalProvenance": "原作 display[15] id=477 depth=411 (aw-僵尸) — 作者摆放实例",
     "reason": "同 r6 fail#2:填充体内摆放,转换后落入实体 Collision,玩家不可达"},
    {"id": "A18-spawnpoint-0", "map": "A18", "kind": "spawnPoint",
     "fieldPath": "stage.SpawnPoint.Point[0]",
     "unit": None,
     "referencing": [{"fieldPath": "stage.Wave.SubWave[1].EnemyGroup.Enemy[0]",
                      "unit": "cf6.蛮斧刽子手", "spawnIndex": 0}],
     "engineOffsets": [[0, 2]],
     "originalNative": [856.5, 191.2],
     "factPath": ["generators", 1], "factIdentity": {"instance": "敌人生成器1", "xy": [856.45, 191.15]},
     "originalProvenance": "原作 display[12] id=1434 name='敌人生成器1' depth=290 — 触发区(1868)激活的生成器",
     "reason": "r6 fail#3/#4:生成点落在墙带填充内,转换后为实体 Collision;引擎出生仅 +2y"
               "(WaveSpawner Offset)不足以脱出,引用它的 Wave[1][0](SpawnIndex=0)随本点一并修复"},
    {"id": "A20-boss-0-0", "map": "A20", "kind": "bossEnemy",
     "fieldPath": "bossEncounter.groups[0].enemies[0]",
     "unit": "cf6.特种兵.持盾一阶段", "originalNative": [185.0, 162.0],
     "factPath": ["generators", 5], "factIdentity": {"unit": "敌人-特种兵-带盾", "xy": [185.0, 162.0]},
     "originalProvenance": "原作 display[18] id=1434 depth=225 — door1 门刷点(门触发演出属机关线,首版按血量阈值发兵)",
     "reason": "r6 fail#5:门刷点在墙内填充体,转换后落入实体 Collision,玩家不可达"},
    {"id": "A22-boss-0-3", "map": "A22", "kind": "bossEnemy",
     "fieldPath": "bossEncounter.groups[0].enemies[3]",
     "unit": "cf6.大刀机器人", "originalNative": [185.0, 162.0],
     "factPath": ["generators", 5], "factIdentity": {"unit": "敌人-大刀机器人", "xy": [185.0, 162.0]},
     "originalProvenance": "与 A20 共享门几何(A20/A22 walkBounds/碰撞相同),原作 display[18] 同位 id=1434",
     "reason": "r6 fail#6:同 A20 boss[0][0] 的门内墙填充问题"},
]

UNCHANGED_PENDING = [
    "A06 bossEncounter.groups[0].enemies[5] 兵种466 屏外对称入场位(世界(8.45,338.8),原作 id=1585 同位) — 保持不改,实机待核",
    "A17 bossEncounter.groups[0].enemies[6..7] 兵种469 屏外对称入场位(世界(4.0,369.9)/(1546.9,416.3)) — 保持不改,实机待核",
    "A17 Wave[0][0] 兵种472 Boss 原作同位高度(世界(963.55,305.9),walkBounds 顶上方 23.35px) — 保持不改,实机待核",
    "TUTORIAL 既有门矩形上沿越 Ymin 2px(vanilla 引擎惯例,39 门中 23 个越界) — 保持不改",
]


def refuse(msg):
    print("REFUSE:", msg)
    sys.exit(2)


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def load_json(path):
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def point_inside(point, polygon):
    x, y = point
    odd = False
    n = len(polygon)
    for i in range(n):
        a, b = polygon[i], polygon[(i + 1) % n]
        if (a[1] > y) != (b[1] > y):
            edge_x = a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if x < edge_x:
                odd = not odd
    return odd


class Env:
    def __init__(self, node):
        self.name = node.findtext("BackgroundURL")
        self.xmin = float(node.findtext("Xmin"))
        self.ymin = float(node.findtext("Ymin"))
        self.xmax = float(node.findtext("Xmax"))
        self.ymax = float(node.findtext("Ymax"))
        self.collisions = []
        for c in node.findall("Collision"):
            poly = [tuple(float(v) for v in p.text.split(",")) for p in c.findall("Point")]
            xs = [p[0] for p in poly]
            ys = [p[1] for p in poly]
            self.collisions.append((poly, (min(xs), min(ys), max(xs), max(ys))))

    def in_bounds(self, p):
        return self.xmin < p[0] < self.xmax and self.ymin < p[1] < self.ymax

    def blocked(self, p):
        for poly, (x0, y0, x1, y1) in self.collisions:
            if x0 <= p[0] <= x1 and y0 <= p[1] <= y1 and point_inside(p, poly):
                return True
        return False

    def blocking_index(self, p):
        for i, (poly, (x0, y0, x1, y1)) in enumerate(self.collisions):
            if x0 <= p[0] <= x1 and y0 <= p[1] <= y1 and point_inside(p, poly):
                return i
        return None


def get_path(doc, path):
    """Resolve 'a.b[3].c' style field paths."""
    node = doc
    for tok in path.split("."):
        m = re.match(r"^([^\[\]]+)((\[\d+\])*)$", tok)
        if not m:
            refuse("bad fieldPath token: %s" % tok)
        node = node[m.group(1)]
        for idx in re.findall(r"\[(\d+)\]", m.group(2)):
            node = node[int(idx)]
    return node


def verify_foot_box(env, w, offsets=()):
    """Whole 36x18px foot box on a 1px lattice must be collision-free and
    strictly inside walkBounds; extra engine offsets (e.g. spawn +2y) too."""
    checks = [(0.0, 0.0)] + [tuple(o) for o in offsets]
    evidence = {"footBoxHalf": [FOOT_HALF_X, FOOT_HALF_Y], "latticeStepPx": 1,
                "offsetChecks": [], "walkBoundsContained": True}
    for dx, dy in checks:
        cx, cy = w[0] + dx, w[1] + dy
        if not (env.xmin < cx - FOOT_HALF_X and cx + FOOT_HALF_X < env.xmax
                and env.ymin < cy - FOOT_HALF_Y and cy + FOOT_HALF_Y < env.ymax):
            evidence["walkBoundsContained"] = False
            return False, evidence
        nx = int(round(2 * FOOT_HALF_X)) + 1
        ny = int(round(2 * FOOT_HALF_Y)) + 1
        total = free = 0
        for iy in range(ny + 1):
            py = cy - FOOT_HALF_Y + (2 * FOOT_HALF_Y) * iy / ny
            for ix in range(nx + 1):
                px = cx - FOOT_HALF_X + (2 * FOOT_HALF_X) * ix / nx
                total += 1
                if not env.blocked((px, py)):
                    free += 1
        evidence["offsetChecks"].append({"offset": [dx, dy], "freeSamples": "%d/%d" % (free, total)})
        if free != total:
            return False, evidence
    return True, evidence


def reachable_grid(env, spawn, step=5.0):
    """5px reference BFS from PlayerX/Y (reference only, not AVM1 proof)."""
    x0, y0, x1, y1 = env.xmin, env.ymin, env.xmax, env.ymax
    nxc = int((x1 - x0) / step)
    nyc = int((y1 - y0) / step)
    free = set()
    for xi in range(nxc):
        for yi in range(nyc):
            if not env.blocked((x0 + (xi + 0.5) * step, y0 + (yi + 0.5) * step)):
                free.add((xi, yi))
    if not free:
        return None

    def nearest(p):
        return min(free, key=lambda c: (x0 + (c[0] + 0.5) * step - p[0]) ** 2
                   + (y0 + (c[1] + 0.5) * step - p[1]) ** 2)

    start = nearest(spawn)
    seen = {start}
    q = deque([start])
    while q:
        c = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nb = (c[0] + dx, c[1] + dy)
            if nb in free and nb not in seen:
                seen.add(nb)
                q.append(nb)
    return lambda p: nearest(p) in seen


def find_adapted(env, world0, origin, spawn_world, offsets):
    """Nearest box-free, reachable point; snapped to 0.1 in native space."""
    is_reachable = reachable_grid(env, spawn_world)
    if is_reachable is None:
        refuse("no free cells on reference grid for %s" % env.name)
    hx, hy = FOOT_HALF_X, FOOT_HALF_Y
    ox, oy = origin
    for rad in (96.0, 224.0, 1e9):
        if rad > 1e8:
            wx0, wy0, wx1, wy1 = env.xmin, env.ymin, env.xmax, env.ymax
        else:
            wx0, wy0 = world0[0] - rad, world0[1] - rad
            wx1, wy1 = world0[0] + rad, world0[1] + rad
        # raster window covers the box margin as well
        gx0 = int(math.floor(max(wx0 - hx - 1, env.xmin + 0.001)))
        gy0 = int(math.floor(max(wy0 - hy - 1, env.ymin + 0.001)))
        gx1 = int(math.ceil(min(wx1 + hx + 1, env.xmax - 0.001)))
        gy1 = int(math.ceil(min(wy1 + hy + 1, env.ymax - 0.001)))
        w = gx1 - gx0 + 1
        h = gy1 - gy0 + 1
        if w <= 0 or h <= 0:
            continue
        blocked = bytearray(w * h)
        for iy in range(h):
            py = gy0 + iy
            row = iy * w
            for ix in range(w):
                if env.blocked((gx0 + ix, py)):
                    blocked[row + ix] = 1
        # summed-area table for O(1) full-rect queries
        sat = [[0] * (w + 1) for _ in range(h + 1)]
        for iy in range(h):
            acc = 0
            srow = sat[iy + 1]
            prow = sat[iy]
            brow = iy * w
            for ix in range(w):
                acc += blocked[brow + ix]
                srow[ix + 1] = prow[ix + 1] + acc

        def rect_solid(cx, cy):
            ax = int(math.ceil(cx - hx)) - gx0
            ay = int(math.ceil(cy - hy)) - gy0
            bx = int(math.floor(cx + hx)) - gx0
            by = int(math.floor(cy + hy)) - gy0
            if ax < 0 or ay < 0 or bx >= w or by >= h:
                return True
            return (sat[by + 1][bx + 1] - sat[ay][bx + 1]
                    - sat[by + 1][ax] + sat[ay][ax]) > 0

        cands = []
        cx0 = int(math.ceil(max(wx0, env.xmin + hx + 0.01)))
        cx1 = int(math.floor(min(wx1, env.xmax - hx - 0.01)))
        cy0 = int(math.ceil(max(wy0, env.ymin + hy + 0.01)))
        cy1 = int(math.floor(min(wy1, env.ymax - hy - 0.01)))
        for cy in range(cy0, cy1 + 1):
            for cx in range(cx0, cx1 + 1):
                if rect_solid(cx, cy):
                    continue
                d = (cx - world0[0]) ** 2 + (cy - world0[1]) ** 2
                cands.append((d, cx, cy))
        cands.sort()
        for _, cx, cy in cands[:300]:
            native = [round(cx + ox, 1), round(cy + oy, 1)]
            final_world = (native[0] - ox, native[1] - oy)
            ok, evidence = verify_foot_box(env, final_world, offsets)
            if not ok:
                continue
            if not is_reachable(final_world):
                continue
            return native, list(final_world), evidence
    refuse("no box-free reachable candidate found near %s for %s"
           % (world0, env.name))


def main():
    check_mode = "--check" in sys.argv
    envs = {e.findtext("BackgroundURL"): Env(e)
            for e in ET.parse(ENV_XML).getroot().findall("Environment")}
    mapinput = load_json(MAPINPUT)["maps"]
    if isinstance(mapinput, list):
        mapinput = {m["id"]: m for m in mapinput}
    facts = {m["id"]: m for m in load_json(FACTS)["maps"]}
    frag = {m["id"]: m for m in load_json(FRAG)["maps"]}
    ridx = {m["id"]: m for m in load_json(RIDX)["maps"]}

    entries = []
    for t in TARGETS:
        mid = t["map"]
        fm = frag.get(mid)
        if fm is None:
            refuse("%s missing from maps.fragment.json" % mid)
        nb = mapinput[mid]["nativeBounds"]
        if mapinput[mid]["worldScale"] != 1:
            refuse("%s worldScale != 1 (%s); inverse transform would be wrong"
                   % (mid, mapinput[mid]["worldScale"]))
        origin = (nb[0], nb[1])
        env = envs.get("CF6_%s_BG.swf" % mid)
        if env is None:
            refuse("%s missing from environment.fragment.xml" % mid)

        # --- identity guard 1: current fragment field holds the expected value ---
        cur = get_path(fm, t["fieldPath"])
        expect = t["newNative"] if (check_mode and "newNative" in t) else None
        if check_mode:
            prev = load_json(OUT)["entries"]
            rec = next((e for e in prev if e["id"] == t["id"]), None)
            if rec is None:
                refuse("%s missing from existing adaptation table" % t["id"])
            want = rec["newNative"]
            if abs(cur["x"] - want[0]) > TOL or abs(cur["y"] - want[1]) > TOL:
                refuse("%s %s = (%s,%s), expected adapted (%s,%s); "
                       "run build-sting-fragments.py first or identity drifted"
                       % (mid, t["fieldPath"], cur.get("x"), cur.get("y"), want[0], want[1]))
        else:
            want = t["originalNative"]
            if abs(cur["x"] - want[0]) > TOL or abs(cur["y"] - want[1]) > TOL:
                refuse("%s %s = (%s,%s), expected original (%s,%s); "
                       "source drifted or already adapted — will not move blindly"
                       % (mid, t["fieldPath"], cur.get("x"), cur.get("y"), want[0], want[1]))
        if t["unit"] is not None and REGISTRY.resolve_id(cur.get("Type")) != REGISTRY.resolve_id(t["unit"]):
            refuse("%s %s Type=%s, expected %s (identity mismatch)"
                   % (mid, t["fieldPath"], cur.get("Type"), t["unit"]))
        for r in t.get("referencing", []):
            rn = get_path(fm, r["fieldPath"])
            if REGISTRY.resolve_id(rn.get("Type")) != REGISTRY.resolve_id(r["unit"]) or rn.get("SpawnIndex") != r["spawnIndex"]:
                refuse("%s referencing field %s identity mismatch" % (mid, r["fieldPath"]))

        # --- identity guard 2: fact-table provenance unchanged ---
        fact = facts[mid]
        fnode = fact[t["factPath"][0]][t["factPath"][1]]
        for k, v in t["factIdentity"].items():
            if k == "xy":
                if abs(fnode["xy"][0] - v[0]) > TOL or abs(fnode["xy"][1] - v[1]) > TOL:
                    refuse("%s facts %s%s xy=%s != %s" % (mid, t["factPath"][0], t["factPath"][1], fnode["xy"], v))
            elif fnode.get(k) != v:
                refuse("%s facts %s[%s] %s=%s != %s" % (mid, t["factPath"][0], t["factPath"][1], k, fnode.get(k), v))

        world0 = (t["originalNative"][0] - origin[0], t["originalNative"][1] - origin[1])
        if check_mode:
            # re-verify the recorded adapted point only
            rec_world = (rec["newNative"][0] - origin[0], rec["newNative"][1] - origin[1])
            ok, evidence = verify_foot_box(env, rec_world, t.get("engineOffsets", []))
            if not ok:
                refuse("%s adapted point %s failed foot-box re-verification" % (t["id"], rec_world))
            entries.append(rec)
            continue

        # --- geometry premise: the original world point really is blocked ---
        bi = env.blocking_index(world0)
        if not env.in_bounds(world0) or bi is None:
            refuse("%s original world %s not inside a collision polygon "
                   "(in_bounds=%s, poly=%s); premise mismatch, will not adapt"
                   % (t["id"], [round(v, 2) for v in world0], env.in_bounds(world0), bi))

        spawn_world = tuple(ridx[mid]["spawn"])
        native, final_world, evidence = find_adapted(
            env, world0, origin, spawn_world, t.get("engineOffsets", []))
        dist = math.hypot(final_world[0] - world0[0], final_world[1] - world0[1])
        entries.append({
            "id": t["id"], "map": mid, "kind": t["kind"],
            "fieldPath": t["fieldPath"],
            "referencingFields": [r["fieldPath"] for r in t.get("referencing", [])],
            "unit": t["unit"],
            "originalNative": t["originalNative"],
            "originalWorld": [round(world0[0], 4), round(world0[1], 4)],
            "originalProvenance": t["originalProvenance"],
            "factPath": "encounter-facts.v1.json %s %s[%d]" % (mid, t["factPath"][0], t["factPath"][1]),
            "reason": t["reason"],
            "origin": [origin[0], origin[1]],
            "premise": {"inWalkBounds": True, "insideCollision": True, "collisionIndex": bi},
            "newNative": native,
            "targetWorld": [round(final_world[0], 4), round(final_world[1], 4)],
            "distanceMovedPx": round(dist, 2),
            "verification": dict(evidence, connectivityRef="5px点格BFS自PlayerX/Y可达(参考,非AVM1寻路证明)"),
        })
        print("adapted %-18s %s native (%s,%s) -> (%s,%s)  world (%s,%s) -> (%s,%s)  %.1fpx"
              % (t["id"], mid,
                 t["originalNative"][0], t["originalNative"][1], native[0], native[1],
                 round(world0[0], 2), round(world0[1], 2),
                 round(final_world[0], 2), round(final_world[1], 2), dist))

    doc = {
        "schema": "cf6-placement-adaptation.v1",
        "status": "adopted-trial",
        "statusNote": "主控试作采纳初版集成的有界源数据适配;真实消费者(运行时单位脱困/寻路)待实机验证;"
                      "不声称原作完全复现。原始事实表与原坐标保持历史来源不变,本表记录原字段路径/原坐标/"
                      "目的世界坐标/反算 native 新坐标/碰撞理由;root 组装仍只减 nativeBounds 原点一次",
        "generatedBy": "tools/cf6-roguelike-content/build-placement-adaptation.py",
        "coordinateSpace": "native-original(与 maps.fragment.json 一致)",
        "geometryAuthority": {
            "environment": "tools/cf6-map-runtime/generated/environment.fragment.xml(最终 walkBounds/Collision,世界空间)",
            "origins": "tools/cf6-map-source/generated/map-input.json nativeBounds[:2](worldScale==1 已逐图核)",
            "footBox": "36x18px(±18横向/±9纵向)整盒 1px 栅格无碰撞且严格在 walkBounds 内;"
                       "候选按离原点最近可用区,并经 5px 参考格自出生点可达性过滤;不以贴碰撞边浮点充当安全点",
        },
        "inputSha256": {
            "encounter-facts.v1.json": sha256(FACTS),
            "environment.fragment.xml": sha256(ENV_XML),
            "map-input.json": sha256(MAPINPUT),
            "maps.fragment.json(pre-adaptation)": sha256(FRAG),
        },
        "unchangedPendingOnMachine": UNCHANGED_PENDING,
        "entries": entries,
    }
    if check_mode:
        prev = load_json(OUT)
        for k, v in doc["inputSha256"].items():
            if k.startswith("maps.fragment"):
                continue
            if prev["inputSha256"].get(k) != v:
                refuse("input hash drift for %s; re-run write mode and re-review" % k)
        print("check OK: %d adaptation entries re-verified (identity, geometry, hashes)"
              % len(entries))
        return
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    print("wrote", os.path.relpath(OUT, ROOT), "entries=%d" % len(entries))


if __name__ == "__main__":
    main()
