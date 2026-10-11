#!/usr/bin/env node
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert/strict');
const root = path.resolve(__dirname, '..');
const fadeXml = fs.readFileSync(path.join(root, 'CRAZYFLASHER7MercenaryEmpire/LIBRARY/sprite/淡出动画.xml'), 'utf8');
const runSource = fs.readFileSync(path.join(root, 'scripts/类定义/org/flashNight/arki/scene/StageRunSession.as'), 'utf8');
const start = runSource.indexOf('private static function getStageStartBlockReasonIgnoringReservation(coveredBookEntry:Boolean):String');
const end = runSource.indexOf('private static function isRunTerminal()', start);
assert.ok(start >= 0 && end > start, 'production admission function must exist');
const admission = runSource.slice(start, end);
const body = admission.slice(admission.indexOf('{') + 1, admission.lastIndexOf('}'));
const frames = [...fadeXml.matchAll(/<DOMFrame\b([^>]*)>([\s\S]*?)<\/DOMFrame>/g)];
const frame17 = frames.find(m => /\bindex="16"/.test(m[1]) && m[2].includes('<Actionscript>'));
assert.ok(frame17, 'production fade frame 17 must exist');
const script = frame17[2].match(/<script><!\[CDATA\[([\s\S]*?)\]\]><\/script>/)[1];
let saves = [], initialization = [];
const fade = { __returnFadeActive: true };
const context = vm.createContext({
    fade, _root: { 淡出动画: fade, 存档系统: { dirtyMark: false, requestSave: reason => saves.push(reason) },
        完成Web场景初始化: current => initialization.push({sameFade:current===fade,saves:saves.length,active:current.__returnFadeActive}) },
    _returnAttempt: null, _run: null, _returnRequested: false, _preparedInventory: null,
    LootContainerService: { hasStageSettlementPending: () => false },
    hasPersistedSettlementPending: () => false, isRunTerminal: () => false
});
// These two production bodies use the shared Boolean/control-flow subset only.
// This source harness complements the real AVM1 suite; it is not Flash/game E2E.
vm.runInContext('function admission(coveredBookEntry){' + body + '\n}', context);
const reason = coveredBookEntry => {
    context.coveredBookEntryFixture = coveredBookEntry;
    return vm.runInContext('admission(coveredBookEntryFixture)', context);
};
const runFrame = () => vm.runInContext('(function(){' + script + '\n}).call(fade)', context);
let checks = 0;
assert.equal(reason(), 'scene_transition'); checks++;
runFrame();
assert.equal(fade.__returnFadeActive, false, 'frame 17 must release legacy stage admission before SceneReady'); checks++;
assert.equal(reason(), '', 'first substage must be allowed to initialize beneath the Web curtain'); checks++;
assert.deepEqual(saves, [], 'clean save guard remains unchanged'); checks++;
context._root.存档系统.dirtyMark = true; fade.__returnFadeActive = true; runFrame();
assert.deepEqual(saves, ['ui.fade_out'], 'dirty guard still delegates to the original save authority'); checks++;
assert.deepEqual(initialization, [{sameFade:true,saves:0,active:false},{sameFade:true,saves:1,active:false}],
    'blank-frame advancement is requested only after legacy admission release and save guard'); checks++;
