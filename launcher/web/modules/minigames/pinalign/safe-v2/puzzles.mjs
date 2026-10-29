import { CONFIG, PUZZLE_TYPES } from './config.mjs';

export const DIRS = Object.freeze(['▲', '►', '▼', '◄']);
export const MATRIX_DELTAS = Object.freeze([1, 2]);
export const ODD_SLOTS = Object.freeze([0, 1, 2, 3, 4, 5]);
export const ODD_LABELS = Object.freeze(['①', '②', '③', '④', '⑤', '⑥']);
export const GRILLE_MASKS = Object.freeze([
  Object.freeze({ id: 0, holes: Object.freeze([0, 4, 8]), rot: 0, notch: '▲上缺口（正置直套）' }),
  Object.freeze({ id: 1, holes: Object.freeze([1, 3, 7]), rot: 0, notch: '▲上缺口（正置直套）' }),
  Object.freeze({ id: 2, holes: Object.freeze([2, 4, 6]), rot: 180, notch: '▼下缺口（转180°对准▲）' }),
  Object.freeze({ id: 3, holes: Object.freeze([0, 5, 7]), rot: 180, notch: '▼下缺口（转180°对准▲）' }),
]);

export function hashSeed(seed) {
  const text = String(seed);
  let hash = 2166136261;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/**
 * Random-access series identity. Index 0 preserves the base seed directly;
 * later boxes depend only on the base seed and index, never retries or elapsed time.
 */
export function deriveSafeSeed(seriesSeed, safeIndex = 0) {
  if (!Number.isSafeInteger(safeIndex) || safeIndex < 0) {
    throw new RangeError('safeIndex must be a nonnegative safe integer');
  }
  const seedText = String(seriesSeed);
  return safeIndex === 0 ? seedText : `CF7-safe-series-v2:${JSON.stringify([seedText, safeIndex])}`;
}

/** Mulberry32: deterministic PRNG. */
export function createRng(seed) {
  let word = typeof seed === 'number' ? seed >>> 0 : hashSeed(seed);
  return () => {
    word = (word + 0x6D2B79F5) >>> 0;
    let mix = word;
    mix = Math.imul(mix ^ (mix >>> 15), mix | 1);
    mix ^= mix + Math.imul(mix ^ (mix >>> 7), mix | 61);
    return ((mix ^ (mix >>> 14)) >>> 0) / 4294967296;
  };
}

function integerIn(value, lo, hi) {
  return Number.isInteger(value) && value >= lo && value <= hi;
}

export function isLegalParams(type, p) {
  if (!p || typeof p !== 'object') return false;
  if (type === 'matrix') {
    return integerIn(p.aDir, 0, 2)
      && MATRIX_DELTAS.includes(p.delta)
      && integerIn(p.code, CONFIG.password.min, CONFIG.password.max);
  }
  if (type === 'odd') {
    return integerIn(p.oddIndex, 0, 5)
      && integerIn(p.code, CONFIG.password.min, CONFIG.password.max);
  }
  if (type === 'grille') {
    return integerIn(p.maskId, 0, 3)
      && integerIn(p.code, CONFIG.password.min, CONFIG.password.max);
  }
  return false;
}

/** Finite, exhaustive domains. Generation samples these validated domains only. */
export function* enumerateParams(type) {
  if (type === 'matrix') {
    for (let aDir = 0; aDir <= 2; aDir++) {
      for (const delta of MATRIX_DELTAS) {
        for (let code = 100; code <= 999; code++) {
          yield { aDir, delta, code };
        }
      }
    }
    return;
  }
  if (type === 'odd') {
    for (const oddIndex of ODD_SLOTS) {
      for (let code = 100; code <= 999; code++) {
        yield { oddIndex, code };
      }
    }
    return;
  }
  if (type === 'grille') {
    for (let maskId = 0; maskId <= 3; maskId++) {
      for (let code = 100; code <= 999; code++) {
        yield { maskId, code };
      }
    }
    return;
  }
  throw new RangeError(`Unknown puzzle type: ${type}`);
}

export function solvePuzzle(type, params) {
  if (!isLegalParams(type, params)) throw new RangeError(`Illegal ${type} puzzle parameters`);
  return String(params.code);
}

export function matrixCandidateCodes(targetDir, code) {
  const out = [];
  for (let dir = 0; dir < 4; dir++) {
    if (dir === targetDir) out.push(String(code));
    else {
      const offset = (dir - targetDir + 4) % 4;
      out.push(String(100 + ((code - 100 + offset * 211) % 900)));
    }
  }
  return out;
}

export function oddCandidateCodes(oddIndex, code) {
  const out = [];
  for (let i = 0; i < 6; i++) {
    if (i === oddIndex) out.push(String(code));
    else {
      const offset = (i - oddIndex + 6) % 6;
      out.push(String(100 + ((code - 100 + offset * 137) % 900)));
    }
  }
  return out;
}

export function buildGrilleGrid(maskId, code) {
  const mask = GRILLE_MASKS[maskId];
  const digits = String(code).split('').map(Number);
  const grid = new Array(9);
  for (let cell = 0; cell < 9; cell++) {
    grid[cell] = (code + cell * 3 + maskId) % 10;
  }
  grid[mask.holes[0]] = digits[0];
  grid[mask.holes[1]] = digits[1];
  grid[mask.holes[2]] = digits[2];
  return grid;
}

function renderStampGlyph(cx, cy, r, kind, dir, highlight = false) {
  const rot = dir * 90;
  const stroke = highlight ? '#b33225' : '#2e3836';
  const fill = highlight ? '#b3322518' : 'none';
  const frame = kind === 'circle'
    ? `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${fill}" stroke="${stroke}" stroke-width="${highlight ? 2.2 : 1.6}"/>`
    : `<rect x="${cx - r}" y="${cy - r}" width="${r * 2}" height="${r * 2}" rx="2.5" fill="${fill}" stroke="${stroke}" stroke-width="${highlight ? 2.2 : 1.6}"/>`;
  const pointer = `<g transform="translate(${cx} ${cy}) rotate(${rot})"><path d="M0 ${-r + 3.2} L4.2 ${r - 4.5} L0 ${r - 7.2} L-4.2 ${r - 4.5} Z" fill="${stroke}"/></g>`;
  return frame + pointer;
}

function renderMatrixSvg(params, solved = false) {
  const { aDir, delta, code } = params;
  const bDir = (aDir + delta) % 4;
  const cDir = (aDir + 1) % 4;
  const dDir = (cDir + delta) % 4;
  const codes = matrixCandidateCodes(dDir, code);
  const ruleText = delta === 1 ? '顺转90°' : '翻转180°';
  const cells = [
    renderStampGlyph(44, 24, 14, 'circle', aDir),
    `<path d="M66 24 H88 M84 20 L89 24 L84 28" fill="none" stroke="#5b5341" stroke-width="1.5"/>`,
    solved ? `<text x="77" y="16" text-anchor="middle" font-size="8" fill="#b33225">${ruleText}</text>` : '',
    renderStampGlyph(110, 24, 14, 'circle', bDir),
    renderStampGlyph(44, 60, 14, 'square', cDir),
    `<path d="M66 60 H88 M84 56 L89 60 L84 64" fill="none" stroke="#5b5341" stroke-width="1.5"/>`,
    solved
      ? renderStampGlyph(110, 60, 14, 'square', dDir, true)
      : `<rect x="96" y="46" width="28" height="28" rx="2.5" fill="none" stroke="#7a6f5a" stroke-width="1.5" stroke-dasharray="3 2"/><text x="110" y="65" text-anchor="middle" font-size="14" font-weight="700" fill="#6b5e49">?</text>`,
    `<text x="142" y="30" font-size="9" fill="#5e5646">Ⅰ行：○${DIRS[aDir]}→○${DIRS[bDir]}</text>`,
    `<text x="142" y="46" font-size="9" fill="#5e5646">Ⅱ行：□${DIRS[cDir]}→□${solved ? DIRS[dDir] : '？'}</text>`,
    `<text x="142" y="62" font-size="8.5" fill="${solved ? '#b33225' : '#7b715e'}">${solved ? '已定位：□' + DIRS[dDir] : '按Ⅰ行旋向推导'}</text>`,
    `<line x1="10" y1="81" x2="210" y2="81" stroke="#b3a58a" stroke-width="1"/>`,
  ];
  for (let dir = 0; dir < 4; dir++) {
    const x = 31 + dir * 52;
    const hit = solved && dir === dDir;
    cells.push(
      hit ? `<rect x="${x - 22}" y="85" width="44" height="49" rx="3" fill="#b3322515" stroke="#b33225" stroke-width="1.6"/>` : '',
      renderStampGlyph(x, 101, 10.5, 'square', dir, hit),
      `<text x="${x}" y="128" text-anchor="middle" font-family="ui-monospace,Consolas,monospace" font-size="11" font-weight="${hit ? '700' : '600'}" fill="${hit ? '#b33225' : '#2b3534'}">${codes[dir]}</text>`
    );
  }
  return `<svg viewBox="0 0 220 138" class="cipher-svg" aria-hidden="true">${cells.join('')}</svg>`;
}

function renderOddSvg(params, solved = false) {
  const { oddIndex, code } = params;
  const family = (code + oddIndex) % 3;
  const codes = oddCandidateCodes(oddIndex, code);
  const parts = [];
  for (let i = 0; i < 6; i++) {
    const col = i % 3, row = Math.floor(i / 3);
    const cx = 42 + col * 68, cy = 28 + row * 64;
    const isOdd = i === oddIndex;
    const hit = solved && isOdd;
    const stroke = hit ? '#b33225' : '#2e3836';
    if (hit) {
      parts.push(`<rect x="${cx - 28}" y="${cy - 22}" width="56" height="58" rx="4" fill="#b3322515" stroke="#b33225" stroke-width="1.6"/>`);
    }
    parts.push(`<text x="${cx - 23}" y="${cy - 8}" font-size="9" fill="#6d6350">${ODD_LABELS[i]}</text>`);
    if (family === 0) {
      // Closed ring + twin rivets vs broken ring + single rivet
      if (!isOdd) {
        parts.push(
          `<circle cx="${cx}" cy="${cy}" r="13" fill="none" stroke="${stroke}" stroke-width="1.7"/>`,
          `<circle cx="${cx - 4.5}" cy="${cy}" r="2.3" fill="${stroke}"/>`,
          `<circle cx="${cx + 4.5}" cy="${cy}" r="2.3" fill="${stroke}"/>`
        );
      } else {
        parts.push(
          `<circle cx="${cx}" cy="${cy}" r="13" fill="none" stroke="${stroke}" stroke-width="1.7" stroke-dasharray="56 18" stroke-dashoffset="8"/>`,
          `<circle cx="${cx}" cy="${cy}" r="2.8" fill="${stroke}"/>`
        );
      }
    } else if (family === 1) {
      // Upright triangle in closed circle vs inverted triangle in broken circle
      if (!isOdd) {
        parts.push(
          `<circle cx="${cx}" cy="${cy}" r="13" fill="none" stroke="${stroke}" stroke-width="1.7"/>`,
          `<path d="M${cx} ${cy - 7} L${cx + 6.5} ${cy + 5} L${cx - 6.5} ${cy + 5} Z" fill="${stroke}"/>`
        );
      } else {
        parts.push(
          `<circle cx="${cx}" cy="${cy}" r="13" fill="none" stroke="${stroke}" stroke-width="1.7" stroke-dasharray="56 18"/>`,
          `<path d="M${cx} ${cy + 7} L${cx + 6.5} ${cy - 5} L${cx - 6.5} ${cy - 5} Z" fill="${stroke}"/>`
        );
      }
    } else {
      // Symmetric cross in box vs diagonal slash in notched box
      if (!isOdd) {
        parts.push(
          `<rect x="${cx - 12}" y="${cy - 12}" width="24" height="24" rx="2.5" fill="none" stroke="${stroke}" stroke-width="1.7"/>`,
          `<path d="M${cx - 7} ${cy} H${cx + 7} M${cx} ${cy - 7} V${cy + 7}" stroke="${stroke}" stroke-width="2"/>`
        );
      } else {
        parts.push(
          `<rect x="${cx - 12}" y="${cy - 12}" width="24" height="24" rx="2.5" fill="none" stroke="${stroke}" stroke-width="1.7" stroke-dasharray="68 16"/>`,
          `<path d="M${cx - 7} ${cy - 7} L${cx + 7} ${cy + 7}" stroke="${stroke}" stroke-width="2.2"/>`
        );
      }
    }
    parts.push(
      `<text x="${cx}" y="${cy + 27}" text-anchor="middle" font-family="ui-monospace,Consolas,monospace" font-size="11" font-weight="${hit ? '700' : '600'}" fill="${hit ? '#b33225' : '#2b3534'}">${codes[i]}</text>`
    );
  }
  return `<svg viewBox="0 0 220 138" class="cipher-svg" aria-hidden="true">${parts.join('')}</svg>`;
}

function renderGrilleSvg(params, solved = false) {
  const { maskId, code } = params;
  const mask = GRILLE_MASKS[maskId];
  const grid = buildGrilleGrid(maskId, code);
  const parts = [
    `<text x="48" y="13" text-anchor="middle" font-size="8.5" fill="#5e5646">底盘 (顶缺口▲)</text>`,
    `<path d="M44 16 L48 22 L52 16 Z" fill="#b33225"/>`,
    `<rect x="12" y="22" width="72" height="72" fill="#e8dcc2" stroke="#474134" stroke-width="1.5"/>`,
    `<text x="164" y="13" text-anchor="middle" font-size="8.5" fill="#5e5646">掩模 (${mask.rot === 0 ? '正置▲' : '倒置▼转180°'})</text>`,
    `<rect x="128" y="22" width="72" height="72" fill="#cfc2a6" stroke="#474134" stroke-width="1.5"/>`,
    mask.rot === 0
      ? `<path d="M160 16 L164 22 L168 16 Z" fill="#b33225"/>`
      : `<path d="M160 100 L164 94 L168 100 Z" fill="#b33225"/>`,
    `<path d="M122 58 H90 M95 54 L89 58 L95 62" fill="none" stroke="#6d624e" stroke-width="1.4"/>`,
    `<text x="106" y="50" text-anchor="middle" font-size="8" fill="#6d624e">${mask.rot === 0 ? '对▲直套' : '转180°对▲'}</text>`,
  ];
  for (let i = 0; i < 9; i++) {
    const r = Math.floor(i / 3), c = i % 3;
    const gx = 12 + c * 24, gy = 22 + r * 24;
    const holeOrder = mask.holes.indexOf(i);
    const hit = solved && holeOrder >= 0;
    parts.push(
      `<rect x="${gx}" y="${gy}" width="24" height="24" fill="${hit ? '#b3322522' : 'none'}" stroke="${hit ? '#b33225' : '#8b7f68'}" stroke-width="${hit ? '1.6' : '0.8'}"/>`,
      `<text x="${gx + 12}" y="${gy + 16}" text-anchor="middle" font-family="ui-monospace,Consolas,monospace" font-size="12" font-weight="700" fill="${hit ? '#b33225' : '#2b3534'}">${grid[i]}</text>`
    );
    if (hit) {
      parts.push(`<text x="${gx + 4}" y="${gy + 8}" font-size="7" font-weight="700" fill="#b33225">${holeOrder + 1}</text>`);
    }
  }
  // Right stencil: show holes in printed orientation (if rot===180, printed cell is 8 - trueHole)
  for (let i = 0; i < 9; i++) {
    const r = Math.floor(i / 3), c = i % 3;
    const mx = 128 + c * 24, my = 22 + r * 24;
    const alignedCell = mask.rot === 180 ? 8 - i : i;
    const holeOrder = mask.holes.indexOf(alignedCell);
    const isHole = holeOrder >= 0;
    parts.push(
      `<rect x="${mx}" y="${my}" width="24" height="24" fill="${isHole ? '#fbf5e6' : '#bfb193'}" stroke="#6e634e" stroke-width="0.9"/>`
    );
    if (isHole) {
      parts.push(
        `<circle cx="${mx + 12}" cy="${my + 12}" r="8.5" fill="none" stroke="#b33225" stroke-width="1.3"/>`,
        `<text x="${mx + 12}" y="${my + 15.5}" text-anchor="middle" font-size="10" font-weight="700" fill="#b33225">${['①', '②', '③'][holeOrder]}</text>`
      );
    }
  }
  const footText = solved
    ? `已对齐缺口▲：孔①＝${grid[mask.holes[0]]}，孔②＝${grid[mask.holes[1]]}，孔③＝${grid[mask.holes[2]]} → ${code}`
    : `将掩模红缺口与底盘顶缺口▲对齐，按①→②→③读数`;
  parts.push(`<text x="110" y="122" text-anchor="middle" font-size="9" font-weight="${solved ? '700' : '500'}" fill="${solved ? '#b33225' : '#524a3b'}">${footText}</text>`);
  return `<svg viewBox="0 0 220 138" class="cipher-svg" aria-hidden="true">${parts.join('')}</svg>`;
}

export function createPuzzle(type, params) {
  const definition = PUZZLE_TYPES.find(p => p.id === type);
  const answer = solvePuzzle(type, params);
  let memo, svg, solvedSvg;
  if (type === 'matrix') {
    const bDir = (params.aDir + params.delta) % 4;
    const cDir = (params.aDir + 1) % 4;
    const dDir = (cDir + params.delta) % 4;
    const codes = matrixCandidateCodes(dDir, params.code);
    const legend = DIRS.map((sym, i) => `□${sym}＝${codes[i]}`).join('，');
    memo = `图推矩阵：第一行 ○${DIRS[params.aDir]} → ○${DIRS[bDir]}；第二行 □${DIRS[cDir]} → ？。\n印章对照：${legend}。\n按第一行旋向规律补齐“？”，门上记对应三位钢印号。`;
    svg = renderMatrixSvg(params, false);
    solvedSvg = renderMatrixSvg(params, true);
  } else if (type === 'odd') {
    const codes = oddCandidateCodes(params.oddIndex, params.code);
    const family = (params.code + params.oddIndex) % 3;
    const normalTag = ['闭环双铆', '闭环正标▲', '闭框十字'][family];
    const oddTag = ['断口单铆', '断口倒标▼', '缺框斜杠'][family];
    const items = ODD_LABELS.map((label, i) => `${label}[${i === params.oddIndex ? oddTag : normalTag}]＝${codes[i]}`).join('，');
    memo = `质检排异：${items}。\n六枚印章中五枚同制、一枚异制；找出唯一异类印章，门上记其三位批号。`;
    svg = renderOddSvg(params, false);
    solvedSvg = renderOddSvg(params, true);
  } else {
    const mask = GRILLE_MASKS[params.maskId];
    const grid = buildGrilleGrid(params.maskId, params.code);
    const rows = [
      grid.slice(0, 3).join(' '),
      grid.slice(3, 6).join(' '),
      grid.slice(6, 9).join(' '),
    ].join(' / ');
    const printedHoles = mask.holes.map(h => (mask.rot === 180 ? 8 - h : h) + 1);
    memo = `转格底盘（▲在顶边）：[${rows}]。\n掩模缺口：${mask.notch}；盘面孔位：①＝格${printedHoles[0]}，②＝格${printedHoles[1]}，③＝格${printedHoles[2]}。\n将掩模缺口转至顶边▲对齐，按①→②→③直读三位密码。`;
    svg = renderGrilleSvg(params, false);
    solvedSvg = renderGrilleSvg(params, true);
  }
  return Object.freeze({
    type,
    title: definition.title,
    params: structuredClone(params),
    answer,
    memo,
    svg,
    solvedSvg,
    help: definition.help,
    recognition: definition.recognition,
    manualPage: definition.manualPage,
  });
}

/** Reservoir sampling avoids retaining thousands of parameter objects in the UI. */
export function generatePuzzle(seed, { type, params } = {}) {
  const rng = createRng(`${seed}:puzzle`);
  const chosenType = type ?? PUZZLE_TYPES[Math.floor(rng() * PUZZLE_TYPES.length)].id;
  if (params !== undefined) return createPuzzle(chosenType, params);
  let chosen;
  let count = 0;
  for (const candidate of enumerateParams(chosenType)) {
    count++;
    if (rng() < 1 / count) chosen = candidate;
  }
  if (!chosen) throw new RangeError(`No legal puzzle parameters for ${chosenType}`);
  return createPuzzle(chosenType, chosen);
}
