'use strict';

const assert = require('node:assert/strict');
const childProcess = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const test = require('node:test');
const { inspectFont } = require('../lib/font-metadata');
const { loadCatalog, validateCatalog } = require('../lib/catalog');
const { generateCatalog } = require('../lib/generator');
const { syncAssets, validateDownloadUrl } = require('../lib/sync');

const root = path.resolve(__dirname, '../../..');
const cli = path.join(root, 'tools/fontctl/cli.js');
const schema = path.join(root, 'fonts/fonts.xsd');
const catalog = path.join(root, 'fonts/fonts.xml');
const validFixture = path.join(root, 'tools/fontctl/tests/fixtures/valid/fonts.xml');
const sampleWoff2 = fs.readFileSync(path.join(root, 'fonts/permanent/runtime/jetbrains-mono.woff2'));

function run(argumentsList, options = {}) {
    const result = childProcess.spawnSync(
        process.execPath,
        [cli, ...argumentsList, '--json'],
        {
            cwd: options.cwd || root,
            encoding: 'utf8',
            maxBuffer: 64 * 1024 * 1024,
        },
    );
    assert.equal(result.signal, null, result.stderr);
    assert.ok(result.stdout.trim(), `fontctl 未输出 JSON：${result.stderr}`);
    return { status: result.status, json: JSON.parse(result.stdout), stderr: result.stderr };
}

function fixture(name) {
    return path.join(root, 'tools/fontctl/tests/fixtures', name, 'fonts.xml');
}

function withTempDirectory(callback) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-fontctl-'));
    try {
        return callback(directory);
    } finally {
        fs.rmSync(directory, { recursive: true, force: true });
    }
}

async function withTempDirectoryAsync(callback) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-fontctl-'));
    try {
        return await callback(directory);
    } finally {
        fs.rmSync(directory, { recursive: true, force: true });
    }
}

function sha256(value) {
    return crypto.createHash('sha256').update(value).digest('hex');
}

function utf16Be(value) {
    const littleEndian = Buffer.from(value, 'utf16le');
    const bigEndian = Buffer.alloc(littleEndian.length);
    for (let index = 0; index < littleEndian.length; index += 2) {
        bigEndian[index] = littleEndian[index + 1];
        bigEndian[index + 1] = littleEndian[index];
    }
    return bigEndian;
}

function syntheticTtf() {
    const family = utf16Be('Alpha');
    const subfamily = utf16Be('Regular');
    const name = Buffer.alloc(30 + family.length + subfamily.length);
    name.writeUInt16BE(0, 0);
    name.writeUInt16BE(2, 2);
    name.writeUInt16BE(30, 4);
    for (const [recordIndex, nameId, value, valueOffset] of [
        [0, 1, family, 0],
        [1, 2, subfamily, family.length],
    ]) {
        const offset = 6 + recordIndex * 12;
        name.writeUInt16BE(3, offset);
        name.writeUInt16BE(1, offset + 2);
        name.writeUInt16BE(0x0409, offset + 4);
        name.writeUInt16BE(nameId, offset + 6);
        name.writeUInt16BE(value.length, offset + 8);
        name.writeUInt16BE(valueOffset, offset + 10);
        value.copy(name, 30 + valueOffset);
    }
    const os2 = Buffer.alloc(64);
    os2.writeUInt16BE(400, 4);
    os2.writeUInt16BE(5, 6);
    const cmap = Buffer.alloc(40);
    cmap.writeUInt16BE(0, 0);
    cmap.writeUInt16BE(1, 2);
    cmap.writeUInt16BE(3, 4);
    cmap.writeUInt16BE(10, 6);
    cmap.writeUInt32BE(12, 8);
    cmap.writeUInt16BE(12, 12);
    cmap.writeUInt16BE(0, 14);
    cmap.writeUInt32BE(28, 16);
    cmap.writeUInt32BE(0, 20);
    cmap.writeUInt32BE(1, 24);
    cmap.writeUInt32BE(65, 28);
    cmap.writeUInt32BE(66, 32);
    cmap.writeUInt32BE(1, 36);
    const tables = [['name', name], ['OS/2', os2], ['cmap', cmap]];
    const directoryLength = 12 + tables.length * 16;
    let dataOffset = directoryLength;
    const records = tables.map(([tag, value]) => {
        const record = { tag, value, offset: dataOffset };
        dataOffset += value.length;
        dataOffset = (dataOffset + 3) & ~3;
        return record;
    });
    const font = Buffer.alloc(dataOffset);
    font.writeUInt32BE(0x00010000, 0);
    font.writeUInt16BE(tables.length, 4);
    records.forEach((record, index) => {
        const offset = 12 + index * 16;
        font.write(record.tag, offset, 4, 'ascii');
        font.writeUInt32BE(0, offset + 4);
        font.writeUInt32BE(record.offset, offset + 8);
        font.writeUInt32BE(record.value.length, offset + 12);
        record.value.copy(font, record.offset);
    });
    return font;
}

