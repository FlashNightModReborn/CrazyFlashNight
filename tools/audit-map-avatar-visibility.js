#!/usr/bin/env node
'use strict';

// 对账 data/map/map_panel.xml 的 <avatar_visibility> 段 vs launcher 端 staticAvatars/dynamicAvatars。
//
// 校验规则与 AS2 端 MapPanelCatalog.parseAvatarVisibility 保持等价（任一档失败 = exit 1）：
//
//   档 0a (ERROR): <rule> 必须有 avatarId 属性
//   档 0b (ERROR): <rule> 必须有 npc 属性
//   档 0c (ERROR): chain/min 必须配对（要么都有要么都没）
//   档 0d (ERROR): chain 必须 ∈ VALID_CHAIN_NAMES（10 个 task_chain canonical）
//   档 0e (ERROR): min 必须为非负数值
//   档 0f (ERROR): requireInfra="A|B" 切分后每项必须 ∈ VALID_INFRA_NAMES
//   档 0g (ERROR): 同一 avatarId 不可指向不同 npc
//   档 1  (ERROR): avatarId 必须命中 launcher staticAvatars/dynamicAvatars id 集
//   档 2  (WARN ): npc 在 task_npcs/npc.name 中存在（非必需，仅 lint：rule 也可对非任务静态 NPC）
//
// VALID_CHAIN_NAMES 与 scripts/类定义/org/flashNight/neur/Server/SaveManager.as
// REPAIR_DICT_TASK_CHAINS、MapPanelCatalog.VALID_CHAIN_NAMES 保持同步。
// VALID_INFRA_NAMES 与 MapPanelService.isUnlocked 中 infra.XXX 引用一致。

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const mapDataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const xmlFile = path.join(projectRoot, 'data', 'map', 'map_panel.xml');

const VALID_CHAIN_NAMES = [
    '主线', '引导', '支线', '挑战', '废城',
    '彩蛋', '异形', '大学', '后勤', '预览'
];
const VALID_INFRA_NAMES = ['自行车', '摩托车', '越野车'];

function parseArgs(argv) {
    const args = { json: false };
    for (let i = 0; i < argv.length; i += 1) {
        const a = argv[i];
        if (a === '--json') args.json = true;
        else if (a === '--help' || a === '-h') {
            console.error('usage: node tools/audit-map-avatar-visibility.js [--json]');
            process.exit(0);
        } else {
            console.error('unknown arg: ' + a);
            process.exit(1);
        }
    }
    return args;
}

function loadMapPanelData() {
    const source = fs.readFileSync(mapDataFile, 'utf8');
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source, sandbox, { filename: mapDataFile });
    if (!sandbox.MapPanelData) throw new Error('MapPanelData not found');
    return sandbox.MapPanelData;
}

function parseXmlRules() {
    const raw = fs.readFileSync(xmlFile, 'utf8');
    // 提取 <avatar_visibility>...</avatar_visibility> 区段
    const sectRe = /<avatar_visibility>([\s\S]*?)<\/avatar_visibility>/;
    const sectMatch = sectRe.exec(raw);
    if (!sectMatch) return [];  // 整段缺失 = 空规则集（允许）

    const inner = sectMatch[1];
    const ruleRe = /<rule\s+([^/>]+)\/>/g;
    const attrRe = /(\w+)\s*=\s*"([^"]*)"/g;
    const rules = [];
    let m;
    let index = 0;
    while ((m = ruleRe.exec(inner)) !== null) {
        const attrs = {};
        attrRe.lastIndex = 0;
        let a;
        while ((a = attrRe.exec(m[1])) !== null) {
            attrs[a[1]] = a[2];
        }
        rules.push({
            index: index,
            avatarId: attrs.avatarId,
            npc: attrs.npc,
            chain: attrs.chain,
            min: attrs.min,
            requireInfra: attrs.requireInfra
        });
        index += 1;
    }
    return rules;
}

function parseXmlNpcNames() {
    const raw = fs.readFileSync(xmlFile, 'utf8');
    const npcRe = /<npc\s+([^/>]+)\/>/g;
    const attrRe = /(\w+)\s*=\s*"([^"]*)"/g;
    const names = new Set();
    let m;
    while ((m = npcRe.exec(raw)) !== null) {
        attrRe.lastIndex = 0;
        let a;
        while ((a = attrRe.exec(m[1])) !== null) {
            if (a[1] === 'name') names.add(a[2]);
        }
    }
    return names;
}

