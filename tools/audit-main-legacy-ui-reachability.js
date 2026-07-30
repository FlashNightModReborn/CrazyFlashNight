#!/usr/bin/env node
'use strict';

// Fail-closed structural gate for retired AS2 UI assets in the published main.
//
// The source half reads only the main XFL DOMDocument Include manifest and the
// included library XML files.  It intentionally does not grep the repository,
// comments, CDATA/ActionScript, documentation, or orphan library XML.
//
// The binary half converts the published main SWF to FFDec XML and inspects only
// ImportAssets, linkage-name, and PlaceObject structures.  Script string pools
// are deliberately outside this gate.

const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const DEFAULT_DOM = path.join(
    'CRAZYFLASHER7MercenaryEmpire',
    'DOMDocument.xml'
);
const DEFAULT_SWF = 'CRAZYFLASHER7MercenaryEmpire.swf';

const FORBIDDEN_EXTERNAL_SWFS = Object.freeze([
    '物品与技能相关界面.swf',
    '物品改装界面.swf'
]);

const FORBIDDEN_UI_IDENTIFIERS = Object.freeze([
    '物品改装界面',
    '物品栏界面',
    '购买物品界面',
    '仓库界面',
    '学习技能界面',
    '资源箱界面'
]);

// Some retired authoring symbols have opaque Flash-generated names.  Keep the
// aliases explicit so re-placing an unnamed legacy symbol cannot bypass the
// human-readable linkage/instance checks.
const FORBIDDEN_LIBRARY_ITEMS = Object.freeze({
    'import/UI组件/物品改装界面': '物品改装界面',
    'import/UI组件/新版物品栏界面': '物品栏界面',
    'import/UI组件/新版商店界面': '购买物品界面',
    'import/UI组件/新版仓库界面': '仓库界面',
    'import/UI组件/资源箱界面': '资源箱界面',
    'sprite/Symbol 1779': '学习技能界面'
});

const SWF_LINKAGE_TAGS = new Set([
    'ImportAssetsTag',
    'ImportAssets2Tag',
    'ExportAssetsTag',
    'SymbolClassTag'
]);

function readUtf8(file) {
    return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
}

function maskXmlNonMarkup(text) {
    function blank(match) {
        return match.replace(/[^\r\n]/gu, ' ');
    }
    return text
        .replace(/<!\[CDATA\[[\s\S]*?\]\]>/gu, blank)
        .replace(/<!--[\s\S]*?-->/gu, blank);
}

