'use strict';

const fs = require('fs');
const path = require('path');
const { XmlSyntaxError, parseXml } = require('./xml');

const ID_PATTERN = /^[a-z0-9]+(?:[.-][a-z0-9]+)*$/;
const CLASSIFICATIONS = new Set(['migrate', 'compatibility', 'system-owned', 'path-glyph']);
const FORMATS = new Set(['ttf', 'otf', 'woff', 'woff2']);
const STYLES = new Set(['normal', 'italic', 'oblique']);
const STRETCHES = new Set([
    'ultra-condensed', 'extra-condensed', 'condensed', 'semi-condensed',
    'normal', 'semi-expanded', 'expanded', 'extra-expanded', 'ultra-expanded',
]);
const STATUSES = new Set(['pilot_pending', 'accepted', 'compatibility']);
const TARGETS = new Set(['web', 'native']);
const RESIDENCIES = new Set(['permanent', 'on-demand']);
const SEVERITY_ORDER = new Map([['error', 0], ['warning', 1], ['pilot-debt', 2]]);

function compareText(left, right) {
    return String(left || '').localeCompare(String(right || ''), 'en');
}

function diagnostic(code, message, file, detail = {}, severity = 'error') {
    return {
        severity,
        code,
        message,
        file,
        line: detail.line || 0,
        column: detail.column || 0,
        ...detail,
    };
}

function sortDiagnostics(items) {
    return [...items].sort((left, right) => (
        (SEVERITY_ORDER.get(left.severity) ?? 99) - (SEVERITY_ORDER.get(right.severity) ?? 99)
        || compareText(left.file, right.file)
        || (left.line || 0) - (right.line || 0)
        || (left.column || 0) - (right.column || 0)
        || compareText(left.code, right.code)
        || compareText(left.id, right.id)
        || compareText(left.ref, right.ref)
        || compareText(left.message, right.message)
    ));
}

function child(node, name) {
    return node ? node.children.find((item) => item.name === name) || null : null;
}

function children(node, name) {
    return node ? node.children.filter((item) => item.name === name) : [];
}

function attr(node, name, fallback = '') {
    if (!node || !Object.prototype.hasOwnProperty.call(node.attributes, name)) return fallback;
    return node.attributes[name];
}

function location(node, xmlPath, extra = {}) {
    return {
        line: node ? node.line : 0,
        column: node ? node.column : 0,
        xmlPath,
        ...extra,
    };
}

function parseBoolean(value) {
    if (value === 'true' || value === '1') return true;
    if (value === 'false' || value === '0') return false;
    return null;
}

function parseInteger(value) {
    if (!/^\d+$/.test(String(value))) return null;
    const result = Number(value);
    return Number.isSafeInteger(result) ? result : null;
}

function parseTargets(value) {
    return String(value || '').trim().split(/\s+/).filter(Boolean);
}

