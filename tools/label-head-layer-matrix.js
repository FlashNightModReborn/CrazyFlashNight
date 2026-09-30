#!/usr/bin/env node
'use strict';

// 头部层级矩阵打标驱动：对 tmp/head-layer-matrix 的每格（性别×发型×装备）
// 以 devin CLI（swe2 视觉）逐格对比「游戏内现状 vs 调整后」两张图，输出 JSONL 判定。
//
// 用法：
//   node tools/label-head-layer-matrix.js [--matrix tmp/head-layer-matrix]
//       [--out tmp/head-layer-verdicts] [--concurrency 5] [--limit N]
//       [--only 装备1,装备2] [--summarize]
//
// verdicts.jsonl 每行：{gender, hair, item, verdict, reason, ts}。
// verdict ∈ hair_over_ok（B/发型压装备 可接受或更自然）
//           keep_mask_over（A/装备压发型 明显更合适）
//           ambiguous（两者差异小或判断困难，留人工）
// 断点续跑：已存在于 verdicts.jsonl 的格子自动跳过。
// --summarize 不打标，只把 verdicts 聚合成 per-item 建议（summary.json）。

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const projectRoot = path.resolve(__dirname, '..');

function parseArgs(argv) {
    const args = {
        matrix: path.join('tmp', 'head-layer-matrix'),
        out: path.join('tmp', 'head-layer-verdicts'),
        concurrency: 5,
        limit: 0,
        only: null,
        summarize: false
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        const next = argv[i + 1] || '';
        if (arg === '--matrix') { args.matrix = next; i += 1; }
        else if (arg === '--out') { args.out = next; i += 1; }
        else if (arg === '--concurrency') { args.concurrency = Math.max(1, Number(next) || 5); i += 1; }
        else if (arg === '--limit') { args.limit = Math.max(0, Number(next) || 0); i += 1; }
        else if (arg === '--only') { args.only = new Set(next.split(',').filter(Boolean)); i += 1; }
        else if (arg === '--summarize') { args.summarize = true; }
        else if (arg === '--help' || arg === '-h') {
            console.log('usage: node tools/label-head-layer-matrix.js [--matrix <dir>] [--out <dir>] [--concurrency 5] [--limit N] [--only a,b] [--summarize]');
            process.exit(0);
        } else {
            console.error('unknown arg: ' + arg);
            process.exit(1);
        }
    }
    return args;
}

function collectCells(matrixDir) {
    const cells = [];
    for (const gender of fs.readdirSync(matrixDir)) {
        const genderDir = path.join(matrixDir, gender);
        if (!fs.statSync(genderDir).isDirectory()) continue;
        for (const hair of fs.readdirSync(genderDir)) {
            const hairDir = path.join(genderDir, hair);
            const indexFile = path.join(hairDir, 'index.json');
            if (!fs.existsSync(indexFile)) continue;
            const index = JSON.parse(fs.readFileSync(indexFile, 'utf8'));
            for (const item of index.items || []) {
                if (item.helmet) continue;
                if (!item.files || !item.files.flash || !item.files.doll) continue;
                cells.push({
                    gender: index.gender || gender,
                    hair: index.hair || hair,
                    item: item.name,
                    flash: path.resolve(projectRoot, item.files.flash),
                    doll: path.resolve(projectRoot, item.files.doll)
                });
            }
        }
    }
    return cells;
}

function loadDone(verdictsFile) {
    const done = new Set();
    if (!fs.existsSync(verdictsFile)) return done;
    const lines = fs.readFileSync(verdictsFile, 'utf8').split('\n');
    for (const line of lines) {
        if (!line.trim()) continue;
        try {
            const v = JSON.parse(line);
            done.add(v.gender + '|' + v.hair + '|' + v.item);
        } catch (error) { /* 跳过坏行，重跑该格 */ }
    }
    return done;
}

