#!/usr/bin/env node
'use strict';

// 对账 data/task/*.json 的 finish_npc 引用 vs data/map/task_npc_registry.json 的 NPC 集合。
//
// 历史 (Stage A → 方案 B 前): 本工具校验 data/map/map_panel.xml 的 <npc> 段 → launcher slot 一致性。
//   task_npcs 段已迁出 XML，那一档校验全部失效。
// 当前 (方案 B, 2026-05-28): NPC↔hotspot 真相源已统一到 launcher/web/modules/map-panel-data.js，
//   build.ps1 Step 1b 派生为 data/map/task_npc_registry.json。本工具反向 info 巡检：
//
//   档 1 (ERROR, exit 1): registry JSON 不存在 / 损坏 / alias canonical 自身不在 task_npcs。
//                         这一档代表 registry 链路真的坏了，必须修。
//   档 2 (WARN, exit 0):  data/task/*.json 的 finish_npc 在 registry（含 alias，含小写 fallback，
//                         对齐 AS2 MapTaskNpcRegistry.findMarker 三级查询语义）里找不到。
//                         绝大多数是战斗/佣兵 NPC（没有 map 头像，finish_npc 字段用途不同），
//                         不属于地图任务交付链路漂移。AS2 端 buildTaskNpcMarkers 会自然
//                         跳过这些，不影响功能。如果某条 WARN 你确认是地图 NPC 漂移，
//                         去 launcher/web/modules/map-panel-data.js 的 staticAvatars 补上即可。

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const registryFile = path.join(projectRoot, 'data', 'map', 'task_npc_registry.json');
const taskDir = path.join(projectRoot, 'data', 'task');

function parseArgs(argv) {
    const args = { json: false };
    for (let i = 0; i < argv.length; i += 1) {
        const a = argv[i];
        if (a === '--json') args.json = true;
        else if (a === '--help' || a === '-h') {
            console.error('usage: node tools/audit-map-taskmarkers.js [--json]');
            process.exit(0);
        } else {
            console.error('unknown arg: ' + a);
            process.exit(1);
        }
    }
    return args;
}

function loadRegistry() {
    if (!fs.existsSync(registryFile)) {
        return { ok: false, error: 'registry file missing: ' + registryFile + ' (跑 node tools/derive-task-npc-registry.js 派生)' };
    }
    try {
        const obj = JSON.parse(fs.readFileSync(registryFile, 'utf8'));
        const npcSet = new Set();
        const npcLowerSet = new Map();  // lower → canonical original
        const npcHotspots = {};
        const npcHotspotSet = new Set();
        const aliasMap = {};
        (obj.task_npcs || []).forEach(function(n) {
            if (n && n.name) {
                const name = String(n.name);
                const hotspot = n.hotspot ? String(n.hotspot) : '';
                npcSet.add(name);
                if (!npcHotspots[name]) npcHotspots[name] = [];
                if (hotspot) {
                    npcHotspots[name].push(hotspot);
                    npcHotspotSet.add(name + '\n' + hotspot);
                }
                const lower = name.toLowerCase();
                if (!npcLowerSet.has(lower)) npcLowerSet.set(lower, name); // "先来先占" 对齐 AS2 register()
            }
        });
        (obj.aliases || []).forEach(function(a) {
            if (a && a.name && a.canonical) aliasMap[String(a.name)] = String(a.canonical);
        });
        return { ok: true, npcSet: npcSet, npcLowerSet: npcLowerSet, npcHotspots: npcHotspots, npcHotspotSet: npcHotspotSet, aliasMap: aliasMap, raw: obj };
    } catch (e) {
        return { ok: false, error: 'registry JSON parse failed: ' + e.message };
    }
}

// 对齐 MapTaskNpcRegistry.findMarker 三级查询：原样 → alias → 小写 fallback
function lookupNpc(reg, name, hotspot) {
    if (reg.npcSet.has(name)) return resolvePlacement(reg, { hit: true, via: 'exact', resolved: name }, hotspot);
    if (reg.aliasMap[name] !== undefined) {
        const canon = reg.aliasMap[name];
        if (reg.npcSet.has(canon)) return resolvePlacement(reg, { hit: true, via: 'alias', resolved: canon }, hotspot);
        return { hit: false, via: 'alias-broken', resolved: canon };
    }
    const lower = String(name).toLowerCase();
    if (reg.npcLowerSet.has(lower)) return resolvePlacement(reg, { hit: true, via: 'lowerFallback', resolved: reg.npcLowerSet.get(lower) }, hotspot);
    return { hit: false, via: 'miss', resolved: null };
}

function resolvePlacement(reg, res, hotspot) {
    const placements = reg.npcHotspots[res.resolved] || [];
    if (hotspot) {
        if (!reg.npcHotspotSet.has(res.resolved + '\n' + hotspot)) {
            return { hit: false, via: 'placement-miss', resolved: res.resolved, hotspot: hotspot, placements: placements };
        }
        res.hotspot = hotspot;
        res.ambiguous = false;
        return res;
    }
    res.placements = placements;
    res.ambiguous = placements.length > 1;
    return res;
}

