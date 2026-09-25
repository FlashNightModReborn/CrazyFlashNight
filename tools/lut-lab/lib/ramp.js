'use strict';

// 参数化昼夜 ramp 生成器（v1 · 仅「光照」模式，不做夜视族）。
//
// 权威时间映射（scripts/类定义/org/flashNight/arki/weather/WeatherSystem.as:138 核实）：
//   dayNightLightLevels = [0,0,1,4,7,7,7,7,7,7,7,7,9,7,7,7,7,7,7,4,1,0,0,0]（索引=小时）
//   L0=深夜(21–01)、L1=夜(20/02)、L4=晨昏点(03/19)、L7=白天恒等(04–18)、L9=正午(12)；
//   L2/L3/L5/L6/L8 为相邻整点间的小数级插值扫过档，是过渡平滑性的主要承载档。
//
// 管线（逐 texel，输入 sRGB 0–1）：
//   1) sRGB 解码 → 线性
//   2) 曝光 ×2^EV
//   3) 白平衡 RGB 增益（色温偏移；Tanner Helland 的 Planckian 经验近似拟合，
//      见 temperatureToRgb 注——近似非精确黑体解，偏移量以 6500K 为中性点、luma 归一）
//   4) sRGB 重编码
//   5) 饱和（Rec.709 luma 向灰度 lerp；负值降饱和）
//   6) Purkinje（t<4 时 R 通道向 luma 额外靠拢指定比例）
//   7) 对比形态（split-tone 暗部冷/高光暖双区 → toe 压暗 → 中调压缩 →
//      高光 shoulder 滚降 + 高光区降饱和）
//   8) clamp01
//
// 曲线连续性：四通道参数在 t 上分段 smoothstep(u)=u²(3−2u) 连续，整数档采样。
// 自检（本文件 selfCheck）覆盖：L7 逐字节恒等、全档灰阶 luma 随等级单调不降、
// 同参数重跑 SHA-256 一致。

const { clamp01, luma709, REC709 } = require('./lut');

// ---------- sRGB 传递函数 ----------

function srgbDecode(c) {
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function srgbEncode(c) {
    return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}

function smoothstep(a, b, x) {
    if (a === b) return x < a ? 0 : 1;
    const u = clamp01((x - a) / (b - a));
    return u * u * (3 - 2 * u);
}

// ---------- 白平衡（Tanner Helland 近似） ----------

// 色温 → RGB 增益：Tanner Helland 对 Planckian 轨迹的经验近似拟合
// （https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm.html；
//   近似非精确黑体解。本处只用相对 6500K 中性点的偏移增益并 luma 归一，
//   近似误差在 dev 工具可接受范围）。
function clamp255(v) { return v < 0 ? 0 : v > 255 ? 255 : v; }

function temperatureToRgb(kelvin) {
    const t = Math.max(1000, Math.min(40000, kelvin)) / 100;
    const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
    const g = t <= 66
        ? 99.4708025861 * Math.log(t) - 161.1195681661
        : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
    const b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307);
    return [clamp255(r), clamp255(g), clamp255(b)];
}

// 色温偏移 ΔK → RGB 增益。负偏移 = 视觉更冷（更高 CCT）：T = 6500 − ΔK。
// 增益以 6500K 为中性点归一，并做 luma 归一（明度统一由 EV 承载，色温不改明度）。
function whiteBalanceGains(deltaK) {
    if (!deltaK) return [1, 1, 1];
    const t = Math.max(1000, Math.min(40000, 6500 - deltaK));
    const neutral = temperatureToRgb(6500);
    const target = temperatureToRgb(t);
    const gains = [target[0] / neutral[0], target[1] / neutral[1], target[2] / neutral[2]];
    const luma = REC709[0] * gains[0] + REC709[1] * gains[1] + REC709[2] * gains[2];
    return gains.map((v) => v / luma);
}

// ---------- 配方（v1 第一版候选） ----------

