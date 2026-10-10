/** A兵团武器库·蓝图素材烘焙
 *  输入：data/crafting/{武器合成,饰品合成,进阶防具,基础防具}.json 的产物图标名
 *        data/items/asset_source_map.xml（图标-<名> → swf + symbolName）
 *  流程：按 swf 分组 → ffdec 导 symbolClass CSV 取 characterId → -selectid 导 sprite:svg
 *        首帧 SVG 后处理成白线稿（去填充/去滤镜/统一描边）→ launcher/web/assets/armory-blueprints/
 *  产出：blueprints/*.svg + manifest.json（图标名 → 文件名）
 *  用法：node tools/bake-armory-blueprints.js [--dry-run]
 *  方案与踩坑：docs/武器库蓝图描线-Flash素材烘焙与引用解析方案-2026-10-10.md
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const FFDEC = path.join(ROOT, 'tools', 'ffdec', 'ffdec-cli.exe');
const ASSET_MAP = path.join(ROOT, 'data', 'items', 'asset_source_map.xml');
const OUT_DIR = path.join(ROOT, 'launcher', 'web', 'assets', 'armory-blueprints');
const TMP = path.join(ROOT, 'tmp', 'armory-bp-bake');
const CATEGORIES = ['武器合成', '饰品合成', '进阶防具', '基础防具'];
// 辅助元件名黑名单：判定/参考/测试/特效等不是产品本体
const AUX_NAME = /^(判定|参考|测试|特效|代码|辅助|阴影|背景|占位|mask|.*位置)/i;

// ── 单品校正表：图标名 → 出图方式 ──
//   skip:true    不出蓝图（素材只有位图/无合适矢量/不需要展示）
//   source:{sprite:'linkage'}  强制本体元件（图标与真身命名对不上时）
//   parts:[...]  显式拼合源；元素 {sprite:'linkage'} 或 {shape:<characterId>}
//   mode         'stack'  每件各自横置后上下排（双持/入鞘=本体+鞘）
//   dropCids     源 sprite 首帧里要剔除的 use characterId（底衬/标记层）
const BP_TUNE = {
  '诛神短剑': { skip: true }, '诛神短枪': { skip: true },
  '远古诛神短剑': { skip: true }, '远古诛神短枪': { skip: true },
  'Andy套装碎片': { skip: true },
  '大圣头甲': { skip: true }, '大圣手甲': { skip: true },
  '大圣腿甲': { skip: true }, '大圣鞋': { skip: true }, '大圣胸甲': { skip: true },
  // 产物名与真身字母序不一致（图标 SAPS12 ↔ 枪 SPAS12）
  'SAPS12': { source: { sprite: '枪-手枪-SPAS12' } },
  // 入鞘刀：裸刀身(shape66 是 刀-虎彻配鞘版 内部的无名刀身 shape) + 刀鞘
  '虎彻配鞘版': { mode: 'stack', parts: [{ shape: 66 }, { sprite: '刀-虎彻的鞘' }] },
  '血刀配鞘版': { mode: 'stack', parts: [{ sprite: '刀-血刀加长版' }, { sprite: '刀-血刀刀鞘' }] },
  // 般若半覆面：cid 3 是脸底衬块，剔除后只留面具
  '般若影鬼半覆面': { dropCids: [3] },
  '般若赤鬼半覆面': { dropCids: [3] },
};
const IDENTITY_M = { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 };
const BP_XMLNS = 'xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"';
// 变装部件槽位后缀：只含身体部位（剥掉后得套件基名/件名）。
// 注意盔/头套/面具/鞋/战鞋/耳坠等不在此列——它们本身就是独立单件名。
const DRESSUP_POS = /(左上臂|右上臂|左下臂|右下臂|左大腿|右大腿|左小腿|右小腿|下臂|上臂|身体|屁股|大腿|小腿|左手|右手)$/;
// 部位后缀 → 槽位。chest=躯干+袖管（甲/胸甲/上装/背心/劲装），legs=下装件，
// hands=成对手部件；不带部位后缀的是 standalone 单件，不参与扩张。
const DRESSUP_SLOTS = [
  [/^(身体|上臂|左上臂|右上臂|下臂|左下臂|右下臂)$/, 'chest'],
  [/^(屁股|左大腿|右大腿|左小腿|右小腿|大腿|小腿)$/, 'legs'],
  [/^(左手|右手)$/, 'hands'],
];
function dressupBase(name) { return name.replace(DRESSUP_POS, ''); }
function dressupSlot(name) {
  const m = DRESSUP_POS.exec(name);
  if (!m) return 'standalone';
  for (const [re, cls] of DRESSUP_SLOTS) if (re.test(m[1])) return cls;
  return 'standalone';
}
const DRY = process.argv.includes('--dry-run');
const REUSE = process.argv.includes('--reuse');

// ── 0. 物品名 → 运行时图标名：UI 按 output.icon 找蓝图文件，
//    必须与物品 XML 的 <icon> 字段一致（韦森686改装版 → 图标「韦森686」）。
const iconByName = {};
const itemsDir = path.join(ROOT, 'data', 'items');
for (const f of fs.readdirSync(itemsDir)) {
  if (!/\.xml$/i.test(f)) continue;
  const c = fs.readFileSync(path.join(itemsDir, f), 'utf8');
  for (const m of c.matchAll(/<name>([^<]+)<\/name>[\s\S]{0,600}?<icon>([^<]*)<\/icon>/g)) {
    const nm = m[1].trim(), ic = m[2].trim();
    if (nm && ic) iconByName[nm] = ic;
  }
}

// ── 1. 收集产物图标名 ──
// 饰品类（项链/军牌/耳坠/手镯）按设计不出蓝图：armory 面板对
// 「饰品合成」类目不挂线稿层，这里直接不生成。
const iconNames = new Set(); // 这里存「运行时图标名」= 文件名
const recipeOf = {};         // iconName -> recipe name（审计用）
for (const cat of CATEGORIES) {
  if (cat === '饰品合成') continue;
  const file = path.join(ROOT, 'data', 'crafting', cat + '.json');
  const recipes = JSON.parse(fs.readFileSync(file, 'utf8'));
  const list = Array.isArray(recipes) ? recipes : Object.values(recipes);
  for (const r of list) {
    if (!r || !r.name) continue;
    const icon = iconByName[r.name] || r.name;
    iconNames.add(icon);
    recipeOf[icon] = r.name;
  }
}
console.log('product icon names:', iconNames.size);

// ── 2. 解析 asset_source_map ──
const mapXml = fs.readFileSync(ASSET_MAP, 'utf8');
const unesc = s => s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&apos;/g, "'");
const assetById = {}; // linkageId -> {swf, symbolName}
// 属性按名提取：symbolName 可缺省、属性顺序不限
for (const m of mapXml.matchAll(/<asset\s+([^>]+?)\/?\s*>/g)) {
  const attrs = m[1];
  const get = k => { const mm = new RegExp(k + '="([^"]*)"').exec(attrs); return mm ? unesc(mm[1]) : ''; };
  const id = get('id'), swf = get('swf');
  if (id && swf && !assetById[id]) assetById[id] = { swf, symbolName: get('symbolName') };
}
// conflict 节点里的重复 id 也补进来（取第一个 source）
for (const m of mapXml.matchAll(/<conflict\s+id="([^"]+)"[^>]*>([\s\S]*?)<\/conflict>/g)) {
  const cid = unesc(m[1]);
  if (assetById[cid]) continue;
  const src = m[2].match(/<source\s+swf="([^"]+)"/);
  if (src) assetById[cid] = { swf: unesc(src[1]), symbolName: '' };
}

const jobs = []; // {iconName, linkageId, swf, characterId?}
const missing = [];
for (const name of iconNames) {
  const linkage = '图标-' + name;
  const a = assetById[linkage];
  if (!a) { missing.push(name); continue; }
  jobs.push({ iconName: name, linkageId: linkage, swf: a.swf });
}
console.log('resolved:', jobs.length, 'missing:', missing.length, missing.slice(0, 10).join(','));

// ── 3. 按 swf 分组，导 symbolClass ──
fs.mkdirSync(TMP, { recursive: true });
// 旧版工作目录按跑序命名（swf0..N），换批次元件顺序一变整个缓存就串到别的 swf，
// 产物会张冠李戴（黑铁劲装出大圣手甲）。一律清掉，改用 swf 路径+体积的稳定命名。
for (const d of fs.readdirSync(TMP)) {
  if (/^swf\d+$/.test(d)) fs.rmSync(path.join(TMP, d), { recursive: true, force: true });
}
const bySwf = new Map();
for (const j of jobs) {
  if (!bySwf.has(j.swf)) bySwf.set(j.swf, []);
  bySwf.get(j.swf).push(j);
}
const workDirBySwf = new Map();
const scannedNameById = new Map(); // swfRel -> nameById
function scanSwf(swfRel) {
  const srcAbs = path.join(ROOT, swfRel);
  if (!fs.existsSync(srcAbs)) return null;
  // symbolClass 结果按 swf 路径+体积缓存，补扫几十个 swf 时重跑不再重复导出
  const cacheDir = path.join(TMP, 'scache');
  fs.mkdirSync(cacheDir, { recursive: true });
  const cacheKey = swfRel.replace(/[^\w.-]/g, '_') + '.' + fs.statSync(srcAbs).size;
  const cacheFile = path.join(cacheDir, cacheKey + '.csv');
  // 工作目录与 scache 同名绑定 swf+体积：目录名恒定，缓存不会串
  const work = path.join(TMP, 'wk_' + cacheKey);
  workDirBySwf.set(swfRel, work);
  fs.mkdirSync(work, { recursive: true });
  const local = path.join(work, 'src.swf');
  fs.copyFileSync(srcAbs, local); // 避开中文路径问题
  let csv = null;
  if (fs.existsSync(cacheFile)) {
    csv = fs.readFileSync(cacheFile, 'utf8');
  } else {
    const scDir = path.join(work, 'sc');
    try {
      execFileSync(FFDEC, ['-export', 'symbolClass', scDir, local],
        { stdio: ['ignore', 'pipe', 'pipe'], timeout: 300000 });
    } catch (e) {
      console.log('symbolClass FAILED', swfRel, String(e).slice(0, 200));
      return null;
    }
    if (!fs.existsSync(scDir)) return null;
    const csvFile = fs.readdirSync(scDir).find(f => f.endsWith('.csv'));
    if (!csvFile) return null;
    csv = fs.readFileSync(path.join(scDir, csvFile), 'utf8');
    try { fs.writeFileSync(cacheFile, csv, 'utf8'); } catch (e) { /* 缓存失败不阻塞 */ }
  }
  const idByName = {};
  const nameById = {};
  for (const line of csv.split(/\r?\n/)) {
    const idx = line.indexOf(';');
    if (idx > 0) {
      const id = Number(line.slice(0, idx));
      const nm = line.slice(idx + 1).trim();
      idByName[nm] = id;
      nameById[id] = nm;
    }
  }
  scannedNameById.set(swfRel, { idByName, nameById });
  return { work, local, idByName, nameById };
}
for (const [swfRel, group] of bySwf) {
  const sc = scanSwf(swfRel);
  if (!sc) { group.forEach(j => j.error = 'swf scan failed: ' + swfRel); continue; }
  for (const j of group) j.characterId = sc.idByName[j.linkageId];
  group.filter(j => !j.characterId).forEach(j => j.error = 'linkage not in symbolClass');
  group.nameById = sc.nameById;
  group.maps = sc;
}

