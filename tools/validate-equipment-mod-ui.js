#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const modsDir = path.join(root, 'data', 'items', 'equipment_mods');
const listPath = path.join(modsDir, 'list.xml');
const itemListPath = path.join(root, 'data', 'items', 'list.xml');
const expectedGrades = {
  low: { color: '#006600' },
  medium: { color: '#996600' },
  high: { color: '#0099FF' },
  special: { color: '#FFFF00' }
};
const expectedScopes = new Set(['armor', 'firearm', 'blade', 'fist', 'universal', 'underbarrel']);
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

const scopeMap = new Map();
for (const block of blocks(presentationXml, 'scope')) {
  const id = text(block, 'id');
  const label = text(block, 'label');
  if (!expectedScopes.has(id)) fail(errors, '未知 scope id: ' + id);
  if (!label) fail(errors, 'scope ' + id + ' 缺少 label');
  if (scopeMap.has(id)) fail(errors, '重复 scope id: ' + id);
  scopeMap.set(id, { label });
}
for (const id of expectedScopes) {
  if (!scopeMap.has(id)) fail(errors, '缺少 scope: ' + id);
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
const scopeCounts = Object.fromEntries(Array.from(expectedScopes, id => [id, 0]));
let total = 0;

for (const fileName of sourceFiles) {
  const filePath = path.join(modsDir, fileName);
  if (!fs.existsSync(filePath)) {
    fail(errors, '插件文件不存在: ' + fileName);
    continue;
  }
  const sourceXml = read(filePath);
  const grade = text(sourceXml, 'modGrade');
  const scope = text(sourceXml, 'catalogScope');
  if (!expectedGrades[grade]) fail(errors, fileName + ' 缺少或使用非法 <modGrade>: ' + grade);
  if (!scopeMap.has(scope)) fail(errors, fileName + ' 缺少或使用非法 <catalogScope>: ' + scope);
  for (const block of blocks(sourceXml, 'mod')) {
    const name = text(block, 'name');
    const tag = text(block, 'tag');
    const explicitRole = text(block, 'uiRole');
    const role = explicitRole || tagDefaults.get(tag);
    total += 1;
    if (expectedGrades[grade]) counts[grade] += 1;
    if (scopeCounts[scope] != null) scopeCounts[scope] += 1;
    seenTags.add(tag);
    if (!name) fail(errors, fileName + ' 存在无名称 mod');
    if (names.has(name)) fail(errors, '重复插件名: ' + name);
    names.add(name);
    if (!tag) fail(errors, name + ' 缺少 tag');
    if (!role) fail(errors, name + ' 的 tag 缺少默认 uiRole: ' + tag);
    else if (!roleMap.has(role)) fail(errors, name + ' 解析到未知 uiRole: ' + role);
  }
}

const itemListXml = read(itemListPath);
const itemFiles = blocks(itemListXml, 'items').map(value => value.trim());
const itemNameCounts = new Map();
const pluginMaterialNames = new Set();
for (const fileName of itemFiles) {
  const filePath = path.join(root, 'data', 'items', fileName);
  if (!fs.existsSync(filePath)) {
    fail(errors, '物品列表引用了不存在的文件: ' + fileName);
    continue;
  }
  for (const block of blocks(read(filePath), 'item')) {
    const name = text(block, 'name');
    if (!name) continue;
    itemNameCounts.set(name, (itemNameCounts.get(name) || 0) + 1);
    if (fileName === '收集品_材料_插件.xml') pluginMaterialNames.add(name);
  }
}
for (const name of names) {
  const count = itemNameCounts.get(name) || 0;
  if (count !== 1) fail(errors, '插件定义必须唯一对应一个材料物品: ' + name + ' (当前 ' + count + ')');
}
for (const name of pluginMaterialNames) {
  if (!names.has(name)) fail(errors, '插件材料物品没有对应 mod 定义: ' + name);
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
  + ' scopes=' + Object.entries(scopeCounts).map(([id, count]) => id + ':' + count).join(',')
  + ' tags=' + seenTags.size + ' roles=' + roleMap.size
  + ' pluginMaterials=' + pluginMaterialNames.size);
