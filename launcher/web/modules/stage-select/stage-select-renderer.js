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
    if (typeof window === 'undefined' || !window.StageSelectCardLayout) {
        throw new Error('stage-select/stage-select-renderer.js 需要先加载 stage-select/stage-select-card-layout.js（快捷卡几何）');
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
                    // 节点语义图例：放在顶栏工具行（不遮挡地图节点/导航），纯展示、不接收指针、不进 Tab 序；
                    // 形状与颜色同地图信标一一对应。
                    '<div class="stage-select-legend" id="stage-select-legend" role="note" aria-label="地点图例">' +
                        '<span class="stage-select-legend-item is-combat"><span class="stage-select-legend-glyph" aria-hidden="true"></span>战斗关卡</span>' +
                        '<span class="stage-select-legend-item is-route"><span class="stage-select-legend-glyph" aria-hidden="true"></span>友方据点</span>' +
                        '<span class="stage-select-legend-item is-region-jump"><span class="stage-select-legend-glyph" aria-hidden="true"></span>区域跳转</span>' +
                        '<span class="stage-select-legend-item is-task"><span class="stage-select-legend-glyph" aria-hidden="true"></span>任务</span>' +
                        '<span class="stage-select-legend-item is-locked"><span class="stage-select-legend-glyph" aria-hidden="true"></span>未解锁</span>' +
                    '</div>' +
                    '<button class="stage-select-mod-btn stage-select-mod-toggle" id="stage-select-mod-toggle" type="button" aria-expanded="false" aria-controls="stage-select-mod-pod" title="辅助功能与选关修改器" data-audio-cue="navigate">辅助 ▾</button>' +
                    '<div class="stage-select-mod-pod" id="stage-select-mod-pod" role="group" aria-label="选关修改器" hidden>' +
                        '<button class="stage-select-mod-btn" id="stage-select-mod-unlock" type="button" aria-pressed="false" title="选关修改器：临时解锁全部关卡（挑战模式自动禁用）" data-audio-cue="navigate">⚡ 全关卡解锁</button>' +
                        '<button class="stage-select-mod-btn is-test-space" id="stage-select-mod-test-space" type="button" title="选关修改器：进入测试空间（挑战模式自动禁用）" data-audio-cue="activate">⌖ 测试空间</button>' +
                    '</div>' +
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
                        // 二维战术底板（网格 + 暗角）：只在 runtime 二维区域显示，不接收指针。
                        '<div class="stage-select-board-fx" aria-hidden="true"></div>' +
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
                                // 详情标题保留独立窄幅标记，不与快捷卡操作区共用装饰。
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
        S._modToolbarEl = S._el.querySelector('#stage-select-mod-pod');
        S._modToggleEl = S._el.querySelector('#stage-select-mod-toggle');
        S._modUnlockBtnEl = S._el.querySelector('#stage-select-mod-unlock');
        S._modTestSpaceBtnEl = S._el.querySelector('#stage-select-mod-test-space');
        // 快捷路径情报侧栏挂在舞台设计坐标系内（随 PanelScale 等比缩放），位于卡片层之上。
        StageSelectQuick.createDOM(S._stageEl);

        if (S._modToggleEl) {
            S._modToggleEl.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                setModMenuOpen(!S._modMenuOpen);
            });
        }
        if (S._modUnlockBtnEl) {
            S._modUnlockBtnEl.addEventListener('click', function(e) {
                e.stopPropagation();
                if (VM.isChallengeMode()) return;
                var next = VM.setForceUnlock(!VM.isForceUnlockActive());
                renderCurrentFrame();
                StageSelectBridge.requestSnapshot({ setForceUnlock: next });
                StageSelectCore.logDev('modifier forceUnlock: ' + (next ? 'on' : 'off'));
            });
        }
        if (S._modTestSpaceBtnEl) {
            S._modTestSpaceBtnEl.addEventListener('click', function(e) {
                e.stopPropagation();
                if (VM.isChallengeMode()) return;
                StageSelectCore.cue('activate');
                StageSelectBridge.requestReturnFrame('地图-测试空间', { id: 'mod-test-space' });
            });
        }

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
            if (S._modMenuOpen && !StageSelectCore.isWithin(e.target, S._modToolbarEl) && !StageSelectCore.isWithin(e.target, S._modToggleEl)) {
                setModMenuOpen(false);
            }
            if (!S._frameMenuOpen || !VM.isRuntimeMode()) return;
            if (StageSelectCore.isWithin(e.target, S._frameToggleEl) || StageSelectCore.isWithin(e.target, S._tabsEl)) return;
            setFrameMenuOpen(false);
        });
        S._el.addEventListener('keydown', function(e) {
            // P2 页内 Esc 分层消费（dev/harness 路径；正式 runtime 物理 Esc 由 C# 钩子截获，
            // 经 panel_esc → onRequestClose('escape') 走 requestClose 内的同序分层，两条路径互斥不重叠）。
            // defaultPrevented = 区域菜单 toggle/tabs 已消费本次 Esc，不再落穿到检查器层。
            if (e.key !== 'Escape' || e.defaultPrevented) return;
            if (StageSelectCameraEditor.isOpen()) { e.preventDefault(); StageSelectCameraEditor.hide(); return; }
            if (S._modMenuOpen) { e.preventDefault(); setModMenuOpen(false, { restoreFocus:true }); return; }
            if (S._frameMenuOpen && VM.isRuntimeMode()) {
                e.preventDefault();
                setFrameMenuOpen(false);
                if (S._frameToggleEl) S._frameToggleEl.focus();
                return;
            }
            if (StageSelectInspector.isInspectorOpen()) {
                e.preventDefault();
                StageSelectInspector.clearSelection({ restoreFocus: true });
                return;
            }
            if (StageSelectQuick.pinnedId()) { e.preventDefault(); StageSelectQuick.unpin(); }
        });
        S._fixtureSelectEl.addEventListener('change', function() {
            applyFixture(S._fixtureSelectEl.value);
            renderCurrentFrame();
        });
        // P2：难度点击委派上移到面板根，同时覆盖卡片层 hover 卡与 pinned 检查器里的难度按钮。
        S._el.addEventListener('click', StageSelectInspector.handleDifficultyClick);
        // P2：点舞台空白取消选中（节点 / 导航 / hover 卡 / 检查器内部点击除外）。
        S._shellEl.addEventListener('click', StageSelectInspector.handleStageBlankClick);
        S._shellEl.addEventListener('click', StageSelectQuick.handleBlankClick);
        S._stageEl.addEventListener('pointermove', handleCardPointerMove);
        S._stageEl.addEventListener('pointerleave', handleCardPointerLeave);
        S._inspectorCloseEl.addEventListener('click', function(e) {
            e.stopPropagation();
            StageSelectInspector.clearSelection({ restoreFocus: true });
        });
        // 检查器内 ←/→ 移焦、Enter/Space 选择、↑↓ 无操作；独立出战按钮负责提交。
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

        S._el.querySelector('.stage-select-tools').prepend(StageSelectCameraEditor.createToggle('游览地图'));
        renderTabs();
        return S._el;
    }

    // ════════════════════════════════════════════════════════════════════════════
    // 生命周期（对位 arena-shell：跨模块编排，领域规则仍在各模块内）
    // ════════════════════════════════════════════════════════════════════════════
    function onOpen(root, initData) {
        S._catalogId = StageSelectData.activateCatalog(initData && initData.catalogId);
        var manifest = StageSelectData.getManifest();
        S._session += 1;
        S._pendingReq = {};
        S._panelInstanceId = StageSelectBridge.readInitInstanceId(initData);
        S._lastAppliedStateRevision = 0;
        S._runtimeSnapshot = null;
        S._busyStageName = '';
        S._lastError = '';
        S._lastCloseSendError = '';
        S._mode = initData && initData.mode || 'dev';
        S.DESIGN_W = manifest.designSize && manifest.designSize.width || 1024;
        S.DESIGN_H = manifest.designSize && manifest.designSize.height || 576;
        S._fixtureName = initData && initData.fixture || 'mixed';
        var requestedFrameLabel = initData && (initData.frameLabel || initData.page) || '';
        S._currentFrameLabel = requestedFrameLabel && StageSelectData.hasFrame(requestedFrameLabel)
            ? requestedFrameLabel : manifest.frameOrder[0];
        var requestedReturnFrameLabel = initData && initData.returnFrameLabel || '';
        // Host 提供根场景身份；外交场景不必同时是一张选关页。
        S._returnFrameLabel = typeof requestedReturnFrameLabel === 'string' && requestedReturnFrameLabel
            ? requestedReturnFrameLabel : S._currentFrameLabel;
        applyFixture(S._fixtureName);
        if (S._fixtureSelectEl) S._fixtureSelectEl.value = S._fixtureName;
        if (S._el) S._el.classList.toggle('is-runtime', VM.isRuntimeMode());
        setFrameMenuOpen(false);
        setModMenuOpen(false);
        S._lastDifficultyClick = null;
        // P2：每次打开重置选中态与卡片/焦点跟踪（create 只跑一次，元素跨 open 复用）
        S._selectedStageId = '';
        S._tabbableStageId = '';
        S._hoverStageId = '';
        S._cardHoverStageId = '';
        S._cardPlacementById = {};
        S._cardBridge = null;
        S._focusStageId = '';
        StageSelectQuick.reset();
        S._forceUnlock = false;
        S._tourPinsVisible = false;
        if (S._el) S._el.classList.remove('is-tour-pins-visible');
        S._lastInputKeyboard = false; // 打磨批二轮：键盘模态位随面板打开复位（默认指针模态）
        StageSelectFocus.reset();
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
        var previousCatalogId = S._catalogId;
        S._catalogId = StageSelectData.activateCatalog(initData && initData.catalogId);
        var catalogChanged = previousCatalogId !== S._catalogId;
        var manifest = StageSelectData.getManifest();
        S._panelInstanceId = StageSelectBridge.readInitInstanceId(initData);
        StageSelectBridge.invalidatePendingRequests('rebind');
        S._lastAppliedStateRevision = 0;
        if (initData && initData.frameLabel && StageSelectData.hasFrame(initData.frameLabel)) {
            S._currentFrameLabel = initData.frameLabel;
        } else if (catalogChanged || !StageSelectData.hasFrame(S._currentFrameLabel)) {
            S._currentFrameLabel = manifest.frameOrder[0];
        }
        if (initData && typeof initData.returnFrameLabel === 'string' && initData.returnFrameLabel) {
            S._returnFrameLabel = initData.returnFrameLabel;
        } else if (catalogChanged || !S._returnFrameLabel) {
            S._returnFrameLabel = S._currentFrameLabel;
        }
        if (catalogChanged) {
            S.DESIGN_W = manifest.designSize && manifest.designSize.width || 1024;
            S.DESIGN_H = manifest.designSize && manifest.designSize.height || 576;
            S._runtimeSnapshot = null;
            S._selectedStageId = '';
            S._tabbableStageId = '';
            S._hoverStageId = '';
            S._cardHoverStageId = '';
            S._focusStageId = '';
            renderTabs();
            attachScaleWatcher();
            renderCurrentFrame();
        }
        StageSelectCore.logDev('session rebound: ' + (S._panelInstanceId || '(unbound)'));
        StageSelectBridge.requestSnapshot();
        return true;
    }

    // onRequestClose：遮罩点击 / C# panel_esc（物理 Escape）/ 关闭钮共用。
    // P2 Esc 分层消费：关区域菜单 > 关检查器（焦点归还触发节点）> 关面板。
    function requestClose(reason) {
        if (reason === 'escape') {
            if (StageSelectCameraEditor.isOpen()) { StageSelectCameraEditor.hide(); return; }
            if (S._modMenuOpen) { setModMenuOpen(false, { restoreFocus:true }); return; }
            if (S._frameMenuOpen) {
                setFrameMenuOpen(false);
                if (S._frameToggleEl) S._frameToggleEl.focus();
                return;
            }
            if (StageSelectInspector.isInspectorOpen()) {
                StageSelectInspector.clearSelection({ restoreFocus: true });
                return;
            }
            if (StageSelectQuick.unpin()) return;
        }
        // Web 主动关闭以 Host transport 的同步接收结果为提交点。false/throw 时不能先卸载
        // 当前 owner/DOM，也不能消费在途请求或 busy；保留原状态供用户直接重试。
        if (!StageSelectBridge.sendCloseNotification()) {
            S._lastCloseSendError = 'send_failed';
            StageSelectCore.showError('send_failed');
            return false;
        }
        S._lastCloseSendError = '';
        StageSelectBridge.invalidatePendingRequests('requestClose');
        Panels.close();
        return true;
    }

    // 幂等：任何关闭路径（requestClose→Panels.close / C# close / 切面板）都经此统一销毁
    function onClose() {
        StageSelectDiorama.hide();
        setFrameMenuOpen(false);
        setModMenuOpen(false);
        // scoped 测试目录只在 stage-select 活跃期间生效。只有 Panels 已接受关闭并进入
        // onClose 后才恢复 production；transport false/throw 时 requestClose 会提前返回，
        // 因而不会让仍可见的测试页突然切换数据源。
        S._catalogId = StageSelectData.activateCatalog(StageSelectData.DEFAULT_CATALOG_ID);
        // P2：检查器销毁幂等——清选中态并隐藏，元素保留待下次 open 复用
        StageSelectInspector.clearSelection();
        StageSelectFocus.reset();
        StageSelectQuick.reset();
        S._hoverStageId = '';
        S._cardHoverStageId = '';
        S._cardPlacementById = {};
        S._cardBridge = null;
        S._focusStageId = '';
        S._tabbableStageId = '';
        // P3：C# 侧发起/切面板导致的关闭也在这里清 pending（requestClose 只覆盖 web 主动路径），
        // 在途回包随 session 自增一并失效。
        StageSelectBridge.invalidatePendingRequests('onClose');
        S._busyStageName = '';
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
        StageSelectQuick.reset();
        StageSelectCameraEditor.hide();
        setModMenuOpen(false);
        StageSelectCore.logDev((source || 'route') + ': ' + label);
        renderCurrentFrame();
    }

    function modAvailable() {
        return !VM.isChallengeMode() && !StageSelectData.getManifest().testOnly;
    }

    function syncModVisibility() {
        var available = modAvailable();
        if (!available) S._modMenuOpen = false;
        if (S._modToggleEl) {
            S._modToggleEl.hidden = !available;
            S._modToggleEl.setAttribute('aria-expanded', S._modMenuOpen ? 'true' : 'false');
            S._modToggleEl.classList.toggle('has-mod-active', VM.isForceUnlockActive());
        }
        if (S._modToolbarEl) S._modToolbarEl.hidden = !available || !S._modMenuOpen;
        if (S._el) S._el.classList.toggle('is-mod-menu-open', available && S._modMenuOpen);
    }

    function setModMenuOpen(open, opts) {
        opts = opts || {};
        var next = !!open && modAvailable();
        if (next && S._frameMenuOpen) setFrameMenuOpen(false);
        S._modMenuOpen = next;
        syncModVisibility();
        if (next && S._modUnlockBtnEl) S._modUnlockBtnEl.focus({ preventScroll:true });
        else if (!next && opts.restoreFocus && S._modToggleEl) S._modToggleEl.focus();
    }

    function setFrameMenuOpen(open) {
        if (open && S._modMenuOpen) setModMenuOpen(false);
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
        StageSelectDiorama.bind(frame);
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
        var manifest = StageSelectData.getManifest();
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
        var title = S._el.querySelector('.stage-select-title');
        if (title) title.textContent = manifest.title || '选关';
        if (S._el) {
            S._el.setAttribute('data-catalog-id', S._catalogId || StageSelectData.DEFAULT_CATALOG_ID);
            S._el.setAttribute('data-test-catalog', manifest.testOnly ? 'true' : 'false');
            S._el.setAttribute('data-accent', VM.getFrameAccent(frame.frameLabel));
        }
        if (S._modUnlockBtnEl) {
            var forceActive = VM.isForceUnlockActive();
            S._modUnlockBtnEl.setAttribute('aria-pressed', forceActive ? 'true' : 'false');
            S._modUnlockBtnEl.classList.toggle('is-active', forceActive);
        }
        syncModVisibility();
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
            S._frameToggleEl.setAttribute('title', manifest.testOnly ? manifest.title : '切换区域');
            S._frameToggleEl.setAttribute('aria-label', manifest.testOnly
                ? manifest.title + '，切换区域' : '切换区域');
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
        S._cardBridge = null;
        S._buttonLayerEl.innerHTML = '';
        if (S._cardLayerEl) S._cardLayerEl.innerHTML = '';
        (frame.decorations || []).forEach(function(item) {
            S._buttonLayerEl.appendChild(createDecoration(item));
        });
        StageSelectDiorama.orderButtons(frame).forEach(function(button) {
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
        var isMapEntry = button.entryKind === 'map';
        var directSizing = (direct || isMapEntry) ? computeDirectSizing(button) : null;
        var mapLayout = isMapEntry && button.directLayout ? buildMapDirectLayout(button.directLayout) : null;
        var displayName = VM.getStageDisplayName(button);
        var node = document.createElement('div');
        node.className = 'stage-select-stage-button';
        if (direct || isMapEntry) {
            if (direct) node.classList.add('is-direct-entry');
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
            // 锁定节点仍可聚焦：aria-disabled + 通用占位名称让焦点可读锁定态，原因文案由检查器展示。
            node.setAttribute('aria-disabled', 'true');
            node.setAttribute('aria-label', state.pending ? '等待同步解锁状态' : displayName);
        } else if (state.forceUnlocked) {
            node.classList.add('is-force-unlocked');
        }
        if (state.task) node.classList.add('is-task');
        if (S._busyStageName && S._busyStageName === button.stageName) node.classList.add('is-busy');
        node.innerHTML =
            '<span class="stage-select-hit-zone" aria-hidden="true"></span>' +
            renderStageMarkerSvg(isMapEntry) +
            '<span class="stage-select-stage-name">' + renderStageNameHtml(displayName, isMapEntry) + '</span>' +
            renderStageLockSvg() +
            '<span class="stage-select-task-pulse"></span>' +
            // 靶标括号：悬停/锁定时吸附到信标（地图同款四角框），纯装饰不接收指针。
            '<span class="stage-select-reticle" aria-hidden="true"></span>' +
            // 打磨批：选中光环独立元素（task-pulse 同族柔和外发光），替代旧 hit-zone 硬 box-shadow 圆环
            '<span class="stage-select-selected-ring" aria-hidden="true"></span>';
        node.addEventListener('click', function(e) {
            if (direct) {
                // 直达入口（副本任务）：保持一步跳转，不经过检查器。
                StageSelectInspector.requestStageActivation(button, '', null);
                return;
            }
            // 指针单击（detail≥1）已解锁节点 = 锁定快捷卡（卡片常驻、三维支点推近），不打开深度详情；
            // 双击的第二击（detail≥2）留给 dblclick。键盘 / 辅助技术 / 程序化激活（detail=0）
            // 与锁定节点保持原语义：选中并打开深度详情（检查器）；再点同节点取消选中。
            if (e.detail >= 2) return;
            if (e.detail === 1 && StageSelectQuick.pointerActivate(button.id)) return;
            StageSelectInspector.toggleStageSelection(button.id);
            StageSelectCore.logDev('select stage: ' + button.stageName + (state.unlocked ? '' : ' (locked fixture)'));
        });
        node.addEventListener('dblclick', function() {
            // 双击 = 深度详情（鼠标直达既有双栏聚焦）；第一击已锁定，openDetail 先即时解除锁定与推近。
            if (direct || !state.unlocked) return;
            StageSelectQuick.openDetail(button.id);
        });
        node.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                if (direct) {
                    StageSelectInspector.requestStageActivation(button, '', null);
                    return;
                }
                // 键盘路径：Enter/Space 选中并打开检查器，焦点移交检查器内主操作（锁定节点移交关闭钮）。
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
            StageSelectDiorama.hover(button.id);
            updateCardVisibility();
        });
        node.addEventListener('pointerleave', function() {
            StageSelectDiorama.hover('');
            if (S._hoverStageId === button.id) S._hoverStageId = '';
            scheduleCardVisibilityUpdate();
        });
        node.addEventListener('focusin', function() {
            S._focusStageId = button.id;
            S._tabbableStageId = button.id;
            applyRovingTabIndex();
            // 打磨批二轮：焦点环只随键盘模态挂 .is-kb-focus（指针路径持焦不出蓝环）
            node.classList.toggle('is-kb-focus', !!S._lastInputKeyboard);
            if(S._lastInputKeyboard)StageSelectDiorama.hover(button.id);
            updateCardVisibility();
        });
        node.addEventListener('focusout', function() {
            if (S._focusStageId === button.id) S._focusStageId = '';
            if(!S._hoverStageId)StageSelectDiorama.hover('');
            node.classList.remove('is-kb-focus');
            updateCardVisibility();
        });
        var cardAnchor = direct || !state.unlocked ? null : createCardAnchor(button, state, detail, sizing, displayName);
        StageSelectDiorama.place(button, node, cardAnchor, sizing.cardHeight);
        return { node: node, anchor: cardAnchor };
    }

    function createCardAnchor(button, state, detail, sizing, displayName) {
        var previewAsset = VM.getPreviewAsset(button);
        var resolvedPreviewUrl = StageSelectCore.resolveAssetUrl(previewAsset.url || button.previewUrl);
        var anchor = document.createElement('div');
        anchor.className = 'stage-select-card-anchor';
        if (button.entryKind === 'map') anchor.classList.add('is-map-entry');
        anchor.setAttribute('data-stage-name', button.stageName);
        anchor.setAttribute('data-stage-id', button.id);
        anchor.setAttribute('data-card-name-lines', String(sizing.nameLines));
        anchor.setAttribute('data-placement', 'above');
        anchor._stageCardSizing = sizing;
        anchor.style.left = button.x + 'px';
        anchor.style.top = button.y + 'px';
        anchor.style.setProperty('--stage-card-content-width', sizing.width + 'px');
        anchor.style.setProperty('--stage-card-width', sizing.width + 'px');
        anchor.style.setProperty('--stage-card-height', sizing.cardHeight + 'px');
        if (!state.unlocked) anchor.classList.add('is-locked');
        else if (state.forceUnlocked) anchor.classList.add('is-force-unlocked');
        if (state.task) anchor.classList.add('is-task');
        if (S._busyStageName && S._busyStageName === button.stageName) anchor.classList.add('is-busy');
        anchor.innerHTML =
            '<span class="stage-select-card">' +
                '<span class="stage-select-card-corner" aria-hidden="true"></span>' +
                '<span class="stage-select-card-content">' +
                    '<span class="stage-select-card-name">' + StageSelectCore.escapeHtml(displayName) + '</span>' +
                    '<span class="stage-select-preview-wrap" data-preview-tier="' + StageSelectCore.escapeAttr(previewAsset.tier) + '">' +
                        '<img class="stage-select-preview" src="' + StageSelectCore.escapeAttr(resolvedPreviewUrl) + '" alt="' + StageSelectCore.escapeAttr(displayName) + ' 预览" data-preview-source="' + StageSelectCore.escapeAttr(button.previewSource || '') + '">' +
                    '</span>' +
                    '<span class="stage-select-card-detail">' + detail.html + '</span>' +
                '</span>' +
                '<span class="stage-select-difficulties">' + renderDifficulties(button, state, false) + '</span>' +
            '</span>';
        var cardEl = anchor.querySelector('.stage-select-card');
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

    function cardPlacementKey(button) {
        return S._catalogId + '/' + S._currentFrameLabel + '/' + button.id;
    }

    function cardLabelRect(button, node, point) {
        var projected = S._visualStagePoints && S._visualStagePoints[button.id];
        if (projected) {
            var label = node.querySelector('.stage-select-stage-name');
            var width = label && label.offsetWidth || projected.labelWidth || 140;
            var height = label && label.offsetHeight || projected.labelHeight || 30;
            return {
                x: point.x + StageSelectCore.finiteNumber(projected.labelX, 0) - width / 2,
                y: point.y + StageSelectCore.finiteNumber(projected.labelY, 0) - height / 2,
                width: width,
                height: height
            };
        }
        if (button.entryKind === 'map') {
            var text = button.directLayout && button.directLayout.text || {};
            return {
                x: button.x + StageSelectCore.finiteNumber(text.x, -68.5),
                y: button.y + StageSelectCore.finiteNumber(text.y, 135.7),
                width: StageSelectCore.finiteNumber(text.width, 137),
                height: StageSelectCore.finiteNumber(text.height, 34.3)
            };
        }
        return { x: button.x - 70.5, y: button.y + 133.7, width: 137, height: 34.3 };
    }

    function fallbackCardSizes(anchor) {
        var sizing = anchor._stageCardSizing || { width: 167, cardHeight: 232 };
        return {
            above: { width: sizing.width, height: sizing.cardHeight },
            below: { width: sizing.width, height: sizing.cardHeight },
            left: { width: sizing.width, height: sizing.cardHeight },
            right: { width: sizing.width, height: sizing.cardHeight }
        };
    }

    function measureCardSizes(anchor, force) {
        if (!force && anchor._cardLayoutSizes) return anchor._cardLayoutSizes;
        var sizes = fallbackCardSizes(anchor), card = anchor.querySelector('.stage-select-card');
        if (anchor.isConnected && card) {
            anchor.classList.add('is-measuring');
            if (card.offsetWidth > 0 && card.offsetHeight > 0) {
                sizes.above = sizes.below = sizes.left = sizes.right = { width: card.offsetWidth, height: card.offsetHeight };
            }
            anchor.classList.remove('is-measuring');
        }
        anchor._cardLayoutSizes = sizes;
        return sizes;
    }

    // 二维：Flash 原版卡恒在上方（地名在信标下）。三维：地名牌是主要瞄准目标且可能经引线远离信标，
    // 卡片先贴地名所在一侧（地名在信标上方 → 上方），避免把卡放到信标另一侧、让地名到难度行行程翻倍。
    function preferredCardSide(button) {
        var projected = S._visualStagePoints && S._visualStagePoints[button.id];
        if (!projected) return 'above';
        return StageSelectCore.finiteNumber(projected.labelY, -1) > 0 ? 'below' : 'above';
    }

    function placeCardAnchor(button, node, anchor, forceMeasure) {
        if (!anchor) return;
        var point = VM.getStageNavPoint(button, computeDirectSizing);
        var obstacles = [{ x: point.x - 22, y: point.y - 22, width: 44, height: 44 }, cardLabelRect(button, node, point)];
        // 水平中心对齐地名：二维地名本就居中于信标；三维地名牌是主要瞄准目标，可能经引线远离信标。
        var labelCenterX = obstacles[1].x + obstacles[1].width / 2;
        var key = cardPlacementKey(button);
        var sizes = measureCardSizes(anchor, !!forceMeasure);
        var layoutWith = function(list, cx) {
            return StageSelectCardLayout.place({
                point: point,
                centerX: typeof cx === 'number' ? cx : labelCenterX,
                obstacles: list,
                sizes: sizes,
                preferredSide: preferredCardSide(button), // 由几何决定、不随历史漂移（见 card-layout 停靠合同）
                bounds: { width: S.DESIGN_W, height: S.DESIGN_H, top: 54, inset: 8 },
                nodeRadius: 22,
                bridgeWidth: 28
            });
        };
        var placed = layoutWith(obstacles);
        // 三维地名经长引线远离信标且贴近舞台边缘时，「避让信标 + 地名」只能把卡放到信标另一侧，
        // 地名到难度行的行程翻倍。此时改为只避让地名：卡片贴地名停靠（允许压住本节点信标——
        // 光标在地名牌上，信标不是瞄准目标），保持 Flash 级短行程。
        if (S._visualStagePoints && S._visualStagePoints[button.id]) {
            var lab = obstacles[1];
            var gapToLabel = placed.top >= lab.y + lab.height ? placed.top - (lab.y + lab.height) : lab.y - (placed.top + placed.height);
            // 阈值取两倍常规地名-信标间距（约 45px）：只处理「卡片落在长引线另一端」的情形，
            // 普通三维节点卡片落在信标下方时与地名相隔约 50–60px，保持常规停靠。
            if (gapToLabel > 96) {
                var labelOnly = layoutWith([lab]);
                if (labelOnly.valid) {
                    // 贴地名停靠若压住本节点信标，优先水平让开信标（仍贴地名），让开后仍能悬停/点中信标；
                    // 两侧都放不下时才接受压住信标。
                    var mk = obstacles[0];
                    var covers = function(p) {
                        return StageSelectCardLayout.intersects({ x: p.left, y: p.top, width: p.width, height: p.height }, mk);
                    };
                    if (covers(labelOnly)) {
                        var w = labelOnly.width;
                        [mk.x - 8 - w / 2, mk.x + mk.width + 8 + w / 2]
                            .sort(function(a, b) { return Math.abs(a - labelCenterX) - Math.abs(b - labelCenterX); })
                            .some(function(cx) {
                                var shifted = layoutWith([lab], cx);
                                if (!shifted.valid || covers(shifted)) return false;
                                labelOnly = shifted;
                                return true;
                            });
                    }
                    placed = labelOnly;
                }
            }
        }
        S._cardPlacementById[key] = placed.side; // 仅诊断回读，不再回灌 preferredSide
        anchor.setAttribute('data-placement', placed.side);
        anchor.setAttribute('data-action-position', placed.connection.actionPosition);
        anchor.classList.toggle('is-tight-layout', !placed.valid);
        anchor.style.left = placed.left + 'px';
        anchor.style.top = placed.top + 'px';
        anchor.style.setProperty('--stage-card-width', placed.width + 'px');
        anchor.style.setProperty('--stage-card-height', placed.height + 'px');
        anchor._cardConnection = placed.connection;
    }

    function handleCardPointerMove(event) {
        var bridge = S._cardBridge;
        if (!bridge || !S._stageEl) return;
        var rect = S._stageEl.getBoundingClientRect();
        if (!rect.width || !rect.height) return;
        var point = {
            x: (event.clientX - rect.left) * S.DESIGN_W / rect.width,
            y: (event.clientY - rect.top) * S.DESIGN_H / rect.height
        };
        var id = bridge.stageId;
        var anchor = S._cardLayerEl.querySelector('.stage-select-card-anchor[data-stage-id="' + StageSelectCore.selectorQuote(id) + '"]');
        var node = findNodeById(id);
        var onCard = anchor && StageSelectCore.isWithin(event.target, anchor);
        var onNode = node && StageSelectCore.isWithin(event.target, node);
        var inside = StageSelectCardLayout.contains(bridge, point);
        if (inside && (!S._hoverStageId || S._hoverStageId === id)) {
            if (S._cardHoverStageId !== id) {
                S._cardHoverStageId = id;
                updateCardVisibility();
            }
            return;
        }
        if (!inside && !onCard && !onNode && S._cardHoverStageId === id) {
            S._cardHoverStageId = '';
            scheduleCardVisibilityUpdate();
        }
    }

    function handleCardPointerLeave() {
        S._hoverStageId = '';
        S._cardHoverStageId = '';
        StageSelectDiorama.hover('');
        scheduleCardVisibilityUpdate();
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

    // 节点语义的形状编码（2026-10-16 玩家反馈：副本与友方据点一眼难分）：
    // 战斗/任务关卡 = 菱形信标；外交据点（entryKind=map）= 圆形信标 + 前进三角内芯。
    // 形状独立于颜色承载语义，红绿色弱下仍可区分；三段 path 的 class 不变，沿用既有填色规则。
    function renderStageMarkerSvg(isMapEntry) {
        if (isMapEntry) {
            return '<span class="stage-select-marker is-route" aria-hidden="true">' +
                '<svg class="stage-select-marker-svg" viewBox="-293 -293 586 586" focusable="false">' +
                    '<path class="stage-select-marker-disc" d="M0 -264 A264 264 0 1 1 0 264 A264 264 0 1 1 0 -264 Z"/>' +
                    '<path class="stage-select-marker-fill" fill-rule="evenodd" d="' +
                        'M0 -220 A220 220 0 1 1 0 220 A220 220 0 1 1 0 -220 Z ' +
                        'M0 -162 A162 162 0 1 0 0 162 A162 162 0 1 0 0 -162 Z' +
                    '"/>' +
                    '<path class="stage-select-marker-core" d="M-52 -92 L100 0 L-52 92 Z"/>' +
                '</svg>' +
            '</span>';
        }
        return '<span class="stage-select-marker" aria-hidden="true">' +
            '<svg class="stage-select-marker-svg" viewBox="-293 -293 586 586" focusable="false">' +
                '<path class="stage-select-marker-disc" d="M0 -264 L264 0 L0 264 L-264 0 Z"/>' +
                '<path class="stage-select-marker-fill" fill-rule="evenodd" d="' +
                    'M0 -220 L220 0 L0 220 L-220 0 Z ' +
                    'M0 -162 L-162 0 L0 162 L162 0 Z' +
                '"/>' +
                '<path class="stage-select-marker-core" d="M0 -84 L84 0 L0 84 L-84 0 Z"/>' +
            '</svg>' +
        '</span>';
    }

    // 外交据点名称以「前往」开头时，把动词降级为小号前缀，让地名成为视觉重心；
    // textContent 仍是完整原文（无障碍名称与既有文本断言不变）。
    function renderStageNameHtml(displayName, isMapEntry) {
        var text = String(displayName || '');
        var verb = '前往';
        if (isMapEntry && text.indexOf(verb) === 0 && text.length > verb.length) {
            return '<span class="stage-select-stage-name-verb">' + verb + '</span>' +
                StageSelectCore.escapeHtml(text.substr(verb.length));
        }
        return StageSelectCore.escapeHtml(text);
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
        if (!state.unlocked) return '';
        // hover 卡内按钮是鼠标快捷路径（tabIndex=-1 不进 Tab 序）；检查器内按钮承接键盘路径。
        var tabAttr = tabbable === false ? ' tabindex="-1"' : '';
        if (button && button.entryKind === 'map') {
            return '<button type="button" class="stage-select-map-action" data-stage-name="' + StageSelectCore.escapeAttr(button.stageName) + '" data-entry-kind="map" data-difficulty=""' + tabAttr + '>前往地点</button>';
        }
        var difficulties = VM.isChallengeMode() ? ['地狱'] : ['简单', '冒险', '修罗', '地狱'];
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
            if (visualKind === 'return-garage' && S._returnFrameLabel !== '地图-联合大学') return;
            var node = document.createElement('button');
            node.type = 'button';
            node.className = 'stage-select-nav-button is-' + visualKind;
            node.style.left = nav.x + 'px';
            node.style.top = nav.y + 'px';
            node.setAttribute('data-nav-id', nav.id);
            node.setAttribute('data-action-kind', nav.actionKind || '');
            node.setAttribute('data-library-item', nav.libraryItemName || '');
            if (visualKind === 'region-jump') {
                node.setAttribute('aria-label', getNavDisplayLabel(nav, visualKind));
                node.innerHTML = '<span class="stage-select-nav-caption"><span class="stage-select-nav-eyebrow">查看区域</span>'
                    + '<span class="stage-select-nav-target">' + StageSelectCore.escapeHtml(nav.targetFrameLabel || '') + '</span></span>';
            } else {
                node.textContent = getNavDisplayLabel(nav, visualKind);
            }
            StageSelectDiorama.placeNav(nav,node);
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
        if (nav && nav.actionKind === 'localFrame') return 'region-jump';
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
        if (visualKind === 'region-jump') return '查看区域：' + target;
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

    // Adaptive width and fallback height estimation. The open card is measured again in
    // placeCardAnchor for its actual vertical/side placement, so these values only seed first layout.
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
        // 快捷卡高度封顶（2026-10-29 Flash 手感回归）：卡内简介最多 2 行（双行标题时 1 行），
        // 完整简介移交情报侧栏。卡片足够矮，任意节点都能在上方或下方放下，不再需要侧向停靠。
        // baseline = 内边距 12 + 标题 18/36 + 预览 73 + 简介外距 4 + 难度行 34。
        var detailCap = (nameLines === 2 ? 1 : 2) * lineHeight;
        var baseline = (nameLines === 2) ? 159 : 141;
        var minH = baseline + lineHeight;
        var maxH = baseline + detailCap;

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
        var openAnchor = null;
        var anchors = S._cardLayerEl.querySelectorAll('.stage-select-card-anchor');
        for (var i = 0; i < anchors.length; i += 1) {
            var id = anchors[i].getAttribute('data-stage-id');
            var open = id === openId;
            var node = findNodeById(id);
            if (open) {
                var button = VM.findStageButtonById(id);
                if (button && node) placeCardAnchor(button, node, anchors[i], true);
                openAnchor = anchors[i];
            }
            anchors[i].classList.toggle('is-card-open', open);
            if (node) node.classList.toggle('has-open-card', open);
        }
        S._cardBridge = openAnchor && openAnchor._cardConnection
            ? Object.assign({ stageId: openId }, openAnchor._cardConnection)
            : null;
        StageSelectQuick.onCardChange(openId, openAnchor);
    }

    // leave 事件的延迟合并入口：等同一指针移动的 leave/enter 边界事件序列全部落地后再裁决。
    function scheduleCardVisibilityUpdate() {
        // 连接区承担连续悬停；短延时只兜底边界事件竞争，不再代替节点到卡片的路径。
        StageSelectCore.scheduleTimer(updateCardVisibility, S._visualStagePoints ? 150 : 0);
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
            return { inspectorControl: active.id || true };
        }
        return null;
    }

    function restoreFocusSnapshot(snapshot) {
        if (!snapshot) return;
        if (snapshot.stageId) {
            if (StageSelectInspector.isInspectorOpen()) { StageSelectInspector.focusInspectorPrimary(); return; }
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
            var control = typeof snapshot.inspectorControl === 'string' && document.getElementById(snapshot.inspectorControl);
            if (control && control.getClientRects().length) control.focus();
            else StageSelectInspector.focusInspectorPrimary();
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
        placeCardAnchor: placeCardAnchor,
        syncStageLayout: syncStageLayout
    };
})();
