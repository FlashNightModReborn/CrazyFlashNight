#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const timelineSource = fs.readFileSync(
    path.join(projectRoot, 'launcher', 'web', 'modules', 'asset-timeline.js'),
    'utf8'
).replace(/^\uFEFF/, '');
const rendererSource = fs.readFileSync(
    path.join(projectRoot, 'launcher', 'web', 'modules', 'dressup-doll-renderer.js'),
    'utf8'
).replace(/^\uFEFF/, '');
const previewSource = fs.readFileSync(
    path.join(projectRoot, 'launcher', 'web', 'modules', 'character-appearance-preview.js'),
    'utf8'
).replace(/^\uFEFF/, '');

class FakeImage {
    constructor() {
        this.complete = true;
        this.naturalWidth = 20;
        this.naturalHeight = 40;
        this.onload = null;
        this.onerror = null;
        this._src = '';
    }
    set src(value) { this._src = String(value || ''); }
    get src() { return this._src; }
}

function fakeContext(draws) {
    return {
        setTransform() {},
        clearRect() {},
        save() {},
        restore() {},
        translate() {},
        scale() {},
        transform() {},
        beginPath() {},
        moveTo() {},
        lineTo() {},
        quadraticCurveTo() {},
        closePath() {},
        fill() {},
        stroke() {},
        fillText() {},
        measureText(value) { return {width:String(value || '').length * 6}; },
        drawImage(value) { if (draws) draws.push(value.src); }
    };
}

function holder(tx, ty) {
    return {
        field:'身体',
        matrix:{a:1, b:0, c:0, d:1, tx, ty},
        fallbackBasic:false,
        basic:null
    };
}

function manifest() {
    const states = {};
    [
        ['空手站立', 0, 0],
        ['长枪站立', 100, 10],
        ['手枪站立', 20, 4],
        ['手枪2站立', 35, 6],
        ['双枪站立', 60, 8],
        ['兵器站立', 80, 2],
        ['手雷站立', 45, 5]
    ].forEach(([label, x, y]) => {
        states[label] = {holders:[holder(x, y)]};
    });
    return {
        __baseUrl:'http://example.invalid/assets/dressup/manifest.json',
        items:{},
        skinKeys:{
            body:{
                export:{format:'png', zoom:1, uri:'skins/body.png', width:20, height:40},
                frames:[{
                    frame:1,
                    sourceFrame:1,
                    uri:'skins/body.png',
                    width:20,
                    height:40,
                    originX:0,
                    originY:0
                }]
            },
            bodyWide:{
                export:{format:'png', zoom:1, uri:'skins/body-wide.png', width:40, height:40},
                frames:[{
                    frame:1,
                    sourceFrame:1,
                    uri:'skins/body-wide.png',
                    width:40,
                    height:40,
                    originX:0,
                    originY:0
                }]
            }
        },
        rigs:{
            battle:{
                defaultState:'空手站立',
                genders:{男:{states}}
            }
        },
        rig:{genders:{男:{holders:[]}}}
    };
}

function state(renderer, data, stateLabel, attackMode, fitEnvelope, bodyKey) {
    return renderer.buildStateFromEquipment(data, {
        gender:'男',
        equipment:{},
        appearance:{身体:bodyKey || 'body'},
        fitFields:['身体'],
        drawFields:['身体'],
        strictFields:true,
        rig:'battle',
        stateLabel,
        attackMode,
        fitEnvelope,
        zoom:1,
        margin:0
    });
}

function sameBounds(actual, expected) {
    ['minX','minY','maxX','maxY'].forEach(key => {
        assert.ok(Math.abs(actual[key] - expected[key]) < 1e-9,
            key + ' differs: ' + actual[key] + ' !== ' + expected[key]);
    });
}

function sameCamera(actual, expected) {
    sameBounds(actual.bounds, expected.bounds);
    ['scale','offsetX','offsetY'].forEach(key => assert.strictEqual(actual[key], expected[key], key));
}

