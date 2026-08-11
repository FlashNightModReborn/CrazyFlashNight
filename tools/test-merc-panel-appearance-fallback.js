'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const rendererPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'merc-portrait-renderer.js');
const mercDataPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'merc-data.js');
const manifestPath = path.join(projectRoot, 'launcher', 'web', 'assets', 'dressup', 'manifest.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

const context = {
    console,
    window: {},
    DressupDollRenderer: {
        buildStateFromEquipment: function(unusedManifest, state) { return state; }
    }
};
context.globalThis = context;

vm.runInNewContext(fs.readFileSync(mercDataPath, 'utf8'), context, { filename: mercDataPath });
context.MercData = context.window.MercData;
vm.runInNewContext(fs.readFileSync(rendererPath, 'utf8'), context, { filename: rendererPath });

const api = context.window.MercPortraits;
assert(api && typeof api.buildState === 'function', 'MercPortraits production module must load');

function stateFor(merc) {
    return api.buildState(merc, { manifest });
}

let cases = 0;

let state = stateFor({
    gender: '男',
    face: '男变装-基本脸型',
    hair: '发型-男式-黑暴走头',
    equips: [{ slot: 6, name: '红外线滤光镜' }]
});
assert.strictEqual(state.gender, '男');
assert.strictEqual(state.appearance['脸型'], '男变装-基本脸型');
assert.strictEqual(state.appearance['发型'], '发型-男式-黑暴走头');
cases++;

state = stateFor({
    gender: '男',
    face: '男变装-基本脸型',
    hair: '发型-男式-黑暴走头',
    equips: [{ slot: 6, name: '黑色摩托头盔' }]
});
assert(!Object.prototype.hasOwnProperty.call(state.appearance, '发型'), 'helmet=true should suppress hair');
cases++;

state = stateFor({
    gender: '男',
    face: '男变装-基本脸型',
    hair: '发型-男式-黑短发',
    equips: []
});
assert.strictEqual(state.appearance['发型'], '发型-男式-精武短发');
cases++;

state = stateFor({ gender: 0, face: 0, hair: 21, equips: [] });
assert.strictEqual(state.gender, '女');
assert.strictEqual(state.appearance['脸型'], '女变装-基本脸型');
assert.strictEqual(state.appearance['发型'], '发型-女式-深蓝色蕾丝发带马尾');
cases++;

state = stateFor({ face: '', hair: '', equips: [] });
assert.strictEqual(state.gender, '女', 'missing gender must match AS2 Arena default');
assert.strictEqual(state.appearance['脸型'], '女变装-基本脸型');
cases++;

state = stateFor({ gender: 'unknown-old-host-value', face: '', hair: '', equips: [] });
assert.strictEqual(state.gender, '女', 'unknown gender must match AS2 Arena default');
assert.strictEqual(state.appearance['脸型'], '女变装-基本脸型');
cases++;

['男', '主角-男', 1].forEach(function(gender) {
    assert.strictEqual(stateFor({ gender, equips: [] }).gender, '男');
});
['女', '主角-女', 0].forEach(function(gender) {
    assert.strictEqual(stateFor({ gender, equips: [] }).gender, '女');
});
cases++;

process.stdout.write(JSON.stringify({ ok: true, cases }, null, 2) + '\n');
