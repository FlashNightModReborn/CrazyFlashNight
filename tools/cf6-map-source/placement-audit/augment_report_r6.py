# -*- coding: utf-8 -*-
"""r6 report augmentation: attach re-verification evidence (original authored
provenance, nearest-free fix candidates, walkability) to the flagged checks and
reclassify intentional off-screen spawns vs genuine in-collision placements.
Reads placement-audit-r6.json, writes it back ordered; read-only on game data."""
from __future__ import annotations

import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
REPORT = os.path.join(ROOT, "tools/cf6-map-source/placement-audit/placement-audit-r6.json")

report = json.load(open(REPORT, encoding="utf-8"))

PROVENANCE = {
    ("A02", "waveEnemy", "Wave[0][3] 兵种461 L36"): {
        "verdict": "fail",
        "sourceField": "maps.fragment.json A02 Wave[0].EnemyGroup.Enemy[3] x=828.8 y=441.9",
        "originalProvenance": "original display[13] id=477 depth=336 at (828.75,441.85) — authored placement",
        "geometry": "inside original even-odd fill AND inside converted Collision trapezoid; "
                    "original engine evidence of solid-fill movement blocking not found, "
                    "CF7 environment semantics treat the fill as solid",
        "playerCanReach": False,
        "nearestFreeWorld": [864.49, 388.82],
        "minimalFixCandidate": "nudge spawn to nearest free point ~(864.5,388.8) world "
                               "(30px) or mark unit as turret/static; needs 主控实机 to confirm "
                               "whether CF7 depenetration frees wall-spawned units",
    },
    ("A02", "waveEnemy", "Wave[0][5] 兵种461 L36"): {
        "verdict": "fail",
        "sourceField": "maps.fragment.json A02 Wave[0].EnemyGroup.Enemy[5] x=1085.8 y=463.9",
        "originalProvenance": "original display[15] id=477 depth=411 at (1085.75,463.85) — authored placement",
        "geometry": "inside original even-odd fill AND converted Collision",
        "playerCanReach": False,
        "nearestFreeWorld": [1137.53, 470.71],
        "minimalFixCandidate": "nudge spawn to ~(1137.5,470.7) world (32px); same caveat as Wave[0][3]",
    },
    ("A06", "bossEnemy", "boss[0][5] 兵种466 L41"): {
        "verdict": "unknown",
        "sourceField": "maps.fragment.json A06 bossEncounter.groups[0] 兵种466 x=5.0 y=305.4 SpawnIndex=left",
        "originalProvenance": "matches original display[7] id=1585 depth=91 at (5.0,305.45); "
                              "runtime-index A06 pendingDynamics lists sprite1585 as unidentified semantics",
        "geometry": "45px left of original walkBounds x0=50 (world x=8.45 < Xmin=53.45); "
                    "original authored off-screen entrance, symmetric to the in-bounds right pair",
        "playerCanReach": "not applicable (off-screen entrance; unit walks in)",
        "minimalFixCandidate": "none if entrance intent confirmed; alternatively drop explicit x/y and keep "
                               "SpawnIndex=left to spawn on the left line",
    },
    ("A17", "waveEnemy", "Wave[0][0] 兵种472 L57"): {
        "verdict": "unknown",
        "sourceField": "maps.fragment.json A17 Wave[0].Enemy[0] 兵种472 InstanceName=cf6Boss_A17 x=675.6 y=226.7",
        "originalProvenance": "matches original display[18] id=952 name='boss' depth=871 at (675.6,226.65) — "
                              "the original authored boss placement",
        "geometry": "23.35px above walkBounds top in both spaces (original 226.7 < 250; world 305.9 < Ymin 329.2)",
        "playerCanReach": "player cannot walk above Ymin; boss stand position unverifiable statically",
        "minimalFixCandidate": "keep original coordinate pending 主控实机; if boss is clamped/frozen, "
                               "lower to walk top edge (world y≈330)",
    },
    ("A17", "bossEnemy", "boss[0][6] 兵种469 L56"): {
        "verdict": "unknown",
        "sourceField": "maps.fragment.json A17 bossEncounter.groups[0] 兵种469 x=4.0 y=369.9 SpawnIndex=left",
        "originalProvenance": "matches original display[7] id=1585 depth=512 at (4.0,369.9); sprite1585 semantics unidentified",
        "geometry": "46px left of original walkBounds x0=50 (world 291.95 < Xmin 337.95); authored off-screen entrance",
        "playerCanReach": "not applicable (off-screen entrance)",
        "minimalFixCandidate": "none if entrance intent confirmed",
    },
    ("A17", "bossEnemy", "boss[0][7] 兵种469 L56"): {
        "verdict": "unknown",
        "sourceField": "maps.fragment.json A17 bossEncounter.groups[0] 兵种469 x=1546.9 y=416.3 SpawnIndex=right",
        "originalProvenance": "matches original display[8] id=1585 depth=514 at (1546.9,416.3)",
        "geometry": "46.9px right of original walkBounds x1=1500 (world 1834.85 > Xmax 1787.95); authored off-screen entrance",
        "playerCanReach": "not applicable (off-screen entrance)",
        "minimalFixCandidate": "none if entrance intent confirmed",
    },
    ("A18", "spawnPoint", "SpawnPoint[0] QuantityMax=2"): {
        "verdict": "fail",
        "sourceField": "maps.fragment.json A18 stage.SpawnPoint.Point[0] x=856.5 y=191.2",
        "originalProvenance": "matches original display[12] id=1434 name='敌人生成器1' depth=290 at (856.45,191.15)",
        "geometry": "inside original even-odd fill AND converted Collision; engine adds only +2y at spawn "
                    "(WaveSpawner Offset), insufficient: fill continues to y≈205.2 original (world 222.65)",
        "playerCanReach": False,
        "nearestFreeWorld": [885.0, 222.65],
        "minimalFixCandidate": "move SpawnPoint[0] to (885.0,222.65) world (14px down) or set Offset>=16; "
                               "confirm with 主控实机 whether door-spawned units escape the wall band",
    },
    ("A18", "waveEnemy", "Wave[1][0] 兵种463 L59 via SpawnPoint[0]"): {
        "verdict": "fail",
        "sourceField": "spawned through SpawnPoint[0] (see spawnPoint entry)",
        "geometry": "inherits SpawnPoint[0] in-collision position",
        "playerCanReach": False,
        "minimalFixCandidate": "fixed together with SpawnPoint[0]",
    },
    ("A20", "bossEnemy", "boss[0][0] 兵种467 L60"): {
        "verdict": "fail",
        "sourceField": "maps.fragment.json A20 bossEncounter.groups[0] 兵种467 x=185.0 y=162.0 SpawnIndex=left",
        "originalProvenance": "matches original display[18] id=1434 depth=225 at (185.0,162.0) — original door spawner; "
                              "sourceNote: 原门触发演出(door1/2/4)属机关线,首版按血量阈值发兵",
        "geometry": "inside original even-odd fill AND converted Collision (door-in-wall)",
        "playerCanReach": False,
        "nearestFreeWorld": [267.5, 192.38],
        "minimalFixCandidate": "nudge to (267.5,192.4) world (8px) or rely on SpawnIndex=left line; "
                               "same door-in-wall class as A18",
    },
    ("A22", "bossEnemy", "boss[0][3] 兵种465 L60"): {
        "verdict": "fail",
        "sourceField": "maps.fragment.json A22 bossEncounter.groups[0] 兵种465 x=185.0 y=162.0 SpawnIndex=left",
        "originalProvenance": "same shared door geometry as A20 (A20/A22 share walkBounds/collisions)",
        "geometry": "inside original even-odd fill AND converted Collision (door-in-wall)",
        "playerCanReach": False,
        "nearestFreeWorld": [267.5, 192.38],
        "minimalFixCandidate": "same as A20",
    },
}

