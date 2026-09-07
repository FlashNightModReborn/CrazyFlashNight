'use strict';
// Run the real initializer's admission prefix, not a retyped legacy rule.
// Node proves these finite numeric/source paths; CS6 focused + publish remains a separate gate.
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert/strict');
const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root, 'scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as'), 'utf8');
const start = source.indexOf('_root.初始化NPC = function(目标) {');
const end = source.indexOf('    var npcBaseName:String', start);
assert(start >= 0 && end > start, 'actual NPC initializer prefix must be found');
const prefix = source.slice(start, end);
assert.equal((prefix.match(/MapWorldNpcController\.hasPresencePermit\(目标\)/g) || []).length, 2);
assert(prefix.includes('任务需求支线') && prefix.includes('_root.tasks_finished'));
let passed = 0;
function check(name, facts, npc, expected) {
    const target = Object.assign({_visible:true, stop(){ this.stopped = true; }}, npc);
    const sandbox = {_root:facts, org:{flashNight:{arki:{map:{MapWorldNpcController:{
        intercept(value){ return value.intercepted === true; },
        hasPresencePermit(value){ return value.permitted === true; }
    }}}}}};
    vm.runInNewContext(prefix.replace(/:(?:Number|Array|Boolean)\b/g, '') + 'return "initialized";};', sandbox);
    const result = sandbox._root.初始化NPC(target);
    assert.equal(result === 'initialized', expected, name);
    if (!expected && !target.intercepted && !target.NPC初始化完毕) assert.equal(target._visible, false, name + ' hides legacy NPC');
    passed++;
}
check('legacy main requirement preserved', {主线任务进度:2,tasks_finished:{}}, {任务需求:3}, false);
check('legacy no requirement preserved', {主线任务进度:2,tasks_finished:{}}, {}, true);
check('legacy missing task history stays hidden', {主线任务进度:80,tasks_finished:{}}, {任务需求支线:[1000081]}, false);
check('legacy all side tasks must be finished', {主线任务进度:80,tasks_finished:{1000081:1}}, {任务需求支线:[1000081,1000082]}, false);
check('legacy positive completion counts pass', {主线任务进度:80,tasks_finished:{1000081:1,1000082:2}}, {任务需求支线:[1000081,1000082]}, true);
check('legacy invalid string ID retains upstream behavior', {主线任务进度:80,tasks_finished:{}}, {任务需求支线:['invalid']}, true);
check('scoped managed presence does not run a second legacy gate', {主线任务进度:0,tasks_finished:{}}, {permitted:true,任务需求:50,任务需求支线:[1000081]}, true);
check('managed pending interception does not initialize', {主线任务进度:80,tasks_finished:{}}, {intercepted:true}, false);
check('initialized NPC does not initialize twice', {主线任务进度:80,tasks_finished:{}}, {NPC初始化完毕:true}, false);
console.log('NPC upstream compatibility source paths: ' + passed + '/9 passed; no live NPC interaction claimed.');
