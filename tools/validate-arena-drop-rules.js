#!/usr/bin/env node
'use strict';

// 对账竞技场 XML、当前佣兵预设、物品目录与 AS2 接线。
// 这里的旧关键词只作为迁移等价性 oracle；运行时唯一真源是 arena_drop_rules.xml。

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const XML_PATH = path.join(ROOT, 'data', 'arena', 'arena_drop_rules.xml');
const MERC_PATH = path.join(ROOT, 'data', 'merc', 'mercenaries.json');
const ITEM_LIST_PATH = path.join(ROOT, 'data', 'items', 'list.xml');
const SCENE_PATH = path.join(ROOT, 'scripts', '逻辑', '关卡系统',
    '关卡系统_lsy_场景转换.as');
const BOOT_PATH = path.join(ROOT, 'scripts', '类定义', 'org', 'flashNight',
    'boot', 'BootSequencer.as');
const INDEX_PATH = path.join(ROOT, 'scripts', '类定义', 'org', 'flashNight',
    'arki', 'item', 'obtain', 'ItemObtainIndex.as');
const LOADER_PATH = path.join(ROOT, 'scripts', '类定义', 'org', 'flashNight',
    'gesh', 'xml', 'LoadXml', 'ArenaDropRulesLoader.as');
const TOOLTIP_PATH = path.join(ROOT, 'scripts', '类定义', 'org', 'flashNight',
    'gesh', 'tooltip', 'builder', 'ObtainMethodsBuilder.as');
const RELEASE_POLICY_PATH = path.join(ROOT, 'tools',
    'validate-launcher-release-policy.ps1');

const LEGACY_FAMILY_TOKENS = [
    '次品蓝晶', '巨兽', '冰魄斩', '合金',
    '烈焰', '异形', '巴雷特', '方舟武士'
];
const SLOT_TO_MERC_KEY = Object.freeze({
    '长枪':'primary',
    '刀':'melee',
    '头部装备':'head',
    '上装装备':'body',
    '下装装备':'leg',
    '手部装备':'hand',
    '脚部装备':'foot'
});

function fail(message) {
    throw new Error(message);
}

function decodeXml(value) {
    return String(value)
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&');
}

function parseAttributes(source, label) {
    const attrs = {};
    let rest = source.trim();
    while (rest) {
        const match = /^([A-Za-z_][A-Za-z0-9_.-]*)\s*=\s*"([^"]*)"\s*/.exec(rest);
        if (!match) fail(label + ': malformed attribute text: ' + rest);
        if (Object.prototype.hasOwnProperty.call(attrs, match[1])) {
            fail(label + ': duplicate attribute ' + match[1]);
        }
        attrs[match[1]] = decodeXml(match[2]);
        rest = rest.slice(match[0].length);
    }
    return attrs;
}

function parseXml(source) {
    let text = source.replace(/^\uFEFF/, '');
    text = text.replace(/^\s*<\?xml[^?]*\?>\s*/, '');
    text = text.replace(/<!--[\s\S]*?-->/g, '');
    if (text.includes('<!') || text.includes('<?')) fail('unsupported XML declaration');

    const tokens = text.match(/<[^>]+>|[^<]+/g) || [];
    const stack = [];
    let root = null;
    for (const token of tokens) {
        if (token[0] !== '<') {
            if (token.trim()) fail('text nodes are not allowed in arena_drop_rules.xml');
            continue;
        }
        if (/^<\//.test(token)) {
            const close = /^<\/([A-Za-z_][A-Za-z0-9_.-]*)\s*>$/.exec(token);
            if (!close || !stack.length || stack[stack.length - 1].name !== close[1]) {
                fail('mismatched closing tag: ' + token);
            }
            stack.pop();
            continue;
        }
        const selfClosing = /\/\s*>$/.test(token);
        const open = /^<([A-Za-z_][A-Za-z0-9_.-]*)([\s\S]*?)(?:\/\s*>|>)$/.exec(token);
        if (!open) fail('malformed opening tag: ' + token);
        const node = {
            name:open[1],
            attrs:parseAttributes(open[2], '<' + open[1] + '>'),
            children:[]
        };
        if (stack.length) stack[stack.length - 1].children.push(node);
        else if (root == null) root = node;
        else fail('multiple XML roots');
        if (!selfClosing) stack.push(node);
    }
    if (stack.length) fail('unclosed tag: ' + stack[stack.length - 1].name);
    if (root == null) fail('missing XML root');
    return root;
}