context._returnAttempt = {}; assert.equal(reason(), 'scene_transition'); checks++;
context._returnAttempt = null; context._run = {}; assert.equal(reason(), 'stage_run_active'); checks++;
context._run = null; context._preparedInventory = {}; assert.equal(reason(), 'pending_stage_settlement'); checks++;
context._preparedInventory = null; context._root.当前为战斗地图 = true; assert.equal(reason(), 'battle_map'); checks++;
context._root.当前为战斗地图 = false;
// A covered book entry may pass only the visual curtain. It must still respect
// return, run, settlement, calibration and battle-map admission authorities.
// This does not exercise the separate reservation/entry-token authorization.
for (const visualGuard of ['fade', 'scene']) {
    fade.__returnFadeActive = visualGuard === 'fade';
    context._root.场景转换中 = visualGuard === 'scene';
    for (const covered of [undefined, false, 1, 'true']) {
        assert.equal(reason(covered), 'scene_transition', visualGuard + ' requires explicit covered-entry authority'); checks++;
    }
    assert.equal(reason(true), '', visualGuard + ' permits a covered entry'); checks++;
}
context._returnAttempt = {}; assert.equal(reason(true), 'scene_transition'); checks++;
context._returnAttempt = null; context._run = {}; assert.equal(reason(true), 'stage_run_active'); checks++;
context._returnRequested = true; assert.equal(reason(true), 'pending_stage_settlement'); checks++;
context._run = null; context._returnRequested = false;
context._preparedInventory = {}; assert.equal(reason(true), 'pending_stage_settlement'); checks++;
context._preparedInventory = null;
context.LootContainerService.hasStageSettlementPending = () => true;
assert.equal(reason(true), 'pending_stage_settlement'); checks++;
context.LootContainerService.hasStageSettlementPending = () => false;
context.hasPersistedSettlementPending = () => true;
assert.equal(reason(true), 'pending_stage_settlement'); checks++;
context.hasPersistedSettlementPending = () => false;
context._root.斗兽标定模式 = true; assert.equal(reason(true), 'calibration_active'); checks++;
context._root.斗兽标定模式 = false;
context._root.当前为战斗地图 = true; assert.equal(reason(true), 'battle_map'); checks++;
context._root.当前为战斗地图 = false; context._root.场景转换中 = false;
assert.equal(reason(), '', 'ordinary admission resumes when all authorities are clear'); checks++;
// Run the production delayed-cleanup callback in the same shared control-flow subset.
// Legacy door clips may have no managed Web session; a completed teardown must resume them.
const sceneFlow = fs.readFileSync(path.join(root, 'scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as'), 'utf8');
const retryStart = sceneFlow.indexOf('_root.__安排游戏世界清理重试 = function');
const retryEnd = sceneFlow.indexOf('_root.清除游戏世界组件 = function', retryStart);
assert.ok(retryStart >= 0 && retryEnd > retryStart); checks++;
const retrySource = sceneFlow.slice(retryStart, retryEnd)
    .replace('function(清理请求:Object):Void', 'function(清理请求)')
    .replace('function():Void', 'function()');
function cleanupCase(options = {}) {
    let callback, scheduled = 0, cleared = 0, resumed = 0;
    const ticket = {};
    const retryRoot = { 帧计时器: { 添加单次任务: cb => { callback = cb; scheduled++; } },
        淡出动画: { play: () => resumed++ },
        清除游戏世界组件: actual => { assert.equal(actual, ticket); cleared++; return options.blocked !== true; },
        完成Web清场: options.missing ? undefined : () => options.managed === true };
    const guard = { isCurrent: () => options.stale !== true, ownsFade: () => options.foreign !== true };
    vm.runInNewContext(retrySource, { _root: retryRoot,
        org: { flashNight: { arki: { scene: { SceneTransitionGuard: guard } } } } });
    retryRoot.__安排游戏世界清理重试(ticket);
    if (options.duplicate) retryRoot.__安排游戏世界清理重试(ticket);
    if (options.superseded) retryRoot.__游戏世界清理重试请求 = {};
    callback();
    return { scheduled, cleared, resumed };
}
assert.deepEqual(cleanupCase({ managed: true }), { scheduled: 1, cleared: 1, resumed: 0 },
    'managed cleanup retains its scheduled frame boundary'); checks++;
assert.deepEqual(cleanupCase(), { scheduled: 1, cleared: 1, resumed: 1 },
    'unmanaged cleanup resumes the original legacy timeline'); checks++;
assert.deepEqual(cleanupCase({ missing: true }), { scheduled: 1, cleared: 1, resumed: 1 },
    'legacy cleanup works without a Web facade'); checks++;
assert.deepEqual(cleanupCase({ stale: true }), { scheduled: 1, cleared: 0, resumed: 0 },
    'stale cleanup cannot destroy a world or resume a fade'); checks++;
assert.deepEqual(cleanupCase({ superseded: true }), { scheduled: 1, cleared: 0, resumed: 0 },
    'superseded retry cannot clear the current world'); checks++;
assert.deepEqual(cleanupCase({ foreign: true }), { scheduled: 1, cleared: 1, resumed: 0 },
    'completed teardown cannot resume a foreign fade'); checks++;
assert.deepEqual(cleanupCase({ blocked: true }), { scheduled: 1, cleared: 1, resumed: 0 },
    'blocked teardown keeps the fade stopped'); checks++;
assert.deepEqual(cleanupCase({ managed: true, duplicate: true }), { scheduled: 1, cleared: 1, resumed: 0 },
    'duplicate retry schedules one cleanup and retains managed ownership'); checks++;
const report = { kind: 'production-source-stage-admission-fixture', checks, gameE2e: false, slotsTouched: false };
const output = path.join(root, 'tmp/u12-scene-transition/stage-entry-source-results.json');
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
console.log('Scene transition stage admission checks passed: ' + checks + ' (source fixture only)');
