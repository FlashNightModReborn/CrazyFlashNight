'use strict';
// Expectations below predate this port. They are copied from AS2 test source at
// db6d3d248b80b80651987c99557c4e83b56f9301, not captured from this implementation.
// These are source-defined content regressions, not a fresh AVM1 parity corpus.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { load, catalog, input, repo } = require('./helpers.cjs');
const E = load();
const production = JSON.parse(fs.readFileSync(path.join(repo, 'data/tooltip/tooltip-catalog.json'), 'utf8'));
function context(c = production, projection = {}) {
    return { input: { version: 1, kind: 'item' }, catalog: c, projection };
}

test('EquipmentIntervalCurveTest: standalone curve text and legacy compression', () => {
    // scripts/.../arki/item/equipment/EquipmentIntervalCurveTest.as:115-130
    const ctx = context(production, { registeredModName: '磁稳贯穿弹' });
    const html = E.ModStatBuilder.build(ctx, '磁稳贯穿弹').join('');
    assert.ok(html.includes('柔性增加，最多 +32毫秒'));
    assert.ok(!html.includes('saturatingAdd'));
    const lines = [];
    E.UseSwitchStatsBuilder.buildStatBlock(ctx, lines, { curve: { diffusion: 1.414 } }, '');
    assert.ok(lines.join('').includes('压缩等级 20'));
});

test('WeaponAmmoDataTest: chamber, ghost and reward keep separate annotations', () => {
    // scripts/.../arki/unit/Action/Shoot/WeaponAmmoDataTest.as:75-115
    // Effective values are the explicit results asserted by that domain test;
    // the TS content test does not reproduce EquipmentCalculator/merge rules.
    const ctx = context();
    const tti = { capacity: 7, overload: { chamber: 1, ghost: 1, ghostLimit: 2 } };
    const ttiText = E.WeaponAmmoInfoBuilder.capacitySuffix(ctx, tti);
    assert.ok(ttiText.includes("#FFCC70'>+2"));
    assert.ok(ttiText.includes("#9BE0E9'>+1"));
    const lines = [];
    E.UseSwitchStatsBuilder.buildStatBlock(ctx, lines, production.mods['枪械内构强化套件'].stats, '');
    assert.ok(lines.join('').includes('幽灵装填上限 → 2发'));
    assert.ok(!lines.join('').includes('[object Object]'));
    const gm6 = { capacity: 5, overload: { chamber: 1, ghost: 0, ghostLimit: 2, reward: 1 } };
    const gm6Text = E.WeaponAmmoInfoBuilder.capacitySuffix(ctx, gm6);
    assert.ok(gm6Text.includes("#CAADFF'>+5"));
    assert.ok(!gm6Text.includes('#FFCC70'));
});

test('EquipmentEmissiveAssetTest: flashlight, laser and all authored emissions', () => {
    // scripts/.../arki/render/EquipmentEmissiveAssetTest.as:70-103
    const ctx = context();
    const torch = E.EquipmentLightingInfoBuilder.build(ctx, production.mods['战术手电'], null, true).join('');
    assert.ok(torch.includes('近身补光') && torch.includes('+20') && torch.includes('+25'));
    const laser = E.EquipmentLightingInfoBuilder.build(ctx, production.mods['镭射瞄准具'], null, true).join('');
    assert.ok(laser.includes('狭窄束带') && !laser.includes('闪避'));
    const authored = Object.values(production.items).filter(item =>
        item.lifecycle?.attr_环境光?.init?.initRoutines === '装备自发光初始化');
    assert.equal(authored.length, 30, 'existing AS2 source requires thirty authored independent emissions');
    for (const item of authored) {
        assert.ok(E.EquipmentLightingInfoBuilder.build(ctx, item, null, false).join('').includes('【照明效果】'), item.name);
    }
});

test('SheriffArsenalTest: built-in flashlight describes the asserted 20-point bonus', () => {
    // scripts/.../arki/unit/UnitComponent/Dressup/EquipmentUtil/SheriffArsenalTest.as:74-82
    const text = E.EquipmentLightingInfoBuilder.build(context(production, { electric: false }),
        production.items['特勤霰弹枪'], [], false).join('');
    assert.ok(text.includes('20'));
    assert.ok(text.includes('闪避加成 +20'));
});

