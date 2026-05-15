/**
 * Arena Panel QA Suite
 *
 * 测试覆盖：
 *   - panel-open: Panel 能正确打开并渲染 8 张卡片
 *   - snapshot-render: snapshot 到达后金钱显示正确，卡片状态正确
 *   - enter-success: 点击卡片发送 enter，收到成功回包
 *   - enter-insufficient-money: 金钱不足时按钮禁用，点击不发送请求
 *   - close-btn: 关闭按钮发送 close 命令
 *   - esc-close: ESC 触发关闭
 *   - force-close: force_close 正确处理
 *   - card-count: 确认 8 张卡片都存在且数据正确
 *   - roll-again: "换一批"按钮重发 preview，并刷新对手渲染
 *   - preview-switch-race: 卡片 A preview 飞行中切到卡片 B，旧回包被闭包丢弃
 *   - equip-tooltip: hover 装备发送 equip_tooltip，回包后 cache，第二次 hover 不再发请求
 */
var ArenaHarnessQA = (function() {
    'use strict';

    var CASES = [
        { id: 'panel-open',           title: 'Panel 打开并渲染 8 张卡片' },
        { id: 'snapshot-render',      title: 'Snapshot 更新 UI 状态' },
        { id: 'enter-success',        title: 'Enter 成功链路' },
        { id: 'enter-fail-money',     title: '金钱不足时禁用挑战' },
        { id: 'close-btn',            title: '关闭按钮' },
        { id: 'esc-close',            title: 'ESC 关闭' },
        { id: 'force-close',          title: 'Force Close' },
        { id: 'card-count',           title: '卡片数据完整性' },
        { id: 'roll-again',           title: '换一批重发 preview' },
        { id: 'preview-switch-race',  title: '切卡片时旧 preview 回包被丢弃' },
        { id: 'equip-tooltip',        title: '装备 hover 发起 tooltip 请求 + cache' }
    ];

    function runSuite(api, host, onlyCase) {
        var tests = CASES;
        if (onlyCase) {
            tests = tests.filter(function(c) { return c.id === onlyCase; });
            if (tests.length === 0) {
                return Promise.resolve(MinigameHarness.normalizeBundle([
                    { id: onlyCase, title: 'unknown case', pass: false, detail: 'case not found' }
                ]));
            }
        }
        return Promise.all(tests.map(function(tc) {
            return api.runCase(tc.id, tc.title, function() {
                return runCase(api, host, tc.id);
            });
        })).then(function(results) {
            return MinigameHarness.normalizeBundle(results);
        });
    }

    function runCase(api, host, id) {
        switch (id) {
            case 'panel-open':           return casePanelOpen(api, host);
            case 'snapshot-render':      return caseSnapshotRender(api, host);
            case 'enter-success':        return caseEnterSuccess(api, host);
            case 'enter-fail-money':     return caseEnterFailMoney(api, host);
            case 'close-btn':            return caseCloseBtn(api, host);
            case 'esc-close':            return caseEscClose(api, host);
            case 'force-close':          return caseForceClose(api, host);
            case 'card-count':           return caseCardCount(api, host);
            case 'roll-again':           return caseRollAgain(api, host);
            case 'preview-switch-race':  return casePreviewSwitchRace(api, host);
            case 'equip-tooltip':        return caseEquipTooltip(api, host);
            default:                     return Promise.resolve({ pass: false, detail: 'unknown case' });
        }
    }

    // ── case: panel-open ──
    function casePanelOpen(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('normal');
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                var grid = document.querySelector('.arena-grid');
                api.assert(!!grid, 'arena-grid 不存在');
                var cards = grid.querySelectorAll('.arena-card');
                api.assertEqual(cards.length, 8, '卡片数量应为 8');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: snapshot-render ──
    function caseSnapshotRender(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('poor');
                host.open();
                return api.waitFor(function() {
                    return document.querySelector('.arena-money-value') != null;
                }, 2000, 'money element');
            })
            .then(function() {
                // 等待 snapshot 回包渲染
                return api.waitFor(function() {
                    var el = document.querySelector('.arena-money-value');
                    return el && el.textContent.indexOf('1,000') >= 0;
                }, 2000, 'money rendered');
            })
            .then(function() {
                // 金钱不足时，高押金卡片应被禁用
                var disabled = document.querySelectorAll('.arena-card-disabled');
                api.assert(disabled.length >= 6, '贫穷状态下至少 6 张卡片应被禁用（实际: ' + disabled.length + '）');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: enter-success ──
    // 新流程: 点卡片 → preview → 详情视图 → 确认挑战 → enter
    function caseEnterSuccess(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.enterMessages = [];
                host.previewMessages = [];
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return api.waitFor(function() {
                    var el = document.querySelector('.arena-card-btn');
                    return el && !el.disabled;
                }, 2000, 'card button ready');
            })
            .then(function() {
                var btn = document.querySelector('.arena-card-btn');
                btn.click();
                return api.waitFor(function() {
                    return host.previewMessages.length > 0;
                }, 2000, 'preview message sent');
            })
            .then(function() {
                var pmsg = host.previewMessages[host.previewMessages.length - 1];
                api.assert(pmsg.cmd === 'preview', '首条消息应为 preview');
                api.assert(typeof pmsg.expr === 'string' && pmsg.expr.length > 0, 'preview 应携带 expr');
                // 等对手渲染完毕（确认挑战按钮启用）
                return api.waitFor(function() {
                    var confirmBtn = document.querySelector('.arena-detail-confirm');
                    return confirmBtn && !confirmBtn.disabled;
                }, 2000, 'detail view + confirm enabled');
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assert(rows.length >= 1, '对手行应被渲染');
                var confirmBtn = document.querySelector('.arena-detail-confirm');
                confirmBtn.click();
                return api.waitFor(function() {
                    return host.enterMessages.length > 0;
                }, 2000, 'enter message sent');
            })
            .then(function() {
                var msg = host.enterMessages[host.enterMessages.length - 1];
                api.assert(msg.cmd === 'enter', '提交消息应为 enter');
                api.assert(typeof msg.cardIndex === 'number', '应包含 cardIndex');
                api.assert(typeof msg.expr === 'string' && msg.expr.length > 0, 'enter 应携带 expr');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: enter-fail-money ──
    function caseEnterFailMoney(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('broke');
                host.open();
                return api.waitFor(function() {
                    return document.querySelector('.arena-card-disabled') != null;
                }, 2000, 'disabled cards rendered');
            })
            .then(function() {
                var btn = document.querySelector('.arena-card-btn');
                api.assert(!!btn, '找不到卡片按钮');
                api.assert(btn.disabled === true, '破产状态下按钮应被禁用');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: close-btn ──
    function caseCloseBtn(api, host) {
        return Promise.resolve()
            .then(function() {
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                var closeBtn = document.querySelector('.arena-close-btn');
                api.assert(!!closeBtn, '关闭按钮不存在');
                closeBtn.click();
                return api.waitFor(function() {
                    return !Panels.getActive || Panels.getActive() !== 'arena';
                }, 2000, 'panel closed');
            })
            .then(function() {
                var msgs = host.sentMessages.filter(function(m) {
                    return m.type === 'panel' && m.cmd === 'close' && m.panel === 'arena';
                });
                api.assert(msgs.length >= 1, '应发送至少一条 close 消息');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: esc-close ──
    function caseEscClose(api, host) {
        return Promise.resolve()
            .then(function() {
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                // 模拟 C# 发送 panel_esc
                chrome.webview.__dispatch({ type: 'panel_esc' });
                return api.waitFor(function() {
                    return !Panels.getActive || Panels.getActive() !== 'arena';
                }, 2000, 'panel closed via esc');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: force-close ──
    function caseForceClose(api, host) {
        return Promise.resolve()
            .then(function() {
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                host.forceClose();
                return api.waitFor(function() {
                    return !Panels.getActive || Panels.getActive() !== 'arena';
                }, 2000, 'panel force-closed');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: roll-again ──
    function caseRollAgain(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.previewMessages = [];
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return api.waitFor(function() {
                    var el = document.querySelector('.arena-card-btn');
                    return el && !el.disabled;
                }, 2000, 'card button ready');
            })
            .then(function() {
                document.querySelector('.arena-card-btn').click();
                return api.waitFor(function() {
                    var btn = document.querySelector('.arena-detail-roll');
                    return btn && !btn.disabled;
                }, 2000, 'first preview done, roll-again enabled');
            })
            .then(function() {
                var before = host.previewMessages.length;
                document.querySelector('.arena-detail-roll').click();
                return api.waitFor(function() {
                    return host.previewMessages.length > before;
                }, 2000, 'second preview sent');
            })
            .then(function() {
                api.assert(host.previewMessages.length >= 2, '应至少发出 2 条 preview（首次 + 换一批）');
                return api.waitFor(function() {
                    var btn = document.querySelector('.arena-detail-confirm');
                    return btn && !btn.disabled;
                }, 2000, 'confirm re-enabled after second preview');
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assert(rows.length >= 1, '换一批后对手应重新渲染');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: preview-switch-race ──
    // 点卡 A → preview 飞行中点 back → 点卡 B → 等 B 渲染 →
    // 等待 A 的回包到达 → 验证 A 的迟到回包没有污染 B 的渲染（_activeCardIdx 闭包守住）
    function casePreviewSwitchRace(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.previewMessages = [];
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return api.waitFor(function() {
                    var btns = document.querySelectorAll('.arena-card-btn');
                    return btns.length >= 2 && !btns[0].disabled && !btns[1].disabled;
                }, 2000, 'first two cards ready');
            })
            .then(function() {
                // card-1: opponentCount=1
                document.querySelectorAll('.arena-card-btn')[0].click();
                // 不等 preview 回包，立刻 back
                document.querySelector('.arena-detail-back').click();
                // 立刻点 card-2: opponentCount=2
                document.querySelectorAll('.arena-card-btn')[1].click();
                // 等 card-2 渲染完成
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-opp-row');
                    return rows.length === 2;
                }, 2000, 'card-2 opponents rendered (count=2)');
            })
            .then(function() {
                // 多等一会儿，确保 card-1 的迟到回包已经到达并被丢弃
                return new Promise(function(resolve) { setTimeout(resolve, 200); });
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assertEqual(rows.length, 2, 'card-1 迟到回包不应改写 card-2 的渲染（仍 2 行）');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: equip-tooltip ──
    // hover 装备格 → 发出 equip_tooltip → 回包 cache →
    // 再次 hover 同一格 → 不应发新请求（命中 cache）
    function caseEquipTooltip(api, host) {
        function fireMouse(el, type) {
            var evt = document.createEvent('MouseEvent');
            evt.initMouseEvent(type, true, true, window, 0, 0, 0, 0, 0, false, false, false, false, 0, null);
            el.dispatchEvent(evt);
        }
        function countTooltipReqs() {
            return host.sentMessages.filter(function(m) { return m.cmd === 'equip_tooltip'; }).length;
        }
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.sentMessages = [];
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return api.waitFor(function() {
                    var el = document.querySelector('.arena-card-btn');
                    return el && !el.disabled;
                }, 2000, 'card button ready');
            })
            .then(function() {
                document.querySelector('.arena-card-btn').click();
                return api.waitFor(function() {
                    var cells = document.querySelectorAll('.arena-equip-cell[data-eq-raw]');
                    return cells.length > 0;
                }, 2000, 'equip cells rendered');
            })
            .then(function() {
                var cell = document.querySelector('.arena-equip-cell[data-eq-raw]');
                api.assert(!!cell, '应有装备格');
                fireMouse(cell, 'mouseenter');
                return api.waitFor(function() {
                    return countTooltipReqs() >= 1;
                }, 2000, 'equip_tooltip 请求发出');
            })
            .then(function() {
                // 等回包到达 + 写入 cache（mock 是 50ms 延迟）
                return new Promise(function(resolve) { setTimeout(resolve, 100); });
            })
            .then(function() {
                var cell = document.querySelector('.arena-equip-cell[data-eq-raw]');
                fireMouse(cell, 'mouseleave');
                var before = countTooltipReqs();
                fireMouse(cell, 'mouseenter');
                return new Promise(function(resolve) { setTimeout(resolve, 80); }).then(function() {
                    var after = countTooltipReqs();
                    api.assertEqual(after, before, '同 (raw|level) 再次 hover 应命中 cache，不发新请求');
                });
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: card-count ──
    function caseCardCount(api, host) {
        return Promise.resolve()
            .then(function() {
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                var cards = window.ArenaPanel ? window.ArenaPanel.getCards() : null;
                api.assert(!!cards, 'ArenaPanel.getCards 应返回数据');
                api.assertEqual(cards.length, 8, '应有 8 张卡片');
                var totalDeposit = cards.reduce(function(s, c) { return s + c.deposit; }, 0);
                var totalReward = cards.reduce(function(s, c) { return s + c.reward; }, 0);
                api.assert(totalDeposit > 0, '押金总和应大于 0');
                api.assert(totalReward > 0, '奖金总和应大于 0');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    return {
        runSuite: runSuite
    };
})();
