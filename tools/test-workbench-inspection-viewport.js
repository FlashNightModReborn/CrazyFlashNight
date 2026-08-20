#!/usr/bin/env node
'use strict';

const assert = require('assert');
const InspectionViewport = require(
    '../launcher/web/modules/workbench-inspection-viewport.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

class FakeClassList {
    constructor() { this.values = {}; }
    add(...names) {
        names.forEach(name => { if (name) this.values[name] = true; });
    }
    remove(...names) {
        names.forEach(name => { delete this.values[name]; });
    }
    contains(name) { return !!this.values[name]; }
}

class FakeStyle {
    constructor() { this.values = {}; }
    get transform() { return this.values.transform || ''; }
    set transform(value) { this.values.transform = String(value); }
    removeProperty(name) { delete this.values[name]; }
}

class FakeNode {
    constructor(tagName, ownerDocument) {
        this.tagName = String(tagName || 'div').toUpperCase();
        this.ownerDocument = ownerDocument;
        this.parentNode = null;
        this.children = [];
        this.attributes = {};
        this.classList = new FakeClassList();
        this.style = new FakeStyle();
        this.listeners = {};
        this.disabled = false;
        this.textContent = '';
        this.type = '';
        this.clientWidth = 200;
        this.clientHeight = 100;
        this.rect = {left:10, top:20, width:400, height:200};
        this.capturedPointers = {};
    }
    set className(value) {
        this.classList = new FakeClassList();
        String(value || '').split(/\s+/).forEach(name => this.classList.add(name));
    }
    get className() { return Object.keys(this.classList.values).join(' '); }
    appendChild(node) {
        if (node.parentNode) node.parentNode.removeChild(node);
        node.parentNode = this;
        this.children.push(node);
        return node;
    }
    removeChild(node) {
        const index = this.children.indexOf(node);
        if (index >= 0) this.children.splice(index, 1);
        node.parentNode = null;
        return node;
    }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name)
            ? this.attributes[name] : null;
    }
    hasAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name);
    }
    removeAttribute(name) { delete this.attributes[name]; }
    addEventListener(type, handler, options) {
        (this.listeners[type] = this.listeners[type] || []).push({handler, options});
    }
    removeEventListener(type, handler, options) {
        const list = this.listeners[type] || [];
        const index = list.findIndex(entry =>
            entry.handler === handler && entry.options === options);
        if (index >= 0) list.splice(index, 1);
    }
    dispatch(type, init) {
        const event = Object.assign({
            type,
            target:this,
            currentTarget:this,
            defaultPrevented:false,
            preventDefault() { this.defaultPrevented = true; }
        }, init || {});
        (this.listeners[type] || []).slice().forEach(entry => entry.handler(event));
        return event;
    }
    listenerCount(type) { return (this.listeners[type] || []).length; }
    querySelectorAll(selector) {
        const result = [];
        this.children.forEach(child => {
            if ((selector === 'button' && child.tagName === 'BUTTON')
                    || (selector === '[data-inspection-action]'
                        && child.hasAttribute('data-inspection-action'))) {
                result.push(child);
            }
            result.push(...child.querySelectorAll(selector));
        });
        return result;
    }
    getBoundingClientRect() {
        return Object.assign({
            right:this.rect.left + this.rect.width,
            bottom:this.rect.top + this.rect.height
        }, this.rect);
    }
    setPointerCapture(pointerId) { this.capturedPointers[pointerId] = true; }
    hasPointerCapture(pointerId) { return !!this.capturedPointers[pointerId]; }
    releasePointerCapture(pointerId) { delete this.capturedPointers[pointerId]; }
    focus() { this.ownerDocument.activeElement = this; }
}

class FakeDocument {
    constructor() { this.activeElement = null; }
    createElement(tagName) { return new FakeNode(tagName, this); }
}

function action(root, name) {
    return root.querySelectorAll('button').find(
        button => button.getAttribute('data-inspection-action') === name);
}

function setup(options) {
    const document = new FakeDocument();
    const host = document.createElement('footer');
    const viewport = document.createElement('section');
    const target = document.createElement('canvas');
    const overlay = document.createElement('aside');
    overlay.style.transform = 'translateX(9px)';
    viewport.appendChild(target);
    viewport.appendChild(overlay);
    const changes = [];
    const camera = InspectionViewport.create(Object.assign({
        document,
        viewport,
        target,
        controlsHost:host,
        minZoom:1,
        maxZoom:3,
        fitZoom:1,
        defaultZoom:1.5,
        zoomStep:0.2,
        panStep:34,
        resetLabel:'重置',
        onChange(state, reason) {
            changes.push({state, reason});
        }
    }, options || {}));
    return {document, host, viewport, target, overlay, changes, camera};
}

