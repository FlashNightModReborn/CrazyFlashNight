/** 情报物品插图烘焙：Flash 元件 → 蓝图白线稿 SVG。
 *  复用 tools/lib/blueprint-svg.js（与武器库蓝图同一管线、同一后处理）。
 *  首批输入：flashswf/摇滚武器临时存放.swf 的三件乐器武器
 *    （话筒=DefineSprite_3 / 吉他=DefineSprite_9 / 键盘=DefineSprite_14，
 *     该 SWF 无 linkage 导出，按成员数标定——吉他 5 件、话筒 2 件、键盘 4 件）。
 *  产出：launcher/web/assets/intel-illustrations/*.svg + manifest.json
 *  用法：node tools/bake-intel-blueprints.js [--dry-run]
 */
const fs = require('fs');
const path = require('path');
const {
  exportFirstFrameSvg, toBlueprint, rotateIfTall, rotateByDeg,
  alignToPrincipalAxis, renderedPathCount,
} = require('./lib/blueprint-svg');

const ROOT = path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'launcher', 'web', 'assets', 'intel-illustrations');
const TMP = path.join(ROOT, 'tmp', 'intel-bp-bake');
const DRY = process.argv.includes('--dry-run');

// 注册表：{name, swf, spriteId, out, alt, rotateDeg|alignAxis}
// spriteId 是 SWF 内 DefineSprite characterId；换素材源时重枚举核对。
// rotateDeg：按姿态角转正（负角=逆时针），与话筒一样横放展示。
// alignAxis：素材本体歪（keytar 斜持）时按点云主轴水平化，比手调角度可靠。
const JOBS = [
  { name: '话筒', out: 'rock-park-mic.svg', swf: 'flashswf/摇滚武器临时存放.swf', spriteId: 3,
    alt: '定向声波话筒·白线稿' },
  { name: '吉他', out: 'rock-park-guitar.svg', swf: 'flashswf/摇滚武器临时存放.swf', spriteId: 9,
    alt: '电能吉他·白线稿', rotateDeg: -30 },
  { name: '键盘', out: 'rock-park-keyboard.svg', swf: 'flashswf/摇滚武器临时存放.swf', spriteId: 14,
    alt: '键盘合成器·白线稿', alignAxis: true },
];

const work = path.join(TMP);
fs.mkdirSync(path.join(work, 'svg'), { recursive: true });

const manifest = {};
const failed = [];
for (const job of JOBS) {
  const local = path.join(work, job.name + '.swf');
  fs.copyFileSync(path.join(ROOT, job.swf), local); // 中文路径→临时副本
  const r = exportFirstFrameSvg(job.spriteId, path.join(work, 'svg'), local, null);
  if (!r) { failed.push(job.name + ' export'); continue; }
  const bp = toBlueprint(r.svg);
  const svg = job.alignAxis ? alignToPrincipalAxis(bp).svg
    : job.rotateDeg ? rotateByDeg(bp, job.rotateDeg)
    : rotateIfTall(bp);
  if (renderedPathCount(svg) < 2) { failed.push(job.name + ' no-vector'); continue; }
  if (!DRY) {
    fs.mkdirSync(OUT_DIR, { recursive: true });
    fs.writeFileSync(path.join(OUT_DIR, job.out), svg, 'utf8');
  }
  const vb = /viewBox="([^"]*)"/.exec(svg);
  manifest[job.name] = {
    file: job.out, alt: job.alt, viewBox: vb ? vb[1] : null,
    source: { swf: job.swf, spriteId: job.spriteId },
  };
  console.log('ok', job.name, '→', job.out, vb ? vb[1] : '(no viewBox)');
}
if (!DRY) {
  fs.writeFileSync(path.join(OUT_DIR, 'manifest.json'),
    JSON.stringify({ _note: 'bake-intel-blueprints.js 生成', items: manifest }, null, 2), 'utf8');
}
console.log('done:', Object.keys(manifest).length, 'failed:', failed.join(',') || 'none');
