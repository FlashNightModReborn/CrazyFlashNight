// glossary 数据校验：JSON 合法、requires 条件里的物品名必须注册、
// minValue 不得超过物品 maxvalue、词条必须有免门槛首页（否则已揭示词条会是空壳）。
// 用法：node tools/validate-glossary.js
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const glossDir = path.join(root, 'data', 'glossary');
const itemsPath = path.join(root, 'data', 'items', '收集品_情报.xml');

// 情报物品注册表：<name> 与 <maxvalue>
const itemsXml = fs.readFileSync(itemsPath, 'utf8');
const maxvalue = {};
for (const b of itemsXml.split(/<item[\s>]/).slice(1)) {
    const n = (b.match(/<name>([^<]+)/) || [])[1];
    const mv = (b.match(/<maxvalue>(\d+)/) || [])[1];
    if (n) maxvalue[n] = mv ? Number(mv) : null;
}

let errors = 0;
function err(msg) { console.log('ERR ' + msg); errors++; }

function checkRequires(owner, requires) {
    if (requires === undefined) return;
    if (!Array.isArray(requires)) { err(owner + ': requires 不是数组'); return; }
    for (const cond of requires) {
        if (!cond || typeof cond !== 'object') { err(owner + ': 条件不是对象 ' + JSON.stringify(cond)); continue; }
        if (typeof cond.item === 'string') {
            if (!(cond.item in maxvalue)) {
                err(owner + ': 未注册的情报物品 ' + JSON.stringify(cond.item));
                continue;
            }
            const min = cond.minValue == null ? 1 : Number(cond.minValue);
            if (!(min >= 0)) err(owner + ': minValue 非法 ' + JSON.stringify(cond));
            else if (maxvalue[cond.item] != null && min > maxvalue[cond.item]) {
                err(owner + ': minValue ' + min + ' 超过 ' + cond.item + ' 的 maxvalue=' + maxvalue[cond.item]);
            }
            continue;
        }
        if (cond.minCollectedItems != null || cond.decryptLevel != null) {
            if (typeof cond.item !== 'undefined') err(owner + ': 条件字段混杂 ' + JSON.stringify(cond));
            continue;
        }
        err(owner + ': 无法识别的条件形态 ' + JSON.stringify(cond));
    }
}

let index;
try {
    index = JSON.parse(fs.readFileSync(path.join(glossDir, 'glossary_index.json'), 'utf8'));
} catch (e) {
    console.log('ERR glossary_index.json 解析失败: ' + e.message);
    process.exit(1);
}

const termFiles = new Set(fs.readdirSync(glossDir).filter(f => f.endsWith('.json') && f !== 'glossary_index.json'));
const indexed = new Set();
for (const e of index) {
    if (!e || typeof e.termName !== 'string') { err('index 条目缺 termName'); continue; }
    indexed.add(e.termName);
    checkRequires('index:' + e.termName, e.requires);
    if (!termFiles.has(e.termName + '.json')) err('index 词条缺文件: ' + e.termName);
}

for (const f of termFiles) {
    const termName = f.replace(/\.json$/, '');
    if (!indexed.has(termName)) console.log('WARN ' + f + ' 不在 index 中');
    let term;
    try { term = JSON.parse(fs.readFileSync(path.join(glossDir, f), 'utf8')); }
    catch (e) { err(f + ' 解析失败: ' + e.message); continue; }
    const pages = term.pages;
    if (!Array.isArray(pages) || !pages.length) { err(f + ': 缺 pages[]'); continue; }
    let free = 0;
    for (let i = 0; i < pages.length; i++) {
        const p = pages[i];
        const label = f + ':页' + (p && p.pageKey != null ? p.pageKey : i);
        if (!p || typeof p !== 'object') { err(label + ' 不是对象'); continue; }
        checkRequires(label, p.requires);
        if (!p.requires || !p.requires.length) free++;
        if (!Array.isArray(p.blocks)) err(label + ': blocks 不是数组');
    }
    if (!free) err(f + ': 没有免门槛首页（词条揭示后会是空页）');
}

console.log('index=' + index.length + ' terms, files=' + termFiles.size + ', errors=' + errors);
process.exit(errors ? 1 : 0);
