/** 平板电脑界面 Web 化素材烘焙
 *  输入：flashswf/UI/平板电脑界面.swf + data/infrastructure/infrastructure.xml
 *        + data/dictionaries/material_catalog.xml
 *  流程：ffdec 导 sprite 帧 SVG → 剔除唤起/悬停元件 → 写入 launcher/web/assets/tablet/
 *  产出：hub.svg（主屏）、view-{infrastructure,contacts,encyclopedia,materials}.svg、
 *        nav-*.svg / enc-*.svg 图标、contacts.json / materials.json / infrastructure.json、
 *        manifest.json（含 hotspots 渲染包围盒，面板按百分比覆盖热点）
 *  用法：node tools/bake-tablet-assets.js [--reuse]
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { FFDEC, svgRenderBounds } = require('./lib/blueprint-svg');

const ROOT = path.resolve(__dirname, '..');
const SWF = path.join(ROOT, 'flashswf', 'UI', '平板电脑界面.swf');
const OUT = path.join(ROOT, 'launcher', 'web', 'assets', 'tablet');
const TMP = path.join(ROOT, 'tmp', 'tablet-bake');
const REUSE = process.argv.includes('--reuse');

// 帧 13（主屏）与 334 静止帧共有需要剔除的元件：
// 唤起动画/触摸区/三条悬停说明（Web 用 DOM 实现）
const HUB_DROP = new Set(['90', '91', '93', '109', '116', '137']);
const VIEW_DROP = HUB_DROP; // 子视图同件剔除
// 图标淡入动画：帧1 alpha=0 → 提亮到接近终态的可见值
const ICON_ALPHA = '0.55';
/** sprite 全帧导出目录中取编号最大的帧（淡入动画的完成态） */
function lastFrameFile(dir) {
  const files = fs.readdirSync(dir)
    .filter(f => /^\d+\.svg$/.test(f))
    .sort((a, b) => parseInt(a) - parseInt(b));
  if (!files.length) throw new Error('no frames in ' + dir);
  return path.join(dir, files[files.length - 1]);
}
// sprite334 静止帧 → 各页背景
const VIEW_FRAMES = { infrastructure: '24', contacts: '54', encyclopedia: '84', materials: '99' };
// 图标整件 → 文件名
const NAV_ICONS = { infrastructure: '155', contacts: '165', encyclopedia: '176' };
const ENC_ICONS = { sidequests: '249', materials: '259', characters: '269', texts: '279', units: '294', factions: '304' };
// hub 热点定位锚（use 的 ffdec:characterId → 面板侧 key）
const HUB_HOTSPOTS = { nav_infrastructure: '155', nav_contacts: '165', nav_encyclopedia: '176', exit: '145' };
const ENC_HOTSPOTS = { sidequests: '249', materials: '259', characters: '269', texts: '279', units: '294', factions: '304', crumb: '176' };
const CONTACT_ROWS_CID = '221'; // 列表0-7
const CONTACT_EXTRA = { portrait: '222', ragchat: '234' };

function exportSpriteAllFrames(characterId, cacheDir) {
  const prefix = new RegExp('^DefineSprite_' + characterId + '(_|$)');
  let dir = fs.existsSync(cacheDir) ? fs.readdirSync(cacheDir).find(d => prefix.test(d)) : undefined;
  if (!dir) {
    execFileSync(FFDEC,
      ['-onerror', 'ignore', '-selectid', String(characterId), '-format', 'sprite:svg',
       '-export', 'sprite', cacheDir, SWF],
      { stdio: ['ignore', 'pipe', 'pipe'], timeout: 300000 });
    dir = fs.readdirSync(cacheDir).find(d => prefix.test(d));
  }
  if (!dir) throw new Error('sprite ' + characterId + ' export failed');
  return path.join(cacheDir, dir);
}

/** 剔除指定 characterId 的 <use>，去掉 ffdec 元数据与位图元素，按内容重算 viewBox。
 *  iconAlpha：图标 sprite 都是淡入动画，帧导出固定取第 1 帧（fill-opacity=0）；
 *  把这些全透明路径提亮到设计终态附近，否则按钮图标整批不可见（实机症状）。 */
