from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


PINNED_SWF = "1f2d0126c3c84b7f817bf1f6e9f40db4bfa69a1f57476f6ce8645a25d35b88f7"
PINNED_FFDEC = "c03ad5d22008246b9f2523a70830502ed0d01610f4054912b43ae70f58dddd86"
PINNED_XFL = {
    "shape/Symbol 621": "0b8f0bbd054d599a28673b5f3a037d41996d4b665e34bc36019141c8dd9be299",
    "shape/Symbol 622": "f6de9d9c24a9d714f383dd9c870a556208bb7380225380a3a99da9ba45d9c375",
    "shape/Symbol 623": "05965f8278cc97211e8700bbc100fb6a575c3b486bbcddaad3646e713ea058cb",
}
PINNED_SHAPES = {
    "shape/Symbol 621": (3209, "effect-621.svg", (504, 265), 81316),
    "shape/Symbol 622": (3210, "effect-622.svg", (1277, 392), 198147),
    "shape/Symbol 623": (3211, "wood-dummy-623.svg", (340, 841), 176692),
}
NS = {"x": "http://ns.adobe.com/xfl/2008/"}


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def raster_coverage(path: Path) -> dict:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    return {
        "size": [image.width, image.height],
        "alphaAtLeast128": sum(alpha.histogram()[128:]),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True, help="Read-only source repository root")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    repo = args.repo.resolve()
    root = args.out.resolve() / "launcher" / "web" / "assets" / "gym"
    manifest_path = root / "manifest.json"
    errors = []
    if not manifest_path.is_file():
        print(json.dumps({"ok": False, "errors": ["missing runtime manifest"]}, indent=2))
        return 1
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    motion_path = root / manifest.get("motionUri", "")
    motion = json.loads(motion_path.read_text(encoding="utf-8-sig")) if motion_path.is_file() else {}

    if manifest.get("schema") != "cf7-gym-motion-manifest-v1":
        errors.append("manifest schema mismatch")
    if motion.get("schema") != "cf7-wood-dummy-motion-v1":
        errors.append("motion schema mismatch")
    sources = manifest.get("sourceDigests", {})
    for key, entry in sources.items():
        if key == "equipmentXflShapes":
            entries = entry.items()
        else:
            entries = [(key, entry)]
        for subkey, source in entries:
            path = (repo / source.get("repoRelativePath", "")).resolve()
            if not path.is_file():
                errors.append(f"missing source: {key}/{subkey}")
            elif sha(path) != source.get("sha256"):
                errors.append(f"source digest mismatch: {key}/{subkey}")

    if sources.get("compiledSwf", {}).get("sha256") != PINNED_SWF:
        errors.append("manifest is not pinned to the audited things0.swf")
    if sources.get("ffdecCli", {}).get("sha256") != PINNED_FFDEC:
        errors.append("manifest is not pinned to the audited FFDec CLI")
    for symbol, expected in PINNED_XFL.items():
        got = sources.get("equipmentXflShapes", {}).get(symbol, {}).get("sha256")
        if got != expected:
            errors.append("manifest XFL shape mapping differs from audited pin: " + symbol)

    if manifest.get("frameRate") != 30 or motion.get("source", {}).get("frameRate") != 30:
        errors.append("expected project frameRate 30")
    if manifest.get("loop", {}).get("frameCount") != 127 or motion.get("source", {}).get("frameCount") != 127:
        errors.append("expected 127-frame loop")
    if manifest.get("loop", {}).get("timelineStart") != 155 or manifest.get("loop", {}).get("timelineEndExclusive") != 282:
        errors.append("unexpected loop frame range")
    if (
        manifest.get("loop", {}).get("labelSourceLine") != 19
        or manifest.get("loop", {}).get("durationSourceLine") != 49
        or manifest.get("loop", {}).get("loopbackSourceLine") != 54
    ):
        errors.append("XFL source line evidence mismatch")
    if manifest.get("layerCount") != len(motion.get("layers", [])):
        errors.append("layer count mismatch")

    key_count = 0
    instance_count = 0
    for layer in motion.get("layers", []):
        last = -1
        for key in layer.get("keyframes", []):
            key_count += 1
            lo, hi = key.get("loopStart", -1), key.get("loopEndExclusive", -1)
            if not (0 <= lo < hi <= 127):
                errors.append("exposure outside loop: " + layer.get("name", "?"))
            if lo < last:
                errors.append("overlapping exposures: " + layer.get("name", "?"))
            last = hi
            for element in key.get("elements", []):
                instance_count += 1
                values = element.get("matrix", {}).get("values", [])
                if len(values) != 6 or not all(math.isfinite(float(value)) for value in values):
                    errors.append("invalid matrix: " + layer.get("name", "?"))
    if key_count != manifest.get("keyframeExposureCount"):
        errors.append("exposure count mismatch")
    if instance_count != manifest.get("directInstanceKeyCount"):
        errors.append("direct element count mismatch")

    expected_stations = {
        "dummy": ("木人桩", "wood-dummy-loop.json", 155, 282, 127),
        "dumbbell": ("哑铃", "dumbbell-loop.json", 1, 78, 77),
        "squat": ("深蹲", "squat-loop.json", 79, 154, 75),
    }
    if set(manifest.get("stations", {})) != set(expected_stations):
        errors.append("station list mismatch")
    for station_id, (label, uri, start, end, frame_count) in expected_stations.items():
        station = manifest.get("stations", {}).get(station_id, {})
        station_path = root / uri
        if station.get("label") != label or station.get("motionUri") != uri:
            errors.append("station identity mismatch: " + station_id)
        if (station.get("timelineStart") != start or station.get("timelineEndExclusive") != end \
                or station.get("frameCount") != frame_count or station.get("frameRate") != 30 \
                or station.get("loopbackFrameIndex") != end):
            errors.append("station frame contract mismatch: " + station_id)
        if not station_path.is_file():
            errors.append("missing station motion: " + station_id)
            continue
        if sha(station_path) != manifest.get("outputs", {}).get(uri):
            errors.append("station motion hash mismatch: " + station_id)
        data = json.loads(station_path.read_text(encoding="utf-8-sig"))
        expected_schema = "cf7-wood-dummy-motion-v1" if station_id == "dummy" else "cf7-gym-station-motion-v1"
        if data.get("schema") != expected_schema or (station_id != "dummy" and data.get("stationId") != station_id):
            errors.append("station schema mismatch: " + station_id)
        source = data.get("source", {})
        if source.get("timelineIndices") != [start, end - 1] or source.get("frameCount") != frame_count \
                or source.get("frameRate") != 30 or source.get("sha256") != sources.get("timeline", {}).get("sha256"):
            errors.append("station source mismatch: " + station_id)
        if data.get("vectors") != manifest.get("vectors") \
                or data.get("componentBindings") != manifest.get("componentBindings"):
            errors.append("station shared assets mismatch: " + station_id)
        station_keys = 0
        station_elements = 0
        for layer in data.get("layers", []):
            for key in layer.get("keyframes", []):
                station_keys += 1
                lo, hi = key.get("loopStart", -1), key.get("loopEndExclusive", -1)
                if not (0 <= lo < hi <= frame_count):
                    errors.append("station exposure outside loop: " + station_id)
                for element in key.get("elements", []):
                    station_elements += 1
                    name = element.get("libraryItemName", "")
                    if name not in data.get("vectors", {}) and not (
                            name.startswith("主角肢体素材/")
                            and name.removeprefix("主角肢体素材/") in data.get("componentBindings", {})):
                        errors.append("station unresolved symbol: " + station_id + "/" + name)
        if station.get("layerCount") != len(data.get("layers", [])) \
                or station.get("keyframeExposureCount") != station_keys \
                or station.get("directInstanceKeyCount") != station_elements:
            errors.append("station exposure count mismatch: " + station_id)

    for symbol, vector in manifest.get("vectors", {}).items():
        packaged = root / vector.get("uri", "")
        source = (repo / vector.get("repoRelativePath", "")).resolve()
        if not packaged.is_file() or sha(packaged) != vector.get("sha256"):
            errors.append("vector asset hash mismatch: " + symbol)
        if not source.is_file() or sha(source) != vector.get("sourceSha256"):
            errors.append("vector source hash mismatch: " + symbol)
        if symbol in PINNED_SHAPES:
            cid, _, expected_size, expected_alpha = PINNED_SHAPES[symbol]
            if vector.get("backend") != "FFDec compiled SWF shape export" or vector.get("characterId") != cid:
                errors.append("FFDec character mapping mismatch: " + symbol)
            if vector.get("compiledSwf", {}).get("sha256") != PINNED_SWF:
                errors.append("compiled SWF pin missing from vector: " + symbol)
            if vector.get("ffdecCli", {}).get("sha256") != PINNED_FFDEC:
                errors.append("FFDec CLI pin missing from vector: " + symbol)
            if vector.get("referencePngCoverage") != {"size": list(expected_size), "alphaAtLeast128": expected_alpha}:
                errors.append("FFDec alpha baseline missing or changed: " + symbol)
            if packaged.is_file():
                try:
                    xml = ET.parse(packaged).getroot()
                    fills = {node.get("fill", "").upper() for node in xml.iter() if node.tag.rsplit("}", 1)[-1] == "path"}
                    if not set(vector.get("fillColors", [])).issubset(fills):
                        errors.append("FFDec SVG fill palette mismatch: " + symbol)
                except ET.ParseError:
                    errors.append("invalid vector SVG: " + symbol)

    # Regenerate both vector and PNG references from the pinned SWF. This proves
    # the package did not silently fall back to the defective XFL edge grouping.
    cli = repo / sources.get("ffdecCli", {}).get("repoRelativePath", "")
    swf = repo / sources.get("compiledSwf", {}).get("repoRelativePath", "")
    if cli.is_file() and swf.is_file():
        with tempfile.TemporaryDirectory(prefix=".verify-gym-", dir=str(root)) as temporary:
            temp = Path(temporary)
            svg_dir, png_dir = temp / "svg", temp / "png"
            svg_dir.mkdir()
            png_dir.mkdir()
            commands = [
                [str(cli), "-selectid", "3209-3211", "-format", "shape:svg", "-zoom", "4", "-export", "shape", str(svg_dir), str(swf)],
                [str(cli), "-selectid", "3209-3211", "-format", "shape:png", "-zoom", "4", "-export", "shape", str(png_dir), str(swf)],
            ]
            for command in commands:
                try:
                    subprocess.run(command, check=True, capture_output=True, text=True, encoding="utf-8")
                except (subprocess.CalledProcessError, OSError) as error:
                    errors.append("FFDec source-reference re-export failed: " + str(error))
                    break
            for symbol, (cid, svg_name, size, alpha) in PINNED_SHAPES.items():
                packaged = root / manifest.get("vectors", {}).get(symbol, {}).get("uri", "")
                fresh_svg, fresh_png = svg_dir / f"{cid}.svg", png_dir / f"{cid}.png"
                if not fresh_svg.is_file() or not fresh_png.is_file():
                    errors.append("FFDec omitted pinned reference: " + symbol)
                    continue
                if packaged.is_file() and sha(packaged) != sha(fresh_svg):
                    errors.append("packaged SVG is not the pinned FFDec export: " + symbol)
                coverage = raster_coverage(fresh_png)
                if coverage != {"size": list(size), "alphaAtLeast128": alpha}:
                    errors.append("fresh FFDec PNG alpha gate failed: " + symbol)

    package_json = [root / "manifest.json"] + [root / station[1] for station in expected_stations.values()]
    absolute_path = re.compile(r"(?:[A-Za-z]:[\\/]|\\\\Users\\)")
    for path in package_json:
        if path.is_file() and absolute_path.search(path.read_text(encoding="utf-8-sig")):
            errors.append("portable package JSON contains a workstation absolute path: " + path.name)

    expected = set(manifest.get("outputs", {})) | {"manifest.json"}
    actual = {path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file()}
    if actual != expected:
        errors.append("asset file set mismatch")

    result = {
        "ok": not errors,
        "errors": errors,
        "motionBytes": motion_path.stat().st_size if motion_path.is_file() else 0,
        "vectorBytes": sum((root / vector["uri"]).stat().st_size for vector in manifest.get("vectors", {}).values() if (root / vector["uri"]).is_file()),
        "frameRate": manifest.get("frameRate"),
        "frameCount": manifest.get("loop", {}).get("frameCount"),
        "keyframeExposures": key_count,
        "directInstances": instance_count,
        "assetFiles": len(actual),
        "assetBytes": sum(path.stat().st_size for path in root.rglob("*") if path.is_file()),
        "stations": {station_id: {
            "frameCount": manifest.get("stations", {}).get(station_id, {}).get("frameCount"),
            "keyframeExposures": manifest.get("stations", {}).get(station_id, {}).get("keyframeExposureCount"),
            "directInstances": manifest.get("stations", {}).get(station_id, {}).get("directInstanceKeyCount"),
        } for station_id in expected_stations},
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
