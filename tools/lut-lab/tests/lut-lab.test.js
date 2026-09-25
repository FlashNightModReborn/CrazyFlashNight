'use strict';

const assert = require('node:assert/strict');
const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const test = require('node:test');
const { parseCube, serializeCube } = require('../lib/cube');
const { sampleLut, resampleTo32, buildLut, generateLut, GENERATOR_KINDS } = require('../lib/lut');
const ramp = require('../lib/ramp');
const { generateImage, IMAGE_KINDS } = require('../lib/rawimage');

const root = path.resolve(__dirname, '../../..');
const cli = path.join(root, 'tools/lut-lab/cli.js');

function run(argumentsList) {
    const result = childProcess.spawnSync(process.execPath, [cli, ...argumentsList], {
        cwd: root,
        encoding: 'utf8',
        maxBuffer: 16 * 1024 * 1024,
    });
    return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

function withTempDirectory(callback) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-lut-lab-'));
    try {
        return callback(directory);
    } finally {
        fs.rmSync(directory, { recursive: true, force: true });
    }
}

test('identity apply 与输入逐字节相等（三种测试图）', () => {
    withTempDirectory((dir) => {
        const cube = path.join(dir, 'identity.cube');
        assert.equal(run(['generate', '--kind', 'identity', '--out', cube]).status, 0);
        for (const kind of IMAGE_KINDS) {
            const input = path.join(dir, `${kind}.rgba`);
            const output = path.join(dir, `${kind}.out.rgba`);
            assert.equal(run(['gen-image', '--kind', kind, '--width', '96', '--height', '48', '--out', input]).status, 0);
            assert.equal(run(['apply', '--lut', cube, '--in', input, '--out', output, '--width', '96', '--height', '48']).status, 0);
            assert.ok(
                fs.readFileSync(output).equals(fs.readFileSync(input)),
                `identity apply 后 ${kind} 应与输入逐字节相等`,
            );
        }
    });
});

test('identity 对全部 256 级灰阶逐字节保真', () => {
    withTempDirectory((dir) => {
        const cube = path.join(dir, 'identity.cube');
        run(['generate', '--kind', 'identity', '--out', cube]);
        const input = path.join(dir, 'ramp.rgba');
        run(['gen-image', '--kind', 'gray-ramp', '--width', '256', '--height', '2', '--out', input]);
        const output = path.join(dir, 'ramp.out.rgba');
        run(['apply', '--lut', cube, '--in', input, '--out', output, '--width', '256', '--height', '2']);
        assert.ok(fs.readFileSync(output).equals(fs.readFileSync(input)));
    });
});

test('17³ 二次曲线 LUT 重采样到 32³：手工闭式对照', () => {
    // 源 LUT：out = ((r/16)^2, g/16, b/16)。二次曲线三线性重采样后，
    // 网格点 i 的 R 通道闭式解为相邻两源格点值的线性插值（插值二次曲线 ≠ 二次曲线本身）。
    const source = buildLut(17, (r, g, b) => [r * r, g, b]);
    const lut = resampleTo32(source);
    assert.equal(lut.size, 32);
    const closedForm = (i) => {
        const u = (i * 16) / 31;
        const k = Math.min(Math.floor(u), 15);
        const f = u - k;
        return (1 - f) * (k / 16) ** 2 + f * ((k + 1) / 16) ** 2;
    };
    for (const i of [0, 1, 7, 15, 23, 30, 31]) {
        const [r, g, b] = sampleLut(lut, i / 31, i / 31, i / 31);
        assert.ok(Math.abs(r - closedForm(i)) < 1e-12, `i=${i} R 通道：期望 ${closedForm(i)}，实际 ${r}`);
        assert.ok(Math.abs(g - i / 31) < 1e-12, `i=${i} G 通道（线性应保持精确）：期望 ${i / 31}，实际 ${g}`);
        assert.ok(Math.abs(b - i / 31) < 1e-12, `i=${i} B 通道（线性应保持精确）：期望 ${i / 31}，实际 ${b}`);
    }
    // 手算锚点：i=15 时 u=240/31=7.741935…，k=7、f=23/31，
    // R = (8/31)*(7/16)^2 + (23/31)*(8/16)^2 = 7.28125/31 ≈ 0.234879032258
    const [r15] = sampleLut(lut, 15 / 31, 0, 0);
    assert.ok(Math.abs(r15 - 7.28125 / 31) < 1e-12, `i=15 手算锚点：期望 ${7.28125 / 31}，实际 ${r15}`);
    // 端点精确、单调不减
    assert.equal(sampleLut(lut, 0, 0, 0)[0], 0);
    assert.equal(sampleLut(lut, 1, 1, 1)[0], 1);
    for (const i of Array.from({ length: 31 }, (_, index) => index)) {
        assert.ok(closedForm(i) <= closedForm(i + 1), `闭式解应单调不减：i=${i}`);
    }
});

test('16/32/33/64 尺寸解析与重采样，32³ 原样通过', () => {
    for (const size of [16, 32, 33, 64]) {
        const text = serializeCube(buildLut(size, (r, g, b) => [r, g, b]));
        const parsed = parseCube(text, `synthetic-${size}.cube`);
        assert.equal(parsed.size, size);
        const lut = resampleTo32(parsed);
        assert.equal(lut.size, 32);
        // 恒等源重采样后仍是恒等：抽查对角网格点（serialize 六位小数量化，容差 2e-6）
        for (const i of [0, 11, 31]) {
            const [r, g, b] = sampleLut(lut, i / 31, i / 31, i / 31);
            assert.ok(
                Math.abs(r - i / 31) < 2e-6 && Math.abs(g - i / 31) < 2e-6 && Math.abs(b - i / 31) < 2e-6,
                `size=${size} i=${i}：期望 ${i / 31}，实际 [${r}, ${g}, ${b}]`,
            );
        }
        if (size === 32) assert.equal(lut, parsed, '32³ 不应产生新对象');
        else assert.equal(lut.resampledFrom, size);
    }
});

test('TITLE / DOMAIN_MIN / DOMAIN_MAX 解析与域映射', () => {
    const text = [
        'TITLE "domain probe"',
        'LUT_3D_SIZE 16',
        'DOMAIN_MIN 0.0 0.0 0.0',
        'DOMAIN_MAX 0.5 0.5 0.5',
        ...Array.from({ length: 16 ** 3 }, (_, index) => {
            const r = index % 16; const g = Math.floor(index / 16) % 16; const b = Math.floor(index / 256);
            return `${(r / 15).toFixed(6)} ${(g / 15).toFixed(6)} ${(b / 15).toFixed(6)}`;
        }),
        '',
    ].join('\n');
    const parsed = parseCube(text, 'domain.cube');
    assert.equal(parsed.title, 'domain probe');
    assert.deepEqual(parsed.domainMax, [0.5, 0.5, 0.5]);
    // 域 [0,0.5]：输入 0.25 应映射到网格中点 7.5，输出 ≈ 0.5*0.5 = 0.25 的恒等（在域内）
    const [r] = sampleLut(parsed, 0.25, 0.25, 0.25);
    assert.ok(Math.abs(r - 0.5) < 2e-6, `域映射：输入 0.25（域中点）应得归一化 0.5，实际 ${r}`);
});

test('解析明确拒绝：未知关键字 / LUT_1D_SIZE / 行数不完整 / 非有限值', () => {
    assert.throws(() => parseCube('LUT_3D_SIZE 16\nFOO_BAR 1\n', 'bad.cube'), /未知关键字：FOO_BAR/);
    assert.throws(() => parseCube('LUT_1D_SIZE 16\n', 'bad.cube'), /不支持 LUT_1D_SIZE/);
    const truncated = ['LUT_3D_SIZE 16', ...Array.from({ length: 16 ** 3 - 1 }, () => '0 0 0')].join('\n');
    assert.throws(() => parseCube(truncated, 'bad.cube'), /数据行数不完整：期望 4096 行（16\^3），实际 4095 行/);
    const notFinite = ['LUT_3D_SIZE 16', ...Array.from({ length: 16 ** 3 }, (_, i) => (i === 5 ? '0 nan 0' : '0 0 0'))].join('\n');
    assert.throws(() => parseCube(notFinite, 'bad.cube'), /非有限数值/);
});