function cleanFrameSvg(svg, dropCids, iconAlpha) {
  let s = svg;
  for (const cid of dropCids) {
    s = s.replace(new RegExp(`<use [^>]*ffdec:characterId="${cid}"[^>]*/>`, 'g'), '');
  }
  s = s.replace(/\s+ffdec:[\w.-]+="[^"]*"/g, '');
  s = s.replace(/\s+xmlns:ffdec="[^"]*"/, '');
  s = s.replace(/<image[^>]*\/?>(?:<\/image>)?/g, '');
  s = s.replace(/\s+width="[^"]*"/, (m, o) => o === 0 ? m : m); // 不动外层声明，viewBox 单独补
  if (iconAlpha != null) {
    s = s.replace(/fill-opacity="0(?:\.0+)?"/g, 'fill-opacity="' + iconAlpha + '"');
  }
  // 悬空 use（引用了被剔元件的 defs 仍留着无害）
  const liveIds = new Set((s.match(/id="([^"]+)"/g) || []).map(x => x.slice(4, -1)));
  s = s.replace(/<use [^>]*xlink:href="#([^"]+)"[^>]*\/>/g,
    (tag, id) => liveIds.has(id) ? tag : '');
  const b = svgRenderBounds(s);
  if (b) {
    const px = b.w * 0.02 + 1, py = b.h * 0.02 + 1;
    s = s.replace(/<svg([^>]*)>/, (full, attrs) => {
      let a = attrs.replace(/\s*width="[^"]*"/, '').replace(/\s*height="[^"]*"/, '');
      return `<svg${a} viewBox="${(b.minX - px).toFixed(2)} ${(b.minY - py).toFixed(2)} ${(b.w + px * 2).toFixed(2)} ${(b.h + py * 2).toFixed(2)}">`;
    });
  }
  return s;
}

