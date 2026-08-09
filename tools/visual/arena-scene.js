/**
 * workbench-atlas arena 场景族（P4 接入）——真实 feature 场景：加载生产闭包
 * （与 panels-lazy-registry arena 注册项同序的生产脚本 + dev fixture），驱动真实
 * arena panel 的 catalog-decision 壳 + skin 关键状态，并在同一 case 的第二阶段切到
 * 真实 custom_result 结算页：
 *   default（未选中·决策空态）/ selected（选中卡·右栏 preview·CommitBar ready）/
 *   blocked（金钱不足·CommitBar blocked）分别映射 success / failed / error 结算态，
 *   再乘 reduced-motion（runner 媒体仿真轴）× 三视口。这样保留 canonical 66 case，
 *   同时让 18 个 Arena case 都覆盖挑战态，且最终截图稳定落在结算页。
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
        'dressup-doll-renderer.js',
        'merc-data.js',
        'merc-portrait-renderer.js',
        'icons.js',
        'portrait-resolver.js',
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
    var RESULT_BY_CHALLENGE = { 'default': 'success', selected: 'failed', blocked: 'error' };
    var RESULT_MATCH_CODE = 'CF7ARENA:v1;mode=mvm;seed=519920;blue=u44@30x1,u45@30x1,u48@30x1,u49@30x1;red=u61@60x3,u62@60x3,u63@60x1';

    // P5 Host authority fixture. Production builds these cards from arena_config.xml;
    // atlas only mirrors the wire shape so the real Web panel cannot fall back to
    // the retired client-side economy table.
    var AUTHORITY_TIERS = [
        [1, 5, 1, 1], [5, 10, 1, 2], [10, 15, 2, 3], [15, 20, 2, 4],
        [20, 30, 3, 4], [30, 35, 3, 4], [35, 40, 4, 4], [40, 50, 4, 4],
        [50, 60, 4, 4], [60, 100, 4, 4]
    ];
    function authorityRound(value, step) {
        return Math.max(step, Math.round(value / step) * step);
    }
    function authorityCard(id, mode, index, tier, count, multiplier, label) {
        var unitPrice = tier[0] >= 40 ? 1250 : 1000;
        var reward = authorityRound(authorityRound(count * tier[0] * unitPrice, 1000) * multiplier, 1000);
        return {
            id: id,
            mode: mode,
            name: 'DEATH MATCH',
            index: index,
            previewIndex: index - 1,
            opponentCount: count,
            countMin: tier[2],
            countMax: tier[3],
            levelMin: tier[0],
            levelMax: tier[1],
            deposit: Math.max(500, authorityRound(reward / 2, 500)),
            reward: reward,
            expr: '#0@' + tier[0] + '-' + tier[1] + '%' + count,
            economyMultiplier: multiplier,
            hiddenLabel: label || '',
            isHiddenChallenge: mode === 'hidden',
            requiresMixedRoster: mode === 'hidden'
        };
    }
    function buildAuthorityFixture(playerLevel) {
        var cards = [];
        for (var i = 0; i < AUTHORITY_TIERS.length; i++) {
            cards.push(authorityCard('arena-' + (i + 1), 'standard', i + 1,
                AUTHORITY_TIERS[i], AUTHORITY_TIERS[i][3], 1, ''));
        }
        var tierIndex = AUTHORITY_TIERS.length - 1;
        for (var t = 0; t < AUTHORITY_TIERS.length; t++) {
            if (playerLevel >= AUTHORITY_TIERS[t][0]
                    && (playerLevel < AUTHORITY_TIERS[t][1] || t === AUTHORITY_TIERS.length - 1)) {
                tierIndex = t;
                break;
            }
        }
        var hidden = [
            ['arena-hidden-1', 1, 3, 1.5, 'Alert I'],
            ['arena-hidden-2', 2, 4, 2.0, 'Alert II']
        ];
        for (var h = 0; h < hidden.length; h++) {
            var target = AUTHORITY_TIERS[Math.min(tierIndex + hidden[h][1], AUTHORITY_TIERS.length - 1)];
            cards.push(authorityCard(hidden[h][0], 'hidden', cards.length + 1,
                target, hidden[h][2], hidden[h][3], hidden[h][4]));
        }
        return { schemaVersion: 1, source: 'atlas-authority-fixture', sourceDigest: 'ATLAS', cards: cards };
    }

    var errors = [];
    var warnings = [];
    function error(name, detail) { errors.push({ name: name, detail: detail || '' }); }
    function expect(name, value, detail) { if (!value) error(name, detail); }
    function near(a, b, tolerance) { return Math.abs(a - b) <= tolerance; }

    function installWebviewMock(state) {
        var listeners = [];
        var fixture = FIXTURES[state === 'blocked' ? 'broke' : 'normal'];
        var authorityById = {};
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
                    var authority = buildAuthorityFixture(fixture.playerLevel);
                    authorityById = {};
                    for (var a = 0; a < authority.cards.length; a++) {
                        authorityById[authority.cards[a].id] = authority.cards[a];
                    }
                    window.chrome.webview.__dispatch({
                        type: 'panel_resp', panel: 'arena', cmd: 'snapshot',
                        callId: message.callId, success: true,
                        snapshot: {
                            money: fixture.money,
                            playerLevel: fixture.playerLevel,
                            reuseCount: fixture.reuseCount,
                            reuseLimit: fixture.reuseLimit,
                            knownEnemies: knownEnemies(),
                            arenaAuthority: authority
                        }
                    });
                }, 50);
            } else if (message.cmd === 'preview') {
                var cardIdx = message.cardIndex;
                setTimeout(function() {
                    var authorityCard = authorityById[message.cardId] || null;
                    var m = String(authorityCard && authorityCard.expr || '').match(/@(\d+)-(\d+)%(\d+)/);
                    var lo = m ? Number(m[1]) : 1;
                    var hi = m ? Number(m[2]) : 10;
                    var count = m ? Number(m[3]) : 1;
                    var opponents = [];
                    for (var i = 0; i < count; i++) {
                        var lvl = lo + Math.floor((hi - lo) * (i + 1) / (count + 1));
                        var eLvl = Math.max(1, Math.floor(lvl / 5));
                        opponents.push({
                            id: 'arena-atlas-' + cardIdx + '-' + i,
                            name: 'Atlas-' + (cardIdx != null ? cardIdx + '-' : '') + (i + 1),
                            level: lvl,
                            gender: i % 2 ? '女' : '男',
                            face: i % 2 ? '女变装-基本脸型' : '男变装-基本脸型',
                            hair: i % 2 ? '发型-女式-玫红色马尾' : '发型-男式-黑韩式头',
                            equips: [
                                { slot: 6, raw: '锐刻幻影夜视仪', name: '锐刻幻影夜视仪', icon: '锐刻幻影夜视仪', displayname: '锐刻幻影夜视仪', level: eLvl },
                                { slot: 7, raw: '蓝晶战斗服', name: '蓝晶战斗服', icon: '蓝晶战斗服', displayname: '蓝晶战斗服', level: eLvl },
                                { slot: 12, raw: '战术巴雷特', name: '战术巴雷特', icon: '战术巴雷特', displayname: '战术巴雷特', level: eLvl }
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
                        success: true, expr: authorityCard ? authorityCard.expr : '', opponents: opponents
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
        var resultState = params.get('resultState') || RESULT_BY_CHALLENGE[state] || 'success';
        var reducedExpected = params.get('reduced') === '1';
        var metrics = {};

        installWebviewMock(state);
        window.CF7_ICON_ROOT = '/launcher/web/icons/';
        window.CF7_DRESSUP_MANIFEST_URL = '/launcher/web/assets/dressup/manifest.json';
        window.CF7_PORTRAIT_ROOT = '/launcher/web/assets/enemy-portraits/';
        window.CF7_PORTRAIT_LEGACY_ROOT = '/launcher/web/assets/pets/';
        window.CF7_PORTRAIT_LOCKED_URL = '/launcher/web/assets/pets/pet_locked.png';

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
                if (!opened) return finish(state, resultState, reducedExpected, metrics);
                poll(function() {
                    var st = window.ArenaPanel.getState();
                    return document.querySelectorAll('#arena-grid .arena-card').length === 12
                        && st.previewPendingCount === 0 && st.previewCacheCount > 0
                        && !document.querySelector('#arena-grid [data-merc-portrait-state="pending"]');
                }, 9000, function(ready) {
                    expect('catalog previews settle (12 cards, cache filled)', ready,
                        JSON.stringify(window.ArenaPanel.getState ? {
                            pending: window.ArenaPanel.getState().previewPendingCount,
                            cached: window.ArenaPanel.getState().previewCacheCount,
                            cards: document.querySelectorAll('#arena-grid .arena-card').length
                        } : {}));
                    driveState(state, function() { finish(state, resultState, reducedExpected, metrics); });
                });
            });
        }, function(err) {
            error('arena closure load', err && err.message);
            finish(state, resultState, reducedExpected, metrics);
        });
    }

    function driveState(state, done) {
        if (state === 'default') { done(); return; }
        var card = document.querySelector('#arena-grid .arena-card');
        if (!card) { error('state drive', 'no card to select'); done(); return; }
        card.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        poll(function() {
            var opponents = document.getElementById('arena-opponents');
            return !!(opponents && opponents.childElementCount > 0
                && !opponents.querySelector('[data-merc-portrait-state="pending"]'));
        }, 5000, function(ok) {
            expect('selected card fills decision preview', ok);
            done();
        });
    }

    function resultInitData(resultState) {
        var failed = resultState === 'failed';
        var errorResult = resultState === 'error';
        return {
            mode: 'custom_result',
            source: 'workbench_atlas',
            matchCode: RESULT_MATCH_CODE,
            state: failed ? 'failed' : 'completed',
            batchId: 'atlas-p4-001',
            totalRuns: 1,
            completedRuns: 1,
            resultPath: 'logs/arena-custom/atlas-p4-results.jsonl',
            lastError: failed ? '委托执行失败：未产生可信战果'
                : errorResult ? '结果文件校验失败：错误条必须保持可见' : '',
            lastResult: failed ? null : {
                schema: 'arena-calibration.result.v1',
                status: 'finished',
                winner: 'blue',
                frames: 196,
                durationMs: 6533,
                spawnDistance: 650,
                blueFormation: 'line',
                redFormation: 'shield',
                formationSpacing: 54,
                blue: { aliveCount: 3, startCount: 4, remainHp: 6840, maxHp: 9200 },
                red: { aliveCount: 0, startCount: 7, remainHp: 0, maxHp: 12800 }
            }
        };
    }

    function driveResultState(resultState, done) {
        if (typeof Panels === 'undefined' || !Panels.close
                || !window.chrome || !window.chrome.webview || !window.chrome.webview.__dispatch) {
            error('result state drive', 'Panels / WebView lifecycle unavailable');
            done(false);
            return;
        }
        try {
            // 同一生产 DOM 先走 Panels.close()，再由 WebView panel_cmd 经过 Bridge ->
            // Panels.open() 重开；不直接调用 ArenaShell 或写 innerHTML，避免 atlas 绕过
            // 宿主生命周期及 normalize/build/render/focus/PanelScale 等结算页合同。
            Panels.close();
            window.chrome.webview.__dispatch({
                type: 'panel_cmd',
                cmd: 'open',
                panel: 'arena',
                initData: resultInitData(resultState)
            });
        } catch (e) {
            error('result state drive', e && e.message ? e.message : String(e));
            done(false);
            return;
        }
        poll(function() {
            var view = document.getElementById('arena-custom-result-view');
            return !!(view && !view.hidden && view.querySelector('.arena-custom-result-panel')
                && view.querySelector('.arena-custom-result-title'));
        }, 5000, done);
    }

    function resolvedTokenColor(host, token) {
        if (!host) return '';
        var probe = document.createElement('span');
        probe.style.cssText = 'position:absolute;visibility:hidden;color:var(' + token + ')';
        host.appendChild(probe);
        var value = getComputedStyle(probe).color;
        host.removeChild(probe);
        return value;
    }

    function zeroTimeList(value) {
        return String(value || '').split(',').every(function(part) {
            var number = parseFloat(part);
            return !isNaN(number) && number === 0;
        });
    }

    function validateResult(resultState, reducedExpected, scale, metrics) {
        var panel = document.querySelector('.arena-panel');
        var grid = document.getElementById('arena-grid-view');
        var view = document.getElementById('arena-custom-result-view');
        var resultPanel = view && view.querySelector('.arena-custom-result-panel');
        var title = view && view.querySelector('.arena-custom-result-title');
        var errorStrip = view && view.querySelector('.arena-custom-result-error');
        var actions = view ? view.querySelectorAll('[data-custom-result-action]') : [];
        var uniqueActions = {};
        Array.prototype.forEach.call(actions, function(action) {
            uniqueActions[action.getAttribute('data-custom-result-action')] = true;
        });

        expect('custom result phase opens through production lifecycle', !!(view && !view.hidden && resultPanel));
        expect('challenge grid is hidden behind result phase', !!grid && grid.hidden);
        expect('result actions expose copy/back/reopen paths', !!(uniqueActions.copy && uniqueActions.back && uniqueActions.reopen),
            JSON.stringify(Object.keys(uniqueActions)));
        expect('result focus scope moves focus into result page', !!(view && view.contains(document.activeElement)),
            document.activeElement && document.activeElement.className);

        if (view && resultPanel) {
            var viewRect = view.getBoundingClientRect();
            var resultRect = resultPanel.getBoundingClientRect();
            expect('result page avoids horizontal overflow', view.scrollWidth <= view.clientWidth + 1
                && resultPanel.scrollWidth <= resultPanel.clientWidth + 1,
                JSON.stringify({ view: [view.scrollWidth, view.clientWidth], panel: [resultPanel.scrollWidth, resultPanel.clientWidth] }));
            expect('result panel remains inside logical canvas', resultRect.left >= viewRect.left - 1
                && resultRect.right <= viewRect.right + 1 && resultRect.top >= viewRect.top - 1
                && resultRect.bottom <= viewRect.bottom + 1,
                JSON.stringify({ view: [viewRect.left, viewRect.top, viewRect.right, viewRect.bottom],
                    result: [resultRect.left, resultRect.top, resultRect.right, resultRect.bottom] }));
        }
        expect('result actions keep at least 24px logical hit height', actions.length > 0
            && Array.prototype.every.call(actions, function(action) {
                return action.getBoundingClientRect().height / scale >= 24;
            }), String(actions.length));
        var reopen = view && view.querySelector('[data-custom-result-action="reopen"]');
        expect('result primary CTA keeps 40px logical hit height', !!reopen
            && reopen.getBoundingClientRect().height / scale >= 40,
            reopen ? String(reopen.getBoundingClientRect().height / scale) : 'missing');

        if (resultState === 'failed') {
            expect('failed result renders explicit failure title', !!title && title.textContent === '委托失败'
                && title.classList.contains('arena-custom-result-title-failed'), title && title.textContent);
            expect('failed title uses semantic danger token', !!title
                && getComputedStyle(title).color === resolvedTokenColor(panel, '--wb-semantic-danger'),
                title && getComputedStyle(title).color);
        } else {
            expect('completed result renders blue victory title', !!title && title.textContent === '蓝方胜'
                && title.classList.contains('arena-custom-result-title-blue'), title && title.textContent);
        }
        if (resultState === 'success') {
            expect('success result has no error strip', !errorStrip);
        } else {
            expect('failed/error result keeps error strip visible', !!errorStrip && errorStrip.textContent.length > 0);
            expect('result error strip uses semantic danger token', !!errorStrip
                && getComputedStyle(errorStrip).color === resolvedTokenColor(panel, '--wb-semantic-danger'),
                errorStrip && getComputedStyle(errorStrip).color);
            expect('result error strip keeps visible surface and border', !!errorStrip
                && getComputedStyle(errorStrip).backgroundColor !== 'rgba(0, 0, 0, 0)'
                && getComputedStyle(errorStrip).borderTopStyle !== 'none');
        }

        if (reducedExpected && view) {
            var motionNodes = [view, resultPanel, title, actions[0]];
            expect('reduced-motion strips result animations and transitions', motionNodes.every(function(node) {
                if (!node) return false;
                var style = getComputedStyle(node);
                return style.animationName === 'none' && zeroTimeList(style.transitionDuration);
            }), 'result motion sample');
        }
        metrics.resultTitle = title ? title.textContent : '';
        metrics.resultActionCount = actions.length;
        metrics.resultErrorVisible = !!errorStrip;
    }

    function complete(state, resultState, reducedExpected, metrics, shell) {
        var caseId = 'arena-' + window.innerWidth + 'x' + window.innerHeight + '-' + state
            + '-result-' + resultState + '-' + (reducedExpected ? 'reduce' : 'motion');
        metrics.caseId = caseId;
        metrics.viewport = [window.innerWidth, window.innerHeight];
        metrics.scene = 'arena';
        metrics.challengeState = state;
        metrics.resultState = resultState;
        metrics.reduced = reducedExpected;
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

    function finish(state, resultState, reducedExpected, metrics) {
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

        metrics = {
            scale: scale, cards: cards.length
        };
        driveResultState(resultState, function(ready) {
            expect('custom result phase settles', ready, resultState);
            var resultScaleShell = document.querySelector('.arena-scale-shell');
            var resultScale = resultScaleShell
                ? parseFloat(getComputedStyle(resultScaleShell).getPropertyValue('--panel-scale')) || scale : scale;
            validateResult(resultState, reducedExpected, resultScale, metrics);
            complete(state, resultState, reducedExpected, metrics, shell);
        });
    }

    window.__atlasArenaScene = { run: run };
})();
