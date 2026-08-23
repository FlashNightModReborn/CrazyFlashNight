'use strict';

const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const path = require('path');
const { diagnostic, sortDiagnostics } = require('./catalog');
const { inspectFont } = require('./font-metadata');
const { MAX_FONT_BYTES } = require('./scan');

const MAX_REDIRECTS = 5;
const REQUEST_TIMEOUT_MS = 30000;

function sha256File(file) {
    const hash = crypto.createHash('sha256');
    hash.update(fs.readFileSync(file));
    return hash.digest('hex');
}

function verifyFile(file, asset) {
    const expected = asset.integrity || asset.downloads[0] || null;
    if (!expected || !fs.existsSync(file)) return { ok: false, reason: expected ? 'missing' : 'integrity-undeclared' };
    const stat = fs.statSync(file);
    if (!stat.isFile() || stat.size !== expected.bytes || stat.size > MAX_FONT_BYTES) {
        return { ok: false, reason: 'bytes-mismatch', bytes: stat.size };
    }
    const sha256 = sha256File(file);
    if (sha256 !== expected.sha256) return { ok: false, reason: 'sha256-mismatch', bytes: stat.size, sha256 };
    try {
        inspectFont(asset.file, fs.readFileSync(file));
    } catch (error) {
        return { ok: false, reason: `invalid-font:${error.message}`, bytes: stat.size, sha256 };
    }
    return { ok: true, reason: 'verified', bytes: stat.size, sha256 };
}

function validateDownloadUrl(value, allowedHosts) {
    const parsed = new URL(value);
    if (parsed.protocol !== 'https:') throw new Error('url_scheme');
    if (parsed.username || parsed.password || parsed.hash) throw new Error('url_unsafe');
    if (parsed.port) throw new Error('url_port');
    if (!allowedHosts.has(parsed.hostname.toLowerCase())) throw new Error(`host_not_allowed:${parsed.hostname}`);
    return parsed;
}

function downloadToFile(url, destination, expectedBytes, allowedHosts, redirectCount = 0) {
    return new Promise((resolve, reject) => {
        let parsed;
        try {
            parsed = validateDownloadUrl(url, allowedHosts);
        } catch (error) {
            reject(error);
            return;
        }
        const request = https.get(parsed, {
            headers: { 'User-Agent': 'CF7-fontctl/1.0', Accept: 'font/*,application/octet-stream;q=0.9,*/*;q=0.1' },
            timeout: REQUEST_TIMEOUT_MS,
        }, (response) => {
            const status = response.statusCode || 0;
            if ([301, 302, 303, 307, 308].includes(status)) {
                response.resume();
                if (redirectCount >= MAX_REDIRECTS) {
                    reject(new Error('redirect_limit'));
                    return;
                }
                const location = response.headers.location;
                if (!location) {
                    reject(new Error('redirect_without_location'));
                    return;
                }
                let next;
                try {
                    next = new URL(location, parsed).toString();
                    validateDownloadUrl(next, allowedHosts);
                } catch (error) {
                    reject(error);
                    return;
                }
                downloadToFile(next, destination, expectedBytes, allowedHosts, redirectCount + 1).then(resolve, reject);
                return;
            }
            if (status !== 200) {
                response.resume();
                reject(new Error(`http_${status}`));
                return;
            }
            const declaredLength = Number(response.headers['content-length']);
            if (Number.isFinite(declaredLength) && declaredLength > 0 && declaredLength !== expectedBytes) {
                response.resume();
                reject(new Error(`content_length_mismatch:${declaredLength}`));
                return;
            }
            const stream = fs.createWriteStream(destination, { flags: 'wx' });
            let received = 0;
            let settled = false;
            function fail(error) {
                if (settled) return;
                settled = true;
                response.destroy();
                stream.destroy();
                try { fs.unlinkSync(destination); } catch { }
                reject(error);
            }
            response.on('data', (chunk) => {
                received += chunk.length;
                if (received > expectedBytes || received > MAX_FONT_BYTES) fail(new Error('response_too_large'));
            });
            response.on('error', fail);
            stream.on('error', fail);
            stream.on('finish', () => {
                if (settled) return;
                settled = true;
                stream.close(() => {
                    if (received !== expectedBytes) {
                        try { fs.unlinkSync(destination); } catch { }
                        reject(new Error(`response_bytes_mismatch:${received}`));
                    } else resolve({ finalUrl: parsed.toString(), bytes: received });
                });
            });
            response.pipe(stream);
        });
        request.on('timeout', () => request.destroy(new Error('request_timeout')));
        request.on('error', (error) => {
            try { fs.unlinkSync(destination); } catch { }
            reject(error);
        });
    });
}

