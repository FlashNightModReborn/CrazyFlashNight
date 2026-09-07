#!/usr/bin/env node
'use strict';
const fs = require('fs'), path = require('path'), cp = require('child_process'), vm = require('vm'), assert = require('assert/strict');
const root = path.resolve(__dirname, '../..');
const { build } = require('./migrate-v2');
const migration = build(), definition = migration.definition;
const roomLocation = Object.keys(definition.locations).find(id => definition.locations[id].sceneName === '房间');
assert(roomLocation, 'Frozen baseline must contain the registered room scene.');
const dotnet = process.env.CF7_DOTNET_EXE || cp.execFileSync('powershell.exe', ['-NoProfile', '-Command', '. ./launcher/resolve-dotnet.ps1; Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path'], { cwd: root, encoding: 'utf8' }).trim();
const cli = path.join(__dirname, 'bin/Release/net10.0/MapWorkbench.dll');
function project(definition, facts, extra = {}) {
    const out = cp.spawnSync(dotnet, [cli, 'project', root], { cwd: root, input: JSON.stringify({ definition, facts, ...extra }), encoding: 'utf8', maxBuffer: 48 * 1024 * 1024 });
    assert.equal(out.signal, null, out.stderr);
    return JSON.parse(out.stdout);
}
function source(file) { return cp.execFileSync('git', ['show', migration.evidence.sourceCommit + ':' + file], { cwd: root, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 }); }
const oldService = source('scripts/类定义/org/flashNight/arki/map/MapPanelService.as');
const avatarRules = [...source('data/map/map_panel.xml').matchAll(/<rule\s+([^>]+)\/>/g)].map(match => Object.fromEntries([...match[1].matchAll(/([A-Za-z]+)="([^"]*)"/g)].map(a => [a[1], a[2]])));
const oldMethod = oldService.slice(oldService.indexOf('private static function isUnlocked('), oldService.indexOf('private static function buildUnlockFlags('))
    .replace('private static function isUnlocked(groupName:String):Boolean', 'function legacy(groupName)');
const context = { _root: {} };
vm.createContext(context);
vm.runInContext('function getInfrastructure(){return _root.基建系统.infrastructure;}\n' + oldMethod, context, { timeout: 1000 });
const thresholdValues = [...new Set([0, ...avatarRules.filter(r => r.chain === '主线').flatMap(r => [Number(r.min) - 1, Number(r.min)]), ...Object.values(definition.rules).flatMap(rule => {
    const values = [];
    function visit(n) { if (n.type === 'chain' && n.key === '主线') values.push(n.min - 1, n.min); for (const c of n.children || []) visit(c); }
    visit(rule.condition); return values;
})])].sort((a, b) => a - b);
const facts = [];
for (const progress of thresholdValues) for (const university of [0, 6, 7]) for (let vehicle = 0; vehicle < 8; vehicle++) facts.push({
    chains: { 主线: progress, 大学: university }, infrastructure: { 自行车: !!(vehicle & 1), 摩托车: !!(vehicle & 2), 越野车: !!(vehicle & 4) },
    tasks: {}, activeOrder: [], scene: { stageFlag: '房间', frameLabel: '基地地图', entrance: '出生地', mapFrame: '', inCombat: false }, navigation: { reason: '' }, dynamic: { roommateGender: '男' }
});
assert(facts.length <= 1024);
const result = project(definition, facts, { summary: true }); assert.equal(result.success, true, result.error);
let assertions = 0;
for (let i = 0; i < facts.length; i++) {
    context._root = { task_chains_progress: facts[i].chains, 基建系统: { infrastructure: facts[i].infrastructure } };
    for (const id of Object.keys(definition.rules)) {
        const group = id.slice(7);
        assert.equal(result.results[i].unlocks[group], context.legacy(group), group + ' case ' + i); assertions++;
    }
    for (const rule of avatarRules) {
        const slotPage = Object.values(definition.pages).find(p => [...p.staticAvatars, ...(p.dynamicAvatars || [])].some(a => a.id === rule.avatarId));
        const slot = [...slotPage.staticAvatars, ...(slotPage.dynamicAvatars || [])].find(a => a.id === rule.avatarId);
        const enter = definition.locations[slot.hotspotId].enterWhen;
        const routeVisible = enter.type === 'always' || context.legacy(enter.key.slice(7));
        const expected = routeVisible && (!rule.chain || facts[i].chains[rule.chain] >= Number(rule.min)) && (!rule.requireInfra || rule.requireInfra.split('|').some(k => facts[i].infrastructure[k]));
        assert.equal(result.results[i].avatarVisibility[rule.avatarId], expected, rule.avatarId + ' case ' + i); assertions++;
    }
    assert.equal(result.results[i].currentLocationId, roomLocation); assertions++;
}
// 第一阶段静态投影不能因领域模型分离而改变几何或 NPC 外观。
const legacy = JSON.parse(source('data/map/map_definition.json'));
for (const pageId of legacy.pageOrder) {
    const old = legacy.pages[pageId], next = result.webDefinition.pages[pageId];
    assert.equal(old.hotspots.length, next.hotspots.length);
    for (let i = 0; i < old.hotspots.length; i++) {
        assert.deepEqual(old.hotspots[i].rect, next.hotspots[i].rect); assert.equal(old.hotspots[i].sceneName, next.hotspots[i].sceneName); assertions += 2;
    }
}
const missing = project(definition, { navigation: { reason: '' } }, { summary: true }); assert.equal(missing.success, true);
assert.equal(missing.results[0].unlocks.schoolOutside, false); assertions++;
const unknown = structuredClone(definition); unknown.rules['unlock.warlord'].condition = { type: 'javascript', value: 'true' };
assert.equal(project(unknown, {}).success, false); assertions++;
const cycle = structuredClone(definition); cycle.rules['unlock.warlord'].condition = { type: 'rule', key: 'unlock.warlord' };
assert.equal(project(cycle, {}).success, false); assertions++;
const bad = structuredClone(definition); bad.locations[roomLocation].sceneName = bad.locations.base_roof.sceneName;
assert.equal(project(bad, {}).success, false); assertions++;
const trial = structuredClone(definition);
const first = Object.entries(trial.placements)[0], secondId = 'place_test_second';
const firstId = first[0], npcId = first[1].npcId;
trial.placements[firstId].presenceWhen = { type: 'chain', key: '主线', min: 0, max: 9 };
trial.placements[firstId].worldBinding = { occurrenceId: 'fixture_a', sourceDigest: 'A'.repeat(64) };
trial.placements[secondId] = { ...structuredClone(first[1]), locationId: roomLocation, presenceWhen: { type: 'chain', key: '主线', min: 10 }, worldBinding: { occurrenceId: 'fixture_b', sourceDigest: 'B'.repeat(64) } };
const worldBindings = { fixture_a: { ready: true, sourceDigest: 'A'.repeat(64), sceneKey: trial.locations[first[1].locationId].sceneName, taskName: trial.npcs[npcId].runtimeNames[0] },
    fixture_b: { ready: true, sourceDigest: 'B'.repeat(64), sceneKey: trial.locations[roomLocation].sceneName, taskName: trial.npcs[npcId].runtimeNames[0] } };
const tasks = { 1: { id: 1, get_npc: 'Pig', finish_endpoint: { mode: 'followCurrent', npcId } }, 2: { id: 2, get_npc: 'Pig', finish_endpoint: { mode: 'fixed', npcId, placementId: firstId } } };
const early = { ...facts[0], chains: { 主线: 9, 大学: 0 }, tasks: { 1: { active: true, deliverable: true }, 2: { active: true, deliverable: true } }, activeOrder: ['1', '2'] };
const late = { ...early, chains: { 主线: 10, 大学: 0 } };
const routes = project(trial, [early, late], { tasks, worldBindings }); assert.equal(routes.success, true, routes.error);
assert.equal(routes.results[0].taskEndpoints['1'].finish.placementId, firstId);
assert.equal(routes.results[1].taskEndpoints['1'].finish.placementId, secondId);
assert.equal(routes.results[1].taskEndpoints['2'].finish.resolved, false);
assert.equal(routes.results[1].delivery.hotspotId, roomLocation); assertions += 4;
trial.placements[firstId].presenceWhen = { type: 'always' };
const conflict = project(trial, late, { tasks, worldBindings }); assert.equal(conflict.success, true, conflict.error);
assert.equal(conflict.results[0].taskEndpoints['1'].finish.status, 'ambiguous_placement'); assertions++;
console.log(`Map domain: ${facts.length} legacy progress/vehicle cases, ${assertions} assertions; same geometry, unknown/cycle rejection, fixed/follow migration and conflict passed.`);
