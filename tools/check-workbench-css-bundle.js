#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {resolveCssBundle} = require('./lib/read-css-bundle.js');

const ROOT = path.resolve(__dirname, '..');
const WEB_ROOT = path.join(ROOT, 'launcher', 'web');
const CSS_ROOT = path.join(ROOT, 'launcher', 'web', 'css');
const ENTRY = path.join(CSS_ROOT, 'panels.css');
const IMPORTS = [
    './panels/foundation-top.css',
    './workbench/tokens.css',
    './panels/foundation-rest.css',
    './workbench/core.css',
    './panels/features.css',
    './workbench/inventory.css',
    './workbench/skins.css',
    './workbench/entities.css',
    './workbench/crafting.css',
    './workbench/skills.css',
    './workbench/equipment-tuning.css',
    './workbench/components.css',
    './workbench/states.css',
    './workbench/motion.css'
];

function fail(message) {
    console.error('[workbench-css-bundle] FAIL: ' + message);
    process.exit(1);
}

function isInside(root, candidate) {
    const relative = path.relative(root, candidate);
    return relative === '' || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative));
}

function collectLocalAssetReferences(files, allowedRoot) {
    const references = [];
    const urlRe = /url\(\s*(?:"([^"]+)"|'([^']+)'|([^\s)'\"]+))\s*\)/gi;
    files.forEach(file => {
        const source = fs.readFileSync(file, 'utf8');
        let match;
        while ((match = urlRe.exec(source))) {
            const specifier = match[1] || match[2] || match[3];
            if (/^(?:[a-z][a-z0-9+.-]*:|\/\/|\/|#)/i.test(specifier)) continue;
            const pathOnly = specifier.split(/[?#]/, 1)[0];
            let decodedPath;
            try { decodedPath = decodeURIComponent(pathOnly); }
            catch (error) { throw new Error('invalid encoded CSS asset URL in ' + path.relative(ROOT, file) + ': ' + specifier); }
            const target = path.resolve(path.dirname(file), decodedPath);
            if (!isInside(allowedRoot, target)) {
                throw new Error('CSS asset URL escapes web root in ' + path.relative(ROOT, file) + ': ' + specifier);
            }
            if (!fs.existsSync(target) || !fs.statSync(target).isFile()) {
                throw new Error('missing CSS asset referenced by ' + path.relative(ROOT, file) + ': ' + specifier
                    + ' -> ' + path.relative(ROOT, target));
            }
            references.push({
                file:path.relative(ROOT, file).replace(/\\/g, '/'),
                specifier,
                target:path.relative(ROOT, target).replace(/\\/g, '/')
            });
        }
    });
    return references;
}

function assertSafetyContract() {
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-css-bundle-'));
    const root = path.join(scratch, 'root');
    fs.mkdirSync(path.join(root, 'nested'), {recursive:true});
    try {
        fs.writeFileSync(path.join(root, 'entry.css'), '@import url("./a.css");\n.entry{}\n', 'utf8');
        fs.writeFileSync(path.join(root, 'a.css'), '@import "./nested/b.css";\n.a{}\n', 'utf8');
        fs.writeFileSync(path.join(root, 'nested', 'b.css'), '.b{}\n', 'utf8');
        const nested = resolveCssBundle(path.join(root, 'entry.css'), {rootDir:root});
        if (nested.css !== '.b{}\n.a{}\n.entry{}\n') fail('recursive local @import expansion drifted');

        const externalStatement = '@import url("https://example.invalid/theme.css") screen;\n';
        fs.writeFileSync(path.join(root, 'external.css'), externalStatement + '.local{}\n', 'utf8');
        const external = resolveCssBundle(path.join(root, 'external.css'), {rootDir:root});
        if (external.css !== externalStatement + '.local{}\n') fail('external @import must remain untouched');

        fs.writeFileSync(path.join(root, 'cycle-a.css'), '@import "./cycle-b.css";\n', 'utf8');
        fs.writeFileSync(path.join(root, 'cycle-b.css'), '@import "./cycle-a.css";\n', 'utf8');
        let cycleRejected = false;
        try { resolveCssBundle(path.join(root, 'cycle-a.css'), {rootDir:root}); }
        catch (error) { cycleRejected = /cycle/i.test(error.message); }
        if (!cycleRejected) fail('recursive reader did not reject an import cycle');

        fs.writeFileSync(path.join(root, 'escape.css'), '@import "../outside.css";\n', 'utf8');
        let escapeRejected = false;
        try { resolveCssBundle(path.join(root, 'escape.css'), {rootDir:root}); }
        catch (error) { escapeRejected = /escapes bundle root/i.test(error.message); }
        if (!escapeRejected) fail('recursive reader did not reject a root escape');

        fs.writeFileSync(path.join(root, 'asset.png'), 'fixture', 'utf8');
        fs.writeFileSync(path.join(root, 'nested', 'asset.css'), '.asset{background:url("../asset.png")}', 'utf8');
        const assetReferences = collectLocalAssetReferences([path.join(root, 'nested', 'asset.css')], root);
        if (assetReferences.length !== 1) fail('local CSS asset discovery drifted');

        fs.writeFileSync(path.join(root, 'nested', 'missing.css'), '.missing{background:url("../missing.png")}', 'utf8');
        let missingRejected = false;
        try { collectLocalAssetReferences([path.join(root, 'nested', 'missing.css')], root); }
        catch (error) { missingRejected = /missing CSS asset/i.test(error.message); }
        if (!missingRejected) fail('local CSS asset closure did not reject a missing file');
    } finally {
        const tempRoot = path.resolve(os.tmpdir());
        const relative = path.relative(tempRoot, scratch);
        if (relative && !relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative)) {
            fs.rmSync(scratch, {recursive:true, force:true});
        }
    }
}

assertSafetyContract();

if (!fs.existsSync(ENTRY)) fail('missing facade: launcher/web/css/panels.css');
const facade = fs.readFileSync(ENTRY, 'utf8');
const importRe = /^[ \t]*@import\s+url\((?:"([^"]+)"|'([^']+)')\)\s*;[ \t]*(?:\r?\n|$)/gm;
const actualImports = [];
const residue = facade.replace(importRe, (statement, doubleQuoted, singleQuoted) => {
    actualImports.push(doubleQuoted || singleQuoted);
    return '';
});
if (residue.trim()) fail('panels.css must remain an import-only facade');
if (JSON.stringify(actualImports) !== JSON.stringify(IMPORTS)) {
    fail('facade import order drifted\nexpected: ' + IMPORTS.join(', ') + '\nactual:   ' + actualImports.join(', '));
}

let result;
try {
    result = resolveCssBundle(ENTRY, {rootDir:CSS_ROOT});
} catch (error) {
    fail(error.message || String(error));
}

const expectedFiles = [ENTRY].concat(IMPORTS.map(specifier => path.resolve(CSS_ROOT, specifier)));
if (JSON.stringify(result.files) !== JSON.stringify(expectedFiles)) {
    fail('resolved dependency order does not match the facade');
}

let assetReferences;
try {
    assetReferences = collectLocalAssetReferences(result.files.slice(1), WEB_ROOT);
} catch (error) {
    fail(error.message || String(error));
}
if (!assetReferences.length) fail('no local asset references found; CSS asset closure check is not exercised');

const digest = crypto.createHash('sha256').update(result.css, 'utf8').digest('hex');
const expectedArg = process.argv.find(value => value.startsWith('--expect-sha='));
if (expectedArg) {
    const expectedDigest = expectedArg.slice('--expect-sha='.length).toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(expectedDigest)) fail('invalid --expect-sha value');
    if (digest !== expectedDigest) fail('expanded bundle SHA-256 mismatch: expected ' + expectedDigest + ', got ' + digest);
}

const fragments = result.files.slice(1).map(file => {
    const text = fs.readFileSync(file, 'utf8');
    return {
        file:path.relative(ROOT, file).replace(/\\/g, '/'),
        bytes:Buffer.byteLength(text, 'utf8'),
        lines:text.split(/\r?\n/).length - (text.endsWith('\n') ? 1 : 0)
    };
});
const maxFragment = fragments.reduce((max, item) => item.lines > max.lines ? item : max, {file:'', lines:0});
if (maxFragment.lines > 10000) fail('CSS fragment exceeds 10,000-line governance ceiling: ' + maxFragment.file);

console.log(JSON.stringify({
    ok:true,
    safetyChecks:['recursive-import','external-import-preservation','cycle-rejection','root-boundary','local-asset-closure'],
    facade:'launcher/web/css/panels.css',
    imports:IMPORTS.length,
    localAssetReferences:assetReferences,
    aggregate:{
        bytes:Buffer.byteLength(result.css, 'utf8'),
        lines:result.css.split(/\r?\n/).length - (result.css.endsWith('\n') ? 1 : 0),
        sha256:digest
    },
    maxFragment,
    fragments
}, null, 2));
