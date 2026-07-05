/**
 * Arena Panel QA Suite
 *
 * 测试覆盖（22 项）：
 *   - panel-open: Panel 能正确打开并渲染社群档位卡片 + 死线警报隐藏卡
 *   - snapshot-render: snapshot 到达后金钱显示正确，卡片状态正确
 *   - enter-success: 通过 detail 路径入场（点 🔍 → 等 cache 命中 → 点确认挑战）
 *   - enter-fail-money: 金钱不足时 enter 按钮 disabled，detail 按钮仍可点
 *   - close-btn: 关闭按钮发送 close 命令
 *   - esc-close: ESC 触发关闭
 *   - force-close: force_close 正确处理
 *   - card-count: 确认 10 张公开标准卡 + 2 张死线警报隐藏卡都存在且数据正确
 *   - hidden-mixed-enter: 死线警报隐藏卡本地混编 cache 后入场携带 roster，不走 merc preview
 *   - standard-mixed-card: 公开标准卡固定 mixed 分支可抽出佣兵模板 + 怪物组
 *   - roll-again: "换一批"按钮重发 preview 并刷新对手渲染
 *   - preview-switch-race: 用 onRollAgain 在 detail 飞行中 → back → 进另一卡，验旧回包不污染新卡
 *   - equip-tooltip: hover 装备发送 equip_tooltip，回包后 cache，第二次 hover 不再发请求
 *   - grid-batch-preview: panel open 后佣兵公开卡并发 AS2 preview、roster 卡本地 cache，每张卡 grid 摘要都脱离 loading
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
        { id: 'panel-open',           title: 'Panel 打开并渲染标准卡片' },
        { id: 'snapshot-render',      title: 'Snapshot 更新 UI 状态' },
        { id: 'enter-success',        title: 'Enter 成功链路（detail 路径）' },
        { id: 'enter-fail-money',     title: '金钱不足时禁用挑战' },
        { id: 'close-btn',            title: '关闭按钮' },
        { id: 'esc-close',            title: 'ESC 关闭' },
        { id: 'force-close',          title: 'Force Close' },
        { id: 'card-count',           title: '卡片数据完整性' },
        { id: 'hidden-mixed-enter',   title: '死线警报隐藏卡混编 roster 入场' },
        { id: 'standard-mixed-card',  title: '公开标准卡固定 mixed' },
        { id: 'roll-again',           title: '换一批重发 preview' },
        { id: 'reroll-all',           title: '全部重抽重发公开卡 preview' },
        { id: 'preview-switch-race',  title: '迟到 preview 回包被丢弃' },
        { id: 'equip-tooltip',        title: '装备 hover 发起 tooltip 请求 + cache' },
        { id: 'grid-batch-preview',   title: 'Panel 打开后公开卡 preview + 隐藏混编 cache' },
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
            case 'hidden-mixed-enter':      return caseHiddenMixedEnter(api, host);
            case 'standard-mixed-card':     return caseStandardMixedCard(api, host);
            case 'roll-again':              return caseRollAgain(api, host);
            case 'reroll-all':              return caseRerollAll(api, host);
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

    // ── 公共辅助：等 batch preview 全部完成（snapshot 回包后立即并发当前卡片集 → 全部成功回包） ──
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
            var params = r.parameters || r.Parameters || r['参数'];
            return String(r.id || r.type) + '@' + r.level + 'x' + r.count + (params ? '~' + JSON.stringify(params) : '');
        }).join(',');
    }

    function rosterTotal(roster) {
        var total = 0;
        roster = roster || [];
        for (var i = 0; i < roster.length; i++) total += Number(roster[i].count) || 0;
        return total;
    }

    function standardPreviewMessageCount(cards) {
        var count = 0;
        cards = cards || [];
        for (var i = 0; i < cards.length; i++) {
            if (!cards[i].isHiddenChallenge && !cards[i].isCustom && cards[i].standardRole !== 'monster' && cards[i].standardRole !== 'mixed') count++;
        }
        return count;
    }

    function standardRoleCounts(cards) {
        var counts = { merc: 0, monster: 0, mixed: 0 };
        cards = cards || [];
        for (var i = 0; i < 10 && i < cards.length; i++) {
            var role = cards[i].standardRole || 'merc';
            counts[role] = (counts[role] || 0) + 1;
        }
        return counts;
    }

    function findPublicCardIndexByRole(cards, role, nth) {
        cards = cards || [];
        nth = nth || 1;
        var seen = 0;
        for (var i = 0; i < 10 && i < cards.length; i++) {
            if ((cards[i].standardRole || 'merc') === role) {
                seen++;
                if (seen === nth) return i;
            }
        }
        return -1;
    }

    function assertMixedRoster(api, opponents, label) {
        var humanoid = false;
        var nonhuman = false;
        opponents = opponents || [];
        for (var i = 0; i < opponents.length; i++) {
            if (opponents[i].rosterKind === 'humanoid') humanoid = true;
            if (opponents[i].rosterKind === 'nonhuman') nonhuman = true;
        }
        api.assert(humanoid && nonhuman, label + ' 应同时包含佣兵模板与怪物组 roster 单位');
    }

    function assertMercenaryMixedSquad(api, squad, label) {
        api.assert(squad && squad.source === 'mercenary', label + ' 应优先使用 mercenaries.json 普通佣兵做人形侧');
        assertMixedRoster(api, squad.opponents, label);
        var counts = countMixedRosterKinds(squad.opponents);
        api.assert(counts.merc > 0, label + ' 的人形侧应携带 mercId');
    }

    function countMixedRosterKinds(opponents) {
        var counts = { humanoid: 0, nonhuman: 0, merc: 0 };
        opponents = opponents || [];
        for (var i = 0; i < opponents.length; i++) {
            if (opponents[i].rosterKind === 'humanoid') {
                counts.humanoid++;
                if (opponents[i].mercId != null) counts.merc++;
            }
            if (opponents[i].rosterKind === 'nonhuman') counts.nonhuman++;
        }
        return counts;
    }

    function assertHiddenMixedRatio(api, squad, card, label, options) {
        options = options || {};
        var total = Math.max(2, Math.min(4, Math.round(Number(card.opponentCount) || 2)));
        var expectedHumanoid = Math.max(1, Math.ceil(total / 2));
        var expectedNonhuman = Math.max(1, total - expectedHumanoid);
        var counts = countMixedRosterKinds(squad && squad.opponents);
        api.assertEqual(counts.merc, expectedHumanoid,
            label + ' 应让普通佣兵承担主力配比');
        api.assert(counts.nonhuman >= expectedNonhuman,
            label + ' 的非人形怪数量不应小于怪物槽位');
        api.assert(counts.merc + counts.nonhuman <= expectedHumanoid + expectedNonhuman * 8,
            label + ' 的真实刷怪数应受每组上限保护');
        if (squad && squad.monsterSource === 'meta-team') {
            var groupCounts = countMonsterGroups(squad.opponents);
            api.assert(groupCounts.groups >= expectedNonhuman,
                label + ' 的怪物槽位应对应多个怪物组');
        }
        if (options.requireExpandedMonsterGroup) {
            api.assert(squad && squad.monsterSource === 'meta-team',
                label + ' 的怪物侧应优先来自关卡拆解小队');
            api.assert(counts.nonhuman > expectedNonhuman,
                label + ' 的怪物槽位应展开为多单位怪物组');
        }
    }

    function assertMetaTeamSquad(api, squad, label) {
        api.assert(squad && squad.source === 'meta-team', label + ' 应优先使用关卡拆解 meta-team');
        api.assert(squad.opponents && squad.opponents.length >= (squad.equivalentCount || 1),
            label + ' 的真实组合人数不应小于佣兵等效人数');
    }

    function countMonsterGroups(opponents) {
        var seen = {};
        var groups = 0;
        var nonhuman = 0;
        opponents = opponents || [];
        for (var i = 0; i < opponents.length; i++) {
            if (opponents[i].rosterKind !== 'nonhuman') continue;
            nonhuman++;
            var gid = opponents[i].sourceGroupId || '';
            if (gid && !seen[gid]) {
                seen[gid] = true;
                groups++;
            }
        }
        return { groups: groups, nonhuman: nonhuman };
    }

    function assertStandardMonsterGroupSquad(api, squad, card, label) {
        assertMetaTeamSquad(api, squad, label);
        var expectedGroups = Math.max(1, Math.min(4, Math.round(Number(card.opponentCount) || 1)));
        var counts = countMonsterGroups(squad.opponents);
        api.assertEqual(squad.equivalentCount, expectedGroups,
            label + ' 的等效人数应等于卡片对手数');
        api.assert(counts.groups >= expectedGroups,
            label + ' 应按对手数展开为多个怪物组');
        api.assert(counts.nonhuman > expectedGroups,
            label + ' 应让怪物组展开为怪海实体');
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
                api.assert(cards.length >= 10, '卡片数量应至少包含 10 个公开档位');
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
    // 新流程：panel 开 → snapshot → batch preview 全卡 → 等 grid 摘要全到 →
    //         点 🔍 进 detail（cache 命中，无新 preview） → 点确认挑战 → enter 协议带 cardIndex
    function caseEnterSuccess(api, host) {
        var cardIdx = 0;
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
                var cards = window.ArenaPanel.getCards();
                cardIdx = findPublicCardIndexByRole(cards, 'merc', 1);
                api.assert(cardIdx >= 0, '应能找到佣兵公开卡');
                var beforeCount = host.previewMessages.length;
                document.querySelector('.arena-card-btn-detail[data-index="' + cardIdx + '"]').click();
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
                api.assertEqual(msg.cardIndex, cardIdx, 'detail 入场应带所选 cardIndex');
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
    // 等 batch → 进 detail（cache 命中无新 preview）→ 换一批（额外 1 条 preview） → 验对手仍渲
    function caseRollAgain(api, host) {
        var cardIdx = 0;
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
                var cards = window.ArenaPanel.getCards();
                var previewCount = standardPreviewMessageCount(cards);
                api.assertEqual(host.previewMessages.length, previewCount, 'batch 应按佣兵公开卡数发出 AS2 preview');
                cardIdx = findPublicCardIndexByRole(cards, 'merc', 1);
                api.assert(cardIdx >= 0, '应能找到佣兵公开卡');
                document.querySelector('.arena-card-btn-detail[data-index="' + cardIdx + '"]').click();
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
                }, 2000, 'rollAgain 触发额外 preview');
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                api.assert(host.previewMessages.length >= standardPreviewMessageCount(cards) + 1, '换一批后总 preview 数应 >= 佣兵公开卡数 + 1');
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
    // 流程：等 batch → 进卡 0 detail → 点 rollAgain（发 preview 但回包未到）
    //       → 立刻 back → 立刻进卡 1 detail（cache 命中）→ 等 200ms 让卡 0 rollAgain 回包到
    //       → 验卡 1 detail 仍是卡 1 的人数（_activeCardIdx === 1 ≠ 0 守住，旧回包仅写 cache 不渲 detail）
    function casePreviewSwitchRace(api, host) {
        var card0Idx = 0, card1Idx = 1;
        var card0Count = 1, card1Count = 1;
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
                var cards = window.ArenaPanel.getCards();
                card0Idx = findPublicCardIndexByRole(cards, 'merc', 1);
                card1Idx = findPublicCardIndexByRole(cards, 'merc', 2);
                api.assert(card0Idx >= 0 && card1Idx >= 0, '应能找到两张佣兵公开卡');
                card0Count = cards[card0Idx].opponentCount;
                card1Count = cards[card1Idx].opponentCount;
                // 进第一张佣兵卡 detail：cache 命中，立即渲对应人数
                document.querySelector('.arena-card-btn-detail[data-index="' + card0Idx + '"]').click();
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-opp-row');
                    var rollBtn = document.querySelector('.arena-detail-roll');
                    return rows.length === card0Count && rollBtn && !rollBtn.disabled;
                }, 2000, 'card-0 detail 就绪');
            })
            .then(function() {
                // 点 rollAgain → 发新 preview，但回包未到（80ms mock 延迟）
                document.querySelector('.arena-detail-roll').click();
                // 立刻 back → 立刻进第二张佣兵卡 detail（cache 命中，应渲对应人数）
                document.querySelector('.arena-detail-back').click();
                document.querySelector('.arena-card-btn-detail[data-index="' + card1Idx + '"]').click();
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-opp-row');
                    return rows.length === card1Count;
                }, 2000, 'card-1 detail 渲完');
            })
            .then(function() {
                // 等卡 0 的 rollAgain 回包到达（mock 80ms + buffer）
                return new Promise(function(resolve) { setTimeout(resolve, 250); });
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assertEqual(rows.length, card1Count, '第一张佣兵卡 rollAgain 迟到回包不应污染第二张佣兵卡 detail (_activeCardIdx 守护)');
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
                var cards = window.ArenaPanel.getCards();
                var cardIdx = findPublicCardIndexByRole(cards, 'merc', 1);
                api.assert(cardIdx >= 0, '应能找到佣兵公开卡');
                document.querySelector('.arena-card-btn-detail[data-index="' + cardIdx + '"]').click();
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
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                var cards = window.ArenaPanel ? window.ArenaPanel.getCards() : null;
                api.assert(!!cards, 'ArenaPanel.getCards 应返回数据');
                api.assertEqual(cards.length, 12, 'harness 标准模式应有 10 张公开卡 + 2 张隐藏警报卡');
                var hidden = cards.filter(function(c) { return !!c.isHiddenChallenge; });
                api.assertEqual(hidden.length, 2, '应有 2 张隐藏警报卡');
                var roleCounts = standardRoleCounts(cards);
                api.assertEqual(roleCounts.merc, 7, '公开标准卡应固定 7 张佣兵卡');
                api.assertEqual(roleCounts.monster, 2, '公开标准卡应固定 2 张怪物组卡');
                api.assertEqual(roleCounts.mixed, 1, '公开标准卡应固定 1 张 mixed 卡');
                for (var i = 0; i < 10; i++) {
                    api.assert(!cards[i].isHiddenChallenge, '前 10 张应为公开标准档位');
                    api.assert(cards[i].countMin <= cards[i].opponentCount && cards[i].opponentCount <= cards[i].countMax,
                        '公开卡 ' + i + ' 的人数应在随机范围内');
                    api.assert(cards[i].opponentCount <= 4, '公开卡 ' + i + ' 的人数不应超过 4');
                }
                for (var h = 0; h < hidden.length; h++) {
                    api.assert(hidden[h].economyMultiplier > 1, '隐藏卡应有经济倍率补偿');
                    api.assert(hidden[h].opponentCount <= 4, '隐藏卡佣兵等效人数不应超过 4');
                }
                api.assert(hidden[0].opponentCount >= 2 && hidden[0].opponentCount <= 3,
                    '死线警报 I 为满足混编实际应限定在 2-3 人');
                api.assertEqual(hidden[0].hiddenLabel, '死线警报 I', '隐藏卡 I 标签应为死线警报');
                api.assertEqual(hidden[1].opponentCount, 4, '死线警报 II 应固定 4 人');
                api.assertEqual(hidden[1].hiddenLabel, '死线警报 II', '隐藏卡 II 标签应为死线警报');
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.cardKind[10], 'mixed', '死线警报 I 应走本地混编 roster');
                api.assertEqual(state.cardKind[11], 'mixed', '死线警报 II 应走本地混编 roster');
                assertMercenaryMixedSquad(api, state.monsterSquad[10], '死线警报 I');
                assertMercenaryMixedSquad(api, state.monsterSquad[11], '死线警报 II');
                assertHiddenMixedRatio(api, state.monsterSquad[10], cards[10], '死线警报 I');
                assertHiddenMixedRatio(api, state.monsterSquad[11], cards[11], '死线警报 II');
                var totalDeposit = cards.reduce(function(s, c) { return s + c.deposit; }, 0);
                var totalReward = cards.reduce(function(s, c) { return s + c.reward; }, 0);
                api.assert(totalDeposit > 0, '押金总和应大于 0');
                api.assert(totalReward > 0, '奖金总和应大于 0');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: hidden-mixed-enter ──
    function caseHiddenMixedEnter(api, host) {
        var hiddenIdx = 11;
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
                var cards = window.ArenaPanel.getCards();
                var card = cards[hiddenIdx];
                api.assert(card && card.isHiddenChallenge, 'card 11 应为隐藏警报卡');
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.cardKind[hiddenIdx], 'mixed', '隐藏卡应为 mixed roster');
                assertMercenaryMixedSquad(api, state.monsterSquad[hiddenIdx], '隐藏警报卡');
                assertHiddenMixedRatio(api, state.monsterSquad[hiddenIdx], card, '隐藏警报卡', { requireExpandedMonsterGroup: true });
                var detailBtn = document.querySelector('.arena-card-btn-detail[data-index="' + hiddenIdx + '"]');
                api.assert(detailBtn && detailBtn.disabled, '隐藏卡 detail 按钮应禁用');
                var enterBtn = document.querySelector('.arena-card-btn-enter[data-index="' + hiddenIdx + '"]');
                api.assert(enterBtn && !enterBtn.disabled, '隐藏卡混编 cache 成功后 enter 应可用');
                enterBtn.click();
                return api.waitFor(function() {
                    return host.enterMessages.length > 0;
                }, 2000, 'hidden enter message sent');
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                var msg = host.enterMessages[host.enterMessages.length - 1];
                api.assertEqual(msg.cmd, 'enter', '消息应为 enter');
                api.assertEqual(msg.cardIndex, hiddenIdx, '隐藏卡入场应带 cardIndex');
                api.assert(msg.roster && msg.roster.length >= cards[hiddenIdx].opponentCount,
                    '隐藏卡入场应携带不小于佣兵等效人数的真实组合 roster');
                var hasMercRoster = false;
                for (var i = 0; i < msg.roster.length; i++) {
                    if (msg.roster[i].kind === 'merc' && msg.roster[i].mercId != null) hasMercRoster = true;
                    else api.assert(/^兵种/.test(String(msg.roster[i].type || '')), '非佣兵 roster 条目应携带兵种 type');
                }
                api.assert(hasMercRoster, '隐藏卡入场 roster 应携带 mercId 佣兵条目');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: standard-mixed-card ──
    function caseStandardMixedCard(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.setKnownEnemies([
                    '敌人-终结者T800',
                    '敌人-玩具机器人',
                    '敌人-诺艾尔',
                    '敌人-普通改造僵尸',
                    '敌人-重型改造僵尸',
                    '敌人-普通爆炸僵尸',
                    '敌人-兽化改造僵尸',
                    '敌人-方舟卫士',
                    '敌人-方舟无人机',
                    '敌人-渗透者',
                    '主角-男',
                    '主角-尾上世莉架'
                ]);
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
                var state = window.ArenaPanel.getState();
                var cards = window.ArenaPanel.getCards();
                var roleCounts = standardRoleCounts(cards);
                api.assertEqual(roleCounts.mixed, 1, '公开标准卡应有且仅有 1 张 mixed 角色卡');
                api.assertEqual(roleCounts.monster, 2, '公开标准卡应有且仅有 2 张怪物组角色卡');
                var mixedIdx = -1;
                var monsterChecked = 0;
                for (var i = 0; i < 10; i++) {
                    if (state.cardKind[i] === 'mixed') { mixedIdx = i; break; }
                }
                for (var m = 0; m < 10; m++) {
                    if (cards[m].standardRole !== 'monster') continue;
                    api.assertEqual(state.cardKind[m], 'monster', '公开标准怪物组卡应走本地 monster roster');
                    assertStandardMonsterGroupSquad(api, state.monsterSquad[m], cards[m], '公开标准怪物组卡 ' + m);
                    monsterChecked++;
                }
                api.assertEqual(monsterChecked, 2, '应检查 2 张公开标准怪物组卡');
                api.assert(mixedIdx >= 0, '公开标准卡应至少抽出一张 mixed');
                api.assertEqual(cards[mixedIdx].standardRole, 'mixed', '运行态 mixed 应来自卡片固定 mixed 角色');
                var squad = state.monsterSquad[mixedIdx];
                assertMercenaryMixedSquad(api, squad, '公开标准 mixed 卡');
                var mixedTotal = Math.max(2, Math.min(4, Math.round(Number(cards[mixedIdx].opponentCount) || 2)));
                var expectedMixedGroups = Math.max(1, mixedTotal - 1);
                var mixedGroupCounts = countMonsterGroups(squad.opponents);
                api.assert(mixedGroupCounts.groups >= expectedMixedGroups,
                    '公开 mixed 卡的怪物槽位应展开为多个怪物组');
                api.assert(mixedGroupCounts.nonhuman > expectedMixedGroups,
                    '公开 mixed 卡的怪物组应展开为怪海实体');
                var hasPlayerTemplate = false;
                for (var j = 0; j < squad.opponents.length; j++) {
                    if (squad.opponents[j].rosterKind === 'humanoid' &&
                        squad.opponents[j].mercId != null &&
                        /主角/.test(String(squad.opponents[j].spritename || ''))) {
                        hasPlayerTemplate = true;
                    }
                }
                api.assert(hasPlayerTemplate, '公开 mixed 卡的人形侧应为 mercenaries.json 佣兵单位');
                var detailBtn = document.querySelector('.arena-card-btn-detail[data-index="' + mixedIdx + '"]');
                api.assert(detailBtn && !detailBtn.disabled, '公开 mixed 卡 detail 按钮应可用');
                detailBtn.click();
                return api.waitFor(function() {
                    var detail = document.getElementById('arena-detail-view');
                    var meta = document.getElementById('arena-detail-meta');
                    var brief = document.querySelector('.arena-opp-roster-brief');
                    return detail && !detail.hidden &&
                        meta && /实体/.test(meta.textContent || '') &&
                        brief && /实战实体/.test(brief.textContent || '');
                }, 2000, 'mixed detail should show equivalent/entity roster semantics');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) {
                return { pass: false, detail: String(e.message || e) };
            });
    }

    // ── case: reroll-all ──
    function caseRerollAll(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                for (var fp = 0; fp < 10; fp++) host.failNextPreviewForCard(fp, 'stock_insufficient');
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                var expectedPreviewCount = standardPreviewMessageCount(cards);
                var before = host.previewMessages.length;
                var btn = document.getElementById('arena-reroll-all');
                api.assert(!!btn && !btn.disabled && !btn.hidden, '全部重抽按钮应可用');
                btn.click();
                return api.waitFor(function() {
                    return host.previewMessages.length >= before + expectedPreviewCount;
                }, 3000, '全部重抽应重发公开卡 AS2 preview');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 新增 case：grid 增强相关（batch preview / 直入 / cache 一致性 / money disable / 失败重试）
    // ════════════════════════════════════════════════════════════════════════════

    // ── case: grid-batch-preview ──
    // panel open + snapshot 回包后，公开卡立即并发 AS2 preview；隐藏混编卡本地抽 roster cache。
    // 全部 card grid 摘要脱离 loading 态（成功 cache 或失败态均不再 loading）。
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
                var cards = window.ArenaPanel.getCards();
                var previewCount = standardPreviewMessageCount(cards);
                api.assertEqual(host.previewMessages.length, previewCount, '应按佣兵公开卡数发出 AS2 preview');
                // 验 cardIndex 全覆盖 — 用 set 断言去重数量
                var seen = {};
                for (var i = 0; i < host.previewMessages.length; i++) {
                    var idx = host.previewMessages[i].cardIndex;
                    api.assert(typeof idx === 'number' && idx >= 0 && idx < cards.length, 'preview 应带合法 cardIndex（实际: ' + idx + '）');
                    api.assert((cards[idx].standardRole || 'merc') === 'merc', '只有佣兵公开卡应发 AS2 preview');
                    seen[idx] = true;
                }
                api.assertEqual(Object.keys(seen).length, previewCount, 'cardIndex 应覆盖全部佣兵公开卡各一次');
                for (var p = 0; p < 10; p++) {
                    if ((cards[p].standardRole || 'merc') === 'merc') {
                        api.assert(seen[p] === true, '佣兵公开卡 ' + p + ' 应发出 AS2 preview');
                    }
                }
            })
            .then(function() {
                // 验所有 grid 摘要都不为 loading 文本
                var cards = window.ArenaPanel.getCards();
                for (var i = 0; i < cards.length; i++) {
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
        var cardIdx = 0;
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
                var cards = window.ArenaPanel.getCards();
                cardIdx = findPublicCardIndexByRole(cards, 'merc', 1);
                api.assert(cardIdx >= 0, '应能找到佣兵公开卡');
                // 记录佣兵卡的初始摘要文本
                oldSummaryText = document.getElementById('arena-opp-summary-' + cardIdx).textContent;
                api.assert(oldSummaryText && oldSummaryText.length > 0, '佣兵卡应有初始摘要文本');
                // 进 detail → 换一批
                document.querySelector('.arena-card-btn-detail[data-index="' + cardIdx + '"]').click();
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
                var newSummary = document.getElementById('arena-opp-summary-' + cardIdx).textContent;
                // 摘要应仍有内容（不是 loading）
                api.assert(newSummary && newSummary.indexOf('抽取中') === -1, '摘要应是新数据，不应是 loading');
                // 注意：mock 生成的对手 name 包含 cardIndex 但每次内容相同，所以 "新摘要 != 旧摘要" 不可靠。
                // 改验：摘要文本与 cache 中对手 name+lvl 一致（间接验同步）。
                var cache = host.getPreviewCache();
                var opps = cache[cardIdx];
                api.assert(opps && opps.length > 0, 'host._previewCache[cardIdx] 应有对手数据');
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

                // 公开最高档押金显著高于 1000 → enter disabled，detail 仍可点
                var highIdx = 9;
                var highEnter = document.querySelector('.arena-card-btn-enter[data-index="' + highIdx + '"]');
                var highDetail = document.querySelector('.arena-card-btn-detail[data-index="' + highIdx + '"]');
                api.assertEqual(highEnter.disabled, true, '公开最高档 enter 按钮应 disabled');
                api.assertEqual(highDetail.disabled, false, '公开最高档 detail 按钮应 enabled（仅 busy 时禁）');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: grid-single-fail-retry ──
    // 单卡 preview 失败 → 摘要显示"加载失败 ↻" + .arena-card-opponents-error 类 + 该卡 enter 按钮仍 disabled
    // → 点击摘要触发重发 → 摘要回 loading 然后成功
    function caseGridSingleFailRetry(api, host) {
        var failIdx = 0;
        var okIdx = 0;
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
                // 等至少一张佣兵卡摘要进入 error 态
                return api.waitFor(function() {
                    var cards = window.ArenaPanel.getCards();
                    for (var i = 0; i < 10; i++) {
                        if ((cards[i].standardRole || 'merc') !== 'merc') continue;
                        var sum = document.getElementById('arena-opp-summary-' + i);
                        if (sum && sum.classList.contains('arena-card-opponents-error')) {
                            failIdx = i;
                            okIdx = findPublicCardIndexByRole(cards, 'monster', 1);
                            return true;
                        }
                    }
                    return false;
                }, 3000, '失败卡摘要进入 error 态');
            })
            .then(function() {
                var sum = document.getElementById('arena-opp-summary-' + failIdx);
                api.assert(sum.textContent.indexOf('↻') >= 0, '失败卡摘要应含 ↻ 重试图标');
                api.assert(sum.textContent.indexOf('stock_insufficient') >= 0, '失败卡摘要应含 error 文本');
                // 失败卡 enter 按钮应 disabled（hasPreview false）
                var enterBtn = document.querySelector('.arena-card-btn-enter[data-index="' + failIdx + '"]');
                api.assertEqual(enterBtn.disabled, true, '失败卡的 enter 按钮应 disabled');
                // 其他本地 roster 卡 enter 应正常 enabled
                var card0Enter = document.querySelector('.arena-card-btn-enter[data-index="' + okIdx + '"]');
                api.assertEqual(card0Enter.disabled, false, '其他成功卡的 enter 按钮不受影响');
            })
            .then(function() {
                // 点击 ↻ 重试（failNextPreviewForCard 已在第一次回包后清掉，这次会成功）
                var beforeCount = host.previewMessages.length;
                document.getElementById('arena-opp-summary-' + failIdx).click();
                return api.waitFor(function() {
                    return host.previewMessages.length > beforeCount;
                }, 2000, '点击 ↻ 触发重发 preview');
            })
            .then(function() {
                // 等摘要回成功态
                return api.waitFor(function() {
                    var sum = document.getElementById('arena-opp-summary-' + failIdx);
                    return sum && !sum.classList.contains('arena-card-opponents-error')
                                && !sum.classList.contains('arena-card-opponents-loading');
                }, 2000, '失败卡摘要恢复成功态');
            })
            .then(function() {
                var enterBtn = document.querySelector('.arena-card-btn-enter[data-index="' + failIdx + '"]');
                api.assertEqual(enterBtn.disabled, false, '重试成功后失败卡 enter 按钮应 enabled');
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
                api.assert(/实时解析 OK/.test(document.getElementById('arena-custom-code-status').textContent || ''), '赛程代码状态应显示实时解析 OK');
                api.assertEqual(document.getElementById('arena-custom-editor-view').hidden, true, '入口卡内不应直接展开阵容编辑器');
                api.assert(!document.querySelector('.arena-card-custom #arena-custom-code-input'), '入口卡不应承载赛程代码输入');
                api.assert(!document.querySelector('.arena-card-custom #arena-custom-preset-select'), '入口卡不应承载预设下拉框');
                api.assert(window.ArenaUnitCatalog && window.ArenaUnitCatalog.unitCount > window.ArenaUnitCatalog.hostileCount, '单位目录应全量暴露 units.json，而不是只暴露 is_hostile');
                api.assert(window.ArenaUnitParameterPresetsMeta && window.ArenaUnitParameterPresetsMeta.presetCount > 200, '关卡参数预设表应从 Enemy.Parameters 派生');
                document.querySelector('.arena-custom-side-red .arena-custom-side-edit').click();
                return api.waitFor(function() {
                    var editor = document.getElementById('arena-custom-editor-view');
                    return editor && !editor.hidden && document.querySelectorAll('.arena-custom-unit-group').length > 0;
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
                var presetStyle = getComputedStyle(document.querySelector('#arena-custom-editor-view #arena-custom-preset-select'));
                var searchStyle = getComputedStyle(document.getElementById('arena-custom-unit-search'));
                api.assert(/none/.test(String(presetStyle.appearance || presetStyle.webkitAppearance || '')), '测试场预设下拉框应关闭浏览器原生 appearance');
                api.assert(presetStyle.backgroundImage && presetStyle.backgroundImage !== 'none', '测试场预设下拉框应使用竞技场自绘箭头背景');
                var customSelectTrigger = document.querySelector('#arena-custom-preset-select').parentNode.querySelector('.arena-custom-select-trigger');
                api.assert(!!customSelectTrigger, '测试场预设下拉框应渲染自绘触发器');
                var triggerStyle = getComputedStyle(customSelectTrigger);
                api.assert(triggerStyle.backgroundImage && triggerStyle.backgroundImage !== 'none', '测试场自绘下拉触发器应使用竞技场箭头背景');
                customSelectTrigger.click();
                var customSelectMenu = document.querySelector('.arena-custom-select-menu:not([hidden])');
                api.assert(!!customSelectMenu, '测试场预设下拉框应打开自绘选项层');
                api.assert(customSelectMenu.querySelectorAll('.arena-custom-select-option').length > 1000, '测试场自绘选项层应承载完整预设池');
                var customSelectMenuStyle = getComputedStyle(customSelectMenu);
                api.assert(customSelectMenuStyle.backgroundImage && customSelectMenuStyle.backgroundImage !== 'none', '测试场自绘选项层应使用竞技场背景');
                var customSelectScrollbar = getComputedStyle(customSelectMenu, '::-webkit-scrollbar-thumb');
                api.assert(customSelectScrollbar && customSelectScrollbar.backgroundImage && customSelectScrollbar.backgroundImage !== 'none', '测试场自绘选项层滚动条应使用竞技场样式');
                customSelectTrigger.click();
                api.assert(/none/.test(String(searchStyle.appearance || searchStyle.webkitAppearance || '')), '测试场搜索框应关闭浏览器原生 appearance');
                var rosterList = document.getElementById('arena-custom-active-roster');
                api.assert(rosterList && rosterList.scrollWidth <= rosterList.clientWidth + 1, '阵容列表不应产生横向滚动条');
                var firstRosterRow = document.querySelector('.arena-custom-roster-row');
                api.assert(firstRosterRow && firstRosterRow.querySelector('.arena-custom-param-pill') && firstRosterRow.querySelector('.arena-custom-icon-btn'), '默认参数与移除按钮应同时保留在阵容行内');
                var unitScrollbar = getComputedStyle(document.getElementById('arena-custom-unit-list'), '::-webkit-scrollbar-thumb');
                api.assert(unitScrollbar && unitScrollbar.backgroundImage && unitScrollbar.backgroundImage !== 'none', '单位目录滚动条应使用竞技场自绘样式');
                var groups = document.querySelectorAll('.arena-custom-unit-group');
                api.assert(groups.length > 1, '单位浏览器应按势力分组渲染');
                api.assertEqual(document.querySelectorAll('.arena-custom-unit-row').length, 0, '单位浏览器默认应折叠势力分组');
                var largeGroup = null;
                for (var g = 0; g < groups.length; g++) {
                    if (Number(groups[g].getAttribute('data-custom-faction-count')) > 80) {
                        largeGroup = groups[g];
                        break;
                    }
                }
                api.assert(!!largeGroup, '单位浏览器应保留大势力分组用于滚动加载');
                largeGroup.click();
                var firstBatchRows = document.querySelectorAll('.arena-custom-unit-row').length;
                api.assert(firstBatchRows > 0, '展开势力后应渲染首批单位行');
                api.assert(firstBatchRows < Number(largeGroup.getAttribute('data-custom-faction-count')), '首批单位行不应一次性渲染完整大分组');
                var unitList = document.getElementById('arena-custom-unit-list');
                unitList.scrollTop = unitList.scrollHeight;
                unitList.dispatchEvent(new Event('scroll'));
                api.assert(document.querySelectorAll('.arena-custom-unit-row').length > firstBatchRows, '滚动到底应继续追加单位行');
                api.assert(document.querySelector('.arena-custom-unit-mark'), '单位图标占位符应渲染');
            })
            .then(function() {
                var search = document.getElementById('arena-custom-unit-search');
                search.value = 'P90战术版';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                return api.waitFor(function() {
                    var row = document.querySelector('[data-custom-preset-id]');
                    return row && /P90战术版/.test(row.textContent || '');
                }, 2000, 'search reaches P90 parameter preset');
            })
            .then(function() {
                var row = document.querySelector('[data-custom-preset-id]');
                api.assert(!!row, 'P90 参数预设行应可点击');
                row.click();
                return api.waitFor(function() {
                    var state = window.ArenaPanel.getState();
                    var red = state.customEditor && state.customEditor.red || [];
                    for (var i = 0; i < red.length; i++) {
                        if (red[i].parameters && red[i].parameters['手枪'] === 'P90战术版') return true;
                    }
                    return false;
                }, 2000, 'P90 preset added to red roster');
            })
            .then(function() {
                function findP90ParamButton() {
                    var buttons = document.querySelectorAll('[data-custom-edit-params]');
                    for (var i = 0; i < buttons.length; i++) {
                        var row = buttons[i].parentNode;
                        if (row && /P90战术版/.test(row.textContent || '')) return buttons[i];
                    }
                    return null;
                }
                var buttons = document.querySelectorAll('[data-custom-edit-params]');
                var button = null;
                for (var i = 0; i < buttons.length; i++) {
                    var row = buttons[i].parentNode;
                    if (row && /P90战术版/.test(row.textContent || '')) {
                        button = buttons[i];
                        break;
                    }
                }
                api.assert(!!button, '参数预设加入后应显示参数编辑入口');
                var miniInput = document.querySelector('.arena-custom-mini-input[type="number"]');
                api.assert(!!miniInput, '阵容行应提供竞技场样式数字输入');
                var miniStyle = getComputedStyle(miniInput);
                api.assert(/none|textfield/.test(String(miniStyle.appearance || miniStyle.webkitAppearance || '')), '测试场数字输入应隐藏浏览器原生步进器外观');
                var p90Row = button.parentNode;
                var countInput = p90Row ? p90Row.querySelector('[data-custom-roster-input="count"]') : null;
                api.assert(!!countInput, 'P90 阵容行应有数量输入');
                var beforeTotal = rosterTotal((window.ArenaPanel.getState().customEditor || {}).red);
                var nextCount = Math.min(20, (Number(countInput.value) || 1) + 1);
                countInput.value = String(nextCount);
                countInput.dispatchEvent(new Event('change', { bubbles: true }));
                return api.waitFor(function() {
                    var red = (window.ArenaPanel.getState().customEditor || {}).red || [];
                    return rosterTotal(red) === beforeTotal + 1;
                }, 2000, 'roster count input updates editor state').then(function() {
                    document.querySelector('[data-custom-editor-action="done"]').click();
                    return api.waitFor(function() {
                        return document.getElementById('arena-grid-view') &&
                            !document.getElementById('arena-grid-view').hidden &&
                            document.querySelector('.arena-card-custom');
                    }, 2000, 'back to custom entry card after roster input change');
                }).then(function() {
                    var countText = document.querySelector('.arena-card-custom .arena-custom-side-red .arena-custom-side-count');
                    api.assert(countText && countText.textContent.indexOf(String(beforeTotal + 1) + ' 单位') >= 0,
                        '数量输入 change 后入口卡红方单位数应立即刷新');
                    document.querySelector('.arena-card-custom .arena-custom-side-red .arena-custom-side-edit').click();
                    return api.waitFor(function() {
                        var state = window.ArenaPanel.getState();
                        return state.customEditorPage === 'side' &&
                            state.customSelectedSide === 'red' &&
                            document.querySelectorAll('.arena-custom-unit-group').length > 0;
                    }, 2000, 'return to red side editor after entry summary refresh check');
                }).then(function() {
                    button = findP90ParamButton();
                    api.assert(!!button, '返回红方编辑页后仍应找到 P90 参数入口');
                    button.click();
                    return api.waitFor(function() {
                        var state = window.ArenaPanel.getState();
                        return state.customEditorPage === 'params' && !!document.querySelector('[data-custom-param-editor-input]');
                    }, 2000, 'parameter editor page opened');
                });
            })
            .then(function() {
                var editor = document.querySelector('[data-custom-param-editor-input]');
                api.assert(/P90战术版/.test(editor.value || ''), '参数编辑页应显示当前 JSON 参数');
                document.querySelector('[data-custom-param-mode="xml"]').click();
                return api.waitFor(function() {
                    var input = document.querySelector('[data-custom-param-editor-input]');
                    return input && /<手枪>P90战术版<\/手枪>/.test(input.value || '');
                }, 2000, 'parameter editor switches to XML');
            })
            .then(function() {
                var editor = document.querySelector('[data-custom-param-editor-input]');
                editor.value = '<Parameters>\n  <手枪>P90战术版</手枪>\n  <手枪2>P90战术版</手枪2>\n</Parameters>';
                editor.dispatchEvent(new Event('input', { bubbles: true }));
                api.assert(document.querySelector('.arena-custom-param-dirty'), '参数编辑页应提示草稿未应用');
                api.assert(/放弃返回/.test(document.querySelector('[data-custom-param-action="back"]').textContent || ''), '参数草稿脏时返回按钮应变为放弃返回');
                document.querySelector('[data-custom-param-action="save-back"]').click();
                return api.waitFor(function() {
                    var state = window.ArenaPanel.getState();
                    var red = state.customEditor && state.customEditor.red || [];
                    var expanded = state.customMatch && state.customMatch.parsed && state.customMatch.parsed.calibrationCase
                        ? state.customMatch.parsed.calibrationCase.redRoster : [];
                    var editorOk = false;
                    var expandedOk = false;
                    for (var i = 0; i < red.length; i++) {
                        if (red[i].parameters && red[i].parameters['手枪2'] === 'P90战术版') editorOk = true;
                    }
                    for (var j = 0; j < expanded.length; j++) {
                        if (expanded[j].parameters && expanded[j].parameters['手枪2'] === 'P90战术版') expandedOk = true;
                    }
                    return state.customEditorPage === 'side' && editorOk && expandedOk && state.customMatch.code.indexOf('~') > 0;
                }, 2000, 'editable parameters reflected in match code and calibration case');
            })
            .then(function() {
                var search = document.getElementById('arena-custom-unit-search');
                search.value = '';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                var state = window.ArenaPanel.getState();
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
                var battleSummary = document.getElementById('arena-custom-battle-summary');
                var configPage = document.querySelector('[data-custom-editor-page="config"]');
                api.assert(!!battleSummary, '配置页应显示战场参数摘要');
                api.assert(!configPage.querySelector('#arena-custom-spawn-distance'), '配置总览不应直接渲染战场滑条');
                api.assert(/650/.test(document.getElementById('arena-custom-battle-summary-distance').textContent || ''), '战场摘要应显示默认开局距离');
                document.getElementById('arena-custom-battle-edit').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    var battlePage = document.querySelector('[data-custom-editor-page="battle"]');
                    return st.customEditorPage === 'battle' && battlePage && !battlePage.hidden;
                }, 2000, 'open custom battle params page');
            })
            .then(function() {
                var battlePanel = document.getElementById('arena-custom-battle-params');
                api.assert(!!battlePanel, '战场参数子页应显示完整参数区域');
                api.assert(!!document.getElementById('arena-custom-spawn-distance'), '战场参数应提供开局距离滑条');
                api.assert(!!document.getElementById('arena-custom-timeout'), '战场参数应提供战斗时长滑条');
                api.assert(!!document.querySelector('[data-custom-formation-side="blue"][data-custom-formation-value="wedge"]'), '蓝方应提供楔形阵型预设');
                api.assert(!!document.querySelector('[data-custom-formation-side="red"][data-custom-formation-value="shield"]'), '红方应提供前盾后排阵型预设');
                api.assert(!!document.querySelector('#arena-custom-blue-formation-legend i'), '蓝方阵型应显示填充顺序图例');
                var blueFirstX = parseFloat(document.querySelector('#arena-custom-blue-formation-legend i').style.left);
                var redFirstX = parseFloat(document.querySelector('#arena-custom-red-formation-legend i').style.left);
                api.assert(blueFirstX > redFirstX, '蓝方阵型图例应相对红方左右镜像');
                var blueLineNodes = document.querySelectorAll('#arena-custom-blue-formation-legend i');
                api.assert(Math.abs(parseFloat(blueLineNodes[0].style.left) - parseFloat(blueLineNodes[1].style.left)) > 1,
                    '横列图例应沿 X 横向铺开');
                api.assert(Math.abs(parseFloat(blueLineNodes[0].style.top) - parseFloat(blueLineNodes[1].style.top)) < 1,
                    '横列图例应保持同一 Y');
                document.querySelector('[data-custom-formation-side="red"][data-custom-formation-value="column"]').click();
                var redColumnNodes = document.querySelectorAll('#arena-custom-red-formation-legend i');
                api.assert(Math.abs(parseFloat(redColumnNodes[0].style.left) - parseFloat(redColumnNodes[1].style.left)) < 1,
                    '纵队图例应保持同一 X');
                api.assert(Math.abs(parseFloat(redColumnNodes[0].style.top) - parseFloat(redColumnNodes[1].style.top)) > 1,
                    '纵队图例应沿 Y 纵向铺开');

                var distance = document.getElementById('arena-custom-spawn-distance');
                distance.value = '820';
                distance.dispatchEvent(new Event('input', { bubbles: true }));

                var timeout = document.getElementById('arena-custom-timeout');
                timeout.value = '180';
                timeout.dispatchEvent(new Event('input', { bubbles: true }));

                document.querySelector('[data-custom-formation-side="blue"][data-custom-formation-value="wedge"]').click();
                document.querySelector('[data-custom-formation-side="red"][data-custom-formation-value="shield"]').click();

                return api.waitFor(function() {
                    var parsed = window.ArenaPanel.getState().customMatch.parsed;
                    return parsed &&
                        parsed.spawnDistance === 820 &&
                        parsed.timeoutFrames === 5400 &&
                        parsed.blueFormation === 'wedge' &&
                        parsed.redFormation === 'shield';
                }, 2000, 'custom battle params applied');
            })
            .then(function() {
                var parsed = window.ArenaPanel.getState().customMatch.parsed;
                api.assert(parsed.canonical.indexOf('timeout=5400') >= 0, '非默认战斗时长应写入 canonical 赛程码');
                api.assert(parsed.canonical.indexOf('spawnDistance=820') >= 0, '非默认开局距离应写入 canonical 赛程码');
                api.assert(parsed.canonical.indexOf('blueFormation=wedge') >= 0, '非默认蓝方阵型应写入 canonical 赛程码');
                api.assert(parsed.canonical.indexOf('redFormation=shield') >= 0, '非默认红方阵型应写入 canonical 赛程码');
                api.assert(/距离 820/.test(document.getElementById('arena-custom-code-status').textContent || ''), '状态栏应展示开局距离');
                document.querySelector('[data-custom-editor-page="battle"] [data-custom-editor-action="to-config"]').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customEditorPage === 'config' &&
                        /820/.test(document.getElementById('arena-custom-battle-summary-distance').textContent || '') &&
                        /楔形/.test(document.getElementById('arena-custom-battle-summary-formation').textContent || '');
                }, 2000, 'battle params summary updated after returning to config');
            })
            .then(function() {
                var editorRect = document.getElementById('arena-custom-editor-view').getBoundingClientRect();
                var buttons = document.querySelectorAll('.arena-custom-side-config-actions .arena-custom-btn, .arena-custom-side-config-load .arena-custom-btn');
                api.assert(buttons.length >= 8, '配置总览应保留双方底部操作按钮');
                for (var bi = 0; bi < buttons.length; bi++) {
                    var rect = buttons[bi].getBoundingClientRect();
                    api.assert(rect.height >= 24 && rect.bottom <= editorRect.bottom + 1, '配置总览底部按钮应在编辑视图内可见');
                }
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
                document.getElementById('arena-custom-undo').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return rosterSig(st.customEditor.blue) === blueBeforeSwapSig &&
                        rosterSig(st.customEditor.red) === redBeforeSwapSig;
                }, 2000, 'undo restores roster after swap');
            })
            .then(function() {
                document.querySelector('[data-custom-action="swap-sides"]').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return rosterSig(st.customEditor.blue) === redBeforeSwapSig &&
                        rosterSig(st.customEditor.red) === blueBeforeSwapSig;
                }, 2000, 'blue/red roster swapped again after undo');
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
                        document.querySelectorAll('.arena-custom-unit-group').length > 0;
                }, 2000, 'return to red side editor after config actions');
            })
            .then(function() {
                document.querySelector('[data-custom-unit-filter="nonhostile"]').click();
                return api.waitFor(function() {
                    var active = document.querySelector('.arena-custom-unit-filter-active');
                    return active && active.getAttribute('data-custom-unit-filter') === 'nonhostile';
                }, 2000, 'non-hostile filter active');
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
                var search = document.getElementById('arena-custom-unit-search');
                search.value = '旧型号机器人';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                return api.waitFor(function() {
                    var row = document.querySelector('[data-custom-add-unit="390"]');
                    return row && /旧型号机器人/.test(row.textContent || '');
                }, 2000, 'search reaches unit beyond initial browser batch');
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
        var lastReplayMatchCode = '';
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
                lastReplayMatchCode = msg.matchCode || '';
                api.assert(msg.matchCode && msg.matchCode.indexOf('CF7ARENA:v1;mode=mvm') === 0, '应携带 canonical 赛程代码');
                api.assert(msg.calibrationCase && msg.calibrationCase.blueRoster.length === 4, '应携带 thief-lv30x4 对照阵容');
                api.assertEqual(msg.calibrationCase.spawnDistance, 650, '后台定制赛默认开局距离应进入 calibrationCase');
                api.assertEqual(msg.calibrationCase.timeoutFrames, 3600, '后台定制赛默认战斗时长应进入 calibrationCase');
                api.assertEqual(msg.calibrationCase.blueFormation, 'line', '后台定制赛默认蓝方阵型应进入 calibrationCase');
                api.assertEqual(msg.calibrationCase.redFormation, 'line', '后台定制赛默认红方阵型应进入 calibrationCase');
                api.assertEqual(msg.calibrationCase.formationSpacing, 54, '后台定制赛默认阵型间距应进入 calibrationCase');
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
                api.assert(!!resultView.querySelector('[data-custom-result-action="reopen"]'), '结算页应提供再赛一场入口');
                api.assert(/返回基地/.test(resultView.textContent), '结算页退出文案应指向返回基地');
                var returnBaseBefore = host.sentMessages.filter(function(m) {
                    return m && m.cmd === 'close' && m.dismissReturnStack && m.returnBase;
                }).length;
                var startBeforeReplay = host.sentMessages.filter(function(m) { return m && m.cmd === 'custom_start'; }).length;
                resultView.querySelector('[data-custom-result-action="reopen"]').click();
                return api.waitFor(function() {
                    var state = window.ArenaPanel.getState();
                    var view = document.getElementById('arena-custom-result-view');
                    return state.activeMode === 'custom' &&
                        !state.customResult &&
                        !state.customRun &&
                        view && view.hidden &&
                        document.querySelector('.arena-card-custom');
                }, 2000, 'custom result reopen to panel').then(function() {
                    var returnBaseAfter = host.sentMessages.filter(function(m) {
                        return m && m.cmd === 'close' && m.dismissReturnStack && m.returnBase;
                    }).length;
                    api.assertEqual(returnBaseAfter, returnBaseBefore, '再赛一场不应发送返回基地 close');
                    document.querySelector('.arena-custom-generate').click();
                    return api.waitFor(function() {
                        var confirm = document.getElementById('arena-custom-confirm');
                        return confirm && !confirm.hidden;
                    }, 2000, 'custom confirm rendered again');
                }).then(function() {
                    document.querySelector('[data-custom-confirm-action="start"]').click();
                    return api.waitFor(function() {
                        var starts = host.sentMessages.filter(function(m) { return m && m.cmd === 'custom_start'; });
                        return starts.length > startBeforeReplay;
                    }, 2000, 'second custom_start sent');
                }).then(function() {
                    return api.waitFor(function() {
                        var state = window.ArenaPanel.getState();
                        return state.activeMode === 'custom' &&
                            state.customResult &&
                            state.customRun &&
                            state.customRun.state === 'completed' &&
                            host._customResultOpens >= 2;
                    }, 3000, 'custom result reopened second time');
                }).then(function() {
                    var view = document.getElementById('arena-custom-result-view');
                    api.assert(!!view && !view.hidden, '第二次结算页应显示');
                    view.querySelector('[data-custom-result-action="reopen"]').click();
                    return api.waitFor(function() {
                        var state = window.ArenaPanel.getState();
                        var resultView = document.getElementById('arena-custom-result-view');
                        return state.activeMode === 'custom' &&
                            !state.customResult &&
                            !state.customRun &&
                            resultView && resultView.hidden &&
                            document.querySelector('.arena-card-custom');
                    }, 2000, 'custom result second reopen to panel');
                }).then(function() {
                    var closeBefore = host.sentMessages.filter(function(m) { return m && m.cmd === 'close'; }).length;
                    chrome.webview.__dispatch({ type: 'panel_esc' });
                    return api.waitFor(function() {
                        var closes = host.sentMessages.filter(function(m) { return m && m.cmd === 'close'; });
                        return closes.length > closeBefore;
                    }, 2000, 'reopened custom panel ESC sends close').then(function() {
                        var closes = host.sentMessages.filter(function(m) { return m && m.cmd === 'close'; });
                        var lastClose = closes[closes.length - 1] || {};
                        api.assert(!lastClose.returnBase, '再赛一场回到编辑面板后 ESC 不应发送 returnBase');
                        api.assert(!lastClose.dismissReturnStack, '再赛一场回到编辑面板后 ESC 应为普通关闭');
                        host.open({
                            mode: 'custom_result',
                            source: 'arena_custom_match_result_harness_reopen_close_check',
                            debug: true,
                            matchCode: lastReplayMatchCode,
                            state: 'completed',
                            batchId: 'custom-harness-reopen-close-check',
                            resultPath: 'logs/arena-custom/custom-harness-reopen-close-check-results.jsonl',
                            lastResult: {
                                schema: 'arena-calibration.result.v1',
                                batchId: 'custom-harness-reopen-close-check',
                                caseId: 'arena-custom-p3',
                                runId: 'arena-custom-p3-r001',
                                status: 'finished',
                                winner: 'blue',
                                frames: 96
                            }
                        });
                        return api.waitFor(function() {
                            var resultView = document.getElementById('arena-custom-result-view');
                            return resultView && !resultView.hidden;
                        }, 2000, 'synthetic custom result reopened for return-base close check');
                    });
                });
            })
            .then(function() {
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
                api.assert(startCloses.length >= 2, '两次 custom_start 后的关闭都不应请求返回基地');
                var statusMessages = host.sentMessages.filter(function(m) { return m && m.cmd === 'custom_status'; });
                api.assertEqual(statusMessages.length, 0, 'closePanel 主路径不应继续轮询 custom_status');
                var enterMessages = host.sentMessages.filter(function(m) { return m && m.cmd === 'enter'; });
                api.assertEqual(enterMessages.length, 0, 'P2 定制赛不应发送正式 enter');
                api.assert(host._customResultOpens >= 2, 'Host 应可连续回开 custom_result');
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
