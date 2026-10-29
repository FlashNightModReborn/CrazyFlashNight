/**
 * stage-select/stage-select-quick.js — 选关快捷路径：情报侧栏 + 指针锁定 + 支点推近 + 靶标/邻居降亮。
 *
 * 交互合同（2026-10-29 「近端执行、远端情报」，兼顾 Flash 老玩家手感与操作速度）：
 * - 第 1 层（悬停）= Flash 手势：节点上方弹出快捷卡，难度行相对节点方向/偏移固定，点难度即进入
 *   （卡片几何见 stage-select-card-layout.js 停靠合同；本模块不改提交链路）。
 * - 第 2 层（情报侧栏）：悬停停留后在节点对侧屏幕边缘被动显示完整简介/通关记录/情报摘要；
 *   未锁定时不接收指针、不进 Tab 序，不挡任何节点悬停——老玩家可以完全无视。
 * - 第 3 层（锁定）：指针单击已解锁节点 = 锁定（卡片常驻、侧栏可交互）；三维战区以节点为支点推近，
 *   节点与难度行留在光标下，出发行程不变。锁定永不进关；再点同节点 / 点空白 / Esc 解除。
 * - 深度详情（既有双栏聚焦）：双击节点、侧栏「展开详情」、键盘 Enter 或辅助技术激活进入，
 *   不在出发的必经路径上。程序化 click（event.detail===0）保持原「选中→详情」语义。
 *
 * 依赖（调用时解析）：StageSelectCore / StageSelectViewModel / StageSelectRenderer /
 * StageSelectInspector / StageSelectDiorama / StageSelectCameraEditor。
 */
