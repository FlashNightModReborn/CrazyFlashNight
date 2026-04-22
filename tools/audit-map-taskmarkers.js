#!/usr/bin/env node
'use strict';

// 对账 AS2 _mapRegisterTaskNpcMarker 登记 vs Web 侧静态/动态头像槽。
// 目的：任务环锚点优先落到头像中心（findAvatarAnchorForMarker），如果 AS2 npcName
// 在对应页面没有任何一个头像槽能通过 normalizeNpcMarkerKey 匹配上，ring 只能回退到
// marker.point 或 hotspot 中心——室友错位就是这条退化路径。
// 失败分级：
//   ERROR  — pageId/hotspotId 与 Web 数据不匹配（会让 ring 被页面过滤掉）
//   WARN   — npcKey 没在任何头像槽命中（ring 落到硬编码 point，对未来头像重定位不稳）

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const mapDataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const as2File = path.join(projectRoot, 'scripts', '逻辑系统分区', '地图系统_WebView.as');

function parseArgs(argv) {
    const args = { json: false, failOnWarn: false };
    for (let i = 0; i < argv.length; i += 1) {
        const a = argv[i];
        if (a === '--json') args.json = true;
        else if (a === '--fail-on-warn') args.failOnWarn = true;
        else if (a === '--help' || a === '-h') {
            console.error('usage: node tools/audit-map-taskmarkers.js [--json] [--fail-on-warn]');
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

// 与 map-panel.js 保持一致（normalizeNpcMarkerKey + getSlotNpcKeys）
function normalizeNpcMarkerKey(value) {
    return String(value || '')
        .replace(/^task_npc_/, '')
        .replace(/\s+/g, '')
        .replace(/[·•]/g, '')
        .toLowerCase();
}

function getSlotNpcKeys(slot) {
    const keys = [];
    if (!slot) return keys;
    if (slot.label) keys.push(normalizeNpcMarkerKey(slot.label));
    if (slot.id) keys.push(normalizeNpcMarkerKey(slot.id));
    if (slot.assetUrl) keys.push(normalizeNpcMarkerKey(slot.assetUrl));
    if (slot.label === '杀马特') keys.push(normalizeNpcMarkerKey('∞天ㄙ★使的剪∞'));
    return keys;
}

function parseAS2Markers() {
    const source = fs.readFileSync(as2File, 'utf8');

    const aliases = {};
    const aliasRe = /_root\._mapTaskNpcAliases\[\s*"([^"]+)"\s*\]\s*=\s*"([^"]+)"\s*;/g;
    let m;
    while ((m = aliasRe.exec(source)) !== null) {
        aliases[m[1]] = m[2];
    }

    const markers = [];
    const markerRe = /_root\._mapRegisterTaskNpcMarker\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)/g;
    while ((m = markerRe.exec(source)) !== null) {
        markers.push({
            npcName: m[1],
            pageId: m[2],
            hotspotId: m[3],
            x: Number(m[4]),
            y: Number(m[5])
        });
    }

    return { aliases, markers };
}

function findHotspotOnPage(page, hotspotId) {
    const hotspots = (page && page.hotspots) || [];
    for (let i = 0; i < hotspots.length; i += 1) {
        if (hotspots[i].id === hotspotId) return hotspots[i];
    }
    return null;
}

function findMatchingSlot(page, npcKey) {
    const groups = [
        { list: (page && page.staticAvatars) || [], kind: 'static' },
        { list: (page && page.dynamicAvatars) || [], kind: 'dynamic' }
    ];
    for (let g = 0; g < groups.length; g += 1) {
        const list = groups[g].list;
        for (let i = 0; i < list.length; i += 1) {
            const keys = getSlotNpcKeys(list[i]);
            for (let j = 0; j < keys.length; j += 1) {
                if (keys[j] && keys[j] === npcKey) {
                    return { slot: list[i], kind: groups[g].kind };
                }
            }
        }
    }
    return null;
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    const MapPanelData = loadMapPanelData();
    const { aliases, markers } = parseAS2Markers();

    const errors = [];
    const warnings = [];
    const ok = [];

    for (let i = 0; i < markers.length; i += 1) {
        const marker = markers[i];
        const canonicalName = aliases[marker.npcName] || marker.npcName;
        const npcKey = normalizeNpcMarkerKey(canonicalName);
        const page = MapPanelData.getPage ? MapPanelData.getPage(marker.pageId) : null;

        if (!page || page.id !== marker.pageId) {
            errors.push({
                marker: marker,
                reason: 'page not found in MapPanelData: ' + marker.pageId
            });
            continue;
        }

        const hotspot = findHotspotOnPage(page, marker.hotspotId);
        if (!hotspot) {
            errors.push({
                marker: marker,
                reason: 'hotspot "' + marker.hotspotId + '" not on page "' + marker.pageId + '" (ring will be filtered by visibleLookup)'
            });
            continue;
        }

        const match = findMatchingSlot(page, npcKey);
        if (match) {
            ok.push({ marker: marker, matched: match.kind + ':' + (match.slot.id || match.slot.label || '?') });
        } else {
            warnings.push({
                marker: marker,
                npcKey: npcKey,
                reason: 'no static/dynamic avatar slot matches npcKey="' + npcKey + '" on page "' + marker.pageId + '" — ring falls back to hardcoded point (' + marker.x + ',' + marker.y + ')'
            });
        }
    }

    if (args.json) {
        process.stdout.write(JSON.stringify({ ok, warnings, errors }, null, 2) + '\n');
    } else {
        console.log('task marker audit: ' + markers.length + ' registered, ' + ok.length + ' matched, ' + warnings.length + ' warn, ' + errors.length + ' error');
        if (errors.length) {
            console.log('\nERRORS:');
            errors.forEach(function(e) {
                console.log('  [' + e.marker.pageId + '/' + e.marker.hotspotId + '] ' + e.marker.npcName + ' — ' + e.reason);
            });
        }
        if (warnings.length) {
            console.log('\nWARNINGS:');
            warnings.forEach(function(w) {
                console.log('  [' + w.marker.pageId + '/' + w.marker.hotspotId + '] ' + w.marker.npcName + ' — ' + w.reason);
            });
        }
    }

    if (errors.length) process.exit(1);
    if (args.failOnWarn && warnings.length) process.exit(1);
}

main();
