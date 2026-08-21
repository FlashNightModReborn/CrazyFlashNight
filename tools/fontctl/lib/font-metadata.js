'use strict';

const path = require('path');
const zlib = require('zlib');

const WIDTH_TO_STRETCH = new Map([
    [1, 'ultra-condensed'],
    [2, 'extra-condensed'],
    [3, 'condensed'],
    [4, 'semi-condensed'],
    [5, 'normal'],
    [6, 'semi-expanded'],
    [7, 'expanded'],
    [8, 'extra-expanded'],
    [9, 'ultra-expanded'],
]);
const MAX_EXPANDED_TABLE_BYTES = 256 * 1024 * 1024;

function ensureRange(buffer, offset, length, label) {
    if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length)
        || offset < 0 || length < 0 || offset + length > buffer.length) {
        throw new Error(`${label} 越界`);
    }
}

function tagAt(buffer, offset) {
    ensureRange(buffer, offset, 4, 'table tag');
    return buffer.toString('ascii', offset, offset + 4);
}

function sfntTables(buffer) {
    ensureRange(buffer, 0, 12, 'sfnt header');
    const count = buffer.readUInt16BE(4);
    if (count < 1) throw new Error('sfnt 不含 table');
    ensureRange(buffer, 12, count * 16, 'sfnt table directory');
    const tables = new Map();
    for (let index = 0; index < count; index += 1) {
        const record = 12 + index * 16;
        const tag = tagAt(buffer, record);
        const offset = buffer.readUInt32BE(record + 8);
        const length = buffer.readUInt32BE(record + 12);
        ensureRange(buffer, offset, length, `sfnt table ${tag}`);
        if (tables.has(tag)) throw new Error(`重复 sfnt table：${tag}`);
        tables.set(tag, buffer.subarray(offset, offset + length));
    }
    return tables;
}

function woffTables(buffer) {
    ensureRange(buffer, 0, 44, 'WOFF header');
    if (buffer.readUInt32BE(8) !== buffer.length) throw new Error('WOFF header length 与文件长度不一致');
    const count = buffer.readUInt16BE(12);
    if (count < 1) throw new Error('WOFF 不含 table');
    ensureRange(buffer, 44, count * 20, 'WOFF table directory');
    const tables = new Map();
    let expandedBytes = 0;
    for (let index = 0; index < count; index += 1) {
        const record = 44 + index * 20;
        const tag = tagAt(buffer, record);
        const offset = buffer.readUInt32BE(record + 4);
        const compressedLength = buffer.readUInt32BE(record + 8);
        const originalLength = buffer.readUInt32BE(record + 12);
        expandedBytes += originalLength;
        if (originalLength > MAX_EXPANDED_TABLE_BYTES || expandedBytes > MAX_EXPANDED_TABLE_BYTES) {
            throw new Error('WOFF 展开后的 table 总量超过 Gate A 上限');
        }
        ensureRange(buffer, offset, compressedLength, `WOFF table ${tag}`);
        const stored = buffer.subarray(offset, offset + compressedLength);
        const table = compressedLength < originalLength ? zlib.inflateSync(stored) : stored;
        if (table.length !== originalLength) throw new Error(`WOFF table ${tag} 解压长度不匹配`);
        if (tables.has(tag)) throw new Error(`重复 WOFF table：${tag}`);
        tables.set(tag, table);
    }
    return tables;
}

function validateWoff2Header(buffer) {
    ensureRange(buffer, 0, 48, 'WOFF2 header');
    if (buffer.readUInt32BE(8) !== buffer.length) throw new Error('WOFF2 header length 与文件长度不一致');
    if (buffer.readUInt16BE(12) < 1) throw new Error('WOFF2 不含 table');
    if (buffer.readUInt16BE(14) !== 0) throw new Error('WOFF2 reserved 字段必须为 0');
    if (buffer.readUInt32BE(16) < 12 || buffer.readUInt32BE(20) < 1) throw new Error('WOFF2 size 字段非法');
}

function decodeUtf16Be(buffer) {
    if (buffer.length % 2 !== 0) return '';
    const swapped = Buffer.allocUnsafe(buffer.length);
    for (let index = 0; index < buffer.length; index += 2) {
        swapped[index] = buffer[index + 1];
        swapped[index + 1] = buffer[index];
    }
    return swapped.toString('utf16le').replace(/\0/g, '').trim();
}

function decodeName(buffer, platformId) {
    if (platformId === 0 || platformId === 3) return decodeUtf16Be(buffer);
    return buffer.toString('latin1').replace(/\0/g, '').trim();
}

