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
const { validateCondition, parseEconomyWhitelist } = require('./lib/objective-types.js');

const projectRoot = path.resolve(__dirname, '..');
const metricsFile = path.join(projectRoot, 'scripts', '类定义', 'org', 'flashNight', 'arki', 'achievement', 'AchievementMetrics.as');
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

// 依赖图 DFS：from 沿 edges 可达 to 时返回路径 [from..to]，不可达返回 null（死锁环检测用）。
function findDepPath(from, to, edges) {
    if (from === to) return [from];
    const stack = [from];
    const visited = {};
    const parent = {};
    visited[from] = true;
    while (stack.length > 0) {
        const cur = stack.pop();
        const next = edges[cur] || [];
        for (let i = 0; i < next.length; i += 1) {
            const nb = next[i];
            if (visited[nb] === true) continue;
            visited[nb] = true;
            parent[nb] = cur;
            if (nb === to) {
                const path = [to];
                let p = to;
                while (p !== from) { p = parent[p]; path.push(p); }
                return path.reverse();
            }
            stack.push(nb);
        }
    }
    return null;
}

function buildCatalog(rawTasks, taskTexts) {
    const tasks = {};
    // conditions 校验（任务-成就判定层共享，可选字段；设计 docs/任务成就-判定层共享-设计-2026-06-11.md §3）。
    // economyCount 白名单惰性解析：仅当数据真用到 economyCount 才读 AchievementMetrics.as。
    let economyCounters = null;
    const pendingTaskRefs = []; // taskFinished 跨任务引用，全集建完后做存在性闭包（防前向引用误杀）
    const pendingChainRefs = []; // chainProgress 链引用，全集建完后校验 链存在 + target ≤ 链最大 seq（可达性）
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

        // conditions（可选）：逐条过共享校验器（类型枚举/target/label/params/sinceAccept 单调限定）
        if (t.conditions !== undefined) {
            if (!Array.isArray(t.conditions) || t.conditions.length === 0) {
                fail(ctx + ': conditions must be a non-empty array when present');
            }
            for (let c = 0; c < t.conditions.length; c += 1) {
                const cond = t.conditions[c];
                if (cond && cond.type === 'economyCount' && economyCounters === null) {
                    economyCounters = parseEconomyWhitelist(metricsFile, fail);
                }
                validateCondition(cond, ctx + '.conditions[' + c + ']', fail, economyCounters);
                // 跨任务闭包：自引用即拒；存在性/死锁等全集建完后 post-pass（防前向引用误杀）
                if (cond.type === 'taskFinished') {
                    if (String(cond.params.taskId) === idKey) {
                        fail(ctx + '.conditions[' + c + ']: taskFinished cannot reference itself');
                    }
                    pendingTaskRefs.push({ ctx: ctx + '.conditions[' + c + ']', host: idKey, ref: String(cond.params.taskId) });
                }
                // chainProgress 可达性闭包（post-pass）：task_chains_progress 只在【有序号链】任务
                // FinishTask 时写 max(progress, seq)（通信_鸡蛋_任务系统.as UpdateTaskProgress），
                // 引用无序号链或 target 超链最大 seq = 永不可达静默上架
                if (cond.type === 'chainProgress') {
                    pendingChainRefs.push({
                        ctx: ctx + '.conditions[' + c + ']',
                        host: idKey,
                        chain: String(cond.params.chain),
                        target: Number(cond.target)
                    });
                }
            }
        }

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

    // taskFinished 条件引用的任务存在性闭包（全集已建完）
    for (let r = 0; r < pendingTaskRefs.length; r += 1) {
        if (idSeen[pendingTaskRefs[r].ref] !== true) {
            fail(pendingTaskRefs[r].ctx + ': taskFinished references missing task id "' + pendingTaskRefs[r].ref + '"');
        }
    }

    // ═══ 条件死锁校验：lower 成任务级依赖图 + 环检测 ═══
    // 死锁是依赖图的【全局】性质——逐条局部不变量（target<ownSeq / 存在性检查）连续两轮被复审
    // 击穿（序号缺口、跨链循环各是一个组合盲区），故收敛到标准做法：所有 gating lower 成
    // 任务级 precedence 边，对条件边做可达性环检测。三类已知死锁（自链/缺口/跨链循环）统一归约。
    //
    // 保守顺序模型（偏误杀不偏漏；真有合法乱序设计在此放宽——显式决策点）：
    //   ① 有序号链按 seq 升序完成 → 每任务依赖链内前一实际 seq 任务
    //     （实测 225 个相邻链转换 171 个 get_requirements 显式依赖前序，FinishTask 自动接取亦按序）
    //   ② get_requirements：接取前置 ⇒ 完成前置
    //   ③ 条件边：taskFinished → 引用任务；chainProgress(C,t) → C 链 seq≥t 的【最小 seq】任务（锚点；
    //     锚点若死锁，链上更晚任务按 ① 全部死锁，故取最小即足）——seq 缺口天然落到锚点=自身/后续
    //   判定：沿「依赖」边从锚点 DFS 可达宿主 = 满足条件须先完成宿主自身 → 死锁环，打印路径。
    // 边界声明：只证「条件无结构性死锁」，不证「任务可完成」（物品/经济/运行态归 playtest）；
    // 只审计条件边参与的环，存量 get_requirements/链序的历史问题不在此门。
    const depEdges = {}; // idKey → [依赖的 idKey...]
    function addDep(from, to) {
        if (!depEdges[from]) depEdges[from] = [];
        depEdges[from].push(to);
    }
    // ① 链内前驱边
    const allChainNames = Object.keys(chains);
    for (let n = 0; n < allChainNames.length; n += 1) {
        const seqMap = chains[allChainNames[n]];
        const sorted = Object.keys(seqMap).map(Number).sort(function (a, b) { return a - b; });
        for (let s = 1; s < sorted.length; s += 1) {
            addDep(String(seqMap[sorted[s]]), String(seqMap[sorted[s - 1]]));
        }
    }
    // ② get_requirements 边（引用不存在的 id 不在此门审计，跳过）
    const allIds = Object.keys(tasks);
    for (let i = 0; i < allIds.length; i += 1) {
        const req = tasks[allIds[i]].req;
        for (let r = 0; r < req.length; r += 1) {
            if (idSeen[String(req[r])] === true) addDep(allIds[i], String(req[r]));
        }
    }
    // ③ 条件边（基础闭包先行：链存在 / target≤最大 seq —— 锚点解析的前提）
    const condEdges = [];
    for (let r = 0; r < pendingTaskRefs.length; r += 1) {
        condEdges.push({ ctx: pendingTaskRefs[r].ctx, host: pendingTaskRefs[r].host, anchor: pendingTaskRefs[r].ref });
    }
    for (let r = 0; r < pendingChainRefs.length; r += 1) {
        const ref = pendingChainRefs[r];
        const seqMap = chains[ref.chain];
        if (seqMap === undefined) {
            fail(ref.ctx + ': chainProgress references unknown sequenced chain "' + ref.chain
                + '" (无序号链不更新 task_chains_progress，条件永不可达)');
        }
        const seqs = Object.keys(seqMap).map(Number).sort(function (a, b) { return a - b; });
        if (ref.target > seqs[seqs.length - 1]) {
            fail(ref.ctx + ': chainProgress target ' + ref.target + ' exceeds chain "' + ref.chain
                + '" max seq ' + seqs[seqs.length - 1] + ' (unreachable condition)');
        }
        let anchorSeq = null;
        for (let s = 0; s < seqs.length; s += 1) {
            if (seqs[s] >= ref.target) { anchorSeq = seqs[s]; break; }
        }
        condEdges.push({ ctx: ref.ctx, host: ref.host, anchor: String(seqMap[anchorSeq]) });
    }
    for (let e = 0; e < condEdges.length; e += 1) addDep(condEdges[e].host, condEdges[e].anchor);
    // 环检测：每条条件边从锚点出发找回宿主的依赖路径
    for (let e = 0; e < condEdges.length; e += 1) {
        const edge = condEdges[e];
        if (edge.anchor === edge.host) {
            fail(edge.ctx + ': deadlock cycle — 条件锚点为本任务自身'
                + '（链 seq 缺口或 target ≥ 自身 seq：该进度只能由完成本任务推到）');
        }
        const path = findDepPath(edge.anchor, edge.host, depEdges);
        if (path !== null) {
            fail(edge.ctx + ': deadlock cycle — 满足该条件须先完成任务 ' + edge.anchor
                + '，而其依赖链回到本任务: ' + path.join(' → ') + '（→ 表示「依赖/须先完成」）');
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

// 稳定子集（仅排除 _generatedAt，时间戳每次都变）用于 unchanged 跳写，避免无意义 mtime/diff churn。
// 必须含 version / taskCount：否则 schema 版本升级或任务数变化会被误判为 unchanged 而静默跳过刷新
// （含手改/损坏的旧产物得不到纠正）。除 _generatedAt 外的字段一律纳入比较。
function stableSubset(payload) {
    return {
        _source: payload._source,
        _note: payload._note,
        version: payload.version,
        taskCount: payload.taskCount,
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
