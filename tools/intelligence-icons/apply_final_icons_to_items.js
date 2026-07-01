#!/usr/bin/env node
'use strict';

const childProcess = require('child_process');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const projectRoot = path.resolve(__dirname, '..', '..');
const finalRoot = path.join(projectRoot, 'outputs', 'intelligence-icons', 'final-review-2026-06-30');
const finalManifestPath = path.join(finalRoot, 'manifest', 'final-icons.tsv');
const designDocPath = path.join(projectRoot, 'docs', '情报图标设计方案-复用图标-2026-06-29.md');
const itemXmlPath = path.join(projectRoot, 'data', 'items', '收集品_情报.xml');
const launcherManifestPath = path.join(projectRoot, 'launcher', 'web', 'icons', 'manifest.json');
const launcherIconsDir = path.join(projectRoot, 'launcher', 'web', 'icons');
const svg2swfDir = path.join(projectRoot, 'tools', 'svg2swf', 'svg2swf-0.5');
const svg2swfExe = path.join(svg2swfDir, 'svg2swf.exe');

const slugPngDir = path.join(finalRoot, 'final');
const slugSvgDir = path.join(finalRoot, 'svg');
const slugSwfDir = path.join(finalRoot, 'swf');
const byNameRoot = path.join(finalRoot, 'by-item-name');
const byNamePngDir = path.join(byNameRoot, 'png');
const byNameSvgDir = path.join(byNameRoot, 'svg');
const byNameSwfDir = path.join(byNameRoot, 'swf');
const nameMapPath = path.join(byNameRoot, 'item-name-map.tsv');

function fail(message) {
    console.error('[apply-final-icons] ' + message);
    process.exit(1);
}

function readText(file) {
    try {
        return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
    } catch (e) {
        fail('cannot read ' + file + ': ' + e.message);
    }
}

function writeText(file, text) {
    fs.writeFileSync(file, text, 'utf8');
}

function ensureDir(dir) {
    fs.mkdirSync(dir, { recursive: true });
}

function copyFile(src, dest) {
    if (!fs.existsSync(src)) fail('missing source file: ' + src);
    fs.copyFileSync(src, dest);
}

function rel(file) {
    return path.relative(projectRoot, file).replace(/\\/g, '/');
}

function parseTsv(file) {
    const lines = readText(file).split(/\r?\n/).filter(Boolean);
    if (!lines.length) fail('empty TSV: ' + file);
    const headers = lines[0].split('\t');
    return lines.slice(1).map((line) => {
        const cells = line.split('\t');
        const row = {};
        for (let i = 0; i < headers.length; i += 1) row[headers[i]] = cells[i] || '';
        return row;
    });
}

function cleanCell(value) {
    return String(value || '').replace(/\\\|/g, '|').trim();
}

function parseDesignNames() {
    const raw = readText(designDocPath);
    const start = raw.indexOf('## 方案表');
    if (start < 0) fail('cannot find design table section in ' + designDocPath);
    const end = raw.indexOf('## 游戏资产', start);
    const section = raw.slice(start, end > start ? end : raw.length);
    const out = new Map();
    for (const line of section.split(/\r?\n/)) {
        const m = /^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|/.exec(line);
        if (!m) continue;
        const idNum = Number(m[1]);
        if (!Number.isInteger(idNum) || idNum < 1 || idNum > 41) continue;
        const id = String(idNum).padStart(2, '0');
        if (out.has(id)) fail('duplicate design id #' + id);
        out.set(id, cleanCell(m[2]));
    }
    if (out.size !== 41) fail('expected 41 design names, got ' + out.size);
    return out;
}

function buildRows() {
    const names = parseDesignNames();
    const finalRows = parseTsv(finalManifestPath);
    const out = [];
    for (const row of finalRows) {
        const id = String(row.id || '').padStart(2, '0');
        const slug = row.slug || '';
        if (!id || !slug) fail('bad final manifest row: ' + JSON.stringify(row));
        const name = names.get(id);
        if (!name) fail('no item name for final icon id #' + id);
        out.push({ id, slug, name });
    }
    if (out.length !== 41) fail('expected 41 final icons, got ' + out.length);
    return out;
}

