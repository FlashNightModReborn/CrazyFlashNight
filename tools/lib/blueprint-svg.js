/** 蓝图白线稿共享库：ffdec 导出 + SVG 后处理（白描线稿化/拼合）。
 *  从 bake-armory-blueprints.js 抽出，供武器库蓝图与情报插图烘焙共用。
 *  方案与踩坑：docs/武器库蓝图描线-Flash素材烘焙与引用解析方案-2026-10-10.md
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const FFDEC = path.join(ROOT, 'tools', 'ffdec', 'ffdec-cli.exe');
const IDENTITY_M = { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 };
const BP_XMLNS = 'xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"';

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

module.exports = {
  ROOT, FFDEC, IDENTITY_M, BP_XMLNS,
  exportFirstFrameSvg, exportShapeSvg,
  isAxisRectPath, renderedPathCount,
  matMul, parseMatrix, parseSvgTree, svgRenderBounds,
  extractGroup, groupRenderBounds,
  toBlueprint, rotateIfTall, composeBlueprints,
};
