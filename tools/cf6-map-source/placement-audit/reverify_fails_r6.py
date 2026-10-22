# -*- coding: utf-8 -*-
"""r6 fail-item reverification: check each flagged world point against the ORIGINAL
even-odd fill paths (not the trapezoid decomposition) and find nearest free points.
Read-only; imports tools/cf6-map-runtime/geometry.py without modifying it."""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "cf6-map-runtime"))
import geometry  # noqa: E402

MAPINPUT = json.load(open(os.path.join(ROOT, "tools/cf6-map-source/generated/map-input.json"), encoding="utf-8"))
MAPS = MAPINPUT["maps"]
NATIVE = {m["id"]: m for m in MAPS} if isinstance(MAPS, list) else MAPS

CASES = [
    ("A02", [872.25, 417.8], "Wave[0][3] 兵种461 L36"),
    ("A02", [1129.25, 439.8], "Wave[0][5] 兵种461 L36"),
    ("A06", [8.45, 338.8], "boss[0][5] 兵种466 L41"),
    ("A17", [963.55, 305.9], "Wave[0][0] 兵种472 L57"),
    ("A17", [291.95, 449.1], "boss[0][6] 兵种469 L56"),
    ("A17", [1834.85, 495.5], "boss[0][7] 兵种469 L56"),
    ("A18", [885.0, 208.65], "SpawnPoint[0]"),
    ("A20", [263.5, 185.45], "boss[0][0] 兵种467 L60"),
    ("A22", [263.5, 185.45], "boss[0][3] 兵种465 L60"),
]


def original_fill(point, paths):
    return sum(geometry.point_inside(point, p) for p in paths) % 2


for mid, world, label in CASES:
    ox, oy = NATIVE[mid]["nativeBounds"][:2]
    orig = [world[0] + ox, world[1] + oy]  # world = orig - origin  =>  orig = world + origin
    ev = json.load(open(os.path.join(ROOT, "tools/cf6-map-runtime/generated/%s-original-geometry.json" % mid), encoding="utf-8"))
    paths, notes = geometry.collision_paths(ev)
    wb = ev["geometry"]["walkBounds"]
    in_orig_bounds = wb[0] < orig[0] < wb[2] and wb[1] < orig[1] < wb[3]
    blocked_orig = original_fill(orig, paths) if in_orig_bounds else None
    print("== %s %s" % (mid, label))
    print("  world=", world, " origin=", [ox, oy], " original=", [round(v, 2) for v in orig])
    print("  original walkBounds=", wb, " inOriginalBounds=", in_orig_bounds,
          " blockedByOriginalEvenOdd=", blocked_orig)
    # nearest free point in original space (scan ring)
    if blocked_orig:
        best = None
        for r in range(2, 200, 2):
            for deg in range(0, 360, 15):
                import math
                q = [orig[0] + r * math.cos(math.radians(deg)), orig[1] + r * math.sin(math.radians(deg))]
                if wb[0] < q[0] < wb[2] and wb[1] < q[1] < wb[3] and not original_fill(q, paths):
                    d = r
                    if best is None or d < best[0]:
                        best = (d, q)
            if best:
                break
        if best:
            print("  nearest free original=", [round(v, 2) for v in best[1]],
                  " dist=", best[0], " => world=", [round(best[1][0] - ox, 2), round(best[1][1] - oy, 2)])
        else:
            print("  no free point within 200px ring")
