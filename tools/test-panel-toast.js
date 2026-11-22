'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const TOAST_PATH = path.resolve(__dirname, '..', 'launcher', 'web', 'modules', 'toast.js');
const TOAST_SOURCE = fs.readFileSync(TOAST_PATH, 'utf8');

let passed = 0;
function check(name, callback) {
    callback();
    passed++;
    process.stdout.write('PASS ' + name + '\n');
}

function createFakeElement(tag) {
    const attrs = Object.create(null);
    const classes = new Set();
    const styles = Object.create(null);
    const el = {
        tagName: String(tag || 'div').toUpperCase(),
        id: '',
        className: '',
        hidden: false,
        textContent: '',
        parentNode: null,
        children: [],
        offsetWidth: 100,
        _rect: { left: 100, top: 40, width: 1024, height: 640 },
        style: {
            display: '',
            setProperty(k, v) { styles[k] = String(v); },
            removeProperty(k) { delete styles[k]; },
            getPropertyValue(k) { return styles[k] || ''; },
            _map: styles
        },
        classList: {
            add(...names) { names.forEach(n => classes.add(n)); },
            remove(...names) { names.forEach(n => classes.delete(n)); },
            contains(name) { return classes.has(name); }
        },
        setAttribute(k, v) { attrs[k] = String(v); },
        getAttribute(k) { return Object.prototype.hasOwnProperty.call(attrs, k) ? attrs[k] : null; },
        appendChild(child) {
            if (child.parentNode && child.parentNode.children) {
                const idx = child.parentNode.children.indexOf(child);
                if (idx >= 0) child.parentNode.children.splice(idx, 1);
            }
            child.parentNode = this;
            this.children.push(child);
            return child;
        },
        querySelector(sel) {
            for (let i = 0; i < this.children.length; i++) {
                const child = this.children[i];
                if (sel === '.panel-feedback-icon' && child.className === 'panel-feedback-icon') return child;
                if (sel === '.panel-feedback-text' && child.className === 'panel-feedback-text') return child;
                if (sel === '.panel-scale-shell:not([hidden])' && child.className === 'panel-scale-shell' && !child.hidden) return child;
                const deep = child.querySelector(sel);
                if (deep) return deep;
            }
            return null;
        },
        getBoundingClientRect() { return this._rect; }
    };
    return el;
}

function createHarness(options) {
    options = options || {};
    let panelOpen = options.panelOpen !== false;
    const bridgeSent = [];
    const audioCues = [];
    const timers = new Map();
    let nextTimerId = 1;

    const container = createFakeElement('div');
    container.id = 'panel-container';
    container.hidden = !panelOpen;
    const content = createFakeElement('div');
    content.id = 'panel-content';
    const scaleShell = createFakeElement('div');
    scaleShell.className = 'panel-scale-shell';
    scaleShell._rect = { left: 120, top: 60, width: 1280, height: 720 };
    content.appendChild(scaleShell);
    container.appendChild(content);
    const body = createFakeElement('body');
    body.appendChild(container);

    const byId = Object.create(null);
    byId['panel-container'] = container;
    byId['panel-content'] = content;

    const document = {
        body: body,
        createElement(tag) {
            const el = createFakeElement(tag);
            const origAppend = container.appendChild.bind(container);
            return el;
        },
        getElementById(id) {
            if (byId[id]) return byId[id];
            for (let i = 0; i < container.children.length; i++) {
                if (container.children[i].id === id) return container.children[i];
            }
            return null;
        }
    };

    const windowObj = {
        BootstrapAudio: {
            cue(name) { audioCues.push(name); }
        }
    };

    const sandbox = {
        window: windowObj,
        document: document,
        Panels: {
            isOpen() { return panelOpen; }
        },
        Bridge: {
            send(msg) { bridgeSent.push(msg); return true; }
        },
        setTimeout(fn, ms) {
            const id = nextTimerId++;
            timers.set(id, { fn, ms });
            return id;
        },
        clearTimeout(id) {
            timers.delete(id);
        }
    };
    vm.createContext(sandbox);
    vm.runInContext(TOAST_SOURCE + '\nthis.__Toast = Toast;', sandbox);

    return {
        Toast: sandbox.__Toast,
        container,
        scaleShell,
        bridgeSent,
        audioCues,
        timers,
        setPanelOpen(v) {
            panelOpen = !!v;
            container.hidden = !panelOpen;
        },
        runAllTimers() {
            const snapshot = Array.from(timers.entries());
            snapshot.forEach(([id, entry]) => {
                if (timers.has(id)) {
                    timers.delete(id);
                    entry.fn();
                }
            });
        }
    };
}

