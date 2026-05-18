#!/usr/bin/env node
'use strict';

// 对账 data/map/map_panel.xml 的 <npc> 列表 vs launcher 端 staticAvatars / dynamicAvatars。
//
// Stage A 重写：原 _root._mapRegisterTaskNpcMarker 是已下线 AS2 API，工具悄悄空转。
// 新版改读 XML 作为权威源，单向校验（XML → launcher）：
//
//   档 0a (ERROR): <npc> 节点必须有 name 属性（AS2 端 MapTaskNpcRegistry.applyFromXml 同样硬失败）
//   档 0b (ERROR): <npc> 节点必须有 hotspot 属性
//   档 0c (ERROR): npc.name 不得在 XML 内重复（含大小写仅 case 不同冲突）
//   档 0d (ERROR): REQUIRED_NPC_NAMES 必须全部出现（54 项 canonical，允许超集）
//   档 1  (ERROR): XML.npc.hotspot 必须命中 launcher panel 数据某个 hotspot id
//   档 2  (ERROR): XML.npc 的 normalizeNpcMarkerKey 必须在 launcher staticAvatars / dynamicAvatars 中匹配某个 slot
//   档 3  (ERROR): 匹配到的 slot.hotspotId 必须 === XML.npc.hotspot（Stage 0 已修完后这条全过）
//   档 4  (ERROR): XML <npc> 节点不得带 x / y 属性（Stage A 已删完）
//
// 本工具只做 XML canonical / task npc → launcher 方向校验。反向（launcher 有 slot 但
// XML 无 npc）允许存在——典型如 faction.researcher_avatar：launcher 静态头像但不是任务
// finish_npc、不在 REQUIRED_NPC_NAMES 里，因此 XML 不需要登记。XML 覆盖完整性仅由档 0d
// (REQUIRED_NPC_NAMES) 兜底，非任务非 canonical 的 launcher slot 不报警。
//
// 与 A.5 的 launcher-orphan 概念**不一样**：A.5 launcher-orphan = "launcher slot 有但
// source-data 没有对应 entry"（assetUrl 找不到 source entry），由
// `node tools/audit-map-layout.js --kind avatar --fail-on-review` 的 missing status 兜底，
// 完全独立于本工具。
//
// REQUIRED_NPC_NAMES 与 scripts/类定义/org/flashNight/arki/map/MapTaskNpcRegistry.as 的同名列表保持同步。
// 新增 / 改名 canonical NPC 属于设计变更，两边都要改。

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const mapDataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const xmlFile = path.join(projectRoot, 'data', 'map', 'map_panel.xml');

// 同步自 scripts/类定义/org/flashNight/arki/map/MapTaskNpcRegistry.as REQUIRED_NPC_NAMES。
// 新增 / 改名 canonical NPC 必须两边同步修改。
const REQUIRED_NPC_NAMES = [
    'Pig', 'Boy', 'King', '冷兵器商人', '杀马特',
    '酒保', '格格巫', '丽丽丝', '舞女',
    '宝石线人', '前治安官', '黑铁会外交部长', '学生妹', '幸存老兵',
    'The Girl', 'Andy Law', 'Shop Girl', 'Blue', '小F',
    '厨师',
    'general', 'gazer', 'director', 'itinerant', 'surveyor',
    'singer', 'keyboard', 'guitar',
    '火凤', '翅虎', '黑龙', '黑铁',
    '牛仔', '假肢仙人', '吸特乐',
    'artist', 'soldier', '排骨', '机哥', '阿波', 'PROPHET',
    '黑仔', 'Bat', 'Tomboy', '武器订购系统',
    '体育老师', '室友', '程铮', '剑道社长', '冯佑权',
    '理科教授', '文科老师', 'Vanshuther', '教导主任'
];

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

function loadMapPanelData() {
    const source = fs.readFileSync(mapDataFile, 'utf8');
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source, sandbox, { filename: mapDataFile });
    if (!sandbox.MapPanelData) throw new Error('MapPanelData not found');
    return sandbox.MapPanelData;
}

// 与 launcher/web/modules/map-panel.js:1242-1247 normalizeNpcMarkerKey 同步
function normalizeNpcMarkerKey(value) {
    return String(value || '')
        .replace(/^task_npc_/, '')
        .replace(/\s+/g, '')
        .replace(/[·•]/g, '')
        .toLowerCase();
}