test('serialize→parse 往返：六款生成器数据量化误差 ≤ 5e-7', () => {
    for (const kind of GENERATOR_KINDS) {
        const lut = generateLut(kind);
        assert.equal(lut.size, 32);
        const parsed = parseCube(serializeCube(lut, { title: lut.title }), `${kind}.cube`);
        assert.equal(parsed.title, lut.title);
        assert.equal(parsed.size, 32);
        assert.equal(parsed.data.length, lut.data.length);
        for (let i = 0; i < lut.data.length; i += 1) {
            assert.ok(Math.abs(parsed.data[i] - lut.data[i]) <= 5e-7, `${kind} 偏移 ${i} 量化误差超限`);
        }
    }
});

test('生成器端点语义：identity 恒等、夜视暗部抬升与高光裁切、satclip 中性灰不变', () => {
    const identity = generateLut('identity');
    const identitySample = sampleLut(identity, 0.2, 0.5, 0.8);
    [0.2, 0.5, 0.8].forEach((v, i) => {
        assert.ok(Math.abs(identitySample[i] - v) < 1e-12, `identity 采样 ${v} 应保真，实际 ${identitySample[i]}`);
    });
    const green = generateLut('nightvision-green');
    const dark = sampleLut(green, 0, 0, 0);
    assert.ok(dark[1] > 0.04 && dark[1] < 0.05, `夜视暗部抬升应 ≈0.045，实际 ${dark[1]}`);
    const bright = sampleLut(green, 1, 1, 1);
    assert.equal(bright[1], 1, '夜视高光应裁切到 1');
    const satclip = generateLut('stress-satclip');
    const gray = sampleLut(satclip, 0.4, 0.4, 0.4);
    assert.ok(Math.abs(gray[0] - 0.4) < 1e-12, `中性灰经 satclip 应不变，实际 ${gray[0]}`);
    const red = sampleLut(satclip, 1, 0, 0);
    assert.equal(red[0], 1, '纯红 R 通道保持 1');
    assert.equal(red[2], 0, '纯红 B 通道裁到 0');
    const darkcurve = generateLut('stress-darkcurve');
    // 折点 0.25 落在 32³ 网格点 7（7/31≈0.2258）与 8（8/31≈0.2581）之间，逐格点核对分段曲线值
    assert.ok(Math.abs(sampleLut(darkcurve, 7 / 31, 7 / 31, 7 / 31)[0] - (7 / 31) * 0.2) < 1e-9, 'darkcurve 网格点 7（深压段）');
    assert.ok(Math.abs(sampleLut(darkcurve, 8 / 31, 8 / 31, 8 / 31)[0] - (0.05 + (8 / 31 - 0.25) * 1.4)) < 1e-9, 'darkcurve 网格点 8（陡升段）');
    assert.equal(sampleLut(darkcurve, 0, 0, 0)[0], 0, 'darkcurve 端点 0→0');
    assert.ok(Math.abs(sampleLut(darkcurve, 1, 1, 1)[0] - 1) < 1e-12, 'darkcurve 端点 1→1');
});

test('gen-image 三种：字节数与锚点像素', () => {
    const width = 96; const height = 48;
    for (const kind of IMAGE_KINDS) {
        const image = generateImage(kind, width, height);
        assert.equal(image.length, width * height * 4, `${kind} 字节数`);
    }
    const dark = generateImage('dark-gradient', width, height);
    const px = (buffer, x, y) => [0, 1, 2, 3].map((c) => buffer[(y * width + x) * 4 + c]);
    assert.deepEqual(px(dark, 0, 0), [0, 0, 0, 255], 'dark-gradient 原点为黑');
    assert.deepEqual(px(dark, width - 1, 0), [64, 64, 64, 255], 'dark-gradient 灰带右端 ≈64');
    assert.deepEqual(px(dark, width - 1, 20), [64, 0, 0, 255], 'dark-gradient R 带右端');
    assert.deepEqual(px(dark, width - 1, 47), [0, 0, 64, 255], 'dark-gradient B 带右端');
    const primaries = generateImage('primaries', width, height);
    assert.deepEqual(px(primaries, 12, 12), [255, 0, 0, 255], 'primaries 左上块为红');
    assert.deepEqual(px(primaries, 84, 12), [255, 255, 255, 255], 'primaries 右上块为白');
    assert.deepEqual(px(primaries, 84, 36), [128, 128, 128, 255], 'primaries 右下块为灰50');
    const ramp = generateImage('gray-ramp', width, height);
    assert.deepEqual(px(ramp, 0, 0), [0, 0, 0, 255], 'gray-ramp 平滑段左端为 0');
    assert.deepEqual(px(ramp, width - 1, 0), [255, 255, 255, 255], 'gray-ramp 平滑段右端为 255');
    assert.equal(px(ramp, width - 1, 36)[0], 255, 'gray-ramp 阶梯段右端为 255');
    assert.ok(px(ramp, 0, 36)[0] === 0, 'gray-ramp 阶梯段左端为 0');
});

test('CLI inspect：正常文件退出 0 且输出尺寸/域/范围，截断文件退出 2', () => {
    withTempDirectory((dir) => {
        const cube = path.join(dir, 'identity.cube');
        run(['generate', '--kind', 'identity', '--out', cube]);
        const ok = run(['inspect', cube]);
        assert.equal(ok.status, 0, ok.stderr);
        assert.match(ok.stdout, /LUT_3D_SIZE：32/);
        assert.match(ok.stdout, /数据行数：32768（期望 32\^3=32768，完整）/);
        assert.match(ok.stdout, /数值范围 R：\[0, 1\]/);
        const truncated = path.join(dir, 'truncated.cube');
        fs.writeFileSync(truncated, 'LUT_3D_SIZE 16\n0 0 0\n');
        const bad = run(['inspect', truncated]);
        assert.equal(bad.status, 2);
        assert.match(bad.stderr, /数据行数不完整/);
        const usage = run(['inspect']);
        assert.equal(usage.status, 64);
    });
});

test('CLI apply 对 17³ LUT 自动重采样并在输出中声明', () => {
    withTempDirectory((dir) => {
        const cube17 = path.join(dir, 'ramp17.cube');
        fs.writeFileSync(cube17, serializeCube(buildLut(17, (r, g, b) => [r, g, b]), { title: 'ramp17' }));
        const input = path.join(dir, 'in.rgba');
        run(['gen-image', '--kind', 'gray-ramp', '--width', '256', '--height', '2', '--out', input]);
        const output = path.join(dir, 'out.rgba');
        const applied = run(['apply', '--lut', cube17, '--in', input, '--out', output, '--width', '256', '--height', '2']);
        assert.equal(applied.status, 0, applied.stderr);
        assert.match(applied.stdout, /已三线性重采样到 32³/);
        // 17³ 恒等 ramp 重采样后仍是恒等：输出与输入逐字节相等
        assert.ok(fs.readFileSync(output).equals(fs.readFileSync(input)));
    });
});

test('bake-ramp 配方锚点：整数档精确取锚点值，L7 全参数恒等', () => {
    const recipe = ramp.RECIPES['natural-daynight-v1'];
    for (let level = 0; level <= 9; level++) {
        const p = ramp.paramsAt(recipe, level);
        for (const field of ramp.ANCHOR_FIELDS) {
            assert.equal(p[field], recipe.anchors[level][field], `L${level}.${field} 应取锚点值`);
        }
    }
    const p7 = ramp.paramsAt(recipe, 7);
    for (const field of ramp.ANCHOR_FIELDS) assert.equal(p7[field], 0, `L7 参数 ${field} 应为 0（恒等）`);
    // 参数函数在锚点间 smoothstep 连续（中点值在两端之间）
    const mid = ramp.paramsAt(recipe, 4.5);
    for (const field of ramp.ANCHOR_FIELDS) {
        const a = recipe.anchors[4][field];
        const b = recipe.anchors[5][field];
        assert.ok(mid[field] >= Math.min(a, b) - 1e-12 && mid[field] <= Math.max(a, b) + 1e-12,
            `L4.5.${field} 应在锚点之间`);
    }
});