function verifyHelmetAndFraming(Preview, real) {
    const gear = {
        '头部装备':'钛合金61式头部装甲', '上装装备':'钛合金61式胸甲', '下装装备':'钛合金61式腿甲',
        '手部装备':'钛合金61式手甲', '脚部装备':'钛合金61式装甲鞋', '长枪':'M4A1战术版',
        '手枪':'Mossberg500', '手枪2':'Mossberg500', '刀':'热能武士刀', '手雷':'战术核弹手雷'
    };
    const hair = '发型-男式-蓝色头巾';
    const hairUri = new URL(real.skinKeys[hair].export.uri, 'http://example.invalid/').href;
    assert.strictEqual(real.items[gear['头部装备']].helmet, true);
    const draws = [];
    function canvas(width, height) {
        return {width:0, height:0, clientWidth:width, clientHeight:height,
            getBoundingClientRect() { return {width, height}; }, getContext() { return fakeContext(draws); }};
    }
    const expanded = Preview.create(canvas(428, 317), {manifest:real, animate:false});
    const original = Preview.create(canvas(326, 284), {manifest:real, animate:false, maxScale:3});
    const profile = {characterName:'测试', gender:'male', height:175};
    const appearance = {脸型:'男变装-基本脸型', 发型:hair};
    const equippedState = Preview.buildStateFromEquipment(real, {gender:'男', equipment:gear, appearance});
    assert.strictEqual(equippedState.hairHidden, true);
    assert.strictEqual(equippedState.keyMap.发型, '');
    assert.strictEqual(appearance.发型, hair, 'helmet suppression must not mutate the saved hair input');
    draws.length = 0;
    const helmet = expanded.renderProfile(profile, gear, appearance, {zoom:1, margin:12});
    assert.strictEqual(helmet.hairHidden, true);
    assert(!draws.includes(hairUri), 'helmet must prevent the hair image from drawing');
    sameCamera(expanded.renderProfile(profile, gear,
        {脸型:appearance.脸型, 发型:'缺失的发型素材'}, {zoom:1, margin:12}), helmet);
    const old = original.renderProfile(profile, gear, appearance, {zoom:0.8, margin:18});
    const usedHeight = (helmet.contentBounds.maxY - helmet.contentBounds.minY) * helmet.scale;
    assert(helmet.scale > old.scale * 1.2, 'the supplied armor must be visibly larger in the new preview');
    assert(usedHeight / 317 > 0.75, 'the body should occupy at least three quarters of the preview height');
    assert(usedHeight / 317 < 0.94, 'keep room for the maximum height setting');
    const uncoveredGear = Object.assign({}, gear, {'头部装备':''});
    draws.length = 0;
    const uncovered = expanded.renderProfile(profile, uncoveredGear, appearance, {zoom:1, margin:12});
    assert.strictEqual(uncovered.hairHidden, false);
    assert(draws.includes(hairUri), 'taking off the helmet must restore the original hair preview');
    const ordinaryHat = Object.keys(real.items).find(name => real.items[name].use === '头部装备'
        && real.items[name].helmet === false && real.items[name].fieldsByGender.男);
    assert(ordinaryHat, 'non-suppressing headwear fixture exists');
    draws.length = 0;
    const hat = expanded.renderProfile(profile, Object.assign({}, gear, {'头部装备':ordinaryHat}), appearance);
    assert.strictEqual(hat.hairHidden, false);
    assert(draws.includes(hairUri), 'headwear without the helmet flag must not hide hair');
    expanded.destroy(); original.destroy();
    process.stdout.write('Helmet suppression/restoration passed; supplied armor body height '
        + Math.round(usedHeight / 317 * 100) + '% of preview, scale +'
        + Math.round((helmet.scale / old.scale - 1) * 100) + '% over the previous layout\n');
}