function twoFaceCatalog(alphaContent, betaContent, includePreset = false) {
    return `<?xml version="1.0" encoding="UTF-8"?>
<fontCatalog version="1" gate="A" runtimeAuthority="false">
  <downloadPolicy><allowedHost name="example.invalid"/></downloadPolicy>
  <exclusions><path glob="scripts/**" reason="test"/><path glob="flashswf/**" reason="test"/><path glob="闪7重置版字体/**" reason="test"/></exclusions>
  <fonts>
    <font id="alpha" label="甲" file="alpha.woff2" format="woff2" targets="web" license="OFL-1.1" group="test" residency="on-demand" shippedFallback="false"><face id="alpha-400" family="Alpha" weight="400" style="normal" stretch="normal" classification="migrate"/><download priority="1" url="https://example.invalid/alpha.woff2" bytes="${Buffer.byteLength(alphaContent)}" sha256="${sha256(alphaContent)}"/></font>
    <font id="beta" label="乙" file="beta.woff2" format="woff2" targets="web" license="OFL-1.1" group="test" residency="on-demand" shippedFallback="false"><face id="beta-400" family="Beta" weight="400" style="normal" stretch="normal" classification="migrate"/><download priority="1" url="https://example.invalid/beta.woff2" bytes="${Buffer.byteLength(betaContent)}" sha256="${sha256(betaContent)}"/></font>
  </fonts>
  <roles><role id="web.test.body" label="测试" status="pilot_pending" allowPresetOverride="true"><use face="alpha-400"/><use face="beta-400"/><genericFallback family="serif" classification="system-owned"/></role></roles>
  <presets>${includePreset ? '<preset id="test.beta" label="乙预设" status="pilot_pending"><bind role="web.test.body" face="beta-400"/></preset>' : ''}</presets>
  <rawFamilies><family name="Alpha" classification="migrate"/><family name="Beta" classification="migrate"/><family name="serif" classification="system-owned"/><family name="PlayerInfoPathGlyphAtlas" classification="path-glyph"/></rawFamilies>
</fontCatalog>`;
}

test('零依赖 sfnt metadata 解析 family、weight、stretch 与 cmap', () => {
    const metadata = inspectFont('alpha.ttf', syntheticTtf());
    assert.equal(metadata.metadataStatus, 'parsed');
    assert.deepEqual(metadata.families, ['Alpha']);
    assert.deepEqual(metadata.subfamilies, ['Regular']);
    assert.equal(metadata.weight, 400);
    assert.equal(metadata.stretch, 'normal');
    assert.equal(metadata.cmap.codePointCount, 2);
    assert.equal(metadata.cmap.firstCodePoint, 65);
    assert.equal(metadata.cmap.lastCodePoint, 66);
});

test('valid fixture 同时通过 XSD 与语义校验，输出确定', () => {
    const first = run(['validate', '--catalog', validFixture]);
    const second = run(['validate', '--catalog', validFixture]);
    assert.equal(first.status, 0);
    assert.deepEqual(first.json, second.json);
    assert.equal(first.json.data.assetCount, 1);
});