// ── 本地包围盒：use 的 ffdec:characterId → 沿树累积祖先矩阵的渲染 bounds ──
// （blueprint-svg 的 groupRenderBounds 会跳过 defs 内的 use，这里自己走全树）
function miniParse(svg) {
  const root = { tag: 'root', attrs: '', children: [] };
  const stack = [root];
  const re = /<(\/?)([A-Za-z][\w:.-]*)([^>]*)>/g;
  let m;
  while ((m = re.exec(svg))) {
    const [, closing, tag, attrs] = m;
    if (closing) { if (stack.length > 1) stack.pop(); continue; }
    const node = { tag, attrs, children: [] };
    stack[stack.length - 1].children.push(node);
    if (!/\/\s*$/.test(attrs) && !/^(path|use|stop|fe\w+|line|rect|circle|ellipse|polyline|polygon|image)$/i.test(tag))
      stack.push(node);
  }
  return root;
}
const attrOf = (a, k, d) => { const m = new RegExp(k + '="([^"]*)"').exec(a || ''); return m ? m[1] : d; };
function matMul(A, B) {
  return { a: A.a*B.a + A.c*B.b, b: A.b*B.a + A.d*B.b,
           c: A.a*B.c + A.c*B.d, d: A.b*B.c + A.d*B.d,
           e: A.a*B.e + A.c*B.f + A.e, f: A.b*B.e + A.d*B.f + A.f };
}
const IDENT = { a:1,b:0,c:0,d:1,e:0,f:0 };
function parseTransform(s) {
  if (!s) return IDENT;
  let M = IDENT;
  const re = /(matrix|translate|scale|rotate)\(([^)]*)\)/g;
  let m;
  while ((m = re.exec(s))) {
    const n = m[2].split(/[\s,]+/).filter(Boolean).map(Number);
    let T = IDENT;
    if (m[1] === 'matrix') T = { a:n[0],b:n[1],c:n[2],d:n[3],e:n[4],f:n[5] };
    else if (m[1] === 'translate') T = { a:1,b:0,c:0,d:1,e:n[0]||0,f:n[1]||0 };
    else if (m[1] === 'scale') T = { a:n[0]??1,b:0,c:0,d:n[1]??n[0]??1,e:0,f:0 };
    else if (m[1] === 'rotate') {
      const r = (n[0]||0) * Math.PI/180, c = Math.cos(r), s2 = Math.sin(r);
      T = { a:c,b:s2,c:-s2,d:c,e:0,f:0 };
    }
    M = matMul(M, T);
  }
  return M;
}
function defContentBounds(node, M, acc, depth, idMap, seen) {
  if (depth > 14) return;
  const M2 = matMul(M, parseTransform(attrOf(node.attrs, 'transform')));
  if (node.tag === 'path') {
    const d = attrOf(node.attrs, 'd', '');
    const nums = d.match(/-?\.?\d*\.?\d+(?:e[+-]?\d+)?/g) || [];
    for (let i = 0; i + 1 < nums.length; i += 2) {
      const x = M2.a * +nums[i] + M2.c * +nums[i+1] + M2.e;
      const y = M2.b * +nums[i] + M2.d * +nums[i+1] + M2.f;
      if (x < acc.minX) acc.minX = x; if (x > acc.maxX) acc.maxX = x;
      if (y < acc.minY) acc.minY = y; if (y > acc.maxY) acc.maxY = y;
      acc.n++;
    }
    return;
  }
  if (node.tag === 'use') {
    const href = (attrOf(node.attrs, 'xlink:href') || attrOf(node.attrs, 'href') || '').slice(1);
    const ux = parseFloat(attrOf(node.attrs, 'x', '0')), uy = parseFloat(attrOf(node.attrs, 'y', '0'));
    const t = idMap[href];
    if (t && !seen.has(href)) {
      seen.add(href);
      defContentBounds(t, matMul(M2, { a:1,b:0,c:0,d:1,e:ux,f:uy }), acc, depth + 1, idMap, seen);
    }
    return;
  }
  node.children.forEach(c => defContentBounds(c, M2, acc, depth + 1, idMap, seen));
}
function hotspotBounds(svg, cid) {
  return hotspotBoundsAll(svg, cid)[0] || null;
}

/** 同 cid 可能多处摆位（帧内实体 + defs 内副本）；返回视图空间的全部命中，
 *  过滤条件是 bounds 落在帧 svg 的 viewBox 附近（defs 内副本坐标原点在别处）。 */
function hotspotBoundsAll(svg, cid) {
  const root = miniParse(svg);
  const idMap = {};
  (function collect(n) { const id = attrOf(n.attrs, 'id'); if (id) idMap[id] = n; n.children.forEach(collect); })(root);
  const out = [];
  const seen = new Set();
  function walk(node, M, depth) {
    if (depth > 14) return;
    const M2 = matMul(M, parseTransform(attrOf(node.attrs, 'transform')));
    if (node.tag === 'use') {
      const cc = attrOf(node.attrs, 'ffdec:characterId');
      const href = (attrOf(node.attrs, 'xlink:href') || attrOf(node.attrs, 'href') || '').slice(1);
      const ux = parseFloat(attrOf(node.attrs, 'x', '0')), uy = parseFloat(attrOf(node.attrs, 'y', '0'));
      const M3 = matMul(M2, { a:1,b:0,c:0,d:1,e:ux,f:uy });
      const t = idMap[href];
      if (cc === cid && t) {
        const acc = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity, n: 0 };
        defContentBounds(t, M3, acc, 0, idMap, new Set());
        if (acc.n && isFinite(acc.minX)) {
          const b = { x: +acc.minX.toFixed(2), y: +acc.minY.toFixed(2),
            w: +(acc.maxX - acc.minX).toFixed(2), h: +(acc.maxY - acc.minY).toFixed(2) };
          out.push(b);
        }
        return;
      }
      if (t && !seen.has(href)) { seen.add(href); walk(t, M3, depth + 1); }
      return;
    }
    node.children.forEach(c => walk(c, M2, depth));
  }
  const svgNode = root.children.find(c => c.tag === 'svg') || root;
  walk(svgNode, IDENT, 0);
  return out;
}

