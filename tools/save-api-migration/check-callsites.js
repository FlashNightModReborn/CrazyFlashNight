#!/usr/bin/env node
/*
 * check-callsites.js — SaveManager API 分层 R1 Slice 0 调用点回归门
 *
 * 依据 tmp/adjudication-savemanager-api-20260904/gptpro.txt §3.2 Slice 0 / §5.5：
 *   - scripts/ 层 17 strict 逻辑点（A1-A6 + B1-B5 + C1-C6 中的 scripts 部分 = 11 物理点）、
 *     15 debounce 逻辑点中的 scripts 部分（D1/D2 = 2 物理点）数量精确；
 *   - XFL 10 strict 物理点、13 debounce 物理点数量精确；
 *   - 3 处悬空 _root.存档系统.markDirty() 与 2 处 XFL _root.保存购物车()（C6 关联、不纳入四层）基线锁定；
 *   - 全部数量断言为 ==（精确），任何漂移非零退出；
 *   - 扫描命中集合与 callsites.v1.json 记录集合一一对应（双向差集为空）。
 *
 * 用法：node tools/save-api-migration/check-callsites.js [--verify-swf-hashes] [--json]
 *   --verify-swf-hashes  额外校验 baseline.swf 中登记的 SHA-256 与当前文件一致
 *                        （默认不校验：hash 是 Slice 0 快照证据，asLoader/UI SWF 会被其他
 *                         切片正常重发布，不作为每次必过的不变量）
 *   --json               以 JSON 输出汇总（供机器消费）
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..', '..');
const MANIFEST_PATH = path.join(__dirname, 'callsites.v1.json');

const STRICT_APIS = ['flushDurableNow', 'flushBeforeTransition'];
const REQUEST_APIS = ['requestSave', 'markDirty+requestSave'];

// pattern 家族：扫描、计数与 manifest 比对的统一口径
const FAMILIES = {
  forceSave:        { re: /_root\.强制存盘\s*\(/,  layers: ['scripts', 'xfl'] },
  autoSave:         { re: /_root\.自动存盘\s*\(/,  layers: ['scripts', 'xfl'] },
  localSave:        { re: /_root\.本地存盘\s*\(/,  layers: ['scripts', 'xfl'] },
  directFlushNow:   { re: /flushNow\s*\(/,          layers: ['scripts'] },
  danglingMarkDirty:{ re: /存档系统\.markDirty\s*\(/, layers: ['scripts'] },
  saveShopCart:     { re: /_root\.保存购物车\s*\(/,  layers: ['xfl'] }
};

// directFlushNow 的定义宿主与 shim 委托文件（不是调用点）
const FLUSHNOW_DEF_HOSTS = new Set([
  'scripts/类定义/org/flashNight/neur/Server/SaveManager.as',
  'scripts/通信/通信_lsy_原版存档系统.as'
]);

const errors = [];
const warnings = [];

function fail(msg) { errors.push(msg); }
function rel(p) { return path.relative(ROOT, p).split(path.sep).join('/'); }

// ---------- 文件枚举 ----------
function walk(dir, out) {
  out = out || [];
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

function scriptsProductionAsFiles() {
  return walk(path.join(ROOT, 'scripts'))
    .filter(f => f.endsWith('.as'))
    .map(rel)
    .filter(norm => {
      if (/(^|\/)tests?\//.test(norm)) return false;      // 测试目录
      if (/Tests?\.as$/.test(norm)) return false;          // *Test.as / *Tests.as
      if (/(^|\/)TestLoader\.as$/.test(norm)) return false; // gitignored scratch runner
      return true;
    });
}

function xflXmlFiles() {
  const mains = walk(path.join(ROOT, 'CRAZYFLASHER7MercenaryEmpire'))
    .filter(f => f.endsWith('.xml')).map(rel);
  const lives = walk(path.join(ROOT, 'flashswf', 'UI'))
    .filter(f => f.endsWith('.xml')).map(rel);
  return { mains, lives, all: mains.concat(lives) };
}

// ---------- 去注释（逐文件状态机） ----------
// 口径：AS 块注释 /* */ 与行注释 //；XML 额外处理 <!-- -->。
// 不处理字符串字面量内的 // 或 /*：当前目标 pattern 命中区域无此形态；
// 若未来引入会产生多计（安全方向，报警后人工复核并更新本口径）。
function effectiveCodeLines(text, isXml) {
  const result = new Map(); // lineNo -> 去注释后的行文本
  let inBlock = false;      // /* */
  let inXmlComment = false; // <!-- -->
  const lines = text.split(/\r\n|\r|\n/);
  for (let i = 0; i < lines.length; i++) {
    const src = lines[i];
    let out = '';
    let j = 0;
    while (j < src.length) {
      if (inBlock) {
        const end = src.indexOf('*/', j);
        if (end === -1) { j = src.length; break; }
        inBlock = false; j = end + 2;
      } else if (inXmlComment) {
        const end = src.indexOf('-->', j);
        if (end === -1) { j = src.length; break; }
        inXmlComment = false; j = end + 3;
      } else if (src.startsWith('/*', j)) {
        inBlock = true; j += 2;
      } else if (isXml && src.startsWith('<!--', j)) {
        inXmlComment = true; j += 4;
      } else if (src.startsWith('//', j)) {
        break; // 行注释：丢弃本行剩余
      } else {
        out += src[j]; j++;
      }
    }
    if (out.trim().length > 0) result.set(i + 1, out);
  }
  return result;
}

