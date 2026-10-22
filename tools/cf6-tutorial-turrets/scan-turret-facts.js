"use strict";
// tools/cf6-tutorial-turrets/scan-turret-facts.js
// Read-only SWF fact scanner for the CF6 tutorial-turret lane (r13).
// Input: the verified original SWF (crazyflasher6-cn.swf). No writes to the SWF.
// Output: JSON to stdout.
//   node tools/cf6-tutorial-turrets/scan-turret-facts.js <swfPath>
// Reports:
//   - tag code / kind / bounds for watched charIds (turret sprite 1591, its parts,
//     tutorial-room pair 1443/1448, A01 world 1592 parts)
//   - full placement records (depth, charId, name, matrix a/b/c/d/tx/ty in pixels,
//     clipEvents) for sprite 1592 frame 1 (A01 world) and sprite 1499 frame 1
//     (tutorial room world), plus every frame of sprite 1591.
// Matrix decode follows SWF spec: bit7 hasScale, bit6 hasRotateSkew, nbits fields,
// scale fixed 16.16, translate in twips (1/20 px).
const fs = require("fs");
const zlib = require("zlib");
const raw = fs.readFileSync(process.argv[2]);
const sig = raw.toString("ascii", 0, 3);
const body = sig === "FWS" ? raw.subarray(8) : sig === "CWS" ? zlib.inflateSync(raw.subarray(8)) : null;
if (!body) throw new Error("unsupported " + sig);

const TAG_NAMES = {
    0: "End", 1: "ShowFrame", 2: "DefineShape", 9: "SetBackgroundColor",
    20: "DefineBitsLossless", 21: "DefineBitsJPEG2", 22: "DefineShape2",
    26: "PlaceObject2", 32: "DefineShape3", 35: "DefineBitsJPEG3",
    36: "DefineBitsLossless2", 39: "DefineSprite", 43: "FrameLabel",
    46: "DefineMorphShape", 56: "ExportAssets", 69: "FileAttributes",
    70: "PlaceObject3", 73: "DefineFontAlignZones", 76: "SymbolClass",
    82: "DoABC", 83: "DefineShape4", 12: "DoAction", 59: "DoInitAction",
    65: "ScriptLimits", 87: "DefineBinaryData", 88: "DefineFontName"
};

function readRect(buf, off) {
    const bits = buf[off] >> 3;
    const nbits = bits;
    const totalBits = 5 + nbits * 4;
    const byteLen = Math.ceil(totalBits / 8);
    // decode signed values
    let bitPos = off * 8 + 5;
    const vals = [];
    for (let i = 0; i < 4; i++) {
        let v = 0;
        for (let b = 0; b < nbits; b++) {
            const byte = buf[bitPos >> 3];
            const bit = (byte >> (7 - (bitPos & 7))) & 1;
            v = (v << 1) | bit;
            bitPos++;
        }
        if (nbits > 0 && (v & (1 << (nbits - 1)))) v -= (1 << nbits);
        vals.push(v / 20);
    }
    return { rect: vals, next: off + byteLen };
}

function cstr(buf, off) {
    const end = buf.indexOf(0, off);
    return { text: buf.toString("utf8", off, end < 0 ? buf.length : end), next: end + 1 };
}

function readMatrix(buf, off) {
    const b0 = buf[off];
    const hasScale = (b0 & 0x80) !== 0, hasRotate = (b0 & 0x40) !== 0;
    const nbits = (b0 >> 1) & 0x1f;
    const fields = (hasScale ? 2 : 0) + (hasRotate ? 2 : 0) + 2;
    const byteLen = Math.ceil((7 + nbits * fields) / 8);
    let bitPos = off * 8 + 7;
    function readBits(n, signed) {
        let v = 0;
        for (let b = 0; b < n; b++) {
            const byte = buf[bitPos >> 3];
            const bit = (byte >> (7 - (bitPos & 7))) & 1;
            v = (v << 1) | bit;
            bitPos++;
        }
        if (signed && n > 0 && (v & (1 << (n - 1)))) v -= (1 << n);
        return v;
    }
    let a = 1, d = 1, b = 0, c = 0;
    if (hasScale) { a = readBits(nbits, true) / 65536; d = readBits(nbits, true) / 65536; }
    if (hasRotate) { b = readBits(nbits, true) / 65536; c = readBits(nbits, true) / 65536; }
    const tx = readBits(nbits, true) / 20;
    const ty = readBits(nbits, true) / 20;
    return { matrix: [a, b, c, d, tx, ty], next: off + byteLen };
}

function readCxform(buf, off) {
    const b0 = buf[off];
    const hasAdd = (b0 & 0x20) !== 0, hasMul = (b0 & 0x10) !== 0;
    const nbits = b0 & 0x0f;
    return off + Math.ceil((8 + nbits * ((hasAdd ? 4 : 0) + (hasMul ? 4 : 0))) / 8);
}

