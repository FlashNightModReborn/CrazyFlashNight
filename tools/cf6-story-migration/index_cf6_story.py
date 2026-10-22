#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Index all CF6 (crazyflasher6-cn.swf) comic / story cutscenes into
cf6-story-index.json — the ground-truth source for fragment assembly.

Read-only against the original SWF and the existing deobfuscated script export.
Every structural claim is derived from the SWF itself; pan targets / page
advance frames / transition labels are cross-checked against the deobfuscated
scripts (path pinned by directory SHA is out of scope — file list recorded).

Usage: index_cf6_story.py [--swf PATH] [--scripts DIR] [--out PATH]
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cf6swf import Swf, TAG_NAMES

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEF_SWF = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图", "原作参考", "crazyflasher6-cn.swf")
DEF_SCRIPTS = os.path.join(REPO, "tmp", "cf6-soldier-20261016", "knife-audit", "deobfuscated-export", "scripts")
DEF_OUT = os.path.join(REPO, "tools", "cf6-story-migration", "generated", "cf6-story-index.json")

EXPECTED_SHA256 = "b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01"

# Discovered comic table (main-label -> outer/strip sprite ids, verified by parse).
COMICS = [
    {"id": "cf6-s1", "label": "s1", "outer": 1292, "strip": 1289, "skipButton": 1291},
    {"id": "cf6-s2", "label": "s2", "outer": 1308, "strip": 1307, "skipButton": 1291},
    {"id": "cf6-s3", "label": "s3", "outer": 1325, "strip": 1324, "skipButton": 1291},
    {"id": "cf6-s4", "label": "s4", "outer": 1334, "strip": 1333, "skipButton": 1291},
    {"id": "cf6-s5", "label": "s5", "outer": 1349, "strip": 1348, "skipButton": 1291},
    {"id": "cf6-s6", "label": "s6", "outer": 1384, "strip": 1383, "skipButton": 1291},
    {"id": "cf6-s7", "label": "s7", "outer": 1400, "strip": 1399, "skipButton": 1291},
]

MYX_RE = re.compile(r"myx\s*=\s*(-?\d+)\s*;")
MYY_RE = re.compile(r"myy\s*=\s*(-?\d+)\s*;")
MUSIC_RE = re.compile(r'循环播放音乐\s*=\s*"([^"]*)"')
TARGET_RE = re.compile(r'目标帧\s*=\s*"([^"]+)"')


def read_text(path):
    return io.open(path, "r", encoding="utf-8", errors="replace").read()


def script_file(scripts_dir, *parts):
    p = os.path.join(scripts_dir, *parts)
    return p if os.path.isfile(p) else None


def outer_pages(scripts_dir, outer_id):
    """Parse per-frame DoAction of the outer comic sprite -> page pan list."""
    pages = []
    base = os.path.join(scripts_dir, "DefineSprite_%d" % outer_id)
    frame_dirs = sorted(
        (d for d in os.listdir(base) if d.startswith("frame_")),
        key=lambda d: int(d.split("_")[1]),
    ) if os.path.isdir(base) else []
    for d in frame_dirs:
        fno = int(d.split("_")[1])
        f = script_file(scripts_dir, "DefineSprite_%d" % outer_id, d, "DoAction.as")
        if not f:
            continue
        src = read_text(f)
        mx = MYX_RE.search(src)
        my = MYY_RE.search(src)
        entry = {"outerFrame": fno, "script": os.path.relpath(f, scripts_dir)}
        if mx and my:
            entry["pan"] = {"x": int(mx.group(1)), "y": int(my.group(1))}
        if "切镜" in src:
            entry["transition"] = True
        if "stop();" in src:
            entry["stop"] = True
        pages.append(entry)
    return pages


def strip_advances(scripts_dir, strip_id):
    """Parse strip frames whose DoAction calls _parent.nextFrame()."""
    out = []
    base = os.path.join(scripts_dir, "DefineSprite_%d" % strip_id)
    if not os.path.isdir(base):
        return out
    for d in sorted(os.listdir(base), key=lambda d: int(d.split("_")[1])):
        if not d.startswith("frame_"):
            continue
        f = script_file(scripts_dir, "DefineSprite_%d" % strip_id, d, "DoAction.as")
        if not f:
            continue
        src = read_text(f)
        if "_parent.nextFrame()" in src:
            out.append({"stripFrame": int(d.split("_")[1]),
                        "stops": "stop();" in src,
                        "script": os.path.relpath(f, scripts_dir)})
    return out


