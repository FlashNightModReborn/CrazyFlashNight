#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const dictPath = path.join(root, 'data', 'dictionaries', 'information_dictionary.xml');
const h5Dir = path.join(root, 'data', 'intelligence_h5');

const BLOCK_TYPES = new Set([
  'paragraph',
  'heading',
  'list',
  'table',
  'quote',
  'divider',
  'stamp',
  'note',
  'handwritten',
  'annotation',
  'terminalLog',
  'redaction',
  'decryptBlock',
  'blueprint',
  'timeline',
  'hardwareExtract',
  'surfaceMark',
  'paperFragment',
  'paperStage',
]);

const INLINE_TYPES = new Set([
  'text',
  'strong',
  'underline',
  'colorToken',
  'damageText',
  'redaction',
  'decryptText',
  'pcName',
]);

const COLOR_TOKENS = new Set([
  'danger',
  'warning',
  'info',
  'success',
  'muted',
  'material-basic',
  'material-mid',
  'material-high',
  'material-rare',
  'biohazard',
  'faction-army',
  'faction-noah',
  'faction-blackiron',
  'faction-university',
]);

const SURFACE_VARIANTS = new Set([
  'dirt',
  'water',
  'blood-hand',
  'fold',
  'tear',
]);

const DAMAGE_KINDS = new Set([
  'data-loss',
  'smear',
  'deleted',
  'missing',
  'blurred',
  'edited',
]);

const MASK_STYLES = new Set([
  'block',
  'bar',
  'garble',
  'mojibake',
  'symbol',
]);

const SKINS = new Set([
  'paper',
  'report',
  'dossier',
  'terminal',
  'newspaper',
  'blueprint',
  'diary',
  'edict',
  'field-notes',
]);

const FRAGMENT_TONES = new Set([
  'aged',
  'burnt',
  'torn',
  'ink',
  'carbon',
]);

const FRAGMENT_PINS = new Set([
  'none',
  'pushpin',
  'tape',
  'clip',
]);

const STAGE_LAYOUTS = new Set([
  'stack',
  'scatter',
]);

function read(filePath) {
  return fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
}

function parseArgs(argv) {
  const args = { strict: false, allowMissing: false };
  for (const arg of argv) {
    if (arg === '--strict') args.strict = true;
    else if (arg === '--allow-missing') args.allowMissing = true;
    else if (arg === '--help' || arg === '-h') {
      console.log('usage: node tools/validate-intelligence-h5.js [--allow-missing|--strict]');
      process.exit(0);
    } else {
      fail([`unknown arg: ${arg}`]);
    }
  }
  if (!args.strict && !args.allowMissing) args.allowMissing = true;
  return args;
}

function parseDictionary() {
  const xml = read(dictPath);
  const items = [];
  for (const match of xml.matchAll(/<Item>([\s\S]*?)<\/Item>/g)) {
    const body = match[1];
    const name = (body.match(/<Name>([\s\S]*?)<\/Name>/) || [])[1]?.trim();
    if (!name) continue;
    const index = Number((body.match(/<Index>(\d+)<\/Index>/) || [])[1] || 0);
    const pages = [];
    for (const info of body.matchAll(/<Information\s+([^/>]+?)\s*\/>/g)) {
      const attrs = {};
      info[1].replace(/([\w:-]+)\s*=\s*"([^"]*)"/g, (_, key, value) => {
        attrs[key] = value;
        return '';
      });
      if (attrs.PageKey) pages.push(attrs.PageKey);
    }
    items.push({ name, index, pages });
  }
  items.sort((a, b) => a.index - b.index || a.name.localeCompare(b.name, 'zh-Hans-CN'));
  return items;
}

function jsonPathFor(itemName) {
  const full = path.resolve(h5Dir, `${itemName}.json`);
  const rootWithSep = path.resolve(h5Dir) + path.sep;
  if (!full.startsWith(rootWithSep)) throw new Error(`invalid item path: ${itemName}`);
  return full;
}

