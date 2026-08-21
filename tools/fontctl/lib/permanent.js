'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { diagnostic, sortDiagnostics } = require('./catalog');
const { inspectFont } = require('./font-metadata');

const FONT_EXTENSION = /\.(?:ttf|otf|woff|woff2)$/i;

function sha256(buffer) {
    return crypto.createHash('sha256').update(buffer).digest('hex');
}

function validatePermanentAssets(catalog, fontRoot) {
    const directory = path.resolve(fontRoot, 'permanent', 'runtime');
    const diagnostics = [];
    const add = (code, message, file, detail = {}) => diagnostics.push(diagnostic(
        code,
        message,
        file,
        { line: 0, column: 0, ...detail },
    ));
    const assetsByFile = new Map(catalog.fonts.map((asset) => [asset.file.toLowerCase(), asset]));

    if (!fs.existsSync(directory) || !fs.statSync(directory).isDirectory()) {
        add('PERMANENT_DIRECTORY_MISSING', '常驻字体目录不存在：fonts/permanent/runtime', directory);
        return sortDiagnostics(diagnostics);
    }

    const entries = fs.readdirSync(directory, { withFileTypes: true })
        .sort((left, right) => left.name.localeCompare(right.name, 'en'));
    for (const entry of entries) {
        if (!FONT_EXTENSION.test(entry.name)) continue;
        const file = path.join(directory, entry.name);
        if (entry.isSymbolicLink() || !entry.isFile()) {
            add('PERMANENT_FILE_INVALID', `常驻字体必须是直接子文件且不得为符号链接：${entry.name}`, file, { fileName: entry.name });
            continue;
        }
        const asset = assetsByFile.get(entry.name.toLowerCase());
        if (!asset) {
            add('PERMANENT_ASSET_UNDECLARED', `常驻目录含未登记字体：${entry.name}`, file, { fileName: entry.name });
        } else if (asset.residency !== 'permanent') {
            add('PERMANENT_RESIDENCY_DRIFT', `on-demand asset 不得进入常驻目录：${entry.name}`, file, { id: asset.id });
        }
    }

    for (const asset of catalog.fonts.filter((item) => item.residency === 'permanent')) {
        const file = path.join(directory, asset.file);
        if (!fs.existsSync(file)) {
            add('PERMANENT_ASSET_MISSING', `声明为 permanent 的字体缺失：${asset.file}`, file, { id: asset.id });
            continue;
        }
        const expected = asset.integrity || asset.downloads[0] || null;
        if (!expected) {
            add('PERMANENT_INTEGRITY_UNDECLARED', `常驻字体缺少 bytes/sha256：${asset.file}`, file, { id: asset.id });
            continue;
        }
        try {
            const buffer = fs.readFileSync(file);
            const actualHash = sha256(buffer);
            if (buffer.length !== expected.bytes || actualHash !== expected.sha256) {
                add('PERMANENT_INTEGRITY', `常驻字体完整性不匹配：${asset.file}`, file, {
                    id: asset.id,
                    expectedBytes: expected.bytes,
                    actualBytes: buffer.length,
                    expectedSha256: expected.sha256,
                    actualSha256: actualHash,
                });
                continue;
            }
            inspectFont(asset.file, buffer);
        } catch (error) {
            add('PERMANENT_FONT_INVALID', `常驻字体容器非法：${asset.file}（${error.message}）`, file, { id: asset.id });
        }
    }
    return sortDiagnostics(diagnostics);
}

module.exports = { validatePermanentAssets };