function parsePlace(buf, off, size, v3) {
    let p = off;
    const flags1 = buf[p++];
    let flags2 = 0;
    // PlaceObject3 ALWAYS carries a second flags byte (unlike PlaceObject2 where
    // clipActions is flags1 bit7). Reading it conditionally desyncs the record.
    if (v3) flags2 = buf[p++];
    // PlaceObject3 flags2: 0x01 filterList, 0x02 blendMode, 0x04 cacheAsBitmap,
    // 0x08 className (or hasImage+hasCharacter), 0x10 hasImage.
    // hasClipActions stays flags1 bit7 in both versions.
    const hasClipActions = (flags1 & 0x80) !== 0;
    const depth = buf.readUInt16LE(p); p += 2;
    let charId = null, name = null, matrix = null, className = null;
    if (v3 && ((flags2 & 0x08) || ((flags2 & 0x10) && (flags1 & 0x02)))) {
        const s = cstr(buf, p); className = s.text; p = s.next;
    }
    if (flags1 & 0x02) { charId = buf.readUInt16LE(p); p += 2; }
    if (flags1 & 0x04) { const m = readMatrix(buf, p); matrix = m.matrix; p = m.next; }
    if (flags1 & 0x08) p = readCxform(buf, p);
    if (flags1 & 0x10) p += 2;
    if (flags1 & 0x20) { const s = cstr(buf, p); name = s.text; p = s.next; }
    if (flags1 & 0x40) p += 2;
    if (v3 && (flags2 & 0x01)) return { depth, charId, name, matrix, className, clipEvents: ["<filters:truncated>"] };
    if (v3 && (flags2 & 0x02)) p += 1;
    if (v3 && (flags2 & 0x04)) p += 1;
    const clipEvents = [];
    if (hasClipActions) {
        p += 2;
        p += 4; // all event flags
        const names = [[0x1, "load"], [0x2, "enterFrame"], [0x4, "unload"], [0x8, "mouseMove"], [0x10, "mouseDown"], [0x20, "mouseUp"], [0x40, "keyDown"], [0x80, "keyUp"], [0x100, "data"], [0x200, "keyPress"], [0x400, "dragOut"], [0x800, "dragOver"], [0x1000, "rollOut"], [0x2000, "rollOver"], [0x4000, "releaseOutside"], [0x8000, "release"], [0x10000, "press"]];
        while (p + 8 <= off + size) {
            const flags = buf.readUInt32LE(p); p += 4;
            if (flags === 0) break;
            const sz = buf.readUInt32LE(p); p += 4;
            if (flags & 0x200) p += 1;
            for (const [bit, nm] of names) if (flags & bit) clipEvents.push(nm);
            p += sz;
        }
    }
    return { depth, charId, name, matrix, clipEvents };
}

function parseTimeline(start, end) {
    let off = start;
    const frames = [];
    let cur = { places: [], doAction: 0, label: null };
    frames.push(cur);
    while (off < end) {
        const header = body.readUInt16LE(off); off += 2;
        let code = header >> 6, size = header & 63;
        if (size === 63) { size = body.readUInt32LE(off); off += 4; }
        if (off + size > body.length) break;
        if (code === 43) { cur.label = cstr(body, off).text; }
        else if (code === 26) { try { cur.places.push(parsePlace(body, off, size, false)); } catch (e) { cur.places.push({ parseError: String(e) }); } }
        else if (code === 70) { try { cur.places.push(parsePlace(body, off, size, true)); } catch (e) { cur.places.push({ parseError: String(e) }); } }
        else if (code === 12 || code === 59) { cur.doAction++; }
        else if (code === 1) { cur = { places: [], doAction: 0, label: null }; frames.push(cur); }
        else if (code === 0) { break; }
        off += size;
    }
    return frames;
}

const WATCH = [1443, 1448, 1591, 359, 506, 13824, 1584, 1419, 1499, 1592, 1497, 1498, 1551];
const watchHits = {};
const spriteStarts = {};

let off = readRect(body, 8).next + 4; // skip RECT + fps + frameCount
while (off < body.length) {
    const tagStart = off;
    const header = body.readUInt16LE(off); off += 2;
    let code = header >> 6, size = header & 63;
    if (size === 63) { size = body.readUInt32LE(off); off += 4; }
    if (off + size > body.length) break;
    // definition tags carry charId as first u16
    const defTags = [2, 22, 32, 83, 39, 46, 20, 21, 35, 36, 87];
    if (defTags.indexOf(code) >= 0) {
        const id = body.readUInt16LE(off);
        if (WATCH.indexOf(id) >= 0) {
            const hit = { tagCode: code, tag: TAG_NAMES[code] || String(code), offset: tagStart, length: size };
            if (code === 2 || code === 22 || code === 32 || code === 83) {
                hit.boundsPx = readRect(body, off + 2).rect; // [xmin,xmax,ymin,ymax]
            }
            watchHits[id] = hit;
        }
        if (code === 39) spriteStarts[id] = { start: off + 4, end: off + size, fc: body.readUInt16LE(off + 2) };
    } else if (code === 39) {
        // unreachable (39 in defTags) — kept for clarity
    }
    if (code === 39) { /* handled above */ }
    off += size;
}
// second pass for sprites if missed (DefineSprite code 39 was in defTags)
for (const id of [1592, 1499, 1591]) {
    if (!spriteStarts[id]) {
        // rescan quickly
    }
}

const out = { watch: watchHits, sprites: {} };
for (const id of [1592, 1499, 1591]) {
    const s = spriteStarts[id];
    if (!s) { out.sprites[id] = null; continue; }
    const frames = parseTimeline(s.start, s.end);
    if (id === 1591) {
        out.sprites[id] = { frameCount: s.fc, frames: frames.map((f, i) => ({ frame: i + 1, label: f.label, doAction: f.doAction, places: f.places })).filter(f => f.places.length || f.doAction || f.label) };
    } else {
        out.sprites[id] = { frameCount: s.fc, frame1: frames[0] };
    }
}
console.log(JSON.stringify(out, null, 1));
