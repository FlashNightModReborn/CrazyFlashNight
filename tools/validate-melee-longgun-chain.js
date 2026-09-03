#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ITEM_DIR = path.join(ROOT, 'data', 'items');
const ITEM_LIST_PATH = path.join(ITEM_DIR, 'list.xml');
const MELEE_LONGGUN_TYPES = new Set(['近战', '压制近战']);
const MOD_DIR = path.join(ITEM_DIR, 'equipment_mods');
const MOD_FILES = [
    '低级材料_刀专用.xml',
    '中等材料_刀专用.xml',
    '高等材料_刀专用.xml'
];
const SWITCH_XFL_PATH = path.join(
    ROOT, 'flashswf', 'arts', 'things0', 'LIBRARY', 'sprite', '攻击模式切换.xml');
const SWITCH_CORE_PATH = path.join(
    ROOT, 'scripts', '类定义', 'org', 'flashNight', 'arki', 'unit', 'Action', 'Melee', 'SwitchStrikeCore.as');
const PLAYER_FUNCTION_PATH = path.join(
    ROOT, 'scripts', '逻辑', '单位函数', '单位函数_fs_aka_玩家模板迁移.as');

function fail(message) {
    throw new Error(message);
}

function readText(filePath) {
    return fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
}

function decodeXml(value) {
    return String(value || '')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&amp;/g, '&');
}

