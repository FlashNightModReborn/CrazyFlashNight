#!/usr/bin/env node
'use strict';

// 情报 H5 vs legacy XML/txt 的语义对齐审计。
//
// 用途：每篇 H5 都应当至少完整保留 legacy 时代的"叙事密点"——
//   1. EncryptReplace 字典词在 H5 里都应有 decryptText 包裹（按等级真锁死的精细加密）
//   2. EncryptCut 字典词在 H5 里都应有 redaction 或 damageText 包裹（删除/涂抹语义）
//   3. txt 段落字符在 H5 同 PageKey 中应大致出现（粗略覆盖率，避免整段漏写）
//
// 输出 dry-run 报告，不修改任何文件。
// CLI:
//   node tools/intelligence-h5-semantic-audit.js                # 全量审计
//   node tools/intelligence-h5-semantic-audit.js --item 资料    # 单条
//   node tools/intelligence-h5-semantic-audit.js --json         # JSON 输出
//   node tools/intelligence-h5-semantic-audit.js --strict       # warning 视为 error，exit 非 0

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const dictPath = path.join(root, 'data', 'dictionaries', 'information_dictionary.xml');
const txtDir = path.join(root, 'data', 'intelligence');
const h5Dir = path.join(root, 'data', 'intelligence_h5');

// 段落覆盖率阈值：H5 plain text 字符数 < legacy txt 字符数 * COVERAGE_RATIO 时，视为可疑漏段
const COVERAGE_RATIO = 0.55;
// 段落首字符匹配窗口：每段 txt 抽前 N 个非空白字符到 H5 全文里 indexOf 找子串
const SEED_WINDOW = 8;

function parseArgs(argv) {
  const args = { item: null, json: false, strict: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--item') args.item = argv[++i];
    else if (a === '--json') args.json = true;
    else if (a === '--strict') args.strict = true;
    else if (a === '-h' || a === '--help') {
      console.log('usage: node tools/intelligence-h5-semantic-audit.js [--item <name>] [--json] [--strict]');
      process.exit(0);
    } else throw new Error('unknown arg: ' + a);
  }
  return args;
}

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8').replace(/^﻿/, '');
}

function parseDictionary() {
  const xml = read(dictPath);
  const items = [];
  for (const match of xml.matchAll(/<Item>([\s\S]*?)<\/Item>/g)) {
    const body = match[1];
    const name = (body.match(/<Name>([\s\S]*?)<\/Name>/) || [])[1];
    if (!name) continue;
    const trimmedName = name.trim();
    const replace = parseDictBlock(body, 'EncryptReplace');
    const cut = parseDictBlock(body, 'EncryptCut');
    const pages = [];
    for (const info of body.matchAll(/<Information\s+([^/>]+?)\s*\/>/g)) {
      const attrs = {};
      info[1].replace(/([\w:-]+)\s*=\s*"([^"]*)"/g, (_, key, value) => {
        attrs[key] = value;
        return '';
      });
      if (attrs.PageKey) pages.push({
        pageKey: attrs.PageKey,
        value: Number(attrs.Value || 0),
        encryptLevel: Number(attrs.EncryptLevel || 0)
      });
    }
    items.push({ name: trimmedName, replace, cut, pages });
  }
  return items;
}

function parseDictBlock(body, tag) {
  const m = body.match(new RegExp('<' + tag + '>([\\s\\S]*?)</' + tag + '>'));
  if (!m) return [];
  const out = [];
  // <关键词>替换符</关键词>，关键词中不允许出现 < 或 >
  for (const wm of m[1].matchAll(/<([^/<>\s]+)>([\s\S]*?)<\/\1>/g)) {
    out.push({ keyword: wm[1], replacement: wm[2] });
  }
  return out;
}

function parseLegacyTxt(itemName) {
  const filePath = path.join(txtDir, itemName + '.txt');
  if (!fs.existsSync(filePath)) return null;
  const raw = read(filePath);
  const pages = {};
  // @@@PageKey@@@ 后面到下一个 @@@ 或 EOF
  const re = /@@@([^@\s]+)@@@\r?\n([\s\S]*?)(?=@@@[^@\s]+@@@|$)/g;
  let m;
  while ((m = re.exec(raw)) !== null) {
    pages[m[1]] = m[2].replace(/\r/g, '').trim();
  }
  return pages;
}

function parseH5(itemName) {
  const filePath = path.join(h5Dir, itemName + '.json');
  if (!fs.existsSync(filePath)) return null;
  return JSON.parse(read(filePath));
}

