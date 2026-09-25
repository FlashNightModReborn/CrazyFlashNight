#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { parseCube, serializeCube, rangeByChannel } = require('./lib/cube');
const { sampleLut, resampleTo32, generateLut, GENERATOR_KINDS, buildLut, blendLut } = require('./lib/lut');
const ramp = require('./lib/ramp');
const { readRaw, writeRaw, applyLutToPixels, generateImage, IMAGE_KINDS } = require('./lib/rawimage');

const COMMANDS = new Set(['generate', 'apply', 'gen-image', 'inspect', 'make-set', 'bake-ramp', 'pack-set']);

// 集合（set）= 某模式 0–9 整数级各一个 LUT 的有序组；make-set 生成演示集合到 <out>/<name>/。
const SET_KINDS = {
    'nightvision-green-ramp': {
        title: '夜视绿强度斜坡（演示集合）',
        mode: '夜视',
        filePrefix: '夜视',
        source: 'tools/lut-lab make-set 生成',
        license: '项目内部生成，随仓库',
        notes: '等级 = 夜视绿强度：identity 与 nightvision-green 按 L/9 逐节点线性混合',
        build(level) {
            return blendLut(generateLut('identity'), generateLut('nightvision-green'), level / 9);
        },
    },
};
const VALUE_OPTIONS = new Set(['kind', 'out', 'lut', 'in', 'width', 'height', 'set']);
const BOOLEAN_OPTIONS = new Set(['json', 'check']);

const USAGE = [
    '用法：node tools/lut-lab/cli.js <命令> [参数]',
    '  generate --kind <' + GENERATOR_KINDS.join('|') + '> --out <file.cube>',
    '  apply --lut <file.cube> --in <raw.rgba> --out <raw.rgba> --width W --height H',
    '  gen-image --kind <' + IMAGE_KINDS.join('|') + '> --width W --height H --out <raw.rgba>',
    '  inspect <file.cube>',
    '  make-set --kind <' + Object.keys(SET_KINDS).join('|') + '> --out <setsRoot>',
    '  bake-ramp --kind <' + Object.keys(ramp.RECIPES).join('|') + '> --out <setsRoot>',
    '  pack-set --set <setsDir（含 preset.json + 10 档 cube）> --out <file.lutset> [--check]',
    '通用参数：--json。raw 为纯 RGBA8 字节流；.CUBE 统一 32³、R 变化最快，',
    '解析容忍 16/17/32/33/64 并三线性重采样到 32³。',
].join('\n');

function usageError(message) {
    const error = new Error(message);
    error.usageMessage = `${message}\n${USAGE}`;
    throw error;
}

function parseArguments(argv) {
    if (!argv.length || !COMMANDS.has(argv[0])) {
        const error = new Error('usage');
        error.usageMessage = USAGE;
        throw error;
    }
    const command = argv[0];
    const options = Object.create(null);
    const positional = [];
    for (let index = 1; index < argv.length; index += 1) {
        const token = argv[index];
        if (!token.startsWith('--')) {
            positional.push(token);
            continue;
        }
        const name = token.slice(2);
        if (Object.prototype.hasOwnProperty.call(options, name)) usageError(`参数不得重复：--${name}`);
        if (BOOLEAN_OPTIONS.has(name)) {
            options[name] = true;
            continue;
        }
        if (!VALUE_OPTIONS.has(name) || index + 1 >= argv.length || argv[index + 1].startsWith('--')) {
            usageError(VALUE_OPTIONS.has(name) ? `参数 --${name} 缺少值` : `未知参数：--${name}`);
        }
        options[name] = argv[index + 1];
        index += 1;
    }
    if (command === 'inspect') {
        if (positional.length !== 1) usageError('inspect 需要恰好一个位置参数 <file.cube>');
        options.file = positional[0];
    } else if (positional.length) {
        usageError(`无法识别的位置参数：${positional[0]}`);
    }
    const requireValue = (name) => {
        if (!options[name]) usageError(`${command} 必须提供 --${name}`);
        return options[name];
    };
    const requireDimension = (name) => {
        const raw = requireValue(name);
        if (!/^\d+$/.test(raw)) usageError(`--${name} 需要正整数，实际：${raw}`);
        const value = Number.parseInt(raw, 10);
        if (value < 1 || value > 16384) usageError(`--${name} 超出 1..16384：${value}`);
        return value;
    };
    if (command === 'generate') {
        requireValue('kind');
        requireValue('out');
    } else if (command === 'apply') {
        requireValue('lut');
        requireValue('in');
        requireValue('out');
        options.width = requireDimension('width');
        options.height = requireDimension('height');
    } else if (command === 'gen-image') {
        requireValue('kind');
        requireValue('out');
        options.width = requireDimension('width');
        options.height = requireDimension('height');
    } else if (command === 'make-set') {
        requireValue('kind');
        requireValue('out');
    } else if (command === 'bake-ramp') {
        requireValue('kind');
        requireValue('out');
    } else if (command === 'pack-set') {
        requireValue('set');
        requireValue('out');
    }
    return { command, options };
}

