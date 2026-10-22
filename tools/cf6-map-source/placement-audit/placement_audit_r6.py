# -*- coding: utf-8 -*-
"""r6 placement audit (read-only): cf6-sting.json vs environment.fragment.xml /
runtime-index.json / route-geometry-overrides.json.

Checks per map:
  T1 identity/route completeness, A07/A21 structural expectations
  T2 transform-once: book coord == source coord - origin (scale=1), PlayerX/Y and
     mechanism layers already world-space (no second origin subtraction)
  T3 spatial: every explicit placement vs walkBounds / Collision polygons
  T4 door/exit geometry
  T5 mechanism consumption conditions (from Cf6MapMechanism.as read-only review)
  T6 reference connectivity grid (NOT Flash player-foot / pathfinding proof)

Never writes to inputs; never fabricates missing geometry; null coords stay null.
"""
from __future__ import annotations

import hashlib
import json
import os
import xml.etree.ElementTree as ET
from collections import deque

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

BOOK = "data/stages/books/cf6-sting.json"
FRAG = "tools/cf6-map-runtime/generated/environment.fragment.xml"
RIDX = "tools/cf6-map-runtime/generated/runtime-index.json"
OVER = "tools/cf6-map-runtime/route-geometry-overrides.json"
SRC = "data/stages/books/cf6-sting-source/maps.fragment.json"
MAPINPUT = "tools/cf6-map-source/generated/map-input.json"
STAGE_ENV = "data/environment/stage_environment.xml"

ROUTE = ["A%02d" % i for i in range(1, 23) if i not in (7, 21)]
MERCHANT = "生存战-迷之盔甲君"

TOL = 0.02  # world-coordinate comparison tolerance (values rounded to 4dp)