// ── 3.5 缺失图标回退：asset map 没登记 图标-<名> 的产物，
// 在已扫描 symbolClass 里找近似 linkage，找不到再补扫 things* 系列 swf ──
function fuzzyFindIcon(name) {
  const cands = [];
  const nameL = name.toLowerCase();
  const bigrams = s => {
    const g = new Set();
    for (let i = 0; i + 2 <= s.length; i++) g.add(s.slice(i, i + 2));
    return g;
  };
  const nameBg = bigrams(nameL);
  const consider = (swfRel, nm, id) => {
    if (!nm || AUX_NAME.test(nm)) return;
    const nmL = nm.toLowerCase();
    if (!nm.startsWith('图标-')) {
      // 本体 linkage 直接命中产物名（男变装-大圣上装身体 → 大圣上装）
      if (nmL.includes(nameL)) cands.push({ swfRel, id, linkage: nm, score: 60 + name.length / nm.length });
      return;
    }
    const rest = nm.slice(3), restL = nmL.slice(3);
    if (restL === nameL) cands.push({ swfRel, id, linkage: nm, score: 100 });
    else if (rest.length >= 2 && (nameL.includes(restL) || restL.includes(nameL))) {
      cands.push({ swfRel, id, linkage: nm, score: 80 + Math.min(rest.length, name.length) });
    } else {
      // 双字组重叠：黄金骑士牙狼头盔 ↔ 图标-牙狼铠头盔（共「牙狼」「头盔」）
      let shared = 0;
      for (const g of bigrams(restL)) if (nameBg.has(g)) shared++;
      if (shared >= 2) cands.push({ swfRel, id, linkage: nm, score: 40 + shared });
    }
  };
  const pools = [...scannedNameById.entries()];
  for (const [swfRel, maps] of pools) {
    for (const [id, nm] of Object.entries(maps.nameById)) consider(swfRel, nm, Number(id));
  }
  cands.sort((a, b) => b.score - a.score);
  return cands[0] || null;
}