function publishVerified(staging, target) {
    const backup = `${target}.${process.pid}.${Date.now()}.bak`;
    let movedExisting = false;
    try {
        if (fs.existsSync(target)) {
            fs.renameSync(target, backup);
            movedExisting = true;
        }
        fs.renameSync(staging, target);
        if (movedExisting) fs.unlinkSync(backup);
    } catch (error) {
        try { if (fs.existsSync(staging)) fs.unlinkSync(staging); } catch { }
        if (movedExisting && !fs.existsSync(target) && fs.existsSync(backup)) {
            try { fs.renameSync(backup, target); } catch { }
        }
        throw error;
    }
}

function selectAssets(catalog, selection) {
    let assets = [...catalog.fonts];
    if (selection.assetIds && selection.assetIds.length) {
        const wanted = new Set(selection.assetIds);
        assets = assets.filter((asset) => wanted.has(asset.id));
    }
    if (selection.groups && selection.groups.length) {
        const wanted = new Set(selection.groups);
        assets = assets.filter((asset) => wanted.has(asset.group));
    }
    return assets;
}

async function syncAssets(catalog, fontRoot, selection = {}, options = {}) {
    const diagnostics = [];
    const allowedHosts = new Set(catalog.allowedHosts.map((item) => item.name.toLowerCase()));
    const cacheDirectory = path.resolve(fontRoot, 'temporary', 'cache');
    const stagingDirectory = path.join(cacheDirectory, '.staging');
    const assets = selectAssets(catalog, selection);
    const knownIds = new Set(catalog.fonts.map((asset) => asset.id));
    const knownGroups = new Set(catalog.fonts.map((asset) => asset.group));
    for (const id of selection.assetIds || []) {
        if (!knownIds.has(id)) diagnostics.push(diagnostic('UNKNOWN_ASSET', `未知 asset：${id}`, catalog.file, { id }));
    }
    for (const group of selection.groups || []) {
        if (!knownGroups.has(group)) diagnostics.push(diagnostic('UNKNOWN_GROUP', `未知 group：${group}`, catalog.file, { group }));
    }
    if (diagnostics.length) return { assets: [], diagnostics: sortDiagnostics(diagnostics) };
    if (!options.checkOnly) {
        fs.mkdirSync(cacheDirectory, { recursive: true });
        fs.mkdirSync(stagingDirectory, { recursive: true });
    }

    const results = [];
    for (const asset of assets) {
        const target = path.join(cacheDirectory, asset.file);
        const existing = verifyFile(target, asset);
        if (existing.ok) {
            results.push({ id: asset.id, file: asset.file, status: 'verified-existing', source: 'temporary/cache' });
            continue;
        }
        if (options.checkOnly) {
            diagnostics.push(diagnostic('CACHE_MISSING_OR_INVALID', `cache 缺失或无效：${asset.file}（${existing.reason}）`, target, { id: asset.id }));
            results.push({ id: asset.id, file: asset.file, status: 'missing-or-invalid', reason: existing.reason });
            continue;
        }
        if (!asset.downloads.length) {
            results.push({ id: asset.id, file: asset.file, status: 'no-download-config' });
            continue;
        }
        const expected = asset.integrity || asset.downloads[0];
        let installed = false;
        const failures = [];
        for (const download of [...asset.downloads].sort((left, right) => left.priority - right.priority)) {
            const staging = path.join(stagingDirectory, `${asset.file}.${process.pid}.${Date.now()}.${crypto.randomBytes(6).toString('hex')}.tmp`);
            try {
                const downloader = options.downloadToFile || downloadToFile;
                await downloader(download.url, staging, expected.bytes, allowedHosts);
                const verified = verifyFile(staging, asset);
                if (!verified.ok) throw new Error(verified.reason);
                publishVerified(staging, target);
                results.push({ id: asset.id, file: asset.file, status: 'downloaded', source: 'temporary/cache', url: download.url });
                installed = true;
                break;
            } catch (error) {
                try { if (fs.existsSync(staging)) fs.unlinkSync(staging); } catch { }
                failures.push({ url: download.url, error: error.message });
            }
        }
        if (!installed) {
            diagnostics.push(diagnostic('DOWNLOAD_FAILED', `asset ${asset.id} 的全部下载源失败`, target, { id: asset.id, failures }));
            results.push({ id: asset.id, file: asset.file, status: 'failed', failures });
        }
    }
    return { assets: results, diagnostics: sortDiagnostics(diagnostics) };
}

module.exports = {
    downloadToFile,
    publishVerified,
    selectAssets,
    syncAssets,
    validateDownloadUrl,
    verifyFile,
};
