/**
 * Arena Panel QA Suite
 *
 * 测试覆盖（34 项，含 no-merc 纸娃娃回退闭包）：
 *   - panel-open: Panel 能正确打开，DualPaneShell（catalog-decision）挂载 + 渲染社群档位卡片 + 死线警报隐藏卡
 *   - snapshot-render: snapshot 到达后金钱显示正确（壳 header metric），卡片状态正确
 *   - enter-success: 选中卡 → 右栏 preview（cache 命中）→ CommitBar 主 CTA 入场（协议带 cardIndex）
 *   - enter-fail-money: 金钱不足时可选中查看但 CommitBar 禁用并给出阻断原因
 *   - close-btn: 壳 header 关闭按钮发送 close 命令
 *   - esc-close: ESC 触发关闭
 *   - force-close: force_close 正确处理
 *   - card-count: 确认 10 张公开标准卡 + 2 张死线警报隐藏卡都存在且数据正确
 *   - hidden-mixed-enter: 死线警报隐藏卡本地混编 cache 后入场携带 roster；右栏保持配置保密
 *   - standard-mixed-card: 公开标准卡固定 mixed 分支可抽出佣兵模板 + 怪物组（右栏 preview 断言）
 *   - roll-again: 右栏决策头「换一批」重发选中卡 preview 并刷新右栏渲染
 *   - preview-switch-race: 换一批飞行中改选他卡，迟到回包不污染新选中卡 preview（三元组隔离）
 *   - equip-tooltip: hover 装备发送 equip_tooltip，回包后 cache，第二次 hover 不再发请求
 *   - grid-batch-preview: panel open 后佣兵公开卡并发 AS2 preview、roster 卡本地 cache，每张卡目录摘要都脱离 loading
 *   - keyboard-commit: P0 裁决 2——选中卡 Enter/Space 与右栏 CommitBar 走同一 commit handler（payload 全等）
 *   - grid-cache-consistency: 「换一批」后目录摘要与新对手数据一致
 *   - grid-money-disable: 金钱不足时选中高押金卡 → CommitBar 禁用 + 原因，卡仍可被选中查看
 *   - grid-single-fail-retry: 单卡 preview 失败 → 摘要显示"加载失败 ↻" → 点击 ↻ 触发重发 → CommitBar 恢复
 *   - custom-match-p1: 定制赛 tab、赛程代码解析、calibration case 摘要
 *   - custom-match-p2: 定制赛开始委托、关闭 webpanel、结算回开结果态且不走正式 enter
 *   - custom-match-pve: 定制赛玩家 vs 怪物走标准 enter，不走后台 custom_start
 *   - custom-secondary-page: P3 参数页 SecondaryPage（inert/焦点移入/Tab 环）、Esc 逐层
 *     （DOM keydown + 宿主 panel_esc 双通道）、opener 焦点归还、确认条共享 CommitBar
 *     ready/busy 投影、结算页焦点栈层
 *   - fallen-mode-cards: 堕落 tab 渲染、18 张势力卡精确集合/排序/字段派生、FALLEN_MIN_UNITS 过滤、本地采样零 AS2 preview
 *   - fallen-detail-commit: 堕落卡右栏 preview（标题/meta/怪物行）、换一批本地重抽、commit payload（roster 下发、无 mode 字段）
 *   - fallen-partial-known: 部分已知 fixture（波斯军 6 sprite）出卡精确集合，登记跨势力 sprite 污染现状
 *   - escalation-mode-flow: 爬升 tab、isEscalation 卡派生（maxWaves/押注经济）、右栏 preview、commit payload（mode=escalation+pool）
 *   - known-empty-standard-only: knownEnemies 全未知 → 堕落/爬升 tab 缺席，标准模式回退全 merc 仍可用，隐藏卡进失败态
 *   - enter-fail-toast: enter 返回 success:false → toast 展示错误、panel 不关、CommitBar 恢复可用
 *   - keyboard-baseline: 原生 button 语义/focus 可达/无正 tabindex/选中卡键盘提交路径/Web 层不消费 Esc
 *   - overflow-1024: 1024×576 逻辑画布下壳 header/双栏/右栏 preview 零横向溢出
 *   - long-text-clipping: 长中文文案（爬升标题/meta 芯片/势力 rank/摘要）按 ellipsis 裁剪且不失控外溢
 *
 * 执行模型（2026-08-07 P1b 整改）：
 *   用例串行执行，且每个用例前置复位 panel/host 状态（resetCaseEnvironment），
 *   保证全量跑与 --case 单跑初始条件一致。历史教训：Promise.all 并发时 22 个
 *   open/setFixture 互相覆盖（最后写入者赢），且用例内层 {pass:false} 曾被
 *   harness-base runCase 当作成功上报（detail 打成 [object Object]）——全量跑假绿。
 *   现在内层 pass:false 会转成 rejection，如实记 FAIL。
 *
 * P2 改写（2026-08-07 批次合同 §2 裁决）：
 *   grid-direct-enter 按裁决 2 改写为 keyboard-commit（卡片不再承载直入按钮）；
 *   detail 整页视图退役，fallen/escalation 等 detail 断言改锚右栏 preview
 *   （#arena-detail-title/#arena-detail-meta/#arena-opponents 元素 id 保持）；
 *   「全部重抽」留左栏控件条（#arena-reroll-all）；「换一批」随选中语义迁右栏决策头（#arena-roll-one）；
 *   唯一主 CTA = 右栏 CommitBar（.workbench-commit-primary.arena-detail-confirm）。
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
        { id: 'no-merc-meta-dressup', title: '无佣兵时元战队主角纸娃娃回退' },
        { id: 'no-merc-synthetic-dressup', title: '无佣兵时合成主角纸娃娃回退' },
        { id: 'roll-again',           title: '换一批重发 preview' },
        { id: 'reroll-all',           title: '全部重抽重发公开卡 preview' },
        { id: 'preview-switch-race',  title: '迟到 preview 回包被丢弃' },
        { id: 'equip-tooltip',        title: '装备 hover 发起 tooltip 请求 + cache' },
        { id: 'grid-batch-preview',   title: 'Panel 打开后公开卡 preview + 隐藏混编 cache' },
        { id: 'keyboard-commit',      title: '键盘提交 = 右栏同一 commit handler（P0 裁决 2）' },
        { id: 'grid-cache-consistency', title: '换一批后目录摘要同步更新' },
        { id: 'grid-money-disable',   title: '金钱不足 CommitBar 灰 / 卡仍可选中' },
        { id: 'grid-single-fail-retry', title: '单卡失败显示 ↻ + 重试' },
        { id: 'custom-match-p1',      title: '定制赛 P1 赛程代码入口' },
        { id: 'custom-match-p2',      title: '定制赛 P2 后台 single-case 委托' },
        { id: 'custom-match-pve',     title: '定制赛 PVE 玩家 vs 怪物' },
        { id: 'custom-secondary-page', title: '定制赛 P3 参数页 SecondaryPage/焦点栈/CommitBar' },
        { id: 'fallen-mode-cards',    title: '堕落模式 tab 与势力卡派生' },
        { id: 'fallen-detail-commit', title: '堕落卡 detail/换一批/commit' },
        { id: 'fallen-partial-known', title: '堕落模式部分已知出卡集合' },
        { id: 'escalation-mode-flow', title: '爬升模式卡片与 commit payload' },
        { id: 'known-empty-standard-only', title: '全未知时仅标准/定制可用' },
        { id: 'enter-fail-toast',     title: 'Enter 失败 toast 反馈' },
        { id: 'keyboard-baseline',    title: '键盘基线（focus/语义/Esc 归属）' },
        { id: 'overflow-1024',        title: '1024×576 零横向溢出' },
        { id: 'long-text-clipping',   title: '长中文文案裁剪不失控' }
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
        // 串行执行 + 每用例前置复位：全部用例共享同一 panel/host 全局态，
        // 并发会让 open/setFixture/setKnownEnemies 互相覆盖（最后写入者赢）。
        var results = [];
        var chain = Promise.resolve();
        tests.forEach(function(tc) {
            chain = chain.then(function() {
                resetCaseEnvironment(host);
                return runCaseIsolated(api, host, tc);
            }).then(function(r) {
                results.push(r);
            });
        });
        return chain.then(function() {
            return MinigameHarness.normalizeBundle(results);
        });
    }

    // 单用例执行：内层 {pass:false, detail} 转成 rejection，让 harness-base 如实记 FAIL。
    function runCaseIsolated(api, host, tc) {
        return api.runCase(tc.id, tc.title, function() {
            return runCase(api, host, tc.id).then(function(result) {
                if (result && result.pass === false) {
                    throw new Error(result.detail || (tc.id + ' failed'));
                }
                return (result && typeof result.detail === 'string') ? result.detail : '';
            });
        });
    }

    // 用例前置复位：对齐 --case 单跑的初始条件（面板重开 = 新 session = 新 snapshot）。
    // arena 的 reopen 是 rebind no-op（不重发 snapshot），所以必须先 Panels.close()
    // 让本用例的 host.open() 走完整 onOpen，本用例自设的 fixture/knownEnemies 才生效。
    function resetCaseEnvironment(host) {
        if (window.Panels && Panels.getActive && Panels.getActive()) {
            try { Panels.close(); } catch (e) {}
        }
        host.setFixture('normal');
        if (host.resetKnownEnemies) host.resetKnownEnemies();
        host.resetPreviewState();
        host.enterMessages = [];
        host.sentMessages = [];
        host.nextEnterError = '';
        if (host.resetCustomState) host.resetCustomState();
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
            case 'no-merc-meta-dressup':    return caseNoMercMetaDressup(api, host);
            case 'no-merc-synthetic-dressup': return caseNoMercSyntheticDressup(api, host);
            case 'roll-again':              return caseRollAgain(api, host);
            case 'reroll-all':              return caseRerollAll(api, host);
            case 'preview-switch-race':     return casePreviewSwitchRace(api, host);
            case 'equip-tooltip':           return caseEquipTooltip(api, host);
            case 'grid-batch-preview':      return caseGridBatchPreview(api, host);
            case 'keyboard-commit':         return caseKeyboardCommit(api, host);
            case 'grid-cache-consistency':  return caseGridCacheConsistency(api, host);
            case 'grid-money-disable':      return caseGridMoneyDisable(api, host);
            case 'grid-single-fail-retry':  return caseGridSingleFailRetry(api, host);
            case 'custom-match-p1':         return caseCustomMatchP1(api, host);
            case 'custom-match-p2':         return caseCustomMatchP2(api, host);
            case 'custom-match-pve':        return caseCustomMatchPve(api, host);
            case 'custom-secondary-page':   return caseCustomSecondaryPage(api, host);
            case 'fallen-mode-cards':       return caseFallenModeCards(api, host);
            case 'fallen-detail-commit':    return caseFallenDetailCommit(api, host);
            case 'fallen-partial-known':    return caseFallenPartialKnown(api, host);
            case 'escalation-mode-flow':    return caseEscalationModeFlow(api, host);
            case 'known-empty-standard-only': return caseKnownEmptyStandardOnly(api, host);
            case 'enter-fail-toast':        return caseEnterFailToast(api, host);
            case 'keyboard-baseline':       return caseKeyboardBaseline(api, host);
            case 'overflow-1024':           return caseOverflow1024(api, host);
            case 'long-text-clipping':      return caseLongTextClipping(api, host);
            default:                        return Promise.resolve({ pass: false, detail: 'unknown case' });
        }
    }

    // ── 公共辅助：等 batch preview 全部完成（snapshot 回包后立即并发当前卡片集 → 全部成功回包） ──
    // 等待条件：所有 grid 摘要 span 都已脱离 loading 态（即 _previewCache 各 cardIdx 都填了）。
    // 测试新流程下进 detail 的标准准备步骤：先等 batch 完成，确保 cache 命中跳过 detail 内的 preview 请求。
    function waitBatchPreviewReady(api) {
        return api.waitFor(function() {
            var cards = document.querySelectorAll('#arena-grid .arena-card');
            var loading = document.querySelectorAll('.arena-card-opponents-loading');
            return cards.length > 0 && loading.length === 0;
        }, 3000, 'batch preview 全部完成（grid 摘要无 loading）');
    }

    function portraitHasVisiblePixels(host) {
        var img = host && host.querySelector('img');
        if (!img || !img.complete || !img.naturalWidth || !img.naturalHeight) return false;
        try {
            var canvas = document.createElement('canvas');
            canvas.width = 32;
            canvas.height = 32;
            var context = canvas.getContext('2d', { willReadFrequently: true });
            context.drawImage(img, 0, 0, 32, 32);
            var pixels = context.getImageData(0, 0, 32, 32).data;
            for (var i = 3; i < pixels.length; i += 4) if (pixels[i] > 4) return true;
        } catch (ignore) {}
        return false;
    }

    // ── P2 公共辅助：右栏决策面（CommitBar 唯一主 CTA + 状态文本）与选中语义 ──
    function commitPrimary() {
        return document.querySelector('.arena-decision .workbench-commit-primary');
    }
    function commitStatusText() {
        var el = document.querySelector('.arena-decision .workbench-commit-status');
        return el ? (el.textContent || '') : '';
    }
    function waitCommitEnabled(api) {
        return api.waitFor(function() {
            var btn = commitPrimary();
            return btn && !btn.disabled;
        }, 2000, 'CommitBar 主 CTA enabled');
    }
    function waitCommitDisabled(api, reason) {
        return api.waitFor(function() {
            var btn = commitPrimary();
            return btn && btn.disabled && (!reason || commitStatusText().indexOf(reason) >= 0);
        }, 2000, 'CommitBar 主 CTA disabled' + (reason ? '（' + reason + '）' : ''));
    }
    // 点卡 = 选中（右栏 preview 更新；cache 命中时不发新 preview）
    function clickCard(idx) {
        var el = document.querySelector('#arena-grid .arena-card[data-index="' + idx + '"]');
        if (el) el.click();
        return el;
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
        var mercs = window.ArenaMetaRosters && window.ArenaMetaRosters.mercenaries || [];
        for (var i = 0; i < squad.opponents.length; i++) {
            var opponent = squad.opponents[i];
            if (opponent.mercId == null) continue;
            var projected = null;
            for (var m = 0; m < mercs.length; m++) {
                if (String(mercs[m].id) === String(opponent.mercId)) { projected = mercs[m]; break; }
            }
            api.assert(!!projected, label + ' 的 mercId 必须命中公开佣兵投影');
            api.assert(projected.portrait && projected.portrait.kind === 'dressup', label + ' 的佣兵投影必须携带 dressup actor');
            assertDressupActorEqual(api, opponent, projected.portrait.actor,
                label + ' mercId=' + opponent.mercId + ' 的公开预览必须等于 AS2 按同 mercId 重建的外观 tuple',
                projected);
        }
    }

    function stableEquipment(equipment) {
        var sorted = {};
        equipment = equipment && typeof equipment === 'object' ? equipment : {};
        Object.keys(equipment).sort().forEach(function(slot) { sorted[slot] = String(equipment[slot]); });
        return JSON.stringify(sorted);
    }

    function assertDressupActorEqual(api, opponent, expectedActor, label, expectedSourceTuple) {
        api.assert(opponent && opponent.portraitKind === 'dressup', label + ' 应显式声明 portraitKind=dressup');
        api.assert(opponent.portrait && opponent.portrait.kind === 'dressup' && opponent.portrait.actor,
            label + ' 应携带 portrait.actor');
        var actual = opponent.portrait.actor;
        api.assertEqual(actual.gender, expectedActor.gender, label + ' gender');
        api.assertEqual(String(actual.face), String(expectedActor.face), label + ' face');
        api.assertEqual(String(actual.hair), String(expectedActor.hair), label + ' hair');
        api.assertEqual(stableEquipment(actual.equipment), stableEquipment(expectedActor.equipment), label + ' equipment');
        var sourceTuple = expectedSourceTuple || expectedActor;
        api.assertEqual(opponent.gender, sourceTuple.gender, label + ' 顶层 gender');
        api.assertEqual(String(opponent.face), String(sourceTuple.face), label + ' 顶层 face');
        api.assertEqual(String(opponent.hair), String(sourceTuple.hair), label + ' 顶层 hair');
        api.assertEqual(stableEquipment(opponent.equipment), stableEquipment(sourceTuple.equipment), label + ' 顶层 equipment');
    }

    function catalogActorForOpponent(opponent) {
        var units = window.ArenaUnitCatalog && window.ArenaUnitCatalog.units || [];
        for (var i = 0; i < units.length; i++) {
            if (String(units[i].type || '') !== String(opponent.type || '')) continue;
            var portrait = units[i].portrait;
            return portrait && portrait.kind === 'dressup' ? portrait.actor : null;
        }
        return null;
    }

    function assertCatalogHydratedHumanoids(api, squad, label) {
        api.assert(squad && squad.opponents && squad.opponents.length, label + ' 应产出 roster');
        var humanoids = 0;
        for (var i = 0; i < squad.opponents.length; i++) {
            var opponent = squad.opponents[i];
            if (opponent.rosterKind !== 'humanoid') continue;
            humanoids++;
            var expectedActor = catalogActorForOpponent(opponent);
            api.assert(!!expectedActor, label + ' 的主角模板必须命中 ArenaUnitCatalog portrait.actor');
            assertDressupActorEqual(api, opponent, expectedActor, label + ' type=' + opponent.type);
        }
        api.assert(humanoids > 0, label + ' 应至少包含一个主角模板');
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
        api.assert(counts.merc + counts.nonhuman <= expectedHumanoid + expectedNonhuman * 12,
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
                return api.waitFor(function() {
                    return document.querySelectorAll('#arena-grid .arena-card').length >= 10;
                }, 2000, '权威标准卡 snapshot 渲染');
            })
            .then(function() {
                // P2：浏览面 = 共享 DualPaneShell（catalog-decision 封闭 profile 投影）
                var shell = document.querySelector('.arena-panel .workbench-shell');
                api.assert(!!shell, 'workbench-shell 不存在');
                api.assertEqual(shell.getAttribute('data-profile'), 'catalog-decision', '壳 profile 应为 catalog-decision');
                var grid = document.querySelector('.arena-grid');
                api.assert(!!grid, 'arena-grid 不存在');
                var cards = grid.querySelectorAll('.arena-card');
                api.assert(cards.length >= 10, '卡片数量应至少包含 10 个公开档位');
                // 壳 header 承载：模式 tabs（第一个 action）/ 密度切换 / 帮助 / 关闭
                var header = shell.querySelector('.workbench-header');
                api.assert(!!header.querySelector('.arena-modes .arena-mode-tab'), '壳 header 应承载模式 tabs');
                api.assert(!!header.querySelector('.item-grid-mode-toggle'), '壳 header 应承载目录密度切换');
                api.assert(!!header.querySelector('.workbench-help-btn'), '壳 header 应承载帮助入口');
                api.assert(!!header.querySelector('.workbench-close-btn'), '壳 header 应承载关闭按钮');
                api.assert(!!window.MercPortraits && typeof window.MercPortraits.mount === 'function', '竞技场应加载共享佣兵纸娃娃头像组件');
                var fullButton = header.querySelector('.item-grid-mode-option[data-layout-mode="full"]');
                var compactButton = header.querySelector('.item-grid-mode-option[data-layout-mode="compact"]');
                api.assert(!!fullButton && !!compactButton, '完整/紧凑布局按钮应同时存在');
                fullButton.click();
                var fullColumns = getComputedStyle(grid).gridTemplateColumns.trim().split(/\s+/).length;
                api.assertEqual(fullColumns, 2, '完整模式应为 2 列识别卡，不再塞 4 列');
                var firstPortrait = grid.querySelector('.arena-card-portrait');
                api.assert(!!firstPortrait && !!firstPortrait.closest('.arena-card-overview'), '完整卡应以头像为第一视觉锚点');
                compactButton.click();
                var compactColumns = getComputedStyle(grid).gridTemplateColumns.trim().split(/\s+/).length;
                api.assertEqual(compactColumns, 3, '紧凑模式应为 3 列速览卡，不再塞 4 列');
                var compactPortrait = grid.querySelector('.arena-card-portrait');
                api.assert(!!compactPortrait && parseFloat(getComputedStyle(compactPortrait).width) <= 50, '紧凑头像应收至 48px CSS 档');
                api.assert(getComputedStyle(grid.querySelector('.arena-card-stats')).display !== 'none', '紧凑态仍应保留对手数/等级语义');
                fullButton.click();
                // 换一批（右栏决策头）/ 全部重抽（左栏控件条）+ 右栏唯一主 CTA（未选中 = disabled）
                api.assert(!!document.getElementById('arena-roll-one'), '右栏决策头应有「换一批」控件');
                api.assert(document.getElementById('arena-roll-one').closest('.arena-decision-head') != null,
                    '「换一批」应挂在右栏决策头');
                api.assert(!!document.getElementById('arena-reroll-all'), '左栏应有「全部重抽」控件');
                var primary = commitPrimary();
                api.assert(!!primary, '右栏应有 CommitBar 主 CTA');
                api.assertEqual(primary.disabled, true, '未选中时主 CTA 应禁用');
                api.assert(commitStatusText().indexOf('选择左侧挑战') >= 0, '未选中状态文案应引导选择');
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
    // P2 流程：panel 开 → snapshot → batch preview 全卡 → 等目录摘要全到 →
    //         点卡选中（cache 命中，无新 preview）→ 右栏 CommitBar 主 CTA → enter 协议带 cardIndex
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
                return api.waitFor(function() {
                    return document.querySelector('#arena-grid .arena-card-portrait-item[data-portrait-ref]');
                }, 3000, '标准模式怪物卡面头像挂载');
            })
            .then(function() {
                // 选中前记录 preview 消息计数 — 验证 cache 命中确实跳过新请求
                var cards = window.ArenaPanel.getCards();
                cardIdx = findPublicCardIndexByRole(cards, 'merc', 1);
                api.assert(cardIdx >= 0, '应能找到佣兵公开卡');
                var beforeCount = host.previewMessages.length;
                clickCard(cardIdx);
                return waitCommitEnabled(api).then(function() {
                    api.assertEqual(host.previewMessages.length, beforeCount, '选中时 cache 命中，不应发新 preview');
                });
            })
            .then(function() {
                return api.waitFor(function() {
                    var portrait = document.querySelector('.arena-opp-row .arena-opp-portrait');
                    return portrait && portrait.getAttribute('data-merc-portrait-source') === 'dressup';
                }, 6000, '竞技场佣兵右栏纸娃娃头像');
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assert(rows.length >= 1, '右栏对手行应被渲染（来自 batch cache）');
                api.assert(rows[0].querySelector('.arena-opp-portrait').classList.contains('merc-dressup-ready'), '佣兵右栏不应继续使用硬编码剪影');
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.selectedCardIdx, cardIdx, '选中态应为被点卡片');
                commitPrimary().click();
                return api.waitFor(function() {
                    return host.enterMessages.length > 0;
                }, 2000, 'enter message sent');
            })
            .then(function() {
                var msg = host.enterMessages[host.enterMessages.length - 1];
                api.assert(msg.cmd === 'enter', '提交消息应为 enter');
                api.assertEqual(msg.cardIndex, cardIdx, '入场应带所选 cardIndex');
                api.assert(typeof msg.cardId === 'string' && msg.cardId.indexOf('arena-') === 0, 'enter 应只携带权威 cardId');
                api.assert(msg.expr === undefined && msg.deposit === undefined && msg.reward === undefined,
                    'P5 Web enter 不得携带 expr/deposit/reward');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: enter-fail-money ──
    // 破产时高押金卡：选中/查看不受阻（预览可读），CommitBar 禁用并给出金钱不足原因
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
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                clickCard(0);
                return waitCommitDisabled(api, '金钱不足');
            })
            .then(function() {
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.selectedCardIdx, 0, '破产状态下卡片仍可选中查看（预览不受阻）');
                var primary = commitPrimary();
                api.assert(!!primary, '找不到 CommitBar 主 CTA');
                api.assertEqual(primary.disabled, true, '破产状态下主 CTA 应被禁用');
                api.assert(commitStatusText().indexOf('押金') >= 0, '阻断原因应含押金数额');
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
                var closeBtn = document.querySelector('.workbench-close-btn');
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
    // 等 batch → 选中佣兵卡（cache 命中无新 preview）→ 右栏「换一批」（额外 1 条 preview）→
    // 验右栏对手仍渲、CommitBar 恢复可用
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
                clickCard(cardIdx);
                return api.waitFor(function() {
                    var btn = document.getElementById('arena-roll-one');
                    return btn && !btn.disabled;
                }, 2000, '选中后右栏「换一批」可用');
            })
            .then(function() {
                var before = host.previewMessages.length;
                document.getElementById('arena-roll-one').click();
                return api.waitFor(function() {
                    return host.previewMessages.length > before;
                }, 2000, 'rollAgain 触发额外 preview');
            })
            .then(function() {
                // 裁决 3：单卡重抽后、新 preview 到达前，该卡 commit 禁用
                var primary = commitPrimary();
                api.assertEqual(primary.disabled, true, '换一批飞行中 CommitBar 应禁用');
                var cards = window.ArenaPanel.getCards();
                api.assert(host.previewMessages.length >= standardPreviewMessageCount(cards) + 1, '换一批后总 preview 数应 >= 佣兵公开卡数 + 1');
                return waitCommitEnabled(api);
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assert(rows.length >= 1, '换一批后右栏对手应重新渲染');
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.selectedCardIdx, cardIdx, '换一批后选中卡保持不变（保留位置）');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: preview-switch-race ──
    // 验三元组隔离：选中卡 0「换一批」飞行中改选卡 1，卡 0 的迟到回包只写 cache、
    // 不污染卡 1 的右栏 preview（_selectedCardIdx 守护 + pending 记录逐字段比对）。
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
                // 选中第一张佣兵卡：cache 命中，右栏立即渲对应人数
                clickCard(card0Idx);
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-opp-row');
                    var rollBtn = document.getElementById('arena-roll-one');
                    return rows.length === card0Count && rollBtn && !rollBtn.disabled;
                }, 2000, 'card-0 右栏 preview 就绪');
            })
            .then(function() {
                // 点「换一批」→ 发新 preview，但回包未到（80ms mock 延迟）
                document.getElementById('arena-roll-one').click();
                // 立刻改选第二张佣兵卡（cache 命中，应渲对应人数）
                clickCard(card1Idx);
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-opp-row');
                    return rows.length === card1Count;
                }, 2000, 'card-1 右栏 preview 渲完');
            })
            .then(function() {
                // 等卡 0 的 rollAgain 回包到达（mock 80ms + buffer）
                return new Promise(function(resolve) { setTimeout(resolve, 250); });
            })
            .then(function() {
                var rows = document.querySelectorAll('.arena-opp-row');
                api.assertEqual(rows.length, card1Count, '卡 0 换一批迟到回包不应污染卡 1 的右栏 preview（三元组隔离）');
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.selectedCardIdx, card1Idx, '选中应停在卡 1');
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
                clickCard(cardIdx);
                return api.waitFor(function() {
                    var cells = document.querySelectorAll('#arena-opponents .arena-equip-cell[data-eq-raw]');
                    return cells.length > 0;
                }, 2000, 'equip cells rendered（右栏 preview）');
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
                // P2：隐藏卡可选中，但右栏保持「配置保密」（不渲染对手行）——
                // 旧 detail 按钮禁用语义 = 选中可看经济面、不可看阵容
                clickCard(hiddenIdx);
                return waitCommitEnabled(api);
            })
            .then(function() {
                var rows = document.querySelectorAll('#arena-opponents .arena-opp-row');
                api.assertEqual(rows.length, 0, '隐藏卡右栏不应渲染对手配置行');
                api.assert(document.getElementById('arena-opponents').textContent.indexOf('保密') >= 0,
                    '隐藏卡右栏应提示配置保密');
                commitPrimary().click();
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
                // 全量已知：monster 角色卡的 meta-team 采样要求整队 spritename 已知（isKnownTeam），
                // 手写 12 条只覆盖部分等级带 → 怪物角色落到未覆盖带时回退 unit-pool，断言随
                // Math.random 角色落位漂移（2026-08-07 串行化后暴露，单跑同样红）。断言未动。
                host.setKnownEnemies(window.ArenaQaKnownFixtures.all());
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
                var detailTarget = clickCard(mixedIdx);
                api.assert(!!detailTarget, '公开 mixed 卡应可选中');
                return api.waitFor(function() {
                    var meta = document.getElementById('arena-detail-meta');
                    return meta && /实体/.test(meta.textContent || '') &&
                        document.querySelectorAll('#arena-opponents .arena-opp-row-monster').length > 0;
                }, 2000, 'mixed 右栏 preview 应显示等效/实体 roster 语义');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) {
                return { pass: false, detail: String(e.message || e) };
            });
    }

    function caseNoMercMetaDressup(api, host) {
        var squad = null;
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.setKnownEnemies(window.ArenaQaKnownFixtures.all());
                host.resetPreviewState();
                host.open();
                return waitPanelActive(api);
            })
            .then(function() { return waitBatchPreviewReady(api); })
            .then(function() {
                var mercs = window.ArenaMetaRosters.mercenaries;
                try {
                    window.ArenaMetaRosters.mercenaries = [];
                    squad = ArenaPreviewAuthority.sampleMixedSquadForTests({
                        levelMin: 1,
                        levelMax: 100,
                        opponentCount: 4,
                        requiresMixedRoster: true
                    });
                } finally {
                    window.ArenaMetaRosters.mercenaries = mercs;
                }
                api.assert(squad && squad.source === 'meta-team',
                    '无可用佣兵时应进入真实元战队回退，而不是丢失 mixed 卡');
                assertMixedRoster(api, squad.opponents, '无佣兵元战队回退');
                assertCatalogHydratedHumanoids(api, squad, '无佣兵元战队回退');
                ArenaChallengeBrowser.renderOpponents(squad.opponents);
                return api.waitFor(function() {
                    return document.querySelector('.arena-opp-portrait.arena-portrait-merc.merc-dressup-ready[data-merc-portrait-source="dressup"]');
                }, 7000, 'no-merc meta-team humanoid mounts dressup portrait');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    function caseNoMercSyntheticDressup(api, host) {
        var squad = null;
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.setKnownEnemies(window.ArenaQaKnownFixtures.all());
                host.resetPreviewState();
                host.open();
                return waitPanelActive(api);
            })
            .then(function() { return waitBatchPreviewReady(api); })
            .then(function() {
                squad = ArenaPreviewAuthority.sampleSyntheticMixedSquadForTests({
                    levelMin: 1,
                    levelMax: 100,
                    opponentCount: 4,
                    isHiddenChallenge: true,
                    requiresMixedRoster: true
                });
                api.assert(squad && squad.source === 'synthetic', '合成回退测试缝应产出 synthetic mixed roster');
                assertMixedRoster(api, squad.opponents, '无佣兵合成回退');
                assertCatalogHydratedHumanoids(api, squad, '无佣兵合成回退');

                var missingGender = ArenaPreviewAuthority.weightedMercenarySampleForTests([{
                    id: '__legacy_missing_gender__',
                    name: 'legacy missing gender',
                    level: 1,
                    face: null,
                    hair: null,
                    equipment: {},
                    weight: 1
                }], 1)[0];
                api.assertEqual(missingGender.gender, '女', '缺失 gender 必须对齐 ArenaPanelService legacy 规则回退为女');
                api.assertEqual(missingGender.spritename, '主角-女', '缺失 gender 的主角模板必须选择女 sprite');
                api.assertEqual(missingGender.face, '女变装-基本脸型', '缺失 gender/face 必须使用女基本脸型');
                api.assertEqual(missingGender.portrait.actor.gender, '女', '缺失 gender 的显式 dressup actor 必须为女');

                ArenaChallengeBrowser.renderOpponents(squad.opponents);
                return api.waitFor(function() {
                    return document.querySelector('.arena-opp-portrait.arena-portrait-merc.merc-dressup-ready[data-merc-portrait-source="dressup"]');
                }, 7000, 'no-merc synthetic humanoid mounts dressup portrait');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
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
                // 先选中一张卡，让决策面处于可提交前的真实状态
                var cards = window.ArenaPanel.getCards();
                clickCard(findPublicCardIndexByRole(cards, 'monster', 1) >= 0 ? findPublicCardIndexByRole(cards, 'monster', 1) : 0);
                return api.waitFor(function() {
                    return window.ArenaPanel.getState().selectedCardIdx >= 0;
                }, 2000, '卡片已选中');
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                var expectedPreviewCount = standardPreviewMessageCount(cards);
                var before = host.previewMessages.length;
                var btn = document.getElementById('arena-reroll-all');
                api.assert(!!btn && !btn.disabled && !btn.hidden, '全部重抽按钮应可用');
                btn.click();
                // P0 裁决 3：全部重抽 → 整个决策面失效（清空 selection 与 commit 可用性）
                api.assertEqual(window.ArenaPanel.getState().selectedCardIdx, -1, '全部重抽应清空选中');
                var primary = commitPrimary();
                api.assert(!!primary && primary.disabled, '全部重抽后 CommitBar 应禁用');
                api.assert(commitStatusText().indexOf('选择左侧挑战') >= 0, '全部重抽后决策面应归空态');
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
                return api.waitFor(function() {
                    return document.querySelector('.arena-card-portrait-item[data-merc-portrait-source="dressup"]')
                        && document.querySelector('.arena-card-portrait-item[data-portrait-ref]');
                }, 6000, '标准卡佣兵/怪物代表头像均完成挂载');
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                var hosts = document.querySelectorAll('#arena-grid .arena-card-portrait');
                api.assertEqual(hosts.length, cards.length, '每张标准/隐藏卡都应保留稳定头像槽');
                for (var i = 0; i < 10; i++) {
                    api.assert(!hosts[i].classList.contains('arena-card-portrait-loading'), '公开卡 ' + i + ' 头像应脱离 loading');
                }
                var hiddenHosts = document.querySelectorAll('#arena-grid .arena-card-portrait-hidden');
                api.assertEqual(hiddenHosts.length, 2, '两张隐藏挑战应保留保密头像槽');
                for (var h = 0; h < hiddenHosts.length; h++) {
                    api.assert(!hiddenHosts[h].hasAttribute('data-portrait-ref')
                        && !hiddenHosts[h].hasAttribute('data-merc-portrait-source'), '保密卡不得提前泄露阵容头像');
                }
                var multiGroup = document.querySelector('#arena-grid .arena-card-portrait[data-arena-portrait-count="2"], '
                    + '#arena-grid .arena-card-portrait[data-arena-portrait-count="3"], '
                    + '#arena-grid .arena-card-portrait[data-arena-portrait-count="4"]');
                api.assert(!!multiGroup, '完整态样本应包含至少一张多单位头像组');
                var items = multiGroup.querySelectorAll('.arena-card-portrait-item');
                api.assert(items.length >= 2 && items.length <= 4, '头像组应保留 2—4 个实际单位小图标');
                var fullButton = document.querySelector('.item-grid-mode-option[data-layout-mode="full"]');
                var compactButton = document.querySelector('.item-grid-mode-option[data-layout-mode="compact"]');
                var beforeDensityMessages = host.previewMessages.length;
                fullButton.click();
                var fullVisible = 0;
                for (var f = 0; f < items.length; f++) {
                    if (getComputedStyle(items[f]).display !== 'none') fullVisible++;
                }
                api.assertEqual(fullVisible, items.length, '完整态应批量展示头像组内全部小图标');
                compactButton.click();
                var compactVisible = 0;
                for (var c = 0; c < items.length; c++) {
                    if (getComputedStyle(items[c]).display !== 'none') compactVisible++;
                }
                api.assertEqual(compactVisible, 1, '紧凑态应只显示头像组首项');
                api.assertEqual(multiGroup.querySelectorAll('.arena-card-portrait-item').length, items.length, '密度切换不得丢弃阵容头像数据');
                api.assertEqual(host.previewMessages.length, beforeDensityMessages, '密度切换不得重新请求或抽取对手');
                fullButton.click();
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: keyboard-commit（原 grid-direct-enter，按 P0 裁决 2 改写）──
    // 卡片不再承载独立直入按钮；选中卡 Enter/Space 与右栏 CommitBar 主 CTA 走
    // 同一个 commit handler（commitSelectedChallenge）——三条路径发出的 enter payload 必须全等。
    function caseKeyboardCommit(api, host) {
        var cardIdx = 0;
        function lastEnterPayload() {
            var msg = host.enterMessages[host.enterMessages.length - 1];
            return msg ? JSON.stringify({
                cmd: msg.cmd, cardId: msg.cardId, cardIndex: msg.cardIndex, difficulty: msg.difficulty,
                roster: msg.roster || null, mode: msg.mode || null
            }) : '';
        }
        function fireKey(el, key) {
            el.dispatchEvent(new KeyboardEvent('keydown', { key: key, bubbles: true, cancelable: true }));
        }
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
                // 挑战卡不再有任何独立直入按钮（旧 grid-direct-enter 合同退役）
                var grid = document.getElementById('arena-grid');
                api.assert(!grid.querySelector('.arena-card-btn-enter'), '目录卡不应再有 ⚔ 直入按钮');
                api.assert(!grid.querySelector('.arena-card-btn-detail'), '目录卡不应再有 🔍 次按钮');
                api.assert(!document.getElementById('arena-detail-view'), 'detail 整页视图应已退役');
                var prizeBlocks = grid.querySelectorAll('.arena-card-prize');
                api.assert(prizeBlocks.length >= 10, '标准目录应提供可量测的经济区');
                for (var prizeIdx = 0; prizeIdx < prizeBlocks.length; prizeIdx++) {
                    var prizeBlock = prizeBlocks[prizeIdx];
                    var prizeValue = prizeBlock.querySelector('.arena-prize-value');
                    var prizeDeposit = prizeBlock.querySelector('.arena-prize-deposit');
                    var blockRect = prizeBlock.getBoundingClientRect();
                    var valueRect = prizeValue.getBoundingClientRect();
                    var depositRect = prizeDeposit.getBoundingClientRect();
                    api.assert(valueRect.bottom <= depositRect.top + 0.5,
                        '卡片 ' + prizeIdx + ' 奖金与押金不得重叠');
                    api.assert(valueRect.left >= blockRect.left - 0.5
                        && valueRect.right <= blockRect.right + 0.5
                        && depositRect.left >= blockRect.left - 0.5
                        && depositRect.right <= blockRect.right + 0.5,
                        '卡片 ' + prizeIdx + ' 经济数值不得溢出容器');
                }
                var cards = window.ArenaPanel.getCards();
                cardIdx = findPublicCardIndexByRole(cards, 'merc', 1);
                api.assert(cardIdx >= 0, '应能找到佣兵公开卡');
            })
            .then(function() {
                // 未选中卡上 Enter = 只选中固定预览（不发 enter）
                var cardEl = document.querySelector('#arena-grid .arena-card[data-index="' + cardIdx + '"]');
                fireKey(cardEl, 'Enter');
                return api.waitFor(function() {
                    return window.ArenaPanel.getState().selectedCardIdx === cardIdx;
                }, 2000, 'Enter 选中卡片').then(function() {
                    api.assertEqual(host.enterMessages.length, 0, '未选中卡首次 Enter 只选中，不应发 enter');
                    api.assert(cardEl.classList.contains('arena-card-selected'), '选中卡应有 arena-card-selected 类');
                    api.assertEqual(cardEl.getAttribute('aria-selected'), 'true', '选中卡 aria-selected=true');
                    return waitCommitEnabled(api);
                });
            })
            .then(function() {
                // 已选中卡 Enter → commit #1（注入失败让 panel 保持打开，可继续比较后续路径）
                host.nextEnterError = 'mock keyboard-commit #1';
                var cardEl = document.querySelector('#arena-grid .arena-card[data-index="' + cardIdx + '"]');
                fireKey(cardEl, 'Enter');
                return api.waitFor(function() {
                    return host.enterMessages.length === 1;
                }, 2000, '选中卡 Enter 应发出 enter');
            })
            .then(function() {
                // 等失败回包清 busy（toast 可见即回包已处理）
                return api.waitFor(function() {
                    var toast = document.getElementById('arena-toast');
                    return toast && toast.classList.contains('arena-toast-visible');
                }, 2000, 'commit #1 失败回包已处理');
            })
            .then(function() {
                // 已选中卡 Space → commit #2（同一 handler 第二快捷键别名）
                host.nextEnterError = 'mock keyboard-commit #2';
                var cardEl = document.querySelector('#arena-grid .arena-card[data-index="' + cardIdx + '"]');
                fireKey(cardEl, ' ');
                return api.waitFor(function() {
                    return host.enterMessages.length === 2;
                }, 2000, '选中卡 Space 应发出 enter');
            })
            .then(function() {
                return api.waitFor(function() {
                    var toast = document.getElementById('arena-toast');
                    return toast && toast.classList.contains('arena-toast-visible')
                        && toast.textContent.indexOf('#2') >= 0;
                }, 2000, 'commit #2 失败回包已处理');
            })
            .then(function() {
                // 右栏 CommitBar 主 CTA → commit #3（成功，panel 关闭）
                return waitCommitEnabled(api).then(function() {
                    commitPrimary().click();
                    return api.waitFor(function() {
                        return host.enterMessages.length === 3;
                    }, 2000, 'CommitBar 主 CTA 应发出 enter');
                });
            })
            .then(function() {
                var p0 = lastEnterPayload();
                host.enterMessages.pop();
                var p1 = lastEnterPayload();
                host.enterMessages.pop();
                var p2 = lastEnterPayload();
                api.assert(p0 && p1 && p2, '三次 commit 都应有 enter 消息');
                api.assertEqual(p0, p1, 'Space 与 CommitBar 主 CTA 的 enter payload 应全等（同一 handler）');
                api.assertEqual(p1, p2, 'Enter 与 Space 的 enter payload 应全等（同一 handler）');
                api.assert(JSON.parse(p2).cardIndex === cardIdx, 'keyboard-commit 应带所选 cardIndex');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: grid-cache-consistency ──
    // 选中卡「换一批」→ 目录摘要文本应同步为新对手数据（双区同步覆盖）
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
                clickCard(cardIdx);
                return api.waitFor(function() {
                    var btn = document.getElementById('arena-roll-one');
                    return btn && !btn.disabled;
                }, 2000, 'roll 按钮就绪');
            })
            .then(function() {
                var beforeCount = host.previewMessages.length;
                document.getElementById('arena-roll-one').click();
                return api.waitFor(function() {
                    return host.previewMessages.length > beforeCount;
                }, 2000, 'rollAgain preview 已发出');
            })
            .then(function() {
                // 等回包到达 + 写 cache + renderCardSummary 同步目录（80ms mock + buffer）
                return new Promise(function(resolve) { setTimeout(resolve, 200); });
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
    // poor fixture：低押金卡选中 → CommitBar 可用；高押金卡选中 → CommitBar 禁用 + 金钱不足原因，
    // 卡本身仍可选中（阵容查看不受阻，对齐 EntityTile inspectable/actionable 分离）
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
                // 卡 0 押金 500 → 玩家 1000 够 → 选中后 CommitBar 可用
                clickCard(0);
                return waitCommitEnabled(api);
            })
            .then(function() {
                // 公开最高档押金显著高于 1000 → 可选中查看，CommitBar 禁用并给出原因
                var highIdx = 9;
                clickCard(highIdx);
                return waitCommitDisabled(api, '金钱不足');
            })
            .then(function() {
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.selectedCardIdx, 9, '高押金卡仍应可选中（查看阵容不受阻）');
                var rows = document.querySelectorAll('#arena-opponents .arena-opp-row');
                api.assert(rows.length >= 1, '高押金卡右栏 preview 应正常渲染');
                var cardEl = document.querySelector('#arena-grid .arena-card[data-index="9"]');
                api.assert(cardEl.classList.contains('arena-card-disabled'), '高押金卡应保持视觉降权灰类');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: grid-single-fail-retry ──
    // 单卡 preview 失败 → 摘要显示"加载失败 ↻" + 选中该卡 CommitBar error 禁用
    // → 点击摘要 ↻ 触发重发 → 摘要回 loading 然后成功 → CommitBar 恢复可用
    function caseGridSingleFailRetry(api, host) {
        var failIdx = 0;
        var okIdx = 0;
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                // 自注入单卡 preview 失败（历史：并发时代靠 reroll-all 用例遗留的注入交叉感染，
                // 串行化后必须自己注入；断言未动）
                for (var fp = 0; fp < 10; fp++) host.failNextPreviewForCard(fp, 'stock_insufficient');
                host.open();
                return api.waitFor(function() {
                    return Panels.getActive && Panels.getActive() === 'arena';
                }, 2000, 'panel active');
            })
            .then(function() {
                // 等至少一张佣兵卡摘要进入 error 态
                return api.waitFor(function() {
                    var cards = window.ArenaPanel.getCards();
                    if (!cards || cards.length < 10) return false;
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
                // 选中失败卡 → CommitBar error 禁用且给原因
                clickCard(failIdx);
                return waitCommitDisabled(api, 'stock_insufficient');
            })
            .then(function() {
                // 其他本地 roster 卡选中 → CommitBar 正常可用（不受失败卡影响）
                clickCard(okIdx);
                return waitCommitEnabled(api);
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
                clickCard(failIdx);
                return waitCommitEnabled(api);
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
                var unitList = document.getElementById('arena-custom-unit-list');
                unitList.scrollTop = Math.min(180, unitList.scrollHeight - unitList.clientHeight);
                var toggleGroup = groups[Math.min(6, groups.length - 1)];
                var toggleFactionKey = toggleGroup.getAttribute('data-custom-toggle-faction');
                var scrollBeforeExpand = unitList.scrollTop;
                api.assert(scrollBeforeExpand > 0, '分类滚动保持回归必须从非零目录位置开始');
                toggleGroup.click();
                api.assert(Math.abs(unitList.scrollTop - scrollBeforeExpand) <= 1,
                    '展开分类标签后应保留滚动位置（before=' + scrollBeforeExpand + ', after=' + unitList.scrollTop + '）');
                var expandedToggleGroup = document.querySelector('[data-custom-toggle-faction="' + toggleFactionKey + '"]');
                var scrollBeforeCollapse = unitList.scrollTop;
                expandedToggleGroup.click();
                api.assert(Math.abs(unitList.scrollTop - scrollBeforeCollapse) <= 1,
                    '收起分类标签后应保留滚动位置（before=' + scrollBeforeCollapse + ', after=' + unitList.scrollTop + '）');
                groups = document.querySelectorAll('.arena-custom-unit-group');
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
                unitList.scrollTop = unitList.scrollHeight;
                unitList.dispatchEvent(new Event('scroll'));
                api.assert(document.querySelectorAll('.arena-custom-unit-row').length > firstBatchRows, '滚动到底应继续追加单位行');
                api.assert(document.querySelector('.arena-custom-unit-portrait'), '单位目录应渲染通用头像舞台');
                var scrollBeforeAdd = unitList.scrollTop;
                var rosterTotalBeforeAdd = rosterTotal((window.ArenaPanel.getState().customEditor || {}).red);
                api.assert(scrollBeforeAdd > 0, '滚动保持回归必须从非零目录位置开始');
                document.querySelector('.arena-custom-unit-row').click();
                var rosterTotalAfterAdd = rosterTotal((window.ArenaPanel.getState().customEditor || {}).red);
                api.assertEqual(rosterTotalAfterAdd, rosterTotalBeforeAdd + 1, '点击目录单位应加入当前红方');
                api.assert(Math.abs(unitList.scrollTop - scrollBeforeAdd) <= 1,
                    '点击目录单位后应保留滚动位置（before=' + scrollBeforeAdd + ', after=' + unitList.scrollTop + '）');
            })
            .then(function() {
                var search = document.getElementById('arena-custom-unit-search');
                search.value = '武装JK';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                return api.waitFor(function() {
                    var portrait = document.querySelector('[data-custom-add-unit="285"] .arena-custom-unit-portrait');
                    var source = portrait && portrait.getAttribute('data-portrait-source');
                    var coverage = document.getElementById('arena-custom-portrait-coverage');
                    return portrait && (source === 'svg' || source === 'png')
                        && coverage && coverage.getAttribute('data-coverage-state') === 'complete';
                }, 5000, 'accepted JK portrait and complete catalog coverage reach arena unit catalog');
            })
            .then(function() {
                var portrait = document.querySelector('[data-custom-add-unit="285"] .arena-custom-unit-portrait');
                var coverage = document.getElementById('arena-custom-portrait-coverage');
                api.assert(window.EnemyPortraits && window.PortraitResolver === window.EnemyPortraits, 'Team 兼容别名与通用头像组件应指向同一实例');
                var jkOrange = EnemyPortraits.resolve({ portraitRef: '敌人-武装JK', portraitVariant: 'orange' });
                var jkWhite = EnemyPortraits.resolve({ portraitRef: '敌人-武装JK', portraitVariant: 'white' });
                var simonli = EnemyPortraits.resolve({ portraitRef: '敌人-锡蒙利' });
                var simonliGenerator = EnemyPortraits.resolve({ portraitRef: '敌人-锡蒙利范围光环发生器' });
                api.assert(portrait && portrait.classList.contains('entity-portrait-art'), '竞技场头像应消费通用 entity-portrait-art 样式契约');
                api.assertEqual(portrait.getAttribute('data-portrait-ref'), '敌人-武装JK', '单位 spritename 应作为稳定 portraitRef');
                api.assert(portrait.getAttribute('data-portrait-variant') === 'orange'
                    && jkOrange && jkWhite && jkOrange.svgUrl !== jkWhite.svgUrl,
                    '竞技场无发色状态时应使用 JK 默认橙发，同时共享清单必须保留橙发/白发两个独立头像');
                api.assert(coverage && coverage.getAttribute('data-coverage-state') === 'complete', '当前全兵种素材包应明确投影为完整覆盖');
                api.assertEqual(Number(coverage.getAttribute('data-coverage-total')), 217, '全兵种目录应按 217 个唯一 spritename 统计');
                api.assertEqual(Number(coverage.getAttribute('data-coverage-ready')), 217, '怪物清单 214 项与主角纸娃娃 3 项应合并为 217 个可用身份');
                api.assertEqual(Number(coverage.getAttribute('data-coverage-missing')), 0, '全兵种目录不应再有锁定图身份缺口');
                api.assertEqual(Number(coverage.getAttribute('data-coverage-enemy-ready')), 214, '214 个怪物消费身份应全部命中 manifest 或签名 alias');
                api.assertEqual(Number(coverage.getAttribute('data-coverage-dressup-ready')), 3, '三个主角模板身份都应进入纸娃娃头像路线');
                api.assert(simonli && simonliGenerator
                    && simonliGenerator.requestedPortraitRef === '敌人-锡蒙利范围光环发生器'
                    && simonliGenerator.portraitRef === '敌人-锡蒙利'
                    && simonliGenerator.svgUrl === simonli.svgUrl
                    && simonliGenerator.pngUrl === simonli.pngUrl,
                    '锡蒙利范围光环发生器应经签名 identity alias 复用锡蒙利主体，不复制新资产');
                var search = document.getElementById('arena-custom-unit-search');
                search.value = '霜精之王';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                return api.waitFor(function() {
                    var frost = document.querySelector('[data-custom-add-unit="411"] .arena-custom-unit-portrait');
                    return frost && frost.getAttribute('data-portrait-source') === 'svg' && portraitHasVisiblePixels(frost);
                }, 5000, 'Frost King accepted SVG paints visible pixels');
            })
            .then(function() {
                var frost = document.querySelector('[data-custom-add-unit="411"] .arena-custom-unit-portrait');
                api.assertEqual(frost.getAttribute('data-portrait-ref'), '敌人-霜精之王', '霜精之王应消费已人工通过的稳定身份，不得回退问号');
                var search = document.getElementById('arena-custom-unit-search');
                search.value = 'Pig';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                return api.waitFor(function() {
                    var hero = document.querySelector('[data-custom-add-unit="158"] .arena-custom-unit-portrait');
                    return hero && hero.getAttribute('data-arena-portrait-kind') === 'dressup'
                        && hero.getAttribute('data-merc-portrait-source') === 'dressup'
                        && portraitHasVisiblePixels(hero);
                }, 7000, 'protagonist template renders through dressup portrait route');
            })
            .then(function() {
                var hero = document.querySelector('[data-custom-add-unit="158"] .arena-custom-unit-portrait');
                api.assert(hero && hero.classList.contains('merc-dressup-ready'), '主角单位应渲染具体纸娃娃外观而不是通用锁定图');
                var heroImage = hero.querySelector('img');
                var heroImageStyle = getComputedStyle(heroImage);
                var heroRect = hero.getBoundingClientRect();
                var heroImageRect = heroImage.getBoundingClientRect();
                api.assertEqual(heroImageStyle.objectFit, 'cover', '竞技场纸娃娃应复用佣兵卡的 cover 裁剪规则');
                api.assert(heroImageRect.width <= heroRect.width + 0.5
                    && heroImageRect.height <= heroRect.height + 0.5
                    && Math.abs(heroImage.offsetWidth - hero.clientWidth) <= 1
                    && Math.abs(heroImage.offsetHeight - hero.clientHeight) <= 1,
                    '纸娃娃快照应铺满头像内容盒且不越过外框，不得以 112px 原图溢出后只露出武器局部');
                api.assert(!hero.hasAttribute('title') && !!hero.getAttribute('data-custom-tooltip')
                    && !!hero.__panelTooltipBinding,
                    '头像说明应接入 PanelTooltip，禁止回退浏览器原生 title 气泡');
                var queueState = MercPortraits.debugState();
                api.assertEqual(queueState.maxConcurrentRenders, 4, '纸娃娃快照队列默认并发上限应为 4');
                api.assert(queueState.activeRenderCount <= queueState.maxConcurrentRenders
                    && queueState.peakActiveRenderCount <= queueState.maxConcurrentRenders,
                    '纸娃娃快照活跃渲染数不得突破共享并发上限');
                var search = document.getElementById('arena-custom-unit-search');
                search.value = '远古流年';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                return api.waitFor(function() {
                    var ancient = document.querySelector('[data-custom-add-unit="235"] .arena-custom-unit-portrait');
                    return ancient && ancient.getAttribute('data-merc-portrait-state') === 'ready'
                        && ancient.getAttribute('data-merc-portrait-source') === 'dressup'
                        && ancient.classList.contains('merc-dressup-ready')
                        && !ancient.classList.contains('merc-portrait-fallback')
                        && portraitHasVisiblePixels(ancient);
                }, 10000, 'unit 235 exact ancient armor renders a ready 112px portrait');
            })
            .then(function() {
                var ancient = document.querySelector('[data-custom-add-unit="235"] .arena-custom-unit-portrait');
                api.assert(ancient && ancient.getAttribute('data-merc-portrait-state') === 'ready',
                    '远古流年首次渲染必须结束于 ready，不得残留 pending/fallback');
                var search = document.getElementById('arena-custom-unit-search');
                search.value = '主角-男';
                search.dispatchEvent(new Event('input', { bubbles: true }));
                return api.waitFor(function() {
                    var portraits = document.querySelectorAll('[data-arena-portrait-kind="dressup"]');
                    var mounted = document.querySelectorAll('[data-arena-portrait-kind="dressup"][data-arena-portrait-mounted="1"]');
                    return portraits.length > 40 && mounted.length > 0 && mounted.length < portraits.length;
                }, 3000, 'dressup portraits mount only near the visible catalog window');
            })
            .then(function() {
                var portraits = document.querySelectorAll('[data-arena-portrait-kind="dressup"]');
                var mounted = document.querySelectorAll('[data-arena-portrait-kind="dressup"][data-arena-portrait-mounted="1"]');
                api.assert(mounted.length < portraits.length,
                    '长目录不得一次打开全部纸娃娃渲染（mounted=' + mounted.length + ', total=' + portraits.length + '）');
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
                api.assert(enterMsg.expr === undefined && enterMsg.deposit === undefined && enterMsg.reward === undefined,
                    'PVE Web enter 也不得携带经济字段；Host 固定重建零经济');
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

    // ── case: custom-secondary-page ──
    // 定制赛 P3 选择性收敛（批次合同 §3 P3）：
    //   ① 深层参数页由共享 SecondaryPage 承载：active/aria-hidden 翻转、编辑器头部与其余
    //      页面 inert+aria-hidden（背景禁用）、焦点移入（initialFocus = 返回阵容）、Tab 环页内循环；
    //   ② Esc 逐层：DOM keydown（FocusScope）退参数页；宿主 panel_esc 通道同路径逐层
    //      （参数页 → 编辑器页级 → 总览），面板不被误关；
    //   ③ opener 焦点归还：离开参数页焦点回阵容行「参数」按钮，离开编辑器回总览入口按钮；
    //   ④ 确认条共享 CommitBar：ready/busy 投影（点击后同一 task 立即可见禁用 + aria-busy），
    //      panel_esc 先取消确认层（不关面板）；结算页焦点栈层激活 + 返回基地关闭不变。
    function caseCustomSecondaryPage(api, host) {
        var paramSide = '';
        var paramIndex = '';
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
                document.querySelector('.arena-mode-tab[data-mode="custom"]').click();
                return api.waitFor(function() {
                    return document.querySelector('.arena-card-custom') != null;
                }, 2000, 'custom card rendered');
            })
            .then(function() {
                var state = window.ArenaPanel.getState();
                api.assertEqual(state.customEditorScopeActive, false, '总览层编辑器焦点栈不应激活');
                document.querySelector('.arena-card-custom .arena-custom-side-red .arena-custom-side-edit').click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customEditorPage === 'side' && st.customSelectedSide === 'red'
                        && st.customEditorScopeActive === true;
                }, 2000, 'editor opened with focus scope active');
            })
            .then(function() {
                // 焦点移入编辑器（壳外整页视图 = 一个焦点栈层）
                var editorView = document.getElementById('arena-custom-editor-view');
                api.assert(editorView.contains(document.activeElement), '进入编辑器后焦点应在编辑器内');
                var btn = document.querySelector('#arena-custom-active-roster [data-custom-edit-params]');
                api.assert(!!btn, '阵容行应有参数编辑入口');
                paramSide = btn.getAttribute('data-side');
                paramIndex = btn.getAttribute('data-index');
                btn.click();
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customEditorPage === 'params' && st.customParamPageActive === true;
                }, 2000, 'param page opened as SecondaryPage');
            })
            .then(function() {
                var page = document.querySelector('[data-custom-editor-page="params"]');
                api.assert(page.classList.contains('workbench-secondary-page'), '参数页应挂共享 SecondaryPage 类');
                api.assert(page.classList.contains('active'), '参数页应处于 active 态');
                api.assertEqual(page.getAttribute('aria-hidden'), 'false', '参数页打开时应 aria-hidden=false');
                // 背景 inert/aria-hidden（共享合同：二级页打开时底层禁用）
                var header = document.querySelector('.arena-custom-editor-header');
                api.assert(header.hasAttribute('inert'), '参数页打开时编辑器头部应 inert');
                api.assertEqual(header.getAttribute('aria-hidden'), 'true', '参数页打开时编辑器头部应 aria-hidden');
                var sidePage = document.querySelector('[data-custom-editor-page="side"]');
                api.assertEqual(sidePage.hidden, true, '参数页打开时单方编辑页应隐藏');
                // 焦点移入：initialFocus = 返回阵容按钮
                var backBtn = page.querySelector('[data-custom-param-action="back"]');
                api.assert(document.activeElement === backBtn, '参数页打开后焦点应在「返回阵容」（initialFocus）');
            })
            .then(function() {
                // Tab 环 trap：焦点在页内循环（textarea = 页内最后一个可聚焦元素）
                var page = document.querySelector('[data-custom-editor-page="params"]');
                var textarea = page.querySelector('[data-custom-param-editor-input]');
                var backBtn = page.querySelector('[data-custom-param-action="back"]');
                textarea.focus();
                api.assert(document.activeElement === textarea, '参数输入框应可聚焦');
                textarea.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));
                api.assert(document.activeElement === backBtn, '末位 Tab 应环回页内首个控件（trap 不外溢到头部）');
                backBtn.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', shiftKey: true, bubbles: true, cancelable: true }));
                api.assert(document.activeElement === textarea, '首位 Shift+Tab 应环回页内末位控件');
            })
            .then(function() {
                // DOM Esc（FocusScope 层）：只退参数页，不关编辑器/面板
                var page = document.querySelector('[data-custom-editor-page="params"]');
                page.querySelector('[data-custom-param-editor-input]')
                    .dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customEditorPage === 'side' && st.customParamPageActive === false;
                }, 2000, 'DOM Escape closes param page only');
            })
            .then(function() {
                api.assert(Panels.getActive && Panels.getActive() === 'arena', 'DOM Esc 退参数页不应关闭面板');
                var page = document.querySelector('[data-custom-editor-page="params"]');
                api.assertEqual(page.getAttribute('aria-hidden'), 'true', '参数页关闭后应 aria-hidden=true');
                var header = document.querySelector('.arena-custom-editor-header');
                api.assert(!header.hasAttribute('inert'), '参数页关闭后编辑器头部应解除 inert');
                api.assert(header.getAttribute('aria-hidden') !== 'true', '参数页关闭后编辑器头部应解除 aria-hidden');
                api.assertEqual(document.querySelector('[data-custom-editor-page="side"]').hidden, false, '返回后单方编辑页应恢复显示');
                // opener 焦点归还：回到同一阵容行的「参数」按钮（列表重渲后按 side/index 找回）
                var opener = document.querySelector('#arena-custom-active-roster [data-custom-edit-params][data-side="'
                    + paramSide + '"][data-index="' + paramIndex + '"]');
                api.assert(!!opener && document.activeElement === opener, '离开参数页焦点应归还阵容行「参数」按钮');
            })
            .then(function() {
                // 宿主 panel_esc 通道同路径：先退参数页
                var btn = document.querySelector('#arena-custom-active-roster [data-custom-edit-params]');
                btn.click();
                return api.waitFor(function() {
                    return window.ArenaPanel.getState().customParamPageActive === true;
                }, 2000, 'param page reopened');
            })
            .then(function() {
                chrome.webview.__dispatch({ type: 'panel_esc' });
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    return st.customEditorPage === 'side' && st.customParamPageActive === false;
                }, 2000, 'panel_esc closes param page first');
            })
            .then(function() {
                api.assert(Panels.getActive && Panels.getActive() === 'arena', 'panel_esc 退参数页不应关闭面板');
                // 再退编辑器页级：side → config
                chrome.webview.__dispatch({ type: 'panel_esc' });
                return api.waitFor(function() {
                    return window.ArenaPanel.getState().customEditorPage === 'config';
                }, 2000, 'panel_esc steps editor back to config page');
            })
            .then(function() {
                api.assert(Panels.getActive && Panels.getActive() === 'arena', 'panel_esc 退编辑器页级不应关闭面板');
                // 再退编辑器整页 → 回总览，焦点归还入口按钮
                chrome.webview.__dispatch({ type: 'panel_esc' });
                return api.waitFor(function() {
                    var editor = document.getElementById('arena-custom-editor-view');
                    return editor.hidden && document.querySelector('.arena-card-custom');
                }, 2000, 'panel_esc exits editor to overview');
            })
            .then(function() {
                var opener = document.querySelector('.arena-card-custom .arena-custom-edit');
                api.assert(!!opener && document.activeElement === opener, '离开编辑器焦点应归还总览「编辑配置」按钮');
                // 确认条共享 CommitBar（ready 投影）
                document.querySelector('.arena-custom-generate').click();
                return api.waitFor(function() {
                    var confirm = document.getElementById('arena-custom-confirm');
                    return confirm && !confirm.hidden;
                }, 2000, 'custom confirm rendered');
            })
            .then(function() {
                var bar = document.querySelector('#arena-custom-confirm .workbench-commit-bar');
                api.assert(!!bar, '确认条应消费共享 CommitBar');
                var primary = bar.querySelector('.workbench-commit-primary');
                api.assertEqual(primary.getAttribute('data-custom-confirm-action'), 'start', 'CommitBar 主按钮应保留 start 动作锚点');
                api.assert(/确认委托/.test(primary.textContent || ''), 'MVM 确认条主按钮应为「确认委托」');
                var status = bar.querySelector('.workbench-commit-status');
                api.assert(/场地费/.test(status.textContent || ''), '确认条状态应呈现成本（场地费）');
                api.assertEqual(primary.disabled, false, '确认条主按钮 ready 态应可用');
                // panel_esc 先取消确认层，不关面板
                chrome.webview.__dispatch({ type: 'panel_esc' });
                return api.waitFor(function() {
                    return window.ArenaPanel.getState().customConfirmOpen === false
                        && document.getElementById('arena-custom-confirm').hidden;
                }, 2000, 'panel_esc cancels confirm layer');
            })
            .then(function() {
                api.assert(Panels.getActive && Panels.getActive() === 'arena', '取消确认层不应关闭面板');
                document.querySelector('.arena-custom-generate').click();
                return api.waitFor(function() {
                    var confirm = document.getElementById('arena-custom-confirm');
                    return confirm && !confirm.hidden;
                }, 2000, 'custom confirm rendered again');
            })
            .then(function() {
                // busy 投影：点击后同一 task 内立即可见禁用（原实现静默 no-op，P3 修正）
                // busy 投影：点击后同一 task 内立即可见禁用（原实现静默 no-op，P3 修正；
                // startCustomMatch 内的重解析不再关闭确认层，busy 窗口真实可见）
                var primary = document.querySelector('#arena-custom-confirm .workbench-commit-primary');
                primary.click();
                api.assertEqual(primary.disabled, true, '提交飞行中主按钮应立即禁用（不再静默 no-op）');
                api.assertEqual(primary.getAttribute('aria-busy'), 'true', '提交飞行中主按钮应 aria-busy');
                var busyStatus = document.querySelector('#arena-custom-confirm .workbench-commit-status');
                api.assert(/正在提交/.test(busyStatus.textContent || ''), '提交飞行中应显示 busy 状态文本');
                var status = document.querySelector('#arena-custom-confirm .workbench-commit-status');
                api.assert(/正在提交/.test(status.textContent || ''), '提交飞行中应显示 busy 状态文本');
                return api.waitFor(function() {
                    for (var i = 0; i < host.sentMessages.length; i++) {
                        if (host.sentMessages[i] && host.sentMessages[i].cmd === 'custom_start') return true;
                    }
                    return false;
                }, 2000, 'custom_start sent from CommitBar onCommit');
            })
            .then(function() {
                // 委托成功 → 关面板 → Host 回开结算页：结算页焦点栈层激活
                return api.waitFor(function() {
                    var st = window.ArenaPanel.getState();
                    var view = document.getElementById('arena-custom-result-view');
                    return st.customResult && st.customRun && st.customRun.state === 'completed'
                        && view && !view.hidden && st.customResultScopeActive === true;
                }, 3000, 'custom result reopened with focus scope active');
            })
            .then(function() {
                var view = document.getElementById('arena-custom-result-view');
                api.assert(view.contains(document.activeElement), '结算页打开后焦点应在结算页内');
                chrome.webview.__dispatch({ type: 'panel_esc' });
                return api.waitFor(function() {
                    for (var i = 0; i < host.sentMessages.length; i++) {
                        var msg = host.sentMessages[i];
                        if (msg && msg.cmd === 'close' && msg.dismissReturnStack && msg.returnBase) return true;
                    }
                    return false;
                }, 2000, 'result view panel_esc returns base');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // P1b：堕落/爬升模式 + 基线用例（characterization：只钉现行实现真实行为，不改面板）
    // knownEnemies fixture 来自 ./known-enemies-fixtures.js（window.ArenaQaKnownFixtures），
    // 经 harness host.setKnownEnemies → mock snapshot.knownEnemies 注入面板。
    // ════════════════════════════════════════════════════════════════════════════

    function knownFixtures(api) {
        var fx = window.ArenaQaKnownFixtures;
        api.assert(!!fx, 'known-enemies-fixtures.js 未加载（harness 应先于 qa-suite 引入）');
        return fx;
    }

    function waitPanelActive(api) {
        return api.waitFor(function() {
            return Panels.getActive && Panels.getActive() === 'arena';
        }, 2000, 'panel active');
    }

    function waitModeTab(api, mode) {
        return api.waitFor(function() {
            return document.querySelector('.arena-mode-tab[data-mode="' + mode + '"]');
        }, 2000, mode + ' tab rendered');
    }

    function switchToMode(api, mode) {
        document.querySelector('.arena-mode-tab[data-mode="' + mode + '"]').click();
        return api.waitFor(function() {
            return window.ArenaPanel.getState().activeMode === mode;
        }, 2000, 'activeMode=' + mode);
    }

    function findCardIndexByFaction(cards, faction) {
        for (var i = 0; i < cards.length; i++) {
            if (cards[i].faction === faction) return i;
        }
        return -1;
    }

    function assertNoHorizontalOverflow(api, selector, label) {
        var el = document.querySelector(selector);
        api.assert(!!el, label + '：' + selector + ' 应存在');
        api.assert(el.scrollWidth <= el.clientWidth + 1,
            label + '：不应出现横向溢出（scrollWidth=' + el.scrollWidth + ' clientWidth=' + el.clientWidth + '）');
    }

    // ── case: fallen-mode-cards ──
    // 全量已知 → 堕落 tab 渲染；18 张势力卡的精确集合/排序/派生字段钉死现行公式；
    // FALLEN_MIN_UNITS=4 滤掉单例势力；预览全程本地采样（零 AS2 preview）。
    function caseFallenModeCards(api, host) {
        // buildFallenCards 派生结果（2026-08 数据 + FALLEN_BAND_WINDOW=15）：按 (levelMin,levelMax) 升序
        var EXPECTED = [
            ['波斯军', 44, 59], ['不死军团', 44, 59], ['日本军', 45, 60], ['亡灵/僵尸', 45, 60],
            ['天网', 45, 60], ['黑铁会', 45, 60], ['忍者', 45, 60], ['雪山', 45, 60],
            ['军阀势力', 45, 60], ['摇滚公园', 45, 60], ['狂野玫瑰', 45, 60], ['堕落城', 45, 60],
            ['虫群', 45, 60], ['方舟', 45, 60], ['异形', 85, 100], ['铁血', 85, 100],
            ['凤凰眷属', 85, 100], ['魔神', 85, 100]
        ];
        return Promise.resolve()
            .then(function() {
                var fx = knownFixtures(api);
                host.setFixture('rich');
                host.setKnownEnemies(fx.all());
                host.resetPreviewState();
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                return waitModeTab(api, 'fallen');
            })
            .then(function() {
                api.assert(!!document.querySelector('.arena-mode-tab[data-mode="escalation"]'), '爬升 tab 应同时渲染（同源 requiresRosters 门槛）');
                api.assert(!!document.querySelector('.arena-mode-tab[data-mode="standard"]'), '标准 tab 应保留');
                api.assert(!!document.querySelector('.arena-mode-tab[data-mode="custom"]'), '定制赛 tab 应保留');
                api.assertEqual(document.querySelectorAll('.arena-mode-tab').length, 4, '全量已知时应渲染 4 个模式 tab');
                // 标准模式 batch 已发过 AS2 preview；清零后切堕落，验堕落 batch 零 AS2 往返
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                host.resetPreviewState();
                return switchToMode(api, 'fallen');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                return api.waitFor(function() {
                    return document.querySelector('#arena-grid .arena-card-portrait-item[data-portrait-ref]');
                }, 3000, '堕落模式卡面头像挂载');
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                api.assertEqual(cards.length, EXPECTED.length, '堕落模式应出 18 张势力卡');
                var expectedByFaction = {};
                for (var e = 0; e < EXPECTED.length; e++) expectedByFaction[EXPECTED[e][0]] = EXPECTED[e];
                for (var i = 0; i < cards.length; i++) {
                    var expected = expectedByFaction[cards[i].faction];
                    api.assert(!!expected, '堕落卡应来自权威 18 势力集合：' + cards[i].faction);
                    api.assertEqual(cards[i].levelMin, expected[1], cards[i].faction + ' 挑战带下限');
                    api.assertEqual(cards[i].levelMax, expected[2], cards[i].faction + ' 挑战带上限');
                    api.assert(cards[i].isFallen === true, cards[i].faction + ' 应带 isFallen 标记');
                    api.assert(!cards[i].isEscalation, cards[i].faction + ' 堕落卡不应带 isEscalation');
                    if (i > 0) {
                        api.assert(cards[i - 1].levelMin <= cards[i].levelMin,
                            'Host 权威卡在 Web 只按挑战带升序投影');
                    }
                }
                // FALLEN_MIN_UNITS=4 过滤效果：联合大学/斯巴达各仅 1 单位，即使全量已知也不出卡
                api.assert(findCardIndexByFaction(cards, '联合大学') < 0, '联合大学（1 单位）应被 FALLEN_MIN_UNITS 过滤');
                api.assert(findCardIndexByFaction(cards, '斯巴达') < 0, '斯巴达（1 单位）应被 FALLEN_MIN_UNITS 过滤');
                // 波斯军（排序后首卡）字段派生钉死：benchLevel 缺省回退 levelMax=59，
                // count=clamp(3+⌊59/25⌋,4,6)=5，奖金=59×5×800=236000，押金=roundTo(奖金×0.4)=94000
                var persiaIdx = findCardIndexByFaction(cards, '波斯军');
                var c = cards[persiaIdx];
                api.assertEqual(c.opponentCount, 5, '波斯军对手数派生');
                api.assertEqual(c.deposit, 94000, '波斯军押金派生');
                api.assertEqual(c.reward, 236000, '波斯军奖金派生');
                api.assertEqual(c.expr, '#0@44-59%5', '波斯军合成 expr（仅为过 AS2 非空校验）');
                api.assertEqual(c.unitCount, 6, '波斯军已知单位数');
                api.assertEqual(host.previewMessages.length, 0, '堕落卡预览应为本地采样，全程零 AS2 preview');
                // 卡面 DOM：建卡即紫罗兰怪物卡 + 势力名 rank + 麾下阵容 cap + 押金/奖金渲染
                var el = document.querySelector('.arena-card[data-index="' + persiaIdx + '"]');
                api.assert(el.classList.contains('arena-card-monster'), '堕落卡应建卡即上 arena-card-monster（紫罗兰）');
                var portrait = el.querySelector('.arena-card-portrait');
                var portraitItem = portrait.querySelector('.arena-card-portrait-item');
                api.assert(portraitItem && portraitItem.classList.contains('entity-portrait-art') && !portrait.classList.contains('arena-card-portrait-loading'), '堕落卡应接入怪物身份头像，而非剪影');
                api.assertEqual(el.querySelector('.arena-card-rank-faction').textContent, '波斯军', '堕落卡 rank 槽应为势力名');
                api.assertEqual(el.querySelector('.arena-card-opponents-cap').textContent, '麾下阵容', '堕落卡阵容 cap 应为「麾下阵容」');
                api.assert(el.querySelector('.arena-prize-value').textContent.indexOf('236,000') >= 0, '卡面应渲染奖金 236,000');
                api.assert(el.querySelector('.arena-prize-deposit').textContent.indexOf('94,000') >= 0, '卡面应渲染押金 94,000');
                var sum = document.getElementById('arena-opp-summary-' + persiaIdx);
                api.assert(sum.textContent.indexOf('实体×5') >= 0, 'grid 摘要应为 roster 实体格式（实际: ' + sum.textContent + '）');
                // P2：本地采样 cache 落盘后，选中该卡 → 右栏 CommitBar 可用
                clickCard(persiaIdx);
                return waitCommitEnabled(api);
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: fallen-detail-commit ──
    // 选中波斯军卡 → 右栏 preview：标题/meta/怪物行渲染；换一批 = 本地重抽（零 AS2 preview）；
    // commit 走 roster 下发（现行实现堕落入场不带 mode 字段，AS2 按 roster 有无分流——钉现状）。
    function caseFallenDetailCommit(api, host) {
        var cardIdx = -1;
        return Promise.resolve()
            .then(function() {
                var fx = knownFixtures(api);
                host.setFixture('rich');
                host.setKnownEnemies(fx.all());
                host.resetPreviewState();
                host.enterMessages = [];
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                return waitModeTab(api, 'fallen');
            })
            .then(function() {
                return switchToMode(api, 'fallen');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                cardIdx = findCardIndexByFaction(cards, '波斯军');
                api.assert(cardIdx >= 0, '应找到波斯军势力卡');
                clickCard(cardIdx);
                return api.waitFor(function() {
                    var btn = commitPrimary();
                    return btn && !btn.disabled && document.querySelectorAll('.arena-opp-row-monster').length === 5;
                }, 2000, '波斯军右栏 preview 渲染完成（cache 命中）');
            })
            .then(function() {
                return api.waitFor(function() {
                    var rows = document.querySelectorAll('.arena-opp-row-monster');
                    if (rows.length !== 5) return false;
                    for (var i = 0; i < rows.length; i++) {
                        var portrait = rows[i].querySelector('.arena-opp-portrait');
                        if (!portrait || !portrait.classList.contains('entity-portrait-art')
                                || !portrait.hasAttribute('data-portrait-source')) return false;
                    }
                    return true;
                }, 5000, '波斯军右栏全部怪物身份头像');
            })
            .then(function() {
                api.assertEqual(document.getElementById('arena-detail-title').textContent, '波斯军 · 禁区噩梦 挑战', '堕落卡右栏标题（levelMax 59 → 禁区噩梦）');
                var meta = document.getElementById('arena-detail-meta').textContent;
                api.assert(meta.indexOf('等效 ×5') >= 0, 'meta 应含等效人数');
                api.assert(meta.indexOf('实体 ×5') >= 0, 'meta 应含实体人数');
                api.assert(meta.indexOf('等级 44—59') >= 0, 'meta 应含挑战带');
                // 经济上屏唯一归属 CommitBar 状态条（meta 芯片不再复述押金/奖金）
                api.assert(meta.indexOf('押金') < 0, 'meta 不再承载押金（唯一归属 CommitBar 状态条）');
                var commitText = commitStatusText();
                api.assert(commitText.indexOf('押金 94,000') >= 0, 'CommitBar 状态条应含押金');
                api.assert(commitText.indexOf('奖金 236,000') >= 0, 'CommitBar 状态条应含奖金');
                // 对手全部来自波斯军挑战带单位池；方舟妖姬 maxLevel 20 < 带下限 44，按 poolForBand 不入池
                var bandNames = { '波斯步兵': true, '波斯弓兵': true, '不死亲卫队': true, '不死兽人': true, '斯巴达勇士': true };
                var rows = document.querySelectorAll('.arena-opp-row-monster');
                for (var i = 0; i < rows.length; i++) {
                    var name = rows[i].querySelector('.arena-opp-name').textContent;
                    api.assert(bandNames[name] === true, '右栏对手应来自波斯军挑战带单位池（实际: ' + name + '）');
                    var portrait = rows[i].querySelector('.arena-opp-portrait');
                    api.assert(portrait.classList.contains('entity-portrait-art') && portrait.hasAttribute('data-portrait-source'), '怪物右栏头像应接入共享身份组件并保留 fail-soft 来源');
                }
            })
            .then(function() {
                // 换一批（右栏决策头）：堕落卡本地重抽，不产生 AS2 preview 往返
                var beforePreviews = host.previewMessages.length;
                document.getElementById('arena-roll-one').click();
                return api.waitFor(function() {
                    var btn = commitPrimary();
                    return btn && !btn.disabled && document.querySelectorAll('.arena-opp-row-monster').length === 5;
                }, 2000, '换一批后右栏重渲').then(function() {
                    api.assertEqual(host.previewMessages.length, beforePreviews, '堕落卡换一批应为本地重抽，零 AS2 preview');
                    api.assertEqual(window.ArenaPanel.getState().previewOpponents.length, 5, '换一批后 previewOpponents 应为新小队');
                });
            })
            .then(function() {
                commitPrimary().click();
                return api.waitFor(function() {
                    return host.enterMessages.length > 0;
                }, 2000, 'fallen enter message sent');
            })
            .then(function() {
                var msg = host.enterMessages[host.enterMessages.length - 1];
                api.assertEqual(msg.cmd, 'enter', '提交消息应为 enter');
                api.assertEqual(msg.cardIndex, cardIdx, '入场应带所选 cardIndex');
                api.assertEqual(msg.cardId, 'fallen-波斯军', 'enter 应只携带权威 cardId');
                api.assert(msg.expr === undefined && msg.deposit === undefined && msg.reward === undefined,
                    '堕落 Web enter 不得携带 expr/deposit/reward');
                api.assertEqual(msg.difficulty, '', 'harness 直开 difficulty 为空串');
                // 现行实现：堕落入场靠 roster 下发，不设 mode/faction/pool 字段（钉现状，非理想协议设计）
                api.assert(msg.mode === undefined, '堕落 enter 现行不携带 mode 字段');
                api.assert(msg.faction === undefined, '堕落 enter 现行不携带 faction 字段');
                api.assert(msg.pool === undefined, '堕落 enter 现行不携带 pool 字段');
                api.assert(msg.roster && msg.roster.length === 5, '堕落 enter 应携带 5 条采样 roster');
                for (var i = 0; i < msg.roster.length; i++) {
                    var entry = msg.roster[i];
                    api.assert(entry.mercId === undefined && entry.kind === undefined, '堕落 roster 条目应为怪物 type 条目');
                    api.assert(/^兵种/.test(String(entry.type || '')), 'roster 条目应携带兵种 type（实际: ' + entry.type + '）');
                    api.assert(entry.level >= 44 && entry.level <= 59, 'roster 条目等级应钳进挑战带 [44,59]（实际: ' + entry.level + '）');
                }
                // 成功回包 closePanel:true → requestClose({dismissReturnStack:true})
                return api.waitFor(function() {
                    return !Panels.getActive || Panels.getActive() !== 'arena';
                }, 2000, 'enter 成功后 panel 关闭').then(function() {
                    var closes = host.sentMessages.filter(function(m) { return m && m.cmd === 'close'; });
                    api.assert(closes.length >= 1 && closes[closes.length - 1].dismissReturnStack === true,
                        'enter 成功关闭应带 dismissReturnStack（清返回链）');
                    api.assert(!closes[closes.length - 1].returnBase, '普通入场关闭不应请求返回基地');
                });
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: fallen-partial-known ──
    // 部分已知 fixture（波斯军 6 sprite）→ 精确出卡集合。
    // 登记为债：跨势力 sprite 污染——波斯军的 6 个 spritename 同时散落在不死军团/方舟/亡灵/僵尸/天网/忍者
    // 的 roster 里（arena-factions.js 注释已标 units 白名单待策划回填），所以 6 个 sprite 点亮 6 张卡。
    function caseFallenPartialKnown(api, host) {
        // [faction, levelMin, levelMax, unitCount(已知单位数)] — 按现行派生 + 稳定排序钉死
        var EXPECTED = [
            ['波斯军', 44, 59, 6],
            ['不死军团', 44, 59, 5],
            ['方舟', 45, 60, 4],
            ['亡灵/僵尸', 60, 60, 1],
            ['天网', 60, 60, 2],
            ['忍者', 60, 60, 3]
        ];
        return Promise.resolve()
            .then(function() {
                var fx = knownFixtures(api);
                host.setFixture('rich');
                host.setKnownEnemies(fx.partial());
                host.resetPreviewState();
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                return waitModeTab(api, 'fallen');
            })
            .then(function() {
                return switchToMode(api, 'fallen');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                api.assertEqual(cards.length, EXPECTED.length, '部分已知（波斯军 6 sprite）应出 6 张卡（含跨势力污染）');
                var expectedByFaction = {};
                for (var e = 0; e < EXPECTED.length; e++) expectedByFaction[EXPECTED[e][0]] = EXPECTED[e];
                for (var i = 0; i < cards.length; i++) {
                    var expected = expectedByFaction[cards[i].faction];
                    api.assert(!!expected, '部分已知出卡应属于固定 6 势力集合：' + cards[i].faction);
                    api.assertEqual(cards[i].levelMin, expected[1], cards[i].faction + ' 挑战带下限（按已知单位派生）');
                    api.assertEqual(cards[i].levelMax, expected[2], cards[i].faction + ' 挑战带上限（按已知单位派生）');
                    api.assertEqual(cards[i].unitCount, expected[3], cards[i].faction + ' 已知单位数');
                }
                // 斯巴达唯一单位 敌人-斯巴达战士 在波斯军 fixture 内（已知），但总单位数 1 < FALLEN_MIN_UNITS → 仍不出卡
                api.assert(findCardIndexByFaction(cards, '斯巴达') < 0, '斯巴达即使唯一单位已知，也应被 FALLEN_MIN_UNITS 过滤');
                api.assert(findCardIndexByFaction(cards, '联合大学') < 0, '联合大学单位未知且总数不足，不应出卡');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: escalation-mode-flow ──
    // 爬升 tab 渲染；卡片与堕落同源 + isEscalation 标记 + 押注经济派生；
    // detail 标题/meta；commit payload 走 mode=escalation + 势力完整单位池（不下发 roster 快照）。
    function caseEscalationModeFlow(api, host) {
        var cardIdx = -1;
        return Promise.resolve()
            .then(function() {
                var fx = knownFixtures(api);
                host.setFixture('rich');
                host.setKnownEnemies(fx.all());
                host.resetPreviewState();
                host.enterMessages = [];
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                return waitModeTab(api, 'escalation');
            })
            .then(function() {
                // 标准模式 batch 的 AS2 preview 先清零，切爬升后验零 AS2 往返
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                host.resetPreviewState();
                return switchToMode(api, 'escalation');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                return api.waitFor(function() {
                    return document.querySelector('#arena-grid .arena-card-portrait-item[data-portrait-ref]');
                }, 3000, '爬升模式卡面头像挂载');
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                api.assertEqual(cards.length, 18, '爬升模式应与堕落同源出 18 张卡');
                for (var i = 0; i < cards.length; i++) {
                    api.assert(cards[i].isEscalation === true, cards[i].faction + ' 爬升卡应带 isEscalation 标记');
                    api.assert(cards[i].isFallen === true, cards[i].faction + ' 爬升卡应复用堕落卡视觉（isFallen=true）');
                }
                // 波斯军：scale=large → maxWaves 10；waveBase=roundTo(59×5×500,100)=147500，
                // deposit=roundTo(waveBase,1000)=148000，reward=waveBase=147500
                cardIdx = findCardIndexByFaction(cards, '波斯军');
                api.assert(cardIdx >= 0, '应找到波斯军爬升卡');
                var c = cards[cardIdx];
                api.assertEqual(c.maxWaves, 10, '波斯军（large）波数上限');
                api.assertEqual(c.deposit, 148000, '波斯军押注派生');
                api.assertEqual(c.reward, 147500, '波斯军波奖励基准');
                api.assertEqual(c.opponentCount, 5, '波斯军起始波人数');
                api.assertEqual(c.expr, '#0@44-59%5', '波斯军合成 expr');
                // 波数档：small=5 / coalition=15（wavesForScale 按手标 scale）
                api.assertEqual(cards[findCardIndexByFaction(cards, '不死军团')].maxWaves, 5, '不死军团（small）波数上限应为 5');
                api.assertEqual(cards[findCardIndexByFaction(cards, '天网')].maxWaves, 15, '天网（coalition）波数上限应为 15');
                api.assertEqual(host.previewMessages.length, 0, '爬升卡预览同为本地采样，零 AS2 preview');
                // 卡片头像逐个异步挂载；等待任意一张就绪不能证明当前断言目标（波斯军）已完成。
                return api.waitFor(function() {
                    return document.querySelector('.arena-card[data-index="' + cardIdx + '"] .arena-card-portrait-item.entity-portrait-art[data-portrait-source]');
                }, 3000, '波斯军爬升卡接入怪物身份头像并保留 fail-soft 来源');
            })
            .then(function() {
                clickCard(cardIdx);
                return api.waitFor(function() {
                    var btn = commitPrimary();
                    return btn && !btn.disabled && document.querySelectorAll('.arena-opp-row-monster').length === 5;
                }, 2000, '波斯军爬升右栏 preview 渲染完成');
            })
            .then(function() {
                return api.waitFor(function() {
                    return document.querySelector('.arena-opp-row-monster .arena-opp-portrait.entity-portrait-art[data-portrait-source]');
                }, 3000, '爬升模式右栏怪物头像');
            })
            .then(function() {
                api.assertEqual(document.getElementById('arena-detail-title').textContent, '波斯军 · 爬升挑战（无限波 · 奖池押注）', '爬升卡右栏标题');
                // 经济上屏唯一归属 CommitBar 状态条（meta 芯片不再复述押金/奖金）
                var commitText = commitStatusText();
                api.assert(commitText.indexOf('押金 148,000') >= 0, 'CommitBar 状态条应含押注');
                api.assert(commitText.indexOf('奖金 147,500') >= 0, 'CommitBar 状态条应含波奖励基准');
                commitPrimary().click();
                return api.waitFor(function() {
                    return host.enterMessages.length > 0;
                }, 2000, 'escalation enter message sent');
            })
            .then(function() {
                var msg = host.enterMessages[host.enterMessages.length - 1];
                api.assertEqual(msg.cmd, 'enter', '提交消息应为 enter');
                api.assertEqual(msg.cardIndex, cardIdx, '入场应带所选 cardIndex');
                api.assertEqual(msg.cardId, 'esc-波斯军', '爬升 enter 应只携带权威 cardId');
                api.assert(msg.mode === undefined && msg.faction === undefined && msg.pool === undefined
                    && msg.baseCount === undefined && msg.baseLevelMin === undefined && msg.baseLevelMax === undefined
                    && msg.maxWaves === undefined && msg.deposit === undefined && msg.reward === undefined,
                    '爬升 pool/波数/经济必须全部由 Host 注入，Web payload 不得出现');
                api.assert(msg.roster === undefined, '爬升 Web enter 不下发 roster 快照');
                return api.waitFor(function() {
                    return !Panels.getActive || Panels.getActive() !== 'arena';
                }, 2000, 'enter 成功后 panel 关闭').then(function() {
                    var closes = host.sentMessages.filter(function(m) { return m && m.cmd === 'close'; });
                    api.assert(closes.length >= 1 && closes[closes.length - 1].dismissReturnStack === true,
                        'enter 成功关闭应带 dismissReturnStack');
                });
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: known-empty-standard-only ──
    // 空态：knownEnemies 全未知 → _knownEnemyCount=0 → 堕落/爬升 tab 结构性缺席；
    // 标准模式不受影响（公开卡回退全 merc 走 AS2 preview）；隐藏警报卡因混编情报不足进失败态。
    function caseKnownEmptyStandardOnly(api, host) {
        return Promise.resolve()
            .then(function() {
                var fx = knownFixtures(api);
                host.setFixture('rich');
                host.setKnownEnemies(fx.none());
                host.resetPreviewState();
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                // 以金钱渲染为 snapshot 已落地标记
                return api.waitFor(function() {
                    var el = document.querySelector('.arena-money-value');
                    return el && el.textContent.indexOf('10,000,000') >= 0;
                }, 2000, 'snapshot applied');
            })
            .then(function() {
                api.assertEqual(window.ArenaPanel.getState().knownEnemyCount, 0, '全未知 fixture 应让 knownEnemyCount=0');
                api.assertEqual(document.querySelectorAll('.arena-mode-tab').length, 2, '全未知时应只剩 2 个 tab');
                api.assert(!!document.querySelector('.arena-mode-tab[data-mode="standard"]'), '标准 tab 应在');
                api.assert(!!document.querySelector('.arena-mode-tab[data-mode="custom"]'), '定制赛 tab 应在（不依赖 rosters）');
                api.assert(!document.querySelector('.arena-mode-tab[data-mode="fallen"]'), '堕落 tab 应缺席');
                api.assert(!document.querySelector('.arena-mode-tab[data-mode="escalation"]'), '爬升 tab 应缺席');
                // debug 出口的保护分支同样拒绝切换
                api.assertEqual(window.ArenaPanel.switchMode('fallen'), 0, '全未知时 switchMode(fallen) 应被 modeAvailable 拒绝');
                api.assertEqual(window.ArenaPanel.getState().activeMode, 'standard', 'activeMode 应保持 standard');
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                var state = window.ArenaPanel.getState();
                api.assertEqual(cards.length, 12, '标准模式仍应出 10 公开 + 2 隐藏卡');
                for (var i = 0; i < 10; i++) {
                    api.assertEqual(state.cardKind[i], 'merc', '全未知时公开卡 ' + i + ' 应回退 merc（decideStandardRosterSquad 恒 null）');
                }
                api.assertEqual(host.previewMessages.length, 10, '全未知时 10 张公开卡全部走 AS2 preview');
                // 隐藏警报卡：混编采样要求 _knownEnemyCount>0 → 失败态「混编情报不足」
                api.assertEqual(state.previewErrorCount, 2, '两张隐藏卡应进 preview 失败态');
                for (var h = 10; h < 12; h++) {
                    var sum = document.getElementById('arena-opp-summary-' + h);
                    api.assert(sum.textContent.indexOf('混编情报不足') >= 0, '隐藏卡 ' + h + ' 摘要应显示混编情报不足');
                }
            })
            .then(function() {
                // 选中失败隐藏卡 → CommitBar 禁用并给出 error 原因
                clickCard(10);
                return waitCommitDisabled(api, '混编情报不足');
            })
            .then(function() {
                // 标准公开卡在富裕状态下选中 → CommitBar 可用
                clickCard(0);
                return waitCommitEnabled(api);
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: enter-fail-toast ──
    // 失败态：mock 桥注入 enter success:false → toast 展示错误文本、panel 保持打开、busy 解除 CommitBar 恢复。
    function caseEnterFailToast(api, host) {
        var errText = '余额校验失败（mock注入）';
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                host.enterMessages = [];
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                clickCard(0);
                return waitCommitEnabled(api);
            })
            .then(function() {
                host.nextEnterError = errText;
                commitPrimary().click();
                return api.waitFor(function() {
                    var toast = document.getElementById('arena-toast');
                    return toast && toast.classList.contains('arena-toast-visible');
                }, 2000, 'enter 失败后 toast 可见');
            })
            .then(function() {
                var toast = document.getElementById('arena-toast');
                api.assertEqual(toast.textContent, errText, 'toast 应展示 AS2 回包的 error 文本');
                api.assert(Panels.getActive && Panels.getActive() === 'arena', 'enter 失败不应关闭 panel');
                var closes = host.sentMessages.filter(function(m) { return m && m.cmd === 'close'; });
                api.assertEqual(closes.length, 0, 'enter 失败不应发送 close');
                // busy 解除 → CommitBar 恢复可用（preview cache 仍在、选中保持）
                return waitCommitEnabled(api);
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: keyboard-baseline ──
    // 键盘基线（P2 维度）：
    //   ① 可点控件全部是原生 <button type="button">（Enter/Space 激活由浏览器默认语义保证）；
    //   ② 无正 tabindex（不破坏自然 Tab 顺序）；关键控件 focus() 可达 = Tab 可停；
    //      目录卡 = div[role=option][tabindex=0]（列表语义，方向键移动选择，提交见 keyboard-commit）；
    //   ③ Web 层不消费 Escape：关闭语义归宿主 panel_esc 通道（已由 esc-close 用例覆盖）；
    //   ④ 合成 keydown 走面板自管 handler：未选中卡 Enter 只选中（本地意图零写入），
    //      已选中卡 Enter/Space 提交 = keyboard-commit 用例覆盖。
    function caseKeyboardBaseline(api, host) {
        return Promise.resolve()
            .then(function() {
                host.setFixture('rich');
                host.resetPreviewState();
                host.enterMessages = [];
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                var panel = document.querySelector('.arena-panel');
                api.assert(!!panel, 'arena-panel 应存在');
                var selectors = ['.arena-mode-tab', '#arena-roll-one', '#arena-reroll-all',
                    '.workbench-close-btn', '.workbench-help-btn', '.arena-decision .workbench-commit-primary',
                    '.item-grid-mode-option'];
                for (var s = 0; s < selectors.length; s++) {
                    var nodes = panel.querySelectorAll(selectors[s]);
                    api.assert(nodes.length > 0, selectors[s] + ' 应存在');
                    for (var n = 0; n < nodes.length; n++) {
                        api.assertEqual(nodes[n].tagName, 'BUTTON', selectors[s] + ' 应为原生 button');
                        api.assertEqual(nodes[n].type, 'button', selectors[s] + ' 应为 type=button（Enter 不触发表单提交）');
                    }
                }
                var tabindexed = panel.querySelectorAll('[tabindex]');
                for (var t = 0; t < tabindexed.length; t++) {
                    api.assert(parseInt(tabindexed[t].getAttribute('tabindex'), 10) <= 0,
                        '不应使用正 tabindex 破坏自然 Tab 顺序（' + tabindexed[t].className + '）');
                }
                // 目录卡列表语义：role=option + tabindex=0 + aria-selected
                var card0 = document.querySelector('#arena-grid .arena-card[data-index="0"]');
                api.assertEqual(card0.getAttribute('role'), 'option', '目录卡应为 role=option');
                api.assertEqual(card0.getAttribute('tabindex'), '0', '目录卡应 tabindex=0（Tab 可停）');
                api.assertEqual(card0.getAttribute('aria-selected'), 'false', '未选中卡 aria-selected=false');
                card0.focus();
                api.assert(document.activeElement === card0, '目录卡应可 focus（Tab 可停）');
                var firstTab = document.querySelector('.arena-mode-tab[data-mode="standard"]');
                firstTab.focus();
                api.assert(document.activeElement === firstTab, '模式 tab 应可 focus（Tab 可停）');
            })
            .then(function() {
                // Esc：Web 层无 keydown Escape 处理 → panel 保持打开（宿主下发 panel_esc 才关闭）
                document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
                api.assert(Panels.getActive && Panels.getActive() === 'arena', 'Web 层 Escape keydown 不应关闭 panel（Esc 归宿主 panel_esc 通道）');
                // 未选中卡上的合成 Enter：只选中（本地意图），不发 enter
                var before = host.enterMessages.length;
                var card0 = document.querySelector('#arena-grid .arena-card[data-index="0"]');
                card0.focus();
                card0.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                api.assertEqual(host.enterMessages.length, before, '未选中卡 Enter 只选中、不应触发挑战');
                api.assertEqual(window.ArenaPanel.getState().selectedCardIdx, 0, '未选中卡 Enter 应完成选中');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: overflow-1024 ──
    // 1024×576 逻辑画布（QA 模式 viewport-shell=100vw×100vh，PanelScale 等比缩放不影响布局单位）：
    // 标准/堕落 grid、detail 均不应出现横向溢出。若现行实现存在溢出，按现状断言并注释登记为债。
    function caseOverflow1024(api, host) {
        return Promise.resolve()
            .then(function() {
                var fx = knownFixtures(api);
                host.setFixture('rich');
                host.setKnownEnemies(fx.all());
                host.resetPreviewState();
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                assertNoHorizontalOverflow(api, '.arena-panel', '标准模式面板画布');
                assertNoHorizontalOverflow(api, '.arena-panel .workbench-header', '壳 header（tabs/密度/帮助/关闭）');
                assertNoHorizontalOverflow(api, '#arena-grid-view', '标准模式浏览面');
                assertNoHorizontalOverflow(api, '#arena-grid', '标准模式卡片网格');
                return switchToMode(api, 'fallen');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                // 18 张堕落卡 → arena-grid-scroll 纵向滚动布局
                api.assert(document.getElementById('arena-grid').classList.contains('arena-grid-scroll'), '18 张卡应切纵向滚动布局');
                assertNoHorizontalOverflow(api, '#arena-grid', '堕落模式卡片网格（18 卡滚动态）');
                var cards = window.ArenaPanel.getCards();
                var idx = findCardIndexByFaction(cards, '波斯军');
                clickCard(idx);
                return api.waitFor(function() {
                    return document.querySelectorAll('.arena-opp-row-monster').length === 5;
                }, 2000, '波斯军右栏 preview 渲染');
            })
            .then(function() {
                assertNoHorizontalOverflow(api, '.arena-decision', '右栏决策面');
                assertNoHorizontalOverflow(api, '#arena-opponents', '右栏对手列表');
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    // ── case: long-text-clipping ──
    // 长中文文案：按现行 CSS 契约（nowrap + ellipsis + hidden）裁剪，视觉不失控外溢。
    // 取现行实现里的最长文案组合：爬升 detail 标题（势力名 · 爬升挑战（无限波 · 奖池押注））、
    // meta 芯片行、势力 rank（.arena-card-rank-faction）、grid 摘要（实体×N · 长单位名）。
    function caseLongTextClipping(api, host) {
        return Promise.resolve()
            .then(function() {
                var fx = knownFixtures(api);
                host.setFixture('rich');
                host.setKnownEnemies(fx.all());
                host.resetPreviewState();
                host.open();
                return waitPanelActive(api);
            })
            .then(function() {
                return waitModeTab(api, 'escalation');
            })
            .then(function() {
                return switchToMode(api, 'escalation');
            })
            .then(function() {
                return waitBatchPreviewReady(api);
            })
            .then(function() {
                var cards = window.ArenaPanel.getCards();
                var idx = findCardIndexByFaction(cards, '亡灵/僵尸'); // 最长势力名（含斜杠）
                api.assert(idx >= 0, '应找到亡灵/僵尸爬升卡');
                clickCard(idx);
                return api.waitFor(function() {
                    return document.querySelectorAll('.arena-opp-row-monster').length === cards[idx].opponentCount;
                }, 2000, '亡灵/僵尸右栏 preview 渲染');
            })
            .then(function() {
                var title = document.getElementById('arena-detail-title');
                api.assertEqual(title.textContent, '亡灵/僵尸 · 爬升挑战（无限波 · 奖池押注）', '最长右栏标题文本');
                var ts = getComputedStyle(title);
                api.assertEqual(ts.whiteSpace, 'nowrap', '标题应按单行裁剪');
                api.assertEqual(ts.textOverflow, 'ellipsis', '标题应以省略号裁剪');
                api.assert(ts.overflow === 'hidden' || ts.overflowX === 'hidden', '标题应隐藏外溢内容');
                var titleBlock = document.querySelector('.arena-detail-title-block');
                api.assert(title.getBoundingClientRect().right <= titleBlock.getBoundingClientRect().right + 1,
                    '标题视觉边界不应越出标题块');
                var meta = document.getElementById('arena-detail-meta');
                api.assert(meta.scrollWidth <= meta.clientWidth + 1, 'meta 芯片行不应横向撑破');
                var chips = meta.querySelectorAll('.arena-meta-chip');
                for (var i = 0; i < chips.length; i++) {
                    api.assert(chips[i].getBoundingClientRect().right <= meta.getBoundingClientRect().right + 1,
                        'meta 芯片 ' + i + ' 不应越出 meta 行（' + chips[i].textContent + '）');
                }
                // P2：无「返回」——选中即预览；改选他卡验证右栏随之切换即可（目录始终可见）
                var nextIdx = findCardIndexByFaction(window.ArenaPanel.getCards(), '波斯军');
                clickCard(nextIdx);
                return api.waitFor(function() {
                    return document.getElementById('arena-detail-title').textContent.indexOf('波斯军') === 0;
                }, 2000, '改选后右栏标题切换');
            })
            .then(function() {
                var cardEls = document.querySelectorAll('#arena-grid .arena-card');
                api.assertEqual(cardEls.length, 18, '爬升 grid 应渲染 18 张卡');
                for (var i = 0; i < cardEls.length; i++) {
                    var cardRect = cardEls[i].getBoundingClientRect();
                    var rank = cardEls[i].querySelector('.arena-card-rank-faction');
                    api.assert(!!rank, '爬升卡 ' + i + ' 应有势力 rank');
                    api.assert(rank.getBoundingClientRect().right <= cardRect.right + 1,
                        '势力 rank 不应越出卡片（' + rank.textContent + '）');
                    var sum = document.getElementById('arena-opp-summary-' + i);
                    api.assert(!!sum, '爬升卡 ' + i + ' 应有摘要');
                    var ss = getComputedStyle(sum);
                    api.assertEqual(ss.textOverflow, 'ellipsis', '摘要应以省略号裁剪');
                    api.assert(sum.getBoundingClientRect().right <= cardRect.right + 1,
                        '摘要不应越出卡片（' + sum.textContent + '）');
                }
            })
            .then(function() { return { pass: true }; })
            .catch(function(e) { return { pass: false, detail: String(e.message || e) }; });
    }

    return {
        runSuite: runSuite
    };
})();