// 与 launcher/web/modules/map-panel.js:1258-1268 getSlotNpcKeys 等价
function getSlotNpcKeys(slot) {
    const keys = [];
    if (!slot) return keys;
    if (slot.label) keys.push(normalizeNpcMarkerKey(slot.label));
    if (slot.id) keys.push(normalizeNpcMarkerKey(slot.id));
    if (slot.assetUrl) keys.push(normalizeNpcMarkerKey(slot.assetUrl));
    if (slot.label === '杀马特') keys.push(normalizeNpcMarkerKey('∞天ㄙ★使的剪∞'));
    return keys;
}

function parseXmlNpcs() {
    const raw = fs.readFileSync(xmlFile, 'utf8');
    const npcRe = /<npc\s+([^/>]+)\/>/g;
    const attrRe = /(\w+)\s*=\s*"([^"]*)"/g;
    const npcs = [];
    let m;
    let index = 0;
    while ((m = npcRe.exec(raw)) !== null) {
        const inner = m[1];
        const attrs = {};
        attrRe.lastIndex = 0;
        let a;
        while ((a = attrRe.exec(inner)) !== null) {
            attrs[a[1]] = a[2];
        }
        // 不预过滤：缺 name/hotspot 也保留，让 main 统一报档 0a / 0b 错
        npcs.push({
            index: index,
            name: attrs.name,            // 可能 undefined
            hotspot: attrs.hotspot,      // 可能 undefined
            hasX: attrs.x !== undefined,
            hasY: attrs.y !== undefined
        });
        index += 1;
    }
    return npcs;
}

function findSlotForNpcKey(MapPanelData, npcKey) {
    const pageOrder = MapPanelData.getPageOrder();
    for (let i = 0; i < pageOrder.length; i += 1) {
        const pageId = pageOrder[i];
        const page = MapPanelData.getPage(pageId);
        const pools = [
            { kind: 'static', list: page.staticAvatars || [] },
            { kind: 'dynamic', list: page.dynamicAvatars || [] }
        ];
        for (let p = 0; p < pools.length; p += 1) {
            const list = pools[p].list;
            for (let j = 0; j < list.length; j += 1) {
                const keys = getSlotNpcKeys(list[j]);
                for (let k = 0; k < keys.length; k += 1) {
                    if (keys[k] && keys[k] === npcKey) {
                        return { pageId: pageId, slot: list[j], kind: pools[p].kind };
                    }
                }
            }
        }
    }
    return null;
}

