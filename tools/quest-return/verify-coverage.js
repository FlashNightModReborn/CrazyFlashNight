'use strict';

// 只读：用生产 C# 地图域复核新增地点/人物与原始 NPC 脚本，不重写条件求值器。
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert/strict');
const domain = require('../lib/map-domain');
const root = path.resolve(__dirname, '../..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/^\uFEFF/, '');
const definition = JSON.parse(read('data/map/map_definition.json'));
assert(!definition.pageOrder.includes('outskirts'), '彩蛋系列不得新增公开聚落页');
assert(!Object.values(definition.pages).some(page => page.hotspots.some(h => ['survivor_camp', 'easter_egg'].includes(h.locationId))),
  '独立场景只登记交付端点，不得生成公开地图入口');
const evidence = JSON.parse(read('tools/quest-return/coverage-evidence.json'));
const taskFiles = [...read('data/task/list.xml').matchAll(/<task>([^<]+)<\/task>/g)].map(m => m[1]);
const tasks = {};
for (const file of taskFiles) {
  for (const task of JSON.parse(read('data/task/' + file)).tasks) tasks[String(task.id)] = task;
}
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
for (const entry of evidence.placements) {
  const source = path.posix.join(path.posix.dirname(entry.sourceFile), entry.sourceEntry);
  const text = read(source).replace(/\r\n/g, '\n');
  assert(text.includes(entry.legacyScript), entry.npcName + ': 原始 NPC 脚本已变化，应重新核对出现条件');
  assert.equal(hash(entry.legacyScript), entry.scriptDigest);
  assert.equal(hash(fs.readFileSync(path.join(root, entry.sourceSwf))), entry.swfSha256);
  const placement = definition.placements[entry.placementId];
  assert.equal(definition.locations[placement.locationId].sceneName, entry.sceneKey);
  assert.deepEqual(placement.presenceWhen, entry.presenceWhen);
  assert.equal(placement.legacyWorldAdapter, true);
}

function facts(main = 600, egg = 20, finished = []) {
  const taskFacts = {};
  for (const id of Object.keys(tasks)) taskFacts[id] = { active: true, deliverable: true, finished: finished.includes(id) ? 1 : 0, available: false };
  return { chains: { 主线: main, 彩蛋: egg, 支线: 100, 大学: 20, 后勤: 20, 将军: 20, 废城: 20, 引导: 20, 异形: 20 },
    tasks: taskFacts, activeOrder: Object.keys(tasks), infrastructure: { 自行车: 1, 摩托车: 1, 越野车: 1 },
    flags: {}, scene: { stageFlag: '地图-联合大学', frameLabel: '外部地图', mapFrame: '基地1层', inCombat: true },
    navigation: { reason: 'stage_run_active' } };
}
const cases = [
  { name: 'camp-locked', facts: facts(0, 0), location: 'survivor_camp', enterable: false },
  { name: 'camp-unlocked', facts: facts(1, 0), location: 'survivor_camp', enterable: true },
  { name: 'egg-locked', facts: facts(600, 0), location: 'easter_egg', enterable: false },
  { name: 'egg-unlocked', facts: facts(600, 1), location: 'easter_egg', enterable: true },
  { name: 'egg-private-delivery', facts: facts(600, 4), npc: '文天', location: 'easter_egg' },
  { name: 'egg-private-delivery-locked', facts: facts(600, 0), npc: '文天', location: 'easter_egg', returnNavigable: false },
  { name: 'demon-camp', facts: facts(77, 20, ['1000081']), npc: '人修罗', location: 'survivor_camp' },
  { name: 'demon-egg', facts: facts(77, 20, ['1000081', '1000082']), npc: '人修罗', location: 'easter_egg' },
  { name: 'demon-absent', facts: facts(76, 20, ['1000081', '1000082']), npc: '人修罗', absent: true }
];
for (const entry of evidence.placements) {
  const min = entry.legacyScript.match(/(?:任务需求\s*=\s*|主线任务进度\s*<\s*)(\d+)/);
  if (min && entry.npcName !== '人修罗') {
    cases.push({ name: entry.npcName + '-below', facts: facts(Number(min[1]) - 1), placement: entry.placementId, present: false });
    cases.push({ name: entry.npcName + '-at', facts: facts(Number(min[1])), placement: entry.placementId, present: true });
  }
}
for (const [name, egg, present] of [['神秘男人', 0, true], ['神秘男人', 1, false], ['heeho君', 3, false], ['heeho君', 4, true]]) {
  cases.push({ name: name + '-' + egg, facts: facts(600, egg), placement: evidence.placements.find(p => p.npcName === name).placementId, present });
}
const projected = domain.invoke('project', root, { definition, tasks, facts: cases.map(c => c.facts) });
for (let i = 0; i < cases.length; i++) {
  const c = cases[i], result = projected.results[i];
  if ('enterable' in c) assert.equal(result.locations[c.location].enterable, c.enterable, c.name);
  if ('present' in c) assert.equal(result.placements[c.placement].present, c.present, c.name);
  if (c.npc) {
    const id = Object.keys(tasks).find(id => tasks[id].finish_npc === c.npc);
    assert(id, c.name + ': task must exist');
    const endpoint = result.taskEndpoints[id].finish;
    if (c.absent) assert.equal(endpoint.resolved, false, c.name);
    else { assert.equal(endpoint.locationId, c.location, c.name); assert.equal(endpoint.returnNavigable, c.returnNavigable ?? true, c.name); }
  }
}
const runtime = domain.validateContent(root);
assert.equal(runtime.success, true);
assert.equal(runtime.unreadyWorldBindings.length, 0);
const names = new Set(Object.values(definition.npcs).flatMap(npc => npc.runtimeNames.concat(npc.aliases)).map(n => n.toLowerCase()));
const missing = Object.values(tasks).filter(task => !names.has(String(task.finish_npc || '').toLowerCase()));
assert(missing.every(task => evidence.unresolvedNpcNames.includes(task.finish_npc)));
for (const scene of evidence.deferredSceneNames) assert(!Object.values(definition.locations).some(l => l.sceneName === scene));
console.log(JSON.stringify({ success: true, cases: cases.length, locations: runtime.locations, tasks: runtime.tasks,
  mappedFinishNpcNames: Object.keys(tasks).length - missing.length,
  unresolved: missing.map(task => ({ taskId: task.id, npc: task.finish_npc })),
  evidence: 'static_source_and_production_projection; physical_journeys_pending' }, null, 2));
