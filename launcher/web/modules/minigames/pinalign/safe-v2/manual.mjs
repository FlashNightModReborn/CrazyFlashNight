import { MANUAL_SHOTS } from './manual-images.mjs';
import { STRUCTURES, PUZZLE_TYPES } from './config.mjs';

export const escapeHTML = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function resolveManualImgSrc(relPath) {
  try {
    return new URL('../' + relPath, import.meta.url).href;
  } catch {
    return relPath;
  }
}

function diagram(page) {
  const key = (page < 3 ? 'a' : 'b') + (page % 3), shot = MANUAL_SHOTS[key];
  const x = shot.point.x.toFixed(1), y = shot.point.y.toFixed(1);
  const dirs = [[85, 0], [0, -80], [0, 0], [-85, 0], [0, 80], [0, 0]], [dx, dy] = dirs[page];
  const nx = (shot.point.x + dx).toFixed(1), ny = (shot.point.y + dy).toFixed(1);
  const name = STRUCTURES[page < 3 ? 'a' : 'b'][page % 3].title;
  const arrow = shot.kind === 'arc'
    ? shot.path.map((q, i) => (i ? 'L' : 'M') + q.x.toFixed(1) + ' ' + q.y.toFixed(1)).join(' ')
    : `M${x} ${y}L${nx} ${ny}`;
  const imgSrc = resolveManualImgSrc(shot.src);
  return `<div class="manual-diagram actual"><div class="manual-photo"><img width="500" height="310" src="${escapeHTML(imgSrc)}" alt="${escapeHTML(name)}，与柜门上同一形制"><svg viewBox="0 0 500 310" aria-hidden="true"><defs><marker id="manual-action-arrow" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto"><path d="M0 0 8 4 0 8Z" fill="#f0c37e"/></marker></defs><circle cx="${x}" cy="${y}" r="15" fill="none" stroke="#17252c" stroke-width="7"/><circle cx="${x}" cy="${y}" r="15" fill="none" stroke="#f0c37e" stroke-width="3"/><path d="${arrow}" fill="none" stroke="#18242b" stroke-width="7"/><path d="${arrow}" fill="none" stroke="#f0c37e" stroke-width="3" marker-end="url(#manual-action-arrow)"/></svg></div><div class="diagram-caption">圈内为作用点 · 认准黄铜止挡销，向无销敞口侧短拖</div></div>`;
}

const step = (n, title, text) => `<div class="manual-step"><span>${n}</span><div><b>${escapeHTML(title)}</b><p>${escapeHTML(text)}</p></div></div>`;

export function manualPage(page) {
  if (page < 6) {
    const s = STRUCTURES[page < 3 ? 'a' : 'b'][page % 3];
    return `<article class="manual-page"><div class="page-kicker">${page < 3 ? '结构 Ⅰ / 解除承压（正反双极性）' : '结构 Ⅱ / 牵引释放（正反双极性）'}</div><h3>${escapeHTML(s.title)}</h3>${diagram(page)}${step(1, '识别', s.feature)}${step(2, '作用点', s.point)}${step(3, '极性判读', s.action)}${step(4, '啮合反馈', s.result)}<p class="manual-warning">${escapeHTML(s.recovery)}</p></article>`;
  }
  const p = PUZZLE_TYPES[page - 6];
  const examples = [
    [
      'Ⅰ行看旋向 → Ⅱ行推目标章 → 查对照栏',
      '第一行 ○▲ → ○►（顺转90°）；第二行 □► 顺转90° 得 □▼，查下方 □▼ 对应三位钢印号。',
      '若第一行 ○▲ → ○▼（翻转180°），则第二行 □► 翻转180° 得 □◄，无需任何加减心算。',
    ],
    [
      '五章同制 · 一章破规 → 直读异类批号',
      '六枚钢印中五枚为“闭环＋双对称铆钉”，唯一一枚为“断口环＋单铆钉”，直接抄其下方三位号。',
      '也可能五枚为“闭环正立▲”、一枚为“断口倒置▼”；视觉扫一眼即可定位异类。',
    ],
    [
      '掩模缺口对准底盘顶缺口▲ → 按①②③读数',
      '掩模缺口在顶边（▲）时直接正置套在 3×3 底盘上，依次读取孔①(百)、孔②(十)、孔③(个)。',
      '掩模缺口在底边（▼）时先在脑中旋转 180° 让缺口朝上，再按旋转后的 ①→②→③ 孔位读数。',
    ],
  ][page - 6];
  return `<article class="manual-page"><div class="page-kicker">暗语图推 / 公开规则 ${page - 5}</div><h3>${escapeHTML(p.title)}</h3><div class="manual-rule">${escapeHTML(examples[0])}</div>${step(1, '图面特征', p.recognition)}${step(2, '一步解法', p.help)}${step(3, '正置示例', examples[1])}${step(4, '变体示例', examples[2])}<p class="manual-warning">一次视觉推导直接产出完整三位密码（100–999）。只在点击“开锁”或按 Enter 时校验整段答案。</p></article>`;
}

export function manualIndex(page) {
  const ids = page < 6 ? [0, 1, 2, 3, 4, 5] : [6, 7, 8];
  return ids.map(i => `<button data-page="${i}" class="${i === page ? 'active' : ''}" title="${escapeHTML(i < 6 ? STRUCTURES[i < 3 ? 'a' : 'b'][i % 3].title : PUZZLE_TYPES[i - 6].title)}">${i < 3 ? 'Ⅰ · ' + (i + 1) : i < 6 ? 'Ⅱ · ' + (i - 2) : PUZZLE_TYPES[i - 6].title}</button>`).join('');
}
