"""Real-asset checks for reusable portrait effects, alpha and provenance."""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageChops
from dialogue_portrait_postprocess import recipes, apply, provenance

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "launcher/web/assets/dialogue-portraits"


def main():
    manifest = json.loads((ASSETS / "manifest.json").read_text(encoding="utf-8"))
    key = "前治安官（无线电）"
    recipe = recipes(ROOT)[key]
    original = manifest["entries"][recipe["source"]]["expressions"]["普通"]
    source_path = ASSETS / original["uri"]
    original_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    image = Image.open(source_path).convert("RGBA")
    first = apply(image, recipe["settings"], manifest["zoom"])
    second = apply(image, recipe["settings"], manifest["zoom"])
    assert first.tobytes() == second.tobytes(), "effects must be deterministic"
    assert first.size == image.size, "effects cannot refit the original portrait"
    assert first.getpixel((0, 0))[3] == 0 and first.getpixel((160, 160))[3] == 0, "no rectangular background"
    bounds = first.getchannel("A").getbbox()
    original_bounds = image.getchannel("A").getbbox()
    assert all(abs(a-b) <= 16 for a,b in zip(bounds, original_bounds)), "glow cannot change portrait framing"
    assert ImageChops.difference(first, image).getbbox(), "radio variant must visibly differ"
    changed = dict(recipe["settings"], scanDarken=1, glowOpacity=0)
    assert first.tobytes() != apply(image, changed, manifest["zoom"]).tobytes(), "profile must control the result"
    assert hashlib.sha256(source_path.read_bytes()).hexdigest() == original_hash, "effects cannot rewrite original art"
    entry = manifest["entries"][key]
    source = ROOT / entry["sourcePath"]
    assert entry["postprocess"] == provenance(recipe, source, ROOT), "derived portrait provenance is stale"
    for dependency in manifest["postprocessInputs"]:
        path = (ROOT / dependency["path"]).resolve()
        assert path.is_relative_to(ROOT.resolve())
        assert hashlib.sha256(path.read_bytes()).hexdigest() == dependency["sha256"], "postprocess input is stale"
    asset = entry["expressions"]["普通"]
    assert hashlib.sha256((ASSETS / asset["uri"]).read_bytes()).hexdigest() == asset["sha256"]
    assert (asset["width"], asset["height"]) == image.size, "Host and Web must retain the same stage window"
    # All previous portraits (including original Boy/Blue radio art) remain intact.
    baseline = ROOT / "tmp/newcomer-rescue/portrait-baseline/manifest.json"
    if baseline.exists():
        before = json.loads(baseline.read_text(encoding="utf-8"))
        for name, old in before["entries"].items():
            if name == key:
                continue
            assert manifest["entries"][name] == old, "unrelated portrait entry changed: " + name
            for old_asset in old["expressions"].values():
                assert hashlib.sha256((ASSETS / old_asset["uri"]).read_bytes()).hexdigest() == old_asset["sha256"]
    print("Portrait postprocess verified: deterministic effects, original geometry/alpha, provenance and retained portraits")


if __name__ == "__main__":
    main()
