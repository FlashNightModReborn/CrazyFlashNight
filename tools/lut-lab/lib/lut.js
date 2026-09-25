'use strict';

// LUT 数学核心：三线性采样、任意尺寸重采样到 32^3、内置生成器。
// 采样输入为 LUT 输入值空间（DOMAIN_MIN..DOMAIN_MAX 所指空间，通常即 [0,1] 图像值）。

const REC709 = [0.2126, 0.7152, 0.0722];

function clamp01(value) {
    return value < 0 ? 0 : value > 1 ? 1 : value;
}

function luma709(r, g, b) {
    return REC709[0] * r + REC709[1] * g + REC709[2] * b;
}

function gridValue(lut, ri, gi, bi, channel) {
    return lut.data[(((bi * lut.size + gi) * lut.size) + ri) * 3 + channel];
}

function axisToGrid(lut, value, axis) {
    const span = lut.domainMax[axis] - lut.domainMin[axis];
    const normalized = span > 0 ? (value - lut.domainMin[axis]) / span : 0;
    const scaled = normalized * (lut.size - 1);
    return scaled < 0 ? 0 : scaled > lut.size - 1 ? lut.size - 1 : scaled;
}

function sampleChannel(lut, ur, ug, ub, channel) {
    const size = lut.size;
    const r0 = Math.floor(ur); const g0 = Math.floor(ug); const b0 = Math.floor(ub);
    const r1 = Math.min(r0 + 1, size - 1); const g1 = Math.min(g0 + 1, size - 1); const b1 = Math.min(b0 + 1, size - 1);
    const fr = ur - r0; const fg = ug - g0; const fb = ub - b0;
    const c000 = gridValue(lut, r0, g0, b0, channel);
    const c100 = gridValue(lut, r1, g0, b0, channel);
    const c010 = gridValue(lut, r0, g1, b0, channel);
    const c110 = gridValue(lut, r1, g1, b0, channel);
    const c001 = gridValue(lut, r0, g0, b1, channel);
    const c101 = gridValue(lut, r1, g0, b1, channel);
    const c011 = gridValue(lut, r0, g1, b1, channel);
    const c111 = gridValue(lut, r1, g1, b1, channel);
    const c00 = c000 + (c100 - c000) * fr;
    const c10 = c010 + (c110 - c010) * fr;
    const c01 = c001 + (c101 - c001) * fr;
    const c11 = c011 + (c111 - c011) * fr;
    const c0 = c00 + (c10 - c00) * fg;
    const c1 = c01 + (c11 - c01) * fg;
    return c0 + (c1 - c0) * fb;
}

function sampleLut(lut, r, g, b) {
    const ur = axisToGrid(lut, r, 0);
    const ug = axisToGrid(lut, g, 1);
    const ub = axisToGrid(lut, b, 2);
    return [
        sampleChannel(lut, ur, ug, ub, 0),
        sampleChannel(lut, ur, ug, ub, 1),
        sampleChannel(lut, ur, ug, ub, 2),
    ];
}

// 非 32^3 重采样到 32^3，保持原 DOMAIN；对网格点 i/31 在源 LUT 上做三线性。
function resampleTo32(lut) {
    if (lut.size === 32) return lut;
    const size = 32;
    const data = new Float64Array(size * size * size * 3);
    for (let bi = 0; bi < size; bi += 1) {
        const b = lut.domainMin[2] + (bi / (size - 1)) * (lut.domainMax[2] - lut.domainMin[2]);
        for (let gi = 0; gi < size; gi += 1) {
            const g = lut.domainMin[1] + (gi / (size - 1)) * (lut.domainMax[1] - lut.domainMin[1]);
            for (let ri = 0; ri < size; ri += 1) {
                const r = lut.domainMin[0] + (ri / (size - 1)) * (lut.domainMax[0] - lut.domainMin[0]);
                const [or, og, ob] = sampleLut(lut, r, g, b);
                const offset = (((bi * size + gi) * size) + ri) * 3;
                data[offset] = or;
                data[offset + 1] = og;
                data[offset + 2] = ob;
            }
        }
    }
    return {
        size,
        title: lut.title,
        domainMin: lut.domainMin.slice(),
        domainMax: lut.domainMax.slice(),
        data,
        dataLines: size * size * size,
        resampledFrom: lut.size,
    };
}

