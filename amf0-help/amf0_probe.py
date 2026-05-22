# -*- coding: utf-8 -*-
"""
Independent AMF0 / SOL decoder built from the spec ALONE — no flash-lso.

Purpose: empirically determine the AMF0 Reference (0x07) index base in
real Flash-Player-written .sol files.

Reference table policy (AMF0 spec §2.9, also how every known decoder works):
  - A complex object (Object 0x03, ECMA-Array 0x08, Strict-Array 0x0A,
    Typed-Object 0x10) is appended to the table the moment its marker is
    read, BEFORE its members are decoded (so self-reference works).
  - Simple values (Number/Bool/String/Null/Undefined/Date/...) and
    Reference markers themselves never advance the table.

The decoder records, for every Reference marker, the raw u16 it carried and
the structural path where it appeared. It does NOT pre-decide a base; it
reports the raw numbers so the base can be read off the data.
"""
import struct
import sys
import json

class Ref:
    __slots__ = ("raw", "path", "offset")
    def __init__(self, raw, path, offset):
        self.raw = raw
        self.path = path
        self.offset = offset
    def __repr__(self):
        return "Ref(%d)" % self.raw

class Decoder:
    def __init__(self, data, body_start):
        self.d = data
        self.p = body_start
        self.table = []          # 0-based: every complex object in DFS pre-order
        self.table_info = []     # parallel: (kind, summary)
        self.table_path = []     # parallel: the path where this entry was fully encoded
        self.refs = []           # list of Ref
        self.obj_id = {}         # id(decoded-python-container) -> table index

    def u8(self):
        v = self.d[self.p]; self.p += 1; return v
    def u16(self):
        v = struct.unpack_from(">H", self.d, self.p)[0]; self.p += 2; return v
    def u32(self):
        v = struct.unpack_from(">I", self.d, self.p)[0]; self.p += 4; return v
    def s16(self):
        v = struct.unpack_from(">h", self.d, self.p)[0]; self.p += 2; return v
    def f64(self):
        v = struct.unpack_from(">d", self.d, self.p)[0]; self.p += 8; return v
    def amf_string(self):
        n = self.u16()
        s = self.d[self.p:self.p+n]; self.p += n
        return s.decode("utf-8", "replace")
    def amf_long_string(self):
        n = self.u32()
        s = self.d[self.p:self.p+n]; self.p += n
        return s.decode("utf-8", "replace")

    def register(self, kind, summary, path):
        idx = len(self.table)
        self.table.append(None)
        self.table_info.append((kind, summary))
        self.table_path.append(path)
        return idx

    def value(self, path):
        marker_off = self.p
        m = self.u8()
        if m == 0x00:                       # Number
            return self.f64()
        if m == 0x01:                       # Boolean
            return bool(self.u8())
        if m == 0x02:                       # String
            return self.amf_string()
        if m == 0x03:                       # Object
            idx = self.register("Object", "", path)
            obj = {}
            keys = []
            while True:
                name = self.amf_string()
                if len(name) == 0:
                    end = self.u8()
                    assert end == 0x09, "object-end expected, got %02x at %d" % (end, self.p-1)
                    break
                obj[name] = self.value(path + "." + name)
                keys.append(name)
            self.table[idx] = obj
            self.obj_id[id(obj)] = idx
            self.table_info[idx] = ("Object", ",".join(keys[:4]))
            return obj
        if m == 0x05:                       # Null
            return None
        if m == 0x06:                       # Undefined
            return "<undefined>"
        if m == 0x07:                       # Reference
            raw = self.u16()
            r = Ref(raw, path, marker_off)
            self.refs.append(r)
            return r
        if m == 0x08:                       # ECMA-Array
            idx = self.register("ECMAArray", "", path)
            count = self.u32()
            obj = {}
            keys = []
            while True:
                name = self.amf_string()
                if len(name) == 0:
                    end = self.u8()
                    assert end == 0x09, "ecma-end expected, got %02x at %d" % (end, self.p-1)
                    break
                obj[name] = self.value(path + "." + name)
                keys.append(name)
            self.table[idx] = obj
            self.obj_id[id(obj)] = idx
            self.table_info[idx] = ("ECMAArray", "count=%d keys=%s" % (count, ",".join(keys[:4])))
            return ("ECMA", count, obj)
        if m == 0x0A:                       # Strict-Array
            idx = self.register("StrictArray", "", path)
            count = self.u32()
            arr = []
            self.table[idx] = arr
            for i in range(count):
                arr.append(self.value(path + "[%d]" % i))
            self.obj_id[id(arr)] = idx
            self.table_info[idx] = ("StrictArray", "count=%d" % count)
            return arr
        if m == 0x0B:                       # Date
            ts = self.f64(); tz = self.s16()
            return ("Date", ts, tz)
        if m == 0x0C:                       # Long string
            return self.amf_long_string()
        if m == 0x0D:                       # Unsupported
            return "<unsupported>"
        if m == 0x0F:                       # XML
            return ("XML", self.amf_long_string())
        if m == 0x10:                       # Typed object
            cls = self.amf_string()
            idx = self.register("Typed:" + cls, "", path)
            obj = {"__class__": cls}
            keys = []
            while True:
                name = self.amf_string()
                if len(name) == 0:
                    end = self.u8()
                    assert end == 0x09
                    break
                obj[name] = self.value(path + "." + name)
                keys.append(name)
            self.table[idx] = obj
            self.obj_id[id(obj)] = idx
            self.table_info[idx] = ("Typed:" + cls, ",".join(keys[:4]))
            return obj
        raise ValueError("unknown AMF0 marker 0x%02x at offset %d" % (m, marker_off))

    def parse_body(self, body_end):
        root = {}
        order = []
        while self.p < body_end - 1:
            # body element: <u16 name><value><u8 0x00 trailer>
            name = self.amf_string()
            v = self.value(name)
            trailer = self.u8()
            root[name] = v
            order.append((name, trailer))
        return root, order