const PROMPT_TEMPLATE = cell => [
    '你在为一个 2D 游戏的头部装备做图层顺序打标。下面两张图是同一角色、同一发型、同一件头部装备「' + cell.item + '」，唯一区别是头发与装备的叠放顺序：',
    '- 图A（游戏内现状）: ' + cell.flash,
    '- 图B（调整后）: ' + cell.doll,
    '请读两张图，先识别这是什么装备（帽子/眼镜/风镜/口罩面罩/头饰/其他），再判断：B（发型压装备）是否让头发遮住了该装备的关键识别特征（帽冠、镜筒、镜框上沿、大面积装饰），或显得头发被装备整个吞掉。',
    '只输出一行 JSON，不要输出其他内容：',
    '{"verdict":"hair_over_ok|keep_mask_over|ambiguous","reason":"一句话"}',
    'verdict 口径：hair_over_ok = B 更自然或两者皆可；keep_mask_over = A 明显更合适、B 破坏了装备识别；ambiguous = 差异很小或难以判断。'
].join('\n');

function parseVerdict(text) {
    const lines = String(text || '').split('\n').map(l => l.trim()).filter(Boolean);
    for (let i = lines.length - 1; i >= 0; i--) {
        const line = lines[i].replace(/^```(?:json)?|```$/g, '').trim();
        if (!line.startsWith('{')) continue;
        try {
            const parsed = JSON.parse(line);
            const verdict = String(parsed.verdict || '');
            if (['hair_over_ok', 'keep_mask_over', 'ambiguous'].indexOf(verdict) >= 0) {
                return { verdict, reason: String(parsed.reason || '') };
            }
        } catch (error) { /* 继续找上一行 */ }
    }
    return null;
}

function isRateWall(text) {
    return /rate.?limit|quota|429|exceed|额度|too many/i.test(String(text || ''));
}

function runDevin(promptFile) {
    return new Promise(resolve => {
        const child = spawn('devin', ['-p', '--permission-mode', 'auto', '--prompt-file', promptFile], {
            cwd: projectRoot,
            shell: false,
            windowsHide: true
        });
        let out = '';
        let err = '';
        let settled = false;
        const timer = setTimeout(() => {
            if (!settled) {
                settled = true;
                child.kill();
                resolve({ ok: false, timeout: true, out, err });
            }
        }, 180000);
        child.stdout.on('data', d => { out += d; });
        child.stderr.on('data', d => { err += d; });
        child.on('error', error => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            resolve({ ok: false, error: String(error), out, err });
        });
        child.on('close', code => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            resolve({ ok: code === 0, code, out, err });
        });
    });
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function labelCell(cell, workerId, promptDir) {
    const promptFile = path.join(promptDir, 'prompt-' + workerId + '.txt');
    fs.writeFileSync(promptFile, PROMPT_TEMPLATE(cell), 'utf8');
    for (let attempt = 0; attempt < 3; attempt++) {
        const result = await runDevin(promptFile);
        const parsed = result.ok ? parseVerdict(result.out) : null;
        if (parsed) return { verdict: parsed.verdict, reason: parsed.reason };
        if (isRateWall(result.out + '\n' + result.err)) {
            return { verdict: null, rateWall: true };
        }
        await sleep(2000 * (attempt + 1));
    }
    return { verdict: 'error', reason: 'unparseable_or_failed' };
}

