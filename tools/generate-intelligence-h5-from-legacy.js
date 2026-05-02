#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const dictPath = path.join(root, 'data', 'dictionaries', 'information_dictionary.xml');
const textDir = path.join(root, 'data', 'intelligence');
const outDir = path.join(root, 'data', 'intelligence_h5');

const DEMO_ITEMS = new Set([
  '资料',
  'ECHO-034的加密日志',
  '水厂外勤档案',
  '环线流民日记',
  '旧世残篇：西南自治区概况',
  'A兵团制式套装改造图纸',
  '黑铁会的秘密情报书',
  '幻层残响',
]);

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
}

function parseAttrs(source) {
  const attrs = {};
  source.replace(/([\w:-]+)\s*=\s*"([^"]*)"/g, (_, key, value) => {
    attrs[key] = value;
    return '';
  });
  return attrs;
}

function parseDictionary() {
  const xml = read(dictPath);
  const items = [];
  for (const match of xml.matchAll(/<Item>([\s\S]*?)<\/Item>/g)) {
    const body = match[1];
    const name = (body.match(/<Name>([\s\S]*?)<\/Name>/) || [])[1]?.trim();
    if (!name) continue;
    const index = Number((body.match(/<Index>(\d+)<\/Index>/) || [])[1] || 0);
    const pages = [];
    for (const info of body.matchAll(/<Information\s+([^/>]+?)\s*\/>/g)) {
      const attrs = parseAttrs(info[1]);
      if (attrs.PageKey) {
        pages.push({
          pageKey: attrs.PageKey,
          value: Number(attrs.Value || 0),
          encryptLevel: Number(attrs.EncryptLevel || 0),
        });
      }
    }
    items.push({ name, index, pages });
  }
  items.sort((a, b) => a.index - b.index || a.name.localeCompare(b.name, 'zh-Hans-CN'));
  return items;
}

function parseLegacyPages(content) {
  content = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const re = /^@@@([^@\n]+)@@@\s*$/gm;
  const markers = [];
  let match;
  while ((match = re.exec(content))) {
    markers.push({ key: match[1].trim(), start: match.index, after: re.lastIndex });
  }
  if (!markers.length) return { '1': content.trim() };
  const pages = {};
  markers.forEach((marker, index) => {
    pages[marker.key] = content.slice(marker.after, index + 1 < markers.length ? markers[index + 1].start : content.length).trim();
  });
  return pages;
}

function colorToToken(color) {
  const normalized = String(color || '').toUpperCase();
  if (normalized === '#FF0000' || normalized === '#FF3333' || normalized === '#FF6666') return 'danger';
  if (normalized === '#0099FF') return 'info';
  if (normalized === '#00CC00' || normalized === '#66FF66') return 'success';
  if (normalized === '#006600') return 'material-basic';
  if (normalized === '#996600') return 'material-mid';
  return 'warning';
}