// ---------- 扫描 ----------
function scanFiles(files, isXml) {
  // 返回 { familyName: [{file, line, snippet}] }
  const hits = {};
  for (const name of Object.keys(FAMILIES)) hits[name] = [];
  for (const norm of files) {
    const abs = path.join(ROOT, norm);
    let text;
    try { text = fs.readFileSync(abs, 'utf8'); }
    catch (e) { fail('无法读取文件: ' + norm + ' (' + e.message + ')'); continue; }
    const codeLines = effectiveCodeLines(text, isXml);
    for (const [lineNo, code] of codeLines) {
      for (const [name, fam] of Object.entries(FAMILIES)) {
        if (name === 'directFlushNow' && FLUSHNOW_DEF_HOSTS.has(norm)) continue;
        if (fam.re.test(code)) {
          hits[name].push({ file: norm, line: lineNo, snippet: code.trim().slice(0, 120) });
        }
      }
    }
  }
  return hits;
}

function keyOf(h) { return h.file + ':' + h.line; }

// 双向集合比对：扫描命中 vs manifest 记录
function assertSetEqual(label, scanHits, manifestKeys) {
  const scanSet = new Set(scanHits.map(keyOf));
  const manSet = new Set(manifestKeys);
  for (const k of scanSet) {
    if (!manSet.has(k)) fail(label + '：扫描命中 ' + k + ' 不在 manifest 中（新增调用点未登记）');
  }
  for (const k of manSet) {
    if (!scanSet.has(k)) fail(label + '：manifest 记录 ' + k + ' 在源码中未命中（已删除或行号漂移）');
  }
  return scanSet.size;
}

function assertEq(label, actual, expected) {
  if (actual !== expected) {
    fail(label + '：实际 ' + actual + ' != 期望 ' + expected + '（精确数量断言失败）');
  }
  return actual;
}

