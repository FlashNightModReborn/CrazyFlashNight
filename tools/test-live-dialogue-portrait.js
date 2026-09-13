'use strict';

/**
 * LiveDialoguePortraits + DressupDollRenderer 显式表情选帧的 node vm 定向测试。
 * 先例：tools/test-doll-bake.js / test-merc-portrait-renderer-runtime.js。
 *
 * 合成 manifest（非生产资产）：两个脸型各带 expressions 元数据
 * （普通/愤怒/微笑 → 不同 uri），验证：
 *   1. 模块加载 + API 形状
 *   2. 两个人物 appearance 归一化互不串味
 *   3. 两种表情画出不同表情帧 uri
 *   4. 缺失表情显式回退 '普通'（fallback:'default'，可观测）
 *   5. 尺寸档 / assetVersion 变更 → identity 隔离
 *   6. 旧默认行为：不传 expression → static-first-frame 首帧、无表情记录
 *   7. renderDataUrl 端到端（stub Image 异步 onload + 轮询）+ dispose
 *   8. resolveExpressionFrame 纯函数回退链
 */

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const MODULES = [
    path.join(projectRoot, 'launcher', 'web', 'modules', 'asset-timeline.js'),
    path.join(projectRoot, 'launcher', 'web', 'modules', 'dressup-doll-renderer.js'),
    path.join(projectRoot, 'launcher', 'web', 'modules', 'dialogue', 'live-portrait.js')
];

const BASE_URL = 'https://test.local/web/';

function frame(uri, n, w, h) {
    return { uri: uri, frame: n, sourceFrame: n, width: w || 40, height: h || 60 };
}

function skinEntry(uri, width, height, extra) {
    const entry = {
        covered: true,
        export: {
            format: 'png', zoom: 1, fps: 24, playback: 'static-first-frame',
            uri: uri, width: width, height: height, frameCount: 1
        },
        frames: [frame(uri, 1, width, height)]
    };
    return Object.assign(entry, extra || {});
}

function makeManifest(generatedAt) {
    return {
        schema: 'cf7-dressup-manifest-v1',
        generatedAt: generatedAt || 'test-v1',
        __baseUrl: BASE_URL + 'assets/dressup/',
        genders: ['男', '女'],
        appearance: {
            faceById: { '0': '女变装-基本脸型', '1': '男变装-基本脸型' },
            hairById: { '3': '发型-男式-黑长发', '22': '发型-女式-银色清爽直发' }
        },
        items: {
            '佣兵护甲': {
                use: '上装',
                fieldsByGender: { '男': { '身体': '身体-佣兵护甲' }, '女': { '身体': '身体-佣兵护甲' } }
            },
            '法师袍': {
                use: '上装',
                fieldsByGender: { '男': { '身体': '身体-法师袍' }, '女': { '身体': '身体-法师袍' } }
            }
        },
        skinKeys: {
            '男变装-基本脸型': skinEntry('d/face_m_1.png', 40, 60, {
                expressions: {
                    '普通': frame('d/face_m_1.png', 1),
                    '愤怒': frame('d/face_m_expr_2.png', 2),
                    '微笑': frame('d/face_m_expr_3.png', 3)
                },
                defaultExpression: '普通',
                expressionSource: { kind: 'xfl-labels', labels: { '普通': 0, '愤怒': 1, '微笑': 2 } }
            }),
            '女变装-基本脸型': skinEntry('d/face_f_1.png', 38, 58, {
                expressions: {
                    '普通': frame('d/face_f_1.png', 1),
                    '大笑': frame('d/face_f_expr_4.png', 4)
                },
                defaultExpression: '普通',
                expressionSource: { kind: 'xfl-labels', labels: { '普通': 0, '大笑': 3 } }
            }),
            '发型-男式-黑长发': skinEntry('d/hair_m3.png', 44, 40),
            '发型-女式-银色清爽直发': skinEntry('d/hair_f22.png', 44, 40),
            '身体-佣兵护甲': skinEntry('d/body_armor.png', 60, 80),
            '身体-法师袍': skinEntry('d/body_robe.png', 60, 80)
        },
        rig: {
            genders: {
                '男': {
                    holders: [
                        { field: '身体', matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 }, fallbackBasic: false, basic: null },
                        { field: '脸型', matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: -40 }, fallbackBasic: false, basic: null },
                        { field: '发型', matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: -50 }, fallbackBasic: false, basic: null }
                    ]
                },
                '女': {
                    holders: [
                        { field: '身体', matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 }, fallbackBasic: false, basic: null },
                        { field: '脸型', matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: -40 }, fallbackBasic: false, basic: null },
                        { field: '发型', matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: -50 }, fallbackBasic: false, basic: null }
                    ]
                }
            }
        },
        rigs: {}
    };
}