// 候选补充 swf：things* 物品库家族 + arts/new/ 全部（新装备图标多在新库里）
const EXTRA_SWFS = [];
for (const cand of fs.readdirSync(path.join(ROOT, 'flashswf', 'arts'))) {
  if (/^things\d*(-new)?\.swf$/i.test(cand) || /^素材库.*图标.*\.swf$/.test(cand)) {
    const rel = 'flashswf/arts/' + cand;
    if (!scannedNameById.has(rel) && fs.existsSync(path.join(ROOT, rel))) EXTRA_SWFS.push(rel);
  }
}
const newDir = path.join(ROOT, 'flashswf', 'arts', 'new');
if (fs.existsSync(newDir)) {
  for (const cand of fs.readdirSync(newDir)) {
    if (!/\.swf$/i.test(cand)) continue;
    const rel = 'flashswf/arts/new/' + cand;
    if (!scannedNameById.has(rel)) EXTRA_SWFS.push(rel);
  }
}
let lazyScanned = false;
for (const name of missing.slice()) {
  let hit = fuzzyFindIcon(name);
  if (!hit && !lazyScanned) {
    lazyScanned = true;
    for (const rel of EXTRA_SWFS) { scanSwf(rel); bySwf.set(rel, bySwf.get(rel) || []); }
    hit = fuzzyFindIcon(name);
  }
  if (!hit) continue;
  const swfRel = hit.swfRel;
  const maps = scannedNameById.get(swfRel);
  const job = { iconName: name, linkageId: hit.linkage, swf: swfRel,
    characterId: maps.idByName[hit.linkage], fallbackFrom: hit.linkage };
  if (!bySwf.has(swfRel)) bySwf.set(swfRel, []);
  bySwf.get(swfRel).push(job);
  if (!bySwf.get(swfRel).nameById) bySwf.get(swfRel).nameById = maps.nameById;
  if (!bySwf.get(swfRel).maps) bySwf.get(swfRel).maps = maps;
  missing.splice(missing.indexOf(name), 1);
}
if (missing.length) console.log('still missing after fuzzy:', missing.length, missing.join(','));
else console.log('fuzzy icon fallback resolved all missing');

// ── 4. 逐件导 sprite SVG（首帧）并后处理 ──
if (!DRY) fs.mkdirSync(OUT_DIR, { recursive: true });
const manifest = {};
const fail = [];
for (const [swfRel, group] of bySwf) {
  const work = workDirBySwf.get(swfRel);
  if (!work) continue;
  const local = path.join(work, 'src.swf');
  if (!fs.existsSync(local)) continue;
  const outDir = path.join(work, 'svg');
  for (const j of group) {
    if (!j.characterId) continue;
    const tune = BP_TUNE[j.iconName];
    if (tune && tune.skip) { j.skipped = true; continue; }
    const parts = [];
    if (tune && (tune.parts || tune.source)) {
      // 校正表显式指定的拼合源/本体
      for (const spec of tune.parts || [tune.source]) {
        const p = resolvePart(spec, group, outDir, local);
        if (p) parts.push(p);
        else console.log('  tune source missing:', j.iconName, JSON.stringify(spec));
      }
    }
    if (!parts.length) {
      const linkName = group.nameById && group.nameById[j.characterId];
      const raw = exportFirstFrameSvg(j.characterId, outDir, local, linkName);
      if (!raw) { j.error = 'icon svg missing'; fail.push(j.iconName); continue; }
      // 取件优先级：命名引用（刀-輪舞 等命名 sprite 是完整素材）→
      // symbolClass 按名找本体（图标拆段摆放时组装版 wrapper，如
      // 刀-异形女王毒刺）→ 图标实际显示件（clip 组内 use / 老式图标的
      // 非窗口非停放顶层 use，兜底无 linkage 名的产品）→ 裸图标。
      const refs = collectSourceRefs(raw.svg, group.nameById || {}, j.iconName);
      for (const r of refs.slice(0, 3)) {
        const inner = exportFirstFrameSvg(r.id, outDir, local, r.name);
        if (inner) parts.push({ svg: inner.svg, source: r.name, sourceId: r.id, count: r.count });
      }
      // 同名双持：同一 sprite 被摆放两次 → 补第二份上下排
      if (parts.length === 1 && parts[0].count >= 2) parts.push(parts[0]);
      if (!parts.length) {
        const byName = findSourceByName(group.nameById || {}, j.iconName);
        if (byName) {
          const inner = exportFirstFrameSvg(byName.id, outDir, local, byName.name);
          if (inner) parts.push({ svg: inner.svg, source: byName.name, sourceId: byName.id });
        }
      }
      if (!parts.length) {
        const seen = new Map(); // cid -> svg 缓存，同一元件多次摆放只导一次
        const exportByKind = (u) => {
          if (seen.has(u.cid)) return seen.get(u.cid);
          const r = u.kind === 'shape'
            ? exportShapeSvg(u.cid, outDir, local)
            : (exportFirstFrameSvg(u.cid, outDir, local,
                (group.nameById || {})[u.cid]) || {}).svg;
          seen.set(u.cid, r || null);
          return r;
        };
        for (const u of collectIconUses(raw.svg).slice(0, 8)) {
          const r = exportByKind(u);
          if (r) parts.push({ svg: r,
            source: (group.nameById || {})[u.cid] || (u.kind + '#' + u.cid),
            sourceId: u.cid });
        }
      }
      if (!parts.length) {
        parts.push({ svg: raw.svg, source: j.linkageId, sourceId: j.characterId });
      }
    }
    if (tune && tune.dropCids) {
      for (const p of parts) p.svg = dropUseCids(p.svg, tune.dropCids);
    }
    let mode = tune && tune.mode;
    const allDressup = parts.length && parts.every(p => /^[男女]变装-/.test(p.source || ''));
    // 变装件补齐同槽兄弟件（装备 = <dressup> 前缀整套部件）；多件横排
    // 爆炸图展示——部件各自是独立紧凑画布（尺寸互不相同），不存在共享
    // 骨架坐标系，不能原位叠加；横排空间利用率高。
    if (!mode && allDressup) expandDressup(parts, group, outDir, local);
    if (!mode) mode = parts.length > 1 && allDressup ? 'row' : 'stack';
    const svg = composeBlueprints(parts.map(p => p.svg), mode, allDressup);
    // 原图只有位图（image/pattern 被剥离后几乎无矢量路径）的不出蓝图
    if (renderedPathCount(svg) < 2) {
      j.noVector = true;
      continue;
    }
    const fileName = j.iconName + '.svg';
    if (!DRY) fs.writeFileSync(path.join(OUT_DIR, fileName), svg, 'utf8');
    manifest[j.iconName] = { file: fileName,
      sources: parts.map(p => p.source), sourceIds: parts.map(p => p.sourceId) };
  }
}