function verifySharedPreview(Renderer, Preview, canvas) {
    const data = manifest();
    const weapon = JSON.parse(JSON.stringify(data.skinKeys.body));
    weapon.export.height = weapon.frames[0].height = 4000;
    data.skinKeys.weapon = weapon;
    data.items['光效测试枪'] = {fieldsByGender:{
        男:{'长枪_装扮':'weapon'}, 女:{'长枪_装扮':'weapon'}
    }};
    Object.values(data.rigs.battle.genders.男.states).forEach(value => {
        value.holders.push(Object.assign(holder(0, -4000), {field:'长枪_装扮'}));
        value.holders.push(Object.assign(holder(-4000, 0), {field:'左手'}));
    });
    data.rigs.battle.genders.女 = JSON.parse(JSON.stringify(data.rigs.battle.genders.男));
    Object.values(data.rigs.battle.genders.女.states).forEach(value => {
        value.holders[0].matrix.d = 1.5;
    });
    let callbackMeta;
    const preview = Preview.create(canvas, {manifest:data, animate:false, margin:0, zoom:1,
        onRender(meta) { callbackMeta = meta; }});
    const equipment = {'长枪':'光效测试枪'};
    const appearance = {身体:'body', 左手:'body'};
    const neutral = Renderer.buildStateFromEquipment(data, {
        gender:'男', equipment, appearance, stateLabel:'空手站立', margin:0, zoom:1
    });
    const stable = preview.render(neutral);
    assert(stable.fitEnvelopeApplied);
    assert.strictEqual(stable.drawnImages, 3, 'weapons and hands still draw outside the body framing');
    assert.strictEqual(neutral.fitEnvelope, undefined, 'the preview must not mutate caller state');
    const raw = Renderer.create(canvas, {manifest:data, animate:false});
    assert(raw.render(neutral).scale < stable.scale, 'regression fixture must reproduce effect-driven shrinking');
    raw.destroy();
    Preview.cameraEnvelopePoses().forEach(pose => {
        sameCamera(preview.render(Object.assign({}, neutral, pose)), stable);
    });
    // The weapon gets ten times taller; the person and camera must stay exactly where they were.
    weapon.export.height = weapon.frames[0].height = 40000;
    sameCamera(preview.render(neutral), stable);
    sameCamera(preview.setPixelRatio(2), stable);
    const view = {margin:0, zoom:1};
    const profile = {characterName:'测试', gender:'male', height:175};
    sameCamera(preview.renderProfile(profile, equipment, appearance, view), stable);
    sameCamera(preview.renderProfile(Object.assign({}, profile, {height:200}), equipment, appearance, view), stable);
    // Height is a separate visual scale, so autofit must not cancel the slider's change.
    const Controls = require('../launcher/web/modules/character-identity-controls.js');
    assert(Controls.previewScale(200) > Controls.previewScale(150));
    const female = preview.renderProfile(Object.assign({}, profile, {gender:'female'}), equipment, appearance, view);
    assert.notStrictEqual(female.bounds.maxY, stable.bounds.maxY, 'gender changes recompute the body envelope');
    const wider = preview.renderProfile(profile, equipment, {身体:'bodyWide'}, view);
    assert.notStrictEqual(wider.bounds.maxX, stable.bounds.maxX, 'new clothing recomputes the envelope');
    preview.renderProfile(profile, {'长枪':'缺失物品'}, appearance, view);
    assert.deepStrictEqual(Array.from(callbackMeta.missingItems), ['长枪']);
    preview.destroy();

    const real = JSON.parse(fs.readFileSync(path.join(projectRoot,
        'launcher/web/assets/dressup/manifest.json'), 'utf8'));
    verifyHelmetAndFraming(Preview, real);
    const realPreview = Preview.create(canvas, {manifest:real, animate:false, maxScale:12});
    const outfit = {'上装装备':'黑色功夫装', '下装装备':'咖啡色多包裤', '脚部装备':'棕色皮鞋'};
    let comparisons = 0;
    ['男', '女'].forEach(gender => {
        const face = {脸型:gender + '变装-基本脸型'};
        Preview.cameraEnvelopePoses().forEach(pose => {
            const options = Object.assign({gender, equipment:outfit, appearance:face}, pose);
            const baseline = realPreview.render(Renderer.buildStateFromEquipment(real, options));
            ['TYPE79', '激光剑', '主唱光剑', '光剑天秤', '血色光剑天秤'].forEach(name => {
                const item = real.items[name];
                assert(item, 'production weapon fixture exists: ' + name);
                const equipped = Object.assign({}, outfit, {[item.use]:name});
                const measured = realPreview.render(Renderer.buildStateFromEquipment(real,
                    Object.assign({}, options, {equipment:equipped})));
                sameCamera(measured, baseline);
                comparisons++;
            });
        });
    });
    realPreview.destroy();
    return comparisons;
}

