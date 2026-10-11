'use strict';
// Node contract checks for the bookshelf 3D shelf overview: visual config normalization,
// embedded-GLB boundary, asset manifest hashes and catalog/mesh identity alignment.
// No renderer, Host, Flash or save interaction is exercised here.
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const crypto = require('crypto');
const { pathToFileURL } = require('url');
const root = path.resolve(__dirname, '..');
const R = require('../launcher/web/modules/bookshelf-runtime.js');

const sha = data => crypto.createHash('sha256').update(data).digest('hex');

function glb(data) {
    assert.equal(data.readUInt32LE(0), 0x46546c67, 'GLB magic');
    assert.equal(data.readUInt32LE(4), 2, 'GLB version');
    assert.equal(data.readUInt32LE(8), data.length, 'GLB length');
    assert.equal(data.readUInt32LE(16), 0x4e4f534a, 'GLB JSON chunk');
    const jsonLength = data.readUInt32LE(12);
    const doc = JSON.parse(data.slice(20, 20 + jsonLength).toString('utf8'));
    const start = 20 + jsonLength;
    assert.equal(data.readUInt32LE(start + 4), 0x004e4942, 'GLB BIN chunk');
    const bin = data.slice(start + 8, start + 8 + data.readUInt32LE(start));
    return { doc, bin };
}

function audit(data) {
    const { doc } = glb(data);
    for (const resource of [...(doc.buffers || []), ...(doc.images || [])]) {
        assert.ok(!resource.uri, 'embedded-only GLB resource closure');
    }
    const primitives = doc.meshes.flatMap(mesh => mesh.primitives);
    const triangles = primitives.reduce((sum, p) => sum + doc.accessors[p.indices].count / 3, 0);
    return { bytes: data.length, meshes: doc.meshes.length, primitives: primitives.length,
        triangles, materials: doc.materials.length, images: (doc.images || []).length };
}

