/* global Panels, PanelScale, Bridge, MinigameHostBridge */
(function () {
    'use strict';

    var DESIGN_WIDTH = 1024;
    var DESIGN_HEIGHT = 576;
    var scriptUrl = document.currentScript && document.currentScript.src
        ? document.currentScript.src : window.location.href;
    var runtimeUrl = new URL('./runtime/main.js?v=warlord-sandtable-phase-c.as2', scriptUrl).href;
    var modulePromise = null;
    var panelRoot = null;
    var scaleShell = null;
    var scaleHandle = null;
    var session = null;
    var initData = null;
    var generation = 0;
    var panelOpen = false;
    var closePending = false;
    var closeTimer = null;

    if (typeof Bridge !== 'undefined' && Bridge && typeof Bridge.on === 'function') {
        Bridge.on('panel_resp', function (data) {
            if (!data || data.panel !== 'warlord' || data.cmd !== 'battle_start') return;
            if (session && typeof session.handleHostResponse === 'function') {
                session.handleHostResponse(data);
            }
        });
    }

    function create() {
        var root = document.createElement('section');
        root.className = 'warlord-panel';
        root.setAttribute('aria-label', '军阀战术演习');
        root.innerHTML = '<div class="warlord-scale-shell panel-scale-shell">'
            + '<div class="warlord-boot"><b>军阀战术演习</b><span>正在装载确定性核心与三维沙盘…</span></div>'
            + '</div>';
        return root;
    }

    function loadRuntime() {
        if (!modulePromise) {
            modulePromise = import(runtimeUrl).catch(function (error) {
                modulePromise = null;
                throw error;
            });
        }
        return modulePromise;
    }

    function sanitizeInit(value) {
        var input = value && typeof value === 'object' ? value : {};
        var difficulty = input.difficulty;
        var preset = input.preset;
        var source = typeof input.source === 'string' ? input.source : 'dev-harness';
        var productAuthority = input.battleAuthority === 'as2'
            || source === 'runtime' || source === 'as2_battle_resume';
        return {
            mode: typeof input.mode === 'string' ? input.mode : 'phase-b',
            source: source,
            seed: typeof input.seed === 'string' ? input.seed : 'warlord-demo-seed-001',
            preset: preset === 'all-units' ? 'all-units' : 'standard',
            difficulty: difficulty === 'easy' || difficulty === 'hard' || difficulty === 'extreme'
                ? difficulty : 'normal',
            panelInstanceId: typeof input.panelInstanceId === 'string' ? input.panelInstanceId : '',
            productionWrites: false,
            forceWebglFailure: input.forceWebglFailure === true,
            mapTheme: input.mapTheme === 'tundra' ? 'tundra' : 'desert',
            battleAuthority: productAuthority ? 'as2' : 'fixture',
            as2BattleSession: input.as2BattleSession === true,
            aiSeenTransitions: Array.isArray(input.aiSeenTransitions)
                ? input.aiSeenTransitions.slice(0, 256) : [],
            resume: input.resume && typeof input.resume === 'object' ? input.resume : null,
            bridgeSend: sendBattleEnvelope
        };
    }

    function sendBattleEnvelope(message) {
        if (!panelOpen || !initData || !initData.panelInstanceId
                || typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') return false;
        if (!message || message.type !== 'panel' || message.panel !== 'warlord'
                || message.cmd !== 'battle_start'
                || message.panelInstanceId !== initData.panelInstanceId) return false;
        try { return Bridge.send(message) === true; } catch (ignore) { return false; }
    }

    function mountAsync(localGeneration) {
        loadRuntime().then(function (runtime) {
            if (!panelOpen || generation !== localGeneration || !scaleShell) return;
            if (!runtime || typeof runtime.mount !== 'function') {
                throw new Error('ESM runtime did not export mount()');
            }
            session = runtime.mount(scaleShell, initData);
            if (!panelOpen || generation !== localGeneration) {
                if (session && session.dispose) session.dispose();
                session = null;
                return;
            }
            scaleShell.setAttribute('data-runtime-version', runtime.WARLORD_RUNTIME_VERSION || 'unknown');
            notifyHost('opened', {
                phase: 'phase-c.as2',
                productionWrites: false,
                battleAuthority: initData && initData.battleAuthority || 'fixture',
                runtimeVersion: runtime.WARLORD_RUNTIME_VERSION || 'unknown'
            });
        }).catch(function (error) {
            if (!panelOpen || generation !== localGeneration || !scaleShell) return;
            scaleShell.innerHTML = '<div class="warlord-boot warlord-boot-error"><b>沙盘装载失败</b><span>'
                + escapeHtml(error && error.message ? error.message : String(error))
                + '</span><button type="button" data-warlord-retry>重试</button></div>';
            var retry = scaleShell.querySelector('[data-warlord-retry]');
            if (retry) retry.addEventListener('click', function () {
                if (!panelOpen || generation !== localGeneration || !scaleShell) return;
                scaleShell.innerHTML = '<div class="warlord-boot"><b>军阀战术演习</b><span>重新装载沙盘…</span></div>';
                mountAsync(localGeneration);
            }, { once: true });
        });
    }

    function onOpen(el, value) {
        panelRoot = el;
        scaleShell = el.querySelector('.warlord-scale-shell');
        if (!scaleShell) return false;
        panelOpen = true;
        closePending = false;
        clearCloseTimer();
        initData = sanitizeInit(value);
        generation += 1;
        var localGeneration = generation;
        if (scaleHandle) scaleHandle.detach();
        scaleHandle = typeof PanelScale !== 'undefined' && PanelScale.attach
            ? PanelScale.attach(scaleShell, DESIGN_WIDTH, DESIGN_HEIGHT) : null;
        scaleShell.removeEventListener('warlord:request-close', onRuntimeCloseRequest);
        scaleShell.addEventListener('warlord:request-close', onRuntimeCloseRequest);
        mountAsync(localGeneration);
        return true;
    }

    function onRebind(el, value) {
        panelRoot = el;
        scaleShell = el.querySelector('.warlord-scale-shell');
        if (!scaleShell) return false;
        clearCloseTimer();
        closePending = false;
        initData = sanitizeInit(value);
        generation += 1;
        if (session && session.rebind) {
            session.rebind(initData);
            if (scaleHandle && scaleHandle.update) scaleHandle.update();
            return true;
        }
        mountAsync(generation);
        return true;
    }

    function onRuntimeCloseRequest(event) {
        if (event) event.stopPropagation();
        onRequestClose('button');
    }

    function onRequestClose(reason) {
        if (reason === 'escape' && session && session.requestClose
                && session.requestClose('escape')) return true;
        if (closePending) return true;
        var panelInstanceId = initData && initData.panelInstanceId;
        if (!panelInstanceId || typeof Bridge === 'undefined' || !Bridge.send) {
            showCloseStatus('Launcher 连接不可用，军阀演习保持打开。');
            return false;
        }
        var localGeneration = generation;
        closePending = true;
        showCloseStatus('正在等待 Launcher 确认关闭当前演习实例…');
        var accepted = false;
        try {
            accepted = Bridge.send({
                type: 'panel',
                cmd: 'close',
                panel: 'warlord',
                panelInstanceId: panelInstanceId
            }) === true;
        } catch (ignore) {
            accepted = false;
        }
        if (!accepted) {
            if (panelOpen && generation === localGeneration && initData
                    && initData.panelInstanceId === panelInstanceId) {
                closePending = false;
                showCloseStatus('Launcher 连接不可用，军阀演习保持打开。');
            }
            return false;
        }
        if (panelOpen && closePending && generation === localGeneration && initData
                && initData.panelInstanceId === panelInstanceId) {
            closeTimer = setTimeout(function () {
                closeTimer = null;
                if (!panelOpen || !closePending || generation !== localGeneration
                        || !initData || initData.panelInstanceId !== panelInstanceId) return;
                closePending = false;
                showCloseStatus('Launcher 尚未确认关闭，可再次尝试。');
            }, closeAckTimeoutMs());
        }
        return true;
    }

    function onClose() {
        clearCloseTimer();
        generation += 1;
        panelOpen = false;
        closePending = false;
        if (session && session.dispose) session.dispose();
        session = null;
        if (scaleHandle) scaleHandle.detach();
        scaleHandle = null;
        initData = null;
        if (scaleShell) {
            scaleShell.removeEventListener('warlord:request-close', onRuntimeCloseRequest);
        }
        scaleShell = null;
        panelRoot = null;
        notifyHost('closed', { phase: 'phase-c.as2', productionWrites: false });
    }

    function notifyHost(kind, data) {
        if (typeof MinigameHostBridge !== 'undefined' && MinigameHostBridge.sendSession) {
            return MinigameHostBridge.sendSession('warlord', kind, data || {});
        }
        return false;
    }

    function showCloseStatus(message) {
        var live = scaleShell && scaleShell.querySelector('[data-region="live"]');
        if (live) live.textContent = message;
    }

    function closeAckTimeoutMs() {
        var configured = Number(window.__CF7_PANEL_CLOSE_ACK_TIMEOUT_MS__);
        return isFinite(configured) && configured >= 50
            ? Math.min(configured, 3000) : 3000;
    }

    function clearCloseTimer() {
        if (closeTimer !== null) clearTimeout(closeTimer);
        closeTimer = null;
    }

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
    }

    Panels.register('warlord', {
        create: create,
        onOpen: onOpen,
        onRebind: onRebind,
        onRequestClose: onRequestClose,
        onClose: onClose
    });
})();