// 导出指定 characterId 的 sprite 首帧 SVG；返回 {svg, dir} 或 null。
// expectName：symbolClass 里该 id 的名字；缓存目录名对不上就是别的元件残留，删掉重导。
function exportFirstFrameSvg(characterId, outDir, local, expectName) {
  const prefix = new RegExp('^DefineSprite_' + characterId + '(_|$)');
  let dir = fs.existsSync(outDir)
    ? fs.readdirSync(outDir).find(d => prefix.test(d)) : undefined;
  if (dir && expectName && dir !== 'DefineSprite_' + characterId + '_' + expectName) {
    fs.rmSync(path.join(outDir, dir), { recursive: true, force: true });
    dir = undefined;
  }
  if (!dir) {
    // 缓存缺失时照常导出（--reuse 只跳过已有缓存的重复导出）
    // 逐 id 导出：长 selectid 列表/个别坏 id 会让 ffdec 静默整体跳过
    try {
      execFileSync(FFDEC,
        ['-selectid', String(characterId), '-format', 'sprite:svg',
         '-export', 'sprite', outDir, local],
        { stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000 });
    } catch (e) { return null; }
    dir = fs.existsSync(outDir)
      ? fs.readdirSync(outDir).find(d => prefix.test(d)) : undefined;
  }
  if (!dir) return null;
  const first = fs.readdirSync(path.join(outDir, dir)).filter(f => f.endsWith('.svg')).sort()[0];
  if (!first) return null;
  return { svg: fs.readFileSync(path.join(outDir, dir, first), 'utf8'), dir };
}

// 导出 shape 元件 SVG（无名部件用，如虎彻裸刀身 shape#66）：<outDir>/shape<id>.svg
function exportShapeSvg(characterId, outDir, local) {
  const file = path.join(outDir, 'shape' + characterId + '.svg');
  const produced = path.join(outDir, characterId + '.svg');
  if (!fs.existsSync(file)) {
    if (!fs.existsSync(produced)) {
      try {
        execFileSync(FFDEC,
          ['-selectid', String(characterId), '-format', 'shape:svg',
           '-export', 'shape', outDir, local],
          { stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000 });
      } catch (e) { return null; }
    }
    if (!fs.existsSync(produced)) return null;
    try { fs.renameSync(produced, file); } catch (e) { /* 已存在则直接用 */ }
  }
  const use = fs.existsSync(file) ? file : produced;
  return fs.existsSync(use) ? fs.readFileSync(use, 'utf8') : null;
}

// BP_TUNE.parts/source 元素 → {svg, source, sourceId}；在同 swf 的 symbolClass 里解析
function resolvePart(spec, group, outDir, local) {
  if (spec.shape != null) {
    const svg = exportShapeSvg(spec.shape, outDir, local);
    return svg ? { svg, source: 'shape#' + spec.shape, sourceId: spec.shape, count: 1 } : null;
  }
  const id = group.maps && group.maps.idByName[spec.sprite];
  if (!id) return null;
  const r = exportFirstFrameSvg(id, outDir, local, spec.sprite);
  return r ? { svg: r.svg, source: spec.sprite, sourceId: id, count: 1 } : null;
}

// 剔除指定 characterId 的 use（面具脸底衬等辅助层）
function dropUseCids(svg, cids) {
  for (const cid of cids)
    svg = svg.replace(new RegExp(`<use [^>]*ffdec:characterId="${cid}"[^>]*/>`, 'g'), '');
  return svg;
}

// 收集图标 sprite <use> 引用的命名原素材元件（含每个元件被摆放次数）：
// linkage 名包含图标名的排前（刀-异形女王毒刺 命中 异形女王毒刺），
// 排除 图标-/判定/参考/测试/特效/代码/阴影/背景 等非素材引用。
function collectSourceRefs(svg, nameById, iconName) {
  const counts = new Map();
  for (const m of svg.matchAll(/ffdec:characterId="(\d+)"[^>]*xlink:href="#(?:sprite|shape)\d+"/g)) {
    const id = Number(m[1]);
    counts.set(id, (counts.get(id) || 0) + 1);
  }
  const named = [], namedFirst = [];
  for (const [id, count] of counts) {
    const name = nameById[id];
    if (!name || name.startsWith('图标-') || AUX_NAME.test(name)) continue;
    (iconName && name.includes(iconName) ? namedFirst : named).push({ id, name, count });
  }
  return namedFirst.concat(named);
}

// 收集图标首帧里「实际被显示」的引用，作为命名引用找不到时的兜底取件。
// 新式图标结构：窗口底形 + clipPath + <g clip-path> 产品 use </g> ——
// clip 组内的每个 use 就是产品本体（sprite 或 shape，可能无 linkage 名）。
// 老式图标（项链/黑铁长裤等）没有 clip 组，顶层 use 里：
//   scale≈1 且摆在 (-12,-12) 的是共享窗口底形；
//   scale≈1 且平移量大的（|t|>20）是画板外停放的原始素材；
//   其余（缩放摆放的）才是产品。
function parseUseTag(t) {
  const cid = (/ffdec:characterId="(\d+)"/.exec(t) || [])[1];
  const href = (/xlink:href="#([^"]+)"/.exec(t) || [])[1] || '';
  const tr = (/transform="([^"]*)"/.exec(t) || [])[1] || '';
  const x = parseFloat((/\sx="(-?[\d.]+)"/.exec(t) || [])[1] || 0);
  const y = parseFloat((/\sy="(-?[\d.]+)"/.exec(t) || [])[1] || 0);
  return {
    cid: Number(cid),
    kind: /^shape/.test(href) ? 'shape' : 'sprite',
    transform: (tr + ((x || y) ? ` translate(${x} ${y})` : '')).trim(),
    matrix: tr,
  };
}
function collectIconUses(svg) {
  const topEnd = svg.indexOf('<defs>');
  const top = topEnd >= 0 ? svg.slice(0, topEnd) : svg;
  const gi = top.search(/<g clip-path=/);
  if (gi >= 0) {
    const seg = extractGroup(top, gi);
    if (seg) {
      return [...seg.matchAll(/<use [^>]*\/>/g)]
        .map(m => parseUseTag(m[0])).filter(u => u.cid);
    }
  }
  const out = [];
  let windowDropped = false;
  for (const m of top.matchAll(/<use [^>]*\/>/g)) {
    const u = parseUseTag(m[0]);
    if (!u.cid) continue;
    const mt = parseMatrix(u.matrix);
    const s = mt ? Math.max(Math.hypot(mt.a, mt.b), Math.hypot(mt.c, mt.d)) : 1;
    const tx = mt ? mt.tx : 0, ty = mt ? mt.ty : 0;
    // 窗口底形：scale≈1 且摆在 (-12,-12)。只丢第一个匹配——窗口总在产品之前，
    // 产品碰巧同位（军牌 shape1 也在 -12,-12）时不能误杀。
    if (!windowDropped && Math.abs(s - 1) < 0.05
        && Math.abs(tx + 12) < 1 && Math.abs(ty + 12) < 1) {
      windowDropped = true;
      continue;
    }
    if (Math.abs(s - 1) < 0.05 && (Math.abs(tx) > 20 || Math.abs(ty) > 20)) continue;       // 停放
    out.push(u);
  }
  return out;
}

