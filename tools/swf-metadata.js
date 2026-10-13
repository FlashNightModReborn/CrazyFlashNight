"use strict";

// Shared, content-addressed SWF metadata. No runtime hooks and no mutable verdict cache.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const crypto = require("crypto");
const digest = data => crypto.createHash("sha256").update(data).digest("hex");
// Parser edits invalidate cached metadata automatically; policy verdicts are always recomputed.
const VERSION = "1-" + digest(fs.readFileSync(__filename)).slice(0, 16);

function parseSwf(raw) {
    if (raw.length < 12) throw new Error("Truncated SWF header");
    const signature = raw.toString("ascii", 0, 3);
    const body = signature === "FWS" ? raw.subarray(8) :
        signature === "CWS" ? zlib.inflateSync(raw.subarray(8)) : null;
    if (!body) throw new Error("Unsupported SWF signature: " + signature);
    if (body.length + 8 !== raw.readUInt32LE(4)) throw new Error("SWF length mismatch");
    const classes = [], imports = [], functions = [], exports = [], inits = new Map(), sprites = new Set();
    function requireBytes(buf, off, size) {
        if (off < 0 || size < 0 || off + size > buf.length) throw new Error("Truncated SWF record");
    }
    function str(buf, off) {
        const end = buf.indexOf(0, off);
        if (end < 0) throw new Error("Unterminated SWF string");
        return { text: buf.toString("utf8", off, end), next: end + 1 };
    }
    function actions(buf, owner) {
        let off = 0;
        while (off < buf.length) {
            const code = buf[off++];
            if (code === 0) return;
            if (code < 128) continue;
            requireBytes(buf, off, 2);
            const size = buf.readUInt16LE(off); off += 2;
            requireBytes(buf, off, size);
            const rec = buf.subarray(off, off + size); off += size;
            if (code !== 0x8e && code !== 0x9b) continue;
            const name = str(rec, 0); let p = name.next;
            requireBytes(rec, p, code === 0x8e ? 5 : 2);
            const count = rec.readUInt16LE(p); p += code === 0x8e ? 5 : 2;
            for (let i = 0; i < count; i++) {
                if (code === 0x8e) { requireBytes(rec, p, 1); p++; }
                p = str(rec, p).next;
            }
            requireBytes(rec, p, 2);
            const codeSize = rec.readUInt16LE(p);
            requireBytes(buf, off, codeSize);
            functions.push({ owner, type: code === 0x8e ? "DefineFunction2" : "DefineFunction", name: name.text || "(anon)", codeSize });
            actions(buf.subarray(off, off + codeSize), owner + " > " + (name.text || "(anon)"));
            off += codeSize;
        }
    }
    function tags(start, end, sprite) {
        let off = start, frame = 0;
        while (off < end) {
            requireBytes(body, off, 2);
            const header = body.readUInt16LE(off); off += 2;
            const code = header >> 6; let size = header & 63;
            if (size === 63) { requireBytes(body, off, 4); size = body.readUInt32LE(off); off += 4; }
            const next = off + size;
            if (next > end) throw new Error("Tag exceeds SWF container");
            const rec = body.subarray(off, next);
            if (code === 0) return;
            if (code === 39) {
                requireBytes(rec, 0, 4);
                const id = rec.readUInt16LE(0); sprites.add(id); tags(off + 4, next, id);
            } else if (code === 56) {
                requireBytes(rec, 0, 2); const count = rec.readUInt16LE(0); let p = 2;
                for (let i = 0; i < count; i++) {
                    requireBytes(rec, p, 2); const id = rec.readUInt16LE(p), name = str(rec, p + 2); p = name.next;
                    exports.push({ id, name: name.text });
                }
                if (p !== rec.length) throw new Error("Invalid ExportAssets length");
            } else if (code === 59) {
                requireBytes(rec, 0, 2); const id = rec.readUInt16LE(0), payload = rec.subarray(2);
                if (inits.has(id)) throw new Error("Duplicate DoInitAction sprite: " + id);
                inits.set(id, { actionBytes: payload.length, actionSha256: digest(payload) });
                actions(payload, "DoInitAction[class sprite=" + id + "]");
            } else if (code === 12) {
                actions(rec, "DoAction[sprite=" + sprite + " frame=" + frame + "]");
            } else if (code === 57 || code === 71) {
                const url = str(rec, 0); let p = url.next + (code === 71 ? 2 : 0);
                requireBytes(rec, p, 2); const count = rec.readUInt16LE(p); p += 2; const names = [];
                for (let i = 0; i < count; i++) { requireBytes(rec, p, 2); const name = str(rec, p + 2); names.push(name.text); p = name.next; }
                if (p !== rec.length) throw new Error("Invalid ImportAssets length");
                imports.push({ url: url.text, names });
            }
            if (code === 1) frame++;
            off = next;
        }
        throw new Error("Missing End tag");
    }
    const rectBytes = Math.ceil((5 + (body[0] >> 3) * 4) / 8);
    requireBytes(body, 0, rectBytes + 4);
    tags(rectBytes + 4, body.length, null);
    for (const entry of exports) {
        if (!entry.name.startsWith("__Packages.")) continue;
        if (!sprites.has(entry.id) || !inits.has(entry.id)) throw new Error("Class export has no defining sprite/init: " + entry.name);
        classes.push({ fqn: entry.name.slice(11), spriteId: entry.id, ...inits.get(entry.id) });
    }
    functions.sort((a, b) => b.codeSize - a.codeSize);
    return { parserVersion: VERSION, signature, swfVersion: raw[3], bytes: raw.length, sha256: digest(raw), classes, imports, functions };
}

