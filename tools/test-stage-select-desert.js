'use strict';
// Contract checks use the current authoritative catalog and reject malformed visual inputs.
// Browser/GLB/Host acceptance is intentionally separate.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const { pathToFileURL } = require('url');
const root = path.resolve(__dirname, '..');

async function main() {
    const context = {};
    for (const file of ['launcher/web/modules/stage-select-data.js',
        'launcher/web/modules/stage-select/stage-select-desert-data.js']) {
        vm.runInNewContext(fs.readFileSync(path.join(root, file), 'utf8'), context, { filename: file });
    }
    const plain = value => JSON.parse(JSON.stringify(value));
    const catalog = plain(context.StageSelectData.exportManifest());
    const frame = catalog.frames.find(item => item.frameLabel === '基地房顶');
    const routing = plain(context.StageSelectDesertData);
    const module = await import(pathToFileURL(path.join(root, 'launcher/web/modules/stage-select/stage-select-desert-config.js')).href);
    const { normalizeDesertConfig, validateEmbeddedGlb, layoutDesertPins, WORLD_STAGE_IDS } = module;
    const twoDimensional = ['stage_34_8', 'stage_34_9'];
    assert.deepEqual([...WORLD_STAGE_IDS].sort(), frame.stageButtons.map(item => item.id).filter(id => !twoDimensional.includes(id)).sort());
    assert.deepEqual(routing.worldStageIds, [...WORLD_STAGE_IDS]);
    assert.deepEqual(routing.twoDimensionalStageIds, twoDimensional);
    assert.deepEqual(Object.keys(routing.fallbackPins).sort(), frame.stageButtons.map(item => item.id).sort());
    assert.deepEqual(Object.keys(routing.navPins).sort(), frame.navButtons.map(item => item.id).sort());
    assert.equal(frame.stageButtons.find(item => item.id === 'stage_34_10').entryKind, 'map');
    assert.equal(frame.navButtons.find(item => item.id === 'nav_34_1').targetFrameLabel, '沙漠虫洞');
    assert.equal(catalog.frames.find(item => item.frameLabel === '沙漠虫洞').navButtons.find(item => item.id === 'nav_46_0').targetFrameLabel, '基地房顶');
    assert.equal(routing.fallback, frame.background.assetUrl);
    const source = {
        schema: 1, camera: { gltfPosition: [40, 80, 110], gltfTarget: [0, 0, 0], horizontalSpan: 150, maxSpan: 600 },
        assetHashes: { 'scene.glb': 'a'.repeat(64) }, pins: Object.fromEntries(WORLD_STAGE_IDS.map((id, i) => [id, {
            worldAnchor: [i * 3, 0, i * -2], focusBounds: { min: [i * 3 - 1, 0, i * -2 - 1], max: [i * 3 + 1, 2, i * -2 + 1] },
            screenOffset: i === 0 ? [-24, 0] : [0, 0]
        }]))
    };
    const frozen = JSON.stringify(source), normalized = normalizeDesertConfig(source);
    assert.equal(JSON.stringify(source), frozen, 'validation must not mutate the producer input');
    assert.equal(normalized.camera.minSpan, 1.5);
    assert.deepEqual(normalized.pins.stage_34_0.screenOffset, [-24, 0]);
    const broken = mutate => { const value = plain(source); mutate(value); return value; };
    assert.equal(normalizeDesertConfig(broken(value => value.pins.stage_34_0.placeId = 'refugees')).pins.stage_34_0.placeId, 'refugees');
    assert.throws(() => normalizeDesertConfig(broken(value => value.pins.stage_34_0.placeId = '../environment')), /owner/);
    const subareas = count => Array.from({ length: count }, (_, i) => ({ id: 'area-' + i, label: '第' + (i + 1) + '段',
        subStageIndex: i, sourceBackground: 'source-map-' + i + '.png',
        worldBounds: { min: [i * 2, 0, 0], max: [i * 2 + 1, 1, 1] }, worldCenter: [i * 2 + .5, .5, .5] }));
    const withAreas = broken(value => { value.pins.stage_34_1.subareas = subareas(3); value.pins.stage_34_4.subareas = subareas(4); });
    assert.equal(normalizeDesertConfig(withAreas).pins.stage_34_1.subareas[2].subStageIndex, 2);
    assert.deepEqual(normalizeDesertConfig(withAreas).pins.stage_34_4.subareas[3].worldCenter, [6.5, .5, .5]);
    assert.throws(() => normalizeDesertConfig(broken(value => value.pins.stage_34_1.subareas = subareas(4))), /subarea count/);
    assert.throws(() => normalizeDesertConfig(broken(value => value.pins.stage_34_0.subareas = subareas(3))), /subarea count/);
    for (const mutate of [areas => { areas[1].id = areas[0].id; }, areas => { areas[1].subStageIndex = areas[0].subStageIndex; },
        areas => { [areas[0], areas[1]] = [areas[1], areas[0]]; }, areas => { areas[2].subStageIndex = 3; },
        areas => { areas[0].sourceBackground = ''; }, areas => { areas[0].worldBounds.max[0] = -1; },
        areas => { areas[0].worldCenter[0] = Infinity; }]) {
        assert.throws(() => normalizeDesertConfig(broken(value => { value.pins.stage_34_1.subareas = subareas(3); mutate(value.pins.stage_34_1.subareas); })), /subarea|vector/);
    }
    assert.throws(() => normalizeDesertConfig(broken(value => delete value.pins.stage_34_7)), /identity/);
    assert.throws(() => normalizeDesertConfig(broken(value => value.pins.stage_34_8 = value.pins.stage_34_0)), /identity/);
    assert.throws(() => normalizeDesertConfig(broken(value => value.camera.gltfPosition[0] = NaN)), /vector/);
    assert.equal(normalizeDesertConfig(broken(value => value.camera.minSpan = 1.5)).camera.minSpan, 1.5);
    for (const minSpan of [0, 1.49, NaN, 151]) {
        assert.throws(() => normalizeDesertConfig(broken(value => value.camera.minSpan = minSpan)), /camera/);
    }
    assert.throws(() => normalizeDesertConfig(broken(value => value.pins.stage_34_0.focusBounds.max[0] = -5)), /bounds/);
    assert.throws(() => normalizeDesertConfig(broken(value => value.assetHashes['scene.glb'] = 'unverified')), /fingerprint/);
    assert.throws(() => normalizeDesertConfig(broken(value => value.pins.stage_34_0.screenOffset = [999, 0])), /offset/);
    function glb(document) {
        const text = Buffer.from(JSON.stringify(document));
        const length = Math.ceil(text.length / 4) * 4, buffer = Buffer.alloc(20 + length, 0x20);
        buffer.writeUInt32LE(0x46546c67, 0); buffer.writeUInt32LE(2, 4); buffer.writeUInt32LE(buffer.length, 8);
        buffer.writeUInt32LE(length, 12); buffer.writeUInt32LE(0x4e4f534a, 16); text.copy(buffer, 20);
        return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
    }
    validateEmbeddedGlb(glb({ asset: { version: '2.0' }, buffers: [{ byteLength: 0 }], images: [{ bufferView: 0 }] }));
    assert.throws(() => validateEmbeddedGlb(glb({ images: [{ uri: 'https://example.invalid/texture.png' }] })), /external/);
    assert.throws(() => validateEmbeddedGlb(glb({ buffers: [{ uri: '../outside.bin' }] })), /external/);
    assert.throws(() => validateEmbeddedGlb(new ArrayBuffer(20)), /container/);
    const projected = Object.fromEntries(WORLD_STAGE_IDS.map((id, i) => [id, {
        ...normalized.pins[id], x: 120 + (i % 3) * 290, y: 120 + Math.floor(i / 3) * 130
    }]));
    const arranged = layoutDesertPins(projected, routing.screenPins);
    for (const id of WORLD_STAGE_IDS) {
        assert.equal(arranged.pins[id].x, projected[id].x);
        assert.equal(arranged.pins[id].y, projected[id].y);
        assert.deepEqual(arranged.pins[id].worldAnchor, projected[id].worldAnchor);
    }
    assert.deepEqual(arranged.failures, []);
    assert.deepEqual(arranged.pins.stage_34_8, routing.screenPins.stage_34_8);
    const assetConfig = path.join(root, 'launcher/web/assets/stage-diorama/desert-region/config.json');
    let actualAssetConfig = false;
    if (fs.existsSync(assetConfig)) {
        normalizeDesertConfig(JSON.parse(fs.readFileSync(assetConfig, 'utf8')));
        actualAssetConfig = true;
    }
    console.log(JSON.stringify({ pass: true, worldEntries: WORLD_STAGE_IDS.length, screenEntries: twoDimensional.length,
        navigationEntries: frame.navButtons.length, actualAssetConfig,
        scope: 'Current catalog/visual config/embedded-GLB boundary; no renderer, Host, or game acceptance' }));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
