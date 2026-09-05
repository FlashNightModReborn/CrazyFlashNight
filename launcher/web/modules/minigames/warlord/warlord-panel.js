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
    var stageTerminalAttempt = null;
    var OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;
    var STAGE_BINDING_KEYS = ['callId', 'revision', 'runId', 'scenarioRef', 'schema', 'subStageId'];
    var STAGE_TERMINAL_KEYS = ['callId', 'reasonCode', 'revision', 'runId', 'scenarioRef', 'schema', 'subStageId', 'terminal'];
    var RESUME_APPLIED_KEYS = ['inputDigest', 'requestId', 'schema', 'sessionId', 'stageOuterBinding', 'status'];
    var PLAYER_AVATAR_PORTRAIT_KEYS = ['equipment', 'face', 'gender', 'hair', 'schema'];
    var PLAYER_AVATAR_EQUIPMENT_KEYS = ['body', 'foot', 'hand', 'head', 'leg', 'neck'];

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
            + '<div class="warlord-boot"><b>军阀战术演习</b><span>正在准备战区沙盘…</span></div>'
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
            scenarioRef: typeof input.scenarioRef === 'string' ? input.scenarioRef : '',
            panelInstanceId: typeof input.panelInstanceId === 'string' ? input.panelInstanceId : '',
            productionWrites: false,
            forceWebglFailure: input.forceWebglFailure === true,
            mapTheme: input.mapTheme === 'tundra' ? 'tundra' : 'desert',
            battleAuthority: productAuthority ? 'as2' : 'fixture',
            as2BattleSession: input.as2BattleSession === true,
            aiSeenTransitions: Array.isArray(input.aiSeenTransitions)
                ? input.aiSeenTransitions.slice(0, 256) : [],
            resume: input.resume && typeof input.resume === 'object' ? input.resume : null,
            stageOuterBinding: input.stageOuterBinding && typeof input.stageOuterBinding === 'object'
                ? input.stageOuterBinding : null,
            playerAvatarPortrait: productAuthority
                ? normalizePlayerAvatarPortrait(input.playerAvatarPortrait) : null,
            bridgeSend: sendBattleEnvelope
        };
    }

    function portraitText(value) {
        if (typeof value !== 'string' || value.length > 128 || /[\x00-\x1f\\"]/u.test(value)) return null;
        return value;
    }

    function normalizePlayerAvatarPortrait(value) {
        if (!hasExactKeys(value, PLAYER_AVATAR_PORTRAIT_KEYS)
                || value.schema !== 'warlord.player-avatar-portrait.v1'
                || (value.gender !== '男' && value.gender !== '女')) return null;
        var face = portraitText(value.face);
        var hair = portraitText(value.hair);
        if (face === null || hair === null
                || !hasExactKeys(value.equipment, PLAYER_AVATAR_EQUIPMENT_KEYS)) return null;
        var equipment = {};
        for (var i = 0; i < PLAYER_AVATAR_EQUIPMENT_KEYS.length; i += 1) {
            var key = PLAYER_AVATAR_EQUIPMENT_KEYS[i];
            var item = portraitText(value.equipment[key]);
            if (item === null) return null;
            equipment[key] = item;
        }
        return {
            schema: 'warlord.player-avatar-portrait.v1', gender: value.gender,
            face: face, hair: hair, equipment: equipment
        };
    }

    function hasExactKeys(value, expected) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var keys = Object.keys(value).sort();
        if (keys.length !== expected.length) return false;
        for (var i = 0; i < expected.length; i += 1) {
            if (keys[i] !== expected[i]) return false;
        }
        return true;
    }

    function isOpaqueId(value) {
        return typeof value === 'string' && OPAQUE_ID_PATTERN.test(value);
    }

    function normalizedStageBinding(value) {
        if (!hasExactKeys(value, STAGE_BINDING_KEYS)
                || value.schema !== 'warlord.stage-outer-binding.v1'
                || !isOpaqueId(value.runId) || !isOpaqueId(value.subStageId)
                || !isOpaqueId(value.scenarioRef) || !isOpaqueId(value.callId)
                || !Number.isSafeInteger(value.revision) || value.revision < 0) return null;
        return value;
    }

    function isStageMode(value) {
        return !!value && value.source === 'game_stage' && value.mode === 'stage-v1';
    }

    function sameStageBinding(left, right) {
        return !!left && !!right && left.runId === right.runId
            && left.subStageId === right.subStageId
            && left.scenarioRef === right.scenarioRef
            && left.callId === right.callId
            && left.revision === right.revision;
    }

    function validStageTerminal(message, binding) {
        if (!hasExactKeys(message, STAGE_TERMINAL_KEYS)
                || message.schema !== 'warlord.stage-outer-terminal.v1'
                || !isOpaqueId(message.reasonCode)
                || ['CompleteSubStage', 'FailStage', 'Suspended', 'Unknown'].indexOf(message.terminal) < 0
                || !Number.isSafeInteger(message.revision) || message.revision < 0) return false;
        return message.runId === binding.runId
            && message.subStageId === binding.subStageId
            && message.scenarioRef === binding.scenarioRef
            && message.callId === binding.callId
            && message.revision === binding.revision;
    }

    function sameStageTerminal(left, right) {
        if (!left || !right) return false;
        for (var i = 0; i < STAGE_TERMINAL_KEYS.length; i += 1) {
            var key = STAGE_TERMINAL_KEYS[i];
            if (left[key] !== right[key]) return false;
        }
        return true;
    }

    function sendStageTerminal(localGeneration, message) {
        if (!panelOpen || generation !== localGeneration || !isStageMode(initData)) return false;
        var binding = normalizedStageBinding(initData.stageOuterBinding);
        var panelInstanceId = initData && initData.panelInstanceId;
        if (!binding || !validStageTerminal(message, binding) || !isOpaqueId(panelInstanceId)
                || typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') return false;
        if (stageTerminalAttempt) {
            return sameStageTerminal(stageTerminalAttempt.envelope, message)
                ? stageTerminalAttempt.delivered : false;
        }

        var attempt = {
            envelope: Object.assign({}, message),
            delivered: false
        };
        stageTerminalAttempt = attempt;
        var delivered = false;
        try {
            delivered = Bridge.send({
                type: 'panel',
                panel: 'warlord',
                cmd: 'minigame_session',
                panelInstanceId: panelInstanceId,
                payload: {
                    game: 'warlord',
                    kind: 'stage_terminal',
                    data: message
                }
            }) === true;
        } catch (ignore) {
            delivered = false;
        }
        if (!panelOpen || generation !== localGeneration || stageTerminalAttempt !== attempt) return false;
        attempt.delivered = delivered;
        return delivered;
    }

    function installStageTerminalSender(value, localGeneration) {
        value.stageTerminalSend = function (message) {
            return sendStageTerminal(localGeneration, message);
        };
    }

    function validResumeApplied(message, binding) {
        return hasExactKeys(message, RESUME_APPLIED_KEYS)
            && message.schema === 'warlord.as2-resume-apply.v1'
            && (message.status === 'applied' || message.status === 'frozen')
            && typeof message.inputDigest === 'string'
            && /^sha256:[0-9a-f]{64}$/i.test(message.inputDigest)
            && isOpaqueId(message.sessionId)
            && isOpaqueId(message.requestId)
            && sameStageBinding(
                normalizedStageBinding(message.stageOuterBinding),
                binding);
    }

    function sendResumeApplied(localGeneration, message) {
        if (!panelOpen || generation !== localGeneration || !isStageMode(initData)) return false;
        var binding = normalizedStageBinding(initData.stageOuterBinding);
        var panelInstanceId = initData && initData.panelInstanceId;
        if (!binding || !validResumeApplied(message, binding) || !isOpaqueId(panelInstanceId)
                || typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') return false;
        var delivered = false;
        try {
            delivered = Bridge.send({
                type: 'panel',
                panel: 'warlord',
                cmd: 'minigame_session',
                panelInstanceId: panelInstanceId,
                payload: {
                    game: 'warlord',
                    kind: 'battle_resume_applied',
                    data: message
                }
            }) === true;
        } catch (ignore) {
            delivered = false;
        }
        return panelOpen && generation === localGeneration && delivered;
    }

    function installResumeAppliedSender(value, localGeneration) {
        value.resumeAppliedSend = function (message) {
            return sendResumeApplied(localGeneration, message);
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
            if (typeof console !== 'undefined' && console.error) console.error('Warlord runtime load failed', error);
            scaleShell.innerHTML = '<div class="warlord-boot warlord-boot-error"><b>沙盘装载失败</b><span>'
                + '暂时无法打开战区沙盘，请稍后重试。'
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
        stageTerminalAttempt = null;
        initData = sanitizeInit(value);
        generation += 1;
        var localGeneration = generation;
        installStageTerminalSender(initData, localGeneration);
        installResumeAppliedSender(initData, localGeneration);
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
        var previousBinding = normalizedStageBinding(initData && initData.stageOuterBinding);
        var nextInitData = sanitizeInit(value);
        var nextBinding = normalizedStageBinding(nextInitData.stageOuterBinding);
        if (!sameStageBinding(previousBinding, nextBinding)) stageTerminalAttempt = null;
        initData = nextInitData;
        generation += 1;
        installStageTerminalSender(initData, generation);
        installResumeAppliedSender(initData, generation);
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
        if (isStageMode(initData)) {
            if (!session || typeof session.prepareStageClose !== 'function') {
                showCloseStatus('关卡沙盘尚未准备完成，无法安全提交暂停状态；页面将保持打开。');
                return false;
            }
            var stageClose = session.prepareStageClose();
            if (stageClose !== 'ready') {
                showCloseStatus('关卡暂停状态尚未送达；页面将保持打开，不会直接返回基地。');
                return false;
            }
        }
        if (closePending) return true;
        var panelInstanceId = initData && initData.panelInstanceId;
        if (!panelInstanceId || typeof Bridge === 'undefined' || !Bridge.send) {
            showCloseStatus('当前无法关闭演习；对局仍保持打开，请稍后再试。');
            return false;
        }
        var localGeneration = generation;
        closePending = true;
        showCloseStatus('正在关闭当前演习，请稍候…');
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
                showCloseStatus('当前无法关闭演习；对局仍保持打开，请稍后再试。');
            }
            return false;
        }
        // Host acknowledgement is asynchronous.  Release the Three/WebGL owner
        // before Host can hide the overlay; if the exact close is not confirmed,
        // the timeout path rebuilds one presentation scene from unchanged state.
        if (session && typeof session.quiesceForPanelClose === 'function') {
            session.quiesceForPanelClose();
        }
        if (panelOpen && closePending && generation === localGeneration && initData
                && initData.panelInstanceId === panelInstanceId) {
            closeTimer = setTimeout(function () {
                closeTimer = null;
                if (!panelOpen || !closePending || generation !== localGeneration
                        || !initData || initData.panelInstanceId !== panelInstanceId) return;
                closePending = false;
                if (session && typeof session.resumeAfterPanelCloseTimeout === 'function') {
                    session.resumeAfterPanelCloseTimeout();
                }
                showCloseStatus('关闭请求暂时没有响应，可以再次尝试。');
            }, closeAckTimeoutMs());
        }
        return true;
    }

    function onClose() {
        clearCloseTimer();
        generation += 1;
        panelOpen = false;
        closePending = false;
        stageTerminalAttempt = null;
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

    // Read-only, bounded Host diagnostic. It deliberately reads no player text,
    // image pixels or WebGL state and does not change the strategic/app lifecycle.
    function readPresentation() {
        function describe(element) {
            if (!element) return null;
            var rect = element.getBoundingClientRect();
            var css = window.getComputedStyle(element);
            var blocked = false;
            for (var node = element; node; node = node.parentElement) {
                var style = window.getComputedStyle(node);
                if (node.hidden || style.display === 'none'
                        || style.visibility === 'hidden' || Number(style.opacity) === 0) {
                    blocked = true;
                    break;
                }
            }
            return {
                connected: element.isConnected,
                rect: [rect.x, rect.y, rect.width, rect.height].map(function (v) {
                    return Math.round(v * 100) / 100;
                }),
                display: css.display,
                visibility: css.visibility,
                opacity: css.opacity,
                transform: css.transform,
                blockedByStyle: blocked
            };
        }
        var app = document.querySelector('.warlord-app');
        var battle = document.querySelector('.warlord-battle-layer');
        var button = document.querySelector('.warlord-battle-controls [data-action="battle-close"]');
        var hit = null;
        if (button) {
            var rect = button.getBoundingClientRect();
            hit = document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2);
        }
        return {
            panelOpen: panelOpen,
            documentVisibility: document.visibilityState,
            viewport: [window.innerWidth, window.innerHeight, window.devicePixelRatio],
            container: describe(document.querySelector('#panel-container')),
            shell: describe(document.querySelector('.warlord-scale-shell')),
            app: describe(app),
            battle: describe(battle),
            closeButton: describe(button),
            closeButtonHit: !!button && (hit === button || button.contains(hit)),
            sceneLifecycle: app && app.dataset.sceneLifecycle,
            authorityState: app && app.dataset.authorityState,
            canvasCount: app ? app.querySelectorAll('canvas').length : 0
        };
    }

    window.WarlordPanelDiagnostics = { read: readPresentation };

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