function collectAvatarIds(MapPanelData) {
    const ids = new Set();
    const pageOrder = MapPanelData.getPageOrder();
    for (let i = 0; i < pageOrder.length; i += 1) {
        const page = MapPanelData.getPage(pageOrder[i]);
        const pools = [page.staticAvatars || [], page.dynamicAvatars || []];
        for (let p = 0; p < pools.length; p += 1) {
            for (let j = 0; j < pools[p].length; j += 1) {
                if (pools[p][j].id) ids.add(pools[p][j].id);
            }
        }
    }
    return ids;
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    const MapPanelData = loadMapPanelData();
    const rules = parseXmlRules();
    const xmlNpcNames = parseXmlNpcNames();
    const launcherAvatarIds = collectAvatarIds(MapPanelData);

    const errors = [];
    const warnings = [];
    const ok = [];

    const avatarIdToNpc = {};  // 档 0g 用

    for (let i = 0; i < rules.length; i += 1) {
        const r = rules[i];

        // 档 0a
        if (r.avatarId === undefined || r.avatarId === '') {
            errors.push({ tier: '0a', rule: '<rule[' + r.index + ']>', reason: '<rule> 缺 avatarId 属性' });
            continue;
        }
        // 档 0b
        if (r.npc === undefined || r.npc === '') {
            errors.push({ tier: '0b', rule: r.avatarId, reason: '<rule avatarId="' + r.avatarId + '"> 缺 npc 属性' });
            continue;
        }
        // 档 0c: chain/min 配对
        const hasChain = r.chain !== undefined && r.chain !== '';
        const hasMin = r.min !== undefined && r.min !== '';
        if (hasChain !== hasMin) {
            errors.push({ tier: '0c', rule: r.avatarId, reason: 'chain/min 必须配对出现（chain=' + r.chain + ', min=' + r.min + ')' });
            continue;
        }
        // 档 0d: chain 白名单
        if (hasChain && VALID_CHAIN_NAMES.indexOf(r.chain) < 0) {
            errors.push({ tier: '0d', rule: r.avatarId, reason: 'chain="' + r.chain + '" 不在 VALID_CHAIN_NAMES (10个 canonical) 内' });
            continue;
        }
        // 档 0e: min 非负数值
        if (hasMin) {
            const minNum = Number(r.min);
            if (Number.isNaN(minNum) || minNum < 0) {
                errors.push({ tier: '0e', rule: r.avatarId, reason: 'min="' + r.min + '" 不是非负数值' });
                continue;
            }
        }
        // 档 0f: requireInfra 切分白名单
        if (r.requireInfra !== undefined && r.requireInfra !== '') {
            const parts = r.requireInfra.split('|');
            let bad = null;
            for (let k = 0; k < parts.length; k += 1) {
                if (VALID_INFRA_NAMES.indexOf(parts[k]) < 0) { bad = parts[k]; break; }
            }
            if (bad !== null) {
                errors.push({ tier: '0f', rule: r.avatarId, reason: 'requireInfra 含非白名单项 "' + bad + '"（白名单：' + VALID_INFRA_NAMES.join('/') + '）' });
                continue;
            }
        }
        // 档 0g: avatarId → npc 一致性
        if (avatarIdToNpc[r.avatarId] !== undefined && avatarIdToNpc[r.avatarId] !== r.npc) {
            errors.push({ tier: '0g', rule: r.avatarId, reason: '同一 avatarId 指向不同 npc: "' + avatarIdToNpc[r.avatarId] + '" vs "' + r.npc + '"' });
            continue;
        }
        avatarIdToNpc[r.avatarId] = r.npc;

        // 档 1: avatarId 命中 launcher
        if (!launcherAvatarIds.has(r.avatarId)) {
            errors.push({ tier: 1, rule: r.avatarId, reason: 'avatarId="' + r.avatarId + '" 未在 launcher staticAvatars/dynamicAvatars id 集中命中' });
            continue;
        }

        // 档 2 (lint): npc 不在 task_npcs 内仅作 warning（允许对非任务静态 NPC 加 rule）
        if (!xmlNpcNames.has(r.npc)) {
            warnings.push({ tier: 2, rule: r.avatarId, reason: 'npc="' + r.npc + '" 不在 task_npcs/npc 集内（非任务静态 NPC 也允许加 rule，仅提示）' });
        }

        ok.push({ avatarId: r.avatarId, npc: r.npc, chain: r.chain || '', min: r.min || '', requireInfra: r.requireInfra || '' });
    }

    if (args.json) {
        process.stdout.write(JSON.stringify({
            ok: ok, errors: errors, warnings: warnings,
            total: rules.length
        }, null, 2) + '\n');
    } else {
        console.log('avatar_visibility audit: ' + rules.length + ' rules, ' + ok.length + ' OK, ' + errors.length + ' ERROR, ' + warnings.length + ' WARN');
        if (errors.length) {
            console.log('\nERRORS:');
            errors.forEach(function(e) {
                console.log('  [tier ' + e.tier + '] ' + e.rule + ' — ' + e.reason);
            });
        }
        if (warnings.length) {
            console.log('\nWARNINGS:');
            warnings.forEach(function(w) {
                console.log('  [tier ' + w.tier + '] ' + w.rule + ' — ' + w.reason);
            });
        }
    }

    if (errors.length) process.exit(1);
}

main();