function lineText(line) {
  return String(line || '')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function parseInline(source) {
  const tokens = [];
  const stack = [{ strong: false, underline: false, color: '' }];
  const tagRe = /<[^>]+>/g;
  let last = 0;
  let match;
  while ((match = tagRe.exec(source))) {
    emitText(source.slice(last, match.index), stack[stack.length - 1], tokens);
    handleTag(match[0], stack);
    last = tagRe.lastIndex;
  }
  emitText(source.slice(last), stack[stack.length - 1], tokens);
  return mergeTextTokens(tokens);
}

function handleTag(tag, stack) {
  const lower = tag.toLowerCase();
  if (/^<\s*\/\s*(b|strong|u|font)\s*>/.test(lower)) {
    if (stack.length > 1) stack.pop();
    return;
  }
  const top = stack[stack.length - 1];
  if (/^<\s*(b|strong)\b/.test(lower)) stack.push({ strong: true, underline: top.underline, color: top.color });
  else if (/^<\s*u\b/.test(lower)) stack.push({ strong: top.strong, underline: true, color: top.color });
  else if (/^<\s*font\b/.test(lower)) {
    const color = /\bcolor\s*=\s*['"]?([^'"\s>]+)['"]?/i.exec(tag);
    stack.push({ strong: top.strong, underline: top.underline, color: color ? colorToToken(color[1]) : top.color });
  } else if (/^<\s*br\s*\/?\s*>/.test(lower)) {
    // keep line structure at block level; inline br is intentionally ignored here
  }
}

function emitText(text, style, out) {
  if (!text) return;
  const re = /(\$\{PC_NAME\}|█+|\[已编辑\]|\[数据损毁\]|\[缺失\]|\[已删除\]|\[涂抹\]|\[签名模糊\])/g;
  let last = 0;
  let match;
  while ((match = re.exec(text))) {
    emitPlain(text.slice(last, match.index), style, out);
    const raw = match[1];
    if (raw === '${PC_NAME}') out.push(wrap({ type: 'pcName' }, style));
    else out.push(wrap(damageToken(raw), style));
    last = re.lastIndex;
  }
  emitPlain(text.slice(last), style, out);
}

function damageToken(raw) {
  const kindMap = {
    '[已编辑]': 'edited',
    '[数据损毁]': 'data-loss',
    '[缺失]': 'missing',
    '[已删除]': 'deleted',
    '[涂抹]': 'smear',
    '[签名模糊]': 'blurred',
  };
  if (/^█+$/.test(raw)) return { type: 'damageText', kind: 'data-loss', text: raw };
  return { type: 'damageText', kind: kindMap[raw] || 'data-loss', text: raw };
}

function emitPlain(text, style, out) {
  if (!text) return;
  out.push(wrap({ type: 'text', text }, style));
}

function wrap(token, style) {
  let current = token;
  if (style.color) current = { type: 'colorToken', token: style.color, content: [current] };
  if (style.underline) current = { type: 'underline', content: [current] };
  if (style.strong) current = { type: 'strong', content: [current] };
  return current;
}

function mergeTextTokens(tokens) {
  const out = [];
  tokens.forEach((token) => {
    const prev = out[out.length - 1];
    if (token.type === 'text' && prev && prev.type === 'text') prev.text += token.text;
    else out.push(token);
  });
  return out;
}

function chooseSkin(itemName) {
  if (/ECHO|终端|加密日志/.test(itemName)) return 'terminal';
  if (/图纸|配方/.test(itemName)) return 'blueprint';
  if (/黑铁书|秘密情报书|令$/.test(itemName)) return 'edict';
  if (/日记|手记|笔记/.test(itemName)) return 'diary';
  if (/档案|残篇|摘要/.test(itemName)) return 'dossier';
  if (/线报|采访|告急|动荡|风雨/.test(itemName)) return 'newspaper';
  if (/报告|证明|清单|情报/.test(itemName)) return 'report';
  return 'paper';
}

function buildBlocks(itemName, pageInfo, pageText) {
  const lines = pageText.split('\n').map((line) => line.trim()).filter(Boolean);
  const skin = chooseSkin(itemName);
  if (!lines.length) return [{ type: 'note', content: [{ type: 'text', text: '该页暂无可恢复内容。' }] }];

  if (skin === 'terminal') return buildTerminalBlocks(itemName, pageInfo, lines);
  if (skin === 'blueprint') return buildBlueprintBlocks(itemName, pageInfo, lines);

  const blocks = [];
  blocks.push(...surfaceMarksFor(itemName, pageInfo.pageKey));
  if (DEMO_ITEMS.has(itemName) && pageInfo.pageKey === '1_1' && /水厂外勤档案/.test(itemName)) {
    blocks.push({ type: 'stamp', tone: 'danger', content: [{ type: 'text', text: '机密档案夹' }] });
  }
  if (DEMO_ITEMS.has(itemName) && pageInfo.pageKey === '1' && /黑铁会的秘密情报书/.test(itemName)) {
    blocks.push({ type: 'stamp', tone: 'danger', content: [{ type: 'text', text: '教令' }] });
  }

  let paragraph = [];
  function flushParagraph() {
    if (!paragraph.length) return;
    blocks.push({ type: 'paragraph', content: joinInlineLines(paragraph) });
    paragraph = [];
  }

  lines.forEach((line) => {
    const clean = lineText(line);
    if (!clean) return;
    if (/批注|手写|铅笔|红字|档案人注记/.test(clean) && DEMO_ITEMS.has(itemName)) {
      flushParagraph();
      blocks.push({ type: 'handwritten', tone: /铅笔/.test(clean) ? 'dark' : 'red', content: parseInline(line) });
    } else if (/^【.*】$/.test(clean) || /^《.*》$/.test(clean) || /^第[一二三四五六七八九十]+[、.]/.test(clean)) {
      flushParagraph();
      blocks.push({ type: 'heading', level: 2, content: parseInline(line) });
    } else if (/^\*.*\*$/.test(clean)) {
      flushParagraph();
      blocks.push({ type: 'note', content: parseInline(line.replace(/^\*|\*$/g, '')) });
    } else if (/^[-•]/.test(clean)) {
      flushParagraph();
      blocks.push({ type: 'list', items: [parseInline(line.replace(/^[-•]\s*/, ''))] });
    } else {
      paragraph.push(parseInline(line));
    }
  });
  flushParagraph();

  const tableRows = collectKeyValueRows(lines);
  if (DEMO_ITEMS.has(itemName) && tableRows.length >= 3) {
    blocks.splice(Math.min(2, blocks.length), 0, {
      type: 'table',
      columns: ['字段', '内容'],
      rows: tableRows.slice(0, 8),
    });
  }

  if (DEMO_ITEMS.has(itemName) && /芯片|U ?盘|终端|黑匣子|缓存|密钥/.test(pageText)) {
    blocks.push({
      type: 'hardwareExtract',
      label: '离线介质提取',
      status: pageInfo.encryptLevel > 0 ? '需要解密等级 ' + pageInfo.encryptLevel : '可读取',
      steps: ['握手', '校验密钥', '抽取残片'],
      reveal: [{ type: 'note', content: [{ type: 'text', text: '硬件提取流程已建立，正文内容以当前解密等级显示。' }] }],
    });
  }

  return decorateEncryptedPage(itemName, pageInfo, blocks);
}

function buildTerminalBlocks(itemName, pageInfo, lines) {
  const entries = lines.map((line) => {
    const clean = lineText(line);
    let kind = 'text';
    if (/》》》|系统|WARNING|ERROR|PROTOCOL|权限|终端|上传|节点/.test(clean)) kind = 'system';
    else if (/^\[.*\]$/.test(clean)) kind = 'prompt';
    return { kind, content: parseInline(line) };
  });
  const blocks = surfaceMarksFor(itemName, pageInfo.pageKey);
  blocks.push({ type: 'terminalLog', title: itemName, entries });
  if (/芯片|终端|黑匣子|上传|节点/.test(lines.join('\n')) && DEMO_ITEMS.has(itemName)) {
    blocks.push({
      type: 'hardwareExtract',
      label: 'Project_ECHO 残片提取',
      status: pageInfo.encryptLevel > 0 ? '权限门槛 E' + pageInfo.encryptLevel : '链路不稳定',
      steps: ['恢复节点握手', '校验植入芯片记录', '抽取日志块'],
      reveal: [{ type: 'paragraph', content: [{ type: 'text', text: '该页来自受损终端缓存，提取结果会随解密等级稳定。' }] }],
    });
  }
  return decorateEncryptedPage(itemName, pageInfo, blocks);
}

function buildBlueprintBlocks(itemName, pageInfo, lines) {
  const blocks = surfaceMarksFor(itemName, pageInfo.pageKey);
  const materialLines = lines.filter((line) => /<font\b/i.test(line) || /材料|准备|需要|制作/.test(lineText(line))).slice(0, 8);
  blocks.push({
    type: 'blueprint',
    title: [{ type: 'text', text: itemName }],
    materials: materialLines.map((line) => parseInline(line)),
    steps: lines.filter((line) => /^\d+[.、]/.test(lineText(line))).slice(0, 8).map((line) => ({ content: parseInline(line) })),
  });
  lines.forEach((line) => {
    const clean = lineText(line);
    if (!clean) return;
    if (/^【.*】$/.test(clean) || /^《.*》$/.test(clean)) blocks.push({ type: 'heading', level: 2, content: parseInline(line) });
    else blocks.push({ type: 'paragraph', content: parseInline(line) });
  });
  return decorateEncryptedPage(itemName, pageInfo, blocks);
}

function decorateEncryptedPage(itemName, pageInfo, blocks) {
  if (pageInfo.encryptLevel <= 0 || !DEMO_ITEMS.has(itemName)) return blocks;
  return injectDecryptText(blocks, pageInfo.encryptLevel);
}

function injectDecryptText(value, level) {
  if (Array.isArray(value)) return value.map((item) => injectDecryptText(item, level));
  if (!value || typeof value !== 'object') return value;
  if (value.type === 'text') return value;
  const out = Array.isArray(value) ? [] : {};
  Object.keys(value).forEach((key) => {
    if (key === 'content' || key === 'title' || key === 'caption' || key === 'label' || key === 'note') {
      out[key] = injectInlineDecrypt(value[key], level);
    } else {
      out[key] = injectDecryptText(value[key], level);
    }
  });
  return out;
}

function injectInlineDecrypt(value, level) {
  if (!Array.isArray(value)) return value;
  const out = [];
  value.forEach((item) => {
    if (item && item.type === 'text') {
      out.push(...splitSensitiveText(item.text || '', level));
    } else if (item && typeof item === 'object' && Array.isArray(item.content)) {
      const copy = {};
      Object.keys(item).forEach((key) => {
        copy[key] = key === 'content' ? injectInlineDecrypt(item[key], level) : item[key];
      });
      out.push(copy);
    } else {
      out.push(item);
    }
  });
  return out;
}

function splitSensitiveText(text, level) {
  const sensitive = /(诺亚方舟计划组|诺亚组织|A兵团|统合部门|统合|WP|Project_ECHO|γ-ECHO|Protocol-\d+|外部接口人|外部接口|V-15C|密钥|芯片|黑匣子|终端|下水道|水样|异常样本|感染半径|间谍|特工|研究所)/g;
  const out = [];
  let last = 0;
  let match;
  while ((match = sensitive.exec(text))) {
    if (match.index > last) out.push({ type: 'text', text: text.slice(last, match.index) });
    out.push({
      type: 'decryptText',
      level,
      encryptedText: maskText(match[1]),
      content: [{ type: 'text', text: match[1] }],
    });
    last = sensitive.lastIndex;
  }
  if (last < text.length) out.push({ type: 'text', text: text.slice(last) });
  return out.length ? out : [{ type: 'text', text }];
}

function maskText(text) {
  return String(text || '').replace(/[^\s，。！？、,.!?;；:：()[\]【】《》"“”'·\-—_#0-9A-Za-z]/g, '█');
}

function surfaceMarksFor(itemName, pageKey) {
  if (!DEMO_ITEMS.has(itemName)) return [];
  const marks = [];
  if (itemName === '水厂外勤档案' && pageKey === '1_1') {
    marks.push({ type: 'surfaceMark', variant: 'water', x: 66, y: 7, w: 24, h: 18, rotate: -8, opacity: 0.38 });
    marks.push({ type: 'surfaceMark', variant: 'dirt', x: 7, y: 70, w: 18, h: 16, rotate: 16, opacity: 0.24 });
  } else if (itemName === 'ECHO-034的加密日志' && pageKey === '1_9') {
    marks.push({ type: 'surfaceMark', variant: 'blood-hand', x: 72, y: 8, w: 15, h: 18, rotate: 13, opacity: 0.42 });
  } else if (itemName === '旧世残篇：西南自治区概况' && pageKey === '1_1') {
    marks.push({ type: 'surfaceMark', variant: 'tear', x: 73, y: 1, w: 17, h: 26, rotate: 8, opacity: 0.36 });
    marks.push({ type: 'surfaceMark', variant: 'dirt', x: 12, y: 54, w: 26, h: 18, rotate: -10, opacity: 0.25 });
  } else if (itemName === '环线流民日记' && pageKey === '1_1') {
    marks.push({ type: 'surfaceMark', variant: 'fold', x: 49, y: 0, w: 6, h: 98, rotate: 0, opacity: 0.28 });
    marks.push({ type: 'surfaceMark', variant: 'dirt', x: 70, y: 62, w: 18, h: 16, rotate: 21, opacity: 0.26 });
  } else if (itemName === '黑铁会的秘密情报书' && pageKey === '1') {
    marks.push({ type: 'surfaceMark', variant: 'blood-hand', x: 77, y: 12, w: 13, h: 15, rotate: -16, opacity: 0.30 });
  } else if (itemName === '资料' && pageKey === '40') {
    marks.push({ type: 'surfaceMark', variant: 'fold', x: 8, y: 0, w: 8, h: 100, rotate: -2, opacity: 0.22 });
  }
  return marks;
}

function joinInlineLines(lines) {
  const out = [];
  lines.forEach((tokens, index) => {
    if (index > 0) out.push({ type: 'text', text: '\n' });
    out.push(...tokens);
  });
  return out;
}

function collectKeyValueRows(lines) {
  const rows = [];
  lines.forEach((line) => {
    const clean = lineText(line);
    const index = clean.indexOf('：');
    if (index <= 0 || index > 20) return;
    rows.push([parseInline(clean.slice(0, index)), parseInline(clean.slice(index + 1))]);
  });
  return rows;
}

function main() {
  fs.mkdirSync(outDir, { recursive: true });
  const items = parseDictionary();
  let written = 0;
  items.forEach((item) => {
    const textPath = path.join(textDir, `${item.name}.txt`);
    const pageText = fs.existsSync(textPath) ? parseLegacyPages(read(textPath)) : {};
    const doc = {
      schemaVersion: 1,
      itemName: item.name,
      skin: chooseSkin(item.name),
      pages: item.pages.map((page) => ({
        pageKey: page.pageKey,
        blocks: buildBlocks(item.name, page, pageText[page.pageKey] || ''),
      })),
    };
    fs.writeFileSync(path.join(outDir, `${item.name}.json`), JSON.stringify(doc, null, 2) + '\n', 'utf8');
    written += 1;
  });
  console.log(`[intelligence-h5] generated ${written} files in ${path.relative(root, outDir)}`);
}

main();
