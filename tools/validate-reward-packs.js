#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ITEM_DIR = path.join(ROOT, 'data', 'items');
const MODES = new Set(['fixed', 'independent', 'chooseOne']);
const ENTRY_FIELDS = new Set([
    'itemName',
    'quantityMin',
    'quantityMax',
    'chanceNumerator',
    'chanceDenominator',
    'weight'
]);
const GRENADE_FIELDS = [
    'dressup', 'capacity', 'split', 'diffusion', 'interval', 'velocity',
    'bullet', 'sound', 'muzzle', 'bullethit', 'clipname', 'bulletsize',
    'power', 'impact'
];
const errors = [];
let onlineSupplyValidated = false;

function fail(message) {
    errors.push(message);
}

function readText(file) {
    try {
        return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
    } catch (error) {
        fail(path.relative(ROOT, file) + ': cannot read: ' + error.message);
        return '';
    }
}

function decodeXmlText(value) {
    return String(value || '')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&amp;/g, '&');
}

function textOf(xml, tag) {
    const match = new RegExp('<' + tag + '>\\s*([\\s\\S]*?)\\s*</' + tag + '>').exec(String(xml || ''));
    return match ? decodeXmlText(match[1].trim()) : '';
}

function blocksOf(xml, tag) {
    const blocks = [];
    const re = new RegExp('<' + tag + '\\b[^>]*>([\\s\\S]*?)</' + tag + '>', 'g');
    let match;
    while ((match = re.exec(String(xml || ''))) !== null) blocks.push(match[1]);
    return blocks;
}

function positiveInteger(text) {
    return /^[1-9]\d*$/.test(String(text || '').trim());
}

function present(xml, tag) {
    return new RegExp('<' + tag + '(?:>|\\s|/)').test(String(xml || ''));
}

function requireText(source, context, expected) {
    if (!String(source || '').includes(expected)) {
        fail(context + ': missing required integration text "' + expected + '"');
    }
}

function forbidText(source, context, forbidden) {
    if (String(source || '').includes(forbidden)) {
        fail(context + ': forbidden legacy integration text "' + forbidden + '"');
    }
}

