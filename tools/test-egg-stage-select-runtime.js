'use strict';
/* U7 彩蛋地图选关面板的纯 Node 单测：wire 验证、请求 mux 与门槛投影。 */
const assert = require('assert');
const R = require('../launcher/web/modules/egg-stage-select-runtime.js');
let passed = 0;
function check(value, label) { assert(value, label); passed++; }

function snapshot(overrides) {
    return Object.assign({
        v: 1, operation: 'snapshot', success: true,
        progress: { main: 67, egg: 11 },
        destinations: [
            { id: 'forest_depth', name: '密林深处', stageName: '密林深处', difficulty: '简单',
                unlocked: true, hintLocked: false, lockReason: '' },
            { id: 'machine_zone', name: '机器游荡区', stageName: '机器游荡区', difficulty: '简单',
                unlocked: true, hintLocked: false, lockReason: '' },
            { id: 'forest_center', name: '密林中央', stageName: '密林中央', difficulty: '冒险',
                unlocked: true, hintLocked: false, lockReason: '' }
        ]
    }, overrides);
}

const state = R.normalizeState(snapshot());
check(state && state.destinations.length === 3, 'valid snapshot');
const locked = snapshot();
locked.destinations[2] = Object.assign({}, locked.destinations[2],
    { unlocked: false, hintLocked: true, lockReason: '彩蛋进度达到 11 解锁' });
check(R.normalizeState(locked).destinations[2].lockReason === '彩蛋进度达到 11 解锁', 'locked projection keeps reason');
for (const defect of [
    s => { s.destinations.pop(); }, s => { s.destinations[0].unlocked = 'yes'; },
    s => { s.destinations[0].lockReason = '彩蛋'; }, // unlocked 必须为 true 时 reason 为空
    s => { s.destinations[1].difficulty = '无尽'; },
    s => { s.destinations.push({ id: 'candy_land', name: 'x', stageName: 'x', difficulty: '简单', unlocked: false, hintLocked: true, lockReason: 'x' }); },
    s => { s.progress.egg = 1.5; }, s => { delete s.destinations[0].hintLocked; }
]) {
    const broken = snapshot(); defect(broken);
    check(!R.normalizeState(broken), 'invalid snapshot refused');
}

const ok = R.normalizeEnter({ v: 1, operation: 'enter', success: true, closePanel: true,
    destinationId: 'forest_center', stageName: '密林中央', difficulty: '冒险' });
check(ok && ok.destinationId === 'forest_center' && ok.difficulty === '冒险', 'valid enter success keeps fixed difficulty');
check(R.normalizeEnter({ v: 1, operation: 'enter', success: false, error: 'pending_stage_settlement' }).error === 'pending_stage_settlement',
    'definitive settlement refusal passes');
for (const broken of [
    { v: 1, operation: 'enter', success: true, closePanel: true, destinationId: 'forest_center', stageName: '密林中央', difficulty: '无尽' },
    { v: 1, operation: 'enter', success: true, closePanel: true, destinationId: 'candy_land', stageName: '密林中央', difficulty: '冒险' },
    { v: 1, operation: 'enter', success: false, error: 'invented_error' }
]) check(!R.normalizeEnter(broken), 'invalid enter response refused');

const sent = [];
let registered = null;
const router = { register: handler => { registered = handler; return () => {}; } };
const mux = new R.RequestMux({ send: message => { sent.push(message); return true; }, panelInstanceId: 'egg.panel.1', router });
let answered = null;
mux.request('enter', { v: 1, destinationId: 'forest_depth' }, result => { answered = result; });
check(sent.length === 1 && sent[0].panel === 'egg-stage-select' && sent[0].domain === 'egg_stage_select'
    && sent[0].cmd === 'enter' && sent[0].payload.destinationId === 'forest_depth', 'enter envelope');
registered.handleResponse({ type: 'panel_resp', panel: 'egg-stage-select', domain: 'egg_stage_select',
    cmd: 'enter', callId: sent[0].callId, panelInstanceId: 'egg.panel.1',
    v: 1, operation: 'enter', success: true, closePanel: true, destinationId: 'forest_depth', stageName: '密林深处', difficulty: '简单' });
check(answered && answered.success === true, 'exact response delivered');
mux.destroy();
console.log('test-egg-stage-select-runtime: ' + passed + ' checks passed');