for (const [name, code] of [
    ['broken-reference', 'BROKEN_FACE_REF'],
    ['duplicate', 'DUPLICATE_ID'],
    ['illegal-name', 'ILLEGAL_ID'],
    ['unknown-role', 'UNKNOWN_ROLE'],
]) {
    test(`${name} fixture 以稳定语义码失败`, () => {
        const result = run(['validate', '--catalog', fixture(name)]);
        assert.equal(result.status, 2);
        assert.ok(result.json.errors.some((item) => item.code === code));
    });
}

test('malformed XML 失败关闭并返回行列', () => withTempDirectory((directory) => {
    const file = path.join(directory, 'fonts.xml');
    fs.writeFileSync(file, '<fontCatalog><fonts></fontCatalog>', 'utf8');
    const result = run(['validate', '--catalog', file]);
    assert.equal(result.status, 2);
    assert.equal(result.json.errors[0].code, 'XML_CLOSE_MISMATCH');
    assert.ok(result.json.errors[0].line > 0);
}));

test('XSD 不允许省略 face stretch', () => withTempDirectory((directory) => {
    const file = path.join(directory, 'fonts.xml');
    const source = fs.readFileSync(validFixture, 'utf8').replace(' stretch="normal"', '');
    fs.writeFileSync(file, source, 'utf8');
    const result = run(['validate', '--catalog', file]);
    assert.equal(result.status, 2);
    assert.ok(result.json.errors.some((item) => item.code === 'XSD_INVALID'));
}));

test('下载主机必须进入 XML 白名单', () => withTempDirectory((directory) => {
    const file = path.join(directory, 'fonts.xml');
    const source = fs.readFileSync(validFixture, 'utf8').replace('https://example.invalid/', 'https://evil.invalid/');
    fs.writeFileSync(file, source, 'utf8');
    const result = run(['validate', '--catalog', file]);
    assert.equal(result.status, 2);
    assert.ok(result.json.errors.some((item) => item.code === 'HOST_NOT_ALLOWED'));
}));

test('role fallback cycle 被确定性拒绝', () => withTempDirectory((directory) => {
    const file = path.join(directory, 'fonts.xml');
    const source = fs.readFileSync(validFixture, 'utf8').replace(
        '<use face="alpha-400"/>',
        '<use face="alpha-400"/><roleFallback role="web.test.body"/>',
    );
    fs.writeFileSync(file, source, 'utf8');
    const result = run(['validate', '--catalog', file]);
    assert.equal(result.status, 2);
    assert.ok(result.json.errors.some((item) => item.code === 'ROLE_FALLBACK_CYCLE'));
}));

test('preset 不能覆盖未授权 role', () => withTempDirectory((directory) => {
    const file = path.join(directory, 'fonts.xml');
    const source = fs.readFileSync(validFixture, 'utf8').replace('allowPresetOverride="true"', 'allowPresetOverride="false"');
    fs.writeFileSync(file, source, 'utf8');
    const result = run(['validate', '--catalog', file]);
    assert.equal(result.status, 2);
    assert.ok(result.json.errors.some((item) => item.code === 'PRESET_OVERRIDE_FORBIDDEN'));
}));

test('未知参数使用独立 usage 退出码 64', () => {
    const result = run(['validate', '--unknown']);
    assert.equal(result.status, 64);
    assert.equal(result.json.errors[0].code, 'USAGE');
});

