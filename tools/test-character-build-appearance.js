#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ROOT = path.resolve(__dirname, '..');
for (const name of ['asset-timeline', 'dressup-doll-renderer', 'character-appearance-preview']) {
    vm.runInThisContext(fs.readFileSync(path.join(ROOT, 'launcher/web/modules', name + '.js'), 'utf8'), {filename:name});
}
const Controller = require('../launcher/web/modules/character-build.js').CharacterBuildController;
const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'launcher/web/assets/dressup/manifest.json'), 'utf8').replace(/^\uFEFF/, ''));
const itemName = '火药燃气液压打桩机';
const baseKey = '枪-长枪-火药燃气液压打桩机';
const tierKey = '枪-长枪-Codex-打桩机M7';
function appearance(dressup, extra) {
    return Object.assign({dressup, dressup1:'', dressup2:'', dressup3:'', helmet:false, hairAbove:false}, extra);
}
function state(gender, worn, candidate) {
    const context = {
        _manifest:manifest,
        _selectedTarget:{kind:'equipment', slotKey:'长枪'},
        _snapshotPayload:{
            portrait:{gender, equipment:{'长枪':itemName}, appearance:{}},
            equipment:[{slotKey:'长枪', occupied:true, item:{name:itemName, appearance:worn}}]
        }
    };
    return Controller.prototype._portraitState.call(context, candidate);
}
let cases = 0;
for (const gender of ['男', '女']) {
    assert.equal(state(gender, appearance(tierKey)).keyMap['长枪_装扮'], tierKey);
    const candidate = {raw:{item:{name:itemName, appearance:appearance(baseKey)}}};
    const before = JSON.stringify(candidate);
    assert.equal(state(gender, appearance(tierKey), candidate).keyMap['长枪_装扮'], baseKey);
    assert.equal(JSON.stringify(candidate), before);
    assert.equal(state(gender, appearance(baseKey), {raw:{item:{name:itemName, appearance:appearance(tierKey)}}}).keyMap['长枪_装扮'], tierKey);
    assert.equal(state(gender, appearance(tierKey), {raw:{item:{name:itemName}}}).keyMap['长枪_装扮'], baseKey);
    assert.equal(state(gender, null).keyMap['长枪_装扮'], baseKey);
    assert.equal(state(gender, appearance('missing-tier-skin')).keyMap['长枪_装扮'], 'missing-tier-skin');
    cases += 7;

    // The existing generated base catalog is an independent oracle for all
    // gender/part expansion rules, including multi-part blades and armor.
    for (const [name, item] of Object.entries(manifest.items)) {
        if (item.virtual || !item.fieldsByGender || !item.fieldsByGender[gender]) continue;
        const part = item.fieldsByGender[gender];
        const resolved = appearance(item.dressup || '', {helmet:!!item.helmet, hairAbove:!!item.hairAbove});
        if (item.use === '刀') for (const i of [1,2,3]) resolved['dressup' + i] = part['刀' + i + '_装扮'] || '';
        const plain = {gender, equipment:{[item.use]:name}};
        const expected = DressupDollRenderer.buildStateFromEquipment(manifest, plain);
        const actual = DressupDollRenderer.buildStateFromEquipment(manifest,
            {...plain, equipmentAppearance:{[item.use]:resolved}});
        assert.deepEqual(actual.keyMap, expected.keyMap, gender + ' ' + name);
        assert.equal(actual.headHelmet, expected.headHelmet);
        assert.equal(actual.headHairAbove, expected.headHairAbove);
        cases++;
    }
}

const fixture = {items:{gun:{use:'手枪'}, blade:{use:'刀'}, head:{use:'头部装备', helmet:true}}};
const dual = DressupDollRenderer.buildStateFromEquipment(fixture, {
    equipment:{手枪:'gun',手枪2:'gun'}, equipmentAppearance:{手枪:appearance('ice-gun'),手枪2:appearance('fire-gun')}
});
assert.deepEqual(dual.keyMap, {'手枪_装扮':'ice-gun','手枪2_装扮':'fire-gun'});
const blade = DressupDollRenderer.buildStateFromEquipment(fixture, {
    equipment:{刀:'blade'}, equipmentAppearance:{刀:appearance('blade', {dressup1:'edge',dressup2:'sheath',dressup3:'pommel'})}
});
assert.deepEqual(blade.keyMap, {'刀_装扮':'blade','刀1_装扮':'edge','刀2_装扮':'sheath','刀3_装扮':'pommel'});
const head = CharacterAppearancePreview.buildStateFromEquipment(fixture, {
    equipment:{头部装备:'head'}, appearance:{发型:'hair'}, equipmentAppearance:{头部装备:appearance('mask',{hairAbove:true})}
});
assert.equal(head.hairHidden, false);
assert.equal(head.keyMap['发型'], 'hair');
assert.equal(head.headHairAbove, true);
assert.equal(CharacterAppearancePreview.buildStateFromEquipment(fixture, {
    equipment:{头部装备:'head'}, appearance:{发型:'hair'}, equipmentAppearance:{头部装备:appearance('helmet',{helmet:true})}
}).keyMap['发型'], '');
cases += 4;
console.log('PASS character-build resolved appearance: ' + cases + ' cases; current loadout, candidate, legacy, both genders and all base mappings.');
