#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
source-boundary-check.py — CF6 无车战 20 图出生点"源证据边界"静态检查（K3 content r8，只读）

目的
----
对 cf6-sting 章节当前工作树版本，逐个敌人/支援怪/玩家/商人生成入口给出：
  1) 几何事实：世界坐标、是否在当前行走区 [Xmin,Ymin]-[Xmax,Ymax] 内、
     是否在边界墙环（行走区外扩 300px，见 CollisionLayerRenderer.drawBoundary）内、
     是否落入任一 Collision 多边形（even-odd 点测）；
  2) 现役源码语义分类：该入口在 WaveSpawner.spawnEnemy / Mover.move2D 路径下的
     静态可证行为（见 report.json 的 sourceEvidence，含 文件:行号 与源文件 SHA256）。

证据边界（必须随报告一起阅读）
------------------------------
- 本脚本只做静态点/多边形几何 + 已核源码路径的语义归类；不运行 Flash/CS6/游戏。
- "boundary_ring（墙环内）"只表示：单位一旦发起移动，Mover.move2D 的目标点 hitTest 会命中
  碰撞层并转入 resolveCollision 朝场景中心挤出（Mover.as:384-426）。单位是否/何时发起移动
  取决于 AI tick、待机/登场景门与 XFL 时间轴节律，静态无法证明，结论中一律标注 runtime-pending。
- 静止的界外单位没有任何逐帧代码修正其位置（无逐帧 clamp；enforceScreenBounds 不在逐帧路径）。
- beyond_ring 只表示超出这层边界墙环；其他碰撞和单位行为仍需独立判断，不能据此断言阻断。

用法
----
    tmp/cf6-py312/Scripts/python.exe tools/cf6-roguelike-content/placement-review/source-boundary-check.py
