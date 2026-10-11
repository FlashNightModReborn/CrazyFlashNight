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

// 运行时 _visible=0 的屏外元素（唤起动画/触摸区/三条悬停说明）：XFL 帧1脚本隐藏但导出帧仍含
const HIDE_ALWAYS = ['90', '91', '93', '109', '116', '137'];
// 图标与悬停说明从背景剥离：原 XFL 本就是"按钮图标分离"结构，Web 版图标作 DOM 层
// 才能复现进入子页时图标位移/淡入动画；图鉴六分类同理
// 常驻动画件从背景剥离：叉整体(145→内部143乱码循环)与无人机(217)改由 DOM 帧序列驱动
const VIEW_DROP = {
  hub: [...HIDE_ALWAYS, '155', '165', '176', '145'],
  infrastructure: [...HIDE_ALWAYS, '155', '165', '176', '145'],
  contacts: [...HIDE_ALWAYS, '155', '165', '176', '145', '217'],
  encyclopedia: [...HIDE_ALWAYS, '155', '165', '176', '145', '249', '259', '269', '279', '294', '304'],
  materials: [...HIDE_ALWAYS, '155', '165', '176', '145', '249', '259', '269', '279', '294', '304'],
};
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
// sprite334 静止帧 → 各页背景；取 label 的 stop() 定格帧（XFL 0 基 index → ffdec 帧号）
const VIEW_FRAMES = { infrastructure: '25', contacts: '55', encyclopedia: '85', materials: '99' };
// 图标整件 → 文件名
const NAV_ICONS = { infrastructure: '155', contacts: '165', encyclopedia: '176' };
const ENC_ICONS = { sidequests: '249', materials: '259', characters: '269', texts: '279', units: '294', factions: '304' };
// hub 三入口 rollOver 播放的悬停说明浮层（透明按钮 on(rollOver) → play；Web 以 img 覆盖还原）
const HOVER_DESCS = { nav_infrastructure: '109', nav_contacts: '116', nav_encyclopedia: '137' };
// 子视图"重按返回"锚：进入子页后当前页图标移到左上，点它返回上一层；
// 材料大全页以图鉴图标作面包屑返回图鉴页；叉（cid 145）在材料页不显示
const VIEW_BACK = { infrastructure: '155', contacts: '165', encyclopedia: '176', materials: '176' };
const EXIT_CID = '145';
// hub 热点定位锚（use 的 ffdec:characterId → 面板侧 key）
const HUB_HOTSPOTS = { nav_infrastructure: '155', nav_contacts: '165', nav_encyclopedia: '176', exit: '145' };
const ENC_HOTSPOTS = { sidequests: '249', materials: '259', characters: '269', texts: '279', units: '294', factions: '304', crumb: '176' };
const CONTACT_ROWS_CID = '221'; // 列表0-7
const CONTACT_EXTRA = { portrait: '222', ragchat: '234' };
// 联络动作按钮：进入商店（打开当前头像 NPC 商店）；终端通信=234 已在 CONTACT_EXTRA
const CONTACT_ACTION_BOUNDS = { shop: '223' };
// 基建内容整体内部锚点：名称/简介/升级需求文本框、升级按钮、滑动按钮栏容器
const INFRA_BOUNDS = { name: '204', desc: '203', req: '205', upgrade: '207' };
const INFRA_LIST_CID = '202';
// 滑动按钮栏内的滚动轨(199)与滑块(201)：烘进背景只是装饰，Web 侧按
// 其包围盒叠加透明拖拽层，驱动列表 scrollTop（原版 scrollbutton 拖动语义）
const INFRA_SCROLL = { rail: '199', thumb: '201' };
// 滑动按钮栏行几何（XFL 滑动按钮栏.xml：btnWidth=120, btnHeight=20, btnBound=25）
const INFRA_ROW = { w: 120, h: 20, pitch: 25, rows: 8 };
// 常驻动画：自包含 sprite 帧导出（内部无运行时 _visible 元件，帧序列干净）
// exit-glow = 叉整体(145)内部的「退出」乱码闪变循环；drone = 联络视图的无人机飞行循环
const AMBIENT_EXPORTS = [
  { key: 'exitGlow', cid: '143', zoom: 1 },
  { key: 'drone', cid: '217', zoom: 0.15 },
];

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

