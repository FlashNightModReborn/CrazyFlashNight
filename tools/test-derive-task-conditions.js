#!/usr/bin/env node
'use strict';

// 任务 conditions 派生校验的持久化正反例矩阵（回归防线）。
// 背景：死锁/可达性校验历经四轮修复（局部规则×2 → 图环检测 → AND-OR 不动点），每轮都
// 由复审击穿前一轮的盲区；且正式数据 conditions=0，常规 `--check` 不会执行这些分支——
// 没有持久化反例时回归完全不可见。本矩阵把四轮全部教训固化为合成夹具。
//
// 用法：node tools/test-derive-task-conditions.js
// 机制：每用例 = 内联合成任务数据 → 写入临时 task-dir → 跑
//       `node tools/derive-task-catalog.js --check --task-dir <tmp>` → 断言 exit code + 报错片段。
// 不触碰 data/task 真实数据。economyCount 白名单解析（SOT=AchievementMetrics.as）不在此测，
// 由 derive-achievement-catalog 的真实数据路径覆盖。
//
// 新增校验规则时同轮补用例（教训：规则没有反例 = 没有验证）。

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const projectRoot = path.resolve(__dirname, '..');
const derive = path.join(__dirname, 'derive-task-catalog.js');

// ── 夹具任务速记 ──
function task(id, chain, extra) {
    const t = { id: id, chain: chain, title: '夹具任务' + id, description: '测试用' };
    if (extra) for (const k in extra) t[k] = extra[k];
    return t;
}
function cp(chain, target, extra) {
    const c = { type: 'chainProgress', params: { chain: chain }, target: target, label: 'x' };
    if (extra) for (const k in extra) c[k] = extra[k];
    return c;
}
function tf(taskId, extra) {
    const c = { type: 'taskFinished', params: { taskId: taskId }, target: 1, label: 'x' };
    if (extra) for (const k in extra) c[k] = extra[k];
    return c;
}

// expect: null = 应通过（exit 0）；字符串 = 应失败且 stderr 含该片段
const CASES = [
    // ── 基础校验（objective-types.js validateCondition） ──
    { name: '无 conditions 基线（应通过）', expect: null,
      tasks: [task(1, 'A#1'), task(2, 'A#2', { get_requirements: [1] })] },
    { name: '未知条件类型', expect: 'unknown condition type',
      tasks: [task(1, 'A#1', { conditions: [{ type: 'noSuchType', params: {}, target: 1, label: 'x' }] })] },
    { name: 'label 缺失', expect: 'label required',
      tasks: [task(1, 'A#1', { conditions: [{ type: 'killTotal', params: {}, target: 5 }] })] },
    { name: 'target=0', expect: 'target must be integer >= 1',
      tasks: [task(1, 'A#1', { conditions: [{ type: 'killTotal', params: {}, target: 0, label: 'x' }] })] },
    { name: 'sinceAccept 用于非单调类型(itemCount)', expect: 'sinceAccept only valid for monotonic',
      tasks: [task(1, 'A#1', { conditions: [{ type: 'itemCount', params: { item: '绷带' }, target: 3, label: 'x', sinceAccept: true }] })] },
    { name: 'sinceAccept killTotal 合法（应通过）', expect: null,
      tasks: [task(1, 'A#1', { conditions: [{ type: 'killTotal', params: {}, target: 50, label: '击杀', sinceAccept: true }] })] },
    // ── 布尔型 target / count（二轮）──
    { name: 'taskFinished target=2（rawOf 返 0/1）', expect: 'taskFinished target must be 1',
      tasks: [task(1, 'A#1', { conditions: [tf(2, { target: 2 })] }), task(2, 'A#2')] },
    { name: 'itemOwned target=2（rawOf 返 0/1）', expect: 'itemOwned target must be 1',
      tasks: [task(1, 'A#1', { conditions: [{ type: 'itemOwned', params: { item: '绷带' }, target: 2, label: 'x' }] })] },
    { name: 'itemOwned count=0（containTaskItems 恒真）', expect: 'params.count must be a number >= 1',
      tasks: [task(1, 'A#1', { conditions: [{ type: 'itemOwned', params: { item: '绷带', count: 0 }, target: 1, label: 'x' }] })] },
    // ── 引用闭包 ──
    { name: 'taskFinished 自引用', expect: 'cannot reference itself',
      tasks: [task(1, 'A#1', { conditions: [tf(1)] })] },
    { name: 'taskFinished 引用缺失任务', expect: 'references missing task id',
      tasks: [task(1, 'A#1', { conditions: [tf(999)] })] },
    { name: 'chainProgress 引用无序号链', expect: 'unknown sequenced chain',
      tasks: [task(1, 'A#1', { conditions: [cp('委托', 1)] }), task(2, '委托')] },
    { name: 'chainProgress target 超链最大 seq', expect: 'exceeds chain',
      tasks: [task(1, 'A#1', { conditions: [cp('B', 99)] }), task(2, 'B#1')] },
    // ── 死锁不动点（三/四轮：缺口、互锁、get_req 介导、级联） ──
    { name: '【缺口】A#1,A#5 链上 A#5 要进度 4（唯一候选=自身）', expect: 'conditions deadlock',
      tasks: [task(1, 'A#1'), task(5, 'A#5', { conditions: [cp('A', 4)] })] },
    { name: '【自链 target=自身 seq 且依赖前序】', expect: 'conditions deadlock',
      tasks: [task(1, 'A#1'), task(2, 'A#2', { get_requirements: [1], conditions: [cp('A', 2)] })] },
    { name: '【跨链互锁】A#1↔B#1 互要对方链进度', expect: 'conditions deadlock',
      tasks: [task(1, 'A#1', { conditions: [cp('B', 1)] }), task(2, 'B#1', { conditions: [cp('A', 1)] })] },
    { name: '【taskFinished 互锁】', expect: 'conditions deadlock',
      tasks: [task(1, 'A#1', { conditions: [tf(2)] }), task(2, 'B#1', { conditions: [tf(1)] })] },
    { name: '【get_req 介导环】A#1 要 B 进度，B#1 接取前置=A#1', expect: 'conditions deadlock',
      tasks: [task(1, 'A#1', { conditions: [cp('B', 1)] }), task(2, 'B#1', { get_requirements: [1] })] },
    { name: '【级联受害】C 前置依赖死锁任务（报级联）', expect: '级联死锁',
      tasks: [task(1, 'A#1', { conditions: [cp('B', 1)] }), task(2, 'B#1', { get_requirements: [1] }), task(3, 'C#1', { get_requirements: [1] })] },
    // ── 运行时语义对齐（四轮误报场景：链序号≠完成顺序，taskAvailable 只查 get_requirements） ──
    { name: '【乱序合法】A#1 要本链进度 2，A#2 独立可先完成（应通过）', expect: null,
      tasks: [task(1, 'A#1', { conditions: [cp('A', 2)] }), task(2, 'A#2')] },
    { name: '【自链回看】A#2 前置 A#1 并要进度 1（应通过）', expect: null,
      tasks: [task(1, 'A#1'), task(2, 'A#2', { get_requirements: [1], conditions: [cp('A', 1)] })] },
    { name: '【单向跨链】B#2 要 A 进度 1，A#1 独立（应通过）', expect: null,
      tasks: [task(1, 'A#1'), task(2, 'B#1'), task(3, 'B#2', { get_requirements: [2], conditions: [cp('A', 1)] })] },
    { name: '【taskFinished 正向引用独立任务】（应通过）', expect: null,
      tasks: [task(1, 'A#1', { conditions: [tf(2)] }), task(2, 'B#1')] }
];