var StageSelectQuick = (function() {
    'use strict';

    if (typeof window === 'undefined' || !window.StageSelectCore) {
        throw new Error('stage-select/stage-select-quick.js 需要先加载 stage-select/stage-select-core.js');
    }

    var S = StageSelectCore.state;
    var DOSSIER_DWELL_MS = 280;   // 悬停停留后才显示情报，快速扫过多个节点不闪烁
    var DOSSIER_LINGER_MS = 220;  // 离开节点后的保留时间，覆盖节点 → 卡片的交接
    var dossier = null, nameEl = null, typeEl = null, metaEl = null, detailEl = null, intelEl = null, hintEl = null, expandEl = null;
    var shownId = '', showTimer = 0, hideTimer = 0, pinReturnCamera = null;

    function vm() { return window.StageSelectViewModel; }

    function clearTimers() {
        if (showTimer) clearTimeout(showTimer);
        if (hideTimer) clearTimeout(hideTimer);
        showTimer = 0;
        hideTimer = 0;
    }

    function createDOM(stageEl) {
        dossier = document.createElement('aside');
        dossier.className = 'stage-select-dossier';
        dossier.id = 'stage-select-dossier';
        dossier.setAttribute('role', 'region');
        dossier.setAttribute('aria-label', '地点情报');
        dossier.setAttribute('data-side', 'right');
        dossier.hidden = true;
        dossier.innerHTML =
            '<div class="stage-select-dossier-head">' +
                '<span class="stage-select-dossier-name"></span>' +
                '<span class="stage-select-dossier-type"></span>' +
            '</div>' +
            '<div class="stage-select-dossier-meta"></div>' +
            '<div class="stage-select-dossier-detail"></div>' +
            '<div class="stage-select-dossier-intel"></div>' +
            '<div class="stage-select-dossier-foot">' +
                '<span class="stage-select-dossier-hint"></span>' +
                '<button type="button" class="stage-select-dossier-expand" tabindex="-1" data-audio-cue="select">展开详情</button>' +
            '</div>';
        nameEl = dossier.querySelector('.stage-select-dossier-name');
        typeEl = dossier.querySelector('.stage-select-dossier-type');
        metaEl = dossier.querySelector('.stage-select-dossier-meta');
        detailEl = dossier.querySelector('.stage-select-dossier-detail');
        intelEl = dossier.querySelector('.stage-select-dossier-intel');
        hintEl = dossier.querySelector('.stage-select-dossier-hint');
        expandEl = dossier.querySelector('.stage-select-dossier-expand');
        expandEl.addEventListener('click', function(e) {
            e.stopPropagation();
            if (S._pinnedStageId) openDetail(S._pinnedStageId);
        });
        dossier.addEventListener('click', function(e) { e.stopPropagation(); });
        stageEl.appendChild(dossier);
        return dossier;
    }

    function historyFor(state) {
        var value = state && state.clearHistory;
        return value && value.cleared === true && Array.isArray(value.difficulties) && value.difficulties.length ? value : null;
    }

    function renderDossier(id) {
        var VM = vm();
        var button = VM.findStageButtonById(id);
        if (!button || !dossier) return false;
        var state = VM.getStageState(button.stageName);
        if (!state.unlocked) return false;
        var isMap = button.entryKind === 'map';
        var displayName = VM.getStageDisplayName(button);
        var stageType = state.stageType || button.stageType || (isMap ? '外交地图' : '');
        var detail = StageSelectCore.buildStageDetail(button, state);
        nameEl.textContent = displayName;
        typeEl.textContent = stageType;
        typeEl.hidden = !stageType;
        var meta = [];
        if (isMap) {
            meta.push('<span class="stage-select-dossier-chip is-map">外交据点 · 非交战区域</span>');
        } else {
            var info = historyFor(state);
            meta.push('<span class="stage-select-dossier-chip' + (info ? ' is-cleared' : '') + '">' +
                StageSelectCore.escapeHtml(info ? '已通关 · ' + info.difficulties.join(' / ') : '暂无通关记录') + '</span>');
            if (state.task) {
                meta.push('<span class="stage-select-dossier-chip is-task">' +
                    StageSelectCore.escapeHtml('任务目标 · 推荐' + (state.highestDifficulty || '简单')) + '</span>');
            }
        }
        if (state.forceUnlocked) meta.push('<span class="stage-select-dossier-chip is-force">演习解锁</span>');
        metaEl.innerHTML = meta.join('');
        detailEl.innerHTML = detail.html;
        var intel = '';
        if (isMap) {
            intel = '前往后可与驻地 NPC 交互、交易补给或推进支线。';
        } else if (!historyFor(state)) {
            intel = '通关后解锁奖励与敌人情报。';
        } else {
            var data = window.StageSelectIntelData && StageSelectIntelData.stages && StageSelectIntelData.stages[button.stageName];
            intel = data
                ? '情报：可能产出 ' + data.rewards.length + ' 种 · 常规敌人 ' + data.enemies.length + ' 类'
                : '暂无该关卡的情报资料。';
        }
        intelEl.textContent = intel;
        var pinned = S._pinnedStageId === id;
        hintEl.textContent = pinned ? '已锁定 · 点空白或 Esc 解除' : '单击地点锁定 · 双击展开详情';
        expandEl.hidden = !pinned;
        expandEl.tabIndex = pinned ? 0 : -1;
        dossier.classList.toggle('is-pinned', pinned);
        dossier.setAttribute('data-stage-id', id);
        return true;
    }

    // 侧栏停靠：节点在右半屏 → 左侧边缘，反之右侧；与快捷卡或当前节点相交的一侧不可用（两边都不可用时不显示）；
    // 两侧都可用时选压住其它地名/信标更少的一侧，平局保持对侧习惯。
    function dockDossier(id, anchor) {
        var VM = vm();
        var button = VM.findStageButtonById(id);
        if (!button) return false;
        var point = VM.getStageNavPoint(button, StageSelectRenderer.computeDirectSizing);
        var designW = S.DESIGN_W || 1024;
        var preferred = point.x > designW / 2 ? 'left' : 'right';
        var card = cardRect(anchor);
        var width = dossier.offsetWidth || 248;
        var height = dossier.offsetHeight || 200;
        var top = 62;
        var rects = {
            left: { x: 12, y: top, width: width, height: height },
            right: { x: designW - 12 - width, y: top, width: width, height: height }
        };
        var order = [preferred, preferred === 'left' ? 'right' : 'left'];
        var rectSets = nodeRects(id);
        var others = rectSets.others;
        var best = null;
        for (var i = 0; i < order.length; i += 1) {
            var rect = rects[order[i]];
            var coversCard = card && StageSelectCardLayout.intersects(rect, card);
            // 本节点（信标 + 地名牌，三维地名可经引线远离信标）都不得被侧栏压住：锁定后侧栏可交互，
            // 压住地名会吞掉再次单击 / 双击。
            var padded = { x: rect.x - 8, y: rect.y - 8, width: rect.width + 16, height: rect.height + 16 };
            var coversNode = point.x >= padded.x && point.x <= padded.x + padded.width && point.y >= padded.y && point.y <= padded.y + padded.height;
            for (var o = 0; o < rectSets.own.length && !coversNode; o += 1) {
                if (StageSelectCardLayout.intersects(padded, rectSets.own[o])) coversNode = true;
            }
            if (coversCard || coversNode) continue;
            var covered = 0;
            for (var j = 0; j < others.length; j += 1) {
                if (StageSelectCardLayout.intersects(rect, others[j])) covered += 1;
            }
            if (!best || covered < best.covered) best = { side: order[i], covered: covered };
        }
        if (!best) return false;
        dossier.setAttribute('data-side', best.side);
        return true;
    }

    // 节点地名/信标矩形（设计坐标）：own = 当前节点（不得被压住），others = 邻居（择边时少压）。
    function nodeRects(id) {
        var result = { own: [], others: [] };
        if (!S._buttonLayerEl || !S._stageEl) return result;
        var stage = S._stageEl.getBoundingClientRect();
        if (!stage.width) return result;
        var k = (S.DESIGN_W || 1024) / stage.width;
        S._buttonLayerEl.querySelectorAll('.stage-select-stage-button').forEach(function(node) {
            var bucket = node.getAttribute('data-stage-id') === id ? result.own : result.others;
            node.querySelectorAll('.stage-select-stage-name, .stage-select-marker').forEach(function(part) {
                if (!part.getClientRects().length) return;
                var r = part.getBoundingClientRect();
                if (!r.width || !r.height) return;
                bucket.push({ x: (r.left - stage.left) * k, y: (r.top - stage.top) * k, width: r.width * k, height: r.height * k });
            });
        });
        return result;
    }

    function cardRect(anchor) {
        if (!anchor) return null;
        var left = parseFloat(anchor.style.left), top = parseFloat(anchor.style.top);
        var width = parseFloat(anchor.style.getPropertyValue('--stage-card-width'));
        var height = parseFloat(anchor.style.getPropertyValue('--stage-card-height'));
        if (![left, top, width, height].every(isFinite)) return null;
        return { x: left, y: top, width: width, height: height };
    }

    function showDossier(id, anchor) {
        if (!dossier) return;
        if (!renderDossier(id)) { hideDossier(); return; }
        dossier.hidden = false;
        if (!dockDossier(id, anchor)) { hideDossier(); return; }
        shownId = id;
        dossier.classList.add('is-visible');
    }

    function hideDossier() {
        clearTimers();
        shownId = '';
        if (!dossier) return;
        dossier.classList.remove('is-visible', 'is-pinned');
        dossier.hidden = true;
        dossier.removeAttribute('data-stage-id');
        if (expandEl) { expandEl.hidden = true; expandEl.tabIndex = -1; }
    }

    function findAnchor(id) {
        return id && S._cardLayerEl
            ? S._cardLayerEl.querySelector('.stage-select-card-anchor[data-stage-id="' + StageSelectCore.selectorQuote(id) + '"]')
            : null;
    }

    // renderer.updateCardVisibility 的唯一下游：同步锁定类、靶标、邻居降亮与情报侧栏。
    function onCardChange(openId, openAnchor) {
        applyPinClasses();
        applyUnderCard(openId, openAnchor);
        var inspectorOpen = window.StageSelectInspector && StageSelectInspector.isInspectorOpen();
        var touring = window.StageSelectCameraEditor && StageSelectCameraEditor.isOpen();
        if (!openId || inspectorOpen || touring) {
            if (inspectorOpen || touring) { hideDossier(); return; }
            if (showTimer) { clearTimeout(showTimer); showTimer = 0; }
            if (shownId && !hideTimer) {
                hideTimer = setTimeout(function() { hideTimer = 0; if (!vm().computeOpenCardId()) hideDossier(); }, DOSSIER_LINGER_MS);
            }
            return;
        }
        if (hideTimer) { clearTimeout(hideTimer); hideTimer = 0; }
        var immediate = !!shownId || S._pinnedStageId === openId;
        if (immediate) { showDossier(openId, openAnchor); return; }
        if (showTimer) clearTimeout(showTimer);
        showTimer = setTimeout(function() {
            showTimer = 0;
            if (vm().computeOpenCardId() === openId) showDossier(openId, findAnchor(openId));
        }, DOSSIER_DWELL_MS);
    }

    function applyPinClasses() {
        var id = S._pinnedStageId;
        if (S._buttonLayerEl) {
            S._buttonLayerEl.querySelectorAll('.stage-select-stage-button').forEach(function(node) {
                node.classList.toggle('is-pinned', !!id && node.getAttribute('data-stage-id') === id);
            });
        }
        if (S._cardLayerEl) {
            S._cardLayerEl.querySelectorAll('.stage-select-card-anchor').forEach(function(anchor) {
                anchor.classList.toggle('is-pinned', !!id && anchor.getAttribute('data-stage-id') === id);
            });
        }
        if (S._el) S._el.classList.toggle('has-pinned-stage', !!id);
    }

    // 被打开的快捷卡压住的邻居节点降亮（而不是被直接盖死），仍可悬停与点击。
    function applyUnderCard(openId, openAnchor) {
        if (!S._buttonLayerEl) return;
        var nodes = S._buttonLayerEl.querySelectorAll('.stage-select-stage-button');
        var card = openId && openAnchor ? openAnchor.querySelector('.stage-select-card') : null;
        var rect = card && card.getClientRects().length ? card.getBoundingClientRect() : null;
        for (var i = 0; i < nodes.length; i += 1) {
            var node = nodes[i];
            var under = false;
            if (rect && node.getAttribute('data-stage-id') !== openId) {
                var parts = node.querySelectorAll('.stage-select-stage-name, .stage-select-marker');
                for (var j = 0; j < parts.length && !under; j += 1) {
                    if (!parts[j].getClientRects().length) continue;
                    var r = parts[j].getBoundingClientRect();
                    under = r.left < rect.right && r.right > rect.left && r.top < rect.bottom && r.bottom > rect.top;
                }
            }
            node.classList.toggle('is-under-card', under);
        }
    }

    function isPinnable(button) {
        var VM = vm();
        if (!button || VM.isDirectEntry(button)) return false;
        return !!VM.getStageState(button.stageName).unlocked;
    }

    // 指针单击入口（renderer 节点 click 与三维拾取共用）。返回 true 表示已按「锁定」消费。
    function pointerActivate(stageId) {
        var VM = vm();
        var button = VM.findStageButtonById(stageId);
        if (!isPinnable(button)) return false;
        if (S._selectedStageId) return false; // 深度详情打开时节点层 inert，防御性保持原语义
        if (S._pinnedStageId === stageId) unpin();
        else pin(stageId);
        return true;
    }

    function pin(stageId) {
        var wasPinned = !!S._pinnedStageId;
        S._pinnedStageId = stageId;
        StageSelectCore.logDev('pin stage: ' + stageId);
        // 支点推近只在首次锁定时发生；锁定迁移到另一节点时保持当前镜头，避免目标从光标下溜走。
        if (!wasPinned && window.StageSelectDiorama && StageSelectDiorama.pinZoom) {
            pinReturnCamera = StageSelectDiorama.pinZoom(stageId);
        }
        StageSelectRenderer.updateCardVisibility();
    }

    function unpin(opts) {
        opts = opts || {};
        if (!S._pinnedStageId) return false;
        S._pinnedStageId = '';
        var restore = pinReturnCamera;
        pinReturnCamera = null;
        if (restore && window.StageSelectDiorama && StageSelectDiorama.restorePinCamera) {
            StageSelectDiorama.restorePinCamera(restore, !opts.instant);
        }
        if (!opts.silent && window.StageSelectRenderer) StageSelectRenderer.updateCardVisibility();
        return true;
    }

    function togglePin(stageId) {
        return pointerActivate(stageId);
    }

    function openDetail(stageId) {
        unpin({ instant: true, silent: true });
        hideDossier();
        StageSelectInspector.selectStage(stageId);
    }

    function handleBlankClick(e) {
        if (!S._pinnedStageId) return;
        var target = e.target;
        if (target && target.closest && target.closest('.stage-select-stage-button, .stage-select-card-anchor, .stage-select-dossier, .stage-select-nav-button, .stage-select-inspector, .stage-focus-surface, .stage-camera-editor, .stage-select-diorama-comparison')) return;
        unpin();
    }

    // 面板打开/关闭/切页：清空锁定与侧栏。切页前由 renderer 调用，镜头随 diorama rebind 自然复位。
    function reset() {
        S._pinnedStageId = '';
        pinReturnCamera = null;
        hideDossier();
    }

    function stats() {
        return {
            pinnedStageId: S._pinnedStageId || '',
            dossierVisible: !!(dossier && !dossier.hidden),
            dossierStageId: shownId,
            dossierSide: dossier ? dossier.getAttribute('data-side') : '',
            pinZoomed: !!pinReturnCamera
        };
    }

    return {
        createDOM: createDOM,
        onCardChange: onCardChange,
        pointerActivate: pointerActivate,
        togglePin: togglePin,
        pin: pin,
        unpin: unpin,
        openDetail: openDetail,
        handleBlankClick: handleBlankClick,
        hideDossier: hideDossier,
        reset: reset,
        pinnedId: function() { return S._pinnedStageId || ''; },
        stats: stats
    };
})();