test('resolver 按来源优先，而不是按 face 优先', () => withTempDirectory((directory) => {
    const alpha = sampleWoff2;
    const beta = sampleWoff2;
    const catalogFile = path.join(directory, 'catalog.xml');
    const fontRoot = path.join(directory, 'font-root');
    fs.mkdirSync(path.join(fontRoot, 'temporary', 'custom'), { recursive: true });
    fs.mkdirSync(path.join(fontRoot, 'permanent', 'runtime'), { recursive: true });
    fs.writeFileSync(path.join(fontRoot, 'temporary', 'custom', 'beta.woff2'), beta);
    fs.writeFileSync(path.join(fontRoot, 'permanent', 'runtime', 'alpha.woff2'), alpha);
    fs.writeFileSync(catalogFile, twoFaceCatalog(alpha, beta));
    const result = run(['resolve', '--catalog', catalogFile, '--schema', schema, '--font-root', fontRoot, '--role', 'web.test.body']);
    assert.equal(result.status, 0);
    assert.equal(result.json.data.selected.source, 'temporary/custom');
    assert.equal(result.json.data.selected.face, 'beta-400');
    assert.deepEqual(result.json.data.candidates.slice(0, 2).map((item) => item.face), ['alpha-400', 'beta-400']);
}));

test('preset override 在同一来源内先于 role 默认 face', () => withTempDirectory((directory) => {
    const alpha = sampleWoff2;
    const beta = sampleWoff2;
    const catalogFile = path.join(directory, 'catalog.xml');
    const fontRoot = path.join(directory, 'font-root');
    fs.mkdirSync(path.join(fontRoot, 'temporary', 'custom'), { recursive: true });
    fs.writeFileSync(path.join(fontRoot, 'temporary', 'custom', 'alpha.woff2'), alpha);
    fs.writeFileSync(path.join(fontRoot, 'temporary', 'custom', 'beta.woff2'), beta);
    fs.writeFileSync(catalogFile, twoFaceCatalog(alpha, beta, true));
    const result = run(['resolve', '--catalog', catalogFile, '--schema', schema, '--font-root', fontRoot, '--role', 'web.test.body', '--preset', 'test.beta']);
    assert.equal(result.status, 0);
    assert.equal(result.json.data.selected.face, 'beta-400');
    assert.equal(result.json.data.selected.reason, 'preset-override');
}));

test('无 remote 的 custom asset 可用，但 permanent 必须声明 integrity', () => withTempDirectory((directory) => {
    const font = syntheticTtf();
    const baseSource = fs.readFileSync(validFixture, 'utf8').replace(/\s*<download\b[^>]*\/>/, '');
    const catalogWithoutIntegrity = path.join(directory, 'custom-only.xml');
    fs.writeFileSync(catalogWithoutIntegrity, baseSource);

    const customRoot = path.join(directory, 'custom-root');
    fs.mkdirSync(path.join(customRoot, 'temporary', 'custom'), { recursive: true });
    fs.writeFileSync(path.join(customRoot, 'temporary', 'custom', 'alpha.ttf'), font);
    const custom = run(['resolve', '--catalog', catalogWithoutIntegrity, '--schema', schema, '--font-root', customRoot, '--role', 'web.test.body']);
    assert.equal(custom.status, 0);
    assert.equal(custom.json.data.selected.source, 'temporary/custom');

    const permanentRoot = path.join(directory, 'permanent-root');
    fs.mkdirSync(path.join(permanentRoot, 'permanent', 'runtime'), { recursive: true });
    fs.writeFileSync(path.join(permanentRoot, 'permanent', 'runtime', 'alpha.ttf'), font);
    const undeclared = run(['resolve', '--catalog', catalogWithoutIntegrity, '--schema', schema, '--font-root', permanentRoot, '--role', 'web.test.body']);
    assert.equal(undeclared.status, 2);
    assert.ok(undeclared.json.errors.some((item) => item.code === 'LOCAL_FONT_INTEGRITY_UNDECLARED'));
    assert.equal(undeclared.json.data.selected.source, 'system-fallback');

    const integrity = `<integrity bytes="${font.length}" sha256="${sha256(font)}"/>`;
    const catalogWithIntegrity = path.join(directory, 'permanent.xml');
    fs.writeFileSync(catalogWithIntegrity, baseSource.replace('<face id="alpha-400"', `${integrity}<face id="alpha-400"`));
    const permanent = run(['resolve', '--catalog', catalogWithIntegrity, '--schema', schema, '--font-root', permanentRoot, '--role', 'web.test.body']);
    assert.equal(permanent.status, 0);
    assert.equal(permanent.json.data.selected.source, 'permanent/runtime');
    assert.equal(permanent.json.data.selected.integrity, 'verified');
}));