test('bake-ramp L7 全管线 256 级灰阶逐字节保真 + L7 cube 数据 == identity cube', () => {
    const recipe = ramp.RECIPES['natural-daynight-v1'];
    assert.deepEqual(ramp.checkIdentityRoundTrip(recipe), [], 'L7 全管线 256 级灰阶应逐字节保真');
    const l7 = ramp.buildLevelLut(recipe, 7);
    const identity = buildLut(32, (r, g, b) => [r, g, b]);
    const stripTitle = (text) => text.replace(/^TITLE .*\n/, '');
    assert.equal(
        stripTitle(serializeCube(l7)),
        stripTitle(serializeCube(identity)),
        'L7 cube 数据应与 identity cube 逐字节一致（除 TITLE 行）',
    );
});

test('bake-ramp 灰阶 luma 随等级单调不降（8/16 级）', () => {
    const recipe = ramp.RECIPES['natural-daynight-v1'];
    assert.deepEqual(ramp.checkMonotonic(ramp.grayscaleLumaTable(recipe, 8)).failures, [], '灰阶 8 级单调性');
    assert.deepEqual(ramp.checkMonotonic(ramp.grayscaleLumaTable(recipe, 16)).failures, [], '灰阶 16 级单调性');
});

test('bake-ramp 确定性：同参数重跑序列化逐字节一致', () => {
    const recipe = ramp.RECIPES['natural-daynight-v1'];
    for (const level of [0, 3, 7, 9]) {
        const a = serializeCube(ramp.buildLevelLut(recipe, level));
        const b = serializeCube(ramp.buildLevelLut(recipe, level));
        assert.equal(a, b, `L${level} 重跑应逐字节一致`);
    }
});

test('bake-ramp 产出 cube 解析/重采样路径不受影响（32³ 原样通过 + 17³/64³ 既有语义）', () => {
    const recipe = ramp.RECIPES['natural-daynight-v1'];
    for (let level = 0; level <= 9; level++) {
        const parsed = parseCube(serializeCube(ramp.buildLevelLut(recipe, level)), `光照-${level}.cube`);
        assert.equal(parsed.size, 32);
        const lut = resampleTo32(parsed);
        assert.equal(lut.size, 32);
        assert.equal(lut, parsed, '32³ 不应产生新对象');
    }
    // 17³/64³ 重采样既有语义保持
    for (const size of [17, 64]) {
        const parsed = parseCube(
            serializeCube(buildLut(size, (r, g, b) => [r, g, b])),
            `synthetic-${size}.cube`,
        );
        assert.equal(parsed.size, size);
        assert.equal(resampleTo32(parsed).size, 32);
    }
});

test('CLI bake-ramp 端到端：10 档 + preset.json + manifest 幂等 upsert + 确定性 SHA 一致', () => {
    withTempDirectory((dir) => {
        const first = run(['bake-ramp', '--kind', 'natural-daynight-v1', '--out', dir]);
        assert.equal(first.status, 0, first.stderr);
        assert.ok(/L7 identity：PASS/.test(first.stdout), '应打印 L7 identity PASS');
        assert.ok(/单调性：PASS/.test(first.stdout), '应打印单调性 PASS');
        const setDir = path.join(dir, 'natural-daynight-v1');
        assert.ok(fs.existsSync(path.join(setDir, 'preset.json')));
        for (let i = 0; i <= 9; i++) {
            assert.ok(fs.existsSync(path.join(setDir, `光照-${i}.cube`)), `光照-${i}.cube 应存在`);
        }
        const preset = JSON.parse(fs.readFileSync(path.join(setDir, 'preset.json'), 'utf8'));
        assert.equal(preset.generator, 'bake-ramp');
        assert.equal(preset.mode, '光照');
        assert.equal(preset.timeMapping.array.length, 24, '权威时间映射数组应为 24 小时');
        assert.equal(preset.anchors.length, 10);
        const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.sets.json'), 'utf8'));
        assert.equal(manifest.length, 1);
        assert.equal(manifest[0].name, 'natural-daynight-v1');
        assert.equal(manifest[0].mode, '光照');
        assert.equal(manifest[0].files.length, 10);
        assert.ok(manifest[0].notes.includes('验收用'));
        const sha1 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(first.stdout)[1];
        const second = run(['bake-ramp', '--kind', 'natural-daynight-v1', '--out', dir]);
        assert.equal(second.status, 0, second.stderr);
        const sha2 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(second.stdout)[1];
        assert.equal(sha1, sha2, '重跑 SHA-256 应一致');
        const manifest2 = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.sets.json'), 'utf8'));
        assert.equal(manifest2.length, 1, '重跑 manifest 仍应为 1 条（幂等 upsert）');
        // 写出 cube 可解析且为 32³
        const parsed = parseCube(fs.readFileSync(path.join(setDir, '光照-7.cube'), 'utf8'), '光照-7.cube');
        assert.equal(parsed.size, 32);
    });
});

test('bake-ramp v2 暖窗隶属与豁免权重：窗口内/羽化/窗外/灰色', () => {
    assert.equal(ramp.warmWindowMembership(20), 1, '暖窗核心（20°）应全隶属');
    assert.equal(ramp.warmWindowMembership(355), 1, '暖窗核心（355°，环绕）应全隶属');
    assert.ok(Math.abs(ramp.warmWindowMembership(55) - 0.5) < 1e-9, '羽化中点（55°）应为 0.5');
    assert.equal(ramp.warmWindowMembership(60), 0, '窗外（60°）应为 0');
    assert.equal(ramp.warmWindowMembership(340), 0, '窗外（340°）应为 0');
    assert.equal(ramp.warmWindowMembership(200), 0, '冷色（200°）应为 0');
    const recipe = ramp.RECIPES['natural-daynight-v2'];
    const p1 = ramp.paramsAt(recipe, 1);
    assert.ok(ramp.warmProtectionWeight(p1, 1.0, 0.45, 0.10) > 0.3, '高饱和橙应有显著豁免');
    assert.equal(ramp.warmProtectionWeight(p1, 0.15, 0.5, 1.0), 0, '高饱和蓝（窗外）豁免应为 0');
    assert.equal(ramp.warmProtectionWeight(p1, 0.5, 0.5, 0.5), 0, '中性灰豁免应为 0');
    assert.equal(ramp.warmProtectionWeight(ramp.paramsAt(recipe, 7), 1.0, 0.45, 0.10), 0, 'L7 豁免恒零');
});

test('bake-ramp v2 插值档参数介于相邻锚点之间，锚点档精确取值', () => {
    const recipe = ramp.RECIPES['natural-daynight-v2'];
    const levels = recipe.anchorLevels;
    const scalarFields = [...ramp.ANCHOR_FIELDS, ...ramp.V2_SCALAR_FIELDS];
    for (const t of [2, 3, 6, 8]) {
        let seg = 0;
        while (t > levels[seg + 1]) seg++;
        const p = ramp.paramsAt(recipe, t);
        const a = ramp.anchorParams(recipe, recipe.anchors[seg]);
        const b = ramp.anchorParams(recipe, recipe.anchors[seg + 1]);
        for (const field of scalarFields) {
            const lo = Math.min(a[field], b[field]) - 1e-12;
            const hi = Math.max(a[field], b[field]) + 1e-12;
            assert.ok(p[field] >= lo && p[field] <= hi, `L${t}.${field}=${p[field]} 应在锚点区间 [${lo}, ${hi}]`);
        }
        for (const field of ramp.TINT_FIELDS) {
            const lo = Math.min(a[field].strength, b[field].strength) - 1e-12;
            const hi = Math.max(a[field].strength, b[field].strength) + 1e-12;
            assert.ok(p[field].strength >= lo && p[field].strength <= hi, `L${t}.${field}.strength 应在锚点区间`);
        }
    }
    for (let i = 0; i < levels.length; i++) {
        const p = ramp.paramsAt(recipe, levels[i]);
        const a = ramp.anchorParams(recipe, recipe.anchors[i]);
        for (const field of scalarFields) assert.equal(p[field], a[field], `L${levels[i]}.${field} 应取锚点值`);
        for (const field of ramp.TINT_FIELDS) assert.equal(p[field].strength, a[field].strength, `L${levels[i]}.${field}.strength 应取锚点值`);
    }
});