// 对比形态参数说明：
//   toe      低区压暗曲线强度（防伽马破解：近黑压向真黑）
//   midComp  以中灰 0.5 为轴的中调压缩强度
//   shoulder 高光滚降强度（soft-knee；亮度滚降经灰阶单调性标定，见 calibrationNote）
//   hiDesat  高光区额外降饱和（L9「过曝脱色」的主要承载；不改变 luma，保住单调性）
//   splitTone L5 专用：暗部冷 / 高光暖双区偏移强度
//   purkinje 低等级红通道向 luma 额外靠拢比例（Purkinje 红额外衰减的简化）
const RECIPES = {
    'natural-daynight-v1': {
        name: 'natural-daynight-v1',
        title: '自然昼夜 ramp v1 候选（验收用）',
        mode: '光照',
        filePrefix: '光照',
        manifestNote: 'bake-ramp v1 候选，验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: 'L9 shoulder 亮度滚降经灰阶单调性标定（上限约 0.44），「过曝脱色」主要由高光区降饱和（hiDesat 0.6）承载；L8 为轻 shoulder（0.30）。',
        anchors: [
            { ev: -5.0, tempK: -5000, satPct: -70, toe: 0.85, midComp: 0.35, shoulder: 0,    hiDesat: 0,   splitTone: 0, purkinje: 1.0 },
            { ev: -4.2, tempK: -4500, satPct: -60, toe: 0.65, midComp: 0.30, shoulder: 0,    hiDesat: 0,   splitTone: 0, purkinje: 1.0 },
            { ev: -3.2, tempK: -4000, satPct: -45, toe: 0.25, midComp: 0.80, shoulder: 0,    hiDesat: 0,   splitTone: 0, purkinje: 1.0 },
            { ev: -2.3, tempK: -3000, satPct: -30, toe: 0.10, midComp: 0.50, shoulder: 0,    hiDesat: 0,   splitTone: 0, purkinje: 0.15 },
            { ev: -1.5, tempK: -1500, satPct: -15, toe: 0.05, midComp: 0.25, shoulder: 0,    hiDesat: 0,   splitTone: 0, purkinje: 0.08 },
            { ev: -0.9, tempK: +1800, satPct: +5,  toe: 0.05, midComp: 0.10, shoulder: 0,    hiDesat: 0,   splitTone: 1, purkinje: 0 },
            { ev: -0.4, tempK: +800,  satPct: +3,  toe: 0,    midComp: 0,    shoulder: 0,    hiDesat: 0,   splitTone: 0, purkinje: 0 },
            { ev: 0,    tempK: 0,     satPct: 0,   toe: 0,    midComp: 0,    shoulder: 0,    hiDesat: 0,   splitTone: 0, purkinje: 0 },
            { ev: +0.15, tempK: +400, satPct: 0,   toe: 0,    midComp: 0,    shoulder: 0.30, hiDesat: 0.2, splitTone: 0, purkinje: 0 },
            { ev: +0.4, tempK: +400,  satPct: -5,  toe: 0,    midComp: 0,    shoulder: 0.42, hiDesat: 0.6, splitTone: 0, purkinje: 0 },
        ],
    },
    // ── v2「钢蓝硬派」：6 锚点结构 + 三条风味通道 ──
    // 6 锚点：L0/L1/L4/L5/L7/L9；非锚点档 L2/L3/L6/L8 由相邻锚点参数空间插值生成
    // （生成器路径语义：参数连续则曲线相干，跨度均 ≤3 级；与面板手工预设的 LUT 级 blend 不同，见 preset.json）。
    // 黑位延续 v1 的 toe 压死（L0/L1 防伽马破解）。
    'natural-daynight-v2': {
        name: 'natural-daynight-v2',
        title: '自然昼夜 ramp v2「钢蓝硬派」（bake-ramp v2 候选）',
        mode: '光照',
        filePrefix: '光照',
        manifestNote: 'bake-ramp v2 候选「钢蓝硬派」，验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.25,
        calibrationNote: '6 锚点结构；shoulder 沿用 v1 幂次滚降白点保持标定；黑位延续 v1 toe 压死（L0/L1 防伽马破解）。'
            + '三条风味通道：全等级 split-tone（暗部/高光成对）、暖色豁免（340°–60° 窗口，L7 恒零）、'
            + '银蓝夜高光（≤L4 保 luma 定向月白银蓝）。',
        anchors: [
            { // L0 深夜：暗部钢蓝 + 月白银蓝高光 + 暖色豁免（灯火保暖）
                ev: -5.0, tempK: -5000, satPct: -70, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 215, strength: 0.35 }, splitHigh: { hue: 215, strength: 0.05 },
                warmProtect: 0.90, warmResidual: 0, silverHigh: { hue: 210, strength: 0.35 }, blackLift: 0,
            },
            { // L1 夜：钢蓝减弱、豁免略降
                ev: -4.2, tempK: -4500, satPct: -60, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 215, strength: 0.30 }, splitHigh: { hue: 215, strength: 0.04 },
                warmProtect: 0.85, warmResidual: 0, silverHigh: { hue: 210, strength: 0.30 }, blackLift: 0,
            },
            { // L4 晨昏点：暗部青 + 高光残暖，豁免保留
                ev: -1.5, tempK: -1500, satPct: -15, toe: 0.05, midComp: 0.25, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.20 }, splitHigh: { hue: 30, strength: 0.12 },
                warmProtect: 0.50, warmResidual: 0, silverHigh: { hue: 210, strength: 0.15 }, blackLift: 0,
            },
            { // L5 晨昏过渡扫过区（暖调带）：青阴影 + 暖高光，无豁免
                ev: -0.9, tempK: +1800, satPct: +5, toe: 0.05, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.10 }, splitHigh: { hue: 35, strength: 0.10 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 210, strength: 0 }, blackLift: 0,
            },
            { // L7 白天恒等：全参数零（硬断言逐字节恒等）
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 210, strength: 0 }, splitHigh: { hue: 40, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 210, strength: 0 }, blackLift: 0,
            },
            { // L9 正午：高光微暖白 + 过曝脱色（幂次滚降白点保持）
                ev: +0.4, tempK: +400, satPct: -5, toe: 0, midComp: 0, shoulder: 0.42, hiDesat: 0.6, purkinje: 0,
                splitShadow: { hue: 215, strength: 0.05 }, splitHigh: { hue: 40, strength: 0.10 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 210, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── v2m「城市奶灰」：与 v2 共享锚点结构，仅黑位/对比/暖色残存不同 ──
    // 黑位略抬升（奶灰底，blackLift 近黑提升曲线）+ 对比微降（EV/midComp 收拢、toe 不压死）
    // + 暖色区残存更多饱和（warmResidual 叠加豁免，混合光源感）；L0 仍须足够暗（l0LumaCeiling 不破）。
    //
    // 黑位与单调性的结构性取舍（设计注明）：纯黑灰阶处 EV 增益为零贡献，任何「低等级抬黑、
    // 高等级回纯黑（L7 恒等）」的黑位都必然在淡出边界产生近黑回落。本变体把 blackLift 设计为
    // 缓出曲线（L0=L1 持平，L4/L5 缓降，L6 起为 0），单级回落 ≤0.006（≈1.5/255），
    // 且仅落在近黑灰阶（≤0.1）——作为 fadeAllowance 受控回落写入自检（非静默放行，见 calibrationNote）。
    'natural-daynight-v2m': {
        name: 'natural-daynight-v2m',
        title: '自然昼夜 ramp v2m「城市奶灰」（bake-ramp v2 候选）',
        mode: '光照',
        filePrefix: '光照',
        manifestNote: 'bake-ramp v2 候选「城市奶灰」，验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.32,
        // 黑位淡出段的受控回落许可（结构性，见本配方头部注释）：仅近黑灰阶、单级 ≤0.006
        fadeAllowance: { maxGray: 0.1, maxDrop: 0.0061 },
        calibrationNote: '6 锚点结构（同 v2）；黑位略抬升（奶灰底 blackLift，近黑提升、0.35 以上不动）+ 对比微降'
            + '（EV 收拢、midComp 降低、toe 不压死）+ 暖色残存更多饱和（warmResidual 叠加豁免，混合光源感）；'
            + '黑位缓出曲线：L0=L1 持平、L4/L5 缓降、L6 起为 0——近黑（≤0.1）单级回落 ≤0.006（≈1.5/255），'
            + '属结构性取舍（低等级抬黑与 L7 恒等不可兼得），已用 fadeAllowance 显式记录而非静默放行；'
            + 'L0 顶灰 luma ≤ 0.32（刚需线不破，实测见自检表）。',
        anchors: [
            {
                ev: -4.6, tempK: -5000, satPct: -55, toe: 0.15, midComp: 0.20, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 215, strength: 0.35 }, splitHigh: { hue: 215, strength: 0.05 },
                warmProtect: 0.75, warmResidual: 0.20, silverHigh: { hue: 210, strength: 0.30 }, blackLift: 0.020,
            },
            {
                ev: -3.9, tempK: -4500, satPct: -48, toe: 0.10, midComp: 0.18, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 215, strength: 0.30 }, splitHigh: { hue: 215, strength: 0.04 },
                warmProtect: 0.70, warmResidual: 0.20, silverHigh: { hue: 210, strength: 0.25 }, blackLift: 0.020,
            },
            {
                ev: -1.4, tempK: -1500, satPct: -10, toe: 0.03, midComp: 0.15, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.20 }, splitHigh: { hue: 30, strength: 0.12 },
                warmProtect: 0.55, warmResidual: 0.10, silverHigh: { hue: 210, strength: 0.12 }, blackLift: 0.016,
            },
            {
                ev: -0.9, tempK: +1800, satPct: +5, toe: 0.02, midComp: 0.08, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.10 }, splitHigh: { hue: 35, strength: 0.10 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 210, strength: 0 }, blackLift: 0.012,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 210, strength: 0 }, splitHigh: { hue: 40, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 210, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.4, tempK: +400, satPct: -5, toe: 0, midComp: 0, shoulder: 0.42, hiDesat: 0.6, purkinje: 0,
                splitShadow: { hue: 215, strength: 0.05 }, splitHigh: { hue: 40, strength: 0.10 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 210, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── 青橙电影族：全等级青（暗部 ≈190°）/橙（高光 ≈30°）对撞 ──
    // 设计意图：比 v2 的日常自然更风格化——白天也带轻微青橙；夜晚暖色保护加强
    // （火光/灯光是青橙体系的主角，warmProtect 高于 v2）。参考：商业电影青橙分级惯例。
    'cinematic-teal-orange-v1': {
        name: 'cinematic-teal-orange-v1',
        title: '青橙电影族 v1（bake-ramp 族扩，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.28,
        manifestNote: '青橙电影族 v1（bake-ramp 族扩），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: '青（暗部 ≈190°）/橙（高光 ≈30°）全等级对撞，白天（L9）也带轻微青橙；'
            + '暖色保护强于 v2（火光/灯光是主角）；shoulder 沿用幂次滚降白点保持标定。',
        anchors: [
            {
                ev: -5.0, tempK: -4800, satPct: -55, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.40 }, splitHigh: { hue: 30, strength: 0.20 },
                warmProtect: 0.95, warmResidual: 0, silverHigh: { hue: 205, strength: 0.30 }, blackLift: 0,
            },
            {
                ev: -4.0, tempK: -4200, satPct: -48, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.35 }, splitHigh: { hue: 30, strength: 0.18 },
                warmProtect: 0.92, warmResidual: 0, silverHigh: { hue: 205, strength: 0.25 }, blackLift: 0,
            },
            {
                ev: -1.4, tempK: -1200, satPct: -12, toe: 0.05, midComp: 0.22, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.25 }, splitHigh: { hue: 30, strength: 0.22 },
                warmProtect: 0.60, warmResidual: 0, silverHigh: { hue: 205, strength: 0.10 }, blackLift: 0,
            },
            {
                ev: -0.8, tempK: +1600, satPct: +6, toe: 0.05, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.15 }, splitHigh: { hue: 30, strength: 0.15 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.4, tempK: +400, satPct: -3, toe: 0, midComp: 0, shoulder: 0.42, hiDesat: 0.5, purkinje: 0,
                splitShadow: { hue: 195, strength: 0.12 }, splitHigh: { hue: 32, strength: 0.15 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── 漂白硬派族：军事纪录感 ──
    // 设计意图：全等级降饱和（白天 −20 起步、夜档近乎单色灰绿）、银灰高光（低 chroma tint）、
    // 中调偏绿灰、对比偏高；toe 压死保留（防伽马破解）。
    // 约束：「降饱和 −20 起步」曲线在 t=7 处必须归零——由锚点结构保证（L7 全零，L7 逐字节恒等不破）。
    'war-bleach-v1': {
        name: 'war-bleach-v1',
        title: '漂白硬派族 v1（bake-ramp 族扩，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.22,
        manifestNote: '漂白硬派族 v1（bake-ramp 族扩），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: '漂白语义：降饱和从夜档单色灰绿（−75）向白天（−20）收拢、L7 归零（锚点结构保证恒等断言不破）；'
            + '银灰高光用低 chroma tint（chroma≈0.2–0.3）；中调偏绿灰（splitShadow hue≈150°）；'
            + '暖色豁免弱（硬派漂白连暖色也压）；toe 压死保留。',
        anchors: [
            {
                ev: -5.2, tempK: -3500, satPct: -75, toe: 0.85, midComp: 0.45, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 150, strength: 0.22 }, splitHigh: { hue: 210, strength: 0.06 },
                warmProtect: 0.35, warmResidual: 0, silverHigh: { hue: 205, strength: 0.25, chroma: 0.3 }, blackLift: 0,
            },
            {
                ev: -4.4, tempK: -3000, satPct: -70, toe: 0.65, midComp: 0.40, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 150, strength: 0.18 }, splitHigh: { hue: 210, strength: 0.05 },
                warmProtect: 0.30, warmResidual: 0, silverHigh: { hue: 205, strength: 0.20, chroma: 0.3 }, blackLift: 0,
            },
            {
                ev: -1.6, tempK: -1000, satPct: -30, toe: 0.05, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 150, strength: 0.12 }, splitHigh: { hue: 210, strength: 0.04 },
                warmProtect: 0.20, warmResidual: 0, silverHigh: { hue: 205, strength: 0.08, chroma: 0.25 }, blackLift: 0,
            },
            {
                ev: -0.9, tempK: +900, satPct: -15, toe: 0.05, midComp: 0.15, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 150, strength: 0.08 }, splitHigh: { hue: 210, strength: 0.03 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 150, strength: 0 }, splitHigh: { hue: 210, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.35, tempK: +200, satPct: -20, toe: 0, midComp: 0, shoulder: 0.50, hiDesat: 0.5, purkinje: 0,
                splitShadow: { hue: 150, strength: 0.06 }, splitHigh: { hue: 210, strength: 0.06, chroma: 0.2 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── 胶片印刷族：Kodak 2383 式 S 曲线骨架 ──
    // 设计意图：明显 toe+shoulder 的 S 曲线为全域响应骨架（印刷胶片感），
    // 整体轻微印刷色相偏移（高光暖 ≈35° / 暗部青绿 ≈165°），曝光轴沿用 v1；目标观感「胶片感白天」。
    'film-print-v1': {
        name: 'film-print-v1',
        title: '胶片印刷族 v1（bake-ramp 族扩，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.28,
        manifestNote: '胶片印刷族 v1（bake-ramp 族扩），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: 'S 曲线骨架：全域 toe（印刷软压非压死）+ L9 shoulder 0.35（幂次滚降白点保持）；'
            + '印刷色相偏移：splitShadow 青绿 ≈165° / splitHigh 暖 ≈35°；EV 轴沿用 v1。',
        anchors: [
            {
                ev: -5.0, tempK: -2500, satPct: -55, toe: 0.45, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 165, strength: 0.15 }, splitHigh: { hue: 35, strength: 0.10 },
                warmProtect: 0.70, warmResidual: 0, silverHigh: { hue: 200, strength: 0.20 }, blackLift: 0,
            },
            {
                ev: -4.2, tempK: -2200, satPct: -48, toe: 0.35, midComp: 0.28, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 165, strength: 0.13 }, splitHigh: { hue: 35, strength: 0.09 },
                warmProtect: 0.65, warmResidual: 0, silverHigh: { hue: 200, strength: 0.15 }, blackLift: 0,
            },
            {
                ev: -1.5, tempK: -600, satPct: -15, toe: 0.12, midComp: 0.20, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 165, strength: 0.10 }, splitHigh: { hue: 35, strength: 0.08 },
                warmProtect: 0.45, warmResidual: 0, silverHigh: { hue: 200, strength: 0.05 }, blackLift: 0,
            },
            {
                ev: -0.9, tempK: +1200, satPct: +4, toe: 0.08, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 165, strength: 0.08 }, splitHigh: { hue: 35, strength: 0.08 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 200, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 165, strength: 0 }, splitHigh: { hue: 35, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 200, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.4, tempK: +400, satPct: -8, toe: 0.08, midComp: 0, shoulder: 0.35, hiDesat: 0.4, purkinje: 0,
                splitShadow: { hue: 165, strength: 0.08 }, splitHigh: { hue: 35, strength: 0.10 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 200, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── 霓虹城市族：城市夜场主打 ──
    // 设计意图：黑位抬（奶灰底，参 v2m）；夜档暗部青/品红双色倾向
    // （splitShadow 青 ≈190° × splitShadow2 品红 ≈320°，按 luma 插值——深影偏青、亮影偏品红）；
    // 高光允许更艳（splitHigh 品红 ≈300°）；暖色保护收窄到纯橙（{corePos:35, coreNeg:-5, feather:8}，
    // 让品红/青霓虹自由发挥）；白天档相对收敛（这族主打夜场）。
    'neon-city-v1': {
        name: 'neon-city-v1',
        title: '霓虹城市族 v1（bake-ramp 族扩，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.32,
        fadeAllowance: { maxGray: 0.1, maxDrop: 0.0061 },
        warmWindow: { corePos: 35, coreNeg: -5, feather: 8 },
        manifestNote: '霓虹城市族 v1（bake-ramp 族扩），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: '夜场主打：黑位抬（奶灰底 blackLift 缓出，近黑回落 ≤0.006/级，fadeAllowance 显式标注）；'
            + '暗部青/品红双色倾向（splitShadow2 实验：w2=smoothstep(0.15,0.55,luma)×strength，深影偏青亮影偏品红）；'
            + '高光品红 ≈300° 允许更艳；暖窗收窄到纯橙（让品红/青霓虹自由发挥）；白天收敛。',
        anchors: [
            {
                ev: -4.2, tempK: -3500, satPct: -45, toe: 0.10, midComp: 0.20, shoulder: 0, hiDesat: 0, purkinje: 0.8,
                splitShadow: { hue: 190, strength: 0.30 }, splitShadow2: { hue: 320, strength: 0.25 },
                splitHigh: { hue: 300, strength: 0.15 },
                warmProtect: 0.85, warmResidual: 0, silverHigh: { hue: 280, strength: 0.25 }, blackLift: 0.025,
            },
            {
                ev: -3.6, tempK: -3000, satPct: -40, toe: 0.08, midComp: 0.18, shoulder: 0, hiDesat: 0, purkinje: 0.8,
                splitShadow: { hue: 190, strength: 0.28 }, splitShadow2: { hue: 320, strength: 0.22 },
                splitHigh: { hue: 300, strength: 0.12 },
                warmProtect: 0.80, warmResidual: 0, silverHigh: { hue: 280, strength: 0.20 }, blackLift: 0.020,
            },
            {
                ev: -1.3, tempK: -800, satPct: -12, toe: 0.03, midComp: 0.15, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.15 }, splitShadow2: { hue: 320, strength: 0.10 },
                splitHigh: { hue: 35, strength: 0.10 },
                warmProtect: 0.55, warmResidual: 0, silverHigh: { hue: 280, strength: 0.05 }, blackLift: 0.014,
            },
            {
                ev: -0.9, tempK: +1600, satPct: +4, toe: 0.02, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.08 }, splitShadow2: { hue: 320, strength: 0 },
                splitHigh: { hue: 35, strength: 0.10 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 280, strength: 0 }, blackLift: 0.010,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitShadow2: { hue: 320, strength: 0 },
                splitHigh: { hue: 35, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 280, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.35, tempK: +300, satPct: -3, toe: 0, midComp: 0, shoulder: 0.40, hiDesat: 0.5, purkinje: 0,
                splitShadow: { hue: 200, strength: 0.05 }, splitShadow2: { hue: 320, strength: 0 },
                splitHigh: { hue: 35, strength: 0.08 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 280, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── 青橙电影族细化变体（维护者验收拍板：cinematic-teal-orange 最有潜力，族内出三变体定稿 A/B）──
    // 公共约束（三变体一致）：暖色豁免沿用 v1 强度（warmProtect .95/.92/.60/0/0/0，族核心资产）；
    // L7 恒等锚点逐字节不破；L0/L1 顶灰刚需线沿用族线 0.28；EV/色温/饱和/toe/midComp/shoulder/
    // hiDesat/Purkinje 与 v1 逐参数一致——变体差异只落在 split-tone（与 silverHigh，仅 v2c）强度曲线。
    // 注：L6/L8 为插值档（L6=L5 之半、L8=L9 之半，锚点结构决定），白天收敛动作只能落在 L9 锚点。
    //
    // ── v2a「均衡」：白天档青橙收敛，保护肤色与白天可读性（青橙主场在晨昏与夜）──
    'cinematic-teal-orange-v2a': {
        name: 'cinematic-teal-orange-v2a',
        title: '青橙电影族 v2a「均衡」（bake-ramp 族扩细化，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.28,
        manifestNote: '青橙电影族 v2a「均衡」（bake-ramp 族扩细化），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: '与 v1 差异：仅 L9 锚点 split 收敛约一半（splitShadow 0.12→0.06、splitHigh 0.15→0.07）；'
            + 'L8 随插值自动收敛（=L9 之半），L6 结构性 =L5 之半（锚点结构决定）；'
            + '夜档 L0/L1 与晨昏 L4/L5 与 v1 逐参数一致；暖色豁免沿用 v1。定位：白天可读性优先的默认候选。',
        anchors: [
            {
                ev: -5.0, tempK: -4800, satPct: -55, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.40 }, splitHigh: { hue: 30, strength: 0.20 },
                warmProtect: 0.95, warmResidual: 0, silverHigh: { hue: 205, strength: 0.30 }, blackLift: 0,
            },
            {
                ev: -4.0, tempK: -4200, satPct: -48, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.35 }, splitHigh: { hue: 30, strength: 0.18 },
                warmProtect: 0.92, warmResidual: 0, silverHigh: { hue: 205, strength: 0.25 }, blackLift: 0,
            },
            {
                ev: -1.4, tempK: -1200, satPct: -12, toe: 0.05, midComp: 0.22, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.25 }, splitHigh: { hue: 30, strength: 0.22 },
                warmProtect: 0.60, warmResidual: 0, silverHigh: { hue: 205, strength: 0.10 }, blackLift: 0,
            },
            {
                ev: -0.8, tempK: +1600, satPct: +6, toe: 0.05, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.15 }, splitHigh: { hue: 30, strength: 0.15 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.4, tempK: +400, satPct: -3, toe: 0, midComp: 0, shoulder: 0.42, hiDesat: 0.5, purkinje: 0,
                splitShadow: { hue: 195, strength: 0.06 }, splitHigh: { hue: 32, strength: 0.07 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── v2b「夜重」：split-tone 曲线向夜倾斜——L5 及以下全强度，L6 起快速衰减，L8/L9 接近干净 ──
    'cinematic-teal-orange-v2b': {
        name: 'cinematic-teal-orange-v2b',
        title: '青橙电影族 v2b「夜重」（bake-ramp 族扩细化，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.28,
        manifestNote: '青橙电影族 v2b「夜重」（bake-ramp 族扩细化），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: '与 v1 差异：L0–L5 与 v1 逐参数一致（夜档全火力、晨昏全强度）；'
            + 'L9 split 收敛到 0.02/0.025（接近干净，白天档几乎只剩 shoulder 0.42 + hiDesat 0.5）；'
            + 'L6 起结构性快速衰减（=L5 之半 → L7 恒等零），L8≈0.01；暖色豁免沿用 v1。'
            + '取向：白天读图优先、夜晚风格拉满。',
        anchors: [
            {
                ev: -5.0, tempK: -4800, satPct: -55, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.40 }, splitHigh: { hue: 30, strength: 0.20 },
                warmProtect: 0.95, warmResidual: 0, silverHigh: { hue: 205, strength: 0.30 }, blackLift: 0,
            },
            {
                ev: -4.0, tempK: -4200, satPct: -48, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.35 }, splitHigh: { hue: 30, strength: 0.18 },
                warmProtect: 0.92, warmResidual: 0, silverHigh: { hue: 205, strength: 0.25 }, blackLift: 0,
            },
            {
                ev: -1.4, tempK: -1200, satPct: -12, toe: 0.05, midComp: 0.22, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.25 }, splitHigh: { hue: 30, strength: 0.22 },
                warmProtect: 0.60, warmResidual: 0, silverHigh: { hue: 205, strength: 0.10 }, blackLift: 0,
            },
            {
                ev: -0.8, tempK: +1600, satPct: +6, toe: 0.05, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.15 }, splitHigh: { hue: 30, strength: 0.15 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.4, tempK: +400, satPct: -3, toe: 0, midComp: 0, shoulder: 0.42, hiDesat: 0.5, purkinje: 0,
                splitShadow: { hue: 195, strength: 0.02 }, splitHigh: { hue: 32, strength: 0.025 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── v2c「强风格」：chroma 比 v1 再推进一步（split 全锚点 ×1.2），白天档也给足青橙，探风格上限 ──
    'cinematic-teal-orange-v2c': {
        name: 'cinematic-teal-orange-v2c',
        title: '青橙电影族 v2c「强风格」（bake-ramp 族扩细化，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 7, 9],
        l0LumaCeiling: 0.28,
        manifestNote: '青橙电影族 v2c「强风格」（bake-ramp 族扩细化），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: '与 v1 差异：全部 split-tone 强度 ×1.2（chroma +20%：L0 .48/.24、L1 .42/.216、'
            + 'L4 .30/.264、L5 .18/.18、L9 splitShadow .144），silverHigh 同步 ×1.2（.36/.30/.12）；'
            + '白天档 L9 给足暗部青/高光暖；L7 恒等锚点逐字节不破；暖色豁免沿用 v1。'
            + '标定记录：L9 splitHigh 原计划 ×1.2（0.18），实测白点凹陷 0.001409 超既有 0.001 许可边界，'
            + '收敛到 0.16（凹陷 0.000896，许可内逐处标注；白点不受 splitShadow 影响，0.144 维持 ×1.2）。'
            + '定位：风格上限探针。',
        anchors: [
            {
                ev: -5.0, tempK: -4800, satPct: -55, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.48 }, splitHigh: { hue: 30, strength: 0.24 },
                warmProtect: 0.95, warmResidual: 0, silverHigh: { hue: 205, strength: 0.36 }, blackLift: 0,
            },
            {
                ev: -4.0, tempK: -4200, satPct: -48, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.42 }, splitHigh: { hue: 30, strength: 0.216 },
                warmProtect: 0.92, warmResidual: 0, silverHigh: { hue: 205, strength: 0.30 }, blackLift: 0,
            },
            {
                ev: -1.4, tempK: -1200, satPct: -12, toe: 0.05, midComp: 0.22, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.30 }, splitHigh: { hue: 30, strength: 0.264 },
                warmProtect: 0.60, warmResidual: 0, silverHigh: { hue: 205, strength: 0.12 }, blackLift: 0,
            },
            {
                ev: -0.8, tempK: +1600, satPct: +6, toe: 0.05, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.18 }, splitHigh: { hue: 30, strength: 0.18 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.4, tempK: +400, satPct: -3, toe: 0, midComp: 0, shoulder: 0.42, hiDesat: 0.5, purkinje: 0,
                splitShadow: { hue: 195, strength: 0.144 }, splitHigh: { hue: 32, strength: 0.16 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // ── 青橙 v3「黄昏橙峰 + 正午重构」（维护者结构化反馈：白天干净 / 黄昏橙峰极值 / 入夜青蓝纯净 /
    //    正午三形态重选 / 夜档刚需线收紧到「没法打」）──
    // 主干（v3a/b/c 共享，仅 L9 锚点不同）：
    //  · 7 锚点 [0/1/4/5/6/7/9]——L6 由插值档升级为显式近零锚（任务要求「L6 快速衰减到近零」，
    //    6 锚点结构下 L6 恒等于 L5 之半，与 L5 橙峰极值数学互斥；原 6 锚位语义与 L7 恒等不变，
    //    preset.json structure 如实记录 7 锚点）。
    //  · 黄昏橙峰：L5 splitHigh 暖橙 0.30（=2×v1，≥1.5× 目标）；L4 暖侧增强 0.22→0.26；
    //    L6 split 近零。注：白点凹陷在 L5 不构成上限——split 增益合并向量 luma 归一，
    //    对灰阶精确保 luma，且 L4/L5 锚点 shoulder=0（凹陷只发生在 split×shoulder 交互的
    //    L8/L9）；L5=0.30 的上限是感知层面的（A/B 验收内容），非自检约束。
    //  · 夜档青蓝纯净：L0/L1 splitHigh 由暖 30° 改冷银蓝 205°（0.12/0.10），splitShadow
    //    钢青 190° 保持；暖只经暖色豁免（0.95/0.92 沿用 v1）留给火光/灯光；不加全局暖。
    //  · 刚需线收紧：L0 EV −5.0→−5.5、L1 −4.0→−4.8（任务给 −4.7 约数，实测 −4.7 顶灰 0.227
    //    微超 0.22 线，微调 −4.8 → 0.2155）；toe 压死保持；l0LumaCeiling 0.15 / l1LumaCeiling 0.22。
    //  · L6 锚点其余参数 = L5/L7 中点（EV −0.4、tempK +800、sat +3、toe 0.025、midComp 0.05），
    //    与 v2a 在 L6 的插值结果一致——v3 影调主干除 split 曲线外与 v2a 全等。
    'cinematic-dusk-peak-v3a': {
        name: 'cinematic-dusk-peak-v3a',
        title: '青橙黄昏峰 v3a「轻过曝正午」（bake-ramp v3 候选，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 6, 7, 9],
        l0LumaCeiling: 0.15,
        l1LumaCeiling: 0.22,
        manifestNote: '青橙黄昏峰 v3a「轻过曝正午」（bake-ramp v3 候选），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: 'v3 主干：7 锚点（L6 显式近零锚，见 ramp.js 族注释）；黄昏橙峰 L5 splitHigh 0.30（2×v1）、'
            + 'L4 0.26；夜档 splitHigh 改冷银蓝 205°；L0/L1 EV 收紧 −5.5/−4.8（顶灰 0.132/0.216，'
            + '刚需线 ≤0.15/≤0.22）；暖色豁免沿用 v1。'
            + '与 v1/v2 系结构差异：7 锚点（新增 L6 显式锚）、夜档 splitHigh 转冷、夜档 EV 收紧、L9 三形态之一。'
            + 'v3a 正午=轻过曝脱色：shoulder 0.38 + hiDesat 0.55（现行 0.42/0.5 附近的太弱-太强中点），'
            + 'split 收敛同 v2a（0.06/0.07，白天干净）。',
        anchors: [
            {
                ev: -5.5, tempK: -4800, satPct: -55, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.40 }, splitHigh: { hue: 205, strength: 0.12 },
                warmProtect: 0.95, warmResidual: 0, silverHigh: { hue: 205, strength: 0.30 }, blackLift: 0,
            },
            {
                ev: -4.8, tempK: -4200, satPct: -48, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.35 }, splitHigh: { hue: 205, strength: 0.10 },
                warmProtect: 0.92, warmResidual: 0, silverHigh: { hue: 205, strength: 0.25 }, blackLift: 0,
            },
            {
                ev: -1.4, tempK: -1200, satPct: -12, toe: 0.05, midComp: 0.22, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.25 }, splitHigh: { hue: 30, strength: 0.26 },
                warmProtect: 0.60, warmResidual: 0, silverHigh: { hue: 205, strength: 0.10 }, blackLift: 0,
            },
            {
                ev: -0.8, tempK: +1600, satPct: +6, toe: 0.05, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.15 }, splitHigh: { hue: 30, strength: 0.30 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: -0.4, tempK: +800, satPct: +3, toe: 0.025, midComp: 0.05, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.4, tempK: +400, satPct: -4, toe: 0, midComp: 0, shoulder: 0.38, hiDesat: 0.55, purkinje: 0,
                splitShadow: { hue: 195, strength: 0.06 }, splitHigh: { hue: 32, strength: 0.07 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // v3b 正午=硬光：中调微对比提升（midComp 负值，引擎本轮起支持）+ 强 shoulder + 高光微暖白、降饱和减弱
    'cinematic-dusk-peak-v3b': {
        name: 'cinematic-dusk-peak-v3b',
        title: '青橙黄昏峰 v3b「硬光正午」（bake-ramp v3 候选，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 6, 7, 9],
        l0LumaCeiling: 0.15,
        l1LumaCeiling: 0.22,
        manifestNote: '青橙黄昏峰 v3b「硬光正午」（bake-ramp v3 候选），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: 'v3 主干同 v3a（7 锚点 / 黄昏橙峰 L5 0.30 / 夜档冷银蓝 splitHigh / EV 收紧 −5.5/−4.8）。'
            + '与 v1/v2 系结构差异同 v3a；v3b 正午=硬光：midComp −0.08（中调微对比提升，负值本轮引擎新增）、'
            + 'shoulder 0.55（强）+ hiDesat 0.25（降饱和减弱——「阳光很硬」而非「画面很灰」）、'
            + 'tempK +500 高光微暖白、EV +0.5；split 收敛同 v2a。',
        anchors: [
            {
                ev: -5.5, tempK: -4800, satPct: -55, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.40 }, splitHigh: { hue: 205, strength: 0.12 },
                warmProtect: 0.95, warmResidual: 0, silverHigh: { hue: 205, strength: 0.30 }, blackLift: 0,
            },
            {
                ev: -4.8, tempK: -4200, satPct: -48, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.35 }, splitHigh: { hue: 205, strength: 0.10 },
                warmProtect: 0.92, warmResidual: 0, silverHigh: { hue: 205, strength: 0.25 }, blackLift: 0,
            },
            {
                ev: -1.4, tempK: -1200, satPct: -12, toe: 0.05, midComp: 0.22, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.25 }, splitHigh: { hue: 30, strength: 0.26 },
                warmProtect: 0.60, warmResidual: 0, silverHigh: { hue: 205, strength: 0.10 }, blackLift: 0,
            },
            {
                ev: -0.8, tempK: +1600, satPct: +6, toe: 0.05, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.15 }, splitHigh: { hue: 30, strength: 0.30 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: -0.4, tempK: +800, satPct: +3, toe: 0.025, midComp: 0.05, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.5, tempK: +500, satPct: -2, toe: 0, midComp: -0.08, shoulder: 0.55, hiDesat: 0.25, purkinje: 0,
                splitShadow: { hue: 195, strength: 0.06 }, splitHigh: { hue: 32, strength: 0.07 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
        ],
    },
    // v3c 正午=热霾：黑位轻微抬升（hot haze）+ 高光强脱色 + 全帧极轻微暖霾 cast
    'cinematic-dusk-peak-v3c': {
        name: 'cinematic-dusk-peak-v3c',
        title: '青橙黄昏峰 v3c「热霾正午」（bake-ramp v3 候选，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 6, 7, 9],
        l0LumaCeiling: 0.15,
        l1LumaCeiling: 0.22,
        manifestNote: '青橙黄昏峰 v3c「热霾正午」（bake-ramp v3 候选），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: 'v3 主干同 v3a（7 锚点 / 黄昏橙峰 L5 0.30 / 夜档冷银蓝 splitHigh / EV 收紧 −5.5/−4.8）。'
            + '与 v1/v2 系结构差异同 v3a；v3c 正午=热霾：blackLift 0.010（黑位轻微抬升 hot haze，'
            + 'L8 随插值 0.005，单调性不受黑位抬升影响——抬升随等级递增不产生回落）、'
            + 'hiDesat 0.65（高光强脱色）、tempK +650（全帧极轻微暖霾 cast）、shoulder 0.35；'
            + 'split 收敛同 v2a。',
        anchors: [
            {
                ev: -5.5, tempK: -4800, satPct: -55, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.40 }, splitHigh: { hue: 205, strength: 0.12 },
                warmProtect: 0.95, warmResidual: 0, silverHigh: { hue: 205, strength: 0.30 }, blackLift: 0,
            },
            {
                ev: -4.8, tempK: -4200, satPct: -48, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.35 }, splitHigh: { hue: 205, strength: 0.10 },
                warmProtect: 0.92, warmResidual: 0, silverHigh: { hue: 205, strength: 0.25 }, blackLift: 0,
            },
            {
                ev: -1.4, tempK: -1200, satPct: -12, toe: 0.05, midComp: 0.22, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 190, strength: 0.25 }, splitHigh: { hue: 30, strength: 0.26 },
                warmProtect: 0.60, warmResidual: 0, silverHigh: { hue: 205, strength: 0.10 }, blackLift: 0,
            },
            {
                ev: -0.8, tempK: +1600, satPct: +6, toe: 0.05, midComp: 0.10, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0.15 }, splitHigh: { hue: 30, strength: 0.30 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: -0.4, tempK: +800, satPct: +3, toe: 0.025, midComp: 0.05, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            {
                ev: +0.35, tempK: +650, satPct: -6, toe: 0, midComp: 0, shoulder: 0.35, hiDesat: 0.65, purkinje: 0,
                splitShadow: { hue: 195, strength: 0.06 }, splitHigh: { hue: 32, strength: 0.07 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0.010,
            },
        ],
    },
    // ── v4「硬光黄昏」：维护者 v3 验收后迭代指令（单一候选集合）──
    // 指令要点：①黄昏橙峰 L5→L4（「黄昏先假设是光照等级为 4」——权威时间表 L4=03:00/19:00，
    //   正是真实晨昏小时）；②v3 黄昏「看起来很怪」修正——L4 同时是暗部转青与高光极暖的交汇点，
    //   冷暖对撞过强显脏：橙峰拉满时暗部青收敛（≤.08 偏中性冷 205°）、silverHigh 高光冷切除（0），
    //   tempK 暖侧加大（−1200→+1200）补偿阴影冷感缺失，让橙读作「夕阳光」而非滤镜感；
    //   ③v3b 硬光正午胜出并上升为全族基调：L4–L9 midComp 负值微调（中调微对比，黄昏档最轻
    //   −0.02 防把暖峰推脏）、降饱和克制（白天段 ≥−2）、L9=v3b 原样；夜段（L0/L1 及 L2/L3
    //   插值区）不适用硬光（midComp 是刚需线载体，不动），刚需线/青蓝纯净/暖色豁免沿用 v3。
    // 结构：7 锚点 [0/1/4/5/6/7/9]（L6 显式近零锚，沿用 v3 裁决）；L5=过渡暖 0.12（=L4×0.4，
    //   指令区间 1/3–1/2）；L8 插值跟随 L7→L9。
    // 机制记录：L4 白点凹陷许可不构成上限（shoulder=0 + split 灰阶 luma 精确保持，同 v3 结论），
    //   0.30 直接成立、实测 0 处许可。
    'hardlight-dusk-v4': {
        name: 'hardlight-dusk-v4',
        title: '硬光黄昏 v4「黄昏@L4」（bake-ramp v4 候选，验收用）',
        mode: '光照',
        filePrefix: '光照',
        anchorLevels: [0, 1, 4, 5, 6, 7, 9],
        l0LumaCeiling: 0.15,
        l1LumaCeiling: 0.22,
        manifestNote: '硬光黄昏 v4（黄昏橙峰@L4 + 硬光全族基调），验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels',
        calibrationNote: 'v3→v4 结构差异：①黄昏橙峰 L5→L4（维护者指令「黄昏先假设是光照等级为 4」，'
            + '权威时间表 L4=03:00/19:00）；②L4 冷暖对撞修正：splitShadow 190°/.25→205°/.06（≤.08 偏中性冷）、'
            + 'silverHigh .10→0（高光冷与暖峰同区对撞一并切除）、tempK −1200→+1200（暖侧补偿）、'
            + 'sat −12→−6、midComp .22→−0.02；③硬光全族化：L4/L5/L6/L9 midComp −0.02/−0.02/−0.04/−0.08、'
            + '白天段 sat ≥−2、L9=v3b 原样（EV+0.5/tempK+500/sat−2/shoulder .55/hiDesat .25/midComp−0.08）；'
            + '④L5=过渡暖 splitHigh .12（L4×0.4）、L6=0；夜段 L0/L1 与 v3 逐参数一致（EV −5.5/−4.8、'
            + 'splitHigh 冷银蓝 205°、midComp .35/.30 不动）。',
        anchors: [
            { // L0 深夜：与 v3 逐参数一致（刚需线载体，不动）
                ev: -5.5, tempK: -4800, satPct: -55, toe: 0.85, midComp: 0.35, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.40 }, splitHigh: { hue: 205, strength: 0.12 },
                warmProtect: 0.95, warmResidual: 0, silverHigh: { hue: 205, strength: 0.30 }, blackLift: 0,
            },
            { // L1 夜：与 v3 逐参数一致
                ev: -4.8, tempK: -4200, satPct: -48, toe: 0.65, midComp: 0.30, shoulder: 0, hiDesat: 0, purkinje: 1.0,
                splitShadow: { hue: 190, strength: 0.35 }, splitHigh: { hue: 205, strength: 0.10 },
                warmProtect: 0.92, warmResidual: 0, silverHigh: { hue: 205, strength: 0.25 }, blackLift: 0,
            },
            { // L4 黄昏峰（03:00/19:00）：橙峰拉满 0.30，暗部青收敛让路（205°/.06），silverHigh 切除，
              // tempK +1200 暖侧补偿——橙读作夕阳光而非滤镜感；暖火豁免 0.60 保持
                ev: -1.4, tempK: +1200, satPct: -6, toe: 0.05, midComp: -0.02, shoulder: 0, hiDesat: 0, purkinje: 0.08,
                splitShadow: { hue: 205, strength: 0.06 }, splitHigh: { hue: 30, strength: 0.30 },
                warmProtect: 0.60, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            { // L5 过渡暖：橙峰 ×0.4，其余与 v3 同向（tempK 随 L4 暖化回落至 +1400）
                ev: -0.8, tempK: +1400, satPct: +6, toe: 0.05, midComp: -0.02, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 205, strength: 0.04 }, splitHigh: { hue: 30, strength: 0.12 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            { // L6 显式近零锚（v3 裁决）：split=0；midComp 硬光化 −0.04
                ev: -0.4, tempK: +800, satPct: +3, toe: 0.025, midComp: -0.04, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            { // L7 白天恒等：全参数零（硬断言逐字节恒等）
                ev: 0, tempK: 0, satPct: 0, toe: 0, midComp: 0, shoulder: 0, hiDesat: 0, purkinje: 0,
                splitShadow: { hue: 190, strength: 0 }, splitHigh: { hue: 30, strength: 0 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
            { // L9 正午 = v3b 硬光原样（EV+0.5 / tempK+500 / sat−2 / shoulder .55 / hiDesat .25 / midComp −0.08）
                ev: +0.5, tempK: +500, satPct: -2, toe: 0, midComp: -0.08, shoulder: 0.55, hiDesat: 0.25, purkinje: 0,
                splitShadow: { hue: 195, strength: 0.06 }, splitHigh: { hue: 32, strength: 0.07 },
                warmProtect: 0, warmResidual: 0, silverHigh: { hue: 205, strength: 0 }, blackLift: 0,
            },
        ],
    },
};

const ANCHOR_FIELDS = ['ev', 'tempK', 'satPct', 'toe', 'midComp', 'shoulder', 'hiDesat', 'splitTone', 'purkinje'];
// v2 新增标量字段（v1 锚点未提供时恒 0，保证 v1 输出字节不变）
const V2_SCALAR_FIELDS = ['blackLift', 'warmProtect', 'warmResidual'];
// v2 风味 tint 字段：{hue(度), strength}；strength 线性插值，tint 向量在向量空间插值
// splitShadow2 为 neon-city「暗部青/品红双色倾向」实验的第二暗部色相（见 evaluateTexel 7a 注）
const TINT_FIELDS = ['splitShadow', 'splitHigh', 'silverHigh', 'splitShadow2'];

// 参数在 t 上分段 smoothstep 连续；整数锚点档精确取锚点值。
// v2 起支持稀疏锚点（anchorLevels）：非锚点档由相邻锚点参数空间插值生成
// （生成器路径语义：参数连续则曲线相干；与面板手工预设的 LUT 级 blend 不同）。
function anchorParams(recipe, anchor) {
    const out = {};
    for (const field of ANCHOR_FIELDS) out[field] = anchor[field] || 0;
    for (const field of V2_SCALAR_FIELDS) out[field] = anchor[field] || 0;
    for (const field of TINT_FIELDS) {
        const spec = anchor[field] || {};
        const hue = spec.hue === undefined ? 210 : spec.hue;
        out[field] = {
            hue,
            strength: spec.strength || 0,
            tint: hueToTint(hue, spec.chroma),
        };
    }
    // 配方级暖窗（neon-city 收窄到纯橙用；null = 默认窗口 [340°,60°]）
    out.warmWindow = recipe.warmWindow || null;
    return out;
}

function lerpParams(a, b, u) {
    const out = {};
    for (const field of ANCHOR_FIELDS) out[field] = a[field] * (1 - u) + b[field] * u;
    for (const field of V2_SCALAR_FIELDS) out[field] = a[field] * (1 - u) + b[field] * u;
    for (const field of TINT_FIELDS) {
        const ta = a[field], tb = b[field];
        out[field] = {
            hue: u < 0.5 ? ta.hue : tb.hue, // hue 仅记录；着色以向量插值为准（避免环绕）
            strength: ta.strength * (1 - u) + tb.strength * u,
            tint: lerpVec(ta.tint, tb.tint, u),
        };
    }
    out.warmWindow = a.warmWindow || b.warmWindow || null; // 配方级常量，不插值
    return out;
}

function lerpVec(a, b, u) {
    return [a[0] * (1 - u) + b[0] * u, a[1] * (1 - u) + b[1] * u, a[2] * (1 - u) + b[2] * u];
}

function paramsAt(recipe, t) {
    const anchors = recipe.anchors;
    const levels = recipe.anchorLevels || anchors.map((_, i) => i);
    if (t <= levels[0]) return anchorParams(recipe, anchors[0]);
    if (t >= levels[levels.length - 1]) return anchorParams(recipe, anchors[anchors.length - 1]);
    let seg = 0;
    while (seg < levels.length - 2 && t > levels[seg + 1]) seg++;
    const la = levels[seg];
    const lb = levels[seg + 1];
    const u = smoothstep(0, 1, (t - la) / (lb - la));
    return lerpParams(
        anchorParams(recipe, anchors[seg]),
        anchorParams(recipe, anchors[seg + 1]),
        u,
    );
}

// ---------- 风味通道辅助（v2） ----------

// 色相（0..360°，luma=1 的定向色向量）；chroma 决定离中性灰的距离
function hslToRgb(h, s, l) {
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    const conv = (t) => {
        let tt = t;
        if (tt < 0) tt += 1;
        if (tt > 1) tt -= 1;
        if (tt < 1 / 6) return p + (q - p) * 6 * tt;
        if (tt < 1 / 2) return q;
        if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
        return p;
    };
    return [conv(h + 1 / 3), conv(h), conv(h - 1 / 3)];
}

function hueToTint(hueDeg, chroma) {
    const c = chroma === undefined ? 0.6 : chroma;
    const [r, g, b] = hslToRgb(((hueDeg % 360) + 360) % 360 / 360, c, 0.5);
    const l = luma709(r, g, b);
    return l > 0 ? [r / l, g / l, b / l] : [1, 1, 1];
}

// HSV 饱和（max==0 → 0）与色相（度）
function rgbToHsvSat(r, g, b) {
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const d = max - min;
    const sat = max <= 0 ? 0 : d / max;
    let hue = 0;
    if (d > 1e-12) {
        if (max === r) hue = 60 * (((g - b) / d) % 6);
        else if (max === g) hue = 60 * ((b - r) / d + 2);
        else hue = 60 * ((r - g) / d + 4);
        if (hue < 0) hue += 360;
    }
    return [hue, sat];
}

// 暖色相窗口隶属：窗口默认 [340°, 60°]（环绕），核心 [350°, 50°] 全隶属，两端各 10° 羽化到 0。
// 以 0° 为中心的符号坐标：核心边界 +50°/−10°，外边界 +60°/−20°；dist=超出核心的度数。
// window_ 为配方级覆盖（如 neon-city 收窄到纯橙 {corePos:35, coreNeg:-5, feather:8}）。
function warmWindowMembership(hueDeg, window_) {
    const corePos = window_ && window_.corePos !== undefined ? window_.corePos : 50;
    const coreNeg = window_ && window_.coreNeg !== undefined ? window_.coreNeg : -10;
    const feather = window_ && window_.feather !== undefined ? window_.feather : 10;
    let h = ((hueDeg % 360) + 360) % 360;
    if (h > 180) h -= 360;
    const dist = h > corePos ? h - corePos : (h < coreNeg ? coreNeg - h : 0);
    return 1 - smoothstep(0, feather, dist);
}

// 暖色豁免权重（channel 2）：豁免强度（warmProtect + warmResidual，封顶 1）
// × 窗口隶属 × 饱和权重（高饱和暖色保护最强，灰不受影响）。色相/饱和取自输入 texel（稳定参考系）。
function warmProtectionWeight(params, r, g, b) {
    const strength = params.warmProtect + (params.warmResidual || 0);
    if (strength <= 0) return 0;
    const [hue, sat] = rgbToHsvSat(r, g, b);
    return Math.min(1, strength) * warmWindowMembership(hue, params.warmWindow) * smoothstep(0.15, 0.5, sat);
}

// 暖色保护自检探针（v2 自检新增）：代表性 texel 对照表
// （高饱和橙 vs 同 luma 蓝 vs 中性灰；橙的饱和保留率应显著高于蓝、灰不受影响）。
function warmProtectionProbe(recipe, level) {
    const params = paramsAt(recipe, level);
    const orange = [1.0, 0.45, 0.10];
    // 蓝：构造后按橙的 luma 归一到同档（对照公平性）
    const lOrange = luma709(orange[0], orange[1], orange[2]);
    const blue0 = [0.15, 0.50, 1.0];
    const lBlue0 = luma709(blue0[0], blue0[1], blue0[2]);
    const blue = blue0.map((v) => clamp01(v * (lOrange / lBlue0)));
    const texels = [
        { name: '高饱和橙（暖窗内）', rgb: orange },
        { name: '同 luma 蓝（暖窗外）', rgb: blue },
        { name: '中性灰', rgb: [0.5, 0.5, 0.5] },
    ];
    return texels.map((texel) => {
        const [r, g, b] = texel.rgb;
        const [or, og, ob] = evaluateTexel(params, r, g, b);
        const [, inSat] = rgbToHsvSat(r, g, b);
        const [, outSat] = rgbToHsvSat(or, og, ob);
        // 反事实（仅首行暖色 texel 计算）：同一 texel 关闭豁免后的保留率，量化豁免机制强度
        let retentionNoProt = null;
        if (texel === texels[0]) {
            const off = Object.assign({}, params, { warmProtect: 0, warmResidual: 0 });
            const [nr, ng, nb] = evaluateTexel(off, r, g, b);
            const [, outSatOff] = rgbToHsvSat(nr, ng, nb);
            retentionNoProt = inSat > 1e-9 ? outSatOff / inSat : 1;
        }
        return {
            name: texel.name,
            inSat,
            outSat,
            retention: inSat > 1e-9 ? outSat / inSat : 1,
            retentionNoProt,
            warmWeight: warmProtectionWeight(params, r, g, b),
            lumaIn: luma709(r, g, b),
            lumaOut: luma709(or, og, ob),
        };
    });
}

// ---------- 对比形态 ----------

function applyContrast(rgb, p) {
    let [r, g, b] = rgb;

    if (p.splitTone > 0) {
        // L5 split-tone：暗部冷（减红增蓝）/ 高光暖（增红减蓝），按 luma 分区在 log 空间插值
        const l = luma709(r, g, b);
        const w = smoothstep(0.30, 0.70, l);
        const shadowTint = [0.92, 1.0, 1.12];
        const highTint = [1.06, 1.0, 0.90];
        const s = p.splitTone;
        r *= Math.pow(shadowTint[0], (1 - w) * s) * Math.pow(highTint[0], w * s);
        g *= Math.pow(shadowTint[1], (1 - w) * s) * Math.pow(highTint[1], w * s);
        b *= Math.pow(shadowTint[2], (1 - w) * s) * Math.pow(highTint[2], w * s);
    }

    if (p.toe > 0) {
        // toe 压暗曲线：0.30 以下渐强压暗（近黑防伽马破解），0.30 以上不动
        const crush = (v) => v * (1 - p.toe * (1 - smoothstep(0, 0.30, v)));
        r = crush(r); g = crush(g); b = crush(b);
    }

    if (p.midComp !== 0) {
        // 中调压缩：以 0.5 为轴向中灰收拢，越靠中压缩越强，两端不动；
        // 负值为中调微对比提升（v3b 硬光正午：中调离轴外推，端点同样不动）
        const comp = (v) => 0.5 + (v - 0.5) * (1 - p.midComp * (1 - Math.abs(2 * v - 1)));
        r = comp(r); g = comp(g); b = comp(b);
    }

    const s0 = 0.75;
    if (p.shoulder > 0 || p.hiDesat > 0) {
        if (p.shoulder > 0) {
            // 幂次高光滚降：s0 以上按 (1−(1−min(u,1))^(1+shoulder)) 压缩接近段，
            // 但白点保持（u≥1 → 1）——EV 提升可越出肩区，滚降只压缩接近段的斜率，
            // 与灰阶单调性硬断言兼容（渐近式 u/(1+ku) 在白点必降，已弃用）。
            const roll = (v) => {
                if (v <= s0) return v;
                const u = Math.min(1, (v - s0) / (1 - s0));
                return s0 + (1 - s0) * (1 - Math.pow(1 - u, 1 + p.shoulder));
            };
            r = roll(r); g = roll(g); b = roll(b);
        }
        if (p.hiDesat > 0) {
            // 高光区降饱和：向 luma 靠拢（不改变 luma，保住灰阶单调性）
            const l2 = luma709(r, g, b);
            const zone = smoothstep(s0, 1.0, l2) * p.hiDesat;
            r = r + (l2 - r) * zone;
            g = g + (l2 - g) * zone;
            b = b + (l2 - b) * zone;
        }
    }
    return [r, g, b];
}

// ---------- 单 texel 管线 ----------

function evaluateTexel(params, r, g, b) {
    // 暖色豁免权重（channel 2，v2）：取自输入 texel（稳定参考系）；v1/零强度时恒 0
    const warmP = warmProtectionWeight(params, r, g, b);
    // 1) sRGB 解码 → 线性
    let lr = srgbDecode(r), lg = srgbDecode(g), lb = srgbDecode(b);
    // 2) 曝光 ×2^EV
    const gain = Math.pow(2, params.ev);
    lr *= gain; lg *= gain; lb *= gain;
    // 3) 白平衡增益；暖窗内像素按权重减免冷偏移（增益向 1 靠拢，v1 时 warmP=0 不变）
    const [gr, gg, gb] = whiteBalanceGains(params.tempK);
    lr *= gr + (1 - gr) * warmP;
    lg *= gg + (1 - gg) * warmP;
    lb *= gb + (1 - gb) * warmP;
    // 4) sRGB 重编码
    let cr = srgbEncode(lr), cg = srgbEncode(lg), cb = srgbEncode(lb);
    // 5) 饱和（向 Rec.709 luma lerp；负值降饱和）；暖窗内降饱和按权重减免（v1 时不变）
    let sf = 1 + params.satPct / 100;
    if (sf < 1 && warmP > 0) sf = sf + (1 - sf) * warmP;
    const luma = luma709(cr, cg, cb);
    cr = luma + (cr - luma) * sf;
    cg = luma + (cg - luma) * sf;
    cb = luma + (cb - luma) * sf;
    // 6) Purkinje：R 通道向 luma 额外靠拢（仅 t<4）；
    //    暖窗内红衰减按暖色豁免同一权重减免（否则高红暖色被压向灰度，与「灯火保持暖」直接冲突——
    //    豁免语义按维护者意图覆盖降饱和/冷偏移/红衰减三处，见 preset.json flavor.warmProtection）。
    if (params.purkinje > 0) {
        const purk = params.purkinje * (1 - warmP);
        if (purk > 0) {
            const l2 = luma709(cr, cg, cb);
            cr = cr * (1 - purk) + l2 * purk;
        }
    }
    // 7a) 全等级 split-tone（channel 1，v2）：暗部/高光各一对（色相+强度），按 luma 分区。
    //     tint 为 luma=1 的定向色，pow(tint, strength) 逐通道增益；暖窗内冷着色按豁免权重向 1 靠拢
    //     （冷夜氛围不应染色灯火，与豁免同一权重）；v1/零强度时跳过。
    //     splitShadow2（neon-city「暗部青/品红双色倾向」实验）：存在时暗部 tint 按 luma 在
    //     双色相间插值——w2=smoothstep(0.15,0.55,luma)×splitShadow2.strength，
    //     深影偏 splitShadow.hue（青 ≈190°）、亮影偏 splitShadow2.hue（品红 ≈320°）。
    const sSh = params.splitShadow;
    const sHi = params.splitHigh;
    if (sSh.strength > 0 || sHi.strength > 0) {
        const l3 = luma709(cr, cg, cb);
        const w = smoothstep(0.30, 0.70, l3);
        let shadowTint = sSh.tint;
        if (params.splitShadow2 && params.splitShadow2.strength > 0) {
            const w2 = smoothstep(0.15, 0.55, l3) * params.splitShadow2.strength;
            shadowTint = lerpVec(sSh.tint, params.splitShadow2.tint, w2);
        }
        const ws = (1 - w) * sSh.strength;
        const wh = w * sHi.strength;
        // 增益向量 luma 归一：split-tone 只改色不改亮度。必须归一「shadow×high 合并增益」
        // （分别归一后相乘 luma 仍漂移 ≈0.07%，在白点形成恒量反相，已实测）；
        // 旧标量 splitTone 路径为保 v1 输出字节不变不套用此归一。
        const tintGain = (tint, s, i) => {
            const g = Math.pow(tint[i], s);
            return g + (1 - g) * warmP;
        };
        const gs = [
            tintGain(shadowTint, ws, 0) * tintGain(sHi.tint, wh, 0),
            tintGain(shadowTint, ws, 1) * tintGain(sHi.tint, wh, 1),
            tintGain(shadowTint, ws, 2) * tintGain(sHi.tint, wh, 2),
        ];
        const gl = REC709[0] * gs[0] + REC709[1] * gs[1] + REC709[2] * gs[2];
        if (gl > 0) {
            cr *= gs[0] / gl;
            cg *= gs[1] / gl;
            cb *= gs[2] / gl;
        }
    }
    // 7b) 银蓝夜高光（channel 3，v2）：≤L4 锚点的高光定向月白银蓝——保 luma、改色相，
    //     与暗部钢蓝（channel 1 splitShadow）分开控制。lerp(c, luma*tint, z)，tint luma=1 → luma 不变。
    if (params.silverHigh.strength > 0) {
        const l4 = luma709(cr, cg, cb);
        const z = smoothstep(0.55, 0.90, l4) * params.silverHigh.strength;
        const tint = params.silverHigh.tint;
        cr = cr * (1 - z) + l4 * tint[0] * z;
        cg = cg * (1 - z) + l4 * tint[1] * z;
        cb = cb * (1 - z) + l4 * tint[2] * z;
    }
    // 7c) 对比形态（splitTone 旧标量路径 → toe → midComp → shoulder + 高光区降饱和）
    [cr, cg, cb] = applyContrast([cr, cg, cb], params);
    // 7d) 黑位抬升（v2m）：近黑提升曲线（奶灰底），0.35 以上不动；v1/v2 为 0 时跳过
    if (params.blackLift > 0) {
        const lift = (v) => v + params.blackLift * (1 - smoothstep(0, 0.35, v));
        cr = lift(cr); cg = lift(cg); cb = lift(cb);
    }
    // 8) clamp01
    return [clamp01(cr), clamp01(cg), clamp01(cb)];
}

// ---------- LUT 构建 ----------

function buildLevelLut(recipe, level) {
    const params = paramsAt(recipe, level);
    const size = 32;
    const data = new Float64Array(size * size * size * 3);
    let offset = 0;
    for (let bi = 0; bi < size; bi++) {
        const b = bi / (size - 1);
        for (let gi = 0; gi < size; gi++) {
            const g = gi / (size - 1);
            for (let ri = 0; ri < size; ri++) {
                const r = ri / (size - 1);
                const [or, og, ob] = evaluateTexel(params, r, g, b);
                data[offset] = or; data[offset + 1] = og; data[offset + 2] = ob;
                offset += 3;
            }
        }
    }
    return {
        size,
        title: `${recipe.title} · ${recipe.mode} L${level}`,
        domainMin: [0, 0, 0],
        domainMax: [1, 1, 1],
        data,
        dataLines: size * size * size,
    };
}

// ---------- 自检 ----------

// 灰阶 luma 表：levels × graySteps（gray = i/(steps-1)）
function grayscaleLumaTable(recipe, steps) {
    const table = [];
    for (let level = 0; level <= 9; level++) {
        const params = paramsAt(recipe, level);
        const row = [];
        for (let i = 0; i < steps; i++) {
            const v = i / (steps - 1);
            const [or, og, ob] = evaluateTexel(params, v, v, v);
            row.push(luma709(or, og, ob));
        }
        table.push(row);
    }
    return table;
}

function checkMonotonic(table, tolerance, fadeAllowance, whiteSagAllowance) {
    const tol = tolerance === undefined ? 1e-9 : tolerance;
    const failures = [];
    const allowed = [];
    const lastG = table[0].length - 1;
    // 白点凹陷容差前提：L7 白点必须精确 1.0（恒等锚点完好）；仅对白列生效
    const l7WhiteExact = table[7] && Math.abs(table[7][lastG] - 1) <= 1e-9;
    for (let t = 0; t < table.length - 1; t++) {
        for (let g = 0; g < table[t].length; g++) {
            const delta = table[t + 1][g] - table[t][g];
            if (delta < -tol) {
                const gray = g / (table[t].length - 1);
                // 黑位淡出段的受控回落许可（仅近黑灰阶且单级回落 ≤ maxDrop，结构性取舍显式记录）
                if (fadeAllowance && gray <= fadeAllowance.maxGray && -delta <= fadeAllowance.maxDrop) {
                    allowed.push(`L${t}→L${t + 1} 灰阶 ${gray.toFixed(3)}：Δ=${delta.toFixed(6)}（黑位淡出受控回落）`);
                    continue;
                }
                // 暖调白点受控凹陷许可：仅白列（灰阶=1.0）且 L7 白点精确 1.0 且凹陷 ≤ maxSag。
                // 成因：暖色温 + splitHigh 对 B 通道的抑制使白点略低于 1.0（暖调白，非真反相），
                // 每通道肩部不对称滚降进一步放大差异；≤0.001（≈0.26/255），属可标注的结构性artifact。
                if (whiteSagAllowance && g === lastG && l7WhiteExact
                    && -delta <= whiteSagAllowance.maxSag) {
                    allowed.push(`L${t}→L${t + 1} 白点：Δ=${delta.toFixed(6)}（暖调白点受控凹陷）`);
                    continue;
                }
                failures.push(`L${t}→L${t + 1} 灰阶 ${g}：Δ=${delta.toFixed(6)}（反相）`);
            }
        }
    }
    return { failures, allowed };
}

// L7 全管线 256 级灰阶逐字节保真（恒等断言的量化形式）
function checkIdentityRoundTrip(recipe) {
    const params = paramsAt(recipe, 7);
    const failures = [];
    for (let k = 0; k <= 255; k++) {
        const v = k / 255;
        const [or, og, ob] = evaluateTexel(params, v, v, v);
        if (Math.round(or * 255) !== k || Math.round(og * 255) !== k || Math.round(ob * 255) !== k) {
            failures.push(`k=${k} → (${Math.round(or * 255)},${Math.round(og * 255)},${Math.round(ob * 255)})`);
        }
    }
    return failures;
}

module.exports = {
    RECIPES,
    ANCHOR_FIELDS,
    V2_SCALAR_FIELDS,
    TINT_FIELDS,
    paramsAt,
    anchorParams,
    evaluateTexel,
    buildLevelLut,
    grayscaleLumaTable,
    checkMonotonic,
    checkIdentityRoundTrip,
    whiteBalanceGains,
    temperatureToRgb,
    srgbDecode,
    srgbEncode,
    smoothstep,
    hueToTint,
    hslToRgb,
    rgbToHsvSat,
    warmWindowMembership,
    warmProtectionWeight,
    warmProtectionProbe,
};