test('exports a constructible shared camera without activating embedded previews', () => {
    assert.strictEqual(typeof InspectionViewport.Camera, 'function');
    assert.strictEqual(typeof InspectionViewport.create, 'function');
    const probe = setup();
    const state = probe.camera.debugState();
    assert.deepStrictEqual(state, {
        enabled:false,
        zoom:1.5,
        panX:0,
        panY:0,
        dragging:false,
        minimum:1,
        maximum:3
    });
    assert.strictEqual(probe.target.style.transform, '');
    assert.strictEqual(probe.viewport.style.transform, '');
    assert.strictEqual(probe.overlay.style.transform, 'translateX(9px)');
    assert(probe.camera.controls.querySelectorAll('button').every(button => button.disabled));

    const wheel = probe.viewport.dispatch('wheel', {
        deltaY:-100, clientX:210, clientY:120
    });
    const key = probe.viewport.dispatch('keydown', {key:'+'});
    const down = probe.viewport.dispatch('pointerdown', {
        pointerId:4, button:0, clientX:100, clientY:80
    });
    assert.strictEqual(wheel.defaultPrevented, false);
    assert.strictEqual(key.defaultPrevented, false);
    assert.strictEqual(down.defaultPrevented, false);
    assert.deepStrictEqual(probe.camera.debugState(), state);
});

test('zoom, pan, reset, controls, and resize transform only the declared target', () => {
    const probe = setup();
    assert.strictEqual(probe.camera.activate({reset:true}), true);
    assert.strictEqual(probe.camera.debugState().zoom, 1.5);
    assert.strictEqual(
        probe.target.style.transform,
        'translate3d(0px,0px,0) scale(1.5)');
    assert.strictEqual(probe.viewport.style.transform, '');
    assert.strictEqual(probe.overlay.style.transform, 'translateX(9px)');
    assert(probe.camera.controls.querySelectorAll('button').every(button => !button.disabled));

    assert.strictEqual(probe.camera.setZoom(2, 310, 120), true);
    const anchored = probe.camera.debugState();
    assert.strictEqual(anchored.enabled, true);
    assert.strictEqual(anchored.zoom, 2);
    assert(Math.abs(anchored.panX - (-50 / 3)) < 0.000001);
    assert.strictEqual(anchored.panY, 0);
    assert(probe.target.style.transform.includes('translate3d(-17px,0px,0) scale(2)'));
    assert.strictEqual(probe.overlay.style.transform, 'translateX(9px)');

    probe.camera.setZoom(99);
    assert.strictEqual(probe.camera.debugState().zoom, 3);
    probe.camera.setZoom(-99);
    assert.strictEqual(probe.camera.debugState().zoom, 1);

    action(probe.camera.controls, 'reset').dispatch('click');
    assert.strictEqual(probe.camera.debugState().zoom, 1.5);
    action(probe.camera.controls, 'fit').dispatch('click');
    assert.strictEqual(probe.camera.debugState().zoom, 1);
    action(probe.camera.controls, 'zoom-in').dispatch('click');
    assert.strictEqual(probe.camera.debugState().zoom, 1.2);

    probe.camera.reset(3, {panX:100, panY:50});
    probe.viewport.clientWidth = 40;
    probe.viewport.clientHeight = 20;
    assert.strictEqual(probe.camera.resize(), true);
    assert.strictEqual(probe.camera.debugState().panX, 40);
    assert.strictEqual(probe.camera.debugState().panY, 20);
    assert(probe.changes.some(change => change.reason === 'resize'));

    const offsetProbe = setup({
        resetOffset(zoom) { return {panX:zoom > 1 ? 28 : 0}; }
    });
    offsetProbe.camera.activate({reset:true});
    assert.strictEqual(offsetProbe.camera.debugState().panX, 28);
    action(offsetProbe.camera.controls, 'fit').dispatch('click');
    assert.strictEqual(offsetProbe.camera.debugState().panX, 0);
    action(offsetProbe.camera.controls, 'reset').dispatch('click');
    assert.strictEqual(offsetProbe.camera.debugState().panX, 28);

    const expandedProbe = setup({
        defaultZoom:1,
        resetOffset() { return {panX:96, panY:-72}; },
        panBounds() { return {x:120, y:90}; }
    });
    expandedProbe.camera.activate({reset:true});
    assert.strictEqual(expandedProbe.camera.debugState().panX, 96);
    assert.strictEqual(expandedProbe.camera.debugState().panY, -72);
    expandedProbe.camera.shift(999, -999);
    assert.strictEqual(expandedProbe.camera.debugState().panX, 120);
    assert.strictEqual(expandedProbe.camera.debugState().panY, -90);
});

