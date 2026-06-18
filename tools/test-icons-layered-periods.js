#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const timelinePath = path.join(projectRoot, 'launcher', 'web', 'modules', 'asset-timeline.js');
const iconsPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'icons.js');
const timelineSource = fs.readFileSync(timelinePath, 'utf8').replace(/^\uFEFF/, '');
const iconsSource = fs.readFileSync(iconsPath, 'utf8').replace(/^\uFEFF/, '');

function frames(prefix, count, crop) {
    const out = [];
    for (let i = 1; i <= count; i += 1) {
        const entry = { frame: i, uri: `${prefix}${i}.png` };
        if (crop) {
            Object.assign(entry, {
                cropX: crop.x + (i % 3),
                cropY: crop.y,
                cropWidth: crop.width,
                cropHeight: crop.height,
                canvasWidth: 256,
                canvasHeight: 256
            });
        }
        out.push(entry);
    }
    return out;
}

function makeManifest() {
    return {
        multi: {
            f1: 'base.png',
            playback: 'nested-animation',
            animated: true,
            fps: 1,
            nestedAnimation: {
                strategy: 'direct-layered-icon-canvas',
                base: { uri: 'base.png' },
                layers: [
                    { characterId: 101, fps: 1, frames: frames('a', 5) },
                    { characterId: 102, fps: 1, frames: frames('b', 7) }
                ]
            }
        },
        singleLong: {
            f1: 'single_base.png',
            playback: 'nested-animation',
            animated: true,
            fps: 1,
            nestedAnimation: {
                strategy: 'direct-layered-icon-canvas',
                base: { uri: 'single_base.png' },
                layers: [
                    { characterId: 252, fps: 1, frames: frames('ice', 120, { x: 25, y: 2, width: 199, height: 247 }) }
                ]
            }
        },
        cropMotion: {
            f1: 'crop_base.png',
            playback: 'nested-animation',
            animated: true,
            fps: 1,
            nestedAnimation: {
                strategy: 'direct-layered-icon-canvas',
                base: { uri: 'crop_base.png' },
                layers: [
                    {
                        characterId: 303,
                        fps: 1,
                        frames: [
                            {
                                frame: 1,
                                uri: 'crop_shared.png',
                                cropX: 0,
                                cropY: 0,
                                cropWidth: 128,
                                cropHeight: 128,
                                canvasWidth: 256,
                                canvasHeight: 256
                            },
                            {
                                frame: 2,
                                uri: 'crop_shared.png',
                                cropX: 64,
                                cropY: 0,
                                cropWidth: 128,
                                cropHeight: 128,
                                canvasWidth: 256,
                                canvasHeight: 256
                            }
                        ]
                    }
                ]
            }
        },
        staticOnly: {
            f1: 'static_1.png',
            playback: 'static-first-frame',
            animated: false
        }
    };
}

class FakeImage {
    constructor() {
        this.src = '';
    }
}

class FakeElement {
    constructor(attrs) {
        this.nodeType = 1;
        this.attrs = Object.assign({}, attrs || {});
        this.children = [];
    }

    append(child) {
        child.parentNode = this;
        this.children.push(child);
        return child;
    }

    getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attrs, name) ? this.attrs[name] : null;
    }

    setAttribute(name, value) {
        this.attrs[name] = String(value);
    }

    removeAttribute(name) {
        delete this.attrs[name];
    }

    querySelector(selector) {
        const all = this.querySelectorAll(selector);
        return all.length ? all[0] : null;
    }

    querySelectorAll(selector) {
        const result = [];
        const matches = node => {
            if (selector === '[data-icon-layered-name]') {
                return node.getAttribute('data-icon-layered-name') !== null;
            }
            if (selector === 'img[data-icon-name]') {
                return node.getAttribute('data-icon-name') !== null;
            }
            if (selector === 'img[data-icon-name][data-icon-animated="1"]') {
                return node.getAttribute('data-icon-name') !== null &&
                    node.getAttribute('data-icon-animated') === '1';
            }
            if (selector === '[data-icon-layered-name][data-icon-layered-animated="1"]') {
                return node.getAttribute('data-icon-layered-name') !== null &&
                    node.getAttribute('data-icon-layered-animated') === '1';
            }
            if (selector === 'img[data-icon-layer-base="1"]') {
                return node.getAttribute('data-icon-layer-base') === '1';
            }
            const layerMatch = selector.match(/^img\[data-icon-layer-index="(\d+)"\]$/);
            if (layerMatch) {
                return node.getAttribute('data-icon-layer-index') === layerMatch[1];
            }
            return false;
        };
        const walk = node => {
            if (matches(node)) result.push(node);
            node.children.forEach(walk);
        };
        this.children.forEach(walk);
        return result;
    }
}

function makeLayeredNode(name) {
    const wrapper = new FakeElement({
        'data-icon-layered-name': name || 'multi',
        'data-icon-fps': '1'
    });
    wrapper.append(new FakeElement({ 'data-icon-layer-base': '1' }));
    wrapper.append(new FakeElement({ 'data-icon-layer-index': '0' }));
    if ((name || 'multi') === 'multi') {
        wrapper.append(new FakeElement({ 'data-icon-layer-index': '1' }));
    }
    return wrapper;
}

