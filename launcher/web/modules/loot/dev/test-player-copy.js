#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const PRODUCTION_FILES = ['loot-view.js', 'loot-panel.js', 'loot-organizer.js'];
const FORBIDDEN = [
    {label:'内部工作流缩写', pattern:/TRANSFER-PAIR|MAP CHEST|AUTHORITY SOURCE|PLAYER OWNED/},
    {label:'内部状态词', pattern:/权威|瞬态容器|玩家域|完整容器|对账|重放|水位/},
    {label:'协议字段', pattern:/\b(?:lease|token|revision|epoch|callId|wire|ACTIVE|CONSUMED|ABANDONED)\b/i}
];

function stringLiterals(source) {
    const literals = [];
    let index = 0;
    while (index < source.length) {
        if (source[index] === '/' && source[index + 1] === '/') {
            index = source.indexOf('\n', index + 2);
            if (index < 0) break;
            continue;
        }
        if (source[index] === '/' && source[index + 1] === '*') {
            index = source.indexOf('*/', index + 2);
            if (index < 0) break;
            index += 2;
            continue;
        }
        const quote = source[index];
        if (quote !== "'" && quote !== '"' && quote !== '`') {
            index++;
            continue;
        }
        const start = index++;
        let value = '';
        while (index < source.length) {
            const current = source[index++];
            if (current === '\\') {
                value += current;
                if (index < source.length) value += source[index++];
                continue;
            }
            if (current === quote) break;
            value += current;
        }
        literals.push({
            value:value,
            line:source.slice(0, start).split(/\r?\n/).length
        });
    }
    return literals;
}

function assertPlayerCopy() {
    const lootDir = path.resolve(__dirname, '..');
    const violations = [];
    let checked = 0;
    for (const file of PRODUCTION_FILES) {
        const source = fs.readFileSync(path.join(lootDir, file), 'utf8');
        for (const literal of stringLiterals(source)) {
            const playerFacing = /[\u3400-\u9fff]/.test(literal.value)
                || FORBIDDEN[0].pattern.test(literal.value);
            if (!playerFacing) continue;
            checked++;
            for (const rule of FORBIDDEN) {
                if (rule.pattern.test(literal.value)) {
                    violations.push(`${file}:${literal.line} ${rule.label}: ${literal.value}`);
                }
            }
        }
    }
    if (violations.length) {
        throw new Error('Loot 玩家文案词表门失败：\n' + violations.join('\n'));
    }
    console.log(`Loot player copy ${checked} literals checked, 0 forbidden`);
    return {checked:checked, forbidden:0};
}

if (require.main === module) {
    try { assertPlayerCopy(); }
    catch (error) { console.error(error.message || error); process.exit(1); }
}

module.exports = {assertPlayerCopy};