function buildLut(size, fn) {
    const data = new Float64Array(size * size * size * 3);
    for (let bi = 0; bi < size; bi += 1) {
        const b = bi / (size - 1);
        for (let gi = 0; gi < size; gi += 1) {
            const g = gi / (size - 1);
            for (let ri = 0; ri < size; ri += 1) {
                const r = ri / (size - 1);
                const [or, og, ob] = fn(r, g, b);
                const offset = (((bi * size + gi) * size) + ri) * 3;
                data[offset] = clamp01(or);
                data[offset + 1] = clamp01(og);
                data[offset + 2] = clamp01(ob);
            }
        }
    }
    return {
        size,
        title: null,
        domainMin: [0, 0, 0],
        domainMax: [1, 1, 1],
        data,
        dataLines: size * size * size,
    };
}

// 夜视共用响应：Rec.709 亮度 → 增益 1.18 + 暗部抬升 0.045 → 1.0 硬裁切（高光溢出）。
function nightVisionResponse(r, g, b) {
    return clamp01(luma709(r, g, b) * 1.18 + 0.045);
}

// 暗部压陡：分段线性，斜率 0.2 / 1.4 / 1.2，0.25 与 0.5 处折点连续但斜率跳变。
function darkCurve(v) {
    if (v < 0.25) return v * 0.2;
    if (v < 0.5) return 0.05 + (v - 0.25) * 1.4;
    return 0.4 + (v - 0.5) * 1.2;
}

const GENERATORS = {
    identity: {
        title: 'CF7 LUT Lab identity',
        fn: (r, g, b) => [r, g, b],
    },
    'nightvision-green': {
        title: 'CF7 LUT Lab nightvision green phosphor',
        fn: (r, g, b) => {
            const v = nightVisionResponse(r, g, b);
            return [v * 0.07, v, v * 0.13];
        },
    },
    'nightvision-amber': {
        title: 'CF7 LUT Lab nightvision amber phosphor',
        fn: (r, g, b) => {
            const v = nightVisionResponse(r, g, b);
            return [v, v * 0.6, v * 0.08];
        },
    },
    'nightvision-white': {
        title: 'CF7 LUT Lab nightvision white phosphor',
        fn: (r, g, b) => {
            const v = nightVisionResponse(r, g, b);
            return [v * 0.93, v * 0.97, v];
        },
    },
    'stress-darkcurve': {
        title: 'CF7 LUT Lab stress dark curve',
        fn: (r, g, b) => [darkCurve(r), darkCurve(g), darkCurve(b)],
    },
    'stress-satclip': {
        title: 'CF7 LUT Lab stress saturation clip',
        fn: (r, g, b) => {
            const luma = luma709(r, g, b);
            return [
                clamp01(luma + (r - luma) * 2.2),
                clamp01(luma + (g - luma) * 2.2),
                clamp01(luma + (b - luma) * 2.2),
            ];
        },
    },
};

function generateLut(kind) {
    const generator = GENERATORS[kind];
    if (!generator) {
        const known = Object.keys(GENERATORS).join(' / ');
        throw new Error(`未知 LUT 种类：${kind}（可用：${known}）`);
    }
    const lut = buildLut(32, generator.fn);
    lut.title = generator.title;
    return lut;
}

// 逐节点线性混合两个同尺寸同 domain 的 LUT：out = a*(1-t) + b*t。
// 供 make-set 按等级语义生成斜坡集合（如 恒等→夜视绿 强度 ramp）。
function blendLut(a, b, t) {
    if (a.size !== b.size) throw new Error(`blendLut 需要同尺寸（${a.size} vs ${b.size}）`);
    if (t < 0 || t > 1) throw new Error(`blendLut t 越界：${t}`);
    const out = buildLut(a.size, () => [0, 0, 0]);
    for (let i = 0; i < out.data.length; i += 1) {
        out.data[i] = a.data[i] * (1 - t) + b.data[i] * t;
    }
    out.title = `blend(${(a.title || 'a')} → ${(b.title || 'b')}, t=${t})`;
    return out;
}

module.exports = {
    REC709,
    clamp01,
    luma709,
    sampleLut,
    resampleTo32,
    buildLut,
    blendLut,
    generateLut,
    GENERATOR_KINDS: Object.keys(GENERATORS),
};