function loadLutResampled(file) {
    const parsed = parseCube(fs.readFileSync(file, 'utf8'), file);
    const lut = resampleTo32(parsed);
    return { parsed, lut };
}

function writeResult(command, data, json) {
    const result = { schemaVersion: 1, command, ok: true, errors: [], data };
    if (json) {
        process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    } else {
        for (const line of data.lines) process.stdout.write(`${line}\n`);
    }
}

function main() {
    let parsed;
    try {
        parsed = parseArguments(process.argv.slice(2));
    } catch (error) {
        process.stderr.write(`${error.usageMessage || error.message}\n`);
        process.exitCode = 64;
        return;
    }
    const { command, options } = parsed;
    const json = Boolean(options.json);
    try {
        if (command === 'generate') {
            const lut = generateLut(options.kind);
            fs.mkdirSync(path.dirname(path.resolve(options.out)), { recursive: true });
            fs.writeFileSync(options.out, serializeCube(lut));
            writeResult(command, {
                lines: [
                    `generate ${options.kind}：已写出 ${options.out}`,
                    `LUT_3D_SIZE 32，数据行 ${lut.dataLines}，R 分量变化最快，float 六位小数`,
                ],
                out: path.resolve(options.out),
                kind: options.kind,
                size: lut.size,
                dataLines: lut.dataLines,
            }, json);
        } else if (command === 'apply') {
            const { parsed: source, lut } = loadLutResampled(options.lut);
            const input = readRaw(options.in, options.width, options.height);
            const output = applyLutToPixels(lut, input, sampleLut);
            fs.mkdirSync(path.dirname(path.resolve(options.out)), { recursive: true });
            writeRaw(options.out, output);
            const resampleNote = lut.resampledFrom ? '，已三线性重采样到 32³' : '';
            const lines = [
                `apply：${options.in} (${options.width}x${options.height}) -> ${options.out}`,
                `LUT ${options.lut}：size ${source.size}${resampleNote}`,
                `像素 ${input.length / 4}，输出 ${output.length} 字节`,
            ];
            writeResult(command, {
                lines,
                out: path.resolve(options.out),
                lutSize: source.size,
                resampledTo32: Boolean(lut.resampledFrom),
                pixels: input.length / 4,
                bytes: output.length,
            }, json);
        } else if (command === 'gen-image') {
            const buffer = generateImage(options.kind, options.width, options.height);
            fs.mkdirSync(path.dirname(path.resolve(options.out)), { recursive: true });
            writeRaw(options.out, buffer);
            writeResult(command, {
                lines: [
                    `gen-image ${options.kind}：${options.width}x${options.height} -> ${options.out}`,
                    `输出 ${buffer.length} 字节（${options.width}x${options.height}x4）`,
                ],
                out: path.resolve(options.out),
                kind: options.kind,
                width: options.width,
                height: options.height,
                bytes: buffer.length,
            }, json);
        } else if (command === 'make-set') {
            const spec = SET_KINDS[options.kind];
            if (!spec) usageError(`未知集合种类：${options.kind}（可用：${Object.keys(SET_KINDS).join(' / ')}）`);
            const setsRoot = path.resolve(options.out);
            const setDir = path.join(setsRoot, options.kind);
            fs.mkdirSync(setDir, { recursive: true });
            const files = [];
            for (let level = 0; level <= 9; level += 1) {
                const lut = spec.build(level);
                lut.title = `${spec.title} · L${level}`;
                const fileName = `${spec.filePrefix}-${level}.cube`;
                fs.writeFileSync(path.join(setDir, fileName), serializeCube(lut));
                files.push(fileName);
            }
            // manifest.sets.json：按 name 幂等 upsert（重复生成不产生重复条目）
            const manifestPath = path.join(setsRoot, 'manifest.sets.json');
            let manifest = [];
            if (fs.existsSync(manifestPath)) {
                manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
                if (!Array.isArray(manifest)) throw new Error(`manifest.sets.json 不是数组：${manifestPath}`);
            }
            const entry = {
                name: options.kind,
                title: spec.title,
                mode: spec.mode,
                dir: options.kind,
                files,
                source: spec.source,
                license: spec.license,
                notes: spec.notes,
            };
            const at = manifest.findIndex((item) => item && item.name === options.kind);
            if (at >= 0) manifest[at] = entry; else manifest.push(entry);
            fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
            writeResult(command, {
                lines: [
                    `make-set ${options.kind}：${files.length} 档已写出 ${setDir}`,
                    `manifest.sets.json 已更新（共 ${manifest.length} 个集合）`,
                ],
                out: setDir,
                kind: options.kind,
                levels: files.length,
                manifest: manifestPath,
            }, json);
        } else if (command === 'bake-ramp') {
            const recipe = ramp.RECIPES[options.kind];
            if (!recipe) usageError(`未知 ramp 配方：${options.kind}（可用：${Object.keys(ramp.RECIPES).join(' / ')}）`);
            const setsRoot = path.resolve(options.out);
            const setDir = path.join(setsRoot, recipe.name);
            fs.mkdirSync(setDir, { recursive: true });

            // 1) 烘焙 10 档 32³ cube
            const files = [];
            const cubeTexts = [];
            for (let level = 0; level <= 9; level += 1) {
                const lut = ramp.buildLevelLut(recipe, level);
                const fileName = `${recipe.filePrefix}-${level}.cube`;
                const text = serializeCube(lut);
                fs.writeFileSync(path.join(setDir, fileName), text, 'utf8');
                files.push(fileName);
                cubeTexts.push(text);
            }

            // 2) preset.json：完整可再编辑配方（锚点参数 + 管线顺序 + 权威时间映射）
            const preset = {
                schemaVersion: 2,
                name: recipe.name,
                title: recipe.title,
                mode: recipe.mode,
                generator: 'bake-ramp',
                structure: recipe.anchorLevels
                    ? `${recipe.anchorLevels.length} 锚点结构 [${recipe.anchorLevels.join('/')}]；非锚点档由相邻锚点参数空间插值生成（生成器路径语义：参数连续则曲线相干，跨度均 ≤3 级；与面板手工预设的 LUT 级 blend 不同）`
                    : '10 锚点全档直出',
                pipeline: [
                    'warmProtectionWeight（channel 2 暖色豁免权重：窗口隶属×饱和权重×强度；取输入 texel）',
                    'srgbDecode (sRGB → 线性)',
                    'exposure ×2^EV（线性域）',
                    'whiteBalance RGB 增益（Tanner Helland 近似；暖窗内按权重向 1 靠拢=减免冷偏移）',
                    'srgbEncode（线性 → sRGB）',
                    'saturation lerp（Rec.709 luma；暖窗内降饱和按权重减免）',
                    'purkinje（t<4 时 R 通道向 luma 额外靠拢）',
                    'splitTone 成对（channel 1：splitShadow/splitHigh 按 luma 分区，luma=1 定向色 pow 增益）',
                    'silverHigh（channel 3：≤L4 高光月白银蓝，lerp(c, luma·tint, z) 保 luma 改色相）',
                    'contrast: splitTone(旧标量) → toe 压暗 → 中调压缩 → 高光 shoulder + 高光区降饱和',
                    'blackLift（v2m 黑位抬升：近黑提升曲线，0.35 以上不动）',
                    'clamp01',
                ],
                flavor: {
                    splitTone: 'channel 1：每锚点 splitShadow/splitHigh 一对 {hue,strength}；luma=1 定向色，暗部权重 (1−w)、高光权重 w（w=smoothstep(0.30,0.70,luma)），逐通道 pow(tint,strength) 增益',
                    warmProtection: 'channel 2：窗口 [340°,60°]（核心 [350°,50°]，两端各 10° 羽化）；权重 = min(1, warmProtect+warmResidual) × 窗口隶属 × smoothstep(0.15,0.5,sat)；高饱和暖色保护最强、灰不受影响；减免方式=白平衡增益向 1 靠拢、降饱和因子向 1 靠拢、Purkinje 红衰减按同一权重减免（三处共享权重，否则高红暖色被红衰减压向灰度，与「灯火保持暖」冲突）；L7 恒零',
                    silverHigh: 'channel 3：≤L4 锚点高光定向月白银蓝（hue≈210°，luma=1 tint），z=smoothstep(0.55,0.90,luma)×strength，lerp(c, luma·tint, z)——保 luma、改色相；与暗部钢蓝分开控制',
                    blackLift: 'v2m 黑位：v + blackLift×(1−smoothstep(0,0.35,v))（奶灰底近黑提升）',
                },
                timeMapping: {
                    source: 'scripts/类定义/org/flashNight/arki/weather/WeatherSystem.as:138 dayNightLightLevels',
                    array: [0, 0, 1, 4, 7, 7, 7, 7, 7, 7, 7, 7, 9, 7, 7, 7, 7, 7, 7, 4, 1, 0, 0, 0],
                    labels: {
                        L0: '深夜 21–01', L1: '夜 20/02', L4: '晨昏点 03/19',
                        L7: '白天恒等 04–18', L9: '正午 12',
                        'L2/L3/L5/L6/L8': '相邻整点间小数级插值扫过档（过渡平滑性主要承载档）',
                    },
                },
                anchorLevels: recipe.anchorLevels || null,
                anchors: recipe.anchors,
                interpolation: 'paramsAt：分段 smoothstep(u)=u²(3−2u) 连续；v2 为相邻锚点参数空间插值（tint 向量空间插值，strength 线性）',
                calibrationNote: recipe.calibrationNote,
                l0LumaCeiling: recipe.l0LumaCeiling || null,
                edgePolicy: 'hold（集合模型 0–9；9 以上钉 L9）',
                notes: 'bake-ramp v2 候选，验收用。保存只写 tmp/lut-lab/，不碰 data/ 与生产配置。',
            };
            fs.writeFileSync(
                path.join(setDir, 'preset.json'),
                `${JSON.stringify(preset, null, 2)}\n`, 'utf8');

            // 3) manifest.sets.json 原子 upsert（与 make-set 同 schema、同原子语义）
            const manifestPath = path.join(setsRoot, 'manifest.sets.json');
            let manifest = [];
            if (fs.existsSync(manifestPath)) {
                manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
                if (!Array.isArray(manifest)) throw new Error(`manifest.sets.json 不是数组：${manifestPath}`);
            }
            const entry = {
                name: recipe.name,
                title: recipe.title,
                mode: recipe.mode,
                dir: recipe.name,
                files,
                source: 'tools/lut-lab bake-ramp（参数化昼夜 ramp 生成器 v1）',
                license: '项目内部生成，随仓库',
                notes: recipe.manifestNote || ('bake-ramp 候选，验收用；权威时间映射 WeatherSystem.as:138 dayNightLightLevels'),
            };
            const at = manifest.findIndex((item) => item && item.name === recipe.name);
            if (at >= 0) manifest[at] = entry; else manifest.push(entry);
            const manifestTmp = `${manifestPath}.tmp`;
            fs.writeFileSync(manifestTmp, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
            fs.renameSync(manifestTmp, manifestPath);

            // 4) 自检：L7 恒等（256 级逐字节 + cube 数据与恒等 cube 一致）、
            //    灰阶 luma 单调不降（8/16 级）、确定性 SHA-256
            const identityFailures = ramp.checkIdentityRoundTrip(recipe);
            const identityLut = buildLut(32, (r, g, b) => [r, g, b]);
            const stripTitle = (text) => text.replace(/^TITLE .*\n/, '');
            const cubeIdentityOk = identityFailures.length === 0
                && stripTitle(cubeTexts[7]) === stripTitle(serializeCube(identityLut));
            const table8 = ramp.grayscaleLumaTable(recipe, 8);
            const table16 = ramp.grayscaleLumaTable(recipe, 16);
            const whiteSagAllowance = { maxSag: 0.001 };
            const mono8 = ramp.checkMonotonic(table8, undefined, recipe.fadeAllowance, whiteSagAllowance);
            const mono16 = ramp.checkMonotonic(table16, undefined, recipe.fadeAllowance, whiteSagAllowance);
            const monoFailures = [...mono8.failures, ...mono16.failures];
            const monoAllowed = [...mono8.allowed, ...mono16.allowed];
            const crypto = require('crypto');
            const sha256 = crypto.createHash('sha256').update(cubeTexts.join('')).digest('hex');
            if (!cubeIdentityOk) throw new Error(`自检失败：L7 恒等（${identityFailures.slice(0, 3).join('；') || 'cube 数据不一致'}）`);
            if (monoFailures.length) throw new Error(`自检失败：灰阶单调性（${monoFailures.slice(0, 3).join('；')}）`);

            // L0 顶灰 luma 刚需线（v2m 奶灰抬黑后仍须足够暗）
            const l0Max = table16[0][table16[0].length - 1];
            if (recipe.l0LumaCeiling && l0Max > recipe.l0LumaCeiling) {
                throw new Error(`自检失败：L0 顶灰 luma=${l0Max.toFixed(3)} 超刚需线 ${recipe.l0LumaCeiling}`);
            }
            // L1 顶灰 luma 刚需线（v3 起：夜档可读性收紧，L1 必须「灰蓝一片、没法打」）
            const l1Max = table16[1][table16[1].length - 1];
            if (recipe.l1LumaCeiling && l1Max > recipe.l1LumaCeiling) {
                throw new Error(`自检失败：L1 顶灰 luma=${l1Max.toFixed(3)} 超刚需线 ${recipe.l1LumaCeiling}`);
            }

            // 暖色保护验证（channel 2）：L1 对照表 + 断言。
            // 断言口径：①橙保留率 > 蓝保留率 + 0.05（蓝被冷偏移增强是场景本意，豁免须反超）；
            // ②橙豁免前后保留率差 ≥ 0.20（豁免机制强度，反事实对照）；
            // ③灰 warmWeight 恒 0（豁免机制对灰不生效）。
            // 配方无豁免通道（如 v1）时仅打印参考表，不做断言。
            const probeL1 = ramp.warmProtectionProbe(recipe, 1);
            const probeL0 = ramp.warmProtectionProbe(recipe, 0);
            const probeL4 = ramp.warmProtectionProbe(recipe, 4);
            const pOrange = probeL1[0];
            const pBlue = probeL1[1];
            const pGray = probeL1[2];
            const paramsL1 = ramp.paramsAt(recipe, 1);
            const warmStrength = paramsL1.warmProtect + (paramsL1.warmResidual || 0);
            const hasWarmChannel = warmStrength > 0;
            const exemptionDelta = pOrange.retention - pOrange.retentionNoProt;
            // 两档断言：强豁免（≥0.5，火光主角）要求橙显著反超且豁免差显著；
            // 弱豁免（<0.5，如漂白硬派）只要求机制有效且不反向（橙严格高于蓝、豁免差不反）。
            const warmOk = !hasWarmChannel
                || (warmStrength >= 0.5
                    ? (pOrange.retention >= pBlue.retention + 0.05
                        && exemptionDelta >= 0.20
                        && pGray.warmWeight === 0)
                    : (pOrange.retention > pBlue.retention
                        && exemptionDelta >= 0.10
                        && pGray.warmWeight === 0));
            if (!warmOk) {
                throw new Error(`自检失败：暖色保护（强度=${warmStrength.toFixed(2)}，橙保留 ${pOrange.retention.toFixed(3)} vs 蓝 ${pBlue.retention.toFixed(3)}；`
                    + `豁免前后差=${exemptionDelta.toFixed(3)}；灰 w=${pGray.warmWeight.toFixed(4)}）`);
            }
            const fmtProbe = (level, rows) => [
                `暖色保护对照表（L${level}，行=texel，列=inSat→outSat/保留率/豁免权重/Δluma）：`,
                ...rows.map((row) => `  ${row.name}：${row.inSat.toFixed(3)}→${row.outSat.toFixed(3)}`
                    + `（保留 ${row.retention.toFixed(3)}`
                    + (row.retentionNoProt != null ? `，无豁免 ${row.retentionNoProt.toFixed(3)}` : '')
                    + `，w=${row.warmWeight.toFixed(3)}，`
                    + `Δluma=${(row.lumaOut - row.lumaIn).toFixed(3)}）`),
            ];

            const fmtRow = (level, row) => `  L${level}: ${row.map((v) => v.toFixed(3)).join(' ')}`;
            const lines = [
                `bake-ramp ${recipe.name}：10 档已写出 ${setDir}`,
                `L7 identity：PASS（全管线 256 级灰阶逐字节；L7 cube 数据与 identity cube 一致）`,
                `单调性：PASS（灰阶 luma 随等级单调不降，8/16 级）`
                    + (monoAllowed.length
                        ? `；另含受控回落 ${monoAllowed.length} 处（`
                            + (recipe.fadeAllowance
                                ? `黑位淡出仅近黑灰阶 ≤ ${recipe.fadeAllowance.maxGray}、单级 ≤ ${recipe.fadeAllowance.maxDrop}`
                                : `暖调白点凹陷 ≤ 0.001（L7 白点精确 1.0）`)
                            + `；首条：${monoAllowed[0]}）`
                        : ''),
                `确定性 SHA-256（10 档 cube 串联）：${sha256}`,
                recipe.l0LumaCeiling
                    ? `L0 顶灰 luma=${l0Max.toFixed(3)}（刚需线 ≤ ${recipe.l0LumaCeiling}）：PASS`
                    : `L0 顶灰 luma=${l0Max.toFixed(3)}`,
                recipe.l1LumaCeiling
                    ? `L1 顶灰 luma=${l1Max.toFixed(3)}（刚需线 ≤ ${recipe.l1LumaCeiling}）：PASS`
                    : null,
                hasWarmChannel
                    ? `暖色保护：PASS（L1 橙保留 ${pOrange.retention.toFixed(3)} ≥ 蓝 ${pBlue.retention.toFixed(3)} + 0.05；`
                        + `橙豁免前后差=${exemptionDelta.toFixed(3)} ≥ 0.20；灰 w=${pGray.warmWeight.toFixed(4)}=0 豁免不生效）`
                    : `暖色保护：N/A（本配方无暖色豁免通道，对照表仅参考）`,
                ...fmtProbe(1, probeL1),
                ...fmtProbe(0, probeL0),
                ...fmtProbe(4, probeL4),
                `灰阶 luma 表（8 级，行=L0..L9，列=灰阶 0..1）：`,
                ...table8.map((row, i) => fmtRow(i, row)),
                `灰阶 luma 表（16 级）：`,
                ...table16.map((row, i) => fmtRow(i, row)),
                `manifest.sets.json 已原子更新（共 ${manifest.length} 个集合）`,
            ].filter(Boolean);
            writeResult(command, {
                lines,
                out: setDir,
                kind: recipe.name,
                levels: files.length,
                manifest: manifestPath,
                sha256,
                identity: cubeIdentityOk,
                monotonic: true,
                luma8: table8,
                luma16: table16,
            }, json);
        } else if (command === 'pack-set') {
            // CF7LUTSET v1 打包（格式见 lib/lutset.js 头注）：集合目录 10 档 cube → 单一二进制。
            // --check：重新打包并与现有产物逐字节比较（新鲜度校验），stale 即失败，不写文件。
            const lutset = require('./lib/lutset');
            const crypto = require('crypto');
            const setDir = path.resolve(options.set);
            const outPath = path.resolve(options.out);
            const packed = lutset.packSet(setDir);
            const fileSha = crypto.createHash('sha256').update(packed.buffer).digest('hex');
            if (options.check) {
                if (!fs.existsSync(outPath)) {
                    throw new Error(`pack-set --check：产物不存在，需重新生成：${outPath}`);
                }
                const existing = fs.readFileSync(outPath);
                if (!existing.equals(packed.buffer)) {
                    throw new Error(`pack-set --check：产物过期（与集合目录逐字节不符），需重跑 pack-set：${outPath}`);
                }
                writeResult(command, {
                    lines: [
                        `pack-set --check：产物新鲜（逐字节一致） ${outPath}`,
                        `数据段 SHA-256：${packed.sha256}`,
                        `文件 SHA-256：${fileSha}`,
                    ],
                    out: outPath, set: setDir, check: 'fresh', dataSha256: packed.sha256, fileSha256: fileSha,
                }, json);
            } else {
                fs.mkdirSync(path.dirname(outPath), { recursive: true });
                fs.writeFileSync(outPath, packed.buffer);
                writeResult(command, {
                    lines: [
                        `pack-set：${packed.files.length} 档已打包 ${outPath}（CF7LUTSET v1，${packed.buffer.length} 字节）`,
                        `数据段 SHA-256（内嵌完整性字段）：${packed.sha256}`,
                        `文件 SHA-256：${fileSha}`,
                    ],
                    out: outPath, set: setDir, bytes: packed.buffer.length,
                    dataSha256: packed.sha256, fileSha256: fileSha, levels: packed.files.length,
                }, json);
            }
        } else {
            const source = parseCube(fs.readFileSync(options.file, 'utf8'), options.file);
            const range = rangeByChannel(source);
            const lines = [
                `文件：${path.resolve(options.file)}`,
                `TITLE：${source.title || '(无)'}`,
                `LUT_3D_SIZE：${source.size}`,
                `DOMAIN_MIN：${source.domainMin.join(' ')}`,
                `DOMAIN_MAX：${source.domainMax.join(' ')}`,
                `数据行数：${source.dataLines}（期望 ${source.size}^3=${source.size * source.size * source.size}，完整）`,
                `数值范围 R：[${range.min[0]}, ${range.max[0]}]`,
                `数值范围 G：[${range.min[1]}, ${range.max[1]}]`,
                `数值范围 B：[${range.min[2]}, ${range.max[2]}]`,
            ];
            if (source.size !== 32) lines.push(`注意：非 32³，apply 时将三线性重采样到 32³`);
            writeResult(command, {
                lines,
                file: path.resolve(options.file),
                title: source.title,
                size: source.size,
                domainMin: source.domainMin,
                domainMax: source.domainMax,
                dataLines: source.dataLines,
                range,
                resampledOnApply: source.size !== 32,
            }, json);
        }
    } catch (error) {
        const message = error && error.message ? error.message : String(error);
        if (json) {
            const result = { schemaVersion: 1, command, ok: false, errors: [{ code: 'LUTLAB', message }], data: null };
            process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
        } else {
            process.stderr.write(`lut-lab ${command} 失败：${message}\n`);
        }
        process.exitCode = 2;
    }
}

main();
