/**
 * stage-select/stage-select-view-model.js — 选关面板 P4-a 工程拆分 · 状态模型（ViewModel）。
 *
 * 纯数据层：frame 路由、按钮状态合并（fixture + runtime snapshot）、选中态、挑战模式、
 * 任务统计、几何导航打分、hover 卡开阖裁决。本文件不得出现任何 DOM API、不得引用
 * document/window 全局；节点身份只用稳定 `stageButton.id` / `stageName` 挂接；除 manifest
 * 坐标（x/y）外不烘焙 2D 布局假设——像素级测量（如直达入口尺寸）由调用方经 `directSizer`
 * 回调注入（空间 renderer 提供 DOM 实现，未来 P5 三维 renderer 可提供自己的实现）。
 * 这是 P5 三维 renderer 的插座：非 DOM renderer 可直接消费本模块输出的全部决策。
 *
 * 本文件由 modules/stage-select-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议
 * payload / QA 断言不变）。跨模块引用仅限 StageSelectCore.state（共享状态容器）与
 * StageSelectData（manifest/fixture SOT）——二者均非 DOM 模块；本模块不反向调用
 * renderer / inspector / bridge 的任何函数。
 * 依赖守卫：stage-select/stage-select-core.js。
 * 加载形态：顶层 var 全局（同 stage-select-data.js），保证 vm.runInContext / node eval
 * 沙箱可读，且不引入 window 标识符。
 */
