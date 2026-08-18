'use strict';

/**
 * DollBake（launcher/web/modules/doll-bake.js）node vm 运行时测试。
 * 先例：tools/test-merc-portrait-renderer-runtime.js（vm 注入 stub，断言 API 形状）。
 *
 * 覆盖：模块可加载、API 形状、tuple 归一化（10 字段白名单/缺省 ""）、
 * merc 投影（face/hair/gender + 非空装备槽）、dollBake 消息 → doll_bake_result
 * 回传（pngBase64 去前缀、requestId 透传）、空渲染/异常 → error 回传、
 * 非法 key 直接丢弃。
 */

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const modulePath = path.join(projectRoot, 'launcher', 'web', 'modules', 'doll-bake.js');
const moduleSource = fs.readFileSync(modulePath, 'utf8');

function createHarness(options) {
    options = options || {};
    const taskCalls = [];
    const bridgeHandlers = {};
    const loadedScripts = [];
    const errors = [];

    const context = {
        console: {
            error: function(msg) { errors.push(String(msg)); },
            log: function() {}
        },
        Promise,
        Bridge: {
            on: function(type, handler) { bridgeHandlers[type] = handler; },
            task: function(taskName, payload) { taskCalls.push({ taskName, payload }); return 'call_x'; },
            send: function() { return true; }
        },
        LazyLoader: {
            load: function(urls) {
                loadedScripts.push(urls.slice());
                return options.loadFails
                    ? Promise.reject(new Error('load failed'))
                    : Promise.resolve();
            }
        },
        MercPortraits: options.noRenderer ? undefined : {
            renderDataUrl: function(merc, renderOptions) {
                if (options.captureRender) options.captureRender(merc, renderOptions);
                return Promise.resolve(options.dataUrl === undefined
                    ? 'data:image/png;base64,QUJDREVGRw=='
                    : options.dataUrl);
            }
        },
        window: {}
    };
    context.globalThis = context;
    vm.runInNewContext(moduleSource, context, { filename: modulePath });
    return {
        api: context.window.DollBake || context.DollBake,
        taskCalls,
        bridgeHandlers,
        loadedScripts,
        errors
    };
}

const VALID_MESSAGE = {
    requestId: 'doll_1_abc',
    key: '纸娃娃-8a44ae89',
    tuple: {
        face: '女变装-基本脸型', hair: '发型-女式-玫红色马尾', mask: '',
        head: '', body: '佣兵-战术背心', leg: '', hand: '', foot: '',
        neck: '', gender: '女'
    }
};

// vm realm 的 Array/Object 与宿主原型不同，deepStrictEqual 会误报；JSON 归一化后再比
function norm(value) {
    return JSON.parse(JSON.stringify(value));
}

