'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { eraseTypes, loadFunctions } = require('./as2-source');
const here = path.resolve(__dirname, '..');
const root = { 暂停: false, 帧计时器: { 当前帧数: 0 }, 主角函数: { 清理射击任务() {} }, 技能函数: {} };
root.技能函数.霸体减伤 = (u, value, duration, key) => { u.buffs[key] = value; };
root.技能函数.移除霸体减伤 = (u, key) => { delete u.buffs[key]; };
const context = vm.createContext({ _root: root, Math, Number, String, isNaN, isFinite, length: s => s.length });
const base = fs.readFileSync(path.join(here, 'SoldierAI.as'), 'utf8');
vm.runInContext(eraseTypes(base.slice(0, base.indexOf('soldierClearMovement=function'))), context);
vm.runInContext(eraseTypes(fs.readFileSync(path.join(here, 'SoldierDefense.as'), 'utf8')), context);
loadFunctions(context, path.join(here, 'SoldierAI.as'), [
  'soldierCanShieldGuard', 'soldierSetHP', 'soldierClearMovement', 'soldierCancelAttack', '状态改变', 'soldierRemoveShieldBuff'
]);

function actor(options = {}) {
  const u = {};
  for (const key of Object.keys(context)) {
    if (key.startsWith('soldier') || key === '状态改变') u[key] = typeof context[key] === 'object' && context[key] !== null
      ? JSON.parse(JSON.stringify(context[key])) : context[key];
  }
  Object.assign(u, { _name: 'shield-01', hp满血值: 10000, soldierHP: 10000, soldierPhase: 1,
    状态: '长枪站立', 特种兵防御错峰: false, 特种兵主动架盾: false, buffs: { CF6特种兵持盾: 75 },
    man: { _currentframe: 1 }, damageTakenMultiplier: 0.25, ...options });
  Object.defineProperty(u, 'hp', { get() { return this.soldierHP; }, set(v) { this.soldierSetHP(v); } });
  u.gotoAndStop = function (pose) { this.pose = pose; this.man = { _currentframe: 1 }; };
  u.buffManager = { update() { u.damageTakenMultiplier = 1 - Math.max(0, ...Object.values(u.buffs)) / 100; } };
  u.soldierInitializeDefense();
  return u;
}
function hit(u, loss) { u.hp -= loss; }
function tick(u, frame) { u.soldierClock = frame; root.帧计时器.当前帧数 = frame; u.soldierObserveShieldThreat(); return u.soldierTryShieldGuard(); }
function leaveGuard(u) { u.状态改变('长枪站立'); u.buffManager.update(0); }
const tests = [];
function test(name, run) { run(); tests.push(name); }