// ---------- stub 浏览器环境 ----------

class FakeImage {
    constructor() {
        this.complete = false;
        this.naturalWidth = 0;
        this.naturalHeight = 0;
        this.onload = null;
        this.onerror = null;
    }
    set src(value) {
        this._src = value;
        // 异步完成：首个 tick 会看到 pendingImages>0，之后 onload 内
        // renderer 自发 render(lastState)，轮询 tick 再确认 ready。
        const self = this;
        setTimeout(function() {
            self.complete = true;
            self.naturalWidth = 40;
            self.naturalHeight = 60;
            if (typeof self.onload === 'function') self.onload();
        }, 0);
    }
    get src() { return this._src; }
}

class FakeContext2D {
    constructor(canvas) { this.canvas = canvas; }
    save() {}
    restore() {}
    translate() {}
    scale() {}
    transform() {}
    setTransform() {}
    clearRect() {}
    beginPath() {}
    moveTo() {}
    lineTo() {}
    quadraticCurveTo() {}
    closePath() {}
    fill() {}
    stroke() {}
    fillText() {}
    measureText() { return { width: 0 }; }
    drawImage(image) {
        if (image && image.src) this.canvas.__drawn.push(String(image.src));
    }
    getImageData(x, y, w, h) {
        const data = new Uint8ClampedArray(Math.max(1, w * h * 4));
        for (let i = 3; i < data.length; i += 4) data[i] = 255;
        return { data: data, width: w, height: h };
    }
}

class FakeCanvas {
    constructor() {
        this.width = 0;
        this.height = 0;
        this.clientWidth = 0;
        this.clientHeight = 0;
        this.parentNode = null;
        this.__drawn = [];
        this.__ctx = new FakeContext2D(this);
    }
    getContext() { return this.__ctx; }
    getBoundingClientRect() {
        return { left: 0, top: 0, right: this.width, bottom: this.height,
            width: this.width, height: this.height };
    }
    toDataURL() {
        return 'data:image/png;base64,'
            + Buffer.from(JSON.stringify({
                width: this.width, height: this.height, drawn: this.__drawn
            }), 'utf8').toString('base64');
    }
}

class FakeContainer {
    constructor() { this.children = []; }
    appendChild(node) { node.parentNode = this; this.children.push(node); }
    removeChild(node) {
        const i = this.children.indexOf(node);
        if (i >= 0) this.children.splice(i, 1);
        node.parentNode = null;
    }
}

function decodeDataUrl(dataUrl) {
    const prefix = 'data:image/png;base64,';
    assert.ok(dataUrl.indexOf(prefix) === 0, 'dataURL prefix');
    return JSON.parse(Buffer.from(dataUrl.slice(prefix.length), 'base64').toString('utf8'));
}