function isInvalidWindowsFileName(name) {
    return /[<>:"/\\|?*\x00-\x1F]/.test(name);
}

function validateFileNames(rows) {
    const bad = rows.filter((r) => isInvalidWindowsFileName(r.name));
    if (bad.length) fail('item names cannot be used as filenames: ' + bad.map((r) => r.name).join(', '));
}

function convertSvgToSwf(srcSvg, destSwf) {
    const result = childProcess.spawnSync(svg2swfExe, [srcSvg, destSwf], {
        cwd: svg2swfDir,
        encoding: 'utf8'
    });
    if (result.error) fail('svg2swf failed to start: ' + result.error.message);
    if (result.status !== 0) {
        fail('svg2swf failed for ' + srcSvg + '\nstdout:\n' + (result.stdout || '') + '\nstderr:\n' + (result.stderr || ''));
    }
    if (!fs.existsSync(destSwf) || fs.statSync(destSwf).size <= 0) fail('svg2swf produced empty output: ' + destSwf);
}

function parseSwfTags(file) {
    const b = fs.readFileSync(file);
    const sig = b.slice(0, 3).toString('ascii');
    if (sig !== 'FWS' && sig !== 'CWS') fail('unsupported SWF signature for ' + file + ': ' + sig);
    let body = b.slice(8);
    if (sig === 'CWS') body = zlib.inflateSync(body);
    if (!body.length) fail('empty SWF body: ' + file);

    const nbits = body[0] >> 3;
    const rectBits = 5 + 4 * nbits;
    const rectBytes = Math.ceil(rectBits / 8);
    let pos = rectBytes + 4;
    const counts = new Map();
    while (pos + 2 <= body.length) {
        const codeAndLength = body.readUInt16LE(pos);
        pos += 2;
        const code = codeAndLength >> 6;
        let length = codeAndLength & 0x3f;
        if (length === 0x3f) {
            if (pos + 4 > body.length) break;
            length = body.readUInt32LE(pos);
            pos += 4;
        }
        counts.set(code, (counts.get(code) || 0) + 1);
        pos += length;
        if (code === 0) break;
    }
    const sum = (codes) => codes.reduce((n, c) => n + (counts.get(c) || 0), 0);
    return {
        signature: sig,
        version: b[3],
        length: b.length,
        shapeCount: sum([2, 22, 32, 83]),
        bitmapCount: sum([6, 20, 21, 35, 36, 90])
    };
}

function escapeXmlText(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function unescapeXmlText(value) {
    return String(value || '')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&amp;/g, '&');
}

function childText(block, tag) {
    const re = new RegExp('<' + tag + '>\\s*([\\s\\S]*?)\\s*</' + tag + '>');
    const m = re.exec(block);
    return m ? unescapeXmlText(m[1].trim()) : '';
}

function updateItemXml(rows) {
    const target = new Map(rows.map((r) => [r.name, r]));
    const seen = new Set();
    const raw = readText(itemXmlPath);
    const updated = raw.replace(/<item\b[^>]*>[\s\S]*?<\/item>/g, (block) => {
        const name = childText(block, 'name');
        if (!target.has(name)) return block;
        seen.add(name);
        if (/<icon\s*\/>/.test(block)) {
            return block.replace(/<icon\s*\/>/, '<icon>' + escapeXmlText(name) + '</icon>');
        }
        if (/<icon>[\s\S]*?<\/icon>/.test(block)) {
            return block.replace(/(<icon>)[\s\S]*?(<\/icon>)/, '$1' + escapeXmlText(name) + '$2');
        }
        fail('target item has no <icon>: ' + name);
        return block;
    });
    const missing = rows.filter((r) => !seen.has(r.name));
    if (missing.length) fail('target items missing from XML: ' + missing.map((r) => r.name).join(', '));
    if (updated !== raw) writeText(itemXmlPath, updated);
}

function updateLauncherManifest(rows) {
    let manifest;
    try {
        manifest = JSON.parse(readText(launcherManifestPath));
    } catch (e) {
        fail('invalid launcher icon manifest: ' + e.message);
    }
    for (const row of rows) {
        manifest[row.name] = { f1: row.name + '.png' };
    }
    writeText(launcherManifestPath, JSON.stringify(manifest, null, 2) + '\n');
}

function main() {
    if (!fs.existsSync(svg2swfExe)) fail('missing svg2swf executable: ' + svg2swfExe);
    const rows = buildRows();
    validateFileNames(rows);

    ensureDir(slugSwfDir);
    ensureDir(byNamePngDir);
    ensureDir(byNameSvgDir);
    ensureDir(byNameSwfDir);

    const swfStats = [];
    const mapLines = ['id\tslug\tname\tpng\tsvg\tswf'];
    for (const row of rows) {
        const stem = row.id + '-' + row.slug;
        const srcPng = path.join(slugPngDir, stem + '.png');
        const srcSvg = path.join(slugSvgDir, stem + '.svg');
        const slugSwf = path.join(slugSwfDir, stem + '.swf');

        convertSvgToSwf(srcSvg, slugSwf);
        const tags = parseSwfTags(slugSwf);
        if (tags.shapeCount <= 0 || tags.bitmapCount !== 0) {
            fail('unexpected SWF tag mix for ' + slugSwf + ': shape=' + tags.shapeCount + ', bitmap=' + tags.bitmapCount);
        }
        swfStats.push(tags);

        const itemPng = path.join(byNamePngDir, row.name + '.png');
        const itemSvg = path.join(byNameSvgDir, row.name + '.svg');
        const itemSwf = path.join(byNameSwfDir, row.name + '.swf');
        copyFile(srcPng, itemPng);
        copyFile(srcSvg, itemSvg);
        copyFile(slugSwf, itemSwf);
        copyFile(srcPng, path.join(launcherIconsDir, row.name + '.png'));

        mapLines.push([row.id, row.slug, row.name, rel(itemPng), rel(itemSvg), rel(itemSwf)].join('\t'));
    }
    ensureDir(byNameRoot);
    writeText(nameMapPath, mapLines.join('\n') + '\n');

    updateItemXml(rows);
    updateLauncherManifest(rows);

    const totalShapes = swfStats.reduce((n, s) => n + s.shapeCount, 0);
    console.log('[apply-final-icons] icons=' + rows.length);
    console.log('[apply-final-icons] by-name package=' + rel(byNameRoot));
    console.log('[apply-final-icons] swf vector check: shapeTags=' + totalShapes + ', bitmapTags=0');
    console.log('[apply-final-icons] updated XML=' + rel(itemXmlPath));
    console.log('[apply-final-icons] updated launcher manifest=' + rel(launcherManifestPath));
}

main();