test('scan 只读扫描传入 font root，并报告未登记字体', () => withTempDirectory((directory) => {
    const fontRoot = path.join(directory, 'fonts');
    fs.mkdirSync(path.join(fontRoot, 'temporary', 'custom'), { recursive: true });
    fs.writeFileSync(path.join(fontRoot, 'temporary', 'custom', 'jetbrains-mono.woff2'), sampleWoff2);
    fs.writeFileSync(path.join(fontRoot, 'temporary', 'custom', 'extra.woff2'), sampleWoff2);
    const result = run(['scan', '--catalog', catalog, '--font-root', fontRoot]);
    assert.equal(result.status, 0);
    assert.deepEqual(result.json.data.files.map((item) => item.file), ['extra.woff2', 'jetbrains-mono.woff2']);
    assert.ok(result.json.data.files.every((item) => item.validFont));
    assert.ok(result.json.warnings.some((item) => item.code === 'UNDECLARED_LOCAL_FONT'));
}));

test('损坏 custom candidate 被隔离，resolve 仍解释 system fallback', () => withTempDirectory((directory) => {
    const catalogFile = path.join(directory, 'catalog.xml');
    const fontRoot = path.join(directory, 'font-root');
    fs.mkdirSync(path.join(fontRoot, 'temporary', 'custom'), { recursive: true });
    fs.writeFileSync(path.join(fontRoot, 'temporary', 'custom', 'alpha.woff2'), 'not-a-font');
    fs.writeFileSync(catalogFile, twoFaceCatalog(sampleWoff2, sampleWoff2));
    const result = run(['resolve', '--catalog', catalogFile, '--schema', schema, '--font-root', fontRoot, '--role', 'web.test.body']);
    assert.equal(result.status, 2);
    assert.ok(result.json.errors.some((item) => item.code === 'FONT_INVALID'));
    assert.equal(result.json.data.candidates[0].validFont, false);
    assert.equal(result.json.data.selected.source, 'generic-fallback');
}));

test('同来源递归目录中的同 basename 确定性拒绝', () => withTempDirectory((directory) => {
    const fontRoot = path.join(directory, 'fonts');
    fs.mkdirSync(path.join(fontRoot, 'temporary', 'custom', 'a'), { recursive: true });
    fs.mkdirSync(path.join(fontRoot, 'temporary', 'custom', 'b'), { recursive: true });
    fs.writeFileSync(path.join(fontRoot, 'temporary', 'custom', 'a', 'extra.woff2'), sampleWoff2);
    fs.writeFileSync(path.join(fontRoot, 'temporary', 'custom', 'b', 'extra.woff2'), sampleWoff2);
    const result = run(['scan', '--catalog', catalog, '--font-root', fontRoot]);
    assert.equal(result.status, 2);
    assert.ok(result.json.errors.some((item) => item.code === 'FONT_BASENAME_COLLISION'));
}));

test('根目录与现役 manifest 完整等价', () => {
    const result = run(['validate']);
    assert.equal(result.status, 0);
    assert.equal(result.json.data.assetCount, 14);
    assert.equal(result.json.data.faceCount, 14);
    assert.equal(result.json.data.roleCount, 28);
    assert.equal(result.json.data.presetCount, 9);
    assert.equal(result.json.data.declaredBytes, 119211978);
    assert.equal(result.json.data.shippedFallbackCount, 1);
    assert.equal(result.json.data.permanentAssetCount, 2);
});