function validateOnlineSupplyIntegration() {
    const treePath = path.join(ROOT, 'flashswf', 'levels', '基地场景合集',
        'LIBRARY', '地图', '基地1层.xml');
    const frameTimerPath = path.join(ROOT, 'scripts', '通信', '通信_fs_帧计时器.as');
    const cheatPath = path.join(ROOT, 'scripts', '引擎', '引擎_aka_作弊码.as');
    const settingsPath = path.join(ROOT, 'scripts', '类定义', 'org', 'flashNight',
        'arki', 'ui', 'GameSettingsPanelService.as');
    const inboxPath = path.join(ROOT, 'scripts', '类定义', 'org', 'flashNight',
        'arki', 'item', 'RewardInboxService.as');
    const helpPath = path.join(ROOT, 'launcher', 'web', 'help', 'cheat-codes.md');
    const tree = readText(treePath);
    const frameTimer = readText(frameTimerPath);
    const cheat = readText(cheatPath);
    const settings = readText(settingsPath);
    const inbox = readText(inboxPath);
    const help = readText(helpPath);

    ['new Date()', '.getTime()', '节日补给配置', 'startTimestamp', 'endTimestamp']
        .forEach((legacy) => forbidText(tree, '基地1层圣诞树', legacy));
    [
        '_root.帧计时器.获取在线补给帧数()',
        '_root.主线任务进度 > 28',
        'onClipEvent (enterFrame)',
        '当前窗口已投送',
        '新来源键 != 当前来源键',
        '10 * 60 * 帧率',
        '20 * 60 * 帧率',
        '40 * 60 * 帧率',
        '60 * 60 * 帧率',
        '120 * 60 * 帧率'
    ].forEach((required) => requireText(tree, '基地1层圣诞树', required));
    const supplyPairs = [
        [10, '在线补给包·Ⅰ'], [20, '在线补给包·Ⅱ'], [40, '在线补给包·Ⅲ'],
        [60, '在线补给包·Ⅳ'], [120, '在线补给包·Ⅴ']
    ];
    supplyPairs.forEach(([minutes, pack]) => {
        requireText(tree, '基地1层圣诞树',
            'sourceKey:"christmas_tree:online-' + minutes + 'm", packName:"' + pack + '"');
    });

    ['this.在线补给起始帧', 'this.在线补给测试偏移帧',
        'this.获取在线补给帧数', 'this.设置在线补给测试分钟',
        'normalized > 1440']
        .forEach((required) => requireText(frameTimer, '在线补给帧计时器', required));
    const setterStart = frameTimer.indexOf('this.设置在线补给测试分钟');
    const setterEnd = frameTimer.indexOf('this.异常间隔帧数', setterStart);
    const setterBody = setterStart >= 0 && setterEnd > setterStart
        ? frameTimer.slice(setterStart, setterEnd) : '';
    if (/this\.当前帧数\s*=/.test(setterBody)) {
        fail('在线补给帧计时器: test cheat must not mutate the global current frame');
    }

    ['#supplytime:', '设置在线补给测试分钟', '0 至 1440']
        .forEach((required) => requireText(cheat, '在线补给作弊码', required));
    ['{command:"#supplytime:10"', 'startsWith(command, "#supplytime:")',
        'effectScope:"session"']
        .forEach((required) => requireText(settings, 'Settings 作弊契约', required));
    ['在线补给包已投送', 'hasDeliveredOnlineSupplyPack',
        '_supplySessionToken', 'supplySessionPrefix()', 'isOnlineSupplyPair',
        'isOnlineSupplySourceKey',
        '!containsPrefix(feature.supplyKeys, sessionPrefix)',
        'feature.supplyKeys = []']
        .forEach((required) => requireText(inbox, '在线补给幂等探针', required));
    ['Math.floor(timestamp / 1000000)',
        'timestamp - high * 1000000',
        'high.toString(36)', 'low.toString(36)']
        .forEach((required) => requireText(inbox, '在线补给会话标识', required));
    if (/new Date\(\)\.getTime\(\)[\s\S]{0,240}\.toString\(36\)/.test(inbox)
            || inbox.includes('tokenNumber.toString(36)')) {
        fail('在线补给会话标识: AVM1 must not encode the full millisecond timestamp as one base36 integer');
    }
    [10, 20, 40, 60, 120].forEach((minutes) => {
        requireText(inbox, '在线补给幂等探针',
            'christmas_tree:online-' + minutes + 'm');
    });
    supplyPairs.forEach(([minutes, pack]) => {
        requireText(inbox, '在线补给幂等探针',
            'sourceKey == "christmas_tree:online-' + minutes + 'm" && name == "' + pack + '"');
    });
    const capacityFence = inbox.indexOf('if (remainingCount(feature) >= MAX_OCCURRENCES)');
    const rollbackSnapshot = inbox.indexOf('var featureBefore:Object = ObjectUtil.clone(feature)');
    const sessionIndexReplacement = inbox.indexOf(
        'if (!containsPrefix(feature.supplyKeys, sessionPrefix)) feature.supplyKeys = []');
    if (!(capacityFence >= 0 && rollbackSnapshot > capacityFence
            && sessionIndexReplacement > rollbackSnapshot)) {
        fail('在线补给幂等探针: capacity must reject before the rollback-covered session-index replacement');
    }
    const resetSessionStart = inbox.indexOf('public static function resetSession()');
    const resetSessionEnd = inbox.indexOf('/**', resetSessionStart + 1);
    const resetSessionBody = resetSessionStart >= 0 && resetSessionEnd > resetSessionStart
        ? inbox.slice(resetSessionStart, resetSessionEnd) : '';
    if (resetSessionBody.includes('_supplySessionToken')) {
        fail('在线补给幂等探针: save switching must not rotate the Flash-run supply token');
    }
    ['#supplytime:10', '不改全局帧时间、冷却或调度']
        .forEach((required) => requireText(help, '作弊码帮助', required));
    onlineSupplyValidated = true;
}

const manifest = readText(path.join(ITEM_DIR, 'list.xml'));
const files = [];
const manifestRe = /<items>\s*([^<]+?)\s*<\/items>/g;
let manifestMatch;
while ((manifestMatch = manifestRe.exec(manifest)) !== null) files.push(manifestMatch[1].trim());
if (files.length === 0) fail('data/items/list.xml: no <items> entries');

const items = [];
const itemByName = new Map();
files.forEach((relativeFile) => {
    const source = path.join(ITEM_DIR, relativeFile);
    const xml = readText(source).replace(/<!--[\s\S]*?-->/g, '');
    blocksOf(xml, 'item').forEach((raw, index) => {
        const name = textOf(raw, 'name');
        const context = 'data/items/' + relativeFile + ' / item #' + (index + 1);
        if (!name) {
            fail(context + ': missing <name>');
            return;
        }
        const item = {name, use:textOf(raw, 'use'), raw, context:context + ' / ' + name};
        if (!itemByName.has(name)) itemByName.set(name, []);
        itemByName.get(name).push(item);
        items.push(item);
    });
});

let packCount = 0;
let entryCount = 0;
const modeCounts = {fixed:0, independent:0, chooseOne:0};