/** sprite:png 帧导出（常驻动画用）。cacheDir 需与 SVG 导出目录分开，
 *  同 cid 的目录名前缀相同，靠目录内扩展名区分是否已导过。 */
function exportSpritePngFrames(characterId, cacheDir, zoom) {
  const prefix = new RegExp('^DefineSprite_' + characterId + '(_|$)');
  const find = () => (fs.existsSync(cacheDir) ? fs.readdirSync(cacheDir)
    .find(d => prefix.test(d) && fs.readdirSync(path.join(cacheDir, d)).some(f => f.endsWith('.png'))) : undefined);
  let dir = find();
  if (!dir) {
    const args = ['-onerror', 'ignore', '-selectid', String(characterId)];
    if (zoom && zoom !== 1) args.push('-zoom', String(zoom));
    args.push('-format', 'sprite:png', '-export', 'sprite', cacheDir, SWF);
    execFileSync(FFDEC, args, { stdio: ['ignore', 'pipe', 'pipe'], timeout: 300000 });
    dir = find();
  }
  if (!dir) throw new Error('sprite ' + characterId + ' png export failed');
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

/** 目标 cid 的 <use> 在视图空间的累积摆放矩阵（不含内部内容，适合
 *  把 sprite 自身 viewBox 映射到帧内位置；悬停说明带大面积遮罩/引导线，
 *  直接按帧内路径 bounds 会高估出屏，需要用此法取实际摆放）。 */
function usePlacementMatrix(svg, cid) {
  const root = miniParse(svg);
  const idMap = {};
  (function collect(n) { const id = attrOf(n.attrs, 'id'); if (id) idMap[id] = n; n.children.forEach(collect); })(root);
  let found = null;
  const seen = new Set();
  function walk(node, M, depth) {
    if (depth > 14 || found) return;
    const M2 = matMul(M, parseTransform(attrOf(node.attrs, 'transform')));
    if (node.tag === 'use') {
      const cc = attrOf(node.attrs, 'ffdec:characterId');
      const href = (attrOf(node.attrs, 'xlink:href') || attrOf(node.attrs, 'href') || '').slice(1);
      const ux = parseFloat(attrOf(node.attrs, 'x', '0')), uy = parseFloat(attrOf(node.attrs, 'y', '0'));
      const M3 = matMul(M2, { a:1,b:0,c:0,d:1,e:ux,f:uy });
      if (cc === cid) { found = M3; return; }
      const t = idMap[href];
      if (t && !seen.has(href)) { seen.add(href); walk(t, M3, depth + 1); }
      return;
    }
    node.children.forEach(c => walk(c, M2, depth));
  }
  const svgNode = root.children.find(c => c.tag === 'svg') || root;
  walk(svgNode, IDENT, 0);
  return found;
}
function transformRect(M, r) {
  const pts = [[r.x, r.y], [r.x + r.w, r.y], [r.x, r.y + r.h], [r.x + r.w, r.y + r.h]];
  const tp = pts.map(p => ({ x: M.a * p[0] + M.c * p[1] + M.e, y: M.b * p[0] + M.d * p[1] + M.f }));
  const xs = tp.map(p => p.x), ys = tp.map(p => p.y);
  const minX = Math.min.apply(null, xs), maxX = Math.max.apply(null, xs);
  const minY = Math.min.apply(null, ys), maxY = Math.max.apply(null, ys);
  return { x: +minX.toFixed(2), y: +minY.toFixed(2), w: +(maxX - minX).toFixed(2), h: +(maxY - minY).toFixed(2) };
}

/** <use> 摆放矩形：use 声明的 width/height（文档尺寸）经累积矩阵映射到视图空间。
 *  按钮/文本元件在 ffdec 帧导出里没有可求 bounds 的 <path> 内容，
 *  hotspotBounds 取不到；文本框的声明尺寸本身就是排版位置，更贴合。 */
function usePlacedBounds(svg, cid) {
  const root = miniParse(svg);
  const idMap = {};
  (function collect(n) { const id = attrOf(n.attrs, 'id'); if (id) idMap[id] = n; n.children.forEach(collect); })(root);
  let found = null;
  const seen = new Set();
  function walk(node, M, depth) {
    if (depth > 14 || found) return;
    const M2 = matMul(M, parseTransform(attrOf(node.attrs, 'transform')));
    if (node.tag === 'use') {
      const cc = attrOf(node.attrs, 'ffdec:characterId');
      const href = (attrOf(node.attrs, 'xlink:href') || attrOf(node.attrs, 'href') || '').slice(1);
      const ux = parseFloat(attrOf(node.attrs, 'x', '0')), uy = parseFloat(attrOf(node.attrs, 'y', '0'));
      const M3 = matMul(M2, { a: 1, b: 0, c: 0, d: 1, e: ux, f: uy });
      if (cc === cid) {
        const w = parseFloat(attrOf(node.attrs, 'width', '0'));
        const h = parseFloat(attrOf(node.attrs, 'height', '0'));
        if (w > 0 && h > 0) found = transformRect(M3, { x: 0, y: 0, w, h });
        return;
      }
      const t = idMap[href];
      if (t && !seen.has(href)) { seen.add(href); walk(t, M3, depth + 1); }
      return;
    }
    node.children.forEach(c => walk(c, M2, depth));
  }
  const svgNode = root.children.find(c => c.tag === 'svg') || root;
  walk(svgNode, IDENT, 0);
  return found;
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
// 原 XFL 联络页 NPC头像.loadMovie("flashswf/portraits/profiles/<名字>.png")
// 45% 缩放进入 200×200 框；web 侧原样复制 PNG 进 assets，等比+裁剪不做压缩
const PROFILE_SRC = path.join(ROOT, 'flashswf', 'portraits', 'profiles');

/** SWF 头帧率（8.8 定点），供常驻动画按原速播放。CWS 需先解压头段 */
function swfFrameRate() {
  const zlib = require('zlib');
  const b = fs.readFileSync(SWF);
  let body = b.slice(8);
  if (b[0] === 0x43) body = zlib.inflateSync(body); // CWS：签名 C + zlib 流
  const nbits = body[0] >> 3;
  const off = Math.ceil((5 + nbits * 4) / 8);
  const fps = ((body[off + 1] << 8) | body[off]) / 256;
  return fps > 0 ? +fps.toFixed(3) : 24;
}

function main() {
  fs.mkdirSync(OUT, { recursive: true });
  fs.mkdirSync(TMP, { recursive: true });

  const ambient = {};
  for (const a of AMBIENT_EXPORTS) ambient[a.key] = { fps: swfFrameRate(), places: {} };

  // ── 335 全帧（主屏 = 帧13）──
  const d335 = exportSpriteAllFrames(335, TMP);
  const hubRaw = fs.readFileSync(path.join(d335, '13.svg'), 'utf8');
  const hotspots = {};
  for (const [key, cid] of Object.entries(HUB_HOTSPOTS)) {
    const b = hotspotBounds(hubRaw, cid);
    if (b) hotspots[key] = b;
  }
  const hubGlow = usePlacedBounds(hubRaw, '143') || hotspotBounds(hubRaw, '143');
  if (hubGlow) ambient.exitGlow.places.hub = hubGlow;
  const hubClean = cleanFrameSvg(hubRaw, new Set(VIEW_DROP.hub), ICON_ALPHA);
  fs.writeFileSync(path.join(OUT, 'hub.svg'), hubClean);
  const viewBoxes = { hub: (/viewBox="([^"]+)"/.exec(hubClean) || [])[1] };

  // ── 334 全帧（四页背景）──
  const d334 = exportSpriteAllFrames(334, TMP);
  const encHotspots = {};
  const contactBounds = {};
  const infraBounds = {};
  let infraRows = null;
  const viewBack = {}, viewExits = {};
  const iconPlaces = { hub: {} }, encIconPlaces = {};
  for (const [key, cid] of Object.entries(NAV_ICONS)) {
    const b = hotspotBounds(hubRaw, cid);
    if (b) iconPlaces.hub[key] = b;
  }
  for (const [view, frame] of Object.entries(VIEW_FRAMES)) {
    const f = path.join(d334, frame + '.svg');
    if (!fs.existsSync(f)) throw new Error('missing frame ' + frame);
    const raw = fs.readFileSync(f, 'utf8');
    const bb = hotspotBounds(raw, VIEW_BACK[view]);
    if (bb) viewBack[view] = bb;
    const eb = hotspotBounds(raw, EXIT_CID);
    if (eb) viewExits[view] = eb;
    const gb = usePlacedBounds(raw, '143') || hotspotBounds(raw, '143');
    if (gb) ambient.exitGlow.places[view] = gb;
    iconPlaces[view] = {};
    for (const [key, cid] of Object.entries(NAV_ICONS)) {
      const b = hotspotBounds(raw, cid);
      if (b) iconPlaces[view][key] = b;
    }
    if (view === 'encyclopedia' || view === 'materials') {
      encIconPlaces[view] = {};
      for (const [key, cid] of Object.entries(ENC_ICONS)) {
        const b = hotspotBounds(raw, cid);
        if (b) encIconPlaces[view][key] = b;
      }
    }
    if (view === 'encyclopedia') {
      for (const [key, cid] of Object.entries(ENC_HOTSPOTS)) {
        const b = hotspotBounds(raw, cid);
        if (b) encHotspots[key] = b;
      }
    }
    const clean = cleanFrameSvg(raw, new Set(VIEW_DROP[view]), ICON_ALPHA);
    fs.writeFileSync(path.join(OUT, 'view-' + view + '.svg'), clean);
    const vbStr = (/viewBox="([^"]+)"/.exec(clean) || [])[1];
    if (view === 'contacts') {
      const rows = filterByViewBox(hotspotBoundsAll(raw, CONTACT_ROWS_CID), vbStr);
      if (rows.length) contactBounds.rows = rows;
      for (const [key, cid] of Object.entries(CONTACT_EXTRA)) {
        const bb = filterByViewBox(hotspotBoundsAll(raw, cid), vbStr)[0];
        if (bb) contactBounds[key] = bb;
      }
      for (const [key, cid] of Object.entries(CONTACT_ACTION_BOUNDS)) {
        const bb = filterByViewBox(hotspotBoundsAll(raw, cid), vbStr)[0]
          || usePlacedBounds(raw, cid);
        if (bb) contactBounds[key] = bb;
      }
      // 终端通信按钮在帧导出里没有可求 bounds 的路径（DefineButton），用摆放矩阵
      for (const [key, cid] of Object.entries(CONTACT_EXTRA)) {
        if (!contactBounds[key]) {
          const bb = usePlacedBounds(raw, cid);
          if (bb) contactBounds[key] = bb;
        }
      }
      const db = usePlacedBounds(raw, '217');
      if (db) ambient.drone.places.contacts = db;
    }
    if (view === 'infrastructure') {
      for (const [key, cid] of Object.entries(INFRA_BOUNDS)) {
        // 文本/按钮元件：声明尺寸即排版框，优先用摆放矩形
        const bb = usePlacedBounds(raw, cid) || hotspotBounds(raw, cid);
        if (bb) infraBounds[key] = bb;
      }
      const lb = usePlacedBounds(raw, INFRA_LIST_CID) || hotspotBounds(raw, INFRA_LIST_CID);
      if (lb) infraBounds.list = lb;
      for (const [key, cid] of Object.entries(INFRA_SCROLL)) {
        const bb = usePlacedBounds(raw, cid) || hotspotBounds(raw, cid);
        if (bb) infraBounds[key] = bb;
      }
      // 行框：滑动按钮栏局部 (0, 25i, 120×20) 经摆放矩阵映射到视图
      const M = usePlacementMatrix(raw, INFRA_LIST_CID);
      if (M) {
        infraRows = [];
        for (let i = 0; i < INFRA_ROW.rows; i++) {
          infraRows.push(transformRect(M,
            { x: 0, y: INFRA_ROW.pitch * i, w: INFRA_ROW.w, h: INFRA_ROW.h }));
        }
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

  // ── 悬停说明浮层：同取末帧（说明展开完成态）；包围盒用摆放矩阵映射其
  //    自身 viewBox —— 说明 sprite 内含大面积遮罩与屏外引导线，按帧内路径
  //    bounds 会把遮盖区也算进去导致覆盖错位 ──
  const hovers = {};
  for (const [name, cid] of Object.entries(HOVER_DESCS)) {
    const d = exportSpriteAllFrames(cid, TMP);
    const svg = cleanFrameSvg(fs.readFileSync(lastFrameFile(d), 'utf8'), new Set());
    fs.writeFileSync(path.join(OUT, 'hover-' + name + '.svg'), svg);
    const M = usePlacementMatrix(hubRaw, cid);
    const vbStr = (/viewBox="([^"]+)"/.exec(svg) || [])[1];
    if (M && vbStr) {
      const p = vbStr.split(/[\s,]+/).map(Number);
      hovers[name] = transformRect(M, { x: p[0], y: p[1], w: p[2], h: p[3] });
    }
  }

  // ── 常驻动画帧序列 → assets/tablet/ambient/<key>/fNN.png ──
  const ambientTmp = path.join(TMP, 'ambient-png');
  fs.mkdirSync(ambientTmp, { recursive: true });
  for (const a of AMBIENT_EXPORTS) {
    const d = exportSpritePngFrames(a.cid, ambientTmp, a.zoom);
    const frames = fs.readdirSync(d)
      .filter(f => /^\d+\.png$/.test(f))
      .sort((x, y) => parseInt(x) - parseInt(y));
    const od = path.join(OUT, 'ambient', a.key);
    fs.mkdirSync(od, { recursive: true });
    frames.forEach((f, i) => fs.copyFileSync(
      path.join(d, f),
      path.join(od, 'f' + String(i + 1).padStart(2, '0') + '.png')));
    ambient[a.key].frames = frames.length;
  }

  // ── 数据 ──
  const infra = parseInfrastructure();
  fs.writeFileSync(path.join(OUT, 'infrastructure.json'), JSON.stringify(infra));
  const mats = parseMaterials();
  fs.writeFileSync(path.join(OUT, 'materials.json'), JSON.stringify(mats));
  // 联络头像：原版 NPC头像 直接 loadMovie profiles/<名字>.png（400×400，45% 缩放
  // 进 200×200 框）；文件名大小写不一致（boy/king/pig 小写），大小写不敏感查找后原样复制
  const profOut = path.join(OUT, 'portraits');
  fs.mkdirSync(profOut, { recursive: true });
  const profFiles = fs.existsSync(PROFILE_SRC) ? fs.readdirSync(PROFILE_SRC) : [];
  const contactsJson = CONTACTS.map(n => {
    const low = n.toLowerCase() + '.png';
    const srcName = profFiles.find(f => f.toLowerCase() === low);
    let uri = null;
    if (srcName) {
      fs.copyFileSync(path.join(PROFILE_SRC, srcName), path.join(profOut, n + '.png'));
      uri = 'portraits/' + encodeURIComponent(n) + '.png';
    } else {
      console.log('WARN: no profile portrait for', n);
    }
    return { name: n, shopId: n, portrait: uri };
  });
  fs.writeFileSync(path.join(OUT, 'contacts.json'), JSON.stringify(contactsJson));

  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify({
    schema: 'cf7-tablet-assets-v1',
    source: 'flashswf/UI/平板电脑界面.swf',
    views: Object.fromEntries(Object.keys(VIEW_FRAMES).map(v => [v, 'view-' + v + '.svg'])),
    navIcons: NAV_ICONS, encIcons: ENC_ICONS,
    hotspots, encHotspots, contactBounds, infraBounds, infraRows, viewBoxes,
    hovers, viewBack, exits: viewExits, iconPlaces, encIconPlaces, ambient,
    counts: { infrastructure: infra.length, materials: mats.length, contacts: CONTACTS.length }
  }, null, 2));

  console.log('hub hotspots:', JSON.stringify(hotspots));
  console.log('enc hotspots:', JSON.stringify(encHotspots));
  console.log('contact bounds:', JSON.stringify(contactBounds));
  console.log('infra:', infra.length, 'materials:', mats.length);
  console.log('wrote', OUT);
}
main();