var StageSelectViewModel = (function() {
    'use strict';

    if (typeof StageSelectCore === 'undefined') {
        throw new Error('stage-select/stage-select-view-model.js 需要先加载 stage-select/stage-select-core.js（共享基座：状态容器 + 跨模块工具）');
    }

    var S = StageSelectCore.state; // 共享状态（原顶层 var _x）

    // 限制词条 web 自算（迁自 AS2 _root.限制系统 关卡系统_lsy_限制系统.as:43-45 +
    // _root.获取难度等级 通信_鸡蛋_任务系统.as:488），取代旧 _root.任务栏UI函数.打印限制词条明细。
    // ⚠ 与 关卡系统_lsy_限制系统.as 的 addEntry 描述 + task-panel.js 的 LIMITATION_DESC 保持同步。
    var LIMITATION_DESC = {
        'DisableCompanion': '无法携带同伴',
        'DisableKnockdownProtection': '被击飞和击倒状态下无法免疫攻击',
        'DisableResurrection': '无法使用复活币'
    };
    function limitDiffName(level) {
        var n = Number(level);
        if (n === 1) return '简单';
        if (n === 1.5) return '冒险';
        if (n === 2) return '修罗';
        if (n === 2.5) return '地狱';
        return '';
    }
    // 复刻 打印限制词条明细：每条 "- [N难度]描述\n"（limitLevel 真值才加难度前缀）。
    function renderLimitDetail(limitations, limitLevel) {
        if (!limitations || !limitations.length) return '';
        var prefix = limitLevel ? ('[' + limitDiffName(limitLevel) + '难度]') : '';
        var s = '';
        for (var i = 0; i < limitations.length; i += 1) {
            s += '- ' + prefix + (LIMITATION_DESC[limitations[i]] || limitations[i]) + '\n';
        }
        return s;
    }

    function getStageState(stageName) {
        var stages = S._fixture && S._fixture.stages || {};
        var base = stages[stageName] || {};
        var state = {
            unlocked: typeof base.unlocked === 'undefined' ? true : !!base.unlocked,
            task: !!base.task,
            highestDifficulty: base.highestDifficulty || '简单',
            detail: base.detail || '',
            materialDetail: base.materialDetail || '',
            limitDetail: base.limitDetail || '',
            stageType: base.stageType || '',
            lockReason: typeof base.lockReason === 'string' ? base.lockReason : ''
        };
        var live = S._runtimeSnapshot && S._runtimeSnapshot.stageDetails && S._runtimeSnapshot.stageDetails[stageName] || null;
        if (live) {
            if (typeof live.task !== 'undefined') state.task = !!live.task;
            state.highestDifficulty = live.highestDifficulty || state.highestDifficulty;
            state.detail = typeof live.detail === 'string' ? live.detail : state.detail;
            state.materialDetail = typeof live.materialDetail === 'string' ? live.materialDetail : state.materialDetail;
            // limitDetail 改 web 自算（live.limitations 原始键名 + LIMITATION_DESC）；
            // 回退旧 live.limitDetail 字符串（兼容尚未重编的 AS2 快照）。
            if (live.limitations) state.limitDetail = renderLimitDetail(live.limitations, live.limitLevel);
            else if (typeof live.limitDetail === 'string') state.limitDetail = live.limitDetail;
            state.stageType = live.stageType || state.stageType;
            // 逐关锁定原因（AS2 buildLockReason 生成，仅锁定时非空）；缺省/非字符串按空串，
            // inspector 对空串回退通用文案。
            state.lockReason = typeof live.lockReason === 'string' ? live.lockReason : state.lockReason;
        }
        if (S._runtimeSnapshot && S._runtimeSnapshot.unlockedStages && Object.prototype.hasOwnProperty.call(S._runtimeSnapshot.unlockedStages, stageName)) {
            state.unlocked = !!S._runtimeSnapshot.unlockedStages[stageName];
        }
        return state;
    }

    function isChallengeMode() {
        if (S._runtimeSnapshot && typeof S._runtimeSnapshot.isChallengeMode !== 'undefined') return !!S._runtimeSnapshot.isChallengeMode;
        return !!(S._fixture && S._fixture.challenge);
    }

    function isRuntimeMode() {
        return S._mode === 'runtime';
    }

    function getTaskTargets() {
        var manifest = StageSelectData.getManifest();
        var byStage = {};
        var byFrame = {};
        var stages = [];
        var frames = [];
        var frameSeen = {};
        var total = 0;

        (manifest.frames || []).forEach(function(frame) {
            var frameCount = 0;
            var frameStageSeen = {};
            (frame.stageButtons || []).forEach(function(button) {
                var name = button.stageName || '';
                if (!name || frameStageSeen[name]) return;
                frameStageSeen[name] = true;
                if (!getStageState(name).task) return;
                frameCount += 1;
                if (!byStage[name]) {
                    byStage[name] = {
                        stageName: name,
                        frameLabel: frame.frameLabel,
                        highestDifficulty: getStageState(name).highestDifficulty || '简单'
                    };
                    stages.push(name);
                    total += 1;
                }
            });
            if (frameCount > 0) {
                byFrame[frame.frameLabel] = frameCount;
                if (!frameSeen[frame.frameLabel]) {
                    frameSeen[frame.frameLabel] = true;
                    frames.push(frame.frameLabel);
                }
            }
        });

        return {
            byStage: byStage,
            byFrame: byFrame,
            stages: stages,
            frames: frames,
            total: total
        };
    }

    function formatTaskCount(count) {
        return count > 99 ? '99+' : String(count);
    }

    function findStageButton(stageName, entryKind) {
        var frame = StageSelectData.getFrame(S._currentFrameLabel);
        var buttons = frame && frame.stageButtons || [];
        for (var i = 0; i < buttons.length; i += 1) {
            if (buttons[i].stageName === stageName && (buttons[i].entryKind || 'difficulty') === entryKind) return buttons[i];
        }
        return null;
    }

    function findStageButtonById(stageId) {
        if (!stageId) return null;
        var frame = StageSelectData.getFrame(S._currentFrameLabel);
        var buttons = frame && frame.stageButtons || [];
        for (var i = 0; i < buttons.length; i += 1) {
            if (buttons[i].id === stageId) return buttons[i];
        }
        return null;
    }

    function isDirectEntry(button) {
        return button && button.entryKind && button.entryKind !== 'difficulty';
    }

    function getStageDisplayName(button) {
        var directText = button && button.directLayout && button.directLayout.text && button.directLayout.text.label || '';
        if ((button && button.entryKind) === 'map' && directText) return directText;
        var name = button && button.stageName || '';
        if ((button && button.entryKind) === 'map' && name.indexOf('外交-') === 0) {
            return name.substr(3);
        }
        return name || '未命名';
    }

    // 方向键几何最近邻导航的视觉锚点（纯前端，坐标来自 manifest x/y）。
    // directSizer：直达入口（task）像素尺寸的注入回调（空间 renderer 提供）——
    // ViewModel 自身不烘焙坐标以外的 2D 布局假设。
    function getStageNavPoint(button, directSizer) {
        var x = Number(button.x) || 0;
        var y = Number(button.y) || 0;
        if (button.entryKind === 'map') {
            var marker = button.directLayout && button.directLayout.marker || {};
            return { x: x + StageSelectCore.finiteNumber(marker.x, 0), y: y + StageSelectCore.finiteNumber(marker.y, 120) };
        }
        if (button.entryKind === 'task') {
            var size = directSizer(button);
            return { x: x + size.width / 2, y: y + size.height / 2 };
        }
        // 普通关卡节点：视觉锚点 = 标记圆心 ≈ (x, y + 120)（translate(-70.5,133.7) + marker 局部 (70.5,-13.7)）。
        return { x: x, y: y + 120 };
    }

    // 方向键几何最近邻导航（纯决策半）：方向半平面主轴距离 + 2×垂直轴偏差打分。
    // 返回候选 stageButton 或 null；焦点移交 / roving tabindex 回写由 renderer 执行。
    function computeNavTarget(button, key, directSizer) {
        var frame = StageSelectData.getFrame(S._currentFrameLabel);
        var buttons = frame && frame.stageButtons || [];
        if (buttons.length < 2) return null;
        var origin = getStageNavPoint(button, directSizer);
        var best = null;
        var bestScore = Infinity;
        for (var i = 0; i < buttons.length; i += 1) {
            var candidate = buttons[i];
            if (candidate.id === button.id) continue;
            var point = getStageNavPoint(candidate, directSizer);
            var dx = point.x - origin.x;
            var dy = point.y - origin.y;
            var primary;
            var cross;
            if (key === 'ArrowRight') { primary = dx; cross = dy; }
            else if (key === 'ArrowLeft') { primary = -dx; cross = dy; }
            else if (key === 'ArrowDown') { primary = dy; cross = dx; }
            else { primary = -dy; cross = dx; }
            if (primary <= 1) continue;
            var score = primary + 2 * Math.abs(cross);
            if (score < bestScore) {
                bestScore = score;
                best = candidate;
            }
        }
        return best;
    }

    // hover 卡开阖裁决（纯决策）：指针在节点或卡上、或焦点在节点上时显示；
    // 选中节点（检查器承接）/ 锁定节点 / 直达入口不显示。返回 stageButton.id 或 ''。
    // 打磨批二轮：选中过滤之外另有 DOM 级保险——锚点镜像 .is-selected + CSS display:none
    // （renderer.applySelectionClasses / stage-select.css ⑨），事件乱序残留 is-card-open 也画不出卡。
    function computeOpenCardId() {
        var id = S._cardHoverStageId || S._hoverStageId || S._focusStageId || '';
        if (!id || id === S._selectedStageId) return '';
        var button = findStageButtonById(id);
        if (!button || isDirectEntry(button)) return '';
        if (!getStageState(button.stageName).unlocked) return '';
        return id;
    }

    // 选中态迁移（纯状态半）：仅普通关卡可选中；成功返回 true。
    // 选中金环 / roving tabindex / 检查器渲染等 DOM 反映由 inspector/renderer 编排。
    function applySelection(stageId) {
        var button = findStageButtonById(stageId);
        if (!button || isDirectEntry(button)) return false;
        S._selectedStageId = stageId;
        S._tabbableStageId = stageId;
        return true;
    }

    // 取消选中（纯状态半）：返回迁移前的选中 id（供焦点归还），无选中时返回 ''。
    function clearSelectionState() {
        var prevId = S._selectedStageId;
        S._selectedStageId = '';
        return prevId;
    }

    // frame 路由（纯状态半）：label 无效（manifest 无此 frame）时拒绝并返回 false。
    // 路由成功的重渲染 / 日志由 renderer 编排。
    function tryRouteFrame(label) {
        if (!StageSelectData.getFrame(label)) return false;
        S._currentFrameLabel = label;
        return true;
    }

    // fixture 装载（纯状态半）：badge DOM 同步由 renderer 编排。
    function setFixture(name) {
        S._fixtureName = name || 'mixed';
        S._fixture = StageSelectData.getFixture(S._fixtureName);
    }

    // runtime snapshot 应用（纯状态半）：全量替换 + 帧标签随动；重渲染 / 日志由 renderer 编排。
    function applySnapshot(snapshot) {
        S._runtimeSnapshot = snapshot || {};
        S._lastError = '';
        if (S._runtimeSnapshot.currentFrameLabel && StageSelectData.getFrame(S._runtimeSnapshot.currentFrameLabel)) {
            S._currentFrameLabel = S._runtimeSnapshot.currentFrameLabel;
        }
        if (S._runtimeSnapshot.returnFrameLabel) {
            S._returnFrameLabel = S._runtimeSnapshot.returnFrameLabel;
        }
    }

    function resolveReturnFrameLabel(nav) {
        if (nav && nav.actionKind === 'flashJumpFrameValue' && nav.targetFrameLabel) {
            return nav.targetFrameLabel;
        }
        return S._returnFrameLabel || S._currentFrameLabel || '';
    }

    function getManifestStageNames() {
        var manifest = StageSelectData.getManifest();
        var lookup = {};
        var names = [];
        (manifest.frames || []).forEach(function(frame) {
            (frame.stageButtons || []).forEach(function(button) {
                var name = button.stageName || '';
                if (!name || lookup[name]) return;
                lookup[name] = true;
                names.push(name);
            });
        });
        return names;
    }

    function countUnlocked(unlockedStages) {
        var count = 0;
        var key;
        for (key in (unlockedStages || {})) {
            if (unlockedStages[key]) count += 1;
        }
        return count;
    }

    // 导出：被 renderer / inspector / bridge / facade 引用的纯数据层 API
    return {
        LIMITATION_DESC: LIMITATION_DESC,
        renderLimitDetail: renderLimitDetail,
        getStageState: getStageState,
        isChallengeMode: isChallengeMode,
        isRuntimeMode: isRuntimeMode,
        getTaskTargets: getTaskTargets,
        formatTaskCount: formatTaskCount,
        findStageButton: findStageButton,
        findStageButtonById: findStageButtonById,
        isDirectEntry: isDirectEntry,
        getStageDisplayName: getStageDisplayName,
        getStageNavPoint: getStageNavPoint,
        computeNavTarget: computeNavTarget,
        computeOpenCardId: computeOpenCardId,
        applySelection: applySelection,
        clearSelectionState: clearSelectionState,
        tryRouteFrame: tryRouteFrame,
        setFixture: setFixture,
        applySnapshot: applySnapshot,
        resolveReturnFrameLabel: resolveReturnFrameLabel,
        getManifestStageNames: getManifestStageNames,
        countUnlocked: countUnlocked
    };
})();
