#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const MODULES_DIR = path.join(ROOT, 'launcher', 'web', 'modules');

const ALLOW_RESOLVE = new Set([
  path.join('launcher', 'web', 'modules', 'icons.js'),
  path.join('launcher', 'web', 'modules', 'tooltip.js'),
  path.join('launcher', 'web', 'modules', 'intelligence-panel.js')
]);

function rel(file) {
  return path.relative(ROOT, file).replace(/\\/g, '/');
}

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.isFile() && /\.js$/i.test(entry.name)) out.push(full);
  }
  return out;
}

function stripComments(s) {
  return s
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
}

function lineOf(text, index) {
  return text.slice(0, index).split(/\r?\n/).length;
}

function extractObjectBlocks(text, needle) {
  const blocks = [];
  let pos = 0;
  while ((pos = text.indexOf(needle, pos)) !== -1) {
    const open = text.indexOf('{', pos + needle.length);
    if (open === -1) break;
    let depth = 0;
    let quote = null;
    let escaped = false;
    let lineComment = false;
    let blockComment = false;
    for (let i = open; i < text.length; i++) {
      const ch = text[i];
      const next = text[i + 1];
      if (lineComment) {
        if (ch === '\n' || ch === '\r') lineComment = false;
        continue;
      }
      if (blockComment) {
        if (ch === '*' && next === '/') {
          blockComment = false;
          i++;
        }
        continue;
      }
      if (quote) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = null;
        }
        continue;
      }
      if (ch === '/' && next === '/') {
        lineComment = true;
        i++;
        continue;
      }
      if (ch === '/' && next === '*') {
        blockComment = true;
        i++;
        continue;
      }
      if (ch === '"' || ch === '\'' || ch === '`') {
        quote = ch;
        continue;
      }
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        if (depth === 0) {
          blocks.push({ start: pos, body: text.slice(open, i + 1) });
          pos = i + 1;
          break;
        }
      }
    }
    if (pos <= open) break;
  }
  return blocks;
}

function main() {
  const files = walk(MODULES_DIR);
  const errors = [];
  let richTooltipCalls = 0;
  let resolveUses = 0;

  for (const file of files) {
    const raw = fs.readFileSync(file, 'utf8');
    const text = stripComments(raw);
    const relative = rel(file);
    const relNative = path.relative(ROOT, file);

    for (const block of extractObjectBlocks(text, 'PanelTooltip.buildItemRichHtml(')) {
      richTooltipCalls++;
      if (/\biconUrl\s*:/.test(block.body) && !/\biconHtml\s*:/.test(block.body)) {
        errors.push(`${relative}:${lineOf(text, block.start)} buildItemRichHtml passes iconUrl without iconHtml; use PanelTooltip.dynamicIconHtml(iconKey) so animated/layered icons play.`);
      }
    }

    if (!/tooltip\.js$/.test(relative)) {
      const manualIconUrlImg = /kshop-tt-icon[\s\S]{0,120}<img\s+src=[\s\S]{0,80}iconUrl|<img\s+src=[\s\S]{0,80}iconUrl[\s\S]{0,120}kshop-tt-icon/.exec(text);
      if (manualIconUrlImg) {
        errors.push(`${relative}:${lineOf(text, manualIconUrlImg.index)} tooltip icon manually renders iconUrl; use PanelTooltip.dynamicIconHtml(iconKey).`);
      }
    }

    let match;
    const resolveRe = /Icons\.resolve\s*\(/g;
    while ((match = resolveRe.exec(text))) {
      resolveUses++;
      if (!ALLOW_RESOLVE.has(relNative)) {
        errors.push(`${relative}:${lineOf(text, match.index)} Icons.resolve is static-first-frame; use Icons.html/applyIconToImage or add an explicit audit allowlist entry.`);
      }
    }
  }

  if (errors.length) {
    console.error('[audit-web-icon-render-entrypoints] FAIL');
    for (const error of errors) console.error('  - ' + error);
    process.exit(1);
  }

  console.log(`[audit-web-icon-render-entrypoints] OK: ${richTooltipCalls} rich tooltip icon calls audited, ${resolveUses} static resolve uses confined to allowlist.`);
}

main();
