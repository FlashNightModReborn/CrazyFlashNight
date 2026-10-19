#!/usr/bin/env node
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert/strict');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const xml = read('CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml');
const guardSource = read('scripts/类定义/org/flashNight/arki/scene/SceneTransitionGuard.as');
const flowSource = read('scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as');
const frames = [...xml.matchAll(/<DOMFrame\b([^>]*)>([\s\S]*?)<\/DOMFrame>/g)];
const label = frames.find(frame => /\bname="外部地图"/.test(frame[1]));
const placement = frames.find(frame => /\bname="gameworld层级定位器"/.test(frame[2])
    && frame[2].includes('_root.加载共享场景(_root.关卡标志)'));
assert.ok(label && placement, 'external entry label and authored scene locator must exist');
const index = frame => Number(frame[1].match(/\bindex="(\d+)"/)[1]);
const displayFrame = index(placement) + 1;
assert.equal(index(label), index(placement),
    'first external entry must land on the authored scene locator, not an empty loading span');
let checks = 1;

// These production functions use the AS2/JavaScript shared control-flow subset.
// This fixture cannot prove MovieClip load dispatch or an actual Flash scene.
function body(source, signature) {
    const start = source.indexOf(signature);
    assert.ok(start >= 0, 'missing production function: ' + signature);
    const open = source.indexOf('{', start);
    let depth = 1, end = open + 1;
    while (depth && end < source.length) {
        if (source[end] === '{') depth++;
        if (source[end] === '}') depth--;
        end++;
    }
    assert.equal(depth, 0, 'unclosed production function: ' + signature);
    return source.slice(open + 1, end - 1).replace(/:\s*(?:String|Object|Number|Boolean|Void|MovieClip)\b/g, '');
}
const functions = ['rememberBaseSceneFrame', 'rememberSharedSceneFrame',
    'observedBaseSceneFrame', 'observedSharedSceneFrame'];
function fixture(options = {}) {
    const calls = { jumps: [], mounts: [], survivalStops: 0, survivalStarts: 0, navigation: 0, watches: 0 };
    const run = options.lee ? { bookId: 'lee-trial', outcome: 'active', slot: 'test-only' } : {};
    const sceneRoot = { _currentframe: options.frame || displayFrame, _saveExt: { bookRun: run }, savePath: 'test-only',
        gameworld: options.world, __externalSceneFrame: options.observedExternal,
        __baseSceneFrame: options.observedBase, __leeBattleSceneFrame: options.observedBattle,
        soundEffectManager: { notifyLeaveBattle() {} },
        加载共享场景: name => calls.mounts.push(name),
        生存模式关闭: () => calls.survivalStops++, 开启生存模式: () => calls.survivalStarts++ };
    sceneRoot.gotoAndPlay = target => {
        calls.jumps.push(target);
        if (typeof target === 'number') sceneRoot._currentframe = target;
        else if (target === '外部地图') sceneRoot._currentframe = index(label) + 1;
    };
    const guard = { noteExternalNavigation() {}, beginNavigation: () => calls.navigation++, watchLeeStageNavigation: () => calls.watches++ };
    const context = vm.createContext({ _root: sceneRoot,
        WeatherSystem: { getInstance: () => ({ getEnvConfig: () => ({
            hasSceneEnv: name => name.startsWith('地图-') || name === '基地门口' }) }) },
        org: { flashNight: { arki: { scene: { SceneTransitionGuard: guard,
            SharedScenePlacement: { retireIdle: () => true }, StageManager: { instance: {} }, StageReturnFlow: { beginSceneLoad: () => options.denied !== true } },
            ui: { BookshelfPanelService: { applyAtSceneBoundary: () => true, takeBoundaryFrame: name => name } } } } } });
    for (const name of functions) {
        vm.runInContext('function ' + name + '(root, ' + (name.startsWith('remember') ? 'scene' : 'targetFrame')
            + '){' + body(guardSource, 'function ' + name + '(') + '\n}', context);
        guard[name] = context[name];
    }
    vm.runInContext('_root.跳转地图 = function(跳转帧, 返回令牌){'
        + body(flowSource, '_root.跳转地图 = function(') + '\n}', context);
    return { root: sceneRoot, guard, calls };
}
let current = fixture({ frame: 12 });
current.root.跳转地图('地图-测试空间');
assert.deepEqual(current.calls.jumps, ['外部地图']); checks++;
assert.equal(current.root._currentframe, displayFrame, 'first visit reaches the actual scene placement'); checks++;
assert.deepEqual(current.calls.mounts, [], 'first visit leaves mounting to the authored load callback'); checks++;

