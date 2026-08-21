'use strict';

const crypto = require('crypto');
const fs = require('fs');

const VIRTUAL_FONT_ORIGIN = 'https://cfn-fonts.local/';

function cssFamily(value) {
    return `"${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

function cssVariable(roleId) {
    return `--cf7-font-${roleId.replace(/\./g, '-')}`;
}

function collectRoleCandidates(role, maps) {
    const faces = [];
    const system = [];
    const generic = [];
    const visited = new Set();

    function appendUnique(list, key, value) {
        if (!list.some((item) => item[key] === value[key])) list.push(value);
    }

    function visit(current) {
        if (!current || visited.has(current.id)) return;
        visited.add(current.id);
        for (const use of current.uses) {
            if (!faces.includes(use.face)) faces.push(use.face);
        }
        for (const fallback of current.roleFallbacks) visit(maps.rolesById.get(fallback.role));
        for (const fallback of current.systemFallbacks) {
            appendUnique(system, 'family', {
                family: fallback.family,
                classification: fallback.classification,
            });
        }
        for (const fallback of current.genericFallbacks) {
            appendUnique(generic, 'family', {
                family: fallback.family,
                classification: fallback.classification,
            });
        }
    }

    visit(role);
    return { faces, system, generic };
}

function buildRuntimeProjection(catalog, maps) {
    const sourceSha256 = crypto.createHash('sha256').update(fs.readFileSync(catalog.file)).digest('hex');
    const groups = {};
    for (const group of catalog.groups || []) {
        groups[group.id] = {
            id: group.id,
            label: group.label,
            description: group.description,
        };
    }
    for (const asset of catalog.fonts) {
        if (!groups[asset.group]) {
            groups[asset.group] = {
                id: asset.group,
                label: asset.group,
                description: asset.group,
            };
        }
    }
    const faces = {};
    const assets = catalog.fonts.map((asset) => {
        const expected = asset.integrity || asset.downloads[0] || null;
        for (const face of asset.faces) {
            faces[face.id] = {
                id: face.id,
                asset: asset.id,
                alias: `CF7Face--${face.id}`,
                family: face.family,
                weight: face.weight,
                style: face.style,
                stretch: face.stretch,
                classification: face.classification,
            };
        }
        return {
            id: asset.id,
            label: asset.label,
            file: asset.file,
            format: asset.format,
            targets: [...asset.targets],
            license: asset.license,
            group: asset.group,
            residency: asset.residency,
            shippedFallback: asset.shippedFallback,
            bytes: expected ? expected.bytes : null,
            sha256: expected ? expected.sha256 : null,
            faces: asset.faces.map((face) => face.id),
            downloads: [...asset.downloads]
                .sort((left, right) => left.priority - right.priority)
                .map((download) => ({
                    priority: download.priority,
                    url: download.url,
                    bytes: download.bytes,
                    sha256: download.sha256,
                })),
        };
    });

    const roles = {};
    for (const role of catalog.roles) {
        const candidates = collectRoleCandidates(role, maps);
        roles[role.id] = {
            id: role.id,
            label: role.label,
            status: role.status,
            allowPresetOverride: role.allowPresetOverride,
            faces: candidates.faces,
            system: candidates.system,
            generic: candidates.generic,
        };
    }

    const presets = {};
    for (const preset of catalog.presets) {
        presets[preset.id] = {
            id: preset.id,
            label: preset.label,
            status: preset.status,
            binds: Object.fromEntries(preset.binds.map((bind) => [bind.role, bind.face])),
        };
    }

    const legacyFamilies = {};
    for (const family of catalog.rawFamilies) {
        if (!family.role) continue;
        for (const name of [family.name, ...family.aliases.map((alias) => alias.name)]) {
            legacyFamilies[name.trim().toLocaleLowerCase('en-US')] = family.role;
        }
    }

    return {
        schemaVersion: 1,
        catalogVersion: catalog.version,
        gate: catalog.gate,
        runtimeAuthority: catalog.runtimeAuthority,
        sourceSha256,
        virtualFontOrigin: VIRTUAL_FONT_ORIGIN,
        allowedHosts: catalog.allowedHosts.map((item) => item.name.toLowerCase()),
        groups,
        assets,
        faces,
        roles,
        presets,
        legacyFamilies,
    };
}

function roleStack(projection, roleId, presetIds = []) {
    const role = projection.roles[roleId];
    if (!role) return null;
    let override = null;
    for (const presetId of presetIds || []) {
        const preset = projection.presets[presetId];
        if (preset && preset.binds[roleId]) override = preset.binds[roleId];
    }
    const orderedFaces = [];
    if (override) orderedFaces.push(override);
    for (const faceId of role.faces) if (!orderedFaces.includes(faceId)) orderedFaces.push(faceId);
    return [
        ...orderedFaces.map((faceId) => cssFamily(projection.faces[faceId].alias)),
        ...role.system.map((item) => cssFamily(item.family)),
        ...role.generic.map((item) => item.family),
    ].join(', ');
}

module.exports = {
    VIRTUAL_FONT_ORIGIN,
    buildRuntimeProjection,
    collectRoleCandidates,
    cssFamily,
    cssVariable,
    roleStack,
};