function children(node, name) {
    return node.children.filter(child => child.name === name);
}

function onlyChildNames(node, allowed) {
    for (const child of node.children) {
        if (!allowed.includes(child.name)) {
            fail('<' + node.name + '> has unsupported child <' + child.name + '>');
        }
    }
}

function exactAttributes(node, required, optional) {
    const allowed = required.concat(optional || []);
    for (const key of Object.keys(node.attrs)) {
        if (!allowed.includes(key)) fail('<' + node.name + '> has unsupported attribute ' + key);
    }
    for (const key of required) {
        if (!Object.prototype.hasOwnProperty.call(node.attrs, key)
                || node.attrs[key] === '') {
            fail('<' + node.name + '> missing attribute ' + key);
        }
    }
}

function exactSet(actualValues, expectedValues, label) {
    const actual = [...new Set(actualValues)].sort();
    const expected = [...new Set(expectedValues)].sort();
    if (actualValues.length !== actual.length) fail(label + ': duplicate values');
    if (actual.length !== expected.length
            || actual.some((value, index) => value !== expected[index])) {
        fail(label + ': exact-set mismatch\nactual=' + actual.join('|')
            + '\nexpected=' + expected.join('|'));
    }
}

function numberAttr(node, name, min, max, integer) {
    const value = Number(node.attrs[name]);
    if (!Number.isFinite(value) || value < min || value > max
            || (integer && Math.floor(value) !== value)) {
        fail('<' + node.name + '> invalid ' + name + '=' + node.attrs[name]);
    }
    return value;
}

function validateRuleShape(rule) {
    exactAttributes(rule, ['id', 'stopOnMatch', 'carrierScope']);
    if (rule.attrs.stopOnMatch !== 'true') fail(rule.attrs.id + ': stopOnMatch must be true');
    if (!['carrier', 'specific_carrier'].includes(rule.attrs.carrierScope)) {
        fail(rule.attrs.id + ': unsupported carrierScope');
    }
    onlyChildNames(rule, ['Trigger', 'Drop', 'SlotLottery', 'EligibleItem']);
    const triggers = children(rule, 'Trigger');
    const drops = children(rule, 'Drop');
    const lotteries = children(rule, 'SlotLottery');
    const eligible = children(rule, 'EligibleItem');
    if (!triggers.length || !eligible.length || (!drops.length && !lotteries.length)) {
        fail(rule.attrs.id + ': incomplete rule shape');
    }
    if (lotteries.length > 1) fail(rule.attrs.id + ': only one SlotLottery is supported');
    for (const trigger of triggers) {
        exactAttributes(trigger, ['slot', 'item']);
        if (trigger.children.length) fail('<Trigger> must be self-closing');
    }
    for (const drop of drops) {
        exactAttributes(drop, ['slot', 'chancePercent']);
        numberAttr(drop, 'chancePercent', 0, 100, false);
        if (drop.children.length) fail('<Drop> must be self-closing');
    }
    for (const item of eligible) {
        exactAttributes(item, ['name', 'slot']);
        if (!SLOT_TO_MERC_KEY[item.attrs.slot]) {
            fail('unsupported EligibleItem slot: ' + item.attrs.slot);
        }
        if (item.children.length) fail('<EligibleItem> must be self-closing');
    }
    return {triggers, drops, lottery:lotteries[0] || null, eligible};
}

