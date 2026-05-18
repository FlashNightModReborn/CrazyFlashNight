#!/usr/bin/env node
'use strict';

// 对账 data/map/map_panel.xml 的 <npc> 列表 vs launcher 端 staticAvatars / dynamicAvatars。
//
// Stage A 重写：原 _root._mapRegisterTaskNpcMarker 是已下线 AS2 API，工具悄悄空转。
// 新版改读 XML 作为权威源，单向校验（XML → launcher）：
//
//   档 1 (ERROR): XML.npc.hotspot 必须命中 launcher panel 数据某个 hotspot id
//   档 2 (ERROR): XML.npc 的 normalizeNpcMarkerKey 必须在 launcher staticAvatars / dynamicAvatars 中匹配某个 slot
//   档 3 (ERROR): 匹配到的 slot.hotspotId 必须 === XML.npc.hotspot（Stage 0 已修完后这条全过）
//   档 4 (ERROR): XML <npc> 节点不得带 x / y 属性（Stage A 已删完）
//
// 反向方向（launcher staticAvatars 有 slot 但 XML 无 npc）**不在本工具职责**——
// 那是 Stage A.5 的 launcher-orphan 子集，由 source-data ↔ staticAvatars 漂移 audit 处理。

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const mapDataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const xmlFile = path.join(projectRoot, 'data', 'map', 'map_panel.xml');

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
    while ((m = npcRe.exec(raw)) !== null) {
        const inner = m[1];
        const attrs = {};
        attrRe.lastIndex = 0;
        let a;
        while ((a = attrRe.exec(inner)) !== null) {
            attrs[a[1]] = a[2];
        }
        if (attrs.name && attrs.hotspot) {
            npcs.push({
                name: attrs.name,
                hotspot: attrs.hotspot,
                hasX: attrs.x !== undefined,
                hasY: attrs.y !== undefined
            });
        }
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

    for (let i = 0; i < npcs.length; i += 1) {
        const npc = npcs[i];

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

    if (args.json) {
        process.stdout.write(JSON.stringify({ ok: ok, errors: errors, total: npcs.length }, null, 2) + '\n');
    } else {
        console.log('XML <npc> audit: ' + npcs.length + ' total, ' + ok.length + ' OK, ' + errors.length + ' ERROR');
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
