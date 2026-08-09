#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { audit, EXPECTED_CLOSURE } = require('./audit-arena-portrait-coverage');
const {
    KNOWN_UNAVAILABLE_MERC_SKIN_KEYS,
    LEGACY_EQUIPMENT_ALIASES,
    inspectDressupPortrait,
    inspectMercDressupPortrait,
    isDressupPortraitRef
} = require('./lib/arena-portrait-routing');

const ROOT = path.resolve(__dirname, '..');
const units = require(path.join(ROOT, 'data', 'units', 'units.json'));
const enemyManifest = require(path.join(ROOT, 'launcher', 'web', 'assets', 'enemy-portraits', 'manifest.json'));
const dressupManifest = require(path.join(ROOT, 'launcher', 'web', 'assets', 'dressup', 'manifest.json'));
const mercenaries = require(path.join(ROOT, 'data', 'merc', 'mercenaries.json'))
    .filter(merc => merc && !merc.hidden && Number(merc.level) > 0 && merc.id != null && merc.name != null);

function inspectRgbaPng(filePath) {
    const buffer = fs.readFileSync(filePath);
    assert(buffer.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])),
        `${filePath} must retain a PNG signature`);
    let offset = 8;
    let width = 0;
    let height = 0;
    const idat = [];
    while (offset + 12 <= buffer.length) {
        const length = buffer.readUInt32BE(offset);
        const type = buffer.toString('ascii', offset + 4, offset + 8);
        const dataStart = offset + 8;
        const dataEnd = dataStart + length;
        assert(dataEnd + 4 <= buffer.length, `${filePath} must not contain a truncated PNG chunk`);
        if (type === 'IHDR') {
            width = buffer.readUInt32BE(dataStart);
            height = buffer.readUInt32BE(dataStart + 4);
            assert.strictEqual(buffer[dataStart + 8], 8, `${filePath} must retain 8-bit channels`);
            assert.strictEqual(buffer[dataStart + 9], 6, `${filePath} must retain RGBA color`);
            assert.strictEqual(buffer[dataStart + 12], 0, `${filePath} must remain non-interlaced`);
        } else if (type === 'IDAT') {
            idat.push(buffer.subarray(dataStart, dataEnd));
        }
        offset = dataEnd + 4;
        if (type === 'IEND') break;
    }
    assert(width > 0 && height > 0 && idat.length > 0, `${filePath} must contain IHDR and IDAT data`);
    const packed = zlib.inflateSync(Buffer.concat(idat));
    const stride = width * 4;
    assert.strictEqual(packed.length, height * (stride + 1), `${filePath} scanline size must match IHDR`);
    const decoded = Buffer.alloc(height * stride);
    for (let y = 0; y < height; y += 1) {
        const filter = packed[y * (stride + 1)];
        const sourceOffset = y * (stride + 1) + 1;
        const targetOffset = y * stride;
        for (let x = 0; x < stride; x += 1) {
            const raw = packed[sourceOffset + x];
            const left = x >= 4 ? decoded[targetOffset + x - 4] : 0;
            const up = y > 0 ? decoded[targetOffset - stride + x] : 0;
            const upLeft = y > 0 && x >= 4 ? decoded[targetOffset - stride + x - 4] : 0;
            let value;
            if (filter === 0) value = raw;
            else if (filter === 1) value = raw + left;
            else if (filter === 2) value = raw + up;
            else if (filter === 3) value = raw + Math.floor((left + up) / 2);
            else if (filter === 4) {
                const estimate = left + up - upLeft;
                const leftDistance = Math.abs(estimate - left);
                const upDistance = Math.abs(estimate - up);
                const upLeftDistance = Math.abs(estimate - upLeft);
                value = raw + (leftDistance <= upDistance && leftDistance <= upLeftDistance
                    ? left : (upDistance <= upLeftDistance ? up : upLeft));
            } else {
                assert.fail(`${filePath} uses unsupported PNG filter ${filter}`);
            }
            decoded[targetOffset + x] = value & 0xff;
        }
    }
    let nonTransparentPixels = 0;
    for (let index = 3; index < decoded.length; index += 4) {
        if (decoded[index] > 0) nonTransparentPixels += 1;
    }
    return { bytes: buffer.length, width, height, nonTransparentPixels };
}

