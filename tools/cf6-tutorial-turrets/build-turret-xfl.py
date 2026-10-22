#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Deterministic native-XFL builder for the CF6 A01 tutorial turret (r14).

Input: the verified original SWF (sha256 pinned). Decodes the turret closure
with the same bit-exact decoder as verify-native-decode.py (kept independent:
this file re-derives geometry in raw twips and fails closed on any inexact
consume) and emits the native XFL source tree for CF6_A01_Turret:

  --extract   decode SWF, write PNG/MP3 sources into the Codex source-draft
              dir + generated/geometry-r14.json (twip-exact paths, fill
              matrices, placements, ColorMatrix, StartSound facts)
  --jsfl      emit generated/import-assets.jsfl (CS6 native import recipe)
  --assemble  after the root-owned CS6 import saved the bare XFL, write
              LIBRARY/CF6Turret/*.xml + splice symbols/timelines into the saved
              DOMDocument.xml + PublishSettings.xml; refuses if the media
              items the JSFL imported are missing
  --check     verify the assembled tree: XML well-formed, every Include
              resolves, media href bytes SHA-match the Codex sources, linkage
              identifier present, symbol XML regeneration is byte-identical;
              plus SEMANTIC assertions on the actual saved turret symbol XML
              (layer/frame plan, frame-12 event sound + envelope values,
              ColorMatrixFilter script array, native placements) so a CS6
              re-save that reorders bytes but preserves meaning still passes,
              and any real drift in sound envelope / filter / frame structure
              fails closed instead of being left to human eyeballing

Nothing here runs CS6 or writes SWF. Coordinates stay native-original
(no viewport scaling anywhere).
"""
import hashlib
import io
import json
import os
import struct
import sys
import zlib

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SWF_PATH = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6地图", "原作参考", "crazyflasher6-cn.swf")
EXPECT_SHA256 = "b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01"
CODEX_DIR = os.path.join(REPO, "flashswf", "arts", "new", "Codex素材源稿", "CF6教学炮塔")
GEN_DIR = os.path.join(REPO, "tools", "cf6-tutorial-turrets", "generated")
XFL_DIR = os.path.join(REPO, "flashswf", "backgrounds", "cf6", "CF6_A01_Turret")
XFL_NAME = "CF6_A01_Turret"

LINKAGE = "CF6教学炮塔-A01自动炮"
LIB_PREFIX = "CF6Turret"
BODY_ITEM = LIB_PREFIX + "/turret-body-1588.png"
FLASH_ITEM = LIB_PREFIX + "/muzzle-flash-502.png"
DETAIL_ITEM = LIB_PREFIX + "/turret-detail-927.png"
SOUND_ITEM = LIB_PREFIX + "/fire-sound-1169.import.mp3"

COLOR_MATRIX = [
    0.48174965381622314, 0.5356919169425964, -0.027441544458270073, 0.0, -45.89500045776367,
    0.21949733793735504, 0.6808332800865173, 0.08966939151287079, 0.0, -45.89500045776367,
    0.30943387746810913, 0.3974023759365082, 0.28316378593444824, 0.0, -45.89500427246094,
    0.0, 0.0, 0.0, 1.0, 0.0,
]
SOUND_ENVELOPE = {"level0": 11022, "level1": 9533}


# ---------------------------------------------------------------- swf decode
class Bits(object):
    def __init__(self, data, pos=0):
        self.d = data
        self.byte = pos
        self.bit = 0

    def u(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | ((self.d[self.byte] >> (7 - self.bit)) & 1)
            self.bit += 1
            if self.bit == 8:
                self.bit = 0
                self.byte += 1
        return v

    def s(self, n):
        v = self.u(n)
        if n and (v >> (n - 1)) & 1:
            v -= (1 << n)
        return v

    def fb(self, n):
        return self.s(n) / 65536.0

    def align(self):
        if self.bit:
            self.bit = 0
            self.byte += 1


def read_rect_twips(b):
    nbits = b.u(5)
    vals = [b.s(nbits) for _ in range(4)]
    b.align()
    return vals  # xmin, xmax, ymin, ymax in twips


def read_matrix(b):
    a, d, bb, c = 1.0, 1.0, 0.0, 0.0
    if b.u(1):
        n = b.u(5)
        a = b.fb(n)
        d = b.fb(n)
    if b.u(1):
        n = b.u(5)
        bb = b.fb(n)
        c = b.fb(n)
    n = b.u(5)
    tx = b.s(n)
    ty = b.s(n)
    b.align()
    return {"a": a, "b": bb, "c": c, "d": d, "txTwips": tx, "tyTwips": ty}


def read_fill_array(data, b, shape_code):
    rgba = shape_code in (32, 83)
    count = data[b.byte]
    b.byte += 1
    if count == 0xFF and shape_code != 2:
        count = struct.unpack_from("<H", data, b.byte)[0]
        b.byte += 2
    styles = []
    for _ in range(count):
        t = data[b.byte]
        b.byte += 1
        st = {"type": t}
        if t == 0x00:
            n = 4 if rgba else 3
            st["color"] = list(data[b.byte:b.byte + n])
            b.byte += n
        elif t in (0x10, 0x12):
            st["matrix"] = read_matrix(b)
            n = data[b.byte] & 0x0F
            b.byte += 1 + n * (5 if rgba else 4)
            if t == 0x12:
                b.byte += 2
        elif 0x40 <= t <= 0x43:
            st["bitmapId"] = struct.unpack_from("<H", data, b.byte)[0]
            b.byte += 2
            st["matrix"] = read_matrix(b)
        else:
            raise ValueError("unknown fill type 0x%02x" % t)
        styles.append(st)
    return styles


def read_line_array(data, b, shape_code):
    rgba = shape_code in (32, 83)
    count = data[b.byte]
    b.byte += 1
    if count == 0xFF and shape_code != 2:
        count = struct.unpack_from("<H", data, b.byte)[0]
        b.byte += 2
    b.byte += count * (6 if rgba else 5)
    return count


def decode_shape(data, bs, be, code):
    """Full geometry in raw twips. Fails closed on any inexact consume."""
    b = Bits(data, bs)
    cid = b.u(16)
    bounds = read_rect_twips(b)
    arrays = []  # fill-style arrays: index 0 = initial, then newStyles gens
    arrays.append(read_fill_array(data, b, code))
    read_line_array(data, b, code)
    nfb = b.u(4)
    nlb = b.u(4)
    strokes = []  # not expected; recorded for completeness
    subpaths = []  # {fill0, fill1, gen, edges:[(cmd, twip ints...)]}
    cur = None
    cx = cy = 0
    gen = 0

    def flush():
        nonlocal cur
        if cur is not None and cur["edges"]:
            subpaths.append(cur)
        cur = None

    while True:
        if b.u(1):
            if cur is None:
                raise ValueError("edge without active subpath")
            if b.u(1):
                n = b.u(4) + 2
                if b.u(1):
                    dx = b.s(n)
                    dy = b.s(n)
                else:
                    if b.u(1):
                        dx, dy = 0, b.s(n)
                    else:
                        dx, dy = b.s(n), 0
                cx += dx
                cy += dy
                cur["edges"].append(("L", cx, cy))
            else:
                n = b.u(4) + 2
                ax, ay = b.s(n), b.s(n)
                dx, dy = b.s(n), b.s(n)
                # CurvedEdgeRecord stores both deltas relative to the
                # preceding point: control from current, anchor from control.
                ax, ay = cx + ax, cy + ay
                cx, cy = ax + dx, ay + dy
                cur["edges"].append(("Q", ax, ay, cx, cy))
        else:
            flags = b.u(5)
            if flags == 0:
                break
            move = None
            f0 = f1 = None
            if flags & 0x01:
                n = b.u(5)
                cx, cy = b.s(n), b.s(n)
                move = (cx, cy)
            if flags & 0x02:
                f0 = b.u(nfb)
            if flags & 0x04:
                f1 = b.u(nfb)
            if flags & 0x08:
                b.u(nlb)
            if flags & 0x10:
                b.align()
                arrays.append(read_fill_array(data, b, code))
                read_line_array(data, b, code)
                nfb = b.u(4)
                nlb = b.u(4)
                gen += 1
            if move is not None:
                flush()
                cur = {"gen": gen, "fill0": f0, "fill1": f1,
                       "edges": [("M", move[0], move[1])]}
            else:
                if cur is not None:
                    if f0:
                        cur["fill0"] = f0
                    if f1:
                        cur["fill1"] = f1
                elif f0 or f1:
                    raise ValueError("fill select without subpath")
    flush()
    b.align()
    if b.byte != be:
        raise ValueError("shape %d decode inexact: %d != %d" % (cid, b.byte, be))
    return {"charId": cid, "boundsTwips": bounds, "fillArrays": arrays,
            "subpaths": subpaths}


def load_swf(path):
    raw = io.open(path, "rb").read()
    sha = hashlib.sha256(raw).hexdigest()
    if sha != EXPECT_SHA256:
        raise SystemExit("swf sha256 mismatch: " + sha)
    data = zlib.decompress(raw[8:]) if raw[:3] == b"CWS" else raw[8:]
    b = Bits(data, 0)
    read_rect_twips(b)
    start = b.byte + 4
    defs = {}
    p = start
    while p + 2 <= len(data):
        ts = p
        hdr = struct.unpack_from("<H", data, p)[0]
        p += 2
        code = hdr >> 6
        ln = hdr & 0x3F
        if ln == 0x3F:
            ln = struct.unpack_from("<I", data, p)[0]
            p += 4
        bs = p
        if code in (2, 22, 32, 35, 36, 14, 39):
            cid = struct.unpack_from("<H", data, bs)[0]
            defs[cid] = (code, ts, bs, bs + ln)
        p = bs + ln
        if code == 0:
            break
    return data, defs


# ---------------------------------------------------------------- extraction
def cmd_extract():
    from PIL import Image
    data, defs = load_swf(SWF_PATH)
    out_dir = os.path.join(CODEX_DIR, "bitmaps")
    os.makedirs(out_dir, exist_ok=True)
    media = {}

    code, ts, bs, be = defs[502]
    fmt = data[bs + 2]
    w, h = struct.unpack_from("<HH", data, bs + 3)
    if fmt != 5:
        raise SystemExit("bitmap 502 expected lossless format 5, got %d" % fmt)
    z = zlib.decompress(data[bs + 7:be])
    img = Image.frombytes("RGBA", (w, h), z, "raw", "ARGB")
    p = os.path.join(out_dir, "muzzle-flash-502.png")
    img.save(p)
    media["muzzle-flash-502.png"] = _file_entry(p, w, h)

    code, ts, bs, be = defs[1588]
    alpha_off = struct.unpack_from("<I", data, bs + 2)[0]
    jpeg = data[bs + 6:bs + 6 + alpha_off]
    alpha = zlib.decompress(data[bs + 6 + alpha_off:be])
    j = Image.open(io.BytesIO(jpeg)).convert("RGB")
    a = Image.frombytes("L", j.size, alpha)
    out = Image.merge("RGBA", (*j.split(), a))
    p = os.path.join(out_dir, "turret-body-1588.png")
    out.save(p)
    jp = os.path.join(out_dir, "turret-body-1588.jpg")
    io.open(jp, "wb").write(jpeg)
    media["turret-body-1588.png"] = _file_entry(p, j.size[0], j.size[1])
    media["turret-body-1588.jpg"] = _file_entry(jp, j.size[0], j.size[1])

    code, ts, bs, be = defs[927]
    if code != 35:
        raise SystemExit("bitmap 927 expected DefineBitsJPEG3")
    alpha_off = struct.unpack_from("<I", data, bs + 2)[0]
    jpeg = data[bs + 6:bs + 6 + alpha_off]
    alpha = zlib.decompress(data[bs + 6 + alpha_off:be])
    j = Image.open(io.BytesIO(jpeg)).convert("RGB")
    a = Image.frombytes("L", j.size, alpha)
    out = Image.merge("RGBA", (*j.split(), a))
    p = os.path.join(out_dir, "turret-detail-927.png")
    out.save(p)
    jp = os.path.join(out_dir, "turret-detail-927.jpg")
    io.open(jp, "wb").write(jpeg)
    media["turret-detail-927.png"] = _file_entry(p, j.size[0], j.size[1])
    media["turret-detail-927.jpg"] = _file_entry(jp, j.size[0], j.size[1])

    code, ts, bs, be = defs[1169]
    if data[bs + 2] >> 4 != 2:
        raise SystemExit("sound 1169 expected mp3")
    # Preserve the r14 extraction byte-for-byte as historical evidence. It
    # included the high sample-count bytes and SeekSamples before MP3 frames.
    legacy_mp3 = data[bs + 5:be]
    p = os.path.join(out_dir, "fire-sound-1169.mp3")
    io.open(p, "wb").write(legacy_mp3)
    media["fire-sound-1169.mp3"] = _file_entry(p, None, None)
    # DefineSound: ID UI16 + SoundInfo UI8 + SoundSampleCount UI32;
    # MP3 SoundData then starts with SeekSamples SI16, followed by frame bytes.
    sample_count = struct.unpack_from("<I", data, bs + 3)[0]
    seek_samples = struct.unpack_from("<h", data, bs + 7)[0]
    mp3 = data[bs + 9:be]
    if hashlib.sha256(mp3).hexdigest() != "4d042c4e7e3ae242f32f357bdda66b575be4abe6f0c647d443a0d648bffe2a0a":
        raise SystemExit("sound 1169 MP3 payload differs from independent FFDec export")
    p = os.path.join(out_dir, "fire-sound-1169.import.mp3")
    io.open(p, "wb").write(mp3)
    media["fire-sound-1169.import.mp3"] = _file_entry(p, None, None)
    media["fire-sound-1169.import.mp3"].update(sampleCount=sample_count,
        seekSamples=seek_samples, sourcePayloadOffset=9)

    geometry = {}
    for cid in (277, 503, 504, 505, 1589):
        code, ts, bs, be = defs[cid]
        geometry[str(cid)] = decode_shape(data, bs, be, code)
    geom_path = os.path.join(GEN_DIR, "geometry-r14.json")
    os.makedirs(GEN_DIR, exist_ok=True)
    doc = {
        "schema": "cf6-turret-geometry.v1",
        "sourceSwfSha256": EXPECT_SHA256,
        "coordinateSpace": "native-original twips (1/20 px)",
        "shapes": geometry,
        "media": media,
        "colorMatrixFilter": COLOR_MATRIX,
        "fireSound": {"charId": 1169, "envelope": SOUND_ENVELOPE, "sync": "event"},
    }
    io.open(geom_path, "w", encoding="utf-8").write(
        json.dumps(doc, ensure_ascii=False, indent=1) + "\n")
    print(json.dumps({"extracted": sorted(media), "geometry": geom_path},
                     ensure_ascii=False))


def _file_entry(path, w, h):
    b = io.open(path, "rb").read()
    e = {"sha256": hashlib.sha256(b).hexdigest(), "bytes": len(b)}
    if w:
        e["width"] = w
        e["height"] = h
    return e


# ---------------------------------------------------------------- XFL emit
def fmt_num(v):
    s = repr(float(v))
    return s[:-2] if s.endswith(".0") else s


def bitmap_fill_xml(index, item_name, m, clipped):
    return ('<FillStyle index="%d"><BitmapFill bitmapPath="%s" bitmapIsClipped="%s">'
            '<matrix><Matrix a="%s" b="%s" c="%s" d="%s" tx="%s" ty="%s"/></matrix>'
            '</BitmapFill></FillStyle>' % (
                index, item_name, "true" if clipped else "false",
                fmt_num(m["a"]), fmt_num(m["b"]), fmt_num(m["c"]), fmt_num(m["d"]),
                fmt_num(m["txTwips"] / 20.0), fmt_num(m["tyTwips"] / 20.0)))


def solid_fill_xml(index, color):
    r, g, bb = color[0], color[1], color[2]
    alpha = color[3] / 255.0 if len(color) > 3 else 1.0
    return ('<FillStyle index="%d"><SolidColor color="#%02X%02X%02X" alpha="%s"/>'
            '</FillStyle>' % (index, r, g, bb, fmt_num(alpha)))


def shape_xml(shape, bitmap_map):
    """Emit fills/edges XFL fragments. bitmap_map: charId -> library item name."""
    fills = []
    fill_keys = {}
    for gen, arr in enumerate(shape["fillArrays"]):
        for idx, st in enumerate(arr):
            key = (gen, idx + 1)
            if st["type"] == 0x00:
                template = ("solid", st["color"])
            elif 0x40 <= st["type"] <= 0x43:
                item = bitmap_map.get(st["bitmapId"])
                if item is None:
                    # dead entry never referenced by edges: dropped on purpose
                    continue
                template = ("bitmap", item, st["matrix"], st["type"] in (0x41, 0x43))
            else:
                raise ValueError("gradient fill unexpected in turret closure")
            fill_keys[key] = len(fills) + 1
            fills.append(template)
    fill_xml_parts = []
    for i, t in enumerate(fills, start=1):
        if t[0] == "solid":
            fill_xml_parts.append(solid_fill_xml(i, t[1]))
        else:
            fill_xml_parts.append(bitmap_fill_xml(i, t[1], t[2], t[3]))
    edge_groups = {}
    for sp in shape["subpaths"]:
        if len(sp["edges"]) < 2:
            continue  # moveTo-only degenerate subpath (fill deselect marker)
        for side in ("fill0", "fill1"):
            ref = sp[side]
            if not ref:
                continue  # 0 / None = no fill on this side
            key = (sp["gen"], ref)
            if key not in fill_keys:
                raise ValueError("subpath references dropped/dead fill %s" % (key,))
            edge_groups.setdefault((side, fill_keys[key]), []).append(sp["edges"])
    parts = []
    for (side, xfl_index), groups in sorted(edge_groups.items(),
                                            key=lambda kv: (kv[0][0], kv[0][1])):
        segs = []
        for edges in groups:
            for e in edges:
                if e[0] == "M":
                    segs.append("!%d %d" % (e[1], e[2]))
                elif e[0] == "L":
                    segs.append("|%d %d" % (e[1], e[2]))
                else:
                    segs.append("[%d %d %d %d" % (e[1], e[2], e[3], e[4]))
        parts.append('<Edge %s="%d" edges="%s"/>' % (
            "fillStyle0" if side == "fill0" else "fillStyle1",
            xfl_index, "".join(segs)))
    fill_xml = "".join(fill_xml_parts)
    return ("<fills>%s</fills><edges>%s</edges>" % (fill_xml, "".join(parts))
            if fills else "<edges>%s</edges>" % "".join(parts))


def dom_shape(shape, bitmap_map):
    return "<DOMShape isFloating=\"true\">%s</DOMShape>" % shape_xml(shape, bitmap_map)


BITMAP_MAP = {502: FLASH_ITEM, 1588: BODY_ITEM, 927: DETAIL_ITEM}
BODY_SYMBOL = LIB_PREFIX + "/00001-机身"
MARKER_SYMBOL = LIB_PREFIX + "/00002-枪口标记"
FLASH_SYMBOL = LIB_PREFIX + "/00003-枪口焰"
TURRET_SYMBOL = LIB_PREFIX + "/00004-" + LINKAGE

XSI = 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
NS = 'xmlns="http://ns.adobe.com/xfl/2008/"'


def symbol_doc(name, symbol_type, inner, extra=""):
    return ("<?xml version='1.0' encoding='utf-8'?>\n"
            "<DOMSymbolItem %s %s name=\"%s\" symbolType=\"%s\"%s>"
            "<timeline><DOMTimeline name=\"%s\"><layers>%s</layers></DOMTimeline></timeline>"
            "</DOMSymbolItem>\n" % (XSI, NS, _xml_escape(name), symbol_type, extra,
                                    _xml_escape(name.split("/")[-1]), inner))


def _xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def layer(name, frames_xml, color=None):
    c = ' color="%s"' % color if color else ""
    return ('<DOMLayer name="%s"%s><frames>%s</frames></DOMLayer>'
            % (_xml_escape(name), c, frames_xml))


def frame(index, duration, elements="", action=None, extra_attrs="", extra_children=""):
    a = ""
    if action is not None:
        a = ("<Actionscript><script><![CDATA[%s]]></script></Actionscript>" % action)
    return ('<DOMFrame index="%d" duration="%d" keyMode="9728"%s>%s%s%s</DOMFrame>'
            % (index, duration, extra_attrs, a, extra_children,
               elements if elements else "<elements/>"))


def instance(item, tx, ty, name=None, symbol_type="movie clip", scale_x=None):
    n = ' name="%s"' % _xml_escape(name) if name else ""
    a = fmt_num(scale_x) if scale_x is not None else "1"
    return ('<DOMSymbolInstance libraryItemName="%s"%s symbolType="%s">'
            '<matrix><Matrix a="%s" b="0" c="0" d="1" tx="%s" ty="%s"/></matrix>'
            '</DOMSymbolInstance>' % (_xml_escape(item), n, symbol_type, a,
                                      fmt_num(tx), fmt_num(ty)))


def build_symbol_sources(geometry):
    """Deterministic LIBRARY/CF6Turret/*.xml contents (dict name -> text)."""
    shapes = geometry["shapes"]
    out = {}

    body_shape = shapes["1589"]
    body_inner = layer("机身形状", frame(0, 1, "<elements>%s</elements>"
                                         % dom_shape(body_shape, BITMAP_MAP)))
    out["00001-机身.xml"] = symbol_doc(BODY_SYMBOL, "movie clip", body_inner)

    marker_shape = shapes["277"]
    marker_inner = layer("标记形状", frame(0, 1, "<elements>%s</elements>"
                                           % dom_shape(marker_shape, BITMAP_MAP)))
    out["00002-枪口标记.xml"] = symbol_doc(MARKER_SYMBOL, "movie clip",
                                           marker_inner)

    flash_frames = []
    for i, cid in enumerate(("503", "504", "505")):
        action = "gotoAndStop(random(3)+1);" if i == 0 else None
        flash_frames.append(frame(i, 1,
                                  "<elements>%s</elements>" % dom_shape(shapes[cid], BITMAP_MAP),
                                  action=action))
    flash_inner = layer("枪口焰帧", "".join(flash_frames))
    out["00003-枪口焰.xml"] = symbol_doc(FLASH_SYMBOL, "movie clip", flash_inner)

    cm = ",".join(fmt_num(v) for v in COLOR_MATRIX)
    frame1_script = (
        "// 原作 sprite1591 帧1 对机身(1590)的 PlaceObject3 滤镜：单个 ColorMatrixFilter\n"
        "// （verify-decode-r14.json 字节精确解出；XFL 无原生 ColorMatrixFilter 节点，脚本原值应用）\n"
        "import flash.filters.*;\n"
        "stop(); // 服务取得控制之前不推进事件声音时间轴\n"
        "机身.filters = [new ColorMatrixFilter([" + cm + "])];\n"
    )
    fx_frame = frame(11, 1, "<elements>%s%s</elements>" % (
        instance(MARKER_SYMBOL, 105.25, -12.55, name="枪口位置2"),
        instance(FLASH_SYMBOL, 112.45, -70.5)))
    sound_frame = frame(11, 1,
                        extra_attrs=' soundName="%s"' % _xml_escape(SOUND_ITEM),
                        extra_children=("<SoundEnvelope><SoundEnvelopePoint level0=\"%d\" level1=\"%d\"/>"
                                        "</SoundEnvelope>"
                                        % (SOUND_ENVELOPE["level0"], SOUND_ENVELOPE["level1"])))
    turret_inner = (
        layer("actions", frame(0, 18, action=frame1_script))
        + layer("帧12枪口", frame(0, 11) + fx_frame + frame(12, 6))
        + layer("机身", frame(0, 18,
                            "<elements>%s</elements>" % instance(
                                BODY_SYMBOL, 20.55, -49.45, name="机身")))
        + layer("射击声", frame(0, 11) + sound_frame + frame(12, 6), color="#DDD603")
    )
    out["00004-CF6教学炮塔-A01自动炮.xml"] = symbol_doc(
        TURRET_SYMBOL, "movie clip", turret_inner,
        extra=(' linkageExportForAS="true" linkageExportInFirstFrame="true"'
               ' linkageIdentifier="%s"' % _xml_escape(LINKAGE)))
    return out


def build_domdocument(media_xml):
    includes = "".join('<Include href="%s" loadImmediate="false"/>'
                       % _xml_escape(LIB_PREFIX + "/" + n)
                       for n in ("00001-机身.xml", "00002-枪口标记.xml",
                                 "00003-枪口焰.xml", "00004-CF6教学炮塔-A01自动炮.xml"))
    scene = ("<timelines><DOMTimeline name=\"Scene 1\"><layers>"
             + layer("empty", frame(0, 1, action="stop();"))
             + "</layers></DOMTimeline></timelines>")
    return ("<DOMDocument xmlns=\"http://ns.adobe.com/xfl/2008/\" width=\"200\" height=\"120\" "
            "frameRate=\"30\" currentTimeline=\"1\" xflVersion=\"2.2\" "
            "creatorInfo=\"Adobe Flash Professional CS6\" platform=\"Windows\" "
            "majorVersion=\"12\" playOptionsPlayLoop=\"false\" playOptionsPlayPages=\"false\" "
            "playOptionsPlayFrameActions=\"false\">\n"
            "     <PrinterSettings/>\n     <publishHistory/>\n"
            "<symbols>%s</symbols>%s%s</DOMDocument>\n"
            % (includes, media_xml, scene))


def publish_settings_xml():
    src = os.path.join(REPO, "flashswf", "backgrounds", "cf6", "CF6_DoorWood1714",
                       "PublishSettings.xml")
    txt = io.open(src, "r", encoding="utf-8").read()
    if "CF6_DoorWood1714.swf" not in txt:
        raise SystemExit("publish-settings template drifted")
    return txt.replace("CF6_DoorWood1714.swf", XFL_NAME + ".swf")


def cmd_jsfl():
    os.makedirs(GEN_DIR, exist_ok=True)
    os.makedirs(XFL_DIR, exist_ok=True)
    assets = [
        {"src": os.path.join(CODEX_DIR, "bitmaps", "turret-body-1588.png"),
         "item": BODY_ITEM, "kind": "bitmap"},
        {"src": os.path.join(CODEX_DIR, "bitmaps", "muzzle-flash-502.png"),
         "item": FLASH_ITEM, "kind": "bitmap"},
        {"src": os.path.join(CODEX_DIR, "bitmaps", "turret-detail-927.png"),
         "item": DETAIL_ITEM, "kind": "bitmap"},
        {"src": os.path.join(CODEX_DIR, "bitmaps", "fire-sound-1169.import.mp3"),
         "item": SOUND_ITEM, "kind": "sound"},
    ]
    for a in assets:
        if not os.path.exists(a["src"]):
            raise SystemExit("run --extract first; missing " + a["src"])
    target = os.path.join(XFL_DIR, XFL_NAME + ".xfl")
    receipt = os.path.join(REPO, "tmp", "cf6-roguelike-20261021", "validation",
                           "turret-native-import-")
    lines = [
        "// Generated recipe. Run only in the root-owned CS6 session.",
        "// Deterministic native import for CF6_A01_Turret: 3 PNG + 1 MP3, nothing else.",
        "(function () {",
        "function canonicalDocumentURI(value) {",
        "  try { return encodeURI(decodeURI(value)); } catch (uriError) { return value; }",
        "}",
        "function uri(p) { return FLfile.platformPathToURI(p); }",
        "var target = uri(%s);" % json.dumps(target, ensure_ascii=False),
        "var stamp = String(new Date().getTime());",
        "var receipt = uri(%s + stamp + \".txt\");" % json.dumps(receipt, ensure_ascii=False),
        "if (!FLfile.write(receipt, \"CF6_TURRET_NATIVE_IMPORT_STARTED\\n\" + target + \"\\n\"))",
        "  throw new Error(\"Cannot write native import receipt before creating document\");",
        "var assets = [",
    ]
    for a in assets:
        lines.append("  {\"path\": %s, \"item\": %s, \"kind\": \"%s\"},"
                     % (json.dumps(a["src"], ensure_ascii=False), json.dumps(a["item"], ensure_ascii=False), a["kind"]))
    lines[-1] = lines[-1].rstrip(",")
    lines += [
        "];",
        "var doc = null;",
        "try {",
        "if (FLfile.exists(target)) throw new Error(\"Refusing to overwrite existing XFL: \" + target);",
        "doc = fl.createDocument();",
        "if (!doc) throw new Error(\"Native document creation failed\");",
        "doc.asVersion = 2;",
        "doc.frameRate = 30;",
        "doc.width = 200; doc.height = 120;",
        "if (!doc.library.itemExists(\"CF6Turret\") && doc.library.newFolder(\"CF6Turret\") === false)",
        "  throw new Error(\"Cannot create owned CF6Turret library folder\");",
        "for (var i=0; i<assets.length; i++) {",
        "  var a=assets[i];",
        "  FLfile.write(receipt,\"ASSET_BEGIN \"+a.item+\"\\n\",\"append\");",
        "  var sourceURI=uri(a.path);",
        "  if (!FLfile.exists(sourceURI)) throw new Error(\"Missing asset: \" + a.path);",
        "  doc.importFile(canonicalDocumentURI(sourceURI), false);",
        "  var item=null;",
        "  if (a.kind===\"bitmap\") {",
        "    if (doc.selection.length !== 1) throw new Error(\"Expected one PNG instance: \" + a.item);",
        "    item=doc.selection[0].libraryItem;",
        "    item.compressionType=\"lossless\";",
        "    item.useImportedJPEGData=false;",
        "    item.allowSmoothing=false;",
        "    doc.deleteSelection();",
        "  } else {",
        "    var before=doc.library.items.length;",
        "    for (var k=0;k<doc.library.items.length;k++) {",
        "      var it=doc.library.items[k];",
        "      if (it.itemType===\"sound\" && it.name.indexOf(\"fire-sound-1169\")>=0) { item=it; break; }",
        "    }",
        "    if (!item) throw new Error(\"Sound import missing from library: \" + a.item);",
        "  }",
        "  var leaf=a.item.substring(a.item.lastIndexOf(\"/\")+1);",
        "  doc.library.selectItem(item.name,true,true);",
        "  if (item.name !== leaf && doc.library.renameItem(leaf) === false)",
        "    throw new Error(\"Cannot name imported item: \" + a.item);",
        "  if (doc.library.moveToFolder(\"CF6Turret\") === false || !doc.library.itemExists(a.item))",
        "    throw new Error(\"Cannot verify imported library path: \" + a.item);",
        "  FLfile.write(receipt,\"ASSET_IMPORTED \"+a.item+\"\\n\",\"append\");",
        "}",
        "var timeline = doc.getTimeline();",
        "timeline.layers[timeline.currentLayer].name=\"empty\";",
        "timeline.layers[timeline.currentLayer].frames[0].actionScript=\"stop();\";",
        "if (!fl.saveDocument(doc,canonicalDocumentURI(target))) throw new Error(\"XFL save failed\");",
        "if (!FLfile.write(receipt,\"CF6_TURRET_NATIVE_IMPORT_SAVED\\n\"+target+\"\\n\",\"append\"))",
        "  throw new Error(\"Native XFL saved but receipt append failed\");",
        "fl.trace(\"CF6_TURRET_NATIVE_IMPORT_READY " + XFL_NAME + " \" + target);",
        "} catch (importError) {",
        "  FLfile.write(receipt,\"CF6_TURRET_NATIVE_IMPORT_ERROR\\n\"+String(importError)+\"\\n\",\"append\");",
        "  throw importError;",
        "} finally {",
        "  if (doc) fl.closeDocument(doc, false);",
        "}",
        "})();",
        "",
    ]
    out = os.path.join(GEN_DIR, "import-assets.jsfl")
    # CS6 reads BOM-less JSFL as the local code page, corrupting Chinese paths.
    io.open(out, "w", encoding="utf-8-sig", newline="\n").write("\n".join(lines))
    print(out)


def _read_media_block(dom):
    start = dom.find("<media>")
    end = dom.find("</media>")
    if start < 0 or end < 0:
        return ""
    return dom[start:end + len("</media>")]


def cmd_assemble(xfl_dir):
    geom = json.load(io.open(os.path.join(GEN_DIR, "geometry-r14.json"),
                             "r", encoding="utf-8"))
    dom_path = os.path.join(xfl_dir, "DOMDocument.xml")
    if not os.path.exists(dom_path):
        raise SystemExit("XFL not created yet; run the CS6 import JSFL first: " + dom_path)
    dom = io.open(dom_path, "r", encoding="utf-8").read()
    media = _read_media_block(dom)
    for need in (BODY_ITEM, FLASH_ITEM, DETAIL_ITEM, SOUND_ITEM):
        if ('name="%s"' % need) not in media:
            raise SystemExit("imported media item missing in saved XFL: " + need)
    sources = build_symbol_sources(geom)
    lib_dir = os.path.join(xfl_dir, "LIBRARY", LIB_PREFIX)
    os.makedirs(lib_dir, exist_ok=True)
    for name, text in sources.items():
        io.open(os.path.join(lib_dir, name), "w", encoding="utf-8",
                newline="\n").write(text)
    io.open(dom_path, "w", encoding="utf-8", newline="\n").write(
        build_domdocument(media))
    io.open(os.path.join(xfl_dir, "PublishSettings.xml"), "w",
            encoding="utf-8", newline="\n").write(publish_settings_xml())
    io.open(os.path.join(xfl_dir, XFL_NAME + ".xfl"), "w",
            encoding="ascii", newline="\n").write("PROXY-CS5")
    print(json.dumps({"assembled": sorted(sources), "xfl": dom_path},
                     ensure_ascii=False))


def _ln(tag):
    """Namespace-insensitive local name (XFL default ns may vary after CS6 saves)."""
    return tag.split("}")[-1]


def _children(el, name):
    return [c for c in el if _ln(c.tag) == name]


def _first(el, name):
    for c in el:
        if _ln(c.tag) == name:
            return c
    return None


def check_turret_semantics(xfl_dir, problems):
    """Semantic assertions on the ACTUAL saved turret symbol XML.

    Byte-compare above pins the deterministic pre-CS6 state; this layer parses
    whatever is on disk (a CS6 save may reorder attributes/whitespace) and
    asserts the machine-checkable facts the r15 review requires: 4-layer
    layout, 11+1+6 frame plan, frame-12 event sound with the original
    SoundEnvelope values, the ColorMatrixFilter frame-1 script with the exact
    20-value matrix, and the native instance placements.
    """
    import xml.etree.ElementTree as ET
    path = os.path.join(xfl_dir, "LIBRARY", LIB_PREFIX,
                        "00004-CF6教学炮塔-A01自动炮.xml")
    if not os.path.exists(path):
        problems.append("turret semantic: symbol xml missing: " + path)
        return
    try:
        root = ET.parse(path).getroot()
    except Exception as e:
        problems.append("turret semantic: symbol xml unparseable: %s" % e)
        return

    timeline = _first(root, "timeline")
    dt = _first(timeline, "DOMTimeline") if timeline is not None else None
    layers_el = _first(dt, "layers") if dt is not None else None
    layers = _children(layers_el, "DOMLayer") if layers_el is not None else []
    names = [ly.get("name") for ly in layers]
    expected_layers = ["actions", "帧12枪口", "机身", "射击声"]
    if names != expected_layers:
        problems.append("turret semantic: layer set/order drifted: %r" % (names,))
        return
    by_name = dict(zip(names, layers))

    expected_plans = {
        "actions": [(0, 18)],
        "帧12枪口": [(0, 11), (11, 1), (12, 6)],
        "机身": [(0, 18)],
        "射击声": [(0, 11), (11, 1), (12, 6)],
    }
    plans = {}
    for lname, ly in by_name.items():
        frames_el = _first(ly, "frames")
        frames = _children(frames_el, "DOMFrame") if frames_el is not None else []
        plans[lname] = [(int(f.get("index")), int(f.get("duration")))
                        for f in frames]
    for lname, want in expected_plans.items():
        if plans[lname] != want:
            problems.append("turret semantic: layer '%s' frame plan drifted: "
                            "%r != %r" % (lname, plans[lname], want))

    def frame_at(lname, index):
        frames_el = _first(by_name[lname], "frames")
        for f in _children(frames_el, "DOMFrame"):
            if f.get("index") == str(index):
                return f
        return None

    # frame-12 (index 11) event sound + original envelope values
    sf = frame_at("射击声", 11)
    if sf is None:
        problems.append("turret semantic: 射击声 frame index 11 missing")
    else:
        if sf.get("soundName") != SOUND_ITEM:
            problems.append("turret semantic: frame-12 soundName drifted: %r"
                            % (sf.get("soundName"),))
        env = _first(sf, "SoundEnvelope")
        points = _children(env, "SoundEnvelopePoint") if env is not None else []
        got = [(p.get("level0"), p.get("level1")) for p in points]
        want = [(str(SOUND_ENVELOPE["level0"]), str(SOUND_ENVELOPE["level1"]))]
        if got != want:
            problems.append("turret semantic: sound envelope drifted: %r != %r"
                            % (got, want))

    # frame-1 actions script: ColorMatrixFilter applied to 机身, exact 20 values
    af = frame_at("actions", 0)
    script_el = _first(_first(af, "Actionscript"), "script") \
        if af is not None else None
    script = script_el.text or "" if script_el is not None else ""
    if "机身.filters" not in script or "new ColorMatrixFilter([" not in script:
        problems.append("turret semantic: actions script lacks the "
                        "ColorMatrixFilter application on 机身")
    else:
        head = script.split("new ColorMatrixFilter([", 1)[1]
        try:
            body = head.split("])", 1)[0]
            vals = [float(x) for x in body.split(",")]
        except ValueError:
            vals = []
        if vals != list(COLOR_MATRIX):
            problems.append("turret semantic: ColorMatrix array drifted: "
                            "%d values, match=%s" % (len(vals), vals == list(COLOR_MATRIX)))

    # native placements
    def placements(lname, index):
        f = frame_at(lname, index)
        els = _first(f, "elements") if f is not None else None
        return _children(els, "DOMSymbolInstance") if els is not None else []

    def matrix_of(inst):
        m = _first(_first(inst, "matrix"), "Matrix")
        return (float(m.get("tx")), float(m.get("ty"))) if m is not None else None

    fx = placements("帧12枪口", 11)
    marker = [i for i in fx
              if i.get("name") == "枪口位置2"
              and i.get("libraryItemName") == MARKER_SYMBOL]
    if len(marker) != 1 or matrix_of(marker[0]) != (105.25, -12.55):
        problems.append("turret semantic: muzzle marker 枪口位置2 placement drifted: %r"
                        % ([matrix_of(i) for i in marker],))
    flash = [i for i in fx
             if i.get("libraryItemName") == FLASH_SYMBOL]
    if len(flash) != 1 or matrix_of(flash[0]) != (112.45, -70.5):
        problems.append("turret semantic: muzzle flash placement drifted: %r"
                        % ([matrix_of(i) for i in flash],))
    body = [i for i in placements("机身", 0) if i.get("name") == "机身"]
    if len(body) != 1 or matrix_of(body[0]) != (20.55, -49.45):
        problems.append("turret semantic: 机身 placement drifted: %r"
                        % ([matrix_of(i) for i in body],))


def cmd_check(xfl_dir):
    import xml.dom.minidom as minidom
    geom_path = os.path.join(GEN_DIR, "geometry-r14.json")
    geom = json.load(io.open(geom_path, "r", encoding="utf-8"))
    problems = []

    dom_path = os.path.join(xfl_dir, "DOMDocument.xml")
    if not os.path.exists(dom_path):
        problems.append("DOMDocument.xml missing")
        dom = ""
    else:
        dom = io.open(dom_path, "r", encoding="utf-8").read()
        try:
            minidom.parse(dom_path)
        except Exception as e:
            problems.append("DOMDocument.xml not well-formed: %s" % e)

    sources = build_symbol_sources(geom)
    for name, text in sources.items():
        p = os.path.join(xfl_dir, "LIBRARY", LIB_PREFIX, name)
        if not os.path.exists(p):
            problems.append("missing symbol xml: " + name)
            continue
        actual = io.open(p, "r", encoding="utf-8").read()
        if actual != text:
            problems.append("symbol xml drifted from deterministic source: " + name)
        try:
            minidom.parse(p)
        except Exception as e:
            problems.append("symbol xml not well-formed %s: %s" % (name, e))
        if ('Include href="%s/%s"' % (LIB_PREFIX, name)) not in dom:
            problems.append("DOMDocument lacks Include for " + name)

    check_turret_semantics(xfl_dir, problems)

    media = _read_media_block(dom)
    for need in (BODY_ITEM, FLASH_ITEM, DETAIL_ITEM, SOUND_ITEM):
        if ('name="%s"' % need) not in media:
            problems.append("media item missing: " + need)
    sha_map = {"turret-body-1588.png": BODY_ITEM,
               "muzzle-flash-502.png": FLASH_ITEM,
               "turret-detail-927.png": DETAIL_ITEM,
               "fire-sound-1169.import.mp3": SOUND_ITEM}
    for fname, item in sha_map.items():
        src = os.path.join(CODEX_DIR, "bitmaps", fname)
        dst = os.path.join(xfl_dir, "LIBRARY", *item.split("/"))
        if not os.path.exists(dst):
            problems.append("library media file missing: " + item)
            continue
        h_src = hashlib.sha256(io.open(src, "rb").read()).hexdigest()
        h_dst = hashlib.sha256(io.open(dst, "rb").read()).hexdigest()
        if h_src != h_dst:
            problems.append("library media bytes differ from Codex source: " + item)
        want = geom["media"][fname]["sha256"]
        if h_src != want:
            problems.append("Codex source drifted from extraction record: " + fname)

    if ('linkageIdentifier="%s"' % LINKAGE) not in sources["00004-CF6教学炮塔-A01自动炮.xml"]:
        problems.append("linkage identifier missing in turret symbol source")
    ps = os.path.join(xfl_dir, "PublishSettings.xml")
    if not os.path.exists(ps) or XFL_NAME + ".swf" not in io.open(ps, encoding="utf-8").read():
        problems.append("PublishSettings.xml missing or wrong swf name")
    if not os.path.exists(os.path.join(xfl_dir, XFL_NAME + ".xfl")):
        problems.append("xfl proxy file missing")
    bin_dir = os.path.join(xfl_dir, "bin")
    if not os.path.isdir(bin_dir) or not any(n.endswith(".dat") for n in os.listdir(bin_dir)):
        problems.append("bin/ native media cache missing (CS6 import not saved?)")

    print(json.dumps({"check": "PASS" if not problems else "FAIL",
                      "problems": problems}, ensure_ascii=False, indent=1))
    sys.exit(1 if problems else 0)


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("--extract", "--jsfl", "--assemble", "--check"):
        print(__doc__)
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "--extract":
        cmd_extract()
    elif cmd == "--jsfl":
        cmd_jsfl()
    else:
        # optional explicit target dir (used by the self-test with a simulated
        # post-import tree); default is the real deliverable path
        xfl_dir = sys.argv[2] if len(sys.argv) > 2 else XFL_DIR
        {"--assemble": cmd_assemble, "--check": cmd_check}[cmd](xfl_dir)


if __name__ == "__main__":
    main()
