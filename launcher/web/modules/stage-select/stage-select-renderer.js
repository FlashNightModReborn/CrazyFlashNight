/**
 * stage-select/stage-select-renderer.js — 选关面板 P4-a 工程拆分 · 空间 renderer + 面板生命周期。
 *
 * 职责：DOM 舞台（背景/nav 层/按钮层/卡片锚点层）的创建与更新、帧菜单（区域 listbox）、
 * hover 卡可见性、roving tabindex / 方向键焦点移交、PanelScale 缩放接线、
 * 面板生命周期编排（onOpen / onRebind / onClose / requestClose —— 对位 arena-shell 的
 * 壳层编排角色）。全部领域决策（状态合并 / 选中 / 导航打分 / 开卡裁决）消费
 * StageSelectViewModel 纯数据层；协议请求经 StageSelectBridge；选中/检查器/难度提交
 * intent 经 StageSelectInspector。本模块不持有领域规则，只做 DOM 反映与编排。
 *
 * 本文件由 modules/stage-select-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议
 * payload / DOM id·class 契约 / QA 断言不变）。跨模块函数引用解析于调用时。
 * 依赖守卫：stage-select/stage-select-core.js + stage-select-view-model.js。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined' || !window.StageSelectCore) {
        throw new Error('stage-select/stage-select-renderer.js 需要先加载 stage-select/stage-select-core.js（共享基座：状态容器 + 跨模块工具）');
    }
    if (typeof window === 'undefined' || !window.StageSelectViewModel) {
        throw new Error('stage-select/stage-select-renderer.js 需要先加载 stage-select/stage-select-view-model.js（纯数据层 ViewModel）');
    }

    var S = StageSelectCore.state; // 共享状态（原顶层 var _x）
    var VM = StageSelectViewModel;

    // Off-DOM measurer: replicate .stage-select-card-detail typography exactly.
    // Reused across measurements to avoid layout-tree churn.
    var _detailMeasurer = null;

    // ════════════════════════════════════════════════════════════════════════════
    // DOM 创建
    // ════════════════════════════════════════════════════════════════════════════
    function createDOM() {
        S._el = document.createElement('div');
        S._el.className = 'stage-select-panel';
        // P1-B：skin 作用域锚点——css/panels/stage-select.css 的 --ss-* token 挂 [data-workbench-skin="stage-select"]
        S._el.setAttribute('data-workbench-skin', 'stage-select');
        S._el.innerHTML =
            '<div class="stage-select-header">' +
                '<div class="stage-select-heading">' +
                    '<span class="stage-select-title">选关</span>' +
                    '<button class="stage-select-frame-toggle" id="stage-select-frame-toggle" type="button" aria-expanded="false" aria-haspopup="listbox" title="切换区域" data-audio-cue="navigate">' +
                        '<span class="stage-select-frame-toggle-label" id="stage-select-frame-toggle-label"></span>' +
                        '<span class="stage-select-frame-toggle-counter" id="stage-select-frame-toggle-counter" aria-hidden="true"></span>' +
                        '<span class="stage-select-frame-toggle-task-badge" id="stage-select-frame-toggle-task-badge" aria-hidden="true"></span>' +
                        '<span class="stage-select-frame-toggle-icon" aria-hidden="true">▾</span>' +
                    '</button>' +
                    '<span class="stage-select-region" id="stage-select-region"></span>' +
                '</div>' +
                '<div class="stage-select-tabs" id="stage-select-tabs"></div>' +
                '<div class="stage-select-tools">' +
                    '<label class="stage-select-fixture-label">fixture</label>' +
                    '<select id="stage-select-fixture">' +
                        '<option value="mixed">mixed</option>' +
                        '<option value="allUnlocked">allUnlocked</option>' +
                        '<option value="challenge">challenge</option>' +
                    '</select>' +
                    '<span class="stage-select-badge" id="stage-select-badge">DEV</span>' +
                    '<button class="stage-select-close-btn" type="button" title="关闭" aria-label="关闭" data-audio-cue="back">✕</button>' +
                '</div>' +
            '</div>' +
            '<div class="stage-select-body">' +
                '<div class="stage-select-stage-shell" id="stage-select-stage-shell">' +
                    '<div class="stage-select-stage" id="stage-select-stage">' +
                        '<img class="stage-select-bg" id="stage-select-bg" alt="选关背景">' +
                        '<div class="stage-select-nav-layer" id="stage-select-nav-layer"></div>' +
                        '<div class="stage-select-button-layer" id="stage-select-button-layer"></div>' +
                        // P2：hover 卡整体迁出 role=button 节点，消除嵌套 button 语义；
                        // 卡片层在按钮层之上，几何锚点（.stage-select-card-anchor）与节点同位同 transform。
                        '<div class="stage-select-card-layer" id="stage-select-card-layer"></div>' +
                    '</div>' +
                    // P2：pinned 决策检查器——浮层/底部面板形态挂在舞台壳内（不压缩地图），runtime/dev 同构。
                    '<div class="stage-select-inspector" id="stage-select-inspector" role="region" aria-label="关卡决策" hidden>' +
                        '<span class="stage-select-inspector-preview">' +
                            '<img class="stage-select-inspector-preview-img" id="stage-select-inspector-preview" alt="">' +
                        '</span>' +
                        '<div class="stage-select-inspector-main">' +
                            '<div class="stage-select-inspector-head">' +
                                // 打磨批视觉同族化：红色切角装饰对齐 hover 卡 .stage-select-card-corner 语言
                                '<span class="stage-select-inspector-corner" aria-hidden="true"></span>' +
                                '<span class="stage-select-inspector-name" id="stage-select-inspector-name"></span>' +
                                '<span class="stage-select-inspector-type" id="stage-select-inspector-type"></span>' +
                                '<button type="button" class="stage-select-inspector-close" id="stage-select-inspector-close" aria-label="关闭决策检查器" title="关闭（Esc）" data-audio-cue="back">✕</button>' +
                            '</div>' +
                            '<div class="stage-select-inspector-lock" id="stage-select-inspector-lock" role="note" hidden></div>' +
                            '<div class="stage-select-inspector-task" id="stage-select-inspector-task" hidden></div>' +
                            '<div class="stage-select-inspector-detail" id="stage-select-inspector-detail"></div>' +
                            '<div class="stage-select-inspector-difficulties" id="stage-select-inspector-difficulties" role="group" aria-label="难度选择"></div>' +
                        '</div>' +
                    '</div>' +
                '</div>' +
                '<div class="stage-select-side">' +
                    '<div class="stage-select-side-title">静态复刻</div>' +
                    '<div class="stage-select-summary" id="stage-select-summary"></div>' +
                    '<div class="stage-select-dev-log" id="stage-select-dev-log">等待交互</div>' +
                '</div>' +
            '</div>';

        S._shellEl = S._el.querySelector('#stage-select-stage-shell');
        S._stageEl = S._el.querySelector('#stage-select-stage');
        S._backgroundEl = S._el.querySelector('#stage-select-bg');
        S._buttonLayerEl = S._el.querySelector('#stage-select-button-layer');
        S._cardLayerEl = S._el.querySelector('#stage-select-card-layer');
        S._navLayerEl = S._el.querySelector('#stage-select-nav-layer');
        S._inspectorEl = S._el.querySelector('#stage-select-inspector');
        S._inspectorPreviewEl = S._el.querySelector('#stage-select-inspector-preview');
        S._inspectorNameEl = S._el.querySelector('#stage-select-inspector-name');
        S._inspectorTypeEl = S._el.querySelector('#stage-select-inspector-type');
        S._inspectorLockEl = S._el.querySelector('#stage-select-inspector-lock');
        S._inspectorTaskEl = S._el.querySelector('#stage-select-inspector-task');
        S._inspectorDetailEl = S._el.querySelector('#stage-select-inspector-detail');
        S._inspectorDiffEl = S._el.querySelector('#stage-select-inspector-difficulties');
        S._inspectorCloseEl = S._el.querySelector('#stage-select-inspector-close');
        S._tabsEl = S._el.querySelector('#stage-select-tabs');
        S._summaryEl = S._el.querySelector('#stage-select-summary');
        S._badgeEl = S._el.querySelector('#stage-select-badge');
        S._logEl = S._el.querySelector('#stage-select-dev-log');
        S._fixtureSelectEl = S._el.querySelector('#stage-select-fixture');
        S._frameToggleEl = S._el.querySelector('#stage-select-frame-toggle');
        S._frameToggleLabelEl = S._el.querySelector('#stage-select-frame-toggle-label');
        S._frameToggleCounterEl = S._el.querySelector('#stage-select-frame-toggle-counter');
        S._frameToggleTaskBadgeEl = S._el.querySelector('#stage-select-frame-toggle-task-badge');

        S._el.querySelector('.stage-select-close-btn').addEventListener('click', requestClose);
        S._frameToggleEl.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            var willOpen = !S._frameMenuOpen;
            setFrameMenuOpen(willOpen);
            if (willOpen) focusActiveFrameTab();
        });
        S._frameToggleEl.addEventListener('keydown', handleFrameToggleKey);
        S._tabsEl.addEventListener('click', function(e) {
            e.stopPropagation();
        });
        S._tabsEl.addEventListener('keydown', handleFrameMenuKey);
        S._el.addEventListener('click', function(e) {
            if (!S._frameMenuOpen || !VM.isRuntimeMode()) return;
            if (StageSelectCore.isWithin(e.target, S._frameToggleEl) || StageSelectCore.isWithin(e.target, S._tabsEl)) return;
            setFrameMenuOpen(false);
        });
        S._el.addEventListener('keydown', function(e) {
            // P2 页内 Esc 分层消费（dev/harness 路径；正式 runtime 物理 Esc 由 C# 钩子截获，
            // 经 panel_esc → onRequestClose('escape') 走 requestClose 内的同序分层，两条路径互斥不重叠）。
            // defaultPrevented = 区域菜单 toggle/tabs 已消费本次 Esc，不再落穿到检查器层。
            if (e.key !== 'Escape' || e.defaultPrevented) return;
            if (S._frameMenuOpen && VM.isRuntimeMode()) {
                e.preventDefault();
                setFrameMenuOpen(false);
                if (S._frameToggleEl) S._frameToggleEl.focus();
                return;
            }
            if (StageSelectInspector.isInspectorOpen()) {
                e.preventDefault();
                StageSelectInspector.clearSelection({ restoreFocus: true });
            }
        });
        S._fixtureSelectEl.addEventListener('change', function() {
            applyFixture(S._fixtureSelectEl.value);
            renderCurrentFrame();
        });
        // P2：难度点击委派上移到面板根，同时覆盖卡片层 hover 卡与 pinned 检查器里的难度按钮。
        S._el.addEventListener('click', StageSelectInspector.handleDifficultyClick);
        // P2：点舞台空白取消选中（节点 / 导航 / hover 卡 / 检查器内部点击除外）。
        S._shellEl.addEventListener('click', StageSelectInspector.handleStageBlankClick);
        S._inspectorCloseEl.addEventListener('click', function(e) {
            e.stopPropagation();
            StageSelectInspector.clearSelection({ restoreFocus: true });
        });
        // 打磨批：检查器内 ←/→ 难度导航 / Enter 提交 / ↑↓ 无操作，语义实现在 inspector.handleInspectorKey。
        S._inspectorEl.addEventListener('keydown', StageSelectInspector.handleInspectorKey);
        // 打磨批二轮：自有键盘模态跟踪（capture 阶段先于各节点/检查器 handler 落地）——
        // 任意 keydown 记键盘模态，任意 pointerdown 记指针模态并即刻剥掉所有节点的 .is-kb-focus
        // （覆盖「点击已持焦节点、focusin 不再重燃」的情形）。节点焦点环只由 .is-kb-focus 驱动，
        // 不再信 :focus-visible 启发式：WebView2 宿主的 MoveFocus(Programmatic) 等嵌入焦点链会
        // 让鼠标点击也命中 :focus-visible（实机蓝环压卡事故的根因之一）。
        S._el.addEventListener('keydown', function() {
            S._lastInputKeyboard = true;
            // 模态翻转对称处理：pointerdown 即刻剥环，keydown 即刻补环——覆盖「节点已被鼠标
            // 持焦、Esc/按键后 focus() 为空操作、focusin 不再重燃」的路径（如实机 Esc 取消选中）。
            var active = document.activeElement;
            if (active && active.classList && active.classList.contains('stage-select-stage-button')
                    && StageSelectCore.isWithin(active, S._buttonLayerEl)) {
                active.classList.add('is-kb-focus');
            }
        }, true);
        S._el.addEventListener('pointerdown', function() {
            S._lastInputKeyboard = false;
            clearKbFocusClasses();
        }, true);

        renderTabs();
        return S._el;
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 生命周期（对位 arena-shell：跨模块编排，领域规则仍在各模块内）
    // ════════════════════════════════════════════════════════════════════════════
    function onOpen(root, initData) {
        var manifest = StageSelectData.getManifest();
        S._session += 1;
        S._pendingReq = {};
        S._panelInstanceId = StageSelectBridge.readInitInstanceId(initData);
        S._lastAppliedStateRevision = 0;
        S._runtimeSnapshot = null;
        S._busyStageName = '';
        S._lastError = '';
        S._mode = initData && initData.mode || 'dev';
        S.DESIGN_W = manifest.designSize && manifest.designSize.width || 1024;
        S.DESIGN_H = manifest.designSize && manifest.designSize.height || 576;
        S._fixtureName = initData && initData.fixture || 'mixed';
        S._currentFrameLabel = initData && initData.frameLabel || initData && initData.page || manifest.frameOrder[0];
        S._returnFrameLabel = initData && initData.returnFrameLabel || S._currentFrameLabel;
        applyFixture(S._fixtureName);
        if (S._fixtureSelectEl) S._fixtureSelectEl.value = S._fixtureName;
        if (S._el) S._el.classList.toggle('is-runtime', VM.isRuntimeMode());
        setFrameMenuOpen(false);
        S._lastDifficultyClick = null;
        // P2：每次打开重置选中态与卡片/焦点跟踪（create 只跑一次，元素跨 open 复用）
        S._selectedStageId = '';
        S._tabbableStageId = '';
        S._hoverStageId = '';
        S._cardHoverStageId = '';
        S._focusStageId = '';
        S._lastInputKeyboard = false; // 打磨批二轮：键盘模态位随面板打开复位（默认指针模态）
        renderTabs();
        attachScaleWatcher();
        renderCurrentFrame();
        StageSelectBridge.requestSnapshot();
        syncStageLayout();
        root.classList.remove('is-entered');
        StageSelectCore.scheduleTimer(function() { if (root) root.classList.add('is-entered'); }, 20);
    }

    // Host 同名 reopen（DoRebind）：不重建 DOM/选中态，只换绑会话令牌并补一次快照。
    function onRebind(root, initData) {
        S._panelInstanceId = StageSelectBridge.readInitInstanceId(initData);
        StageSelectBridge.invalidatePendingRequests('rebind');
        S._lastAppliedStateRevision = 0;
        if (initData && initData.frameLabel && StageSelectData.getFrame(initData.frameLabel)) {
            S._currentFrameLabel = initData.frameLabel;
        }
        if (initData && initData.returnFrameLabel && StageSelectData.getFrame(initData.returnFrameLabel)) {
            S._returnFrameLabel = initData.returnFrameLabel;
        }
        StageSelectCore.logDev('session rebound: ' + (S._panelInstanceId || '(unbound)'));
        StageSelectBridge.requestSnapshot();
        return true;
    }

    // onRequestClose：遮罩点击 / C# panel_esc（物理 Escape）/ 关闭钮共用。
    // P2 Esc 分层消费：关区域菜单 > 关检查器（焦点归还触发节点）> 关面板。
    function requestClose(reason) {
        if (reason === 'escape') {
            if (S._frameMenuOpen) {
                setFrameMenuOpen(false);
                if (S._frameToggleEl) S._frameToggleEl.focus();
                return;
            }
            if (StageSelectInspector.isInspectorOpen()) {
                StageSelectInspector.clearSelection({ restoreFocus: true });
                return;
            }
        }
        StageSelectBridge.invalidatePendingRequests('requestClose');
        Panels.close();
        if (typeof Bridge !== 'undefined' && Bridge && Bridge.send) {
            Bridge.send({ type: 'panel', panel: 'stage-select', cmd: 'close' });
        }
    }

    // 幂等：任何关闭路径（requestClose→Panels.close / C# close / 切面板）都经此统一销毁
    function onClose() {
        setFrameMenuOpen(false);
        // P2：检查器销毁幂等——清选中态并隐藏，元素保留待下次 open 复用
        StageSelectInspector.clearSelection();
        S._hoverStageId = '';
        S._cardHoverStageId = '';
        S._focusStageId = '';
        S._tabbableStageId = '';
        // P3：C# 侧发起/切面板导致的关闭也在这里清 pending（requestClose 只覆盖 web 主动路径），
        // 在途回包随 session 自增一并失效。
        StageSelectBridge.invalidatePendingRequests('onClose');
        if (S._scaleHandle) { S._scaleHandle.detach(); S._scaleHandle = null; }
        StageSelectCore.clearTimers();
    }

    // fixture 装载编排：ViewModel 纯状态 + badge DOM 同步。
    function applyFixture(name) {
        VM.setFixture(name);
        if (S._badgeEl) S._badgeEl.textContent = S._fixture && S._fixture.challenge ? 'CHALLENGE' : 'DEV';
    }

    // runtime snapshot 应用编排：ViewModel 纯状态 + 全量重建 + dev log。
    function applyRuntimeSnapshot(snapshot) {
        VM.applySnapshot(snapshot);
        renderCurrentFrame();
        StageSelectCore.logDev('snapshot live: ' + VM.countUnlocked(S._runtimeSnapshot.unlockedStages) + ' unlocked');
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 帧菜单（区域 listbox）与 frame 路由编排
    // ════════════════════════════════════════════════════════════════════════════
    function renderTabs() {
        if (!S._tabsEl || !window.StageSelectData) return;
        var manifest = StageSelectData.getManifest();
        S._tabsEl.setAttribute('role', 'listbox');
        S._tabsEl.innerHTML = '';
        manifest.frameOrder.forEach(function(label, index) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'stage-select-tab';
            button.setAttribute('data-frame-label', label);
            button.setAttribute('data-frame-index', String(index));
            button.setAttribute('role', 'option');
            button.tabIndex = -1;
            button.innerHTML =
                '<span class="stage-select-tab-label">' + StageSelectCore.escapeHtml(label) + '</span>' +
                '<span class="stage-select-tab-task-badge" aria-hidden="true"></span>';
            button.addEventListener('click', function() {
                selectFrameTab(label);
            });
            S._tabsEl.appendChild(button);
        });
    }

    function selectFrameTab(label) {
        var sourceFrameLabel = S._currentFrameLabel;
        setFrame(label, 'tab');
        if (VM.isRuntimeMode() && label !== sourceFrameLabel) {
            StageSelectBridge.requestJumpFrame(label, { id: 'tab:' + label }, sourceFrameLabel);
        }
        setFrameMenuOpen(false);
        if (S._frameToggleEl) S._frameToggleEl.focus();
    }

    function focusActiveFrameTab() {
        if (!S._tabsEl) return;
        var active = S._tabsEl.querySelector('.stage-select-tab.is-active');
        if (!active) active = S._tabsEl.querySelector('.stage-select-tab');
        if (active) active.focus();
    }

    function handleFrameToggleKey(e) {
        if (!VM.isRuntimeMode()) return;
        if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            if (!S._frameMenuOpen) setFrameMenuOpen(true);
            focusActiveFrameTab();
        } else if (e.key === 'Escape' && S._frameMenuOpen) {
            e.preventDefault();
            setFrameMenuOpen(false);
        }
    }

    function handleFrameMenuKey(e) {
        if (!S._frameMenuOpen || !S._tabsEl) return;
        var nodes = S._tabsEl.querySelectorAll('.stage-select-tab');
        if (!nodes.length) return;
        var current = document.activeElement;
        var idx = -1;
        for (var i = 0; i < nodes.length; i += 1) {
            if (nodes[i] === current) { idx = i; break; }
        }
        var next = idx;
        switch (e.key) {
            case 'ArrowRight':
            case 'ArrowDown':
                next = idx < 0 ? 0 : (idx + 1) % nodes.length;
                break;
            case 'ArrowLeft':
            case 'ArrowUp':
                next = idx < 0 ? 0 : (idx - 1 + nodes.length) % nodes.length;
                break;
            case 'Home':
                next = 0;
                break;
            case 'End':
                next = nodes.length - 1;
                break;
            case 'Enter':
            case ' ':
                if (idx >= 0) {
                    e.preventDefault();
                    selectFrameTab(nodes[idx].getAttribute('data-frame-label'));
                }
                return;
            case 'Escape':
                e.preventDefault();
                setFrameMenuOpen(false);
                if (S._frameToggleEl) S._frameToggleEl.focus();
                return;
            default:
                return;
        }
        e.preventDefault();
        nodes[next].focus();
    }

    // frame 路由编排：ViewModel.tryRouteFrame 纯状态迁移成功后才重渲染。
    function setFrame(label, source) {
        if (!VM.tryRouteFrame(label)) return;
        StageSelectCore.logDev((source || 'route') + ': ' + label);
        renderCurrentFrame();
    }

    function setFrameMenuOpen(open) {
        S._frameMenuOpen = !!open && VM.isRuntimeMode();
        if (S._el) S._el.classList.toggle('is-frame-menu-open', S._frameMenuOpen);
        if (S._frameToggleEl) S._frameToggleEl.setAttribute('aria-expanded', S._frameMenuOpen ? 'true' : 'false');
        if (S._frameMenuOpen) StageSelectCore.clearError();
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 帧渲染
    // ════════════════════════════════════════════════════════════════════════════
    function renderCurrentFrame() {
        var frame = StageSelectData.getFrame(S._currentFrameLabel);
        if (!frame) return;
        // P2：全量重建会丢弃焦点/选中——先按 stage id 快照，重建后恢复。
        var focusSnapshot = captureFocusSnapshot();
        S._currentFrameLabel = frame.frameLabel;
        renderHeader(frame);
        renderBackground(frame);
        renderStageButtons(frame);
        renderNavButtons(frame);
        applySelectionClasses();
        applyRovingTabIndex();
        StageSelectInspector.renderInspector();
        updateCardVisibility();
        restoreFocusSnapshot(focusSnapshot);
        syncStageLayout();
    }

    function renderHeader(frame) {
        var tabs = S._tabsEl ? S._tabsEl.querySelectorAll('.stage-select-tab') : [];
        var taskTargets = VM.getTaskTargets();
        var activeIndex = -1;
        for (var i = 0; i < tabs.length; i += 1) {
            var isActive = tabs[i].getAttribute('data-frame-label') === frame.frameLabel;
            tabs[i].classList.toggle('is-active', isActive);
            tabs[i].setAttribute('aria-selected', isActive ? 'true' : 'false');
            if (isActive) activeIndex = i;
        }
        syncFrameTaskBadges(taskTargets);
        var region = S._el.querySelector('#stage-select-region');
        if (region) region.textContent = frame.frameLabel;
        if (S._frameToggleLabelEl) S._frameToggleLabelEl.textContent = frame.frameLabel;
        if (S._frameToggleCounterEl) {
            S._frameToggleCounterEl.textContent = tabs.length
                ? (activeIndex >= 0 ? (activeIndex + 1) : 1) + '/' + tabs.length
                : '';
        }
        if (S._frameToggleTaskBadgeEl) {
            S._frameToggleTaskBadgeEl.textContent = taskTargets.total ? VM.formatTaskCount(taskTargets.total) : '';
            S._frameToggleTaskBadgeEl.style.display = taskTargets.total ? '' : 'none';
        }
        if (S._frameToggleEl) {
            S._frameToggleEl.classList.toggle('has-task', taskTargets.total > 0);
            S._frameToggleEl.setAttribute('data-task-count', String(taskTargets.total || 0));
        }
        if (S._summaryEl) {
            S._summaryEl.innerHTML =
                '<div>frame: <b>' + StageSelectCore.escapeHtml(frame.frameLabel) + '</b></div>' +
                '<div>decorations: <b>' + (frame.decorations || []).length + '</b></div>' +
                '<div>stage buttons: <b>' + (frame.stageButtons || []).length + '</b></div>' +
                '<div>nav buttons: <b>' + (frame.navButtons || []).length + '</b></div>' +
                '<div>background: <b>' + StageSelectCore.escapeHtml(frame.background && frame.background.mode || 'missing') + '</b></div>' +
                '<div>fixture: <b>' + StageSelectCore.escapeHtml(S._fixtureName) + '</b></div>' +
                '<div>task targets: <b>' + taskTargets.total + '</b></div>' +
                '<div>runtime: <b>' + (S._runtimeSnapshot ? 'live' : 'fixture') + '</b></div>' +
                (S._lastError ? '<div class="stage-select-error-line">error: <b>' + StageSelectCore.escapeHtml(S._lastError) + '</b></div>' : '');
        }
    }

    function syncFrameTaskBadges(taskTargets) {
        if (!S._tabsEl) return;
        var tabs = S._tabsEl.querySelectorAll('.stage-select-tab');
        for (var i = 0; i < tabs.length; i += 1) {
            var label = tabs[i].getAttribute('data-frame-label') || '';
            var count = taskTargets && taskTargets.byFrame ? Number(taskTargets.byFrame[label] || 0) : 0;
            var badge = tabs[i].querySelector('.stage-select-tab-task-badge');
            tabs[i].classList.toggle('has-task', count > 0);
            tabs[i].setAttribute('data-task-count', String(count));
            if (badge) {
                badge.textContent = count ? VM.formatTaskCount(count) : '';
                badge.style.display = count ? '' : 'none';
            }
        }
    }

    function renderBackground(frame) {
        var bg = frame.background || {};
        if (S._backgroundEl) {
            S._backgroundEl.src = StageSelectCore.resolveAssetUrl(bg.assetUrl || '');
            S._backgroundEl.alt = frame.frameLabel + ' 背景';
            S._backgroundEl.setAttribute('data-mode', bg.mode || 'missing');
            applyBackgroundRect(bg.rect);
        }
    }

    function applyBackgroundRect(rect) {
        var r = rect || { x: 0, y: 0, w: S.DESIGN_W, h: S.DESIGN_H };
        var x = Number(r.x) || 0;
        var y = Number(r.y) || 0;
        var w = Number(r.w) || S.DESIGN_W;
        var h = Number(r.h) || S.DESIGN_H;
        S._backgroundEl.style.left = x + 'px';
        S._backgroundEl.style.top = y + 'px';
        if (VM.isRuntimeMode()) {
            // 沉浸全屏化 2026-06-11：runtime 下底图至少铺到舞台右/下边缘——16 帧源 rect 高度参差
            // （552/555/556/614/768），原本 h<576 帧底沿露 #020617 黑条。只放大不缩小、不改 x/y：
            // under-fill 帧拉伸填满（背景图 4% 拉伸无感、marker/按钮在独立层不受影响），over-fill/偏移帧
            // 保持原裁切窗口。dev 静态复刻保留精确 manifest rect 以对齐原版审计。
            w = Math.max(w, S.DESIGN_W - x);
            h = Math.max(h, S.DESIGN_H - y);
        }
        S._backgroundEl.style.width = w + 'px';
        S._backgroundEl.style.height = h + 'px';
    }

    function renderStageButtons(frame) {
        S._buttonLayerEl.innerHTML = '';
        if (S._cardLayerEl) S._cardLayerEl.innerHTML = '';
        (frame.decorations || []).forEach(function(item) {
            S._buttonLayerEl.appendChild(createDecoration(item));
        });
        (frame.stageButtons || []).forEach(function(button) {
            var parts = createStageButton(button);
            S._buttonLayerEl.appendChild(parts.node);
            if (parts.anchor && S._cardLayerEl) S._cardLayerEl.appendChild(parts.anchor);
        });
    }

    function createDecoration(item) {
        var node = document.createElement('span');
        node.className = 'stage-select-decoration';
        node.classList.add('is-' + (item.kind || 'decor'));
        node.classList.add('is-' + (item.variant || 'default'));
        node.setAttribute('data-decoration-id', item.id || '');
        node.setAttribute('data-decoration-kind', item.kind || '');
        node.style.left = (Number(item.x) || 0) + 'px';
        node.style.top = (Number(item.y) || 0) + 'px';
        node.style.width = (Number(item.width) || 0) + 'px';
        node.style.height = (Number(item.height) || 0) + 'px';
        node.innerHTML = '<img class="stage-select-decoration-img" src="' + StageSelectCore.escapeAttr(StageSelectCore.resolveAssetUrl(item.assetUrl || '')) + '" alt="" draggable="false">';
        return node;
    }

    function createStageButton(button) {
        var state = VM.getStageState(button.stageName);
        var detail = StageSelectCore.buildStageDetail(button, state);
        var sizing = computeCardSizing(button, detail);
        var direct = VM.isDirectEntry(button);
        var directSizing = direct ? computeDirectSizing(button) : null;
        var mapLayout = direct && button.entryKind === 'map' && button.directLayout ? buildMapDirectLayout(button.directLayout) : null;
        var displayName = VM.getStageDisplayName(button);
        var node = document.createElement('div');
        node.className = 'stage-select-stage-button';
        if (direct) {
            node.classList.add('is-direct-entry');
            node.classList.add('is-' + (button.entryKind || 'direct') + '-entry');
            node.style.setProperty('--stage-direct-width', directSizing.width + 'px');
            node.style.setProperty('--stage-direct-height', directSizing.height + 'px');
            if (mapLayout) {
                applyMapDirectLayoutVars(node, mapLayout);
            }
        }
        // roving tabindex：节点簇只有一个 Tab 停靠点，节点间移动走方向键几何导航。
        node.tabIndex = -1;
        node.setAttribute('role', 'button');
        node.setAttribute('data-stage-name', button.stageName);
        node.setAttribute('data-stage-id', button.id);
        node.setAttribute('data-entry-kind', button.entryKind || 'difficulty');
        node.setAttribute('data-card-name-lines', String(sizing.nameLines));
        if (!direct) {
            // 选中即打开 pinned 决策检查器：aria-expanded 暴露检查器开阖，aria-controls 指向检查器。
            node.setAttribute('aria-expanded', 'false');
            node.setAttribute('aria-controls', 'stage-select-inspector');
        }
        if (mapLayout) {
            node.style.left = (button.x + mapLayout.bounds.x) + 'px';
            node.style.top = (button.y + mapLayout.bounds.y) + 'px';
            node.style.width = mapLayout.bounds.width + 'px';
            node.style.minHeight = mapLayout.bounds.height + 'px';
        } else {
            node.style.left = button.x + 'px';
            node.style.top = button.y + 'px';
        }
        node.style.setProperty('--stage-card-width', sizing.width + 'px');
        node.style.setProperty('--stage-card-height', sizing.cardHeight + 'px');
        if (button.y < 60) node.classList.add('is-edge-top');
        if (button.x < 40) node.classList.add('is-edge-left');
        if (button.x > 790) node.classList.add('is-edge-right');
        if (!state.unlocked) {
            node.classList.add('is-locked');
            // 锁定节点仍可聚焦：aria-disabled + 名称后缀让焦点可读锁定态，原因文案由检查器展示。
            node.setAttribute('aria-disabled', 'true');
            node.setAttribute('aria-label', displayName + '（未解锁）');
        }
        if (state.task) node.classList.add('is-task');
        if (S._busyStageName && S._busyStageName === button.stageName) node.classList.add('is-busy');
        node.innerHTML =
            '<span class="stage-select-hit-zone" aria-hidden="true"></span>' +
            renderStageMarkerSvg() +
            '<span class="stage-select-stage-name">' + StageSelectCore.escapeHtml(displayName) + '</span>' +
            renderStageLockSvg() +
            '<span class="stage-select-task-pulse"></span>' +
            // 打磨批：选中光环独立元素（task-pulse 同族柔和外发光），替代旧 hit-zone 硬 box-shadow 圆环
            '<span class="stage-select-selected-ring" aria-hidden="true"></span>';
        node.addEventListener('click', function(e) {
            if (direct) {
                // 直达入口（外交地图 / 副本任务）：保持一步跳转，不经过检查器。
                StageSelectInspector.requestStageActivation(button, '', null);
                return;
            }
            // 普通关卡：点击 = 选中并 pin 检查器；再点同节点取消选中。
            StageSelectInspector.toggleStageSelection(button.id);
            StageSelectCore.logDev('select stage: ' + button.stageName + (state.unlocked ? '' : ' (locked fixture)'));
        });
        node.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                if (direct) {
                    StageSelectInspector.requestStageActivation(button, '', null);
                    return;
                }
                // 键盘路径：Enter/Space 选中并打开检查器，焦点移交检查器内难度（锁定节点移交关闭钮）。
                StageSelectInspector.selectStage(button.id, { focusInspector: true });
                StageSelectCore.logDev('select stage: ' + button.stageName + (state.unlocked ? '' : ' (locked fixture)'));
                return;
            }
            if (e.key === 'ArrowRight' || e.key === 'ArrowLeft' || e.key === 'ArrowUp' || e.key === 'ArrowDown') {
                e.preventDefault();
                // 打磨批：检查器打开期间方向键归检查器（焦点困在检查器内）——
                // 节点上的方向键不再走几何导航，回引焦点到检查器难度行；Esc 分层不变。
                if (StageSelectInspector.isInspectorOpen()) {
                    StageSelectInspector.focusInspectorPrimary();
                    return;
                }
                moveNodeFocus(button, e.key);
            }
        });
        // hover 卡可见性跟踪（卡已迁出节点，纯 JS 驱动 .is-card-open）：
        // 指针悬停节点或卡本体、或焦点落在节点上时显示；选中节点由检查器承接、锁定节点保持不显示。
        // leave 侧延迟一拍合并：指针从节点移入卡片（或反向）时 leave/enter 同帧竞争，
        // 延迟到边界事件序列结束后统一裁决，避免交接闪烁。
        // 打磨批二轮：选中节点另有两层 DOM 保险——锚点镜像 .is-selected（CSS 硬隐藏卡片，
        // 见 applySelectionClasses）、节点镜像 .has-open-card（卡开期间键盘焦点环让位，
        // 见 updateCardVisibility）；节点蓝环改 .is-kb-focus 键盘模态类驱动（见 focusin）。
        node.addEventListener('pointerenter', function() {
            S._hoverStageId = button.id;
            updateCardVisibility();
        });
        node.addEventListener('pointerleave', function() {
            if (S._hoverStageId === button.id) S._hoverStageId = '';
            scheduleCardVisibilityUpdate();
        });
        node.addEventListener('focusin', function() {
            S._focusStageId = button.id;
            S._tabbableStageId = button.id;
            applyRovingTabIndex();
            // 打磨批二轮：焦点环只随键盘模态挂 .is-kb-focus（指针路径持焦不出蓝环）
            node.classList.toggle('is-kb-focus', !!S._lastInputKeyboard);
            updateCardVisibility();
        });
        node.addEventListener('focusout', function() {
            if (S._focusStageId === button.id) S._focusStageId = '';
            node.classList.remove('is-kb-focus');
            updateCardVisibility();
        });
        return { node: node, anchor: direct ? null : createCardAnchor(button, state, detail, sizing, displayName) };
    }

    // hover 卡锚点：与关卡节点同位同 transform 的非交互层，承接迁出的卡片（含原生难度 button），
    // 消除「role=button 内嵌 button」的嵌套交互语义。节点上的状态类 / 卡片尺寸变量同步镜像到锚点，
    // 让既有卡片 CSS（edge 吸附 / data-card-name-lines / 自适应宽高）无需改几何即可继续生效。
    function createCardAnchor(button, state, detail, sizing, displayName) {
        var anchor = document.createElement('div');
        anchor.className = 'stage-select-card-anchor';
        anchor.setAttribute('data-stage-name', button.stageName);
        anchor.setAttribute('data-stage-id', button.id);
        anchor.setAttribute('data-card-name-lines', String(sizing.nameLines));
        anchor.style.left = button.x + 'px';
        anchor.style.top = button.y + 'px';
        anchor.style.setProperty('--stage-card-width', sizing.width + 'px');
        anchor.style.setProperty('--stage-card-height', sizing.cardHeight + 'px');
        if (button.y < 60) anchor.classList.add('is-edge-top');
        if (button.x < 40) anchor.classList.add('is-edge-left');
        if (button.x > 790) anchor.classList.add('is-edge-right');
        if (!state.unlocked) anchor.classList.add('is-locked');
        if (state.task) anchor.classList.add('is-task');
        if (S._busyStageName && S._busyStageName === button.stageName) anchor.classList.add('is-busy');
        anchor.innerHTML =
            '<span class="stage-select-card">' +
                '<span class="stage-select-card-corner" aria-hidden="true"></span>' +
                '<span class="stage-select-card-name">' + StageSelectCore.escapeHtml(displayName) + '</span>' +
                '<span class="stage-select-preview-wrap">' +
                    '<img class="stage-select-preview" src="' + StageSelectCore.escapeAttr(StageSelectCore.resolveAssetUrl(button.previewUrl)) + '" alt="' + StageSelectCore.escapeAttr(displayName) + ' 预览" data-preview-source="' + StageSelectCore.escapeAttr(button.previewSource || '') + '">' +
                '</span>' +
                '<span class="stage-select-card-detail">' + detail.html + '</span>' +
                '<span class="stage-select-difficulties">' + renderDifficulties(button, state, false) + '</span>' +
            '</span>';
        var cardEl = anchor.firstChild;
        cardEl.addEventListener('pointerenter', function() {
            S._cardHoverStageId = button.id;
            updateCardVisibility();
        });
        cardEl.addEventListener('pointerleave', function() {
            if (S._cardHoverStageId === button.id) S._cardHoverStageId = '';
            scheduleCardVisibilityUpdate();
        });
        return anchor;
    }

    function buildMapDirectLayout(layout) {
        var marker = layout && layout.marker || {};
        var text = layout && layout.text || {};
        var markerX = StageSelectCore.finiteNumber(marker.x, 0);
        var markerY = StageSelectCore.finiteNumber(marker.y, 120);
        var textX = StageSelectCore.finiteNumber(text.x, -68.5);
        var textY = StageSelectCore.finiteNumber(text.y, 135.7);
        var textW = StageSelectCore.finiteNumber(text.width, 137);
        var textH = StageSelectCore.finiteNumber(text.height, 34.3);
        var minX = Math.min(markerX - 22, textX);
        var minY = Math.min(markerY - 22, textY);
        var maxX = Math.max(markerX + 22, textX + textW);
        var maxY = Math.max(markerY + 22, textY + textH);
        return {
            marker: { x: markerX - minX, y: markerY - minY },
            text: { x: textX - minX, y: textY - minY, width: textW, height: textH },
            bounds: {
                x: minX,
                y: minY,
                width: Math.max(1, maxX - minX),
                height: Math.max(1, maxY - minY)
            }
        };
    }

    function applyMapDirectLayoutVars(node, layout) {
        var marker = layout && layout.marker || {};
        var text = layout && layout.text || {};
        node.style.setProperty('--stage-map-marker-x', StageSelectCore.numericCss(marker.x, 0));
        node.style.setProperty('--stage-map-marker-y', StageSelectCore.numericCss(marker.y, 120));
        node.style.setProperty('--stage-map-text-x', StageSelectCore.numericCss(text.x, -68.5));
        node.style.setProperty('--stage-map-text-y', StageSelectCore.numericCss(text.y, 135.7));
        node.style.setProperty('--stage-map-text-width', StageSelectCore.numericCss(text.width, 137));
        node.style.setProperty('--stage-map-text-height', StageSelectCore.numericCss(text.height, 34.3));
    }

    function renderStageMarkerSvg() {
        return '<span class="stage-select-marker" aria-hidden="true">' +
            '<svg class="stage-select-marker-svg" viewBox="-293 -293 586 586" focusable="false">' +
                '<path class="stage-select-marker-fill" fill-rule="evenodd" d="' +
                    'M118 -118 Q167 -69 167 1 Q167 70 118 119 Q69 168 0 168 Q-69 168 -118 119 Q-167 70 -167 1 Q-167 -69 -118 -118 Q-69 -167 0 -166 Q69 -167 118 -118 Z ' +
                    'M168 -167 Q237 -98 237 1 Q237 99 168 168 Q99 238 1 238 Q-98 238 -167 168 Q-237 99 -236 1 Q-237 -98 -167 -167 Q-98 -237 1 -236 Q99 -237 168 -167 Z ' +
                    'M207 -207 Q292 -121 293 1 Q293 122 207 207 Q121 293 0 293 Q-121 293 -207 207 Q-293 122 -292 1 Q-293 -121 -207 -207 Q-121 -292 0 -292 Q121 -292 207 -207 Z' +
                '"/>' +
            '</svg>' +
        '</span>';
    }

    function renderStageLockSvg() {
        return '<span class="stage-select-lock" aria-hidden="true">' +
            '<svg class="stage-select-lock-svg" viewBox="-180 -270 360 540" focusable="false">' +
                '<path class="stage-select-lock-body" fill-rule="evenodd" d="' +
                    'M93 -228 Q131 -190 131 -136 L131 -32 L132 -32 Q178 -32 178 13 L178 222 Q178 267 132 267 L-133 267 Q-178 267 -178 222 L-178 13 Q-178 -32 -133 -32 L-132 -32 L-132 -136 Q-132 -190 -93 -228 Q-55 -267 0 -267 Q54 -267 93 -228 Z ' +
                    'M67 -203 Q95 -175 95 -136 L95 -32 L-96 -32 L-96 -136 Q-96 -175 -68 -203 Q-40 -231 0 -231 Q39 -231 67 -203 Z' +
                '"/>' +
                '<path class="stage-select-lock-hole" d="' +
                    'M13 166 L-14 166 L-14 109 L-30 99 Q-43 86 -43 69 Q-43 51 -30 39 Q-18 26 0 26 Q17 26 30 39 Q42 51 42 69 Q42 86 30 99 L13 109 L13 166 Z' +
                '"/>' +
            '</svg>' +
        '</span>';
    }

    function renderDifficulties(button, state, tabbable) {
        var difficulties = VM.isChallengeMode() ? ['地狱'] : ['简单', '冒险', '修罗', '地狱'];
        // hover 卡内按钮是鼠标快捷路径（tabIndex=-1 不进 Tab 序）；检查器内按钮承接键盘路径。
        var tabAttr = tabbable === false ? ' tabindex="-1"' : '';
        return difficulties.map(function(name) {
            var active = state.task && state.highestDifficulty === name ? ' is-recommended' : '';
            return '<button type="button" class="stage-select-difficulty is-' + difficultyClass(name) + active + '" data-stage-name="' + StageSelectCore.escapeAttr(button.stageName) + '" data-entry-kind="' + StageSelectCore.escapeAttr(button.entryKind || 'difficulty') + '" data-difficulty="' + StageSelectCore.escapeAttr(name) + '"' + tabAttr + '>' + StageSelectCore.escapeHtml(name) + '</button>';
        }).join('');
    }

    function difficultyClass(name) {
        if (name === '简单') return 'easy';
        if (name === '冒险') return 'adventure';
        if (name === '修罗') return 'shura';
        if (name === '地狱') return 'hell';
        return 'unknown';
    }

    function renderNavButtons(frame) {
        S._navLayerEl.innerHTML = '';
        (frame.navButtons || []).forEach(function(nav) {
            var visualKind = getNavVisualKind(nav);
            var node = document.createElement('button');
            node.type = 'button';
            node.className = 'stage-select-nav-button is-' + visualKind;
            node.style.left = nav.x + 'px';
            node.style.top = nav.y + 'px';
            node.setAttribute('data-nav-id', nav.id);
            node.setAttribute('data-action-kind', nav.actionKind || '');
            node.setAttribute('data-library-item', nav.libraryItemName || '');
            node.textContent = getNavDisplayLabel(nav, visualKind);
            node.addEventListener('click', function(e) {
                e.stopPropagation();
                if (nav.actionKind === 'localFrame' && nav.targetFrameLabel) {
                    var sourceFrameLabel = S._currentFrameLabel;
                    setFrame(nav.targetFrameLabel, 'nav');
                    if (VM.isRuntimeMode()) StageSelectBridge.requestJumpFrame(nav.targetFrameLabel, nav, sourceFrameLabel);
                } else if (VM.isRuntimeMode() && (nav.actionKind === 'flashJumpCurrent' || nav.actionKind === 'flashJumpFrameValue')) {
                    StageSelectBridge.requestReturnFrame(VM.resolveReturnFrameLabel(nav), nav);
                } else {
                    StageSelectCore.logDev('nav static only: ' + (nav.targetFrameLabel || nav.actionKind));
                }
            });
            S._navLayerEl.appendChild(node);
        });
    }

    function getNavVisualKind(nav) {
        var item = nav && nav.libraryItemName || '';
        if (item === '选关界面UI/Symbol 3308') return 'entry-yellow';
        if (item === '试炼场深处按钮') return 'entry-red';
        if (item === 'sprite/Symbol 1025') return 'return';
        if (item === 'sprite/返回车库按钮') return 'return-garage';
        if (item === 'sprite/通用按钮') return 'generic';
        if (item.indexOf('选关界面UI/Symbol ') === 0) return 'scene-entry';
        return 'generic';
    }

    function getNavDisplayLabel(nav, visualKind) {
        var target = nav && nav.targetFrameLabel || '';
        if (visualKind === 'entry-yellow' || visualKind === 'entry-red') return '进入' + target;
        if (visualKind === 'return') return '返回';
        if (visualKind === 'return-garage') return '回A兵团车库';
        return target || nav.label || '返回';
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 卡片尺寸测量（2D 布局专属——ViewModel 不承载，经 directSizer 注入给 VM 导航几何）
    // ════════════════════════════════════════════════════════════════════════════
    function getDetailMeasurer() {
        if (_detailMeasurer || typeof document === 'undefined' || !document.body) return _detailMeasurer;
        _detailMeasurer = document.createElement('div');
        _detailMeasurer.setAttribute('aria-hidden', 'true');
        _detailMeasurer.style.cssText = [
            'position:absolute',
            'visibility:hidden',
            'pointer-events:none',
            'left:-9999px',
            'top:0',
            'box-sizing:content-box',
            'font-family:"Microsoft YaHei","Microsoft JhengHei",Arial,sans-serif',
            'font-size:14px',
            'white-space:normal',
            'word-break:break-all',
            'overflow-wrap:anywhere',
            'padding:0',
            'margin:0',
            'border:0'
        ].join(';');
        document.body.appendChild(_detailMeasurer);
        return _detailMeasurer;
    }

    // Measure exact rendered height of the detail HTML at a given inner width + line-height.
    // Returns -1 if measurement is unavailable (test/SSR contexts).
    function measureDetailHeight(html, innerWidth, lineHeight) {
        var m = getDetailMeasurer();
        if (!m) return -1;
        m.style.width = innerWidth + 'px';
        m.style.lineHeight = lineHeight + 'px';
        m.innerHTML = html || '';
        return m.scrollHeight;
    }

    // Heuristic fallback when DOM measurement isn't available.
    function estimateStageCardHeight(text, charsPerLine, lineHeight, baseline, minH, maxH) {
        var lines = StageSelectCore.cleanStageText(text).split('\n');
        var estLines = 0;
        lines.forEach(function(line) {
            estLines += Math.max(1, Math.ceil(StageSelectCore.weighChars(line) / charsPerLine));
        });
        return Math.max(minH, Math.min(maxH, baseline + estLines * lineHeight));
    }

    // Adaptive card sizing: keep 167px (original look) when content fits;
    // bump to 195 / 220 only when title or description would overflow.
    // Card height comes from a real off-DOM render measurement so wrapping,
    // CJK glyph metrics and word-break behavior are pixel-accurate.
    function computeCardSizing(button, detail) {
        var nameWeight = StageSelectCore.weighChars(button.stageName || '');
        var textWeight = StageSelectCore.weighChars(StageSelectCore.cleanStageText(detail.rawText || '').replace(/\n/g, ' '));

        if (!VM.isRuntimeMode()) {
            // Dev mode: original geometry, fall back to estimation since the
            // dev card uses the legacy 167-wide layout.
            return {
                width: 167,
                nameLines: 1,
                cardHeight: estimateStageCardHeight(detail.rawText || '', 10.8, 20, 124, 232, 430)
            };
        }

        var width;
        var nameLines;
        if (nameWeight <= 9.4)         { width = 167; nameLines = 1; }
        else if (nameWeight <= 12.2)   { width = 195; nameLines = 1; }
        else if (nameWeight <= 14.0)   { width = 220; nameLines = 1; }
        else                           { width = 220; nameLines = 2; }

        // Description-driven bump: wider card → fewer wrap lines.
        if (textWeight > 130 && width < 220) width = 220;
        else if (textWeight > 90 && width < 195) width = 195;

        // Inner widths must match CSS: detail width = card width - 17px
        var innerWidth = width - 17;
        // Line height matches CSS rules (runtime detail = 19px; non-runtime = 20px)
        var lineHeight = 19;
        var baseline = (nameLines === 2) ? 167 : 124;
        var minH = (nameLines === 2) ? 240 : 232;
        // Generous cap: ~17 lines of 19px detail in 220-wide card.
        var maxH = 480;

        var detailH = measureDetailHeight(detail.html, innerWidth, lineHeight);
        var cardHeight;
        if (detailH >= 0) {
            cardHeight = Math.max(minH, Math.min(maxH, baseline + detailH));
        } else {
            // Headless / SSR fallback path
            var charsPerLine = (width === 220) ? 14.6 : (width === 195) ? 12.6 : 10.8;
            cardHeight = estimateStageCardHeight(detail.rawText || '', charsPerLine, lineHeight, baseline, minH, maxH);
        }
        return { width: width, nameLines: nameLines, cardHeight: cardHeight };
    }

    function computeDirectSizing(button) {
        var nameWeight = StageSelectCore.weighChars(button && button.stageName || '');
        var width = Math.max(92, Math.min(168, Math.ceil(nameWeight * 13) + 28));
        var height = nameWeight > 9.8 ? 34 : 26;
        if (button && button.entryKind === 'task') {
            width = 91;
            height = 21;
        }
        return { width: width, height: height };
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 选中态 / roving tabindex / hover 卡可见性的 DOM 反映（决策在 ViewModel /
    // 编排归 inspector，本模块只提供 DOM 原语）
    // ════════════════════════════════════════════════════════════════════════════
    function findNodeById(stageId) {
        if (!stageId || !S._buttonLayerEl) return null;
        return S._buttonLayerEl.querySelector('.stage-select-stage-button[data-stage-id="' + StageSelectCore.selectorQuote(stageId) + '"]');
    }

    // 打磨批二轮：键盘模态位转指针时统一剥环（pointerdown capture 调用；
    // 覆盖「点击已持焦节点、focusin 不再重燃、旧环残留」的路径）。
    function clearKbFocusClasses() {
        if (!S._buttonLayerEl) return;
        var nodes = S._buttonLayerEl.querySelectorAll('.stage-select-stage-button.is-kb-focus');
        for (var i = 0; i < nodes.length; i += 1) {
            nodes[i].classList.remove('is-kb-focus');
        }
    }

    function applySelectionClasses() {
        if (!S._buttonLayerEl) return;
        var nodes = S._buttonLayerEl.querySelectorAll('.stage-select-stage-button');
        for (var i = 0; i < nodes.length; i += 1) {
            var selected = !!S._selectedStageId && nodes[i].getAttribute('data-stage-id') === S._selectedStageId;
            nodes[i].classList.toggle('is-selected', selected);
            if (!nodes[i].classList.contains('is-direct-entry')) {
                nodes[i].setAttribute('aria-expanded', selected ? 'true' : 'false');
            }
        }
        // 打磨批二轮：.is-selected 镜像到卡锚点——CSS 硬保险（锚点.is-selected 的卡 display:none）
        // 以 DOM 状态类保证「选中节点永不出 hover 卡」，JS 开卡裁决（computeOpenCardId 过滤）仍先行。
        if (S._cardLayerEl) {
            var anchors = S._cardLayerEl.querySelectorAll('.stage-select-card-anchor');
            for (var j = 0; j < anchors.length; j += 1) {
                anchors[j].classList.toggle('is-selected',
                    !!S._selectedStageId && anchors[j].getAttribute('data-stage-id') === S._selectedStageId);
            }
        }
    }

    // roving tabindex：选中节点优先，否则保持当前停靠点，再退化为首个关卡节点。
    function applyRovingTabIndex() {
        if (!S._buttonLayerEl) return;
        var nodes = S._buttonLayerEl.querySelectorAll('.stage-select-stage-button');
        if (!nodes.length) return;
        var wanted = S._tabbableStageId;
        if (S._selectedStageId && findNodeById(S._selectedStageId)) wanted = S._selectedStageId;
        var found = false;
        var i;
        for (i = 0; i < nodes.length; i += 1) {
            if (nodes[i].getAttribute('data-stage-id') === wanted) { found = true; break; }
        }
        if (!found) wanted = nodes[0].getAttribute('data-stage-id');
        S._tabbableStageId = wanted;
        for (i = 0; i < nodes.length; i += 1) {
            nodes[i].tabIndex = nodes[i].getAttribute('data-stage-id') === wanted ? 0 : -1;
        }
    }

    // hover 卡可见性唯一 DOM 出口：开阖裁决（computeOpenCardId）在 ViewModel。
    // 打磨批二轮：同步向节点镜像 has-open-card——卡开期间该节点的键盘焦点环让位
    // （卡本体即焦点/悬停指示器；环压卡下缘是打磨批二轮治理的实机冲突形态之一）。
    function updateCardVisibility() {
        if (!S._cardLayerEl) return;
        var openId = VM.computeOpenCardId();
        var anchors = S._cardLayerEl.querySelectorAll('.stage-select-card-anchor');
        for (var i = 0; i < anchors.length; i += 1) {
            var open = anchors[i].getAttribute('data-stage-id') === openId;
            anchors[i].classList.toggle('is-card-open', open);
            var node = findNodeById(anchors[i].getAttribute('data-stage-id'));
            if (node) node.classList.toggle('has-open-card', open);
        }
    }

    // leave 事件的延迟合并入口：等同一指针移动的 leave/enter 边界事件序列全部落地后再裁决。
    function scheduleCardVisibilityUpdate() {
        StageSelectCore.scheduleTimer(updateCardVisibility, 0);
    }

    // 方向键焦点移交（DOM 半）：最近邻打分（computeNavTarget）在 ViewModel，
    // 直达入口像素尺寸经 computeDirectSizing 注入（ViewModel 不烘焙 2D 布局假设）。
    function moveNodeFocus(button, key) {
        var best = VM.computeNavTarget(button, key, computeDirectSizing);
        if (!best) return;
        var node = findNodeById(best.id);
        if (!node) return;
        S._tabbableStageId = best.id;
        applyRovingTabIndex();
        node.focus();
    }

    // 重建前快照焦点：关卡节点按 stage id 记，检查器内控件按角色记（推荐难度按钮重建后未必同位）。
    function captureFocusSnapshot() {
        var active = document.activeElement;
        if (!active || !S._el || !StageSelectCore.isWithin(active, S._el)) return null;
        if (StageSelectCore.isWithin(active, S._buttonLayerEl)) {
            var node = active.closest ? active.closest('.stage-select-stage-button') : null;
            if (node) return { stageId: node.getAttribute('data-stage-id') || '' };
            return null;
        }
        if (S._inspectorEl && StageSelectCore.isWithin(active, S._inspectorEl)) {
            if (active.classList && active.classList.contains('stage-select-difficulty')) {
                return { inspectorDifficulty: active.getAttribute('data-difficulty') || '' };
            }
            return { inspectorControl: true };
        }
        return null;
    }

    function restoreFocusSnapshot(snapshot) {
        if (!snapshot) return;
        if (snapshot.stageId) {
            var node = findNodeById(snapshot.stageId);
            if (node) {
                S._tabbableStageId = snapshot.stageId;
                applyRovingTabIndex();
                node.focus();
            }
            return;
        }
        if (snapshot.inspectorDifficulty && StageSelectInspector.isInspectorOpen()) {
            var difficulty = S._inspectorDiffEl.querySelector('.stage-select-difficulty[data-difficulty="' + StageSelectCore.selectorQuote(snapshot.inspectorDifficulty) + '"]');
            if (difficulty) { difficulty.focus(); return; }
        }
        if (snapshot.inspectorControl && StageSelectInspector.isInspectorOpen()) {
            S._inspectorCloseEl.focus();
        }
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 布局缩放（PanelScale 共享 primitive 接线）
    // ════════════════════════════════════════════════════════════════════════════
    // 布局缩放统一走共享 PanelScale（2026-08-16 P1-A，替换自写 syncStageLayout + ResizeObserver）。
    // stage 壳保留居中 translate(-50%,-50%) anchor——与 .panel-scale-shell 的 top/left:0 +
    // origin top left 约定冲突，故同 intelligence 先例只消费 JS 层 attach/detach，不挂壳类，
    // 由 onUpdate 回写 transform / 宽高 / --stage-select-scale。钳制语义保持旧实现不变：
    // min 0.45；dev max 1.35 防静态复刻过放大；runtime 不上限，等比放大铺满全 anchor 16:9
    // （沉浸全屏化 2026-06-11，shell 已是全 16:9，两路 Math.min 相等，零 letterbox）。
    function attachScaleWatcher() {
        if (S._scaleHandle) { S._scaleHandle.detach(); S._scaleHandle = null; }
        if (typeof PanelScale === 'undefined' || !PanelScale || typeof PanelScale.attach !== 'function') return;
        S._scaleHandle = PanelScale.attach(S._stageEl, S.DESIGN_W, S.DESIGN_H, {
            minScale: 0.45,
            maxScale: VM.isRuntimeMode() ? Infinity : 1.35,
            onUpdate: applyStageScale
        });
    }

    function applyStageScale(scale) {
        if (!S._stageEl) return;
        S._stageEl.style.width = S.DESIGN_W + 'px';
        S._stageEl.style.height = S.DESIGN_H + 'px';
        S._stageEl.style.transform = 'translate(-50%, -50%) scale(' + scale + ')';
        S._stageEl.style.setProperty('--stage-select-scale', scale);
    }

    function syncStageLayout() {
        if (S._scaleHandle) S._scaleHandle.update();
    }

    // 导出：被 inspector / bridge / facade 引用的名字
    window.StageSelectRenderer = {
        createDOM: createDOM,
        onOpen: onOpen,
        onRebind: onRebind,
        requestClose: requestClose,
        onClose: onClose,
        applyFixture: applyFixture,
        applyRuntimeSnapshot: applyRuntimeSnapshot,
        setFrame: setFrame,
        setFrameMenuOpen: setFrameMenuOpen,
        renderCurrentFrame: renderCurrentFrame,
        renderDifficulties: renderDifficulties,
        computeDirectSizing: computeDirectSizing,
        findNodeById: findNodeById,
        applySelectionClasses: applySelectionClasses,
        applyRovingTabIndex: applyRovingTabIndex,
        updateCardVisibility: updateCardVisibility,
        scheduleCardVisibilityUpdate: scheduleCardVisibilityUpdate,
        syncStageLayout: syncStageLayout
    };
})();