const current = audit();
assert.deepStrictEqual(current.errors, [], 'current Arena portrait closure must pass');
assert.strictEqual(current.coverage.total, EXPECTED_CLOSURE.total);
assert.strictEqual(current.coverage.ready, EXPECTED_CLOSURE.ready);
assert.strictEqual(current.coverage.missing, EXPECTED_CLOSURE.missing);
assert.strictEqual(current.assets.humanAcceptedVariantCount, EXPECTED_CLOSURE.humanAcceptedVariantCount);
assert.strictEqual(current.assets.checkedBindingCount, EXPECTED_CLOSURE.checkedBindingCount);
assert.strictEqual(current.assets.uniqueFileCount, EXPECTED_CLOSURE.uniqueFileCount);
assert.strictEqual(Object.keys(LEGACY_EQUIPMENT_ALIASES).length, 4,
    'only four genuine naming aliases may remain after the ancient armor assets are exported');
for (const ancientItem of ['远古诛神头盔', '远古诛神胸甲', '远古诛神腿甲', '远古诛神战鞋']) {
    assert(!Object.prototype.hasOwnProperty.call(LEGACY_EQUIPMENT_ALIASES, ancientItem),
        `${ancientItem} must resolve through its real virtual item and must never alias to ordinary Godslayer armor`);
}
assert.strictEqual(LEGACY_EQUIPMENT_ALIASES['远古诛神手套'], '黄金骑士牙狼手套',
    'only the ancient glove may reuse its audited canonical owner');
assert.strictEqual(current.dressup.legacyEquipmentAliasOccurrenceCount, 8,
    'all eight concrete naming-alias occurrences must resolve canonically');
assert.strictEqual(current.dressup.legacyVirtualItemDefinitionCount, 4,
    'the four ancient armor items must remain narrow manifest virtual items');
assert.strictEqual(current.dressup.legacyVirtualItemOccurrenceCount, 4,
    'unit 235 must remain the only consumer of the four ancient virtual armor items');
assert.strictEqual(current.dressup.legacyVirtualSkinKeyCount, 10,
    'the ancient head/body/leg/foot closure must retain ten exact runtime skin keys');
assert.strictEqual(current.dressup.legacyCompatibilityCheckCount, 20,
    'the known twenty alias/virtual definition and occurrence regression checks must remain closed');
assert.deepStrictEqual(Object.keys(KNOWN_UNAVAILABLE_MERC_SKIN_KEYS), ['军绿防弹衣']);
assert.strictEqual(KNOWN_UNAVAILABLE_MERC_SKIN_KEYS['军绿防弹衣'].length, 3,
    'only the three audited unavailable army-green vest arm skins may pass');
for (const merc of mercenaries) {
    assert(inspectMercDressupPortrait(merc).portrait,
        `visible mercenary ${merc.id} must retain a resolvable dressup projection`);
}

const driftManifest = JSON.parse(JSON.stringify(dressupManifest));
let driftMerc = null;
let driftSkinKey = '';
for (const merc of mercenaries) {
    const gender = String(merc.gender) === '男' ? '男' : '女';
    for (const itemName of Object.values(merc.equipment || {})) {
        const rawName = String(itemName || '').split('#', 1)[0];
        if (!rawName || KNOWN_UNAVAILABLE_MERC_SKIN_KEYS[rawName]) continue;
        const item = driftManifest.items[rawName];
        const fields = item && item.fieldsByGender && item.fieldsByGender[gender];
        const candidate = fields && Object.values(fields).find(key => (
            driftManifest.skinKeys[key] && driftManifest.skinKeys[key].covered === true
        ));
        if (candidate) { driftMerc = merc; driftSkinKey = candidate; break; }
    }
    if (driftMerc) break;
}
assert(driftMerc && driftSkinKey, 'fixture requires a covered non-allowlisted mercenary skin');
driftManifest.skinKeys[driftSkinKey].covered = false;
const driftProjection = inspectMercDressupPortrait(driftMerc, { manifest: driftManifest });
assert.strictEqual(driftProjection.portrait, null,
    'a newly uncovered non-allowlisted mercenary skin must fail closed');