/** 过滤 defs 内副本：帧导出 raw 无 viewBox，用烘后视图的 viewBox 窗口判定 */
function filterByViewBox(boundsList, viewBoxStr, pad) {
  if (!viewBoxStr) return boundsList;
  const vb = viewBoxStr.split(/[\s,]+/).map(Number);
  const p = pad == null ? 80 : pad;
  const live = boundsList.filter(b =>
    b.x >= vb[0] - p && b.y >= vb[1] - p
    && b.x + b.w <= vb[0] + vb[2] + p && b.y + b.h <= vb[1] + vb[3] + p);
  return live.length ? live : boundsList;
}

function stripMeta(svg) {
  return svg.replace(/\s+ffdec:[\w.-]+="[^"]*"/g, '').replace(/\s+xmlns:ffdec="[^"]*"/, '');
}

// ── 数据投影 ──
function parseInfrastructure() {
  const xml = fs.readFileSync(path.join(ROOT, 'data', 'infrastructure', 'infrastructure.xml'), 'utf8');
  const list = [];
  for (const m of xml.matchAll(/<Infrastructure>([\s\S]*?)<\/Infrastructure>/g)) {
    const body = m[1];
    const name = (/<Name>([^<]+)<\/Name>/.exec(body) || [])[1];
    const levels = [];
    for (const lm of body.matchAll(/<Level id="(\d+)">([\s\S]*?)<\/Level>/g)) {
      const lb = lm[2];
      const val = tag => { const t = new RegExp('<' + tag + '>([\\s\\S]*?)</' + tag + '>').exec(lb); return t ? t[1].trim() : ''; };
      const materials = [...lb.matchAll(/<Material>[\s\S]*?<Name>([^<]+)<\/Name>[\s\S]*?<Value>([^<]+)<\/Value>[\s\S]*?<\/Material>/g)]
        .map(x => ({ name: x[1].trim(), count: +x[2] }));
      const skills = [...lb.matchAll(/<Skill>[\s\S]*?<Name>([^<]+)<\/Name>[\s\S]*?<Level>([^<]+)<\/Level>[\s\S]*?<\/Skill>/g)]
        .map(x => ({ name: x[1].trim(), level: +x[2] }));
      levels.push({ id: +lm[1], description: val('Description'), price: +val('Price') || 0, materials, skills });
    }
    list.push({ name, levels, maxLevel: levels.length - 1 });
  }
  return list;
}

function parseMaterials() {
  const xml = fs.readFileSync(path.join(ROOT, 'data', 'dictionaries', 'material_catalog.xml'), 'utf8');
  const list = [];
  for (const m of xml.matchAll(/<Material>([\s\S]*?)<\/Material>/g)) {
    const b = m[1];
    const t = tag => { const r = new RegExp('<' + tag + '>([\\s\\S]*?)</' + tag + '>').exec(b); return r ? r[1].trim() : ''; };
    if (t('legacyVisible') !== 'true') continue;
    list.push({
      name: t('Name'), typeId: t('typeId'),
      info: t('legacyInformation'),
      infra: t('authoredDirectPurposeId') === 'system:infrastructure_upgrade'
    });
  }
  return list;
}

const CONTACTS = ['Andy Law', 'The Girl', 'Blue', 'Shop Girl', 'Boy', 'King', 'Pig', '格格巫'];