function validateDocument(filePath, item, errors) {
  let doc;
  try {
    doc = JSON.parse(read(filePath));
  } catch (error) {
    errors.push(`${item.name}: invalid JSON: ${error.message}`);
    return;
  }
  const ctx = item.name;
  if (doc.schemaVersion !== 1) errors.push(`${ctx}: schemaVersion must be 1`);
  if (doc.itemName !== item.name) errors.push(`${ctx}: itemName mismatch (${doc.itemName})`);
  if (!SKINS.has(doc.skin)) errors.push(`${ctx}: unknown skin "${doc.skin}"`);
  if (!Array.isArray(doc.pages)) {
    errors.push(`${ctx}: pages must be an array`);
    return;
  }
  const jsonKeys = doc.pages.map((page) => page && page.pageKey);
  if (jsonKeys.length !== item.pages.length || jsonKeys.some((key, index) => key !== item.pages[index])) {
    errors.push(`${ctx}: PageKey mismatch. dictionary=[${item.pages.join(',')}] json=[${jsonKeys.join(',')}]`);
  }
  doc.pages.forEach((page, index) => {
    const loc = `${ctx} page ${page && page.pageKey || index}`;
    if (!page || typeof page !== 'object') {
      errors.push(`${loc}: page must be an object`);
      return;
    }
    if (!Array.isArray(page.blocks)) {
      errors.push(`${loc}: blocks must be an array`);
      return;
    }
    page.blocks.forEach((block, blockIndex) => validateBlock(block, `${loc} block ${blockIndex}`, errors));
  });
  scanUnsafe(doc, ctx, errors);
}

function validateBlock(block, loc, errors) {
  if (!block || typeof block !== 'object' || Array.isArray(block)) {
    errors.push(`${loc}: block must be an object`);
    return;
  }
  if (!BLOCK_TYPES.has(block.type)) errors.push(`${loc}: unknown block type "${block.type}"`);
  if (block.type === 'heading') {
    const level = Number(block.level || 2);
    if (level < 1 || level > 4) errors.push(`${loc}: heading level must be 1-4`);
  }
  if (block.type === 'colorToken' && block.token && !COLOR_TOKENS.has(block.token)) {
    errors.push(`${loc}: unknown color token "${block.token}"`);
  }
  if (block.type === 'surfaceMark' && block.variant && !SURFACE_VARIANTS.has(block.variant)) {
    errors.push(`${loc}: unknown surface variant "${block.variant}"`);
  }
  if (block.type === 'paperFragment') {
    const tone = block.tone || 'aged';
    if (!FRAGMENT_TONES.has(tone)) errors.push(`${loc}: unknown fragment tone "${tone}"`);
    const pin = block.pin || 'none';
    if (!FRAGMENT_PINS.has(pin)) errors.push(`${loc}: unknown fragment pin "${pin}"`);
  }
  if (block.type === 'paperStage') {
    const layout = block.layout || 'stack';
    if (!STAGE_LAYOUTS.has(layout)) errors.push(`${loc}: unknown stage layout "${layout}"`);
  }
  ['content', 'title', 'caption', 'label', 'note'].forEach((key) => {
    if (Array.isArray(block[key])) validateInlineArray(block[key], `${loc}.${key}`, errors);
  });
  if (Array.isArray(block.items)) {
    block.items.forEach((item, index) => {
      if (Array.isArray(item)) validateInlineArray(item, `${loc}.items[${index}]`, errors);
      else if (item && Array.isArray(item.content)) validateInlineArray(item.content, `${loc}.items[${index}].content`, errors);
      else if (item && typeof item === 'object' && item.type) validateBlock(item, `${loc}.items[${index}]`, errors);
      else if (typeof item !== 'string') errors.push(`${loc}.items[${index}]: item must be inline array, block, or string`);
    });
  }
  if (Array.isArray(block.blocks)) block.blocks.forEach((child, index) => validateBlock(child, `${loc}.blocks[${index}]`, errors));
  if (Array.isArray(block.reveal)) block.reveal.forEach((child, index) => validateBlock(child, `${loc}.reveal[${index}]`, errors));
  if (Array.isArray(block.plain)) block.plain.forEach((child, index) => validateBlock(child, `${loc}.plain[${index}]`, errors));
  if (Array.isArray(block.encrypted)) block.encrypted.forEach((child, index) => validateBlock(child, `${loc}.encrypted[${index}]`, errors));
  if (Array.isArray(block.fragments)) block.fragments.forEach((child, index) => validateBlock(child, `${loc}.fragments[${index}]`, errors));
  if (Array.isArray(block.entries)) {
    block.entries.forEach((entry, index) => {
      if (entry && Array.isArray(entry.content)) validateInlineArray(entry.content, `${loc}.entries[${index}].content`, errors);
      if (entry && Array.isArray(entry.blocks)) entry.blocks.forEach((child, childIndex) => validateBlock(child, `${loc}.entries[${index}].blocks[${childIndex}]`, errors));
    });
  }
  if (Array.isArray(block.rows)) {
    block.rows.forEach((row, rowIndex) => {
      if (!Array.isArray(row)) {
        errors.push(`${loc}.rows[${rowIndex}]: row must be an array`);
        return;
      }
      row.forEach((cell, cellIndex) => {
        if (Array.isArray(cell)) validateInlineArray(cell, `${loc}.rows[${rowIndex}][${cellIndex}]`, errors);
        else if (typeof cell !== 'string' && typeof cell !== 'number') errors.push(`${loc}.rows[${rowIndex}][${cellIndex}]: invalid cell`);
      });
    });
  }
  if (Array.isArray(block.steps)) {
    block.steps.forEach((step, index) => {
      if (step && Array.isArray(step.content)) validateInlineArray(step.content, `${loc}.steps[${index}].content`, errors);
      else if (typeof step !== 'string') errors.push(`${loc}.steps[${index}]: step must be string or content object`);
    });
  }
}

