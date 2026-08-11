#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const {
    DRESSUP_EQUIPMENT_FIELDS,
    DRESSUP_MANIFEST_PATH,
    LEGACY_EQUIPMENT_ALIASES,
    inspectDressupPortrait,
    isDressupPortraitRef
} = require('./lib/arena-portrait-routing');

const ROOT = path.resolve(__dirname, '..');
const UNITS_PATH = path.join(ROOT, 'data', 'units', 'units.json');
const MANIFEST_PATH = path.join(ROOT, 'launcher', 'web', 'assets', 'enemy-portraits', 'manifest.json');
const WEB_ROOT = path.join(ROOT, 'launcher', 'web');
const EXPECTED_CLOSURE = Object.freeze({
    total: 217,
    ready: 217,
    missing: 0,
    dressupTotal: 3,
    dressupReady: 3,
    dressupMissing: 0,
    enemyTotal: 214,
    enemyReady: 214,
    enemyMissing: 0,
    humanAcceptedVariantCount: 222,
    checkedBindingCount: 444,
    uniqueFileCount: 442,
    legacyEquipmentAliasDefinitionCount: 4,
    legacyEquipmentAliasOccurrenceCount: 8,
    legacyVirtualItemDefinitionCount: 4,
    legacyVirtualItemOccurrenceCount: 4,
    legacyVirtualSkinKeyCount: 10,
    legacyCompatibilityCheckCount: 20
});
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

function exact(errors, label, actual, expected) {
    if (actual !== expected) errors.push(`${label}: ${actual} != ${expected}`);
}

