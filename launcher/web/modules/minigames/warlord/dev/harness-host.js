(function () {
    'use strict';

    var specs = {};
    var active = null;
    var activeElement = null;
    var bridgeMessages = [];
    var bridgeHandlers = {};
    var battleResponseMode = 'none';

    function emitBridge(eventName, data) {
        (bridgeHandlers[eventName] || []).slice().forEach(function (handler) {
            handler(data);
        });
    }

    window.Bridge = {
        on: function (eventName, handler) {
            if (typeof handler !== 'function') return function () {};
            if (!bridgeHandlers[eventName]) bridgeHandlers[eventName] = [];
            bridgeHandlers[eventName].push(handler);
            return function () {
                var handlers = bridgeHandlers[eventName] || [];
                var index = handlers.indexOf(handler);
                if (index >= 0) handlers.splice(index, 1);
            };
        },
        send: function (message) {
            bridgeMessages.push(message && typeof structuredClone === 'function'
                ? structuredClone(message) : JSON.parse(JSON.stringify(message || null)));
            if (battleResponseMode === 'reject' && message && message.panel === 'warlord'
                    && message.cmd === 'battle_start' && typeof message.callId === 'string') {
                setTimeout(function () {
                    emitBridge('panel_resp', {
                        type: 'panel_resp',
                        panel: 'warlord',
                        cmd: 'battle_start',
                        callId: message.callId,
                        success: false,
                        ok: false
                    });
                }, 0);
            }
            return true;
        }
    };

    window.Panels = {
        register: function (id, spec) { specs[id] = spec; },
        open: function (id, initData) {
            var spec = specs[id];
            if (!spec) throw new Error('unknown harness panel: ' + id);
            if (active && active !== id) window.Panels.close();
            if (!spec._el) {
                spec._el = spec.create(document.getElementById('harness-stage'));
                document.getElementById('harness-stage').appendChild(spec._el);
            }
            spec._el.style.display = '';
            active = id;
            activeElement = spec._el;
            return spec.onOpen ? spec.onOpen(spec._el, initData || {}) !== false : true;
        },
        rebind: function (id, initData) {
            var spec = specs[id];
            if (!spec || active !== id) return false;
            return spec.onRebind ? spec.onRebind(spec._el, initData || {}) !== false : true;
        },
        close: function () {
            if (!active) return;
            var spec = specs[active];
            if (spec && spec.onClose) spec.onClose();
            if (activeElement) activeElement.style.display = 'none';
            active = null;
            activeElement = null;
        },
        requestClose: function () {
            var spec = active && specs[active];
            if (spec && spec.onRequestClose) return spec.onRequestClose('harness');
            window.Panels.close();
            return true;
        }
    };

    function queryInit() {
        var params = new URLSearchParams(location.search);
        return {
            mode: 'phase-a',
            source: 'dev-harness',
            seed: params.get('seed') || 'warlord-demo-seed-001',
            preset: params.get('preset') === 'all-units' ? 'all-units' : 'standard',
            difficulty: params.get('difficulty') || 'normal',
            scenarioRef: params.get('scenario') || 'warlord_tutorial_v1',
            mapTheme: params.get('theme') === 'tundra' ? 'tundra' : 'desert',
            forceWebglFailure: params.get('webgl') === '0',
            battleAuthority: 'fixture',
            productionWrites: false
        };
    }

    window.__warlordHarness = {
        open: function (overrides) { return window.Panels.open('warlord', Object.assign(queryInit(), overrides || {})); },
        close: function () { return window.Panels.close(); },
        rebind: function (overrides) { return window.Panels.rebind('warlord', Object.assign(queryInit(), overrides || {})); },
        requestClose: function () { return window.Panels.requestClose(); },
        bridgeMessages: function () { return bridgeMessages.slice(); },
        clearBridgeMessages: function () { bridgeMessages.length = 0; },
        setBattleResponseMode: function (mode) {
            if (mode !== 'none' && mode !== 'reject') throw new Error('unknown battle response mode: ' + mode);
            battleResponseMode = mode;
        },
        activeElement: function () { return activeElement; },
        spec: function () { return specs.warlord; }
    };

    window.addEventListener('DOMContentLoaded', function () {
        window.__warlordHarness.open();
    });
})();