async function summarize(verdictsFile, outDir) {
    const perItem = {};
    const lines = fs.existsSync(verdictsFile)
        ? fs.readFileSync(verdictsFile, 'utf8').split('\n') : [];
    let total = 0;
    for (const line of lines) {
        if (!line.trim()) continue;
        let v;
        try { v = JSON.parse(line); } catch (error) { continue; }
        total++;
        const key = v.item;
        if (!perItem[key]) {
            perItem[key] = { item: key, hairOverOk: 0, keepMaskOver: 0, ambiguous: 0, error: 0, dissentHairs: [] };
        }
        const bucket = perItem[key];
        if (v.verdict === 'hair_over_ok') bucket.hairOverOk++;
        else if (v.verdict === 'keep_mask_over') {
            bucket.keepMaskOver++;
            bucket.dissentHairs.push(v.gender + '/' + v.hair);
        } else if (v.verdict === 'ambiguous') bucket.ambiguous++;
        else bucket.error++;
    }
    const summary = Object.keys(perItem).sort().map(key => {
        const bucket = perItem[key];
        const cells = bucket.hairOverOk + bucket.keepMaskOver + bucket.ambiguous;
        // 多数决：keep 占比 ≤25% 建议翻转（发型压面具），≥50% 建议保持现状，
        // 中间地带或有 error 格子一律留人工。逐件最终拍板权在维护者。
        const keepRatio = cells > 0 ? bucket.keepMaskOver / cells : 0;
        const suggestion = bucket.error > 0 ? 'review'
            : keepRatio <= 0.25 ? 'hair_over_ok'
            : keepRatio >= 0.5 ? 'keep_mask_over'
            : 'review';
        return {
            item: bucket.item,
            suggestion: suggestion,
            cells: cells,
            hairOverOk: bucket.hairOverOk,
            keepMaskOver: bucket.keepMaskOver,
            ambiguous: bucket.ambiguous,
            error: bucket.error,
            dissentHairs: bucket.dissentHairs
        };
    });
    const outFile = path.join(outDir, 'summary.json');
    fs.writeFileSync(outFile, JSON.stringify({ total, items: summary }, null, 2));
    const counts = { hair_over_ok: 0, keep_mask_over: 0, review: 0 };
    summary.forEach(s => { counts[s.suggestion]++; });
    console.log('verdicts=' + total + ' items=' + summary.length
        + ' hair_over_ok=' + counts.hair_over_ok
        + ' keep_mask_over=' + counts.keep_mask_over
        + ' review=' + counts.review
        + ' -> ' + path.relative(projectRoot, outFile));
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    const matrixDir = path.resolve(projectRoot, args.matrix);
    const outDir = path.resolve(projectRoot, args.out);
    const verdictsFile = path.join(outDir, 'verdicts.jsonl');
    fs.mkdirSync(outDir, { recursive: true });
    fs.mkdirSync(path.join(outDir, 'prompts'), { recursive: true });

    if (args.summarize) {
        await summarize(verdictsFile, outDir);
        return;
    }

    let cells = collectCells(matrixDir);
    if (args.only) cells = cells.filter(c => args.only.has(c.item));
    const done = loadDone(verdictsFile);
    const todo = cells.filter(c => !done.has(c.gender + '|' + c.hair + '|' + c.item));
    const workload = args.limit > 0 ? todo.slice(0, args.limit) : todo;
    console.log('cells=' + cells.length + ' done=' + done.size + ' todo=' + workload.length
        + ' concurrency=' + args.concurrency);

    let cursor = 0;
    let labeled = 0;
    let rateWalls = 0;
    const startedAt = Date.now();
    const fd = fs.openSync(verdictsFile, 'a');

    async function worker(workerId) {
        for (;;) {
            const index = cursor++;
            if (index >= workload.length) return;
            const cell = workload[index];
            const result = await labelCell(cell, workerId, path.join(outDir, 'prompts'));
            if (result.rateWall) {
                rateWalls++;
                cursor--;  // 退回本格，全局退避后重试
                const backoff = Math.min(30, 5 * rateWalls);
                console.log('[rate-wall] 全局退避 ' + backoff + ' 分钟（第 ' + rateWalls + ' 次）');
                await sleep(backoff * 60000);
                continue;
            }
            fs.writeSync(fd, JSON.stringify({
                gender: cell.gender,
                hair: cell.hair,
                item: cell.item,
                verdict: result.verdict,
                reason: result.reason,
                ts: new Date().toISOString()
            }) + '\n');
            labeled++;
            if (labeled % 25 === 0) {
                const elapsed = (Date.now() - startedAt) / 60000;
                const eta = workload.length > labeled
                    ? Math.round(elapsed / labeled * (workload.length - labeled)) : 0;
                console.log('progress ' + labeled + '/' + workload.length
                    + ' elapsed=' + Math.round(elapsed) + 'min eta=' + eta + 'min');
            }
        }
    }

    const workers = [];
    for (let i = 0; i < args.concurrency; i++) workers.push(worker(i));
    await Promise.all(workers);
    fs.closeSync(fd);
    console.log('done: labeled=' + labeled + ' rateWalls=' + rateWalls);
    await summarize(verdictsFile, outDir);
}

main().catch(error => {
    console.error(error && error.stack || error);
    process.exit(1);
});
