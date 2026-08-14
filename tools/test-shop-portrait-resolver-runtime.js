#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const resolverPath = path.join(projectRoot, 'launcher', 'web', 'modules',
    'shop-portrait-resolver.js');
const resolverSource = fs.readFileSync(resolverPath, 'utf8');
const productionManifestPath = path.join(projectRoot, 'launcher', 'web', 'assets',
    'shop-portraits', 'manifest.json');
const DIGEST_A = 'a'.repeat(64);
const DIGEST_B = 'b'.repeat(64);

function entry(digest) {
    return {
        uri: 'subjects/' + digest + '.png',
        width: 256,
        height: 256,
        bounds: { x: 12, y: 8, width: 220, height: 240 },
        sha256: digest
    };
}

function manifest() {
    return {
        schema: 'cf7-shop-portraits-v1',
        geometry: { width: 256, height: 256 },
        entries: {
            '商店・甲': entry(DIGEST_A),
            heeho君: entry(DIGEST_B)
        }
    };
}

function deferred() {
    let resolve;
    let reject;
    const promise = new Promise(function(onResolve, onReject) {
        resolve = onResolve;
        reject = onReject;
    });
    return { promise, resolve, reject };
}

function loadResolver(options) {
    options = options || {};
    const context = {
        console,
        Promise,
        fetch: options.fetch,
        XMLHttpRequest: options.XMLHttpRequest,
        Date: { now: function() { return options.now ? options.now() : 1000; } },
        window: Object.assign({
            CF7_SHOP_PORTRAIT_ROOT: '/shop-assets/',
            CF7_SHOP_PORTRAIT_RETRY_BASE_MS: 10,
            CF7_SHOP_PORTRAIT_RETRY_MAX_MS: 20
        }, options.window || {})
    };
    context.globalThis = context;
    vm.runInNewContext(resolverSource, context, { filename: resolverPath });
    return context.window.ShopPortraits;
}

function container() {
    const attrs = {};
    const classes = new Set();
    return {
        attrs,
        classes,
        isConnected: true,
        classList: {
            add: function(value) { classes.add(value); }
        },
        setAttribute: function(key, value) { attrs[key] = String(value); },
        getAttribute: function(key) {
            return Object.prototype.hasOwnProperty.call(attrs, key) ? attrs[key] : null;
        },
        removeAttribute: function(key) { delete attrs[key]; }
    };
}

function imageRecorder() {
    let assigned = '';
    const writes = [];
    const attrs = {};
    const image = {
        writes,
        attrs,
        alt: 'must-be-cleared',
        onerror: null,
        onload: null,
        setAttribute: function(key, value) { attrs[key] = String(value); },
        removeAttribute: function(key) {
            if (key === 'src') assigned = '';
            delete attrs[key];
        }
    };
    Object.defineProperty(image, 'src', {
        get: function() { return assigned; },
        set: function(value) {
            assigned = String(value);
            writes.push(assigned);
        }
    });
    return image;
}