function validateInlineArray(nodes, loc, errors) {
  nodes.forEach((node, index) => validateInline(node, `${loc}[${index}]`, errors));
}

function validateInline(node, loc, errors) {
  if (typeof node === 'string') return;
  if (!node || typeof node !== 'object' || Array.isArray(node)) {
    errors.push(`${loc}: inline token must be string or object`);
    return;
  }
  if (!INLINE_TYPES.has(node.type)) errors.push(`${loc}: unknown inline token "${node.type}"`);
  if (node.type === 'colorToken' && !COLOR_TOKENS.has(node.token)) errors.push(`${loc}: unknown color token "${node.token}"`);
  if (node.type === 'damageText' && node.kind && !DAMAGE_KINDS.has(node.kind)) errors.push(`${loc}: unknown damage kind "${node.kind}"`);
  if ((node.type === 'decryptText' || node.type === 'redaction') && node.mask && !MASK_STYLES.has(node.mask)) {
    errors.push(`${loc}: unknown mask style "${node.mask}"`);
  }
  if (Array.isArray(node.content)) validateInlineArray(node.content, `${loc}.content`, errors);
  if (Array.isArray(node.reveal)) validateInlineArray(node.reveal, `${loc}.reveal`, errors);
}

function scanUnsafe(value, loc, errors) {
  if (typeof value === 'string') {
    if (/<\s*script/i.test(value) || /\bon[a-z]+\s*=/i.test(value) || /javascript\s*:/i.test(value)) {
      errors.push(`${loc}: unsafe string content`);
    }
    return;
  }
  if (!value || typeof value !== 'object') return;
  if (Array.isArray(value)) {
    value.forEach((item, index) => scanUnsafe(item, `${loc}[${index}]`, errors));
    return;
  }
  Object.keys(value).forEach((key) => {
    if (/^on/i.test(key) || key === 'script' || key === 'html' || key === 'innerHTML') {
      errors.push(`${loc}: unsafe key "${key}"`);
    }
    scanUnsafe(value[key], `${loc}.${key}`, errors);
  });
}

function fail(errors) {
  errors.forEach((error) => console.error('[intelligence-h5] ' + error));
  process.exit(1);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const items = parseDictionary();
  const errors = [];
  let validated = 0;
  items.forEach((item) => {
    let filePath;
    try {
      filePath = jsonPathFor(item.name);
    } catch (error) {
      errors.push(`${item.name}: ${error.message}`);
      return;
    }
    if (!fs.existsSync(filePath)) {
      if (args.strict) errors.push(`${item.name}: missing ${path.relative(root, filePath)}`);
      return;
    }
    validated += 1;
    validateDocument(filePath, item, errors);
  });
  if (args.strict && validated !== items.length) {
    errors.push(`strict requires all items: validated ${validated}/${items.length}`);
  }
  if (errors.length) fail(errors);
  console.log(`[intelligence-h5] OK: validated ${validated}/${items.length} files (${args.strict ? 'strict' : 'allow-missing'})`);
}

main();