def main_frame_script(scripts_dir, frame_no):
    """Main timeline frame folder (1-based in deobfuscated export)."""
    base = os.path.join(scripts_dir, "frame_%d" % frame_no)
    if not os.path.isdir(base):
        return {}
    out = {}
    f = os.path.join(base, "DoAction.as")
    if os.path.isfile(f):
        src = read_text(f)
        m = MUSIC_RE.search(src)
        if m:
            out["music"] = m.group(1)
    for root, _dirs, files in os.walk(base):
        for fn in files:
            if not fn.endswith(".as"):
                continue
            src = read_text(os.path.join(root, fn))
            t = TARGET_RE.search(src)
            if t and "onClipEvent(load)" in fn:
                out.setdefault("targets", []).append(
                    {"script": os.path.relpath(os.path.join(root, fn), scripts_dir), "targetLabel": t.group(1)})
    return out


def subtree_char_ids(swf, root_ids, max_depth=8):
    """All character ids reachable from root sprite ids via PlaceObject charId,
    plus bitmap ids referenced by shape fills (comic pages bake art as bitmap
    fills inside shapes)."""
    seen = set()
    stack = [(sid, 0) for sid in root_ids]
    while stack:
        sid, depth = stack.pop()
        if sid in seen or depth > max_depth:
            continue
        seen.add(sid)
        sp = swf.sprites.get(sid)
        if sp:
            for f in sp["frames"]:
                for pl in f["places"]:
                    cid = pl.get("charId")
                    if cid is not None and cid not in seen:
                        stack.append((cid, depth + 1))
        else:
            for ref in swf.shape_bitmap_refs(sid):
                if ref not in seen:
                    stack.append((ref, depth + 1))
    return sorted(seen)


def asset_record(swf, cid):
    """Describe one character: kind + original-byte SHA pin."""
    rec = {"charId": cid}
    if cid in swf.sprites:
        rec["kind"] = "sprite"
        rec["frameCount"] = len(swf.sprites[cid]["frames"])
        # pin: sha over concatenated sprite tag body bytes
        h = hashlib.sha256()
        for _c, off, ln in swf.sprites[cid]["tags"]:
            h.update(swf.raw_tag_bytes(off, ln))
        rec["bodySha256"] = h.hexdigest()
        return rec
    d = swf.defs.get(cid)
    if not d:
        rec["kind"] = "unknown"
        return rec
    code, off, ln = d
    rec["kind"] = TAG_NAMES.get(code, "tag%d" % code)
    rec["tagCode"] = code
    rec["bodyBytes"] = ln
    rec["bodySha256"] = swf.tag_sha256(off, ln)
    if code == 37:
        et = swf.edit_text(cid)
        if et:
            rec["editText"] = et
    if code == 14:
        rec["sound"] = swf.define_sound_info(cid)
    if cid in swf.exports:
        rec["exportName"] = swf.exports[cid]
    return rec


def strip_timeline(swf, strip_id):
    """Keep the original tag order, including remove/place at the same depth."""
    events = []
    frame = 1
    for code, off, length in swf.sprites[strip_id]["tags"]:
        if code == 1:
            frame += 1
        elif code in (26, 70):
            pl = swf._parse_place(code, off, length)
            e = {"stripFrame": frame, "depth": pl.get("depth")}
            if pl.get("charId") is not None:
                e["charId"] = pl["charId"]
            if pl.get("matrix"):
                e["matrix"] = pl["matrix"]
            if pl.get("move"):
                e["move"] = True
            events.append(e)
        elif code in (5, 28):
            depth_offset = off + (2 if code == 5 else 0)
            depth = int.from_bytes(swf.body[depth_offset:depth_offset + 2], "little")
            events.append({"stripFrame": frame, "removeDepth": depth})
    return events


