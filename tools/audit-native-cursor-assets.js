#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const projectRoot = path.resolve(__dirname, '..');
const assetDir = path.join(projectRoot, 'launcher', 'web', 'assets', 'cursor', 'native');
const manifestPath = path.join(assetDir, 'manifest.json');

function parseArgs(argv) {
    const args = { json: false };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--json') args.json = true;
        else if (arg === '--help' || arg === '-h') {
            console.error('usage: node tools/audit-native-cursor-assets.js [--json]');
            process.exit(0);
        } else {
            console.error('unknown arg: ' + arg);
            process.exit(1);
        }
    }
    return args;
}

function ensurePngSignature(buf, file) {
    const sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    for (let i = 0; i < sig.length; i += 1) {
        if (buf[i] !== sig[i]) throw new Error(file + ' is not a PNG');
    }
}

function paeth(a, b, c) {
    const p = a + b - c;
    const pa = Math.abs(p - a);
    const pb = Math.abs(p - b);
    const pc = Math.abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

function unfilterScanline(filter, raw, prev, bpp) {
    const out = Buffer.alloc(raw.length);
    for (let i = 0; i < raw.length; i += 1) {
        const left = i >= bpp ? out[i - bpp] : 0;
        const up = prev ? prev[i] : 0;
        const upLeft = prev && i >= bpp ? prev[i - bpp] : 0;
        let value = raw[i];
        if (filter === 1) value = (value + left) & 0xff;
        else if (filter === 2) value = (value + up) & 0xff;
        else if (filter === 3) value = (value + Math.floor((left + up) / 2)) & 0xff;
        else if (filter === 4) value = (value + paeth(left, up, upLeft)) & 0xff;
        else if (filter !== 0) throw new Error('unsupported PNG filter: ' + filter);
        out[i] = value;
    }
    return out;
}

function pngInfo(file) {
    const buf = fs.readFileSync(file);
    ensurePngSignature(buf, file);

    let offset = 8;
    let width = 0;
    let height = 0;
    let bitDepth = 0;
    let colorType = 0;
    const idat = [];

    while (offset + 8 <= buf.length) {
        const len = buf.readUInt32BE(offset);
        const type = buf.toString('ascii', offset + 4, offset + 8);
        const dataStart = offset + 8;
        const dataEnd = dataStart + len;
        const data = buf.slice(dataStart, dataEnd);
        if (type === 'IHDR') {
            width = data.readUInt32BE(0);
            height = data.readUInt32BE(4);
            bitDepth = data[8];
            colorType = data[9];
        } else if (type === 'IDAT') {
            idat.push(data);
        } else if (type === 'IEND') {
            break;
        }
        offset = dataEnd + 4;
    }

    const channelsByType = { 0: 1, 2: 3, 4: 2, 6: 4 };
    const channels = channelsByType[colorType];
    if (!channels || bitDepth !== 8) {
        return { width, height, bitDepth, colorType, hotspotAlpha: null, alphaBounds: null };
    }

    const bpp = channels;
    const rowBytes = width * bpp;
    const inflated = zlib.inflateSync(Buffer.concat(idat));
    const rows = [];
    let srcOffset = 0;
    let prev = null;
    for (let y = 0; y < height; y += 1) {
        const filter = inflated[srcOffset];
        const raw = inflated.slice(srcOffset + 1, srcOffset + 1 + rowBytes);
        const row = unfilterScanline(filter, raw, prev, bpp);
        rows.push(row);
        prev = row;
        srcOffset += rowBytes + 1;
    }

    function alphaAt(x, y) {
        if (x < 0 || y < 0 || x >= width || y >= height) return 0;
        if (colorType === 6) return rows[y][x * bpp + 3];
        if (colorType === 4) return rows[y][x * bpp + 1];
        return 255;
    }

    let minX = width;
    let minY = height;
    let maxX = -1;
    let maxY = -1;
    let alphaPixels = 0;
    for (let y = 0; y < height; y += 1) {
        for (let x = 0; x < width; x += 1) {
            if (alphaAt(x, y) > 0) {
                if (x < minX) minX = x;
                if (y < minY) minY = y;
                if (x > maxX) maxX = x;
                if (y > maxY) maxY = y;
                alphaPixels += 1;
            }
        }
    }

    return {
        width,
        height,
        bitDepth,
        colorType,
        alphaAt,
        alphaBounds: alphaPixels > 0 ? { minX, minY, maxX, maxY, alphaPixels } : null
    };
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    const errors = [];
    const warnings = [];
    const results = [];

    if (!fs.existsSync(manifestPath)) {
        console.error('[FAIL] missing native cursor manifest: ' + manifestPath);
        process.exit(1);
    }

    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const canvas = manifest.canvas || {};
    const hotspot = manifest.hotspot || {};
    const states = Array.isArray(manifest.states) ? manifest.states : [];
    if (!canvas.width || !canvas.height) errors.push('manifest canvas.width/height missing');
    if (!Number.isInteger(hotspot.x) || !Number.isInteger(hotspot.y)) errors.push('manifest hotspot.x/y missing');
    if (states.length === 0) errors.push('manifest states empty');

    const expected = new Set(states.map(String));
    for (const state of states) {
        const file = path.join(assetDir, state + '.png');
        if (!fs.existsSync(file)) {
            errors.push('missing state PNG: ' + state + '.png');
            continue;
        }

        let info;
        try {
            info = pngInfo(file);
        } catch (err) {
            errors.push(state + '.png parse failed: ' + err.message);
            continue;
        }

        if (info.width !== canvas.width || info.height !== canvas.height) {
            errors.push(state + '.png size ' + info.width + 'x' + info.height
                + ' does not match canvas ' + canvas.width + 'x' + canvas.height);
        }
        if (!info.alphaBounds) {
            errors.push(state + '.png has no visible pixels');
        }
        if (typeof info.alphaAt === 'function' && info.alphaAt(hotspot.x, hotspot.y) <= 0) {
            errors.push(state + '.png hotspot pixel (' + hotspot.x + ',' + hotspot.y + ') is transparent');
        }

        results.push({
            state,
            width: info.width,
            height: info.height,
            bitDepth: info.bitDepth,
            colorType: info.colorType,
            hotspotAlpha: typeof info.alphaAt === 'function' ? info.alphaAt(hotspot.x, hotspot.y) : null,
            alphaBounds: info.alphaBounds
        });
    }

    for (const name of fs.readdirSync(assetDir)) {
        if (/\.png$/i.test(name)) {
            const state = name.replace(/\.png$/i, '');
            if (!expected.has(state)) warnings.push('unregistered native cursor PNG: ' + name);
        }
    }

    if (args.json) {
        console.log(JSON.stringify({ manifest, results, warnings, errors }, null, 2));
    } else {
        for (const warning of warnings) console.log('[WARN] ' + warning);
        if (errors.length > 0) {
            for (const error of errors) console.error('[FAIL] ' + error);
        } else {
            console.log('OK native cursor canvas: ' + states.length + ' states, '
                + canvas.width + 'x' + canvas.height + ', hotspot='
                + hotspot.x + ',' + hotspot.y);
        }
    }

    process.exit(errors.length > 0 ? 1 : 0);
}

main();
