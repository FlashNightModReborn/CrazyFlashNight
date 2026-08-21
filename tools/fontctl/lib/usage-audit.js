'use strict';

const fs = require('fs');
const path = require('path');
const { diagnostic, sortDiagnostics } = require('./catalog');

const AUDIT_ROOTS = [
    { relative: 'launcher/src', extensions: new Set(['.cs']) },
    { relative: 'launcher/web', extensions: new Set(['.css', '.js', '.html', '.json', '.svg']) },
    { relative: 'config', extensions: new Set(['.json', '.xml']) },
    { relative: 'data/items', extensions: new Set(['.xml']) },
];
const IGNORED_VALUES = new Set([
    'inherit', 'initial', 'unset', 'revert', 'revert-layer', 'caption', 'icon',
    'menu', 'message-box', 'small-caption', 'status-bar',
]);

function globToRegExp(glob) {
    const normalized = glob.replace(/\\/g, '/');
    let expression = '^';
    for (let index = 0; index < normalized.length; index += 1) {
        const character = normalized[index];
        if (character === '*' && normalized[index + 1] === '*') {
            if (normalized[index + 2] === '/') {
                expression += '(?:.*/)?';
                index += 2;
            } else {
                expression += '.*';
                index += 1;
            }
        } else if (character === '*') expression += '[^/]*';
        else if (character === '?') expression += '[^/]';
        else expression += character.replace(/[|\\{}()[\]^$+?.]/g, '\\$&');
    }
    return new RegExp(`${expression}$`, 'i');
}

function buildLineStarts(source) {
    const starts = [0];
    for (let index = 0; index < source.length; index += 1) {
        if (source.charCodeAt(index) === 10) starts.push(index + 1);
    }
    return starts;
}

function lineNumberAt(lineStarts, index) {
    let low = 0;
    let high = lineStarts.length;
    while (low + 1 < high) {
        const middle = (low + high) >>> 1;
        if (lineStarts[middle] <= index) low = middle;
        else high = middle;
    }
    return low + 1;
}

