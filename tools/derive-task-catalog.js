#!/usr/bin/env node
'use strict';

// 从 data/task/*.json（游戏权威任务源）派生 web 任务面板「事件日志/任务树」(WS6) 直读的
// 静态目录 task-catalog.json。对标 tools/derive-map-catalog.js（build.ps1 Step 1c）：
// 读源 → 校验 → 写派生 JSON，失败 exit 1 在 build 阶段拦截。
//
// 与 map 派生的方向差异：
//   - map 的 SOT 是 web JS（map-panel-data.js）→ 派生 AS2 JSON。
//   - task 的 SOT 是游戏 JSON（data/task/*.json，AS2 也读它）→ 派生 web JSON。
//     因此 web 拿到的是同一源的【只读投影】，不存在 AS2/web 双源漂移（设计 C1）。
//
// 读取（按 manifest，天然不含死数据 mercenary_tasks_old / easteregg_*）：
//   data/task/list.xml       → 各 *_tasks.json 的 .tasks 数组合并
//   data/task/text/list.xml  → 各 *_text(s).json dictMerge → task_texts
//   文本解析镜像 AS2 TaskUtil.getTaskText：'$' 前缀查 task_texts，否则字面量。
//
// 闭包校验器（设计 C2，审计 Phase 1 前置硬门控）：
//   任务的 title/description/get_conversation/finish_conversation 若值以 '$' 开头，
//   该键必须存在于合并后的 task_texts，否则 exit 1（防 $KEY 缺失运行时显示原始键）。
//   外加 dup-id 守卫、chain 序号完整性。
//
// 输出 = launcher/web/modules/tasks/task-catalog.json（设计 §2 形状）。
// 用法：node tools/derive-task-catalog.js [--output <file>] [--check]
//   --check：只解析+校验，不写盘（CI / build gate 干跑）。

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const taskDir = path.join(projectRoot, 'data', 'task');
const textDir = path.join(projectRoot, 'data', 'task', 'text');
const defaultOutput = path.join(projectRoot, 'launcher', 'web', 'modules', 'tasks', 'task-catalog.json');