// 变装碎片补全：以图标首个引用定目标槽位（胸/腿/手/独立单件），
// 只保留并补齐「同套件基名 + 同槽位」的部件。装备 = <dressup> 前缀
// 整套部件；独立单件（盔/鞋/面具/耳坠/头套…）不扩张，并剥掉图标里
// 混入的跨槽引用（如胸甲图标里带的盔/腿甲）。
function expandDressup(parts, group, outDir, local) {
  const base = dressupBase(parts[0].source);
  const slot = dressupSlot(parts[0].source);
  if (slot === 'standalone' || !/^[男女]变装-/.test(base) || base.length < 6) {
    parts.length = 1;
    return;
  }
  const kept = parts.filter(p => dressupBase(p.source) === base && dressupSlot(p.source) === slot);
  parts.length = 0;
  parts.push.apply(parts, kept);
  const have = new Set(parts.map(p => p.source));
  const extra = [];
  for (const [id, name] of Object.entries(group.maps.nameById)) {
    if (have.has(name) || AUX_NAME.test(name)) continue;
    if (dressupBase(name) !== base || dressupSlot(name) !== slot) continue;
    extra.push({ id: Number(id), name });
  }
  extra.sort((a, b) => a.id - b.id);
  for (const e of extra) {
    const r = exportFirstFrameSvg(e.id, outDir, local, e.name);
    if (r) parts.push({ svg: r.svg, source: e.name, sourceId: e.id });
  }
}

// 图标内部没有命名引用时，在 symbolClass 里按图标名找本体
// （枪-AK47火麒麟、刀-X 等，排除 图标-/辅助命名）。
function findSourceByName(nameById, iconName) {
  if (!iconName) return null;
  for (const id of Object.keys(nameById)) {
    const name = nameById[id];
    if (!name || name.startsWith('图标-') || AUX_NAME.test(name)) continue;
    if (name.includes(iconName)) return { id: Number(id), name };
  }
  return null;
}

// 轴对齐矩形 path（发光/边框底壳特征）判定：
// 4-5 个顶点、只含 M/L/Z、仅 2 个不同 x 和 2 个不同 y 即矩形
function isAxisRectPath(d) {
  if (!/^[MLZmlz\s\d.,-]+$/.test(d)) return false;
  const nums = (d.match(/-?\d*\.?\d+(?:e-?\d+)?/g) || []).map(Number);
  if (nums.length < 8 || nums.length > 10 || nums.length % 2) return false;
  const xs = new Set(), ys = new Set();
  for (let i = 0; i < nums.length; i += 2) { xs.add(nums[i]); ys.add(nums[i + 1]); }
  return xs.size <= 2 && ys.size <= 2;
}

// 统计 svg 中实际渲染的 path 数（走 use 解析，不含 defs 死节点）
function renderedPathCount(svg) {
  const root = parseSvgTree(svg);
  const idMap = {};
  (function collect(node) {
    const id = /id="([^"]+)"/.exec(node.attrs || '');
    if (id) idMap[id[1]] = node;
    node.children.forEach(collect);
  })(root);
  let n = 0;
  const seen = new Set();
  (function walk(node) {
    if (node.tag === 'defs' || node.tag === 'clipPath' || node.tag === 'filter'
        || /Gradient$/.test(node.tag) || node.tag === 'stop') return;
    if (node.tag === 'path') { n++; return; }
    if (node.tag === 'use') {
      const href = (/xlink:href="#([^"]+)"/.exec(node.attrs || '') || [])[1];
      const t = href && idMap[href];
      if (t && !seen.has(href)) { seen.add(href); walk(t); }
      return;
    }
    node.children.forEach(walk);
  })(root.children.find(c => c.tag === 'svg') || root);
  return n;
}

// ── SVG 渲染包围盒：递归走 use/transform 矩阵 ──
function matMul(a, b) {
  return {
    a: a.a * b.a + a.c * b.b, b: a.b * b.a + a.d * b.b,
    c: a.a * b.c + a.c * b.d, d: a.b * b.c + a.d * b.d,
    tx: a.a * b.tx + a.c * b.ty + a.tx,
    ty: a.b * b.tx + a.d * b.ty + a.ty,
  };
}
function parseMatrix(attr) {
  const m = /matrix\(([^)]*)\)/.exec(attr || '');
  if (!m) return null;
  const n = m[1].split(/[\s,]+/).map(Number);
  if (n.length !== 6 || n.some(isNaN)) return null;
  return { a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5] };
}

// 迷你 DOM：ffdec svg 结构规整（g/use/path/defs/clipPath），用栈式 token 解析。
function parseSvgTree(svg) {
  const root = { tag: 'root', attrs: '', children: [] };
  const stack = [root];
  const re = /<(\/?)([A-Za-z][\w:.-]*)([^>]*)>/g;
  let m;
  while ((m = re.exec(svg))) {
    const [, closing, tag, attrs] = m;
    if (closing) { if (stack.length > 1) stack.pop(); continue; }
    const node = { tag, attrs, children: [], selfClose: /\/\s*$/.test(attrs) };
    stack[stack.length - 1].children.push(node);
    if (!node.selfClose && !/^(path|use|stop|fe\w+|line|rect|circle|ellipse|polyline|polygon|image)$/i.test(tag)) {
      stack.push(node);
    }
  }
  return root;
}