// 递归提取 H5 page 的所有 inline 文本字符（不区分 decryptText / redaction / damageText 包裹与否）
function flattenAllText(node, acc) {
  if (node == null) return;
  if (typeof node === 'string') { acc.push(node); return; }
  if (Array.isArray(node)) { for (const x of node) flattenAllText(x, acc); return; }
  if (typeof node !== 'object') return;
  if (typeof node.text === 'string') acc.push(node.text);
  if (typeof node.encryptedText === 'string') {
    // encryptedText 是占位符，不算正文字符
  }
  // 走所有可能承载子节点的字段
  for (const key of ['content', 'blocks', 'fragments', 'items', 'rows', 'columns', 'entries', 'plain', 'reveal', 'note', 'caption', 'title', 'materials', 'steps']) {
    if (node[key] != null) flattenAllText(node[key], acc);
  }
}

// 提取被特定类型节点（decryptText / redaction / damageText）包裹的所有"明文字符串"
function collectWrappedText(node, types, acc) {
  if (node == null) return;
  if (Array.isArray(node)) { for (const x of node) collectWrappedText(x, types, acc); return; }
  if (typeof node !== 'object') return;
  if (node.type && types.has(node.type)) {
    const inner = [];
    flattenAllText(node.content || node.plain || node.reveal || [], inner);
    if (typeof node.text === 'string') inner.push(node.text);
    const joined = inner.join('').trim();
    if (joined) acc.push(joined);
    return; // 不递归——避免把同一段被双重计入
  }
  for (const key of ['content', 'blocks', 'fragments', 'items', 'rows', 'columns', 'entries', 'plain', 'reveal', 'note', 'caption', 'title', 'materials', 'steps']) {
    if (node[key] != null) collectWrappedText(node[key], types, acc);
  }
}

function pageBlocksOf(h5, pageKey) {
  if (!h5 || !Array.isArray(h5.pages)) return null;
  const p = h5.pages.find(x => String(x.pageKey) === String(pageKey));
  return p ? (p.blocks || []) : null;
}

// 数字符串中"实际可读字符"长度（去空白、占位符）
function readableLength(s) {
  return String(s || '').replace(/[\s　]+/g, '').replace(/\$\{PC_NAME\}/g, '').length;
}

function hasFuzzyMatch(haystack, needle) {
  if (!needle) return true;
  // 简化：去空白后做子串查询
  const h = String(haystack).replace(/[\s　]+/g, '');
  const n = String(needle).replace(/[\s　]+/g, '');
  return h.indexOf(n) >= 0;
}