def parse_sol(path):
    data = open(path, "rb").read()
    assert data[0:2] == b"\x00\xbf", "bad signature"
    length = struct.unpack(">I", data[2:6])[0]
    assert data[6:10] == b"TCSO", "bad TCSO"
    # 6 bytes: 00 04 00 00 00 00
    pos = 16
    namelen = struct.unpack(">H", data[pos:pos+2])[0]; pos += 2
    so_name = data[pos:pos+namelen].decode("utf-8", "replace"); pos += namelen
    amf_version = struct.unpack(">I", data[pos:pos+4])[0]; pos += 4
    body_start = pos
    body_end = 6 + length
    return data, so_name, amf_version, body_start, body_end


def main():
    path = sys.argv[1]
    data, so_name, amf_version, body_start, body_end = parse_sol(path)
    print("=== SOL header ===")
    print("file bytes      :", len(data))
    print("SharedObject    :", repr(so_name))
    print("AMF version     :", amf_version, "(0=AMF0, 3=AMF3)")
    print("body offset     :", body_start, "..", body_end)
    print()

    dec = Decoder(data, body_start)
    root, order = dec.parse_body(body_end)

    print("=== top-level body keys (in file order) ===")
    for i, (name, trailer) in enumerate(order):
        v = root[name]
        if isinstance(v, Ref):
            kind = "Reference(raw=%d)" % v.raw
        elif isinstance(v, dict):
            kind = "Object"
        elif isinstance(v, tuple) and v and v[0] == "ECMA":
            kind = "ECMAArray(count=%d)" % v[1]
        elif isinstance(v, list):
            kind = "StrictArray"
        else:
            kind = type(v).__name__
        print("  [%2d] %-28s -> %s" % (i, repr(name), kind))
    print()

    print("=== complex-object reference table (0-based, DFS pre-order) ===")
    print("total entries:", len(dec.table))
    for i in range(min(len(dec.table), 30)):
        kind, summ = dec.table_info[i]
        print("  table[%3d] %-12s %s" % (i, kind, summ))
    if len(dec.table) > 30:
        print("  ... (%d more)" % (len(dec.table) - 30))
    print()

    print("=== every Reference marker found (%d total) ===" % len(dec.refs))
    for r in dec.refs:
        # what does raw point to under each base hypothesis? show DECODE PATH
        def show(idx):
            if 0 <= idx < len(dec.table):
                k, s = dec.table_info[idx]
                return "table[%d] %-11s path=%s {%s}" % (idx, k, dec.table_path[idx], s)
            return "table[%d] <out-of-range>" % idx
        print("  offset=%-6d raw=%-4d  at-path=%s" % (r.offset, r.raw, r.path))
        print("       base-0 (spec): %s" % show(r.raw))
        print("       base-1 (raw-1): %s" % show(r.raw - 1))
    print()

    # ── DECISIVE CROSS-CHECK ──────────────────────────────────────────────
    # A dual-write Reference at top-level key K must point at the object that
    # was fully encoded at a nested path whose LEAF name == K. Find that
    # nested object's spec-0-based table index purely structurally, then see
    # which base (raw==idx vs raw==idx+1) Flash actually used.
    print("=== DECISIVE: structural target vs raw reference value ===")
    leaf_to_indices = {}
    for i, pth in enumerate(dec.table_path):
        leaf = pth.rsplit(".", 1)[-1].rsplit("[", 1)[0]
        leaf_to_indices.setdefault(leaf, []).append(i)
    verdict = []
    for r in dec.refs:
        leaf = r.path.rsplit(".", 1)[-1]
        # candidate nested objects sharing this leaf name, excluding the ref site
        cands = [i for i in leaf_to_indices.get(leaf, []) if dec.table_path[i] != r.path]
        line = "  ref at top-level %-24s raw=%d" % (repr(r.path), r.raw)
        if len(cands) == 1:
            idx = cands[0]
            off = r.raw - idx
            line += " | nested twin at table[%d] (%s) | raw-idx offset = %+d" % (
                idx, dec.table_path[idx], off)
            verdict.append(off)
        else:
            line += " | %d nested-name candidates %s (ambiguous)" % (len(cands), cands)
        print(line)
    print()
    if verdict:
        if all(o == verdict[0] for o in verdict):
            print(">>> ALL %d dual-write references share a CONSTANT offset of %+d"
                  % (len(verdict), verdict[0]))
            print(">>> meaning: file value = (spec 0-based index) %+d" % verdict[0])
        else:
            print(">>> offsets are NOT constant: %s" % verdict)
    print()

    # write a json dump of the table-info for cross checks
    out = {
        "table": [{"i": i, "kind": dec.table_info[i][0], "summary": dec.table_info[i][1]}
                  for i in range(len(dec.table))],
        "refs": [{"raw": r.raw, "path": r.path, "offset": r.offset} for r in dec.refs],
    }
    open(path + ".probe.json", "w", encoding="utf-8").write(
        json.dumps(out, ensure_ascii=False, indent=1))
    print("wrote", path + ".probe.json")


if __name__ == "__main__":
    main()