test('59 份情报数据的 skin 与 writerVoice 全部落入语义角色或 preset', () => {
    const directory = path.join(root, 'data', 'intelligence_h5');
    const files = fs.readdirSync(directory).filter((file) => file.endsWith('.json')).sort();
    assert.equal(files.length, 59);
    const loaded = loadCatalog(catalog);
    const validated = validateCatalog(loaded);
    const roles = validated.maps.rolesById;
    const presets = validated.maps.presetsById;
    const skinContracts = {
        blueprint: 'web.intelligence.body',
        diary: 'intelligence.diary',
        dossier: 'web.intelligence.archive',
        edict: 'web.intelligence.body',
        'field-notes': 'web.intelligence.body',
        newspaper: 'web.intelligence.body',
        paper: 'web.intelligence.body',
        report: 'web.intelligence.body',
        terminal: 'web.intelligence.terminal',
    };
    const voiceContracts = {
        neat: 'intelligence.neat',
        rough: 'intelligence.rough',
        plain: 'intelligence.plain',
        weary: 'intelligence.weary',
    };
    const skinCounts = {};
    const voiceCounts = {};
    let corpus = '';
    for (const file of files) {
        const source = fs.readFileSync(path.join(directory, file), 'utf8');
        const item = JSON.parse(source);
        assert.equal(item.schemaVersion, 1, file);
        assert.ok(Array.isArray(item.pages) && item.pages.length > 0, file);
        assert.ok(skinContracts[item.skin], `${file}: unknown skin ${item.skin}`);
        const skinContract = skinContracts[item.skin];
        assert.ok(skinContract.startsWith('web.') ? roles.has(skinContract) : presets.has(skinContract), file);
        skinCounts[item.skin] = (skinCounts[item.skin] || 0) + 1;
        if (item.writerVoice) {
            assert.ok(voiceContracts[item.writerVoice], `${file}: unknown writerVoice ${item.writerVoice}`);
            assert.ok(presets.has(voiceContracts[item.writerVoice]), file);
            voiceCounts[item.writerVoice] = (voiceCounts[item.writerVoice] || 0) + 1;
        }
        corpus += source;
    }
    assert.deepEqual(skinCounts, {
        blueprint: 6, diary: 6, dossier: 10, edict: 5, 'field-notes': 1,
        newspaper: 6, paper: 17, report: 6, terminal: 2,
    });
    assert.deepEqual(voiceCounts, { neat: 1, plain: 1, rough: 1, weary: 1 });
    for (const punctuation of ['“', '”', '——', '……', '《', '》']) assert.ok(corpus.includes(punctuation), punctuation);
});

test('generate 产出确定性 CSS/JS/JSON，并可由 JS 消费 role 与兼容映射', () => withTempDirectory((directory) => {
    const loaded = loadCatalog(catalog);
    const validated = validateCatalog(loaded);
    assert.equal(validated.diagnostics.filter((item) => item.severity === 'error').length, 0);
    const first = generateCatalog(loaded, validated.maps, directory, false);
    assert.equal(first.diagnostics.length, 0);
    assert.equal(first.projection.assets.filter((asset) => asset.residency === 'permanent').length, 2);
    const checked = generateCatalog(loaded, validated.maps, directory, true);
    assert.equal(checked.diagnostics.length, 0);
    const generatedJs = path.join(directory, 'font-catalog.js');
    delete require.cache[require.resolve(generatedJs)];
    const runtime = require(generatedJs);
    assert.match(runtime.role('web.intelligence.title'), /CF7Face--ma-shan-zheng-regular-400/);
    assert.match(runtime.canvasFont('web.overlay.mono', 12, { weight: 700 }), /^normal 700 12px /);
    assert.equal(runtime.legacyFamily('MS Mincho'), '"MS Mincho", serif');
    fs.appendFileSync(path.join(directory, 'font-catalog.css'), '/* drift */\n');
    const drift = generateCatalog(loaded, validated.maps, directory, true);
    assert.ok(drift.diagnostics.some((item) => item.code === 'GENERATED_DRIFT'));
}));

