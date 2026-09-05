'use strict';

const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const {effectiveCodeLines, validateXflCallsite} = require('./check-callsites');
const root = path.resolve(__dirname, '../..');
const manifest = require('./callsites.v1.json');
let passed = 0;
function test(name, run) { run(); passed++; console.log('PASS ' + name); }

const xml = code => '<script><![CDATA[\n' + code + '\n]]></script>';
const strict = {physicalId:'C5.live', line:2, legacyEntry:'apiFlushDurableNow',
  targetApi:'flushDurableNow', reasonId:['manual_save'], dirtyGuard:false};
const request = {physicalId:'E9', line:2, legacyEntry:'apiRequestSave',
  targetApi:'requestSave', reasonId:['ui.inventory_close'], dirtyGuard:true};
const valid = '_root.存档系统.flushDurableNow("manual_save");';
test('普通 strict cut 使用冻结 API 和 reason', () => {
  assert.deepEqual(validateXflCallsite(strict, xml(valid)), []);
});
test('拒绝把手动存档改成 transition（本次发现的回归）', () => {
  const wrong = {...strict, legacyEntry:'apiFlushBeforeTransition'};
  assert(validateXflCallsite(wrong, xml(valid.replace('flushDurableNow', 'flushBeforeTransition'))).length);
});
test('拒绝错误 reason（本次发现的 settings.manual_save）', () => {
  assert(validateXflCallsite(strict, xml(valid.replace('manual_save', 'settings.manual_save'))).length);
});
test('拒绝 strict dirty 早退及返回值消费', () => {
  for (const prefix of ['if (_root.存档系统.dirtyMark) ', 'return ', 'var ok = ']) {
    assert(validateXflCallsite(strict, xml(prefix + valid)).length);
  }
});
test('E1/E9/E10 只能保留原有 dirty guard', () => {
  const call = '_root.存档系统.requestSave("ui.inventory_close");';
  assert.deepEqual(validateXflCallsite(request, xml('if(_root.存档系统.dirtyMark) ' + call)), []);
  assert(validateXflCallsite(request, xml(call)).length);
  assert(validateXflCallsite(request, xml('if(_root.存档系统.hasPendingChanges()) ' + call)).length);
});
test('非脚本 XML 与 XML/AS 注释不能充当调用点', () => {
  const fake = '<!--' + xml(valid) + '-->\n<meta>' + valid + '</meta>\n' + xml('// ' + valid);
  assert.equal([...effectiveCodeLines(fake, true).values()].length, 0);
  assert(validateXflCallsite(strict, '<meta>\n' + valid + '\n</meta>').length);
});
test('脚本同一行重复存盘拒绝，不靠 family 单次命中蒙混过关', () => {
  assert(validateXflCallsite(strict, xml(valid + valid)).length);
});
test('所有当前 XFL 物理点都满足冻结合同', () => {
  const records = manifest.callsites.filter(c => c.layer !== 'scripts');
  assert.equal(records.length, 24);
  for (const record of records) {
    assert.deepEqual(validateXflCallsite(record, fs.readFileSync(path.join(root, record.sourcePath), 'utf8')), [], record.physicalId);
  }
});
test('manifest reason 均由 SaveManager 注册，transition 只允许冻结三条车道', () => {
  const source = fs.readFileSync(path.join(root, 'scripts/类定义/org/flashNight/neur/Server/SaveManager.as'), 'utf8');
  const registry = source.match(/SAVE_REASON_IDS:Array\s*=\s*\[([\s\S]*?)\]/)[1];
  const reasons = new Set([...registry.matchAll(/"([^"]+)"/g)].map(m => m[1]));
  for (const record of manifest.callsites) {
    for (const reason of record.reasonId) {
      if (record.targetApi !== 'markDirty') assert(reasons.has(reason), record.physicalId + ': ' + reason);
    }
  }
  assert.deepEqual(manifest.callsites.filter(c => c.targetApi === 'flushBeforeTransition')
    .map(c => c.callsiteId).sort(), ['A1', 'A6', 'B2']);
});
test('C6 购物车 partial 保存顺序与两个入口保持', () => {
  const record = manifest.callsites.find(c => c.physicalId === 'C6');
  const source = [...effectiveCodeLines(fs.readFileSync(path.join(root, record.sourcePath), 'utf8'), true).values()].join('\n');
  assert.equal((source.match(/_root\.保存购物车\(\)/g) || []).length, 2);
  const close = source.slice(source.indexOf('function 关闭商城()'));
  assert(close.indexOf('_root.保存购物车()') >= 0);
  assert(close.indexOf('_root.保存购物车()') < close.indexOf('_root.存档系统.flushDurableNow("shop_legacy.close")'));
});
test('legacy 嫌疑入口保留 opt-in reason probe，不宣称 dead', () => {
  for (const id of ['E3', 'E11', 'E12']) {
    const record = manifest.callsites.find(c => c.physicalId === id);
    assert.equal(record.liveState, 'suspect_legacy');
    const source = fs.readFileSync(path.join(root, record.sourcePath), 'utf8');
    assert(source.includes('if (_root.__saveApiReasonProbeEnabled === true) trace("[SaveApiReason] ' + id + '|requestSave|' + record.reasonId[0] + '");'));
  }
});

// 直接执行生产 SceneChanged 回调（无 AS2-only 语法），只替换外围宿主。
// 实际 SOL 与 wheel 的物理行为由 SaveManagerTest 的新鲜 CS6 回归负责。
const timerSource = fs.readFileSync(path.join(root, 'scripts/通信/通信_fs_帧计时器.as'), 'utf8');
const hook = timerSource.match(/_root\.帧计时器\.eventBus\.subscribe\("SceneChanged", function\(\) \{[\s\S]*?\}, null\);/)[0];
for (const dirty of [false, true]) for (const outcome of [true, false, 'pending']) {
  test('生产 SceneChanged 顺序 dirty=' + dirty + ' outcome=' + outcome, () => {
    const events = [];
    let pending = true;
    const noop = () => {};
    const context = {
      _root:{存档系统:{dirtyMark:dirty}, 关卡结束界面:{}, server:{isSocketConnected:false},
        帧计时器:{scheduler:{onSceneChanged:noop}, eventBus:{
          subscribe:(event, callback) => callback(), publish:noop}}},
      System:{IME:{setEnabled:noop}}, HitNumberBatchProcessor:{clear:noop},
      FrameBroadcaster:{reset:noop}, RayVfxManager:{reset:noop},
      org:{flashNight:{naki:{Sort:{TimSort:{resetState:noop}}}}},
      SaveManager:{getInstance:() => ({flushDurableNow:reason => {
        assert.equal(reason, 'scene.changed_safety_net');
        events.push('fence start');
        if (outcome === true) pending = false;
        events.push('flush terminal');
        return outcome;
      }})},
      EnhancedCooldownWheel:{I:() => ({deactivateAll:() => {
        events.push('deactivateAll');
        assert.equal(pending, outcome !== true);
      }})}
    };
    vm.runInNewContext(hook, context, {timeout:1000});
    assert.deepEqual(events, ['fence start', 'flush terminal', 'deactivateAll']);
  });
}
console.log('SAVE-API CONTRACTS PASS: ' + passed);
