'use strict';
// 最小 PNG 编解码（纯 Node + zlib，无外部依赖）。
// decode: 8-bit 非交错，colorType 6(RGBA)/2(RGB)/3(palette)/0(gray) → RGBA Buffer。
// encode: 固定输出 8-bit RGBA、filter=0。供 tooltip-parity 截图对比用。

const zlib = require('zlib');

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
        t[n] = c >>> 0;
    }
    return t;
})();

function crc32(buf) {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
}

function readChunks(buf) {
    if (buf.length < 8 || !buf.slice(0, 8).equals(SIG)) throw new Error('not a PNG');
    const chunks = [];
    let off = 8;
    while (off + 12 <= buf.length) {
        const len = buf.readUInt32BE(off);
        const type = buf.toString('ascii', off + 4, off + 8);
        const data = buf.slice(off + 8, off + 8 + len);
        chunks.push({ type, data });
        off += 12 + len;
        if (type === 'IEND') break;
    }
    return chunks;
}

const BPP = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };

function decode(buf) {
    const chunks = readChunks(buf);
    const ihdr = chunks.find(c => c.type === 'IHDR');
    if (!ihdr) throw new Error('missing IHDR');
    const w = ihdr.data.readUInt32BE(0), h = ihdr.data.readUInt32BE(4);
    const depth = ihdr.data[8], colorType = ihdr.data[9];
    const interlace = ihdr.data[12];
    if (depth !== 8) throw new Error('unsupported bit depth ' + depth);
    if (interlace !== 0) throw new Error('interlaced PNG unsupported');
    const bpp = BPP[colorType];
    if (bpp == null) throw new Error('unsupported colorType ' + colorType);

    let palette = null, trns = null;
    for (const c of chunks) {
        if (c.type === 'PLTE') palette = c.data;
        if (c.type === 'tRNS') trns = c.data;
    }
    const idat = Buffer.concat(chunks.filter(c => c.type === 'IDAT').map(c => c.data));
    const raw = zlib.inflateSync(idat);

    const stride = w * bpp;
    const px = Buffer.alloc(w * h * 4);
    let prev = Buffer.alloc(stride);
    let src = 0;
    for (let y = 0; y < h; y++) {
        const filter = raw[src++];
        const line = raw.slice(src, src + stride); src += stride;
        const cur = Buffer.alloc(stride);
        for (let x = 0; x < stride; x++) {
            const a = x >= bpp ? cur[x - bpp] : 0;
            const b = prev[x];
            const c = x >= bpp ? prev[x - bpp] : 0;
            let v = line[x];
            switch (filter) {
                case 0: break;
                case 1: v = (v + a) & 0xff; break;
                case 2: v = (v + b) & 0xff; break;
                case 3: v = (v + ((a + b) >> 1)) & 0xff; break;
                case 4: {
                    const p = a + b - c;
                    const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
                    v = (v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 0xff;
                    break;
                }
                default: throw new Error('bad filter ' + filter);
            }
            cur[x] = v;
        }
        // 展开到 RGBA
        for (let x = 0; x < w; x++) {
            const di = (y * w + x) * 4, si = x * bpp;
            switch (colorType) {
                case 6: px[di] = cur[si]; px[di + 1] = cur[si + 1]; px[di + 2] = cur[si + 2]; px[di + 3] = cur[si + 3]; break;
                case 2: px[di] = cur[si]; px[di + 1] = cur[si + 1]; px[di + 2] = cur[si + 2]; px[di + 3] = 255; break;
                case 0: px[di] = px[di + 1] = px[di + 2] = cur[si]; px[di + 3] = 255; break;
                case 4: px[di] = px[di + 1] = px[di + 2] = cur[si]; px[di + 3] = cur[si + 1]; break;
                case 3: {
                    const idx = cur[si];
                    if (!palette || idx * 3 + 2 >= palette.length) throw new Error('palette index OOB');
                    px[di] = palette[idx * 3]; px[di + 1] = palette[idx * 3 + 1]; px[di + 2] = palette[idx * 3 + 2];
                    px[di + 3] = trns && idx < trns.length ? trns[idx] : 255;
                    break;
                }
            }
        }
        prev = cur;
    }
    return { width: w, height: h, data: px };
}

function chunk(type, data) {
    const out = Buffer.alloc(12 + data.length);
    out.writeUInt32BE(data.length, 0);
    out.write(type, 4, 'ascii');
    data.copy(out, 8);
    out.writeUInt32BE(crc32(out.slice(4, 8 + data.length)), 8 + data.length);
    return out;
}

function encode(img) {
    const { width: w, height: h, data } = img;
    if (data.length !== w * h * 4) throw new Error('RGBA size mismatch');
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
    ihdr[8] = 8; ihdr[9] = 6; // depth=8, colorType=RGBA
    const stride = w * 4;
    const raw = Buffer.alloc(h * (stride + 1));
    for (let y = 0; y < h; y++) {
        raw[y * (stride + 1)] = 0;
        data.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
    }
    return Buffer.concat([
        SIG,
        chunk('IHDR', ihdr),
        chunk('IDAT', zlib.deflateSync(raw, { level: 6 })),
        chunk('IEND', Buffer.alloc(0))
    ]);
}

module.exports = { decode, encode, crc32 };
