'use strict';
const assert = require('assert/strict'), path = require('path');
const { pathToFileURL } = require('url');
const { gzipSync } = require('zlib'), { createHash } = require('crypto');
const root = path.resolve(__dirname, '..'), assetRoot = new URL('https://transport-fixture.invalid/desert/');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function fixture(padding = 0) {
    const json = Buffer.from(JSON.stringify({ asset: { version: '2.0' }, extras: { padding: 'x'.repeat(padding) } }));
    const length = Math.ceil(json.length / 4) * 4, raw = Buffer.alloc(20 + length, 0x20);
    raw.writeUInt32LE(0x46546c67, 0); raw.writeUInt32LE(2, 4); raw.writeUInt32LE(raw.length, 8);
    raw.writeUInt32LE(length, 12); raw.writeUInt32LE(0x4e4f534a, 16); json.copy(raw, 20);
    const packed = gzipSync(raw);
    return { raw, packed, config: { assetHashes: { 'scene.glb': hash(raw) },
        sceneTransport: { path: 'scene.glb.gz', encoding: 'gzip', sha256: hash(packed), bytes: packed.length, decodedBytes: raw.length } } };
}
async function main() {
    const { normalizeDesertTransport, MAX_DESERT_TRANSPORT_BYTES, MAX_DESERT_SCENE_BYTES, validateEmbeddedGlb } = await import(pathToFileURL(path.join(root, 'launcher/web/modules/stage-select/stage-select-desert-config.js')).href);
    const { loadDesertSceneBytes } = await import(pathToFileURL(path.join(root, 'launcher/web/modules/stage-select/stage-select-desert-transport.js')).href);
    const originalFetch = globalThis.fetch, nativeDecoder = globalThis.DecompressionStream, f = fixture();
    const checks = [];
    try {
        assert.equal(normalizeDesertTransport(undefined), null);
        assert.deepEqual(normalizeDesertTransport(f.config.sceneTransport), f.config.sceneTransport);
        for (const bad of [null, { ...f.config.sceneTransport, path: '../scene.glb.gz' }, { ...f.config.sceneTransport, path: 'https://example.invalid/scene.glb.gz' },
            { ...f.config.sceneTransport, encoding: 'deflate' }, { ...f.config.sceneTransport, sha256: 'unverified' },
            { ...f.config.sceneTransport, bytes: Infinity }, { ...f.config.sceneTransport, bytes: 12.5 },
            { ...f.config.sceneTransport, bytes: MAX_DESERT_TRANSPORT_BYTES + 1 },
            { ...f.config.sceneTransport, decodedBytes: MAX_DESERT_SCENE_BYTES + 1 }]) assert.throws(() => normalizeDesertTransport(bad), /transport/);
        checks.push('Exact local gzip path, fingerprints and bounded integer sizes are required');
        globalThis.fetch = async url => { assert.equal(url.pathname, '/desert/scene.glb.gz'); return new Response(f.packed); };
        const decoded = await loadDesertSceneBytes(f.config, assetRoot);
        assert.deepEqual(Buffer.from(decoded.bytes), f.raw); validateEmbeddedGlb(decoded.bytes);
        assert.equal(decoded.sceneHash, hash(f.raw)); assert.equal(decoded.transport.sha256, hash(f.packed));
        globalThis.fetch = async url => { assert.equal(url.pathname, '/desert/scene.glb'); return new Response(f.raw); };
        const legacy = await loadDesertSceneBytes({ assetHashes: f.config.assetHashes }, assetRoot);
        assert.deepEqual(Buffer.from(legacy.bytes), f.raw); assert.equal(legacy.transport.encoding, 'raw');
        checks.push('Native gzip decoding preserves every GLB byte and its old identity; raw fixtures remain supported');

        let decoderCalls = 0;
        globalThis.DecompressionStream = class { constructor() { decoderCalls++; throw new Error('must not decode invalid transport'); } };
        globalThis.fetch = async () => new Response(f.packed);
        await assert.rejects(loadDesertSceneBytes({ ...f.config, sceneTransport: { ...f.config.sceneTransport, bytes: f.packed.length + 1 } }, assetRoot), /byte length/);
        await assert.rejects(loadDesertSceneBytes({ ...f.config, sceneTransport: { ...f.config.sceneTransport, sha256: 'a'.repeat(64) } }, assetRoot), /transport fingerprint/);
        assert.equal(decoderCalls, 0); globalThis.DecompressionStream = nativeDecoder;
        const corrupt = Buffer.from(f.packed); corrupt[corrupt.length - 8] ^= 1;
        globalThis.fetch = async () => new Response(corrupt);
        await assert.rejects(loadDesertSceneBytes({ ...f.config, sceneTransport: { ...f.config.sceneTransport, sha256: hash(corrupt) } }, assetRoot), /gzip decoding/);
        globalThis.fetch = async () => new Response(f.packed);
        await assert.rejects(loadDesertSceneBytes({ ...f.config, sceneTransport: { ...f.config.sceneTransport, decodedBytes: f.raw.length - 1 } }, assetRoot), /decoded scene.*byte limit/);
        await assert.rejects(loadDesertSceneBytes({ ...f.config, sceneTransport: { ...f.config.sceneTransport, decodedBytes: f.raw.length + 1 } }, assetRoot), /decoded scene.*byte length/);
        await assert.rejects(loadDesertSceneBytes({ ...f.config, assetHashes: { 'scene.glb': 'a'.repeat(64) } }, assetRoot), /scene fingerprint/);
        checks.push('Wrong transport length/hash is rejected before decoding; broken gzip, oversized output and wrong decoded identity are rejected');

        let requests = 0;
        globalThis.fetch = async () => { requests++; return new Response(f.packed); };
        const early = new AbortController(); early.abort();
        await assert.rejects(loadDesertSceneBytes(f.config, assetRoot, early.signal), { name: 'AbortError' }); assert.equal(requests, 0);
        globalThis.DecompressionStream = undefined;
        await assert.rejects(loadDesertSceneBytes(f.config, assetRoot), /decoding unavailable/); assert.equal(requests, 0);
        globalThis.DecompressionStream = nativeDecoder;
        const duringRead = new AbortController(); let canceled = 0, response;
        globalThis.fetch = async () => response = new Response(new ReadableStream({
            start(controller) { controller.enqueue(f.packed.subarray(0, 8)); }, cancel() { canceled++; }
        }));
        const pending = loadDesertSceneBytes(f.config, assetRoot, duringRead.signal);
        const timer = setTimeout(() => duringRead.abort(), 10);
        try { await assert.rejects(pending, { name: 'AbortError' }); } finally { clearTimeout(timer); }
        assert.equal(canceled, 1); assert.equal(response.body.locked, false);
        const large = fixture(1024 * 1024), duringDecode = new AbortController(); let decodedChunks = 0;
        globalThis.fetch = async () => new Response(large.packed);
        globalThis.DecompressionStream = class {
            constructor(format) {
                const decoder = new nativeDecoder(format);
                return { writable: decoder.writable, readable: decoder.readable.pipeThrough(new TransformStream({
                    transform(chunk, controller) { decodedChunks++; controller.enqueue(chunk); duringDecode.abort(); }
                })) };
            }
        };
        await assert.rejects(loadDesertSceneBytes(large.config, assetRoot, duringDecode.signal), { name: 'AbortError' });
        assert.ok(decodedChunks > 0);
        checks.push('Abort before fetch, during network streaming and during native decompression retires readers; missing API fails without a download');
        console.log(JSON.stringify({ pass: true, checks }));
    } finally { globalThis.fetch = originalFetch; globalThis.DecompressionStream = nativeDecoder; }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
