#!/usr/bin/env node
'use strict';

// dressup-doll-renderer 逐件头部层叠门：
// state.headHairAbove 布尔显式钉住 脸型/发型/面具 绘制顺序（与 AS2
// DressupReferenceManager.refDepths 互换及物品 XML hairAbove 标记同一真源）。
// 用法：node tools/test-dressup-head-layer-order.js

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const timelinePath = path.join(projectRoot, 'launcher', 'web', 'modules', 'asset-timeline.js');
const rendererPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'dressup-doll-renderer.js');
const timelineSource = fs.readFileSync(timelinePath, 'utf8').replace(/^﻿/, '');
const rendererSource = fs.readFileSync(rendererPath, 'utf8').replace(/^﻿/, '');

let failures = 0;
function check(name, cond) {
    if (cond) {
        console.log('PASS: ' + name);
    } else {
        failures++;
        console.error('FAIL: ' + name);
    }
}

function imageName(src) {
    const clean = String(src || '').split(/[?#]/, 1)[0];
    return clean.slice(clean.lastIndexOf('/') + 1);
}

class FakeImage {
    constructor() {
        this.complete = true;
        this.naturalWidth = 8;
        this.naturalHeight = 8;
        this.onload = null;
        this.onerror = null;
        this._src = '';
    }

    set src(value) {
        this._src = value;
    }

    get src() {
        return this._src;
    }
}

function makeContext(draws) {
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
        measureText(text) {
            return { width: String(text || '').length * 6 };
        },
        drawImage(image) {
            draws.push(imageName(image && image.src));
        },
        getImageData() {
            throw new Error('getImageData unavailable in this harness');
        }
    };
}

function skinEntry(name) {
    return {
        covered: true,
        export: { format: 'png', zoom: 1, fps: 24, frameCount: 1, uri: 'skins/' + name + '.png', width: 10, height: 10 },
        frames: [{ frame: 1, sourceFrame: 1, uri: 'skins/' + name + '.png', width: 10, height: 10, originX: 0, originY: 0 }]
    };
}

function holder(field) {
    return { field: field, matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 }, fallbackBasic: false, basic: null };
}

function makeManifest() {
    return {
        __baseUrl: 'http://example.invalid/assets/dressup/manifest.json',
        items: {
            '面具A': {
                use: '头部装备',
                helmet: false,
                fieldsByGender: { '男': { '面具': 'skin_mask' } }
            },
            '面具B': {
                use: '头部装备',
                helmet: false,
                hairAbove: true,
                fieldsByGender: { '男': { '面具': 'skin_mask' } }
            }
        },
        skinKeys: {
            skin_face: skinEntry('face'),
            skin_hair: skinEntry('hair'),
            skin_mask: skinEntry('mask')
        },
        rig: { genders: {} },
        rigs: {
            battle: {
                defaultState: '空手站立',
                genders: {
                    '男': {
                        states: {
                            // 烘焙 rig 顺序即发型压面具（bake 工具重排后的现状）。
                            '空手站立': { holders: [holder('脸型'), holder('面具'), holder('发型')] }
                        }
                    }
                }
            }
        }
    };
}

function drawOrder(context, manifest, state) {
    const draws = [];
    const canvas = {
        width: 0,
        height: 0,
        getBoundingClientRect() {
            return { width: 320, height: 320 };
        },
        getContext() {
            return makeContext(draws);
        }
    };
    const renderer = context.DressupDollRenderer.create(canvas, {
        manifest,
        zoom: 1,
        animate: false,
        pixelRatio: 1
    });
    renderer.render(state);
    renderer.destroy();
    return draws;
}

function main() {
    const context = {
        console,
        URL,
        Image: FakeImage,
        document: { baseURI: 'http://example.invalid/modules/dressup/dev/harness.html' },
        window: {
            devicePixelRatio: 1,
            performance: { now: () => 0 },
            requestAnimationFrame: () => 0,
            cancelAnimationFrame: () => {}
        }
    };
    vm.createContext(context);
    vm.runInContext(timelineSource, context, { filename: 'asset-timeline.js' });
    vm.runInContext(rendererSource, context, { filename: 'dressup-doll-renderer.js' });

    const manifest = makeManifest();
    const appearance = { '脸型': 'skin_face', '发型': 'skin_hair' };

    // 未标记装备：buildStateFromEquipment 钉住 headHairAbove=false，
    // 绘制顺序回落历史默认（脸型<发型<面具，面具压发型）。
    const stateA = context.DressupDollRenderer.buildStateFromEquipment(manifest, {
        gender: '男',
        equipment: { '头部装备': '面具A' },
        appearance: appearance,
        rig: 'battle',
        stateLabel: '空手站立'
    });
    check('未标记装备 state.headHairAbove=false', stateA.headHairAbove === false);
    check('未标记装备绘制顺序 脸型→发型→面具',
        drawOrder(context, manifest, stateA).join(',') === 'face.png,hair.png,mask.png');

    // 标记装备：headHairAbove=true，绘制顺序 脸型<面具<发型（发型压面具）。
    const stateB = context.DressupDollRenderer.buildStateFromEquipment(manifest, {
        gender: '男',
        equipment: { '头部装备': '面具B' },
        appearance: appearance,
        rig: 'battle',
        stateLabel: '空手站立'
    });
    check('标记装备 state.headHairAbove=true', stateB.headHairAbove === true);
    check('标记装备绘制顺序 脸型→面具→发型',
        drawOrder(context, manifest, stateB).join(',') === 'face.png,mask.png,hair.png');

    // raw state 不带布尔标记：保持 rig 烘焙顺序（发型压面具），不被默认值误重排。
    const rawState = { gender: '男', keyMap: { '脸型': 'skin_face', '面具': 'skin_mask', '发型': 'skin_hair' }, rig: 'battle', stateLabel: '空手站立' };
    check('raw state 保持 rig 烘焙顺序 脸型→面具→发型',
        drawOrder(context, manifest, rawState).join(',') === 'face.png,mask.png,hair.png');

    // 显式布尔覆盖优于 manifest 标记：未标记装备也可由调用方钉成发型压面具。
    const overridden = context.DressupDollRenderer.buildStateFromEquipment(manifest, {
        gender: '男',
        equipment: { '头部装备': '面具A' },
        appearance: appearance,
        rig: 'battle',
        stateLabel: '空手站立'
    });
    overridden.headHairAbove = true;
    check('显式 headHairAbove=true 覆盖后绘制 脸型→面具→发型',
        drawOrder(context, manifest, overridden).join(',') === 'face.png,mask.png,hair.png');

    if (failures) {
        console.error('head layer order: ' + failures + ' failed');
        process.exit(1);
    }
    console.log('head layer order: all passed');
}

main();