在仓库根执行；写出 tools/cf6-roguelike-content/placement-review/report.json（覆盖）。
只读输入，不修改任何被检查文件。
"""
import hashlib
import json
import os
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT_JSON = os.path.join(os.path.dirname(__file__), "report.json")

BOUNDARY_MARGIN = 300.0  # CollisionLayerRenderer.drawBoundary 默认 margin；SceneCollisionManager.as:112 显式传 300

DATA_INPUTS = [
    "data/stages/books/cf6-sting.json",
    "data/stages/books/cf6-sting-source/maps.fragment.json",
    "data/environment/stage_environment.xml",
    "tools/cf6-map-runtime/generated/runtime-index.json",
]

# 语义结论所绑定的源码文件（hash 变化即表示结论需重核）
SOURCE_EVIDENCE = {
    "spawn_verbatim_xy": {
        "file": "scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as",
        "lines": "353-416",
        "claim": "spawnEnemy 对显式 x/y 原样写入 initObject._x/_y（as:412-413），全程无 clamp；"
                 "仅 isNaN(x)||isNaN(y) 时才按 SpawnIndex 替换（数值→SpawnPoint，as:356-369；"
                 "'left'/'right'→出生线随机整点，as:370-383）。显式 x/y 绝对优先于 SpawnIndex。",
    },
    "spawn_support_entry": {
        "file": "scripts/类定义/org/flashNight/arki/scene/StageEvent.as",
        "lines": "184-199",
        "claim": "Cf6FiniteSupport 的 boss 支援怪与波次怪共用同一个 WaveSpawner.spawnEnemy 出口，"
                 "SpawnIndex 与 x/y 语义一致。",
    },
    "z_axis_from_y": {
        "file": "scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as",
        "lines": "723",
        "claim": "单位初始化 this.Z轴坐标 = this._y；无地面吸附、无行走带归位。",
    },
    "boundary_ring_draw": {
        "file": "scripts/类定义/org/flashNight/arki/collision/CollisionLayerRenderer.as",
        "lines": "45-90",
        "claim": "drawBoundary 以 [Xmin-300,Xmax+300]x[Ymin-300,Ymax+300] 外框减行走区内框绘制实心墙环；"
                 "环内点 hitTest=true（碰撞），行走区内与环外（>300px）为 false。",
    },
    "boundary_ring_margin": {
        "file": "scripts/类定义/org/flashNight/arki/scene/SceneCollisionManager.as",
        "lines": "98-114",
        "claim": "redraw 显式以 margin=300 调 drawBoundary（坐标经 calculateOffset 换算到碰撞层空间，语义不变）。",
    },
    "move_hit_test": {
        "file": "scripts/类定义/org/flashNight/arki/spatial/move/Mover.as",
        "lines": "134-158",
        "claim": "move2D 仅当目标点 hitTest 为 false 才写 _x/_y；命中则转 resolveCollision，本步不走。",
    },
    "resolve_push_in": {
        "file": "scripts/类定义/org/flashNight/arki/spatial/move/Mover.as",
        "lines": "384-426",
        "claim": "resolveCollision：当前点已在碰撞内时，按 lerp(移动方向, 指向场景中心) 归一化向量"
                 "以 max(speed,5) 步长挤出；两个分量在'单位于环内、目标在界内'场景下均指向界内，"
                 "该条件下存在朝界内挤出的路径。它不保证单位发起移动、到达界内或可被命中；无精确 clamp。",
    },
    "chase_z_seek": {
        "file": "scripts/类定义/org/flashNight/arki/unit/UnitAI/behavior/CombatModule.as",
        "lines": "136-148",
        "claim": "追击未进入攻击距离且非 standby 时设置 上行/下行 = sign(diff_z)、左行/右行 = x 方向；"
                 "AI 具有把界外单位沿 z/x 带回界内的方向性。",
    },
    "ai_ticks_offscreen": {
        "file": "scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/UpdateEventComponent.as",
        "lines": "54-56,93-107",
        "claim": "屏外剔除仅置 _visible=false（注释明言'仅控制渲染，不影响逻辑'）；unitAI.update() 无条件执行，"
                 "界外单位 AI 照常 tick。",
    },
    "no_spawn_depenetration": {
        "file": "scripts/类定义/org/flashNight/arki/spatial/move/Mover.as",
        "lines": "516-617",
        "claim": "pushOutFromCollision/enforceScreenBounds 仅被主角过场景钩子、装备与主角/佣兵 AI 卡死脱困调用；"
                 "普通敌人出生时刻无 depenetration，静止界外单位无任何代码修正其位置。",
    },
}


def sha256_of(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def load_json(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return json.load(f)


def parse_environments(rel):
    """stage_environment.xml -> {BackgroundURL: {Xmin,Ymin,Xmax,Ymax, collisions:[[(x,y),...],...]}}"""
    tree = ET.parse(os.path.join(ROOT, rel))
    envs = {}
    for env in tree.getroot().iter("Environment"):
        bg = env.findtext("BackgroundURL")
        if not bg:
            continue
        def num(tag):
            v = env.findtext(tag)
            return float(v) if v not in (None, "") else None
        polys = []
        for col in env.findall("Collision"):
            pts = []
            for p in col.findall("Point"):
                xs, ys = (p.text or "").split(",")
                pts.append((float(xs), float(ys)))
            if pts:
                polys.append(pts)
        envs[bg.strip()] = {
            "Xmin": num("Xmin"), "Ymin": num("Ymin"),
            "Xmax": num("Xmax"), "Ymax": num("Ymax"),
            "collisionPolygons": polys,
        }
    return envs


def point_in_poly_evenodd(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y):
            xint = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xint:
                inside = not inside
        j = i
    return inside


def classify_point(x, y, env):
    """返回 (zone, inside_collision_polygon)。zone: inside_walk/boundary_ring/beyond_ring/no_env"""
    if env is None or env["Xmin"] is None:
        return "no_env", None
    in_walk = (env["Xmin"] <= x <= env["Xmax"]) and (env["Ymin"] <= y <= env["Ymax"])
    in_outer = (env["Xmin"] - BOUNDARY_MARGIN <= x <= env["Xmax"] + BOUNDARY_MARGIN) and \
               (env["Ymin"] - BOUNDARY_MARGIN <= y <= env["Ymax"] + BOUNDARY_MARGIN)
    if in_walk:
        zone = "inside_walk"
    elif in_outer:
        zone = "boundary_ring"
    else:
        zone = "beyond_ring"
    in_poly = any(point_in_poly_evenodd(x, y, poly) for poly in env["collisionPolygons"])
    return zone, in_poly


def collect_entries(mid, m):
    """抽取 玩家/波次敌人/支援怪/商人/SpawnPoint 入口。"""
    stage = m.get("stage", {})
    out = {"player": [], "waveEnemy": [], "bossSupport": [], "merchant": [], "spawnPoint": []}
    bi = stage.get("BasicInformation") or {}
    if "PlayerX" in bi and "PlayerY" in bi:
        out["player"].append({"x": bi["PlayerX"], "y": bi["PlayerY"]})
    wave = stage.get("Wave") or {}
    subwaves = wave.get("SubWave") if isinstance(wave, dict) else wave
    for wi, sw in enumerate(subwaves or []):
        enemies = ((sw or {}).get("EnemyGroup") or {}).get("Enemy") or []
        for ei, e in enumerate(enemies):
            out["waveEnemy"].append({
                "ref": "Wave[%d][%d]" % (wi, ei),
                "Type": e.get("Type"), "Level": e.get("Level"),
                "x": e.get("x"), "y": e.get("y"),
                "SpawnIndex": e.get("SpawnIndex"),
                "InstanceName": e.get("InstanceName"),
            })
    be = m.get("bossEncounter") or {}
    for gi, g in enumerate(be.get("groups") or []):
        for ei, e in enumerate(g.get("enemies") or []):
            out["bossSupport"].append({
                "ref": "boss[%d][%d](hpRatio=%s)" % (gi, ei, g.get("hpRatio")),
                "Type": e.get("Type"), "Level": e.get("Level"),
                "x": e.get("x"), "y": e.get("y"),
                "SpawnIndex": e.get("SpawnIndex"),
            })
    inst = (stage.get("Instances") or {}).get("Instance") or []
    for ii, it in enumerate(inst):
        out["merchant"].append({
            "ref": "Instance[%d]" % ii,
            "Identifier": it.get("Identifier"),
            "x": it.get("x"), "y": it.get("y"),
        })
    sp = (stage.get("SpawnPoint") or {}).get("Point") or []
    for si, p in enumerate(sp):
        out["spawnPoint"].append({
            "ref": "SpawnPoint[%d]" % si,
            "x": p.get("x"), "y": p.get("y"),
            "QuantityMax": p.get("QuantityMax"),
        })
    return out


def evaluate_entry(e, spawn_points, env):
    """对单条入口给出几何+语义分类。显式 x/y 优先（WaveSpawner.as:354-413）。"""
    r = dict(e)
    x, y = e.get("x"), e.get("y")
    idx = e.get("SpawnIndex")
    if x is None or y is None:
        if isinstance(idx, int) and 0 <= idx < len(spawn_points):
            px, py = spawn_points[idx]
            r["resolution"] = "spawnPoint[%d] (WaveSpawner.as:356-369)" % idx
            x, y = px, py
        elif idx in ("left", "right"):
            r["resolution"] = "spawn-line random point, engine-resolved at runtime (WaveSpawner.as:370-383)"
            r["zone"] = "engine_spawn_line"
            return r
        else:
            r["resolution"] = "engine default spawn semantics (WaveSpawner.as:404-408)"
            r["zone"] = "engine_default"
            return r
    else:
        r["resolution"] = "explicit x/y verbatim, overrides SpawnIndex (WaveSpawner.as:412-413)"
    zone, in_poly = classify_point(float(x), float(y), env)
    r["world"] = [x, y]
    r["zone"] = zone
    r["insideCollisionPolygon"] = in_poly
    if env and env["Xmin"] is not None:
        r["walkBounds"] = [env["Xmin"], env["Ymin"], env["Xmax"], env["Ymax"]]
        r["distOutside"] = {
            "left": max(0.0, env["Xmin"] - float(x)),
            "right": max(0.0, float(x) - env["Xmax"]),
            "top": max(0.0, env["Ymin"] - float(y)),
            "bottom": max(0.0, float(y) - env["Ymax"]),
        }
    return r


def main():
    input_sha = {p: sha256_of(p) for p in DATA_INPUTS}
    source_sha = {}
    for key, ev in SOURCE_EVIDENCE.items():
        source_sha[ev["file"]] = sha256_of(ev["file"])
    with open(os.path.join(os.path.dirname(__file__), "reviewed-source-hashes.json"), encoding="utf-8") as f:
        reviewed = json.load(f)
    if source_sha != reviewed:
        raise ValueError("Reviewed source identity changed; re-review semantics before updating source pins")

    book = load_json("data/stages/books/cf6-sting.json")
    envs = parse_environments("data/environment/stage_environment.xml")

    maps = {}
    for m in book["maps"]:
        mid = m.get("mapId") or m.get("id")
        maps[mid] = m

    per_map = {}
    totals = {"inside_walk": 0, "boundary_ring": 0, "beyond_ring": 0,
              "engine_spawn_line": 0, "engine_default": 0, "no_env": 0,
              "inside_collision_polygon": 0}
    for mid in sorted(maps):
        m = maps[mid]
        bg = (m.get("background") or "").split("/")[-1]
        env = envs.get(bg)
        entries = collect_entries(mid, m)
        sp_points = [(p["x"], p["y"]) for p in entries["spawnPoint"]]
        emap = {}
        for cat in ("player", "waveEnemy", "bossSupport", "merchant", "spawnPoint"):
            evaluated = []
            for e in entries[cat]:
                if cat == "spawnPoint":
                    ev = dict(e)
                    if e.get("x") is not None:
                        zone, in_poly = classify_point(float(e["x"]), float(e["y"]), env)
                        ev["zone"] = zone
                        ev["insideCollisionPolygon"] = in_poly
                    evaluated.append(ev)
                else:
                    evaluated.append(evaluate_entry(e, sp_points, env))
            emap[cat] = evaluated
            for ev in evaluated:
                z = ev.get("zone")
                if z in totals:
                    totals[z] += 1
                if ev.get("insideCollisionPolygon"):
                    totals["inside_collision_polygon"] += 1
        per_map[mid] = {
            "background": bg,
            "walkBounds": ([env["Xmin"], env["Ymin"], env["Xmax"], env["Ymax"]]
                           if env and env["Xmin"] is not None else None),
            "counts": {cat: len(emap[cat]) for cat in emap},
            "entries": emap,
        }

    report = {
        "schema": "cf6-source-boundary-check-r8.v1",
        "generatedBy": "tools/cf6-roguelike-content/placement-review/source-boundary-check.py (K3 content r8, read-only)",
        "inputSha256": input_sha,
        "sourceEvidence": {k: dict(v, sha256=source_sha[v["file"]]) for k, v in SOURCE_EVIDENCE.items()},
        "boundaryMargin": BOUNDARY_MARGIN,
        "evidenceBoundary": (
            "静态点/多边形几何 + 已核源码路径语义归类；未运行 Flash/CS6/游戏。"
            "boundary_ring 仅表示'移动时 resolveCollision 朝心挤出路径适用'；"
            "单位是否/何时移动（AI tick、standby/登场门、XFL 时间轴节律）及精确回界帧数只能实机确定。"
            "静止界外单位无任何逐帧代码修正其位置。"
        ),
        "totals": totals,
        "maps": per_map,
    }
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print("wrote", os.path.relpath(OUT_JSON, ROOT))
    print("totals:", json.dumps(totals, ensure_ascii=False))
    # 简报：非 inside_walk 的显式点
    for mid in sorted(per_map):
        for cat in ("waveEnemy", "bossSupport"):
            for ev in per_map[mid]["entries"][cat]:
                if ev.get("zone") not in (None, "inside_walk", "engine_spawn_line", "engine_default"):
                    print("OUT-OF-WALK:", mid, cat, ev.get("ref"), ev.get("Type"),
                          "world=", ev.get("world"), "zone=", ev.get("zone"),
                          "outside=", ev.get("distOutside"), "inPoly=", ev.get("insideCollisionPolygon"))


if __name__ == "__main__":
    sys.exit(main())
