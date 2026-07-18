'use strict';

const fs = require('fs');
const path = require('path');

const IMPORT_STATEMENT_RE = /^[ \t]*@import\b[^;]*;[ \t]*(?:\r?\n|$)/gm;

function parseImport(statement) {
    const body = statement.trim().replace(/^@import\s+/, '').replace(/;$/, '').trim();
    let match = body.match(/^url\(\s*(?:"([^"]+)"|'([^']+)'|([^\s)]+))\s*\)([\s\S]*)$/);
    if (match) return {specifier:match[1] || match[2] || match[3], conditions:match[4].trim()};
    match = body.match(/^(?:"([^"]+)"|'([^']+)')([\s\S]*)$/);
    if (match) return {specifier:match[1] || match[2], conditions:match[3].trim()};
    throw new Error('Unsupported CSS @import syntax: ' + statement.trim());
}

function isInside(rootDir, candidate) {
    const relative = path.relative(rootDir, candidate);
    return relative === '' || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative));
}

function isLocalImport(specifier) {
    return !/^(?:[a-z][a-z0-9+.-]*:|\/\/|\/|#)/i.test(specifier);
}

function resolveCssBundle(entryPath, options) {
    const entry = path.resolve(entryPath);
    const rootDir = path.resolve(options && options.rootDir ? options.rootDir : path.dirname(entry));
    const stack = [];
    const files = [];

    function visit(filePath) {
        const absolute = path.resolve(filePath);
        if (!isInside(rootDir, absolute)) {
            throw new Error('CSS import escapes bundle root: ' + absolute + ' (root: ' + rootDir + ')');
        }
        const pathKey = process.platform === 'win32' ? absolute.toLowerCase() : absolute;
        if (stack.some(item => item.key === pathKey)) {
            throw new Error('CSS import cycle: ' + stack.map(item => item.path).concat([absolute]).join(' -> '));
        }
        if (!fs.existsSync(absolute) || !fs.statSync(absolute).isFile()) {
            throw new Error('CSS import does not exist: ' + absolute);
        }

        stack.push({path:absolute, key:pathKey});
        files.push(absolute);
        const source = fs.readFileSync(absolute, 'utf8');
        const importStatementRe = new RegExp(IMPORT_STATEMENT_RE.source, IMPORT_STATEMENT_RE.flags);
        const css = source.replace(importStatementRe, statement => {
            let parsed;
            try { parsed = parseImport(statement); }
            catch (error) { throw new Error(error.message + ' in ' + absolute); }
            const specifier = parsed.specifier;
            if (!isLocalImport(specifier)) return statement;
            if (parsed.conditions) {
                throw new Error('Conditional local CSS imports cannot be flattened safely in ' + absolute + ': ' + statement.trim());
            }
            if (/[?#]/.test(specifier)) {
                throw new Error('Local CSS imports may not contain query/hash suffixes: ' + specifier);
            }
            return visit(path.resolve(path.dirname(absolute), specifier));
        });
        stack.pop();
        return css;
    }

    return {css:visit(entry), files, entry, rootDir};
}

function readCssBundle(entryPath, options) {
    return resolveCssBundle(entryPath, options).css;
}

module.exports = {readCssBundle, resolveCssBundle};