(async function() {
    let cases = 0;

    const api = loadResolver();
    api.__setManifestForTests(manifest());
    const resolved = api.resolve('商店・甲');
    assert.strictEqual(resolved.shopId, '商店・甲');
    assert.strictEqual(resolved.url, '/shop-assets/subjects/' + DIGEST_A + '.png');
    assert.deepStrictEqual(JSON.parse(JSON.stringify(resolved.bounds)),
        { x: 12, y: 8, width: 220, height: 240 });
    const productionManifest = JSON.parse(fs.readFileSync(productionManifestPath, 'utf8'));
    const productionApi = loadResolver();
    productionApi.__setManifestForTests(productionManifest);
    const productionShopIds = Object.keys(productionManifest.entries);
    assert(productionShopIds.length > 0, 'production shop portrait manifest must not be empty');
    productionShopIds.forEach(function(shopId) {
        const productionValue = productionApi.resolve(shopId);
        assert(productionValue && productionValue.shopId === shopId,
            'production manifest key must resolve without identity normalization: ' + shopId);
    });
    cases++;

    assert.strictEqual(api.resolve(' 商店・甲'), null, 'shopId must not be trimmed');
    assert.strictEqual(api.resolve('商店・甲 '), null, 'shopId must not be trimmed');
    assert.strictEqual(api.resolve('HEEHO君'), null, 'shopId must not be case folded');
    assert.strictEqual(api.resolve('undefined'), null, 'undefined sentinel is not an identity');
    assert.strictEqual(api.resolve('UnDeFiNeD'), null, 'undefined sentinel check is case insensitive');
    assert.strictEqual(api.resolve('\u0085商店'), null, 'C1 controls are not valid identity text');
    assert.strictEqual(api.resolve('heeho君').sha256, DIGEST_B);
    cases++;

    const invalidManifests = [
        Object.assign({}, manifest(), { schema: 'cf7-shop-portraits-v2' }),
        Object.assign({}, manifest(), { extra: true }),
        Object.assign({}, manifest(), { geometry: { width: 128, height: 256 } }),
        Object.assign({}, manifest(), { entries: [] }),
        Object.assign({}, manifest(), { entries: { bad: Object.assign(entry(DIGEST_A), {
            extra: true
        }) } }),
        Object.assign({}, manifest(), { entries: { bad: Object.assign(entry(DIGEST_A), {
            bounds: { x: 12, y: 8, width: 220, height: 240, extra: 1 }
        }) } }),
        Object.assign({}, manifest(), { entries: { bad: Object.assign(entry(DIGEST_A), {
            uri: 'subjects/' + DIGEST_B + '.png'
        }) } }),
        Object.assign({}, manifest(), { entries: { bad: Object.assign(entry(DIGEST_A), {
            bounds: { x: 250, y: 0, width: 7, height: 1 }
        }) } }),
        Object.assign({}, manifest(), { entries: { ['bad\u0001id']: entry(DIGEST_A) } }),
        Object.assign({}, manifest(), { entries: { ['bad\u0085id']: entry(DIGEST_A) } }),
        Object.assign({}, manifest(), { entries: { [' leading']: entry(DIGEST_A) } }),
        Object.assign({}, manifest(), { entries: { ['trailing ']: entry(DIGEST_A) } }),
        Object.assign({}, manifest(), { entries: { ['   ']: entry(DIGEST_A) } }),
        Object.assign({}, manifest(), { entries: { UnDeFiNeD: entry(DIGEST_A) } })
    ];
    for (const invalid of invalidManifests) {
        const invalidApi = loadResolver();
        assert.throws(function() { invalidApi.__setManifestForTests(invalid); },
            /shop portrait manifest/);
    }
    cases++;

    let now = 0;
    let fetchCalls = 0;
    const retryApi = loadResolver({
        now: function() { return now; },
        fetch: function(url, options) {
            fetchCalls++;
            assert.strictEqual(url, '/shop-assets/manifest.json');
            assert.deepStrictEqual(JSON.parse(JSON.stringify(options)),
                { cache: 'no-cache', credentials: 'same-origin' });
            if (fetchCalls === 1) return Promise.reject(new Error('transient'));
            return Promise.resolve({ ok: true, json: function() { return Promise.resolve(manifest()); } });
        }
    });
    assert.strictEqual(await retryApi.loadManifest(), null);
    assert.strictEqual(await retryApi.loadManifest(), null,
        'cooldown must fail soft without a second transport request');
    assert.strictEqual(fetchCalls, 1);
    now = 10;
    assert((await retryApi.loadManifest()).entries['商店・甲']);
    assert.strictEqual(fetchCalls, 2);
    cases++;

    let boundedNow = 0;
    let boundedCalls = 0;
    const boundedApi = loadResolver({
        now: function() { return boundedNow; },
        fetch: function() {
            boundedCalls++;
            return Promise.reject(new Error('still unavailable'));
        }
    });
    assert.strictEqual(await boundedApi.loadManifest(), null);
    boundedNow = 10;
    assert.strictEqual(await boundedApi.loadManifest(), null);
    boundedNow = 29;
    assert.strictEqual(await boundedApi.loadManifest(), null);
    assert.strictEqual(boundedCalls, 2, 'second cooldown must grow to the configured maximum');
    boundedNow = 30;
    assert.strictEqual(await boundedApi.loadManifest(), null);
    boundedNow = 49;
    assert.strictEqual(await boundedApi.loadManifest(), null);
    assert.strictEqual(boundedCalls, 3, 'retry delay must remain bounded at the maximum');
    boundedNow = 50;
    assert.strictEqual(await boundedApi.loadManifest(), null);
    assert.strictEqual(boundedCalls, 4);
    cases++;

    const mountedContainer = container();
    const mountedImage = imageRecorder();
    const mountedValue = await api.mount(mountedContainer, mountedImage, '商店・甲');
    assert.strictEqual(mountedValue.shopId, '商店・甲');
    assert.strictEqual(mountedImage.alt, '');
    assert.strictEqual(mountedImage.attrs.alt, '');
    assert.strictEqual(mountedImage.attrs['aria-hidden'], 'true');
    assert.strictEqual(mountedImage.draggable, false);
    assert.strictEqual(mountedImage.decoding, 'async');
    assert.strictEqual(mountedImage.writes[0], '/shop-assets/subjects/' + DIGEST_A + '.png');
    assert.strictEqual(mountedContainer.attrs['data-shop-portrait-source'], 'placeholder');
    mountedImage.onload();
    assert.strictEqual(mountedContainer.attrs['data-shop-portrait-source'], 'manifest');
    assert.strictEqual(mountedContainer.attrs['data-shop-portrait-id'], '商店・甲');
    cases++;

    const missContainer = container();
    const missImage = imageRecorder();
    assert.strictEqual(await api.mount(missContainer, missImage, '不存在'), null);
    assert.deepStrictEqual(missImage.writes, []);
    assert.strictEqual(missContainer.attrs['data-shop-portrait-source'], 'placeholder');
    assert.strictEqual(missImage.alt, '', 'missing portraits retain decorative no-alt semantics');
    cases++;

    const failedContainer = container();
    const failedImage = imageRecorder();
    await api.mount(failedContainer, failedImage, 'heeho君');
    assert.strictEqual(typeof failedImage.onerror, 'function');
    failedImage.onerror();
    assert.strictEqual(failedImage.onerror, null);
    assert.strictEqual(failedImage.onload, null);
    assert.strictEqual(failedImage.src, '');
    assert.strictEqual(failedContainer.attrs['data-shop-portrait-source'], 'placeholder');
    assert.strictEqual(failedContainer.attrs['data-shop-portrait-id'], undefined);
    cases++;

    const delayed = deferred();
    const staleApi = loadResolver({
        fetch: function() { return delayed.promise; }
    });
    const staleContainer = container();
    const staleImage = imageRecorder();
    const staleMount = staleApi.mount(staleContainer, staleImage, '商店・甲');
    const currentImage = imageRecorder();
    const currentMount = staleApi.mount(staleContainer, currentImage, 'heeho君');
    delayed.resolve({ ok: true, json: function() { return Promise.resolve(manifest()); } });
    assert.strictEqual(await staleMount, null, 'superseded request must not mutate its image');
    assert.strictEqual((await currentMount).shopId, 'heeho君');
    assert.deepStrictEqual(staleImage.writes, []);
    assert.strictEqual(currentImage.writes.length, 1);
    cases++;

    const disconnected = deferred();
    const disconnectedApi = loadResolver({
        fetch: function() { return disconnected.promise; }
    });
    const disconnectedContainer = container();
    const disconnectedImage = imageRecorder();
    const disconnectedMount = disconnectedApi.mount(disconnectedContainer,
        disconnectedImage, '商店・甲');
    disconnectedContainer.isConnected = false;
    disconnected.resolve({ ok: true, json: function() { return Promise.resolve(manifest()); } });
    assert.strictEqual(await disconnectedMount, null);
    assert.deepStrictEqual(disconnectedImage.writes, []);
    cases++;

    const staleLoadContainer = container();
    const staleLoadImage = imageRecorder();
    await api.mount(staleLoadContainer, staleLoadImage, '商店・甲');
    const staleOnload = staleLoadImage.onload;
    await api.mount(staleLoadContainer, staleLoadImage, 'heeho君');
    staleOnload();
    assert.notStrictEqual(staleLoadContainer.attrs['data-shop-portrait-id'], '商店・甲',
        'late image completion must be fenced by the current request token');
    cases++;

    const asyncApi = loadResolver({
        fetch: function() {
            return Promise.resolve({ ok: true, json: function() { return Promise.resolve(manifest()); } });
        }
    });
    assert.strictEqual((await asyncApi.resolveAsync('heeho君')).shopId, 'heeho君');
    assert.strictEqual(await asyncApi.resolveAsync(' heeho君'), null);
    cases++;

    process.stdout.write(JSON.stringify({ ok: true, cases }, null, 2) + '\n');
})().catch(function(error) {
    console.error(error && error.stack || error);
    process.exitCode = 1;
});
