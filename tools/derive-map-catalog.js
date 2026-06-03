#!/usr/bin/env node
'use strict';

// 从 launcher/web/modules/map-panel-data.js 派生 AS2 端 MapPanelCatalog 启动期消费的
// 地图拓扑表（groups / hotspots）。等价于原 data/map/map_panel.xml 的 <groups>/<hotspots> 段。
// build.ps1 Step 1c 调用本脚本；失败则 exit 1 中断 build。
//
// SOT = MapPanelData 公开 API（不读私有 _unlockGroups/_pageUnlockGroups）：
//   - exportManifest().unlockGroups   → 8 个可锁 group 的 {id,conditionId,label,lockedReason}
//   - getPageOrder()                  → ['base','faction','defense','school']
//   - getPage(pageId).hotspots[]      → {id,label,sceneName,...}
//   - getHotspotUnlockGroup(page,id)  → hotspot 的 unlock group id（base 页恒空）
// 输出 = data/map/map_catalog.json，形如：
//   { groups:[{id,page,label,lockedReason?}], hotspots:[{id,group,frame}] }
//
// base 特例（与 map_panel.xml 旧手写一致）：
//   - base group 不在 web _unlockGroups 里 → 本脚本硬编码注入 {id:base,page:base,label:基地}（无 lockedReason）
//   - base 页所有 hotspot 的 unlock group 恒空 → 派生为 group="base"
//   - 非 base 页 hotspot 必须有非空 unlock group，否则 fail（gate）

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const dataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const avatarSourceFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-avatar-source-data.js');
const defaultOutput = path.join(projectRoot, 'data', 'map', 'map_catalog.json');

// base group：web _unlockGroups 不含（base 永解锁、无门控），硬编码注入。
const BASE_GROUP = { id: 'base', page: 'base', label: '基地' };
const VALID_PAGE_IDS = ['base', 'faction', 'defense', 'school'];

function parseArgs(argv) {
    const args = { output: defaultOutput };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--output') {
            args.output = argv[i + 1] || '';
            i += 1;
            continue;
        }
        if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        }
        printHelp(1, 'unknown arg: ' + arg);
        return null;
    }
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/derive-map-catalog.js [--output <file>]');
    console.error('  default output: ' + defaultOutput);
    process.exit(exitCode);
}

function loadMapData() {
    const sandbox = { console };
    vm.createContext(sandbox);
    // avatar source 先载入（map-panel-data.js 末尾 exportManifest 会引用；缺失时 graceful-null，
    // 但与 derive-task-npc-registry.js 保持一致以防未来强依赖）。
    if (fs.existsSync(avatarSourceFile)) {
        vm.runInContext(fs.readFileSync(avatarSourceFile, 'utf8'), sandbox, { filename: avatarSourceFile });
    }
    vm.runInContext(fs.readFileSync(dataFile, 'utf8'), sandbox, { filename: dataFile });
    if (!sandbox.MapPanelData) {
        throw new Error('MapPanelData not found in ' + dataFile);
    }
    return sandbox.MapPanelData;
}

function fail(msg) {
    console.error('[derive-map-catalog] ' + msg);
    process.exit(1);
}

// 反查每个可锁 group 归属的 page：扫所有 hotspot，要求同 group 的 hotspot page 一致。
function buildGroupPageMap(MapPanelData, order) {
    const groupPage = {};
    for (let i = 0; i < order.length; i += 1) {
        const pageId = order[i];
        const page = MapPanelData.getPage(pageId);
        if (!page) fail('getPage("' + pageId + '") returned falsy');
        const hotspots = page.hotspots || [];
        for (let j = 0; j < hotspots.length; j += 1) {
            const hid = hotspots[j].id;
            const g = MapPanelData.getHotspotUnlockGroup(pageId, hid);
            if (!g) continue; // base 页 / 无门控 hotspot，不参与 group→page 反查
            if (groupPage[g] === undefined) {
                groupPage[g] = pageId;
            } else if (groupPage[g] !== pageId) {
                fail('group "' + g + '" maps to multiple pages: "' + groupPage[g] + '" vs "' + pageId + '" (hotspot ' + hid + ')');
            }
        }
    }
    return groupPage;
}