function parseAttributes(source, label) {
    const attributes = {};
    let remaining = source.trim();
    while (remaining) {
        const match = /^([^\s=]+)\s*=\s*(["'])([\s\S]*?)\2\s*/.exec(remaining);
        if (!match) fail(label + ': malformed attribute text: ' + remaining);
        if (Object.prototype.hasOwnProperty.call(attributes, match[1])) {
            fail(label + ': duplicate attribute ' + match[1]);
        }
        attributes[match[1]] = decodeXml(match[3]);
        remaining = remaining.slice(match[0].length);
    }
    return attributes;
}

function parseXml(source, label) {
    const text = source
        .replace(/^\uFEFF/, '')
        .replace(/<\?xml[\s\S]*?\?>/g, '')
        .replace(/<!--[\s\S]*?-->/g, '');
    const tokens = text.match(/<[^>]+>|[^<]+/g) || [];
    const stack = [];
    let root = null;

    for (const token of tokens) {
        if (token[0] !== '<') {
            if (stack.length) stack[stack.length - 1].text += token;
            else if (token.trim()) fail(label + ': text outside XML root');
            continue;
        }
        if (/^<!/.test(token) || /^<\?/.test(token)) {
            fail(label + ': unsupported XML declaration ' + token);
        }
        if (/^<\//.test(token)) {
            const closing = /^<\/([^\s>]+)\s*>$/.exec(token);
            if (!closing || !stack.length || stack[stack.length - 1].name !== closing[1]) {
                fail(label + ': mismatched closing tag ' + token);
            }
            stack.pop();
            continue;
        }

        const opening = /^<([^\s/>]+)([\s\S]*?)(\/?)>$/.exec(token);
        if (!opening) fail(label + ': malformed opening tag ' + token);
        const node = {
            name: opening[1],
            attributes: parseAttributes(opening[2], label + ': <' + opening[1] + '>'),
            children: [],
            text: ''
        };
        if (stack.length) stack[stack.length - 1].children.push(node);
        else if (root == null) root = node;
        else fail(label + ': multiple XML roots');
        if (opening[3] !== '/') stack.push(node);
    }

    if (stack.length) fail(label + ': unclosed tag <' + stack[stack.length - 1].name + '>');
    if (root == null) fail(label + ': missing XML root');
    return root;
}

function child(node, name) {
    return node.children.find(candidate => candidate.name === name) || null;
}

function childText(node, name) {
    const target = child(node, name);
    return target ? decodeXml(target.text.trim()) : '';
}

function childrenNamed(node, name) {
    return node ? node.children.filter(candidate => candidate.name === name) : [];
}

function at(node, ...names) {
    let current = node;
    for (const name of names) {
        current = child(current, name);
        if (!current) return null;
    }
    return current;
}

function textAt(node, ...names) {
    const target = at(node, ...names);
    return target ? decodeXml(target.text.trim()) : '';
}

function csvSet(value) {
    return new Set(String(value || '').split(',').map(part => part.trim()).filter(Boolean));
}

function findBranch(container, elementName, branchName) {
    return childrenNamed(container, elementName).find(branch =>
        String(branch.attributes.name || '') === branchName) || null;
}

function expectEqual(errors, label, actual, expected) {
    if (String(actual) !== String(expected)) {
        errors.push(label + ': expected ' + expected + ', got ' + actual);
    }
}

function expectCsv(errors, label, actual, expected) {
    const actualSet = csvSet(actual);
    const expectedSet = csvSet(expected);
    if (actualSet.size !== expectedSet.size ||
        [...expectedSet].some(value => !actualSet.has(value))) {
        errors.push(label + ': expected {' + [...expectedSet].join(',') +
            '}, got {' + [...actualSet].join(',') + '}');
    }
}

function expectNode(errors, label, node) {
    if (!node) errors.push(label + ': missing node');
    return node;
}

function effectiveField(profile, baseProfile, fieldName) {
    const authored = childText(profile, fieldName);
    return authored !== '' ? authored : childText(baseProfile, fieldName);
}

function auditItemDocument(sourceLabel, source) {
    const root = parseXml(source, sourceLabel);
    const errors = [];
    let itemCount = 0;
    let profileCount = 0;
    let multiSegmentCount = 0;

    for (const item of root.children.filter(node => node.name === 'item')) {
        const weaponType = item.attributes.weapontype || '';
        if (!MELEE_LONGGUN_TYPES.has(weaponType) || childText(item, 'use') !== '长枪') continue;

        itemCount += 1;
        const itemName = childText(item, 'name') || '<unnamed>';
        const baseProfile = child(item, 'data');
        if (!baseProfile) {
            errors.push(sourceLabel + ' / ' + itemName + ': missing <data>');
            continue;
        }

        const profiles = [baseProfile].concat(
            item.children.filter(node => /^data_/.test(node.name))
        );
        for (const profile of profiles) {
            profileCount += 1;
            const splitText = effectiveField(profile, baseProfile, 'split');
            const bullet = effectiveField(profile, baseProfile, 'bullet');
            const split = Number(splitText);
            const profileLabel = sourceLabel + ' / ' + itemName + ' / <' + profile.name + '>';

            if (!Number.isFinite(split) || split < 1 || Math.floor(split) !== split) {
                errors.push(profileLabel + ': effective split must be a positive integer, got ' + splitText);
                continue;
            }
            if (!bullet) {
                errors.push(profileLabel + ': effective bullet is missing');
                continue;
            }
            if (split > 1) {
                multiSegmentCount += 1;
                if (bullet !== '近战联弹') {
                    errors.push(profileLabel + ': split=' + split
                        + ' must use 近战联弹, got ' + bullet);
                }
            }
        }
    }

    return {errors, itemCount, profileCount, multiSegmentCount};
}

function auditPluginBuild() {
    const errors = [];
    const mods = new Map();

    for (const fileName of MOD_FILES) {
        const root = parseXml(readText(path.join(MOD_DIR, fileName)), fileName);
        for (const mod of childrenNamed(root, 'mod')) {
            const name = childText(mod, 'name');
            if (mods.has(name)) errors.push('duplicate audited mod: ' + name);
            mods.set(name, {node: mod, fileName});
        }
    }

    function requireMod(name) {
        const record = mods.get(name);
        if (!record) {
            errors.push('missing audited mod: ' + name);
            return null;
        }
        return record.node;
    }

    function expectDirectPort(name, expectedUse, expectedWeaponType, expectedTag) {
        const mod = requireMod(name);
        if (!mod) return null;
        expectCsv(errors, name + '.use', childText(mod, 'use'), expectedUse);
        if (expectedWeaponType != null) {
            expectCsv(errors, name + '.weapontype', childText(mod, 'weapontype'), expectedWeaponType);
        }
        expectEqual(errors, name + '.tag', childText(mod, 'tag'), expectedTag);
        return mod;
    }

    const quartz = expectDirectPort('石英磨刀石', '刀,长枪', '近战,压制近战', '刃面处理');
    if (quartz) {
        const baseSwitch = expectNode(errors, '石英磨刀石.baseSwitch', at(quartz, 'stats', 'baseSwitch'));
        if (baseSwitch) {
            expectEqual(errors, '石英磨刀石.baseSwitch.path', baseSwitch.attributes.path, 'data.damagetype');
            const values = childrenNamed(baseSwitch, 'value');
            const actual = new Map(values.map(value => [value.attributes.name || 'default', textAt(value, 'percentage', 'power')]));
            expectEqual(errors, '石英磨刀石.default', actual.get('default'), '9');
            expectEqual(errors, '石英磨刀石.break', actual.get('破击'), '24');
            expectEqual(errors, '石英磨刀石.magic', actual.get('魔法'), '50');
        }
        expectEqual(errors, '石英磨刀石.lock', textAt(quartz, 'stats', 'lockOverride', 'damagetype'), '物理');
    }

    const core = expectDirectPort('强化柄芯', '刀,长枪', '近战,压制近战', '柄芯');
    if (core) {
        expectEqual(errors, '强化柄芯.modslot', textAt(core, 'stats', 'merge', 'modslot'), '3');
        expectEqual(errors, '强化柄芯.weight', textAt(core, 'stats', 'flat', 'weight'), '2');
        expectCsv(errors, '强化柄芯.provideTags', childText(core, 'provideTags'), '扩展模组槽,强化框架');
        const branch = findBranch(at(core, 'stats', 'useSwitch'), 'use', 'weapontype:近战,weapontype:压制近战');
        if (expectNode(errors, '强化柄芯.meleeBranch', branch)) {
            expectEqual(errors, '强化柄芯.interface', childText(branch, 'provideTags'), '刀式柄芯接口');
        }
    }

    const rope = expectDirectPort('绳扣穿孔片', '刀,长枪', null, '柄侧板');
    if (rope) {
        if (childText(rope, 'weapontype')) errors.push('绳扣穿孔片 must remain available to all longguns');
        const branch = findBranch(child(rope, 'skillSwitch'), 'use', 'use:长枪');
        if (expectNode(errors, '绳扣穿孔片.skillBranch', branch)) {
            expectEqual(errors, '绳扣穿孔片.skill', childText(branch, 'skillname'), '旋转抡枪');
        }
    }

    const ring = expectDirectPort('挂环指槽板', '刀,长枪', null, '柄侧板');
    if (ring) {
        if (childText(ring, 'weapontype')) errors.push('挂环指槽板 must remain available to all longguns');
        if (childText(ring, 'provideTags')) errors.push('挂环指槽板 NOAH must remain conditional to longguns');
        const bladeBranch = findBranch(at(ring, 'stats', 'useSwitch'), 'use', 'use:刀');
        if (bladeBranch && childText(bladeBranch, 'provideTags')) {
            errors.push('挂环指槽板 blade branch must not provide NOAH');
        }
        const branch = findBranch(at(ring, 'stats', 'useSwitch'), 'use', 'use:长枪');
        if (expectNode(errors, '挂环指槽板.longgunBranch', branch)) {
            expectEqual(errors, '挂环指槽板.weightCoefficient', textAt(branch, 'merge', 'switchstrike', 'weightCoefficient'), '5');
            expectEqual(errors, '挂环指槽板.impactMultiplier', textAt(branch, 'merge', 'switchstrike', 'impactMultiplier'), '5');
            expectEqual(errors, '挂环指槽板.NOAH', childText(branch, 'provideTags'), 'NOAH');
        }
    }

    const electric = expectDirectPort('电击导能柄', '刀,长枪', '近战,压制近战', '握柄核心');
    if (electric) {
        const switchNode = at(electric, 'stats', 'useSwitch');
        const bladeBranch = findBranch(switchNode, 'use', 'use:刀');
        const meleeBranch = findBranch(switchNode, 'use', 'weapontype:近战,weapontype:压制近战');
        if (expectNode(errors, '电击导能柄.bladeBranch', bladeBranch)) {
            expectEqual(errors, '电击导能柄.bladePenalty', textAt(bladeBranch, 'flat', 'power'), '-10');
        }
        if (expectNode(errors, '电击导能柄.meleeBranch', meleeBranch)) {
            expectEqual(errors, '电击导能柄.require', childText(meleeBranch, 'requireTags'), '刀式柄芯接口');
            expectEqual(errors, '电击导能柄.multiplier', textAt(meleeBranch, 'multiplier', 'power'), '-3');
            expectEqual(errors, '电击导能柄.powerTag', childText(meleeBranch, 'provideTags'), '电力');
        }
    }

    const matrix = expectDirectPort('矩锁多点挂槽板', '刀,长枪', null, '柄侧板');
    if (matrix) {
        if (childText(matrix, 'weapontype')) errors.push('矩锁多点挂槽板 must remain available to all longguns');
        const switchNode = at(matrix, 'stats', 'useSwitch');
        const gunBranch = findBranch(switchNode, 'use', 'use:长枪');
        const meleeBranch = findBranch(switchNode, 'use', 'weapontype:近战,weapontype:压制近战');
        if (expectNode(errors, '矩锁多点挂槽板.gunBranch', gunBranch)) {
            expectEqual(errors, '矩锁多点挂槽板.power', textAt(gunBranch, 'percentage', 'power'), '5');
            expectEqual(errors, '矩锁多点挂槽板.criticalhit', textAt(gunBranch, 'softOverride', 'criticalhit'), '10');
            expectEqual(errors, '矩锁多点挂槽板.NOAH', childText(gunBranch, 'provideTags'), 'NOAH');
        }
        if (expectNode(errors, '矩锁多点挂槽板.meleeBranch', meleeBranch)) {
            expectEqual(errors, '矩锁多点挂槽板.interface', childText(meleeBranch, 'provideTags'), '刀式柄芯接口');
        }
    }

    const red = expectDirectPort('赤旌熔脊柄', '刀,长枪', '近战,压制近战', '握柄核心');
    if (red) {
        expectEqual(errors, '赤旌熔脊柄.damage', textAt(red, 'stats', 'override', 'damagetype'), '破击');
        expectEqual(errors, '赤旌熔脊柄.magic', textAt(red, 'stats', 'override', 'magictype'), '热');
        const meleeBranch = findBranch(at(red, 'stats', 'useSwitch'), 'use', 'weapontype:近战,weapontype:压制近战');
        if (expectNode(errors, '赤旌熔脊柄.meleeBranch', meleeBranch)) {
            expectEqual(errors, '赤旌熔脊柄.require', childText(meleeBranch, 'requireTags'), '刀式柄芯接口');
        }
        const powerBranch = findBranch(at(red, 'stats', 'tagSwitch'), 'tag', '电力');
        if (expectNode(errors, '赤旌熔脊柄.powerBranch', powerBranch)) {
            expectEqual(errors, '赤旌熔脊柄.hp', textAt(powerBranch, 'flat', 'hp'), '50');
        }
    }

    const xfl = readText(SWITCH_XFL_PATH);
    const profileCounts = {};
    for (const match of xfl.matchAll(/执行切手技\(this,\s*"([^"]+)"\)/g)) {
        profileCounts[match[1]] = (profileCounts[match[1]] || 0) + 1;
    }
    const expectedProfiles = {回旋踢: 2, 空手: 1, 长枪: 1, 兵器: 1, 双刀: 2, 疾影: 1};
    for (const [profile, count] of Object.entries(expectedProfiles)) {
        expectEqual(errors, '攻击模式切换.' + profile, profileCounts[profile] || 0, count);
    }
    if (/子弹属性\.子弹威力|_root\.子弹属性初始化\(this\)/.test(xfl)) {
        errors.push('攻击模式切换.xml still embeds switch-strike formulas');
    }

    const coreSource = readText(SWITCH_CORE_PATH);
    for (const token of [
        'weightCoefficient: 3', 'knockRate: 5', 'impactMultiplier: 1',
        'data.switchstrike', 'buildBulletProperties'
    ]) {
        if (!coreSource.includes(token)) errors.push('SwitchStrikeCore missing contract token: ' + token);
    }
    const playerSource = readText(PLAYER_FUNCTION_PATH);
    if (!/主角函数\.执行切手技[\s\S]*SwitchStrikeCore\.shoot/.test(playerSource)) {
        errors.push('player function does not expose the persistent switch-strike entry');
    }

    return errors;
}

function runSelfTests() {
    const validFixture = `
<root>
  <item weapontype="近战">
    <name>valid</name><use>长枪</use>
    <data><split>3</split><bullet>近战联弹</bullet></data>
    <data_fire><power>10</power></data_fire>
  </item>
</root>`;
    const valid = auditItemDocument('valid-fixture', validFixture);
    if (valid.errors.length !== 0 || valid.profileCount !== 2 || valid.multiSegmentCount !== 2) {
        fail('validator self-test failed to preserve inherited valid profiles');
    }

    const invalidFixture = `
<root>
  <item weapontype="压制近战">
    <name>invalid</name><use>长枪</use>
    <data><split>4</split><bullet>近战子弹</bullet></data>
  </item>
</root>`;
    const invalid = auditItemDocument('invalid-fixture', invalidFixture);
    if (invalid.errors.length !== 1 || !invalid.errors[0].includes('must use 近战联弹')) {
        fail('validator self-test failed to reject multi-instance melee bullets');
    }
}

function main() {
    runSelfTests();
    const manifest = parseXml(readText(ITEM_LIST_PATH), 'data/items/list.xml');
    const itemFiles = manifest.children
        .filter(node => node.name === 'items')
        .map(node => decodeXml(node.text.trim()));
    if (!itemFiles.length) fail('data/items/list.xml has no <items> entries');

    const errors = [];
    let itemCount = 0;
    let profileCount = 0;
    let multiSegmentCount = 0;
    for (const relativePath of itemFiles) {
        const result = auditItemDocument(
            'data/items/' + relativePath,
            readText(path.join(ITEM_DIR, relativePath))
        );
        errors.push(...result.errors);
        itemCount += result.itemCount;
        profileCount += result.profileCount;
        multiSegmentCount += result.multiSegmentCount;
    }
    errors.push(...auditPluginBuild());

    if (errors.length) {
        for (const error of errors) console.error('[melee-longgun-chain] ' + error);
        process.exitCode = 1;
        return;
    }
    console.log('近战长枪联弹校验通过：items=' + itemCount
        + ' profiles=' + profileCount + ' multiSegment=' + multiSegmentCount
        + ' pluginBuild=7 switchStrikeLocators=8');
}

try {
    main();
} catch (error) {
    console.error('[melee-longgun-chain] ' + error.message);
    process.exitCode = 1;
}