test('small isolated hit remains below pressure threshold', () => {
  const u = actor(); hit(u, 50); assert.equal(tick(u, 1), false); assert.equal(u.soldierShieldGuardDamage, 50);
});
test('40 percent lost during charge is remembered and fulfilled at the first safe tick', () => {
  const u = actor({ 状态: '长枪攻击', soldierAttackOwner: { action: 'shoot', charge: true, active: true } });
  hit(u, 4000); assert.equal(u.soldierShieldGuardDamage, 4000); assert.equal(u.soldierShieldGuardPending, true);
  assert.equal(tick(u, 1), false); u.soldierAttackOwner = null; u.状态 = '长枪站立';
  assert.equal(tick(u, 2), true); assert.equal(u.hp, 6000); assert.equal(u.状态, '被击');
});
test('knife pressure is recorded without interrupting the committed attack', () => {
  const u = actor({ 状态: '近战' }); hit(u, 300); assert.equal(tick(u, 1), false);
  u.状态 = '长枪站立'; assert.equal(tick(u, 2), true);
});
test('three small impacts inside the window queue defense', () => {
  const u = actor(); for (const frame of [0, 4, 8]) { u.soldierClock = frame; hit(u, 10); }
  assert.equal(tick(u, 9), true);
});
test('isolated impacts outside the window do not fabricate sustained pressure', () => {
  const u = actor(); for (const frame of [0, 13, 26]) { u.soldierClock = frame; hit(u, 10); }
  assert.equal(tick(u, 27), false); assert.equal(u.soldierShieldGuardHits, 1);
});
test('cooldown pressure survives until the next available guard', () => {
  const u = actor(); u.soldierNextShieldGuardAt = 90; hit(u, 500);
  assert.equal(tick(u, 89), false); assert.equal(tick(u, 90), true);
});
test('ordinary and stationary elite fire yield while mobile attacks retain their lock', () => {
  for (const kind of ['ordinary', 'stand', 'run', 'slide', 'retreat']) {
    const u = actor({ 状态: '长枪攻击', soldierAttackOwner: { action: 'shoot', elite: kind !== 'ordinary', kind, active: true } });
    hit(u, 300); assert.equal(tick(u, 1), kind === 'ordinary' || kind === 'stand', kind);
  }
});
test('guard never resets an existing mandatory ceasefire', () => {
  const u = actor({ soldierNextShootAt: 150 }); hit(u, 300); tick(u, 1); assert.equal(u.soldierNextShootAt, 150);
});
test('steady pose uses the standard strongest-source reduction and exits cleanly', () => {
  const u = actor(); hit(u, 300); tick(u, 1); assert.equal(u.damageTakenMultiplier, 0.25);
  u.soldierGuardPose(u.man, true); assert(Math.abs(u.damageTakenMultiplier - 0.15) < 1e-10);
  root.技能函数.霸体减伤(u, 90, 0, 'other'); u.buffManager.update(); assert(Math.abs(u.damageTakenMultiplier - 0.1) < 1e-10);
  u.soldierGuardPose(u.man, false); assert(Math.abs(u.damageTakenMultiplier - 0.1) < 1e-10);
  delete u.buffs.other; u.buffManager.update(); assert.equal(u.damageTakenMultiplier, 0.25);
  leaveGuard(u); assert.equal(u.soldierShieldGuardActive, false);
});
test('stale body callback cannot apply extra reduction', () => {
  const u = actor(), old = u.man; hit(u, 300); tick(u, 1); u.soldierGuardPose(old, true);
  assert.equal(u.soldierShieldGuardBuffActive, false);
});
test('breaking shield clears requests and every owned reduction source', () => {
  const u = actor(); hit(u, 300); tick(u, 1); u.soldierGuardPose(u.man, true); u.hp = 0; u.buffManager.update();
  assert.equal(u.soldierPhase, 0); assert.equal(u.soldierShieldGuardPending, false);
  assert.equal(u.soldierShieldGuardActive, false); assert.equal(u.damageTakenMultiplier, 1);
  assert.equal(tick(u, 120), false);
});
test('healing clears pressure without refreshing defense cooldown', () => {
  const u = actor({ soldierNextShieldGuardAt: 90 }); hit(u, 300); u.hp = u.hp满血值;
  assert.equal(u.soldierShieldGuardPending, false); assert.equal(u.soldierNextShieldGuardAt, 90);
});
test('nonfinite damage input cannot enter the pressure queue', () => {
  for (const loss of [NaN, Infinity, -Infinity]) {
    const u = actor(); u.soldierRecordShieldPressure(10000, loss); assert.equal(u.soldierShieldGuardDamage, 0);
  }
});
test('airborne, knocked-down and unshielded actors cannot start guarding', () => {
  for (const blocked of [{ 浮空: true }, { 倒地: true }, { soldierPhase: 2 }]) {
    const u = actor(blocked); hit(u, 300); assert.equal(tick(u, 1), false);
  }
});
test('identity staggering is reproducible and varies across a squad', () => {
  const delays = new Set(), rests = new Set();
  for (let i = 0; i < 20; i++) {
    const options = { cf6UnitIdentity: 'CF6-test-' + i, 特种兵防御错峰: true };
    const a = actor(options), b = actor(options); delays.add(a.soldierShieldGuardDelay); rests.add(a.soldierShieldGuardRest);
    assert.equal(a.soldierShieldGuardDelay, b.soldierShieldGuardDelay);
    assert(a.soldierShieldGuardRatio >= 0.02 && a.soldierShieldGuardRatio <= 0.030000001);
  }
  assert.equal(delays.size, 5); assert.equal(rests.size, 7);
});
test('fresh incoming threat can queue proactive defense before any HP loss', () => {
  const u = actor({ 特种兵主动架盾: true, _btCount: 1, _btFrame: 9, _btMinETA: 5 });
  assert.equal(tick(u, 10), true); assert.equal(u.hp, u.hp满血值);
});
test('stale or invalid threat observations do not trigger defense', () => {
  for (const fields of [{ _btFrame: 1 }, { _btMinETA: -1 }, { _btMinETA: NaN }, { _btCount: 0 }]) {
    const u = actor({ 特种兵主动架盾: true, _btCount: 1, _btFrame: 9, _btMinETA: 5, ...fields });
    assert.equal(tick(u, 10), false);
  }
});
if (require.main === module) console.log(JSON.stringify({ evidence: 'source-functions-with-explicit-Flash-stubs', nativeValidated: false,
  passed: tests.length, failed: 0, tests }, null, 2));
module.exports = { actor, hit, tick, leaveGuard, root };