function validateAuthoredContract(root) {
    if (root.name !== 'ArenaDropRules') fail('root must be <ArenaDropRules>');
    exactAttributes(root, ['schemaVersion']);
    if (root.attrs.schemaVersion !== '1') fail('schemaVersion must be 1');
    onlyChildNames(root, ['Profile']);
    const profiles = children(root, 'Profile');
    if (profiles.length !== 1) fail('exactly one Profile is required');
    const profile = profiles[0];
    exactAttributes(profile, ['id', 'arenaId', 'arenaLabel', 'modeLabel']);
    if (profile.attrs.id !== 'standard_merc'
            || profile.attrs.arenaId !== 'death_match'
            || profile.attrs.arenaLabel !== 'DEATH MATCH'
            || profile.attrs.modeLabel !== '标准佣兵对战') {
        fail('standard_merc profile identity drifted');
    }
    onlyChildNames(profile, ['Rule']);
    const rules = children(profile, 'Rule');
    if (rules.length !== 2
            || rules[0].attrs.id !== 'zhanmadao_guaranteed'
            || rules[1].attrs.id !== 'gladiator_equipment') {
        fail('rule physical order must be zhanmadao_guaranteed then gladiator_equipment');
    }

    const zhan = validateRuleShape(rules[0]);
    if (zhan.triggers.length !== 1
            || zhan.triggers[0].attrs.slot !== '刀'
            || zhan.triggers[0].attrs.item !== '斩马刀'
            || zhan.drops.length !== 1
            || zhan.drops[0].attrs.slot !== '刀'
            || numberAttr(zhan.drops[0], 'chancePercent', 100, 100, false) !== 100
            || rules[0].attrs.carrierScope !== 'carrier'
            || zhan.lottery != null
            || zhan.eligible.length !== 1
            || zhan.eligible[0].attrs.name !== '斩马刀'
            || zhan.eligible[0].attrs.slot !== '刀') {
        fail('zhanmadao_guaranteed contract drifted');
    }

    const gladiator = validateRuleShape(rules[1]);
    if (rules[1].attrs.carrierScope !== 'specific_carrier') {
        fail('gladiator carrierScope must remain specific_carrier');
    }
    exactSet(gladiator.triggers.map(node => node.attrs.slot + '\0' + node.attrs.item), [
        '颈部装备\0角斗高手项链', '颈部装备\0角斗王者项链'
    ], 'gladiator triggers');
    if (gladiator.drops.length !== 2) fail('gladiator must have two direct weapon drops');
    const dropsBySlot = Object.fromEntries(gladiator.drops.map(node => [node.attrs.slot, node]));
    if (!dropsBySlot['长枪'] || !dropsBySlot['刀']
            || numberAttr(dropsBySlot['长枪'], 'chancePercent', 25, 25, false) !== 25
            || numberAttr(dropsBySlot['刀'], 'chancePercent', 25, 25, false) !== 25) {
        fail('gladiator weapon drop contract drifted');
    }

    const lottery = gladiator.lottery;
    if (!lottery) fail('gladiator SlotLottery is required');
    exactAttributes(lottery, ['dropChancePercent']);
    if (numberAttr(lottery, 'dropChancePercent', 100, 100, false) !== 100) {
        fail('gladiator lottery drop chance drifted');
    }
    onlyChildNames(lottery, ['Choice']);
    const choices = children(lottery, 'Choice');
    const expectedSlots = ['头部装备', '上装装备', '下装装备', '手部装备', '脚部装备'];
    if (choices.length !== 6) fail('gladiator lottery must have five slots plus one empty choice');
    for (let i = 0; i < expectedSlots.length; i += 1) {
        exactAttributes(choices[i], ['slot', 'weight']);
        if (choices[i].attrs.slot !== expectedSlots[i]
                || numberAttr(choices[i], 'weight', 1, 1, true) !== 1) {
            fail('gladiator lottery slot/order drifted at index ' + i);
        }
    }
    exactAttributes(choices[5], ['empty', 'weight']);
    if (choices[5].attrs.empty !== 'true'
            || numberAttr(choices[5], 'weight', 2, 2, true) !== 2) {
        fail('gladiator lottery empty weight must remain 2');
    }
    return {profile, rules, gladiator};
}

function deriveLegacyReachableItems() {
    const mercs = JSON.parse(fs.readFileSync(MERC_PATH, 'utf8'));
    if (!Array.isArray(mercs)) fail('mercenaries.json root must be an array');
    const necklaceMercs = mercs.filter(merc => merc && merc.equipment
        && (merc.equipment.neck === '角斗高手项链'
            || merc.equipment.neck === '角斗王者项链'));
    const zhanMercs = mercs.filter(merc => merc && merc.equipment
        && merc.equipment.melee === '斩马刀');
    const bySlot = {};
    for (const [slot, mercKey] of Object.entries(SLOT_TO_MERC_KEY)) {
        bySlot[slot] = [...new Set(necklaceMercs
            .map(merc => merc.equipment[mercKey])
            .filter(name => typeof name === 'string' && name
                && LEGACY_FAMILY_TOKENS.some(token => name.includes(token))))].sort();
    }
    return {mercs, necklaceMercs, zhanMercs, bySlot};
}

