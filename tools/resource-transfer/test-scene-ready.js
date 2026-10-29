'use strict';
// Source extraction isolates the notification boundary. Flash integration remains separate.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { createSource } = require('../player-stat-refresh/source');
const root = path.resolve(__dirname, '../..');
const args = process.argv.slice(2);
const option = (name, fallback) => args.find(x => x.startsWith(name + '='))?.slice(name.length + 1) || fallback;
const source = createSource(option('--source', root));
const className = option('--class', 'PlayerSceneLifecycle');
const file = `scripts/类定义/org/flashNight/arki/scene/${className}.as`;
const numberSource = createSource(root);
const resource = numberSource.methods('scripts/类定义/org/flashNight/arki/unit/Action/Regeneration/ResourceNumber.as',
    ['finite', 'nonnegative', 'positive', 'canPayMp', 'payMp'], { _root: {}, reject() {} });
const cases = [];
function fixture() {
    const state = { current: true, published: 0, faults: [] };
    const gate = {};
    const actor = { hp: 80, hp满血值: 100, mp: 20, mp满血值: 30 };
    const spawn = { hero: true, kind: 'player', resourcesReady: true, gate, finalHp: 80, finalMp: 20 };
    actor.__playerSceneSpawn = actor.__resourceSpawn = spawn;
    const notify = source.fn(file, 'function actorReady(', {
        owns: () => state.current,
        failInitialization: (g, reason) => { g.failed = true; },
        publishReady: () => { state.published++; },
        ResourceNumber: { ...resource, reject(target, reason) { state.faults.push(reason); } }
    });
    return { state, gate, actor, spawn, notify: () => notify(actor) };
}
function check(name, fn) {
    try { fn(); cases.push({ name, passed: true }); }
    catch (error) { cases.push({ name, passed: false, error: String(error.message) }); }
}
for (const [name, hp, mp] of [['damage', 60, 20], ['heal', 90, 20], ['mp_zero', 80, 0], ['overflow', 120, 40]]) {
    check('legitimate_change_' + name, () => {
        const f = fixture(); f.actor.hp = hp; f.actor.mp = mp; f.notify();
        assert.equal(f.state.published, 1); assert.equal(f.gate.failed, undefined);
        assert.deepEqual([f.actor.hp, f.actor.mp], [hp, mp]);
    });
}
check('actual_payment_between_settlement_and_notification', () => {
    const f = fixture(); assert.equal(resource.payMp(f.actor, 5), true); f.notify();
    assert.equal(f.state.published, 1); assert.equal(f.actor.mp, 15);
});
for (const [key, value] of [['hp', 0], ['mp', NaN], ['mp', -1], ['hp满血值', Infinity], ['mp满血值', 0]]) {
    check('invalid_current_resource_' + key + '_' + value, () => {
        const f = fixture(); f.actor[key] = value; f.notify();
        assert.equal(f.state.published, 0); assert.equal(f.gate.failed, true);
        assert.equal(f.state.faults.length, 1);
    });
}
check('lee_zero_mp_mode', () => {
    const f = fixture(); f.spawn.kind = 'lee'; f.actor.mp = f.actor.mp满血值 = 0; f.notify();
    assert.equal(f.state.published, 1);
});
check('stale_callback_cannot_publish', () => {
    const f = fixture(); f.state.current = false; f.notify();
    assert.equal(f.state.published, 0); assert.notEqual(f.gate.actorReady, true);
});
check('later_damage_does_not_replay_initial_notification', () => {
    const f = fixture(); f.notify(); f.actor.hp = 10; f.actor.mp = 0; f.notify();
    assert.equal(f.state.published, 1); assert.equal(f.gate.failed, undefined);
});
check('unfinished_resource_tail_cannot_publish', () => {
    const f = fixture(); f.spawn.resourcesReady = false; f.notify();
    assert.equal(f.state.published, 0);
});
const report = { evidenceTier: 'node-source-extraction', cases,
    passed: cases.filter(x => x.passed).length, failed: cases.filter(x => !x.passed).length,
    sourceEvidence: [...source.evidence, ...numberSource.evidence] };
const output = option('--output', null);
if (output) fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ evidenceTier: report.evidenceTier, passed: report.passed, failed: report.failed, output }));
if (report.failed) process.exitCode = 1;
