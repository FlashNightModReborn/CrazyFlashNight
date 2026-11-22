'use strict';

// Exercise the production AS2 frame entry, its actual subscriber and the four-bucket wheel.
// JavaScript supplies the transport, unit dispatchers and other independent frame consumers.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r/g, '');
const classes = 'scripts/类定义/org/flashNight/';
const serverSource = source(classes + 'neur/Server/ServerManager.as');
const wheelSource = source(classes + 'neur/ScheduleTimer/UnitUpdateWheel.as');
const pumpSource = source('scripts/通信/通信_fs_帧计时器.as');
const phoenix = source(classes + 'arki/unit/Action/Huofeng/HuofengReviveShield.as');

function body(sourceText, start, closing) {
    const offset = sourceText.indexOf(start);
    assert.notEqual(offset, -1, start);
    const open = sourceText.indexOf('{', offset);
    const end = sourceText.indexOf(closing, open);
    assert.ok(end > open, start);
    return sourceText.slice(open + 1, end).replace(/:(?:Void|Number|String|MovieClip|Boolean|Object|Array|Error)\b/g, '');
}

// Unqualified instance fields in AS2 resolve against the receiver.
function method(name, args) {
    const code = body(wheelSource, 'function ' + name + '(', '\n    }');
    return Function(...args, 'with (this) {' + code + '\n}');
}
const moveWheel = method('tick', []);
const addUnit = method('add', ['unit']);
const removeUnit = method('remove', ['unit']);
const countUnits = method('getTotalUnitsCount', []);
const resetWheel = method('reset', []);
const wheelSize = Number(wheelSource.match(/WHEEL_SIZE:Number\s*=\s*(\d+)/)[1]);
const frame = Function('with (this) {' +
    body(serverSource, 'public function onEnterFrameHandler()', '\n    }') + '\n}');
const subscriber = Function('frameToken', 'with (this) {' +
    body(pumpSource, 'subscribe("frameUpdate", function(frameToken:Number)', '\n    }, this);') + '\n}');
const guardedShield = Function('_root', 'return class extends class { update(delta) { return delta; } } {' +
    'update(deltaTime) {' + body(phoenix, 'public function update(', '\n    }') + '}}');

function fixture(initialSlot) {
    const wheel = {currentPos:initialSlot, WHEEL_SIZE:wheelSize, slots:[[], [], [], []], unitDict:{},
        slotDict:{}, counter:0, totalUnits:0, processedCount:0, getTotalUnitsCount:countUnits,
        add:addUnit, remove:removeUnit, tick:moveWheel};
    const world = {暂停:false};
    const server = {currentFrame:0, gameFrame:0, gameFrameAdvanced:false, hasSentThisFrame:true, _root:world};
    const totals = {task:0, scene:0, wave:0, stage:0};
    const context = {_root:world, SceneManager:{instance:{update(){ totals.scene++; }}},
        WaveSpawner:{instance:{tick(){ totals.wave++; }}}, StageManager:{instance:{tick(){ totals.stage++; }}},
        org:{flashNight:{neur:{Server:{Issue205SourceProbe:{mark(){}}}},
            arki:{camera:{HorizontalScroller:{observeDriver(){}}}}}}};
    world.server = server;
    world.帧计时器 = {unitUpdateWheel:wheel, taskManager:{updateFrame(token) {
        assert.equal(token, server.currentFrame);
        totals.task++;
        if (context.onTask) context.onTask();
    }}};
    server.eventBus = {publish(name, token) {
        assert.equal(name, 'frameUpdate');
        subscriber.call(context, token);
    }};
    return {world, server, context, totals, wheel, step(){ frame.call(server); }};
}

assert.equal(wheelSize, 4);
for (let initial = 0; initial < wheelSize; initial++) {
    for (let mask = 0; mask < 4096; mask++) {
        const f = fixture(initial);
        let game = 0;
        for (let i = 0; i < 12; i++) {
            const admitted = (mask & (1 << i)) !== 0;
            f.world.暂停 = !admitted;
            if (admitted) game++;
            f.step();
            assert.equal(f.server.currentFrame, i + 1);
            assert.equal(f.server.gameFrame, game);
            assert.equal(f.server.gameFrameAdvanced, admitted);
            assert.equal(f.wheel.currentPos, (initial + game) % wheelSize);
        }
        assert.deepEqual(f.totals, {task:12, scene:12, wave:12, stage:12});
    }
}
console.log('PASS four initial bucket positions x 4096 pause sequences, system consumers continue');

const f = fixture(0);
const fireShield = new (guardedShield(f.world))();
const ticks = [];
f.wheel.add({dispatcher:{publish() { ticks.push([f.server.gameFrame, 4, fireShield.update(4)]); }}});
for (let i = 0; i < 3; i++) f.step();
f.context.onTask = () => { f.world.暂停 = true; };
f.step();
assert.deepEqual(ticks, [[4, 4, false]]);
f.context.onTask = () => { f.world.暂停 = false; };
f.step();
assert.equal(f.server.gameFrame, 4);
assert.equal(f.wheel.currentPos, 0);
delete f.context.onTask;
for (let i = 0; i < 4; i++) f.step();
assert.deepEqual(ticks, [[4, 4, false], [8, 4, 4]]);
console.log('PASS acquire and release after frame entry, including existing Huofeng live guard');

const burst = fixture(2);
const units = [];
const calls = Array(32).fill(0);
burst.world.暂停 = true;
for (let i = 0; i < calls.length; i++) {
    const unit = {dispatcher:{publish(){ calls[i]++; }}};
    units.push(unit);
    burst.wheel.add(unit);
    burst.step();
    assert.equal(burst.wheel.currentPos, 2);
}
for (let i = 0; i < 8; i++) burst.wheel.remove(units[i]);
for (let i = 0; i < 31; i++) burst.step();
assert.equal(burst.wheel.processedCount, 0);
burst.world.暂停 = false;
const loads = [];
for (let i = 0; i < 12; i++) {
    const before = burst.wheel.processedCount;
    burst.step();
    loads.push(burst.wheel.processedCount - before);
}
assert.deepEqual(loads, [0,0,0,24, 0,0,0,24, 0,0,0,24]);
assert.deepEqual(calls, Array(8).fill(0).concat(Array(24).fill(3)));
console.log('PASS 32 paused registrations / 8 removals, 3 resumed cycles: ' + loads.join(','));

const fresh = fixture(3);
delete fresh.world.暂停;
fresh.step();
assert.equal(fresh.server.gameFrame, 1);
fresh.world.暂停 = true;
const oldUnit = {dispatcher:{publish(){ assert.fail('old scene received a unit tick'); }}};
fresh.wheel.add(oldUnit);
resetWheel.call(fresh.wheel);
assert.equal(oldUnit.updateEventComponentID, null);
for (let i = 0; i < 300; i++) fresh.step();
assert.equal(fresh.server.gameFrame, 1);
assert.equal(fresh.wheel.currentPos, 3);
fresh.world.暂停 = false;
fresh.step();
assert.equal(fresh.wheel.currentPos, 0);
assert.equal(fresh.server.gameFrame, 2);
const initialization = serverSource.slice(serverSource.indexOf('public function ServerManager()'),
    serverSource.indexOf('initFrameClip();'));
assert.match(initialization, /\bgameFrame\s*=\s*0\s*;/);
assert.match(initialization, /\bgameFrameAdvanced\s*=\s*false\s*;/);
console.log('PASS startup before PauseManager installation and scene reset during a 300-frame pause');
