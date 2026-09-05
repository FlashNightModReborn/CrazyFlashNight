/**
 * stage-select/stage-select-bridge.js — 选关面板 P4-a 工程拆分 · Host bridge 通路。
 *
 * 职责：snapshot / enter / jump_frame / return_frame 四请求的信封装配与发送、pending
 * 表（callId → 回调）、panel_resp 分发与 P3 会话守卫校验（panelInstanceId +
 * sessionGeneration 双字段 strict-when-present、stateRevision 单调水位、
 * catalogVersion 回显核对）、关闭即清 pending（invalidatePendingRequests）、
 * 迟到/跨会话回包拒绝计数。不含 UI；回包落地后的重渲染 / 关闭面板经
 * StageSelectRenderer 编排，状态合并经 StageSelectViewModel。
 *
 * 本文件由 modules/stage-select-panel.js 单文件 IIFE 机械拆分而来（纯移动：行为 / 协议
 * payload / QA 断言不变）。跨模块函数引用解析于调用时。
 * 依赖守卫：stage-select/stage-select-core.js + stage-select-view-model.js。
 * Bridge 全局与原单文件同为加载期假设（overlay boot / harness 均先于本模块提供）。
 */
(function() {
    'use strict';

    if (typeof window === 'undefined' || !window.StageSelectCore) {
        throw new Error('stage-select/stage-select-bridge.js 需要先加载 stage-select/stage-select-core.js（共享基座：状态容器 + 跨模块工具）');
    }
    if (typeof window === 'undefined' || !window.StageSelectViewModel) {
        throw new Error('stage-select/stage-select-bridge.js 需要先加载 stage-select/stage-select-view-model.js（纯数据层 ViewModel）');
    }

    var S = StageSelectCore.state; // 共享状态（原顶层 var _x）

    // ── P3 协议守卫（只加守卫，不改协议语义；AS2 侧零改动）──────────────────
    // 参照 skills/loot 现役模式：panelInstanceId 绑定 Host 权威实例 + sessionGeneration
    // 面板本地会话序号。请求携带二者，C# 代封回显（AS2 不回显请求字段）；回包分发时
    // 校验 instance+session（不止 callId），迟到/跨会话回包拒绝并记 dev log。
    function readInitInstanceId(initData) {
        var value = initData && initData.panelInstanceId;
        return typeof value === 'string' && value ? value : '';
    }

    // 关闭即清 pending 并令在途回包失效：session 自增使任何意外存活的旧回调
    // currentSession !== _session 检查必然失败（pending 清空是第一道，回调不进城）。
    function invalidatePendingRequests(reason) {
        var count = 0;
        var key;
        for (key in S._pendingReq) {
            if (Object.prototype.hasOwnProperty.call(S._pendingReq, key)) count += 1;
        }
        S._pendingReq = {};
        S._session += 1;
        if (count > 0) StageSelectCore.logDev('pending invalidated: ' + count + ' in-flight (' + (reason || 'close') + ')');
    }

    function dropResponse(data, reason) {
        S._droppedRespCount += 1;
        StageSelectCore.logDev('response dropped (' + reason + '): cmd=' + (data && data.cmd || '?')
            + ' callId=' + (data && data.callId || '?'));
    }

    // 双字段 strict-when-present：回包携带该字段就必须匹配；缺失（旧 C# 不回显）则跳过，
    // 保证版本偏斜时退化为 P3 前行为而不是面板锁死。绑定后（_panelInstanceId 非空）
    // 异值一律拒绝。
    function isResponseSessionValid(data) {
        if (S._panelInstanceId && typeof data.panelInstanceId !== 'undefined'
                && data.panelInstanceId !== S._panelInstanceId) {
            dropResponse(data, 'panelInstanceId mismatch, bound=' + S._panelInstanceId);
            return false;
        }
        if (typeof data.sessionGeneration !== 'undefined'
                && Number(data.sessionGeneration) !== S._session) {
            dropResponse(data, 'sessionGeneration mismatch, current=' + S._session);
            return false;
        }
        return true;
    }

    // Bridge.send 的 true 仅代表本地 transport 同步投递；false/throw 都是确定的
    // 本地发送失败。所有带 pending 的请求必须在本调用栈内消费自己的 exact callId，
    // 不能留下一个永远等不到回包的 pending/busy 再伪装成 timeout。
    function tryBridgeSend(message, context) {
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') return false;
        try {
            if (Bridge.send(message) !== false) return true;
            if (window.console && console.error) {
                console.error('[stage-select] ' + context + ' send failed: Bridge.send returned false');
            }
        } catch (error) {
            if (window.console && console.error) {
                console.error('[stage-select] ' + context + ' send failed: Bridge.send threw', error);
            }
        }
        return false;
    }

    function sendPendingRequest(reqId, message, context, onSendFailure) {
        if (tryBridgeSend(message, context)) return true;
        // reqId 单调唯一；仍只消费当前 exact callback，兼容测试 bridge 的同步回包。
        if (Object.prototype.hasOwnProperty.call(S._pendingReq, reqId)) {
            delete S._pendingReq[reqId];
            if (typeof onSendFailure === 'function') onSendFailure();
        }
        return false;
    }

    function requestSnapshot() {
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            StageSelectCore.logDev('snapshot skipped: bridge unavailable');
            return false;
        }
        var manifest = StageSelectData.getManifest();
        var reqId = 'stage-select-snapshot-' + (++S._reqSeq);
        var currentSession = S._session;
        S._pendingReq[reqId] = function(resp) {
            delete S._pendingReq[reqId];
            if (currentSession !== S._session || !Panels.isOpen() || Panels.getActive() !== 'stage-select') return;
            if (!resp.success) {
                StageSelectCore.showError(resp.error || 'snapshot_failed');
                return;
            }
            // P3 stateRevision 单调守卫：乱序/迟到 snapshot 不得覆盖更新状态。
            // 回包未携带（旧 C#）则跳过，退化为 P3 前的后到覆盖行为。
            var revision = typeof resp.stateRevision === 'number' && isFinite(resp.stateRevision)
                ? resp.stateRevision : NaN;
            if (!isNaN(revision)) {
                if (revision <= S._lastAppliedStateRevision) {
                    dropResponse(resp, 'stale stateRevision ' + revision
                        + ' <= applied ' + S._lastAppliedStateRevision);
                    return;
                }
                S._lastAppliedStateRevision = revision;
            }
            // catalogVersion：manifest 版本回显，不一致仅记 dev log（静态打包，实践不可达）。
            if (typeof resp.catalogVersion !== 'undefined'
                    && Number(resp.catalogVersion) !== Number(manifest.version)) {
                StageSelectCore.logDev('catalog version mismatch: manifest=' + manifest.version
                    + ' resp=' + resp.catalogVersion);
            }
            StageSelectCore.clearError();
            StageSelectRenderer.applyRuntimeSnapshot(resp.snapshot || {});
        };
        var snapshotRequest = {
            type: 'panel',
            panel: 'stage-select',
            cmd: 'snapshot',
            callId: reqId,
            panelInstanceId: S._panelInstanceId,
            sessionGeneration: S._session,
            catalogVersion: manifest.version,
            catalogSchema: manifest.schema,
            stageNames: StageSelectViewModel.getManifestStageNames()
        };
        // 非生产目录的 frameLabel 是 Web 内部虚拟页，不得写进 AS2 的
        // Web选关当前帧值/返回帧值。空串也不能发送：AS2 resolver 会把它归一为基地门口，
        // 因此 scoped snapshot 必须完全省略两键；生产目录继续显式携带两键。
        if (S._catalogId === StageSelectData.DEFAULT_CATALOG_ID) {
            snapshotRequest.frameLabel = S._currentFrameLabel;
            snapshotRequest.returnFrameLabel = S._returnFrameLabel;
        }
        return sendPendingRequest(reqId, snapshotRequest, 'snapshot', function() {
            if (currentSession !== S._session) return;
            StageSelectCore.showError('send_failed');
        });
    }

    function requestJumpFrame(frameLabel, nav, sourceFrameLabel) {
        if (!frameLabel) return false;
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            StageSelectCore.showError('bridge_unavailable');
            return false;
        }
        var reqId = 'stage-select-jump-' + (++S._reqSeq);
        var currentSession = S._session;
        S._pendingReq[reqId] = function(resp) {
            delete S._pendingReq[reqId];
            if (currentSession !== S._session || !Panels.isOpen() || Panels.getActive() !== 'stage-select') return;
            if (!resp.success) {
                StageSelectCore.showError(resp.error || 'jump_frame_failed');
                return;
            }
            StageSelectCore.clearError();
            StageSelectCore.logDev('jump frame synced: ' + frameLabel);
        };
        return sendPendingRequest(reqId, {
            type: 'panel',
            panel: 'stage-select',
            cmd: 'jump_frame',
            callId: reqId,
            frameLabel: frameLabel,
            sourceFrameLabel: sourceFrameLabel || '',
            navId: nav && nav.id || '',
            panelInstanceId: S._panelInstanceId,
            sessionGeneration: S._session
        }, 'jump_frame', function() {
            if (currentSession !== S._session) return;
            StageSelectCore.showError('send_failed');
        });
    }

    function requestEnter(stageName, difficulty, entryKind) {
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            StageSelectCore.showError('bridge_unavailable');
            return false;
        }
        var reqId = 'stage-select-enter-' + (++S._reqSeq);
        var currentSession = S._session;
        S._busyStageName = stageName;
        S._lastError = '';
        StageSelectRenderer.renderCurrentFrame();
        S._pendingReq[reqId] = function(resp) {
            delete S._pendingReq[reqId];
            if (currentSession !== S._session) return;
            S._busyStageName = '';
            if (!resp.success) {
                StageSelectCore.showError(resp.error || 'enter_failed');
                StageSelectRenderer.renderCurrentFrame();
                return;
            }
            StageSelectCore.logDev('enter accepted: ' + stageName + ' / ' + difficulty);
            if (resp.closePanel) {
                StageSelectRenderer.requestClose();
                return;
            }
            StageSelectRenderer.renderCurrentFrame();
        };
        return sendPendingRequest(reqId, {
            type: 'panel',
            panel: 'stage-select',
            cmd: 'enter',
            callId: reqId,
            stageName: stageName,
            difficulty: difficulty,
            entryKind: entryKind || 'difficulty',
            panelInstanceId: S._panelInstanceId,
            sessionGeneration: S._session
        }, 'enter', function() {
            if (currentSession !== S._session) return;
            if (S._busyStageName === stageName) S._busyStageName = '';
            StageSelectCore.showError('send_failed');
            if (Panels.isOpen() && Panels.getActive() === 'stage-select') {
                StageSelectRenderer.renderCurrentFrame();
            }
        });
    }

    function requestReturnFrame(frameLabel, nav) {
        var targetFrameLabel = frameLabel || S._returnFrameLabel || S._currentFrameLabel;
        if (!targetFrameLabel) {
            StageSelectCore.showError('invalid_return_frame');
            return false;
        }
        if (typeof Bridge === 'undefined' || !Bridge || typeof Bridge.send !== 'function') {
            StageSelectCore.showError('bridge_unavailable');
            return false;
        }
        var reqId = 'stage-select-return-' + (++S._reqSeq);
        var currentSession = S._session;
        S._pendingReq[reqId] = function(resp) {
            delete S._pendingReq[reqId];
            if (currentSession !== S._session) return;
            if (!resp.success) {
                StageSelectCore.showError(resp.error || 'return_frame_failed');
                return;
            }
            StageSelectCore.clearError();
            StageSelectCore.logDev('return frame synced: ' + (resp.returnFrameLabel || targetFrameLabel));
            if (resp.closePanel) {
                StageSelectRenderer.requestClose();
            }
        };
        return sendPendingRequest(reqId, {
            type: 'panel',
            panel: 'stage-select',
            cmd: 'return_frame',
            callId: reqId,
            frameLabel: targetFrameLabel,
            returnFrameLabel: targetFrameLabel,
            navId: nav && nav.id || '',
            panelInstanceId: S._panelInstanceId,
            sessionGeneration: S._session
        }, 'return_frame', function() {
            if (currentSession !== S._session) return;
            StageSelectCore.showError('send_failed');
        });
    }

    function sendCloseNotification() {
        return tryBridgeSend({ type: 'panel', panel: 'stage-select', cmd: 'close' }, 'close');
    }

    // 导出：被 renderer / inspector / facade 引用的名字
    window.StageSelectBridge = {
        readInitInstanceId: readInitInstanceId,
        invalidatePendingRequests: invalidatePendingRequests,
        dropResponse: dropResponse,
        isResponseSessionValid: isResponseSessionValid,
        requestSnapshot: requestSnapshot,
        requestJumpFrame: requestJumpFrame,
        requestEnter: requestEnter,
        requestReturnFrame: requestReturnFrame,
        sendCloseNotification: sendCloseNotification
    };

    Bridge.on('panel_resp', function(data) {
        if (!data || data.panel !== 'stage-select') return;
        var cb = S._pendingReq[data.callId];
        if (!cb) {
            // 迟到/无主回包：pending 已随关闭清空，或 callId 不属于当前会话。
            dropResponse(data, 'no pending request');
            return;
        }
        if (!isResponseSessionValid(data)) {
            delete S._pendingReq[data.callId];
            return;
        }
        cb(data);
    });
})();
