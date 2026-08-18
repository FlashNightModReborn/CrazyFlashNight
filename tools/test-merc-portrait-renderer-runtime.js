'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const rendererPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'merc-portrait-renderer.js');
const rendererSource = fs.readFileSync(rendererPath, 'utf8');

const manifest = {
    skinKeys: {
        '女变装-基本脸型': { covered: true },
        '男变装-基本脸型': { covered: true },
        '发型-女式-玫红色马尾': { covered: true },
        '发型-女式-深蓝色蕾丝发带马尾': { covered: true }
    },
    appearance: {
        faceById: { '0': '女变装-基本脸型', '1': '男变装-基本脸型' },
        hairById: { '21': '发型-女式-深蓝色蕾丝发带马尾' }
    },
    items: {}
};

function createNode() {
    const attrs = {};
    const classes = {};
    const container = {
        connected: true,
        classList: {
            add: function() { for (let i = 0; i < arguments.length; i++) classes[arguments[i]] = true; },
            remove: function() { for (let i = 0; i < arguments.length; i++) delete classes[arguments[i]]; }
        },
        setAttribute: function(key, value) { attrs[key] = String(value); },
        getAttribute: function(key) { return Object.prototype.hasOwnProperty.call(attrs, key) ? attrs[key] : null; },
        removeAttribute: function(key) { delete attrs[key]; }
    };
    const img = {
        hidden: false,
        src: '',
        removeAttribute: function(key) { if (key === 'src') this.src = ''; }
    };
    return { container, img, attrs, classes };
}

function createHarness(options) {
    options = options || {};
    const timers = [];
    const stats = { creates: 0, destroys: 0, loadManifestCalls: 0, rendererOptions: [] };
    const alpha = new Uint8ClampedArray(200 * 4);
    for (let i = 3; i < alpha.length; i += 4) alpha[i] = 255;

    function setTimer(fn) {
        const timer = { fn, cancelled: false };
        timers.push(timer);
        return timer;
    }

    const DressupDollRenderer = {
        loadManifest: function() {
            stats.loadManifestCalls++;
            return options.loadManifest ? options.loadManifest() : Promise.resolve(manifest);
        },
        buildStateFromEquipment: function(unusedManifest, state) { return state; },
        create: function(canvas, rendererOptions) {
            const index = ++stats.creates;
            stats.rendererOptions.push(Object.assign({}, rendererOptions));
            canvas.width = rendererOptions.width;
            canvas.height = rendererOptions.height;
            canvas._url = options.dataUrl ? options.dataUrl(index) : 'data:image/png;base64,' + String(index).repeat(8);
            const implementation = options.createRenderer
                ? options.createRenderer(index, canvas)
                : { render: function() { return { pendingImages: 0, failedImages: 0 }; } };
            return {
                render: function(state) { return implementation.render(state); },
                destroy: function() {
                    stats.destroys++;
                    if (implementation.destroy) implementation.destroy();
                }
            };
        }
    };

    const document = {
        documentElement: { contains: function(node) { return node && node.connected !== false; } },
        createElement: function() {
            return {
                width: 0,
                height: 0,
                getContext: function() {
                    return { getImageData: function() { return { data: alpha }; } };
                },
                toDataURL: function() { return this._url; }
            };
        }
    };
    const context = {
        console,
        Promise,
        document,
        DressupDollRenderer,
        MercData: { DRESSUP_SLOT_BY_INDEX: { 6: 'head', 12: 'main' } },
        setTimeout: setTimer,
        clearTimeout: function(timer) { if (timer) timer.cancelled = true; },
        window: {
            devicePixelRatio: 1.5,
            CF7_MERC_PORTRAIT_MAX_CONCURRENCY: options.concurrency || 4,
            CF7_MERC_PORTRAIT_CACHE_MAX_ENTRIES: options.cacheEntries || 96,
            CF7_MERC_PORTRAIT_CACHE_MAX_BYTES: options.cacheBytes || (12 * 1024 * 1024)
        }
    };
    context.globalThis = context;
    vm.runInNewContext(rendererSource, context, { filename: rendererPath });

    return {
        api: context.window.MercPortraits,
        stats,
        timers,
        runNextTimer: function() {
            while (timers.length) {
                const timer = timers.shift();
                if (!timer.cancelled) { timer.fn(); return true; }
            }
            return false;
        }
    };
}

async function flushMicrotasks(rounds) {
    for (let i = 0; i < (rounds || 8); i++) await Promise.resolve();
}

function merc(key, overrides) {
    return Object.assign({
        gender: '女',
        face: '女变装-基本脸型',
        hair: '',
        equips: [{ slot: 12, name: 'weapon-' + key }]
    }, overrides || {});
}

