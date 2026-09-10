'use strict';

// 执行生产入口的函数体，验证资源和播放路由；这不是AVM1或游戏输入实测。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
let passed = 0;
function test(label, fn) { fn(); passed++; console.log('PASS ' + label); }
function read(file) { return fs.readFileSync(path.join(root, file), 'utf8'); }
function extract(source, marker) {
    const begin = source.indexOf(marker);
    assert(begin >= 0, marker);
    const next = source.indexOf('\n_root.', begin + marker.length);
    assert(next > begin, '缺少函数边界');
    const candidate = source.slice(begin + marker.length, next).replace(/\/\*[^]*?\*\//g, '').trim();
    // 仅擦除路由函数现有的AS2类型标注；资源入口本身是共同语法。
    return '(' + candidate.replace(/:(MovieClip|String|Void)\b/g, '').replace(/;$/, '') + ')';
}
const releaseSource = extract(read('scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'), '_root.主角函数.释放主动战技 = ');
function releaseCase({atomic = false, hp = 100, mp = 20, permit = true, accept = true, subweapon = false} = {}) {
    const events = [];
    const state = {calls: 0, subweaponCalls: 0};
    const ability = {
        原子释放: atomic,
        释放许可判定: () => permit,
        释放: actor => {
            state.calls++;
            if (atomic && accept) { actor.hp -= 7; actor.mp -= 3; }
            return accept;
        }
    };
    const unit = {hp, mp, _y: 88, 浮空: true, 主动战技: {兵器: {
        战技函数: ability, 消耗hp: 10, 消耗mp: atomic ? 100 : 5, isSubweaponControl: subweapon
    }}, dispatcher: {publish: (...args) => events.push(args)}};
    const context = vm.createContext({攻击模式: '兵器', _root: {帧计时器: {当前帧数: 17}},
        WeaponSkillInputService: {requestSubweaponControl(actor, frame) {
            assert.equal(actor, unit); assert.equal(frame, 17); state.subweaponCalls++; return true;
        }}});
    state.result = vm.runInContext(releaseSource, context).call(unit);
    return {unit, events, ...state};
}
test('普通战技照常预检和单次扣费', () => {
    const r = releaseCase();
    assert.deepEqual([r.result, r.unit.hp, r.unit.mp, r.calls, r.unit.temp_y], [true, 90, 15, 1, 88]);
    assert.deepEqual(r.events, [['WeaponSkill', '兵器']]);
});
test('普通战技生命或蓝量不足不释放', () => {
    for (const input of [{hp: 10}, {mp: 4}]) {
        const r = releaseCase(input); assert.equal(r.result, false); assert.equal(r.calls, 0); assert.equal(r.events.length, 0);
    }
});
test('许可拒绝不付款也不触发冷却事件', () => {
    for (const atomic of [false, true]) {
        const r = releaseCase({atomic, permit: false});
        assert.deepEqual([r.result, r.unit.hp, r.unit.mp, r.calls, r.events.length], [false, 100, 20, 0, 0]);
    }
});
test('原子战技不受静态蓝费阻挡且不被公共入口重复扣费', () => {
    const r = releaseCase({atomic: true});
    assert.deepEqual([r.result, r.unit.hp, r.unit.mp, r.calls, r.events.length], [true, 93, 17, 1, 1]);
});
test('原子提交拒绝保留资源与冷却', () => {
    const r = releaseCase({atomic: true, accept: false});
    assert.deepEqual([r.result, r.unit.hp, r.unit.mp, r.calls, r.events.length], [false, 100, 20, 1, 0]);
});
test('副武器继续交给独立输入服务', () => {
    const r = releaseCase({subweapon: true, hp: 1, mp: 0});
    assert.deepEqual([r.result, r.subweaponCalls, r.calls, r.events.length], [true, 1, 0, 0]);
});

const routeSource = extract(read('scripts/引擎/引擎_fs_战技路由.as'), '_root.战技路由.战技标签跳转_旧 = ');
function routeCase(soldier, mode, hp = 1) {
    const calls = [];
    const unit = {hp, 兵种: soldier, man: {}, container: {}, 状态改变: state => calls.push(state)};
    const context = vm.createContext({RoutingLifecycle: {
        ensureTempY() {}, preparePoseAndBonus() {}, bindMovement() {}, bindEndCleanup() {}
    }, _root: {战技路由: {
        载入后跳转战技容器(container, actor) { assert.equal(actor, unit); assert.equal(container, unit.container); calls.push('container'); },
        战技man载入后跳转_旧(man, actor) { assert.equal(actor, unit); assert.equal(man, unit.man); calls.push('legacy'); }
    }}});
    vm.runInContext(routeSource, context)(unit, '任意声明战技', mode);
    return calls;
}
test('任意声明战技均能选择容器播放', () => assert.deepEqual(routeCase('旧角色', 'container'), ['战技', 'container']));
test('男主默认容器路由保留', () => assert.deepEqual(routeCase('主角-男'), ['战技', 'container']));
test('旧角色无声明时保持标签路由', () => assert.deepEqual(routeCase('旧角色'), ['战技', 'legacy']));
test('死亡单位不启动战技容器', () => assert.deepEqual(routeCase('主角-男', 'container', 0), ['血腥死']));
console.log(`血浪资源与路由入口 ${passed}/${passed}；Node执行生产函数体，非AVM1输入实测。`);