test('wheel, keyboard, drag, pointercancel, and lost capture share one bounded state', () => {
    const probe = setup();
    probe.camera.activate({reset:true});

    const wheel = probe.viewport.dispatch('wheel', {
        deltaY:-100, clientX:210, clientY:120
    });
    assert.strictEqual(wheel.defaultPrevented, true);
    assert.strictEqual(probe.camera.debugState().zoom, 1.7);

    const home = probe.viewport.dispatch('keydown', {key:'Home'});
    assert.strictEqual(home.defaultPrevented, true);
    assert.strictEqual(probe.camera.debugState().zoom, 1);
    const zero = probe.viewport.dispatch('keydown', {key:'0'});
    assert.strictEqual(zero.defaultPrevented, true);
    assert.strictEqual(probe.camera.debugState().zoom, 1.5);
    const plus = probe.viewport.dispatch('keydown', {key:'+'});
    assert.strictEqual(plus.defaultPrevented, true);
    assert.strictEqual(probe.camera.debugState().zoom, 1.7);
    const left = probe.viewport.dispatch('keydown', {key:'ArrowLeft'});
    assert.strictEqual(left.defaultPrevented, true);
    assert.strictEqual(probe.camera.debugState().panX, -34);
    const unrelated = probe.viewport.dispatch('keydown', {key:'Enter'});
    assert.strictEqual(unrelated.defaultPrevented, false);

    probe.camera.reset(2);
    const down = probe.viewport.dispatch('pointerdown', {
        pointerId:7, button:0, clientX:100, clientY:80
    });
    assert.strictEqual(down.defaultPrevented, true);
    assert.strictEqual(probe.viewport.hasPointerCapture(7), true);
    probe.viewport.dispatch('pointermove', {
        pointerId:7, clientX:140, clientY:100
    });
    assert.strictEqual(probe.camera.debugState().panX, 20);
    assert.strictEqual(probe.camera.debugState().panY, 10);
    probe.viewport.dispatch('pointercancel', {pointerId:7});
    assert.strictEqual(probe.camera.debugState().dragging, false);
    assert.strictEqual(probe.viewport.hasPointerCapture(7), false);

    probe.viewport.dispatch('pointerdown', {
        pointerId:8, button:0, clientX:140, clientY:100
    });
    assert.strictEqual(probe.camera.debugState().dragging, true);
    probe.viewport.dispatch('lostpointercapture', {pointerId:8});
    assert.strictEqual(probe.camera.debugState().dragging, false);
    assert.strictEqual(probe.viewport.hasPointerCapture(8), false);
});

test('deactivate and destroy reset presentation and deterministically release ownership', () => {
    const probe = setup();
    const buttons = probe.camera.controls.querySelectorAll('button').slice();
    probe.camera.activate({reset:true});
    probe.camera.setZoom(2);
    probe.viewport.dispatch('pointerdown', {
        pointerId:9, button:0, clientX:100, clientY:80
    });
    assert.strictEqual(probe.camera.deactivate(), true);
    assert.strictEqual(probe.target.style.transform, '');
    assert.strictEqual(probe.overlay.style.transform, 'translateX(9px)');
    assert.strictEqual(probe.viewport.hasAttribute('data-inspection-active'), false);
    assert.strictEqual(probe.viewport.hasPointerCapture(9), false);
    assert.deepStrictEqual(probe.camera.debugState(), {
        enabled:false,
        zoom:1.5,
        panX:0,
        panY:0,
        dragging:false,
        minimum:1,
        maximum:3
    });

    const inactiveWheel = probe.viewport.dispatch('wheel', {
        deltaY:-100, clientX:210, clientY:120
    });
    assert.strictEqual(inactiveWheel.defaultPrevented, false);
    assert.strictEqual(probe.target.style.transform, '');

    assert.strictEqual(probe.host.children.length, 1);
    assert.strictEqual(probe.camera.destroy(), true);
    assert.strictEqual(probe.camera.destroy(), false);
    assert.strictEqual(probe.host.children.length, 0);
    assert.strictEqual(probe.viewport.hasAttribute('tabindex'), false);
    assert.strictEqual(
        probe.viewport.classList.contains('workbench-inspection-viewport'), false);
    assert.strictEqual(
        probe.target.classList.contains('workbench-inspection-target'), false);
    ['pointerdown', 'pointermove', 'pointerup', 'pointercancel',
        'lostpointercapture', 'wheel', 'keydown'].forEach(type => {
        assert.strictEqual(probe.viewport.listenerCount(type), 0, type);
    });
    buttons.forEach(button => assert.strictEqual(button.listenerCount('click'), 0));
});

process.stdout.write(
    'workbench inspection viewport: ' + passed + '/' + passed + ' passed\n');
