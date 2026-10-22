#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Minimal read-only SWF (FWS/CWS) parser for CF6 story-cutscene indexing.

Scope: only what the comic/cutscene migration needs — tag walk, DefineSprite
recursion, PlaceObject2/3 (MSB-first flags), MATRIX translate/scale, FrameLabel,
DefineEditText initial HTML text, SoundStreamHead(2) params, DefineSound params,
ExportAssets, raw tag byte ranges for SHA256 pinning.

PlaceObject2 flags are MSB-first per the SWF spec:
  0x80 hasClipActions, 0x40 hasClipDepth, 0x20 hasName, 0x10 hasRatio,
  0x08 hasColorTransform, 0x04 hasMatrix, 0x02 hasCharacter, 0x01 move.
(Verified against crazyflasher6-cn.swf sprite 1289: flags=0x06 -> charId present.)
"""
import hashlib
import io
import struct
import zlib

TAG_NAMES = {
    0: "End", 1: "ShowFrame", 2: "DefineShape", 6: "DefineBits", 8: "JPEGTables",
    9: "SetBackgroundColor", 10: "DefineFont", 11: "DefineText", 14: "DefineSound",
    15: "StartSound", 18: "SoundStreamHead", 19: "SoundStreamBlock",
    20: "DefineBitsLossless", 21: "DefineBitsJPEG2", 22: "DefineShape2",
    26: "PlaceObject2", 28: "RemoveObject2", 32: "DefineShape3",
    33: "DefineText2", 35: "DefineBitsJPEG3", 36: "DefineBitsLossless2",
    37: "DefineEditText", 39: "DefineSprite", 43: "FrameLabel",
    45: "SoundStreamHead2", 46: "DefineMorphShape", 48: "DefineFont2",
    59: "DoInitAction", 69: "FileAttributes", 70: "PlaceObject3",
    73: "DefineFontAlignZones", 75: "DefineFont3", 76: "ExportAssets",
    82: "DoAction", 83: "DefineShape4", 87: "DefineBinaryData",
    88: "DefineFontName", 89: "StartSound2",
}
# Tags whose body starts with a UI16 character id.
DEF_TAG_CODES = {2, 6, 10, 11, 14, 20, 21, 22, 32, 33, 34, 35, 36, 37, 39, 46, 48, 73, 74, 75, 83, 87}

SOUND_FORMATS = {0: "uncompressed-native", 1: "adpcm", 2: "mp3", 3: "uncompressed-le", 4: "nellymoser16", 5: "nellymoser8", 6: "nellymoser", 11: "speex"}
SOUND_RATES = {0: 5512, 1: 11025, 2: 22050, 3: 44100}


def _sha(b):
    return hashlib.sha256(b).hexdigest()


class Swf(object):
    def __init__(self, path):
        self.path = path
        self.raw = io.open(path, "rb").read()
        self.sha256 = _sha(self.raw)
        sig = self.raw[:3]
        if sig == b"FWS":
            self.body = self.raw[8:]
        elif sig == b"CWS":
            self.body = zlib.decompress(self.raw[8:])
        else:
            raise ValueError("unsupported signature %r" % sig)
        self.version = self.raw[3]
        bits = self.body[0] >> 3
        rect_bytes = (5 + bits * 4 + 7) // 8
        # stage rect in twips
        self.stage_rect = self._read_rect(self.body, 0)
        hoff = rect_bytes
        self.fps = struct.unpack("<H", self.body[hoff:hoff + 2])[0] / 256.0
        self.frame_count = struct.unpack("<H", self.body[hoff + 2:hoff + 4])[0]
        self.tags = []           # (code, body_start, length) over decompressed body
        self.sprites = {}        # id -> list of (code, start, len)
        self.defs = {}           # id -> (code, start, len)  non-sprite definitions
        self.main_frames = []    # per-frame dicts
        self.exports = {}        # id -> name
        self._walk()

    @staticmethod
    def _read_rect(buf, off):
        bits = buf[off] >> 3
        n = 5 + bits * 4
        # bit reader
        val = 0
        data = buf[off:off + (n + 7) // 8]
        acc = int.from_bytes(data, "big")
        total_bits = len(data) * 8
        vals = []
        pos = 5
        for _ in range(4):
            v = (acc >> (total_bits - pos - bits)) & ((1 << bits) - 1)
            # sign extend
            if v & (1 << (bits - 1)):
                v -= 1 << bits
            vals.append(v)
            pos += bits
        return {"xmin": vals[0], "xmax": vals[1], "ymin": vals[2], "ymax": vals[3]}

    def _walk_tags(self, start, end):
        off = start
        while off + 2 <= end:
            h = struct.unpack("<H", self.body[off:off + 2])[0]
            off += 2
            code = h >> 6
            ln = h & 0x3F
            if ln == 0x3F:
                ln = struct.unpack("<I", self.body[off:off + 4])[0]
                off += 4
            yield code, off, ln
            off += ln

    def _walk(self):
        bits = self.body[0] >> 3
        rect_bytes = (5 + bits * 4 + 7) // 8
        start = rect_bytes + 4
        # main timeline frame assembly
        cur = {"places": [], "removes": [], "actions": 0, "label": None, "sounds": []}
        for code, off, ln in self._walk_tags(start, len(self.body)):
            self.tags.append((code, off, ln))
            cid = None
            if code in DEF_TAG_CODES and ln >= 2:
                cid = struct.unpack("<H", self.body[off:off + 2])[0]
            if code == 39:
                self.sprites[cid] = self._walk_sprite(off + 4, off + ln)
            elif cid is not None:
                self.defs[cid] = (code, off, ln)
            if code == 1:  # ShowFrame
                self.main_frames.append(cur)
                cur = {"places": [], "removes": [], "actions": 0, "label": None, "sounds": []}
            elif code == 43:
                cur["label"] = self._cstr(off)
            elif code in (26, 70):
                cur["places"].append(self._parse_place(code, off, ln))
            elif code in (27, 28):
                cur["removes"].append({"code": code, "depth": struct.unpack("<H", self.body[off + (2 if code == 27 else 0):off + (4 if code == 27 else 2)])[0] if ln >= 2 else None})
            elif code in (82, 59):
                cur["actions"] += 1
            elif code in (15, 89):
                cur["sounds"].append(self._parse_start_sound(code, off, ln))
            elif code == 56:
                self._parse_exports(off, ln)

    def _walk_sprite(self, start, end):
        tags = []
        frames = []
        cur = {"places": [], "removes": [], "actions": 0, "label": None, "sounds": [], "stream_blocks": 0}
        for code, off, ln in self._walk_tags(start, end):
            tags.append((code, off, ln))
            if code == 1:
                frames.append(cur)
                cur = {"places": [], "removes": [], "actions": 0, "label": None, "sounds": [], "stream_blocks": 0}
            elif code == 43:
                cur["label"] = self._cstr(off)
            elif code in (26, 70):
                cur["places"].append(self._parse_place(code, off, ln))
            elif code in (27, 28):
                dpos = off + (2 if code == 27 else 0)
                cur["removes"].append(struct.unpack("<H", self.body[dpos:dpos + 2])[0] if ln >= 2 else None)
            elif code in (82, 59):
                cur["actions"] += 1
            elif code in (15, 89):
                cur["sounds"].append(self._parse_start_sound(code, off, ln))
            elif code == 19:
                cur["stream_blocks"] += 1
        return {"tags": tags, "frames": frames}

    def _cstr(self, off):
        e = self.body.index(0, off)
        return self.body[off:e].decode("utf-8", "replace")

    def _read_matrix(self, off):
        # Bit layout (MSB-first): hasScale:1, hasRotate:1,
        # [scaleBits:5, scaleX, scaleY] if hasScale,
        # [rotBits:5, skew0, skew1] if hasRotate,
        # transBits:5, tx, ty. Field widths are self-describing,
        # so read a generous window and compute consumed bytes at the end.
        data = self.body[off:off + 32]
        acc = int.from_bytes(data, "big")
        total = len(data) * 8
        pos = 0

        def read(n):
            nonlocal pos
            if n <= 0:
                return 0
            v = (acc >> (total - pos - n)) & ((1 << n) - 1)
            if v & (1 << (n - 1)):
                v -= 1 << n
            pos += n
            return v

        has_scale = read(1)
        has_rot = read(1)
        scale = None
        rot = None
        if has_scale:
            sbits = read(5)
            scale = (read(sbits) / 65536.0, read(sbits) / 65536.0)
        if has_rot:
            rbits = read(5)
            rot = (read(rbits) / 65536.0, read(rbits) / 65536.0)
        tbits = read(5)
        tx = read(tbits)
        ty = read(tbits)
        nbytes = (pos + 7) // 8
        return {"tx": tx, "ty": ty, "scale": scale, "rotate": rot}, off + nbytes

    def _skip_cxform(self, off, alpha):
        b0 = self.body[off]
        has_add = b0 & 0x20
        has_mul = b0 & 0x10
        nbits = b0 & 0x0F
        channels = 4 if alpha else 3
        fields = (channels if has_add else 0) + (channels if has_mul else 0)
        return off + (6 + nbits * fields + 7) // 8

    def _parse_place(self, code, off, ln):
        b = self.body
        p = {"tag": TAG_NAMES.get(code, code)}
        if code == 26:
            flags = b[off]
            p["depth"] = struct.unpack("<H", b[off + 1:off + 3])[0]
            q = off + 3
            if flags & 0x02:
                p["charId"] = struct.unpack("<H", b[q:q + 2])[0]
                q += 2
            if flags & 0x04:
                m, q = self._read_matrix(q)
                p["matrix"] = m
            if flags & 0x08:
                q = self._skip_cxform(q, False)
            if flags & 0x10:
                p["ratio"] = struct.unpack("<H", b[q:q + 2])[0]
                q += 2
            if flags & 0x20:
                e = b.index(0, q)
                p["name"] = b[q:e].decode("utf-8", "replace")
                q = e + 1
            if flags & 0x40:
                p["clipDepth"] = struct.unpack("<H", b[q:q + 2])[0]
                q += 2
            if flags & 0x80:
                p["clipActions"] = True
            p["move"] = bool(flags & 0x01)
        else:  # PlaceObject3
            f1 = b[off]
            f2 = b[off + 1]
            p["depth"] = struct.unpack("<H", b[off + 2:off + 4])[0]
            q = off + 4
            if f2 & 0x08:
                e = b.index(0, q)
                p["className"] = b[q:e].decode("utf-8", "replace")
                q = e + 1
            if f1 & 0x02:
                p["charId"] = struct.unpack("<H", b[q:q + 2])[0]
                q += 2
            if f1 & 0x04:
                m, q = self._read_matrix(q)
                p["matrix"] = m
            p["move"] = bool(f1 & 0x01)
        return p

    def _parse_start_sound(self, code, off, ln):
        # StartSound: soundId UI16 + SoundInfo byte (skip detail); StartSound2: name cstr + info
        if code == 15 and ln >= 3:
            return {"soundId": struct.unpack("<H", self.body[off:off + 2])[0]}
        if code == 89:
            return {"soundName": self._cstr(off)}
        return {}

    def _parse_exports(self, off, ln):
        count = struct.unpack("<H", self.body[off:off + 2])[0]
        q = off + 2
        for _ in range(count):
            cid = struct.unpack("<H", self.body[q:q + 2])[0]
            q += 2
            e = self.body.index(0, q)
            self.exports[cid] = self.body[q:e].decode("utf-8", "replace")
            q = e + 1

    # ---- higher level helpers ----

    def raw_tag_bytes(self, off, ln):
        """Header + body bytes of the tag (original bytes, as stored decompressed)."""
        # recover header start: we stored body offset; header is 2 or 6 bytes before
        # short header if ln < 0x3F originally — we cannot know; recompute is unsafe.
        # Instead pin BODY bytes, which are the definition payload.
        return self.body[off:off + ln]

    def tag_sha256(self, off, ln):
        return _sha(self.raw_tag_bytes(off, ln))

    def sound_stream_head(self, tags):
        """Return parsed SoundStreamHead/2 params from a tag list, or None."""
        for code, off, ln in tags:
            if code in (18, 45) and ln >= 4:
                b0 = self.body[off]
                b1 = self.body[off + 1]
                lat = struct.unpack("<H", self.body[off + 2:off + 4])[0] if ln >= 4 else None
                return {
                    "tag": TAG_NAMES[code],
                    "playbackRate": SOUND_RATES.get((b0 >> 2) & 3),
                    "playback16bit": bool(b0 & 2),
                    "playbackStereo": bool(b0 & 1),
                    "format": SOUND_FORMATS.get((b1 >> 4) & 15, "unknown"),
                    "streamRate": SOUND_RATES.get((b1 >> 2) & 3),
                    "stream16bit": bool(b1 & 2),
                    "streamStereo": bool(b1 & 1),
                    "latencySeek": lat,
                }
        return None

    def define_sound_info(self, cid):
        d = self.defs.get(cid)
        if not d or d[0] != 14:
            return None
        code, off, ln = d
        b0 = self.body[off + 2]
        return {
            "format": SOUND_FORMATS.get((b0 >> 4) & 15, "unknown"),
            "rate": SOUND_RATES.get((b0 >> 2) & 3),
            "is16bit": bool(b0 & 2),
            "stereo": bool(b0 & 1),
            "sampleCount": struct.unpack("<I", self.body[off + 3:off + 7])[0],
            "dataSha256": _sha(self.body[off + 7:off + ln]),
            "dataBytes": ln - 7,
        }

    def edit_text(self, cid):
        """Parse DefineEditText: returns dict with original HTML initial text."""
        d = self.defs.get(cid)
        if not d or d[0] != 37:
            return None
        code, off, ln = d
        b = self.body
        p = off + 2
        bits = b[p] >> 3
        p += (5 + bits * 4 + 7) // 8  # RECT
        f0 = b[p]
        f1 = b[p + 1]
        p += 2
        font_id = None
        font_height = None
        if f0 & 0x01:
            font_id = struct.unpack("<H", b[p:p + 2])[0]
            font_height = struct.unpack("<H", b[p + 2:p + 4])[0]
            p += 4
        color = None
        if f0 & 0x04:
            color = "%08X" % struct.unpack("<I", b[p:p + 4])[0]
            p += 4
        if f0 & 0x02:
            p += 2
        if f1 & 0x20:
            p += 9
        e = b.index(0, p)
        var_name = b[p:e].decode("utf-8", "replace")
        p = e + 1
        text = None
        if f0 & 0x80:
            e = b.index(0, p)
            text = b[p:e].decode("utf-8", "replace")
        return {
            "charId": cid, "varName": var_name, "html": bool(f1 & 0x02),
            "readOnly": bool(f0 & 0x08), "fontId": font_id, "fontHeight": font_height,
            "color": color, "initialText": text,
        }

    def text2_glyphs(self, cid):
        """Parse DefineText2 header (glyph/advance bits + record count). Full glyph
        decoding needs the font code table; handled by index script via DefineFont2."""
        d = self.defs.get(cid)
        if not d or d[0] != 33:
            return None
        return {"charId": cid, "rawSha256": self.tag_sha256(d[1], d[2])}

    def sprite_frames(self, sid):
        return self.sprites.get(sid, {}).get("frames", [])

    def find_named_instances(self, needle):
        """Search every PlaceObject name across main timeline and all sprites."""
        hits = []
        for i, f in enumerate(self.main_frames):
            for pl in f["places"]:
                if pl.get("name") and needle in pl["name"]:
                    hits.append({"where": "main", "frame": i, "charId": pl.get("charId"), "depth": pl.get("depth"), "name": pl["name"]})
        for sid, sp in self.sprites.items():
            for i, f in enumerate(sp["frames"]):
                for pl in f["places"]:
                    if pl.get("name") and needle in pl["name"]:
                        hits.append({"where": "sprite %s" % sid, "frame": i, "charId": pl.get("charId"), "depth": pl.get("depth"), "name": pl["name"]})
        return hits

    def shape_bitmap_refs(self, cid):
        """Bitmap character ids referenced by fills of DefineShape1-4."""
        d = self.defs.get(cid)
        if not d or d[0] not in (2, 22, 32, 83):
            return []
        code, off, ln = d
        b = self.body
        p = off + 2
        ver = {2: 1, 22: 2, 32: 3, 83: 4}[code]
        # shape bounds RECT
        p += (5 + (b[p] >> 3) * 4 + 7) // 8
        if ver == 4:
            # edge bounds RECT + flags UI8
            p += (5 + (b[p] >> 3) * 4 + 7) // 8 + 1
        # FillStyleArray
        count = b[p]
        p += 1
        if count == 0xFF and ver >= 2:
            count = struct.unpack("<H", b[p:p + 2])[0]
            p += 2
        refs = []

        def skip_matrix(q):
            _m, nq = self._read_matrix(q)
            return nq

        for _ in range(count):
            ftype = b[p]
            p += 1
            if ftype == 0x00:
                p += 4 if ver >= 3 else 3
            elif ftype in (0x10, 0x12, 0x13):
                p = skip_matrix(p)
                if ver == 4:
                    gcount = b[p] & 0x0F
                    p += 1
                else:
                    gcount = b[p]
                    p += 1
                p += gcount * (5 if ver >= 3 else 4)
                if ftype == 0x13:
                    p += 2
            elif ftype in (0x40, 0x41, 0x42, 0x43):
                refs.append(struct.unpack("<H", b[p:p + 2])[0])
                p += 2
                p = skip_matrix(p)
            else:
                break
        return refs
