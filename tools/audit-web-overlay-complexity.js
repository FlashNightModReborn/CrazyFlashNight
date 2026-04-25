#!/usr/bin/env node
/*
 * Static Web overlay complexity audit.
 *
 * This tool intentionally does not launch WebView2 or a browser. It scans the
 * overlay CSS/JS sources for compositor-heavy features and high-frequency
 * layout/render triggers so performance work can start from stable evidence.
 */

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');

function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}

function count(text, pattern) {
  const m = text.match(pattern);
  return m ? m.length : 0;
}

function lineRefs(text, pattern, limit) {
  const lines = text.split(/\r?\n/);
  const refs = [];
  for (let i = 0; i < lines.length; i += 1) {
    if (pattern.test(lines[i])) {
      refs.push({ line: i + 1, text: lines[i].trim() });
      if (refs.length >= limit) break;
    }
  }
  return refs;
}

function cssMetrics(rel, sectionStart) {
  const full = read(rel);
  const text = sectionStart ? full.slice(Math.max(0, full.indexOf(sectionStart))) : full;
  return {
    file: rel,
    scopedFrom: sectionStart || null,
    bytes: Buffer.byteLength(text, 'utf8'),
    lines: text.split(/\r?\n/).length,
    rulesApprox: count(text, /[{]/g) - count(text, /@keyframes\b/g),
    keyframes: count(text, /@keyframes\b/g),
    animationDecls: count(text, /(^|[;{\s])animation\s*:/gm),
    transitionDecls: count(text, /(^|[;{\s])transition\s*:/gm),
    filterDecls: count(text, /(^|[;{\s])filter\s*:/gm),
    backdropFilterDecls: count(text, /backdrop-filter\s*:/g),
    dropShadowUses: count(text, /drop-shadow\(/g),
    boxShadowDecls: count(text, /box-shadow\s*:/g),
    mixBlendModeDecls: count(text, /mix-blend-mode\s*:/g),
    clipPathDecls: count(text, /clip-path\s*:/g),
    willChangeDecls: count(text, /will-change\s*:/g),
    insetZeroDecls: count(text, /inset\s*:\s*0\b/g),
    mapSelectorsApprox: count(text, /\.map-/g),
    minigameSelectorsApprox: count(text, /\.(lockbox|pinalign|gobang)-/g),
    sampleHeavyLines: lineRefs(
      text,
      /\b(animation|filter|backdrop-filter|mix-blend-mode|clip-path|will-change)\s*:|drop-shadow\(/,
      14
    )
  };
}

function jsMetrics(rel) {
  const text = read(rel);
  return {
    file: rel,
    bytes: Buffer.byteLength(text, 'utf8'),
    lines: text.split(/\r?\n/).length,
    requestAnimationFrame: count(text, /requestAnimationFrame/g),
    setInterval: count(text, /setInterval/g),
    setTimeout: count(text, /setTimeout/g),
    resizeObserver: count(text, /ResizeObserver/g),
    getBoundingClientRect: count(text, /getBoundingClientRect/g),
    getComputedStyle: count(text, /getComputedStyle/g),
    querySelectorAll: count(text, /querySelectorAll/g),
    createElement: count(text, /createElement/g),
    innerHTMLWrites: count(text, /\.innerHTML\s*=/g),
    addEventListener: count(text, /addEventListener/g),
    canvasContext: count(text, /getContext\s*\(/g),
    drawImage: count(text, /drawImage\s*\(/g),
    renderFunctionsApprox: count(text, /function\s+render[A-Z0-9_]/g),
    sampleLayoutLines: lineRefs(
      text,
      /requestAnimationFrame|ResizeObserver|getBoundingClientRect|getComputedStyle|querySelectorAll|innerHTML\s*=/,
      14
    )
  };
}

function sumCss(items) {
  const keys = [
    'bytes', 'lines', 'rulesApprox', 'keyframes', 'animationDecls', 'transitionDecls',
    'filterDecls', 'backdropFilterDecls', 'dropShadowUses', 'boxShadowDecls',
    'mixBlendModeDecls', 'clipPathDecls', 'willChangeDecls', 'insetZeroDecls',
    'mapSelectorsApprox', 'minigameSelectorsApprox'
  ];
  const out = {};
  for (const key of keys) out[key] = items.reduce((acc, item) => acc + (item[key] || 0), 0);
  return out;
}

function sumJs(items) {
  const keys = [
    'bytes', 'lines', 'requestAnimationFrame', 'setInterval', 'setTimeout',
    'resizeObserver', 'getBoundingClientRect', 'getComputedStyle', 'querySelectorAll',
    'createElement', 'innerHTMLWrites', 'addEventListener', 'canvasContext',
    'drawImage', 'renderFunctionsApprox'
  ];
  const out = {};
  for (const key of keys) out[key] = items.reduce((acc, item) => acc + (item[key] || 0), 0);
  return out;
}

const cssFiles = [
  'launcher/web/css/overlay.css',
  'launcher/web/css/panels.css',
  'launcher/web/css/welcome.css'
];

const jsFiles = [
  'launcher/web/modules/map-panel.js',
  'launcher/web/modules/map-hud.js',
  'launcher/web/modules/panels.js',
  'launcher/web/modules/notch.js',
  'launcher/web/modules/jukebox.js',
  'launcher/web/modules/sparkline.js',
  'launcher/web/modules/cursor-feedback.js'
];

const css = cssFiles.map(file => cssMetrics(file));
const mapCss = cssMetrics('launcher/web/css/panels.css', 'Map Panel');
const js = jsFiles.map(file => jsMetrics(file));
const mapJs = jsMetrics('launcher/web/modules/map-panel.js');

const report = {
  generatedAt: new Date().toISOString(),
  cssTotal: sumCss(css),
  mapCss,
  jsTotal: sumJs(js),
  mapJs,
  css,
  js
};

if (process.argv.includes('--json')) {
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
} else {
  console.log('[web-overlay-complexity] CSS total');
  console.table([report.cssTotal]);
  console.log('[web-overlay-complexity] Map CSS');
  console.table([{
    lines: mapCss.lines,
    rulesApprox: mapCss.rulesApprox,
    keyframes: mapCss.keyframes,
    animationDecls: mapCss.animationDecls,
    filterDecls: mapCss.filterDecls,
    dropShadowUses: mapCss.dropShadowUses,
    boxShadowDecls: mapCss.boxShadowDecls,
    mixBlendModeDecls: mapCss.mixBlendModeDecls,
    clipPathDecls: mapCss.clipPathDecls,
    willChangeDecls: mapCss.willChangeDecls,
    insetZeroDecls: mapCss.insetZeroDecls,
    mapSelectorsApprox: mapCss.mapSelectorsApprox
  }]);
  console.log('[web-overlay-complexity] JS total');
  console.table([report.jsTotal]);
  console.log('[web-overlay-complexity] Map JS');
  console.table([{
    lines: mapJs.lines,
    requestAnimationFrame: mapJs.requestAnimationFrame,
    resizeObserver: mapJs.resizeObserver,
    getBoundingClientRect: mapJs.getBoundingClientRect,
    getComputedStyle: mapJs.getComputedStyle,
    querySelectorAll: mapJs.querySelectorAll,
    createElement: mapJs.createElement,
    innerHTMLWrites: mapJs.innerHTMLWrites,
    addEventListener: mapJs.addEventListener,
    renderFunctionsApprox: mapJs.renderFunctionsApprox
  }]);
}
