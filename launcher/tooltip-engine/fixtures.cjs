#!/usr/bin/env node
'use strict';
// Test/benchmark inputs only. They intentionally do not reproduce the AS2
// calculator, matcher, discovery index or normalizers. They are not an oracle.
const fs = require('node:fs');
const path = require('node:path');
const repo = path.resolve(__dirname, '../..');
const defaultCatalog = path.join(repo, 'data/tooltip/tooltip-catalog.json');
function catalogText() {
    if (fs.existsSync(path.join(repo,'tools/tooltip-catalog.cjs'))) return require('../../tools/tooltip-catalog.cjs').compile(repo).catalog;
    return fs.readFileSync(defaultCatalog,'utf8');
}

function itemInput(catalog, itemName, overrides = {}) {
    const item = catalog.items[itemName];
    const equipment = item.type === '武器' || item.type === '防具';
    const projection = {
        isEquipment: equipment, isMaterial: !equipment && item.use === '材料',
        isInformation: !equipment && item.use === '情报' && item.maxvalue > 0,
        calculated: null, baselineData: item.data && item.use !== '药剂' ? item.data : null,
        bladeCount: 0, isVerticalBullet: false, electric: false,
        registeredModName: catalog.mods[itemName] ? itemName : null,
        tierOptions: [], drugEffects: [], mods: {}, obtainRecords: [],
        ...overrides.projection
    };
    return { version: 1, kind: 'item', itemName, value: { level: 1 },
        presentation: 'native', ...overrides, projection };
}
function createInputs(catalog) {
    const inputs = Object.keys(catalog.items).map(name => itemInput(catalog, name));
    const gun = catalog.items['TTI Benelli M4'];
    if (gun) {
        const calculated = {};
        for (const key of ['description', 'displayname', 'icon', 'use', 'weapontype', 'actiontype', 'data', 'skill', 'subweapon', 'lifecycle']) {
            if (gun[key] !== undefined) calculated[key] = gun[key];
        }
        // Supplied effective values, deliberately not calculated from mods/tier.
        calculated.data = { ...gun.data, power: 1234, capacity: 8,
            overload: { chamber: 1, ghost: 1, ghostLimit: 2 } };
        const mod = '枪械内构强化套件';
        const projection = { calculated, levelMultiplier: 1.5,
            mods: { [mod]: { present: true, useCases: [], bulletCases: [], skill: null } },
            obtainRecords: [{ kind: 'shop', npc: '合成基准商人' }],
            tierOptions: [{ name: '合成测试阶', available: true, material: '钢材' }] };
        for (const presentation of ['native', 'inventory', 'web']) {
            inputs.push(itemInput(catalog, gun.name, { presentation, value: { level: 5, mods: [mod] }, projection }));
        }
        inputs.push(itemInput(catalog, gun.name, { output: 'details', value: { level: 5, mods: [mod] }, projection }));
    }
    const drug = Object.values(catalog.items).find(item => item.use === '药剂');
    if (drug) {
        const projection = { drugEffects: [
            { type: 'heal', hp: 20, scaleWithAlchemy: true },
            { type: 'buff', property: 'damage', calc: 'add', value: 50, duration: 1800, scaleWithAlchemy: true }
        ] };
        inputs.push(itemInput(catalog, drug.name, { value: 5, projection }));
        inputs.push(itemInput(catalog, drug.name, { value: 1, projection,
            hud: { kind: 'drug', count: 1, slot: 0, key: '1' } }));
    }
    inputs.push(
        { version: 1, kind: 'skill', mode: 'loadout', skillName: '合成技能',
            skillData: { Name: '合成技能', Type: '主动', Equippable: true, CD: 1234, MP: 5, Description: '用于相同运行时输入比较。' },
            state: { level: 2, equipped: true }, resourceHint: { state: 'blocked', reason: 'mp' } },
        { version: 1, kind: 'skill', mode: 'learn', skillName: '合成技能',
            skillData: { Name: '合成技能', Type: '主动', MaxLevel: 10, UnlockSP: 1, UpgradeSP: 2, CD: 1234, MP: 5, UnlockLevel: 3 } },
        { version: 1, kind: 'body', html: '<B>基准</B><BR><FONT COLOR="#ABCDEF">正文 &amp; \u00a0</FONT>', profile: 'dense' },
        { version: 1, kind: 'hud', mode: 'resources', data: { hp: [80, 100], mp: [10, 20], shield: [5, 10], shieldReady: true, shieldPresent: true, poise: .5, experience: [5, 0, 10], sp: 3 } },
        { version: 1, kind: 'hud', mode: 'action', data: { name: '动作', keyLabel: 'Q', description: '动作描述' } },
        { version: 1, kind: 'hud', mode: 'switch', data: { bank: 0, switchKey: 'Tab', otherBankHasStock: true } },
        { version: 1, kind: 'hud', mode: 'weapon', data: { name: '战技', cooldown: 3000, mp: 5, hp: 0, sp: 0, description: '战技描述', resourceHint: { state: 'low', reason: 'mp' } } }
    );
    return inputs;
}
if (require.main === module) {
    const args = process.argv.slice(2);
    if (args.length > 1) throw new Error('usage: node fixtures.cjs [output.jsonl]');
    const inputs = createInputs(JSON.parse(catalogText()));
    const jsonl = inputs.map(x => JSON.stringify(x)).join('\n') + '\n';
    if (args[0]) {
        fs.mkdirSync(path.dirname(path.resolve(args[0])), { recursive: true });
        fs.writeFileSync(args[0], jsonl);
        process.stderr.write(`synthetic-inputs: ${inputs.length}; not an AVM1 oracle; ${path.resolve(args[0])}\n`);
    } else process.stdout.write(jsonl);
}
module.exports = { createInputs, itemInput, defaultCatalog, catalogText, repo };
