'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const resolverPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'portrait-resolver.js');
const resolverSource = fs.readFileSync(resolverPath, 'utf8');

function loadResolver(options) {
    options = options || {};
    const context = {
        console,
        Promise,
        fetch: options.fetch,
        Date: { now: function() { return options.now ? options.now() : 1000; } },
        document: {
            createElement: function() {
                return {
                    width: 0,
                    height: 0,
                    getContext: function() {
                        return {
                            clearRect: function() {},
                            drawImage: function() {},
                            getImageData: function() { return { data: new Uint8ClampedArray(32 * 32 * 4) }; }
                        };
                    }
                };
            }
        },
        window: Object.assign({
            CF7_PORTRAIT_MANIFEST_RETRY_BASE_MS: 10,
            CF7_PORTRAIT_MANIFEST_RETRY_MAX_MS: 20
        }, options.window || {})
    };
    context.globalThis = context;
    vm.runInNewContext(resolverSource, context, { filename: resolverPath });
    return context.window.EnemyPortraits;
}

function container() {
    const attrs = {};
    return {
        isConnected: true,
        classList: { add: function() {}, remove: function() {} },
        setAttribute: function(key, value) { attrs[key] = String(value); },
        getAttribute: function(key) { return Object.prototype.hasOwnProperty.call(attrs, key) ? attrs[key] : null; },
        removeAttribute: function(key) { delete attrs[key]; }
    };
}

function imageRecorder() {
    let assigned = '';
    const writes = [];
    const img = {
        writes,
        onerror: null,
        onload: null,
        removeAttribute: function(key) { if (key === 'src') assigned = ''; }
    };
    Object.defineProperty(img, 'src', {
        get: function() {
            return assigned ? 'http://example.test/' + assigned.replace(/^\/+/, '') : '';
        },
        set: function(value) {
            assigned = String(value);
            writes.push(assigned);
        }
    });
    return img;
}

function subject(preferredFormat, svgBytes, pngBytes) {
    const value = {
        svg: { url: 'assets/enemy-portraits/subjects/vector.svg', bytes: svgBytes },
        pngFallback: { url: 'assets/enemy-portraits/subjects/raster.png', bytes: pngBytes }
    };
    if (preferredFormat) value.preferredFormat = preferredFormat;
    return value;
}

const manifest = {
    schema: 'cf7.enemy-portrait-manifest.v1',
    aliases: {
        aliasWhite: { targetPortraitRef: 'multi', variantKey: 'white' }
    },
    entries: {
        multi: {
            defaultVariant: 'orange',
            variants: {
                orange: { status: 'human_accepted', subject: subject('svg', 1000, 500), legacyUrl: 'legacy-orange.png' },
                white: { status: 'human_accepted', subject: subject('svg', 1000, 500), legacyUrl: 'legacy-white.png' }
            }
        },
        pngPreferred: {
            defaultVariant: 'default',
            variants: { default: { status: 'human_accepted', subject: subject('png', 1000, 500), legacyUrl: 'legacy.png' } }
        },
        svgPreferred: {
            defaultVariant: 'default',
            variants: { default: { status: 'human_accepted', subject: subject('svg', 800000, 100000), legacyUrl: 'legacy.png' } }
        },
        legacyHeavy: {
            defaultVariant: 'default',
            variants: { default: { status: 'human_accepted', subject: subject('', 5000000, 400000), legacyUrl: 'legacy.png' } }
        },
        legacyAtFallbackBoundary: {
            defaultVariant: 'default',
            variants: { default: { status: 'human_accepted', subject: subject('', 2 * 1024 * 1024, 256 * 1024), legacyUrl: 'legacy.png' } }
        },
        legacyBelowSizeBoundary: {
            defaultVariant: 'default',
            variants: { default: { status: 'human_accepted', subject: subject('', 2 * 1024 * 1024 - 1, 256 * 1024 - 1), legacyUrl: 'legacy.png' } }
        },
        legacyBelowRatioBoundary: {
            defaultVariant: 'default',
            variants: { default: { status: 'human_accepted', subject: subject('', 2 * 1024 * 1024, 256 * 1024 + 1), legacyUrl: 'legacy.png' } }
        }
    }
};

(async function() {
    let cases = 0;
    let now = 0;
    let fetchCalls = 0;
    const retryApi = loadResolver({
        now: function() { return now; },
        fetch: function() {
            fetchCalls++;
            if (fetchCalls === 1) return Promise.reject(new Error('transient manifest failure'));
            return Promise.resolve({ ok: true, json: function() { return Promise.resolve(manifest); } });
        }
    });
    assert.strictEqual(await retryApi.loadManifest(), null);
    assert.strictEqual(await retryApi.loadManifest(), null, 'cooldown should fail soft without hammering transport');
    assert.strictEqual(fetchCalls, 1);
    now = 10;
    assert.strictEqual(await retryApi.loadManifest(), manifest, 'manifest should retry after bounded cooldown');
    assert.strictEqual(fetchCalls, 2);
    cases++;

    const api = loadResolver();
    api.__setManifestForTests(manifest);
    assert.strictEqual(api.resolve({ portraitRef: 'aliasWhite' }).variantKey, 'white');
    cases++;
    assert.strictEqual(api.resolve({ portraitRef: 'aliasWhite', portraitVariant: 'orange' }).variantKey, 'orange');
    cases++;

    async function firstSource(ref) {
        const img = imageRecorder();
        await api.mount(container(), img, { portraitRef: ref, legacyUrl: 'legacy.png' });
        return img.writes[0];
    }

    assert(/raster\.png$/.test(await firstSource('pngPreferred')), 'preferredFormat=png must be primary');
    cases++;
    assert(/vector\.svg$/.test(await firstSource('svgPreferred')), 'preferredFormat=svg must override size heuristic');
    cases++;
    assert(/raster\.png$/.test(await firstSource('legacyHeavy')), 'old manifests should use bounded size-ratio fallback');
    cases++;
    assert(/raster\.png$/.test(await firstSource('legacyAtFallbackBoundary')), 'legacy fallback must include the exact 2MiB/8x boundary');
    cases++;
    assert(/vector\.svg$/.test(await firstSource('legacyBelowSizeBoundary')), 'legacy fallback must remain SVG-first below 2MiB');
    cases++;
    assert(/vector\.svg$/.test(await firstSource('legacyBelowRatioBoundary')), 'legacy fallback must remain SVG-first below 8x');
    cases++;

    const lockedImg = imageRecorder();
    await api.mount(container(), lockedImg, { locked: true, legacyUrl: 'assets/pets/custom-locked.png' });
    assert.strictEqual(lockedImg.writes.length, 1);
    const firstError = lockedImg.onerror;
    assert.strictEqual(typeof firstError, 'function');
    firstError.call(lockedImg);
    assert.strictEqual(lockedImg.writes.length, 2, 'legacy failure may request the sealed fallback once');
    assert.strictEqual(lockedImg.onerror, null, 'sealed fallback must not retain a recursive error handler');
    cases++;

    process.stdout.write(JSON.stringify({ ok: true, cases }, null, 2) + '\n');
})().catch(function(error) {
    console.error(error && error.stack || error);
    process.exitCode = 1;
});
