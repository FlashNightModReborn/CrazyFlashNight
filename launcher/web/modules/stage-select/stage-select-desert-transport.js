import { MAX_DESERT_SCENE_BYTES } from './stage-select-desert-config.js';

function live(signal) {
    if (signal?.aborted) throw new DOMException('Closed', 'AbortError');
}

async function fingerprint(bytes, signal) {
    live(signal);
    if (!globalThis.crypto?.subtle) throw new Error('Desert scene fingerprint verification unavailable');
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    live(signal);
    return [...new Uint8Array(digest)].map(value => value.toString(16).padStart(2, '0')).join('');
}

async function readBounded(stream, limit, expected, label, signal) {
    if (!stream) throw new Error('Missing desert ' + label + ' stream');
    const reader = stream.getReader(), chunks = [];
    let length = 0;
    const cancel = () => { reader.cancel().catch(() => {}); };
    signal?.addEventListener('abort', cancel, { once: true });
    try {
        live(signal);
        while (true) {
            const { done, value } = await reader.read(); live(signal);
            if (done) break;
            length += value.byteLength;
            if (length > limit) throw new Error('Desert ' + label + ' exceeds byte limit');
            chunks.push(value);
        }
        if (expected !== null && length !== expected) throw new Error('Desert ' + label + ' byte length mismatch');
        const bytes = new Uint8Array(length);
        let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
        return bytes.buffer;
    } finally {
        signal?.removeEventListener('abort', cancel);
        await reader.cancel().catch(() => {}); reader.releaseLock();
    }
}

async function decodeGzip(bytes, expected, signal) {
    let offset = 0;
    const source = new ReadableStream({
        pull(controller) {
            live(signal);
            if (offset === bytes.byteLength) { controller.close(); return; }
            const count = Math.min(64 * 1024, bytes.byteLength - offset);
            controller.enqueue(new Uint8Array(bytes, offset, count)); offset += count;
        }
    });
    try {
        return await readBounded(source.pipeThrough(new DecompressionStream('gzip')), expected, expected, 'decoded scene', signal);
    } catch (error) {
        live(signal);
        if (error.name === 'AbortError') throw error;
        throw new Error('Desert gzip decoding failed: ' + error.message);
    }
}

// Both identities are checked before parsing. The gzip is only a lossless local
// transport; the decoded GLB keeps the originally reviewed scene fingerprint.
export async function loadDesertSceneBytes(config, assetRoot, signal) {
    live(signal);
    const transport = config.sceneTransport;
    if (transport && typeof globalThis.DecompressionStream !== 'function') throw new Error('Desert gzip decoding unavailable');
    const path = transport?.path || 'scene.glb', expectedHash = transport?.sha256 || config.assetHashes['scene.glb'];
    const url = new URL(path, assetRoot); url.searchParams.set('sha256', expectedHash);
    const response = await fetch(url, { signal }); live(signal);
    if (!response.ok) throw new Error('Desert scene HTTP ' + response.status);
    const encoded = await readBounded(response.body, transport?.bytes || MAX_DESERT_SCENE_BYTES,
        transport?.bytes ?? null, 'transport', signal);
    const encodedHash = await fingerprint(encoded, signal);
    if (encodedHash !== expectedHash) throw new Error('Desert transport fingerprint mismatch');
    const bytes = transport ? await decodeGzip(encoded, transport.decodedBytes, signal) : encoded;
    const sceneHash = transport ? await fingerprint(bytes, signal) : encodedHash;
    if (sceneHash !== config.assetHashes['scene.glb']) throw new Error('Desert scene fingerprint mismatch');
    live(signal);
    return { bytes, sceneHash, transport: { path, encoding: transport ? 'gzip' : 'raw',
        bytes: encoded.byteLength, sha256: encodedHash, decodedBytes: bytes.byteLength, decodedSha256: sceneHash } };
}
