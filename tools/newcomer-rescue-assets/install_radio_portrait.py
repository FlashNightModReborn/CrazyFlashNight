"""Merge the bounded official portrait bake; preserve every existing portrait.

Run bake-dialogue-portraits.py --keys 前治安官（无线电） --external-only --zoom 2 --image-format webp
with a separate --output-dir first. This merger checks all retained file hashes.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
KEY = "前治安官（无线电）"
PRODUCTION = ROOT / "launcher/web/assets/dialogue-portraits"
CANDIDATE = ROOT / "tmp/newcomer-rescue/radio-bake-v2"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def install():
    manifest = json.loads((PRODUCTION / "manifest.json").read_text(encoding="utf-8"))
    candidate = json.loads((CANDIDATE / "manifest.json").read_text(encoding="utf-8"))
    if set(candidate["entries"]) != {KEY}:
        raise SystemExit("The candidate must contain only the new radio portrait")
    for entry in manifest["entries"].values():
        for image in entry["expressions"].values():
            if digest(PRODUCTION / image["uri"]) != image["sha256"]:
                raise SystemExit("Retained portrait is missing or changed: " + image["uri"])
    new = KEY not in manifest["entries"]
    entry = candidate["entries"][KEY]
    unchanged = not new and manifest["entries"][KEY] == entry
    for image in entry["expressions"].values():
        source = CANDIDATE / image["uri"]
        if digest(source) != image["sha256"]:
            raise SystemExit("Radio candidate hash mismatch")
        target = PRODUCTION / image["uri"]
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.is_file() or digest(target) != image["sha256"]:
            shutil.copy2(source, target)
            unchanged = False
    inputs = {i["path"]: i for i in manifest.get("generatorInputs", [])}
    inputs.update({i["path"]: i for i in candidate.get("generatorInputs", [])})
    generator_inputs = list(inputs.values())
    if manifest.get("generatorInputs") != generator_inputs:
        unchanged = False
    if manifest.get("postprocessInputs") != candidate.get("postprocessInputs"):
        unchanged = False
    if unchanged:
        print("Sheriff radio portrait is current; all retained portrait hashes verified")
        return
    manifest["entries"][KEY] = entry
    # The entry is bounded, but its shared recipe/generator inputs still travel
    # with the full manifest. Preserve existing inputs for unrelated portraits.
    manifest["generatorInputs"] = generator_inputs
    manifest["postprocessInputs"] = candidate["postprocessInputs"]
    spec = importlib.util.spec_from_file_location("portrait_baker", ROOT / "tools/bake-dialogue-portraits.py")
    sys.path.insert(0, str(ROOT / "tools"))
    baker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(baker)
    baker.rebuild_aliases(manifest)
    manifest["generatedAt"] = datetime.now(timezone.utc).isoformat()
    report = json.loads((PRODUCTION / "report.json").read_text(encoding="utf-8"))
    if new:
        report["externalEntries"] += 1
        report["externalExpressions"] += len(entry["expressions"])
    uris = {image["uri"] for e in manifest["entries"].values() for image in e["expressions"].values()}
    closure = report["assetClosure"]
    closure.update(referencedAssets=len(uris), onDiskAssets=len(uris),
                   referencedPngs=sum(u.endswith(".png") for u in uris),
                   onDiskPngs=sum(u.endswith(".png") for u in uris),
                   totalBytes=sum((PRODUCTION / u).stat().st_size for u in uris))
    # Referenced subject first, manifest last, so consumers never see a missing new file.
    (PRODUCTION / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (PRODUCTION / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Installed sheriff radio portrait; all retained portrait hashes verified")


if __name__ == "__main__":
    install()