function decodeXml(value) {
    return String(value || '').replace(
        /&(?:quot|apos|lt|gt|amp|#x[0-9a-f]+|#[0-9]+);/giu,
        entity => {
            switch (entity.toLowerCase()) {
                case '&quot;': return '"';
                case '&apos;': return "'";
                case '&lt;': return '<';
                case '&gt;': return '>';
                case '&amp;': return '&';
                default: {
                    const body = entity.slice(2, -1);
                    const codePoint = body[0].toLowerCase() === 'x'
                        ? Number.parseInt(body.slice(1), 16)
                        : Number.parseInt(body, 10);
                    return Number.isFinite(codePoint)
                        ? String.fromCodePoint(codePoint)
                        : entity;
                }
            }
        }
    );
}

function parseAttributes(raw) {
    const attributes = {};
    const pattern = /([A-Za-z_][\w:.-]*)\s*=\s*(["'])([\s\S]*?)\2/gu;
    let match;
    while ((match = pattern.exec(raw)) !== null) {
        attributes[match[1]] = decodeXml(match[3]);
    }
    return attributes;
}

function parseXmlTokens(text) {
    const masked = maskXmlNonMarkup(text);
    const pattern = /<\s*(\/?)\s*([A-Za-z_][\w:.-]*)\b([^<>]*?)(\/?)\s*>/gu;
    const stack = [];
    const tokens = [];
    let match;

    while ((match = pattern.exec(masked)) !== null) {
        const closing = match[1] === '/';
        const name = match[2];
        if (closing) {
            let ownerIndex = stack.length - 1;
            while (ownerIndex >= 0 && stack[ownerIndex].name !== name) {
                ownerIndex--;
            }
            if (ownerIndex >= 0) stack.length = ownerIndex;
            continue;
        }

        const token = {
            name,
            attributes: parseAttributes(match[3]),
            start: match.index,
            end: pattern.lastIndex,
            ancestors: stack.slice()
        };
        tokens.push(token);
        if (match[4] !== '/') stack.push(token);
    }

    return tokens;
}

function lineOf(text, index) {
    let line = 1;
    for (let cursor = 0; cursor < index; cursor++) {
        if (text.charCodeAt(cursor) === 10) line++;
    }
    return line;
}

function normalizeSlashes(value) {
    return String(value || '').replace(/\\/gu, '/');
}

function normalizeLibraryItem(value) {
    let normalized = normalizeSlashes(value).replace(/^\.?\/*LIBRARY\//iu, '');
    normalized = normalized.replace(/\.xml$/iu, '');
    return normalized.replace(/^\/+|\/+$/gu, '');
}

function unique(values) {
    return Array.from(new Set(values));
}

function matchExternalSwfs(value) {
    const normalized = normalizeSlashes(value).split(/[?#]/u, 1)[0];
    const base = normalized.slice(normalized.lastIndexOf('/') + 1);
    return FORBIDDEN_EXTERNAL_SWFS.filter(item => base === item);
}

function matchUiIdentifiers(value) {
    const text = String(value || '');
    return FORBIDDEN_UI_IDENTIFIERS.filter(item => text.includes(item));
}

function matchLibraryItem(value) {
    const normalized = normalizeLibraryItem(value);
    const matches = matchUiIdentifiers(normalized);
    if (Object.prototype.hasOwnProperty.call(FORBIDDEN_LIBRARY_ITEMS, normalized)) {
        matches.push(FORBIDDEN_LIBRARY_ITEMS[normalized]);
    }
    return unique(matches);
}

function isInside(root, candidate) {
    const relative = path.relative(root, candidate);
    return relative === '' ||
        (!relative.startsWith('..' + path.sep) &&
         relative !== '..' &&
         !path.isAbsolute(relative));
}

function relativeDisplay(projectRoot, file) {
    const relative = path.relative(projectRoot, file);
    return isInside(projectRoot, file)
        ? normalizeSlashes(relative)
        : normalizeSlashes(file);
}

function createFinding(level, code, message, file, line, token, value, route) {
    const finding = {
        level,
        code,
        message,
        file,
        line,
        token,
        value
    };
    if (route && route.length > 0) finding.route = route.slice();
    return finding;
}

function sortAndDedupe(findings) {
    const seen = new Set();
    const result = [];
    findings.sort((left, right) => {
        const a = [
            left.level, left.file, String(left.line || 0), left.code,
            left.token, left.value, (left.route || []).join(' -> ')
        ].join('\u0000');
        const b = [
            right.level, right.file, String(right.line || 0), right.code,
            right.token, right.value, (right.route || []).join(' -> ')
        ].join('\u0000');
        return a < b ? -1 : (a > b ? 1 : 0);
    });
    for (const finding of findings) {
        const key = JSON.stringify(finding);
        if (seen.has(key)) continue;
        seen.add(key);
        result.push(finding);
    }
    return result;
}

function addMatches(findings, options) {
    for (const token of unique(options.tokens || [])) {
        findings.push(createFinding(
            options.level || 'error',
            options.code,
            options.message,
            options.file,
            options.line,
            token,
            options.value,
            options.route
        ));
    }
}

function scanXflSource(projectRoot, domPath) {
    const findings = [];
    const resolvedDom = path.resolve(projectRoot, domPath || DEFAULT_DOM);
    const xflRoot = path.dirname(resolvedDom);
    const libraryRoot = path.join(xflRoot, 'LIBRARY');
    const domDisplay = relativeDisplay(projectRoot, resolvedDom);

    if (!fs.existsSync(resolvedDom) || !fs.statSync(resolvedDom).isFile()) {
        findings.push(createFinding(
            'error',
            'XFL_DOM_MISSING',
            'main XFL DOMDocument.xml is missing',
            domDisplay,
            0,
            '',
            resolvedDom
        ));
        return {
            findings,
            domPath: resolvedDom,
            includedSymbols: 0,
            reachableSymbols: 0,
            includeHrefs: []
        };
    }

    const domText = readUtf8(resolvedDom);
    const domTokens = parseXmlTokens(domText);
    const includeTokens = domTokens.filter(token =>
        token.name === 'Include' && token.attributes.href
    );
    const symbols = new Map();
    const includeHrefs = [];

    for (const include of includeTokens) {
        const href = include.attributes.href;
        includeHrefs.push(href);
        addMatches(findings, {
            code: 'XFL_FORBIDDEN_INCLUDE',
            message: 'main XFL Include manifest retains a retired AS2 UI symbol',
            file: domDisplay,
            line: lineOf(domText, include.start),
            tokens: matchLibraryItem(href),
            value: href,
            route: ['DOMDocument Include manifest']
        });

        const symbolPath = path.resolve(
            libraryRoot,
            ...normalizeSlashes(href).split('/')
        );
        if (!isInside(libraryRoot, symbolPath)) {
            findings.push(createFinding(
                'error',
                'XFL_INCLUDE_OUTSIDE_LIBRARY',
                'main XFL Include escapes the LIBRARY root',
                domDisplay,
                lineOf(domText, include.start),
                '',
                href
            ));
            continue;
        }
        if (!fs.existsSync(symbolPath) || !fs.statSync(symbolPath).isFile()) {
            findings.push(createFinding(
                'error',
                'XFL_INCLUDE_MISSING',
                'main XFL Include target is missing',
                domDisplay,
                lineOf(domText, include.start),
                '',
                href
            ));
            continue;
        }

        const text = readUtf8(symbolPath);
        const tokens = parseXmlTokens(text);
        const item = tokens.find(token => token.name === 'DOMSymbolItem');
        const fallbackName = normalizeLibraryItem(href);
        const symbolName = normalizeLibraryItem(
            item && item.attributes.name || fallbackName
        );
        const file = relativeDisplay(projectRoot, symbolPath);
        symbols.set(symbolName, { name: symbolName, file, text, tokens, item });

        if (!item) continue;
        addMatches(findings, {
            code: 'XFL_FORBIDDEN_SYMBOL',
            message: 'included main-XFL symbol is a retired AS2 UI asset',
            file,
            line: lineOf(text, item.start),
            tokens: matchLibraryItem(item.attributes.name || symbolName),
            value: item.attributes.name || symbolName,
            route: ['DOMDocument Include manifest', symbolName]
        });
        addMatches(findings, {
            code: 'XFL_FORBIDDEN_LINKAGE',
            message: 'included main-XFL symbol exports/imports a retired AS2 UI linkage',
            file,
            line: lineOf(text, item.start),
            tokens: matchUiIdentifiers(item.attributes.linkageIdentifier),
            value: item.attributes.linkageIdentifier || '',
            route: ['DOMDocument Include manifest', symbolName]
        });
        for (const attribute of ['linkageURL', 'sourceURL']) {
            addMatches(findings, {
                code: 'XFL_FORBIDDEN_EXTERNAL_SWF',
                message: 'included main-XFL symbol imports a retired AS2 UI SWF',
                file,
                line: lineOf(text, item.start),
                tokens: matchExternalSwfs(item.attributes[attribute]),
                value: item.attributes[attribute] || '',
                route: ['DOMDocument Include manifest', symbolName]
            });
        }
    }

    const routes = new Map();
    const queue = [];
    const rootInstances = domTokens.filter(token => token.name === 'DOMSymbolInstance');
    for (const instance of rootInstances) {
        const libraryItemName = normalizeLibraryItem(
            instance.attributes.libraryItemName
        );
        const route = libraryItemName ? ['<main timeline>', libraryItemName] : [];
        addMatches(findings, {
            code: 'XFL_FORBIDDEN_ROOT_PLACE',
            message: 'main timeline places a retired AS2 UI instance',
            file: domDisplay,
            line: lineOf(domText, instance.start),
            tokens: unique(
                matchUiIdentifiers(instance.attributes.name)
                    .concat(matchLibraryItem(libraryItemName))
            ),
            value: [
                instance.attributes.name || '',
                instance.attributes.libraryItemName || ''
            ].filter(Boolean).join(' | '),
            route
        });
        if (libraryItemName && !routes.has(libraryItemName)) {
            routes.set(libraryItemName, route);
            queue.push(libraryItemName);
        }
    }

    while (queue.length > 0) {
        const ownerName = queue.shift();
        const owner = symbols.get(ownerName);
        if (!owner) continue;
        const ownerRoute = routes.get(ownerName) || ['<main timeline>', ownerName];
        const instances = owner.tokens.filter(token =>
            token.name === 'DOMSymbolInstance'
        );
        for (const instance of instances) {
            const childName = normalizeLibraryItem(
                instance.attributes.libraryItemName
            );
            const childRoute = childName
                ? ownerRoute.concat(childName)
                : ownerRoute.slice();
            addMatches(findings, {
                code: 'XFL_FORBIDDEN_REACHABLE_PLACE',
                message: 'a main-reachable helper symbol places a retired AS2 UI instance',
                file: owner.file,
                line: lineOf(owner.text, instance.start),
                tokens: unique(
                    matchUiIdentifiers(instance.attributes.name)
                        .concat(matchLibraryItem(childName))
                ),
                value: [
                    instance.attributes.name || '',
                    instance.attributes.libraryItemName || ''
                ].filter(Boolean).join(' | '),
                route: childRoute
            });
            if (childName && !routes.has(childName)) {
                routes.set(childName, childRoute);
                queue.push(childName);
            }
        }
    }

    return {
        findings: sortAndDedupe(findings),
        domPath: resolvedDom,
        includedSymbols: symbols.size,
        reachableSymbols: Array.from(routes.keys())
            .filter(name => symbols.has(name)).length,
        includeHrefs
    };
}

function nearestTypedItem(token) {
    for (let index = token.ancestors.length - 1; index >= 0; index--) {
        const ancestor = token.ancestors[index];
        if (ancestor.name === 'item' && ancestor.attributes.type) return ancestor;
    }
    return null;
}

function hasAncestor(token, name) {
    return token.ancestors.some(ancestor => ancestor.name === name);
}

function directText(text, token) {
    const nextTag = text.indexOf('<', token.end);
    const end = nextTag < 0 ? text.length : nextTag;
    return decodeXml(text.slice(token.end, end)).trim();
}

function scanSwfXmlText(xmlText, displayFile) {
    const findings = [];
    const tokens = parseXmlTokens(xmlText);

    for (const token of tokens) {
        if (token.name !== 'item') continue;
        const type = token.attributes.type || '';

        if (type === 'ImportAssetsTag' || type === 'ImportAssets2Tag') {
            addMatches(findings, {
                code: 'SWF_FORBIDDEN_IMPORT_URL',
                message: 'published main SWF imports a retired AS2 UI SWF',
                file: displayFile,
                line: lineOf(xmlText, token.start),
                tokens: matchExternalSwfs(token.attributes.url),
                value: token.attributes.url || ''
            });
        }

        if (/^PlaceObject(?:2|3|4)?Tag$/u.test(type)) {
            for (const attribute of ['name', 'className']) {
                addMatches(findings, {
                    code: 'SWF_FORBIDDEN_PLACE_OBJECT',
                    message: 'published main SWF places a retired AS2 UI instance',
                    file: displayFile,
                    line: lineOf(xmlText, token.start),
                    tokens: matchUiIdentifiers(token.attributes[attribute]),
                    value: token.attributes[attribute] || ''
                });
            }
        }

        if (!hasAncestor(token, 'names')) continue;
        const owner = nearestTypedItem(token);
        if (!owner || !SWF_LINKAGE_TAGS.has(owner.attributes.type)) continue;
        const value = directText(xmlText, token);
        const matches = matchUiIdentifiers(value);
        if (matches.length === 0) continue;
        const importName = owner.attributes.type === 'ImportAssetsTag' ||
            owner.attributes.type === 'ImportAssets2Tag';
        addMatches(findings, {
            code: importName
                ? 'SWF_FORBIDDEN_IMPORT_NAME'
                : 'SWF_FORBIDDEN_EXPORTED_LINKAGE',
            message: importName
                ? 'published main SWF imports a retired AS2 UI linkage'
                : 'published main SWF exposes a retired AS2 UI linkage',
            file: displayFile,
            line: lineOf(xmlText, token.start),
            tokens: matches,
            value
        });
    }

    return {
        findings: sortAndDedupe(findings),
        tagCount: tokens.filter(token =>
            token.name === 'item' && token.attributes.type
        ).length
    };
}

function findJavaRuntime() {
    const candidates = [];
    if (process.env.JAVA_HOME) {
        candidates.push(path.join(process.env.JAVA_HOME, 'bin', 'java.exe'));
        candidates.push(path.join(process.env.JAVA_HOME, 'bin', 'java'));
    }
    candidates.push(
        'java',
        path.join(
            process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)',
            'Common Files', 'Adobe', 'Adobe Flash CS6', 'jre', 'bin', 'java.exe'
        )
    );

    for (const candidate of candidates) {
        if (candidate !== 'java' && !fs.existsSync(candidate)) continue;
        const probe = childProcess.spawnSync(candidate, ['-version'], {
            encoding: 'utf8',
            windowsHide: true
        });
        if (probe.error || probe.status !== 0) continue;
        const versionText = String(probe.stdout || '') + String(probe.stderr || '');
        const match = versionText.match(/\bversion\s+"(?:1\.)?(\d+)/iu);
        if (match && Number(match[1]) >= 8) return candidate;
    }
    return '';
}

function resolveFfdecRunner(projectRoot, override) {
    if (override) {
        const resolved = path.resolve(projectRoot, override);
        if (!fs.existsSync(resolved)) return null;
        if (path.extname(resolved).toLowerCase() === '.jar') {
            const java = findJavaRuntime();
            return java
                ? { command: java, prefixArgs: ['-jar', resolved], description: resolved }
                : null;
        }
        return { command: resolved, prefixArgs: [], description: resolved };
    }

    const jar = path.join(projectRoot, 'tools', 'ffdec', 'ffdec.jar');
    const java = findJavaRuntime();
    if (java && fs.existsSync(jar)) {
        return {
            command: java,
            prefixArgs: ['-jar', jar],
            description: relativeDisplay(projectRoot, jar)
        };
    }

    // ffdec-cli.exe is a Launch4j wrapper which may return before its Java
    // child exits.  Prefer the jar so spawnSync owns the real process and the
    // audited SWF cannot remain locked after this gate completes.
    const cli = path.join(projectRoot, 'tools', 'ffdec', 'ffdec-cli.exe');
    if (process.platform === 'win32' && fs.existsSync(cli)) {
        return {
            command: cli,
            prefixArgs: [],
            description: relativeDisplay(projectRoot, cli)
        };
    }

    const shell = path.join(projectRoot, 'tools', 'ffdec', 'ffdec');
    if (fs.existsSync(shell)) {
        return {
            command: shell,
            prefixArgs: [],
            description: relativeDisplay(projectRoot, shell)
        };
    }
    return null;
}

function exportSwfXml(projectRoot, swfPath, options) {
    const runner = resolveFfdecRunner(projectRoot, options.ffdec);
    if (!runner) {
        throw new Error('repository FFDec runner is unavailable');
    }
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-main-ui-gate-'));
    const xmlPath = path.join(tempRoot, 'main.swf.xml');
    const args = runner.prefixArgs.concat([
        '-swf2xml',
        swfPath,
        xmlPath
    ]);
    const result = childProcess.spawnSync(runner.command, args, {
        cwd: projectRoot,
        encoding: 'utf8',
        maxBuffer: 32 * 1024 * 1024,
        timeout: options.ffdecTimeoutMs || 180000,
        windowsHide: true
    });
    if (result.error) {
        if (!options.keepSwfXml) fs.rmSync(tempRoot, { recursive: true, force: true });
        throw result.error;
    }
    if (result.status !== 0 || !fs.existsSync(xmlPath)) {
        const detail = [
            result.stdout || '',
            result.stderr || ''
        ].join('\n').trim().slice(0, 2000);
        if (!options.keepSwfXml) fs.rmSync(tempRoot, { recursive: true, force: true });
        throw new Error(
            'FFDec -swf2xml failed with exit ' + result.status +
            (detail ? ': ' + detail : '')
        );
    }
    return {
        xmlPath,
        tempRoot,
        runner: runner.description
    };
}

function auditProject(options) {
    const projectRoot = path.resolve(options.projectRoot || path.resolve(__dirname, '..'));
    const domPath = path.resolve(projectRoot, options.dom || DEFAULT_DOM);
    const source = scanXflSource(projectRoot, domPath);
    let findings = source.findings.slice();
    const swf = {
        requested: !options.sourceOnly,
        scanned: false,
        status: options.sourceOnly ? 'skipped_source_only' : 'pending',
        path: '',
        xmlSource: '',
        ffdecRunner: '',
        tagCount: 0
    };

    let exported = null;
    try {
        if (!options.sourceOnly) {
            if (options.swfXml) {
                const xmlPath = path.resolve(projectRoot, options.swfXml);
                swf.path = options.swf
                    ? relativeDisplay(projectRoot, path.resolve(projectRoot, options.swf))
                    : '';
                swf.xmlSource = relativeDisplay(projectRoot, xmlPath);
                if (!fs.existsSync(xmlPath) || !fs.statSync(xmlPath).isFile()) {
                    findings.push(createFinding(
                        'error',
                        'SWF_XML_MISSING',
                        'provided FFDec SWF XML is missing',
                        swf.xmlSource,
                        0,
                        '',
                        xmlPath
                    ));
                    swf.status = 'failed';
                } else {
                    const result = scanSwfXmlText(readUtf8(xmlPath), swf.xmlSource);
                    findings = findings.concat(result.findings);
                    swf.scanned = true;
                    swf.status = 'scanned_fixture_xml';
                    swf.tagCount = result.tagCount;
                }
            } else {
                const swfPath = path.resolve(projectRoot, options.swf || DEFAULT_SWF);
                swf.path = relativeDisplay(projectRoot, swfPath);
                if (!fs.existsSync(swfPath) || !fs.statSync(swfPath).isFile()) {
                    findings.push(createFinding(
                        options.requireSwf ? 'error' : 'warning',
                        'SWF_MISSING',
                        'published main SWF is absent; binary reachability was not checked',
                        swf.path,
                        0,
                        '',
                        swfPath
                    ));
                    swf.status = 'missing';
                } else {
                    exported = exportSwfXml(projectRoot, swfPath, options);
                    swf.xmlSource = options.keepSwfXml
                        ? normalizeSlashes(exported.xmlPath)
                        : '<temporary FFDec XML>';
                    swf.ffdecRunner = exported.runner;
                    const result = scanSwfXmlText(
                        readUtf8(exported.xmlPath),
                        swf.path + ' (FFDec XML)'
                    );
                    findings = findings.concat(result.findings);
                    swf.scanned = true;
                    swf.status = 'scanned_ffdec';
                    swf.tagCount = result.tagCount;
                }
            }
        }
    } catch (error) {
        findings.push(createFinding(
            'error',
            'SWF_SCAN_FAILED',
            'published main SWF could not be structurally audited',
            swf.path || DEFAULT_SWF,
            0,
            '',
            error.message
        ));
        swf.status = 'failed';
    } finally {
        if (exported && !options.keepSwfXml) {
            fs.rmSync(exported.tempRoot, { recursive: true, force: true });
        }
    }

    findings = sortAndDedupe(findings);
    const errors = findings.filter(item => item.level === 'error').length;
    const warnings = findings.filter(item => item.level === 'warning').length;
    return {
        schemaVersion: 'cf7-main-legacy-ui-reachability/v1',
        tool: 'audit-main-legacy-ui-reachability',
        status: errors === 0 ? 'passed' : 'failed',
        projectRoot: normalizeSlashes(projectRoot),
        forbidden: {
            externalSwfs: FORBIDDEN_EXTERNAL_SWFS.slice(),
            uiIdentifiers: FORBIDDEN_UI_IDENTIFIERS.slice(),
            libraryItems: Object.assign({}, FORBIDDEN_LIBRARY_ITEMS)
        },
        source: {
            domPath: relativeDisplay(projectRoot, source.domPath),
            includedSymbols: source.includedSymbols,
            reachableSymbols: source.reachableSymbols,
            includeCount: source.includeHrefs.length
        },
        swf,
        summary: { errors, warnings },
        findings
    };
}

function parseArguments(argv) {
    const options = {};
    const valueOptions = new Set([
        'project-root', 'dom', 'swf', 'swf-xml', 'ffdec', 'ffdec-timeout-ms'
    ]);
    const flagOptions = new Set([
        'source-only', 'require-swf', 'keep-swf-xml', 'json', 'help'
    ]);

    for (let index = 0; index < argv.length; index++) {
        const raw = argv[index];
        if (!raw.startsWith('--')) throw new Error('unexpected argument: ' + raw);
        const equals = raw.indexOf('=');
        const name = raw.slice(2, equals >= 0 ? equals : undefined);
        if (flagOptions.has(name)) {
            if (equals >= 0) throw new Error('--' + name + ' does not take a value');
            options[name.replace(/-([a-z])/gu, (_, ch) => ch.toUpperCase())] = true;
            continue;
        }
        if (!valueOptions.has(name)) throw new Error('unknown option: --' + name);
        const value = equals >= 0 ? raw.slice(equals + 1) : argv[++index];
        if (value === undefined || value === '') {
            throw new Error('--' + name + ' requires a value');
        }
        options[name.replace(/-([a-z])/gu, (_, ch) => ch.toUpperCase())] = value;
    }

    if (options.ffdecTimeoutMs !== undefined) {
        const parsed = Number(options.ffdecTimeoutMs);
        if (!Number.isSafeInteger(parsed) || parsed < 1000) {
            throw new Error('--ffdec-timeout-ms must be an integer >= 1000');
        }
        options.ffdecTimeoutMs = parsed;
    }
    return options;
}

function usage() {
    return [
        'Usage: node tools/audit-main-legacy-ui-reachability.js [options]',
        '',
        'Options:',
        '  --project-root <path>   Repository root (defaults to parent of tools/)',
        '  --dom <path>            Main DOMDocument.xml path relative to project root',
        '  --swf <path>            Published main SWF path relative to project root',
        '  --swf-xml <path>        Inspect an existing FFDec XML instead of running FFDec',
        '  --source-only           Inspect only the XFL source closure',
        '  --require-swf           Missing published main SWF is an error',
        '  --ffdec <path>          Override FFDec CLI or jar',
        '  --ffdec-timeout-ms <n>  FFDec timeout (default: 180000)',
        '  --keep-swf-xml          Retain temporary FFDec XML for diagnosis',
        '  --json                  Print a machine-readable report'
    ].join('\n');
}

function printHuman(report) {
    console.log(
        '[main-legacy-ui] XFL source: includes=' + report.source.includeCount +
        ', includedSymbols=' + report.source.includedSymbols +
        ', reachableSymbols=' + report.source.reachableSymbols
    );
    console.log(
        '[main-legacy-ui] SWF: status=' + report.swf.status +
        (report.swf.path ? ', path=' + report.swf.path : '')
    );
    for (const finding of report.findings) {
        const output = finding.level === 'error' ? console.error : console.warn;
        const location = finding.file +
            (finding.line ? ':' + finding.line : '');
        const route = finding.route
            ? ' route=' + finding.route.join(' -> ')
            : '';
        output(
            '[main-legacy-ui][' + finding.level.toUpperCase() + ']' +
            '[' + finding.code + '] ' + location + ': ' +
            finding.message +
            (finding.token ? ' [' + finding.token + ']' : '') +
            (finding.value ? ' value=' + JSON.stringify(finding.value) : '') +
            route
        );
    }
    console.log(
        '[main-legacy-ui] ' + report.status.toUpperCase() +
        ': errors=' + report.summary.errors +
        ', warnings=' + report.summary.warnings
    );
}

function main() {
    let options;
    try {
        options = parseArguments(process.argv.slice(2));
    } catch (error) {
        console.error('[main-legacy-ui] ' + error.message);
        console.error(usage());
        process.exitCode = 2;
        return;
    }
    if (options.help) {
        console.log(usage());
        return;
    }

    const report = auditProject(options);
    if (options.json) {
        console.log(JSON.stringify(report, null, 2));
    } else {
        printHuman(report);
    }
    if (report.status !== 'passed') process.exitCode = 1;
}

module.exports = {
    DEFAULT_DOM,
    DEFAULT_SWF,
    FORBIDDEN_EXTERNAL_SWFS,
    FORBIDDEN_LIBRARY_ITEMS,
    FORBIDDEN_UI_IDENTIFIERS,
    auditProject,
    parseArguments,
    parseXmlTokens,
    scanSwfXmlText,
    scanXflSource
};

if (require.main === module) main();