// ---------- 主流程 ----------
function main() {
  const argv = process.argv.slice(2);
  const verifySwfHashes = argv.includes('--verify-swf-hashes');
  const jsonOut = argv.includes('--json');

  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  const counts = manifest.counts;
  const callsites = manifest.callsites;

  // 1) manifest 结构校验
  const REQUIRED = ['callsiteId', 'physicalId', 'layer', 'sourcePath', 'line', 'legacyEntry',
    'legacyApi', 'targetApi', 'reasonId', 'returnConsumed', 'duplicateGroup', 'pairRole',
    'liveState', 'expectedSwf'];
  const LAYERS = new Set(['scripts', 'xfl-main', 'xfl-live']);
  const PAIR_ROLES = new Set(['sole', 'live', 'mainCopy']);
  const LIVE_STATES = new Set(['live', 'unproven', 'suspect_legacy', 'dead']);
  for (const cs of callsites) {
    for (const f of REQUIRED) {
      if (!(f in cs)) fail('manifest 记录 ' + (cs.physicalId || '?') + ' 缺字段 ' + f);
    }
    if (!LAYERS.has(cs.layer)) fail(cs.physicalId + '：layer 非法 ' + cs.layer);
    if (!PAIR_ROLES.has(cs.pairRole)) fail(cs.physicalId + '：pairRole 非法 ' + cs.pairRole);
    if (!LIVE_STATES.has(cs.liveState)) fail(cs.physicalId + '：liveState 非法 ' + cs.liveState);
    if (!FAMILIES[cs.legacyEntry]) fail(cs.physicalId + '：legacyEntry 未知 ' + cs.legacyEntry);
    if (!Array.isArray(cs.reasonId) || cs.reasonId.length === 0) {
      fail(cs.physicalId + '：reasonId 必须为非空数组');
    }
    if (typeof cs.line !== 'number' || cs.line < 1) fail(cs.physicalId + '：line 非法');
  }
  const idSet = new Set();
  for (const cs of callsites) {
    if (idSet.has(cs.physicalId)) fail('manifest physicalId 重复: ' + cs.physicalId);
    idSet.add(cs.physicalId);
  }

  // 2) 全库独立扫描
  const scriptsFiles = scriptsProductionAsFiles();
  const xfl = xflXmlFiles();
  const scriptsHits = scanFiles(scriptsFiles.map(f => f), false);
  const xflHits = scanFiles(xfl.all, true);

  // 3) 精确数量断言（==，非 <=）
  assertEq('scripts/ 生产 _root.强制存盘() 物理点', scriptsHits.forceSave.length, counts.scriptsForceSavePhysical);
  assertEq('scripts/ 生产 flushNow() 直调物理点（B 组）', scriptsHits.directFlushNow.length, counts.scriptsDirectFlushNowPhysical);
  assertEq('scripts/ 生产 _root.自动存盘() 物理点', scriptsHits.autoSave.length, counts.scriptsDebouncePhysical);
  assertEq('scripts/ 生产 _root.本地存盘() 物理点', scriptsHits.localSave.length, counts.scriptsLocalSavePhysical);
  assertEq('scripts/ 生产悬空 _root.存档系统.markDirty() 物理点', scriptsHits.danglingMarkDirty.length, counts.danglingMarkDirtyPhysical);
  assertEq('XFL _root.强制存盘() 物理点', xflHits.forceSave.length, counts.xflStrictPhysical);
  assertEq('XFL _root.自动存盘() 物理点', xflHits.autoSave.length, counts.xflDebouncePhysical);
  assertEq('XFL _root.本地存盘() 物理点', xflHits.localSave.length, counts.xflLocalSavePhysical);
  assertEq('XFL _root.保存购物车() 物理点（C6 关联，不纳入四层）', xflHits.saveShopCart.length, counts.xflSaveShopCartPhysical);

  // 4) manifest 逐条定位校验：sourcePath 存在、line 行有效代码含对应 family pattern
  const fileCache = new Map();
  function codeLinesOf(norm, isXml) {
    const ck = norm + (isXml ? '|xml' : '|as');
    if (!fileCache.has(ck)) {
      if (!fs.existsSync(path.join(ROOT, norm))) { fileCache.set(ck, null); }
      else fileCache.set(ck, effectiveCodeLines(fs.readFileSync(path.join(ROOT, norm), 'utf8'), isXml));
    }
    return fileCache.get(ck);
  }
  for (const cs of callsites) {
    const isXml = cs.layer !== 'scripts';
    const cl = codeLinesOf(cs.sourcePath, isXml);
    if (!cl) { fail(cs.physicalId + '：sourcePath 不存在 ' + cs.sourcePath); continue; }
    const line = cl.get(cs.line);
    if (!line) {
      fail(cs.physicalId + '：' + cs.sourcePath + ':' + cs.line + ' 无有效代码（空行/注释/行号漂移）');
      continue;
    }
    const fam = FAMILIES[cs.legacyEntry];
    if (!fam.re.test(line)) {
      fail(cs.physicalId + '：' + cs.sourcePath + ':' + cs.line + ' 不含 ' + cs.legacyApi +
        '（family=' + cs.legacyEntry + '），实际内容: ' + line.trim().slice(0, 120));
    }
    const expectSwfLayer = cs.layer === 'scripts' ? 'scripts'
      : (cs.sourcePath.startsWith('flashswf/UI/') ? 'xfl-live' : 'xfl-main');
    if (expectSwfLayer !== cs.layer) {
      fail(cs.physicalId + '：layer ' + cs.layer + ' 与 sourcePath 归属 ' + expectSwfLayer + ' 不一致');
    }
  }

  // 5) 扫描命中集合 == manifest 记录集合（一一对应）
  const manKeys = (layerPred, entry) =>
    callsites.filter(cs => layerPred(cs) && cs.legacyEntry === entry)
      .map(cs => cs.sourcePath + ':' + cs.line);
  const isScripts = cs => cs.layer === 'scripts';
  const isXfl = cs => cs.layer !== 'scripts';

  assertSetEqual('scripts forceSave', scriptsHits.forceSave, manKeys(isScripts, 'forceSave'));
  assertSetEqual('scripts directFlushNow', scriptsHits.directFlushNow, manKeys(isScripts, 'directFlushNow'));
  assertSetEqual('scripts autoSave', scriptsHits.autoSave, manKeys(isScripts, 'autoSave'));
  assertSetEqual('scripts localSave', scriptsHits.localSave, manKeys(isScripts, 'localSave'));
  assertSetEqual('xfl forceSave', xflHits.forceSave, manKeys(isXfl, 'forceSave'));
  assertSetEqual('xfl autoSave', xflHits.autoSave, manKeys(isXfl, 'autoSave'));
  assertSetEqual('xfl localSave', xflHits.localSave, manKeys(isXfl, 'localSave'));
  const danglingKeys = (manifest.danglingMarkDirty || []).map(d => d.sourcePath + ':' + d.line);
  assertSetEqual('scripts danglingMarkDirty', scriptsHits.danglingMarkDirty, danglingKeys);
  const shopCartKeys = (manifest.outOfScope && manifest.outOfScope.xflSaveShopCart || [])
    .map(d => d.sourcePath + ':' + d.line);
  assertSetEqual('xfl saveShopCart', xflHits.saveShopCart, shopCartKeys);

  // 6) 逻辑计数断言（17 strict / 15 debounce，按 callsiteId 去重）
  const logicalById = new Map();
  for (const cs of callsites) {
    if (!logicalById.has(cs.callsiteId)) logicalById.set(cs.callsiteId, cs);
  }
  const strictLogical = [...logicalById.values()].filter(cs => STRICT_APIS.includes(cs.targetApi));
  const requestLogical = [...logicalById.values()].filter(cs => REQUEST_APIS.includes(cs.targetApi));
  assertEq('strict 逻辑调用点（A/B/C 组）', strictLogical.length, counts.strictLogicalTotal);
  assertEq('debounce 逻辑调用点（D/E 组）', requestLogical.length, counts.debounceLogicalTotal);
  assertEq('manifest scripts strict 物理记录',
    callsites.filter(cs => isScripts(cs) && STRICT_APIS.includes(cs.targetApi)).length,
    counts.scriptsStrictPhysical);
  assertEq('manifest scripts debounce 物理记录',
    callsites.filter(cs => isScripts(cs) && REQUEST_APIS.includes(cs.targetApi)).length,
    counts.scriptsDebouncePhysical);
  assertEq('manifest XFL strict 物理记录',
    callsites.filter(cs => isXfl(cs) && STRICT_APIS.includes(cs.targetApi)).length,
    counts.xflStrictPhysical);
  assertEq('manifest XFL debounce 物理记录',
    callsites.filter(cs => isXfl(cs) && REQUEST_APIS.includes(cs.targetApi)).length,
    counts.xflDebouncePhysical);

  // 7) paired parity 断言（裁决 §5.5：C1/C2/C3/C5 主 XFL 与 live 副本必须同 API/reason）
  const groups = new Map();
  for (const cs of callsites) {
    if (cs.duplicateGroup) {
      if (!groups.has(cs.duplicateGroup)) groups.set(cs.duplicateGroup, []);
      groups.get(cs.duplicateGroup).push(cs);
    }
  }
  for (const cs of callsites) {
    if (!cs.duplicateGroup && cs.pairRole !== 'sole') {
      fail(cs.physicalId + '：无 duplicateGroup 但 pairRole=' + cs.pairRole);
    }
  }
  for (const [gid, members] of groups) {
    if (members.length !== 2) {
      fail('duplicateGroup ' + gid + '：成员数 ' + members.length + ' != 2');
      continue;
    }
    const roles = members.map(m => m.pairRole).sort().join(',');
    if (roles !== 'live,mainCopy') {
      fail('duplicateGroup ' + gid + '：pairRole 组合异常 ' + roles);
    }
    const [a, b] = members;
    if (a.targetApi !== b.targetApi) {
      fail('duplicateGroup ' + gid + '：targetApi 不一致 ' + a.targetApi + ' vs ' + b.targetApi);
    }
    if (JSON.stringify(a.reasonId) !== JSON.stringify(b.reasonId)) {
      fail('duplicateGroup ' + gid + '：reasonId 不一致 ' +
        JSON.stringify(a.reasonId) + ' vs ' + JSON.stringify(b.reasonId));
    }
    if (a.expectedSwf === b.expectedSwf) {
      fail('duplicateGroup ' + gid + '：paired 副本 expectedSwf 不应相同 ' + a.expectedSwf);
    }
  }

  // 8) 可选：SWF hash 校验
  if (verifySwfHashes) {
    for (const [swf, info] of Object.entries(manifest.baseline.swf)) {
      const abs = path.join(ROOT, swf);
      if (!fs.existsSync(abs)) { fail('baseline SWF 缺失: ' + swf); continue; }
      const sha = crypto.createHash('sha256').update(fs.readFileSync(abs)).digest('hex');
      if (sha !== info.sha256) {
        fail('SWF hash 漂移: ' + swf + ' 当前 ' + sha + ' != 基线 ' + info.sha256 +
          '（重发布后请同步 manifest baseline）');
      }
    }
  }

  // 9) 汇总输出
  const summary = [];
  for (const [cid, cs] of logicalById) {
    const physical = callsites.filter(x => x.callsiteId === cid);
    summary.push({
      callsiteId: cid,
      targetApi: cs.targetApi,
      reasonId: cs.reasonId,
      returnConsumed: cs.returnConsumed,
      liveState: physical.map(p => p.pairRole === 'sole' ? p.liveState : p.pairRole + ':' + p.liveState),
      physicalPoints: physical.map(p => p.sourcePath + ':' + p.line),
      expectedSwf: physical.map(p => p.expectedSwf),
      migrateSlice: cs.migrateSlice,
      dirtyGuard: cs.dirtyGuard
    });
  }

  if (jsonOut) {
    console.log(JSON.stringify({
      ok: errors.length === 0,
      scanned: { scriptsProductionFiles: scriptsFiles.length, xflXmlFiles: xfl.all.length },
      counts: {
        scriptsForceSave: scriptsHits.forceSave.length,
        scriptsDirectFlushNow: scriptsHits.directFlushNow.length,
        scriptsAutoSave: scriptsHits.autoSave.length,
        scriptsLocalSave: scriptsHits.localSave.length,
        scriptsDanglingMarkDirty: scriptsHits.danglingMarkDirty.length,
        xflForceSave: xflHits.forceSave.length,
        xflAutoSave: xflHits.autoSave.length,
        xflLocalSave: xflHits.localSave.length,
        xflSaveShopCart: xflHits.saveShopCart.length,
        strictLogical: strictLogical.length,
        debounceLogical: requestLogical.length
      },
      callsites: summary,
      errors, warnings
    }, null, 2));
  } else {
    console.log('=== SaveManager API 分层 R1 / Slice 0 调用点回归门 ===');
    console.log('扫描面：scripts 生产 .as ' + scriptsFiles.length + ' 个；XFL XML ' + xfl.all.length +
      ' 个（主 XFL ' + xfl.mains.length + ' + flashswf/UI ' + xfl.lives.length + '）');
    console.log('');
    console.log('物理点计数（精确断言）：');
    console.log('  scripts/ _root.强制存盘()      = ' + scriptsHits.forceSave.length + '（期望 ' + counts.scriptsForceSavePhysical + '）');
    console.log('  scripts/ flushNow() 直调(B组)  = ' + scriptsHits.directFlushNow.length + '（期望 ' + counts.scriptsDirectFlushNowPhysical + '）');
    console.log('  scripts/ _root.自动存盘()      = ' + scriptsHits.autoSave.length + '（期望 ' + counts.scriptsDebouncePhysical + '）');
    console.log('  scripts/ _root.本地存盘()      = ' + scriptsHits.localSave.length + '（期望 ' + counts.scriptsLocalSavePhysical + '）');
    console.log('  scripts/ 悬空 存档系统.markDirty() = ' + scriptsHits.danglingMarkDirty.length + '（期望 ' + counts.danglingMarkDirtyPhysical + '）');
    console.log('  XFL      _root.强制存盘()      = ' + xflHits.forceSave.length + '（期望 ' + counts.xflStrictPhysical + '）');
    console.log('  XFL      _root.自动存盘()      = ' + xflHits.autoSave.length + '（期望 ' + counts.xflDebouncePhysical + '）');
    console.log('  XFL      _root.本地存盘()      = ' + xflHits.localSave.length + '（期望 ' + counts.xflLocalSavePhysical + '）');
    console.log('  XFL      _root.保存购物车()    = ' + xflHits.saveShopCart.length + '（期望 ' + counts.xflSaveShopCartPhysical + '，C6 关联不纳入四层）');
    console.log('逻辑点：strict ' + strictLogical.length + '/' + counts.strictLogicalTotal +
      '，debounce ' + requestLogical.length + '/' + counts.debounceLogicalTotal);
    console.log('');
    console.log('逐调用点 targetApi / reasonId 汇总（供审阅）：');
    for (const s of summary) {
      const reasons = s.reasonId.join(', ');
      const live = s.liveState.join(' | ');
      console.log('  ' + s.callsiteId.padEnd(4) +
        ('slice' + s.migrateSlice).padEnd(7) +
        s.targetApi.padEnd(22) +
        ('ret:' + (s.returnConsumed ? 'yes' : 'no')).padEnd(8) +
        (s.dirtyGuard ? 'guarded  ' : '         ') +
        live.padEnd(46) + reasons);
      for (let i = 0; i < s.physicalPoints.length; i++) {
        console.log('      ' + s.physicalPoints[i] + '  ->  ' + s.expectedSwf[i]);
      }
    }
    console.log('');
    for (const w of warnings) console.log('WARN: ' + w);
    if (errors.length > 0) {
      console.log('FAIL（' + errors.length + ' 项漂移/不一致）：');
      for (const e of errors) console.log('  ✗ ' + e);
    } else {
      console.log('SAVE-API-CALLSITES PASS：' + callsites.length + ' 物理点 / ' +
        logicalById.size + ' 逻辑点全部与 manifest 一一对应，数量断言全过。');
    }
  }

  process.exit(errors.length === 0 ? 0 : 1);
}

main();