function svgRenderBounds(svg) {
  const root = parseSvgTree(svg);
  const idMap = {};
  (function collect(node) {
    const id = /id="([^"]+)"/.exec(node.attrs || '');
    if (id) idMap[id[1]] = node;
    node.children.forEach(collect);
  })(root);
  const acc = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity, n: 0 };
  function addPt(x, y, M) {
    const px = M.a * x + M.c * y + M.tx, py = M.b * x + M.d * y + M.ty;
    if (px < acc.minX) acc.minX = px; if (px > acc.maxX) acc.maxX = px;
    if (py < acc.minY) acc.minY = py; if (py > acc.maxY) acc.maxY = py;
    acc.n++;
  }
  function pathBounds(d, M) {
    const toks = d.match(/[MLQCAZmlqcz]|-?\d*\.?\d+(?:e-?\d+)?/g) || [];
    for (let i = 0; i < toks.length; i++) {
      if (/^-?\d/.test(toks[i]) && i + 1 < toks.length && /^-?\d/.test(toks[i + 1])) {
        addPt(parseFloat(toks[i]), parseFloat(toks[i + 1]), M); i++;
      }
    }
  }
  function walk(node, M, skip) {
    if (node.tag === 'defs' || node.tag === 'clipPath' || node.tag === 'filter'
        || /Gradient$/.test(node.tag)) return;
    const local = parseMatrix(node.attrs);
    const M2 = local ? matMul(M, local) : M;
    if (node.tag === 'path') {
      const d = /d="([^"]*)"/.exec(node.attrs || '');
      if (d && !skip) pathBounds(d[1], M2);
      return;
    }
    if (node.tag === 'use') {
      const href = /xlink:href="#([^"]+)"/.exec(node.attrs || '');
      const t = href && idMap[href[1]];
      if (t && !skip) {
        // use 的 x/y 也是定位分量
        const ux = parseFloat((/[^t]x="(-?[\d.]+)"/.exec(node.attrs) || [])[1] || 0);
        const uy = parseFloat((/y="(-?[\d.]+)"/.exec(node.attrs) || [])[1] || 0);
        const Mu = matMul(M2, { a: 1, b: 0, c: 0, d: 1, tx: ux, ty: uy });
        walk(t, Mu, skip);
      }
      return;
    }
    node.children.forEach(c => walk(c, M2, skip));
  }
  // 只遍历 <svg> 本体；defs 里的模板不直接渲染
  const svgNode = root.children.find(c => c.tag === 'svg') || root;
  walk(svgNode, IDENTITY_M, false);
  if (!acc.n || !isFinite(acc.minX)) return null;
  return { minX: acc.minX, minY: acc.minY, w: acc.maxX - acc.minX, h: acc.maxY - acc.minY };
}

// 平衡截取 <g …>…</g> 整段（g 可嵌套，非贪婪正则会截错位置）
function extractGroup(s, openIdx) {
  const re = /<\/?g[^>]*>/g;
  re.lastIndex = openIdx;
  let depth = 0, m;
  while ((m = re.exec(s))) {
    if (m[0].startsWith('</')) { if (--depth === 0) return s.slice(openIdx, m.index + m[0].length); }
    else if (!/\/>$/.test(m[0])) depth++;
  }
  return null;
}

// 组 gid 被各 <use> 摆放后的渲染包围盒（叠加祖先 transform， defs 内不渲染）。
// 没被引用的返回 null（死 def）。
function groupRenderBounds(svg, gid) {
  const root = parseSvgTree(svg);
  const idMap = {};
  (function collect(n) {
    const id = /id="([^"]+)"/.exec(n.attrs || '');
    if (id) idMap[id[1]] = n;
    n.children.forEach(collect);
  })(root);
  const target = idMap[gid];
  if (!target) return null;
  const acc = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity, n: 0 };
  function accPts(node, M) {
    if (node.tag === 'defs' || node.tag === 'clipPath' || node.tag === 'filter'
        || /Gradient$/.test(node.tag)) return;
    const local = parseMatrix(node.attrs);
    const M2 = local ? matMul(M, local) : M;
    if (node.tag === 'path') {
      const d = /d="([^"]*)"/.exec(node.attrs || '');
      if (d) {
        const toks = d[1].match(/[MLQCAZmlqcz]|-?\d*\.?\d+(?:e-?\d+)?/g) || [];
        for (let i = 0; i < toks.length; i++) {
          if (/^-?\d/.test(toks[i]) && i + 1 < toks.length && /^-?\d/.test(toks[i + 1])) {
            const x = +toks[i], y = +toks[i + 1]; i++;
            const px = M2.a * x + M2.c * y + M2.tx, py = M2.b * x + M2.d * y + M2.ty;
            if (px < acc.minX) acc.minX = px; if (px > acc.maxX) acc.maxX = px;
            if (py < acc.minY) acc.minY = py; if (py > acc.maxY) acc.maxY = py;
            acc.n++;
          }
        }
      }
      return;
    }
    if (node.tag === 'use') {
      const href = (/xlink:href="#([^"]+)"/.exec(node.attrs || '') || [])[1];
      const t = href && idMap[href[1]];
      if (t) {
        const ux = parseFloat((/[^t]x="(-?[\d.]+)"/.exec(node.attrs) || [])[1] || 0);
        const uy = parseFloat((/y="(-?[\d.]+)"/.exec(node.attrs) || [])[1] || 0);
        accPts(t, matMul(M2, { a: 1, b: 0, c: 0, d: 1, tx: ux, ty: uy }));
      }
      return;
    }
    node.children.forEach(c => accPts(c, M2));
  }
  const seekSeen = new Set();
  function seek(node, M) {
    if (seekSeen.has(node)) return;
    seekSeen.add(node);
    if (node.tag === 'defs' || node.tag === 'clipPath' || node.tag === 'filter'
        || /Gradient$/.test(node.tag)) return;
    const local = parseMatrix(node.attrs);
    const M2 = local ? matMul(M, local) : M;
    if (node.tag === 'use') {
      const href = (/xlink:href="#([^"]+)"/.exec(node.attrs || '') || [])[1];
      const ux = parseFloat((/[^t]x="(-?[\d.]+)"/.exec(node.attrs) || [])[1] || 0);
      const uy = parseFloat((/y="(-?[\d.]+)"/.exec(node.attrs) || [])[1] || 0);
      const M3 = matMul(M2, { a: 1, b: 0, c: 0, d: 1, tx: ux, ty: uy });
      if (href === gid) { accPts(target, M3); return; }
      // 目标组经 sprite 组间接引用（defs 里的 sprite 也装着 use）→ 顺引用链继续找
      const t = href && idMap[href];
      if (t) seek(t, M3);
      return;
    }
    node.children.forEach(c => seek(c, M2));
  }
  const svgNode = root.children.find(c => c.tag === 'svg') || root;
  seek(svgNode, IDENTITY_M);
  if (!acc.n || !isFinite(acc.minX)) return null;
  return { minX: acc.minX, minY: acc.minY, w: acc.maxX - acc.minX, h: acc.maxY - acc.minY };
}