test('LongGunSubWeaponCoreTest: normalized subweapon text keeps ammo, damage and cost', () => {
    // scripts/.../arki/unit/Action/Shoot/LongGunSubWeaponCoreTest.as:1947-1956;
    // makeSubweapon at 1975. Defaults below are the projected normalizer output.
    const subweapon = { name: '测试副武器', controlName: '测试副武器', description: '测试副武器说明。',
        cd: 3000, consumeMode: 'onFire', consumeTiming: 'onFire', mp: 100, power: 1000,
        capacity: 5, initialLoaded: 5, reserveName: '火焰喷射器燃料罐', bullet: '测试榴弹',
        sound: 'test.wav', split: 1, diffusion: 3, velocity: 30, range: 50, impact: 5,
        damageType: '破击', magicType: '生化', fireCost: 1, clipCostPerLoad: 1 };
    const joined = E.TooltipTextBuilder.buildSubweaponInfo(context(production, { subweapon }), subweapon).join('');
    assert.ok(joined.includes(E.TooltipConstants.LBL_SUBWEAPON));
    assert.ok(!joined.includes(E.TooltipConstants.LBL_ACTIVE_SKILL));
    assert.ok(joined.includes('火焰喷射器燃料罐'));
    assert.ok(joined.includes('破击'));
    assert.ok(joined.includes('100'));
});

test('ArenaDropRuleCatalogTest: carrier scope determines concise acquisition wording', () => {
    // scripts/.../arki/merc/ArenaDropRuleCatalogTest.as:137-146
    const source = { kind: 'drop', dropType: 'arena', arenaId: 'death_match', arenaLabel: 'DEATH MATCH' };
    const carrier = E.ObtainMethodsBuilder.build(context(production, {
        obtainRecords: [{ ...source, carrierScope: 'carrier', probability: 100 }]
    }), '斩马刀').join('');
    const specific = E.ObtainMethodsBuilder.build(context(production, {
        obtainRecords: [{ ...source, carrierScope: 'specific_carrier', probability: 14.285714,
            selectionWeight: 1, totalWeight: 7 }]
    }), '合金盔').join('');
    assert.ok(carrier.includes('竞技场：') && specific.includes('竞技场：'));
    assert.ok(carrier.includes('携带该装备的佣兵'));
    assert.ok(!carrier.includes('携带该装备的特定佣兵'));
    assert.ok(specific.includes('携带该装备的特定佣兵'));
    assert.ok(!carrier.includes('DEATH MATCH'));
    assert.ok(!specific.includes('1/7'));
});

test('CraftingPanelServiceTest: grouped discovery sources preserve legacy display names', () => {
    // scripts/.../arki/item/CraftingPanelServiceTest.as:1945-1949
    const c = catalog();
    const i = input(c, 'material', { projection: { obtainRecords: [
        { kind: 'drop', dropType: 'stage', stageName: '测试关卡多档', probability: 0,
            variants: [{ occurrenceIndex: 0 }, { occurrenceIndex: 1 }, { occurrenceIndex: 2 }] },
        { kind: 'drop', dropType: 'enemy', enemyType: '敌人-测试四档', enemyDisplayName: '测试四档', probability: 0,
            minLevel: 0, maxLevel: 999, variants: [{ occurrenceIndex: 0 }, { occurrenceIndex: 1 }] }
    ] } });
    const text = E.buildProjection(i, c).descHTML;
    assert.ok(text.includes('测试关卡多档'));
    assert.ok(text.includes('测试四档'));
});

test('Web preview retains inline crit for current consumable grenades', () => {
    // Original Web物品注释HTML rebuilds crit only under ItemUtil.isEquipment.
    // These three current XML items have crit metadata but are consumables.
    for (const name of ['十字螺旋手里剑', '寒铁镖', '鎏金雀翎']) {
        const web = E.buildProjection(input(production, name, { presentation: 'web' }), production);
        const native = E.buildProjection(input(production, name, { presentation: 'native' }), production);
        const text = section => section.runs.map(run => run.text).join('');
        assert.ok(web.document.sections.some(section => section.role === 'intro' && text(section).includes('暴击')), name);
        assert.ok(native.document.sections.some(section => section.role === 'sub' && text(section).includes('暴击')), name);
        assert.ok(!web.descHTML.includes('暴击'), name + ': compatibility desc must not repeat intro crit');
    }
});

test('catalog item clone order preserves the current golden-snake blade skill list', () => {
    // 武器_刀_直剑.xml children: 凶斩, 拔刀术, 瞬步斩, 龙斩.
    // ItemUtil.getItemData -> ObjectUtil.cloneFast reverses object insertion;
    // the two Builder for..in passes then produce the reverse authored order.
    // This is a source-derived order assertion, not a fresh AVM1 capture.
    const item = production.items['金蛇剑'];
    const html = E.TooltipTextBuilder.buildBladeSkillMultipliers(context(), item, null).join('');
    const expected = ['龙斩', '瞬步斩', '拔刀术', '凶斩'];
    let previous = -1;
    for (const name of expected) {
        const index = html.indexOf(name);
        assert.ok(index > previous, name + ': source-derived display order');
        previous = index;
    }
});