function createHarness(manifest) {
    const documentStub = {
        baseURI: BASE_URL,
        createElement: function(tag) {
            assert.strictEqual(tag, 'canvas');
            return new FakeCanvas();
        }
    };
    const context = {
        console: console,
        Promise: Promise,
        URL: URL,
        Image: FakeImage,
        document: documentStub,
        setTimeout: setTimeout,
        clearTimeout: clearTimeout,
        setInterval: setInterval,
        clearInterval: clearInterval,
        window: {
            devicePixelRatio: 1,
            performance: { now: function() { return Date.now(); } },
            requestAnimationFrame: function(fn) { return setTimeout(function() { fn(Date.now()); }, 16); },
            cancelAnimationFrame: function(id) { clearTimeout(id); }
        }
    };
    context.window.document = documentStub;
    context.window.window = context.window;
    context.globalThis = context;
    for (const file of MODULES) {
        vm.runInNewContext(fs.readFileSync(file, 'utf8'), context, { filename: file });
    }
    return {
        context: context,
        api: context.window.LiveDialoguePortraits || context.LiveDialoguePortraits,
        renderer: context.DressupDollRenderer || context.window.DressupDollRenderer,
        manifest: manifest || makeManifest()
    };
}

const APPEARANCE_A = { gender: '男', face: '1', hair: '3', body: '佣兵护甲' };
const APPEARANCE_B = { gender: '女', face: '0', hair: '22', body: '法师袍' };

function norm(value) {
    return JSON.parse(JSON.stringify(value));
}

function wait(ms) {
    return new Promise(function(resolve) { setTimeout(resolve, ms); });
}

