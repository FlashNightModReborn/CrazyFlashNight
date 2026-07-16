#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const webRoot = path.join(projectRoot, 'launcher', 'web');
const mapRoot = path.join(webRoot, 'assets', 'map');
const runtimeSources = [
    path.join(webRoot, 'modules', 'map-panel-data.js'),
    path.join(webRoot, 'modules', 'map-avatar-source-data.js'),
    path.join(webRoot, 'modules', 'map-fit-presets.js'),
    path.join(webRoot, 'modules', 'map-panel.js'),
    path.join(webRoot, 'modules', 'map', 'dev', 'preview.js'),
    path.join(projectRoot, 'launcher', 'tests', 'Fixtures', 'MapHud', 'payload-v1-basic.json')
];

function walk(dir) {
    const out = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const abs = path.join(dir, entry.name);
        if (entry.isDirectory()) out.push.apply(out, walk(abs));
        else out.push(abs);
    }
    return out;
}

function inspectWebpBuffer(buf) {
    if (!Buffer.isBuffer(buf) || buf.length < 20 ||
            buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WEBP') {
        return { valid: false, lossless: false, lossy: false, error: 'invalid RIFF/WEBP header' };
    }
    const declaredSize = buf.readUInt32LE(4) + 8;
    if (declaredSize !== buf.length) {
        return { valid: false, lossless: false, lossy: false, error: 'RIFF size mismatch' };
    }
    let offset = 12;
    let lossless = false;
    let lossy = false;
    while (offset + 8 <= buf.length) {
        const chunkType = buf.toString('ascii', offset, offset + 4);
        const chunkSize = buf.readUInt32LE(offset + 4);
        const next = offset + 8 + chunkSize + (chunkSize & 1);
        if (next > buf.length) {
            return { valid: false, lossless: false, lossy: false, error: 'truncated ' + chunkType + ' chunk' };
        }
        if (chunkType === 'VP8L') lossless = true;
        if (chunkType === 'VP8 ') lossy = true;
        offset = next;
    }
    if (offset !== buf.length) {
        return { valid: false, lossless: false, lossy: false, error: 'trailing partial chunk' };
    }
    return { valid: true, lossless, lossy, error: '' };
}

function makeSyntheticWebp(chunkType) {
    const buf = Buffer.alloc(22);
    buf.write('RIFF', 0, 'ascii');
    buf.writeUInt32LE(14, 4);
    buf.write('WEBP', 8, 'ascii');
    buf.write(chunkType, 12, 'ascii');
    buf.writeUInt32LE(1, 16);
    buf[20] = 0;
    return buf;
}

function assertParserContract() {
    const lossless = inspectWebpBuffer(makeSyntheticWebp('VP8L'));
    const lossy = inspectWebpBuffer(makeSyntheticWebp('VP8 '));
    if (!lossless.valid || !lossless.lossless || lossless.lossy ||
            !lossy.valid || lossy.lossless || !lossy.lossy) {
        throw new Error('WebP chunk parser self-test failed');
    }
}

assertParserContract();

const errors = [];
const files = walk(mapRoot);
const pngFiles = files.filter(file => /\.png$/i.test(file));
const webpFiles = files.filter(file => /\.webp$/i.test(file));
if (pngFiles.length) {
    errors.push('runtime map PNG files remain: ' + pngFiles.map(file => path.relative(projectRoot, file)).join(', '));
}
if (!webpFiles.length) errors.push('no runtime map WebP files found');
for (const file of webpFiles) {
    const inspection = inspectWebpBuffer(fs.readFileSync(file));
    const relative = path.relative(projectRoot, file);
    if (!inspection.valid) errors.push('invalid WebP container: ' + relative + ' (' + inspection.error + ')');
    else if (!inspection.lossless || inspection.lossy) errors.push('runtime WebP is not lossless VP8L: ' + relative);
}

const referenced = new Set();
for (const source of runtimeSources) {
    const text = fs.readFileSync(source, 'utf8');
    const pngRefs = text.match(/assets\/map\/[^'"\r\n]+\.png/gi) || [];
    for (const ref of pngRefs) errors.push('runtime PNG reference remains in ' + path.relative(projectRoot, source) + ': ' + ref);
    const webpRefs = text.match(/assets\/map\/[^'"\r\n]+\.webp/gi) || [];
    for (const ref of webpRefs) referenced.add(ref);
}
for (const ref of referenced) {
    const abs = path.join(webRoot, ref.replace(/^\/+/, '').replace(/\//g, path.sep));
    if (!fs.existsSync(abs)) errors.push('missing referenced WebP: ' + ref);
}

const required = [
    'page-base.webp', 'page-faction.webp', 'page-defense.webp', 'page-school.webp',
    'roommate-male.webp', 'roommate-female.webp'
];
for (const name of required) {
    if (!fs.existsSync(path.join(mapRoot, name))) errors.push('missing required map asset: assets/map/' + name);
}

if (errors.length) {
    for (const error of errors) console.error('[map-webp] ERROR ' + error);
    process.exit(1);
}

const bytes = webpFiles.reduce((sum, file) => sum + fs.statSync(file).size, 0);
console.log('[map-webp] ok files=' + webpFiles.length + ' bytes=' + bytes + ' refs=' + referenced.size + ' png=0');