// ── 白线稿后处理：fill→none、去 glow 滤镜、统一描边 ──
function toBlueprint(svg) {
  let s = svg;
  // 命中判定挂点（刀口位置N/枪口位置N 等 use id 含「位置」）不是画面 → 连 use 删
  s = s.replace(/<use [^>]*\bid="[^"]*位置\d*"[^>]*\/>/g, '');
  // 位图 pattern 填充：pattern 定义与其填充元素一并剥掉——
  // 位图出不了线稿，留着只是个矩形壳/外框（诛神剑的剑身贴图就是这种）。
  const patIds = new Set([...s.matchAll(/<pattern[^>]*\bid="([^"]+)"/g)].map(m => m[1]));
  if (patIds.size) {
    s = s.replace(/<pattern[^>]*>[\s\S]*?<\/pattern>/g, '');
    for (const pid of patIds) {
      const esc = pid.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      // 填充可能在 fill 属性或 style="fill:url(#…)" 里（ffdec 位图 shape 用后者）
      s = s.replace(new RegExp(`<(?:path|rect|g)[^>]*(?:fill="url\\(#${esc}\\)"|style="[^"]*fill:\\s*url\\(#${esc}\\))[^>]*/>`, 'g'), '');
    }
  }
  // 矩形底壳剔除：仅当「整组全是轴对齐矩形」才动——组里带真实线条的保留
  // （金箍棒棍身、MK48 枪口护罩、Scout10 枪身都是「矩形打头+多段线」组）。
  // 删除条件二选一：铺满画面 ≥60%（发光窗/底壳）或只占 ≤4%（判定标记小方框）。
  const whole = svgRenderBounds(s);
  const rectIds = new Set();
  for (const m of s.matchAll(/<g id="(shape\d+)"[^>]*>/g)) {
    const seg = extractGroup(s, m.index);
    if (!seg) continue;
    const inner = seg.slice(seg.indexOf('>') + 1);
    if (/<(?:use|g|image|text)\b/.test(inner)) continue;
    const ds = [...inner.matchAll(/<path[^>]*d="([^"]*)"/g)].map(x => x[1]);
    if (!ds.length || !ds.every(isAxisRectPath)) continue;
    const gb = groupRenderBounds(s, m[1]);
    if (!gb) { rectIds.add(m[1]); continue; } // 无引用死 def
    const rw = whole && whole.w ? gb.w / whole.w : 0;
    const rh = whole && whole.h ? gb.h / whole.h : 0;
    if (Math.min(rw, rh) >= 0.6 || rw * rh <= 0.04) rectIds.add(m[1]);
  }
  for (const id of rectIds) {
    s = s.replace(new RegExp(`<use [^>]*xlink:href="#${id}"[^>]*/>`, 'g'), '');
    const gi = s.search(new RegExp(`<g id="${id}"[^>]*>`));
    if (gi >= 0) {
      const seg = extractGroup(s, gi);
      if (seg) s = s.slice(0, gi) + s.slice(gi + seg.length);
    }
  }
  // 滤镜 use 分两类：发光副本层可以删；本体若也带滤镜（金箍棒棒身）
  // 删了就只剩挂件——所以要求删完剩余包围盒仍覆盖 ≥85% 且 path ≥8，
  // 否则只摘 filter 属性、元素保留。
  {
    const stripped = s.replace(/<use [^>]*filter="url\(#filter\d+\)"[^>]*\/>/g, '');
    const b0 = svgRenderBounds(s), b1 = svgRenderBounds(stripped);
    const cover = b0 && b1 && b0.w > 0 && b0.h > 0
      && Math.min(b1.w / b0.w, b1.h / b0.h) >= 0.85;
    if (cover && renderedPathCount(stripped) >= 8) {
      s = stripped;
    } else {
      s = s.replace(/\s+filter="url\(#filter\d+\)"/g, '');
    }
  }
  // 含透明 stop 的渐变（光晕/淡出）——收集其 id，删除以它为 fill 的元素
  const glowGrad = new Set();
  for (const m of s.matchAll(/<(?:linear|radial)Gradient[^>]*id="(gradient\d+)"[^>]*>([\s\S]*?)<\/(?:linear|radial)Gradient>/g)) {
    if (/stop-opacity="0(\.0*)?"/.test(m[2])) glowGrad.add(m[1]);
  }
  for (const id of glowGrad) {
    s = s.replace(new RegExp(`<path [^>]*fill="url\\(#${id}\\)"[^>]*/>`, 'g'), '');
  }
  // ffdec 元数据属性与位图贴图、剪裁窗、死滤镜定义一并剥离
  s = s.replace(/\s+ffdec:[\w.-]+="[^"]*"/g, '');
  s = s.replace(/<image[^>]*\/?>(?:<\/image>)?/g, '');
  s = s.replace(/\s+clip-path="url\(#[^)]+\)"/g, '');
  s = s.replace(/<clipPath[^>]*>[\s\S]*?<\/clipPath>/g, '');
  s = s.replace(/<filter[^>]*>[\s\S]*?<\/filter>/g, '');
  // 所有 fill → none；existing stroke="none" → 白描边
  s = s.replace(/fill="[^"]*"/g, 'fill="none"');
  s = s.replace(/fill-opacity="[^"]*"/g, '');
  s = s.replace(/stroke="[^"]*"/g, 'stroke="#dfeeff"');
  s = s.replace(/stroke-width="[^"]*"/g, '');
  // 注意 <line 必须带词边界，否则误伤 <linearGradient
  s = s.replace(/(<(?:path|polyline|polygon|line|rect|ellipse|circle)(?=[\s/>]))(?![^>]*\bstroke=)/g,
    '$1 stroke="#dfeeff"');
  // 统一描边宽度（non-scaling 让嵌套 transform 下粗细一致）
  s = s.replace(/(<(?:path|polyline|polygon|line|rect|ellipse|circle)(?=[\s/>]))/g,
    '$1 stroke-width="1.4" vector-effect="non-scaling-stroke"');
  // 悬空 <use>（目标已被剔层或导出缺失）直接删，避免渲染器报整图错误
  const liveIds = new Set((s.match(/id="([^"]+)"/g) || []).map(x => x.slice(4, -1)));
  s = s.replace(/<use [^>]*xlink:href="#([^"]+)"[^>]*\/>/g,
    (tag, id) => liveIds.has(id) ? tag : '');
  // 补 viewBox：ffdec 的 width/height 是帧声明尺寸，内容经 use/transform 平移后
  // 可能完全落在框外 → 按剔除后的实际渲染内容计算包围盒。
  const bounds = svgRenderBounds(s);
  if (bounds) {
    const padX = bounds.w * 0.04 + 2, padY = bounds.h * 0.04 + 2;
    const bx = bounds.minX - padX, by = bounds.minY - padY;
    const bw = bounds.w + padX * 2, bh = bounds.h + padY * 2;
    s = s.replace(/<svg([^>]*)>/, (full, attrs) => {
      let a = attrs.replace(/\s*width="[^"]*"/, '').replace(/\s*height="[^"]*"/, '');
      return `<svg${a} viewBox="${bx.toFixed(2)} ${by.toFixed(2)} ${bw.toFixed(2)} ${bh.toFixed(2)}">`;
    });
  }
  return s;
}

// 竖置素材（刀/枪源姿态多为垂直）横置 90°，蓝图内可视面积更大
function rotateIfTall(svgText) {
  const m = /<svg[^>]*viewBox="(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+)"/.exec(svgText);
  if (!m) return svgText;
  const bx = +m[1], by = +m[2], bw = +m[3], bh = +m[4];
  if (!bw || !bh || bh / bw < 1.5) return svgText;
  const cx = bx + bw / 2, cy = by + bh / 2;
  const hw = bh / 2, hh = bw / 2;
  const open = svgText.indexOf('>', svgText.indexOf('<svg')) + 1;
  const close = svgText.lastIndexOf('</svg>');
  const head = svgText.slice(0, open).replace(/viewBox="[^"]*"/,
    `viewBox="${(cx - hw).toFixed(2)} ${(cy - hh).toFixed(2)} ${(hw * 2).toFixed(2)} ${(hh * 2).toFixed(2)}"`);
  return head + `<g transform="rotate(-90 ${cx.toFixed(2)} ${cy.toFixed(2)})">`
    + svgText.slice(open, close) + '</g></svg>';
}

