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

const hitBehaviorRequiredKeys = [
  'type', 'stackGroup', 'profileId',
  'decayDelay', 'decayInterval', 'maxStacks',
  'hitStacks', 'breakStacks', 'milestoneInterval',
  'damagePerStack', 'crumblePerMilestone', 'executeAtMax',
  'sameSourceOnly'
];
const hitBehaviorAllowedKeySet = new Set(hitBehaviorRequiredKeys);
const hitBehaviorIntKeys = new Set([
  'decayDelay', 'decayInterval', 'maxStacks',
  'hitStacks', 'breakStacks', 'milestoneInterval'
]);
const hitBehaviorFloatKeys = new Set([
  'damagePerStack', 'crumblePerMilestone', 'executeAtMax'
]);
const hitBehaviorProfileIndex = new Map();
let hitBehaviorProfileCount = 0;

function parseChildTags(xmlFragment) {
  const tags = [];
  const re = /<([A-Za-z0-9_]+)(?:\s[^>]*)?>([\s\S]*?)<\/\1>/g;
  let m;
  while ((m = re.exec(xmlFragment))) {
    tags.push({ name: m[1], value: m[2].trim() });
  }
  return tags;
}

function validateHitBehaviorXmlBlock(errors, modName, location, hbXml) {
  const childTags = parseChildTags(hbXml);
  const map = new Map();
  for (const t of childTags) {
    if (!hitBehaviorAllowedKeySet.has(t.name)) {
      fail(errors, `[hitBehavior:HB_UNKNOWN_FIELD] ${modName} (${location}) 含未知字段 <${t.name}>`);
    }
    if (map.has(t.name)) {
      fail(errors, `[hitBehavior:HB_DUPLICATE_FIELD] ${modName} (${location}) 重复声明字段 <${t.name}>`);
    }
    map.set(t.name, t.value);
  }
  for (const reqKey of hitBehaviorRequiredKeys) {
    if (!map.has(reqKey) || map.get(reqKey) === '') {
      fail(errors, `[hitBehavior:HB_MISSING_FIELD] ${modName} (${location}) 缺少必填字段 <${reqKey}>`);
    }
  }
  if (map.size < hitBehaviorRequiredKeys.length) return null;

  const type = map.get('type');
  if (type !== 'grayGooPrimer' && type !== 'toughnessVulnerabilityPrimer') {
    fail(errors, `[hitBehavior:HB_UNSUPPORTED_BEHAVIOR_TYPE] ${modName} (${location}) 非法 type: ${type}`);
  }
  const stackGroup = map.get('stackGroup');
  const profileId = map.get('profileId');
  if (!stackGroup || stackGroup.includes('|')) {
    fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) 非法 stackGroup: ${stackGroup}`);
  }
  if (!profileId || profileId.includes('|')) {
    fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) 非法 profileId: ${profileId}`);
  }
  const sameSourceOnlyRaw = map.get('sameSourceOnly');
  if (sameSourceOnlyRaw !== 'true' && sameSourceOnlyRaw !== 'false') {
    fail(errors, `[hitBehavior:HB_TYPE_MISMATCH] ${modName} (${location}) sameSourceOnly 必须为 true/false`);
  }

  const nums = {};
  for (const k of hitBehaviorIntKeys) {
    const raw = map.get(k);
    const n = Number(raw);
    if (!Number.isFinite(n) || !/^-?\d+$/.test(raw)) {
      fail(errors, `[hitBehavior:HB_TYPE_MISMATCH] ${modName} (${location}) <${k}> 必须为整数: ${raw}`);
    }
    nums[k] = n;
  }
  for (const k of hitBehaviorFloatKeys) {
    const raw = map.get(k);
    const n = Number(raw);
    if (!Number.isFinite(n)) {
      fail(errors, `[hitBehavior:HB_INVALID_NUMBER] ${modName} (${location}) <${k}> 必须为有限数值: ${raw}`);
    }
    nums[k] = n;
  }

  if (nums.decayDelay < 1) fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) decayDelay < 1`);
  if (nums.decayInterval < 1) fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) decayInterval < 1`);
  if (nums.maxStacks < 1 || nums.maxStacks > 18) fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) maxStacks 超出 [1,18]`);
  if (nums.milestoneInterval < 1 || nums.milestoneInterval > nums.maxStacks || (nums.maxStacks % nums.milestoneInterval) !== 0 || (nums.maxStacks / nums.milestoneInterval) < 1 || (nums.maxStacks / nums.milestoneInterval) > 3) {
    fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) milestoneInterval 必须整除 maxStacks 且节点数在 1..3 之间`);
  }
  if (nums.hitStacks < 1 || nums.hitStacks >= nums.milestoneInterval || nums.hitStacks > nums.maxStacks) {
    fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) hitStacks 必须满足 1 <= hitStacks < milestoneInterval`);
  }
  if (nums.breakStacks < 1 || nums.breakStacks > nums.maxStacks) {
    fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) breakStacks 超出 [1,maxStacks]`);
  }
  if (nums.damagePerStack < 0 || nums.damagePerStack > 1) fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) damagePerStack 超出 [0,1]`);
  if (nums.crumblePerMilestone < 0 || nums.crumblePerMilestone > 100) fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) crumblePerMilestone 超出 [0,100]`);
  if (nums.executeAtMax < 0 || nums.executeAtMax > 100) fail(errors, `[hitBehavior:HB_OUT_OF_RANGE] ${modName} (${location}) executeAtMax 超出 [0,100]`);

  const profile = {
    type,
    stackGroup,
    profileId,
    sameSourceOnly: sameSourceOnlyRaw === 'true',
    ...nums
  };
  const identityKey = `${stackGroup}|${profileId}`;
  const shapeJson = JSON.stringify({
    type: profile.type,
    maxStacks: profile.maxStacks,
    milestoneInterval: profile.milestoneInterval,
    damagePerStack: profile.damagePerStack,
    sameSourceOnly: profile.sameSourceOnly,
    decayDelay: profile.decayDelay,
    decayInterval: profile.decayInterval,
    hitStacks: profile.hitStacks,
    breakStacks: profile.breakStacks,
    crumblePerMilestone: profile.crumblePerMilestone,
    executeAtMax: profile.executeAtMax
  });
  if (hitBehaviorProfileIndex.has(identityKey)) {
    const prev = hitBehaviorProfileIndex.get(identityKey);
    if (prev.shapeJson !== shapeJson) {
      fail(errors, `[hitBehavior:HB_IDENTITY_SHAPE_CONFLICT] ${modName} (${location}) 的 (${identityKey}) 与 ${prev.location} 形状不一致`);
    }
  } else {
    hitBehaviorProfileIndex.set(identityKey, { shapeJson, location: `${modName}:${location}`, profile });
  }
  hitBehaviorProfileCount += 1;
  return profile;
}