test('bake-ramp v2 双变体：L7 同为恒等、差异存在、单调性（v2m 含受控回落标注）', () => {
    const v2 = ramp.RECIPES['natural-daynight-v2'];
    const v2m = ramp.RECIPES['natural-daynight-v2m'];
    assert.deepEqual(ramp.checkIdentityRoundTrip(v2), [], 'v2 L7 应逐字节恒等');
    assert.deepEqual(ramp.checkIdentityRoundTrip(v2m), [], 'v2m L7 应逐字节恒等');
    for (const steps of [8, 16]) {
        assert.deepEqual(
            ramp.checkMonotonic(ramp.grayscaleLumaTable(v2, steps)).failures, [],
            `v2 灰阶 ${steps} 级应严格单调`,
        );
        const m = ramp.checkMonotonic(ramp.grayscaleLumaTable(v2m, steps), undefined, v2m.fadeAllowance);
        assert.deepEqual(m.failures, [], `v2m 灰阶 ${steps} 级许可外应无反相`);
        assert.ok(m.allowed.length > 0, `v2m 灰阶 ${steps} 级应有黑位淡出受控回落记录`);
        for (const entry of m.allowed) {
            const delta = Math.abs(Number(/Δ=(-?[\d.]+)/.exec(entry)[1]));
            assert.ok(delta <= v2m.fadeAllowance.maxDrop, `受控回落「${entry}」应 ≤ maxDrop`);
            const gray = Number(/灰阶 ([\d.]+)/.exec(entry)[1]);
            assert.ok(gray <= v2m.fadeAllowance.maxGray, `受控回落「${entry}」应仅落在近黑灰阶`);
        }
    }
    const [a0] = ramp.evaluateTexel(ramp.paramsAt(v2, 0), 0, 0, 0);
    const [m0] = ramp.evaluateTexel(ramp.paramsAt(v2m, 0), 0, 0, 0);
    assert.ok(m0 > a0, 'v2m 近黑应亮于 v2（奶灰底）');
    assert.equal(a0, 0, 'v2 近黑应压死（toe 防伽马破解）');
    const maxV2 = ramp.grayscaleLumaTable(v2, 16)[0][15];
    const maxV2m = ramp.grayscaleLumaTable(v2m, 16)[0][15];
    assert.ok(maxV2m > maxV2, `v2m L0 顶灰 ${maxV2m.toFixed(3)} 应亮于 v2 ${maxV2.toFixed(3)}`);
    assert.ok(maxV2 <= v2.l0LumaCeiling, 'v2 L0 刚需线不破');
    assert.ok(maxV2m <= v2m.l0LumaCeiling, 'v2m L0 刚需线不破');
});

test('CLI bake-ramp v2 双变体端到端：产出 + manifest 幂等 + 暖色保护断言行', () => {
    withTempDirectory((dir) => {
        for (const kind of ['natural-daynight-v2', 'natural-daynight-v2m']) {
            const first = run(['bake-ramp', '--kind', kind, '--out', dir]);
            assert.equal(first.status, 0, first.stderr);
            assert.ok(/L7 identity：PASS/.test(first.stdout), `${kind} 应打印 L7 identity PASS`);
            assert.ok(/暖色保护：PASS/.test(first.stdout), `${kind} 应打印暖色保护 PASS`);
            assert.ok(/高饱和橙（暖窗内）/.test(first.stdout), `${kind} 应打印暖色保护对照表`);
            assert.ok(/顶灰 luma=/.test(first.stdout), `${kind} 应打印 L0 顶灰刚需线`);
            const setDir = path.join(dir, kind);
            assert.ok(fs.existsSync(path.join(setDir, 'preset.json')));
            for (let i = 0; i <= 9; i++) {
                assert.ok(fs.existsSync(path.join(setDir, `光照-${i}.cube`)), `${kind} 光照-${i}.cube 应存在`);
            }
            const preset = JSON.parse(fs.readFileSync(path.join(setDir, 'preset.json'), 'utf8'));
            assert.equal(preset.anchorLevels.length, 6, `${kind} 应为 6 锚点结构`);
            assert.ok(preset.structure.includes('参数空间插值'), `${kind} 应注明插值语义`);
            const sha1 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(first.stdout)[1];
            const second = run(['bake-ramp', '--kind', kind, '--out', dir]);
            assert.equal(second.status, 0, second.stderr);
            const sha2 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(second.stdout)[1];
            assert.equal(sha1, sha2, `${kind} 重跑 SHA-256 应一致`);
        }
        const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.sets.json'), 'utf8'));
        assert.equal(manifest.length, 2, '两变体应各占一条 manifest');
        assert.deepEqual(manifest.map((entry) => entry.name).sort(), ['natural-daynight-v2', 'natural-daynight-v2m']);
        assert.ok(manifest.every((entry) => entry.notes.includes('bake-ramp v2 候选')), 'manifest 条目标注应为 bake-ramp v2 候选');
    });
});

test('bake-ramp 族扩四族：L7 恒等、单调性、与 v2 的差异存在、neon 暖窗收窄', () => {
    const v2 = ramp.RECIPES['natural-daynight-v2'];
    const whiteSag = { maxSag: 0.001 };
    const families = ['cinematic-teal-orange-v1', 'war-bleach-v1', 'film-print-v1', 'neon-city-v1'];
    for (const name of families) {
        const recipe = ramp.RECIPES[name];
        assert.ok(recipe, `${name} 应存在`);
        assert.deepEqual(ramp.checkIdentityRoundTrip(recipe), [], `${name} L7 应逐字节恒等`);
        for (const steps of [8, 16]) {
            const m = ramp.checkMonotonic(
                ramp.grayscaleLumaTable(recipe, steps),
                undefined,
                recipe.fadeAllowance,
                whiteSag,
            );
            assert.deepEqual(m.failures, [], `${name} 灰阶 ${steps} 级单调（许可外无反相）`);
        }
        const a = ramp.evaluateTexel(ramp.paramsAt(recipe, 1), 0.3, 0.2, 0.15);
        const b = ramp.evaluateTexel(ramp.paramsAt(v2, 1), 0.3, 0.2, 0.15);
        assert.notDeepEqual(a, b, `${name} 与 v2 应有可辨差异`);
        if (recipe.l0LumaCeiling) {
            const max0 = ramp.grayscaleLumaTable(recipe, 16)[0][15];
            assert.ok(max0 <= recipe.l0LumaCeiling, `${name} L0 顶灰 ${max0.toFixed(3)} 应 ≤ ${recipe.l0LumaCeiling}`);
        }
    }
    const neon = ramp.RECIPES['neon-city-v1'];
    assert.equal(ramp.warmWindowMembership(320, neon.warmWindow), 0, 'neon 暖窗外（品红 320°）');
    assert.equal(ramp.warmWindowMembership(20, neon.warmWindow), 1, 'neon 暖窗内（纯橙 20°）');
    assert.equal(ramp.warmWindowMembership(320), 0, '默认窗口外（品红 320°）');
    assert.equal(ramp.warmWindowMembership(20), 1, '默认窗口内（橙 20°）');
    const p1 = ramp.paramsAt(neon, 1);
    assert.notDeepEqual(
        ramp.evaluateTexel(p1, 0.05, 0.05, 0.08),
        ramp.evaluateTexel(p1, 0.35, 0.35, 0.40),
        'neon 暗部青/品红双色倾向应按 luma 产生不同响应',
    );
    const war = ramp.RECIPES['war-bleach-v1'];
    assert.equal(ramp.paramsAt(war, 7).satPct, 0, 'war-bleach t=7 satPct 应为 0（恒等锚点语义不破）');
    assert.ok(ramp.paramsAt(war, 9).satPct <= -20, 'war-bleach 白天降饱和 ≥20');
});

