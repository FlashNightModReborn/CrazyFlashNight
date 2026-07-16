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

function isWebp(absPath) {
    const fd = fs.openSync(absPath, 'r');
    const buf = Buffer.alloc(12);
    const read = fs.readSync(fd, buf, 0, 12, 0);
    fs.closeSync(fd);
    return read === 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP';
}

const errors = [];
const files = walk(mapRoot);
const pngFiles = files.filter(file => /\.png$/i.test(file));
const webpFiles = files.filter(file => /\.webp$/i.test(file));
if (pngFiles.length) {
    errors.push('runtime map PNG files remain: ' + pngFiles.map(file => path.relative(projectRoot, file)).join(', '));
}
if (!webpFiles.length) errors.push('no runtime map WebP files found');
for (const file of webpFiles) {
    if (!isWebp(file)) errors.push('invalid WebP signature: ' + path.relative(projectRoot, file));
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
