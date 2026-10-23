'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');

function matchingBrace(text, opening) {
    let depth = 1, quote = '', line = false, block = false;
    for (let i = opening + 1; i < text.length; i++) {
        const c = text[i], next = text[i + 1];
        if (line) { if (c === '\n') line = false; continue; }
        if (block) { if (c === '*' && next === '/') { block = false; i++; } continue; }
        if (quote) {
            if (c === '\\') { i++; continue; }
            if (c === quote) quote = '';
            continue;
        }
        if (c === '/' && next === '/') { line = true; i++; continue; }
        if (c === '/' && next === '*') { block = true; i++; continue; }
        if (c === '"' || c === "'") { quote = c; continue; }
        if (c === '{') depth++;
        if (c === '}' && --depth === 0) return i;
    }
    throw new Error('Unclosed source function');
}

// Only declarations have their types erased. In particular, ': Number(x)' in a
// ternary expression must remain intact. Strings/comments are kept byte-for-byte.
function eraseTypes(source) {
    const chunks = source.match(/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^/"']+|\//g) || [];
    return chunks.map(chunk => {
        if (/^(?:\/\*|\/\/|"|')/.test(chunk)) return chunk;
        return chunk.replace(/(\bvar\s+[\w$\u0080-\uffff]+)\s*:\s*[\w.$\u0080-\uffff]+/g, '$1')
            .replace(/(\bfunction(?:\s+[\w$\u0080-\uffff]+)?\s*\()([^)]*)(\))\s*(?::\s*[\w.$\u0080-\uffff]+)?/g,
                (all, start, params, end) => start + params.replace(/:\s*[\w.$\u0080-\uffff]+/g, '') + end);
    }).join('');
}

function createSource(root) {
    const evidence = [];
    function read(relativePath) {
        const bytes = fs.readFileSync(path.resolve(root, relativePath));
        return {text:bytes.toString('utf8').replace(/^\uFEFF/, ''),
            hash:crypto.createHash('sha256').update(bytes).digest('hex')};
    }
    function extract(relativePath, marker, last = false) {
        const source = read(relativePath);
        const markers = Array.isArray(marker) ? marker : [marker];
        let position = last ? source.text.lastIndexOf(markers[0]) : source.text.indexOf(markers[0]);
        for (const next of markers.slice(1)) position = source.text.indexOf(next, position + 1);
        if (position < 0) throw new Error('Source marker missing: ' + relativePath + ' / ' + marker);
        const start = source.text.indexOf('function', position);
        const opening = source.text.indexOf('{', start);
        const end = matchingBrace(source.text, opening) + 1;
        evidence.push({path:relativePath, marker, sha256:source.hash,
            firstLine:source.text.slice(0, start).split('\n').length,
            lastLine:source.text.slice(0, end).split('\n').length});
        let body = source.text.slice(start, end).replace(/^function\s+[^\s(]+\s*\(/, 'function(');
        return eraseTypes(body);
    }
    function fn(relativePath, marker, globals = {}, last = false) {
        return vm.runInNewContext('(' + extract(relativePath, marker, last) + ')', globals,
            {filename:relativePath, timeout:3000});
    }
    function methods(relativePath, names, globals = {}) {
        const declarations = names.map(name => 'var ' + name + ' = ' + extract(relativePath,
            'function ' + name + '(') + ';').join('\n');
        return vm.runInNewContext('(function(){\n' + declarations + '\nreturn {' +
            names.map(name => name + ':' + name).join(',') + '};\n})()', globals,
            {filename:relativePath, timeout:3000});
    }
    return {read, extract, fn, methods, evidence};
}

module.exports = {createSource, eraseTypes, matchingBrace};
