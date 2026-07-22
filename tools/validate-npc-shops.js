#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { loadItemMeta } = require('./lib/item-icons');

const ROOT = path.resolve(__dirname, '..');
const SHOP_ROOT = path.join(ROOT, 'data', 'shops');
const LIST_PATH = path.join(SHOP_ROOT, 'list.xml');
const ID_RE = /^[A-Za-z0-9._-]{1,64}$/;

function fail(message) {
  throw new Error(message);
}

function readUtf8(file) {
  return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
}

function parseManifest() {
  const xml = readUtf8(LIST_PATH);
  const files = [];
  const re = /<shops>([^<]+)<\/shops>/g;
  let match;
  while ((match = re.exec(xml))) files.push(match[1].trim());
  if (!files.length) fail('data/shops/list.xml does not declare any <shops> files');
  return files;
}

function normalizeEntry(entry, context) {
  if (typeof entry === 'string') {
    if (!entry.trim()) fail(context + ': empty item name');
    return entry;
  }
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) fail(context + ': entry must be string or object');
  if (typeof entry.name !== 'string' || !entry.name.trim()) fail(context + ': object entry requires non-empty name');
  const allowed = new Set(['name', 'requiredInfo', 'purchaseLimit']);
  Object.keys(entry).forEach((key) => {
    if (!allowed.has(key)) fail(context + ': unsupported entry field ' + key);
  });
  if (entry.requiredInfo !== undefined && (typeof entry.requiredInfo !== 'string' || !entry.requiredInfo.trim())) {
    fail(context + ': requiredInfo must be a non-empty string when present');
  }
  if (entry.purchaseLimit !== undefined
      && (!Number.isSafeInteger(entry.purchaseLimit) || entry.purchaseLimit < 1 || entry.purchaseLimit > 999999)) {
    fail(context + ': purchaseLimit must be an integer from 1 to 999999 when present');
  }
  return entry.name;
}

function validateV2(doc, fileName, seenShopIds, itemMeta, groupingStats) {
  if (doc.schema !== 'npc-shop.v2') fail(fileName + ': schema must be npc-shop.v2');
  if (typeof doc.shopId !== 'string' || !doc.shopId.trim() || doc.shopId.length > 80) fail(fileName + ': invalid shopId');
  if (seenShopIds.has(doc.shopId)) fail(fileName + ': duplicate shopId ' + doc.shopId);
  seenShopIds.add(doc.shopId);
  if (doc.title !== undefined && (typeof doc.title !== 'string' || !doc.title.trim())) fail(fileName + ': invalid title');
  if (!doc.catalog || typeof doc.catalog !== 'object' || Array.isArray(doc.catalog)) fail(fileName + ': catalog must be an object');

  const indexes = Object.keys(doc.catalog).map((key) => {
    if (!/^\d+$/.test(key)) fail(fileName + ': catalog key must be a non-negative integer: ' + key);
    const index = Number(key);
    if (!Number.isSafeInteger(index) || index < 0 || index > 10000) fail(fileName + ': catalog index out of range: ' + key);
    const itemName = normalizeEntry(doc.catalog[key], fileName + ' catalog[' + key + ']');
    const item = itemMeta[itemName] || itemMeta[itemName.trim()];
    if (!item) fail(fileName + ' catalog[' + key + ']: unknown data/items name ' + itemName);
    if (!item.type || !item.use) groupingStats.other += 1;
    else if (item.type === '武器' && !item.actiontype && !item.weapontype) groupingStats.weaponOther += 1;
    return index;
  });
  const indexSet = new Set(indexes);

  const sections = doc.sections === undefined ? [] : doc.sections;
  if (!Array.isArray(sections)) fail(fileName + ': sections must be an array');
  if (sections.length) groupingStats.manualShops += 1;
  if (sections.length > 24) fail(fileName + ': too many sections');
  const seenSections = new Set();
  const covered = new Set();
  sections.forEach((section, sectionIndex) => {
    const context = fileName + ' sections[' + sectionIndex + ']';
    if (!section || typeof section !== 'object' || Array.isArray(section)) fail(context + ': section must be an object');
    if (typeof section.id !== 'string' || !ID_RE.test(section.id) || section.id === 'all') fail(context + ': invalid/reserved id');
    if (!seenSections.add(section.id)) fail(context + ': duplicate id ' + section.id);
    if (typeof section.label !== 'string' || !section.label.trim() || section.label.length > 16) fail(context + ': invalid label');
    if (section.kind !== undefined && (typeof section.kind !== 'string' || !ID_RE.test(section.kind))) fail(context + ': invalid kind');
    if (!Array.isArray(section.entries) || !section.entries.length) fail(context + ': entries must be a non-empty array');
    const local = new Set();
    section.entries.forEach((value) => {
      if (!Number.isSafeInteger(value) || value < 0 || !indexSet.has(value)) fail(context + ': unknown catalog index ' + value);
      if (!local.add(value)) fail(context + ': duplicate catalog index ' + value);
      covered.add(value);
    });
  });
  if (sections.length) {
    indexes.forEach((index) => {
      if (!covered.has(index)) fail(fileName + ': catalog index ' + index + ' is not covered by any section');
    });
    if (doc.defaultSection !== undefined && !seenSections.has(doc.defaultSection)) {
      fail(fileName + ': defaultSection does not reference a declared section');
    }
  } else if (doc.defaultSection !== undefined) {
    fail(fileName + ': defaultSection requires sections');
  }
  return indexes.length;
}

function main() {
  const files = parseManifest();
  const seenFiles = new Set();
  const seenShopIds = new Set();
  const itemMeta = loadItemMeta(ROOT, fail);
  const groupingStats = {other:0, weaponOther:0, manualShops:0};
  let entries = 0;
  files.forEach((relative) => {
    if (path.isAbsolute(relative) || relative.includes('..')) fail('unsafe shops path: ' + relative);
    if (!seenFiles.add(relative.toLowerCase())) fail('duplicate shops manifest entry: ' + relative);
    const file = path.resolve(SHOP_ROOT, relative);
    if (!file.startsWith(SHOP_ROOT + path.sep)) fail('shops path escapes data/shops: ' + relative);
    if (!fs.existsSync(file)) fail('missing shops file: ' + relative);
    let doc;
    try { doc = JSON.parse(readUtf8(file)); }
    catch (error) { fail(relative + ': invalid JSON: ' + error.message); }
    entries += validateV2(doc, relative, seenShopIds, itemMeta, groupingStats);
  });
  process.stdout.write('[npc-shops] ok (' + seenShopIds.size + ' NPC files, ' + entries + ' catalog entries; auto-group fallback other='
    + groupingStats.other + ', weapon-subtype-other=' + groupingStats.weaponOther + ', manual-shops=' + groupingStats.manualShops + ')\n');
}

try { main(); }
catch (error) {
  process.stderr.write('[npc-shops] FAIL: ' + (error && error.message ? error.message : String(error)) + '\n');
  process.exit(1);
}
