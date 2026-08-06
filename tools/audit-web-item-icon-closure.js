#!/usr/bin/env node
'use strict';

// Web 可见物品图标闭包审计：
//   - 任务 catalog itemReqs/rewards
//   - 成就原始 rewards（含 hidden，避免 catalog 脱敏后漏审）
//   - 情报物品 XML（IntelligenceTask 从 data/items 取 iconName）
//   - 装备插件 mod 内部名 -> 物品 displayname/icon -> Web manifest/文件闭包
// 均必须指向 launcher/web/icons/manifest.json 中存在的 icon key。

const fs = require('fs');
const path = require('path');
const { loadItemMeta, itemIcon } = require('./lib/item-icons.js');

const projectRoot = path.resolve(__dirname, '..');
const manifestPath = path.join(projectRoot, 'launcher', 'web', 'icons', 'manifest.json');
const taskCatalogPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'tasks', 'task-catalog.json');
const achievementDir = path.join(projectRoot, 'data', 'achievement');
const equipmentModDir = path.join(projectRoot, 'data', 'items', 'equipment_mods');
const iconDir = path.dirname(manifestPath);
const identityFixturePath = path.join(projectRoot, 'tools', 'equipment-tuning', 'fixtures',
    'item-identity-triple.json');

function fail(msg) {
    console.error('[audit-web-item-icon-closure] ' + msg);
    process.exit(1);
}

const requiredWebIdentityProbes = [
    'malformed identity never falls back to internal name or icon',
    'three all-distinct identity fixtures preserve display and icon roles'
];

function hasRequiredWebIdentityProbes(source) {
    return requiredWebIdentityProbes.every(marker => source.includes(marker));
}

function auditWebIdentityProbeMutationGuard(source) {
    let detected = 0;
    for (const marker of requiredWebIdentityProbes) {
        const mutant = source.replace(marker, '[mutated-web-identity-probe]');
        if (mutant === source || hasRequiredWebIdentityProbes(mutant)) {
            fail('Web identity probe mutation guard is ineffective for: ' + marker);
        }
        detected += 1;
    }
    return detected;
}

function readText(file) {
    try {
        return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
    } catch (e) {
        fail('cannot read ' + file + ': ' + e.message);
    }
}

function readJson(file) {
    try {
        return JSON.parse(readText(file));
    } catch (e) {
        fail('invalid JSON in ' + file + ': ' + e.message);
    }
}

function readManifest(listFile, tagName) {
    const raw = readText(listFile);
    const re = new RegExp('<' + tagName + '>\\s*([^<]+?)\\s*</' + tagName + '>', 'g');
    const out = [];
    let m;
    while ((m = re.exec(raw)) !== null) out.push(m[1]);
    if (out.length === 0) fail('manifest ' + listFile + ' has no <' + tagName + '> entries');
    return out;
}

function childText(xml, tagName) {
    const re = new RegExp('<' + tagName + '>\\s*([\\s\\S]*?)\\s*</' + tagName + '>');
    const m = re.exec(String(xml || ''));
    return m ? m[1].trim()
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&') : '';
}

function parseReward(raw, ctx, metaByName) {
    const parts = String(raw).split('#');
    const name = parts[0];
    return { ctx, name, icon: itemIcon(metaByName, name) };
}

function pushMissing(out, manifest, ctx, name, icon) {
    if (!icon || manifest[icon]) return;
    out.push({ ctx, name, icon });
}

function auditTaskCatalog(manifest, metaByName, missing) {
    const payload = readJson(taskCatalogPath);
    const tasks = payload.tasks || {};
    for (const id of Object.keys(tasks)) {
        const t = tasks[id] || {};
        for (const stack of (t.itemReqs || [])) {
            const name = stack.name || '';
            const icon = stack.icon || itemIcon(metaByName, name);
            pushMissing(missing, manifest, 'task ' + id + ' itemReqs', name, icon);
        }
        for (const stack of (t.rewards || [])) {
            const name = stack.name || '';
            const icon = stack.icon || itemIcon(metaByName, name);
            pushMissing(missing, manifest, 'task ' + id + ' rewards', name, icon);
        }
    }
}

function auditAchievements(manifest, metaByName, missing) {
    const files = readManifest(path.join(achievementDir, 'list.xml'), 'achievement');
    for (const rel of files) {
        const data = readJson(path.join(achievementDir, rel));
        const arr = data && Array.isArray(data.achievements) ? data.achievements : [];
        for (const ach of arr) {
            const id = ach && ach.id != null ? String(ach.id) : '<unknown>';
            const rewards = ach && Array.isArray(ach.rewards) ? ach.rewards : [];
            for (let i = 0; i < rewards.length; i += 1) {
                const r = parseReward(rewards[i], 'achievement ' + id + ' rewards[' + i + ']', metaByName);
                pushMissing(missing, manifest, r.ctx, r.name, r.icon);
            }
        }
    }
}

