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
const poseSource = fs.readFileSync(
    path.join(projectRoot, 'launcher', 'web', 'modules', 'character-build',
        'character-build-pose.js'),
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

function fakeContext() {
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
        drawImage() {}
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
    vm.runInContext(poseSource, context, {filename:'character-build-pose.js'});

    const Renderer = context.DressupDollRenderer;
    const Pose = context.window.CharacterBuildPose;
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
    const poses = Pose.cameraEnvelopePoses();
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
    assert.strictEqual(Pose.cameraEnvelopePoses()[0].stateLabel, '空手站立',
        'pose envelope API must return fresh values');

    process.stdout.write('Dressup stable fit passed\n');
}

main();
