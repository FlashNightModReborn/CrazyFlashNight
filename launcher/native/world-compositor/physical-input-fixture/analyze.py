"""Static recount of one frozen passive-input run; never executes recorded code.
Usage: python analyze.py CANDIDATE_ROOT RUN_DIRECTORY OUTPUT_JSON
Recorded acceptance is preserved. Cross-channel equality is not OS completeness.
"""
from collections import Counter
from pathlib import Path
import hashlib
import json
import sys


def modifier_key(vk, scan, extended=False):
    if 160 <= vk <= 165:
        return vk
    if vk == 16 and scan in (42, 54):
        return 160 if scan == 42 else 161
    if vk in (17, 18) and scan == (29 if vk == 17 else 56):
        return (162 if vk == 17 else 164) + int(extended)
    return None


def analyze(candidate, run):
    manifest = json.loads((candidate / "candidate.json").read_text(encoding="utf-8-sig"))
    identity = json.loads((run / "identity.json").read_text(encoding="utf-8-sig"))
    summary = json.loads((run / "summary.json").read_text(encoding="utf-8-sig"))
    matches = []
    for entry in manifest["files"]:
        path = (candidate / entry["path"]).resolve()
        if not path.is_relative_to(candidate.resolve()):
            raise ValueError("manifest escaped candidate root")
        matches.append(hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"].lower())
    dll = next(f for f in manifest["files"] if f["path"] == "bin/PhysicalInputProbe.dll")
    if not all(matches) or identity["sha256"].lower() != dll["sha256"].lower():
        raise ValueError("candidate identity mismatch")
    rows = [json.loads(line) for line in (run / "observations.jsonl").read_text(encoding="utf-8-sig").splitlines()]
    raw_mouse, ll_mouse, raw_mod, ll_mod = [], [], [], []
    unresolved = []
    mouse_pairs = [(1, 1, True), (2, 1, False), (4, 2, True), (8, 2, False),
                   (16, 4, True), (32, 4, False), (64, 5, True), (128, 5, False),
                   (256, 6, True), (512, 6, False)]
    held = {}
    changed_foreground_releases = []
    for row in rows:
        d, kind = row["detail"], row["kind"]
        if kind == "raw_mouse":
            raw_mouse.extend((d["time"], key, down) for bit, key, down in mouse_pairs if d["flags"] & bit)
        elif kind == "ll_mouse":
            ll_mouse.append((d["time"], d["key"], d["down"]))
            if d["down"]:
                held[d["key"]] = row
            elif d["key"] in held:
                begin = held.pop(d["key"])
                if begin["detail"]["foreground"] != d["foreground"]:
                    changed_foreground_releases.append({"downSerial": begin["serial"], "upSerial": row["serial"],
                                                       "downForeground": begin["detail"]["foreground"], "upForeground": d["foreground"]})
        elif kind in ("raw_modifier", "ll_modifier"):
            extended = bool(d["flags"] & (2 if kind == "raw_modifier" else 1))
            key = modifier_key(d["key"], d.get("scan", 0), extended)
            if key is None or (kind == "raw_modifier" and d["flags"] & 4):
                unresolved.append(row["serial"])
                continue
            down = not bool(d["flags"] & 1) if kind == "raw_modifier" else d["down"]
            (raw_mod if kind == "raw_modifier" else ll_mod).append((d["time"], key, down))
    snapshots = [r for r in rows if r["kind"] == "snapshot_observation"]
    first_rejected = next((r for r in snapshots if not r["detail"]["accepted"]), None)
    recorded_rejected = sum(not r["detail"]["accepted"] for r in snapshots)
    counts = Counter(r["kind"] for r in rows)
    return {
        "kind": "static_human_sample_recount_not_C1_acceptance",
        "run": str(run), "pid": identity["pid"], "utcStart": identity["utc"],
        "artifactMatches": sum(matches), "artifactCount": len(matches),
        "injectedControl": identity["injectedControl"], "businessInputGranted": identity["businessInputGranted"],
        "recordCount": len(rows), "recordKinds": dict(counts),
        "serialContinuous": [r["serial"] for r in rows] == list(range(1, len(rows) + 1)),
        "localDropped": summary["Dropped"],
        "mouse": {"rawRecords": counts["raw_mouse"], "rawEdges": len(raw_mouse), "llEdges": len(ll_mouse),
                  "sameEdgeMultiset": Counter(raw_mouse) == Counter(ll_mouse),
                  "foregroundChangedReleases": changed_foreground_releases},
        "modifiers": {"rawEdges": len(raw_mod), "llEdges": len(ll_mod),
                      "exactMatchedEdges": sum((Counter(raw_mod) & Counter(ll_mod)).values()),
                      "rawWithoutLl": sum((Counter(raw_mod) - Counter(ll_mod)).values()),
                      "llWithoutRaw": sum((Counter(ll_mod) - Counter(raw_mod)).values()),
                      "rawByKeyAndDirection": [{"key": k, "down": d, "count": n} for (k, d), n in sorted(Counter((k, d) for _, k, d in raw_mod).items())],
                      "normalizationUnresolvedSerials": unresolved},
        "snapshots": {"accepted": sum(r["detail"]["accepted"] for r in snapshots),
                      "recordedRejected": recorded_rejected,
                      "skippedWithoutSnapshot": summary["SnapshotRejected"] - recorded_rejected,
                      "firstRejected": first_rejected,
                      "acceptedAfterFirstRejection": sum(r["detail"]["accepted"] for r in snapshots if first_rejected and r["serial"] > first_rejected["serial"])},
        "limits": ["No attribution of missing hook callbacks to a specific program or to the old game bug.",
                   "Mouse multiset equality does not prove global delivery order or OS-wide completeness.",
                   "Historical HWND values do not identify the application that owned them.",
                   "Recorded rejected snapshots remain rejected; no retrospective runtime pass is manufactured."]
    }


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    result = analyze(Path(sys.argv[1]), Path(sys.argv[2]))
    Path(sys.argv[3]).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("artifactMatches", "recordCount", "serialContinuous", "localDropped", "modifiers")}, ensure_ascii=False))
