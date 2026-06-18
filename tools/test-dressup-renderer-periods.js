#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const timelinePath = path.join(projectRoot, 'launcher', 'web', 'modules', 'asset-timeline.js');
const rendererPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'dressup-doll-renderer.js');
const timelineSource = fs.readFileSync(timelinePath, 'utf8').replace(/^\uFEFF/, '');
const rendererSource = fs.readFileSync(rendererPath, 'utf8').replace(/^\uFEFF/, '');

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
        }
    };
}

function frame(prefix, index) {
    return {
        frame: index,
        sourceFrame: index,
        uri: `${prefix}${index}.png`,
        width: 10,
        height: 10,
        originX: 0,
        originY: 0
    };
}

function frames(prefix, count) {
    const out = [];
    for (let i = 1; i <= count; i += 1) out.push(frame(prefix, i));
    return out;
}

function compressedLayerAFrames() {
    return [
        frame('skins/a', 1),
        { ...frame('skins/a', 2), uri: 'skins/a1.png', duplicateOfFrame: 1 },
        frame('skins/a', 3),
        { ...frame('skins/a', 4), uri: 'skins/a3.png', duplicateOfFrame: 3 },
        frame('skins/a', 5)
    ];
}

function compressedLayerATimeline() {
    return [
        { ...frame('skins/a', 1), durationFrames: 2, frameEnd: 2, sourceFrameEnd: 2 },
        { ...frame('skins/a', 3), durationFrames: 2, frameEnd: 4, sourceFrameEnd: 4 },
        frame('skins/a', 5)
    ];
}

function makeManifest() {
    return {
        __baseUrl: 'http://example.invalid/assets/dressup/manifest.json',
        items: {},
        skinKeys: {
            multi: {
                export: {
                    format: 'png',
                    zoom: 1,
                    fps: 1,
                    uri: 'skins/base.png',
                    width: 10,
                    height: 10,
                    playback: 'nested-animation',
                    nestedAnimation: {
                        strategy: 'direct-layered',
                        layers: [
                            {
                                characterId: 101,
                                drawOrder: 'over',
                                matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 },
                                export: {
                                    format: 'png-sequence',
                                    zoom: 1,
                                    fps: 1,
                                    frameCount: 5,
                                    logicalFrameCount: 5,
                                    timelineFrameCount: 3,
                                    compressedFrameRefs: 2
                                },
                                frames: compressedLayerAFrames(),
                                timelineFrames: compressedLayerATimeline()
                            },
                            {
                                characterId: 102,
                                drawOrder: 'over',
                                matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 },
                                export: { format: 'png-sequence', zoom: 1, fps: 1, frameCount: 7 },
                                frames: frames('skins/b', 7)
                            }
                        ]
                    }
                },
                frames: [
                    {
                        frame: 1,
                        sourceFrame: 1,
                        uri: 'skins/base.png',
                        width: 10,
                        height: 10,
                        originX: 0,
                        originY: 0
                    }
                ]
            }
        },
        rig: {
            genders: {
                male: {
                    holders: [
                        {
                            field: 'body',
                            matrix: { a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0 }
                        }
                    ]
                }
            }
        }
    };
}

function expectedDraws(nowMs) {
    const tick = Math.floor(nowMs / 1000);
    const layerAByTick = ['a1.png', 'a1.png', 'a3.png', 'a3.png', 'a5.png'];
    return [
        'base.png',
        layerAByTick[tick % layerAByTick.length],
        `b${(tick % 7) + 1}.png`
    ];
}

function main() {
    let nowMs = 0;
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
    const context = {
        console,
        URL,
        Image: FakeImage,
        fetch: null,
        document: { baseURI: 'http://example.invalid/modules/dressup/dev/harness.html' },
        window: {
            devicePixelRatio: 1,
            performance: { now: () => nowMs },
            requestAnimationFrame: () => 0,
            cancelAnimationFrame: () => {}
        }
    };
    vm.createContext(context);
    vm.runInContext(timelineSource, context, { filename: 'asset-timeline.js' });
    vm.runInContext(rendererSource, context, { filename: 'dressup-doll-renderer.js' });

    const manifest = makeManifest();
    const renderer = context.DressupDollRenderer.create(canvas, {
        manifest,
        zoom: 1,
        fps: 1
    });
    const state = { gender: 'male', keyMap: { body: 'multi' } };
    const samples = [0, 1000, 2000, 6000, 7000, 34000];
    const results = [];
    for (const sample of samples) {
        nowMs = sample;
        draws.length = 0;
        const meta = renderer.render(state);
        results.push({
            nowMs,
            draws: draws.slice(),
            expected: expectedDraws(sample),
            animated: Boolean(meta && meta.animated)
        });
    }
    renderer.destroy();

    const failures = results.filter(result => (
        !result.animated ||
        result.draws.length !== result.expected.length ||
        result.draws.some((value, index) => value !== result.expected[index])
    ));
    const frameBudget = manifest.skinKeys.multi.export.nestedAnimation.layers
        .reduce((sum, layer) => sum + layer.frames.length, 0);
    const timelineBudget = manifest.skinKeys.multi.export.nestedAnimation.layers
        .reduce((sum, layer) => sum + ((layer.timelineFrames && layer.timelineFrames.length) || layer.frames.length), 0);
    const payload = {
        frameBudget,
        timelineBudget,
        lcmWouldBe: 35,
        results
    };
    process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
    if (frameBudget !== 12 || timelineBudget !== 10 || failures.length) process.exit(1);
}

main();