test('sync 只发布通过 bytes/hash/font probe 的唯一 staging，并保留失败前文件', async () => withTempDirectoryAsync(async (directory) => {
    const font = syntheticTtf();
    const source = fs.readFileSync(validFixture, 'utf8')
        .replace('bytes="1"', `bytes="${font.length}"`)
        .replace(/sha256="a{64}"/, `sha256="${sha256(font)}"`);
    const catalogFile = path.join(directory, 'fonts.xml');
    fs.writeFileSync(catalogFile, source);
    const loaded = loadCatalog(catalogFile);
    const cache = path.join(directory, 'root', 'temporary', 'cache');

    const success = await syncAssets(loaded, path.join(directory, 'root'), {}, {
        downloadToFile: async (_url, destination) => fs.writeFileSync(destination, font),
    });
    assert.equal(success.diagnostics.length, 0);
    assert.equal(success.assets[0].status, 'downloaded');
    assert.deepEqual(fs.readFileSync(path.join(cache, 'alpha.ttf')), font);

    fs.writeFileSync(path.join(cache, 'alpha.ttf'), 'previous-invalid-file');
    const failed = await syncAssets(loaded, path.join(directory, 'root'), {}, {
        downloadToFile: async (_url, destination) => fs.writeFileSync(destination, 'bad'),
    });
    assert.ok(failed.diagnostics.some((item) => item.code === 'DOWNLOAD_FAILED'));
    assert.equal(fs.readFileSync(path.join(cache, 'alpha.ttf'), 'utf8'), 'previous-invalid-file');
}));

test('sync 对 requested 与 redirect URL 共用 HTTPS host allowlist', () => {
    const allowed = new Set(['example.invalid']);
    assert.equal(validateDownloadUrl('https://example.invalid/font.ttf', allowed).hostname, 'example.invalid');
    assert.throws(() => validateDownloadUrl('http://example.invalid/font.ttf', allowed), /url_scheme/);
    assert.throws(() => validateDownloadUrl('https://evil.invalid/font.ttf', allowed), /host_not_allowed/);
    assert.throws(() => validateDownloadUrl('https://user@example.invalid/font.ttf', allowed), /url_unsafe/);
});

test('audit-usage 覆盖 C#/Web/runtime data 并保持 Flash 边界', () => {
    const result = run(['audit-usage']);
    assert.equal(result.status, 0);
    assert.ok(result.json.data.usage.some((item) => item.file === 'data/items/武器_刀_刀剑.xml' && item.canonical === 'MS Mincho'));
    assert.ok(result.json.data.usage.some((item) => item.file === 'data/items/武器_刀_重斩.xml' && item.canonical === 'Fixedsys'));
    assert.ok(!result.json.data.usage.some((item) => item.file.endsWith('NativeHudFonts.cs')));
    assert.match(fs.readFileSync(path.join(root, 'launcher/src/Guardian/Hud/NativeHudFonts.cs'), 'utf8'), /native\.hud\.body/);
    assert.ok(result.json.data.usage.some((item) => item.classification === 'path-glyph'));
    assert.ok(result.json.data.excluded.includes('flashswf/**'));
    assert.ok(result.json.data.usage.every((item) => !item.file.startsWith('flashswf/') && !item.file.startsWith('data/unused/')));
    assert.equal(result.json.data.dynamicSites.length, 0);
    assert.ok(result.json.data.catalogBoundDynamicSites.some((item) => item.file.endsWith('tooltip.js')));
});

test('audit-usage 发现未知生产 family，但排除 dev harness', () => withTempDirectory((directory) => {
    const production = path.join(directory, 'launcher', 'web', 'main.css');
    const harness = path.join(directory, 'launcher', 'web', 'module', 'dev', 'harness.css');
    fs.mkdirSync(path.dirname(production), { recursive: true });
    fs.mkdirSync(path.dirname(harness), { recursive: true });
    fs.writeFileSync(production, '.known { font-family: "Rogue Production", sans-serif; }');
    fs.writeFileSync(harness, '.ignored { font-family: "Rogue Harness", sans-serif; }');
    const result = run(['audit-usage', '--project-root', directory, '--catalog', catalog, '--schema', schema]);
    assert.equal(result.status, 2);
    assert.ok(result.json.errors.some((item) => item.family === 'Rogue Production'));
    assert.ok(result.json.errors.every((item) => item.family !== 'Rogue Harness'));
}));
