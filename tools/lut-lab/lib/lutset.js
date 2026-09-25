'use strict';

// CF7LUTSET v1 —— 生产渲染链的世界光照 LUT 集合格式（小端二进制）。
//
// 布局：
//   偏移 0   4 字节  magic = "CF7L"（ASCII）
//   偏移 4   u32le   版本 = 1
//   偏移 8   u32le   尺寸 size = 32（32^3 节点）
//   偏移 12  u32le   档数 levels = 10（光照等级 0..9 各一档）
//   偏移 16  32 字节 数据段 SHA-256（完整性字段；Host 加载时逐字节复核，不符即回退 legacy 矩阵）
//   偏移 48  数据段：levels × size^3 × 4 字节 RGBA8
//
// 数据段节点序与 .CUBE / WorldLutBaker.Bake 一致：R 分量变化最快，
// index = ((b*size)+g)*size+r，alpha 恒 255。D3D11 Texture3D 上传时
// RowPitch=size*4、DepthPitch=size*size*4，采样坐标 (r,g,b) 直映 (x,y,z)。
//
// 生成：`node tools/lut-lab/cli.js pack-set --set <sets/x> --out <file.lutset>`
// 校验：`pack-set --check`（重新打包并与现有产物逐字节比较；stale 即非零退出）。
// 权威来源是 tmp/lut-lab/sets/<name>/ 下已验收的 10 档 .cube（bake-ramp 自检全过的产物），
// 本格式只是其确定性二进制打包，不引入新的色彩语义。

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { parseCube } = require('./cube');
const { resampleTo32 } = require('./lut');

const MAGIC = Buffer.from('CF7L', 'ascii');
const VERSION = 1;
const LUT_SIZE = 32;
const LEVELS = 10;
const HEADER_BYTES = 48;
const LEVEL_BYTES = LUT_SIZE * LUT_SIZE * LUT_SIZE * 4;
const DATA_BYTES = LEVELS * LEVEL_BYTES;
const TOTAL_BYTES = HEADER_BYTES + DATA_BYTES;

function quantizeChannel(value) {
    const q = Math.round(value * 255);
    return q < 0 ? 0 : q > 255 ? 255 : q;
}

// 单档 .cube → RGBA8 节点字节。要求默认域 [0,1]；非 32^3 经三线性重采样（与 apply 路径同语义）。
function cubeToRgba8(text, sourceName) {
    const parsed = parseCube(text, sourceName);
    if (parsed.domainMin.some((v) => v !== 0) || parsed.domainMax.some((v) => v !== 1)) {
        throw new Error(`${sourceName}：pack-set 要求默认域 [0,1]，实际 ${parsed.domainMin}..${parsed.domainMax}`);
    }
    const lut = resampleTo32(parsed);
    const out = Buffer.alloc(LEVEL_BYTES);
    for (let node = 0; node < LUT_SIZE * LUT_SIZE * LUT_SIZE; node += 1) {
        const o3 = node * 3;
        const o4 = node * 4;
        out[o4] = quantizeChannel(lut.data[o3]);
        out[o4 + 1] = quantizeChannel(lut.data[o3 + 1]);
        out[o4 + 2] = quantizeChannel(lut.data[o3 + 2]);
        out[o4 + 3] = 255;
    }
    return out;
}

// 从集合目录（preset.json 的 mode 决定文件前缀，等级 0..9 必须齐全）打包。
// 返回 { buffer, sha256, files }；sha256 为数据段哈希（与文件头内嵌字段一致）。
function packSet(setDir) {
    const presetPath = path.join(setDir, 'preset.json');
    if (!fs.existsSync(presetPath)) throw new Error(`集合缺 preset.json：${setDir}`);
    const preset = JSON.parse(fs.readFileSync(presetPath, 'utf8'));
    const prefix = preset.mode;
    if (prefix !== '光照' && prefix !== '夜视') throw new Error(`${presetPath}：无法推导档位文件前缀（mode=${prefix}）`);
    const data = Buffer.alloc(DATA_BYTES);
    const files = [];
    for (let level = 0; level < LEVELS; level += 1) {
        const fileName = `${prefix}-${level}.cube`;
        const filePath = path.join(setDir, fileName);
        if (!fs.existsSync(filePath)) throw new Error(`集合缺档位文件：${filePath}`);
        const rgba = cubeToRgba8(fs.readFileSync(filePath, 'utf8'), fileName);
        rgba.copy(data, level * LEVEL_BYTES);
        files.push(fileName);
    }
    const sha256 = crypto.createHash('sha256').update(data).digest();
    const buffer = Buffer.alloc(TOTAL_BYTES);
    MAGIC.copy(buffer, 0);
    buffer.writeUInt32LE(VERSION, 4);
    buffer.writeUInt32LE(LUT_SIZE, 8);
    buffer.writeUInt32LE(LEVELS, 12);
    sha256.copy(buffer, 16);
    data.copy(buffer, HEADER_BYTES);
    return { buffer, sha256: sha256.toString('hex'), files };
}

module.exports = {
    MAGIC,
    VERSION,
    LUT_SIZE,
    LEVELS,
    HEADER_BYTES,
    LEVEL_BYTES,
    DATA_BYTES,
    TOTAL_BYTES,
    packSet,
    cubeToRgba8,
};