function scanSwf(file, cacheDir) {
    const raw = fs.readFileSync(file), hash = digest(raw);
    const cache = cacheDir && path.join(cacheDir, VERSION + "-" + hash + ".json");
    if (cache) {
        try {
            const data = JSON.parse(fs.readFileSync(cache, "utf8"));
            const checksum = data.metadataSha256; delete data.metadataSha256;
            if (checksum === digest(Buffer.from(JSON.stringify(data))) && data.parserVersion === VERSION && data.sha256 === hash && Array.isArray(data.classes) && Array.isArray(data.imports) && Array.isArray(data.functions)) return { ...data, cacheHit: true };
        } catch (_) { /* Missing/damaged cache is recomputed from the authoritative bytes. */ }
    }
    const data = parseSwf(raw);
    if (cache) {
        fs.mkdirSync(cacheDir, { recursive: true });
        const temporary = cache + "." + process.pid + "." + crypto.randomBytes(4).toString("hex") + ".tmp";
        try { fs.writeFileSync(temporary, JSON.stringify({ ...data, metadataSha256: digest(Buffer.from(JSON.stringify(data))) })); fs.renameSync(temporary, cache); }
        finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
    }
    return { ...data, cacheHit: false };
}

function auditOwnership(root, files, cacheDir, options = {}) {
    const loader = "scripts/asLoader.swf", main = "CRAZYFLASHER7MercenaryEmpire.swf";
    const paths = [...new Set(files.map(f => f.replace(/\\/g, "/")))].filter(f => /\.swf$/i.test(f));
    if (!paths.includes(loader) || !paths.includes(main)) throw new Error("Production ownership requires main and asLoader");
    const rows = new Map(), errors = []; let hits = 0, parsed = 0;
    for (const rel of paths) {
        const full = path.resolve(root, rel), boundary = path.resolve(root) + path.sep;
        if (!full.startsWith(boundary)) throw new Error("SWF path escapes root: " + rel);
        // Historical .swf-suffix UTF-16 configuration, not an AVM1 artifact. Never emit its body.
        if (rel === "flashswf/gk-1-s.swf") {
            const raw = fs.readFileSync(full);
            if (raw.length !== 192 || raw[0] !== 255 || raw[1] !== 254) throw new Error("Unexpected non-SWF asset type: " + rel);
            continue;
        }
        const data = scanSwf(full, cacheDir); rows.set(rel, data);
        if (data.cacheHit) hits++; else parsed++;
    }
    const protectedNames = new Set(rows.get(loader).classes.map(c => c.fqn));
    if (![...protectedNames].some(n => n.startsWith("org.flashNight."))) errors.push("asLoader defines no project classes");
    for (const [rel, data] of rows) {
        const seen = new Set();
        for (const cls of data.classes) {
            if (seen.has(cls.fqn)) errors.push(rel + " defines class twice: " + cls.fqn);
            seen.add(cls.fqn);
            if (rel !== loader && (cls.fqn.startsWith("org.flashNight.") || protectedNames.has(cls.fqn))) errors.push(rel + " duplicates asLoader authority: " + cls.fqn);
        }
        for (const edge of options.checkImports === false ? [] : data.imports) {
            if (/^[a-z]+:/i.test(edge.url)) { errors.push(rel + " imports unbound external RSL: " + edge.url); continue; }
            const url = decodeURIComponent(edge.url).replace(/\\/g, "/");
            const candidates = [url, path.posix.normalize(path.posix.join(path.posix.dirname(rel), url))].filter(p => rows.has(p));
            if (new Set(candidates).size !== 1) errors.push(rel + " has missing/ambiguous RSL: " + edge.url);
        }
    }
    return { errors, files: rows.size, parsed, cacheHits: hits, loaderClasses: rows.get(loader).classes.length, closureChecked: options.checkImports !== false };
}
module.exports = { parseSwf, scanSwf, auditOwnership };