function collectGroups(MapPanelData, order) {
    const manifest = MapPanelData.exportManifest();
    const unlockGroups = manifest.unlockGroups || {};
    const groupPage = buildGroupPageMap(MapPanelData, order);

    const groups = [BASE_GROUP];
    const seen = { base: true };

    const keys = Object.keys(unlockGroups);
    for (let i = 0; i < keys.length; i += 1) {
        const gid = keys[i];
        const def = unlockGroups[gid];
        if (!def || def.id !== gid) fail('unlockGroups["' + gid + '"].id mismatch');
        if (seen[gid]) fail('duplicate group id "' + gid + '"');
        if (!def.label) fail('group "' + gid + '" missing label');
        if (!def.lockedReason) fail('group "' + gid + '" missing lockedReason (non-base group required)');
        const page = groupPage[gid];
        if (!page) fail('group "' + gid + '" has no hotspot → cannot resolve page');
        if (VALID_PAGE_IDS.indexOf(page) < 0) fail('group "' + gid + '" page "' + page + '" invalid');
        seen[gid] = true;
        groups.push({ id: gid, page: page, label: String(def.label), lockedReason: String(def.lockedReason) });
    }
    return { groups, groupIdSet: seen };
}

function collectHotspots(MapPanelData, order, groupIdSet) {
    const hotspots = [];
    const idSet = {};
    for (let i = 0; i < order.length; i += 1) {
        const pageId = order[i];
        const page = MapPanelData.getPage(pageId);
        const list = page.hotspots || [];
        for (let j = 0; j < list.length; j += 1) {
            const h = list[j];
            const hid = h.id;
            if (!hid || typeof hid !== 'string') fail('hotspot missing id in page "' + pageId + '" index ' + j);
            if (idSet[hid]) fail('duplicate hotspot id "' + hid + '"');
            const frame = h.sceneName;
            if (!frame || typeof frame !== 'string') fail('hotspot "' + hid + '" missing sceneName (frame)');
            let group = MapPanelData.getHotspotUnlockGroup(pageId, hid);
            if (!group) {
                // 无门控：只允许出现在 base 页 → group=base；非 base 页无 group = 数据错，硬失败。
                if (pageId !== 'base') {
                    fail('hotspot "' + hid + '" on non-base page "' + pageId + '" has no unlock group');
                }
                group = 'base';
            }
            if (!groupIdSet[group]) fail('hotspot "' + hid + '" references unknown group "' + group + '"');
            idSet[hid] = true;
            hotspots.push({ id: hid, group: group, frame: String(frame) });
        }
    }
    return hotspots;
}

// 比对实质内容（groups + hotspots + _source + _note）是否与旧 payload 一致。
// 一致就保留旧 _generatedAt + 跳过写盘——避免 build.ps1 / git 看到无意义 mtime/diff。
function stableSubset(payload) {
    return {
        _source: payload._source,
        _note: payload._note,
        groups: payload.groups,
        hotspots: payload.hotspots
    };
}

function tryReadExistingPayload(outputPath) {
    try {
        if (!fs.existsSync(outputPath)) return null;
        return JSON.parse(fs.readFileSync(outputPath, 'utf8'));
    } catch (e) {
        return null;
    }
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;

    const MapPanelData = loadMapData();
    const order = MapPanelData.getPageOrder();
    if (!order || !order.length) fail('getPageOrder() returned empty');

    const { groups, groupIdSet } = collectGroups(MapPanelData, order);
    const hotspots = collectHotspots(MapPanelData, order, groupIdSet);

    const newPayload = {
        _generatedAt: new Date().toISOString(),
        _source: 'launcher/web/modules/map-panel-data.js',
        _note: 'generated by tools/derive-map-catalog.js, do not hand-edit',
        groups: groups,
        hotspots: hotspots
    };

    const outDir = path.dirname(args.output);
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

    const oldPayload = tryReadExistingPayload(args.output);
    if (oldPayload && JSON.stringify(stableSubset(oldPayload)) === JSON.stringify(stableSubset(newPayload))) {
        console.log('[derive-map-catalog] unchanged (' + groups.length + ' groups + ' + hotspots.length + ' hotspots), kept _generatedAt=' + (oldPayload._generatedAt || '<none>'));
        return;
    }

    fs.writeFileSync(args.output, JSON.stringify(newPayload, null, 2) + '\n', 'utf8');
    console.log('[derive-map-catalog] wrote ' + groups.length + ' groups + ' + hotspots.length + ' hotspots → ' + args.output);
}

main();
