"""Refresh the native consumers of one published Flash library. A SWF-only import always exports changed inputs."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LIBRARIES = runpy.run_path(str(HERE / "source_recipes.py"))["SOURCE_LIBRARIES"]
OUTPUT = ROOT / "data/combat_visuals"
SCRATCH = ROOT / "tmp/combat-visual-publication"
EFFECTS = (HERE / "build.py", OUTPUT / "effects.v1.json", OUTPUT / "effects-atlas.png")
BULLETS = (ROOT / "tools/combat-bullet-visuals/build.py", OUTPUT / "bullet_styles.v1.json", OUTPUT / "bullets-atlas.png")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def render_inputs(raw):
    """Hash all published tags and settings except AVM1 frame actions and the compiler timestamp.
    Both rasterizers render finite frames without running actions. The reviewed XFL recipe and sound
    adapter are still checked independently. Any unknown tag contributes all its bytes.
    """
    if raw[:3] not in (b"CWS", b"FWS"):
        raise ValueError("unknown SWF compression")
    body = zlib.decompress(raw[8:]) if raw[:3] == b"CWS" else raw[8:]
    if len(body) + 8 != int.from_bytes(raw[4:8], "little"):
        raise ValueError("incomplete published SWF")
    start = (5 + 4 * (body[0] >> 3) + 7) // 8 + 4
    digest = hashlib.sha256(raw[3:4] + body[:start])

    def tags(data):
        pos = 0
        while pos < len(data):
            header, = struct.unpack_from("<H", data, pos)
            code, size = header >> 6, header & 63
            pos += 2
            if size == 63:
                size, = struct.unpack_from("<I", data, pos)
                pos += 4
            if pos + size > len(data):
                raise ValueError("truncated SWF tag")
            payload = data[pos:pos + size]
            pos += size
            if code in (12, 59):
                continue
            if code == 39:
                digest.update(b"sprite[" + payload[:4])
                tags(payload[4:])
                digest.update(b"]")
            else:
                if code == 41 and len(payload) == 26:
                    payload = payload[:-8]
                digest.update(struct.pack("<HI", code, len(payload)))
                digest.update(payload)
            if code == 0:
                if pos != len(data):
                    digest.update(data[pos:])
                return
        raise ValueError("unterminated tag stream")

    tags(body[start:])
    return digest.hexdigest()


def write_json(path, value):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        staged = Path(stream.name)
        stream.write((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    try:
        staged.replace(path)
    finally:
        staged.unlink(missing_ok=True)


def run(script, check=False):
    return subprocess.run([sys.executable, "-B", "-X", "utf8", str(script)] + (["--check"] if check else []),
                          cwd=ROOT).returncode == 0


def published_hash(catalog, relative):
    if "sourceSwfSha256" in catalog:
        return catalog["sourceSwfSha256"]
    return next(row["sha256"] for row in catalog["sources"] if row["path"] == relative)


def replace_source(catalog, relative, new_hash):
    if "sourceSwfSha256" in catalog:
        catalog["sourceSwfSha256"] = new_hash
    else:
        next(row for row in catalog["sources"] if row["path"] == relative)["sha256"] = new_hash


def consumed_frames_match(library, catalog, atlas, bullets=False):
    """Compare only this SWF's finite native frames against their verified packed pixels."""
    from PIL import Image

    helper = runpy.run_path(str(HERE / "build.py"))
    swf = ROOT / library["swf"]
    names = helper["exports"](swf)
    expected = {}
    borders = {}
    plan = []
    if bullets:
        exporter = ROOT / "tools/combat-bullet-visuals/BulletSpriteExporter.java"
        zoom = catalog["atlas"]["scale"]
        for index, style in enumerate(catalog["styles"]):
            visual = style["visual"]
            if visual["kind"] != "sprite":
                continue
            linkage = style["ordinaryLinkage"] or style["gunChainUnitLinkage"]
            plan.append(f"{index}\t{names[linkage]}\t0")
            expected[index, 0] = visual["atlasRectPx"], visual["offsetPx"]
            borders[index] = 2
    else:
        exporter = HERE / "CombatSpriteExporter.java"
        zoom = catalog["pixelsPerUnit"]
        for recipe, style in zip(catalog["recipe"], catalog["styles"]):
            if recipe["sourceKey"] != library["key"]:
                continue
            index = recipe["index"]
            borders[index] = int(recipe["renderMode"] in ("padded", "nested-scaled"))
            frames = sorted({frame for variant in recipe["variants"] for frame in variant})
            plan.append("\t".join([str(index), str(names[recipe["renderLinkage"]]),
                                  ",".join(map(str, frames)), recipe["renderChild"] or "-", recipe["renderMode"]]))
            for frame in style["frames"]:
                expected[index, frame["sourceFrame"]] = frame["rect"], frame["offset"]
    if not expected:
        return False
    classpath = os.pathsep.join(map(str, (ROOT / "tools/ffdec/lib/*", ROOT / "tools/ffdec/ffdec.jar")))
    with tempfile.TemporaryDirectory(dir=SCRATCH) as name:
        temp = Path(name)
        (temp / "plan.tsv").write_text("\n".join(plan), encoding="utf-8")
        subprocess.run([str(helper["java_tool"]("javac")), "-encoding", "UTF-8", "-cp", classpath,
                        "-d", str(temp), str(exporter)], check=True, timeout=120)
        raster = temp / "raster"
        subprocess.run([str(helper["java_tool"]("java")), "-Xmx2g", "-cp", str(temp) + os.pathsep + classpath,
                        exporter.stem, str(swf), str(temp / "plan.tsv"), str(raster), str(zoom)], check=True, timeout=240)
        with Image.open(atlas) as packed:
            for line in (raster / "frames.tsv").read_text(encoding="utf-8").splitlines():
                index, frame, xmin, ymin, _, _, image_file = line.split("\t")
                key = int(index), int(frame)
                if key not in expected:
                    return False
                (x, y, w, h), offset = expected.pop(key)
                with Image.open(image_file) as source:
                    image = source.convert("RGBA")
                    box = image.getbbox()
                    border = borders[key[0]]
                    if box is None and bullets:
                        return False
                    if box is not None and (box[0] < border or box[1] < border
                            or box[2] > image.width - border or box[3] > image.height - border):
                        return False
                    if box is None:
                        box = (0, 0, 1, 1)
                        image = Image.new("RGBA", (1, 1))
                    else:
                        image = image.crop(box)
                    registration = [int(xmin) / 20 + box[0] / zoom, int(ymin) / 20 + box[1] / zoom]
                    if bullets:
                        registration = [round(v, 6) for v in registration]
                    if registration != offset or image.size != (w, h):
                        return False
                    if image.tobytes() != packed.crop((x, y, x + w, y + h)).convert("RGBA").tobytes():
                        return False
    return not expected

