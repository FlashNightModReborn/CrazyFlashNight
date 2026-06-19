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
    '        mercAppearanceValue: mercAppearanceValue,',
    '        dressupEquipmentFromMerc: dressupEquipmentFromMerc,',
    '        dressupAppearanceFromMerc: dressupAppearanceFromMerc',
    '    };',
    marker
].join('\n'));

const context = {
    console,
    setTimeout,
    clearTimeout,
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
    face: '',
    faceId: '1',
    hair: '',
    hairId: '17',
    equips: [{ slot: 6, name: '红外线滤光镜' }]
});
assert.strictEqual(appearance['脸型'], '男变装-基本脸型');
assert.strictEqual(appearance['发型'], '发型-男式-黑暴走头');

appearance = appearanceFor({
    gender: '男',
    face: '',
    faceId: '1',
    hair: '',
    hairId: '17',
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
    face: '',
    faceId: 0,
    hair: '',
    hairId: 21,
    equips: []
});
assert.strictEqual(api.normalizeMercGender({ gender: 0 }), '女');
assert.strictEqual(appearance['脸型'], '女变装-基本脸型');
assert.strictEqual(appearance['发型'], '发型-女式-深蓝色蕾丝发带马尾');

process.stdout.write(JSON.stringify({ ok: true, cases: 4 }, null, 2) + '\n');
