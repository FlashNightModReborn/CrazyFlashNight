/**
 * workbench-atlas arena 场景族（P4 接入）——真实 feature 场景：加载生产闭包
 * （与 panels-lazy-registry arena 注册项同序的 24 脚本 + dev fixture），驱动真实
 * arena panel 的 catalog-decision 壳 + skin 关键状态：
 *   default（未选中·决策空态）/ selected（选中卡·右栏 preview·CommitBar ready）/
 *   blocked（金钱不足·CommitBar blocked）× reduced-motion（runner 媒体仿真轴）× 三视口。
 * 由 workbench-atlas.html 在 scene=arena 时调用；复用页面级 __qaDone/__qaResult 合同，
 * 不另造报告体系。mock 仅覆写 chrome.webview 传输层，snapshot/preview 应答形状与
 * arena/dev/harness.html 同款（preview 对手为占位 fixture，不触发 enter）。
 */
(function() {
    'use strict';

    var MODULE_BASE = '/launcher/web/modules/';
    // 与 panels-lazy-registry arena 注册项同序（共享层中 atlas 页已静态加载
    // panel-scale/lifecycle/focus/primitives/profile/workbench.js，此处只补差集）。
    var SCRIPT_CLOSURE = [
        'bridge.js',
        'panels.js',
        'workbench-components.js',
        'tooltip.js',
        'asset-timeline.js',
        'icons.js',
        'arena-meta-rosters.js',
        'arena-factions.js',
        'arena-unit-catalog.js',
        'arena-unit-param-presets.js',
        'arena-custom-presets.js',
        'arena-custom-match-code.js',
        'arena-custom-parameters.js',
        'arena-custom-undo.js',
        'arena-custom-polling.js',
        'arena-custom-param-editor.js',
        'arena-custom-result-view.js',
        'arena/dev/known-enemies-fixtures.js',
        'arena/arena-core.js',
        'arena/arena-shell.js',
        'arena/arena-challenge-browser.js',
        'arena/arena-preview-authority.js',
        'arena/arena-custom-editor.js',
        'arena/arena-result.js',
        'arena-panel.js'
    ];

    var FIXTURES = {
        normal: { money: 5717348, playerLevel: 28, reuseCount: 1, reuseLimit: 2 },
        broke: { money: 0, playerLevel: 8, reuseCount: 0, reuseLimit: 2 }
    };

    var errors = [];
    var warnings = [];
    function error(name, detail) { errors.push({ name: name, detail: detail || '' }); }
    function expect(name, value, detail) { if (!value) error(name, detail); }
    function near(a, b, tolerance) { return Math.abs(a - b) <= tolerance; }

    function installWebviewMock(state) {
        var listeners = [];
        var fixture = FIXTURES[state === 'blocked' ? 'broke' : 'normal'];
        window.chrome = window.chrome || {};
        window.chrome.webview = {
            addEventListener: function(type, handler) {
                if (type === 'message') listeners.push(handler);
            },
            postMessage: function(message) { handleMessage(message); },
            __dispatch: function(data) {
                var event = { data: data };
                listeners.forEach(function(l) { l(event); });
            }
        };
        function knownEnemies() {
            if (window.ArenaQaKnownFixtures) return window.ArenaQaKnownFixtures.all();
            return [];
        }
        function handleMessage(message) {
            if (message.cmd === 'snapshot') {
                setTimeout(function() {
                    window.chrome.webview.__dispatch({
                        type: 'panel_resp', panel: 'arena', cmd: 'snapshot',
                        callId: message.callId, success: true,
                        snapshot: {
                            money: fixture.money,
                            playerLevel: fixture.playerLevel,
                            reuseCount: fixture.reuseCount,
                            reuseLimit: fixture.reuseLimit,
                            knownEnemies: knownEnemies()
                        }
                    });
                }, 50);
            } else if (message.cmd === 'preview') {
                var cardIdx = message.cardIndex;
                setTimeout(function() {
                    var m = String(message.expr || '').match(/@(\d+)-(\d+)%(\d+)/);
                    var lo = m ? Number(m[1]) : 1;
                    var hi = m ? Number(m[2]) : 10;
                    var count = m ? Number(m[3]) : 1;
                    var opponents = [];
                    for (var i = 0; i < count; i++) {
                        var lvl = lo + Math.floor((hi - lo) * (i + 1) / (count + 1));
                        var eLvl = Math.max(1, Math.floor(lvl / 5));
                        opponents.push({
                            name: 'Atlas-' + (cardIdx != null ? cardIdx + '-' : '') + (i + 1),
                            level: lvl,
                            equips: [
                                { slot: 6, raw: '铁盔', name: '铁盔', icon: '铁盔', displayname: '铁盔', level: eLvl },
                                { slot: 10, raw: '铁靴', name: '铁靴', icon: '铁靴', displayname: '铁靴', level: eLvl }
                            ],
                            skills: [
                                { name: '瞬步', level: 1 + (i % 5), type: '位移', trait: '闪避', cooldown: 8, cost: 20 },
                                { name: '战吼', level: 1 + (i % 3), type: '增益', trait: '团队', cooldown: 20, cost: 15 }
                            ]
                        });
                    }
                    window.chrome.webview.__dispatch({
                        type: 'panel_resp', panel: 'arena', cmd: 'preview',
                        callId: message.callId, cardIndex: cardIdx,
                        success: true, expr: message.expr, opponents: opponents
                    });
                }, 60);
            }
            // enter / equip_tooltip / custom_* 在 atlas 场景不触发，无需应答
        }
    }

    function loadScriptsSequentially(urls, done, fail) {
        var i = 0;
        function next() {
            if (i >= urls.length) { done(); return; }
            var url = urls[i++];
            var tag = document.createElement('script');
            tag.src = url;
            tag.onload = next;
            tag.onerror = function() { fail(new Error('script load failed: ' + url)); };
            document.head.appendChild(tag);
        }
        next();
    }

    function poll(condition, timeoutMs, done) {
        var start = Date.now();
        (function tick() {
            var ok = false;
            try { ok = condition(); } catch (e) { /* 驱动中间态容忍瞬时异常 */ }
            if (ok) { done(true); return; }
            if (Date.now() - start > timeoutMs) { done(false); return; }
            setTimeout(tick, 100);
        })();
    }

    function run() {
        var params = new URLSearchParams(location.search);
        var state = params.get('state') || 'default';
        var reducedExpected = params.get('reduced') === '1';
        var metrics = {};

        installWebviewMock(state);
        window.CF7_ICON_ROOT = '/launcher/web/icons/';

        loadScriptsSequentially(SCRIPT_CLOSURE.map(function(rel) { return MODULE_BASE + rel; }), function() {
            // panels.js 契约容器绑定（harness 里由 harness-base.js 代办，这里显式调用）
            if (typeof Panels !== 'undefined' && Panels.init) Panels.init();
            // 打开真实面板（panels.js 契约容器由 atlas 页提供）
            window.chrome.webview.__dispatch({ type: 'panel_cmd', cmd: 'open', panel: 'arena', initData: {} });
            poll(function() {
                return !!(document.querySelector('.arena-panel .workbench-shell')
                    && window.ArenaPanel && window.ArenaPanel.getState().snapshot);
            }, 9000, function(opened) {
                expect('arena panel opens with workbench shell and snapshot', opened);
                if (!opened) return finish(state, reducedExpected, metrics);
                poll(function() {
                    var st = window.ArenaPanel.getState();
                    return document.querySelectorAll('#arena-grid .arena-card').length === 12
                        && st.previewPendingCount === 0 && st.previewCacheCount > 0;
                }, 9000, function(ready) {
                    expect('catalog previews settle (12 cards, cache filled)', ready,
                        JSON.stringify(window.ArenaPanel.getState ? {
                            pending: window.ArenaPanel.getState().previewPendingCount,
                            cached: window.ArenaPanel.getState().previewCacheCount,
                            cards: document.querySelectorAll('#arena-grid .arena-card').length
                        } : {}));
                    driveState(state, function() { finish(state, reducedExpected, metrics); });
                });
            });
        }, function(err) {
            error('arena closure load', err && err.message);
            finish(state, reducedExpected, metrics);
        });
    }

    function driveState(state, done) {
        if (state === 'default') { done(); return; }
        var card = document.querySelector('#arena-grid .arena-card');
        if (!card) { error('state drive', 'no card to select'); done(); return; }
        card.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        poll(function() {
            var opponents = document.getElementById('arena-opponents');
            return !!(opponents && opponents.childElementCount > 0);
        }, 5000, function(ok) {
            expect('selected card fills decision preview', ok);
            done();
        });
    }

    function finish(state, reducedExpected, metrics) {
        var panel = document.querySelector('.arena-panel');
        var shell = panel && panel.querySelector('.workbench-shell');
        var scaleShell = document.querySelector('.arena-scale-shell');
        var scale = scaleShell
            ? parseFloat(getComputedStyle(scaleShell).getPropertyValue('--panel-scale')) || 1 : 1;

        expect('arena skin anchor present', !!document.querySelector('.arena-panel[data-workbench-skin="arena"]'));
        expect('catalog-decision shell mounted inside arena panel', !!shell);
        if (shell) {
            var slots = shell.querySelectorAll('.workbench-slot');
            expect('dual slots remain separated', slots.length === 2
                && slots[0].getBoundingClientRect().right < slots[1].getBoundingClientRect().left, 'slot geometry');
            var body = shell.querySelector('.workbench-body');
            if (body) expect('workbench body avoids horizontal overflow',
                body.scrollWidth <= body.clientWidth + 1, body.scrollWidth + '/' + body.clientWidth);
        }
        if (panel) {
            var rect = panel.getBoundingClientRect();
            expect('logical canvas is 1024x576', near(rect.width / scale, 1024, .75) && near(rect.height / scale, 576, .75),
                JSON.stringify([rect.width, rect.height, scale]));
            expect('player-facing sample hides protocol vocabulary',
                !/(?:callId|lease|opaque|token|\bAS2\b|\bwire\b|epoch)/i.test(panel.textContent),
                (panel.textContent.match(/(?:callId|lease|opaque|token|\bAS2\b|\bwire\b|epoch)/i) || [''])[0]);
        }
        var cards = document.querySelectorAll('#arena-grid .arena-card');
        expect('catalog renders 12 challenge cards as options', cards.length === 12
            && document.querySelector('#arena-grid').getAttribute('role') === 'listbox'
            && cards[0] && cards[0].getAttribute('role') === 'option', String(cards.length));
        var commitBtn = panel && panel.querySelector('.workbench-commit-bar .workbench-commit-primary');
        var commitStatus = panel && panel.querySelector('.workbench-commit-bar .workbench-commit-status');
        expect('shared CommitBar present as decision CTA', !!commitBtn);

        if (state === 'default') {
            var title = document.getElementById('arena-detail-title');
            expect('default state keeps decision empty', !!title && title.textContent === '选择挑战'
                && !!document.querySelector('#arena-opponents .arena-decision-empty'),
                title && title.textContent);
            expect('default state commit disabled', !!commitBtn && commitBtn.disabled);
        } else if (state === 'selected') {
            expect('exactly one card selected', document.querySelectorAll('#arena-grid .arena-card[aria-selected="true"]').length === 1);
            expect('selected state commit ready with economy summary', !!commitBtn && !commitBtn.disabled
                && !!commitStatus && commitStatus.textContent.indexOf('押金') >= 0,
                commitStatus && commitStatus.textContent);
        } else if (state === 'blocked') {
            expect('blocked state commit disabled with money reason', !!commitBtn && commitBtn.disabled
                && !!commitStatus && commitStatus.textContent.indexOf('金钱不足') >= 0,
                commitStatus && commitStatus.textContent);
        }

        var mediaReduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
        expect('reduced-motion emulation matches requested scenario', mediaReduced === reducedExpected, String(mediaReduced));
        if (cards.length) {
            var animationName = getComputedStyle(cards[0]).animationName;
            if (reducedExpected) {
                expect('reduced-motion strips card entrance animation', animationName === 'none', animationName);
            } else {
                expect('motion scenario keeps card entrance animation', animationName !== 'none', animationName);
            }
        }

        var caseId = 'arena-' + window.innerWidth + 'x' + window.innerHeight + '-' + state + '-' + (reducedExpected ? 'reduce' : 'motion');
        metrics = {
            caseId: caseId, viewport: [window.innerWidth, window.innerHeight], scene: 'arena', state: state,
            reduced: reducedExpected, scale: scale, cards: cards.length
        };
        var badge = document.getElementById('atlas-badge');
        if (badge) badge.textContent = caseId;
        document.title = 'CF7 Workbench Atlas · ' + caseId;
        window.__qaResult = { schemaVersion: 1, caseId: caseId, errors: errors, warnings: warnings, metrics: metrics };
        window.__qaDone = true;
        window.__visualReady = true;
        var output = document.getElementById('atlas-output');
        if (output) output.textContent = JSON.stringify(window.__qaResult, null, 2);
        if (shell) shell.setAttribute('data-atlas-result', errors.length ? 'error' : warnings.length ? 'warning' : 'pass');
    }

    window.__atlasArenaScene = { run: run };
})();
