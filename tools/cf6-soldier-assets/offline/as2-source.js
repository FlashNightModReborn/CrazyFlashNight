'use strict';
// Narrow source-body runner. It does not emulate MovieClip, AVM1 or Flash APIs.
const fs = require('node:fs');
const vm = require('node:vm');

function functionBody(source, name) {
  const marker = new RegExp('^' + name + '=function\\(', 'm').exec(source);
  if (!marker) throw new Error('Missing source function: ' + name);
  const start = source.indexOf('function', marker.index);
  const open = source.indexOf('{', start);
  let depth = 0, mode = 'code', quote = '';
  for (let i = open; i < source.length; i++) {
    const c = source[i], n = source[i + 1];
    if (mode === 'line') { if (c === '\n') mode = 'code'; continue; }
    if (mode === 'block') { if (c === '*' && n === '/') { mode = 'code'; i++; } continue; }
    if (mode === 'string') {
      if (c === '\\') i++;
      else if (c === quote) mode = 'code';
      continue;
    }
    if (c === '/' && n === '/') { mode = 'line'; i++; continue; }
    if (c === '/' && n === '*') { mode = 'block'; i++; continue; }
    if (c === '"' || c === "'") { mode = 'string'; quote = c; continue; }
    if (c === '{') depth++;
    if (c === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw new Error('Unbalanced source function: ' + name);
}

function eraseTypes(source, extraTypes = []) {
  const kinds = ['Number','String','Boolean','Void','MovieClip','Object','Array','Function',...extraTypes];
  for (const kind of kinds) if (!/^[A-Za-z_][A-Za-z_0-9]*$/.test(kind)) throw new Error('Invalid erased type');
  return source.replace(new RegExp('("(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\'|//[^\\n]*|/\\*[\\s\\S]*?\\*/)|:\\s*(' + kinds.join('|') + ')\\b(?!\\s*\\()', 'g'),
    (whole, literal) => literal || '');
}

function loadFunctions(context, path, names) {
  const source = fs.readFileSync(path, 'utf8');
  for (const name of names) vm.runInContext(name + '=' + eraseTypes(functionBody(source, name)), context, { filename: path });
}

function loadStaticClass(context, path, className, extraTypes = []) {
  const source = fs.readFileSync(path, 'utf8').replace(/\b(?:public|private)\s+static\s+function\s+(\w+)\s*\(/g,
    (_, name) => '\n' + name + '=function(');
  const names = [...source.matchAll(/^(\w+)=function\(/gm)].map(x => x[1]);
  if (!names.length) throw new Error('No static source methods: ' + path);
  const fields = [...source.matchAll(/(?:public|private)\s+static\s+var\s+(\w+)\s*:\s*\w+\s*(?:=\s*([^;]+))?;/g)];
  const declarations = names.map(name => 'var ' + name + ';').join('\n') + '\n' +
    fields.map(row => 'var ' + row[1] + '=' + (row[2] || 'undefined') + ';').join('\n');
  const definitions = names.map(name => name + '=' + eraseTypes(functionBody(source,name), extraTypes) + ';').join('\n');
  vm.runInContext(className + '=(function(){\n' + declarations + '\n' + definitions + '\nvar api={' +
    names.map(name => name + ':' + name).join(',') + '};\n' +
    fields.map(row => 'Object.defineProperty(api,"'+row[1]+'",{get:function(){return '+row[1]+';},set:function(v){'+row[1]+'=v;}});').join('\n') +
    '\nreturn api;})()', context, { filename:path });
  return context[className];
}

module.exports = { functionBody, eraseTypes, loadFunctions, loadStaticClass };
