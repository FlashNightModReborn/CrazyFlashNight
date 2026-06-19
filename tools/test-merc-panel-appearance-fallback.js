'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const panelPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'merc-panel.js');
const manifestPath = path.join(projectRoot, 'launcher', 'web', 'assets', 'dressup', 'manifest.json');

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
let source = fs.readFileSync(panelPath, 'utf8');

const marker = '    window.MercTeamController = {';
if (!source.includes(marker)) {
    throw new Error('merc-panel.js test hook marker not found');
}

source = source.replace(marker, [
    '    window.__MercPanelAppearanceTest = {',
    '        setManifest: function(manifest) { _dressupManifest = manifest; },',
    '        normalizeMercGender: normalizeMercGender,',
    '        dressupEquipmentFromMerc: dressupEquipmentFromMerc,',
    '        dressupAppearanceFromMerc: dressupAppearanceFromMerc,',
    '        renderDressupSnapshot: renderDressupSnapshot',
    '    };',
    marker
].join('\n'));

const context = {
    console,
    setTimeout: function(fn) { fn(); return 1; },
    clearTimeout,
    document: {
        createElement: function(tagName) {
            assert.strictEqual(tagName, 'canvas');
            return {
                style: {},
                width: 64,
                height: 64,
                toDataURL: function() {
                    context.__toDataUrlCalls = (context.__toDataUrlCalls || 0) + 1;
                    return 'data:image/png;base64,test';
                },
                getContext: function() {
                    return {
                        getImageData: function() {
                            const data = new Uint8ClampedArray(160 * 4);
                            for (let i = 3; i < data.length; i += 4) data[i] = 255;
                            return { data };
                        }
                    };
                }
            };
        }
    },
    window: {
        MercData: { SLOTS: [], SLOT_NAMES: {} },
        addEventListener: function() {},
        removeEventListener: function() {}
    },
    Bridge: {
        on: function() {},
        send: function() {}
    },
    Panels: {
        close: function() {}
    },
    PanelTooltip: {
        hide: function() {}
    },
    DressupDollRenderer: {
        create: function() {
            let calls = 0;
            return {
                render: function() {
                    calls++;
                    context.__renderCalls = calls;
                    const sequence = context.__pendingSequence || [1, 0];
                    const index = Math.min(calls - 1, sequence.length - 1);
                    const failedSeq = context.__failedSequence || [];
                    const fIndex = Math.min(calls - 1, failedSeq.length - 1);
                    const failedImages = failedSeq.length ? (failedSeq[fIndex] || 0) : 0;
                    return { pendingImages: sequence[index], failedImages: failedImages };
                },
                destroy: function() {
                    context.__rendererDestroyed = true;
                }
            };
        }
    }
};
context.globalThis = context;

vm.runInNewContext(source, context, { filename: panelPath });

const api = context.window.__MercPanelAppearanceTest;
assert(api, 'test hook was not installed');
api.setManifest(manifest);

function appearanceFor(merc) {
    const equipment = api.dressupEquipmentFromMerc(merc);
    return api.dressupAppearanceFromMerc(merc, equipment);
}

let appearance = appearanceFor({
    gender: '男',
    face: '男变装-基本脸型',
    hair: '发型-男式-黑暴走头',
    equips: [{ slot: 6, name: '红外线滤光镜' }]
});
assert.strictEqual(appearance['脸型'], '男变装-基本脸型');
assert.strictEqual(appearance['发型'], '发型-男式-黑暴走头');

appearance = appearanceFor({
    gender: '男',
    face: '男变装-基本脸型',
    hair: '发型-男式-黑暴走头',
    equips: [{ slot: 6, name: '黑色摩托头盔' }]
});
assert.strictEqual(appearance['脸型'], '男变装-基本脸型');
assert(!Object.prototype.hasOwnProperty.call(appearance, '发型'), 'helmet=true should suppress hair');

appearance = appearanceFor({
    gender: '男',
    face: '男变装-基本脸型',
    hair: '发型-男式-金色不良少年头',
    equips: [{ slot: 6, name: '红色风镜' }]
});
assert.strictEqual(appearance['发型'], '发型-男式-金色不良少年头');

appearance = appearanceFor({
    gender: 0,
    face: 0,
    hair: 21,
    equips: []
});
assert.strictEqual(api.normalizeMercGender({ gender: 0 }), '女');
assert.strictEqual(appearance['脸型'], '女变装-基本脸型');
assert.strictEqual(appearance['发型'], '发型-女式-深蓝色蕾丝发带马尾');

let snapshotResult = null;
context.__pendingSequence = [1, 0];
context.__renderCalls = 0;
context.__rendererDestroyed = false;
context.__toDataUrlCalls = 0;
api.renderDressupSnapshot({ keyMap: {} }, 64, 64, function(url, meta) {
    snapshotResult = { url, meta };
});
assert(snapshotResult, 'snapshot callback should run');
assert.strictEqual(context.__renderCalls, 2, 'snapshot must wait past the pending image frame');
assert.strictEqual(snapshotResult.url, 'data:image/png;base64,test');
assert.strictEqual(snapshotResult.meta.pendingImages, 0);
assert.strictEqual(context.__rendererDestroyed, true);
assert.strictEqual(context.__toDataUrlCalls, 1);

snapshotResult = null;
context.__pendingSequence = [1];
context.__renderCalls = 0;
context.__rendererDestroyed = false;
context.__toDataUrlCalls = 0;
api.renderDressupSnapshot({ keyMap: {} }, 64, 64, function(url, meta) {
    snapshotResult = { url, meta };
});
assert(snapshotResult, 'snapshot timeout callback should run');
assert(context.__renderCalls >= 50, 'snapshot should keep waiting while image layers are pending');
assert.strictEqual(snapshotResult.url, '', 'snapshot must not cache a partial portrait on timeout');
assert.strictEqual(snapshotResult.meta.pendingImages, 1);
assert.strictEqual(context.__rendererDestroyed, true);
assert.strictEqual(context.__toDataUrlCalls, 0);

// errored layer image (failedImages > 0) must never be cached, even when pending hits 0
snapshotResult = null;
context.__pendingSequence = [0];
context.__failedSequence = [1];
context.__renderCalls = 0;
context.__rendererDestroyed = false;
context.__toDataUrlCalls = 0;
api.renderDressupSnapshot({ keyMap: {} }, 64, 64, function(url, meta) {
    snapshotResult = { url, meta };
});
assert(snapshotResult, 'snapshot failed-layer callback should run');
assert(context.__renderCalls >= 50, 'snapshot should keep waiting while a layer image is errored');
assert.strictEqual(snapshotResult.url, '', 'snapshot must not cache a portrait when a layer image errored (404/decode-fail)');
assert.strictEqual(snapshotResult.meta.failedImages, 1);
assert.strictEqual(context.__toDataUrlCalls, 0);
context.__failedSequence = [];

process.stdout.write(JSON.stringify({ ok: true, cases: 7 }, null, 2) + '\n');