async function main() {
    // 1. 模块加载 + API 形状
    {
        const h = createHarness();
        assert.ok(h.api, 'LiveDialoguePortraits exported');
        ['normalizeAppearance', 'buildState', 'identity', 'resolve',
            'render', 'renderDataUrl', 'loadManifest', 'clearCache'].forEach(function(name) {
            assert.strictEqual(typeof h.api[name], 'function', 'api.' + name);
        });
        assert.strictEqual(typeof h.renderer.resolveExpressionFrame, 'function',
            'resolveExpressionFrame exported');
    }

    // 2. 两个人物归一化互不串味（face id → skinKey，装备槽展开）
    {
        const h = createHarness();
        const a = h.api.normalizeAppearance(h.manifest, APPEARANCE_A);
        const b = h.api.normalizeAppearance(h.manifest, APPEARANCE_B);
        assert.strictEqual(a.gender, '男');
        assert.strictEqual(a.fields['脸型'], '男变装-基本脸型');
        assert.strictEqual(a.fields['发型'], '发型-男式-黑长发');
        assert.strictEqual(a.equipment.body, '佣兵护甲');
        assert.strictEqual(b.gender, '女');
        assert.strictEqual(b.fields['脸型'], '女变装-基本脸型');
        assert.strictEqual(b.fields['发型'], '发型-女式-银色清爽直发');
        assert.strictEqual(b.equipment.body, '法师袍');
        const idA = h.api.identity(h.manifest, APPEARANCE_A, { expression: '普通' });
        const idB = h.api.identity(h.manifest, APPEARANCE_B, { expression: '普通' });
        assert.notStrictEqual(idA, idB, '两个人物 identity 不同');
    }

    // 3. 两种表情 → 不同表情帧 uri 入画
    {
        const h = createHarness();
        const angry = await h.api.renderDataUrl(APPEARANCE_A,
            { manifest: h.manifest, size: 768, expression: '愤怒', timeoutMs: 3000, pollMs: 5 });
        const angryDrawn = decodeDataUrl(angry).drawn;
        assert.ok(angryDrawn.some(function(u) { return u.indexOf('face_m_expr_2.png') >= 0; }),
            '愤怒应画 expr_2 帧: ' + angryDrawn.join(','));
        assert.ok(!angryDrawn.some(function(u) { return u.indexOf('face_m_1.png') >= 0; }),
            '愤怒不应画默认首帧');
        const smile = await h.api.renderDataUrl(APPEARANCE_A,
            { manifest: h.manifest, size: 768, expression: '微笑', timeoutMs: 3000, pollMs: 5 });
        const smileDrawn = decodeDataUrl(smile).drawn;
        assert.ok(smileDrawn.some(function(u) { return u.indexOf('face_m_expr_3.png') >= 0; }),
            '微笑应画 expr_3 帧');
        assert.notStrictEqual(angry, smile, '两种表情的像素产出不同');
    }

    // 4. 缺失表情显式回退 '普通'（fallback:'default'）+ 可观测
    {
        const h = createHarness();
        const container = new FakeContainer();
        const handle = h.api.render(container, APPEARANCE_A,
            { manifest: h.manifest, size: 512, expression: '委屈', timeoutMs: 3000, pollMs: 5 });
        const meta = await handle.ready;
        assert.ok(meta, 'mounted render resolves meta');
        const faceRecord = (meta.expressions || []).filter(function(r) {
            return r.field === '脸型';
        })[0];
        assert.ok(faceRecord, '脸型表情记录存在: ' + JSON.stringify(meta.expressions));
        assert.strictEqual(faceRecord.requested, '委屈');
        assert.strictEqual(faceRecord.resolved, '普通');
        assert.strictEqual(faceRecord.fallback, 'default');
        handle.dispose();
        assert.strictEqual(container.children.length, 0, 'dispose 移除 canvas');
    }

    // 4b. 无 expressions 元数据的条目被请求时进 expressionsUnmatched
    {
        const h = createHarness();
        const container = new FakeContainer();
        const handle = h.api.render(container, APPEARANCE_A, {
            manifest: h.manifest, size: 512,
            fieldExpressions: { '发型': '愤怒' },
            timeoutMs: 3000, pollMs: 5
        });
        const meta = await handle.ready;
        const unmatched = (meta.expressionsUnmatched || []).filter(function(r) {
            return r.field === '发型';
        })[0];
        assert.ok(unmatched, '无元数据条目的表情请求可观测');
        assert.strictEqual(unmatched.fallback, 'no-expressions');
        handle.dispose();
    }

    // 5. 尺寸档 / assetVersion → identity 与缓存隔离
    {
        const h = createHarness();
        const idBig = h.api.identity(h.manifest, APPEARANCE_A, { size: 768, expression: '愤怒' });
        const idSmall = h.api.identity(h.manifest, APPEARANCE_A, { size: 256, expression: '愤怒' });
        assert.notStrictEqual(idBig, idSmall, '尺寸档隔离');
        const idV1 = h.api.identity(h.manifest, APPEARANCE_A, { size: 768, expression: '愤怒', assetVersion: 'v1' });
        const idV2 = h.api.identity(h.manifest, APPEARANCE_A, { size: 768, expression: '愤怒', assetVersion: 'v2' });
        assert.notStrictEqual(idV1, idV2, 'assetVersion 隔离');
        const manifestV2 = makeManifest('test-v2');
        const idAuto1 = h.api.identity(h.manifest, APPEARANCE_A, { size: 768, expression: '愤怒' });
        const idAuto2 = h.api.identity(manifestV2, APPEARANCE_A, { size: 768, expression: '愤怒' });
        assert.notStrictEqual(idAuto1, idAuto2, 'manifest generatedAt 版本指纹隔离');
        // 缓存隔离：不同尺寸各画各的，LRU 不串
        const big = decodeDataUrl(await h.api.renderDataUrl(APPEARANCE_A,
            { manifest: h.manifest, size: 768, expression: '愤怒', timeoutMs: 3000, pollMs: 5 }));
        const small = decodeDataUrl(await h.api.renderDataUrl(APPEARANCE_A,
            { manifest: h.manifest, size: 256, expression: '愤怒', timeoutMs: 3000, pollMs: 5 }));
        assert.strictEqual(big.width, 768);
        assert.strictEqual(small.width, 256);
        const again = decodeDataUrl(await h.api.renderDataUrl(APPEARANCE_A,
            { manifest: h.manifest, size: 768, expression: '愤怒', timeoutMs: 3000, pollMs: 5 }));
        assert.strictEqual(again.width, 768, '缓存命中仍返回 768');
    }

    // 6. 旧默认行为：不传 expression → 首帧、无表情记录、不动画
    {
        const h = createHarness();
        const container = new FakeContainer();
        const handle = h.api.render(container, APPEARANCE_A,
            { manifest: h.manifest, size: 512, timeoutMs: 3000, pollMs: 5 });
        const meta = await handle.ready;
        assert.ok(meta, 'default render resolves');
        assert.strictEqual(meta.expressionRequests, 0);
        assert.deepStrictEqual(norm(meta.expressions), []);
        assert.strictEqual(meta.animated, false, '停帧脸型不得被当动画放');
        handle.dispose();
        const dataUrl = await h.api.renderDataUrl(APPEARANCE_A,
            { manifest: h.manifest, size: 768, timeoutMs: 3000, pollMs: 5 });
        const drawn = decodeDataUrl(dataUrl).drawn;
        assert.ok(drawn.some(function(u) { return u.indexOf('face_m_1.png') >= 0; }),
            '无 expression 时画默认首帧');
        assert.ok(!drawn.some(function(u) { return u.indexOf('expr_') >= 0; }),
            '无 expression 时不画表情帧');
    }

    // 7. renderDataUrl dispose → 显式 reject；超时 → 显式 reject 而非空白
    {
        const h = createHarness();
        const pending = h.api.renderDataUrl(APPEARANCE_A,
            { manifest: h.manifest, size: 768, expression: '愤怒',
              createCanvas: function() {
                  const c = new FakeCanvas();
                  c.toDataURL = function() { return ''; };
                  return c;
              },
              timeoutMs: 3000, pollMs: 5 });
        pending.dispose();
        await assert.rejects(pending, /disposed|empty|timeout/, 'dispose 后显式失败');
        // alpha 永不可能达标 → 有界轮询走尽 → 显式 timeout reject（不回空白当成功）
        const timeoutHarness = createHarness();
        const stuck = timeoutHarness.api.renderDataUrl(APPEARANCE_B,
            { manifest: timeoutHarness.manifest, size: 768, expression: '大笑',
              minAlphaPixels: Number.MAX_SAFE_INTEGER, timeoutMs: 120, pollMs: 5 });
        await assert.rejects(stuck, /timeout/, 'alpha 不达标/超时显式 reject');
    }

    // 8. resolveExpressionFrame 纯函数回退链
    {
        const h = createHarness();
        const face = h.manifest.skinKeys['男变装-基本脸型'];
        const hit = h.renderer.resolveExpressionFrame(face, '愤怒');
        assert.strictEqual(hit.resolved, '愤怒');
        assert.strictEqual(hit.fallback, false);
        assert.strictEqual(hit.frame.uri, 'd/face_m_expr_2.png');
        const miss = h.renderer.resolveExpressionFrame(face, '委屈');
        assert.strictEqual(miss.resolved, '普通');
        assert.strictEqual(miss.fallback, 'default');
        const noMeta = h.renderer.resolveExpressionFrame(
            h.manifest.skinKeys['发型-男式-黑长发'], '愤怒');
        assert.strictEqual(noMeta.fallback, 'no-expressions');
        const noDefault = h.renderer.resolveExpressionFrame({
            expressions: { '微笑': frame('d/x.png', 3) }
        }, '愤怒');
        assert.strictEqual(noDefault.resolved, '微笑');
        assert.strictEqual(noDefault.fallback, 'first');
        assert.strictEqual(h.renderer.resolveExpressionFrame(face, ''), null);
        assert.strictEqual(h.renderer.resolveExpressionFrame(face, null), null);
    }

    console.log('test-live-dialogue-portrait: all 8 cases passed');
}

main().catch(function(error) {
    console.error(error);
    process.exit(1);
});
