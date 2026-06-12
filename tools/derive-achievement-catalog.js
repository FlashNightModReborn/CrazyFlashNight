#!/usr/bin/env node
'use strict';

// 从 data/achievement/*.json（成就权威源，AS2 AchievementDataLoader 也读它）派生 web 成就 tab
// 直读的静态目录 achievement-catalog.json。对标 tools/derive-task-catalog.js（build.ps1 Step 1f）。
// 设计：docs/成就系统-A轮-设计-2026-06-10.md §5。
//
// 校验清单（失败 exit 1，build gate 拦截）：
//   ① BOM 安全 readJson + manifest 解析（data/achievement/list.xml <achievement> 标签）
//   ② 全局 dup-id；与任务 id 空间重叠仅告警（两域命名空间独立，撞号只影响人读）
//   ③ category "链名#序号" 必填 + 序号数字 + 同类 dup-seq
//   ④ objective.type 枚举白名单 + per-type 必填 params；economyCount.counter 直接正则解析
//      AchievementMetrics.as 的 VALID 键集为唯一权威（解析失败/键集为空 → exit 1；
//      漂移后果 = record 静默丢弃 → 成就永久 0 进度无报错，故单源是硬要求）
//   ⑤ 跨域闭包：taskFinished.taskId 必须存在于 data/task 合并任务集；
//      chainProgress.chain 链存在且 target ≤ 该链最大 seq（超界 = 永不可达成静默上架）
//   ⑥ claim.mode ∈ {remote}（A 轮唯一合法值；auto/npc 留枚举注释位不实现）；
//      条目含 finish_remote 字段即 fail（成就域单一写法，防 AS2 raw / web catalog 双权威分叉）
//   ⑦ title/description 非空且禁 '$' 前缀（成就文案字面量直写，不走 task_texts 间接层）
//   ⑧ rewards "名#数" 可解析、数量>0、单条禁同名重复（ItemUtil.require 覆盖非累加）、
//      黑名单 {经验值}（acquire 触发 _root.主角是否升级 升级弹窗链，ItemUtil.as:417-419；
//      解禁 = 删 REWARD_BLACKLIST 条目，即显式决策点）
//
// hidden 条目脱敏输出（防剧透第一层，从源头不泄）：
//   title/description 置 "???"、rewards 置 []、objective 仅保留 {type,target}（params 含
//   物品名/任务 id 等线索，剔除）。明文（含 rewards）仅经 AS2 handleState hiddenReveals
//   对已解锁条目按需回传。
//
// 用法：node tools/derive-achievement-catalog.js [--output <file>] [--check]
//   --check：只解析+校验，不写盘（CI / build gate 干跑）。

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const achievementDir = path.join(projectRoot, 'data', 'achievement');
const taskDir = path.join(projectRoot, 'data', 'task');
const metricsFile = path.join(projectRoot, 'scripts', '类定义', 'org', 'flashNight', 'arki', 'achievement', 'AchievementMetrics.as');
const defaultOutput = path.join(projectRoot, 'launcher', 'web', 'modules', 'tasks', 'achievement-catalog.json');

// objective.type 枚举：单源迁移至 tools/lib/objective-types.js（任务 conditions 与成就共享同一枚举，
// 设计：docs/任务成就-判定层共享-设计-2026-06-11.md §2；原 A 轮本地枚举=设计 §1.1）。
// 注意：枚举里的新类型（如 itemCount）若未在下方 switch 加 params 校验会落 default fail——
// 成就域启用新类型必须显式加 case（刻意的双重门，防"枚举放行但语义未评估"静默上架）。
const { OBJECTIVE_TYPES } = require('./lib/objective-types.js');

// rewards 黑名单：经验值 acquire 触发 _root.主角是否升级（ItemUtil.as:417-419），
// 面板遮罩下升级弹窗/特效体验未评估（设计 §1.2）。解禁 = 删此条目（显式决策点）。
const REWARD_BLACKLIST = { '经验值': true };

function fail(msg) {
    console.error('[derive-achievement-catalog] ' + msg);
    process.exit(1);
}

function warn(msg) {
    console.warn('[derive-achievement-catalog] WARN: ' + msg);
}

function parseArgs(argv) {
    const args = { output: defaultOutput, check: false };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--output') { args.output = argv[i + 1] || ''; i += 1; continue; }
        if (arg === '--check') { args.check = true; continue; }
        if (arg === '--help' || arg === '-h') { printHelp(0); return null; }
        printHelp(1, 'unknown arg: ' + arg);
        return null;
    }
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/derive-achievement-catalog.js [--output <file>] [--check]');
    console.error('  --check  parse + validate only, do not write');
    console.error('  default output: ' + defaultOutput);
    process.exit(exitCode);
}