function auditIntelligence(manifest, metaByName, missing) {
    const names = Object.keys(metaByName);
    for (const name of names) {
        const meta = metaByName[name];
        if (!meta || meta.use !== '情报') continue;
        const icon = meta.icon || name;
        pushMissing(missing, manifest, 'intelligence item ' + name, name, icon);
    }
}

function manifestImageUris(entry, out) {
    out = out || [];
    if (typeof entry === 'string') {
        if (/\.(?:png|webp|gif|jpe?g)$/i.test(entry) && out.indexOf(entry) < 0) out.push(entry);
        return out;
    }
    if (!entry || typeof entry !== 'object') return out;
    for (const key of Object.keys(entry)) manifestImageUris(entry[key], out);
    return out;
}

function auditEquipmentMods(manifest, metaByName, missing) {
    const identityFixture = readJson(identityFixturePath);
    const expectedCounts = identityFixture.expectedCounts || {};
    const expectedAllDistinct = Array.isArray(identityFixture.allDistinct)
        ? identityFixture.allDistinct : [];
    if (identityFixture.schemaVersion !== 1
            || identityFixture.domain !== 'equipment_tuning.modCandidates') {
        fail('identity fixture schema/domain is not canonical v1 equipment tuning');
    }
    const fixtureKeys = new Set();
    const fixtureNames = new Set();
    for (const fixture of expectedAllDistinct) {
        if (!fixture || !/^[A-Za-z0-9._~-]{1,128}$/.test(fixture.candidateKey || '')
                || !fixture.itemName || !fixture.displayName || !fixture.icon
                || fixture.itemName === fixture.displayName
                || fixture.itemName === fixture.icon
                || fixture.displayName === fixture.icon
                || fixtureKeys.has(fixture.candidateKey)
                || fixtureNames.has(fixture.itemName)) {
            fail('identity fixture contains a malformed or duplicate all-distinct row');
        }
        fixtureKeys.add(fixture.candidateKey);
        fixtureNames.add(fixture.itemName);
    }
    const files = readManifest(path.join(equipmentModDir, 'list.xml'), 'items');
    const seen = Object.create(null);
    let modCount = 0;
    let presentationAliases = 0;
    let iconKeyDivergence = 0;
    let legacyInternalIconMisses = 0;
    const allDistinct = [];
    for (const rel of files) {
        const raw = readText(path.join(equipmentModDir, rel));
        const modRe = /<mod\b[^>]*>([\s\S]*?)<\/mod>/g;
        let match;
        while ((match = modRe.exec(raw)) !== null) {
            const name = childText(match[1], 'name');
            if (!name) fail('equipment mod without <name> in ' + rel);
            if (seen[name]) fail('duplicate equipment mod name ' + name + ' in ' + seen[name] + ' and ' + rel);
            seen[name] = rel;
            modCount += 1;
            const meta = metaByName[name];
            if (!meta) {
                missing.push({ctx:'equipment mod ' + rel, name, icon:'<missing item data>', reason:'item_missing'});
                continue;
            }
            const icon = itemIcon(metaByName, name);
            const displayName = meta.displayname || name;
            if (displayName !== name || icon !== name) presentationAliases += 1;
            if (icon !== name) {
                iconKeyDivergence += 1;
                if (!manifest[name]) legacyInternalIconMisses += 1;
            }
            if (name !== displayName && name !== icon && displayName !== icon) {
                allDistinct.push({itemName:name, displayName, icon});
            }
            pushMissing(missing, manifest, 'equipment mod ' + rel, name, icon);
            const entry = manifest[icon];
            if (!entry) continue;
            const uris = manifestImageUris(entry);
            if (uris.length === 0) {
                missing.push({ctx:'equipment mod ' + rel, name, icon, reason:'manifest_has_no_image'});
                continue;
            }
            for (const uri of uris) {
                const resolved = path.resolve(iconDir, uri);
                const relative = path.relative(iconDir, resolved);
                if (relative.startsWith('..') || path.isAbsolute(relative) || !fs.existsSync(resolved)) {
                    missing.push({ctx:'equipment mod ' + rel, name, icon,
                        reason:'asset_missing', asset:uri});
                }
            }
        }
    }
    if (modCount === 0) fail('equipment mod manifest contains no <mod> definitions');

    const actualCounts = {
        mods:modCount,
        presentationAliases,
        iconKeyDivergence,
        allDistinct:allDistinct.length,
        legacyInternalIconMisses
    };
    for (const key of Object.keys(actualCounts)) {
        if (actualCounts[key] !== expectedCounts[key]) {
            fail('identity count drift for ' + key + ': expected '
                + expectedCounts[key] + ', got ' + actualCounts[key]);
        }
    }
    if (expectedAllDistinct.length !== 3) {
        fail('identity fixture must freeze exactly three all-distinct rows');
    }
    for (const expected of expectedAllDistinct) {
        const actual = allDistinct.find(row => row.itemName === expected.itemName);
        if (!actual || actual.displayName !== expected.displayName || actual.icon !== expected.icon) {
            fail('all-distinct fixture drift for ' + expected.itemName);
        }
    }

    // 这道 release-policy 静态门与 browser harness 的动态反例共同锁定“三名分离”协议。
    const service = readText(path.join(projectRoot, 'scripts', '类定义', 'org', 'flashNight',
        'arki', 'item', 'EquipmentTuningService.as'));
    const renderer = readText(path.join(projectRoot, 'launcher', 'web', 'modules',
        'equipment-tuning-render.js'));
    const serviceTest = readText(path.join(projectRoot, 'scripts', '类定义', 'org', 'flashNight',
        'arki', 'item', 'EquipmentTuningServiceTest.as'));
    const hostTest = readText(path.join(projectRoot, 'launcher', 'tests', 'Tasks',
        'EquipmentTuningTaskTests.cs'));
    const webHarness = readText(path.join(projectRoot, 'launcher', 'web', 'modules',
        'equipment-tuning', 'dev', 'harness.html'));
    if (!service.includes('displayName:presentation.displayName')
            || !service.includes('icon:presentation.icon')
            || !renderer.includes('candidateDisplayName(candidate')
            || !renderer.includes('candidateIconName(candidate')) {
        fail('equipment tuning itemName/displayName/icon projection contract is missing');
    }
    for (const fixture of expectedAllDistinct) {
        for (const source of [serviceTest, hostTest, webHarness]) {
            if (!source.includes(fixture.itemName)
                    || !source.includes(fixture.displayName)
                    || !source.includes(fixture.icon)) {
                fail('cross-language all-distinct fixture missing for ' + fixture.itemName);
            }
        }
    }
    const displayHelper = renderer.slice(
        renderer.indexOf('function candidateDisplayName'),
        renderer.indexOf('function candidateIconName'));
    const iconHelper = renderer.slice(
        renderer.indexOf('function candidateIconName'),
        renderer.indexOf('function iconHtml'));
    if (displayHelper.includes('candidate.itemName')
            || displayHelper.includes('candidate.candidateKey')
            || iconHelper.includes('candidate.itemName')
            || iconHelper.includes('candidate.candidateKey')) {
        fail('Web candidate presentation must not guess display/icon from internal identity');
    }
    for (const marker of ['missing-display-name', 'wrong-icon-type', 'legacy-display-alias']) {
        if (!hostTest.includes(marker)) {
            fail('executable Host malformed identity case missing: ' + marker);
        }
    }
    if (!hasRequiredWebIdentityProbes(webHarness)) {
        fail('executable Web identity positive/negative probes are missing');
    }
    const webIdentityMutationsDetected = auditWebIdentityProbeMutationGuard(webHarness);
    return {modCount, presentationAliases, iconKeyDivergence,
        allDistinct, legacyInternalIconMisses, webIdentityMutationsDetected};
}

