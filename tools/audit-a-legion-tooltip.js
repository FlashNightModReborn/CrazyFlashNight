'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const ITEMS_DIR = path.join(ROOT, 'data', 'items');
const REPORT = path.join(ROOT, 'docs', 'reports', 'a-legion-tooltip-content-audit.md');
const LONG_DESCRIPTION_MIN = 200;
const A_PATTERN = /A兵团|Andy|安迪烙/i;

function walk(dir) {
    const out = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) out.push(...walk(full));
        else if (entry.isFile() && entry.name.toLowerCase().endsWith('.xml')) out.push(full);
    }
    return out.sort();
}

function tag(source, name) {
    const match = source.match(new RegExp('<' + name + '>([\\s\\S]*?)</' + name + '>'));
    return match ? match[1] : '';
}

function decodeXml(value) {
    return value.replace(/&lt;/g, '<').replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"').replace(/&apos;/g, "'")
        .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
        .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
        .replace(/&amp;/g, '&');
}

function plainText(value) {
    return decodeXml(value).replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
}

function colorOf(value) {
    return value.toUpperCase();
}

function collect() {
    const items = [];
    for (const file of walk(ITEMS_DIR)) {
        const source = fs.readFileSync(file, 'utf8');
        const blocks = source.match(/<item>[\s\S]*?<\/item>/g) || [source];
        for (const block of blocks) {
            const description = tag(block, 'description');
            if (!description) continue;
            const decoded = decodeXml(description);
            const text = plainText(description);
            const spans = [];
            const pattern = /<font\b[^>]*color\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/font>/gi;
            let match;
            while ((match = pattern.exec(decoded)) !== null) {
                spans.push({ color: colorOf(match[1]), text: plainText(match[2]) });
            }
            const aSpans = spans.filter(span => A_PATTERN.test(span.text));
            const warlordSpans = spans.filter(span => span.text.includes('军阀'));
            const hasA = A_PATTERN.test(text);
            const hasWarlord = text.includes('军阀');
            items.push({
                file: path.relative(ROOT, file).replace(/\\/g, '/'),
                name: plainText(tag(block, 'name')),
                displayName: plainText(tag(block, 'displayname')),
                length: text.length,
                hasA,
                hasWarlord,
                aColors: [...new Set(aSpans.map(span => span.color))].sort(),
                warlordColors: [...new Set(warlordSpans.map(span => span.color))].sort(),
                aWithoutFont: hasA && aSpans.length === 0,
                warlordWithoutFont: hasWarlord && warlordSpans.length === 0
            });
        }
    }
    return items;
}

function md(value) {
    return String(value || '—').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

function itemLine(item) {
    return '| ' + md(item.displayName || item.name) + ' | ' + md(item.name)
        + ' | ' + item.length + ' | `' + item.file + '` |';
}

function render(items) {
    const aItems = items.filter(item => item.hasA);
    const warlordItems = items.filter(item => item.hasWarlord);
    const longItems = items.filter(item => item.length >= LONG_DESCRIPTION_MIN)
        .sort((a, b) => b.length - a.length || a.name.localeCompare(b.name, 'zh-CN'));
    const colors = key => [...new Set(items.flatMap(item => item[key]))].sort();
    const lines = [
        '# 物品简介 A兵团/军阀内容与长文审计', '',
        '- A兵团相关物品：' + aItems.length + ' 件；相关颜色：'
            + (colors('aColors').join('、') || '无'),
        '- 军阀相关物品：' + warlordItems.length + ' 件；相关颜色：'
            + (colors('warlordColors').join('、') || '无'),
        '- 超过 ' + LONG_DESCRIPTION_MIN + ' 字的简介：' + longItems.length + ' 件',
        '- 匹配规则：预设 `#FF0000` 或明确 `A兵团` / `Andy` / `安迪烙` → 红色徽标 + 同色下划线；`军阀` → 黑黄徽标 + `#FFFFE0` 下划线。', '',
        '## A兵团相关内容', '',
        '| 显示名 | 物品名 | 已有字体颜色 | 未着色相关内容 | 文件 |',
        '|---|---|---|---|---|'
    ];
    for (const item of aItems) {
        lines.push('| ' + md(item.displayName || item.name) + ' | ' + md(item.name)
            + ' | ' + (item.aColors.join('、') || '无') + ' | '
            + (item.aWithoutFont ? '是' : '否') + ' | `' + item.file + '` |');
    }
    lines.push('', '## 军阀相关内容', '',
        '| 显示名 | 物品名 | 已有字体颜色 | 未着色相关内容 | 文件 |',
        '|---|---|---|---|---|');
    for (const item of warlordItems) {
        lines.push('| ' + md(item.displayName || item.name) + ' | ' + md(item.name)
            + ' | ' + (item.warlordColors.join('、') || '无') + ' | '
            + (item.warlordWithoutFont ? '是' : '否') + ' | `' + item.file + '` |');
    }
    lines.push('', '## 超过 ' + LONG_DESCRIPTION_MIN + ' 字的简介（按字数降序）', '',
        '| 显示名 | 物品名 | 字数 | 文件 |', '|---|---|---:|---|');
    for (const item of longItems) lines.push(itemLine(item));
    lines.push('');
    return lines.join('\n');
}

const output = render(collect());
if (process.argv.includes('--check')) {
    if (!fs.existsSync(REPORT) || fs.readFileSync(REPORT, 'utf8') !== output) {
        console.error('Report is stale: ' + path.relative(ROOT, REPORT));
        process.exit(1);
    }
    console.log('A兵团/军阀简介审计报告一致: ' + path.relative(ROOT, REPORT));
} else {
    fs.mkdirSync(path.dirname(REPORT), { recursive: true });
    fs.writeFileSync(REPORT, output, 'utf8');
    console.log('Wrote ' + path.relative(ROOT, REPORT));
}