function validateModHitBehaviorContract(errors, modName, modBlock) {
  if (!modBlock.includes('<hitBehavior>')) return;

  // 禁止在 merge / softOverride / lockOverride / baseSwitch / tagSwitch / bulletSwitch 中声明 hitBehavior
  for (const badOp of ['merge', 'softOverride', 'lockOverride', 'baseSwitch', 'tagSwitch', 'bulletSwitch']) {
    for (const opBlock of blocks(modBlock, badOp)) {
      if (opBlock.includes('<hitBehavior>')) {
        fail(errors, `[hitBehavior:HB_OPERATOR_CONFLICT] ${modName} 在 <${badOp}> 中声明了 <hitBehavior>，必须使用完整 <override><hitBehavior>`);
      }
    }
  }

  const statsBlocks = blocks(modBlock, 'stats');
  if (statsBlocks.length !== 1) return;
  const statsXml = statsBlocks[0];
  const statsWithoutUseSwitch = statsXml.replace(/<useSwitch>[\s\S]*?<\/useSwitch>/g, '');
  const rootOverrides = blocks(statsWithoutUseSwitch, 'override');
  let rootHbCount = 0;
  for (const ov of rootOverrides) {
    for (const hb of blocks(ov, 'hitBehavior')) {
      rootHbCount += 1;
      validateHitBehaviorXmlBlock(errors, modName, 'stats.override.hitBehavior', hb);
    }
  }

  const useSwitchBlocks = blocks(statsXml, 'useSwitch');
  let branchHbCount = 0;
  for (const us of useSwitchBlocks) {
    const useRe = /<use(?:\s+name="([^"]*)")?\s*>([\s\S]*?)<\/use>/g;
    let m;
    while ((m = useRe.exec(us))) {
      const useName = (m[1] || 'default').trim();
      const useBody = m[2];
      for (const ov of blocks(useBody, 'override')) {
        for (const hb of blocks(ov, 'hitBehavior')) {
          branchHbCount += 1;
          validateHitBehaviorXmlBlock(errors, modName, `useSwitch[${useName}].override.hitBehavior`, hb);
        }
      }
    }
  }

  if (branchHbCount > 0 && rootHbCount === 0) {
    fail(errors, `[hitBehavior:HB_MISSING_FIELD] ${modName} 在 useSwitch 中声明了 override.hitBehavior，但缺少根级 stats.override.hitBehavior`);
  }
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
    validateModHitBehaviorContract(errors, name, block);
  }
}

// 验证灰蛊裂隙弹三档完整黄金数值契约（#208）
const expectedGrayGooProfiles = {
  'grayGooVulnerability|base': { crumblePerMilestone: 1, executeAtMax: 8, hitStacks: 1, breakStacks: 1, decayDelay: 90, decayInterval: 10 },
  'grayGooVulnerability|highPowerHandgun': { crumblePerMilestone: 0.1, executeAtMax: 5, hitStacks: 2, breakStacks: 2, decayDelay: 90, decayInterval: 10 },
  'grayGooVulnerability|handgun': { crumblePerMilestone: 0.3, executeAtMax: 8, hitStacks: 3, breakStacks: 3, decayDelay: 150, decayInterval: 15 }
};
for (const [idKey, exp] of Object.entries(expectedGrayGooProfiles)) {
  const entry = hitBehaviorProfileIndex.get(idKey);
  if (!entry) {
    fail(errors, `[hitBehavior:GOLDEN_MISSING] 缺少灰蛊裂隙弹黄金档位: ${idKey}`);
    continue;
  }
  const p = entry.profile;
  for (const [k, v] of Object.entries(exp)) {
    if (p[k] !== v) {
      fail(errors, `[hitBehavior:GOLDEN_MISMATCH] ${idKey}.${k} 期望 ${v}，实际 ${p[k]}`);
    }
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
  + ' pluginMaterials=' + pluginMaterialNames.size
  + ' hitBehaviorProfiles=' + hitBehaviorProfileCount);