// ── 夹具写盘 + 跑 derive ──
const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-cond-matrix-'));
const textDir = path.join(tmpRoot, 'text');
fs.mkdirSync(textDir, { recursive: true });
fs.writeFileSync(path.join(tmpRoot, 'list.xml'), '<root><task>tasks.json</task></root>', 'utf8');
fs.writeFileSync(path.join(textDir, 'list.xml'), '<root><text>texts.json</text></root>', 'utf8');
fs.writeFileSync(path.join(textDir, 'texts.json'), '{}', 'utf8');

function runCase(c) {
    fs.writeFileSync(path.join(tmpRoot, 'tasks.json'), JSON.stringify({ tasks: c.tasks }, null, 2), 'utf8');
    let res;
    try {
        execFileSync('node', [derive, '--check', '--task-dir', tmpRoot], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], cwd: projectRoot });
        res = { code: 0, out: '' };
    } catch (e) {
        res = { code: e.status, out: String(e.stdout || '') + String(e.stderr || '') };
    }
    if (c.expect === null) {
        return res.code === 0 ? null : ('expected pass, got exit=' + res.code + ': ' + res.out.slice(0, 200));
    }
    if (res.code === 0) return 'expected fail containing "' + c.expect + '", but passed';
    if (res.out.indexOf(c.expect) < 0) return 'fail message mismatch, want "' + c.expect + '", got: ' + res.out.slice(0, 200);
    return null;
}

let failed = 0;
for (let i = 0; i < CASES.length; i += 1) {
    const err = runCase(CASES[i]);
    console.log((err === null ? '  PASS ' : '  FAIL ') + CASES[i].name + (err === null ? '' : '\n        ' + err));
    if (err !== null) failed += 1;
}
fs.rmSync(tmpRoot, { recursive: true, force: true });
console.log('[test-derive-task-conditions] ' + (CASES.length - failed) + '/' + CASES.length + ' passed'
    + (failed > 0 ? ' (failed=' + failed + ')' : ''));
process.exit(failed > 0 ? 1 : 0);
