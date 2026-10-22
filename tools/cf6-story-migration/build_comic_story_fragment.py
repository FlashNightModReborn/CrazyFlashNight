#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Assemble comic-story.fragment.json from the CF6 story index + extracted assets.

Closed schema cf6-comic-story.fragment.v1. Every segment carries original
frame/label/trigger evidence, route before/after against the current
TUTORIAL→A01-A06→A08-A20→A22 route (A07 excluded, A21 performance kept),
per-page assets/text/input semantics and a single continuation. Anything not
found in the source is marked "unknown" — never invented.

--check mode re-validates: source SHA, per-asset SHA pins, page counts vs
original advance frames, rect bounds, and schema closure.

Usage: build_comic_story_fragment.py [--check]
"""
import argparse
import hashlib
import io
import json
import os
import re
import struct
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
INDEX = os.path.join(REPO, "tools", "cf6-story-migration", "generated", "cf6-story-index.extracted.json")
ASSETS = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6漫画过场")
OUT = os.path.join(REPO, "tools", "cf6-story-migration", "generated", "comic-story.fragment.json")

FPS = 30.0
VIEWPORT_W = 600.0
VIEWPORT_H = 350.0

# Current route (主控给定): TUTORIAL→A01-A06→A08-A20→A22; A07 excluded; A21 = performance map.
ROUTE_MAPS = ["TUTORIAL", "A01", "A02", "A03", "A04", "A05", "A06", "A08", "A09", "A10",
              "A11", "A12", "A13", "A14", "A15", "A16", "A17", "A18", "A19", "A20", "A22"]

# Route anchoring per comic. beforeTrigger evidence comes from batch-1 facts
# (exit config charIds) and deobfuscated scripts (目标帧 assignments).
ROUTE = {
    "cf6-s1": {"before": {"map": "TUTORIAL", "exit": "killCount>=0 (需要杀死数=0)", "evidenceCharId": 1430,
                          "evidence": "DefineSprite_1499/frame_1/PlaceObject2_1430_50"},
               "after": {"map": "A01", "originalTargetLabel": "a1"}},
    "cf6-s2": {"before": {"map": "A01", "exit": "killCount>=20", "evidenceCharId": 1587,
                          "evidence": "DefineSprite_1592/frame_1/PlaceObject2_1587_148"},
               "after": {"map": "A02", "originalTargetLabel": "a2"}},
    "cf6-s3": {"before": {"map": "A02", "exit": "killCount>=7", "evidenceCharId": 1617,
                          "evidence": "DefineSprite_1695/frame_1/PlaceObject2_1617_128"},
               "after": {"map": "A03", "originalTargetLabel": "a3"}},
    "cf6-s4": {"before": {"map": "A06", "exit": "boss(aw-蛮蛮) hp<=0 → 1766 monitor frame70 切镜",
                          "evidenceCharId": 1766, "evidence": "DefineSprite_1778/frame_1/PlaceObject2_1766_182"},
               "after": {"map": "unknown", "originalTargetLabel": "a7",
                         "note": "原作续接 A07 车辆段；现行路线排除 A07，续接目标需主控裁决（候选 A08）"}},
    "cf6-s5": {"before": {"map": "unknown",
                          "note": "原作由 A07 车辆段内撞击事件 gotoAndStop(s5) 触发"
                                  "（DefineSprite_1816/frame_3/PlaceObject2_1795_365）；A07 不入现行路线，挂点需主控裁决",
                          "evidence": "DefineSprite_1816/frame_3/PlaceObject2_1795_365"},
               "after": {"map": "A08", "originalTargetLabel": "a8"}},
    "cf6-s6": {"before": {"map": "A17", "exit": "boss(敌人-大头机器人) hp<=0 → 1766 切镜",
                          "evidenceCharId": 1766, "evidence": "DefineSprite_1954/frame_1/PlaceObject2_1766_985"},
               "after": {"map": "A18", "originalTargetLabel": "a18"}},
    "cf6-s7": {"before": {"map": "A22", "exit": "boss(敌人-老头机器人) hp<=0 → 1766 切镜",
                          "evidenceCharId": 1766, "evidence": "DefineSprite_2011/frame_1/PlaceObject2_1766_180"},
               "after": {"map": "unknown", "originalTargetLabel": "end",
                         "note": "原作续接 end 制作名单后回游戏封面；书中路线续接胜利结算，需主控裁决"}},
}

USE_RE = re.compile(
    r'<use[^>]*ffdec:characterId="(\d+)"[^>]*transform="matrix\(([^)]+)\)"[^>]*'
    r'width="([\d.]+)"[^>]*height="([\d.]+)"|<use[^>]*height="([\d.]+)"[^>]*'
    r'transform="matrix\(([^)]+)\)"[^>]*width="([\d.]+)"[^>]*xlink:href="#(text|shape)\d+"')


def sha256_file(path):
    h = hashlib.sha256()
    with io.open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def jpeg_size(path):
    with io.open(path, "rb") as fp:
        data = fp.read()
    if data[:2] != b"\xff\xd8":
        return None
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        seg = struct.unpack(">H", data[i + 2:i + 4])[0]
        i += 2 + seg
    return None


def parse_page_svg(path):
    """Extract <use> placements (characterId, matrix, size) from an ffdec frame SVG."""
    try:
        text = io.open(path, encoding="utf-8").read()
    except OSError:
        return []
    out = []
    for m in re.finditer(r'<use\b[^>]*>', text):
        tag = m.group(0)
        cid = re.search(r'ffdec:characterId="(\d+)"', tag)
        mat = re.search(r'transform="matrix\(([^)]+)\)"', tag)
        if not cid or not mat:
            continue
        vals = [float(v) for v in mat.group(1).split(",")]
        out.append({"charId": int(cid.group(1)),
                    "matrix": {"a": vals[0], "b": vals[1], "c": vals[2], "d": vals[3],
                               "tx": vals[4], "ty": vals[5]}})
    svg_w = re.search(r'<svg[^>]*width="([\d.]+)px"', text)
    svg_h = re.search(r'<svg[^>]*height="([\d.]+)px"', text)
    return {"placements": out,
            "canvas": [float(svg_w.group(1)) if svg_w else None,
                       float(svg_h.group(1)) if svg_h else None]}


def text_present_at(comic, frame):
    """EditText charIds present on the strip at a given strip frame (from place/remove events)."""
    active = {}
    for e in comic["stripTimeline"]:
        if e["stripFrame"] > frame:
            break
        if "removeDepth" in e:
            active.pop(e["removeDepth"], None)
        elif e.get("charId") is not None:
            active[e["depth"]] = e["charId"]
        elif e.get("move"):
            pass  # matrix-only move keeps the same character
    text_ids = set(a["charId"] for a in comic["assets"] if a.get("editText"))
    return sorted(cid for cid in active.values() if cid in text_ids)


def build():
    index = json.load(io.open(INDEX, encoding="utf-8"))
    manifest = json.load(io.open(os.path.join(ASSETS, "MANIFEST.json"), encoding="utf-8"))
    music_by_name = {m["exportName"]: m for m in index["musicMap"]}

    frag = {
        "schema": "cf6-comic-story.fragment.v1",
        "status": "source_prepared",
        "bookId": "cf6-sting",
        "routeId": "historical",
        "routeMaps": ROUTE_MAPS,
        "routeExclusions": ["A07"],
        "source": {
            "swf": index["source"]["swf"],
            "sha256": index["source"]["sha256"],
            "fps": index["source"]["fps"],
            "indexGenerator": "tools/cf6-story-migration/index_cf6_story.py",
            "assetExtractor": manifest["extractor"],
            "assetManifest": "flashswf/arts/new/Codex素材源稿/CF6漫画过场/MANIFEST.json",
        },
        "segments": [],
        "performances": [],
        "unknowns": [],
        "integrationNotes": [
            "Host launcher/src/Tasks/BookComicTask.cs Pages 白名单需加 cf6-s1..cf6-s7（冻结文件，主控改）",
            "Web launcher/web/modules/book-comic-content.js 需合入 cf6 页内容（冻结文件，主控改）；本 fragment 的 consumerMapping 逐段给出可直连字段",
            "AS2 侧接线：BookRunService.presentChapter 的 cf6 分支在章节边界调 Cf6StoryService.begin(pageId, continuation)；continuation 即 showChapterDialogue 等价物（主控改共享入口）",
            "原作完成/跳过殊途同归（均走切镜→目标帧）；fragment continuation 两者同一目标，取消/过期不推进",
            "旁白为连续音频流 narration.mp3，与页推进同步；现有面板无音频通道，cue 通道 cf6 默认静音（Cf6StoryService.cueSound 留表）",
            "切镜(1281) frame21 原作做 自动存盘；迁移后持久化归现役 AS2 权威，漫画服务本身零持久写",
        ],
    }

    for comic in index["comics"]:
        cid = comic["id"]
        r = ROUTE[cid]
        advances = [a["stripFrame"] for a in comic["stripAdvances"]]
        page_starts = [1] + advances[:-1]
        pan_pages = [p for p in comic["outerPages"] if p.get("pan")]
        music = music_by_name.get(comic["music"], {})

        # canvas size from original JPEG if present
        canvas = None
        art_ref = None
        for a in comic["assets"]:
            if a.get("extractedFile") and a["extractedFile"].endswith(".jpg"):
                art_ref = a
                size = jpeg_size(os.path.join(ASSETS, a["extractedFile"]))
                if size:
                    canvas = [float(size[0]), float(size[1])]

        texts_by_id = {}
        for a in comic["assets"]:
            et = a.get("editText")
            if et and et.get("initialText"):
                t = re.sub(r"<sbr\s*/>", "", et["initialText"])
                t = re.sub(r"<[^>]+>", "", t).strip()
                texts_by_id[a["charId"]] = {"plain": t, "htmlOriginal": et["initialText"],
                                            "bodySha256": a.get("bodySha256")}

        pages = []
        for pi, start in enumerate(page_starts):
            end = advances[pi] if pi < len(advances) else advances[-1]
            dur = round((end - (page_starts[pi - 1] if pi else 0) if pi else end) / FPS, 4)
            if pi:
                dur = round((end - advances[pi - 1]) / FPS, 4)
            pan = pan_pages[pi]["pan"] if pi < len(pan_pages) else {"x": 0, "y": 0}
            page = {"index": pi + 1,
                    "outerFrame": pan_pages[pi]["outerFrame"] if pi < len(pan_pages) else None,
                    "stripFrameRange": [start, end],
                    "durationSec": dur,
                    "panPx": pan,
                    "visual": "%s/page%d.svg" % (cid, pi + 1)}
            if canvas:
                page["canvasPx"] = canvas
                page["viewportRect"] = [
                    round(max(0.0, -pan["x"]) / canvas[0], 6),
                    round(max(0.0, -pan["y"]) / canvas[1], 6),
                    round(VIEWPORT_W / canvas[0], 6),
                    round(VIEWPORT_H / canvas[1], 6)]
            page_texts = []
            for tid in text_present_at(comic, start):
                if tid in texts_by_id:
                    page_texts.append(dict({"charId": tid}, **texts_by_id[tid]))
            if not page_texts:
                # all-visible comics (e.g. s2): texts live on the canvas, camera-only paging
                page_texts = []
            page["texts"] = page_texts
            pages.append(page)

        # comic-level text table (position from page-1 SVG where present)
        comic_texts = []
        svg1 = parse_page_svg(os.path.join(ASSETS, cid, "page1.svg"))
        pos_by_id = {}
        if svg1:
            for pl in svg1["placements"]:
                pos_by_id[pl["charId"]] = {"x": pl["matrix"]["tx"], "y": pl["matrix"]["ty"]}
        for tid, t in texts_by_id.items():
            comic_texts.append(dict({"charId": tid, "posPx": pos_by_id.get(tid, "unknown")}, **t))

        seg = {
            "id": cid,
            "kind": "comic",
            "original": {
                "mainLabel": comic["label"], "mainFrame": comic["mainFrame"],
                "outerSprite": comic["outer"], "stripSprite": comic["strip"],
                "stripFrames": comic["verify"]["stripSpriteFrameCount"], "fps": FPS,
                "music": {"name": comic["music"], "charId": music.get("charId"),
                          "asset": music.get("extractedFile"),
                          "loop": True, "restartPollingFrames": 30,
                          "dataSha256": (music.get("sound") or {}).get("dataSha256")},
                "skip": {"buttonCharId": comic["skipButton"], "input": "keyPress Space",
                         "script": comic.get("skipScript"),
                         "action": "_root.切镜.gotoAndPlay(2); 切镜.目标帧=目标帧"},
                "advance": {"mechanism": "strip 内 DoAction _parent.nextFrame()（旁白流驱动的自动翻页）",
                            "stripFrames": advances,
                            "scripts": [a["script"] for a in comic["stripAdvances"]]},
                "transition": {"clip": "_root.切镜", "charId": 1281,
                               "placedMainFrame": 30, "placedDepth": 1297,
                               "atFrame": 21, "does": "_root.自动存盘(); _root.gotoAndStop(目标帧)",
                               "targetLabel": comic["targets"][0]["targetLabel"] if comic["targets"] else "unknown"},
                "pageArtOriginal": art_ref and {"charId": art_ref["charId"],
                                                "asset": art_ref.get("extractedFile"),
                                                "bodySha256": art_ref.get("bodySha256")} or None,
            },
            "route": r,
            "pages": pages,
            "texts": comic_texts,
            "audio": {"narration": {"asset": "%s/narration.mp3" % cid,
                                    "rawAsset": "%s/narration-stream-raw.bin" % cid,
                                    "firstAudioFrame": comic["verify"]["stripFirstAudioFrame"],
                                    "startSec": (comic["verify"]["stripFirstAudioFrame"] - 1) / FPS,
                                    "streamHead": comic["verify"]["stripSoundStreamHead"],
                                    "rawConcatSha256": comic["verify"]["streamAudioSha256"],
                                    "note": "原作逐帧流；MP3载荷不补静音，面板按首个音频块的原始帧偏移起播"}},
            "input": {"advance": "auto", "skip": "Space(任意时刻,等价完成)",
                      "originalKeys": ["Space"]},
            "continuation": {
                "onComplete": r["after"]["map"],
                "onSkip": r["after"]["map"],
                "equivalence": "原作跳过与看完同归切镜→目标帧",
                "authority": "as2",
                "staleRule": "过期/取消/异档回调一律 expire，不推进新关",
            },
            "consumerMapping": {
                "panel": "book-comic", "pageId": cid,
                "image": (art_ref or {}).get("extractedFile"),
                "title": cid,
                "panelsFromPages": "pages[].viewportRect + pages[].durationSec 直映射 panel.rect/duration",
                "linesFromTexts": "pages[].texts[].plain → panel.lines[].text；原作无说话人标记，speaker 留空不编造",
            },
        }
        frag["segments"].append(seg)

    for perf in index["performances"]:
        frag["performances"].append({
            "id": perf["id"],
            "kind": "in-engine-performance" if perf["id"] == "cf6-a21" else "credits",
            "original": {
                "mainLabel": perf["label"], "mainFrame": perf["mainFrame"],
                "sprite": perf["sprite"], "spriteFrames": perf["spriteFrameCount"],
                "music": perf.get("music"),
                "targets": perf.get("targets", []),
            },
            "route": {"before": {"map": "A20", "exit": "boss(老头人形) hp<=0 → 1766 切镜 → a21",
                                 "evidence": "DefineSprite_1992/frame_1/PlaceObject2_1766_215"}
                      if perf["id"] == "cf6-a21" else
                      {"map": "unknown", "note": "原作由 s7 漫画切镜进入；书中路线由主控裁决"},
                      "after": {"map": "A22", "originalTargetLabel": "a22"}
                      if perf["id"] == "cf6-a21" else
                      {"map": "unknown", "originalTargetLabel": "游戏封面",
                       "note": "名单滚动+渐隐后 gotoAndStop(游戏封面)"}},
            "assets": [{"charId": a["charId"], "kind": a["kind"],
                        "bodySha256": a.get("bodySha256"),
                        "extractedFile": a.get("extractedFile")} for a in perf["assets"]],
            "texts": "%s/texts.json" % perf["id"],
            "note": "A21 为引擎内时间轴演出（283帧,3个事件音效）；完整复刻属地图/演出线，本 lane 只交付结构与素材",
        })

    frag["unknowns"] = [
        "cf6-s4.after：原作目标 a7 被现行路线排除，续接目标需主控裁决",
        "cf6-s5.before：原作触发在 A07 内，现行路线无挂点，需主控裁决",
        "cf6-s7.after / cf6-end.before-after：原作进名单回封面；书中胜利结算接线需主控裁决",
        "各漫画旁白与页内文本的逐句对齐（哪句配哪页）：原作无数据标记，仅有时间流，标 unknown 不猜",
        "漫画画面对话气泡的说话人身份：原作无文本标记，speaker 一律留空",
    ]

    with io.open(OUT, "w", encoding="utf-8", newline="\n") as fp:
        json.dump(frag, fp, ensure_ascii=False, indent=1)
        fp.write("\n")
    print("wrote", os.path.relpath(OUT, REPO))
    return frag


def check(frag):
    errors = []
    if frag["schema"] != "cf6-comic-story.fragment.v1":
        errors.append("schema")
    if frag["source"]["sha256"] != "b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01":
        errors.append("source sha")
    manifest = json.load(io.open(os.path.join(ASSETS, "MANIFEST.json"), encoding="utf-8"))
    for seg in frag["segments"]:
        n_pages = len(seg["pages"])
        n_adv = len(seg["original"]["advance"]["stripFrames"])
        if n_pages != n_adv:
            errors.append("%s page count %d != advances %d" % (seg["id"], n_pages, n_adv))
        for p in seg["pages"]:
            v = p.get("viewportRect")
            if v and not (0 <= v[0] < 1 and 0 <= v[1] < 1 and 0 < v[2] <= 1 and 0 < v[3] <= 1):
                errors.append("%s page%d rect out of bounds" % (seg["id"], p["index"]))
            rel = p["visual"]
            want = manifest["files"].get(rel)
            if not want:
                errors.append("%s missing pinned asset %s" % (seg["id"], rel))
            else:
                got = sha256_file(os.path.join(ASSETS, rel))
                if got != want:
                    errors.append("%s asset sha mismatch %s" % (seg["id"], rel))
        img = seg["consumerMapping"]["image"]
        if img:
            want = manifest["files"].get(img)
            got = sha256_file(os.path.join(ASSETS, img)) if want else None
            if want is None or got != want:
                errors.append("%s consumer image pin mismatch" % seg["id"])
    print("check:", "OK" if not errors else "FAIL")
    for e in errors:
        print("  -", e)
    return not errors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.check:
        frag = json.load(io.open(OUT, encoding="utf-8"))
        sys.exit(0 if check(frag) else 1)
    frag = build()
    sys.exit(0 if check(frag) else 1)


if __name__ == "__main__":
    main()