(async function() {
    let cases = 0;

    const dpiHarness = createHarness({});
    const dpiResult = await dpiHarness.api.renderDataUrl(merc('dpi-contract'), { size: 256 });
    assert(dpiResult.indexOf('data:image/png;base64,') === 0);
    assert.strictEqual(dpiHarness.stats.rendererOptions.length, 1);
    assert.strictEqual(dpiHarness.stats.rendererOptions[0].width, 256);
    assert.strictEqual(dpiHarness.stats.rendererOptions[0].height, 256);
    assert.strictEqual(dpiHarness.stats.rendererOptions[0].pixelRatio, 1,
        'snapshot size must be independent of the host devicePixelRatio');
    assert.strictEqual(dpiHarness.stats.rendererOptions[0].animate, false,
        'one-shot portrait bake must not schedule an animation loop');
    cases++;

    const exceptionHarness = createHarness({
        concurrency: 4,
        createRenderer: function(index) {
            let calls = 0;
            return {
                render: function() {
                    calls++;
                    if (index <= 4) {
                        if (calls === 1) return { pendingImages: 1, failedImages: 0 };
                        throw new Error('async tick failure ' + index);
                    }
                    return { pendingImages: 0, failedImages: 0 };
                }
            };
        }
    });
    const exceptionNodes = Array.from({ length: 5 }, createNode);
    const exceptionPromises = exceptionNodes.map(function(node, index) {
        return exceptionHarness.api.mount(node.container, node.img, merc('exception-' + index), {});
    });
    await flushMicrotasks();
    let state = exceptionHarness.api.debugState();
    assert.strictEqual(state.activeRenderCount, 4);
    assert.strictEqual(state.queuedRenderCount, 1);
    for (let i = 0; i < 4; i++) assert.strictEqual(exceptionHarness.runNextTimer(), true);
    await Promise.all(exceptionPromises);
    state = exceptionHarness.api.debugState();
    assert.strictEqual(exceptionNodes[4].attrs['data-merc-portrait-state'], 'ready');
    assert.strictEqual(state.activeRenderCount, 0);
    assert.strictEqual(state.queuedRenderCount, 0);
    assert.strictEqual(state.pendingSnapshotCount, 0);
    assert(state.peakActiveRenderCount <= state.maxConcurrentRenders);
    cases++;

    const sharedHarness = createHarness({
        concurrency: 1,
        createRenderer: function() {
            let calls = 0;
            return {
                render: function() {
                    calls++;
                    return calls === 1
                        ? { pendingImages: 1, failedImages: 0 }
                        : { pendingImages: 0, failedImages: 0 };
                }
            };
        }
    });
    const sharedA = createNode();
    const sharedB = createNode();
    const sharedMerc = merc('shared');
    const sharedPromiseA = sharedHarness.api.mount(sharedA.container, sharedA.img, sharedMerc, {});
    const sharedPromiseB = sharedHarness.api.mount(sharedB.container, sharedB.img, sharedMerc, {});
    await flushMicrotasks();
    assert.strictEqual(sharedHarness.stats.creates, 1, 'same key must share one renderer');
    assert.strictEqual(sharedHarness.api.debugState().pendingSubscriberCount, 2);
    sharedHarness.api.clear(sharedA.container, sharedA.img);
    assert.strictEqual(sharedHarness.stats.destroys, 0, 'one remaining subscriber must keep the shared job alive');
    assert.strictEqual(sharedHarness.api.debugState().pendingSubscriberCount, 1);
    assert.strictEqual(sharedHarness.runNextTimer(), true);
    const sharedResults = await Promise.all([sharedPromiseA, sharedPromiseB]);
    assert.strictEqual(sharedResults[0], null);
    assert.strictEqual(sharedResults[1].source, 'shared-pending');
    assert.strictEqual(sharedA.attrs['data-merc-portrait-state'], 'fallback');
    assert.strictEqual(sharedB.attrs['data-merc-portrait-state'], 'ready');
    cases++;

    const cancelA = createNode();
    const cancelB = createNode();
    const cancelMerc = merc('cancel-all');
    const cancelPromiseA = sharedHarness.api.mount(cancelA.container, cancelA.img, cancelMerc, {});
    const cancelPromiseB = sharedHarness.api.mount(cancelB.container, cancelB.img, cancelMerc, {});
    await flushMicrotasks();
    const destroysBeforeCancel = sharedHarness.stats.destroys;
    sharedHarness.api.clear(cancelA.container, cancelA.img);
    sharedHarness.api.clear(cancelB.container, cancelB.img);
    assert.strictEqual(sharedHarness.stats.destroys, destroysBeforeCancel + 1,
        'last subscriber cancellation must destroy the active renderer synchronously');
    const sameTurnRemount = createNode();
    const sameTurnPromise = sharedHarness.api.mount(
        sameTurnRemount.container, sameTurnRemount.img, cancelMerc, {});
    await flushMicrotasks();
    assert.strictEqual(sharedHarness.runNextTimer(), true,
        'same-turn remount must create a fresh pending renderer');
    const sameTurnResult = await sameTurnPromise;
    assert.strictEqual(sameTurnResult.source, 'dressup');
    assert.strictEqual(sameTurnRemount.attrs['data-merc-portrait-state'], 'ready');
    await Promise.all([cancelPromiseA, cancelPromiseB]);
    state = sharedHarness.api.debugState();
    assert.strictEqual(state.activeRenderCount, 0);
    assert.strictEqual(state.pendingSnapshotCount, 0);
    cases++;

    const lruHarness = createHarness({ cacheEntries: 2, cacheBytes: 4096 });
    const normalizedA = createNode();
    const normalizedB = createNode();
    await lruHarness.api.mount(normalizedA.container, normalizedA.img, merc('normalized', {
        gender: 0,
        face: 0,
        hair: '发型-女式-红马尾'
    }), {});
    const normalizedResult = await lruHarness.api.mount(normalizedB.container, normalizedB.img, merc('normalized', {
        gender: '女',
        face: '女变装-基本脸型',
        hair: '发型-女式-玫红色马尾'
    }), {});
    assert.strictEqual(normalizedResult.source, 'cache');
    assert.strictEqual(lruHarness.stats.creates, 1, 'equivalent face/hair aliases must share the normalized key');
    cases++;

    lruHarness.api.clearCache();
    assert.strictEqual(lruHarness.api.debugState().cachedSnapshotCount, 0);
    const lruA1 = createNode(), lruB1 = createNode(), lruA2 = createNode(), lruC1 = createNode(), lruB2 = createNode();
    await lruHarness.api.mount(lruA1.container, lruA1.img, merc('lru-a'), {});
    await lruHarness.api.mount(lruB1.container, lruB1.img, merc('lru-b'), {});
    assert.strictEqual((await lruHarness.api.mount(lruA2.container, lruA2.img, merc('lru-a'), {})).source, 'cache');
    await lruHarness.api.mount(lruC1.container, lruC1.img, merc('lru-c'), {});
    const createsBeforeReload = lruHarness.stats.creates;
    assert.strictEqual((await lruHarness.api.mount(lruB2.container, lruB2.img, merc('lru-b'), {})).source, 'dressup');
    assert.strictEqual(lruHarness.stats.creates, createsBeforeReload + 1, 'least-recently-used entry must be evicted');
    state = lruHarness.api.debugState();
    assert(state.cachedSnapshotCount <= state.maxCachedSnapshotCount);
    assert(state.cachedSnapshotBytes <= state.maxCachedSnapshotBytes);
    lruHarness.api.clearCache();
    assert.strictEqual(lruHarness.api.debugState().cachedSnapshotBytes, 0);
    cases++;

    const byteHarness = createHarness({
        cacheEntries: 8,
        cacheBytes: 40,
        dataUrl: function() { return 'data:image/png;base64,' + 'x'.repeat(40); }
    });
    const firstByteNode = createNode();
    await byteHarness.api.mount(firstByteNode.container, firstByteNode.img, merc('oversize'), {});
    const firstByteCreates = byteHarness.stats.creates;
    const byteNode = createNode();
    await byteHarness.api.mount(byteNode.container, byteNode.img, merc('oversize'), {});
    assert.strictEqual(byteHarness.stats.creates, firstByteCreates + 1, 'entry above byte budget must not remain cached');
    assert.strictEqual(byteHarness.api.debugState().cachedSnapshotCount, 0);
    cases++;

    let releaseManifest;
    const tokenHarness = createHarness({
        loadManifest: function() { return new Promise(function(resolve) { releaseManifest = resolve; }); }
    });
    const tokenNode = createNode();
    const stalePromise = tokenHarness.api.mount(tokenNode.container, tokenNode.img, merc('stale'), {});
    const oldToken = tokenNode.attrs['data-merc-portrait-request'];
    await tokenHarness.api.mount(tokenNode.container, tokenNode.img, null, {});
    assert.strictEqual(tokenNode.attrs['data-merc-portrait-request'], undefined);
    releaseManifest(manifest);
    assert.strictEqual(await stalePromise, null);
    assert.strictEqual(tokenNode.attrs['data-merc-portrait-state'], 'fallback');
    assert.strictEqual(tokenNode.img.src, '');
    assert.notStrictEqual(tokenNode.attrs['data-merc-portrait-request'], oldToken);
    cases++;

    // Cross-runtime duplicate guard: the browser alias table must stay
    // byte-equal to the Node build-time copy in tools/lib/arena-portrait-routing.js.
    // The renderer copy is created inside the vm sandbox, so compare key-by-key
    // instead of relying on prototype-sensitive deepStrictEqual.
    const routing = require(path.join(projectRoot, 'tools', 'lib', 'arena-portrait-routing.js'));
    const aliasHarness = createHarness({});
    const browserAliases = aliasHarness.api.HAIR_COMPAT_ALIASES;
    assert.deepStrictEqual(Object.keys(browserAliases).sort(), Object.keys(routing.HAIR_COMPAT_ALIASES).sort());
    for (const aliasKey of Object.keys(routing.HAIR_COMPAT_ALIASES)) {
        assert.strictEqual(browserAliases[aliasKey], routing.HAIR_COMPAT_ALIASES[aliasKey]);
    }
    cases++;

    process.stdout.write(JSON.stringify({ ok: true, cases }, null, 2) + '\n');
})().catch(function(error) {
    console.error(error && error.stack || error);
    process.exitCode = 1;
});
