'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { renderedPathCount } = require('./blueprint-svg');

// 武器库按 icon 请求同名 SVG。manifest 另由烘焙器用于保留或清理文件，两者都要对齐。
function checkWeaponBlueprints(products, directory, tuning) {
  if (!products.length) throw new Error('武器合成配方为空，无法检查蓝图覆盖');
  const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8').replace(/^\uFEFF/, ''));
  const entries = manifest.items;
  if (!entries || typeof entries !== 'object' || Array.isArray(entries)) {
    throw new Error('蓝图 manifest.json 缺少 items 对象');
  }

  // 按目录中的真实拼写匹配，Windows 上也能报出只有大小写不同的文件。
  const files = new Set(fs.readdirSync(directory, { withFileTypes: true }).filter(f => f.isFile()).map(f => f.name));
  const findings = [];
  let covered = 0, exempt = 0;
  for (const [index, product] of products.entries()) {
    const { name, icon, source } = product;
    const label = (product.recipeId || '配方 #' + (index + 1)) + ' ' + (name || '（无产物）');
    if (!source) {
      findings.push(label + '：在 data/items/list.xml 加载的物品中找不到该产物');
      continue;
    }
    const filename = icon + '.svg';
    const registered = Object.hasOwn(entries, icon);
    const present = files.has(filename);
    if (tuning[icon]?.skip && !registered && !present) {
      exempt++;
      continue;
    }
    const issues = [];
    if (!registered) issues.push('清单缺项');
    else if (entries[icon]?.file !== filename) issues.push('清单文件名与界面请求不一致');
    if (!present) issues.push('缺同名 SVG');
    else {
      const svg = fs.readFileSync(path.join(directory, filename), 'utf8');
      if (!/<svg\b/.test(svg) || !renderedPathCount(svg)) issues.push('缺少可引用的线稿路径');
    }
    if (issues.length) findings.push(`${label} → ${filename}（${issues.join('、')}，物品表 ${source}）`);
    else covered++;
  }
  return { findings, covered, exempt };
}

module.exports = { checkWeaponBlueprints };
