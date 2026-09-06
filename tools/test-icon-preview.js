#!/usr/bin/env node
'use strict';

// 局部预览的生命周期与播放契约；使用可控时钟，避免按真实时间等待动画。
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class Element {
    constructor() { this.attrs = {}; this.style = {}; this.children = []; }
    setAttribute(key, value) { this.attrs[key] = String(value); }
    getAttribute(key) { return this.attrs[key] ?? null; }
    removeAttribute(key) { delete this.attrs[key]; }
    appendChild(child) { child.parentNode = this; this.children.push(child); return child; }
    removeChild(child) { this.children.splice(this.children.indexOf(child), 1); child.parentNode = null; }
}

function runtime() {
    const pending = new Map();
    let next = 0, fetches = 0;
    const published = { f1: 'published.png' };
    const context = vm.createContext({
        document: { createElement: () => new Element() },
        window: {
            requestAnimationFrame: callback => { pending.set(++next, callback); return next; },
            cancelAnimationFrame: id => pending.delete(id)
        },
        fetch: async () => { fetches++; return { json: async () => ({ existing: published }) }; }
    });
    for (const file of ['asset-timeline.js', 'icons.js']) {
        vm.runInContext(fs.readFileSync(path.join(__dirname, '../launcher/web/modules', file), 'utf8'), context);
    }
    return {
        icons: context.Icons, host: new Element(), pending, published,
        get fetches() { return fetches; },
        frame(now) {
            const callbacks = [...pending.values()]; pending.clear();
            callbacks.forEach(callback => callback(now));
        }
    };
}

let passed = 0;
async function check(name, run) {
    await run(); passed++; console.log('PASS ' + name);
}

(async () => {
    await check('动图直接使用 WebP；停播显示封面；不触发共享缓存或 JS 帧循环', async () => {
        const env = runtime();
        await new Promise(resolve => env.icons.load(resolve));
        assert.equal(env.icons.entry('existing'), env.published);
        const entry = { format: 'webp-animated', f1: 'cover.webp', uri: 'https://asset-workbench.local/job/animated.webp' };
        let preview = env.icons.createPreview(env.host, entry, { animate: true });
        const image = env.host.children[0].children[0];
        assert.equal(image.getAttribute('src'), entry.uri);
        assert.equal(preview.animated, true);
        assert.equal(env.pending.size, 0);
        preview.destroy();
        assert.equal(image.getAttribute('src'), null);
        preview = env.icons.createPreview(env.host, entry, { animate: false });
        assert.equal(env.host.children[0].children[0].getAttribute('src'), 'icons/cover.webp');
        assert.equal(env.icons.entry('existing'), env.published);
        assert.equal(env.fetches, 1);
        preview.destroy();
    });

    await check('序列按持续帧数播放并循环，销毁后不再调度', () => {
        const env = runtime();
        const preview = env.icons.createPreview(env.host, {
            f1: 'a.png', animated: true, fps: 10,
            frames: [{ frame: 1, uri: 'a.png', durationFrames: 2 }, { frame: 2, uri: 'b.png' }]
        }, { animate: true });
        const image = env.host.children[0].children[0];
        env.frame(5000); env.frame(5199);
        assert.equal(image.getAttribute('src'), 'icons/a.png');
        env.frame(5200); assert.equal(image.getAttribute('src'), 'icons/b.png');
        env.frame(5300); assert.equal(image.getAttribute('src'), 'icons/a.png');
        const lateCallback = [...env.pending.values()][0];
        preview.destroy(); preview.destroy(); lateCallback(5500);
        assert.equal(env.pending.size, 0);
        assert.equal(env.host.children.length, 0);
        assert.equal(image.getAttribute('src'), null);
    });

    await check('嵌套图层各自计时；相同图片的位置变化也能播放', () => {
        const env = runtime();
        const preview = env.icons.createPreview(env.host, {
            f1: 'cover.png', playback: 'nested-animation', fps: 1,
            nestedAnimation: { base: { uri: 'base.png' }, layers: [
                { frames: [{ uri: 'same.png', cropX: 0, cropY: 0, cropWidth: 128, cropHeight: 128, canvasWidth: 256, canvasHeight: 256 },
                    { uri: 'same.png', cropX: 64, cropY: 0, cropWidth: 128, cropHeight: 128, canvasWidth: 256, canvasHeight: 256 }] },
                { fps: 2, frames: [{ uri: 'b1.png' }, { uri: 'b2.png' }, { uri: 'b3.png' }] }
            ] }
        }, { animate: true });
        const [base, moving, flashing] = env.host.children[0].children;
        assert.equal(base.getAttribute('src'), 'icons/base.png');
        env.frame(0); env.frame(1000);
        assert.match(moving.getAttribute('style'), /left:25\.0000%/);
        assert.equal(flashing.getAttribute('src'), 'icons/b3.png');
        env.frame(2000);
        assert.match(moving.getAttribute('style'), /left:0\.0000%/);
        assert.equal(flashing.getAttribute('src'), 'icons/b2.png');
        preview.destroy(); assert.equal(env.pending.size, 0);
    });

    await check('物品图标和完整展示两个槽位不能被误当成动画', () => {
        const env = runtime();
        const preview = env.icons.createPreview(env.host, { f1: 'icon.png', f2: 'display.png' }, { animate: true });
        assert.equal(preview.animated, false);
        assert.equal(env.host.children[0].children[0].getAttribute('src'), 'icons/icon.png');
        assert.equal(env.pending.size, 0);
        preview.destroy();
    });

    await check('缺图、图片错误与销毁不会影响旁边的消费者', () => {
        const env = runtime();
        const sibling = env.host.appendChild(new Element());
        let errors = 0;
        const preview = env.icons.createPreview(env.host, null, { animate: true, onError: () => errors++ });
        assert.equal(preview.available, false);
        const image = env.host.children[1].children[0], lateError = image.onerror;
        lateError(); assert.equal(errors, 1);
        preview.destroy(); lateError();
        assert.equal(errors, 1);
        assert.equal(env.host.children.length, 1);
        assert.equal(env.host.children[0], sibling);
        assert.equal(env.pending.size, 0);
    });
    console.log(passed + ' icon preview checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