// UTF-8 BOM 安全的 JSON 读取（list.xml 与部分数据文件带 BOM，JSON.parse 不吃 BOM）。
function readJson(file) {
    let raw;
    try {
        raw = fs.readFileSync(file, 'utf8');
    } catch (e) {
        fail('cannot read ' + file + ': ' + e.message);
    }
    raw = raw.replace(/^﻿/, '');
    try {
        return JSON.parse(raw);
    } catch (e) {
        fail('invalid JSON in ' + file + ': ' + e.message);
    }
}

// 解析 list.xml，取出 <tagName>filename</tagName> 列表（顺序保留，镜像 ListLoader）。
function readManifest(listFile, tagName) {
    let raw;
    try {
        raw = fs.readFileSync(listFile, 'utf8');
    } catch (e) {
        fail('cannot read manifest ' + listFile + ': ' + e.message);
    }
    raw = raw.replace(/^﻿/, '');
    const re = new RegExp('<' + tagName + '>\\s*([^<]+?)\\s*</' + tagName + '>', 'g');
    const out = [];
    let m;
    while ((m = re.exec(raw)) !== null) {
        out.push(m[1]);
    }
    if (out.length === 0) fail('manifest ' + listFile + ' has no <' + tagName + '> entries');
    return out;
}

// ④ economyCount 白名单单源：正则解析 AchievementMetrics.as 的 buildValid 函数体。
//    （AS2 类编译器不接受对象字面量字符串键，故 .as 侧用 v["键"] = true; 赋值式构建——本解析与之配套，格式勿改）
function loadValidCounters() {
    let raw;
    try {
        raw = fs.readFileSync(metricsFile, 'utf8');
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

// ⑤ 跨域闭包用任务域索引：合并任务 id 集 + 各有序链的最大 seq。
function loadTaskIndex() {
    const files = readManifest(path.join(taskDir, 'list.xml'), 'task');
    const ids = {};
    const chainMaxSeq = {};
    for (let i = 0; i < files.length; i += 1) {
        const data = readJson(path.join(taskDir, files[i]));
        if (!data || !Array.isArray(data.tasks)) fail(files[i] + ': missing top-level "tasks" array');
        for (let t = 0; t < data.tasks.length; t += 1) {
            const task = data.tasks[t];
            if (task == null || typeof task !== 'object') continue;
            if (task.id !== undefined && task.id !== null) ids[String(task.id)] = true;
            if (typeof task.chain === 'string') {
                const cp = task.chain.split('#');
                if (cp[1] !== undefined && cp[1] !== '') {
                    const seq = Number(cp[1]);
                    if (!isNaN(seq) && (chainMaxSeq[cp[0]] === undefined || seq > chainMaxSeq[cp[0]])) {
                        chainMaxSeq[cp[0]] = seq;
                    }
                }
            }
        }
    }
    return { ids: ids, chainMaxSeq: chainMaxSeq };
}

function loadAchievements() {
    const files = readManifest(path.join(achievementDir, 'list.xml'), 'achievement');
    let merged = [];
    for (let i = 0; i < files.length; i += 1) {
        const data = readJson(path.join(achievementDir, files[i]));
        if (!data || !Array.isArray(data.achievements)) fail(files[i] + ': missing top-level "achievements" array');
        merged = merged.concat(data.achievements);
    }
    return merged;
}

function needNonEmptyString(v, ctx) {
    if (typeof v !== 'string' || v.length === 0) fail(ctx + ' must be a non-empty string');
    return v;
}

// ⑦ 文案字面量直写：非空 + 禁 $ 前缀。
function validateText(v, ctx) {
    needNonEmptyString(v, ctx);
    if (v.charAt(0) === '$') fail(ctx + ' must be a literal (no "$" text-key indirection): "' + v + '"');
    return v;
}

// ⑧ rewards 校验 + "名#数" → [{name,count}]。
function parseRewards(t, ctx) {
    if (!Array.isArray(t.rewards)) fail(ctx + ': rewards must be an array (use [] for none)');
    const out = [];
    const seen = {};
    for (let i = 0; i < t.rewards.length; i += 1) {
        const parts = String(t.rewards[i]).split('#');
        const name = parts[0];
        if (!name) fail(ctx + ': rewards[' + i + '] has empty item name');
        if (REWARD_BLACKLIST[name]) {
            fail(ctx + ': rewards 禁含「' + name + '」（acquire 触发升级弹窗链，ItemUtil.as:417-419；见脚本头注释）');
        }
        const count = parts[1] !== undefined ? Number(parts[1]) : 1;
        if (isNaN(count) || count <= 0) fail(ctx + ': rewards[' + i + '] invalid count: "' + t.rewards[i] + '"');
        if (seen[name]) fail(ctx + ': rewards 同名物品重复「' + name + '」（ItemUtil.require 覆盖非累加，会少发）');
        seen[name] = true;
        out.push({ name: name, count: count });
    }
    return out;
}

// ④/⑤ objective 校验。
function validateObjective(t, ctx, taskIndex, validCounters) {
    const o = t.objective;
    if (o == null || typeof o !== 'object') fail(ctx + ': missing objective object');
    if (OBJECTIVE_TYPES[o.type] !== true) fail(ctx + ': unknown objective.type "' + o.type + '"');
    if (typeof o.target !== 'number' || isNaN(o.target) || o.target < 1) {
        fail(ctx + ': objective.target must be a number >= 1');
    }
    const p = o.params;
    if (p == null || typeof p !== 'object') fail(ctx + ': objective.params required (use {} when empty)');

    switch (o.type) {
        case 'infraLevel':
            needNonEmptyString(p.name, ctx + ': infraLevel params.name');
            break;
        case 'infraBuiltCount':
        case 'killTotal':
            break;
        case 'taskFinished':
            if (p.taskId === undefined || p.taskId === null) fail(ctx + ': taskFinished requires params.taskId');
            if (taskIndex.ids[String(p.taskId)] !== true) {
                fail(ctx + ': taskFinished references missing task id "' + p.taskId + '" (cross-domain closure)');
            }
            if (o.target !== 1) fail(ctx + ': taskFinished target must be 1 (boolean-type objective)');
            break;
        case 'chainProgress':
            needNonEmptyString(p.chain, ctx + ': chainProgress params.chain');
            if (taskIndex.chainMaxSeq[p.chain] === undefined) {
                fail(ctx + ': chainProgress references unknown chain "' + p.chain + '" (cross-domain closure)');
            }
            if (o.target > taskIndex.chainMaxSeq[p.chain]) {
                fail(ctx + ': chainProgress target ' + o.target + ' exceeds chain "' + p.chain
                    + '" max seq ' + taskIndex.chainMaxSeq[p.chain] + ' (unreachable achievement)');
            }
            break;
        case 'skillLevel':
            needNonEmptyString(p.skill, ctx + ': skillLevel params.skill');
            break;
        case 'itemOwned':
            needNonEmptyString(p.item, ctx + ': itemOwned params.item');
            if (p.count !== undefined && (typeof p.count !== 'number' || isNaN(p.count) || p.count < 1)) {
                fail(ctx + ': itemOwned params.count must be a number >= 1 when present');
            }
            if (o.target !== 1) fail(ctx + ': itemOwned target must be 1 (boolean-type objective)');
            break;
        case 'economyCount':
            needNonEmptyString(p.counter, ctx + ': economyCount params.counter');
            if (validCounters[p.counter] !== true) {
                fail(ctx + ': economyCount counter "' + p.counter
                    + '" not in AchievementMetrics.VALID (白名单单源，新键先加 AchievementMetrics.as)');
            }
            break;
        default:
            fail(ctx + ': unhandled objective.type "' + o.type + '"');
    }
}

function buildCatalog(rawAchievements, taskIndex, validCounters) {
    const achievements = {};
    const categoriesSeqMap = {};
    const idSeen = {};

    for (let i = 0; i < rawAchievements.length; i += 1) {
        const t = rawAchievements[i];
        if (t == null || typeof t !== 'object') fail('achievement index ' + i + ' not an object');
        if (typeof t.id !== 'number' || isNaN(t.id)) fail('achievement index ' + i + ' missing numeric id');
        const idKey = String(t.id);
        const ctx = 'achievement ' + idKey;
        if (idSeen[idKey]) fail('duplicate achievement id "' + idKey + '"');
        idSeen[idKey] = true;
        if (taskIndex.ids[idKey] === true) {
            warn(ctx + ' overlaps task id space (两域命名空间独立但撞号易混淆，建议换号段)');
        }

        // ③ category "链名#序号"
        if (typeof t.category !== 'string' || t.category.length === 0) fail(ctx + ': missing category');
        const catParts = t.category.split('#');
        const catName = catParts[0];
        if (!catName) fail(ctx + ': category name empty');
        const seq = Number(catParts[1]);
        if (catParts[1] === undefined || catParts[1] === '' || isNaN(seq)) {
            fail(ctx + ': category seq not a number: "' + t.category + '"');
        }
        if (!categoriesSeqMap[catName]) categoriesSeqMap[catName] = {};
        if (categoriesSeqMap[catName][seq] !== undefined) {
            fail('category "' + catName + '" duplicate seq ' + seq
                + ' (achievement ' + idKey + ' vs ' + categoriesSeqMap[catName][seq] + ')');
        }
        categoriesSeqMap[catName][seq] = t.id;

        // ⑥ claim 单一写法 + finish_remote 禁字段
        if (Object.prototype.hasOwnProperty.call(t, 'finish_remote')) {
            fail(ctx + ': "finish_remote" is a task-domain field; achievements must use claim:{mode:"remote"}');
        }
        if (t.claim == null || typeof t.claim !== 'object' || t.claim.mode !== 'remote') {
            fail(ctx + ': claim.mode must be "remote" (A 轮唯一合法值)');
        }

        const title = validateText(t.title, ctx + '.title');
        const description = validateText(t.description, ctx + '.description');
        const hidden = t.hidden === true;
        const rewards = parseRewards(t, ctx);
        validateObjective(t, ctx, taskIndex, validCounters);

        // hidden 脱敏投影：title/description→"???"、rewards→[]、objective 剔除 params（含物品名/任务 id 线索）。
        achievements[idKey] = {
            id: t.id,
            category: [catName, seq],
            title: hidden ? '???' : title,
            description: hidden ? '???' : description,
            hidden: hidden,
            rewards: hidden ? [] : rewards,
            claimMode: 'remote',
            objective: hidden
                ? { type: t.objective.type, target: t.objective.target }
                : { type: t.objective.type, params: t.objective.params, target: t.objective.target }
        };
    }

    // categories：各类别按 seq 升序的 id 数组（web 页签渲染顺序）。
    const categories = {};
    const catNames = Object.keys(categoriesSeqMap);
    for (let n = 0; n < catNames.length; n += 1) {
        const name = catNames[n];
        const seqMap = categoriesSeqMap[name];
        const seqs = Object.keys(seqMap).map(Number).sort(function (a, b) { return a - b; });
        categories[name] = seqs.map(function (s) { return seqMap[s]; });
    }

    return {
        achievementCount: Object.keys(achievements).length,
        achievements: achievements,
        categories: categories
    };
}

// 稳定子集（仅排除 _generatedAt）用于 unchanged 跳写。必须含 version / achievementCount：
// 否则 schema 升级或条目数变化会被误判 unchanged 而静默跳过刷新（derive-task-catalog 同款教训）。
function stableSubset(payload) {
    return {
        _source: payload._source,
        _note: payload._note,
        version: payload.version,
        achievementCount: payload.achievementCount,
        achievements: payload.achievements,
        categories: payload.categories
    };
}

function tryReadExistingPayload(outputPath) {
    try {
        if (!fs.existsSync(outputPath)) return null;
        return JSON.parse(fs.readFileSync(outputPath, 'utf8').replace(/^﻿/, ''));
    } catch (e) {
        return null;
    }
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;

    const validCounters = loadValidCounters();
    const taskIndex = loadTaskIndex();
    const rawAchievements = loadAchievements();
    const catalog = buildCatalog(rawAchievements, taskIndex, validCounters);

    if (args.check) {
        console.log('[derive-achievement-catalog] check OK: ' + catalog.achievementCount + ' achievements, '
            + Object.keys(catalog.categories).length + ' categories, '
            + Object.keys(validCounters).length + ' valid counters, closure valid.');
        return;
    }

    const newPayload = {
        _generatedAt: new Date().toISOString(),
        _source: 'data/achievement/*.json (per list.xml) + AchievementMetrics.as VALID + data/task closure',
        _note: 'generated by tools/derive-achievement-catalog.js, do not hand-edit; hidden entries desensitized (full text via AS2 hiddenReveals only)',
        version: 1,
        achievementCount: catalog.achievementCount,
        achievements: catalog.achievements,
        categories: catalog.categories
    };

    const outDir = path.dirname(args.output);
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

    const oldPayload = tryReadExistingPayload(args.output);
    if (oldPayload && JSON.stringify(stableSubset(oldPayload)) === JSON.stringify(stableSubset(newPayload))) {
        console.log('[derive-achievement-catalog] unchanged (' + catalog.achievementCount + ' achievements), kept _generatedAt=' + (oldPayload._generatedAt || '<none>'));
        return;
    }

    // 紧凑输出：派生产物只供机器消费（与 task-catalog.json 同口径）。
    fs.writeFileSync(args.output, JSON.stringify(newPayload) + '\n', 'utf8');
    console.log('[derive-achievement-catalog] wrote ' + catalog.achievementCount + ' achievements ('
        + Object.keys(catalog.categories).length + ' categories) → ' + args.output);
}

main();
