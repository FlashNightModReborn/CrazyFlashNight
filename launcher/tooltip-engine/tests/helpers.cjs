'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const repo = path.resolve(__dirname, '../../..');
const bundlePath = path.join(repo, 'launcher/scripts/dist/tooltip-bundle.js');
function load() {
    const sandbox = vm.createContext({});
    vm.runInContext(fs.readFileSync(bundlePath, 'utf8'), sandbox, { filename: 'tooltip-bundle.js' });
    return sandbox.TooltipEngine;
}
function catalog() {
    return {
        version: 1, contentVersion: 'test:source-defined',
        items: {
            gun: { name: 'gun', displayname: '测试枪', icon: '枪图标', type: '武器', use: '长枪', weapontype: '突击步枪', price: 10,
                description: '说明\n    【夜视】测试\n    主体', data: { level: 1, weight: 30, power: 100, capacity: 10, split: 1, interval: 200, bullet: '普通子弹', clipname: 'ammo' } },
            ammo: { name: 'ammo', displayname: '测试弹药', icon: '弹药图标', type: '消耗品', use: '弹夹', price: 2 },
            drug: { name: 'drug', displayname: '测试药剂', icon: '药图标', type: '消耗品', use: '药剂', price: 3, data: {} },
            mod: { name: 'mod', displayname: '测试插件', icon: '插件图标', type: '消耗品', use: '材料', price: 5 },
            material: { name: 'material', displayname: '测试材料', icon: '材料图标', type: '消耗品', use: '材料', price: 1 },
        },
        mods: {}, levelStatList: [0, 1, 1.1], recipes: {}, recipesUsing: {}, enemyNames: {}, magicDamageTypes: { 热: true, 冷: true }
    };
}
function input(c, name = 'gun', patch = {}) {
    const item = c.items[name];
    const equipment = item.type === '武器' || item.type === '防具';
    const projection = {
        isEquipment: equipment, isMaterial: !equipment && item.use === '材料', isInformation: !equipment && item.use === '情报' && item.maxvalue > 0,
        registeredModName: null, baselineData: item.data, bladeCount: 0, isVerticalBullet: false, electric: false,
        tierOptions: [], drugEffects: [], mods: {}, obtainRecords: [], ...patch.projection
    };
    return { version: 1, kind: 'item', itemName: name, value: { level: 1 }, presentation: 'inventory', ...patch, projection };
}
function plain(value) { return JSON.parse(JSON.stringify(value)); }
function docText(doc) { return doc.sections.map(s => (s.runs || []).map(r => r.text).join('')).join('\n'); }
function deepFreeze(value) {
    if (value && typeof value === 'object' && !Object.isFrozen(value)) {
        for (const x of Object.values(value)) deepFreeze(x);
        Object.freeze(value);
    }
    return value;
}
module.exports = { load, catalog, input, plain, docText, deepFreeze, repo, bundlePath };
