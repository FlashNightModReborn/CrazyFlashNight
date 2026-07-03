/**
 * Arena Panel QA Suite
 *
 * 测试覆盖（11 旧 + 7 新）：
 *   - panel-open: Panel 能正确打开并渲染 8 张卡片
 *   - snapshot-render: snapshot 到达后金钱显示正确，卡片状态正确
 *   - enter-success: 通过 detail 路径入场（点 🔍 → 等 cache 命中 → 点确认挑战）
 *   - enter-fail-money: 金钱不足时 enter 按钮 disabled，detail 按钮仍可点
 *   - close-btn: 关闭按钮发送 close 命令
 *   - esc-close: ESC 触发关闭
 *   - force-close: force_close 正确处理
 *   - card-count: 确认 8 张卡片都存在且数据正确
 *   - roll-again: "换一批"按钮重发 preview 并刷新对手渲染
 *   - preview-switch-race: 用 onRollAgain 在 detail 飞行中 → back → 进另一卡，验旧回包不污染新卡
 *   - equip-tooltip: hover 装备发送 equip_tooltip，回包后 cache，第二次 hover 不再发请求
 *   - grid-batch-preview: panel open 后 8 路并发 preview，每张卡 grid 摘要都拿到对手
 *   - grid-direct-enter: 不进 detail 直接点 grid 上"⚔ 开始挑战"，验 enter 协议带 cardIndex 且未跳 detail
 *   - grid-cache-consistency: detail 内"换一批"后回 grid，摘要文本与新对手数据一致
 *   - grid-money-disable: 金钱不足时 enter 按钮 disabled、detail 按钮仍 enabled
 *   - grid-single-fail-retry: 单卡 preview 失败 → 摘要显示"加载失败 ↻" → 点击 ↻ 触发重发
 *   - custom-match-p1: 定制赛 tab、赛程代码解析、calibration case 摘要
 *   - custom-match-p2: 定制赛开始委托、关闭 webpanel、结算回开结果态且不走正式 enter
 *   - custom-match-pve: 定制赛玩家 vs 怪物走标准 enter，不走后台 custom_start
 */