current = fixture({ observedExternal: displayFrame });
current.root.跳转地图('地图-测试空间');
assert.deepEqual(current.calls.mounts, ['地图-测试空间'], 'same-frame return must recreate the cleared world'); checks++;
assert.deepEqual(current.calls.jumps, [], 'same-frame return cannot depend on another locator onLoad'); checks++;
assert.equal(current.calls.survivalStops + current.calls.survivalStarts, 0,
    'an external map must not enter the infinite-battle branch'); checks++;
current = fixture({ observedExternal: displayFrame });
current.root.跳转地图('地图-军阀帐篷');
assert.deepEqual(current.calls.mounts, ['地图-军阀帐篷'], 'external-to-external return preserves its actual destination'); checks++;
current = fixture({ frame: 12, observedExternal: displayFrame });
current.root.跳转地图('地图-测试空间');
assert.deepEqual(current.calls.jumps, [displayFrame], 'a remembered external placement can be revisited from another root frame'); checks++;
assert.deepEqual(current.calls.mounts, [], 'different-frame navigation cannot create a duplicate world'); checks++;

current = fixture({ observedExternal: displayFrame, world: {} });
assert.equal(current.guard.observedSharedSceneFrame(current.root, '外部地图'), 0,
    'a live world never grants a second direct mount'); checks++;
current = fixture();
current.guard.rememberSharedSceneFrame(current.root, '地图-测试空间');
assert.equal(current.root.__externalSceneFrame, displayFrame, 'remember only a frame that actually initialized an external world'); checks++;
current = fixture();
current.guard.rememberSharedSceneFrame(current.root, '基地场景-基地门口');
assert.equal(current.root.__externalSceneFrame, undefined, 'base initialization does not qualify an external frame'); checks++;
current = fixture({ frame: 41, observedBase: 41 });
current.root.跳转地图('基地门口');
assert.deepEqual(current.calls.mounts, ['基地场景-基地门口'], 'base reentry retains the original prefix and route'); checks++;
current = fixture({ observedBattle: displayFrame });
current.root.跳转地图('wuxianguotu_1');
assert.deepEqual(current.calls.jumps, ['wuxianguotu_1'], 'ordinary battle entry retains its original admission route'); checks++;
current = fixture({ observedBattle: displayFrame, lee: true });
current.root.跳转地图('wuxianguotu_1');
assert.deepEqual(current.calls.mounts, ['wuxianguotu_1']); checks++;
assert.equal(current.calls.survivalStops, 1); checks++;
assert.equal(current.calls.survivalStarts, 1); checks++;
current = fixture({ observedExternal: displayFrame, denied: true });
current.root.跳转地图('地图-测试空间');
assert.deepEqual(current.calls.mounts, [], 'denied navigation cannot mount a scene'); checks++;
assert.deepEqual(current.calls.jumps, [], 'denied navigation cannot move the root timeline'); checks++;
assert.equal(current.calls.navigation, 0, 'denied navigation cannot replace the navigation identity'); checks++;

const report = { kind: 'external-scene-production-source-fixture', checks, displayFrame,
    gameE2e: false, slotsTouched: false, requiresPairedMainAndAsLoader: true };
const output = path.join(root, 'tmp/external-scene-entry/source-results.json');
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
console.log('External scene source checks passed: ' + checks + ' (not Flash/game E2E)');