assert(driftProjection.issues.some(item => item.code === 'equipment_skin_uncovered'
    && item.detail === driftSkinKey));

const dressupUnit = units.find(unit => isDressupPortraitRef(unit && unit.spritename));
assert(dressupUnit, 'fixture requires one dressup unit');
const invalidUnit = JSON.parse(JSON.stringify(dressupUnit));
invalidUnit.data.head = '__arena_unknown_equipment__';
const invalidProjection = inspectDressupPortrait(invalidUnit);
assert.strictEqual(invalidProjection.portrait, null, 'unknown equipment must fail closed');
assert(invalidProjection.issues.some(item => item.code === 'unknown_equipment'));

const ancientUnit = units.find(unit => Number(unit && unit.id) === 235);
assert(ancientUnit && ancientUnit.data, 'fixture requires unit 235');
assert.deepStrictEqual({
    head: ancientUnit.data.head,
    body: ancientUnit.data.body,
    hand: ancientUnit.data.hand,
    leg: ancientUnit.data.leg,
    foot: ancientUnit.data.foot
}, {
    head: '远古诛神头盔',
    body: '远古诛神胸甲',
    hand: '远古诛神手套',
    leg: '远古诛神腿甲',
    foot: '远古诛神战鞋'
}, 'unit 235 source tuple must retain the real ancient armor identity');
const ancientProjection = inspectDressupPortrait(ancientUnit);
assert(ancientProjection.portrait, 'unit 235 must project after the exact ancient assets are exported');
assert.deepStrictEqual(ancientProjection.portrait.actor, {
    gender: '男',
    face: '男变装-基本脸型',
    hair: '',
    equipment: {
        head: '远古诛神头盔',
        body: '远古诛神胸甲',
        hand: '黄金骑士牙狼手套',
        leg: '远古诛神腿甲',
        foot: '远古诛神战鞋',
        neck: '远古诛神项链',
        primary: '远古诛神枪',
        secondary: '远古诛神短枪',
        secondary2: '远古诛神短枪',
        melee: '远古诛神剑'
    }
}, 'unit 235 actor tuple must preserve the source identity; only the hand uses its canonical item owner');

const expectedAncientFields = {
    '远古诛神头盔': ['男变装-远古诛神头盔'],
    '远古诛神胸甲': [
        '男变装-远古诛神胸甲身体', '男变装-远古诛神胸甲上臂',
        '男变装-远古诛神胸甲左下臂', '男变装-远古诛神胸甲右下臂'
    ],
    '远古诛神腿甲': [
        '男变装-远古诛神腿甲屁股', '男变装-远古诛神腿甲左大腿',
        '男变装-远古诛神腿甲右大腿', '男变装-远古诛神腿甲小腿'
    ],
    '远古诛神战鞋': ['男变装-远古诛神战鞋']
};
const expectedAncientExports = {
    '男变装-远古诛神头盔': { uri: 'skins/dd78e490_1.png', width: 269, height: 302 },
    '男变装-远古诛神战鞋': { uri: 'skins/4fd89007_1.png', width: 259, height: 184 },
    '男变装-远古诛神胸甲身体': { uri: 'skins/a8dfe0f8_1.png', width: 1000, height: 1024 },
    '男变装-远古诛神胸甲上臂': { uri: 'skins/fb50bc57_1.png', width: 225, height: 319 },
    '男变装-远古诛神胸甲左下臂': { uri: 'skins/8ad1c9a5_1.png', width: 123, height: 253 },
    '男变装-远古诛神胸甲右下臂': { uri: 'skins/e91f3204_1.png', width: 206, height: 246 },
    '男变装-远古诛神腿甲屁股': { uri: 'skins/3f64de8f_1.png', width: 645, height: 509 },
    '男变装-远古诛神腿甲左大腿': { uri: 'skins/e1961378_1.png', width: 212, height: 364 },
    '男变装-远古诛神腿甲右大腿': { uri: 'skins/8258e8d9_1.png', width: 214, height: 375 },
    '男变装-远古诛神腿甲小腿': { uri: 'skins/57952ba8_1.png', width: 286, height: 356 }
};
let ancientExportBytes = 0;
for (const [itemName, expectedKeys] of Object.entries(expectedAncientFields)) {
    const item = dressupManifest.items[itemName];
    assert(item && item.virtual === true && Number(item.sourceUnitId) === 235,
        `${itemName} must remain a unit-235-scoped virtual item`);
    assert.deepStrictEqual(Object.values(item.fieldsByGender['男']), expectedKeys,
        `${itemName} must bind the exact ancient skin keys`);
    for (const skinKey of expectedKeys) {
        const skin = dressupManifest.skinKeys[skinKey];
        assert(skin && skin.covered === true && skin.export && skin.export.uri,
            `${skinKey} must have a real runtime export`);
        const expectedExport = expectedAncientExports[skinKey];
        assert(expectedExport, `${skinKey} must have a locked runtime export fixture`);
        assert.strictEqual(skin.export.uri, expectedExport.uri, `${skinKey} runtime URI must not drift`);
        const exportPath = path.join(ROOT, 'launcher', 'web', 'assets', 'dressup', skin.export.uri);
        assert(fs.existsSync(exportPath), `${skinKey} exported PNG must exist`);
        const image = inspectRgbaPng(exportPath);
        assert.deepStrictEqual({ width: image.width, height: image.height }, {
            width: expectedExport.width,
            height: expectedExport.height
        }, `${skinKey} pixel dimensions must not drift`);
        assert(image.nonTransparentPixels > 0, `${skinKey} must contain non-transparent pixels`);
        ancientExportBytes += image.bytes;
    }
}
assert.strictEqual(Object.keys(expectedAncientExports).length, 10,
    'the unit-235 runtime export fixture must lock exactly ten PNGs');
