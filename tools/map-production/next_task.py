#!/usr/bin/env python3
"""Print the next claimable map-production task without touching git."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOARD = ROOT / "map-production"
TASKS = BOARD / "tasks.json"
CLAIMS = BOARD / "claims"
RESULTS = BOARD / "results"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="list all claimable tasks")
    ap.add_argument("--json", action="store_true", help="print JSON")
    args = ap.parse_args()

    data = json.loads(TASKS.read_text(encoding="utf-8"))
    claimed = {p.stem for p in CLAIMS.glob("*.json")}
    done = {p.stem for p in RESULTS.glob("*.json")}
    tasks = [
        t for t in data["tasks"]
        if t.get("claimable") and t["id"] not in claimed and t["id"] not in done
    ]
    tasks.sort(key=lambda t: (t["priority"], t["wave"], t["id"]))
    if args.all:
        out = tasks
    else:
        out = tasks[:1]
    if args.json:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        if not out:
            print("no claimable task")
        for t in out:
            print(f"{t['id']}\t{t['stage']}\t{t['mapCount']}图\t{t['chain']}\t{t['packageDir']}")
    return 0 if out else 1


if __name__ == "__main__":
    sys.exit(main())