function audit(options) {
    options = options || {};
    const errors = [];
    const units = options.units || readJson(UNITS_PATH);
    const manifest = options.enemyManifest || readJson(MANIFEST_PATH);
    const dressupManifest = options.dressupManifest || readJson(DRESSUP_MANIFEST_PATH);
    if (!Array.isArray(units)) errors.push('data/units/units.json must be an array');
    if (!SUPPORTED_SCHEMAS.has(manifest.schema)) errors.push(`unsupported manifest schema: ${manifest.schema || '<blank>'}`);
    if (!manifest.entries || typeof manifest.entries !== 'object') errors.push('manifest entries missing');
    if (!dressupManifest || dressupManifest.schema !== 'cf7-dressup-manifest-v1') {
        errors.push(`unsupported dressup manifest schema: ${(dressupManifest && dressupManifest.schema) || '<blank>'}`);
    }

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
    const dressupProjectionErrors = [];
    const dressupAliasApplications = [];
    const dressupVirtualApplications = [];
    const enemyRefs = [];
    for (const ref of refs) {
        if (!isDressupPortraitRef(ref)) {
            enemyRefs.push(ref);
            continue;
        }
        const matchingUnits = unitsByRef.get(ref) || [];
        let ready = matchingUnits.length > 0;
        for (const unit of matchingUnits) {
            const inspected = inspectDressupPortrait(unit, { manifest: dressupManifest });
            for (const alias of inspected.aliases) {
                dressupAliasApplications.push(Object.assign({ unitId: unit.id, portraitRef: ref }, alias));
            }
            if (!inspected.portrait) {
                ready = false;
                dressupProjectionErrors.push({ unitId: unit.id, portraitRef: ref, issues: inspected.issues });
            }
            for (const field of DRESSUP_EQUIPMENT_FIELDS) {
                const raw = String(unit && unit.data && unit.data[field] || '').split('#', 1)[0].trim();
                const item = raw && dressupManifest.items && dressupManifest.items[raw];
                if (item && item.virtual === true) {
                    dressupVirtualApplications.push({ unitId: unit.id, portraitRef: ref, field, item: raw });
                }
            }
        }
        if (ready) dressupReadyRefs.push(ref);
        else dressupMissingRefs.push(ref);
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
                const file = localAssetPath(binding.url);
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

    const dressupRoute = {
        total: dressupReadyRefs.length + dressupMissingRefs.length,
        ready: dressupReadyRefs.length,
        missing: dressupMissingRefs.length
    };
    const enemyRoute = {
        total: enemyRefs.length,
        ready: readyRefs.length - dressupReadyRefs.length,
        missing: missingRefs.length - dressupMissingRefs.length
    };
    const legacyVirtualItems = Object.entries(dressupManifest.items || {})
        .filter(([, item]) => item && item.virtual === true && Number(item.sourceUnitId) === 235);
    const legacyVirtualSkinKeys = new Set();
    for (const [itemName, item] of legacyVirtualItems) {
        for (const fields of Object.values(item.fieldsByGender || {})) {
            for (const skinKey of Object.values(fields || {})) {
                legacyVirtualSkinKeys.add(skinKey);
                const skin = dressupManifest.skinKeys && dressupManifest.skinKeys[skinKey];
                if (!skin || skin.covered !== true || !skin.export || !skin.export.uri) {
                    errors.push(`Arena legacy virtual skin is not runtime-exported: ${itemName} -> ${skinKey}`);
                }
            }
        }
    }
    const legacyAliasDefinitionCount = Object.keys(LEGACY_EQUIPMENT_ALIASES).length;
    const legacyAliasOccurrenceCount = dressupAliasApplications.filter(item => item.kind === 'equipment').length;
    const legacyCompatibilityCheckCount = legacyAliasDefinitionCount + legacyAliasOccurrenceCount
        + legacyVirtualItems.length + dressupVirtualApplications.length;
    const summary = {
        schema: 'cf7.arena-portrait-coverage-audit.v2',
        source: {
            units: path.relative(ROOT, UNITS_PATH).replace(/\\/g, '/'),
            enemyManifest: path.relative(ROOT, MANIFEST_PATH).replace(/\\/g, '/'),
            dressupManifest: path.relative(ROOT, DRESSUP_MANIFEST_PATH).replace(/\\/g, '/')
        },
        catalog: {
            rawUnitCount: Array.isArray(units) ? units.length : 0,
            uniquePortraitRefCount: refs.length,
            blankPortraitRefCount: blank,
            caseFoldCollisionGroups: caseFoldCollisions,
            portraitRoutes: { dressup: dressupRoute, enemyManifest: enemyRoute }
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
            routes: { dressupReadyRefs, dressupMissingRefs, enemyRefs }
        },
        dressup: {
            legacyEquipmentAliasDefinitionCount: legacyAliasDefinitionCount,
            legacyEquipmentAliasOccurrenceCount: legacyAliasOccurrenceCount,
            legacyVirtualItemDefinitionCount: legacyVirtualItems.length,
            legacyVirtualItemOccurrenceCount: dressupVirtualApplications.length,
            legacyVirtualSkinKeyCount: legacyVirtualSkinKeys.size,
            legacyCompatibilityCheckCount,
            aliasApplications: dressupAliasApplications,
            virtualApplications: dressupVirtualApplications,
            projectionErrors: dressupProjectionErrors
        },
        assets: {
            manifestIdentityCount: Object.keys(manifest.entries || {}).length,
            humanAcceptedVariantCount: acceptedVariantCount,
            checkedFileCount: checkedAssetCount,
            checkedBindingCount: checkedAssetCount,
            uniqueFileCount: checkedAssetFiles.size
        },
        expected: EXPECTED_CLOSURE,
        errors
    };

    exact(errors, 'catalog identity closure changed', refs.length, EXPECTED_CLOSURE.total);
    exact(errors, 'ready coverage closure changed', readyRefs.length, EXPECTED_CLOSURE.ready);
    exact(errors, 'missing coverage closure changed', missingRefs.length, EXPECTED_CLOSURE.missing);
    exact(errors, 'dressup identity closure changed', dressupRoute.total, EXPECTED_CLOSURE.dressupTotal);
    exact(errors, 'dressup ready closure changed', dressupRoute.ready, EXPECTED_CLOSURE.dressupReady);
    exact(errors, 'dressup missing closure changed', dressupRoute.missing, EXPECTED_CLOSURE.dressupMissing);
    exact(errors, 'enemy identity closure changed', enemyRoute.total, EXPECTED_CLOSURE.enemyTotal);
    exact(errors, 'enemy ready closure changed', enemyRoute.ready, EXPECTED_CLOSURE.enemyReady);
    exact(errors, 'enemy missing closure changed', enemyRoute.missing, EXPECTED_CLOSURE.enemyMissing);
    exact(errors, 'human-accepted variant closure changed', acceptedVariantCount, EXPECTED_CLOSURE.humanAcceptedVariantCount);
    exact(errors, 'accepted binding closure changed', checkedAssetCount, EXPECTED_CLOSURE.checkedBindingCount);
    exact(errors, 'unique accepted file closure changed', checkedAssetFiles.size, EXPECTED_CLOSURE.uniqueFileCount);
    exact(errors, 'legacy equipment alias definition closure changed', summary.dressup.legacyEquipmentAliasDefinitionCount,
        EXPECTED_CLOSURE.legacyEquipmentAliasDefinitionCount);
    exact(errors, 'legacy equipment alias occurrence closure changed', summary.dressup.legacyEquipmentAliasOccurrenceCount,
        EXPECTED_CLOSURE.legacyEquipmentAliasOccurrenceCount);
    exact(errors, 'legacy virtual item definition closure changed', summary.dressup.legacyVirtualItemDefinitionCount,
        EXPECTED_CLOSURE.legacyVirtualItemDefinitionCount);
    exact(errors, 'legacy virtual item occurrence closure changed', summary.dressup.legacyVirtualItemOccurrenceCount,
        EXPECTED_CLOSURE.legacyVirtualItemOccurrenceCount);
    exact(errors, 'legacy virtual skin-key closure changed', summary.dressup.legacyVirtualSkinKeyCount,
        EXPECTED_CLOSURE.legacyVirtualSkinKeyCount);
    exact(errors, 'legacy compatibility regression closure changed', summary.dressup.legacyCompatibilityCheckCount,
        EXPECTED_CLOSURE.legacyCompatibilityCheckCount);
    if (readyRefs.length + missingRefs.length !== refs.length) errors.push('coverage partition mismatch');
    for (const projectionError of dressupProjectionErrors) {
        errors.push(`dressup projection rejected unit ${projectionError.unitId} (${projectionError.portraitRef}): ${JSON.stringify(projectionError.issues)}`);
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
            .map(([status, count]) => `${status}=${count}`).join(', ') || 'none'}\n`);
        if (result.errors.length) {
            for (const error of result.errors) process.stderr.write(`ERROR: ${error}\n`);
        }
    }
    if (args.has('--check') && result.errors.length) process.exitCode = 1;
}

if (require.main === module) main();

module.exports = {
    EXPECTED_CLOSURE,
    audit
};