test('CLI bake-ramp 族扩端到端：四族产出 + manifest 幂等 + 自检断言行', () => {
    withTempDirectory((dir) => {
        const kinds = ['cinematic-teal-orange-v1', 'war-bleach-v1', 'film-print-v1', 'neon-city-v1'];
        for (const kind of kinds) {
            const first = run(['bake-ramp', '--kind', kind, '--out', dir]);
            assert.equal(first.status, 0, first.stderr);
            assert.ok(/L7 identity：PASS/.test(first.stdout), `${kind} 应打印 L7 identity PASS`);
            assert.ok(/单调性：PASS/.test(first.stdout), `${kind} 应打印单调性 PASS`);
            assert.ok(/暖色保护：PASS|暖色保护：N\/A/.test(first.stdout), `${kind} 应打印暖色保护结论`);
            assert.ok(/顶灰 luma=/.test(first.stdout), `${kind} 应打印 L0 顶灰`);
            const setDir = path.join(dir, kind);
            assert.ok(fs.existsSync(path.join(setDir, 'preset.json')));
            for (let i = 0; i <= 9; i++) {
                assert.ok(fs.existsSync(path.join(setDir, `光照-${i}.cube`)), `${kind} 光照-${i}.cube 应存在`);
            }
            const preset = JSON.parse(fs.readFileSync(path.join(setDir, 'preset.json'), 'utf8'));
            assert.equal(preset.anchorLevels.length, 6, `${kind} 应为 6 锚点结构`);
            assert.ok(preset.calibrationNote, `${kind} 应有设计意图说明`);
            const sha1 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(first.stdout)[1];
            const second = run(['bake-ramp', '--kind', kind, '--out', dir]);
            assert.equal(second.status, 0, second.stderr);
            const sha2 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(second.stdout)[1];
            assert.equal(sha1, sha2, `${kind} 重跑 SHA-256 应一致`);
        }
        const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.sets.json'), 'utf8'));
        assert.equal(manifest.length, kinds.length, '四族应各占一条 manifest');
        assert.deepEqual(manifest.map((entry) => entry.name).sort(), [...kinds].sort());
    });
});

test('青橙族细化变体：与 v1 的锚点差异结构、公共约束（暖豁免/L7/刚需线）', () => {
    const v1 = ramp.RECIPES['cinematic-teal-orange-v1'];
    const v2a = ramp.RECIPES['cinematic-teal-orange-v2a'];
    const v2b = ramp.RECIPES['cinematic-teal-orange-v2b'];
    const v2c = ramp.RECIPES['cinematic-teal-orange-v2c'];
    for (const v of [v2a, v2b, v2c]) {
        assert.ok(v, '变体配方应存在');
        assert.deepEqual(v.anchorLevels, [0, 1, 4, 5, 7, 9], '变体应为同 6 锚点结构');
        assert.equal(v.l0LumaCeiling, 0.28, '变体刚需线沿用族线 0.28');
        assert.deepEqual(
            v.anchors.map((a) => a.warmProtect),
            v1.anchors.map((a) => a.warmProtect),
            '暖色豁免曲线应沿用 v1（公共约束）',
        );
        assert.deepEqual(ramp.checkIdentityRoundTrip(v), [], '变体 L7 应逐字节恒等');
        for (const steps of [8, 16]) {
            const m = ramp.checkMonotonic(
                ramp.grayscaleLumaTable(v, steps), undefined, v.fadeAllowance, { maxSag: 0.001 });
            assert.deepEqual(m.failures, [], `灰阶 ${steps} 级许可外无反相`);
            for (const entry of m.allowed) {
                const delta = Math.abs(Number(/Δ=(-?[\d.]+)/.exec(entry)[1]));
                assert.ok(delta <= 0.001, `白点凹陷「${entry}」应在既有 0.001 边界内`);
            }
        }
        const max0 = ramp.grayscaleLumaTable(v, 16)[0][15];
        assert.ok(max0 <= 0.28, `L0 顶灰 ${max0.toFixed(3)} 不破刚需线`);
    }
    // v2a/v2b：夜档与晨昏锚点（L0/L1/L4/L5）与 v1 逐参数一致（夜档维持、晨昏维持）
    for (const v of [v2a, v2b]) {
        for (const i of [0, 1, 2, 3]) {
            assert.deepEqual(v.anchors[i], v1.anchors[i], `锚点 ${i} 应与 v1 一致`);
        }
        assert.deepEqual(v.anchors[4], v1.anchors[4], 'L7 恒等锚点与 v1 一致（全零）');
    }
    // v2a：仅 L9 split 收敛约一半，L9 其余字段与 v1 一致
    assert.ok(v2a.anchors[5].splitShadow.strength < v1.anchors[5].splitShadow.strength, 'v2a L9 暗部青收敛');
    assert.ok(v2a.anchors[5].splitHigh.strength < v1.anchors[5].splitHigh.strength, 'v2a L9 高光暖收敛');
    assert.equal(v2a.anchors[5].shoulder, v1.anchors[5].shoulder, 'v2a L9 shoulder 不变');
    assert.equal(v2a.anchors[5].hiDesat, v1.anchors[5].hiDesat, 'v2a L9 hiDesat 不变');
    // v2b：L9 split 接近干净（≤0.025），只剩 shoulder/desat
    assert.ok(v2b.anchors[5].splitShadow.strength <= 0.02, 'v2b L9 暗部青接近干净');
    assert.ok(v2b.anchors[5].splitHigh.strength <= 0.025, 'v2b L9 高光暖接近干净');
    assert.equal(v2b.anchors[5].shoulder, 0.42, 'v2b L9 shoulder 保留');
    assert.equal(v2b.anchors[5].hiDesat, 0.5, 'v2b L9 hiDesat 保留');
    // v2c：夜锚点 split 与 silverHigh 为 v1 ×1.2（chroma +20%）；L9 splitHigh 标定记录 0.16
    for (const i of [0, 1, 2, 3]) {
        for (const field of ['splitShadow', 'splitHigh', 'silverHigh']) {
            const got = v2c.anchors[i][field].strength;
            const want = v1.anchors[i][field].strength * 1.2;
            assert.ok(Math.abs(got - want) < 1e-9, `v2c 锚点${i} ${field}=${got} 应为 v1×1.2=${want}`);
        }
    }
    assert.equal(v2c.anchors[5].splitShadow.strength, 0.144, 'v2c L9 暗部青 ×1.2（白点不受暗部影响）');
    assert.ok(v2c.anchors[5].splitHigh.strength <= 0.16, 'v2c L9 高光暖受白点凹陷 0.001 边界标定');
});

test('青橙族细化变体：白天风格化强度排序 v2b < v2a < v1 < v2c，夜档 v2a==v2b', () => {
    const names = ['cinematic-teal-orange-v1', 'cinematic-teal-orange-v2a',
        'cinematic-teal-orange-v2b', 'cinematic-teal-orange-v2c'];
    const [v1, v2a, v2b, v2c] = names.map((n) => ramp.RECIPES[n]);
    // 青橙强度 = split-tone 通道自身的染色量（同参数置零 split 后与原件的输出差），
    // 与 shoulder/hiDesat 等共享形态参数解耦（它们三变体一致，不能用偏离输入度量）
    const texels = [[0.65, 0.50, 0.42], [0.30, 0.25, 0.20], [0.85, 0.80, 0.75]];
    const splitEffect = (recipe, level) => {
        const p = ramp.paramsAt(recipe, level);
        const off = Object.assign({}, p, {
            splitShadow: Object.assign({}, p.splitShadow, { strength: 0 }),
            splitHigh: Object.assign({}, p.splitHigh, { strength: 0 }),
        });
        let sum = 0;
        for (const [r, g, b] of texels) {
            const [ar, ag, ab] = ramp.evaluateTexel(p, r, g, b);
            const [br, bg, bb] = ramp.evaluateTexel(off, r, g, b);
            sum += Math.abs(ar - br) + Math.abs(ag - bg) + Math.abs(ab - bb);
        }
        return sum;
    };
    const d1 = splitEffect(v1, 9), da = splitEffect(v2a, 9), db = splitEffect(v2b, 9), dc = splitEffect(v2c, 9);
    assert.ok(db < da && da < d1 && d1 < dc,
        `L9 青橙强度应排序 v2b(${db.toFixed(4)}) < v2a(${da.toFixed(4)}) < v1(${d1.toFixed(4)}) < v2c(${dc.toFixed(4)})`);
    assert.ok(db < 0.05 && da < d1 * 0.7, 'v2b 白天应接近干净、v2a 应明显收敛');
    // 夜档：v2a 与 v2b 锚点逐参数一致 → L1 渲染逐点一致；v2c 夜风格更强
    const p1a = ramp.paramsAt(v2a, 1);
    const p1b = ramp.paramsAt(v2b, 1);
    assert.deepEqual(
        ramp.evaluateTexel(p1a, 0.30, 0.20, 0.15),
        ramp.evaluateTexel(p1b, 0.30, 0.20, 0.15),
        'v2a/v2b 夜档 L1 应一致（同一夜火力）',
    );
    assert.ok(splitEffect(v2c, 1) > splitEffect(v1, 1) * 1.15, 'v2c 夜档青橙强度应 ≈v1×1.2');
});

