'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { loadCompiler } = require('./tooltip-catalog.cjs');
const root = path.resolve(__dirname, '..');
const compiler = loadCompiler();
const texts = Object.create(null);
for (const file of compiler.lists) texts[file] = fs.readFileSync(path.join(root, file), 'utf8');
for (const file of compiler.sourcePaths(texts)) texts[file] = fs.readFileSync(path.join(root, file), 'utf8');
const base = compiler.compile(texts);
const plain = (value) => JSON.parse(JSON.stringify(value));
const file = 'data/crafting/tooltip-fixture.json';
const product = Object.keys(base.payload.items)[0];
function changeRecipe(material) {
    return {
        ...texts,
        'data/crafting/list.xml': '<root><list>tooltip-fixture</list></root>',
        [file]: JSON.stringify([{ name: product, recipeId: 'test.source-upgrade', materials: [material] }])
    };
}
test('only displayed recipe fields change identity; whitespace and editor line endings do not', () => {
    const windows = Object.fromEntries(
        Object.entries(texts).map(([name, text]) => [name, text.replace(/\r?\n/g, '\r\n')])
    );
    const authored = compiler
        .sourcePaths(texts)
        .find((name) => name.startsWith('data/crafting/') && name.endsWith('.json'));
    windows[authored] = '\uFEFF' + JSON.stringify(JSON.parse(texts[authored]), null, 4);
    assert.equal(JSON.stringify(compiler.compile(windows).payload), JSON.stringify(base.payload));
    const changed = compiler.compile(changeRecipe('军用帆布#3')).payload;
    assert.equal(changed.recipes[product].materials.find((r) => r.name === '军用帆布').value, 3);
    assert.equal(compiler.archive(changed.items), compiler.archive(base.payload.items));
    assert.equal(base.payload.skills, undefined);
});
test('bad reference identifies its source and field; checkout can keep unrelated item explanations', () => {
    const invalid = changeRecipe('不存在的布料#3');
    const error = /tooltip-fixture\.json.*test\.source-upgrade.*materials\[\d+\].*不存在的布料/;
    assert.throws(() => compiler.compile(invalid), error);
    const checkout = compiler.compile(invalid, true);
    assert.match(checkout.diagnostic, error);
    assert.equal(checkout.payload.recipesUnavailable, true);
    assert.equal(checkout.payload.recipeTargets[product], true);
    assert.equal(checkout.payload.recipeTargets.AK47, undefined);
    assert.equal(checkout.payload.items.AK47.displayname, base.payload.items.AK47.displayname);
    assert.equal(Object.keys(checkout.payload.recipes).length, 0);
    const brokenJson = compiler.compile({ ...invalid, [file]: '[' }, true);
    assert.equal(brokenJson.payload.recipesUnavailable, true);
    assert.equal(brokenJson.payload.recipeTargets, undefined);
});
test('original duplicate priority, object enumeration, mod normalization and reverse lookup are preserved', () => {
    const p = base.payload;
    assert.deepEqual(plain(base.duplicateItems), [
        { name: 'TheGirl头-NPC', same: true },
        { name: '小F头部', same: false },
        { name: '三戈戟二型', same: false }
    ]);
    assert.equal(p.items['小F头部'].data.level, 10);
    assert.deepEqual(Object.keys(p.items['金蛇剑'].data.skillmultipliers), [
        '龙斩',
        '瞬步斩',
        '拔刀术',
        '凶斩'
    ]);
    assert.deepEqual(plain(p.mods['战术导轨'].provideTagDict), {
        导轨平台: true,
        下导轨挂点: true,
        侧导轨挂点: true,
        瞄具挂点: true
    });
    const etch = p.mods['灰蛊蚀刻霰弹'].stats.override.hitBehavior;
    assert.deepEqual([etch.type, etch.delayFrames, etch.detonationCrumble], ['grayGooEtch', 54, 1]);
    const primer = p.mods['灰蛊裂隙弹'].stats;
    assert.equal(primer.override.hitBehavior.maxStacks, 18);
    assert.deepEqual(plain(primer.useSwitch.useCases.map((r) => r.override.hitBehavior.profileId)), [
        'highPowerHandgun',
        'handgun'
    ]);
    for (const names of Object.values(p.recipesUsing))
        assert.deepEqual(plain(names), Array.from(new Set(names)).sort());
    for (const item of Object.values(p.items)) {
        assert.ok(!('balance' in item));
        assert.ok(!('id' in item));
    }
    assert.deepEqual(plain(p.obtainRecords), {});
});
test('XML scalar, entities, attributes, repeated nodes, unknown expressions and data boundaries', () => {
    const f = 'data/items/消耗品_货币.xml';
    function append(xml) {
        return {
            ...texts,
            [f]: texts[f].replace(/(<\/[^>]+>\s*)$/, () => xml + texts[f].match(/<\/[^>]+>\s*$/)[0])
        };
    }
    const p = compiler.compile(
        append(
            '<item><name>trial</name><x>0</x><x>-3.5</x><flag>TRUE</flag><space>   </space><attr k="2"/><Description>&amp;lt;b&amp;gt;甲\n乙</Description><description>&amp;lt;</description><literal>&amp;#13;</literal></item>'
        )
    ).payload.items.trial;
    assert.deepEqual(plain(p.x), [0, -3.5]);
    assert.equal(p.flag, true);
    assert.equal(p.space, '');
    assert.equal(p.attr.k, 2);
    assert.equal(p.Description, '<b>甲\n乙');
    assert.equal(p.description, '&lt;');
    assert.equal(p.literal, '&#13;');
    assert.throws(() => compiler.compile(append('<item><CaseSwitch/></item>')), /CaseSwitch/);
    assert.throws(() => compiler.compile(append('<item><n>1e999</n></item>')), /Non-finite/);
    assert.throws(
        () =>
            compiler.sourcePaths({ ...texts, 'data/items/list.xml': '<root><items>../bad.xml</items></root>' }),
        /invalid entry/
    );
    assert.throws(() => compiler.compile({ ...texts, [f]: '<!DOCTYPE x><x/>' }), /DTD/);
});
