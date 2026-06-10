(function() {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // 成就 tab（任务面板第三 tab，2026-06-10 A 轮）
    //   设计：docs/成就系统-A轮-设计-2026-06-10.md §6
    //   · 静态目录 = build 派生 achievement-catalog.json（web 直读；hidden 条目已脱敏 "???"，
    //     明文仅经 AS2 handleState 的 hiddenReveals 按需回传——防剧透双层之第一层）
    //   · 动态状态 = achievementState 叠加 { unlocked, claimed, progress, hiddenReveals, dataReady }
    //   · 领取 = achievementClaim { achievementId }（稳定主键，绝不传 index）；
    //     回包并入完整状态叠加，本模块原子重渲，零额外往返
    //   · 四态徽章：locked(hidden 未达成"???") / inProgress(进度条) / unlocked(领取钮+红点) / claimed(灰勾)
    //   · 奖励 toast 在 web 面板内渲染（不走 AS2 弹窗——WebView overlay 遮挡 Flash 弹窗）
    //
    // 与 task-panel.js 的协作（panels-lazy-registry deps 先加载本文件）：
    //   task-panel.js createDOM 时调 install(ctx)，onOpen 调 reset()，switchTab('ach') 调 enter()。
    //   ctx = { paneEl, send, toast, escHtml, escAttr, itemIconHtml, beginOp, endOp, isBusy, session }
    //   claim 在途经 ctx.beginOp/endOp 复用任务面板 _busy 锁（拦截 切tab/关面板/二次点击 三处口径）。
    // ═══════════════════════════════════════════════════════════

    var _ctx = null;
    var _listEl = null;
    var _summaryEl = null;

    // 静态目录（不可变，模块级缓存，只 fetch 一次；测试钩子 window.__ACHIEVEMENT_CATALOG）
    var _catalog = null;
    var _catalogState = 'idle';   // idle | loading | ready | error
    var _catalogWaiters = [];

    // 动态状态（每次 enter 重取；存档态可变）
    var _state = null;            // { unlocked:{id:1}, claimed:{id:1}, progress:{id:cur}, reveals:{id:{title,description,rewards}} }
    var _stateError = null;       // null | 'not_ready' | 'failed'

    window.TaskAchievementTab = {
        install: function(ctx) {
            _ctx = ctx;
            ctx.paneEl.innerHTML = '' +
                '<div class="ach-summary" id="ach-summary"></div>' +
                '<div class="ach-list" id="ach-list"></div>' +
                '<div class="ach-toast-anchor" id="ach-toast-anchor"></div>';
            _summaryEl = ctx.paneEl.querySelector('#ach-summary');
            _listEl = ctx.paneEl.querySelector('#ach-list');
            // 领取按钮（事件委托，按钮随列表每次重渲）
            _listEl.addEventListener('click', onListClick);
        },

        // onOpen 重置：动态状态清空重取，catalog 缓存保留（不可变，与 _catalog 同口径）
        reset: function() {
            _state = null;
            _stateError = null;
            if (_listEl) _listEl.innerHTML = '';
            if (_summaryEl) _summaryEl.innerHTML = '';
            clearToasts();
        },

        // 切入成就 tab：catalog 懒加载 + 状态刷新（每次进入都重取，开销 = 一次轻量叠加）
        enter: function() {
            renderLoading();
            loadCatalog(function(cat) {
                if (!cat) { renderCatalogError(); return; }
                requestState();
            });
        },

        // ── QA 钩子（harness ?qa= 用，生产无副作用）──
        _state: function() {
            return {
                catalogState: _catalogState,
                stateLoaded: !!_state,
                stateError: _stateError,
                rowCount: _listEl ? _listEl.querySelectorAll('.ach-row').length : 0,
                unlockedCount: _state ? countKeys(_state.unlocked) : 0,
                claimedCount: _state ? countKeys(_state.claimed) : 0,
                toastCount: _ctx ? _ctx.paneEl.querySelectorAll('.ach-toast').length : 0
            };
        }
    };

    function countKeys(o) { var n = 0; for (var k in o) n++; return n; }

    // ═══════════════════════════════════════════════════════════
    // 静态目录加载（镜像 task-panel loadCatalog；测试钩子优先 + 强制失败钩子）
    // ═══════════════════════════════════════════════════════════
    function loadCatalog(cb) {
        if (typeof window !== 'undefined' && window.__ACH_FORCE_CATALOG_ERROR) { cb(null); return; }
        if (_catalogState === 'ready') { cb(_catalog); return; }
        if (typeof window !== 'undefined' && window.__ACHIEVEMENT_CATALOG) {
            _catalog = window.__ACHIEVEMENT_CATALOG; _catalogState = 'ready'; cb(_catalog); return;
        }
        _catalogWaiters.push(cb);
        if (_catalogState === 'loading') return;
        _catalogState = 'loading';
        var flush = function(ok) {
            var ws = _catalogWaiters; _catalogWaiters = [];
            for (var i = 0; i < ws.length; i++) ws[i](ok ? _catalog : null);
        };
        try {
            fetch('modules/tasks/achievement-catalog.json').then(function(r) {
                if (!r.ok) throw new Error('http ' + r.status);
                return r.json();
            }).then(function(json) {
                _catalog = json; _catalogState = 'ready'; flush(true);
            })['catch'](function() {
                _catalogState = 'error'; flush(false);
            });
        } catch (e) {
            _catalogState = 'error'; flush(false);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // 状态拉取
    // ═══════════════════════════════════════════════════════════
    function requestState() {
        var session = _ctx.session();
        _ctx.send('achievementState', null, function(data) {
            if (session !== _ctx.session()) return;
            applyStateResponse(data);
            renderAll();
        });
    }

    // state / claim 回包共用：把叠加揉进 _state（claim 回包并入完整叠加 = 同一口径）
    function applyStateResponse(data) {
        if (!data || data.success !== true) {
            _state = null;
            _stateError = (data && data.error === 'not_ready') ? 'not_ready' : 'failed';
            return;
        }
        var reveals = {};
        var hr = data.hiddenReveals || [];
        for (var i = 0; i < hr.length; i++) {
            if (hr[i] && hr[i].id !== undefined) reveals[String(hr[i].id)] = hr[i];
        }
        _state = {
            unlocked: toIdSet(data.unlocked),
            claimed: toIdSet(data.claimed),
            progress: data.progress || {},
            reveals: reveals
        };
        _stateError = null;
    }

    function toIdSet(arr) {
        var set = {};
        if (arr && arr.length) for (var i = 0; i < arr.length; i++) set[String(arr[i])] = 1;
        return set;
    }

    // ═══════════════════════════════════════════════════════════
    // 渲染
    // ═══════════════════════════════════════════════════════════
    function renderLoading() {
        _summaryEl.innerHTML = '';
        _listEl.innerHTML = '<div class="ach-hint">加载成就数据…</div>';
    }
    function renderCatalogError() {
        _summaryEl.innerHTML = '';
        _listEl.innerHTML = '<div class="ach-hint ach-error">成就数据未加载（成就目录缺失或损坏）</div>';
    }
    function renderNotReady() {
        _summaryEl.innerHTML = '';
        _listEl.innerHTML = '<div class="ach-hint">存档尚未就绪，进入游戏后再来看看吧</div>';
    }
    function renderStateError() {
        _summaryEl.innerHTML = '';
        _listEl.innerHTML = '<div class="ach-hint ach-error">成就进度加载失败（请重开面板重试）</div>';
    }

    function renderAll() {
        if (!_catalog) { renderCatalogError(); return; }
        if (!_state) {
            if (_stateError === 'not_ready') renderNotReady(); else renderStateError();
            return;
        }
        var esc = _ctx.escHtml;
        var cats = _catalog.categories || {};
        var defs = _catalog.achievements || {};
        var total = 0, unlockedN = 0, claimedN = 0, claimableN = 0;
        var html = '';

        for (var catName in cats) {
            var ids = cats[catName];
            if (!ids || !ids.length) continue;
            var rowsHtml = '';
            for (var i = 0; i < ids.length; i++) {
                var def = defs[String(ids[i])];
                if (!def) continue;
                total++;
                var st = entryState(def);
                if (st.unlocked) unlockedN++;
                if (st.claimed) claimedN++;
                if (st.claimable) claimableN++;
                rowsHtml += renderRow(def, st, i);
            }
            if (!rowsHtml) continue;
            html += '<div class="ach-section"><div class="ach-section-title">' + esc(catName) + '</div>' + rowsHtml + '</div>';
        }

        _summaryEl.innerHTML =
            '<span class="ach-sum-item">已解锁 <strong>' + unlockedN + '</strong> / ' + total + '</span>' +
            '<span class="ach-sum-item">已领取 <strong>' + claimedN + '</strong></span>' +
            (claimableN > 0 ? '<span class="ach-sum-item ach-sum-claimable">可领取 <strong>' + claimableN + '</strong></span>' : '');
        _listEl.innerHTML = html || '<div class="ach-hint">暂无成就条目</div>';
    }

    // 单条目状态归并（四态）：claimed > unlocked(claimable) > inProgress > locked(hidden)
    function entryState(def) {
        var idStr = String(def.id);
        var claimed = _state.claimed[idStr] === 1;
        var unlocked = claimed || _state.unlocked[idStr] === 1;
        return {
            claimed: claimed,
            unlocked: unlocked,
            claimable: unlocked && !claimed,
            hiddenLocked: def.hidden === true && !unlocked
        };
    }

    function renderRow(def, st, i) {
        var esc = _ctx.escHtml;
        var idStr = String(def.id);
        var reveal = _state.reveals[idStr];

        // hidden 条目：catalog 已脱敏（"???"）；解锁后改用 hiddenReveals 明文（含 rewards）
        var title = (def.hidden === true && reveal) ? reveal.title : def.title;
        var desc = (def.hidden === true && reveal) ? reveal.description : def.description;
        var rewards = (def.hidden === true && reveal) ? (reveal.rewards || []) : (def.rewards || []);

        var stateCls = st.claimed ? 'state-claimed'
            : st.claimable ? 'state-unlocked'
            : st.hiddenLocked ? 'state-locked'
            : 'state-progress';
        var medal = st.claimed ? '✔' : st.claimable ? '★' : st.hiddenLocked ? '?' : '·';

        // 进度条：cur 来自叠加（hidden 未解锁条目服务端不回 progress → 不渲染，防可探测）；
        // target 来自 catalog；双端封顶（min(cur,target)），文本 cur/target，绝不出 NaN
        var progressHtml = '';
        var target = def.objective && Number(def.objective.target);
        if (!st.hiddenLocked && target > 0) {
            var cur = Number(_state.progress[idStr]);
            if (isNaN(cur)) cur = st.unlocked ? target : 0;   // 解锁后无 progress 键 → 恒显 target/target
            if (cur > target) cur = target;
            if (cur < 0) cur = 0;
            var pct = Math.round(Math.min(cur / target, 1) * 100);
            progressHtml = '<div class="ach-progress"><div class="ach-progress-fill" style="width:' + pct + '%"></div>' +
                '<span class="ach-progress-text">' + cur + '/' + target + '</span></div>';
        }

        // 奖励图标（data-item-name → 复用任务面板 hover 富 tooltip 委托）
        var rewardsHtml = '';
        for (var r = 0; r < rewards.length; r++) {
            rewardsHtml += _ctx.itemIconHtml(rewards[r].name, rewards[r].count, r);
        }

        var actionHtml = st.claimed
            ? '<span class="ach-claimed-mark">已领取</span>'
            : st.claimable
                ? '<button class="ach-claim-btn" data-ach-id="' + esc(idStr) + '" type="button">领取<span class="ach-claim-dot"></span></button>'
                : '';

        return '<div class="ach-row ' + stateCls + '" data-ach-id="' + esc(idStr) + '" style="animation-delay:' + (Math.min(i, 12) * 0.03).toFixed(2) + 's">' +
            '<div class="ach-medal">' + medal + '</div>' +
            '<div class="ach-main">' +
                '<div class="ach-title">' + esc(title) +
                    (def.hidden === true ? '<span class="ach-hidden-tag">隐藏</span>' : '') + '</div>' +
                '<div class="ach-desc">' + esc(desc) + '</div>' +
                progressHtml +
            '</div>' +
            (rewardsHtml ? '<div class="ach-rewards">' + rewardsHtml + '</div>' : '') +
            '<div class="ach-action">' + actionHtml + '</div>' +
        '</div>';
    }

    // ═══════════════════════════════════════════════════════════
    // 领取
    // ═══════════════════════════════════════════════════════════
    function onListClick(e) {
        var btn = e.target && e.target.closest ? e.target.closest('.ach-claim-btn') : null;
        if (!btn) return;
        onClaim(btn.getAttribute('data-ach-id'), btn);
    }

    function onClaim(achievementId, btn) {
        if (_ctx.isBusy()) return;   // 在途拦截（二次点击）
        _ctx.beginOp(btn);           // 复用任务面板 _busy：同时拦 切tab / 关面板
        var session = _ctx.session();
        _ctx.send('achievementClaim', { achievementId: Number(achievementId) }, function(data) {
            _ctx.endOp(btn);
            if (session !== _ctx.session()) return;

            // 回包并入完整状态叠加 → 原子重渲（成功/失败同口径，服务端权威纠偏）
            var hadOverlay = data && data.unlocked !== undefined;
            if (data && data.success === true) {
                applyStateResponse(data);
                renderAll();
                showRewardToast(data.rewards || []);
                return;
            }
            var err = data && data.error;
            if (err === 'already_claimed') {
                // 幂等：静默按 overlay 重渲为 claimed，UI 不抖、不报错
                if (hadOverlay) { applyStateResponse(withSuccess(data)); renderAll(); }
                return;
            }
            if (err === 'not_ready') {
                _state = null; _stateError = 'not_ready';
                renderAll();   // 「存档尚未就绪」降级文案；_busy 已解除可重试
                return;
            }
            if (err === 'achievement_not_found') {
                _ctx.toast('成就数据已更新，正在刷新');
                requestState();   // web/catalog 版本错位征兆 → 强制刷新 state
                return;
            }
            if (err === 'not_unlocked') {
                _ctx.toast('该成就尚未达成');
                if (hadOverlay) { applyStateResponse(withSuccess(data)); renderAll(); }
                return;
            }
            if (err === 'inventory_full') {
                _ctx.toast('背包已满，无法领取，请清理背包后重试');
                return;   // 保持 unlocked 可重试（服务端未置 claimed）
            }
            _ctx.toast(err === 'timeout' ? '领取超时，请重试' : (err === 'disconnected' ? '游戏连接已断开' : '领取失败' + (err ? '：' + err : '')));
        });
    }

    // 失败回包也携带 overlay（success:false）；applyStateResponse 只认 success:true → 包一层借道
    function withSuccess(data) {
        return {
            success: true,
            unlocked: data.unlocked, claimed: data.claimed,
            progress: data.progress, hiddenReveals: data.hiddenReveals
        };
    }

    // ═══════════════════════════════════════════════════════════
    // 面板内奖励 toast（不走 AS2 任务奖励提示界面——overlay 遮挡 Flash 弹窗）
    // ═══════════════════════════════════════════════════════════
    function showRewardToast(rewards) {
        var anchor = _ctx.paneEl.querySelector('#ach-toast-anchor');
        if (!anchor) return;
        var esc = _ctx.escHtml;
        var parts = [];
        for (var i = 0; i < rewards.length; i++) {
            parts.push(esc(rewards[i].name) + (rewards[i].count > 1 ? '×' + rewards[i].count : ''));
        }
        var t = document.createElement('div');
        t.className = 'ach-toast';
        t.innerHTML = '<span class="ach-toast-icon">🏆</span>' +
            (parts.length ? '已领取：' + parts.join('、') : '成就已确认');
        anchor.appendChild(t);
        setTimeout(function() { if (t.parentNode) t.parentNode.removeChild(t); }, 3200);
    }

    function clearToasts() {
        if (!_ctx) return;
        var anchor = _ctx.paneEl.querySelector('#ach-toast-anchor');
        if (anchor) anchor.innerHTML = '';
    }
})();
