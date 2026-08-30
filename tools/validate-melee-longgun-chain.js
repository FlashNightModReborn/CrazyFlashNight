#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ITEM_DIR = path.join(ROOT, 'data', 'items');
const ITEM_LIST_PATH = path.join(ITEM_DIR, 'list.xml');
const MELEE_LONGGUN_TYPES = new Set(['近战', '压制近战']);

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

    if (errors.length) {
        for (const error of errors) console.error('[melee-longgun-chain] ' + error);
        process.exitCode = 1;
        return;
    }
    console.log('近战长枪联弹校验通过：items=' + itemCount
        + ' profiles=' + profileCount + ' multiSegment=' + multiSegmentCount);
}

try {
    main();
} catch (error) {
    console.error('[melee-longgun-chain] ' + error.message);
    process.exitCode = 1;
}
