/**
 * stage-select/stage-select-inspector.js — 选关面板 P4-a 工程拆分 · pinned 决策检查器。
 *
 * 职责：选中态编排（选中 → 检查器内容 → 难度提交 intent 的完整链路）——
 * selectStage / toggleStageSelection / clearSelection 的跨层编排（纯状态迁移在
 * StageSelectViewModel，金环 / roving tabindex / 卡片让位等 DOM 反映在
 * StageSelectRenderer），检查器内容渲染（复用 hover 卡数据链），键盘落点与检查器内
 * 方向键难度导航（handleInspectorKey），舞台空白点击取消，难度点击委派入口与进入
 * intent 仲裁（锁定本地拒绝 / busy 去重 / 按下反馈），最终经 StageSelectBridge.requestEnter 提交。
 *
 * 本文件由 modules/stage-select-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议
 * payload / DOM id·class 契约 / QA 断言不变）。跨模块函数引用解析于调用时。
 * 依赖守卫：stage-select/stage-select-core.js + stage-select-view-model.js +
 * stage-select-renderer.js。
 *
 * P2 交互终态（双模裁决 2026-08-16：hover 卡一点即进的鼠标快捷路径不动，检查器承接
 * 选中态与键盘路径）：
 * - 点击 / Enter / Space 普通关卡节点 = 选中并 pin 检查器；再点同节点 / 点舞台空白 /
 *   Esc / 点其他节点（转移）控制取消或迁移；直达入口保持一步跳转不经过检查器。
 * - 检查器复用 hover 卡数据链（名称 / 预览 / 简介 / 限制词条 / 材料 / 任务推荐难度），
 *   锁定节点展示锁定状态与原因文案、不渲染难度按钮。
 * - snapshot / busy / error 全量重建后按 stageButton.id 恢复选中态与焦点。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined' || !window.StageSelectCore) {
        throw new Error('stage-select/stage-select-inspector.js 需要先加载 stage-select/stage-select-core.js（共享基座：状态容器 + 跨模块工具）');
    }
    if (typeof window === 'undefined' || !window.StageSelectViewModel) {
        throw new Error('stage-select/stage-select-inspector.js 需要先加载 stage-select/stage-select-view-model.js（纯数据层 ViewModel）');
    }
    if (typeof window === 'undefined' || !window.StageSelectRenderer) {
        throw new Error('stage-select/stage-select-inspector.js 需要先加载 stage-select/stage-select-renderer.js（空间 renderer）');
    }

    var S = StageSelectCore.state; // 共享状态（原顶层 var _x）
    var VM = StageSelectViewModel;

    function isInspectorOpen() {
        return !!(S._inspectorEl && !S._inspectorEl.hidden);
    }

    function selectStage(stageId, opts) {
        opts = opts || {};
        if (!VM.applySelection(stageId)) return;
        StageSelectRenderer.applySelectionClasses();
        StageSelectRenderer.applyRovingTabIndex();
        renderInspector();
        StageSelectRenderer.updateCardVisibility(); // 选中节点的 hover 卡让位给检查器
        if (opts.focusInspector) focusInspectorPrimary();
    }

    function toggleStageSelection(stageId) {
        if (S._selectedStageId === stageId) {
            clearSelection();
            return;
        }
        selectStage(stageId);
    }

    // 幂等：无选中时也安全调用（面板关闭路径依赖这一点）。
    function clearSelection(opts) {
        opts = opts || {};
        var prevId = VM.clearSelectionState();
        StageSelectRenderer.applySelectionClasses();
        renderInspector();
        StageSelectRenderer.updateCardVisibility();
        if (opts.restoreFocus && prevId) {
            var node = StageSelectRenderer.findNodeById(prevId);
            if (node) {
                S._tabbableStageId = prevId;
                StageSelectRenderer.applyRovingTabIndex();
                node.focus();
            }
        }
    }

    function renderInspector() {
        if (!S._inspectorEl) return;
        var button = S._selectedStageId ? VM.findStageButtonById(S._selectedStageId) : null;
        if (!button || VM.isDirectEntry(button)) {
            // 选中关卡不在当前 frame（切页）时检查器隐藏但选中记忆保留，回到原 frame 自动恢复。
            S._inspectorEl.hidden = true;
            return;
        }
        var state = VM.getStageState(button.stageName);
        var detail = StageSelectCore.buildStageDetail(button, state);
        var displayName = VM.getStageDisplayName(button);
        S._inspectorEl.setAttribute('aria-label', '关卡决策：' + displayName);
        S._inspectorNameEl.textContent = displayName;
        S._inspectorTypeEl.textContent = state.stageType || '';
        S._inspectorTypeEl.hidden = !state.stageType;
        S._inspectorPreviewEl.src = StageSelectCore.resolveAssetUrl(button.previewUrl || '');
        S._inspectorPreviewEl.alt = displayName + ' 预览';
        S._inspectorDetailEl.innerHTML = detail.html;
        if (state.unlocked) {
            S._inspectorLockEl.hidden = true;
            S._inspectorLockEl.textContent = '';
        } else {
            // 逐关锁定原因（2026-08-16 专项）：snapshot stageDetails[].lockReason 由 AS2
            // StageSelectPanelService.buildLockReason 生成（仅锁定时非空，字段恒在）；
            // 空串 / 旧快照缺字段时回退通用文案。
            S._inspectorLockEl.textContent = state.lockReason
                ? '未解锁：' + state.lockReason
                : '未解锁：该关卡尚未开放，继续推进主线或完成前置条件后可进入。';
            S._inspectorLockEl.hidden = false;
        }
        if (state.unlocked && state.task) {
            S._inspectorTaskEl.textContent = '任务目标 · 推荐难度：' + (state.highestDifficulty || '简单');
            S._inspectorTaskEl.hidden = false;
        } else {
            S._inspectorTaskEl.hidden = true;
            S._inspectorTaskEl.textContent = '';
        }
        S._inspectorDiffEl.innerHTML = state.unlocked ? StageSelectRenderer.renderDifficulties(button, state, true) : '';
        S._inspectorDiffEl.hidden = !state.unlocked;
        S._inspectorEl.classList.toggle('is-locked', !state.unlocked);
        S._inspectorEl.classList.toggle('is-busy', !!S._busyStageName && S._busyStageName === button.stageName);
        // 浮层不遮选中节点本身：节点在下半屏时检查器改靠顶停靠（runtime 让开 42px 顶部 HUD）。
        S._inspectorEl.classList.toggle('is-dock-top', VM.getStageNavPoint(button, StageSelectRenderer.computeDirectSizing).y > S.DESIGN_H * 0.5);
        S._inspectorEl.hidden = false;
    }

    // 键盘打开检查器后的落点：任务推荐难度 > 首个难度 > （锁定时）关闭钮。
    function focusInspectorPrimary() {
        if (!isInspectorOpen()) return;
        var target = S._inspectorDiffEl.querySelector('.stage-select-difficulty.is-recommended')
            || S._inspectorDiffEl.querySelector('.stage-select-difficulty');
        if (!target) target = S._inspectorCloseEl;
        if (target) target.focus();
    }

    // 检查器内键盘语义（打磨批 2026-08-16，接线在 renderer.createDOM 的 inspector keydown）：
    // - ←/→ 在同排难度按钮间循环移焦（取模循环与区域菜单 handleFrameMenuKey 同语义：
    //   同排 2~4 键短列表，循环比端点钳制少按键且全面板习语一致）；焦点即选中高亮
    //   （各按钮自身色系的亮度+发光，样式见 stage-select.css 检查器难度 :focus 段）。
    //   焦点不在难度按钮上（如落在关闭钮）时 → 进首键、← 进末键，方向键始终有明确去向。
    // - Enter/Space 提交当前难度：preventDefault 拦掉原生 button 激活，统一改走 .click()
    //   （真实键盘与 qa 合成事件同一路径），最终仍由面板根 handleDifficultyClick 委派，
    //   payload 与鼠标点击完全一致。
    // - ↑/↓ 定义为无操作（仅 preventDefault 防页面滚动）：难度行是单排横向组，无垂直
    //   目标；不绑定「焦点回节点」，避免与 Esc 取消语义重叠，保持 Esc 单一出口。
    // - 检查器打开期间地图节点的方向键导航由 renderer 侧守卫截停并回引焦点到本行
    //   （焦点困在检查器内）；Esc 分层 / Tab 序不变。
    // - 退化：挑战模式单键循环 = 原地；锁定检查器无难度按钮，方向键不抢关闭钮焦点。
    function handleInspectorKey(e) {
        if (!isInspectorOpen()) return;
        var key = e.key;
        if (key !== 'ArrowLeft' && key !== 'ArrowRight' && key !== 'ArrowUp' && key !== 'ArrowDown'
                && key !== 'Enter' && key !== ' ') {
            return;
        }
        var difficulties = S._inspectorDiffEl ? S._inspectorDiffEl.querySelectorAll('.stage-select-difficulty') : [];
        var active = document.activeElement;
        var idx = -1;
        for (var i = 0; i < difficulties.length; i += 1) {
            if (difficulties[i] === active) { idx = i; break; }
        }
        if (key === 'Enter' || key === ' ') {
            if (idx >= 0) {
                e.preventDefault();
                difficulties[idx].click();
            }
            return;
        }
        e.preventDefault();
        if (key === 'ArrowUp' || key === 'ArrowDown') return;
        if (!difficulties.length) return;
        var next;
        if (idx < 0) {
            next = key === 'ArrowRight' ? 0 : difficulties.length - 1;
        } else {
            next = (idx + (key === 'ArrowRight' ? 1 : -1) + difficulties.length) % difficulties.length;
        }
        difficulties[next].focus();
    }

    function handleStageBlankClick(e) {
        if (!S._selectedStageId) return;
        var target = e.target;
        if (target && target.closest
                && target.closest('.stage-select-stage-button, .stage-select-nav-button, .stage-select-card-anchor, .stage-select-inspector')) {
            return;
        }
        clearSelection();
    }

    // 难度点击委派入口（面板根 click 委托，同时覆盖 hover 卡与检查器内的难度按钮）。
    function handleDifficultyClick(e) {
        var target = e.target;
        if (!target || !target.classList || !target.classList.contains('stage-select-difficulty')) return;
        e.preventDefault();
        e.stopPropagation();
        var stageName = target.getAttribute('data-stage-name') || '';
        var difficulty = target.getAttribute('data-difficulty') || '';
        var entryKind = target.getAttribute('data-entry-kind') || 'difficulty';
        var button = VM.findStageButton(stageName, entryKind);
        if (button) {
            requestStageActivation(button, difficulty, target);
            return;
        }
        requestStageActivation({ stageName: stageName, entryKind: entryKind }, difficulty, target);
    }

    // 进入 intent 仲裁：锁定本地拒绝（illegal 音效 + 错误提示）、busy 去重、
    // 按下反馈，通过后经 bridge 提交 enter 请求。
    function requestStageActivation(button, difficulty, pressedTarget) {
        var stageName = button && button.stageName || '';
        var entryKind = button && button.entryKind || 'difficulty';
        var state = VM.getStageState(stageName);
        if (!stageName) {
            StageSelectCore.showError('invalid_stage');
            return;
        }
        if (!state.unlocked) {
            S._lastDifficultyClick = {
                stageName: stageName,
                difficulty: difficulty,
                entryKind: entryKind,
                blocked: 'locked'
            };
            StageSelectCore.cue('illegal'); // 本地拦截：锁定关卡的进入请求（契约 §2 illegal）
            StageSelectCore.showError('locked');
            StageSelectCore.logDev((entryKind === 'difficulty' ? 'difficulty' : entryKind) + ' blocked: ' + stageName + ' / locked');
            return;
        }
        if (S._busyStageName) {
            StageSelectCore.logDev('difficulty busy: ' + S._busyStageName);
            return;
        }
        S._lastDifficultyClick = {
            stageName: stageName,
            difficulty: difficulty,
            entryKind: entryKind
        };
        StageSelectCore.logDev((entryKind === 'difficulty' ? 'difficulty' : entryKind) + ' enter request: ' + stageName + (difficulty ? ' / ' + difficulty : ''));
        StageSelectCore.cue('activate'); // 进入关卡 = 核心提交动作：本地校验已过，播意图音（契约 §2 activate；权威回包不再补结果音）
        if (pressedTarget && pressedTarget.classList && pressedTarget.classList.contains('stage-select-difficulty')) {
            pressedTarget.classList.add('is-pressed');
            StageSelectCore.scheduleTimer(function() {
                pressedTarget.classList.remove('is-pressed');
            }, 180);
        }
        StageSelectBridge.requestEnter(stageName, difficulty, entryKind);
    }

    // 导出：被 renderer / bridge / facade 引用的名字
    window.StageSelectInspector = {
        isInspectorOpen: isInspectorOpen,
        selectStage: selectStage,
        toggleStageSelection: toggleStageSelection,
        clearSelection: clearSelection,
        renderInspector: renderInspector,
        focusInspectorPrimary: focusInspectorPrimary,
        handleStageBlankClick: handleStageBlankClick,
        handleInspectorKey: handleInspectorKey,
        handleDifficultyClick: handleDifficultyClick,
        requestStageActivation: requestStageActivation
    };
})();
