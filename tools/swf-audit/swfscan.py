# -*- coding: utf-8 -*-
"""轻量 SWF 扫描器：尺寸 / 标签直方图 / 实例名提取。无需 ffdec。"""
import sys, os, zlib, struct, json

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