def first_stream_audio_frame(swf, strip_id):
    """MP3 extraction removes block headers, so retain its original start frame."""
    frame = 1
    for code, off, length in swf.sprites[strip_id]["tags"]:
        if code == 1:
            frame += 1
        elif code == 19 and length > 4:
            samples = int.from_bytes(swf.body[off:off + 2], "little")
            if samples > 0:
                return frame
    raise ValueError("no nonempty MP3 stream block in sprite %s" % strip_id)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--swf", default=DEF_SWF)
    ap.add_argument("--scripts", default=DEF_SCRIPTS)
    ap.add_argument("--out", default=DEF_OUT)
    args = ap.parse_args()

    swf = Swf(args.swf)
    index = {
        "schema": "cf6-story-index.v1",
        "source": {
            "swf": os.path.relpath(args.swf, REPO).replace(os.sep, "/"),
            "sha256": swf.sha256,
            "expectedSha256": EXPECTED_SHA256,
            "sha256Match": swf.sha256 == EXPECTED_SHA256,
            "swfVersion": swf.version,
            "fps": swf.fps,
            "mainFrameCount": swf.frame_count,
            "stageRectTwips": swf.stage_rect,
            "deobfuscatedScripts": os.path.relpath(args.scripts, REPO),
        },
        "comics": [],
        "performances": [],
        "musicMap": [],
        "transitionClips": [],
    }

    # main labels
    labels = {}
    for i, f in enumerate(swf.main_frames):
        if f.get("label"):
            labels[f["label"]] = i
    index["mainLabels"] = labels

    # transition clip (切镜) resolution
    index["transitionClips"] = swf.find_named_instances("切镜")

    for c in COMICS:
        label_frame = labels.get(c["label"])
        entry = dict(c)
        entry["mainFrame"] = label_frame
        # music + target label live on the frame after the label frame (label+1 folder
        # in the deobfuscated export, which numbers main frames 1-based).
        fs = main_frame_script(args.scripts, label_frame + 1)
        entry["music"] = fs.get("music")
        entry["targets"] = fs.get("targets", [])
        entry["outerPages"] = outer_pages(args.scripts, c["outer"])
        entry["stripAdvances"] = strip_advances(args.scripts, c["strip"])
        # structural verification from SWF itself
        outer_frames = swf.sprite_frames(c["outer"])
        strip_frames = swf.sprite_frames(c["strip"])
        entry["verify"] = {
            "outerSpriteFrameCount": len(outer_frames),
            "stripSpriteFrameCount": len(strip_frames),
            "outerFrame1Places": [
                {"charId": p.get("charId"), "depth": p.get("depth"), "name": p.get("name")}
                for p in (outer_frames[0]["places"] if outer_frames else [])
            ],
            "stripSoundStreamHead": swf.sound_stream_head(swf.sprites[c["strip"]]["tags"]),
            "stripStreamBlocks": sum(f["stream_blocks"] for f in strip_frames),
            "stripFirstAudioFrame": first_stream_audio_frame(swf, c["strip"]),
            "outerSoundStreamHead": swf.sound_stream_head(swf.sprites[c["outer"]]["tags"]),
        }
        # stream audio raw bytes (original, unparsed codec payload)
        h = hashlib.sha256()
        total = 0
        for code, off, ln in swf.sprites[c["strip"]]["tags"]:
            if code == 19:
                # SoundStreamBlock body = SI16 sampleCount? actually raw stream data
                h.update(swf.raw_tag_bytes(off, ln))
                total += ln
        entry["verify"]["streamAudioSha256"] = h.hexdigest()
        entry["verify"]["streamAudioBytes"] = total
        # assets closure
        chars = subtree_char_ids(swf, [c["strip"], c["outer"], c["skipButton"]])
        entry["assetIds"] = chars
        entry["assets"] = [asset_record(swf, cid) for cid in chars]
        entry["stripTimeline"] = strip_timeline(swf, c["strip"])
        # skip button script evidence
        bf = script_file(args.scripts, "DefineButton2_%d" % c["skipButton"], "BUTTONCONDACTION on(keyPress Space).as")
        entry["skipScript"] = os.path.relpath(bf, args.scripts) if bf else None
        index["comics"].append(entry)

    # A21 performance + end credits
    for perf_id, label, sprite_id in (("cf6-a21", "a21", 2008), ("cf6-end", "end", 2034)):
        label_frame = labels.get(label)
        frames = swf.sprite_frames(sprite_id)
        chars = subtree_char_ids(swf, [sprite_id])
        fs = main_frame_script(args.scripts, label_frame + 1)
        index["performances"].append({
            "id": perf_id, "label": label, "mainFrame": label_frame,
            "sprite": sprite_id, "spriteFrameCount": len(frames),
            "music": fs.get("music"), "targets": fs.get("targets", []),
            "soundStreamHead": swf.sound_stream_head(swf.sprites[sprite_id]["tags"]),
            "assetIds": chars,
            "assets": [asset_record(swf, cid) for cid in chars],
        })

    # music: 音乐循环播放器 (sprite 94) does attachSound(循环播放音乐), so
    # "musicNN" are DefineSound export names — resolve via ExportAssets.
    mm = []
    for cid, name in sorted(swf.exports.items()):
        if isinstance(name, str) and name.startswith("music"):
            info = swf.define_sound_info(cid)
            mm.append({"exportName": name, "charId": cid, "sound": info})
    index["musicMap"] = mm

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with io.open(args.out, "w", encoding="utf-8", newline="\n") as fp:
        json.dump(index, fp, ensure_ascii=False, indent=1)
        fp.write("\n")
    print("wrote %s" % os.path.relpath(args.out, REPO))
    print("sha256 match: %s" % (swf.sha256 == EXPECTED_SHA256))
    for c in index["comics"]:
        v = c["verify"]
        print(c["id"], "mainFrame", c["mainFrame"], "pages", len([p for p in c["outerPages"] if p.get("pan")]),
              "advances", len(c["stripAdvances"]), "stripFrames", v["stripSpriteFrameCount"],
              "music", c["music"], "targets", [t["targetLabel"] for t in c["targets"]],
              "assets", len(c["assets"]), "audioBytes", v["streamAudioBytes"])


if __name__ == "__main__":
    main()
