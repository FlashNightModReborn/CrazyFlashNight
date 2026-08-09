#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const {
    isDressupPortraitRef,
    projectDressupPortrait
} = require('./lib/arena-portrait-routing');

const ROOT = path.resolve(__dirname, '..');
const UNITS_PATH = path.join(ROOT, 'data', 'units', 'units.json');
const MANIFEST_PATH = path.join(ROOT, 'launcher', 'web', 'assets', 'enemy-portraits', 'manifest.json');
const WEB_ROOT = path.join(ROOT, 'launcher', 'web');
const PILOT_BASELINE = Object.freeze({ total: 217, ready: 210, missing: 7 });
const SUPPORTED_SCHEMAS = new Set([
    'cf7.team-enemy-portrait-manifest.v1',
    'cf7.enemy-portrait-manifest.v1'
]);

function readJson(file) {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function resolveAlias(manifest, requestedRef, errors) {
    const seen = new Set();
    let current = requestedRef;
    while (manifest.aliases && manifest.aliases[current]) {
        if (seen.has(current)) {
            errors.push(`alias cycle: ${Array.from(seen).concat(current).join(' -> ')}`);
            return current;
        }
        seen.add(current);
        const next = manifest.aliases[current].targetPortraitRef;
        if (!next || typeof next !== 'string') {
            errors.push(`alias target missing: ${current}`);
            return current;
        }
        current = next;
    }
    return current;
}

function acceptedVariant(entry) {
    if (!entry || !entry.variants) return null;
    const variant = entry.variants[entry.defaultVariant];
    return variant && variant.status === 'human_accepted' && variant.subject ? variant : null;
}

function localAssetPath(url) {
    if (!url || typeof url !== 'string' || /^[a-z]+:/i.test(url) || url.startsWith('//')) return null;
    const normalized = url.replace(/^\/+/, '').split('/');
    return path.join(WEB_ROOT, ...normalized);
}

function audit() {
    const errors = [];
    const units = readJson(UNITS_PATH);
    const manifest = readJson(MANIFEST_PATH);
    if (!Array.isArray(units)) errors.push('data/units/units.json must be an array');
    if (!SUPPORTED_SCHEMAS.has(manifest.schema)) errors.push(`unsupported manifest schema: ${manifest.schema || '<blank>'}`);
    if (!manifest.entries || typeof manifest.entries !== 'object') errors.push('manifest entries missing');

    const refs = [];
    const unique = new Set();
    const unitsByRef = new Map();
    let blank = 0;
    for (const unit of Array.isArray(units) ? units : []) {
        const ref = String(unit && unit.spritename || '').trim();
        if (!ref) { blank++; continue; }
        if (!unitsByRef.has(ref)) unitsByRef.set(ref, []);
        unitsByRef.get(ref).push(unit);
        if (!unique.has(ref)) {
            unique.add(ref);
            refs.push(ref);
        }
    }

    const dressupReadyRefs = [];
    const dressupMissingRefs = [];
    const enemyRefs = [];
    for (const ref of refs) {
        if (!isDressupPortraitRef(ref)) {
            enemyRefs.push(ref);
            continue;
        }
        const matchingUnits = unitsByRef.get(ref) || [];
        if (matchingUnits.length > 0 && matchingUnits.every(unit => projectDressupPortrait(unit))) {
            dressupReadyRefs.push(ref);
        } else {
            dressupMissingRefs.push(ref);
        }
    }

    const readyRefs = dressupReadyRefs.slice();
    const missingRefs = dressupMissingRefs.slice();
    let aliasResolved = 0;
    for (const ref of enemyRefs) {
        const resolved = resolveAlias(manifest, ref, errors);
        if (resolved !== ref) aliasResolved++;
        if (acceptedVariant(manifest.entries && manifest.entries[resolved])) readyRefs.push(ref);
        else missingRefs.push(ref);
    }

    let acceptedVariantCount = 0;
    let checkedAssetCount = 0;
    const checkedAssetFiles = new Set();
    for (const [portraitRef, entry] of Object.entries(manifest.entries || {})) {
        if (!entry || !entry.variants) {
            errors.push(`entry variants missing: ${portraitRef}`);
            continue;
        }
        for (const [variantKey, variant] of Object.entries(entry.variants)) {
            if (!variant || variant.status !== 'human_accepted') continue;
            acceptedVariantCount++;
            const bindings = [
                { kind: 'svg', url: variant.subject && variant.subject.svg && variant.subject.svg.url },
                { kind: 'png', url: variant.subject && variant.subject.pngFallback && variant.subject.pngFallback.url }
            ];
            for (const binding of bindings) {
                const url = binding.url;
                const file = localAssetPath(url);
                if (!file) {
                    errors.push(`accepted asset URL invalid: ${portraitRef}::${variantKey}`);
                    continue;
                }
                checkedAssetCount++;
                checkedAssetFiles.add(path.resolve(file));
                if (!fs.existsSync(file)) {
                    errors.push(`accepted asset missing: ${path.relative(ROOT, file)}`);
                } else if (binding.kind === 'svg') {
                    const svg = fs.readFileSync(file, 'utf8');
                    if (/<filter\b[^>]*\bid=(['"])[^'"]+\1[^>]*\/\s*>/i.test(svg)) {
                        errors.push(`accepted SVG contains browser-blank FFDec filter: ${path.relative(ROOT, file)}`);
                    }
                }
            }
        }
    }

    const folded = new Map();
    for (const ref of refs) {
        const key = ref.toLocaleLowerCase('zh-CN');
        if (!folded.has(key)) folded.set(key, []);
        folded.get(key).push(ref);
    }
    const caseFoldCollisions = Array.from(folded.values()).filter(group => group.length > 1);
    const manifestRefs = Object.keys(manifest.entries || {});
    const missingDetails = dressupMissingRefs.map(ref => ({
        portraitRef: ref,
        resolvedPortraitRef: ref,
        status: 'dressup_projection_missing',
        caseMatches: []
    })).concat(missingRefs.filter(ref => !isDressupPortraitRef(ref)).map(ref => {
        const resolved = resolveAlias(manifest, ref, errors);
        const entry = manifest.entries && manifest.entries[resolved];
        const caseMatches = entry ? [] : manifestRefs.filter(candidate => (
            candidate.toLocaleLowerCase('zh-CN') === resolved.toLocaleLowerCase('zh-CN')
        ));
        return {
            portraitRef: ref,
            resolvedPortraitRef: resolved,
            status: entry ? (entry.status || 'manifest_entry_without_status')
                : (caseMatches.length ? 'case_mismatch' : 'no_manifest_entry'),
            caseMatches
        };
    }));
    const missingByStatus = {};
    for (const detail of missingDetails) {
        missingByStatus[detail.status] = (missingByStatus[detail.status] || 0) + 1;
    }

    const summary = {
        schema: 'cf7.arena-portrait-coverage-audit.v1',
        source: {
            units: path.relative(ROOT, UNITS_PATH).replace(/\\/g, '/'),
            manifest: path.relative(ROOT, MANIFEST_PATH).replace(/\\/g, '/')
        },
        catalog: {
            rawUnitCount: Array.isArray(units) ? units.length : 0,
            uniquePortraitRefCount: refs.length,
            blankPortraitRefCount: blank,
            caseFoldCollisionGroups: caseFoldCollisions,
            portraitRoutes: {
                dressup: {
                    total: dressupReadyRefs.length + dressupMissingRefs.length,
                    ready: dressupReadyRefs.length,
                    missing: dressupMissingRefs.length
                },
                enemyManifest: {
                    total: enemyRefs.length,
                    ready: readyRefs.length - dressupReadyRefs.length,
                    missing: missingRefs.length - dressupMissingRefs.length
                }
            }
        },
        coverage: {
            ready: readyRefs.length,
            missing: missingRefs.length,
            total: refs.length,
            aliasResolved,
            missingRefs,
            missingSample: missingRefs.slice(0, 20),
            missingByStatus,
            missingDetails,
            routes: {
                dressupReadyRefs,
                dressupMissingRefs,
                enemyRefs
            }
        },
        assets: {
            manifestIdentityCount: Object.keys(manifest.entries || {}).length,
            humanAcceptedVariantCount: acceptedVariantCount,
            checkedFileCount: checkedAssetCount,
            checkedBindingCount: checkedAssetCount,
            uniqueFileCount: checkedAssetFiles.size
        },
        baseline: PILOT_BASELINE,
        errors
    };

    if (refs.length !== PILOT_BASELINE.total) {
        errors.push(`catalog identity baseline changed: ${refs.length} != ${PILOT_BASELINE.total}`);
    }
    if (dressupReadyRefs.length !== 3 || dressupMissingRefs.length !== 0) {
        errors.push(`dressup portrait route drifted: ready=${dressupReadyRefs.length} missing=${dressupMissingRefs.length}`);
    }
    if (readyRefs.length < PILOT_BASELINE.ready) {
        errors.push(`ready coverage regressed: ${readyRefs.length} < ${PILOT_BASELINE.ready}`);
    }
    if (missingRefs.length > PILOT_BASELINE.missing) {
        errors.push(`fallback debt regressed: ${missingRefs.length} > ${PILOT_BASELINE.missing}`);
    }
    if (readyRefs.length + missingRefs.length !== refs.length) {
        errors.push('coverage partition mismatch');
    }
    return summary;
}

function main() {
    const args = new Set(process.argv.slice(2));
    const result = audit();
    if (args.has('--json')) {
        process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    } else {
        process.stdout.write(
            `Arena portrait coverage: ${result.coverage.ready}/${result.coverage.total} ready, ` +
            `${result.coverage.missing} locked fallback; ` +
            `${result.assets.checkedBindingCount} accepted asset bindings / ` +
            `${result.assets.uniqueFileCount} unique files verified.\n`
        );
        if (result.catalog.caseFoldCollisionGroups.length) {
            process.stdout.write(`Case-sensitive identity groups: ${JSON.stringify(result.catalog.caseFoldCollisionGroups)}\n`);
        }
        process.stdout.write(`Fallback debt: ${Object.entries(result.coverage.missingByStatus)
            .map(([status, count]) => `${status}=${count}`).join(', ')}\n`);
        if (result.errors.length) {
            for (const error of result.errors) process.stderr.write(`ERROR: ${error}\n`);
        }
    }
    if (args.has('--check') && result.errors.length) process.exitCode = 1;
}

main();
