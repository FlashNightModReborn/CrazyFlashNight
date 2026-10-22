#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""r14 self-test for the turret native-XFL chain (no CS6, no SWF writes).

Covers what CAN be verified without the root-owned CS6 session:
  - decode: every closure shape consumes bytes exactly; live fills are
    502/927/1588; the 0xFFFF dead fill is never edge-referenced; 1536 is a
    parser phantom (never produced by correct decode);
  - symbol XML invariants: linkage id, marker instance name, 18-frame layout
    (11+1+6), frame-12 sound with envelope, ColorMatrix script values;
  - assemble+check against a SIMULATED post-import tree (media block +
    library media byte copies), proving the finalize path passes once CS6
    did its part, and FAILS when a media item is missing;
  - r15: semantic bad cases on the actual saved symbol XML -- sound envelope
    value drift, ColorMatrixFilter script removal, sound keyframe index
    drift -- each must make --check FAIL closed naming the fact.

Run: python tools/cf6-tutorial-turrets/test-turret-xfl.py
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "build_turret_xfl", os.path.join(HERE, "build-turret-xfl.py"))
bx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bx)

passed = 0
failed = 0


def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("[FAIL]", msg)


def main():
    subprocess.run([sys.executable, "-X", "utf8", "-B", os.path.join(HERE, "build-turret-xfl.py"),
                    "--extract"], check=True, capture_output=True)
    geom_path = os.path.join(HERE, "generated", "geometry-r14.json")
    geom = json.load(io.open(geom_path, "r", encoding="utf-8"))

    # --- decode facts -----------------------------------------------------
    s503 = geom["shapes"]["503"]
    fills = [f for arr in s503["fillArrays"] for f in arr]
    dead = [f for f in fills if f.get("bitmapId") == 65535]
    live = [f for f in fills if f.get("bitmapId") == 502]
    check(len(dead) == 1 and len(live) == 1,
          "503 has one dead 0xFFFF fill and one live bitmap-502 fill")
    used = set()
    for sp in s503["subpaths"]:
        for side in ("fill0", "fill1"):
            if sp[side]:
                used.add((sp["gen"], sp[side]))
    check((0, 1) not in used and (0, 2) in used,
          "503 edges never select the dead fill, always the live one")
    for cid in ("503", "504", "505"):
        check(len(geom["shapes"][cid]["subpaths"]) == 1
              and len(geom["shapes"][cid]["subpaths"][0]["edges"]) == 5,
              "flash frame %s is a single closed quad" % cid)
    body = geom["shapes"]["1589"]
    body_ids = sorted({f.get("bitmapId") for arr in body["fillArrays"]
                       for f in arr if "bitmapId" in f})
    check(body_ids == [927, 1588],
          "1589 body live fills are bitmaps 927 and 1588 only (got %s)" % body_ids)
    check(len(body["subpaths"]) == 5, "1589 subpath count preserved (incl. 2 degenerate)")
    real = [sp for sp in body["subpaths"] if len(sp["edges"]) >= 2]
    check(len(real) == 3, "1589 has 3 real subpaths (2 rects + 1 curved)")
    check(sum(len(sp["edges"]) for sp in real) == 5 + 5 + 26,
          "1589 edge totals match byte-exact decode")
    curved = [sp for sp in real if any(e[0] == "Q" for e in sp["edges"])][0]
    # Independent FFDec SVG baseline from original sprite1591: reversed
    # segment ends at (82.35,-23.1),(82.35,-22.25),(82.5,-21.35) pixels.
    # Pin absolute twips, rather than reproducing the decoder's arithmetic.
    check(curved["edges"][0] == ["M", 1650, -427]
          and curved["edges"][1] == ["Q", 1647, -445, 1647, -462],
          "original head curve retains the nonzero origin and control point")

    # --- symbol XML invariants --------------------------------------------
    src = bx.build_symbol_sources(geom)
    check(sorted(src) == ["00001-机身.xml", "00002-枪口标记.xml",
                          "00003-枪口焰.xml", "00004-CF6教学炮塔-A01自动炮.xml"],
          "symbol source set exact")
    # CS6 resolves these generated library items from the Include filename.
    # A different DOMSymbolItem name produced duplicate placed instances in
    # real published SWFs despite the generic XML-reference audit passing.
    check(all(ET.fromstring(text).get("name") == bx.LIB_PREFIX + "/" + filename[:-4]
              for filename, text in src.items()),
          "library symbol names agree with exact Include filenames")
    turret = src["00004-CF6教学炮塔-A01自动炮.xml"]
    check('linkageIdentifier="CF6教学炮塔-A01自动炮"' in turret
          and 'linkageExportForAS="true"' in turret, "linkage exported")
    check('name="枪口位置2"' in turret, "muzzle marker instance name preserved")
    check('tx="105.25" ty="-12.55"' in turret, "marker local offset native")
    check('tx="112.45" ty="-70.5"' in turret, "flash local offset native")
    check('tx="20.55" ty="-49.45"' in turret, "body placement native")
    check('index="0" duration="18"' in turret, "18-frame cycle")
    check('index="11" duration="1"' in turret, "frame-12 (index 11) fire keyframe")
    check('index="12" duration="6"' in turret, "frame-13 removal keyframe")
    check('soundName="CF6Turret/fire-sound-1169.import.mp3"' in turret, "frame-12 event sound uses unwrapped MP3 payload")
    check("stop();" in turret, "turret timeline stops before service takes ownership")
    check('level0="11022" level1="9533"' in turret, "original sound envelope values")
    for v in ("0.48174965381622314", "-45.89500045776367", "0.28316378593444824"):
        check(v in turret, "ColorMatrix value %s in frame-1 script" % v)
    check("ColorMatrixFilter" in turret, "filter applied via AS2 ColorMatrixFilter")
    check("65535" not in src["00003-枪口焰.xml"], "dead 0xFFFF fill dropped from flash symbol")
    check('bitmapPath="CF6Turret/muzzle-flash-502.png"' in src["00003-枪口焰.xml"],
          "flash frames use live bitmap 502")
    check('bitmapPath="CF6Turret/turret-body-1588.png"' in src["00001-机身.xml"]
          and 'bitmapPath="CF6Turret/turret-detail-927.png"' in src["00001-机身.xml"],
          "body symbol uses bitmaps 1588 and 927")
    check('a="27.373046875"' in src["00003-枪口焰.xml"], "503 fill matrix twips/px native")
    check('!330 -240' in src["00002-枪口标记.xml"], "marker shape edges in twips")
    check('alpha="0"' in src["00002-枪口标记.xml"], "marker fill invisible like original")
    check("gotoAndStop(random(3)+1);" in src["00003-枪口焰.xml"],
          "original flash random-frame behaviour kept")

    # --- simulated assemble + check ----------------------------------------
    scratch = os.path.join(HERE, "generated", "selftest-xfl")
    if os.path.isdir(scratch):
        shutil.rmtree(scratch)
    os.makedirs(os.path.join(scratch, "LIBRARY", "CF6Turret"))
    os.makedirs(os.path.join(scratch, "bin"))
    io.open(os.path.join(scratch, "bin", "M 1 0.dat"), "wb").write(b"stub")
    media_items = []
    for fname, item in (("turret-body-1588.png", bx.BODY_ITEM),
                        ("muzzle-flash-502.png", bx.FLASH_ITEM),
                        ("turret-detail-927.png", bx.DETAIL_ITEM),
                        ("fire-sound-1169.import.mp3", bx.SOUND_ITEM)):
        data = io.open(os.path.join(bx.CODEX_DIR, "bitmaps", fname), "rb").read()
        io.open(os.path.join(scratch, "LIBRARY", *item.split("/")), "wb").write(data)
        media_items.append('<DOMBitmapItem name="%s" href="%s"/>'
                           % (item, item.split("/")[-1]))
    media_items[-1] = media_items[-1].replace("DOMBitmapItem", "DOMSoundItem")
    dom = ('<DOMDocument xmlns="http://ns.adobe.com/xfl/2008/">'
           "<symbols/><media>" + "".join(media_items) + "</media><timelines/></DOMDocument>")
    io.open(os.path.join(scratch, "DOMDocument.xml"), "w", encoding="utf-8").write(dom)

    r = subprocess.run([sys.executable, "-X", "utf8", "-B", os.path.join(HERE, "build-turret-xfl.py"),
                        "--assemble", scratch], capture_output=True, text=True, encoding="utf-8", errors="replace")
    check(r.returncode == 0, "assemble on simulated post-import tree: " + r.stderr)
    r = subprocess.run([sys.executable, "-X", "utf8", "-B", os.path.join(HERE, "build-turret-xfl.py"),
                        "--check", scratch], capture_output=True, text=True, encoding="utf-8", errors="replace")
    check(r.returncode == 0 and '"check": "PASS"' in r.stdout,
          "finalize check PASS on complete tree: " + r.stdout + r.stderr)

    # negative: drop one media file -> check must FAIL
    os.remove(os.path.join(scratch, "LIBRARY", "CF6Turret", "muzzle-flash-502.png"))
    r = subprocess.run([sys.executable, "-X", "utf8", "-B", os.path.join(HERE, "build-turret-xfl.py"),
                        "--check", scratch], capture_output=True, text=True, encoding="utf-8", errors="replace")
    check(r.returncode == 1 and "muzzle-flash-502" in r.stdout,
          "finalize check FAILS closed when a media file is missing")

    # --- negative: semantic drift on the actual saved symbol XML -----------
    # Restore the media file, then per bad case re-assemble a clean tree and
    # mutate one semantic fact; --check must FAIL closed naming that fact.
    io.open(os.path.join(scratch, "LIBRARY", "CF6Turret", "muzzle-flash-502.png"),
            "wb").write(io.open(os.path.join(bx.CODEX_DIR, "bitmaps",
                                             "muzzle-flash-502.png"), "rb").read())
    turret_path = os.path.join(scratch, "LIBRARY", "CF6Turret",
                               "00004-CF6教学炮塔-A01自动炮.xml")

    def reassemble():
        rr = subprocess.run([sys.executable, "-X", "utf8", "-B", os.path.join(HERE, "build-turret-xfl.py"),
                             "--assemble", scratch], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
        check(rr.returncode == 0,
              "re-assemble clean tree before bad case: " + rr.stderr)

    def mutate(old, new):
        txt = io.open(turret_path, "r", encoding="utf-8").read()
        if old not in txt:
            print("[FAIL] mutation anchor missing: " + old)
            sys.exit(1)
        io.open(turret_path, "w", encoding="utf-8", newline="\n").write(
            txt.replace(old, new, 1))

    def expect_fail(keyword, label):
        rr = subprocess.run([sys.executable, "-X", "utf8", "-B", os.path.join(HERE, "build-turret-xfl.py"),
                             "--check", scratch], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
        check(rr.returncode == 1 and keyword in rr.stdout,
              "%s -> check FAILS closed naming it: %s"
              % (label, rr.stdout + rr.stderr))

    reassemble()
    mutate('level1="9533"', 'level1="9534"')
    expect_fail("envelope", "sound envelope value drift")

    reassemble()
    mutate("机身.filters = [new ColorMatrixFilter(",
           "机身.filters = [new ColorMatrixFilterX(")
    expect_fail("ColorMatrixFilter", "ColorMatrixFilter script removal")

    reassemble()
    mutate('<DOMFrame index="11" duration="1" keyMode="9728" soundName=',
           '<DOMFrame index="10" duration="1" keyMode="9728" soundName=')
    expect_fail("射击声", "sound keyframe index drift")

    print("test-turret-xfl: passed=%d failed=%d" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