function expectedAt(nowMs) {
    const tick = Math.floor(nowMs / 1000);
    return {
        layerA: `icons/a${(tick % 5) + 1}.png`,
        layerB: `icons/b${(tick % 7) + 1}.png`
    };
}

async function main() {
    const manifest = makeManifest();
    const callbacks = [];
    const layeredNode = makeLayeredNode('multi');
    const singleNode = makeLayeredNode('singleLong');
    const cropNode = makeLayeredNode('cropMotion');
    const layeredNodes = [layeredNode, singleNode, cropNode];
    const documentElement = {
        contains: node => layeredNodes.some(layered => node === layered || layered.children.includes(node))
    };
    const document = {
        documentElement,
        querySelectorAll(selector) {
            if (selector === '[data-icon-layered-name][data-icon-layered-animated="1"]') {
                return layeredNodes.filter(node => node.getAttribute('data-icon-layered-animated') === '1');
            }
            if (selector === 'img[data-icon-name][data-icon-animated="1"]') return [];
            return [];
        }
    };
    const context = {
        console,
        Image: FakeImage,
        document,
        window: {
            requestAnimationFrame(callback) {
                callbacks.push(callback);
                return callbacks.length;
            }
        },
        fetch() {
            return Promise.resolve({ json: () => Promise.resolve(manifest) });
        }
    };
    vm.createContext(context);
    vm.runInContext(timelineSource, context, { filename: 'asset-timeline.js' });
    vm.runInContext(iconsSource, context, { filename: 'icons.js' });
    await new Promise(resolve => context.Icons.load(resolve));

    const html = context.Icons.html('multi', 'test-icon');
    const singleHtml = context.Icons.html('singleLong', 'test-icon');
    context.Icons.enhance(layeredNode);
    context.Icons.enhance(singleNode);
    context.Icons.enhance(cropNode);
    const frameBudget = manifest.multi.nestedAnimation.layers.reduce(
        (sum, layer) => sum + layer.frames.length,
        0
    );
    const singleFrameBudget = manifest.singleLong.nestedAnimation.layers.reduce(
        (sum, layer) => sum + layer.frames.length,
        0
    );
    const samples = [0, 6000, 7000, 34000];
    const results = [];
    for (const nowMs of samples) {
        const callback = callbacks.shift();
        if (typeof callback !== 'function') {
            throw new Error('Icons did not schedule an animation frame.');
        }
        callback(nowMs);
        const expected = expectedAt(nowMs);
        results.push({
            nowMs,
            layerA: layeredNode.children[1].getAttribute('src'),
            layerB: layeredNode.children[2].getAttribute('src'),
            singleLayer: singleNode.children[1].getAttribute('src'),
            expectedSingleLayer: `icons/ice${(Math.floor(nowMs / 1000) % 120) + 1}.png`,
            cropStyle: cropNode.children[1].getAttribute('style') || '',
            expectedCropLeft: Math.floor(nowMs / 1000) % 2 === 0 ? 'left:0.0000%;' : 'left:25.0000%;',
            expected
        });
    }

    const staticHtml = context.Icons.html('staticOnly', 'test-icon');
    const payload = {
        frameBudget,
        lcmWouldBe: 35,
        singleFrameBudget,
        htmlHasWrapper: /data-icon-layered-name="multi"/.test(html),
        htmlHasLayers: /data-icon-layer-index="0"/.test(html) && /data-icon-layer-index="1"/.test(html),
        singleHtmlHasWrapper: /data-icon-layered-name="singleLong"/.test(singleHtml),
        singleHtmlHasOneLayer: /data-icon-layer-index="0"/.test(singleHtml) && !/data-icon-layer-index="1"/.test(singleHtml),
        singleHtmlHasCropStyle: /left:10\.\d+%;top:0\.7813%;width:77\.7344%;height:96\.4844%/.test(singleHtml),
        singleNodeHasCropStyle: /left:10\.\d+%;top:0\.7813%;width:77\.7344%;height:96\.4844%/.test(singleNode.children[1].getAttribute('style') || ''),
        cropMotionAnimated: cropNode.getAttribute('data-icon-layered-animated') === '1',
        cropMotionUsesSameUri: cropNode.children[1].getAttribute('src') === 'icons/crop_shared.png',
        staticNotLayered: !/data-icon-layered-name/.test(staticHtml),
        results
    };
    process.stdout.write(JSON.stringify(payload, null, 2) + '\n');

    const failures = results.filter(result => (
        result.layerA !== result.expected.layerA ||
        result.layerB !== result.expected.layerB ||
        result.singleLayer !== result.expectedSingleLayer ||
        result.cropStyle.indexOf(result.expectedCropLeft) === -1
    ));
    if (
        frameBudget !== 12 ||
        singleFrameBudget !== 120 ||
        !payload.htmlHasWrapper ||
        !payload.htmlHasLayers ||
        !payload.singleHtmlHasWrapper ||
        !payload.singleHtmlHasOneLayer ||
        !payload.singleHtmlHasCropStyle ||
        !payload.singleNodeHasCropStyle ||
        !payload.cropMotionAnimated ||
        !payload.cropMotionUsesSameUri ||
        !payload.staticNotLayered ||
        failures.length
    ) {
        process.exit(1);
    }
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