// 拼合多个源素材。mode：
//   'stack'   每件各自横置 90° 后上下排（双持/入鞘=本体+鞘）——统一缩放保相对尺寸
//   'row'     多件原姿态横排（变装套装爆炸图）——统一缩放、逐件垂直居中
// noRotate：变装/穿戴素材保持原姿态，不做武器向横置。
// 扁平 <g transform> 缩放平移排布，不用嵌套 <svg>（<img> 场景下部分渲染器不可靠）。
// 不同 part 的 defs id 会撞（shape0 等），逐 part 加命名空间前缀。
function composeBlueprints(partSvgs, mode, noRotate) {
  const rot = noRotate ? (t => t) : rotateIfTall;
  const processed = partSvgs.map(t => toBlueprint(t));
  if (processed.length === 1) return rot(processed[0]);
  const nsInner = (t, i) => {
    const open = t.indexOf('>', t.indexOf('<svg')) + 1;
    const close = t.lastIndexOf('</svg>');
    let inner = t.slice(open, close);
    inner = inner.replace(/id="([^"]+)"/g, `id="p${i}_$1"`);
    inner = inner.replace(/xlink:href="#([^"]+)"/g, `xlink:href="#p${i}_$1"`);
    inner = inner.replace(/url\(#([^)]+)\)/g, `url(#p${i}_$1)`);
    return inner;
  };
  const getVb = t => {
    const m = /viewBox="([^"]*)"/.exec(t);
    return m ? m[1].split(/\s+/).map(Number) : [0, 0, 100, 100];
  };
  if (mode === 'row') {
    // 原姿态横排：统一缩放到固定行高、逐件垂直居中
    const vbs = processed.map(getVb);
    const H = 120, GAP = 16;
    const k = H / Math.max.apply(null, vbs.map(v => v[3] || 1));
    let x = 0, body = '';
    processed.forEach((t, i) => {
      const [bx, by, bw, bh] = vbs[i];
      body += `<g transform="translate(${x.toFixed(1)} ${((H - bh * k) / 2).toFixed(1)}) `
        + `scale(${k.toFixed(4)}) translate(${(-bx).toFixed(2)} ${(-by).toFixed(2)})">${nsInner(t, i)}</g>`;
      x += bw * k + GAP;
    });
    const W = Math.max(1, x - GAP).toFixed(1);
    return `<svg ${BP_XMLNS} viewBox="0 0 ${W} ${H}">${body}</svg>`;
  }
  // stack：先各自横置，再统一缩放、逐件居中竖排
  const rows = processed.map(rot);
  const vbs = rows.map(getVb);
  const W = 120, GAP = 14;
  const k = W / Math.max.apply(null, vbs.map(v => v[2] || 1));
  let y = 0, body = '';
  rows.forEach((t, i) => {
    const [bx, by, bw, bh] = vbs[i];
    body += `<g transform="translate(${((W - bw * k) / 2).toFixed(1)} ${y.toFixed(1)}) `
      + `scale(${k.toFixed(4)}) translate(${(-bx).toFixed(2)} ${(-by).toFixed(2)})">${nsInner(t, i)}</g>`;
    y += bh * k + GAP;
  });
  const H = Math.max(1, y - GAP).toFixed(1);
  return `<svg ${BP_XMLNS} viewBox="0 0 ${W} ${H}">${body}</svg>`;
}

if (!DRY) {
  fs.writeFileSync(path.join(OUT_DIR, 'manifest.json'),
    JSON.stringify({ _note: 'bake-armory-blueprints.js 生成', count: Object.keys(manifest).length,
      items: manifest }, null, 0), 'utf8');
}
console.log('blueprints written:', Object.keys(manifest).length);
const byErr = {};
for (const j of jobs.filter(x => x.error)) (byErr[j.error] = byErr[j.error] || []).push(j.iconName);
console.log('errors:', JSON.stringify(byErr));
console.log('failed:', fail.length, fail.join(','));
console.log('missing source:', missing.length, missing.join(','));
const skipped = jobs.filter(x => x.skipped).map(x => x.iconName);
if (skipped.length) console.log('skipped (BP_TUNE):', skipped.length, skipped.join(','));
const noVector = jobs.filter(x => x.noVector).map(x => x.iconName);
if (noVector.length) console.log('skipped (bitmap-only):', noVector.length, noVector.join(','));

// ── 5. 产物审计：枚举仍可能有问题的蓝图 ──
if (!DRY) {
  const audit = { empty: [], noViewBox: [], extremeAspect: [], iconFallback: [], bitmapStripped: [] };
  for (const [name, it] of Object.entries(manifest)) {
    const p = path.join(OUT_DIR, it.file);
    if (!fs.existsSync(p)) { audit.empty.push(name); continue; }
    const s = fs.readFileSync(p, 'utf8');
    const vb = (/viewBox="([^"]*)"/.exec(s) || [])[1];
    const nPaths = (s.match(/<path/g) || []).length;
    if (!nPaths) audit.empty.push(name);
    else if (!vb) audit.noViewBox.push(name);
    else {
      const [, , w, h] = vb.split(/\s+/).map(Number);
      const ar = w / h;
      if (ar > 8 || ar < 0.125) audit.extremeAspect.push(`${name}(${ar.toFixed(1)})`);
    }
    if ((it.sources || []).some(x => x && x.startsWith('图标-'))) audit.iconFallback.push(name);
  }
  // 孤儿文件清理：产物目录里不在 manifest 的 svg（旧命名残留）删掉
  const wanted = new Set(Object.values(manifest).map(i => i.file));
  const orphans = fs.readdirSync(OUT_DIR)
    .filter(f => f.endsWith('.svg') && !wanted.has(f));
  for (const f of orphans) { try { fs.unlinkSync(path.join(OUT_DIR, f)); } catch (e) {} }
  if (orphans.length) console.log('orphan svg removed:', orphans.length, orphans.slice(0, 8).join(','));

  console.log('\n── audit ──');
  console.log('empty/no-geometry:', audit.empty.length, audit.empty.join(','));
  console.log('no-viewBox:', audit.noViewBox.length, audit.noViewBox.join(','));
  console.log('extreme aspect:', audit.extremeAspect.length, audit.extremeAspect.join(','));
  console.log('icon-derived (no source sprite):', audit.iconFallback.length, audit.iconFallback.join(','));
}