async function main() {
    const module = await import(pathToFileURL(path.join(root, 'launcher/web/modules/bookshelf-shelf-config.js')).href);
    const { normalizeShelfConfig, validateEmbeddedGlb } = module;
    const plain = value => JSON.parse(JSON.stringify(value));

    const assets = path.join(root, 'launcher/web/assets/bookshelf/shelf');
    const rawConfig = JSON.parse(fs.readFileSync(path.join(assets, 'config.json'), 'utf8'));
    const frozen = JSON.stringify(rawConfig);
    const config = normalizeShelfConfig(rawConfig);
    assert.equal(JSON.stringify(rawConfig), frozen, 'validation must not mutate the producer input');
    const design = JSON.parse(fs.readFileSync(path.join(root, 'docs/design-data/bookshelf-shelf-draft.json'), 'utf8'));
    assert.equal(config.hoverPull, design.hoverPull, 'hover pull follows the design draft');

    const catalog = JSON.parse(fs.readFileSync(path.join(root, 'data/books/catalog.json'), 'utf8'));
    const adopted = R.adoptCatalog(plain(catalog));
    const ids = adopted.map(book => book.id);
    assert.deepEqual(Object.keys(config.entries), ids, 'shelf entries cover exactly the catalog books');
    for (const book of adopted) {
        const entry = config.entries[book.id];
        if (book.format === 'playable') {
            assert.equal(entry.kind, 'box');
            assert.ok(entry.meshes.includes('BOX_crazy-flasher'), 'collection box mesh present');
            for (const chapter of book.chapters) {
                assert.ok(entry.meshes.includes('DISC_' + chapter.id), 'disc mesh present: ' + chapter.id);
                assert.ok(R.safeAsset(chapter.cover), 'chapter cover is a safe asset path');
            }
            assert.ok(R.safeAsset(book.boxArt), 'box art is a safe asset path');
        } else {
            assert.equal(entry.kind, 'book');
            assert.ok(entry.meshes.includes('BOOK_' + book.id) && entry.meshes.includes('LABEL_' + book.id));
            assert.ok(R.safeAsset(book.spine), 'spine is a safe asset path');
        }
    }

    const broken = mutate => { const value = plain(rawConfig); mutate(value); return value; };
    assert.throws(() => normalizeShelfConfig(broken(value => { value.schema = 'other'; })), /config/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.camera.gltfPosition[1] = NaN; })), /vector/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.camera.minSpan = 0.2; })), /camera/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.camera.maxSpan = 99999; })), /camera/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.entries.dust.meshes = ['SCENE_all']; })), /entry/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.entries.dust.kind = 'disc'; })), /entry/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.hoverPull = 99; })), /pull/);
    assert.throws(() => normalizeShelfConfig(broken(value => { delete value.archiveZone; })), /archive/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.archiveZone.max = 0; })), /archive/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.archiveZone.color = 7; })), /archive/);
    assert.throws(() => normalizeShelfConfig(broken(value => { value.assetHashes['scene.glb'] = 'unverified'; })), /fingerprint/);
    const badCatalog = plain(catalog);
    badCatalog.books[0].spine = '../escape.png';
    assert.throws(() => R.adoptCatalog(badCatalog), /invalid_book/);
    const badCover = plain(catalog);
    badCover.books[4].chapters[2].cover = 'https://evil.test/disc.png';
    assert.throws(() => R.adoptCatalog(badCover), /invalid_series/);
    const badBox = plain(catalog);
    delete badBox.books[4].boxArt;
    assert.throws(() => R.adoptCatalog(badBox), /invalid_book/);

    const scene = fs.readFileSync(path.join(assets, 'scene.glb'));
    const parsed = validateEmbeddedGlb(scene.buffer.slice(scene.byteOffset, scene.byteOffset + scene.byteLength));
    const nodeNames = new Set(parsed.nodes.map(node => node.name));
    for (const entry of Object.values(config.entries)) {
        for (const mesh of entry.meshes) assert.ok(nodeNames.has(mesh), 'entry mesh exists in GLB: ' + mesh);
    }
    const externalDoc = { asset: { version: '2.0' }, images: [{ uri: 'https://example.invalid/x.png' }] };
    const text = Buffer.from(JSON.stringify(externalDoc));
    const length = Math.ceil(text.length / 4) * 4;
    const fake = Buffer.alloc(20 + length, 0x20);
    fake.writeUInt32LE(0x46546c67, 0); fake.writeUInt32LE(2, 4); fake.writeUInt32LE(fake.length, 8);
    fake.writeUInt32LE(length, 12); fake.writeUInt32LE(0x4e4f534a, 16); text.copy(fake, 20);
    assert.throws(() => validateEmbeddedGlb(fake.buffer.slice(fake.byteOffset, fake.byteOffset + fake.byteLength)), /external/);
    assert.throws(() => validateEmbeddedGlb(new ArrayBuffer(20)), /container/);

    const manifest = JSON.parse(fs.readFileSync(path.join(assets, 'manifest.json'), 'utf8'));
    assert.equal(manifest.schema, 'bookshelf-shelf.v1');
    assert.deepEqual(manifest.audit, audit(scene), 'manifest audit matches the GLB');
    const textureFiles = fs.readdirSync(path.join(assets, 'textures')).filter(name => name.endsWith('.png'));
    assert.ok(manifest.audit.bytes < 1024 * 1024 && manifest.audit.triangles < 4000
        && manifest.audit.images === textureFiles.length && textureFiles.length >= 11,
        'graybox scene stays far below the 8.6MB base-gate reference');
    assert.ok(config.archiveZone && config.archiveZone.max >= 1, 'archive zone configured for runtime slots');
    assert.equal(config.archiveZone.floorY, design.shelf.grid.rowFloors[design.placements.archives.row],
        'archive zone sits on its placement row floor');
    const [ax0, ax1] = design.shelf.columns[design.placements.archives.column];
    assert.ok(config.archiveZone.leftEdge >= ax0
        && config.archiveZone.leftEdge + (config.archiveZone.max + 1) * (config.archiveZone.width + config.archiveZone.gap) <= ax1 + config.archiveZone.gap,
        'archive folders plus the more-box fit their compartment');
    const capacity = design.shelf.bookFillOrder.reduce((sum, cell) => sum + cell.capacity, 0);
    assert.ok(capacity >= design.books.length + 2, 'fill order reserves room for future books');
    for (const cell of design.shelf.bookFillOrder) {
        assert.ok(design.shelf.columns[cell.column] && Number.isInteger(cell.row)
            && cell.row < design.shelf.grid.rowFloors.length && cell.capacity >= 1, 'valid fill cell');
    }
    assert.ok(manifest.artSources && manifest.artSources.files.length > 0
        && manifest.artSources.movies.flat().every(movie => /^[a-f0-9]{64}$/.test(movie.sha256)),
        'extracted art provenance pinned in manifest');
    const closure = new Set();
    for (const entry of manifest.files) {
        const data = fs.readFileSync(path.join(assets, entry.path));
        assert.equal(sha(data), entry.sha256, 'manifest hash: ' + entry.path);
        assert.equal(data.length, entry.bytes, 'manifest bytes: ' + entry.path);
        closure.add(entry.path);
    }
    const actual = [];
    (function walk(dir, prefix) {
        for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
            if (item.isDirectory()) walk(path.join(dir, item.name), prefix + item.name + '/');
            else if (item.name !== 'manifest.json') actual.push(prefix + item.name);
        }
    })(assets, '');
    assert.deepEqual(actual.sort(), [...closure].sort(), 'shelf closure matches manifest');
    for (const book of adopted) {
        const assets_ = book.format === 'playable'
            ? [book.boxArt, ...book.chapters.map(chapter => chapter.cover)]
            : [book.spine];
        for (const asset of assets_) {
            assert.ok(closure.has(asset.replace(/^shelf\//, '')), 'catalog presentation asset in shelf closure: ' + asset);
        }
    }
    const { doc, bin } = glb(scene);
    const embedded = new Map();
    for (const image of doc.images) {
        const view = doc.bufferViews[image.bufferView];
        embedded.set(image.name, bin.slice(view.byteOffset || 0, (view.byteOffset || 0) + view.byteLength));
    }
    for (const [name, png] of embedded) {
        const file = fs.readFileSync(path.join(assets, 'textures', name + '.png'));
        assert.ok(png.equals(file), 'embedded texture equals closure file: ' + name);
    }
    const v4 = JSON.parse(fs.readFileSync(path.join(assets, 'v4-manifest.json'), 'utf8'));
    const activeModel = fs.readFileSync(path.join(assets, v4.model));
    assert.equal(v4.schema, 'bookshelf-interactive.v4');
    assert.equal(v4.model, 'v3.glb');
    assert.equal(sha(activeModel), v4.sha256, 'active model fingerprint');
    assert.deepEqual(audit(activeModel), v4.audit, 'active model audit');
    assert(v4.audit.bytes < 2 * 1024 * 1024 && v4.audit.triangles < 12000 && v4.audit.images === 26);
    const activeDoc = glb(activeModel).doc, activeNames = new Set(activeDoc.nodes.map(node => node.name));
    for (const book of adopted) assert(activeNames.has(book.format === 'playable' ? 'COLLECTION_CF1_6' : 'BOOK_' + book.id));
    for (let i = 1; i <= 6; i++) assert(activeNames.has('DISC_CF' + i), 'active chapter mesh: ' + i);
    assert(activeNames.has('ARCHIVE_ALL_DRAWER'), 'authoritative archive directory');
    const sourcePaths = new Set();
    for (const source of v4.sources) {
        assert(!sourcePaths.has(source.path), 'unique v4 source path'); sourcePaths.add(source.path);
        const data = fs.readFileSync(path.join(root, source.path));
        assert.equal(data.length, source.bytes, 'v4 source bytes: ' + source.path);
        assert.equal(sha(data), source.sha256, 'v4 source hash: ' + source.path);
    }
    console.log('Bookshelf v4 contract: active model and ' + sourcePaths.size + ' sources aligned; '
        + v4.audit.triangles + ' triangles, ' + v4.audit.images + ' embedded images, ' + v4.audit.bytes + ' bytes.');
    console.log('Bookshelf catalog presentation contract: config/catalog/manifest/GLB aligned; '
        + manifest.audit.triangles + ' triangles, ' + manifest.audit.images + ' embedded images, '
        + manifest.audit.bytes + ' bytes; no renderer or Host claim.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