test('CLI bake-ramp 青橙族细化变体端到端：三变体产出 + manifest 幂等 + 自检断言行', () => {
    withTempDirectory((dir) => {
        const kinds = ['cinematic-teal-orange-v2a', 'cinematic-teal-orange-v2b', 'cinematic-teal-orange-v2c'];
        for (const kind of kinds) {
            const first = run(['bake-ramp', '--kind', kind, '--out', dir]);
            assert.equal(first.status, 0, first.stderr);
            assert.ok(/L7 identity：PASS/.test(first.stdout), `${kind} 应打印 L7 identity PASS`);
            assert.ok(/单调性：PASS/.test(first.stdout), `${kind} 应打印单调性 PASS`);
            assert.ok(/暖色保护：PASS/.test(first.stdout), `${kind} 应打印暖色保护 PASS（强豁免档）`);
            assert.ok(/顶灰 luma=/.test(first.stdout), `${kind} 应打印 L0 顶灰刚需线`);
            const setDir = path.join(dir, kind);
            for (let i = 0; i <= 9; i++) {
                assert.ok(fs.existsSync(path.join(setDir, `光照-${i}.cube`)), `${kind} 光照-${i}.cube 应存在`);
            }
            const preset = JSON.parse(fs.readFileSync(path.join(setDir, 'preset.json'), 'utf8'));
            assert.equal(preset.anchorLevels.length, 6, `${kind} 应为 6 锚点结构`);
            assert.ok(preset.calibrationNote.includes('与 v1 差异'), `${kind} preset.json 应注明与 v1 的差异点`);
            const sha1 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(first.stdout)[1];
            const second = run(['bake-ramp', '--kind', kind, '--out', dir]);
            assert.equal(second.status, 0, second.stderr);
            const sha2 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(second.stdout)[1];
            assert.equal(sha1, sha2, `${kind} 重跑 SHA-256 应一致`);
        }
        const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.sets.json'), 'utf8'));
        assert.equal(manifest.length, 3, '三变体应各占一条 manifest');
        assert.deepEqual(manifest.map((entry) => entry.name).sort(), [...kinds].sort());
    });
});

test('青橙 v3 主干：黄昏橙峰结构（L5>L4>L6≈0）、夜档冷银蓝、刚需线收紧、暖豁免沿用', () => {
    const v1 = ramp.RECIPES['cinematic-teal-orange-v1'];
    const v3names = ['cinematic-dusk-peak-v3a', 'cinematic-dusk-peak-v3b', 'cinematic-dusk-peak-v3c'];
    for (const name of v3names) {
        const r = ramp.RECIPES[name];
        assert.ok(r, `${name} 应存在`);
        assert.deepEqual(r.anchorLevels, [0, 1, 4, 5, 6, 7, 9], `${name} 应为 7 锚点（L6 显式近零锚）`);
        // 黄昏橙峰：L5 极值 > L4 加强 > L6 近零
        assert.equal(r.anchors[3].splitHigh.strength, 0.30, `${name} L5 橙峰 0.30`);
        assert.ok(r.anchors[3].splitHigh.strength >= v1.anchors[3].splitHigh.strength * 1.5,
            `${name} L5 暖强度应 ≥ v1×1.5`);
        assert.ok(r.anchors[2].splitHigh.strength > v1.anchors[2].splitHigh.strength,
            `${name} L4 暖侧应强于 v1（0.22）`);
        assert.ok(r.anchors[3].splitHigh.strength > r.anchors[2].splitHigh.strength,
            `${name} 峰结构 L5 > L4`);
        assert.ok(r.anchors[4].splitHigh.strength <= 0.001 && r.anchors[4].splitShadow.strength <= 0.001,
            `${name} L6 split 应近零`);
        assert.equal(r.anchors[3].splitHigh.hue, 30, `${name} 橙峰保持 30° 暖橙`);
        // 夜档青蓝纯净：splitHigh 冷银蓝（暖窗外），splitShadow 钢青保持；暖只经豁免
        for (const i of [0, 1]) {
            assert.equal(r.anchors[i].splitHigh.hue, 205, `${name} 夜档 L${i} splitHigh 应冷银蓝 205°`);
            assert.equal(ramp.warmWindowMembership(r.anchors[i].splitHigh.hue, null), 0,
                `${name} 夜档 splitHigh 必须在暖窗外（不加暖）`);
            assert.equal(r.anchors[i].splitShadow.hue, 190, `${name} 夜档 splitShadow 钢青保持`);
        }
        // 暖色豁免沿用 v1 强度（族核心资产）
        assert.deepEqual(
            r.anchors.map((a) => a.warmProtect),
            [0.95, 0.92, 0.60, 0, 0, 0, 0],
            `${name} warmProtect 曲线应沿用 v1`,
        );
        const probeL1 = ramp.warmProtectionProbe(r, 1);
        assert.ok(probeL1[0].retention >= probeL1[1].retention + 0.05,
            `${name} 夜档暖火保留应显著高于蓝`);
        // L7 恒等 + 单调性（许可内）+ 收紧刚需线
        assert.deepEqual(ramp.checkIdentityRoundTrip(r), [], `${name} L7 应逐字节恒等`);
        for (const steps of [8, 16]) {
            const m = ramp.checkMonotonic(
                ramp.grayscaleLumaTable(r, steps), undefined, r.fadeAllowance, { maxSag: 0.001 });
            assert.deepEqual(m.failures, [], `${name} 灰阶 ${steps} 级许可外无反相`);
        }
        const t16 = ramp.grayscaleLumaTable(r, 16);
        assert.ok(t16[0][15] <= 0.15, `${name} L0 顶灰 ${t16[0][15].toFixed(3)} 应 ≤ 0.15（收紧线）`);
        assert.ok(t16[1][15] <= 0.22, `${name} L1 顶灰 ${t16[1][15].toFixed(3)} 应 ≤ 0.22（收紧线）`);
        // 收紧实测：L0/L1 顶灰必须显著低于 v1（v1=0.187/0.306）
        const v1t = ramp.grayscaleLumaTable(v1, 16);
        assert.ok(t16[0][15] < v1t[0][15] - 0.03, `${name} L0 顶灰应显著低于 v1`);
        assert.ok(t16[1][15] < v1t[1][15] - 0.06, `${name} L1 顶灰应显著低于 v1`);
    }
});