check('panel-open error renders unified top banner, plays rejected cue, and does not spam notch', function() {
    const h = createHarness({ panelOpen: true });
    h.Toast.add('<FONT COLOR="#FF5555">背包已满（50/50）<BR>请先整理背包</FONT>', 'error');
    const state = h.Toast.debugState();
    assert.strictEqual(state.visible, true);
    assert.strictEqual(state.severity, 'error');
    assert.strictEqual(state.text, '背包已满（50/50） 请先整理背包');
    assert.strictEqual(state.last.shownInPanel, true);
    assert.strictEqual(state.last.sentToHost, false);
    assert.deepStrictEqual(h.bridgeSent, []);
    assert.deepStrictEqual(h.audioCues, ['rejected']);

    const banner = h.container.children.find(c => c.id === 'panel-feedback-banner');
    assert.ok(banner, 'banner mounted inside #panel-container');
    assert.strictEqual(banner.getAttribute('role'), 'alert');
    assert.strictEqual(banner.getAttribute('aria-live'), 'assertive');
    assert.strictEqual(banner.querySelector('.panel-feedback-icon').textContent, '✕');
    assert.strictEqual(banner.style.getPropertyValue('--panel-feedback-left'), '760px');
    assert.strictEqual(banner.style.getPropertyValue('--panel-feedback-top'), '125px');
    assert.strictEqual(banner.style.getPropertyValue('--panel-feedback-scale'), '1.2500');
});

check('single-line upsert updates existing banner node without duplicating DOM', function() {
    const h = createHarness({ panelOpen: true });
    h.Toast.add('第一条警告', 'warning');
    h.Toast.add('第二条成功', 'success');
    const banners = h.container.children.filter(c => c.id === 'panel-feedback-banner');
    assert.strictEqual(banners.length, 1);
    assert.strictEqual(h.Toast.debugState().severity, 'success');
    assert.strictEqual(h.Toast.debugState().text, '第二条成功');
    assert.strictEqual(banners[0].getAttribute('role'), 'status');
    assert.strictEqual(banners[0].getAttribute('aria-live'), 'polite');
    assert.strictEqual(banners[0].querySelector('.panel-feedback-icon').textContent, '✓');
    assert.deepStrictEqual(h.audioCues, ['illegal', 'success']);
});

check('silent option suppresses audio cue while keeping visual severity and banner', function() {
    const h = createHarness({ panelOpen: true });
    h.Toast.add('已有操作在进行中，请稍候', 'warning', { silent: true });
    const state = h.Toast.debugState();
    assert.strictEqual(state.visible, true);
    assert.strictEqual(state.severity, 'warning');
    assert.deepStrictEqual(h.audioCues, []);
    assert.deepStrictEqual(h.bridgeSent, []);
});

check('info and omitted severity stay visually calm and audio-silent', function() {
    const h = createHarness({ panelOpen: true });
    h.Toast.add('普通提示信息');
    assert.strictEqual(h.Toast.debugState().severity, 'info');
    assert.deepStrictEqual(h.audioCues, []);
    h.Toast.add('显式信息', 'info');
    assert.strictEqual(h.Toast.debugState().severity, 'info');
    assert.deepStrictEqual(h.audioCues, []);
});

check('dismissPanel hides banner and clears pending timers', function() {
    const h = createHarness({ panelOpen: true });
    h.Toast.add('阻断提示', 'error');
    assert.strictEqual(h.Toast.debugState().visible, true);
    assert.ok(h.timers.size > 0);
    h.Toast.dismissPanel();
    assert.strictEqual(h.Toast.debugState().visible, false);
    assert.strictEqual(h.timers.size, 0);
});

check('banner auto-dismisses when TTL timer fires', function() {
    const h = createHarness({ panelOpen: true });
    h.Toast.add('短暂成功', 'success', { durationMs: 1200 });
    assert.strictEqual(h.Toast.debugState().visible, true);
    h.runAllTimers();
    assert.strictEqual(h.Toast.debugState().visible, false);
});

check('persistAfterClose routes directly to Host panel-toast even while panel is open', function() {
    const h = createHarness({ panelOpen: true });
    h.Toast.add('已整容并扣费', 'success', { persistAfterClose: true, silent: true });
    const state = h.Toast.debugState();
    assert.strictEqual(state.last.shownInPanel, false);
    assert.strictEqual(state.last.sentToHost, true);
    assert.deepStrictEqual(h.audioCues, []);
    assert.strictEqual(h.bridgeSent.length, 1);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(h.bridgeSent[0])), {
        type: 'panel-toast',
        html: '已整容并扣费',
        severity: 'success'
    });
});

check('panel-closed state routes to Host panel-toast', function() {
    const h = createHarness({ panelOpen: false });
    h.Toast.add('关闭后的外部回执', 'info');
    const state = h.Toast.debugState();
    assert.strictEqual(state.visible, false);
    assert.strictEqual(state.last.shownInPanel, false);
    assert.strictEqual(state.last.sentToHost, true);
    assert.strictEqual(h.bridgeSent.length, 1);
    assert.strictEqual(h.bridgeSent[0].type, 'panel-toast');
    assert.strictEqual(h.bridgeSent[0].html, '关闭后的外部回执');
});

check('HTML tag stripping prevents raw markup from leaking into banner text', function() {
    const h = createHarness({ panelOpen: true });
    h.Toast.add('<img src=x onerror=alert(1)>无法卸下<br/><b>请先清理</b>', 'error');
    assert.strictEqual(h.Toast.debugState().text, '无法卸下 请先清理');
});

process.stdout.write('Panel toast: ' + passed + '/' + passed + ' passed\n');
