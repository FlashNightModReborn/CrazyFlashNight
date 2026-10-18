"""Read CF6 sound provenance from an unmodified SWF; never writes SWF bytes."""
from pathlib import Path
import hashlib
import importlib.util
import struct
import zlib

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('cf6_swf_scan', ROOT/'tools/swf-audit/swfscan.py')
scan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scan)


class Source:
    def __init__(self, path):
        self.path = Path(path)
        raw = self.path.read_bytes()
        self.sha256 = hashlib.sha256(raw).hexdigest()
        if raw[:3] == b'CWS':
            self.data = zlib.decompress(raw[8:])
        elif raw[:3] == b'FWS':
            self.data = raw[8:]
        else:
            raise ValueError('Expected an ordinary FWS/CWS source')
        if len(self.data)+8 != struct.unpack_from('<I', raw, 4)[0]:
            raise ValueError('SWF length mismatch')
        bits = scan.Bits(self.data)
        n = bits.u(5)
        for _ in range(4):
            bits.s(n)
        bits.align()
        self.fps = struct.unpack_from('<H', self.data, bits.byte)[0]/256
        self.sounds, self.sprites, self.exports, self.events, self.children = {}, {}, {}, [], {}
        self._walk(bits.byte+4, len(self.data), 0)

    def _walk(self, start, end, owner):
        pos, frame = start, 1
        self.children.setdefault(owner, set())
        while pos < end-1:
            header = struct.unpack_from('<H', self.data, pos)[0]
            pos += 2
            code, size = header >> 6, header & 63
            if size == 63:
                size = struct.unpack_from('<I', self.data, pos)[0]
                pos += 4
            if pos+size > end:
                raise ValueError('Truncated SWF tag')
            body = self.data[pos:pos+size]
            if code == 14:
                cid, flags, count = struct.unpack_from('<HBI', body)
                self.sounds[cid] = {'codec':flags >> 4, 'rate':[5512,11025,22050,44100][(flags >> 2)&3],
                    'bits':16 if flags&2 else 8, 'channels':2 if flags&1 else 1,
                    'sampleCount':count, 'body':body}
            elif code == 15:
                cid = struct.unpack_from('<H', body)[0]
                flags, q = body[2], 3
                row = {'spriteId':owner, 'frame':frame, 'soundId':cid,
                    'syncStop':bool(flags&32), 'syncNoMultiple':bool(flags&16)}
                for flag, key, fmt, width in ((1,'inPoint','<I',4),(2,'outPoint','<I',4),(4,'loopCount','<H',2)):
                    if flags&flag:
                        row[key] = struct.unpack_from(fmt, body, q)[0]
                        q += width
                if flags&8:
                    count = body[q]
                    q += 1
                    row['envelope'] = []
                    for _ in range(count):
                        point, left, right = struct.unpack_from('<IHH', body, q)
                        row['envelope'].append({'position44':point,'left':left,'right':right})
                        q += 8
                if q != len(body):
                    raise ValueError('Unconsumed SoundInfo bytes')
                self.events.append(row)
            elif code == 39:
                cid, count = struct.unpack_from('<HH', body)
                self.sprites[cid] = count
                self._walk(pos+4, pos+size, cid)
            elif code in (4,26,70):
                if code == 4:
                    self.children[owner].add(struct.unpack_from('<H', body)[0])
                else:
                    flags, q = body[0], 3
                    if code == 70:
                        flags2, q = body[1], 4
                        if flags2&8 or (flags2&16 and flags&2):
                            _, q = scan.read_string(body,q)
                    if flags&2:
                        self.children[owner].add(struct.unpack_from('<H', body, q)[0])
            elif code == 56:
                q = 2
                for _ in range(struct.unpack_from('<H', body)[0]):
                    cid = struct.unpack_from('<H', body, q)[0]
                    name, q = scan.read_string(body,q+2)
                    self.exports[cid] = name
            pos += size
            if code == 0:
                break
            if code == 1:
                frame += 1

    def closure(self, root):
        pending, found = [root], set()
        while pending:
            cid = pending.pop()
            if cid not in found:
                found.add(cid)
                pending.extend(self.children.get(cid, ()))
        return found

    def sound_payload(self, cid):
        item = self.sounds[cid]
        if item['codec'] != 2:
            raise ValueError('Only lossless extraction of original MP3 is supported here')
        return item['body'][9:]

    def sound_metadata(self, cid):
        row = {key:value for key,value in self.sounds[cid].items() if key != 'body'}
        row.update(soundId=cid, linkage=self.exports.get(cid),
            bodySha256=hashlib.sha256(self.sounds[cid]['body']).hexdigest())
        if row['codec'] == 2:
            payload = self.sound_payload(cid)
            row.update(mp3Bytes=len(payload),mp3Sha256=hashlib.sha256(payload).hexdigest())
        return row