function main() {
    let now = 0;
    const context = {
        console,
        URL,
        Image:FakeImage,
        fetch:null,
        document:{baseURI:'http://example.invalid/'},
        window:{
            devicePixelRatio:1,
            performance:{now:() => now},
            requestAnimationFrame:() => 0,
            cancelAnimationFrame() {}
        }
    };
    vm.createContext(context);
    vm.runInContext(timelineSource, context, {filename:'asset-timeline.js'});
    vm.runInContext(rendererSource, context, {filename:'dressup-doll-renderer.js'});
    context.window.DressupDollRenderer = context.DressupDollRenderer;
    vm.runInContext(previewSource, context, {filename:'character-appearance-preview.js'});

    const Renderer = context.DressupDollRenderer;
    const Preview = context.window.CharacterAppearancePreview;
    const data = manifest();
    const empty = state(Renderer, data, '空手站立', '空手');
    const longGun = state(Renderer, data, '长枪站立', '长枪');

    const emptyMeasure = Renderer.measureState(data, empty);
    const gunMeasure = Renderer.measureState(data, longGun);
    sameBounds(emptyMeasure.bounds, {minX:0, minY:0, maxX:20, maxY:40});
    sameBounds(gunMeasure.bounds, {minX:100, minY:10, maxX:120, maxY:50});
    assert.strictEqual(emptyMeasure.fitHolders, 1);
    assert.strictEqual(emptyMeasure.stateLabel, '空手站立');

    const envelope = {minX:-8, minY:-8, maxX:128, maxY:58};
    const copied = state(Renderer, data, '空手站立', '空手', envelope);
    envelope.minX = -999;
    assert.strictEqual(copied.fitEnvelope.minX, -8,
        'buildStateFromEquipment must copy the stable envelope');

    const canvas = {
        width:0,
        height:0,
        clientWidth:240,
        clientHeight:200,
        getBoundingClientRect() { return {width:240, height:200}; },
        getContext() { return fakeContext(); }
    };
    const renderer = Renderer.create(canvas, {
        manifest:data,
        animate:false,
        zoom:1,
        margin:0
    });
    const poses = Preview.cameraEnvelopePoses();
    const pureEnvelope = Renderer.measureEnvelope(data, empty, poses, {}, 0.06);
    sameBounds(pureEnvelope, {minX:-7.2, minY:-3, maxX:127.2, maxY:53});
    const stableEnvelope = renderer.measureEnvelope(empty, poses, 0.06);
    sameBounds(stableEnvelope, pureEnvelope);
    const stabilized = Renderer.withFitEnvelope(
        renderer, empty, poses, 0.06);
    sameBounds(stabilized.fitEnvelope, pureEnvelope);
    const wider = state(
        Renderer, data, '空手站立', '空手', null, 'bodyWide');
    const widerEnvelope = renderer.measureEnvelope(wider, poses, 0.06);
    sameBounds(widerEnvelope, {minX:-8.4, minY:-3, maxX:148.4, maxY:53});
    assert.notStrictEqual(widerEnvelope.maxX, stableEnvelope.maxX,
        'equipment/appearance changes must recompute the fit envelope');
    const stableEmpty = renderer.render(
        state(Renderer, data, '空手站立', '空手', stableEnvelope)
    );
    now += 16;
    const stableGun = renderer.render(
        state(Renderer, data, '长枪站立', '长枪', stableEnvelope)
    );
    assert.strictEqual(stableEmpty.fitEnvelopeApplied, true);
    assert.strictEqual(stableGun.fitEnvelopeApplied, true);
    sameBounds(stableEmpty.bounds, pureEnvelope);
    sameBounds(stableGun.bounds, pureEnvelope);
    assert.strictEqual(stableEmpty.scale, stableGun.scale);
    assert.strictEqual(stableEmpty.offsetX, stableGun.offsetX);
    assert.strictEqual(stableEmpty.offsetY, stableGun.offsetY);
    assert.notStrictEqual(stableEmpty.contentBounds.minX, stableGun.contentBounds.minX);

    const dynamicGun = renderer.render(longGun);
    assert.strictEqual(dynamicGun.fitEnvelopeApplied, false);
    sameBounds(dynamicGun.bounds, gunMeasure.bounds);
    renderer.destroy();

    assert.deepStrictEqual(
        Array.from(poses, value => value.stateLabel),
        ['空手站立','长枪站立','手枪站立','手枪2站立','双枪站立','兵器站立','手雷站立']
    );
    poses[0].stateLabel = '被调用方修改';
    assert.strictEqual(Preview.cameraEnvelopePoses()[0].stateLabel, '空手站立',
        'pose envelope API must return fresh values');

    const comparisons = verifySharedPreview(Renderer, Preview, canvas);
    process.stdout.write('Dressup stable fit passed; shared preview: giant effects, 7 poses, gender/clothing/height, '
        + comparisons + ' production weapon comparisons (no browser or image loading)\n');
}

main();