test('青橙 v3 正午三形态：互异、主干共享、白天 split 同一收敛、各自语义可辨', () => {
    const [v3a, v3b, v3c] = ['cinematic-dusk-peak-v3a', 'cinematic-dusk-peak-v3b', 'cinematic-dusk-peak-v3c']
        .map((n) => ramp.RECIPES[n]);
    // 主干共享：L0/L1/L4/L5/L6/L7 锚点逐参数一致
    for (let i = 0; i <= 5; i++) {
        assert.deepEqual(v3a.anchors[i], v3b.anchors[i], `v3a/v3b 锚点${i} 应共享`);
        assert.deepEqual(v3a.anchors[i], v3c.anchors[i], `v3a/v3c 锚点${i} 应共享`);
    }
    // L9 锚点两两互异，但 split 收敛一致（差异在曝光响应/对比/脱色/黑位，不在青橙）
    const l9 = [v3a, v3b, v3c].map((r) => r.anchors[6]);
    assert.notDeepEqual(l9[0], l9[1]); assert.notDeepEqual(l9[0], l9[2]); assert.notDeepEqual(l9[1], l9[2]);
    for (const a of l9) {
        assert.equal(a.splitShadow.strength, 0.06, '三形态 L9 splitShadow 同一收敛');
        assert.equal(a.splitHigh.strength, 0.07, '三形态 L9 splitHigh 同一收敛');
    }
    // 渲染互异（亮部 texel）
    const out = [v3a, v3b, v3c].map((r) => ramp.evaluateTexel(ramp.paramsAt(r, 9), 0.85, 0.78, 0.70));
    assert.notDeepEqual(out[0], out[1]); assert.notDeepEqual(out[0], out[2]); assert.notDeepEqual(out[1], out[2]);
    // 形态语义：v3c 黑位抬升（近黑输出显著高于 v3a）；v3b 中调对比提升（同参数置零 midComp 隔离）
    const nearBlack = (r) => ramp.evaluateTexel(ramp.paramsAt(r, 9), 0.06, 0.06, 0.06)[0];
    assert.ok(nearBlack(v3c) > nearBlack(v3a) + 0.003, 'v3c 热霾黑位应明显高于 v3a');
    const p9b = ramp.paramsAt(v3b, 9);
    assert.ok(p9b.midComp < 0, 'v3b L9 midComp 应为负（中调微对比提升）');
    const p9bFlat = Object.assign({}, p9b, { midComp: 0 });
    const darkMidOn = ramp.evaluateTexel(p9b, 0.40, 0.40, 0.40)[0];
    const darkMidOff = ramp.evaluateTexel(p9bFlat, 0.40, 0.40, 0.40)[0];
    const brightMidOn = ramp.evaluateTexel(p9b, 0.55, 0.55, 0.55)[0];
    const brightMidOff = ramp.evaluateTexel(p9bFlat, 0.55, 0.55, 0.55)[0];
    assert.ok(darkMidOn < darkMidOff && brightMidOn > brightMidOff,
        'v3b 负 midComp 应使中调离轴外推（暗侧更暗、亮侧更亮=对比提升）');
    // v3a 轻过曝脱色介于二者之间：高光脱色量 v3b(0.25) < v3a(0.55) < v3c(0.65)
    assert.ok(l9[0].hiDesat > l9[1].hiDesat && l9[0].hiDesat < l9[2].hiDesat, 'v3a 脱色居中');
});

test('CLI bake-ramp 青橙 v3 端到端：三形态产出 + 7 锚点记录 + L1 刚需线行 + 确定性', () => {
    withTempDirectory((dir) => {
        const kinds = ['cinematic-dusk-peak-v3a', 'cinematic-dusk-peak-v3b', 'cinematic-dusk-peak-v3c'];
        for (const kind of kinds) {
            const first = run(['bake-ramp', '--kind', kind, '--out', dir]);
            assert.equal(first.status, 0, first.stderr);
            assert.ok(/L7 identity：PASS/.test(first.stdout), `${kind} 应打印 L7 identity PASS`);
            assert.ok(/单调性：PASS/.test(first.stdout), `${kind} 应打印单调性 PASS`);
            assert.ok(/L0 顶灰 luma=0\.1\d\d（刚需线 ≤ 0\.15）：PASS/.test(first.stdout),
                `${kind} 应打印 L0 收紧刚需线 PASS`);
            assert.ok(/L1 顶灰 luma=0\.2\d\d（刚需线 ≤ 0\.22）：PASS/.test(first.stdout),
                `${kind} 应打印 L1 收紧刚需线 PASS`);
            assert.ok(/暖色保护：PASS/.test(first.stdout), `${kind} 应打印暖色保护 PASS`);
            const setDir = path.join(dir, kind);
            for (let i = 0; i <= 9; i++) {
                assert.ok(fs.existsSync(path.join(setDir, `光照-${i}.cube`)), `${kind} 光照-${i}.cube 应存在`);
            }
            const preset = JSON.parse(fs.readFileSync(path.join(setDir, 'preset.json'), 'utf8'));
            assert.equal(preset.anchorLevels.length, 7, `${kind} 应为 7 锚点结构`);
            assert.ok(preset.structure.includes('7 锚点结构'), `${kind} structure 应如实记录 7 锚点`);
            assert.ok(preset.calibrationNote.includes('结构差异'), `${kind} 应注明与 v1/v2 系的结构差异`);
            const sha1 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(first.stdout)[1];
            const second = run(['bake-ramp', '--kind', kind, '--out', dir]);
            assert.equal(second.status, 0, second.stderr);
            const sha2 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(second.stdout)[1];
            assert.equal(sha1, sha2, `${kind} 重跑 SHA-256 应一致`);
        }
        const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.sets.json'), 'utf8'));
        assert.equal(manifest.length, 3, '三形态应各占一条 manifest');
        assert.deepEqual(manifest.map((entry) => entry.name).sort(), [...kinds].sort());
    });
});

test('v4 硬光黄昏：暖峰@L4 结构、L4 冷暖对撞修正、硬光化字段、夜段沿用 v3', () => {
    const v3a = ramp.RECIPES['cinematic-dusk-peak-v3a'];
    const v3b = ramp.RECIPES['cinematic-dusk-peak-v3b'];
    const v4 = ramp.RECIPES['hardlight-dusk-v4'];
    assert.ok(v4, 'v4 配方应存在');
    assert.deepEqual(v4.anchorLevels, [0, 1, 4, 5, 6, 7, 9], 'v4 应为 7 锚点（L6 显式近零锚沿用 v3 裁决）');
    // 暖峰在 L4：L4(0.30) > L5(0.12，=L4×0.4 落在 1/3–1/2 区间) > L6≈0；逐档 paramsAt 同序
    assert.ok(v4.anchors[2].splitHigh.strength > v4.anchors[3].splitHigh.strength, '暖峰 L4 > L5');
    assert.ok(v4.anchors[3].splitHigh.strength >= v4.anchors[2].splitHigh.strength / 3
        && v4.anchors[3].splitHigh.strength <= v4.anchors[2].splitHigh.strength / 2,
        'L5 过渡暖应在 L4 的 1/3–1/2');
    assert.ok(v4.anchors[4].splitHigh.strength <= 0.001 && v4.anchors[4].splitShadow.strength <= 0.001,
        'L6 split 应近零');
    assert.equal(v4.anchors[2].splitHigh.hue, 30, 'L4 橙峰保持 30° 暖橙');
    const curve = [0, 1, 2, 3, 4, 5, 6, 7].map((l) => ramp.paramsAt(v4, l).splitHigh.strength);
    assert.ok(curve[4] > curve[3] && curve[3] > curve[5] && curve[5] > curve[6],
        `逐档暖峰应集中 L4 区间（实测 ${curve.map((v) => v.toFixed(2)).join('/')}）`);
    // L4 冷暖对撞修正：暗部青 ≤0.08 且偏中性冷（200–210°）；silverHigh 切除；tempK 暖侧补偿
    assert.ok(v4.anchors[2].splitShadow.strength <= 0.08, 'L4 暗部冷强度应 ≤0.08');
    assert.ok(v4.anchors[2].splitShadow.hue >= 200 && v4.anchors[2].splitShadow.hue <= 210,
        'L4 暗部冷应偏中性（200–210°）');
    assert.equal(v4.anchors[2].silverHigh.strength, 0, 'L4 silverHigh 高光冷应切除（与暖峰同区对撞）');
    assert.ok(v4.anchors[2].tempK > 0, 'L4 tempK 应暖侧加大（补偿阴影冷感缺失）');
    // 硬光全族化：L4–L9 midComp 负值微调（L7 恒等除外），白天段 sat ≥ −2，L9 == v3b 原样
    for (const i of [2, 3, 4, 6]) {
        assert.ok(v4.anchors[i].midComp < 0, `锚点${i} midComp 应为负（中调微对比）`);
    }
    assert.ok(v4.anchors[2].midComp >= -0.02, '黄昏档 midComp 最轻（防把暖峰推脏）');
    assert.ok(v4.anchors[4].satPct >= -2 && v4.anchors[6].satPct >= -2, '白天段 sat 降幅克制 ≥−2');
    assert.deepEqual(v4.anchors[6], v3b.anchors[6], 'L9 应为 v3b 参数原样');
    // 夜段沿用 v3：L0/L1 与 v3a 逐参数一致（刚需线载体 midComp 不动、冷银蓝、暖豁免）
    assert.deepEqual(v4.anchors[0], v3a.anchors[0], 'v4 L0 应与 v3 逐参数一致');
    assert.deepEqual(v4.anchors[1], v3a.anchors[1], 'v4 L1 应与 v3 逐参数一致');
    // 自检：L7 恒等、单调性（许可内）、刚需线、暖豁免
    assert.deepEqual(ramp.checkIdentityRoundTrip(v4), [], 'v4 L7 应逐字节恒等');
    for (const steps of [8, 16]) {
        const m = ramp.checkMonotonic(
            ramp.grayscaleLumaTable(v4, steps), undefined, v4.fadeAllowance, { maxSag: 0.001 });
        assert.deepEqual(m.failures, [], `v4 灰阶 ${steps} 级许可外无反相`);
    }
    const t16 = ramp.grayscaleLumaTable(v4, 16);
    assert.ok(t16[0][15] <= 0.15 && t16[1][15] <= 0.22, 'v4 L0/L1 顶灰过收紧刚需线');
    const probeL1 = ramp.warmProtectionProbe(v4, 1);
    assert.ok(probeL1[0].retention >= probeL1[1].retention + 0.05, 'v4 夜档暖火保留显著高于蓝');
    // 黄昏观感 sanity：L4 暖橙 texel 被强化推橙，且暗部青 texel 响应远弱于 v3（冷让路）
    const warm = (r) => ramp.evaluateTexel(ramp.paramsAt(r, 4), 0.9, 0.55, 0.25);
    const [, g4v3, b4v3] = warm(v3a); const [, g4v4, b4v4] = warm(v4);
    assert.ok(b4v4 < b4v3, 'v4 黄昏暖橙的蓝通道应比 v3 压得更低（橙峰 L4 0.30 > v3 L4 0.26）');
    const dark = (r) => ramp.evaluateTexel(ramp.paramsAt(r, 4), 0.10, 0.10, 0.12);
    const d3 = dark(v3a); const d4 = dark(v4);
    const coolness = (o) => o[2] - o[0];
    assert.ok(coolness(d4) < coolness(d3), 'v4 黄昏暗部冷染色应弱于 v3（暗部青让路）');
});

