# -*- coding: utf-8 -*-
"""轻量 SWF 扫描器：尺寸 / 标签直方图 / 实例名提取。无需 ffdec。"""
import sys, os, zlib, struct, json
from collections import Counter

SHAPE   = {2,22,32,83,46,84}                 # DefineShape* / DefineMorphShape*
BITMAP  = {6,8,20,21,35,36,90}               # DefineBits* / JPEGTables
SPRITE  = 39
PLACE   = {4,26,70}                          # PlaceObject / 2 / 3
ACTION  = {12,59}                            # DoAction / DoInitAction
SOUND   = {14,17,18,19,75,73,60}             # DefineSound / SoundStream*
TEXT    = {11,33,37}                         # DefineText* / EditText
TAGNAME = {2:'DefineShape',22:'DefineShape2',32:'DefineShape3',83:'DefineShape4',
           46:'DefineMorphShape',84:'DefineMorphShape2',6:'DefineBits',
           20:'DefineBitsLossless',36:'DefineBitsLossless2',21:'DefineBitsJPEG2',
           35:'DefineBitsJPEG3',90:'DefineBitsJPEG4',39:'DefineSprite',
           12:'DoAction',59:'DoInitAction',14:'DefineSound'}

class Bits:
    def __init__(self, data, pos=0):
        self.d = data; self.byte = pos; self.bit = 0
    def u(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | ((self.d[self.byte] >> (7 - self.bit)) & 1)
            self.bit += 1
            if self.bit == 8:
                self.bit = 0; self.byte += 1
        return v
    def s(self, n):
        v = self.u(n)
        if n and (v >> (n - 1)) & 1:
            v -= (1 << n)
        return v
    def align(self):
        if self.bit:
            self.bit = 0; self.byte += 1

def skip_matrix(b):
    if b.u(1):                       # HasScale
        ns = b.u(5); b.u(ns); b.u(ns)
    if b.u(1):                       # HasRotate
        nr = b.u(5); b.u(nr); b.u(nr)
    nt = b.u(5); b.u(nt); b.u(nt)
    b.align()

def skip_cxform(b, alpha):
    add = b.u(1); mul = b.u(1); n = b.u(4)
    fields = 4 if alpha else 3
    if mul:
        for _ in range(fields): b.u(n)
    if add:
        for _ in range(fields): b.u(n)
    b.align()

def read_string(d, pos):
    e = pos
    while e < len(d) and d[e] != 0:
        e += 1
    return d[pos:e].decode('utf-8', 'replace'), e + 1

def parse_tags(d, start, end, hist, names, depth=0):
    p = start
    while p < end - 1:
        hdr = d[p] | (d[p+1] << 8); p += 2
        code = hdr >> 6; ln = hdr & 0x3F
        if ln == 0x3F:
            ln = struct.unpack_from('<I', d, p)[0]; p += 4
        body = p; p += ln
        if code == 0:
            break
        hist[code] = hist.get(code, 0) + 1
        if code == SPRITE:
            parse_tags(d, body + 4, body + ln, hist, names, depth + 1)
        elif code in (26, 70):       # PlaceObject2 / PlaceObject3
            try:
                b = Bits(d, body)
                f = b.u(8)
                hasMove = f & 1; hasChar = (f>>1)&1; hasMat=(f>>2)&1
                hasCx=(f>>3)&1; hasRatio=(f>>4)&1; hasName=(f>>5)&1
                hasClassName = hasImage = 0
                if code == 70:
                    f2 = b.u(8)                       # PlaceObject3 第二标志字节
                    hasClassName = (f2 >> 3) & 1      # bit3 = HasClassName
                    hasImage     = (f2 >> 4) & 1      # bit4 = HasImage
                b.byte += 2          # depth
                if code == 70 and (hasClassName or (hasImage and hasChar)):
                    _, b.byte = read_string(d, b.byte)
                if hasChar:
                    b.byte += 2
                if hasMat:
                    skip_matrix(b)
                if hasCx:
                    skip_cxform(b, True)
                if hasRatio:
                    b.byte += 2
                if hasName:
                    nm, _ = read_string(d, b.byte)
                    if nm:
                        names.add(nm)
            except Exception:
                pass
    return p

def scan(path):
    with open(path, 'rb') as fh:
        raw = fh.read()
    sig = raw[:3]; ver = raw[3]
    if sig == b'CWS':
        body = zlib.decompress(raw[8:])
    elif sig == b'FWS':
        body = raw[8:]
    elif sig == b'ZWS':
        import lzma
        body = lzma.decompress(raw[12:17] + struct.pack('<Q', 0xFFFFFFFFFFFFFFFF) + raw[17:])
    else:
        return {'file': os.path.basename(path), 'error': 'bad-sig'}
    b = Bits(body, 0)
    nb = b.u(5)
    xmin=b.s(nb); xmax=b.s(nb); ymin=b.s(nb); ymax=b.s(nb)
    b.align()
    rate = struct.unpack_from('<H', body, b.byte)[0] / 256.0
    fcount = struct.unpack_from('<H', body, b.byte + 2)[0]
    hist = {}; names = set()
    parse_tags(body, b.byte + 4, len(body), hist, names)
    shapes  = sum(hist.get(c,0) for c in SHAPE)
    bitmaps = sum(hist.get(c,0) for c in BITMAP)
    actions = sum(hist.get(c,0) for c in ACTION)
    return {
        'file': os.path.basename(path),
        'bytes': len(raw),
        'sig': sig.decode('ascii','replace'),
        'ver': ver,
        'w': round((xmax-xmin)/20.0, 1),
        'h': round((ymax-ymin)/20.0, 1),
        'frames': fcount,
        'fps': round(rate,1),
        'shapes': shapes,
        'bitmaps': bitmaps,
        'sprites': hist.get(SPRITE,0),
        'actions': actions,
        'names': sorted(names),
    }


def avm1_container(raw):
    """Strict tag bounds and AVM1 script/linkage inventory for publish verification."""
    limit = 512 * 1024 * 1024
    if len(raw) < 8 or len(raw) > limit:
        raise ValueError("invalid SWF file size")
    signature, version = raw[:3], raw[3]
    declared = struct.unpack_from('<I', raw, 4)[0]
    if not 8 <= declared <= limit:
        raise ValueError("invalid or oversized declared SWF length")
    if signature == b'FWS':
        data = raw[8:]
    elif signature == b'CWS':
        decoder = zlib.decompressobj()
        data = decoder.decompress(raw[8:], declared - 8 + 1)
        if not decoder.eof or decoder.unused_data:
            raise ValueError("incomplete or trailing CWS compressed data")
    elif signature == b'ZWS':
        import lzma
        decoder = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE, memlimit=limit)
        data = decoder.decompress(
            raw[12:17] + struct.pack('<Q', declared - 8) + raw[17:], max_length=declared - 8 + 1
        )
    else:
        raise ValueError(f"invalid SWF signature {signature!r}")
    if len(data) != declared - 8:
        raise ValueError("SWF declared and decompressed lengths differ")

    header = Bits(data)
    rect_bits = header.u(5)
    for _ in range(4):
        header.s(rect_bits)
    header.align()
    actions, exports, imports = Counter(), [], []

    def u16(pos):
        return struct.unpack_from('<H', data, pos)[0]

    def u32(pos):
        return struct.unpack_from('<I', data, pos)[0]

    def string(pos, end):
        stop = data.index(0, pos, end)
        return data[pos:stop].decode('utf-8'), stop + 1

    def action(kind, start, end):
        if start > end:
            raise ValueError(f"{kind} exceeds tag")
        if start < end:
            actions[kind] += 1

    def clip_actions(pos, end, code):
        width = 4 if version >= 6 else 2
        pos += 2 + width  # reserved and aggregate ClipEventFlags
        while pos + width <= end:
            flags = int.from_bytes(data[pos:pos + width], 'little')
            pos += width
            if not flags:
                if pos != end:
                    raise ValueError("trailing data after ClipActions")
                return
            stop = pos + 4 + u32(pos)
            if stop > end:
                raise ValueError("ClipAction exceeds PlaceObject tag")
            action(f"PlaceObject{2 if code == 26 else 3}.ClipAction",
                   pos + 4 + bool(flags & 0x20000), stop)
            pos = stop
        raise ValueError("missing ClipActions terminator")

    def place(pos, end, code):
        flags = data[pos]
        if not flags & 128:
            return
        extra = data[pos + 1] if code in (70, 94) else 0
        if code == 94:
            raise ValueError("PlaceObject4 clip actions are unsupported")
        pos += 4 if code == 70 else 3  # flags and depth
        if extra & 8 or (extra & 16 and flags & 2):
            _, pos = string(pos, end)
        if flags & 2:
            pos += 2
        bits = Bits(data, pos)
        if flags & 4:
            skip_matrix(bits)
        if flags & 8:
            skip_cxform(bits, True)
        pos = bits.byte + (2 if flags & 16 else 0)
        if flags & 32:
            _, pos = string(pos, end)
        if flags & 64:
            pos += 2
        if extra & 1:
            count = data[pos]
            pos += 1
            fixed_filter_sizes = {0: 23, 1: 9, 2: 15, 3: 27, 6: 80}
            for _ in range(count):
                kind = data[pos]
                pos += 1
                if kind in fixed_filter_sizes:
                    pos += fixed_filter_sizes[kind]
                elif kind in (4, 7):
                    pos += 20 + data[pos] * 5
                elif kind == 5:
                    pos += 15 + data[pos] * data[pos + 1] * 4
                else:
                    raise ValueError(f"unknown PlaceObject filter {kind}")
        pos += bool(extra & 2) + bool(extra & 4) + bool(extra & 32) + 4 * bool(extra & 64)
        clip_actions(pos, end, code)

    def button_actions(pos, end, code):
        if code == 7:
            pos += 2  # button ID
            while pos < end and data[pos]:
                bits = Bits(data, pos + 5)
                skip_matrix(bits)
                pos = bits.byte
            action("DefineButton.Action", pos + 1, end)
            return
        start = pos + 3  # ActionOffset is relative to this field
        offset = u16(start)
        if not offset:
            return
        pos = start + offset
        while pos + 4 <= end:
            size = u16(pos)
            stop = pos + size if size else end
            if not pos + 4 <= stop <= end:
                raise ValueError("invalid DefineButton2 action size")
            action("DefineButton2.CondAction", pos + 4, stop)
            if not size:
                return
            pos = stop
        raise ValueError("missing DefineButton2 final action")

    def tags(pos, end, depth=0):
        if depth > 64:
            raise ValueError("SWF sprite nesting exceeds 64")
        while pos + 2 <= end:
            word = u16(pos)
            code, size = word >> 6, word & 63
            pos += 2
            if size == 63:
                size = u32(pos)
                pos += 4
            stop = pos + size
            if stop > end:
                raise ValueError("SWF tag exceeds container")
            if code == 0:
                if size or stop != end:
                    raise ValueError("invalid SWF End tag or trailing data")
                return
            if code == SPRITE:
                tags(pos + 4, stop, depth + 1)
            elif code in ACTION:
                action("DoAction" if code == 12 else "DoInitAction", pos + (2 if code == 59 else 0), stop)
            elif code in (26, 70, 94):
                place(pos, stop, code)
            elif code in (7, 34):
                button_actions(pos, stop, code)
            elif code in (56, 57, 71):
                url = None
                if code != 56:
                    url, pos = string(pos, stop)
                    if code == 71:
                        pos += 2
                count = u16(pos)
                pos += 2
                for _ in range(count):
                    character_id = u16(pos)
                    name, pos = string(pos + 2, stop)
                    item = dict(name=name, characterId=character_id)
                    if url is not None:
                        imports.append(dict(item, url=url))
                    else:
                        exports.append(item)
                if pos != stop:
                    raise ValueError("invalid linkage tag length")
            elif code in (72, 82) or (code == 69 and data[pos] & 8):
                raise ValueError("AVM2 bytecode is outside the AVM1 gate")
            pos = stop
        raise ValueError("missing SWF End tag")

    tags(header.byte + 4, len(data))
    return dict(signature=signature.decode(), version=version, declaredBytes=declared,
                actionBlocks=sum(actions.values()), actionHistogram=dict(actions),
                exports=exports, imports=imports)

if __name__ == '__main__':
    args = sys.argv[1:]
    outpath = None
    if args and args[0] == '-o':
        outpath = args[1]; args = args[2:]
    targets = []
    for arg in args:
        if os.path.isdir(arg):
            for fn in sorted(os.listdir(arg)):
                if fn.lower().endswith('.swf'):
                    targets.append(os.path.join(arg, fn))
        elif arg.lower().endswith('.swf'):
            targets.append(arg)
    out = []
    for t in targets:
        try:
            out.append(scan(t))
        except Exception as e:
            out.append({'file': os.path.basename(t), 'error': repr(e)})
    txt = json.dumps(out, ensure_ascii=False, indent=0)
    if outpath:
        with open(outpath, 'w', encoding='utf-8') as fh:
            fh.write(txt)
        sys.stderr.write('scanned %d -> %s\n' % (len(out), outpath))
    else:
        sys.stdout.buffer.write(txt.encode('utf-8'))