function loadCatalog(file) {
    const absoluteFile = path.resolve(file);
    const source = fs.readFileSync(absoluteFile, 'utf8');
    let root;
    try {
        root = parseXml(source, absoluteFile);
    } catch (error) {
        if (error instanceof XmlSyntaxError) {
            const wrapped = new Error(error.message);
            wrapped.diagnostic = diagnostic(error.code, error.message, absoluteFile, {
                line: error.line,
                column: error.column,
                xmlPath: '/',
            });
            throw wrapped;
        }
        throw error;
    }

    const downloadPolicyNode = child(root, 'downloadPolicy');
    const exclusionsNode = child(root, 'exclusions');
    const groupsNode = child(root, 'groups');
    const fontsNode = child(root, 'fonts');
    const rolesNode = child(root, 'roles');
    const presetsNode = child(root, 'presets');
    const rawFamiliesNode = child(root, 'rawFamilies');

    const allowedHosts = children(downloadPolicyNode, 'allowedHost').map((node, index) => ({
        name: attr(node, 'name'),
        node,
        xmlPath: `/fontCatalog/downloadPolicy/allowedHost[${index + 1}]`,
    }));
    const exclusions = children(exclusionsNode, 'path').map((node, index) => ({
        glob: attr(node, 'glob'),
        reason: attr(node, 'reason'),
        node,
        xmlPath: `/fontCatalog/exclusions/path[${index + 1}]`,
    }));
    const groups = children(groupsNode, 'group').map((node, index) => ({
        id: attr(node, 'id'),
        label: attr(node, 'label'),
        description: attr(node, 'description'),
        node,
        xmlPath: `/fontCatalog/groups/group[${index + 1}]`,
    }));
    const fonts = children(fontsNode, 'font').map((node, fontIndex) => {
        const xmlPath = `/fontCatalog/fonts/font[${fontIndex + 1}]`;
        const integrityNode = child(node, 'integrity');
        return {
            id: attr(node, 'id'),
            label: attr(node, 'label'),
            file: attr(node, 'file'),
            format: attr(node, 'format'),
            targets: parseTargets(attr(node, 'targets')),
            license: attr(node, 'license'),
            group: attr(node, 'group'),
            residency: attr(node, 'residency'),
            shippedFallback: parseBoolean(attr(node, 'shippedFallback')),
            node,
            xmlPath,
            integrity: integrityNode ? {
                bytes: parseInteger(attr(integrityNode, 'bytes')),
                sha256: attr(integrityNode, 'sha256'),
                node: integrityNode,
                xmlPath: `${xmlPath}/integrity`,
            } : null,
            faces: children(node, 'face').map((faceNode, faceIndex) => ({
                id: attr(faceNode, 'id'),
                family: attr(faceNode, 'family'),
                weight: parseInteger(attr(faceNode, 'weight')),
                style: attr(faceNode, 'style'),
                stretch: attr(faceNode, 'stretch'),
                classification: attr(faceNode, 'classification'),
                node: faceNode,
                xmlPath: `${xmlPath}/face[${faceIndex + 1}]`,
            })),
            downloads: children(node, 'download').map((downloadNode, downloadIndex) => ({
                priority: parseInteger(attr(downloadNode, 'priority')),
                url: attr(downloadNode, 'url'),
                bytes: parseInteger(attr(downloadNode, 'bytes')),
                sha256: attr(downloadNode, 'sha256'),
                node: downloadNode,
                xmlPath: `${xmlPath}/download[${downloadIndex + 1}]`,
            })),
        };
    });
    const roles = children(rolesNode, 'role').map((node, roleIndex) => {
        const xmlPath = `/fontCatalog/roles/role[${roleIndex + 1}]`;
        return {
            id: attr(node, 'id'),
            label: attr(node, 'label'),
            status: attr(node, 'status'),
            allowPresetOverride: parseBoolean(attr(node, 'allowPresetOverride')),
            node,
            xmlPath,
            uses: children(node, 'use').map((useNode, index) => ({
                face: attr(useNode, 'face'),
                node: useNode,
                xmlPath: `${xmlPath}/use[${index + 1}]`,
            })),
            roleFallbacks: children(node, 'roleFallback').map((fallbackNode, index) => ({
                role: attr(fallbackNode, 'role'),
                node: fallbackNode,
                xmlPath: `${xmlPath}/roleFallback[${index + 1}]`,
            })),
            systemFallbacks: children(node, 'systemFallback').map((fallbackNode, index) => ({
                family: attr(fallbackNode, 'family'),
                classification: attr(fallbackNode, 'classification'),
                node: fallbackNode,
                xmlPath: `${xmlPath}/systemFallback[${index + 1}]`,
            })),
            genericFallbacks: children(node, 'genericFallback').map((fallbackNode, index) => ({
                family: attr(fallbackNode, 'family'),
                classification: attr(fallbackNode, 'classification'),
                node: fallbackNode,
                xmlPath: `${xmlPath}/genericFallback[${index + 1}]`,
            })),
        };
    });
    const presets = children(presetsNode, 'preset').map((node, presetIndex) => {
        const xmlPath = `/fontCatalog/presets/preset[${presetIndex + 1}]`;
        return {
            id: attr(node, 'id'),
            label: attr(node, 'label'),
            status: attr(node, 'status'),
            node,
            xmlPath,
            binds: children(node, 'bind').map((bindNode, index) => ({
                role: attr(bindNode, 'role'),
                face: attr(bindNode, 'face'),
                node: bindNode,
                xmlPath: `${xmlPath}/bind[${index + 1}]`,
            })),
        };
    });
    const rawFamilies = children(rawFamiliesNode, 'family').map((node, familyIndex) => {
        const xmlPath = `/fontCatalog/rawFamilies/family[${familyIndex + 1}]`;
        return {
            name: attr(node, 'name'),
            classification: attr(node, 'classification'),
            role: attr(node, 'role') || null,
            node,
            xmlPath,
            aliases: children(node, 'alias').map((aliasNode, index) => ({
                name: attr(aliasNode, 'name'),
                node: aliasNode,
                xmlPath: `${xmlPath}/alias[${index + 1}]`,
            })),
        };
    });

    return {
        file: absoluteFile,
        source,
        root,
        version: attr(root, 'version'),
        gate: attr(root, 'gate'),
        runtimeAuthority: parseBoolean(attr(root, 'runtimeAuthority')),
        allowedHosts,
        exclusions,
        groups,
        fonts,
        roles,
        presets,
        rawFamilies,
    };
}

