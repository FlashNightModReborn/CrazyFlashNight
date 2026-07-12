#!/usr/bin/env node
'use strict';

// 只生成待人工复核的防具套装候选；结果不得直接进入运行时或批量购买意图。
const fs = require('fs');
const path = require('path');
const { loadItemMeta } = require('./lib/item-icons');

const ROOT = path.resolve(__dirname, '..');
const SHOP_ROOT = path.join(ROOT, 'data', 'shops');
const SLOT_SUFFIXES = [
  '头部装备','颈部装备','上装装备','手部装备','下装装备','脚部装备',
  '战术背心','战术上衣','战术裤子','战术裤','战术手套','战术鞋',
  '猪鼻式防毒面具','防毒面具','夜视仪','太阳镜','墨镜','眼镜',
  '上衣','裤子','短裤','长裤','裙子','短裙','手套','鞋子','皮鞋','军靴','鞋',
  '头盔','头套','面具','帽子','帽','领子','背心','马甲','夹克','校服','上装','下装','衣服','头','衣','裙'
].sort((a, b) => b.length - a.length);
const WEAK_STEMS = new Set(['黑色','白色','红色','蓝色','灰色','棕色','绿色','战术','军用','普通','新手']);

function fail(message) { throw new Error(message); }
function read(file) { return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''); }
function shopFiles() {
  const raw = read(path.join(SHOP_ROOT, 'list.xml')), result = [];
  const re = /<shops>\s*([^<]+?)\s*<\/shops>/g; let match;
  while ((match = re.exec(raw))) result.push(match[1]);
  return result;
}
function stemOf(name) {
  let stem = String(name || '').replace(/-NPC$/i, '').replace(/[·・\s]+/g, '').trim();
  for (let i = 0; i < SLOT_SUFFIXES.length; i += 1) {
    const suffix = SLOT_SUFFIXES[i];
    if (stem.endsWith(suffix) && stem.length > suffix.length + 1) { stem = stem.slice(0, -suffix.length); break; }
  }
  return stem;
}
function main() {
  const meta = loadItemMeta(ROOT, fail), candidates = [];
  shopFiles().forEach((relative) => {
    const doc = JSON.parse(read(path.join(SHOP_ROOT, relative))), groups = new Map();
    Object.keys(doc.catalog || {}).forEach((index) => {
      const raw = doc.catalog[index], name = typeof raw === 'string' ? raw : raw.name, item = meta[name];
      if (!item || item.type !== '防具') return;
      const stem = stemOf(name);
      if (stem.length < 2 || WEAK_STEMS.has(stem)) return;
      if (!groups.has(stem)) groups.set(stem, []);
      groups.get(stem).push({catalogIndex:Number(index), name, slot:item.use});
    });
    groups.forEach((items, stem) => {
      const slots = Array.from(new Set(items.map((item) => item.slot))).filter(Boolean);
      if (slots.length < 2) return;
      const slotCounts = {};
      items.forEach((item) => { slotCounts[item.slot] = (slotCounts[item.slot] || 0) + 1; });
      const ambiguousSlots = Object.keys(slotCounts).filter((slot) => slotCounts[slot] > 1);
      candidates.push({
        shopId:doc.shopId, stem, confidence:slots.length >= 4 ? 'high' : (slots.length >= 3 ? 'medium' : 'low'),
        slots, ambiguousSlots, items:items.sort((a, b) => a.catalogIndex - b.catalogIndex)
      });
    });
  });
  candidates.sort((a, b) => b.slots.length - a.slots.length || a.shopId.localeCompare(b.shopId, 'zh-CN') || a.stem.localeCompare(b.stem, 'zh-CN'));
  if (process.argv.includes('--check')) {
    if (!candidates.length || candidates.some((candidate) => candidate.slots.length < 2)) fail('candidate contract is empty or malformed');
    process.stdout.write('[equipment-set-candidates] check ok (' + candidates.length + ' review-only candidate(s), runtimeAuthoritative=false)\n');
    return;
  }
  if (process.argv.includes('--json')) {
    process.stdout.write(JSON.stringify({schema:'equipment-set-candidates.v1',runtimeAuthoritative:false,candidates}, null, 2) + '\n');
    return;
  }
  process.stdout.write('[equipment-set-candidates] ' + candidates.length + ' heuristic candidate(s); review only, never runtime authoritative\n');
  candidates.forEach((candidate) => {
    const ambiguity = candidate.ambiguousSlots.length ? ' ambiguous=' + candidate.ambiguousSlots.join(',') : '';
    process.stdout.write('- [' + candidate.confidence + '] ' + candidate.shopId + ' / ' + candidate.stem
      + ' (' + candidate.slots.join(',') + ')' + ambiguity + '\n');
    process.stdout.write('  ' + candidate.items.map((item) => item.catalogIndex + ':' + item.name).join(' | ') + '\n');
  });
}

try { main(); }
catch (error) { process.stderr.write('[equipment-set-candidates] FAIL: ' + (error.message || String(error)) + '\n'); process.exit(1); }