assert.strictEqual(ancientExportBytes, 2536431,
    'the ten unit-235 runtime PNGs must retain the audited 2,536,431-byte footprint');
const ancientGlove = dressupManifest.items['黄金骑士牙狼手套'];
assert.deepStrictEqual(Object.values(ancientGlove.fieldsByGender['男']), [
    '男变装-远古诛神手套左手', '男变装-远古诛神手套右手'
], 'the canonical glove owner must retain both exact ancient hand skin keys');
assert.deepStrictEqual([
    ...Object.values(expectedAncientFields).flat(),
    ...Object.values(ancientGlove.fieldsByGender['男'])
], [
    '男变装-远古诛神头盔',
    '男变装-远古诛神胸甲身体', '男变装-远古诛神胸甲上臂',
    '男变装-远古诛神胸甲左下臂', '男变装-远古诛神胸甲右下臂',
    '男变装-远古诛神腿甲屁股', '男变装-远古诛神腿甲左大腿',
    '男变装-远古诛神腿甲右大腿', '男变装-远古诛神腿甲小腿',
    '男变装-远古诛神战鞋',
    '男变装-远古诛神手套左手', '男变装-远古诛神手套右手'
], 'unit 235 must retain the exact twelve ancient armor skin keys, including both canonical glove exports');

const negativeManifest = JSON.parse(JSON.stringify(enemyManifest));
let removedRef = '';
for (const unit of units) {
    const ref = String(unit && unit.spritename || '').trim();
    const entry = negativeManifest.entries && negativeManifest.entries[ref];
    const variant = entry && entry.variants && entry.variants[entry.defaultVariant];
    if (!isDressupPortraitRef(ref) && variant && variant.status === 'human_accepted') {
        delete entry.variants[entry.defaultVariant];
        removedRef = ref;
        break;
    }
}
assert(removedRef, 'fixture requires a directly bound accepted default variant');
const negative = audit({ enemyManifest: negativeManifest });
assert(negative.errors.length > 0, 'deleting one default variant must fail the gate');
assert(negative.coverage.missing > 0, 'deleting one default variant must create locked fallback debt');
assert(negative.coverage.ready < EXPECTED_CLOSURE.ready, 'deleting one default variant must regress ready coverage');
assert.strictEqual(negative.assets.humanAcceptedVariantCount,
    EXPECTED_CLOSURE.humanAcceptedVariantCount - 1,
    'the negative fixture must remove exactly one accepted variant');

process.stdout.write('Arena portrait coverage regression tests passed.\n');