function validateMercParity(gladiator, derived) {
    const xmlBySlot = {};
    for (const item of gladiator.eligible) {
        (xmlBySlot[item.attrs.slot] || (xmlBySlot[item.attrs.slot] = []))
            .push(item.attrs.name);
    }
    for (const slot of Object.keys(SLOT_TO_MERC_KEY)) {
        exactSet(xmlBySlot[slot] || [], derived.bySlot[slot],
            'EligibleItem parity for ' + slot);
    }
    if (derived.necklaceMercs.length !== 17 || derived.zhanMercs.length !== 5) {
        fail('current eligible preset counts drifted from 17 necklace / 5 zhanmadao');
    }
}

function loadItemNames() {
    const listXml = fs.readFileSync(ITEM_LIST_PATH, 'utf8');
    const files = [];
    let match;
    const filePattern = /<items>([^<]+)<\/items>/g;
    while ((match = filePattern.exec(listXml))) files.push(decodeXml(match[1].trim()));
    if (!files.length) fail('data/items/list.xml contains no <items> entries');
    const names = new Set();
    const namePattern = /<name>([^<]+)<\/name>/g;
    for (const file of files) {
        const source = fs.readFileSync(path.join(ROOT, 'data', 'items', file), 'utf8');
        namePattern.lastIndex = 0;
        while ((match = namePattern.exec(source))) names.add(decodeXml(match[1].trim()));
    }
    return names;
}

function validateItemClosure(contract) {
    const itemNames = loadItemNames();
    const referenced = [];
    for (const rule of contract.rules) {
        for (const trigger of children(rule, 'Trigger')) referenced.push(trigger.attrs.item);
        for (const item of children(rule, 'EligibleItem')) referenced.push(item.attrs.name);
    }
    for (const name of referenced) {
        if (!itemNames.has(name)) fail('arena rule references unknown item: ' + name);
    }
}

function requireSource(pathName, needles, forbidden) {
    const source = fs.readFileSync(pathName, 'utf8');
    for (const needle of needles) {
        if (!source.includes(needle)) fail(path.relative(ROOT, pathName) + ' missing: ' + needle);
    }
    for (const needle of forbidden || []) {
        if (source.includes(needle)) fail(path.relative(ROOT, pathName) + ' retains hardcode: ' + needle);
    }
}

function validateWiring() {
    requireSource(SCENE_PATH, ['ArenaDropRuleCatalog.resolveDrops(',
        '_root.竞技场掉落规则, "standard_merc"'], ['jjcDropItem', 'random(7)']);
    requireSource(BOOT_PATH, ['ArenaDropRulesLoader', 'arenaDropRulesReady',
        '_root.竞技场掉落规则', 'arena_drop_rules_failed']);
    requireSource(LOADER_PATH, ['super("data/arena/arena_drop_rules.xml")',
        'ArenaDropRuleCatalog.parse(raw)', 'loadArenaDropRules']);
    requireSource(INDEX_PATH, ['DROP_TYPE_ARENA:String = "arena"',
        'buildArenaDropRecords(arenaDropCatalog)', 'record.dropType !== DROP_TYPE_ARENA',
        'carrierScope:source.carrierScope']);
    requireSource(TOOLTIP_PATH, ['TIP_OBTAIN_ARENA', 'COL_DROP_ARENA',
        'DROP_TYPE_ARENA', 'TIP_OBTAIN_ARENA_CARRIER',
        'TIP_OBTAIN_ARENA_SPECIFIC_CARRIER'],
        ['arena.sourceHint', 'String(arena.arenaLabel)']);
    requireSource(RELEASE_POLICY_PATH, ['arena-drop-rules-current',
        "'arena_drop_rules.xml'"]);
}

function main() {
    const unknown = process.argv.slice(2);
    if (unknown.length) fail('unknown argument: ' + unknown[0]);
    const root = parseXml(fs.readFileSync(XML_PATH, 'utf8'));
    const contract = validateAuthoredContract(root);
    const derived = deriveLegacyReachableItems();
    validateMercParity(contract.gladiator, derived);
    validateItemClosure(contract);
    validateWiring();
    const gladiatorCount = contract.gladiator.eligible.length;
    process.stdout.write('Arena drop rules: schema 1 / 2 rules / '
        + (gladiatorCount + 1) + ' sources / '
        + derived.necklaceMercs.length + ' necklace presets / '
        + derived.zhanMercs.length + ' zhanmadao presets passed\n');
}

try { main(); }
catch (error) {
    process.stderr.write('[validate-arena-drop-rules] ' + error.message + '\n');
    process.exitCode = 1;
}