function readNames(table) {
    if (!table) return { families: [], subfamilies: [] };
    ensureRange(table, 0, 6, 'name header');
    const count = table.readUInt16BE(2);
    const stringOffset = table.readUInt16BE(4);
    ensureRange(table, 6, count * 12, 'name records');
    const records = [];
    for (let index = 0; index < count; index += 1) {
        const offset = 6 + index * 12;
        const platformId = table.readUInt16BE(offset);
        const encodingId = table.readUInt16BE(offset + 2);
        const languageId = table.readUInt16BE(offset + 4);
        const nameId = table.readUInt16BE(offset + 6);
        const length = table.readUInt16BE(offset + 8);
        const valueOffset = stringOffset + table.readUInt16BE(offset + 10);
        if (![1, 2, 16, 17].includes(nameId)) continue;
        ensureRange(table, valueOffset, length, 'name string');
        const value = decodeName(table.subarray(valueOffset, valueOffset + length), platformId);
        if (value) records.push({ platformId, encodingId, languageId, nameId, value });
    }
    records.sort((left, right) => (
        (left.nameId === 16 || left.nameId === 17 ? 0 : 1) - (right.nameId === 16 || right.nameId === 17 ? 0 : 1)
        || (left.platformId === 3 ? 0 : 1) - (right.platformId === 3 ? 0 : 1)
        || left.languageId - right.languageId
        || left.value.localeCompare(right.value, 'en')
    ));
    const unique = (ids) => [...new Set(records.filter((record) => ids.includes(record.nameId)).map((record) => record.value))];
    const typographicFamilies = unique([16]);
    const legacyFamilies = unique([1]);
    const typographicSubfamilies = unique([17]);
    const legacySubfamilies = unique([2]);
    return {
        families: typographicFamilies.length ? typographicFamilies : legacyFamilies,
        subfamilies: typographicSubfamilies.length ? typographicSubfamilies : legacySubfamilies,
    };
}

function readMetrics(tables) {
    const os2 = tables.get('OS/2');
    const head = tables.get('head');
    let weight = null;
    let stretch = null;
    let italic = false;
    let oblique = false;
    if (os2 && os2.length >= 8) {
        weight = os2.readUInt16BE(4);
        stretch = WIDTH_TO_STRETCH.get(os2.readUInt16BE(6)) || null;
    }
    if (os2 && os2.length >= 64) {
        const selection = os2.readUInt16BE(62);
        italic = Boolean(selection & 0x0001);
        oblique = Boolean(selection & 0x0200);
    } else if (head && head.length >= 46) {
        italic = Boolean(head.readUInt16BE(44) & 0x0002);
    }
    return {
        weight,
        style: oblique ? 'oblique' : (italic ? 'italic' : 'normal'),
        stretch,
    };
}

function summarizeFormat12(table, offset, format) {
    ensureRange(table, offset, 16, `cmap format ${format}`);
    const length = table.readUInt32BE(offset + 4);
    const groupCount = table.readUInt32BE(offset + 12);
    ensureRange(table, offset, length, `cmap format ${format}`);
    ensureRange(table, offset + 16, groupCount * 12, `cmap format ${format} groups`);
    let count = 0;
    let first = null;
    let last = null;
    for (let index = 0; index < groupCount; index += 1) {
        const group = offset + 16 + index * 12;
        const start = table.readUInt32BE(group);
        const end = table.readUInt32BE(group + 4);
        const glyph = table.readUInt32BE(group + 8);
        if (end < start || end > 0x10ffff) throw new Error(`cmap format ${format} group 非法`);
        let groupCountValue = end - start + 1;
        if (format === 13 && glyph === 0) groupCountValue = 0;
        if (format === 12 && glyph === 0 && groupCountValue > 0) groupCountValue -= 1;
        if (groupCountValue > 0) {
            count += groupCountValue;
            first = first === null ? start + (format === 12 && glyph === 0 ? 1 : 0) : Math.min(first, start);
            last = last === null ? end : Math.max(last, end);
        }
    }
    return { format, codePointCount: count, firstCodePoint: first, lastCodePoint: last, groupCount };
}