function collectFinishNpcs() {
    const refs = [];
    const files = fs.readdirSync(taskDir).filter(function(f) { return f.endsWith('.json'); });
    files.forEach(function(file) {
        const full = path.join(taskDir, file);
        let obj;
        try {
            obj = JSON.parse(fs.readFileSync(full, 'utf8'));
        } catch (e) {
            refs.push({ file: file, taskId: '<parse-error>', finishNpc: null, error: e.message });
            return;
        }
        const list = (obj && Array.isArray(obj.tasks)) ? obj.tasks : [];
        list.forEach(function(t) {
            if (t && typeof t.finish_npc === 'string' && t.finish_npc !== '') {
                refs.push({ file: file, taskId: t.id, finishNpc: t.finish_npc, finishHotspot: t.finish_npc_hotspot || '' });
            }
        });
    });
    return refs;
}

function main() {
    const args = parseArgs(process.argv.slice(2));

    const reg = loadRegistry();
    if (!reg.ok) {
        console.error('[FAIL] ' + reg.error);
        process.exit(1);
    }

    const refs = collectFinishNpcs();
    const errors = [];      // tier 1: 真正破损（registry 自己 / JSON parse）→ exit 1
    const warnings = [];    // tier 2: 任务 NPC 在 registry 找不到 → info, exit 0
    const aliasHits = [];   // alias 命中 info
    const lowerHits = [];   // lowercase fallback 命中 info
    const ok = [];

    refs.forEach(function(r) {
        if (r.error) {
            errors.push({ tier: 'parse', file: r.file, reason: 'JSON parse failed: ' + r.error });
            return;
        }
        const res = lookupNpc(reg, r.finishNpc, r.finishHotspot);
        if (res.hit) {
            if (res.ambiguous) {
                errors.push({
                    tier: 'placement',
                    file: r.file, taskId: r.taskId,
                    reason: 'finish_npc="' + r.finishNpc + '" 有多个地图 placement (' + res.placements.join(', ') + ')，必须补 finish_npc_hotspot'
                });
                return;
            }
            if (res.via === 'alias') {
                aliasHits.push({ file: r.file, taskId: r.taskId, finishNpc: r.finishNpc, canonical: res.resolved });
            } else if (res.via === 'lowerFallback') {
                lowerHits.push({ file: r.file, taskId: r.taskId, finishNpc: r.finishNpc, canonical: res.resolved });
            }
            ok.push(r);
            return;
        }
        if (res.via === 'alias-broken') {
            errors.push({
                tier: 1,
                file: r.file, taskId: r.taskId,
                reason: 'finish_npc="' + r.finishNpc + '" 通过 alias 映射到 "' + res.resolved + '"，但 canonical 不在 registry.task_npcs（registry 自己破损）'
            });
            return;
        }
        if (res.via === 'placement-miss') {
            errors.push({
                tier: 'placement',
                file: r.file, taskId: r.taskId,
                reason: 'finish_npc="' + r.finishNpc + '" 的 finish_npc_hotspot="' + r.finishHotspot + '" 未命中 registry placement（可选: ' + res.placements.join(', ') + '）'
            });
            return;
        }
        warnings.push({
            file: r.file, taskId: r.taskId, finishNpc: r.finishNpc,
            reason: 'finish_npc="' + r.finishNpc + '" 不在 registry（多见于战斗/佣兵 NPC，无地图头像，functional 不受影响；若是地图 NPC 漂移请回 staticAvatars 补）'
        });
    });

    if (args.json) {
        process.stdout.write(JSON.stringify({
            registryCounts: {
                task_npcs: reg.npcSet.size,
                aliases: Object.keys(reg.aliasMap).length
            },
            taskRefCount: refs.length,
            ok: ok.length,
            aliasHits: aliasHits,
            lowerHits: lowerHits,
            warnings: warnings,
            errors: errors
        }, null, 2) + '\n');
    } else {
        console.log('task finish_npc audit: ' + refs.length + ' refs, ' + ok.length + ' OK, ' + warnings.length + ' WARN, ' + errors.length + ' ERROR');
        console.log('  registry: ' + reg.npcSet.size + ' task_npcs + ' + Object.keys(reg.aliasMap).length + ' aliases');
        console.log('  hits: ' + aliasHits.length + ' via alias, ' + lowerHits.length + ' via lowercase fallback');
        if (aliasHits.length) {
            console.log('\nALIAS HITS (info):');
            aliasHits.forEach(function(h) {
                console.log('  ' + h.file + ' task ' + h.taskId + ': "' + h.finishNpc + '" → "' + h.canonical + '"');
            });
        }
        if (lowerHits.length) {
            console.log('\nLOWERCASE FALLBACK HITS (info, AS2 仍能匹配但拼写不一致):');
            lowerHits.forEach(function(h) {
                console.log('  ' + h.file + ' task ' + h.taskId + ': "' + h.finishNpc + '" → "' + h.canonical + '"');
            });
        }
        if (warnings.length) {
            console.log('\nWARNINGS (info, exit 0):');
            warnings.forEach(function(w) {
                console.log('  ' + w.file + ' task ' + (w.taskId || '?') + ': ' + w.reason);
            });
        }
        if (errors.length) {
            console.log('\nERRORS (exit 1):');
            errors.forEach(function(e) {
                console.log('  [tier ' + e.tier + '] ' + e.file + ' task ' + (e.taskId || '?') + ' — ' + e.reason);
            });
        }
    }

    if (errors.length) process.exit(1);
}

main();
