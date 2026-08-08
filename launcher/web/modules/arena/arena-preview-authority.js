/**
 * arena-preview-authority.js — 竞技场面板 P4 工程拆分 · preview 权威通路：snapshot / preview 请求与三元组守卫 / 本地 roster 采样。
 *
 * 本文件由 modules/arena-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议 payload /
 * DOM id·class 契约 / QA 断言不变）。转换规则：原顶层 `var _x` 状态 → ArenaCore.state._x（本文件内
 * 以 `S._x` 访问）；跨模块函数/常量引用 → `模块全局.名字`。加载顺序由 panels-lazy-registry 的
 * arena 注册项与 arena/dev/harness.html script 区固定（与本文件守卫一致）。
 * 依赖守卫：arena/arena-core.js。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined' || !window.ArenaCore) {
        throw new Error('arena/arena-preview-authority.js 需要先加载 arena/arena-core.js（共享基座：状态容器 + 跨模块工具 + 共享常量）');
    }

    var S = ArenaCore.state; // 共享状态（原顶层 var _x）


    function sendCustomRequest(cmd, payload, cb) {
        var reqId = 'arena_custom_' + (++S._reqSeq) + '_' + S._session;
        S._pendingReq[reqId] = function(data) {
            if (typeof cb === 'function') cb(data || {});
        };
        payload = payload || {};
        payload.type = 'panel';
        payload.panel = 'arena';
        payload.cmd = cmd;
        payload.callId = reqId;
        Bridge.send(payload);
    }

    // ════════════════════════════════════════════════════════════════════════════
    // Snapshot
    // ════════════════════════════════════════════════════════════════════════════
    function requestSnapshot() {
        var reqId = 'arena_snap_' + (++S._reqSeq) + '_' + S._session;
        var snapSession = S._session; // 闭包捕获，跨 panel reopen 不要触发旧 session 的 batch
        S._pendingReq[reqId] = function(data) {
            if (data.success && data.snapshot) {
                S._snapshot = data.snapshot;
                setKnownEnemies(S._snapshot.knownEnemies);
                if (S._activeMode === 'standard') {
                    ArenaChallengeBrowser.rebuildForMode('standard');
                } else if (!ArenaShell.modeAvailable(S._activeMode)) {
                    ArenaChallengeBrowser.rebuildForMode('standard');
                }
                ArenaShell.refreshModeTabs();
                ArenaChallengeBrowser.updateMoneyDisplay(S._snapshot.money);
                ArenaChallengeBrowser.updateCardStates();
                if (S._shell) S._shell.setStatus('就绪', Workbench.WorkbenchState.READY);
                // snapshot 成功才发 batch preview：① 提早发会让 preview 回包后 updateCommitBar 拿不到 money
                //   导致主 CTA 在 money 未到时一闪亮一下；② snapshot 失败时 panel 实际不可用，preview 也无意义
                if (snapSession === S._session) {
                    batchRequestPreview();
                }
            } else if (S._shell) {
                S._shell.setStatus('读取失败', Workbench.WorkbenchState.ERROR);
            }
        };
        Bridge.send({
            type: 'panel',
            panel: 'arena',
            cmd: 'snapshot',
            callId: reqId
        });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // Batch Preview（panel open 时并发抽当前卡片集）
    // ════════════════════════════════════════════════════════════════════════════
    function batchRequestPreview() {
        if (S._activeMode === 'custom') {
            ArenaCustomEditor.refreshCustomMatchCard();
            return;
        }
        for (var i = 0; i < S._activeCards.length; i++) {
            requestPreviewForCard(i);
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    // Preview（按 cardIdx 抽签 + 缓存）
    //
    // 触发路径：
    //   1. snapshot 成功 → batchRequestPreview() → 当前卡片集并发首抽
    //   2. 左栏控件条「↻ 换一批」→ onRollAgain → 选中卡强制重抽（清 cache/pending，gen+1）
    //   3. cache miss（选中时 batch 仍 pending 或失败重试）→ renderDecisionForCard / onSummaryRetry
    //
    // dedup：_previewPending[cardIdx] 已存在则 return，避免一卡多飞造成 reqId 失效。
    // 双区同步：回包写 _previewCache → renderCardSummary 同步目录摘要；若用户当前选中的
    //   就是该卡（_selectedCardIdx === cardIdx），还会同步右栏 preview 与 CommitBar。
    // 迟到回包隔离（P0 裁决 3，模式 + 稳定卡 ID + session/generation 三元组）：
    //   pending 记录携带 {reqId, mode, cardKey, gen}（reqId 内含 _session）；回包时逐字段
    //   比对当前记录与活卡，任一漂移即丢弃——模式切换/全部重抽（记录清空）、单卡重抽
    //   （gen 递增）、卡片集重映射（cardKey 漂移）均不会把旧对手写进新决策面。
    // ════════════════════════════════════════════════════════════════════════════
    function requestPreviewForCard(cardIdx) {
        if (S._previewPending[cardIdx] !== undefined) return; // dedup（仅 merc 异步路径用）
        var card = S._activeCards[cardIdx];
        if (!card) return;

        // 决定本卡种类（首抽 / 换一批后未决定时）。
        //   - 堕落卡：恒怪物，且锁定从本卡势力采样（非随机势力）；采样失败 → 报错，绝不退回 merc 路径
        //     （否则合成 expr 会被 AS2 当真去抽人形佣兵，串成人形对手）。
        //   - 标准卡：按 session 固定角色计划执行（7 merc / 2 monster / 1 mixed，位置随机）。
        if (S._cardKind[cardIdx] === undefined) {
            if (card.isFallen) {
                var fsq = sampleFactionSquad(card.faction, card.levelMin, card.levelMax, card.opponentCount);
                if (fsq) { S._cardKind[cardIdx] = 'monster'; S._monsterSquad[cardIdx] = fsq; }
                else {
                    S._previewError[cardIdx] = '该势力暂无可用单位';
                    ArenaChallengeBrowser.renderCardSummary(cardIdx);
                    ArenaChallengeBrowser.updateCardStates();
                    if (S._selectedCardIdx === cardIdx) {
                        S._detailOpponentsEl.innerHTML = '<div class="arena-opponents-error">该势力暂无可用单位</div>';
                    }
                    return;
                }
            } else if (card.isHiddenChallenge) {
                var mixed = sampleHiddenMixedSquad(card);
                if (mixed) { S._cardKind[cardIdx] = 'mixed'; S._monsterSquad[cardIdx] = mixed; }
                else {
                    S._previewError[cardIdx] = '混编情报不足';
                    ArenaChallengeBrowser.renderCardSummary(cardIdx);
                    ArenaChallengeBrowser.updateCardStates();
                    return;
                }
            } else {
                var decided = decideStandardRosterSquad(card);
                if (decided) { S._cardKind[cardIdx] = decided.kind || 'monster'; S._monsterSquad[cardIdx] = decided; }
                else { S._cardKind[cardIdx] = 'merc'; }
            }
        }
        if (S._cardKind[cardIdx] === 'monster' || S._cardKind[cardIdx] === 'mixed') {
            applyMonsterPreview(cardIdx); // web 本地采样渲染，无 AS2 preview 往返
            return;
        }

        var reqId = 'arena_prev_' + (++S._reqSeq) + '_' + S._session;
        // 隔离三元组：reqId（含 session）+ 发出时模式 + 稳定卡 ID + generation
        var isolate = {
            reqId: reqId,
            mode: S._activeMode,
            cardKey: ArenaChallengeBrowser.stableCardKey(card),
            gen: S._previewGen[cardIdx] || 0
        };
        S._previewPending[cardIdx] = isolate;
        delete S._previewError[cardIdx]; // 清旧错误，让摘要进 loading 态

        // 摘要 UI 进 loading 态（覆盖上次失败 / 上次结果）
        var sumEl = document.getElementById('arena-opp-summary-' + cardIdx);
        if (sumEl) {
            sumEl.className = 'arena-card-opponents arena-card-opponents-loading';
            sumEl.textContent = '抽取中…';
            sumEl.onclick = null;
        }

        S._pendingReq[reqId] = function(data) {
            var cur = S._previewPending[cardIdx];
            // 三元组隔离：记录被清（模式切换/全部重抽/会话复位）、被换（单卡重抽 gen+1）、
            // 模式已变或同位卡身份漂移，一律丢弃迟到回包
            if (!cur || cur.reqId !== isolate.reqId || cur.mode !== isolate.mode
                    || cur.gen !== isolate.gen || S._activeMode !== isolate.mode) return;
            var liveCard = S._activeCards[cardIdx];
            if (!liveCard || ArenaChallengeBrowser.stableCardKey(liveCard) !== isolate.cardKey) return;
            delete S._previewPending[cardIdx];

            if (!data.success || !data.opponents) {
                S._previewError[cardIdx] = data.error || '抽取失败';
                ArenaChallengeBrowser.renderCardSummary(cardIdx);
                ArenaChallengeBrowser.updateCardStates(); // 失败 → 选中该卡时 CommitBar 给 error 原因且禁用
                if (S._selectedCardIdx === cardIdx) {
                    S._detailOpponentsEl.innerHTML = '<div class="arena-opponents-error">' + ArenaCore.escapeHtml(S._previewError[cardIdx]) + '</div>';
                }
                return;
            }

            S._previewCache[cardIdx] = data.opponents;
            ArenaChallengeBrowser.renderCardSummary(cardIdx);
            ArenaChallengeBrowser.updateCardStates(); // 刷新 CommitBar / 选中卡可用性

            if (S._selectedCardIdx === cardIdx) {
                S._previewOpponents = data.opponents;
                ArenaChallengeBrowser.renderDetailMeta(liveCard, data.opponents);
                ArenaChallengeBrowser.renderOpponents(data.opponents);
            }
        };

        Bridge.send({
            type: 'panel',
            panel: 'arena',
            cmd: 'preview',
            callId: reqId,
            cardIndex: cardIdx,
            cardId: card.id
        });
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 元战队 / 混编采样 — M2：web 本地从 window.ArenaMetaRosters 抽，无 AS2 往返
    // ════════════════════════════════════════════════════════════════════════════
    // 按标准卡角色计划决定本卡是否为 mixed / 怪物小队；返回 {kind,faction,opponents} 或 null（=走 merc）。
    function decideStandardRosterSquad(card) {
        var rosters = (typeof window !== 'undefined' && window.ArenaMetaRosters)
            ? window.ArenaMetaRosters.factions : null;
        if (!rosters) return null;                       // 无数据（如 QA harness 未载）→ 恒 merc
        if (S._knownEnemyCount <= 0) return null;           // 未击杀过对应 spritename → 不混入怪物，避免剧透

        if (card.standardRole === 'mixed') {
            var mixed = sampleMixedSquad(card);
            if (mixed) return mixed;
            return null;
        }
        if (card.standardRole === 'monster') {
            var monster = sampleMonsterTeamSquad(card);
            if (!monster) monster = sampleMonsterSquad(rosters, card.levelMin, card.levelMax, card.opponentCount);
            if (monster) monster.kind = 'monster';
            return monster;
        }
        return null;
    }

    // 隐藏警报卡：优先走已知的真实关卡组合；没有可用组合时才回退到已知兵种池临时混编。
    function sampleHiddenMixedSquad(card) {
        return sampleMixedSquad(card);
    }

    function sampleMixedSquad(card) {
        var mercSquad = sampleMercenaryMixedSquad(card);
        if (mercSquad) return mercSquad;
        var teamSquad = sampleMixedMetaTeamSquad(card); // 无可用佣兵时才允许剧情/关卡人形模板兜底
        if (teamSquad) return teamSquad;
        return sampleSyntheticMixedSquad(card);
    }

    function sampleMercenaryMixedSquad(card) {
        var rosters = ArenaShell.rostersAvailable() ? window.ArenaMetaRosters.factions : null;
        if (!rosters || S._knownEnemyCount <= 0) return null;
        var mercPool = mercenaryPoolForBand(card.levelMin, card.levelMax);
        var pools = splitRosterPools(rosters, card.levelMin, card.levelMax);
        if (!mercPool.length || !pools.nonHuman.length) return null;

        var counts = mixedRosterCounts(card);
        var opponents = weightedMercenarySample(mercPool, counts.humanoid);
        var monsters = sampleNonHumanTeamOpponents(card, counts.monster, ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS);
        var monsterSource = 'meta-team';
        if (!monsters || !monsters.length) {
            monsters = weightedSample(pools.nonHuman, card.levelMin, card.levelMax, counts.monster);
            monsterSource = 'unit-pool';
        }
        for (var i = 0; i < monsters.length; i++) {
            opponents.push(monsters[i]);
        }
        shuffleInPlace(opponents);
        return { kind: 'mixed', faction: '混编', source: 'mercenary', monsterSource: monsterSource, equivalentCount: card.opponentCount, opponents: opponents };
    }

    function sampleMixedMetaTeamSquad(card) {
        var teams = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.teams)
            ? window.ArenaMetaRosters.teams : null;
        if (!teams || !teams.length || S._knownEnemyCount <= 0) return null;

        var candidates = [];
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            if (!team || team.unitCount < 2 || team.unitCount > ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS) continue;
            if (team.levelMax < card.levelMin || team.levelMin > card.levelMax) continue;
            if (!isKnownTeam(team)) continue;
            if (!teamHasHumanoidAndNonHuman(team)) continue;
            candidates.push({ team: team, weight: hiddenTeamWeight(team, card) });
        }
        if (!candidates.length) return null;

        var chosen = weightedTeamPick(candidates);
        var opponents = expandTeamOpponents(chosen);
        if (opponents.length < 2) return null;
        return {
            kind: 'mixed',
            faction: '混编',
            source: 'meta-team',
            teamId: chosen.id || '',
            sourceName: chosen.sourceName || chosen.sourceStage || '',
            equivalentCount: card.opponentCount,
            opponents: opponents
        };
    }

    function sampleSyntheticMixedSquad(card) {
        var rosters = ArenaShell.rostersAvailable() ? window.ArenaMetaRosters.factions : null;
        if (!rosters || S._knownEnemyCount <= 0) return null;
        var humanoidPool = humanoidTemplatePoolForBand(card.levelMin, card.levelMax);
        var pools = splitRosterPools(rosters, card.levelMin, card.levelMax);
        if (!humanoidPool.length || !pools.nonHuman.length) return null;

        var counts = mixedRosterCounts(card);
        var opponents = weightedSample(humanoidPool, card.levelMin, card.levelMax, counts.humanoid);
        var monsters = sampleNonHumanTeamOpponents(card, counts.monster, ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS);
        var monsterSource = 'meta-team';
        if (!monsters || !monsters.length) {
            monsters = weightedSample(pools.nonHuman, card.levelMin, card.levelMax, counts.monster);
            monsterSource = 'unit-pool';
        }
        for (var i = 0; i < monsters.length; i++) {
            opponents.push(monsters[i]);
        }
        shuffleInPlace(opponents);
        return { kind: 'mixed', faction: '混编', source: 'synthetic', monsterSource: monsterSource, equivalentCount: card.opponentCount, opponents: opponents };
    }

    function sampleMonsterTeamSquad(card) {
        var groupTarget = Math.max(1, Math.min(ArenaChallengeBrowser.STANDARD_OPPONENT_CAP,
            Math.round(Number(card.opponentCount) || 1)));
        var teams = pickKnownNonHumanTeams(card.levelMin, card.levelMax, groupTarget, ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS);
        if (!teams || !teams.length) return null;

        var opponents = [];
        var teamIds = [];
        var factionMap = {};
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            var groupOpponents = expandTeamOpponents(team, ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS, i + 1);
            if (!groupOpponents || groupOpponents.length < 2) continue;
            teamIds.push(team.id || '');
            if (team.faction) factionMap[team.faction] = true;
            for (var j = 0; j < groupOpponents.length; j++) {
                opponents.push(groupOpponents[j]);
            }
        }
        if (!opponents.length) return null;
        return {
            kind: 'monster',
            faction: summarizeMonsterFactions(factionMap),
            source: 'meta-team',
            teamId: teamIds.join('|'),
            sourceName: teams.length > 1 ? '多组怪物队' : (teams[0].sourceName || teams[0].sourceStage || ''),
            equivalentCount: teams.length,
            opponents: opponents
        };
    }

    function sampleNonHumanTeamOpponents(card, equivalentCount, maxUnits) {
        var groupTarget = Math.max(1, Math.min(ArenaChallengeBrowser.STANDARD_OPPONENT_CAP,
            Math.round(Number(equivalentCount) || 1)));
        var teams = pickKnownNonHumanTeams(card.levelMin, card.levelMax, groupTarget, maxUnits);
        if (!teams || !teams.length) return null;

        var opponents = [];
        var groups = 0;
        for (var i = 0; i < teams.length; i++) {
            var groupOpponents = expandTeamOpponents(teams[i], maxUnits, i + 1);
            if (!groupOpponents || groupOpponents.length < 2) continue;
            groups++;
            for (var j = 0; j < groupOpponents.length; j++) {
                opponents.push(groupOpponents[j]);
            }
        }
        return groups >= groupTarget ? opponents : null;
    }

    function pickKnownNonHumanTeam(levelMin, levelMax, equivalentCount, maxUnits) {
        var teams = pickKnownNonHumanTeams(levelMin, levelMax, 1, maxUnits, equivalentCount);
        return teams && teams.length ? teams[0] : null;
    }

    function pickKnownNonHumanTeams(levelMin, levelMax, groupCount, maxUnits, equivalentCount) {
        var candidates = collectKnownNonHumanTeamCandidates(levelMin, levelMax, equivalentCount || 1, maxUnits);
        if (!candidates.length) return null;
        groupCount = Math.max(1, Math.min(ArenaChallengeBrowser.STANDARD_OPPONENT_CAP, Math.round(Number(groupCount) || 1)));
        var picked = [];
        var used = {};
        for (var i = 0; i < groupCount; i++) {
            var team = weightedTeamPick(candidates, used);
            if (!team) break;
            picked.push(team);
            used[teamPickKey(team)] = true;
        }
        return picked;
    }

    function collectKnownNonHumanTeamCandidates(levelMin, levelMax, equivalentCount, maxUnits) {
        var teams = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.teams)
            ? window.ArenaMetaRosters.teams : null;
        if (!teams || !teams.length || S._knownEnemyCount <= 0) return [];
        maxUnits = Math.max(2, Math.min(ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS, Math.round(Number(maxUnits) || ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS)));

        var candidates = [];
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            if (!team || team.unitCount < 2 || team.unitCount > maxUnits) continue;
            if (team.levelMax < levelMin || team.levelMin > levelMax) continue;
            if (!teamHasOnlyNonHuman(team)) continue;
            if (!isKnownTeam(team)) continue;
            candidates.push({
                team: team,
                weight: monsterTeamWeight(team, levelMin, levelMax, equivalentCount)
            });
        }
        return candidates;
    }

    function summarizeMonsterFactions(factionMap) {
        var count = 0;
        var last = '';
        for (var key in factionMap) {
            if (!factionMap.hasOwnProperty(key)) continue;
            count++;
            last = key;
        }
        if (count === 1) return last || '怪物组';
        if (count > 1) return '混合怪物组';
        return '怪物组';
    }

    function teamPickKey(team) {
        if (!team) return '';
        return String(team.id || ((team.sourceStage || '') + '#' + (team.sourceName || '') + '#' + (team.levelMin || '') + '-' + (team.levelMax || '')));
    }

    function mixedRosterCounts(card) {
        var total = Math.max(2, Math.min(ArenaChallengeBrowser.STANDARD_OPPONENT_CAP, Math.round(Number(card.opponentCount) || 2)));
        if (card && (card.isHiddenChallenge || card.requiresMixedRoster)) {
            var hiddenHumanoid = Math.max(1, Math.ceil(total / 2));
            return { humanoid: hiddenHumanoid, monster: Math.max(1, total - hiddenHumanoid) };
        }
        return { humanoid: 1, monster: Math.max(1, total - 1) };
    }

    function mercenaryPoolForBand(levelMin, levelMax) {
        var mercs = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.mercenaries)
            ? window.ArenaMetaRosters.mercenaries : null;
        if (!mercs || !mercs.length) return [];
        var idCounts = {};
        for (var c = 0; c < mercs.length; c++) {
            var countedId = String(mercs[c] && mercs[c].id);
            idCounts[countedId] = (idCounts[countedId] || 0) + 1;
        }
        var pool = [];
        for (var i = 0; i < mercs.length; i++) {
            var merc = mercs[i];
            if (idCounts[String(merc && merc.id)] !== 1) continue;
            var lvl = Number(merc.level) || 1;
            if (lvl < levelMin || lvl > levelMax) continue;
            pool.push(merc);
        }
        return pool;
    }

    function weightedMercenarySample(pool, count) {
        var totalW = 0;
        for (var k = 0; k < pool.length; k++) totalW += (pool[k].weight || 1);
        var opponents = [];
        var used = {};
        for (var n = 0; n < count && n < pool.length; n++) {
            var pick = null;
            for (var guard = 0; guard < 20 && !pick; guard++) {
                var r = Math.random() * totalW, acc = 0;
                for (var j = 0; j < pool.length; j++) {
                    acc += (pool[j].weight || 1);
                    if (r <= acc) { pick = pool[j]; break; }
                }
                if (pick && used[pick.id]) pick = null;
            }
            if (!pick) {
                for (var f = 0; f < pool.length; f++) {
                    if (!used[pool[f].id]) { pick = pool[f]; break; }
                }
            }
            if (!pick) break;
            used[pick.id] = true;
            opponents.push({
                name: pick.name,
                level: Number(pick.level) || 1,
                mercId: pick.id,
                spritename: '主角-男',
                gender: pick.gender || '',
                isMonster: true,
                humanoid: true,
                rosterKind: 'humanoid',
                source: 'mercenary'
            });
        }
        return opponents;
    }

    function humanoidTemplatePoolForBand(levelMin, levelMax) {
        var teams = (typeof window !== 'undefined' && window.ArenaMetaRosters && window.ArenaMetaRosters.teams)
            ? window.ArenaMetaRosters.teams : null;
        if (!teams || !teams.length) return [];
        var pool = [];
        for (var i = 0; i < teams.length; i++) {
            var team = teams[i];
            if (!team || team.levelMax < levelMin || team.levelMin > levelMax) continue;
            var members = team.members || [];
            for (var m = 0; m < members.length; m++) {
                var member = members[m];
                if (!isHumanoidTemplateUnit(member)) continue;
                var unit = {
                    type: member.type,
                    name: member.name,
                    spritename: member.spritename,
                    gender: member.gender || '',
                    minLevel: Number(member.level) || levelMin,
                    maxLevel: Number(member.level) || levelMax,
                    weight: Math.max(1, Number(member.count) || 1),
                    humanoid: true
                };
                var parameters = member.Parameters || member.parameters || member['参数'];
                if (ArenaCustomEditor.customHasParameters(parameters)) unit.parameters = ArenaCustomEditor.cloneCustomParameters(parameters);
                pool.push(unit);
            }
        }
        return pool;
    }

    function isKnownTeam(team) {
        var members = (team && team.members) || [];
        if (!members.length) return false;
        for (var i = 0; i < members.length; i++) {
            if (!isKnownEnemyUnit(members[i])) return false;
        }
        return true;
    }

    function teamHasHumanoidAndNonHuman(team) {
        var members = (team && team.members) || [];
        var humanoid = false, nonHuman = false;
        for (var i = 0; i < members.length; i++) {
            var kind = rosterKindForUnit(members[i]);
            if (kind === 'humanoid') humanoid = true;
            else if (kind === 'nonhuman') nonHuman = true;
        }
        return humanoid && nonHuman;
    }

    function teamHasOnlyNonHuman(team) {
        var members = (team && team.members) || [];
        if (!members.length) return false;
        for (var i = 0; i < members.length; i++) {
            if (rosterKindForUnit(members[i]) !== 'nonhuman') return false;
        }
        return true;
    }

    function hiddenTeamWeight(team, card) {
        var targetPower = Math.max(1, card.opponentCount) * ((card.levelMin + card.levelMax) / 2);
        var power = Number(team.powerRating);
        if (isNaN(power) || power <= 0) power = estimateTeamPower(team);
        var closeness = targetPower / (targetPower + Math.abs(power - targetPower));
        var groupBonus = team.unitCount > card.opponentCount ? 1.2 : 1;
        return Math.max(0.05, closeness) * groupBonus;
    }

    function monsterTeamWeight(team, levelMin, levelMax, equivalentCount) {
        var levelBase = (levelMin + levelMax) / 2;
        var targetPower = Math.max(1, Number(equivalentCount) || 1) * levelBase;
        var power = Number(team.powerRating);
        if (isNaN(power) || power <= 0) power = estimateTeamPower(team);
        var closeness = targetPower / (targetPower + Math.abs(power - targetPower));
        var sizeBonus = team.unitCount > Math.max(1, equivalentCount) ? 1.15 : 1;
        var factionBonus = team.faction && team.faction !== 'unknown' ? 1.05 : 1;
        return Math.max(0.05, closeness) * sizeBonus * factionBonus;
    }

    function estimateTeamPower(team) {
        var members = (team && team.members) || [];
        var sum = 0;
        for (var i = 0; i < members.length; i++) {
            sum += (Number(members[i].level) || 1) * Math.max(1, Number(members[i].count) || 1);
        }
        return sum || 1;
    }

    function weightedTeamPick(candidates, used) {
        var pool = [];
        for (var p = 0; p < candidates.length; p++) {
            var key = teamPickKey(candidates[p].team);
            if (!used || !used[key]) pool.push(candidates[p]);
        }
        if (!pool.length) pool = candidates;

        var total = 0;
        for (var i = 0; i < pool.length; i++) total += pool[i].weight || 1;
        var r = Math.random() * total, acc = 0;
        for (var j = 0; j < pool.length; j++) {
            acc += pool[j].weight || 1;
            if (r <= acc) return pool[j].team;
        }
        return pool[0].team;
    }

    function expandTeamOpponents(team, maxUnits, groupInstance) {
        var limit = Math.max(1, Math.min(ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS,
            Math.round(Number(maxUnits) || ArenaChallengeBrowser.HIDDEN_MIXED_TEAM_MAX_UNITS)));
        var out = [];
        var members = (team && team.members) || [];
        var baseGroupId = String((team && team.id) || ((team && team.sourceStage) ? (team.sourceStage + '#' + team.sourceName) : '') || 'monster-team');
        var groupId = groupInstance != null ? (baseGroupId + '@' + groupInstance) : baseGroupId;
        var groupName = String((team && (team.sourceName || team.sourceStage || team.faction)) || '关卡怪物组');
        var groupTotal = Math.min(limit, Math.max(1, Number(team && team.unitCount) || limit));
        for (var i = 0; i < members.length; i++) {
            var member = members[i];
            var count = Math.max(1, Math.round(Number(member.count) || 1));
            for (var n = 0; n < count && out.length < limit; n++) {
                var opponent = {
                    name: member.name,
                    level: Number(member.level) || 1,
                    type: member.type,
                    spritename: member.spritename,
                    gender: member.gender || '',
                    isMonster: true,
                    rosterKind: rosterKindForUnit(member),
                    sourceGroupId: groupId,
                    sourceGroupName: groupName,
                    sourceGroupMemberIndex: out.length + 1,
                    sourceGroupMemberTotal: groupTotal
                };
                var parameters = member.Parameters || member.parameters || member['参数'];
                if (ArenaCustomEditor.customHasParameters(parameters)) opponent.parameters = ArenaCustomEditor.cloneCustomParameters(parameters);
                out.push(opponent);
            }
        }
        shuffleInPlace(out);
        return out;
    }

    function splitRosterPools(rosters, levelMin, levelMax) {
        var all = [], humanoid = [], nonHuman = [];
        for (var f in rosters) {
            var pool = poolForBand(rosters[f].units, levelMin, levelMax);
            for (var i = 0; i < pool.length; i++) {
                var unit = pool[i];
                all.push(unit);
                if (rosterKindForUnit(unit) === 'humanoid') humanoid.push(unit);
                else if (rosterKindForUnit(unit) === 'nonhuman') nonHuman.push(unit);
            }
        }
        return { all: all, humanoid: humanoid, nonHuman: nonHuman };
    }

    function rosterKindForUnit(unit) {
        if (isHumanoidTemplateUnit(unit)) return 'humanoid';
        return 'nonhuman';
    }

    function isHumanoidRosterUnit(unit) {
        return rosterKindForUnit(unit) === 'humanoid';
    }

    function isHumanoidTemplateUnit(unit) {
        if (!unit) return false;
        if (unit.humanoid === true) return true;
        return /主角/.test(String(unit.spritename || ''));
    }

    function shuffleInPlace(list) {
        for (var i = list.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var t = list[i];
            list[i] = list[j];
            list[j] = t;
        }
    }

    // 从与 [levelMin,levelMax] 重叠的某个势力 roster，按 weight 加权采样 count 个单位（可重复）。
    // 每个单位等级钳进卡片等级带。无重叠势力 → null（该等级带无怪可混，保持 merc）。
    function sampleMonsterSquad(rosters, levelMin, levelMax, count) {
        var eligible = [];
        for (var f in rosters) {
            var pool = poolForBand(rosters[f].units, levelMin, levelMax);
            if (pool.length) eligible.push({ faction: f, pool: pool });
        }
        if (eligible.length === 0) return null;
        var chosen = eligible[Math.floor(Math.random() * eligible.length)];
        return { faction: chosen.faction, opponents: weightedSample(chosen.pool, levelMin, levelMax, count) };
    }

    // 堕落模式（Phase 2）：从指定势力采样（非随机势力）。faction 缺失 / 无等级带重叠单位 → null。
    function sampleFactionSquad(factionName, levelMin, levelMax, count) {
        var factions = ArenaShell.rostersAvailable() ? window.ArenaMetaRosters.factions : null;
        if (!factions || !factions[factionName]) return null;
        var pool = poolForBand(factions[factionName].units, levelMin, levelMax);
        if (!pool.length) return null;
        return { faction: factionName, opponents: weightedSample(pool, levelMin, levelMax, count) };
    }

    // 取势力单位中与 [levelMin,levelMax] 等级带重叠的子池。
    function poolForBand(units, levelMin, levelMax) {
        units = units || [];
        var pool = [];
        for (var i = 0; i < units.length; i++) {
            var u = units[i];
            if (!isKnownEnemyUnit(u)) continue;
            if (u.minLevel <= levelMax && u.maxLevel >= levelMin) pool.push(u);
        }
        return pool;
    }

    function setKnownEnemies(list) {
        S._knownEnemies = {};
        S._knownEnemyCount = 0;
        list = list || [];
        for (var i = 0; i < list.length; i++) {
            var key = String(list[i] || '');
            if (!key || S._knownEnemies[key]) continue;
            S._knownEnemies[key] = true;
            S._knownEnemyCount++;
        }
    }

    function isKnownEnemyUnit(unit) {
        if (!unit || !unit.spritename) return false;
        if (isHumanoidTemplateUnit(unit)) return true; // 佣兵模板由竞技场混编放行；普通怪物仍要求已击杀
        return S._knownEnemies[String(unit.spritename)] === true;
    }

    function rosterDisplaySpritename(unit) {
        var sprite = String(unit && unit.spritename || '');
        if (isHumanoidTemplateUnit(unit) && (sprite === '主角-男' || sprite === '主角-女')) {
            var gender = String(unit && unit.gender || '').trim();
            if (gender === '女') return '主角-女';
            if (gender === '男') return '主角-男';
        }
        return sprite.replace(/^敌人-/, '');
    }

    function filterKnownUnits(units) {
        units = units || [];
        var out = [];
        for (var i = 0; i < units.length; i++) {
            if (isKnownEnemyUnit(units[i])) out.push(units[i]);
        }
        return out;
    }

    // 从单位池按 weight 加权采样 count 个（可重复），每个单位等级钳进 [levelMin,levelMax]。
    function weightedSample(pool, levelMin, levelMax, count) {
        var totalW = 0;
        for (var k = 0; k < pool.length; k++) totalW += (pool[k].weight || 1);
        var opponents = [];
        for (var n = 0; n < count; n++) {
            var r = Math.random() * totalW, acc = 0, pick = pool[0];
            for (var j = 0; j < pool.length; j++) {
                acc += (pool[j].weight || 1);
                if (r <= acc) { pick = pool[j]; break; }
            }
            var lo = Math.max(pick.minLevel, levelMin), hi = Math.min(pick.maxLevel, levelMax);
            if (hi < lo) hi = lo;
            var lvl = lo + Math.floor(Math.random() * (hi - lo + 1));
            var opponent = {
                name: pick.name,
                level: lvl,
                type: pick.type,
                spritename: pick.spritename,
                gender: pick.gender || '',
                isMonster: true,
                rosterKind: isHumanoidRosterUnit(pick) ? 'humanoid' : 'nonhuman'
            };
            var parameters = pick.Parameters || pick.parameters || pick['参数'];
            if (ArenaCustomEditor.customHasParameters(parameters)) opponent.parameters = ArenaCustomEditor.cloneCustomParameters(parameters);
            opponents.push(opponent);
        }
        return opponents;
    }

    // 怪物卡：本地采样结果直接写 cache + 渲染（不发 AS2，无 pending）。
    function applyMonsterPreview(cardIdx) {
        var squad = S._monsterSquad[cardIdx];
        if (!squad) return;
        delete S._previewError[cardIdx];
        delete S._previewPending[cardIdx];
        S._previewCache[cardIdx] = squad.opponents;
        markCardMonster(cardIdx, squad.faction);
        ArenaChallengeBrowser.renderCardSummary(cardIdx);
        ArenaChallengeBrowser.updateCardStates();
        if (S._selectedCardIdx === cardIdx) {
            S._previewOpponents = squad.opponents;
            ArenaChallengeBrowser.renderDetailMeta(S._activeCards[cardIdx], squad.opponents);
            ArenaChallengeBrowser.renderOpponents(squad.opponents);
        }
    }

    // 怪物卡视觉标记：加类 + 把「对手阵容」cap 换成势力名（faction=null 还原为 merc 态）。
    function markCardMonster(cardIdx, faction) {
        var cardEl = S._cardEls[cardIdx];
        if (!cardEl) return;
        var card = S._activeCards[cardIdx];
        var isFallen = !!(card && card.isFallen);
        // 堕落卡建卡即恒紫罗兰；标准卡按本次采样结果开关
        cardEl.classList.toggle('arena-card-monster', !!faction || isFallen);
        if (card && card.isHiddenChallenge) return; // 隐藏卡不公开混编来源，保留「配置保密」
        if (isFallen) return; // 堕落卡的势力名（rank）+「麾下阵容」cap 已在 buildCards 定好，采样回调不覆盖
        var capEl = cardEl.querySelector('.arena-card-opponents-cap');
        if (capEl) capEl.textContent = faction ? ('⚠ ' + faction) : '对手阵容';
    }

    // 导出：仅被其它 arena 模块 / facade 引用的名字
    window.ArenaPreviewAuthority = {
        sendCustomRequest: sendCustomRequest,
        requestSnapshot: requestSnapshot,
        batchRequestPreview: batchRequestPreview,
        requestPreviewForCard: requestPreviewForCard,
        teamHasHumanoidAndNonHuman: teamHasHumanoidAndNonHuman,
        teamHasOnlyNonHuman: teamHasOnlyNonHuman,
        setKnownEnemies: setKnownEnemies,
        rosterDisplaySpritename: rosterDisplaySpritename,
        filterKnownUnits: filterKnownUnits
    };
})();
