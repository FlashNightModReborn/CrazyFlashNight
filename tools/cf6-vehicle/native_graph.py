"""Read-only structural gate; actual rendering remains a separate native test."""
from pathlib import Path
import json
import struct

HERE = Path(__file__).resolve().parent


def validate(native, scan):
    data = native.data
    bits = scan.Bits(data)
    width = bits.u(5)
    for _ in range(4):
        bits.s(width)
    bits.align()
    shapes, bitmaps = set(), set()

    def definitions(start, end):
        pos = start
        while pos < end - 1:
            header = struct.unpack_from('<H', data, pos)[0]
            pos += 2
            code, size = header >> 6, header & 63
            if size == 63:
                size = struct.unpack_from('<I', data, pos)[0]
                pos += 4
            if pos + size > end:
                raise ValueError('truncated native graphics tag')
            if code in scan.SHAPE:
                shapes.add(struct.unpack_from('<H', data, pos)[0])
            elif code in scan.BITMAP - {8}:
                bitmaps.add(struct.unpack_from('<H', data, pos)[0])
            elif code == 39:
                definitions(pos + 4, pos + size)
            pos += size
            if code == 0:
                break

    definitions(bits.byte + 4, len(data))
    if not shapes or not bitmaps:
        raise ValueError('native vehicle library is an empty graphics shell')
    manifest = json.loads((HERE/'art-manifest.json').read_text(encoding='utf-8'))
    timelines = json.loads((HERE/'source/art-timelines.json').read_text(encoding='utf-8'))
    by_name = {name:cid for cid,name in native.exports.items()}
    rows = {}
    for source_id,name in manifest['exports'].items():
        cid = by_name.get(name)
        expected = len(timelines[source_id]['frames'])
        actual = native.sprites.get(cid)
        if actual != expected:
            raise ValueError('native public frame count mismatch: '+name)
        closure = native.closure(cid)
        visible = closure & shapes
        if not visible:
            raise ValueError('native public symbol has no reachable shape: '+name)
        rows[name] = {'sourceId':int(source_id),'frames':actual,
                      'closureNodes':len(closure),'reachableShapes':len(visible)}
    return {'shapes':len(shapes),'bitmaps':len(bitmaps),'public':rows,
            'boundary':'structure only; real pixels and production consumer remain required'}
