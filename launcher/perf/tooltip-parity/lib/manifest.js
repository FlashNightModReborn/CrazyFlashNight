'use strict';
// baseline manifest 生成/校验共用：manifest.json 记录每个冻结文件的 sha256 与来源 commit。
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function sha256(buf) { return crypto.createHash('sha256').update(buf).digest('hex'); }

/** 递归收集 dir 下所有文件，key = 相对 dir 的 posix 路径。 */
function collectFiles(dir) {
    const out = [];
    (function walk(d) {
        for (const e of fs.readdirSync(d, { withFileTypes: true })) {
            const p = path.join(d, e.name);
            if (e.isDirectory()) walk(p);
            else if (e.isFile() && e.name !== 'manifest.json') out.push(p);
        }
    })(dir);
    return out.sort();
}

function buildManifest(dir, sourceSha) {
    const files = {};
    for (const abs of collectFiles(dir)) {
        const rel = path.relative(dir, abs).replace(/\\/g, '/');
        files[rel] = { sha256: sha256(fs.readFileSync(abs)), bytes: fs.statSync(abs).size };
    }
    return {
        schema: 'cf7.tooltip-parity-baseline.v1',
        sourceSha: sourceSha || null,
        generatedAt: new Date().toISOString(),
        files
    };
}

function writeManifest(dir, sourceSha) {
    const manifest = buildManifest(dir, sourceSha);
    fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(manifest, null, 1));
    return manifest;
}

module.exports = { sha256, collectFiles, buildManifest, writeManifest };