def sha256(path):
    with open(os.path.join(ROOT, path), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def load_json(path):
    with open(os.path.join(ROOT, path), encoding="utf-8-sig") as f:
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
    """One environment entry in CF7 world space."""

    def __init__(self, node):
        self.name = node.findtext("BackgroundURL")
        self.xmin = float(node.findtext("Xmin"))
        self.ymin = float(node.findtext("Ymin"))
        self.xmax = float(node.findtext("Xmax"))
        self.ymax = float(node.findtext("Ymax"))
        self.width = node.findtext("Width")
        self.height = node.findtext("Height")
        self.doors = [
            {
                "direction": d.findtext("Direction"),
                "rect": [float(d.findtext(k)) for k in ("x0", "y0", "x1", "y1")],
                "identifier": d.findtext("Identifier"),
            }
            for d in node.findall("Door")
        ]
        self.collisions = [
            [tuple(float(v) for v in p.text.split(",")) for p in c.findall("Point")]
            for c in node.findall("Collision")
        ]
        for tag, attr in (("LeftSpawnLine", "left_line"), ("RightSpawnLine", "right_line")):
            e = node.find(tag)
            setattr(self, attr, [float(e.findtext(k)) for k in ("x0", "y0", "x1", "y1")] if e is not None else None)

    def in_bounds(self, p, margin=0.0):
        return (self.xmin + margin < p[0] < self.xmax - margin
                and self.ymin + margin < p[1] < self.ymax - margin)

    def blocked(self, p):
        return any(point_inside(p, poly) for poly in self.collisions)

    def free(self, p, margin=0.0):
        if p[0] is None or p[1] is None:
            return None
        return self.in_bounds(p, margin) and not self.blocked(p)


def grid_connectivity(env, spawn, targets, step=5.0):
    """Point-grid BFS from spawn. Reference only: ignores player radius and AVM1."""
    x0, y0, x1, y1 = env.xmin, env.ymin, env.xmax, env.ymax
    nx = int((x1 - x0) / step)
    ny = int((y1 - y0) / step)
    if nx <= 0 or ny <= 0:
        return {"error": "degenerate bounds"}

    def center(cell):
        return (x0 + (cell[0] + 0.5) * step, y0 + (cell[1] + 0.5) * step)

    free = set()
    for xi in range(nx):
        for yi in range(ny):
            if not env.blocked(center((xi, yi))):
                free.add((xi, yi))
    if not free:
        return {"error": "no free cells"}

    def nearest_free(p):
        return min(free, key=lambda c: (center(c)[0] - p[0]) ** 2 + (center(c)[1] - p[1]) ** 2)

    start = nearest_free(spawn)
    visited = {start}
    queue = deque([start])
    while queue:
        c = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nb = (c[0] + dx, c[1] + dy)
            if nb in free and nb not in visited:
                visited.add(nb)
                queue.append(nb)

    out = {"gridStep": step, "freeCells": len(free), "reachableCells": len(visited),
           "start": [round(v, 2) for v in center(start)], "targets": []}
    for label, point in targets:
        if point[0] is None:
            out["targets"].append({"label": label, "reachable": None, "note": "null coordinate"})
            continue
        cell = nearest_free(point)
        dist = ((center(cell)[0] - point[0]) ** 2 + (center(cell)[1] - point[1]) ** 2) ** 0.5
        out["targets"].append({"label": label, "reachable": cell in visited,
                               "snapDistance": round(dist, 2)})
    return out


def merchant_anchor_free(env, spawn, anchor):
    """Re-run the assembler's own placement predicate (build-chapter.merchant_anchor)."""
    def free(p, margin):
        for dx in (-margin, 0, margin):
            for dy in (-margin / 2, 0, margin / 2):
                q = (p[0] + dx, p[1] + dy)
                if not env.in_bounds(q) or env.blocked(q):
                    return False
        return True

    dx, dy = anchor[0] - spawn[0], anchor[1] - spawn[1]
    if not free(anchor, 18):
        return False, "anchor 18px foot box not free"
    if not all(free((spawn[0] + dx * t / 12, spawn[1] + dy * t / 12), 8) for t in range(13)):
        return False, "approach corridor 8px samples not free"
    return True, "assembler predicate holds"


def main():
    inputs = {p: sha256(p) for p in (BOOK, FRAG, RIDX, OVER, SRC, MAPINPUT, STAGE_ENV)}
    book = load_json(BOOK)
    ridx = load_json(RIDX)
    over = load_json(OVER)
    src = load_json(SRC)
    mapinput = load_json(MAPINPUT)
    frag_root = ET.parse(os.path.join(ROOT, FRAG)).getroot()
    stage_env_root = ET.parse(os.path.join(ROOT, STAGE_ENV)).getroot()

    frag_envs = {e.findtext("BackgroundURL"): Env(e) for e in frag_root.findall("Environment")}
    stage_envs = {e.findtext("BackgroundURL"): e for e in stage_env_root.findall("Environment")}

    native = mapinput["maps"]
    if isinstance(native, list):
        native = {m["id"]: m for m in native}
    origin = {k: v["nativeBounds"][:2] for k, v in native.items()}
    scale = {k: v["worldScale"] for k, v in native.items()}

    book_maps = {m["id"]: m for m in book["maps"]}
    src_maps = {m["id"]: m for m in src["maps"]}
    ridx_maps = {m["id"]: m for m in ridx["maps"]}

    report = {"schema": "cf6-placement-audit-r6.v1",
              "inputSha256": inputs,
              "evidenceBoundary": "static point/grid geometry on assembled JSON+XML; "
                                  "connectivity grid is a reference, not Flash player-foot "
                                  "or AVM1 pathfinding proof; no game was run",
              "checks": []}

    def check(map_id, category, item, status, detail):
        report["checks"].append({"map": map_id, "category": category, "item": item,
                                 "status": status, "detail": detail})

    # ---------- T1 identity ----------
    book_ids = [m["id"] for m in book["maps"]]
    check("*", "identity", "book route", "pass" if book_ids == ["TUTORIAL"] + ROUTE else "fail",
          {"expected": ["TUTORIAL"] + ROUTE, "actual": book_ids})
    check("*", "identity", "runtime-index route", "pass" if sorted(ridx_maps) == sorted(ROUTE) else "fail",
          {"actual": sorted(ridx_maps)})
    check("*", "identity", "overrides route", "pass" if sorted(over["maps"]) == sorted(ROUTE) else "fail",
          {"actual": sorted(over["maps"])})
    frag_names = [e.findtext("BackgroundURL") for e in frag_root.findall("Environment")]
    check("*", "identity", "environment fragment route",
          "pass" if frag_names == ["CF6_%s_BG.swf" % m for m in ROUTE] else "fail",
          {"actual": frag_names})
    check("*", "identity", "A07 has no node",
          "pass" if "A07" not in book_maps and "A07" not in ridx_maps
          and "A07" not in over["maps"] and "CF6_A07_BG.swf" not in frag_envs else "fail",
          {"note": "A07 absent from book/runtime-index/overrides/environment fragment"})
    a20_note = "".join(book_maps["A20"].get("sourceNote", {}).get("notes", []))
    a21_swf = os.path.isfile(os.path.join(ROOT, "flashswf/backgrounds/cf6/CF6_A21_Transform.swf"))
    a21_xfl = os.path.isdir(os.path.join(ROOT, "flashswf/backgrounds/cf6/CF6_A21_Transform"))
    check("*", "identity", "A21 performance mechanism between A20 and A22",
          "pass" if ("A21由机关线演出" in a20_note and a21_xfl) else "fail",
          {"bookNotePresent": "A21由机关线演出" in a20_note,
           "consumer": "Cf6MapMechanism.beginRoom injects {role:transformation,"
                       " url:flashswf/backgrounds/cf6/CF6_A21_Transform.swf} when mapId==A20;"
                       " loaded() requires mc.actor._totalframes>92; render plays 93 frames/180",
           "transformSwfExists": a21_swf, "transformXflExists": a21_xfl,
           "swfStatus": "compiled SWF pending (Astra lane)" if not a21_swf else "present"})

    # ---------- per-map ----------
    for mid in ["TUTORIAL"] + ROUTE:
        bm = book_maps[mid]
        stage = bm["stage"]
        basic = stage.get("BasicInformation", {})
        player = (basic.get("PlayerX"), basic.get("PlayerY"))

        if mid == "TUTORIAL":
            env_node = stage_envs.get("gk1_1_BG.swf")
            env = Env(env_node) if env_node is not None else None
            check(mid, "registration", "tutorial environment gk1_1_BG.swf",
                  "pass" if env is not None else "fail", {})
        else:
            env = frag_envs.get("CF6_%s_BG.swf" % mid)

        rm = ridx_maps.get(mid)
        om = over["maps"].get(mid)
        sm = src_maps.get(mid)
        ox, oy = origin.get(mid, (None, None))

        # --- T2 transform-once ---
        if mid != "TUTORIAL":
            if scale.get(mid) != 1:
                check(mid, "transform", "worldScale", "fail", {"worldScale": scale.get(mid)})
            # PlayerX/Y must equal runtime spawn (already world), NOT source - 2*origin
            rs = rm["spawn"] if rm else None
            ok = rs and abs(player[0] - rs[0]) <= TOL and abs(player[1] - rs[1]) <= TOL
            check(mid, "transform", "PlayerX/Y == runtime-index spawn (already world)",
                  "pass" if ok else "fail",
                  {"book": list(player), "runtimeSpawn": rs,
                   "note": "assembler copies runtime spawn; must not subtract origin again"})
            if om and rs:
                exp = [round(om["spawn"][0] - ox, 4), round(om["spawn"][1] - oy, 4)]
                ok = abs(rs[0] - exp[0]) <= TOL and abs(rs[1] - exp[1]) <= TOL
                check(mid, "transform", "runtime spawn == overrides spawn - origin (once)",
                      "pass" if ok else "fail",
                      {"overridesSpawn": om["spawn"], "expected": exp, "runtimeSpawn": rs,
                       "spawnAdjusted": om["geometryBasis"]["spawnAdjusted"],
                       "spawnAdjustment": om["geometryBasis"].get("spawnAdjustment")})
            # mechanism copied verbatim (already world coords)
            mech_same = bm.get("mechanism") == (rm or {}).get("mechanism")
            check(mid, "transform", "mechanism layers identical to runtime-index (no re-transform)",
                  "pass" if mech_same else "fail", {"bookMechanism": bm.get("mechanism")})
            # environment fragment == overrides - origin
            if om and env:
                exp_bounds = [om["walkBounds"][0] - ox, om["walkBounds"][1] - oy,
                              om["walkBounds"][2] - ox, om["walkBounds"][3] - oy]
                got = [env.xmin, env.ymin, env.xmax, env.ymax]
                ok = all(abs(a - b) <= TOL for a, b in zip(exp_bounds, got))
                check(mid, "transform", "walkBounds fragment == overrides - origin",
                      "pass" if ok else "fail", {"expected": exp_bounds, "actual": got})
                if om.get("exit") and env.doors:
                    er = om["exit"]["rect"]
                    exp_rect = [er[0] - ox, er[1] - oy, er[2] - ox, er[3] - oy]
                    ok = any(all(abs(a - b) <= TOL for a, b in zip(exp_rect, d["rect"]))
                             and d["direction"] == om["exit"]["direction"] for d in env.doors)
                    check(mid, "transform", "exit Door rect == overrides.exit - origin",
                          "pass" if ok else "fail",
                          {"expected": exp_rect, "doors": env.doors})
                # collision trapezoids: same count, pairwise equal after shift
                oc = om["collisions"]
                same_n = len(oc) == len(env.collisions)
                mism = []
                if same_n:
                    for i, (poly_o, poly_f) in enumerate(zip(oc, env.collisions)):
                        if len(poly_o) != len(poly_f) or any(
                                abs(a[0] - ox - b[0]) > TOL or abs(a[1] - oy - b[1]) > TOL
                                for a, b in zip(poly_o, poly_f)):
                            mism.append(i)
                check(mid, "transform", "collision polygons fragment == overrides - origin",
                      "pass" if same_n and not mism else "fail",
                      {"overridesCount": len(oc), "fragmentCount": len(env.collisions),
                       "mismatchIndex": mism})
                for tag, line in (("leftSpawnLine", env.left_line), ("rightSpawnLine", env.right_line)):
                    ol = om.get(tag)
                    if ol is None and line is None:
                        continue
                    exp = [ol[0] - ox, ol[1] - oy, ol[2] - ox, ol[3] - oy] if ol else None
                    ok = exp and line and all(abs(a - b) <= TOL for a, b in zip(exp, line))
                    check(mid, "transform", tag + " fragment == overrides - origin",
                          "pass" if ok else "fail", {"expected": exp, "actual": line})

            # authored placements: book == source - origin
            if sm:
                def cmp_lists(category, src_list, book_list, keyfields):
                    used = [False] * len(book_list)
                    for s in src_list:
                        if all(s.get(k) is None for k in ("x", "y")) or ("x" not in s and "y" not in s):
                            continue
                        if "x" not in s or "y" not in s:
                            check(mid, "transform", category, "unknown",
                                  {"source": s, "note": "partial coordinates; not coerced"})
                            continue
                        exp = (round(s["x"] - ox, 4), round(s["y"] - oy, 4))
                        best = None
                        for i, b in enumerate(book_list):
                            if used[i] or any(b.get(k) != s.get(k) for k in keyfields):
                                continue
                            if "x" not in b or "y" not in b:
                                continue
                            d = (abs(b["x"] - exp[0]) + abs(b["y"] - exp[1]))
                            if best is None or d < best[0]:
                                best = (d, i, b)
                        if best is None:
                            check(mid, "transform", category, "fail",
                                  {"source": s, "expectedWorld": list(exp),
                                   "note": "no matching book placement (removed by economy merge?)"})
                            continue
                        used[best[1]] = True
                        b = best[2]
                        if abs(b["x"] - exp[0]) <= TOL and abs(b["y"] - exp[1]) <= TOL:
                            continue
                        if abs(b["x"] - s["x"]) <= TOL and abs(b["y"] - s["y"]) <= TOL:
                            kind = "MISSING transform (book==source)"
                        elif abs(b["x"] - (s["x"] - 2 * ox)) <= TOL and abs(b["y"] - (s["y"] - 2 * oy)) <= TOL:
                            kind = "DOUBLE transform (book==source-2*origin)"
                        else:
                            kind = "drift"
                        check(mid, "transform", category, "fail",
                              {"source": [s["x"], s["y"]], "expectedWorld": list(exp),
                               "book": [b["x"], b["y"]], "kind": kind,
                               "keys": {k: s.get(k) for k in keyfields}})

                sinst = [i for i in sm["stage"].get("Instances", {}).get("Instance", [])
                         if i.get("Identifier") != MERCHANT]
                binst = [i for i in stage.get("Instances", {}).get("Instance", [])
                         if i.get("Identifier") != MERCHANT]
                cmp_lists("Instances", sinst, binst, ("Identifier",))
                gold = ("金币",)
                spick = [p for p in sm["stage"].get("Pickups", {}).get("Pickup", [])
                         if p.get("Name") not in gold]
                bpick = [p for p in stage.get("Pickups", {}).get("Pickup", [])
                         if p.get("Name") not in gold]
                cmp_lists("Pickups", spick, bpick, ("Name", "Value"))
                cmp_lists("SpawnPoint",
                          sm["stage"].get("SpawnPoint", {}).get("Point", []),
                          stage.get("SpawnPoint", {}).get("Point", []), ("QuantityMax",))
                for wi, (sw, bw) in enumerate(zip(sm["stage"]["Wave"]["SubWave"],
                                                  stage["Wave"]["SubWave"])):
                    cmp_lists("Wave[%d]" % wi,
                              sw["EnemyGroup"]["Enemy"], bw["EnemyGroup"]["Enemy"],
                              ("Type", "Level"))
                for gi, (sg, bg) in enumerate(zip(sm.get("bossEncounter", {}).get("groups", []),
                                                  bm.get("bossEncounter", {}).get("groups", []))):
                    cmp_lists("bossEncounter[%d]" % gi, sg["enemies"], bg["enemies"],
                              ("Type", "Level"))
                # economy-added gold must sit exactly on PlayerX/Y
                for p in stage.get("Pickups", {}).get("Pickup", []):
                    if p.get("Name") == "金币":
                        ok = abs(p["x"] - player[0]) <= TOL and abs(p["y"] - player[1]) <= TOL
                        check(mid, "transform", "economy gold pickup on PlayerX/Y",
                              "pass" if ok else "fail",
                              {"gold": [p["x"], p["y"]], "player": list(player)})

        # --- geometryBasis equality book vs runtime-index ---
        if mid != "TUTORIAL" and rm:
            check(mid, "registration", "geometryBasis book == runtime-index",
                  "pass" if bm.get("geometryBasis") == rm.get("geometryBasis") else "fail", {})

        # --- T3 spatial ---
        def spatial(category, label, p, allow_offscreen_hint):
            if p[0] is None or p[1] is None:
                check(mid, category, label, "unknown", {"note": "null coordinate; not coerced to 0"})
                return
            if env is None:
                check(mid, category, label, "unknown", {"note": "no environment entry"})
                return
            inb = env.in_bounds(p)
            blk = env.blocked(p) if inb else False
            if inb and not blk:
                check(mid, category, label, "pass", {"world": list(p)})
            elif inb and blk:
                check(mid, category, label, "fail",
                      {"world": list(p), "reason": "inside collision polygon",
                       "walkBounds": [env.xmin, env.ymin, env.xmax, env.ymax]})
            else:
                status = "unknown" if allow_offscreen_hint else "fail"
                check(mid, category, label, status,
                      {"world": list(p), "reason": "outside walkBounds",
                       "walkBounds": [env.xmin, env.ymin, env.xmax, env.ymax],
                       "offscreenJustification": allow_offscreen_hint})

        spatial("spawn", "PlayerX/Y", player, None)
        for p in stage.get("Pickups", {}).get("Pickup", []):
            spatial("pickup", "%s x%s" % (p.get("Name"), p.get("Value")),
                    (p.get("x"), p.get("y")), None)
        for inst in stage.get("Instances", {}).get("Instance", []):
            spatial("merchant" if inst.get("Identifier") == MERCHANT else "instance",
                    inst.get("Identifier"), (inst.get("x"), inst.get("y")), None)
        notes_text = json.dumps(bm.get("sourceNote", {}), ensure_ascii=False)
        for wi, w in enumerate(stage.get("Wave", {}).get("SubWave", [])):
            for ei, e in enumerate(w["EnemyGroup"]["Enemy"]):
                label = "Wave[%d][%d] %s L%s" % (wi, ei, e.get("Type"), e.get("Level"))
                if "x" in e and "y" in e:
                    hint = None
                    p = (e.get("x"), e.get("y"))
                    if env is not None and p[0] is not None and not env.in_bounds(p):
                        hint = "screen-edge/off-screen spawn; verify intent in sourceNote"
                        if ("屏外" in notes_text or "门" in notes_text):
                            hint = "sourceNote mentions 屏外/门 spawn context"
                    spatial("waveEnemy", label, p, hint)
                elif e.get("SpawnIndex") in ("left", "right"):
                    line = env.left_line if e["SpawnIndex"] == "left" else env.right_line
                    if env is not None and line is None:
                        check(mid, "waveEnemy", label, "fail",
                              {"reason": "SpawnIndex=%s but environment has no %s spawn line"
                               % (e["SpawnIndex"], e["SpawnIndex"])})
                    elif env is not None:
                        blocked_samples = sum(
                            1 for t in range(21)
                            if env.blocked(((line[0] + line[2]) / 2,
                                            line[1] + (line[3] - line[1]) * t / 20)))
                        check(mid, "waveEnemy", label,
                              "pass" if blocked_samples == 0 else "fail",
                              {"spawnLine": line, "blockedSamplesOf21": blocked_samples,
                               "semantics": "WaveSpawner random point on %s line" % e["SpawnIndex"]})
                elif isinstance(e.get("SpawnIndex"), int) and e["SpawnIndex"] > -1:
                    pts = stage.get("SpawnPoint", {}).get("Point", [])
                    idx = e["SpawnIndex"]
                    if idx >= len(pts):
                        check(mid, "waveEnemy", label, "fail",
                              {"reason": "SpawnIndex %d but only %d SpawnPoint entries"
                               % (idx, len(pts))})
                    else:
                        spatial("waveEnemy", label + " via SpawnPoint[%d]" % idx,
                                (pts[idx].get("x"), pts[idx].get("y")), None)
                else:
                    lines_ok = env is not None and env.left_line and env.right_line
                    check(mid, "waveEnemy", label,
                          "pass" if lines_ok else "unknown",
                          {"semantics": "no x/y and no SpawnIndex: engine default "
                                        "1/3 left line, 2/3 right line (WaveSpawner.spawnEnemy default)",
                           "spawnLinesPresent": bool(lines_ok)})
        for gi, g in enumerate(bm.get("bossEncounter", {}).get("groups", [])):
            for ei, e in enumerate(g["enemies"]):
                label = "boss[%d][%d] %s L%s" % (gi, ei, e.get("Type"), e.get("Level"))
                if "x" in e and "y" in e:
                    spatial("bossEnemy", label, (e.get("x"), e.get("y")), None)
                elif e.get("SpawnIndex") in ("left", "right"):
                    line = env.left_line if e["SpawnIndex"] == "left" else env.right_line if env else None
                    check(mid, "bossEnemy", label, "pass" if line else "fail",
                          {"spawnLine": line,
                           "semantics": "boss reinforcement random point on %s line" % e["SpawnIndex"]})
                else:
                    check(mid, "bossEnemy", label, "unknown", {"enemy": e})
        for si, p in enumerate(stage.get("SpawnPoint", {}).get("Point", [])):
            spatial("spawnPoint", "SpawnPoint[%d] QuantityMax=%s" % (si, p.get("QuantityMax")),
                    (p.get("x"), p.get("y")), None)

        # --- T4 door/exit ---
        if env is not None:
            for di, d in enumerate(env.doors):
                r = d["rect"]
                in_b = (env.xmin <= r[0] and r[2] <= env.xmax
                        and env.ymin <= r[1] and r[3] <= env.ymax)
                samples = [(r[0] + (r[2] - r[0]) * i / 4, r[1] + (r[3] - r[1]) * j / 4)
                           for i in range(5) for j in range(5)]
                free_samples = sum(1 for s in samples
                                   if env.in_bounds(s) and not env.blocked(s))
                check(mid, "door", "Door[%d] %s" % (di, d["direction"]),
                      "pass" if in_b and free_samples > 0 else "fail",
                      {"rect": r, "insideWalkBounds": in_b,
                       "freeSamplesOf25": free_samples})

        # --- T5 mechanism consumption ---
        mech = bm.get("mechanism", {})
        layers = mech.get("layers", [])
        if mid in ("A10", "A13"):
            scroll = [l for l in layers if l.get("role") == "elevator-scroll"]
            ok = (len(scroll) == 1 and scroll[0].get("loopHeight", 0) > 0
                  and len(scroll[0].get("clip", [])) == 4)
            check(mid, "mechanism", "elevator fail-closed requirements",
                  "pass" if ok else "fail",
                  {"consumer": "Cf6MapMechanism.createState forces kind=elevator for A10/A13; "
                               "loadLayers fails closed without elevator-scroll (loopHeight>0, clip[4]); "
                               "exit stays closed until closing->moving->stopping->opening->ready",
                   "layers": scroll})
        if mech.get("kind") == "door":
            has_exit_seq = any(l.get("role") == "door-exit-sequence" for l in layers)
            has_leaves = (any(l.get("role") == "door-left" for l in layers)
                          and any(l.get("role") == "door-right" for l in layers))
            check(mid, "mechanism", "door kind requires leaves or exit sequence",
                  "pass" if (has_exit_seq or has_leaves) else "fail",
                  {"roles": [l.get("role") for l in layers]})
        for l in layers:
            if l.get("role") in ("door-spawn-sequence", "door-exit-sequence"):
                fr = l.get("frames")
                ok_frames = isinstance(fr, int) and 2 <= fr <= 120
                detail = {"id": l.get("id"), "frames": fr}
                if l.get("role") == "door-spawn-sequence":
                    sx, sy, sr = l.get("spawnX"), l.get("spawnY"), l.get("spawnRadius")
                    ok_r = isinstance(sr, (int, float)) and 0 < sr <= 300
                    detail.update({"spawnX": sx, "spawnY": sy, "spawnRadius": sr})
                    spatial_ok = env is not None and sx is not None and env.free((sx, sy))
                    check(mid, "mechanism", "door-spawn-sequence %s" % l.get("id"),
                          "pass" if (ok_frames and ok_r and spatial_ok) else "fail",
                          dict(detail, spawnPointFree=spatial_ok))
                else:
                    check(mid, "mechanism", "door-exit-sequence %s" % l.get("id"),
                          "pass" if ok_frames else "fail", detail)
            url = l.get("url", "")
            if url:
                exists = os.path.isfile(os.path.join(ROOT, url))
                check(mid, "registration", "layer swf %s" % os.path.basename(url),
                      "pass" if exists else "unknown",
                      {"url": url, "exists": exists,
                       "note": None if exists else "compiled SWF pending in Astra lane; "
                       "runtime fails closed on missing layer"})
        if mid != "TUTORIAL":
            bg = basic.get("Background", "")
            exists = os.path.isfile(os.path.join(ROOT, bg)) if bg else False
            check(mid, "registration", "background swf", "pass" if exists else "unknown",
                  {"url": bg, "exists": exists,
                   "note": None if exists else "compiled SWF pending in Astra lane"})

        # --- merchant anchor predicate ---
        for inst in stage.get("Instances", {}).get("Instance", []):
            if inst.get("Identifier") == MERCHANT and env is not None:
                ok, why = merchant_anchor_free(env, player, (inst["x"], inst["y"]))
                check(mid, "merchant", "assembler anchor predicate", "pass" if ok else "fail",
                      {"anchor": [inst["x"], inst["y"]], "reason": why})

        # --- T6 reference connectivity ---
        if env is not None and player[0] is not None:
            targets = []
            for di, d in enumerate(env.doors):
                r = d["rect"]
                targets.append(("door%d-center" % di, ((r[0] + r[2]) / 2, (r[1] + r[3]) / 2)))
            for p in stage.get("Pickups", {}).get("Pickup", []):
                targets.append(("pickup:%s" % p.get("Name"), (p.get("x"), p.get("y"))))
            for inst in stage.get("Instances", {}).get("Instance", []):
                targets.append(("instance:%s" % inst.get("Identifier"), (inst.get("x"), inst.get("y"))))
            conn = grid_connectivity(env, player, targets)
            unreachable = [t for t in conn.get("targets", []) if t.get("reachable") is False]
            check(mid, "connectivity", "reference grid BFS from PlayerX/Y",
                  "pass" if not unreachable and "error" not in conn else
                  ("unknown" if "error" in conn else "fail"),
                  dict(conn, caveat="point grid step %s; not player-radius/AVM1 proof" % conn.get("gridStep")))

    # merchant count
    merchants = [(m["id"], i["x"], i["y"]) for m in book["maps"]
                 for i in m["stage"].get("Instances", {}).get("Instance", [])
                 if i.get("Identifier") == MERCHANT]
    check("*", "merchant", "five merchants total",
          "pass" if len(merchants) == 5 else "fail",
          {"count": len(merchants), "at": merchants})

    out = os.path.join(ROOT, "tools/cf6-map-source/placement-audit/placement-audit-r6.json")
    with open(out, "w", encoding="utf-8") as f:
        f.write(json.dumps(report, ensure_ascii=False, indent=1) + "\n")

    total = len(report["checks"])
    by_status = {}
    for c in report["checks"]:
        by_status[c["status"]] = by_status.get(c["status"], 0) + 1
    print("checks:", total, by_status)
    for c in report["checks"]:
        if c["status"] != "pass":
            print(c["status"].upper(), c["map"], c["category"], c["item"],
                  json.dumps(c["detail"], ensure_ascii=False)[:220])


if __name__ == "__main__":
    main()