@contextmanager
def recover_outputs(consumers):
    sound_dir = ROOT / "sounds/export/特效"
    paths = {p for _, catalog, atlas in consumers for p in (catalog, atlas)}
    paths.update(sound_dir.glob("cfnfx-*.wav"))
    with tempfile.TemporaryDirectory(dir=SCRATCH) as name:
        backups = {}
        for i, path in enumerate(paths):
            if path.is_file():
                backups[path] = Path(name) / str(i)
                shutil.copy2(path, backups[path])
        try:
            yield
        except BaseException:
            for path in paths | set(sound_dir.glob("cfnfx-*.wav")):
                if path in backups:
                    shutil.copy2(backups[path], path)
                elif path.is_file():
                    path.unlink()
            raise


@contextmanager
def publication_lock():
    # Both catalogs can share the stock library and WAV set. One publisher owns their outputs at a time.
    SCRATCH.mkdir(parents=True, exist_ok=True)
    with (SCRATCH / "catalogs.lock").open("a+b") as lock:
        lock.seek(0)
        if os.name == "nt":
            import msvcrt
            try:
                msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as error:
                raise RuntimeError("Another combat art publication is in progress") from error
        else:
            import fcntl
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
        # Closing the handle releases this process's lock, including on errors.


def refresh(path, xfl):
    path = path.resolve()
    relative = path.relative_to(ROOT).as_posix()
    library = next((row for row in LIBRARIES if row["swf"] == relative), None)
    if library is None:
        return
    consumers = [EFFECTS, BULLETS] if library["key"] == "stock" else [EFFECTS]
    with publication_lock():
        refresh_consumers(library, path, relative, consumers, xfl)


def refresh_consumers(library, path, relative, consumers, xfl):
    folder = (ROOT / library["libraryRoot"]).parent
    settings = folder / "PublishSettings.xml"
    known = xfl is not None and xfl.resolve() == folder / (folder.name + ".xfl") and settings.is_file()
    proof_path = SCRATCH / (library["key"] + ".json")
    raw = path.read_bytes()
    current = {"sha256": sha(raw)}
    if known:
        try:
            current.update(render=render_inputs(raw), settings=sha(settings.read_bytes()))
            if library["key"] == "stock":
                # The exported WAV reader validates its timing and registration. Keep a separate
                # fingerprint of the actual compressed sample bytes before reusing those WAVs.
                sounds, _ = runpy.run_path(str(HERE / "build.py"))["swf_audio"](path)
                audio = hashlib.sha256()
                for sound_id, payload in sorted(sounds.items()):
                    audio.update(struct.pack("<HI", sound_id, len(payload)))
                    audio.update(payload)
                current["audio"] = audio.hexdigest()
        except (ValueError, struct.error, IndexError, zlib.error):
            known = False
    previous = {}
    if proof_path.exists():
        try:
            previous = json.loads(proof_path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            pass
    with recover_outputs(consumers):
        for script, manifest, atlas in consumers:
            try:
                catalog = json.loads(manifest.read_text(encoding="utf-8"))
                original = published_hash(catalog, relative)
            except (OSError, ValueError, KeyError, StopIteration):
                original = None
            if original == current["sha256"] and run(script, check=True):
                print("verified", manifest.name)
                continue
            if (known and original and previous.get("sha256") == original
                    and previous.get("settings") == current["settings"]):
                saved = manifest.read_bytes()
                replace_source(catalog, relative, current["sha256"])
                write_json(manifest, catalog)
                # A republish can renumber unrelated character IDs. Compare the actual consumed
                # frames on that path, including registration, before retaining the atlas.
                if run(script, check=True):
                    if previous.get("render") == current["render"]:
                        print("reused verified atlas and sounds (unchanged published tags)", manifest.name)
                        continue
                    audio_matches = (library["key"] != "stock" or script == BULLETS[0]
                                     or previous.get("audio") == current["audio"])
                    if audio_matches and consumed_frames_match(library, catalog, atlas, script == BULLETS[0]):
                        print("reused verified atlas and sounds (matched published consumer frames)", manifest.name)
                        continue
                manifest.write_bytes(saved)
            if not run(script) or not run(script, check=True):
                raise ValueError("derived output failed verification: " + manifest.name)
            print("regenerated", manifest.name)
        if sha(path.read_bytes()) != current["sha256"] or (known and sha(settings.read_bytes()) != current["settings"]):
            raise ValueError("publication changed during export")
        if known:
            write_json(proof_path, current)
        else:
            proof_path.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swf", required=True, type=Path)
    parser.add_argument("--published-xfl", type=Path, help="actual project just published by CS6")
    options = parser.parse_args()
    refresh(options.swf, options.published_xfl)