function expectedTarget(roleId) {
    if (roleId.startsWith('native.')) return 'native';
    if (roleId.startsWith('web.')) return 'web';
    return null;
}

function validateCatalog(catalog) {
    const diagnostics = [];
    const add = (code, message, item, extra = {}, severity = 'error') => {
        diagnostics.push(diagnostic(
            code,
            message,
            catalog.file,
            location(item && item.node, item && item.xmlPath, extra),
            severity,
        ));
    };

    if (catalog.root.name !== 'fontCatalog') add('XML_ROOT', '根元素必须是 fontCatalog', { node: catalog.root, xmlPath: '/' });
    if (catalog.version !== '1') add('CATALOG_VERSION', 'fontCatalog version 必须为 1', { node: catalog.root, xmlPath: '/fontCatalog' });
    if (!['A', 'B', 'C', 'D', 'E'].includes(catalog.gate)) add('CATALOG_GATE', 'fontCatalog gate 必须为 A..E', { node: catalog.root, xmlPath: '/fontCatalog' });
    if (catalog.runtimeAuthority === null) add('RUNTIME_AUTHORITY', 'runtimeAuthority 必须是 boolean', { node: catalog.root, xmlPath: '/fontCatalog' });
    if (['A', 'B'].includes(catalog.gate) && catalog.runtimeAuthority !== false) add('RUNTIME_AUTHORITY', `Gate ${catalog.gate} 必须声明 runtimeAuthority=false`, { node: catalog.root, xmlPath: '/fontCatalog' });
    if (['C', 'D', 'E'].includes(catalog.gate) && catalog.runtimeAuthority !== true) add('RUNTIME_AUTHORITY', `Gate ${catalog.gate} 必须声明 runtimeAuthority=true`, { node: catalog.root, xmlPath: '/fontCatalog' });

    const allowedHostNames = new Set();
    for (const host of catalog.allowedHosts) {
        const normalized = host.name.toLowerCase();
        if (!/^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)(?:\.(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?))+$/.test(normalized)) {
            add('HOST_INVALID', `下载白名单主机名非法：${host.name || '(空)'}`, host, { host: host.name });
        }
        if (allowedHostNames.has(normalized)) add('DUPLICATE_HOST', `重复下载白名单主机：${host.name}`, host, { host: host.name });
        allowedHostNames.add(normalized);
    }
    if (!catalog.allowedHosts.length) add('HOST_ALLOWLIST_EMPTY', 'downloadPolicy 至少需要一个 allowedHost', { node: catalog.root, xmlPath: '/fontCatalog/downloadPolicy' });

    const exclusionGlobs = new Set();
    for (const exclusion of catalog.exclusions) {
        const normalized = exclusion.glob.replace(/\\/g, '/');
        if (!normalized || normalized.startsWith('/') || normalized.includes('..') || normalized.includes('//')) {
            add('EXCLUSION_GLOB_INVALID', `排除路径必须是仓库相对正向路径：${exclusion.glob || '(空)'}`, exclusion, { glob: exclusion.glob });
        }
        if (exclusionGlobs.has(normalized.toLowerCase())) add('DUPLICATE_EXCLUSION', `重复排除路径：${exclusion.glob}`, exclusion, { glob: exclusion.glob });
        exclusionGlobs.add(normalized.toLowerCase());
        if (!exclusion.reason.trim()) add('EXCLUSION_REASON_MISSING', `排除路径缺少 reason：${exclusion.glob}`, exclusion, { glob: exclusion.glob });
    }
    for (const required of ['scripts/**', 'flashswf/**', '闪7重置版字体/**']) {
        if (!exclusionGlobs.has(required.toLowerCase())) {
            add('REQUIRED_EXCLUSION_MISSING', `缺少 Gate A 强制排除：${required}`, { node: catalog.root, xmlPath: '/fontCatalog/exclusions' }, { glob: required });
        }
    }

    const groupsById = new Map();
    for (const group of catalog.groups) {
        if (!ID_PATTERN.test(group.id)) add('ILLEGAL_GROUP_ID', `非法 group ID：${group.id || '(空)'}`, group, { id: group.id });
        if (groupsById.has(group.id)) add('DUPLICATE_GROUP', `重复 group：${group.id}`, group, { id: group.id });
        else groupsById.set(group.id, group);
        if (!group.label.trim()) add('LABEL_MISSING', `group ${group.id} 缺少显示名`, group, { id: group.id });
        if (!group.description.trim()) add('DESCRIPTION_MISSING', `group ${group.id} 缺少说明`, group, { id: group.id });
    }

    const assetsById = new Map();
    const assetsByFile = new Map();
    const facesById = new Map();
    const faceOwners = new Map();
    const seenUrls = new Map();
    for (const asset of catalog.fonts) {
        if (!ID_PATTERN.test(asset.id)) add('ILLEGAL_ID', `非法 asset ID：${asset.id || '(空)'}`, asset, { id: asset.id });
        if (assetsById.has(asset.id)) add('DUPLICATE_ID', `重复 asset ID：${asset.id}`, asset, { id: asset.id });
        else assetsById.set(asset.id, asset);
        if (!asset.label.trim()) add('LABEL_MISSING', `asset ${asset.id} 缺少显示名`, asset, { id: asset.id });

        const fileKey = asset.file.toLowerCase();
        if (!asset.file || path.basename(asset.file) !== asset.file || /[\\/]/.test(asset.file)) {
            add('ILLEGAL_FILE', `字体文件名必须是不含路径的 basename：${asset.file || '(空)'}`, asset, { id: asset.id });
        }
        if (assetsByFile.has(fileKey)) add('DUPLICATE_FILE', `字体文件名大小写冲突或重复：${asset.file}`, asset, { id: asset.id, ref: assetsByFile.get(fileKey).id });
        else assetsByFile.set(fileKey, asset);
        if (!FORMATS.has(asset.format)) add('FORMAT_INVALID', `未知字体格式：${asset.format}`, asset, { id: asset.id });
        if (asset.format === 'woff2') {
            add(
                'CUSTOM_WOFF2_OVERRIDE_UNSUPPORTED',
                `asset ${asset.id} 的 hash 固定 cache/permanent WOFF2 仍受支持，但 local custom WOFF2 当前没有覆盖权`,
                asset,
                { id: asset.id, format: asset.format },
                'warning',
            );
        }
        const extension = path.extname(asset.file).slice(1).toLowerCase();
        if (asset.format && extension !== asset.format) add('FORMAT_EXTENSION_MISMATCH', `${asset.file} 与 format=${asset.format} 不一致`, asset, { id: asset.id });
        if (!asset.license.trim()) add('LICENSE_MISSING', `asset ${asset.id} 缺少许可证标识`, asset, { id: asset.id });
        if (!asset.group.trim()) add('GROUP_MISSING', `asset ${asset.id} 缺少 group`, asset, { id: asset.id });
        if (catalog.groups.length && !groupsById.has(asset.group)) {
            add('UNKNOWN_GROUP', `asset ${asset.id} 引用未知 group：${asset.group}`, asset, { id: asset.id, ref: asset.group });
        }
        if (!RESIDENCIES.has(asset.residency)) add('RESIDENCY_INVALID', `asset ${asset.id} 的 residency 必须是 permanent 或 on-demand`, asset, { id: asset.id });
        if (asset.shippedFallback === null) add('BOOLEAN_INVALID', `asset ${asset.id} 的 shippedFallback 必须是 boolean`, asset, { id: asset.id });
        if (!asset.targets.length || asset.targets.some((target) => !TARGETS.has(target)) || new Set(asset.targets).size !== asset.targets.length) {
            add('TARGETS_INVALID', `asset ${asset.id} 的 targets 必须是去重后的 web/native 列表`, asset, { id: asset.id });
        }
        if ((asset.format === 'woff' || asset.format === 'woff2') && asset.targets.includes('native')) {
            add('FORMAT_TARGET_MISMATCH', `${asset.format} 资产 ${asset.id} 不得声明 native target`, asset, { id: asset.id });
        }
        if (!asset.faces.length) add('FACE_MISSING', `asset ${asset.id} 至少需要一个 face`, asset, { id: asset.id });

        if (asset.integrity) {
            if (asset.integrity.bytes === null || asset.integrity.bytes < 1) add('BYTES_INVALID', `asset ${asset.id} 的 integrity bytes 必须为正整数`, asset.integrity, { id: asset.id });
            if (!/^[0-9a-f]{64}$/.test(asset.integrity.sha256)) add('HASH_INVALID', `asset ${asset.id} 的 integrity sha256 必须是 64 位小写十六进制`, asset.integrity, { id: asset.id });
        }

        for (const face of asset.faces) {
            if (!ID_PATTERN.test(face.id)) add('ILLEGAL_FACE_ID', `非法 face ID：${face.id || '(空)'}`, face, { id: face.id });
            if (facesById.has(face.id)) add('DUPLICATE_FACE', `重复 face ID：${face.id}`, face, { id: face.id });
            else {
                facesById.set(face.id, face);
                faceOwners.set(face.id, asset);
            }
            if (!face.family.trim()) add('FAMILY_MISSING', `face ${face.id} 缺少 family`, face, { id: face.id });
            if (face.weight === null || face.weight < 1 || face.weight > 1000) add('WEIGHT_INVALID', `face ${face.id} 的 weight 必须在 1..1000`, face, { id: face.id });
            if (!STYLES.has(face.style)) add('STYLE_INVALID', `face ${face.id} 的 style 非法：${face.style}`, face, { id: face.id });
            if (!STRETCHES.has(face.stretch)) add('STRETCH_INVALID', `face ${face.id} 的 stretch 非法：${face.stretch}`, face, { id: face.id });
            if (!CLASSIFICATIONS.has(face.classification)) add('UNKNOWN_CLASSIFICATION', `face ${face.id} 的分类非法：${face.classification}`, face, { id: face.id });
        }

        const priorities = new Set();
        let integrity = null;
        for (const download of asset.downloads) {
            if (download.priority === null || download.priority < 1) add('DOWNLOAD_PRIORITY_INVALID', `asset ${asset.id} 的下载优先级必须为正整数`, download, { id: asset.id });
            if (priorities.has(download.priority)) add('DUPLICATE_DOWNLOAD_PRIORITY', `asset ${asset.id} 重复下载优先级 ${download.priority}`, download, { id: asset.id });
            priorities.add(download.priority);
            if (download.bytes === null || download.bytes < 1) add('BYTES_INVALID', `asset ${asset.id} 的 bytes 必须为正整数`, download, { id: asset.id });
            if (!/^[0-9a-f]{64}$/.test(download.sha256)) add('HASH_INVALID', `asset ${asset.id} 的 sha256 必须是 64 位小写十六进制`, download, { id: asset.id });
            const currentIntegrity = `${download.bytes}:${download.sha256}`;
            if (integrity !== null && integrity !== currentIntegrity) add('DOWNLOAD_INTEGRITY_DRIFT', `asset ${asset.id} 的镜像 bytes/sha256 不一致`, download, { id: asset.id });
            integrity = integrity || currentIntegrity;
            try {
                const parsed = new URL(download.url);
                if (parsed.protocol !== 'https:') add('URL_SCHEME', `下载地址必须使用 HTTPS：${download.url}`, download, { id: asset.id, url: download.url });
                if (parsed.username || parsed.password || parsed.hash) add('URL_UNSAFE', `下载地址不得含认证信息或 fragment：${download.url}`, download, { id: asset.id, url: download.url });
                if (parsed.port) add('URL_PORT', `下载地址只能使用默认 HTTPS 端口：${download.url}`, download, { id: asset.id, url: download.url });
                if (!allowedHostNames.has(parsed.hostname.toLowerCase())) add('HOST_NOT_ALLOWED', `下载主机未进入白名单：${parsed.hostname}`, download, { id: asset.id, host: parsed.hostname });
            } catch {
                add('URL_INVALID', `下载地址非法：${download.url}`, download, { id: asset.id, url: download.url });
            }
            if (seenUrls.has(download.url)) add('DUPLICATE_DOWNLOAD_URL', `下载地址被多个资产复用：${download.url}`, download, { id: asset.id, ref: seenUrls.get(download.url) });
            else seenUrls.set(download.url, asset.id);
        }
        if (asset.downloads.length) {
            const sorted = [...priorities].sort((a, b) => a - b);
            if (sorted.some((priority, index) => priority !== index + 1)) add('DOWNLOAD_PRIORITY_GAP', `asset ${asset.id} 的下载优先级必须从 1 连续递增`, asset, { id: asset.id });
            if (asset.integrity && integrity !== `${asset.integrity.bytes}:${asset.integrity.sha256}`) {
                add('ASSET_INTEGRITY_DRIFT', `asset ${asset.id} 的 integrity 与下载镜像不一致`, asset.integrity, { id: asset.id });
            }
        }
    }

    if (catalog.groups.length) {
        const usedGroups = new Set(catalog.fonts.map((asset) => asset.group));
        for (const group of catalog.groups) {
            if (!usedGroups.has(group.id)) add('UNUSED_GROUP', `group 未被任何 asset 使用：${group.id}`, group, { id: group.id });
        }
    }

    const familyLookup = new Map();
    for (const family of catalog.rawFamilies) {
        if (!family.name.trim()) add('RAW_FAMILY_MISSING', 'raw family name 不得为空', family);
        if (!CLASSIFICATIONS.has(family.classification)) add('UNKNOWN_CLASSIFICATION', `family ${family.name} 的分类非法：${family.classification}`, family, { family: family.name });
        for (const nameItem of [{ name: family.name, node: family.node, xmlPath: family.xmlPath }, ...family.aliases]) {
            const key = nameItem.name.trim().toLocaleLowerCase('en-US');
            if (!key) {
                add('RAW_FAMILY_MISSING', 'family/alias name 不得为空', nameItem);
                continue;
            }
            if (familyLookup.has(key)) {
                add('DUPLICATE_FAMILY', `family/alias 大小写冲突或重复：${nameItem.name}`, nameItem, { family: nameItem.name, ref: familyLookup.get(key).canonical });
            } else {
                familyLookup.set(key, { canonical: family.name, classification: family.classification, role: family.role, family });
            }
        }
    }
    for (const [faceId, face] of facesById) {
        const registered = familyLookup.get(face.family.toLocaleLowerCase('en-US'));
        if (!registered) add('UNREGISTERED_FACE_FAMILY', `face ${faceId} 的 family 未登记到 rawFamilies：${face.family}`, face, { id: faceId, family: face.family });
        else if (registered.classification !== face.classification) add('FAMILY_CLASSIFICATION_MISMATCH', `face ${faceId} 与 raw family 分类不一致`, face, { id: faceId, family: face.family });
    }

    const rolesById = new Map();
    const referencedFaces = new Set();
    for (const role of catalog.roles) {
        if (!ID_PATTERN.test(role.id)) add('ILLEGAL_ROLE_ID', `非法 role ID：${role.id || '(空)'}`, role, { id: role.id });
        if (rolesById.has(role.id)) add('DUPLICATE_ROLE', `重复 role：${role.id}`, role, { id: role.id });
        else rolesById.set(role.id, role);
        if (!role.label.trim()) add('LABEL_MISSING', `role ${role.id} 缺少显示名`, role, { id: role.id });
        if (!STATUSES.has(role.status)) add('STATUS_INVALID', `role ${role.id} 的 status 非法：${role.status}`, role, { id: role.id });
        if (role.allowPresetOverride === null) add('BOOLEAN_INVALID', `role ${role.id} 的 allowPresetOverride 必须是 boolean`, role, { id: role.id });
        if (!role.uses.length && !role.roleFallbacks.length && !role.systemFallbacks.length && !role.genericFallbacks.length) add('ROLE_EMPTY', `role ${role.id} 没有任何候选`, role, { id: role.id });
        const target = expectedTarget(role.id);
        const candidateKeys = new Set();
        for (const use of role.uses) {
            const candidateKey = `face:${use.face}`;
            if (candidateKeys.has(candidateKey)) add('DUPLICATE_ROLE_CANDIDATE', `role ${role.id} 重复 face 候选：${use.face}`, use, { id: role.id, ref: use.face });
            candidateKeys.add(candidateKey);
            const face = facesById.get(use.face);
            if (!face) add('BROKEN_FACE_REF', `role ${role.id} 引用未知 face：${use.face}`, use, { id: role.id, ref: use.face });
            else {
                referencedFaces.add(use.face);
                const owner = faceOwners.get(use.face);
                if (target && !owner.targets.includes(target)) add('FACE_TARGET_MISMATCH', `role ${role.id} 需要 ${target}，但 face ${use.face} 不支持`, use, { id: role.id, ref: use.face });
            }
        }
        for (const fallback of [...role.systemFallbacks, ...role.genericFallbacks]) {
            const candidateKey = `family:${fallback.family.toLocaleLowerCase('en-US')}`;
            if (candidateKeys.has(candidateKey)) add('DUPLICATE_ROLE_CANDIDATE', `role ${role.id} 重复 family 候选：${fallback.family}`, fallback, { id: role.id, family: fallback.family });
            candidateKeys.add(candidateKey);
            const registered = familyLookup.get(fallback.family.toLocaleLowerCase('en-US'));
            if (!registered) add('UNREGISTERED_FALLBACK', `role ${role.id} 的 fallback 未登记：${fallback.family}`, fallback, { id: role.id, family: fallback.family });
            else if (registered.classification !== fallback.classification) add('FAMILY_CLASSIFICATION_MISMATCH', `role ${role.id} 的 fallback 分类与 rawFamilies 不一致：${fallback.family}`, fallback, { id: role.id, family: fallback.family });
        }
        for (const fallback of role.systemFallbacks) {
            if (!['system-owned', 'compatibility'].includes(fallback.classification)) add('SYSTEM_FALLBACK_CLASSIFICATION', `systemFallback ${fallback.family} 必须归类为 system-owned 或 compatibility`, fallback, { id: role.id });
        }
        for (const fallback of role.genericFallbacks) {
            if (fallback.classification !== 'system-owned') add('GENERIC_FALLBACK_CLASSIFICATION', `genericFallback ${fallback.family} 必须归类为 system-owned`, fallback, { id: role.id });
        }
    }

    for (const family of catalog.rawFamilies) {
        if (family.role && !rolesById.has(family.role)) {
            add('BROKEN_RAW_FAMILY_ROLE', `raw family ${family.name} 引用了未知 role：${family.role}`, family, { family: family.name, ref: family.role });
        }
        if (family.role && family.classification !== 'compatibility') {
            add('RAW_FAMILY_ROLE_CLASSIFICATION', `只有 compatibility raw family 可以映射 legacy role：${family.name}`, family, { family: family.name, ref: family.role });
        }
    }

    for (const role of catalog.roles) {
        for (const fallback of role.roleFallbacks) {
            const duplicates = role.roleFallbacks.filter((item) => item.role === fallback.role);
            if (duplicates.length > 1 && duplicates[0] !== fallback) add('DUPLICATE_ROLE_CANDIDATE', `role ${role.id} 重复 fallback role：${fallback.role}`, fallback, { id: role.id, ref: fallback.role });
            if (!rolesById.has(fallback.role)) add('BROKEN_ROLE_REF', `role ${role.id} 引用未知 fallback role：${fallback.role}`, fallback, { id: role.id, ref: fallback.role });
        }
    }
    const visiting = new Set();
    const visited = new Set();
    function walkRole(roleId, trail) {
        if (visiting.has(roleId)) {
            const role = rolesById.get(roleId);
            add('ROLE_FALLBACK_CYCLE', `role fallback 出现循环：${[...trail, roleId].join(' -> ')}`, role, { id: roleId });
            return;
        }
        if (visited.has(roleId)) return;
        visiting.add(roleId);
        const role = rolesById.get(roleId);
        if (role) for (const fallback of role.roleFallbacks) walkRole(fallback.role, [...trail, roleId]);
        visiting.delete(roleId);
        visited.add(roleId);
    }
    for (const roleId of rolesById.keys()) walkRole(roleId, []);

    const presetsById = new Map();
    for (const preset of catalog.presets) {
        if (!ID_PATTERN.test(preset.id)) add('ILLEGAL_PRESET_ID', `非法 preset ID：${preset.id || '(空)'}`, preset, { id: preset.id });
        if (presetsById.has(preset.id)) add('DUPLICATE_PRESET', `重复 preset：${preset.id}`, preset, { id: preset.id });
        else presetsById.set(preset.id, preset);
        if (!preset.label.trim()) add('LABEL_MISSING', `preset ${preset.id} 缺少显示名`, preset, { id: preset.id });
        if (!STATUSES.has(preset.status)) add('STATUS_INVALID', `preset ${preset.id} 的 status 非法：${preset.status}`, preset, { id: preset.id });
        const boundRoles = new Set();
        for (const bind of preset.binds) {
            const role = rolesById.get(bind.role);
            const face = facesById.get(bind.face);
            if (!role) add('UNKNOWN_ROLE', `preset ${preset.id} 引用未知 role：${bind.role}`, bind, { id: preset.id, ref: bind.role });
            else if (!role.allowPresetOverride) add('PRESET_OVERRIDE_FORBIDDEN', `role ${bind.role} 不允许 preset 覆盖`, bind, { id: preset.id, ref: bind.role });
            if (!face) add('BROKEN_FACE_REF', `preset ${preset.id} 引用未知 face：${bind.face}`, bind, { id: preset.id, ref: bind.face });
            else {
                referencedFaces.add(bind.face);
                const target = role ? expectedTarget(role.id) : null;
                const owner = faceOwners.get(bind.face);
                if (target && !owner.targets.includes(target)) add('FACE_TARGET_MISMATCH', `preset ${preset.id} 的 face ${bind.face} 不支持 ${target}`, bind, { id: preset.id, ref: bind.face });
            }
            if (boundRoles.has(bind.role)) add('DUPLICATE_PRESET_BIND', `preset ${preset.id} 重复绑定 role ${bind.role}`, bind, { id: preset.id, ref: bind.role });
            boundRoles.add(bind.role);
        }
    }

    for (const faceId of facesById.keys()) {
        if (!referencedFaces.has(faceId)) add('UNREACHABLE_FACE', `face 未被 role 或 preset 使用：${faceId}`, facesById.get(faceId), { id: faceId });
    }

    return {
        diagnostics: sortDiagnostics(diagnostics),
        maps: { groupsById, assetsById, assetsByFile, facesById, faceOwners, familyLookup, rolesById, presetsById },
    };
}

module.exports = {
    CLASSIFICATIONS,
    compareText,
    diagnostic,
    loadCatalog,
    sortDiagnostics,
    validateCatalog,
};