function main() {
  fs.mkdirSync(OUT, { recursive: true });
  fs.mkdirSync(TMP, { recursive: true });

  // ── 335 全帧（主屏 = 帧13）──
  const d335 = exportSpriteAllFrames(335, TMP);
  const hubRaw = fs.readFileSync(path.join(d335, '13.svg'), 'utf8');
  const hotspots = {};
  for (const [key, cid] of Object.entries(HUB_HOTSPOTS)) {
    const b = hotspotBounds(hubRaw, cid);
    if (b) hotspots[key] = b;
  }
  const hubClean = cleanFrameSvg(hubRaw, HUB_DROP, ICON_ALPHA);
  fs.writeFileSync(path.join(OUT, 'hub.svg'), hubClean);
  const viewBoxes = { hub: (/viewBox="([^"]+)"/.exec(hubClean) || [])[1] };

  // ── 334 全帧（四页背景）──
  const d334 = exportSpriteAllFrames(334, TMP);
  const encHotspots = {};
  const contactBounds = {};
  for (const [view, frame] of Object.entries(VIEW_FRAMES)) {
    const f = path.join(d334, frame + '.svg');
    if (!fs.existsSync(f)) throw new Error('missing frame ' + frame);
    const raw = fs.readFileSync(f, 'utf8');
    if (view === 'encyclopedia') {
      for (const [key, cid] of Object.entries(ENC_HOTSPOTS)) {
        const b = hotspotBounds(raw, cid);
        if (b) encHotspots[key] = b;
      }
    }
    const clean = cleanFrameSvg(raw, VIEW_DROP, ICON_ALPHA);
    fs.writeFileSync(path.join(OUT, 'view-' + view + '.svg'), clean);
    if (view === 'contacts') {
      const vbStr = (/viewBox="([^"]+)"/.exec(clean) || [])[1];
      const rows = filterByViewBox(hotspotBoundsAll(raw, CONTACT_ROWS_CID), vbStr);
      if (rows.length) contactBounds.rows = rows;
      for (const [key, cid] of Object.entries(CONTACT_EXTRA)) {
        const bb = filterByViewBox(hotspotBoundsAll(raw, cid), vbStr)[0];
        if (bb) contactBounds[key] = bb;
      }
    }
    viewBoxes[view] = (/viewBox="([^"]+)"/.exec(clean) || [])[1];
  }

  // ── 图标单件：取末帧（淡入完成态），帧1 alpha=0 不可用 ──
  for (const [name, cid] of Object.entries(NAV_ICONS)) {
    const d = exportSpriteAllFrames(cid, TMP);
    fs.writeFileSync(path.join(OUT, 'nav-' + name + '.svg'),
      cleanFrameSvg(fs.readFileSync(lastFrameFile(d), 'utf8'), new Set()));
  }
  for (const [name, cid] of Object.entries(ENC_ICONS)) {
    const d = exportSpriteAllFrames(cid, TMP);
    fs.writeFileSync(path.join(OUT, 'enc-' + name + '.svg'),
      cleanFrameSvg(fs.readFileSync(lastFrameFile(d), 'utf8'), new Set()));
  }

  // ── 数据 ──
  const infra = parseInfrastructure();
  fs.writeFileSync(path.join(OUT, 'infrastructure.json'), JSON.stringify(infra));
  const mats = parseMaterials();
  fs.writeFileSync(path.join(OUT, 'materials.json'), JSON.stringify(mats));
  fs.writeFileSync(path.join(OUT, 'contacts.json'), JSON.stringify(CONTACTS.map(n => ({ name: n, shopId: n }))));

  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify({
    schema: 'cf7-tablet-assets-v1',
    source: 'flashswf/UI/平板电脑界面.swf',
    views: Object.fromEntries(Object.keys(VIEW_FRAMES).map(v => [v, 'view-' + v + '.svg'])),
    navIcons: NAV_ICONS, encIcons: ENC_ICONS,
    hotspots, encHotspots, contactBounds, viewBoxes,
    counts: { infrastructure: infra.length, materials: mats.length, contacts: CONTACTS.length }
  }, null, 2));

  console.log('hub hotspots:', JSON.stringify(hotspots));
  console.log('enc hotspots:', JSON.stringify(encHotspots));
  console.log('contact bounds:', JSON.stringify(contactBounds));
  console.log('infra:', infra.length, 'materials:', mats.length);
  console.log('wrote', OUT);
}
main();
