#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Independent bit-exact verifier for the CF6 A01 turret native tags (r14).

Purpose: cross-check r13 claims with a from-scratch SWF-spec decoder that is
independent of scan-turret-facts.js / extract-native-tags.js (whose matrix
skip conflated NbitsScale bits with HasRotate). Decodes, from the verified
original SWF bytes:
  - full FILLSTYLEARRAY of every DefineShape in the turret closure
    (type, bitmapId, bit-exact fill MATRIX, solid RGBA),
  - LINESTYLEARRAY summary,
  - sprite 1591 timeline: every tag, incl. PlaceObject2/3 with a FULL filter
    list decode (drop-shadow/blur/glow/bevel/gradient*/convolution/colormatrix),
  - existence / tag type of every referenced charId (502, 1536, 65535, ...).

Read-only on the SWF. Usage:
  python tools/cf6-tutorial-turrets/verify-native-decode.py <swfPath> [-o out.json]
"""
import json
import struct
import sys
import zlib
import hashlib

EXPECT_SHA256 = "b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01"

TAG_NAMES = {
    0: "End", 1: "ShowFrame", 2: "DefineShape", 4: "PlaceObject", 5: "RemoveObject",
    6: "DefineBits", 8: "JPEGTables", 9: "SetBackgroundColor", 10: "DefineFont",
    11: "DefineText", 12: "DoAction", 15: "StartSound", 18: "SoundStreamHead",
    20: "DefineBitsLossless", 21: "DefineBitsJPEG2", 22: "DefineShape2",
    26: "PlaceObject2", 28: "RemoveObject2", 32: "DefineShape3", 33: "DefineText2",
    34: "DefineButton2", 35: "DefineBitsJPEG3", 36: "DefineBitsLossless2",
    37: "DefineEditText", 39: "DefineSprite", 43: "FrameLabel",
    45: "SoundStreamHead2", 46: "DefineMorphShape", 48: "DefineFont2",
    56: "ExportAssets", 59: "DoInitAction", 65: "ScriptLimits", 69: "FileAttributes",
    70: "PlaceObject3", 73: "DefineFontAlignZones", 75: "DefineFont3",
    76: "ExportAssets56", 82: "DoABC", 83: "DefineShape4", 87: "DefineBinaryData",
    88: "DefineFontName", 19: "SoundStreamBlock",
}
DEF_TAG_CODES = {2, 6, 10, 11, 14, 20, 21, 22, 32, 33, 34, 35, 36, 37, 39, 46,
                 48, 73, 74, 75, 83, 87}


class Bits(object):
    """MSB-first bit reader over a bytes object, exactly per SWF spec."""

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
        # 16.16 fixed point (used by MATRIX scale/rotate fields)
        return self.s(n) / 65536.0

    def align(self):
        if self.bit:
            self.bit = 0
            self.byte += 1

    def tell(self):
        return self.byte + (1 if self.bit else 0)


def read_rect(b):
    nbits = b.u(5)
    vals = [b.s(nbits) / 20.0 for _ in range(4)]
    b.align()
    return {"xmin": vals[0], "xmax": vals[1], "ymin": vals[2], "ymax": vals[3]}


def read_matrix(b):
    a, d, bb, c = 1.0, 1.0, 0.0, 0.0
    if b.u(1):  # HasScale
        n = b.u(5)
        a = b.fb(n)
        d = b.fb(n)
    if b.u(1):  # HasRotateSkew
        n = b.u(5)
        bb = b.fb(n)
        c = b.fb(n)
    n = b.u(5)
    tx = b.s(n) / 20.0
    ty = b.s(n) / 20.0
    b.align()
    return {"scaleX": a, "rotateSkew0": bb, "rotateSkew1": c, "scaleY": d,
            "translateX": tx, "translateY": ty}


def read_cxform(b, alpha):
    b.u(1)  # hasAdd
    b.u(1)  # hasMult
    n = b.u(4)
    fields = 4 if alpha else 3
    b.u(n * fields)
    b.u(n * fields)
    b.align()


def read_fill_styles(b, shape_code):
    # FILLSTYLEARRAY is byte-aligned; multi-byte integers are little-endian
    # (a MSB-first bit read would byte-swap them -- do not use b.u(16) here).
    rgba = shape_code in (32, 83)  # DefineShape3/4 use RGBA
    d = b.d
    count = d[b.byte]; b.byte += 1
    if count == 0xFF and shape_code != 2:
        count = struct.unpack_from("<H", d, b.byte)[0]; b.byte += 2
    styles = []
    for _ in range(count):
        st = {"type": d[b.byte]}
        b.byte += 1
        t = st["type"]
        if t == 0x00:
            n = 4 if rgba else 3
            st["rgba" if rgba else "rgb"] = list(d[b.byte:b.byte + n])
            b.byte += n
        elif t in (0x10, 0x12):
            st["matrix"] = read_matrix(b)
            n = d[b.byte] & 0x0F
            b.byte += 1
            st["gradientCount"] = n
            b.byte += n * (5 if rgba else 4)
            if t == 0x12:
                b.byte += 2  # focal
        elif 0x40 <= t <= 0x43:
            st["bitmapId"] = struct.unpack_from("<H", d, b.byte)[0]
            b.byte += 2
            st["matrix"] = read_matrix(b)
        else:
            st["unknownType"] = True
            styles.append(st)
            return styles  # cannot continue safely
        styles.append(st)
    return styles


def read_line_styles(b, shape_code):
    rgba = shape_code in (32, 83)
    d = b.d
    count = d[b.byte]; b.byte += 1
    if count == 0xFF and shape_code != 2:
        count = struct.unpack_from("<H", d, b.byte)[0]; b.byte += 2
    out = []
    for _ in range(count):
        w = struct.unpack_from("<H", d, b.byte)[0] / 20.0
        b.byte += 2
        n = 4 if rgba else 3
        c = list(d[b.byte:b.byte + n])
        b.byte += n
        out.append({"width": w, "color": c})
    return out


def read_shape_records(b, num_fill_bits, num_line_bits, shape_code_hint=2):
    """Walk SHAPERECORDs; collect used fill/line style indices (1-based).

    Bit-packed right after the NumFillBits/NumLineBits nibble pair.
    StyleChangeRecord flags (after typeFlag=0), MSB first:
    newStyles, lineStyle, fillStyle1, fillStyle0, moveTo.
    """
    used_fill0, used_fill1, used_line = set(), set(), set()
    moves = 0
    edges = 0
    while True:
        if b.u(1):  # edge record
            edges += 1
            if b.u(1):  # straight
                n = b.u(4) + 2
                if b.u(1):  # general line
                    b.s(n); b.s(n)
                else:
                    vert = b.u(1)
                    b.s(n)  # the single delta (dx or dy)
            else:  # curved
                n = b.u(4) + 2
                b.s(n); b.s(n); b.s(n); b.s(n)
        else:
            flags = b.u(5)
            if flags == 0:
                break  # EndShapeRecord
            moves += 1
            if flags & 0x01:  # moveTo
                n = b.u(5)
                b.s(n); b.s(n)
            if flags & 0x02:  # fillStyle0
                used_fill0.add(b.u(num_fill_bits))
            if flags & 0x04:  # fillStyle1
                used_fill1.add(b.u(num_fill_bits))
            if flags & 0x08:  # lineStyle
                used_line.add(b.u(num_line_bits))
            if flags & 0x10:  # newStyles comes LAST in the record (Shape2+)
                b.align()  # FillStyleArray of new styles begins on a byte boundary
                read_fill_styles(b, shape_code_hint)
                read_line_styles(b, shape_code_hint)
                num_fill_bits = b.u(4)
                num_line_bits = b.u(4)
    return {"fillStyle0Used": sorted(str(x) for x in used_fill0),
            "fillStyle1Used": sorted(str(x) for x in used_fill1),
            "lineStyleUsed": sorted(str(x) for x in used_line),
            "styleChangeRecords": moves, "edgeRecords": edges}


def read_filter_list(d, p):
    """Full FILTERLIST decode at byte offset p. Returns (filters, nextPos)."""
    n = d[p]
    p += 1
    filters = []
    for _ in range(n):
        fid = d[p]
        p += 1
        f = {"filterId": fid}
        if fid == 0:  # DropShadow
            f["kind"] = "DropShadow"
            f["rgba"] = list(d[p:p + 4]); p += 4
            f["blurX"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["blurY"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["angle"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["distance"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["strength"] = struct.unpack_from("<H", d, p)[0] / 256.0; p += 2
            flags = d[p]; p += 1
            f["innerShadow"] = bool(flags & 0x80)
            f["knockout"] = bool(flags & 0x40)
            f["compositeSource"] = bool(flags & 0x20)
            f["passes"] = flags & 0x1F
        elif fid == 1:  # Blur
            f["kind"] = "Blur"
            f["blurX"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["blurY"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            flags = d[p]; p += 1
            f["passes"] = flags >> 3
        elif fid == 2:  # Glow
            f["kind"] = "Glow"
            f["rgba"] = list(d[p:p + 4]); p += 4
            f["blurX"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["blurY"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["strength"] = struct.unpack_from("<H", d, p)[0] / 256.0; p += 2
            flags = d[p]; p += 1
            f["innerGlow"] = bool(flags & 0x80)
            f["knockout"] = bool(flags & 0x40)
            f["compositeSource"] = bool(flags & 0x20)
            f["passes"] = flags & 0x1F
        elif fid == 3:  # Bevel
            f["kind"] = "Bevel"
            f["shadowRgba"] = list(d[p:p + 4]); p += 4
            f["highlightRgba"] = list(d[p:p + 4]); p += 4
            f["blurX"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["blurY"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["angle"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["distance"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["strength"] = struct.unpack_from("<H", d, p)[0] / 256.0; p += 2
            flags = d[p]; p += 1
            f["innerShadow"] = bool(flags & 0x80)
            f["knockout"] = bool(flags & 0x40)
            f["compositeSource"] = bool(flags & 0x20)
            f["onTop"] = bool(flags & 0x10)
            f["passes"] = flags & 0x0F
        elif fid in (4, 7):  # GradientGlow / GradientBevel
            f["kind"] = "GradientGlow" if fid == 4 else "GradientBevel"
            nc = d[p]; p += 1
            f["colors"] = [list(d[p + 4 * i:p + 4 * i + 4]) for i in range(nc)]
            p += 4 * nc
            f["ratio"] = [d[p + i] for i in range(nc)]
            p += nc
            f["blurX"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["blurY"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["angle"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["distance"] = struct.unpack_from("<I", d, p)[0] / 65536.0; p += 4
            f["strength"] = struct.unpack_from("<H", d, p)[0] / 256.0; p += 2
            flags = d[p]; p += 1
            f["innerShadow"] = bool(flags & 0x80)
            f["knockout"] = bool(flags & 0x40)
            f["compositeSource"] = bool(flags & 0x20)
            f["onTop"] = bool(flags & 0x10)
            f["passes"] = flags & 0x0F
        elif fid == 5:  # Convolution
            f["kind"] = "Convolution"
            mx = d[p]; my = d[p + 1]; p += 2
            f["matrixX"] = mx; f["matrixY"] = my
            f["divisor"] = struct.unpack_from("<f", d, p)[0]; p += 4
            f["bias"] = struct.unpack_from("<f", d, p)[0]; p += 4
            f["matrix"] = [struct.unpack_from("<f", d, p + 4 * i)[0]
                           for i in range(mx * my)]
            p += 4 * mx * my
            f["defaultColor"] = list(d[p:p + 4]); p += 4
            flags = d[p]; p += 1
            f["clamp"] = bool(flags & 0x02)
            f["preserveAlpha"] = bool(flags & 0x01)
        elif fid == 6:  # ColorMatrix
            f["kind"] = "ColorMatrix"
            f["matrix"] = [struct.unpack_from("<f", d, p + 4 * i)[0] for i in range(20)]
            p += 80
        else:
            f["kind"] = "UNKNOWN"
            f["remainingBytes"] = len(d) - p
            filters.append(f)
            return filters, None
        filters.append(f)
    return filters, p


def parse_place(d, p, size, v3):
    end = p + size
    out = {"tag": "PlaceObject3" if v3 else "PlaceObject2"}
    flags1 = d[p]; p += 1
    flags2 = d[p] if v3 else 0
    if v3:
        p += 1
    out["flags1"] = flags1
    if v3:
        out["flags2"] = flags2
    has_clip_actions = bool(flags1 & 0x80)
    out["depth"] = struct.unpack_from("<H", d, p)[0]; p += 2
    if v3 and ((flags2 & 0x08) or ((flags2 & 0x10) and (flags1 & 0x02))):
        e = d.index(0, p)
        out["className"] = d[p:e].decode("utf-8", "replace"); p = e + 1
    if flags1 & 0x02:
        out["charId"] = struct.unpack_from("<H", d, p)[0]; p += 2
    if flags1 & 0x04:
        b = Bits(d, p)
        out["matrix"] = read_matrix(b)
        p = b.tell()
    if flags1 & 0x08:
        b = Bits(d, p)
        read_cxform(b, True)
        p = b.tell()
    if flags1 & 0x10:
        out["ratio"] = struct.unpack_from("<H", d, p)[0]; p += 2
    if flags1 & 0x20:
        e = d.index(0, p)
        out["name"] = d[p:e].decode("utf-8", "replace"); p = e + 1
    if flags1 & 0x40:
        out["clipDepth"] = struct.unpack_from("<H", d, p)[0]; p += 2
    if v3 and (flags2 & 0x01):
        filters, np = read_filter_list(d, p)
        out["filters"] = filters
        p = np if np is not None else end
    if v3 and (flags2 & 0x02):
        out["blendMode"] = d[p]; p += 1
    if v3 and (flags2 & 0x04):
        out["cacheAsBitmap"] = d[p]; p += 1
    if has_clip_actions:
        p += 2  # reserved
        p += 4  # all event flags
        events = []
        while p + 8 <= end:
            fl = struct.unpack_from("<I", d, p)[0]; p += 4
            if fl == 0:
                break
            sz = struct.unpack_from("<I", d, p)[0]; p += 4
            if fl & 0x200:
                p += 1
            events.append({"flags": fl, "actionBytes": sz})
            p += sz
        out["clipActionRecords"] = events
    out["parsedBytes"] = p - (end - size)
    out["consumedExact"] = (p == end)
    return out


def walk_tags(d, start, end):
    p = start
    while p + 2 <= end:
        hdr = struct.unpack_from("<H", d, p)[0]
        tag_start = p
        p += 2
        code = hdr >> 6
        ln = hdr & 0x3F
        if ln == 0x3F:
            ln = struct.unpack_from("<I", d, p)[0]
            p += 4
        body_start = p
        yield code, tag_start, body_start, body_start + ln
        p = body_start + ln
        if code == 0:
            break


def main():
    path = sys.argv[1]
    out_path = None
    if "-o" in sys.argv:
        out_path = sys.argv[sys.argv.index("-o") + 1]
    raw = open(path, "rb").read()
    sha = hashlib.sha256(raw).hexdigest()
    sig = raw[:3]
    data = zlib.decompress(raw[8:]) if sig == b"CWS" else raw[8:]
    b = Bits(data, 0)
    frame_rect = read_rect(b)
    fps = struct.unpack_from("<H", data, b.byte)[0] / 256.0
    defs = {}
    for code, ts, bs, be in walk_tags(data, b.byte + 4, len(data)):
        if code in DEF_TAG_CODES and bs + 2 <= be:
            cid = struct.unpack_from("<H", data, bs)[0]
            defs[cid] = {"code": code, "tag": TAG_NAMES.get(code, str(code)),
                         "start": ts, "bodyStart": bs, "end": be}

    closure_shapes = [277, 503, 504, 505, 1589]
    report = {"sourceSha256": sha, "shaMatch": sha == EXPECT_SHA256,
              "fps": fps, "frameRectPx": frame_rect, "shapes": {}, "sprite1591": None,
              "charIdCheck": {}}

    for cid in closure_shapes:
        d = defs.get(cid)
        if not d:
            report["shapes"][str(cid)] = None
            continue
        bb = Bits(data, d["bodyStart"])
        bb.u(16)  # id
        entry = {"tag": d["tag"], "bounds": read_rect(bb)}
        entry["fillStyles"] = read_fill_styles(bb, d["code"])
        entry["lineStyles"] = read_line_styles(bb, d["code"])
        nfb = bb.u(4)
        nlb = bb.u(4)
        entry["numFillBits"] = nfb
        entry["numLineBits"] = nlb
        entry["shapeRecords"] = read_shape_records(bb, nfb, nlb, d["code"])
        bb.align()
        entry["parsedEndByte"] = bb.byte
        entry["tagEndByte"] = d["end"]
        entry["consumedExact"] = (bb.byte == d["end"])
        report["shapes"][str(cid)] = entry

    # sprite 1591 full timeline
    d = defs.get(1591)
    if d:
        fc = struct.unpack_from("<H", data, d["bodyStart"] + 2)[0]
        frames = []
        cur = {"index": 1, "tags": []}
        frames.append(cur)
        for code, ts, bs, be in walk_tags(data, d["bodyStart"] + 4, d["end"]):
            if code == 0:
                break
            if code == 1:
                cur = {"index": cur["index"] + 1, "tags": []}
                frames.append(cur)
                continue
            t = {"code": code, "tag": TAG_NAMES.get(code, "Unknown%d" % code),
                 "len": be - bs}
            if code in (26, 70):
                t["place"] = parse_place(data, bs, be - bs, code == 70)
            elif code == 43:
                e = data.index(0, bs)
                t["label"] = data[bs:e].decode("utf-8", "replace")
            cur["tags"].append(t)
        report["sprite1591"] = {"frameCount": fc, "frames": frames}

    # charId existence check for every ref we encountered
    refs = {502, 1536, 65535, 1588, 1589, 1590, 359, 277, 503, 504, 505, 506}
    for cid in sorted(refs):
        info = defs.get(cid)
        report["charIdCheck"][str(cid)] = (
            {"exists": True, "tag": info["tag"], "offset": info["start"],
             "length": info["end"] - info["start"]} if info else {"exists": False})

    txt = json.dumps(report, ensure_ascii=False, indent=1)
    if out_path:
        open(out_path, "w", encoding="utf-8").write(txt + "\n")
        sys.stderr.write("written %s\n" % out_path)
    else:
        sys.stdout.write(txt + "\n")


if __name__ == "__main__":
    main()
