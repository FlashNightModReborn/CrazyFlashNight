'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { diagnostic, sortDiagnostics } = require('./catalog');

function buildCompatibilityManifest(projection) {
    const groups = {};
    for (const [groupId, metadata] of Object.entries(projection.groups || {})) {
        const assets = projection.assets.filter((asset) => asset.group === groupId);
        groups[groupId] = {
            label: metadata.label,
            description: metadata.description,
            totalBytes: assets.reduce((total, asset) => total + Number(asset.bytes || 0), 0),
            files: assets.map((asset) => ({
                name: asset.file,
                label: asset.label,
                license: asset.license,
                bytes: asset.bytes,
                sha256: asset.sha256,
                urls: asset.downloads.map((download) => download.url),
                shippedFallback: asset.shippedFallback,
            })),
        };
    }
    return {
        schemaVersion: 1,
        generatedBy: 'tools/fontctl',
        sourceSha256: projection.sourceSha256,
        gate: projection.gate,
        comment: 'Generated compatibility projection. Edit fonts/fonts.xml and run fontctl generate.',
        groups,
    };
}

function hashFile(file) {
    const hash = crypto.createHash('sha256');
    hash.update(fs.readFileSync(file));
    return hash.digest('hex');
}

function validateManifestParity(catalog, manifestFile, assetDirectory) {
    const diagnostics = [];
    const add = (code, message, detail = {}) => diagnostics.push(diagnostic(
        code,
        message,
        manifestFile,
        { line: 0, column: 0, ...detail },
    ));

    let manifest;
    try {
        manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
    } catch (error) {
        add('MANIFEST_READ', `无法读取现役 font-pack manifest：${error.message}`);
        return sortDiagnostics(diagnostics);
    }
    if (manifest.schemaVersion !== 1 || !manifest.groups || typeof manifest.groups !== 'object') {
        add('MANIFEST_SHAPE', '生成的 font-pack compatibility projection 必须使用 schemaVersion=1 且包含 groups');
        return sortDiagnostics(diagnostics);
    }
    const expectedSourceHash = crypto.createHash('sha256').update(fs.readFileSync(catalog.file)).digest('hex');
    if (manifest.generatedBy !== 'tools/fontctl' || manifest.sourceSha256 !== expectedSourceHash
        || manifest.gate !== catalog.gate) {
        add('MANIFEST_SOURCE_DRIFT', 'font-pack compatibility projection 未绑定当前 fonts.xml/gate');
    }

    const expectedByFile = new Map();
    for (const [groupId, group] of Object.entries(manifest.groups)) {
        if (!group || !Array.isArray(group.files)) {
            add('MANIFEST_SHAPE', `manifest group ${groupId} 缺少 files 数组`, { group: groupId });
            continue;
        }
        for (const item of group.files) {
            const key = String(item.name || '').toLowerCase();
            if (!key) {
                add('MANIFEST_SHAPE', `manifest group ${groupId} 含空文件名`, { group: groupId });
                continue;
            }
            if (expectedByFile.has(key)) {
                add('MANIFEST_DUPLICATE_FILE', `manifest 重复声明字体文件：${item.name}`, { group: groupId, fileName: item.name });
                continue;
            }
            expectedByFile.set(key, { groupId, item });
        }
    }

    const actualByFile = new Map(catalog.fonts.map((asset) => [asset.file.toLowerCase(), asset]));
    for (const [fileKey, expected] of expectedByFile) {
        const actual = actualByFile.get(fileKey);
        if (!actual) {
            add('MANIFEST_ASSET_MISSING', `fonts.xml 未表达现役资产：${expected.item.name}`, { fileName: expected.item.name });
            continue;
        }
        const comparisons = [
            ['group', actual.group, expected.groupId],
            ['label', actual.label, expected.item.label],
            ['license', actual.license, expected.item.license],
            ['shippedFallback', actual.shippedFallback, expected.item.shippedFallback],
        ];
        for (const [field, actualValue, expectedValue] of comparisons) {
            if (actualValue !== expectedValue) {
                add('MANIFEST_FIELD_DRIFT', `${actual.file} 的 ${field} 与现役 manifest 不一致`, {
                    id: actual.id,
                    field,
                    expected: expectedValue,
                    actual: actualValue,
                });
            }
        }
        const expectedUrls = Array.isArray(expected.item.urls) ? expected.item.urls : [];
        if (actual.downloads.length !== expectedUrls.length) {
            add('MANIFEST_DOWNLOAD_COUNT_DRIFT', `${actual.file} 的下载镜像数量与现役 manifest 不一致`, {
                id: actual.id,
                expected: expectedUrls.length,
                actual: actual.downloads.length,
            });
        }
        const count = Math.max(actual.downloads.length, expectedUrls.length);
        for (let index = 0; index < count; index += 1) {
            const download = actual.downloads[index];
            const expectedUrl = expectedUrls[index];
            if (!download || download.priority !== index + 1 || download.url !== expectedUrl
                || download.bytes !== expected.item.bytes || download.sha256 !== expected.item.sha256) {
                add('MANIFEST_DOWNLOAD_DRIFT', `${actual.file} 的第 ${index + 1} 个下载项未无损复刻现役 manifest`, {
                    id: actual.id,
                    priority: index + 1,
                });
            }
        }
        if (expected.item.shippedFallback) {
            const shippedPath = path.join(assetDirectory, expected.item.name);
            if (!fs.existsSync(shippedPath)) {
                add('SHIPPED_FALLBACK_MISSING', `现役 shipped fallback 不存在：${expected.item.name}`, { fileName: expected.item.name });
            } else {
                const stat = fs.statSync(shippedPath);
                const sha256 = hashFile(shippedPath);
                if (stat.size !== expected.item.bytes || sha256 !== expected.item.sha256) {
                    add('SHIPPED_FALLBACK_INTEGRITY', `现役 shipped fallback 完整性不匹配：${expected.item.name}`, {
                        fileName: expected.item.name,
                        expectedBytes: expected.item.bytes,
                        actualBytes: stat.size,
                        expectedSha256: expected.item.sha256,
                        actualSha256: sha256,
                    });
                }
            }
        }
    }
    for (const asset of catalog.fonts) {
        if (!expectedByFile.has(asset.file.toLowerCase())) {
            add('MANIFEST_EXTRA_ASSET', `fonts.xml 含现役 manifest 未登记的资产：${asset.file}`, { id: asset.id });
        }
    }

    return sortDiagnostics(diagnostics);
}

module.exports = { buildCompatibilityManifest, validateManifestParity };
