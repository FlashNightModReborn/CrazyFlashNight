#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const modsDir = path.join(root, 'data', 'items', 'equipment_mods');
const listPath = path.join(modsDir, 'list.xml');
const expectedGrades = {
  low: { prefix: '低级材料_', color: '#006600' },
  medium: { prefix: '中等材料_', color: '#996600' },
  high: { prefix: '高等材料_', color: '#0099FF' },
  special: { prefix: '特殊材料_', color: '#FFFF00' }
};
const allowedSymbols = new Set([
  'triangle-solid', 'triangle-outline',
  'square-solid', 'square-outline',
  'circle-solid', 'circle-outline',
  'diamond-solid', 'diamond-outline',
  'star-solid', 'star-outline'
]);

function read(file) {
  return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
}

function blocks(xml, tag) {
  const result = [];
  const pattern = new RegExp('<' + tag + '>([\\s\\S]*?)<\\/' + tag + '>', 'g');
  let match;
  while ((match = pattern.exec(xml))) result.push(match[1]);
  return result;
}

function text(xml, tag) {
  const match = new RegExp('<' + tag + '>([\\s\\S]*?)<\\/' + tag + '>').exec(xml);
  return match ? match[1].trim().replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&') : '';
}

function fail(errors, message) {
  errors.push(message);
}

const errors = [];
const listXml = read(listPath);
const presentationName = text(listXml, 'uiPresentation');
if (!presentationName) fail(errors, 'list.xml 缺少 <uiPresentation>');
const presentationPath = path.join(modsDir, presentationName || 'ui_presentation.xml');
if (!fs.existsSync(presentationPath)) fail(errors, '展示词典不存在: ' + presentationPath);

const presentationXml = fs.existsSync(presentationPath) ? read(presentationPath) : '';
const gradeMap = new Map();
for (const block of blocks(presentationXml, 'grade')) {
  const id = text(block, 'id');
  const color = text(block, 'color');
  if (!expectedGrades[id]) fail(errors, '未知 grade id: ' + id);
  else if (color !== expectedGrades[id].color) fail(errors, id + ' 色号应为 ' + expectedGrades[id].color + '，实际为 ' + color);
  if (gradeMap.has(id)) fail(errors, '重复 grade id: ' + id);
  gradeMap.set(id, { color, label: text(block, 'label') });
}
for (const id of Object.keys(expectedGrades)) {
  if (!gradeMap.has(id)) fail(errors, '缺少 grade: ' + id);
}

const roleMap = new Map();
for (const block of blocks(presentationXml, 'role')) {
  const id = text(block, 'id');
  const symbol = text(block, 'symbol');
  // tagDefault 内也有 <role> 文本；这里只消费带 <id> 的根级角色定义。
  if (!id) continue;
  if (!allowedSymbols.has(symbol)) fail(errors, 'role ' + id + ' 使用非法 symbol: ' + symbol);
  if (roleMap.has(id)) fail(errors, '重复 role id: ' + id);
  roleMap.set(id, { symbol, label: text(block, 'label') });
}

const tagDefaults = new Map();
for (const block of blocks(presentationXml, 'tagDefault')) {
  const tag = text(block, 'tag');
  const role = text(block, 'role');
  if (!roleMap.has(role)) fail(errors, 'tag ' + tag + ' 指向未知 role: ' + role);
  if (tagDefaults.has(tag)) fail(errors, '重复 tagDefault: ' + tag);
  tagDefaults.set(tag, role);
}

const fallbackRole = text(presentationXml, 'fallbackRole');
if (!roleMap.has(fallbackRole)) fail(errors, 'fallbackRole 未注册: ' + fallbackRole);

const sourceFiles = blocks(listXml, 'items').map(value => value.trim());
const names = new Set();
const seenTags = new Set();
const counts = { low: 0, medium: 0, high: 0, special: 0 };
let total = 0;

for (const fileName of sourceFiles) {
  const grade = Object.keys(expectedGrades).find(id => fileName.startsWith(expectedGrades[id].prefix));
  if (!grade) {
    fail(errors, '无法从文件名前缀解析档级: ' + fileName);
    continue;
  }
  const filePath = path.join(modsDir, fileName);
  if (!fs.existsSync(filePath)) {
    fail(errors, '插件文件不存在: ' + fileName);
    continue;
  }
  for (const block of blocks(read(filePath), 'mod')) {
    const name = text(block, 'name');
    const tag = text(block, 'tag');
    const explicitRole = text(block, 'uiRole');
    const role = explicitRole || tagDefaults.get(tag);
    total += 1;
    counts[grade] += 1;
    seenTags.add(tag);
    if (!name) fail(errors, fileName + ' 存在无名称 mod');
    if (names.has(name)) fail(errors, '重复插件名: ' + name);
    names.add(name);
    if (!tag) fail(errors, name + ' 缺少 tag');
    if (!role) fail(errors, name + ' 的 tag 缺少默认 uiRole: ' + tag);
    else if (!roleMap.has(role)) fail(errors, name + ' 解析到未知 uiRole: ' + role);
  }
}

for (const tag of tagDefaults.keys()) {
  if (!seenTags.has(tag)) fail(errors, 'ui_presentation.xml 存在未使用的 tagDefault: ' + tag);
}

if (errors.length) {
  for (const error of errors) console.error('[equipment-mod-ui] ERROR ' + error);
  process.exit(1);
}

console.log('[equipment-mod-ui] ok mods=' + total
  + ' low=' + counts.low + ' medium=' + counts.medium
  + ' high=' + counts.high + ' special=' + counts.special
  + ' tags=' + seenTags.size + ' roles=' + roleMap.size);