test('CLI bake-ramp v4 端到端：产出 + 7 锚点记录 + 黄昏=L4 假设来源注明 + 确定性', () => {
    withTempDirectory((dir) => {
        const first = run(['bake-ramp', '--kind', 'hardlight-dusk-v4', '--out', dir]);
        assert.equal(first.status, 0, first.stderr);
        assert.ok(/L7 identity：PASS/.test(first.stdout), '应打印 L7 identity PASS');
        assert.ok(/单调性：PASS/.test(first.stdout), '应打印单调性 PASS');
        assert.ok(/L0 顶灰 luma=0\.1\d\d（刚需线 ≤ 0\.15）：PASS/.test(first.stdout), 'L0 收紧线 PASS');
        assert.ok(/L1 顶灰 luma=0\.2\d\d（刚需线 ≤ 0\.22）：PASS/.test(first.stdout), 'L1 收紧线 PASS');
        assert.ok(/暖色保护：PASS/.test(first.stdout), '暖色保护 PASS');
        const setDir = path.join(dir, 'hardlight-dusk-v4');
        for (let i = 0; i <= 9; i++) {
            assert.ok(fs.existsSync(path.join(setDir, `光照-${i}.cube`)), `光照-${i}.cube 应存在`);
        }
        const preset = JSON.parse(fs.readFileSync(path.join(setDir, 'preset.json'), 'utf8'));
        assert.equal(preset.anchorLevels.length, 7, 'v4 应为 7 锚点结构');
        assert.ok(preset.structure.includes('7 锚点结构'), 'structure 应如实记录 7 锚点');
        assert.ok(preset.calibrationNote.includes('v3→v4 结构差异'), '应记录 v3→v4 全部结构差异');
        assert.ok(preset.calibrationNote.includes('黄昏先假设是光照等级为 4'), '应注明「黄昏=L4」假设来源（维护者指令原文）');
        const sha1 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(first.stdout)[1];
        const second = run(['bake-ramp', '--kind', 'hardlight-dusk-v4', '--out', dir]);
        assert.equal(second.status, 0, second.stderr);
        const sha2 = /确定性 SHA-256（10 档 cube 串联）：([0-9a-f]{64})/.exec(second.stdout)[1];
        assert.equal(sha1, sha2, '重跑 SHA-256 应一致');
        const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.sets.json'), 'utf8'));
        assert.equal(manifest.length, 1);
        assert.equal(manifest[0].name, 'hardlight-dusk-v4');
    });
});

test('pack-set：CF7LUTSET v1 格式、完整性字段、--check 新鲜度', () => {
    withTempDirectory((dir) => {
        // 先烘一个真实集合（v4 全档），再打包
        const bake = run(['bake-ramp', '--kind', 'hardlight-dusk-v4', '--out', dir]);
        assert.equal(bake.status, 0, bake.stderr);
        const setDir = path.join(dir, 'hardlight-dusk-v4');
        const outFile = path.join(dir, 'out', 'hardlight-dusk-v4.lutset');
        const pack = run(['pack-set', '--set', setDir, '--out', outFile]);
        assert.equal(pack.status, 0, pack.stderr);
        assert.ok(/CF7LUTSET v1，1310768 字节/.test(pack.stdout), '应报告 CF7LUTSET v1 与总字节数');
        const buf = fs.readFileSync(outFile);
        assert.equal(buf.length, 48 + 10 * 32 * 32 * 32 * 4, '总长 = 48 头 + 10×32³×4');
        assert.equal(buf.toString('ascii', 0, 4), 'CF7L', 'magic');
        assert.equal(buf.readUInt32LE(4), 1, 'version');
        assert.equal(buf.readUInt32LE(8), 32, 'size');
        assert.equal(buf.readUInt32LE(12), 10, 'levels');
        // 内嵌 SHA-256 == 数据段实际哈希
        const crypto = require('crypto');
        const embedded = buf.subarray(16, 48).toString('hex');
        const actual = crypto.createHash('sha256').update(buf.subarray(48)).digest('hex');
        assert.equal(embedded, actual, '内嵌完整性字段必须等于数据段 SHA-256');
        // L7 恒等档抽查：节点 (r,g,b) → (f(r),f(g),f(b),255)，f 单调、端点 0/255
        const l7 = buf.subarray(48 + 7 * 32 * 32 * 32 * 4, 48 + 8 * 32 * 32 * 32 * 4);
        for (let k = 0; k < 32; k++) {
            assert.equal(l7[k * 4 + 3], 255, 'alpha 恒 255');
            if (k > 0) assert.ok(l7[k * 4] >= l7[(k - 1) * 4], 'L7 对角单调');
        }
        assert.equal(l7[0], 0); assert.equal(l7[(31) * 4], 255);
        for (let b = 0; b < 32; b += 7) for (let g = 0; g < 32; g += 5) for (let r = 0; r < 32; r += 3) {
            const o = (((b * 32 + g) * 32) + r) * 4;
            assert.ok(l7[o] === l7[r * 4] && l7[o + 1] === l7[g * 4] && l7[o + 2] === l7[b * 4],
                `L7 节点(${r},${g},${b}) 应恒等`);
        }
        // 确定性：重打包逐字节一致；--check fresh；篡改产物后 --check stale（非零退出）
        const pack2 = run(['pack-set', '--set', setDir, '--out', outFile + '.2']);
        assert.equal(pack2.status, 0);
        assert.ok(fs.readFileSync(outFile).equals(fs.readFileSync(outFile + '.2')), '重打包应逐字节一致');
        const fresh = run(['pack-set', '--set', setDir, '--out', outFile, '--check']);
        assert.equal(fresh.status, 0, '--check 新鲜应退出 0: ' + fresh.stderr);
        assert.ok(/产物新鲜/.test(fresh.stdout));
        const corrupted = Buffer.from(buf);
        corrupted[48 + 100] ^= 1;
        fs.writeFileSync(outFile + '.stale', corrupted);
        const stale = run(['pack-set', '--set', setDir, '--out', outFile + '.stale', '--check']);
        assert.notEqual(stale.status, 0, '--check 对不符产物必须非零退出');
        // 缺档/缺 preset.json 明确失败
        const broken = path.join(dir, 'broken-set');
        fs.mkdirSync(broken, { recursive: true });
        fs.writeFileSync(path.join(broken, 'preset.json'), '{"mode":"光照"}\n');
        const noLevels = run(['pack-set', '--set', broken, '--out', path.join(dir, 'x.lutset')]);
        assert.notEqual(noLevels.status, 0, '缺档位文件必须失败');
    });
});
