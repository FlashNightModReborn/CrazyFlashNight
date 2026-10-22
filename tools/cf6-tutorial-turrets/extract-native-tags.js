"use strict";
// tools/cf6-tutorial-turrets/extract-native-tags.js
// Read-only on the SWF. Extracts the RAW tag bytes (header + body, verbatim) of
// the CF6 A01 auto-turret closure into the Codex source-draft directory, with a
// sha256 manifest. No SWF is generated or modified; CS6 assembly is the
// integrator's job (see 装配说明.md next to the output).
//
//   node tools/cf6-tutorial-turrets/extract-native-tags.js <swfPath> <outDir>
//
// Closure roots: turret sprite 1591; gameplay reference assets 356/1108.
// Sprite bodies are scanned for PlaceObject2/3 charIds; DefineShape1/2/3/4 fill
// styles are scanned for bitmap-fill references (types 0x40-0x43).
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const crypto = require("crypto");

const EXPECT_SHA256 = "b52af10e2dda43332e0b2ffb9549d2fad474f298b9f6c67d848ffc33ff589b01";
// Closure root: turret sprite 1591 only. The original bullet (356) and map-hit
// effect (1108) are NOT extracted: CF7 already ships equivalent linkages
// ("普通子弹" / "无声火花", data/items/asset_source_map.xml), so the migration
// reuses those instead of adding duplicate art.
const ROOTS = [1591];

const raw = fs.readFileSync(process.argv[2]);
const outDir = process.argv[3];
const sha = crypto.createHash("sha256").update(raw).digest("hex");
if (sha !== EXPECT_SHA256) throw new Error("swf sha256 mismatch: " + sha);
const body = raw.toString("ascii", 0, 3) === "CWS" ? zlib.inflateSync(raw.subarray(8)) : raw.subarray(8);

const TAG_NAMES = {2:"DefineShape",20:"DefineBitsLossless",21:"DefineBitsJPEG2",22:"DefineShape2",
    32:"DefineShape3",35:"DefineBitsJPEG3",36:"DefineBitsLossless2",39:"DefineSprite",83:"DefineShape4"};

function rectEnd(buf, off) { return off + Math.ceil((5 + (buf[off] >> 3) * 4) / 8); }
function readMatrixEnd(buf, off) {
    const b0 = buf[off];
    const fields = ((b0 & 0x80) ? 2 : 0) + ((b0 & 0x40) ? 2 : 0) + 2;
    const nbits = (b0 >> 1) & 0x1f;
    return off + Math.ceil((7 + nbits * fields) / 8);
}
function readCxformEnd(buf, off) {
    const b0 = buf[off];
    const nbits = b0 & 0x0f;
    return off + Math.ceil((8 + nbits * (((b0 & 0x20) ? 4 : 0) + ((b0 & 0x10) ? 4 : 0))) / 8);
}

// collect top-level definition tags: charId -> {code, start(header), end}
const defs = {};
let off = rectEnd(body, 8) + 4;
while (off < body.length) {
    const tagStart = off;
    const header = body.readUInt16LE(off); off += 2;
    let code = header >> 6, size = header & 63;
    if (size === 63) { size = body.readUInt32LE(off); off += 4; }
    if (off + size > body.length) break;
    if (TAG_NAMES[code] !== undefined) {
        const id = body.readUInt16LE(off);
        defs[id] = { code, start: tagStart, dataStart: off, end: off + size };
    }
    off += size;
}

// scan a sprite body for placed charIds (PlaceObject2=26, PlaceObject3=70)
function spriteDeps(dataStart, end) {
    const deps = [];
    let p = dataStart + 4; // id + frameCount
    while (p < end) {
        const header = body.readUInt16LE(p); p += 2;
        let code = header >> 6, size = header & 63;
        if (size === 63) { size = body.readUInt32LE(p); p += 4; }
        if (p + size > end) break;
        if (code === 26 || code === 70) {
            try {
                let q = p;
                const flags1 = body[q++];
                if (code === 70) q++; // flags2 always present in PlaceObject3
                q += 2; // depth
                if (code === 70 && ((body[p + 1] & 0x08) || ((body[p + 1] & 0x10) && (flags1 & 0x02)))) {
                    q = body.indexOf(0, q) + 1; // className
                }
                if (flags1 & 0x02) { deps.push(body.readUInt16LE(q)); }
            } catch (e) { /* keep going; deps are best-effort for the closure walk */ }
        }
        p += size;
    }
    return deps;
}

// scan a DefineShape1/2/3/4 body for bitmap-fill charIds (fill types 0x40..0x43)
function shapeDeps(code, dataStart, end) {
    const deps = [];
    let p = dataStart + 2; // id
    p = rectEnd(body, p);  // bounds
    if (code === 83) p = rectEnd(body, p); // edge bounds
    if (code === 83) p += 1;               // usesWinding/NonZero flags byte
    // fill styles
    let fillCount = body[p++];
    if (fillCount === 0xff && code !== 2) { fillCount = body.readUInt16LE(p); p += 2; }
    for (let i = 0; i < fillCount && p < end; i++) {
        const type = body[p++];
        if (type === 0x00) { p += (code === 32 || code === 83) ? 4 : 3; }
        else if (type === 0x10 || type === 0x12) {
            p = readMatrixEnd(body, p);
            let n = body[p++] & 0x0f;
            for (let g = 0; g < n; g++) { p += 1 + ((code === 32 || code === 83) ? 4 : 3); }
            if (type === 0x12) p += 2;
        } else if (type >= 0x40 && type <= 0x43) {
            deps.push(body.readUInt16LE(p)); p += 2;
            p = readMatrixEnd(body, p);
        } else break;
    }
    return deps;
}

const closure = {};
const queue = ROOTS.slice();
while (queue.length) {
    const id = queue.shift();
    if (closure[id] !== undefined) continue;
    const d = defs[id];
    if (!d) { closure[id] = null; continue; }
    closure[id] = d;
    let deps = [];
    if (d.code === 39) deps = spriteDeps(d.dataStart, d.end);
    else deps = shapeDeps(d.code, d.dataStart, d.end);
    for (const dep of deps) if (closure[dep] === undefined) queue.push(dep);
}

fs.mkdirSync(outDir, { recursive: true });
const tagDir = path.join(outDir, "raw-tags");
fs.mkdirSync(tagDir, { recursive: true });
const manifest = { schema: "cf6-turret-native-tags.v1", sourceSwfSha256: sha, tags: {} };
for (const id of Object.keys(closure).sort((a, b) => a - b)) {
    const d = closure[id];
    if (!d) { manifest.tags[id] = { missing: true }; continue; }
    const bytes = body.subarray(d.start, d.end);
    const name = "tag-" + id + "-" + (TAG_NAMES[d.code] || d.code) + ".bin";
    fs.writeFileSync(path.join(tagDir, name), bytes);
    manifest.tags[id] = {
        file: "raw-tags/" + name, tag: TAG_NAMES[d.code] || String(d.code),
        offset: d.start, length: d.end - d.start,
        sha256: crypto.createHash("sha256").update(bytes).digest("hex")
    };
}
fs.writeFileSync(path.join(outDir, "manifest.json"), JSON.stringify(manifest, null, 1) + "\n");
console.log(JSON.stringify({ closure: Object.keys(closure).map(Number).sort((a, b) => a - b), outDir }));