items.forEach((item) => {
    const rewardPacks = blocksOf(item.raw, 'rewardPack');
    if (item.use !== '礼包') {
        if (rewardPacks.length > 0) fail(item.context + ': <rewardPack> requires <use>礼包</use>');
        return;
    }

    packCount += 1;
    if (rewardPacks.length !== 1) {
        fail(item.context + ': must declare exactly one <rewardPack>');
        return;
    }
    const dataBlocks = blocksOf(item.raw, 'data');
    if (dataBlocks.length !== 1
            || blocksOf(dataBlocks[0], 'rewardPack').length !== 1) {
        fail(item.context + ': <rewardPack> must be the single runtime <data> child');
        return;
    }
    GRENADE_FIELDS.forEach((field) => {
        if (present(item.raw, field)) fail(item.context + ': legacy grenade field <' + field + '> is forbidden');
    });

    const rewardPack = rewardPacks[0];
    const mode = textOf(rewardPack, 'mode');
    if (!MODES.has(mode)) {
        fail(item.context + ': unsupported rewardPack mode "' + mode + '"');
        return;
    }
    modeCounts[mode] += 1;

    const entriesBlocks = blocksOf(rewardPack, 'entries');
    if (entriesBlocks.length !== 1) {
        fail(item.context + ': rewardPack must declare exactly one <entries> wrapper');
        return;
    }
    const entries = blocksOf(entriesBlocks[0], 'entry');
    if (entries.length === 0) {
        fail(item.context + ': rewardPack entries must not be empty');
        return;
    }

    entries.forEach((entry, index) => {
        entryCount += 1;
        const context = item.context + ' / entry #' + (index + 1);
        const fields = [];
        const fieldRe = /<([A-Za-z][A-Za-z0-9_]*)\b[^>]*>/g;
        let fieldMatch;
        while ((fieldMatch = fieldRe.exec(entry)) !== null) fields.push(fieldMatch[1]);
        fields.forEach((field) => {
            if (!ENTRY_FIELDS.has(field)) fail(context + ': unknown field <' + field + '>');
        });

        const itemName = textOf(entry, 'itemName');
        const quantityMinText = textOf(entry, 'quantityMin');
        const quantityMaxText = textOf(entry, 'quantityMax');
        if (!itemName) fail(context + ': itemName must not be empty');
        else if (!itemByName.has(itemName)) fail(context + ': unknown exact itemName "' + itemName + '"');
        else if (itemByName.get(itemName).length !== 1) {
            fail(context + ': ambiguous exact itemName "' + itemName + '" has ' +
                itemByName.get(itemName).length + ' active definitions');
        }
        if (!positiveInteger(quantityMinText)) fail(context + ': quantityMin must be a positive integer');
        if (!positiveInteger(quantityMaxText)) fail(context + ': quantityMax must be a positive integer');
        if (positiveInteger(quantityMinText) && positiveInteger(quantityMaxText)
                && Number(quantityMinText) > Number(quantityMaxText)) {
            fail(context + ': quantityMin must be <= quantityMax');
        }

        const numeratorText = textOf(entry, 'chanceNumerator');
        const denominatorText = textOf(entry, 'chanceDenominator');
        const weightText = textOf(entry, 'weight');
        if (mode === 'independent') {
            if (!positiveInteger(numeratorText)) fail(context + ': independent chanceNumerator must be a positive integer');
            if (!positiveInteger(denominatorText)) fail(context + ': independent chanceDenominator must be a positive integer');
            if (positiveInteger(numeratorText) && positiveInteger(denominatorText)
                    && Number(numeratorText) > Number(denominatorText)) {
                fail(context + ': chanceNumerator must be <= chanceDenominator');
            }
            if (weightText) fail(context + ': independent entry must not declare weight');
        } else if (mode === 'chooseOne') {
            if (!positiveInteger(weightText)) fail(context + ': chooseOne weight must be a positive integer');
            if (numeratorText || denominatorText) fail(context + ': chooseOne entry must not declare chance fields');
        } else if (numeratorText || denominatorText || weightText) {
            fail(context + ': fixed entry must not declare chance or weight fields');
        }
    });
});

validateOnlineSupplyIntegration();

if (errors.length > 0) {
    errors.forEach((message) => process.stderr.write('[reward-packs] ERROR: ' + message + '\n'));
    process.stderr.write('[reward-packs] FAIL (' + errors.length + ' error(s))\n');
    process.exit(1);
}

process.stdout.write(
    '[reward-packs] OK: ' + packCount + ' packs, ' + entryCount + ' entries; ' +
    'fixed=' + modeCounts.fixed + ', independent=' + modeCounts.independent +
    ', chooseOne=' + modeCounts.chooseOne + '; onlineSupply=' +
    (onlineSupplyValidated ? 'frame-clock/5-windows/session-bounded' : 'unvalidated') + '\n'
);
