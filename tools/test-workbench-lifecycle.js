'use strict';

const assert = require('assert');
const Lifecycle = require('../launcher/web/modules/workbench-lifecycle.js');

let passed = 0;
function test(name, run) {
    run();
    passed += 1;
    process.stdout.write('ok - ' + name + '\n');
}

test('DisposableStack disposes in reverse order and only once', () => {
    const calls = [];
    const stack = new Lifecycle.DisposableStack();
    stack.defer(() => calls.push('first'));
    stack.defer(() => calls.push('second'));
    assert.strictEqual(stack.dispose(), true);
    assert.strictEqual(stack.dispose(), false);
    assert.deepStrictEqual(calls, ['second', 'first']);
});

test('DisposableStack removes event listeners deterministically', () => {
    const calls = [];
    const target = {
        addEventListener(type, handler, options) { calls.push(['add', type, handler, options]); },
        removeEventListener(type, handler, options) { calls.push(['remove', type, handler, options]); }
    };
    const handler = () => {};
    const stack = new Lifecycle.DisposableStack();
    stack.listen(target, 'focusin', handler, true);
    stack.dispose();
    assert.deepStrictEqual(calls, [
        ['add', 'focusin', handler, true],
        ['remove', 'focusin', handler, true]
    ]);
});

test('PanelLifecycle owns one active session and tears it down on unmount', () => {
    const calls = [];
    const lifecycle = new Lifecycle.PanelLifecycle({
        mount(host) { calls.push('mount:' + host.id); },
        activate(context, session) {
            calls.push('activate:' + context.id);
            session.defer(() => calls.push('session-dispose:' + context.id));
        },
        deactivate(reason) { calls.push('deactivate:' + reason); },
        unmount(host, reason) { calls.push('unmount:' + host.id + ':' + reason); },
        destroy(reason) { calls.push('destroy:' + reason); }
    });
    assert.strictEqual(lifecycle.mount({id: 'host'}), true);
    assert.strictEqual(lifecycle.activate({id: 'one'}), true);
    assert.strictEqual(lifecycle.activate({id: 'two'}), true);
    assert.strictEqual(lifecycle.unmount('close'), true);
    assert.strictEqual(lifecycle.destroy('final'), true);
    assert.strictEqual(lifecycle.destroy('again'), false);
    assert.deepStrictEqual(calls, [
        'mount:host',
        'activate:one',
        'deactivate:reactivate',
        'session-dispose:one',
        'activate:two',
        'deactivate:close',
        'session-dispose:two',
        'unmount:host:close',
        'destroy:final'
    ]);
    assert.strictEqual(lifecycle.state(), 'destroyed');
});

test('activation failure disposes partial session and remains mounted', () => {
    let disposed = false;
    const lifecycle = new Lifecycle.PanelLifecycle({
        activate(context, session) {
            session.defer(() => { disposed = true; });
            throw new Error('boom');
        }
    });
    lifecycle.mount({});
    assert.throws(() => lifecycle.activate({}), /boom/);
    assert.strictEqual(disposed, true);
    assert.strictEqual(lifecycle.state(), 'mounted');
});

test('mount failure rolls back partial resources, host, and state', () => {
    let disposed = 0;
    const lifecycle = new Lifecycle.PanelLifecycle({
        mount(host, mountSession) {
            mountSession.defer(() => { disposed += 1; });
            throw new Error('mount failed');
        }
    });
    assert.throws(() => lifecycle.mount({id:'broken'}), /mount failed/);
    assert.strictEqual(disposed, 1);
    assert.strictEqual(lifecycle.host(), null);
    assert.strictEqual(lifecycle.state(), 'unmounted');
    assert.throws(() => lifecycle.mount({id:'broken-again'}), /mount failed/);
    assert.strictEqual(disposed, 2);
});

test('remount and unmount dispose each mount session exactly once', () => {
    const calls = [];
    const lifecycle = new Lifecycle.PanelLifecycle({
        mount(host, mountSession) {
            calls.push('mount:' + host.id);
            mountSession.defer(() => calls.push('mount-dispose:' + host.id));
        },
        unmount(host, reason) { calls.push('unmount:' + host.id + ':' + reason); }
    });
    lifecycle.mount({id:'one'});
    lifecycle.mount({id:'two'});
    lifecycle.unmount('close');
    lifecycle.destroy('final');
    assert.deepStrictEqual(calls, [
        'mount:one',
        'unmount:one:remount',
        'mount-dispose:one',
        'mount:two',
        'unmount:two:close',
        'mount-dispose:two'
    ]);
});

test('unmount completes teardown even when deactivate fails', () => {
    const calls = [];
    const lifecycle = new Lifecycle.PanelLifecycle({
        activate(context, session) { session.defer(() => calls.push('session')); },
        deactivate() { calls.push('deactivate'); throw new Error('deactivate failed'); },
        unmount(host) { calls.push('unmount:' + host.id); }
    });
    lifecycle.mount({id:'host'});
    lifecycle.activate({});
    assert.throws(() => lifecycle.unmount('close'), /deactivate failed/);
    assert.deepStrictEqual(calls, ['deactivate', 'session', 'unmount:host']);
    assert.strictEqual(lifecycle.host(), null);
    assert.strictEqual(lifecycle.state(), 'unmounted');
});

process.stdout.write('Workbench lifecycle ' + passed + '/' + passed + ' passed\n');
