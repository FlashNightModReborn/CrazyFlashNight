"""Verify the runtime together with the loose inputs loaded by a game session."""

from hashlib import sha256
import json
from pathlib import Path

from evidence import digest, identities_match, link, read_json, same_hash, same_path


def combined_material(manifest):
    assets = {item["path"]: item["sha256"].lower() for item in manifest["assets"]}
    identity = {"runtimePayloadClosure": manifest["payloadClosure"].lower(), "looseInputs": sorted(assets.items())}
    return sha256(json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def read_material_session(file, project, expected, startup):
    manifest = read_json(file)
    combined = combined_material(manifest)
    result = {"status": "BLOCKED", "raw": link(file), "combinedMaterialSha256": combined, "stages": {}}
    if (not identities_match(manifest, expected) or not same_path(manifest["root"], str(project)) or
            not same_path(manifest["candidateRoot"], expected["installRoot"]) or
            not same_hash(combined, manifest.get("combinedMaterialSha256")) or startup.get("status") != "PASS"):
        return result
    assets = manifest["assets"]
    if len({item["path"] for item in assets}) != len(assets):
        return result
    matched = {}
    project = Path(project).resolve()
    for item in assets:
        asset = (project / item["path"]).resolve()
        if not asset.is_relative_to(project):
            return result
        matched[item["path"]] = same_hash(digest(asset), item["sha256"])
    result.update(looseAssets=matched, runtimeFileCount=len(manifest["runtime"]))
    process = startup["process"]
    ready = startup["ready"]
    base = Path(startup["raw"]["path"]).parent
    for name in ("before", "ready", "exit"):
        stage = base / ("material-" + name + ".json")
        if not stage.exists():
            result["stages"][name] = {"status": "NOT_RUN"}
            continue
        data = read_json(stage)
        matches = (same_path(data["manifest"], str(file)) and same_hash(data["combinedMaterialSha256"], combined) and
                   same_hash(data["payloadClosure"], manifest["payloadClosure"]) and data["checkedLooseInputs"] == len(assets))
        if name != "before":
            matches = matches and data.get("pid") == process["pid"] and data.get("attempt") == ready["attemptId"]
        result["stages"][name] = {"status": "PASS" if matches else "BLOCKED", "raw": link(stage), "utc": data.get("utc")}
    if all(matched.values()) and all(row["status"] == "PASS" for row in result["stages"].values()):
        result["status"] = "PASS"
    return result
