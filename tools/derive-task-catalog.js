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
const { loadItemMeta, attachIcon } = require('./lib/item-icons.js');

const projectRoot = path.resolve(__dirname, '..');
const metricsFile = path.join(projectRoot, 'scripts', '类定义', 'org', 'flashNight', 'arki', 'achievement', 'AchievementMetrics.as');
const defaultTaskDir = path.join(projectRoot, 'data', 'task');
const defaultOutput = path.join(projectRoot, 'launcher', 'web', 'modules', 'tasks', 'task-catalog.json');
let taskDir = defaultTaskDir;            // --task-dir 可覆盖（测试夹具用，见 tools/test-derive-task-conditions.js）
let textDir = path.join(defaultTaskDir, 'text');
let itemMetaByName = null;

function fail(msg) {
    console.error('[derive-task-catalog] ' + msg);
    process.exit(1);
}

function parseArgs(argv) {
    const args = { output: defaultOutput, check: false, taskDir: null };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--output') { args.output = argv[i + 1] || ''; i += 1; continue; }
        if (arg === '--check') { args.check = true; continue; }
        if (arg === '--task-dir') { args.taskDir = argv[i + 1] || ''; i += 1; continue; }
        if (arg === '--help' || arg === '-h') { printHelp(0); return null; }
        printHelp(1, 'unknown arg: ' + arg);
        return null;
    }
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/derive-task-catalog.js [--output <file>] [--check] [--task-dir <dir>]');
    console.error('  --check     parse + validate only, do not write');
    console.error('  --task-dir  task data root override (default data/task; for test fixtures)');
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
    return itemMetaByName ? attachIcon(o, itemMetaByName) : o;
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

        // 委托链（副本任务）专属字段：副本 Web 面板需要海报/契约金/等级窗口/挑战条件。
        // 仅 chain=="委托" 才挂 dungeon 子对象；普通 tasks 面板忽略未知字段（向后兼容）。
        // 委托简报对话不入静态 catalog —— 走运行态 dungeonBriefing（复用立绘解析，避免重复）。
        if (chainName === '委托') {
            const ch = (t.challenge && typeof t.challenge === 'object')
                ? {
                    difficulty: t.challenge.difficulty != null ? String(t.challenge.difficulty) : '',
                    limitations: Array.isArray(t.challenge.limitations) ? t.challenge.limitations.slice() : []
                }
                : null;
            tasks[idKey].dungeon = {
                imageurl: t.imageurl != null ? String(t.imageurl) : '',
                getNpc: t.get_npc != null ? String(t.get_npc) : '',
                deposit: Number(t.deposit) || 0,
                kDeposit: Number(t.Kdeposit) || 0,
                restrictedLevel: Number(t.restricted_level) || 0,
                recommendedLevel: t.recommended_level != null ? String(t.recommended_level) : '',
                challenge: ch
            };
        }

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

    // ═══ 条件可满足性校验：单调 AND-OR 不动点（对齐运行时真实语义） ═══
    // 四轮演进：局部规则两轮被击穿（前序依赖盲区/seq 缺口）→ 图环检测一轮被击穿（链前驱边
    // 虚构了运行时不存在的顺序约束：taskAvailable 接取门控只查 get_requirements 不查链序号
    // ——通信_鸡蛋_任务系统.as，实测 11 个非前序依赖转换含独立挑战任务，会被误报死锁）。
    // 终版按引擎真实语义建模，不再附加任何顺序假设：
    //   任务 T 可完成 ⇔ get_requirements 全部可完成（接取门控，唯一真实边）
    //                 ∧ taskFinished 条件引用任务可完成
    //                 ∧ 每个 chainProgress(C,t) 条件存在【任一】候选 X∈C、seq(X)≥t、X 可完成
    //     （chainProgress 是析取——任一候选满足即可，普通有向图环检测表达不了 OR，
    //       故用单调不动点迭代「可完成集合」直至收敛：Horn 可满足性，O(V·E) 上界，238 任务可忽略；
    //       候选=宿主自身天然无效——判定时宿主必不在集合内，seq 缺口/自链死锁由此自然涌现）
    //   基线集 = 仅 get_requirements 的不动点；带条件后从基线集跌出的任务 = 条件引入的死锁 → fail
    //   并逐任务打印阻塞条件。存量数据在基线集就不可完成的任务不在此门审计（历史问题与 conditions 无关）。
    // 边界：只证「条件无结构性死锁」，不证「可完成」（物品/经济/运行态/NPC 脚本发任务归 playtest）。
    const allIds = Object.keys(tasks);
    const reqOf = {};      // idKey → [存在的 get_requirements idKey...]
    for (let i = 0; i < allIds.length; i += 1) {
        const req = tasks[allIds[i]].req;
        const out = [];
        for (let r = 0; r < req.length; r += 1) {
            if (idSeen[String(req[r])] === true) out.push(String(req[r]));
        }
        reqOf[allIds[i]] = out;
    }
    const tfByHost = {};   // idKey → [{ctx, ref}]
    for (let r = 0; r < pendingTaskRefs.length; r += 1) {
        const t = pendingTaskRefs[r];
        if (!tfByHost[t.host]) tfByHost[t.host] = [];
        tfByHost[t.host].push(t);
    }
    const cpByHost = {};   // idKey → [{ctx, chain, target}]（基础闭包先行：链存在 / target≤最大 seq）
    const chainCands = {}; // 链名 → [{seq, id(idKey)}]
    const chainNamesAll = Object.keys(chains);
    for (let n = 0; n < chainNamesAll.length; n += 1) {
        const seqMap = chains[chainNamesAll[n]];
        chainCands[chainNamesAll[n]] = Object.keys(seqMap).map(function (s) {
            return { seq: Number(s), id: String(seqMap[Number(s)]) };
        });
    }
    for (let r = 0; r < pendingChainRefs.length; r += 1) {
        const ref = pendingChainRefs[r];
        const seqMap = chains[ref.chain];
        if (seqMap === undefined) {
            fail(ref.ctx + ': chainProgress references unknown sequenced chain "' + ref.chain
                + '" (无序号链不更新 task_chains_progress，条件永不可达)');
        }
        const seqs = Object.keys(seqMap).map(Number);
        const maxSeq = Math.max.apply(null, seqs);
        if (ref.target > maxSeq) {
            fail(ref.ctx + ': chainProgress target ' + ref.target + ' exceeds chain "' + ref.chain
                + '" max seq ' + maxSeq + ' (unreachable condition)');
        }
        if (!cpByHost[ref.host]) cpByHost[ref.host] = [];
        cpByHost[ref.host].push(ref);
    }

    function computeCompletable(useConditions) {
        const done = {};
        let changed = true;
        while (changed) {
            changed = false;
            for (let i = 0; i < allIds.length; i += 1) {
                const id = allIds[i];
                if (done[id] === true) continue;
                let ok = true;
                const req = reqOf[id];
                for (let r = 0; r < req.length && ok; r += 1) {
                    if (done[req[r]] !== true) ok = false;
                }
                if (ok && useConditions) {
                    const tfs = tfByHost[id] || [];
                    for (let t = 0; t < tfs.length && ok; t += 1) {
                        if (done[tfs[t].ref] !== true) ok = false;
                    }
                    const cps = cpByHost[id] || [];
                    for (let c = 0; c < cps.length && ok; c += 1) {
                        let sat = false;
                        const cands = chainCands[cps[c].chain];
                        for (let k = 0; k < cands.length; k += 1) {
                            if (cands[k].seq >= cps[c].target && done[cands[k].id] === true) { sat = true; break; }
                        }
                        if (!sat) ok = false;
                    }
                }
                if (ok) { done[id] = true; changed = true; }
            }
        }
        return done;
    }

    if (pendingTaskRefs.length > 0 || pendingChainRefs.length > 0) {
        const baseline = computeCompletable(false);
        const withCond = computeCompletable(true);
        const lines = [];
        for (let i = 0; i < allIds.length; i += 1) {
            const id = allIds[i];
            if (baseline[id] !== true || withCond[id] === true) continue;
            // 跌出基线集 = 条件引入的死锁；逐条定位阻塞原因
            const tfs = tfByHost[id] || [];
            const cps = cpByHost[id] || [];
            let blamed = false;
            for (let t = 0; t < tfs.length; t += 1) {
                if (withCond[tfs[t].ref] !== true) {
                    lines.push(tfs[t].ctx + ': taskFinished 引用任务 ' + tfs[t].ref + ' 不可先于本任务完成');
                    blamed = true;
                }
            }
            for (let c = 0; c < cps.length; c += 1) {
                const cands = chainCands[cps[c].chain].filter(function (x) { return x.seq >= cps[c].target; });
                if (!cands.some(function (x) { return withCond[x.id] === true; })) {
                    lines.push(cps[c].ctx + ': chainProgress ' + cps[c].chain + '≥' + cps[c].target
                        + ' 的全部候选任务 [' + cands.map(function (x) { return x.id + '(#' + x.seq + ')'; }).join(', ')
                        + '] 均不可先于本任务完成');
                    blamed = true;
                }
            }
            if (!blamed) {
                lines.push('task ' + id + ': 级联死锁——get_requirements 前置任务因上述条件死锁不可完成');
            }
        }
        if (lines.length > 0) {
            fail('conditions deadlock — 以下任务因条件永不可满足而无法完成:\n  ' + lines.join('\n  '));
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
    if (args.taskDir) {
        taskDir = path.resolve(args.taskDir);
        textDir = path.join(taskDir, 'text');
    }

    const rawTasks = loadTasks();
    const taskTexts = loadTexts();
    itemMetaByName = loadItemMeta(projectRoot, fail);
    const catalog = buildCatalog(rawTasks, taskTexts);

    if (args.check) {
        console.log('[derive-task-catalog] check OK: ' + catalog.taskCount + ' tasks, '
            + Object.keys(catalog.chains).length + ' sequenced chains, closure valid.');
        return;
    }

    const newPayload = {
        _generatedAt: new Date().toISOString(),
        _source: 'data/task/*.json + data/task/text/*.json (per list.xml) + data/items/*.xml item icons',
        _note: 'generated by tools/derive-task-catalog.js, do not hand-edit; v3 adds itemReqs/rewards icon from item XML',
        version: 3,
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