function auditItem(dictItem) {
  const findings = []; // { kind, severity, page, message }
  const txt = parseLegacyTxt(dictItem.name);
  const h5 = parseH5(dictItem.name);

  if (!h5) {
    findings.push({ kind: 'h5-missing', severity: 'error', page: null, message: 'H5 JSON not found at data/intelligence_h5/' + dictItem.name + '.json' });
    return { item: dictItem.name, findings };
  }

  // 预先把每页的 H5 plain text、decryptText/redaction/damageText 包裹文本采集出来
  const perPage = {};
  for (const p of dictItem.pages) {
    const blocks = pageBlocksOf(h5, p.pageKey);
    if (blocks == null) {
      findings.push({ kind: 'h5-page-missing', severity: 'error', page: p.pageKey, message: 'H5 缺少 pageKey=' + p.pageKey + ' 的 page entry' });
      continue;
    }
    const allChars = [];
    flattenAllText(blocks, allChars);
    const decryptWrapped = [];
    collectWrappedText(blocks, new Set(['decryptText', 'decryptBlock']), decryptWrapped);
    const cutWrapped = [];
    collectWrappedText(blocks, new Set(['redaction', 'damageText']), cutWrapped);
    perPage[p.pageKey] = {
      plain: allChars.join(''),
      decryptWrapped,
      cutWrapped,
      meta: p
    };
  }

  // (1) 关键词覆盖：EncryptReplace 词必须被 decryptText / decryptBlock 包裹
  for (const { keyword } of dictItem.replace) {
    for (const pk of Object.keys(perPage)) {
      const page = perPage[pk];
      const occurrencesInH5 = countOccurrences(page.plain, keyword);
      if (occurrencesInH5 === 0) continue; // 该词在此页不出现，跳过
      const occurrencesInWrap = page.decryptWrapped.reduce((sum, w) => sum + countOccurrences(w, keyword), 0);
      if (occurrencesInWrap < occurrencesInH5) {
        findings.push({
          kind: 'keyword-not-decrypted',
          severity: 'warning',
          page: pk,
          message: `EncryptReplace 字典词「${keyword}」在 page ${pk} 出现 ${occurrencesInH5} 次，但只有 ${occurrencesInWrap} 次被 decryptText/decryptBlock 包裹（缺 ${occurrencesInH5 - occurrencesInWrap} 次）`
        });
      }
    }
  }

  // (2) 切除词覆盖：EncryptCut 词应被 redaction 或 damageText 包裹
  for (const { keyword } of dictItem.cut) {
    for (const pk of Object.keys(perPage)) {
      const page = perPage[pk];
      const occurrencesInH5 = countOccurrences(page.plain, keyword);
      if (occurrencesInH5 === 0) continue;
      const occurrencesInWrap = page.cutWrapped.reduce((sum, w) => sum + countOccurrences(w, keyword), 0);
      if (occurrencesInWrap < occurrencesInH5) {
        findings.push({
          kind: 'keyword-not-redacted',
          severity: 'warning',
          page: pk,
          message: `EncryptCut 字典词「${keyword}」在 page ${pk} 出现 ${occurrencesInH5} 次，但只有 ${occurrencesInWrap} 次被 redaction/damageText 包裹（缺 ${occurrencesInH5 - occurrencesInWrap} 次）`
        });
      }
    }
  }

  // (3) 段落覆盖率（只在有 txt 文件时执行）
  if (txt) {
    for (const pk of Object.keys(perPage)) {
      const page = perPage[pk];
      const legacy = txt[pk];
      if (legacy == null) {
        findings.push({ kind: 'txt-page-missing', severity: 'info', page: pk, message: `legacy txt 缺少 @@@${pk}@@@ 段落（H5 此页可能是新增内容）` });
        continue;
      }
      const legacyLen = readableLength(legacy);
      const h5Len = readableLength(page.plain);
      if (legacyLen >= 20 && h5Len < legacyLen * COVERAGE_RATIO) {
        findings.push({
          kind: 'page-coverage-low',
          severity: 'warning',
          page: pk,
          message: `page ${pk} 字符覆盖率偏低：legacy ${legacyLen} 字 vs H5 ${h5Len} 字（比例 ${(h5Len / legacyLen).toFixed(2)} < ${COVERAGE_RATIO}），疑似漏段或大幅改写`
        });
      }
      // 段落首字符种子查询：legacy 按句号/换行拆段，每段前 SEED_WINDOW 字到 H5 全文找
      const sentences = legacy.split(/[。\n]+/).map(s => s.trim()).filter(s => readableLength(s) >= SEED_WINDOW);
      for (const sent of sentences) {
        const seed = sent.replace(/\$\{PC_NAME\}/g, '').replace(/[\s　]+/g, '').slice(0, SEED_WINDOW);
        if (!seed) continue;
        if (!hasFuzzyMatch(page.plain, seed)) {
          findings.push({
            kind: 'sentence-seed-missing',
            severity: 'info',
            page: pk,
            message: `page ${pk} 句首种子「${seed}」未在 H5 出现（句子原文：「${sent.slice(0, 40)}${sent.length > 40 ? '…' : ''}」）`
          });
        }
      }
    }
  } else {
    findings.push({ kind: 'txt-missing', severity: 'info', page: null, message: 'legacy txt 文件不存在，跳过段落覆盖率检查' });
  }

  return { item: dictItem.name, findings };
}

function countOccurrences(haystack, needle) {
  if (!needle) return 0;
  let i = 0, count = 0;
  while ((i = haystack.indexOf(needle, i)) !== -1) {
    count += 1;
    i += needle.length;
  }
  return count;
}

function summarize(reports) {
  let warning = 0, error = 0, info = 0;
  for (const r of reports) {
    for (const f of r.findings) {
      if (f.severity === 'warning') warning += 1;
      else if (f.severity === 'error') error += 1;
      else info += 1;
    }
  }
  return { warning, error, info };
}

function printHuman(reports, totals) {
  for (const r of reports) {
    if (r.findings.length === 0) continue;
    console.log(`\n[${r.item}]`);
    for (const f of r.findings) {
      const tag = f.severity.toUpperCase().padEnd(7);
      console.log(`  ${tag} ${f.message}`);
    }
  }
  const itemsWithIssues = reports.filter(r => r.findings.length > 0).length;
  console.log(`\n[summary] ${reports.length} items audited, ${itemsWithIssues} have findings — error=${totals.error} warning=${totals.warning} info=${totals.info}`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  let items = parseDictionary();
  if (args.item) items = items.filter(x => x.name === args.item);
  if (items.length === 0) {
    console.error('no items matched');
    process.exit(2);
  }
  const reports = items.map(auditItem);
  const totals = summarize(reports);
  if (args.json) {
    console.log(JSON.stringify({ totals, reports }, null, 2));
  } else {
    printHuman(reports, totals);
  }
  if (totals.error > 0) process.exit(1);
  if (args.strict && totals.warning > 0) process.exit(1);
}

main();
