'use strict';

// raw RGBA8 字节流读写、CPU 三线性参考施加器、程序化测试图。
// raw 格式：纯 RGBA8 字节流，每像素 4 字节 R/G/B/A，宽高由参数给出，无文件头。

const fs = require('fs');

function assertDimension(name, value) {
    if (!Number.isInteger(value) || value < 1 || value > 16384) {
        throw new Error(`${name} 必须是 1..16384 的整数，实际：${value}`);
    }
}

function readRaw(file, width, height) {
    assertDimension('--width', width);
    assertDimension('--height', height);
    const buffer = fs.readFileSync(file);
    const expected = width * height * 4;
    if (buffer.length !== expected) {
        throw new Error(`raw 字节数不匹配：期望 ${width}x${height}x4=${expected} 字节，实际 ${buffer.length} 字节`);
    }
    return buffer;
}

function writeRaw(file, buffer) {
    fs.writeFileSync(file, buffer);
}

// 逐像素三线性施加：RGB 经 LUT，alpha 原样透传。
function applyLutToPixels(lut, input, sampleLut) {
    const output = Buffer.alloc(input.length);
    for (let offset = 0; offset < input.length; offset += 4) {
        const [r, g, b] = sampleLut(lut, input[offset] / 255, input[offset + 1] / 255, input[offset + 2] / 255);
        output[offset] = Math.round(Math.min(Math.max(r, 0), 1) * 255);
        output[offset + 1] = Math.round(Math.min(Math.max(g, 0), 1) * 255);
        output[offset + 2] = Math.round(Math.min(Math.max(b, 0), 1) * 255);
        output[offset + 3] = input[offset + 3];
    }
    return output;
}

const IMAGE_KINDS = ['dark-gradient', 'primaries', 'gray-ramp'];

// dark-gradient：4 条横带（灰 / R / G / B），每条 x 方向 0..0.25 平滑暗部渐变。
// primaries：4 列 x 2 行饱和色块（R G B W / C M Y 灰50）。
// gray-ramp：上半 0..255 平滑灰阶，下半 32 级阶梯。
function generateImage(kind, width, height) {
    if (!IMAGE_KINDS.includes(kind)) {
        throw new Error(`未知测试图种类：${kind}（可用：${IMAGE_KINDS.join(' / ')}）`);
    }
    assertDimension('--width', width);
    assertDimension('--height', height);
    const buffer = Buffer.alloc(width * height * 4);
    const setPixel = (x, y, r, g, b) => {
        const offset = (y * width + x) * 4;
        buffer[offset] = r;
        buffer[offset + 1] = g;
        buffer[offset + 2] = b;
        buffer[offset + 3] = 255;
    };
    const tx = (x) => (width > 1 ? x / (width - 1) : 0);
    for (let y = 0; y < height; y += 1) {
        for (let x = 0; x < width; x += 1) {
            if (kind === 'dark-gradient') {
                const band = Math.min(3, Math.floor((y * 4) / height));
                const v = Math.round(tx(x) * 0.25 * 255);
                if (band === 0) setPixel(x, y, v, v, v);
                else if (band === 1) setPixel(x, y, v, 0, 0);
                else if (band === 2) setPixel(x, y, 0, v, 0);
                else setPixel(x, y, 0, 0, v);
            } else if (kind === 'primaries') {
                const col = Math.min(3, Math.floor((x * 4) / width));
                const row = Math.min(1, Math.floor((y * 2) / height));
                const colors = [
                    [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]],
                    [[0, 255, 255], [255, 0, 255], [255, 255, 0], [128, 128, 128]],
                ];
                const [r, g, b] = colors[row][col];
                setPixel(x, y, r, g, b);
            } else {
                if (y * 2 < height) {
                    const v = Math.round(tx(x) * 255);
                    setPixel(x, y, v, v, v);
                } else {
                    const step = Math.min(31, Math.floor((x * 32) / width));
                    const v = Math.round((step * 255) / 31);
                    setPixel(x, y, v, v, v);
                }
            }
        }
    }
    return buffer;
}

module.exports = { readRaw, writeRaw, applyLutToPixels, generateImage, IMAGE_KINDS };
