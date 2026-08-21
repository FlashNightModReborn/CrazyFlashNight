'use strict';

const { diagnostic, sortDiagnostics } = require('./catalog');
const { SOURCE_DIRECTORIES, scanFontDirectories } = require('./scan');

function resolveRole(catalog, maps, fontRoot, roleId, presetId = null) {
    const diagnostics = [];
    const add = (code, message, detail = {}) => diagnostics.push(diagnostic(
        code,
        message,
        catalog.file,
        { line: 0, column: 0, ...detail },
    ));
    const role = maps.rolesById.get(roleId);
    if (!role) {
        add('UNKNOWN_ROLE', `未知 role：${roleId || '(未提供)'}`, { role: roleId });
        return { candidates: [], selected: null, diagnostics: sortDiagnostics(diagnostics), scan: null };
    }

    let preset = null;
    if (presetId) {
        preset = maps.presetsById.get(presetId);
        if (!preset) add('UNKNOWN_PRESET', `未知 preset：${presetId}`, { preset: presetId });
    }
    const binding = preset ? preset.binds.find((item) => item.role === roleId) : null;
    if (preset && !binding) add('PRESET_ROLE_UNBOUND', `preset ${presetId} 没有绑定 role ${roleId}`, { preset: presetId, role: roleId });

    const faceOrder = [];
    const fallbackCandidates = [];
    const expandedRoles = new Set();
    function collectRole(currentRole, reason, isRoot) {
        if (!currentRole || expandedRoles.has(currentRole.id)) return;
        expandedRoles.add(currentRole.id);
        if (isRoot && binding) faceOrder.push({ face: binding.face, reason: 'preset-override' });
        for (const use of currentRole.uses) {
            if (!faceOrder.some((item) => item.face === use.face)) {
                faceOrder.push({ face: use.face, reason: isRoot ? 'role-candidate' : reason });
            }
        }
        for (const fallback of currentRole.roleFallbacks) {
            collectRole(maps.rolesById.get(fallback.role), `role-fallback:${fallback.role}`, false);
        }
        for (const item of currentRole.systemFallbacks) {
            fallbackCandidates.push({ source: 'system-fallback', family: item.family, classification: item.classification, available: null, eligible: true, integrity: 'not-probed', reason: isRoot ? 'declared-system-fallback' : reason });
        }
        for (const item of currentRole.genericFallbacks) {
            fallbackCandidates.push({ source: 'generic-fallback', family: item.family, classification: item.classification, available: null, eligible: true, integrity: 'not-probed', reason: isRoot ? 'declared-generic-fallback' : reason });
        }
    }
    collectRole(role, 'role-candidate', true);

    const scan = scanFontDirectories(catalog, fontRoot);
    diagnostics.push(...scan.diagnostics.filter((item) => item.severity === 'error'));
    const filesBySource = new Map(SOURCE_DIRECTORIES.map((entry) => [entry.source, []]));
    for (const file of scan.files) filesBySource.get(file.source).push(file);
    const candidates = [];

    for (const source of SOURCE_DIRECTORIES.map((entry) => entry.source)) {
        for (const faceEntry of faceOrder) {
            const face = maps.facesById.get(faceEntry.face);
            const asset = maps.faceOwners.get(faceEntry.face);
            if (!face || !asset) {
                add('BROKEN_FACE_REF', `role ${roleId} 的候选 face 不存在：${faceEntry.face}`, { role: roleId, ref: faceEntry.face });
                continue;
            }
            const matches = (filesBySource.get(source) || []).filter((file) => file.file.toLowerCase() === asset.file.toLowerCase());
            if (matches.length > 1) {
                add('AMBIGUOUS_LOCAL_FONT', `${source} 中有多个 ${asset.file}，无法确定候选`, { role: roleId, face: face.id, source });
            }
            const local = matches.length === 1 ? matches[0] : null;
            let integrity = 'missing';
            let eligible = false;
            if (local) {
                if (!local.validFont) {
                    integrity = 'invalid-font';
                } else if (source === 'temporary/custom') {
                    integrity = 'custom-override';
                    eligible = true;
                } else {
                    const expected = asset.integrity || asset.downloads[0] || null;
                    if (!expected) {
                        integrity = 'undeclared';
                        add('LOCAL_FONT_INTEGRITY_UNDECLARED', `${source}/${local.relative} 没有可复核的 asset integrity`, {
                            role: roleId,
                            face: face.id,
                            source,
                        });
                    } else {
                        const valid = local.bytes === expected.bytes && local.sha256 === expected.sha256;
                        integrity = valid ? 'verified' : 'mismatch';
                        eligible = valid;
                        if (!valid) {
                            add('LOCAL_FONT_INTEGRITY', `${source}/${local.relative} 与 fonts.xml 完整性不一致`, {
                                role: roleId,
                                face: face.id,
                                source,
                                expectedBytes: expected.bytes,
                                actualBytes: local.bytes,
                                expectedSha256: expected.sha256,
                                actualSha256: local.sha256,
                            });
                        }
                    }
                }
            }
            candidates.push({
                source,
                face: face.id,
                family: face.family,
                asset: asset.id,
                file: asset.file,
                relative: local ? local.relative : asset.file,
                available: Boolean(local),
                validFont: local ? local.validFont : null,
                eligible,
                integrity,
                reason: faceEntry.reason,
            });
        }
    }

    candidates.push(...fallbackCandidates);

    return {
        candidates,
        selected: candidates.find((item) => item.eligible) || null,
        diagnostics: sortDiagnostics(diagnostics),
        scan: { fileCount: scan.files.length },
    };
}

module.exports = { resolveRole };