function fail(msg) {
    console.error('[derive-task-catalog] ' + msg);
    process.exit(1);
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
    console.error('usage: node tools/derive-task-catalog.js [--output <file>] [--check]');
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

// 合并任务源（concatField("tasks")）。
function loadTasks() {
    const files = readManifest(path.join(taskDir, 'list.xml'), 'task');
    let merged = [];
    for (let i = 0; i < files.length; i += 1) {
        const data = readJson(path.join(taskDir, files[i]));
        if (!data || !Array.isArray(data.tasks)) fail(files[i] + ': missing top-level "tasks" array');
        merged = merged.concat(data.tasks);
    }
    return merged;
}

// 合并文本字典（dictMerge，后者覆盖）。
function loadTexts() {
    const files = readManifest(path.join(textDir, 'list.xml'), 'text');
    const dict = {};
    for (let i = 0; i < files.length; i += 1) {
        const data = readJson(path.join(textDir, files[i]));
        if (!data || typeof data !== 'object') fail(files[i] + ': not a text dict');
        const keys = Object.keys(data);
        for (let k = 0; k < keys.length; k += 1) dict[keys[k]] = data[keys[k]];
    }
    return dict;
}

// 解析文本：镜像 TaskUtil.getTaskText。引用 $KEY 但缺键 → 闭包校验失败。
// 返回解析后的值（字符串 / 数组 / undefined）。
function resolveText(rawValue, taskTexts, ctx) {
    if (typeof rawValue !== 'string') return rawValue; // 非字符串（已是数组/缺失）原样返回
    if (rawValue.charAt(0) !== '$') return rawValue;     // 字面量
    if (!Object.prototype.hasOwnProperty.call(taskTexts, rawValue)) {
        fail(ctx + ' references missing text key "' + rawValue + '" (closure check)');
    }
    return taskTexts[rawValue];
}

// "name#count" → { name, count }
function parseNameCount(entry, kind) {
    const parts = String(entry).split('#');
    const o = { name: parts[0], count: parts[1] !== undefined ? Number(parts[1]) : 1 };
    if (kind) o.kind = kind;
    return o;
}

function buildCatalog(rawTasks, taskTexts) {
    const tasks = {};
    const chains = {};            // 有序号链：name → { seq: id }
    const chainsUnsequenced = {}; // 无序号链（委托等）：name → [id...]（遇见序）
    const idSeen = {};

    for (let i = 0; i < rawTasks.length; i += 1) {
        const t = rawTasks[i];
        if (t == null || typeof t !== 'object') fail('task index ' + i + ' not an object');
        if (t.id === undefined || t.id === null) fail('task index ' + i + ' missing id');
        const id = t.id;
        const idKey = String(id);
        if (idSeen[idKey]) fail('duplicate task id "' + idKey + '"');
        idSeen[idKey] = true;

        // chain："链名#序号" 或 "链名"
        if (typeof t.chain !== 'string' || t.chain.length === 0) fail('task ' + idKey + ' missing chain');
        const chainParts = t.chain.split('#');
        const chainName = chainParts[0];
        let seq = null;
        if (chainParts[1] !== undefined && chainParts[1] !== '') {
            seq = Number(chainParts[1]);
            if (isNaN(seq)) fail('task ' + idKey + ' chain seq not a number: "' + t.chain + '"');
        }

        const ctx = 'task ' + idKey;
        const title = resolveText(t.title, taskTexts, ctx + '.title');
        const description = resolveText(t.description, taskTexts, ctx + '.description');
        const getConv = resolveText(t.get_conversation, taskTexts, ctx + '.get_conversation');
        const finishConv = resolveText(t.finish_conversation, taskTexts, ctx + '.finish_conversation');

        // 关卡需求（取首条，镜像 handleDetail）
        let stageReq = null;
        if (Array.isArray(t.finish_requirements) && t.finish_requirements.length > 0) {
            const sp = String(t.finish_requirements[0]).split('#');
            stageReq = { name: sp[0], difficulty: sp[1] !== undefined ? String(sp[1]) : '' };
        }

        // 物品需求
        const itemReqs = [];
        if (Array.isArray(t.finish_submit_items)) {
            for (let s = 0; s < t.finish_submit_items.length; s += 1) itemReqs.push(parseNameCount(t.finish_submit_items[s], 'submit'));
        }
        if (Array.isArray(t.finish_contain_items)) {
            for (let c = 0; c < t.finish_contain_items.length; c += 1) itemReqs.push(parseNameCount(t.finish_contain_items[c], 'contain'));
        }

        // 奖励
        const rewards = [];
        if (Array.isArray(t.rewards)) {
            for (let r = 0; r < t.rewards.length; r += 1) rewards.push(parseNameCount(t.rewards[r]));
        }

        const hasConv = function (v) { return v != null && v.length > 0; };

        tasks[idKey] = {
            id: id,
            chain: [chainName, seq],
            type: chainName,
            title: title != null ? String(title) : '',
            description: description != null ? String(description) : '',
            npcName: t.finish_npc !== undefined ? String(t.finish_npc) : '',
            stageReq: stageReq,
            itemReqs: itemReqs,
            rewards: rewards,
            // req = get_requirements（前置任务 id）：图表视图画前置依赖连线 + 算拓扑深度的边数据。
            // 多数任务 0-1 个前置（实测仅 8 个有 2 个），体积极小。
            req: (Array.isArray(t.get_requirements) ? t.get_requirements.slice() : []),
            hasGetConv: hasConv(getConv),
            hasFinishConv: hasConv(finishConv)
        };

        if (seq !== null) {
            if (!chains[chainName]) chains[chainName] = {};
            if (chains[chainName][seq] !== undefined) {
                fail('chain "' + chainName + '" duplicate seq ' + seq + ' (task ' + idKey + ' vs ' + chains[chainName][seq] + ')');
            }
            chains[chainName][seq] = id;
        } else {
            if (!chainsUnsequenced[chainName]) chainsUnsequenced[chainName] = [];
            chainsUnsequenced[chainName].push(id);
        }
    }

    // 有序号链 → 按 seq 升序的 id 数组（= AS2 task_in_chains_by_sequence 排序后）
    const chainsOrdered = {};
    const chainNames = Object.keys(chains);
    for (let n = 0; n < chainNames.length; n += 1) {
        const name = chainNames[n];
        const seqMap = chains[name];
        const seqs = Object.keys(seqMap).map(Number).sort(function (a, b) { return a - b; });
        chainsOrdered[name] = seqs.map(function (s) { return seqMap[s]; });
    }

    return {
        taskCount: Object.keys(tasks).length,
        tasks: tasks,
        chains: chainsOrdered,
        chainsUnsequenced: chainsUnsequenced
    };
}

// 稳定子集（排除 _generatedAt）用于 unchanged 跳写，避免无意义 mtime/diff churn。
function stableSubset(payload) {
    return {
        _source: payload._source,
        _note: payload._note,
        tasks: payload.tasks,
        chains: payload.chains,
        chainsUnsequenced: payload.chainsUnsequenced
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

    const rawTasks = loadTasks();
    const taskTexts = loadTexts();
    const catalog = buildCatalog(rawTasks, taskTexts);

    if (args.check) {
        console.log('[derive-task-catalog] check OK: ' + catalog.taskCount + ' tasks, '
            + Object.keys(catalog.chains).length + ' sequenced chains, closure valid.');
        return;
    }

    const newPayload = {
        _generatedAt: new Date().toISOString(),
        _source: 'data/task/*.json + data/task/text/*.json (per list.xml)',
        _note: 'generated by tools/derive-task-catalog.js, do not hand-edit',
        version: 1,
        taskCount: catalog.taskCount,
        tasks: catalog.tasks,
        chains: catalog.chains,
        chainsUnsequenced: catalog.chainsUnsequenced
    };

    const outDir = path.dirname(args.output);
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

    const oldPayload = tryReadExistingPayload(args.output);
    if (oldPayload && JSON.stringify(stableSubset(oldPayload)) === JSON.stringify(stableSubset(newPayload))) {
        console.log('[derive-task-catalog] unchanged (' + catalog.taskCount + ' tasks), kept _generatedAt=' + (oldPayload._generatedAt || '<none>'));
        return;
    }

    // 紧凑输出（无 pretty-print 缩进）：派生产物只供机器消费，缩进会让体积翻倍（实测 202KB→~90KB）。
    fs.writeFileSync(args.output, JSON.stringify(newPayload) + '\n', 'utf8');
    console.log('[derive-task-catalog] wrote ' + catalog.taskCount + ' tasks ('
        + Object.keys(catalog.chains).length + ' sequenced chains) → ' + args.output);
}

main();