function findHotspotInAnyPage(MapPanelData, hotspotId) {
    const pageOrder = MapPanelData.getPageOrder();
    for (let i = 0; i < pageOrder.length; i += 1) {
        const pageId = pageOrder[i];
        const page = MapPanelData.getPage(pageId);
        const hotspots = page.hotspots || [];
        for (let j = 0; j < hotspots.length; j += 1) {
            if (hotspots[j].id === hotspotId) return { pageId: pageId, hotspot: hotspots[j] };
        }
    }
    return null;
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    const MapPanelData = loadMapPanelData();
    const npcs = parseXmlNpcs();

    const errors = [];
    const ok = [];

    // 档 0c 用：name → 出现次数 / 索引
    const nameOccurrences = {};       // 原名 (case-sensitive) → [index, ...]
    const lowerNameOwner = {};        // lower(name) → 首次出现的原名

    for (let i = 0; i < npcs.length; i += 1) {
        const npc = npcs[i];

        // 档 0a: 缺 name（没 name 就无法记录到 nameOccurrences，canonical 0d 也无法把它当作"出现过"）
        if (npc.name === undefined || npc.name === '') {
            errors.push({
                tier: '0a',
                npc: '<npc[' + npc.index + ']>',
                reason: '<npc> 节点缺 name 属性（AS2 端 MapTaskNpcRegistry.applyFromXml 会硬失败）'
            });
            continue;
        }

        // 先把 name 记账（让 0d canonical 检查能看到"出现过"），再做余下校验。
        // 这样即便后续 0b/0c/0c-lower 失败 continue，0d 也不会重复抱怨"canonical 缺失"。

        // 档 0c-1: name 完全相同重复（首条 push 进 nameOccurrences；后续都报错）
        if (nameOccurrences[npc.name]) {
            errors.push({
                tier: '0c',
                npc: npc.name,
                reason: 'npc.name 在 XML 内重复（首见 index=' + nameOccurrences[npc.name][0] + '，本次 index=' + npc.index + '）'
            });
            nameOccurrences[npc.name].push(npc.index);
            continue;
        }
        nameOccurrences[npc.name] = [npc.index];

        // 档 0c-2: 仅大小写不同冲突（AS2 端 MapTaskNpcRegistry.applyFromXml 同样硬失败）
        const lower = String(npc.name).toLowerCase();
        if (lowerNameOwner[lower] !== undefined && lowerNameOwner[lower] !== npc.name) {
            errors.push({
                tier: '0c',
                npc: npc.name,
                reason: 'npc.name 仅大小写与 "' + lowerNameOwner[lower] + '" 不同（AS2 lowercased fallback 表会冲突）'
            });
            continue;
        }
        lowerNameOwner[lower] = npc.name;

        // 档 0b: 缺 hotspot
        if (npc.hotspot === undefined || npc.hotspot === '') {
            errors.push({
                tier: '0b',
                npc: npc.name,
                reason: '<npc name="' + npc.name + '"> 缺 hotspot 属性'
            });
            continue;
        }

        // 档 4: XML <npc> 不得带 x / y
        if (npc.hasX || npc.hasY) {
            errors.push({
                tier: 4,
                npc: npc.name,
                reason: '<npc> 节点带有 x 或 y 属性 — Stage A 已废弃这两个字段, 请删除'
            });
            continue;
        }

        // 档 1: hotspot 必须在 panel 数据中存在
        const hsHit = findHotspotInAnyPage(MapPanelData, npc.hotspot);
        if (!hsHit) {
            errors.push({
                tier: 1,
                npc: npc.name,
                reason: 'XML.hotspot="' + npc.hotspot + '" 不在 launcher panel 数据任一 page 的 hotspots 内'
            });
            continue;
        }

        // 档 2: npcKey 在 launcher slot 中能匹配
        const npcKey = normalizeNpcMarkerKey(npc.name);
        const slotHit = findSlotForNpcKey(MapPanelData, npcKey);
        if (!slotHit) {
            errors.push({
                tier: 2,
                npc: npc.name,
                reason: 'normalizeNpcMarkerKey("' + npc.name + '")="' + npcKey + '" 未匹配 launcher 任一 staticAvatars / dynamicAvatars slot'
            });
            continue;
        }

        // 档 3: slot.hotspotId 必须 === XML.npc.hotspot
        if (slotHit.slot.hotspotId !== npc.hotspot) {
            errors.push({
                tier: 3,
                npc: npc.name,
                reason: 'XML.hotspot="' + npc.hotspot + '" 与 launcher slot.hotspotId="' + slotHit.slot.hotspotId + '" 不一致 (slot 位于 page "' + slotHit.pageId + '" 的 ' + slotHit.kind + 'Avatars)'
            });
            continue;
        }

        ok.push({
            npc: npc.name,
            hotspot: npc.hotspot,
            matched: slotHit.kind + ':' + (slotHit.slot.id || slotHit.slot.label || '?'),
            page: slotHit.pageId
        });
    }

    // 档 0d: REQUIRED_NPC_NAMES 全部出现
    const missingRequired = [];
    for (let i = 0; i < REQUIRED_NPC_NAMES.length; i += 1) {
        const name = REQUIRED_NPC_NAMES[i];
        if (!nameOccurrences[name]) missingRequired.push(name);
    }
    if (missingRequired.length) {
        errors.push({
            tier: '0d',
            npc: '<canonical>',
            reason: 'REQUIRED_NPC_NAMES 缺失（AS2 端会 trace 同样的缺失并返回 false）: ' + missingRequired.join(', ')
        });
    }

    if (args.json) {
        process.stdout.write(JSON.stringify({
            ok: ok,
            errors: errors,
            total: npcs.length,
            requiredTotal: REQUIRED_NPC_NAMES.length,
            requiredMissing: missingRequired
        }, null, 2) + '\n');
    } else {
        console.log('XML <npc> audit: ' + npcs.length + ' total, ' + ok.length + ' OK, ' + errors.length + ' ERROR (required canonical: ' + REQUIRED_NPC_NAMES.length + ')');
        if (errors.length) {
            console.log('\nERRORS:');
            errors.forEach(function(e) {
                console.log('  [tier ' + e.tier + '] ' + e.npc + ' — ' + e.reason);
            });
        }
    }

    if (errors.length) process.exit(1);
}

main();
