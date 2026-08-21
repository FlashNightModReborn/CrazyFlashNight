'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { diagnostic, sortDiagnostics } = require('./catalog');
const { inspectFont } = require('./font-metadata');

const SOURCE_DIRECTORIES = [
    { source: 'temporary/custom', relative: path.join('temporary', 'custom') },
    { source: 'temporary/cache', relative: path.join('temporary', 'cache') },
    { source: 'permanent/runtime', relative: path.join('permanent', 'runtime') },
];
const FONT_EXTENSION = /\.(?:ttf|otf|woff|woff2)$/i;
const MAX_FONT_BYTES = 256 * 1024 * 1024;

function isWithin(parent, candidate) {
    const relative = path.relative(parent, candidate);
    return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function hashBuffer(buffer) {
    const hash = crypto.createHash('sha256');
    hash.update(buffer);
    return hash.digest('hex');
}

function scanFontDirectories(catalog, fontRoot) {
    const absoluteRoot = path.resolve(fontRoot);
    const files = [];
    const diagnostics = [];
    const declaredByFile = new Map(catalog.fonts.map((asset) => [asset.file.toLowerCase(), asset]));
    const seenBySourceAndCase = new Map();

    function add(code, message, file, detail = {}, severity = 'error') {
        diagnostics.push(diagnostic(code, message, file, { line: 0, column: 0, ...detail }, severity));
    }

    function walk(directory, source, sourceRoot) {
        const entries = fs.readdirSync(directory, { withFileTypes: true })
            .sort((left, right) => left.name.localeCompare(right.name, 'en'));
        for (const entry of entries) {
            const absolute = path.join(directory, entry.name);
            const relative = path.relative(sourceRoot, absolute).replace(/\\/g, '/');
            if (entry.isSymbolicLink()) {
                add('FONT_SYMLINK_FORBIDDEN', `字体目录不跟随符号链接：${source}/${relative}`, absolute, { source, relative });
                continue;
            }
            if (entry.isDirectory()) {
                walk(absolute, source, sourceRoot);
                continue;
            }
            if (!entry.isFile() || !FONT_EXTENSION.test(entry.name)) continue;
            const resolved = path.resolve(absolute);
            if (!isWithin(sourceRoot, resolved) || !isWithin(absoluteRoot, resolved)) {
                add('FONT_PATH_ESCAPE', `字体路径逃出声明目录：${absolute}`, absolute, { source, relative });
                continue;
            }
            const fileName = path.basename(absolute);
            const collisionKey = `${source}\0${fileName.toLowerCase()}`;
            if (seenBySourceAndCase.has(collisionKey)) {
                const previous = seenBySourceAndCase.get(collisionKey);
                const code = previous.fileName === fileName ? 'FONT_BASENAME_COLLISION' : 'FONT_CASE_COLLISION';
                add(code, `同一来源存在无法确定绑定的 basename：${previous.relative} / ${relative}`, absolute, { source, fileName, previous: previous.relative });
            } else {
                seenBySourceAndCase.set(collisionKey, { fileName, relative });
            }
            const stat = fs.statSync(absolute);
            const declared = declaredByFile.get(fileName.toLowerCase()) || null;
            if (stat.size > MAX_FONT_BYTES) {
                add('FONT_TOO_LARGE', `字体超过 Gate A 单文件上限 ${MAX_FONT_BYTES} bytes：${source}/${relative}`, absolute, { source, relative, bytes: stat.size });
                files.push({
                    source,
                    relative,
                    file: fileName,
                    path: absolute,
                    bytes: stat.size,
                    sha256: null,
                    declared: Boolean(declared),
                    assetId: declared ? declared.id : null,
                    validFont: false,
                    metadata: null,
                });
                continue;
            }
            const buffer = fs.readFileSync(absolute);
            let metadata = null;
            let validFont = true;
            try {
                metadata = inspectFont(fileName, buffer);
                if (metadata.metadataStatus === 'container-only') {
                    add(
                        'FONT_METADATA_PARTIAL',
                        `WOFF2 容器已识别，但 Gate A 零依赖扫描器不展开压缩 metadata：${source}/${relative}`,
                        absolute,
                        { source, relative },
                        'warning',
                    );
                } else if (declared && metadata.families.length) {
                    const expectedFamilies = new Set(declared.faces.map((face) => face.family.toLocaleLowerCase('en-US')));
                    const observedFamilies = metadata.families.map((family) => family.toLocaleLowerCase('en-US'));
                    if (!observedFamilies.some((family) => expectedFamilies.has(family))) {
                        add(
                            source === 'temporary/custom' ? 'FONT_FAMILY_OVERRIDE' : 'FONT_FAMILY_MISMATCH',
                            `字体内部 family 与 asset ${declared.id} 的 face 不一致：${metadata.families.join(' / ')}`,
                            absolute,
                            { source, relative, id: declared.id, observedFamilies: metadata.families },
                            source === 'temporary/custom' ? 'warning' : 'error',
                        );
                    }
                }
            } catch (error) {
                validFont = false;
                add('FONT_INVALID', `字体容器或 metadata 非法：${source}/${relative}（${error.message}）`, absolute, { source, relative });
            }
            files.push({
                source,
                relative,
                file: fileName,
                path: absolute,
                bytes: stat.size,
                sha256: hashBuffer(buffer),
                declared: Boolean(declared),
                assetId: declared ? declared.id : null,
                validFont,
                metadata,
            });
            if (!declared) {
                add(
                    'UNDECLARED_LOCAL_FONT',
                    `本地字体尚未在 fonts.xml 登记，resolver 不会使用：${source}/${relative}`,
                    absolute,
                    { source, relative },
                    'warning',
                );
            }
        }
    }

    for (const entry of SOURCE_DIRECTORIES) {
        const sourceRoot = path.resolve(absoluteRoot, entry.relative);
        if (!isWithin(absoluteRoot, sourceRoot)) {
            add('FONT_ROOT_ESCAPE', `字体来源目录逃出根目录：${entry.source}`, sourceRoot, { source: entry.source });
            continue;
        }
        if (!fs.existsSync(sourceRoot)) continue;
        const stat = fs.lstatSync(sourceRoot);
        if (stat.isSymbolicLink()) {
            add('FONT_SYMLINK_FORBIDDEN', `字体来源目录不得是符号链接：${entry.source}`, sourceRoot, { source: entry.source });
            continue;
        }
        if (!stat.isDirectory()) {
            add('FONT_SOURCE_NOT_DIRECTORY', `字体来源不是目录：${entry.source}`, sourceRoot, { source: entry.source });
            continue;
        }
        walk(sourceRoot, entry.source, sourceRoot);
    }

    files.sort((left, right) => (
        SOURCE_DIRECTORIES.findIndex((item) => item.source === left.source)
        - SOURCE_DIRECTORIES.findIndex((item) => item.source === right.source)
        || left.relative.localeCompare(right.relative, 'en')
    ));
    return { files, diagnostics: sortDiagnostics(diagnostics) };
}

module.exports = { MAX_FONT_BYTES, SOURCE_DIRECTORIES, scanFontDirectories };