async function main() {
    // 1. 模块可加载 + API 形状 + Bridge.on('dollBake') 注册
    {
        const h = createHarness();
        assert.ok(h.api, 'DollBake api exported');
        assert.strictEqual(typeof h.api.handleMessage, 'function');
        assert.strictEqual(typeof h.api.mercFromTuple, 'function');
        assert.strictEqual(typeof h.api.normalizeTuple, 'function');
        assert.ok(Array.isArray(h.api.SCRIPTS));
        assert.strictEqual(typeof h.bridgeHandlers['dollBake'], 'function',
            'dollBake bridge handler registered');
    }

    // 2. SCRIPTS 注入顺序（renderer → merc-data → portrait 归一化层）
    {
        const h = createHarness();
        assert.deepStrictEqual(norm(h.api.SCRIPTS), [
            'modules/dressup-doll-renderer.js',
            'modules/merc-data.js',
            'modules/merc-portrait-renderer.js'
        ]);
    }

    // 3. normalizeTuple：10 字段白名单、缺省 ""、值字符串化
    {
        const h = createHarness();
        const t = h.api.normalizeTuple({ face: 'f', gender: '女', extra: 'ignored' });
        assert.deepStrictEqual(Object.keys(t), [
            'face', 'hair', 'mask', 'head', 'body', 'leg', 'hand', 'foot', 'neck', 'gender'
        ]);
        assert.strictEqual(t.face, 'f');
        assert.strictEqual(t.hair, '');
        assert.strictEqual(t.gender, '女');
        assert.ok(!('extra' in t));
        const coerced = h.api.normalizeTuple({ face: 42, hair: null });
        assert.strictEqual(coerced.face, '42');
        assert.strictEqual(coerced.hair, '');
    }

    // 4. mercFromTuple：face/hair/gender 透传 + 非空装备槽投影
    {
        const h = createHarness();
        const merc = h.api.mercFromTuple(VALID_MESSAGE.tuple);
        assert.strictEqual(merc.face, '女变装-基本脸型');
        assert.strictEqual(merc.hair, '发型-女式-玫红色马尾');
        assert.strictEqual(merc.gender, '女');
        assert.deepStrictEqual(norm(merc.equipment), { body: '佣兵-战术背心' });
        const full = h.api.mercFromTuple({
            head: 'h1', body: 'b1', hand: 'ha1', leg: 'l1', foot: 'f1', neck: 'n1', mask: 'm1'
        });
        assert.deepStrictEqual(norm(full.equipment), {
            head: 'h1', body: 'b1', hand: 'ha1', leg: 'l1', foot: 'f1', neck: 'n1'
        });
    }

    // 5. happy path：dollBake → LazyLoader 注入 → renderDataUrl → doll_bake_result
    {
        let rendered = null;
        const h = createHarness({ captureRender: function(merc, opts) { rendered = { merc, opts }; } });
        const ok = await h.api.handleMessage(VALID_MESSAGE);
        assert.strictEqual(ok, true);
        assert.deepStrictEqual(norm(h.loadedScripts), norm([h.api.SCRIPTS]));
        assert.ok(rendered, 'renderDataUrl invoked');
        assert.strictEqual(rendered.opts.size, 256);
        assert.strictEqual(rendered.merc.gender, '女');
        assert.strictEqual(h.taskCalls.length, 1);
        const call = h.taskCalls[0];
        assert.strictEqual(call.taskName, 'doll_bake_result');
        assert.strictEqual(call.payload.key, '纸娃娃-8a44ae89');
        assert.strictEqual(call.payload.requestId, 'doll_1_abc');
        assert.strictEqual(call.payload.pngBase64, 'QUJDREVGRw=='); // 已去 dataURL 前缀
        assert.ok(!('error' in call.payload));
    }

    // 6. 空渲染（''）→ error 回传，不抛
    {
        const h = createHarness({ dataUrl: '' });
        const ok = await h.api.handleMessage(VALID_MESSAGE);
        assert.strictEqual(ok, false);
        assert.strictEqual(h.taskCalls.length, 1);
        const call = h.taskCalls[0];
        assert.strictEqual(call.taskName, 'doll_bake_result');
        assert.strictEqual(call.payload.key, '纸娃娃-8a44ae89');
        assert.ok(typeof call.payload.error === 'string' && call.payload.error.length > 0);
        assert.ok(!('pngBase64' in call.payload));
        assert.strictEqual(h.errors.length, 1);
    }

    // 7. renderer 加载失败 → error 回传
    {
        const h = createHarness({ loadFails: true });
        const ok = await h.api.handleMessage(VALID_MESSAGE);
        assert.strictEqual(ok, false);
        assert.strictEqual(h.taskCalls.length, 1);
        assert.ok(h.taskCalls[0].payload.error.indexOf('load failed') >= 0);
    }

    // 8. 非法 key / 非 dollBake 形状 → 丢弃，无任何回传
    {
        const h = createHarness();
        assert.strictEqual(await h.api.handleMessage({ key: '斗士-26' }), false);
        assert.strictEqual(await h.api.handleMessage({}), false);
        assert.strictEqual(await h.api.handleMessage(null), false);
        assert.strictEqual(h.taskCalls.length, 0);
        assert.strictEqual(h.loadedScripts.length, 0);
    }

    console.log('test-doll-bake: all 8 cases passed');
}

main().catch(function(error) {
    console.error(error);
    process.exit(1);
});
