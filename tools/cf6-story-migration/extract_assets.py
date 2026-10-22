#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract CF6 comic/story-cutscene assets with full provenance.

Outputs (under flashswf/arts/new/Codex素材源稿/CF6漫画过场/):
- original bytes: page-art JPEG (DefineBitsJPEG2 body), music/narration MP3
  payloads (original frames, stream headers stripped per SWF spec), raw stream
  concatenations, A21 event sounds
- original vectors: per-page frame SVGs rendered by FFDec from the original
  shape/text tags (no redraw), bubble shapes as SVG
- texts.json: original DefineEditText HTML + plain text, sha-pinned
- MANIFEST.json: sha256 of every produced file + source pins

FFDec is invoked from the repo-local copy tools/ffdec/ffdec-cli.jar using the
pre-installed Adobe Animate JRE (read-only usage, no installs).

Usage: extract_assets.py [--swf PATH] [--index PATH] [--out DIR] [--work DIR]
"""
import argparse
import hashlib
import io
import json
import os
import re
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cf6swf import Swf

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEF_SWF = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图", "原作参考", "crazyflasher6-cn.swf")
DEF_INDEX = os.path.join(REPO, "tools", "cf6-story-migration", "generated", "cf6-story-index.json")
DEF_OUT = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6漫画过场")
DEF_WORK = os.path.join(REPO, "tools", "cf6-story-migration", "ffdec-work")
FFDEC_JAR = os.path.join(REPO, "tools", "ffdec", "ffdec-cli.jar")
JAVA_CANDIDATES = [
    r"C:\Program Files\Adobe\Adobe Animate 2024\jre\bin\java.exe",
    r"C:\Program Files (x86)\FFDec\jre\bin\java.exe",
]

HTML_TAG_RE = re.compile(r"<[^>]+>")
SBR_RE = re.compile(r"<sbr\s*/>")


def sha256_file(path):
    h = hashlib.sha256()
    with io.open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_java():
    for c in JAVA_CANDIDATES:
        if os.path.isfile(c):
            return c
    import shutil
    j = shutil.which("java")
    if j:
        return j
    raise SystemExit("no java runtime found; looked for repo-local FFDec JRE candidates")


def ffdec(java, swf, fmt, selectid, outdir, what):
    os.makedirs(outdir, exist_ok=True)
    cmd = [java, "-jar", FFDEC_JAR, "-format", fmt]
    if selectid:
        cmd += ["-selectid", selectid]
    cmd += ["-export", what, outdir, swf]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
    if r.returncode != 0:
        raise SystemExit("ffdec failed: %s\n%s" % (cmd, r.stderr[-2000:]))
    return r


def plain_text(html):
    t = SBR_RE.sub("", html)
    t = HTML_TAG_RE.sub("", t)
    return t.strip()


def write_bytes(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.isfile(path):
        with io.open(path, "rb") as fp:
            if fp.read() == data:
                return
    with io.open(path, "wb") as fp:
        fp.write(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--swf", default=DEF_SWF)
    ap.add_argument("--index", default=DEF_INDEX)
    ap.add_argument("--out", default=DEF_OUT)
    ap.add_argument("--work", default=DEF_WORK)
    args = ap.parse_args()

    index = json.load(io.open(args.index, encoding="utf-8"))
    swf = Swf(args.swf)
    java = find_java()
    manifest = {
        "schema": "cf6-story-assets-manifest.v1",
        "sourceSwf": index["source"],
        "extractor": {
            "script": "tools/cf6-story-migration/extract_assets.py",
            "ffdecJar": os.path.relpath(FFDEC_JAR, REPO).replace(os.sep, "/"),
            "ffdecJarSha256": sha256_file(FFDEC_JAR),
            "java": java,
        },
        "files": {},
    }

    def record(rel):
        manifest["files"][rel.replace(os.sep, "/")] = sha256_file(os.path.join(args.out, rel))

    # ---- 1. per-comic extraction ----
    for comic in index["comics"]:
        cid_dir = comic["id"]
        strip = comic["strip"]
        # page start frames: frame 1 + all advance frames except the final one
        # (the final advance enters the outer transition frame).
        advances = [a["stripFrame"] for a in comic["stripAdvances"]]
        page_starts = [1] + advances[:-1]

        # 1a. ffdec sprite SVG for the strip (all frames; we keep page frames only).
        # Resume-safe: only skip when every page-start frame SVG already exists.
        work_sprite = os.path.join(args.work, "svg", "DefineSprite_%d" % strip)
        complete = all(os.path.isfile(os.path.join(work_sprite, "%d.svg" % f)) for f in page_starts)
        if not complete:
            ffdec(java, args.swf, "sprite:svg", str(strip),
                  os.path.join(args.work, "svg"), "sprite")
        # 1b. page SVGs (original vector/text state at each page start)
        page_files = []
        for pi, frame in enumerate(page_starts):
            src = os.path.join(work_sprite, "%d.svg" % frame)
            if not os.path.isfile(src):
                raise SystemExit("missing ffdec frame svg %s" % src)
            rel = os.path.join(cid_dir, "page%d.svg" % (pi + 1))
            with io.open(src, "rb") as fp:
                data = fp.read()
            write_bytes(os.path.join(args.out, rel), data)
            record(rel)
            page_files.append(rel.replace(os.sep, "/"))
        comic["extractedPages"] = page_files

        # 1c. original JPEG bitmaps in closure
        for a in comic["assets"]:
            if a.get("kind") in ("DefineBitsJPEG2", "DefineBitsJPEG3"):
                d = swf.defs[a["charId"]]
                body = swf.raw_tag_bytes(d[1], d[2])[2:]  # skip charId UI16
                if d[0] == 35:
                    # JPEG3: alphaDataOffset UI32 then JPEG then zlib alpha; keep whole payload
                    ext = "jpeg3bin"
                else:
                    ext = "jpg"
                rel = os.path.join(cid_dir, "art-%d.%s" % (a["charId"], ext))
                write_bytes(os.path.join(args.out, rel), body)
                record(rel)
                a["extractedFile"] = rel.replace(os.sep, "/")

        # 1d. texts (original HTML from DefineEditText)
        texts = []
        for a in comic["assets"]:
            et = a.get("editText")
            if et and et.get("initialText"):
                texts.append({
                    "charId": a["charId"],
                    "htmlOriginal": et["initialText"],
                    "plainText": plain_text(et["initialText"]),
                    "fontId": et.get("fontId"),
                    "bodySha256": a.get("bodySha256"),
                })
        rel = os.path.join(cid_dir, "texts.json")
        write_bytes(os.path.join(args.out, rel),
                    (json.dumps(texts, ensure_ascii=False, indent=1) + "\n").encode("utf-8"))
        record(rel)

        # 1e. narration stream: raw concat + mp3 payload concat
        raw_all = bytearray()
        mp3_payload = bytearray()
        head = comic["verify"]["stripSoundStreamHead"]
        for code, off, ln in swf.sprites[strip]["tags"]:
            if code != 19:
                continue
            blk = swf.raw_tag_bytes(off, ln)
            raw_all += blk
            if head and head.get("format") == "mp3" and ln >= 4:
                mp3_payload += blk[4:]  # SI16 sampleCount + SI16 seekOffset
        if raw_all:
            rel = os.path.join(cid_dir, "narration-stream-raw.bin")
            write_bytes(os.path.join(args.out, rel), bytes(raw_all))
            record(rel)
        if mp3_payload:
            rel = os.path.join(cid_dir, "narration.mp3")
            write_bytes(os.path.join(args.out, rel), bytes(mp3_payload))
            record(rel)
        srel = os.path.join(cid_dir, "narration.json")
        write_bytes(os.path.join(args.out, srel), (json.dumps({
            "streamHead": head,
            "streamBlocks": comic["verify"]["stripStreamBlocks"],
            "rawConcatSha256": comic["verify"]["streamAudioSha256"],
            "note": "raw bin = SoundStreamBlock bodies concatenated byte-exact; mp3 = per-block 4-byte SI16 headers stripped per SWF spec (payload unchanged)",
        }, ensure_ascii=False, indent=1) + "\n").encode("utf-8"))
        record(srel)

    # ---- 2. music (DefineSound mp3, original bytes) ----
    for m in index["musicMap"]:
        snd = m.get("sound") or {}
        if snd.get("format") != "mp3":
            continue
        d = swf.defs[m["charId"]]
        body = swf.raw_tag_bytes(d[1], d[2])
        data = body[7 + 2:]  # id+flags+sampleCount + SI16 seekSamples
        rel = os.path.join("music", "%s.mp3" % m["exportName"])
        write_bytes(os.path.join(args.out, rel), data)
        record(rel)
        m["extractedFile"] = rel.replace(os.sep, "/")

    # ---- 3. A21 performance + end credits ----
    for perf in index["performances"]:
        pid = perf["id"]
        # event sounds
        for i, f in enumerate(swf.sprites[perf["sprite"]]["frames"]):
            for s in f["sounds"]:
                sid = s.get("soundId")
                if sid is None:
                    continue
                info = swf.define_sound_info(sid)
                if info:
                    d = swf.defs[sid]
                    body = swf.raw_tag_bytes(d[1], d[2])
                    ext = "mp3" if info["format"] == "mp3" else "bin"
                    skip = 7 + (2 if info["format"] == "mp3" else 0)
                    rel = os.path.join(pid, "sound-%d-f%d.%s" % (sid, i + 1, ext))
                    write_bytes(os.path.join(args.out, rel), body[skip:])
                    record(rel)
        # original bytes of every asset in closure (bin per tag, evidence-grade)
        for a in perf["assets"]:
            if a.get("kind") in ("DefineBitsJPEG2", "DefineBitsJPEG3", "DefineBitsLossless", "DefineBitsLossless2"):
                d = swf.defs[a["charId"]]
                rel = os.path.join(pid, "bitmap-%d.bin" % a["charId"])
                write_bytes(os.path.join(args.out, rel), swf.raw_tag_bytes(d[1], d[2])[2:])
                record(rel)
                a["extractedFile"] = rel.replace(os.sep, "/")
        # credits / performance texts via ffdec formatted text export
        text_ids = [str(a["charId"]) for a in perf["assets"] if a.get("kind") in ("DefineText2", "DefineText")]
        if text_ids:
            tdir = os.path.join(args.work, "text", pid)
            if not os.path.isdir(tdir):
                ffdec(java, args.swf, "text:formatted", ",".join(text_ids), tdir, "text")
            texts = []
            for tid in text_ids:
                tp = os.path.join(tdir, "%s.txt" % tid)
                if os.path.isfile(tp):
                    raw = io.open(tp, encoding="utf-8").read()
                    texts.append({"charId": int(tid), "ffdecFormatted": raw})
            rel = os.path.join(pid, "texts.json")
            write_bytes(os.path.join(args.out, rel),
                        (json.dumps(texts, ensure_ascii=False, indent=1) + "\n").encode("utf-8"))
            record(rel)

    # ---- 4. manifest ----
    write_bytes(os.path.join(args.out, "MANIFEST.json"),
                (json.dumps(manifest, ensure_ascii=False, indent=1) + "\n").encode("utf-8"))
    # updated index with extractedFile back-references
    idx_out = os.path.join(REPO, "tools", "cf6-story-migration", "generated", "cf6-story-index.extracted.json")
    write_bytes(idx_out, (json.dumps(index, ensure_ascii=False, indent=1) + "\n").encode("utf-8"))
    print("assets ->", os.path.relpath(args.out, REPO))
    print("files pinned:", len(manifest["files"]))
    print("index ->", os.path.relpath(idx_out, REPO))


if __name__ == "__main__":
    main()
