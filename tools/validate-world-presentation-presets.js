#!/usr/bin/env node
// Fast authoring gate for the external visual catalog. The Host loader is the
// runtime authority and additionally rejects duplicate JSON keys.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.resolve(__dirname, '..');
const argv = process.argv.slice(2);
let file = path.join(root, 'data/environment/presentation_presets.v1.json');
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--file' && i + 1 < argv.length) file = path.resolve(argv[++i]);
  else if (argv[i] !== '--check') throw Error('Usage: node tools/validate-world-presentation-presets.js [--check] [--file path]');
}
function exact(value, keys, where) {
  if (!value || Array.isArray(value) || typeof value !== 'object') throw Error(where + ': expected object');
  const actual = Object.keys(value).sort(), wanted = [...keys].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) throw Error(where + ': field set mismatch');
}
function number(value, min, max, where) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max)
    throw Error(where + ': out of bounds');
}
function vector(value, length, min, max, where) {
  if (!Array.isArray(value) || value.length !== length) throw Error(where + ': vector length');
  value.forEach((v, i) => number(v, min, max, where + '[' + i + ']'));
}
const raw = fs.readFileSync(file);
const data = JSON.parse(raw.toString('utf8').replace(/^\uFEFF/, ''));
exact(data, ['version', 'atmosphere', 'weather'], 'catalog');
if (data.version !== 1) throw Error('Unsupported catalog version');
if (!Array.isArray(data.atmosphere) || data.atmosphere.length < 1 || data.atmosphere.length > 64)
  throw Error('Atmosphere count outside bounds');
const families = new Set(['alert', 'medical', 'industrial', 'toxic', 'corrosion',
  'cold-iron', 'ambush', 'banquet', 'blood-moon', 'incense']);
const names = new Set();
for (const look of data.atmosphere) {
  exact(look, ['name', 'family', 'primary', 'secondary', 'base', 'edge', 'motion',
    'rate', 'frequency', 'focus', 'falloff', 'mix'], 'atmosphere');
  const name = look.name;
  if (typeof name !== 'string' || !name.trim() || name.length > 48 || /[\x00-\x1f]/.test(name)
    || ['none', 'custom', '雨', '雪', '沙尘'].includes(name) || names.has(name))
    throw Error('Duplicate or invalid atmosphere name: ' + name);
  names.add(name);
  if (!families.has(look.family)) throw Error('Unknown atmosphere family: ' + look.family);
  vector(look.primary, 3, 0, 1, name + '.primary');
  vector(look.secondary, 3, 0, 1, name + '.secondary');
  vector(look.frequency, 2, 0, 16, name + '.frequency');
  vector(look.focus, 2, 0, 1, name + '.focus');
  number(look.base, 0, 0.5, name + '.base');
  number(look.edge, 0, 0.5, name + '.edge');
  number(look.motion, 0, 0.5, name + '.motion');
  number(look.rate, 0, 20, name + '.rate');
  number(look.falloff, 0.05, 2, name + '.falloff');
  number(look.mix, 0, 0.5, name + '.mix');
  if (look.family === 'medical' && look.focus[0] >= look.focus[1])
    throw Error(name + ': medical horizontal color stops reversed');
  if (['toxic', 'corrosion'].includes(look.family) && look.focus[1] >= look.falloff)
    throw Error(name + ': haze falloff reversed');
}
const weatherNames = ['rain', 'snow', 'dust', 'fog', 'slash'];
exact(data.weather, weatherNames, 'weather');
for (const name of weatherNames) {
  const look = data.weather[name];
  exact(look, ['count', 'primary', 'secondary', 'size', 'alpha', 'speed', 'wind',
    'splashSize', 'splashAlpha', 'splashStart', 'edgeFade'], 'weather.' + name);
  if (!Number.isInteger(look.count)) throw Error(name + ': count must be integral');
  number(look.count, 0, 512, name + '.count');
  vector(look.primary, 3, 0, 1, name + '.primary');
  vector(look.secondary, 3, 0, 1, name + '.secondary');
  number(look.size, 0.25, 4, name + '.size');
  number(look.alpha, 0, 2, name + '.alpha');
  number(look.speed, 0.1, 4, name + '.speed');
  number(look.wind, 0, 4, name + '.wind');
  number(look.splashSize, 0.25, 4, name + '.splashSize');
  number(look.splashAlpha, 0, 2, name + '.splashAlpha');
  number(look.splashStart, 0.5, 0.95, name + '.splashStart');
  number(look.edgeFade, 0.1, 4, name + '.edgeFade');
}
let references = 0;
for (const relative of ['data/environment/stage_environment.xml', 'data/environment/scene_environment.xml']) {
  const xml = fs.readFileSync(path.join(root, relative), 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  for (const block of xml.matchAll(/<Environment(?:\s[^>]*)?>[\s\S]*?<\/Environment>/g))
    if (/<Preset>/.test(block[0]) && /<Overlay>/.test(block[0]))
      throw Error(relative + ': a named Preset with Overlay selects custom drawing; define a catalog variant instead');
  for (const match of xml.matchAll(/<Preset>\s*([^<]+?)\s*<\/Preset>/g)) {
    const name = match[1].trim();
    if (['雨', '雪', '沙尘'].includes(name)) continue;
    if (!names.has(name)) throw Error(relative + ': undefined atmosphere preset ' + name);
    references++;
  }
}
console.log('[world-presentation] ok version=1 named=' + names.size + ' weather=' + weatherNames.length
  + ' sceneReferences=' + references + ' sha256=' + crypto.createHash('sha256').update(raw).digest('hex').toUpperCase());