patched = 0
for c in report["checks"]:
    key = (c["map"], c["category"], c["item"])
    if key in PROVENANCE:
        p = PROVENANCE[key]
        c["status"] = p["verdict"]
        c["detail"]["reverification"] = p
        patched += 1
    # vanilla-convention reclassification for the tutorial door
    if key == ("TUTORIAL", "door", "Door[0] 上"):
        c["status"] = "pass"
        c["detail"]["note"] = ("pre-existing vanilla map gk1_1_BG.swf (not produced by cf6 assembly); "
                               "door rects crossing the boundary wall are engine convention: "
                               "23/39 vanilla doors in stage_environment.xml extend past walkBounds; "
                               "20/25 rect samples free")
        patched += 1

# enrich background-registration unknowns with XFL presence
ridx = json.load(open(os.path.join(ROOT, "tools/cf6-map-runtime/generated/runtime-index.json"), encoding="utf-8"))
xfl_by_id = {m["id"]: m.get("xfl") for m in ridx["maps"]}
for c in report["checks"]:
    if c["category"] == "registration" and c["item"] == "background swf" and c["status"] == "unknown":
        xfl = xfl_by_id.get(c["map"])
        c["detail"]["xflPath"] = xfl
        c["detail"]["xflExists"] = os.path.isfile(os.path.join(ROOT, xfl)) if xfl else False

report["summary"] = {
    "total": len(report["checks"]),
    "byStatus": {s: sum(1 for c in report["checks"] if c["status"] == s)
                 for s in ("pass", "fail", "unknown")},
    "reverified": patched,
}
with open(REPORT, "w", encoding="utf-8") as f:
    f.write(json.dumps(report, ensure_ascii=False, indent=1) + "\n")
print("patched", patched, "summary", report["summary"])
