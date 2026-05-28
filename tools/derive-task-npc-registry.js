#!/usr/bin/env node
'use strict';

// 从 launcher/web/modules/map-panel-data.js 的 staticAvatars + dynamicAvatars 派生
// AS2 端 MapTaskNpcRegistry 启动期消费的 NPC↔hotspot 表。
// build.ps1 在出 launcher 产物前调用本脚本；失败则 exit 1 中断 build。
//
// SOT = MapPanelData.getPage(id).staticAvatars/.dynamicAvatars (label, hotspotId)
// 输出 = data/map/task_npc_registry.json
//
// alias 段当前仅 1 条，hardcode 在本文件顶部。未来 alias 增多再独立 JSON。

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const dataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const avatarSourceFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-avatar-source-data.js');
const defaultOutput = path.join(projectRoot, 'data', 'map', 'task_npc_registry.json');

// 任务字符串非正式拼写 → canonical 映射。
// 历史由 data/map/map_panel.xml 的 <alias> 段维护，现统一在派生脚本里硬编码。
const ALIASES = [
    { name: '∞天ㄙ★使的剪∞', canonical: '杀马特' }
];

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
    console.error('usage: node tools/derive-task-npc-registry.js [--output <file>]');
    console.error('  default output: ' + defaultOutput);
    process.exit(exitCode);
}

function loadMapData() {
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync(avatarSourceFile, 'utf8'), sandbox, { filename: avatarSourceFile });
    vm.runInContext(fs.readFileSync(dataFile, 'utf8'), sandbox, { filename: dataFile });
    if (!sandbox.MapPanelData) {
        throw new Error('MapPanelData not found in ' + dataFile);
    }
    return sandbox.MapPanelData;
}

function fail(msg) {
    console.error('[derive-task-npc-registry] ' + msg);
    process.exit(1);
}

function collectTaskNpcs(MapPanelData) {
    const order = MapPanelData.getPageOrder();
    const allHotspotIds = {};
    const allIds = MapPanelData.getAllHotspotIds();
    for (let i = 0; i < allIds.length; i += 1) allHotspotIds[allIds[i]] = true;

    const npcs = [];
    const nameSet = new Set();
    const nameLowerSet = new Map(); // lower → original

    function addOne(label, hotspotId, originPage, originKind) {
        if (!label || typeof label !== 'string') {
            fail('empty label in ' + originPage + '.' + originKind);
        }
        if (!hotspotId || typeof hotspotId !== 'string') {
            fail('empty hotspotId for label="' + label + '" in ' + originPage + '.' + originKind);
        }
        if (!allHotspotIds[hotspotId]) {
            fail('hotspotId "' + hotspotId + '" (label="' + label + '") not in MapPanelData hotspot set');
        }
        if (nameSet.has(label)) {
            fail('duplicate NPC label "' + label + '" (originPage=' + originPage + ')');
        }
        const lower = label.toLowerCase();
        if (nameLowerSet.has(lower) && nameLowerSet.get(lower) !== label) {
            fail('NPC label "' + label + '" collides with "' + nameLowerSet.get(lower) + '" on lowercase fold');
        }
        nameSet.add(label);
        nameLowerSet.set(lower, label);
        npcs.push({ name: label, hotspot: hotspotId });
    }

    for (let i = 0; i < order.length; i += 1) {
        const pageId = order[i];
        const page = MapPanelData.getPage(pageId);
        if (!page) fail('getPage("' + pageId + '") returned falsy');

        const statics = page.staticAvatars || [];
        for (let j = 0; j < statics.length; j += 1) {
            addOne(statics[j].label, statics[j].hotspotId, pageId, 'staticAvatars');
        }
        const dynamics = page.dynamicAvatars || [];
        for (let j = 0; j < dynamics.length; j += 1) {
            addOne(dynamics[j].label, dynamics[j].hotspotId, pageId, 'dynamicAvatars');
        }
    }

    return { npcs, nameSet };
}

function validateAliases(nameSet) {
    const seenAliasName = new Set();
    for (let i = 0; i < ALIASES.length; i += 1) {
        const a = ALIASES[i];
        if (!a.name || !a.canonical) fail('alias[' + i + '] missing name/canonical');
        if (nameSet.has(a.name)) fail('alias name "' + a.name + '" collides with existing NPC');
        if (seenAliasName.has(a.name)) fail('duplicate alias name "' + a.name + '"');
        if (!nameSet.has(a.canonical)) {
            fail('alias "' + a.name + '" canonical "' + a.canonical + '" not in NPC set');
        }
        seenAliasName.add(a.name);
    }
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;

    const MapPanelData = loadMapData();
    const { npcs, nameSet } = collectTaskNpcs(MapPanelData);
    validateAliases(nameSet);

    const payload = {
        _generatedAt: new Date().toISOString(),
        _source: 'launcher/web/modules/map-panel-data.js',
        _note: 'generated by tools/derive-task-npc-registry.js, do not hand-edit',
        task_npcs: npcs,
        aliases: ALIASES
    };

    const outDir = path.dirname(args.output);
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(args.output, JSON.stringify(payload, null, 2) + '\n', 'utf8');

    console.log('[derive-task-npc-registry] wrote ' + npcs.length + ' task_npcs + ' + ALIASES.length + ' aliases → ' + args.output);
}

main();