function splitFamilies(value) {
    const result = [];
    let current = '';
    let quote = null;
    let depth = 0;
    for (const character of String(value)) {
        if (quote) {
            current += character;
            if (character === quote) quote = null;
            continue;
        }
        if (character === '"' || character === "'") {
            quote = character;
            current += character;
        } else if (character === '(') {
            depth += 1;
            current += character;
        } else if (character === ')') {
            depth = Math.max(0, depth - 1);
            current += character;
        } else if (character === ',' && depth === 0) {
            result.push(current);
            current = '';
        } else current += character;
    }
    result.push(current);
    return result.map((item) => item
        .replace(/!important\s*$/i, '')
        .trim()
        .replace(/^(['"])(.*)\1$/, '$2')
        .trim())
        .filter((item) => item
            && !IGNORED_VALUES.has(item.toLowerCase())
            && !/^var\(/i.test(item)
            && !/^env\(/i.test(item));
}

function maskComments(source, extension) {
    const output = source.split('');
    const lineComments = extension === '.js' || extension === '.cs';
    const htmlComments = extension === '.html' || extension === '.svg';
    let quote = null;
    let verbatim = false;
    for (let index = 0; index < source.length; index += 1) {
        const character = source[index];
        if (quote) {
            if (verbatim && quote === '"' && character === '"' && source[index + 1] === '"') {
                index += 1;
                continue;
            }
            if (!verbatim && character === '\\') {
                index += 1;
                continue;
            }
            if (character === quote) {
                quote = null;
                verbatim = false;
            }
            continue;
        }
        if (character === '"' || character === "'" || character === '`') {
            quote = character;
            verbatim = character === '"' && index > 0 && source[index - 1] === '@';
            continue;
        }
        let end = -1;
        if (source.startsWith('/*', index)) end = source.indexOf('*/', index + 2);
        else if (htmlComments && source.startsWith('<!--', index)) end = source.indexOf('-->', index + 4);
        if (end >= 0) {
            const closingLength = source.startsWith('<!--', index) ? 3 : 2;
            for (let offset = index; offset < end + closingLength; offset += 1) {
                if (output[offset] !== '\n' && output[offset] !== '\r') output[offset] = ' ';
            }
            index = end + closingLength - 1;
            continue;
        }
        if (lineComments && source.startsWith('//', index)) {
            const lineEnd = source.indexOf('\n', index + 2);
            const stop = lineEnd < 0 ? source.length : lineEnd;
            for (let offset = index; offset < stop; offset += 1) output[offset] = ' ';
            index = stop - 1;
        }
    }
    return output.join('');
}

function extractShorthandFamilies(value) {
    const match = String(value).match(/(?:^|\s)(?:\d*\.?\d+)(?:px|pt|pc|em|rem|%|vh|vw)(?:\s*\/\s*[^\s]+)?\s+(.+)$/i);
    return match ? splitFamilies(match[1]) : [];
}

function enumerateFiles(projectRoot, exclusionMatchers) {
    const files = [];
    function walk(directory, extensions) {
        const entries = fs.readdirSync(directory, { withFileTypes: true })
            .sort((left, right) => left.name.localeCompare(right.name, 'en'));
        for (const entry of entries) {
            const absolute = path.join(directory, entry.name);
            const relative = path.relative(projectRoot, absolute).replace(/\\/g, '/');
            if (exclusionMatchers.some((matcher) => matcher.test(relative))) continue;
            if (entry.isSymbolicLink()) continue;
            if (entry.isDirectory()) walk(absolute, extensions);
            else if (entry.isFile() && extensions.has(path.extname(entry.name).toLowerCase())) files.push({ absolute, relative });
        }
    }
    for (const root of AUDIT_ROOTS) {
        const absolute = path.join(projectRoot, root.relative);
        if (fs.existsSync(absolute) && fs.statSync(absolute).isDirectory()) walk(absolute, root.extensions);
    }
    return files.sort((left, right) => left.relative.localeCompare(right.relative, 'en'));
}

function auditUsage(catalog, maps, projectRoot) {
    const exclusionMatchers = catalog.exclusions.map((item) => globToRegExp(item.glob));
    const files = enumerateFiles(projectRoot, exclusionMatchers);
    const usages = [];
    const diagnostics = [];
    const dynamicSites = [];
    const catalogBoundDynamicSites = [];
    const occurrenceKeys = new Set();
    const lineStartsByFile = new Map();

    function lineFor(file, source, index) {
        let starts = lineStartsByFile.get(file.relative);
        if (!starts) {
            starts = buildLineStarts(source);
            lineStartsByFile.set(file.relative, starts);
        }
        return lineNumberAt(starts, index);
    }

    function recordDynamic(file, source, index, expression) {
        const normalized = String(expression || '').trim().slice(0, 120);
        if (!normalized) return;
        const line = lineFor(file, source, index);
        const key = `${file.relative}\0${line}\0${normalized}`;
        const nearby = source.slice(Math.max(0, index - 900), Math.min(source.length, index + 500));
        const target = /CF7FontCatalog/.test(nearby) ? catalogBoundDynamicSites : dynamicSites;
        if (target.some((item) => `${item.file}\0${item.line}\0${item.expression}` === key)) return;
        target.push({ file: file.relative, line, expression: normalized, binding: target === catalogBoundDynamicSites ? 'catalog-role' : null });
    }

    function record(file, source, index, family, kind) {
        const normalized = String(family || '')
            .replace(/\\(["'])/g, '$1')
            .trim()
            .replace(/^[\s'"`]+|[\s'"`,);]+$/g, '')
            .trim();
        if (!normalized
            || /^[-\d.]+$/.test(normalized)
            || /^[-+]?\d*\.?\d+(?:px|pt|pc|em|rem|%|vh|vw|ch|ex)$/i.test(normalized)
            || /^(?:calc|min|max|clamp|var|env)\(/i.test(normalized)
            || /(?:\+|\$\{|=>)/.test(normalized)) return;
        const line = lineFor(file, source, index);
        const key = `${file.relative}\0${line}\0${normalized.toLocaleLowerCase('en-US')}\0${kind}`;
        if (occurrenceKeys.has(key)) return;
        occurrenceKeys.add(key);
        const registered = maps.familyLookup.get(normalized.toLocaleLowerCase('en-US')) || null;
        usages.push({
            file: file.relative,
            line,
            family: normalized,
            canonical: registered ? registered.canonical : null,
            classification: registered ? registered.classification : 'unknown',
            kind,
        });
        if (!registered) {
            diagnostics.push(diagnostic(
                'UNKNOWN_RAW_FAMILY',
                `发现未分类的裸字体 family：${normalized}`,
                path.join(projectRoot, file.relative),
                { line, column: 0, family: normalized, source: kind, action: '在 fonts.xml rawFamilies 中分类，或改为语义 role' },
            ));
        }
    }

    function recordValue(file, source, index, value, kind) {
        for (const family of splitFamilies(value)) record(file, source, index, family, kind);
    }

    for (const file of files) {
        const source = fs.readFileSync(file.absolute, 'utf8');
        const scannable = maskComments(source, path.extname(file.relative).toLowerCase());
        const patterns = [
            {
                kind: 'css-font-family',
                regex: /font-family\s*:\s*([^;}\r\n]+)/gi,
                values: (match) => splitFamilies(match[1]),
            },
            {
                kind: 'css-font-variable',
                regex: /--[a-z0-9_-]*font[a-z0-9_-]*\s*:\s*([^;}\r\n]+)/gi,
                values: (match) => splitFamilies(match[1]),
            },
            {
                kind: 'svg-font-family',
                regex: /\bfont-family\s*=\s*(["'])(.*?)\1/gi,
                values: (match) => splitFamilies(match[2]),
            },
            {
                kind: 'dom-font-family',
                regex: /\bfontFamily\s*[:=]\s*(["'`])([^"'`$]+)\1/g,
                values: (match) => splitFamilies(match[2]),
            },
            {
                kind: 'json-font-family',
                regex: /["']fontFamily["']\s*:\s*(["'])(.*?)\1/g,
                values: (match) => splitFamilies(match[2]),
            },
            {
                kind: 'csharp-font-constructor',
                regex: /\bnew\s+(?:System\.Drawing\.)?(?:Font|FontFamily)\s*\(\s*"([^"]+)"/g,
                values: (match) => [match[1]],
            },
            {
                kind: 'csharp-font-name',
                regex: /\b(?:FontFamilyName|FontName|FamilyName|FontFamily)\s*=\s*"([^"]+)"/g,
                values: (match) => [match[1]],
            },
            {
                kind: 'data-font-face',
                regex: /(?:&lt;|<)font\b[^>]*?\bface\s*=\s*(["'])(.*?)\1/gi,
                values: (match) => [match[2]],
            },
            {
                kind: 'canvas-font',
                regex: /\.font\s*=\s*(["'`])([^"'`$]+)\1/g,
                values: (match) => extractShorthandFamilies(match[2]),
            },
            {
                kind: 'css-font-shorthand',
                regex: /(?:^|[;{])\s*font\s*:\s*([^;}\r\n]+)/gim,
                values: (match) => extractShorthandFamilies(match[1]),
            },
        ];
        for (const pattern of patterns) {
            for (const match of scannable.matchAll(pattern.regex)) {
                for (const family of pattern.values(match)) record(file, source, match.index, family, pattern.kind);
            }
        }

        if (/font/i.test(path.basename(file.relative))) {
            for (const match of scannable.matchAll(/\bstring\s*\[\]\s+(?:[a-z0-9_]*font[a-z0-9_]*|[a-z0-9_]*famil[a-z0-9_]*|names)\s*=\s*\{([^}]+)\}/gi)) {
                for (const quoted of match[1].matchAll(/"([^"]+)"/g)) {
                    record(file, source, match.index + quoted.index, quoted[1], 'csharp-font-array');
                }
            }
        }

        if (file.relative.toLowerCase().endsWith('.cs')) {
            for (const match of scannable.matchAll(/\bPlayerInfoPathGlyphAtlas\b/g)) {
                record(file, source, match.index, 'PlayerInfoPathGlyphAtlas', 'path-glyph');
            }
        }
        for (const match of scannable.matchAll(/font-family[^;\r\n]*(?:\+|\$\{)[^;\r\n]*/gi)) {
            recordDynamic(file, source, match.index, match[0]);
        }
        for (const match of scannable.matchAll(/\b(?:fontFamily|\.font)\s*[:=]\s*([^;\r\n,}]+)/g)) {
            const expression = match[1].trim();
            if (!expression
                || /^["'`]/.test(expression)
                || /^(?:inherit|null|undefined)$/i.test(expression)) continue;
            recordDynamic(file, source, match.index, expression);
        }
    }

    usages.sort((left, right) => left.file.localeCompare(right.file, 'en') || left.line - right.line || left.family.localeCompare(right.family, 'en') || left.kind.localeCompare(right.kind, 'en'));
    dynamicSites.sort((left, right) => left.file.localeCompare(right.file, 'en') || left.line - right.line || left.expression.localeCompare(right.expression, 'en'));
    catalogBoundDynamicSites.sort((left, right) => left.file.localeCompare(right.file, 'en') || left.line - right.line || left.expression.localeCompare(right.expression, 'en'));
    const classificationCounts = {};
    for (const usage of usages) classificationCounts[usage.classification] = (classificationCounts[usage.classification] || 0) + 1;
    if (dynamicSites.length) {
        diagnostics.push(diagnostic(
            'DYNAMIC_FONT_USAGE',
            `发现 ${dynamicSites.length} 个需在 Gate B/C 绑定或人工复核的动态字体表达式`,
            projectRoot,
            { line: 0, column: 0, count: dynamicSites.length, action: 'consumer cutover 前为动态来源增加 role/context 绑定' },
            'pilot-debt',
        ));
    }

    return {
        files,
        usages,
        dynamicSites,
        catalogBoundDynamicSites,
        classificationCounts,
        excluded: catalog.exclusions.map((item) => item.glob),
        diagnostics: sortDiagnostics(diagnostics),
    };
}

module.exports = { AUDIT_ROOTS, auditUsage, globToRegExp, splitFamilies };