var ArenaHarnessQA = (function() {
    'use strict';

    var CASES = [
        { id: 'panel-open',           title: 'Panel 打开并渲染 8 张卡片' },
        { id: 'snapshot-render',      title: 'Snapshot 更新 UI 状态' },
        { id: 'enter-success',        title: 'Enter 成功链路（detail 路径）' },
        { id: 'enter-fail-money',     title: '金钱不足时禁用挑战' },
        { id: 'close-btn',            title: '关闭按钮' },
        { id: 'esc-close',            title: 'ESC 关闭' },
        { id: 'force-close',          title: 'Force Close' },
        { id: 'card-count',           title: '卡片数据完整性' },
        { id: 'roll-again',           title: '换一批重发 preview' },
        { id: 'preview-switch-race',  title: '迟到 preview 回包被丢弃' },
        { id: 'equip-tooltip',        title: '装备 hover 发起 tooltip 请求 + cache' },
        { id: 'grid-batch-preview',   title: 'Panel 打开后 8 路并发 preview' },
        { id: 'grid-direct-enter',    title: 'Grid 直入战场（不进 detail）' },
        { id: 'grid-cache-consistency', title: '换一批后 grid 摘要同步更新' },
        { id: 'grid-money-disable',   title: '金钱不足 enter 灰 / detail 亮' },
        { id: 'grid-single-fail-retry', title: '单卡失败显示 ↻ + 重试' },
        { id: 'custom-match-p1',      title: '定制赛 P1 赛程代码入口' },
        { id: 'custom-match-p2',      title: '定制赛 P2 后台 single-case 委托' },
        { id: 'custom-match-pve',     title: '定制赛 PVE 玩家 vs 怪物' }
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
            case 'panel-open':              return casePanelOpen(api, host);
            case 'snapshot-render':         return caseSnapshotRender(api, host);
            case 'enter-success':           return caseEnterSuccess(api, host);
            case 'enter-fail-money':        return caseEnterFailMoney(api, host);
            case 'close-btn':               return caseCloseBtn(api, host);
            case 'esc-close':               return caseEscClose(api, host);
            case 'force-close':             return caseForceClose(api, host);
            case 'card-count':              return caseCardCount(api, host);
            case 'roll-again':              return caseRollAgain(api, host);
            case 'preview-switch-race':     return casePreviewSwitchRace(api, host);
            case 'equip-tooltip':           return caseEquipTooltip(api, host);
            case 'grid-batch-preview':      return caseGridBatchPreview(api, host);
            case 'grid-direct-enter':       return caseGridDirectEnter(api, host);
            case 'grid-cache-consistency':  return caseGridCacheConsistency(api, host);
            case 'grid-money-disable':      return caseGridMoneyDisable(api, host);
            case 'grid-single-fail-retry':  return caseGridSingleFailRetry(api, host);
            case 'custom-match-p1':         return caseCustomMatchP1(api, host);
            case 'custom-match-p2':         return caseCustomMatchP2(api, host);
            case 'custom-match-pve':        return caseCustomMatchPve(api, host);
            default:                        return Promise.resolve({ pass: false, detail: 'unknown case' });
        }
    }

    // ── 公共辅助：等 batch preview 全部完成（snapshot 回包后立即并发 8 路 → 全部成功回包） ──
    // 等待条件：所有 grid 摘要 span 都已脱离 loading 态（即 _previewCache 各 cardIdx 都填了）。
    // 测试新流程下进 detail 的标准准备步骤：先等 batch 完成，确保 cache 命中跳过 detail 内的 preview 请求。
    function waitBatchPreviewReady(api) {
        return api.waitFor(function() {
            var loading = document.querySelectorAll('.arena-card-opponents-loading');
            return loading.length === 0;
        }, 3000, 'batch preview 全部完成（grid 摘要无 loading）');
    }

    function rosterSig(roster) {
        return (roster || []).map(function(r) {
            return String(r.id || r.type) + '@' + r.level + 'x' + r.count;
        }).join(',');
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
    // 新流程：panel 开 → snapshot → batch preview 8 路 → 等 grid 摘要全到 →
    //         点 🔍 进 detail（cache 命中，无新 preview） → 点确认挑战 → enter 协议带 cardIndex
    function caseEnterSuccess(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.enterMessages = [];
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                // 进 detail 前记录 preview 消息计数 — 验证 cache 命中确实跳过新请求
                var beforeCount = host.previewMessages.length;
                document.querySelector('.arena-card-btn-detail[data-index="0"]').click();
                return api.waitFor(function() {
                    var confirmBtn = document.querySelector('.arena-detail-confirm');
                    return confirmBtn && !confirmBtn.disabled;
                }, 2000, 'detail view + confirm enabled (cache 命中)').then(function() {
                    api.assertEqual(host.previewMessages.length, beforeCount, '进 detail 时 cache 命中，不应发新 preview');
                });
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assert(rows.length >= 1, '对手行应被渲染（来自 batch cache）');
                document.querySelector('.arena-detail-confirm').click();
                return api.waitFor(function() {
                    return host.enterMessages.length > 0;
                }, 2000, 'enter message sent');
            })
            .then(function() {
                var msg = host.enterMessages[host.enterMessages.length - 1];
                api.assert(msg.cmd === 'enter', '提交消息应为 enter');
                api.assertEqual(msg.cardIndex, 0, 'detail 入场应带 cardIndex=0');
                api.assert(typeof msg.expr === 'string' && msg.expr.length > 0, 'enter 应携带 expr');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: enter-fail-money ──
    // 破产时 enter 按钮 disabled（钱不够），detail 按钮仍 enabled（看对手装备 / 攒钱再来）
    function caseEnterFailMoney(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('broke');
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return document.querySelector('.arena-card-disabled') != null;
                }, 2000, 'disabled cards rendered');
            })
            .then(function() {
                var enterBtn = document.querySelector('.arena-card-btn-enter');
                var detailBtn = document.querySelector('.arena-card-btn-detail');
                api.assert(!!enterBtn, '找不到 enter 按钮');
                api.assert(!!detailBtn, '找不到 detail 按钮');
                api.assertEqual(enterBtn.disabled, true, '破产状态下 enter 按钮应被禁用');
                api.assertEqual(detailBtn.disabled, false, '破产状态下 detail 按钮仍可点（仅 busy 时禁用）');
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
    // 等 batch（8 条） → 进 detail（cache 命中无新 preview）→ 换一批（第 9 条 preview） → 验对手仍渲
    function caseRollAgain(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                api.assertEqual(host.previewMessages.length, 8, 'batch 应发出 8 条 preview');
                document.querySelector('.arena-card-btn-detail[data-index="0"]').click();
                return api.waitFor(function() {
                    var btn = document.querySelector('.arena-detail-roll');
                    return btn && !btn.disabled;
                }, 2000, 'detail 视图就绪、roll-again enabled');
            })
            .then(function() {
                var before = host.previewMessages.length;
                document.querySelector('.arena-detail-roll').click();
                return api.waitFor(function() {
                    return host.previewMessages.length > before;
                }, 2000, 'rollAgain 触发第 9 条 preview');
            })
            .then(function() {
                api.assert(host.previewMessages.length >= 9, '换一批后总 preview 数应 >= 9（batch 8 + rollAgain 1）');
                return api.waitFor(function() {
                    var btn = document.querySelector('.arena-detail-confirm');
                    return btn && !btn.disabled;
                }, 2000, 'confirm re-enabled after rollAgain');
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assert(rows.length >= 1, '换一批后对手应重新渲染');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: preview-switch-race ──
    // 验闭包守护：detail 内 onRollAgain 飞行中切到另一卡 detail，旧 rollAgain 回包不污染新卡 detail。
    // 流程：等 batch → 进卡 0 detail（count=1）→ 点 rollAgain（发 preview 但回包未到）
    //       → 立刻 back → 立刻进卡 1 detail（count=2，cache 命中）→ 等 200ms 让卡 0 rollAgain 回包到
    //       → 验卡 1 detail 仍 2 行（_activeCardIdx === 1 ≠ 0 守住，旧回包仅写 cache 不渲 detail）
    function casePreviewSwitchRace(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                // 进卡 0 detail：cache 命中，立即渲 1 行
                document.querySelector('.arena-card-btn-detail[data-index="0"]').click();
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-opp-row');
                    var rollBtn = document.querySelector('.arena-detail-roll');
                    return rows.length === 1 && rollBtn && !rollBtn.disabled;
                }, 2000, 'card-0 detail 就绪 (count=1)');
            })
            .then(function() {
                // 点 rollAgain → 发新 preview，但回包未到（80ms mock 延迟）
                document.querySelector('.arena-detail-roll').click();
                // 立刻 back → 立刻进卡 1 detail（cache 命中，应渲 2 行）
                document.querySelector('.arena-detail-back').click();
                document.querySelector('.arena-card-btn-detail[data-index="1"]').click();
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-opp-row');
                    return rows.length === 2;
                }, 2000, 'card-1 detail 渲完 (count=2)');
            })
            .then(function() {
                // 等卡 0 的 rollAgain 回包到达（mock 80ms + buffer）
                return new Promise(function(resolve) { setTimeout(resolve, 250); });
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assertEqual(rows.length, 2, '卡 0 rollAgain 迟到回包不应污染卡 1 detail (_activeCardIdx 守护)');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: equip-tooltip ──
    // 等 batch → 进 detail（cache 命中渲对手 + 装备格） → hover 装备 → equip_tooltip 请求 + cache →
    // 再 hover 同格 → 命中 cache 不发新请求
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
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                document.querySelector('.arena-card-btn-detail[data-index="0"]').click();
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

    // ════════════════════════════════════════════════════════════════════════════
    // 新增 case：grid 增强相关（batch preview / 直入 / cache 一致性 / money disable / 失败重试）
    // ════════════════════════════════════════════════════════════════════════════

    // ── case: grid-batch-preview ──
    // panel open + snapshot 回包后，立即并发 8 路 preview；每路带 cardIndex 0..7 各一次；
    // 8 张卡 grid 摘要全部脱离 loading 态（即 _previewCache 全填）。
    function caseGridBatchPreview(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                api.assertEqual(host.previewMessages.length, 8, '应发出 8 条 preview');
                // 验 cardIndex 0..7 各一次 — 用 set 断言去重数量
                var seen = {};
                for (var i = 0; i < host.previewMessages.length; i++) {
                    var idx = host.previewMessages[i].cardIndex;
                    api.assert(typeof idx === 'number' && idx >= 0 && idx < 8, 'preview 应带合法 cardIndex（实际: ' + idx + '）');
                    seen[idx] = true;
                }
                api.assertEqual(Object.keys(seen).length, 8, '8 路 cardIndex 应覆盖 0..7 各一次');
            })
            .then(function() {
                // 验所有 grid 摘要都不为 loading 文本
                for (var i = 0; i < 8; i++) {
                    var sumEl = document.getElementById('arena-opp-summary-' + i);
                    api.assert(!!sumEl, '卡片 ' + i + ' 摘要 span 应存在');
                    api.assert(!sumEl.classList.contains('arena-card-opponents-loading'), '卡片 ' + i + ' 摘要应脱离 loading 态');
                    api.assert(sumEl.textContent.indexOf('抽取中') === -1, '卡片 ' + i + ' 摘要不应含"抽取中"');
                    api.assert(sumEl.textContent.length > 0, '卡片 ' + i + ' 摘要应有文本');
                }
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: grid-direct-enter ──
    // 不进 detail，直接点 grid "⚔ 开始挑战" → enter 协议带 cardIndex 且 detail view 仍隐藏
    function caseGridDirectEnter(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.enterMessages = [];
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                // 等 enter 按钮 enabled（snapshot 到 + cache 填）
                return api.waitFor(function() {
                    var btn = document.querySelector('.arena-card-btn-enter[data-index="0"]');
                    return btn && !btn.disabled;
                }, 2000, 'card-0 enter 按钮 enabled');
            })
            .then(function() {
                document.querySelector('.arena-card-btn-enter[data-index="0"]').click();
                return api.waitFor(function() {
                    return host.enterMessages.length > 0;
                }, 2000, 'enter message sent (grid 直入)');
            })
            .then(function() {
                var msg = host.enterMessages[host.enterMessages.length - 1];
                api.assertEqual(msg.cmd, 'enter', '消息应为 enter');
                api.assertEqual(msg.cardIndex, 0, 'grid 直入应带 cardIndex=0');
                // detail view 应仍隐藏（fast path 没有切到 detail）
                var detailEl = document.getElementById('arena-detail-view');
                api.assert(!!detailEl, 'detail view 元素应存在');
                api.assertEqual(detailEl.hidden, true, 'grid 直入路径不应切到 detail view');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: grid-cache-consistency ──
    // detail 内"换一批" → 回 grid → 摘要文本应已更新为新对手数据（同步覆盖）
    function caseGridCacheConsistency(api, host) {
        var oldSummaryText;
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                // 记录卡 0 的初始摘要文本
                oldSummaryText = document.getElementById('arena-opp-summary-0').textContent;
                api.assert(oldSummaryText && oldSummaryText.length > 0, '卡 0 应有初始摘要文本');
                // 进 detail → 换一批
                document.querySelector('.arena-card-btn-detail[data-index="0"]').click();
                return api.waitFor(function() {
                    var btn = document.querySelector('.arena-detail-roll');
                    return btn && !btn.disabled;
                }, 2000, 'detail roll 按钮就绪');
            })
            .then(function() {
                var beforeCount = host.previewMessages.length;
                document.querySelector('.arena-detail-roll').click();
                return api.waitFor(function() {
                    return host.previewMessages.length > beforeCount;
                }, 2000, 'rollAgain preview 已发出');
            })
            .then(function() {
                // 等回包到达 + 写 cache + renderCardSummary 同步 grid（80ms mock + buffer）
                return new Promise(function(resolve) { setTimeout(resolve, 200); });
            })
            .then(function() {
                // 回 grid 验摘要更新
                document.querySelector('.arena-detail-back').click();
                return api.waitFor(function() {
                    var grid = document.getElementById('arena-grid-view');
                    return grid && !grid.hidden;
                }, 2000, 'back to grid');
            })
            .then(function() {
                var newSummary = document.getElementById('arena-opp-summary-0').textContent;
                // 摘要应仍有内容（不是 loading）
                api.assert(newSummary && newSummary.indexOf('抽取中') === -1, '摘要应是新数据，不应是 loading');
                // 注意：mock 生成的对手 name 包含 cardIndex 但每次内容相同，所以 "新摘要 != 旧摘要" 不可靠。
                // 改验：摘要文本与 cache 中对手 name+lvl 一致（间接验同步）。
                var cache = host.getPreviewCache();
                var opps = cache[0];
                api.assert(opps && opps.length > 0, 'host._previewCache[0] 应有对手数据');
                // 摘要应至少含第一个对手 name
                api.assert(newSummary.indexOf(opps[0].name) >= 0, '摘要 "' + newSummary + '" 应含对手 name "' + opps[0].name + '"');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: grid-money-disable ──
    // poor fixture：高押金卡 enter 按钮 disabled、detail 按钮 enabled；低押金卡 enter 按钮 enabled
    function caseGridMoneyDisable(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('poor'); // money: 1000
                host.resetPreviewState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                // 卡 0 押金 500 → 玩家 1000 够 → enter enabled
                var card0Enter = document.querySelector('.arena-card-btn-enter[data-index="0"]');
                var card0Detail = document.querySelector('.arena-card-btn-detail[data-index="0"]');
                api.assertEqual(card0Enter.disabled, false, '卡 0（押金 500）enter 按钮应 enabled');
                api.assertEqual(card0Detail.disabled, false, '卡 0 detail 按钮应 enabled');

                // 卡 7 押金 100000 → 玩家 1000 不够 → enter disabled，detail 仍可点
                var card7Enter = document.querySelector('.arena-card-btn-enter[data-index="7"]');
                var card7Detail = document.querySelector('.arena-card-btn-detail[data-index="7"]');
                api.assertEqual(card7Enter.disabled, true, '卡 7（押金 100000）enter 按钮应 disabled');
                api.assertEqual(card7Detail.disabled, false, '卡 7 detail 按钮应 enabled（仅 busy 时禁）');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: grid-single-fail-retry ──
    // 单卡 preview 失败 → 摘要显示"加载失败 ↻" + .arena-card-opponents-error 类 + 该卡 enter 按钮仍 disabled
    // → 点击摘要触发重发 → 摘要回 loading 然后成功
    function caseGridSingleFailRetry(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                host.failNextPreviewForCard(2, 'stock_insufficient'); // 卡 2 第一次必失败
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                // 等卡 2 摘要进入 error 态（其他 7 卡正常完成）
                return api.waitFor(function() {
                    var sum = document.getElementById('arena-opp-summary-2');
                    return sum && sum.classList.contains('arena-card-opponents-error');
                }, 3000, '卡 2 摘要进入 error 态');
            })
            .then(function() {
                var sum = document.getElementById('arena-opp-summary-2');
                api.assert(sum.textContent.indexOf('↻') >= 0, '卡 2 摘要应含 ↻ 重试图标');
                api.assert(sum.textContent.indexOf('stock_insufficient') >= 0, '卡 2 摘要应含 error 文本');
                // 卡 2 enter 按钮应 disabled（hasPreview false）
                var enterBtn = document.querySelector('.arena-card-btn-enter[data-index="2"]');
                api.assertEqual(enterBtn.disabled, true, '失败卡的 enter 按钮应 disabled');
                // 其他卡（如卡 0）enter 应正常 enabled
                var card0Enter = document.querySelector('.arena-card-btn-enter[data-index="0"]');
                api.assertEqual(card0Enter.disabled, false, '其他成功卡的 enter 按钮不受影响');
            })
            .then(function() {
                // 点击 ↻ 重试（failNextPreviewForCard 已在第一次回包后清掉，这次会成功）
                var beforeCount = host.previewMessages.length;
                document.getElementById('arena-opp-summary-2').click();
                return api.waitFor(function() {
                    return host.previewMessages.length > beforeCount;
                }, 2000, '点击 ↻ 触发重发 preview');
            })
            .then(function() {
                // 等摘要回成功态
                return api.waitFor(function() {
                    var sum = document.getElementById('arena-opp-summary-2');
                    return sum && !sum.classList.contains('arena-card-opponents-error')
                                && !sum.classList.contains('arena-card-opponents-loading');
                }, 2000, '卡 2 摘要恢复成功态');
            })
            .then(function() {
                var enterBtn = document.querySelector('.arena-card-btn-enter[data-index="2"]');
                api.assertEqual(enterBtn.disabled, false, '重试成功后卡 2 enter 按钮应 enabled');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: custom-match-p1 ──
    // 定制赛 P1 仅验证赛程代码 + calibration case 摘要。
    function caseCustomMatchP1(api, host) {
        var savedRedId = '';
        var savedRedSig = '';
        var randomBlueSig = '';
        var redBeforeSwapSig = '';
        var blueBeforeSwapSig = '';
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.sentMessages = [];
                if (host.resetCustomState) host.resetCustomState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                var tab = document.querySelector('.arena-mode-tab[data-mode="custom"]');
                api.assert(!!tab, '应显示 定制赛 tab');
                tab.click();
                return api.waitFor(function() {
                    return document.querySelector('.arena-card-custom') != null;
                }, 2000, 'custom card rendered');
            })
            .then(function() {
                var cards = document.querySelectorAll('.arena-card');
                api.assertEqual(cards.length, 1, '定制赛 P1 应只渲染 1 张入口卡');
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.activeMode, 'custom', 'activeMode 应为 custom');
                api.assert(window.ArenaCustomPresetsMeta && window.ArenaCustomPresetsMeta.presetCount > 1000, '预设池应来自关卡拆解元战队，而不是少量手写样例');
                api.assert(window.ArenaCustomPresets && window.ArenaCustomPresets[0] && window.ArenaCustomPresets[0].source === 'meta-team', '第一条预设应保留 meta-team 溯源');
                api.assert(state.customMatch && state.customMatch.parsed, '赛程代码应解析成功');
                api.assertEqual(state.customMatch.parsed.calibrationCase.blueRoster.length, 4, '蓝方应为 thief-lv30x4 对照阵容');
                api.assert(state.customMatch.parsed.calibrationCase.redRoster.length > 0, '红方应为关卡拆解元战队');
                api.assert(document.getElementById('arena-custom-fee').textContent !== '--', '估算场地费应渲染');
                api.assertEqual(document.getElementById('arena-custom-editor-view').hidden, true, '入口卡内不应直接展开阵容编辑器');
                api.assert(!document.querySelector('.arena-card-custom #arena-custom-code-input'), '入口卡不应承载赛程代码输入');
                api.assert(!document.querySelector('.arena-card-custom #arena-custom-preset-select'), '入口卡不应承载预设下拉框');
                api.assert(window.ArenaUnitCatalog && window.ArenaUnitCatalog.unitCount > window.ArenaUnitCatalog.hostileCount, '单位目录应全量暴露 units.json，而不是只暴露 is_hostile');
                document.querySelector('.arena-custom-side-red .arena-custom-side-edit').click();
                return api.waitFor(function() {
                    var editor = document.getElementById('arena-custom-editor-view');
                    return editor && !editor.hidden && document.querySelectorAll('.arena-custom-unit-row').length > 0;
                }, 2000, 'custom editor rendered');
            })
            .then(function() {
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.customSelectedSide, 'red', '调整红方应把编辑目标切到红方');
                api.assertEqual(state.customEditorPage, 'side', '调整红方应进入第三级单方阵容编辑页');
                api.assert(document.querySelector('[data-custom-editor-page="config"]').hidden, '进入单方编辑页后配置总览应隐藏');
                api.assert(!document.querySelector('[data-custom-editor-page="side"]').hidden, '单方编辑页应显示');
                api.assert(!!document.querySelector('[data-custom-side="red"].arena-custom-side-target-active'), '红方添加目标按钮应进入 active 状态');
                api.assert(!!document.querySelector('#arena-custom-editor-view #arena-custom-code-input'), '赛程代码输入应迁入二级编辑页');
                api.assert(document.querySelector('#arena-custom-editor-view #arena-custom-preset-select').options.length > 1000, '二级编辑页应暴露关卡拆解预设池');
                api.assert(document.querySelectorAll('.arena-custom-unit-row').length > 0, '单位浏览器应渲染 units.json 全量单位');
                api.assert(document.querySelector('.arena-custom-unit-mark'), '单位图标占位符应渲染');
                savedRedSig = rosterSig(state.customEditor.red);
                document.querySelector('[data-custom-side-action="save"][data-side="active"]').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customSavedRosters && st.customSavedRosters.length === 1;
                }, 2000, 'red side saved');
            })
            .then(function() {
                var state = window.ArenaPanel.getState();
                savedRedId = state.customSavedRosters[0].id;
                var oldBlueSig = rosterSig(state.customEditor.blue);
                document.querySelector('[data-custom-side="blue"]').click();
                return api.waitFor(function() {
                    return window.ArenaPanel.getState().customSelectedSide === 'blue';
                }, 2000, 'switch to blue side').then(function() {
                    document.querySelector('[data-custom-side-action="random"][data-side="active"]').click();
                    return api.waitFor(function() {
                        var st = window.ArenaPanel.getState();
                        randomBlueSig = rosterSig(st.customEditor.blue);
                        return randomBlueSig && randomBlueSig !== oldBlueSig;
                    }, 2000, 'blue side random roster applied');
                });
            })
            .then(function() {
                document.querySelector('[data-custom-side-action="save"][data-side="active"]').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customSavedRosters && st.customSavedRosters.length >= 2;
                }, 2000, 'blue side saved');
            })
            .then(function() {
                document.querySelector('[data-custom-editor-action="to-config"]').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customEditorPage === 'config' && !document.querySelector('[data-custom-editor-page="config"]').hidden;
                }, 2000, 'back to custom config overview');
            })
            .then(function() {
                var state = window.ArenaPanel.getState();
                blueBeforeSwapSig = rosterSig(state.customEditor.blue);
                redBeforeSwapSig = rosterSig(state.customEditor.red);
                document.querySelector('[data-custom-action="swap-sides"]').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return rosterSig(st.customEditor.blue) === redBeforeSwapSig &&
                        rosterSig(st.customEditor.red) === blueBeforeSwapSig;
                }, 2000, 'blue/red roster swapped');
            })
            .then(function() {
                var redSelect = document.querySelector('[data-custom-saved-select="red"]');
                api.assert(!!redSelect, '红方配置卡应有读取配置下拉框');
                redSelect.value = savedRedId;
                document.querySelector('[data-custom-side-action="load"][data-side="red"]').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return rosterSig(st.customEditor.red) === savedRedSig;
                }, 2000, 'red side saved roster loaded');
            })
            .then(function() {
                document.querySelector('[data-custom-side-action="edit"][data-side="red"]').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customEditorPage === 'side' &&
                        st.customSelectedSide === 'red' &&
                        document.querySelectorAll('.arena-custom-unit-row').length > 0;
                }, 2000, 'return to red side editor after config actions');
            })
            .then(function() {
                document.querySelector('[data-custom-unit-filter="nonhostile"]').click();
                return api.waitFor(function() {
                    return document.querySelector('.arena-custom-unit-row-nonhostile') != null;
                }, 2000, 'non-hostile filter rendered');
            })
            .then(function() {
                api.assert(document.querySelector('.arena-custom-unit-filter-active').getAttribute('data-custom-unit-filter') === 'nonhostile', '非敌对过滤按钮应进入 active 状态');
                document.querySelector('[data-custom-unit-filter="all"]').click();
                return api.waitFor(function() {
                    var active = document.querySelector('.arena-custom-unit-filter-active');
                    return active && active.getAttribute('data-custom-unit-filter') === 'all';
                }, 2000, 'all filter restored');
            })
            .then(function() {
                document.querySelector('[data-custom-side="red"]').click();
                var search = document.getElementById('arena-custom-unit-search');
                search.value = '主角-男';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-custom-unit-row');
                    for (var i = 0; i < rows.length; i++) {
                        if (/非敌对/.test(rows[i].textContent || '')) return true;
                    }
                    return false;
                }, 2000, 'filtered non-hostile unit rows');
            })
            .then(function() {
                document.querySelector('.arena-custom-unit-row-nonhostile').click();
                return api.waitFor(function() {
                    var state = window.ArenaPanel.getState();
                    return state.customEditor &&
                        state.customEditor.red &&
                        state.customEditor.red.length >= 3 &&
                        state.customMatch.parsed.calibrationCase.redRoster.length >= 3;
                }, 2000, 'manual roster add reflected in match code');
            })
            .then(function() {
                var enterMessages = host.sentMessages.filter(function(m) { return m && m.cmd === 'enter'; });
                api.assertEqual(enterMessages.length, 0, 'P1 摘要不应发送正式 enter');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: custom-match-p2 ──
    // 定制赛 P2 点击开始委托后走 custom_start，关闭 webpanel；结算后由 Host 回开结果态，不走正式 arena enter。
    function caseCustomMatchP2(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.sentMessages = [];
                if (host.resetCustomState) host.resetCustomState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                var tab = document.querySelector('.arena-mode-tab[data-mode="custom"]');
                api.assert(!!tab, '应显示 定制赛 tab');
                tab.click();
                return api.waitFor(function() {
                    return document.querySelector('.arena-card-custom') != null;
                }, 2000, 'custom card rendered');
            })
            .then(function() {
                document.querySelector('.arena-custom-generate').click();
                return api.waitFor(function() {
                    var confirm = document.getElementById('arena-custom-confirm');
                    return confirm && !confirm.hidden;
                }, 2000, 'custom confirm rendered');
            })
            .then(function() {
                var earlyStart = host.sentMessages.filter(function(m) { return m && m.cmd === 'custom_start'; });
                api.assertEqual(earlyStart.length, 0, '确认前不应发送 custom_start');
                document.querySelector('[data-custom-confirm-action="start"]').click();
                return api.waitFor(function() {
                    for (var i = 0; i < host.sentMessages.length; i++) {
                        if (host.sentMessages[i] && host.sentMessages[i].cmd === 'custom_start') return true;
                    }
                    return false;
                }, 2000, 'custom_start sent');
            })
            .then(function() {
                var msg = null;
                for (var i = host.sentMessages.length - 1; i >= 0; i--) {
                    if (host.sentMessages[i] && host.sentMessages[i].cmd === 'custom_start') {
                        msg = host.sentMessages[i];
                        break;
                    }
                }
                api.assert(!!msg, '应找到 custom_start 消息');
                api.assert(msg.matchCode && msg.matchCode.indexOf('CF7ARENA:v1;mode=mvm') === 0, '应携带 canonical 赛程代码');
                api.assert(msg.calibrationCase && msg.calibrationCase.blueRoster.length === 4, '应携带 thief-lv30x4 对照阵容');
                return api.waitFor(function() {
                    for (var i = 0; i < host.sentMessages.length; i++) {
                        if (host.sentMessages[i] && host.sentMessages[i].cmd === 'close' && host.sentMessages[i].dismissReturnStack) return true;
                    }
                    return false;
                }, 2000, 'custom panel close sent');
            })
            .then(function() {
                return api.waitFor(function() {
                    var state = window.ArenaPanel.getState();
                    return state.activeMode === 'custom' &&
                        state.customResult &&
                        state.customRun &&
                        state.customRun.state === 'completed' &&
                        state.customRun.reopened === true;
                }, 3000, 'custom result reopened');
            })
            .then(function() {
                var resultView = document.getElementById('arena-custom-result-view');
                api.assert(!!resultView && !resultView.hidden, '回开后应显示独立结算页');
                api.assert(/蓝方胜|红方胜|平局|超时|委托/.test(resultView.textContent), '结算页应显示胜负结果');
                var backBtn = resultView.querySelector('[data-custom-result-action="back"]');
                api.assert(!!backBtn, '结算页应提供返回基地按钮');
                api.assert(/返回基地/.test(resultView.textContent), '结算页退出文案应指向返回基地');
                chrome.webview.__dispatch({ type: 'panel_esc' });
                return api.waitFor(function() {
                    for (var i = 0; i < host.sentMessages.length; i++) {
                        var msg = host.sentMessages[i];
                        if (msg && msg.cmd === 'close' && msg.dismissReturnStack && msg.returnBase) return true;
                    }
                    return false;
                }, 2000, 'custom result ESC/backdrop close returns base');
            })
            .then(function() {
                var startCloses = host.sentMessages.filter(function(m) {
                    return m && m.cmd === 'close' && m.dismissReturnStack && !m.returnBase;
                });
                api.assert(startCloses.length >= 1, 'custom_start 后的关闭不应请求返回基地');
                var statusMessages = host.sentMessages.filter(function(m) { return m && m.cmd === 'custom_status'; });
                api.assertEqual(statusMessages.length, 0, 'closePanel 主路径不应继续轮询 custom_status');
                var enterMessages = host.sentMessages.filter(function(m) { return m && m.cmd === 'enter'; });
                api.assertEqual(enterMessages.length, 0, 'P2 定制赛不应发送正式 enter');
                api.assert(host._customResultOpens >= 1, 'Host 应回开 custom_result');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: custom-match-pve ──
    // 玩家 vs 怪物复用标准竞技场 enter，不走后台 ArenaCalibrationTask/custom_start。
    function caseCustomMatchPve(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.sentMessages = [];
                if (host.resetCustomState) host.resetCustomState();
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                var tab = document.querySelector('.arena-mode-tab[data-mode="custom"]');
                api.assert(!!tab, '应显示 定制赛 tab');
                tab.click();
                return api.waitFor(function() {
                    return document.querySelector('.arena-card-custom') != null;
                }, 2000, 'custom card rendered');
            })
            .then(function() {
                document.querySelector('.arena-custom-edit').click();
                return api.waitFor(function() {
                    return !document.getElementById('arena-custom-editor-view').hidden;
                }, 2000, 'custom editor opened');
            })
            .then(function() {
                document.querySelector('[data-custom-mode="pve"]').click();
                return api.waitFor(function() {
                    var state = window.ArenaPanel.getState();
                    return state.customEditor &&
                        state.customEditor.mode === 'pve' &&
                        state.customMatch &&
                        state.customMatch.parsed &&
                        state.customMatch.parsed.mode === 'pve';
                }, 2000, 'pve mode parsed');
            })
            .then(function() {
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.customSelectedSide, 'red', 'PVE 编辑目标应固定为怪物侧');
                var playerCard = document.getElementById('arena-custom-config-blue');
                api.assert(playerCard && !playerCard.hidden, 'PVE 配置页应显示玩家当前存档卡');
                api.assert(/当前存档/.test(playerCard.textContent || ''), 'PVE 玩家卡应标记当前存档');
                api.assert((playerCard.textContent || '').indexOf('兵种') < 0, 'PVE 玩家卡不应显示怪物组合');
                api.assertEqual(playerCard.querySelectorAll('[data-custom-side-action], [data-custom-saved-select]').length, 0, 'PVE 玩家卡不应提供阵容读写控件');
                api.assert(document.querySelector('[data-custom-action="swap-sides"]').hidden, 'PVE 不应显示交换红蓝');
                document.querySelector('[data-custom-editor-action="done"]').click();
                return api.waitFor(function() {
                    return document.getElementById('arena-grid-view') &&
                        !document.getElementById('arena-grid-view').hidden &&
                        document.querySelector('.arena-card-custom') != null;
                }, 2000, 'back to custom card');
            })
            .then(function() {
                document.querySelector('.arena-custom-generate').click();
                return api.waitFor(function() {
                    var confirm = document.getElementById('arena-custom-confirm');
                    return confirm && !confirm.hidden && /确认挑战|开始挑战/.test(confirm.textContent || '');
                }, 2000, 'pve confirm rendered');
            })
            .then(function() {
                var earlyStart = host.sentMessages.filter(function(m) { return m && m.cmd === 'custom_start'; });
                api.assertEqual(earlyStart.length, 0, 'PVE 确认前不应发送 custom_start');
                document.querySelector('[data-custom-confirm-action="start"]').click();
                return api.waitFor(function() {
                    for (var i = 0; i < host.sentMessages.length; i++) {
                        if (host.sentMessages[i] && host.sentMessages[i].cmd === 'enter') return true;
                    }
                    return false;
                }, 2000, 'pve enter sent');
            })
            .then(function() {
                var enterMsg = null;
                for (var i = host.sentMessages.length - 1; i >= 0; i--) {
                    if (host.sentMessages[i] && host.sentMessages[i].cmd === 'enter') {
                        enterMsg = host.sentMessages[i];
                        break;
                    }
                }
                api.assert(!!enterMsg, '应找到 PVE enter 消息');
                api.assertEqual(enterMsg.mode, 'custom_pve', 'PVE enter 应标记 custom_pve');
                api.assertEqual(enterMsg.deposit, 0, 'PVE enter 押金应为 0');
                api.assertEqual(enterMsg.reward, 0, 'PVE enter 奖金应为 0');
                api.assert(enterMsg.matchCode && enterMsg.matchCode.indexOf('CF7ARENA:v1;mode=pve') === 0, 'PVE enter 应携带 canonical 赛程代码');
                api.assert(enterMsg.roster && enterMsg.roster.length > 0, 'PVE enter 应携带展开后的怪物 roster');
                var customStarts = host.sentMessages.filter(function(m) { return m && m.cmd === 'custom_start'; });
                api.assertEqual(customStarts.length, 0, 'PVE 不应发送后台 custom_start');
                return api.waitFor(function() {
                    for (var j = 0; j < host.sentMessages.length; j++) {
                        if (host.sentMessages[j] && host.sentMessages[j].cmd === 'close' && host.sentMessages[j].dismissReturnStack) return true;
                    }
                    return false;
                }, 2000, 'pve panel close sent');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    return {
        runSuite: runSuite
    };
})();
