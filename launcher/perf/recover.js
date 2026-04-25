// 把一个被中断的 run（崩溃/Ctrl+C）的 partial.json 拼成完整报表。
// 用法：
//   node recover.js reports/2026-04-25T08-15-45
// 或省略路径，自动找最新的含 partial.json 的目录：
//   node recover.js

'use strict';

const fs = require('fs');
const path = require('path');
const { writeJson, writeMarkdown, writeVisualHtml } = require('./lib/report');

function findLatestDirWithPartial(root) {
    if (!fs.existsSync(root)) return null;
    const dirs = fs.readdirSync(root)
        .map(name => path.join(root, name))
        .filter(p => fs.statSync(p).isDirectory())
        .filter(p => fs.existsSync(path.join(p, 'partial.json')))
        .sort();
    return dirs[dirs.length - 1] || null;
}

function main() {
    let target = process.argv[2];
    if (!target) {
        target = findLatestDirWithPartial(path.resolve(__dirname, 'reports'));
        if (!target) {
            console.error('no reportDir given and none found with partial.json');
            process.exit(2);
        }
        console.log('[recover] using latest:', target);
    }
    const partialPath = path.join(target, 'partial.json');
    if (!fs.existsSync(partialPath)) {
        console.error('not a recoverable dir (no partial.json):', target);
        process.exit(2);
    }
    const rows = JSON.parse(fs.readFileSync(partialPath, 'utf8'));
    if (!rows.length) { console.error('partial.json empty'); process.exit(2); }

    const jsonOut = path.join(target, 'summary.json');
    const mdOut = path.join(target, 'summary.md');
    const htmlOut = path.join(target, 'visual-diff.html');
    writeJson(rows, jsonOut);
    writeMarkdown(rows, mdOut);
    writeVisualHtml(rows, htmlOut);

    const meta = (() => { try { return JSON.parse(fs.readFileSync(path.join(target, 'meta.json'), 'utf8')); } catch { return null; } })();
    const planned = meta ? (meta.scenarios.length * meta.ablations.length) : null;
    console.log(`[recover] rows: ${rows.length}${planned ? ' / planned ' + planned : ''}`);
    console.log(`[recover] JSON : ${jsonOut}`);
    console.log(`[recover] MD   : ${mdOut}`);
    console.log(`[recover] HTML : ${htmlOut}`);
}

main();