function main() {
    const manifest = readJson(manifestPath);
    const metaByName = loadItemMeta(projectRoot, fail);
    const missing = [];

    auditTaskCatalog(manifest, metaByName, missing);
    auditAchievements(manifest, metaByName, missing);
    auditIntelligence(manifest, metaByName, missing);
    const equipmentMods = auditEquipmentMods(manifest, metaByName, missing);

    if (missing.length > 0) {
        console.error('[audit-web-item-icon-closure] broken item icon closure: ' + missing.length);
        for (const m of missing.slice(0, 50)) {
            console.error('  - ' + m.ctx + ': ' + m.name + ' -> ' + m.icon
                + (m.reason ? ' [' + m.reason + ']' : '') + (m.asset ? ' ' + m.asset : ''));
        }
        if (missing.length > 50) console.error('  ... +' + (missing.length - 50) + ' more');
        process.exit(1);
    }

    console.log('[audit-web-item-icon-closure] identity counts:'
        + ' mods=' + equipmentMods.modCount
        + ' aliases=' + equipmentMods.presentationAliases
        + ' icon-divergence=' + equipmentMods.iconKeyDivergence
        + ' all-distinct=' + equipmentMods.allDistinct.length
        + ' legacy-internal-icon-misses=' + equipmentMods.legacyInternalIconMisses
        + ' web-probe-mutations-detected=' + equipmentMods.webIdentityMutationsDetected
        + '/' + requiredWebIdentityProbes.length);
    equipmentMods.allDistinct.forEach((row, index) => {
        console.log('[audit-web-item-icon-closure] identity fixture ' + (index + 1)
            + ': internal=' + row.itemName + ' | display=' + row.displayName
            + ' | icon=' + row.icon);
    });
    console.log('[audit-web-item-icon-closure] OK: task/achievement/intelligence/equipment-mod item icons resolve');
}

main();
