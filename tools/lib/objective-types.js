'use strict';

// objective.type 枚举单源（成就 + 任务 conditions 共用；设计：docs/任务成就-判定层共享-设计-2026-06-11.md §2）。
// AS2 端实现 = org/flashNight/arki/achievement/ObjectiveEvaluator.rawOf 的类型分发，两处必须同集；
// derive-achievement-catalog.js 与 derive-task-catalog.js 都从本模块取枚举，禁止各自维护副本。
// killByType 为后续轮占位（成就 A 轮设计 §1.3），勿提前加入。
const OBJECTIVE_TYPES = {
    infraLevel: true,
    infraBuiltCount: true,
    killTotal: true,
    taskFinished: true,
    chainProgress: true,
    skillLevel: true,
    itemOwned: true,
    economyCount: true,
    itemCount: true       // 任务条件轮新增：ItemUtil.getTotal 实数计数（itemOwned 是 0/1，无法做进度条）
};

// sinceAccept（任务接取后窗口计数）只对【单调递增】指标有意义：
// 非单调指标（物品可消耗、等级理论可变）减基线会出现负数/语义混乱 → derive 校验直接拒绝。
const MONOTONIC_TYPES = {
    killTotal: true,
    economyCount: true
};

// 任务 conditions 条目校验（derive-task-catalog.js build gate 调用）。
// 形状：{ type, params, target, label, sinceAccept? }
//   - label 必填：面板进度行直接显示写手文案，避免 AS2 端模板代码与数据漂移。
//   - economyCounters：从 AchievementMetrics.as VALID 块解析出的白名单（economyCount 必须命中）。
function validateCondition(cond, ctx, fail, economyCounters) {
    if (cond == null || typeof cond !== 'object' || Array.isArray(cond)) fail(ctx + ': condition must be an object');
    if (OBJECTIVE_TYPES[cond.type] !== true) fail(ctx + ': unknown condition type "' + cond.type + '"');
    const target = Number(cond.target);
    if (isNaN(target) || target < 1 || Math.floor(target) !== target) fail(ctx + ': target must be integer >= 1, got "' + cond.target + '"');
    if (typeof cond.label !== 'string' || cond.label.trim() === '') fail(ctx + ': label required (panel progress row text)');
    if (cond.sinceAccept !== undefined) {
        if (cond.sinceAccept !== true) fail(ctx + ': sinceAccept must be literal true when present');
        if (MONOTONIC_TYPES[cond.type] !== true) fail(ctx + ': sinceAccept only valid for monotonic types (killTotal/economyCount), not "' + cond.type + '"');
    }
    const p = (cond.params != null && typeof cond.params === 'object') ? cond.params : {};
    switch (cond.type) {
        case 'infraLevel':
            if (typeof p.name !== 'string' || !p.name) fail(ctx + ': infraLevel params.name required');
            break;
        case 'infraBuiltCount':
        case 'killTotal':
            break; // 无必填 params
        case 'taskFinished':
            if (p.taskId === undefined || p.taskId === null || p.taskId === '') fail(ctx + ': taskFinished params.taskId required');
            // rawOf 对 taskFinished 显式返 0/1 布尔（完成次数不外露），target>1 = 永不可达静默上架
            if (target !== 1) fail(ctx + ': taskFinished target must be 1 (boolean-type, rawOf returns 0/1)');
            break;
        case 'chainProgress':
            if (typeof p.chain !== 'string' || !p.chain) fail(ctx + ': chainProgress params.chain required');
            break;
        case 'skillLevel':
            if (typeof p.skill !== 'string' || !p.skill) fail(ctx + ': skillLevel params.skill required');
            break;
        case 'itemOwned':
            if (typeof p.item !== 'string' || !p.item) fail(ctx + ': itemOwned params.item required');
            // rawOf 对 itemOwned 返 0/1 布尔（进度条用 itemCount），target>1 = 永不可达
            if (target !== 1) fail(ctx + ': itemOwned target must be 1 (boolean-type; use itemCount for progress)');
            // count<1 时 containTaskItems("item#0") 恒真 = 条件直接错误达成（与成就 validateObjective 同规）
            if (p.count !== undefined && (typeof p.count !== 'number' || isNaN(p.count) || p.count < 1)) {
                fail(ctx + ': itemOwned params.count must be a number >= 1 when present');
            }
            break;
        case 'itemCount':
            if (typeof p.item !== 'string' || !p.item) fail(ctx + ': itemCount params.item required');
            break;
        case 'economyCount':
            if (typeof p.counter !== 'string' || !p.counter) fail(ctx + ': economyCount params.counter required');
            if (economyCounters && economyCounters[p.counter] !== true) {
                fail(ctx + ': economyCount counter "' + p.counter + '" not in AchievementMetrics VALID whitelist');
            }
            break;
        default:
            fail(ctx + ': no params validation for type "' + cond.type + '" (add to objective-types.js)');
    }
}

// economyCount 白名单解析（与 derive-achievement-catalog.js loadValidCounters 同正则同 SOT=
// AchievementMetrics.as buildValid 块；两处解析器都对解析失败硬 fail，漂移即红）。
function parseEconomyWhitelist(metricsFilePath, fail) {
    const fs = require('fs');
    let raw;
    try {
        raw = fs.readFileSync(metricsFilePath, 'utf8');
    } catch (e) {
        fail('cannot read AchievementMetrics.as (economyCount 白名单单源): ' + e.message);
    }
    raw = raw.replace(/^﻿/, '');
    const block = raw.match(/function\s+buildValid\s*\(\s*\)\s*:\s*Object\s*\{([\s\S]*?)return\s+v\s*;/);
    if (!block) fail('AchievementMetrics.as: cannot locate buildValid() body (白名单解析失败)');
    const keys = {};
    const re = /v\["([^"]+)"\]\s*=\s*true\s*;/g;
    let m;
    let count = 0;
    while ((m = re.exec(block[1])) !== null) {
        keys[m[1]] = true;
        count += 1;
    }
    if (count === 0) fail('AchievementMetrics.as: VALID key set is empty');
    return keys;
}

module.exports = { OBJECTIVE_TYPES, MONOTONIC_TYPES, validateCondition, parseEconomyWhitelist };
