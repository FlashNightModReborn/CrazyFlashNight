'use strict';

// .CUBE 解析与序列化。数据布局：R 分量变化最快，index = ((b*size)+g)*size+r，每点 3 个 float。
// 解析容忍 LUT_3D_SIZE 16/17/32/33/64（实际接受 2..256），支持 TITLE/DOMAIN_MIN/DOMAIN_MAX，
// 其余关键字明确拒绝；数据行数必须恰好等于 size^3。

const SUPPORTED_KEYWORDS = new Set(['TITLE', 'LUT_3D_SIZE', 'DOMAIN_MIN', 'DOMAIN_MAX']);
const DEFAULT_DOMAIN_MIN = [0, 0, 0];
const DEFAULT_DOMAIN_MAX = [1, 1, 1];

function cubeError(message, sourceName, line) {
    const error = new Error(`${sourceName}:${line} ${message}`);
    error.cubeSource = sourceName;
    error.cubeLine = line;
    return error;
}

function parseCube(text, sourceName) {
    const source = sourceName || '<memory>';
    let size = 0;
    let title = null;
    let domainMin = DEFAULT_DOMAIN_MIN.slice();
    let domainMax = DEFAULT_DOMAIN_MAX.slice();
    const values = [];
    const lines = String(text).replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    for (let index = 0; index < lines.length; index += 1) {
        const lineNumber = index + 1;
        const line = lines[index].trim();
        if (!line || line.startsWith('#')) continue;
        const tokens = line.split(/\s+/);
        const head = tokens[0];
        // 先判数据行（"1 1 1" 这类纯整数行也合法），再判关键字。
        const triple = tokens.map(Number);
        if (triple.every((v) => Number.isFinite(v))) {
            if (tokens.length !== 3) {
                throw cubeError(`数据行需要恰好 3 个浮点数，实际 ${tokens.length} 个：${line}`, source, lineNumber);
            }
            values.push(triple[0], triple[1], triple[2]);
            continue;
        }
        if (/^[A-Z][A-Z_0-9]*$/.test(head)) {
            if (head === 'LUT_1D_SIZE') {
                throw cubeError('不支持 LUT_1D_SIZE（仅接受 3D LUT）', source, lineNumber);
            }
            if (!SUPPORTED_KEYWORDS.has(head)) {
                throw cubeError(
                    `未知关键字：${head}（仅支持 TITLE / LUT_3D_SIZE / DOMAIN_MIN / DOMAIN_MAX）`,
                    source,
                    lineNumber,
                );
            }
            if (head === 'TITLE') {
                title = line.slice(head.length).trim().replace(/^"|"$/g, '');
            } else if (head === 'LUT_3D_SIZE') {
                if (size !== 0) throw cubeError('LUT_3D_SIZE 重复声明', source, lineNumber);
                if (tokens.length !== 2 || !/^\d+$/.test(tokens[1])) {
                    throw cubeError(`LUT_3D_SIZE 需要单个整数，实际：${line}`, source, lineNumber);
                }
                size = Number.parseInt(tokens[1], 10);
                if (size < 2 || size > 256) throw cubeError(`LUT_3D_SIZE 超出 2..256：${size}`, source, lineNumber);
                if (values.length > 0) throw cubeError('LUT_3D_SIZE 必须出现在数据行之前', source, lineNumber);
            } else {
                if (tokens.length !== 4) throw cubeError(`${head} 需要 3 个浮点数，实际：${line}`, source, lineNumber);
                const domainTriple = tokens.slice(1).map(Number);
                if (domainTriple.some((v) => !Number.isFinite(v))) {
                    throw cubeError(`${head} 含非有限数值：${line}`, source, lineNumber);
                }
                if (head === 'DOMAIN_MIN') domainMin = domainTriple;
                else domainMax = domainTriple;
            }
            continue;
        }
        if (tokens.length === 3) {
            throw cubeError(`数据行含非有限数值：${line}`, source, lineNumber);
        }
        throw cubeError(`无法解析的行：${line}`, source, lineNumber);
    }
    if (size === 0) throw cubeError('缺少 LUT_3D_SIZE 声明', source, lines.length);
    const expectedLines = size * size * size;
    const actualLines = values.length / 3;
    if (actualLines !== expectedLines) {
        throw cubeError(`数据行数不完整：期望 ${expectedLines} 行（${size}^3），实际 ${actualLines} 行`, source, lines.length);
    }
    for (let axis = 0; axis < 3; axis += 1) {
        if (!(domainMax[axis] > domainMin[axis])) {
            throw cubeError(`DOMAIN_MAX 必须大于 DOMAIN_MIN（轴 ${axis}）：${domainMin[axis]}..${domainMax[axis]}`, source, 0);
        }
    }
    return {
        size,
        title,
        domainMin,
        domainMax,
        data: Float64Array.from(values),
        dataLines: actualLines,
    };
}

function isDefaultDomain(lut) {
    return lut.domainMin.every((v, i) => v === DEFAULT_DOMAIN_MIN[i])
        && lut.domainMax.every((v, i) => v === DEFAULT_DOMAIN_MAX[i]);
}

function serializeCube(lut, options) {
    const title = options && options.title !== undefined ? options.title : lut.title;
    const lines = [];
    if (title) lines.push(`TITLE "${title}"`);
    lines.push(`LUT_3D_SIZE ${lut.size}`);
    if (!isDefaultDomain(lut) || (options && options.alwaysWriteDomain)) {
        lines.push(`DOMAIN_MIN ${lut.domainMin.map((v) => v.toFixed(6)).join(' ')}`);
        lines.push(`DOMAIN_MAX ${lut.domainMax.map((v) => v.toFixed(6)).join(' ')}`);
    }
    for (let offset = 0; offset < lut.data.length; offset += 3) {
        lines.push(
            `${lut.data[offset].toFixed(6)} ${lut.data[offset + 1].toFixed(6)} ${lut.data[offset + 2].toFixed(6)}`,
        );
    }
    return `${lines.join('\n')}\n`;
}

function rangeByChannel(lut) {
    const min = [Infinity, Infinity, Infinity];
    const max = [-Infinity, -Infinity, -Infinity];
    for (let offset = 0; offset < lut.data.length; offset += 3) {
        for (let channel = 0; channel < 3; channel += 1) {
            const value = lut.data[offset + channel];
            if (value < min[channel]) min[channel] = value;
            if (value > max[channel]) max[channel] = value;
        }
    }
    return { min, max };
}

module.exports = { parseCube, serializeCube, rangeByChannel, isDefaultDomain };