function summarizeFormat4(table, offset) {
    ensureRange(table, offset, 16, 'cmap format 4');
    const length = table.readUInt16BE(offset + 2);
    const segmentCount = table.readUInt16BE(offset + 6) / 2;
    ensureRange(table, offset, length, 'cmap format 4');
    if (!Number.isInteger(segmentCount) || segmentCount < 1) throw new Error('cmap format 4 segmentCount 非法');
    const endCodes = offset + 14;
    const startCodes = endCodes + segmentCount * 2 + 2;
    const deltas = startCodes + segmentCount * 2;
    const rangeOffsets = deltas + segmentCount * 2;
    ensureRange(table, rangeOffsets, segmentCount * 2, 'cmap format 4 arrays');
    let count = 0;
    let first = null;
    let last = null;
    for (let segment = 0; segment < segmentCount; segment += 1) {
        const start = table.readUInt16BE(startCodes + segment * 2);
        const end = table.readUInt16BE(endCodes + segment * 2);
        const delta = table.readInt16BE(deltas + segment * 2);
        const rangeOffsetLocation = rangeOffsets + segment * 2;
        const rangeOffset = table.readUInt16BE(rangeOffsetLocation);
        if (end < start) throw new Error('cmap format 4 segment 非法');
        for (let codePoint = start; codePoint <= end && codePoint !== 0xffff; codePoint += 1) {
            let glyph;
            if (rangeOffset === 0) glyph = (codePoint + delta) & 0xffff;
            else {
                const glyphOffset = rangeOffsetLocation + rangeOffset + (codePoint - start) * 2;
                if (glyphOffset + 2 > offset + length) continue;
                glyph = table.readUInt16BE(glyphOffset);
                if (glyph !== 0) glyph = (glyph + delta) & 0xffff;
            }
            if (glyph !== 0) {
                count += 1;
                first = first === null ? codePoint : Math.min(first, codePoint);
                last = last === null ? codePoint : Math.max(last, codePoint);
            }
        }
    }
    return { format: 4, codePointCount: count, firstCodePoint: first, lastCodePoint: last, groupCount: segmentCount };
}

function readCmap(table) {
    if (!table) return null;
    ensureRange(table, 0, 4, 'cmap header');
    const count = table.readUInt16BE(2);
    ensureRange(table, 4, count * 8, 'cmap records');
    const candidates = [];
    for (let index = 0; index < count; index += 1) {
        const record = 4 + index * 8;
        const platformId = table.readUInt16BE(record);
        const encodingId = table.readUInt16BE(record + 2);
        const offset = table.readUInt32BE(record + 4);
        ensureRange(table, offset, 2, 'cmap subtable');
        const format = table.readUInt16BE(offset);
        if ([4, 12, 13].includes(format)) candidates.push({ platformId, encodingId, offset, format });
    }
    candidates.sort((left, right) => (
        ([12, 13, 4].indexOf(left.format) - [12, 13, 4].indexOf(right.format))
        || (left.platformId === 0 ? 0 : left.platformId === 3 ? 1 : 2)
        || left.encodingId - right.encodingId
    ));
    if (!candidates.length) return null;
    const selected = candidates[0];
    const summary = selected.format === 4
        ? summarizeFormat4(table, selected.offset)
        : summarizeFormat12(table, selected.offset, selected.format);
    return { ...summary, platformId: selected.platformId, encodingId: selected.encodingId };
}

function inspectFont(fileName, buffer) {
    const extension = path.extname(fileName).slice(1).toLowerCase();
    if (buffer.length < 4) throw new Error('文件短于字体容器 header');
    const signature = buffer.toString('ascii', 0, 4);
    let detectedFormat;
    let tables = null;
    if (buffer.readUInt32BE(0) === 0x00010000 || signature === 'true' || signature === 'typ1') {
        detectedFormat = 'ttf';
        tables = sfntTables(buffer);
    } else if (signature === 'OTTO') {
        detectedFormat = 'otf';
        tables = sfntTables(buffer);
    } else if (signature === 'wOFF') {
        detectedFormat = 'woff';
        tables = woffTables(buffer);
    } else if (signature === 'wOF2') {
        detectedFormat = 'woff2';
        validateWoff2Header(buffer);
    } else {
        throw new Error(`不支持的字体 magic：${buffer.subarray(0, 4).toString('hex')}`);
    }
    if (extension !== detectedFormat) throw new Error(`扩展名 .${extension} 与容器 ${detectedFormat} 不一致`);
    if (!tables) {
        return {
            format: detectedFormat,
            metadataStatus: 'container-only',
            families: [],
            subfamilies: [],
            weight: null,
            style: null,
            stretch: null,
            cmap: null,
        };
    }
    const names = readNames(tables.get('name'));
    const metrics = readMetrics(tables);
    return {
        format: detectedFormat,
        metadataStatus: 'parsed',
        ...names,
        ...metrics,
        cmap: readCmap(tables.get('cmap')),
    };
}

module.exports = { inspectFont };
