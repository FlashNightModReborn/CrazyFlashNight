'use strict';
/* U7 地铁线路面板的纯 Node 单测：wire 验证、请求 mux 与关闭语义。 */
const assert = require('assert');
const R = require('../launcher/web/modules/subway-select-runtime.js');
let passed = 0;
function check(value, label) { assert(value, label); passed++; }

function snapshot(overrides) {
    return Object.assign({
        v: 1, operation: 'snapshot', success: true,
        progress: { main: 50, egg: 4 },
        stations: [
            { id: '总备处站', name: '总备处站', frame: 4 },
            { id: '新市场站', name: '新市场站', frame: 3 },
            { id: '自由广场站', name: '自由广场站', frame: 2 },
            { id: '环线东北站', name: '环线东北站', frame: 3 }
        ],
        entries: [
            { id: 'clean_stationA', name: '清理总备处', description: '清理总备处站，尝试搜寻神秘士兵的据点。',
                stageName: '总备处站清理', difficulty: '简单', enterable: true, highlighted: true },
            { id: 'defend_stationC', name: '自由广场防守', description: '',
                stageName: '', difficulty: '', enterable: false, highlighted: false }
        ]
    }, overrides);
}

const state = R.normalizeState(snapshot());
check(state && state.entries.length === 2 && state.stations.length === 4, 'valid snapshot');
check(state.stations.every(s => s.locked === false), 'all four stations unlocked at frame > 1');
check(R.normalizeState(snapshot({
    stations: snapshot().stations.map(s => s.id === '新市场站' ? Object.assign({}, s, { frame: 1 }) : s)
})).stations[1].locked === true, 'frame 1 station projects locked');
for (const defect of [
    s => { s.v = 2; }, s => { s.success = false; }, s => { s.progress.main = -1; },
    s => { s.stations.pop(); }, s => { s.stations[0].frame = 5; },
    s => { s.entries[0].stageName = ''; }, s => { s.entries[0].difficulty = '无尽'; },
    s => { s.entries[0].enterable = 'yes'; }, s => { s.entries.push(s.entries[0]); },
    s => { delete s.entries[0].highlighted; }, s => { s.entries[0].extra = true; }
]) {
    const broken = snapshot(); defect(broken);
    check(!R.normalizeState(broken), 'invalid snapshot refused');
}

const ok = R.normalizeEnter({ v: 1, operation: 'enter', success: true, closePanel: true,
    entryId: 'explore_stationD', stageName: '环线东北站', difficulty: '简单' });
check(ok && ok.entryId === 'explore_stationD' && ok.difficulty === '简单', 'valid enter success');
check(R.normalizeEnter({ v: 1, operation: 'enter', success: false, error: 'locked' }).error === 'locked',
    'definitive locked passes');
for (const broken of [
    { v: 1, operation: 'enter', success: true, closePanel: false, entryId: 'explore_stationD', stageName: '环线东北站', difficulty: '简单' },
    { v: 1, operation: 'enter', success: true, closePanel: true, entryId: 'fly_stationX', stageName: '环线东北站', difficulty: '简单' },
    { v: 1, operation: 'enter', success: false, error: 'invented_error' },
    { v: 1, operation: 'snapshot', success: true }
]) check(!R.normalizeEnter(broken), 'invalid enter response refused');

// RequestMux: snapshot/enter 只发规定 envelope，回包按 instance+callId 精确匹配。
const sent = [];
let registered = null;
const router = { register: handler => { registered = handler; return () => {}; } };
const mux = new R.RequestMux({ send: message => { sent.push(message); return true; }, panelInstanceId: 'subway.panel.1', router });
let answered = null;
mux.request('snapshot', { v: 1 }, result => { answered = result; });
check(sent.length === 1 && sent[0].type === 'panel' && sent[0].panel === 'subway' && sent[0].domain === 'subway'
    && sent[0].cmd === 'snapshot' && sent[0].panelInstanceId === 'subway.panel.1', 'snapshot envelope');
check(mux.request('peek', { v: 1 }, () => {}) === null && sent.length === 1, 'unknown cmd never sends');
const callId = sent[0].callId;
registered.handleResponse({ type: 'panel_resp', panel: 'subway', domain: 'subway', cmd: 'snapshot',
    callId: callId, panelInstanceId: 'other.instance', success: true });
check(answered === null, 'foreign instance response ignored');
registered.handleResponse({ type: 'panel_resp', panel: 'subway', domain: 'subway', cmd: 'snapshot',
    callId: callId, panelInstanceId: 'subway.panel.1', success: true });
check(answered && answered.success === true, 'exact instance response delivered');
mux.destroy();
console.log('test-subway-select-runtime: ' + passed + ' checks passed');
