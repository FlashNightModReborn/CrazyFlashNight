#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const dictPath = path.join(root, 'data', 'dictionaries', 'information_dictionary.xml');
const outDir = path.join(root, 'tmp', 'intelligence-h5-prompts');

function parseArgs(argv) {
  const args = { batchSize: 10, start: 0 };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--batch-size') {
      args.batchSize = Number(argv[++i]) || 10;
    } else if (arg === '--start') {
      args.start = Number(argv[++i]) || 0;
    } else if (arg === '--help' || arg === '-h') {
      console.log('usage: node tools/generate-intelligence-h5-prompts.js [--batch-size 10] [--start 0]');
      process.exit(0);
    } else {
      throw new Error('unknown arg: ' + arg);
    }
  }
  return args;
}

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
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
      const attrs = {};
      info[1].replace(/([\w:-]+)\s*=\s*"([^"]*)"/g, (_, key, value) => {
        attrs[key] = value;
        return '';
      });
      if (attrs.PageKey) pages.push({ pageKey: attrs.PageKey, value: attrs.Value || '0', encryptLevel: attrs.EncryptLevel || '0' });
    }
    items.push({ name, index, pages });
  }
  items.sort((a, b) => a.index - b.index || a.name.localeCompare(b.name, 'zh-Hans-CN'));
  return items;
}

function promptForBatch(batch, batchIndex) {
  const names = batch.map((item) => item.name).join('、');
  const pageLines = batch.map((item) => {
    return `- ${item.name}: ${item.pages.map((page) => `${page.pageKey}(value=${page.value}, E=${page.encryptLevel})`).join(', ')}`;
  }).join('\n');
  return `# KimiCode 情报 H5 批量迁移任务 ${batchIndex}

你只允许修改 \`data/intelligence_h5/\` 下本批次目标 JSON 文件，不要修改 renderer、CSS、C#、validator、legacy txt 或 XML。

## 目标条目
${names}

## PageKey 契约
${pageLines}

## 源文件
- legacy 文本：\`data/intelligence/<itemName>.txt\`
- 字典：\`data/dictionaries/information_dictionary.xml\`
- 物品描述与图标：\`data/items/收集品_情报.xml\`

## 输出格式
每个文件写为 \`data/intelligence_h5/<itemName>.json\`：
\`\`\`json
{
  "schemaVersion": 1,
  "itemName": "条目名",
  "skin": "paper|report|dossier|terminal|newspaper|blueprint|diary|edict",
  "pages": [
    { "pageKey": "1", "blocks": [] }
  ]
}
\`\`\`

## 组件白名单
block: paragraph, heading, list, table, quote, divider, stamp, note, handwritten, annotation, terminalLog, redaction, decryptBlock, blueprint, timeline, hardwareExtract, surfaceMark

inline: text, strong, underline, colorToken, damageText, redaction, decryptText, pcName

## 约束
- \`pages[].pageKey\` 必须与上方 PageKey 契约完全一致，顺序也一致。
- 不允许 HTML 字符串、不允许 <script>、不允许 on* 事件、不允许 javascript: URL。
- 旧 \`<b>\` 转 strong，\`<u>\` 转 underline，\`<font color>\` 转 colorToken。
- \`\${PC_NAME}\` 转 \`{ "type": "pcName" }\`。
- 手写批注、档案人注记、铅笔/红字旁注优先转 handwritten block。
- [已编辑]、[数据损毁]、[缺失]、[已删除]、[涂抹]、[签名模糊] 等不可恢复占位优先转 damageText；只有存在真实可 reveal 明文时才使用 redaction。
- 段落内需要“鼠标悬浮/点击显示明文”的局部密文优先转 decryptText，不要把整页包成 decryptBlock。
- 终端/芯片/U盘/黑匣子/缓存/上传内容可用 terminalLog 或 hardwareExtract。
- 图纸/配方/材料清单可用 blueprint 或 table。
- 污垢、水痕、血手印、折痕、破损边缘等纸面痕迹可用 surfaceMark，variant 使用 dirt / water / blood-hand / fold / tear。

## 验收
完成后必须通过：
\`\`\`
node tools/validate-intelligence-h5.js --allow-missing
\`\`\`
`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  fs.mkdirSync(outDir, { recursive: true });
  const items = parseDictionary().slice(args.start);
  let batchIndex = 1;
  for (let i = 0; i < items.length; i += args.batchSize) {
    const batch = items.slice(i, i + args.batchSize);
    const filePath = path.join(outDir, `batch-${String(batchIndex).padStart(2, '0')}.md`);
    fs.writeFileSync(filePath, promptForBatch(batch, batchIndex), 'utf8');
    batchIndex += 1;
  }
  console.log(`[intelligence-h5-prompts] wrote ${batchIndex - 1} prompt files to ${path.relative(root, outDir)}`);
}

main();
